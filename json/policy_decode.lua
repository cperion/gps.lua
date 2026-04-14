-- json/policy_decode.lua
--
-- Minimal policy-guided decoder over exact Json.Value.
--
-- This is intentionally small. It validates/interprets exact JSON according to
-- JsonPolicy and returns normalized Lua values. Domain-specific decoders can
-- then construct typed ASDL nodes from those normalized values.

local floor = math.floor
local tonumber = tonumber

local pvm = require("pvm")
local classof = pvm.classof
local schema = require("json.asdl")
local decode = require("json.decode")
local policy = require("json.policy")
local policy_asdl = require("json.policy_asdl")

local M = {}
local T = policy_asdl.T
M.T = T

local function fail(path, msg)
    error("json.policy_decode: " .. path .. ": " .. msg, 3)
end

local function field_occurrences(entries, key)
    local out = {}
    for i = 1, #entries do
        local entry = entries[i]
        if entry.key == key then
            out[#out + 1] = entry.value
        end
    end
    return out
end

local function build_allowed(fields, ignore_keys)
    local allowed = {}
    for i = 1, #fields do
        allowed[fields[i].key] = true
    end
    if ignore_keys ~= nil then
        for i = 1, #ignore_keys do
            allowed[ignore_keys[i]] = true
        end
    end
    return allowed
end

local function first_unknown(entries, fields, ignore_keys)
    local allowed = build_allowed(fields, ignore_keys)
    for i = 1, #entries do
        local entry = entries[i]
        if not allowed[entry.key] then
            return entry
        end
    end
    return nil
end

local decode_spec

local function apply_num_sem(sem, value, path)
    local lexeme = decode.as_number_lexeme(value)
    if sem == T.JsonPolicy.KeepLexeme then
        return lexeme
    end

    local n = tonumber(lexeme)
    if n == nil then
        fail(path, "invalid numeric lexeme")
    end

    if sem == T.JsonPolicy.LuaNumber then
        return n
    end

    if sem == T.JsonPolicy.Integer then
        if n ~= floor(n) then
            fail(path, "expected integer")
        end
        return n
    end

    fail(path, "unknown numeric semantics")
end

local function apply_presence(field, occurrences, path)
    local n = #occurrences
    if n ~= 0 then
        return false, nil
    end

    local presence = field.presence
    if presence == T.JsonPolicy.Required then
        fail(path, "missing required key '" .. field.key .. "'")
    elseif presence == T.JsonPolicy.Optional then
        return true, nil
    elseif presence == T.JsonPolicy.DefaultNull then
        return true, nil
    end

    local mt = classof(presence)
    if mt == T.JsonPolicy.DefaultBool then
        return true, decode_spec(field.spec, schema.bool(presence.value), path)
    elseif mt == T.JsonPolicy.DefaultNum then
        return true, decode_spec(field.spec, schema.num(presence.lexeme), path)
    elseif mt == T.JsonPolicy.DefaultStr then
        return true, decode_spec(field.spec, schema.str(presence.value), path)
    end

    fail(path, "unknown presence policy")
end

local function apply_null_policy(field, value, path)
    if value ~= T.Json.Null then
        return false, value
    end

    local nulls = field.nulls
    if nulls == T.JsonPolicy.ForbidNull then
        fail(path, "null not allowed for key '" .. field.key .. "'")
    elseif nulls == T.JsonPolicy.AllowNull then
        return false, value
    elseif nulls == T.JsonPolicy.NullMeansAbsent then
        local synthetic = {}
        return apply_presence(field, synthetic, path)
    end

    fail(path, "unknown null policy")
end

local function choose_occurrence(field, occurrences, dups, path)
    local n = #occurrences
    if n == 0 then
        return apply_presence(field, occurrences, path)
    end

    if dups == T.JsonPolicy.Reject then
        if n > 1 then
            fail(path, "duplicate key '" .. field.key .. "'")
        end
        return false, occurrences[1]
    elseif dups == T.JsonPolicy.FirstWins then
        return false, occurrences[1]
    elseif dups == T.JsonPolicy.LastWins then
        return false, occurrences[n]
    elseif dups == T.JsonPolicy.Preserve then
        if n == 1 then
            return false, occurrences[1]
        end
        return false, occurrences
    end

    fail(path, "unknown duplicate policy")
end

local function decode_field_value(field, raw, path)
    if raw == nil then
        return nil
    end

    if type(raw) == "table" and classof(raw) == false and #raw > 0 then
        local out = {}
        for i = 1, #raw do
            local synthetic_absent, synthetic_value = apply_null_policy(field, raw[i], path)
            if synthetic_absent then
                out[i] = synthetic_value
            else
                out[i] = decode_spec(field.spec, synthetic_value, path)
            end
        end
        return out
    end

    local synthetic_absent, synthetic_value = apply_null_policy(field, raw, path)
    if synthetic_absent then
        return synthetic_value
    end
    if synthetic_value == T.Json.Null and field.nulls == T.JsonPolicy.AllowNull then
        return nil
    end
    return decode_spec(field.spec, synthetic_value, path)
end

local function decode_object(spec, value, path, ignore_keys)
    local entries = decode.as_object_entries(value)

    if spec.extras == T.JsonPolicy.ForbidExtra then
        local unknown = first_unknown(entries, spec.fields, ignore_keys)
        if unknown then
            fail(path, "unexpected key '" .. unknown.key .. "'")
        end
    end

    local out = {}
    for i = 1, #spec.fields do
        local field = spec.fields[i]
        local occurrences = field_occurrences(entries, field.key)
        local synthetic, raw = choose_occurrence(field, occurrences, spec.dups, path)
        if synthetic then
            out[field.key] = raw
        else
            out[field.key] = decode_field_value(field, raw, path .. "." .. field.key)
        end
    end

    if spec.extras == T.JsonPolicy.AllowExtra then
        local extras = {}
        local allowed = build_allowed(spec.fields, ignore_keys)
        for i = 1, #entries do
            local entry = entries[i]
            if not allowed[entry.key] then
                extras[#extras + 1] = entry
            end
        end
        if #extras > 0 then
            out.__extra = extras
        end
    end

    return out
end

local function decode_tagged(spec, value, path)
    local entries = decode.as_object_entries(value)
    local pseudo_field = T.JsonPolicy.FieldSpec(
        spec.tag_key,
        policy.Str,
        T.JsonPolicy.Required,
        T.JsonPolicy.ForbidNull
    )
    local occurrences = field_occurrences(entries, spec.tag_key)
    local _, raw = choose_occurrence(pseudo_field, occurrences, spec.dups, path)
    local tag = decode.as_string(raw)

    local case_spec = nil
    for i = 1, #spec.cases do
        local c = spec.cases[i]
        if c.tag == tag then
            case_spec = c.object
            break
        end
    end
    if case_spec == nil then
        fail(path, "unknown tag '" .. tag .. "'")
    end

    local merged = T.JsonPolicy.ObjectSpec(case_spec.fields, spec.dups, spec.extras)
    local out = decode_object(merged, value, path, { spec.tag_key })
    out.__tag = tag
    if out[spec.tag_key] == nil then
        out[spec.tag_key] = tag
    end
    return out
end

function decode_spec(spec, value, path)
    if spec == T.JsonPolicy.Any then
        return value
    elseif spec == T.JsonPolicy.Null then
        if value ~= T.Json.Null then
            fail(path, "expected null")
        end
        return nil
    elseif spec == T.JsonPolicy.Bool then
        return decode.as_bool(value)
    elseif spec == T.JsonPolicy.Str then
        return decode.as_string(value)
    end

    local mt = classof(spec)
    if mt == T.JsonPolicy.Num then
        return apply_num_sem(spec.sem, value, path)
    elseif mt == T.JsonPolicy.Arr then
        local items = decode.as_array(value)
        local out = {}
        for i = 1, #items do
            out[i] = decode_spec(spec.spec.items, items[i], path .. "[" .. tostring(i) .. "]")
        end
        return out
    elseif mt == T.JsonPolicy.Obj then
        return decode_object(spec.spec, value, path)
    elseif mt == T.JsonPolicy.TaggedObj then
        return decode_tagged(spec.spec, value, path)
    end

    fail(path, "unknown policy spec")
end

M.phase = pvm.phase("json_policy_decode", function(req)
    return decode_spec(req.spec, req.value, "$")
end)

function M.decode(spec, value)
    return pvm.one(M.phase(policy.request(spec, value)))
end

return M
