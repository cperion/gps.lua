-- json/policy_asdl.lua
--
-- Minimal semantic policy ASDL for exact Json.Value.
--
-- This is intentionally smaller than a full JSON Schema system. It expresses
-- only semantic choices not already implied by exact JSON structure.

local schema = require("json.asdl")

local M = {}
local T = schema.T
M.T = T

T:Define [[
    module JsonPolicy {
        Spec = Any
             | Null
             | Bool
             | Str
             | Num(JsonPolicy.NumSem sem) unique
             | Arr(JsonPolicy.ArraySpec spec) unique
             | Obj(JsonPolicy.ObjectSpec spec) unique
             | TaggedObj(JsonPolicy.TaggedSpec spec) unique

        NumSem = KeepLexeme | LuaNumber | Integer

        Presence = Required
                 | Optional
                 | DefaultNull
                 | DefaultBool(boolean value) unique
                 | DefaultNum(string lexeme) unique
                 | DefaultStr(string value) unique

        NullPolicy = ForbidNull | AllowNull | NullMeansAbsent

        DupPolicy = Preserve | Reject | FirstWins | LastWins

        ExtraPolicy = ForbidExtra | AllowExtra

        FieldSpec = (string key,
                     JsonPolicy.Spec spec,
                     JsonPolicy.Presence presence,
                     JsonPolicy.NullPolicy nulls) unique

        ObjectSpec = (JsonPolicy.FieldSpec* fields,
                      JsonPolicy.DupPolicy dups,
                      JsonPolicy.ExtraPolicy extras) unique

        ArraySpec = (JsonPolicy.Spec items) unique

        TaggedCase = (string tag, JsonPolicy.ObjectSpec object) unique

        TaggedSpec = (string tag_key,
                      JsonPolicy.TaggedCase* cases,
                      JsonPolicy.DupPolicy dups,
                      JsonPolicy.ExtraPolicy extras) unique
    }

    module JsonDecode {
        Request = (JsonPolicy.Spec spec, Json.Value value) unique
    }
]]

return M
