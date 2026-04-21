local ml = require('moonlift')
ml.use()

local debug = ml.debug
local backend = rawget(_G, '__moonlift_backend')

local function compare_case(name, src, builder_fn)
    local cmp = debug.compare_source_builder(src, builder_fn.lowered)
    print("== " .. name .. " ==")
    print("spec same:", cmp.spec.same)
    print("disasm same:", cmp.disasm.same)
    print("\n-- optimized source spec --")
    print(cmp.source_spec)
    print("\n-- optimized builder spec --")
    print(cmp.builder_spec)
    print("\n-- normalized source disasm --")
    print(cmp.disasm.lhs_normalized)
    print("\n-- normalized builder disasm --")
    print(cmp.disasm.rhs_normalized)
    print()
end

local function show_slice_bounds_case()
    local I32Slice = slice(i32)
    local builder = (func "sum_slice_affine2") {
        ptr(I32Slice)"s",
        function(s)
            return block(function()
                local acc = var(i32(0))
                for_range_(usize(0), s.len - usize(3), function(i)
                    acc:set(acc + s[(i + usize(1)) + usize(1)])
                end)
                return acc
            end)
        end,
    }

    local raw_spec = assert(backend.dump_spec(builder.lowered))
    local opt_spec = debug.dump_optimized_spec(builder.lowered)
    local raw_disasm = debug.dump_raw_disasm(builder.lowered)
    local opt_disasm = debug.dump_disasm(builder.lowered)

    print("== slice_bounds_affine2 ==")
    print("hoisted:", opt_spec:find("BoundsCheck {", 1, true) ~= nil and opt_spec:find("limit: None", 1, true) ~= nil)
    print("\n-- raw builder spec --")
    print(raw_spec)
    print("\n-- optimized builder spec --")
    print(opt_spec)
    print("\n-- normalized raw builder disasm --")
    print(debug.normalize_disasm(raw_disasm))
    print("\n-- normalized optimized builder disasm --")
    print(debug.normalize_disasm(opt_disasm))
    print()
end

local sum_src = [[
func sum(n: i64) -> i64
    var i: i64 = 0
    var acc: i64 = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end
]]

local sum_builder = (func "sum") {
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
}

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

local recur_builder = (func "recur_loop") {
    u64"n",
    function(n)
        return block(function()
            local x = var(u64(0))
            local i = var(u64(0))
            while_(i:lt(n), function()
                x:set(x * u64(1664525) + i + u64(1013904223))
                i:set(i + u64(1))
            end)
            return x
        end)
    end,
}

compare_case("sum", sum_src, sum_builder)
compare_case("recur_loop", recur_src, recur_builder)
show_slice_bounds_case()
