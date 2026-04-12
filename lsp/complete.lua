-- lsp/complete.lua
--
-- Completion engine. pvm.lower("complete"): CompletionQuery → CompletionList
--
-- Completion sources:
--   1. Locals in scope at cursor position
--   2. Globals (builtins + user-declared)
--   3. Class fields (after `.` or `:`)
--   4. Module exports (table fields of require'd modules)
--   5. Keywords
--
-- Every CompletionItem is an ASDL unique node → cached per query.

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

-- LSP CompletionItemKind constants
local KIND = {
    Text = 1, Method = 2, Function = 3, Constructor = 4,
    Field = 5, Variable = 6, Class = 7, Interface = 8,
    Module = 9, Property = 10, Unit = 11, Value = 12,
    Enum = 13, Keyword = 14, Snippet = 15, Color = 16,
    File = 17, Reference = 18, Folder = 19, EnumMember = 20,
    Constant = 21, Struct = 22, Event = 23, Operator = 24,
    TypeParameter = 25,
}

local KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for",
    "function", "goto", "if", "in", "local", "nil", "not", "or",
    "repeat", "return", "then", "true", "until", "while",
}

function M.new(semantics_engine, type_engine)
    local C = semantics_engine.C

    local function kind_for_symbol(sym)
        if sym.kind == C.SymBuiltin then return KIND.Function end
        if sym.kind == C.SymTypeClass then return KIND.Class end
        if sym.kind == C.SymTypeAlias or sym.kind == C.SymTypeGeneric or sym.kind == C.SymTypeBuiltin then
            return KIND.TypeParameter
        end
        return KIND.Variable
    end

    -- ── complete lower ─────────────────────────────────────

    local complete = pvm.lower("complete", function(q)
        local file = q.file
        local prefix = q.prefix or ""
        local prefix_lower = prefix:lower()
        local items = {}
        local seen = {}

        local function add(label, kind, detail, sort_prefix)
            if seen[label] then return end
            seen[label] = true
            if prefix ~= "" and not label:lower():find(prefix_lower, 1, true) then return end
            items[#items + 1] = C.CompletionItem(
                label, kind, detail or "",
                (sort_prefix or "0") .. label,
                label)
        end

        -- 1. Symbols from the file
        local idx = semantics_engine:index(file)
        local ti = type_engine and type_engine.typed_index(file) or nil

        local function type_detail(sym_id)
            if not ti then return "" end
            for i = 1, #ti.symbols do
                if ti.symbols[i].symbol.id == sym_id then
                    local t = ti.symbols[i].typ
                    if t.kind ~= "TUnknown" and t.kind ~= "TAny" then
                        return type_engine.type_to_string(t)
                    end
                end
            end
            return ""
        end

        for i = 1, #idx.symbols do
            local sym = idx.symbols[i]
            local detail = type_detail(sym.id)
            local k = kind_for_symbol(sym)
            -- Boost locals over globals
            local sort = (sym.kind == C.SymLocal or sym.kind == C.SymParam) and "1" or "2"
            add(sym.name, k, detail, sort)
        end

        -- 2. Class fields (for completions after `.`)
        local env = semantics_engine.resolve_named_types(file)
        for i = 1, #env.classes do
            local cls = env.classes[i]
            for j = 1, #cls.fields do
                local f = cls.fields[j]
                local detail = cls.name .. "." .. f.name
                if type_engine then
                    detail = type_engine.type_to_string(f.typ)
                end
                add(f.name, KIND.Field, detail, "3")
            end
        end

        -- 3. Keywords
        for i = 1, #KEYWORDS do
            add(KEYWORDS[i], KIND.Keyword, "keyword", "9")
        end

        return C.CompletionList(items, false)
    end)

    return {
        complete = complete,
        KIND = KIND,
        C = C,
    }
end

return M
