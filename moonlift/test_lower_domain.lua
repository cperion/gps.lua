package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Lower = require("moonlift.lower_surface_to_elab_domain")

local T = pvm.context()
A.Define(T)
local L = Lower.Define(T)

local Surf = T.MoonliftSurface
local Elab = T.MoonliftElab

local env = Elab.ElabEnv({
    Elab.ElabValueEntry("n", Elab.ElabLocalValue("env.n", "n", Elab.ElabTI32)),
    Elab.ElabValueEntry("a", Elab.ElabLocalValue("env.a", "a", Elab.ElabTI32)),
    Elab.ElabValueEntry("b", Elab.ElabArg(1, "b", Elab.ElabTI32)),
    Elab.ElabValueEntry("dst", Elab.ElabLocalValue("env.dst", "dst", Elab.ElabTPtr(Elab.ElabTF32))),
    Elab.ElabValueEntry("src", Elab.ElabArg(2, "src", Elab.ElabTPtr(Elab.ElabTF32))),
    Elab.ElabValueEntry("tag", Elab.ElabLocalValue("env.tag", "tag", Elab.ElabTI32)),
}, {}, {})

local function path1(name)
    return Surf.SurfNameRef(name)
end

local function one(d)
    return pvm.one(L.lower_domain(d, env))
end

local r1 = one(Surf.SurfDomainRange(path1("n")))
assert(r1 == Elab.ElabDomainRange(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("env.n", "n", Elab.ElabTI32))
))

local r2 = one(Surf.SurfDomainRange2(path1("a"), path1("b")))
assert(r2 == Elab.ElabDomainRange2(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("env.a", "a", Elab.ElabTI32)),
    Elab.ElabBindingExpr(Elab.ElabArg(1, "b", Elab.ElabTI32))
))

local z = one(Surf.SurfDomainZipEq({ path1("dst"), path1("src") }))
assert(z == Elab.ElabDomainZipEq({
    Elab.ElabBindingExpr(Elab.ElabLocalValue("env.dst", "dst", Elab.ElabTPtr(Elab.ElabTF32))),
    Elab.ElabBindingExpr(Elab.ElabArg(2, "src", Elab.ElabTPtr(Elab.ElabTF32))),
}))

local dv = one(Surf.SurfDomainValue(path1("dst")))
assert(dv == Elab.ElabDomainValue(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("env.dst", "dst", Elab.ElabTPtr(Elab.ElabTF32)))
))

local rs = one(Surf.SurfDomainRange(
    Surf.SurfSwitchExpr(
        Surf.SurfNameRef("tag"),
        {
            Surf.SurfSwitchExprArm(
                Surf.SurfInt("1"),
                {},
                Surf.SurfNameRef("a")
            ),
        },
        Surf.SurfNameRef("b")
    )
))
assert(rs == Elab.ElabDomainRange(
    Elab.ElabSwitchExpr(
        Elab.ElabBindingExpr(Elab.ElabLocalValue("env.tag", "tag", Elab.ElabTI32)),
        {
            Elab.ElabSwitchExprArm(
                Elab.ElabInt("1", Elab.ElabTI32),
                {},
                Elab.ElabBindingExpr(Elab.ElabLocalValue("env.a", "a", Elab.ElabTI32))
            ),
        },
        Elab.ElabBindingExpr(Elab.ElabArg(1, "b", Elab.ElabTI32)),
        Elab.ElabTI32
    )
))

print("moonlift surface->elab domain lowering ok")
