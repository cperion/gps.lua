package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Lower = require("moonlift.lower_sem_to_back")

local T = pvm.context()
A.Define(T)
local L = Lower.Define(T)

local Sem = T.MoonliftSem
local Back = T.MoonliftBack

local empty_layout_env = Sem.SemLayoutEnv({})
local pair_layout_env = Sem.SemLayoutEnv({
    Sem.SemLayoutNamed("Demo", "Pair", {
        Sem.SemFieldLayout("left", 0, Sem.SemTI32),
        Sem.SemFieldLayout("right", 4, Sem.SemTI32),
    }, 8, 4),
})

local function one_expr(node, path, layout_env)
    return pvm.one(L.lower_expr(node, path, layout_env or empty_layout_env))
end

local function one_stmt(node, path, layout_env)
    return pvm.one(L.lower_stmt(node, path, layout_env or empty_layout_env))
end

local function one_module(node, layout_env)
    return pvm.one(L.lower_module(node, layout_env or empty_layout_env))
end

local function contains_cmd(plan, cmd)
    for i = 1, #plan.cmds do
        if plan.cmds[i] == cmd then
            return true
        end
    end
    return false
end

local function lacks_cmd(plan, cmd)
    return not contains_cmd(plan, cmd)
end

local function expect_error(fn, text)
    local ok, err = pcall(fn)
    assert(not ok)
    assert(string.find(err, text, 1, true) ~= nil)
end

assert(pvm.one(L.lower_scalar(Sem.SemTI32)) == Back.BackI32)
assert(pvm.one(L.lower_scalar(Sem.SemTIndex)) == Back.BackIndex)
assert(pvm.one(L.lower_stack_slot_spec(Sem.SemTSlice(Sem.SemTI32), empty_layout_env)) == Back.BackStackSlotSpec(16, 8))
assert(pvm.one(L.lower_stack_slot_spec(Sem.SemTView(Sem.SemTI32), empty_layout_env)) == Back.BackStackSlotSpec(24, 8))
assert(pvm.one(L.lower_binding_value(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32))) == Back.BackValId("local:lx"))

local add = one_expr(
    Sem.SemExprAdd(
        Sem.SemTI32,
        Sem.SemExprBinding(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32)),
        Sem.SemExprConstInt(Sem.SemTI32, "1")
    ),
    "expr.add"
)
assert(add == Back.BackExprPlan({
    Back.BackCmdConstInt(Back.BackValId("expr.add.rhs"), Back.BackI32, "1"),
    Back.BackCmdIadd(Back.BackValId("expr.add"), Back.BackI32, Back.BackValId("local:lx"), Back.BackValId("expr.add.rhs")),
}, Back.BackValId("expr.add"), Back.BackI32))

local cell_read = one_expr(
    Sem.SemExprBinding(Sem.SemBindLocalCell("cx", "x", Sem.SemTI32)),
    "expr.cell"
)
assert(cell_read == Back.BackExprPlan({
    Back.BackCmdStackAddr(Back.BackValId("expr.cell.addr"), Back.BackStackSlotId("slot:cx")),
    Back.BackCmdLoad(Back.BackValId("expr.cell"), Back.BackI32, Back.BackValId("expr.cell.addr")),
}, Back.BackValId("expr.cell"), Back.BackI32))

local addr_of_cell = one_expr(
    Sem.SemExprAddrOf(
        Sem.SemPlaceBinding(Sem.SemBindLocalCell("cx", "x", Sem.SemTI32)),
        Sem.SemTPtrTo(Sem.SemTI32)
    ),
    "expr.addr_of_cell"
)
assert(addr_of_cell == Back.BackExprPlan({
    Back.BackCmdStackAddr(Back.BackValId("expr.addr_of_cell"), Back.BackStackSlotId("slot:cx")),
}, Back.BackValId("expr.addr_of_cell"), Back.BackPtr))

local field_addr = one_expr(
    Sem.SemExprAddrOf(
        Sem.SemPlaceField(
            Sem.SemPlaceBinding(Sem.SemBindLocalCell("pair.cell", "pair", Sem.SemTNamed("Demo", "Pair"))),
            Sem.SemFieldByOffset("right", 4, Sem.SemTI32)
        ),
        Sem.SemTPtrTo(Sem.SemTI32)
    ),
    "expr.field_addr",
    pair_layout_env
)
assert(field_addr == Back.BackExprPlan({
    Back.BackCmdStackAddr(Back.BackValId("expr.field_addr.base"), Back.BackStackSlotId("slot:pair.cell")),
    Back.BackCmdConstInt(Back.BackValId("expr.field_addr.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("expr.field_addr"), Back.BackPtr, Back.BackValId("expr.field_addr.base"), Back.BackValId("expr.field_addr.offset")),
}, Back.BackValId("expr.field_addr"), Back.BackPtr))

local bool_and = one_expr(
    Sem.SemExprAnd(
        Sem.SemTBool,
        Sem.SemExprBinding(Sem.SemBindArg(0, "b", Sem.SemTBool)),
        Sem.SemExprConstBool(true)
    ),
    "expr.and"
)
assert(bool_and == Back.BackExprPlan({
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.and.rhs.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.and.short.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.and.join.block")),
    Back.BackCmdAppendBlockParam(Back.BackBlockId("expr.and.join.block"), Back.BackValId("expr.and"), Back.BackBool),
    Back.BackCmdBrIf(Back.BackValId("arg:0:b"), Back.BackBlockId("expr.and.rhs.block"), {}, Back.BackBlockId("expr.and.short.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.and.rhs.block")),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.and.short.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.and.short.block")),
    Back.BackCmdConstBool(Back.BackValId("expr.and.short"), false),
    Back.BackCmdJump(Back.BackBlockId("expr.and.join.block"), { Back.BackValId("expr.and.short") }),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.and.rhs.block")),
    Back.BackCmdConstBool(Back.BackValId("expr.and.rhs"), true),
    Back.BackCmdJump(Back.BackBlockId("expr.and.join.block"), { Back.BackValId("expr.and.rhs") }),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.and.join.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.and.join.block")),
}, Back.BackValId("expr.and"), Back.BackBool))

local bool_or = one_expr(
    Sem.SemExprOr(
        Sem.SemTBool,
        Sem.SemExprBinding(Sem.SemBindArg(0, "b", Sem.SemTBool)),
        Sem.SemExprConstBool(false)
    ),
    "expr.or"
)
assert(bool_or == Back.BackExprPlan({
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.or.rhs.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.or.short.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.or.join.block")),
    Back.BackCmdAppendBlockParam(Back.BackBlockId("expr.or.join.block"), Back.BackValId("expr.or"), Back.BackBool),
    Back.BackCmdBrIf(Back.BackValId("arg:0:b"), Back.BackBlockId("expr.or.rhs.block"), {}, Back.BackBlockId("expr.or.short.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.or.rhs.block")),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.or.short.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.or.short.block")),
    Back.BackCmdConstBool(Back.BackValId("expr.or.short"), true),
    Back.BackCmdJump(Back.BackBlockId("expr.or.join.block"), { Back.BackValId("expr.or.short") }),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.or.rhs.block")),
    Back.BackCmdConstBool(Back.BackValId("expr.or.rhs"), false),
    Back.BackCmdJump(Back.BackBlockId("expr.or.join.block"), { Back.BackValId("expr.or.rhs") }),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.or.join.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.or.join.block")),
}, Back.BackValId("expr.or"), Back.BackBool))

local popcount_expr = one_expr(
    Sem.SemExprIntrinsicCall(
        Sem.SemPopcount,
        Sem.SemTU32,
        { Sem.SemExprConstInt(Sem.SemTU32, "240") }
    ),
    "expr.popcount"
)
assert(popcount_expr == Back.BackExprPlan({
    Back.BackCmdConstInt(Back.BackValId("expr.popcount.arg.1"), Back.BackU32, "240"),
    Back.BackCmdPopcount(Back.BackValId("expr.popcount"), Back.BackU32, Back.BackValId("expr.popcount.arg.1")),
}, Back.BackValId("expr.popcount"), Back.BackU32))

local direct_call = one_expr(
    Sem.SemExprCall(
        Sem.SemCallDirect("", "sum", Sem.SemTFunc({ Sem.SemTI32 }, Sem.SemTI32)),
        Sem.SemTI32,
        { Sem.SemExprConstInt(Sem.SemTI32, "7") }
    ),
    "expr.call"
)
assert(direct_call == Back.BackExprPlan({
    Back.BackCmdConstInt(Back.BackValId("expr.call.arg.1"), Back.BackI32, "7"),
    Back.BackCmdCallValueDirect(Back.BackValId("expr.call"), Back.BackI32, Back.BackFuncId("sum"), Back.BackSigId("sig:sum"), { Back.BackValId("expr.call.arg.1") }),
}, Back.BackValId("expr.call"), Back.BackI32))

local let_scalar = one_stmt(
    Sem.SemStmtLet(
        "lx",
        "x",
        Sem.SemTI32,
        Sem.SemExprConstInt(Sem.SemTI32, "9")
    ),
    "stmt.let_scalar"
)
assert(let_scalar == Back.BackStmtPlan({
    Back.BackCmdConstInt(Back.BackValId("stmt.let_scalar.init"), Back.BackI32, "9"),
    Back.BackCmdAlias(Back.BackValId("local:lx"), Back.BackValId("stmt.let_scalar.init")),
}, Back.BackFallsThrough))
assert(lacks_cmd(let_scalar, Back.BackCmdCreateStackSlot(Back.BackStackSlotId("slot:local:lx"), 4, 4)))

local set_binding = one_stmt(
    Sem.SemStmtSet(
        Sem.SemPlaceBinding(Sem.SemBindLocalCell("cx", "x", Sem.SemTI32)),
        Sem.SemExprConstInt(Sem.SemTI32, "9")
    ),
    "stmt.set_binding"
)
assert(set_binding == Back.BackStmtPlan({
    Back.BackCmdStackAddr(Back.BackValId("stmt.set_binding.addr"), Back.BackStackSlotId("slot:cx")),
    Back.BackCmdConstInt(Back.BackValId("stmt.set_binding.value"), Back.BackI32, "9"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("stmt.set_binding.addr"), Back.BackValId("stmt.set_binding.value")),
}, Back.BackFallsThrough))

local set_deref = one_stmt(
    Sem.SemStmtSet(
        Sem.SemPlaceDeref(
            Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTI32))),
            Sem.SemTI32
        ),
        Sem.SemExprConstInt(Sem.SemTI32, "9")
    ),
    "stmt.set_deref"
)
assert(set_deref == Back.BackStmtPlan({
    Back.BackCmdConstInt(Back.BackValId("stmt.set_deref.value"), Back.BackI32, "9"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("arg:0:p"), Back.BackValId("stmt.set_deref.value")),
}, Back.BackFallsThrough))

local set_field = one_stmt(
    Sem.SemStmtSet(
        Sem.SemPlaceField(
            Sem.SemPlaceBinding(Sem.SemBindLocalCell("pair.cell", "pair", Sem.SemTNamed("Demo", "Pair"))),
            Sem.SemFieldByOffset("right", 4, Sem.SemTI32)
        ),
        Sem.SemExprConstInt(Sem.SemTI32, "32")
    ),
    "stmt.set_field",
    pair_layout_env
)
assert(set_field == Back.BackStmtPlan({
    Back.BackCmdStackAddr(Back.BackValId("stmt.set_field.addr.base"), Back.BackStackSlotId("slot:pair.cell")),
    Back.BackCmdConstInt(Back.BackValId("stmt.set_field.addr.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("stmt.set_field.addr"), Back.BackPtr, Back.BackValId("stmt.set_field.addr.base"), Back.BackValId("stmt.set_field.addr.offset")),
    Back.BackCmdConstInt(Back.BackValId("stmt.set_field.value"), Back.BackI32, "32"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("stmt.set_field.addr"), Back.BackValId("stmt.set_field.value")),
}, Back.BackFallsThrough))

local while_break_value = one_expr(
    Sem.SemExprLoop(
        Sem.SemLoopWhileExpr(
            "loop.break",
            {
                Sem.SemLoopCarryPort("carry.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
            },
            Sem.SemExprConstBool(true),
            {
                Sem.SemStmtBreakValue(Sem.SemExprConstInt(Sem.SemTI32, "5")),
            },
            {
                Sem.SemLoopUpdate(
                    "carry.i",
                    Sem.SemExprAdd(
                        Sem.SemTI32,
                        Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.break", "carry.i", "i", Sem.SemTI32)),
                        Sem.SemExprConstInt(Sem.SemTI32, "1")
                    )
                ),
            },
            Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.break", "carry.i", "i", Sem.SemTI32))
        ),
        Sem.SemTI32
    ),
    "expr.loopbreak"
)
assert(while_break_value.value == Back.BackValId("expr.loopbreak"))
assert(while_break_value.ty == Back.BackI32)
assert(lacks_cmd(while_break_value, Back.BackCmdCreateStackSlot(Back.BackStackSlotId("slot:loopcarry:loop.break:carry.i"), 4, 4)))
assert(contains_cmd(while_break_value, Back.BackCmdAlias(Back.BackValId("local:loopcarry:loop.break:carry.i"), Back.BackValId("expr.loopbreak.header.param.1"))))
assert(contains_cmd(while_break_value, Back.BackCmdCreateStackSlot(Back.BackStackSlotId("slot:breakvalue:flag:expr.loopbreak.exit.block"), 1, 1)))
assert(contains_cmd(while_break_value, Back.BackCmdCreateStackSlot(Back.BackStackSlotId("slot:breakvalue:value:expr.loopbreak.exit.block"), 4, 4)))
assert(contains_cmd(while_break_value, Back.BackCmdJump(Back.BackBlockId("expr.loopbreak.exit.block"), { Back.BackValId("expr.loopbreak.body.param.1") })))
assert(contains_cmd(while_break_value, Back.BackCmdLoad(Back.BackValId("expr.loopbreak.break.value.loaded"), Back.BackI32, Back.BackValId("expr.loopbreak.break.value.addr"))))

local over_range_expr = one_expr(
    Sem.SemExprLoop(
        Sem.SemLoopOverExpr(
            "loop.range",
            Sem.SemLoopIndexPort("i", Sem.SemTIndex),
            Sem.SemDomainRange(Sem.SemExprConstInt(Sem.SemTIndex, "3")),
            {
                Sem.SemLoopCarryPort("carry.acc", "acc", Sem.SemTIndex, Sem.SemExprConstInt(Sem.SemTIndex, "0")),
            },
            {},
            {
                Sem.SemLoopUpdate(
                    "carry.acc",
                    Sem.SemExprAdd(
                        Sem.SemTIndex,
                        Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.range", "carry.acc", "acc", Sem.SemTIndex)),
                        Sem.SemExprBinding(Sem.SemBindLoopIndex("loop.range", "i", Sem.SemTIndex))
                    )
                ),
            },
            Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.range", "carry.acc", "acc", Sem.SemTIndex))
        ),
        Sem.SemTIndex
    ),
    "expr.over"
)
assert(over_range_expr.value == Back.BackValId("expr.over"))
assert(over_range_expr.ty == Back.BackIndex)
assert(lacks_cmd(over_range_expr, Back.BackCmdCreateStackSlot(Back.BackStackSlotId("slot:loopindex:loop.range:i"), 8, 8)))
assert(lacks_cmd(over_range_expr, Back.BackCmdCreateStackSlot(Back.BackStackSlotId("slot:loopcarry:loop.range:carry.acc"), 8, 8)))
assert(contains_cmd(over_range_expr, Back.BackCmdConstInt(Back.BackValId("expr.over.stop"), Back.BackIndex, "3")))
assert(contains_cmd(over_range_expr, Back.BackCmdAlias(Back.BackValId("local:loopindex:loop.range:i"), Back.BackValId("expr.over.header.index"))))
assert(contains_cmd(over_range_expr, Back.BackCmdAlias(Back.BackValId("local:loopcarry:loop.range:carry.acc"), Back.BackValId("expr.over.header.carry.1"))))

local bounded_over_expr = one_expr(
    Sem.SemExprLoop(
        Sem.SemLoopOverExpr(
            "loop.view",
            Sem.SemLoopIndexPort("i", Sem.SemTIndex),
            Sem.SemDomainView(
                Sem.SemViewValue(
                    Sem.SemExprBinding(Sem.SemBindLocalCell("bounded.arr", "arr", Sem.SemTArray(Sem.SemTI32, 4))),
                    Sem.SemTI32
                )
            ),
            {
                Sem.SemLoopCarryPort("carry.acc", "acc", Sem.SemTIndex, Sem.SemExprConstInt(Sem.SemTIndex, "0")),
            },
            {},
            {
                Sem.SemLoopUpdate(
                    "carry.acc",
                    Sem.SemExprAdd(
                        Sem.SemTIndex,
                        Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.view", "carry.acc", "acc", Sem.SemTIndex)),
                        Sem.SemExprBinding(Sem.SemBindLoopIndex("loop.view", "i", Sem.SemTIndex))
                    )
                ),
            },
            Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.view", "carry.acc", "acc", Sem.SemTIndex))
        ),
        Sem.SemTIndex
    ),
    "expr.view"
)
assert(contains_cmd(bounded_over_expr, Back.BackCmdAlias(Back.BackValId("expr.view.view.data"), Back.BackValId("expr.view.view.base"))))
assert(contains_cmd(bounded_over_expr, Back.BackCmdConstInt(Back.BackValId("expr.view.view.len"), Back.BackIndex, "4")))

local slice_index_expr = one_expr(
    Sem.SemExprIndex(
        Sem.SemIndexBaseView(
            Sem.SemViewValue(
                Sem.SemExprBinding(Sem.SemBindLocalCell("slice.cell", "s", Sem.SemTSlice(Sem.SemTI32))),
                Sem.SemTI32
            )
        ),
        Sem.SemExprConstInt(Sem.SemTIndex, "1"),
        Sem.SemTI32
    ),
    "expr.slice_index"
)
assert(contains_cmd(slice_index_expr, Back.BackCmdStackAddr(Back.BackValId("expr.slice_index.addr.view.base"), Back.BackStackSlotId("slot:slice.cell"))))
assert(contains_cmd(slice_index_expr, Back.BackCmdLoad(Back.BackValId("expr.slice_index.addr.view.data"), Back.BackPtr, Back.BackValId("expr.slice_index.addr.view.data.addr"))))
assert(contains_cmd(slice_index_expr, Back.BackCmdLoad(Back.BackValId("expr.slice_index.addr.view.len"), Back.BackIndex, Back.BackValId("expr.slice_index.addr.view.len.addr"))))
assert(contains_cmd(slice_index_expr, Back.BackCmdConstInt(Back.BackValId("expr.slice_index.addr.view.stride"), Back.BackIndex, "4")))
assert(contains_cmd(slice_index_expr, Back.BackCmdLoad(Back.BackValId("expr.slice_index"), Back.BackI32, Back.BackValId("expr.slice_index.addr"))))

local strided_index_expr = one_expr(
    Sem.SemExprIndex(
        Sem.SemIndexBaseView(
            Sem.SemViewStrided(
                Sem.SemExprBinding(Sem.SemBindArg(0, "ptr", Sem.SemTPtrTo(Sem.SemTI32))),
                Sem.SemTI32,
                Sem.SemExprConstInt(Sem.SemTIndex, "8"),
                Sem.SemExprConstInt(Sem.SemTIndex, "2")
            )
        ),
        Sem.SemExprConstInt(Sem.SemTIndex, "3"),
        Sem.SemTI32
    ),
    "expr.strided_index"
)
assert(contains_cmd(strided_index_expr, Back.BackCmdConstInt(Back.BackValId("expr.strided_index.addr.view.elem_size"), Back.BackIndex, "4")))
assert(contains_cmd(strided_index_expr, Back.BackCmdImul(Back.BackValId("expr.strided_index.addr.view.stride"), Back.BackIndex, Back.BackValId("expr.strided_index.addr.view.stride.expr"), Back.BackValId("expr.strided_index.addr.view.elem_size"))))
assert(contains_cmd(strided_index_expr, Back.BackCmdImul(Back.BackValId("expr.strided_index.addr.offset"), Back.BackIndex, Back.BackValId("expr.strided_index.addr.index"), Back.BackValId("expr.strided_index.addr.view.stride"))))

local zip_over_expr = one_expr(
    Sem.SemExprLoop(
        Sem.SemLoopOverExpr(
            "loop.zip",
            Sem.SemLoopIndexPort("i", Sem.SemTIndex),
            Sem.SemDomainZipEq({
                Sem.SemViewValue(Sem.SemExprBinding(Sem.SemBindLocalCell("zip.a", "a", Sem.SemTArray(Sem.SemTI32, 3))), Sem.SemTI32),
                Sem.SemViewValue(Sem.SemExprBinding(Sem.SemBindLocalCell("zip.b", "b", Sem.SemTArray(Sem.SemTI32, 3))), Sem.SemTI32),
            }),
            {
                Sem.SemLoopCarryPort("carry.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
            },
            {},
            {
                Sem.SemLoopUpdate(
                    "carry.acc",
                    Sem.SemExprAdd(
                        Sem.SemTI32,
                        Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.zip", "carry.acc", "acc", Sem.SemTI32)),
                        Sem.SemExprConstInt(Sem.SemTI32, "1")
                    )
                ),
            },
            Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.zip", "carry.acc", "acc", Sem.SemTI32))
        ),
        Sem.SemTI32
    ),
    "expr.zip"
)
assert(contains_cmd(zip_over_expr, Back.BackCmdAlias(Back.BackValId("expr.zip.zip.view.1.data"), Back.BackValId("expr.zip.zip.view.1.base"))))
assert(contains_cmd(zip_over_expr, Back.BackCmdAlias(Back.BackValId("expr.zip.zip.view.2.data"), Back.BackValId("expr.zip.zip.view.2.base"))))
assert(contains_cmd(zip_over_expr, Back.BackCmdConstInt(Back.BackValId("expr.zip.zip.view.1.len"), Back.BackIndex, "3")))

local slice_zip_over_expr = one_expr(
    Sem.SemExprLoop(
        Sem.SemLoopOverExpr(
            "loop.slice.zip",
            Sem.SemLoopIndexPort("i", Sem.SemTIndex),
            Sem.SemDomainZipEq({
                Sem.SemViewValue(Sem.SemExprBinding(Sem.SemBindLocalCell("slice.a", "a", Sem.SemTSlice(Sem.SemTI32))), Sem.SemTI32),
                Sem.SemViewValue(Sem.SemExprBinding(Sem.SemBindLocalCell("slice.b", "b", Sem.SemTSlice(Sem.SemTI32))), Sem.SemTI32),
            }),
            {
                Sem.SemLoopCarryPort("carry.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
            },
            {},
            {
                Sem.SemLoopUpdate(
                    "carry.acc",
                    Sem.SemExprAdd(
                        Sem.SemTI32,
                        Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.slice.zip", "carry.acc", "acc", Sem.SemTI32)),
                        Sem.SemExprConstInt(Sem.SemTI32, "1")
                    )
                ),
            },
            Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.slice.zip", "carry.acc", "acc", Sem.SemTI32))
        ),
        Sem.SemTI32
    ),
    "expr.slice_zip"
)
assert(contains_cmd(slice_zip_over_expr, Back.BackCmdLoad(Back.BackValId("expr.slice_zip.zip.view.1.len"), Back.BackIndex, Back.BackValId("expr.slice_zip.zip.view.1.len.addr"))))
assert(contains_cmd(slice_zip_over_expr, Back.BackCmdLoad(Back.BackValId("expr.slice_zip.zip.view.2.len"), Back.BackIndex, Back.BackValId("expr.slice_zip.zip.view.2.len.addr"))))
assert(contains_cmd(slice_zip_over_expr, Back.BackCmdTrap))

expect_error(function()
    one_stmt(Sem.SemStmtBreak, "stmt.break")
end, "sem_to_back_stmt: break is only valid inside a loop body")

expect_error(function()
    one_stmt(Sem.SemStmtBreakValue(Sem.SemExprConstInt(Sem.SemTI32, "1")), "stmt.break_value")
end, "sem_to_back_stmt: break_value is only valid inside an expression loop body")

expect_error(function()
    one_stmt(Sem.SemStmtContinue, "stmt.continue")
end, "sem_to_back_stmt: continue is only valid inside a loop body")

expect_error(function()
    one_expr(Sem.SemExprBinding(Sem.SemBindGlobalConst("", "K", Sem.SemTI32)), "expr.const_global")
end, "sem_to_back_binding_expr: pure const globals should be folded/lowered before direct runtime binding reads ('K')")

local static_module = one_module(Sem.SemModule("", {
    Sem.SemItemConst(Sem.SemConst(
        "A",
        Sem.SemTI32,
        Sem.SemExprAdd(
            Sem.SemTI32,
            Sem.SemExprConstInt(Sem.SemTI32, "40"),
            Sem.SemExprConstInt(Sem.SemTI32, "2")
        )
    )),
    Sem.SemItemStatic(Sem.SemStatic(
        "S",
        Sem.SemTI32,
        Sem.SemExprAdd(
            Sem.SemTI32,
            Sem.SemExprBinding(Sem.SemBindGlobalConst("", "A", Sem.SemTI32)),
            Sem.SemExprConstInt(Sem.SemTI32, "1")
        )
    )),
    Sem.SemItemFunc(Sem.SemFuncExport(
        "get_s",
        {},
        Sem.SemTI32,
        {
            Sem.SemStmtReturnValue(Sem.SemExprBinding(Sem.SemBindGlobalStatic("", "S", Sem.SemTI32))),
        }
    )),
}))
assert(contains_cmd(static_module, Back.BackCmdDeclareData(Back.BackDataId("data:static:S"), 4, 4)))
assert(contains_cmd(static_module, Back.BackCmdDataInitInt(Back.BackDataId("data:static:S"), 0, Back.BackI32, "43")))
assert(lacks_cmd(static_module, Back.BackCmdDeclareData(Back.BackDataId("data:const:A"), 4, 4)))
assert(contains_cmd(static_module, Back.BackCmdDataAddr(Back.BackValId("func:get_s.stmt.1.value.addr"), Back.BackDataId("data:static:S"))))
assert(static_module.cmds[#static_module.cmds] == Back.BackCmdFinalizeModule)

local arg_residence_module = one_module(Sem.SemModule("", {
    Sem.SemItemFunc(Sem.SemFuncExport(
        "arg_residence",
        {
            Sem.SemParam("n", Sem.SemTI32),
        },
        Sem.SemTVoid,
        {
            Sem.SemStmtReturnVoid,
        }
    )),
}))
assert(contains_cmd(arg_residence_module, Back.BackCmdBindEntryParams(
    Back.BackBlockId("arg_residence:entry"),
    { Back.BackValId("arg:0:n") }
)))
assert(lacks_cmd(arg_residence_module, Back.BackCmdCreateStackSlot(Back.BackStackSlotId("slot:arg:0:n"), 4, 4)))
assert(lacks_cmd(arg_residence_module, Back.BackCmdStackAddr(Back.BackValId("arg.addr:0:n"), Back.BackStackSlotId("slot:arg:0:n"))))

expect_error(function()
    one_expr(
        Sem.SemExprAddrOf(
            Sem.SemPlaceBinding(Sem.SemBindArg(0, "n", Sem.SemTI32)),
            Sem.SemTPtrTo(Sem.SemTI32)
        ),
        "expr.addr_of_value_arg"
    )
end, "sem_to_back_binding_addr: pure value argument 'n' has no canonical storage in Sem->Back yet")

print("moonlift sem->back lowering ok")
