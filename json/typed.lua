-- json/typed.lua
--
-- Helpers for building typed decoders from exact Json.Value.
--
-- A typed decoder is a scalar boundary:
--   Json.Value -> Domain.*
--
-- The semantic work is split cleanly:
--   exact JSON -> normalized policy decode -> typed mapper

local pvm = require("pvm")
local policy_decode = require("json.policy_decode")

local M = {}

function M.decoder(name, spec, mapper)
    assert(type(name) == "string", "json.typed.decoder: name must be a string")
    assert(type(mapper) == "function", "json.typed.decoder: mapper must be a function")

    local phase = pvm.phase(name, function(value)
        return mapper(policy_decode.decode(spec, value), value)
    end)

    return function(value)
        return pvm.one(phase(value))
    end, phase
end

return M
