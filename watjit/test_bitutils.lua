package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")
local wm = require("watjit.wasmtime")

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

local clz32 = wj.fn {
    name = "clz32",
    params = { wj.u32 "x" },
    ret = wj.u32,
    body = function(x)
        return x:clz()
    end,
}

local ctz32 = wj.fn {
    name = "ctz32",
    params = { wj.u32 "x" },
    ret = wj.u32,
    body = function(x)
        return x:ctz()
    end,
}

local popcnt32 = wj.fn {
    name = "popcnt32",
    params = { wj.u32 "x" },
    ret = wj.u32,
    body = function(x)
        return x:popcnt()
    end,
}

local bswap32 = wj.fn {
    name = "bswap32",
    params = { wj.u32 "x" },
    ret = wj.u32,
    body = function(x)
        return x:bswap()
    end,
}

local bswap16 = wj.fn {
    name = "bswap16",
    params = { wj.u16 "x" },
    ret = wj.u16,
    body = function(x)
        return x:bswap()
    end,
}

local bswap64 = wj.fn {
    name = "bswap64",
    params = { wj.u64 "x" },
    ret = wj.u64,
    body = function(x)
        return x:bswap()
    end,
}

local mod = wj.module({ clz32, ctz32, popcnt32, bswap32, bswap16, bswap64 })
local wat = mod:wat()

has(wat, '(i32.clz')
has(wat, '(i32.ctz')
has(wat, '(i32.popcnt')
has(wat, '(i32.shr_u')
has(wat, '(i32.and')
has(wat, '(i32.shl')
has(wat, '(i64.shr_u')
has(wat, '(i64.and')
has(wat, '(i64.shl')

local inst = mod:compile(wm.engine())
assert(inst:fn("clz32")(1) == 31)
assert(inst:fn("ctz32")(16) == 4)
assert(inst:fn("popcnt32")(0xf0f0f00f) == 16)
assert(inst:fn("bswap32")(0x12345678) == 0x78563412)
assert(inst:fn("bswap16")(0x1234) == 0x3412)
assert(inst:fn("bswap64")(0) == 0)

print("watjit: bit utility ops ok")
