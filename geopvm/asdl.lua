-- geopvm/asdl.lua
--
-- GeoPVM v1 schema.
--
-- Notes:
--   - bounded structural/identity nodes are `unique`
--   - request-space nodes are intentionally NOT unique

local pvm = require("pvm")

local M = {}
local T = pvm.context({
    handle_storage = {
        ["Geo.Coord"] = true,
        ["Geo.Ring"] = true,
        ["Geo.BBox"] = true,
        ["Geo.Point"] = true,
        ["Geo.LineString"] = true,
        ["Geo.Polygon"] = true,
    },
})
M.T = T

T:Define [[
module Geo {
    Coord = (number x, number y) unique
    Ring = (Geo.Coord* coords) unique
    BBox = (number minx, number miny,
            number maxx, number maxy) unique

    Geometry = Point(number x, number y) unique
             | LineString(Geo.Coord* coords) unique
             | Polygon(Geo.Ring* rings) unique

    PropValue = PStr(string v) unique
              | PNum(number v) unique
              | PBool(boolean v) unique
              | PNull unique

    Prop = (string key, Geo.PropValue value) unique
    Props = (Geo.Prop* entries) unique

    Feature = (string id, Geo.Geometry geom, Geo.Props props) unique
    LayerMeta = (string name, number srid) unique
    LayerRef = (Geo.LayerMeta meta, number rev) unique
}

module Query {
    TileReq = (string layer, number z, number x, number y, string fmt)
    BBoxReq = (string layer, Geo.BBox bbox)
    ClipReq = (Geo.Feature feature, Geo.BBox bbox)
    EncodeMVTReq = (Geo.Feature feature, string layer, number extent, Geo.BBox bbox)
}
]]

M.EMPTY_PROPS = T.Geo.Props({})

function M.prop_string(key, value)
    return T.Geo.Prop(key, T.Geo.PStr(value))
end

function M.prop_number(key, value)
    return T.Geo.Prop(key, T.Geo.PNum(value))
end

function M.prop_boolean(key, value)
    return T.Geo.Prop(key, T.Geo.PBool(value))
end

function M.props(entries)
    return T.Geo.Props(entries or {})
end

return M
