package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.Define(T)
    local Sem = T.MoonliftSem
    local Back = T.MoonliftBack

    local lower_neg_cmd = pvm.phase("sem_to_back_neg_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, value) return pvm.once(Back.BackCmdIneg(dst, ty, value)) end,
        [Sem.SemTI16] = function(self, dst, ty, value) return pvm.once(Back.BackCmdIneg(dst, ty, value)) end,
        [Sem.SemTI32] = function(self, dst, ty, value) return pvm.once(Back.BackCmdIneg(dst, ty, value)) end,
        [Sem.SemTI64] = function(self, dst, ty, value) return pvm.once(Back.BackCmdIneg(dst, ty, value)) end,
        [Sem.SemTF32] = function(self, dst, ty, value) return pvm.once(Back.BackCmdFneg(dst, ty, value)) end,
        [Sem.SemTF64] = function(self, dst, ty, value) return pvm.once(Back.BackCmdFneg(dst, ty, value)) end,
    })

    local lower_add_cmd = pvm.phase("sem_to_back_add_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIadd(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIadd(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIadd(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIadd(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIadd(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIadd(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIadd(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIadd(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIadd(dst, ty, lhs, rhs)) end,
        [Sem.SemTPtr] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIadd(dst, ty, lhs, rhs)) end,
        [Sem.SemTPtrTo] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIadd(dst, ty, lhs, rhs)) end,
        [Sem.SemTF32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFadd(dst, ty, lhs, rhs)) end,
        [Sem.SemTF64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFadd(dst, ty, lhs, rhs)) end,
    })

    local lower_sub_cmd = pvm.phase("sem_to_back_sub_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIsub(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIsub(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIsub(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIsub(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIsub(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIsub(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIsub(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIsub(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIsub(dst, ty, lhs, rhs)) end,
        [Sem.SemTF32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFsub(dst, ty, lhs, rhs)) end,
        [Sem.SemTF64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFsub(dst, ty, lhs, rhs)) end,
    })

    local lower_mul_cmd = pvm.phase("sem_to_back_mul_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdImul(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdImul(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdImul(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdImul(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdImul(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdImul(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdImul(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdImul(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdImul(dst, ty, lhs, rhs)) end,
        [Sem.SemTF32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFmul(dst, ty, lhs, rhs)) end,
        [Sem.SemTF64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFmul(dst, ty, lhs, rhs)) end,
    })

    local lower_div_cmd = pvm.phase("sem_to_back_div_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSdiv(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSdiv(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSdiv(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSdiv(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUdiv(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUdiv(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUdiv(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUdiv(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUdiv(dst, ty, lhs, rhs)) end,
        [Sem.SemTF32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFdiv(dst, ty, lhs, rhs)) end,
        [Sem.SemTF64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFdiv(dst, ty, lhs, rhs)) end,
    })

    local lower_rem_cmd = pvm.phase("sem_to_back_rem_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSrem(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSrem(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSrem(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSrem(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUrem(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUrem(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUrem(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUrem(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUrem(dst, ty, lhs, rhs)) end,
    })

    local lower_lt_cmd = pvm.phase("sem_to_back_lt_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpLt(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpLt(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpLt(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpLt(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpLt(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpLt(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpLt(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpLt(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpLt(dst, ty, lhs, rhs)) end,
        [Sem.SemTF32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFCmpLt(dst, ty, lhs, rhs)) end,
        [Sem.SemTF64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFCmpLt(dst, ty, lhs, rhs)) end,
    })

    local lower_le_cmd = pvm.phase("sem_to_back_le_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpLe(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpLe(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpLe(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpLe(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpLe(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpLe(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpLe(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpLe(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpLe(dst, ty, lhs, rhs)) end,
        [Sem.SemTF32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFCmpLe(dst, ty, lhs, rhs)) end,
        [Sem.SemTF64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFCmpLe(dst, ty, lhs, rhs)) end,
    })

    local lower_gt_cmd = pvm.phase("sem_to_back_gt_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpGt(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpGt(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpGt(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpGt(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpGt(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpGt(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpGt(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpGt(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpGt(dst, ty, lhs, rhs)) end,
        [Sem.SemTF32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFCmpGt(dst, ty, lhs, rhs)) end,
        [Sem.SemTF64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFCmpGt(dst, ty, lhs, rhs)) end,
    })

    local lower_ge_cmd = pvm.phase("sem_to_back_ge_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpGe(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpGe(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpGe(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSIcmpGe(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpGe(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpGe(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpGe(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpGe(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUIcmpGe(dst, ty, lhs, rhs)) end,
        [Sem.SemTF32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFCmpGe(dst, ty, lhs, rhs)) end,
        [Sem.SemTF64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFCmpGe(dst, ty, lhs, rhs)) end,
    })

    local lower_eq_cmd = pvm.phase("sem_to_back_eq_cmd", {
        [Sem.SemTBool] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTPtr] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTPtrTo] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTF32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFCmpEq(dst, ty, lhs, rhs)) end,
        [Sem.SemTF64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFCmpEq(dst, ty, lhs, rhs)) end,
    })

    local lower_ne_cmd = pvm.phase("sem_to_back_ne_cmd", {
        [Sem.SemTBool] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTPtr] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTPtrTo] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIcmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTF32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFCmpNe(dst, ty, lhs, rhs)) end,
        [Sem.SemTF64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdFCmpNe(dst, ty, lhs, rhs)) end,
    })

    local lower_not_cmd = pvm.phase("sem_to_back_not_cmd", {
        [Sem.SemTBool] = function(self, dst, value) return pvm.once(Back.BackCmdBoolNot(dst, value)) end,
    })

    local lower_bnot_cmd = pvm.phase("sem_to_back_bnot_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, value) return pvm.once(Back.BackCmdBnot(dst, ty, value)) end,
        [Sem.SemTI16] = function(self, dst, ty, value) return pvm.once(Back.BackCmdBnot(dst, ty, value)) end,
        [Sem.SemTI32] = function(self, dst, ty, value) return pvm.once(Back.BackCmdBnot(dst, ty, value)) end,
        [Sem.SemTI64] = function(self, dst, ty, value) return pvm.once(Back.BackCmdBnot(dst, ty, value)) end,
        [Sem.SemTU8] = function(self, dst, ty, value) return pvm.once(Back.BackCmdBnot(dst, ty, value)) end,
        [Sem.SemTU16] = function(self, dst, ty, value) return pvm.once(Back.BackCmdBnot(dst, ty, value)) end,
        [Sem.SemTU32] = function(self, dst, ty, value) return pvm.once(Back.BackCmdBnot(dst, ty, value)) end,
        [Sem.SemTU64] = function(self, dst, ty, value) return pvm.once(Back.BackCmdBnot(dst, ty, value)) end,
        [Sem.SemTIndex] = function(self, dst, ty, value) return pvm.once(Back.BackCmdBnot(dst, ty, value)) end,
    })

    local lower_and_cmd = pvm.phase("sem_to_back_and_cmd", {
        [Sem.SemTBool] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBand(dst, ty, lhs, rhs)) end,
    })

    local lower_or_cmd = pvm.phase("sem_to_back_or_cmd", {
        [Sem.SemTBool] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBor(dst, ty, lhs, rhs)) end,
    })

    local lower_band_cmd = pvm.phase("sem_to_back_band_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBand(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBand(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBand(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBand(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBand(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBand(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBand(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBand(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBand(dst, ty, lhs, rhs)) end,
    })

    local lower_bor_cmd = pvm.phase("sem_to_back_bor_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBor(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBor(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBor(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBor(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBor(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBor(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBor(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBor(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBor(dst, ty, lhs, rhs)) end,
    })

    local lower_bxor_cmd = pvm.phase("sem_to_back_bxor_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBxor(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBxor(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBxor(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBxor(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBxor(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBxor(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBxor(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBxor(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBxor(dst, ty, lhs, rhs)) end,
    })

    local lower_shl_cmd = pvm.phase("sem_to_back_shl_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIshl(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIshl(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIshl(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIshl(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIshl(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIshl(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIshl(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIshl(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdIshl(dst, ty, lhs, rhs)) end,
    })

    local lower_lshr_cmd = pvm.phase("sem_to_back_lshr_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdUshr(dst, ty, lhs, rhs)) end,
    })

    local lower_ashr_cmd = pvm.phase("sem_to_back_ashr_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTI16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTI32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTI64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTU8] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTU16] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTU32] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTU64] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSshr(dst, ty, lhs, rhs)) end,
        [Sem.SemTIndex] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdSshr(dst, ty, lhs, rhs)) end,
    })

    return {
        lower_neg_cmd = lower_neg_cmd,
        lower_add_cmd = lower_add_cmd,
        lower_sub_cmd = lower_sub_cmd,
        lower_mul_cmd = lower_mul_cmd,
        lower_div_cmd = lower_div_cmd,
        lower_rem_cmd = lower_rem_cmd,
        lower_lt_cmd = lower_lt_cmd,
        lower_le_cmd = lower_le_cmd,
        lower_gt_cmd = lower_gt_cmd,
        lower_ge_cmd = lower_ge_cmd,
        lower_eq_cmd = lower_eq_cmd,
        lower_ne_cmd = lower_ne_cmd,
        lower_not_cmd = lower_not_cmd,
        lower_bnot_cmd = lower_bnot_cmd,
        lower_and_cmd = lower_and_cmd,
        lower_or_cmd = lower_or_cmd,
        lower_band_cmd = lower_band_cmd,
        lower_bor_cmd = lower_bor_cmd,
        lower_bxor_cmd = lower_bxor_cmd,
        lower_shl_cmd = lower_shl_cmd,
        lower_lshr_cmd = lower_lshr_cmd,
        lower_ashr_cmd = lower_ashr_cmd,
    }
end

return M
