local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local measure_mod = require("ui.measure")

local T = ui_asdl.T
local Core = T.Core
local Layout = T.Layout
local View = T.View
local Solve = T.Solve

local M = {}

local measure = measure_mod.measure
local text_layout = measure_mod.text_layout

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
    if v == Layout.MarginAuto then
        return 0
    end
    if cls == Layout.MarginPx then
        return v.px
    end
    return 0
end

local function box_margins(box)
    local m = box.margin
    return margin_px(m.left), margin_px(m.right), margin_px(m.top), margin_px(m.bottom)
end

local function should_clip(box)
    return box.overflow_x ~= Layout.OVisible or box.overflow_y ~= Layout.OVisible
end

local function has_visual(visual)
    return visual.bg ~= 0 or visual.border_w > 0
end

local function get_scroll(env, id)
    if id == Core.NoId then
        return 0, 0
    end
    local scrolls = env.scrolls
    for i = 1, #scrolls do
        local s = scrolls[i]
        if s.id == id then
            return s.x, s.y
        end
    end
    return 0, 0
end

local function push_draw(draw, kind, id, x, y, w, h, visual, text)
    draw[#draw + 1] = View.Cmd(kind, id, x, y, w, h, visual, text)
end

local function push_regions(frame, id, cursor, x, y, w, h, z)
    if id == Core.NoId then
        return z
    end
    frame.hit[#frame.hit + 1] = View.Hit(id, x, y, w, h, z)
    frame.focus[#frame.focus + 1] = View.FocusItem(id, #frame.focus + 1, x, y, w, h)
    if cursor ~= T.Style.CursorDefault then
        frame.cursors[#frame.cursors + 1] = View.CursorRegion(id, cursor, x, y, w, h)
    end
    return z + 1
end

local function effective_cross_align(self_align, items)
    if self_align == Layout.SelfAuto then
        return items
    end
    if self_align == Layout.SelfStart then return Layout.CStart end
    if self_align == Layout.SelfCenter then return Layout.CCenter end
    if self_align == Layout.SelfEnd then return Layout.CEnd end
    if self_align == Layout.SelfStretch then return Layout.CStretch end
    if self_align == Layout.SelfBaseline then return Layout.CBaseline end
    return items
end

local function compute_main_alignment(justify, used, available, gap, count)
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

local function cross_place(align, start_xy, avail_cross, border_cross, m_start, m_end)
    if align == Layout.CCenter then
        return start_xy + (avail_cross - (border_cross + m_start + m_end)) / 2 + m_start, border_cross
    elseif align == Layout.CEnd then
        return start_xy + avail_cross - border_cross - m_end, border_cross
    elseif align == Layout.CStretch then
        local stretched = max0(avail_cross - m_start - m_end)
        return start_xy + m_start, stretched
    end
    return start_xy + m_start, border_cross
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

    if fr_total > 0 then
        for i = 1, #cols do
            local track = cols[i]
            if pvm.classof(track) == Layout.TrackFr then
                widths[i] = remaining * (track.fr / fr_total)
            end
        end
    end

    return widths
end

local function span_size(sizes, start_i, span, gap)
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

local function track_positions(sizes, gap, start)
    local out = {}
    local pos = start
    for i = 1, #sizes do
        out[i] = pos
        pos = pos + sizes[i] + gap
    end
    return out
end

local function place(node, x, y, w, h, env, frame, z)
    local cls = pvm.classof(node)

    if cls == Layout.Leaf then
        local box = node.box
        local visual = box.visual
        if has_visual(visual) then
            push_draw(frame.draw, View.Rect, node.id, x, y, w, h, visual, nil)
        end
        z = push_regions(frame, node.id, box.cursor, x, y, w, h, z)
        if node.text ~= nil then
            local pad = box.padding
            local inner_w = max0(w - pad.left - pad.right)
            local inner_h = max0(h - pad.top - pad.bottom)
            local tl = text_layout(node.text, Layout.Constraint(inner_w, inner_h))
            push_draw(frame.draw, View.Text, node.id, x + pad.left, y + pad.top, inner_w, inner_h, nil, tl)
        end
        return z
    end

    local box = node.box
    local visual = box.visual
    if has_visual(visual) then
        push_draw(frame.draw, View.Rect, node.id, x, y, w, h, visual, nil)
    end
    z = push_regions(frame, node.id, box.cursor, x, y, w, h, z)

    local clipped = should_clip(box)
    if clipped then
        push_draw(frame.draw, View.PushClip, node.id, x, y, w, h, nil, nil)
    end

    local pad = box.padding
    local cx = x + pad.left
    local cy = y + pad.top
    local cw = max0(w - pad.left - pad.right)
    local ch = max0(h - pad.top - pad.bottom)

    local sx, sy = get_scroll(env, node.id)
    cx = cx - sx
    cy = cy - sy

    if cls == Layout.Flex then
        local children = node.children
        local axis = node.axis
        local sizes = {}
        local used = 0
        local gap = axis == Layout.LRow and node.gap_x or node.gap_y

        for i = 1, #children do
            local child = children[i]
            local child_constraint
            if axis == Layout.LCol then
                child_constraint = Layout.Constraint(cw, HUGE)
            else
                child_constraint = Layout.Constraint(cw, ch)
            end
            local size = measure(child, child_constraint)
            sizes[i] = size
            used = used + (axis == Layout.LCol and size.h or size.w)
        end
        if #children > 1 then
            used = used + (#children - 1) * gap
        end

        local main_start, main_gap = compute_main_alignment(
            node.justify,
            used,
            axis == Layout.LCol and ch or cw,
            gap,
            #children
        )

        local pos = (axis == Layout.LCol and cy or cx) + main_start
        for i = 1, #children do
            local child = children[i]
            local size = sizes[i]
            local ml, mr, mt, mb = box_margins(child.box)
            local outer_w = size.w
            local outer_h = size.h
            local border_w = max0(outer_w - ml - mr)
            local border_h = max0(outer_h - mt - mb)
            local align = effective_cross_align(child.box.self_align, node.items)

            if axis == Layout.LCol then
                local child_x, placed_w = cross_place(align, cx, cw, border_w, ml, mr)
                local child_y = pos + mt
                if align == Layout.CStretch then
                    placed_w = max0(cw - ml - mr)
                end
                z = place(child, child_x, child_y, placed_w, border_h, env, frame, z)
                pos = pos + outer_h + main_gap
            else
                local child_y, placed_h = cross_place(align, cy, ch, border_h, mt, mb)
                local child_x = pos + ml
                if align == Layout.CStretch then
                    placed_h = max0(ch - mt - mb)
                end
                z = place(child, child_x, child_y, border_w, placed_h, env, frame, z)
                pos = pos + outer_w + main_gap
            end
        end

    elseif cls == Layout.Grid then
        local col_widths = resolve_grid_cols(node, cw)
        local row_heights = {}
        for i = 1, #node.items do
            local item = node.items[i]
            local item_w = span_size(col_widths, item.col_start, item.col_span, node.col_gap)
            local size = measure(item.node, Layout.Constraint(item_w > 0 and item_w or cw, HUGE))
            local row = item.row_start
            local prev = row_heights[row] or 0
            if size.h > prev then row_heights[row] = size.h end
        end

        local col_x = track_positions(col_widths, node.col_gap, cx)
        local row_y = track_positions(row_heights, node.row_gap, cy)

        for i = 1, #node.items do
            local item = node.items[i]
            local ix = col_x[item.col_start] or cx
            local iy = row_y[item.row_start] or cy
            local iw = span_size(col_widths, item.col_start, item.col_span, node.col_gap)
            local ih = span_size(row_heights, item.row_start, item.row_span, node.row_gap)

            local size = measure(item.node, Layout.Constraint(iw, ih))
            local ml, mr, mt, mb = box_margins(item.node.box)
            local border_w = max0(size.w - ml - mr)
            local border_h = max0(size.h - mt - mb)
            local child_x = ix + ml
            local child_y = iy + mt
            local placed_w = border_w
            local placed_h = border_h

            if item.col_align == Layout.CCenter then
                child_x = ix + (iw - size.w) / 2 + ml
            elseif item.col_align == Layout.CEnd then
                child_x = ix + iw - size.w + ml
            elseif item.col_align == Layout.CStretch then
                placed_w = max0(iw - ml - mr)
            end

            if item.row_align == Layout.CCenter then
                child_y = iy + (ih - size.h) / 2 + mt
            elseif item.row_align == Layout.CEnd then
                child_y = iy + ih - size.h + mt
            elseif item.row_align == Layout.CStretch then
                placed_h = max0(ih - mt - mb)
            end

            z = place(item.node, child_x, child_y, placed_w, placed_h, env, frame, z)
        end
    end

    if clipped then
        push_draw(frame.draw, View.PopClip, node.id, x, y, w, h, nil, nil)
    end

    return z
end

local solve = pvm.lower("ui.solve", function(node, env)
    local size = measure(node, Layout.Constraint(env.vw, env.vh))
    local root_w = finite(env.vw) and env.vw or size.w
    local root_h = finite(env.vh) and env.vh or size.h

    if size.w < root_w then root_w = size.w end
    if size.h < root_h then root_h = size.h end
    if root_w < 0 then root_w = 0 end
    if root_h < 0 then root_h = 0 end

    local frame = {
        draw = {},
        hit = {},
        focus = {},
        cursors = {},
    }

    place(node, 0, 0, root_w, root_h, env, frame, 1)

    return View.Frame(frame.draw, frame.hit, frame.focus, frame.cursors)
end)

M.solve = solve
M.T = T

return M
