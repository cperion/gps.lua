#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local jp = require("jit.p")
local geopvm = require("geopvm")

local floor = math.floor

local T = geopvm.T
local EMPTY = geopvm.schema.EMPTY_PROPS

local function origin_tile_xy(z)
    local n = 2 ^ z
    return floor(n / 2), floor(n / 2)
end

local function point_features(n)
    local side = floor(math.sqrt(n) + 0.5)
    if side * side < n then side = side + 1 end
    local step = 128
    local start = -floor(side / 2) * step
    local out = {}
    local k = 0
    for iy = 1, side do
        for ix = 1, side do
            k = k + 1
            if k > n then return out end
            local x = start + (ix - 1) * step
            local y = start + (iy - 1) * step
            out[k] = T.Geo.Feature("p" .. k, T.Geo.Point(x, y), EMPTY)
        end
    end
    return out
end

local function line_features(n)
    local out = {}
    local span = 4096
    local step = 64
    local base = -floor(n / 2) * step
    for i = 1, n do
        local y = base + (i - 1) * step
        out[i] = T.Geo.Feature("l" .. i, T.Geo.LineString({
            T.Geo.Coord(-span, y),
            T.Geo.Coord(0, y),
            T.Geo.Coord(span, y),
        }), EMPTY)
    end
    return out
end

local shape = arg[1] or "line"
local n = tonumber(arg[2]) or 5000
local iters = tonumber(arg[3]) or 500
local mode = arg[4] or "vf2i1m1"
local outfile = arg[5] or "/tmp/geopvm_tile_profile.out"
local warm = (arg[6] == nil) and true or (arg[6] == "warm")

local features = (shape == "point") and point_features(n) or line_features(n)
local store = geopvm.store.new({ tile_cache_size = 64, decode_cache_size = 64 })
geopvm.store.add_memory_layer(store, "demo", 3857, features)

local z = 15
local x, y = origin_tile_xy(z)

if warm then
    geopvm.tile.build_mvt(store, "demo", z, x, y)
end

jp.start(mode, outfile)
for _ = 1, iters do
    if not warm then store.tile_cache:clear() end
    geopvm.tile.build_mvt(store, "demo", z, x, y)
end
jp.stop()

print(string.format("wrote profile to %s  shape=%s n=%d warm=%s", outfile, shape, n, tostring(warm)))
