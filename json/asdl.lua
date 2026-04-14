-- json/asdl.lua
--
-- Exact JSON ASDL.
--
-- Design notes:
--   - numbers preserve their original lexeme
--   - object entries preserve order and duplicates
--   - values are interned (`unique`) for structural reuse

local pvm = require("pvm")

local M = {}
local T = pvm.context()
M.T = T

T:Define [[
    module Json {
        Value = Null
              | Bool(boolean v) unique
              | Num(string lexeme) unique
              | Str(string v) unique
              | Arr(Json.Value* items) unique
              | Obj(Json.Member* entries) unique

        Member = (string key, Json.Value value) unique
    }
]]

local Bool = T.Json.Bool
local Num = T.Json.Num
local Str = T.Json.Str
local Member = T.Json.Member
local Arr = T.Json.Arr
local Obj = T.Json.Obj

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

M.NULL = T.Json.Null

return M
