package.path = "./?.lua;./?/init.lua;" .. package.path

local Lower = require("moonlift.lower_surface_to_elab_loop")

local M = {}

function M.Define(T)
    local api = Lower.Define(T)
    return {
        lower_type = api.lower_type,
        lower_expr = api.lower_expr,
        expr_type = api.expr_type,
        lower_domain = api.lower_domain,
    }
end

return M
