package.path = "./?.lua;./?/init.lua;" .. package.path

local json = require("json")
local pvm = require("pvm")

local value = json.parse_string('{"a":1,"b":[true,null,"x"],"obj":{"k":"v"}}')

print(json.pretty_string(value))
print(pvm.report_string({ json.pretty.phase }))
