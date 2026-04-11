#!/usr/bin/env luajit
-- lua_lsp_queries_demo.lua
--
-- Demonstrates goto-definition / references / hover over the v1 semantic engine.

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local Sem = require("bench.lua_lsp_semantics_v1").new()
local C = Sem.C

local x_decl = C.Name("x")
local x_ref1 = C.NameRef("x")
local x_ref2 = C.NameRef("x")
local y_ref = C.NameRef("y")

local docs = C.DocBlock({
    C.ClassTag("User", {}),
    C.FieldTag("id", C.TNumber(), false),
    C.AliasTag("UserId", C.TNumber()),
})

local file = C.File("file:///demo.lua", {
    C.Item({ docs }, C.LocalAssign({ x_decl }, { C.Number("1") })),
    C.Item({}, C.CallStmt(C.NameRef("print"), { x_ref1, y_ref, x_ref2 })),
})

local def = Sem:goto_definition(file, x_ref1)
local refs = Sem:find_references(file, x_ref1, true)
local hover_x = Sem:hover(file, x_ref1)
local hover_y = Sem:hover(file, y_ref)
local hover_ty = Sem:hover(file, C.TNamed("User"))

print("queries demo")
print("  goto x -> decl anchor is x_decl?", def.kind == "DefHit" and def.anchor and def.anchor.id == tostring(x_decl), def.meta and def.meta.kind or "nil")
print("  references(x, include def):", #(refs.refs or {}))
print("  hover(x):", hover_x and hover_x.name, hover_x and hover_x.symbol_kind, "uses=" .. tostring(hover_x and hover_x.uses))
print("  hover(y):", hover_y and hover_y.kind, hover_y and hover_y.name)
print("  hover(TNamed('User')):", hover_ty and hover_ty.detail, hover_ty and hover_ty.name)

-- tiny edit keeping x nodes shared
local file2 = pvm.with(file, {
    items = {
        file.items[1],
        C.Item({}, C.CallStmt(C.NameRef("print"), { x_ref1, C.NameRef("z"), x_ref2 })),
    }
})

local idx1 = Sem:index(file)
local idx2 = Sem:index(file2)
local b1 = Sem:symbol_for_anchor(file, x_ref1)
local b2 = Sem:symbol_for_anchor(file2, x_ref1)
local sym1 = (b1.kind == "AnchorSymbol") and b1.symbol or nil
local sym2 = (b2.kind == "AnchorSymbol") and b2.symbol or nil

print("")
print("incremental stability")
print("  symbol id stable across tiny edit?", sym1 and sym2 and (sym1.id == sym2.id) or false)
print("  unresolved before/after:", #idx1.unresolved, #idx2.unresolved)

print("")
print("phase stats")
print(Sem:report_string())
