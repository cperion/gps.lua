package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")
local wm = require("watjit.wasmtime")
local aj = require("asdljit")

local schema = aj.compile([[
module Bench {
    Point = (i32 x, i32 y) unique
    Shape = Span(i32 a, i32 b) unique
          | Rect(i32 x, i32 y, i32 w, i32 h) unique
}
]], {
    type_map = {
        i32 = wj.i32,
    },
})

assert(schema.Bench ~= nil)
assert(schema.Bench.Point ~= nil)
assert(schema.Bench.Shape ~= nil)
assert(schema.Bench.Span ~= nil)
assert(schema.Bench.Rect ~= nil)

local Point = schema.Bench.Point
local Rect = schema.Bench.Rect

assert(Point.kind == "product")
assert(Point.unique == true)
assert(Rect.kind == "constructor")
assert(Rect.parent_sum == "Bench.Shape")

local PointLayout = Point:layout()
assert(PointLayout.size == 8)
assert(PointLayout.offsets.x.offset == 0)
assert(PointLayout.offsets.y.offset == 4)

local point_hash = Point:hash_quote()
local point_eq = Point:eq_quote()
local rect_hash = Rect:hash_quote()

local point_hash_fn = wj.fn {
    name = "point_hash_fn",
    params = Point:param_list(schema.type_map),
    ret = wj.u32,
    body = function(x, y)
        return point_hash(x, y)
    end,
}

local point_eq_fn = wj.fn {
    name = "point_eq_fn",
    params = Point:eq_param_list(schema.type_map),
    ret = wj.i32,
    body = function(lx, ly, rx, ry)
        return point_eq(lx, ly, rx, ry)
    end,
}

local rect_hash_fn = wj.fn {
    name = "rect_hash_fn",
    params = Rect:param_list(schema.type_map),
    ret = wj.u32,
    body = function(x, y, w, h)
        return rect_hash(x, y, w, h)
    end,
}

local mod = wj.module({ point_hash_fn, point_eq_fn, rect_hash_fn })
local wat = mod:wat()
assert(not wat:find("(call $asdljit_mix_u32", 1, true), wat)

local inst = mod:compile(wm.engine())
local hash_point = inst:fn("point_hash_fn")
local eq_point = inst:fn("point_eq_fn")
local hash_rect = inst:fn("rect_hash_fn")

local h1 = hash_point(10, 20)
local h2 = hash_point(10, 20)
local h3 = hash_point(10, 21)
assert(h1 == h2)
assert(h1 ~= h3)

assert(eq_point(1, 2, 1, 2) == 1)
assert(eq_point(1, 2, 1, 3) == 0)
assert(hash_rect(1, 2, 3, 4) ~= hash_rect(1, 2, 3, 5))

print("asdljit: codegen scaffold ok")
