#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local ASDL = require("lsp.asdl")
local Parser = require("lsp.parser")
local Semantics = require("lsp.semantics")

local ctx = ASDL.context()
local C = ctx.Lua
local parser = Parser.new(ctx)
local sem = Semantics.new(ctx)

-- ── Helper: parse source and run semantics ─────────────────
local function analyze(uri, text)
    local source = C.OpenDoc(uri, 0, text)
    local parsed = pvm.one(parser.parse(source))
    return sem:compile(parsed)
end

-- ── Test 1: basic diagnostics ──────────────────────────────
print("=== Test 1: diagnostics ===")
local file1 = analyze("file:///test.lua", table.concat({
    "local x = 42",
    "local y = 100",
    "print(x, z)",
}, "\n"))

local diags1 = pvm.drain(sem.diagnostics(file1))
print("diagnostics:", #diags1)
for i = 1, #diags1 do
    print("  ", diags1[i].code, diags1[i].message)
end
-- Should find: undefined global 'z', unused local 'y'
local function code_name(c)
    local k = tostring(c):match("^Lua%.([%w_]+)") or tostring(c)
    if k == "DiagUndefinedGlobal" then return "undefined-global" end
    if k == "DiagUnusedLocal" then return "unused-local" end
    if k == "DiagUnusedParam" then return "unused-param" end
    return k
end

local found_z, found_y = false, false
for i = 1, #diags1 do
    local code = code_name(diags1[i].code)
    if code == "undefined-global" and diags1[i].name == "z" then found_z = true end
    if code == "unused-local" and diags1[i].name == "y" then found_y = true end
end
assert(found_z, "should find undefined global z")
assert(found_y, "should find unused local y")
print("OK!")

-- ── Test 2: doc types ──────────────────────────────────────
print("\n=== Test 2: doc types ===")
local file2 = analyze("file:///types.lua", table.concat({
    "---@class User",
    "---@field name string",
    "---@field id number",
    "local M = {}",
    "---@alias UserId number",
    "local x = 1",
}, "\n"))

local env = sem.resolve_named_types(file2)
print("classes:", #env.classes)
print("aliases:", #env.aliases)
for i = 1, #env.classes do
    print("  class:", env.classes[i].name, "fields:", #env.classes[i].fields)
end
for i = 1, #env.aliases do
    print("  alias:", env.aliases[i].name)
end
assert(#env.classes == 1, "expected 1 class")
assert(env.classes[1].name == "User")
assert(#env.classes[1].fields == 2, "expected 2 fields")
assert(#env.aliases == 1, "expected 1 alias")
print("OK!")

-- ── Test 3: symbol index ───────────────────────────────────
print("\n=== Test 3: symbol index ===")
local file3 = analyze("file:///symbols.lua", table.concat({
    "local x = 42",
    "local y = x + 1",
    "print(y)",
}, "\n"))

local idx = sem:index(file3)
print("symbols:", #idx.symbols)
print("defs:", #idx.defs)
print("uses:", #idx.uses)
print("unresolved:", #idx.unresolved)
for i = 1, #idx.symbols do
    print("  sym:", idx.symbols[i].id, idx.symbols[i].kind, idx.symbols[i].name)
end
print("OK!")

-- ── Test 4: hover ──────────────────────────────────────────
print("\n=== Test 4: hover ===")
-- Find the anchor for x's declaration
local x_anchor = nil
for i = 1, #idx.defs do
    if idx.defs[i].name == "x" then x_anchor = idx.defs[i].anchor; break end
end
if x_anchor then
    local h = pvm.one(sem:hover(file3, x_anchor))
    print("hover kind:", h.kind)
    if h.kind == "HoverSymbol" then
        print("  name:", h.name, "symbol_kind:", h.symbol_kind, "defs:", h.defs, "uses:", h.uses)
    end
    assert(h.kind == "HoverSymbol", "expected HoverSymbol")
    print("OK!")
else
    print("SKIP: no x anchor found")
end

-- ── Test 5: goto definition ────────────────────────────────
print("\n=== Test 5: goto definition ===")
-- Find anchor for a reference to x
local x_use_anchor = nil
for i = 1, #idx.uses do
    if idx.uses[i].name == "x" then x_use_anchor = idx.uses[i].anchor; break end
end
if x_use_anchor then
    local def = pvm.one(sem:goto_definition(file3, x_use_anchor))
    print("definition kind:", def.kind)
    if def.kind == "DefHit" then
        print("  anchor:", tostring(def.anchor))
    end
    assert(def.kind == "DefHit", "expected DefHit")
    print("OK!")
else
    print("SKIP: no x use anchor found")
end

-- ── Test 6: find references ────────────────────────────────
print("\n=== Test 6: find references ===")
if x_anchor then
    local refs = pvm.drain(sem:find_references(file3, x_anchor, true))
    print("references (incl decl):", #refs)
    for i = 1, #refs do
        print("  ref:", refs[i].name, refs[i].kind)
    end
    assert(#refs >= 2, "expected at least 2 refs (decl + use)")
    print("OK!")
end

-- ── Test 7: incremental caching ────────────────────────────
print("\n=== Test 7: incremental semantics caching ===")
local file4a = analyze("file:///inc.lua", table.concat({
    "local a = 1",
    "local b = 2",
    "print(a, b)",
}, "\n"))
local diags_a = pvm.drain(sem.diagnostics(file4a))

-- Change one line
local file4b = analyze("file:///inc.lua", table.concat({
    "local a = 1",
    "local b = 999",  -- changed
    "print(a, b)",
}, "\n"))
local diags_b = pvm.drain(sem.diagnostics(file4b))

-- Items should share identity where unchanged
assert(file4a.items[1].syntax == file4b.items[1].syntax, "item 1 syntax should be shared (local a = 1)")
assert(file4a.items[2].syntax ~= file4b.items[2].syntax, "item 2 should differ")
assert(file4a.items[3].syntax == file4b.items[3].syntax, "item 3 syntax should be shared (print(a, b))")
print("Item sharing: OK")
print("Diags before:", #diags_a, "after:", #diags_b)

-- ── Test 8: cache report ───────────────────────────────────
print("\n=== Test 8: cache report ===")
print(sem:report_string())

print("\nAll semantics tests passed!")
