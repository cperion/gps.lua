-- bench_json.lua — JSON decoding: raw recursive vs uvm family vs library decoders
--
-- Methodology notes:
--   * compare complete decode calls, not token-level internals
--   * keep UVM coarse-grained: one semantic step per document
--   * consume each result in the bench loop so calls are not dead work
--   * benchmark pvm.lower both hot (cache hit) and cold-miss variants
--
-- The JSON decoder uses FFI byte scanning (same technique as asdl_lexer).

package.path = "./.luarocks/share/lua/5.1/?.lua;./.luarocks/share/lua/5.1/?/init.lua;./?.lua;./?/init.lua;" .. package.path
package.cpath = "./.luarocks/lib/lua/5.1/?.so;./.luarocks/lib64/lua/5.1/?.so;" .. package.cpath

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local ffi = require("ffi")
local uvm = require("uvm")
local S = uvm.status

-- ══════════════════════════════════════════════════════════════
--  RAW JSON DECODER (recursive descent, FFI byte scanning)
-- ══════════════════════════════════════════════════════════════

local C_SPACE = 32; local C_TAB = 9; local C_NL = 10; local C_CR = 13
local C_QUOTE = 34; local C_BSLASH = 92
local C_LBRACE = 123; local C_RBRACE = 125
local C_LBRACK = 91; local C_RBRACK = 93
local C_COLON = 58; local C_COMMA = 44
local C_MINUS = 45; local C_PLUS = 43; local C_DOT = 46
local C_0 = 48; local C_9 = 57
local C_t = 116; local C_f = 102; local C_n = 110
local C_e = 101; local C_E = 69

local function is_ws(b) return b==C_SPACE or b==C_TAB or b==C_NL or b==C_CR end

local ESCAPES = {
    [110]="\n", [114]="\r", [116]="\t", [98]="\b", [102]="\f",
    [34]="\"", [92]="\\", [47]="/",
}

local decode_value -- forward

local function skip_ws(buf, pos, len)
    while pos < len and is_ws(buf[pos]) do pos = pos + 1 end
    return pos
end

local function decode_string(buf, pos, len, src)
    -- pos points at opening quote
    pos = pos + 1
    local start = pos
    local has_esc = false
    while pos < len do
        local b = buf[pos]
        if b == C_QUOTE then
            if not has_esc then
                return pos + 1, src:sub(start + 1, pos)
            else
                -- slow path: unescape
                local parts = {}
                local seg_start = start
                local i = start
                while i < pos do
                    if buf[i] == C_BSLASH then
                        parts[#parts+1] = src:sub(seg_start + 1, i)
                        i = i + 1
                        local esc = ESCAPES[buf[i]]
                        if esc then parts[#parts+1] = esc
                        else parts[#parts+1] = string.char(buf[i]) end
                        i = i + 1
                        seg_start = i
                    else
                        i = i + 1
                    end
                end
                parts[#parts+1] = src:sub(seg_start + 1, pos)
                return pos + 1, table.concat(parts)
            end
        elseif b == C_BSLASH then
            has_esc = true; pos = pos + 2
        else
            pos = pos + 1
        end
    end
    error("unterminated string")
end

local function decode_number(buf, pos, len, src)
    local start = pos
    if buf[pos] == C_MINUS then pos = pos + 1 end
    if buf[pos] == C_0 then pos = pos + 1
    else while pos < len and buf[pos] >= C_0 and buf[pos] <= C_9 do pos = pos + 1 end end
    if pos < len and buf[pos] == C_DOT then
        pos = pos + 1
        while pos < len and buf[pos] >= C_0 and buf[pos] <= C_9 do pos = pos + 1 end
    end
    if pos < len and (buf[pos] == C_e or buf[pos] == C_E) then
        pos = pos + 1
        if pos < len and (buf[pos] == C_PLUS or buf[pos] == C_MINUS) then pos = pos + 1 end
        while pos < len and buf[pos] >= C_0 and buf[pos] <= C_9 do pos = pos + 1 end
    end
    return pos, tonumber(src:sub(start + 1, pos))
end

function decode_value(buf, pos, len, src)
    pos = skip_ws(buf, pos, len)
    if pos >= len then error("unexpected end") end
    local b = buf[pos]

    if b == C_QUOTE then
        return decode_string(buf, pos, len, src)

    elseif b == C_LBRACE then
        pos = skip_ws(buf, pos + 1, len)
        local obj = {}
        if buf[pos] == C_RBRACE then return pos + 1, obj end
        while true do
            pos = skip_ws(buf, pos, len)
            local key; pos, key = decode_string(buf, pos, len, src)
            pos = skip_ws(buf, pos, len)
            pos = pos + 1 -- skip colon
            local val; pos, val = decode_value(buf, pos, len, src)
            obj[key] = val
            pos = skip_ws(buf, pos, len)
            if buf[pos] == C_RBRACE then return pos + 1, obj end
            pos = pos + 1 -- skip comma
        end

    elseif b == C_LBRACK then
        pos = skip_ws(buf, pos + 1, len)
        local arr = {}
        if buf[pos] == C_RBRACK then return pos + 1, arr end
        local n = 0
        while true do
            local val; pos, val = decode_value(buf, pos, len, src)
            n = n + 1; arr[n] = val
            pos = skip_ws(buf, pos, len)
            if buf[pos] == C_RBRACK then return pos + 1, arr end
            pos = pos + 1 -- skip comma
        end

    elseif b == C_t then -- true
        return pos + 4, true
    elseif b == C_f then -- false
        return pos + 5, false
    elseif b == C_n then -- null
        return pos + 4, nil

    elseif b == C_MINUS or (b >= C_0 and b <= C_9) then
        return decode_number(buf, pos, len, src)

    else
        error("unexpected char " .. string.char(b) .. " at " .. pos)
    end
end

local function json_decode_raw(src)
    return uvm.json.raw_decode(src)
end

-- ══════════════════════════════════════════════════════════════
--  UVM JSON DECODER (same code, wrapped as a family)
-- ══════════════════════════════════════════════════════════════

local json_family = uvm.json.decoder({ name = "json.decoder" })
local json_generated = uvm.json.generated({ spec = uvm.json.spec_table() })
local json_generated_family = uvm.json.generated_decoder({ name = "json.generated" })

local function json_decode_uvm(src)
    local m = json_family:spawn({ source = src })
    local status, val = m:step()
    return val
end

local function json_decode_generated(src)
    return json_generated.decode(src)
end

local function json_decode_uvm_generated(src)
    local m = json_generated_family:spawn({ source = src })
    local status, val = m:step()
    return val
end

-- ══════════════════════════════════════════════════════════════
--  PVM.LOWER JSON DECODER (memoized on string identity)
-- ══════════════════════════════════════════════════════════════

local pvm = require("pvm")
local json_lower = pvm.lower("json.decode", json_decode_raw)

-- ══════════════════════════════════════════════════════════════
--  TEST DATA
-- ══════════════════════════════════════════════════════════════

local function make_json(n_items)
    local parts = { "[" }
    for i = 1, n_items do
        if i > 1 then parts[#parts+1] = "," end
        parts[#parts+1] = string.format(
            '{"id":%d,"name":"item_%d","value":%.2f,"active":%s,"tags":["a","b","c"]}',
            i, i, i * 1.5, i % 2 == 0 and "true" or "false")
    end
    parts[#parts+1] = "]"
    return table.concat(parts)
end

local SMALL  = '{"a":1,"b":"hello","c":[1,2,3],"d":true,"e":null}'
local MEDIUM = make_json(100)
local LARGE  = make_json(1000)

-- ══════════════════════════════════════════════════════════════
--  VERIFY CORRECTNESS
-- ══════════════════════════════════════════════════════════════

local function deep_eq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local r1 = json_decode_raw(SMALL)
local r2 = json_decode_uvm(SMALL)
local r2g = json_decode_generated(SMALL)
local r2ug = json_decode_uvm_generated(SMALL)
assert(deep_eq(r1, r2), "small mismatch")
assert(deep_eq(r1, r2g), "small generated mismatch")
assert(deep_eq(r1, r2ug), "small uvm generated mismatch")

local r3 = json_decode_raw(MEDIUM)
local r4 = json_decode_uvm(MEDIUM)
local r4g = json_decode_generated(MEDIUM)
local r4ug = json_decode_uvm_generated(MEDIUM)
assert(deep_eq(r3, r4), "medium mismatch")
assert(deep_eq(r3, r4g), "medium generated mismatch")
assert(deep_eq(r3, r4ug), "medium uvm generated mismatch")

print("Correctness: OK\n")

-- ══════════════════════════════════════════════════════════════
--  BENCH
-- ══════════════════════════════════════════════════════════════

local has_cjson, cjson = pcall(require, "cjson")
local has_dkjson, dkjson = pcall(require, "dkjson")

local function bench_same(fn, input, N)
    local sink = 0
    for i = 1, math.min(N, 100) do sink = sink + (fn(input) and 1 or 0) end
    collectgarbage("collect"); collectgarbage("collect")
    local t0 = os.clock()
    for i = 1, N do sink = sink + (fn(input) and 1 or 0) end
    local elapsed = (os.clock() - t0) / N
    if sink == 0 then error("unreachable sink") end
    return elapsed
end

local function bench_miss_once(fn, inputs)
    local sink = 0
    collectgarbage("collect"); collectgarbage("collect")
    local t0 = os.clock()
    for i = 1, #inputs do sink = sink + (fn(inputs[i]) and 1 or 0) end
    local elapsed = (os.clock() - t0) / #inputs
    if sink == 0 then error("unreachable sink") end
    return elapsed
end

local function make_lower_miss_variants(input, count)
    local vars = {}
    for i = 1, count do vars[i] = input .. string.rep(" ", i) end
    return vars
end

local function run(label, input, N, cold_N)
    print(string.format("── %s (%d bytes) ──", label, #input))

    local t_raw = bench_same(json_decode_raw, input, N)
    local t_gen = bench_same(json_decode_generated, input, N)
    local t_uvm = bench_same(json_decode_uvm, input, N)
    local t_uvm_gen = bench_same(json_decode_uvm_generated, input, N)

    json_lower:reset()
    json_lower(input)
    local t_lower_hot = bench_same(function(s) return json_lower(s) end, input, N)

    json_lower:reset()
    local miss_variants = make_lower_miss_variants(input, cold_N)
    local t_lower_cold = bench_miss_once(function(s) return json_lower(s) end, miss_variants)

    print(string.format("  raw recursive:    %8.1fus", t_raw * 1e6))
    print(string.format("  generated raw:    %8.1fus  (%.2fx)", t_gen * 1e6, t_gen / t_raw))
    print(string.format("  uvm family:       %8.1fus  (%.2fx)", t_uvm * 1e6, t_uvm / t_raw))
    print(string.format("  uvm generated:    %8.1fus  (%.2fx)", t_uvm_gen * 1e6, t_uvm_gen / t_raw))
    print(string.format("  pvm.lower (miss): %8.1fus  (%.2fx)", t_lower_cold * 1e6, t_lower_cold / t_raw))
    print(string.format("  pvm.lower (hot):  %8.1fus  (%.0fx faster)", t_lower_hot * 1e6, t_raw / t_lower_hot))

    if has_cjson then
        local t_c = bench_same(cjson.decode, input, N)
        print(string.format("  cjson (C):        %8.1fus  (%.2fx)", t_c * 1e6, t_c / t_raw))
    end
    if has_dkjson then
        local t_dk = bench_same(dkjson.decode, input, N)
        print(string.format("  dkjson:           %8.1fus  (%.2fx)", t_dk * 1e6, t_dk / t_raw))
    end
    print()
end

print("JSON Decode Benchmark")
print(string.rep("═", 60))
run("small",  SMALL,  100000, 2000)
run("medium", MEDIUM, 10000, 500)
run("large",  LARGE,  1000, 100)

print("Summary:")
print("  raw = handwritten recursive Lua + FFI byte scanning")
print("  generated raw = Quote-generated JSON parser cached by JSON compile-spec / plan identity")
print("  uvm = same handwritten decoder wrapped in uvm.family (coarse: 1 step per document)")
print("  uvm generated = generated decoder wrapped in uvm.family")
print("  lower(miss) = pvm.lower on distinct-but-equivalent strings")
print("  lower(hot)  = pvm.lower cache hit on the same string")
if has_cjson then print("  cjson = lua-cjson C library") else print("  cjson = not installed") end
if has_dkjson then print("  dkjson = pure Lua JSON library") else print("  dkjson = not installed") end
