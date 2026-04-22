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
    Elab.ElabValueEntry("n", Elab.ElabLocalValue("env.n", "n", Elab.ElabTI32)),
    Elab.ElabValueEntry("p", Elab.ElabLocalValue("env.p", "p", Elab.ElabTPtr(Elab.ElabTI32))),
}, {}, {})

local function one_loop_expr(node, path)
    return pvm.one(L.lower_loop_expr(node, env, path))
end

local function one_loop_stmt(node, path)
    return pvm.one(L.lower_loop_stmt(node, env, path))
end

local function one_stmt(node, path)
    return pvm.one(L.lower_stmt(node, env, path))
end

local while_expr = one_loop_expr(
    Surf.SurfLoopWhileExpr(
        {
            Surf.SurfLoopCarryInit("i", Surf.SurfTI32, Surf.SurfInt("0")),
            Surf.SurfLoopCarryInit("acc", Surf.SurfTI32, Surf.SurfInt("0")),
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
    ),
    "loop.sum"
)
assert(while_expr == Elab.ElabLoopExprNode(
    Elab.ElabLoopWhileExpr(
        "loop.sum",
        {
            Elab.ElabLoopCarryPort("loop.sum.carries.carry.1", "i", Elab.ElabTI32, Elab.ElabInt("0", Elab.ElabTI32)),
            Elab.ElabLoopCarryPort("loop.sum.carries.carry.2", "acc", Elab.ElabTI32, Elab.ElabInt("0", Elab.ElabTI32)),
        },
        Elab.ElabExprLt(
            Elab.ElabTBool,
            Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.sum", "loop.sum.carries.carry.1", "i", Elab.ElabTI32)),
            Elab.ElabBindingExpr(Elab.ElabLocalValue("env.n", "n", Elab.ElabTI32))
        ),
        {
            Elab.ElabLet(
                "loop.sum.body.stmt.1",
                "xi",
                Elab.ElabTI32,
                Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.sum", "loop.sum.carries.carry.1", "i", Elab.ElabTI32))
            ),
        },
        {
            Elab.ElabLoopUpdate(
                "loop.sum.carries.carry.1",
                Elab.ElabExprAdd(
                    Elab.ElabTI32,
                    Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.sum", "loop.sum.carries.carry.1", "i", Elab.ElabTI32)),
                    Elab.ElabInt("1", Elab.ElabTI32)
                )
            ),
            Elab.ElabLoopUpdate(
                "loop.sum.carries.carry.2",
                Elab.ElabExprAdd(
                    Elab.ElabTI32,
                    Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.sum", "loop.sum.carries.carry.2", "acc", Elab.ElabTI32)),
                    Elab.ElabBindingExpr(Elab.ElabLocalValue("loop.sum.body.stmt.1", "xi", Elab.ElabTI32))
                )
            ),
        },
        Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.sum", "loop.sum.carries.carry.2", "acc", Elab.ElabTI32))
    ),
    Elab.ElabTI32
))

local set_stmt = one_stmt(
    Surf.SurfSet(
        Surf.SurfPlaceDeref(Surf.SurfNameRef("p")),
        Surf.SurfInt("9")
    ),
    "stmt.set"
)
assert(set_stmt == Elab.ElabSet(
    Elab.ElabPlaceDeref(
        Elab.ElabBindingExpr(Elab.ElabLocalValue("env.p", "p", Elab.ElabTPtr(Elab.ElabTI32))),
        Elab.ElabTI32
    ),
    Elab.ElabInt("9", Elab.ElabTI32)
))

local break_loop = one_loop_stmt(
    Surf.SurfLoopWhileStmt(
        { Surf.SurfLoopCarryInit("i", Surf.SurfTI32, Surf.SurfInt("0")) },
        Surf.SurfBool(true),
        { Surf.SurfBreak },
        { Surf.SurfLoopNextAssign("i", Surf.SurfExprAdd(Surf.SurfNameRef("i"), Surf.SurfInt("1"))) }
    ),
    "loop.break"
)
assert(break_loop == Elab.ElabLoopWhileStmt(
    "loop.break",
    {
        Elab.ElabLoopCarryPort("loop.break.carries.carry.1", "i", Elab.ElabTI32, Elab.ElabInt("0", Elab.ElabTI32)),
    },
    Elab.ElabBool(true, Elab.ElabTBool),
    { Elab.ElabBreak },
    {
        Elab.ElabLoopUpdate(
            "loop.break.carries.carry.1",
            Elab.ElabExprAdd(
                Elab.ElabTI32,
                Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.break", "loop.break.carries.carry.1", "i", Elab.ElabTI32)),
                Elab.ElabInt("1", Elab.ElabTI32)
            )
        ),
    }
))

local continue_loop = one_loop_stmt(
    Surf.SurfLoopWhileStmt(
        { Surf.SurfLoopCarryInit("i", Surf.SurfTI32, Surf.SurfInt("0")) },
        Surf.SurfBool(true),
        { Surf.SurfContinue },
        { Surf.SurfLoopNextAssign("i", Surf.SurfExprAdd(Surf.SurfNameRef("i"), Surf.SurfInt("1"))) }
    ),
    "loop.continue"
)
assert(continue_loop == Elab.ElabLoopWhileStmt(
    "loop.continue",
    {
        Elab.ElabLoopCarryPort("loop.continue.carries.carry.1", "i", Elab.ElabTI32, Elab.ElabInt("0", Elab.ElabTI32)),
    },
    Elab.ElabBool(true, Elab.ElabTBool),
    { Elab.ElabContinue },
    {
        Elab.ElabLoopUpdate(
            "loop.continue.carries.carry.1",
            Elab.ElabExprAdd(
                Elab.ElabTI32,
                Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.continue", "loop.continue.carries.carry.1", "i", Elab.ElabTI32)),
                Elab.ElabInt("1", Elab.ElabTI32)
            )
        ),
    }
))

local break_value_loop = one_loop_expr(
    Surf.SurfLoopWhileExpr(
        { Surf.SurfLoopCarryInit("i", Surf.SurfTI32, Surf.SurfInt("0")) },
        Surf.SurfBool(true),
        { Surf.SurfBreakValue(Surf.SurfInt("7")) },
        { Surf.SurfLoopNextAssign("i", Surf.SurfExprAdd(Surf.SurfNameRef("i"), Surf.SurfInt("1"))) },
        Surf.SurfNameRef("i")
    ),
    "loop.break_value"
)
assert(break_value_loop == Elab.ElabLoopExprNode(
    Elab.ElabLoopWhileExpr(
        "loop.break_value",
        {
            Elab.ElabLoopCarryPort("loop.break_value.carries.carry.1", "i", Elab.ElabTI32, Elab.ElabInt("0", Elab.ElabTI32)),
        },
        Elab.ElabBool(true, Elab.ElabTBool),
        {
            Elab.ElabBreakValue(Elab.ElabInt("7", Elab.ElabTI32)),
        },
        {
            Elab.ElabLoopUpdate(
                "loop.break_value.carries.carry.1",
                Elab.ElabExprAdd(
                    Elab.ElabTI32,
                    Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.break_value", "loop.break_value.carries.carry.1", "i", Elab.ElabTI32)),
                    Elab.ElabInt("1", Elab.ElabTI32)
                )
            ),
        },
        Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.break_value", "loop.break_value.carries.carry.1", "i", Elab.ElabTI32))
    ),
    Elab.ElabTI32
))

local over_stmt = one_loop_stmt(
    Surf.SurfLoopOverStmt(
        "i",
        Surf.SurfDomainRange(Surf.SurfNameRef("n")),
        {
            Surf.SurfLoopCarryInit("acc", Surf.SurfTI32, Surf.SurfInt("0")),
        },
        {},
        {
            Surf.SurfLoopNextAssign("acc", Surf.SurfExprAdd(
                Surf.SurfNameRef("acc"),
                Surf.SurfExprCastTo(Surf.SurfTI32, Surf.SurfNameRef("i"))
            )),
        }
    ),
    "loop.over"
)
assert(over_stmt == Elab.ElabLoopOverStmt(
    "loop.over",
    Elab.ElabLoopIndexPort("i", Elab.ElabTIndex),
    Elab.ElabDomainRange(
        Elab.ElabBindingExpr(Elab.ElabLocalValue("env.n", "n", Elab.ElabTI32))
    ),
    {
        Elab.ElabLoopCarryPort("loop.over.carries.carry.1", "acc", Elab.ElabTI32, Elab.ElabInt("0", Elab.ElabTI32)),
    },
    {},
    {
        Elab.ElabLoopUpdate(
            "loop.over.carries.carry.1",
            Elab.ElabExprAdd(
                Elab.ElabTI32,
                Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.over", "loop.over.carries.carry.1", "acc", Elab.ElabTI32)),
                Elab.ElabExprCastTo(
                    Elab.ElabTI32,
                    Elab.ElabBindingExpr(Elab.ElabLoopIndex("loop.over", "i", Elab.ElabTIndex))
                )
            )
        ),
    }
))

print("moonlift surface->elab loop lowering ok")
