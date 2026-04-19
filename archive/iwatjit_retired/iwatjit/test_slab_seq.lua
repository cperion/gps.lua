package.path = "./?.lua;./?/init.lua;" .. package.path

local iwj = require("iwatjit")
local S = require("watjit.stream")
local wj = require("watjit")

local TRange = {}
TRange.__index = TRange

local function Range(a, b)
    return setmetatable({ a = a, b = b }, TRange)
end

local rt = iwj.runtime()
local lower = iwj.phase(rt, "lower", {
    [TRange] = function(self)
        return S.range(wj.i32, self.a, self.b, 1)
    end,
})

local node = Range(1, 9)
local plan1 = lower(node)
assert(plan1.kind == "recording")
local values = iwj.drain(plan1)
assert(#values == 8)

local plan2 = lower(node)
assert(plan2.kind == "cached_seq")
assert(plan2.slab ~= nil)
assert(plan2.values == nil)
assert(plan2.slab.count == 8)
assert(plan2.slab.capacity == 8)
assert(tonumber(plan2.slab.ptr[0]) == 1)
assert(tonumber(plan2.slab.ptr[7]) == 8)

local mem = iwj.memory_stats(rt)
assert(mem.result.used >= 8 * wj.i32.size)
assert(mem.result.live_slots >= 1)

print("iwatjit: slab-backed seq ok")
