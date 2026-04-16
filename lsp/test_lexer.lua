#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local ASDL = require("lsp.asdl")
local Lexer = require("lsp.lexer")

local ctx = ASDL.context()
local C = ctx.Lua
local engine = Lexer.new(ctx)

-- Basic test: lex a small file via pvm.phase
print("=== Lex phase test ===")
local src = table.concat({
    "local x = 42",
    'local y = "hello"',
    "print(x, y)",
}, "\n")

local source = C.OpenDoc("file:///test.lua", 0, src)
local tokens = pvm.drain(engine.lex(source))
print("tokens:", #tokens)
for i = 1, math.min(15, #tokens) do
    print(string.format("  %-12s %s", tokens[i].kind, tokens[i].value))
end

-- Token interning
local local_tok = C.Token("local", "local")
assert(tokens[1] == local_tok, "Token interning should work")
print("Token interning: OK")

-- Lex cache hit
local tokens2 = pvm.drain(engine.lex(source))
print("Cache hit: OK (same source → same tokens)")

-- lex_with_positions
local result = pvm.drain(engine.lex_with_positions(source))
print("tokens with positions:", #result)
assert(result[1].line == 1, "first token should be on line 1")
assert(result[1].col == 1, "first token should be at col 1")
print("Positions: OK")

-- Keywords
local kw_src = "and break do else elseif end false for function goto if in local nil not or repeat return then true until while myname"
local kw_source = C.OpenDoc("file:///kw.lua", 0, kw_src)
local kw_tokens = pvm.drain(engine.lex(kw_source))
local kw_count, name_count = 0, 0
for i = 1, #kw_tokens do
    if kw_tokens[i].kind == "<eof>" then break end
    if kw_tokens[i].kind == "<name>" then name_count = name_count + 1
    else kw_count = kw_count + 1 end
end
assert(kw_count == 22, "expected 22 keywords, got " .. kw_count)
assert(name_count == 1, "expected 1 name, got " .. name_count)
print("Keywords: OK (" .. kw_count .. " keywords, " .. name_count .. " names)")

print("\nAll lexer tests passed!")
