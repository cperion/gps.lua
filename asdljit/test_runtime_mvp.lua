package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")
local aj = require("asdljit")

local schema = aj.compile([[
module Bench {
    Point = (i32 x, i32 y) unique
    Shape = Rect(i32 x, i32 y, i32 w, i32 h) unique
}
]], {
    type_map = {
        i32 = wj.i32,
    },
})

local Point = schema.Bench.Point
local Rect = schema.Bench.Rect

local points = Point:runtime { capacity = 32 }
local rects = Rect:runtime { capacity = 32 }

local p1 = points:new(10, 20)
local p2 = points:new(10, 20)
local p3 = points:new(10, 21)

assert(p1 == 1)
assert(p2 == p1)
assert(p3 == 2)
assert(points:len() == 2)

local x, y = points:raw(p1)
assert(x == 10)
assert(y == 20)
local rec = points:get(p3)
assert(rec.x == 10)
assert(rec.y == 21)

local r1 = rects:new(1, 2, 3, 4)
local r2 = rects:new(1, 2, 3, 4)
local r3 = rects:new(1, 2, 3, 5)
assert(r1 == r2)
assert(r3 ~= r1)
assert(rects:len() == 2)

local wat = points:wat()
assert(not wat:find("(call $asdljit_mix_u32", 1, true), wat)
assert(wat:find("_hash_fn", 1, true))
assert(wat:find("_eq_slot_fn", 1, true))
assert(wat:find("_store_fn", 1, true))

print("asdljit: runtime MVP ok")
