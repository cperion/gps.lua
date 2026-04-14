#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local geopvm = require("geopvm")
local pvm = require("pvm")

local clock = os.clock
local floor = math.floor
local fmt = string.format

local T = geopvm.T
local EMPTY = geopvm.schema.EMPTY_PROPS
local util = geopvm.util

local function bench_us(iters, fn)
    for _ = 1, math.min(20, iters) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = clock()
    for _ = 1, iters do fn() end
    local dt = clock() - t0
    return dt * 1e6 / iters
end

local function print_row(cols, widths)
    local out = {}
    for i = 1, #cols do
        out[i] = fmt("%-" .. widths[i] .. "s", tostring(cols[i]))
    end
    print(table.concat(out, "  "))
end

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

local function run_case(shape, n, make_features)
    local features = make_features(n)
    local z = 15
    local x, y = origin_tile_xy(z)
    local bbox = util.tile_bbox_3857(z, x, y)

    local build_us = bench_us(1, function()
        local store = geopvm.store.new({ tile_cache_size = 64, decode_cache_size = 64 })
        geopvm.store.add_memory_layer(store, "demo", 3857, features)
    end)

    local store = geopvm.store.new({ tile_cache_size = 64, decode_cache_size = 64 })
    geopvm.store.add_memory_layer(store, "demo", 3857, features)

    local query_iters = (n <= 1000) and 2000 or 500
    local query_us = bench_us(query_iters, function()
        local out = geopvm.store.query_bbox(store, "demo", bbox)
        return out[1]
    end)

    local clip_iters = (n <= 1000) and 2000 or 500
    local candidates = geopvm.store.query_bbox(store, "demo", bbox)
    local clip_us = bench_us(clip_iters, function()
        local count = 0
        for i = 1, #candidates do
            if geopvm.clip.run(candidates[i], bbox) ~= nil then count = count + 1 end
        end
        return count
    end)

    local tile_cold_iters = (n <= 1000) and 400 or 80
    local tile_cold_us = bench_us(tile_cold_iters, function()
        store.tile_cache:clear()
        return geopvm.tile.build_mvt(store, "demo", z, x, y)
    end)

    local _ = geopvm.tile.build_mvt(store, "demo", z, x, y)
    local tile_hot_us = bench_us(query_iters, function()
        return geopvm.tile.build_mvt(store, "demo", z, x, y)
    end)

    local query_n = #geopvm.store.query_bbox(store, "demo", bbox)
    local tile_bytes = #geopvm.tile.build_mvt(store, "demo", z, x, y)

    return {
        shape = shape,
        n = n,
        query_n = query_n,
        build_us = build_us,
        query_us = query_us,
        clip_us = clip_us,
        tile_cold_us = tile_cold_us,
        tile_hot_us = tile_hot_us,
        tile_bytes = tile_bytes,
        report = (#geopvm.tile.phases > 0) and pvm.report_string(geopvm.tile.phases) or "  (no inner pvm phases in tile path)",
    }
end

local rows = {}
rows[#rows + 1] = run_case("point", 1000, point_features)
rows[#rows + 1] = run_case("point", 10000, point_features)
rows[#rows + 1] = run_case("line", 1000, line_features)
rows[#rows + 1] = run_case("line", 5000, line_features)

print("geopvm memory bench")
print("indexed in-memory layer, bbox query, clip, tile cold/hot")
print_row(
    { "shape", "n", "hits", "build_us", "query_us", "clip_us", "tile_cold", "tile_hot", "tile_bytes" },
    { 8, 8, 8, 10, 10, 10, 10, 10, 10 }
)
print_row(
    { "--------", "--------", "--------", "----------", "----------", "----------", "----------", "----------", "----------" },
    { 8, 8, 8, 10, 10, 10, 10, 10, 10 }
)
for _, row in ipairs(rows) do
    print_row({
        row.shape,
        row.n,
        row.query_n,
        fmt("%.2f", row.build_us),
        fmt("%.2f", row.query_us),
        fmt("%.2f", row.clip_us),
        fmt("%.2f", row.tile_cold_us),
        fmt("%.2f", row.tile_hot_us),
        row.tile_bytes,
    }, { 8, 8, 8, 10, 10, 10, 10, 10, 10 })
end

print()
print("phase reports:")
for _, row in ipairs(rows) do
    print(string.format("[%s %d]", row.shape, row.n))
    print(row.report)
end
