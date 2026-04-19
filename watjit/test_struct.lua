package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local Vec2 = wj.struct("Vec2", {
    { "x", wj.i32 },
    { "y", wj.i32 },
})

local Pair = wj.struct("Pair", {
    { "lhs", Vec2 },
    { "rhs", Vec2 },
    { "vals", wj.array(wj.i32, 3) },
})

local write_pair = wj.fn {
    name = "write_pair",
    params = { wj.i32 "base" },
    body = function(base)
        local pair = Pair.at(base)
        pair.lhs.x(11)
        pair.lhs.y(22)
        pair.rhs.x(pair.lhs.x + 3)
        pair.rhs.y(pair.lhs.y + pair.rhs.x)
        pair.vals[0](7)
        pair.vals[1](pair.rhs.x)
        pair.vals[2](pair.rhs.y)
    end,
}

local engine = wm.engine()
local inst = wj.module({ write_pair }):compile(engine)
local run = inst:fn("write_pair")
local mem = inst:memory("memory", "int32_t")

run(0)

assert(mem[0] == 11)
assert(mem[1] == 22)
assert(mem[2] == 14)
assert(mem[3] == 36)
assert(mem[4] == 7)
assert(mem[5] == 14)
assert(mem[6] == 36)

print("watjit: struct/array ok")
