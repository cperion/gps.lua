-- json/build.lua
--
-- Tiny parser-private exact-tree builder for JSON.
--
-- Keeps parser/runtime boundaries simple:
--   - parser scans bytes and decides syntax
--   - builder constructs exact canonical JSON ASDL values

local schema = require("json.asdl")

local M = {}
local T = schema.T
M.T = T

local Bool = T.Json.Bool
local Num = T.Json.Num
local Str = T.Json.Str
local Member = T.Json.Member
local Arr = T.Json.Arr
local Obj = T.Json.Obj

M.NULL = schema.NULL
M.TRUE = Bool(true)
M.FALSE = Bool(false)

function M.bool(v)
    return Bool(v)
end

function M.num(lexeme)
    return Num(lexeme)
end

function M.str(v)
    return Str(v)
end

function M.member(key, value)
    return Member(key, value)
end

function M.arr(items)
    return Arr(items)
end

function M.obj(entries)
    return Obj(entries)
end

function M.obj_pairs(keys, vals, n)
    local entries = {}
    for i = 1, n do
        entries[i] = Member(keys[i], vals[i])
    end
    return Obj(entries)
end

return M
