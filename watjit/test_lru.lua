package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")
local wm = require("watjit.wasmtime")

local q = wj.lru("q", 3)

local engine = wm.engine()
local inst = wj.module(q:funcs()):compile(engine)

local init = inst:fn("q_init")
local push_head = inst:fn("q_push_head")
local remove = inst:fn("q_remove")
local touch = inst:fn("q_touch")
local pop_tail = inst:fn("q_pop_tail")
local head = inst:fn("q_head")
local tail = inst:fn("q_tail")
local is_linked = inst:fn("q_is_linked")
local mem = inst:memory("memory", "int32_t")

init(0)
assert(head(0) == -1)
assert(tail(0) == -1)

push_head(0, 0)
push_head(0, 1)
assert(head(0) == 1)
assert(tail(0) == 0)

touch(0, 0)
assert(head(0) == 0)
assert(tail(0) == 1)

push_head(0, 2)
assert(head(0) == 2)
assert(tail(0) == 1)
assert(is_linked(0, 0) == 1)
assert(is_linked(0, 1) == 1)
assert(is_linked(0, 2) == 1)

assert(pop_tail(0) == 1)
assert(head(0) == 2)
assert(tail(0) == 0)
assert(is_linked(0, 1) == 0)

remove(0, 2)
assert(head(0) == 0)
assert(tail(0) == 0)
assert(is_linked(0, 2) == 0)
assert(is_linked(0, 0) == 1)

-- header
assert(mem[0] == 0)
assert(mem[1] == 0)
assert(mem[2] == 3)

-- slot 0 meta = prev=-1 next=-1 linked=1
assert(mem[3] == -1)
assert(mem[4] == -1)
assert(mem[5] == 1)

-- slot 1 meta cleared after pop_tail
assert(mem[6] == -1)
assert(mem[7] == -1)
assert(mem[8] == 0)

-- slot 2 meta cleared after remove
assert(mem[9] == -1)
assert(mem[10] == -1)
assert(mem[11] == 0)

print("watjit: lru ok")
