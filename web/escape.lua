local M = {}

local function escape_core(s, is_attr)
    s = tostring(s or "")
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    if is_attr then
        s = s:gsub('"', "&quot;")
    end
    return s
end

function M.text(s)
    return escape_core(s, false)
end

function M.attr(s)
    return escape_core(s, true)
end

return M
