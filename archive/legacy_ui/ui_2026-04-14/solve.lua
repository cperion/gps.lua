-- ui/solve.lua
--
-- Layout-solving boundary.
--
-- This module compiles lowered `UI.Node` trees plus a viewport frame into a
-- solved tree with concrete frames. It is the architectural boundary that
-- consumes layout uncertainty so draw/hit do not re-solve layout on every walk.

local schema = require("ui.asdl")
local measure = require("ui.measure")
local flex = require("ui._flex")
local grid = require("ui._grid")

local T = schema.T

local solve = { T = T, schema = schema, measure = measure }

local math_max = math.max

local Constraint = T.Facts.Constraint
local Frame = T.Facts.Frame
local SpanExact = T.Facts.SpanExact
local SPAN_UNCONSTRAINED = T.Facts.SpanUnconstrained
local ScrollExtent = T.Facts.ScrollExtent

local SEmpty = T.SolvedUI.Empty
local SInteract = T.SolvedUI.Interact
local SFlex = T.SolvedUI.Flex
local SFlexItem = T.SolvedUI.FlexItem
local SGrid = T.SolvedUI.Grid
local SGridItem = T.SolvedUI.GridItem
local SPad = T.SolvedUI.Pad
local SStack = T.SolvedUI.Stack
local SClip = T.SolvedUI.Clip
local STransform = T.SolvedUI.Transform
local SScrollArea = T.SolvedUI.ScrollArea
local SPanel = T.SolvedUI.Panel
local SRect = T.SolvedUI.Rect
local SText = T.SolvedUI.Text
local SRuntimeText = T.SolvedUI.RuntimeText
local SCustomPaint = T.SolvedUI.CustomPaint
local SOverlay = T.SolvedUI.Overlay
local SSpacer = T.SolvedUI.Spacer

local SCROLL_X = T.Layout.ScrollX
local SCROLL_Y = T.Layout.ScrollY
local SCROLL_BOTH = T.Layout.ScrollBoth

local function mkframe(x, y, w, h)
    return Frame(x, y, w, h)
end

local function intern_frame(frame)
    return Frame(frame.x, frame.y, frame.w, frame.h)
end

local function style_insets(style)
    local h = (style.pad_h or 0) + (style.border_w or 0)
    local v = (style.pad_v or 0) + (style.border_w or 0)
    return h, v
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
    }
end

local function resolve_local_frame(node, outer, measure_opts)
    local m = measure.measure(node, measure.exact_constraint_from_frame(outer), measure_opts)
    return mkframe(outer.x, outer.y, m.used_w, m.used_h), m
end

local function exact_or_atmost(px, exact)
    if exact then
        return measure.exact(px)
    end
    return measure.at_most(px)
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

local solve_node_inner

local function solve_child(node, frame, measure_opts)
    return solve_node_inner(node, frame, measure_opts)
end

local function solve_flex(node, outer, measure_opts)
    local placed, frame = flex.layout(node, outer, measure_opts, measure)
    local children = {}
    for i = 1, #placed do
        children[i] = SFlexItem(solve_child(placed[i].node, intern_frame(placed[i].frame), measure_opts))
    end
    return SFlex(intern_frame(frame), children)
end

local function solve_grid(node, outer, measure_opts)
    local frame = resolve_local_frame(node, outer, measure_opts)
    local placed = grid.layout_children(node, frame, measure, measure_opts, mkframe)
    local children = {}
    for i = 1, #placed do
        children[i] = SGridItem(solve_child(placed[i].node, intern_frame(placed[i].frame), measure_opts))
    end
    return SGrid(frame, children)
end

solve_node_inner = function(node, outer, measure_opts)
    local kind = node.kind

    if kind == "Empty" then
        return SEmpty
    elseif kind == "Interact" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        return SInteract(node.key_id, node.hit_id, node.press_id, node.focus_id, frame, solve_child(node.child, frame, measure_opts))
    elseif kind == "Flex" then
        return solve_flex(node, outer, measure_opts)
    elseif kind == "Grid" then
        return solve_grid(node, outer, measure_opts)
    elseif kind == "Pad" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        local child_frame = mkframe(
            frame.x + node.insets.l,
            frame.y + node.insets.t,
            math_max(0, frame.w - node.insets.l - node.insets.r),
            math_max(0, frame.h - node.insets.t - node.insets.b))
        return SPad(frame, solve_child(node.child, child_frame, measure_opts))
    elseif kind == "Stack" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        local children = {}
        for i = 1, #node.children do
            children[i] = solve_child(node.children[i], frame, measure_opts)
        end
        return SStack(frame, children)
    elseif kind == "Clip" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        return SClip(frame, solve_child(node.child, frame, measure_opts))
    elseif kind == "Transform" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        return STransform(frame, node.tx, node.ty, solve_child(node.child, frame, measure_opts))
    elseif kind == "ScrollArea" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        local inset_h, inset_v = style_insets(node.style)
        local viewport_w = math_max(0, frame.w - inset_h * 2)
        local viewport_h = math_max(0, frame.h - inset_v * 2)
        local viewport_x = frame.x + inset_h
        local viewport_y = frame.y + inset_v
        local child_m = measure.measure(node.child, scroll_child_constraint(node, viewport_w, viewport_h), measure_opts)
        local content_w = (node.axis == SCROLL_X or node.axis == SCROLL_BOTH) and math_max(viewport_w, child_m.used_w) or viewport_w
        local content_h = (node.axis == SCROLL_Y or node.axis == SCROLL_BOTH) and math_max(viewport_h, child_m.used_h) or viewport_h
        local child_frame = mkframe(viewport_x - node.scroll_x, viewport_y - node.scroll_y, content_w, content_h)
        return SScrollArea(
            node.id,
            frame,
            ScrollExtent(content_w, content_h, viewport_w, viewport_h),
            node.scroll_x,
            node.scroll_y,
            node.style,
            solve_child(node.child, child_frame, measure_opts))
    elseif kind == "Panel" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        local inset_h, inset_v = style_insets(node.style)
        local child_frame = mkframe(
            frame.x + inset_h,
            frame.y + inset_v,
            math_max(0, frame.w - inset_h * 2),
            math_max(0, frame.h - inset_v * 2))
        return SPanel(node.tag, frame, node.style, solve_child(node.child, child_frame, measure_opts))
    elseif kind == "Rect" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        return SRect(node.tag, frame, node.style)
    elseif kind == "Text" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        return SText(node.tag, frame, node.style, node.text)
    elseif kind == "RuntimeText" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        return SRuntimeText(node.tag, frame, node.style, node.text)
    elseif kind == "CustomPaint" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        return SCustomPaint(node.tag, frame, node.paint)
    elseif kind == "Overlay" then
        local base = solve_child(node.base, outer, measure_opts)
        return SOverlay(base, node.overlay)
    elseif kind == "Spacer" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        return SSpacer(frame)
    end

    error("ui.solve: unsupported UI node kind " .. tostring(kind), 2)
end

function solve.node(node, frame, opts)
    local measure_opts = build_measure_opts(opts)
    return solve_node_inner(node, frame, measure_opts)
end

function T.UI.Node:solve(frame, opts)
    return solve.node(self, frame, opts)
end

return solve
