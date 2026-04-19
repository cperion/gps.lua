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

local source = C.OpenDoc("file:///test.lua", 0, src1)
local result = pvm.one(engine.parse(source))
local file = result

print("uri:", file.uri)
print("items:", #file.items)
for i = 1, #file.items do
    print("  item", i, "stmt:", file.items[i].core.stmt.kind)
end
print("anchors:", #file.anchors)
assert(#file.items == 3, "expected 3 items, got " .. #file.items)
assert(file.items[1].core.stmt.kind == "LocalAssign")
assert(file.items[2].core.stmt.kind == "LocalAssign")
assert(file.items[3].core.stmt.kind == "CallStmt")
print("OK!")

-- ── Test 2: interning ──────────────────────────────────────
print("\n=== Test 2: ASDL interning ===")
local src2 = table.concat({
    "local x = 42",
    'local y = "hello"',
    "print(x, y)",
}, "\n")
local source2 = C.OpenDoc("file:///test.lua", 0, src2)
local result2 = pvm.one(engine.parse(source2))

-- Same source text → same OpenDoc → parse cache hit
assert(source == source2, "same text should produce same OpenDoc")
print("OpenDoc interning: OK (same text → same object)")

-- Same structural content → same AST nodes
local name_x_1 = file.items[1].core.stmt.names[1]     -- Name("x") from first parse
local name_x_2 = result2.items[1].core.stmt.names[1]  -- Name("x") from second parse
assert(name_x_1 == name_x_2, "Name('x') should be same interned object")
print("Name interning: OK")

-- ── Test 3: incremental cache behavior ─────────────────────
print("\n=== Test 3: incremental caching ===")
local src3 = table.concat({
    "local x = 42",
    'local y = "world"',  -- changed "hello" → "world"
    "print(x, y)",
}, "\n")
local source3 = C.OpenDoc("file:///test.lua", 0, src3)
local result3 = pvm.one(engine.parse(source3))

-- Different source → different OpenDoc → parse cache miss
assert(source ~= source3, "different text should produce different OpenDoc")

-- But unchanged items should be same interned objects!
local item1_old = file.items[1].core  -- local x = 42
local item1_new = result3.items[1].core  -- local x = 42 (unchanged)
assert(item1_old == item1_new, "unchanged Item core should be same interned object")
print("Unchanged Item core interning: OK (local x = 42 is same object)")

local item3_old = file.items[3].core  -- print(x, y)
local item3_new = result3.items[3].core  -- print(x, y) (unchanged)
assert(item3_old == item3_new, "unchanged Item core should be same interned object")
print("Unchanged Item core interning: OK (print(x, y) is same object)")

local item2_old = file.items[2].core  -- local y = "hello"
local item2_new = result3.items[2].core  -- local y = "world"
assert(item2_old ~= item2_new, "changed Item core should be different object")
print("Changed Item core: OK (different objects)")

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

local source4 = C.OpenDoc("file:///complex.lua", 0, src4)
local result4 = pvm.one(engine.parse(source4))
print("items:", #result4.items)
print("anchors:", #result4.anchors)
print("parse_error:", result4.status.kind == "ParseError" and result4.status.message or "")
for i = 1, math.min(15, #result4.items) do
    local item = result4.items[i].core
    local docs_str = #item.docs > 0 and (" [" .. #item.docs[1].tags .. " doc tags]") or ""
    print(string.format("  item %2d: %-20s%s", i, item.stmt.kind, docs_str))
end
assert(result4.status.kind == "ParseOk", "should parse without errors")
print("OK!")

-- ── Test 5: pvm phase caching ──────────────────────────────
print("\n=== Test 5: pvm cache behavior ===")
-- Parse same source twice — should be cache hit
local r5a = pvm.one(engine.parse(source4))
local r5b = pvm.one(engine.parse(source4))
assert(r5a == r5b, "same OpenDoc → same parse result (cache hit)")
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
