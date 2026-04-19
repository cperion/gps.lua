package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")
local aj = require("asdljit")

local schema = aj.compile([[
module Geo {
    Point = (i32 x, i32 y) unique
    Edge = (Geo.Point a, Geo.Point b) unique
    Polyline = (Geo.Point* points) unique
}
]], {
    type_map = {
        i32 = wj.i32,
    },
})

local Point = schema.Geo.Point
local Edge = schema.Geo.Edge
local Polyline = schema.Geo.Polyline

local points = Point:runtime { capacity = 64 }
local point_list = schema:list_runtime("Geo.Point", {
    capacity = 64,
    elem_capacity = 256,
    scratch_capacity = 32,
    elem_runtime = points,
    name = "Geo_Point_List_With",
})

local p1 = points:new(1, 2)
local p2 = points:with(p1, { y = 5 })
local p3 = points:new(1, 5)
assert(p2 == p3)
assert(p2 ~= p1)
local x2, y2 = points:raw(p2)
assert(x2 == 1 and y2 == 5)

local edges = Edge:runtime {
    capacity = 64,
    field_runtimes = {
        a = points,
        b = points,
    },
}

local e1 = edges:new({ x = 1, y = 2 }, { x = 3, y = 4 })
local e2 = edges:with(e1, { a = { x = 1, y = 9 } })
local er = edges:get(e2)
assert(er.a.x == 1 and er.a.y == 9)
assert(er.b.x == 3 and er.b.y == 4)

local polylines = Polyline:runtime {
    capacity = 64,
    list_runtimes = {
        points = point_list,
    },
}

local pl1 = polylines:new({ { x = 1, y = 2 }, { x = 3, y = 4 } })
local pl2 = polylines:with(pl1, {
    points = { { x = 1, y = 2 }, { x = 7, y = 8 } },
})
local pr = polylines:get(pl2)
assert(#pr.points == 2)
assert(pr.points[1].x == 1 and pr.points[1].y == 2)
assert(pr.points[2].x == 7 and pr.points[2].y == 8)

local points_handle = select(1, polylines:raw_handles(pl2))
assert(type(points_handle) == "number")
assert(points_handle >= 1)

print("asdljit: with MVP ok")
