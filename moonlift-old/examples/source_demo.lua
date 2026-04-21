local ml = require('moonlift')
ml.use()
local ffi = require('ffi')

local add = code[[
func add(a: i32, b: i32) -> i32
    return a + b
end
]]
local addh = add()
assert(addh(20, 22) == 42)
print('addh(20,22) =', addh(20, 22))

local math_mod = module[[
func add2(x: i32) -> i32
    return x + 2
end

func use_add2(x: i32) -> i32
    return add2(x) * 2
end
]]
local compiled_math = math_mod()
assert(compiled_math.add2(40) == 42)
assert(compiled_math.use_add2(19) == 42)
print('compiled_math.use_add2(19) =', compiled_math.use_add2(19))

local inferred_mod = module[[
struct Pair2
    a: i32
    b: i32
end

impl Pair2
    func sum(self: &Pair2)
        self.a + self.b
    end
end

func add2_infer(x: i32)
    x + 2
end

func use_add2_infer(x: i32)
    return add2_infer(x) * 2
end

func pair2_sum(p: &Pair2)
    return p:sum()
end
]]
local compiled_inferred = inferred_mod()
local pbuf2 = ffi.new('int32_t[2]')
pbuf2[0] = 20; pbuf2[1] = 22
local pptr2 = tonumber(ffi.cast('intptr_t', pbuf2))
assert(compiled_inferred.add2_infer(40) == 42)
assert(compiled_inferred.use_add2_infer(19) == 42)
assert(compiled_inferred.pair2_sum(pptr2) == 42)
print('compiled_inferred.use_add2_infer(19) =', compiled_inferred.use_add2_infer(19))
print('compiled_inferred.pair2_sum(...) =', compiled_inferred.pair2_sum(pptr2))

local recursive_infer = code[[
func fact(n: i32)
    if n <= 1 then
        return 1
    end
    return n * fact(n - 1)
end
]]
local facth = recursive_infer()
assert(facth(5) == 120)
print('facth(5) =', facth(5))

local splice_infer = code[[
func from_splice()
    @{42}
end
]]
local from_splice_h = splice_infer()
assert(from_splice_h() == 42)
print('from_splice_h() =', from_splice_h())

local type_splice = code[[
func id_spliced(x: @{i32}) -> @{i32}
    return x
end
]]
local id_spliced_h = type_splice()
assert(id_spliced_h(42) == 42)
print('id_spliced_h(42) =', id_spliced_h(42))

local item_splice_mod = module[[
@{"func extra_answer() -> i32\n    return 42\nend"}
]]
local compiled_item_splice = item_splice_mod()
assert(compiled_item_splice.extra_answer() == 42)
print('compiled_item_splice.extra_answer() =', compiled_item_splice.extra_answer())

local hole_bound_expr = expr("?L: i32 + ?R: i32", { L = 20, R = 22 })
assert(hole_bound_expr ~= nil and hole_bound_expr.t == i32)
print('hole_bound_expr.t =', hole_bound_expr.t)

local source_bound_expr = expr[[20 + 22]]
local hole_expr_code = code([[
func from_hole_expr() -> i32
    return ?E: i32
end
]], { E = source_bound_expr })
local from_hole_expr_h = hole_expr_code()
assert(from_hole_expr_h() == 42)
print('from_hole_expr_h() =', from_hole_expr_h())

local hole_mod = module([[
const N = ?N: i32
const XS = [N]i32 { 10, 11, 12, 9 }

func hole_len_ok() -> i32
    return ?RET: i32
end
]], { N = 4, RET = 42 })
assert(hole_mod.__native_source ~= nil)
assert(hole_mod.XS ~= nil and hole_mod.XS._layout.count == 4)
local compiled_hole_mod = hole_mod()
assert(compiled_hole_mod.hole_len_ok() == 42)
print('compiled_hole_mod.hole_len_ok() =', compiled_hole_mod.hole_len_ok())

local array_len_mod = module[[
enum Width : u8
    One = 1
    Two = One + 1
    Four = cast<i32>(Two) * 2
end

const N = if true then cast<i32>(Width.Two) else 0 end
const M = switch Width.Two do
    case 1 then 3
    case 2 then 4
    default then 5
end
const XS = [N + M - 2]i32 { 10, 11, 12, 9 }

func array_len_ok() -> i32
    return 42
end
]]
assert(array_len_mod.__native_source ~= nil)
assert(array_len_mod.Width.Four.node.value == 4)
assert(array_len_mod.XS ~= nil and array_len_mod.XS._layout.count == 4)
local compiled_array_len = array_len_mod()
assert(compiled_array_len.array_len_ok() == 42)
print('array_len_mod.Width.Four =', array_len_mod.Width.Four.node.value)
print('array_len_mod.XS count =', array_len_mod.XS._layout.count)
print('compiled_array_len.array_len_ok() =', compiled_array_len.array_len_ok())

local slice_mod = module[[
slice I32Slice = i32

func sum_slice(s: &I32Slice) -> i32
    var acc: i32 = 0
    var i: usize = 0
    while i < s.len do
        acc = acc + s[i]
        i = i + 1
    end
    return acc
end
]]
assert(slice_mod.__native_source ~= nil)
local compiled_slice = slice_mod()
local sbuf = ffi.new('int32_t[4]')
sbuf[0] = 10; sbuf[1] = 11; sbuf[2] = 12; sbuf[3] = 9
local slice_header = ffi.new('uint64_t[2]')
slice_header[0] = tonumber(ffi.cast('intptr_t', sbuf))
slice_header[1] = 4
local slice_ptr = tonumber(ffi.cast('intptr_t', slice_header))
assert(compiled_slice.sum_slice(slice_ptr) == 42)
print('compiled_slice.sum_slice(...) =', compiled_slice.sum_slice(slice_ptr))

local pair_mod = module[[
struct Pair
    a: i32
    b: i32
end

impl Pair
    func sum(self: &Pair) -> i32
        return self.a + self.b
    end
end

func pair_sum(p: &Pair) -> i32
    return p:sum()
end

func pair_sum_local() -> i32
    let p: Pair = Pair { a = 40, b = 2 }
    return p.a + p.b
end
]]
local compiled_pair = pair_mod()
local pbuf = ffi.new('int32_t[2]')
pbuf[0] = 20; pbuf[1] = 22
local pptr = tonumber(ffi.cast('intptr_t', pbuf))
assert(compiled_pair.pair_sum(pptr) == 42)
assert(compiled_pair.pair_sum_local() == 42)
print('compiled_pair.pair_sum(...) =', compiled_pair.pair_sum(pptr))
print('compiled_pair.pair_sum_local() =', compiled_pair.pair_sum_local())

local triangular = code[[
func triangular(n: i32) -> i32
    var i: i32 = 0
    var acc: i32 = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end
]]
local triangularh = triangular()
assert(triangularh(6) == 21)
print('triangularh(6) =', triangularh(6))

local maybe_answer = code[[
func maybe_answer(flag: bool) -> i32
    if flag then
        return 42
    end
    7
end
]]
local maybeh = maybe_answer()
assert(maybeh(true) == 42)
assert(maybeh(false) == 7)
print('maybeh(true) =', maybeh(true))
print('maybeh(false) =', maybeh(false))

local infer_maybe = code[[
func infer_maybe(flag: bool)
    if flag then
        return 42
    end
    7
end
]]
local infer_maybe_h = infer_maybe()
assert(infer_maybe_h(true) == 42)
assert(infer_maybe_h(false) == 7)
print('infer_maybe_h(true) =', infer_maybe_h(true))
print('infer_maybe_h(false) =', infer_maybe_h(false))

local nested_return = code[[
func nested_return(limit: i32) -> i32
    var i: i32 = 0
    while i < limit do
        var j: i32 = 0
        while j < limit do
            if j == 2 then
                return 42
            end
            j = j + 1
        end
        i = i + 1
    end
    return 0
end
]]
local nestedh = nested_return()
assert(nestedh(6) == 42)
print('nestedh(6) =', nestedh(6))

local stmt_if = code[[
func stmt_if(x: i32) -> i32
    var acc: i32 = 0
    if x > 0 then
        acc = 40
    else
        acc = 10
    end
    return acc + 2
end
]]
local stmt_if_h = stmt_if()
assert(stmt_if_h(1) == 42)
assert(stmt_if_h(-1) == 12)
print('stmt_if_h(1) =', stmt_if_h(1))
print('stmt_if_h(-1) =', stmt_if_h(-1))

local switch_loop = code[[
func switch_loop(limit: i32) -> i32
    var i: i32 = 0
    var acc: i32 = 0
    while i < limit do
        switch i do
        case 0 then
            i = i + 1
            continue
        case 4 then
            break
        default then
            acc = acc + i
        end
        i = i + 1
    end
    return acc
end
]]
local switch_loop_h = switch_loop()
assert(switch_loop_h(10) == 6)
print('switch_loop_h(10) =', switch_loop_h(10))

local canonical_loop_mod = module[[
slice F32Slice = f32

func sum_loop_while(n: usize) -> i32
    return loop i: index = 0, acc: i32 = 0 while i < n
        let xi: i32 = cast<i32>(i) + 1
    next
        acc = acc + xi
        i = i + 1
    end -> acc
end

func sum_loop_over(n: usize) -> i32
    return loop i over range(n), acc: i32 = 0
    next
        acc = acc + cast<i32>(i) + 1
    end -> acc
end

func sum_loop_over_from_one(n: i64) -> i64
    return loop i over range(1, n), acc: i64 = 0
    next
        acc = acc + i
    end -> acc
end

func sum_loop_while_induction_last(n: usize) -> i32
    return loop acc: i32 = 0, i: index = 0 while i < n
        let xi: i32 = cast<i32>(i) + 1
    next
        acc = acc + xi
        i = i + 1
    end -> acc
end

func sum_loop_while_desc() -> i32
    return loop i: i32 = 5, acc: i32 = 0 while i > 0
    next
        acc = acc + i
        i = i - 2
    end -> acc
end

func iter_final() -> i32
    return loop i: i32 = 0 while i < 3
    next
        i = i + 1
    end -> i
end

func no_iter_final() -> i32
    return loop i: i32 = 7 while false
    next
        i = i + 1
    end -> i
end

func sum_desc_slice(s: &F32Slice) -> f32
    return loop i: index = s.len, acc: f32 = 0.0 while i > 0
    next
        acc = acc + s[i - 1]
        i = i - 1
    end -> acc
end

func gain_sum(dst: &F32Slice, src: &F32Slice, gain: f32) -> f32
    return loop i over zip_eq(dst, src), acc: f32 = 0.0
        let y = src[i] * gain
        dst[i] = y
    next
        acc = acc + y
    end -> acc
end
]]
assert(canonical_loop_mod.__native_source ~= nil)
local compiled_loop_mod = canonical_loop_mod()
assert(compiled_loop_mod.sum_loop_while(6) == 21)
assert(compiled_loop_mod.sum_loop_over(6) == 21)
assert(compiled_loop_mod.sum_loop_over_from_one(7) == 21)
assert(compiled_loop_mod.sum_loop_while_induction_last(6) == 21)
assert(compiled_loop_mod.sum_loop_while_desc() == 9)
assert(compiled_loop_mod.iter_final() == 3)
assert(compiled_loop_mod.no_iter_final() == 7)
print('compiled_loop_mod.sum_loop_while(6) =', compiled_loop_mod.sum_loop_while(6))
print('compiled_loop_mod.sum_loop_over(6) =', compiled_loop_mod.sum_loop_over(6))
print('compiled_loop_mod.sum_loop_over_from_one(7) =', compiled_loop_mod.sum_loop_over_from_one(7))
print('compiled_loop_mod.sum_loop_while_induction_last(6) =', compiled_loop_mod.sum_loop_while_induction_last(6))
print('compiled_loop_mod.sum_loop_while_desc() =', compiled_loop_mod.sum_loop_while_desc())
print('compiled_loop_mod.iter_final() =', compiled_loop_mod.iter_final())
print('compiled_loop_mod.no_iter_final() =', compiled_loop_mod.no_iter_final())

local gain_src = ffi.new('float[4]', { 1, 2, 3, 4 })
local gain_dst = ffi.new('float[4]')
local gain_src_hdr = ffi.new('uint64_t[2]')
local gain_dst_hdr = ffi.new('uint64_t[2]')
gain_src_hdr[0] = tonumber(ffi.cast('intptr_t', gain_src))
gain_src_hdr[1] = 4
gain_dst_hdr[0] = tonumber(ffi.cast('intptr_t', gain_dst))
gain_dst_hdr[1] = 4
local gain_src_ptr = tonumber(ffi.cast('intptr_t', gain_src_hdr))
local gain_dst_ptr = tonumber(ffi.cast('intptr_t', gain_dst_hdr))
local gain_total = compiled_loop_mod.gain_sum(gain_dst_ptr, gain_src_ptr, 0.5)
assert(math.abs(gain_total - 5.0) < 1e-6)
local gain_rev_total = compiled_loop_mod.sum_desc_slice(gain_src_ptr)
assert(math.abs(gain_rev_total - 10.0) < 1e-6)
print('compiled_loop_mod.gain_sum(...) =', gain_total)
print('compiled_loop_mod.sum_desc_slice(...) =', gain_rev_total)

local for_continue = code[[
func for_continue(limit: i32) -> i32
    var acc: i32 = 0
    for i = 0, limit - 1 do
        if i == 2 then
            continue
        end
        acc = acc + 1
    end
    return acc
end
]]
local for_continue_h = for_continue()
assert(for_continue_h(5) == 4)
print('for_continue_h(5) =', for_continue_h(5))

local reverse_sum = code[[
func reverse_sum() -> i32
    var acc: i32 = 0
    for i = 5, 1, -2 do
        acc = acc + i
    end
    return acc
end
]]
local reverse_sum_h = reverse_sum()
assert(reverse_sum_h() == 9)
print('reverse_sum_h() =', reverse_sum_h())

local bits_tagged_mod = module[[
union NumberBits
    i: i32
    f: f32
end

impl NumberBits
    func as_i32(self: &NumberBits)
        self.i
    end
end

tagged union TaggedValue : u8
    Pair
        a: i16
        b: i16
    end
end

impl TaggedValue
    func tag_code(self: &TaggedValue)
        cast<i32>(self.tag)
    end
end

func union_i(p: &NumberBits) -> i32
    p:as_i32()
end

func tagged_sum(tv: &TaggedValue) -> i32
    cast<i32>(tv.tag) + cast<i32>(tv.payload.Pair.a) + cast<i32>(tv.payload.Pair.b)
end
]]
assert(bits_tagged_mod.__native_source ~= nil)
local compiled_bits_tagged = bits_tagged_mod()
local nb_buf = ffi.new('int32_t[1]')
nb_buf[0] = 42
local nb_ptr = tonumber(ffi.cast('intptr_t', nb_buf))
assert(compiled_bits_tagged.union_i(nb_ptr) == 42)
local tv_buf = ffi.new('uint8_t[?]', bits_tagged_mod.TaggedValue.size)
local tv_ptr = tonumber(ffi.cast('intptr_t', tv_buf))
local tv_bytes = ffi.cast('uint8_t*', tv_buf)
tv_bytes[0] = bits_tagged_mod.TaggedValue.Pair.node.value
local tv_payload = ffi.cast('int16_t*', tv_bytes + bits_tagged_mod.TaggedValue.payload.offset)
tv_payload[0] = 20
tv_payload[1] = 22
assert(compiled_bits_tagged.tagged_sum(tv_ptr) == bits_tagged_mod.TaggedValue.Pair.node.value + 20 + 22)
print('compiled_bits_tagged.union_i(...) =', compiled_bits_tagged.union_i(nb_ptr))
print('compiled_bits_tagged.tagged_sum(...) =', compiled_bits_tagged.tagged_sum(tv_ptr))

ffi.cdef[[ int abs(int x); ]]
local abs_mod = module[[
@abi("C")
extern func abs(x: i32) -> i32

func use_abs(x: i32) -> i32
    return abs(x)
end
]]
local compiled_abs = abs_mod()
assert(compiled_abs.use_abs(-42) == 42)
print('compiled_abs.use_abs(-42) =', compiled_abs.use_abs(-42))

local e = expr[[if true then 42 else 0 end]]
assert(e ~= nil and e.t == i32)
print('expr[[...]].t =', e.t.name)

local loop_e = expr[[loop i over range(4), acc: i32 = 0
next
    acc = acc + cast<i32>(i)
end -> acc]]
assert(loop_e ~= nil and loop_e.t == i32)
print('loop expr[[...]].t =', loop_e.t.name)

local loop_while_e = expr[[loop i: index = 0, acc: i32 = 0 while i < 4
next
    acc = acc + cast<i32>(i)
    i = i + 1
end -> acc]]
assert(loop_while_e ~= nil and loop_while_e.t == i32)
print('loop while expr[[...]].t =', loop_while_e.t.name)

local t = ml.type[[func(&u8, usize) -> void]]
assert(t ~= nil)
print('type[[...]] =', t.name)

local add_hole_q = ml.quote.expr[[
?lhs: i32 + ?rhs: i32
]]
local quoted_answer = (func "quoted_answer") {
    function()
        return add_hole_q:bind {
            lhs = expr[[20]],
            rhs = expr[[22]],
        }()
    end,
}
local quoted_answer_h = quoted_answer()
assert(quoted_answer_h() == 42)
print('quoted_answer_h() =', quoted_answer_h())

local block_q = ml.quote.block[[
do
    let x: i32 = 20
    x + ?tail: i32
end
]]
local quoted_block = (func "quoted_block") {
    function()
        return block_q:bind { tail = 22 }()
    end,
}
local quoted_block_h = quoted_block()
assert(quoted_block_h() == 42)
print('quoted_block_h() =', quoted_block_h())

local addk_q = ml.quote.func[[
func (x: i32) -> i32
    return x + ?k: i32
end
]]
local quoted_func = (func "quoted_func") {
    i32"x",
    addk_q:bind { k = expr[[2]] },
}
local quoted_func_h = quoted_func()
assert(quoted_func_h(40) == 42)
print('quoted_func_h(40) =', quoted_func_h(40))

local array_t_q = ml.quote.type[[[?N: i32]i32]]
local free_type_holes = array_t_q:free_holes()
assert(free_type_holes.N == i32)
local hole_names = array_t_q:query {
    expr = function(node)
        if node.tag == 'hole' then return node.name end
    end,
}
assert(#hole_names == 1 and hole_names[1] == 'N')
local rewritten_array_t = array_t_q:rewrite {
    expr = function(node)
        if node.tag == 'hole' and node.name == 'N' then
            return { tag = 'number', raw = '4', kind = 'int' }
        end
    end,
}()
assert(rewritten_array_t ~= nil and rewritten_array_t.count == 4 and rewritten_array_t.elem == i32)
local array_t = array_t_q:bind { N = 4 }()
assert(array_t ~= nil and array_t.count == 4 and array_t.elem == i32)
print('array_t.name =', array_t.name)

local quoted_mod_q = ml.quote.module[[
func quoted_module_answer() -> i32
    return ?base: i32 + ?delta: i32
end
]]
local free_mod_holes = quoted_mod_q:free_holes()
assert(free_mod_holes.base == i32 and free_mod_holes.delta == i32)
local item_tags = quoted_mod_q:query {
    item = function(node)
        return node.tag
    end,
}
assert(#item_tags == 1 and item_tags[1] == 'func')
local rewritten_mod_q = quoted_mod_q:rewrite {
    expr = function(node)
        if node.tag == 'hole' and node.name == 'base' then
            return { tag = 'number', raw = '40', kind = 'int' }
        elseif node.tag == 'hole' and node.name == 'delta' then
            return { tag = 'number', raw = '2', kind = 'int' }
        end
    end,
}
local compiled_rewritten_mod = rewritten_mod_q()()
assert(compiled_rewritten_mod.quoted_module_answer() == 42)
local quoted_mod = quoted_mod_q:bind { base = 40, delta = 2 }()
local compiled_quoted_mod = quoted_mod()
assert(compiled_quoted_mod.quoted_module_answer() == 42)
print('compiled_quoted_mod.quoted_module_answer() =', compiled_quoted_mod.quoted_module_answer())

local expr_splice_q = ml.quote.expr[[?lhs: i32 + ?rhs: i32]]:bind {
    lhs = expr[[20]],
    rhs = expr[[22]],
}
local spliced_expr_fn = code([[
func from_quote_expr() -> i32
    return @{expr_splice_q}
end
]], { expr_splice_q = expr_splice_q })
assert(spliced_expr_fn()() == 42)
print('spliced_expr_fn() =', spliced_expr_fn()())

local type_splice_q = ml.quote.type[[[?N: i32]i32]]:bind { N = 4 }
local spliced_type = ml.type("@{type_splice_q}", { type_splice_q = type_splice_q })
assert(spliced_type ~= nil and spliced_type.count == 4 and spliced_type.elem == i32)
print('spliced_type.name =', spliced_type.name)

local rewritten_type_splice_q = ml.quote.type[[[?N: i32]i32]]:rewrite {
    expr = function(node)
        if node.tag == 'hole' and node.name == 'N' then
            return { tag = 'number', raw = '4', kind = 'int' }
        end
    end,
}
local rewritten_spliced_type = ml.type("@{rewritten_type_splice_q}", { rewritten_type_splice_q = rewritten_type_splice_q })
assert(rewritten_spliced_type ~= nil and rewritten_spliced_type.count == 4 and rewritten_spliced_type.elem == i32)
print('rewritten_spliced_type.name =', rewritten_spliced_type.name)

local module_splice_q = ml.quote.module[[
func extra_answer() -> i32
    return 42
end
]]
local spliced_mod = module([[
@{module_splice_q}
]], { module_splice_q = module_splice_q })
assert(spliced_mod().extra_answer() == 42)
print('spliced_mod.extra_answer() =', spliced_mod().extra_answer())

local rewritten_module_splice_q = ml.quote.module[[
func rewritten_extra() -> i32
    return ?x: i32
end
]]:rewrite {
    expr = function(node)
        if node.tag == 'hole' and node.name == 'x' then
            return { tag = 'number', raw = '42', kind = 'int' }
        end
    end,
}
local rewritten_spliced_mod = module([[
@{rewritten_module_splice_q}
]], { rewritten_module_splice_q = rewritten_module_splice_q })
assert(rewritten_spliced_mod().rewritten_extra() == 42)
print('rewritten_spliced_mod.rewritten_extra() =', rewritten_spliced_mod().rewritten_extra())

print('\nsource frontend demo ok')
