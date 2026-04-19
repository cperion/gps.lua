package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local Vec2 = wj.struct("Vec2", {
    { "x", wj.i32 },
    { "y", wj.i32 },
})

local scratch = wj.arena("scratch", 64)

local exercise = wj.fn {
    name = "exercise",
    params = { wj.i32 "base" },
    ret = wj.i32,
    body = function(base)
        local p0 = wj.let(wj.i32, "p0", -1)
        local p1 = wj.let(wj.i32, "p1", -1)

        scratch.init(base)
        p0(scratch.alloc(base, Vec2.size))
        p1(scratch.alloc(base, Vec2.size))

        local a = Vec2.at(p0)
        local b = Vec2.at(p1)
        a.x(10)
        a.y(20)
        b.x(30)
        b.y(a.x + a.y)
        return b.y
    end,
}

local funcs = scratch:funcs()
funcs[#funcs + 1] = exercise

local engine = wm.engine()
local inst = wj.module(funcs):compile(engine)
local run = inst:fn("exercise")
local mem = inst:memory("memory", "int32_t")

assert(run(0) == 30)
assert(mem[0] == 24)
assert(mem[1] == 64)
assert(mem[2] == 10)
assert(mem[3] == 20)
assert(mem[4] == 30)
assert(mem[5] == 30)

print("watjit: arena ok")
