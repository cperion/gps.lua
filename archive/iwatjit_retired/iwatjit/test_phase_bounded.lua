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

local a = Range(1, 5)
local b = Range(10, 14)

local pa1 = lower(a)
assert(pa1.kind == "recording")
assert(iwj.sum(pa1) == 10)
local pa2 = lower(a)
assert(pa2.kind == "cached_seq")
assert(pa2.slab ~= nil)

local pb1 = lower(b)
assert(pb1.kind == "recording")
assert(iwj.sum(pb1) == 46)
local pb2 = lower(b)
assert(pb2.kind == "cached_seq")
assert(pb2.slab ~= nil)

-- lower is bounded to one committed entry, so a must be evicted even though
-- the global result capacity is large.
assert(pa2.slab == nil)
assert(pa2.values ~= nil)
assert(iwj.count(pa2) == 4)
assert(iwj.one(pa2, -1) == 1)

local pa3 = lower(a)
assert(pa3.kind == "recording")
assert(iwj.drain(pa3)[4] == 4)
assert(lower(a).kind == "cached_seq")

local mem = iwj.memory_stats(rt)
assert(mem.result.live_slots == 1)
assert(mem.result.used < mem.result.cap)
assert(mem.result.evictions >= 1)

local report = iwj.report_string(rt)
assert(report:find("bound=1", 1, true))
assert(report:find("evict=", 1, true))

print("iwatjit: per-phase bounded cache ok")
print(report)
