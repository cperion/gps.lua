#!/usr/bin/env luajit
-- lua_lsp_stdio_real_v1.lua
--
-- LSP stdio entrypoint using a real Lua parser adapter
-- (Neovim Tree-sitter Lua backend).

package.path = "./?.lua;./?/init.lua;" .. package.path

local JsonRpc = require("bench.lua_lsp_jsonrpc_v1")
local Parser = require("bench.lua_lsp_parser_treesitter_nvim_v1").new()

JsonRpc.run_stdio({
    parse = Parser.parse,
    position_to_anchor = Parser.position_to_anchor,
    adapter_opts = {
        anchor_to_range = Parser.anchor_to_range,
    },
    server_info = {
        name = "lua-lsp-pvm-real",
        version = "0.1.0",
    },
})
