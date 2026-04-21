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

assert(lowered == Elab.ElabModule({
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
                Elab.ElabBindingExpr(Elab.ElabLocalStoredValue("func.main.stmt.1", "y", Elab.ElabTI32)),
                Elab.ElabBindingExpr(Elab.ElabGlobal("", "K", Elab.ElabTI32))
            )),
        }
    )),
}))

print("moonlift surface->elab top lowering ok")
