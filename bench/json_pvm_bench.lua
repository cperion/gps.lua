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
    return dt * 1e6 / iters, dt
end

local function gen_object(n)
    local out = {}
    for i = 1, n do
        out[i] = string.format('"k%d":[%d,%d,%d]', i, i, i + 1, i + 2)
    end
    return "{" .. table.concat(out, ",") .. "}"
end

for _, n in ipairs({ 10, 100, 1000 }) do
    local src = gen_object(n)
    local iters = (n <= 100) and 2000 or 200

    local parse_us = bench_us(iters, function()
        json.parse_string(src)
    end)

    local value = json.parse_string(src)
    local emit_us = bench_us(iters, function()
        json.compact(value)
    end)

    io.write(string.format("pvm-json object{%d} parse=%8.2fus emit=%8.2fus", n, parse_us, emit_us))

    if ok_cjson then
        local cparse_us = bench_us(iters, function() cjson.decode(src) end)
        local cemit_us = bench_us(iters, function() cjson.encode(cjson.decode(src)) end)
        io.write(string.format("  cjson parse=%8.2fus emit=%8.2fus", cparse_us, cemit_us))
    end

    io.write("\n")
end
