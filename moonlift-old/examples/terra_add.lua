print("=== Terra Add Loop ===\n")

local N = 1000000000

local terra add_loop(n: int64): int64
    var x: int64 = 0
    var i: int64 = 0
    while i < n do
        x = x + 1
        i = i + 1
    end
    return x
end

local t1 = os.clock()
add_loop:compile()
local t2 = os.clock()
print(string.format('Compile: %.3f ms', (t2 - t1) * 1000))

local t3 = os.clock()
local r1 = add_loop(N)
local t4 = os.clock()
print(string.format('Terra: %.3f ms  result=%d', (t4 - t3) * 1000, r1))
