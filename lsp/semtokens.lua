-- lsp/semtokens.lua
--
-- Semantic token planner boundary.
-- pvm.phase("plan_semantic_tokens"): LspSemanticTokenQuery -> LspSemanticTokenSpanList

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

local LEX_KEYWORD_KIND = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
    ["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["goto"] = true,
    ["if"] = true, ["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true,
    ["or"] = true, ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
    ["until"] = true, ["while"] = true,
}

local LEX_OPERATOR_KIND = {
    ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["//"] = true,
    ["%"] = true, ["^"] = true, ["#"] = true, ["&"] = true, ["|"] = true,
    ["~"] = true, ["<<"] = true, [">>"] = true,
    ["="] = true, ["=="] = true, ["~="] = true, ["<"] = true, ["<="] = true,
    [">"] = true, [">="] = true, [".."] = true,
}

local function utf8_char_len_at(s, i)
    local b = s:byte(i)
    if not b then return 0 end
    if b < 0x80 then return 1 end
    if b < 0xE0 then return 2 end
    if b < 0xF0 then return 3 end
    return 4
end

local function utf16_len(s)
    local n, i = 0, 1
    while i <= #s do
        local len = utf8_char_len_at(s, i)
        if len <= 0 then len = 1 end
        if i + len - 1 > #s then len = 1 end
        n = n + ((len == 4) and 2 or 1)
        i = i + len
    end
    return n
end

local function line_bounds(text, line0)
    local line = line0 or 0
    if line < 0 then line = 0 end

    local pos, cur = 1, 0
    while cur < line do
        local nl = text:find("\n", pos, true)
        if not nl then return #text + 1, #text + 1 end
        pos = nl + 1
        cur = cur + 1
    end

    local line_end = text:find("\n", pos, true)
    if not line_end then line_end = #text + 1 end
    return pos, line_end
end

local function mods_key(mods)
    if not mods or #mods == 0 then return "" end
    local out = {}
    for i = 1, #mods do out[i] = tostring(mods[i]) end
    table.sort(out)
    return table.concat(out, "|")
end

function M.new(semantics_engine, lexer_engine, range_for)
    local C = semantics_engine.C

    local Tok = {
        namespace = C.SemTokNamespace,
        type = C.SemTokType,
        class = C.SemTokClass,
        enum = C.SemTokEnum,
        interface = C.SemTokInterface,
        struct = C.SemTokStruct,
        typeParameter = C.SemTokTypeParameter,
        parameter = C.SemTokParameter,
        variable = C.SemTokVariable,
        property = C.SemTokProperty,
        enumMember = C.SemTokEnumMember,
        event = C.SemTokEvent,
        ["function"] = C.SemTokFunction,
        method = C.SemTokMethod,
        macro = C.SemTokMacro,
        keyword = C.SemTokKeyword,
        modifier = C.SemTokModifier,
        comment = C.SemTokComment,
        string = C.SemTokString,
        number = C.SemTokNumber,
        regexp = C.SemTokRegexp,
        operator = C.SemTokOperator,
        decorator = C.SemTokDecorator,
    }

    local Mod = {
        declaration = C.SemTokDeclaration,
        definition = C.SemTokDefinition,
        readonly = C.SemTokReadonly,
        static = C.SemTokStatic,
        deprecated = C.SemTokDeprecated,
        abstract = C.SemTokAbstract,
        async = C.SemTokAsync,
        modification = C.SemTokModification,
        documentation = C.SemTokDocumentation,
        defaultLibrary = C.SemTokDefaultLibrary,
        global = C.SemTokGlobal,
    }

    local function add_span(spans, seen, line, startc, len, tok, mods)
        if line < 0 then line = 0 end
        if startc < 0 then startc = 0 end
        if len <= 0 then len = 1 end
        local key = line .. ":" .. startc .. ":" .. len .. ":" .. tostring(tok) .. ":" .. mods_key(mods)
        if seen[key] then return end
        seen[key] = true
        spans[#spans + 1] = C.LspSemanticTokenSpan(line, startc, len, tok, mods or {})
    end

    local plan_semantic_tokens = pvm.phase("plan_semantic_tokens", function(q)
        local spans, seen = {}, {}

        local idx = semantics_engine:index(q.doc)
        local env = semantics_engine.resolve_named_types(q.doc)

        local function add_anchor(anchor, tok, mods)
            if not anchor or not range_for then return end
            local r = range_for(q.doc, anchor)
            local line = r.start.line or 0
            local startc = r.start.character or 0
            local len = (r.stop.character or 0) - startc
            add_span(spans, seen, line, startc, len, tok, mods)
        end

        for i = 1, #idx.defs do
            local occ = idx.defs[i]
            if occ.kind == C.SymParam then
                add_anchor(occ.anchor, Tok.parameter, { Mod.declaration, Mod.definition })
            elseif occ.kind == C.SymBuiltin then
                add_anchor(occ.anchor, Tok["function"], { Mod.declaration, Mod.definition, Mod.defaultLibrary })
            elseif occ.kind == C.SymGlobal then
                add_anchor(occ.anchor, Tok.variable, { Mod.declaration, Mod.definition, Mod.global })
            else
                add_anchor(occ.anchor, Tok.variable, { Mod.declaration, Mod.definition })
            end
        end

        for i = 1, #idx.uses do
            local occ = idx.uses[i]
            if occ.kind == C.SymParam then
                add_anchor(occ.anchor, Tok.parameter, {})
            elseif occ.kind == C.SymBuiltin then
                add_anchor(occ.anchor, Tok["function"], { Mod.defaultLibrary })
            elseif occ.kind == C.SymGlobal then
                add_anchor(occ.anchor, Tok.variable, { Mod.global })
            else
                add_anchor(occ.anchor, Tok.variable, {})
            end
        end

        for i = 1, #env.classes do
            local cls = env.classes[i]
            add_anchor(cls.anchor, Tok.class, { Mod.declaration, Mod.definition })
            for j = 1, #cls.fields do
                add_anchor(cls.fields[j].anchor, Tok.property, { Mod.declaration, Mod.definition })
            end
        end
        for i = 1, #env.aliases do
            add_anchor(env.aliases[i].anchor, Tok.type, { Mod.declaration, Mod.definition })
        end
        for i = 1, #env.generics do
            add_anchor(env.generics[i].anchor, Tok.typeParameter, { Mod.declaration, Mod.definition })
        end

        local text = q.doc and q.doc.text or ""
        local uri = q.doc and q.doc.uri or ""
        if lexer_engine and text ~= "" and uri ~= "" then
            local src = C.OpenDoc(uri, q.doc.version or 0, text)
            local lexed = pvm.drain(lexer_engine.lex_with_positions(src))

            for i = 1, #lexed do
                local lt = lexed[i]
                local tok = lt.token
                if tok then
                    local kind = nil
                    local mods = {}
                    if tok.kind == "<string>" then kind = Tok.string
                    elseif tok.kind == "<number>" then kind = Tok.number
                    elseif tok.kind == "<comment>" then kind = Tok.comment
                    elseif LEX_KEYWORD_KIND[tok.kind] then kind = Tok.keyword
                    elseif LEX_OPERATOR_KIND[tok.kind] then kind = Tok.operator
                    end

                    if kind then
                        local line0 = (lt.line or 1) - 1
                        local line_start = line_bounds(text, line0)
                        local start_off = lt.start_offset or line_start
                        local stop_off = lt.end_offset or start_off
                        if stop_off < start_off then stop_off = start_off end

                        local prefix = text:sub(line_start, math.max(line_start, start_off) - 1)
                        local token_txt = text:sub(start_off, stop_off)
                        local startc = utf16_len(prefix)
                        local len = utf16_len(token_txt)
                        add_span(spans, seen, line0, startc, len, kind, mods)
                    end
                end
            end
        end

        table.sort(spans, function(a, b)
            if a.line ~= b.line then return a.line < b.line end
            return a.start < b.start
        end)

        return C.LspSemanticTokenSpanList(spans)
    end)

    return {
        plan_semantic_tokens_phase = plan_semantic_tokens,
        plan_semantic_tokens = plan_semantic_tokens,
        C = C,
        Tok = Tok, Mod = Mod,
    }
end

return M
