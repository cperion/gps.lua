local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Core = T.Core

local M = {}

function M.id_string(id)
    if id == nil or id == Core.NoId then return nil end
    return id.value
end

function M.surface_lookup(map, id)
    if map == nil then return nil end
    local key = M.id_string(id)
    if key == nil then return nil end
    return map[key]
end

function M.add_surface(map, id, value)
    local key = M.id_string(id)
    if key == nil then return map end
    map[key] = value
    return map
end

function M.route_many(surfaces, ui_events, route_one)
    local out = {}
    for i = 1, #ui_events do
        local ev = route_one(surfaces, ui_events[i])
        if ev ~= nil then
            out[#out + 1] = ev
        end
    end
    return out
end

function M.empty_route()
    return function()
        return nil
    end
end

function M.bundle(node, surfaces, route_one, extras)
    extras = extras or {}
    route_one = route_one or M.empty_route()

    local bundle = {
        node = node,
        surfaces = surfaces or {},
        route_one = route_one,
    }

    function bundle:route_ui_event(ui_event)
        return route_one(self.surfaces, ui_event)
    end

    function bundle:route_ui_events(ui_events)
        return M.route_many(self.surfaces, ui_events, route_one)
    end

    for k, v in pairs(extras) do
        bundle[k] = v
    end

    return bundle
end

M.T = T

return M
