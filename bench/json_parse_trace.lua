#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local jit = require("jit")
local dump = require("jit.dump")
local json = require("json")

local function gen_object(n)
    local out = {}
    for i = 1, n do
        out[i] = string.format('"k%d":{"x":%d,"y":[%d,%d,%d],"s":"v%d"}', i, i, i, i + 1, i + 2, i)
    end
    return "{" .. table.concat(out, ",") .. "}"
end

local n = tonumber(arg[1]) or 50
local iters = tonumber(arg[2]) or 20
local mode = arg[3] or "tbis"
local outfile = arg[4] or "./bench/json_parse_trace.out"

local src = gen_object(n)

jit.opt.start("hotloop=1", "hotexit=1")
dump.start(mode, outfile)
for _ = 1, iters do
    json.parse_string(src)
end

print("wrote trace dump to", outfile)
