-- lsp/rename.lua
--
-- Rename symbol: finds all occurrences (defs + uses) and produces text edits.
-- pvm.phase("rename"): RenameQuery → RenameResult

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.new(semantics_engine, adapter)
	local C = semantics_engine.C
	local rename = pvm.phase("rename", function(q)
		local file = q.doc
		local anchor = q.anchor
		local new_name = q.new_name

		if not new_name or new_name == "" then
			return C.RenameFail("empty name")
		end

		-- Find the symbol at this anchor
		local binding = pvm.one(semantics_engine:symbol_for_anchor(file, anchor))
		if binding.kind ~= "AnchorSymbol" then
			return C.RenameFail("no symbol at position")
		end

		local sym = binding.symbol
		if sym.kind == C.SymBuiltin then
			return C.RenameFail("cannot rename builtin '" .. sym.name .. "'")
		end

		-- Gather all defs + uses
		local defs = pvm.drain(semantics_engine:definitions_of(file, sym.id))
		local uses = pvm.drain(semantics_engine:references_of(file, sym.id))

		local edits = {}
		local seen = {}

		local function add_edit(anc)
			if not anc then
				return
			end
			local aid = anc.id
			if seen[aid] then
				return
			end
			seen[aid] = true

			-- Get range from adapter if available
			local range = C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1))
			if adapter and adapter._lsp_range_for then
				range = pvm.one(adapter._lsp_range_for(C.LspRangeQuery(file, anc)))
			end
			edits[#edits + 1] = C.RenameEdit(anc, range, new_name)
		end

		for i = 1, #defs do
			add_edit(defs[i].anchor)
		end
		for i = 1, #uses do
			add_edit(uses[i].anchor)
		end

		if #edits == 0 then
			return C.RenameFail("no occurrences found")
		end

		return C.RenameOk(edits)
	end)

	local prepare_rename = pvm.phase("prepare_rename", function(q)
		local file = q.doc
		local anchor = q.anchor

		local binding = pvm.one(semantics_engine:symbol_for_anchor(file, anchor))
		if binding.kind ~= "AnchorSymbol" then
			return nil
		end
		if binding.symbol.kind == C.SymBuiltin then
			return nil
		end

		-- Return the range of the anchor
		if adapter and adapter._lsp_range_for then
			return pvm.one(adapter._lsp_range_for(C.LspRangeQuery(file, anchor)))
		end
		return C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1))
	end)

	return {
		rename_phase = rename,
		prepare_rename_phase = prepare_rename,
		rename = rename,
		prepare_rename = prepare_rename,
		C = C,
	}
end

return M
