-- asdl_parser2.lua — ASDL parser as a uvm machine
--
-- Same semantics as asdl_parser.lua, zero recursion.
-- The recursive descent becomes a state-machine family with explicit stacks.
--
-- Architecture:
--   param = { lex_gen, lex_param }  (the input — immutable)
--   state = { pos, tok, call_stack, val_stack, namespace_stack, ... }
--
-- Each recursive function in asdl_parser.lua maps to a state label.
-- Function calls → push return label + goto callee label.
-- Function returns → pop label + goto it.
--
-- The step function is one big dispatch on state.label.
-- Status protocol:
--   RUN   = internal parse progress (one token consumed or state transition)
--   YIELD = definition produced
--   TRAP  = parse error
--   HALT  = input exhausted, parsing complete

local ffi = require("ffi")
local lexer = require("gps.asdl_lexer")
local uvm = require("uvm")

local T = lexer.TOKEN
local S = uvm.status

-- ══════════════════════════════════════════════════════════════
--  STATE LABELS — one per "function entry" or "continuation point"
-- ══════════════════════════════════════════════════════════════

local L = {
    -- top level
    DEFS_LOOP       = 1,    -- check for module/definition/end
    DEFS_MODULE     = 2,    -- module keyword consumed, parse module
    DEFS_DEF        = 3,    -- parse single definition

    -- definition
    DEF_NAME        = 10,   -- expect IDENT (type name)
    DEF_EQ          = 11,   -- expect =
    DEF_TYPE        = 12,   -- decide product vs sum
    DEF_DONE        = 13,   -- definition complete → yield

    -- product
    PROD_FIELDS     = 20,   -- call parse_fields
    PROD_UNIQUE     = 21,   -- check for "unique"
    PROD_DONE       = 22,

    -- sum / constructors
    SUM_CTOR        = 30,   -- parse one constructor
    SUM_PIPE        = 31,   -- check for | (another constructor)
    SUM_ATTRS       = 32,   -- check for "attributes"
    SUM_ATTRS_MERGE = 33,   -- merge attrs into constructors
    SUM_DONE        = 34,

    -- constructor
    CTOR_NAME       = 40,   -- expect IDENT
    CTOR_LPAREN     = 41,   -- check for (
    CTOR_FIELDS     = 42,   -- call parse_fields
    CTOR_UNIQUE     = 43,   -- check for "unique"
    CTOR_DONE       = 44,

    -- fields
    FIELDS_OPEN     = 50,   -- expect (
    FIELDS_ENTRY    = 51,   -- start a field
    FIELDS_COMMA    = 52,   -- check for , or )
    FIELDS_CLOSE    = 53,   -- expect ) — done

    -- field
    FIELD_TYPE      = 60,   -- call parse_qualified_name for type
    FIELD_MOD       = 61,   -- check ? or *
    FIELD_NAME      = 62,   -- expect IDENT (field name)
    FIELD_DONE      = 63,

    -- qualified name
    QNAME_FIRST     = 70,   -- expect IDENT
    QNAME_DOT       = 71,   -- check for .
    QNAME_NEXT      = 72,   -- expect IDENT after .
    QNAME_DONE      = 73,

    -- module
    MOD_NAME        = 80,   -- expect IDENT (module name)
    MOD_LBRACE      = 81,   -- expect {
    MOD_BODY        = 82,   -- parse definitions (recursive in namespace)
    MOD_RBRACE      = 83,   -- expect }
    MOD_DONE        = 84,
}

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

-- ══════════════════════════════════════════════════════════════
--  THE FAMILY
-- ══════════════════════════════════════════════════════════════

local parser_family = uvm.family({
    name = "asdl.parser",

    init = function(param, _seed)
        local st = {
            -- lexer state
            pos = 0, tok_kind = -1, tok_start = 0, tok_stop = 0,
            -- parser state
            label = L.DEFS_LOOP,
            call_stack = {},    -- return labels
            cs_top = 0,
            -- value accumulation
            defs = {},          -- collected definitions (yielded one at a time)
            namespace = "",     -- current namespace prefix
            ns_stack = {},      -- namespace stack for modules
            ns_top = 0,
            -- temporaries (avoid allocations in hot path)
            cur_def = nil,      -- current definition being built
            cur_type = nil,     -- current type (sum or product)
            cur_ctor = nil,     -- current constructor
            cur_ctors = nil,    -- constructor list for current sum
            cur_fields = nil,   -- current field list
            cur_field = nil,    -- current field
            cur_qname = nil,    -- qualified name accumulator
            cur_attrs = nil,    -- attributes field list
        }
        -- prime the lexer
        advance(param, st)
        return st
    end,

    step = function(param, st)
        local label = st.label

        -- ── helpers (inline for clarity) ─────────────────────

        local function push_call(ret_label)
            st.cs_top = st.cs_top + 1
            st.call_stack[st.cs_top] = ret_label
        end

        local function pop_call()
            local ret = st.call_stack[st.cs_top]
            st.cs_top = st.cs_top - 1
            return ret
        end

        local function push_ns()
            st.ns_top = st.ns_top + 1
            st.ns_stack[st.ns_top] = st.namespace
        end

        local function pop_ns()
            st.namespace = st.ns_stack[st.ns_top]
            st.ns_top = st.ns_top - 1
        end

        local function trap(msg)
            return st, S.TRAP, msg, st.tok_start, tok_text(param, st)
        end

        -- ── DEFINITIONS LOOP ─────────────────────────────────

        if label == L.DEFS_LOOP then
            if st.tok_kind == 0 or st.tok_kind == T.RBRACE then
                -- end of definitions at this level
                -- if we're inside a module, return to module handler
                if st.cs_top > 0 then
                    st.label = pop_call()
                    return st, S.RUN
                end
                return nil, S.HALT
            end
            -- check for "module"
            if st.tok_kind == T.IDENT and tok_text(param, st) == "module" then
                advance(param, st)
                st.label = L.MOD_NAME
                return st, S.RUN
            end
            -- otherwise it's a definition
            st.label = L.DEF_NAME
            return st, S.RUN

        -- ── MODULE ───────────────────────────────────────────

        elseif label == L.MOD_NAME then
            if st.tok_kind ~= T.IDENT then return trap("expected module name") end
            local name = tok_text(param, st)
            advance(param, st)
            push_ns()
            st.namespace = st.namespace .. name .. "."
            st.label = L.MOD_LBRACE
            return st, S.RUN

        elseif label == L.MOD_LBRACE then
            if st.tok_kind ~= T.LBRACE then return trap("expected '{'") end
            advance(param, st)
            -- recurse into definitions
            push_call(L.MOD_RBRACE)
            st.label = L.DEFS_LOOP
            return st, S.RUN

        elseif label == L.MOD_RBRACE then
            if st.tok_kind ~= T.RBRACE then return trap("expected '}'") end
            advance(param, st)
            pop_ns()
            st.label = L.DEFS_LOOP
            return st, S.RUN

        -- ── DEFINITION ───────────────────────────────────────

        elseif label == L.DEF_NAME then
            if st.tok_kind ~= T.IDENT then return trap("expected type name") end
            local name = st.namespace .. tok_text(param, st)
            advance(param, st)
            st.cur_def = { name = name, namespace = st.namespace }
            st.label = L.DEF_EQ
            return st, S.RUN

        elseif label == L.DEF_EQ then
            if st.tok_kind ~= T.EQUALS then return trap("expected '='") end
            advance(param, st)
            st.label = L.DEF_TYPE
            return st, S.RUN

        elseif label == L.DEF_TYPE then
            if st.tok_kind == T.LPAREN then
                -- product type
                st.label = L.PROD_FIELDS
            else
                -- sum type
                st.cur_ctors = {}
                st.label = L.SUM_CTOR
            end
            return st, S.RUN

        elseif label == L.DEF_DONE then
            -- yield the completed definition
            local def = st.cur_def
            st.cur_def = nil
            st.label = L.DEFS_LOOP
            return st, S.YIELD, def

        -- ── PRODUCT ──────────────────────────────────────────

        elseif label == L.PROD_FIELDS then
            push_call(L.PROD_UNIQUE)
            st.cur_fields = {}
            st.label = L.FIELDS_OPEN
            return st, S.RUN

        elseif label == L.PROD_UNIQUE then
            local unique = false
            if st.tok_kind == T.IDENT and tok_text(param, st) == "unique" then
                unique = true
                advance(param, st)
            end
            st.cur_def.type = { kind = "product", fields = st.cur_fields, unique = unique }
            st.cur_fields = nil
            st.label = L.DEF_DONE
            return st, S.RUN

        -- ── SUM ──────────────────────────────────────────────

        elseif label == L.SUM_CTOR then
            -- start a constructor
            st.cur_ctor = {}
            st.label = L.CTOR_NAME
            return st, S.RUN

        elseif label == L.SUM_PIPE then
            -- constructor done, check for | (more constructors)
            st.cur_ctors[#st.cur_ctors + 1] = st.cur_ctor
            st.cur_ctor = nil
            if st.tok_kind == T.PIPE then
                advance(param, st)
                st.label = L.SUM_CTOR
            else
                st.label = L.SUM_ATTRS
            end
            return st, S.RUN

        elseif label == L.SUM_ATTRS then
            -- check for "attributes"
            if st.tok_kind == T.IDENT and tok_text(param, st) == "attributes" then
                advance(param, st)
                st.cur_attrs = nil
                st.cur_fields = {}
                push_call(L.SUM_ATTRS_MERGE)
                st.label = L.FIELDS_OPEN
                return st, S.RUN
            end
            st.label = L.SUM_DONE
            return st, S.RUN

        elseif label == L.SUM_ATTRS_MERGE then
            local attrs = st.cur_fields
            st.cur_fields = nil
            for _, ctor in ipairs(st.cur_ctors) do
                ctor.fields = ctor.fields or {}
                for _, a in ipairs(attrs) do
                    ctor.fields[#ctor.fields + 1] = a
                end
            end
            st.label = L.SUM_DONE
            return st, S.RUN

        elseif label == L.SUM_DONE then
            st.cur_def.type = { kind = "sum", constructors = st.cur_ctors }
            st.cur_ctors = nil
            st.label = L.DEF_DONE
            return st, S.RUN

        -- ── CONSTRUCTOR ──────────────────────────────────────

        elseif label == L.CTOR_NAME then
            if st.tok_kind ~= T.IDENT then return trap("expected constructor name") end
            st.cur_ctor.name = st.namespace .. tok_text(param, st)
            advance(param, st)
            st.label = L.CTOR_LPAREN
            return st, S.RUN

        elseif label == L.CTOR_LPAREN then
            if st.tok_kind == T.LPAREN then
                push_call(L.CTOR_UNIQUE)
                st.cur_fields = {}
                st.label = L.FIELDS_OPEN
            else
                st.label = L.CTOR_UNIQUE
            end
            return st, S.RUN

        elseif label == L.CTOR_UNIQUE then
            if st.tok_kind == T.IDENT and tok_text(param, st) == "unique" then
                st.cur_ctor.unique = true
                advance(param, st)
            else
                st.cur_ctor.unique = false
            end
            if st.cur_fields then
                st.cur_ctor.fields = st.cur_fields
                st.cur_fields = nil
            end
            st.label = L.SUM_PIPE
            return st, S.RUN

        -- ── FIELDS ───────────────────────────────────────────

        elseif label == L.FIELDS_OPEN then
            if st.tok_kind ~= T.LPAREN then return trap("expected '('") end
            advance(param, st)
            if st.tok_kind == T.RPAREN then
                advance(param, st)
                st.label = pop_call()
            else
                st.label = L.FIELDS_ENTRY
            end
            return st, S.RUN

        elseif label == L.FIELDS_ENTRY then
            st.cur_field = { namespace = st.namespace }
            push_call(L.FIELDS_COMMA)
            st.cur_qname = nil
            st.label = L.QNAME_FIRST
            return st, S.RUN

        elseif label == L.FIELDS_COMMA then
            -- field type name is in cur_qname, finish the field
            st.cur_field.type = st.cur_qname
            st.cur_qname = nil
            -- check ? or *
            if st.tok_kind == T.QUESTION then
                st.cur_field.optional = true
                advance(param, st)
            elseif st.tok_kind == T.STAR then
                st.cur_field.list = true
                advance(param, st)
            end
            -- expect field name
            if st.tok_kind ~= T.IDENT then return trap("expected field name") end
            st.cur_field.name = tok_text(param, st)
            advance(param, st)
            -- store field
            st.cur_fields[#st.cur_fields + 1] = st.cur_field
            st.cur_field = nil
            -- comma or close?
            if st.tok_kind == T.COMMA then
                advance(param, st)
                st.label = L.FIELDS_ENTRY
            elseif st.tok_kind == T.RPAREN then
                advance(param, st)
                st.label = pop_call()
            else
                return trap("expected ',' or ')'")
            end
            return st, S.RUN

        -- ── QUALIFIED NAME ───────────────────────────────────

        elseif label == L.QNAME_FIRST then
            if st.tok_kind ~= T.IDENT then return trap("expected type name") end
            st.cur_qname = tok_text(param, st)
            advance(param, st)
            st.label = L.QNAME_DOT
            return st, S.RUN

        elseif label == L.QNAME_DOT then
            if st.tok_kind == T.DOT then
                advance(param, st)
                st.label = L.QNAME_NEXT
            else
                st.label = pop_call()
            end
            return st, S.RUN

        elseif label == L.QNAME_NEXT then
            if st.tok_kind ~= T.IDENT then return trap("expected name after '.'") end
            st.cur_qname = st.cur_qname .. "." .. tok_text(param, st)
            advance(param, st)
            st.label = L.QNAME_DOT
            return st, S.RUN

        else
            return st, S.TRAP, "bad label", label
        end
    end,

    patchable = function(_param, state)
        return state.label == L.DEFS_LOOP
    end,

    disasm = function(param)
        return "ASDL_PARSER over " .. tostring(param.lex_param.source:sub(1,40)) .. "..."
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
        local status, a, b, c = machine:step()
        if status == S.YIELD then
            defs[#defs + 1] = a
        elseif status == S.HALT then
            break
        elseif status == S.TRAP then
            error(string.format("ASDL parse error: %s at pos %s near '%s'",
                tostring(a), tostring(b), tostring(c)), 2)
        end
        -- RUN → continue
    end
    return defs
end

-- expose the family for advanced use (stepping, inspection, hot-swap)
M.family = parser_family

return M
