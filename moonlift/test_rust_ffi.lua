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

local intrinsic_program = Back.BackProgram({
    Back.BackCmdCreateSig(Back.BackSigId("sig:poprot"), { Back.BackU32 }, { Back.BackU32 }),
    Back.BackCmdDeclareFuncExport(Back.BackFuncId("poprot"), Back.BackSigId("sig:poprot")),
    Back.BackCmdBeginFunc(Back.BackFuncId("poprot")),
    Back.BackCmdCreateBlock(Back.BackBlockId("entry.poprot")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("entry.poprot")),
    Back.BackCmdBindEntryParams(Back.BackBlockId("entry.poprot"), { Back.BackValId("x") }),
    Back.BackCmdPopcount(Back.BackValId("pc"), Back.BackU32, Back.BackValId("x")),
    Back.BackCmdConstInt(Back.BackValId("rotamt"), Back.BackU32, "1"),
    Back.BackCmdRotl(Back.BackValId("out"), Back.BackU32, Back.BackValId("pc"), Back.BackValId("rotamt")),
    Back.BackCmdReturnValue(Back.BackValId("out")),
    Back.BackCmdSealBlock(Back.BackBlockId("entry.poprot")),
    Back.BackCmdFinishFunc(Back.BackFuncId("poprot")),

    Back.BackCmdCreateSig(Back.BackSigId("sig:fma1"), { Back.BackF32, Back.BackF32, Back.BackF32 }, { Back.BackF32 }),
    Back.BackCmdDeclareFuncExport(Back.BackFuncId("fma1"), Back.BackSigId("sig:fma1")),
    Back.BackCmdBeginFunc(Back.BackFuncId("fma1")),
    Back.BackCmdCreateBlock(Back.BackBlockId("entry.fma1")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("entry.fma1")),
    Back.BackCmdBindEntryParams(Back.BackBlockId("entry.fma1"), { Back.BackValId("a"), Back.BackValId("b"), Back.BackValId("c"), }),
    Back.BackCmdFma(Back.BackValId("fma.out"), Back.BackF32, Back.BackValId("a"), Back.BackValId("b"), Back.BackValId("c")),
    Back.BackCmdReturnValue(Back.BackValId("fma.out")),
    Back.BackCmdSealBlock(Back.BackBlockId("entry.fma1")),
    Back.BackCmdFinishFunc(Back.BackFuncId("fma1")),
    Back.BackCmdFinalizeModule,
})

local intrinsic_artifact = jit:compile(intrinsic_program)
local poprot_ptr = intrinsic_artifact:getpointer(Back.BackFuncId("poprot"))
local poprot = ffi.cast("uint32_t (*)(uint32_t)", poprot_ptr)
assert(poprot(0xF0) == 8)

local fma_ptr = intrinsic_artifact:getpointer(Back.BackFuncId("fma1"))
local fma1 = ffi.cast("float (*)(float, float, float)", fma_ptr)
assert(tonumber(fma1(2, 3, 4)) == 10)
intrinsic_artifact:free()

jit:free()

print("moonlift rust ffi ok")
