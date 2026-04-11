-- lsp/docsymbols.lua
--
-- Document symbols for outline/breadcrumbs.
-- pvm.phase("doc_symbols"): File → DocSymbol*
--
-- Walks the AST and emits DocSymbol ASDL nodes with hierarchy:
--   File → function/local declarations → nested functions

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

-- LSP SymbolKind
local SK = {
    File = 1, Module = 2, Namespace = 3, Package = 4, Class = 5,
    Method = 6, Property = 7, Field = 8, Constructor = 9, Enum = 10,
    Interface = 11, Function = 12, Variable = 13, Constant = 14,
    String = 15, Number = 16, Boolean = 17, Array = 18, Object = 19,
    Key = 20, Null = 21, EnumMember = 22, Struct = 23, Event = 24,
    Operator = 25, TypeParameter = 26,
}

function M.new(semantics_engine)
    local C = semantics_engine.C

    local function anchor_ref(v)
        if type(v) == "table" and tostring(v):match("^Lua%.AnchorRef%(") then return v end
        return C.AnchorRef(tostring(v))
    end

    -- ── doc_symbols phase ──────────────────────────────────
    -- Walks Items, emits DocSymbol for each declaration.
    -- Children capture nested functions.

    local doc_symbols
    doc_symbols = pvm.phase("doc_symbols", {
        [C.File] = function(n)
            return pvm.children(doc_symbols, n.items)
        end,

        [C.Item] = function(n)
            return doc_symbols(n.stmt)
        end,

        [C.LocalAssign] = function(n)
            -- Emit one symbol per declared name
            local trips = {}
            for i = 1, #n.names do
                local name = n.names[i]
                local detail = ""
                if n.values[i] then
                    local vk = n.values[i].kind
                    if vk == "Number" then detail = n.values[i].value
                    elseif vk == "String" then detail = '"' .. n.values[i].value:sub(1, 20) .. '"'
                    elseif vk == "TableCtor" then detail = "{...}"
                    elseif vk == "FunctionExpr" then detail = "function"
                    elseif vk == "Call" then detail = "call"
                    end
                end
                local kind = SK.Variable
                if n.values[i] and n.values[i].kind == "FunctionExpr" then
                    kind = SK.Function
                elseif n.values[i] and n.values[i].kind == "TableCtor" then
                    kind = SK.Object
                end
                -- Recurse into function body for children
                local children = {}
                if n.values[i] and n.values[i].kind == "FunctionExpr" then
                    children = pvm.drain(doc_symbols(n.values[i].body))
                end
                trips[#trips + 1] = { pvm.once(
                    C.DocSymbol(name.value, detail, kind, anchor_ref(name), children)
                ) }
            end
            return pvm.concat_all(trips)
        end,

        [C.LocalFunction] = function(n)
            local children = pvm.drain(doc_symbols(n.body))
            return pvm.once(C.DocSymbol(n.name, "function", SK.Function, anchor_ref(n), children))
        end,

        [C.Function] = function(n)
            local fname
            if n.name.kind == "LName" then fname = n.name.name
            elseif n.name.kind == "LField" then fname = n.name.key
            elseif n.name.kind == "LMethod" then fname = n.name.method
            else fname = "?" end
            local children = pvm.drain(doc_symbols(n.body))
            local kind = n.name.kind == "LMethod" and SK.Method or SK.Function
            return pvm.once(C.DocSymbol(fname, "function", kind, anchor_ref(n.name), children))
        end,

        [C.Assign] = function(n)
            -- Only emit for simple global assignments like M.foo = ...
            local trips = {}
            for i = 1, #n.lhs do
                local lv = n.lhs[i]
                if lv.kind == "LField" then
                    local detail = ""
                    local kind = SK.Variable
                    if n.rhs[i] and n.rhs[i].kind == "FunctionExpr" then
                        detail = "function"; kind = SK.Function
                    end
                    trips[#trips + 1] = { pvm.once(
                        C.DocSymbol(lv.key, detail, kind, anchor_ref(lv), {})
                    ) }
                end
            end
            if #trips > 0 then return pvm.concat_all(trips) end
            return pvm.empty()
        end,

        [C.FuncBody] = function(n)
            return pvm.children(doc_symbols, n.body.items)
        end,

        [C.Block] = function(n)
            return pvm.children(doc_symbols, n.items)
        end,

        -- Statements that don't produce symbols but may contain nested ones
        [C.If] = function(n)
            local trips = {}
            for i = 1, #n.arms do
                trips[#trips + 1] = { doc_symbols(n.arms[i].body) }
            end
            if n.else_block then
                trips[#trips + 1] = { doc_symbols(n.else_block) }
            end
            return pvm.concat_all(trips)
        end,
        [C.While]  = function(n) return doc_symbols(n.body) end,
        [C.Repeat] = function(n) return doc_symbols(n.body) end,
        [C.ForNum] = function(n) return doc_symbols(n.body) end,
        [C.ForIn]  = function(n) return doc_symbols(n.body) end,
        [C.Do]     = function(n) return doc_symbols(n.body) end,

        -- Leaves
        [C.Return]   = function() return pvm.empty() end,
        [C.CallStmt] = function() return pvm.empty() end,
        [C.Break]    = function() return pvm.empty() end,
        [C.Goto]     = function() return pvm.empty() end,
        [C.Label]    = function() return pvm.empty() end,
    })

    return {
        doc_symbols = doc_symbols,
        SK = SK,
        C = C,
    }
end

return M
