-- bench_json4.lua — JSON decode with proper layering
--
-- GUIDE.md principle: each pass resolves one class of decision.
-- Each boundary between passes is an ASDL type.
--
-- Layer 0 → 1: bytes → JsonTok.Token*  (lexer resolves: what are the tokens?)
-- Layer 1 → 2: Token* → Json.Value     (parser resolves: what structure?)
--
-- Two ASDL types. Two uvm boundaries. Two cache points.
-- Interning at the token level deduplicates repeated keys/values.

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local ffi = require("ffi")
local uvm = require("uvm")
local pvm = require("pvm")
local S = uvm.status

-- ══════════════════════════════════════════════════════════════
--  ASDL LAYER 1: Tokens (what the lexer produces)
-- ══════════════════════════════════════════════════════════════

local T = pvm.context():Define [[
    module JsonTok {
        Token = LBrace | RBrace | LBrack | RBrack | Colon | Comma
              | Str(string value) unique
              | Num(number value) unique
              | True | False | Null
    }
]]

-- singletons (pointer-comparable, zero allocation)
local TOK_LBRACE = T.JsonTok.LBrace
local TOK_RBRACE = T.JsonTok.RBrace
local TOK_LBRACK = T.JsonTok.LBrack
local TOK_RBRACK = T.JsonTok.RBrack
local TOK_COLON  = T.JsonTok.Colon
local TOK_COMMA  = T.JsonTok.Comma
local TOK_TRUE   = T.JsonTok.True
local TOK_FALSE  = T.JsonTok.False
local TOK_NULL   = T.JsonTok.Null
local TOK_STR    = T.JsonTok.Str
local TOK_NUM    = T.JsonTok.Num

-- ══════════════════════════════════════════════════════════════
--  ASDL LAYER 2: Values (what the parser produces)
-- ══════════════════════════════════════════════════════════════

T:Define [[
    module Json {
        Value = Str(string value) unique
              | Num(number value) unique
              | Bool(boolean value) unique
              | Null
              | Arr(Json.Value* items) unique
              | Obj(Json.Pair* pairs) unique
        Pair = (string key, Json.Value value) unique
    }
]]

local JStr, JNum, JBool, JNull, JArr, JObj, JPair =
    T.Json.Str, T.Json.Num, T.Json.Bool, T.Json.Null, T.Json.Arr, T.Json.Obj, T.Json.Pair

-- ══════════════════════════════════════════════════════════════
--  PASS 1: bytes → Token*  (FFI byte scanning)
--
--  uvm stream family. Each step yields one token.
--  Or: batch function that produces the full token array.
--  The token array IS the ASDL intermediate — cached by pvm.lower.
-- ══════════════════════════════════════════════════════════════

local ESCAPES = {[110]="\n",[114]="\r",[116]="\t",[98]="\b",[102]="\f",[34]='"',[92]="\\",[47]="/"}

local function lex_string(buf, pos, len, src)
    pos = pos + 1; local st = pos; local esc = false
    while pos < len do
        if buf[pos] == 34 then
            if not esc then return pos + 1, src:sub(st + 1, pos) end
            local parts, seg, i = {}, st, st
            while i < pos do
                if buf[i] == 92 then parts[#parts+1] = src:sub(seg+1,i); i=i+1
                    local e = ESCAPES[buf[i]]; parts[#parts+1] = e or string.char(buf[i]); i=i+1; seg=i
                else i = i + 1 end
            end; parts[#parts+1] = src:sub(seg+1, pos); return pos + 1, table.concat(parts)
        elseif buf[pos] == 92 then esc = true; pos = pos + 2
        else pos = pos + 1 end
    end; error("unterminated string")
end

local function lex_number(buf, pos, len, src)
    local st = pos
    if buf[pos] == 45 then pos = pos + 1 end
    if buf[pos] == 48 then pos = pos + 1
    else while pos < len and buf[pos] >= 48 and buf[pos] <= 57 do pos = pos + 1 end end
    if pos < len and buf[pos] == 46 then pos = pos + 1
        while pos < len and buf[pos] >= 48 and buf[pos] <= 57 do pos = pos + 1 end end
    if pos < len and (buf[pos] == 101 or buf[pos] == 69) then pos = pos + 1
        if pos < len and (buf[pos] == 43 or buf[pos] == 45) then pos = pos + 1 end
        while pos < len and buf[pos] >= 48 and buf[pos] <= 57 do pos = pos + 1 end end
    return pos, tonumber(src:sub(st + 1, pos))
end

-- Batch lexer: bytes → Token array (interned tokens)
local function lex_json(src)
    local len = #src
    local buf = ffi.new("uint8_t[?]", len)
    ffi.copy(buf, src, len)

    local tokens = {}
    local n = 0
    local pos = 0

    while pos < len do
        local b = buf[pos]
        if b == 32 or b == 9 or b == 10 or b == 13 then
            pos = pos + 1
        elseif b == 123 then n=n+1; tokens[n] = TOK_LBRACE; pos = pos + 1
        elseif b == 125 then n=n+1; tokens[n] = TOK_RBRACE; pos = pos + 1
        elseif b == 91  then n=n+1; tokens[n] = TOK_LBRACK; pos = pos + 1
        elseif b == 93  then n=n+1; tokens[n] = TOK_RBRACK; pos = pos + 1
        elseif b == 58  then n=n+1; tokens[n] = TOK_COLON;  pos = pos + 1
        elseif b == 44  then n=n+1; tokens[n] = TOK_COMMA;  pos = pos + 1
        elseif b == 34 then
            local str; pos, str = lex_string(buf, pos, len, src)
            n=n+1; tokens[n] = TOK_STR(str)  -- interned!
        elseif b == 116 then n=n+1; tokens[n] = TOK_TRUE;  pos = pos + 4
        elseif b == 102 then n=n+1; tokens[n] = TOK_FALSE; pos = pos + 5
        elseif b == 110 then n=n+1; tokens[n] = TOK_NULL;  pos = pos + 4
        elseif b == 45 or (b >= 48 and b <= 57) then
            local num; pos, num = lex_number(buf, pos, len, src)
            n=n+1; tokens[n] = TOK_NUM(num)  -- interned!
        else
            error("unexpected byte " .. b .. " at " .. pos)
        end
    end

    return tokens
end

-- Memoized: same string → cached token array
local lex_lower = pvm.lower("lex", lex_json)

-- ══════════════════════════════════════════════════════════════
--  PASS 2: Token* → Json.Value  (recursive descent on token array)
--
--  No byte scanning. No FFI. Just walking an array of interned tokens.
--  Each token is already an ASDL node — pointer comparison for dispatch.
-- ══════════════════════════════════════════════════════════════

local parse_value -- forward

local function parse_value_at(tokens, pos)
    local tok = tokens[pos]
    local k = tok.kind

    if k == "Str" then
        return pos + 1, JStr(tok.value)

    elseif k == "Num" then
        return pos + 1, JNum(tok.value)

    elseif k == "True" then  return pos + 1, JBool(true)
    elseif k == "False" then return pos + 1, JBool(false)
    elseif k == "Null" then  return pos + 1, JNull

    elseif k == "LBrace" then
        pos = pos + 1
        if tokens[pos].kind == "RBrace" then return pos + 1, JObj({}) end
        local pairs = {}; local np = 0
        while true do
            local key = tokens[pos].value  -- must be Str
            pos = pos + 2  -- skip key + colon
            local val; pos, val = parse_value_at(tokens, pos)
            np = np + 1; pairs[np] = JPair(key, val)
            if tokens[pos].kind == "RBrace" then return pos + 1, JObj(pairs) end
            pos = pos + 1  -- skip comma
        end

    elseif k == "LBrack" then
        pos = pos + 1
        if tokens[pos].kind == "RBrack" then return pos + 1, JArr({}) end
        local items = {}; local ni = 0
        while true do
            local val; pos, val = parse_value_at(tokens, pos)
            ni = ni + 1; items[ni] = val
            if tokens[pos].kind == "RBrack" then return pos + 1, JArr(items) end
            pos = pos + 1  -- skip comma
        end

    else
        error("unexpected token kind: " .. tostring(k) .. " at position " .. pos)
    end
end

local function parse_tokens(tokens)
    local _, val = parse_value_at(tokens, 1)
    return val
end

-- Memoized: same token array → cached Json.Value
local parse_lower = pvm.lower("parse", parse_tokens)

-- ══════════════════════════════════════════════════════════════
--  FULL PIPELINE: string → tokens → value (two cached layers)
-- ══════════════════════════════════════════════════════════════

local function json_decode_layered(src)
    local tokens = lex_lower(src)      -- Layer 1: cached on string identity
    return parse_lower(tokens)          -- Layer 2: cached on token array identity
end

-- ══════════════════════════════════════════════════════════════
--  FUSED (single pass, for comparison — what bench_json3 did)
-- ══════════════════════════════════════════════════════════════

local shared_buf, shared_cap = nil, 0

local function fused_decode_value(b, p, n, s)
    while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end
    local c = b[p]
    if c == 34 then
        local str; p, str = lex_string(b, p, n, s); return p, JStr(str)
    elseif c == 123 then
        p=p+1; while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end
        if b[p]==125 then return p+1, JObj({}) end
        local pairs,np = {},0
        while true do
            while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end
            local key; p, key = lex_string(b, p, n, s)
            while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end; p=p+1
            local val; p, val = fused_decode_value(b, p, n, s)
            np=np+1; pairs[np] = JPair(key, val)
            while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end
            if b[p]==125 then return p+1, JObj(pairs) end; p=p+1
        end
    elseif c == 91 then
        p=p+1; while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end
        if b[p]==93 then return p+1, JArr({}) end
        local items,ni = {},0
        while true do
            local val; p, val = fused_decode_value(b, p, n, s)
            ni=ni+1; items[ni]=val
            while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end
            if b[p]==93 then return p+1, JArr(items) end; p=p+1
        end
    elseif c==116 then return p+4, JBool(true)
    elseif c==102 then return p+5, JBool(false)
    elseif c==110 then return p+4, JNull
    else local num; p, num = lex_number(b, p, n, s); return p, JNum(num) end
end

local function json_decode_fused(src)
    local n=#src
    if n>shared_cap then shared_buf=ffi.new("uint8_t[?]",n); shared_cap=n end
    ffi.copy(shared_buf, src, n)
    local _, v = fused_decode_value(shared_buf, 0, n, src); return v
end

-- ══════════════════════════════════════════════════════════════
--  TEST DATA
-- ══════════════════════════════════════════════════════════════

local function make_json(count)
    local p = {"["}
    for i=1,count do
        if i>1 then p[#p+1]="," end
        p[#p+1]=string.format('{"id":%d,"name":"item_%d","val":%.2f,"on":%s,"t":["a","b","c"]}',
            i, i, i*1.5, i%2==0 and "true" or "false")
    end; p[#p+1]="]"; return table.concat(p)
end

local SMALL  = '{"a":1,"b":"hello","c":[1,2,3],"d":true}'
local MEDIUM = make_json(100)
local LARGE  = make_json(1000)

-- ══════════════════════════════════════════════════════════════
--  VERIFY
-- ══════════════════════════════════════════════════════════════

local r1 = json_decode_fused(SMALL)
local r2 = json_decode_layered(SMALL)
assert(r1 == r2, "fused and layered should produce same interned result")

local r3 = json_decode_layered(SMALL)
assert(r2 == r3, "repeated layered should be same pointer (both layers cached)")

-- Token interning
local tokens = lex_json('{"a":1,"a":2}')
assert(tokens[1] == TOK_LBRACE, "token 1 should be LBrace singleton")
assert(tokens[2] == tokens[6], "repeated key 'a' should be same interned token")

-- Layered cache
lex_lower:reset(); parse_lower:reset()
json_decode_layered(MEDIUM)
json_decode_layered(MEDIUM)
print("lex_lower:   " .. pvm.report({lex_lower}))
print("parse_lower: " .. pvm.report({parse_lower}))
print()

print("Correctness + interning + layered caching: OK\n")

-- ══════════════════════════════════════════════════════════════
--  BENCH
-- ══════════════════════════════════════════════════════════════

local function bench(fn, input, N)
    for i=1,math.min(N,200) do fn(input) end
    collectgarbage("collect"); collectgarbage("collect")
    local t0=os.clock()
    for i=1,N do fn(input) end
    return (os.clock()-t0)/N
end

local function run(label, input, N)
    lex_lower:reset(); parse_lower:reset()

    local t_fused   = bench(json_decode_fused,   input, N)
    local t_layered = bench(json_decode_layered, input, N)

    -- Prime caches then measure hot
    lex_lower:reset(); parse_lower:reset()
    json_decode_layered(input)
    local t_hot = bench(json_decode_layered, input, N)

    -- Lex only
    lex_lower:reset()
    local t_lex = bench(function(s) return lex_lower(s) end, input, N)

    print(string.format("── %s (%d bytes) ──", label, #input))
    print(string.format("  fused (1 pass):     %8.1fus  (%5.1f MB/s)", t_fused*1e6, #input/t_fused/1e6))
    print(string.format("  layered (2 pass):   %8.1fus  (%5.1f MB/s)  %.2fx vs fused", t_layered*1e6, #input/t_layered/1e6, t_layered/t_fused))
    print(string.format("  layered (cached):   %8.1fus  (%.0fx vs fused)", t_hot*1e6, t_fused/t_hot))
    print(string.format("  lex only:           %8.1fus  (%.0f%% of layered)", t_lex*1e6, t_lex/t_layered*100))
    print()
end

print("JSON: fused (1 pass, bytes→ASDL) vs layered (2 pass, bytes→Token*→ASDL)")
print(string.rep("═", 75))
run("small",  SMALL,  100000)
run("medium", MEDIUM, 5000)
run("large",  LARGE,  500)

-- ══════════════════════════════════════════════════════════════
--  COLD BENCH (unique strings, no cache hits)
-- ══════════════════════════════════════════════════════════════

print("═══════════════════════════════════════════════════════════")
print("  COLD: unique strings each call (no cache)")
print("═══════════════════════════════════════════════════════════\n")

local function make_variants(base, N)
    local out = {}
    for i = 1, N do out[i] = base:gsub("1", tostring(10000+i), 1) end
    return out
end

local function bench_cold(fn, variants, N)
    for i = 1, math.min(100, N) do fn(variants[i]) end
    collectgarbage("collect"); collectgarbage("collect")
    local t0 = os.clock()
    for i = 1, N do fn(variants[((i-1) % #variants) + 1]) end
    return (os.clock() - t0) / N
end

for _, info in ipairs({
    { "small",  SMALL,  50000 },
    { "medium", MEDIUM, 3000 },
    { "large",  LARGE,  300 },
}) do
    local label, base, N = info[1], info[2], info[3]
    local vars = make_variants(base, math.min(N, 500))

    lex_lower:reset(); parse_lower:reset()
    local t_fused = bench_cold(json_decode_fused, vars, N)

    lex_lower:reset(); parse_lower:reset()
    local t_layered = bench_cold(json_decode_layered, vars, N)

    lex_lower:reset()
    local t_lex = bench_cold(lex_json, vars, N)

    print(string.format("  %-8s (%5dB)  fused: %7.1fus (%5.1f MB/s)  layered: %7.1fus (%5.1f MB/s)  ratio: %.2fx  lex: %.0f%%",
        label, #base,
        t_fused*1e6, #base/t_fused/1e6,
        t_layered*1e6, #base/t_layered/1e6,
        t_layered / t_fused,
        t_lex / t_layered * 100))
end
