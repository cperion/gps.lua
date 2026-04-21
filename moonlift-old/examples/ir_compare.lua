local ml = require('moonlift')
ml.use()

print("=== Source vs Builder Runtime Comparison ===\n")

-- Source version
local src = code[[
func test(n: i64) -> i64
    var x: i64 = 0
    var i: i64 = 0
    while i < n do
        x = x + i
        i = i + 1
    end
    return x
end
]]

-- Builder version
local builder = (func "test") {
    i64"n",
    function(n)
        return block(function()
            local x = var(i64(0))
            local i = var(i64(0))
            while_(i:lt(n), function()
                x:set(x + i)
                i:set(i + i64(1))
            end)
            return x
        end)
    end
}

local src_h = src()
local builder_h = builder()

local N = 100000000
print("--- Runtime (n=" .. N .. ") ---")

for run = 1, 3 do
    local t1 = os.clock()
    local r1 = src_h(N)
    local t2 = os.clock()
    print(string.format("Source:   %.3f ms  result=%d", (t2 - t1) * 1000, r1))

    local t3 = os.clock()
    local r2 = builder_h(N)
    local t4 = os.clock()
    print(string.format("Builder:  %.3f ms  result=%d", (t4 - t3) * 1000, r2))
    print()
end
