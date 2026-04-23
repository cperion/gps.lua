package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.Define(T)
    local Sem = T.MoonliftSem

    local lower_type_default_residence
    local lower_binding_residence
    local lower_back_binding
    local lower_view_entries
    local lower_place_entries
    local lower_index_base_entries
    local lower_domain_entries
    local lower_field_init_entries
    local lower_switch_stmt_arm_entries
    local lower_switch_expr_arm_entries
    local lower_loop_update_entries
    local lower_expr_entries
    local lower_stmt_entries
    local lower_loop_entries
    local lower_func_residence_plan

    local function one_type_default_residence(node)
        return pvm.one(lower_type_default_residence(node))
    end

    local function one_binding_residence(node)
        return pvm.one(lower_binding_residence(node))
    end

    local function one_back_binding(node, residence_plan)
        return pvm.one(lower_back_binding(node, residence_plan))
    end

    local function one_view_entries(node)
        return pvm.one(lower_view_entries(node))
    end

    local function one_place_entries(node)
        return pvm.one(lower_place_entries(node))
    end

    local function one_index_base_entries(node)
        return pvm.one(lower_index_base_entries(node))
    end

    local function one_domain_entries(node)
        return pvm.one(lower_domain_entries(node))
    end

    local function one_field_init_entries(node)
        return pvm.one(lower_field_init_entries(node))
    end

    local function one_switch_stmt_arm_entries(node)
        return pvm.one(lower_switch_stmt_arm_entries(node))
    end

    local function one_switch_expr_arm_entries(node)
        return pvm.one(lower_switch_expr_arm_entries(node))
    end

    local function one_loop_update_entries(node)
        return pvm.one(lower_loop_update_entries(node))
    end

    local function one_expr_entries(node)
        return pvm.one(lower_expr_entries(node))
    end

    local function one_stmt_entries(node)
        return pvm.one(lower_stmt_entries(node))
    end

    local function one_loop_entries(node)
        return pvm.one(lower_loop_entries(node))
    end

    local function append_entries(dst, src)
        for i = 1, #src do
            dst[#dst + 1] = src[i]
        end
    end

    local function concat_entries(...)
        local out = {}
        for i = 1, select("#", ...) do
            append_entries(out, select(i, ...))
        end
        return out
    end

    local function expr_entry_list(nodes)
        local out = {}
        for i = 1, #nodes do
            append_entries(out, one_expr_entries(nodes[i]))
        end
        return out
    end

    local function stmt_entry_list(nodes)
        local out = {}
        for i = 1, #nodes do
            append_entries(out, one_stmt_entries(nodes[i]))
        end
        return out
    end

    local function field_init_entry_list(nodes)
        local out = {}
        for i = 1, #nodes do
            append_entries(out, one_field_init_entries(nodes[i]))
        end
        return out
    end

    local function switch_stmt_arm_entry_list(nodes)
        local out = {}
        for i = 1, #nodes do
            append_entries(out, one_switch_stmt_arm_entries(nodes[i]))
        end
        return out
    end

    local function switch_expr_arm_entry_list(nodes)
        local out = {}
        for i = 1, #nodes do
            append_entries(out, one_switch_expr_arm_entries(nodes[i]))
        end
        return out
    end

    local function loop_update_entry_list(nodes)
        local out = {}
        for i = 1, #nodes do
            append_entries(out, one_loop_update_entries(nodes[i]))
        end
        return out
    end

    local function binding_residence(binding, residence_plan)
        if residence_plan ~= nil then
            for i = 1, #residence_plan.entries do
                local entry = residence_plan.entries[i]
                if entry.binding == binding then
                    return entry.residence
                end
            end
        end
        return one_binding_residence(binding)
    end

    local function explicit_entry(binding, residence)
        return Sem.SemResidenceEntry(binding, residence)
    end

    local function entry(binding)
        return explicit_entry(binding, one_binding_residence(binding))
    end

    local function merged_residence(lhs, rhs)
        if lhs == Sem.SemResidenceStack or rhs == Sem.SemResidenceStack then
            return Sem.SemResidenceStack
        end
        return Sem.SemResidenceValue
    end

    local function normalized_entries(entries)
        local out = {}
        for i = 1, #entries do
            local next_entry = entries[i]
            local found = false
            for j = 1, #out do
                local prev = out[j]
                if prev.binding == next_entry.binding then
                    out[j] = explicit_entry(prev.binding, merged_residence(prev.residence, next_entry.residence))
                    found = true
                    break
                end
            end
            if not found then
                out[#out + 1] = next_entry
            end
        end
        return out
    end

    local function carry_entry(loop_id, carry)
        return entry(Sem.SemBindLoopCarry(loop_id, carry.port_id, carry.name, carry.ty))
    end

    local function index_entry(loop)
        return entry(Sem.SemBindLoopIndex(loop.loop_id, loop.index_port.name, loop.index_port.ty))
    end

    local function func_param_entry_list(params)
        local out = {}
        for i = 1, #params do
            local param = params[i]
            out[#out + 1] = entry(Sem.SemBindArg(i - 1, param.name, param.ty))
        end
        return out
    end

    local function loop_carry_entry_list(loop_id, carries)
        local out = {}
        for i = 1, #carries do
            out[#out + 1] = carry_entry(loop_id, carries[i])
        end
        return out
    end

    lower_type_default_residence = pvm.phase("moonlift_sem_residence_type_default", {
        [Sem.SemTBool] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTI8] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTI16] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTI32] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTI64] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTU8] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTU16] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTU32] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTU64] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTF32] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTF64] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTPtr] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTIndex] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTPtrTo] = function() return pvm.once(Sem.SemResidenceValue) end,
        [Sem.SemTVoid] = function() return pvm.once(Sem.SemResidenceStack) end,
        [Sem.SemTArray] = function() return pvm.once(Sem.SemResidenceStack) end,
        [Sem.SemTSlice] = function() return pvm.once(Sem.SemResidenceStack) end,
        [Sem.SemTView] = function() return pvm.once(Sem.SemResidenceStack) end,
        [Sem.SemTFunc] = function() return pvm.once(Sem.SemResidenceStack) end,
        [Sem.SemTNamed] = function() return pvm.once(Sem.SemResidenceStack) end,
    })

    lower_binding_residence = pvm.phase("moonlift_sem_residence_binding", {
        [Sem.SemBindLocalValue] = function(self)
            return pvm.once(one_type_default_residence(self.ty))
        end,
        [Sem.SemBindLocalCell] = function()
            return pvm.once(Sem.SemResidenceStack)
        end,
        [Sem.SemBindArg] = function(self)
            return pvm.once(one_type_default_residence(self.ty))
        end,
        [Sem.SemBindLoopCarry] = function(self)
            return pvm.once(one_type_default_residence(self.ty))
        end,
        [Sem.SemBindLoopIndex] = function(self)
            return pvm.once(one_type_default_residence(self.ty))
        end,
        [Sem.SemBindGlobalFunc] = function()
            return pvm.once(Sem.SemResidenceValue)
        end,
        [Sem.SemBindGlobalConst] = function()
            return pvm.once(Sem.SemResidenceValue)
        end,
        [Sem.SemBindGlobalStatic] = function()
            return pvm.once(Sem.SemResidenceStack)
        end,
        [Sem.SemBindExtern] = function()
            return pvm.once(Sem.SemResidenceValue)
        end,
    })

    lower_back_binding = pvm.phase("moonlift_sem_back_binding", {
        [Sem.SemBindLocalValue] = function(self, residence_plan)
            if binding_residence(self, residence_plan) == Sem.SemResidenceStack then
                return pvm.once(Sem.SemBackLocalStored(self.id, self.name, self.ty))
            end
            return pvm.once(Sem.SemBackLocalValue(self.id, self.name, self.ty))
        end,
        [Sem.SemBindLocalCell] = function(self)
            return pvm.once(Sem.SemBackLocalCell(self.id, self.name, self.ty))
        end,
        [Sem.SemBindArg] = function(self, residence_plan)
            if binding_residence(self, residence_plan) == Sem.SemResidenceStack then
                return pvm.once(Sem.SemBackArgStored(self.index, self.name, self.ty))
            end
            return pvm.once(Sem.SemBackArgValue(self.index, self.name, self.ty))
        end,
        [Sem.SemBindLoopCarry] = function(self, residence_plan)
            if binding_residence(self, residence_plan) == Sem.SemResidenceStack then
                return pvm.once(Sem.SemBackLoopCarryStored(self.loop_id, self.port_id, self.name, self.ty))
            end
            return pvm.once(Sem.SemBackLoopCarryValue(self.loop_id, self.port_id, self.name, self.ty))
        end,
        [Sem.SemBindLoopIndex] = function(self, residence_plan)
            if binding_residence(self, residence_plan) == Sem.SemResidenceStack then
                return pvm.once(Sem.SemBackLoopIndexStored(self.loop_id, self.name, self.ty))
            end
            return pvm.once(Sem.SemBackLoopIndexValue(self.loop_id, self.name, self.ty))
        end,
        [Sem.SemBindGlobalFunc] = function(self)
            return pvm.once(Sem.SemBackGlobalFunc(self.module_name, self.item_name, self.ty))
        end,
        [Sem.SemBindGlobalConst] = function(self)
            return pvm.once(Sem.SemBackGlobalConst(self.module_name, self.item_name, self.ty))
        end,
        [Sem.SemBindGlobalStatic] = function(self)
            return pvm.once(Sem.SemBackGlobalStatic(self.module_name, self.item_name, self.ty))
        end,
        [Sem.SemBindExtern] = function(self)
            return pvm.once(Sem.SemBackExtern(self.symbol, self.ty))
        end,
    })

    lower_view_entries = pvm.phase("moonlift_sem_residence_view_entries", {
        [Sem.SemViewValue] = function(self)
            return pvm.once(one_expr_entries(self.base))
        end,
        [Sem.SemViewContiguous] = function(self)
            return pvm.once(concat_entries(one_expr_entries(self.data), one_expr_entries(self.len)))
        end,
        [Sem.SemViewStrided] = function(self)
            return pvm.once(concat_entries(one_expr_entries(self.data), one_expr_entries(self.len), one_expr_entries(self.stride)))
        end,
        [Sem.SemViewWindow] = function(self)
            return pvm.once(concat_entries(one_view_entries(self.base), one_expr_entries(self.start), one_expr_entries(self.len)))
        end,
        [Sem.SemViewInterleaved] = function(self)
            return pvm.once(concat_entries(
                one_expr_entries(self.data),
                one_expr_entries(self.len),
                one_expr_entries(self.stride),
                one_expr_entries(self.lane)
            ))
        end,
    })

    lower_place_entries = pvm.phase("moonlift_sem_residence_place_entries", {
        [Sem.SemPlaceBinding] = function(self)
            return pvm.once({ explicit_entry(self.binding, Sem.SemResidenceStack) })
        end,
        [Sem.SemPlaceDeref] = function(self)
            return pvm.once(one_expr_entries(self.base))
        end,
        [Sem.SemPlaceField] = function(self)
            return pvm.once(one_place_entries(self.base))
        end,
        [Sem.SemPlaceIndex] = function(self)
            return pvm.once(concat_entries(one_index_base_entries(self.base), one_expr_entries(self.index)))
        end,
    })

    lower_index_base_entries = pvm.phase("moonlift_sem_residence_index_base_entries", {
        [Sem.SemIndexBasePlace] = function(self)
            return pvm.once(one_place_entries(self.base))
        end,
        [Sem.SemIndexBaseView] = function(self)
            return pvm.once(one_view_entries(self.view))
        end,
    })

    lower_domain_entries = pvm.phase("moonlift_sem_residence_domain_entries", {
        [Sem.SemDomainRange] = function(self)
            return pvm.once(one_expr_entries(self.stop))
        end,
        [Sem.SemDomainRange2] = function(self)
            return pvm.once(concat_entries(one_expr_entries(self.start), one_expr_entries(self.stop)))
        end,
        [Sem.SemDomainView] = function(self)
            return pvm.once(one_view_entries(self.view))
        end,
        [Sem.SemDomainZipEq] = function(self)
            local out = {}
            for i = 1, #self.views do
                append_entries(out, one_view_entries(self.views[i]))
            end
            return pvm.once(out)
        end,
    })

    lower_field_init_entries = pvm.phase("moonlift_sem_residence_field_init_entries", {
        [Sem.SemFieldInit] = function(self)
            return pvm.once(one_expr_entries(self.value))
        end,
    })

    lower_switch_stmt_arm_entries = pvm.phase("moonlift_sem_residence_switch_stmt_arm_entries", {
        [Sem.SemSwitchStmtArm] = function(self)
            return pvm.once(concat_entries(one_expr_entries(self.key), stmt_entry_list(self.body)))
        end,
    })

    lower_switch_expr_arm_entries = pvm.phase("moonlift_sem_residence_switch_expr_arm_entries", {
        [Sem.SemSwitchExprArm] = function(self)
            return pvm.once(concat_entries(one_expr_entries(self.key), stmt_entry_list(self.body), one_expr_entries(self.result)))
        end,
    })

    lower_loop_update_entries = pvm.phase("moonlift_sem_residence_loop_update_entries", {
        [Sem.SemLoopUpdate] = function(self)
            return pvm.once(one_expr_entries(self.value))
        end,
    })

    lower_expr_entries = pvm.phase("moonlift_sem_residence_expr_entries", {
        [Sem.SemExprConstInt] = function() return pvm.once({}) end,
        [Sem.SemExprConstFloat] = function() return pvm.once({}) end,
        [Sem.SemExprConstBool] = function() return pvm.once({}) end,
        [Sem.SemExprNil] = function() return pvm.once({}) end,
        [Sem.SemExprBinding] = function() return pvm.once({}) end,
        [Sem.SemExprNeg] = function(self) return pvm.once(one_expr_entries(self.value)) end,
        [Sem.SemExprNot] = function(self) return pvm.once(one_expr_entries(self.value)) end,
        [Sem.SemExprBNot] = function(self) return pvm.once(one_expr_entries(self.value)) end,
        [Sem.SemExprAddrOf] = function(self) return pvm.once(one_place_entries(self.place)) end,
        [Sem.SemExprDeref] = function(self) return pvm.once(one_expr_entries(self.value)) end,
        [Sem.SemExprAdd] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprSub] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprMul] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprDiv] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprRem] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprEq] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprNe] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprLt] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprLe] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprGt] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprGe] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprAnd] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprOr] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprBitXor] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprBitAnd] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprBitOr] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprShl] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprLShr] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprAShr] = function(self) return pvm.once(concat_entries(one_expr_entries(self.lhs), one_expr_entries(self.rhs))) end,
        [Sem.SemExprCastTo] = function(self) return pvm.once(one_expr_entries(self.value)) end,
        [Sem.SemExprTruncTo] = function(self) return pvm.once(one_expr_entries(self.value)) end,
        [Sem.SemExprZExtTo] = function(self) return pvm.once(one_expr_entries(self.value)) end,
        [Sem.SemExprSExtTo] = function(self) return pvm.once(one_expr_entries(self.value)) end,
        [Sem.SemExprBitcastTo] = function(self) return pvm.once(one_expr_entries(self.value)) end,
        [Sem.SemExprSatCastTo] = function(self) return pvm.once(one_expr_entries(self.value)) end,
        [Sem.SemExprSelect] = function(self)
            return pvm.once(concat_entries(one_expr_entries(self.cond), one_expr_entries(self.then_value), one_expr_entries(self.else_value)))
        end,
        [Sem.SemExprIndex] = function(self)
            return pvm.once(concat_entries(one_index_base_entries(self.base), one_expr_entries(self.index)))
        end,
        [Sem.SemExprField] = function(self)
            return pvm.once(one_expr_entries(self.base))
        end,
        [Sem.SemExprLoad] = function(self)
            return pvm.once(one_expr_entries(self.addr))
        end,
        [Sem.SemExprIntrinsicCall] = function(self)
            return pvm.once(expr_entry_list(self.args))
        end,
        [Sem.SemExprCall] = function(self)
            local out = expr_entry_list(self.args)
            if self.target.callee ~= nil then
                append_entries(out, one_expr_entries(self.target.callee))
            end
            return pvm.once(out)
        end,
        [Sem.SemExprAgg] = function(self)
            return pvm.once(field_init_entry_list(self.fields))
        end,
        [Sem.SemExprArrayLit] = function(self)
            return pvm.once(expr_entry_list(self.elems))
        end,
        [Sem.SemExprBlock] = function(self)
            return pvm.once(concat_entries(stmt_entry_list(self.stmts), one_expr_entries(self.result)))
        end,
        [Sem.SemExprIf] = function(self)
            return pvm.once(concat_entries(one_expr_entries(self.cond), one_expr_entries(self.then_expr), one_expr_entries(self.else_expr)))
        end,
        [Sem.SemExprSwitch] = function(self)
            return pvm.once(concat_entries(one_expr_entries(self.value), switch_expr_arm_entry_list(self.arms), one_expr_entries(self.default_expr)))
        end,
        [Sem.SemExprLoop] = function(self)
            return pvm.once(one_loop_entries(self.loop))
        end,
    })

    lower_stmt_entries = pvm.phase("moonlift_sem_residence_stmt_entries", {
        [Sem.SemStmtLet] = function(self)
            return pvm.once(concat_entries(
                { entry(Sem.SemBindLocalValue(self.id, self.name, self.ty)) },
                one_expr_entries(self.init)
            ))
        end,
        [Sem.SemStmtVar] = function(self)
            return pvm.once(concat_entries(
                { entry(Sem.SemBindLocalCell(self.id, self.name, self.ty)) },
                one_expr_entries(self.init)
            ))
        end,
        [Sem.SemStmtSet] = function(self)
            return pvm.once(concat_entries(one_place_entries(self.place), one_expr_entries(self.value)))
        end,
        [Sem.SemStmtExpr] = function(self)
            return pvm.once(one_expr_entries(self.expr))
        end,
        [Sem.SemStmtIf] = function(self)
            return pvm.once(concat_entries(one_expr_entries(self.cond), stmt_entry_list(self.then_body), stmt_entry_list(self.else_body)))
        end,
        [Sem.SemStmtSwitch] = function(self)
            return pvm.once(concat_entries(one_expr_entries(self.value), switch_stmt_arm_entry_list(self.arms), stmt_entry_list(self.default_body)))
        end,
        [Sem.SemStmtAssert] = function(self)
            return pvm.once(one_expr_entries(self.cond))
        end,
        [Sem.SemStmtReturnVoid] = function()
            return pvm.once({})
        end,
        [Sem.SemStmtReturnValue] = function(self)
            return pvm.once(one_expr_entries(self.value))
        end,
        [Sem.SemStmtBreak] = function()
            return pvm.once({})
        end,
        [Sem.SemStmtBreakValue] = function(self)
            return pvm.once(one_expr_entries(self.value))
        end,
        [Sem.SemStmtContinue] = function()
            return pvm.once({})
        end,
        [Sem.SemStmtLoop] = function(self)
            return pvm.once(one_loop_entries(self.loop))
        end,
    })

    lower_loop_entries = pvm.phase("moonlift_sem_residence_loop_entries", {
        [Sem.SemLoopWhileStmt] = function(self)
            return pvm.once(concat_entries(
                loop_carry_entry_list(self.loop_id, self.carries),
                one_expr_entries(self.cond),
                stmt_entry_list(self.body),
                loop_update_entry_list(self.next)
            ))
        end,
        [Sem.SemLoopOverStmt] = function(self)
            return pvm.once(concat_entries(
                { index_entry(self) },
                loop_carry_entry_list(self.loop_id, self.carries),
                one_domain_entries(self.domain),
                stmt_entry_list(self.body),
                loop_update_entry_list(self.next)
            ))
        end,
        [Sem.SemLoopWhileExpr] = function(self)
            return pvm.once(concat_entries(
                loop_carry_entry_list(self.loop_id, self.carries),
                one_expr_entries(self.cond),
                stmt_entry_list(self.body),
                loop_update_entry_list(self.next),
                one_expr_entries(self.result)
            ))
        end,
        [Sem.SemLoopOverExpr] = function(self)
            return pvm.once(concat_entries(
                { index_entry(self) },
                loop_carry_entry_list(self.loop_id, self.carries),
                one_domain_entries(self.domain),
                stmt_entry_list(self.body),
                loop_update_entry_list(self.next),
                one_expr_entries(self.result)
            ))
        end,
    })

    lower_func_residence_plan = pvm.phase("moonlift_sem_residence_func_plan", {
        [Sem.SemFuncLocal] = function(self)
            return pvm.once(Sem.SemResidencePlan(normalized_entries(concat_entries(func_param_entry_list(self.params), stmt_entry_list(self.body)))))
        end,
        [Sem.SemFuncExport] = function(self)
            return pvm.once(Sem.SemResidencePlan(normalized_entries(concat_entries(func_param_entry_list(self.params), stmt_entry_list(self.body)))))
        end,
    })

    return {
        lower_type_default_residence = lower_type_default_residence,
        lower_binding_residence = lower_binding_residence,
        lower_back_binding = lower_back_binding,
        lower_view_entries = lower_view_entries,
        lower_place_entries = lower_place_entries,
        lower_index_base_entries = lower_index_base_entries,
        lower_domain_entries = lower_domain_entries,
        lower_expr_entries = lower_expr_entries,
        lower_stmt_entries = lower_stmt_entries,
        lower_loop_entries = lower_loop_entries,
        lower_func_residence_plan = lower_func_residence_plan,
    }
end

return M
