-- geopvm/geoarrow.lua
--
-- Minimal GeoArrow-shaped layer geometry columns for hot numeric kernels.
--
-- Scope:
--   - XY only
--   - Point / LineString / Polygon
--   - separated coordinate arrays (x[], y[])
--   - top-level geometry selector via type_id[] + child_offset[]
--
-- This is an internal realization for static/memory-backed layers. It does not
-- replace ASDL semantic nodes.

local abs = math.abs
local floor = math.floor
local max = math.max
local min = math.min
local tconcat = table.concat

local pvm = require("pvm")
local classof = pvm.classof
local schema = require("geopvm.asdl")

local M = {}
local T = schema.T
M.T = T

M.K_POINT = 1
M.K_LINE = 2
M.K_POLY = 3

local EPS = 1e-9

local function append_xy(xs, ys, x, y)
    local n = #xs
    if n > 0 and abs(xs[n] - x) <= EPS and abs(ys[n] - y) <= EPS then
        return
    end
    xs[n + 1] = x
    ys[n + 1] = y
end

function M.build(entries)
    local cols = {
        type_id = {},
        child_offset = {},

        point_x = {},
        point_y = {},

        line_geom_offsets = {},
        line_x = {},
        line_y = {},

        poly_geom_offsets = {},
        poly_ring_offsets = {},
        poly_x = {},
        poly_y = {},
    }

    for i = 1, #entries do
        local geom = entries[i].feature.geom
        local mt = classof(geom)
        entries[i].geom_index = i

        if mt == T.Geo.Point then
            cols.type_id[i] = M.K_POINT
            cols.child_offset[i] = #cols.point_x + 1
            cols.point_x[#cols.point_x + 1] = geom.x
            cols.point_y[#cols.point_y + 1] = geom.y

        elseif mt == T.Geo.LineString then
            cols.type_id[i] = M.K_LINE
            cols.child_offset[i] = #cols.line_geom_offsets + 1
            cols.line_geom_offsets[#cols.line_geom_offsets + 1] = #cols.line_x + 1
            local pts, start, len = geom:__raw_coords()
            local stop = start + len - 1
            for j = start, stop do
                cols.line_x[#cols.line_x + 1] = pts[j].x
                cols.line_y[#cols.line_y + 1] = pts[j].y
            end

        elseif mt == T.Geo.Polygon then
            cols.type_id[i] = M.K_POLY
            cols.child_offset[i] = #cols.poly_geom_offsets + 1
            cols.poly_geom_offsets[#cols.poly_geom_offsets + 1] = #cols.poly_ring_offsets + 1
            local rings, rstart, rlen = geom:__raw_rings()
            local rstop = rstart + rlen - 1
            for r = rstart, rstop do
                cols.poly_ring_offsets[#cols.poly_ring_offsets + 1] = #cols.poly_x + 1
                local pts, pstart, plen = rings[r]:__raw_coords()
                local pstop = pstart + plen - 1
                for j = pstart, pstop do
                    cols.poly_x[#cols.poly_x + 1] = pts[j].x
                    cols.poly_y[#cols.poly_y + 1] = pts[j].y
                end
            end
        else
            error("unsupported geometry for geoarrow build", 2)
        end
    end

    cols.line_geom_offsets[#cols.line_geom_offsets + 1] = #cols.line_x + 1
    cols.poly_geom_offsets[#cols.poly_geom_offsets + 1] = #cols.poly_ring_offsets + 1
    cols.poly_ring_offsets[#cols.poly_ring_offsets + 1] = #cols.poly_x + 1

    return cols
end

local function quantize(v, lo, hi, extent)
    local span = hi - lo
    if span == 0 then return 0 end
    local q = floor(((v - lo) / span) * extent + 0.5)
    return min(extent, max(0, q))
end

local function point_text(x, y, bbox, extent)
    local minx, miny, maxx, maxy = bbox:__raw()
    return quantize(x, minx, maxx, extent) .. ":" ..
           quantize(y, miny, maxy, extent)
end

local function point_in_bbox(x, y, bbox)
    local minx, miny, maxx, maxy = bbox:__raw()
    return x >= minx and x <= maxx and y >= miny and y <= maxy
end

local function clip_segment_to_bbox(x0, y0, x1, y1, bbox)
    local minx, miny, maxx, maxy = bbox:__raw()
    local dx = x1 - x0
    local dy = y1 - y0
    local t0, t1 = 0.0, 1.0

    local function cliptest(p, q)
        if p == 0 then
            return q >= 0
        end
        local r = q / p
        if p < 0 then
            if r > t1 then return false end
            if r > t0 then t0 = r end
        else
            if r < t0 then return false end
            if r < t1 then t1 = r end
        end
        return true
    end

    if not cliptest(-dx, x0 - minx) then return nil end
    if not cliptest( dx, maxx - x0) then return nil end
    if not cliptest(-dy, y0 - miny) then return nil end
    if not cliptest( dy, maxy - y0) then return nil end

    return x0 + t0 * dx, y0 + t0 * dy, x0 + t1 * dx, y0 + t1 * dy
end

local function edge_inside_xy(x, y, edge, bbox)
    local minx, miny, maxx, maxy = bbox:__raw()
    if edge == 1 then return x >= minx - EPS end
    if edge == 2 then return x <= maxx + EPS end
    if edge == 3 then return y >= miny - EPS end
    return y <= maxy + EPS
end

local function edge_intersection_xy(ax, ay, bx, by, edge, bbox)
    local minx, miny, maxx, maxy = bbox:__raw()
    if edge == 1 or edge == 2 then
        local x = (edge == 1) and minx or maxx
        local dx = bx - ax
        if abs(dx) <= EPS then return x, ay end
        local t = (x - ax) / dx
        return x, ay + t * (by - ay)
    else
        local y = (edge == 3) and miny or maxy
        local dy = by - ay
        if abs(dy) <= EPS then return ax, y end
        local t = (y - ay) / dy
        return ax + t * (bx - ax), y
    end
end

local function encode_point(cols, off, bbox, extent)
    local x = cols.point_x[off]
    local y = cols.point_y[off]
    if not point_in_bbox(x, y, bbox) then return nil end
    return point_text(x, y, bbox, extent), "Point"
end

local function encode_line(cols, off, bbox, extent)
    local start_i = cols.line_geom_offsets[off]
    local stop_i = cols.line_geom_offsets[off + 1] - 1
    if stop_i - start_i + 1 < 2 then return nil end

    local best_xs, best_ys, best_score = nil, nil, -1
    local run_xs, run_ys, run_score = nil, nil, 0

    for i = start_i, stop_i - 1 do
        local x0, y0 = cols.line_x[i], cols.line_y[i]
        local x1, y1 = cols.line_x[i + 1], cols.line_y[i + 1]
        local cx0, cy0, cx1, cy1 = clip_segment_to_bbox(x0, y0, x1, y1, bbox)
        if cx0 then
            local score = (cx1 - cx0) * (cx1 - cx0) + (cy1 - cy0) * (cy1 - cy0)
            if run_xs == nil then
                run_xs, run_ys = {}, {}
                run_score = score
                append_xy(run_xs, run_ys, cx0, cy0)
                append_xy(run_xs, run_ys, cx1, cy1)
            else
                local n = #run_xs
                if abs(run_xs[n] - cx0) <= EPS and abs(run_ys[n] - cy0) <= EPS then
                    append_xy(run_xs, run_ys, cx1, cy1)
                    run_score = run_score + score
                else
                    if run_xs and #run_xs >= 2 and run_score > best_score then
                        best_xs, best_ys, best_score = run_xs, run_ys, run_score
                    end
                    run_xs, run_ys = {}, {}
                    run_score = score
                    append_xy(run_xs, run_ys, cx0, cy0)
                    append_xy(run_xs, run_ys, cx1, cy1)
                end
            end
        else
            if run_xs and #run_xs >= 2 and run_score > best_score then
                best_xs, best_ys, best_score = run_xs, run_ys, run_score
            end
            run_xs, run_ys, run_score = nil, nil, 0
        end
    end

    if run_xs and #run_xs >= 2 and run_score > best_score then
        best_xs, best_ys = run_xs, run_ys
    end
    if best_xs == nil then return nil end

    local out = {}
    for i = 1, #best_xs do
        out[i] = point_text(best_xs[i], best_ys[i], bbox, extent)
    end
    return tconcat(out, ";"), "LineString"
end

local function clip_ring(cols_x, cols_y, start_i, stop_i, bbox)
    local input_x, input_y = {}, {}
    local n = 0
    local end_i = stop_i
    if stop_i - start_i >= 1 then
        local x0, y0 = cols_x[start_i], cols_y[start_i]
        local xn, yn = cols_x[stop_i], cols_y[stop_i]
        if abs(x0 - xn) <= EPS and abs(y0 - yn) <= EPS then
            end_i = stop_i - 1
        end
    end
    for i = start_i, end_i do
        n = n + 1; input_x[n] = cols_x[i]; input_y[n] = cols_y[i]
    end

    for edge = 1, 4 do
        if #input_x == 0 then break end
        local out_x, out_y = {}, {}
        local sx, sy = input_x[#input_x], input_y[#input_y]
        local s_in = edge_inside_xy(sx, sy, edge, bbox)
        for i = 1, #input_x do
            local ex, ey = input_x[i], input_y[i]
            local e_in = edge_inside_xy(ex, ey, edge, bbox)
            if e_in then
                if not s_in then
                    local ix, iy = edge_intersection_xy(sx, sy, ex, ey, edge, bbox)
                    append_xy(out_x, out_y, ix, iy)
                end
                append_xy(out_x, out_y, ex, ey)
            elseif s_in then
                local ix, iy = edge_intersection_xy(sx, sy, ex, ey, edge, bbox)
                append_xy(out_x, out_y, ix, iy)
            end
            sx, sy, s_in = ex, ey, e_in
        end
        input_x, input_y = out_x, out_y
    end

    if #input_x < 3 then return nil end
    if abs(input_x[1] - input_x[#input_x]) > EPS or abs(input_y[1] - input_y[#input_y]) > EPS then
        input_x[#input_x + 1] = input_x[1]
        input_y[#input_y + 1] = input_y[1]
    end
    if #input_x < 4 then return nil end
    return input_x, input_y
end

local function encode_polygon(cols, off, bbox, extent)
    local ring_start = cols.poly_geom_offsets[off]
    local ring_stop = cols.poly_geom_offsets[off + 1] - 1
    local out = {}
    local rn = 0

    for r = ring_start, ring_stop do
        local start_i = cols.poly_ring_offsets[r]
        local stop_i = cols.poly_ring_offsets[r + 1] - 1
        local xs, ys = clip_ring(cols.poly_x, cols.poly_y, start_i, stop_i, bbox)
        if xs ~= nil then
            local pts = {}
            for i = 1, #xs do
                pts[i] = point_text(xs[i], ys[i], bbox, extent)
            end
            rn = rn + 1
            out[rn] = tconcat(pts, ";")
        end
    end

    if rn == 0 then return nil end
    return tconcat(out, "|"), "Polygon"
end

function M.encode_geometry(cols, geom_index, bbox, extent)
    local kind = cols.type_id[geom_index]
    local off = cols.child_offset[geom_index]
    if kind == M.K_POINT then return encode_point(cols, off, bbox, extent) end
    if kind == M.K_LINE then return encode_line(cols, off, bbox, extent) end
    if kind == M.K_POLY then return encode_polygon(cols, off, bbox, extent) end
    return nil
end

return M
