#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local jp = require("jit.p")
local lib = require("bench.ui_bench_lib")

local workload = arg[1] or "flat_list"
local n = tonumber(arg[2]) or (lib.workloads[workload] and lib.workloads[workload].default_n) or 200
local iters = tonumber(arg[3]) or 200
local stage = arg[4] or "full"
local mode = arg[5] or "vf2i1m1"
local outfile = arg[6] or ("./bench/ui_cold_" .. workload .. "_" .. stage .. ".out")

if not lib.workloads[workload] then
    io.stderr:write("usage: luajit bench/ui_cold_profile.lua [flat_list|text_heavy|nested_panels] [n] [iters] [full|lower|render] [jit.p mode] [outfile]\n")
    os.exit(1)
end

local auth = lib.build_auth(workload, n, nil)

local function run_once()
    lib.reset_phases()
    if stage == "lower" then
        lib.lower_one(auth)
        return
    end
    if stage == "render" then
        local layout = lib.lower_one(auth)
        lib.render_ops(layout)
        return
    end
    if stage == "full" then
        lib.full_run(auth)
        return
    end
    error("unknown stage: " .. tostring(stage))
end

jp.start(mode, outfile)
for _ = 1, iters do
    run_once()
end
jp.stop()

print(string.format("wrote cold profile to %s  workload=%s n=%d iters=%d stage=%s", outfile, workload, n, iters, stage))
print(lib.report_string())
