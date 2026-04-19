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
local base = lower(node)
assert(base.kind == "recording")
assert(iwj.sum(base) == 15)

local hit = lower(node)
assert(hit.kind == "cached_seq")
assert(hit.slab ~= nil)

local derived = hit
    :map(wj.i32, function(v) return v * 2 end)
    :filter(function(v) return v:gt(4) end)
    :concat(S.once(wj.i32, 99))

assert(iwj.sum(derived) == 123) -- 6 + 8 + 10 + 99
local drained = iwj.drain(derived)
assert(#drained == 4)
assert(drained[1] == 6)
assert(drained[2] == 8)
assert(drained[3] == 10)
assert(drained[4] == 99)
assert(iwj.one(derived, -1) == 6)
assert(iwj.count(derived) == 4)

local t = rt.terminals[derived]
assert(t ~= nil)
assert(t.staged_sum ~= nil)
assert(t.staged_drain ~= nil)
assert(t.staged_one ~= nil)
assert(t.staged_count ~= nil)

print("iwatjit: native staged seq-hit terminals ok")
