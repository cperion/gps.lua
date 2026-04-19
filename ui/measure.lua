local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local plan = require("ui.plan")
local text = require("ui.text")

local T = ui_asdl.T
local Core = T.Core
local Style = T.Style
local Layout = T.Layout

local M = {}

local HUGE = plan.HUGE
local finite = plan.finite
local max0 = plan.max0
local margin_px = plan.margin_px
local flow_plan = plan.flow_plan
local flex_plan = plan.flex_plan
local grid_plan = plan.grid_plan

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

local function resolve_flow_width(sizing, fill_w, hug_w, parent_limit)
    local cls = pvm.classof(sizing)
    if sizing == Layout.SAuto then
        if finite(parent_limit) then
            return fill_w
        end
        return hug_w
    end
    if sizing == Layout.SHug then
        return hug_w
    end
    if sizing == Layout.SFill then
        if finite(parent_limit) then
            return parent_limit
        end
        return hug_w
    end
    if cls == Layout.SFixed then
        return sizing.px
    end
    if cls == Layout.SFrac then
        if finite(parent_limit) then
            return parent_limit * sizing.value
        end
        return hug_w
    end
    return hug_w
end

local text_layout_phase = pvm.phase("ui.text_layout", function(style, constraint, text_system)
    return text.layout(style, constraint, text_system)
end, {
    args_cache = "last",
})

local function resolve_fill_when_auto(sizing, fill_v, hug_v, parent_limit)
    local cls = pvm.classof(sizing)
    if sizing == Layout.SAuto then
        if finite(parent_limit) then return fill_v end
        return hug_v
    end
    if sizing == Layout.SHug then return hug_v end
    if sizing == Layout.SFill then
        if finite(parent_limit) then return parent_limit end
        return hug_v
    end
    if cls == Layout.SFixed then return sizing.px end
    if cls == Layout.SFrac then
        if finite(parent_limit) then return parent_limit * sizing.value end
        return hug_v
    end
    return hug_v
end

local function scroll_child_constraint(axis, inner_w, inner_h)
    if axis == Style.ScrollX then
        return Layout.Constraint(HUGE, inner_h)
    elseif axis == Style.ScrollY then
        return Layout.Constraint(inner_w, HUGE)
    end
    return Layout.Constraint(HUGE, HUGE)
end

local measure_phase
local content_cache = setmetatable({}, { __mode = "k" })

local function content_map(store)
    if store == nil then return nil end
    local map = content_cache[store]
    if map ~= nil then return map end
    map = {}
    local items = store.items or store
    for i = 1, #items do
        local item = items[i]
        map[item.id] = item.content
    end
    content_cache[store] = map
    return map
end

local function content_string(store, id)
    if store == nil or id == nil or id == Core.NoId then return "" end
    local map = content_map(store)
    return map[id] or ""
end

local function leaf_text_style(text_spec, content_store)
    if text_spec == nil then return nil end
    local cls = pvm.classof(text_spec)
    if cls == Layout.TextLiteral then
        return text_spec.style
    end
    if cls == Layout.TextBinding then
        local style = text_spec.style
        return Layout.TextStyle(
            style.font_id,
            style.font_size,
            style.font_weight,
            style.fg,
            style.align,
            style.leading,
            style.tracking,
            content_string(content_store, text_spec.content_id)
        )
    end
    return text_spec
end

local function measure_one(node, constraint, text_system, content_store)
    return pvm.one(measure_phase(node, constraint, text_system, content_store))
end

local function text_layout_one(style, constraint, text_system)
    return pvm.one(text_layout_phase(style, constraint, text_system))
end

local function leaf_intrinsic(node, constraint, text_system, content_store)
    local pad = node.box.padding
    local pad_h = pad.left + pad.right
    local pad_v = pad.top + pad.bottom
    local inner_w = finite(constraint.max_w) and max0(constraint.max_w - pad_h) or HUGE

    local content_w, content_h, baseline = 0, 0, 0
    local text_style = leaf_text_style(node.text, content_store)
    if text_style ~= nil then
        local tl = text_layout_one(text_style, Layout.Constraint(inner_w, HUGE), text_system)
        content_w = tl.measured_w
        content_h = tl.measured_h
        baseline = tl.baseline + pad.top
    end

    return content_w + pad_h, content_h + pad_v, baseline
end

local function measure_leaf(self, constraint, text_system, content_store)
    local box = self.box
    local intrinsic_w, intrinsic_h, baseline = leaf_intrinsic(self, constraint, text_system, content_store)
    local w = resolve_sizing(box.w, intrinsic_w, constraint.max_w)
    local h = resolve_sizing(box.h, intrinsic_h, constraint.max_h)

    w = apply_minmax(w, box.min_w, box.max_w, constraint.max_w)
    h = apply_minmax(h, box.min_h, box.max_h, constraint.max_h)

    local margin = box.margin
    w = w + margin_px(margin.left) + margin_px(margin.right)
    h = h + margin_px(margin.top) + margin_px(margin.bottom)

    return pvm.once(Layout.Size(w, h, baseline))
end

local function measure_paint(self, constraint)
    local box = self.box
    local pad = box.padding
    local intrinsic_w = pad.left + pad.right
    local intrinsic_h = pad.top + pad.bottom
    local w = resolve_sizing(box.w, intrinsic_w, constraint.max_w)
    local h = resolve_sizing(box.h, intrinsic_h, constraint.max_h)

    w = apply_minmax(w, box.min_w, box.max_w, constraint.max_w)
    h = apply_minmax(h, box.min_h, box.max_h, constraint.max_h)

    local margin = box.margin
    w = w + margin_px(margin.left) + margin_px(margin.right)
    h = h + margin_px(margin.top) + margin_px(margin.bottom)

    return pvm.once(Layout.Size(w, h, 0))
end

local function measure_flow(self, constraint, text_system, content_store)
    local box = self.box
    local pad = box.padding
    local pad_h = pad.left + pad.right
    local pad_v = pad.top + pad.bottom
    local inner_w = finite(constraint.max_w) and max0(constraint.max_w - pad_h) or HUGE
    local inner_h = finite(constraint.max_h) and max0(constraint.max_h - pad_v) or HUGE

    local placements, max_outer_w, used_h = flow_plan(self, inner_w, inner_h, function(node, child_constraint)
        return measure_one(node, child_constraint, text_system, content_store)
    end)
    local hug_w = max_outer_w + pad_h
    local fill_w = finite(constraint.max_w) and constraint.max_w or hug_w
    local intrinsic_h = used_h + pad_v

    local w = resolve_flow_width(box.w, fill_w, hug_w, constraint.max_w)
    local h = resolve_sizing(box.h, intrinsic_h, constraint.max_h)

    w = apply_minmax(w, box.min_w, box.max_w, constraint.max_w)
    h = apply_minmax(h, box.min_h, box.max_h, constraint.max_h)

    local margin = box.margin
    w = w + margin_px(margin.left) + margin_px(margin.right)
    h = h + margin_px(margin.top) + margin_px(margin.bottom)

    local baseline = 0
    if #placements > 0 then
        baseline = placements[1].dy + placements[1].size.baseline
    end

    return pvm.once(Layout.Size(w, h, baseline))
end

local function measure_flex(self, constraint, text_system, content_store)
    local box = self.box
    local pad = box.padding
    local pad_h = pad.left + pad.right
    local pad_v = pad.top + pad.bottom
    local inner_w = finite(constraint.max_w) and max0(constraint.max_w - pad_h) or HUGE
    local inner_h = finite(constraint.max_h) and max0(constraint.max_h - pad_v) or HUGE

    local layout = flex_plan(self, inner_w, inner_h, function(node, child_constraint)
        return measure_one(node, child_constraint, text_system, content_store)
    end)
    local intrinsic_w, intrinsic_h, baseline

    if self.axis == Layout.LRow then
        intrinsic_w = layout.base_main_extent + pad_h
        intrinsic_h = layout.cross_extent + pad_v
        baseline = 0
        for i = 1, #layout.items do
            local item = layout.items[i]
            if item.line == 1 then
                local b = item.dy + item.baseline
                if b > baseline then baseline = b end
            end
        end
    else
        intrinsic_w = layout.cross_extent + pad_h
        intrinsic_h = layout.base_main_extent + pad_v
        baseline = 0
    end

    local w = resolve_sizing(box.w, intrinsic_w, constraint.max_w)
    local h = resolve_sizing(box.h, intrinsic_h, constraint.max_h)
    w = apply_minmax(w, box.min_w, box.max_w, constraint.max_w)
    h = apply_minmax(h, box.min_h, box.max_h, constraint.max_h)

    local margin = box.margin
    w = w + margin_px(margin.left) + margin_px(margin.right)
    h = h + margin_px(margin.top) + margin_px(margin.bottom)

    return pvm.once(Layout.Size(w, h, baseline))
end

local function measure_grid(self, constraint, text_system, content_store)
    local box = self.box
    local pad = box.padding
    local pad_h = pad.left + pad.right
    local pad_v = pad.top + pad.bottom
    local inner_w = finite(constraint.max_w) and max0(constraint.max_w - pad_h) or HUGE
    local inner_h = finite(constraint.max_h) and max0(constraint.max_h - pad_v) or HUGE

    local layout = grid_plan(self, inner_w, inner_h, function(node, child_constraint)
        return measure_one(node, child_constraint, text_system, content_store)
    end)
    local intrinsic_w = layout.used_w + pad_h
    local intrinsic_h = layout.used_h + pad_v

    local w = resolve_sizing(box.w, intrinsic_w, constraint.max_w)
    local h = resolve_sizing(box.h, intrinsic_h, constraint.max_h)
    w = apply_minmax(w, box.min_w, box.max_w, constraint.max_w)
    h = apply_minmax(h, box.min_h, box.max_h, constraint.max_h)

    local margin = box.margin
    w = w + margin_px(margin.left) + margin_px(margin.right)
    h = h + margin_px(margin.top) + margin_px(margin.bottom)

    return pvm.once(Layout.Size(w, h, 0))
end

local function measure_scroll(self, constraint, text_system, content_store)
    local box = self.box
    local pad = box.padding
    local pad_h = pad.left + pad.right
    local pad_v = pad.top + pad.bottom
    local inner_w = finite(constraint.max_w) and max0(constraint.max_w - pad_h) or HUGE
    local inner_h = finite(constraint.max_h) and max0(constraint.max_h - pad_v) or HUGE
    local child = measure_one(self.child, scroll_child_constraint(self.axis, inner_w, inner_h), text_system, content_store)
    local intrinsic_w = child.w + pad_h
    local intrinsic_h = child.h + pad_v

    local fill_w = finite(constraint.max_w) and constraint.max_w or intrinsic_w
    local fill_h = finite(constraint.max_h) and constraint.max_h or intrinsic_h
    local w, h

    if self.axis == Style.ScrollY then
        w = resolve_fill_when_auto(box.w, fill_w, intrinsic_w, constraint.max_w)
        h = resolve_sizing(box.h, intrinsic_h, constraint.max_h)
    elseif self.axis == Style.ScrollX then
        w = resolve_sizing(box.w, intrinsic_w, constraint.max_w)
        h = resolve_fill_when_auto(box.h, fill_h, intrinsic_h, constraint.max_h)
    else
        w = resolve_fill_when_auto(box.w, fill_w, intrinsic_w, constraint.max_w)
        h = resolve_fill_when_auto(box.h, fill_h, intrinsic_h, constraint.max_h)
    end

    w = apply_minmax(w, box.min_w, box.max_w, constraint.max_w)
    h = apply_minmax(h, box.min_h, box.max_h, constraint.max_h)

    local margin = box.margin
    w = w + margin_px(margin.left) + margin_px(margin.right)
    h = h + margin_px(margin.top) + margin_px(margin.bottom)

    return pvm.once(Layout.Size(w, h, child.baseline + pad.top))
end

measure_phase = pvm.phase("ui.measure", {
    [Layout.Leaf] = function(self, constraint, text_system, content_store)
        return measure_leaf(self, constraint, text_system, content_store)
    end,

    [Layout.Flow] = function(self, constraint, text_system, content_store)
        return measure_flow(self, constraint, text_system, content_store)
    end,

    [Layout.Paint] = function(self, constraint, text_system, content_store)
        return measure_paint(self, constraint, text_system)
    end,

    [Layout.Scroll] = function(self, constraint, text_system, content_store)
        return measure_scroll(self, constraint, text_system, content_store)
    end,

    [Layout.Flex] = function(self, constraint, text_system, content_store)
        return measure_flex(self, constraint, text_system, content_store)
    end,

    [Layout.Grid] = function(self, constraint, text_system, content_store)
        return measure_grid(self, constraint, text_system, content_store)
    end,

    [Layout.WithInput] = function(self, constraint, text_system, content_store)
        return pvm.once(pvm.one(measure_phase(self.child, constraint, text_system, content_store)))
    end,

    [Layout.WithDragSource] = function(self, constraint, text_system, content_store)
        return pvm.once(pvm.one(measure_phase(self.child, constraint, text_system, content_store)))
    end,

    [Layout.WithDropTarget] = function(self, constraint, text_system, content_store)
        return pvm.once(pvm.one(measure_phase(self.child, constraint, text_system, content_store)))
    end,

    [Layout.WithDropSlot] = function(self, constraint, text_system, content_store)
        return pvm.once(pvm.one(measure_phase(self.child, constraint, text_system, content_store)))
    end,
}, {
    args_cache = "last",
})

function M.root(node, max_w, max_h, text_system, content_store)
    return measure_phase(node, Layout.Constraint(max_w, max_h), text_system, content_store)
end

M.phase = measure_phase
M.text_layout_phase = text_layout_phase
M.text = text
M.T = T

return M
