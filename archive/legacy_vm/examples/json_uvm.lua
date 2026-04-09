package.path = "./?.lua;./?/init.lua;" .. package.path

local uvm = require("uvm")

local src = '{"name":"cedric","tags":["lua","uvm"],"active":true}'

-- Table-producing decoder.
local table_json = uvm.json.decoder()
local m1 = table_json:spawn({ source = src })
local st1, value = m1:run()
print("table status:", uvm.status_name_of(st1), value.name, value.tags[1], value.active)

-- ASDL-producing decoder.
local T = uvm.json.define_types()
local asdl_json = uvm.json.asdl_decoder({ types = T })
local m2 = asdl_json:spawn({ source = src })
local st2, node = m2:run()
print("asdl status:", uvm.status_name_of(st2), node.kind, node.pairs[1].key)

-- Generated-from-spec decoder: authored UJsonSpec -> lowered UJsonPlan -> codegen.
local gen_json = uvm.json.generated_decoder()
local st3, value2 = gen_json:spawn({ source = src }):run()
print("generated status:", uvm.status_name_of(st3), value2.name)
print("generated has plan:", gen_json.generated_plan ~= nil)

-- The family can still be compiled like any other coarse UVM leaf.
local compiled = table_json:compile()
local st4, value3 = compiled:spawn({ source = src }):run()
print("compiled status:", uvm.status_name_of(st4), value3.name)
