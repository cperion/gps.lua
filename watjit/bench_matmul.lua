package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")
local matmul = require("watjit.matmul")

local function now()
    return os.clock()
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

local function bench_case(engine, M, N, K, iters)
    local layout = matmul.layout(M, N, K, 8)
    local fn = matmul.make(M, N, K, wj.f64)

    local t_compile = now()
    local inst = wj.module({ fn }, { memory_pages = wj.pages_for_bytes(layout.total_bytes) }):compile(engine)
    local compile_ms = (now() - t_compile) * 1000

    local run = inst:fn(fn.name)
    local mem = inst:memory("memory", "double")
    local wa = mem + (layout.a_offset / 8)
    local wb = mem + (layout.b_offset / 8)
    local wc = mem + (layout.c_offset / 8)

    local la = ffi.new("double[?]", layout.a_elems)
    local lb = ffi.new("double[?]", layout.b_elems)
    local lc = ffi.new("double[?]", layout.c_elems)

    fill(wa, layout.a_elems)
    fill(wb, layout.b_elems)
    fill(la, layout.a_elems)
    fill(lb, layout.b_elems)
    zero(wc, layout.c_elems)
    zero(lc, layout.c_elems)

    run(layout.a_offset, layout.b_offset, layout.c_offset)
    lua_matmul(la, lb, lc, M, N, K)
    for i = 0, layout.c_elems - 1 do
        assert(math.abs(wc[i] - lc[i]) < 1e-9)
    end

    local t_wasm = now()
    for _ = 1, iters do
        run(layout.a_offset, layout.b_offset, layout.c_offset)
    end
    local wasm_ms = (now() - t_wasm) * 1000

    local t_lua = now()
    for _ = 1, iters do
        lua_matmul(la, lb, lc, M, N, K)
    end
    local lua_ms = (now() - t_lua) * 1000

    print(string.format(
        "%-12s compile=%8.3f ms  wasm=%8.3f ms  lua=%8.3f ms  speedup=%6.2fx",
        string.format("%dx%dx%d", M, N, K),
        compile_ms,
        wasm_ms,
        lua_ms,
        lua_ms / wasm_ms
    ))
end

local engine = wm.engine()
print("watjit matmul bench")
bench_case(engine, 16, 16, 16, 200)
bench_case(engine, 32, 32, 32, 80)
bench_case(engine, 64, 64, 64, 10)
