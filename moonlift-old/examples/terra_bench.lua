print("=== Terra Compilation Benchmark ===\n")

local N = 10000000

local terra sum_loop(n: int64): int64
    var i: int64 = 0
    var acc: int64 = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end

local t1 = os.clock()
sum_loop:compile()
local t2 = os.clock()
print(string.format("Compile time: %.3f ms", (t2 - t1) * 1000))

local t3 = os.clock()
local r1 = sum_loop(N)
local t4 = os.clock()
print(string.format("Run time: %.3f ms  result=%d", (t4 - t3) * 1000, r1))

local function sum_lua(n)
    local i, acc = 0, 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end

local t5 = os.clock()
local r2 = sum_lua(N)
local t6 = os.clock()
print(string.format("LuaJIT: %.3f ms  result=%d", (t6 - t5) * 1000, r2))

print("\n--- Multiple Compiles ---")
local times = {}
for i = 1, 20 do
    local t = terra(n: int64): int64
        var j: int64 = 0
        var acc: int64 = 0
        while j < n do
            j = j + 1
            acc = acc + j
        end
        return acc
    end
    local start = os.clock()
    t:compile()
    table.insert(times, os.clock() - start)
end

local total = 0
for _, t in ipairs(times) do total = total + t end
print(string.format("20 compiles: %.3f ms total, %.3f ms/iter", total * 1000, (total / 20) * 1000))
