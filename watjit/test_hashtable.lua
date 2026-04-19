package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

local ht = wj.hashtable("ht", 4)
local mod = wj.module(ht:funcs(), {
    memory_pages = wj.pages_for_bytes(ht.memory_bytes + 64),
})
local wat = mod:wat()

has(wat, '(func $ht_init (export "ht_init")')
has(wat, '(func $ht_get (export "ht_get")')
has(wat, '(func $ht_set (export "ht_set")')
has(wat, '(func $ht_del (export "ht_del")')
has(wat, '(i32.rem_u')
has(wat, '(i32.xor')

local inst = mod:compile(wm.engine())
local init = inst:fn("ht_init")
local clear = inst:fn("ht_clear")
local len = inst:fn("ht_len")
local get = inst:fn("ht_get")
local has_key = inst:fn("ht_has")
local set = inst:fn("ht_set")
local del = inst:fn("ht_del")
local mem = ffi.cast("uint8_t*", select(1, inst:memory("memory")))

for i = 0, ht.memory_bytes + 31 do
    mem[i] = 0xff
end

init(0)
assert(len(0) == 0)
assert(get(0, 123, -9) == -9)
assert(has_key(0, 123) == 0)

assert(set(0, 1, 11) == 1)
assert(set(0, 2, 22) == 1)
assert(set(0, -1, 99) == 1)
assert(len(0) == 3)
assert(get(0, 1, -1) == 11)
assert(get(0, 2, -1) == 22)
assert(get(0, -1, -1) == 99)
assert(has_key(0, -1) == 1)

assert(set(0, 2, 222) == 1)
assert(len(0) == 3)
assert(get(0, 2, -1) == 222)

assert(set(0, 3, 33) == 1)
assert(len(0) == 4)
assert(set(0, 4, 44) == 0)
assert(len(0) == 4)

assert(del(0, 2) == 1)
assert(del(0, 2) == 0)
assert(len(0) == 3)
assert(has_key(0, 2) == 0)
assert(get(0, 2, -5) == -5)

assert(set(0, 4, 44) == 1)
assert(len(0) == 4)
assert(get(0, 4, -1) == 44)

clear(0)
assert(len(0) == 0)
assert(get(0, 1, -7) == -7)
assert(has_key(0, 4) == 0)

print("watjit: hashtable ok")
