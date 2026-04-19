package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")
local wm = require("watjit.wasmtime")

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

local early_block = wj.fn {
    name = "early_block",
    params = { wj.i32 "x" },
    ret = wj.i32,
    body = function(x)
        local out = wj.i32("out", 1)
        local done = wj.label("done")
        wj.block(done, function()
            wj.if_(x:eq(0), function()
                wj.br(done)
            end)
            out(9)
        end)
        return out
    end,
}

local early_goto = wj.fn {
    name = "early_goto",
    params = { wj.i32 "x" },
    ret = wj.i32,
    body = function(x)
        local out = wj.i32("out", 5)
        local done = wj.label("done")
        wj.block(done, function()
            wj.if_(x:lt(0), function()
                wj.goto_(done)
            end)
            out(11)
        end)
        return out
    end,
}

local for_break_continue = wj.fn {
    name = "for_break_continue",
    params = { wj.i32 "n" },
    ret = wj.i32,
    body = function(n)
        local i = wj.i32("i")
        local acc = wj.i32("acc", 0)
        wj.for_(i, n, function(ctrl)
            wj.if_(i:eq(3), function()
                ctrl:continue_()
            end)
            wj.if_(i:eq(6), function()
                ctrl:break_()
            end)
            acc(acc + i)
        end)
        return acc
    end,
}

local structured_loop = wj.fn {
    name = "structured_loop",
    params = { wj.i32 "n" },
    ret = wj.i32,
    body = function(n)
        local i = wj.i32("i", 0)
        local acc = wj.i32("acc", 0)
        local spin = wj.label("spin")
        wj.loop(spin, function(ctrl)
            i(i + 1)
            wj.if_(i:lt(3), function()
                ctrl:continue_()
            end)
            wj.if_(i:gt(n), function()
                ctrl:break_()
            end)
            acc(acc + i)
            wj.if_(acc:gt(20), function()
                ctrl:break_()
            end)
        end)
        return acc
    end,
}

local mod = wj.module({ early_block, early_goto, for_break_continue, structured_loop })
local wat = mod:wat()

has(wat, '(block $done_')
has(wat, '(br $done_')
has(wat, '(block $continue_')
has(wat, '(loop $spin_')
has(wat, '(br $spin_')

local inst = mod:compile(wm.engine())
assert(inst:fn("early_block")(0) == 1)
assert(inst:fn("early_block")(7) == 9)
assert(inst:fn("early_goto")(-1) == 5)
assert(inst:fn("early_goto")(3) == 11)
assert(inst:fn("for_break_continue")(10) == 12)
assert(inst:fn("structured_loop")(5) == 12)
assert(inst:fn("structured_loop")(20) == 25)

print("watjit: structured control ok")
