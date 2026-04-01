-- asdl/lexer.lua — GPS lexer for ASDL syntax
--
-- gen   = lex_next
-- param = { input, len, source }
-- state = pos (one integer)

local ffi = require("ffi")
-- no external deps beyond ffi

local M = {}

M.TOKEN = {
    IDENT    = 1,
    EQUALS   = 2,
    PIPE     = 3,
    QUESTION = 4,
    STAR     = 5,
    COMMA    = 6,
    LPAREN   = 7,
    RPAREN   = 8,
    LBRACE   = 9,
    RBRACE   = 10,
    DOT      = 11,
    ERROR    = 255,
}

M.TOKEN_NAME = {}
for k, v in pairs(M.TOKEN) do M.TOKEN_NAME[v] = k end

local function is_alpha(b) return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 end
local function is_digit(b) return b >= 48 and b <= 57 end
local function is_alnum(b) return is_alpha(b) or is_digit(b) end
local function is_space(b) return b == 32 or b == 9 or b == 10 or b == 13 end

local T = M.TOKEN

function M.lex_next(param, pos)
    local input = param.input
    local len = param.len

    while pos < len do
        local b = input[pos]

        if is_space(b) then
            pos = pos + 1
        elseif b == 35 then -- #
            pos = pos + 1
            while pos < len and input[pos] ~= 10 do pos = pos + 1 end
            if pos < len then pos = pos + 1 end
        elseif b == 61  then return pos + 1, T.EQUALS,   pos, pos + 1
        elseif b == 124 then return pos + 1, T.PIPE,     pos, pos + 1
        elseif b == 63  then return pos + 1, T.QUESTION, pos, pos + 1
        elseif b == 42  then return pos + 1, T.STAR,     pos, pos + 1
        elseif b == 44  then return pos + 1, T.COMMA,    pos, pos + 1
        elseif b == 40  then return pos + 1, T.LPAREN,   pos, pos + 1
        elseif b == 41  then return pos + 1, T.RPAREN,   pos, pos + 1
        elseif b == 123 then return pos + 1, T.LBRACE,   pos, pos + 1
        elseif b == 125 then return pos + 1, T.RBRACE,   pos, pos + 1
        elseif b == 46  then return pos + 1, T.DOT,      pos, pos + 1
        elseif is_alpha(b) then
            local start = pos
            while pos < len and is_alnum(input[pos]) do pos = pos + 1 end
            return pos, T.IDENT, start, pos
        else
            return pos + 1, T.ERROR, pos, pos + 1
        end
    end

    return nil
end

function M.compile(input_string)
    local len = #input_string
    local input = ffi.new("uint8_t[?]", len)
    ffi.copy(input, input_string, len)
    return { input = input, len = len, source = input_string }
end

function M.tokens(input_string)
    return M.lex_next, M.compile(input_string), 0
end

function M.text(source, start, stop)
    return source:sub(start + 1, stop)
end

return M
