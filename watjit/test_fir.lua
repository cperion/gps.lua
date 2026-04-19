package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")
local fir = require("watjit.fir")

local coeffs = { 0.1, 0.2, 0.4, 0.2, 0.1 }
local n = 64
local layout = fir.layout(n, 8)
local fn = fir.make(coeffs, wj.f64)

local engine = wm.engine()
local inst = wj.module({ fn }, { memory_pages = wj.pages_for_bytes(layout.total_bytes) }):compile(engine)
local run = inst:fn(fn.name)
local mem = inst:memory("memory", "double")
local x = mem + (layout.x_offset / 8)
local y = mem + (layout.y_offset / 8)
local expect = ffi.new("double[?]", n)

for i = 0, n - 1 do
    x[i] = ((i * 7) % 11) - 3
    y[i] = 0
    expect[i] = 0
end

for i = #coeffs - 1, n - 1 do
    local acc = 0
    for j = 0, #coeffs - 1 do
        acc = acc + coeffs[j + 1] * x[i - j]
    end
    expect[i] = acc
end

run(layout.x_offset, layout.y_offset, n)

for i = 0, n - 1 do
    assert(math.abs(y[i] - expect[i]) < 1e-12, ("fir mismatch at %d: got=%f expect=%f"):format(i, y[i], expect[i]))
end

print("watjit: fir ok")
