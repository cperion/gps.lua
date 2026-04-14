-- ui/measure.lua
--
-- Concrete UI measurement reducer.
--
-- This module measures lowered `UI.Node` trees into typed `Facts.Measure` values.
-- It stays reducer-based and explicit: callers may provide a cache and text
-- measurement hook, but there is no hidden retained layout graph.

local pvm = require("pvm")
local classof = pvm.classof
local schema = require("ui.asdl")
local flex = require("ui._flex")
local grid = require("ui._grid")

local T = schema.T

local measure = { T = T, schema = schema }

local math_floor = math.floor
local math_huge = math.huge
local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local type = type

local INF = math_huge

local SPAN_UNCONSTRAINED = T.Facts.SpanUnconstrained
local SpanExact = T.Facts.SpanExact
local SpanAtMost = T.Facts.SpanAtMost
local BaselinePx = T.Facts.BaselinePx
local BASELINE_NONE = T.Facts.NoBaseline
local Constraint = T.Facts.Constraint
local Frame = T.Facts.Frame
local Intrinsic = T.Facts.Intrinsic
local Measure = T.Facts.Measure

local SIZE_AUTO = T.Layout.SizeAuto
local SIZE_CONTENT = T.Layout.SizeContent
local NO_MIN = T.Layout.NoMin
local NO_MAX = T.Layout.NoMax
local WRAP_NO = T.Layout.WrapNoWrap
local AXIS_ROW = T.Layout.AxisRow
local AXIS_ROW_REV = T.Layout.AxisRowReverse
local SCROLL_X = T.Layout.ScrollX
local SCROLL_Y = T.Layout.ScrollY
local SCROLL_BOTH = T.Layout.ScrollBoth
local LINEHEIGHT_AUTO = T.Layout.LineHeightAuto
local TEXT_NOWRAP = T.Layout.TextNoWrap
local TEXT_WORDWRAP = T.Layout.TextWordWrap
local TEXT_CHARWRAP = T.Layout.TextCharWrap
local UNLIMITED_LINES = T.Layout.UnlimitedLines

local mtSpanExact = classof(SpanExact(0))
local mtSpanAtMost = classof(SpanAtMost(0))
local mtSizePx = classof(T.Layout.SizePx(0))
local mtSizePercent = classof(T.Layout.SizePercent(0))
local mtMinPx = classof(T.Layout.MinPx(0))
local mtLineHeightPx = classof(T.Layout.LineHeightPx(0))
local mtLineHeightScale = classof(T.Layout.LineHeightScale(1))
local mtMaxLines = classof(T.Layout.MaxLines(1))

local function clamp(v, lo, hi)
    if lo and v < lo then
        v = lo
    end
    if hi and v > hi then
        v = hi
    end
    return v
end

local function max_of(a, b)
    return (a > b) and a or b
end

local function span_available(span)
    if span == SPAN_UNCONSTRAINED then
        return INF, false
    end
    local mt = classof(span)
    if mt == mtSpanExact then
        return span.px, true
    end
    if mt == mtSpanAtMost then
        return span.px, false
    end
    return INF, false
end

local function span_key(span)
    if span == SPAN_UNCONSTRAINED then
        return "U"
    end
    local mt = classof(span)
    if mt == mtSpanExact then
        return "E" .. span.px
    end
    if mt == mtSpanAtMost then
        return "A" .. span.px
    end
    return tostring(span)
end

local function constraint_key(constraint)
    return span_key(constraint.w) .. ":" .. span_key(constraint.h)
end

local function sub_span(span, delta)
    if delta <= 0 then
        return span
    end
    if span == SPAN_UNCONSTRAINED then
        return span
    end
    local px = math_max(0, span.px - delta)
    if classof(span) == mtSpanExact then
        return SpanExact(px)
    end
    return SpanAtMost(px)
end

local function box_min_value(minv)
    if minv == NO_MIN then
        return 0
    end
    return minv.px
end

local function box_max_value(maxv)
    if maxv == NO_MAX then
        return INF
    end
    return maxv.px
end

local function resolve_size_value(spec, available, content_value)
    if spec == SIZE_AUTO or spec == SIZE_CONTENT then
        return content_value
    end
    local mt = classof(spec)
    if mt == mtSizePx then
        return spec.px
    end
    if mt == mtSizePercent then
        if available ~= INF then
            return available * spec.ratio
        end
        return content_value
    end
    return content_value
end


local function exact_or_atmost(px, exact)
    if px == INF then
        return SPAN_UNCONSTRAINED
    end
    if exact then
        return SpanExact(px)
    end
    return SpanAtMost(px)
end

local function box_content_constraint(box, outer)
    local aw = span_available(outer.w)
    local ah = span_available(outer.h)
    local avail_w, exact_w = aw, false
    local avail_h, exact_h = ah, false

    local mtw = classof(box.w)
    if mtw == mtSizePx then
        avail_w, exact_w = box.w.px, true
    elseif mtw == mtSizePercent and avail_w ~= INF then
        avail_w, exact_w = avail_w * box.w.ratio, true
    end

    local mth = classof(box.h)
    if mth == mtSizePx then
        avail_h, exact_h = box.h.px, true
    elseif mth == mtSizePercent and avail_h ~= INF then
        avail_h, exact_h = avail_h * box.h.ratio, true
    end

    return Constraint(exact_or_atmost(avail_w, exact_w), exact_or_atmost(avail_h, exact_h))
end

local function make_baseline(px)
    if not px then
        return BASELINE_NONE
    end
    return BaselinePx(px)
end

local function apply_box_measure(box, outer, raw)
    local aw, outer_exact_w = span_available(outer.w)
    local ah, outer_exact_h = span_available(outer.h)
    local min_w, min_h = box_min_value(box.min_w), box_min_value(box.min_h)
    local max_w, max_h = box_max_value(box.max_w), box_max_value(box.max_h)

    local used_w = outer_exact_w
        and (box.w == SIZE_AUTO or box.w == SIZE_CONTENT)
        and aw or resolve_size_value(box.w, aw, raw.used_w)
    local used_h = outer_exact_h
        and (box.h == SIZE_AUTO or box.h == SIZE_CONTENT)
        and ah or resolve_size_value(box.h, ah, raw.used_h)

    local intr_min_w, intr_min_h = raw.min_w, raw.min_h
    local intr_max_w, intr_max_h = raw.max_w, raw.max_h

    local mtw = classof(box.w)
    if mtw == mtSizePx then
        intr_min_w, intr_max_w = box.w.px, box.w.px
    elseif mtw == mtSizePercent then
        intr_max_w = INF
    end

    local mth = classof(box.h)
    if mth == mtSizePx then
        intr_min_h, intr_max_h = box.h.px, box.h.px
    elseif mth == mtSizePercent then
        intr_max_h = INF
    end

    intr_min_w = clamp(intr_min_w, min_w, max_w)
    intr_min_h = clamp(intr_min_h, min_h, max_h)
    intr_max_w = clamp(intr_max_w, min_w, max_w)
    intr_max_h = clamp(intr_max_h, min_h, max_h)
    used_w = clamp(used_w, min_w, max_w)
    used_h = clamp(used_h, min_h, max_h)

    if aw ~= INF then
        used_w = math_min(used_w, aw)
    end
    if ah ~= INF then
        used_h = math_min(used_h, ah)
    end

    return Measure(
        outer,
        Intrinsic(intr_min_w, intr_min_h, intr_max_w, intr_max_h, raw.baseline or BASELINE_NONE),
        used_w,
        used_h,
        raw.baseline or BASELINE_NONE)
end

local function raw_measure_zero()
    return {
        min_w = 0,
        min_h = 0,
        max_w = 0,
        max_h = 0,
        used_w = 0,
        used_h = 0,
        baseline = BASELINE_NONE,
    }
end

local function raw_from_child_measure(child)
    return {
        min_w = child.intrinsic.min_w,
        min_h = child.intrinsic.min_h,
        max_w = child.intrinsic.max_w,
        max_h = child.intrinsic.max_h,
        used_w = child.used_w,
        used_h = child.used_h,
        baseline = child.baseline,
    }
end

local function is_row_axis(axis)
    return axis == AXIS_ROW or axis == AXIS_ROW_REV
end

local function style_insets(style)
    local h = (style.pad_h or 0) + (style.border_w or 0)
    local v = (style.pad_v or 0) + (style.border_w or 0)
    return h, v
end

local function default_font_height(font_id)
    return 16
end

local function resolve_line_height(line_height, font_id, opts)
    local base = (opts and opts.font_height and opts.font_height(font_id)) or default_font_height(font_id)
    local mt = classof(line_height)
    if line_height == LINEHEIGHT_AUTO then
        return base
    end
    if mt == mtLineHeightPx then
        return line_height.px
    end
    if mt == mtLineHeightScale then
        return base * line_height.scale
    end
    return base
end

local function text_word_min_width(char_w, text)
    local best = 0
    local current = 0
    for i = 1, #text do
        local byte = text:byte(i)
        if byte == 32 or byte == 9 or byte == 10 then
            if current > best then
                best = current
            end
            current = 0
        else
            current = current + char_w
        end
    end
    if current > best then
        best = current
    end
    return best
end

local function split_text_lines(text)
    local out = {}
    local start = 1
    while true do
        local i = text:find("\n", start, true)
        if not i then
            out[#out + 1] = text:sub(start)
            break
        end
        out[#out + 1] = text:sub(start, i - 1)
        start = i + 1
    end
    if #out == 0 then
        out[1] = ""
    end
    return out
end

local function default_text_measure(style, text, max_w, max_h, node, opts)
    local line_h = resolve_line_height(style.line_height, style.font_id, opts)
    local char_w = math_max(4, math_floor(line_h * 0.5 + 0.5))
    local lines_src = split_text_lines(text or "")

    local raw_w = 0
    local min_w = 0
    local explicit_lines = #lines_src
    local wrapped_lines = 0

    for i = 1, explicit_lines do
        local line = lines_src[i]
        local line_w = #line * char_w
        if line_w > raw_w then
            raw_w = line_w
        end

        local line_min_w
        if style.wrap == TEXT_NOWRAP then
            line_min_w = line_w
        elseif style.wrap == TEXT_WORDWRAP then
            line_min_w = text_word_min_width(char_w, line)
        else
            line_min_w = (#line > 0) and char_w or 0
        end
        if line_min_w > min_w then
            min_w = line_min_w
        end

        local line_count = 1
        if style.wrap ~= TEXT_NOWRAP and max_w ~= INF and max_w > 0 then
            line_count = math_max(1, math_ceil(line_w / max_w))
        end
        wrapped_lines = wrapped_lines + line_count
    end

    local limit_mt = classof(style.line_limit)
    if limit_mt == mtMaxLines then
        wrapped_lines = math_min(wrapped_lines, style.line_limit.count)
    end

    local used_w = raw_w
    if style.wrap ~= TEXT_NOWRAP and max_w ~= INF and max_w > 0 then
        used_w = math_min(raw_w, max_w)
    end

    local used_h = wrapped_lines * line_h
    if max_h ~= INF then
        used_h = math_min(used_h, max_h)
    end

    return {
        min_w = min_w,
        min_h = explicit_lines * line_h,
        max_w = raw_w,
        max_h = explicit_lines * line_h,
        used_w = used_w,
        used_h = used_h,
        baseline = math_floor(line_h * 0.8 + 0.5),
    }
end

local function passthrough_measure(measure_node, box, child, constraint)
    local inner = box_content_constraint(box, constraint)
    local m = measure_node(child, inner)
    return apply_box_measure(box, constraint, raw_from_child_measure(m))
end

local function panel_like_measure(measure_node, box, style, child, constraint)
    local inner = box_content_constraint(box, constraint)
    local inset_h, inset_v = style_insets(style)
    inner = Constraint(sub_span(inner.w, inset_h * 2), sub_span(inner.h, inset_v * 2))
    local m = measure_node(child, inner)
    local raw = {
        min_w = m.intrinsic.min_w + inset_h * 2,
        min_h = m.intrinsic.min_h + inset_v * 2,
        max_w = m.intrinsic.max_w + inset_h * 2,
        max_h = m.intrinsic.max_h + inset_v * 2,
        used_w = m.used_w + inset_h * 2,
        used_h = m.used_h + inset_v * 2,
        baseline = m.baseline,
    }
    return apply_box_measure(box, constraint, raw)
end

local function scroll_area_measure(measure_node, axis, box, style, child, constraint)
    local inner = box_content_constraint(box, constraint)
    local inset_h, inset_v = style_insets(style)
    local child_w = sub_span(inner.w, inset_h * 2)
    local child_h = sub_span(inner.h, inset_v * 2)

    if axis == SCROLL_X or axis == SCROLL_BOTH then
        child_w = SPAN_UNCONSTRAINED
    end
    if axis == SCROLL_Y or axis == SCROLL_BOTH then
        child_h = SPAN_UNCONSTRAINED
    end

    local m = measure_node(child, Constraint(child_w, child_h))
    local raw = {
        min_w = ((axis == SCROLL_X or axis == SCROLL_BOTH) and 0 or m.intrinsic.min_w) + inset_h * 2,
        min_h = ((axis == SCROLL_Y or axis == SCROLL_BOTH) and 0 or m.intrinsic.min_h) + inset_v * 2,
        max_w = ((axis == SCROLL_X or axis == SCROLL_BOTH) and INF or m.intrinsic.max_w) + inset_h * 2,
        max_h = ((axis == SCROLL_Y or axis == SCROLL_BOTH) and INF or m.intrinsic.max_h) + inset_v * 2,
        used_w = m.used_w + inset_h * 2,
        used_h = m.used_h + inset_v * 2,
        baseline = m.baseline,
    }
    return apply_box_measure(box, constraint, raw)
end

local function grid_measure(node, constraint, measure_node)
    local inner = box_content_constraint(node.box, constraint)
    local raw = raw_measure_zero()
    local cols = node.cols
    local rows = node.rows
    local items = node.children
    if #cols == 0 or #rows == 0 or #items == 0 then
        return apply_box_measure(node.box, constraint, raw)
    end

    local col_bases = grid.track_bases(cols)
    local row_bases = grid.track_bases(rows)
    local gap_x = node.gap_x or 0
    local gap_y = node.gap_y or 0
    local any_inf_w, any_inf_h = false, false

    for i = 1, #items do
        local item = items[i]
        local m = measure_node(item.node, Constraint(SPAN_UNCONSTRAINED, SPAN_UNCONSTRAINED))
        local c, r, col_span, row_span = grid.item_slot(item, #cols, #rows)
        grid.distribute_min(col_bases, c, col_span, gap_x, m.intrinsic.min_w)
        grid.distribute_min(row_bases, r, row_span, gap_y, m.intrinsic.min_h)
        if m.intrinsic.max_w == INF then any_inf_w = true end
        if m.intrinsic.max_h == INF then any_inf_h = true end
    end

    local avail_w = span_available(inner.w)
    local col_sizes, total_w = grid.track_sizes(cols, col_bases, gap_x, avail_w)

    for i = 1, #items do
        local item = items[i]
        local c, r, col_span, row_span = grid.item_slot(item, #cols, #rows)
        local span_w = grid.span_total(col_sizes, c, col_span, gap_x)
        local m = measure_node(item.node, Constraint(SpanExact(math_max(0, span_w)), SPAN_UNCONSTRAINED))
        grid.distribute_min(row_bases, r, row_span, gap_y, m.used_h)
        if m.intrinsic.max_h == INF then any_inf_h = true end
    end

    local avail_h = span_available(inner.h)
    local row_sizes, total_h = grid.track_sizes(rows, row_bases, gap_y, avail_h)

    raw.min_w = gap_x * math_max(0, #cols - 1)
    raw.min_h = gap_y * math_max(0, #rows - 1)
    for i = 1, #cols do raw.min_w = raw.min_w + (col_bases[i] or 0) end
    for i = 1, #rows do raw.min_h = raw.min_h + (row_bases[i] or 0) end
    raw.max_w = any_inf_w and INF or total_w
    raw.max_h = any_inf_h and INF or total_h
    raw.used_w = total_w
    raw.used_h = total_h

    return apply_box_measure(node.box, constraint, raw)
end

local function flex_measure(measure_node, node, constraint)
    local inner = box_content_constraint(node.box, constraint)
    local infos, avail_main = flex.collect_infos(node, inner, measure_node)
    local axis = node.axis
    local rowish = flex.is_row_axis(axis)
    local cross_size = flex.span_available(rowish and inner.h or inner.w)
    local raw = raw_measure_zero()

    if #infos == 0 then
        return apply_box_measure(node.box, constraint, raw)
    end

    local sum_min_main = node.gap_main * math_max(0, #infos - 1)
    local sum_hypo_main = node.gap_main * math_max(0, #infos - 1)
    local min_line_main = 0
    local cross_min_single = 0

    for i = 1, #infos do
        local inf = infos[i]
        local outer_min = inf.min_main + inf.main_margin_start + inf.main_margin_end
        local outer_hypo = inf.hypo_main + inf.main_margin_start + inf.main_margin_end
        sum_min_main = sum_min_main + outer_min
        sum_hypo_main = sum_hypo_main + outer_hypo
        min_line_main = max_of(min_line_main, outer_hypo)
        cross_min_single = max_of(cross_min_single, inf.min_cross + inf.cross_margin_start + inf.cross_margin_end)
    end

    local lines = flex.collect_lines(infos, node.wrap, avail_main, node.gap_main)
    local used_cross = 0
    local max_line_main = 0
    local single_cross = 0

    for li = 1, #lines do
        local line = lines[li]
        local sizes = flex.resolve_line_main_sizes(infos, line, avail_main, node.gap_main)
        local line_main = flex.line_used_main(infos, line, sizes, node.gap_main)
        local line_cross = 0

        for j = 1, #line do
            local idx = line[j]
            local inf = infos[idx]
            local slot_main = sizes[idx]
            local ccon = rowish
                and Constraint(SpanExact(math_max(0, slot_main)), flex.exact_or_atmost(cross_size, false))
                or Constraint(flex.exact_or_atmost(cross_size, false), SpanExact(math_max(0, slot_main)))
            local m = measure_node(inf.item.node, ccon)
            local actual_cross = flex.cross_size_of(m, axis)
            line_cross = max_of(line_cross, actual_cross + inf.cross_margin_start + inf.cross_margin_end)
        end

        max_line_main = max_of(max_line_main, line_main)
        used_cross = used_cross + line_cross
        if li > 1 then
            used_cross = used_cross + node.gap_cross
        end
        if li == 1 then
            single_cross = line_cross
        end
    end

    if node.wrap == WRAP_NO or avail_main == INF then
        if rowish then
            raw.min_w, raw.max_w, raw.used_w = sum_min_main, sum_hypo_main, max_line_main
            raw.min_h, raw.max_h, raw.used_h = cross_min_single, single_cross, single_cross
        else
            raw.min_w, raw.max_w, raw.used_w = cross_min_single, single_cross, single_cross
            raw.min_h, raw.max_h, raw.used_h = sum_min_main, sum_hypo_main, max_line_main
        end
    else
        if rowish then
            raw.min_w, raw.max_w, raw.used_w = min_line_main, max_line_main, max_line_main
            raw.min_h, raw.max_h, raw.used_h = used_cross, used_cross, used_cross
        else
            raw.min_w, raw.max_w, raw.used_w = used_cross, used_cross, used_cross
            raw.min_h, raw.max_h, raw.used_h = min_line_main, max_line_main, max_line_main
        end
    end

    return apply_box_measure(node.box, constraint, raw)
end

function measure.exact(px)
    return SpanExact(px)
end

function measure.at_most(px)
    return SpanAtMost(px)
end

measure.UNCONSTRAINED = SPAN_UNCONSTRAINED
measure.NO_BASELINE = BASELINE_NONE
measure.INF = INF

function measure.constraint(w, h)
    return Constraint(w or SPAN_UNCONSTRAINED, h or SPAN_UNCONSTRAINED)
end

function measure.frame(x, y, w, h)
    return Frame(x, y, w, h)
end

function measure.available_constraint_from_frame(frame)
    return Constraint(SpanAtMost(frame.w), SpanAtMost(frame.h))
end

function measure.exact_constraint_from_frame(frame)
    return Constraint(SpanExact(frame.w), SpanExact(frame.h))
end

function measure.measure(node, constraint, opts)
    opts = opts or {}
    local text_measure = opts.text_measure or default_text_measure
    local stats = opts.stats

    local measure_uncached

    local function measure_node(cur, c)
        if stats then
            stats.calls = (stats.calls or 0) + 1
        end
        return measure_uncached(cur, c or Constraint(SPAN_UNCONSTRAINED, SPAN_UNCONSTRAINED))
    end

    measure_uncached = function(cur, c)
        local kind = cur.kind
        if kind == "Empty" then
            return Measure(c, Intrinsic(0, 0, 0, 0, BASELINE_NONE), 0, 0, BASELINE_NONE)
        elseif kind == "Interact" then
            return measure_node(cur.child, c)
        elseif kind == "Flex" then
            return flex_measure(measure_node, cur, c)
        elseif kind == "Grid" then
            return grid_measure(cur, c, measure_node)
        elseif kind == "Pad" then
            local inner = box_content_constraint(cur.box, c)
            inner = Constraint(sub_span(inner.w, cur.insets.l + cur.insets.r), sub_span(inner.h, cur.insets.t + cur.insets.b))
            local child = measure_node(cur.child, inner)
            local raw = {
                min_w = child.intrinsic.min_w + cur.insets.l + cur.insets.r,
                min_h = child.intrinsic.min_h + cur.insets.t + cur.insets.b,
                max_w = child.intrinsic.max_w + cur.insets.l + cur.insets.r,
                max_h = child.intrinsic.max_h + cur.insets.t + cur.insets.b,
                used_w = child.used_w + cur.insets.l + cur.insets.r,
                used_h = child.used_h + cur.insets.t + cur.insets.b,
                baseline = child.baseline,
            }
            return apply_box_measure(cur.box, c, raw)
        elseif kind == "Stack" then
            local inner = box_content_constraint(cur.box, c)
            local raw = raw_measure_zero()
            for i = 1, #cur.children do
                local m = measure_node(cur.children[i], inner)
                raw.min_w = max_of(raw.min_w, m.intrinsic.min_w)
                raw.min_h = max_of(raw.min_h, m.intrinsic.min_h)
                raw.max_w = max_of(raw.max_w, m.intrinsic.max_w)
                raw.max_h = max_of(raw.max_h, m.intrinsic.max_h)
                raw.used_w = max_of(raw.used_w, m.used_w)
                raw.used_h = max_of(raw.used_h, m.used_h)
            end
            return apply_box_measure(cur.box, c, raw)
        elseif kind == "Clip" or kind == "Transform" then
            return passthrough_measure(measure_node, cur.box, cur.child, c)
        elseif kind == "ScrollArea" then
            return scroll_area_measure(measure_node, cur.axis, cur.box, cur.style, cur.child, c)
        elseif kind == "Panel" then
            return panel_like_measure(measure_node, cur.box, cur.style, cur.child, c)
        elseif kind == "Rect" then
            return apply_box_measure(cur.box, c, raw_measure_zero())
        elseif kind == "Text" then
            local inner = box_content_constraint(cur.box, c)
            local max_w = span_available(inner.w)
            local max_h = span_available(inner.h)
            local raw = text_measure(cur.style, cur.text or "", max_w, max_h, cur, opts)
            raw.baseline = make_baseline(raw.baseline)
            return apply_box_measure(cur.box, c, raw)
        elseif kind == "RuntimeText" then
            return apply_box_measure(cur.box, c, raw_measure_zero())
        elseif kind == "CustomPaint" then
            return apply_box_measure(cur.box, c, raw_measure_zero())
        elseif kind == "Overlay" then
            return measure_node(cur.base, c)
        elseif kind == "Spacer" then
            return apply_box_measure(cur.box, c, raw_measure_zero())
        end
        error("ui.measure: unsupported UI node kind " .. tostring(kind), 2)
    end

    return measure_node(node, constraint or Constraint(SPAN_UNCONSTRAINED, SPAN_UNCONSTRAINED))
end

-- Direct ASDL methods.
-- `T.UI.Node` is a sum parent, so ordinary assignment propagates these methods
-- to all concrete node classes via asdl_context.lua.
function T.UI.Node:measure(constraint, opts)
    return measure.measure(self, constraint, opts)
end

function T.UI.Node:measure_in_frame(frame, opts)
    return measure.measure(self, measure.exact_constraint_from_frame(frame), opts)
end

return measure
