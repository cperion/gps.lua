-- json/init.lua
--
-- Public facade for the JSON stack.

local asdl = require("json.asdl")
local parse = require("json.parse")
local emit = require("json.emit")
local encode = require("json.encode")
local decode = require("json.decode")
local format_asdl = require("json.format_asdl")
local pretty = require("json.pretty")
local project = require("json.project")
local typed = require("json.typed")
local policy_asdl = require("json.policy_asdl")
local policy = require("json.policy")
local policy_decode = require("json.policy_decode")

return {
    T = asdl.T,
    NULL = asdl.NULL,
    F = format_asdl.T,
    P = policy_asdl.T,

    asdl = asdl,
    parse = parse,
    emit = emit,
    encode = encode,
    decode = decode,
    format_asdl = format_asdl,
    pretty = pretty,
    project = project,
    typed = typed,
    policy_asdl = policy_asdl,
    policy = policy,
    policy_decode = policy_decode,

    parse_string = parse.parse,
    chunks = encode.chunks,
    into = encode.into,
    compact = encode.compact,
    pretty_string = encode.pretty,
    from_lua = project.from_lua,
}
