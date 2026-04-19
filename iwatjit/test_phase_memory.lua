package.path = "./?.lua;./?/init.lua;" .. package.path

local iwj = require("iwatjit")
local S = require("watjit.stream")
local wj = require("watjit")

local TRange = {}
TRange.__index = TRange

local function Range(a, b)
    return setmetatable({ a = a, b = b }, TRange)
end

local rt = iwj.runtime {
    result_capacity = 1024 * 1024,
}

local lower = iwj.phase(rt, "lower", {
    [TRange] = function(self)
        return S.range(wj.i32, self.a, self.b, 1)
    end,
}, {
    bounded = 1,
})

local a = Range(1, 9)   -- 8 i32s => slab class 8 => 32 bytes
local b = Range(1, 5)   -- 4 i32s => slab class 4 => 16 bytes

assert(iwj.sum(lower(a)) == 36)
local sa = iwj.phase_stats(lower)
assert(sa.memory == 8 * wj.i32.size)
assert(sa.live == 1)
assert(sa.evictions == 0)

local mem1 = iwj.memory_stats(rt)
assert(mem1.result.used == 8 * wj.i32.size)
assert(mem1.phases[1].used == 8 * wj.i32.size)
assert(mem1.phases[1].name == "lower")

assert(iwj.sum(lower(b)) == 10)
local sb = iwj.phase_stats(lower)
assert(sb.memory == 4 * wj.i32.size)
assert(sb.live == 1)
assert(sb.evictions >= 1)

local mem2 = iwj.memory_stats(rt)
assert(mem2.result.used == 4 * wj.i32.size)
assert(mem2.phases[1].used == 4 * wj.i32.size)
assert(mem2.phases[1].evictions >= 1)

local report = iwj.report_string(rt)
assert(report:find("mem=16", 1, true))

print("iwatjit: per-phase memory accounting ok")
print(report)
