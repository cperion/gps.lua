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

local node = Range(1, 6)
local plan1 = lower(node)
assert(plan1.kind == "recording")

local c1 = iwj.open(plan1)
assert(c1:next() == 1)
assert(c1:next() == 2)

local plan2 = lower(node)
assert(plan2 == plan1)

local c2 = iwj.open(plan2)
assert(c2:next() == 1)
assert(c2:next() == 2)
assert(c2:next() == 3)

c1:cancel()

local rest = c2:drain()
assert(#rest == 2)
assert(rest[1] == 4)
assert(rest[2] == 5)

local plan3 = lower(node)
assert(plan3.kind == "cached_seq")
assert(iwj.count(plan3) == 5)
assert(iwj.sum(plan3) == 15)

local node2 = Range(10, 13)
local plan4 = lower(node2)
assert(plan4.kind == "recording")
local c3 = iwj.open(plan4)
assert(c3:next() == 10)
c3:cancel()

local plan5 = lower(node2)
assert(plan5.kind == "recording")
assert(plan5 ~= plan4)
assert(iwj.sum(plan5) == 33)
assert(lower(node2).kind == "cached_seq")

local report = iwj.report_string(rt)
assert(report:find("shared=1", 1, true))
assert(report:find("cancels=1", 1, true))

print("iwatjit: recording shared/cancel ok")
print(report)
