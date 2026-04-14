-- geopvm/clip.lua
--
-- Direct geometry clipping kernel.
--
-- v1 performs bbox clipping for Point / LineString / Polygon geometries.
-- GeometryCollection / Multi* types are intentionally out of scope for now.

local schema = require("geopvm.asdl")
local util = require("geopvm.util")

local M = {}
local T = schema.T
M.T = T

function M.run(feature, bbox)
    return util.clip_feature(feature, bbox)
end

return M
