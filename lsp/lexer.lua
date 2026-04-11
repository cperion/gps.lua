-- lsp/lexer.lua
--
-- Lua lexer as pvm.phase("lex").
--
-- Dispatches on SourceFile, emits Token ASDL nodes.
-- Token = (string kind, string value) unique — NO position.
-- Position is tracked in a parallel array returned alongside.
--
-- Usage:
--   local engine = require("lsp.lexer").new(ctx)
--   -- As pvm phase (lazy triplet, cached per SourceFile identity):
--   local g, p, c = engine.lex(source_file)
--   local tokens = pvm.drain(g, p, c)
--
--   -- As pvm lower (returns {tokens=..., positions=...}, cached):
--   local result = engine.lex_with_positions(source_file)
--   result.tokens[i]      -- Token ASDL node
--   result.positions[i]   -- {line, col, offset, end_offset}
--
-- Because Token is unique + position-free:
--   Token("local", "local") at line 1 == Token("local", "local") at line 50
--   → maximum interning → maximum downstream cache hits

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local ASDL = require("lsp.asdl")

local M = {}

-- ── Keyword table ──────────────────────────────────────────
local KEYWORDS = {}
for w in ("and break do else elseif end false for function goto " ..
          "if in local nil not or repeat return then true until while"):gmatch("%w+") do
    KEYWORDS[w] = true
end

-- ── Long bracket level detection ───────────────────────────
local function long_bracket_level(src, pos)
    if src:byte(pos) ~= 91 then return nil end -- [
    local i = pos + 1
    while src:byte(i) == 61 do i = i + 1 end   -- =
    if src:byte(i) ~= 91 then return nil end    -- [
    return i - pos - 1
end

-- ── Long string / long comment body ────────────────────────
local function scan_long_string(src, pos, level)
    local n = #src
    local i = pos + level + 2
    local b = src:byte(i)
    if b == 10 then i = i + 1
    elseif b == 13 then i = i + 1; if src:byte(i) == 10 then i = i + 1 end
    end
    local start = i
    local close = "]" .. ("="):rep(level) .. "]"
    local j = src:find(close, i, true)
    if not j then return src:sub(start), n + 1 end
    return src:sub(start, j - 1), j + #close
end

-- ── Number literal scanner ─────────────────────────────────
local function scan_number(src, pos)
    local n = #src
    local i = pos
    if src:byte(i) == 48 and (src:byte(i+1) == 120 or src:byte(i+1) == 88) then
        i = i + 2
        while true do
            local b = src:byte(i)
            if not b then break end
            if (b >= 48 and b <= 57) or (b >= 65 and b <= 70) or (b >= 97 and b <= 102) or b == 95 then
                i = i + 1
            else break end
        end
        local b = src:byte(i)
        if b == 112 or b == 80 then
            i = i + 1; b = src:byte(i)
            if b == 43 or b == 45 then i = i + 1 end
            while true do b = src:byte(i); if b and b >= 48 and b <= 57 then i = i + 1 else break end end
        end
    else
        while true do
            local b = src:byte(i)
            if b and ((b >= 48 and b <= 57) or b == 95) then i = i + 1 else break end
        end
        if src:byte(i) == 46 then
            i = i + 1
            while true do
                local b = src:byte(i)
                if b and ((b >= 48 and b <= 57) or b == 95) then i = i + 1 else break end
            end
        end
        local b = src:byte(i)
        if b == 101 or b == 69 then
            i = i + 1; b = src:byte(i)
            if b == 43 or b == 45 then i = i + 1 end
            while true do b = src:byte(i); if b and b >= 48 and b <= 57 then i = i + 1 else break end end
        end
    end
    local b = src:byte(i)
    if b == 105 then i = i + 1
    elseif b == 85 or b == 117 then
        i = i + 1
        if src:byte(i) == 76 or src:byte(i) == 108 then i = i + 1 end
        if src:byte(i) == 76 or src:byte(i) == 108 then i = i + 1 end
    elseif b == 76 or b == 108 then
        i = i + 1
        if src:byte(i) == 76 or src:byte(i) == 108 then i = i + 1 end
    end
    return src:sub(pos, i - 1), i
end

-- ── Short string scanner ───────────────────────────────────
local function scan_short_string(src, pos)
    local quote = src:byte(pos)
    local n = #src
    local i = pos + 1
    local parts, p = {}, 0
    while i <= n do
        local b = src:byte(i)
        if b == quote then return table.concat(parts), i + 1
        elseif b == 92 then
            i = i + 1; b = src:byte(i)
            if not b then break end
            if     b == 97  then p=p+1; parts[p]="\a"; i=i+1
            elseif b == 98  then p=p+1; parts[p]="\b"; i=i+1
            elseif b == 102 then p=p+1; parts[p]="\f"; i=i+1
            elseif b == 110 then p=p+1; parts[p]="\n"; i=i+1
            elseif b == 114 then p=p+1; parts[p]="\r"; i=i+1
            elseif b == 116 then p=p+1; parts[p]="\t"; i=i+1
            elseif b == 118 then p=p+1; parts[p]="\v"; i=i+1
            elseif b == 92  then p=p+1; parts[p]="\\"; i=i+1
            elseif b == 39  then p=p+1; parts[p]="'";  i=i+1
            elseif b == 34  then p=p+1; parts[p]='"';  i=i+1
            elseif b == 10  then p=p+1; parts[p]="\n"; i=i+1
            elseif b == 13  then
                p=p+1; parts[p]="\n"; i=i+1
                if src:byte(i) == 10 then i=i+1 end
            elseif b == 120 then
                local hex = src:sub(i+1, i+2)
                p=p+1; parts[p]=string.char(tonumber(hex, 16) or 0); i=i+3
            elseif b >= 48 and b <= 57 then
                local j = i
                while j < i+3 and src:byte(j) and src:byte(j) >= 48 and src:byte(j) <= 57 do j=j+1 end
                p=p+1; parts[p]=string.char(tonumber(src:sub(i, j-1)) or 0); i=j
            elseif b == 122 then
                i = i + 1
                while true do
                    b = src:byte(i)
                    if b==32 or b==9 or b==10 or b==13 or b==12 then i=i+1 else break end
                end
            else p=p+1; parts[p]=string.char(b); i=i+1
            end
        elseif b == 10 or b == 13 then return table.concat(parts), i
        else p=p+1; parts[p]=string.char(b); i=i+1
        end
    end
    return table.concat(parts), i
end

-- ══════════════════════════════════════════════════════════════
--  Raw scanner: returns arrays of (kind, value, line, col, offset, end_offset)
--  This is the inner loop — pure byte scanning, no ASDL allocation.
-- ══════════════════════════════════════════════════════════════
local function scan_all(src)
    local n = #src
    local kinds, values, lines_arr, cols, offsets, end_offsets = {}, {}, {}, {}, {}, {}
    local count = 0
    local i = 1
    local line = 1
    local line_start = 1

    while i <= n do
        local b = src:byte(i)
        local col = i - line_start + 1
        local token_start = i

        -- whitespace
        if b == 32 or b == 9 or b == 12 then
            i = i + 1
        elseif b == 10 then
            i = i + 1; line = line + 1; line_start = i
        elseif b == 13 then
            i = i + 1; if src:byte(i) == 10 then i = i + 1 end
            line = line + 1; line_start = i

        -- comment or minus
        elseif b == 45 then
            if src:byte(i+1) == 45 then
                i = i + 2
                local level = long_bracket_level(src, i)
                if level then
                    local body, end_pos = scan_long_string(src, i, level)
                    for _ in body:gmatch("\n") do line = line + 1 end
                    i = end_pos
                    local j = end_pos - 1
                    while j > 0 and src:byte(j) ~= 10 and src:byte(j) ~= 13 do j = j - 1 end
                    if j > 0 then line_start = j + 1 end
                    count = count + 1
                    kinds[count] = "<comment>"; values[count] = src:sub(token_start, end_pos-1)
                    lines_arr[count] = line; cols[count] = col
                    offsets[count] = token_start; end_offsets[count] = end_pos - 1
                else
                    while i <= n do
                        local cb = src:byte(i)
                        if cb == 10 or cb == 13 then break end
                        i = i + 1
                    end
                    count = count + 1
                    kinds[count] = "<comment>"; values[count] = src:sub(token_start, i-1)
                    lines_arr[count] = line; cols[count] = col
                    offsets[count] = token_start; end_offsets[count] = i - 1
                end
            else
                i = i + 1; count = count + 1
                kinds[count] = "-"; values[count] = "-"
                lines_arr[count] = line; cols[count] = col
                offsets[count] = token_start; end_offsets[count] = token_start
            end

        -- string literals
        elseif b == 34 or b == 39 then
            local val, end_pos = scan_short_string(src, i)
            for _ in src:sub(i, end_pos-1):gmatch("\n") do line = line + 1 end
            local j = end_pos - 1
            while j > token_start and src:byte(j) ~= 10 and src:byte(j) ~= 13 do j = j - 1 end
            if j > token_start then line_start = j + 1 end
            count = count + 1
            kinds[count] = "<string>"; values[count] = val
            lines_arr[count] = line; cols[count] = col
            offsets[count] = token_start; end_offsets[count] = end_pos - 1
            i = end_pos

        elseif b == 91 then
            local level = long_bracket_level(src, i)
            if level then
                local val, end_pos = scan_long_string(src, i, level)
                for _ in val:gmatch("\n") do line = line + 1 end
                local j = end_pos - 1
                while j > token_start and src:byte(j) ~= 10 and src:byte(j) ~= 13 do j = j - 1 end
                if j > token_start then line_start = j + 1 end
                count = count + 1
                kinds[count] = "<string>"; values[count] = val
                lines_arr[count] = line; cols[count] = col
                offsets[count] = token_start; end_offsets[count] = end_pos - 1
                i = end_pos
            else
                i = i + 1; count = count + 1
                kinds[count] = "["; values[count] = "["
                lines_arr[count] = line; cols[count] = col
                offsets[count] = token_start; end_offsets[count] = token_start
            end

        -- numbers
        elseif (b >= 48 and b <= 57) or (b == 46 and src:byte(i+1) and src:byte(i+1) >= 48 and src:byte(i+1) <= 57) then
            local val, end_pos = scan_number(src, i)
            count = count + 1
            kinds[count] = "<number>"; values[count] = val
            lines_arr[count] = line; cols[count] = col
            offsets[count] = token_start; end_offsets[count] = end_pos - 1
            i = end_pos

        -- name or keyword
        elseif (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 then
            local j = i + 1
            while j <= n do
                local c = src:byte(j)
                if (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95 then
                    j = j + 1
                else break end
            end
            local word = src:sub(i, j-1)
            count = count + 1
            kinds[count] = KEYWORDS[word] and word or "<name>"
            values[count] = word
            lines_arr[count] = line; cols[count] = col
            offsets[count] = token_start; end_offsets[count] = j - 1
            i = j

        -- dot / concat / vararg
        elseif b == 46 then
            if src:byte(i+1) == 46 then
                if src:byte(i+2) == 46 then
                    count=count+1; kinds[count]="..."; values[count]="..."
                    lines_arr[count]=line; cols[count]=col
                    offsets[count]=token_start; end_offsets[count]=i+2; i=i+3
                else
                    count=count+1; kinds[count]=".."; values[count]=".."
                    lines_arr[count]=line; cols[count]=col
                    offsets[count]=token_start; end_offsets[count]=i+1; i=i+2
                end
            else
                count=count+1; kinds[count]="."; values[count]="."
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=token_start; i=i+1
            end

        -- relational / assignment
        elseif b == 61 then
            if src:byte(i+1) == 61 then
                count=count+1; kinds[count]="=="; values[count]="=="
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=i+1; i=i+2
            else
                count=count+1; kinds[count]="="; values[count]="="
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=token_start; i=i+1
            end
        elseif b == 60 then
            local b2 = src:byte(i+1)
            if b2 == 61 then
                count=count+1; kinds[count]="<="; values[count]="<="
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=i+1; i=i+2
            elseif b2 == 60 then
                count=count+1; kinds[count]="<<"; values[count]="<<"
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=i+1; i=i+2
            else
                count=count+1; kinds[count]="<"; values[count]="<"
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=token_start; i=i+1
            end
        elseif b == 62 then
            local b2 = src:byte(i+1)
            if b2 == 61 then
                count=count+1; kinds[count]=">="; values[count]=">="
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=i+1; i=i+2
            elseif b2 == 62 then
                count=count+1; kinds[count]=">>"; values[count]=">>"
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=i+1; i=i+2
            else
                count=count+1; kinds[count]=">"; values[count]=">"
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=token_start; i=i+1
            end
        elseif b == 126 then
            if src:byte(i+1) == 61 then
                count=count+1; kinds[count]="~="; values[count]="~="
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=i+1; i=i+2
            else
                count=count+1; kinds[count]="~"; values[count]="~"
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=token_start; i=i+1
            end
        elseif b == 58 then
            if src:byte(i+1) == 58 then
                count=count+1; kinds[count]="::"; values[count]="::"
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=i+1; i=i+2
            else
                count=count+1; kinds[count]=":"; values[count]=":"
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=token_start; i=i+1
            end
        elseif b == 47 then
            if src:byte(i+1) == 47 then
                count=count+1; kinds[count]="//"; values[count]="//"
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=i+1; i=i+2
            else
                count=count+1; kinds[count]="/"; values[count]="/"
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=token_start; i=i+1
            end

        -- single-char tokens
        else
            local ch
            if     b == 43  then ch = "+"
            elseif b == 42  then ch = "*"
            elseif b == 37  then ch = "%"
            elseif b == 94  then ch = "^"
            elseif b == 35  then ch = "#"
            elseif b == 38  then ch = "&"
            elseif b == 124 then ch = "|"
            elseif b == 40  then ch = "("
            elseif b == 41  then ch = ")"
            elseif b == 123 then ch = "{"
            elseif b == 125 then ch = "}"
            elseif b == 93  then ch = "]"
            elseif b == 59  then ch = ";"
            elseif b == 44  then ch = ","
            end
            if ch then
                count=count+1; kinds[count]=ch; values[count]=ch
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=token_start
                i = i + 1
            else
                -- unknown byte
                count=count+1; kinds[count]="<error>"; values[count]=string.char(b)
                lines_arr[count]=line; cols[count]=col
                offsets[count]=token_start; end_offsets[count]=token_start
                i = i + 1
            end
        end
    end

    -- EOF
    count = count + 1
    kinds[count] = "<eof>"; values[count] = ""
    lines_arr[count] = line; cols[count] = i - line_start + 1
    offsets[count] = i; end_offsets[count] = i

    return count, kinds, values, lines_arr, cols, offsets, end_offsets
end

-- ══════════════════════════════════════════════════════════════
--  pvm boundaries
-- ══════════════════════════════════════════════════════════════

function M.new(ctx)
    ctx = ctx or ASDL.context()
    local C = ctx.Lua

    -- ── lex phase ──────────────────────────────────────────
    -- Dispatches on SourceFile. Emits Token ASDL nodes.
    -- Token is (kind, value) unique — NO position.
    -- Positions are captured in the `lex_with_positions` lower below.
    --
    -- Because Token carries no position:
    --   Token("local", "local") is ONE interned object system-wide.
    --   Token("<name>", "x") is ONE interned object.
    -- → Downstream phases (parser, semantics) get maximum cache hits.
    local lex = pvm.phase("lex", {
        [C.SourceFile] = function(self)
            local count, kinds, values = scan_all(self.text)
            local tokens = {}
            for i = 1, count do
                tokens[i] = C.Token(kinds[i], values[i])
            end
            return pvm.seq(tokens)
        end,
    })

    -- ── lex_with_positions lower ───────────────────────────
    -- Returns (tokens, positions) for parser use.
    -- tokens[i]    = Token ASDL node (interned, position-free)
    -- positions[i] = {line, col, offset, end_offset} (raw numbers)
    --
    -- Cached per SourceFile identity.
    local lex_with_positions = pvm.lower("lex_with_positions", function(source_file)
        local count, kinds, values, lines_arr, cols, offsets, end_offsets = scan_all(source_file.text)
        local tokens = {}
        local positions = {}
        for i = 1, count do
            tokens[i] = C.Token(kinds[i], values[i])
            positions[i] = {
                line = lines_arr[i],
                col = cols[i],
                offset = offsets[i],
                end_offset = end_offsets[i],
            }
        end
        return { tokens = tokens, positions = positions, count = count }
    end)

    return {
        C = C,
        context = ctx,
        lex = lex,
        lex_with_positions = lex_with_positions,
        scan_all = scan_all,  -- exposed for testing
        KEYWORDS = KEYWORDS,
    }
end

return M
