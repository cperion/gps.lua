-- lsp/rename.lua
--
-- Rename symbol: finds all occurrences (defs + uses) and produces text edits.
-- pvm.lower("rename"): RenameQuery → RenameResult

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.new(semantics_engine, adapter)
    local C = semantics_engine.C

    local function anchor_ref(v)
        if type(v) == "table" and tostring(v):match("^Lua%.AnchorRef%(") then return v end
        return C.AnchorRef(tostring(v))
    end

    local rename = pvm.lower("rename", function(q)
        local file = q.file
        local anchor = q.anchor
        local new_name = q.new_name

        if not new_name or new_name == "" then
            return C.RenameFail("empty name")
        end

        -- Find the symbol at this anchor
        local binding = semantics_engine:symbol_for_anchor(file, anchor)
        if binding.kind ~= "AnchorSymbol" then
            return C.RenameFail("no symbol at position")
        end

        local sym = binding.symbol
        if sym.kind == C.SymBuiltin then
            return C.RenameFail("cannot rename builtin '" .. sym.name .. "'")
        end

        -- Gather all defs + uses
        local defs = semantics_engine:definitions_of(file, sym.id).items
        local uses = semantics_engine:references_of(file, sym.id).items

        local edits = {}
        local seen = {}

        local function add_edit(anc)
            if not anc then return end
            local aid = anc.id
            if seen[aid] then return end
            seen[aid] = true

            -- Get range from adapter if available
            local range = C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1))
            if adapter and adapter._lsp_range_for then
                range = adapter._lsp_range_for(C.LspRangeQuery(file, anc))
            end
            edits[#edits + 1] = C.RenameEdit(anc, range, new_name)
        end

        for i = 1, #defs do add_edit(defs[i].anchor) end
        for i = 1, #uses do add_edit(uses[i].anchor) end

        if #edits == 0 then
            return C.RenameFail("no occurrences found")
        end

        return C.RenameOk(edits)
    end)

    local prepare_rename = pvm.lower("prepare_rename", function(q)
        local file = q.file
        local anchor = q.anchor

        local binding = semantics_engine:symbol_for_anchor(file, anchor)
        if binding.kind ~= "AnchorSymbol" then return nil end
        if binding.symbol.kind == C.SymBuiltin then return nil end

        -- Return the range of the anchor
        if adapter and adapter._lsp_range_for then
            return adapter._lsp_range_for(C.LspRangeQuery(file, anchor))
        end
        return C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1))
    end)

    return {
        rename = rename,
        prepare_rename = prepare_rename,
        C = C,
    }
end

return M
