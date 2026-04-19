package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")
local matmul = require("watjit.matmul")

local M, N, K = 5, 6, 3
local layout = matmul.layout(M, N, K, 8)
local pages = wj.pages_for_bytes(layout.total_bytes)

local engine = wm.engine()
local fn = matmul.make_simd(M, N, K, wj.simd.f64x2)
local inst = wj.module({ fn }, { memory_pages = pages }):compile(engine)
local run = inst:fn(fn.name)
local mem = inst:memory("memory", "double")

local a = mem + (layout.a_offset / 8)
local b = mem + (layout.b_offset / 8)
local c = mem + (layout.c_offset / 8)
local expect = ffi.new("double[?]", layout.c_elems)

for i = 0, layout.a_elems - 1 do
    a[i] = (i % 7) + 1
end
for i = 0, layout.b_elems - 1 do
    b[i] = ((i * 5) % 13) - 3
end
for i = 0, layout.c_elems - 1 do
    c[i] = 0
    expect[i] = 0
end

for i = 0, M - 1 do
    for j = 0, N - 1 do
        local sum = 0
        for k = 0, K - 1 do
            sum = sum + a[i * K + k] * b[k * N + j]
        end
        expect[i * N + j] = sum
    end
end

run(layout.a_offset, layout.b_offset, layout.c_offset)

for i = 0, layout.c_elems - 1 do
    local diff = math.abs(c[i] - expect[i])
    assert(diff < 1e-12, ("simd matmul mismatch at %d: got=%f expect=%f"):format(i, c[i], expect[i]))
end

print("watjit: matmul simd ok")
