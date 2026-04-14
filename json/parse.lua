-- json/parse.lua
--
-- Strict JSON parser.
--
-- This is a fused frontend parser, not a pvm phase. It parses directly into the
-- exact Json ASDL tree.
--
-- The object hot loop inlines next_kind and the string/member/object fast path
-- via quote.lua codegen, while construction goes through the ordinary public
-- JSON constructors. Complex/rare paths (escapes, numbers, arrays) remain as
-- regular functions.

local ffi = require("ffi")

local char = string.char
local concat = table.concat
local sub = string.sub
local floor = math.floor

local Quote = require("quote")
local schema = require("json.asdl")
local build = require("json.build")

local M = {}
local T = schema.T
M.T = T

-- Frontier kinds
local K_INVALID   = 0
local K_OBJ_BEGIN = 1
local K_OBJ_END   = 2
local K_ARR_BEGIN = 3
local K_ARR_END   = 4
local K_COLON     = 5
local K_COMMA     = 6
local K_STR       = 7
local K_NUM       = 8
local K_TRUE      = 9
local K_FALSE     = 10
local K_NULL      = 11
local K_END       = 12
local K_WS        = 13

-- String scanner byte classes
local S_NORMAL = 0
local S_QUOTE  = 1
local S_ESCAPE = 2
local S_CTRL   = 3

-- Frontier classifier table
local CHAR_KIND = ffi.new("uint8_t[256]")
for b = 0, 255 do
    CHAR_KIND[b] = K_INVALID
end
CHAR_KIND[123] = K_OBJ_BEGIN
CHAR_KIND[125] = K_OBJ_END
CHAR_KIND[91]  = K_ARR_BEGIN
CHAR_KIND[93]  = K_ARR_END
CHAR_KIND[58]  = K_COLON
CHAR_KIND[44]  = K_COMMA
CHAR_KIND[34]  = K_STR
CHAR_KIND[45]  = K_NUM
CHAR_KIND[32]  = K_WS
CHAR_KIND[9]   = K_WS
CHAR_KIND[10]  = K_WS
CHAR_KIND[13]  = K_WS
for b = 48, 57 do
    CHAR_KIND[b] = K_NUM
end
CHAR_KIND[116] = K_TRUE
CHAR_KIND[102] = K_FALSE
CHAR_KIND[110] = K_NULL

-- String scanner classifier
local STR_KIND = ffi.new("uint8_t[256]")
for b = 0, 255 do
    STR_KIND[b] = S_NORMAL
end
for b = 0, 31 do
    STR_KIND[b] = S_CTRL
end
STR_KIND[34] = S_QUOTE
STR_KIND[92] = S_ESCAPE

-- Hex digit lookup for unicode escapes
local hex_val = ffi.new("int16_t[256]")
for b = 0, 255 do
    hex_val[b] = -1
end
for b = 48, 57 do
    hex_val[b] = b - 48
end
for b = 65, 70 do
    hex_val[b] = b - 55
end
for b = 97, 102 do
    hex_val[b] = b - 87
end

-- Helper: parse 4-digit hex escape
local function parse_hex4(ptr, n, pos)
    if pos + 3 > n then
        return nil
    end
    local a = hex_val[ptr[pos - 1]]
    local b = hex_val[ptr[pos]]
    local c = hex_val[ptr[pos + 1]]
    local d = hex_val[ptr[pos + 2]]
    if a < 0 or b < 0 or c < 0 or d < 0 then
        return nil
    end
    return (((a * 16) + b) * 16 + c) * 16 + d
end

-- Helper: encode codepoint as UTF-8
local function utf8_encode_cp(cp)
    if cp < 0x80 then
        return char(cp)
    elseif cp < 0x800 then
        return char(
            0xC0 + floor(cp / 0x40),
            0x80 + (cp % 0x40)
        )
    elseif cp < 0x10000 then
        return char(
            0xE0 + floor(cp / 0x1000),
            0x80 + (floor(cp / 0x40) % 0x40),
            0x80 + (cp % 0x40)
        )
    end
    return char(
        0xF0 + floor(cp / 0x40000),
        0x80 + (floor(cp / 0x1000) % 0x40),
        0x80 + (floor(cp / 0x40) % 0x40),
        0x80 + (cp % 0x40)
    )
end

-------------------------------------------------------------------------------
-- Code-generate the parser.
--
-- Strategy: generate parse_object_node with inlined frontier classification and
-- string fast paths, while delegating exact-tree construction to json.build.
-- Arrays and scalars remain regular functions.
-------------------------------------------------------------------------------

local build_num = build.num
local build_str = build.str
local build_arr = build.arr
local build_obj_pairs = build.obj_pairs
local bool_true = build.TRUE
local bool_false = build.FALSE
local null_value = build.NULL

local function gen_object_parser()
    local q = Quote()

    local _CHAR_KIND = q:val(CHAR_KIND, "CHAR_KIND")
    local _STR_KIND  = q:val(STR_KIND, "STR_KIND")
    local _K_WS      = q:val(K_WS, "K_WS")
    local _K_OBJ_END = q:val(K_OBJ_END, "K_OBJ_END")
    local _K_COLON   = q:val(K_COLON, "K_COLON")
    local _K_COMMA   = q:val(K_COMMA, "K_COMMA")
    local _K_STR     = q:val(K_STR, "K_STR")
    local _K_END     = q:val(K_END, "K_END")
    local _S_NORMAL  = q:val(S_NORMAL, "S_NORMAL")
    local _S_QUOTE   = q:val(S_QUOTE, "S_QUOTE")
    local _S_ESCAPE  = q:val(S_ESCAPE, "S_ESCAPE")

    local _sub = q:val(sub, "sub")
    local _build_str = q:val(build_str, "build_str")
    local _build_obj_pairs = q:val(build_obj_pairs, "build_obj_pairs")

    q("return function(text, ptr, n, ib, parse_value, parse_string_raw, err)")
    q("  local i = ib[1] + 1")
    q("  local keys = {}")
    q("  local vals = {}")
    q("  local m = 0")
    q("  local j = i")
    q("  while j <= n do")
    q("    local ck = %s[ptr[j - 1]]", _CHAR_KIND)
    q("    if ck ~= %s then", _K_WS)
    q("      i = j")
    q("      if ck == %s then ib[1] = i + 1; return %s(keys, vals, 0) end", _K_OBJ_END, _build_obj_pairs)
    q("      if ck ~= %s then ib[1] = i; err(\"expected string key or '}'\") end", _K_STR)
    q("      break")
    q("    end")
    q("    j = j + 1")
    q("  end")
    q("")
    q("  while true do")
    q("    i = i + 1")
    q("    local seg = i; j = i")
    q("    local key")
    q("    while j <= n do")
    q("      local sk = %s[ptr[j - 1]]", _STR_KIND)
    q("      if sk == %s then j = j + 1", _S_NORMAL)
    q("      elseif sk == %s then", _S_QUOTE)
    q("        key = %s(text, seg, j - 1); i = j + 1; break", _sub)
    q("      elseif sk == %s then", _S_ESCAPE)
    q("        ib[1] = seg - 1; key = parse_string_raw(); i = ib[1]; break")
    q("      else ib[1] = j; err('control character in string') end")
    q("    end")
    q("    if not key then ib[1] = i; err('unterminated string') end")
    q("")
    q("    j = i")
    q("    while j <= n do")
    q("      local ck = %s[ptr[j - 1]]", _CHAR_KIND)
    q("      if ck ~= %s then", _K_WS)
    q("        if ck ~= %s then ib[1] = j; err(\"expected ':'\") end", _K_COLON)
    q("        i = j + 1; break")
    q("      end")
    q("      j = j + 1")
    q("    end")
    q("")
    q("    j = i; local vk = %s", _K_END)
    q("    while j <= n do")
    q("      vk = %s[ptr[j - 1]]", _CHAR_KIND)
    q("      if vk ~= %s then i = j; break end", _K_WS)
    q("      j = j + 1")
    q("    end")
    q("")
    q("    local val")
    q("    if vk == %s then", _K_STR)
    q("      i = i + 1; seg = i; j = i")
    q("      local raw")
    q("      while j <= n do")
    q("        local sk = %s[ptr[j - 1]]", _STR_KIND)
    q("        if sk == %s then j = j + 1", _S_NORMAL)
    q("        elseif sk == %s then", _S_QUOTE)
    q("          raw = %s(text, seg, j - 1); i = j + 1; break", _sub)
    q("        elseif sk == %s then", _S_ESCAPE)
    q("          ib[1] = seg - 1; raw = parse_string_raw(); i = ib[1]; break")
    q("        else ib[1] = j; err('control character in string') end")
    q("      end")
    q("      if not raw then ib[1] = i; err('unterminated string') end")
    q("      val = %s(raw)", _build_str)
    q("    else")
    q("      ib[1] = i; val = parse_value(vk); i = ib[1]")
    q("    end")
    q("")
    q("    m = m + 1")
    q("    keys[m] = key")
    q("    vals[m] = val")
    q("")
    q("    j = i")
    q("    while j <= n do")
    q("      local ck = %s[ptr[j - 1]]", _CHAR_KIND)
    q("      if ck ~= %s then", _K_WS)
    q("        if ck == %s then", _K_COMMA)
    q("          i = j + 1")
    q("          j = i")
    q("          while j <= n do")
    q("            ck = %s[ptr[j - 1]]", _CHAR_KIND)
    q("            if ck ~= %s then", _K_WS)
    q("              i = j")
    q("              if ck ~= %s then ib[1]=i; err(\"expected string key\") end", _K_STR)
    q("              break")
    q("            end")
    q("            j = j + 1")
    q("          end")
    q("          break")
    q("        elseif ck == %s then", _K_OBJ_END)
    q("          ib[1] = j + 1; return %s(keys, vals, m)", _build_obj_pairs)
    q("        else ib[1] = j; err(\"expected ',' or '}'\") end")
    q("      end")
    q("      j = j + 1")
    q("    end")
    q("  end")
    q("end")

    return q:compile("=(json.parse_object_gen)")
end

local parse_object_gen = gen_object_parser()

function M.parse(text)
    local i, n = 1, #text
    local ptr = ffi.cast("const uint8_t*", text)
    -- Shared cursor box for communicating with generated code
    local ib = {0}

    local function err(msg)
        error("json parse error at " .. tostring(ib[1] or i) .. ": " .. msg, 2)
    end

    local function next_kind()
        local j = i
        while j <= n do
            local k = CHAR_KIND[ptr[j - 1]]
            if k ~= K_WS then
                i = j
                return k
            end
            j = j + 1
        end
        i = j
        return K_END
    end

    local parse_value
    local parse_value_sync
    local parse_string_raw_sync

    local function parse_string_raw()
        i = i + 1 -- opening quote
        local seg = i
        local j = i
        local out = nil
        local o = 0

        while j <= n do
            local k = STR_KIND[ptr[j - 1]]
            if k == S_NORMAL then
                j = j + 1
            elseif k == S_QUOTE then
                local tail = sub(text, seg, j - 1)
                i = j + 1
                if out == nil then
                    return tail
                end
                if tail ~= "" then
                    o = o + 1
                    out[o] = tail
                end
                return concat(out)
            elseif k == S_ESCAPE then
                if out == nil then out = {} end
                if j > seg then
                    o = o + 1
                    out[o] = sub(text, seg, j - 1)
                end

                local esc = (j < n) and ptr[j] or nil
                if not esc then
                    i = j
                    err("unfinished escape")
                end

                if esc == 34 then
                    o = o + 1; out[o] = '"'; j = j + 2
                elseif esc == 92 then
                    o = o + 1; out[o] = "\\"; j = j + 2
                elseif esc == 47 then
                    o = o + 1; out[o] = "/"; j = j + 2
                elseif esc == 98 then
                    o = o + 1; out[o] = "\b"; j = j + 2
                elseif esc == 102 then
                    o = o + 1; out[o] = "\f"; j = j + 2
                elseif esc == 110 then
                    o = o + 1; out[o] = "\n"; j = j + 2
                elseif esc == 114 then
                    o = o + 1; out[o] = "\r"; j = j + 2
                elseif esc == 116 then
                    o = o + 1; out[o] = "\t"; j = j + 2
                elseif esc == 117 then
                    local cp = parse_hex4(ptr, n, j + 2)
                    if not cp then
                        i = j
                        err("invalid unicode escape")
                    end

                    local consumed = 6
                    if cp >= 0xD800 and cp <= 0xDBFF then
                        if j + 7 <= n and ptr[j + 5] == 92 and ptr[j + 6] == 117 then
                            local cp2 = parse_hex4(ptr, n, j + 8)
                            if cp2 and cp2 >= 0xDC00 and cp2 <= 0xDFFF then
                                cp = 0x10000 + ((cp - 0xD800) * 0x400) + (cp2 - 0xDC00)
                                consumed = 12
                            else
                                cp = 0xFFFD
                            end
                        else
                            cp = 0xFFFD
                        end
                    elseif cp >= 0xDC00 and cp <= 0xDFFF then
                        cp = 0xFFFD
                    end

                    o = o + 1
                    out[o] = utf8_encode_cp(cp)
                    j = j + consumed
                else
                    i = j
                    err("invalid escape")
                end
                seg = j
            else
                i = j
                err("control character in string")
            end
        end

        err("unterminated string")
    end

    local function parse_string_node_fast()
        i = i + 1 -- opening quote
        local seg = i
        local j = i

        while j <= n do
            local sk = STR_KIND[ptr[j - 1]]
            if sk == S_NORMAL then
                j = j + 1
            elseif sk == S_QUOTE then
                local raw = sub(text, seg, j - 1)
                i = j + 1
                return build_str(raw)
            elseif sk == S_ESCAPE then
                i = seg - 1
                local raw = parse_string_raw()
                return build_str(raw)
            else
                i = j
                err("control character in string")
            end
        end

        err("unterminated string")
    end

    local function parse_number_node()
        local start = i
        local c = ptr[i - 1]

        if c == 45 then
            i = i + 1
            c = (i <= n) and ptr[i - 1] or nil
        end

        if c == 48 then
            i = i + 1
        elseif c and c >= 49 and c <= 57 then
            i = i + 1
            while true do
                c = (i <= n) and ptr[i - 1] or nil
                if c and c >= 48 and c <= 57 then
                    i = i + 1
                else
                    break
                end
            end
        else
            err("invalid number")
        end

        c = (i <= n) and ptr[i - 1] or nil
        if c == 46 then
            i = i + 1
            c = (i <= n) and ptr[i - 1] or nil
            if not (c and c >= 48 and c <= 57) then
                err("invalid fraction")
            end
            while true do
                c = (i <= n) and ptr[i - 1] or nil
                if c and c >= 48 and c <= 57 then
                    i = i + 1
                else
                    break
                end
            end
        end

        c = (i <= n) and ptr[i - 1] or nil
        if c == 69 or c == 101 then
            i = i + 1
            c = (i <= n) and ptr[i - 1] or nil
            if c == 43 or c == 45 then
                i = i + 1
            end
            c = (i <= n) and ptr[i - 1] or nil
            if not (c and c >= 48 and c <= 57) then
                err("invalid exponent")
            end
            while true do
                c = (i <= n) and ptr[i - 1] or nil
                if c and c >= 48 and c <= 57 then
                    i = i + 1
                else
                    break
                end
            end
        end

        local lexeme = sub(text, start, i - 1)
        return build_num(lexeme)
    end

    local function parse_array_node()
        i = i + 1 -- [
        local items = {}
        local m = 0
        local k = next_kind()
        if k == K_ARR_END then
            i = i + 1
            return build_arr(items)
        end
        m = m + 1
        items[m] = (k == K_STR) and parse_string_node_fast() or parse_value(k)
        while true do
            k = next_kind()
            if k == K_COMMA then
                i = i + 1
                k = next_kind()
                m = m + 1
                items[m] = (k == K_STR) and parse_string_node_fast() or parse_value(k)
            elseif k == K_ARR_END then
                i = i + 1
                return build_arr(items)
            else
                err("expected ',' or ']' in array")
            end
        end
    end

    -- Wrappers for generated code to call recursive helpers with cursor sync
    function parse_value_sync(vk)
        i = ib[1]
        local val = parse_value(vk)
        ib[1] = i
        return val
    end

    function parse_string_raw_sync()
        i = ib[1]
        local raw = parse_string_raw()
        ib[1] = i
        return raw
    end

    local function parse_object_node()
        ib[1] = i
        local result = parse_object_gen(text, ptr, n, ib, parse_value_sync, parse_string_raw_sync, err)
        i = ib[1]
        return result
    end

    function parse_value(k)
        k = k or next_kind()

        if k == K_STR then
            return parse_string_node_fast()
        elseif k == K_OBJ_BEGIN then
            return parse_object_node()
        elseif k == K_ARR_BEGIN then
            return parse_array_node()
        elseif k == K_TRUE and i + 3 <= n and ptr[i] == 114 and ptr[i + 1] == 117 and ptr[i + 2] == 101 then
            i = i + 4
            return bool_true
        elseif k == K_FALSE and i + 4 <= n and ptr[i] == 97 and ptr[i + 1] == 108 and ptr[i + 2] == 115 and ptr[i + 3] == 101 then
            i = i + 5
            return bool_false
        elseif k == K_NULL and i + 3 <= n and ptr[i] == 117 and ptr[i + 1] == 108 and ptr[i + 2] == 108 then
            i = i + 4
            return null_value
        elseif k == K_NUM then
            return parse_number_node()
        elseif k == K_END then
            err("unexpected end of input")
        end

        err("unexpected token")
    end

    local value = parse_value(next_kind())
    if next_kind() ~= K_END then
        err("trailing characters")
    end
    return value
end

return M
