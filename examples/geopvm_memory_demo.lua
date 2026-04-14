package.path = "./?.lua;./?/init.lua;" .. package.path

local geopvm = require("geopvm")

local T = geopvm.T
local store = geopvm.store.new({ tile_cache_size = 16, decode_cache_size = 16 })
local EMPTY = geopvm.schema.EMPTY_PROPS

geopvm.store.add_memory_layer(store, "demo", 3857, {
    T.Geo.Feature("origin", T.Geo.Point(0, 0), EMPTY),
    T.Geo.Feature("east", T.Geo.Point(1000, 0), EMPTY),
})

local bytes = geopvm.tile.build_mvt(store, "demo", 0, 0, 0)
print(bytes)
local report = require("pvm").report_string(geopvm.tile.phases)
print(report ~= "" and report or "(no inner pvm phases in tile path)")
