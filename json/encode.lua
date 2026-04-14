-- json/encode.lua
--
-- Convenience wrappers over compact + pretty JSON lowerings.

local pvm = require("pvm")
local emit = require("json.emit")
local pretty = require("json.pretty")
local fmt = require("json.format_asdl")

local M = {}

function M.chunks(value)
    return emit.compact(value)
end

function M.into(value, out)
    out = out or {}
    local g, p, c = M.chunks(value)
    pvm.drain_into(g, p, c, out)
    return out
end

function M.compact(value)
    return table.concat(M.into(value, {}))
end

local function render_pretty(g, p, c, indent_unit, out)
    out = out or {}
    indent_unit = indent_unit or "  "

    local depth = 0
    local bol = true
    local n = #out

    pvm.each(g, p, c, function(cmd)
        local k = cmd.kind
        if k == fmt.K_PUSH then
            depth = depth + 1
            return
        end
        if k == fmt.K_POP then
            depth = depth - 1
            return
        end
        if k == fmt.K_NEWLINE then
            n = n + 1
            out[n] = "\n"
            bol = true
            return
        end
        if bol then
            for _ = 1, depth do
                n = n + 1
                out[n] = indent_unit
            end
            bol = false
        end
        n = n + 1
        out[n] = cmd.text
    end)

    return out
end

function M.pretty_tokens(value)
    return pretty.tokens(value)
end

function M.pretty_into(value, out, indent_unit)
    local g, p, c = M.pretty_tokens(value)
    return render_pretty(g, p, c, indent_unit, out)
end

function M.pretty(value, indent_unit)
    return table.concat(M.pretty_into(value, {}, indent_unit))
end

return M
