-- json/decode.lua
--
-- Typed helpers over exact Json ASDL values.

local tonumber = tonumber

local pvm = require("pvm")
local classof = pvm.classof
local schema = require("json.asdl")

local M = {}
local T = schema.T
M.T = T

local function fail(msg)
    error(msg, 3)
end

function M.kind(v)
    if v == T.Json.Null then return "null" end
    local mt = classof(v)
    if mt == T.Json.Bool then return "bool" end
    if mt == T.Json.Num then return "num" end
    if mt == T.Json.Str then return "str" end
    if mt == T.Json.Arr then return "arr" end
    if mt == T.Json.Obj then return "obj" end
    fail("json.decode: not a Json.Value")
end

function M.as_bool(v)
    if classof(v) ~= T.Json.Bool then
        fail("json.decode: expected bool")
    end
    return v.v
end

function M.as_string(v)
    if classof(v) ~= T.Json.Str then
        fail("json.decode: expected string")
    end
    return v.v
end

function M.as_number_lexeme(v)
    if classof(v) ~= T.Json.Num then
        fail("json.decode: expected number")
    end
    return v.lexeme
end

function M.as_number(v)
    local lexeme = M.as_number_lexeme(v)
    local n = tonumber(lexeme)
    if n == nil then
        fail("json.decode: invalid numeric lexeme")
    end
    return n
end

function M.as_array(v)
    if classof(v) ~= T.Json.Arr then
        fail("json.decode: expected array")
    end
    return v.items
end

function M.as_object_entries(v)
    if classof(v) ~= T.Json.Obj then
        fail("json.decode: expected object")
    end
    return v.entries
end

function M.is_null(v)
    return v == T.Json.Null
end

function M.get(obj, key)
    local entries = M.as_object_entries(obj)
    for i = 1, #entries do
        local entry = entries[i]
        if entry.key == key then
            return entry.value
        end
    end
    return nil
end

function M.get_all(obj, key)
    local entries = M.as_object_entries(obj)
    local out = {}
    for i = 1, #entries do
        local entry = entries[i]
        if entry.key == key then
            out[#out + 1] = entry.value
        end
    end
    return out
end

function M.require(obj, key)
    local v = M.get(obj, key)
    if v == nil then
        fail("json.decode: missing required key '" .. key .. "'")
    end
    return v
end

function M.field_string(obj, key)
    return M.as_string(M.require(obj, key))
end

function M.field_number(obj, key)
    return M.as_number(M.require(obj, key))
end

function M.field_bool(obj, key)
    return M.as_bool(M.require(obj, key))
end

function M.list_of(f, arr)
    local items = M.as_array(arr)
    local out = {}
    for i = 1, #items do
        out[i] = f(items[i])
    end
    return out
end

return M
