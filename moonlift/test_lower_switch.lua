package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Lower = require("moonlift.lower_surface_to_elab_loop")

local T = pvm.context()
A.Define(T)
local L = Lower.Define(T)

local Surf = T.MoonliftSurface
local Elab = T.MoonliftElab

local env = Elab.ElabEnv("", {
    Elab.ElabValueEntry("x", Elab.ElabLocalValue("env.x", "x", Elab.ElabTI32)),
}, {}, {})

local function one_expr(node)
    return pvm.one(L.lower_expr(node, env))
end

local function one_stmt(node)
    return pvm.one(L.lower_stmt(node, env))
end

local switch_stmt = one_stmt(
    Surf.SurfSwitch(
        Surf.SurfNameRef("x"),
        {
            Surf.SurfSwitchStmtArm(
                Surf.SurfInt("1"),
                { Surf.SurfExprStmt(Surf.SurfInt("11")) }
            ),
        },
        { Surf.SurfExprStmt(Surf.SurfInt("22")) }
    )
)
assert(switch_stmt == Elab.ElabSwitch(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("env.x", "x", Elab.ElabTI32)),
    {
        Elab.ElabSwitchStmtArm(
            Elab.ElabInt("1", Elab.ElabTI32),
            { Elab.ElabExprStmt(Elab.ElabInt("11", Elab.ElabTI32)) }
        ),
    },
    { Elab.ElabExprStmt(Elab.ElabInt("22", Elab.ElabTI32)) }
))

local switch_expr = one_expr(
    Surf.SurfSwitchExpr(
        Surf.SurfNameRef("x"),
        {
            Surf.SurfSwitchExprArm(
                Surf.SurfInt("1"),
                { Surf.SurfExprStmt(Surf.SurfNameRef("x")) },
                Surf.SurfInt("11")
            ),
        },
        Surf.SurfInt("22")
    )
)
assert(switch_expr == Elab.ElabSwitchExpr(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("env.x", "x", Elab.ElabTI32)),
    {
        Elab.ElabSwitchExprArm(
            Elab.ElabInt("1", Elab.ElabTI32),
            { Elab.ElabExprStmt(Elab.ElabBindingExpr(Elab.ElabLocalValue("env.x", "x", Elab.ElabTI32))) },
            Elab.ElabInt("11", Elab.ElabTI32)
        ),
    },
    Elab.ElabInt("22", Elab.ElabTI32),
    Elab.ElabTI32
))

print("moonlift surface->elab switch lowering ok")
