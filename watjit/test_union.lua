package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

local Pair16 = wj.struct("Pair16", {
    { "lo", wj.u16 },
    { "hi", wj.u16 },
})

local Vec2 = wj.struct("Vec2", {
    { "x", wj.i32 },
    { "y", wj.i32 },
})

local Bits = wj.union("Bits", {
    { "u", wj.u32 },
    { "f", wj.f32 },
    { "pair", Pair16 },
})

local Overlay = wj.union("Overlay", {
    { "word", wj.u32 },
    { "vec", Vec2 },
})

assert(Bits.size == 4)
assert(Overlay.size == 8)

local write_u_bits = wj.fn {
    name = "write_u_bits",
    params = { wj.i32 "base", wj.u32 "value" },
    body = function(base, value)
        local bits = Bits.at(base)
        bits.u(value)
    end,
}

local read_f_bits = wj.fn {
    name = "read_f_bits",
    params = { wj.i32 "base" },
    ret = wj.f32,
    body = function(base)
        local bits = Bits.at(base)
        return bits.f
    end,
}

local write_pair_bits = wj.fn {
    name = "write_pair_bits",
    params = { wj.i32 "base", wj.u16 "lo", wj.u16 "hi" },
    body = function(base, lo, hi)
        local bits = Bits.at(base)
        bits.pair.lo(lo)
        bits.pair.hi(hi)
    end,
}

local read_u_bits = wj.fn {
    name = "read_u_bits",
    params = { wj.i32 "base" },
    ret = wj.u32,
    body = function(base)
        local bits = Bits.at(base)
        return bits.u
    end,
}

local write_overlay = wj.fn {
    name = "write_overlay",
    params = { wj.i32 "base", wj.i32 "x", wj.i32 "y" },
    body = function(base, x, y)
        local ov = Overlay.at(base)
        ov.vec.x(x)
        ov.vec.y(y)
    end,
}

local read_overlay_word = wj.fn {
    name = "read_overlay_word",
    params = { wj.i32 "base" },
    ret = wj.u32,
    body = function(base)
        local ov = Overlay.at(base)
        return ov.word
    end,
}

local read_overlay_y = wj.fn {
    name = "read_overlay_y",
    params = { wj.i32 "base" },
    ret = wj.i32,
    body = function(base)
        local ov = Overlay.at(base)
        return ov.vec.y
    end,
}

local mod = wj.module({
    write_u_bits,
    read_f_bits,
    write_pair_bits,
    read_u_bits,
    write_overlay,
    read_overlay_word,
    read_overlay_y,
})

local wat = mod:wat()
has(wat, '(func $write_u_bits (export "write_u_bits")')
has(wat, '(func $read_f_bits (export "read_f_bits")')
has(wat, '(i32.store16')
has(wat, '(f32.load')
has(wat, '(i32.load')

local inst = mod:compile(wm.engine())
local write_u = inst:fn("write_u_bits")
local read_f = inst:fn("read_f_bits")
local write_pair = inst:fn("write_pair_bits")
local read_u = inst:fn("read_u_bits")
local write_overlay = inst:fn("write_overlay")
local read_overlay_word = inst:fn("read_overlay_word")
local read_overlay_y = inst:fn("read_overlay_y")
local mem_base = select(1, inst:memory("memory"))
local mem_u8 = ffi.cast("uint8_t*", mem_base)

write_u(0, 0x3f800000)
assert(math.abs(read_f(0) - 1.0) < 1e-6)

write_pair(0, 0x5678, 0x1234)
assert(read_u(0) == 0x12345678)
assert(mem_u8[0] == 0x78)
assert(mem_u8[1] == 0x56)
assert(mem_u8[2] == 0x34)
assert(mem_u8[3] == 0x12)

write_overlay(16, 33, 77)
assert(read_overlay_word(16) == 33)
assert(read_overlay_y(16) == 77)

print("watjit: union ok")
