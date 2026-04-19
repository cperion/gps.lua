package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")
local matmul = require("watjit.matmul")

local M, N, K = 3, 4, 4
local layout = matmul.layout(M, N, K, 8)
local fn = matmul.make(M, N, K, wj.f64)

local engine = wm.engine()
local t0 = os.clock()
local inst = wj.module({ fn }, { memory_pages = wj.pages_for_bytes(layout.total_bytes) }):compile(engine)
local compile_ms = (os.clock() - t0) * 1000

local run = inst:fn(fn.name)
local mem = inst:memory("memory", "double")
local a = mem + (layout.a_offset / 8)
local b = mem + (layout.b_offset / 8)
local c = mem + (layout.c_offset / 8)
local expect = ffi.new("double[?]", layout.c_elems)

for i = 0, layout.a_elems - 1 do
    a[i] = i + 1
end
for i = 0, layout.b_elems - 1 do
    b[i] = (i % 5) - 1
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

local t1 = os.clock()
run(layout.a_offset, layout.b_offset, layout.c_offset)
local call_ms = (os.clock() - t1) * 1000

for i = 0, layout.c_elems - 1 do
    assert(math.abs(c[i] - expect[i]) < 1e-12)
end

print(("compiled %s in %.3f ms, call %.3f ms"):format(fn.name, compile_ms, call_ms))
print("result:")
for i = 0, M - 1 do
    local row = {}
    for j = 0, N - 1 do
        row[#row + 1] = string.format("%8.2f", c[i * N + j])
    end
    print(table.concat(row, " "))
end
