package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

local surface_int_ops = wj.fn {
    name = "surface_int_ops",
    params = { wj.u32 "x", wj.u32 "y" },
    ret = wj.u32,
    body = function(x, y)
        local z = wj.u32("z", x:band(y))
        z(z:bor(wj.u32(0x10)))
        z(z:bxor(wj.u32(0x03)))
        z(z:shl(1))
        z(z:shr_u(1))
        z(z:rotl(2))
        z(z:rotr(2))
        z(z + x:rem_u(y))
        return wj.select(x:gt_u(y), z, y:div_u(wj.u32(1)))
    end,
}

local write_narrow = wj.fn {
    name = "write_narrow",
    params = { wj.i32 "base" },
    body = function(base)
        local bytes_u = wj.view(wj.u8, base, "bytes_u")
        local bytes_s = wj.view(wj.i8, base + 4, "bytes_s")
        local words_u = wj.view(wj.u16, base + 8, "words_u")
        bytes_u[0](255)
        bytes_s[0](-1)
        words_u[0](65535)
    end,
}

local read_u8 = wj.fn {
    name = "read_u8",
    params = { wj.i32 "base" },
    ret = wj.i32,
    body = function(base)
        local bytes = wj.view(wj.u8, base, "bytes")
        return bytes[0]
    end,
}

local read_i8 = wj.fn {
    name = "read_i8",
    params = { wj.i32 "base" },
    ret = wj.i32,
    body = function(base)
        local bytes = wj.view(wj.i8, base, "bytes")
        return bytes[0]
    end,
}

local read_u16 = wj.fn {
    name = "read_u16",
    params = { wj.i32 "base" },
    ret = wj.i32,
    body = function(base)
        local words = wj.view(wj.u16, base, "words")
        return words[0]
    end,
}

local gt_u = wj.fn {
    name = "gt_u",
    params = { wj.u32 "a", wj.u32 "b" },
    ret = wj.i32,
    body = function(a, b)
        return a:gt_u(b)
    end,
}

local rem_u = wj.fn {
    name = "rem_u_test",
    params = { wj.u32 "a", wj.u32 "b" },
    ret = wj.i32,
    body = function(a, b)
        return a:rem_u(b)
    end,
}

local mod = wj.module({
    surface_int_ops,
    write_narrow,
    read_u8,
    read_i8,
    read_u16,
    gt_u,
    rem_u,
})

local wat = mod:wat()

has(wat, '(param $x i32)')
has(wat, '(param $y i32)')
has(wat, '(local $z i32)')
has(wat, '(i32.and')
has(wat, '(i32.or')
has(wat, '(i32.xor')
has(wat, '(i32.shl')
has(wat, '(i32.shr_u')
has(wat, '(i32.rotl')
has(wat, '(i32.rotr')
has(wat, '(i32.rem_u')
has(wat, '(i32.div_u')
has(wat, '(i32.gt_u')
has(wat, '(select')
has(wat, '(i32.load8_u')
has(wat, '(i32.load8_s')
has(wat, '(i32.load16_u')
has(wat, '(i32.store8')
has(wat, '(i32.store16')

local inst = mod:compile(wm.engine())
local write = inst:fn("write_narrow")
local load_u8 = inst:fn("read_u8")
local load_i8 = inst:fn("read_i8")
local load_u16 = inst:fn("read_u16")
local cmp_gt_u = inst:fn("gt_u")
local calc_rem_u = inst:fn("rem_u_test")
local mem_u8 = inst:memory("memory", "uint8_t")
local mem_u16 = ffi.cast("uint16_t*", select(1, inst:memory("memory")))

write(0)
assert(mem_u8[0] == 255)
assert(mem_u8[4] == 255)
assert(mem_u16[4] == 65535)
assert(load_u8(0) == 255)
assert(load_i8(4) == -1)
assert(load_u16(8) == 65535)
assert(cmp_gt_u(-1, 1) == 1)
assert(calc_rem_u(-1, 256) == 255)

print("watjit: integer core ops ok")
