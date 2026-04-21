package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Lower = require("moonlift.lower_surface_to_elab")

local T = pvm.context()
A.Define(T)
local L = Lower.Define(T)

local Surf = T.MoonliftSurface
local Elab = T.MoonliftElab

local i32 = pvm.one(L.lower_type(Surf.SurfTI32))
assert(i32 == Elab.ElabTI32)

local p_i32 = pvm.one(L.lower_type(Surf.SurfTPtr(Surf.SurfTI32)))
assert(p_i32 == Elab.ElabTPtr(Elab.ElabTI32))

local s_f32 = pvm.one(L.lower_type(Surf.SurfTSlice(Surf.SurfTF32)))
assert(s_f32 == Elab.ElabTSlice(Elab.ElabTF32))

local fn_ty = pvm.one(L.lower_type(
    Surf.SurfTFunc(
        { Surf.SurfTI32, Surf.SurfTPtr(Surf.SurfTU8) },
        Surf.SurfTVoid
    )
))
assert(fn_ty == Elab.ElabTFunc(
    { Elab.ElabTI32, Elab.ElabTPtr(Elab.ElabTU8) },
    Elab.ElabTVoid
))

local named = pvm.one(L.lower_type(
    Surf.SurfTNamed(
        Surf.SurfPath({ Surf.SurfName("Foo"), Surf.SurfName("Bar") })
    )
))
assert(named == Elab.ElabTNamed("Foo", "Bar"))

print("moonlift surface->elab type lowering ok")
