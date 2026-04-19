package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local Pair16 = wj.struct("Pair16", {
    { "lo", wj.u16 },
    { "hi", wj.u16 },
})

local Value = wj.tagged_union("Value", {
    tag_t = wj.u8,
    packed = false,
    variants = {
        { "I32", wj.i32 },
        { "F32", wj.f32 },
        { "Pair", Pair16 },
    },
})

assert(Value.layout_kind == "struct")
assert(Value.Tag ~= nil)
assert(Value.Payload ~= nil)
assert(Value.tag_field == "tag")
assert(Value.payload_field == "payload")
assert(Value.I32 ~= nil)
assert(Value.F32 ~= nil)
assert(Value.Pair ~= nil)
assert(Value.variants.I32.index == 0)
assert(Value.variants.F32.index == 1)
assert(Value.variants.Pair.index == 2)
assert(Value.offsets.tag.offset == 0)
assert(Value.offsets.payload.offset == 4)
assert(Value.size == 8)
assert(Value.align == 4)

local write_i32 = wj.fn {
    name = "write_i32_value",
    params = { wj.i32 "base", wj.i32 "x" },
    body = function(base, x)
        local v = Value.at(base)
        v.tag(Value.I32)
        v.payload.I32(x)
    end,
}

local write_pair = wj.fn {
    name = "write_pair_value",
    params = { wj.i32 "base", wj.u16 "lo", wj.u16 "hi" },
    body = function(base, lo, hi)
        local v = Value.at(base)
        v.tag(Value.Pair)
        v.payload.Pair.lo(lo)
        v.payload.Pair.hi(hi)
    end,
}

local classify = wj.fn {
    name = "classify_value",
    params = { wj.i32 "base" },
    ret = wj.i32,
    body = function(base)
        local v = Value.at(base)
        local out = wj.i32("out", -1)
        wj.switch(v.tag, {
            [Value.I32] = function()
                out(v.payload.I32)
            end,
            [Value.Pair] = function()
                out(v.payload.Pair.hi)
            end,
            [Value.F32] = function()
                out(777)
            end,
        }, function()
            out(999)
        end)
        return out
    end,
}

local mod = wj.module({ write_i32, write_pair, classify })
local inst = mod:compile(wm.engine())
local mem_base = select(1, inst:memory("memory"))
local mem_u8 = ffi.cast("uint8_t*", mem_base)
local function u32_at(byte_offset)
    return ffi.cast("uint32_t*", mem_base + byte_offset)[0]
end

inst:fn("write_i32_value")(0, 123456)
assert(mem_u8[0] == 0)
assert(inst:fn("classify_value")(0) == 123456)

inst:fn("write_pair_value")(16, 0x1234, 0xabcd)
assert(mem_u8[16] == 2)
assert(u32_at(20) == 0xabcd1234)
assert(inst:fn("classify_value")(16) == 0xabcd)

print("watjit: tagged union ok")
