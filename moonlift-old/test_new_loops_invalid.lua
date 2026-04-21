local ml = require('moonlift')
ml.use()

local function expect_fail(label, src, needle)
    local ok, err = pcall(function()
        local f = code(src)
        f()
    end)
    assert(not ok, label .. ': expected failure')
    local msg = tostring(err)
    assert(msg:find(needle, 1, true), label .. ': missing error substring: ' .. needle .. '\nactual: ' .. msg)
    print(label .. ' -> ok (' .. needle .. ')')
end

expect_fail(
    'phi-loop missing next',
    [[
func bad(n: i32) -> i32
    return loop i: i32 = 0, acc: i32 = 0 while i < n
    end -> acc
end
]],
    'loop next section is missing'
)

expect_fail(
    'phi-loop direct carry assignment in body',
    [[
func bad(n: i32) -> i32
    return loop i: i32 = 0, acc: i32 = 0 while i < n
        acc = acc + 1
    next
        i = i + 1
        acc = acc
    end -> acc
end
]],
    'canonical loop bodies must update loop variables only through the next section'
)

expect_fail(
    'phi-loop break forbidden',
    [[
func bad(n: i32) -> i32
    return loop i: i32 = 0 while i < n
        break
    next
        i = i + 1
    end -> i
end
]],
    'canonical loop bodies do not support break, continue, or return'
)

expect_fail(
    'domain-loop assigning index in body',
    [[
func bad(n: i32) -> i32
    return loop i over range(n), acc: i32 = 0
        i = i + 1
    next
        acc = acc + 1
    end -> acc
end
]],
    'canonical loop bodies must not assign to the loop index or carried state directly'
)

expect_fail(
    'domain-loop next assigns index',
    [[
func bad(n: i32) -> i32
    return loop i over range(n), acc: i32 = 0
    next
        i = i + 1
        acc = acc + 1
    end -> acc
end
]],
    "loop next section has no carried state named 'i'"
)

expect_fail(
    'duplicate next binding',
    [[
func bad(n: i32) -> i32
    return loop i: i32 = 0, acc: i32 = 0 while i < n
    next
        i = i + 1
        acc = acc + 1
        acc = acc + 2
    end -> acc
end
]],
    "duplicate loop next binding 'acc'"
)

print('\ninvalid loop syntax tests ok')
