package.path = "./?.lua;./?/init.lua;" .. package.path

local geopvm = require("geopvm")

local T = geopvm.T
local EMPTY = geopvm.schema.EMPTY_PROPS

local bbox = T.Geo.BBox(0, 0, 10, 10)

local function dump(label, feature)
    if not feature then
        print(label, "nil")
        return
    end
    print(label)
    print(geopvm.geojson.feature(feature))
end

local point = T.Geo.Feature("p", T.Geo.Point(5, 5), EMPTY)
local line = T.Geo.Feature("l", T.Geo.LineString({
    T.Geo.Coord(-5, 5),
    T.Geo.Coord(5, 5),
    T.Geo.Coord(15, 5),
}), EMPTY)
local poly = T.Geo.Feature("g", T.Geo.Polygon({
    T.Geo.Ring({
        T.Geo.Coord(-5, -5),
        T.Geo.Coord(15, -5),
        T.Geo.Coord(15, 15),
        T.Geo.Coord(-5, 15),
        T.Geo.Coord(-5, -5),
    })
}), EMPTY)

local out = geopvm.clip.run(point, bbox)
dump("point", out)

out = geopvm.clip.run(line, bbox)
dump("line", out)

out = geopvm.clip.run(poly, bbox)
dump("polygon", out)
