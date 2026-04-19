package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local S = wj.stream
local I = wj.iter
local i32 = wj.i32

local drain_custom = I.compile_drain_into {
    name = "iter_drain_custom",
    params = { i32 "x_base", i32 "n", i32 "out_base" },
    build = function(x_base, n, out_base)
        local src = S.seq(i32, x_base, n)
            :map(i32, function(v) return v * i32(2) end)
            :filter(function(v) return v:gt(0) end)
            :drop(1)
            :take(3)
            :concat(S.range(i32, i32(100), i32(102), i32(1)))
            :concat(S.once(i32, 999))
            :concat(S.empty(i32))
        return src, out_base
    end,
}

local count_custom = I.compile_count {
    name = "iter_count_custom",
    params = { i32 "x_base", i32 "n" },
    build = function(x_base, n)
        return S.seq(i32, x_base, n)
            :map(i32, function(v) return v * i32(2) end)
            :filter(function(v) return v:gt(0) end)
            :drop(1)
            :take(3)
            :concat(S.range(i32, i32(100), i32(102), i32(1)))
            :concat(S.once(i32, 999))
    end,
}

local sum_custom = I.compile_sum {
    name = "iter_sum_custom",
    params = {},
    ret = i32,
    build = function()
        return S.range(i32, i32(1), i32(5), i32(1))
            :concat(S.once(i32, 10))
            :map(i32, function(v) return v + i32(1) end)
    end,
}

local one_custom = I.compile_one {
    name = "iter_one_custom",
    params = {},
    ret = i32,
    default = -1,
    build = function()
        return S.empty(i32)
            :concat(S.once(i32, 77))
            :concat(S.once(i32, 88))
    end,
}

local direct_sum = wj.fn {
    name = "iter_direct_sum",
    params = { i32 "x_base", i32 "n" },
    ret = i32,
    body = function(x_base, n)
        return S.seq(i32, x_base, n)
            :map(i32, function(v) return v + i32(1) end)
            :filter(function(v) return (v % i32(2)):eq(0) end)
            :sum(0)
    end,
}

local count_sink = I.sink_block {
    params = { wj.ptr(i32) "slot" },
    item = i32 "v",
    body = function(slot, _v)
        slot[0](slot[0] + i32(1))
    end,
}

local first_gt_sink = I.sink_expr {
    params = { wj.ptr(i32) "slot", i32 "limit" },
    item = i32 "v",
    body = function(slot, limit, v)
        local code = i32("code", I.CONTINUE())
        wj.if_(v:gt(limit), function()
            slot[0](v)
            code(I.HALT())
        end)
        return code
    end,
}

local scaled_reducer = I.reducer_expr {
    params = { i32 "scale" },
    acc = i32 "acc",
    item = i32 "v",
    ret = i32,
    body = function(scale, acc, v)
        return acc + (v * scale)
    end,
}

local count_via_sink_quote = wj.fn {
    name = "iter_count_via_sink_quote",
    params = { i32 "x_base", i32 "n", i32 "slot_base" },
    ret = i32,
    body = function(x_base, n, slot_base)
        local slot = wj.view(i32, slot_base, "slot")
        slot[0](0)
        S.seq(i32, x_base, n):lower(I.bind(count_sink, slot))
        return slot[0]
    end,
}

local first_gt_quote = wj.fn {
    name = "iter_first_gt_quote",
    params = { i32 "x_base", i32 "n", i32 "limit", i32 "slot_base" },
    ret = i32,
    body = function(x_base, n, limit, slot_base)
        local slot = wj.view(i32, slot_base, "slot")
        slot[0](-1)
        S.seq(i32, x_base, n):lower(I.bind(first_gt_sink, slot, limit))
        return slot[0]
    end,
}

local scaled_fold_quote = wj.fn {
    name = "iter_scaled_fold_quote",
    params = { i32 "x_base", i32 "n", i32 "scale" },
    ret = i32,
    body = function(x_base, n, scale)
        return S.seq(i32, x_base, n):fold(0, I.bind(scaled_reducer, scale), i32)
    end,
}

local mod = wj.module({
    drain_custom,
    count_custom,
    sum_custom,
    one_custom,
    direct_sum,
    count_via_sink_quote,
    first_gt_quote,
    scaled_fold_quote,
})
local inst = mod:compile(wm.engine())
local drain = inst:fn("iter_drain_custom")
local count = inst:fn("iter_count_custom")
local sum = inst:fn("iter_sum_custom")
local one = inst:fn("iter_one_custom")
local direct = inst:fn("iter_direct_sum")
local sink_count = inst:fn("iter_count_via_sink_quote")
local first_gt = inst:fn("iter_first_gt_quote")
local scaled_fold = inst:fn("iter_scaled_fold_quote")
local mem = inst:memory("memory", "int32_t")

mem[0] = -3
mem[1] = 1
mem[2] = 2
mem[3] = 3
mem[4] = 4

local written = drain(0, 5, 64)
assert(written == 6)
assert(mem[16] == 4)
assert(mem[17] == 6)
assert(mem[18] == 8)
assert(mem[19] == 100)
assert(mem[20] == 101)
assert(mem[21] == 999)

assert(count(0, 5) == 6)
assert(sum() == 25)
assert(one() == 77)
assert(direct(0, 5) == 4)
assert(sink_count(0, 5, 128) == 5)
assert(first_gt(0, 5, 2, 132) == 3)
assert(scaled_fold(0, 5, 3) == 21)

local n1 = I.normalize(S.seq(i32, i32(0), 4):drop(1):take(2))
assert(n1.kind == "take")
assert(n1.src.kind == "drop")

print("watjit: iter compiled traversal algebra ok")
