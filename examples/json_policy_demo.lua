package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local json = require("json")
local policy = require("json.policy")
local policy_decode = require("json.policy_decode")

local D = pvm.context():Define [[
    module Demo {
        Mode = Fast | Slow
        Config = (string name, boolean enabled, number threshold, Demo.Mode mode) unique
    }
]]

local spec = policy.object({
    policy.field("name", policy.Str, policy.Required, policy.ForbidNull),
    policy.field("enabled", policy.Bool, policy.default_bool(true), policy.ForbidNull),
    policy.field("threshold", policy.num(policy.LuaNumber), policy.default_num("0.5"), policy.ForbidNull),
    policy.field("mode", policy.Str, policy.Required, policy.ForbidNull),
}, {
    dups = policy.Reject,
    extras = policy.ForbidExtra,
})

local function decode_mode(s)
    if s == "fast" then return D.Demo.Fast end
    if s == "slow" then return D.Demo.Slow end
    error("unknown mode '" .. tostring(s) .. "'")
end

local function decode_config(value)
    local obj = policy_decode.decode(spec, value)
    return D.Demo.Config(
        obj.name,
        obj.enabled,
        obj.threshold,
        decode_mode(obj.mode)
    )
end

local src = '{"name":"alpha","mode":"fast"}'
local value = json.parse_string(src)
local cfg1 = decode_config(value)
local cfg2 = decode_config(value)

print(cfg1)
print(cfg1 == cfg2)
print(pvm.report_string({ policy_decode.phase }))
