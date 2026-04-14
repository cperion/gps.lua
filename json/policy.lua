-- json/policy.lua
--
-- Convenience facade over JsonPolicy ASDL.

local asdl = require("json.policy_asdl")

local M = {}
local T = asdl.T
M.T = T

M.Any = T.JsonPolicy.Any
M.Null = T.JsonPolicy.Null
M.Bool = T.JsonPolicy.Bool
M.Str = T.JsonPolicy.Str

M.KeepLexeme = T.JsonPolicy.KeepLexeme
M.LuaNumber = T.JsonPolicy.LuaNumber
M.Integer = T.JsonPolicy.Integer

M.Required = T.JsonPolicy.Required
M.Optional = T.JsonPolicy.Optional
M.DefaultNull = T.JsonPolicy.DefaultNull

M.ForbidNull = T.JsonPolicy.ForbidNull
M.AllowNull = T.JsonPolicy.AllowNull
M.NullMeansAbsent = T.JsonPolicy.NullMeansAbsent

M.Preserve = T.JsonPolicy.Preserve
M.Reject = T.JsonPolicy.Reject
M.FirstWins = T.JsonPolicy.FirstWins
M.LastWins = T.JsonPolicy.LastWins

M.ForbidExtra = T.JsonPolicy.ForbidExtra
M.AllowExtra = T.JsonPolicy.AllowExtra

function M.num(sem)
    return T.JsonPolicy.Num(sem or M.LuaNumber)
end

function M.array(items)
    return T.JsonPolicy.Arr(T.JsonPolicy.ArraySpec(items))
end

function M.field(key, spec, presence, nulls)
    return T.JsonPolicy.FieldSpec(
        key,
        spec,
        presence or M.Required,
        nulls or M.ForbidNull
    )
end

function M.object(fields, opts)
    opts = opts or {}
    return T.JsonPolicy.Obj(T.JsonPolicy.ObjectSpec(
        fields or {},
        opts.dups or M.Reject,
        opts.extras or M.ForbidExtra
    ))
end

function M.case(tag, fields, opts)
    opts = opts or {}
    return T.JsonPolicy.TaggedCase(tag, T.JsonPolicy.ObjectSpec(
        fields or {},
        opts.dups or M.Reject,
        opts.extras or M.ForbidExtra
    ))
end

function M.tagged(tag_key, cases, opts)
    opts = opts or {}
    return T.JsonPolicy.TaggedObj(T.JsonPolicy.TaggedSpec(
        tag_key,
        cases or {},
        opts.dups or M.Reject,
        opts.extras or M.ForbidExtra
    ))
end

function M.default_bool(v)
    return T.JsonPolicy.DefaultBool(v)
end

function M.default_num(lexeme)
    return T.JsonPolicy.DefaultNum(lexeme)
end

function M.default_str(v)
    return T.JsonPolicy.DefaultStr(v)
end

function M.request(spec, value)
    return T.JsonDecode.Request(spec, value)
end

return M
