package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("pvm")
local A = require("moonlift.asdl")
local J = require("moonlift.jit")

local T = pvm.context()
A.Define(T)

local Back = T.MoonliftBack
local api = J.Define(T)
local jit = api.jit()

local program = Back.BackProgram({
    Back.BackCmdCreateSig(Back.BackSigId("sig:add1"), { Back.BackI32 }, { Back.BackI32 }),
    Back.BackCmdDeclareFuncExport(Back.BackFuncId("add1"), Back.BackSigId("sig:add1")),
    Back.BackCmdBeginFunc(Back.BackFuncId("add1")),
    Back.BackCmdCreateBlock(Back.BackBlockId("entry")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("entry")),
    Back.BackCmdBindEntryParams(Back.BackBlockId("entry"), { Back.BackValId("arg") }),
    Back.BackCmdConstInt(Back.BackValId("one"), Back.BackI32, "1"),
    Back.BackCmdIadd(Back.BackValId("sum"), Back.BackI32, Back.BackValId("arg"), Back.BackValId("one")),
    Back.BackCmdReturnValue(Back.BackValId("sum")),
    Back.BackCmdSealBlock(Back.BackBlockId("entry")),
    Back.BackCmdFinishFunc(Back.BackFuncId("add1")),
    Back.BackCmdFinalizeModule,
})

local artifact = jit:compile(program)
local ptr = artifact:getpointer(Back.BackFuncId("add1"))
local f = ffi.cast("int32_t (*)(int32_t)", ptr)
assert(f(41) == 42)
artifact:free()

local data_program = Back.BackProgram({
    Back.BackCmdDeclareData(Back.BackDataId("const:k"), 4, 4),
    Back.BackCmdDataInitInt(Back.BackDataId("const:k"), 0, Back.BackI32, "42"),
    Back.BackCmdCreateSig(Back.BackSigId("sig:getk"), {}, { Back.BackI32 }),
    Back.BackCmdDeclareFuncExport(Back.BackFuncId("getk"), Back.BackSigId("sig:getk")),
    Back.BackCmdBeginFunc(Back.BackFuncId("getk")),
    Back.BackCmdCreateBlock(Back.BackBlockId("entry")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("entry")),
    Back.BackCmdDataAddr(Back.BackValId("addr"), Back.BackDataId("const:k")),
    Back.BackCmdLoad(Back.BackValId("value"), Back.BackI32, Back.BackValId("addr")),
    Back.BackCmdReturnValue(Back.BackValId("value")),
    Back.BackCmdSealBlock(Back.BackBlockId("entry")),
    Back.BackCmdFinishFunc(Back.BackFuncId("getk")),
    Back.BackCmdFinalizeModule,
})

local data_artifact = jit:compile(data_program)
local data_ptr = data_artifact:getpointer(Back.BackFuncId("getk"))
local getk = ffi.cast("int32_t (*)()", data_ptr)
assert(getk() == 42)
data_artifact:free()
jit:free()

print("moonlift rust ffi ok")
