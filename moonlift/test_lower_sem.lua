package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Lower = require("moonlift.lower_elab_to_sem")

local T = pvm.context()
A.Define(T)
local L = Lower.Define(T)

local Elab = T.MoonliftElab
local Sem = T.MoonliftSem

local function one_type(node, const_env)
    return pvm.one(L.lower_type(node, const_env))
end

local function one_binding(node, const_env)
    return pvm.one(L.lower_binding(node, const_env))
end

local function one_expr(node, const_env)
    return pvm.one(L.lower_expr(node, const_env))
end

local function one_domain(node, const_env)
    return pvm.one(L.lower_domain(node, const_env))
end

local function one_loop(node, const_env)
    return pvm.one(L.lower_loop(node, const_env))
end

local function one_stmt(node, const_env)
    return pvm.one(L.lower_stmt(node, const_env))
end

local function one_item(node, const_env)
    return pvm.one(L.lower_item(node, const_env))
end

local function one_module(node, const_env)
    return pvm.one(L.lower_module(node, const_env))
end

local array4_elab = Elab.ElabTArray(Elab.ElabInt("4", Elab.ElabTIndex), Elab.ElabTI32)
local array4_sem = Sem.SemTArray(Sem.SemTI32, 4)

assert(one_type(Elab.ElabTI32) == Sem.SemTI32)
assert(one_type(Elab.ElabTPtr(Elab.ElabTI32)) == Sem.SemTPtrTo(Sem.SemTI32))
assert(one_type(array4_elab) == array4_sem)
assert(one_type(Elab.ElabTView(Elab.ElabTI32)) == Sem.SemTView(Sem.SemTI32))
assert(one_type(Elab.ElabTNamed("Demo", "Pair")) == Sem.SemTNamed("Demo", "Pair"))

local const_env = Elab.ElabConstEnv({
    Elab.ElabConstEntry("", "N", Elab.ElabTIndex, Elab.ElabInt("4", Elab.ElabTIndex)),
    Elab.ElabConstEntry(
        "",
        "M",
        Elab.ElabTIndex,
        Elab.ElabExprAdd(
            Elab.ElabTIndex,
            Elab.ElabBindingExpr(Elab.ElabGlobalConst("", "N", Elab.ElabTIndex)),
            Elab.ElabInt("2", Elab.ElabTIndex)
        )
    ),
})
assert(one_type(
    Elab.ElabTArray(
        Elab.ElabBindingExpr(Elab.ElabGlobalConst("", "M", Elab.ElabTIndex)),
        Elab.ElabTI32
    ),
    const_env
) == Sem.SemTArray(Sem.SemTI32, 6))

assert(one_binding(Elab.ElabGlobalFunc("", "sum", Elab.ElabTFunc({ Elab.ElabTI32 }, Elab.ElabTI32))) ==
    Sem.SemBindGlobalFunc("", "sum", Sem.SemTFunc({ Sem.SemTI32 }, Sem.SemTI32)))
assert(one_binding(Elab.ElabGlobalConst("", "K", Elab.ElabTI32)) ==
    Sem.SemBindGlobalConst("", "K", Sem.SemTI32))
assert(one_binding(Elab.ElabGlobalStatic("", "S", Elab.ElabTI32)) ==
    Sem.SemBindGlobalStatic("", "S", Sem.SemTI32))
assert(one_binding(Elab.ElabExtern("puts", Elab.ElabTFunc({}, Elab.ElabTVoid))) ==
    Sem.SemBindExtern("puts", Sem.SemTFunc({}, Sem.SemTVoid)))

local pair_cell_elab = Elab.ElabLocalCell("pair.cell", "pair", Elab.ElabTNamed("Demo", "Pair"))
local pair_cell_sem = Sem.SemBindLocalCell("pair.cell", "pair", Sem.SemTNamed("Demo", "Pair"))
local arr_cell_elab = Elab.ElabLocalCell("arr.cell", "arr", array4_elab)
local arr_cell_sem = Sem.SemBindLocalCell("arr.cell", "arr", array4_sem)

local add_expr = one_expr(Elab.ElabExprAdd(
    Elab.ElabTI32,
    Elab.ElabBindingExpr(Elab.ElabLocalValue("lx", "x", Elab.ElabTI32)),
    Elab.ElabInt("1", Elab.ElabTI32)
))
assert(add_expr == Sem.SemExprAdd(
    Sem.SemTI32,
    Sem.SemExprBinding(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32)),
    Sem.SemExprConstInt(Sem.SemTI32, "1")
))

local addr_of_expr = one_expr(Elab.ElabExprAddrOf(
    Elab.ElabPlaceBinding(Elab.ElabLocalCell("cx", "x", Elab.ElabTI32)),
    Elab.ElabTPtr(Elab.ElabTI32)
))
assert(addr_of_expr == Sem.SemExprAddrOf(
    Sem.SemPlaceBinding(Sem.SemBindLocalCell("cx", "x", Sem.SemTI32)),
    Sem.SemTPtrTo(Sem.SemTI32)
))

local field_addr_expr = one_expr(Elab.ElabExprAddrOf(
    Elab.ElabPlaceField(
        Elab.ElabPlaceBinding(pair_cell_elab),
        "left",
        Elab.ElabTI32
    ),
    Elab.ElabTPtr(Elab.ElabTI32)
))
assert(field_addr_expr == Sem.SemExprAddrOf(
    Sem.SemPlaceField(
        Sem.SemPlaceBinding(pair_cell_sem),
        Sem.SemFieldByName("left", Sem.SemTI32)
    ),
    Sem.SemTPtrTo(Sem.SemTI32)
))

local deref_expr = one_expr(Elab.ElabExprDeref(
    Elab.ElabTI32,
    Elab.ElabBindingExpr(Elab.ElabArg(0, "p", Elab.ElabTPtr(Elab.ElabTI32)))
))
assert(deref_expr == Sem.SemExprDeref(
    Sem.SemTI32,
    Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTI32)))
))

local direct_call = one_expr(Elab.ElabCall(
    Elab.ElabBindingExpr(Elab.ElabGlobalFunc("", "sum", Elab.ElabTFunc({ Elab.ElabTI32 }, Elab.ElabTI32))),
    Elab.ElabTI32,
    { Elab.ElabInt("7", Elab.ElabTI32) }
))
assert(direct_call == Sem.SemExprCall(
    Sem.SemCallDirect("", "sum", Sem.SemTFunc({ Sem.SemTI32 }, Sem.SemTI32)),
    Sem.SemTI32,
    { Sem.SemExprConstInt(Sem.SemTI32, "7") }
))

local extern_call = one_expr(Elab.ElabCall(
    Elab.ElabBindingExpr(Elab.ElabExtern("puts", Elab.ElabTFunc({ Elab.ElabTPtr(Elab.ElabTI8) }, Elab.ElabTVoid))),
    Elab.ElabTVoid,
    { Elab.ElabNil(Elab.ElabTPtr(Elab.ElabTI8)) }
))
assert(extern_call == Sem.SemExprCall(
    Sem.SemCallExtern("puts", Sem.SemTFunc({ Sem.SemTPtrTo(Sem.SemTI8) }, Sem.SemTVoid)),
    Sem.SemTVoid,
    { Sem.SemExprNil(Sem.SemTPtrTo(Sem.SemTI8)) }
))

local domain_range = one_domain(Elab.ElabDomainRange(
    Elab.ElabBindingExpr(Elab.ElabArg(0, "n", Elab.ElabTI32))
))
assert(domain_range == Sem.SemDomainRange(
    Sem.SemExprCastTo(Sem.SemTIndex, Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTI32)))
))

local domain_value = one_domain(Elab.ElabDomainValue(
    Elab.ElabBindingExpr(arr_cell_elab)
))
assert(domain_value == Sem.SemDomainView(
    Sem.SemViewValue(
        Sem.SemExprBinding(arr_cell_sem),
        Sem.SemTI32
    )
))

local domain_zip = one_domain(Elab.ElabDomainZipEq({
    Elab.ElabBindingExpr(Elab.ElabLocalCell("zip.a", "a", array4_elab)),
    Elab.ElabBindingExpr(Elab.ElabLocalCell("zip.b", "b", array4_elab)),
}))
assert(domain_zip == Sem.SemDomainZipEq({
    Sem.SemViewValue(Sem.SemExprBinding(Sem.SemBindLocalCell("zip.a", "a", array4_sem)), Sem.SemTI32),
    Sem.SemViewValue(Sem.SemExprBinding(Sem.SemBindLocalCell("zip.b", "b", array4_sem)), Sem.SemTI32),
}))

local set_stmt = one_stmt(Elab.ElabSet(
    Elab.ElabPlaceBinding(Elab.ElabLocalCell("cx", "x", Elab.ElabTI32)),
    Elab.ElabExprAdd(
        Elab.ElabTI32,
        Elab.ElabBindingExpr(Elab.ElabLocalValue("lx", "x", Elab.ElabTI32)),
        Elab.ElabInt("2", Elab.ElabTI32)
    )
))
assert(set_stmt == Sem.SemStmtSet(
    Sem.SemPlaceBinding(Sem.SemBindLocalCell("cx", "x", Sem.SemTI32)),
    Sem.SemExprAdd(
        Sem.SemTI32,
        Sem.SemExprBinding(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32)),
        Sem.SemExprConstInt(Sem.SemTI32, "2")
    )
))

local deref_set_stmt = one_stmt(Elab.ElabSet(
    Elab.ElabPlaceDeref(
        Elab.ElabBindingExpr(Elab.ElabArg(0, "p", Elab.ElabTPtr(Elab.ElabTI32))),
        Elab.ElabTI32
    ),
    Elab.ElabInt("9", Elab.ElabTI32)
))
assert(deref_set_stmt == Sem.SemStmtSet(
    Sem.SemPlaceDeref(
        Sem.SemExprBinding(Sem.SemBindArg(0, "p", Sem.SemTPtrTo(Sem.SemTI32))),
        Sem.SemTI32
    ),
    Sem.SemExprConstInt(Sem.SemTI32, "9")
))

local index_set_stmt = one_stmt(Elab.ElabSet(
    Elab.ElabPlaceIndex(
        Elab.ElabIndexBasePlace(Elab.ElabPlaceBinding(arr_cell_elab), Elab.ElabTI32),
        Elab.ElabInt("1", Elab.ElabTIndex),
        Elab.ElabTI32
    ),
    Elab.ElabInt("9", Elab.ElabTI32)
))
assert(index_set_stmt == Sem.SemStmtSet(
    Sem.SemPlaceIndex(
        Sem.SemIndexBasePlace(Sem.SemPlaceBinding(arr_cell_sem), Sem.SemTI32),
        Sem.SemExprConstInt(Sem.SemTIndex, "1"),
        Sem.SemTI32
    ),
    Sem.SemExprConstInt(Sem.SemTI32, "9")
))

assert(one_stmt(Elab.ElabBreak) == Sem.SemStmtBreak)
assert(one_stmt(Elab.ElabBreakValue(Elab.ElabInt("5", Elab.ElabTI32))) ==
    Sem.SemStmtBreakValue(Sem.SemExprConstInt(Sem.SemTI32, "5")))
assert(one_stmt(Elab.ElabContinue) == Sem.SemStmtContinue)

local switch_expr = one_expr(Elab.ElabSwitchExpr(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("lx", "x", Elab.ElabTI32)),
    {
        Elab.ElabSwitchExprArm(
            Elab.ElabInt("1", Elab.ElabTI32),
            { Elab.ElabExprStmt(Elab.ElabBindingExpr(Elab.ElabLocalValue("lx", "x", Elab.ElabTI32))) },
            Elab.ElabInt("11", Elab.ElabTI32)
        ),
    },
    Elab.ElabInt("22", Elab.ElabTI32),
    Elab.ElabTI32
))
assert(switch_expr == Sem.SemExprSwitch(
    Sem.SemExprBinding(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32)),
    {
        Sem.SemSwitchExprArm(
            Sem.SemExprConstInt(Sem.SemTI32, "1"),
            { Sem.SemStmtExpr(Sem.SemExprBinding(Sem.SemBindLocalValue("lx", "x", Sem.SemTI32))) },
            Sem.SemExprConstInt(Sem.SemTI32, "11")
        ),
    },
    Sem.SemExprConstInt(Sem.SemTI32, "22"),
    Sem.SemTI32
))

local while_loop = one_loop(Elab.ElabLoopWhileExpr(
    "loop.sum",
    {
        Elab.ElabLoopCarryPort("carry.i", "i", Elab.ElabTI32, Elab.ElabInt("0", Elab.ElabTI32)),
        Elab.ElabLoopCarryPort("carry.acc", "acc", Elab.ElabTI32, Elab.ElabInt("0", Elab.ElabTI32)),
    },
    Elab.ElabExprLt(
        Elab.ElabTBool,
        Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.sum", "carry.i", "i", Elab.ElabTI32)),
        Elab.ElabBindingExpr(Elab.ElabArg(0, "n", Elab.ElabTI32))
    ),
    {
        Elab.ElabExprStmt(Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.sum", "carry.acc", "acc", Elab.ElabTI32))),
    },
    {
        Elab.ElabLoopUpdate(
            "carry.i",
            Elab.ElabExprAdd(
                Elab.ElabTI32,
                Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.sum", "carry.i", "i", Elab.ElabTI32)),
                Elab.ElabInt("1", Elab.ElabTI32)
            )
        ),
        Elab.ElabLoopUpdate(
            "carry.acc",
            Elab.ElabExprAdd(
                Elab.ElabTI32,
                Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.sum", "carry.acc", "acc", Elab.ElabTI32)),
                Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.sum", "carry.i", "i", Elab.ElabTI32))
            )
        ),
    },
    Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.sum", "carry.acc", "acc", Elab.ElabTI32))
))
assert(while_loop == Sem.SemLoopWhileExpr(
    "loop.sum",
    {
        Sem.SemLoopCarryPort("carry.i", "i", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
        Sem.SemLoopCarryPort("carry.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
    },
    Sem.SemExprLt(
        Sem.SemTBool,
        Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.sum", "carry.i", "i", Sem.SemTI32)),
        Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTI32))
    ),
    {
        Sem.SemStmtExpr(Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.sum", "carry.acc", "acc", Sem.SemTI32))),
    },
    {
        Sem.SemLoopUpdate(
            "carry.i",
            Sem.SemExprAdd(
                Sem.SemTI32,
                Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.sum", "carry.i", "i", Sem.SemTI32)),
                Sem.SemExprConstInt(Sem.SemTI32, "1")
            )
        ),
        Sem.SemLoopUpdate(
            "carry.acc",
            Sem.SemExprAdd(
                Sem.SemTI32,
                Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.sum", "carry.acc", "acc", Sem.SemTI32)),
                Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.sum", "carry.i", "i", Sem.SemTI32))
            )
        ),
    },
    Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.sum", "carry.acc", "acc", Sem.SemTI32))
))

local over_loop = one_loop(Elab.ElabLoopOverStmt(
    "loop.over",
    Elab.ElabLoopIndexPort("i", Elab.ElabTIndex),
    Elab.ElabDomainRange(Elab.ElabBindingExpr(Elab.ElabArg(0, "n", Elab.ElabTI32))),
    {
        Elab.ElabLoopCarryPort("carry.acc", "acc", Elab.ElabTI32, Elab.ElabInt("0", Elab.ElabTI32)),
    },
    {},
    {
        Elab.ElabLoopUpdate(
            "carry.acc",
            Elab.ElabExprAdd(
                Elab.ElabTI32,
                Elab.ElabBindingExpr(Elab.ElabLoopCarry("loop.over", "carry.acc", "acc", Elab.ElabTI32)),
                Elab.ElabExprCastTo(
                    Elab.ElabTI32,
                    Elab.ElabBindingExpr(Elab.ElabLoopIndex("loop.over", "i", Elab.ElabTIndex))
                )
            )
        ),
    }
))
assert(over_loop == Sem.SemLoopOverStmt(
    "loop.over",
    Sem.SemLoopIndexPort("i", Sem.SemTIndex),
    Sem.SemDomainRange(
        Sem.SemExprCastTo(Sem.SemTIndex, Sem.SemExprBinding(Sem.SemBindArg(0, "n", Sem.SemTI32)))
    ),
    {
        Sem.SemLoopCarryPort("carry.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
    },
    {},
    {
        Sem.SemLoopUpdate(
            "carry.acc",
            Sem.SemExprAdd(
                Sem.SemTI32,
                Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.over", "carry.acc", "acc", Sem.SemTI32)),
                Sem.SemExprCastTo(
                    Sem.SemTI32,
                    Sem.SemExprBinding(Sem.SemBindLoopIndex("loop.over", "i", Sem.SemTIndex))
                )
            )
        ),
    }
))

local item_module = one_module(Elab.ElabModule("", {
    Elab.ElabItemConst(Elab.ElabConst("K", Elab.ElabTI32, Elab.ElabInt("1", Elab.ElabTI32))),
    Elab.ElabItemStatic(Elab.ElabStatic("S", Elab.ElabTI32, Elab.ElabInt("2", Elab.ElabTI32))),
}))
assert(item_module == Sem.SemModule("", {
    Sem.SemItemConst(Sem.SemConst("K", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "1"))),
    Sem.SemItemStatic(Sem.SemStatic("S", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "2"))),
}))

assert(one_item(Elab.ElabItemStatic(Elab.ElabStatic("S", Elab.ElabTI32, Elab.ElabInt("2", Elab.ElabTI32)))) ==
    Sem.SemItemStatic(Sem.SemStatic("S", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "2"))))

print("moonlift elab->sem lowering ok")
