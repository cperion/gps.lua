#!/usr/bin/env luajit
-- lua_lsp_symbol_index_demo.lua
--
-- Demonstrates stable symbol IDs across tiny edits when node identity is reused.

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local Sem = require("bench.lua_lsp_semantics_v1").new()
local C = Sem.C

local x_decl = C.Name("x")
local x_ref = C.NameRef("x")
local y_ref = C.NameRef("y")

local item1 = C.Item({}, C.LocalAssign({ x_decl }, { C.Number("1") }))
local item2 = C.Item({}, C.CallStmt(C.NameRef("print"), { x_ref, y_ref }))

local file1 = C.File("file:///demo.lua", { item1, item2 })

local idx1 = Sem:index(file1)
local b1 = Sem:symbol_for_anchor(file1, x_ref)
local sym_x_1 = (b1.kind == "AnchorSymbol") and b1.symbol or nil

-- tiny edit: y -> z, keep x declaration/ref nodes shared
local item2b = C.Item({}, C.CallStmt(C.NameRef("print"), { x_ref, C.NameRef("z") }))
local file2 = pvm.with(file1, { items = { item1, item2b } })

local idx2 = Sem:index(file2)
local b2 = Sem:symbol_for_anchor(file2, x_ref)
local sym_x_2 = (b2.kind == "AnchorSymbol") and b2.symbol or nil

print("symbol-id stability demo")
print("  x id before:", sym_x_1 and sym_x_1.id or "<nil>")
print("  x id after :", sym_x_2 and sym_x_2.id or "<nil>")
print("  stable?    ", sym_x_1 and sym_x_2 and (sym_x_1.id == sym_x_2.id) or false)
print("  unresolved1:", #idx1.unresolved, "unresolved2:", #idx2.unresolved)

print("")
print("phase stats")
print(Sem:report_string())
