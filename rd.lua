-- gps/rd.lua — Low-level fused recursive-descent helper
--
-- Manual parser helper for hand-written recursive descent.
-- Kept as a low-level tool. The primary parser API is GPS.grammar + GPS.parse.
--
-- Usage:
--   local GPS = require("gps")
--   local L = GPS.lex { symbols = "+ - * / ( )", number = true, ident = true, whitespace = true }
--   local result = GPS.rd(L, "1 + 2 * 3", function(p)
--       ...
--   end)

return function(L, input_string, grammar_fn)
    local param = L.compile(input_string)
    local source = input_string
    local pos = 0

    local tok_kind = -1
    local tok_start = 0
    local tok_stop = 0

    local p = {}

    function p:advance()
        local new_pos, kind, start, stop = L.lex_next(param, pos)
        if new_pos == nil then
            tok_kind = 0
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

    p:advance()
    p.kind = tok_kind
    p.start = tok_start
    p.stop = tok_stop

    return grammar_fn(p)
end
