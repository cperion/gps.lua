local ml = require('moonlift')
ml.use()

print("=== Moonlift Add Loop ===\n")

local N = 1000000000

local ml_add = code[[
func add_loop(n: i64) -> i64
    var x: i64 = 0
    var i: i64 = 0
    while i < n do
        x = x + 1
        i = i + 1
    end
    return x
end
]]
local ml_h = ml_add()

local t1 = os.clock()
local r1 = ml_h(N)
local t2 = os.clock()
print(string.format('Moonlift: %.3f ms  result=%d', (t2 - t1) * 1000, r1))
