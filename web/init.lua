local M = {}

local lazy = {
    Define = function() return require("web.asdl").Define end,
    html = function() return require("web.html").bind end,
    render = function() return require("web.render").bind end,
    router = function() return require("web.router") end,
    stream = function() return require("web.stream") end,
    http = function() return require("web.http") end,
    ws = function() return require("web.ws") end,
    live = function() return require("web.live") end,
    live_page = function() return require("web.live_page").bind end,
    response = function() return require("web.response").bind end,
    forms = function() return require("web.forms").bind end,
    diff = function() return require("web.diff").bind end,
    encode = function() return require("web.encode").bind end,
}

return setmetatable(M, {
    __index = function(t, k)
        local loader = lazy[k]
        if not loader then
            return nil
        end
        local v = loader()
        rawset(t, k, v)
        return v
    end,
})
