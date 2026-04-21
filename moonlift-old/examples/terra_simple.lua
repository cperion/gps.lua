print("=== Terra Simple Loop ===\n")

local N = 100000000

local terra arithmetic(n: int64): int64
    var x: int64 = 1
    var i: int64 = 0
    while i < n do
        x = (x * 1103515245 + 12345) % 2147483648
        i = i + 1
    end
    return x
end

local t1 = os.clock()
arithmetic:compile()
local t2 = os.clock()
print(string.format('Compile: %.3f ms', (t2 - t1) * 1000))

local t3 = os.clock()
local r1 = arithmetic(N)
local t4 = os.clock()
print(string.format('Terra: %.3f ms  result=%d', (t4 - t3) * 1000, r1))
