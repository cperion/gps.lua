print("=== Terra Fair Benchmark ===\n")

local N = 10000000

local terra collatz_sum(n: int64): int64
    var total: int64 = 0
    var x: int64 = 1
    while x < n do
        var c: int64 = x
        var steps: int64 = 0
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

local t1 = os.clock()
collatz_sum:compile()
local t2 = os.clock()
print(string.format('Compile: %.3f ms', (t2 - t1) * 1000))

print('\n--- Collatz Steps (n=' .. N .. ') ---')
local t3 = os.clock()
local r1 = collatz_sum(N)
local t4 = os.clock()
print(string.format('Terra: %.3f ms  result=%d', (t4 - t3) * 1000, r1))
