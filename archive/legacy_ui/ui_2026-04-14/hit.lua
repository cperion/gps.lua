-- ui/hit.lua
--
-- Concrete UI hit-testing reducer.
--
-- This reducer walks lowered `UI.Node` trees using measured frames and returns a
-- typed `Facts.Hit` result. Interaction identity comes from explicit
-- interaction nodes (`Interact`, plus `ScrollArea`), not from paint tags.
-- It also exposes `scroll_id(...)` to target the nearest scroll container under
-- the pointer, which the session layer uses for wheel routing.

local pvm = require("pvm")
local classof = pvm.classof
local schema = require("ui.asdl")
local measure = require("ui.measure")
local solve = require("ui.solve")
local flex = require("ui._flex")
local grid = require("ui._grid")

local T = schema.T

local hit = { T = T, schema = schema, measure = measure }

local math_abs = math.abs
local math_floor = math.floor
local math_huge = math.huge
local math_max = math.max
local math_min = math.min

local INF = math_huge

local MISS = T.Facts.Miss
local HitId = T.Facts.HitId

local AXIS_ROW = T.Layout.AxisRow
local AXIS_ROW_REV = T.Layout.AxisRowReverse
local AXIS_COL = T.Layout.AxisCol
local AXIS_COL_REV = T.Layout.AxisColReverse

local WRAP_NO = T.Layout.WrapNoWrap
local WRAP_WRAP_REV = T.Layout.WrapWrapReverse

local SCROLL_X = T.Layout.ScrollX
local SCROLL_Y = T.Layout.ScrollY
local SCROLL_BOTH = T.Layout.ScrollBoth

local MAIN_END = T.Layout.MainEnd
local MAIN_CENTER = T.Layout.MainCenter
local MAIN_SPACE_BETWEEN = T.Layout.MainSpaceBetween
local MAIN_SPACE_AROUND = T.Layout.MainSpaceAround
local MAIN_SPACE_EVENLY = T.Layout.MainSpaceEvenly

local CROSS_AUTO = T.Layout.CrossAuto
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

local BASIS_AUTO = T.Layout.BasisAuto
local BASIS_CONTENT = T.Layout.BasisContent

local mtSpanExact = classof(measure.exact(0))
local mtSpanAtMost = classof(measure.at_most(0))
local mtBasisPx = classof(T.Layout.BasisPx(0))
local mtBasisPercent = classof(T.Layout.BasisPercent(0))

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

local function inside(px, py, x, y, w, h)
    return px >= x and py >= y and px < x + w and py < y + h
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

local function span_available(span)
    if span == measure.UNCONSTRAINED then
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

local function exact_or_atmost(px, exact)
    if px == INF then
        return measure.UNCONSTRAINED
    end
    if exact then
        return measure.exact(px)
    end
    return measure.at_most(px)
end

local function baseline_num(baseline)
    if baseline == measure.NO_BASELINE or baseline == nil then
        return nil
    end
    return baseline.px
end

local function style_insets(style)
    local h = (style.pad_h or 0) + (style.border_w or 0)
    local v = (style.pad_v or 0) + (style.border_w or 0)
    return h, v
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

local function resolve_basis_value(spec, available, content_value)
    if spec == BASIS_AUTO or spec == BASIS_CONTENT then
        return content_value
    end
    local mt = classof(spec)
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

local function build_measure_opts(opts)
    opts = opts or {}
    if opts.measure then
        return opts.measure
    end
    return {
        text_measure = opts.text_measure,
        font_height = opts.font_height,
        stats = opts.measure_stats,
        runtime = opts.runtime,
        env = opts.env,
    }
end

local function resolve_local_frame(node, outer, measure_opts)
    local m = measure.measure(node, measure.exact_constraint_from_frame(outer), measure_opts)
    return mkframe(outer.x, outer.y, m.used_w, m.used_h), m
end

local function scroll_child_constraint(node, viewport_w, viewport_h)
    local cw = exact_or_atmost(viewport_w, false)
    local ch = exact_or_atmost(viewport_h, false)
    if node.axis == SCROLL_X or node.axis == SCROLL_BOTH then
        cw = measure.UNCONSTRAINED
    end
    if node.axis == SCROLL_Y or node.axis == SCROLL_BOTH then
        ch = measure.UNCONSTRAINED
    end
    return measure.constraint(cw, ch)
end

local function scroll_child_frame(node, frame, measure_opts)
    local inset_h, inset_v = style_insets(node.style)
    local viewport_w = math_max(0, frame.w - inset_h * 2)
    local viewport_h = math_max(0, frame.h - inset_v * 2)
    local viewport_x = frame.x + inset_h
    local viewport_y = frame.y + inset_v
    local m = measure.measure(node.child, scroll_child_constraint(node, viewport_w, viewport_h), measure_opts)
    local child_w = (node.axis == SCROLL_X or node.axis == SCROLL_BOTH) and math_max(viewport_w, m.used_w) or viewport_w
    local child_h = (node.axis == SCROLL_Y or node.axis == SCROLL_BOTH) and math_max(viewport_h, m.used_h) or viewport_h
    return mkframe(viewport_x - node.scroll_x, viewport_y - node.scroll_y, child_w, child_h), viewport_x, viewport_y, viewport_w, viewport_h
end

local function intersect_clip(x, y, w, h, top)
    if not top then
        return x, y, w, h
    end
    local x2 = math_max(x, top[1])
    local y2 = math_max(y, top[2])
    local nw = math_max(0, math_min(x + w, top[1] + top[3]) - x2)
    local nh = math_max(0, math_min(y + h, top[2] + top[4]) - y2)
    return x2, y2, nw, nh
end

local function point_visible(ctx, x, y)
    local top = ctx.clip_stack[#ctx.clip_stack]
    return (not top) or inside(x, y, top[1], top[2], top[3], top[4])
end

local function frame_hit(ctx, frame)
    local x = frame.x + ctx.tx
    local y = frame.y + ctx.ty
    return point_visible(ctx, ctx.mx, ctx.my) and inside(ctx.mx, ctx.my, x, y, frame.w, frame.h)
end

local function flex_layout_children(node, outer, measure_opts)
    return flex.layout(node, outer, measure_opts, measure)
end

local function grid_layout_children(node, outer, measure_opts)
    local frame = resolve_local_frame(node, outer, measure_opts)
    return grid.layout_children(node, frame, measure, measure_opts, mkframe), frame
end

local function new_ctx(frame, x, y, opts)
    opts = opts or {}
    return {
        frame = frame,
        mx = x,
        my = y,
        tx = 0,
        ty = 0,
        tx_stack = {},
        clip_stack = {},
        opts = opts,
        measure_opts = build_measure_opts(opts),
    }
end

local function push_transform(ctx, dx, dy)
    ctx.tx_stack[#ctx.tx_stack + 1] = { ctx.tx, ctx.ty }
    ctx.tx = ctx.tx + dx
    ctx.ty = ctx.ty + dy
end

local function pop_transform(ctx)
    local t = ctx.tx_stack[#ctx.tx_stack]
    ctx.tx_stack[#ctx.tx_stack] = nil
    ctx.tx = t[1]
    ctx.ty = t[2]
end

local function push_clip(ctx, x, y, w, h)
    local ax, ay, nw, nh = intersect_clip(x, y, w, h, ctx.clip_stack[#ctx.clip_stack])
    ctx.clip_stack[#ctx.clip_stack + 1] = { ax, ay, nw, nh }
end

local function pop_clip(ctx)
    ctx.clip_stack[#ctx.clip_stack] = nil
end

local hit_node

local function interact_hit_id(node, active_id)
    if node.press_id and node.press_id ~= "" then
        return node.press_id
    end
    if node.hit_id and node.hit_id ~= "" then
        return node.hit_id
    end
    if node.focus_id and node.focus_id ~= "" then
        return node.focus_id
    end
    if node.key_id and node.key_id ~= "" then
        return node.key_id
    end
    return active_id
end

local function hit_with_fallback(result, fallback_id, fallback_frame, ctx)
    if result ~= MISS then
        return result
    end
    if fallback_id and fallback_id ~= "" and fallback_frame and frame_hit(ctx, fallback_frame) then
        return HitId(fallback_id)
    end
    return MISS
end

local solved_hit_node
solved_hit_node = function(node, active_id, ctx)
    if not node then
        return MISS
    end

    local kind = node.kind
    local frame = node.frame

    if kind == "Empty" then
        return MISS
    elseif kind == "Interact" then
        local next_id = interact_hit_id(node, active_id)
        local result = solved_hit_node(node.child, next_id, ctx)
        return hit_with_fallback(result, next_id, frame, ctx)
    elseif kind == "Flex" then
        for i = #node.children, 1, -1 do
            local result = solved_hit_node(node.children[i].node, active_id, ctx)
            if result ~= MISS then
                return result
            end
        end
        return hit_with_fallback(MISS, active_id, frame, ctx)
    elseif kind == "Grid" then
        for i = #node.children, 1, -1 do
            local result = solved_hit_node(node.children[i].node, active_id, ctx)
            if result ~= MISS then
                return result
            end
        end
        return hit_with_fallback(MISS, active_id, frame, ctx)
    elseif kind == "Pad" then
        local result = solved_hit_node(node.child, active_id, ctx)
        return hit_with_fallback(result, active_id, frame, ctx)
    elseif kind == "Stack" then
        for i = #node.children, 1, -1 do
            local result = solved_hit_node(node.children[i], active_id, ctx)
            if result ~= MISS then
                return result
            end
        end
        return hit_with_fallback(MISS, active_id, frame, ctx)
    elseif kind == "Clip" then
        push_clip(ctx, frame.x + ctx.tx, frame.y + ctx.ty, frame.w, frame.h)
        local result = solved_hit_node(node.child, active_id, ctx)
        pop_clip(ctx)
        return hit_with_fallback(result, active_id, frame, ctx)
    elseif kind == "Transform" then
        push_transform(ctx, node.tx, node.ty)
        local result = solved_hit_node(node.child, active_id, ctx)
        pop_transform(ctx)
        return hit_with_fallback(result, active_id, frame, ctx)
    elseif kind == "ScrollArea" then
        local next_id = (node.id ~= nil and node.id ~= "") and node.id or active_id
        local inset_h, inset_v = style_insets(node.style)
        push_clip(ctx, frame.x + inset_h + ctx.tx, frame.y + inset_v + ctx.ty, node.extent.viewport_w, node.extent.viewport_h)
        local result = solved_hit_node(node.child, next_id, ctx)
        pop_clip(ctx)
        return hit_with_fallback(result, next_id, frame, ctx)
    elseif kind == "Panel" then
        local result = solved_hit_node(node.child, active_id, ctx)
        return hit_with_fallback(result, active_id, frame, ctx)
    elseif kind == "Rect" or kind == "Text" or kind == "RuntimeText" or kind == "CustomPaint" or kind == "Spacer" then
        return hit_with_fallback(MISS, active_id, frame, ctx)
    elseif kind == "Overlay" then
        return solved_hit_node(node.base, active_id, ctx)
    end

    error("ui.hit: unsupported SolvedUI node kind " .. tostring(kind), 2)
end

function hit.hit_solved(node, frame, x, y, opts)
    local ctx = new_ctx(frame, x, y, opts)
    return solved_hit_node(node, nil, ctx)
end

function hit.hit(node, frame, x, y, opts)
    return hit.hit_solved(solve.node(node, frame, opts), frame, x, y, opts)
end

function hit.id_solved(node, frame, x, y, opts)
    local result = hit.hit_solved(node, frame, x, y, opts)
    if result == MISS then
        return nil
    end
    return result.id
end

function hit.id(node, frame, x, y, opts)
    local result = hit.hit(node, frame, x, y, opts)
    if result == MISS then
        return nil
    end
    return result.id
end

local solved_scroll_hit_node
solved_scroll_hit_node = function(node, scroll_id, ctx)
    if not node then
        return nil
    end

    local kind = node.kind
    local frame = node.frame

    if kind == "Empty" then
        return nil
    elseif kind == "Interact" then
        return solved_scroll_hit_node(node.child, scroll_id, ctx)
    elseif kind == "Flex" then
        for i = #node.children, 1, -1 do
            local result = solved_scroll_hit_node(node.children[i].node, scroll_id, ctx)
            if result ~= nil then
                return result
            end
        end
        return nil
    elseif kind == "Grid" then
        for i = #node.children, 1, -1 do
            local result = solved_scroll_hit_node(node.children[i].node, scroll_id, ctx)
            if result ~= nil then
                return result
            end
        end
        return nil
    elseif kind == "Pad" then
        return solved_scroll_hit_node(node.child, scroll_id, ctx)
    elseif kind == "Stack" then
        for i = #node.children, 1, -1 do
            local result = solved_scroll_hit_node(node.children[i], scroll_id, ctx)
            if result ~= nil then
                return result
            end
        end
        return nil
    elseif kind == "Clip" then
        push_clip(ctx, frame.x + ctx.tx, frame.y + ctx.ty, frame.w, frame.h)
        local result = solved_scroll_hit_node(node.child, scroll_id, ctx)
        pop_clip(ctx)
        return result
    elseif kind == "Transform" then
        push_transform(ctx, node.tx, node.ty)
        local result = solved_scroll_hit_node(node.child, scroll_id, ctx)
        pop_transform(ctx)
        return result
    elseif kind == "ScrollArea" then
        local next_scroll = (node.id ~= nil and node.id ~= "") and node.id or scroll_id
        local inset_h, inset_v = style_insets(node.style)
        push_clip(ctx, frame.x + inset_h + ctx.tx, frame.y + inset_v + ctx.ty, node.extent.viewport_w, node.extent.viewport_h)
        local result = solved_scroll_hit_node(node.child, next_scroll, ctx)
        pop_clip(ctx)
        if result ~= nil then
            return result
        end
        if frame_hit(ctx, frame) then
            return next_scroll
        end
        return nil
    elseif kind == "Panel" then
        return solved_scroll_hit_node(node.child, scroll_id, ctx)
    elseif kind == "Rect" or kind == "Text" or kind == "RuntimeText" or kind == "CustomPaint" or kind == "Spacer" then
        if scroll_id ~= nil and frame_hit(ctx, frame) then
            return scroll_id
        end
        return nil
    elseif kind == "Overlay" then
        return solved_scroll_hit_node(node.base, scroll_id, ctx)
    end

    error("ui.hit: unsupported SolvedUI node kind " .. tostring(kind), 2)
end

function hit.scroll_id_solved(node, frame, x, y, opts)
    local ctx = new_ctx(frame, x, y, opts)
    return solved_scroll_hit_node(node, nil, ctx)
end

function hit.scroll_id(node, frame, x, y, opts)
    return hit.scroll_id_solved(solve.node(node, frame, opts), frame, x, y, opts)
end

hit.MISS = MISS

-- Direct ASDL methods.
function T.UI.Node:hit(frame, x, y, opts)
    return hit.hit(self, frame, x, y, opts)
end

function T.UI.Node:hit_id(frame, x, y, opts)
    return hit.id(self, frame, x, y, opts)
end

function T.Facts.Hit:as_id()
    if self == MISS then
        return nil
    end
    return self.id
end

return hit
