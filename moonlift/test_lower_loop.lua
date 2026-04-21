package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Lower = require("moonlift.lower_surface_to_elab_loop")

local T = pvm.context()
A.Define(T)
local L = Lower.Define(T)

local Surf = T.MoonliftSurface
local Elab = T.MoonliftElab

local env = Elab.ElabEnv({
    Elab.ElabValueEntry("n", Elab.ElabLocalValue("env.n", "n", Elab.ElabTI32)),
    Elab.ElabValueEntry("p", Elab.ElabLocalValue("env.p", "p", Elab.ElabTPtr(Elab.ElabTI32))),
}, {}, {})

local function one_loop_expr(node)
    return pvm.one(L.lower_loop_expr(node, env))
end

local function one_loop_stmt(node)
    return pvm.one(L.lower_loop_stmt(node, env))
end

local function one_stmt(node)
    return pvm.one(L.lower_stmt(node, env))
end

local while_expr = one_loop_expr(
    Surf.SurfLoopWhileExpr(
        {
            Surf.SurfLoopVarInit("i", Surf.SurfTI32, Surf.SurfInt("0")),
            Surf.SurfLoopVarInit("acc", Surf.SurfTI32, Surf.SurfInt("0")),
        },
        Surf.SurfExprLt(Surf.SurfNameRef("i"), Surf.SurfNameRef("n")),
        {
            Surf.SurfLet("xi", Surf.SurfTI32, Surf.SurfNameRef("i")),
        },
        {
            Surf.SurfLoopNextAssign("i", Surf.SurfExprAdd(Surf.SurfNameRef("i"), Surf.SurfInt("1"))),
            Surf.SurfLoopNextAssign("acc", Surf.SurfExprAdd(Surf.SurfNameRef("acc"), Surf.SurfNameRef("xi"))),
        },
        Surf.SurfNameRef("acc")
    )
)
assert(while_expr.ty == Elab.ElabTI32)
assert(while_expr.loop ~= nil)

local store_stmt = one_stmt(
    Surf.SurfStore(Surf.SurfTI32, Surf.SurfNameRef("p"), Surf.SurfInt("9"))
)
assert(store_stmt == Elab.ElabStore(
    Elab.ElabTI32,
    Elab.ElabBindingExpr(Elab.ElabLocalValue("env.p", "p", Elab.ElabTPtr(Elab.ElabTI32))),
    Elab.ElabInt("9", Elab.ElabTI32)
))

local break_loop = one_loop_stmt(
    Surf.SurfLoopWhileStmt(
        { Surf.SurfLoopVarInit("i", Surf.SurfTI32, Surf.SurfInt("0")) },
        Surf.SurfBool(true),
        { Surf.SurfBreak },
        { Surf.SurfLoopNextAssign("i", Surf.SurfExprAdd(Surf.SurfNameRef("i"), Surf.SurfInt("1"))) }
    )
)
assert(break_loop.body[1] == Elab.ElabBreak)

local continue_loop = one_loop_stmt(
    Surf.SurfLoopWhileStmt(
        { Surf.SurfLoopVarInit("i", Surf.SurfTI32, Surf.SurfInt("0")) },
        Surf.SurfBool(true),
        { Surf.SurfContinue },
        { Surf.SurfLoopNextAssign("i", Surf.SurfExprAdd(Surf.SurfNameRef("i"), Surf.SurfInt("1"))) }
    )
)
assert(continue_loop.body[1] == Elab.ElabContinue)

local over_stmt = one_loop_stmt(
    Surf.SurfLoopOverStmt(
        "i",
        Surf.SurfDomainRange(Surf.SurfNameRef("n")),
        {
            Surf.SurfLoopVarInit("acc", Surf.SurfTI32, Surf.SurfInt("0")),
        },
        {},
        {
            Surf.SurfLoopNextAssign("acc", Surf.SurfExprAdd(
                Surf.SurfNameRef("acc"),
                Surf.SurfExprCastTo(Surf.SurfTI32, Surf.SurfNameRef("i"))
            )),
        }
    )
)
assert(over_stmt ~= nil)

print("moonlift surface->elab loop lowering ok")
