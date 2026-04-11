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

        -- Build a map: symbol_id → Item (for doc extraction)
        -- We walk the file items and match declarations
        local sym_item = {}  -- anchor_id → Item
        for i = 1, #file.items do
            local item = file.items[i]
            local stmt = item.stmt
            local sk = stmt.kind

            if sk == "LocalAssign" then
                for j = 1, #stmt.names do
                    sym_item[tostring(stmt.names[j])] = item
                end
            elseif sk == "LocalFunction" then
                sym_item[tostring(stmt)] = item
            elseif sk == "Function" then
                if stmt.name then sym_item[tostring(stmt.name)] = item end
            end
        end

        for i = 1, #idx.symbols do
            local sym = idx.symbols[i]
            local typ = C.TUnknown()

            -- Try annotation first
            local item = sym_item[sym.decl_anchor and sym.decl_anchor.id or ""]
            if item then
                local doc_t = doc_type_for_name(item, sym.name)
                if doc_t then
                    typ = doc_t
                else
                    -- Infer from initializer
                    local stmt = item.stmt
                    if stmt.kind == "LocalAssign" then
                        -- Find which name index this symbol is
                        for j = 1, #stmt.names do
                            if tostring(stmt.names[j]) == (sym.decl_anchor and sym.decl_anchor.id or "") then
                                if stmt.values[j] then
                                    typ = type_of_expr(stmt.values[j])
                                end
                                break
                            end
                        end
                    elseif stmt.kind == "LocalFunction" or stmt.kind == "Function" then
                        local body = stmt.body
                        -- Check for @param/@return
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

            -- Check if it's a class
            if typ.kind == "TUnknown" or typ.kind == "TAny" then
                for ci = 1, #env.classes do
                    if env.classes[ci].name == sym.name then
                        typ = C.TNamed(sym.name)
                        break
                    end
                end
            end

            typed[#typed + 1] = C.TypedSymbol(sym, typ)
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
