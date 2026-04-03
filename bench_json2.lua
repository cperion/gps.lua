-- bench_json2.lua — FFI recursive descent vs lpeg-driven JSON

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local ffi = require("ffi")
local lpeg = require("lpeg")
local P, R, S, C, Cs, Cp = lpeg.P, lpeg.R, lpeg.S, lpeg.C, lpeg.Cs, lpeg.Cp

-- ══════════════════════════════════════════════════════════════
--  LPEG JSON (lpeg for tokenization, Lua for tree building)
-- ══════════════════════════════════════════════════════════════

local ws_skip = (S(" \t\n\r")^0 * Cp())

local esc_map = {['"']='"',['\\']='\\',['/']=    '/',['b']='\b',['f']='\f',['n']='\n',['r']='\r',['t']='\t'}
local lpeg_str = P('"') * Cs((P('\\') * C(P(1)) / esc_map + (1 - P('"')))^0) * P('"') * Cp()
local lpeg_num = C(P('-')^-1 * (P('0') + R('19') * R('09')^0) * (P('.') * R('09')^1)^-1 * (S('eE') * S('+-')^-1 * R('09')^1)^-1) / tonumber * Cp()
local ws_colon = S(" \t\n\r")^0 * P(':') * S(" \t\n\r")^0 * Cp()

local function lpeg_decode(src, pos)
    pos = ws_skip:match(src, pos) or pos
    local ch = src:byte(pos)
    if ch == 34 then -- "
        return lpeg_str:match(src, pos)
    elseif ch == 123 then -- {
        pos = ws_skip:match(src, pos + 1) or (pos + 1)
        local obj = {}
        if src:byte(pos) == 125 then return obj, pos + 1 end
        while true do
            pos = ws_skip:match(src, pos) or pos
            local key, after_key = lpeg_str:match(src, pos)
            pos = ws_colon:match(src, after_key)
            local val; val, pos = lpeg_decode(src, pos)
            obj[key] = val
            pos = ws_skip:match(src, pos) or pos
            local b = src:byte(pos)
            if b == 125 then return obj, pos + 1 end
            pos = pos + 1 -- comma
        end
    elseif ch == 91 then -- [
        pos = ws_skip:match(src, pos + 1) or (pos + 1)
        local arr, n = {}, 0
        if src:byte(pos) == 93 then return arr, pos + 1 end
        while true do
            local val; val, pos = lpeg_decode(src, pos)
            n = n + 1; arr[n] = val
            pos = ws_skip:match(src, pos) or pos
            if src:byte(pos) == 93 then return arr, pos + 1 end
            pos = pos + 1
        end
    elseif ch == 116 then return true, pos + 4
    elseif ch == 102 then return false, pos + 5
    elseif ch == 110 then return nil, pos + 4
    else return lpeg_num:match(src, pos)
    end
end

local function json_decode_lpeg(src)
    return (lpeg_decode(src, 1))
end

-- ══════════════════════════════════════════════════════════════
--  FFI JSON (same as before — recursive descent on byte buffer)
-- ══════════════════════════════════════════════════════════════

local ESCAPES = {[110]="\n",[114]="\r",[116]="\t",[98]="\b",[102]="\f",[34]='"',[92]="\\",[47]="/"}
local decode_value

local function skip_ws(b, p, n)
    while p<n and (b[p]==32 or b[p]==9 or b[p]==10 or b[p]==13) do p=p+1 end; return p end

local function decode_string(b, p, n, s)
    p=p+1; local st=p; local esc=false
    while p<n do
        if b[p]==34 then
            if not esc then return p+1, s:sub(st+1,p) end
            local parts,seg,i = {},st,st
            while i<p do
                if b[i]==92 then parts[#parts+1]=s:sub(seg+1,i); i=i+1
                    local e=ESCAPES[b[i]]; parts[#parts+1]=e or string.char(b[i]); i=i+1; seg=i
                else i=i+1 end
            end; parts[#parts+1]=s:sub(seg+1,p); return p+1, table.concat(parts)
        elseif b[p]==92 then esc=true; p=p+2 else p=p+1 end
    end; error("unterminated string")
end

local function decode_number(b, p, n, s)
    local st=p
    if b[p]==45 then p=p+1 end
    if b[p]==48 then p=p+1 else while p<n and b[p]>=48 and b[p]<=57 do p=p+1 end end
    if p<n and b[p]==46 then p=p+1; while p<n and b[p]>=48 and b[p]<=57 do p=p+1 end end
    if p<n and (b[p]==101 or b[p]==69) then p=p+1
        if p<n and (b[p]==43 or b[p]==45) then p=p+1 end
        while p<n and b[p]>=48 and b[p]<=57 do p=p+1 end end
    return p, tonumber(s:sub(st+1,p))
end

function decode_value(b, p, n, s)
    p = skip_ws(b,p,n); local c=b[p]
    if c==34 then return decode_string(b,p,n,s)
    elseif c==123 then
        p=skip_ws(b,p+1,n); local obj={}
        if b[p]==125 then return p+1, obj end
        while true do
            p=skip_ws(b,p,n); local k; p,k=decode_string(b,p,n,s)
            p=skip_ws(b,p,n); p=p+1; local v; p,v=decode_value(b,p,n,s)
            obj[k]=v; p=skip_ws(b,p,n)
            if b[p]==125 then return p+1, obj end; p=p+1 end
    elseif c==91 then
        p=skip_ws(b,p+1,n); local arr,nn={},0
        if b[p]==93 then return p+1, arr end
        while true do
            local v; p,v=decode_value(b,p,n,s); nn=nn+1; arr[nn]=v
            p=skip_ws(b,p,n)
            if b[p]==93 then return p+1, arr end; p=p+1 end
    elseif c==116 then return p+4, true
    elseif c==102 then return p+5, false
    elseif c==110 then return p+4, nil
    else return decode_number(b,p,n,s) end
end

local shared_buf, shared_cap = nil, 0
local function json_decode_ffi(src)
    local n=#src
    if n>shared_cap then shared_buf=ffi.new("uint8_t[?]",n); shared_cap=n end
    ffi.copy(shared_buf, src, n)
    local _,v = decode_value(shared_buf, 0, n, src); return v
end

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

-- verify
local function deep_eq(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not deep_eq(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end; return true
end

assert(deep_eq(json_decode_lpeg(SMALL), json_decode_ffi(SMALL)), "small mismatch")
assert(deep_eq(json_decode_lpeg(MEDIUM), json_decode_ffi(MEDIUM)), "medium mismatch")
print("Correctness: OK\n")

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
    local t_lpeg = bench(json_decode_lpeg, input, N)
    local t_ffi  = bench(json_decode_ffi, input, N)
    local mb_lpeg = #input / t_lpeg / 1e6
    local mb_ffi  = #input / t_ffi / 1e6
    print(string.format("%-8s (%6d bytes)  lpeg: %7.1fus (%5.1f MB/s)  ffi: %7.1fus (%5.1f MB/s)  ffi/lpeg: %.2fx",
        label, #input, t_lpeg*1e6, mb_lpeg, t_ffi*1e6, mb_ffi, t_ffi/t_lpeg))
end

print("JSON Decode: lpeg vs FFI recursive descent")
print(string.rep("=", 95))
run("small",  SMALL,  200000)
run("medium", MEDIUM, 20000)
run("large",  LARGE,  2000)
