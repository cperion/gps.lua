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
assert(array_len_mod.Width.Four.node.value == 4)
assert(array_len_mod.XS ~= nil and array_len_mod.XS._layout.count == 4)
local compiled_array_len = array_len_mod()
assert(compiled_array_len.array_len_ok() == 42)
print('array_len_mod.Width.Four =', array_len_mod.Width.Four.node.value)
print('array_len_mod.XS count =', array_len_mod.XS._layout.count)
print('compiled_array_len.array_len_ok() =', compiled_array_len.array_len_ok())

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

local t = ml.type[[func(&u8, usize) -> void]]
assert(t ~= nil)
print('type[[...]] =', t.name)

print('\nsource frontend demo ok')
