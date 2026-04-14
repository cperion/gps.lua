#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local jp = require("jit.p")
local json = require("json")

local function gen_object(n)
    local out = {}
    for i = 1, n do
        out[i] = string.format('"k%d":{"x":%d,"y":[%d,%d,%d],"s":"v%d"}', i, i, i, i + 1, i + 2, i)
    end
    return "{" .. table.concat(out, ",") .. "}"
end

local n = tonumber(arg[1]) or 1000
local iters = tonumber(arg[2]) or 1500
local mode = arg[3] or "vf2i1m1"
local outfile = arg[4] or "./bench/json_parse_profile.out"

local src = gen_object(n)

jp.start(mode, outfile)
for _ = 1, iters do
    json.parse_string(src)
end
jp.stop()

print("wrote profile to", outfile)
