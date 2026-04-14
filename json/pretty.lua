-- json/pretty.lua
--
-- Pretty JSON lowering:
--   Json.Value -> JsonFmt.Cmd stream
--
-- Commands keep indentation relative (push/pop/newline/text). The final string
-- rendering is a flat linear terminal over JsonFmt.Cmd.

local pvm = require("pvm")
local schema = require("json.asdl")
local fmt = require("json.format_asdl")
local emit = require("json.emit")

local M = {}
local T = schema.T
M.T = T
M.F = fmt.T

local function token_trip(cmd)
    return { pvm.once(cmd) }
end

local function join_with_sep(trips, n, sep_trips)
    if n == 0 then
        return pvm.empty()
    end
    local parts = {}
    local p = 0
    for i = 1, n do
        if i > 1 then
            for j = 1, #sep_trips do
                p = p + 1
                parts[p] = sep_trips[j]
            end
        end
        p = p + 1
        parts[p] = trips[i]
    end
    return pvm.concat_all(parts)
end

local pretty_phase

local function pretty_items(items)
    local n = #items
    if n == 0 then
        return pvm.empty()
    end
    local trips = {}
    for i = 1, n do
        trips[i] = { pretty_phase(items[i]) }
    end
    return join_with_sep(trips, n, {
        token_trip(fmt.text(",")),
        token_trip(fmt.NL),
    })
end

local function pretty_entries(entries)
    local n = #entries
    if n == 0 then
        return pvm.empty()
    end
    local trips = {}
    for i = 1, n do
        trips[i] = { pretty_phase(entries[i]) }
    end
    return join_with_sep(trips, n, {
        token_trip(fmt.text(",")),
        token_trip(fmt.NL),
    })
end

pretty_phase = pvm.phase("json_pretty_tokens", {
    [T.Json.Null] = function(self)
        return pvm.once(fmt.text("null"))
    end,

    [T.Json.Bool] = function(self)
        return pvm.once(fmt.text(self.v and "true" or "false"))
    end,

    [T.Json.Num] = function(self)
        return pvm.once(fmt.text(self.lexeme))
    end,

    [T.Json.Str] = function(self)
        return pvm.once(fmt.text(emit.escape_string(self.v)))
    end,

    [T.Json.Member] = function(self)
        local g1, p1, c1 = pvm.once(fmt.text(emit.escape_string(self.key)))
        local g2, p2, c2 = pvm.once(fmt.text(": "))
        local g3, p3, c3 = pretty_phase(self.value)
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [T.Json.Arr] = function(self)
        if #self.items == 0 then
            return pvm.once(fmt.text("[]"))
        end
        return pvm.concat_all({
            token_trip(fmt.text("[")),
            token_trip(fmt.NL),
            token_trip(fmt.PUSH),
            { pretty_items(self.items) },
            token_trip(fmt.POP),
            token_trip(fmt.NL),
            token_trip(fmt.text("]")),
        })
    end,

    [T.Json.Obj] = function(self)
        if #self.entries == 0 then
            return pvm.once(fmt.text("{}"))
        end
        return pvm.concat_all({
            token_trip(fmt.text("{")),
            token_trip(fmt.NL),
            token_trip(fmt.PUSH),
            { pretty_entries(self.entries) },
            token_trip(fmt.POP),
            token_trip(fmt.NL),
            token_trip(fmt.text("}")),
        })
    end,
})

M.phase = pretty_phase

function M.tokens(value)
    return pretty_phase(value)
end

return M
