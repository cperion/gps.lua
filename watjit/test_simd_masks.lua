package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local S = wj.simd

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

local select_i32 = wj.fn {
    name = "select_i32",
    params = { wj.i32 "x_base", wj.i32 "y_base", wj.i32 "out_base" },
    body = function(x_base, y_base, out_base)
        local x = wj.view(wj.i32, x_base, "x")
        local y = wj.view(wj.i32, y_base, "y")
        local out = wj.view(wj.i32, out_base, "out")
        local vx = S.i32x4.load(x, 0)
        local vy = S.i32x4.load(y, 0)
        local mask = vx:lt(vy)
        S.i32x4.store(out, 0, S.i32x4.select(mask, vx, vy))
    end,
}

local shuffle_i32 = wj.fn {
    name = "shuffle_i32",
    params = { wj.i32 "a_base", wj.i32 "b_base", wj.i32 "out_base" },
    body = function(a_base, b_base, out_base)
        local a = wj.view(wj.i32, a_base, "a")
        local b = wj.view(wj.i32, b_base, "b")
        local out = wj.view(wj.i32, out_base, "out")
        local va = S.i32x4.load(a, 0)
        local vb = S.i32x4.load(b, 0)
        local vs = S.i32x4.shuffle(va, vb, { 0, 5, 2, 7 })
        S.i32x4.store(out, 0, vs)
    end,
}

local select_f32_sum = wj.fn {
    name = "select_f32_sum",
    params = { wj.i32 "a_base", wj.i32 "b_base" },
    ret = wj.f32,
    body = function(a_base, b_base)
        local a = wj.view(wj.f32, a_base, "a")
        local b = wj.view(wj.f32, b_base, "b")
        local va = S.f32x4.load(a, 0)
        local vb = S.f32x4.load(b, 0)
        local mask = va:gt(vb)
        return S.f32x4.select(mask, va, vb):sum()
    end,
}

local mod = wj.module({ select_i32, shuffle_i32, select_f32_sum })
local wat = mod:wat()
has(wat, '(i32x4.lt_s')
has(wat, '(v128.bitselect')
has(wat, '(i8x16.shuffle')
has(wat, '(f32x4.gt')

local inst = mod:compile(wm.engine())
local mem_i32 = ffi.cast("int32_t*", select(1, inst:memory("memory")))
local mem_f32 = ffi.cast("float*", select(1, inst:memory("memory")))

mem_i32[0] = 1
mem_i32[1] = 5
mem_i32[2] = 3
mem_i32[3] = 8
mem_i32[4] = 2
mem_i32[5] = 4
mem_i32[6] = 3
mem_i32[7] = 9
inst:fn("select_i32")(0, 16, 32)
assert(mem_i32[8] == 1)
assert(mem_i32[9] == 4)
assert(mem_i32[10] == 3)
assert(mem_i32[11] == 8)

mem_i32[0] = 1
mem_i32[1] = 2
mem_i32[2] = 3
mem_i32[3] = 4
mem_i32[4] = 10
mem_i32[5] = 20
mem_i32[6] = 30
mem_i32[7] = 40
inst:fn("shuffle_i32")(0, 16, 32)
assert(mem_i32[8] == 1)
assert(mem_i32[9] == 20)
assert(mem_i32[10] == 3)
assert(mem_i32[11] == 40)

mem_f32[16] = 1.5
mem_f32[17] = 8.0
mem_f32[18] = 3.0
mem_f32[19] = 0.0
mem_f32[20] = 2.0
mem_f32[21] = 4.0
mem_f32[22] = 1.0
mem_f32[23] = 9.0
local sum = inst:fn("select_f32_sum")(64, 80)
assert(math.abs(sum - 22.0) < 1e-5)

print("watjit: simd masks/select/shuffle ok")
