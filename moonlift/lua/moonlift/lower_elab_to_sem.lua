package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.Define(T)
    local Elab = T.MoonliftElab
    local Sem = T.MoonliftSem

    local lower_type
    local lower_param
    local lower_binding
    local lower_expr
    local lower_domain
    local lower_stmt
    local lower_loop
    local lower_func
    local lower_extern_func
    local lower_const
    local lower_item
    local lower_module
    local lower_loop_binding
    local lower_loop_next
    local lower_switch_stmt_arm
    local lower_switch_expr_arm
    local lower_field_init
    local sem_field_ref_type
    local elab_expr_type
    local sem_expr_type
    local elab_array_count
    local binding_call_target
    local expr_call_target

    local function one_type(node)
        return pvm.one(lower_type(node))
    end

    local function one_param(node)
        return pvm.one(lower_param(node))
    end

    local function one_binding(node)
        return pvm.one(lower_binding(node))
    end

    local function one_expr(node)
        return pvm.one(lower_expr(node))
    end

    local function one_domain(node)
        return pvm.one(lower_domain(node))
    end

    local function one_stmt(node)
        return pvm.one(lower_stmt(node))
    end

    local function one_loop(node)
        return pvm.one(lower_loop(node))
    end

    local function one_func(node)
        return pvm.one(lower_func(node))
    end

    local function one_extern_func(node)
        return pvm.one(lower_extern_func(node))
    end

    local function one_const(node)
        return pvm.one(lower_const(node))
    end

    local function one_item(node)
        return pvm.one(lower_item(node))
    end

    local function one_module(node)
        return pvm.one(lower_module(node))
    end

    local function one_loop_binding(node)
        return pvm.one(lower_loop_binding(node))
    end

    local function one_loop_next(node)
        return pvm.one(lower_loop_next(node))
    end

    local function one_switch_stmt_arm(node)
        return pvm.one(lower_switch_stmt_arm(node))
    end

    local function one_switch_expr_arm(node)
        return pvm.one(lower_switch_expr_arm(node))
    end

    local function one_field_init(node)
        return pvm.one(lower_field_init(node))
    end

    local function one_sem_field_ref_type(node)
        return pvm.one(sem_field_ref_type(node))
    end

    local function one_elab_expr_type(node)
        return pvm.one(elab_expr_type(node))
    end

    local function one_sem_expr_type(node)
        return pvm.one(sem_expr_type(node))
    end

    local function one_call_target_from_binding(binding, fn_ty)
        return pvm.one(binding_call_target(binding, fn_ty))
    end

    local function one_call_target_from_expr(expr, fn_ty)
        return pvm.one(expr_call_target(expr, fn_ty))
    end

    local function lower_expr_list(nodes)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_expr(nodes[i])
        end
        return out
    end

    local function lower_stmt_list(nodes)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_stmt(nodes[i])
        end
        return out
    end

    local function lower_field_init_list(nodes)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_field_init(nodes[i])
        end
        return out
    end

    local function lower_switch_stmt_arm_list(nodes)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_switch_stmt_arm(nodes[i])
        end
        return out
    end

    local function lower_switch_expr_arm_list(nodes)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_switch_expr_arm(nodes[i])
        end
        return out
    end

    local function indirect_call_target_handler()
        return function(self, fn_ty)
            return pvm.once(Sem.SemCallIndirect(one_expr(self), fn_ty))
        end
    end

    elab_expr_type = pvm.phase("moonlift_elab_expr_type", {
        [Elab.ElabInt] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabFloat] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabBool] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabNil] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabBindingExpr] = function(self) return pvm.once(self.binding.ty) end,
        [Elab.ElabExprNeg] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprNot] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprBNot] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprRef] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprDeref] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprAdd] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprSub] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprMul] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprDiv] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprRem] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprEq] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprNe] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprLt] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprLe] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprGt] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprGe] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprAnd] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprOr] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprBitAnd] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprBitOr] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprBitXor] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprShl] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprLShr] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprAShr] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprCastTo] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprTruncTo] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprZExtTo] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprSExtTo] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprBitcastTo] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabExprSatCastTo] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabCall] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabField] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabIndex] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabAgg] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabArrayLit] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabIfExpr] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabSwitchExpr] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabLoopExprNode] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabBlockExpr] = function(self) return pvm.once(self.ty) end,
    })

    sem_field_ref_type = pvm.phase("moonlift_sem_field_ref_type", {
        [Sem.SemFieldByName] = function(self) return pvm.once(self.ty) end,
        [Sem.SemFieldByOffset] = function(self) return pvm.once(self.ty) end,
    })

    sem_expr_type = pvm.phase("moonlift_sem_expr_type", {
        [Sem.SemExprConstInt] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprConstFloat] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprConstBool] = function() return pvm.once(Sem.SemTBool) end,
        [Sem.SemExprNil] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprBinding] = function(self) return pvm.once(self.binding.ty) end,
        [Sem.SemExprNeg] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprNot] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprBNot] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprRef] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprDeref] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprAdd] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprSub] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprMul] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprDiv] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprRem] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprEq] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprNe] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprLt] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprLe] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprGt] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprGe] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprAnd] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprOr] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprBitAnd] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprBitOr] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprBitXor] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprShl] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprLShr] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprAShr] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprCastTo] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprTruncTo] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprZExtTo] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprSExtTo] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprBitcastTo] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprSatCastTo] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprSelect] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprIndex] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprField] = function(self) return pvm.once(one_sem_field_ref_type(self.field)) end,
        [Sem.SemExprIndexAddr] = function() return pvm.once(Sem.SemTPtr) end,
        [Sem.SemExprFieldAddr] = function() return pvm.once(Sem.SemTPtr) end,
        [Sem.SemExprLoad] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprIntrinsicCall] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprCall] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprAgg] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprArrayLit] = function(self) return pvm.once(Sem.SemTArray(self.elem_ty, #self.elems)) end,
        [Sem.SemExprBlock] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprIf] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprSwitch] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprLoop] = function(self) return pvm.once(self.ty) end,
    })

    elab_array_count = pvm.phase("moonlift_elab_array_count", {
        [Elab.ElabInt] = function(self)
            local n = tonumber(self.raw)
            if n == nil or n < 0 or n ~= math.floor(n) then
                error("elab_to_sem_type: array count must be a non-negative integer literal")
            end
            return pvm.once(n)
        end,
    })

    lower_type = pvm.phase("elab_to_sem_type", {
        [Elab.ElabTVoid] = function() return pvm.once(Sem.SemTVoid) end,
        [Elab.ElabTBool] = function() return pvm.once(Sem.SemTBool) end,
        [Elab.ElabTI8] = function() return pvm.once(Sem.SemTI8) end,
        [Elab.ElabTI16] = function() return pvm.once(Sem.SemTI16) end,
        [Elab.ElabTI32] = function() return pvm.once(Sem.SemTI32) end,
        [Elab.ElabTI64] = function() return pvm.once(Sem.SemTI64) end,
        [Elab.ElabTU8] = function() return pvm.once(Sem.SemTU8) end,
        [Elab.ElabTU16] = function() return pvm.once(Sem.SemTU16) end,
        [Elab.ElabTU32] = function() return pvm.once(Sem.SemTU32) end,
        [Elab.ElabTU64] = function() return pvm.once(Sem.SemTU64) end,
        [Elab.ElabTF32] = function() return pvm.once(Sem.SemTF32) end,
        [Elab.ElabTF64] = function() return pvm.once(Sem.SemTF64) end,
        [Elab.ElabTIndex] = function() return pvm.once(Sem.SemTIndex) end,
        [Elab.ElabTPtr] = function(self) return pvm.once(Sem.SemTPtrTo(one_type(self.elem))) end,
        [Elab.ElabTArray] = function(self)
            return pvm.once(Sem.SemTArray(one_type(self.elem), pvm.one(elab_array_count(self.count))))
        end,
        [Elab.ElabTSlice] = function(self) return pvm.once(Sem.SemTSlice(one_type(self.elem))) end,
        [Elab.ElabTFunc] = function(self)
            local params = {}
            for i = 1, #self.params do
                params[i] = one_type(self.params[i])
            end
            return pvm.once(Sem.SemTFunc(params, one_type(self.result)))
        end,
        [Elab.ElabTNamed] = function(self) return pvm.once(Sem.SemTNamed(self.module_name, self.type_name)) end,
    })

    lower_param = pvm.phase("elab_to_sem_param", {
        [Elab.ElabParam] = function(self)
            return pvm.once(Sem.SemParam(self.name, one_type(self.ty)))
        end,
    })

    lower_binding = pvm.phase("elab_to_sem_binding", {
        [Elab.ElabLocalValue] = function(self) return pvm.once(Sem.SemBindLocalValue(self.id, self.name, one_type(self.ty))) end,
        [Elab.ElabLocalStoredValue] = function(self) return pvm.once(Sem.SemBindLocalStoredValue(self.id, self.name, one_type(self.ty))) end,
        [Elab.ElabLocalCell] = function(self) return pvm.once(Sem.SemBindLocalCell(self.id, self.name, one_type(self.ty))) end,
        [Elab.ElabArg] = function(self) return pvm.once(Sem.SemBindArg(self.index, self.name, one_type(self.ty))) end,
        [Elab.ElabGlobal] = function(self) return pvm.once(Sem.SemBindGlobal(self.module_name, self.item_name, one_type(self.ty))) end,
        [Elab.ElabExtern] = function(self) return pvm.once(Sem.SemBindExtern(self.symbol, one_type(self.ty))) end,
    })

    binding_call_target = pvm.phase("elab_binding_call_target", {
        [Elab.ElabLocalValue] = function(self, fn_ty)
            return pvm.once(Sem.SemCallIndirect(Sem.SemExprBinding(one_binding(self)), fn_ty))
        end,
        [Elab.ElabLocalStoredValue] = function(self, fn_ty)
            return pvm.once(Sem.SemCallIndirect(Sem.SemExprBinding(one_binding(self)), fn_ty))
        end,
        [Elab.ElabLocalCell] = function(self, fn_ty)
            return pvm.once(Sem.SemCallIndirect(Sem.SemExprBinding(one_binding(self)), fn_ty))
        end,
        [Elab.ElabArg] = function(self, fn_ty)
            return pvm.once(Sem.SemCallIndirect(Sem.SemExprBinding(one_binding(self)), fn_ty))
        end,
        [Elab.ElabGlobal] = function(self, fn_ty)
            return pvm.once(Sem.SemCallDirect(self.module_name, self.item_name, fn_ty))
        end,
        [Elab.ElabExtern] = function(self, fn_ty)
            return pvm.once(Sem.SemCallExtern(self.symbol, fn_ty))
        end,
    })

    expr_call_target = pvm.phase("elab_expr_call_target", {
        [Elab.ElabBindingExpr] = function(self, fn_ty)
            return pvm.once(one_call_target_from_binding(self.binding, fn_ty))
        end,
        [Elab.ElabInt] = indirect_call_target_handler(),
        [Elab.ElabFloat] = indirect_call_target_handler(),
        [Elab.ElabBool] = indirect_call_target_handler(),
        [Elab.ElabNil] = indirect_call_target_handler(),
        [Elab.ElabExprNeg] = indirect_call_target_handler(),
        [Elab.ElabExprNot] = indirect_call_target_handler(),
        [Elab.ElabExprBNot] = indirect_call_target_handler(),
        [Elab.ElabExprRef] = indirect_call_target_handler(),
        [Elab.ElabExprDeref] = indirect_call_target_handler(),
        [Elab.ElabExprAdd] = indirect_call_target_handler(),
        [Elab.ElabExprSub] = indirect_call_target_handler(),
        [Elab.ElabExprMul] = indirect_call_target_handler(),
        [Elab.ElabExprDiv] = indirect_call_target_handler(),
        [Elab.ElabExprRem] = indirect_call_target_handler(),
        [Elab.ElabExprEq] = indirect_call_target_handler(),
        [Elab.ElabExprNe] = indirect_call_target_handler(),
        [Elab.ElabExprLt] = indirect_call_target_handler(),
        [Elab.ElabExprLe] = indirect_call_target_handler(),
        [Elab.ElabExprGt] = indirect_call_target_handler(),
        [Elab.ElabExprGe] = indirect_call_target_handler(),
        [Elab.ElabExprAnd] = indirect_call_target_handler(),
        [Elab.ElabExprOr] = indirect_call_target_handler(),
        [Elab.ElabExprBitAnd] = indirect_call_target_handler(),
        [Elab.ElabExprBitOr] = indirect_call_target_handler(),
        [Elab.ElabExprBitXor] = indirect_call_target_handler(),
        [Elab.ElabExprShl] = indirect_call_target_handler(),
        [Elab.ElabExprLShr] = indirect_call_target_handler(),
        [Elab.ElabExprAShr] = indirect_call_target_handler(),
        [Elab.ElabExprCastTo] = indirect_call_target_handler(),
        [Elab.ElabExprTruncTo] = indirect_call_target_handler(),
        [Elab.ElabExprZExtTo] = indirect_call_target_handler(),
        [Elab.ElabExprSExtTo] = indirect_call_target_handler(),
        [Elab.ElabExprBitcastTo] = indirect_call_target_handler(),
        [Elab.ElabExprSatCastTo] = indirect_call_target_handler(),
        [Elab.ElabCall] = indirect_call_target_handler(),
        [Elab.ElabField] = indirect_call_target_handler(),
        [Elab.ElabIndex] = indirect_call_target_handler(),
        [Elab.ElabAgg] = indirect_call_target_handler(),
        [Elab.ElabArrayLit] = indirect_call_target_handler(),
        [Elab.ElabIfExpr] = indirect_call_target_handler(),
        [Elab.ElabSwitchExpr] = indirect_call_target_handler(),
        [Elab.ElabLoopExprNode] = indirect_call_target_handler(),
        [Elab.ElabBlockExpr] = indirect_call_target_handler(),
    })

    lower_field_init = pvm.phase("elab_to_sem_field_init", {
        [Elab.ElabFieldInit] = function(self)
            return pvm.once(Sem.SemFieldInit(self.name, one_expr(self.value)))
        end,
    })

    lower_switch_stmt_arm = pvm.phase("elab_to_sem_switch_stmt_arm", {
        [Elab.ElabSwitchStmtArm] = function(self)
            return pvm.once(Sem.SemSwitchStmtArm(one_expr(self.key), lower_stmt_list(self.body)))
        end,
    })

    lower_switch_expr_arm = pvm.phase("elab_to_sem_switch_expr_arm", {
        [Elab.ElabSwitchExprArm] = function(self)
            return pvm.once(Sem.SemSwitchExprArm(one_expr(self.key), lower_stmt_list(self.body), one_expr(self.result)))
        end,
    })

    lower_loop_binding = pvm.phase("elab_to_sem_loop_binding", {
        [Elab.ElabLoopBinding] = function(self)
            return pvm.once(Sem.SemLoopBinding(self.id, self.name, one_type(self.ty), one_expr(self.init)))
        end,
    })

    lower_loop_next = pvm.phase("elab_to_sem_loop_next", {
        [Elab.ElabLoopNext] = function(self)
            return pvm.once(Sem.SemLoopNext(one_binding(self.binding), one_expr(self.value)))
        end,
    })

    local function coerce_index_expr(expr)
        if one_sem_expr_type(expr) == Sem.SemTIndex then
            return expr
        end
        return Sem.SemExprCastTo(Sem.SemTIndex, expr)
    end

    lower_domain = pvm.phase("elab_to_sem_domain", {
        [Elab.ElabDomainRange] = function(self)
            return pvm.once(Sem.SemDomainRange(coerce_index_expr(one_expr(self.stop))))
        end,
        [Elab.ElabDomainRange2] = function(self)
            return pvm.once(Sem.SemDomainRange2(coerce_index_expr(one_expr(self.start)), coerce_index_expr(one_expr(self.stop))))
        end,
        [Elab.ElabDomainZipEq] = function(self)
            return pvm.once(Sem.SemDomainZipEq(lower_expr_list(self.values)))
        end,
        [Elab.ElabDomainValue] = function(self)
            return pvm.once(Sem.SemDomainBoundedValue(one_expr(self.value)))
        end,
    })

    lower_loop = pvm.phase("elab_to_sem_loop", {
        [Elab.ElabLoopWhileStmt] = function(self)
            local vars = {}
            local next = {}
            for i = 1, #self.vars do vars[i] = one_loop_binding(self.vars[i]) end
            for i = 1, #self.next do next[i] = one_loop_next(self.next[i]) end
            return pvm.once(Sem.SemLoopWhileStmt(vars, one_expr(self.cond), lower_stmt_list(self.body), next))
        end,
        [Elab.ElabLoopOverStmt] = function(self)
            local carries = {}
            local next = {}
            for i = 1, #self.carries do carries[i] = one_loop_binding(self.carries[i]) end
            for i = 1, #self.next do next[i] = one_loop_next(self.next[i]) end
            return pvm.once(Sem.SemLoopOverStmt(one_binding(self.index_binding), one_domain(self.domain), carries, lower_stmt_list(self.body), next))
        end,
        [Elab.ElabLoopWhileExpr] = function(self)
            local vars = {}
            local next = {}
            for i = 1, #self.vars do vars[i] = one_loop_binding(self.vars[i]) end
            for i = 1, #self.next do next[i] = one_loop_next(self.next[i]) end
            return pvm.once(Sem.SemLoopWhileExpr(vars, one_expr(self.cond), lower_stmt_list(self.body), next, one_expr(self.result)))
        end,
        [Elab.ElabLoopOverExpr] = function(self)
            local carries = {}
            local next = {}
            for i = 1, #self.carries do carries[i] = one_loop_binding(self.carries[i]) end
            for i = 1, #self.next do next[i] = one_loop_next(self.next[i]) end
            return pvm.once(Sem.SemLoopOverExpr(one_binding(self.index_binding), one_domain(self.domain), carries, lower_stmt_list(self.body), next, one_expr(self.result)))
        end,
    })

    lower_expr = pvm.phase("elab_to_sem_expr", {
        [Elab.ElabInt] = function(self)
            return pvm.once(Sem.SemExprConstInt(one_type(self.ty), self.raw))
        end,
        [Elab.ElabFloat] = function(self)
            return pvm.once(Sem.SemExprConstFloat(one_type(self.ty), self.raw))
        end,
        [Elab.ElabBool] = function(self)
            return pvm.once(Sem.SemExprConstBool(self.value))
        end,
        [Elab.ElabNil] = function(self)
            return pvm.once(Sem.SemExprNil(one_type(self.ty)))
        end,
        [Elab.ElabBindingExpr] = function(self)
            return pvm.once(Sem.SemExprBinding(one_binding(self.binding)))
        end,
        [Elab.ElabExprNeg] = function(self)
            return pvm.once(Sem.SemExprNeg(one_type(self.ty), one_expr(self.value)))
        end,
        [Elab.ElabExprNot] = function(self)
            return pvm.once(Sem.SemExprNot(one_type(self.ty), one_expr(self.value)))
        end,
        [Elab.ElabExprBNot] = function(self)
            return pvm.once(Sem.SemExprBNot(one_type(self.ty), one_expr(self.value)))
        end,
        [Elab.ElabExprRef] = function(self)
            return pvm.once(Sem.SemExprRef(one_type(self.ty), one_expr(self.value)))
        end,
        [Elab.ElabExprDeref] = function(self)
            return pvm.once(Sem.SemExprDeref(one_type(self.ty), one_expr(self.value)))
        end,
        [Elab.ElabExprAdd] = function(self)
            return pvm.once(Sem.SemExprAdd(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprSub] = function(self)
            return pvm.once(Sem.SemExprSub(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprMul] = function(self)
            return pvm.once(Sem.SemExprMul(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprDiv] = function(self)
            return pvm.once(Sem.SemExprDiv(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprRem] = function(self)
            return pvm.once(Sem.SemExprRem(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprEq] = function(self)
            return pvm.once(Sem.SemExprEq(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprNe] = function(self)
            return pvm.once(Sem.SemExprNe(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprLt] = function(self)
            return pvm.once(Sem.SemExprLt(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprLe] = function(self)
            return pvm.once(Sem.SemExprLe(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprGt] = function(self)
            return pvm.once(Sem.SemExprGt(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprGe] = function(self)
            return pvm.once(Sem.SemExprGe(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprAnd] = function(self)
            return pvm.once(Sem.SemExprAnd(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprOr] = function(self)
            return pvm.once(Sem.SemExprOr(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprBitAnd] = function(self)
            return pvm.once(Sem.SemExprBitAnd(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprBitOr] = function(self)
            return pvm.once(Sem.SemExprBitOr(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprBitXor] = function(self)
            return pvm.once(Sem.SemExprBitXor(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprShl] = function(self)
            return pvm.once(Sem.SemExprShl(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprLShr] = function(self)
            return pvm.once(Sem.SemExprLShr(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprAShr] = function(self)
            return pvm.once(Sem.SemExprAShr(one_type(self.ty), one_expr(self.lhs), one_expr(self.rhs)))
        end,
        [Elab.ElabExprCastTo] = function(self)
            return pvm.once(Sem.SemExprCastTo(one_type(self.ty), one_expr(self.value)))
        end,
        [Elab.ElabExprTruncTo] = function(self)
            return pvm.once(Sem.SemExprTruncTo(one_type(self.ty), one_expr(self.value)))
        end,
        [Elab.ElabExprZExtTo] = function(self)
            return pvm.once(Sem.SemExprZExtTo(one_type(self.ty), one_expr(self.value)))
        end,
        [Elab.ElabExprSExtTo] = function(self)
            return pvm.once(Sem.SemExprSExtTo(one_type(self.ty), one_expr(self.value)))
        end,
        [Elab.ElabExprBitcastTo] = function(self)
            return pvm.once(Sem.SemExprBitcastTo(one_type(self.ty), one_expr(self.value)))
        end,
        [Elab.ElabExprSatCastTo] = function(self)
            return pvm.once(Sem.SemExprSatCastTo(one_type(self.ty), one_expr(self.value)))
        end,
        [Elab.ElabCall] = function(self)
            local fn_ty = one_type(one_elab_expr_type(self.callee))
            return pvm.once(Sem.SemExprCall(one_call_target_from_expr(self.callee, fn_ty), one_type(self.ty), lower_expr_list(self.args)))
        end,
        [Elab.ElabField] = function(self)
            return pvm.once(Sem.SemExprField(one_expr(self.base), Sem.SemFieldByName(self.name, one_type(self.ty))))
        end,
        [Elab.ElabIndex] = function(self)
            return pvm.once(Sem.SemExprIndex(one_expr(self.base), one_expr(self.index), one_type(self.ty)))
        end,
        [Elab.ElabAgg] = function(self)
            return pvm.once(Sem.SemExprAgg(one_type(self.ty), lower_field_init_list(self.fields)))
        end,
        [Elab.ElabArrayLit] = function(self)
            return pvm.once(Sem.SemExprArrayLit(one_type(self.ty.elem), lower_expr_list(self.elems)))
        end,
        [Elab.ElabIfExpr] = function(self)
            return pvm.once(Sem.SemExprIf(one_expr(self.cond), one_expr(self.then_expr), one_expr(self.else_expr), one_type(self.ty)))
        end,
        [Elab.ElabSwitchExpr] = function(self)
            return pvm.once(Sem.SemExprSwitch(one_expr(self.value), lower_switch_expr_arm_list(self.arms), one_expr(self.default_expr), one_type(self.ty)))
        end,
        [Elab.ElabLoopExprNode] = function(self)
            return pvm.once(Sem.SemExprLoop(one_loop(self.loop), one_type(self.ty)))
        end,
        [Elab.ElabBlockExpr] = function(self)
            return pvm.once(Sem.SemExprBlock(lower_stmt_list(self.stmts), one_expr(self.result), one_type(self.ty)))
        end,
    })

    lower_stmt = pvm.phase("elab_to_sem_stmt", {
        [Elab.ElabLet] = function(self)
            return pvm.once(Sem.SemStmtLet(self.id, self.name, one_type(self.ty), one_expr(self.init)))
        end,
        [Elab.ElabVar] = function(self)
            return pvm.once(Sem.SemStmtVar(self.id, self.name, one_type(self.ty), one_expr(self.init)))
        end,
        [Elab.ElabSet] = function(self)
            return pvm.once(Sem.SemStmtSet(one_binding(self.binding), one_expr(self.value)))
        end,
        [Elab.ElabStore] = function(self)
            return pvm.once(Sem.SemStmtStore(one_type(self.ty), one_expr(self.addr), one_expr(self.value)))
        end,
        [Elab.ElabExprStmt] = function(self)
            return pvm.once(Sem.SemStmtExpr(one_expr(self.expr)))
        end,
        [Elab.ElabIf] = function(self)
            return pvm.once(Sem.SemStmtIf(one_expr(self.cond), lower_stmt_list(self.then_body), lower_stmt_list(self.else_body)))
        end,
        [Elab.ElabSwitch] = function(self)
            return pvm.once(Sem.SemStmtSwitch(one_expr(self.value), lower_switch_stmt_arm_list(self.arms), lower_stmt_list(self.default_body)))
        end,
        [Elab.ElabReturnVoid] = function()
            return pvm.once(Sem.SemStmtReturnVoid)
        end,
        [Elab.ElabReturnValue] = function(self)
            return pvm.once(Sem.SemStmtReturnValue(one_expr(self.value)))
        end,
        [Elab.ElabBreak] = function()
            return pvm.once(Sem.SemStmtBreak)
        end,
        [Elab.ElabContinue] = function()
            return pvm.once(Sem.SemStmtContinue)
        end,
        [Elab.ElabLoopStmtNode] = function(self)
            return pvm.once(Sem.SemStmtLoop(one_loop(self.loop)))
        end,
    })

    lower_func = pvm.phase("elab_to_sem_func", {
        [Elab.ElabFunc] = function(self)
            local params = {}
            for i = 1, #self.params do
                params[i] = one_param(self.params[i])
            end
            return pvm.once(Sem.SemFuncExport(self.name, params, one_type(self.result), lower_stmt_list(self.body)))
        end,
    })

    lower_extern_func = pvm.phase("elab_to_sem_extern_func", {
        [Elab.ElabExternFunc] = function(self)
            local params = {}
            for i = 1, #self.params do
                params[i] = one_param(self.params[i])
            end
            return pvm.once(Sem.SemExternFunc(self.name, self.symbol, params, one_type(self.result)))
        end,
    })

    lower_const = pvm.phase("elab_to_sem_const", {
        [Elab.ElabConst] = function(self)
            return pvm.once(Sem.SemConst(self.name, one_type(self.ty), one_expr(self.value)))
        end,
    })

    lower_item = pvm.phase("elab_to_sem_item", {
        [Elab.ElabItemFunc] = function(self)
            return pvm.once(Sem.SemItemFunc(one_func(self.func)))
        end,
        [Elab.ElabItemExtern] = function(self)
            return pvm.once(Sem.SemItemExtern(one_extern_func(self.func)))
        end,
        [Elab.ElabItemConst] = function(self)
            return pvm.once(Sem.SemItemConst(one_const(self.c)))
        end,
    })

    lower_module = pvm.phase("elab_to_sem_module", {
        [Elab.ElabModule] = function(self)
            local items = {}
            for i = 1, #self.items do
                items[i] = one_item(self.items[i])
            end
            return pvm.once(Sem.SemModule(items))
        end,
    })

    return {
        lower_type = lower_type,
        lower_param = lower_param,
        lower_binding = lower_binding,
        lower_expr = lower_expr,
        lower_domain = lower_domain,
        lower_stmt = lower_stmt,
        lower_loop = lower_loop,
        lower_func = lower_func,
        lower_extern_func = lower_extern_func,
        lower_const = lower_const,
        lower_item = lower_item,
        lower_module = lower_module,
        elab_expr_type = elab_expr_type,
        sem_expr_type = sem_expr_type,
    }
end

return M
