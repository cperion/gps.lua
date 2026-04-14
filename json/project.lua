-- json/project.lua
--
-- Secondary interop: plain Lua values -> exact Json.Value.
--
-- This is not the primary architectural path; exact Json.Value remains the core
-- representation. This module is for convenience when bridging existing Lua
-- data into the JSON stack.

local type = type
local pairs = pairs
local sort = table.sort
local tostring = tostring

local schema = require("json.asdl")

local M = {}
local T = schema.T
M.T = T
M.NULL = schema.NULL

local function is_array(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            return false, 0
        end
        if k > n then n = k end
    end
    for i = 1, n do
        if t[i] == nil then return false, 0 end
    end
    return true, n
end

local function fail(msg)
    error("json.project: " .. msg, 3)
end

local from_lua

local function object_from_map(t)
    local keys = {}
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "string" then
            fail("object keys must be strings")
        end
        n = n + 1
        keys[n] = k
    end
    sort(keys)

    local entries = {}
    for i = 1, #keys do
        local k = keys[i]
        entries[i] = schema.member(k, from_lua(t[k]))
    end
    return schema.obj(entries)
end

function from_lua(v)
    local tv = type(v)
    if v == M.NULL or v == schema.NULL then
        return schema.NULL
    end
    if tv == "boolean" then
        return schema.bool(v)
    end
    if tv == "number" then
        return schema.num(tostring(v))
    end
    if tv == "string" then
        return schema.str(v)
    end
    if tv == "table" then
        local arr, n = is_array(v)
        if arr then
            local items = {}
            for i = 1, n do
                items[i] = from_lua(v[i])
            end
            return schema.arr(items)
        end
        return object_from_map(v)
    end
    fail("unsupported type '" .. tv .. "'")
end

M.from_lua = from_lua

return M
