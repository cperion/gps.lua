-- json/emit.lua
--
-- pvm-native compact JSON emitter.
--
-- Output is a chunk stream (triplet), not a single concatenated string.

local byte = string.byte
local char = string.char
local format = string.format

local pvm = require("pvm")
local schema = require("json.asdl")

local M = {}
local T = schema.T
M.T = T

local ESC_MAP = {
    [34] = '\\"',
    [92] = '\\\\',
    [8]  = '\\b',
    [12] = '\\f',
    [10] = '\\n',
    [13] = '\\r',
    [9]  = '\\t',
}

local function escape_string(s)
    local out = { '"' }
    local o = 1
    for i = 1, #s do
        local c = byte(s, i)
        local esc = ESC_MAP[c]
        if esc then
            o = o + 1
            out[o] = esc
        elseif c < 32 then
            o = o + 1
            out[o] = format("\\u%04X", c)
        else
            o = o + 1
            out[o] = char(c)
        end
    end
    o = o + 1
    out[o] = '"'
    return table.concat(out)
end

local emit_phase

local function concat_with_commas(trips, n)
    if n == 0 then
        return pvm.empty()
    end
    local parts = {}
    local p = 0
    for i = 1, n do
        if i > 1 then
            p = p + 1
            parts[p] = { pvm.once(",") }
        end
        p = p + 1
        parts[p] = trips[i]
    end
    return pvm.concat_all(parts)
end

local function emit_items(items)
    local n = #items
    if n == 0 then
        return pvm.empty()
    end
    local trips = {}
    for i = 1, n do
        trips[i] = { emit_phase(items[i]) }
    end
    return concat_with_commas(trips, n)
end

local function emit_entries(entries)
    local n = #entries
    if n == 0 then
        return pvm.empty()
    end
    local trips = {}
    for i = 1, n do
        trips[i] = { emit_phase(entries[i]) }
    end
    return concat_with_commas(trips, n)
end

emit_phase = pvm.phase("json_emit_compact", {
    [T.Json.Null] = function(self)
        return pvm.once("null")
    end,

    [T.Json.Bool] = function(self)
        return pvm.once(self.v and "true" or "false")
    end,

    [T.Json.Num] = function(self)
        return pvm.once(self.lexeme)
    end,

    [T.Json.Str] = function(self)
        return pvm.once(escape_string(self.v))
    end,

    [T.Json.Member] = function(self)
        local g1, p1, c1 = pvm.once(escape_string(self.key))
        local g2, p2, c2 = pvm.once(":")
        local g3, p3, c3 = emit_phase(self.value)
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [T.Json.Arr] = function(self)
        local g1, p1, c1 = pvm.once("[")
        local g2, p2, c2 = emit_items(self.items)
        local g3, p3, c3 = pvm.once("]")
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [T.Json.Obj] = function(self)
        local g1, p1, c1 = pvm.once("{")
        local g2, p2, c2 = emit_entries(self.entries)
        local g3, p3, c3 = pvm.once("}")
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,
})

M.compact_phase = emit_phase

function M.compact(value)
    return emit_phase(value)
end

function M.escape_string(s)
    return escape_string(s)
end

return M
