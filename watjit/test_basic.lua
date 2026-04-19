package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

local add = wj.fn {
    name = "add",
    params = { wj.i32 "a", wj.i32 "b" },
    ret = wj.i32,
    body = function(a, b)
        return a + b
    end,
}

local accumulate = wj.fn {
    name = "accumulate",
    params = { wj.i32 "a", wj.i32 "b" },
    ret = wj.i32,
    body = function(a, b)
        local sum = wj.let(wj.i32, "sum", a)
        sum(sum + b)
        return sum
    end,
}

local sum_to = wj.fn {
    name = "sum_to",
    params = { wj.i32 "n" },
    ret = wj.i32,
    body = function(n)
        local i = wj.let(wj.i32, "i")
        local acc = wj.let(wj.i32, "acc", 0)
        wj.for_(i, n, function()
            acc(acc + i)
        end)
        return acc
    end,
}

local mod = wj.module({ add, accumulate, sum_to })
local wat = mod:wat()

has(wat, '(module')
has(wat, '(memory (export "memory") 1)')
has(wat, '(func $add (export "add")')
has(wat, '(param $a i32)')
has(wat, '(param $b i32)')
has(wat, '(result i32)')
has(wat, '(i32.add')
has(wat, '(func $accumulate (export "accumulate")')
has(wat, '(local $sum i32)')
has(wat, '(local.set $sum')
has(wat, '(func $sum_to (export "sum_to")')
has(wat, '(local $i i32)')
has(wat, '(local $acc i32)')
has(wat, '(block $break_')
has(wat, '(loop $loop_')
has(wat, '(br_if $break_')

print("watjit: basic WAT emission ok")
