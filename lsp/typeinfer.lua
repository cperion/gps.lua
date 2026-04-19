-- lsp/typeinfer.lua
--
-- Type inference over ParsedDoc + semantic assemblies.
--
-- Cached boundaries:
--   ParsedDoc:typed_index() -> TypedIndex
--   ExprTypeQuery:expr_type() -> ExprTypeResult

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.new(semantics_engine)
    local C = semantics_engine.C

    -- ── Basic literal / local shape inference ───────────────────────

    local function type_of_literal(expr)
        local k = expr.kind
        if k == "Nil"    then return C.TNil end
        if k == "True"   then return C.TBoolean end
        if k == "False"  then return C.TBoolean end
        if k == "Number" then return C.TNumber end
        if k == "String" then return C.TString end
        if k == "Vararg" then return C.TAny end
        return nil
    end

    local function type_of_table_ctor(expr)
        if expr.kind ~= "TableCtor" then return nil end
        local fields = expr.fields
        if #fields == 0 then return C.TTable({}, true) end

        local all_array = true
        local type_fields = {}
        for i = 1, #fields do
            local f = fields[i]
            if f.kind == "NameField" then
                all_array = false
                local vt = type_of_literal(f.value) or C.TAny
                type_fields[#type_fields + 1] = C.TypeField(f.key, vt, false)
            elseif f.kind == "PairField" then
                all_array = false
            end
        end

        if all_array and #fields > 0 and fields[1].kind == "ArrayField" then
            return C.TArray(type_of_literal(fields[1].value) or C.TAny)
        end

        if #type_fields > 0 then
            return C.TTable(type_fields, true)
        end

        return C.TTable({}, true)
    end

    local function type_of_funcbody(body)
        local params = {}
        for i = 1, #body.params do params[i] = C.TAny end
        return C.TFunc(C.FuncType(params, { C.TAny }, body.vararg))
    end

    local function type_of_expr_shape(expr)
        if not expr then return C.TUnknown end
        local lit = type_of_literal(expr)
        if lit then return lit end

        local k = expr.kind
        if k == "TableCtor" then return type_of_table_ctor(expr) or C.TTable({}, true) end
        if k == "FunctionExpr" then return type_of_funcbody(expr.body) end
        if k == "Unary" then
            if expr.op == "#" or expr.op == "-" then return C.TNumber end
            if expr.op == "not" then return C.TBoolean end
            return C.TAny
        end
        if k == "Binary" then
            if expr.op == ".." then return C.TString end
            if expr.op == "+" or expr.op == "-" or expr.op == "*" or expr.op == "/"
                or expr.op == "%" or expr.op == "^" or expr.op == "//" then
                return C.TNumber
            end
            if expr.op == "==" or expr.op == "~=" or expr.op == "<" or expr.op == ">"
                or expr.op == "<=" or expr.op == ">=" or expr.op == "and" or expr.op == "or" then
                return C.TBoolean
            end
            return C.TAny
        end
        if k == "Paren" then return type_of_expr_shape(expr.inner) end
        return C.TUnknown
    end

    -- ── Documentation-derived hints ────────────────────────────────

    local function item_hint_summary(item)
        local out = {
            type_tag = nil,
            param_types = {},
            return_type = nil,
        }

        local function add_return_values(values)
            if not values or #values == 0 then return end
            if #values == 1 then out.return_type = values[1]
            else out.return_type = C.TTuple(values) end
        end

        local docs = item.docs or {}
        for i = 1, #docs do
            for _, h in semantics_engine.doc_hints_phase(docs[i]) do
                if h.kind == "HintType" then
                    out.type_tag = h.typ
                elseif h.kind == "HintParam" then
                    out.param_types[h.name] = h.typ
                elseif h.kind == "HintReturn" then
                    add_return_values(h.values)
                end
            end
        end

        return out
    end

    local function terminal_name_from_expr(e)
        if not e or type(e) ~= "table" then return nil end
        if e.kind == "NameRef" then return e.name end
        if e.kind == "Field" then return e.key end
        return nil
    end

    local function analyze_file_items(file)
        local sym_item = {}          -- decl anchor id -> Item
        local param_anchor_type = {} -- param anchor id -> TypeExpr
        local class_member_type = {} -- class_name -> member -> TypeExpr

        local function put_class_member(class_name, member, typ)
            if not class_name or class_name == "" or not member or member == "" or not typ then return end
            local tbl = class_member_type[class_name]
            if not tbl then tbl = {}; class_member_type[class_name] = tbl end
            if not tbl[member] or tbl[member].kind == "TUnknown" or tbl[member].kind == "TAny" then
                tbl[member] = typ
            end
        end

        local function func_type_from_item_stmt(item, stmt)
            local hints = item_hint_summary(item)
            local body = stmt.body
            local params = {}
            for i = 1, #body.params do
                local pname = body.params[i].name
                params[i] = hints.param_types[pname] or C.TAny
            end
            local returns = hints.return_type and { hints.return_type } or { C.TAny }
            return C.TFunc(C.FuncType(params, returns, body.vararg))
        end

        for i = 1, #file.items do
            local item = file.items[i].core
            local stmt = item.stmt
            local sk = stmt.kind
            local hints = item_hint_summary(item)

            local function bind_params(body)
                for pi = 1, #body.params do
                    local p = body.params[pi]
                    param_anchor_type[tostring(p)] = hints.param_types[p.name] or C.TAny
                end
            end

            if sk == "LocalAssign" then
                for j = 1, #stmt.names do
                    sym_item[tostring(stmt.names[j])] = item
                    local v = stmt.values[j]
                    if v and v.kind == "FunctionExpr" and v.body then
                        bind_params(v.body)
                    end
                end
            elseif sk == "LocalFunction" then
                sym_item[tostring(stmt)] = item
                bind_params(stmt.body)
            elseif sk == "Function" then
                if stmt.name then sym_item[tostring(stmt.name)] = item end
                bind_params(stmt.body)

                if stmt.name and (stmt.name.kind == "LMethod" or stmt.name.kind == "LField") then
                    local class_name = terminal_name_from_expr(stmt.name.base)
                    local member = (stmt.name.kind == "LMethod") and stmt.name.method or stmt.name.key
                    put_class_member(class_name, member, func_type_from_item_stmt(item, stmt))
                end
            end
        end

        return sym_item, param_anchor_type, class_member_type
    end

    local function named_from_type(t, out, seen)
        if not t or type(t) ~= "table" then return end
        local k = t.kind
        if k == "TNamed" then
            local n = t.name
            if n and n ~= "" and not seen[n] then
                seen[n] = true
                out[#out + 1] = n
            end
            return
        end
        if k == "TOptional" then return named_from_type(t.inner, out, seen) end
        if k == "TArray" then return named_from_type(t.item, out, seen) end
        if k == "TMap" then
            named_from_type(t.key, out, seen)
            named_from_type(t.value, out, seen)
            return
        end
        if k == "TTuple" then
            for i = 1, #t.items do named_from_type(t.items[i], out, seen) end
            return
        end
        if k == "TUnion" then
            for i = 1, #t.parts do named_from_type(t.parts[i], out, seen) end
            return
        end
        if k == "TTable" then
            for i = 1, #t.fields do named_from_type(t.fields[i].typ, out, seen) end
            return
        end
        if k == "TFunc" and t.sig then
            for i = 1, #t.sig.params do named_from_type(t.sig.params[i], out, seen) end
            for i = 1, #t.sig.returns do named_from_type(t.sig.returns[i], out, seen) end
            return
        end
    end

    local function make_resolvers(env, class_member_type)
        local function alias_target(name)
            for i = 1, #env.aliases do
                local a = env.aliases[i]
                if a.name == name then return a.typ end
            end
            return nil
        end

        local function class_node(name)
            for i = 1, #env.classes do
                if env.classes[i].name == name then return env.classes[i] end
            end
            return nil
        end

        local function class_field_type(class_name, field, seen_classes)
            seen_classes = seen_classes or {}
            if seen_classes[class_name] then return nil end
            seen_classes[class_name] = true

            local mem = class_member_type[class_name]
            if mem and mem[field] then return mem[field] end

            local c = class_node(class_name)
            if not c then return nil end

            for i = 1, #c.fields do
                if c.fields[i].name == field then return c.fields[i].typ end
            end

            for i = 1, #c.extends do
                local ex = c.extends[i]
                if ex and ex.kind == "TNamed" and ex.name then
                    local parent = class_field_type(ex.name, field, seen_classes)
                    if parent then return parent end
                end
            end

            return nil
        end

        local function resolve_named_field_type(t, field)
            local names = {}
            named_from_type(t, names, {})
            local queue = {}
            for i = 1, #names do queue[#queue + 1] = names[i] end
            local seen_names = {}
            local qi = 1
            while qi <= #queue and qi <= 48 do
                local nm = queue[qi]; qi = qi + 1
                if not seen_names[nm] then
                    seen_names[nm] = true
                    local ft = class_field_type(nm, field)
                    if ft then return ft end
                    local at = alias_target(nm)
                    if at then
                        local extra = {}
                        named_from_type(at, extra, {})
                        for i = 1, #extra do queue[#queue + 1] = extra[i] end
                    end
                end
            end
            return nil
        end

        return resolve_named_field_type
    end

    local function find_expr_by_anchor(doc, anchor)
        local aid = anchor and anchor.id or nil
        if not aid or aid == "" then return nil end

        local function is_target(node)
            return node and tostring(node) == aid
        end

        local visit_expr, visit_stmt, visit_block, visit_item, visit_lvalue, visit_field, visit_funcbody

        visit_lvalue = function(node)
            if not node then return nil end
            if node.kind == "LField" then return visit_expr(node.base) end
            if node.kind == "LIndex" then return visit_expr(node.base) or visit_expr(node.key) end
            if node.kind == "LMethod" then return visit_expr(node.base) end
            return nil
        end

        visit_field = function(node)
            if not node then return nil end
            if is_target(node) and (node.kind == "ArrayField" or node.kind == "PairField" or node.kind == "NameField") then
                return nil
            end
            if node.kind == "ArrayField" then return visit_expr(node.value) end
            if node.kind == "PairField" then return visit_expr(node.key) or visit_expr(node.value) end
            if node.kind == "NameField" then return visit_expr(node.value) end
            return nil
        end

        visit_funcbody = function(node)
            if not node then return nil end
            return visit_block(node.body)
        end

        visit_expr = function(node)
            if not node then return nil end
            if is_target(node) then return node end
            local k = node.kind
            if k == "Field" then return visit_expr(node.base) end
            if k == "Index" then return visit_expr(node.base) or visit_expr(node.key) end
            if k == "Call" then
                local hit = visit_expr(node.callee)
                if hit then return hit end
                for i = 1, #node.args do hit = visit_expr(node.args[i]); if hit then return hit end end
            elseif k == "MethodCall" then
                local hit = visit_expr(node.recv)
                if hit then return hit end
                for i = 1, #node.args do hit = visit_expr(node.args[i]); if hit then return hit end end
            elseif k == "FunctionExpr" then
                return visit_funcbody(node.body)
            elseif k == "TableCtor" then
                for i = 1, #node.fields do
                    local hit = visit_field(node.fields[i])
                    if hit then return hit end
                end
            elseif k == "Unary" then
                return visit_expr(node.value)
            elseif k == "Binary" then
                return visit_expr(node.lhs) or visit_expr(node.rhs)
            elseif k == "Paren" then
                return visit_expr(node.inner)
            end
            return nil
        end

        visit_stmt = function(node)
            if not node then return nil end
            local k = node.kind
            if k == "LocalAssign" then
                for i = 1, #node.values do
                    local hit = visit_expr(node.values[i])
                    if hit then return hit end
                end
            elseif k == "Assign" then
                for i = 1, #node.lhs do
                    local hit = visit_lvalue(node.lhs[i])
                    if hit then return hit end
                end
                for i = 1, #node.rhs do
                    local hit = visit_expr(node.rhs[i])
                    if hit then return hit end
                end
            elseif k == "LocalFunction" then
                return visit_funcbody(node.body)
            elseif k == "Function" then
                return visit_lvalue(node.name) or visit_funcbody(node.body)
            elseif k == "Return" then
                for i = 1, #node.values do
                    local hit = visit_expr(node.values[i])
                    if hit then return hit end
                end
            elseif k == "CallStmt" then
                local hit = visit_expr(node.callee)
                if hit then return hit end
                for i = 1, #node.args do hit = visit_expr(node.args[i]); if hit then return hit end end
            elseif k == "If" then
                for i = 1, #node.arms do
                    local arm = node.arms[i]
                    local hit = visit_expr(arm.cond) or visit_block(arm.body)
                    if hit then return hit end
                end
                return visit_block(node.else_block)
            elseif k == "While" then
                return visit_expr(node.cond) or visit_block(node.body)
            elseif k == "Repeat" then
                return visit_block(node.body) or visit_expr(node.cond)
            elseif k == "ForNum" then
                return visit_expr(node.init) or visit_expr(node.limit) or visit_expr(node.step) or visit_block(node.body)
            elseif k == "ForIn" then
                for i = 1, #node.iter do
                    local hit = visit_expr(node.iter[i])
                    if hit then return hit end
                end
                return visit_block(node.body)
            elseif k == "Do" then
                return visit_block(node.body)
            end
            return nil
        end

        visit_item = function(item)
            return visit_stmt(item.stmt)
        end

        local function visit_located_item(item)
            return visit_item(item.core)
        end

        visit_block = function(block)
            if not block then return nil end
            for i = 1, #block.items do
                local hit = visit_item(block.items[i])
                if hit then return hit end
            end
            return nil
        end

        for i = 1, #doc.items do
            local hit = visit_located_item(doc.items[i])
            if hit then return hit end
        end
        return nil
    end

    -- ── ParsedDoc -> TypedIndex ────────────────────────────

    local typed_index = pvm.phase("typed_index", function(file)
        local idx = semantics_engine:index(file)
        local env = semantics_engine:type_env(file)
        local typed = {}
        local sym_item, param_anchor_type, class_member_type = analyze_file_items(file)
        local resolve_named_field_type = make_resolvers(env, class_member_type)

        local inferred_by_name = {}

        local function remember(sym, typ)
            if not sym or not typ or typ.kind == "TUnknown" then return end
            local cur = inferred_by_name[sym.name]
            if not cur or cur.kind == "TUnknown" or cur.kind == "TAny" then
                inferred_by_name[sym.name] = typ
            end
        end

        local function lookup_name_type(name)
            local t = inferred_by_name[name]
            if t then return t end
            for i = 1, #typed do
                local ts = typed[i]
                if ts.symbol.name == name and ts.typ.kind ~= "TUnknown" then
                    return ts.typ
                end
            end
            return C.TUnknown
        end

        local function infer_from_expr(expr)
            if not expr then return C.TUnknown end
            local t = type_of_expr_shape(expr)
            if t.kind ~= "TUnknown" then return t end

            if expr.kind == "NameRef" then
                return lookup_name_type(expr.name)
            end

            if expr.kind == "Field" and expr.base and expr.key then
                local ft = resolve_named_field_type(infer_from_expr(expr.base), expr.key)
                if ft then return ft end
            end

            if expr.kind == "Call" then
                local ct = infer_from_expr(expr.callee)
                if ct.kind == "TFunc" and ct.sig and #ct.sig.returns > 0 then
                    return ct.sig.returns[1]
                end
            end

            if expr.kind == "MethodCall" and expr.recv and expr.method then
                local mt = resolve_named_field_type(infer_from_expr(expr.recv), expr.method)
                if mt and mt.kind == "TFunc" and mt.sig and #mt.sig.returns > 0 then
                    return mt.sig.returns[1]
                end
                local fn = lookup_name_type(expr.method)
                if fn.kind == "TFunc" and fn.sig and #fn.sig.returns > 0 then
                    return fn.sig.returns[1]
                end
            end

            return C.TUnknown
        end

        for i = 1, #idx.symbols do
            local sym = idx.symbols[i]
            local typ = C.TUnknown
            local aid = sym.decl_anchor and sym.decl_anchor.id or ""

            if sym.kind == C.SymParam and param_anchor_type[aid] then
                typ = param_anchor_type[aid]
            end

            local item = sym_item[aid]
            if item then
                local hints = item_hint_summary(item)
                if hints.type_tag then
                    typ = hints.type_tag
                else
                    local stmt = item.stmt
                    if stmt.kind == "LocalAssign" then
                        for j = 1, #stmt.names do
                            if tostring(stmt.names[j]) == aid then
                                if stmt.values[j] then typ = infer_from_expr(stmt.values[j]) end
                                break
                            end
                        end
                    elseif stmt.kind == "LocalFunction" or stmt.kind == "Function" then
                        local body = stmt.body
                        local params = {}
                        for p = 1, #body.params do
                            local pname = body.params[p].name
                            params[p] = hints.param_types[pname] or C.TAny
                        end
                        local returns = hints.return_type and { hints.return_type } or { C.TAny }
                        typ = C.TFunc(C.FuncType(params, returns, body.vararg))
                    end
                end
            end

            if typ.kind == "TUnknown" or typ.kind == "TAny" then
                for ci = 1, #env.classes do
                    if env.classes[ci].name == sym.name then
                        typ = C.TNamed(sym.name)
                        break
                    end
                end
            end

            typed[#typed + 1] = C.TypedSymbol(sym, typ)
            remember(sym, typ)
        end

        return C.TypedIndex(typed)
    end)

    -- ── ExprTypeQuery -> ExprTypeResult ────────────────────

    local expr_type = pvm.phase("expr_type", function(q)
        local binding = pvm.one(semantics_engine:symbol_for_anchor(q.doc, q.anchor))
        if binding.kind == "AnchorSymbol" then
            local ti = pvm.one(typed_index(q.doc))
            for i = 1, #ti.symbols do
                if ti.symbols[i].symbol.id == binding.symbol.id then
                    return C.ExprTypeHit(ti.symbols[i].typ)
                end
            end
            return C.ExprTypeMiss
        end

        local env = semantics_engine:type_env(q.doc)
        local _, _, class_member_type = analyze_file_items(q.doc)
        local resolve_named_field_type = make_resolvers(env, class_member_type)
        local ti = pvm.one(typed_index(q.doc))

        local function lookup_name_type(name)
            for i = 1, #ti.symbols do
                local ts = ti.symbols[i]
                if ts.symbol.name == name and ts.typ.kind ~= "TUnknown" then
                    return ts.typ
                end
            end
            return C.TUnknown
        end

        local function infer_from_expr(expr)
            if not expr then return C.TUnknown end
            local t = type_of_expr_shape(expr)
            if t.kind ~= "TUnknown" then return t end
            if expr.kind == "NameRef" then return lookup_name_type(expr.name) end
            if expr.kind == "Field" and expr.base and expr.key then
                local ft = resolve_named_field_type(infer_from_expr(expr.base), expr.key)
                if ft then return ft end
            end
            if expr.kind == "Call" then
                local ct = infer_from_expr(expr.callee)
                if ct.kind == "TFunc" and ct.sig and #ct.sig.returns > 0 then return ct.sig.returns[1] end
            end
            if expr.kind == "MethodCall" and expr.recv and expr.method then
                local mt = resolve_named_field_type(infer_from_expr(expr.recv), expr.method)
                if mt and mt.kind == "TFunc" and mt.sig and #mt.sig.returns > 0 then return mt.sig.returns[1] end
            end
            return C.TUnknown
        end

        local expr = find_expr_by_anchor(q.doc, q.anchor)
        if not expr then return C.ExprTypeMiss end
        return C.ExprTypeHit(infer_from_expr(expr))
    end)

    -- ── Public helpers ─────────────────────────────────────

    local function type_for_symbol(file, symbol_id)
        local ti = pvm.one(typed_index(file))
        for i = 1, #ti.symbols do
            if ti.symbols[i].symbol.id == symbol_id then
                return ti.symbols[i].typ
            end
        end
        return C.TUnknown
    end

    local function type_for_anchor(file, anchor)
        local binding = pvm.one(semantics_engine:symbol_for_anchor(file, anchor))
        if binding.kind == "AnchorSymbol" then
            return type_for_symbol(file, binding.symbol.id)
        end
        local r = pvm.one(expr_type(C.ExprTypeQuery(file, anchor)))
        if r.kind == "ExprTypeHit" then return r.typ end
        return C.TUnknown
    end

    local function type_to_string(t)
        if not t then return "unknown" end
        local k = t.kind
        if k == "TAny" then return "any" end
        if k == "TUnknown" then return "unknown" end
        if k == "TNil" then return "nil" end
        if k == "TBoolean" then return "boolean" end
        if k == "TNumber" then return "number" end
        if k == "TString" then return "string" end
        if k == "TNamed" then return t.name end
        if k == "TLiteralString" then return '"' .. t.value .. '"' end
        if k == "TLiteralNumber" then return t.value end
        if k == "TArray" then return type_to_string(t.item) .. "[]" end
        if k == "TOptional" then return type_to_string(t.inner) .. "?" end
        if k == "TUnion" then
            local parts = {}
            for i = 1, #t.parts do parts[i] = type_to_string(t.parts[i]) end
            return table.concat(parts, "|")
        end
        if k == "TFunc" then
            local sig = t.sig
            local params, rets = {}, {}
            for i = 1, #sig.params do params[i] = type_to_string(sig.params[i]) end
            for i = 1, #sig.returns do rets[i] = type_to_string(sig.returns[i]) end
            return "fun(" .. table.concat(params, ", ") .. "): " .. table.concat(rets, ", ")
        end
        if k == "TTable" then
            if #t.fields == 0 then return "table" end
            local fs = {}
            for i = 1, #t.fields do fs[i] = t.fields[i].name .. ": " .. type_to_string(t.fields[i].typ) end
            return "{ " .. table.concat(fs, ", ") .. " }"
        end
        if k == "TMap" then
            return "{ [" .. type_to_string(t.key) .. "]: " .. type_to_string(t.value) .. " }"
        end
        if k == "TTuple" then
            local parts = {}
            for i = 1, #t.items do parts[i] = type_to_string(t.items[i]) end
            return table.concat(parts, ", ")
        end
        return k
    end

    return {
        typed_index_phase = typed_index,
        expr_type_phase = expr_type,
        typed_index = typed_index,
        expr_type = expr_type,
        type_for_symbol = type_for_symbol,
        type_for_anchor = type_for_anchor,
        type_of_expr = type_of_expr_shape,
        type_to_string = type_to_string,
        C = C,
    }
end

return M
