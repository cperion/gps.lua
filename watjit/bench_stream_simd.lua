package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local S = wj.stream
local SC = wj.stream_compile
local i32 = wj.i32
local f64 = wj.f64
local V = wj.simd.f64x2

local n = 16384
local iters = 200
local pages = wj.pages_for_bytes(n * 8 * 2)

local scalar_drain = SC.compile_drain_into {
    name = "scalar_stream_drain",
    params = { i32 "x_base", i32 "n", i32 "out_base" },
    build = function(x_base, n_, out_base)
        local s = S.seq(f64, x_base, n_):map(f64, function(v)
            return v * 1.5 + 2.0
        end)
        return s, out_base
    end,
}

local simd_drain = SC.compile_drain_into {
    name = "simd_stream_drain",
    params = { i32 "x_base", i32 "n", i32 "out_base" },
    build = function(x_base, n_, out_base)
        local s = S.seq(f64, x_base, n_):simd_map(V, f64,
            function(v)
                return v * V.splat(1.5) + V.splat(2.0)
            end,
            function(x)
                return x * 1.5 + 2.0
            end)
        return s, out_base
    end,
}

local scalar_sum = SC.compile_sum {
    name = "scalar_stream_sum",
    params = { i32 "x_base", i32 "n" },
    ret = f64,
    vector_t = V,
    build = function(x_base, n_)
        return S.seq(f64, x_base, n_):map(f64, function(v)
            return v * 1.5 + 2.0
        end)
    end,
}

local simd_sum = SC.compile_sum {
    name = "simd_stream_sum",
    params = { i32 "x_base", i32 "n" },
    ret = f64,
    vector_t = V,
    build = function(x_base, n_)
        return S.seq(f64, x_base, n_):simd_map(V, f64,
            function(v)
                return v * V.splat(1.5) + V.splat(2.0)
            end,
            function(x)
                return x * 1.5 + 2.0
            end)
    end,
}

local inst = wj.module({ scalar_drain, simd_drain, scalar_sum, simd_sum }, { memory_pages = pages }):compile(wm.engine())
local drain_sc = inst:fn("scalar_stream_drain")
local drain_sd = inst:fn("simd_stream_drain")
local sum_sc = inst:fn("scalar_stream_sum")
local sum_sd = inst:fn("simd_stream_sum")
local mem = inst:memory("memory", "double")
local x = mem
local y = mem + n

for i = 0, n - 1 do
    x[i] = ((i * 17) % 29) * 0.125 - 1.0
    y[i] = 0.0
end

local function now_ms()
    return os.clock() * 1000.0
end

local function bench(name, fn)
    local t0 = now_ms()
    for _ = 1, iters do
        fn()
    end
    return now_ms() - t0
end

local sc_drain_ms = bench("scalar_drain", function() drain_sc(0, n, n * 8) end)
local sd_drain_ms = bench("simd_drain", function() drain_sd(0, n, n * 8) end)
local sc_sum_ms = bench("scalar_sum", function() sum_sc(0, n) end)
local sd_sum_ms = bench("simd_sum", function() sum_sd(0, n) end)

print("watjit stream SIMD")
print(string.format("drain  scalar=%8.3f ms  simd=%8.3f ms  speedup=%6.2fx", sc_drain_ms, sd_drain_ms, sc_drain_ms / sd_drain_ms))
print(string.format("sum    scalar=%8.3f ms  simd=%8.3f ms  speedup=%6.2fx", sc_sum_ms, sd_sum_ms, sc_sum_ms / sd_sum_ms))
