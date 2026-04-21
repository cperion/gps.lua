local ml = require('moonlift')
ml.use()

print("=== Tracing type coercion ===\n")

-- What happens when we mix i64 and i32 in source?
local src = code[[
func test() -> i64
    var x: i64 = 0
    x = x + 1
    return x
end
]]

local h = src()
print("Source with i64 + i32 literal compiled OK")

-- Now what about builder?
local ok, err = pcall(function()
    local builder = (func "test") {
        function()
            return block(function()
                local x = var(i64(0))
                x:set(x + i32(1))
                return x
            end)
        end,
    }
    local h2 = builder()
end)

if not ok then
    print("Builder with i64 + i32(1) FAILED:", err)
end

-- What if we use a raw number?
local ok2, err2 = pcall(function()
    local builder2 = (func "test") {
        function()
            return block(function()
                local x = var(i64(0))
                x:set(x + 1)  -- raw Lua number, not i32(1)
                return x
            end)
        end,
    }
    local h3 = builder2()
    print("Builder with i64 + raw number compiled OK")
end)

if not ok2 then
    print("Builder with i64 + raw number FAILED:", err2)
end
