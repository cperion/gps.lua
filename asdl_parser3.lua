-- asdl_parser3.lua — ASDL parser as a uvm machine, coarse-grained
--
-- Same semantics as asdl_parser.lua.
-- The INNER loop is recursive (fast, JIT-traced).
-- The OUTER loop is uvm (resumable, composable, inspectable).
--
-- step() parses ONE complete definition or module and yields it.
-- Between definitions: resumable, hot-swappable, budget-limited.
-- Within a definition: full-speed recursive descent.
--
-- This is the right granularity: step at semantic boundaries,
-- not at token boundaries. You get both speed AND resumability.

local ffi = require("ffi")
local lexer = require("gps.asdl_lexer")
local uvm = require("uvm")

local T = lexer.TOKEN
local S = uvm.status

-- ══════════════════════════════════════════════════════════════
--  LEXER HELPERS (same as asdl_parser.lua)
-- ══════════════════════════════════════════════════════════════

local function advance(param, st)
    local np, kind, start, stop = param.lex_gen(param.lex_param, st.pos)
    if np == nil then
        st.tok_kind = 0; st.tok_start = st.pos; st.tok_stop = st.pos
    else
        st.pos = np; st.tok_kind = kind; st.tok_start = start; st.tok_stop = stop
    end
end

local function tok_text(param, st)
    return lexer.text(param.lex_param.source, st.tok_start, st.tok_stop)
end

local function expect(param, st, kind, what)
    if st.tok_kind ~= kind then
        error(string.format("ASDL parse error: expected %s but found '%s' at pos %d",
            what or tostring(kind), tok_text(param, st), st.tok_start), 0)
    end
    local text = tok_text(param, st)
    advance(param, st)
    return text
end

local function at(st, kind) return st.tok_kind == kind end

local function try(param, st, kind)
    if st.tok_kind == kind then
        local text = tok_text(param, st); advance(param, st); return text
    end
end

local function try_ident(param, st, word)
    if st.tok_kind == T.IDENT and tok_text(param, st) == word then
        advance(param, st); return true
    end
end

-- ══════════════════════════════════════════════════════════════
--  RECURSIVE DESCENT (runs inside a single step — fast, JIT-traced)
-- ══════════════════════════════════════════════════════════════

local function parse_qualified_name(param, st)
    local name = expect(param, st, T.IDENT, "type name")
    while try(param, st, T.DOT) do
        name = name .. "." .. expect(param, st, T.IDENT, "name after '.'")
    end
    return name
end

local function parse_field(param, st, ns)
    local field = { namespace = ns }
    field.type = parse_qualified_name(param, st)
    if try(param, st, T.QUESTION) then field.optional = true
    elseif try(param, st, T.STAR) then field.list = true end
    field.name = expect(param, st, T.IDENT, "field name")
    return field
end

local function parse_fields(param, st, ns)
    local fields = {}
    expect(param, st, T.LPAREN, "'('")
    if not at(st, T.RPAREN) then
        repeat fields[#fields+1] = parse_field(param, st, ns)
        until not try(param, st, T.COMMA)
    end
    expect(param, st, T.RPAREN, "')'")
    return fields
end

local function parse_constructor(param, st, ns)
    local ctor = { name = ns .. expect(param, st, T.IDENT, "constructor name") }
    if at(st, T.LPAREN) then ctor.fields = parse_fields(param, st, ns) end
    ctor.unique = not not try_ident(param, st, "unique")
    return ctor
end

local function parse_sum(param, st, ns)
    local sum = { kind = "sum", constructors = {} }
    repeat sum.constructors[#sum.constructors+1] = parse_constructor(param, st, ns)
    until not try(param, st, T.PIPE)
    if try_ident(param, st, "attributes") then
        local attrs = parse_fields(param, st, ns)
        for _, ctor in ipairs(sum.constructors) do
            ctor.fields = ctor.fields or {}
            for _, a in ipairs(attrs) do ctor.fields[#ctor.fields+1] = a end
        end
    end
    return sum
end

local function parse_product(param, st, ns)
    local p = { kind = "product", fields = parse_fields(param, st, ns) }
    p.unique = not not try_ident(param, st, "unique")
    return p
end

local function parse_type(param, st, ns)
    if at(st, T.LPAREN) then return parse_product(param, st, ns)
    else return parse_sum(param, st, ns) end
end

local function parse_definition(param, st, ns)
    local name = ns .. expect(param, st, T.IDENT, "type name")
    expect(param, st, T.EQUALS, "'='")
    return { name = name, type = parse_type(param, st, ns), namespace = ns }
end

-- Forward declaration for mutual recursion with parse_module
local parse_definitions

local function parse_module(param, st, ns)
    local name = expect(param, st, T.IDENT, "module name")
    expect(param, st, T.LBRACE, "'{'")
    local defs = parse_definitions(param, st, ns .. name .. ".")
    expect(param, st, T.RBRACE, "'}'")
    return defs
end

function parse_definitions(param, st, ns)
    local defs = {}
    while st.tok_kind ~= 0 and not at(st, T.RBRACE) do
        if try_ident(param, st, "module") then
            local module_defs = parse_module(param, st, ns)
            for _, d in ipairs(module_defs) do defs[#defs+1] = d end
        else
            defs[#defs+1] = parse_definition(param, st, ns)
        end
    end
    return defs
end

-- ══════════════════════════════════════════════════════════════
--  UVM FAMILY — coarse grain: one step per definition/module
-- ══════════════════════════════════════════════════════════════
--
-- State: lexer position + namespace stack.
-- Each step() parses one top-level item (definition or module)
-- using the recursive descent above, then yields it.
--
-- Between steps: fully resumable, inspectable, hot-swappable.
-- Within a step: recursive Lua calls, full JIT speed.

local parser_family = uvm.family({
    name = "asdl.parser.v3",

    init = function(param, _seed)
        local st = {
            pos = 0, tok_kind = -1, tok_start = 0, tok_stop = 0,
            namespace = "",
            -- stack for nested module namespaces
            ns_stack = {}, ns_top = 0,
            -- pending: definitions from a module (yielded one at a time)
            pending = nil, pending_idx = 0,
        }
        advance(param, st)
        return st
    end,

    step = function(param, st)
        -- drain pending definitions from a module
        if st.pending then
            st.pending_idx = st.pending_idx + 1
            if st.pending_idx <= #st.pending then
                return st, S.YIELD, st.pending[st.pending_idx]
            end
            st.pending = nil
            st.pending_idx = 0
        end

        -- check for end
        if st.tok_kind == 0 then
            return nil, S.HALT
        end

        -- parse one top-level item
        local ok, result = pcall(function()
            if try_ident(param, st, "module") then
                return parse_module(param, st, st.namespace)
            else
                return parse_definition(param, st, st.namespace)
            end
        end)

        if not ok then
            return st, S.TRAP, tostring(result), st.tok_start
        end

        -- module returns a list of definitions
        if #result > 0 and result[1] and result[1].name then
            -- it's a list of defs from a module
            st.pending = result
            st.pending_idx = 1
            return st, S.YIELD, result[1]
        else
            -- single definition
            return st, S.YIELD, result
        end
    end,

    patchable = function(_param, state)
        return true  -- always patchable between definitions
    end,

    disasm = function(param)
        return "ASDL_PARSER_V3 over " .. tostring(param.lex_param.source:sub(1,40)) .. "..."
    end,
})

-- ══════════════════════════════════════════════════════════════
--  PUBLIC API (compatible with asdl_parser.lua)
-- ══════════════════════════════════════════════════════════════

local M = {}

function M.compile(input_string)
    return {
        lex_gen = lexer.lex_next,
        lex_param = lexer.compile(input_string),
    }
end

function M.parse(input_string)
    local param = M.compile(input_string)
    local machine = parser_family:spawn(param)

    local defs = {}
    while true do
        local status, a, b = machine:step()
        if status == S.YIELD then
            defs[#defs+1] = a
        elseif status == S.HALT then
            break
        elseif status == S.TRAP then
            error(tostring(a), 2)
        end
    end
    return defs
end

M.family = parser_family

return M
