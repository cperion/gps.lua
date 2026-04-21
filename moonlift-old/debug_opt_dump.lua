local ml = require('moonlift')
ml.use()
local backend = rawget(_G, '__moonlift_backend')

local recur_src = [[
func recur_loop(n: u64) -> u64
    var x: u64 = 0
    var i: u64 = 0
    while i < n do
        x = x * 1664525 + i + 1013904223
        i = i + 1
    end
    return x
end
]]
print('--- recur source opt ---')
print(assert(backend.dump_optimized_source_code_spec(recur_src)))

local add_src = [[
func add_loop(n: i64) -> i64
    var x: i64 = 0
    var i: i64 = 0
    while i < n do
        x = x + 1
        i = i + 1
    end
    return x
end
]]
print('--- add source opt ---')
print(assert(backend.dump_optimized_source_code_spec(add_src)))

local src = [[
func sum_arr() -> i32
    let xs: [4]i32 = [4]i32 { 10, 11, 12, 9 }
    var acc: i32 = 0
    var i: i32 = 0
    while i < 4 do
        acc = acc + xs[i]
        i = i + 1
    end
    return acc
end
]]
print('--- static array opt ---')
print(assert(backend.dump_optimized_source_code_spec(src)))
