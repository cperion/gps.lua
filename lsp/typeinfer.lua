-- lsp/typeinfer.lua
--
-- Type inference over Lua AST + doc annotations.
-- All results are TypeExpr ASDL nodes — one type language for everything.
--
-- pvm.lower("typed_index"): File → TypedIndex
--   For each symbol in the file, infers its type from:
--   1. @type/@param/@return annotations on the enclosing Item
--   2. Literal initializers (local x = 42 → TNumber)
--   3. Table constructors (local t = {a=1,b="x"} → TTable)
--   4. Function definitions (function(a,b) → TFunc)
--   5. @class fields
--
-- pvm.lower("expr_type"): ExprTypeQuery → TypeExpr
--   Given (file, anchor_of_expr), returns the inferred type.

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.new(semantics_engine)
    local C = semantics_engine.C

    -- ── Helpers ────────────────────────────────────────────

    local function type_of_literal(expr)
        local k = expr.kind
        if k == "Nil"    then return C.TNil() end
        if k == "True"   then return C.TBoolean() end
        if k == "False"  then return C.TBoolean() end
        if k == "Number" then return C.TNumber() end
        if k == "String" then return C.TString() end
        if k == "Vararg" then return C.TAny() end
        return nil
    end

    local function type_of_table_ctor(expr)
        if expr.kind ~= "TableCtor" then return nil end
        local fields = expr.fields
        if #fields == 0 then return C.TTable({}, true) end

        -- Check if it's a sequence (array-like)
        local all_array = true
        local type_fields = {}
        for i = 1, #fields do
            local f = fields[i]
            if f.kind == "NameField" then
                all_array = false
                local vt = type_of_literal(f.value) or C.TAny()
                type_fields[#type_fields + 1] = C.TypeField(f.key, vt, false)
            elseif f.kind == "PairField" then
                all_array = false
            end
        end

        if all_array and #fields > 0 then
            -- Array-like: infer element type from first value
            local first = fields[1]
            if first.kind == "ArrayField" then
                local et = type_of_literal(first.value) or C.TAny()
                return C.TArray(et)
            end
        end

        if #type_fields > 0 then
            return C.TTable(type_fields, true)
        end

        return C.TTable({}, true)
    end

    local function type_of_funcbody(body)
        -- Build param types (unknown by default, can be enriched by @param)
        local params = {}
        for i = 1, #body.params do
            params[i] = C.TAny()
        end
        -- Return type unknown
        return C.TFunc(C.FuncType(params, { C.TAny() }, body.vararg))
    end

    local function type_of_expr(expr)
        if not expr then return C.TUnknown() end
        local lit = type_of_literal(expr)
        if lit then return lit end

        local k = expr.kind
        if k == "TableCtor" then
            return type_of_table_ctor(expr) or C.TTable({}, true)
        end
        if k == "FunctionExpr" then
            return type_of_funcbody(expr.body)
        end
        if k == "Unary" then
            if expr.op == "#" then return C.TNumber() end
            if expr.op == "-" then return C.TNumber() end
            if expr.op == "not" then return C.TBoolean() end
            return C.TAny()
        end
        if k == "Binary" then
            if expr.op == ".." then return C.TString() end
            if expr.op == "+" or expr.op == "-" or expr.op == "*" or expr.op == "/"
                or expr.op == "%" or expr.op == "^" or expr.op == "//" then
                return C.TNumber()
            end
            if expr.op == "==" or expr.op == "~=" or expr.op == "<" or expr.op == ">"
                or expr.op == "<=" or expr.op == ">=" or expr.op == "and" or expr.op == "or" then
                return C.TBoolean()
            end
            return C.TAny()
        end
        if k == "Paren" then
            return type_of_expr(expr.inner)
        end
        return C.TUnknown()
    end

    -- Extract @type/@param/@return from doc blocks attached to an Item
    local function doc_type_for_name(item, name)
        for d = 1, #item.docs do
            local tags = item.docs[d].tags
            for t = 1, #tags do
                local tag = tags[t]
                if tag.kind == "TypeTag" then
                    return tag.typ
                end
                if tag.kind == "ParamTag" and tag.name == name then
                    return tag.typ
                end
            end
        end
        return nil
    end

    local function doc_return_type(item)
        for d = 1, #item.docs do
            local tags = item.docs[d].tags
            for t = 1, #tags do
                if tags[t].kind == "ReturnTag" and #tags[t].values > 0 then
                    if #tags[t].values == 1 then
                        return tags[t].values[1]
                    end
                    return C.TTuple(tags[t].values)
                end
            end
        end
        return nil
    end

    local function doc_param_types(item)
        local out = {}
        for d = 1, #item.docs do
            local tags = item.docs[d].tags
            for t = 1, #tags do
                if tags[t].kind == "ParamTag" then
                    out[tags[t].name] = tags[t].typ
                end
            end
        end
        return out
    end

    -- ── typed_index lower ──────────────────────────────────
    -- For each symbol, infer its type from context.

    local typed_index = pvm.lower("typed_index", function(file)
        local idx = semantics_engine:index(file)
        local env = semantics_engine.resolve_named_types(file)
        local typed = {}

        -- Build declaration maps keyed by anchor id.
        local sym_item = {}          -- anchor_id -> Item
        local param_anchor_type = {} -- anchor_id -> TypeExpr
        local class_member_type = {} -- class_name -> field/method_name -> TypeExpr

        local function put_class_member(class_name, member, typ)
            if not class_name or class_name == "" or not member or member == "" or not typ then return end
            local tbl = class_member_type[class_name]
            if not tbl then tbl = {}; class_member_type[class_name] = tbl end
            if not tbl[member] or tbl[member].kind == "TUnknown" or tbl[member].kind == "TAny" then
                tbl[member] = typ
            end
        end

        local function terminal_name_from_expr(e)
            if not e or type(e) ~= "table" then return nil end
            if e.kind == "NameRef" then return e.name end
            if e.kind == "Field" then return e.key end
            return nil
        end

        local function bind_function_params(item, body)
            local ptypes = doc_param_types(item)
            for pi = 1, #body.params do
                local p = body.params[pi]
                local pid = tostring(p)
                param_anchor_type[pid] = ptypes[p.name] or C.TAny()
            end
        end

        local function func_type_from_item_stmt(item, stmt)
            local body = stmt.body
            local param_types = doc_param_types(item)
            local ret_type = doc_return_type(item)
            local params = {}
            for p = 1, #body.params do
                local pname = body.params[p].name
                params[p] = param_types[pname] or C.TAny()
            end
            local returns = ret_type and { ret_type } or { C.TAny() }
            return C.TFunc(C.FuncType(params, returns, body.vararg))
        end

        for i = 1, #file.items do
            local item = file.items[i]
            local stmt = item.stmt
            local sk = stmt.kind

            if sk == "LocalAssign" then
                for j = 1, #stmt.names do
                    sym_item[tostring(stmt.names[j])] = item
                    local v = stmt.values[j]
                    if v and v.kind == "FunctionExpr" and v.body then
                        bind_function_params(item, v.body)
                    end
                end
            elseif sk == "LocalFunction" then
                sym_item[tostring(stmt)] = item
                bind_function_params(item, stmt.body)
            elseif sk == "Function" then
                if stmt.name then sym_item[tostring(stmt.name)] = item end
                bind_function_params(item, stmt.body)

                if stmt.name and (stmt.name.kind == "LMethod" or stmt.name.kind == "LField") then
                    local class_name = terminal_name_from_expr(stmt.name.base)
                    local member = (stmt.name.kind == "LMethod") and stmt.name.method or stmt.name.key
                    put_class_member(class_name, member, func_type_from_item_stmt(item, stmt))
                end
            end
        end

        local inferred_by_name = {}

        local function remember(sym, typ)
            if not sym or not typ then return end
            if typ.kind == "TUnknown" then return end
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
            return C.TUnknown()
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

            for j = 1, #c.fields do
                if c.fields[j].name == field then return c.fields[j].typ end
            end

            for j = 1, #c.extends do
                local ex = c.extends[j]
                if ex and ex.kind == "TNamed" and ex.name then
                    local from_parent = class_field_type(ex.name, field, seen_classes)
                    if from_parent then return from_parent end
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

        local function infer_from_expr(expr)
            if not expr then return C.TUnknown() end
            local t = type_of_expr(expr)
            if t.kind ~= "TUnknown" then return t end

            if expr.kind == "NameRef" then
                return lookup_name_type(expr.name)
            end

            if expr.kind == "Field" and expr.base and expr.key then
                local bt = infer_from_expr(expr.base)
                local ft = resolve_named_field_type(bt, expr.key)
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
                -- fallback: method symbol by name in local scope
                local fn = lookup_name_type(expr.method)
                if fn.kind == "TFunc" and fn.sig and #fn.sig.returns > 0 then
                    return fn.sig.returns[1]
                end
            end

            return C.TUnknown()
        end

        for i = 1, #idx.symbols do
            local sym = idx.symbols[i]
            local typ = C.TUnknown()
            local aid = sym.decl_anchor and sym.decl_anchor.id or ""

            if sym.kind == C.SymParam and param_anchor_type[aid] then
                typ = param_anchor_type[aid]
            end

            local item = sym_item[aid]
            if item then
                local doc_t = doc_type_for_name(item, sym.name)
                if doc_t then
                    typ = doc_t
                else
                    local stmt = item.stmt
                    if stmt.kind == "LocalAssign" then
                        for j = 1, #stmt.names do
                            if tostring(stmt.names[j]) == aid then
                                if stmt.values[j] then
                                    typ = infer_from_expr(stmt.values[j])
                                end
                                break
                            end
                        end
                    elseif stmt.kind == "LocalFunction" or stmt.kind == "Function" then
                        local body = stmt.body
                        local param_types = doc_param_types(item)
                        local ret_type = doc_return_type(item)
                        local params = {}
                        for p = 1, #body.params do
                            local pname = body.params[p].name
                            params[p] = param_types[pname] or C.TAny()
                        end
                        local returns = ret_type and { ret_type } or { C.TAny() }
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

    -- ── Public type lookup ─────────────────────────────────

    local function type_for_symbol(file, symbol_id)
        local ti = typed_index(file)
        for i = 1, #ti.symbols do
            if ti.symbols[i].symbol.id == symbol_id then
                return ti.symbols[i].typ
            end
        end
        return C.TUnknown()
    end

    local function type_for_anchor(file, anchor)
        local binding = semantics_engine:symbol_for_anchor(file, anchor)
        if binding.kind == "AnchorSymbol" then
            return type_for_symbol(file, binding.symbol.id)
        end
        return C.TUnknown()
    end

    -- ── Type → string ──────────────────────────────────────

    local function type_to_string(t)
        if not t then return "unknown" end
        local k = t.kind
        if k == "TAny"     then return "any" end
        if k == "TUnknown" then return "unknown" end
        if k == "TNil"     then return "nil" end
        if k == "TBoolean" then return "boolean" end
        if k == "TNumber"  then return "number" end
        if k == "TString"  then return "string" end
        if k == "TNamed"   then return t.name end
        if k == "TLiteralString" then return '"' .. t.value .. '"' end
        if k == "TLiteralNumber" then return t.value end
        if k == "TArray"   then return type_to_string(t.item) .. "[]" end
        if k == "TOptional" then return type_to_string(t.inner) .. "?" end
        if k == "TUnion" then
            local parts = {}
            for i = 1, #t.parts do parts[i] = type_to_string(t.parts[i]) end
            return table.concat(parts, "|")
        end
        if k == "TFunc" then
            local sig = t.sig
            local params = {}
            for i = 1, #sig.params do params[i] = type_to_string(sig.params[i]) end
            local rets = {}
            for i = 1, #sig.returns do rets[i] = type_to_string(sig.returns[i]) end
            return "fun(" .. table.concat(params, ", ") .. "): " .. table.concat(rets, ", ")
        end
        if k == "TTable" then
            if #t.fields == 0 then return "table" end
            local fs = {}
            for i = 1, #t.fields do
                fs[i] = t.fields[i].name .. ": " .. type_to_string(t.fields[i].typ)
            end
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
        typed_index = typed_index,
        type_for_symbol = type_for_symbol,
        type_for_anchor = type_for_anchor,
        type_of_expr = type_of_expr,
        type_to_string = type_to_string,
        C = C,
    }
end

return M
