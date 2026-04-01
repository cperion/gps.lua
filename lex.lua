-- gps/lex.lua — General-purpose GPS lexer toolkit
--
-- Build a lexer from a spec. Returns a GPS machine.
-- Zero allocation in the hot path. FFI byte buffer.
--
-- Usage:
--   local lex = require("gps.lex")
--   local L = lex {
--       symbols = "+ - * / ( ) { } = , . | ? !",
--       keywords = { "if", "else", "while", "return" },
--       line_comment = "--",
--       block_comment = { "/*", "*/" },
--       string_quote = '"',
--       number = true,
--       ident = true,
--       whitespace = true,
--   }
--
--   for pos, kind, start, stop in L.tokens(input) do
--       print(L.name(kind), L.text(input, start, stop))
--   end

local ffi = require("ffi")

local function is_alpha(b) return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 end
local function is_digit(b) return b >= 48 and b <= 57 end
local function is_alnum(b) return is_alpha(b) or is_digit(b) end
local function is_space(b) return b == 32 or b == 9 or b == 10 or b == 13 end

return function(spec)
    spec = spec or {}

    -- ── Build token table ────────────────────────────────────

    local TOKEN = { ERROR = 255 }
    local TOKEN_NAME = { [255] = "ERROR" }
    local next_id = 1

    local function add_token(name)
        if TOKEN[name] then return TOKEN[name] end
        local id = next_id
        next_id = next_id + 1
        TOKEN[name] = id
        TOKEN_NAME[id] = name
        return id
    end

    -- ── Parse symbol spec ────────────────────────────────────
    -- "+" or "+ - * /" (space-separated single/multi-char)

    -- Map: first byte → list of { text, kind_id }
    local symbol_dispatch = {}
    local max_symbol_len = 0

    if spec.symbols then
        for sym in spec.symbols:gmatch("%S+") do
            local id = add_token(sym)
            local first = sym:byte(1)
            symbol_dispatch[first] = symbol_dispatch[first] or {}
            symbol_dispatch[first][#symbol_dispatch[first] + 1] = { text = sym, id = id }
            if #sym > max_symbol_len then max_symbol_len = #sym end
        end
        -- Sort each bucket: longer symbols first (so >= matches before >)
        for _, bucket in pairs(symbol_dispatch) do
            table.sort(bucket, function(a, b) return #a.text > #b.text end)
        end
    end

    -- ── Keywords ─────────────────────────────────────────────

    local keyword_map = {}
    if spec.keywords then
        for _, kw in ipairs(spec.keywords) do
            local id = add_token(kw)
            keyword_map[kw] = id
        end
    end

    -- ── Pattern tokens ───────────────────────────────────────

    local IDENT = spec.ident and add_token("IDENT") or nil
    local NUMBER = spec.number and add_token("NUMBER") or nil
    local STRING = spec.string_quote and add_token("STRING") or nil

    local string_quote_byte = spec.string_quote and spec.string_quote:byte(1)

    -- ── Comment spec ─────────────────────────────────────────

    local line_comment = spec.line_comment
    local line_comment_byte = line_comment and line_comment:byte(1)
    local line_comment_len = line_comment and #line_comment

    local block_comment = spec.block_comment
    local block_open = block_comment and block_comment[1]
    local block_close = block_comment and block_comment[2]
    local block_open_byte = block_open and block_open:byte(1)

    -- ── The gen function ─────────────────────────────────────

    -- Check if bytes at pos match a string
    local function match_str(input, len, pos, str)
        for i = 1, #str - 1 do
            if pos + i >= len or input[pos + i] ~= str:byte(i + 1) then return false end
        end
        return true
    end

    local function skip(input, len, pos)
        while pos < len do
            local b = input[pos]
            if spec.whitespace and is_space(b) then
                pos = pos + 1
            elseif line_comment and b == line_comment_byte and match_str(input, len, pos, line_comment) then
                pos = pos + line_comment_len
                while pos < len and input[pos] ~= 10 do pos = pos + 1 end
                if pos < len then pos = pos + 1 end
            elseif block_open and b == block_open_byte and match_str(input, len, pos, block_open) then
                pos = pos + #block_open
                while pos + #block_close - 1 < len do
                    if match_str(input, len, pos, block_close) and input[pos] == block_close:byte(1) then
                        pos = pos + #block_close; break
                    end
                    pos = pos + 1
                end
            else
                break
            end
        end
        return pos
    end

    local function lex_next(param, pos)
        local input = param.input
        local len = param.len

        pos = skip(input, len, pos)
        if pos >= len then return nil end

        local b = input[pos]

        -- Symbol dispatch (operators, delimiters)
        local bucket = symbol_dispatch[b]
        if bucket then
            for _, sym in ipairs(bucket) do
                local text = sym.text
                if #text == 1 or match_str(input, len, pos, text) then
                    return pos + #text, sym.id, pos, pos + #text
                end
            end
        end

        -- String
        if STRING and b == string_quote_byte then
            local start = pos
            pos = pos + 1
            while pos < len and input[pos] ~= string_quote_byte do
                if input[pos] == 92 then pos = pos + 1 end
                pos = pos + 1
            end
            if pos < len then pos = pos + 1 end
            return pos, STRING, start, pos
        end

        -- Number
        if NUMBER and is_digit(b) then
            local start = pos
            while pos < len and is_digit(input[pos]) do pos = pos + 1 end
            if pos < len and input[pos] == 46 then
                pos = pos + 1
                while pos < len and is_digit(input[pos]) do pos = pos + 1 end
            end
            return pos, NUMBER, start, pos
        end

        -- Identifier / keyword
        if IDENT and is_alpha(b) then
            local start = pos
            while pos < len and is_alnum(input[pos]) do pos = pos + 1 end
            local word = param.source:sub(start + 1, pos)
            local kw_id = keyword_map[word]
            return pos, kw_id or IDENT, start, pos
        end

        -- Unknown
        return pos + 1, TOKEN.ERROR, pos, pos + 1
    end

    -- ── Compile and API ──────────────────────────────────────

    local function compile(input_string)
        local len = #input_string
        local input = ffi.new("uint8_t[?]", len)
        ffi.copy(input, input_string, len)
        return { input = input, len = len, source = input_string }
    end

    return {
        lex_next = lex_next,
        compile  = compile,
        TOKEN    = TOKEN,
        TOKEN_NAME = TOKEN_NAME,

        tokens = function(input_string)
            return lex_next, compile(input_string), 0
        end,

        name = function(kind)
            return TOKEN_NAME[kind] or "?"
        end,

        text = function(source, start, stop)
            return source:sub(start + 1, stop)
        end,
    }
end
