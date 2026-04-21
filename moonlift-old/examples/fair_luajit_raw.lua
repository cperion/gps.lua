-- Raw LuaJIT fair benchmark.
-- Run with: ./target/release/moonlift run examples/fair_luajit_raw.lua

local function collatz_sum(n)
    local total = 0
    local x = 1
    while x < n do
        local c = x
        local steps = 0
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

print("=== Raw LuaJIT Fair Benchmark ===\n")

local N = 10000000
print('--- Collatz Steps (n=' .. N .. ') ---')
local t1 = os.clock()
local r = collatz_sum(N)
local t2 = os.clock()
print(string.format('LuaJIT: %.3f ms  result=%d', (t2 - t1) * 1000, r))
