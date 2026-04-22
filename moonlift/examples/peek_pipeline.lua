package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Peek = require("moonlift.peek")

local T = pvm.context()
A.Define(T)

local Surf = T.MoonliftSurface
local peek = Peek.Define(T)

local shapes = {
    add1 = {
        func = "add1",
        module = Surf.SurfModule({
            Surf.SurfItemFunc(Surf.SurfFunc("add1", { Surf.SurfParam("x", Surf.SurfTI32) }, Surf.SurfTI32, {
                Surf.SurfReturnValue(Surf.SurfExprAdd(Surf.SurfNameRef("x"), Surf.SurfInt("1"))),
            })),
        }),
    },
    ifexpr = {
        func = "pick",
        module = Surf.SurfModule({
            Surf.SurfItemFunc(Surf.SurfFunc("pick", {
                Surf.SurfParam("b", Surf.SurfTBool),
                Surf.SurfParam("x", Surf.SurfTI32),
                Surf.SurfParam("y", Surf.SurfTI32),
            }, Surf.SurfTI32, {
                Surf.SurfReturnValue(Surf.SurfIfExpr(Surf.SurfNameRef("b"), Surf.SurfNameRef("x"), Surf.SurfNameRef("y"))),
            })),
        }),
    },
    switchexpr = {
        func = "pick_case",
        module = Surf.SurfModule({
            Surf.SurfItemFunc(Surf.SurfFunc("pick_case", { Surf.SurfParam("x", Surf.SurfTI32) }, Surf.SurfTI32, {
                Surf.SurfReturnValue(Surf.SurfSwitchExpr(Surf.SurfNameRef("x"), {
                    Surf.SurfSwitchExprArm(Surf.SurfInt("1"), {}, Surf.SurfInt("11")),
                    Surf.SurfSwitchExprArm(Surf.SurfInt("2"), {}, Surf.SurfInt("22")),
                }, Surf.SurfInt("99"))),
            })),
        }),
    },
    sum_range = {
        func = "sum_range",
        module = Surf.SurfModule({
            Surf.SurfItemFunc(Surf.SurfFunc("sum_range", { Surf.SurfParam("n", Surf.SurfTIndex) }, Surf.SurfTIndex, {
                Surf.SurfReturnValue(Surf.SurfLoopExprNode(Surf.SurfLoopOverExpr(
                    "i",
                    Surf.SurfDomainRange(Surf.SurfNameRef("n")),
                    { Surf.SurfLoopVarInit("acc", Surf.SurfTIndex, Surf.SurfInt("0")) },
                    {},
                    { Surf.SurfLoopNextAssign("acc", Surf.SurfExprAdd(Surf.SurfNameRef("acc"), Surf.SurfNameRef("i"))) },
                    Surf.SurfNameRef("acc")
                ))),
            })),
        }),
    },
}

local name = arg[1] or "add1"
local bytes = tonumber(arg[2] or "128")
local shape = assert(shapes[name], "unknown shape '" .. tostring(name) .. "'")

local result = peek.peek_surface_module(shape.module, shape.func, { bytes = bytes })

print("=== shape ===")
print(name)
print()
print("=== back ===")
print(result:format_back())
print()

if result.compile_error ~= nil then
    print("=== compile error ===")
    print(result.compile_error)
elseif result.disasm_error ~= nil then
    print("=== disasm error ===")
    print(result.disasm_error)
else
    print("=== disasm ===")
    print(result.disasm)
end

result:free()
