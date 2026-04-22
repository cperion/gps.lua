package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Lower = require("moonlift.lower_surface_to_elab_top")

local T = pvm.context()
A.Define(T)
local L = Lower.Define(T)

local Surf = T.MoonliftSurface
local Elab = T.MoonliftElab

local module_node = Surf.SurfModule({
    Surf.SurfItemExtern(Surf.SurfExternFunc(
        "ext",
        "ext",
        { Surf.SurfParam("x", Surf.SurfTI32) },
        Surf.SurfTI32
    )),
    Surf.SurfItemConst(Surf.SurfConst(
        "K",
        Surf.SurfTI32,
        Surf.SurfInt("7")
    )),
    Surf.SurfItemFunc(Surf.SurfFunc(
        "helper",
        { Surf.SurfParam("x", Surf.SurfTI32) },
        Surf.SurfTI32,
        {
            Surf.SurfReturnValue(Surf.SurfCall(
                Surf.SurfNameRef("ext"),
                { Surf.SurfNameRef("x") }
            )),
        }
    )),
    Surf.SurfItemFunc(Surf.SurfFunc(
        "main",
        { Surf.SurfParam("x", Surf.SurfTI32) },
        Surf.SurfTI32,
        {
            Surf.SurfLet(
                "y",
                Surf.SurfTI32,
                Surf.SurfCall(
                    Surf.SurfNameRef("helper"),
                    { Surf.SurfNameRef("x") }
                )
            ),
            Surf.SurfReturnValue(Surf.SurfExprAdd(
                Surf.SurfNameRef("y"),
                Surf.SurfNameRef("K")
            )),
        }
    )),
})

local lowered = pvm.one(L.lower_module(module_node))

assert(lowered == Elab.ElabModule("", {
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
}))

local count_module = Surf.SurfModule({
    Surf.SurfItemConst(Surf.SurfConst(
        "N",
        Surf.SurfTIndex,
        Surf.SurfInt("4")
    )),
    Surf.SurfItemConst(Surf.SurfConst(
        "M",
        Surf.SurfTIndex,
        Surf.SurfExprAdd(Surf.SurfNameRef("N"), Surf.SurfInt("2"))
    )),
    Surf.SurfItemFunc(Surf.SurfFunc(
        "use_count",
        { Surf.SurfParam("xs", Surf.SurfTArray(Surf.SurfNameRef("M"), Surf.SurfTI32)) },
        Surf.SurfTVoid,
        { Surf.SurfReturnVoid }
    )),
})

assert(pvm.one(L.lower_module(count_module)) == Elab.ElabModule("", {
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
}))

local type_module = Surf.SurfModule({
    Surf.SurfItemType(Surf.SurfStruct("Pair", {
        Surf.SurfFieldDecl("left", Surf.SurfTI32),
        Surf.SurfFieldDecl("right", Surf.SurfTI32),
    })),
    Surf.SurfItemFunc(Surf.SurfFunc(
        "get_left",
        {},
        Surf.SurfTI32,
        {
            Surf.SurfReturnValue(Surf.SurfExprDot(
                Surf.SurfAgg(
                    Surf.SurfTNamed(Surf.SurfPath({ Surf.SurfName("Pair") })),
                    {
                        Surf.SurfFieldInit("left", Surf.SurfInt("1")),
                        Surf.SurfFieldInit("right", Surf.SurfInt("2")),
                    }
                ),
                "left"
            )),
        }
    )),
})

assert(pvm.one(L.lower_module(type_module)) == Elab.ElabModule("", {
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
}))

local import_module = Surf.SurfModule({
    Surf.SurfItemImport(Surf.SurfImport(Surf.SurfPath({ Surf.SurfName("Demo") }))),
    Surf.SurfItemFunc(Surf.SurfFunc(
        "main",
        {},
        Surf.SurfTVoid,
        { Surf.SurfReturnVoid }
    )),
})

assert(pvm.one(L.lower_module(import_module)) == Elab.ElabModule("", {
    Elab.ElabItemImport(Elab.ElabImport("Demo")),
    Elab.ElabItemFunc(Elab.ElabFunc("main", {}, Elab.ElabTVoid, { Elab.ElabReturnVoid })),
}))

print("moonlift surface->elab top lowering ok")
