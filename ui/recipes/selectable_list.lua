local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local b = require("ui.build")
local core = require("ui.recipes._core")
local collection = require("ui.recipes._collection")

local T = ui_asdl.T

local function wrap_row(id, child, focusable, activatable)
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
    if opts.id == nil then error("selectable_list recipe requires opts.id", 2) end
    if opts.items == nil then error("selectable_list recipe requires opts.items", 2) end
    if opts.key_of == nil then error("selectable_list recipe requires opts.key_of", 2) end
    if opts.row == nil then error("selectable_list recipe requires opts.row", 2) end

    local focusable = opts.focusable ~= false
    local activatable = opts.activatable ~= false

    local built = collection.build {
        id = opts.id,
        items = opts.items,
        key_of = opts.key_of,
        row = opts.row,
        selected_key = opts.selected_key,
        focused_key = opts.focused_key,
        before_each = opts.before_each,
        after_each = opts.after_each,
        before_all = opts.before_all,
        after_all = opts.after_all,
        wrap_row = function(child, item, ctx)
            return wrap_row(ctx.row_id, child, focusable, activatable)
        end,
    }

    local surfaces = {
        items = {},
    }
    for i = 1, #built.row_infos do
        local info = built.row_infos[i]
        core.add_surface(surfaces.items, info.id, info)
    end

    local function route_one(surfaces_, ui_event)
        local cls = pvm.classof(ui_event)
        if cls == T.Interact.Activate and activatable then
            local info = core.surface_lookup(surfaces_.items, ui_event.id)
            if info ~= nil and opts.on_select ~= nil then
                return opts.on_select(info.key, info.item, info.ctx)
            end
        elseif cls == T.Interact.SetFocus and focusable then
            local info = core.surface_lookup(surfaces_.items, ui_event.id)
            if info ~= nil and opts.on_focus ~= nil then
                return opts.on_focus(info.key, info.item, info.ctx)
            end
        end
        return nil
    end

    return core.bundle(built.node, surfaces, route_one)
end
