local ml = require('moonlift')
ml.use()

print("=== Type Investigation ===\n")

-- Check what types literals get
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

-- In source, what does "0" become?
-- From source_frontend.lua line 1798: types.i32(n)

-- In builder, what does i64(0) become?
local builder_i64 = i64(0)
local builder_i32 = i32(0)

print("Builder i64(0) type:", builder_i64.t and builder_i64.t.name or "unknown")
print("Builder i32(0) type:", builder_i32.t and builder_i32.t.name or "unknown")

-- The issue might be:
-- Source: i < n  ->  as_expr(i):lt(n)  where i is i64, n is i64
-- But the literal 1 in "i + 1" becomes i32

-- Let's test with explicit types
local src2 = code[[
func test2(n: i64) -> i64
    var x: i64 = 0
    var i: i64 = 0
    while i < n do
        x = x + i
        i = i + cast<i64>(1)
    end
    return x
end
]]

local h1 = src()
local h2 = src2()

local N = 100000000
print("\n--- Runtime (n=" .. N .. ") ---")

local t1 = os.clock()
local r1 = h1(N)
local t2 = os.clock()
print(string.format("Source (implicit 1): %.3f ms", (t2 - t1) * 1000))

local t3 = os.clock()
local r2 = h2(N)
local t4 = os.clock()
print(string.format("Source (cast 1):     %.3f ms", (t4 - t3) * 1000))
