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
    result_capacity = 8 * wj.i32.size,
}

local lower = iwj.phase(rt, "lower", {
    [TRange] = function(self)
        return S.range(wj.i32, self.a, self.b, 1)
    end,
})

local a = Range(1, 9)
local b = Range(10, 18)

local pa1 = lower(a)
assert(pa1.kind == "recording")
assert(#iwj.drain(pa1) == 8)

local pa2 = lower(a)
assert(pa2.kind == "cached_seq")
assert(pa2.slab ~= nil)
assert(iwj.sum(pa2) == 36)

local pb1 = lower(b)
assert(pb1.kind == "recording")
assert(#iwj.drain(pb1) == 8)

local pb2 = lower(b)
assert(pb2.kind == "cached_seq")
assert(pb2.slab ~= nil)
assert(iwj.sum(pb2) == 108)

-- first committed result should be evicted from the bounded result arena,
-- but old external references still work via fallback values.
assert(pa2.slab == nil)
assert(pa2.values ~= nil)
local old_a = iwj.drain(pa2)
assert(#old_a == 8)
assert(old_a[1] == 1)
assert(old_a[8] == 8)

-- new phase call for the evicted node is a fresh miss.
local pa3 = lower(a)
assert(pa3.kind == "recording")
assert(iwj.sum(pa3) == 36)
assert(lower(a).kind == "cached_seq")

local mem = iwj.memory_stats(rt)
assert(mem.result.used <= mem.result.cap)
assert(mem.result.live_slots == 1)
assert(mem.result.evictions >= 1)

local report = iwj.report_string(rt)
assert(report:find("evict=", 1, true))

print("iwatjit: bounded result lru eviction ok")
print(report)
