package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local T = pvm.context():Define [[
module Bench {
    Coord = (number x, number y) unique
    Ring = (Bench.Coord* coords) unique
    Label = (string text) unique
    LabelList = (string* items) unique
    WrapCoord = (Bench.Coord coord) unique
    Geometry = Point(number x, number y) unique
             | LineString(Bench.Coord* coords) unique
             | Polygon(Bench.Ring* rings) unique
             | Empty
}
]]

local Coord = T.Bench.Coord
local Ring = T.Bench.Ring
local Point = T.Bench.Point
local LineString = T.Bench.LineString
local Polygon = T.Bench.Polygon
local Label = T.Bench.Label
local LabelList = T.Bench.LabelList
local WrapCoord = T.Bench.WrapCoord

local p1 = Point(1, 2)
local p2 = Point(1, 2)
local label = Label("hello")
local label2 = Label("hello")
local labels = LabelList({ "a", "b", "c" })
local labels2 = LabelList({ "a", "b", "c" })
local wrapped = WrapCoord(Coord(9, 10))
local wrapped2 = WrapCoord(Coord(9, 10))

assert(p1 == p2)
assert(pvm.classof(p1) == Point)
assert(Point.__storage == "gc_object")

local p3 = pvm.with(p1, { x = 5 })
assert(p3 ~= p1)
assert(p3.x == 5)
assert(p3.y == 2)
assert(label == label2)
assert(label.text == "hello")
assert(labels == labels2)
assert(wrapped == wrapped2)
assert(wrapped.coord.x == 9 and wrapped.coord.y == 10)

local line = LineString({ Coord(1, 2), Coord(3, 4), Coord(5, 6) })
local coords, start, len, present = line:__raw_coords()
assert(present == true)
assert(start == 1)
assert(len == 3)
assert(coords[1].x == 1)
assert(coords[3].y == 6)

local x, y = p1:__raw()
assert(x == 1 and y == 2)

local poly = Polygon({ Ring({ Coord(0, 0), Coord(1, 0), Coord(1, 1), Coord(0, 0) }) })
local rings, rstart, rlen, rpresent = poly:__raw_rings()
assert(rpresent == true)
assert(rstart == 1)
assert(rlen == 1)
local ring_coords, cstart, clen = rings[1]:__raw_coords()
assert(cstart == 1)
assert(clen == 4)
assert(ring_coords[2].x == 1)

assert(T.Bench.Empty == T.Bench.Empty)
assert(pvm.classof(T.Bench.Empty) ~= false)

local B = T:Builders()
local bpt = B.Bench.Point { x = 7, y = 8 }
assert(bpt == Point(7, 8))

print("asdl_context_wj retired: GC ASDL backend ok")
