package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("pvm")
local A = require("moonlift.asdl")
local J = require("moonlift.jit")
local Source = require("moonlift.source")
local LowerBack = require("moonlift.lower_sem_to_back")

local T = pvm.context()
A.Define(T)

local Sem = T.MoonliftSem
local Back = T.MoonliftBack
local api = J.Define(T)
local source = Source.Define(T)
local lower = LowerBack.Define(T)
local jit = api.jit()

local empty_layout_env = Sem.SemLayoutEnv({})

local function lower_sem_module(node)
    return pvm.one(lower.lower_module(node, empty_layout_env))
end

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

local fib_module = lower_sem_module(Sem.SemModule("", {
    Sem.SemItemFunc(Sem.SemFuncExport(
        "fib",
        { Sem.SemParam("n", Sem.SemTI32) },
        Sem.SemTI32,
        {
            Sem.SemStmtReturnValue(
                Sem.SemExprIf(
                    Sem.SemExprLt(
                        Sem.SemTBool,
                        Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTI32)),
                        Sem.SemExprConstInt(Sem.SemTI32, "2")
                    ),
                    Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTI32)),
                    Sem.SemExprAdd(
                        Sem.SemTI32,
                        Sem.SemExprCall(
                            Sem.SemCallDirect("", "fib", Sem.SemTFunc({ Sem.SemTI32 }, Sem.SemTI32)),
                            Sem.SemTI32,
                            {
                                Sem.SemExprSub(
                                    Sem.SemTI32,
                                    Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTI32)),
                                    Sem.SemExprConstInt(Sem.SemTI32, "1")
                                ),
                            }
                        ),
                        Sem.SemExprCall(
                            Sem.SemCallDirect("", "fib", Sem.SemTFunc({ Sem.SemTI32 }, Sem.SemTI32)),
                            Sem.SemTI32,
                            {
                                Sem.SemExprSub(
                                    Sem.SemTI32,
                                    Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTI32)),
                                    Sem.SemExprConstInt(Sem.SemTI32, "2")
                                ),
                            }
                        )
                    ),
                    Sem.SemTI32
                )
            ),
        }
    )),
}))
local fib_artifact = jit:compile(fib_module)
local fib_ptr = fib_artifact:getpointer(Back.BackFuncId("fib"))
local fib = ffi.cast("int32_t (*)(int32_t)", fib_ptr)
assert(fib(10) == 55)
fib_artifact:free()

local sum_to_module = lower_sem_module(Sem.SemModule("", {
    Sem.SemItemFunc(Sem.SemFuncExport(
        "sum_to",
        { Sem.SemParam("n", Sem.SemTI32) },
        Sem.SemTI32,
        {
            Sem.SemStmtReturnValue(
                Sem.SemExprLoop(
                    Sem.SemLoopWhileExpr(
                        "sum.loop",
                        {
                            Sem.SemLoopCarryPort("sum.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
                            Sem.SemLoopCarryPort("sum.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
                        },
                        Sem.SemExprLt(
                            Sem.SemTBool,
                            Sem.SemExprBinding(Sem.SemBindLoopCarry("sum.loop", "sum.i", "i", Sem.SemTI32)),
                            Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTI32))
                        ),
                        {},
                        {
                            Sem.SemLoopUpdate(
                                "sum.i",
                                Sem.SemExprAdd(
                                    Sem.SemTI32,
                                    Sem.SemExprBinding(Sem.SemBindLoopCarry("sum.loop", "sum.i", "i", Sem.SemTI32)),
                                    Sem.SemExprConstInt(Sem.SemTI32, "1")
                                )
                            ),
                            Sem.SemLoopUpdate(
                                "sum.acc",
                                Sem.SemExprAdd(
                                    Sem.SemTI32,
                                    Sem.SemExprBinding(Sem.SemBindLoopCarry("sum.loop", "sum.acc", "acc", Sem.SemTI32)),
                                    Sem.SemExprBinding(Sem.SemBindLoopCarry("sum.loop", "sum.i", "i", Sem.SemTI32))
                                )
                            ),
                        },
                        Sem.SemExprBinding(Sem.SemBindLoopCarry("sum.loop", "sum.acc", "acc", Sem.SemTI32))
                    ),
                    Sem.SemTI32
                )
            ),
        }
    )),
}))
local sum_to_artifact = jit:compile(sum_to_module)
local sum_to_ptr = sum_to_artifact:getpointer(Back.BackFuncId("sum_to"))
local sum_to = ffi.cast("int32_t (*)(int32_t)", sum_to_ptr)
assert(sum_to(10) == 45)
sum_to_artifact:free()

local typed_artifact = source.compile_module([[
type Pair = struct { left: i32, right: i32 }
func get_left() -> i32
    return Pair { left = 1, right = 2 }.left
end
]], nil, nil, nil, jit)
local typed_ptr = typed_artifact:getpointer(Back.BackFuncId("get_left"))
local get_left = ffi.cast("int32_t (*)()", typed_ptr)
assert(get_left() == 1)
typed_artifact:free()

local package_artifact = source.compile_package({
    {
        name = "Demo",
        text = [[
func inc(x: i32) -> i32
    return x + 7
end
]],
    },
    {
        name = "Main",
        text = [[
import Demo
func main(x: i32) -> i32
    return Demo.inc(x)
end
]],
    },
}, nil, nil, nil, jit)
local package_ptr = package_artifact:getpointer(Back.BackFuncId("Main::main"))
local package_main = ffi.cast("int32_t (*)(int32_t)", package_ptr)
assert(package_main(5) == 12)
package_artifact:free()

jit:free()

print("moonlift rust ffi ok")
