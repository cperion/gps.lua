local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Core = T.Core
local Style = T.Style
local Interact = T.Interact
local Solve = T.Solve

local M = {}

local DEFAULT_DRAG_THRESHOLD_PX = 6

local function max0(n)
    if n < 0 then return 0 end
    return n
end

local function focus_slot(report, id)
    if id == nil or id == Core.NoId then return 0 end
    for i = 1, #report.focusables do
        if report.focusables[i].id == id then
            return report.focusables[i].slot
        end
    end
    return 0
end

local function focus_move_id(report, current_id, dir)
    local n = #report.focusables
    if n == 0 then return Core.NoId end

    local current_slot = focus_slot(report, current_id)
    local next_slot
    if current_slot == 0 then
        next_slot = dir and dir < 0 and n or 1
    else
        next_slot = current_slot + (dir or 1)
        if next_slot < 1 then next_slot = n end
        if next_slot > n then next_slot = 1 end
    end
    return report.focusables[next_slot].id
end

local function emit_hover(events, report)
    if report.hover_id == Core.NoId then
        events[#events + 1] = Interact.ClearHover
    else
        events[#events + 1] = Interact.SetHover(report.hover_id)
    end
end

local function scroll_box(report, id)
    if id == nil or id == Core.NoId then return nil end
    for i = 1, #report.scrollables do
        local box = report.scrollables[i]
        if box.id == id then return box end
    end
    return nil
end

local function scroll_axis(report, id)
    local box = scroll_box(report, id)
    if box == nil then return Style.ScrollBoth end
    return box.axis
end

local function scroll_limits(report, id)
    local box = scroll_box(report, id)
    if box == nil then return 0, 0 end
    local max_x = box.max_x
    local max_y = box.max_y
    if max_x == nil then max_x = max0((box.content_w or box.w or 0) - (box.w or 0)) end
    if max_y == nil then max_y = max0((box.content_h or box.h or 0) - (box.h or 0)) end
    return max_x, max_y
end

local function clamp_scroll_position(report, id, x, y)
    local max_x, max_y = scroll_limits(report, id)
    if x < 0 then x = 0 elseif x > max_x then x = max_x end
    if y < 0 then y = 0 elseif y > max_y then y = max_y end
    return x, y
end

local function point_inside_box(box, x, y)
    return x >= box.x and y >= box.y and x < box.x + box.w and y < box.y + box.h
end

local function topmost_box_id(boxes, x, y)
    for i = #boxes, 1, -1 do
        local box = boxes[i]
        if point_inside_box(box, x, y) then
            return box.id
        end
    end
    return Core.NoId
end

local function drag_source_at(report, x, y)
    return topmost_box_id(report.drag_sources, x, y)
end

local function drop_target_at(report, x, y)
    return topmost_box_id(report.drop_targets, x, y)
end

local function drop_slot_at(report, x, y)
    return topmost_box_id(report.drop_slots, x, y)
end

local function drag_threshold_sq(opts)
    local px = DEFAULT_DRAG_THRESHOLD_PX
    if opts ~= nil and opts.drag_threshold_px ~= nil then
        px = opts.drag_threshold_px
    end
    return px * px
end

local function dist_sq(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return dx * dx + dy * dy
end

local function classify_events(raw, model, report, opts)
    local cls = pvm.classof(raw)
    local events = {}

    if cls == Interact.PointerMoved then
        events[#events + 1] = Interact.SetPointer(raw.x, raw.y)
        emit_hover(events, report)

        local drag = model.drag
        local drag_cls = pvm.classof(drag)
        if drag_cls == Interact.DragPending then
            if dist_sq(drag.start_x, drag.start_y, raw.x, raw.y) >= drag_threshold_sq(opts) then
                local over_target_id = drop_target_at(report, raw.x, raw.y)
                local over_slot_id = drop_slot_at(report, raw.x, raw.y)
                events[#events + 1] = Interact.SetDragging(drag.source_id, drag.start_x, drag.start_y, raw.x, raw.y, over_target_id, over_slot_id)
                events[#events + 1] = Interact.DragStarted(drag.source_id, drag.start_x, drag.start_y)
                events[#events + 1] = Interact.DragMoved(drag.source_id, raw.x, raw.y, over_target_id, over_slot_id)
            end
        elseif drag_cls == Interact.Dragging then
            local over_target_id = drop_target_at(report, raw.x, raw.y)
            local over_slot_id = drop_slot_at(report, raw.x, raw.y)
            events[#events + 1] = Interact.SetDragging(drag.source_id, drag.start_x, drag.start_y, raw.x, raw.y, over_target_id, over_slot_id)
            events[#events + 1] = Interact.DragMoved(drag.source_id, raw.x, raw.y, over_target_id, over_slot_id)
        end

        return events
    end

    if cls == Interact.PointerPressed then
        events[#events + 1] = Interact.SetPointer(raw.x, raw.y)
        emit_hover(events, report)

        if raw.button == Interact.BtnLeft then
            if report.hover_id ~= Core.NoId then
                events[#events + 1] = Interact.SetPressed(report.hover_id)
                events[#events + 1] = Interact.SetFocus(report.hover_id)
            else
                events[#events + 1] = Interact.ClearPressed
                events[#events + 1] = Interact.ClearFocus
            end

            local source_id = drag_source_at(report, raw.x, raw.y)
            if source_id ~= Core.NoId then
                events[#events + 1] = Interact.SetDragPending(source_id, raw.x, raw.y)
            else
                events[#events + 1] = Interact.ClearDrag
            end
        end

        return events
    end

    if cls == Interact.PointerReleased then
        events[#events + 1] = Interact.SetPointer(raw.x, raw.y)
        emit_hover(events, report)

        if raw.button == Interact.BtnLeft then
            local drag = model.drag
            local drag_cls = pvm.classof(drag)

            if drag_cls == Interact.Dragging then
                local over_target_id = drop_target_at(report, raw.x, raw.y)
                local over_slot_id = drop_slot_at(report, raw.x, raw.y)
                events[#events + 1] = Interact.DragDropped(drag.source_id, raw.x, raw.y, over_target_id, over_slot_id)
                events[#events + 1] = Interact.ClearDrag
                events[#events + 1] = Interact.ClearPressed
            elseif drag_cls == Interact.DragPending then
                if model.pressed_id ~= Core.NoId and report.hover_id == model.pressed_id then
                    events[#events + 1] = Interact.Activate(model.pressed_id)
                end
                events[#events + 1] = Interact.ClearDrag
                events[#events + 1] = Interact.ClearPressed
            else
                if model.pressed_id ~= Core.NoId and report.hover_id == model.pressed_id then
                    events[#events + 1] = Interact.Activate(model.pressed_id)
                end
                events[#events + 1] = Interact.ClearPressed
            end
        end

        return events
    end

    if cls == Interact.WheelMoved then
        events[#events + 1] = Interact.SetPointer(raw.x, raw.y)
        emit_hover(events, report)
        if report.scroll_id ~= Core.NoId then
            local axis = scroll_axis(report, report.scroll_id)
            local dx, dy = raw.dx, raw.dy
            if axis == Style.ScrollX then
                dy = 0
            elseif axis == Style.ScrollY then
                dx = 0
            end
            if dx ~= 0 or dy ~= 0 then
                local cur_x, cur_y = 0, 0
                for i = 1, #model.scrolls do
                    local s = model.scrolls[i]
                    if s.id == report.scroll_id then
                        cur_x, cur_y = s.x, s.y
                        break
                    end
                end
                local next_x, next_y = clamp_scroll_position(report, report.scroll_id, cur_x + dx, cur_y + dy)
                dx = next_x - cur_x
                dy = next_y - cur_y
                if dx ~= 0 or dy ~= 0 then
                    events[#events + 1] = Interact.ScrollBy(report.scroll_id, dx, dy)
                end
            end
        end
        return events
    end

    if raw == Interact.FocusNext then
        local id = focus_move_id(report, model.focus_id, 1)
        if id ~= Core.NoId then
            events[#events + 1] = Interact.SetFocus(id)
        end
        return events
    end

    if raw == Interact.FocusPrev then
        local id = focus_move_id(report, model.focus_id, -1)
        if id ~= Core.NoId then
            events[#events + 1] = Interact.SetFocus(id)
        end
        return events
    end

    if raw == Interact.ActivateFocus then
        if model.focus_id ~= Core.NoId then
            events[#events + 1] = Interact.Activate(model.focus_id)
        end
        return events
    end

    if raw == Interact.CancelPointer then
        local drag = model.drag
        local drag_cls = pvm.classof(drag)
        if drag_cls == Interact.DragPending or drag_cls == Interact.Dragging then
            events[#events + 1] = Interact.DragCancelled(drag.source_id)
            events[#events + 1] = Interact.ClearDrag
        end
        if model.pressed_id ~= Core.NoId then
            events[#events + 1] = Interact.ClearPressed
        end
        return events
    end

    return events
end

local classify_phase = pvm.phase("ui.interact.classify", {
    [Interact.PointerMoved] = function(self, model, report, opts)
        return pvm.seq(classify_events(self, model, report, opts))
    end,

    [Interact.PointerPressed] = function(self, model, report, opts)
        return pvm.seq(classify_events(self, model, report, opts))
    end,

    [Interact.PointerReleased] = function(self, model, report, opts)
        return pvm.seq(classify_events(self, model, report, opts))
    end,

    [Interact.WheelMoved] = function(self, model, report, opts)
        return pvm.seq(classify_events(self, model, report, opts))
    end,

    [Interact.FocusNext] = function(self, model, report, opts)
        return pvm.seq(classify_events(self, model, report, opts))
    end,

    [Interact.FocusPrev] = function(self, model, report, opts)
        return pvm.seq(classify_events(self, model, report, opts))
    end,

    [Interact.ActivateFocus] = function(self, model, report, opts)
        return pvm.seq(classify_events(self, model, report, opts))
    end,

    [Interact.CancelPointer] = function(self, model, report, opts)
        return pvm.seq(classify_events(self, model, report, opts))
    end,
}, {
    args_cache = "none",
})

local function scroll_index(scrolls, id)
    for i = 1, #scrolls do
        if scrolls[i].id == id then return i end
    end
    return 0
end

local function update_scrolls(scrolls, id, dx, dy)
    local i = scroll_index(scrolls, id)
    local out = {}
    for j = 1, #scrolls do out[j] = scrolls[j] end
    if i == 0 then
        out[#out + 1] = Solve.Scroll(id, dx, dy)
    else
        local s = scrolls[i]
        out[i] = Solve.Scroll(id, s.x + dx, s.y + dy)
    end
    return out
end

local function clamp_model_scrolls(model, report)
    if report == nil or #model.scrolls == 0 then
        return model
    end

    local changed = false
    local out = {}
    for i = 1, #model.scrolls do
        local s = model.scrolls[i]
        local x, y = clamp_scroll_position(report, s.id, s.x, s.y)
        if x ~= s.x or y ~= s.y then
            changed = true
            out[i] = Solve.Scroll(s.id, x, y)
        else
            out[i] = s
        end
    end

    if not changed then return model end
    return pvm.with(model, { scrolls = out })
end

local function apply_event(model, event, report)
    local cls = pvm.classof(event)
    if cls == Interact.SetPointer then
        return pvm.with(model, { pointer_x = event.x, pointer_y = event.y })
    end
    if cls == Interact.SetHover then
        return pvm.with(model, { hover_id = event.id })
    end
    if event == Interact.ClearHover then
        return pvm.with(model, { hover_id = Core.NoId })
    end
    if cls == Interact.SetFocus then
        return pvm.with(model, { focus_id = event.id })
    end
    if event == Interact.ClearFocus then
        return pvm.with(model, { focus_id = Core.NoId })
    end
    if cls == Interact.SetPressed then
        return pvm.with(model, { pressed_id = event.id })
    end
    if event == Interact.ClearPressed then
        return pvm.with(model, { pressed_id = Core.NoId })
    end
    if cls == Interact.SetDragPending then
        return pvm.with(model, { drag = Interact.DragPending(event.source_id, event.start_x, event.start_y) })
    end
    if cls == Interact.SetDragging then
        return pvm.with(model, { drag = Interact.Dragging(event.source_id, event.start_x, event.start_y, event.x, event.y, event.over_target_id, event.over_slot_id) })
    end
    if event == Interact.ClearDrag then
        return pvm.with(model, { drag = Interact.NoDrag })
    end
    if cls == Interact.ScrollBy then
        local next_model = pvm.with(model, { scrolls = update_scrolls(model.scrolls, event.id, event.dx, event.dy) })
        return clamp_model_scrolls(next_model, report)
    end
    return model
end

function M.model(opts)
    opts = opts or {}
    return Interact.Model(
        opts.pointer_x or 0,
        opts.pointer_y or 0,
        opts.hover_id or Core.NoId,
        opts.focus_id or Core.NoId,
        opts.pressed_id or Core.NoId,
        opts.drag or Interact.NoDrag,
        opts.scrolls or {}
    )
end

function M.hover_state(report)
    if report.hover_id == Core.NoId then
        return Interact.NoHover
    end
    return Interact.Hovered(report.hover_id)
end

function M.focus_state(report, focused_id)
    if focused_id == nil or focused_id == Core.NoId then
        return Interact.NoFocus
    end
    local slot = focus_slot(report, focused_id)
    if slot == 0 then return Interact.NoFocus end
    return Interact.Focused(focused_id, slot)
end

function M.find_focus_slot(report, id)
    return focus_slot(report, id)
end

function M.focus_move(report, current_id, dir)
    return focus_move_id(report, current_id, dir)
end

function M.drag_source_at(report, x, y)
    return drag_source_at(report, x, y)
end

function M.drop_target_at(report, x, y)
    return drop_target_at(report, x, y)
end

function M.drop_slot_at(report, x, y)
    return drop_slot_at(report, x, y)
end

function M.scroll_offset(model, id)
    for i = 1, #model.scrolls do
        local s = model.scrolls[i]
        if s.id == id then return s.x, s.y end
    end
    return 0, 0
end

function M.scroll_box(report, id)
    return scroll_box(report, id)
end

function M.scroll_limits(report, id)
    return scroll_limits(report, id)
end

function M.clamp_scroll_position(report, id, x, y)
    return clamp_scroll_position(report, id, x, y)
end

function M.clamp_model(model, report)
    return clamp_model_scrolls(model, report)
end

function M.classify(raw, model, report, opts)
    return classify_phase(raw, model, report, opts)
end

function M.apply(model, event, report)
    return apply_event(model, event, report)
end

function M.apply_all(model, events_or_g, p, c, report)
    if p == nil and c == nil and type(events_or_g) == "table" and not pvm.classof(events_or_g) then
        for i = 1, #events_or_g do
            model = apply_event(model, events_or_g[i], report)
        end
        return model
    end

    local arr = pvm.drain(events_or_g, p, c)
    for i = 1, #arr do
        model = apply_event(model, arr[i], report)
    end
    return model
end

function M.step(model, report, raw, opts)
    local events = pvm.drain(classify_phase(raw, model, report, opts))
    return M.apply_all(model, events, nil, nil, report), events
end

function M.pointer_moved(x, y)
    return Interact.PointerMoved(x, y)
end

function M.pointer_pressed(button, x, y)
    return Interact.PointerPressed(button, x, y)
end

function M.pointer_released(button, x, y)
    return Interact.PointerReleased(button, x, y)
end

function M.wheel_moved(dx, dy, x, y)
    return Interact.WheelMoved(dx, dy, x, y)
end

function M.focus_next()
    return Interact.FocusNext
end

function M.focus_prev()
    return Interact.FocusPrev
end

function M.activate_focus()
    return Interact.ActivateFocus
end

function M.cancel_pointer()
    return Interact.CancelPointer
end

function M.button_from_love(button)
    if button == 2 then return Interact.BtnRight end
    if button == 3 then return Interact.BtnMiddle end
    return Interact.BtnLeft
end

function M.state(report, focused_id, drag)
    return Interact.State(
        M.hover_state(report),
        M.focus_state(report, focused_id),
        drag or Interact.NoDrag
    )
end

M.classify_phase = classify_phase
M.T = T

return M
