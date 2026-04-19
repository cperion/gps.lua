package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local inc = wj.quote_expr {
    params = { wj.i32 "x" },
    ret = wj.i32,
    body = function(x)
        local t = wj.i32("t", x + 1)
        return t
    end,
}

local store_triplet = wj.quote_block {
    params = { wj.i32 "base", wj.i32 "x", wj.i32 "y" },
    body = function(base, x, y)
        local mem = wj.view(wj.i32, base, "mem")
        local t = wj.i32("t", x + y)
        mem[0](x)
        mem[1](t)
        mem[2](y)
    end,
}

local hash_step = wj.quote_expr {
    params = { wj.u32 "h", wj.u8 "b" },
    ret = wj.u32,
    body = function(h, b)
        return (h:bxor(wj.zext(wj.u32, b))) * wj.u32(16777619)
    end,
}

local hash3 = wj.quote_expr {
    params = { wj.i32 "base" },
    ret = wj.u32,
    body = function(base)
        local bytes = wj.view(wj.u8, base, "bytes")
        local i = wj.i32("i")
        local h = wj.u32("h", wj.u32(2166136261))
        wj.for_(i, 3, function()
            h(hash_step(h, bytes[i]))
        end)
        return h
    end,
}

local quote_math = wj.fn {
    name = "quote_math",
    params = { wj.i32 "x" },
    ret = wj.i32,
    body = function(x)
        local t = wj.i32("t", 100)
        local a = wj.i32("a", inc(x))
        local b = wj.i32("b", inc(x + 1))
        return t + a + b
    end,
}

local quote_store = wj.fn {
    name = "quote_store",
    params = { wj.i32 "base", wj.i32 "x" },
    body = function(base, x)
        store_triplet(base, x, inc(x))
        store_triplet(base + 12, inc(x + 10), inc(x + 20))
    end,
}

local quote_hash = wj.fn {
    name = "quote_hash",
    params = { wj.i32 "base" },
    ret = wj.u32,
    body = function(base)
        return hash3(base)
    end,
}

local inline_sugar = wj.fn {
    name = "inline_sugar",
    params = { wj.i32 "x" },
    ret = wj.i32,
    body = function(x)
        local a = wj.i32("a", quote_math:inline_call(x))
        return a + quote_math:inline_call(x + 1)
    end,
}

local mod = wj.module({ quote_math, quote_store, quote_hash, inline_sugar })
local wat = mod:wat()
assert(not wat:find("(call $", 1, true), wat)

local inst = mod:compile(wm.engine())
assert(inst:fn("quote_math")(5) == 113)
assert(inst:fn("inline_sugar")(5) == 228)

local mem_i32 = ffi.cast("int32_t*", select(1, inst:memory("memory")))
local mem_u8 = ffi.cast("uint8_t*", select(1, inst:memory("memory")))
inst:fn("quote_store")(0, 7)
assert(mem_i32[0] == 7)
assert(mem_i32[1] == 15)
assert(mem_i32[2] == 8)
assert(mem_i32[3] == 18)
assert(mem_i32[4] == 46)
assert(mem_i32[5] == 28)

mem_u8[64] = string.byte('a')
mem_u8[65] = string.byte('b')
mem_u8[66] = string.byte('c')
assert(inst:fn("quote_hash")(64) == 440920331)

print("watjit: quotes ok")
