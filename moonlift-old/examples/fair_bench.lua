local ml = require('moonlift')
ml.use()
local exact = ml.exact_tostring

print("=== Fair Benchmark (LLVM can't optimize away) ===\n")

local N = 10000000

local ml_collatz = code[[
func collatz_sum(n: i64) -> i64
    var total: i64 = 0
    var x: i64 = 1
    while x < n do
        var c: i64 = x
        var steps: i64 = 0
        while c ~= 1 do
            if c % 2 == 0 then
                c = c / 2
            else
                c = c * 3 + 1
            end
            steps = steps + 1
        end
        total = total + steps
        x = x + 1
    end
    return total
end
]]
local ml_h = ml_collatz()

print('--- Collatz Steps (n=' .. N .. ') ---')
local t1 = os.clock()
local r1 = ml_h(N)
local t2 = os.clock()
print(string.format('Moonlift: %.3f ms  result=%s', (t2 - t1) * 1000, exact(r1)))
