-- bench_uvm_fusion.lua — interpreted vs compiled UVM execution paths

package.path = "./?.lua;./?/init.lua;" .. package.path

local uvm = require("uvm")
local S = uvm.status

local base = uvm.stream("counter", function(param, state)
    if state >= param.n then return nil end
    return state + 1, state
end, {
    init = function(param, seed) return seed or 0 end,
})

local generic = base:chain(base):limit(1000000)
local compiled = generic:compile()

local param = { inner = { a = { n = 25000 }, b = { n = 25000 } } }
local seed = { a = 0, b = 0 }

local function run_collect(fam, rounds)
    for _ = 1, 50 do
        local m = fam:spawn(param, seed)
        uvm.run.collect(m, 1000000)
    end
    collectgarbage("collect"); collectgarbage("collect")
    local t0 = os.clock()
    for _ = 1, rounds do
        local m = fam:spawn(param, seed)
        uvm.run.collect(m, 1000000)
    end
    return (os.clock() - t0) / rounds
end

local function run_collect_flat(fam, rounds)
    for _ = 1, 50 do
        local m = fam:spawn(param, seed)
        uvm.run.collect_flat(m, 1000000)
    end
    collectgarbage("collect"); collectgarbage("collect")
    local t0 = os.clock()
    for _ = 1, rounds do
        local m = fam:spawn(param, seed)
        uvm.run.collect_flat(m, 1000000)
    end
    return (os.clock() - t0) / rounds
end

local function run_each(fam, rounds)
    local sink = function() end
    for _ = 1, 50 do
        local m = fam:spawn(param, seed)
        uvm.run.each(m, 1000000, sink)
    end
    collectgarbage("collect"); collectgarbage("collect")
    local t0 = os.clock()
    for _ = 1, rounds do
        local m = fam:spawn(param, seed)
        uvm.run.each(m, 1000000, sink)
    end
    return (os.clock() - t0) / rounds
end

-- correctness
local mg = generic:spawn(param, seed)
local cg, sg = uvm.run.collect(mg, 1000000)
local mc = compiled:spawn(param, seed)
local cc, sc = uvm.run.collect(mc, 1000000)
assert(sg == sc, "status mismatch")
assert(#cg == #cc, "yield count mismatch")
for i = 1, math.min(#cg, 8) do
    assert(cg[i][1] == cc[i][1], "value mismatch at " .. i)
end
local mf = compiled:spawn(param, seed)
local flat, flat_n, sf = uvm.run.collect_flat(mf, 1000000)
assert(sf == sc, "flat status mismatch")
assert(flat_n == #cc * 4, "flat size mismatch")
for i = 1, math.min(#cc, 8) do
    assert(flat[(i-1)*4 + 1] == cc[i][1], "flat payload mismatch at " .. i)
end

print("Correctness: OK")
print("Compiled layout slots:", compiled.state_layout and compiled.state_layout.slot_count or 0)

local rounds = 200
local t_generic_collect = run_collect(generic, rounds)
local t_compiled_collect = run_collect(compiled, rounds)
local t_compiled_flat = run_collect_flat(compiled, rounds)
local t_compiled_each = run_each(compiled, rounds)

print(string.format("generic  + collect:      %8.1f us", t_generic_collect * 1e6))
print(string.format("compiled + collect:      %8.1f us  (%.2fx)", t_compiled_collect * 1e6, t_generic_collect / t_compiled_collect))
print(string.format("compiled + collect_flat: %8.1f us  (%.2fx)", t_compiled_flat * 1e6, t_generic_collect / t_compiled_flat))
print(string.format("compiled + each(sink):   %8.1f us  (%.2fx)", t_compiled_each * 1e6, t_generic_collect / t_compiled_each))
