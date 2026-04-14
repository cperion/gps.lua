#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local lib = require("bench.ui_bench_lib")

local function bench_us(iters, fn)
    for _ = 1, math.min(20, iters) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    for _ = 1, iters do fn() end
    return (os.clock() - t0) * 1e6 / iters
end

local workload_name = arg[1] or "flat_list"
local workload = lib.workloads[workload_name]
if not workload then
    io.stderr:write("usage: luajit bench/ui_bench.lua [flat_list|text_heavy|nested_panels] [n] [iters]\n")
    os.exit(1)
end

local n = tonumber(arg[2]) or workload.default_n
local iters = tonumber(arg[3]) or 400
local changed_index = lib.changed_index(workload_name, n)
local inc_variant_count = math.max(16, math.min(64, n * (workload_name == "nested_panels" and 2 or 1)))

local auth_base = lib.build_auth(workload_name, n, nil)
local auth_inc = {}
for i = 1, inc_variant_count do
    auth_inc[i] = lib.build_auth(workload_name, n, changed_index, i)
end
local inc_pos = 0
local function next_inc_auth()
    inc_pos = inc_pos + 1
    if inc_pos > #auth_inc then inc_pos = 1 end
    return auth_inc[inc_pos]
end

local layout_base = lib.lower_one(auth_base)
local op_count = #lib.render_ops(layout_base)

local build_us = bench_us(iters, function()
    lib.build_auth(workload_name, n, nil)
end)

local lower_cold = bench_us(iters, function()
    lib.reset_phases()
    lib.lower_one(auth_base)
end)

lib.reset_phases()
lib.lower_one(auth_base)
local lower_hot = bench_us(iters, function()
    lib.lower_one(auth_base)
end)

lib.reset_phases()
lib.lower_one(auth_base)
local lower_inc = bench_us(iters, function()
    lib.lower_one(next_inc_auth())
end)

lib.reset_phases()
local render_cold = bench_us(iters, function()
    lib.reset_phases()
    local layout = lib.lower_one(auth_base)
    lib.render_ops(layout)
end)

lib.reset_phases()
lib.full_run(auth_base)
local render_hot = bench_us(iters, function()
    local layout = lib.lower_one(auth_base)
    lib.render_ops(layout)
end)

lib.reset_phases()
lib.full_run(auth_base)
local render_inc = bench_us(iters, function()
    local layout = lib.lower_one(next_inc_auth())
    lib.render_ops(layout)
end)

lib.reset_phases()
local full_cold = bench_us(iters, function()
    lib.reset_phases()
    lib.full_run(auth_base)
end)

lib.reset_phases()
lib.full_run(auth_base)
local full_hot = bench_us(iters, function()
    lib.full_run(auth_base)
end)

lib.reset_phases()
lib.full_run(auth_base)
local full_inc = bench_us(iters, function()
    lib.full_run(next_inc_auth())
end)

print(string.format("ui bench: %s n=%d iters=%d", workload_name, n, iters))
print(string.format("auth nodes: built immediate tree; render ops=%d", op_count))
print("")
print(string.format("build_auth          %9.2f us/op", build_us))
print(string.format("lower cold          %9.2f us/op", lower_cold))
print(string.format("lower hot           %9.2f us/op", lower_hot))
print(string.format("lower incremental   %9.2f us/op", lower_inc))
print(string.format("render cold         %9.2f us/op", render_cold))
print(string.format("render hot          %9.2f us/op", render_hot))
print(string.format("render incremental  %9.2f us/op", render_inc))
print(string.format("full cold           %9.2f us/op", full_cold))
print(string.format("full hot            %9.2f us/op", full_hot))
print(string.format("full incremental    %9.2f us/op", full_inc))
print("")
print(lib.report_string())
