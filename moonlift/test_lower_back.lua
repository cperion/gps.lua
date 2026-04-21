package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Lower = require("moonlift.lower_sem_to_back")

local T = pvm.context()
A.Define(T)
local L = Lower.Define(T)

local Sem = T.MoonliftSem
local Back = T.MoonliftBack

local function one_expr(node, path, layout_env)
    return pvm.one(L.lower_expr(node, path, layout_env))
end

local function one_stmt(node, path, layout_env)
    return pvm.one(L.lower_stmt(node, path, layout_env))
end

local function one_expr_in_loop(node, path, layout_env)
    return pvm.one(L.lower_expr(
        node,
        path,
        layout_env,
        Back.BackBlockId(path .. ".loop_break"),
        {},
        Back.BackBlockId(path .. ".loop_continue"),
        {}
    ))
end

local function one_stmt_in_loop(node, path, layout_env)
    return pvm.one(L.lower_stmt(
        node,
        path,
        layout_env,
        Back.BackBlockId(path .. ".loop_break"),
        {},
        Back.BackBlockId(path .. ".loop_continue"),
        {}
    ))
end

local function one_module(node, layout_env)
    return pvm.one(L.lower_module(node, layout_env))
end

local function contains_cmd(plan, cmd)
    for i = 1, #plan.cmds do
        if plan.cmds[i] == cmd then
            return true
        end
    end
    return false
end

assert(pvm.one(L.lower_scalar(Sem.SemTI32)) == Back.BackI32)
assert(pvm.one(L.lower_scalar(Sem.SemTIndex)) == Back.BackIndex)
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

local rotl_expr = one_expr(
    Sem.SemExprIntrinsicCall(
        Sem.SemRotl,
        Sem.SemTU32,
        {
            Sem.SemExprConstInt(Sem.SemTU32, "1"),
            Sem.SemExprConstInt(Sem.SemTU32, "4"),
        }
    ),
    "expr.rotl"
)
assert(rotl_expr == Back.BackExprPlan({
    Back.BackCmdConstInt(Back.BackValId("expr.rotl.arg.1"), Back.BackU32, "1"),
    Back.BackCmdConstInt(Back.BackValId("expr.rotl.arg.2"), Back.BackU32, "4"),
    Back.BackCmdRotl(Back.BackValId("expr.rotl"), Back.BackU32, Back.BackValId("expr.rotl.arg.1"), Back.BackValId("expr.rotl.arg.2")),
}, Back.BackValId("expr.rotl"), Back.BackU32))

local fma_expr = one_expr(
    Sem.SemExprIntrinsicCall(
        Sem.SemFma,
        Sem.SemTF32,
        {
            Sem.SemExprConstFloat(Sem.SemTF32, "2"),
            Sem.SemExprConstFloat(Sem.SemTF32, "3"),
            Sem.SemExprConstFloat(Sem.SemTF32, "4"),
        }
    ),
    "expr.fma"
)
assert(fma_expr == Back.BackExprPlan({
    Back.BackCmdConstFloat(Back.BackValId("expr.fma.arg.1"), Back.BackF32, "2"),
    Back.BackCmdConstFloat(Back.BackValId("expr.fma.arg.2"), Back.BackF32, "3"),
    Back.BackCmdConstFloat(Back.BackValId("expr.fma.arg.3"), Back.BackF32, "4"),
    Back.BackCmdFma(Back.BackValId("expr.fma"), Back.BackF32, Back.BackValId("expr.fma.arg.1"), Back.BackValId("expr.fma.arg.2"), Back.BackValId("expr.fma.arg.3")),
}, Back.BackValId("expr.fma"), Back.BackF32))

local bounded_over_expr = one_expr(
    Sem.SemExprLoop(
        Sem.SemLoopOverExpr(
            Sem.SemBindLocalStoredValue("bounded.i", "i", Sem.SemTIndex),
            Sem.SemDomainBoundedValue(
                Sem.SemExprBinding(Sem.SemBindLocalStoredValue("bounded.arr", "arr", Sem.SemTArray(Sem.SemTI32, 4)))
            ),
            {
                Sem.SemLoopBinding("bounded.acc", "acc", Sem.SemTIndex, Sem.SemExprConstInt(Sem.SemTIndex, "0")),
            },
            {},
            {
                Sem.SemLoopNext(
                    Sem.SemBindLocalStoredValue("bounded.acc", "acc", Sem.SemTIndex),
                    Sem.SemExprAdd(
                        Sem.SemTIndex,
                        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("bounded.acc", "acc", Sem.SemTIndex)),
                        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("bounded.i", "i", Sem.SemTIndex))
                    )
                ),
            },
            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("bounded.acc", "acc", Sem.SemTIndex))
        ),
        Sem.SemTIndex
    ),
    "expr.bound"
)
assert(contains_cmd(bounded_over_expr, Back.BackCmdStackAddr(Back.BackValId("expr.bound.bounded"), Back.BackStackSlotId("slot:local:bounded.arr"))))
assert(contains_cmd(bounded_over_expr, Back.BackCmdConstInt(Back.BackValId("expr.bound.stop"), Back.BackIndex, "4")))

local zip_eq_over_expr = one_expr(
    Sem.SemExprLoop(
        Sem.SemLoopOverExpr(
            Sem.SemBindLocalStoredValue("zip.i", "i", Sem.SemTIndex),
            Sem.SemDomainZipEq({
                Sem.SemExprBinding(Sem.SemBindLocalStoredValue("zip.a", "a", Sem.SemTArray(Sem.SemTI32, 3))),
                Sem.SemExprBinding(Sem.SemBindLocalStoredValue("zip.b", "b", Sem.SemTArray(Sem.SemTI32, 3))),
            }),
            {
                Sem.SemLoopBinding("zip.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
            },
            {},
            {
                Sem.SemLoopNext(
                    Sem.SemBindLocalStoredValue("zip.acc", "acc", Sem.SemTI32),
                    Sem.SemExprAdd(
                        Sem.SemTI32,
                        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("zip.acc", "acc", Sem.SemTI32)),
                        Sem.SemExprConstInt(Sem.SemTI32, "1")
                    )
                ),
            },
            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("zip.acc", "acc", Sem.SemTI32))
        ),
        Sem.SemTI32
    ),
    "expr.zip"
)
assert(contains_cmd(zip_eq_over_expr, Back.BackCmdStackAddr(Back.BackValId("expr.zip.zip.1"), Back.BackStackSlotId("slot:local:zip.a"))))
assert(contains_cmd(zip_eq_over_expr, Back.BackCmdStackAddr(Back.BackValId("expr.zip.zip.2"), Back.BackStackSlotId("slot:local:zip.b"))))
assert(contains_cmd(zip_eq_over_expr, Back.BackCmdConstInt(Back.BackValId("expr.zip.stop"), Back.BackIndex, "3")))

local assume_stmt = one_stmt(
    Sem.SemStmtExpr(Sem.SemExprIntrinsicCall(
        Sem.SemAssume,
        Sem.SemTVoid,
        { Sem.SemExprBinding(Sem.SemBindArg(0, "ok", Sem.SemTBool)) }
    )),
    "stmt.assume"
)
assert(assume_stmt == Back.BackStmtPlan({
    Back.BackCmdCreateBlock(Back.BackBlockId("stmt.assume.expr.ok.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("stmt.assume.expr.fail.block")),
    Back.BackCmdBrIf(Back.BackValId("arg:0:ok"), Back.BackBlockId("stmt.assume.expr.ok.block"), {}, Back.BackBlockId("stmt.assume.expr.fail.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("stmt.assume.expr.ok.block")),
    Back.BackCmdSealBlock(Back.BackBlockId("stmt.assume.expr.fail.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("stmt.assume.expr.fail.block")),
    Back.BackCmdTrap,
    Back.BackCmdSwitchToBlock(Back.BackBlockId("stmt.assume.expr.ok.block")),
}, Back.BackFallsThrough))

local trap_stmt = one_stmt(
    Sem.SemStmtExpr(Sem.SemExprIntrinsicCall(Sem.SemTrap, Sem.SemTVoid, {})),
    "stmt.trap"
)
assert(trap_stmt == Back.BackStmtPlan({ Back.BackCmdTrap }, Back.BackTerminates))

local ref_cell = one_expr(
    Sem.SemExprRef(
        Sem.SemTPtrTo(Sem.SemTI32),
        Sem.SemExprBinding(Sem.SemBindLocalCell("cx", "x", Sem.SemTI32))
    ),
    "expr.ref"
)
assert(ref_cell == Back.BackExprPlan({
    Back.BackCmdStackAddr(Back.BackValId("expr.ref"), Back.BackStackSlotId("slot:cx")),
}, Back.BackValId("expr.ref"), Back.BackPtr))

local ref_stored = one_expr(
    Sem.SemExprRef(
        Sem.SemTPtrTo(Sem.SemTI32),
        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("ls", "s", Sem.SemTI32))
    ),
    "expr.refstored"
)
assert(ref_stored == Back.BackExprPlan({
    Back.BackCmdStackAddr(Back.BackValId("expr.refstored"), Back.BackStackSlotId("slot:local:ls")),
}, Back.BackValId("expr.refstored"), Back.BackPtr))

local ref_arg = one_expr(
    Sem.SemExprRef(
        Sem.SemTPtrTo(Sem.SemTI32),
        Sem.SemExprBinding(Sem.SemBindArg(0, "x", Sem.SemTI32))
    ),
    "expr.refarg"
)
assert(ref_arg == Back.BackExprPlan({
    Back.BackCmdStackAddr(Back.BackValId("expr.refarg"), Back.BackStackSlotId("slot:arg:0:x")),
}, Back.BackValId("expr.refarg"), Back.BackPtr))

local ref_global = one_expr(
    Sem.SemExprRef(
        Sem.SemTPtrTo(Sem.SemTI32),
        Sem.SemExprBinding(Sem.SemBindGlobal("", "K", Sem.SemTI32))
    ),
    "expr.refglobal"
)
assert(ref_global == Back.BackExprPlan({
    Back.BackCmdDataAddr(Back.BackValId("expr.refglobal"), Back.BackDataId("data:const:K")),
}, Back.BackValId("expr.refglobal"), Back.BackPtr))

local deref_ptr = one_expr(
    Sem.SemExprDeref(
        Sem.SemTI32,
        Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTI32)))
    ),
    "expr.deref"
)
assert(deref_ptr == Back.BackExprPlan({
    Back.BackCmdLoad(Back.BackValId("expr.deref"), Back.BackI32, Back.BackValId("arg:0:p")),
}, Back.BackValId("expr.deref"), Back.BackI32))

local index_addr = one_expr(
    Sem.SemExprIndexAddr(
        Sem.SemIndexBasePtr(
            Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTI32))),
            Sem.SemTI32
        ),
        Sem.SemExprConstInt(Sem.SemTIndex, "3"),
        4
    ),
    "expr.indexaddr"
)
assert(index_addr == Back.BackExprPlan({
    Back.BackCmdConstInt(Back.BackValId("expr.indexaddr.index"), Back.BackIndex, "3"),
    Back.BackCmdConstInt(Back.BackValId("expr.indexaddr.elem_size"), Back.BackIndex, "4"),
    Back.BackCmdImul(Back.BackValId("expr.indexaddr.scaled_index"), Back.BackIndex, Back.BackValId("expr.indexaddr.index"), Back.BackValId("expr.indexaddr.elem_size")),
    Back.BackCmdIadd(Back.BackValId("expr.indexaddr"), Back.BackPtr, Back.BackValId("arg:0:p"), Back.BackValId("expr.indexaddr.scaled_index")),
}, Back.BackValId("expr.indexaddr"), Back.BackPtr))

local index_value = one_expr(
    Sem.SemExprIndex(
        Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTI32))),
        Sem.SemExprConstInt(Sem.SemTIndex, "2"),
        Sem.SemTI32
    ),
    "expr.index"
)
assert(index_value == Back.BackExprPlan({
    Back.BackCmdConstInt(Back.BackValId("expr.index.addr.index"), Back.BackIndex, "2"),
    Back.BackCmdConstInt(Back.BackValId("expr.index.addr.elem_size"), Back.BackIndex, "4"),
    Back.BackCmdImul(Back.BackValId("expr.index.addr.scaled_index"), Back.BackIndex, Back.BackValId("expr.index.addr.index"), Back.BackValId("expr.index.addr.elem_size")),
    Back.BackCmdIadd(Back.BackValId("expr.index.addr"), Back.BackPtr, Back.BackValId("arg:0:p"), Back.BackValId("expr.index.addr.scaled_index")),
    Back.BackCmdLoad(Back.BackValId("expr.index"), Back.BackI32, Back.BackValId("expr.index.addr")),
}, Back.BackValId("expr.index"), Back.BackI32))

local pair_layout_env = Sem.SemLayoutEnv({
    Sem.SemLayoutNamed("Demo", "Pair", {
        Sem.SemFieldLayout("left", 0, Sem.SemTI32),
        Sem.SemFieldLayout("right", 4, Sem.SemTI32),
    }, 8, 4),
})

local agg_let = one_stmt(
    Sem.SemStmtLet(
        "lp",
        "p",
        Sem.SemTNamed("Demo", "Pair"),
        Sem.SemExprAgg(Sem.SemTNamed("Demo", "Pair"), {
            Sem.SemFieldInit("left", Sem.SemExprConstInt(Sem.SemTI32, "10")),
            Sem.SemFieldInit("right", Sem.SemExprConstInt(Sem.SemTI32, "32")),
        })
    ),
    "stmt.agg_let",
    pair_layout_env
)
assert(agg_let == Back.BackStmtPlan({
    Back.BackCmdCreateStackSlot(Back.BackStackSlotId("slot:local:lp"), 8, 4),
    Back.BackCmdStackAddr(Back.BackValId("stmt.agg_let.addr"), Back.BackStackSlotId("slot:local:lp")),
    Back.BackCmdAlias(Back.BackValId("stmt.agg_let.init_store.field.left"), Back.BackValId("stmt.agg_let.addr")),
    Back.BackCmdConstInt(Back.BackValId("stmt.agg_let.init_store.field_init.left.value"), Back.BackI32, "10"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("stmt.agg_let.init_store.field.left"), Back.BackValId("stmt.agg_let.init_store.field_init.left.value")),
    Back.BackCmdConstInt(Back.BackValId("stmt.agg_let.init_store.field.right.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("stmt.agg_let.init_store.field.right"), Back.BackPtr, Back.BackValId("stmt.agg_let.addr"), Back.BackValId("stmt.agg_let.init_store.field.right.offset")),
    Back.BackCmdConstInt(Back.BackValId("stmt.agg_let.init_store.field_init.right.value"), Back.BackI32, "32"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("stmt.agg_let.init_store.field.right"), Back.BackValId("stmt.agg_let.init_store.field_init.right.value")),
}, Back.BackFallsThrough))

local local_field_value = one_expr(
    Sem.SemExprField(
        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("lp", "p", Sem.SemTNamed("Demo", "Pair"))),
        Sem.SemFieldByOffset("right", 4, Sem.SemTI32)
    ),
    "expr.localfield",
    pair_layout_env
)
assert(local_field_value == Back.BackExprPlan({
    Back.BackCmdStackAddr(Back.BackValId("expr.localfield.addr.base"), Back.BackStackSlotId("slot:local:lp")),
    Back.BackCmdConstInt(Back.BackValId("expr.localfield.addr.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("expr.localfield.addr"), Back.BackPtr, Back.BackValId("expr.localfield.addr.base"), Back.BackValId("expr.localfield.addr.offset")),
    Back.BackCmdLoad(Back.BackValId("expr.localfield"), Back.BackI32, Back.BackValId("expr.localfield.addr")),
}, Back.BackValId("expr.localfield"), Back.BackI32))

local block_field_value = one_expr(
    Sem.SemExprField(
        Sem.SemExprBlock(
            {},
            Sem.SemExprAgg(Sem.SemTNamed("Demo", "Pair"), {
                Sem.SemFieldInit("left", Sem.SemExprConstInt(Sem.SemTI32, "1")),
                Sem.SemFieldInit("right", Sem.SemExprConstInt(Sem.SemTI32, "7")),
            }),
            Sem.SemTNamed("Demo", "Pair")
        ),
        Sem.SemFieldByOffset("right", 4, Sem.SemTI32)
    ),
    "expr.blockfield",
    pair_layout_env
)
assert(block_field_value == Back.BackExprPlan({
    Back.BackCmdCreateStackSlot(Back.BackStackSlotId("expr.blockfield.addr.base.slot"), 8, 4),
    Back.BackCmdStackAddr(Back.BackValId("expr.blockfield.addr.base"), Back.BackStackSlotId("expr.blockfield.addr.base.slot")),
    Back.BackCmdAlias(Back.BackValId("expr.blockfield.addr.base.init.result.field.left"), Back.BackValId("expr.blockfield.addr.base")),
    Back.BackCmdConstInt(Back.BackValId("expr.blockfield.addr.base.init.result.field_init.left.value"), Back.BackI32, "1"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("expr.blockfield.addr.base.init.result.field.left"), Back.BackValId("expr.blockfield.addr.base.init.result.field_init.left.value")),
    Back.BackCmdConstInt(Back.BackValId("expr.blockfield.addr.base.init.result.field.right.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("expr.blockfield.addr.base.init.result.field.right"), Back.BackPtr, Back.BackValId("expr.blockfield.addr.base"), Back.BackValId("expr.blockfield.addr.base.init.result.field.right.offset")),
    Back.BackCmdConstInt(Back.BackValId("expr.blockfield.addr.base.init.result.field_init.right.value"), Back.BackI32, "7"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("expr.blockfield.addr.base.init.result.field.right"), Back.BackValId("expr.blockfield.addr.base.init.result.field_init.right.value")),
    Back.BackCmdConstInt(Back.BackValId("expr.blockfield.addr.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("expr.blockfield.addr"), Back.BackPtr, Back.BackValId("expr.blockfield.addr.base"), Back.BackValId("expr.blockfield.addr.offset")),
    Back.BackCmdLoad(Back.BackValId("expr.blockfield"), Back.BackI32, Back.BackValId("expr.blockfield.addr")),
}, Back.BackValId("expr.blockfield"), Back.BackI32))

local if_field_value = one_expr(
    Sem.SemExprField(
        Sem.SemExprIf(
            Sem.SemExprConstBool(true),
            Sem.SemExprAgg(Sem.SemTNamed("Demo", "Pair"), {
                Sem.SemFieldInit("left", Sem.SemExprConstInt(Sem.SemTI32, "2")),
                Sem.SemFieldInit("right", Sem.SemExprConstInt(Sem.SemTI32, "9")),
            }),
            Sem.SemExprAgg(Sem.SemTNamed("Demo", "Pair"), {
                Sem.SemFieldInit("left", Sem.SemExprConstInt(Sem.SemTI32, "3")),
                Sem.SemFieldInit("right", Sem.SemExprConstInt(Sem.SemTI32, "11")),
            }),
            Sem.SemTNamed("Demo", "Pair")
        ),
        Sem.SemFieldByOffset("right", 4, Sem.SemTI32)
    ),
    "expr.iffield",
    pair_layout_env
)
assert(if_field_value == Back.BackExprPlan({
    Back.BackCmdCreateStackSlot(Back.BackStackSlotId("expr.iffield.addr.base.slot"), 8, 4),
    Back.BackCmdStackAddr(Back.BackValId("expr.iffield.addr.base"), Back.BackStackSlotId("expr.iffield.addr.base.slot")),
    Back.BackCmdConstBool(Back.BackValId("expr.iffield.addr.base.init.cond"), true),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.iffield.addr.base.init.then.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.iffield.addr.base.init.else.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.iffield.addr.base.init.join.block")),
    Back.BackCmdBrIf(Back.BackValId("expr.iffield.addr.base.init.cond"), Back.BackBlockId("expr.iffield.addr.base.init.then.block"), {}, Back.BackBlockId("expr.iffield.addr.base.init.else.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.iffield.addr.base.init.then.block")),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.iffield.addr.base.init.else.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.iffield.addr.base.init.then.block")),
    Back.BackCmdAlias(Back.BackValId("expr.iffield.addr.base.init.then.field.left"), Back.BackValId("expr.iffield.addr.base")),
    Back.BackCmdConstInt(Back.BackValId("expr.iffield.addr.base.init.then.field_init.left.value"), Back.BackI32, "2"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("expr.iffield.addr.base.init.then.field.left"), Back.BackValId("expr.iffield.addr.base.init.then.field_init.left.value")),
    Back.BackCmdConstInt(Back.BackValId("expr.iffield.addr.base.init.then.field.right.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("expr.iffield.addr.base.init.then.field.right"), Back.BackPtr, Back.BackValId("expr.iffield.addr.base"), Back.BackValId("expr.iffield.addr.base.init.then.field.right.offset")),
    Back.BackCmdConstInt(Back.BackValId("expr.iffield.addr.base.init.then.field_init.right.value"), Back.BackI32, "9"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("expr.iffield.addr.base.init.then.field.right"), Back.BackValId("expr.iffield.addr.base.init.then.field_init.right.value")),
    Back.BackCmdJump(Back.BackBlockId("expr.iffield.addr.base.init.join.block"), {}),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.iffield.addr.base.init.else.block")),
    Back.BackCmdAlias(Back.BackValId("expr.iffield.addr.base.init.else.field.left"), Back.BackValId("expr.iffield.addr.base")),
    Back.BackCmdConstInt(Back.BackValId("expr.iffield.addr.base.init.else.field_init.left.value"), Back.BackI32, "3"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("expr.iffield.addr.base.init.else.field.left"), Back.BackValId("expr.iffield.addr.base.init.else.field_init.left.value")),
    Back.BackCmdConstInt(Back.BackValId("expr.iffield.addr.base.init.else.field.right.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("expr.iffield.addr.base.init.else.field.right"), Back.BackPtr, Back.BackValId("expr.iffield.addr.base"), Back.BackValId("expr.iffield.addr.base.init.else.field.right.offset")),
    Back.BackCmdConstInt(Back.BackValId("expr.iffield.addr.base.init.else.field_init.right.value"), Back.BackI32, "11"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("expr.iffield.addr.base.init.else.field.right"), Back.BackValId("expr.iffield.addr.base.init.else.field_init.right.value")),
    Back.BackCmdJump(Back.BackBlockId("expr.iffield.addr.base.init.join.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.iffield.addr.base.init.join.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.iffield.addr.base.init.join.block")),
    Back.BackCmdConstInt(Back.BackValId("expr.iffield.addr.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("expr.iffield.addr"), Back.BackPtr, Back.BackValId("expr.iffield.addr.base"), Back.BackValId("expr.iffield.addr.offset")),
    Back.BackCmdLoad(Back.BackValId("expr.iffield"), Back.BackI32, Back.BackValId("expr.iffield.addr")),
}, Back.BackValId("expr.iffield"), Back.BackI32))

local switch_field_value = one_expr(
    Sem.SemExprField(
        Sem.SemExprSwitch(
            Sem.SemExprBinding(Sem.SemBindArg(0, "x", Sem.SemTI32)),
            {
                Sem.SemSwitchExprArm(
                    Sem.SemExprConstInt(Sem.SemTI32, "1"),
                    { Sem.SemStmtExpr(Sem.SemExprConstInt(Sem.SemTI32, "5")) },
                    Sem.SemExprAgg(Sem.SemTNamed("Demo", "Pair"), {
                        Sem.SemFieldInit("left", Sem.SemExprConstInt(Sem.SemTI32, "2")),
                        Sem.SemFieldInit("right", Sem.SemExprConstInt(Sem.SemTI32, "9")),
                    })
                ),
            },
            Sem.SemExprAgg(Sem.SemTNamed("Demo", "Pair"), {
                Sem.SemFieldInit("left", Sem.SemExprConstInt(Sem.SemTI32, "3")),
                Sem.SemFieldInit("right", Sem.SemExprConstInt(Sem.SemTI32, "11")),
            }),
            Sem.SemTNamed("Demo", "Pair")
        ),
        Sem.SemFieldByOffset("right", 4, Sem.SemTI32)
    ),
    "expr.switchfield",
    pair_layout_env
)
assert(switch_field_value == Back.BackExprPlan({
    Back.BackCmdCreateStackSlot(Back.BackStackSlotId("expr.switchfield.addr.base.slot"), 8, 4),
    Back.BackCmdStackAddr(Back.BackValId("expr.switchfield.addr.base"), Back.BackStackSlotId("expr.switchfield.addr.base.slot")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.switchfield.addr.base.init.arm.1.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.switchfield.addr.base.init.default.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.switchfield.addr.base.init.join.block")),
    Back.BackCmdConstInt(Back.BackValId("expr.switchfield.addr.base.init.arm.1.key"), Back.BackI32, "1"),
    Back.BackCmdIcmpEq(Back.BackValId("expr.switchfield.addr.base.init.arm.1.match"), Back.BackBool, Back.BackValId("arg:0:x"), Back.BackValId("expr.switchfield.addr.base.init.arm.1.key")),
    Back.BackCmdBrIf(Back.BackValId("expr.switchfield.addr.base.init.arm.1.match"), Back.BackBlockId("expr.switchfield.addr.base.init.arm.1.block"), {}, Back.BackBlockId("expr.switchfield.addr.base.init.default.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.switchfield.addr.base.init.arm.1.block")),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.switchfield.addr.base.init.default.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.switchfield.addr.base.init.arm.1.block")),
    Back.BackCmdConstInt(Back.BackValId("expr.switchfield.addr.base.init.arm.1.stmt.1.expr"), Back.BackI32, "5"),
    Back.BackCmdAlias(Back.BackValId("expr.switchfield.addr.base.init.arm.1.result.field.left"), Back.BackValId("expr.switchfield.addr.base")),
    Back.BackCmdConstInt(Back.BackValId("expr.switchfield.addr.base.init.arm.1.result.field_init.left.value"), Back.BackI32, "2"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("expr.switchfield.addr.base.init.arm.1.result.field.left"), Back.BackValId("expr.switchfield.addr.base.init.arm.1.result.field_init.left.value")),
    Back.BackCmdConstInt(Back.BackValId("expr.switchfield.addr.base.init.arm.1.result.field.right.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("expr.switchfield.addr.base.init.arm.1.result.field.right"), Back.BackPtr, Back.BackValId("expr.switchfield.addr.base"), Back.BackValId("expr.switchfield.addr.base.init.arm.1.result.field.right.offset")),
    Back.BackCmdConstInt(Back.BackValId("expr.switchfield.addr.base.init.arm.1.result.field_init.right.value"), Back.BackI32, "9"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("expr.switchfield.addr.base.init.arm.1.result.field.right"), Back.BackValId("expr.switchfield.addr.base.init.arm.1.result.field_init.right.value")),
    Back.BackCmdJump(Back.BackBlockId("expr.switchfield.addr.base.init.join.block"), {}),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.switchfield.addr.base.init.default.block")),
    Back.BackCmdAlias(Back.BackValId("expr.switchfield.addr.base.init.default.field.left"), Back.BackValId("expr.switchfield.addr.base")),
    Back.BackCmdConstInt(Back.BackValId("expr.switchfield.addr.base.init.default.field_init.left.value"), Back.BackI32, "3"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("expr.switchfield.addr.base.init.default.field.left"), Back.BackValId("expr.switchfield.addr.base.init.default.field_init.left.value")),
    Back.BackCmdConstInt(Back.BackValId("expr.switchfield.addr.base.init.default.field.right.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("expr.switchfield.addr.base.init.default.field.right"), Back.BackPtr, Back.BackValId("expr.switchfield.addr.base"), Back.BackValId("expr.switchfield.addr.base.init.default.field.right.offset")),
    Back.BackCmdConstInt(Back.BackValId("expr.switchfield.addr.base.init.default.field_init.right.value"), Back.BackI32, "11"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("expr.switchfield.addr.base.init.default.field.right"), Back.BackValId("expr.switchfield.addr.base.init.default.field_init.right.value")),
    Back.BackCmdJump(Back.BackBlockId("expr.switchfield.addr.base.init.join.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.switchfield.addr.base.init.join.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.switchfield.addr.base.init.join.block")),
    Back.BackCmdConstInt(Back.BackValId("expr.switchfield.addr.offset"), Back.BackIndex, "4"),
    Back.BackCmdIadd(Back.BackValId("expr.switchfield.addr"), Back.BackPtr, Back.BackValId("expr.switchfield.addr.base"), Back.BackValId("expr.switchfield.addr.offset")),
    Back.BackCmdLoad(Back.BackValId("expr.switchfield"), Back.BackI32, Back.BackValId("expr.switchfield.addr")),
}, Back.BackValId("expr.switchfield"), Back.BackI32))

local loop_field_value = one_expr(
    Sem.SemExprField(
        Sem.SemExprLoop(
            Sem.SemLoopWhileExpr(
                { Sem.SemLoopBinding("li", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")) },
                Sem.SemExprConstBool(false),
                {},
                { Sem.SemLoopNext(Sem.SemBindLocalStoredValue("li", "i", Sem.SemTI32), Sem.SemExprAdd(Sem.SemTI32, Sem.SemExprBinding(Sem.SemBindLocalStoredValue("li", "i", Sem.SemTI32)), Sem.SemExprConstInt(Sem.SemTI32, "1"))) },
                Sem.SemExprAgg(Sem.SemTNamed("Demo", "Pair"), {
                    Sem.SemFieldInit("left", Sem.SemExprBinding(Sem.SemBindLocalStoredValue("li", "i", Sem.SemTI32))),
                    Sem.SemFieldInit("right", Sem.SemExprConstInt(Sem.SemTI32, "7")),
                })
            ),
            Sem.SemTNamed("Demo", "Pair")
        ),
        Sem.SemFieldByOffset("right", 4, Sem.SemTI32)
    ),
    "expr.loopfield",
    pair_layout_env
)
assert(loop_field_value.value == Back.BackValId("expr.loopfield"))
assert(loop_field_value.ty == Back.BackI32)
assert(contains_cmd(loop_field_value, Back.BackCmdCreateBlock(Back.BackBlockId("expr.loopfield.addr.base.init.loop.continue.block"))))
assert(contains_cmd(loop_field_value, Back.BackCmdJump(Back.BackBlockId("expr.loopfield.addr.base.init.loop.continue.block"), { Back.BackValId("local:li") })))
assert(contains_cmd(loop_field_value, Back.BackCmdAlias(Back.BackValId("local:li"), Back.BackValId("expr.loopfield.addr.base.init.loop.exit.param.1"))))
assert(contains_cmd(loop_field_value, Back.BackCmdLoad(Back.BackValId("expr.loopfield"), Back.BackI32, Back.BackValId("expr.loopfield.addr"))))

local field_value = one_expr(
    Sem.SemExprField(
        Sem.SemExprDeref(
            Sem.SemTI32,
            Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTI32)))
        ),
        Sem.SemFieldByOffset("field", 8, Sem.SemTI32)
    ),
    "expr.field"
)
assert(field_value == Back.BackExprPlan({
    Back.BackCmdConstInt(Back.BackValId("expr.field.addr.offset"), Back.BackIndex, "8"),
    Back.BackCmdIadd(Back.BackValId("expr.field.addr"), Back.BackPtr, Back.BackValId("arg:0:p"), Back.BackValId("expr.field.addr.offset")),
    Back.BackCmdLoad(Back.BackValId("expr.field"), Back.BackI32, Back.BackValId("expr.field.addr")),
}, Back.BackValId("expr.field"), Back.BackI32))

local field_addr = one_expr(
    Sem.SemExprFieldAddr(
        Sem.SemExprDeref(
            Sem.SemTI32,
            Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTI32)))
        ),
        Sem.SemFieldByOffset("field", 8, Sem.SemTI32)
    ),
    "expr.fieldaddr"
)
assert(field_addr == Back.BackExprPlan({
    Back.BackCmdConstInt(Back.BackValId("expr.fieldaddr.offset"), Back.BackIndex, "8"),
    Back.BackCmdIadd(Back.BackValId("expr.fieldaddr"), Back.BackPtr, Back.BackValId("arg:0:p"), Back.BackValId("expr.fieldaddr.offset")),
}, Back.BackValId("expr.fieldaddr"), Back.BackPtr))

local lt = one_expr(
    Sem.SemExprLt(
        Sem.SemTBool,
        Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTI32)),
        Sem.SemExprConstInt(Sem.SemTI32, "4")
    ),
    "expr.lt"
)
assert(lt == Back.BackExprPlan({
    Back.BackCmdConstInt(Back.BackValId("expr.lt.rhs"), Back.BackI32, "4"),
    Back.BackCmdSIcmpLt(Back.BackValId("expr.lt"), Back.BackBool, Back.BackValId("arg:0:n"), Back.BackValId("expr.lt.rhs")),
}, Back.BackValId("expr.lt"), Back.BackBool))

local bool_not = one_expr(
    Sem.SemExprNot(Sem.SemTBool, Sem.SemExprConstBool(true)),
    "expr.not"
)
assert(bool_not == Back.BackExprPlan({
    Back.BackCmdConstBool(Back.BackValId("expr.not.value"), true),
    Back.BackCmdBoolNot(Back.BackValId("expr.not"), Back.BackValId("expr.not.value")),
}, Back.BackValId("expr.not"), Back.BackBool))

local bnot = one_expr(
    Sem.SemExprBNot(Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "7")),
    "expr.bnot"
)
assert(bnot == Back.BackExprPlan({
    Back.BackCmdConstInt(Back.BackValId("expr.bnot.value"), Back.BackI32, "7"),
    Back.BackCmdBnot(Back.BackValId("expr.bnot"), Back.BackI32, Back.BackValId("expr.bnot.value")),
}, Back.BackValId("expr.bnot"), Back.BackI32))

local select_expr = one_expr(
    Sem.SemExprSelect(
        Sem.SemExprConstBool(true),
        Sem.SemExprConstInt(Sem.SemTI32, "1"),
        Sem.SemExprConstInt(Sem.SemTI32, "2"),
        Sem.SemTI32
    ),
    "expr.select"
)
assert(select_expr == Back.BackExprPlan({
    Back.BackCmdConstBool(Back.BackValId("expr.select.cond"), true),
    Back.BackCmdConstInt(Back.BackValId("expr.select.then"), Back.BackI32, "1"),
    Back.BackCmdConstInt(Back.BackValId("expr.select.else"), Back.BackI32, "2"),
    Back.BackCmdSelect(Back.BackValId("expr.select"), Back.BackI32, Back.BackValId("expr.select.cond"), Back.BackValId("expr.select.then"), Back.BackValId("expr.select.else")),
}, Back.BackValId("expr.select"), Back.BackI32))

local if_expr = one_expr(
    Sem.SemExprIf(
        Sem.SemExprConstBool(true),
        Sem.SemExprConstInt(Sem.SemTI32, "1"),
        Sem.SemExprConstInt(Sem.SemTI32, "2"),
        Sem.SemTI32
    ),
    "expr.if"
)
assert(if_expr == Back.BackExprPlan({
    Back.BackCmdConstBool(Back.BackValId("expr.if.cond"), true),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.if.then.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.if.else.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.if.join.block")),
    Back.BackCmdAppendBlockParam(Back.BackBlockId("expr.if.join.block"), Back.BackValId("expr.if"), Back.BackI32),
    Back.BackCmdBrIf(Back.BackValId("expr.if.cond"), Back.BackBlockId("expr.if.then.block"), {}, Back.BackBlockId("expr.if.else.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.if.then.block")),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.if.else.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.if.then.block")),
    Back.BackCmdConstInt(Back.BackValId("expr.if.then"), Back.BackI32, "1"),
    Back.BackCmdJump(Back.BackBlockId("expr.if.join.block"), { Back.BackValId("expr.if.then") }),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.if.else.block")),
    Back.BackCmdConstInt(Back.BackValId("expr.if.else"), Back.BackI32, "2"),
    Back.BackCmdJump(Back.BackBlockId("expr.if.join.block"), { Back.BackValId("expr.if.else") }),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.if.join.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.if.join.block")),
}, Back.BackValId("expr.if"), Back.BackI32))

local switch_expr = one_expr(
    Sem.SemExprSwitch(
        Sem.SemExprBinding(Sem.SemBindArg(0, "x", Sem.SemTI32)),
        {
            Sem.SemSwitchExprArm(
                Sem.SemExprConstInt(Sem.SemTI32, "1"),
                { Sem.SemStmtExpr(Sem.SemExprConstInt(Sem.SemTI32, "5")) },
                Sem.SemExprConstInt(Sem.SemTI32, "11")
            ),
        },
        Sem.SemExprConstInt(Sem.SemTI32, "22"),
        Sem.SemTI32
    ),
    "expr.switch"
)
assert(switch_expr == Back.BackExprPlan({
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.switch.arm.1.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.switch.default.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("expr.switch.join.block")),
    Back.BackCmdAppendBlockParam(Back.BackBlockId("expr.switch.join.block"), Back.BackValId("expr.switch"), Back.BackI32),
    Back.BackCmdConstInt(Back.BackValId("expr.switch.arm.1.key"), Back.BackI32, "1"),
    Back.BackCmdIcmpEq(Back.BackValId("expr.switch.arm.1.match"), Back.BackBool, Back.BackValId("arg:0:x"), Back.BackValId("expr.switch.arm.1.key")),
    Back.BackCmdBrIf(Back.BackValId("expr.switch.arm.1.match"), Back.BackBlockId("expr.switch.arm.1.block"), {}, Back.BackBlockId("expr.switch.default.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.switch.arm.1.block")),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.switch.default.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.switch.arm.1.block")),
    Back.BackCmdConstInt(Back.BackValId("expr.switch.arm.1.stmt.1.expr"), Back.BackI32, "5"),
    Back.BackCmdConstInt(Back.BackValId("expr.switch.arm.1.result"), Back.BackI32, "11"),
    Back.BackCmdJump(Back.BackBlockId("expr.switch.join.block"), { Back.BackValId("expr.switch.arm.1.result") }),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.switch.default.block")),
    Back.BackCmdConstInt(Back.BackValId("expr.switch.default"), Back.BackI32, "22"),
    Back.BackCmdJump(Back.BackBlockId("expr.switch.join.block"), { Back.BackValId("expr.switch.default") }),
    Back.BackCmdSealBlock(Back.BackBlockId("expr.switch.join.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("expr.switch.join.block")),
}, Back.BackValId("expr.switch"), Back.BackI32))

local call = one_expr(
    Sem.SemExprCall(
        Sem.SemCallDirect("", "sum", Sem.SemTFunc({ Sem.SemTI32 }, Sem.SemTI32)),
        Sem.SemTI32,
        { Sem.SemExprConstInt(Sem.SemTI32, "7") }
    ),
    "expr.call"
)
assert(call == Back.BackExprPlan({
    Back.BackCmdConstInt(Back.BackValId("expr.call.arg.1"), Back.BackI32, "7"),
    Back.BackCmdCreateSig(Back.BackSigId("sig:sum"), { Back.BackI32 }, { Back.BackI32 }),
    Back.BackCmdDeclareFuncLocal(Back.BackFuncId("sum"), Back.BackSigId("sig:sum")),
    Back.BackCmdCallValueDirect(Back.BackValId("expr.call"), Back.BackI32, Back.BackFuncId("sum"), Back.BackSigId("sig:sum"), { Back.BackValId("expr.call.arg.1") }),
}, Back.BackValId("expr.call"), Back.BackI32))

local let_stmt = one_stmt(
    Sem.SemStmtLet(
        "lx",
        "x",
        Sem.SemTI32,
        Sem.SemExprConstInt(Sem.SemTI32, "3")
    ),
    "stmt.let"
)
assert(let_stmt == Back.BackStmtPlan({
    Back.BackCmdCreateStackSlot(Back.BackStackSlotId("slot:local:lx"), 4, 4),
    Back.BackCmdStackAddr(Back.BackValId("stmt.let.addr"), Back.BackStackSlotId("slot:local:lx")),
    Back.BackCmdConstInt(Back.BackValId("stmt.let.init"), Back.BackI32, "3"),
    Back.BackCmdAlias(Back.BackValId("local:lx"), Back.BackValId("stmt.let.init")),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("stmt.let.addr"), Back.BackValId("stmt.let.init")),
}, Back.BackFallsThrough))

local var_stmt = one_stmt(
    Sem.SemStmtVar(
        "cx",
        "x",
        Sem.SemTI32,
        Sem.SemExprConstInt(Sem.SemTI32, "5")
    ),
    "stmt.var"
)
assert(var_stmt == Back.BackStmtPlan({
    Back.BackCmdCreateStackSlot(Back.BackStackSlotId("slot:cx"), 4, 4),
    Back.BackCmdStackAddr(Back.BackValId("stmt.var.addr"), Back.BackStackSlotId("slot:cx")),
    Back.BackCmdConstInt(Back.BackValId("stmt.var.init"), Back.BackI32, "5"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("stmt.var.addr"), Back.BackValId("stmt.var.init")),
}, Back.BackFallsThrough))

local set_stmt = one_stmt(
    Sem.SemStmtSet(
        Sem.SemBindLocalCell("cx", "x", Sem.SemTI32),
        Sem.SemExprConstInt(Sem.SemTI32, "9")
    ),
    "stmt.set"
)
assert(set_stmt == Back.BackStmtPlan({
    Back.BackCmdStackAddr(Back.BackValId("stmt.set.addr"), Back.BackStackSlotId("slot:cx")),
    Back.BackCmdConstInt(Back.BackValId("stmt.set.value"), Back.BackI32, "9"),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("stmt.set.addr"), Back.BackValId("stmt.set.value")),
}, Back.BackFallsThrough))

local if_stmt = one_stmt(
    Sem.SemStmtIf(
        Sem.SemExprConstBool(true),
        {
            Sem.SemStmtExpr(Sem.SemExprConstInt(Sem.SemTI32, "1")),
        },
        {
            Sem.SemStmtReturnVoid,
        }
    ),
    "stmt.if"
)
assert(if_stmt == Back.BackStmtPlan({
    Back.BackCmdConstBool(Back.BackValId("stmt.if.cond"), true),
    Back.BackCmdCreateBlock(Back.BackBlockId("stmt.if.then.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("stmt.if.else.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("stmt.if.join.block")),
    Back.BackCmdBrIf(Back.BackValId("stmt.if.cond"), Back.BackBlockId("stmt.if.then.block"), {}, Back.BackBlockId("stmt.if.else.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("stmt.if.then.block")),
    Back.BackCmdSealBlock(Back.BackBlockId("stmt.if.else.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("stmt.if.then.block")),
    Back.BackCmdConstInt(Back.BackValId("stmt.if.then.stmt.1.expr"), Back.BackI32, "1"),
    Back.BackCmdJump(Back.BackBlockId("stmt.if.join.block"), {}),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("stmt.if.else.block")),
    Back.BackCmdReturnVoid,
    Back.BackCmdSealBlock(Back.BackBlockId("stmt.if.join.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("stmt.if.join.block")),
}, Back.BackFallsThrough))

local assert_stmt = one_stmt(
    Sem.SemStmtAssert(Sem.SemExprConstBool(true)),
    "stmt.assert"
)
assert(assert_stmt == Back.BackStmtPlan({
    Back.BackCmdConstBool(Back.BackValId("stmt.assert.cond"), true),
    Back.BackCmdCreateBlock(Back.BackBlockId("stmt.assert.ok.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("stmt.assert.fail.block")),
    Back.BackCmdBrIf(Back.BackValId("stmt.assert.cond"), Back.BackBlockId("stmt.assert.ok.block"), {}, Back.BackBlockId("stmt.assert.fail.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("stmt.assert.ok.block")),
    Back.BackCmdSealBlock(Back.BackBlockId("stmt.assert.fail.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("stmt.assert.fail.block")),
    Back.BackCmdTrap,
    Back.BackCmdSwitchToBlock(Back.BackBlockId("stmt.assert.ok.block")),
}, Back.BackFallsThrough))

local switch_stmt = one_stmt(
    Sem.SemStmtSwitch(
        Sem.SemExprBinding(Sem.SemBindArg(0, "x", Sem.SemTI32)),
        {
            Sem.SemSwitchStmtArm(
                Sem.SemExprConstInt(Sem.SemTI32, "1"),
                { Sem.SemStmtExpr(Sem.SemExprConstInt(Sem.SemTI32, "11")) }
            ),
        },
        { Sem.SemStmtExpr(Sem.SemExprConstInt(Sem.SemTI32, "22")) }
    ),
    "stmt.switch"
)
assert(switch_stmt == Back.BackStmtPlan({
    Back.BackCmdCreateBlock(Back.BackBlockId("stmt.switch.arm.1.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("stmt.switch.default.block")),
    Back.BackCmdCreateBlock(Back.BackBlockId("stmt.switch.join.block")),
    Back.BackCmdConstInt(Back.BackValId("stmt.switch.arm.1.key"), Back.BackI32, "1"),
    Back.BackCmdIcmpEq(Back.BackValId("stmt.switch.arm.1.match"), Back.BackBool, Back.BackValId("arg:0:x"), Back.BackValId("stmt.switch.arm.1.key")),
    Back.BackCmdBrIf(Back.BackValId("stmt.switch.arm.1.match"), Back.BackBlockId("stmt.switch.arm.1.block"), {}, Back.BackBlockId("stmt.switch.default.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("stmt.switch.arm.1.block")),
    Back.BackCmdSealBlock(Back.BackBlockId("stmt.switch.default.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("stmt.switch.arm.1.block")),
    Back.BackCmdConstInt(Back.BackValId("stmt.switch.arm.1.stmt.1.expr"), Back.BackI32, "11"),
    Back.BackCmdJump(Back.BackBlockId("stmt.switch.join.block"), {}),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("stmt.switch.default.block")),
    Back.BackCmdConstInt(Back.BackValId("stmt.switch.default.stmt.1.expr"), Back.BackI32, "22"),
    Back.BackCmdJump(Back.BackBlockId("stmt.switch.join.block"), {}),
    Back.BackCmdSealBlock(Back.BackBlockId("stmt.switch.join.block")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("stmt.switch.join.block")),
}, Back.BackFallsThrough))

local loop_stmt = one_stmt(
    Sem.SemStmtLoop(
        Sem.SemLoopWhileStmt(
            {
                Sem.SemLoopBinding("loop.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
            },
            Sem.SemExprLt(
                Sem.SemTBool,
                Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop.i", "i", Sem.SemTI32)),
                Sem.SemExprConstInt(Sem.SemTI32, "4")
            ),
            {
                Sem.SemStmtExpr(Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop.i", "i", Sem.SemTI32))),
            },
            {
                Sem.SemLoopNext(
                    Sem.SemBindLocalStoredValue("loop.i", "i", Sem.SemTI32),
                    Sem.SemExprAdd(
                        Sem.SemTI32,
                        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop.i", "i", Sem.SemTI32)),
                        Sem.SemExprConstInt(Sem.SemTI32, "1")
                    )
                ),
            }
        )
    ),
    "stmt.loop"
)
assert(loop_stmt.flow == Back.BackFallsThrough)
assert(contains_cmd(loop_stmt, Back.BackCmdCreateBlock(Back.BackBlockId("stmt.loop.continue.block"))))
assert(contains_cmd(loop_stmt, Back.BackCmdJump(Back.BackBlockId("stmt.loop.continue.block"), { Back.BackValId("local:loop.i") })))
assert(contains_cmd(loop_stmt, Back.BackCmdAlias(Back.BackValId("local:loop.i"), Back.BackValId("stmt.loop.continue.param.1"))))
assert(contains_cmd(loop_stmt, Back.BackCmdJump(Back.BackBlockId("stmt.loop.header.block"), { Back.BackValId("stmt.loop.next.1") })))

local loop_expr = one_expr(
    Sem.SemExprLoop(
        Sem.SemLoopWhileExpr(
            {
                Sem.SemLoopBinding("loop2.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
            },
            Sem.SemExprLt(
                Sem.SemTBool,
                Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop2.i", "i", Sem.SemTI32)),
                Sem.SemExprConstInt(Sem.SemTI32, "2")
            ),
            {
                Sem.SemStmtExpr(Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop2.i", "i", Sem.SemTI32))),
            },
            {
                Sem.SemLoopNext(
                    Sem.SemBindLocalStoredValue("loop2.i", "i", Sem.SemTI32),
                    Sem.SemExprAdd(
                        Sem.SemTI32,
                        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop2.i", "i", Sem.SemTI32)),
                        Sem.SemExprConstInt(Sem.SemTI32, "1")
                    )
                ),
            },
            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("loop2.i", "i", Sem.SemTI32))
        ),
        Sem.SemTI32
    ),
    "expr.loop"
)
assert(loop_expr.value == Back.BackValId("local:loop2.i"))
assert(loop_expr.ty == Back.BackI32)
assert(contains_cmd(loop_expr, Back.BackCmdCreateBlock(Back.BackBlockId("expr.loop.continue.block"))))
assert(contains_cmd(loop_expr, Back.BackCmdJump(Back.BackBlockId("expr.loop.continue.block"), { Back.BackValId("local:loop2.i") })))
assert(contains_cmd(loop_expr, Back.BackCmdAlias(Back.BackValId("local:loop2.i"), Back.BackValId("expr.loop.exit.param.1"))))

local over_stmt = one_stmt(
    Sem.SemStmtLoop(
        Sem.SemLoopOverStmt(
            Sem.SemBindLocalStoredValue("stmt.over.index", "i", Sem.SemTIndex),
            Sem.SemDomainRange(Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTIndex))),
            {
                Sem.SemLoopBinding("over.acc", "acc", Sem.SemTIndex, Sem.SemExprConstInt(Sem.SemTIndex, "0")),
            },
            {},
            {
                Sem.SemLoopNext(
                    Sem.SemBindLocalStoredValue("over.acc", "acc", Sem.SemTIndex),
                    Sem.SemExprAdd(
                        Sem.SemTIndex,
                        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("over.acc", "acc", Sem.SemTIndex)),
                        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("stmt.over.index", "i", Sem.SemTIndex))
                    )
                ),
            }
        )
    ),
    "stmt.over"
)
assert(over_stmt.flow == Back.BackFallsThrough)
assert(contains_cmd(over_stmt, Back.BackCmdCreateBlock(Back.BackBlockId("stmt.over.continue.block"))))
assert(contains_cmd(over_stmt, Back.BackCmdJump(Back.BackBlockId("stmt.over.continue.block"), { Back.BackValId("local:stmt.over.index"), Back.BackValId("local:over.acc") })))
assert(contains_cmd(over_stmt, Back.BackCmdAlias(Back.BackValId("local:stmt.over.index"), Back.BackValId("stmt.over.continue.index"))))
assert(contains_cmd(over_stmt, Back.BackCmdAlias(Back.BackValId("local:over.acc"), Back.BackValId("stmt.over.continue.carry.1"))))

local over_expr = one_expr(
    Sem.SemExprLoop(
        Sem.SemLoopOverExpr(
            Sem.SemBindLocalStoredValue("expr.over.index", "i", Sem.SemTIndex),
            Sem.SemDomainRange(Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTIndex))),
            {
                Sem.SemLoopBinding("overe.acc", "acc", Sem.SemTIndex, Sem.SemExprConstInt(Sem.SemTIndex, "0")),
            },
            {},
            {
                Sem.SemLoopNext(
                    Sem.SemBindLocalStoredValue("overe.acc", "acc", Sem.SemTIndex),
                    Sem.SemExprAdd(
                        Sem.SemTIndex,
                        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("overe.acc", "acc", Sem.SemTIndex)),
                        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("expr.over.index", "i", Sem.SemTIndex))
                    )
                ),
            },
            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("overe.acc", "acc", Sem.SemTIndex))
        ),
        Sem.SemTIndex
    ),
    "expr.over"
)
assert(over_expr.value == Back.BackValId("local:overe.acc"))
assert(over_expr.ty == Back.BackIndex)
assert(contains_cmd(over_expr, Back.BackCmdCreateBlock(Back.BackBlockId("expr.over.continue.block"))))
assert(contains_cmd(over_expr, Back.BackCmdJump(Back.BackBlockId("expr.over.continue.block"), { Back.BackValId("local:expr.over.index"), Back.BackValId("local:overe.acc") })))
assert(contains_cmd(over_expr, Back.BackCmdAlias(Back.BackValId("local:expr.over.index"), Back.BackValId("expr.over.exit.index"))))
assert(contains_cmd(over_expr, Back.BackCmdAlias(Back.BackValId("local:overe.acc"), Back.BackValId("expr.over.exit.carry.1"))))

local ok_break, err_break = pcall(function()
    return one_stmt(Sem.SemStmtBreak, "stmt.break")
end)
assert(not ok_break)
assert(string.find(err_break, "sem_to_back_stmt: break is only valid inside a loop body", 1, true) ~= nil)

local ok_continue, err_continue = pcall(function()
    return one_stmt(Sem.SemStmtContinue, "stmt.continue")
end)
assert(not ok_continue)
assert(string.find(err_continue, "sem_to_back_stmt: continue is only valid inside a loop body", 1, true) ~= nil)

local break_loop_stmt = one_stmt(
    Sem.SemStmtLoop(
        Sem.SemLoopWhileStmt(
            { Sem.SemLoopBinding("break.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")) },
            Sem.SemExprConstBool(true),
            { Sem.SemStmtBreak },
            { Sem.SemLoopNext(Sem.SemBindLocalStoredValue("break.i", "i", Sem.SemTI32), Sem.SemExprAdd(Sem.SemTI32, Sem.SemExprBinding(Sem.SemBindLocalStoredValue("break.i", "i", Sem.SemTI32)), Sem.SemExprConstInt(Sem.SemTI32, "1"))) }
        )
    ),
    "stmt.break_loop"
)
assert(break_loop_stmt.flow == Back.BackFallsThrough)
assert(contains_cmd(break_loop_stmt, Back.BackCmdJump(Back.BackBlockId("stmt.break_loop.exit.block"), {})))
assert(contains_cmd(break_loop_stmt, Back.BackCmdCreateBlock(Back.BackBlockId("stmt.break_loop.continue.block"))))

local continue_loop_stmt = one_stmt(
    Sem.SemStmtLoop(
        Sem.SemLoopWhileStmt(
            { Sem.SemLoopBinding("continue.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")) },
            Sem.SemExprConstBool(true),
            { Sem.SemStmtContinue },
            { Sem.SemLoopNext(Sem.SemBindLocalStoredValue("continue.i", "i", Sem.SemTI32), Sem.SemExprAdd(Sem.SemTI32, Sem.SemExprBinding(Sem.SemBindLocalStoredValue("continue.i", "i", Sem.SemTI32)), Sem.SemExprConstInt(Sem.SemTI32, "1"))) }
        )
    ),
    "stmt.continue_loop"
)
assert(continue_loop_stmt.flow == Back.BackFallsThrough)
assert(contains_cmd(continue_loop_stmt, Back.BackCmdJump(Back.BackBlockId("stmt.continue_loop.continue.block"), { Back.BackValId("local:continue.i") })))
assert(contains_cmd(continue_loop_stmt, Back.BackCmdAlias(Back.BackValId("local:continue.i"), Back.BackValId("stmt.continue_loop.continue.param.1"))))

local continue_block_expr_loop_stmt = one_stmt(
    Sem.SemStmtLoop(
        Sem.SemLoopWhileStmt(
            { Sem.SemLoopBinding("cb.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")) },
            Sem.SemExprConstBool(true),
            {
                Sem.SemStmtExpr(Sem.SemExprBlock({ Sem.SemStmtContinue }, Sem.SemExprConstInt(Sem.SemTI32, "7"), Sem.SemTI32)),
            },
            { Sem.SemLoopNext(Sem.SemBindLocalStoredValue("cb.i", "i", Sem.SemTI32), Sem.SemExprAdd(Sem.SemTI32, Sem.SemExprBinding(Sem.SemBindLocalStoredValue("cb.i", "i", Sem.SemTI32)), Sem.SemExprConstInt(Sem.SemTI32, "1"))) }
        )
    ),
    "stmt.continue_block_expr_loop"
)
assert(continue_block_expr_loop_stmt.flow == Back.BackFallsThrough)
assert(contains_cmd(continue_block_expr_loop_stmt, Back.BackCmdJump(Back.BackBlockId("stmt.continue_block_expr_loop.continue.block"), { Back.BackValId("local:cb.i") })))

local break_switch_expr_loop_stmt = one_stmt(
    Sem.SemStmtLoop(
        Sem.SemLoopWhileStmt(
            { Sem.SemLoopBinding("sb.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")) },
            Sem.SemExprConstBool(true),
            {
                Sem.SemStmtExpr(Sem.SemExprSwitch(
                    Sem.SemExprConstInt(Sem.SemTI32, "1"),
                    {
                        Sem.SemSwitchExprArm(
                            Sem.SemExprConstInt(Sem.SemTI32, "1"),
                            { Sem.SemStmtBreak },
                            Sem.SemExprConstInt(Sem.SemTI32, "11")
                        ),
                    },
                    Sem.SemExprConstInt(Sem.SemTI32, "22"),
                    Sem.SemTI32
                )),
            },
            { Sem.SemLoopNext(Sem.SemBindLocalStoredValue("sb.i", "i", Sem.SemTI32), Sem.SemExprAdd(Sem.SemTI32, Sem.SemExprBinding(Sem.SemBindLocalStoredValue("sb.i", "i", Sem.SemTI32)), Sem.SemExprConstInt(Sem.SemTI32, "1"))) }
        )
    ),
    "stmt.break_switch_expr_loop"
)
assert(break_switch_expr_loop_stmt.flow == Back.BackFallsThrough)
assert(contains_cmd(break_switch_expr_loop_stmt, Back.BackCmdJump(Back.BackBlockId("stmt.break_switch_expr_loop.exit.block"), {})))

local terminating_block_expr = one_expr_in_loop(
    Sem.SemExprBlock(
        { Sem.SemStmtBreak },
        Sem.SemExprConstInt(Sem.SemTI32, "123"),
        Sem.SemTI32
    ),
    "expr.terminating_block"
)
assert(getmetatable(terminating_block_expr).__class == Back.BackExprTerminated)
assert(contains_cmd(terminating_block_expr, Back.BackCmdJump(Back.BackBlockId("expr.terminating_block.loop_break"), {})))

local add_if_break_expr = one_expr_in_loop(
    Sem.SemExprAdd(
        Sem.SemTI32,
        Sem.SemExprIf(
            Sem.SemExprConstBool(true),
            Sem.SemExprBlock(
                { Sem.SemStmtBreak },
                Sem.SemExprConstInt(Sem.SemTI32, "10"),
                Sem.SemTI32
            ),
            Sem.SemExprConstInt(Sem.SemTI32, "20"),
            Sem.SemTI32
        ),
        Sem.SemExprConstInt(Sem.SemTI32, "1")
    ),
    "expr.add_if_break"
)
assert(getmetatable(add_if_break_expr).__class == Back.BackExprPlan)
assert(contains_cmd(add_if_break_expr, Back.BackCmdJump(Back.BackBlockId("expr.add_if_break.loop_break"), {})))
assert(contains_cmd(add_if_break_expr, Back.BackCmdIadd(
    Back.BackValId("expr.add_if_break"),
    Back.BackI32,
    Back.BackValId("expr.add_if_break.lhs"),
    Back.BackValId("expr.add_if_break.rhs")
)))

local add_switch_break_expr = one_expr_in_loop(
    Sem.SemExprAdd(
        Sem.SemTI32,
        Sem.SemExprSwitch(
            Sem.SemExprConstInt(Sem.SemTI32, "1"),
            {
                Sem.SemSwitchExprArm(
                    Sem.SemExprConstInt(Sem.SemTI32, "1"),
                    { Sem.SemStmtBreak },
                    Sem.SemExprConstInt(Sem.SemTI32, "11")
                ),
            },
            Sem.SemExprConstInt(Sem.SemTI32, "22"),
            Sem.SemTI32
        ),
        Sem.SemExprConstInt(Sem.SemTI32, "3")
    ),
    "expr.add_switch_break"
)
assert(getmetatable(add_switch_break_expr).__class == Back.BackExprPlan)
assert(contains_cmd(add_switch_break_expr, Back.BackCmdJump(Back.BackBlockId("expr.add_switch_break.loop_break"), {})))
assert(contains_cmd(add_switch_break_expr, Back.BackCmdIadd(
    Back.BackValId("expr.add_switch_break"),
    Back.BackI32,
    Back.BackValId("expr.add_switch_break.lhs"),
    Back.BackValId("expr.add_switch_break.rhs")
)))

local terminating_let_in_loop = one_stmt_in_loop(
    Sem.SemStmtLet(
        "term.let",
        "x",
        Sem.SemTI32,
        Sem.SemExprBlock(
            { Sem.SemStmtBreak },
            Sem.SemExprConstInt(Sem.SemTI32, "7"),
            Sem.SemTI32
        )
    ),
    "stmt.terminating_let"
)
assert(terminating_let_in_loop.flow == Back.BackTerminates)
assert(contains_cmd(terminating_let_in_loop, Back.BackCmdJump(Back.BackBlockId("stmt.terminating_let.loop_break"), {})))

local ret = one_stmt(
    Sem.SemStmtReturnValue(
        Sem.SemExprAdd(
            Sem.SemTI32,
            Sem.SemExprBinding(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32)),
            Sem.SemExprConstInt(Sem.SemTI32, "2")
        )
    ),
    "stmt.ret"
)
assert(ret == Back.BackStmtPlan({
    Back.BackCmdConstInt(Back.BackValId("stmt.ret.value.rhs"), Back.BackI32, "2"),
    Back.BackCmdIadd(Back.BackValId("stmt.ret.value"), Back.BackI32, Back.BackValId("local:lx"), Back.BackValId("stmt.ret.value.rhs")),
    Back.BackCmdReturnValue(Back.BackValId("stmt.ret.value")),
}, Back.BackTerminates))

local mod = one_module(Sem.SemModule({
    Sem.SemItemExtern(Sem.SemExternFunc(
        "sinf",
        "sinf",
        { Sem.SemParam("x", Sem.SemTF32) },
        Sem.SemTF32
    )),
    Sem.SemItemFunc(Sem.SemFuncExport(
        "main",
        { Sem.SemParam("x", Sem.SemTI32) },
        Sem.SemTI32,
        {
            Sem.SemStmtLet(
                "main.lx",
                "y",
                Sem.SemTI32,
                Sem.SemExprConstInt(Sem.SemTI32, "1")
            ),
            Sem.SemStmtReturnValue(
                Sem.SemExprAdd(
                    Sem.SemTI32,
                    Sem.SemExprBinding(Sem.SemBindArg(0, "x", Sem.SemTI32)),
                    Sem.SemExprBinding(Sem.SemBindLocalValue("main.lx", "y", Sem.SemTI32))
                )
            ),
        }
    )),
}))
assert(mod == Back.BackProgram({
    Back.BackCmdCreateSig(Back.BackSigId("sig:extern:sinf"), { Back.BackF32 }, { Back.BackF32 }),
    Back.BackCmdDeclareFuncExtern(Back.BackExternId("sinf"), "sinf", Back.BackSigId("sig:extern:sinf")),
    Back.BackCmdCreateSig(Back.BackSigId("sig:main"), { Back.BackI32 }, { Back.BackI32 }),
    Back.BackCmdDeclareFuncExport(Back.BackFuncId("main"), Back.BackSigId("sig:main")),
    Back.BackCmdBeginFunc(Back.BackFuncId("main")),
    Back.BackCmdCreateBlock(Back.BackBlockId("main:entry")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("main:entry")),
    Back.BackCmdBindEntryParams(Back.BackBlockId("main:entry"), { Back.BackValId("arg:0:x") }),
    Back.BackCmdCreateStackSlot(Back.BackStackSlotId("slot:arg:0:x"), 4, 4),
    Back.BackCmdStackAddr(Back.BackValId("arg.addr:0:x"), Back.BackStackSlotId("slot:arg:0:x")),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("arg.addr:0:x"), Back.BackValId("arg:0:x")),
    Back.BackCmdCreateStackSlot(Back.BackStackSlotId("slot:local:main.lx"), 4, 4),
    Back.BackCmdStackAddr(Back.BackValId("func:main.stmt.1.addr"), Back.BackStackSlotId("slot:local:main.lx")),
    Back.BackCmdConstInt(Back.BackValId("func:main.stmt.1.init"), Back.BackI32, "1"),
    Back.BackCmdAlias(Back.BackValId("local:main.lx"), Back.BackValId("func:main.stmt.1.init")),
    Back.BackCmdStore(Back.BackI32, Back.BackValId("func:main.stmt.1.addr"), Back.BackValId("func:main.stmt.1.init")),
    Back.BackCmdIadd(Back.BackValId("func:main.stmt.2.value"), Back.BackI32, Back.BackValId("arg:0:x"), Back.BackValId("local:main.lx")),
    Back.BackCmdReturnValue(Back.BackValId("func:main.stmt.2.value")),
    Back.BackCmdSealBlock(Back.BackBlockId("main:entry")),
    Back.BackCmdFinishFunc(Back.BackFuncId("main")),
    Back.BackCmdFinalizeModule,
}))

local const_module = one_module(Sem.SemModule({
    Sem.SemItemConst(Sem.SemConst("K", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "42"))),
    Sem.SemItemFunc(Sem.SemFuncExport(
        "get_k",
        {},
        Sem.SemTI32,
        {
            Sem.SemStmtReturnValue(Sem.SemExprBinding(Sem.SemBindGlobal("", "K", Sem.SemTI32))),
        }
    )),
}))
assert(const_module == Back.BackProgram({
    Back.BackCmdDeclareData(Back.BackDataId("data:const:K"), 4, 4),
    Back.BackCmdDataInitInt(Back.BackDataId("data:const:K"), 0, Back.BackI32, "42"),
    Back.BackCmdCreateSig(Back.BackSigId("sig:get_k"), {}, { Back.BackI32 }),
    Back.BackCmdDeclareFuncExport(Back.BackFuncId("get_k"), Back.BackSigId("sig:get_k")),
    Back.BackCmdBeginFunc(Back.BackFuncId("get_k")),
    Back.BackCmdCreateBlock(Back.BackBlockId("get_k:entry")),
    Back.BackCmdSwitchToBlock(Back.BackBlockId("get_k:entry")),
    Back.BackCmdDataAddr(Back.BackValId("func:get_k.stmt.1.value.addr"), Back.BackDataId("data:const:K")),
    Back.BackCmdLoad(Back.BackValId("func:get_k.stmt.1.value"), Back.BackI32, Back.BackValId("func:get_k.stmt.1.value.addr")),
    Back.BackCmdReturnValue(Back.BackValId("func:get_k.stmt.1.value")),
    Back.BackCmdSealBlock(Back.BackBlockId("get_k:entry")),
    Back.BackCmdFinishFunc(Back.BackFuncId("get_k")),
    Back.BackCmdFinalizeModule,
}))

local computed_const_module = one_module(Sem.SemModule({
    Sem.SemItemConst(Sem.SemConst(
        "A",
        Sem.SemTI32,
        Sem.SemExprAdd(
            Sem.SemTI32,
            Sem.SemExprConstInt(Sem.SemTI32, "40"),
            Sem.SemExprConstInt(Sem.SemTI32, "2")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "B",
        Sem.SemTBool,
        Sem.SemExprEq(
            Sem.SemTBool,
            Sem.SemExprBinding(Sem.SemBindGlobal("", "A", Sem.SemTI32)),
            Sem.SemExprConstInt(Sem.SemTI32, "42")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "C",
        Sem.SemTI32,
        Sem.SemExprIf(
            Sem.SemExprConstBool(false),
            Sem.SemExprConstInt(Sem.SemTI32, "1"),
            Sem.SemExprBinding(Sem.SemBindGlobal("", "A", Sem.SemTI32)),
            Sem.SemTI32
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "F",
        Sem.SemTF32,
        Sem.SemExprMul(
            Sem.SemTF32,
            Sem.SemExprConstFloat(Sem.SemTF32, "3.5"),
            Sem.SemExprConstFloat(Sem.SemTF32, "2")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "ARR",
        Sem.SemTArray(Sem.SemTI32, 2),
        Sem.SemExprArrayLit(Sem.SemTI32, {
            Sem.SemExprBinding(Sem.SemBindGlobal("", "A", Sem.SemTI32)),
            Sem.SemExprAdd(
                Sem.SemTI32,
                Sem.SemExprBinding(Sem.SemBindGlobal("", "A", Sem.SemTI32)),
                Sem.SemExprConstInt(Sem.SemTI32, "1")
            ),
        })
    )),
    Sem.SemItemConst(Sem.SemConst(
        "P",
        Sem.SemTNamed("Demo", "Pair"),
        Sem.SemExprAgg(Sem.SemTNamed("Demo", "Pair"), {
            Sem.SemFieldInit("left", Sem.SemExprBinding(Sem.SemBindGlobal("", "A", Sem.SemTI32))),
            Sem.SemFieldInit("right", Sem.SemExprConstInt(Sem.SemTI32, "7")),
        })
    )),
    Sem.SemItemConst(Sem.SemConst(
        "RIGHT",
        Sem.SemTI32,
        Sem.SemExprField(
            Sem.SemExprBinding(Sem.SemBindGlobal("", "P", Sem.SemTNamed("Demo", "Pair"))),
            Sem.SemFieldByName("right", Sem.SemTI32)
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "ELEM",
        Sem.SemTI32,
        Sem.SemExprIndex(
            Sem.SemExprBinding(Sem.SemBindGlobal("", "ARR", Sem.SemTArray(Sem.SemTI32, 2))),
            Sem.SemExprConstInt(Sem.SemTIndex, "1"),
            Sem.SemTI32
        )
    )),
}), pair_layout_env)
assert(computed_const_module == Back.BackProgram({
    Back.BackCmdDeclareData(Back.BackDataId("data:const:A"), 4, 4),
    Back.BackCmdDataInitInt(Back.BackDataId("data:const:A"), 0, Back.BackI32, "42"),
    Back.BackCmdDeclareData(Back.BackDataId("data:const:B"), 1, 1),
    Back.BackCmdDataInitBool(Back.BackDataId("data:const:B"), 0, true),
    Back.BackCmdDeclareData(Back.BackDataId("data:const:C"), 4, 4),
    Back.BackCmdDataInitInt(Back.BackDataId("data:const:C"), 0, Back.BackI32, "42"),
    Back.BackCmdDeclareData(Back.BackDataId("data:const:F"), 4, 4),
    Back.BackCmdDataInitFloat(Back.BackDataId("data:const:F"), 0, Back.BackF32, "7"),
    Back.BackCmdDeclareData(Back.BackDataId("data:const:ARR"), 8, 4),
    Back.BackCmdDataInitInt(Back.BackDataId("data:const:ARR"), 0, Back.BackI32, "42"),
    Back.BackCmdDataInitInt(Back.BackDataId("data:const:ARR"), 4, Back.BackI32, "43"),
    Back.BackCmdDeclareData(Back.BackDataId("data:const:P"), 8, 4),
    Back.BackCmdDataInitZero(Back.BackDataId("data:const:P"), 0, 8),
    Back.BackCmdDataInitInt(Back.BackDataId("data:const:P"), 0, Back.BackI32, "42"),
    Back.BackCmdDataInitInt(Back.BackDataId("data:const:P"), 4, Back.BackI32, "7"),
    Back.BackCmdDeclareData(Back.BackDataId("data:const:RIGHT"), 4, 4),
    Back.BackCmdDataInitInt(Back.BackDataId("data:const:RIGHT"), 0, Back.BackI32, "7"),
    Back.BackCmdDeclareData(Back.BackDataId("data:const:ELEM"), 4, 4),
    Back.BackCmdDataInitInt(Back.BackDataId("data:const:ELEM"), 0, Back.BackI32, "43"),
    Back.BackCmdFinalizeModule,
}))

local cast_const_module = one_module(Sem.SemModule({
    Sem.SemItemConst(Sem.SemConst(
        "BAND",
        Sem.SemTI32,
        Sem.SemExprBitAnd(
            Sem.SemTI32,
            Sem.SemExprConstInt(Sem.SemTI32, "6"),
            Sem.SemExprConstInt(Sem.SemTI32, "3")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "BOR",
        Sem.SemTU32,
        Sem.SemExprBitOr(
            Sem.SemTU32,
            Sem.SemExprConstInt(Sem.SemTU32, "10"),
            Sem.SemExprConstInt(Sem.SemTU32, "4")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "BXOR",
        Sem.SemTU32,
        Sem.SemExprBitXor(
            Sem.SemTU32,
            Sem.SemExprConstInt(Sem.SemTU32, "10"),
            Sem.SemExprConstInt(Sem.SemTU32, "12")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "SHL",
        Sem.SemTU8,
        Sem.SemExprShl(
            Sem.SemTU8,
            Sem.SemExprConstInt(Sem.SemTU8, "3"),
            Sem.SemExprConstInt(Sem.SemTU8, "2")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "LSHR",
        Sem.SemTU32,
        Sem.SemExprLShr(
            Sem.SemTU32,
            Sem.SemExprConstInt(Sem.SemTU32, "8"),
            Sem.SemExprConstInt(Sem.SemTU32, "1")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "ASHR",
        Sem.SemTI32,
        Sem.SemExprAShr(
            Sem.SemTI32,
            Sem.SemExprConstInt(Sem.SemTI32, "-8"),
            Sem.SemExprConstInt(Sem.SemTI32, "1")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "CASTI",
        Sem.SemTI32,
        Sem.SemExprCastTo(
            Sem.SemTI32,
            Sem.SemExprConstFloat(Sem.SemTF32, "3.75")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "TRUNC8",
        Sem.SemTU8,
        Sem.SemExprTruncTo(
            Sem.SemTU8,
            Sem.SemExprConstInt(Sem.SemTU32, "258")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "ZEXT32",
        Sem.SemTU32,
        Sem.SemExprZExtTo(
            Sem.SemTU32,
            Sem.SemExprConstInt(Sem.SemTU8, "255")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "SEXT32",
        Sem.SemTI32,
        Sem.SemExprSExtTo(
            Sem.SemTI32,
            Sem.SemExprConstInt(Sem.SemTI8, "-1")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "BITCASTF",
        Sem.SemTF32,
        Sem.SemExprBitcastTo(
            Sem.SemTF32,
            Sem.SemExprConstInt(Sem.SemTU32, "1065353216")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "SATU8",
        Sem.SemTU8,
        Sem.SemExprSatCastTo(
            Sem.SemTU8,
            Sem.SemExprConstFloat(Sem.SemTF32, "300")
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "SATI8",
        Sem.SemTI8,
        Sem.SemExprSatCastTo(
            Sem.SemTI8,
            Sem.SemExprConstFloat(Sem.SemTF32, "-200")
        )
    )),
}))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:BAND"), 0, Back.BackI32, "2")))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:BOR"), 0, Back.BackU32, "14")))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:BXOR"), 0, Back.BackU32, "6")))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:SHL"), 0, Back.BackU8, "12")))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:LSHR"), 0, Back.BackU32, "4")))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:ASHR"), 0, Back.BackI32, "-4")))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:CASTI"), 0, Back.BackI32, "3")))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:TRUNC8"), 0, Back.BackU8, "2")))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:ZEXT32"), 0, Back.BackU32, "255")))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:SEXT32"), 0, Back.BackI32, "-1")))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitFloat(Back.BackDataId("data:const:BITCASTF"), 0, Back.BackF32, "1")))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:SATU8"), 0, Back.BackU8, "255")))
assert(contains_cmd(cast_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:SATI8"), 0, Back.BackI8, "-128")))

local block_switch_const_module = one_module(Sem.SemModule({
    Sem.SemItemConst(Sem.SemConst(
        "BLOCKLET",
        Sem.SemTI32,
        Sem.SemExprBlock({
            Sem.SemStmtLet("blocklet.x", "x", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "40")),
            Sem.SemStmtLet(
                "blocklet.y",
                "y",
                Sem.SemTI32,
                Sem.SemExprAdd(
                    Sem.SemTI32,
                    Sem.SemExprBinding(Sem.SemBindLocalStoredValue("blocklet.x", "x", Sem.SemTI32)),
                    Sem.SemExprConstInt(Sem.SemTI32, "2")
                )
            ),
        }, Sem.SemExprBinding(Sem.SemBindLocalStoredValue("blocklet.y", "y", Sem.SemTI32)), Sem.SemTI32)
    )),
    Sem.SemItemConst(Sem.SemConst(
        "BLOCKVAR",
        Sem.SemTI32,
        Sem.SemExprBlock({
            Sem.SemStmtVar("blockvar.v", "v", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "1")),
            Sem.SemStmtSet(
                Sem.SemBindLocalCell("blockvar.v", "v", Sem.SemTI32),
                Sem.SemExprAdd(
                    Sem.SemTI32,
                    Sem.SemExprBinding(Sem.SemBindLocalCell("blockvar.v", "v", Sem.SemTI32)),
                    Sem.SemExprConstInt(Sem.SemTI32, "41")
                )
            ),
        }, Sem.SemExprBinding(Sem.SemBindLocalCell("blockvar.v", "v", Sem.SemTI32)), Sem.SemTI32)
    )),
    Sem.SemItemConst(Sem.SemConst(
        "SWITCHEXPR",
        Sem.SemTI32,
        Sem.SemExprSwitch(
            Sem.SemExprConstInt(Sem.SemTI32, "2"),
            {
                Sem.SemSwitchExprArm(
                    Sem.SemExprConstInt(Sem.SemTI32, "1"),
                    {},
                    Sem.SemExprConstInt(Sem.SemTI32, "7")
                ),
                Sem.SemSwitchExprArm(
                    Sem.SemExprConstInt(Sem.SemTI32, "2"),
                    {
                        Sem.SemStmtLet("switchexpr.k", "k", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "40")),
                    },
                    Sem.SemExprAdd(
                        Sem.SemTI32,
                        Sem.SemExprBinding(Sem.SemBindLocalStoredValue("switchexpr.k", "k", Sem.SemTI32)),
                        Sem.SemExprConstInt(Sem.SemTI32, "2")
                    )
                ),
            },
            Sem.SemExprConstInt(Sem.SemTI32, "0"),
            Sem.SemTI32
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "SWITCHSTMT",
        Sem.SemTI32,
        Sem.SemExprBlock({
            Sem.SemStmtVar("switchstmt.s", "s", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
            Sem.SemStmtSwitch(
                Sem.SemExprConstInt(Sem.SemTI32, "2"),
                {
                    Sem.SemSwitchStmtArm(
                        Sem.SemExprConstInt(Sem.SemTI32, "1"),
                        {
                            Sem.SemStmtSet(Sem.SemBindLocalCell("switchstmt.s", "s", Sem.SemTI32), Sem.SemExprConstInt(Sem.SemTI32, "7")),
                        }
                    ),
                    Sem.SemSwitchStmtArm(
                        Sem.SemExprConstInt(Sem.SemTI32, "2"),
                        {
                            Sem.SemStmtSet(Sem.SemBindLocalCell("switchstmt.s", "s", Sem.SemTI32), Sem.SemExprConstInt(Sem.SemTI32, "42")),
                        }
                    ),
                },
                {
                    Sem.SemStmtSet(Sem.SemBindLocalCell("switchstmt.s", "s", Sem.SemTI32), Sem.SemExprConstInt(Sem.SemTI32, "9")),
                }
            ),
        }, Sem.SemExprBinding(Sem.SemBindLocalCell("switchstmt.s", "s", Sem.SemTI32)), Sem.SemTI32)
    )),
    Sem.SemItemConst(Sem.SemConst(
        "BLOCKIF",
        Sem.SemTI32,
        Sem.SemExprBlock({
            Sem.SemStmtVar("blockif.v", "v", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
            Sem.SemStmtIf(
                Sem.SemExprConstBool(true),
                {
                    Sem.SemStmtSet(Sem.SemBindLocalCell("blockif.v", "v", Sem.SemTI32), Sem.SemExprConstInt(Sem.SemTI32, "42")),
                },
                {
                    Sem.SemStmtSet(Sem.SemBindLocalCell("blockif.v", "v", Sem.SemTI32), Sem.SemExprConstInt(Sem.SemTI32, "7")),
                }
            ),
        }, Sem.SemExprBinding(Sem.SemBindLocalCell("blockif.v", "v", Sem.SemTI32)), Sem.SemTI32)
    )),
    Sem.SemItemConst(Sem.SemConst(
        "ASSERTOK",
        Sem.SemTI32,
        Sem.SemExprBlock({
            Sem.SemStmtAssert(Sem.SemExprConstBool(true)),
        }, Sem.SemExprConstInt(Sem.SemTI32, "42"), Sem.SemTI32)
    )),
}))
assert(contains_cmd(block_switch_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:BLOCKLET"), 0, Back.BackI32, "42")))
assert(contains_cmd(block_switch_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:BLOCKVAR"), 0, Back.BackI32, "42")))
assert(contains_cmd(block_switch_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:SWITCHEXPR"), 0, Back.BackI32, "42")))
assert(contains_cmd(block_switch_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:SWITCHSTMT"), 0, Back.BackI32, "42")))
assert(contains_cmd(block_switch_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:BLOCKIF"), 0, Back.BackI32, "42")))
assert(contains_cmd(block_switch_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:ASSERTOK"), 0, Back.BackI32, "42")))

local loop_const_module = one_module(Sem.SemModule({
    Sem.SemItemConst(Sem.SemConst(
        "WHILEACC",
        Sem.SemTI32,
        Sem.SemExprLoop(
            Sem.SemLoopWhileExpr(
                {
                    Sem.SemLoopBinding("whileacc.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
                    Sem.SemLoopBinding("whileacc.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
                },
                Sem.SemExprLt(
                    Sem.SemTBool,
                    Sem.SemExprBinding(Sem.SemBindLocalStoredValue("whileacc.i", "i", Sem.SemTI32)),
                    Sem.SemExprConstInt(Sem.SemTI32, "5")
                ),
                {},
                {
                    Sem.SemLoopNext(
                        Sem.SemBindLocalStoredValue("whileacc.i", "i", Sem.SemTI32),
                        Sem.SemExprAdd(
                            Sem.SemTI32,
                            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("whileacc.i", "i", Sem.SemTI32)),
                            Sem.SemExprConstInt(Sem.SemTI32, "1")
                        )
                    ),
                    Sem.SemLoopNext(
                        Sem.SemBindLocalStoredValue("whileacc.acc", "acc", Sem.SemTI32),
                        Sem.SemExprAdd(
                            Sem.SemTI32,
                            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("whileacc.acc", "acc", Sem.SemTI32)),
                            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("whileacc.i", "i", Sem.SemTI32))
                        )
                    ),
                },
                Sem.SemExprBinding(Sem.SemBindLocalStoredValue("whileacc.acc", "acc", Sem.SemTI32))
            ),
            Sem.SemTI32
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "WHILEBREAK",
        Sem.SemTI32,
        Sem.SemExprLoop(
            Sem.SemLoopWhileExpr(
                {
                    Sem.SemLoopBinding("whilebreak.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
                },
                Sem.SemExprConstBool(true),
                {
                    Sem.SemStmtIf(
                        Sem.SemExprGe(
                            Sem.SemTBool,
                            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("whilebreak.i", "i", Sem.SemTI32)),
                            Sem.SemExprConstInt(Sem.SemTI32, "3")
                        ),
                        { Sem.SemStmtBreak },
                        {}
                    ),
                },
                {
                    Sem.SemLoopNext(
                        Sem.SemBindLocalStoredValue("whilebreak.i", "i", Sem.SemTI32),
                        Sem.SemExprAdd(
                            Sem.SemTI32,
                            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("whilebreak.i", "i", Sem.SemTI32)),
                            Sem.SemExprConstInt(Sem.SemTI32, "1")
                        )
                    ),
                },
                Sem.SemExprBinding(Sem.SemBindLocalStoredValue("whilebreak.i", "i", Sem.SemTI32))
            ),
            Sem.SemTI32
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "STMTCONTINUE",
        Sem.SemTI32,
        Sem.SemExprBlock({
            Sem.SemStmtVar("stmtcontinue.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
            Sem.SemStmtLoop(Sem.SemLoopWhileStmt(
                {
                    Sem.SemLoopBinding("stmtcontinue.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
                },
                Sem.SemExprLt(
                    Sem.SemTBool,
                    Sem.SemExprBinding(Sem.SemBindLocalStoredValue("stmtcontinue.i", "i", Sem.SemTI32)),
                    Sem.SemExprConstInt(Sem.SemTI32, "4")
                ),
                {
                    Sem.SemStmtIf(
                        Sem.SemExprEq(
                            Sem.SemTBool,
                            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("stmtcontinue.i", "i", Sem.SemTI32)),
                            Sem.SemExprConstInt(Sem.SemTI32, "2")
                        ),
                        {
                            Sem.SemStmtSet(
                                Sem.SemBindLocalCell("stmtcontinue.acc", "acc", Sem.SemTI32),
                                Sem.SemExprAdd(
                                    Sem.SemTI32,
                                    Sem.SemExprBinding(Sem.SemBindLocalCell("stmtcontinue.acc", "acc", Sem.SemTI32)),
                                    Sem.SemExprConstInt(Sem.SemTI32, "100")
                                )
                            ),
                            Sem.SemStmtContinue,
                        },
                        {}
                    ),
                    Sem.SemStmtSet(
                        Sem.SemBindLocalCell("stmtcontinue.acc", "acc", Sem.SemTI32),
                        Sem.SemExprAdd(
                            Sem.SemTI32,
                            Sem.SemExprBinding(Sem.SemBindLocalCell("stmtcontinue.acc", "acc", Sem.SemTI32)),
                            Sem.SemExprConstInt(Sem.SemTI32, "1")
                        )
                    ),
                },
                {
                    Sem.SemLoopNext(
                        Sem.SemBindLocalStoredValue("stmtcontinue.i", "i", Sem.SemTI32),
                        Sem.SemExprAdd(
                            Sem.SemTI32,
                            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("stmtcontinue.i", "i", Sem.SemTI32)),
                            Sem.SemExprConstInt(Sem.SemTI32, "1")
                        )
                    ),
                }
            )),
        }, Sem.SemExprBinding(Sem.SemBindLocalCell("stmtcontinue.acc", "acc", Sem.SemTI32)), Sem.SemTI32)
    )),
    Sem.SemItemConst(Sem.SemConst(
        "OVERRANGE",
        Sem.SemTI32,
        Sem.SemExprLoop(
            Sem.SemLoopOverExpr(
                Sem.SemBindLocalStoredValue("overrange.i", "i", Sem.SemTIndex),
                Sem.SemDomainRange(Sem.SemExprConstInt(Sem.SemTIndex, "4")),
                {
                    Sem.SemLoopBinding("overrange.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
                },
                {},
                {
                    Sem.SemLoopNext(
                        Sem.SemBindLocalStoredValue("overrange.acc", "acc", Sem.SemTI32),
                        Sem.SemExprAdd(
                            Sem.SemTI32,
                            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("overrange.acc", "acc", Sem.SemTI32)),
                            Sem.SemExprCastTo(
                                Sem.SemTI32,
                                Sem.SemExprBinding(Sem.SemBindLocalStoredValue("overrange.i", "i", Sem.SemTIndex))
                            )
                        )
                    ),
                },
                Sem.SemExprBinding(Sem.SemBindLocalStoredValue("overrange.acc", "acc", Sem.SemTI32))
            ),
            Sem.SemTI32
        )
    )),
    Sem.SemItemConst(Sem.SemConst(
        "OVERRANGE2BREAK",
        Sem.SemTIndex,
        Sem.SemExprLoop(
            Sem.SemLoopOverExpr(
                Sem.SemBindLocalStoredValue("overrange2.i", "i", Sem.SemTIndex),
                Sem.SemDomainRange2(
                    Sem.SemExprConstInt(Sem.SemTIndex, "1"),
                    Sem.SemExprConstInt(Sem.SemTIndex, "5")
                ),
                {
                    Sem.SemLoopBinding("overrange2.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
                },
                {
                    Sem.SemStmtIf(
                        Sem.SemExprEq(
                            Sem.SemTBool,
                            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("overrange2.i", "i", Sem.SemTIndex)),
                            Sem.SemExprConstInt(Sem.SemTIndex, "3")
                        ),
                        { Sem.SemStmtBreak },
                        {}
                    ),
                },
                {
                    Sem.SemLoopNext(
                        Sem.SemBindLocalStoredValue("overrange2.acc", "acc", Sem.SemTI32),
                        Sem.SemExprAdd(
                            Sem.SemTI32,
                            Sem.SemExprBinding(Sem.SemBindLocalStoredValue("overrange2.acc", "acc", Sem.SemTI32)),
                            Sem.SemExprCastTo(
                                Sem.SemTI32,
                                Sem.SemExprBinding(Sem.SemBindLocalStoredValue("overrange2.i", "i", Sem.SemTIndex))
                            )
                        )
                    ),
                },
                Sem.SemExprBinding(Sem.SemBindLocalStoredValue("overrange2.i", "i", Sem.SemTIndex))
            ),
            Sem.SemTIndex
        )
    )),
}))
assert(contains_cmd(loop_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:WHILEACC"), 0, Back.BackI32, "10")))
assert(contains_cmd(loop_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:WHILEBREAK"), 0, Back.BackI32, "3")))
assert(contains_cmd(loop_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:STMTCONTINUE"), 0, Back.BackI32, "103")))
assert(contains_cmd(loop_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:OVERRANGE"), 0, Back.BackI32, "6")))
assert(contains_cmd(loop_const_module, Back.BackCmdDataInitInt(Back.BackDataId("data:const:OVERRANGE2BREAK"), 0, Back.BackIndex, "3")))

local cycle_ok, cycle_err = pcall(function()
    return one_module(Sem.SemModule({
        Sem.SemItemConst(Sem.SemConst(
            "A",
            Sem.SemTI32,
            Sem.SemExprBinding(Sem.SemBindGlobal("", "B", Sem.SemTI32))
        )),
        Sem.SemItemConst(Sem.SemConst(
            "B",
            Sem.SemTI32,
            Sem.SemExprBinding(Sem.SemBindGlobal("", "A", Sem.SemTI32))
        )),
    }))
end)
assert(not cycle_ok)
assert(string.find(cycle_err, "cyclic const dependency", 1, true) ~= nil)

print("moonlift sem->back lowering ok")
