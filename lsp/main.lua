#!/usr/bin/env luajit
-- lsp/main.lua
--
-- Standalone Lua LSP server on stdio.
-- No Neovim dependency. Pure Lua/LuaJIT.
--
-- Usage:
--   luajit lsp/main.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

require("lsp").run_stdio()
