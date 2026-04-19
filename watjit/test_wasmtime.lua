package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wasmtime = require("watjit.wasmtime")

local add = wj.fn {
    name = "add",
    params = { wj.i32 "a", wj.i32 "b" },
    ret = wj.i32,
    body = function(a, b)
        return a + b
    end,
}

local addf = wj.fn {
    name = "addf",
    params = { wj.f64 "a", wj.f64 "b" },
    ret = wj.f64,
    body = function(a, b)
        return a + b
    end,
}

local write42 = wj.fn {
    name = "write42",
    params = {},
    body = function()
        local mem = wj.view(wj.i32, 0, "mem")
        mem[0](42)
    end,
}

local engine = wasmtime.engine()
local inst = wj.module({ add, addf, write42 }):compile(engine)

local add_fn = inst:fn("add")
assert(add_fn(20, 22) == 42)

local addf_fn = inst:fn("addf")
assert(math.abs(addf_fn(1.5, 2.25) - 3.75) < 1e-12)

local base_u8, mem_size = inst:memory("memory")
assert(mem_size >= 65536)

local mem_i32 = ffi.cast("int32_t*", base_u8)
assert(mem_i32[0] == 0)
inst:fn("write42")()
assert(mem_i32[0] == 42)

print("watjit: wasmtime backend ok (" .. tostring(wasmtime._loaded_from) .. ")")
