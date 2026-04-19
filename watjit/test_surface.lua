package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local branchy = wj.fn {
    name = "branchy",
    params = { wj.i32 "x" },
    ret = wj.i32,
    body = function(x)
        local y = wj.let(wj.i32, "y", 0)
        wj.if_(x:gt(10), function()
            y(x + 1)
        end, function()
            y(x - 1)
        end)
        return y
    end,
}

local write_pair = wj.fn {
    name = "write_pair_v2",
    params = { wj.i32 "base" },
    body = function(base)
        local mem = wj.view(wj.i32, base, "mem")
        local i, j = wj.lets(wj.i32, "i", "j")

        i(5)
        j(9)
        mem[0](i)
        mem[1](j)
        mem[2](i + j)
    end,
}

local engine = wm.engine()
local inst = wj.module({ branchy, write_pair }):compile(engine)
local branch = inst:fn("branchy")
local write = inst:fn("write_pair_v2")
local mem = ffi.cast("int32_t*", select(1, inst:memory("memory")))

assert(branch(20) == 21)
assert(branch(2) == 1)
write(0)
assert(mem[0] == 5)
assert(mem[1] == 9)
assert(mem[2] == 14)

print("watjit: lua-first surface ok")
