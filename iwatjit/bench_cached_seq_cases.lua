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

local function expect_equal(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

local function gt(v, x)
    if type(v) == "number" then
        return v > x
    end
    return v:gt(x)
end

local rt = iwj.runtime {
    result_capacity = 32 * 1024 * 1024,
}

local lower = iwj.phase(rt, "lower", {
    [TRange] = function(self)
        return S.range(wj.i32, self.a, self.b, 1)
    end,
})

local n = 16384
local iters = 200

local node_a = Range(1, n + 1)
local node_b = Range(n + 1, 2 * n + 1)
local node_c = Range(2 * n + 1, 3 * n + 1)

assert(iwj.sum(lower(node_a)) == (n * (n + 1)) / 2)
assert(iwj.sum(lower(node_b)) == ((n + 1 + 2 * n) * n) / 2)
assert(iwj.sum(lower(node_c)) == ((2 * n + 1 + 3 * n) * n) / 2)

local hit_a = lower(node_a)
local hit_b = lower(node_b)
local hit_c = lower(node_c)
assert(hit_a.kind == "cached_seq")
assert(hit_b.kind == "cached_seq")
assert(hit_c.kind == "cached_seq")

local cases = {
    {
        name = "map+concat1",
        build = function()
            return hit_a
                :map(wj.i32, function(v) return v * 3 + 1 end)
                :concat(S.once(wj.i32, 7))
        end,
    },
    {
        name = "map+filter+concat",
        build = function()
            return hit_a
                :map(wj.i32, function(v) return v * 2 end)
                :filter(function(v) return gt(v, n) end)
                :concat(S.once(wj.i32, 99))
        end,
    },
    {
        name = "concat2",
        build = function()
            return hit_a:concat(hit_b)
        end,
    },
    {
        name = "concat2+map",
        build = function()
            return hit_a
                :concat(hit_b)
                :map(wj.i32, function(v) return v + 5 end)
        end,
    },
    {
        name = "concat3+take",
        build = function()
            return hit_a
                :concat(hit_b)
                :concat(hit_c)
                :take(n + 17)
        end,
    },
    {
        name = "drop+take+map",
        build = function()
            return hit_a
                :drop(128)
                :take(n - 256)
                :map(wj.i32, function(v) return v * 5 - 3 end)
        end,
    },
}

print("iwatjit cached-seq staged native terminals")
print(string.format("n=%d  iterations=%d", n, iters))
print(string.format("%-18s %10s %10s %8s %10s %10s %8s", "case", "sum nat", "sum host", "s spd", "drn nat", "drn host", "d spd"))
print(string.rep("-", 86))

for i = 1, #cases do
    local case = cases[i]
    local plan = case.build()

    local host_sum = iwj.host_sum(plan)
    local native_sum = iwj.sum(plan)
    assert(native_sum == host_sum)

    local host_drain = iwj.host_drain(plan)
    local native_drain = iwj.drain(plan)
    assert(expect_equal(native_drain, host_drain))

    local nat_sum_ms = bench(iters, function()
        return iwj.sum(plan)
    end)
    local host_sum_ms = bench(iters, function()
        return iwj.host_sum(plan)
    end)

    local nat_drain_ms = bench(iters, function()
        return iwj.drain(plan)
    end)
    local host_drain_ms = bench(iters, function()
        return iwj.host_drain(plan)
    end)

    print(string.format(
        "%-18s %10.3f %10.3f %8.2fx %10.3f %10.3f %8.2fx",
        case.name,
        nat_sum_ms,
        host_sum_ms,
        host_sum_ms / nat_sum_ms,
        nat_drain_ms,
        host_drain_ms,
        host_drain_ms / nat_drain_ms
    ))
end

print("")
print(iwj.report_string(rt))
