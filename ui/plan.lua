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

local function margin_px(v)
    local cls = pvm.classof(v)
    if v == Layout.MarginAuto then return 0 end
    if cls == Layout.MarginPx then return v.px end
    return 0
end

local function box_margins(box)
    local m = box.margin
    return margin_px(m.left), margin_px(m.right), margin_px(m.top), margin_px(m.bottom)
end

local function is_auto_margin(v)
    return v == Layout.MarginAuto
end

local function should_clip(box)
    return box.overflow_x == Layout.OHidden or box.overflow_y == Layout.OHidden
end

local function is_scroll_container(box)
    return box.overflow_x == Layout.OScroll or box.overflow_x == Layout.OAuto
        or box.overflow_y == Layout.OScroll or box.overflow_y == Layout.OAuto
end

local function effective_cross_align(self_align, items)
    if self_align == Layout.SelfAuto then return items end
    if self_align == Layout.SelfStart then return Layout.CStart end
    if self_align == Layout.SelfCenter then return Layout.CCenter end
    if self_align == Layout.SelfEnd then return Layout.CEnd end
    if self_align == Layout.SelfStretch then return Layout.CStretch end
    if self_align == Layout.SelfBaseline then return Layout.CBaseline end
    return items
end

local function compute_main_alignment(justify, used, available, gap, count)
    if not finite(available) then
        return 0, gap
    end

    local extra = available - used
    if extra < 0 then extra = 0 end

    if justify == Layout.MCenter then
        return extra / 2, gap
    elseif justify == Layout.MEnd then
        return extra, gap
    elseif justify == Layout.MBetween and count > 1 then
        return 0, gap + extra / (count - 1)
    elseif justify == Layout.MAround and count > 0 then
        local step = extra / count
        return step / 2, gap + step
    elseif justify == Layout.MEvenly and count > 0 then
        local step = extra / (count + 1)
        return step, gap + step
    end

    return 0, gap
end

local function cross_place(align, avail_cross, border_cross, m_start, m_end)
    if not finite(avail_cross) then
        return m_start, border_cross
    end

    if align == Layout.CCenter then
        return (avail_cross - (border_cross + m_start + m_end)) / 2 + m_start, border_cross
    elseif align == Layout.CEnd then
        return avail_cross - border_cross - m_end, border_cross
    elseif align == Layout.CStretch then
        local stretched = max0(avail_cross - m_start - m_end)
        return m_start, stretched
    end
    return m_start, border_cross
end

local span_size
local track_positions

local function max_grid_end(items, axis)
    local last = 0
    for i = 1, #items do
        local item = items[i]
        local start_i, span
        if axis == "col" then
            start_i = item.col_start
            span = item.col_span
        else
            start_i = item.row_start
            span = item.row_span
        end
        local finish = start_i + span - 1
        if finish > last then last = finish end
    end
    return last
end

local function ensure_tracks(tracks, count)
    local out = {}
    for i = 1, #tracks do out[i] = tracks[i] end
    for i = #out + 1, count do out[i] = Layout.TrackAuto end
    return out
end

local function track_base_size(track)
    local cls = pvm.classof(track)
    if cls == Layout.TrackFixed then return track.px end
    if cls == Layout.TrackMinMax then return track.min_px end
    return 0
end

local function track_can_grow_from_content(track, current)
    local cls = pvm.classof(track)
    if cls == Layout.TrackFixed then return false, 0 end
    if cls == Layout.TrackMinMax then
        local room = track.max_px - current
        if room > 0 then return true, room end
        return false, 0
    end
    return true, HUGE
end

local function solve_track_mins(tracks, gap, items, need_fn)
    local sizes = {}
    for i = 1, #tracks do
        sizes[i] = track_base_size(tracks[i])
    end

    for i = 1, #items do
        local item = items[i]
        local need = need_fn(item)
        local have = span_size(sizes, item.start_i, item.span, gap)
        local deficit = need - have
        if deficit > 0 then
            local growable = {}
            local total_room = 0
            for ti = item.start_i, math.min(#tracks, item.start_i + item.span - 1) do
                local ok, room = track_can_grow_from_content(tracks[ti], sizes[ti])
                if ok then
                    growable[#growable + 1] = { index = ti, room = room }
                    total_room = total_room + room
                end
            end
            if #growable > 0 then
                local remaining = deficit
                while remaining > 0 and #growable > 0 do
                    local share = remaining / #growable
                    local next_growable = {}
                    local spent = 0
                    for gi = 1, #growable do
                        local g = growable[gi]
                        local add = share
                        if g.room < add then add = g.room end
                        sizes[g.index] = sizes[g.index] + add
                        spent = spent + add
                        local new_room = g.room - add
                        if new_room > 1e-9 then
                            next_growable[#next_growable + 1] = { index = g.index, room = new_room }
                        end
                    end
                    if spent <= 1e-9 then break end
                    remaining = remaining - spent
                    growable = next_growable
                end
            end
        end
    end

    return sizes
end

local function distribute_fr_tracks(tracks, sizes, gap, available)
    if not finite(available) then
        return sizes
    end

    local used = 0
    local fr_total = 0
    for i = 1, #sizes do
        used = used + sizes[i]
        local track = tracks[i]
        if pvm.classof(track) == Layout.TrackFr then
            fr_total = fr_total + track.fr
        end
    end
    if #sizes > 1 then used = used + (#sizes - 1) * gap end

    if fr_total <= 0 or used >= available then
        return sizes
    end

    local extra = available - used
    for i = 1, #sizes do
        local track = tracks[i]
        if pvm.classof(track) == Layout.TrackFr then
            sizes[i] = sizes[i] + extra * (track.fr / fr_total)
        end
    end
    return sizes
end

local function solve_grid_axis(tracks, gap, available, items, need_fn)
    local sizes = solve_track_mins(tracks, gap, items, need_fn)
    return distribute_fr_tracks(tracks, sizes, gap, available)
end

span_size = function(sizes, start_i, span, gap)
    local total = 0
    local last = math.min(#sizes, start_i + span - 1)
    for i = start_i, last do
        total = total + sizes[i]
    end
    if last >= start_i and span > 1 then
        total = total + (last - start_i) * gap
    end
    return total
end

track_positions = function(sizes, gap)
    local out = {}
    local pos = 0
    for i = 1, #sizes do
        out[i] = pos
        pos = pos + sizes[i] + gap
    end
    return out
end

local function node_box(node)
    local cls = pvm.classof(node)
    if cls == Layout.WithInput then
        return node_box(node.child)
    end
    return node.box
end

local function node_with_main_size(node, axis, px)
    local cls = pvm.classof(node)
    if cls == Layout.WithInput then
        return pvm.with(node, { child = node_with_main_size(node.child, axis, px) })
    end

    if axis == Layout.LRow then
        return pvm.with(node, {
            box = pvm.with(node.box, { w = Layout.SFixed(px) })
        })
    end

    return pvm.with(node, {
        box = pvm.with(node.box, { h = Layout.SFixed(px) })
    })
end

local function flow_plan(node, available_w, available_h, measure_one)
    local children = node.children
    local gap_y = node.gap_y
    local items = node.items
    local plan = {}
    local used_h = 0
    local max_outer_w = 0

    for i = 1, #children do
        local child = children[i]
        local child_box = node_box(child)
        local size = measure_one(child, Layout.Constraint(available_w, HUGE))
        local m = child_box.margin
        local ml_auto = is_auto_margin(m.left)
        local mr_auto = is_auto_margin(m.right)
        local ml = ml_auto and 0 or margin_px(m.left)
        local mr = mr_auto and 0 or margin_px(m.right)
        local mt = margin_px(m.top)
        local mb = margin_px(m.bottom)
        local outer_w = size.w
        local outer_h = size.h

        if child_box.w == Layout.SAuto and finite(available_w) then
            outer_w = math.max(ml + mr, available_w)
        end

        plan[i] = {
            node = child,
            box = child_box,
            size = size,
            ml = ml,
            mr = mr,
            mt = mt,
            mb = mb,
            ml_auto = ml_auto,
            mr_auto = mr_auto,
            outer_w = outer_w,
            outer_h = outer_h,
        }

        used_h = used_h + outer_h
        if outer_w > max_outer_w then max_outer_w = outer_w end
    end

    if #children > 1 then
        used_h = used_h + (#children - 1) * gap_y
    end

    local main_start, main_gap = compute_main_alignment(node.justify, used_h, available_h, gap_y, #children)
    local pos = main_start

    for i = 1, #plan do
        local item = plan[i]
        local border_w = max0(item.outer_w - item.ml - item.mr)
        local border_h = max0(item.outer_h - item.mt - item.mb)
        local dx
        local align = effective_cross_align(item.box.self_align, items)

        if finite(available_w) and (item.ml_auto or item.mr_auto) then
            local extra = available_w - (border_w + item.ml + item.mr)
            if extra < 0 then extra = 0 end
            if item.ml_auto and item.mr_auto then
                dx = item.ml + extra / 2
            elseif item.ml_auto then
                dx = item.ml + extra
            else
                dx = item.ml
            end
        else
            local cross_off, placed_w = cross_place(align, available_w, border_w, item.ml, item.mr)
            dx = cross_off
            border_w = placed_w
        end

        item.dx = dx
        item.dy = pos + item.mt
        item.w = border_w
        item.h = border_h
        pos = pos + item.outer_h + main_gap
    end

    return plan, max_outer_w, used_h
end

local function axis_available_main(axis, available_w, available_h)
    if axis == Layout.LRow then return available_w end
    return available_h
end

local function axis_available_cross(axis, available_w, available_h)
    if axis == Layout.LRow then return available_h end
    return available_w
end

local function main_gap_for(node)
    if node.axis == Layout.LRow then return node.gap_x end
    return node.gap_y
end

local function line_gap_for(node)
    if node.axis == Layout.LRow then return node.gap_y end
    return node.gap_x
end

local function natural_flex_constraint(axis, available_w, available_h)
    if axis == Layout.LRow then
        return Layout.Constraint(available_w, available_h)
    end
    return Layout.Constraint(available_w, HUGE)
end

local function final_flex_constraint(axis, border_main, available_cross)
    if axis == Layout.LRow then
        return Layout.Constraint(border_main, available_cross)
    end
    return Layout.Constraint(available_cross, border_main)
end

local function prep_flex_item(axis, child, available_w, available_h, measure_one)
    local box = node_box(child)
    local size = measure_one(child, natural_flex_constraint(axis, available_w, available_h))
    local ml, mr, mt, mb = box_margins(box)

    local main_before, main_after, cross_before, cross_after
    local natural_main, natural_cross
    if axis == Layout.LRow then
        main_before, main_after = ml, mr
        cross_before, cross_after = mt, mb
        natural_main, natural_cross = size.w, size.h
    else
        main_before, main_after = mt, mb
        cross_before, cross_after = ml, mr
        natural_main, natural_cross = size.h, size.w
    end

    local margins_main = main_before + main_after
    local natural_border_main = max0(natural_main - margins_main)
    local basis = box.basis
    local basis_cls = pvm.classof(basis)
    local available_main = axis_available_main(axis, available_w, available_h)
    local base_border_main = natural_border_main

    if basis == Layout.BasisAuto then
        base_border_main = natural_border_main
    elseif basis == Layout.BasisHug then
        base_border_main = natural_border_main
    elseif basis_cls == Layout.BasisFixed then
        base_border_main = basis.px
    elseif basis_cls == Layout.BasisFrac then
        if finite(available_main) then
            base_border_main = available_main * basis.value
        else
            base_border_main = natural_border_main
        end
    end

    if base_border_main < 0 then base_border_main = 0 end

    return {
        node = child,
        box = box,
        natural_size = size,
        natural_main = natural_main,
        natural_cross = natural_cross,
        natural_baseline = size.baseline,
        main_before = main_before,
        main_after = main_after,
        cross_before = cross_before,
        cross_after = cross_after,
        base_border_main = base_border_main,
        base_outer_main = base_border_main + margins_main,
        final_border_main = base_border_main,
        final_outer_main = base_border_main + margins_main,
        final_outer_cross = natural_cross,
        baseline = size.baseline,
        dx = 0,
        dy = 0,
        w = 0,
        h = 0,
        line = 1,
    }
end

local function split_flex_lines(node, items, available_main)
    local wrap = node.wrap == Layout.LWrapOn
    local gap = main_gap_for(node)
    local lines = {}
    local current = nil

    local function push_line()
        if current ~= nil then
            lines[#lines + 1] = current
            current = nil
        end
    end

    for i = 1, #items do
        local item = items[i]
        if current == nil then
            current = { items = {}, base_used_main = 0, final_used_main = 0, cross_size = 0 }
        end

        local needed = item.base_outer_main
        if #current.items > 0 then needed = needed + gap end

        if wrap and finite(available_main) and #current.items > 0 and current.base_used_main + needed > available_main then
            push_line()
            current = { items = {}, base_used_main = 0, final_used_main = 0, cross_size = 0 }
            needed = item.base_outer_main
        end

        current.items[#current.items + 1] = item
        if #current.items == 1 then
            current.base_used_main = item.base_outer_main
        else
            current.base_used_main = current.base_used_main + gap + item.base_outer_main
        end
    end

    push_line()
    return lines
end

local function distribute_flex_line(node, line, available_main)
    local gap = main_gap_for(node)
    local items = line.items

    for i = 1, #items do
        local item = items[i]
        item.final_border_main = item.base_border_main
        item.final_outer_main = item.base_outer_main
    end

    if not finite(available_main) then
        line.final_used_main = line.base_used_main
        return
    end

    local free = available_main - line.base_used_main
    if free > 0 then
        local total_grow = 0
        for i = 1, #items do
            local grow = items[i].box.grow
            if grow > 0 then total_grow = total_grow + grow end
        end
        if total_grow > 0 then
            for i = 1, #items do
                local item = items[i]
                local grow = item.box.grow
                if grow > 0 then
                    item.final_border_main = item.base_border_main + free * (grow / total_grow)
                    item.final_outer_main = item.final_border_main + item.main_before + item.main_after
                end
            end
        end
    elseif free < 0 then
        local over = -free
        local total_shrink = 0
        for i = 1, #items do
            local item = items[i]
            local shrink = item.box.shrink
            if shrink > 0 then
                total_shrink = total_shrink + shrink * item.base_border_main
            end
        end
        if total_shrink > 0 then
            for i = 1, #items do
                local item = items[i]
                local shrink = item.box.shrink
                if shrink > 0 then
                    local reduce = over * ((shrink * item.base_border_main) / total_shrink)
                    item.final_border_main = max0(item.base_border_main - reduce)
                    item.final_outer_main = item.final_border_main + item.main_before + item.main_after
                end
            end
        end
    end

    local used = 0
    for i = 1, #items do
        used = used + items[i].final_outer_main
    end
    if #items > 1 then used = used + (#items - 1) * gap end
    line.final_used_main = used
end

local function measure_flex_line_cross(axis, line, available_cross, measure_one)
    local items = line.items
    local cross = 0

    for i = 1, #items do
        local item = items[i]
        local final_node = node_with_main_size(item.node, axis, item.final_border_main)
        item.final_node = final_node
        local size = measure_one(final_node, final_flex_constraint(axis, item.final_border_main, available_cross))
        item.final_size = size
        item.baseline = size.baseline
        if axis == Layout.LRow then
            item.final_outer_cross = size.h
        else
            item.final_outer_cross = size.w
        end
        if item.final_outer_cross > cross then cross = item.final_outer_cross end
    end

    line.cross_size = cross
end

local function position_flex_line(node, line, axis, available_main, line_origin_cross, line_index)
    local gap = main_gap_for(node)
    local main_start, main_gap = compute_main_alignment(node.justify, line.final_used_main, available_main, gap, #line.items)
    local pos = main_start

    for i = 1, #line.items do
        local item = line.items[i]
        item.line = line_index
        if item.final_node ~= nil then
            item.node = item.final_node
        end

        local align = effective_cross_align(item.box.self_align, node.items)
        local border_cross = max0(item.final_outer_cross - item.cross_before - item.cross_after)
        local cross_off, placed_cross = cross_place(align, line.cross_size, border_cross, item.cross_before, item.cross_after)

        if axis == Layout.LRow then
            item.dx = pos + item.main_before
            item.dy = line_origin_cross + cross_off
            item.w = item.final_border_main
            item.h = placed_cross
        else
            item.dx = line_origin_cross + cross_off
            item.dy = pos + item.main_before
            item.w = placed_cross
            item.h = item.final_border_main
        end

        pos = pos + item.final_outer_main + main_gap
    end
end

local function flex_plan(node, available_w, available_h, measure_one)
    local axis = node.axis
    local available_main = axis_available_main(axis, available_w, available_h)
    local available_cross = axis_available_cross(axis, available_w, available_h)
    local line_gap = line_gap_for(node)
    local raw_items = {}

    for i = 1, #node.children do
        raw_items[i] = prep_flex_item(axis, node.children[i], available_w, available_h, measure_one)
    end

    local lines = split_flex_lines(node, raw_items, available_main)
    local placements = {}
    local base_main_extent = 0
    local final_main_extent = 0
    local cross_extent = 0
    local line_origin_cross = 0

    for li = 1, #lines do
        local line = lines[li]
        distribute_flex_line(node, line, available_main)
        measure_flex_line_cross(axis, line, available_cross, measure_one)
        position_flex_line(node, line, axis, available_main, line_origin_cross, li)

        if line.base_used_main > base_main_extent then base_main_extent = line.base_used_main end
        if line.final_used_main > final_main_extent then final_main_extent = line.final_used_main end
        if li > 1 then cross_extent = cross_extent + line_gap end
        cross_extent = cross_extent + line.cross_size

        for i = 1, #line.items do
            placements[#placements + 1] = line.items[i]
        end

        line_origin_cross = line_origin_cross + line.cross_size + line_gap
    end

    return {
        items = placements,
        lines = lines,
        base_main_extent = base_main_extent,
        final_main_extent = final_main_extent,
        cross_extent = cross_extent,
    }
end

local function grid_plan(node, available_w, available_h, measure_one)
    local item_count = #node.items
    local col_count = math.max(#node.cols, max_grid_end(node.items, "col"))
    local row_count = math.max(#node.rows, max_grid_end(node.items, "row"))
    local cols = ensure_tracks(node.cols, col_count)
    local rows = ensure_tracks(node.rows, row_count)
    local col_gap = node.col_gap
    local row_gap = node.row_gap

    local axis_items = {}
    for i = 1, item_count do
        local item = node.items[i]
        axis_items[i] = {
            node = item.node,
            col_start = item.col_start,
            col_span = item.col_span,
            row_start = item.row_start,
            row_span = item.row_span,
            col_align = item.col_align,
            row_align = item.row_align,
        }
    end

    local col_need_items = {}
    for i = 1, item_count do
        local item = axis_items[i]
        col_need_items[i] = {
            start_i = item.col_start,
            span = item.col_span,
            node = item.node,
        }
    end

    local col_sizes = solve_grid_axis(cols, col_gap, available_w, col_need_items, function(item)
        local size = measure_one(item.node, Layout.Constraint(HUGE, HUGE))
        return size.w
    end)

    local row_need_items = {}
    for i = 1, item_count do
        local item = axis_items[i]
        row_need_items[i] = {
            start_i = item.row_start,
            span = item.row_span,
            node = item.node,
            col_start = item.col_start,
            col_span = item.col_span,
        }
    end

    local row_sizes = solve_grid_axis(rows, row_gap, available_h, row_need_items, function(item)
        local item_w = span_size(col_sizes, item.col_start, item.col_span, col_gap)
        local size = measure_one(item.node, Layout.Constraint(item_w > 0 and item_w or HUGE, HUGE))
        return size.h
    end)

    local col_x = track_positions(col_sizes, col_gap)
    local row_y = track_positions(row_sizes, row_gap)
    local placements = {}

    for i = 1, item_count do
        local item = axis_items[i]
        local ix = col_x[item.col_start] or 0
        local iy = row_y[item.row_start] or 0
        local iw = span_size(col_sizes, item.col_start, item.col_span, col_gap)
        local ih = span_size(row_sizes, item.row_start, item.row_span, row_gap)
        local size = measure_one(item.node, Layout.Constraint(iw > 0 and iw or HUGE, ih > 0 and ih or HUGE))
        local child_box = node_box(item.node)
        local ml, mr, mt, mb = box_margins(child_box)
        local border_w = max0(size.w - ml - mr)
        local border_h = max0(size.h - mt - mb)
        local dx = ix + ml
        local dy = iy + mt
        local w = border_w
        local h = border_h

        if item.col_align == Layout.CCenter then
            dx = ix + (iw - size.w) / 2 + ml
        elseif item.col_align == Layout.CEnd then
            dx = ix + iw - size.w + ml
        elseif item.col_align == Layout.CStretch then
            w = max0(iw - ml - mr)
        end

        if item.row_align == Layout.CCenter then
            dy = iy + (ih - size.h) / 2 + mt
        elseif item.row_align == Layout.CEnd then
            dy = iy + ih - size.h + mt
        elseif item.row_align == Layout.CStretch then
            h = max0(ih - mt - mb)
        end

        placements[i] = {
            node = item.node,
            dx = dx,
            dy = dy,
            w = w,
            h = h,
            slot_w = iw,
            slot_h = ih,
            measured = size,
        }
    end

    return {
        cols = cols,
        rows = rows,
        col_sizes = col_sizes,
        row_sizes = row_sizes,
        col_x = col_x,
        row_y = row_y,
        items = placements,
        used_w = span_size(col_sizes, 1, #col_sizes, col_gap),
        used_h = span_size(row_sizes, 1, #row_sizes, row_gap),
    }
end

M.HUGE = HUGE
M.finite = finite
M.max0 = max0
M.margin_px = margin_px
M.box_margins = box_margins
M.is_auto_margin = is_auto_margin
M.should_clip = should_clip
M.is_scroll_container = is_scroll_container
M.effective_cross_align = effective_cross_align
M.compute_main_alignment = compute_main_alignment
M.cross_place = cross_place
M.span_size = span_size
M.track_positions = track_positions
M.node_box = node_box
M.flow_plan = flow_plan
M.flex_plan = flex_plan
M.grid_plan = grid_plan
M.T = T

return M
