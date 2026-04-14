local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Core = T.Core
local Style = T.Style
local Interact = T.Interact
local Solve = T.Solve

local M = {}

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

local function emit_hover(parts, report)
    if report.hover_id == Core.NoId then
        parts[#parts + 1] = { pvm.once(Interact.ClearHover) }
    else
        parts[#parts + 1] = { pvm.once(Interact.SetHover(report.hover_id)) }
    end
end

local function scroll_axis(report, id)
    if id == nil or id == Core.NoId then return Style.ScrollBoth end
    for i = 1, #report.scrollables do
        local box = report.scrollables[i]
        if box.id == id then return box.axis end
    end
    return Style.ScrollBoth
end

local classify_phase = pvm.phase("ui.interact.classify", {
    [Interact.PointerMoved] = function(self, model, report)
        local parts = {
            { pvm.once(Interact.SetPointer(self.x, self.y)) },
        }
        emit_hover(parts, report)
        return pvm.concat_all(parts)
    end,

    [Interact.PointerPressed] = function(self, model, report)
        local parts = {
            { pvm.once(Interact.SetPointer(self.x, self.y)) },
        }
        emit_hover(parts, report)
        if self.button == Interact.BtnLeft then
            if report.hover_id ~= Core.NoId then
                parts[#parts + 1] = { pvm.once(Interact.SetFocus(report.hover_id)) }
                parts[#parts + 1] = { pvm.once(Interact.Activate(report.hover_id)) }
            else
                parts[#parts + 1] = { pvm.once(Interact.ClearFocus) }
            end
        end
        return pvm.concat_all(parts)
    end,

    [Interact.PointerReleased] = function(self, model, report)
        local parts = {
            { pvm.once(Interact.SetPointer(self.x, self.y)) },
        }
        emit_hover(parts, report)
        return pvm.concat_all(parts)
    end,

    [Interact.WheelMoved] = function(self, model, report)
        local parts = {
            { pvm.once(Interact.SetPointer(self.x, self.y)) },
        }
        emit_hover(parts, report)
        if report.scroll_id ~= Core.NoId then
            local axis = scroll_axis(report, report.scroll_id)
            local dx, dy = self.dx, self.dy
            if axis == Style.ScrollX then
                dy = 0
            elseif axis == Style.ScrollY then
                dx = 0
            end
            if dx ~= 0 or dy ~= 0 then
                parts[#parts + 1] = { pvm.once(Interact.ScrollBy(report.scroll_id, dx, dy)) }
            end
        end
        return pvm.concat_all(parts)
    end,

    [Interact.FocusNext] = function(self, model, report)
        local id = focus_move_id(report, model.focus_id, 1)
        if id == Core.NoId then return pvm.empty() end
        return pvm.once(Interact.SetFocus(id))
    end,

    [Interact.FocusPrev] = function(self, model, report)
        local id = focus_move_id(report, model.focus_id, -1)
        if id == Core.NoId then return pvm.empty() end
        return pvm.once(Interact.SetFocus(id))
    end,

    [Interact.ActivateFocus] = function(self, model, report)
        if model.focus_id == Core.NoId then return pvm.empty() end
        return pvm.once(Interact.Activate(model.focus_id))
    end,
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

local function apply_event(model, event)
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
    if cls == Interact.ScrollBy then
        return pvm.with(model, { scrolls = update_scrolls(model.scrolls, event.id, event.dx, event.dy) })
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

function M.scroll_offset(model, id)
    for i = 1, #model.scrolls do
        local s = model.scrolls[i]
        if s.id == id then return s.x, s.y end
    end
    return 0, 0
end

function M.classify(raw, model, report)
    return classify_phase(raw, model, report)
end

function M.apply(model, event)
    return apply_event(model, event)
end

function M.apply_all(model, events_or_g, p, c)
    if p == nil and c == nil and type(events_or_g) == "table" and not pvm.classof(events_or_g) then
        for i = 1, #events_or_g do
            model = apply_event(model, events_or_g[i])
        end
        return model
    end

    local arr = pvm.drain(events_or_g, p, c)
    for i = 1, #arr do
        model = apply_event(model, arr[i])
    end
    return model
end

function M.step(model, report, raw)
    local events = pvm.drain(classify_phase(raw, model, report))
    return M.apply_all(model, events), events
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
