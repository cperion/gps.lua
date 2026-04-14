#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local clock = os.clock
local fmt = string.format

local SCHEMA = [[
module Bench {
    Coord = (number x, number y) unique
    Ring = (Bench.Coord* coords) unique
    Geometry = Point(number x, number y) unique
             | LineString(Bench.Coord* coords) unique
             | Polygon(Bench.Ring* rings) unique
}
]]

local T = pvm.context():Define(SCHEMA)

local function bench_ms(iters, fn)
    for _ = 1, math.min(5, iters) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = clock()
    local out
    for _ = 1, iters do out = fn() end
    return (clock() - t0) * 1e3 / iters, out
end

local function print_row(cols, widths)
    local out = {}
    for i = 1, #cols do
        out[i] = fmt("%-" .. widths[i] .. "s", tostring(cols[i]))
    end
    print(table.concat(out, "  "))
end

local function build_points(n)
    local Point = T.Bench.Point
    local out = {}
    for i = 1, n do
        out[i] = Point(i, i * 2)
    end
    return out
end

local function build_lines(n)
    local Coord = T.Bench.Coord
    local LineString = T.Bench.LineString
    local out = {}
    for i = 1, n do
        out[i] = LineString({
            Coord(i, i * 2),
            Coord(i + 1, i * 2 + 1),
            Coord(i + 2, i * 2 + 2),
            Coord(i + 3, i * 2 + 3),
        })
    end
    return out
end

local function build_polygons(n)
    local Coord = T.Bench.Coord
    local Ring = T.Bench.Ring
    local Polygon = T.Bench.Polygon
    local out = {}
    for i = 1, n do
        out[i] = Polygon({
            Ring({
                Coord(i, i),
                Coord(i + 10, i),
                Coord(i + 10, i + 10),
                Coord(i, i + 10),
                Coord(i, i),
            })
        })
    end
    return out
end

local function build_mix(n)
    local pts = build_points(math.floor(n / 3))
    local lines = build_lines(math.floor(n / 3))
    local polys = build_polygons(n - #pts - #lines)
    local out = {}
    local k = 0
    for i = 1, #pts do k = k + 1; out[k] = pts[i] end
    for i = 1, #lines do k = k + 1; out[k] = lines[i] end
    for i = 1, #polys do k = k + 1; out[k] = polys[i] end
    return out
end

local function classof_count(xs)
    local acc = 0
    for i = 1, #xs do
        if pvm.classof(xs[i]) then acc = acc + 1 end
    end
    return acc
end

local function scan_points(xs)
    local acc = 0
    for i = 1, #xs do
        local x, y = xs[i]:__raw()
        acc = acc + x + y
    end
    return acc
end

local function scan_lines(xs)
    local acc = 0
    for i = 1, #xs do
        local coords, start, len = xs[i]:__raw_coords()
        local stop = start + len - 1
        for j = start, stop do
            local c = coords[j]
            acc = acc + c.x + c.y
        end
    end
    return acc
end

local function update_points(xs)
    local out = {}
    for i = 1, #xs do
        local p = xs[i]
        local x = p:__raw()
        out[i] = pvm.with(p, { x = x + 1 })
    end
    return out[#out]
end

local function update_lines(xs)
    local out = {}
    for i = 1, #xs do
        out[i] = pvm.with(xs[i], {})
    end
    return out[#out]
end

local function build_geom_phase(name)
    return pvm.phase(name, {
        [T.Bench.Point] = function(self)
            local x, y = self:__raw()
            return pvm.once(x + y)
        end,
        [T.Bench.LineString] = function(self)
            local coords, start, len = self:__raw_coords()
            local fx, fy = coords[start]:__raw()
            local lx, ly = coords[start + len - 1]:__raw()
            return pvm.once(fx + fy + lx + ly)
        end,
        [T.Bench.Polygon] = function(self)
            local rings, rstart = self:__raw_rings()
            local _, _, outer_len = rings[rstart]:__raw_coords()
            return pvm.once(outer_len)
        end,
    })
end

local function phase_sum(xs, phase)
    local acc = 0
    for i = 1, #xs do
        acc = acc + pvm.one(phase(xs[i]))
    end
    return acc
end

local N_POINTS = 30000
local N_LINES = 12000
local N_MIX = 18000

local points = build_points(N_POINTS)
local lines = build_lines(N_LINES)
local mix = build_mix(N_MIX)
local phase = build_geom_phase("geom_handle")

local rows = {}
local function add_row(name, dt_ms, scale)
    rows[#rows + 1] = { name, fmt("%.3f", dt_ms / scale) }
end

add_row("classof(points)", bench_ms(20, function() return classof_count(points) end), N_POINTS / 1e3)
add_row("scan(points)", bench_ms(20, function() return scan_points(points) end), N_POINTS / 1e3)
add_row("scan(lines)", bench_ms(10, function() return scan_lines(lines) end), N_LINES / 1e3)
add_row("pvm.with(points)", bench_ms(5, function() return update_points(points) end), N_POINTS / 1e3)
add_row("pvm.with(lines)", bench_ms(5, function() return update_lines(lines) end), N_LINES / 1e3)
add_row("phase_cold(mix)", bench_ms(5, function() phase:reset(); return phase_sum(mix, phase) end), N_MIX / 1e3)
phase_sum(mix, phase)
add_row("phase_hot(mix)", bench_ms(20, function() return phase_sum(mix, phase) end), N_MIX / 1e3)

print("pvm handle bench")
print("handle-backed ASDL is the only supported runtime path")
print("units: us per 1k nodes")
print("sample storage:")
print("  point storage = " .. tostring(pvm.classof(points[1]).__storage))
do
    local _, _, coords_len = lines[1]:__raw_coords()
    print("  line  storage = " .. tostring(pvm.classof(lines[1]).__storage) .. ", coords_len = " .. tostring(coords_len))
end
print()
print_row({ "bench", "us/1k" }, { 20, 12 })
print_row({ "--------------------", "------------" }, { 20, 12 })
for i = 1, #rows do
    print_row(rows[i], { 20, 12 })
end
print()
print("phase report:")
print(pvm.report_string({ phase }))
