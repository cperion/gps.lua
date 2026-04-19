package.path = "./?.lua;./?/init.lua;" .. package.path

local iwj = require("iwatjit")
local S = require("watjit.stream")
local wj = require("watjit")

local TRange = {}
TRange.__index = TRange

local function Range(a, b)
    return setmetatable({ a = a, b = b }, TRange)
end

local function now_ms()
    return os.clock() * 1000.0
end

local function bench(iters, fn)
    local t0 = now_ms()
    local out
    for _ = 1, iters do
        out = fn()
    end
    return now_ms() - t0, out
end

local rt = iwj.runtime {
    result_capacity = 8 * 1024 * 1024,
}

local lower = iwj.phase(rt, "lower", {
    [TRange] = function(self)
        return S.range(wj.i32, self.a, self.b, 1)
    end,
})

local n = 16384
local iters = 400

local node = Range(1, n + 1)
local base = lower(node)
assert(base.kind == "recording")
assert(iwj.sum(base) == (n * (n + 1)) / 2)

local hit = lower(node)
assert(hit.kind == "cached_seq")

local derived = hit
    :map(wj.i32, function(v) return v * 3 + 1 end)
    :concat(S.once(wj.i32, 7))

local expect_sum = (3 * (n * (n + 1) / 2) + n) + 7
assert(iwj.sum(derived) == expect_sum)
assert(iwj.host_sum(derived) == expect_sum)

local native_sum_ms = bench(iters, function()
    return iwj.sum(derived)
end)
local host_sum_ms = bench(iters, function()
    return iwj.host_sum(derived)
end)

local native_drain_ms, native_out = bench(iters, function()
    return iwj.drain(derived)
end)
local host_drain_ms, host_out = bench(iters, function()
    return iwj.host_drain(derived)
end)

assert(#native_out == n + 1)
assert(#host_out == n + 1)
assert(native_out[1] == 4 and native_out[n] == n * 3 + 1 and native_out[n + 1] == 7)
assert(host_out[1] == 4 and host_out[n] == n * 3 + 1 and host_out[n + 1] == 7)

print("iwatjit cached-seq native staged vs host fallback")
print(string.format("n=%d  iterations=%d", n, iters))
print(string.format("sum    native=%8.3f ms  host=%8.3f ms  speedup=%6.2fx", native_sum_ms, host_sum_ms, host_sum_ms / native_sum_ms))
print(string.format("drain  native=%8.3f ms  host=%8.3f ms  speedup=%6.2fx", native_drain_ms, host_drain_ms, host_drain_ms / native_drain_ms))
print(iwj.report_string(rt))
