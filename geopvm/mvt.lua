-- geopvm/mvt.lua
--
-- Placeholder MVT feature encoder phase.
--
-- v1 still does not emit protobuf MVT bytes, but it now produces deterministic
-- tile-local debug records with quantized geometry coordinates. This makes the
-- tile pipeline reflect clipping + tile-space encoding more honestly.

local tconcat = table.concat

local geoarrow = require("geopvm.geoarrow")
local schema = require("geopvm.asdl")

local M = {}
local T = schema.T
M.T = T

local function encode_stub(entry, geomcols, layer, extent, bbox)
    local qtext, kind = geoarrow.encode_geometry(geomcols, entry.geom_index, bbox, extent)
    if qtext == nil then return nil end
    local feature = entry.feature
    local _, _, props_len = feature.props:__raw_entries()
    local parts = {
        "feature{layer=", layer,
        ",id=", feature.id,
        ",geom=", kind,
        ",extent=", tostring(extent),
        ",props=", tostring(props_len),
        ",q=", qtext,
        "}\n",
    }
    return tconcat(parts)
end

function M.run(entry, geomcols, layer_name, extent, bbox)
    return encode_stub(entry, geomcols, layer_name, extent or 4096, bbox)
end

return M
