#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local json = require("json")

local function gen(n, changed_i, changed_v)
    local parts = {}
    for i = 1, n do
        local v = (i == changed_i) and changed_v or i
        parts[i] = string.format('"k%d":{"x":%d,"y":[%d,%d,%d]}', i, v, i, i + 1, i + 2)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local n = 200
local a = json.parse_string(gen(n, -1, 0))
local b = json.parse_string(gen(n, 137, 999999))

json.compact(a)
json.compact(b)
json.pretty_string(a)
json.pretty_string(b)

print(pvm.report_string({ json.emit.compact_phase, json.pretty.phase }))
