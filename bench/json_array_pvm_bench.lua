#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
package.path = "/home/cedric/.luarocks/share/lua/5.1/?.lua;/home/cedric/.luarocks/share/lua/5.1/?/init.lua;" .. package.path
package.cpath = "/home/cedric/.luarocks/lib64/lua/5.1/?.so;" .. package.cpath

local json = require("json")
local ok_cjson, cjson = pcall(require, "cjson")

local function bench_us(iters, fn)
    for _ = 1, math.min(20, iters) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    for _ = 1, iters do fn() end
    local dt = os.clock() - t0
    return dt * 1e6 / iters
end

local function gen_string_array(n)
    local out = {}
    for i = 1, n do
        out[i] = string.format('"v%d"', i)
    end
    return "[" .. table.concat(out, ",") .. "]"
end

local function gen_object_array(n)
    local out = {}
    for i = 1, n do
        out[i] = string.format('{"k":%d,"s":"v%d"}', i, i)
    end
    return "[" .. table.concat(out, ",") .. "]"
end

local cases = {
    { "str", gen_string_array },
    { "obj", gen_object_array },
}

print("json array benchmark")
print(string.format("%-8s  %-6s  %-10s  %-10s  %-10s  %-10s", "shape", "n", "pvm_parse", "pvm_emit", "cjson_p", "cjson_e"))
print(string.format("%-8s  %-6s  %-10s  %-10s  %-10s  %-10s", "--------", "------", "----------", "----------", "----------", "----------"))

for _, case in ipairs(cases) do
    local shape, gen = case[1], case[2]
    for _, n in ipairs({ 10, 100, 1000 }) do
        local src = gen(n)
        local iters = (n <= 100) and 2000 or 200

        local parse_us = bench_us(iters, function()
            json.parse_string(src)
        end)

        local value = json.parse_string(src)
        local emit_us = bench_us(iters, function()
            json.compact(value)
        end)

        local cparse_us, cemit_us = "-", "-"
        if ok_cjson then
            cparse_us = string.format("%.2f", bench_us(iters, function() cjson.decode(src) end))
            cemit_us = string.format("%.2f", bench_us(iters, function() cjson.encode(cjson.decode(src)) end))
        end

        print(string.format("%-8s  %-6d  %-10.2f  %-10.2f  %-10s  %-10s", shape, n, parse_us, emit_us, cparse_us, cemit_us))
    end
end
