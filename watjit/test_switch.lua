package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")
local wm = require("watjit.wasmtime")

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

local State = wj.enum("State", wj.u8, {
    Empty = 0,
    Live = 1,
    Tomb = 2,
})

local classify_num = wj.fn {
    name = "classify_num",
    params = { wj.i32 "x" },
    ret = wj.i32,
    body = function(x)
        local out = wj.i32("out", -1)
        wj.switch(x, {
            [0] = function()
                out(10)
            end,
            [2] = function()
                out(20)
            end,
            [5] = function()
                out(50)
            end,
        }, function()
            out(99)
        end)
        return out
    end,
}

local classify_state = wj.fn {
    name = "classify_state",
    params = { State "state" },
    ret = wj.i32,
    body = function(state)
        local out = wj.i32("out", -1)
        wj.switch(state, {
            [State.Empty] = function()
                out(100)
            end,
            [State.Live] = function()
                out(200)
            end,
            [State.Tomb] = function()
                out(300)
            end,
        })
        return out
    end,
}

local nested_switch = wj.fn {
    name = "nested_switch",
    params = { wj.i32 "x", State "state" },
    ret = wj.i32,
    body = function(x, state)
        local out = wj.i32("out", 0)
        wj.switch(x, {
            [1] = function()
                wj.switch(state, {
                    [State.Live] = function()
                        out(11)
                    end,
                }, function()
                    out(12)
                end)
            end,
        }, function()
            out(77)
        end)
        return out
    end,
}

local mod = wj.module({ classify_num, classify_state, nested_switch })
local wat = mod:wat()

has(wat, '(func $classify_num (export "classify_num")')
has(wat, '(func $classify_state (export "classify_state")')
has(wat, '(if')
has(wat, '(i32.eq')

local inst = mod:compile(wm.engine())
assert(inst:fn("classify_num")(0) == 10)
assert(inst:fn("classify_num")(2) == 20)
assert(inst:fn("classify_num")(5) == 50)
assert(inst:fn("classify_num")(9) == 99)

assert(inst:fn("classify_state")(0) == 100)
assert(inst:fn("classify_state")(1) == 200)
assert(inst:fn("classify_state")(2) == 300)

assert(inst:fn("nested_switch")(1, 1) == 11)
assert(inst:fn("nested_switch")(1, 0) == 12)
assert(inst:fn("nested_switch")(0, 1) == 77)

print("watjit: switch ok")
