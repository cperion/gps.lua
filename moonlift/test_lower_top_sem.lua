package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Lower = require("moonlift.lower_elab_to_sem")

local T = pvm.context()
A.Define(T)
local L = Lower.Define(T)

local Elab = T.MoonliftElab
local Sem = T.MoonliftSem

local module_node = Elab.ElabModule("", {
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
                    Elab.ElabBindingExpr(Elab.ElabGlobalFunc("", "helper", Elab.ElabTFunc({ Elab.ElabTI32 }, Elab.ElabTI32))),
                    Elab.ElabTI32,
                    { Elab.ElabBindingExpr(Elab.ElabArg(0, "x", Elab.ElabTI32)) }
                )
            ),
            Elab.ElabReturnValue(Elab.ElabExprAdd(
                Elab.ElabTI32,
                Elab.ElabBindingExpr(Elab.ElabLocalValue("func.main.stmt.1", "y", Elab.ElabTI32)),
                Elab.ElabBindingExpr(Elab.ElabGlobalConst("", "K", Elab.ElabTI32))
            )),
        }
    )),
})

local lowered = pvm.one(L.lower_module(module_node))

assert(lowered == Sem.SemModule("", {
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
                Sem.SemExprBinding(Sem.SemBindGlobalConst("", "K", Sem.SemTI32))
            )),
        }
    )),
}))

local count_module = Elab.ElabModule("", {
    Elab.ElabItemConst(Elab.ElabConst(
        "N",
        Elab.ElabTIndex,
        Elab.ElabInt("4", Elab.ElabTIndex)
    )),
    Elab.ElabItemConst(Elab.ElabConst(
        "M",
        Elab.ElabTIndex,
        Elab.ElabExprAdd(
            Elab.ElabTIndex,
            Elab.ElabBindingExpr(Elab.ElabGlobalConst("", "N", Elab.ElabTIndex)),
            Elab.ElabInt("2", Elab.ElabTIndex)
        )
    )),
    Elab.ElabItemFunc(Elab.ElabFunc(
        "use_count",
        { Elab.ElabParam("xs", Elab.ElabTArray(Elab.ElabBindingExpr(Elab.ElabGlobalConst("", "M", Elab.ElabTIndex)), Elab.ElabTI32)) },
        Elab.ElabTVoid,
        { Elab.ElabReturnVoid }
    )),
})

assert(pvm.one(L.lower_module(count_module)) == Sem.SemModule("", {
    Sem.SemItemConst(Sem.SemConst(
        "N",
        Sem.SemTIndex,
        Sem.SemExprConstInt(Sem.SemTIndex, "4")
    )),
    Sem.SemItemConst(Sem.SemConst(
        "M",
        Sem.SemTIndex,
        Sem.SemExprAdd(
            Sem.SemTIndex,
            Sem.SemExprBinding(Sem.SemBindGlobalConst("", "N", Sem.SemTIndex)),
            Sem.SemExprConstInt(Sem.SemTIndex, "2")
        )
    )),
    Sem.SemItemFunc(Sem.SemFuncExport(
        "use_count",
        { Sem.SemParam("xs", Sem.SemTArray(Sem.SemTI32, 6)) },
        Sem.SemTVoid,
        { Sem.SemStmtReturnVoid }
    )),
}))

local type_module = Elab.ElabModule("", {
    Elab.ElabItemType(Elab.ElabStruct("Pair", {
        Elab.ElabFieldType("left", Elab.ElabTI32),
        Elab.ElabFieldType("right", Elab.ElabTI32),
    })),
    Elab.ElabItemFunc(Elab.ElabFunc(
        "get_left",
        {},
        Elab.ElabTI32,
        {
            Elab.ElabReturnValue(Elab.ElabField(
                Elab.ElabAgg(
                    Elab.ElabTNamed("", "Pair"),
                    {
                        Elab.ElabFieldInit("left", Elab.ElabInt("1", Elab.ElabTI32)),
                        Elab.ElabFieldInit("right", Elab.ElabInt("2", Elab.ElabTI32)),
                    }
                ),
                "left",
                Elab.ElabTI32
            )),
        }
    )),
})

assert(pvm.one(L.lower_module(type_module)) == Sem.SemModule("", {
    Sem.SemItemType(Sem.SemStruct("Pair", {
        Sem.SemFieldType("left", Sem.SemTI32),
        Sem.SemFieldType("right", Sem.SemTI32),
    })),
    Sem.SemItemFunc(Sem.SemFuncExport(
        "get_left",
        {},
        Sem.SemTI32,
        {
            Sem.SemStmtReturnValue(Sem.SemExprField(
                Sem.SemExprAgg(
                    Sem.SemTNamed("", "Pair"),
                    {
                        Sem.SemFieldInit("left", Sem.SemExprConstInt(Sem.SemTI32, "1")),
                        Sem.SemFieldInit("right", Sem.SemExprConstInt(Sem.SemTI32, "2")),
                    }
                ),
                Sem.SemFieldByName("left", Sem.SemTI32)
            )),
        }
    )),
}))

local import_module = Elab.ElabModule("", {
    Elab.ElabItemImport(Elab.ElabImport("Demo")),
    Elab.ElabItemFunc(Elab.ElabFunc("main", {}, Elab.ElabTVoid, { Elab.ElabReturnVoid })),
})

assert(pvm.one(L.lower_module(import_module)) == Sem.SemModule("", {
    Sem.SemItemImport(Sem.SemImport("Demo")),
    Sem.SemItemFunc(Sem.SemFuncExport("main", {}, Sem.SemTVoid, { Sem.SemStmtReturnVoid })),
}))

local select_module = Elab.ElabModule("", {
    Elab.ElabItemFunc(Elab.ElabFunc(
        "choose",
        {
            Elab.ElabParam("flag", Elab.ElabTBool),
            Elab.ElabParam("x", Elab.ElabTI32),
            Elab.ElabParam("y", Elab.ElabTI32),
        },
        Elab.ElabTI32,
        {
            Elab.ElabReturnValue(Elab.ElabSelectExpr(
                Elab.ElabBindingExpr(Elab.ElabArg(0, "flag", Elab.ElabTBool)),
                Elab.ElabBindingExpr(Elab.ElabArg(1, "x", Elab.ElabTI32)),
                Elab.ElabBindingExpr(Elab.ElabArg(2, "y", Elab.ElabTI32)),
                Elab.ElabTI32
            )),
        }
    )),
})

assert(pvm.one(L.lower_module(select_module)) == Sem.SemModule("", {
    Sem.SemItemFunc(Sem.SemFuncExport(
        "choose",
        {
            Sem.SemParam("flag", Sem.SemTBool),
            Sem.SemParam("x", Sem.SemTI32),
            Sem.SemParam("y", Sem.SemTI32),
        },
        Sem.SemTI32,
        {
            Sem.SemStmtReturnValue(Sem.SemExprSelect(
                Sem.SemExprBinding(Sem.SemBindArg(0, "flag", Sem.SemTBool)),
                Sem.SemExprBinding(Sem.SemBindArg(1, "x", Sem.SemTI32)),
                Sem.SemExprBinding(Sem.SemBindArg(2, "y", Sem.SemTI32)),
                Sem.SemTI32
            )),
        }
    )),
}))

print("moonlift elab->sem top lowering ok")
