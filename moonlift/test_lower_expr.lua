package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Lower = require("moonlift.lower_surface_to_elab_expr")

local T = pvm.context()
A.Define(T)
local L = Lower.Define(T)

local Surf = T.MoonliftSurface
local Elab = T.MoonliftElab

local env = Elab.ElabEnv({
    Elab.ElabValueEntry("x", Elab.ElabLocalValue("env.x", "x", Elab.ElabTI32)),
    Elab.ElabValueEntry("y", Elab.ElabArg(1, "y", Elab.ElabTI32)),
    Elab.ElabValueEntry("flag", Elab.ElabLocalValue("env.flag", "flag", Elab.ElabTBool)),
    Elab.ElabValueEntry("sum", Elab.ElabGlobal("", "sum", Elab.ElabTFunc({ Elab.ElabTI32 }, Elab.ElabTI32))),
    Elab.ElabValueEntry("ptr", Elab.ElabLocalValue("env.ptr", "ptr", Elab.ElabTPtr(Elab.ElabTF32))),
    Elab.ElabValueEntry("pair", Elab.ElabLocalValue("env.pair", "pair", Elab.ElabTNamed("Demo", "Pair"))),
}, {}, {
    Elab.ElabLayoutNamed("Demo", "Pair", {
        Elab.ElabFieldType("left", Elab.ElabTI32),
        Elab.ElabFieldType("right", Elab.ElabTI32),
    }),
})

local function one(e, expected)
    return pvm.one(L.lower_expr(e, env, expected))
end

local i = one(Surf.SurfInt("42"))
assert(i == Elab.ElabInt("42", Elab.ElabTI32))

local f = one(Surf.SurfFloat("3.14"))
assert(f == Elab.ElabFloat("3.14", Elab.ElabTF64))

local b = one(Surf.SurfBool(true))
assert(b == Elab.ElabBool(true, Elab.ElabTBool))

local nil_i32 = one(Surf.SurfNil, Elab.ElabTI32)
assert(nil_i32 == Elab.ElabNil(Elab.ElabTI32))

local xr = one(Surf.SurfNameRef("x"))
assert(xr == Elab.ElabBindingExpr(Elab.ElabLocalValue("env.x", "x", Elab.ElabTI32)))

local neg = one(Surf.SurfExprNeg(Surf.SurfNameRef("x")))
assert(neg == Elab.ElabExprNeg(Elab.ElabTI32, xr))

local add = one(Surf.SurfExprAdd(
    Surf.SurfNameRef("x"),
    Surf.SurfInt("1")
))
assert(add == Elab.ElabExprAdd(
    Elab.ElabTI32,
    xr,
    Elab.ElabInt("1", Elab.ElabTI32)
))

local cmp = one(Surf.SurfExprLt(
    Surf.SurfNameRef("x"),
    Surf.SurfNameRef("y")
))
assert(cmp == Elab.ElabExprLt(
    Elab.ElabTBool,
    Elab.ElabBindingExpr(Elab.ElabLocalValue("env.x", "x", Elab.ElabTI32)),
    Elab.ElabBindingExpr(Elab.ElabArg(1, "y", Elab.ElabTI32))
))

local casted = one(Surf.SurfExprCastTo(Surf.SurfTF64, Surf.SurfInt("7")))
assert(casted == Elab.ElabExprCastTo(
    Elab.ElabTF64,
    Elab.ElabInt("7", Elab.ElabTI32)
))

local call = one(Surf.SurfCall(Surf.SurfNameRef("sum"), { Surf.SurfInt("7") }))
assert(call == Elab.ElabCall(
    Elab.ElabBindingExpr(Elab.ElabGlobal("", "sum", Elab.ElabTFunc({ Elab.ElabTI32 }, Elab.ElabTI32))),
    Elab.ElabTI32,
    { Elab.ElabInt("7", Elab.ElabTI32) }
))

local index = one(Surf.SurfIndex(Surf.SurfNameRef("ptr"), Surf.SurfInt("1")))
assert(index == Elab.ElabIndex(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("env.ptr", "ptr", Elab.ElabTPtr(Elab.ElabTF32))),
    Elab.ElabInt("1", Elab.ElabTIndex),
    Elab.ElabTF32
))

local field = one(Surf.SurfField(Surf.SurfNameRef("pair"), "left"))
assert(field == Elab.ElabField(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("env.pair", "pair", Elab.ElabTNamed("Demo", "Pair"))),
    "left",
    Elab.ElabTI32
))

local agg = one(Surf.SurfAgg(
    Surf.SurfTNamed(Surf.SurfPath({ Surf.SurfName("Demo"), Surf.SurfName("Pair") })),
    {
        Surf.SurfFieldInit("left", Surf.SurfInt("1")),
        Surf.SurfFieldInit("right", Surf.SurfInt("2")),
    }
))
assert(agg == Elab.ElabAgg(
    Elab.ElabTNamed("Demo", "Pair"),
    {
        Elab.ElabFieldInit("left", Elab.ElabInt("1", Elab.ElabTI32)),
        Elab.ElabFieldInit("right", Elab.ElabInt("2", Elab.ElabTI32)),
    }
))

local array = one(Surf.SurfArrayLit(Surf.SurfTI32, { Surf.SurfInt("3"), Surf.SurfInt("4") }))
assert(array == Elab.ElabArrayLit(
    Elab.ElabTArray(Elab.ElabInt("2", Elab.ElabTIndex), Elab.ElabTI32),
    {
        Elab.ElabInt("3", Elab.ElabTI32),
        Elab.ElabInt("4", Elab.ElabTI32),
    }
))

print("moonlift surface->elab expr lowering ok")
