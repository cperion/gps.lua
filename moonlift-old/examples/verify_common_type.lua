local ml = require('moonlift')
ml.use()

print("=== Verifying common_type behavior ===\n")

-- In source, the literal "1" becomes types.i32(1)
-- But does it actually go through __add?

local i64_val = i64(42)
local i32_val = i32(1)

print("i64_val:", i64_val, "type:", i64_val.t.name)
print("i32_val:", i32_val, "type:", i32_val.t.name)

-- What does is_expr return?
print("is_expr(i64_val):", is_expr and is_expr(i64_val) or "N/A")
print("is_expr(i32_val):", is_expr and is_expr(i32_val) or "N/A")

-- Try to add them
local ok, result = pcall(function()
    return i64_val + i32_val
end)

if ok then
    print("i64 + i32 succeeded:", result)
else
    print("i64 + i32 failed:", result)
end

-- What about i64 + raw number?
local ok2, result2 = pcall(function()
    return i64_val + 1
end)

if ok2 then
    print("i64 + 1 succeeded:", result2)
else
    print("i64 + 1 failed:", result2)
end
