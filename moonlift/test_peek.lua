package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Peek = require("moonlift.peek")

local T = pvm.context()
A.Define(T)

local Surf = T.MoonliftSurface
local peek = Peek.Define(T)

local module_node = Surf.SurfModule({
    Surf.SurfItemFunc(Surf.SurfFunc("add1", { Surf.SurfParam("x", Surf.SurfTI32) }, Surf.SurfTI32, {
        Surf.SurfReturnValue(Surf.SurfExprAdd(Surf.SurfNameRef("x"), Surf.SurfInt("1"))),
    })),
})

local result = peek.disasm_surface_module(module_node, "add1", { bytes = 96 })
assert(result.back ~= nil)
assert(result.compile_error == nil)
assert(type(result:require_disasm()) == "string")
local back_text = result:format_back()
assert(back_text:find("BackCmdIadd", 1, true) ~= nil)
assert(result:require_disasm():find("ret", 1, true) ~= nil)
result:free()

print("moonlift peek ok")
