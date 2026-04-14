local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Layout = T.Layout

local M = {}

local HUGE = math.huge

local function finite(n)
    return n ~= nil and n < HUGE
end

local function max0(n)
    if n < 0 then return 0 end
    return n
end

local function round(n)
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

local function margin_px(v)
    local cls = pvm.classof(v)
    if v == Layout.MarginAuto then
        return 0
    end
    if cls == Layout.MarginPx then
        return v.px
    end
    return 0
end

local function apply_minmax(value, minv, maxv, parent_limit)
    local min_cls = pvm.classof(minv)
    local max_cls = pvm.classof(maxv)

    if min_cls == Layout.MinPx and value < minv.px then
        value = minv.px
    elseif min_cls == Layout.MinFrac and finite(parent_limit) then
        local floor_v = parent_limit * minv.value
        if value < floor_v then value = floor_v end
    end

    if max_cls == Layout.MaxPx and value > maxv.px then
        value = maxv.px
    elseif max_cls == Layout.MaxFrac and finite(parent_limit) then
        local ceil_v = parent_limit * maxv.value
        if value > ceil_v then value = ceil_v end
    end

    return value
end

local function resolve_track_size(track, available, remaining_fr, total_fr)
    local cls = pvm.classof(track)
    if track == Layout.TrackAuto then
        return 0
    end
    if cls == Layout.TrackFixed then
        return track.px
    end
    if cls == Layout.TrackMinMax then
        return track.min_px
    end
    if cls == Layout.TrackFr then
        if finite(available) and total_fr > 0 and remaining_fr > 0 then
            return remaining_fr * (track.fr / total_fr)
        end
        return 0
    end
    return 0
end

local function resolve_sizing(sizing, intrinsic, parent_limit)
    local cls = pvm.classof(sizing)
    if sizing == Layout.SAuto or sizing == Layout.SHug then
        return intrinsic
    end
    if sizing == Layout.SFill then
        if finite(parent_limit) then
            return parent_limit
        end
        return intrinsic
    end
    if cls == Layout.SFixed then
        return sizing.px
    end
    if cls == Layout.SFrac then
        if finite(parent_limit) then
            return parent_limit * sizing.value
        end
        return intrinsic
    end
    return intrinsic
end

local text_layout

text_layout = pvm.lower("ui.text_layout", function(style, constraint)
    local font_px = style.font_size
    local leading = style.leading > 0 and style.leading or font_px
    local tracking = style.tracking or 0
    local text = style.content
    local chars = #text

    if chars == 0 then
        return Layout.TextLayout(style, constraint.max_w, 0, leading, round(font_px * 0.8))
    end

    local advance = font_px * 0.6 + tracking
    if advance < 1 then advance = 1 end

    local raw_w = round(chars * advance)
    local lines = 1
    local measured_w = raw_w

    if finite(constraint.max_w) then
        local limit = max0(constraint.max_w)
        if limit <= 0 then
            lines = chars
            measured_w = 0
        else
            local chars_per_line = math.max(1, math.floor(limit / advance))
            lines = math.max(1, math.ceil(chars / chars_per_line))
            measured_w = math.min(raw_w, limit)
        end
    end

    return Layout.TextLayout(
        style,
        constraint.max_w,
        measured_w,
        lines * leading,
        round(font_px * 0.8)
    )
end)

local measure

local function leaf_intrinsic(node, constraint)
    local pad = node.box.padding
    local pad_h = pad.left + pad.right
    local pad_v = pad.top + pad.bottom
    local inner_w = finite(constraint.max_w) and max0(constraint.max_w - pad_h) or HUGE

    local content_w, content_h, baseline = 0, 0, 0
    if node.text ~= nil then
        local tl = text_layout(node.text, Layout.Constraint(inner_w, HUGE))
        content_w = tl.measured_w
        content_h = tl.measured_h
        baseline = tl.baseline + pad.top
    end

    return content_w + pad_h, content_h + pad_v, baseline
end

local function measure_leaf(node, constraint)
    local box = node.box
    local intrinsic_w, intrinsic_h, baseline = leaf_intrinsic(node, constraint)
    local w = resolve_sizing(box.w, intrinsic_w, constraint.max_w)
    local h = resolve_sizing(box.h, intrinsic_h, constraint.max_h)

    w = apply_minmax(w, box.min_w, box.max_w, constraint.max_w)
    h = apply_minmax(h, box.min_h, box.max_h, constraint.max_h)

    local margin = box.margin
    w = w + margin_px(margin.left) + margin_px(margin.right)
    h = h + margin_px(margin.top) + margin_px(margin.bottom)

    return Layout.Size(w, h, baseline)
end

local function measure_flex_nowrap(node, constraint)
    local box = node.box
    local pad = box.padding
    local inner_w = finite(constraint.max_w) and max0(constraint.max_w - pad.left - pad.right) or HUGE
    local inner_h = finite(constraint.max_h) and max0(constraint.max_h - pad.top - pad.bottom) or HUGE

    local children = node.children
    local axis = node.axis
    local main_total = 0
    local cross_max = 0
    local baseline = 0

    for i = 1, #children do
        local child_constraint
        if axis == Layout.LCol then
            child_constraint = Layout.Constraint(inner_w, HUGE)
        else
            child_constraint = Layout.Constraint(inner_w, inner_h)
        end
        local size = measure(children[i], child_constraint)
        if axis == Layout.LCol then
            main_total = main_total + size.h
            if size.w > cross_max then cross_max = size.w end
        else
            main_total = main_total + size.w
            if size.h > cross_max then cross_max = size.h end
            if size.baseline > baseline then baseline = size.baseline end
        end
    end

    local gap = axis == Layout.LCol and node.gap_y or node.gap_x
    if #children > 1 then
        main_total = main_total + (#children - 1) * gap
    end

    local intrinsic_w, intrinsic_h
    if axis == Layout.LCol then
        intrinsic_w = cross_max + pad.left + pad.right
        intrinsic_h = main_total + pad.top + pad.bottom
    else
        intrinsic_w = main_total + pad.left + pad.right
        intrinsic_h = cross_max + pad.top + pad.bottom
    end

    local w = resolve_sizing(box.w, intrinsic_w, constraint.max_w)
    local h = resolve_sizing(box.h, intrinsic_h, constraint.max_h)
    w = apply_minmax(w, box.min_w, box.max_w, constraint.max_w)
    h = apply_minmax(h, box.min_h, box.max_h, constraint.max_h)

    local margin = box.margin
    w = w + margin_px(margin.left) + margin_px(margin.right)
    h = h + margin_px(margin.top) + margin_px(margin.bottom)

    return Layout.Size(w, h, baseline)
end

local function measure_flex_wrap_row(node, constraint)
    local box = node.box
    local pad = box.padding
    local inner_w = finite(constraint.max_w) and max0(constraint.max_w - pad.left - pad.right) or HUGE
    local children = node.children
    local gap_x = node.gap_x
    local gap_y = node.gap_y

    local line_w = 0
    local line_h = 0
    local total_h = 0
    local max_w = 0

    for i = 1, #children do
        local size = measure(children[i], Layout.Constraint(inner_w, HUGE))
        local needed = size.w
        if line_w > 0 then
            needed = needed + gap_x
        end
        if finite(inner_w) and line_w > 0 and line_w + needed > inner_w then
            if line_w > max_w then max_w = line_w end
            total_h = total_h + line_h + gap_y
            line_w = size.w
            line_h = size.h
        else
            line_w = line_w + needed
            if size.h > line_h then line_h = size.h end
        end
    end

    if line_w > max_w then max_w = line_w end
    if #children > 0 then
        total_h = total_h + line_h
    end

    local intrinsic_w = max_w + pad.left + pad.right
    local intrinsic_h = total_h + pad.top + pad.bottom

    local w = resolve_sizing(box.w, intrinsic_w, constraint.max_w)
    local h = resolve_sizing(box.h, intrinsic_h, constraint.max_h)
    w = apply_minmax(w, box.min_w, box.max_w, constraint.max_w)
    h = apply_minmax(h, box.min_h, box.max_h, constraint.max_h)

    local margin = box.margin
    w = w + margin_px(margin.left) + margin_px(margin.right)
    h = h + margin_px(margin.top) + margin_px(margin.bottom)

    return Layout.Size(w, h, 0)
end

local function measure_flex_wrap_col(node, constraint)
    -- Initial symmetric approximation; proper column-wrap balancing comes later.
    return measure_flex_nowrap(node, constraint)
end

local function measure_flex(node, constraint)
    if node.wrap == Layout.LWrap then
        if node.axis == Layout.LRow then
            return measure_flex_wrap_row(node, constraint)
        end
        return measure_flex_wrap_col(node, constraint)
    end
    return measure_flex_nowrap(node, constraint)
end

local function resolve_grid_cols(node, available_w)
    local cols = node.cols
    local widths = {}
    local fixed_total = 0
    local fr_total = 0

    for i = 1, #cols do
        local track = cols[i]
        local cls = pvm.classof(track)
        if cls == Layout.TrackFixed then
            widths[i] = track.px
            fixed_total = fixed_total + track.px
        elseif cls == Layout.TrackMinMax then
            widths[i] = track.min_px
            fixed_total = fixed_total + track.min_px
        elseif cls == Layout.TrackFr then
            widths[i] = 0
            fr_total = fr_total + track.fr
        else
            widths[i] = 0
        end
    end

    local gaps = (#cols > 1) and ((#cols - 1) * node.col_gap) or 0
    local remaining = finite(available_w) and math.max(0, available_w - fixed_total - gaps) or 0

    for i = 1, #cols do
        local track = cols[i]
        if pvm.classof(track) == Layout.TrackFr then
            widths[i] = resolve_track_size(track, available_w, remaining, fr_total)
        end
    end

    return widths
end

local function span_size(sizes, start_i, span, gap)
    local total = 0
    for i = start_i, math.min(#sizes, start_i + span - 1) do
        total = total + sizes[i]
    end
    if span > 1 then
        total = total + (span - 1) * gap
    end
    return total
end

local function measure_grid(node, constraint)
    local box = node.box
    local pad = box.padding
    local inner_w = finite(constraint.max_w) and max0(constraint.max_w - pad.left - pad.right) or HUGE

    local col_widths = resolve_grid_cols(node, inner_w)
    local row_heights = {}

    for i = 1, #node.items do
        local item = node.items[i]
        local item_w = span_size(col_widths, item.col_start, item.col_span, node.col_gap)
        local size = measure(item.node, Layout.Constraint(item_w > 0 and item_w or inner_w, HUGE))
        local row = item.row_start
        local prev = row_heights[row] or 0
        if size.h > prev then row_heights[row] = size.h end
    end

    local total_cols = 0
    for i = 1, #col_widths do total_cols = total_cols + col_widths[i] end
    local total_rows = 0
    for i = 1, #row_heights do total_rows = total_rows + (row_heights[i] or 0) end

    if #col_widths > 1 then total_cols = total_cols + (#col_widths - 1) * node.col_gap end
    if #row_heights > 1 then total_rows = total_rows + (#row_heights - 1) * node.row_gap end

    local intrinsic_w = total_cols + pad.left + pad.right
    local intrinsic_h = total_rows + pad.top + pad.bottom

    local w = resolve_sizing(box.w, intrinsic_w, constraint.max_w)
    local h = resolve_sizing(box.h, intrinsic_h, constraint.max_h)
    w = apply_minmax(w, box.min_w, box.max_w, constraint.max_w)
    h = apply_minmax(h, box.min_h, box.max_h, constraint.max_h)

    local margin = box.margin
    w = w + margin_px(margin.left) + margin_px(margin.right)
    h = h + margin_px(margin.top) + margin_px(margin.bottom)

    return Layout.Size(w, h, 0)
end

measure = pvm.lower("ui.measure", function(node, constraint)
    local cls = pvm.classof(node)
    if cls == Layout.Leaf then
        return measure_leaf(node, constraint)
    end
    if cls == Layout.Flex then
        return measure_flex(node, constraint)
    end
    if cls == Layout.Grid then
        return measure_grid(node, constraint)
    end
    error("ui.measure: unsupported layout node", 2)
end)

M.measure = measure
M.text_layout = text_layout
M.T = T

return M
