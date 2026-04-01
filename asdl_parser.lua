-- asdl/parser.lua — GPS parser for ASDL syntax
--
-- Fusion: parser param contains the lexer's gen + param.
-- Parser steps the lexer directly. No token array.
--
-- Output: a plain Lua table describing the definitions.
-- The context module turns that into live ASDL types.

local ffi = require("ffi")
local lexer = require("gps.asdl_lexer")

local T = lexer.TOKEN
local M = {}

-- ── Parser state ─────────────────────────────────────────────

ffi.cdef [[
    typedef struct {
        int pos;
        int tok_kind;
        int tok_start;
        int tok_stop;
    } AsdlParseState;
]]

local AsdlParseState = ffi.typeof("AsdlParseState")
local function alloc_state()
    local s = ffi.new(AsdlParseState)
    s.pos = 0; s.tok_kind = -1
    return s
end

-- ── Lexer stepping (fusion point) ────────────────────────────

local function advance(param, state)
    local new_pos, kind, start, stop = param.lex_gen(param.lex_param, state.pos)
    if new_pos == nil then
        state.tok_kind = 0  -- EOF
        state.tok_start = state.pos
        state.tok_stop = state.pos
    else
        state.pos = new_pos
        state.tok_kind = kind
        state.tok_start = start
        state.tok_stop = stop
    end
end

local function tok_text(param, state)
    return lexer.text(param.lex_param.source, state.tok_start, state.tok_stop)
end

local function expect(param, state, kind, what)
    if state.tok_kind ~= kind then
        error(string.format("ASDL parse error: expected %s but found '%s' at pos %d",
            what or lexer.TOKEN_NAME[kind] or tostring(kind),
            tok_text(param, state), state.tok_start), 2)
    end
    local text = tok_text(param, state)
    advance(param, state)
    return text
end

local function at(state, kind)
    return state.tok_kind == kind
end

local function try(param, state, kind)
    if state.tok_kind == kind then
        local text = tok_text(param, state)
        advance(param, state)
        return text
    end
    return nil
end

local function at_ident(param, state, word)
    return state.tok_kind == T.IDENT and tok_text(param, state) == word
end

local function try_ident(param, state, word)
    if at_ident(param, state, word) then
        advance(param, state)
        return true
    end
    return false
end

-- ── Grammar ──────────────────────────────────────────────────

local parse_definitions  -- forward

local function parse_qualified_name(param, state)
    local name = expect(param, state, T.IDENT, "type name")
    while try(param, state, T.DOT) do
        name = name .. "." .. expect(param, state, T.IDENT, "name after '.'")
    end
    return name
end

local function parse_field(param, state, namespace)
    local field = {}
    field.type = parse_qualified_name(param, state)
    field.namespace = namespace
    if try(param, state, T.QUESTION) then
        field.optional = true
    elseif try(param, state, T.STAR) then
        field.list = true
    end
    field.name = expect(param, state, T.IDENT, "field name")
    return field
end

local function parse_fields(param, state, namespace)
    local fields = {}
    expect(param, state, T.LPAREN, "'('")
    if not at(state, T.RPAREN) then
        repeat
            fields[#fields + 1] = parse_field(param, state, namespace)
        until not try(param, state, T.COMMA)
    end
    expect(param, state, T.RPAREN, "')'")
    return fields
end

local function parse_constructor(param, state, namespace)
    local ctor = {}
    ctor.name = namespace .. expect(param, state, T.IDENT, "constructor name")
    if at(state, T.LPAREN) then
        ctor.fields = parse_fields(param, state, namespace)
    end
    ctor.unique = try_ident(param, state, "unique")
    return ctor
end

local function parse_sum(param, state, namespace)
    local sum = { kind = "sum", constructors = {} }
    repeat
        sum.constructors[#sum.constructors + 1] = parse_constructor(param, state, namespace)
    until not try(param, state, T.PIPE)
    if try_ident(param, state, "attributes") then
        local attrs = parse_fields(param, state, namespace)
        for _, ctor in ipairs(sum.constructors) do
            ctor.fields = ctor.fields or {}
            for _, a in ipairs(attrs) do
                ctor.fields[#ctor.fields + 1] = a
            end
        end
    end
    return sum
end

local function parse_product(param, state, namespace)
    local product = { kind = "product", fields = parse_fields(param, state, namespace) }
    product.unique = try_ident(param, state, "unique")
    return product
end

local function parse_type(param, state, namespace)
    if at(state, T.LPAREN) then
        return parse_product(param, state, namespace)
    else
        return parse_sum(param, state, namespace)
    end
end

local function parse_module(param, state, namespace)
    -- "module" already consumed by caller
    local name = expect(param, state, T.IDENT, "module name")
    expect(param, state, T.LBRACE, "'{'")
    local defs = parse_definitions(param, state, namespace .. name .. ".")
    expect(param, state, T.RBRACE, "'}'")
    return defs
end

local function parse_definition(param, state, namespace)
    local name = namespace .. expect(param, state, T.IDENT, "type name")
    expect(param, state, T.EQUALS, "'='")
    local typ = parse_type(param, state, namespace)
    return { name = name, type = typ, namespace = namespace }
end

function parse_definitions(param, state, namespace)
    local defs = {}
    while state.tok_kind ~= 0 and not at(state, T.RBRACE) do
        if try_ident(param, state, "module") then
            local module_defs = parse_module(param, state, namespace)
            for _, d in ipairs(module_defs) do defs[#defs + 1] = d end
        else
            defs[#defs + 1] = parse_definition(param, state, namespace)
        end
    end
    return defs
end

-- ── Public API ───────────────────────────────────────────────

function M.compile(input_string)
    return {
        lex_gen = lexer.lex_next,
        lex_param = lexer.compile(input_string),
    }
end

function M.parse(input_string)
    local param = M.compile(input_string)
    local state = alloc_state()
    advance(param, state)
    return parse_definitions(param, state, "")
end

return M
