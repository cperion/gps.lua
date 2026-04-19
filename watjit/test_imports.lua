package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")
local wm = require("watjit.wasmtime")

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

local engine = wm.engine()

local add = wj.fn {
    name = "add",
    params = { wj.i32 "a", wj.i32 "b" },
    ret = wj.i32,
    body = function(a, b)
        return a + b
    end,
}

local scale = wj.fn {
    name = "scale",
    params = { wj.i32 "x" },
    ret = wj.i32,
    body = function(x)
        return x * 10
    end,
}

local provider = wj.module({ add, scale }):compile(engine)

local ext_add = wj.import {
    module = "env",
    name = "add",
    as = "host_add",
    params = { wj.i32 "a", wj.i32 "b" },
    ret = wj.i32,
}

local ext_scale = wj.import {
    module = "env",
    name = "scale",
    params = { wj.i32 "x" },
    ret = wj.i32,
}

local use_imports = wj.fn {
    name = "use_imports",
    params = { wj.i32 "x", wj.i32 "y" },
    ret = wj.i32,
    body = function(x, y)
        local sum = ext_add(x, y)
        return ext_scale(sum)
    end,
}

local with_void_import = wj.import {
    module = "env",
    name = "write42",
    params = {},
}

local write42 = wj.fn {
    name = "write42",
    params = {},
    body = function()
        local mem = wj.view(wj.i32, 0, "mem")
        mem[0](42)
    end,
}

local caller = wj.fn {
    name = "call_write42",
    params = {},
    ret = wj.i32,
    body = function()
        with_void_import()
        return 7
    end,
}

local provider2 = wj.module({ write42 }):compile(engine)

local mod = wj.module({ ext_add, ext_scale, use_imports })
local wat = mod:wat()
has(wat, '(import "env" "add"')
has(wat, '(func $host_add')
has(wat, '(import "env" "scale"')
has(wat, '(func $scale')
has(wat, '(call $host_add')
has(wat, '(call $scale')

local inst = mod:compile(engine, {
    imports = {
        env = {
            add = provider:extern("add"),
            scale = provider:extern("scale"),
        },
    },
})
assert(inst:fn("use_imports")(4, 5) == 90)

local mod2 = wj.module({ with_void_import, caller })
local inst2 = mod2:compile(engine, {
    imports = {
        env = {
            write42 = provider2:extern("write42"),
        },
    },
})
assert(inst2:fn("call_write42")() == 7)

print("watjit: imports ok")
