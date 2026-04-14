-- geopvm/init.lua
--
-- Public facade for the GeoPVM v1 skeleton.

local schema = require("geopvm.asdl")
local store = require("geopvm.store")
local geoarrow = require("geopvm.geoarrow")
local index = require("geopvm.index")
local query = require("geopvm.query")
local clip = require("geopvm.clip")
local mvt = require("geopvm.mvt")
local tile = require("geopvm.tile")
local geojson = require("geopvm.geojson")
local http = require("geopvm.http")
local util = require("geopvm.util")

return {
    T = schema.T,
    schema = schema,
    store = store,
    geoarrow = geoarrow,
    index = index,
    query = query,
    clip = clip,
    mvt = mvt,
    tile = tile,
    geojson = geojson,
    http = http,
    util = util,
}
