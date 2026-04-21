local ml = require('moonlift')
ml.use()
local backend = rawget(_G, '__moonlift_backend')
local src = [[
func sum_arr() -> i32
    let xs: [4]i32 = [4]i32 { 10, 11, 12, 9 }
    return loop i: i32 = 0, acc: i32 = 0 while i < 4
    next
        acc = acc + xs[i]
        i = i + 1
    end -> acc
end
]]
print(assert(backend.dump_optimized_source_code_spec(src)))
