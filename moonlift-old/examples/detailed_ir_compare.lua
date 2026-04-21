local ml = require('moonlift')
ml.use()

print("=== Detailed IR Comparison ===\n")

local N = 100000000

-- Version 1: Source with implicit literals
local src_implicit = code[[
func test(n: i64) -> i64
    var x: i64 = 0
    var i: i64 = 0
    while i < n do
        x = x + i
        i = i + 1
    end
    return x
end
]]

-- Version 2: Builder with i64 literals
local builder_i64 = (func "test") {
    i64"n",
    function(n)
        return block(function()
            local x = var(i64(0))
            local i = var(i64(0))
            while_(i:lt(n), function()
                x:set(x + i)
                i:set(i + i64(1))
            end)
            return x
        end)
    end,
}

-- Version 3: Builder with i32 literals (like source)
local builder_i32 = (func "test") {
    i64"n",
    function(n)
        return block(function()
            local x = var(i64(0))
            local i = var(i64(0))
            while_(i:lt(n), function()
                x:set(x + i)
                i:set(i + i32(1))
            end)
            return x
        end)
    end,
}

local h1 = src_implicit()
local h2 = builder_i64()
local h3 = builder_i32()

print("--- Runtime (n=" .. N .. ") ---")
for run = 1, 3 do
    local t1 = os.clock()
    local r1 = h1(N)
    local t2 = os.clock()
    print(string.format("Source i64 + implicit(1):  %.3f ms  result=%d", (t2 - t1) * 1000, r1))

    local t3 = os.clock()
    local r2 = h2(N)
    local t4 = os.clock()
    print(string.format("Builder i64 + i64(1):      %.3f ms  result=%d", (t4 - t3) * 1000, r2))

    local t5 = os.clock()
    local r3 = h3(N)
    local t6 = os.clock()
    print(string.format("Builder i64 + i32(1):      %.3f ms  result=%d", (t6 - t5) * 1000, r3))
    print()
end
