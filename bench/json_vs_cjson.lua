#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
package.path = "/home/cedric/.luarocks/share/lua/5.1/?.lua;/home/cedric/.luarocks/share/lua/5.1/?/init.lua;" .. package.path
package.cpath = "/home/cedric/.luarocks/lib64/lua/5.1/?.so;" .. package.cpath

local pvm = require("pvm")
local json = require("json")
local ok_cjson, cjson = pcall(require, "cjson")

local function bench_us(iters, fn)
    for _ = 1, math.min(20, iters) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    for _ = 1, iters do fn() end
    local dt = os.clock() - t0
    return dt * 1e6 / iters, dt
end

local function gen_object(n)
    local out = {}
    for i = 1, n do
        out[i] = string.format('"k%d":{"x":%d,"y":[%d,%d,%d],"s":"v%d"}', i, i, i, i + 1, i + 2, i)
    end
    return "{" .. table.concat(out, ",") .. "}"
end

local function run_case(n)
    local src = gen_object(n)
    local iters = (n <= 100) and 1000 or 100

    local parse_us = bench_us(iters, function()
        json.parse_string(src)
    end)

    local value = json.parse_string(src)
    local compact_us = bench_us(iters, function()
        json.compact(value)
    end)
    local pretty_us = bench_us(iters, function()
        json.pretty_string(value)
    end)
    local roundtrip_us = bench_us(iters, function()
        json.compact(json.parse_string(src))
    end)

    print(string.format(
        "pvm-json object{%d} parse=%8.2fus compact=%8.2fus pretty=%8.2fus parse+compact=%8.2fus",
        n, parse_us, compact_us, pretty_us, roundtrip_us
    ))

    if ok_cjson then
        local cparse_us = bench_us(iters, function()
            cjson.decode(src)
        end)
        local decoded = cjson.decode(src)
        local cencode_us = bench_us(iters, function()
            cjson.encode(decoded)
        end)
        local croundtrip_us = bench_us(iters, function()
            cjson.encode(cjson.decode(src))
        end)
        print(string.format(
            "cjson    object{%d} parse=%8.2fus compact=%8.2fus parse+compact=%8.2fus",
            n, cparse_us, cencode_us, croundtrip_us
        ))
    else
        print(string.format("cjson    object{%d} unavailable (module 'cjson' not found)", n))
    end
end

print("json vs cjson benchmark")
print("")
for _, n in ipairs({ 10, 100, 1000 }) do
    run_case(n)
    print("")
end

local a = json.parse_string(gen_object(200))
local b = json.parse_string(gen_object(200):gsub('"k137":%b{}', '"k137":{"x":999999,"y":[137,138,139],"s":"v137"}'))
json.compact(a)
json.compact(b)
json.pretty_string(a)
json.pretty_string(b)
print(pvm.report_string({ json.emit.compact_phase, json.pretty.phase }))
