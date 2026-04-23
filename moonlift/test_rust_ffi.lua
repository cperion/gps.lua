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

local switch_program = Back.BackProgram({
    Back.BackCmdCreateSig(Back.BackSigId("sig:switch_i32"), { Back.BackI32 }, { Back.BackI32 }),
    Back.BackCmdDeclareFuncExport(Back.BackFuncId("switch_i32"), Back.BackSigId("sig:switch_i32")),
    Back.BackCmdBeginFunc(Back.BackFuncId("switch_i32")),
    Back.BackCmdCreateBlock(Back.BackBlockId("entry.switch_i32")),
    Back.BackCmdCreateBlock(Back.BackBlockId("case.switch_i32.0")),
    Back.BackCmdCreateBlock(Back.BackBlockId("case.switch_i32.5")),
    Back.BackCmdCreateBlock(Back.BackBlockId("default.switch_i32")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("entry.switch_i32")),
    Back.BackCmdBindEntryParams(Back.BackBlockId("entry.switch_i32"), { Back.BackValId("x") }),
    Back.BackCmdSwitchInt(Back.BackValId("x"), Back.BackI32, {
        Back.BackSwitchCase("0", Back.BackBlockId("case.switch_i32.0")),
        Back.BackSwitchCase("5", Back.BackBlockId("case.switch_i32.5")),
    }, Back.BackBlockId("default.switch_i32")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("case.switch_i32.0")),
    Back.BackCmdConstInt(Back.BackValId("ret.switch_i32.0"), Back.BackI32, "10"),
    Back.BackCmdReturnValue(Back.BackValId("ret.switch_i32.0")),
    Back.BackCmdSealBlock(Back.BackBlockId("case.switch_i32.0")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("case.switch_i32.5")),
    Back.BackCmdConstInt(Back.BackValId("ret.switch_i32.5"), Back.BackI32, "50"),
    Back.BackCmdReturnValue(Back.BackValId("ret.switch_i32.5")),
    Back.BackCmdSealBlock(Back.BackBlockId("case.switch_i32.5")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("default.switch_i32")),
    Back.BackCmdConstInt(Back.BackValId("ret.switch_i32.default"), Back.BackI32, "99"),
    Back.BackCmdReturnValue(Back.BackValId("ret.switch_i32.default")),
    Back.BackCmdSealBlock(Back.BackBlockId("default.switch_i32")),
    Back.BackCmdSealBlock(Back.BackBlockId("entry.switch_i32")),
    Back.BackCmdFinishFunc(Back.BackFuncId("switch_i32")),

    Back.BackCmdCreateSig(Back.BackSigId("sig:switch_bool"), { Back.BackBool }, { Back.BackI32 }),
    Back.BackCmdDeclareFuncExport(Back.BackFuncId("switch_bool"), Back.BackSigId("sig:switch_bool")),
    Back.BackCmdBeginFunc(Back.BackFuncId("switch_bool")),
    Back.BackCmdCreateBlock(Back.BackBlockId("entry.switch_bool")),
    Back.BackCmdCreateBlock(Back.BackBlockId("case.switch_bool.true")),
    Back.BackCmdCreateBlock(Back.BackBlockId("default.switch_bool")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("entry.switch_bool")),
    Back.BackCmdBindEntryParams(Back.BackBlockId("entry.switch_bool"), { Back.BackValId("flag") }),
    Back.BackCmdSwitchInt(Back.BackValId("flag"), Back.BackBool, {
        Back.BackSwitchCase("1", Back.BackBlockId("case.switch_bool.true")),
    }, Back.BackBlockId("default.switch_bool")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("case.switch_bool.true")),
    Back.BackCmdConstInt(Back.BackValId("ret.switch_bool.true"), Back.BackI32, "11"),
    Back.BackCmdReturnValue(Back.BackValId("ret.switch_bool.true")),
    Back.BackCmdSealBlock(Back.BackBlockId("case.switch_bool.true")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("default.switch_bool")),
    Back.BackCmdConstInt(Back.BackValId("ret.switch_bool.default"), Back.BackI32, "22"),
    Back.BackCmdReturnValue(Back.BackValId("ret.switch_bool.default")),
    Back.BackCmdSealBlock(Back.BackBlockId("default.switch_bool")),
    Back.BackCmdSealBlock(Back.BackBlockId("entry.switch_bool")),
    Back.BackCmdFinishFunc(Back.BackFuncId("switch_bool")),

    Back.BackCmdCreateSig(Back.BackSigId("sig:switch_index"), { Back.BackIndex }, { Back.BackIndex }),
    Back.BackCmdDeclareFuncExport(Back.BackFuncId("switch_index"), Back.BackSigId("sig:switch_index")),
    Back.BackCmdBeginFunc(Back.BackFuncId("switch_index")),
    Back.BackCmdCreateBlock(Back.BackBlockId("entry.switch_index")),
    Back.BackCmdCreateBlock(Back.BackBlockId("case.switch_index.0")),
    Back.BackCmdCreateBlock(Back.BackBlockId("case.switch_index.3")),
    Back.BackCmdCreateBlock(Back.BackBlockId("default.switch_index")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("entry.switch_index")),
    Back.BackCmdBindEntryParams(Back.BackBlockId("entry.switch_index"), { Back.BackValId("idx") }),
    Back.BackCmdSwitchInt(Back.BackValId("idx"), Back.BackIndex, {
        Back.BackSwitchCase("0", Back.BackBlockId("case.switch_index.0")),
        Back.BackSwitchCase("3", Back.BackBlockId("case.switch_index.3")),
    }, Back.BackBlockId("default.switch_index")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("case.switch_index.0")),
    Back.BackCmdConstInt(Back.BackValId("ret.switch_index.0"), Back.BackIndex, "10"),
    Back.BackCmdReturnValue(Back.BackValId("ret.switch_index.0")),
    Back.BackCmdSealBlock(Back.BackBlockId("case.switch_index.0")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("case.switch_index.3")),
    Back.BackCmdConstInt(Back.BackValId("ret.switch_index.3"), Back.BackIndex, "30"),
    Back.BackCmdReturnValue(Back.BackValId("ret.switch_index.3")),
    Back.BackCmdSealBlock(Back.BackBlockId("case.switch_index.3")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("default.switch_index")),
    Back.BackCmdConstInt(Back.BackValId("ret.switch_index.default"), Back.BackIndex, "99"),
    Back.BackCmdReturnValue(Back.BackValId("ret.switch_index.default")),
    Back.BackCmdSealBlock(Back.BackBlockId("default.switch_index")),
    Back.BackCmdSealBlock(Back.BackBlockId("entry.switch_index")),
    Back.BackCmdFinishFunc(Back.BackFuncId("switch_index")),
    Back.BackCmdFinalizeModule,
})

local switch_artifact = jit:compile(switch_program)
local switch_i32_ptr = switch_artifact:getpointer(Back.BackFuncId("switch_i32"))
local switch_i32 = ffi.cast("int32_t (*)(int32_t)", switch_i32_ptr)
assert(switch_i32(0) == 10)
assert(switch_i32(5) == 50)
assert(switch_i32(9) == 99)
local switch_bool_ptr = switch_artifact:getpointer(Back.BackFuncId("switch_bool"))
local switch_bool = ffi.cast("int32_t (*)(bool)", switch_bool_ptr)
assert(switch_bool(true) == 11)
assert(switch_bool(false) == 22)
local switch_index_ptr = switch_artifact:getpointer(Back.BackFuncId("switch_index"))
local switch_index = ffi.cast("intptr_t (*)(intptr_t)", switch_index_ptr)
assert(tonumber(switch_index(0)) == 10)
assert(tonumber(switch_index(3)) == 30)
assert(tonumber(switch_index(9)) == 99)
switch_artifact:free()

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
                        Sem.SemLoopExprEndOnly,
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

local sum_view_module = lower_sem_module(Sem.SemModule("", {
    Sem.SemItemFunc(Sem.SemFuncExport(
        "sum_view",
        {
            Sem.SemParam("ptr", Sem.SemTPtrTo(Sem.SemTI32)),
            Sem.SemParam("n", Sem.SemTIndex),
        },
        Sem.SemTI32,
        {
            Sem.SemStmtReturnValue(
                Sem.SemExprLoop(
                    Sem.SemLoopOverExpr(
                        "sum.view.loop",
                        Sem.SemLoopIndexPort("i", Sem.SemTIndex),
                        Sem.SemDomainView(
                            Sem.SemViewContiguous(
                                Sem.SemExprBinding(Sem.SemBindArg(0, "ptr", Sem.SemTPtrTo(Sem.SemTI32))),
                                Sem.SemTI32,
                                Sem.SemExprBinding(Sem.SemBindArg(1, "n", Sem.SemTIndex))
                            )
                        ),
                        {
                            Sem.SemLoopCarryPort("sum.view.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
                        },
                        {},
                        {
                            Sem.SemLoopUpdate(
                                "sum.view.acc",
                                Sem.SemExprAdd(
                                    Sem.SemTI32,
                                    Sem.SemExprBinding(Sem.SemBindLoopCarry("sum.view.loop", "sum.view.acc", "acc", Sem.SemTI32)),
                                    Sem.SemExprIndex(
                                        Sem.SemIndexBaseView(
                                            Sem.SemViewContiguous(
                                                Sem.SemExprBinding(Sem.SemBindArg(0, "ptr", Sem.SemTPtrTo(Sem.SemTI32))),
                                                Sem.SemTI32,
                                                Sem.SemExprBinding(Sem.SemBindArg(1, "n", Sem.SemTIndex))
                                            )
                                        ),
                                        Sem.SemExprBinding(Sem.SemBindLoopIndex("sum.view.loop", "i", Sem.SemTIndex)),
                                        Sem.SemTI32
                                    )
                                )
                            ),
                        },
                        Sem.SemLoopExprEndOnly,
                        Sem.SemExprBinding(Sem.SemBindLoopCarry("sum.view.loop", "sum.view.acc", "acc", Sem.SemTI32))
                    ),
                    Sem.SemTI32
                )
            ),
        }
    )),
}))
local sum_view_artifact = jit:compile(sum_view_module)
local sum_view_ptr = sum_view_artifact:getpointer(Back.BackFuncId("sum_view"))
local sum_view = ffi.cast("int32_t (*)(const int32_t*, intptr_t)", sum_view_ptr)
local view_data = ffi.new("int32_t[4]", { 1, 2, 3, 4 })
assert(sum_view(view_data, 4) == 10)
sum_view_artifact:free()

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

local cfg_artifact = source.compile_module([[
func if_stmt() -> i32
    if true then
        1
    else
        2
    end
    return 7
end

func loop_if() -> i32
    return loop (i: i32 = 0, acc: i32 = 0) -> i32 while i < 4
        if true then
            1
        else
            2
        end
    next
        i = i + 1
        acc = acc + 1
    end -> acc
end

func switch_stmt() -> i32
    switch 1 do
    case 0 then
        0
    case 1 then
        1
    default then
        2
    end
    return 9
end

func switch_expr(x: i32) -> i32
    return switch x do
    case 0 then
        10
    case 1 then
        11
    case 2 then
        12
    default then
        99
    end
end

func dispatch_pair(op0: i32, op1: i32) -> i32
    return loop (i: i32 = 0, acc: i32 = 0) -> i32 while i < 2
        let op: i32 = if i == 0 then op0 else op1 end
        let add: i32 = switch op do
        case 0 then
            10
        case 1 then
            20
        default then
            30
        end
    next
        i = i + 1
        acc = acc + add
    end -> acc
end

func choose_select(flag: bool, x: i32, y: i32) -> i32
    return select(flag, x, y)
end

func typed_loop_sum(n: i32) -> i32
    return loop (i: i32 = 0, acc: i32 = 0) -> i32 while i < n
    next
        i = i + 1
        acc = acc + i
    end -> acc
end

func shared_next() -> i32
    return loop (i: i32 = 0, y: i32 = 0) -> i32 while i < 4
        let out: i32 = y + 1
    next
        i = i + 1
        y = out
    end -> y
end

func env_follow(x: f64) -> f64
    return loop (i: i32 = 0, y: f64 = 0.0) -> f64 while i < 3
    next
        i = i + 1
        y = if x < 0.5 then if x < 0.25 then 1.0 else 2.0 end else if x < 0.75 then 3.0 else 4.0 end end
    end -> y
end

func break_find_i32(n: i32) -> i32
    return loop (i: i32 = 0) -> i32 while i < n
        if i == 3 then
            break i
        end
    next
        i = i + 1
    end -> n
end

func break_find_index(n: index) -> index
    return loop (i: index over range(n)) -> index
        if i == 3 then
            break i
        end
    next
    end -> n
end
]], nil, nil, nil, jit)
local if_stmt_ptr = cfg_artifact:getpointer(Back.BackFuncId("if_stmt"))
local if_stmt = ffi.cast("int32_t (*)()", if_stmt_ptr)
assert(if_stmt() == 7)
local loop_if_ptr = cfg_artifact:getpointer(Back.BackFuncId("loop_if"))
local loop_if = ffi.cast("int32_t (*)()", loop_if_ptr)
assert(loop_if() == 4)
local switch_stmt_ptr = cfg_artifact:getpointer(Back.BackFuncId("switch_stmt"))
local switch_stmt = ffi.cast("int32_t (*)()", switch_stmt_ptr)
assert(switch_stmt() == 9)
local switch_expr_ptr = cfg_artifact:getpointer(Back.BackFuncId("switch_expr"))
local switch_expr = ffi.cast("int32_t (*)(int32_t)", switch_expr_ptr)
assert(switch_expr(0) == 10)
assert(switch_expr(2) == 12)
assert(switch_expr(9) == 99)
local dispatch_pair_ptr = cfg_artifact:getpointer(Back.BackFuncId("dispatch_pair"))
local dispatch_pair = ffi.cast("int32_t (*)(int32_t, int32_t)", dispatch_pair_ptr)
assert(dispatch_pair(0, 1) == 30)
assert(dispatch_pair(1, 5) == 50)
local choose_select_ptr = cfg_artifact:getpointer(Back.BackFuncId("choose_select"))
local choose_select = ffi.cast("int32_t (*)(bool, int32_t, int32_t)", choose_select_ptr)
assert(choose_select(true, 11, 22) == 11)
assert(choose_select(false, 11, 22) == 22)
local typed_loop_sum_ptr = cfg_artifact:getpointer(Back.BackFuncId("typed_loop_sum"))
local typed_loop_sum = ffi.cast("int32_t (*)(int32_t)", typed_loop_sum_ptr)
assert(typed_loop_sum(4) == 6)
local shared_next_ptr = cfg_artifact:getpointer(Back.BackFuncId("shared_next"))
local shared_next = ffi.cast("int32_t (*)()", shared_next_ptr)
assert(shared_next() == 4)
local env_follow_ptr = cfg_artifact:getpointer(Back.BackFuncId("env_follow"))
local env_follow = ffi.cast("double (*)(double)", env_follow_ptr)
assert(tonumber(env_follow(0.1)) == 1.0)
assert(tonumber(env_follow(0.6)) == 3.0)
assert(tonumber(env_follow(0.9)) == 4.0)
local break_find_i32_ptr = cfg_artifact:getpointer(Back.BackFuncId("break_find_i32"))
local break_find_i32 = ffi.cast("int32_t (*)(int32_t)", break_find_i32_ptr)
assert(break_find_i32(10) == 3)
assert(break_find_i32(2) == 2)
local break_find_index_ptr = cfg_artifact:getpointer(Back.BackFuncId("break_find_index"))
local break_find_index = ffi.cast("intptr_t (*)(intptr_t)", break_find_index_ptr)
assert(tonumber(break_find_index(10)) == 3)
assert(tonumber(break_find_index(2)) == 2)
cfg_artifact:free()

jit:free()

print("moonlift rust ffi ok")
