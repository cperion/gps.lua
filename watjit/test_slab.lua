package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local Vec2 = wj.struct("Vec2", {
    { "x", wj.i32 },
    { "y", wj.i32 },
})

local pool = wj.slab("vec_pool", Vec2.size, 3)

local exercise = wj.fn {
    name = "exercise_slab",
    params = { wj.i32 "base" },
    ret = wj.i32,
    body = function(base)
        local i0 = wj.let(wj.i32, "i0", -1)
        local i1 = wj.let(wj.i32, "i1", -1)
        local i2 = wj.let(wj.i32, "i2", -1)
        local i3 = wj.let(wj.i32, "i3", -1)
        local p = wj.let(wj.i32, "p", 0)

        pool.init(base)
        i0(pool.alloc(base))
        i1(pool.alloc(base))
        i2(pool.alloc(base))
        i3(pool.alloc(base))

        p(pool.addr(base, i0))
        Vec2.at(p).x(10)
        Vec2.at(p).y(20)

        p(pool.addr(base, i1))
        Vec2.at(p).x(30)
        Vec2.at(p).y(40)

        pool.free(base, i1)
        i3(pool.alloc(base))
        p(pool.addr(base, i3))
        Vec2.at(p).x(50)
        Vec2.at(p).y(60)

        return i3
    end,
}

local funcs = pool:funcs()
funcs[#funcs + 1] = exercise

local engine = wm.engine()
local inst = wj.module(funcs):compile(engine)
local run = inst:fn("exercise_slab")
local mem = inst:memory("memory", "int32_t")

assert(run(0) == 1)

-- header
assert(mem[0] == -1) -- free_head empty after re-allocation
assert(mem[1] == 3)  -- capacity
assert(mem[2] == 8)  -- slot_size
assert(mem[3] == 3)  -- next_unused

-- slot 0 = {10,20}
assert(mem[4] == 10)
assert(mem[5] == 20)

-- slot 1 reused = {50,60}
assert(mem[6] == 50)
assert(mem[7] == 60)

print("watjit: slab ok")
