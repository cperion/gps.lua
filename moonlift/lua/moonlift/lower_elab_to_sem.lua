package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.Define(T)
    local Elab = T.MoonliftElab
    local Sem = T.MoonliftSem

    local lower_type
    local lower_param
    local lower_binding
    local lower_place
    local lower_index_base
    local lower_view
    local lower_expr
    local elab_view_value_elem_type
    local sem_type_is_index
    local lower_domain
    local lower_stmt
    local lower_loop
    local lower_func
    local lower_extern_func
    local lower_const
    local lower_static
    local lower_import
    local lower_item
    local lower_module
    local lower_loop_carry
    local lower_loop_update
    local lower_loop_expr_exit
    local lower_switch_stmt_arm
    local lower_switch_expr_arm
    local lower_field_type
    local lower_type_decl
    local lower_field_init
    local lower_intrinsic
    local lower_const_env_effect
    local apply_const_env_effect
    local sem_field_ref_type
    local elab_expr_type
    local sem_expr_type
    local elab_array_count
    local binding_call_target
    local expr_call_target

    local function one_type(node, const_env)
        return pvm.one(lower_type(node, const_env))
    end

    local function one_param(node, const_env)
        return pvm.one(lower_param(node, const_env))
    end

    local function one_binding(node, const_env)
        return pvm.one(lower_binding(node, const_env))
    end

    local function one_expr(node, const_env)
        return pvm.one(lower_expr(node, const_env))
    end

    local function one_place(node, const_env)
        return pvm.one(lower_place(node, const_env))
    end

    local function one_index_base(node, const_env)
        return pvm.one(lower_index_base(node, const_env))
    end

    local function one_view(node, const_env)
        return pvm.one(lower_view(node, const_env))
    end

    local function one_domain(node, const_env)
        return pvm.one(lower_domain(node, const_env))
    end

    local function one_stmt(node, const_env)
        return pvm.one(lower_stmt(node, const_env))
    end

    local function one_loop(node, const_env)
        return pvm.one(lower_loop(node, const_env))
    end

    local function one_func(node, const_env)
        return pvm.one(lower_func(node, const_env))
    end

    local function one_extern_func(node, const_env)
        return pvm.one(lower_extern_func(node, const_env))
    end

    local function one_const(node, const_env)
        return pvm.one(lower_const(node, const_env))
    end

    local function one_static(node, const_env)
        return pvm.one(lower_static(node, const_env))
    end

    local function one_import(node)
        return pvm.one(lower_import(node))
    end

    local function one_item(node, const_env)
        return pvm.one(lower_item(node, const_env))
    end

    local function one_module(node, const_env)
        return pvm.one(lower_module(node, const_env))
    end

    local function one_loop_carry(node, const_env)
        return pvm.one(lower_loop_carry(node, const_env))
    end

    local function one_loop_update(node, const_env)
        return pvm.one(lower_loop_update(node, const_env))
    end

    local function one_loop_expr_exit(node)
        return pvm.one(lower_loop_expr_exit(node))
    end

    local function one_switch_stmt_arm(node, const_env)
        return pvm.one(lower_switch_stmt_arm(node, const_env))
    end

    local function one_switch_expr_arm(node, const_env)
        return pvm.one(lower_switch_expr_arm(node, const_env))
    end

    local function one_field_type(node, const_env)
        return pvm.one(lower_field_type(node, const_env))
    end

    local function one_type_decl(node, const_env)
        return pvm.one(lower_type_decl(node, const_env))
    end

    local function one_field_init(node, const_env)
        return pvm.one(lower_field_init(node, const_env))
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

    local function one_view_value_elem_type(node, const_env)
        return pvm.one(elab_view_value_elem_type(node, const_env))
    end

    local function one_sem_type_is_index(node)
        return pvm.one(sem_type_is_index(node))
    end

    local function one_call_target_from_binding(binding, fn_ty, const_env)
        return pvm.one(binding_call_target(binding, fn_ty, const_env))
    end

    local function one_call_target_from_expr(expr, fn_ty, const_env)
        return pvm.one(expr_call_target(expr, fn_ty, const_env))
    end

    local function one_intrinsic(node)
        return pvm.one(lower_intrinsic(node))
    end

    local function lower_switch_expr_arm_list(nodes, const_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_switch_expr_arm(nodes[i], const_env)
        end
        return out
    end

    local function lower_switch_stmt_arm_list(nodes, const_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_switch_stmt_arm(nodes[i], const_env)
        end
        return out
    end

    local function lower_field_init_list(nodes, const_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_field_init(nodes[i], const_env)
        end
        return out
    end

    local function lower_stmt_list(nodes, const_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_stmt(nodes[i], const_env)
        end
        return out
    end

    local function lower_expr_list(nodes, const_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_expr(nodes[i], const_env)
        end
        return out
    end

    local function ensure_const_env(const_env)
        if const_env ~= nil then
            return const_env
        end
        return Elab.ElabConstEnv({})
    end

    local function find_const_entry(const_env, module_name, item_name)
        local env = ensure_const_env(const_env)
        for i = #env.entries, 1, -1 do
            local entry = env.entries[i]
            if entry.module_name == module_name and entry.item_name == item_name then
                return entry
            end
        end
        return nil
    end

    local function with_visiting(visiting, key)
        local out = {}
        if visiting ~= nil then
            for k, v in pairs(visiting) do
                out[k] = v
            end
        end
        out[key] = true
        return out
    end

    local function one_array_count(node, const_env, visiting)
        return pvm.one(elab_array_count(node, const_env, visiting))
    end

    local function indirect_call_target_handler()
        return function(self, fn_ty, const_env)
            return pvm.once(Sem.SemCallIndirect(one_expr(self, const_env), fn_ty))
        end
    end

    elab_expr_type = pvm.phase("moonlift_elab_expr_type", {
        [Elab.ElabInt] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabFloat] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabBool] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabNil] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabBindingExpr] = function(self, const_env) return pvm.once(self.binding.ty) end,
        [Elab.ElabExprNeg] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprNot] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprBNot] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprAddrOf] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprDeref] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprAdd] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprSub] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprMul] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprDiv] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprRem] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprEq] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprNe] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprLt] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprLe] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprGt] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprGe] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprAnd] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprOr] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprBitAnd] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprBitOr] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprBitXor] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprShl] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprLShr] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprAShr] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprCastTo] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprTruncTo] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprZExtTo] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprSExtTo] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprBitcastTo] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprSatCastTo] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprAddrOf] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabExprIntrinsicCall] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabCall] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabField] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabIndex] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabAgg] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabArrayLit] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabIfExpr] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabSelectExpr] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabSwitchExpr] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabLoopExprNode] = function(self, const_env) return pvm.once(self.ty) end,
        [Elab.ElabBlockExpr] = function(self, const_env) return pvm.once(self.ty) end,
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
        [Sem.SemExprAddrOf] = function(self) return pvm.once(self.ty) end,
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

    local function checked_array_count(n)
        if n == nil or n < 0 or n ~= math.floor(n) then
            error("elab_to_sem_type: array count must evaluate to a non-negative integer")
        end
        return n
    end

    local function binding_count_name(binding)
        if binding.module_name ~= "" then
            return binding.module_name .. "." .. binding.item_name
        end
        return binding.item_name
    end

    elab_array_count = pvm.phase("moonlift_elab_array_count", {
        [Elab.ElabInt] = function(self, const_env)
            return pvm.once(checked_array_count(tonumber(self.raw)))
        end,
        [Elab.ElabBindingExpr] = function(self, const_env, visiting)
            local binding = self.binding
            if binding.module_name == nil or binding.item_name == nil then
                error("elab_to_sem_type: array count refs must resolve to global const bindings")
            end
            if binding.ty ~= Elab.ElabTIndex then
                error("elab_to_sem_type: array count refs must resolve to index-typed const bindings")
            end
            local key = binding_count_name(binding)
            if visiting ~= nil and visiting[key] then
                error("elab_to_sem_type: cyclic const dependency in array count at '" .. key .. "'")
            end
            local entry = find_const_entry(const_env, binding.module_name, binding.item_name)
            if entry == nil then
                error("elab_to_sem_type: unknown const binding '" .. key .. "' in array count")
            end
            if entry.ty ~= Elab.ElabTIndex then
                error("elab_to_sem_type: array count const '" .. key .. "' must have type index")
            end
            return pvm.once(one_array_count(entry.value, const_env, with_visiting(visiting, key)))
        end,
        [Elab.ElabExprAdd] = function(self, const_env, visiting)
            return pvm.once(checked_array_count(one_array_count(self.lhs, const_env, visiting) + one_array_count(self.rhs, const_env, visiting)))
        end,
        [Elab.ElabExprSub] = function(self, const_env, visiting)
            return pvm.once(checked_array_count(one_array_count(self.lhs, const_env, visiting) - one_array_count(self.rhs, const_env, visiting)))
        end,
        [Elab.ElabExprMul] = function(self, const_env, visiting)
            return pvm.once(checked_array_count(one_array_count(self.lhs, const_env, visiting) * one_array_count(self.rhs, const_env, visiting)))
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
        [Elab.ElabTPtr] = function(self, const_env) return pvm.once(Sem.SemTPtrTo(one_type(self.elem, const_env))) end,
        [Elab.ElabTArray] = function(self, const_env)
            return pvm.once(Sem.SemTArray(one_type(self.elem, const_env), one_array_count(self.count, const_env, nil)))
        end,
        [Elab.ElabTSlice] = function(self, const_env) return pvm.once(Sem.SemTSlice(one_type(self.elem, const_env))) end,
        [Elab.ElabTView] = function(self, const_env) return pvm.once(Sem.SemTView(one_type(self.elem, const_env))) end,
        [Elab.ElabTFunc] = function(self, const_env)
            local params = {}
            for i = 1, #self.params do
                params[i] = one_type(self.params[i], const_env)
            end
            return pvm.once(Sem.SemTFunc(params, one_type(self.result, const_env)))
        end,
        [Elab.ElabTNamed] = function(self) return pvm.once(Sem.SemTNamed(self.module_name, self.type_name)) end,
    })

    lower_param = pvm.phase("elab_to_sem_param", {
        [Elab.ElabParam] = function(self, const_env)
            return pvm.once(Sem.SemParam(self.name, one_type(self.ty, const_env)))
        end,
    })

    lower_binding = pvm.phase("elab_to_sem_binding", {
        [Elab.ElabLocalValue] = function(self, const_env) return pvm.once(Sem.SemBindLocalValue(self.id, self.name, one_type(self.ty, const_env))) end,
        [Elab.ElabLocalCell] = function(self, const_env) return pvm.once(Sem.SemBindLocalCell(self.id, self.name, one_type(self.ty, const_env))) end,
        [Elab.ElabArg] = function(self, const_env) return pvm.once(Sem.SemBindArg(self.index, self.name, one_type(self.ty, const_env))) end,
        [Elab.ElabLoopCarry] = function(self, const_env) return pvm.once(Sem.SemBindLoopCarry(self.loop_id, self.port_id, self.name, one_type(self.ty, const_env))) end,
        [Elab.ElabLoopIndex] = function(self, const_env) return pvm.once(Sem.SemBindLoopIndex(self.loop_id, self.name, one_type(self.ty, const_env))) end,
        [Elab.ElabGlobalFunc] = function(self, const_env) return pvm.once(Sem.SemBindGlobalFunc(self.module_name, self.item_name, one_type(self.ty, const_env))) end,
        [Elab.ElabGlobalConst] = function(self, const_env) return pvm.once(Sem.SemBindGlobalConst(self.module_name, self.item_name, one_type(self.ty, const_env))) end,
        [Elab.ElabGlobalStatic] = function(self, const_env) return pvm.once(Sem.SemBindGlobalStatic(self.module_name, self.item_name, one_type(self.ty, const_env))) end,
        [Elab.ElabExtern] = function(self, const_env) return pvm.once(Sem.SemBindExtern(self.symbol, one_type(self.ty, const_env))) end,
    })

    binding_call_target = pvm.phase("elab_binding_call_target", {
        [Elab.ElabLocalValue] = function(self, fn_ty, const_env)
            return pvm.once(Sem.SemCallIndirect(Sem.SemExprBinding(one_binding(self, const_env)), fn_ty))
        end,
        [Elab.ElabLocalCell] = function(self, fn_ty, const_env)
            return pvm.once(Sem.SemCallIndirect(Sem.SemExprBinding(one_binding(self, const_env)), fn_ty))
        end,
        [Elab.ElabArg] = function(self, fn_ty, const_env)
            return pvm.once(Sem.SemCallIndirect(Sem.SemExprBinding(one_binding(self, const_env)), fn_ty))
        end,
        [Elab.ElabLoopCarry] = function(self, fn_ty, const_env)
            return pvm.once(Sem.SemCallIndirect(Sem.SemExprBinding(one_binding(self, const_env)), fn_ty))
        end,
        [Elab.ElabLoopIndex] = function(self, fn_ty, const_env)
            return pvm.once(Sem.SemCallIndirect(Sem.SemExprBinding(one_binding(self, const_env)), fn_ty))
        end,
        [Elab.ElabGlobalFunc] = function(self, fn_ty)
            return pvm.once(Sem.SemCallDirect(self.module_name, self.item_name, fn_ty))
        end,
        [Elab.ElabGlobalConst] = function(self, fn_ty, const_env)
            return pvm.once(Sem.SemCallIndirect(Sem.SemExprBinding(one_binding(self, const_env)), fn_ty))
        end,
        [Elab.ElabGlobalStatic] = function(self, fn_ty, const_env)
            return pvm.once(Sem.SemCallIndirect(Sem.SemExprBinding(one_binding(self, const_env)), fn_ty))
        end,
        [Elab.ElabExtern] = function(self, fn_ty)
            return pvm.once(Sem.SemCallExtern(self.symbol, fn_ty))
        end,
    })

    expr_call_target = pvm.phase("elab_expr_call_target", {
        [Elab.ElabBindingExpr] = function(self, fn_ty, const_env)
            return pvm.once(one_call_target_from_binding(self.binding, fn_ty, const_env))
        end,
        [Elab.ElabInt] = indirect_call_target_handler(),
        [Elab.ElabFloat] = indirect_call_target_handler(),
        [Elab.ElabBool] = indirect_call_target_handler(),
        [Elab.ElabNil] = indirect_call_target_handler(),
        [Elab.ElabExprNeg] = indirect_call_target_handler(),
        [Elab.ElabExprNot] = indirect_call_target_handler(),
        [Elab.ElabExprBNot] = indirect_call_target_handler(),
        [Elab.ElabExprAddrOf] = indirect_call_target_handler(),
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
        [Elab.ElabExprIntrinsicCall] = indirect_call_target_handler(),
        [Elab.ElabCall] = indirect_call_target_handler(),
        [Elab.ElabField] = indirect_call_target_handler(),
        [Elab.ElabIndex] = indirect_call_target_handler(),
        [Elab.ElabAgg] = indirect_call_target_handler(),
        [Elab.ElabArrayLit] = indirect_call_target_handler(),
        [Elab.ElabIfExpr] = indirect_call_target_handler(),
        [Elab.ElabSelectExpr] = indirect_call_target_handler(),
        [Elab.ElabSwitchExpr] = indirect_call_target_handler(),
        [Elab.ElabLoopExprNode] = indirect_call_target_handler(),
        [Elab.ElabBlockExpr] = indirect_call_target_handler(),
    })

    lower_intrinsic = pvm.phase("elab_to_sem_intrinsic", {
        [Elab.ElabPopcount] = function() return pvm.once(Sem.SemPopcount) end,
        [Elab.ElabClz] = function() return pvm.once(Sem.SemClz) end,
        [Elab.ElabCtz] = function() return pvm.once(Sem.SemCtz) end,
        [Elab.ElabRotl] = function() return pvm.once(Sem.SemRotl) end,
        [Elab.ElabRotr] = function() return pvm.once(Sem.SemRotr) end,
        [Elab.ElabBswap] = function() return pvm.once(Sem.SemBswap) end,
        [Elab.ElabFma] = function() return pvm.once(Sem.SemFma) end,
        [Elab.ElabSqrt] = function() return pvm.once(Sem.SemSqrt) end,
        [Elab.ElabAbs] = function() return pvm.once(Sem.SemAbs) end,
        [Elab.ElabFloor] = function() return pvm.once(Sem.SemFloor) end,
        [Elab.ElabCeil] = function() return pvm.once(Sem.SemCeil) end,
        [Elab.ElabTruncFloat] = function() return pvm.once(Sem.SemTruncFloat) end,
        [Elab.ElabRound] = function() return pvm.once(Sem.SemRound) end,
        [Elab.ElabTrap] = function() return pvm.once(Sem.SemTrap) end,
        [Elab.ElabAssume] = function() return pvm.once(Sem.SemAssume) end,
    })

    lower_place = pvm.phase("elab_to_sem_place", {
        [Elab.ElabPlaceBinding] = function(self, const_env)
            return pvm.once(Sem.SemPlaceBinding(one_binding(self.binding, const_env)))
        end,
        [Elab.ElabPlaceDeref] = function(self, const_env)
            return pvm.once(Sem.SemPlaceDeref(one_expr(self.base, const_env), one_type(self.elem, const_env)))
        end,
        [Elab.ElabPlaceField] = function(self, const_env)
            return pvm.once(Sem.SemPlaceField(one_place(self.base, const_env), Sem.SemFieldByName(self.name, one_type(self.ty, const_env))))
        end,
        [Elab.ElabPlaceIndex] = function(self, const_env)
            return pvm.once(Sem.SemPlaceIndex(one_index_base(self.base, const_env), one_expr(self.index, const_env), one_type(self.ty, const_env)))
        end,
    })

    lower_index_base = pvm.phase("elab_to_sem_index_base", {
        [Elab.ElabIndexBasePlace] = function(self, const_env)
            return pvm.once(Sem.SemIndexBasePlace(one_place(self.base, const_env), one_type(self.elem, const_env)))
        end,
        [Elab.ElabIndexBaseView] = function(self, const_env)
            return pvm.once(Sem.SemIndexBaseView(one_view(self.base, const_env)))
        end,
    })

    elab_view_value_elem_type = pvm.phase("moonlift_elab_view_value_elem_type", {
        [Elab.ElabTPtr] = function(self, const_env)
            return pvm.once(one_type(self.elem, const_env))
        end,
        [Elab.ElabTArray] = function(self, const_env)
            return pvm.once(one_type(self.elem, const_env))
        end,
        [Elab.ElabTSlice] = function(self, const_env)
            return pvm.once(one_type(self.elem, const_env))
        end,
        [Elab.ElabTView] = function(self, const_env)
            return pvm.once(one_type(self.elem, const_env))
        end,
        [Elab.ElabTVoid] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTBool] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTI8] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTI16] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTI32] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTI64] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTU8] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTU16] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTU32] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTU64] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTF32] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTF64] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTIndex] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTFunc] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
        [Elab.ElabTNamed] = function()
            error("elab_to_sem_view: domain values currently require pointer/array/slice/view typed expressions")
        end,
    })

    local function view_value_expr(node, const_env)
        return Sem.SemViewValue(one_expr(node, const_env), one_view_value_elem_type(one_elab_expr_type(node), const_env))
    end

    lower_view = pvm.phase("elab_to_sem_view", {
        [Elab.ElabBindingExpr] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabInt] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabFloat] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabBool] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabNil] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprNeg] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprNot] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprBNot] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprAddrOf] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprDeref] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprAdd] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprSub] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprMul] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprDiv] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprRem] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprEq] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprNe] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprLt] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprLe] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprGt] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprGe] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprAnd] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprOr] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprBitAnd] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprBitOr] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprBitXor] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprShl] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprLShr] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprAShr] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprCastTo] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprTruncTo] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprZExtTo] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprSExtTo] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprBitcastTo] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprSatCastTo] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabExprIntrinsicCall] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabCall] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabField] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabIndex] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabAgg] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabArrayLit] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabIfExpr] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabSelectExpr] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabSwitchExpr] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabLoopExprNode] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
        [Elab.ElabBlockExpr] = function(self, const_env)
            return pvm.once(view_value_expr(self, const_env))
        end,
    })

    sem_type_is_index = pvm.phase("moonlift_sem_type_is_index", {
        [Sem.SemTIndex] = function() return pvm.once(true) end,
        [Sem.SemTVoid] = function() return pvm.once(false) end,
        [Sem.SemTBool] = function() return pvm.once(false) end,
        [Sem.SemTI8] = function() return pvm.once(false) end,
        [Sem.SemTI16] = function() return pvm.once(false) end,
        [Sem.SemTI32] = function() return pvm.once(false) end,
        [Sem.SemTI64] = function() return pvm.once(false) end,
        [Sem.SemTU8] = function() return pvm.once(false) end,
        [Sem.SemTU16] = function() return pvm.once(false) end,
        [Sem.SemTU32] = function() return pvm.once(false) end,
        [Sem.SemTU64] = function() return pvm.once(false) end,
        [Sem.SemTF32] = function() return pvm.once(false) end,
        [Sem.SemTF64] = function() return pvm.once(false) end,
        [Sem.SemTPtr] = function() return pvm.once(false) end,
        [Sem.SemTPtrTo] = function() return pvm.once(false) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTView] = function() return pvm.once(false) end,
        [Sem.SemTFunc] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    lower_field_type = pvm.phase("elab_to_sem_field_type", {
        [Elab.ElabFieldType] = function(self, const_env)
            return pvm.once(Sem.SemFieldType(self.field_name, one_type(self.ty, const_env)))
        end,
    })

    lower_type_decl = pvm.phase("elab_to_sem_type_decl", {
        [Elab.ElabStruct] = function(self, const_env)
            local fields = {}
            for i = 1, #self.fields do
                fields[i] = one_field_type(self.fields[i], const_env)
            end
            return pvm.once(Sem.SemStruct(self.name, fields))
        end,
    })

    lower_field_init = pvm.phase("elab_to_sem_field_init", {
        [Elab.ElabFieldInit] = function(self, const_env)
            return pvm.once(Sem.SemFieldInit(self.name, one_expr(self.value, const_env)))
        end,
    })

    lower_switch_stmt_arm = pvm.phase("elab_to_sem_switch_stmt_arm", {
        [Elab.ElabSwitchStmtArm] = function(self, const_env)
            return pvm.once(Sem.SemSwitchStmtArm(one_expr(self.key, const_env), lower_stmt_list(self.body, const_env)))
        end,
    })

    lower_switch_expr_arm = pvm.phase("elab_to_sem_switch_expr_arm", {
        [Elab.ElabSwitchExprArm] = function(self, const_env)
            return pvm.once(Sem.SemSwitchExprArm(one_expr(self.key, const_env), lower_stmt_list(self.body, const_env), one_expr(self.result, const_env)))
        end,
    })

    lower_loop_carry = pvm.phase("elab_to_sem_loop_carry", {
        [Elab.ElabLoopCarryPort] = function(self, const_env)
            return pvm.once(Sem.SemLoopCarryPort(self.port_id, self.name, one_type(self.ty, const_env), one_expr(self.init, const_env)))
        end,
    })

    lower_loop_update = pvm.phase("elab_to_sem_loop_update", {
        [Elab.ElabLoopUpdate] = function(self, const_env)
            return pvm.once(Sem.SemLoopUpdate(self.port_id, one_expr(self.value, const_env)))
        end,
    })

    lower_loop_expr_exit = pvm.phase("elab_to_sem_loop_expr_exit", {
        [Elab.ElabLoopExprEndOnly] = function()
            return pvm.once(Sem.SemLoopExprEndOnly)
        end,
        [Elab.ElabLoopExprEndOrBreakValue] = function()
            return pvm.once(Sem.SemLoopExprEndOrBreakValue)
        end,
    })

    local function coerce_index_expr(expr)
        if one_sem_type_is_index(one_sem_expr_type(expr)) then
            return expr
        end
        return Sem.SemExprCastTo(Sem.SemTIndex, expr)
    end

    lower_domain = pvm.phase("elab_to_sem_domain", {
        [Elab.ElabDomainRange] = function(self, const_env)
            return pvm.once(Sem.SemDomainRange(coerce_index_expr(one_expr(self.stop, const_env))))
        end,
        [Elab.ElabDomainRange2] = function(self, const_env)
            return pvm.once(Sem.SemDomainRange2(coerce_index_expr(one_expr(self.start, const_env)), coerce_index_expr(one_expr(self.stop, const_env))))
        end,
        [Elab.ElabDomainZipEq] = function(self, const_env)
            local views = {}
            for i = 1, #self.values do
                views[i] = one_view(self.values[i], const_env)
            end
            return pvm.once(Sem.SemDomainZipEq(views))
        end,
        [Elab.ElabDomainValue] = function(self, const_env)
            return pvm.once(Sem.SemDomainView(one_view(self.value, const_env)))
        end,
    })

    lower_loop = pvm.phase("elab_to_sem_loop", {
        [Elab.ElabLoopWhileStmt] = function(self, const_env)
            local carries = {}
            local next = {}
            for i = 1, #self.carries do carries[i] = one_loop_carry(self.carries[i], const_env) end
            for i = 1, #self.next do next[i] = one_loop_update(self.next[i], const_env) end
            return pvm.once(Sem.SemLoopWhileStmt(self.loop_id, carries, one_expr(self.cond, const_env), lower_stmt_list(self.body, const_env), next))
        end,
        [Elab.ElabLoopOverStmt] = function(self, const_env)
            local carries = {}
            local next = {}
            for i = 1, #self.carries do carries[i] = one_loop_carry(self.carries[i], const_env) end
            for i = 1, #self.next do next[i] = one_loop_update(self.next[i], const_env) end
            return pvm.once(Sem.SemLoopOverStmt(self.loop_id, Sem.SemLoopIndexPort(self.index_port.name, one_type(self.index_port.ty, const_env)), one_domain(self.domain, const_env), carries, lower_stmt_list(self.body, const_env), next))
        end,
        [Elab.ElabLoopWhileExpr] = function(self, const_env)
            local carries = {}
            local next = {}
            for i = 1, #self.carries do carries[i] = one_loop_carry(self.carries[i], const_env) end
            for i = 1, #self.next do next[i] = one_loop_update(self.next[i], const_env) end
            return pvm.once(Sem.SemLoopWhileExpr(self.loop_id, carries, one_expr(self.cond, const_env), lower_stmt_list(self.body, const_env), next, one_loop_expr_exit(self.exit), one_expr(self.result, const_env)))
        end,
        [Elab.ElabLoopOverExpr] = function(self, const_env)
            local carries = {}
            local next = {}
            for i = 1, #self.carries do carries[i] = one_loop_carry(self.carries[i], const_env) end
            for i = 1, #self.next do next[i] = one_loop_update(self.next[i], const_env) end
            return pvm.once(Sem.SemLoopOverExpr(self.loop_id, Sem.SemLoopIndexPort(self.index_port.name, one_type(self.index_port.ty, const_env)), one_domain(self.domain, const_env), carries, lower_stmt_list(self.body, const_env), next, one_loop_expr_exit(self.exit), one_expr(self.result, const_env)))
        end,
    })

    lower_expr = pvm.phase("elab_to_sem_expr", {
        [Elab.ElabInt] = function(self, const_env)
            return pvm.once(Sem.SemExprConstInt(one_type(self.ty, const_env), self.raw))
        end,
        [Elab.ElabFloat] = function(self, const_env)
            return pvm.once(Sem.SemExprConstFloat(one_type(self.ty, const_env), self.raw))
        end,
        [Elab.ElabBool] = function(self)
            return pvm.once(Sem.SemExprConstBool(self.value))
        end,
        [Elab.ElabNil] = function(self, const_env)
            return pvm.once(Sem.SemExprNil(one_type(self.ty, const_env)))
        end,
        [Elab.ElabBindingExpr] = function(self, const_env)
            return pvm.once(Sem.SemExprBinding(one_binding(self.binding, const_env)))
        end,
        [Elab.ElabExprNeg] = function(self, const_env)
            return pvm.once(Sem.SemExprNeg(one_type(self.ty, const_env), one_expr(self.value, const_env)))
        end,
        [Elab.ElabExprNot] = function(self, const_env)
            return pvm.once(Sem.SemExprNot(one_type(self.ty, const_env), one_expr(self.value, const_env)))
        end,
        [Elab.ElabExprBNot] = function(self, const_env)
            return pvm.once(Sem.SemExprBNot(one_type(self.ty, const_env), one_expr(self.value, const_env)))
        end,
        [Elab.ElabExprAddrOf] = function(self, const_env)
            return pvm.once(Sem.SemExprAddrOf(one_place(self.place, const_env), one_type(self.ty, const_env)))
        end,
        [Elab.ElabExprDeref] = function(self, const_env)
            return pvm.once(Sem.SemExprDeref(one_type(self.ty, const_env), one_expr(self.value, const_env)))
        end,
        [Elab.ElabExprAdd] = function(self, const_env)
            return pvm.once(Sem.SemExprAdd(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprSub] = function(self, const_env)
            return pvm.once(Sem.SemExprSub(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprMul] = function(self, const_env)
            return pvm.once(Sem.SemExprMul(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprDiv] = function(self, const_env)
            return pvm.once(Sem.SemExprDiv(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprRem] = function(self, const_env)
            return pvm.once(Sem.SemExprRem(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprEq] = function(self, const_env)
            return pvm.once(Sem.SemExprEq(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprNe] = function(self, const_env)
            return pvm.once(Sem.SemExprNe(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprLt] = function(self, const_env)
            return pvm.once(Sem.SemExprLt(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprLe] = function(self, const_env)
            return pvm.once(Sem.SemExprLe(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprGt] = function(self, const_env)
            return pvm.once(Sem.SemExprGt(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprGe] = function(self, const_env)
            return pvm.once(Sem.SemExprGe(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprAnd] = function(self, const_env)
            return pvm.once(Sem.SemExprAnd(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprOr] = function(self, const_env)
            return pvm.once(Sem.SemExprOr(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprBitAnd] = function(self, const_env)
            return pvm.once(Sem.SemExprBitAnd(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprBitOr] = function(self, const_env)
            return pvm.once(Sem.SemExprBitOr(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprBitXor] = function(self, const_env)
            return pvm.once(Sem.SemExprBitXor(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprShl] = function(self, const_env)
            return pvm.once(Sem.SemExprShl(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprLShr] = function(self, const_env)
            return pvm.once(Sem.SemExprLShr(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprAShr] = function(self, const_env)
            return pvm.once(Sem.SemExprAShr(one_type(self.ty, const_env), one_expr(self.lhs, const_env), one_expr(self.rhs, const_env)))
        end,
        [Elab.ElabExprCastTo] = function(self, const_env)
            return pvm.once(Sem.SemExprCastTo(one_type(self.ty, const_env), one_expr(self.value, const_env)))
        end,
        [Elab.ElabExprTruncTo] = function(self, const_env)
            return pvm.once(Sem.SemExprTruncTo(one_type(self.ty, const_env), one_expr(self.value, const_env)))
        end,
        [Elab.ElabExprZExtTo] = function(self, const_env)
            return pvm.once(Sem.SemExprZExtTo(one_type(self.ty, const_env), one_expr(self.value, const_env)))
        end,
        [Elab.ElabExprSExtTo] = function(self, const_env)
            return pvm.once(Sem.SemExprSExtTo(one_type(self.ty, const_env), one_expr(self.value, const_env)))
        end,
        [Elab.ElabExprBitcastTo] = function(self, const_env)
            return pvm.once(Sem.SemExprBitcastTo(one_type(self.ty, const_env), one_expr(self.value, const_env)))
        end,
        [Elab.ElabExprSatCastTo] = function(self, const_env)
            return pvm.once(Sem.SemExprSatCastTo(one_type(self.ty, const_env), one_expr(self.value, const_env)))
        end,
        [Elab.ElabExprIntrinsicCall] = function(self, const_env)
            return pvm.once(Sem.SemExprIntrinsicCall(one_intrinsic(self.op), one_type(self.ty, const_env), lower_expr_list(self.args, const_env)))
        end,
        [Elab.ElabCall] = function(self, const_env)
            local fn_ty = one_type(one_elab_expr_type(self.callee), const_env)
            return pvm.once(Sem.SemExprCall(one_call_target_from_expr(self.callee, fn_ty, const_env), one_type(self.ty, const_env), lower_expr_list(self.args, const_env)))
        end,
        [Elab.ElabField] = function(self, const_env)
            return pvm.once(Sem.SemExprField(one_expr(self.base, const_env), Sem.SemFieldByName(self.name, one_type(self.ty, const_env))))
        end,
        [Elab.ElabIndex] = function(self, const_env)
            return pvm.once(Sem.SemExprIndex(one_index_base(self.base, const_env), one_expr(self.index, const_env), one_type(self.ty, const_env)))
        end,
        [Elab.ElabAgg] = function(self, const_env)
            return pvm.once(Sem.SemExprAgg(one_type(self.ty, const_env), lower_field_init_list(self.fields, const_env)))
        end,
        [Elab.ElabArrayLit] = function(self, const_env)
            return pvm.once(Sem.SemExprArrayLit(one_type(self.ty.elem, const_env), lower_expr_list(self.elems, const_env)))
        end,
        [Elab.ElabIfExpr] = function(self, const_env)
            return pvm.once(Sem.SemExprIf(one_expr(self.cond, const_env), one_expr(self.then_expr, const_env), one_expr(self.else_expr, const_env), one_type(self.ty, const_env)))
        end,
        [Elab.ElabSelectExpr] = function(self, const_env)
            return pvm.once(Sem.SemExprSelect(one_expr(self.cond, const_env), one_expr(self.then_expr, const_env), one_expr(self.else_expr, const_env), one_type(self.ty, const_env)))
        end,
        [Elab.ElabSwitchExpr] = function(self, const_env)
            return pvm.once(Sem.SemExprSwitch(one_expr(self.value, const_env), lower_switch_expr_arm_list(self.arms, const_env), one_expr(self.default_expr, const_env), one_type(self.ty, const_env)))
        end,
        [Elab.ElabLoopExprNode] = function(self, const_env)
            return pvm.once(Sem.SemExprLoop(one_loop(self.loop, const_env), one_type(self.ty, const_env)))
        end,
        [Elab.ElabBlockExpr] = function(self, const_env)
            return pvm.once(Sem.SemExprBlock(lower_stmt_list(self.stmts, const_env), one_expr(self.result, const_env), one_type(self.ty, const_env)))
        end,
    })

    lower_stmt = pvm.phase("elab_to_sem_stmt", {
        [Elab.ElabLet] = function(self, const_env)
            return pvm.once(Sem.SemStmtLet(self.id, self.name, one_type(self.ty, const_env), one_expr(self.init, const_env)))
        end,
        [Elab.ElabVar] = function(self, const_env)
            return pvm.once(Sem.SemStmtVar(self.id, self.name, one_type(self.ty, const_env), one_expr(self.init, const_env)))
        end,
        [Elab.ElabSet] = function(self, const_env)
            return pvm.once(Sem.SemStmtSet(one_place(self.place, const_env), one_expr(self.value, const_env)))
        end,
        [Elab.ElabExprStmt] = function(self, const_env)
            return pvm.once(Sem.SemStmtExpr(one_expr(self.expr, const_env)))
        end,
        [Elab.ElabIf] = function(self, const_env)
            return pvm.once(Sem.SemStmtIf(one_expr(self.cond, const_env), lower_stmt_list(self.then_body, const_env), lower_stmt_list(self.else_body, const_env)))
        end,
        [Elab.ElabSwitch] = function(self, const_env)
            return pvm.once(Sem.SemStmtSwitch(one_expr(self.value, const_env), lower_switch_stmt_arm_list(self.arms, const_env), lower_stmt_list(self.default_body, const_env)))
        end,
        [Elab.ElabReturnVoid] = function()
            return pvm.once(Sem.SemStmtReturnVoid)
        end,
        [Elab.ElabReturnValue] = function(self, const_env)
            return pvm.once(Sem.SemStmtReturnValue(one_expr(self.value, const_env)))
        end,
        [Elab.ElabBreak] = function()
            return pvm.once(Sem.SemStmtBreak)
        end,
        [Elab.ElabBreakValue] = function(self, const_env)
            return pvm.once(Sem.SemStmtBreakValue(one_expr(self.value, const_env)))
        end,
        [Elab.ElabContinue] = function()
            return pvm.once(Sem.SemStmtContinue)
        end,
        [Elab.ElabLoopStmtNode] = function(self, const_env)
            return pvm.once(Sem.SemStmtLoop(one_loop(self.loop, const_env)))
        end,
    })

    lower_func = pvm.phase("elab_to_sem_func", {
        [Elab.ElabFunc] = function(self, const_env)
            local params = {}
            for i = 1, #self.params do
                params[i] = one_param(self.params[i], const_env)
            end
            return pvm.once(Sem.SemFuncExport(self.name, params, one_type(self.result, const_env), lower_stmt_list(self.body, const_env)))
        end,
    })

    lower_extern_func = pvm.phase("elab_to_sem_extern_func", {
        [Elab.ElabExternFunc] = function(self, const_env)
            local params = {}
            for i = 1, #self.params do
                params[i] = one_param(self.params[i], const_env)
            end
            return pvm.once(Sem.SemExternFunc(self.name, self.symbol, params, one_type(self.result, const_env)))
        end,
    })

    lower_const = pvm.phase("elab_to_sem_const", {
        [Elab.ElabConst] = function(self, const_env)
            return pvm.once(Sem.SemConst(self.name, one_type(self.ty, const_env), one_expr(self.value, const_env)))
        end,
    })

    lower_static = pvm.phase("elab_to_sem_static", {
        [Elab.ElabStatic] = function(self, const_env)
            return pvm.once(Sem.SemStatic(self.name, one_type(self.ty, const_env), one_expr(self.value, const_env)))
        end,
    })

    lower_import = pvm.phase("elab_to_sem_import", {
        [Elab.ElabImport] = function(self)
            return pvm.once(Sem.SemImport(self.module_name))
        end,
    })

    lower_item = pvm.phase("elab_to_sem_item", {
        [Elab.ElabItemFunc] = function(self, const_env)
            return pvm.once(Sem.SemItemFunc(one_func(self.func, const_env)))
        end,
        [Elab.ElabItemExtern] = function(self, const_env)
            return pvm.once(Sem.SemItemExtern(one_extern_func(self.func, const_env)))
        end,
        [Elab.ElabItemConst] = function(self, const_env)
            return pvm.once(Sem.SemItemConst(one_const(self.c, const_env)))
        end,
        [Elab.ElabItemStatic] = function(self, const_env)
            return pvm.once(Sem.SemItemStatic(one_static(self.s, const_env)))
        end,
        [Elab.ElabItemImport] = function(self)
            return pvm.once(Sem.SemItemImport(one_import(self.imp)))
        end,
        [Elab.ElabItemType] = function(self, const_env)
            return pvm.once(Sem.SemItemType(one_type_decl(self.t, const_env)))
        end,
    })

    lower_module = pvm.phase("elab_to_sem_module", {
        [Elab.ElabModule] = function(self, const_env)
            local env = ensure_const_env(const_env)
            local entries = {}
            for i = 1, #env.entries do
                entries[i] = env.entries[i]
            end
            for i = 1, #self.items do
                local item = self.items[i]
                if item.c ~= nil then
                    entries[#entries + 1] = Elab.ElabConstEntry(self.module_name, item.c.name, item.c.ty, item.c.value)
                end
            end
            local module_const_env = Elab.ElabConstEnv(entries)
            local items = {}
            for i = 1, #self.items do
                items[i] = one_item(self.items[i], module_const_env)
            end
            return pvm.once(Sem.SemModule(self.module_name, items))
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
        lower_static = lower_static,
        lower_item = lower_item,
        lower_module = lower_module,
        elab_expr_type = elab_expr_type,
        sem_expr_type = sem_expr_type,
    }
end

return M
