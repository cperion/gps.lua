-- geopvm/store.lua
--
-- v1 in-memory store + edit overlay scaffold.
--
-- The final read path should delegate static queries to a packed FlatGeobuf
-- index walker and decode lazily by offset. For now, layers are memory-backed.

local schema = require("geopvm.asdl")
local geoarrow = require("geopvm.geoarrow")
local index = require("geopvm.index")
local lru = require("geopvm.lru")
local util = require("geopvm.util")

local M = {}
local T = schema.T
M.T = T

local function layer_error(name)
    error("unknown layer: " .. tostring(name), 2)
end

local function build_entry(feature)
    return {
        id = feature.id,
        feature = feature,
        bbox = util.geom_bbox(feature.geom),
        geom_index = false,
    }
end

local function rebuild_index(layer)
    layer.index = index.build(layer.entries)
    layer.geomcols = geoarrow.build(layer.entries)
    return layer.index
end

local function bump_rev(layer)
    layer.ref = T.Geo.LayerRef(layer.meta, layer.ref.rev + 1)
    return layer.ref
end

function M.new(opts)
    opts = opts or {}
    return {
        opts = opts,
        layers = {},
        tile_cache = lru.new(opts.tile_cache_size or 1024),
        decode_cache = lru.new(opts.decode_cache_size or 16384),
    }
end

function M.add_memory_layer(store, name, srid, features)
    local meta = T.Geo.LayerMeta(name, srid or 3857)
    local layer = {
        meta = meta,
        ref = T.Geo.LayerRef(meta, 1),
        entries = {},
        by_id = {},
    }

    for i = 1, #features do
        local entry = build_entry(features[i])
        layer.entries[#layer.entries + 1] = entry
        layer.by_id[entry.id] = entry
    end

    rebuild_index(layer)
    store.layers[name] = layer
    return layer
end

function M.get_layer(store, name)
    return store.layers[name] or layer_error(name)
end

function M.query_bbox_entries(store, layer_name, bbox)
    local layer = M.get_layer(store, layer_name)
    local out = {}
    local entries = layer.index and index.query(layer.index, bbox) or layer.entries
    for i = 1, #entries do
        local entry = entries[i]
        if util.bbox_intersects(entry.bbox, bbox) then
            out[#out + 1] = entry
        end
    end
    return out
end

function M.query_bbox(store, layer_name, bbox)
    local entries = M.query_bbox_entries(store, layer_name, bbox)
    local out = {}
    for i = 1, #entries do
        out[i] = entries[i].feature
    end
    return out
end

function M.put_feature(store, layer_name, feature)
    local layer = M.get_layer(store, layer_name)
    local entry = build_entry(feature)
    local old = layer.by_id[entry.id]

    if old then
        for i = 1, #layer.entries do
            if layer.entries[i].id == entry.id then
                layer.entries[i] = entry
                break
            end
        end
    else
        layer.entries[#layer.entries + 1] = entry
    end

    layer.by_id[entry.id] = entry
    rebuild_index(layer)
    return bump_rev(layer)
end

function M.delete_feature(store, layer_name, feature_id)
    local layer = M.get_layer(store, layer_name)
    if not layer.by_id[feature_id] then
        return false, layer.ref
    end

    layer.by_id[feature_id] = nil
    local src = layer.entries
    local dst = {}
    for i = 1, #src do
        if src[i].id ~= feature_id then
            dst[#dst + 1] = src[i]
        end
    end
    layer.entries = dst
    rebuild_index(layer)
    return true, bump_rev(layer)
end

return M
