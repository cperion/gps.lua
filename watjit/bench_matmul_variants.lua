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

local function bench_case(engine, fn, M, N, K, iters)
    local layout = matmul.layout(M, N, K, 8)

    local t_compile = now_ms()
    local inst = wj.module({ fn }, { memory_pages = wj.pages_for_bytes(layout.total_bytes) }):compile(engine)
    local compile_ms = now_ms() - t_compile

    local run = inst:fn(fn.name)
    local mem = inst:memory("memory", "double")
    local a = mem + (layout.a_offset / 8)
    local b = mem + (layout.b_offset / 8)
    local c = mem + (layout.c_offset / 8)

    fill(a, layout.a_elems)
    fill(b, layout.b_elems)
    zero(c, layout.c_elems)
    run(layout.a_offset, layout.b_offset, layout.c_offset)

    local t_run = now_ms()
    for _ = 1, iters do
        run(layout.a_offset, layout.b_offset, layout.c_offset)
    end
    local run_ms = now_ms() - t_run

    return compile_ms, run_ms
end

local engine = wm.engine()
print("watjit matmul variants")
print(string.format("%-12s %9s %9s %9s %9s %9s %9s", "case", "loop", "unroll", "simd", "l/u", "l/s", "u/s"))
print(string.rep("-", 76))
for i = 1, #cases do
    local M, N, K, iters = table.unpack(cases[i])
    local loop_cmp, loop_run = bench_case(engine, matmul.make(M, N, K, wj.f64, { unroll_k = false }), M, N, K, iters)
    local unrl_cmp, unrl_run = bench_case(engine, matmul.make(M, N, K, wj.f64, { unroll_k = true }), M, N, K, iters)
    local simd_cmp, simd_run = bench_case(engine, matmul.make_simd(M, N, K, wj.simd.f64x2, { unroll_k = false }), M, N, K, iters)
    print(string.format(
        "%-12s %9.3f %9.3f %9.3f %9.2fx %9.2fx %9.2fx",
        string.format("%dx%dx%d", M, N, K),
        loop_run,
        unrl_run,
        simd_run,
        loop_run / unrl_run,
        loop_run / simd_run,
        unrl_run / simd_run
    ))
end
