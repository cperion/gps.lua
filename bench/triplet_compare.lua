#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local lib = require("bench.triplet_bench_lib")

local scenario_name = arg[1] or "all"
local n_arg = tonumber(arg[2])
local iters_arg = tonumber(arg[3])
local partial_arg = tonumber(arg[4])

local function format_rate(units, seconds)
    if seconds <= 0 then
        return "inf"
    end
    local rate = units / seconds
    if rate >= 1e9 then
        return string.format("%.2fG/s", rate / 1e9)
    elseif rate >= 1e6 then
        return string.format("%.2fM/s", rate / 1e6)
    elseif rate >= 1e3 then
        return string.format("%.2fk/s", rate / 1e3)
    end
    return string.format("%.2f/s", rate)
end

local function bench_impl(which, name, n, iters, partial)
    local T = lib.load_impl(which)
    local scenario = lib.get_scenario(name)
    local payload = lib.prepare(name, n, partial)

    collectgarbage("collect")
    collectgarbage("collect")
    local kb_before = collectgarbage("count")

    local checksum = 0
    local t0 = os.clock()
    for _ = 1, iters do
        checksum = checksum + lib.run_once(T, name, payload)
    end
    local elapsed = os.clock() - t0

    local kb_live = collectgarbage("count")
    collectgarbage("collect")
    collectgarbage("collect")
    local kb_postgc = collectgarbage("count")

    local units = lib.units_per_run(name, n, partial) * iters
    return {
        impl = which,
        scenario = name,
        label = scenario.label,
        n = n,
        iters = iters,
        partial = partial,
        checksum = checksum,
        seconds = elapsed,
        us_per_run = elapsed * 1e6 / iters,
        units = units,
        units_label = scenario.units_label,
        throughput = format_rate(units, elapsed),
        live_delta_kb = kb_live - kb_before,
        retained_delta_kb = kb_postgc - kb_before,
    }
end

local function print_result(r)
    print(string.format(
        "%-4s  %-24s  n=%-8d iters=%-8d us/run=%-10.2f throughput=%-10s live_kb=%-10.1f retained_kb=%-10.1f checksum=%s",
        r.impl,
        r.scenario,
        r.n,
        r.iters,
        r.us_per_run,
        r.throughput,
        r.live_delta_kb,
        r.retained_delta_kb,
        tostring(r.checksum)
    ))
end

local function print_delta(oldr, newr)
    local speedup = oldr.seconds / newr.seconds
    local live_ratio = (oldr.live_delta_kb ~= 0) and (newr.live_delta_kb / oldr.live_delta_kb) or 0
    print(string.format(
        "delta %-18s speedup(new/old)=%.3fx  live_kb(new/old)=%.3f  retained_kb(old=%.1f new=%.1f)",
        oldr.scenario,
        speedup,
        live_ratio,
        oldr.retained_delta_kb,
        newr.retained_delta_kb
    ))
end

local function run_one(name)
    local n = n_arg or lib.default_n(name)
    local iters = iters_arg or lib.default_iters(name)
    local partial = partial_arg or lib.default_partial(name)
    local label = lib.get_scenario(name).label

    print(string.rep("-", 120))
    print(string.format("scenario: %s  (%s)", name, label))
    if partial ~= nil then
        print(string.format("config: n=%d iters=%d partial=%d", n, iters, partial))
    else
        print(string.format("config: n=%d iters=%d", n, iters))
    end

    local oldr = bench_impl("old", name, n, iters, partial)
    local newr = bench_impl("new", name, n, iters, partial)

    print_result(oldr)
    print_result(newr)
    if lib.get_scenario(name).compare_checksum ~= false and oldr.checksum ~= newr.checksum then
        error(string.format("checksum mismatch for %s: old=%s new=%s", name, tostring(oldr.checksum), tostring(newr.checksum)))
    end
    print_delta(oldr, newr)
end

if scenario_name == "all" then
    print("triplet old vs new compare")
    for i = 1, #lib.scenario_order do
        run_one(lib.scenario_order[i])
    end
else
    run_one(scenario_name)
end
