package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local json = require("json")
local policy = require("json.policy")
local policy_decode = require("json.policy_decode")

local spec = policy.tagged("kind", {
    policy.case("point", {
        policy.field("x", policy.num(policy.LuaNumber), policy.Required, policy.ForbidNull),
        policy.field("y", policy.num(policy.LuaNumber), policy.Required, policy.ForbidNull),
    }),
    policy.case("label", {
        policy.field("text", policy.Str, policy.Required, policy.ForbidNull),
    }),
}, {
    dups = policy.Reject,
    extras = policy.ForbidExtra,
})

local a = json.parse_string('{"kind":"point","x":1,"y":2}')
local b = json.parse_string('{"kind":"point","x":1,"y":2}')

local da = policy_decode.decode(spec, a)
local db = policy_decode.decode(spec, b)

print(da.__tag, da.kind, da.x, da.y)
print(da.kind == db.kind, da.x == db.x, da.y == db.y)
print(pvm.report_string({ policy_decode.phase }))
