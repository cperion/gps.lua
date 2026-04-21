package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Lower = require("moonlift.lower_elab_to_sem")

local T = pvm.context()
A.Define(T)
local L = Lower.Define(T)

local Elab = T.MoonliftElab
local Sem = T.MoonliftSem

local module_node = Elab.ElabModule({
    Elab.ElabItemExtern(Elab.ElabExternFunc(
        "ext",
        "ext",
        { Elab.ElabParam("x", Elab.ElabTI32) },
        Elab.ElabTI32
    )),
    Elab.ElabItemConst(Elab.ElabConst(
        "K",
        Elab.ElabTI32,
        Elab.ElabInt("7", Elab.ElabTI32)
    )),
    Elab.ElabItemFunc(Elab.ElabFunc(
        "helper",
        { Elab.ElabParam("x", Elab.ElabTI32) },
        Elab.ElabTI32,
        {
            Elab.ElabReturnValue(Elab.ElabCall(
                Elab.ElabBindingExpr(Elab.ElabExtern("ext", Elab.ElabTFunc({ Elab.ElabTI32 }, Elab.ElabTI32))),
                Elab.ElabTI32,
                { Elab.ElabBindingExpr(Elab.ElabArg(0, "x", Elab.ElabTI32)) }
            )),
        }
    )),
    Elab.ElabItemFunc(Elab.ElabFunc(
        "main",
        { Elab.ElabParam("x", Elab.ElabTI32) },
        Elab.ElabTI32,
        {
            Elab.ElabLet(
                "func.main.stmt.1",
                "y",
                Elab.ElabTI32,
                Elab.ElabCall(
                    Elab.ElabBindingExpr(Elab.ElabGlobal("", "helper", Elab.ElabTFunc({ Elab.ElabTI32 }, Elab.ElabTI32))),
                    Elab.ElabTI32,
                    { Elab.ElabBindingExpr(Elab.ElabArg(0, "x", Elab.ElabTI32)) }
                )
            ),
            Elab.ElabReturnValue(Elab.ElabExprAdd(
                Elab.ElabTI32,
                Elab.ElabBindingExpr(Elab.ElabLocalValue("func.main.stmt.1", "y", Elab.ElabTI32)),
                Elab.ElabBindingExpr(Elab.ElabGlobal("", "K", Elab.ElabTI32))
            )),
        }
    )),
})

local lowered = pvm.one(L.lower_module(module_node))

assert(lowered == Sem.SemModule({
    Sem.SemItemExtern(Sem.SemExternFunc(
        "ext",
        "ext",
        { Sem.SemParam("x", Sem.SemTI32) },
        Sem.SemTI32
    )),
    Sem.SemItemConst(Sem.SemConst(
        "K",
        Sem.SemTI32,
        Sem.SemExprConstInt(Sem.SemTI32, "7")
    )),
    Sem.SemItemFunc(Sem.SemFuncExport(
        "helper",
        { Sem.SemParam("x", Sem.SemTI32) },
        Sem.SemTI32,
        {
            Sem.SemStmtReturnValue(Sem.SemExprCall(
                Sem.SemCallExtern("ext", Sem.SemTFunc({ Sem.SemTI32 }, Sem.SemTI32)),
                Sem.SemTI32,
                { Sem.SemExprBinding(Sem.SemBindArg(0, "x", Sem.SemTI32)) }
            )),
        }
    )),
    Sem.SemItemFunc(Sem.SemFuncExport(
        "main",
        { Sem.SemParam("x", Sem.SemTI32) },
        Sem.SemTI32,
        {
            Sem.SemStmtLet(
                "func.main.stmt.1",
                "y",
                Sem.SemTI32,
                Sem.SemExprCall(
                    Sem.SemCallDirect("", "helper", Sem.SemTFunc({ Sem.SemTI32 }, Sem.SemTI32)),
                    Sem.SemTI32,
                    { Sem.SemExprBinding(Sem.SemBindArg(0, "x", Sem.SemTI32)) }
                )
            ),
            Sem.SemStmtReturnValue(Sem.SemExprAdd(
                Sem.SemTI32,
                Sem.SemExprBinding(Sem.SemBindLocalValue("func.main.stmt.1", "y", Sem.SemTI32)),
                Sem.SemExprBinding(Sem.SemBindGlobal("", "K", Sem.SemTI32))
            )),
        }
    )),
}))

print("moonlift elab->sem top lowering ok")
