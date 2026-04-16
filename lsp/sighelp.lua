-- lsp/sighelp.lua
--
-- Signature catalog + lookup.
-- pvm.phase("signature_catalog"): File -> SignatureCatalog
-- pvm.phase("signature_lookup"): SignatureLookupQuery -> SignatureHelp

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.new(semantics_engine, type_engine)
    local C = semantics_engine.C

    local function type_to_string(t)
        if type_engine and type_engine.type_to_string then
            return type_engine.type_to_string(t)
        end
        return (t and t.kind and tostring(t.kind):gsub("^T", ""):lower()) or "any"
    end

    local function docs_param_types(item)
        local map = {}
        for di = 1, #(item.docs or {}) do
            local tags = item.docs[di].tags
            for ti = 1, #tags do
                local tag = tags[ti]
                if tag.kind == "ParamTag" then
                    map[tag.name] = type_to_string(tag.typ)
                end
            end
        end
        return map
    end

    local function docs_return(item)
        for di = 1, #(item.docs or {}) do
            local tags = item.docs[di].tags
            for ti = 1, #tags do
                local tag = tags[ti]
                if tag.kind == "ReturnTag" and #tag.values > 0 then
                    return type_to_string(tag.values[1])
                end
            end
        end
        return nil
    end

    local function params_from_body(body, ptypes, drop_first)
        local start = drop_first and 2 or 1
        local out = {}
        for i = start, #body.params do
            local p = body.params[i]
            local t = ptypes[p.name]
            if t and t ~= "" and t ~= "any" and t ~= "unknown" then
                out[#out + 1] = C.ParamLabel(p.name .. ": " .. t)
            else
                out[#out + 1] = C.ParamLabel(p.name)
            end
        end
        if body.vararg then out[#out + 1] = C.ParamLabel("...") end
        return out
    end

    local function signature_from_parts(name, params, ret)
        local ptxt = {}
        for i = 1, #params do ptxt[i] = params[i].label end
        local label = name .. "(" .. table.concat(ptxt, ", ") .. ")"
        if ret and ret ~= "" then label = label .. ": " .. ret end
        return C.SignatureInfo(label, params, 0)
    end

    local signature_catalog = pvm.phase("signature_catalog", function(file)
        local by_name, order = {}, {}

        local function ensure_entry(name)
            if not name or name == "" then return nil end
            local e = by_name[name]
            if e then return e end
            e = { name = name, signatures = {}, seen = {} }
            by_name[name] = e
            order[#order + 1] = name
            return e
        end

        local function add_signature(name, params, ret)
            local entry = ensure_entry(name)
            if not entry then return end
            local sig = signature_from_parts(name, params, ret)
            if entry.seen[sig.label] then return end
            entry.seen[sig.label] = true
            entry.signatures[#entry.signatures + 1] = sig
        end

        local function add_overloads(item, name)
            local entry = ensure_entry(name)
            if not entry then return end
            for di = 1, #(item.docs or {}) do
                local tags = item.docs[di].tags
                for ti = 1, #tags do
                    local tag = tags[ti]
                    if tag.kind == "OverloadTag" and tag.sig then
                        local params = {}
                        for pi = 1, #tag.sig.params do
                            params[#params + 1] = C.ParamLabel("arg" .. tostring(pi) .. ": " .. type_to_string(tag.sig.params[pi]))
                        end
                        local ret = (#tag.sig.returns > 0) and type_to_string(tag.sig.returns[1]) or nil
                        local sig = signature_from_parts(name, params, ret)
                        if not entry.seen[sig.label] then
                            entry.seen[sig.label] = true
                            entry.signatures[#entry.signatures + 1] = sig
                        end
                    end
                end
            end
        end

        local visit_block, visit_item

        local function add_stmt(item, stmt)
            if not stmt then return end

            if stmt.kind == "LocalFunction" then
                local ptypes = docs_param_types(item)
                add_signature(stmt.name, params_from_body(stmt.body, ptypes, false), docs_return(item))
                add_overloads(item, stmt.name)
                return
            end

            if stmt.kind == "Function" then
                local ptypes = docs_param_types(item)
                local ret = docs_return(item)
                if stmt.name.kind == "LName" then
                    add_signature(stmt.name.name, params_from_body(stmt.body, ptypes, false), ret)
                    add_overloads(item, stmt.name.name)
                elseif stmt.name.kind == "LField" then
                    add_signature(stmt.name.key, params_from_body(stmt.body, ptypes, false), ret)
                    add_overloads(item, stmt.name.key)
                    if stmt.name.base and stmt.name.base.kind == "NameRef" then
                        local full = stmt.name.base.name .. "." .. stmt.name.key
                        add_signature(full, params_from_body(stmt.body, ptypes, false), ret)
                        add_overloads(item, full)
                    end
                elseif stmt.name.kind == "LMethod" then
                    add_signature(stmt.name.method, params_from_body(stmt.body, ptypes, true), ret)
                    add_overloads(item, stmt.name.method)
                    if stmt.name.base and stmt.name.base.kind == "NameRef" then
                        local full = stmt.name.base.name .. ":" .. stmt.name.method
                        add_signature(full, params_from_body(stmt.body, ptypes, true), ret)
                        add_overloads(item, full)
                    end
                end
                return
            end

            if stmt.kind == "LocalAssign" then
                for i = 1, #stmt.names do
                    local v = stmt.values[i]
                    if v and v.kind == "FunctionExpr" then
                        local n = stmt.names[i] and stmt.names[i].value or nil
                        if n then
                            local ptypes = docs_param_types(item)
                            add_signature(n, params_from_body(v.body, ptypes, false), docs_return(item))
                            add_overloads(item, n)
                        end
                    end
                end
            end
        end

        function visit_item(item)
            if not item then return end
            local stmt = item.stmt
            add_stmt(item, stmt)

            if not stmt then return end
            if stmt.kind == "LocalFunction" then visit_block(stmt.body and stmt.body.body)
            elseif stmt.kind == "Function" then visit_block(stmt.body and stmt.body.body)
            elseif stmt.kind == "LocalAssign" then
                for i = 1, #stmt.values do
                    local v = stmt.values[i]
                    if v and v.kind == "FunctionExpr" then visit_block(v.body and v.body.body) end
                end
            elseif stmt.kind == "If" then
                for i = 1, #stmt.arms do visit_block(stmt.arms[i].body) end
                if stmt.else_block then visit_block(stmt.else_block) end
            elseif stmt.kind == "While" or stmt.kind == "Repeat" or stmt.kind == "ForNum" or stmt.kind == "ForIn" or stmt.kind == "Do" then
                visit_block(stmt.body)
            end
        end

        function visit_block(block)
            if not block or not block.items then return end
            for i = 1, #block.items do visit_item(block.items[i]) end
        end

        for i = 1, #file.items do
            visit_item(file.items[i].syntax)
        end

        local items = {}
        for i = 1, #order do
            local e = by_name[order[i]]
            items[#items + 1] = C.SignatureEntry(e.name, e.signatures)
        end
        return C.SignatureCatalog(items)
    end)

    local signature_lookup = pvm.phase("signature_lookup", function(q)
        local cat = pvm.one(signature_catalog(q.doc))
        local exact, tail = nil, nil
        local tail_name = q.callee:match("([%a_][%w_]*)$")

        for i = 1, #cat.items do
            local e = cat.items[i]
            if e.name == q.callee then exact = e; break end
            if tail_name and e.name == tail_name then tail = e end
        end

        local target = exact or tail
        if not target then return C.SignatureHelp({}, 0) end

        local sigs = {}
        for i = 1, #target.signatures do
            local s = target.signatures[i]
            local ap = q.active_param or 0
            if ap < 0 then ap = 0 end
            if #s.params > 0 and ap > (#s.params - 1) then ap = #s.params - 1 end
            sigs[i] = C.SignatureInfo(s.label, s.params, ap)
        end

        return C.SignatureHelp(sigs, 0)
    end)

    local sig_help = pvm.phase("sig_help", function(q)
        return C.SignatureHelp({}, 0)
    end)

    return {
        signature_catalog_phase = signature_catalog,
        signature_lookup_phase = signature_lookup,
        sig_help_phase = sig_help,
        signature_catalog = signature_catalog,
        signature_lookup = signature_lookup,
        sig_help = sig_help,
        C = C,
    }
end

return M
