package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Residence = require("moonlift.resolve_sem_residence")

local T = pvm.context()
A.Define(T)
local R = Residence.Define(T)

local Sem = T.MoonliftSem

local function find_residence(plan, binding)
    for i = 1, #plan.entries do
        local entry = plan.entries[i]
        if entry.binding == binding then
            return entry.residence
        end
    end
    return nil
end

assert(pvm.one(R.lower_type_default_residence(Sem.SemTI32)) == Sem.SemResidenceValue)
assert(pvm.one(R.lower_type_default_residence(Sem.SemTPtrTo(Sem.SemTI32))) == Sem.SemResidenceValue)
assert(pvm.one(R.lower_type_default_residence(Sem.SemTArray(Sem.SemTI32, 4))) == Sem.SemResidenceStack)
assert(pvm.one(R.lower_binding_residence(Sem.SemBindLocalValue("x", "x", Sem.SemTI32))) == Sem.SemResidenceValue)
assert(pvm.one(R.lower_binding_residence(Sem.SemBindLocalValue("arr", "arr", Sem.SemTArray(Sem.SemTI32, 4)))) == Sem.SemResidenceStack)
assert(pvm.one(R.lower_binding_residence(Sem.SemBindLocalCell("cx", "x", Sem.SemTI32))) == Sem.SemResidenceStack)
assert(pvm.one(R.lower_binding_residence(Sem.SemBindArg(0, "x", Sem.SemTI32))) == Sem.SemResidenceValue)
assert(pvm.one(R.lower_binding_residence(Sem.SemBindArg(1, "arr", Sem.SemTArray(Sem.SemTI32, 4)))) == Sem.SemResidenceStack)
assert(pvm.one(R.lower_binding_residence(Sem.SemBindLoopCarry("loop", "carry.acc", "acc", Sem.SemTI32))) == Sem.SemResidenceValue)
assert(pvm.one(R.lower_binding_residence(Sem.SemBindLoopIndex("loop", "i", Sem.SemTIndex))) == Sem.SemResidenceValue)

local func = Sem.SemFuncExport(
    "demo",
    {
        Sem.SemParam("x", Sem.SemTI32),
        Sem.SemParam("arr", Sem.SemTArray(Sem.SemTI32, 4)),
    },
    Sem.SemTI32,
    {
        Sem.SemStmtLet(
            "ly",
            "y",
            Sem.SemTI32,
            Sem.SemExprConstInt(Sem.SemTI32, "1")
        ),
        Sem.SemStmtExpr(Sem.SemExprAddrOf(
            Sem.SemPlaceBinding(Sem.SemBindArg(0, "x", Sem.SemTI32)),
            Sem.SemTPtrTo(Sem.SemTI32)
        )),
        Sem.SemStmtExpr(Sem.SemExprAddrOf(
            Sem.SemPlaceBinding(Sem.SemBindLocalValue("ly", "y", Sem.SemTI32)),
            Sem.SemTPtrTo(Sem.SemTI32)
        )),
        Sem.SemStmtVar(
            "vz",
            "z",
            Sem.SemTI32,
            Sem.SemExprConstInt(Sem.SemTI32, "2")
        ),
        Sem.SemStmtExpr(Sem.SemExprLoop(
            Sem.SemLoopOverExpr(
                "loop.sum",
                Sem.SemLoopIndexPort("i", Sem.SemTIndex),
                Sem.SemDomainRange(Sem.SemExprConstInt(Sem.SemTIndex, "4")),
                {
                    Sem.SemLoopCarryPort("carry.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
                },
                {
                    Sem.SemStmtBreakValue(Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.sum", "carry.acc", "acc", Sem.SemTI32))),
                },
                {
                    Sem.SemLoopUpdate(
                        "carry.acc",
                        Sem.SemExprAdd(
                            Sem.SemTI32,
                            Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.sum", "carry.acc", "acc", Sem.SemTI32)),
                            Sem.SemExprConstInt(Sem.SemTI32, "1")
                        )
                    ),
                },
                Sem.SemExprBinding(Sem.SemBindLoopCarry("loop.sum", "carry.acc", "acc", Sem.SemTI32))
            ),
            Sem.SemTI32
        )),
        Sem.SemStmtReturnValue(Sem.SemExprBinding(Sem.SemBindLocalValue("ly", "y", Sem.SemTI32))),
    }
)

local plan = pvm.one(R.lower_func_residence_plan(func))
assert(find_residence(plan, Sem.SemBindArg(0, "x", Sem.SemTI32)) == Sem.SemResidenceStack)
assert(find_residence(plan, Sem.SemBindArg(1, "arr", Sem.SemTArray(Sem.SemTI32, 4))) == Sem.SemResidenceStack)
assert(find_residence(plan, Sem.SemBindLocalValue("ly", "y", Sem.SemTI32)) == Sem.SemResidenceStack)
assert(find_residence(plan, Sem.SemBindLocalCell("vz", "z", Sem.SemTI32)) == Sem.SemResidenceStack)
assert(find_residence(plan, Sem.SemBindLoopIndex("loop.sum", "i", Sem.SemTIndex)) == Sem.SemResidenceValue)
assert(find_residence(plan, Sem.SemBindLoopCarry("loop.sum", "carry.acc", "acc", Sem.SemTI32)) == Sem.SemResidenceValue)

local addr_taken_loop_func = Sem.SemFuncExport(
    "addr_loop_demo",
    {},
    Sem.SemTVoid,
    {
        Sem.SemStmtLoop(Sem.SemLoopOverStmt(
            "loop.addr",
            Sem.SemLoopIndexPort("i", Sem.SemTIndex),
            Sem.SemDomainRange(Sem.SemExprConstInt(Sem.SemTIndex, "4")),
            {
                Sem.SemLoopCarryPort("carry.acc", "acc", Sem.SemTI32, Sem.SemExprConstInt(Sem.SemTI32, "0")),
            },
            {
                Sem.SemStmtExpr(Sem.SemExprAddrOf(
                    Sem.SemPlaceBinding(Sem.SemBindLoopIndex("loop.addr", "i", Sem.SemTIndex)),
                    Sem.SemTPtrTo(Sem.SemTIndex)
                )),
                Sem.SemStmtExpr(Sem.SemExprAddrOf(
                    Sem.SemPlaceBinding(Sem.SemBindLoopCarry("loop.addr", "carry.acc", "acc", Sem.SemTI32)),
                    Sem.SemTPtrTo(Sem.SemTI32)
                )),
            },
            {
                Sem.SemLoopUpdate(
                    "carry.acc",
                    Sem.SemExprConstInt(Sem.SemTI32, "1")
                ),
            }
        )),
        Sem.SemStmtReturnVoid,
    }
)
local addr_taken_loop_plan = pvm.one(R.lower_func_residence_plan(addr_taken_loop_func))
assert(find_residence(addr_taken_loop_plan, Sem.SemBindLoopIndex("loop.addr", "i", Sem.SemTIndex)) == Sem.SemResidenceStack)
assert(find_residence(addr_taken_loop_plan, Sem.SemBindLoopCarry("loop.addr", "carry.acc", "acc", Sem.SemTI32)) == Sem.SemResidenceStack)

print("moonlift sem residence ok")
