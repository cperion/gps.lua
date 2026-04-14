local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local measure_mod = require("ui.measure")
local plan = require("ui.plan")

local T = ui_asdl.T
local Style = T.Style
local Layout = T.Layout
local View = T.View
local Interact = T.Interact

local M = {}

local measure_phase = measure_mod.phase
local text_layout_phase = measure_mod.text_layout_phase
local max0 = plan.max0
local should_clip = plan.should_clip
local node_box = plan.node_box
local flow_plan = plan.flow_plan
local flex_plan = plan.flex_plan
local grid_plan = plan.grid_plan

local function has_visual(visual)
    return visual.bg ~= 0 or visual.border_w > 0
end

local function make_op(kind, id, x, y, w, h, dx, dy, visual, text, cursor, scroll_axis, paint)
    return View.Op(kind, id, x, y, w, h, dx, dy, visual, text, cursor, scroll_axis, paint)
end

local function once_trip(op)
    local g, p, c = pvm.once(op)
    return { g, p, c }
end

local function render_trip(node, w, h, text_system)
    return M.phase(node, w, h, text_system)
end

local function measure_one(node, constraint, text_system)
    return pvm.one(measure_phase(node, constraint, text_system))
end

local function text_layout_one(style, constraint, text_system)
    return pvm.one(text_layout_phase(style, constraint, text_system))
end

local function append_visual_ops(parts, node, w, h)
    local box = node.box
    if has_visual(box.visual) then
        parts[#parts + 1] = once_trip(make_op(View.KRect, node.id, 0, 0, w, h, 0, 0, box.visual, nil, nil, nil, nil))
    end
end

local function append_input_ops(parts, id, role, cursor, w, h)
    if role == Interact.Passive then
        return
    end
    if role == Interact.HitTarget or role == Interact.ActivateTarget or role == Interact.EditTarget then
        parts[#parts + 1] = once_trip(make_op(View.KHit, id, 0, 0, w, h, 0, 0, nil, nil, nil, nil, nil))
    end
    if role == Interact.FocusTarget or role == Interact.ActivateTarget or role == Interact.EditTarget then
        parts[#parts + 1] = once_trip(make_op(View.KFocus, id, 0, 0, w, h, 0, 0, nil, nil, nil, nil, nil))
    end
    if cursor ~= T.Style.CursorDefault then
        parts[#parts + 1] = once_trip(make_op(View.KCursor, id, 0, 0, w, h, 0, 0, nil, nil, cursor, nil, nil))
    end
end

local function begin_container(parts, node, w, h)
    append_visual_ops(parts, node, w, h)

    local box = node.box
    local clipped = should_clip(box)
    if clipped then
        parts[#parts + 1] = once_trip(make_op(View.KPushClip, node.id, 0, 0, w, h, 0, 0, nil, nil, nil, nil, nil))
    end

    local pad = box.padding
    local cw = max0(w - pad.left - pad.right)
    local ch = max0(h - pad.top - pad.bottom)

    if pad.left ~= 0 or pad.top ~= 0 then
        parts[#parts + 1] = once_trip(make_op(View.KPushTx, node.id, 0, 0, 0, 0, pad.left, pad.top, nil, nil, nil, nil, nil))
    end

    return clipped, pad, cw, ch
end

local function end_container(parts, node, clipped, pad)
    if pad.left ~= 0 or pad.top ~= 0 then
        parts[#parts + 1] = once_trip(make_op(View.KPopTx, node.id, 0, 0, 0, 0, 0, 0, nil, nil, nil, nil, nil))
    end
    if clipped then
        parts[#parts + 1] = once_trip(make_op(View.KPopClip, node.id, 0, 0, 0, 0, 0, 0, nil, nil, nil, nil, nil))
    end
end

M.phase = pvm.phase("ui.render", {
    [Layout.WithInput] = function(self, w, h, text_system)
        local parts = {}
        local box = node_box(self.child)
        append_input_ops(parts, self.id, self.role, box.cursor, w, h)
        do
            local g, p, c = render_trip(self.child, w, h, text_system)
            parts[#parts + 1] = { g, p, c }
        end
        return pvm.concat_all(parts)
    end,

    [Layout.Leaf] = function(self, w, h, text_system)
        local parts = {}
        append_visual_ops(parts, self, w, h)

        if self.text ~= nil then
            local pad = self.box.padding
            local inner_w = max0(w - pad.left - pad.right)
            local inner_h = max0(h - pad.top - pad.bottom)
            local tl = text_layout_one(self.text, Layout.Constraint(inner_w, inner_h), text_system)
            parts[#parts + 1] = once_trip(make_op(
                View.KText,
                self.id,
                pad.left,
                pad.top,
                inner_w,
                inner_h,
                0,
                0,
                nil,
                tl,
                nil,
                nil,
                nil
            ))
        end

        if #parts == 0 then return pvm.empty() end
        return pvm.concat_all(parts)
    end,

    [Layout.Paint] = function(self, w, h, text_system)
        local parts = {}
        append_visual_ops(parts, self, w, h)

        if #self.paint.items > 0 then
            local pad = self.box.padding
            parts[#parts + 1] = once_trip(make_op(
                View.KPaint,
                self.id,
                pad.left,
                pad.top,
                max0(w - pad.left - pad.right),
                max0(h - pad.top - pad.bottom),
                0,
                0,
                nil,
                nil,
                nil,
                nil,
                self.paint
            ))
        end

        if #parts == 0 then return pvm.empty() end
        return pvm.concat_all(parts)
    end,

    [Layout.Scroll] = function(self, w, h, text_system)
        local parts = {}
        append_visual_ops(parts, self, w, h)

        local pad = self.box.padding
        local cw = max0(w - pad.left - pad.right)
        local ch = max0(h - pad.top - pad.bottom)
        local child_constraint
        if self.axis == Style.ScrollX then
            child_constraint = Layout.Constraint(math.huge, ch)
        elseif self.axis == Style.ScrollY then
            child_constraint = Layout.Constraint(cw, math.huge)
        else
            child_constraint = Layout.Constraint(math.huge, math.huge)
        end
        local child_size = measure_one(self.child, child_constraint, text_system)

        if pad.left ~= 0 or pad.top ~= 0 then
            parts[#parts + 1] = once_trip(make_op(View.KPushTx, self.id, 0, 0, 0, 0, pad.left, pad.top, nil, nil, nil, nil, nil))
        end
        parts[#parts + 1] = once_trip(make_op(View.KPushScroll, self.id, 0, 0, cw, ch, 0, 0, nil, nil, nil, self.axis, nil))
        do
            local g, p, c = render_trip(self.child, child_size.w, child_size.h, text_system)
            parts[#parts + 1] = { g, p, c }
        end
        parts[#parts + 1] = once_trip(make_op(View.KPopScroll, self.id, 0, 0, cw, ch, 0, 0, nil, nil, nil, self.axis, nil))
        if pad.left ~= 0 or pad.top ~= 0 then
            parts[#parts + 1] = once_trip(make_op(View.KPopTx, self.id, 0, 0, 0, 0, 0, 0, nil, nil, nil, nil, nil))
        end
        return pvm.concat_all(parts)
    end,

    [Layout.Flow] = function(self, w, h, text_system)
        local parts = {}
        local clipped, pad, cw, ch = begin_container(parts, self, w, h)
        local placements = flow_plan(self, cw, ch, function(node, child_constraint)
            return measure_one(node, child_constraint, text_system)
        end)

        for i = 1, #placements do
            local item = placements[i]
            parts[#parts + 1] = once_trip(make_op(View.KPushTx, item.node.id, 0, 0, 0, 0, item.dx, item.dy, nil, nil, nil, nil, nil))
            do
                local g, p, c = render_trip(item.node, item.w, item.h, text_system)
                parts[#parts + 1] = { g, p, c }
            end
            parts[#parts + 1] = once_trip(make_op(View.KPopTx, item.node.id, 0, 0, 0, 0, 0, 0, nil, nil, nil, nil, nil))
        end

        end_container(parts, self, clipped, pad)
        return pvm.concat_all(parts)
    end,

    [Layout.Flex] = function(self, w, h, text_system)
        local parts = {}
        local clipped, pad, cw, ch = begin_container(parts, self, w, h)
        local layout = flex_plan(self, cw, ch, function(node, child_constraint)
            return measure_one(node, child_constraint, text_system)
        end)

        for i = 1, #layout.items do
            local item = layout.items[i]
            parts[#parts + 1] = once_trip(make_op(View.KPushTx, item.node.id, 0, 0, 0, 0, item.dx, item.dy, nil, nil, nil, nil, nil))
            do
                local g, p, c = render_trip(item.node, item.w, item.h, text_system)
                parts[#parts + 1] = { g, p, c }
            end
            parts[#parts + 1] = once_trip(make_op(View.KPopTx, item.node.id, 0, 0, 0, 0, 0, 0, nil, nil, nil, nil, nil))
        end

        end_container(parts, self, clipped, pad)
        return pvm.concat_all(parts)
    end,

    [Layout.Grid] = function(self, w, h, text_system)
        local parts = {}
        local clipped, pad, cw, ch = begin_container(parts, self, w, h)
        local layout = grid_plan(self, cw, ch, function(node, child_constraint)
            return measure_one(node, child_constraint, text_system)
        end)

        for i = 1, #layout.items do
            local item = layout.items[i]
            parts[#parts + 1] = once_trip(make_op(View.KPushTx, item.node.id, 0, 0, 0, 0, item.dx, item.dy, nil, nil, nil, nil, nil))
            do
                local g, p, c = render_trip(item.node, item.w, item.h, text_system)
                parts[#parts + 1] = { g, p, c }
            end
            parts[#parts + 1] = once_trip(make_op(View.KPopTx, item.node.id, 0, 0, 0, 0, 0, 0, nil, nil, nil, nil, nil))
        end

        end_container(parts, self, clipped, pad)
        return pvm.concat_all(parts)
    end,
})

function M.root(node, env, text_system)
    return M.phase(node, env.vw, env.vh, text_system)
end

M.text = measure_mod.text
M.T = T

return M
