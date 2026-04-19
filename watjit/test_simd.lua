package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local S = wj.simd

local kernel = wj.fn {
    name = "simd_add2",
    params = { wj.i32 "x_base", wj.i32 "y_base" },
    body = function(x_base, y_base)
        local x = wj.view(wj.f64, x_base, "x")
        local y = wj.view(wj.f64, y_base, "y")
        local v = S.f64x2.load(x, 0)
        local k = S.f64x2 { 1.5, 2.5 }
        y[0](S.f64x2.sum(v + k))
    end,
}

local pages = wj.pages_for_bytes(32)
local inst = wj.module({ kernel }, { memory_pages = pages }):compile(wm.engine())
local run = inst:fn("simd_add2")
local mem = inst:memory("memory", "double")

mem[0] = 10.0
mem[1] = 20.0
mem[2] = 0.0

run(0, 16)
assert(math.abs(mem[2] - 34.0) < 1e-12)

print("watjit: simd ok")
