-- geopvm/query.lua
--
-- Query entrypoints. Static packed-index walking will eventually live behind
-- the store interface; v1 starts with in-memory bbox scans.

local pvm = require("pvm")
local store = require("geopvm.store")
local schema = require("geopvm.asdl")

local M = {}
local T = schema.T
M.T = T

function M.bbox(store_state, layer_name, bbox)
    local features = store.query_bbox(store_state, layer_name, bbox)
    return pvm.seq(features)
end

function M.request(store_state, req)
    return M.bbox(store_state, req.layer, req.bbox)
end

return M
