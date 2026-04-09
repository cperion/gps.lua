-- bench_json3.lua — JSON decode into ASDL types via uvm
--
-- Methodology notes:
--   * compare whole-document decode calls
--   * include result construction cost (tables or ASDL nodes)
--   * consume each result in the benchmark loop via a sink
--   * treat pvm.lower(cached) as a memoization benchmark, not parser throughput
--
-- ASDL defines the JSON IR, uvm decodes into it,
-- interning deduplicates identical subtrees, pvm.lower caches.

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local ffi = require("ffi")
local lpeg = require("lpeg")
local uvm = require("uvm")
local pvm = require("pvm")
local S = uvm.status

-- ══════════════════════════════════════════════════════════════
--  ASDL: JSON value types (interned via unique)
-- ══════════════════════════════════════════════════════════════

local T = pvm.context():Define [[
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
--  FFI JSON → ASDL decoder
-- ══════════════════════════════════════════════════════════════

local ESCAPES = {[110]="\n",[114]="\r",[116]="\t",[98]="\b",[102]="\f",[34]='"',[92]="\\",[47]="/"}

local decode_value

local function skip_ws(b, p, n)
    while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end; return p
end

local function decode_string_raw(b, p, n, s)
    p=p+1; local st=p; local esc=false
    while p<n do
        if b[p]==34 then
            if not esc then return p+1, s:sub(st+1, p) end
            local parts, seg, i = {}, st, st
            while i<p do
                if b[i]==92 then parts[#parts+1]=s:sub(seg+1,i); i=i+1
                    local e=ESCAPES[b[i]]; parts[#parts+1]=e or string.char(b[i]); i=i+1; seg=i
                else i=i+1 end
            end; parts[#parts+1]=s:sub(seg+1,p); return p+1, table.concat(parts)
        elseif b[p]==92 then esc=true; p=p+2 else p=p+1 end
    end; error("unterminated string")
end

local function decode_number_raw(b, p, n, s)
    local st=p
    if b[p]==45 then p=p+1 end
    if b[p]==48 then p=p+1 else while p<n and b[p]>=48 and b[p]<=57 do p=p+1 end end
    if p<n and b[p]==46 then p=p+1; while p<n and b[p]>=48 and b[p]<=57 do p=p+1 end end
    if p<n and (b[p]==101 or b[p]==69) then p=p+1
        if p<n and (b[p]==43 or b[p]==45) then p=p+1 end
        while p<n and b[p]>=48 and b[p]<=57 do p=p+1 end end
    return p, tonumber(s:sub(st+1, p))
end

-- Decode into ASDL Json.Value (interned)
function decode_value(b, p, n, s)
    p = skip_ws(b,p,n); local c = b[p]
    if c == 34 then
        local str; p, str = decode_string_raw(b, p, n, s)
        return p, JStr(str)
    elseif c == 123 then -- {
        p = skip_ws(b, p+1, n)
        if b[p] == 125 then return p+1, JObj({}) end
        local pairs = {}; local np = 0
        while true do
            p = skip_ws(b, p, n)
            local key; p, key = decode_string_raw(b, p, n, s)
            p = skip_ws(b, p, n); p = p + 1 -- colon
            local val; p, val = decode_value(b, p, n, s)
            np = np + 1; pairs[np] = JPair(key, val)
            p = skip_ws(b, p, n)
            if b[p] == 125 then return p+1, JObj(pairs) end
            p = p + 1 -- comma
        end
    elseif c == 91 then -- [
        p = skip_ws(b, p+1, n)
        if b[p] == 93 then return p+1, JArr({}) end
        local items = {}; local ni = 0
        while true do
            local val; p, val = decode_value(b, p, n, s)
            ni = ni + 1; items[ni] = val
            p = skip_ws(b, p, n)
            if b[p] == 93 then return p+1, JArr(items) end
            p = p + 1
        end
    elseif c == 116 then return p+4, JBool(true)
    elseif c == 102 then return p+5, JBool(false)
    elseif c == 110 then return p+4, JNull
    else
        local num; p, num = decode_number_raw(b, p, n, s)
        return p, JNum(num)
    end
end

-- Raw entry point
local function json_decode_asdl(src)
    return uvm.json.raw_decode_asdl(src, { types = T })
end

-- ══════════════════════════════════════════════════════════════
--  UVM FAMILY: JSON decoder as a machine
-- ══════════════════════════════════════════════════════════════

local json_family = uvm.json.asdl_decoder({ name = "json.asdl", types = T })
local json_generated = uvm.json.generated({ spec = uvm.json.spec_asdl({ types = T }) })
local json_generated_family = uvm.json.generated_asdl_decoder({ name = "json.asdl.generated", types = T })

local function json_decode_uvm(src)
    local m = json_family:spawn({ source = src })
    local _, val = m:step()
    return val
end

local function json_decode_generated(src)
    return json_generated.decode(src)
end

local function json_decode_uvm_generated(src)
    local m = json_generated_family:spawn({ source = src })
    local _, val = m:step()
    return val
end

-- ══════════════════════════════════════════════════════════════
--  PVM.LOWER: memoized on string identity
-- ══════════════════════════════════════════════════════════════

local json_lower = pvm.lower("json.asdl", json_decode_asdl)

-- ══════════════════════════════════════════════════════════════
--  PLAIN TABLE decoder (for comparison — no ASDL, no interning)
-- ══════════════════════════════════════════════════════════════

local decode_plain

function decode_plain(b, p, n, s)
    p = skip_ws(b,p,n); local c = b[p]
    if c == 34 then return decode_string_raw(b, p, n, s)
    elseif c == 123 then
        p = skip_ws(b, p+1, n); local obj = {}
        if b[p] == 125 then return p+1, obj end
        while true do
            p = skip_ws(b, p, n); local k; p, k = decode_string_raw(b, p, n, s)
            p = skip_ws(b, p, n); p = p + 1
            local v; p, v = decode_plain(b, p, n, s); obj[k] = v
            p = skip_ws(b, p, n)
            if b[p] == 125 then return p+1, obj end; p = p + 1
        end
    elseif c == 91 then
        p = skip_ws(b, p+1, n); local arr, nn = {}, 0
        if b[p] == 93 then return p+1, arr end
        while true do
            local v; p, v = decode_plain(b, p, n, s); nn=nn+1; arr[nn]=v
            p = skip_ws(b, p, n)
            if b[p] == 93 then return p+1, arr end; p = p + 1
        end
    elseif c == 116 then return p+4, true
    elseif c == 102 then return p+5, false
    elseif c == 110 then return p+4, nil
    else return decode_number_raw(b, p, n, s) end
end

local shared_buf, shared_cap = nil, 0
local function json_decode_plain(src)
    local n = #src
    if n > shared_cap then shared_buf = ffi.new("uint8_t[?]", n); shared_cap = n end
    ffi.copy(shared_buf, src, n)
    local _, v = decode_plain(shared_buf, 0, n, src)
    return v
end

-- ══════════════════════════════════════════════════════════════
--  LPEG decoder (plain tables, for baseline)
-- ══════════════════════════════════════════════════════════════

local P, R, Sl, C, Cs, Cp = lpeg.P, lpeg.R, lpeg.S, lpeg.C, lpeg.Cs, lpeg.Cp
local ws_skip = (Sl(" \t\n\r")^0 * Cp())
local esc_map = {['"']='"',['\\']='\\',['/']=    '/',['b']='\b',['f']='\f',['n']='\n',['r']='\r',['t']='\t'}
local lpeg_str = P('"') * Cs((P('\\') * C(P(1)) / esc_map + (1 - P('"')))^0) * P('"') * Cp()
local lpeg_num = C(P('-')^-1 * (P('0') + R('19') * R('09')^0) * (P('.') * R('09')^1)^-1 * (Sl('eE') * Sl('+-')^-1 * R('09')^1)^-1) / tonumber * Cp()
local ws_colon = Sl(" \t\n\r")^0 * P(':') * Sl(" \t\n\r")^0 * Cp()

local function lpeg_decode(src, pos)
    pos = ws_skip:match(src, pos) or pos; local ch = src:byte(pos)
    if ch == 34 then return lpeg_str:match(src, pos)
    elseif ch == 123 then
        pos = ws_skip:match(src, pos+1) or (pos+1); local obj = {}
        if src:byte(pos) == 125 then return obj, pos+1 end
        while true do
            pos = ws_skip:match(src, pos) or pos
            local k, ak = lpeg_str:match(src, pos); pos = ws_colon:match(src, ak)
            local v; v, pos = lpeg_decode(src, pos); obj[k] = v
            pos = ws_skip:match(src, pos) or pos
            if src:byte(pos) == 125 then return obj, pos+1 end; pos = pos+1 end
    elseif ch == 91 then
        pos = ws_skip:match(src, pos+1) or (pos+1); local arr, n = {}, 0
        if src:byte(pos) == 93 then return arr, pos+1 end
        while true do
            local v; v, pos = lpeg_decode(src, pos); n=n+1; arr[n]=v
            pos = ws_skip:match(src, pos) or pos
            if src:byte(pos) == 93 then return arr, pos+1 end; pos = pos+1 end
    elseif ch == 116 then return true, pos+4
    elseif ch == 102 then return false, pos+5
    elseif ch == 110 then return nil, pos+4
    else return lpeg_num:match(src, pos) end
end

local function json_decode_lpeg(src) return (lpeg_decode(src, 1)) end

-- ══════════════════════════════════════════════════════════════
--  TEST DATA
-- ══════════════════════════════════════════════════════════════

local function make_json(n)
    local p = {"["}
    for i=1,n do
        if i>1 then p[#p+1]="," end
        p[#p+1]=string.format('{"id":%d,"name":"item_%d","val":%.2f,"on":%s,"t":["a","b","c"]}',
            i, i, i*1.5, i%2==0 and "true" or "false")
    end; p[#p+1]="]"; return table.concat(p)
end

local SMALL  = '{"a":1,"b":"hello","c":[1,2,3],"d":true}'
local MEDIUM = make_json(100)
local LARGE  = make_json(1000)

-- Verify ASDL decoder
local r = json_decode_asdl(SMALL)
assert(r.kind == "Obj")
assert(r.pairs[1].key == "a" and r.pairs[1].value.kind == "Num" and r.pairs[1].value.value == 1)
assert(r.pairs[2].value.kind == "Str" and r.pairs[2].value.value == "hello")

-- Verify interning: same JSON → same ASDL pointer
local r2 = json_decode_asdl(SMALL)
assert(r == r2, "ASDL interning: same input should give same pointer")

-- Verify uvm gives same result
local r3 = json_decode_uvm(SMALL)
assert(r == r3, "uvm should give same interned result")
local r3g = json_decode_generated(SMALL)
assert(r == r3g, "generated decoder should give same interned result")
local r3ug = json_decode_uvm_generated(SMALL)
assert(r == r3ug, "uvm generated decoder should give same interned result")

-- Verify lower cache
json_lower:reset()
local r4 = json_lower(SMALL)
local r5 = json_lower(SMALL)
assert(r4 == r5, "lower cache should return same pointer")
assert(json_lower:stats().hits == 1, "should have 1 cache hit")

print("Correctness + interning + caching: OK\n")

-- Show interning benefit on repeated data
local rep_json = '{"tags":["a","b","c"],"more_tags":["a","b","c"],"val":true,"val2":true}'
local rep_r = json_decode_asdl(rep_json)
-- The two ["a","b","c"] arrays should be the same pointer (interned)
local arr1 = rep_r.pairs[1].value
local arr2 = rep_r.pairs[2].value
print("Interning: identical arrays same pointer:", arr1 == arr2)
print("Interning: identical bools same pointer:", rep_r.pairs[3].value == rep_r.pairs[4].value)
print()

-- ══════════════════════════════════════════════════════════════
--  BENCH
-- ══════════════════════════════════════════════════════════════

local function bench(fn, input, N)
    local sink = 0
    for i=1,math.min(N,200) do sink = sink + (fn(input) and 1 or 0) end
    collectgarbage("collect"); collectgarbage("collect")
    local t0=os.clock()
    for i=1,N do sink = sink + (fn(input) and 1 or 0) end
    local elapsed = (os.clock()-t0)/N
    if sink == 0 then error("unreachable sink") end
    return elapsed
end

local function run(label, input, N)
    local t_lpeg   = bench(json_decode_lpeg,          input, N)
    local t_plain  = bench(json_decode_plain,         input, N)
    local t_asdl   = bench(json_decode_asdl,          input, N)
    local t_gen    = bench(json_decode_generated,     input, N)
    local t_uvm    = bench(json_decode_uvm,           input, N)
    local t_uvm_g  = bench(json_decode_uvm_generated, input, N)

    json_lower:reset(); json_lower(input) -- prime
    local t_lower = bench(function(s) return json_lower(s) end, input, N)

    print(string.format("── %s (%d bytes) ──", label, #input))
    print(string.format("  lpeg → tables:       %8.1fus  (%5.1f MB/s)", t_lpeg*1e6, #input/t_lpeg/1e6))
    print(string.format("  ffi → tables:        %8.1fus  (%5.1f MB/s)  %.1fx vs lpeg", t_plain*1e6, #input/t_plain/1e6, t_lpeg/t_plain))
    print(string.format("  ffi → ASDL:          %8.1fus  (%5.1f MB/s)  %.1fx vs lpeg", t_asdl*1e6, #input/t_asdl/1e6, t_lpeg/t_asdl))
    print(string.format("  generated → ASDL:    %8.1fus  (%5.1f MB/s)  %.1fx vs lpeg", t_gen*1e6, #input/t_gen/1e6, t_lpeg/t_gen))
    print(string.format("  uvm → ASDL:          %8.1fus  (%5.1f MB/s)  %.1fx vs lpeg", t_uvm*1e6, #input/t_uvm/1e6, t_lpeg/t_uvm))
    print(string.format("  uvm gen → ASDL:      %8.1fus  (%5.1f MB/s)  %.1fx vs lpeg", t_uvm_g*1e6, #input/t_uvm_g/1e6, t_lpeg/t_uvm_g))
    print(string.format("  pvm.lower (cached):  %8.1fus  (%.0fx vs raw)", t_lower*1e6, t_asdl/t_lower))
    print()
end

print("JSON Decode: lpeg vs FFI→tables vs FFI→ASDL vs uvm→ASDL vs cached")
print(string.rep("═", 70))
run("small",  SMALL,  200000)
run("medium", MEDIUM, 10000)
run("large",  LARGE,  1000)
print("Notes:")
print("  ffi / generated / uvm paths are decode-throughput comparisons")
print("  generated paths are Quote-generated parsers cached by JSON compile-spec / plan identity")
print("  pvm.lower (cached) is a same-input cache-hit comparison, not parse throughput")
