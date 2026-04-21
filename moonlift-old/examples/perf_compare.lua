local ml = require('moonlift')
ml.use()

print('=== Source vs Builder vs LuaJIT ===\n')

local N = 10000000

local sum_source = code[[
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
local sum_source_h = sum_source()

local sum_builder_h = (func "sum_loop") {
    i64"n",
    function(n)
        return block(function()
            local i = var(i64(0))
            local acc = var(i64(0))
            while_(i:lt(n), function()
                i:set(i + i64(1))
                acc:set(acc + i)
            end)
            return acc
        end)
    end,
}()

local function sum_lua(n)
    local i, acc = 0, 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end

print('--- Sum Loop (n=' .. N .. ') ---')
for name, f in pairs{Source=sum_source_h, Builder=sum_builder_h, LuaJIT=sum_lua} do
    local t = os.clock()
    local r = f(N)
    local elapsed = os.clock() - t
    print(string.format('%-10s %.3f ms  result=%d', name, elapsed * 1000, r))
end

local switch_source = code[[
func switch_bench(n: i32) -> i32
    var acc: i32 = 0
    var i: i32 = 0
    while i < n do
        let r: i32 = i % 8
        let term: i32 = switch r do
            case 0 then 1
            case 1 then 2
            case 2 then 3
            case 3 then 4
            case 4 then 5
            case 5 then 6
            case 6 then 7
            case 7 then 8
            default then 0
        end
        acc = acc + term
        i = i + 1
    end
    return acc
end
]]
local switch_source_h = switch_source()

local switch_builder_h = (func "switch_bench") {
    i32"n",
    function(n)
        return block(function()
            local acc = var(i32(0))
            local i = var(i32(0))
            while_(i:lt(n), function()
                local r = let(i % i32(8))
                local term = let(switch_(r, {
                    [i32(0)] = function() return i32(1) end,
                    [i32(1)] = function() return i32(2) end,
                    [i32(2)] = function() return i32(3) end,
                    [i32(3)] = function() return i32(4) end,
                    [i32(4)] = function() return i32(5) end,
                    [i32(5)] = function() return i32(6) end,
                    [i32(6)] = function() return i32(7) end,
                    [i32(7)] = function() return i32(8) end,
                    default = function() return i32(0) end,
                }))
                acc:set(acc + term)
                i:set(i + i32(1))
            end)
            return acc
        end)
    end,
}()

local function switch_lua(n)
    local acc = 0
    for i = 0, n - 1 do
        local r = i % 8
        if r == 0 then acc = acc + 1
        elseif r == 1 then acc = acc + 2
        elseif r == 2 then acc = acc + 3
        elseif r == 3 then acc = acc + 4
        elseif r == 4 then acc = acc + 5
        elseif r == 5 then acc = acc + 6
        elseif r == 6 then acc = acc + 7
        else acc = acc + 8
        end
    end
    return acc
end

print('\n--- Switch Dispatch (n=' .. N .. ') ---')
for name, f in pairs{Source=switch_source_h, Builder=switch_builder_h, LuaJIT=switch_lua} do
    local t = os.clock()
    local r = f(N)
    local elapsed = os.clock() - t
    print(string.format('%-10s %.3f ms  result=%d', name, elapsed * 1000, r))
end

print('\n=== Done ===')
