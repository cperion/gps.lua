-- ui/_grid.lua
--
-- Shared internal grid kernel.
--
-- This module is intentionally private to the UI implementation. It owns the
-- common explicit-grid helpers used by measurement and runtime placement so the
-- reducers do not drift. The model is small and opinionated: explicit tracks,
-- explicit item placement, and simple spans.

local pvm = require("pvm")
local classof = pvm.classof
local schema = require("ui.asdl")

local T = schema.T

local grid = { T = T, schema = schema }

local math_floor = math.floor
local math_huge = math.huge
local math_max = math.max
local math_min = math.min

local INF = math_huge

local TRACK_AUTO = T.Layout.TrackAuto
local mtTrackPx = classof(T.Layout.TrackPx(0))
local mtTrackFr = classof(T.Layout.TrackFr(1))

function grid.track_bases(tracks)
    local out = {}
    for i = 1, #tracks do
        out[i] = 0
    end
    return out
end

function grid.item_slot(item, col_count, row_count)
    local col = math_max(1, math_min(col_count, math_floor(item.col)))
    local row = math_max(1, math_min(row_count, math_floor(item.row)))
    local col_span = math_max(1, math_floor(item.col_span or 1))
    local row_span = math_max(1, math_floor(item.row_span or 1))
    if col + col_span - 1 > col_count then
        col_span = col_count - col + 1
    end
    if row + row_span - 1 > row_count then
        row_span = row_count - row + 1
    end
    return col, row, col_span, row_span
end

function grid.span_total(sizes, start_i, span, gap)
    local total = 0
    for i = start_i, start_i + span - 1 do
        total = total + (sizes[i] or 0)
    end
    return total + gap * math_max(0, span - 1)
end

function grid.distribute_min(bases, start_i, span, gap, need)
    local target = math_max(0, (need - gap * math_max(0, span - 1)) / span)
    for i = start_i, start_i + span - 1 do
        bases[i] = math_max(bases[i] or 0, target)
    end
end

function grid.track_sizes(tracks, bases, gap, avail)
    local sizes = {}
    local fr_weight = 0
    local total = gap * math_max(0, #tracks - 1)

    for i = 1, #tracks do
        local track = tracks[i]
        local mt = classof(track)
        local base = bases[i] or 0
        if mt == mtTrackPx then
            sizes[i] = track.px
        elseif track == TRACK_AUTO then
            sizes[i] = base
        elseif mt == mtTrackFr then
            sizes[i] = base
            fr_weight = fr_weight + track.weight
        else
            sizes[i] = base
        end
        total = total + sizes[i]
    end

    if avail and avail ~= INF and fr_weight > 0 and total < avail then
        local extra = avail - total
        for i = 1, #tracks do
            local track = tracks[i]
            if classof(track) == mtTrackFr then
                sizes[i] = sizes[i] + extra * (track.weight / fr_weight)
            end
        end
        total = avail
    end

    return sizes, total
end

function grid.layout_children(node, frame, measure_api, measure_opts, mkframe)
    local items = node.children
    local cols = node.cols
    local rows = node.rows
    local placed = {}
    if #items == 0 or #cols == 0 or #rows == 0 then
        return placed
    end

    local gap_x = node.gap_x or 0
    local gap_y = node.gap_y or 0
    local col_bases = grid.track_bases(cols)
    local row_bases = grid.track_bases(rows)

    for i = 1, #items do
        local item = items[i]
        local c, _, col_span = grid.item_slot(item, #cols, #rows)
        local m = measure_api.measure(item.node,
            measure_api.constraint(measure_api.UNCONSTRAINED, measure_api.UNCONSTRAINED), measure_opts)
        grid.distribute_min(col_bases, c, col_span, gap_x, m.intrinsic.min_w)
    end

    local col_sizes = grid.track_sizes(cols, col_bases, gap_x, frame.w)
    for i = 1, #items do
        local item = items[i]
        local c, r, col_span, row_span = grid.item_slot(item, #cols, #rows)
        local span_w = grid.span_total(col_sizes, c, col_span, gap_x)
        local m = measure_api.measure(item.node,
            measure_api.constraint(measure_api.exact(math_max(0, span_w)), measure_api.UNCONSTRAINED), measure_opts)
        grid.distribute_min(row_bases, r, row_span, gap_y, m.used_h)
    end
    local row_sizes = grid.track_sizes(rows, row_bases, gap_y, frame.h)

    local col_pos, row_pos = {}, {}
    local p = 0
    for i = 1, #cols do
        col_pos[i] = p
        p = p + col_sizes[i] + gap_x
    end
    p = 0
    for i = 1, #rows do
        row_pos[i] = p
        p = p + row_sizes[i] + gap_y
    end

    for i = 1, #items do
        local item = items[i]
        local c, r, col_span, row_span = grid.item_slot(item, #cols, #rows)
        placed[i] = {
            node = item.node,
            frame = mkframe(
                frame.x + col_pos[c],
                frame.y + row_pos[r],
                grid.span_total(col_sizes, c, col_span, gap_x),
                grid.span_total(row_sizes, r, row_span, gap_y)),
        }
    end

    return placed
end

return grid
