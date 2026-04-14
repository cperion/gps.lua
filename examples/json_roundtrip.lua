package.path = "./?.lua;./?/init.lua;" .. package.path

local json = require("json")

local src = '{"a":1.0,"a":-0,"msg":"hello","nested":[true,null,"x"]}'
local value = json.parse_string(src)

print(json.compact(value))
print(json.pretty_string(value))
print(json.compact(value))
print(require("pvm").report_string({ json.emit.compact_phase, json.pretty.phase }))
