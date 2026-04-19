local session = require("ui.session")
local backend = require("ui.backends.sdl3")

local M = {}

function M.new(opts)
    opts = opts or {}
    if opts.backend == nil then
        opts.backend = backend
    end
    return session.new(opts)
end

return M
