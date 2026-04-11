#!/usr/bin/env luajit
-- Show trace stability on the HOT cached path
package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local lsp = require("lsp")

local core = lsp.server()
local uri = "file:///trace_test.lua"

local lines = { "local M = {}" }
for i = 1, 100 do lines[#lines + 1] = string.format("local v%d = %d", i, i) end
lines[#lines + 1] = "print(v1, v100)"
lines[#lines + 1] = "return M"
local txt = table.concat(lines, "\n")

-- Full warmup — cold path runs, JIT compiles traces
core:handle("textDocument/didOpen", { textDocument = { uri = uri, version = 1, text = txt } })
for _ = 1, 500 do
    core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
    core:handle("textDocument/hover", { textDocument = { uri = uri }, position = { line = 50, character = 6 } })
    core:handle("textDocument/documentSymbol", { textDocument = { uri = uri } })
    core:handle("textDocument/completion", { textDocument = { uri = uri }, position = { line = 50, character = 0 } })
end

-- Force JIT to fully stabilize
collectgarbage(); collectgarbage()

-- NOW trace the stable path
print("\n=== STABLE HOT PATH: 1000 cached diagnostics ===")
local v = require("jit.v")
v.on()

for i = 1, 1000 do
    core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
end

v.off()

print("\n=== STABLE HOT PATH: 1000 cached hovers ===")
v.on()

for i = 1, 1000 do
    core:handle("textDocument/hover", { textDocument = { uri = uri }, position = { line = 50, character = 6 } })
end

v.off()

print("\n=== STABLE HOT PATH: 1000 completions ===")
v.on()

for i = 1, 1000 do
    core:handle("textDocument/completion", { textDocument = { uri = uri }, position = { line = 50, character = 0 } })
end

v.off()
print("\n=== DONE ===")
