package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local S = wj.stream
local SC = wj.stream_compile

local i32 = wj.i32

local drain_custom = SC.compile_drain_into {
    name = "drain_custom",
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

local count_custom = SC.compile_count {
    name = "count_custom",
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

local fold_sum = SC.compile_fold {
    name = "fold_sum",
    params = {},
    ret = i32,
    init = 0,
    build = function()
        return S.range(i32, i32(1), i32(5), i32(1))
            :concat(S.once(i32, 10))
            :map(i32, function(v) return v + i32(1) end)
    end,
    reducer = function(acc, v)
        return acc + v
    end,
}

local first_value = SC.compile_one {
    name = "first_value",
    params = {},
    ret = i32,
    default = -1,
    build = function()
        return S.empty(i32)
            :concat(S.once(i32, 77))
            :concat(S.once(i32, 88))
    end,
}

local mod = wj.module({ drain_custom, count_custom, fold_sum, first_value })
local inst = mod:compile(wm.engine())

local drain = inst:fn("drain_custom")
local count = inst:fn("count_custom")
local fold = inst:fn("fold_sum")
local first = inst:fn("first_value")
local mem = inst:memory("memory", "int32_t")

-- input: [-3, 1, 2, 3, 4]
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
assert(fold() == 25) -- (1..4 + 10) then +1 each => 2+3+4+5+11
assert(first() == 77)

print("watjit: stream ok")
