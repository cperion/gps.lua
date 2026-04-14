package.path = "./?.lua;./?/init.lua;" .. package.path

local X = require("experiments.traversal_stage")

local clock = os.clock
local fmt = string.format

local function bench(run, warm, reps)
    for _ = 1, warm do run() end
    collectgarbage("collect")
    local t0 = clock()
    for _ = 1, reps do run() end
    local t1 = clock()
    return (t1 - t0) * 1e6 / reps
end

local function sum_array(t)
    local s = 0
    for i = 1, #t do s = s + t[i] end
    return s
end

local function make_array(n)
    local t = {}
    for i = 1, n do t[i] = i end
    return t
end

local function print_row(cols, widths)
    local out = {}
    for i = 1, #cols do
        out[i] = fmt("%-" .. widths[i] .. "s", tostring(cols[i]))
    end
    print(table.concat(out, "  "))
end

local function run_case(name, desc, warm, reps)
    local compiled = X.compile_drain(desc)
    local interp_out = X.drain(desc)
    local compiled_out = compiled()
    assert(#interp_out == #compiled_out)
    assert(sum_array(interp_out) == sum_array(compiled_out))

    local interp_us = bench(function()
        local out = X.drain(desc)
        return out[1]
    end, warm, reps)

    local compiled_us = bench(function()
        local out = compiled()
        return out[1]
    end, warm, reps)

    local compile_us = bench(function()
        local fn = X.compile_drain(desc)
        return fn
    end, 3, math.max(10, math.floor(reps / 20)))

    return {
        name = name,
        out_n = #interp_out,
        interp_us = interp_us,
        compiled_us = compiled_us,
        compile_us = compile_us,
        speedup = interp_us / compiled_us,
        breakeven_runs = (interp_us > compiled_us) and (compile_us / (interp_us - compiled_us)) or math.huge,
        src_bytes = #X.compile_drain_source(desc),
        checksum = sum_array(interp_out),
    }
end

local function suite_for_n(n)
    local base = make_array(n)

    return {
        run_case(
            "seq",
            X.seq(base),
            200, 2000
        ),
        run_case(
            "map",
            X.map("times2", function(v) return v * 2 end,
                X.seq(base)
            ),
            200, 2000
        ),
        run_case(
            "map+filter",
            X.filter("keep_div4", function(v) return v % 4 == 0 end,
                X.map("times2", function(v) return v * 2 end,
                    X.seq(base)
                )
            ),
            200, 2000
        ),
        run_case(
            "concat",
            X.concat(
                X.filter("keep_div4", function(v) return v % 4 == 0 end,
                    X.map("times2", function(v) return v * 2 end,
                        X.seq(base)
                    )
                ),
                X.map("plus1", function(v) return v + 1 end,
                    X.seq(base)
                )
            ),
            200, 2000
        ),
    }
end

local function print_suite(n)
    local rows = suite_for_n(n)
    print()
    print("N=" .. n)
    print_row(
        { "case", "out", "interp_us", "compiled_us", "speedup", "compile_us", "break_even", "src_bytes", "checksum" },
        { 12, 6, 12, 12, 8, 12, 12, 10, 10 }
    )
    print_row(
        { string.rep("-", 12), string.rep("-", 6), string.rep("-", 12), string.rep("-", 12), string.rep("-", 8), string.rep("-", 12), string.rep("-", 12), string.rep("-", 10), string.rep("-", 10) },
        { 12, 6, 12, 12, 8, 12, 12, 10, 10 }
    )
    for _, row in ipairs(rows) do
        print_row({
            row.name,
            row.out_n,
            fmt("%.2f", row.interp_us),
            fmt("%.2f", row.compiled_us),
            fmt("%.2fx", row.speedup),
            fmt("%.2f", row.compile_us),
            fmt("%.2f", row.breakeven_runs),
            row.src_bytes,
            row.checksum,
        }, { 12, 6, 12, 12, 8, 12, 12, 10, 10 })
    end
end

print("traversal_stage microbench")
print("interpret vs staged residual execution")
print_suite(100)
print_suite(1000)
