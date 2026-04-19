package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local memlib = wj.mem("rt")
local mod = wj.module(memlib:funcs())
local wat = mod:wat()

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

has(wat, '(func $rt_memcpy_u8 (export "rt_memcpy_u8")')
has(wat, '(func $rt_memset_u8 (export "rt_memset_u8")')
has(wat, '(func $rt_memmove_u8 (export "rt_memmove_u8")')
has(wat, '(func $rt_memcmp_u8 (export "rt_memcmp_u8")')

local inst = mod:compile(wm.engine())
local memcpy_u8 = inst:fn("rt_memcpy_u8")
local memset_u8 = inst:fn("rt_memset_u8")
local memmove_u8 = inst:fn("rt_memmove_u8")
local memcmp_u8 = inst:fn("rt_memcmp_u8")
local mem = ffi.cast("uint8_t*", select(1, inst:memory("memory")))

for i = 0, 127 do
    mem[i] = 0
end

assert(memset_u8(0, 0xaa, 16) == 0)
for i = 0, 15 do
    assert(mem[i] == 0xaa)
end

for i = 0, 15 do
    mem[32 + i] = i
end
assert(memcpy_u8(48, 32, 16) == 48)
for i = 0, 15 do
    assert(mem[48 + i] == i)
end
assert(memcmp_u8(32, 48, 16) == 0)

mem[48 + 7] = 99
assert(memcmp_u8(32, 48, 16) == -1)
assert(memcmp_u8(48, 32, 16) == 1)

for i = 0, 7 do
    mem[64 + i] = i + 1
end
assert(memmove_u8(66, 64, 6) == 66)
assert(mem[66] == 1)
assert(mem[67] == 2)
assert(mem[68] == 3)
assert(mem[69] == 4)
assert(mem[70] == 5)
assert(mem[71] == 6)

for i = 0, 7 do
    mem[80 + i] = i + 1
end
assert(memmove_u8(80, 82, 6) == 80)
assert(mem[80] == 3)
assert(mem[81] == 4)
assert(mem[82] == 5)
assert(mem[83] == 6)
assert(mem[84] == 7)
assert(mem[85] == 8)

print("watjit: mem primitives ok")
