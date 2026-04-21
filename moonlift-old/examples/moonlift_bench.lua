local ml = require('moonlift')
ml.use()

print("=== Moonlift Compilation Benchmark ===\n")

local N = 10000000

local t1 = os.clock()
local sum_loop = code[[
func sum_loop(n: i64) -> i64
    var i: i64 = 0
    var acc: i64 = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end
]]
local sum_loop_h = sum_loop()
local t2 = os.clock()
print(string.format("Compile time: %.3f ms", (t2 - t1) * 1000))

local t3 = os.clock()
local r1 = sum_loop_h(N)
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
    local source = string.format([[
func sum_%d(n: i64) -> i64
    var j: i64 = 0
    var acc: i64 = 0
    while j < n do
        j = j + 1
        acc = acc + j
    end
    return acc
end
]], i)
    local start = os.clock()
    local f = code(source)()
    table.insert(times, os.clock() - start)
end

local total = 0
for _, t in ipairs(times) do total = total + t end
print(string.format("20 compiles: %.3f ms total, %.3f ms/iter", total * 1000, (total / 20) * 1000))
