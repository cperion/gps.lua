-- bench_json5.lua — three-layer JSON: bytes → Token* → Cmd* → for loop
--
-- Layer 0→1: bytes → Token*    (lex: resolves what are the tokens)
-- Layer 1→2: Token* → Cmd*     (parse: resolves structure, emits flat Begin/End)
-- Layer 2→∞: for loop + stack  (consume: no recursion)
--
-- Every layer is flatter than the last. The final consumer is one loop.

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local ffi = require("ffi")
local pvm = require("pvm")

-- ══════════════════════════════════════════════════════════════
--  ASDL LAYER 1: Tokens (flat, no recursion)
-- ══════════════════════════════════════════════════════════════

local T = pvm.context():Define [[
    module JsonTok {
        Kind = LBrace | RBrace | LBrack | RBrack | Colon | Comma
             | Str | Num | True | False | Null
        Token = (JsonTok.Kind kind, string sval, number nval) unique
    }
]]

local TK = T.JsonTok
local TK_LBRACE = TK.LBrace; local TK_RBRACE = TK.RBrace
local TK_LBRACK = TK.LBrack; local TK_RBRACK = TK.RBrack
local TK_COLON  = TK.Colon;  local TK_COMMA  = TK.Comma
local TK_STR    = TK.Str;    local TK_NUM    = TK.Num
local TK_TRUE   = TK.True;   local TK_FALSE  = TK.False
local TK_NULL   = TK.Null
local Token = TK.Token

-- pre-built singleton tokens (no string/number payload)
local TOK_LBRACE = Token(TK_LBRACE, "", 0)
local TOK_RBRACE = Token(TK_RBRACE, "", 0)
local TOK_LBRACK = Token(TK_LBRACK, "", 0)
local TOK_RBRACK = Token(TK_RBRACK, "", 0)
local TOK_COLON  = Token(TK_COLON,  "", 0)
local TOK_COMMA  = Token(TK_COMMA,  "", 0)
local TOK_TRUE   = Token(TK_TRUE,   "", 0)
local TOK_FALSE  = Token(TK_FALSE,  "", 0)
local TOK_NULL   = Token(TK_NULL,   "", 0)

-- ══════════════════════════════════════════════════════════════
--  ASDL LAYER 2: Commands (flat, no recursion, uniform shape)
-- ══════════════════════════════════════════════════════════════

T:Define [[
    module Json {
        Kind = BeginObj | EndObj | BeginArr | EndArr
             | Key | Str | Num | Bool | Null
        Cmd = (Json.Kind kind, string sval, number nval) unique
    }
]]

local JK = T.Json
local JK_BEGIN_OBJ = JK.BeginObj; local JK_END_OBJ = JK.EndObj
local JK_BEGIN_ARR = JK.BeginArr; local JK_END_ARR = JK.EndArr
local JK_KEY  = JK.Key;  local JK_STR  = JK.Str
local JK_NUM  = JK.Num;  local JK_BOOL = JK.Bool
local JK_NULL = JK.Null
local Cmd = JK.Cmd

-- pre-built singletons
local CMD_BEGIN_OBJ = Cmd(JK_BEGIN_OBJ, "", 0)
local CMD_END_OBJ   = Cmd(JK_END_OBJ,   "", 0)
local CMD_BEGIN_ARR = Cmd(JK_BEGIN_ARR, "", 0)
local CMD_END_ARR   = Cmd(JK_END_ARR,   "", 0)
local CMD_NULL      = Cmd(JK_NULL,       "", 0)
local CMD_TRUE      = Cmd(JK_BOOL,       "", 1)
local CMD_FALSE     = Cmd(JK_BOOL,       "", 0)

-- ══════════════════════════════════════════════════════════════
--  PASS 1: bytes → Token*  (FFI byte scanning)
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
                    local e = ESCAPES[buf[i]]; parts[#parts+1] = e or string.char(buf[i])
                    i=i+1; seg=i
                else i = i + 1 end
            end; parts[#parts+1] = src:sub(seg+1, pos)
            return pos + 1, table.concat(parts)
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

local function lex_json(src)
    local len = #src
    local buf = ffi.new("uint8_t[?]", len)
    ffi.copy(buf, src, len)
    local tokens, n = {}, 0
    local pos = 0
    while pos < len do
        local b = buf[pos]
        if b == 32 or b == 9 or b == 10 or b == 13 then pos = pos + 1
        elseif b == 123 then n=n+1; tokens[n]=TOK_LBRACE; pos=pos+1
        elseif b == 125 then n=n+1; tokens[n]=TOK_RBRACE; pos=pos+1
        elseif b == 91  then n=n+1; tokens[n]=TOK_LBRACK; pos=pos+1
        elseif b == 93  then n=n+1; tokens[n]=TOK_RBRACK; pos=pos+1
        elseif b == 58  then n=n+1; tokens[n]=TOK_COLON;  pos=pos+1
        elseif b == 44  then n=n+1; tokens[n]=TOK_COMMA;  pos=pos+1
        elseif b == 34 then
            local s; pos, s = lex_string(buf, pos, len, src)
            n=n+1; tokens[n] = Token(TK_STR, s, 0)
        elseif b == 116 then n=n+1; tokens[n]=TOK_TRUE;  pos=pos+4
        elseif b == 102 then n=n+1; tokens[n]=TOK_FALSE; pos=pos+5
        elseif b == 110 then n=n+1; tokens[n]=TOK_NULL;  pos=pos+4
        elseif b == 45 or (b >= 48 and b <= 57) then
            local v; pos, v = lex_number(buf, pos, len, src)
            n=n+1; tokens[n] = Token(TK_NUM, "", v)
        else error("unexpected byte " .. b) end
    end
    return tokens
end

local lex_lower = pvm.lower("lex", lex_json)

-- ══════════════════════════════════════════════════════════════
--  PASS 2: Token* → Cmd*  (recursive descent, emits flat commands)
--
--  The recursion in JSON structure is consumed HERE.
--  Output is flat Begin/End pairs. No Value* fields. No tree.
-- ══════════════════════════════════════════════════════════════

local parse_value -- forward

local function parse_value_at(tokens, pos, out, n)
    local tok = tokens[pos]
    local k = tok.kind

    if k == TK_STR then
        n=n+1; out[n] = Cmd(JK_STR, tok.sval, 0)
        return pos + 1, n

    elseif k == TK_NUM then
        n=n+1; out[n] = Cmd(JK_NUM, "", tok.nval)
        return pos + 1, n

    elseif k == TK_TRUE then  n=n+1; out[n]=CMD_TRUE;  return pos+1, n
    elseif k == TK_FALSE then n=n+1; out[n]=CMD_FALSE; return pos+1, n
    elseif k == TK_NULL then  n=n+1; out[n]=CMD_NULL;  return pos+1, n

    elseif k == TK_LBRACE then
        n=n+1; out[n] = CMD_BEGIN_OBJ
        pos = pos + 1
        if tokens[pos].kind == TK_RBRACE then
            n=n+1; out[n] = CMD_END_OBJ; return pos+1, n
        end
        while true do
            -- key
            n=n+1; out[n] = Cmd(JK_KEY, tokens[pos].sval, 0)
            pos = pos + 2  -- skip key + colon
            -- value
            pos, n = parse_value_at(tokens, pos, out, n)
            if tokens[pos].kind == TK_RBRACE then
                n=n+1; out[n] = CMD_END_OBJ; return pos+1, n
            end
            pos = pos + 1  -- comma
        end

    elseif k == TK_LBRACK then
        n=n+1; out[n] = CMD_BEGIN_ARR
        pos = pos + 1
        if tokens[pos].kind == TK_RBRACK then
            n=n+1; out[n] = CMD_END_ARR; return pos+1, n
        end
        while true do
            pos, n = parse_value_at(tokens, pos, out, n)
            if tokens[pos].kind == TK_RBRACK then
                n=n+1; out[n] = CMD_END_ARR; return pos+1, n
            end
            pos = pos + 1  -- comma
        end

    else error("unexpected token kind: " .. tostring(k)) end
end

local function parse_tokens(tokens)
    local out = {}
    local _, n = parse_value_at(tokens, 1, out, 0)
    return out
end

local parse_lower = pvm.lower("parse", parse_tokens)

-- ══════════════════════════════════════════════════════════════
--  CONSUMER: one for loop + stack → Lua tables
--  No recursion. Stack tracks nesting.
-- ══════════════════════════════════════════════════════════════

local function json_to_lua(cmds)
    local stack = {}
    local keys = {}   -- pending object keys
    local top = 0
    local root = nil

    local function push_value(val)
        if top == 0 then root = val; return end
        local parent = stack[top]
        if parent._is_arr then
            parent[#parent + 1] = val
        else
            local key = keys[top]
            keys[top] = nil
            parent[key] = val
        end
    end

    for i = 1, #cmds do
        local c = cmds[i]
        local k = c.kind

        if k == JK_BEGIN_OBJ then
            top = top + 1; stack[top] = {}

        elseif k == JK_END_OBJ then
            local obj = stack[top]; stack[top] = nil; top = top - 1
            push_value(obj)

        elseif k == JK_BEGIN_ARR then
            top = top + 1; local arr = {}; arr._is_arr = true; stack[top] = arr

        elseif k == JK_END_ARR then
            local arr = stack[top]; arr._is_arr = nil; stack[top] = nil; top = top - 1
            push_value(arr)

        elseif k == JK_KEY then
            keys[top] = c.sval

        elseif k == JK_STR then
            push_value(c.sval)

        elseif k == JK_NUM then
            push_value(c.nval)

        elseif k == JK_BOOL then
            push_value(c.nval == 1)

        elseif k == JK_NULL then
            push_value(nil)
        end
    end

    return root
end

-- ══════════════════════════════════════════════════════════════
--  FULL PIPELINE
-- ══════════════════════════════════════════════════════════════

local function json_decode_3layer(src)
    local tokens = lex_lower(src)
    local cmds = parse_lower(tokens)
    return json_to_lua(cmds)
end

-- ══════════════════════════════════════════════════════════════
--  FUSED BASELINE (single recursive pass → Lua tables, no ASDL)
-- ══════════════════════════════════════════════════════════════

local fused_decode

local shared_buf, shared_cap = nil, 0

function fused_decode(b, p, n, s)
    while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end
    local c = b[p]
    if c == 34 then return lex_string(b, p, n, s)
    elseif c == 123 then
        p = p+1; while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end
        local obj = {}
        if b[p] == 125 then return p+1, obj end
        while true do
            while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end
            local k; p, k = lex_string(b, p, n, s)
            while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end; p=p+1
            local v; p, v = fused_decode(b, p, n, s); obj[k] = v
            while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end
            if b[p] == 125 then return p+1, obj end; p=p+1
        end
    elseif c == 91 then
        p = p+1; while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end
        local arr, nn = {}, 0
        if b[p] == 93 then return p+1, arr end
        while true do
            local v; p, v = fused_decode(b, p, n, s); nn=nn+1; arr[nn]=v
            while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end
            if b[p] == 93 then return p+1, arr end; p=p+1
        end
    elseif c==116 then return p+4, true
    elseif c==102 then return p+5, false
    elseif c==110 then return p+4, nil
    else return lex_number(b, p, n, s) end
end

local function json_decode_fused(src)
    local n = #src
    if n > shared_cap then shared_buf = ffi.new("uint8_t[?]", n); shared_cap = n end
    ffi.copy(shared_buf, src, n)
    return select(2, fused_decode(shared_buf, 0, n, src))
end

-- ══════════════════════════════════════════════════════════════
--  VERIFY
-- ══════════════════════════════════════════════════════════════

local function deep_eq(a, b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end; return true
end

local SMALL  = '{"a":1,"b":"hello","c":[1,2,3],"d":true}'
local r_fused = json_decode_fused(SMALL)
local r_3layer = json_decode_3layer(SMALL)
assert(deep_eq(r_fused, r_3layer), "result mismatch")

-- check cmd stream
lex_lower:reset(); parse_lower:reset()
local toks = lex_json(SMALL)
local cmds = parse_tokens(toks)
print("Tokens:", #toks)
print("Commands:", #cmds)
for i = 1, #cmds do
    local c = cmds[i]
    print(string.format("  [%2d] %-10s s=%q n=%s", i, c.kind.kind, c.sval, tostring(c.nval)))
end
print()

-- cache test
lex_lower:reset(); parse_lower:reset()
json_decode_3layer(SMALL)
json_decode_3layer(SMALL)
print("lex:   " .. pvm.report({lex_lower}))
print("parse: " .. pvm.report({parse_lower}))
print()

print("Correctness: OK\n")

-- ══════════════════════════════════════════════════════════════
--  BENCH
-- ══════════════════════════════════════════════════════════════

local function make_json(count)
    local p = {"["}
    for i=1,count do
        if i>1 then p[#p+1]="," end
        p[#p+1]=string.format('{"id":%d,"name":"item_%d","val":%.2f,"on":%s,"t":["a","b","c"]}',
            i, i, i*1.5, i%2==0 and "true" or "false")
    end; p[#p+1]="]"; return table.concat(p)
end

local MEDIUM = make_json(100)
local LARGE  = make_json(1000)

-- Verify medium/large
assert(deep_eq(json_decode_fused(MEDIUM), json_decode_3layer(MEDIUM)), "medium mismatch")
assert(deep_eq(json_decode_fused(LARGE), json_decode_3layer(LARGE)), "large mismatch")

local function bench(fn, input, N)
    for i=1,math.min(N,200) do fn(input) end
    collectgarbage("collect"); collectgarbage("collect")
    local t0=os.clock()
    for i=1,N do fn(input) end
    return (os.clock()-t0)/N
end

local function make_variants(base, N)
    local out = {}
    for i=1,N do out[i]=base:gsub('"item_1"', '"item_1_'..i..'"', 1) end
    return out
end

local function bench_cold(fn, variants, N)
    for i=1,math.min(100,N) do fn(variants[i]) end
    collectgarbage("collect"); collectgarbage("collect")
    local t0=os.clock()
    for i=1,N do fn(variants[((i-1)%#variants)+1]) end
    return (os.clock()-t0)/N
end

print("═══════════════════════════════════════════════════════════════════")
print("  HOT (same string, cache hits for 3-layer)")
print("═══════════════════════════════════════════════════════════════════\n")

for _, info in ipairs({{"small",SMALL,100000},{"medium",MEDIUM,10000},{"large",LARGE,1000}}) do
    local label, input, N = info[1], info[2], info[3]
    local t_fused = bench(json_decode_fused, input, N)
    lex_lower:reset(); parse_lower:reset(); json_decode_3layer(input) -- prime
    local t_3layer = bench(json_decode_3layer, input, N)
    print(string.format("  %-8s fused: %7.1fus (%5.1f MB/s)  3-layer(cached): %7.1fus  (%.0fx)",
        label, t_fused*1e6, #input/t_fused/1e6, t_3layer*1e6, t_fused/t_3layer))
end

print("\n═══════════════════════════════════════════════════════════════════")
print("  COLD (unique strings, no cache)")
print("═══════════════════════════════════════════════════════════════════\n")

for _, info in ipairs({{"medium",MEDIUM,3000},{"large",LARGE,300}}) do
    local label, base, N = info[1], info[2], info[3]
    local vars = make_variants(base, math.min(N, 500))

    local t_fused = bench_cold(json_decode_fused, vars, N)

    lex_lower:reset(); parse_lower:reset()
    local t_3layer = bench_cold(json_decode_3layer, vars, N)

    -- measure each layer separately
    lex_lower:reset()
    local t_lex = bench_cold(lex_json, vars, N)

    local t_parse = bench_cold(function(s)
        return parse_tokens(lex_json(s))
    end, vars, N)

    local t_consume = bench_cold(function(s)
        return json_to_lua(parse_tokens(lex_json(s)))
    end, vars, N)

    print(string.format("  %-8s (%5dB)", label, #base))
    print(string.format("    fused (1 pass → tables):     %7.1fus  (%5.1f MB/s)", t_fused*1e6, #base/t_fused/1e6))
    print(string.format("    3-layer (lex+parse+consume): %7.1fus  (%5.1f MB/s)  %.1fx vs fused", t_3layer*1e6, #base/t_3layer/1e6, t_3layer/t_fused))
    print(string.format("      lex only:                  %7.1fus  (%.0f%%)", t_lex*1e6, t_lex/t_3layer*100))
    print(string.format("      lex+parse:                 %7.1fus  (%.0f%%)", t_parse*1e6, t_parse/t_3layer*100))
    print()
end
