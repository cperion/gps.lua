local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local b = require("ui.build")
local core = require("ui.recipes._core")

local T = ui_asdl.T

local function wrap_child(id, child, focusable, activatable)
    if activatable then
        if focusable then
            return b.with_input(id, T.Interact.ActivateTarget, child)
        end
        return b.with_input(id, T.Interact.HitTarget, child)
    end
    if focusable then
        return b.with_input(id, T.Interact.FocusTarget, child)
    end
    return child
end

return function(opts)
    opts = opts or {}

    local id = opts.id
    local child = opts.child
    if id == nil then error("activatable recipe requires opts.id", 2) end
    if child == nil then error("activatable recipe requires opts.child", 2) end

    local disabled = opts.disabled == true
    local focusable = opts.focusable == true
    local activatable = opts.activatable ~= false

    local surfaces = {
        activate = {},
        focus = {},
    }

    local node = child
    if not disabled then
        node = wrap_child(id, child, focusable, activatable)
        if activatable then
            core.add_surface(surfaces.activate, id, { id = id })
        end
        if focusable then
            core.add_surface(surfaces.focus, id, { id = id })
        end
    end

    local function route_one(surfaces_, ui_event)
        local cls = pvm.classof(ui_event)
        if cls == T.Interact.Activate then
            if core.surface_lookup(surfaces_.activate, ui_event.id) ~= nil and opts.on_activate ~= nil then
                return opts.on_activate(ui_event.id)
            end
        elseif cls == T.Interact.SetFocus then
            if core.surface_lookup(surfaces_.focus, ui_event.id) ~= nil and opts.on_focus ~= nil then
                return opts.on_focus(ui_event.id)
            end
        end
        return nil
    end

    return core.bundle(node, surfaces, route_one)
end
