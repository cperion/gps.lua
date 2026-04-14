#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local lib = require("bench.ui_bench_lib")

local ORDER = { "flat_list", "text_heavy", "nested_panels" }

local DEFAULTS = {
    flat_list = { n = lib.workloads.flat_list.default_n, iters = 120 },
    text_heavy = { n = lib.workloads.text_heavy.default_n, iters = 120 },
    nested_panels = { n = lib.workloads.nested_panels.default_n, iters = 80 },
}

local function bench_us(iters, fn)
    for _ = 1, math.min(20, iters) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    local last
    for _ = 1, iters do last = fn() end
    return (os.clock() - t0) * 1e6 / iters, last
end

local function ensure_clay_bench()
    local f = io.open("bench/clay_bench", "rb")
    if f then f:close(); return true end
    os.execute("cc -O2 -I./bench -o bench/clay_bench bench/clay_bench.c -lm >/dev/null 2>&1")
    f = io.open("bench/clay_bench", "rb")
    if f then f:close(); return true end
    return false
end

local function run_clay(workload, n, iters)
    local pipe = assert(io.popen(string.format("./bench/clay_bench %s %d %d 2>&1", workload, n, iters), "r"))
    local out = pipe:read("*a")
    pipe:close()

    for line in out:gmatch("[^\n]+") do
        local fields = {}
        for field in line:gmatch("%S+") do
            fields[#fields + 1] = field
        end
        if fields[1] == workload and #fields >= 5 then
            return {
                cmds = tonumber(fields[2]),
                total_ms = tonumber(fields[3]),
                per_us = tonumber(fields[4]),
                ips = tonumber(fields[5]),
                raw = out,
            }
        end
    end

    error("failed to parse clay output for " .. workload .. "\n" .. out)
end

local function build_inc_variants(workload_name, n)
    local changed_index = lib.changed_index(workload_name, n)
    local variant_count = math.max(16, math.min(64, n * (workload_name == "nested_panels" and 2 or 1)))
    local auth = {}
    for i = 1, variant_count do
        auth[i] = lib.build_auth(workload_name, n, changed_index, i)
    end
    local pos = 0
    return function()
        pos = pos + 1
        if pos > #auth then pos = 1 end
        return auth[pos]
    end
end

local function run_ui(workload_name, n, iters)
    local auth_base = lib.build_auth(workload_name, n, nil)
    local next_inc_auth = build_inc_variants(workload_name, n)

    lib.reset_phases()
    local layout_base = lib.lower_one(auth_base)
    local ops = lib.render_ops(layout_base)
    local op_count = #ops

    local build_us = bench_us(iters, function()
        lib.build_auth(workload_name, n, nil)
    end)

    local cold_us = bench_us(iters, function()
        lib.reset_phases()
        local auth = lib.build_auth(workload_name, n, nil)
        local layout = lib.lower_one(auth)
        lib.render_ops(layout)
    end)

    lib.reset_phases()
    do
        local layout = lib.lower_one(auth_base)
        lib.render_ops(layout)
    end
    local hot_us = bench_us(iters, function()
        local layout = lib.lower_one(auth_base)
        lib.render_ops(layout)
    end)

    lib.reset_phases()
    do
        local layout = lib.lower_one(auth_base)
        lib.render_ops(layout)
    end
    local inc_us = bench_us(iters, function()
        local layout = lib.lower_one(next_inc_auth())
        lib.render_ops(layout)
    end)

    return {
        build_us = build_us,
        cold_us = cold_us,
        hot_us = hot_us,
        inc_us = inc_us,
        ops = op_count,
        report = lib.report_string(),
    }
end

local function speedup_string(clay_us, ui_us)
    if not clay_us or not ui_us or clay_us <= 0 or ui_us <= 0 then return "n/a" end
    if ui_us < clay_us then
        return string.format("ui faster by %.1fx", clay_us / ui_us)
    end
    return string.format("clay faster by %.1fx", ui_us / clay_us)
end

local function run_one(workload_name, n, iters, have_clay)
    local ui = run_ui(workload_name, n, iters)
    local clay = have_clay and run_clay(workload_name, n, iters) or nil

    print(string.format("%s  n=%d  iters=%d", workload_name, n, iters))
    if clay then
        print(string.format("  clay frame          %9.2f us/op   cmds=%d", clay.per_us, clay.cmds))
    else
        print("  clay frame          unavailable (build bench/clay_bench first)")
    end
    print(string.format("  ui build_auth       %9.2f us/op", ui.build_us))
    print(string.format("  ui compile cold     %9.2f us/op   ops=%d", ui.cold_us, ui.ops))
    print(string.format("  ui compile hot      %9.2f us/op", ui.hot_us))
    print(string.format("  ui compile incr     %9.2f us/op", ui.inc_us))
    if clay then
        print(string.format("  cold comparison     %s", speedup_string(clay.per_us, ui.cold_us)))
        print(string.format("  hot comparison      %s", speedup_string(clay.per_us, ui.hot_us)))
        print(string.format("  incr comparison     %s", speedup_string(clay.per_us, ui.inc_us)))
    end
    print(ui.report)
    print("")
end

local workload_name = arg[1] or "all"
local n_override = tonumber(arg[2])
local iters_override = tonumber(arg[3])

local have_clay = ensure_clay_bench()

if workload_name ~= "all" then
    if not DEFAULTS[workload_name] then
        io.stderr:write("usage: luajit bench/ui_clay_compare.lua [all|flat_list|text_heavy|nested_panels] [n] [iters]\n")
        os.exit(1)
    end
    local spec = DEFAULTS[workload_name]
    run_one(workload_name, n_override or spec.n, iters_override or spec.iters, have_clay)
    os.exit(0)
end

print("ui vs clay.h (shared structural workloads, compiler-only on ui side)")
print("")
for i = 1, #ORDER do
    local name = ORDER[i]
    local spec = DEFAULTS[name]
    run_one(name, spec.n, spec.iters, have_clay)
end
