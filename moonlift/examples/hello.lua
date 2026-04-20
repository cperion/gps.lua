local ml = require("moonlift")
ml.use()

print("hello from moonlift")
assert(__moonlift_runtime ~= nil)

assert(ml.add(20, 22) == 42)
print("ml.add(20, 22) =", ml.add(20, 22))

local plus_k = q.expr {
    params = { i32"x", i32"k" },
    body = function(x, k)
        return x + k
    end,
}

local square = q.expr {
    params = { i32"x" },
    body = function(x)
        local xx = let(x * x)
        return xx
    end,
}

local plus7 = (func "plus7") {
    i32"x",
    function(x)
        return plus_k(x, i32(7))
    end,
}

local plus7h = plus7()
local plus7h_again = plus7()
assert(plus7h_again == plus7h)
assert(plus7h(35) == 42)
print("plus7h(35) =", plus7h(35))

local affine = (func "affine_3x_plus_9") {
    i32"x",
    function(x)
        local x3 = let(x * i32(3))
        return x3 + i32(9)
    end,
}

local affineh = affine()
assert(affineh(11) == 42)
print("affineh(11) =", affineh(11))

local mix = (func "mix") {
    i32"x",
    i32"y",
    function(x, y)
        local twice_x = let(x * i32(2))
        return twice_x + y
    end,
}

local mixh = mix()
assert(mixh(20, 2) == 42)
print("mixh(20, 2) =", mixh(20, 2))

local abs = (func "abs") {
    i32"x",
    function(x)
        local zero = let(i32(0))
        return (x:lt(zero))(-x, x)
    end,
}

local absh = abs()
assert(absh(-42) == 42)
assert(absh(42) == 42)
print("absh(-42) =", absh(-42))
print("absh(42) =", absh(42))

local max2 = (func "max2") {
    i32"x",
    i32"y",
    function(x, y)
        return (x:gt(y))(x, y)
    end,
}

local max2h = max2()
assert(max2h(42, 9) == 42)
assert(max2h(5, 42) == 42)
print("max2h(42, 9) =", max2h(42, 9))
print("max2h(5, 42) =", max2h(5, 42))

local sumsq = (func "sumsq") {
    i32"x",
    i32"y",
    function(x, y)
        return square(x) + square(y)
    end,
}

local score = (func "score") {
    i32"x",
    i32"y",
    function(x, y)
        return block(function()
            local base = let(x + y)
            return (base:gt(i32(10)))(
                function()
                    local bonus = let(base * i32(2))
                    return bonus
                end,
                function()
                    local penalty = let(base - i32(1))
                    return penalty
                end
            )
        end)
    end,
}

local scoreh = score()
assert(scoreh(8, 13) == 42)
assert(scoreh(20, 1) == 42)
print("scoreh(8, 13) =", scoreh(8, 13))
print("scoreh(20, 1) =", scoreh(20, 1))

local half_plus_mod = (func "half_plus_mod") {
    i32"x",
    i32"y",
    function(x, y)
        return x / i32(2) + y % i32(10)
    end,
}

local half_plus_mod_h = half_plus_mod()
assert(half_plus_mod_h(64, 10) == 32)
assert(half_plus_mod_h(64, 20) == 32)
assert(half_plus_mod_h(80, 42) == 42)
print("half_plus_mod_h(80, 42) =", half_plus_mod_h(80, 42))

local both_positive_or_equal = (func "both_positive_or_equal") {
    i32"x",
    i32"y",
    function(x, y)
        local positive_pair = x:gt(i32(0)):and_(y:gt(i32(0)))
        local equal_pair = x:eq(y)
        local good = positive_pair:or_(equal_pair)
        return good(i32(42), i32(0))
    end,
}

local both_positive_or_equal_h = both_positive_or_equal()
assert(both_positive_or_equal_h(21, 21) == 42)
assert(both_positive_or_equal_h(10, 32) == 42)
assert(both_positive_or_equal_h(-1, 2) == 0)
print("both_positive_or_equal_h(10, 32) =", both_positive_or_equal_h(10, 32))

local triangular = (func "triangular") {
    i32"n",
    function(n)
        return block(function()
            local i = var(i32(0))
            local acc = var(i32(0))
            while_(i:lt(n), function()
                i:set(i + i32(1))
                acc:set(acc + i)
            end)
            return acc
        end)
    end,
}

local triangularh = triangular()
assert(triangularh(0) == 0)
assert(triangularh(1) == 1)
assert(triangularh(6) == 21)
print("triangularh(6) =", triangularh(6))

local i16_double = (func "i16_double") {
    i16"x",
    function(x)
        return x + x
    end,
}
local i16_double_h = i16_double()
assert(i16_double_h(21) == 42)
print("i16_double_h(21) =", i16_double_h(21))

local u8_sum = (func "u8_sum") {
    u8"x",
    u8"y",
    function(x, y)
        return x + y
    end,
}
local u8_sum_h = u8_sum()
assert(u8_sum_h(40, 2) == 42)
print("u8_sum_h(40, 2) =", u8_sum_h(40, 2))

local i64_sum = (func "i64_sum") {
    i64"x",
    i64"y",
    function(x, y)
        return x + y
    end,
}
local i64_sum_h = i64_sum()
assert(i64_sum_h(20, 22) == 42)
print("i64_sum_h(20, 22) =", i64_sum_h(20, 22))

local u32_half_plus_mod = (func "u32_half_plus_mod") {
    u32"x",
    u32"y",
    function(x, y)
        return x / u32(2) + y % u32(10)
    end,
}
local u32_half_plus_mod_h = u32_half_plus_mod()
assert(u32_half_plus_mod_h(80, 42) == 42)
print("u32_half_plus_mod_h(80, 42) =", u32_half_plus_mod_h(80, 42))

local u64_half_plus_mod = (func "u64_half_plus_mod") {
    u64"x",
    u64"y",
    function(x, y)
        return x / u64(2) + y % u64(10)
    end,
}
local u64_half_plus_mod_h = u64_half_plus_mod()
assert(u64_half_plus_mod_h(80, 42) == 42)
print("u64_half_plus_mod_h(80, 42) =", u64_half_plus_mod_h(80, 42))

local f32_mean = (func "f32_mean") {
    f32"x",
    f32"y",
    function(x, y)
        return (x + y) / f32(2)
    end,
}
local f32_mean_h = f32_mean()
assert(math.abs(f32_mean_h(40, 44) - 42) < 1e-5)
print("f32_mean_h(40, 44) =", f32_mean_h(40, 44))

local f64_mean = (func "f64_mean") {
    f64"x",
    f64"y",
    function(x, y)
        return (x + y) / f64(2)
    end,
}
local f64_mean_h = f64_mean()
assert(math.abs(f64_mean_h(40, 44) - 42) < 1e-12)
print("f64_mean_h(40, 44) =", f64_mean_h(40, 44))

local is_answer = (func "is_answer") {
    i32"x",
    function(x)
        return x:eq(i32(42))
    end,
}
local is_answer_h = is_answer()
assert(is_answer_h(42) == true)
assert(is_answer_h(41) == false)
print("is_answer_h(42) =", is_answer_h(42))

local mod = module {
    plus7,
    max2,
    sumsq,
    score,
    half_plus_mod,
    both_positive_or_equal,
    triangular,
    i16_double,
    u8_sum,
    i64_sum,
    u32_half_plus_mod,
    u64_half_plus_mod,
    f32_mean,
    f64_mean,
    is_answer,
}
local compiled = mod()
assert(compiled.plus7 == plus7h)
assert(compiled.max2 == max2h)
assert(compiled.score == scoreh)
assert(compiled.plus7(35) == 42)
assert(compiled.max2(7, 42) == 42)
assert(compiled.sumsq(5, 4) == 41)
assert(compiled.score(8, 13) == 42)
assert(compiled.half_plus_mod(80, 42) == 42)
assert(compiled.both_positive_or_equal(10, 32) == 42)
assert(compiled.triangular(6) == 21)
assert(compiled.i16_double(21) == 42)
assert(compiled.u8_sum(40, 2) == 42)
assert(compiled.i64_sum(20, 22) == 42)
assert(compiled.u32_half_plus_mod(80, 42) == 42)
assert(compiled.u64_half_plus_mod(80, 42) == 42)
assert(math.abs(compiled.f32_mean(40, 44) - 42) < 1e-5)
assert(math.abs(compiled.f64_mean(40, 44) - 42) < 1e-12)
assert(compiled.is_answer(42) == true)
print("module.plus7(35) =", compiled.plus7(35))
print("module.max2(7, 42) =", compiled.max2(7, 42))
print("module.sumsq(5, 4) =", compiled.sumsq(5, 4))
print("module.score(8, 13) =", compiled.score(8, 13))
print("module.half_plus_mod(80, 42) =", compiled.half_plus_mod(80, 42))
print("module.both_positive_or_equal(10, 32) =", compiled.both_positive_or_equal(10, 32))
print("module.triangular(6) =", compiled.triangular(6))
print("module.i16_double(21) =", compiled.i16_double(21))
print("module.u8_sum(40, 2) =", compiled.u8_sum(40, 2))
print("module.i64_sum(20, 22) =", compiled.i64_sum(20, 22))
print("module.u32_half_plus_mod(80, 42) =", compiled.u32_half_plus_mod(80, 42))
print("module.u64_half_plus_mod(80, 42) =", compiled.u64_half_plus_mod(80, 42))
print("module.f32_mean(40, 44) =", compiled.f32_mean(40, 44))
print("module.f64_mean(40, 44) =", compiled.f64_mean(40, 44))
print("module.is_answer(42) =", compiled.is_answer(42))

local s = stats()
assert(s.compile_hits >= 7)
assert(s.compile_misses >= 18)
assert(s.cache_entries == s.compiled_functions)
print("compile stats:", s.compile_hits, s.compile_misses, s.cache_entries, s.compiled_functions)

local ffi = require("ffi")

local Vec2 = struct_("Vec2", {
    { "x", f32 },
    { "y", f32 },
})
assert(Vec2.size == 8)
assert(Vec2.align == 4)
assert(Vec2.x.offset == 0)
assert(Vec2.y.offset == 4)
print("Vec2 size =", Vec2.size, "align =", Vec2.align)

local dot2d = (func "dot2d") {
    ptr(Vec2)"a",
    ptr(Vec2)"b",
    function(a, b)
        return a.x * b.x + a.y * b.y
    end,
}
local dot2dh = dot2d()

local buf = ffi.new("float[4]")
buf[0] = 3; buf[1] = 4
buf[2] = 2; buf[3] = 5
local a_ptr = tonumber(ffi.cast("intptr_t", buf))
local b_ptr = tonumber(ffi.cast("intptr_t", buf + 2))
local result = dot2dh(a_ptr, b_ptr)
assert(math.abs(result - 26) < 1e-5, "dot2d failed: " .. tostring(result))
print("dot2dh({3,4}, {2,5}) =", result)

local Pair = struct_("Pair", {
    { "a", i32 },
    { "b", i32 },
})
assert(Pair.size == 8)

local pair_sum = (func "pair_sum") {
    ptr(Pair)"p",
    function(p)
        return p.a + p.b
    end,
}
local pair_sum_h = pair_sum()

local pair_sum_ir = quote_ir {
    params = { ptr(Pair)"p" },
    body = function(p)
        local s = let(p.a + p.b)
        return s
    end,
}
local pair_sum_quote = (func "pair_sum_quote") {
    ptr(Pair)"p",
    pair_sum_ir,
}
local pair_sum_quote_h = pair_sum_quote()

local twice_plus_one_ir = quote_ir {
    params = { i32"x" },
    body = function(x)
        local y = let(x + i32(1))
        return y
    end,
}
local quote_twice = (func "quote_twice") {
    function()
        return twice_plus_one_ir:splice(i32(20)) + twice_plus_one_ir:splice(i32(20))
    end,
}
local quote_twice_h = quote_twice()

local forty_two_q = quote_expr(function()
    return i32(42)
end)
local quote_expr_auto = (func "quote_expr_auto") {
    function()
        return forty_two_q
    end,
}
local quote_expr_auto_h = quote_expr_auto()

local pair_plus_hole_q = quote_block {
    params = { ptr(Pair)"p" },
    body = function(p)
        local total = let(p.a + p.b)
        return total + hole("delta", i32)
    end,
}
local pair_plus_hole = (func "pair_plus_hole") {
    ptr(Pair)"p",
    function(p)
        return pair_plus_hole_q:bind { delta = i32(0) }:splice(p)
    end,
}
local pair_plus_hole_h = pair_plus_hole()

local hole_only_q = quote_expr(function()
    return hole("lhs", i32) + hole("rhs", i32)
end)
local hole_only = (func "hole_only") {
    function()
        return hole_only_q:bind { lhs = i32(20), rhs = i32(22) }:splice()
    end,
}
local hole_only_h = hole_only()

local add_one_q = q.expr {
    params = { i32"x" },
    body = function(x)
        return x + i32(1)
    end,
}
local add_two_q = add_one_q:map_expr(function(node)
    if node.tag == "i32" and node.value == 1 then
        return i32(2)
    end
end)
local add_two_rewrite = (func "add_two_rewrite") {
    i32"x",
    add_two_q,
}
local add_two_rewrite_h = add_two_rewrite()

local trim_dead_q = q.block {
    params = { i32"x" },
    body = function(x)
        local dead = let(i32(7))
        local y = let(x + i32(1))
        return y + dead - i32(7)
    end,
}
local trim_dead_rewrite_q = trim_dead_q:rewrite {
    stmt = function(stmt)
        if stmt.tag == "let" and stmt.init ~= nil and stmt.init.tag == "i32" and stmt.init.value == 7 then
            return false
        end
    end,
    expr = function(node)
        if node.tag == "sub" and node.rhs ~= nil and node.rhs.tag == "i32" and node.rhs.value == 7 then
            return node.lhs
        elseif node.tag == "add" and node.rhs ~= nil and node.rhs.tag == "local" and node.lhs ~= nil and node.lhs.tag == "local" then
            return node.lhs
        end
    end,
}
local trim_dead_rewrite = (func "trim_dead_rewrite") {
    i32"x",
    trim_dead_rewrite_q,
}
local trim_dead_rewrite_h = trim_dead_rewrite()

local hole_names = hole_only_q:query(function(kind, node)
    if kind == "expr" and node.tag == "quote_hole" then
        return node.name
    end
end)
assert(#hole_names == 2 and hole_names[1] == "lhs" and hole_names[2] == "rhs")

local walk_counts = { expr = 0, stmt = 0 }
trim_dead_q:walk(function(kind, node)
    if kind == "expr" then
        walk_counts.expr = walk_counts.expr + 1
    elseif kind == "stmt" then
        walk_counts.stmt = walk_counts.stmt + 1
    end
end)
assert(walk_counts.expr > 0 and walk_counts.stmt >= 2)

local let_stmt_names = q.query(trim_dead_q, {
    stmt = function(stmt)
        if stmt.tag == "let" then return stmt.name end
    end,
})
assert(#let_stmt_names == 2)

Pair:method("sum") {
    function(self)
        return self.a + self.b
    end,
}
Pair:method("bump_sum") {
    i32"delta",
    function(self, delta)
        self.a = self.a + delta
        return self.a + self.b
    end,
}

local pair_sum_method = (func "pair_sum_method") {
    ptr(Pair)"p",
    function(p)
        return p:sum()
    end,
}
local pair_sum_method_h = pair_sum_method()

local pair_proxy_method = (func "pair_proxy_method") {
    function()
        return block(function()
            local p = var(Pair { a = i32(20), b = i32(20) })
            return p:bump_sum(i32(2))
        end)
    end,
}
local pair_proxy_method_h = pair_proxy_method()

local pbuf = ffi.new("int32_t[2]")
pbuf[0] = 20; pbuf[1] = 22
local p_ptr = tonumber(ffi.cast("intptr_t", pbuf))
assert(pair_sum_h(p_ptr) == 42)
assert(pair_sum_quote_h(p_ptr) == 42)
assert(quote_twice_h() == 42)
assert(quote_expr_auto_h() == 42)
assert(pair_plus_hole_h(p_ptr) == 42)
assert(hole_only_h() == 42)
assert(add_two_rewrite_h(40) == 42)
assert(trim_dead_rewrite_h(41) == 42)
assert(pair_sum_method_h(p_ptr) == 42)
assert(pair_proxy_method_h() == 42)
print("pair_sum_h({20, 22}) =", pair_sum_h(p_ptr))
print("pair_sum_quote_h({20, 22}) =", pair_sum_quote_h(p_ptr))
print("quote_twice_h() =", quote_twice_h())
print("quote_expr_auto_h() =", quote_expr_auto_h())
print("pair_plus_hole_h({20, 22}) =", pair_plus_hole_h(p_ptr))
print("hole_only_h() =", hole_only_h())
print("add_two_rewrite_h(40) =", add_two_rewrite_h(40))
print("trim_dead_rewrite_h(41) =", trim_dead_rewrite_h(41))
print("pair_sum_method_h({20, 22}) =", pair_sum_method_h(p_ptr))
print("pair_proxy_method_h() =", pair_proxy_method_h())

local swap_pair = (func "swap_pair") {
    ptr(Pair)"p",
    void,
    function(p)
        local tmp = let(p.a)
        p.a = p.b
        p.b = tmp
    end,
}
local swap_pair_h = swap_pair()
local swap_out = swap_pair_h(p_ptr)
assert(swap_out == nil)
assert(pbuf[0] == 22 and pbuf[1] == 20)
print("swap_pair_h: swapped to", pbuf[0], pbuf[1])

local IntArray = array(i32, 4)
assert(IntArray.size == 16)
assert(IntArray.elem == i32)
assert(IntArray.count == 4)
print("IntArray size =", IntArray.size)

local array_sum4 = (func "array_sum4") {
    ptr(i32)"arr",
    function(arr)
        return block(function()
            local acc = var(i32(0))
            local i = var(i32(0))
            while_(i:lt(i32(4)), function()
                local elem = let(arr[i])
                acc:set(acc + elem)
                i:set(i + i32(1))
            end)
            return acc
        end)
    end,
}
local array_sum4_h = array_sum4()

local abuf = ffi.new("int32_t[4]")
abuf[0] = 10; abuf[1] = 11; abuf[2] = 12; abuf[3] = 9
local a_arr_ptr = tonumber(ffi.cast("intptr_t", abuf))
assert(array_sum4_h(a_arr_ptr) == 42)
print("array_sum4_h({10,11,12,9}) =", array_sum4_h(a_arr_ptr))

local array_set = (func "array_set") {
    ptr(i32)"arr",
    i32"idx",
    function(arr, idx)
        return block(function()
            arr[idx] = i32(99)
            return i32(0)
        end)
    end,
}
local array_set_h = array_set()
array_set_h(a_arr_ptr, 2)
assert(abuf[2] == 99)
print("array_set_h: arr[2] =", abuf[2])

local forty_two = (func "forty_two") {
    function()
        return i32(42)
    end,
}
local forty_two_h = forty_two()
assert(forty_two_h() == 42)
print("forty_two_h() =", forty_two_h())

local sum3 = (func "sum3") {
    i32"a",
    i32"b",
    i32"c",
    function(a, b, c)
        return a + b + c
    end,
}
local sum3_h = sum3()
assert(sum3_h(10, 20, 12) == 42)
print("sum3_h(10,20,12) =", sum3_h(10, 20, 12))

local sum4 = (func "sum4") {
    i32"a",
    i32"b",
    i32"c",
    i32"d",
    function(a, b, c, d)
        return a + b + c + d
    end,
}
local sum4_h = sum4()
assert(sum4_h(10, 20, 7, 5) == 42)
print("sum4_h(10,20,7,5) =", sum4_h(10, 20, 7, 5))

local bit_ops = (func "bit_ops") {
    u32"x",
    function(x)
        local masked = let(x:band(u32(0xff)))
        local mixed = let(masked:bxor(u32(0x80)))
        return mixed:shr_u(u32(1))
    end,
}
local bit_ops_h = bit_ops()
assert(bit_ops_h(212) == 42)
print("bit_ops_h(212) =", bit_ops_h(212))

local cast_ops = (func "cast_ops") {
    u8"x",
    function(x)
        local wide = let(zext(u32, x))
        local top = let(wide:shl(u32(24)))
        local f = let(bitcast(f32, top))
        local bits = let(bitcast(u32, f))
        return bits:shr_u(u32(24))
    end,
}
local cast_ops_h = cast_ops()
assert(cast_ops_h(42) == 42)
print("cast_ops_h(42) =", cast_ops_h(42))

local Status = enum("Status", u8, {
    Idle = 0,
    Busy = 1,
    Done = 42,
})

local status_code = (func "status_code") {
    function()
        return Status.Done
    end,
}
local status_code_h = status_code()
assert(status_code_h() == 42)
print("status_code_h() =", status_code_h())

local is_done = (func "is_done") {
    Status"s",
    function(s)
        return s:eq(Status.Done)
    end,
}
local is_done_h = is_done()
assert(is_done_h(42) == true)
assert(is_done_h(1) == false)
print("is_done_h(42) =", is_done_h(42))

local I32Slice = slice(i32)
assert(I32Slice.size == 16)
assert(I32Slice.ptr.offset == 0)
assert(I32Slice.len.offset == 8)
print("I32Slice size =", I32Slice.size)

local sum_slice = (func "sum_slice") {
    ptr(I32Slice)"s",
    function(s)
        return block(function()
            local acc = var(i32(0))
            local i = var(usize(0))
            while_(i:lt(s.len), function()
                acc:set(acc + s.ptr[i])
                i:set(i + usize(1))
            end)
            return acc
        end)
    end,
}
local sum_slice_h = sum_slice()

local slice_header = ffi.new("uint64_t[2]")
slice_header[0] = tonumber(ffi.cast("intptr_t", abuf))
slice_header[1] = 4
local slice_ptr = tonumber(ffi.cast("intptr_t", slice_header))
assert(sum_slice_h(slice_ptr) == 129)
print("sum_slice_h(...) =", sum_slice_h(slice_ptr))

local NumberBits = union("NumberBits", {
    { "i", i32 },
    { "u", u32 },
    { "f", f32 },
})
NumberBits:method("as_i32") {
    function(self)
        return self.i
    end,
}
local union_method = (func "union_method") {
    ptr(NumberBits)"p",
    function(p)
        return p:as_i32()
    end,
}
local union_method_h = union_method()
assert(NumberBits.size == 4)
assert(NumberBits.i.offset == 0 and NumberBits.f.offset == 0)
print("NumberBits size =", NumberBits.size)
local nbbuf = ffi.new("int32_t[1]")
nbbuf[0] = 42
local nbptr = tonumber(ffi.cast("intptr_t", nbbuf))
assert(union_method_h(nbptr) == 42)
print("union_method_h(...) =", union_method_h(nbptr))

local TaggedValue = tagged_union("TaggedValue", {
    base = u8,
    variants = {
        I32 = { { "value", i32 } },
        Pair = { { "a", i16 }, { "b", i16 } },
    },
})
TaggedValue:method("tag_code") {
    function(self)
        return zext(i32, self.tag)
    end,
}
local tagged_tag_code = (func "tagged_tag_code") {
    ptr(TaggedValue)"p",
    function(p)
        return p:tag_code()
    end,
}
local tagged_tag_code_h = tagged_tag_code()
assert(TaggedValue.Tag.I32 ~= nil)
assert(TaggedValue.Payload.size >= 4)
assert(TaggedValue.tag.offset == 0)
print("TaggedValue size =", TaggedValue.size)
local tv_code_buf = ffi.new("uint8_t[?]", TaggedValue.size)
local tv_code_ptr = tonumber(ffi.cast("intptr_t", tv_code_buf))
local tv_code_view = ffi.cast("uint8_t*", tv_code_buf)
tv_code_view[0] = TaggedValue.Pair.node.value
assert(tagged_tag_code_h(tv_code_ptr) == TaggedValue.Pair.node.value)
print("tagged_tag_code_h(...) =", tagged_tag_code_h(tv_code_ptr))

local switch_status = (func "switch_status") {
    Status"s",
    function(s)
        return switch_(s, {
            [Status.Idle] = function() return i32(0) end,
            [Status.Busy] = function() return i32(1) end,
            default = function() return i32(42) end,
        })
    end,
}
local switch_status_h = switch_status()
assert(switch_status_h(0) == 0)
assert(switch_status_h(1) == 1)
assert(switch_status_h(42) == 42)
print("switch_status_h(42) =", switch_status_h(42))

local bool_not = (func "bool_not") {
    bool"x",
    function(x)
        return x:not_()
    end,
}
local bool_not_h = bool_not()
assert(bool_not_h(false) == true)
assert(bool_not_h(true) == false)
print("bool_not_h(false) =", bool_not_h(false))
print("bool_not_h(true) =", bool_not_h(true))

local bool_not_select = (func "bool_not_select") {
    bool"x",
    function(x)
        return x:not_()(i32(2), i32(1))
    end,
}
local bool_not_select_h = bool_not_select()
assert(bool_not_select_h(false) == 2)
assert(bool_not_select_h(true) == 1)
print("bool_not_select_h(false) =", bool_not_select_h(false))
print("bool_not_select_h(true) =", bool_not_select_h(true))

local function make_stable_switch_case()
    return (func "stable_switch_case") {
        i32"x",
        function(x)
            return switch_(x, {
                [i32(0)] = function() return i32(0) end,
                [i32(1)] = function() return i32(1) end,
                [i32(2)] = function() return i32(2) end,
                default = function() return i32(3) end,
            })
        end,
    }
end
local stable_switch_case_h = make_stable_switch_case()()
local stable_switch_case_handle = stable_switch_case_h.handle
for _ = 1, 16 do
    local h = make_stable_switch_case()()
    assert(h.handle == stable_switch_case_handle)
end
assert(stable_switch_case_h(0) == 0)
assert(stable_switch_case_h(1) == 1)
assert(stable_switch_case_h(2) == 2)
assert(stable_switch_case_h(9) == 3)
print("stable_switch_case_h(9) =", stable_switch_case_h(9))

local break_once = (func "break_once") {
    i32"n",
    function(n)
        return block(function()
            local i = var(i32(0))
            while_(i:lt(n), function()
                i:set(i + i32(1))
                break_()
            end)
            return i
        end)
    end,
}
local break_once_h = break_once()
assert(break_once_h(10) == 1)
print("break_once_h(10) =", break_once_h(10))

local continue_count = (func "continue_count") {
    i32"n",
    function(n)
        return block(function()
            local i = var(i32(0))
            local acc = var(i32(0))
            while_(i:lt(n), function()
                i:set(i + i32(1))
                acc:set(acc + i)
                continue_()
            end)
            return acc
        end)
    end,
}
local continue_count_h = continue_count()
assert(continue_count_h(3) == 6)
print("continue_count_h(3) =", continue_count_h(3))

local bad_break_in_value = (func "bad_break_in_value") {
    i32"n",
    function(n)
        return block(function()
            local i = var(i32(0))
            while_(i:lt(n), function()
                local x = let(block(function()
                    break_()
                    return i32(123)
                end))
                i:set(i + x)
            end)
            return i
        end)
    end,
}
local ok_bad_break, err_bad_break = pcall(function()
    return bad_break_in_value()
end)
assert(ok_bad_break == false)
assert(tostring(err_bad_break):find("expression block terminated via break/continue", 1, true) ~= nil)
print("bad_break_in_value compile error ok")

local add2 = (func "add2") {
    i32"x",
    function(x)
        return x + i32(2)
    end,
}
local add2_h = add2()
local use_add2 = (func "use_add2") {
    i32"x",
    function(x)
        return invoke(add2, x) * i32(2)
    end,
}
local use_add2_h = use_add2()
assert(use_add2_h(19) == 42)
print("use_add2_h(19) =", use_add2_h(19))

local swap_twice = (func "swap_twice") {
    ptr(Pair)"p",
    void,
    function(p)
        invoke(swap_pair, p)
        invoke(swap_pair, p)
    end,
}
local swap_twice_h = swap_twice()
swap_twice_h(p_ptr)
assert(pbuf[0] == 22 and pbuf[1] == 20)
print("swap_twice_h kept pair as", pbuf[0], pbuf[1])

ffi.cdef[[ int abs(int x); ]]
local libc = import_module("libc", ffi.C)
local c_abs = libc:extern("abs") {
    i32"x",
    i32,
}
local use_abs = (func "use_abs") {
    i32"x",
    function(x)
        return invoke(c_abs, x)
    end,
}
local use_abs_h = use_abs()
assert(use_abs_h(-42) == 42)
print("use_abs_h(-42) =", use_abs_h(-42))

local memops = (func "memops") {
    ptr(u8)"dst",
    ptr(u8)"src",
    function(dst, src)
        return block(function()
            memcpy(dst, src, usize(4))
            dst[1] = u8(99)
            memmove(dst + cast(ptr(u8), usize(4)), dst, usize(4))
            memset(dst + cast(ptr(u8), usize(8)), u8(7), usize(2))
            local c = let(memcmp(dst, src, usize(4)))
            return zext(i32, dst[0]) + zext(i32, dst[1]) + zext(i32, dst[4]) + zext(i32, dst[5]) + c
        end)
    end,
}
local memops_h = memops()
local srcb = ffi.new("uint8_t[4]", { 10, 20, 30, 40 })
local dstb = ffi.new("uint8_t[10]")
local srcp = tonumber(ffi.cast("intptr_t", srcb))
local dstp = tonumber(ffi.cast("intptr_t", dstb))
assert(memops_h(dstp, srcp) == 10 + 99 + 10 + 99 + 1)
assert(dstb[0] == 10 and dstb[1] == 99 and dstb[4] == 10 and dstb[5] == 99 and dstb[8] == 7 and dstb[9] == 7)
print("memops_h(...) =", memops_h(dstp, srcp))

local pair_copy_sum = (func "pair_copy_sum") {
    ptr(Pair)"dst",
    ptr(Pair)"src",
    function(dst, src)
        return block(function()
            copy(Pair, dst, src)
            local p = load(Pair, dst)
            return p.a + p.b
        end)
    end,
}
local pair_copy_sum_h = pair_copy_sum()
local pbuf2 = ffi.new("int32_t[2]")
pbuf2[0] = 11; pbuf2[1] = 31
local p2_ptr = tonumber(ffi.cast("intptr_t", pbuf2))
assert(pair_copy_sum_h(p_ptr, p2_ptr) == 42)
assert(pbuf[0] == 11 and pbuf[1] == 31)
print("pair_copy_sum_h(...) =", pair_copy_sum_h(p_ptr, p2_ptr))

local pair_sum_byval = (func "pair_sum_byval") {
    Pair"p",
    function(p)
        return p.a + p.b
    end,
}
local pair_sum_byval_h = pair_sum_byval()
assert(pair_sum_byval_h(p2_ptr) == 42)
print("pair_sum_byval_h(...) =", pair_sum_byval_h(p2_ptr))

local pair_local_sum = (func "pair_local_sum") {
    function()
        return block(function()
            local p = let(Pair { a = i32(40), b = i32(2) })
            return p.a + p.b
        end)
    end,
}
local pair_local_sum_h = pair_local_sum()
assert(pair_local_sum_h() == 42)
print("pair_local_sum_h() =", pair_local_sum_h())

local pair_var_sum = (func "pair_var_sum") {
    function()
        return block(function()
            local p = var(Pair { a = i32(1), b = i32(2) })
            p:set(Pair { a = i32(40), b = i32(2) })
            return p.a + p.b
        end)
    end,
}
local pair_var_sum_h = pair_var_sum()
assert(pair_var_sum_h() == 42)
print("pair_var_sum_h() =", pair_var_sum_h())

local use_pair_sum_byval = (func "use_pair_sum_byval") {
    function()
        return invoke(pair_sum_byval, Pair { a = i32(40), b = i32(2) })
    end,
}
local use_pair_sum_byval_h = use_pair_sum_byval()
assert(use_pair_sum_byval_h() == 42)
print("use_pair_sum_byval_h() =", use_pair_sum_byval_h())

local pair_init_sum = (func "pair_init_sum") {
    ptr(Pair)"dst",
    function(dst)
        return block(function()
            store(Pair, dst, Pair { a = i32(40), b = i32(2) })
            local p = load(Pair, dst)
            return p.a + p.b
        end)
    end,
}
local pair_init_sum_h = pair_init_sum()
assert(pair_init_sum_h(p_ptr) == 42)
assert(pbuf[0] == 40 and pbuf[1] == 2)
print("pair_init_sum_h(...) =", pair_init_sum_h(p_ptr))

local tagged_store = (func "tagged_store") {
    ptr(TaggedValue)"dst",
    function(dst)
        return block(function()
            store(TaggedValue, dst, TaggedValue {
                tag = TaggedValue.Pair,
                payload = TaggedValue.Payload {
                    Pair = { a = i16(20), b = i16(22) },
                },
            })
            local tv = load(TaggedValue, dst)
            return zext(i32, tv.tag) + sext(i32, tv.payload.Pair.a) + sext(i32, tv.payload.Pair.b)
        end)
    end,
}
local tagged_store_h = tagged_store()
local tvbuf = ffi.new("uint8_t[?]", TaggedValue.size)
local tvptr = tonumber(ffi.cast("intptr_t", tvbuf))
assert(tagged_store_h(tvptr) == TaggedValue.Pair.node.value + 20 + 22)
print("tagged_store_h(...) =", tagged_store_h(tvptr))

print("\nall tests passed")
