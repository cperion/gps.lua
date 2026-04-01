-- gps/parse.lua — General-purpose GPS parser toolkit
--
-- Creates a parser with a lexer fused in param.
-- Zero-allocation token stepping. Recursive descent helpers.
--
-- Usage:
--   local lex = require("gps.lex")
--   local parse = require("gps.parse")
--
--   local L = lex { symbols = "+ - * / ( )", number = true, ident = true, whitespace = true }
--
--   local result = parse(L, "1 + 2 * 3", function(p)
--       return p:expr(0)  -- or write your own recursive descent
--   end)
--
-- The parser object `p` provides:
--   p:advance()           — step the lexer (fused in param)
--   p:at(kind)            — check current token
--   p:try(kind)           — consume if match, return text or true
--   p:expect(kind, what?) — consume or error
--   p:text()              — current token text
--   p:eof()               — at end of input?
--   p.kind                — current token kind (number)
--   p.start, p.stop       — current token span

local ffi = require("ffi")

return function(L, input_string, grammar_fn)
    local param = L.compile(input_string)
    local source = input_string
    local pos = 0

    -- Current token
    local tok_kind = -1
    local tok_start = 0
    local tok_stop = 0

    -- Parser object
    local p = {}

    function p:advance()
        local new_pos, kind, start, stop = L.lex_next(param, pos)
        if new_pos == nil then
            tok_kind = 0  -- EOF
            tok_start = pos
            tok_stop = pos
        else
            pos = new_pos
            tok_kind = kind
            tok_start = start
            tok_stop = stop
        end
        p.kind = tok_kind
        p.start = tok_start
        p.stop = tok_stop
        return tok_kind
    end

    function p:at(kind)
        if type(kind) == "string" then kind = L.TOKEN[kind] end
        return tok_kind == kind
    end

    function p:try(kind)
        if type(kind) == "string" then kind = L.TOKEN[kind] end
        if tok_kind == kind then
            local text = source:sub(tok_start + 1, tok_stop)
            self:advance()
            return text
        end
        return nil
    end

    function p:expect(kind, what)
        if type(kind) == "string" then kind = L.TOKEN[kind] end
        if tok_kind ~= kind then
            local got = L.TOKEN_NAME[tok_kind] or tostring(tok_kind)
            local expected = what or L.TOKEN_NAME[kind] or tostring(kind)
            error(string.format("parse error at %d: expected %s, got %s '%s'",
                tok_start, expected, got, source:sub(tok_start + 1, tok_stop)), 2)
        end
        local text = source:sub(tok_start + 1, tok_stop)
        self:advance()
        return text
    end

    function p:text()
        return source:sub(tok_start + 1, tok_stop)
    end

    function p:eof()
        return tok_kind == 0
    end

    -- Prime the parser (get first token)
    p:advance()
    p.kind = tok_kind
    p.start = tok_start
    p.stop = tok_stop

    -- Run the grammar function
    return grammar_fn(p)
end
