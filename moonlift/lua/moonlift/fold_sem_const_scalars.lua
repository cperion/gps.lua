package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.Define(T, env)
    local Sem = T.MoonliftSem

    local fold_view
    local fold_place
    local fold_index_base
    local fold_call_target
    local fold_field_init
    local fold_switch_stmt_arm
    local fold_switch_expr_arm
    local fold_domain
    local fold_expr
    local fold_stmt
    local fold_loop
    local fold_func
    local fold_item
    local fold_module

    local function one_const_eval(node, const_env)
        return env.one_const_eval(node, const_env, nil, nil)
    end

    local function one_view(node, const_env)
        return pvm.one(fold_view(node, const_env))
    end

    local function one_place(node, const_env)
        return pvm.one(fold_place(node, const_env))
    end

    local function one_index_base(node, const_env)
        return pvm.one(fold_index_base(node, const_env))
    end

    local function one_call_target(node, const_env)
        return pvm.one(fold_call_target(node, const_env))
    end

    local function one_field_init(node, const_env)
        return pvm.one(fold_field_init(node, const_env))
    end

    local function one_switch_stmt_arm(node, const_env)
        return pvm.one(fold_switch_stmt_arm(node, const_env))
    end

    local function one_switch_expr_arm(node, const_env)
        return pvm.one(fold_switch_expr_arm(node, const_env))
    end

    local function one_domain(node, const_env)
        return pvm.one(fold_domain(node, const_env))
    end

    local function one_expr(node, const_env)
        return pvm.one(fold_expr(node, const_env))
    end

    local function one_stmt(node, const_env)
        return pvm.one(fold_stmt(node, const_env))
    end

    local function one_loop(node, const_env)
        return pvm.one(fold_loop(node, const_env))
    end

    local function one_func(node, const_env)
        return pvm.one(fold_func(node, const_env))
    end

    local function one_item(node, const_env)
        return pvm.one(fold_item(node, const_env))
    end

    local function expr_list(nodes, const_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_expr(nodes[i], const_env)
        end
        return out
    end

    local function stmt_list(nodes, const_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_stmt(nodes[i], const_env)
        end
        return out
    end

    local function field_init_list(nodes, const_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_field_init(nodes[i], const_env)
        end
        return out
    end

    local function switch_stmt_arm_list(nodes, const_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_switch_stmt_arm(nodes[i], const_env)
        end
        return out
    end

    local function switch_expr_arm_list(nodes, const_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_switch_expr_arm(nodes[i], const_env)
        end
        return out
    end

    local function loop_update_list(nodes, const_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = Sem.SemLoopUpdate(nodes[i].port_id, one_expr(nodes[i].value, const_env))
        end
        return out
    end

    local function loop_carry_list(nodes, const_env)
        local out = {}
        for i = 1, #nodes do
            local carry = nodes[i]
            out[i] = Sem.SemLoopCarryPort(carry.port_id, carry.name, carry.ty, one_expr(carry.init, const_env))
        end
        return out
    end

    local const_value_to_expr = pvm.phase("moonlift_sem_const_scalar_to_expr", {
        [Sem.SemConstInt] = function(self)
            return pvm.once(Sem.SemExprConstInt(self.ty, self.raw))
        end,
        [Sem.SemConstFloat] = function(self)
            return pvm.once(Sem.SemExprConstFloat(self.ty, self.raw))
        end,
        [Sem.SemConstBool] = function(self)
            return pvm.once(Sem.SemExprConstBool(self.value))
        end,
        [Sem.SemConstNil] = function(self)
            return pvm.once(Sem.SemExprNil(self.ty))
        end,
        [Sem.SemConstAgg] = function()
            return pvm.once(nil)
        end,
        [Sem.SemConstArray] = function()
            return pvm.once(nil)
        end,
    })

    local function maybe_fold_scalar(expr, const_env)
        local ok, value = pcall(one_const_eval, expr, const_env)
        if not ok then
            return expr
        end
        local folded = pvm.one(const_value_to_expr(value))
        if folded ~= nil then
            return folded
        end
        return expr
    end

    fold_view = pvm.phase("moonlift_sem_fold_const_scalars_view", {
        [Sem.SemViewValue] = function(self, const_env)
            return pvm.once(Sem.SemViewValue(one_expr(self.base, const_env), self.elem))
        end,
        [Sem.SemViewContiguous] = function(self, const_env)
            return pvm.once(Sem.SemViewContiguous(one_expr(self.data, const_env), self.elem, one_expr(self.len, const_env)))
        end,
        [Sem.SemViewStrided] = function(self, const_env)
            return pvm.once(Sem.SemViewStrided(one_expr(self.data, const_env), self.elem, one_expr(self.len, const_env), one_expr(self.stride, const_env)))
        end,
        [Sem.SemViewWindow] = function(self, const_env)
            return pvm.once(Sem.SemViewWindow(one_view(self.base, const_env), one_expr(self.start, const_env), one_expr(self.len, const_env)))
        end,
        [Sem.SemViewInterleaved] = function(self, const_env)
            return pvm.once(Sem.SemViewInterleaved(one_expr(self.data, const_env), self.elem, one_expr(self.len, const_env), one_expr(self.stride, const_env), one_expr(self.lane, const_env)))
        end,
    })

    fold_place = pvm.phase("moonlift_sem_fold_const_scalars_place", {
        [Sem.SemPlaceBinding] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemPlaceDeref] = function(self, const_env)
            return pvm.once(Sem.SemPlaceDeref(one_expr(self.base, const_env), self.elem))
        end,
        [Sem.SemPlaceField] = function(self, const_env)
            return pvm.once(Sem.SemPlaceField(one_place(self.base, const_env), self.field))
        end,
        [Sem.SemPlaceIndex] = function(self, const_env)
            return pvm.once(Sem.SemPlaceIndex(one_index_base(self.base, const_env), one_expr(self.index, const_env), self.ty))
        end,
    })

    fold_index_base = pvm.phase("moonlift_sem_fold_const_scalars_index_base", {
        [Sem.SemIndexBasePlace] = function(self, const_env)
            return pvm.once(Sem.SemIndexBasePlace(one_place(self.base, const_env), self.elem))
        end,
        [Sem.SemIndexBaseView] = function(self, const_env)
            return pvm.once(Sem.SemIndexBaseView(one_view(self.view, const_env)))
        end,
    })

    fold_call_target = pvm.phase("moonlift_sem_fold_const_scalars_call_target", {
        [Sem.SemCallDirect] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemCallExtern] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemCallIndirect] = function(self, const_env)
            return pvm.once(Sem.SemCallIndirect(one_expr(self.callee, const_env), self.fn_ty))
        end,
    })

    fold_field_init = pvm.phase("moonlift_sem_fold_const_scalars_field_init", {
        [Sem.SemFieldInit] = function(self, const_env)
            return pvm.once(Sem.SemFieldInit(self.name, one_expr(self.value, const_env)))
        end,
    })

    fold_switch_stmt_arm = pvm.phase("moonlift_sem_fold_const_scalars_switch_stmt_arm", {
        [Sem.SemSwitchStmtArm] = function(self, const_env)
            return pvm.once(Sem.SemSwitchStmtArm(one_expr(self.key, const_env), stmt_list(self.body, const_env)))
        end,
    })

    fold_switch_expr_arm = pvm.phase("moonlift_sem_fold_const_scalars_switch_expr_arm", {
        [Sem.SemSwitchExprArm] = function(self, const_env)
            return pvm.once(Sem.SemSwitchExprArm(one_expr(self.key, const_env), stmt_list(self.body, const_env), one_expr(self.result, const_env)))
        end,
    })

    fold_domain = pvm.phase("moonlift_sem_fold_const_scalars_domain", {
        [Sem.SemDomainRange] = function(self, const_env)
            return pvm.once(Sem.SemDomainRange(one_expr(self.stop, const_env)))
        end,
        [Sem.SemDomainRange2] = function(self, const_env)
            return pvm.once(Sem.SemDomainRange2(one_expr(self.start, const_env), one_expr(self.stop, const_env)))
        end,
        [Sem.SemDomainView] = function(self, const_env)
            return pvm.once(Sem.SemDomainView(one_view(self.view, const_env)))
        end,
        [Sem.SemDomainZipEq] = function(self, const_env)
            local out = {}
            for i = 1, #self.views do
                out[i] = one_view(self.views[i], const_env)
            end
            return pvm.once(Sem.SemDomainZipEq(out))
        end,
    })

    fold_expr = pvm.phase("moonlift_sem_fold_const_scalars_expr", {
        [Sem.SemExprConstInt] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemExprConstFloat] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemExprConstBool] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemExprNil] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemExprBinding] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(self, const_env))
        end,
        [Sem.SemExprNeg] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprNeg(self.ty, one_expr(self.value, const_env)), const_env))
        end,
        [Sem.SemExprNot] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprNot(self.ty, one_expr(self.value, const_env)), const_env))
        end,
        [Sem.SemExprBNot] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprBNot(self.ty, one_expr(self.value, const_env)), const_env))
        end,
        [Sem.SemExprAddrOf] = function(self, const_env)
            return pvm.once(Sem.SemExprAddrOf(one_place(self.place, const_env), self.ty))
        end,
        [Sem.SemExprDeref] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprDeref(self.ty, one_expr(self.value, const_env)), const_env))
        end,
        [Sem.SemExprAdd] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprAdd(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprSub] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprSub(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprMul] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprMul(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprDiv] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprDiv(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprRem] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprRem(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprEq] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprEq(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprNe] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprNe(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprLt] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprLt(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprLe] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprLe(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprGt] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprGt(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprGe] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprGe(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprAnd] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprAnd(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprOr] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprOr(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprBitAnd] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprBitAnd(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprBitOr] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprBitOr(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprBitXor] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprBitXor(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprShl] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprShl(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprLShr] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprLShr(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprAShr] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprAShr(self.ty, one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)), const_env))
        end,
        [Sem.SemExprCastTo] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprCastTo(self.ty, one_expr(self.value, const_env)), const_env))
        end,
        [Sem.SemExprTruncTo] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprTruncTo(self.ty, one_expr(self.value, const_env)), const_env))
        end,
        [Sem.SemExprZExtTo] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprZExtTo(self.ty, one_expr(self.value, const_env)), const_env))
        end,
        [Sem.SemExprSExtTo] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprSExtTo(self.ty, one_expr(self.value, const_env)), const_env))
        end,
        [Sem.SemExprBitcastTo] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprBitcastTo(self.ty, one_expr(self.value, const_env)), const_env))
        end,
        [Sem.SemExprSatCastTo] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprSatCastTo(self.ty, one_expr(self.value, const_env)), const_env))
        end,
        [Sem.SemExprSelect] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprSelect(one_expr(self.cond, const_env), one_expr(self.then_value, const_env), one_expr(self.else_value, const_env), self.ty), const_env))
        end,
        [Sem.SemExprIndex] = function(self, const_env)
            return pvm.once(Sem.SemExprIndex(one_index_base(self.base, const_env), one_expr(self.index, const_env), self.ty))
        end,
        [Sem.SemExprField] = function(self, const_env)
            return pvm.once(Sem.SemExprField(one_expr(self.base, const_env), self.field))
        end,
        [Sem.SemExprLoad] = function(self, const_env)
            return pvm.once(Sem.SemExprLoad(self.ty, one_expr(self.addr, const_env)))
        end,
        [Sem.SemExprIntrinsicCall] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprIntrinsicCall(self.op, self.ty, expr_list(self.args, const_env)), const_env))
        end,
        [Sem.SemExprCall] = function(self, const_env)
            return pvm.once(Sem.SemExprCall(one_call_target(self.target, const_env), self.ty, expr_list(self.args, const_env)))
        end,
        [Sem.SemExprAgg] = function(self, const_env)
            return pvm.once(Sem.SemExprAgg(self.ty, field_init_list(self.fields, const_env)))
        end,
        [Sem.SemExprArrayLit] = function(self, const_env)
            return pvm.once(Sem.SemExprArrayLit(self.elem_ty, expr_list(self.elems, const_env)))
        end,
        [Sem.SemExprBlock] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprBlock(stmt_list(self.stmts, const_env), one_expr(self.result, const_env), self.ty), const_env))
        end,
        [Sem.SemExprIf] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprIf(one_expr(self.cond, const_env), one_expr(self.then_expr, const_env), one_expr(self.else_expr, const_env), self.ty), const_env))
        end,
        [Sem.SemExprSwitch] = function(self, const_env)
            return pvm.once(maybe_fold_scalar(Sem.SemExprSwitch(one_expr(self.value, const_env), switch_expr_arm_list(self.arms, const_env), one_expr(self.default_expr, const_env), self.ty), const_env))
        end,
        [Sem.SemExprLoop] = function(self, const_env)
            return pvm.once(Sem.SemExprLoop(one_loop(self.loop, const_env), self.ty))
        end,
    })

    fold_stmt = pvm.phase("moonlift_sem_fold_const_scalars_stmt", {
        [Sem.SemStmtLet] = function(self, const_env)
            return pvm.once(Sem.SemStmtLet(self.id, self.name, self.ty, one_expr(self.init, const_env)))
        end,
        [Sem.SemStmtVar] = function(self, const_env)
            return pvm.once(Sem.SemStmtVar(self.id, self.name, self.ty, one_expr(self.init, const_env)))
        end,
        [Sem.SemStmtSet] = function(self, const_env)
            return pvm.once(Sem.SemStmtSet(one_place(self.place, const_env), one_expr(self.value, const_env)))
        end,
        [Sem.SemStmtExpr] = function(self, const_env)
            return pvm.once(Sem.SemStmtExpr(one_expr(self.expr, const_env)))
        end,
        [Sem.SemStmtIf] = function(self, const_env)
            return pvm.once(Sem.SemStmtIf(one_expr(self.cond, const_env), stmt_list(self.then_body, const_env), stmt_list(self.else_body, const_env)))
        end,
        [Sem.SemStmtSwitch] = function(self, const_env)
            return pvm.once(Sem.SemStmtSwitch(one_expr(self.value, const_env), switch_stmt_arm_list(self.arms, const_env), stmt_list(self.default_body, const_env)))
        end,
        [Sem.SemStmtAssert] = function(self, const_env)
            return pvm.once(Sem.SemStmtAssert(one_expr(self.cond, const_env)))
        end,
        [Sem.SemStmtReturnVoid] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemStmtReturnValue] = function(self, const_env)
            return pvm.once(Sem.SemStmtReturnValue(one_expr(self.value, const_env)))
        end,
        [Sem.SemStmtBreak] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemStmtBreakValue] = function(self, const_env)
            return pvm.once(Sem.SemStmtBreakValue(one_expr(self.value, const_env)))
        end,
        [Sem.SemStmtContinue] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemStmtLoop] = function(self, const_env)
            return pvm.once(Sem.SemStmtLoop(one_loop(self.loop, const_env)))
        end,
    })

    fold_loop = pvm.phase("moonlift_sem_fold_const_scalars_loop", {
        [Sem.SemLoopWhileStmt] = function(self, const_env)
            return pvm.once(Sem.SemLoopWhileStmt(self.loop_id, loop_carry_list(self.carries, const_env), one_expr(self.cond, const_env), stmt_list(self.body, const_env), loop_update_list(self.next, const_env)))
        end,
        [Sem.SemLoopOverStmt] = function(self, const_env)
            return pvm.once(Sem.SemLoopOverStmt(self.loop_id, self.index_port, one_domain(self.domain, const_env), loop_carry_list(self.carries, const_env), stmt_list(self.body, const_env), loop_update_list(self.next, const_env)))
        end,
        [Sem.SemLoopWhileExpr] = function(self, const_env)
            return pvm.once(Sem.SemLoopWhileExpr(self.loop_id, loop_carry_list(self.carries, const_env), one_expr(self.cond, const_env), stmt_list(self.body, const_env), loop_update_list(self.next, const_env), self.exit, one_expr(self.result, const_env)))
        end,
        [Sem.SemLoopOverExpr] = function(self, const_env)
            return pvm.once(Sem.SemLoopOverExpr(self.loop_id, self.index_port, one_domain(self.domain, const_env), loop_carry_list(self.carries, const_env), stmt_list(self.body, const_env), loop_update_list(self.next, const_env), self.exit, one_expr(self.result, const_env)))
        end,
    })

    fold_func = pvm.phase("moonlift_sem_fold_const_scalars_func", {
        [Sem.SemFuncLocal] = function(self, const_env)
            return pvm.once(Sem.SemFuncLocal(self.name, self.params, self.result, stmt_list(self.body, const_env)))
        end,
        [Sem.SemFuncExport] = function(self, const_env)
            return pvm.once(Sem.SemFuncExport(self.name, self.params, self.result, stmt_list(self.body, const_env)))
        end,
    })

    fold_item = pvm.phase("moonlift_sem_fold_const_scalars_item", {
        [Sem.SemItemFunc] = function(self, const_env)
            return pvm.once(Sem.SemItemFunc(one_func(self.func, const_env)))
        end,
        [Sem.SemItemExtern] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemItemConst] = function(self, const_env)
            return pvm.once(Sem.SemItemConst(Sem.SemConst(self.c.name, self.c.ty, one_expr(self.c.value, const_env))))
        end,
        [Sem.SemItemStatic] = function(self, const_env)
            return pvm.once(Sem.SemItemStatic(Sem.SemStatic(self.s.name, self.s.ty, one_expr(self.s.value, const_env))))
        end,
        [Sem.SemItemImport] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemItemType] = function(self)
            return pvm.once(self)
        end,
    })

    fold_module = pvm.phase("moonlift_sem_fold_const_scalars_module", {
        [Sem.SemModule] = function(self, const_env)
            local items = {}
            for i = 1, #self.items do
                items[i] = one_item(self.items[i], const_env)
            end
            return pvm.once(Sem.SemModule(self.module_name, items))
        end,
    })

    return {
        fold_expr = fold_expr,
        fold_stmt = fold_stmt,
        fold_loop = fold_loop,
        fold_func = fold_func,
        fold_item = fold_item,
        fold_module = fold_module,
    }
end

return M
