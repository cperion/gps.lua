local ml = require('moonlift')
ml.use()

print("=== Moonlift Simple Loop ===\n")

local N = 100000000

local ml_arith = code[[
func arithmetic(n: i64) -> i64
    var x: i64 = 1
    var i: i64 = 0
    while i < n do
        x = (x * 1103515245 + 12345) % 2147483648
        i = i + 1
    end
    return x
end
]]
local ml_h = ml_arith()

local t1 = os.clock()
local r1 = ml_h(N)
local t2 = os.clock()
print(string.format('Moonlift: %.3f ms  result=%d', (t2 - t1) * 1000, r1))
