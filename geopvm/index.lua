-- geopvm/index.lua
--
-- Simple in-memory static bbox grid index for v1.
--
-- This is not the final FlatGeobuf packed-index path. It exists to move the
-- store/query layer away from pure full scans while keeping the same external
-- interface.

local floor = math.floor
local max = math.max
local min = math.min
local sqrt = math.sqrt

local schema = require("geopvm.asdl")

local M = {}
local T = schema.T
M.T = T

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function layer_bbox(entries)
    if #entries == 0 then
        return T.Geo.BBox(0, 0, 1, 1)
    end

    local b = entries[1].bbox
    local minx, miny = b.minx, b.miny
    local maxx, maxy = b.maxx, b.maxy

    for i = 2, #entries do
        b = entries[i].bbox
        if b.minx < minx then minx = b.minx end
        if b.miny < miny then miny = b.miny end
        if b.maxx > maxx then maxx = b.maxx end
        if b.maxy > maxy then maxy = b.maxy end
    end

    if minx == maxx then maxx = maxx + 1 end
    if miny == maxy then maxy = maxy + 1 end
    return T.Geo.BBox(minx, miny, maxx, maxy)
end

local function grid_side(n)
    if n <= 16 then return 1 end
    return clamp(floor(sqrt(n) / 2), 2, 32)
end

local function cell_range(axis_min, axis_max, bins, v0, v1)
    local span = axis_max - axis_min
    local a = floor(((v0 - axis_min) / span) * bins) + 1
    local b = floor(((v1 - axis_min) / span) * bins) + 1
    return clamp(a, 1, bins), clamp(b, 1, bins)
end

function M.build(entries)
    local bbox = layer_bbox(entries)
    local nx = grid_side(#entries)
    local ny = nx
    local cells = {}

    for i = 1, #entries do
        local entry = entries[i]
        local ix0, ix1 = cell_range(bbox.minx, bbox.maxx, nx, entry.bbox.minx, entry.bbox.maxx)
        local iy0, iy1 = cell_range(bbox.miny, bbox.maxy, ny, entry.bbox.miny, entry.bbox.maxy)

        for iy = iy0, iy1 do
            local row = (iy - 1) * nx
            for ix = ix0, ix1 do
                local key = row + ix
                local bucket = cells[key]
                if bucket == nil then
                    bucket = {}
                    cells[key] = bucket
                end
                bucket[#bucket + 1] = entry
            end
        end
    end

    return {
        bbox = bbox,
        nx = nx,
        ny = ny,
        cells = cells,
    }
end

function M.query(index, bbox)
    if index == nil then return {} end

    local ib = index.bbox
    local ix0, ix1 = cell_range(ib.minx, ib.maxx, index.nx, bbox.minx, bbox.maxx)
    local iy0, iy1 = cell_range(ib.miny, ib.maxy, index.ny, bbox.miny, bbox.maxy)

    local out = {}
    local seen = {}

    for iy = iy0, iy1 do
        local row = (iy - 1) * index.nx
        for ix = ix0, ix1 do
            local bucket = index.cells[row + ix]
            if bucket ~= nil then
                for i = 1, #bucket do
                    local entry = bucket[i]
                    if not seen[entry] then
                        seen[entry] = true
                        out[#out + 1] = entry
                    end
                end
            end
        end
    end

    return out
end

return M
