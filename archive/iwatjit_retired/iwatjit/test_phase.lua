package.path = "./?.lua;./?/init.lua;" .. package.path

local iwj = require("iwatjit")
local S = require("watjit.stream")
local wj = require("watjit")

local TNum = {}
TNum.__index = TNum
local TRange = {}
TRange.__index = TRange
local TAdd = {}
TAdd.__index = TAdd
local TSeq = {}
TSeq.__index = TSeq

local function Num(v)
    return setmetatable({ value = v }, TNum)
end

local function Range(n)
    return setmetatable({ n = n }, TRange)
end

local function Add(lhs, rhs)
    return setmetatable({ lhs = lhs, rhs = rhs }, TAdd)
end

local function Seq(children)
    return setmetatable({ children = children }, TSeq)
end

local rt = iwj.runtime()
local lower
lower = iwj.phase(rt, "lower", {
    [TNum] = function(self)
        return S.once(wj.i32, self.value)
    end,
    [TRange] = function(self)
        return S.range(wj.i32, 1, self.n + 1, 1)
    end,
    [TAdd] = function(self)
        return lower(self.lhs):concat(lower(self.rhs))
    end,
    [TSeq] = function(self)
        local out = S.empty(wj.i32)
        for i = 1, #self.children do
            out = out:concat(lower(self.children[i]))
        end
        return out
    end,
})

local root = Seq {
    Num(10),
    Range(3),
    Add(Num(20), Range(2)),
}

local plan1 = lower(root)
local plan2 = lower(root)
assert(plan1 == plan2)

local values = iwj.drain(plan1)
assert(#values == 7)
assert(values[1] == 10)
assert(values[2] == 1)
assert(values[3] == 2)
assert(values[4] == 3)
assert(values[5] == 20)
assert(values[6] == 1)
assert(values[7] == 2)

assert(iwj.count(plan1) == 7)
assert(iwj.one(plan1, -1) == 10)
assert(iwj.sum(plan1) == 39)

local report = iwj.report_string(rt)
assert(report:find("lower", 1, true))
assert(report:find("shared=1", 1, true))
assert(report:find("commits=", 1, true))

print("iwatjit: phase stream integration ok")
print(report)
