package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local iwj = require("iwatjit")
local wj = require("watjit")
local S = require("watjit.stream")

local T = pvm.context():Define [[
module Bench {
    Coord = (number x, number y) unique
    Ring = (Bench.Coord* coords) unique
    Geometry = Point(number x, number y) unique
             | LineString(Bench.Coord* coords) unique
             | Polygon(Bench.Ring* rings) unique
}
]]

local Point = T.Bench.Point
local Coord = T.Bench.Coord
local LineString = T.Bench.LineString
local Ring = T.Bench.Ring
local Polygon = T.Bench.Polygon

local rt = iwj.runtime { result_capacity = 1024 * 1024 }
local geom = iwj.phase(rt, "geom", {
    [T.Bench.Point] = function(self)
        local x, y = self:__raw()
        return S.once(wj.i32, x + y)
    end,
    [T.Bench.LineString] = function(self)
        local coords, start, len = self:__raw_coords()
        local fx, fy = coords[start]:__raw()
        local lx, ly = coords[start + len - 1]:__raw()
        return S.once(wj.i32, fx + fy + lx + ly)
    end,
    [T.Bench.Polygon] = function(self)
        local rings, rstart = self:__raw_rings()
        local _, _, outer_len = rings[rstart]:__raw_coords()
        return S.once(wj.i32, outer_len)
    end,
})

local p = Point(3, 4)
local l = LineString({ Coord(1, 2), Coord(3, 4), Coord(5, 6) })
local g = Polygon({ Ring({ Coord(0, 0), Coord(1, 0), Coord(1, 1), Coord(0, 0) }) })

assert(iwj.sum(geom(p)) == 7)
assert(iwj.sum(geom(l)) == 14)
assert(iwj.sum(geom(g)) == 4)

assert(geom(p).kind == "cached_seq")
assert(geom(l).kind == "cached_seq")
assert(geom(g).kind == "cached_seq")

local s = iwj.phase_stats(geom)
assert(s.hits >= 3)
assert(s.memory >= 3 * wj.i32.size)

print("iwatjit: ASDL pvm-project port path ok")
print(iwj.report_string(rt))
