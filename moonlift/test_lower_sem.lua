package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Lower = require("moonlift.lower_elab_to_sem")

local T = pvm.context()
A.Define(T)
local L = Lower.Define(T)

local Elab = T.MoonliftElab
local Sem = T.MoonliftSem

local function one_type(node)
    return pvm.one(L.lower_type(node))
end

local function one_expr(node)
    return pvm.one(L.lower_expr(node))
end

local function one_domain(node)
    return pvm.one(L.lower_domain(node))
end

local function one_stmt(node)
    return pvm.one(L.lower_stmt(node))
end

assert(one_type(Elab.ElabTI32) == Sem.SemTI32)
assert(one_type(Elab.ElabTPtr(Elab.ElabTI32)) == Sem.SemTPtrTo(Sem.SemTI32))
assert(one_type(Elab.ElabTArray(Elab.ElabInt("4", Elab.ElabTI32), Elab.ElabTI32)) == Sem.SemTArray(Sem.SemTI32, 4))
assert(one_type(Elab.ElabTArray(
    Elab.ElabExprAdd(
        Elab.ElabTIndex,
        Elab.ElabInt("2", Elab.ElabTIndex),
        Elab.ElabExprMul(
            Elab.ElabTIndex,
            Elab.ElabInt("3", Elab.ElabTIndex),
            Elab.ElabInt("4", Elab.ElabTIndex)
        )
    ),
    Elab.ElabTI32
)) == Sem.SemTArray(Sem.SemTI32, 14))

local x = Elab.ElabBindingExpr(Elab.ElabLocalValue("lx", "x", Elab.ElabTI32))
local add = one_expr(Elab.ElabExprAdd(Elab.ElabTI32, x, Elab.ElabInt("1", Elab.ElabTI32)))
assert(add == Sem.SemExprAdd(
    Sem.SemTI32,
    Sem.SemExprBinding(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32)),
    Sem.SemExprConstInt(Sem.SemTI32, "1")
))

local ref_expr = one_expr(Elab.ElabExprRef(
    Elab.ElabTPtr(Elab.ElabTI32),
    Elab.ElabBindingExpr(Elab.ElabLocalValue("lx", "x", Elab.ElabTI32))
))
assert(ref_expr == Sem.SemExprRef(
    Sem.SemTPtrTo(Sem.SemTI32),
    Sem.SemExprBinding(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32))
))

local deref_expr = one_expr(Elab.ElabExprDeref(
    Elab.ElabTI32,
    Elab.ElabBindingExpr(Elab.ElabLocalValue("lp", "p", Elab.ElabTPtr(Elab.ElabTI32)))
))
assert(deref_expr == Sem.SemExprDeref(
    Sem.SemTI32,
    Sem.SemExprBinding(Sem.SemBindLocalValue("lp", "p", Sem.SemTPtrTo(Sem.SemTI32)))
))

local direct_call = one_expr(Elab.ElabCall(
    Elab.ElabBindingExpr(Elab.ElabGlobal("", "sum", Elab.ElabTFunc({ Elab.ElabTI32 }, Elab.ElabTI32))),
    Elab.ElabTI32,
    { Elab.ElabInt("7", Elab.ElabTI32) }
))
assert(direct_call == Sem.SemExprCall(
    Sem.SemCallDirect("", "sum", Sem.SemTFunc({ Sem.SemTI32 }, Sem.SemTI32)),
    Sem.SemTI32,
    { Sem.SemExprConstInt(Sem.SemTI32, "7") }
))

local d = one_domain(Elab.ElabDomainRange(Elab.ElabBindingExpr(Elab.ElabArg(0, "n", Elab.ElabTI32))))
assert(d == Sem.SemDomainRange(
    Sem.SemExprCastTo(Sem.SemTIndex, Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTI32)))
))

local set_stmt = one_stmt(Elab.ElabSet(
    Elab.ElabLocalCell("cx", "x", Elab.ElabTI32),
    Elab.ElabExprAdd(Elab.ElabTI32, x, Elab.ElabInt("2", Elab.ElabTI32))
))
assert(set_stmt == Sem.SemStmtSet(
    Sem.SemBindLocalCell("cx", "x", Sem.SemTI32),
    Sem.SemExprAdd(
        Sem.SemTI32,
        Sem.SemExprBinding(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32)),
        Sem.SemExprConstInt(Sem.SemTI32, "2")
    )
))

local store_stmt = one_stmt(Elab.ElabStore(
    Elab.ElabTI32,
    Elab.ElabBindingExpr(Elab.ElabLocalValue("lp", "p", Elab.ElabTPtr(Elab.ElabTI32))),
    Elab.ElabInt("9", Elab.ElabTI32)
))
assert(store_stmt == Sem.SemStmtStore(
    Sem.SemTI32,
    Sem.SemExprBinding(Sem.SemBindLocalValue("lp", "p", Sem.SemTPtrTo(Sem.SemTI32))),
    Sem.SemExprConstInt(Sem.SemTI32, "9")
))

assert(one_stmt(Elab.ElabBreak) == Sem.SemStmtBreak)
assert(one_stmt(Elab.ElabContinue) == Sem.SemStmtContinue)

local field_expr = one_expr(Elab.ElabField(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("lp", "p", Elab.ElabTNamed("Demo", "Pair"))),
    "left",
    Elab.ElabTI32
))
assert(field_expr == Sem.SemExprField(
    Sem.SemExprBinding(Sem.SemBindLocalValue("lp", "p", Sem.SemTNamed("Demo", "Pair"))),
    Sem.SemFieldByName("left", Sem.SemTI32)
))

local switch_stmt = one_stmt(Elab.ElabSwitch(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("lx", "x", Elab.ElabTI32)),
    {
        Elab.ElabSwitchStmtArm(
            Elab.ElabInt("1", Elab.ElabTI32),
            { Elab.ElabExprStmt(Elab.ElabInt("11", Elab.ElabTI32)) }
        ),
    },
    { Elab.ElabExprStmt(Elab.ElabInt("22", Elab.ElabTI32)) }
))
assert(switch_stmt == Sem.SemStmtSwitch(
    Sem.SemExprBinding(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32)),
    {
        Sem.SemSwitchStmtArm(
            Sem.SemExprConstInt(Sem.SemTI32, "1"),
            { Sem.SemStmtExpr(Sem.SemExprConstInt(Sem.SemTI32, "11")) }
        ),
    },
    { Sem.SemStmtExpr(Sem.SemExprConstInt(Sem.SemTI32, "22")) }
))

local switch_expr = one_expr(Elab.ElabSwitchExpr(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("lx", "x", Elab.ElabTI32)),
    {
        Elab.ElabSwitchExprArm(
            Elab.ElabInt("1", Elab.ElabTI32),
            { Elab.ElabExprStmt(Elab.ElabBindingExpr(Elab.ElabLocalValue("lx", "x", Elab.ElabTI32))) },
            Elab.ElabInt("11", Elab.ElabTI32)
        ),
    },
    Elab.ElabInt("22", Elab.ElabTI32),
    Elab.ElabTI32
))
assert(switch_expr == Sem.SemExprSwitch(
    Sem.SemExprBinding(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32)),
    {
        Sem.SemSwitchExprArm(
            Sem.SemExprConstInt(Sem.SemTI32, "1"),
            { Sem.SemStmtExpr(Sem.SemExprBinding(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32))) },
            Sem.SemExprConstInt(Sem.SemTI32, "11")
        ),
    },
    Sem.SemExprConstInt(Sem.SemTI32, "22"),
    Sem.SemTI32
))

local loop_expr = one_expr(Elab.ElabLoopExprNode(
    Elab.ElabLoopWhileExpr(
        {
            Elab.ElabLoopBinding("loop.i", "i", Elab.ElabTI32, Elab.ElabInt("0", Elab.ElabTI32)),
            Elab.ElabLoopBinding("loop.acc", "acc", Elab.ElabTI32, Elab.ElabInt("0", Elab.ElabTI32)),
        },
        Elab.ElabExprLt(
            Elab.ElabTBool,
            Elab.ElabBindingExpr(Elab.ElabLocalStoredValue("loop.i", "i", Elab.ElabTI32)),
            Elab.ElabBindingExpr(Elab.ElabArg(0, "n", Elab.ElabTI32))
        ),
        {
            Elab.ElabExprStmt(Elab.ElabBindingExpr(Elab.ElabLocalStoredValue("loop.acc", "acc", Elab.ElabTI32))),
        },
        {
            Elab.ElabLoopNext(
                Elab.ElabLocalStoredValue("loop.i", "i", Elab.ElabTI32),
                Elab.ElabExprAdd(
                    Elab.ElabTI32,
                    Elab.ElabBindingExpr(Elab.ElabLocalStoredValue("loop.i", "i", Elab.ElabTI32)),
                    Elab.ElabInt("1", Elab.ElabTI32)
                )
            ),
            Elab.ElabLoopNext(
                Elab.ElabLocalStoredValue("loop.acc", "acc", Elab.ElabTI32),
                Elab.ElabExprAdd(
                    Elab.ElabTI32,
                    Elab.ElabBindingExpr(Elab.ElabLocalStoredValue("loop.acc", "acc", Elab.ElabTI32)),
                    Elab.ElabBindingExpr(Elab.ElabLocalStoredValue("loop.i", "i", Elab.ElabTI32))
                )
            ),
        },
        Elab.ElabBindingExpr(Elab.ElabLocalStoredValue("loop.acc", "acc", Elab.ElabTI32))
    ),
    Elab.ElabTI32
))
assert(loop_expr == Sem.SemExprLoop(
    Sem.SemLoopWhileExpr(
        {
            Sem.SemLoopBinding("loop.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
            Sem.SemLoopBinding("loop.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
        },
        Sem.SemExprLt(
            Sem.SemTBool,
            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop.i", "i", Sem.SemTI32)),
            Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTI32))
        ),
        {
            Sem.SemStmtExpr(Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop.acc", "acc", Sem.SemTI32))),
        },
        {
            Sem.SemLoopNext(
                Sem.SemBindLocalStoredValue("loop.i", "i", Sem.SemTI32),
                Sem.SemExprAdd(
                    Sem.SemTI32,
                    Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop.i", "i", Sem.SemTI32)),
                    Sem.SemExprConstInt(Sem.SemTI32, "1")
                )
            ),
            Sem.SemLoopNext(
                Sem.SemBindLocalStoredValue("loop.acc", "acc", Sem.SemTI32),
                Sem.SemExprAdd(
                    Sem.SemTI32,
                    Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop.acc", "acc", Sem.SemTI32)),
                    Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop.i", "i", Sem.SemTI32))
                )
            ),
        },
        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop.acc", "acc", Sem.SemTI32))
    ),
    Sem.SemTI32
))

print("moonlift elab->sem lowering ok")
