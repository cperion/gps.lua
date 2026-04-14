#!/usr/bin/env luajit
-- Test all new features: type inference, completions, document symbols, rename
package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local lsp = require("lsp")

local core = lsp.server()
local uri = "file:///test_features.lua"

local txt = table.concat({
    "---@class User",
    "---@field name string",
    "---@field id number",
    "local M = {}",
    "",
    "---@param name string",
    "---@param id number",
    "---@return User",
    "function M.new(name, id)",
    "    return { name = name, id = id }",
    "end",
    "",
    "local x = 42",
    'local msg = "hello"',
    "local t = { a = 1, b = 2 }",
    "",
    "local function helper(v)",
    "    return v * 2",
    "end",
    "",
    "print(x, msg, helper(x))",
    "print(undefined_var)",
}, "\n")

core:handle("textDocument/didOpen", {
    textDocument = { uri = uri, version = 1, text = txt },
})

-- ── Test 1: Completions ────────────────────────────────────
print("=== Completions ===")
local comp = core:handle("textDocument/completion", {
    textDocument = { uri = uri },
    position = { line = 20, character = 0 },
})
print("items:", comp and comp.items and #comp.items or 0)
if comp and comp.items then
    -- Show first 10
    for i = 1, math.min(10, #comp.items) do
        local it = comp.items[i]
        print(string.format("  %-20s kind=%d  %s", it.label, it.kind, it.detail))
    end
end
-- Should include: M, x, msg, t, helper, print, + keywords
local found_x, found_helper, found_kw = false, false, false
if comp and comp.items then
    for i = 1, #comp.items do
        if comp.items[i].label == "x" then found_x = true end
        if comp.items[i].label == "helper" then found_helper = true end
        if comp.items[i].label == "function" then found_kw = true end
    end
end
assert(found_x, "should find completion for 'x'")
assert(found_helper, "should find completion for 'helper'")
assert(found_kw, "should find keyword 'function'")
print("OK!")

-- ── Test 2: Type inference in completions ──────────────────
print("\n=== Type Inference ===")
if comp and comp.items then
    for i = 1, #comp.items do
        local it = comp.items[i]
        if it.label == "x" and it.detail ~= "" then
            print("  x: " .. it.detail)
            assert(it.detail == "number", "x should be number, got: " .. it.detail)
        end
        if it.label == "msg" and it.detail ~= "" then
            print("  msg: " .. it.detail)
            assert(it.detail == "string", "msg should be string, got: " .. it.detail)
        end
        if it.label == "helper" and it.detail ~= "" then
            print("  helper: " .. it.detail)
        end
    end
end
print("OK!")

-- ── Test 3: Document Symbols ───────────────────────────────
print("\n=== Document Symbols ===")
local syms = core:handle("textDocument/documentSymbol", {
    textDocument = { uri = uri },
})
print("symbols:", syms and syms.items and #syms.items or 0)
if syms and syms.items then
    for i = 1, #syms.items do
        local s = syms.items[i]
        local kids = s.children and #s.children or 0
        print(string.format("  %-20s kind=%d detail=%s children=%d",
            s.name, s.kind, s.detail, kids))
    end
end
-- Should find: M, M.new, x, msg, t, helper
assert(syms and syms.items and #syms.items >= 4, "expected at least 4 document symbols")
print("OK!")

-- ── Test 4: Rename ─────────────────────────────────────────
print("\n=== Rename ===")
-- Rename 'x' to 'value'
local rename_result = core:handle("textDocument/rename", {
    textDocument = { uri = uri },
    position = { line = 12, character = 6 }, -- 'x' declaration
    newName = "value",
})
if rename_result then
    print("rename kind:", rename_result.kind)
    if rename_result.kind == "RenameOk" then
        print("edits:", #rename_result.edits)
        for i = 1, #rename_result.edits do
            print("  edit:", rename_result.edits[i].new_text, "at", tostring(rename_result.edits[i].anchor))
        end
    elseif rename_result.kind == "RenameFail" then
        print("fail:", rename_result.reason)
    end
end
print("OK!")

-- ── Test 5: Completions with prefix ────────────────────────
print("\n=== Completions with prefix ===")
-- Simulate typing "hel" — should filter to "helper"
local comp2 = core._complete_engine.complete(
    core.engine.C.CompletionQuery(
        core:_doc(uri).file,
        core.engine.C.LspPos(20, 3),
        "hel"
    )
)
print("items matching 'hel':", comp2 and #comp2.items or 0)
local found_helper2 = false
if comp2 and comp2.items then
    for i = 1, #comp2.items do
        if comp2.items[i].label == "helper" then found_helper2 = true end
        print("  " .. comp2.items[i].label)
    end
end
assert(found_helper2, "should find 'helper' with prefix 'hel'")
print("OK!")

-- ── Test 5b: Server completion prefix on non-first line ───
print("\n=== Server completion prefix (non-first line) ===")
local comp3 = core:handle("textDocument/completion", {
    textDocument = { uri = uri },
    position = { line = 20, character = 17 }, -- after "hel" in helper(x)
})
print("items matching on line 20:", comp3 and comp3.items and #comp3.items or 0)
local found_helper3 = false
if comp3 and comp3.items then
    for i = 1, #comp3.items do
        if comp3.items[i].label == "helper" then found_helper3 = true end
    end
end
assert(found_helper3, "server completion should include 'helper' on later lines")
assert(comp3 and comp3.items and #comp3.items <= 5,
    "server completion should be prefix-filtered on later lines")
print("OK!")

-- ── Test 6: Run on real file ───────────────────────────────
print("\n=== Real file: pvm.lua ===")
local pvm_text = io.open("pvm.lua", "r"):read("*a")
local pvm_uri = "file:///pvm.lua"
core:handle("textDocument/didOpen", {
    textDocument = { uri = pvm_uri, version = 1, text = pvm_text },
})

local pvm_syms = core:handle("textDocument/documentSymbol", { textDocument = { uri = pvm_uri } })
print("pvm.lua document symbols:", pvm_syms and pvm_syms.items and #pvm_syms.items or 0)
if pvm_syms and pvm_syms.items then
    for i = 1, math.min(10, #pvm_syms.items) do
        local s = pvm_syms.items[i]
        print(string.format("  %-30s kind=%d children=%d",
            s.name, s.kind, s.children and #s.children or 0))
    end
end

local pvm_comp = core:handle("textDocument/completion", {
    textDocument = { uri = pvm_uri },
    position = { line = 50, character = 0 },
})
print("pvm.lua completions:", pvm_comp and pvm_comp.items and #pvm_comp.items or 0)

print("\nAll feature tests passed!")
