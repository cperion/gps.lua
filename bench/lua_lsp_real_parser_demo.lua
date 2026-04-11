#!/usr/bin/env luajit
-- lua_lsp_real_parser_demo.lua
--
-- Demo: server core + real Lua parser adapter (Neovim Tree-sitter).

package.path = "./?.lua;./?/init.lua;" .. package.path

local Server = require("bench.lua_lsp_server_core_v1")
local Parser = require("bench.lua_lsp_parser_treesitter_nvim_v1").new()

local core = Server.new({
    parse = Parser.parse,
    position_to_anchor = Parser.position_to_anchor,
    adapter_opts = { anchor_to_range = Parser.anchor_to_range },
})

local uri = "file:///real.lua"
local text = table.concat({
    "---@class User",
    "local x = 1",
    "local function f(a, b)",
    "  local z = a + b",
    "  return z",
    "end",
    "print(x, y)",
}, "\n")

core:did_open({ textDocument = { uri = uri, version = 1, text = text } })

local d = core:to_lsp(core:diagnostic({ textDocument = { uri = uri } }))
local h = core:to_lsp(core:hover({ textDocument = { uri = uri }, position = { line = 6, character = 6 } })) -- x in print(x, y)
local def = core:to_lsp(core:definition({ textDocument = { uri = uri }, position = { line = 6, character = 6 } }))
local refs = core:to_lsp(core:references({ textDocument = { uri = uri }, position = { line = 6, character = 6 }, context = { includeDeclaration = true } }))

print("real parser demo")
print("  diagnostics:", #d.items)
for i = 1, #d.items do
    print("   -", d.items[i].code, d.items[i].message)
end
print("  hover:", h and h.contents and h.contents.value or "<nil>")
print("  defs:", #def, "refs:", #refs)
