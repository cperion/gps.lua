package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Resolve = require("moonlift.resolve_sem_layout")
local LowerBack = require("moonlift.lower_sem_to_back")

local T = pvm.context()
A.Define(T)

local R = Resolve.Define(T)
local B = LowerBack.Define(T)

local Sem = T.MoonliftSem
local Back = T.MoonliftBack

local layout_env = Sem.SemLayoutEnv({
    Sem.SemLayoutNamed("Demo", "Pair", {
        Sem.SemFieldLayout("left", 0, Sem.SemTI32),
        Sem.SemFieldLayout("right", 4, Sem.SemTI32),
    }, 8, 4),
})

assert(pvm.one(R.resolve_type_mem_layout(Sem.SemTI32, layout_env, Sem.SemModule("", {}), {}, {})) == Sem.SemMemLayout(4, 4))
assert(pvm.one(R.resolve_type_mem_layout(Sem.SemTPtrTo(Sem.SemTI32), layout_env, Sem.SemModule("", {}), {}, {})) == Sem.SemMemLayout(8, 8))
assert(pvm.one(R.resolve_type_mem_layout(Sem.SemTArray(Sem.SemTI32, 3), layout_env, Sem.SemModule("", {}), {}, {})) == Sem.SemMemLayout(12, 4))
assert(pvm.one(R.resolve_type_mem_layout(Sem.SemTSlice(Sem.SemTI32), layout_env, Sem.SemModule("", {}), {}, {})) == Sem.SemMemLayout(16, 8))
assert(pvm.one(R.resolve_type_mem_layout(Sem.SemTView(Sem.SemTI32), layout_env, Sem.SemModule("", {}), {}, {})) == Sem.SemMemLayout(24, 8))

local pair_ptr = Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTNamed("Demo", "Pair"))))
local pair_value = Sem.SemExprDeref(Sem.SemTNamed("Demo", "Pair"), pair_ptr)
local pair_place = Sem.SemPlaceDeref(pair_ptr, Sem.SemTNamed("Demo", "Pair"))

local unresolved_field = Sem.SemExprField(
    pair_value,
    Sem.SemFieldByName("right", Sem.SemTI32)
)

local resolved_field = pvm.one(R.resolve_expr(unresolved_field, layout_env))
assert(resolved_field == Sem.SemExprField(
    Sem.SemExprDeref(Sem.SemTNamed("Demo", "Pair"), Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTNamed("Demo", "Pair"))))),
    Sem.SemFieldByOffset("right", 4, Sem.SemTI32)
))

local lowered_field = pvm.one(B.lower_expr(resolved_field, "expr.pair.right"))
assert(lowered_field == Back.BackExprPlan({
    Back.BackCmdConstInt(Back.BackValId("expr.pair.right.addr.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("expr.pair.right.addr"), Back.BackPtr, Back.BackValId("arg:0:p"), Back.BackValId("expr.pair.right.addr.offset")),
    Back.BackCmdLoad(Back.BackValId("expr.pair.right"), Back.BackI32, Back.BackValId("expr.pair.right.addr")),
}, Back.BackValId("expr.pair.right"), Back.BackI32))

local unresolved_field_addr = Sem.SemExprAddrOf(
    Sem.SemPlaceField(
        pair_place,
        Sem.SemFieldByName("left", Sem.SemTI32)
    ),
    Sem.SemTPtrTo(Sem.SemTI32)
)

local resolved_field_addr = pvm.one(R.resolve_expr(unresolved_field_addr, layout_env))
assert(resolved_field_addr == Sem.SemExprAddrOf(
    Sem.SemPlaceField(
        Sem.SemPlaceDeref(Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTNamed("Demo", "Pair")))), Sem.SemTNamed("Demo", "Pair")),
        Sem.SemFieldByOffset("left", 0, Sem.SemTI32)
    ),
    Sem.SemTPtrTo(Sem.SemTI32)
))

local unresolved_switch_expr = Sem.SemExprSwitch(
    Sem.SemExprBinding(Sem.SemBindArg(1, "tag", Sem.SemTI32)),
    {
        Sem.SemSwitchExprArm(
            Sem.SemExprConstInt(Sem.SemTI32, "1"),
            {},
            Sem.SemExprField(pair_value, Sem.SemFieldByName("left", Sem.SemTI32))
        ),
    },
    Sem.SemExprConstInt(Sem.SemTI32, "0"),
    Sem.SemTI32
)

local resolved_switch_expr = pvm.one(R.resolve_expr(unresolved_switch_expr, layout_env))
assert(resolved_switch_expr == Sem.SemExprSwitch(
    Sem.SemExprBinding(Sem.SemBindArg(1, "tag", Sem.SemTI32)),
    {
        Sem.SemSwitchExprArm(
            Sem.SemExprConstInt(Sem.SemTI32, "1"),
            {},
            Sem.SemExprField(
                Sem.SemExprDeref(Sem.SemTNamed("Demo", "Pair"), Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTNamed("Demo", "Pair"))))),
                Sem.SemFieldByOffset("left", 0, Sem.SemTI32)
            )
        ),
    },
    Sem.SemExprConstInt(Sem.SemTI32, "0"),
    Sem.SemTI32
))

local module = Sem.SemModule("", {
    Sem.SemItemFunc(Sem.SemFuncExport(
        "get_right",
        { Sem.SemParam("p", Sem.SemTPtrTo(Sem.SemTNamed("Demo", "Pair"))) },
        Sem.SemTI32,
        {
            Sem.SemStmtReturnValue(unresolved_field),
        }
    )),
})

local resolved_module = pvm.one(R.resolve_module(module, layout_env))
assert(resolved_module == Sem.SemModule("", {
    Sem.SemItemFunc(Sem.SemFuncExport(
        "get_right",
        { Sem.SemParam("p", Sem.SemTPtrTo(Sem.SemTNamed("Demo", "Pair"))) },
        Sem.SemTI32,
        {
            Sem.SemStmtReturnValue(Sem.SemExprField(
                Sem.SemExprDeref(Sem.SemTNamed("Demo", "Pair"), Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTNamed("Demo", "Pair"))))),
                Sem.SemFieldByOffset("right", 4, Sem.SemTI32)
            )),
        }
    )),
}))

local static_module = Sem.SemModule("", {
    Sem.SemItemStatic(Sem.SemStatic(
        "PAIR",
        Sem.SemTNamed("Demo", "Pair"),
        Sem.SemExprAgg(Sem.SemTNamed("Demo", "Pair"), {
            Sem.SemFieldInit("left", Sem.SemExprConstInt(Sem.SemTI32, "10")),
            Sem.SemFieldInit("right", Sem.SemExprConstInt(Sem.SemTI32, "32")),
        })
    )),
    Sem.SemItemFunc(Sem.SemFuncExport(
        "pair_right",
        {},
        Sem.SemTI32,
        {
            Sem.SemStmtReturnValue(Sem.SemExprField(
                Sem.SemExprBinding(Sem.SemBindGlobalStatic("", "PAIR", Sem.SemTNamed("Demo", "Pair"))),
                Sem.SemFieldByOffset("right", 4, Sem.SemTI32)
            )),
        }
    )),
})

local lowered_static_module = pvm.one(B.lower_module(static_module, layout_env))
assert(lowered_static_module == Back.BackProgram({
    Back.BackCmdDeclareData(Back.BackDataId("data:static:PAIR"), 8, 4),
    Back.BackCmdDataInitZero(Back.BackDataId("data:static:PAIR"), 0, 8),
    Back.BackCmdDataInitInt(Back.BackDataId("data:static:PAIR"), 0, Back.BackI32, "10"),
    Back.BackCmdDataInitInt(Back.BackDataId("data:static:PAIR"), 4, Back.BackI32, "32"),
    Back.BackCmdCreateSig(Back.BackSigId("sig:pair_right"), {}, { Back.BackI32 }),
    Back.BackCmdDeclareFuncExport(Back.BackFuncId("pair_right"), Back.BackSigId("sig:pair_right")),
    Back.BackCmdBeginFunc(Back.BackFuncId("pair_right")),
    Back.BackCmdCreateBlock(Back.BackBlockId("pair_right:entry")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("pair_right:entry")),
    Back.BackCmdDataAddr(Back.BackValId("func:pair_right.stmt.1.value.addr.base"), Back.BackDataId("data:static:PAIR")),
    Back.BackCmdConstInt(Back.BackValId("func:pair_right.stmt.1.value.addr.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("func:pair_right.stmt.1.value.addr"), Back.BackPtr, Back.BackValId("func:pair_right.stmt.1.value.addr.base"), Back.BackValId("func:pair_right.stmt.1.value.addr.offset")),
    Back.BackCmdLoad(Back.BackValId("func:pair_right.stmt.1.value"), Back.BackI32, Back.BackValId("func:pair_right.stmt.1.value.addr")),
    Back.BackCmdReturnValue(Back.BackValId("func:pair_right.stmt.1.value")),
    Back.BackCmdSealBlock(Back.BackBlockId("pair_right:entry")),
    Back.BackCmdFinishFunc(Back.BackFuncId("pair_right")),
    Back.BackCmdFinalizeModule,
}))

local ok_missing_layout, err_missing_layout = pcall(function()
    return pvm.one(R.resolve_expr(
        unresolved_field,
        Sem.SemLayoutEnv({})
    ))
end)
assert(not ok_missing_layout)
assert(string.find(err_missing_layout, "missing layout for named type 'Demo.Pair'", 1, true) ~= nil)

local ok_missing_field, err_missing_field = pcall(function()
    return pvm.one(R.resolve_expr(
        Sem.SemExprField(pair_value, Sem.SemFieldByName("missing", Sem.SemTI32)),
        layout_env
    ))
end)
assert(not ok_missing_field)
assert(string.find(err_missing_field, "unknown field 'missing' on type 'Demo.Pair'", 1, true) ~= nil)

print("moonlift sem layout resolve ok")
