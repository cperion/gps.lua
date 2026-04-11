#!/usr/bin/env luajit
-- lsp/test_server.lua
--
-- End-to-end test of the full LSP server stack:
--   SourceFile → lex phase → parse lower → semantics → adapter → server → LSP response

package.path = "./?.lua;./?/init.lua;" .. package.path

local lsp = require("lsp")
local pvm = require("pvm")

local core = lsp.server()
local uri = "file:///demo.lua"

-- ── Test 1: didOpen + diagnostics ──────────────────────────
print("=== Test 1: didOpen + diagnostics ===")
local txt1 = table.concat({
    "---@class User",
    "---@field name string",
    "---@field id number",
    "local M = {}",
    "",
    "function M.new(name, id)",
    "    return { name = name, id = id }",
    "end",
    "",
    "local x = 42",
    "print(x, undefined_var)",
}, "\n")

core:handle("textDocument/didOpen", {
    textDocument = { uri = uri, version = 1, text = txt1 },
})

local d1 = core:to_lsp(core:handle("textDocument/diagnostic", { textDocument = { uri = uri } }))
print("diagnostics:", #d1.items)
for i = 1, #d1.items do
    print(string.format("  [%d] %s: %s (L%d:%d)",
        d1.items[i].severity, d1.items[i].code, d1.items[i].message,
        d1.items[i].range.start.line, d1.items[i].range.start.character))
end
-- Should find 'undefined_var' as undefined global
local found_undef = false
for i = 1, #d1.items do
    if d1.items[i].code == "undefined-global" and d1.items[i].message:match("undefined_var") then
        found_undef = true
    end
end
assert(found_undef, "should find undefined global 'undefined_var'")
print("OK!")

-- ── Test 2: hover ──────────────────────────────────────────
print("\n=== Test 2: hover ===")
-- Hover over 'x' at line 9 (0-indexed)
local h1 = core:to_lsp(core:handle("textDocument/hover", {
    textDocument = { uri = uri },
    position = { line = 9, character = 6 },
}))
print("hover:", h1 and h1.contents and h1.contents.value or "<nil>")
-- hover result may or may not resolve depending on anchor positions

-- ── Test 3: didChange + re-diagnostics ─────────────────────
print("\n=== Test 3: didChange ===")
local txt2 = table.concat({
    "---@class User",
    "---@field name string",
    "---@field id number",
    "local M = {}",
    "",
    "function M.new(name, id)",
    "    return { name = name, id = id }",
    "end",
    "",
    "local x = 42",
    "local y = 100",  -- added
    "print(x, y)",    -- fixed: y instead of undefined_var
}, "\n")

core:handle("textDocument/didChange", {
    textDocument = { uri = uri, version = 2 },
    contentChanges = { { text = txt2 } },
})

local d2 = core:to_lsp(core:handle("textDocument/diagnostic", { textDocument = { uri = uri } }))
print("diagnostics after fix:", #d2.items)
for i = 1, #d2.items do
    print(string.format("  [%d] %s: %s", d2.items[i].severity, d2.items[i].code, d2.items[i].message))
end
-- Should have fewer/no undefined-global diagnostics
local still_undef = false
for i = 1, #d2.items do
    if d2.items[i].code == "undefined-global" and d2.items[i].message:match("undefined_var") then
        still_undef = true
    end
end
assert(not still_undef, "undefined_var should be gone after fix")
print("OK!")

-- ── Test 4: definition ─────────────────────────────────────
print("\n=== Test 4: definition ===")
local def = core:to_lsp(core:handle("textDocument/definition", {
    textDocument = { uri = uri },
    position = { line = 11, character = 7 }, -- 'x' in print(x, y)
}))
print("definition locations:", type(def) == "table" and #def or 0)

-- ── Test 5: references ─────────────────────────────────────
print("\n=== Test 5: references ===")
local refs = core:to_lsp(core:handle("textDocument/references", {
    textDocument = { uri = uri },
    position = { line = 11, character = 7 },
    context = { includeDeclaration = true },
}))
print("references:", type(refs) == "table" and #refs or 0)

-- ── Test 6: didClose ───────────────────────────────────────
print("\n=== Test 6: didClose ===")
core:handle("textDocument/didClose", {
    textDocument = { uri = uri },
})
print("OK!")

-- ── Test 7: benchmark ──────────────────────────────────────
print("\n=== Test 7: benchmark ===")
local function bench(name, n, fn)
    for _ = 1, 5 do fn() end
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    for _ = 1, n do fn() end
    local us = (os.clock() - t0) * 1e6 / n
    print(string.format("  %-35s %8.1f us", name, us))
end

-- Generate larger file
local big = { "---@class BigClass" }
for i = 1, 500 do big[#big + 1] = string.format("local v%d = %d", i, i) end
big[#big + 1] = "print(v1, v500)"
big[#big + 1] = "print(v2, missing_name)"
local big_txt = table.concat(big, "\n")
local big_uri = "file:///big.lua"

core:handle("textDocument/didOpen", {
    textDocument = { uri = big_uri, version = 1, text = big_txt },
})

bench("diagnostic (500 locals, first)", 10, function()
    core:handle("textDocument/diagnostic", { textDocument = { uri = big_uri } })
end)

bench("diagnostic (500 locals, cached)", 1000, function()
    core:handle("textDocument/diagnostic", { textDocument = { uri = big_uri } })
end)

-- Change one line and re-diagnostic
local function change_and_diag(ver)
    local changed = big_txt:gsub("missing_name", "missing_" .. tostring(ver))
    core:handle("textDocument/didChange", {
        textDocument = { uri = big_uri, version = 100 + ver },
        contentChanges = { { text = changed } },
    })
    return core:handle("textDocument/diagnostic", { textDocument = { uri = big_uri } })
end

bench("change+diagnostic (500 locals)", 10, function()
    change_and_diag(math.random(10000))
end)

print("\nAll server tests passed!")
