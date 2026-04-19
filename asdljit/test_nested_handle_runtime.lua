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
    name = "Geo_Point_List",
})

local p1 = points:new(1, 2)
local p2 = points:new(3, 4)
local p3 = points:new(1, 2)
assert(p1 == p3)
assert(points:len() == 2)

local edges = Edge:runtime {
    capacity = 64,
    field_runtimes = {
        a = points,
        b = points,
    },
}

local e1 = edges:new({ x = 1, y = 2 }, { x = 3, y = 4 })
local e2 = edges:new({ x = 1, y = 2 }, { x = 3, y = 4 })
local e3 = edges:new({ x = 3, y = 4 }, { x = 1, y = 2 })
assert(e1 == e2)
assert(e3 ~= e1)
assert(edges:len() == 2)

local er = edges:get(e1)
assert(er.a.x == 1)
assert(er.a.y == 2)
assert(er.b.x == 3)
assert(er.b.y == 4)

local polylines = Polyline:runtime {
    capacity = 64,
    list_runtimes = {
        points = point_list,
    },
}

local poly1 = polylines:new({ { x = 1, y = 2 }, { x = 3, y = 4 } })
local poly2 = polylines:new({ { x = 1, y = 2 }, { x = 3, y = 4 } })
local poly3 = polylines:new({ { x = 1, y = 2 }, { x = 5, y = 6 } })
assert(poly1 == poly2)
assert(poly3 ~= poly1)
assert(polylines:len() == 2)

local pr = polylines:get(poly1)
assert(#pr.points == 2)
assert(pr.points[1].x == 1)
assert(pr.points[1].y == 2)
assert(pr.points[2].x == 3)
assert(pr.points[2].y == 4)

local list_values = point_list:get(point_list:new({ { x = 7, y = 8 }, { x = 9, y = 10 } }))
assert(#list_values == 2)
assert(list_values[1].x == 7)
assert(list_values[2].y == 10)

print("asdljit: nested handle runtime ok")
