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
    return pvm.one(parser.parse(source))
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
assert(file4a.items[1].core == file4b.items[1].core, "item 1 core should be shared (local a = 1)")
assert(file4a.items[2].core ~= file4b.items[2].core, "item 2 core should differ")
assert(file4a.items[3].core.stmt == file4b.items[3].core.stmt, "item 3 statement should be shared even if span shifts")
print("Semantic cache boundary sharing: OK")
print("Diags before:", #diags_a, "after:", #diags_b)

-- ── Test 8: function-body semantic caching ─────────────────
print("\n=== Test 8: function-body semantic caching ===")
local file5a = analyze("file:///funcs.lua", table.concat({
    "local function keep(x)",
    "  local y = x + 1",
    "  return y",
    "end",
    "",
    "local function edit(z)",
    "  local w = z + 2",
    "  return w",
    "end",
}, "\n"))
local file5b = analyze("file:///funcs.lua", table.concat({
    "local function keep(x)",
    "  local y = x + 1",
    "  return y",
    "end",
    "",
    "local function edit(z)",
    "  local w = z + 999",
    "  return w",
    "end",
}, "\n"))
local keep_a = file5a.items[1].core.stmt.body
local keep_b = file5b.items[1].core.stmt.body
local edit_a = file5a.items[2].core.stmt.body
local edit_b = file5b.items[2].core.stmt.body
assert(keep_a == keep_b, "unchanged function body should be shared")
assert(edit_a ~= edit_b, "changed function body should differ")
assert(sem:func_semantics(keep_a) == sem:func_semantics(keep_b), "func_semantics should cache on unchanged body")
print("FuncSemantics caching: OK")

-- ── Test 9: cached whole-file assemblies ───────────────────
print("\n=== Test 9: cached whole-file assemblies ===")
local env_a = sem:type_env(file3)
local env_b = sem:type_env(file3)
assert(env_a == env_b, "type_env should be cached per ParsedDoc")

local idx_a = sem:index(file3)
local idx_b = sem:index(file3)
assert(idx_a == idx_b, "symbol_index should be cached per ParsedDoc")

local local_diags_a = sem:local_scope_diagnostics(file3)
local local_diags_b = sem:local_scope_diagnostics(file3)
assert(local_diags_a == local_diags_b, "local_scope_diagnostics should be cached per ParsedDoc")

local type_diags_a = sem:type_diagnostics(file3)
local type_diags_b = sem:type_diagnostics(file3)
assert(type_diags_a == type_diags_b, "type_diagnostics should be cached per ParsedDoc")

local diags_cached_a = pvm.drain(sem:diagnostics(file3))
local diags_cached_b = pvm.drain(sem:diagnostics(file3))
assert(#diags_cached_a == #diags_cached_b, "diagnostics should replay stably from cache")
print("Cached assemblies: OK")

-- ── Test 10: cache report ──────────────────────────────────
print("\n=== Test 10: cache report ===")
print(sem:report_string())

print("\nAll semantics tests passed!")
