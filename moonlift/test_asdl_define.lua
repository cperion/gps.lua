package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require('pvm')
local A = require('moonlift.asdl')

local T = pvm.context()
A.Define(T)

assert(T.MoonliftSurface ~= nil)
assert(T.MoonliftElab ~= nil)
assert(T.MoonliftSem ~= nil)
assert(T.MoonliftBack ~= nil)
assert(T.MoonliftSem.SemLoop ~= nil)
assert(T.MoonliftBack.BackProgram ~= nil)

local S = T.MoonliftSem
local i32_ty = S.SemTI32
local idx = S.SemBindLoopCarry('loop', 'carry.i', 'i', i32_ty)
local bind = S.SemExprBinding(idx)
local zero = S.SemExprConstInt(i32_ty, '0')
local init = S.SemLoopCarryPort('carry.i', 'i', i32_ty, zero)
local cond = S.SemExprLt(S.SemTBool, bind, S.SemExprConstInt(i32_ty, '4'))
local nextv = S.SemLoopUpdate('carry.i', S.SemExprAdd(i32_ty, bind, S.SemExprConstInt(i32_ty, '1')))
local loop = S.SemLoopWhileExpr('loop', { init }, cond, {}, { nextv }, S.SemLoopExprEndOnly, bind)
assert(loop ~= nil)

local B = T.MoonliftBack
local sig = B.BackSigId('sig.main')
local func = B.BackFuncId('main')
local entry = B.BackBlockId('entry')
local param_x = B.BackValId('x')
local c37 = B.BackValId('c37')
local sum = B.BackValId('sum')
local prog = B.BackProgram({
    B.BackCmdCreateSig(sig, { B.BackI32 }, { B.BackI32 }),
    B.BackCmdDeclareFuncExport(func, sig),
    B.BackCmdBeginFunc(func),
    B.BackCmdCreateBlock(entry),
    B.BackCmdSwitchToBlock(entry),
    B.BackCmdBindEntryParams(entry, { param_x }),
    B.BackCmdConstInt(c37, B.BackI32, '37'),
    B.BackCmdIadd(sum, B.BackI32, c37, param_x),
    B.BackCmdReturnValue(sum),
    B.BackCmdFinishFunc(func),
    B.BackCmdFinalizeModule,
})
assert(prog ~= nil)

print('moonlift ASDL define ok')
