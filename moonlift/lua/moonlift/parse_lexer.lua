local M = {}

local DiagMT = {
    __tostring = function(self)
        return string.format("moonlift %s error at %d:%d: %s", self.kind or "parse", self.line or 0, self.col or 0, self.message or "error")
    end,
}

function M.new_diag(kind, line, col, msg, offset, finish)
    return setmetatable({
        kind = kind,
        line = line,
        col = col,
        message = msg,
        offset = offset,
        finish = finish,
    }, DiagMT)
end

function M.as_diag(err)
    if type(err) == "table" and err.line ~= nil and err.col ~= nil and err.message ~= nil then
        return err
    end
    return nil
end

local KEYWORDS = {
    ["func"] = true,
    ["extern"] = true,
    ["const"] = true,
    ["static"] = true,
    ["import"] = true,
    ["type"] = true,
    ["struct"] = true,
    ["let"] = true,
    ["var"] = true,
    ["if"] = true,
    ["then"] = true,
    ["elseif"] = true,
    ["else"] = true,
    ["switch"] = true,
    ["case"] = true,
    ["default"] = true,
    ["return"] = true,
    ["break"] = true,
    ["continue"] = true,
    ["loop"] = true,
    ["next"] = true,
    ["while"] = true,
    ["over"] = true,
    ["do"] = true,
    ["end"] = true,
    ["true"] = true,
    ["false"] = true,
    ["nil"] = true,
    ["and"] = true,
    ["or"] = true,
    ["not"] = true,
    ["cast"] = true,
    ["trunc"] = true,
    ["zext"] = true,
    ["sext"] = true,
    ["bitcast"] = true,
    ["satcast"] = true,
    ["view"] = true,
    ["void"] = true,
    ["bool"] = true,
    ["i8"] = true, ["i16"] = true, ["i32"] = true, ["i64"] = true,
    ["u8"] = true, ["u16"] = true, ["u32"] = true, ["u64"] = true,
    ["f32"] = true, ["f64"] = true,
    ["index"] = true,
}

local function is_ident_start_byte(b)
    return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95
end

local function is_ident_continue_byte(b)
    return is_ident_start_byte(b) or (b >= 48 and b <= 57)
end

local function is_digit_byte(b)
    return b >= 48 and b <= 57
end

local function lex_error(line, col, msg, offset, finish)
    error(M.new_diag("lex", line, col, msg, offset, finish), 0)
end

function M.lex(text)
    local tokens = {}
    local n = #text
    local i = 1
    local line = 1
    local col = 1

    local function peek(off)
        off = off or 0
        local j = i + off
        if j > n then return nil end
        return string.byte(text, j)
    end

    local function peek_char(off)
        off = off or 0
        local j = i + off
        if j > n then return nil end
        return string.sub(text, j, j)
    end

    local function advance()
        local ch = string.sub(text, i, i)
        i = i + 1
        if ch == "\n" then
            line = line + 1
            col = 1
        else
            col = col + 1
        end
        return ch
    end

    local function emit(kind, raw, tok_line, tok_col, offset, finish)
        tokens[#tokens + 1] = {
            kind = kind,
            raw = raw,
            line = tok_line,
            col = tok_col,
            offset = offset,
            finish = finish,
        }
    end

    while i <= n do
        local b = peek()
        local ch = peek_char()

        if ch == " " or ch == "\t" or ch == "\r" then
            advance()

        elseif ch == "\n" then
            local tok_line, tok_col = line, col
            local start = i
            advance()
            emit("nl", "\n", tok_line, tok_col, start, i - 1)

        elseif ch == "-" and peek_char(1) == "-" then
            if peek_char(2) == "[" and peek_char(3) == "[" then
                advance(); advance(); advance(); advance()
                while i <= n do
                    if peek_char() == "]" and peek_char(1) == "]" then
                        advance(); advance()
                        break
                    end
                    advance()
                end
            else
                advance(); advance()
                while i <= n and peek_char() ~= "\n" do
                    advance()
                end
            end

        elseif is_ident_start_byte(b) then
            local tok_line, tok_col = line, col
            local start = i
            advance()
            while i <= n do
                local b2 = peek()
                if b2 == nil or not is_ident_continue_byte(b2) then break end
                advance()
            end
            local raw = string.sub(text, start, i - 1)
            emit(KEYWORDS[raw] and raw or "ident", raw, tok_line, tok_col, start, i - 1)

        elseif is_digit_byte(b) then
            local tok_line, tok_col = line, col
            local start = i
            local is_float = false
            if ch == "0" and (peek_char(1) == "x" or peek_char(1) == "X") then
                advance(); advance()
                while i <= n do
                    local c = peek_char()
                    if c == nil or not c:match("[%da-fA-F]") then break end
                    advance()
                end
            else
                while i <= n and is_digit_byte(peek() or -1) do
                    advance()
                end
                if peek_char() == "." and is_digit_byte(peek(1) or -1) then
                    is_float = true
                    advance()
                    while i <= n and is_digit_byte(peek() or -1) do
                        advance()
                    end
                end
                local e = peek_char()
                if e == "e" or e == "E" then
                    is_float = true
                    advance()
                    local sign = peek_char()
                    if sign == "+" or sign == "-" then
                        advance()
                    end
                    if not is_digit_byte(peek() or -1) then
                        lex_error(tok_line, tok_col, "malformed float exponent", start, i)
                    end
                    while i <= n and is_digit_byte(peek() or -1) do
                        advance()
                    end
                end
            end
            local raw = string.sub(text, start, i - 1)
            emit(is_float and "float" or "int", raw, tok_line, tok_col, start, i - 1)

        else
            local tok_line, tok_col = line, col
            local c0 = ch
            local c1 = peek_char(1)
            local c2 = peek_char(2)
            local start = i

            if c0 == "." or c0 == "," or c0 == ":" or c0 == ";"
                or c0 == "(" or c0 == ")"
                or c0 == "[" or c0 == "]"
                or c0 == "{" or c0 == "}"
                or c0 == "+" or c0 == "*" or c0 == "/" or c0 == "%"
                or c0 == "&" or c0 == "|" then
                advance()
                emit(c0, c0, tok_line, tok_col, start, i - 1)

            elseif c0 == "-" and c1 == ">" then
                advance(); advance()
                emit("->", "->", tok_line, tok_col, start, i - 1)

            elseif c0 == "=" and c1 == "=" then
                advance(); advance()
                emit("==", "==", tok_line, tok_col, start, i - 1)

            elseif c0 == "~" and c1 == "=" then
                advance(); advance()
                emit("~=", "~=", tok_line, tok_col, start, i - 1)

            elseif c0 == "<" and c1 == "=" then
                advance(); advance()
                emit("<=", "<=", tok_line, tok_col, start, i - 1)

            elseif c0 == ">" and c1 == "=" then
                advance(); advance()
                emit(">=", ">=", tok_line, tok_col, start, i - 1)

            elseif c0 == "<" and c1 == "<" then
                advance(); advance()
                emit("<<", "<<", tok_line, tok_col, start, i - 1)

            elseif c0 == ">" and c1 == ">" and c2 == ">" then
                advance(); advance(); advance()
                emit(">>>", ">>>", tok_line, tok_col, start, i - 1)

            elseif c0 == ">" and c1 == ">" then
                advance(); advance()
                emit(">>", ">>", tok_line, tok_col, start, i - 1)

            elseif c0 == "=" or c0 == "-" or c0 == "~" or c0 == "<" or c0 == ">" then
                advance()
                emit(c0, c0, tok_line, tok_col, start, i - 1)

            else
                lex_error(tok_line, tok_col, "unexpected character '" .. c0 .. "'", i, i)
            end
        end
    end

    emit("eof", "", line, col, i, i)
    return tokens
end

return M
