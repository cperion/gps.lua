package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local bytes = wj.bytes("rt")
assert(bytes.Slice.size == 8)
assert(bytes.Slice.align == 4)
assert(bytes.Buf.size == 12)
assert(bytes.Buf.align == 4)

local mod = wj.module(bytes:funcs())
local wat = mod:wat()

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

has(wat, '(func $rt_bytes_eq_u8 (export "rt_bytes_eq_u8")')
has(wat, '(func $rt_bytes_cmp_u8 (export "rt_bytes_cmp_u8")')
has(wat, '(func $rt_bytes_find_byte (export "rt_bytes_find_byte")')
has(wat, '(func $rt_cstr_len (export "rt_cstr_len")')
has(wat, '(func $rt_cstr_cmp (export "rt_cstr_cmp")')
has(wat, '(func $rt_bytes_hash_u8 (export "rt_bytes_hash_u8")')
has(wat, '(func $rt_cstr_hash (export "rt_cstr_hash")')
has(wat, '(func $rt_buf_clear (export "rt_buf_clear")')
has(wat, '(func $rt_buf_append_u8 (export "rt_buf_append_u8")')
has(wat, '(func $rt_buf_append_slice_u8 (export "rt_buf_append_slice_u8")')
has(wat, '(func $rt_buf_append_cstr (export "rt_buf_append_cstr")')
has(wat, '(i32.xor')
has(wat, '(i32.mul')

local inst = mod:compile(wm.engine())
local eq_u8 = inst:fn("rt_bytes_eq_u8")
local cmp_u8 = inst:fn("rt_bytes_cmp_u8")
local find_byte = inst:fn("rt_bytes_find_byte")
local cstr_len = inst:fn("rt_cstr_len")
local cstr_cmp = inst:fn("rt_cstr_cmp")
local bytes_hash_u8 = inst:fn("rt_bytes_hash_u8")
local cstr_hash = inst:fn("rt_cstr_hash")
local buf_clear = inst:fn("rt_buf_clear")
local buf_append_u8 = inst:fn("rt_buf_append_u8")
local buf_append_slice_u8 = inst:fn("rt_buf_append_slice_u8")
local buf_append_cstr = inst:fn("rt_buf_append_cstr")
local mem_base = select(1, inst:memory("memory"))
local mem = ffi.cast("uint8_t*", mem_base)
local mem_i32 = ffi.cast("int32_t*", mem_base)

mem[0] = string.byte('a')
mem[1] = string.byte('b')
mem[2] = string.byte('c')
mem[3] = 0

mem[16] = string.byte('a')
mem[17] = string.byte('b')
mem[18] = string.byte('c')
mem[19] = 0

mem[32] = string.byte('a')
mem[33] = string.byte('b')
mem[34] = string.byte('d')
mem[35] = 0

mem[48] = string.byte('a')
mem[49] = string.byte('b')
mem[50] = 0

assert(eq_u8(0, 3, 16, 3) == 1)
assert(eq_u8(0, 3, 32, 3) == 0)
assert(eq_u8(0, 3, 48, 2) == 0)

assert(cmp_u8(0, 3, 16, 3) == 0)
assert(cmp_u8(0, 3, 32, 3) == -1)
assert(cmp_u8(32, 3, 0, 3) == 1)
assert(cmp_u8(48, 2, 0, 3) == -1)

assert(find_byte(0, 3, string.byte('a')) == 0)
assert(find_byte(0, 3, string.byte('c')) == 2)
assert(find_byte(0, 3, string.byte('z')) == -1)

assert(cstr_len(0) == 3)
assert(cstr_len(48) == 2)
assert(cstr_cmp(0, 16) == 0)
assert(cstr_cmp(0, 32) == -1)
assert(cstr_cmp(32, 0) == 1)
assert(cstr_cmp(48, 0) == -1)

assert(bytes_hash_u8(0, 3) == 440920331)
assert(bytes_hash_u8(16, 3) == 440920331)
assert(bytes_hash_u8(32, 3) ~= 440920331)
assert(cstr_hash(0) == 440920331)
assert(cstr_hash(16) == 440920331)
assert(cstr_hash(32) ~= 440920331)

-- Buf at byte offset 96: { base=112, len=0, cap=8 }
mem_i32[24] = 112
mem_i32[25] = 0
mem_i32[26] = 8

assert(buf_append_u8(96, string.byte('x')) == 1)
assert(mem_i32[25] == 1)
assert(mem[112] == string.byte('x'))

assert(buf_append_slice_u8(96, 0, 3) == 1)
assert(mem_i32[25] == 4)
assert(mem[113] == string.byte('a'))
assert(mem[114] == string.byte('b'))
assert(mem[115] == string.byte('c'))

assert(buf_append_cstr(96, 48) == 1)
assert(mem_i32[25] == 6)
assert(mem[116] == string.byte('a'))
assert(mem[117] == string.byte('b'))

assert(buf_append_cstr(96, 0) == 0)
assert(mem_i32[25] == 6)

buf_clear(96)
assert(mem_i32[25] == 0)
assert(buf_append_cstr(96, 32) == 1)
assert(mem_i32[25] == 3)
assert(mem[112] == string.byte('a'))
assert(mem[113] == string.byte('b'))
assert(mem[114] == string.byte('d'))

print("watjit: bytes/cstr helpers ok")
