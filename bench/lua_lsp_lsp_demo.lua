#!/usr/bin/env luajit
-- lua_lsp_lsp_demo.lua
--
-- Demonstrates LSP-shaped payloads from the v1 adapter.

package.path = "./?.lua;./?/init.lua;" .. package.path

local Adapter = require("bench.lua_lsp_adapter_v1")
local Sem = require("bench.lua_lsp_semantics_v1").new()
local C = Sem.C

local lsp = Adapter.new(Sem)

local x_decl = C.Name("x")
local x_ref = C.NameRef("x")
local y_ref = C.NameRef("y")
local t_user = C.TNamed("User")

local file = C.File("file:///demo.lua", {
    C.Item({ C.DocBlock({ C.ClassTag("User", {}) }) },
        C.LocalAssign({ x_decl }, { C.Number("1") })
    ),
    C.Item({}, C.CallStmt(C.NameRef("print"), { x_ref, y_ref })),
})

local defs = lsp:definition(file, x_ref)
local refs = lsp:references(file, x_ref, true)
local hover_sym = lsp:hover(file, x_ref)
local hover_type = lsp:hover(file, t_user)
local diags = lsp:diagnostics(file)
local highlights = lsp:document_highlight(file, x_ref)

print("LSP adapter demo")
print("  definitions:", #(defs.items or {}))
print("  references:", #(refs.items or {}))
print("  diagnostics:", #(diags.items or {}))
print("  highlights:", #(highlights.items or {}))
print("  hover(symbol):", hover_sym and hover_sym.kind == "LspHoverHit" and hover_sym.value.contents.value or "<nil>")
print("  hover(type):", hover_type and hover_type.kind == "LspHoverHit" and hover_type.value.contents.value or "<nil>")

if #(diags.items or {}) > 0 then
    local d0 = diags.items[1]
    print("  first diagnostic:", d0.code, d0.message)
end
