package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")
local matmul = require("watjit.matmul")

local cases = {
    {16, 16, 16, 200},
    {32, 32, 32, 80},
    {64, 64, 64, 10},
}

local function now_ms()
    return os.clock() * 1000.0
end

local function fill(ptr, n)
    for i = 0, n - 1 do
        ptr[i] = ((i * 13) % 17) * 0.25 - 2.0
    end
end

local function zero(ptr, n)
    ffi.fill(ptr, n * ffi.sizeof("double"), 0)
end

local function lua_matmul(a, b, c, M, N, K)
    for i = 0, M - 1 do
        for j = 0, N - 1 do
            local sum = 0.0
            for k = 0, K - 1 do
                sum = sum + a[i * K + k] * b[k * N + j]
            end
            c[i * N + j] = sum
        end
    end
end

local function bench_one(engine, fn, M, N, K, iters)
    local layout = matmul.layout(M, N, K, 8)

    local t_compile = now_ms()
    local inst = wj.module({ fn }, { memory_pages = wj.pages_for_bytes(layout.total_bytes) }):compile(engine)
    local compile_ms = now_ms() - t_compile

    local run = inst:fn(fn.name)
    local mem = inst:memory("memory", "double")
    local wa = mem + (layout.a_offset / 8)
    local wb = mem + (layout.b_offset / 8)
    local wc = mem + (layout.c_offset / 8)
    local expect = ffi.new("double[?]", layout.c_elems)

    fill(wa, layout.a_elems)
    fill(wb, layout.b_elems)
    zero(wc, layout.c_elems)
    zero(expect, layout.c_elems)

    run(layout.a_offset, layout.b_offset, layout.c_offset)
    lua_matmul(wa, wb, expect, M, N, K)
    for i = 0, layout.c_elems - 1 do
        assert(math.abs(wc[i] - expect[i]) < 1e-9)
    end

    local t_run = now_ms()
    for _ = 1, iters do
        run(layout.a_offset, layout.b_offset, layout.c_offset)
    end
    local run_ms = now_ms() - t_run

    return compile_ms, run_ms
end

local function bench_watjit()
    local engine = wm.engine()
    local out = {}
    for i = 1, #cases do
        local M, N, K, iters = table.unpack(cases[i])
        local scalar_fn = matmul.make(M, N, K, wj.f64)
        local simd_fn = matmul.make_simd(M, N, K, wj.simd.f64x2, { unroll_k = false })
        local scalar_cmp, scalar_run = bench_one(engine, scalar_fn, M, N, K, iters)
        local simd_cmp, simd_run = bench_one(engine, simd_fn, M, N, K, iters)
        out[string.format("%dx%dx%d", M, N, K)] = {
            scalar_compile_ms = scalar_cmp,
            scalar_run_ms = scalar_run,
            simd_compile_ms = simd_cmp,
            simd_run_ms = simd_run,
        }
    end
    return out
end

local function bench_terra()
    local pipe = assert(io.popen("terra ./watjit/terra_matmul_bench.t", "r"))
    local text = pipe:read("*a")
    local ok, _, code = pipe:close()
    if ok == false or code ~= 0 then
        error("terra benchmark failed:\n" .. text)
    end

    local out = {}
    for line in text:gmatch("[^\n]+") do
        local M, N, K, first_ms, run_ms = line:match("^(%d+)%s+(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)$")
        if M then
            out[string.format("%sx%sx%s", M, N, K)] = {
                first_ms = tonumber(first_ms),
                run_ms = tonumber(run_ms),
            }
        end
    end
    return out
end

local watjit_results = bench_watjit()
local terra_results = bench_terra()

print("watjit vs terra — matmul")
print(string.format("%-12s %10s %10s %10s %10s %10s %8s %8s", "case", "sc cmp", "sc run", "sd cmp", "sd run", "terra", "sc/t", "sd/t"))
print(string.rep("-", 92))
for i = 1, #cases do
    local M, N, K = cases[i][1], cases[i][2], cases[i][3]
    local key = string.format("%dx%dx%d", M, N, K)
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
print("sc = watjit scalar matmul")
print("sd = watjit SIMD matmul (f64x2 over output columns)")
print("terra = terra steady-state runtime")
