local ml = require('moonlift')
ml.use()

-- Pattern A: increment at END (should rewrite)
local sum_end = code[[
func sum_end(n: i64) -> i64
    var acc: i64 = 0
    var i: i64 = 0
    while i < n do
        acc = acc + i
        i = i + 1
    end
    return acc
end
]]

-- Pattern B: increment at START (current benchmark)
local sum_start = code[[
func sum_start(n: i64) -> i64
    var acc: i64 = 0
    var i: i64 = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end
]]

local function bench(name, f, n)
    local t = os.clock()
    local r = f(n)
    print(string.format("%s: %.6f sec", name, os.clock() - t))
end

print("Pattern A (increment at END):")
bench("sum_end", sum_end(), 100000000)

print("Pattern B (increment at START):")
bench("sum_start", sum_start(), 100000000)
