#!/usr/bin/env luajit
-- Trace the full LSP pipeline and show how stable the JIT traces are
package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local lsp = require("lsp")

local core = lsp.server()
local uri = "file:///trace_test.lua"

-- Build a real file
local lines = { "---@class User", "---@field name string", "---@field id number", "local M = {}" }
for i = 1, 100 do
    lines[#lines + 1] = string.format("local v%d = %d", i, i)
end
lines[#lines + 1] = "function M.process(x) return x * 2 end"
lines[#lines + 1] = "print(v1, v100)"
lines[#lines + 1] = "return M"
local txt = table.concat(lines, "\n")

-- Cold run first (warms the JIT)
core:handle("textDocument/didOpen", {
    textDocument = { uri = uri, version = 1, text = txt },
})
core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
core:handle("textDocument/hover", {
    textDocument = { uri = uri }, position = { line = 50, character = 6 },
})
core:handle("textDocument/completion", {
    textDocument = { uri = uri }, position = { line = 50, character = 0 },
})
core:handle("textDocument/documentSymbol", { textDocument = { uri = uri } })

-- Now do a change to force incremental re-analysis
local txt2 = txt:gsub("v100", "v100_changed")
core:handle("textDocument/didChange", {
    textDocument = { uri = uri, version = 2 },
    contentChanges = { { text = txt2 } },
})
core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })

-- Second change
local txt3 = txt:gsub("v100", "v100_again")
core:handle("textDocument/didChange", {
    textDocument = { uri = uri, version = 3 },
    contentChanges = { { text = txt3 } },
})

-- Now enable trace logging and run the HOT path
io.stderr:write("\n=== JIT TRACE LOG: cached diagnostic ===\n")
io.stderr:flush()

-- Turn on verbose JIT logging
jit.opt.start("hotloop=2", "hotexit=2")
local v = require("jit.v")
v.on("/dev/stderr")

-- Run the cached path many times — this is what the LSP does on every keystroke
for i = 1, 200 do
    core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
end

v.off()

io.stderr:write("\n=== JIT TRACE LOG: cached hover ===\n")
io.stderr:flush()
v.on("/dev/stderr")

for i = 1, 200 do
    core:handle("textDocument/hover", {
        textDocument = { uri = uri }, position = { line = 50, character = 6 },
    })
end

v.off()

io.stderr:write("\n=== JIT TRACE LOG: incremental change + diagnostic ===\n")
io.stderr:flush()
v.on("/dev/stderr")

for i = 1, 50 do
    local changed = txt:gsub("v100", "v_" .. tostring(i))
    core:handle("textDocument/didChange", {
        textDocument = { uri = uri, version = 100 + i },
        contentChanges = { { text = changed } },
    })
    core:handle("textDocument/diagnostic", { textDocument = { uri = uri } })
end

v.off()

-- Print summary
io.stderr:write("\n=== DONE ===\n")
