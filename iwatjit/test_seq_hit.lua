package.path = "./?.lua;./?/init.lua;" .. package.path

local iwj = require("iwatjit")
local S = require("watjit.stream")
local wj = require("watjit")

local TNum = {}
TNum.__index = TNum
local TRange = {}
TRange.__index = TRange
local TCat = {}
TCat.__index = TCat

local function Num(v)
    return setmetatable({ value = v }, TNum)
end

local function Range(a, b)
    return setmetatable({ a = a, b = b }, TRange)
end

local function Cat(lhs, rhs)
    return setmetatable({ lhs = lhs, rhs = rhs }, TCat)
end

local rt = iwj.runtime()
local lower
lower = iwj.phase(rt, "lower", {
    [TNum] = function(self)
        return S.once(wj.i32, self.value)
    end,
    [TRange] = function(self)
        return S.range(wj.i32, self.a, self.b, 1)
    end,
    [TCat] = function(self)
        return lower(self.lhs):concat(lower(self.rhs))
    end,
})

local left = Cat(Range(1, 4), Num(10))
local root = Cat(left, Num(99))

local left_plan_1 = lower(left)
assert(left_plan_1.kind == "recording")
local left_values_1 = iwj.drain(left_plan_1)
assert(#left_values_1 == 4)
assert(left_values_1[1] == 1)
assert(left_values_1[2] == 2)
assert(left_values_1[3] == 3)
assert(left_values_1[4] == 10)

local left_plan_2 = lower(left)
assert(left_plan_2.kind == "cached_seq")
assert(iwj.count(left_plan_2) == 4)
assert(iwj.sum(left_plan_2) == 16)
assert(iwj.one(left_plan_2, -1) == 1)

local root_plan_1 = lower(root)
assert(root_plan_1.kind == "recording")
local root_values_1 = iwj.drain(root_plan_1)
assert(#root_values_1 == 5)
assert(root_values_1[1] == 1)
assert(root_values_1[2] == 2)
assert(root_values_1[3] == 3)
assert(root_values_1[4] == 10)
assert(root_values_1[5] == 99)

local root_plan_2 = lower(root)
assert(root_plan_2.kind == "cached_seq")
local root_values_2 = iwj.drain(root_plan_2)
assert(#root_values_2 == 5)
assert(root_values_2[5] == 99)

local report = iwj.report_string(rt)
assert(report:find("seq_hits=", 1, true))
assert(report:find("commits=", 1, true))
assert(report:find("shared=", 1, true))

print("iwatjit: cached seq hit path ok")
print(report)
