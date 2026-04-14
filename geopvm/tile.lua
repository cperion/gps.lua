-- geopvm/tile.lua
--
-- Tile pipeline scaffold:
--   tile bbox -> indexed query -> direct clip kernel -> direct MVT encoder -> bytes

local tconcat = table.concat

local mvt = require("geopvm.mvt")
local store = require("geopvm.store")
local util = require("geopvm.util")

local M = {}

local function tile_cache_key(layer, fmt, z, x, y, style_rev)
    return string.format(
        "%s@%d|%s|%d/%d/%d|s%d",
        layer.meta.name,
        layer.ref.rev,
        fmt,
        z, x, y,
        style_rev or 0
    )
end

function M.build_mvt(store_state, layer_name, z, x, y, opts)
    opts = opts or {}

    local layer = store.get_layer(store_state, layer_name)
    local key = tile_cache_key(layer, "mvt", z, x, y, opts.style_rev)
    local cached = store_state.tile_cache:get(key)
    if cached ~= nil then
        return cached
    end

    local bbox = util.tile_bbox_3857(z, x, y)
    local extent = opts.extent or 4096

    local entries = store.query_bbox_entries(store_state, layer_name, bbox)
    local geomcols = layer.geomcols
    local chunks = { "MVTSTUB\n" }

    for i = 1, #entries do
        local bytes = mvt.run(entries[i], geomcols, layer.meta.name, extent, bbox)
        if bytes ~= nil then
            chunks[#chunks + 1] = bytes
        end
    end

    local bytes = tconcat(chunks)
    store_state.tile_cache:set(key, bytes)
    return bytes
end

M.cache_key = tile_cache_key
M.phases = {}

return M
