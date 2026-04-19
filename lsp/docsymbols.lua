-- lsp/docsymbols.lua
--
-- Document symbols as phases.
--
--   ParsedDoc:doc_symbol_facts() -> DocSymbolFact*
--   ParsedDoc:doc_symbol_tree()  -> DocSymbolTree
--
-- Facts are streamed flat with explicit parent ids. Tree assembly is a later
-- one-yield phase.

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

local SK = {
    File = 1, Module = 2, Namespace = 3, Package = 4, Class = 5, Method = 6,
    Property = 7, Field = 8, Constructor = 9, Enum = 10, Interface = 11,
    Function = 12, Variable = 13, Constant = 14, String = 15, Number = 16,
    Boolean = 17, Array = 18, Object = 19, Key = 20, Null = 21,
    EnumMember = 22, Struct = 23, Event = 24, Operator = 25, TypeParameter = 26,
}

function M.new(semantics_engine)
    local C = semantics_engine.C

    local function anchor_ref(v)
        if type(v) == "table" and tostring(v):match("^Lua%.AnchorRef%(") then return v end
        return C.AnchorRef(tostring(v))
    end

    local function anchor_id(v)
        return anchor_ref(v).id
    end

    local function detail_for_value(v)
        if not v then return "" end
        local vk = v.kind
        if vk == "Number" then return v.value end
        if vk == "String" then return '"' .. v.value:sub(1, 20) .. '"' end
        if vk == "TableCtor" then return "{...}" end
        if vk == "FunctionExpr" then return "function" end
        if vk == "Call" then return "call" end
        return ""
    end

    local function name_kind_detail_for_function_stmt(n)
        local fname
        if n.name.kind == "LName" then fname = n.name.name
        elseif n.name.kind == "LField" then fname = n.name.key
        elseif n.name.kind == "LMethod" then fname = n.name.method
        else fname = "?" end
        local kind = n.name.kind == "LMethod" and SK.Method or SK.Function
        return fname, kind, "function", anchor_ref(n.name), anchor_id(n.name)
    end

    local doc_symbol_facts
    local function children_with_parent(array, parent_id)
        local trips = {}
        for i = 1, #array do
            trips[#trips + 1] = { doc_symbol_facts(array[i], parent_id or "") }
        end
        return pvm.concat_all(trips)
    end

    doc_symbol_facts = pvm.phase("doc_symbol_facts", {
        [C.ParsedDoc] = function(n, parent_id)
            return children_with_parent(n.items, parent_id or "")
        end,

        [C.LocatedItem] = function(n, parent_id)
            return doc_symbol_facts(n.core, parent_id or "")
        end,

        [C.Item] = function(n, parent_id)
            return doc_symbol_facts(n.stmt, parent_id or "")
        end,

        [C.LocalAssign] = function(n, parent_id)
            local trips = {}
            local parent = parent_id or ""
            for i = 1, #n.names do
                local name = n.names[i]
                local value = n.values[i]
                local kind = SK.Variable
                if value and value.kind == "FunctionExpr" then kind = SK.Function
                elseif value and value.kind == "TableCtor" then kind = SK.Object end
                local id = anchor_id(name)
                trips[#trips + 1] = {
                    pvm.once(C.DocSymbolFact(id, parent, name.value, detail_for_value(value), kind, anchor_ref(name)))
                }
                if value and value.kind == "FunctionExpr" then
                    trips[#trips + 1] = { doc_symbol_facts(value.body, id) }
                end
            end
            return pvm.concat_all(trips)
        end,

        [C.LocalFunction] = function(n, parent_id)
            local parent = parent_id or ""
            local id = anchor_id(n)
            local g1, p1, c1 = pvm.once(C.DocSymbolFact(id, parent, n.name, "function", SK.Function, anchor_ref(n)))
            local g2, p2, c2 = doc_symbol_facts(n.body, id)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.Function] = function(n, parent_id)
            local parent = parent_id or ""
            local fname, kind, detail, anchor, id = name_kind_detail_for_function_stmt(n)
            local g1, p1, c1 = pvm.once(C.DocSymbolFact(id, parent, fname, detail, kind, anchor))
            local g2, p2, c2 = doc_symbol_facts(n.body, id)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.Assign] = function(n, parent_id)
            local trips = {}
            local parent = parent_id or ""
            for i = 1, #n.lhs do
                local lv = n.lhs[i]
                if lv.kind == "LField" then
                    local rhs = n.rhs[i]
                    local kind = (rhs and rhs.kind == "FunctionExpr") and SK.Function or SK.Variable
                    local detail = (rhs and rhs.kind == "FunctionExpr") and "function" or ""
                    local id = anchor_id(lv)
                    trips[#trips + 1] = {
                        pvm.once(C.DocSymbolFact(id, parent, lv.key, detail, kind, anchor_ref(lv)))
                    }
                    if rhs and rhs.kind == "FunctionExpr" then
                        trips[#trips + 1] = { doc_symbol_facts(rhs.body, id) }
                    end
                end
            end
            if #trips == 0 then return pvm.empty() end
            return pvm.concat_all(trips)
        end,

        [C.FuncBody] = function(n, parent_id)
            return children_with_parent(n.body.items, parent_id or "")
        end,

        [C.Block] = function(n, parent_id)
            return children_with_parent(n.items, parent_id or "")
        end,

        [C.If] = function(n, parent_id)
            local trips = {}
            local parent = parent_id or ""
            for i = 1, #n.arms do trips[#trips + 1] = { doc_symbol_facts(n.arms[i].body, parent) } end
            if n.else_block then trips[#trips + 1] = { doc_symbol_facts(n.else_block, parent) } end
            return pvm.concat_all(trips)
        end,
        [C.While] = function(n, parent_id) return doc_symbol_facts(n.body, parent_id or "") end,
        [C.Repeat] = function(n, parent_id) return doc_symbol_facts(n.body, parent_id or "") end,
        [C.ForNum] = function(n, parent_id) return doc_symbol_facts(n.body, parent_id or "") end,
        [C.ForIn] = function(n, parent_id) return doc_symbol_facts(n.body, parent_id or "") end,
        [C.Do] = function(n, parent_id) return doc_symbol_facts(n.body, parent_id or "") end,

        [C.Return] = function() return pvm.empty() end,
        [C.CallStmt] = function() return pvm.empty() end,
        [C.Break] = function() return pvm.empty() end,
        [C.Goto] = function() return pvm.empty() end,
        [C.Label] = function() return pvm.empty() end,
    })

    local doc_symbol_tree = pvm.phase("doc_symbol_tree", function(file)
        local facts = pvm.drain(doc_symbol_facts(file, ""))
        local by_parent = {}
        local order = {}
        for i = 1, #facts do
            local f = facts[i]
            local pid = f.parent_id or ""
            local bucket = by_parent[pid]
            if not bucket then
                bucket = {}
                by_parent[pid] = bucket
            end
            bucket[#bucket + 1] = f
            order[f.id] = i
        end

        local function build(parent_id)
            local src = by_parent[parent_id or ""] or {}
            table.sort(src, function(a, b)
                return (order[a.id] or 0) < (order[b.id] or 0)
            end)
            local out = {}
            for i = 1, #src do
                local f = src[i]
                out[i] = C.DocSymbol(f.name, f.detail, f.kind, f.anchor, build(f.id))
            end
            return out
        end

        return C.DocSymbolTree(build(""))
    end)

    return {
        doc_symbol_facts_phase = doc_symbol_facts,
        doc_symbol_tree_phase = doc_symbol_tree,
        doc_symbol_facts = doc_symbol_facts,
        doc_symbol_tree = doc_symbol_tree,
        SK = SK,
        C = C,
    }
end

return M
