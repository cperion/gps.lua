package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local S = wj.stream
local SC = wj.stream_compile
local i32 = wj.i32
local f64 = wj.f64
local V = wj.simd.f64x2

local simd_drain = SC.compile_drain_into {
    name = "simd_drain",
    params = { i32 "x_base", i32 "n", i32 "out_base" },
    build = function(x_base, n, out_base)
        local src = S.seq(f64, x_base, n):simd_map(V, f64,
            function(v)
                return v + V { 1.0, 2.0 }
            end,
            function(x)
                return x + 1.0
            end)
        return src, out_base
    end,
}

local simd_sum = SC.compile_sum {
    name = "simd_sum",
    params = { i32 "x_base", i32 "n" },
    ret = f64,
    vector_t = V,
    build = function(x_base, n)
        return S.seq(f64, x_base, n):simd_map(V, f64,
            function(v)
                return v * V.splat(2.0)
            end,
            function(x)
                return x * 2.0
            end)
    end,
}

local scalar_sum = SC.compile_sum {
    name = "scalar_sum",
    params = { i32 "x_base", i32 "n" },
    ret = f64,
    vector_t = V,
    build = function(x_base, n)
        return S.seq(f64, x_base, n)
    end,
}

local inst = wj.module({ simd_drain, simd_sum, scalar_sum }, { memory_pages = 1 }):compile(wm.engine())
local drain = inst:fn("simd_drain")
local sum = inst:fn("simd_sum")
local scalar = inst:fn("scalar_sum")
local mem = inst:memory("memory", "double")

for i = 0, 4 do
    mem[i] = i + 1
end

local written = drain(0, 5, 64)
assert(written == 5)
assert(math.abs(mem[8] - 2.0) < 1e-12)
assert(math.abs(mem[9] - 4.0) < 1e-12)
assert(math.abs(mem[10] - 4.0) < 1e-12)
assert(math.abs(mem[11] - 6.0) < 1e-12)
assert(math.abs(mem[12] - 6.0) < 1e-12)

assert(math.abs(sum(0, 5) - 30.0) < 1e-12)
assert(math.abs(scalar(0, 5) - 15.0) < 1e-12)

print("watjit: stream simd ok")
