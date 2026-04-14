#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local jit = require("jit")
local dump = require("jit.dump")
local lib = require("bench.ui_bench_lib")

local workload = arg[1] or "flat_list"
local n = tonumber(arg[2]) or (lib.workloads[workload] and lib.workloads[workload].default_n) or 80
local iters = tonumber(arg[3]) or 200
local stage = arg[4] or "full"
local mode = arg[5] or "tbis"
local outfile = arg[6] or ("./bench/ui_hot_" .. workload .. "_" .. stage .. ".trace")

if not lib.workloads[workload] then
    io.stderr:write("usage: luajit bench/ui_hot_trace.lua [flat_list|text_heavy|nested_panels] [n] [iters] [full|lower|render] [jit.dump mode] [outfile]\n")
    os.exit(1)
end

local auth = lib.build_auth(workload, n, nil)

local function run_once()
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

lib.reset_phases()
run_once() -- warm once before tracing
collectgarbage(); collectgarbage()

jit.opt.start("hotloop=1", "hotexit=1")
dump.start(mode, outfile)
for _ = 1, iters do
    run_once()
end

print(string.format("wrote hot trace to %s  workload=%s n=%d iters=%d stage=%s", outfile, workload, n, iters, stage))
print(lib.report_string())
