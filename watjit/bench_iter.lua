package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")
local ok_ffi, ffi = pcall(require, "ffi")
local ok_wm, wm = pcall(require, "watjit.wasmtime")

local S = wj.stream
local I = wj.iter
local i32 = wj.i32

local function now_ms()
    return os.clock() * 1000.0
end

local function bench_ms(iters, fn)
    local t0 = now_ms()
    for _ = 1, iters do
        fn()
    end
    return now_ms() - t0
end

local function warm(fn, n)
    n = n or 10
    for _ = 1, n do
        fn()
    end
end

local function print_case(name, ms, iters)
    print(string.format("%-28s %10.3f ms total   %10.3f us/iter", name, ms, ms * 1000.0 / iters))
end

local function sum_table(t, n)
    local acc = 0
    for i = 1, n do
        acc = acc + t[i]
    end
    return acc
end

local function map_filter_table_sum(t, n)
    local acc = 0
    for i = 1, n do
        local v = (t[i] + 1) * 2
        if v > 10 and (v % 3) ~= 0 then
            acc = acc + v
        end
    end
    return acc
end

local function build_table_data(n)
    local t = {}
    for i = 1, n do
        t[i] = ((i * 17) % 29) - 7
    end
    return t
end

local function run_compiled_bench(n, iters)
    if not ok_wm then
        print("watjit iter bench — compiled bench skipped (wasmtime unavailable)")
        return
    end

    local sum_fn = I.compile_sum {
        name = "bench_iter_sum",
        params = { i32 "x_base", i32 "n" },
        ret = i32,
        build = function(x_base, n_)
            return S.seq(i32, x_base, n_)
        end,
    }

    local filter_sum_fn = I.compile_sum {
        name = "bench_iter_filter_sum",
        params = { i32 "x_base", i32 "n" },
        ret = i32,
        build = function(x_base, n_)
            return S.seq(i32, x_base, n_)
                :map(i32, function(v) return (v + i32(1)) * i32(2) end)
                :filter(function(v) return v:gt(10) end)
                :filter(function(v) return (v % i32(3)):ne(0) end)
        end,
    }

    local mod = wj.module({ sum_fn, filter_sum_fn }, { memory_pages = wj.pages_for_bytes(n * 4) })
    local inst = mod:compile(wm.engine())
    local run_sum = inst:fn("bench_iter_sum")
    local run_filter_sum = inst:fn("bench_iter_filter_sum")
    local mem = inst:memory("memory", "int32_t")
    local tbl = build_table_data(n)
    for i = 0, n - 1 do
        mem[i] = tbl[i + 1]
    end

    assert(run_sum(0, n) == sum_table(tbl, n))
    assert(run_filter_sum(0, n) == map_filter_table_sum(tbl, n))

    local function lua_sum_fn()
        return sum_table(tbl, n)
    end
    local function iter_sum_fn()
        return run_sum(0, n)
    end
    local function lua_filter_fn()
        return map_filter_table_sum(tbl, n)
    end
    local function iter_filter_fn()
        return run_filter_sum(0, n)
    end

    warm(lua_sum_fn)
    warm(iter_sum_fn)
    warm(lua_filter_fn)
    warm(iter_filter_fn)

    print(string.format("watjit iter bench — compiled traversal algebra (n=%d, iters=%d)", n, iters))
    print_case("lua sum", bench_ms(iters, lua_sum_fn), iters)
    print_case("compiled iter sum", bench_ms(iters, iter_sum_fn), iters)
    print_case("lua map+filter+sum", bench_ms(iters, lua_filter_fn), iters)
    print_case("compiled fused iter", bench_ms(iters, iter_filter_fn), iters)
end

local n = tonumber(arg and arg[1]) or 32768
local iters = tonumber(arg and arg[2]) or 400
run_compiled_bench(n, iters)
