-- geopvm/util.lua
--
-- Geometry/bbox helpers for the v1 skeleton.

local atan = math.atan
local abs = math.abs
local exp = math.exp
local huge = math.huge
local log = math.log
local max = math.max
local min = math.min
local pi = math.pi
local rad = math.rad
local tan = math.tan

local pvm = require("pvm")
local classof = pvm.classof
local schema = require("geopvm.asdl")

local M = {}
local T = schema.T
M.T = T

local WEB_MERCATOR_R = 6378137.0
local EPS = 1e-9
M.WEB_MERCATOR_R = WEB_MERCATOR_R

local function sinh(x)
    return 0.5 * (exp(x) - exp(-x))
end

local function mercator_x_from_lon(lon)
    return WEB_MERCATOR_R * rad(lon)
end

local function mercator_y_from_lat(lat)
    local clamped = max(min(lat, 85.05112878), -85.05112878)
    return WEB_MERCATOR_R * log(tan(pi * 0.25 + rad(clamped) * 0.5))
end

local function bbox_from_extents(minx, miny, maxx, maxy)
    return T.Geo.BBox(minx, miny, maxx, maxy)
end

function M.bbox_intersects(a, b)
    local aminx, aminy, amaxx, amaxy = a:__raw()
    local bminx, bminy, bmaxx, bmaxy = b:__raw()
    return not (
        amaxx < bminx or
        aminx > bmaxx or
        amaxy < bminy or
        aminy > bmaxy
    )
end

function M.bbox_contains_bbox(a, b)
    local aminx, aminy, amaxx, amaxy = a:__raw()
    local bminx, bminy, bmaxx, bmaxy = b:__raw()
    return aminx <= bminx and aminy <= bminy and amaxx >= bmaxx and amaxy >= bmaxy
end

function M.tile_bbox_3857(z, x, y)
    local n = 2 ^ z
    local lon_min = (x / n) * 360.0 - 180.0
    local lon_max = ((x + 1) / n) * 360.0 - 180.0

    local lat_max = math.deg(atan(sinh(pi * (1.0 - (2.0 * y) / n))))
    local lat_min = math.deg(atan(sinh(pi * (1.0 - (2.0 * (y + 1)) / n))))

    return bbox_from_extents(
        mercator_x_from_lon(lon_min),
        mercator_y_from_lat(lat_min),
        mercator_x_from_lon(lon_max),
        mercator_y_from_lat(lat_max)
    )
end

function M.geom_bbox(geom)
    local mt = classof(geom)

    if mt == T.Geo.Point then
        local x, y = geom:__raw()
        return bbox_from_extents(x, y, x, y)
    end

    local minx, miny = huge, huge
    local maxx, maxy = -huge, -huge

    if mt == T.Geo.LineString then
        local coords, start, len = geom:__raw_coords()
        local stop = start + len - 1
        for i = start, stop do
            local c = coords[i]
            minx = min(minx, c.x)
            miny = min(miny, c.y)
            maxx = max(maxx, c.x)
            maxy = max(maxy, c.y)
        end
        return bbox_from_extents(minx, miny, maxx, maxy)
    end

    if mt == T.Geo.Polygon then
        local rings, rstart, rlen = geom:__raw_rings()
        local rstop = rstart + rlen - 1
        for i = rstart, rstop do
            local coords, cstart, clen = rings[i]:__raw_coords()
            local cstop = cstart + clen - 1
            for j = cstart, cstop do
                local c = coords[j]
                minx = min(minx, c.x)
                miny = min(miny, c.y)
                maxx = max(maxx, c.x)
                maxy = max(maxy, c.y)
            end
        end
        return bbox_from_extents(minx, miny, maxx, maxy)
    end

    error("unsupported geometry for bbox")
end

local function point_in_bbox(x, y, bbox)
    local minx, miny, maxx, maxy = bbox:__raw()
    return x >= minx and x <= maxx and y >= miny and y <= maxy
end
M.point_in_bbox = point_in_bbox

local function coord_eq_xy(c, x, y)
    return abs(c.x - x) <= EPS and abs(c.y - y) <= EPS
end

local function append_xy(out, x, y)
    local n = #out
    if n > 0 and coord_eq_xy(out[n], x, y) then
        return
    end
    out[n + 1] = T.Geo.Coord(x, y)
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

local function segment_length2(x0, y0, x1, y1)
    local dx = x1 - x0
    local dy = y1 - y0
    return dx * dx + dy * dy
end

local function choose_longest_run(best_coords, best_score, coords, score)
    if coords and #coords >= 2 and score > best_score then
        return coords, score
    end
    return best_coords, best_score
end

M.clip_segment_to_bbox = clip_segment_to_bbox

local function point_plain(x, y)
    return { x = x, y = y }
end

local function plain_eq(a, b)
    return abs(a.x - b.x) <= EPS and abs(a.y - b.y) <= EPS
end

local function clip_linestring_raw(geom, bbox)
    local coords, start, len = geom:__raw_coords()
    if len < 2 then
        return nil
    end

    local best_coords, best_score = nil, -1
    local run_coords, run_score = nil, 0
    local stop = start + len - 2

    for i = start, stop do
        local a = coords[i]
        local b = coords[i + 1]
        local ax, ay = a:__raw()
        local bx, by = b:__raw()
        local x0, y0, x1, y1 = clip_segment_to_bbox(ax, ay, bx, by, bbox)

        if x0 then
            if run_coords == nil then
                run_coords = {}
                run_score = 0
                run_coords[1] = point_plain(x0, y0)
                if not plain_eq(run_coords[1], point_plain(x1, y1)) then
                    run_coords[2] = point_plain(x1, y1)
                end
                run_score = run_score + segment_length2(x0, y0, x1, y1)
            else
                local last = run_coords[#run_coords]
                if plain_eq(last, point_plain(x0, y0)) then
                    if not plain_eq(last, point_plain(x1, y1)) then
                        run_coords[#run_coords + 1] = point_plain(x1, y1)
                    end
                    run_score = run_score + segment_length2(x0, y0, x1, y1)
                else
                    best_coords, best_score = choose_longest_run(best_coords, best_score, run_coords, run_score)
                    run_coords = { point_plain(x0, y0) }
                    if not plain_eq(run_coords[1], point_plain(x1, y1)) then
                        run_coords[2] = point_plain(x1, y1)
                    end
                    run_score = segment_length2(x0, y0, x1, y1)
                end
            end
        else
            best_coords, best_score = choose_longest_run(best_coords, best_score, run_coords, run_score)
            run_coords, run_score = nil, 0
        end
    end

    best_coords, best_score = choose_longest_run(best_coords, best_score, run_coords, run_score)
    if not best_coords or #best_coords < 2 then
        return nil
    end
    return best_coords
end

M.clip_linestring_raw = clip_linestring_raw

local function clip_linestring(geom, bbox)
    local coords, start, len = geom:__raw_coords()
    if len < 2 then
        return nil
    end

    local best_coords, best_score = nil, -1
    local run_coords, run_score = nil, 0
    local stop = start + len - 2

    for i = start, stop do
        local a = coords[i]
        local b = coords[i + 1]
        local ax, ay = a:__raw()
        local bx, by = b:__raw()
        local x0, y0, x1, y1 = clip_segment_to_bbox(ax, ay, bx, by, bbox)

        if x0 then
            if run_coords == nil then
                run_coords = {}
                run_score = 0
                append_xy(run_coords, x0, y0)
                append_xy(run_coords, x1, y1)
                run_score = run_score + segment_length2(x0, y0, x1, y1)
            else
                local last = run_coords[#run_coords]
                if coord_eq_xy(last, x0, y0) then
                    append_xy(run_coords, x1, y1)
                    run_score = run_score + segment_length2(x0, y0, x1, y1)
                else
                    best_coords, best_score = choose_longest_run(best_coords, best_score, run_coords, run_score)
                    run_coords = {}
                    run_score = segment_length2(x0, y0, x1, y1)
                    append_xy(run_coords, x0, y0)
                    append_xy(run_coords, x1, y1)
                end
            end
        else
            best_coords, best_score = choose_longest_run(best_coords, best_score, run_coords, run_score)
            run_coords, run_score = nil, 0
        end
    end

    best_coords, best_score = choose_longest_run(best_coords, best_score, run_coords, run_score)
    if not best_coords or #best_coords < 2 then
        return nil
    end
    return T.Geo.LineString(best_coords)
end

local function plain_ring_from_raw(coords, start, len)
    local n = len
    local last = start + len - 1
    if n > 1 and coord_eq_xy(coords[start], coords[last].x, coords[last].y) then
        n = n - 1
    end
    local out = {}
    for i = 0, n - 1 do
        local c = coords[start + i]
        out[i + 1] = point_plain(c.x, c.y)
    end
    return out
end

local function edge_inside(p, edge, bbox)
    local minx, miny, maxx, maxy = bbox:__raw()
    if edge == 1 then return p.x >= minx - EPS end
    if edge == 2 then return p.x <= maxx + EPS end
    if edge == 3 then return p.y >= miny - EPS end
    return p.y <= maxy + EPS
end

local function edge_intersection(a, b, edge, bbox)
    local minx, miny, maxx, maxy = bbox:__raw()
    if edge == 1 or edge == 2 then
        local x = (edge == 1) and minx or maxx
        local dx = b.x - a.x
        if abs(dx) <= EPS then return point_plain(x, a.y) end
        local t = (x - a.x) / dx
        return point_plain(x, a.y + t * (b.y - a.y))
    else
        local y = (edge == 3) and miny or maxy
        local dy = b.y - a.y
        if abs(dy) <= EPS then return point_plain(a.x, y) end
        local t = (y - a.y) / dy
        return point_plain(a.x + t * (b.x - a.x), y)
    end
end

local function clip_ring_points(points, bbox)
    local input = points
    for edge = 1, 4 do
        if #input == 0 then break end
        local output = {}
        local s = input[#input]
        local s_in = edge_inside(s, edge, bbox)
        for i = 1, #input do
            local e = input[i]
            local e_in = edge_inside(e, edge, bbox)
            if e_in then
                if not s_in then
                    output[#output + 1] = edge_intersection(s, e, edge, bbox)
                end
                output[#output + 1] = e
            elseif s_in then
                output[#output + 1] = edge_intersection(s, e, edge, bbox)
            end
            s, s_in = e, e_in
        end
        input = output
    end
    return input
end

local function close_ring_points(points)
    if #points < 3 then
        return nil
    end
    if not plain_eq(points[1], points[#points]) then
        points[#points + 1] = point_plain(points[1].x, points[1].y)
    end
    if #points < 4 then
        return nil
    end
    local out = {}
    for i = 1, #points do
        out[i] = T.Geo.Coord(points[i].x, points[i].y)
    end
    return T.Geo.Ring(out)
end

local function clip_polygon_raw(geom, bbox)
    local rings, start, len = geom:__raw_rings()
    local out = {}
    local stop = start + len - 1
    for i = start, stop do
        local coords, cstart, clen = rings[i]:__raw_coords()
        local points = plain_ring_from_raw(coords, cstart, clen)
        local clipped = clip_ring_points(points, bbox)
        if #clipped >= 3 then
            if not plain_eq(clipped[1], clipped[#clipped]) then
                clipped[#clipped + 1] = point_plain(clipped[1].x, clipped[1].y)
            end
            if #clipped >= 4 then
                out[#out + 1] = clipped
            end
        end
    end
    if #out == 0 then return nil end
    return out
end

M.clip_polygon_raw = clip_polygon_raw

local function clip_polygon(geom, bbox)
    local rings, start, len = geom:__raw_rings()
    local out = {}
    local stop = start + len - 1
    for i = start, stop do
        local coords, cstart, clen = rings[i]:__raw_coords()
        local points = plain_ring_from_raw(coords, cstart, clen)
        local clipped = clip_ring_points(points, bbox)
        local ring = close_ring_points(clipped)
        if ring ~= nil then
            out[#out + 1] = ring
        end
    end
    if #out == 0 then
        return nil
    end
    return T.Geo.Polygon(out)
end

function M.clip_feature(feature, bbox)
    local geom = feature.geom
    local fbbox = M.geom_bbox(geom)
    if not M.bbox_intersects(fbbox, bbox) then
        return nil
    end
    if M.bbox_contains_bbox(bbox, fbbox) then
        return feature
    end

    local mt = classof(geom)
    local clipped

    if mt == T.Geo.Point then
        local x, y = geom:__raw()
        if point_in_bbox(x, y, bbox) then
            return feature
        end
        return nil
    elseif mt == T.Geo.LineString then
        clipped = clip_linestring(geom, bbox)
    elseif mt == T.Geo.Polygon then
        clipped = clip_polygon(geom, bbox)
    else
        error("unsupported geometry for clipping")
    end

    if clipped == nil then
        return nil
    end
    if clipped == geom then
        return feature
    end
    return pvm.with(feature, { geom = clipped })
end

return M
