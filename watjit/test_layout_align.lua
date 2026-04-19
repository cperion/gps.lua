package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local Packed = wj.struct("Packed", {
    { "tag", wj.u8 },
    { "value", wj.u32 },
})

local Aligned = wj.struct("Aligned", {
    { "tag", wj.u8 },
    { "value", wj.u32 },
}, {
    packed = false,
})

local FieldAligned = wj.struct("FieldAligned", {
    { "tag", wj.u8 },
    { "value", wj.u32, { align = 8 } },
    { "tail", wj.u8 },
}, {
    packed = false,
})

local PackedAligned = wj.struct("PackedAligned", {
    { "tag", wj.u8 },
    { "value", wj.u32 },
}, {
    align = 8,
})

local AU = wj.union("AlignedUnion", {
    { "b", wj.u8 },
    { "w", wj.u32 },
}, {
    packed = false,
    align = 8,
})

local Container = wj.struct("Container", {
    { "tag", wj.u8 },
    { "payload", AU },
    { "tail", wj.u8 },
}, {
    packed = false,
})

assert(Packed.packed == true)
assert(Packed.align == 1)
assert(Packed.size == 5)
assert(Packed.offsets.tag.offset == 0)
assert(Packed.offsets.value.offset == 1)

assert(Aligned.packed == false)
assert(Aligned.align == 4)
assert(Aligned.size == 8)
assert(Aligned.offsets.tag.offset == 0)
assert(Aligned.offsets.value.offset == 4)

assert(FieldAligned.align == 8)
assert(FieldAligned.size == 16)
assert(FieldAligned.offsets.tag.offset == 0)
assert(FieldAligned.offsets.value.offset == 8)
assert(FieldAligned.offsets.tail.offset == 12)

assert(PackedAligned.packed == true)
assert(PackedAligned.align == 8)
assert(PackedAligned.size == 8)
assert(PackedAligned.offsets.value.offset == 1)

assert(AU.packed == false)
assert(AU.align == 8)
assert(AU.size == 8)
assert(AU.offsets.b.offset == 0)
assert(AU.offsets.w.offset == 0)

assert(Container.align == 8)
assert(Container.size == 24)
assert(Container.offsets.tag.offset == 0)
assert(Container.offsets.payload.offset == 8)
assert(Container.offsets.tail.offset == 16)

local write_layouts = wj.fn {
    name = "write_layouts",
    params = { wj.i32 "base" },
    body = function(base)
        local p = Packed.at(base)
        local a = Aligned.at(base + 32)
        local f = FieldAligned.at(base + 64)
        local c = Container.at(base + 128)

        p.tag(0x11)
        p.value(0x22334455)

        a.tag(0x66)
        a.value(0x778899aa)

        f.tag(0x01)
        f.value(0x0badc0de)
        f.tail(0x02)

        c.tag(0x03)
        c.payload.w(0xdeadbeef)
        c.tail(0x04)
    end,
}

local inst = wj.module({ write_layouts }):compile(wm.engine())
local run = inst:fn("write_layouts")
local mem_base = select(1, inst:memory("memory"))
local mem_u8 = ffi.cast("uint8_t*", mem_base)
local function u32_at(byte_offset)
    return ffi.cast("uint32_t*", mem_base + byte_offset)[0]
end

run(0)

assert(mem_u8[0] == 0x11)
assert(u32_at(1) == 0x22334455)

assert(mem_u8[32] == 0x66)
assert(u32_at(36) == 0x778899aa)

assert(mem_u8[64] == 0x01)
assert(u32_at(72) == 0x0badc0de)
assert(mem_u8[76] == 0x02)

assert(mem_u8[128] == 0x03)
assert(u32_at(136) == 0xdeadbeef)
assert(mem_u8[144] == 0x04)

print("watjit: packed/aligned layouts ok")
