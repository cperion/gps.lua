#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local jit = require("jit")
local dump = require("jit.dump")
local lib = require("bench.triplet_bench_lib")

local which = arg[1] or "new"
local scenario_name = arg[2] or "drain_map_filter"
local n = tonumber(arg[3]) or lib.default_n(scenario_name)
local iters = tonumber(arg[4]) or 200
local partial = tonumber(arg[5]) or lib.default_partial(scenario_name)
local mode = arg[6] or "tbis"
local outfile = arg[7] or string.format("./bench/triplet_%s_%s.trace", which, scenario_name)

local T = lib.load_impl(which)
local payload = lib.prepare(scenario_name, n, partial)

local function run_once()
    return lib.run_once(T, scenario_name, payload)
end

run_once()
collectgarbage("collect")
collectgarbage("collect")

jit.opt.start("hotloop=1", "hotexit=1")
dump.start(mode, outfile)

local checksum = 0
for _ = 1, iters do
    checksum = checksum + run_once()
end

print(string.format(
    "wrote trace dump to %s  impl=%s scenario=%s n=%d iters=%d checksum=%s",
    outfile,
    which,
    scenario_name,
    n,
    iters,
    tostring(checksum)
))
