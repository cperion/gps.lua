package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")
local wm = require("watjit.wasmtime")

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

local cast_i32_to_f64 = wj.fn {
    name = "cast_i32_to_f64",
    params = { wj.i32 "x" },
    ret = wj.f64,
    body = function(x)
        return wj.cast(wj.f64, x)
    end,
}

local cast_f64_to_i32 = wj.fn {
    name = "cast_f64_to_i32",
    params = { wj.f64 "x" },
    ret = wj.i32,
    body = function(x)
        return wj.cast(wj.i32, x)
    end,
}

local zext_u8_to_u64 = wj.fn {
    name = "zext_u8_to_u64",
    params = { wj.u8 "x" },
    ret = wj.u64,
    body = function(x)
        return wj.zext(wj.u64, x)
    end,
}

local sext_i8_to_i64 = wj.fn {
    name = "sext_i8_to_i64",
    params = { wj.i8 "x" },
    ret = wj.i64,
    body = function(x)
        return wj.sext(wj.i64, x)
    end,
}

local trunc_u32_to_u8 = wj.fn {
    name = "trunc_u32_to_u8",
    params = { wj.u32 "x" },
    ret = wj.u8,
    body = function(x)
        return wj.trunc(wj.u8, x)
    end,
}

local bits_of_one = wj.fn {
    name = "bits_of_one",
    params = {},
    ret = wj.u32,
    body = function()
        return wj.bitcast(wj.u32, wj.f32(1.0))
    end,
}

local f32_from_bits = wj.fn {
    name = "f32_from_bits",
    params = { wj.u32 "x" },
    ret = wj.f32,
    body = function(x)
        return wj.bitcast(wj.f32, x)
    end,
}

local demote_f64 = wj.fn {
    name = "demote_f64",
    params = { wj.f64 "x" },
    ret = wj.f32,
    body = function(x)
        return wj.cast(wj.f32, x)
    end,
}

local promote_f32 = wj.fn {
    name = "promote_f32",
    params = { wj.f32 "x" },
    ret = wj.f64,
    body = function(x)
        return wj.cast(wj.f64, x)
    end,
}

local mod = wj.module({
    cast_i32_to_f64,
    cast_f64_to_i32,
    zext_u8_to_u64,
    sext_i8_to_i64,
    trunc_u32_to_u8,
    bits_of_one,
    f32_from_bits,
    demote_f64,
    promote_f32,
})

local wat = mod:wat()
has(wat, '(f64.convert_i32_s')
has(wat, '(i32.trunc_f64_s')
has(wat, '(i64.extend_i32_u')
has(wat, '(i64.extend_i32_s')
has(wat, '(i32.and')
has(wat, '(i32.reinterpret_f32')
has(wat, '(f32.reinterpret_i32')
has(wat, '(f32.demote_f64')
has(wat, '(f64.promote_f32')

local inst = mod:compile(wm.engine())
assert(math.abs(inst:fn("cast_i32_to_f64")(7) - 7.0) < 1e-12)
assert(inst:fn("cast_f64_to_i32")(7.75) == 7)
assert(inst:fn("zext_u8_to_u64")(255) == 255)
assert(inst:fn("sext_i8_to_i64")(-1) == -1)
assert(inst:fn("trunc_u32_to_u8")(511) == 255)
assert(inst:fn("bits_of_one")() == 0x3f800000)
assert(math.abs(inst:fn("f32_from_bits")(0x40000000) - 2.0) < 1e-6)
assert(math.abs(inst:fn("demote_f64")(3.5) - 3.5) < 1e-6)
assert(math.abs(inst:fn("promote_f32")(2.25) - 2.25) < 1e-12)

print("watjit: casts ok")
