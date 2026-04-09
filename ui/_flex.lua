-- ui/_flex.lua
--
-- Shared internal flex kernel.
--
-- This module is intentionally private to the UI implementation. It owns the
-- common flex helpers used by draw/hit runtime placement and flex measurement,
-- so those reducers do not drift. The current goal is one shared, explicit,
-- CSS-inspired flex core, not full browser-flexbox completeness.

local schema = require("ui.asdl")

local T = schema.T

local flex = { T = T, schema = schema }

local math_abs = math.abs
local math_huge = math.huge
local math_max = math.max
local getmetatable = getmetatable

local INF = math_huge

local SpanExact = T.Facts.SpanExact
local SpanAtMost = T.Facts.SpanAtMost
local SPAN_UNCONSTRAINED = T.Facts.SpanUnconstrained
local BASELINE_NONE = T.Facts.NoBaseline

local SIZE_AUTO = T.Layout.SizeAuto
local SIZE_CONTENT = T.Layout.SizeContent
local BASIS_AUTO = T.Layout.BasisAuto
local BASIS_CONTENT = T.Layout.BasisContent
local NO_MAX = T.Layout.NoMax

local AXIS_ROW = T.Layout.AxisRow
local AXIS_ROW_REV = T.Layout.AxisRowReverse
local AXIS_COL = T.Layout.AxisCol
local AXIS_COL_REV = T.Layout.AxisColReverse

local WRAP_NO = T.Layout.WrapNoWrap
local WRAP_WRAP_REV = T.Layout.WrapWrapReverse

local MAIN_END = T.Layout.MainEnd
local MAIN_CENTER = T.Layout.MainCenter
local MAIN_SPACE_BETWEEN = T.Layout.MainSpaceBetween
local MAIN_SPACE_AROUND = T.Layout.MainSpaceAround
local MAIN_SPACE_EVENLY = T.Layout.MainSpaceEvenly

local CROSS_AUTO = T.Layout.CrossAuto
local CROSS_START = T.Layout.CrossStart
local CROSS_END = T.Layout.CrossEnd
local CROSS_CENTER = T.Layout.CrossCenter
local CROSS_STRETCH = T.Layout.CrossStretch
local CROSS_BASELINE = T.Layout.CrossBaseline

local CONTENT_END = T.Layout.ContentEnd
local CONTENT_CENTER = T.Layout.ContentCenter
local CONTENT_STRETCH = T.Layout.ContentStretch
local CONTENT_SPACE_BETWEEN = T.Layout.ContentSpaceBetween
local CONTENT_SPACE_AROUND = T.Layout.ContentSpaceAround
local CONTENT_SPACE_EVENLY = T.Layout.ContentSpaceEvenly

local mtSpanExact = getmetatable(SpanExact(0))
local mtSpanAtMost = getmetatable(SpanAtMost(0))
local mtSizePx = getmetatable(T.Layout.SizePx(0))
local mtSizePercent = getmetatable(T.Layout.SizePercent(0))
local mtBasisPx = getmetatable(T.Layout.BasisPx(0))
local mtBasisPercent = getmetatable(T.Layout.BasisPercent(0))
local mtMaxPx = getmetatable(T.Layout.MaxPx(0))

local EPS = 1e-6

local function clamp(v, lo, hi)
    if lo and v < lo then
        v = lo
    end
    if hi and v > hi then
        v = hi
    end
    return v
end

local function mkframe(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

local function is_row_axis(axis)
    return axis == AXIS_ROW or axis == AXIS_ROW_REV
end

local function is_reverse_axis(axis)
    return axis == AXIS_ROW_REV or axis == AXIS_COL_REV
end

local function is_wrap_reverse(wrap)
    return wrap == WRAP_WRAP_REV
end

local function ensure_measure_api(measure_api)
    return measure_api or require("ui.measure")
end

local function span_available(span)
    if span == SPAN_UNCONSTRAINED then
        return INF, false
    end
    local mt = getmetatable(span)
    if mt == mtSpanExact then
        return span.px, true
    end
    if mt == mtSpanAtMost then
        return span.px, false
    end
    return INF, false
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

local function baseline_num(baseline)
    if baseline == BASELINE_NONE or baseline == nil then
        return nil
    end
    return baseline.px
end

local function resolve_local_frame(node, outer, measure_opts, measure_api)
    measure_api = ensure_measure_api(measure_api)
    local m = measure_api.measure(node, measure_api.exact_constraint_from_frame(outer), measure_opts)
    return mkframe(outer.x, outer.y, m.used_w, m.used_h), m
end

local function main_margins(margin, axis)
    if axis == AXIS_ROW then
        return margin.l, margin.r
    end
    if axis == AXIS_ROW_REV then
        return margin.r, margin.l
    end
    if axis == AXIS_COL then
        return margin.t, margin.b
    end
    return margin.b, margin.t
end

local function cross_margins(margin, axis)
    if axis == AXIS_ROW or axis == AXIS_ROW_REV then
        return margin.t, margin.b
    end
    return margin.l, margin.r
end

local function main_size_of(m, axis)
    return is_row_axis(axis) and m.used_w or m.used_h
end

local function cross_size_of(m, axis)
    return is_row_axis(axis) and m.used_h or m.used_w
end

local function intrinsic_min_main(intr, axis)
    return is_row_axis(axis) and intr.min_w or intr.min_h
end

local function intrinsic_max_main(intr, axis)
    return is_row_axis(axis) and intr.max_w or intr.max_h
end

local function intrinsic_min_cross(intr, axis)
    return is_row_axis(axis) and intr.min_h or intr.min_w
end

local function intrinsic_max_cross(intr, axis)
    return is_row_axis(axis) and intr.max_h or intr.max_w
end

local function node_box(node)
    while node do
        local kind = node.kind
        if kind == "Key" or kind == "HitBox" or kind == "Pressable" or kind == "Focusable" then
            node = node.child
        elseif kind == "Overlay" then
            node = node.base
        elseif kind == "Flex" or kind == "Pad" or kind == "Stack" or kind == "Clip"
            or kind == "Transform" or kind == "Sized" or kind == "ScrollArea"
            or kind == "Panel" or kind == "Rect" or kind == "Text"
            or kind == "CustomPaint" or kind == "Spacer" then
            return node.box
        else
            return nil
        end
    end
    return nil
end

local function resolve_auto_basis(item_node, axis, available, content_value)
    local box = node_box(item_node)
    if not box then
        return content_value
    end
    local spec = is_row_axis(axis) and box.w or box.h
    if spec == SIZE_AUTO or spec == SIZE_CONTENT then
        return content_value
    end
    local mt = getmetatable(spec)
    if mt == mtSizePx then
        return spec.px
    end
    if mt == mtSizePercent and available ~= INF then
        return available * spec.ratio
    end
    return content_value
end

local function cross_size_is_auto(item_node, axis)
    local box = node_box(item_node)
    if not box then
        return true
    end
    local spec = is_row_axis(axis) and box.h or box.w
    return spec == SIZE_AUTO
end

local function explicit_max_main(item_node, axis)
    local box = node_box(item_node)
    if not box then
        return INF
    end
    local spec = is_row_axis(axis) and box.max_w or box.max_h
    if spec == NO_MAX then
        return INF
    end
    if getmetatable(spec) == mtMaxPx then
        return spec.px
    end
    return INF
end

local function resolve_basis_value(spec, item_node, axis, available, content_value)
    if spec == BASIS_AUTO then
        return resolve_auto_basis(item_node, axis, available, content_value)
    end
    if spec == BASIS_CONTENT then
        return content_value
    end
    local mt = getmetatable(spec)
    if mt == mtBasisPx then
        return spec.px
    end
    if mt == mtBasisPercent then
        if available ~= INF then
            return available * spec.ratio
        end
        return content_value
    end
    return content_value
end

local function flex_collect_infos(node, constraint, measure_node)
    local axis = node.axis
    local avail_w = span_available(constraint.w)
    local avail_h = span_available(constraint.h)
    local avail_main = is_row_axis(axis) and avail_w or avail_h
    local infos = {}

    for i = 1, #node.children do
        local item = node.children[i]
        local m = measure_node(item.node, constraint)
        local ml, mr = main_margins(item.margin, axis)
        local mt, mb = cross_margins(item.margin, axis)
        local min_main = intrinsic_min_main(m.intrinsic, axis)
        local max_main = explicit_max_main(item.node, axis)
        local base = resolve_basis_value(item.basis, item.node, axis, avail_main, main_size_of(m, axis))
        infos[i] = {
            item = item,
            measure = m,
            base = base,
            hypo_main = clamp(base, min_main, max_main),
            min_main = min_main,
            max_main = max_main,
            min_cross = intrinsic_min_cross(m.intrinsic, axis),
            max_cross = intrinsic_max_cross(m.intrinsic, axis),
            main_margin_start = ml,
            main_margin_end = mr,
            cross_margin_start = mt,
            cross_margin_end = mb,
            cross_auto = cross_size_is_auto(item.node, axis),
        }
    end

    return infos, avail_main
end

local function collect_lines(infos, wrap, avail_main, gap_main)
    local lines = {}

    if wrap == WRAP_NO or avail_main == INF then
        lines[1] = {}
        for i = 1, #infos do
            lines[1][i] = i
        end
        return lines
    end

    local cur = {}
    local cur_used = 0
    for i = 1, #infos do
        local inf = infos[i]
        local need = inf.hypo_main + inf.main_margin_start + inf.main_margin_end
        if #cur > 0 then
            need = need + gap_main
        end
        if #cur > 0 and cur_used + need > avail_main then
            lines[#lines + 1] = cur
            cur = {}
            cur_used = 0
            need = inf.hypo_main + inf.main_margin_start + inf.main_margin_end
        end
        cur[#cur + 1] = i
        cur_used = cur_used + need
    end
    if #cur > 0 then
        lines[#lines + 1] = cur
    end

    return lines
end

local function sum_outer_hypo_main(infos, indices, gap_main)
    local used = gap_main * math_max(0, #indices - 1)
    for i = 1, #indices do
        local idx = indices[i]
        local inf = infos[idx]
        used = used + inf.hypo_main + inf.main_margin_start + inf.main_margin_end
    end
    return used
end

local function remaining_main_space(infos, indices, sizes, frozen, gap_main)
    local used = gap_main * math_max(0, #indices - 1)
    for i = 1, #indices do
        local idx = indices[i]
        local inf = infos[idx]
        used = used + inf.main_margin_start + inf.main_margin_end
        used = used + (frozen[idx] and sizes[idx] or inf.base)
    end
    return used
end

local function resolve_line_main_sizes(infos, indices, avail_main, gap_main)
    local sizes = {}
    if avail_main == INF then
        for i = 1, #indices do
            local idx = indices[i]
            sizes[idx] = infos[idx].hypo_main
        end
        return sizes
    end

    local frozen = {}
    local outer_hypo = sum_outer_hypo_main(infos, indices, gap_main)
    local use_grow = outer_hypo < avail_main

    for i = 1, #indices do
        local idx = indices[i]
        local inf = infos[idx]
        local factor = use_grow and inf.item.grow or inf.item.shrink
        if factor == 0
            or (use_grow and inf.base > inf.hypo_main)
            or ((not use_grow) and inf.base < inf.hypo_main) then
            sizes[idx] = inf.hypo_main
            frozen[idx] = true
        else
            sizes[idx] = inf.base
        end
    end

    while true do
        local any_unfrozen = false
        for i = 1, #indices do
            if not frozen[indices[i]] then
                any_unfrozen = true
                break
            end
        end
        if not any_unfrozen then
            break
        end

        local free = avail_main - remaining_main_space(infos, indices, sizes, frozen, gap_main)
        if math_abs(free) <= EPS then
            for i = 1, #indices do
                local idx = indices[i]
                if not frozen[idx] then
                    sizes[idx] = clamp(infos[idx].base, infos[idx].min_main, infos[idx].max_main)
                    frozen[idx] = true
                end
            end
            break
        end

        local weight = 0
        if use_grow then
            for i = 1, #indices do
                local idx = indices[i]
                if not frozen[idx] and infos[idx].item.grow > 0 then
                    weight = weight + infos[idx].item.grow
                end
            end
        else
            for i = 1, #indices do
                local idx = indices[i]
                local inf = infos[idx]
                if not frozen[idx] and inf.item.shrink > 0 then
                    weight = weight + inf.item.shrink * inf.base
                end
            end
        end

        if weight <= EPS then
            for i = 1, #indices do
                local idx = indices[i]
                if not frozen[idx] then
                    sizes[idx] = infos[idx].hypo_main
                    frozen[idx] = true
                end
            end
            break
        end

        local total_violation = 0
        local min_viol = {}
        local max_viol = {}
        local has_min_viol = false
        local has_max_viol = false

        for i = 1, #indices do
            local idx = indices[i]
            if not frozen[idx] then
                local inf = infos[idx]
                local target
                if use_grow then
                    target = inf.base + free * (inf.item.grow / weight)
                else
                    local sw = inf.item.shrink * inf.base
                    target = (sw > 0) and (inf.base + free * (sw / weight)) or inf.base
                end
                local clamped = clamp(target, inf.min_main, inf.max_main)
                sizes[idx] = clamped
                local delta = clamped - target
                total_violation = total_violation + delta
                if delta > EPS then
                    min_viol[idx] = true
                    has_min_viol = true
                elseif delta < -EPS then
                    max_viol[idx] = true
                    has_max_viol = true
                end
            end
        end

        if math_abs(total_violation) <= EPS then
            for i = 1, #indices do
                local idx = indices[i]
                if not frozen[idx] then
                    frozen[idx] = true
                end
            end
        elseif total_violation > 0 and has_min_viol then
            for i = 1, #indices do
                local idx = indices[i]
                if min_viol[idx] then
                    frozen[idx] = true
                end
            end
        elseif total_violation < 0 and has_max_viol then
            for i = 1, #indices do
                local idx = indices[i]
                if max_viol[idx] then
                    frozen[idx] = true
                end
            end
        else
            for i = 1, #indices do
                local idx = indices[i]
                if not frozen[idx] then
                    frozen[idx] = true
                end
            end
        end
    end

    for i = 1, #indices do
        local idx = indices[i]
        sizes[idx] = clamp(sizes[idx] or infos[idx].hypo_main, infos[idx].min_main, infos[idx].max_main)
    end

    return sizes
end

local function line_used_main(infos, indices, sizes, gap_main)
    local used = gap_main * math_max(0, #indices - 1)
    for i = 1, #indices do
        local idx = indices[i]
        used = used + sizes[idx] + infos[idx].main_margin_start + infos[idx].main_margin_end
    end
    return used
end

local function pack_main(mode, free, count)
    local lead = 0
    local gap_extra = 0

    if mode == MAIN_END then
        lead = free
    elseif mode == MAIN_CENTER then
        lead = free / 2
    elseif mode == MAIN_SPACE_BETWEEN then
        if free > 0 and count > 1 then
            gap_extra = free / (count - 1)
        end
    elseif mode == MAIN_SPACE_AROUND then
        if free > 0 then
            gap_extra = free / count
            lead = gap_extra / 2
        else
            lead = free / 2
        end
    elseif mode == MAIN_SPACE_EVENLY then
        if free > 0 then
            gap_extra = free / (count + 1)
            lead = gap_extra
        else
            lead = free / 2
        end
    end

    return lead, gap_extra
end

local function pack_cross(mode, free, count)
    local lead = 0
    local gap_extra = 0

    if mode == CONTENT_END then
        lead = free
    elseif mode == CONTENT_CENTER then
        lead = free / 2
    elseif mode == CONTENT_SPACE_BETWEEN then
        if free > 0 and count > 1 then
            gap_extra = free / (count - 1)
        end
    elseif mode == CONTENT_SPACE_AROUND then
        if free > 0 then
            gap_extra = free / count
            lead = gap_extra / 2
        else
            lead = free / 2
        end
    elseif mode == CONTENT_SPACE_EVENLY then
        if free > 0 then
            gap_extra = free / (count + 1)
            lead = gap_extra
        else
            lead = free / 2
        end
    end

    return lead, gap_extra
end

local function layout(node, outer, measure_opts, measure_api)
    measure_api = ensure_measure_api(measure_api)
    local measure_node = function(cur, c)
        return measure_api.measure(cur, c, measure_opts)
    end
    local frame = resolve_local_frame(node, outer, measure_opts, measure_api)
    local axis = node.axis
    local rowish = is_row_axis(axis)
    local main_size = rowish and frame.w or frame.h
    local cross_size = rowish and frame.h or frame.w
    local inner_constraint = measure_api.available_constraint_from_frame(frame)
    local child_infos = flex_collect_infos(node, inner_constraint, measure_node)

    if #child_infos == 0 then
        return {}, frame
    end

    local lines = collect_lines(child_infos, node.wrap, main_size, node.gap_main)
    local line_infos = {}
    local natural_cross_total = 0

    for li = 1, #lines do
        local idxs = lines[li]
        local sizes = resolve_line_main_sizes(child_infos, idxs, main_size, node.gap_main)
        local used_main = line_used_main(child_infos, idxs, sizes, node.gap_main)
        local line_cross = 0
        local line_baseline = 0
        local items = {}

        for j = 1, #idxs do
            local idx = idxs[j]
            local inf = child_infos[idx]
            local slot_main = sizes[idx]
            local ccon = rowish
                and measure_api.constraint(measure_api.exact(math_max(0, slot_main)), exact_or_atmost(cross_size, false))
                or measure_api.constraint(exact_or_atmost(cross_size, false), measure_api.exact(math_max(0, slot_main)))
            local m = measure_node(inf.item.node, ccon)
            local actual_cross = cross_size_of(m, axis)
            local baseline = baseline_num(m.baseline)
            if rowish and baseline == nil then
                baseline = actual_cross
            end
            if baseline and rowish then
                line_baseline = math_max(line_baseline, baseline + inf.cross_margin_start)
            end
            line_cross = math_max(line_cross, actual_cross + inf.cross_margin_start + inf.cross_margin_end)
            items[j] = {
                idx = idx,
                slot_main = slot_main,
                actual_main = slot_main,
                actual_cross = actual_cross,
                measure = m,
                baseline = baseline,
            }
        end

        line_infos[li] = {
            items = items,
            used_main = used_main,
            natural_cross = line_cross,
            baseline = line_baseline,
        }
        natural_cross_total = natural_cross_total + line_cross
        if li > 1 then
            natural_cross_total = natural_cross_total + node.gap_cross
        end
    end

    local line_cross_sizes = {}
    local line_cross_pos = {}
    local free_cross = (cross_size == INF) and 0 or (cross_size - natural_cross_total)

    if #line_infos == 1 and cross_size ~= INF then
        line_cross_sizes[1] = cross_size
    elseif node.align_content == CONTENT_STRETCH and cross_size ~= INF and #line_infos > 0 and free_cross > 0 then
        local extra = free_cross / #line_infos
        for li = 1, #line_infos do
            line_cross_sizes[li] = line_infos[li].natural_cross + extra
        end
    else
        for li = 1, #line_infos do
            line_cross_sizes[li] = line_infos[li].natural_cross
        end
        local line_lead, line_gap_extra = pack_cross(node.align_content, free_cross, #line_infos)
        local p = line_lead
        for li = 1, #line_infos do
            line_cross_pos[li] = p
            p = p + line_cross_sizes[li] + node.gap_cross + line_gap_extra
        end
    end

    if not line_cross_pos[1] then
        local p = 0
        for li = 1, #line_infos do
            line_cross_pos[li] = p
            p = p + line_cross_sizes[li] + node.gap_cross
        end
    end

    local placed = {}
    for li = 1, #line_infos do
        local line = line_infos[li]
        local line_slot_cross = line_cross_sizes[li]
        local free_main = (main_size == INF) and 0 or (main_size - line.used_main)
        local line_start, gap_extra = pack_main(node.justify, free_main, #line.items)
        local pmain = line_start

        for j = 1, #line.items do
            local item = line.items[j]
            local inf = child_infos[item.idx]
            local eff_align = inf.item.self_align
            if eff_align == CROSS_AUTO then
                eff_align = node.align_items
            end
            if (not rowish) and eff_align == CROSS_BASELINE then
                eff_align = CROSS_START
            end

            local cross_inner = math_max(0, line_slot_cross - inf.cross_margin_start - inf.cross_margin_end)
            local actual_cross = item.actual_cross
            if eff_align == CROSS_STRETCH and inf.cross_auto then
                actual_cross = clamp(cross_inner, inf.min_cross, inf.max_cross)
            else
                actual_cross = clamp(actual_cross, inf.min_cross, inf.max_cross)
            end

            local cross_offset
            if eff_align == CROSS_END then
                cross_offset = line_slot_cross - inf.cross_margin_end - actual_cross
            elseif eff_align == CROSS_CENTER then
                cross_offset = inf.cross_margin_start + (cross_inner - actual_cross) / 2
            elseif eff_align == CROSS_BASELINE and rowish and item.baseline then
                cross_offset = line.baseline - item.baseline
            else
                cross_offset = inf.cross_margin_start
            end

            local logical_main = pmain + inf.main_margin_start
            local logical_cross = line_cross_pos[li] + cross_offset

            local x, y, w, h
            if rowish then
                w, h = item.actual_main, actual_cross
                x = is_reverse_axis(axis) and (frame.x + frame.w - logical_main - w) or (frame.x + logical_main)
                y = is_wrap_reverse(node.wrap) and (frame.y + frame.h - logical_cross - h) or (frame.y + logical_cross)
            else
                w, h = actual_cross, item.actual_main
                x = is_wrap_reverse(node.wrap) and (frame.x + frame.w - logical_cross - w) or (frame.x + logical_cross)
                y = is_reverse_axis(axis) and (frame.y + frame.h - logical_main - h) or (frame.y + logical_main)
            end

            placed[#placed + 1] = {
                node = inf.item.node,
                frame = mkframe(x, y, w, h),
            }

            pmain = pmain + inf.main_margin_start + item.slot_main + inf.main_margin_end + node.gap_main + gap_extra
        end
    end

    return placed, frame
end

flex.is_row_axis = is_row_axis
flex.span_available = span_available
flex.exact_or_atmost = exact_or_atmost
flex.main_size_of = main_size_of
flex.cross_size_of = cross_size_of
flex.collect_infos = flex_collect_infos
flex.collect_lines = collect_lines
flex.resolve_line_main_sizes = resolve_line_main_sizes
flex.line_used_main = line_used_main
flex.layout = layout

return flex
