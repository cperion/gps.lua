package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")
local fir = require("watjit.fir")

local cases = {
    {8, 4096, 200},
    {16, 4096, 200},
    {32, 4096, 120},
}

local function now_ms()
    return os.clock() * 1000.0
end

local function make_coeffs(taps)
    local coeffs = {}
    local sum = 0.0
    for i = 1, taps do
        local mid = (taps + 1) / 2.0
        local dist = math.abs(i - mid)
        local w = (mid - dist)
        coeffs[i] = w
        sum = sum + w
    end
    for i = 1, taps do
        coeffs[i] = coeffs[i] / sum
    end
    return coeffs
end

local function fill(ptr, n)
    for i = 0, n - 1 do
        ptr[i] = ((i * 11) % 23) * 0.125 - 1.0
    end
end

local function zero(ptr, n)
    ffi.fill(ptr, n * ffi.sizeof("double"), 0)
end

local function lua_fir(coeffs, x, y, n)
    local taps = #coeffs
    for i = taps - 1, n - 1 do
        local acc = 0.0
        for j = 0, taps - 1 do
            acc = acc + coeffs[j + 1] * x[i - j]
        end
        y[i] = acc
    end
end

local function bench_one(engine, coeffs, n, iters, fn)
    local layout = fir.layout(n, 8)

    local t_compile = now_ms()
    local inst = wj.module({ fn }, { memory_pages = wj.pages_for_bytes(layout.total_bytes) }):compile(engine)
    local compile_ms = now_ms() - t_compile

    local run = inst:fn(fn.name)
    local mem = inst:memory("memory", "double")
    local x = mem + (layout.x_offset / 8)
    local y = mem + (layout.y_offset / 8)
    local expect = ffi.new("double[?]", n)

    fill(x, n)
    zero(y, n)
    zero(expect, n)

    run(layout.x_offset, layout.y_offset, n)
    lua_fir(coeffs, x, expect, n)
    for i = 0, n - 1 do
        assert(math.abs(y[i] - expect[i]) < 1e-9)
    end

    local t_run = now_ms()
    for _ = 1, iters do
        run(layout.x_offset, layout.y_offset, n)
    end
    local run_ms = now_ms() - t_run

    return compile_ms, run_ms
end

local function bench_watjit()
    local engine = wm.engine()
    local out = {}
    for i = 1, #cases do
        local taps, n, iters = table.unpack(cases[i])
        local coeffs = make_coeffs(taps)
        local scalar_fn = fir.make(coeffs, wj.f64)
        local simd_fn = fir.make_simd(coeffs, wj.simd.f64x2)
        local scalar_cmp, scalar_run = bench_one(engine, coeffs, n, iters, scalar_fn)
        local simd_cmp, simd_run = bench_one(engine, coeffs, n, iters, simd_fn)
        out[string.format("%d/%d", taps, n)] = {
            scalar_compile_ms = scalar_cmp,
            scalar_run_ms = scalar_run,
            simd_compile_ms = simd_cmp,
            simd_run_ms = simd_run,
        }
    end
    return out
end

local function bench_terra()
    local pipe = assert(io.popen("terra ./watjit/terra_fir_bench.t", "r"))
    local text = pipe:read("*a")
    local ok, _, code = pipe:close()
    if ok == false or code ~= 0 then
        error("terra FIR benchmark failed:\n" .. text)
    end

    local out = {}
    for line in text:gmatch("[^\n]+") do
        local taps, n, first_ms, run_ms = line:match("^(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)$")
        if taps then
            out[string.format("%s/%s", taps, n)] = {
                first_ms = tonumber(first_ms),
                run_ms = tonumber(run_ms),
            }
        end
    end
    return out
end

local watjit_results = bench_watjit()
local terra_results = bench_terra()

print("watjit vs terra — FIR")
print(string.format("%-12s %10s %10s %10s %10s %10s %8s %8s", "case", "sc cmp", "sc run", "sd cmp", "sd run", "terra", "sc/t", "sd/t"))
print(string.rep("-", 92))
for i = 1, #cases do
    local taps, n = cases[i][1], cases[i][2]
    local key = string.format("%d/%d", taps, n)
    local w = assert(watjit_results[key])
    local t = assert(terra_results[key])
    print(string.format(
        "%-12s %10.3f %10.3f %10.3f %10.3f %10.3f %8.2fx %8.2fx",
        key,
        w.scalar_compile_ms,
        w.scalar_run_ms,
        w.simd_compile_ms,
        w.simd_run_ms,
        t.run_ms,
        w.scalar_run_ms / t.run_ms,
        w.simd_run_ms / t.run_ms
    ))
end

print()
print("sc = watjit scalar FIR")
print("sd = watjit SIMD FIR (f64x2)")
print("terra = terra steady-state runtime")
