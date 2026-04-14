#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local JsonRpc = require("lsp.jsonrpc")
local lsp = require("lsp")
local JSON_NULL = JsonRpc.JSON_NULL

local function hex_bytes(s)
    local out = {}
    for i = 1, #s do out[#out + 1] = string.format("%02X", s:byte(i)) end
    return table.concat(out, " ")
end

print("=== JSON-RPC codec ===")

local smile = JsonRpc.json_decode("\"\\uD83D\\uDE00\"")
print("decoded surrogate pair bytes:", hex_bytes(smile))
assert(smile:byte(1) == 0xF0 and smile:byte(2) == 0x9F and smile:byte(3) == 0x98 and smile:byte(4) == 0x80,
    "surrogate pairs should decode to valid UTF-8 code point")

local bad = JsonRpc.json_decode("\"\\uD83D\"")
print("decoded unpaired surrogate bytes:", hex_bytes(bad))
assert(bad:byte(1) == 0xEF and bad:byte(2) == 0xBF and bad:byte(3) == 0xBD,
    "unpaired surrogate should decode as U+FFFD")

print("\n=== JSON null preservation ===")
local null_obj = JsonRpc.json_decode('{"a":null,"b":[null],"c":{"d":null}}')
assert(null_obj.a == JSON_NULL, "object null field should be preserved")
assert(null_obj.b and null_obj.b[1] == JSON_NULL, "array null should be preserved")
assert(null_obj.c and null_obj.c.d == JSON_NULL, "nested null should be preserved")
local round = JsonRpc.json_encode(null_obj)
print("roundtrip:", round)
assert(round == '{"a":null,"b":[null],"c":{"d":null}}', "null roundtrip should be stable")

print("\n=== Initialize capabilities ===")
local rpc = JsonRpc.new({ core = lsp.server() })
local init = rpc:handle_message({ jsonrpc = "2.0", id = 1, method = "initialize", params = {} })
assert(init and init.result and init.result.capabilities, "initialize should return capabilities")
print("positionEncoding:", init.result.capabilities.positionEncoding)
assert(init.result.capabilities.positionEncoding == "utf-16", "server should advertise UTF-16 position encoding")

print("\n=== Invalid method type ===")
local bad_req = rpc:handle_message({ jsonrpc = "2.0", id = 2, method = JsonRpc.JSON_NULL, params = {} })
assert(bad_req and bad_req.error and bad_req.error.code, "invalid method should return JSON-RPC error")
print("invalid method error code:", bad_req.error.code)
assert(bad_req.error.code == -32600, "invalid method should map to -32600")

local null_id_err = rpc:handle_message({ jsonrpc = "2.0", id = JSON_NULL, method = JSON_NULL, params = {} })
assert(null_id_err and null_id_err.id == JSON_NULL, "error response should preserve null id")
assert(null_id_err.error and null_id_err.error.code == -32600, "null-id invalid request should be -32600")
local encoded_err = JsonRpc.json_encode(null_id_err)
assert(encoded_err:find('"id":null', 1, true), "encoded error should contain id:null")

local ignored = rpc:handle_message({ jsonrpc = "2.0", id = 99, result = nil })
assert(ignored == nil, "client response objects should be ignored")

print("\nAll jsonrpc tests passed!")
