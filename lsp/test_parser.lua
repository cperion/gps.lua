#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local ASDL = require("lsp.asdl")
local Parser = require("lsp.parser")

local ctx = ASDL.context()
local C = ctx.Lua
local engine = Parser.new(ctx)

-- ── Test 1: basic parsing ──────────────────────────────────
print("=== Test 1: basic parsing ===")
local src1 = table.concat({
    "local x = 42",
    'local y = "hello"',
    "print(x, y)",
}, "\n")

local source = C.SourceFile("file:///test.lua", src1)
local result = engine.parse(source)
local file = result.file
local meta = result.meta

print("uri:", file.uri)
print("items:", #file.items)
for i = 1, #file.items do
    print("  item", i, "stmt:", file.items[i].stmt.kind)
end
print("anchors:", #meta.positions)
assert(#file.items == 3, "expected 3 items, got " .. #file.items)
assert(file.items[1].stmt.kind == "LocalAssign")
assert(file.items[2].stmt.kind == "LocalAssign")
assert(file.items[3].stmt.kind == "CallStmt")
print("OK!")

-- ── Test 2: interning ──────────────────────────────────────
print("\n=== Test 2: ASDL interning ===")
local src2 = table.concat({
    "local x = 42",
    'local y = "hello"',
    "print(x, y)",
}, "\n")
local source2 = C.SourceFile("file:///test.lua", src2)
local result2 = engine.parse(source2)

-- Same source text → same SourceFile → parse cache hit
assert(source == source2, "same text should produce same SourceFile")
print("SourceFile interning: OK (same text → same object)")

-- Same structural content → same AST nodes
local name_x_1 = file.items[1].stmt.names[1]     -- Name("x") from first parse
local name_x_2 = result2.file.items[1].stmt.names[1]  -- Name("x") from second parse
assert(name_x_1 == name_x_2, "Name('x') should be same interned object")
print("Name interning: OK")

-- ── Test 3: incremental cache behavior ─────────────────────
print("\n=== Test 3: incremental caching ===")
local src3 = table.concat({
    "local x = 42",
    'local y = "world"',  -- changed "hello" → "world"
    "print(x, y)",
}, "\n")
local source3 = C.SourceFile("file:///test.lua", src3)
local result3 = engine.parse(source3)

-- Different source → different SourceFile → parse cache miss
assert(source ~= source3, "different text should produce different SourceFile")

-- But unchanged items should be same interned objects!
local item1_old = file.items[1]  -- local x = 42
local item1_new = result3.file.items[1]  -- local x = 42 (unchanged)
assert(item1_old == item1_new, "unchanged Item should be same interned object")
print("Unchanged Item interning: OK (local x = 42 is same object)")

local item3_old = file.items[3]  -- print(x, y)
local item3_new = result3.file.items[3]  -- print(x, y) (unchanged)
assert(item3_old == item3_new, "unchanged Item should be same interned object")
print("Unchanged Item interning: OK (print(x, y) is same object)")

local item2_old = file.items[2]  -- local y = "hello"
local item2_new = result3.file.items[2]  -- local y = "world"
assert(item2_old ~= item2_new, "changed Item should be different object")
print("Changed Item: OK (different objects)")

-- ── Test 4: complex Lua ────────────────────────────────────
print("\n=== Test 4: complex Lua ===")
local src4 = table.concat({
    "---@class User",
    "---@field name string",
    "---@field id number",
    "local M = {}",
    "",
    "function M.new(name, id)",
    "    return { name = name, id = id }",
    "end",
    "",
    "local function helper(x)",
    "    if x > 0 then",
    "        return x * 2",
    "    elseif x == 0 then",
    "        return 0",
    "    else",
    "        return -x",
    "    end",
    "end",
    "",
    "for i = 1, 10 do",
    "    local v = helper(i)",
    "    print(v)",
    "end",
    "",
    "for k, v in pairs(M) do",
    "    print(k, v)",
    "end",
    "",
    "while true do",
    "    break",
    "end",
    "",
    "repeat",
    "    x = x + 1",
    "until x > 100",
    "",
    "do",
    "    local temp = 42",
    "end",
    "",
    "::label::",
    "goto label",
    "",
    "return M",
}, "\n")

local source4 = C.SourceFile("file:///complex.lua", src4)
local result4 = engine.parse(source4)
print("items:", #result4.file.items)
print("anchors:", #result4.meta.positions)
print("parse_error:", result4.meta.parse_error)
for i = 1, math.min(15, #result4.file.items) do
    local item = result4.file.items[i]
    local docs_str = #item.docs > 0 and (" [" .. #item.docs[1].tags .. " doc tags]") or ""
    print(string.format("  item %2d: %-20s%s", i, item.stmt.kind, docs_str))
end
assert(result4.meta.parse_error == "", "should parse without errors: " .. result4.meta.parse_error)
print("OK!")

-- ── Test 5: pvm phase caching ──────────────────────────────
print("\n=== Test 5: pvm cache behavior ===")
-- Parse same source twice — should be cache hit
local r5a = engine.parse(source4)
local r5b = engine.parse(source4)
assert(r5a == r5b, "same SourceFile → same parse result (cache hit)")
print("Parse cache hit: OK")

-- Lex phase caching
local tokens_a = pvm.drain(engine.lexer.lex(source4))
local tokens_b = pvm.drain(engine.lexer.lex(source4))
-- Second drain should be from cache (seq hit)
print("Lex tokens:", #tokens_a)
-- Token interning
local local_tok = C.Token("local", "local")
for i = 1, #tokens_a do
    if tokens_a[i].kind == "local" then
        assert(tokens_a[i] == local_tok, "Token interning broken")
        break
    end
end
print("Token interning: OK")

print("\nAll parser tests passed!")
