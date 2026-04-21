package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.Define(T)
    local Sem = T.MoonliftSem
    local Back = T.MoonliftBack

    local lower_scalar
    local lower_type_is_scalar
    local lower_stack_slot_spec
    local lower_binding_value
    local lower_binding_expr
    local lower_binding_addr
    local lower_binding_store_addr
    local lower_type_mem_size
    local lower_field_ref_type
    local lower_field_addr_from_ref
    local lower_field_expr_from_ref
    local lower_sig_spec
    local lower_expr
    local lower_stmt
    local lower_expr_stmt
    local lower_expr_lowering_has_value
    local lower_expr_lowering_flow
    local lower_addr_lowering_continues
    local lower_addr_lowering_flow
    local lower_call_value
    local sem_expr_type
    local lower_add_cmd
    local lower_sub_cmd
    local lower_mul_cmd
    local lower_div_cmd
    local lower_rem_cmd
    local lower_lt_cmd
    local lower_le_cmd
    local lower_gt_cmd
    local lower_ge_cmd
    local lower_eq_cmd
    local lower_ne_cmd
    local lower_neg_cmd
    local lower_not_cmd
    local lower_bnot_cmd
    local lower_and_cmd
    local lower_or_cmd
    local lower_band_cmd
    local lower_bor_cmd
    local lower_bxor_cmd
    local lower_shl_cmd
    local lower_lshr_cmd
    local lower_ashr_cmd
    local lower_loop_stmt_plan
    local lower_loop_expr_plan
    local lower_loop_expr_into_addr
    local lower_over_stmt_domain
    local lower_over_expr_domain
    local lower_over_expr_into_addr_domain
    local lower_over_index_value
    local lower_addr_of_expr
    local lower_index_base_addr
    local lower_index_addr_from_base_type
    local lower_const_agg_init_from_type
    local lower_const_data_init
    local lower_agg_expr_into_addr_from_type
    local lower_copy_type_addr
    local lower_expr_into_addr
    local lower_func
    local lower_item
    local lower_module

    local function one_scalar(node)
        return pvm.one(lower_scalar(node))
    end

    local function one_type_is_scalar(node)
        return pvm.one(lower_type_is_scalar(node))
    end

    local function one_stack_slot_spec(node, layout_env)
        return pvm.one(lower_stack_slot_spec(node, layout_env))
    end

    local function one_binding_value(node)
        return pvm.one(lower_binding_value(node))
    end

    local function one_binding_expr(node, path)
        return pvm.one(lower_binding_expr(node, path))
    end

    local function one_binding_addr(node, path)
        return pvm.one(lower_binding_addr(node, path))
    end

    local function one_binding_store_addr(node, path)
        return pvm.one(lower_binding_store_addr(node, path))
    end

    local function one_type_mem_size(node, layout_env)
        return pvm.one(lower_type_mem_size(node, layout_env))
    end

    local function one_field_ref_type(node)
        return pvm.one(lower_field_ref_type(node))
    end

    local function one_field_addr_from_ref(node, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args)
        return pvm.one(lower_field_addr_from_ref(node, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args))
    end

    local function one_field_expr_from_ref(node, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args)
        return pvm.one(lower_field_expr_from_ref(node, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args))
    end

    local function one_sig_spec(node)
        return pvm.one(lower_sig_spec(node))
    end

    local function one_expr(node, path, layout_env, break_block, break_args, continue_block, continue_args)
        return pvm.one(lower_expr(node, path, layout_env, break_block, break_args, continue_block, continue_args))
    end

    local function one_stmt(node, path, layout_env, break_block, break_args, continue_block, continue_args)
        return pvm.one(lower_stmt(node, path, layout_env, break_block, break_args, continue_block, continue_args))
    end

    local function one_expr_stmt(node, path, layout_env, break_block, break_args, continue_block, continue_args)
        return pvm.one(lower_expr_stmt(node, path, layout_env, break_block, break_args, continue_block, continue_args))
    end

    local function one_loop_stmt_plan(node, path, layout_env)
        return pvm.one(lower_loop_stmt_plan(node, path, layout_env))
    end

    local function one_loop_expr_plan(node, path, layout_env)
        return pvm.one(lower_loop_expr_plan(node, path, layout_env))
    end

    local function one_loop_expr_into_addr(node, addr, path, layout_env)
        return pvm.one(lower_loop_expr_into_addr(node, addr, path, layout_env))
    end

    local function one_over_stmt_domain(node, loop, path, layout_env)
        return pvm.one(lower_over_stmt_domain(node, loop, path, layout_env))
    end

    local function one_over_expr_domain(node, loop, path, layout_env)
        return pvm.one(lower_over_expr_domain(node, loop, path, layout_env))
    end

    local function one_over_expr_into_addr_domain(node, loop, addr, path, layout_env)
        return pvm.one(lower_over_expr_into_addr_domain(node, loop, addr, path, layout_env))
    end

    local function one_over_index_value(node)
        return pvm.one(lower_over_index_value(node))
    end

    local function one_addr_of_expr(node, path, layout_env, break_block, break_args, continue_block, continue_args)
        return pvm.one(lower_addr_of_expr(node, path, layout_env, break_block, break_args, continue_block, continue_args))
    end

    local function one_index_base_addr(node, index, elem_size, path, layout_env, break_block, break_args, continue_block, continue_args)
        return pvm.one(lower_index_base_addr(node, index, elem_size, path, layout_env, break_block, break_args, continue_block, continue_args))
    end

    local function one_index_addr_from_base_type(node, base_expr, index_expr, elem_ty, path, layout_env, break_block, break_args, continue_block, continue_args)
        return pvm.one(lower_index_addr_from_base_type(node, base_expr, index_expr, elem_ty, path, layout_env, break_block, break_args, continue_block, continue_args))
    end

    local function one_const_data_init(node, data_id, offset, layout_env)
        return pvm.one(lower_const_data_init(node, data_id, offset, layout_env))
    end

    local function one_copy_type_addr(node, src_addr, dst_addr, path, layout_env)
        return pvm.one(lower_copy_type_addr(node, src_addr, dst_addr, path, layout_env))
    end

    local function one_expr_into_addr(node, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
        return pvm.one(lower_expr_into_addr(node, addr, path, layout_env, break_block, break_args, continue_block, continue_args))
    end

    local function one_func(node, layout_env)
        return pvm.one(lower_func(node, layout_env))
    end

    local function one_item(node, layout_env)
        return pvm.one(lower_item(node, layout_env))
    end

    local function one_module(node, layout_env)
        return pvm.one(lower_module(node, layout_env))
    end

    local function one_sem_expr_type(node)
        return pvm.one(sem_expr_type(node))
    end

    local function one_call_value(node, dst, ret_ty, path, args, layout_env, break_block, break_args, continue_block, continue_args)
        return pvm.one(lower_call_value(node, dst, ret_ty, path, args, layout_env, break_block, break_args, continue_block, continue_args))
    end

    local function one_add_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_add_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_sub_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_sub_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_mul_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_mul_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_div_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_div_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_rem_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_rem_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_lt_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_lt_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_le_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_le_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_gt_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_gt_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_ge_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_ge_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_eq_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_eq_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_ne_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_ne_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_neg_cmd(node, dst, ty, value)
        return pvm.one(lower_neg_cmd(node, dst, ty, value))
    end

    local function one_not_cmd(node, dst, value)
        return pvm.one(lower_not_cmd(node, dst, value))
    end

    local function one_bnot_cmd(node, dst, ty, value)
        return pvm.one(lower_bnot_cmd(node, dst, ty, value))
    end

    local function one_and_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_and_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_or_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_or_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_band_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_band_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_bor_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_bor_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_bxor_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_bxor_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_shl_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_shl_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_lshr_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_lshr_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_ashr_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(lower_ashr_cmd(node, dst, ty, lhs, rhs))
    end

    local function copy_cmds(src, out)
        for i = 1, #src do
            out[#out + 1] = src[i]
        end
    end

    local function append_expr_cmds(out, plan)
        copy_cmds(plan.cmds, out)
    end

    local function expr_has_value(plan)
        return pvm.one(lower_expr_lowering_has_value(plan))
    end

    local function expr_terminates(plan)
        return pvm.one(lower_expr_lowering_flow(plan)) == Back.BackTerminates
    end

    local function expr_to_stmt_flow(plan)
        return pvm.one(lower_expr_lowering_flow(plan))
    end

    local function terminated_expr(cmds)
        return Back.BackExprTerminated(cmds)
    end

    local function addr_continues(plan)
        return pvm.one(lower_addr_lowering_continues(plan))
    end

    local function addr_terminates(plan)
        return pvm.one(lower_addr_lowering_flow(plan)) == Back.BackTerminates
    end

    local function addr_to_stmt_flow(plan)
        return pvm.one(lower_addr_lowering_flow(plan))
    end

    local function addr_writes(cmds)
        return Back.BackAddrWrites(cmds)
    end

    local function terminated_addr(cmds)
        return Back.BackAddrTerminated(cmds)
    end

    local function append_addr_cmds(out, plan)
        copy_cmds(plan.cmds, out)
    end

    local function append_stmt_cmds(out, plan)
        copy_cmds(plan.cmds, out)
    end

    local function stmt_falls_through(plan)
        return plan.flow == Back.BackFallsThrough
    end

    local function append_expr_and_keep_value(out, plan)
        append_expr_cmds(out, plan)
        return expr_has_value(plan)
    end

    local function lower_stmt_list(nodes, base_path, layout_env, break_block, break_args, continue_block, continue_args)
        local cmds = {}
        local flow = Back.BackFallsThrough
        for i = 1, #nodes do
            if flow == Back.BackTerminates then
                break
            end
            local plan = one_stmt(nodes[i], base_path .. ".stmt." .. i, layout_env, break_block, break_args, continue_block, continue_args)
            append_stmt_cmds(cmds, plan)
            flow = plan.flow
        end
        return cmds, flow
    end

    local function func_id_text(module_name, func_name)
        if module_name == "" then
            return func_name
        end
        return module_name .. "::" .. func_name
    end

    local function local_value_id(id)
        return Back.BackValId("local:" .. id)
    end

    local function local_value_slot_id(id)
        return Back.BackStackSlotId("slot:local:" .. id)
    end

    local function arg_slot_id(index, name)
        return Back.BackStackSlotId("slot:arg:" .. index .. ":" .. name)
    end

    local function local_cell_slot_id(id)
        return Back.BackStackSlotId("slot:" .. id)
    end

    local function temp_slot_id(path)
        return Back.BackStackSlotId(path .. ".slot")
    end

    local function materialize_expr_temp(expr, ty, path, layout_env, break_block, break_args, continue_block, continue_args)
        local spec = one_stack_slot_spec(ty, layout_env)
        local addr = Back.BackValId(path)
        local cmds = {
            Back.BackCmdCreateStackSlot(temp_slot_id(path), spec.size, spec.align),
            Back.BackCmdStackAddr(addr, temp_slot_id(path)),
        }
        local init = one_expr_into_addr(expr, addr, path .. ".init", layout_env, break_block, break_args, continue_block, continue_args)
        append_addr_cmds(cmds, init)
        if addr_terminates(init) then
            return terminated_expr(cmds)
        end
        return Back.BackExprPlan(cmds, addr, Back.BackPtr)
    end

    local function const_data_key(module_name, item_name)
        if module_name == nil or module_name == "" then
            return item_name
        end
        return module_name .. "::" .. item_name
    end

    local function const_data_id(module_name, item_name)
        return Back.BackDataId("data:const:" .. const_data_key(module_name, item_name))
    end

    local function find_named_layout(layout_env, module_name, type_name)
        local layouts = layout_env and layout_env.layouts or nil
        if layouts == nil then return nil end
        for i = 1, #layouts do
            local layout = layouts[i]
            if layout.module_name == module_name and layout.type_name == type_name then
                return layout
            end
        end
        return nil
    end

    local function find_layout_field(layout, field_name)
        for i = 1, #layout.fields do
            local field = layout.fields[i]
            if field.field_name == field_name then
                return field
            end
        end
        return nil
    end

    local function find_field_init(fields, field_name)
        for i = 1, #fields do
            if fields[i].name == field_name then
                return fields[i]
            end
        end
        return nil
    end

    local function require_named_layout(layout_env, module_name, type_name)
        local layout = find_named_layout(layout_env, module_name, type_name)
        if layout == nil then
            error("sem_to_back: missing layout for named type '" .. const_data_key(module_name, type_name) .. "'")
        end
        return layout
    end

    local function emit_aliases_for_loop_bindings(cmds, bindings, param_ids)
        for i = 1, #bindings do
            cmds[#cmds + 1] = Back.BackCmdAlias(local_value_id(bindings[i].id), param_ids[i])
        end
    end

    local function emit_alias_for_index_binding(cmds, binding, value_id)
        cmds[#cmds + 1] = Back.BackCmdAlias(one_over_index_value(binding), value_id)
    end

    local function loop_binding_value_args(bindings)
        local args = {}
        for i = 1, #bindings do
            args[i] = local_value_id(bindings[i].id)
        end
        return args
    end

    local function over_loop_current_args(index_binding, carries)
        local args = { one_over_index_value(index_binding) }
        for i = 1, #carries do
            args[#args + 1] = local_value_id(carries[i].id)
        end
        return args
    end

    local function eval_loop_nexts(nexts, path, layout_env)
        local cmds = {}
        local values = {}
        for i = 1, #nexts do
            local expr = one_expr(nexts[i].value, path .. ".next." .. i, layout_env)
            append_expr_cmds(cmds, expr)
            if expr_terminates(expr) then
                return cmds, values, Back.BackTerminates
            end
            values[i] = expr.value
        end
        return cmds, values, Back.BackFallsThrough
    end

    lower_scalar = pvm.phase("sem_to_back_scalar", {
        [Sem.SemTVoid] = function() return pvm.once(Back.BackVoid) end,
        [Sem.SemTBool] = function() return pvm.once(Back.BackBool) end,
        [Sem.SemTI8] = function() return pvm.once(Back.BackI8) end,
        [Sem.SemTI16] = function() return pvm.once(Back.BackI16) end,
        [Sem.SemTI32] = function() return pvm.once(Back.BackI32) end,
        [Sem.SemTI64] = function() return pvm.once(Back.BackI64) end,
        [Sem.SemTU8] = function() return pvm.once(Back.BackU8) end,
        [Sem.SemTU16] = function() return pvm.once(Back.BackU16) end,
        [Sem.SemTU32] = function() return pvm.once(Back.BackU32) end,
        [Sem.SemTU64] = function() return pvm.once(Back.BackU64) end,
        [Sem.SemTF32] = function() return pvm.once(Back.BackF32) end,
        [Sem.SemTF64] = function() return pvm.once(Back.BackF64) end,
        [Sem.SemTPtr] = function() return pvm.once(Back.BackPtr) end,
        [Sem.SemTIndex] = function() return pvm.once(Back.BackIndex) end,
        [Sem.SemTPtrTo] = function() return pvm.once(Back.BackPtr) end,
    })

    lower_type_is_scalar = pvm.phase("sem_to_back_type_is_scalar", {
        [Sem.SemTVoid] = function() return pvm.once(true) end,
        [Sem.SemTBool] = function() return pvm.once(true) end,
        [Sem.SemTI8] = function() return pvm.once(true) end,
        [Sem.SemTI16] = function() return pvm.once(true) end,
        [Sem.SemTI32] = function() return pvm.once(true) end,
        [Sem.SemTI64] = function() return pvm.once(true) end,
        [Sem.SemTU8] = function() return pvm.once(true) end,
        [Sem.SemTU16] = function() return pvm.once(true) end,
        [Sem.SemTU32] = function() return pvm.once(true) end,
        [Sem.SemTU64] = function() return pvm.once(true) end,
        [Sem.SemTF32] = function() return pvm.once(true) end,
        [Sem.SemTF64] = function() return pvm.once(true) end,
        [Sem.SemTPtr] = function() return pvm.once(true) end,
        [Sem.SemTIndex] = function() return pvm.once(true) end,
        [Sem.SemTPtrTo] = function() return pvm.once(true) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    lower_stack_slot_spec = pvm.phase("sem_to_back_stack_slot_spec", {
        [Sem.SemTBool] = function() return pvm.once(Back.BackStackSlotSpec(1, 1)) end,
        [Sem.SemTI8] = function() return pvm.once(Back.BackStackSlotSpec(1, 1)) end,
        [Sem.SemTU8] = function() return pvm.once(Back.BackStackSlotSpec(1, 1)) end,
        [Sem.SemTI16] = function() return pvm.once(Back.BackStackSlotSpec(2, 2)) end,
        [Sem.SemTU16] = function() return pvm.once(Back.BackStackSlotSpec(2, 2)) end,
        [Sem.SemTI32] = function() return pvm.once(Back.BackStackSlotSpec(4, 4)) end,
        [Sem.SemTU32] = function() return pvm.once(Back.BackStackSlotSpec(4, 4)) end,
        [Sem.SemTF32] = function() return pvm.once(Back.BackStackSlotSpec(4, 4)) end,
        [Sem.SemTI64] = function() return pvm.once(Back.BackStackSlotSpec(8, 8)) end,
        [Sem.SemTU64] = function() return pvm.once(Back.BackStackSlotSpec(8, 8)) end,
        [Sem.SemTF64] = function() return pvm.once(Back.BackStackSlotSpec(8, 8)) end,
        [Sem.SemTPtr] = function() return pvm.once(Back.BackStackSlotSpec(8, 8)) end,
        [Sem.SemTIndex] = function() return pvm.once(Back.BackStackSlotSpec(8, 8)) end,
        [Sem.SemTPtrTo] = function() return pvm.once(Back.BackStackSlotSpec(8, 8)) end,
        [Sem.SemTArray] = function(self, layout_env)
            return pvm.once(Back.BackStackSlotSpec(one_type_mem_size(self, layout_env), one_stack_slot_spec(self.elem, layout_env).align))
        end,
        [Sem.SemTNamed] = function(self, layout_env)
            local layout = require_named_layout(layout_env, self.module_name, self.type_name)
            return pvm.once(Back.BackStackSlotSpec(layout.size, layout.align))
        end,
    })

    lower_binding_value = pvm.phase("sem_to_back_binding_value", {
        [Sem.SemBindLocalValue] = function(self)
            return pvm.once(local_value_id(self.id))
        end,
        [Sem.SemBindLocalStoredValue] = function(self)
            return pvm.once(local_value_id(self.id))
        end,
        [Sem.SemBindArg] = function(self)
            return pvm.once(Back.BackValId("arg:" .. self.index .. ":" .. self.name))
        end,
    })

    lower_binding_expr = pvm.phase("sem_to_back_binding_expr", {
        [Sem.SemBindLocalValue] = function(self)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar immutable local '" .. self.name .. "' has no direct value form in Sem->Back; use address-based access")
            end
            local ty = one_scalar(self.ty)
            local value = local_value_id(self.id)
            return pvm.once(Back.BackExprPlan({}, value, ty))
        end,
        [Sem.SemBindLocalStoredValue] = function(self)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar immutable local '" .. self.name .. "' has no direct value form in Sem->Back; use address-based access")
            end
            local ty = one_scalar(self.ty)
            local value = local_value_id(self.id)
            return pvm.once(Back.BackExprPlan({}, value, ty))
        end,
        [Sem.SemBindArg] = function(self)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar argument '" .. self.name .. "' has no direct value form in Sem->Back")
            end
            local ty = one_scalar(self.ty)
            local value = Back.BackValId("arg:" .. self.index .. ":" .. self.name)
            return pvm.once(Back.BackExprPlan({}, value, ty))
        end,
        [Sem.SemBindLocalCell] = function(self, path)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar mutable local '" .. self.name .. "' has no direct value form in Sem->Back; use address-based access")
            end
            local addr = Back.BackValId(path .. ".addr")
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, local_cell_slot_id(self.id)),
                Back.BackCmdLoad(dst, ty, addr),
            }, dst, ty))
        end,
        [Sem.SemBindGlobal] = function(self, path)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar global '" .. self.item_name .. "' has no direct value form in Sem->Back; use address-based access")
            end
            local addr = Back.BackValId(path .. ".addr")
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            local data_id = const_data_id(self.module_name, self.item_name)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdDataAddr(addr, data_id),
                Back.BackCmdLoad(dst, ty, addr),
            }, dst, ty))
        end,
        [Sem.SemBindExtern] = function(self)
            error("sem_to_back_binding_expr: direct extern binding reads are not yet supported ('" .. self.symbol .. "')")
        end,
    })

    lower_binding_addr = pvm.phase("sem_to_back_binding_addr", {
        [Sem.SemBindLocalCell] = function(self, path)
            local addr = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, local_cell_slot_id(self.id)),
            }, addr, Back.BackPtr))
        end,
        [Sem.SemBindGlobal] = function(self, path)
            local addr = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdDataAddr(addr, const_data_id(self.module_name, self.item_name)),
            }, addr, Back.BackPtr))
        end,
        [Sem.SemBindLocalValue] = function(self)
            error("sem_to_back_binding_addr: pure immutable local '" .. self.name .. "' has no canonical storage in Sem->Back")
        end,
        [Sem.SemBindLocalStoredValue] = function(self, path)
            local addr = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, local_value_slot_id(self.id)),
            }, addr, Back.BackPtr))
        end,
        [Sem.SemBindArg] = function(self, path)
            local addr = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, arg_slot_id(self.index, self.name)),
            }, addr, Back.BackPtr))
        end,
        [Sem.SemBindExtern] = function(self)
            error("sem_to_back_binding_addr: extern '" .. self.symbol .. "' has no addressable storage in Sem->Back")
        end,
    })

    lower_binding_store_addr = pvm.phase("sem_to_back_binding_store_addr", {
        [Sem.SemBindLocalCell] = function(self, path)
            local addr = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, local_cell_slot_id(self.id)),
            }, addr, Back.BackPtr))
        end,
        [Sem.SemBindLocalValue] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to immutable local '" .. self.name .. "'")
        end,
        [Sem.SemBindLocalStoredValue] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to immutable local '" .. self.name .. "'")
        end,
        [Sem.SemBindArg] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to argument '" .. self.name .. "'")
        end,
        [Sem.SemBindGlobal] = function(self)
            error("sem_to_back_binding_store_addr: global set lowering is not yet supported ('" .. self.item_name .. "')")
        end,
        [Sem.SemBindExtern] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to extern '" .. self.symbol .. "'")
        end,
    })

    lower_type_mem_size = pvm.phase("sem_to_back_type_mem_size", {
        [Sem.SemTBool] = function() return pvm.once(1) end,
        [Sem.SemTI8] = function() return pvm.once(1) end,
        [Sem.SemTU8] = function() return pvm.once(1) end,
        [Sem.SemTI16] = function() return pvm.once(2) end,
        [Sem.SemTU16] = function() return pvm.once(2) end,
        [Sem.SemTI32] = function() return pvm.once(4) end,
        [Sem.SemTU32] = function() return pvm.once(4) end,
        [Sem.SemTF32] = function() return pvm.once(4) end,
        [Sem.SemTI64] = function() return pvm.once(8) end,
        [Sem.SemTU64] = function() return pvm.once(8) end,
        [Sem.SemTF64] = function() return pvm.once(8) end,
        [Sem.SemTPtr] = function() return pvm.once(8) end,
        [Sem.SemTIndex] = function() return pvm.once(8) end,
        [Sem.SemTPtrTo] = function() return pvm.once(8) end,
        [Sem.SemTVoid] = function()
            error("sem_to_back_type_mem_size: void has no storable size")
        end,
        [Sem.SemTArray] = function(self, layout_env)
            return pvm.once(one_type_mem_size(self.elem, layout_env) * self.count)
        end,
        [Sem.SemTSlice] = function()
            error("sem_to_back_type_mem_size: slice element sizing is not yet supported in Sem->Back")
        end,
        [Sem.SemTFunc] = function()
            error("sem_to_back_type_mem_size: function values have no plain memory size in Sem->Back")
        end,
        [Sem.SemTNamed] = function(self, layout_env)
            return pvm.once(require_named_layout(layout_env, self.module_name, self.type_name).size)
        end,
    })

    lower_field_ref_type = pvm.phase("sem_to_back_field_ref_type", {
        [Sem.SemFieldByName] = function(self) return pvm.once(self.ty) end,
        [Sem.SemFieldByOffset] = function(self) return pvm.once(self.ty) end,
    })

    lower_field_addr_from_ref = pvm.phase("sem_to_back_field_addr_from_ref", {
        [Sem.SemFieldByName] = function(self)
            error("sem_to_back_field_addr_from_ref: field layout is not yet resolved for '" .. self.field_name .. "'; Sem->Back needs an explicit offset-resolved field")
        end,
        [Sem.SemFieldByOffset] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args)
            local base = one_addr_of_expr(base_expr, path .. ".base", layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local offset = Back.BackValId(path .. ".offset")
            local cmds = {}
            append_expr_cmds(cmds, base)
            if expr_terminates(base) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdConstInt(offset, Back.BackIndex, tostring(self.offset))
            cmds[#cmds + 1] = one_add_cmd(Sem.SemTPtr, dst, Back.BackPtr, base.value, offset)
            return pvm.once(Back.BackExprPlan(cmds, dst, Back.BackPtr))
        end,
    })

    lower_field_expr_from_ref = pvm.phase("sem_to_back_field_expr_from_ref", {
        [Sem.SemFieldByName] = function(self)
            error("sem_to_back_field_expr_from_ref: field layout is not yet resolved for '" .. self.field_name .. "'; Sem->Back needs an explicit offset-resolved field")
        end,
        [Sem.SemFieldByOffset] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_field_expr_from_ref: non-scalar field '" .. self.field_name .. "' has no direct value form in Sem->Back; use address-based access")
            end
            local addr = one_field_addr_from_ref(self, base_expr, path .. ".addr", layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            local cmds = {}
            append_expr_cmds(cmds, addr)
            if expr_terminates(addr) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdLoad(dst, ty, addr.value)
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
    })

    lower_sig_spec = pvm.phase("sem_to_back_sig_spec", {
        [Sem.SemTFunc] = function(self)
            local params = {}
            local results = {}
            for i = 1, #self.params do
                params[i] = one_scalar(self.params[i])
            end
            if self.result ~= Sem.SemTVoid then
                results[1] = one_scalar(self.result)
            end
            return pvm.once(Back.BackSigSpec(params, results))
        end,
    })

    lower_neg_cmd = pvm.phase("sem_to_back_neg_cmd", {
        [Sem.SemTI8] = function(self, dst, ty, value) return pvm.once(Back.BackCmdIneg(dst, ty, value)) end,
        [Sem.SemTI16] = function(self, dst, ty, value) return pvm.once(Back.BackCmdIneg(dst, ty, value)) end,
        [Sem.SemTI32] = function(self, dst, ty, value) return pvm.once(Back.BackCmdIneg(dst, ty, value)) end,
        [Sem.SemTI64] = function(self, dst, ty, value) return pvm.once(Back.BackCmdIneg(dst, ty, value)) end,
        [Sem.SemTF32] = function(self, dst, ty, value) return pvm.once(Back.BackCmdFneg(dst, ty, value)) end,
        [Sem.SemTF64] = function(self, dst, ty, value) return pvm.once(Back.BackCmdFneg(dst, ty, value)) end,
    })

    lower_add_cmd = pvm.phase("sem_to_back_add_cmd", {
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

    lower_sub_cmd = pvm.phase("sem_to_back_sub_cmd", {
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

    lower_mul_cmd = pvm.phase("sem_to_back_mul_cmd", {
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

    lower_div_cmd = pvm.phase("sem_to_back_div_cmd", {
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

    lower_rem_cmd = pvm.phase("sem_to_back_rem_cmd", {
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

    lower_lt_cmd = pvm.phase("sem_to_back_lt_cmd", {
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

    lower_le_cmd = pvm.phase("sem_to_back_le_cmd", {
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

    lower_gt_cmd = pvm.phase("sem_to_back_gt_cmd", {
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

    lower_ge_cmd = pvm.phase("sem_to_back_ge_cmd", {
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

    lower_eq_cmd = pvm.phase("sem_to_back_eq_cmd", {
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

    lower_ne_cmd = pvm.phase("sem_to_back_ne_cmd", {
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

    lower_not_cmd = pvm.phase("sem_to_back_not_cmd", {
        [Sem.SemTBool] = function(self, dst, value) return pvm.once(Back.BackCmdBoolNot(dst, value)) end,
    })

    lower_bnot_cmd = pvm.phase("sem_to_back_bnot_cmd", {
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

    lower_and_cmd = pvm.phase("sem_to_back_and_cmd", {
        [Sem.SemTBool] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBand(dst, ty, lhs, rhs)) end,
    })

    lower_or_cmd = pvm.phase("sem_to_back_or_cmd", {
        [Sem.SemTBool] = function(self, dst, ty, lhs, rhs) return pvm.once(Back.BackCmdBor(dst, ty, lhs, rhs)) end,
    })

    lower_band_cmd = pvm.phase("sem_to_back_band_cmd", {
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

    lower_bor_cmd = pvm.phase("sem_to_back_bor_cmd", {
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

    lower_bxor_cmd = pvm.phase("sem_to_back_bxor_cmd", {
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

    lower_shl_cmd = pvm.phase("sem_to_back_shl_cmd", {
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

    lower_lshr_cmd = pvm.phase("sem_to_back_lshr_cmd", {
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

    lower_ashr_cmd = pvm.phase("sem_to_back_ashr_cmd", {
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

    sem_expr_type = pvm.phase("sem_expr_type_for_back", {
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
        [Sem.SemExprField] = function(self) return pvm.once(one_field_ref_type(self.field)) end,
        [Sem.SemExprIndexAddr] = function() return pvm.once(Sem.SemTPtr) end,
        [Sem.SemExprFieldAddr] = function() return pvm.once(Sem.SemTPtr) end,
        [Sem.SemExprLoad] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprIntrinsicCall] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprIf] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprCall] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprLoop] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprAgg] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprArrayLit] = function(self) return pvm.once(Sem.SemTArray(self.elem_ty, #self.elems)) end,
        [Sem.SemExprBlock] = function(self) return pvm.once(self.ty) end,
        [Sem.SemExprSwitch] = function(self) return pvm.once(self.ty) end,
    })

    lower_expr_lowering_has_value = pvm.phase("back_expr_lowering_has_value", {
        [Back.BackExprPlan] = function()
            return pvm.once(true)
        end,
        [Back.BackExprTerminated] = function()
            return pvm.once(false)
        end,
    })

    lower_expr_lowering_flow = pvm.phase("back_expr_lowering_flow", {
        [Back.BackExprPlan] = function()
            return pvm.once(Back.BackFallsThrough)
        end,
        [Back.BackExprTerminated] = function()
            return pvm.once(Back.BackTerminates)
        end,
    })

    lower_addr_lowering_continues = pvm.phase("back_addr_lowering_continues", {
        [Back.BackAddrWrites] = function()
            return pvm.once(true)
        end,
        [Back.BackAddrTerminated] = function()
            return pvm.once(false)
        end,
    })

    lower_addr_lowering_flow = pvm.phase("back_addr_lowering_flow", {
        [Back.BackAddrWrites] = function()
            return pvm.once(Back.BackFallsThrough)
        end,
        [Back.BackAddrTerminated] = function()
            return pvm.once(Back.BackTerminates)
        end,
    })

    lower_index_base_addr = pvm.phase("sem_to_back_index_base_addr", {
        [Sem.SemIndexBasePtr] = function(self, index, elem_size, path, layout_env, break_block, break_args, continue_block, continue_args)
            local index_ty = one_sem_expr_type(index)
            if index_ty ~= Sem.SemTIndex then
                error("sem_to_back_index_base_addr: pointer indexing currently requires an explicit SemTIndex index expression")
            end
            local base = one_expr(self.base, path .. ".base", layout_env, break_block, break_args, continue_block, continue_args)
            local idx = one_expr(index, path .. ".index", layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local cmds = {}
            append_expr_cmds(cmds, base)
            if expr_terminates(base) then
                return pvm.once(terminated_expr(cmds))
            end
            append_expr_cmds(cmds, idx)
            if expr_terminates(idx) then
                return pvm.once(terminated_expr(cmds))
            end
            local scaled = idx.value
            if elem_size ~= 1 then
                local size_id = Back.BackValId(path .. ".elem_size")
                local mul_id = Back.BackValId(path .. ".scaled_index")
                cmds[#cmds + 1] = Back.BackCmdConstInt(size_id, Back.BackIndex, tostring(elem_size))
                cmds[#cmds + 1] = one_mul_cmd(Sem.SemTIndex, mul_id, Back.BackIndex, idx.value, size_id)
                scaled = mul_id
            end
            cmds[#cmds + 1] = one_add_cmd(Sem.SemTPtr, dst, Back.BackPtr, base.value, scaled)
            return pvm.once(Back.BackExprPlan(cmds, dst, Back.BackPtr))
        end,
        [Sem.SemIndexBaseView] = function()
            error("sem_to_back_index_base_addr: view-based indexing is not yet supported; slice/view layout and bounds lowering must be made explicit first")
        end,
    })

    lower_index_addr_from_base_type = pvm.phase("sem_to_back_index_addr_from_base_type", {
        [Sem.SemTPtrTo] = function(self, base_expr, index_expr, elem_ty, path, layout_env, break_block, break_args, continue_block, continue_args)
            if self.elem ~= elem_ty then
                error("sem_to_back_index_addr_from_base_type: pointer element type does not match indexed result type")
            end
            return pvm.once(one_index_base_addr(Sem.SemIndexBasePtr(base_expr, self.elem), index_expr, one_type_mem_size(elem_ty), path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemTSlice] = function()
            error("sem_to_back_index_addr_from_base_type: slice indexing is not yet supported; slice/view representation must be lowered explicitly first")
        end,
        [Sem.SemTArray] = function()
            error("sem_to_back_index_addr_from_base_type: array-value indexing is not yet supported; aggregate storage/layout lowering must be explicit first")
        end,
        [Sem.SemTPtr] = function()
            error("sem_to_back_index_addr_from_base_type: raw SemTPtr indexing is not yet supported; use SemTPtrTo(element) so element layout is explicit")
        end,
        [Sem.SemTNamed] = function(self)
            error("sem_to_back_index_addr_from_base_type: named base type indexing is not yet supported ('" .. self.type_name .. "')")
        end,
        [Sem.SemTBool] = function()
            error("sem_to_back_index_addr_from_base_type: cannot index a non-pointer scalar base")
        end,
        [Sem.SemTI8] = function() error("sem_to_back_index_addr_from_base_type: cannot index a non-pointer scalar base") end,
        [Sem.SemTI16] = function() error("sem_to_back_index_addr_from_base_type: cannot index a non-pointer scalar base") end,
        [Sem.SemTI32] = function() error("sem_to_back_index_addr_from_base_type: cannot index a non-pointer scalar base") end,
        [Sem.SemTI64] = function() error("sem_to_back_index_addr_from_base_type: cannot index a non-pointer scalar base") end,
        [Sem.SemTU8] = function() error("sem_to_back_index_addr_from_base_type: cannot index a non-pointer scalar base") end,
        [Sem.SemTU16] = function() error("sem_to_back_index_addr_from_base_type: cannot index a non-pointer scalar base") end,
        [Sem.SemTU32] = function() error("sem_to_back_index_addr_from_base_type: cannot index a non-pointer scalar base") end,
        [Sem.SemTU64] = function() error("sem_to_back_index_addr_from_base_type: cannot index a non-pointer scalar base") end,
        [Sem.SemTF32] = function() error("sem_to_back_index_addr_from_base_type: cannot index a non-pointer scalar base") end,
        [Sem.SemTF64] = function() error("sem_to_back_index_addr_from_base_type: cannot index a non-pointer scalar base") end,
        [Sem.SemTIndex] = function() error("sem_to_back_index_addr_from_base_type: cannot index a non-pointer scalar base") end,
        [Sem.SemTVoid] = function() error("sem_to_back_index_addr_from_base_type: cannot index void") end,
        [Sem.SemTFunc] = function() error("sem_to_back_index_addr_from_base_type: cannot index a function value") end,
    })

    lower_addr_of_expr = pvm.phase("sem_to_back_addr_of_expr", {
        [Sem.SemExprBinding] = function(self, path)
            return pvm.once(one_binding_addr(self.binding, path))
        end,
        [Sem.SemExprDeref] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(one_expr(self.value, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprIndexAddr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(one_index_base_addr(self.base, self.index, self.elem_size, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprIndex] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(one_index_addr_from_base_type(one_sem_expr_type(self.base), self.base, self.index, self.ty, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprFieldAddr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(one_field_addr_from_ref(self.field, self.base, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprConstInt] = function()
            error("sem_to_back_addr_of_expr: cannot take address of an integer literal")
        end,
        [Sem.SemExprConstFloat] = function()
            error("sem_to_back_addr_of_expr: cannot take address of a float literal")
        end,
        [Sem.SemExprConstBool] = function()
            error("sem_to_back_addr_of_expr: cannot take address of a bool literal")
        end,
        [Sem.SemExprNil] = function()
            error("sem_to_back_addr_of_expr: cannot take address of nil")
        end,
        [Sem.SemExprNeg] = function()
            error("sem_to_back_addr_of_expr: cannot take address of a computed negation result")
        end,
        [Sem.SemExprNot] = function()
            error("sem_to_back_addr_of_expr: cannot take address of a computed logical-not result")
        end,
        [Sem.SemExprBNot] = function()
            error("sem_to_back_addr_of_expr: cannot take address of a computed bit-not result")
        end,
        [Sem.SemExprRef] = function()
            error("sem_to_back_addr_of_expr: cannot take address of a reference expression result directly")
        end,
        [Sem.SemExprAdd] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed add result") end,
        [Sem.SemExprSub] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed sub result") end,
        [Sem.SemExprMul] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed mul result") end,
        [Sem.SemExprDiv] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed div result") end,
        [Sem.SemExprRem] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed rem result") end,
        [Sem.SemExprEq] = function() error("sem_to_back_addr_of_expr: cannot take address of a comparison result") end,
        [Sem.SemExprNe] = function() error("sem_to_back_addr_of_expr: cannot take address of a comparison result") end,
        [Sem.SemExprLt] = function() error("sem_to_back_addr_of_expr: cannot take address of a comparison result") end,
        [Sem.SemExprLe] = function() error("sem_to_back_addr_of_expr: cannot take address of a comparison result") end,
        [Sem.SemExprGt] = function() error("sem_to_back_addr_of_expr: cannot take address of a comparison result") end,
        [Sem.SemExprGe] = function() error("sem_to_back_addr_of_expr: cannot take address of a comparison result") end,
        [Sem.SemExprAnd] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed and result") end,
        [Sem.SemExprOr] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed or result") end,
        [Sem.SemExprBitAnd] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed bitand result") end,
        [Sem.SemExprBitOr] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed bitor result") end,
        [Sem.SemExprBitXor] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed bitxor result") end,
        [Sem.SemExprShl] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed shl result") end,
        [Sem.SemExprLShr] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed lshr result") end,
        [Sem.SemExprAShr] = function() error("sem_to_back_addr_of_expr: cannot take address of a computed ashr result") end,
        [Sem.SemExprCastTo] = function() error("sem_to_back_addr_of_expr: cannot take address of a cast result") end,
        [Sem.SemExprTruncTo] = function() error("sem_to_back_addr_of_expr: cannot take address of a cast result") end,
        [Sem.SemExprZExtTo] = function() error("sem_to_back_addr_of_expr: cannot take address of a cast result") end,
        [Sem.SemExprSExtTo] = function() error("sem_to_back_addr_of_expr: cannot take address of a cast result") end,
        [Sem.SemExprBitcastTo] = function() error("sem_to_back_addr_of_expr: cannot take address of a cast result") end,
        [Sem.SemExprSatCastTo] = function() error("sem_to_back_addr_of_expr: cannot take address of a cast result") end,
        [Sem.SemExprSelect] = function() error("sem_to_back_addr_of_expr: cannot take address of a select result") end,
        [Sem.SemExprField] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(one_field_addr_from_ref(self.field, self.base, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprLoad] = function() error("sem_to_back_addr_of_expr: cannot take address of a loaded value result") end,
        [Sem.SemExprIntrinsicCall] = function() error("sem_to_back_addr_of_expr: cannot take address of an intrinsic call result") end,
        [Sem.SemExprCall] = function() error("sem_to_back_addr_of_expr: cannot take address of a call result") end,
        [Sem.SemExprAgg] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(materialize_expr_temp(self, self.ty, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprArrayLit] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(materialize_expr_temp(self, one_sem_expr_type(self), path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprBlock] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(materialize_expr_temp(self, self.ty, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprIf] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(materialize_expr_temp(self, self.ty, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprSwitch] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(materialize_expr_temp(self, self.ty, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprLoop] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(materialize_expr_temp(self, self.ty, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
    })

    lower_const_agg_init_from_type = pvm.phase("sem_to_back_const_agg_init_from_type", {
        [Sem.SemTNamed] = function(self, expr, data_id, offset, layout_env)
            local layout = require_named_layout(layout_env, self.module_name, self.type_name)
            local cmds = {
                Back.BackCmdDataInitZero(data_id, offset, layout.size),
            }
            for i = 1, #expr.fields do
                local field_init = expr.fields[i]
                local field = find_layout_field(layout, field_init.name)
                if field == nil then
                    error("sem_to_back_const_data_init: unknown field '" .. field_init.name .. "' in aggregate constant for '" .. const_data_key(self.module_name, self.type_name) .. "'")
                end
                copy_cmds(one_const_data_init(field_init.value, data_id, offset + field.offset, layout_env), cmds)
            end
            return pvm.once(cmds)
        end,
        [Sem.SemTArray] = function()
            error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type, not SemTArray")
        end,
        [Sem.SemTVoid] = function() error("sem_to_back_const_data_init: cannot build a void constant object") end,
        [Sem.SemTBool] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTI8] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTI16] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTI32] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTI64] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTU8] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTU16] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTU32] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTU64] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTF32] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTF64] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTPtr] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTIndex] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTPtrTo] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTSlice] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
        [Sem.SemTFunc] = function() error("sem_to_back_const_data_init: aggregate initializer requires a named aggregate type") end,
    })

    lower_const_data_init = pvm.phase("sem_to_back_const_data_init", {
        [Sem.SemExprConstInt] = function(self, data_id, offset)
            return pvm.once({ Back.BackCmdDataInitInt(data_id, offset, one_scalar(self.ty), self.raw) })
        end,
        [Sem.SemExprConstFloat] = function(self, data_id, offset)
            return pvm.once({ Back.BackCmdDataInitFloat(data_id, offset, one_scalar(self.ty), self.raw) })
        end,
        [Sem.SemExprConstBool] = function(self, data_id, offset)
            return pvm.once({ Back.BackCmdDataInitBool(data_id, offset, self.value) })
        end,
        [Sem.SemExprNil] = function(self, data_id, offset, layout_env)
            return pvm.once({ Back.BackCmdDataInitZero(data_id, offset, one_type_mem_size(self.ty, layout_env)) })
        end,
        [Sem.SemExprAgg] = function(self, data_id, offset, layout_env)
            return pvm.once(pvm.one(lower_const_agg_init_from_type(self.ty, self, data_id, offset, layout_env)))
        end,
        [Sem.SemExprArrayLit] = function(self, data_id, offset, layout_env)
            local elem_size = one_type_mem_size(self.elem_ty, layout_env)
            local cmds = {}
            for i = 1, #self.elems do
                copy_cmds(one_const_data_init(self.elems[i], data_id, offset + ((i - 1) * elem_size), layout_env), cmds)
            end
            return pvm.once(cmds)
        end,
        [Sem.SemExprBinding] = function()
            error("sem_to_back_const_data_init: constant data cannot capture runtime bindings")
        end,
        [Sem.SemExprNeg] = function() error("sem_to_back_const_data_init: computed negation constants are not yet supported") end,
        [Sem.SemExprNot] = function() error("sem_to_back_const_data_init: computed logical-not constants are not yet supported") end,
        [Sem.SemExprBNot] = function() error("sem_to_back_const_data_init: computed bit-not constants are not yet supported") end,
        [Sem.SemExprRef] = function() error("sem_to_back_const_data_init: ref constants are not yet supported") end,
        [Sem.SemExprDeref] = function() error("sem_to_back_const_data_init: deref constants are not yet supported") end,
        [Sem.SemExprAdd] = function() error("sem_to_back_const_data_init: computed add constants are not yet supported") end,
        [Sem.SemExprSub] = function() error("sem_to_back_const_data_init: computed sub constants are not yet supported") end,
        [Sem.SemExprMul] = function() error("sem_to_back_const_data_init: computed mul constants are not yet supported") end,
        [Sem.SemExprDiv] = function() error("sem_to_back_const_data_init: computed div constants are not yet supported") end,
        [Sem.SemExprRem] = function() error("sem_to_back_const_data_init: computed rem constants are not yet supported") end,
        [Sem.SemExprEq] = function() error("sem_to_back_const_data_init: comparison constants are not yet supported") end,
        [Sem.SemExprNe] = function() error("sem_to_back_const_data_init: comparison constants are not yet supported") end,
        [Sem.SemExprLt] = function() error("sem_to_back_const_data_init: comparison constants are not yet supported") end,
        [Sem.SemExprLe] = function() error("sem_to_back_const_data_init: comparison constants are not yet supported") end,
        [Sem.SemExprGt] = function() error("sem_to_back_const_data_init: comparison constants are not yet supported") end,
        [Sem.SemExprGe] = function() error("sem_to_back_const_data_init: comparison constants are not yet supported") end,
        [Sem.SemExprAnd] = function() error("sem_to_back_const_data_init: computed and constants are not yet supported") end,
        [Sem.SemExprOr] = function() error("sem_to_back_const_data_init: computed or constants are not yet supported") end,
        [Sem.SemExprBitAnd] = function() error("sem_to_back_const_data_init: computed bitand constants are not yet supported") end,
        [Sem.SemExprBitOr] = function() error("sem_to_back_const_data_init: computed bitor constants are not yet supported") end,
        [Sem.SemExprBitXor] = function() error("sem_to_back_const_data_init: computed bitxor constants are not yet supported") end,
        [Sem.SemExprShl] = function() error("sem_to_back_const_data_init: computed shl constants are not yet supported") end,
        [Sem.SemExprLShr] = function() error("sem_to_back_const_data_init: computed lshr constants are not yet supported") end,
        [Sem.SemExprAShr] = function() error("sem_to_back_const_data_init: computed ashr constants are not yet supported") end,
        [Sem.SemExprCastTo] = function() error("sem_to_back_const_data_init: cast constants are not yet supported") end,
        [Sem.SemExprTruncTo] = function() error("sem_to_back_const_data_init: cast constants are not yet supported") end,
        [Sem.SemExprZExtTo] = function() error("sem_to_back_const_data_init: cast constants are not yet supported") end,
        [Sem.SemExprSExtTo] = function() error("sem_to_back_const_data_init: cast constants are not yet supported") end,
        [Sem.SemExprBitcastTo] = function() error("sem_to_back_const_data_init: bitcast constants are not yet supported") end,
        [Sem.SemExprSatCastTo] = function() error("sem_to_back_const_data_init: saturating cast constants are not yet supported") end,
        [Sem.SemExprSelect] = function() error("sem_to_back_const_data_init: select constants are not yet supported") end,
        [Sem.SemExprIndex] = function() error("sem_to_back_const_data_init: indexed constants are not yet supported") end,
        [Sem.SemExprField] = function() error("sem_to_back_const_data_init: field-projected constants are not yet supported") end,
        [Sem.SemExprIndexAddr] = function() error("sem_to_back_const_data_init: address constants are not yet supported") end,
        [Sem.SemExprFieldAddr] = function() error("sem_to_back_const_data_init: address constants are not yet supported") end,
        [Sem.SemExprLoad] = function() error("sem_to_back_const_data_init: load constants are not yet supported") end,
        [Sem.SemExprIntrinsicCall] = function() error("sem_to_back_const_data_init: intrinsic-call constants are not yet supported") end,
        [Sem.SemExprCall] = function() error("sem_to_back_const_data_init: call constants are not yet supported") end,
        [Sem.SemExprBlock] = function() error("sem_to_back_const_data_init: block constants are not yet supported") end,
        [Sem.SemExprIf] = function() error("sem_to_back_const_data_init: branch constants are not yet supported") end,
        [Sem.SemExprSwitch] = function() error("sem_to_back_const_data_init: switch constants are not yet supported") end,
        [Sem.SemExprLoop] = function() error("sem_to_back_const_data_init: loop constants are not yet supported") end,
    })

    local function addr_with_offset(base_addr, offset, path)
        local dst = Back.BackValId(path)
        if offset == 0 then
            return { Back.BackCmdAlias(dst, base_addr) }, dst
        end
        local off = Back.BackValId(path .. ".offset")
        return {
            Back.BackCmdConstInt(off, Back.BackIndex, tostring(offset)),
            one_add_cmd(Sem.SemTPtr, dst, Back.BackPtr, base_addr, off),
        }, dst
    end

    lower_agg_expr_into_addr_from_type = pvm.phase("sem_to_back_agg_expr_into_addr_from_type", {
        [Sem.SemTNamed] = function(self, expr, addr, path, layout_env)
            local layout = require_named_layout(layout_env, self.module_name, self.type_name)
            local cmds = {}
            for i = 1, #layout.fields do
                local field = layout.fields[i]
                local init = find_field_init(expr.fields, field.field_name)
                if init == nil then
                    error("sem_to_back_expr_into_addr: aggregate expr is missing field '" .. field.field_name .. "'")
                end
                local field_cmds, field_addr = addr_with_offset(addr, field.offset, path .. ".field." .. field.field_name)
                copy_cmds(field_cmds, cmds)
                local init_plan = one_expr_into_addr(init.value, field_addr, path .. ".field_init." .. field.field_name, layout_env)
                append_addr_cmds(cmds, init_plan)
                if addr_terminates(init_plan) then
                    return pvm.once(terminated_addr(cmds))
                end
            end
            return pvm.once(addr_writes(cmds))
        end,
        [Sem.SemTVoid] = function() error("sem_to_back_expr_into_addr: aggregate expr cannot materialize void") end,
        [Sem.SemTBool] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTI8] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTI16] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTI32] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTI64] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTU8] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTU16] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTU32] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTU64] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTF32] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTF64] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTPtr] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTIndex] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTPtrTo] = function() error("sem_to_back_expr_into_addr: aggregate expr requires an aggregate destination type") end,
        [Sem.SemTArray] = function() error("sem_to_back_expr_into_addr: aggregate expr currently requires a named aggregate type") end,
        [Sem.SemTSlice] = function() error("sem_to_back_expr_into_addr: aggregate expr currently requires a named aggregate type") end,
        [Sem.SemTFunc] = function() error("sem_to_back_expr_into_addr: aggregate expr currently requires a named aggregate type") end,
    })

    lower_copy_type_addr = pvm.phase("sem_to_back_copy_type_addr", {
        [Sem.SemTBool] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({
                Back.BackCmdLoad(value, one_scalar(self), src_addr),
                Back.BackCmdStore(one_scalar(self), dst_addr, value),
            })
        end,
        [Sem.SemTI8] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTI16] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTI32] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTI64] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTU8] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTU16] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTU32] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTU64] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTF32] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTF64] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTPtr] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTIndex] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTPtrTo] = function(self, src_addr, dst_addr, path)
            local value = Back.BackValId(path .. ".value")
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
        end,
        [Sem.SemTArray] = function(self, src_addr, dst_addr, path, layout_env)
            local cmds = {}
            local elem_size = one_type_mem_size(self.elem, layout_env)
            for i = 1, self.count do
                local src_cmds, src_elem = addr_with_offset(src_addr, (i - 1) * elem_size, path .. ".src." .. i)
                local dst_cmds, dst_elem = addr_with_offset(dst_addr, (i - 1) * elem_size, path .. ".dst." .. i)
                copy_cmds(src_cmds, cmds)
                copy_cmds(dst_cmds, cmds)
                copy_cmds(one_copy_type_addr(self.elem, src_elem, dst_elem, path .. ".elem." .. i, layout_env), cmds)
            end
            return pvm.once(cmds)
        end,
        [Sem.SemTNamed] = function(self, src_addr, dst_addr, path, layout_env)
            local layout = require_named_layout(layout_env, self.module_name, self.type_name)
            local cmds = {}
            for i = 1, #layout.fields do
                local field = layout.fields[i]
                local src_cmds, src_field = addr_with_offset(src_addr, field.offset, path .. ".src." .. field.field_name)
                local dst_cmds, dst_field = addr_with_offset(dst_addr, field.offset, path .. ".dst." .. field.field_name)
                copy_cmds(src_cmds, cmds)
                copy_cmds(dst_cmds, cmds)
                copy_cmds(one_copy_type_addr(field.ty, src_field, dst_field, path .. ".field." .. field.field_name, layout_env), cmds)
            end
            return pvm.once(cmds)
        end,
        [Sem.SemTSlice] = function()
            error("sem_to_back_copy_type_addr: slice runtime copying is not yet supported")
        end,
        [Sem.SemTVoid] = function()
            error("sem_to_back_copy_type_addr: cannot copy void")
        end,
        [Sem.SemTFunc] = function()
            error("sem_to_back_copy_type_addr: function values are not storable in Sem->Back")
        end,
    })

    local function build_switch_expr_value(self, path, layout_env, break_block, break_args, continue_block, continue_args)
        if not one_type_is_scalar(self.ty) then
            error("sem_to_back_expr: non-scalar switch expr results have no direct value form in Sem->Back; use an address/materialization context")
        end
        local value_ty = one_sem_expr_type(self.value)
        if not one_type_is_scalar(value_ty) then
            error("sem_to_back_expr: switch value must currently be scalar in Sem->Back")
        end
        local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args)
        local default_expr = one_expr(self.default_expr, path .. ".default", layout_env, break_block, break_args, continue_block, continue_args)
        local cmds = {}
        append_expr_cmds(cmds, value)
        if expr_terminates(value) then
            return terminated_expr(cmds)
        end
        if #self.arms == 0 then
            append_expr_cmds(cmds, default_expr)
            if expr_terminates(default_expr) then
                return terminated_expr(cmds)
            end
            return Back.BackExprPlan(cmds, default_expr.value, one_scalar(self.ty))
        end
        local arm_body_cmds = {}
        local arm_result_plans = {}
        local need_join = expr_has_value(default_expr)
        for i = 1, #self.arms do
            local body_cmds, body_flow = lower_stmt_list(self.arms[i].body, path .. ".arm." .. i, layout_env, break_block, break_args, continue_block, continue_args)
            arm_body_cmds[i] = body_cmds
            if body_flow == Back.BackFallsThrough then
                arm_result_plans[i] = one_expr(self.arms[i].result, path .. ".arm." .. i .. ".result", layout_env, break_block, break_args, continue_block, continue_args)
            else
                arm_result_plans[i] = terminated_expr({})
            end
            if expr_has_value(arm_result_plans[i]) then
                need_join = true
            end
        end
        local dst = Back.BackValId(path)
        local ty = one_scalar(self.ty)
        local join_block = Back.BackBlockId(path .. ".join.block")
        local default_block = Back.BackBlockId(path .. ".default.block")
        local arm_blocks = {}
        local test_blocks = {}
        for i = 1, #self.arms do
            arm_blocks[i] = Back.BackBlockId(path .. ".arm." .. i .. ".block")
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(arm_blocks[i])
            if i > 1 then
                test_blocks[i] = Back.BackBlockId(path .. ".test." .. i .. ".block")
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(test_blocks[i])
            end
        end
        cmds[#cmds + 1] = Back.BackCmdCreateBlock(default_block)
        if need_join then
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(join_block, dst, ty)
        end
        for i = 1, #self.arms do
            if i > 1 then
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(test_blocks[i])
            end
            local key = one_expr(self.arms[i].key, path .. ".arm." .. i .. ".key", layout_env, break_block, break_args, continue_block, continue_args)
            append_expr_cmds(cmds, key)
            local else_block = (i < #self.arms) and test_blocks[i + 1] or default_block
            if expr_has_value(key) then
                local match = Back.BackValId(path .. ".arm." .. i .. ".match")
                cmds[#cmds + 1] = one_eq_cmd(value_ty, match, Back.BackBool, value.value, key.value)
                cmds[#cmds + 1] = Back.BackCmdBrIf(match, arm_blocks[i], {}, else_block, {})
                cmds[#cmds + 1] = Back.BackCmdSealBlock(arm_blocks[i])
                cmds[#cmds + 1] = Back.BackCmdSealBlock(else_block)
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(arm_blocks[i])
            copy_cmds(arm_body_cmds[i], cmds)
            append_expr_cmds(cmds, arm_result_plans[i])
            if expr_has_value(arm_result_plans[i]) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, { arm_result_plans[i].value })
            end
        end
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(default_block)
        append_expr_cmds(cmds, default_expr)
        if expr_has_value(default_expr) then
            cmds[#cmds + 1] = Back.BackCmdJump(join_block, { default_expr.value })
        end
        if need_join then
            cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
            return Back.BackExprPlan(cmds, dst, ty)
        end
        return terminated_expr(cmds)
    end

    local function scalar_value_into_addr(value, addr, store_ty)
        local cmds = {}
        append_expr_cmds(cmds, value)
        if expr_terminates(value) then
            return terminated_addr(cmds)
        end
        cmds[#cmds + 1] = Back.BackCmdStore(store_ty, addr, value.value)
        return addr_writes(cmds)
    end

    local function copy_value_into_addr(expr_ty, src, addr, path, layout_env)
        local cmds = {}
        append_expr_cmds(cmds, src)
        if expr_terminates(src) then
            return terminated_addr(cmds)
        end
        copy_cmds(one_copy_type_addr(expr_ty, src.value, addr, path .. ".copy", layout_env), cmds)
        return addr_writes(cmds)
    end

    local function lower_scalar_expr_into_addr(expr, addr, path, layout_env, break_block, break_args, continue_block, continue_args, store_ty)
        return scalar_value_into_addr(
            one_expr(expr, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args),
            addr,
            store_ty
        )
    end

    local function lower_expr_copy_into_addr(expr, expr_ty, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
        if one_type_is_scalar(expr_ty) then
            return lower_scalar_expr_into_addr(expr, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(expr_ty))
        end
        return copy_value_into_addr(
            expr_ty,
            one_addr_of_expr(expr, path .. ".src", layout_env, break_block, break_args, continue_block, continue_args),
            addr,
            path,
            layout_env
        )
    end

    local function build_switch_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
        local value_ty = one_sem_expr_type(self.value)
        if not one_type_is_scalar(value_ty) then
            error("sem_to_back_expr_into_addr: switch value must currently be scalar in Sem->Back")
        end
        local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args)
        local cmds = {}
        append_expr_cmds(cmds, value)
        if expr_terminates(value) then
            return terminated_addr(cmds)
        end
        if #self.arms == 0 then
            local default_plan = one_expr_into_addr(self.default_expr, addr, path .. ".default", layout_env, break_block, break_args, continue_block, continue_args)
            append_addr_cmds(cmds, default_plan)
            if addr_terminates(default_plan) then
                return terminated_addr(cmds)
            end
            return addr_writes(cmds)
        end
        local arm_body_cmds = {}
        local arm_result_plans = {}
        local default_plan = one_expr_into_addr(self.default_expr, addr, path .. ".default", layout_env, break_block, break_args, continue_block, continue_args)
        local need_join = addr_continues(default_plan)
        for i = 1, #self.arms do
            local body_cmds, body_flow = lower_stmt_list(self.arms[i].body, path .. ".arm." .. i, layout_env, break_block, break_args, continue_block, continue_args)
            arm_body_cmds[i] = body_cmds
            if body_flow == Back.BackFallsThrough then
                arm_result_plans[i] = one_expr_into_addr(self.arms[i].result, addr, path .. ".arm." .. i .. ".result", layout_env, break_block, break_args, continue_block, continue_args)
            else
                arm_result_plans[i] = terminated_addr({})
            end
            if addr_continues(arm_result_plans[i]) then
                need_join = true
            end
        end
        local join_block = Back.BackBlockId(path .. ".join.block")
        local default_block = Back.BackBlockId(path .. ".default.block")
        local arm_blocks = {}
        local test_blocks = {}
        for i = 1, #self.arms do
            arm_blocks[i] = Back.BackBlockId(path .. ".arm." .. i .. ".block")
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(arm_blocks[i])
            if i > 1 then
                test_blocks[i] = Back.BackBlockId(path .. ".test." .. i .. ".block")
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(test_blocks[i])
            end
        end
        cmds[#cmds + 1] = Back.BackCmdCreateBlock(default_block)
        if need_join then
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
        end
        for i = 1, #self.arms do
            if i > 1 then
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(test_blocks[i])
            end
            local key = one_expr(self.arms[i].key, path .. ".arm." .. i .. ".key", layout_env, break_block, break_args, continue_block, continue_args)
            append_expr_cmds(cmds, key)
            local else_block = (i < #self.arms) and test_blocks[i + 1] or default_block
            if expr_has_value(key) then
                local match = Back.BackValId(path .. ".arm." .. i .. ".match")
                cmds[#cmds + 1] = one_eq_cmd(value_ty, match, Back.BackBool, value.value, key.value)
                cmds[#cmds + 1] = Back.BackCmdBrIf(match, arm_blocks[i], {}, else_block, {})
                cmds[#cmds + 1] = Back.BackCmdSealBlock(arm_blocks[i])
                cmds[#cmds + 1] = Back.BackCmdSealBlock(else_block)
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(arm_blocks[i])
            copy_cmds(arm_body_cmds[i], cmds)
            append_addr_cmds(cmds, arm_result_plans[i])
            if addr_continues(arm_result_plans[i]) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
        end
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(default_block)
        append_addr_cmds(cmds, default_plan)
        if addr_continues(default_plan) then
            cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
        end
        if need_join then
            cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
            return addr_writes(cmds)
        end
        return terminated_addr(cmds)
    end

    lower_expr_into_addr = pvm.phase("sem_to_back_expr_into_addr", {
        [Sem.SemExprAgg] = function(self, addr, path, layout_env)
            return pvm.once(pvm.one(lower_agg_expr_into_addr_from_type(self.ty, self, addr, path, layout_env)))
        end,
        [Sem.SemExprArrayLit] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            local cmds = {}
            local elem_size = one_type_mem_size(self.elem_ty, layout_env)
            for i = 1, #self.elems do
                local elem_cmds, elem_addr = addr_with_offset(addr, (i - 1) * elem_size, path .. ".elem." .. i)
                copy_cmds(elem_cmds, cmds)
                local elem_plan = one_expr_into_addr(self.elems[i], elem_addr, path .. ".elem_init." .. i, layout_env, break_block, break_args, continue_block, continue_args)
                append_addr_cmds(cmds, elem_plan)
                if addr_terminates(elem_plan) then
                    return pvm.once(terminated_addr(cmds))
                end
            end
            return pvm.once(addr_writes(cmds))
        end,
        [Sem.SemExprBinding] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_expr_copy_into_addr(self, one_sem_expr_type(self), addr, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprField] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_expr_copy_into_addr(self, one_sem_expr_type(self), addr, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprIndex] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_expr_copy_into_addr(self, one_sem_expr_type(self), addr, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprConstInt] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprConstFloat] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprConstBool] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprNil] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprRef] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprDeref] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_expr_copy_into_addr(self, one_sem_expr_type(self), addr, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprAdd] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprSub] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprMul] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprDiv] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprRem] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprEq] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprNe] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprLt] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprLe] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprGt] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprGe] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprAnd] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprOr] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprBitAnd] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprBitOr] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprBitXor] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprShl] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprLShr] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprAShr] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprCastTo] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprTruncTo] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprZExtTo] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprSExtTo] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprBitcastTo] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprSatCastTo] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprSelect] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprIndexAddr] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackPtr))
        end,
        [Sem.SemExprFieldAddr] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackPtr))
        end,
        [Sem.SemExprLoad] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr_ty = one_sem_expr_type(self)
            if not one_type_is_scalar(expr_ty) then
                error("sem_to_back_expr_into_addr: non-scalar load results are not yet supported")
            end
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(expr_ty)))
        end,
        [Sem.SemExprIntrinsicCall] = function()
            error("sem_to_back_expr_into_addr: intrinsic calls are not yet supported")
        end,
        [Sem.SemExprCall] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr_into_addr: non-scalar call results are not yet supported")
            end
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprBlock] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            local body_cmds, body_flow = lower_stmt_list(self.stmts, path .. ".stmts", layout_env, break_block, break_args, continue_block, continue_args)
            local cmds = {}
            copy_cmds(body_cmds, cmds)
            if body_flow ~= Back.BackFallsThrough then
                return pvm.once(terminated_addr(cmds))
            end
            local result = one_expr_into_addr(self.result, addr, path .. ".result", layout_env, break_block, break_args, continue_block, continue_args)
            append_addr_cmds(cmds, result)
            if addr_terminates(result) then
                return pvm.once(terminated_addr(cmds))
            end
            return pvm.once(addr_writes(cmds))
        end,
        [Sem.SemExprIf] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            local cond = one_expr(self.cond, path .. ".cond", layout_env, break_block, break_args, continue_block, continue_args)
            local then_block = Back.BackBlockId(path .. ".then.block")
            local else_block = Back.BackBlockId(path .. ".else.block")
            local join_block = Back.BackBlockId(path .. ".join.block")
            local then_plan = one_expr_into_addr(self.then_expr, addr, path .. ".then", layout_env, break_block, break_args, continue_block, continue_args)
            local else_plan = one_expr_into_addr(self.else_expr, addr, path .. ".else", layout_env, break_block, break_args, continue_block, continue_args)
            local need_join = addr_continues(then_plan) or addr_continues(else_plan)
            local cmds = {}
            append_expr_cmds(cmds, cond)
            if expr_terminates(cond) then
                return pvm.once(terminated_addr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(then_block)
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(else_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
            end
            cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, then_block, {}, else_block, {})
            cmds[#cmds + 1] = Back.BackCmdSealBlock(then_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(else_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(then_block)
            append_addr_cmds(cmds, then_plan)
            if addr_continues(then_plan) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(else_block)
            append_addr_cmds(cmds, else_plan)
            if addr_continues(else_plan) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                return pvm.once(addr_writes(cmds))
            end
            return pvm.once(terminated_addr(cmds))
        end,
        [Sem.SemExprSwitch] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(build_switch_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprLoop] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            if one_type_is_scalar(self.ty) then
                return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
            end
            return pvm.once(one_loop_expr_into_addr(self.loop, addr, path .. ".loop", layout_env))
        end,
    })

    lower_call_value = pvm.phase("sem_to_back_call_value", {
        [Sem.SemCallDirect] = function(self, dst, ret_ty, path, args)
            local func_text = func_id_text(self.module_name, self.func_name)
            local sig = one_sig_spec(self.fn_ty)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdCreateSig(Back.BackSigId("sig:" .. func_text), sig.params, sig.results),
                Back.BackCmdDeclareFuncLocal(Back.BackFuncId(func_text), Back.BackSigId("sig:" .. func_text)),
                Back.BackCmdCallValueDirect(dst, ret_ty, Back.BackFuncId(func_text), Back.BackSigId("sig:" .. func_text), args),
            }, dst, ret_ty))
        end,
        [Sem.SemCallExtern] = function(self, dst, ret_ty, path, args)
            local sig = one_sig_spec(self.fn_ty)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdCreateSig(Back.BackSigId("sig:extern:" .. self.symbol), sig.params, sig.results),
                Back.BackCmdDeclareFuncExtern(Back.BackExternId(self.symbol), self.symbol, Back.BackSigId("sig:extern:" .. self.symbol)),
                Back.BackCmdCallValueExtern(dst, ret_ty, Back.BackExternId(self.symbol), Back.BackSigId("sig:extern:" .. self.symbol), args),
            }, dst, ret_ty))
        end,
        [Sem.SemCallIndirect] = function(self, dst, ret_ty, path, args, layout_env, break_block, break_args, continue_block, continue_args)
            local callee = one_expr(self.callee, path .. ".callee", layout_env, break_block, break_args, continue_block, continue_args)
            local sig = one_sig_spec(self.fn_ty)
            local cmds = {}
            append_expr_cmds(cmds, callee)
            if expr_terminates(callee) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdCreateSig(Back.BackSigId(path .. ":sig"), sig.params, sig.results)
            cmds[#cmds + 1] = Back.BackCmdCallValueIndirect(dst, ret_ty, callee.value, Back.BackSigId(path .. ":sig"), args)
            return pvm.once(Back.BackExprPlan(cmds, dst, ret_ty))
        end,
    })

    local function unary_expr_plan(value, dst, ty, emit_cmd)
        local cmds = {}
        append_expr_cmds(cmds, value)
        if expr_terminates(value) then
            return terminated_expr(cmds)
        end
        cmds[#cmds + 1] = emit_cmd(value.value)
        return Back.BackExprPlan(cmds, dst, ty)
    end

    local function binary_expr_plan(lhs, rhs, dst, ty, emit_cmd)
        local cmds = {}
        append_expr_cmds(cmds, lhs)
        if expr_terminates(lhs) then
            return terminated_expr(cmds)
        end
        append_expr_cmds(cmds, rhs)
        if expr_terminates(rhs) then
            return terminated_expr(cmds)
        end
        cmds[#cmds + 1] = emit_cmd(lhs.value, rhs.value)
        return Back.BackExprPlan(cmds, dst, ty)
    end

    lower_expr = pvm.phase("sem_to_back_expr", {
        [Sem.SemExprConstInt] = function(self, path)
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            return pvm.once(Back.BackExprPlan({ Back.BackCmdConstInt(dst, ty, self.raw) }, dst, ty))
        end,
        [Sem.SemExprConstFloat] = function(self, path)
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            return pvm.once(Back.BackExprPlan({ Back.BackCmdConstFloat(dst, ty, self.raw) }, dst, ty))
        end,
        [Sem.SemExprConstBool] = function(self, path)
            local dst = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({ Back.BackCmdConstBool(dst, self.value) }, dst, Back.BackBool))
        end,
        [Sem.SemExprNil] = function(self, path)
            local dst = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({ Back.BackCmdConstNull(dst) }, dst, one_scalar(self.ty)))
        end,
        [Sem.SemExprBinding] = function(self, path)
            return pvm.once(one_binding_expr(self.binding, path))
        end,
        [Sem.SemExprRef] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(one_addr_of_expr(self.value, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprDeref] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local addr = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            local cmds = {}
            append_expr_cmds(cmds, addr)
            if expr_terminates(addr) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdLoad(dst, ty, addr.value)
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemExprNeg] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(unary_expr_plan(value, dst, ty, function(v)
                return one_neg_cmd(self.ty, dst, ty, v)
            end))
        end,
        [Sem.SemExprNot] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(unary_expr_plan(value, dst, Back.BackBool, function(v)
                return one_not_cmd(self.ty, dst, v)
            end))
        end,
        [Sem.SemExprBNot] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(unary_expr_plan(value, dst, ty, function(v)
                return one_bnot_cmd(self.ty, dst, ty, v)
            end))
        end,
        [Sem.SemExprAdd] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_add_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprSub] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_sub_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprMul] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_mul_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprDiv] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_div_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprRem] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_rem_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprEq] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local lhs_ty = one_sem_expr_type(self.lhs)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, Back.BackBool, function(l, r)
                return one_eq_cmd(lhs_ty, dst, Back.BackBool, l, r)
            end))
        end,
        [Sem.SemExprNe] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local lhs_ty = one_sem_expr_type(self.lhs)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, Back.BackBool, function(l, r)
                return one_ne_cmd(lhs_ty, dst, Back.BackBool, l, r)
            end))
        end,
        [Sem.SemExprLt] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local lhs_ty = one_sem_expr_type(self.lhs)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, Back.BackBool, function(l, r)
                return one_lt_cmd(lhs_ty, dst, Back.BackBool, l, r)
            end))
        end,
        [Sem.SemExprLe] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local lhs_ty = one_sem_expr_type(self.lhs)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, Back.BackBool, function(l, r)
                return one_le_cmd(lhs_ty, dst, Back.BackBool, l, r)
            end))
        end,
        [Sem.SemExprGt] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local lhs_ty = one_sem_expr_type(self.lhs)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, Back.BackBool, function(l, r)
                return one_gt_cmd(lhs_ty, dst, Back.BackBool, l, r)
            end))
        end,
        [Sem.SemExprGe] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local lhs_ty = one_sem_expr_type(self.lhs)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, Back.BackBool, function(l, r)
                return one_ge_cmd(lhs_ty, dst, Back.BackBool, l, r)
            end))
        end,
        [Sem.SemExprAnd] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_and_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprOr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_or_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprBitAnd] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_band_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprBitOr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_bor_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprBitXor] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_bxor_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprShl] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_shl_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprLShr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_lshr_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprAShr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_ashr_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprSelect] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local dst = Back.BackValId(path)
            local cond = one_expr(self.cond, path .. ".cond", layout_env, break_block, break_args, continue_block, continue_args)
            local then_value = one_expr(self.then_value, path .. ".then", layout_env, break_block, break_args, continue_block, continue_args)
            local else_value = one_expr(self.else_value, path .. ".else", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            local cmds = {}
            append_expr_cmds(cmds, cond)
            if expr_terminates(cond) then
                return pvm.once(terminated_expr(cmds))
            end
            append_expr_cmds(cmds, then_value)
            if expr_terminates(then_value) then
                return pvm.once(terminated_expr(cmds))
            end
            append_expr_cmds(cmds, else_value)
            if expr_terminates(else_value) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdSelect(dst, ty, cond.value, then_value.value, else_value.value)
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemExprIndexAddr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(one_index_base_addr(self.base, self.index, self.elem_size, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprIndex] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr: non-scalar index results have no direct value form in Sem->Back; use address-based access")
            end
            local dst = Back.BackValId(path)
            local addr = one_addr_of_expr(self, path .. ".addr", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            local cmds = {}
            append_expr_cmds(cmds, addr)
            if expr_terminates(addr) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdLoad(dst, ty, addr.value)
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemExprFieldAddr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(one_addr_of_expr(self, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprField] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(one_field_expr_from_ref(self.field, self.base, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemExprLoad] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr: non-scalar load results have no direct value form in Sem->Back; use an address/materialization context")
            end
            local dst = Back.BackValId(path)
            local addr = one_expr(self.addr, path .. ".addr", layout_env, break_block, break_args, continue_block, continue_args)
            local ty = one_scalar(self.ty)
            local cmds = {}
            append_expr_cmds(cmds, addr)
            if expr_terminates(addr) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdLoad(dst, ty, addr.value)
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemExprAgg] = function()
            error("sem_to_back_expr: aggregate exprs have no direct value form in Sem->Back; use an address/materialization context")
        end,
        [Sem.SemExprArrayLit] = function()
            error("sem_to_back_expr: array literal exprs have no direct value form in Sem->Back; use an address/materialization context")
        end,
        [Sem.SemExprCall] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr: non-scalar call results have no direct value form in Sem->Back; use an address/materialization context")
            end
            local dst = Back.BackValId(path)
            local ret_ty = one_scalar(self.ty)
            local cmds = {}
            local args = {}
            for i = 1, #self.args do
                local arg = one_expr(self.args[i], path .. ".arg." .. i, layout_env, break_block, break_args, continue_block, continue_args)
                append_expr_cmds(cmds, arg)
                if expr_terminates(arg) then
                    return pvm.once(terminated_expr(cmds))
                end
                args[i] = arg.value
            end
            local call_plan = one_call_value(self.target, dst, ret_ty, path, args, layout_env, break_block, break_args, continue_block, continue_args)
            append_expr_cmds(cmds, call_plan)
            if expr_terminates(call_plan) then
                return pvm.once(terminated_expr(cmds))
            end
            return pvm.once(Back.BackExprPlan(cmds, dst, ret_ty))
        end,
        [Sem.SemExprLoop] = function(self, path, layout_env)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr: non-scalar loop expr results have no direct value form in Sem->Back; use an address/materialization context")
            end
            return pvm.once(one_loop_expr_plan(self.loop, path, layout_env))
        end,
        [Sem.SemExprIf] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr: non-scalar if expr results have no direct value form in Sem->Back; use an address/materialization context")
            end
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            local cond = one_expr(self.cond, path .. ".cond", layout_env, break_block, break_args, continue_block, continue_args)
            local then_expr = one_expr(self.then_expr, path .. ".then", layout_env, break_block, break_args, continue_block, continue_args)
            local else_expr = one_expr(self.else_expr, path .. ".else", layout_env, break_block, break_args, continue_block, continue_args)
            local then_block = Back.BackBlockId(path .. ".then.block")
            local else_block = Back.BackBlockId(path .. ".else.block")
            local join_block = Back.BackBlockId(path .. ".join.block")
            local need_join = expr_has_value(then_expr) or expr_has_value(else_expr)
            local cmds = {}
            append_expr_cmds(cmds, cond)
            if expr_terminates(cond) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(then_block)
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(else_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(join_block, dst, ty)
            end
            cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, then_block, {}, else_block, {})
            cmds[#cmds + 1] = Back.BackCmdSealBlock(then_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(else_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(then_block)
            append_expr_cmds(cmds, then_expr)
            if expr_has_value(then_expr) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, { then_expr.value })
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(else_block)
            append_expr_cmds(cmds, else_expr)
            if expr_has_value(else_expr) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, { else_expr.value })
            end
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                return pvm.once(Back.BackExprPlan(cmds, dst, ty))
            end
            return pvm.once(terminated_expr(cmds))
        end,
        [Sem.SemExprBlock] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr: non-scalar block expr results have no direct value form in Sem->Back; use an address/materialization context")
            end
            local body_cmds, body_flow = lower_stmt_list(self.stmts, path .. ".stmts", layout_env, break_block, break_args, continue_block, continue_args)
            local cmds = {}
            copy_cmds(body_cmds, cmds)
            if body_flow ~= Back.BackFallsThrough then
                return pvm.once(terminated_expr(cmds))
            end
            local result = one_expr(self.result, path .. ".result", layout_env, break_block, break_args, continue_block, continue_args)
            append_expr_cmds(cmds, result)
            if expr_terminates(result) then
                return pvm.once(terminated_expr(cmds))
            end
            return pvm.once(Back.BackExprPlan(cmds, result.value, one_scalar(self.ty)))
        end,
        [Sem.SemExprSwitch] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(build_switch_expr_value(self, path, layout_env, break_block, break_args, continue_block, continue_args))
        end,
    })

    lower_over_index_value = pvm.phase("sem_to_back_over_index_value", {
        [Sem.SemBindLocalValue] = function(self)
            return pvm.once(local_value_id(self.id))
        end,
        [Sem.SemBindLocalCell] = function(self)
            error("sem_to_back_over_index_value: over-loop index binding must be immutable; got mutable local '" .. self.name .. "'")
        end,
        [Sem.SemBindArg] = function(self)
            error("sem_to_back_over_index_value: over-loop index binding must be a local value, not argument '" .. self.name .. "'")
        end,
        [Sem.SemBindGlobal] = function(self)
            error("sem_to_back_over_index_value: over-loop index binding must be a local value, not global '" .. self.item_name .. "'")
        end,
        [Sem.SemBindExtern] = function(self)
            error("sem_to_back_over_index_value: over-loop index binding must be a local value, not extern '" .. self.symbol .. "'")
        end,
    })

    local function build_over_stmt_plan(loop, path, start_plan, stop_plan, layout_env)
        local index_ty = loop.index_binding.ty
        local index_back_ty = one_scalar(index_ty)
        local header_block = Back.BackBlockId(path .. ".header.block")
        local body_block = Back.BackBlockId(path .. ".body.block")
        local continue_block = Back.BackBlockId(path .. ".continue.block")
        local exit_block = Back.BackBlockId(path .. ".exit.block")
        local header_index = Back.BackValId(path .. ".header.index")
        local body_index = Back.BackValId(path .. ".body.index")
        local continue_index = Back.BackValId(path .. ".continue.index")
        local header_carry_params = {}
        local body_carry_params = {}
        local continue_carry_params = {}
        local header_jump_args = { header_index }
        local current_args = over_loop_current_args(loop.index_binding, loop.carries)
        local cmds = {
            Back.BackCmdCreateBlock(header_block),
            Back.BackCmdCreateBlock(body_block),
            Back.BackCmdCreateBlock(continue_block),
            Back.BackCmdCreateBlock(exit_block),
            Back.BackCmdAppendBlockParam(header_block, header_index, index_back_ty),
            Back.BackCmdAppendBlockParam(body_block, body_index, index_back_ty),
            Back.BackCmdAppendBlockParam(continue_block, continue_index, index_back_ty),
        }
        local init_args = {}
        append_expr_cmds(cmds, start_plan)
        init_args[1] = start_plan.value
        for i = 1, #loop.carries do
            local header_param = Back.BackValId(path .. ".header.carry." .. i)
            local body_param = Back.BackValId(path .. ".body.carry." .. i)
            local continue_param = Back.BackValId(path .. ".continue.carry." .. i)
            header_carry_params[i] = header_param
            body_carry_params[i] = body_param
            continue_carry_params[i] = continue_param
            header_jump_args[#header_jump_args + 1] = header_param
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(loop.carries[i].ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(loop.carries[i].ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(loop.carries[i].ty))
            local init = one_expr(loop.carries[i].init, path .. ".carry_init." .. i, layout_env)
            append_expr_cmds(cmds, init)
            init_args[#init_args + 1] = init.value
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_args)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
        emit_alias_for_index_binding(cmds, loop.index_binding, header_index)
        emit_aliases_for_loop_bindings(cmds, loop.carries, header_carry_params)
        append_expr_cmds(cmds, stop_plan)
        local cond_value = Back.BackValId(path .. ".cond")
        cmds[#cmds + 1] = one_lt_cmd(index_ty, cond_value, Back.BackBool, header_index, stop_plan.value)
        cmds[#cmds + 1] = Back.BackCmdBrIf(cond_value, body_block, header_jump_args, exit_block, {})
        cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
        emit_alias_for_index_binding(cmds, loop.index_binding, body_index)
        emit_aliases_for_loop_bindings(cmds, loop.carries, body_carry_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, exit_block, {}, continue_block, current_args)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, current_args)
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
        emit_alias_for_index_binding(cmds, loop.index_binding, continue_index)
        emit_aliases_for_loop_bindings(cmds, loop.carries, continue_carry_params)
        local one_id = Back.BackValId(path .. ".index.step")
        local next_index = Back.BackValId(path .. ".index.next")
        local next_cmds, next_values = eval_loop_nexts(loop.next, path, layout_env)
        cmds[#cmds + 1] = Back.BackCmdConstInt(one_id, index_back_ty, "1")
        cmds[#cmds + 1] = one_add_cmd(index_ty, next_index, index_back_ty, continue_index, one_id)
        copy_cmds(next_cmds, cmds)
        local jump_args = { next_index }
        for i = 1, #next_values do
            jump_args[#jump_args + 1] = next_values[i]
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, jump_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
        return Back.BackStmtPlan(cmds, Back.BackFallsThrough)
    end

    local function build_over_expr_plan(loop, path, start_plan, stop_plan, layout_env)
        local index_ty = loop.index_binding.ty
        local result_ty = one_sem_expr_type(loop.result)
        local index_back_ty = one_scalar(index_ty)
        local header_block = Back.BackBlockId(path .. ".header.block")
        local body_block = Back.BackBlockId(path .. ".body.block")
        local continue_block = Back.BackBlockId(path .. ".continue.block")
        local exit_block = Back.BackBlockId(path .. ".exit.block")
        local header_index = Back.BackValId(path .. ".header.index")
        local body_index = Back.BackValId(path .. ".body.index")
        local continue_index = Back.BackValId(path .. ".continue.index")
        local exit_index = Back.BackValId(path .. ".exit.index")
        local header_carry_params = {}
        local body_carry_params = {}
        local continue_carry_params = {}
        local exit_carry_params = {}
        local header_jump_args = { header_index }
        local exit_jump_args = { header_index }
        local current_args = over_loop_current_args(loop.index_binding, loop.carries)
        local cmds = {
            Back.BackCmdCreateBlock(header_block),
            Back.BackCmdCreateBlock(body_block),
            Back.BackCmdCreateBlock(continue_block),
            Back.BackCmdCreateBlock(exit_block),
            Back.BackCmdAppendBlockParam(header_block, header_index, index_back_ty),
            Back.BackCmdAppendBlockParam(body_block, body_index, index_back_ty),
            Back.BackCmdAppendBlockParam(continue_block, continue_index, index_back_ty),
            Back.BackCmdAppendBlockParam(exit_block, exit_index, index_back_ty),
        }
        local init_args = {}
        append_expr_cmds(cmds, start_plan)
        init_args[1] = start_plan.value
        for i = 1, #loop.carries do
            local header_param = Back.BackValId(path .. ".header.carry." .. i)
            local body_param = Back.BackValId(path .. ".body.carry." .. i)
            local continue_param = Back.BackValId(path .. ".continue.carry." .. i)
            local exit_param = Back.BackValId(path .. ".exit.carry." .. i)
            header_carry_params[i] = header_param
            body_carry_params[i] = body_param
            continue_carry_params[i] = continue_param
            exit_carry_params[i] = exit_param
            header_jump_args[#header_jump_args + 1] = header_param
            exit_jump_args[#exit_jump_args + 1] = header_param
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(loop.carries[i].ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(loop.carries[i].ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(loop.carries[i].ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit_block, exit_param, one_scalar(loop.carries[i].ty))
            local init = one_expr(loop.carries[i].init, path .. ".carry_init." .. i, layout_env)
            append_expr_cmds(cmds, init)
            init_args[#init_args + 1] = init.value
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_args)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
        emit_alias_for_index_binding(cmds, loop.index_binding, header_index)
        emit_aliases_for_loop_bindings(cmds, loop.carries, header_carry_params)
        append_expr_cmds(cmds, stop_plan)
        local cond_value = Back.BackValId(path .. ".cond")
        cmds[#cmds + 1] = one_lt_cmd(index_ty, cond_value, Back.BackBool, header_index, stop_plan.value)
        cmds[#cmds + 1] = Back.BackCmdBrIf(cond_value, body_block, header_jump_args, exit_block, exit_jump_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
        emit_alias_for_index_binding(cmds, loop.index_binding, body_index)
        emit_aliases_for_loop_bindings(cmds, loop.carries, body_carry_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, exit_block, current_args, continue_block, current_args)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, current_args)
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
        emit_alias_for_index_binding(cmds, loop.index_binding, continue_index)
        emit_aliases_for_loop_bindings(cmds, loop.carries, continue_carry_params)
        local one_id = Back.BackValId(path .. ".index.step")
        local next_index = Back.BackValId(path .. ".index.next")
        local next_cmds, next_values = eval_loop_nexts(loop.next, path, layout_env)
        cmds[#cmds + 1] = Back.BackCmdConstInt(one_id, index_back_ty, "1")
        cmds[#cmds + 1] = one_add_cmd(index_ty, next_index, index_back_ty, continue_index, one_id)
        copy_cmds(next_cmds, cmds)
        local jump_args = { next_index }
        for i = 1, #next_values do
            jump_args[#jump_args + 1] = next_values[i]
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, jump_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
        emit_alias_for_index_binding(cmds, loop.index_binding, exit_index)
        emit_aliases_for_loop_bindings(cmds, loop.carries, exit_carry_params)
        local result = one_expr(loop.result, path .. ".result", layout_env)
        append_expr_cmds(cmds, result)
        return Back.BackExprPlan(cmds, result.value, one_scalar(result_ty))
    end

    lower_over_stmt_domain = pvm.phase("sem_to_back_over_stmt_domain", {
        [Sem.SemDomainRange] = function(self, loop, path, layout_env)
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty))
            return pvm.once(build_over_stmt_plan(loop, path, start, one_expr(self.stop, path .. ".stop", layout_env), layout_env))
        end,
        [Sem.SemDomainRange2] = function(self, loop, path, layout_env)
            return pvm.once(build_over_stmt_plan(loop, path, one_expr(self.start, path .. ".start", layout_env), one_expr(self.stop, path .. ".stop", layout_env), layout_env))
        end,
        [Sem.SemDomainBoundedValue] = function()
            error("sem_to_back_over_stmt_domain: bounded-value over loops are not yet supported; slice/aggregate length extraction needs an explicit low-level data-layout and bounds model")
        end,
        [Sem.SemDomainZipEq] = function()
            error("sem_to_back_over_stmt_domain: zip-eq over loops are not yet supported; equal-length multi-domain traversal needs an explicit low-level bounds agreement model")
        end,
    })

    lower_over_expr_domain = pvm.phase("sem_to_back_over_expr_domain", {
        [Sem.SemDomainRange] = function(self, loop, path, layout_env)
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty))
            return pvm.once(build_over_expr_plan(loop, path, start, one_expr(self.stop, path .. ".stop", layout_env), layout_env))
        end,
        [Sem.SemDomainRange2] = function(self, loop, path, layout_env)
            return pvm.once(build_over_expr_plan(loop, path, one_expr(self.start, path .. ".start", layout_env), one_expr(self.stop, path .. ".stop", layout_env), layout_env))
        end,
        [Sem.SemDomainBoundedValue] = function()
            error("sem_to_back_over_expr_domain: bounded-value over loops are not yet supported; slice/aggregate length extraction needs an explicit low-level data-layout and bounds model")
        end,
        [Sem.SemDomainZipEq] = function()
            error("sem_to_back_over_expr_domain: zip-eq over loops are not yet supported; equal-length multi-domain traversal needs an explicit low-level bounds agreement model")
        end,
    })

    local function build_over_expr_into_addr(loop, addr, path, start_plan, stop_plan, layout_env)
        local index_ty = loop.index_binding.ty
        local index_back_ty = one_scalar(index_ty)
        local header_block = Back.BackBlockId(path .. ".header.block")
        local body_block = Back.BackBlockId(path .. ".body.block")
        local continue_block = Back.BackBlockId(path .. ".continue.block")
        local exit_block = Back.BackBlockId(path .. ".exit.block")
        local header_index = Back.BackValId(path .. ".header.index")
        local body_index = Back.BackValId(path .. ".body.index")
        local continue_index = Back.BackValId(path .. ".continue.index")
        local exit_index = Back.BackValId(path .. ".exit.index")
        local header_carry_params = {}
        local body_carry_params = {}
        local continue_carry_params = {}
        local exit_carry_params = {}
        local header_jump_args = { header_index }
        local exit_jump_args = { header_index }
        local current_args = over_loop_current_args(loop.index_binding, loop.carries)
        local cmds = {
            Back.BackCmdCreateBlock(header_block),
            Back.BackCmdCreateBlock(body_block),
            Back.BackCmdCreateBlock(continue_block),
            Back.BackCmdCreateBlock(exit_block),
            Back.BackCmdAppendBlockParam(header_block, header_index, index_back_ty),
            Back.BackCmdAppendBlockParam(body_block, body_index, index_back_ty),
            Back.BackCmdAppendBlockParam(continue_block, continue_index, index_back_ty),
            Back.BackCmdAppendBlockParam(exit_block, exit_index, index_back_ty),
        }
        local init_args = {}
        append_expr_cmds(cmds, start_plan)
        if expr_terminates(start_plan) then
            return terminated_addr(cmds)
        end
        init_args[1] = start_plan.value
        for i = 1, #loop.carries do
            local header_param = Back.BackValId(path .. ".header.carry." .. i)
            local body_param = Back.BackValId(path .. ".body.carry." .. i)
            local continue_param = Back.BackValId(path .. ".continue.carry." .. i)
            local exit_param = Back.BackValId(path .. ".exit.carry." .. i)
            header_carry_params[i] = header_param
            body_carry_params[i] = body_param
            continue_carry_params[i] = continue_param
            exit_carry_params[i] = exit_param
            header_jump_args[#header_jump_args + 1] = header_param
            exit_jump_args[#exit_jump_args + 1] = header_param
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(loop.carries[i].ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(loop.carries[i].ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(loop.carries[i].ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit_block, exit_param, one_scalar(loop.carries[i].ty))
            local init = one_expr(loop.carries[i].init, path .. ".carry_init." .. i, layout_env)
            append_expr_cmds(cmds, init)
            if expr_terminates(init) then
                return terminated_addr(cmds)
            end
            init_args[#init_args + 1] = init.value
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_args)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
        emit_alias_for_index_binding(cmds, loop.index_binding, header_index)
        emit_aliases_for_loop_bindings(cmds, loop.carries, header_carry_params)
        append_expr_cmds(cmds, stop_plan)
        if expr_terminates(stop_plan) then
            return terminated_addr(cmds)
        end
        local cond_value = Back.BackValId(path .. ".cond")
        cmds[#cmds + 1] = one_lt_cmd(index_ty, cond_value, Back.BackBool, header_index, stop_plan.value)
        cmds[#cmds + 1] = Back.BackCmdBrIf(cond_value, body_block, header_jump_args, exit_block, exit_jump_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
        emit_alias_for_index_binding(cmds, loop.index_binding, body_index)
        emit_aliases_for_loop_bindings(cmds, loop.carries, body_carry_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, exit_block, current_args, continue_block, current_args)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, current_args)
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
        emit_alias_for_index_binding(cmds, loop.index_binding, continue_index)
        emit_aliases_for_loop_bindings(cmds, loop.carries, continue_carry_params)
        local one_id = Back.BackValId(path .. ".index.step")
        local next_index = Back.BackValId(path .. ".index.next")
        local next_cmds, next_values, next_flow = eval_loop_nexts(loop.next, path, layout_env)
        cmds[#cmds + 1] = Back.BackCmdConstInt(one_id, index_back_ty, "1")
        cmds[#cmds + 1] = one_add_cmd(index_ty, next_index, index_back_ty, continue_index, one_id)
        copy_cmds(next_cmds, cmds)
        if next_flow == Back.BackTerminates then
            return terminated_addr(cmds)
        end
        local jump_args = { next_index }
        for i = 1, #next_values do
            jump_args[#jump_args + 1] = next_values[i]
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, jump_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
        emit_alias_for_index_binding(cmds, loop.index_binding, exit_index)
        emit_aliases_for_loop_bindings(cmds, loop.carries, exit_carry_params)
        local result = one_expr_into_addr(loop.result, addr, path .. ".result", layout_env)
        append_addr_cmds(cmds, result)
        if addr_terminates(result) then
            return terminated_addr(cmds)
        end
        return addr_writes(cmds)
    end

    lower_over_expr_into_addr_domain = pvm.phase("sem_to_back_over_expr_into_addr_domain", {
        [Sem.SemDomainRange] = function(self, loop, addr, path, layout_env)
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty))
            return pvm.once(build_over_expr_into_addr(loop, addr, path, start, one_expr(self.stop, path .. ".stop", layout_env), layout_env))
        end,
        [Sem.SemDomainRange2] = function(self, loop, addr, path, layout_env)
            return pvm.once(build_over_expr_into_addr(loop, addr, path, one_expr(self.start, path .. ".start", layout_env), one_expr(self.stop, path .. ".stop", layout_env), layout_env))
        end,
        [Sem.SemDomainBoundedValue] = function()
            error("sem_to_back_over_expr_into_addr_domain: bounded-value over loops are not yet supported; slice/aggregate length extraction needs an explicit low-level data-layout and bounds model")
        end,
        [Sem.SemDomainZipEq] = function()
            error("sem_to_back_over_expr_into_addr_domain: zip-eq over loops are not yet supported; equal-length multi-domain traversal needs an explicit low-level bounds agreement model")
        end,
    })

    lower_loop_stmt_plan = pvm.phase("sem_to_back_loop_stmt", {
        [Sem.SemLoopWhileStmt] = function(self, path, layout_env)
            local header_block = Back.BackBlockId(path .. ".header.block")
            local body_block = Back.BackBlockId(path .. ".body.block")
            local continue_block = Back.BackBlockId(path .. ".continue.block")
            local exit_block = Back.BackBlockId(path .. ".exit.block")
            local header_params = {}
            local body_params = {}
            local continue_params = {}
            local current_args = loop_binding_value_args(self.vars)
            local cmds = {
                Back.BackCmdCreateBlock(header_block),
                Back.BackCmdCreateBlock(body_block),
                Back.BackCmdCreateBlock(continue_block),
                Back.BackCmdCreateBlock(exit_block),
            }
            local init_values = {}
            for i = 1, #self.vars do
                local header_param = Back.BackValId(path .. ".header.param." .. i)
                local body_param = Back.BackValId(path .. ".body.param." .. i)
                local continue_param = Back.BackValId(path .. ".continue.param." .. i)
                header_params[i] = header_param
                body_params[i] = body_param
                continue_params[i] = continue_param
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(self.vars[i].ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(self.vars[i].ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(self.vars[i].ty))
                local init = one_expr(self.vars[i].init, path .. ".init." .. i, layout_env)
                append_expr_cmds(cmds, init)
                init_values[i] = init.value
            end
            cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_values)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
            emit_aliases_for_loop_bindings(cmds, self.vars, header_params)
            local cond = one_expr(self.cond, path .. ".cond", layout_env)
            append_expr_cmds(cmds, cond)
            cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, body_block, header_params, exit_block, {})
            cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
            emit_aliases_for_loop_bindings(cmds, self.vars, body_params)
            local body_cmds, body_flow = lower_stmt_list(self.body, path .. ".body", layout_env, exit_block, {}, continue_block, current_args)
            copy_cmds(body_cmds, cmds)
            if body_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(continue_block, current_args)
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
            emit_aliases_for_loop_bindings(cmds, self.vars, continue_params)
            local next_cmds, next_values = eval_loop_nexts(self.next, path, layout_env)
            copy_cmds(next_cmds, cmds)
            cmds[#cmds + 1] = Back.BackCmdJump(header_block, next_values)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
        end,
        [Sem.SemLoopOverStmt] = function(self, path, layout_env)
            return pvm.once(one_over_stmt_domain(self.domain, self, path, layout_env))
        end,
        [Sem.SemLoopWhileExpr] = function()
            error("sem_to_back_loop_stmt: expected stmt loop, got expr loop")
        end,
        [Sem.SemLoopOverExpr] = function()
            error("sem_to_back_loop_stmt: expected stmt loop, got expr loop")
        end,
    })

    lower_loop_expr_plan = pvm.phase("sem_to_back_loop_expr", {
        [Sem.SemLoopWhileExpr] = function(self, path, layout_env)
            local result_ty = one_sem_expr_type(self.result)
            local header_block = Back.BackBlockId(path .. ".header.block")
            local body_block = Back.BackBlockId(path .. ".body.block")
            local continue_block = Back.BackBlockId(path .. ".continue.block")
            local exit_block = Back.BackBlockId(path .. ".exit.block")
            local header_params = {}
            local body_params = {}
            local continue_params = {}
            local exit_params = {}
            local current_args = loop_binding_value_args(self.vars)
            local cmds = {
                Back.BackCmdCreateBlock(header_block),
                Back.BackCmdCreateBlock(body_block),
                Back.BackCmdCreateBlock(continue_block),
                Back.BackCmdCreateBlock(exit_block),
            }
            local init_values = {}
            for i = 1, #self.vars do
                local header_param = Back.BackValId(path .. ".header.param." .. i)
                local body_param = Back.BackValId(path .. ".body.param." .. i)
                local continue_param = Back.BackValId(path .. ".continue.param." .. i)
                local exit_param = Back.BackValId(path .. ".exit.param." .. i)
                header_params[i] = header_param
                body_params[i] = body_param
                continue_params[i] = continue_param
                exit_params[i] = exit_param
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(self.vars[i].ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(self.vars[i].ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(self.vars[i].ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit_block, exit_param, one_scalar(self.vars[i].ty))
                local init = one_expr(self.vars[i].init, path .. ".init." .. i, layout_env)
                append_expr_cmds(cmds, init)
                init_values[i] = init.value
            end
            cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_values)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
            emit_aliases_for_loop_bindings(cmds, self.vars, header_params)
            local cond = one_expr(self.cond, path .. ".cond", layout_env)
            append_expr_cmds(cmds, cond)
            cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, body_block, header_params, exit_block, header_params)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
            emit_aliases_for_loop_bindings(cmds, self.vars, body_params)
            local body_cmds, body_flow = lower_stmt_list(self.body, path .. ".body", layout_env, exit_block, current_args, continue_block, current_args)
            copy_cmds(body_cmds, cmds)
            if body_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(continue_block, current_args)
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
            emit_aliases_for_loop_bindings(cmds, self.vars, continue_params)
            local next_cmds, next_values = eval_loop_nexts(self.next, path, layout_env)
            copy_cmds(next_cmds, cmds)
            cmds[#cmds + 1] = Back.BackCmdJump(header_block, next_values)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
            emit_aliases_for_loop_bindings(cmds, self.vars, exit_params)
            local result = one_expr(self.result, path .. ".result", layout_env)
            append_expr_cmds(cmds, result)
            return pvm.once(Back.BackExprPlan(cmds, result.value, one_scalar(result_ty)))
        end,
        [Sem.SemLoopOverExpr] = function(self, path, layout_env)
            return pvm.once(one_over_expr_domain(self.domain, self, path, layout_env))
        end,
        [Sem.SemLoopWhileStmt] = function()
            error("sem_to_back_loop_expr: expected expr loop, got stmt loop")
        end,
        [Sem.SemLoopOverStmt] = function()
            error("sem_to_back_loop_expr: expected expr loop, got stmt loop")
        end,
    })

    lower_loop_expr_into_addr = pvm.phase("sem_to_back_loop_expr_into_addr", {
        [Sem.SemLoopWhileExpr] = function(self, addr, path, layout_env)
            local header_block = Back.BackBlockId(path .. ".header.block")
            local body_block = Back.BackBlockId(path .. ".body.block")
            local continue_block = Back.BackBlockId(path .. ".continue.block")
            local exit_block = Back.BackBlockId(path .. ".exit.block")
            local header_params = {}
            local body_params = {}
            local continue_params = {}
            local exit_params = {}
            local current_args = loop_binding_value_args(self.vars)
            local cmds = {
                Back.BackCmdCreateBlock(header_block),
                Back.BackCmdCreateBlock(body_block),
                Back.BackCmdCreateBlock(continue_block),
                Back.BackCmdCreateBlock(exit_block),
            }
            local init_values = {}
            for i = 1, #self.vars do
                local header_param = Back.BackValId(path .. ".header.param." .. i)
                local body_param = Back.BackValId(path .. ".body.param." .. i)
                local continue_param = Back.BackValId(path .. ".continue.param." .. i)
                local exit_param = Back.BackValId(path .. ".exit.param." .. i)
                header_params[i] = header_param
                body_params[i] = body_param
                continue_params[i] = continue_param
                exit_params[i] = exit_param
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(self.vars[i].ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(self.vars[i].ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(self.vars[i].ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit_block, exit_param, one_scalar(self.vars[i].ty))
                local init = one_expr(self.vars[i].init, path .. ".init." .. i, layout_env)
                append_expr_cmds(cmds, init)
                if expr_terminates(init) then
                    return pvm.once(terminated_addr(cmds))
                end
                init_values[i] = init.value
            end
            cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_values)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
            emit_aliases_for_loop_bindings(cmds, self.vars, header_params)
            local cond = one_expr(self.cond, path .. ".cond", layout_env)
            append_expr_cmds(cmds, cond)
            if expr_terminates(cond) then
                return pvm.once(terminated_addr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, body_block, header_params, exit_block, header_params)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
            emit_aliases_for_loop_bindings(cmds, self.vars, body_params)
            local body_cmds, body_flow = lower_stmt_list(self.body, path .. ".body", layout_env, exit_block, current_args, continue_block, current_args)
            copy_cmds(body_cmds, cmds)
            if body_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(continue_block, current_args)
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
            emit_aliases_for_loop_bindings(cmds, self.vars, continue_params)
            local next_cmds, next_values, next_flow = eval_loop_nexts(self.next, path, layout_env)
            copy_cmds(next_cmds, cmds)
            if next_flow == Back.BackTerminates then
                return pvm.once(terminated_addr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdJump(header_block, next_values)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
            emit_aliases_for_loop_bindings(cmds, self.vars, exit_params)
            local result = one_expr_into_addr(self.result, addr, path .. ".result", layout_env)
            append_addr_cmds(cmds, result)
            if addr_terminates(result) then
                return pvm.once(terminated_addr(cmds))
            end
            return pvm.once(addr_writes(cmds))
        end,
        [Sem.SemLoopOverExpr] = function(self, addr, path, layout_env)
            return pvm.once(one_over_expr_into_addr_domain(self.domain, self, addr, path, layout_env))
        end,
        [Sem.SemLoopWhileStmt] = function()
            error("sem_to_back_loop_expr_into_addr: expected expr loop, got stmt loop")
        end,
        [Sem.SemLoopOverStmt] = function()
            error("sem_to_back_loop_expr_into_addr: expected expr loop, got stmt loop")
        end,
    })

    local function expr_stmt_delegate()
        return function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = one_expr(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end
    end

    lower_expr_stmt = pvm.phase("sem_to_back_expr_stmt", {
        [Sem.SemExprConstInt] = expr_stmt_delegate(),
        [Sem.SemExprConstFloat] = expr_stmt_delegate(),
        [Sem.SemExprConstBool] = expr_stmt_delegate(),
        [Sem.SemExprNil] = expr_stmt_delegate(),
        [Sem.SemExprBinding] = expr_stmt_delegate(),
        [Sem.SemExprNeg] = expr_stmt_delegate(),
        [Sem.SemExprNot] = expr_stmt_delegate(),
        [Sem.SemExprBNot] = expr_stmt_delegate(),
        [Sem.SemExprRef] = expr_stmt_delegate(),
        [Sem.SemExprDeref] = expr_stmt_delegate(),
        [Sem.SemExprAdd] = expr_stmt_delegate(),
        [Sem.SemExprSub] = expr_stmt_delegate(),
        [Sem.SemExprMul] = expr_stmt_delegate(),
        [Sem.SemExprDiv] = expr_stmt_delegate(),
        [Sem.SemExprRem] = expr_stmt_delegate(),
        [Sem.SemExprEq] = expr_stmt_delegate(),
        [Sem.SemExprNe] = expr_stmt_delegate(),
        [Sem.SemExprLt] = expr_stmt_delegate(),
        [Sem.SemExprLe] = expr_stmt_delegate(),
        [Sem.SemExprGt] = expr_stmt_delegate(),
        [Sem.SemExprGe] = expr_stmt_delegate(),
        [Sem.SemExprAnd] = expr_stmt_delegate(),
        [Sem.SemExprOr] = expr_stmt_delegate(),
        [Sem.SemExprBitAnd] = expr_stmt_delegate(),
        [Sem.SemExprBitOr] = expr_stmt_delegate(),
        [Sem.SemExprBitXor] = expr_stmt_delegate(),
        [Sem.SemExprShl] = expr_stmt_delegate(),
        [Sem.SemExprLShr] = expr_stmt_delegate(),
        [Sem.SemExprAShr] = expr_stmt_delegate(),
        [Sem.SemExprCastTo] = expr_stmt_delegate(),
        [Sem.SemExprTruncTo] = expr_stmt_delegate(),
        [Sem.SemExprZExtTo] = expr_stmt_delegate(),
        [Sem.SemExprSExtTo] = expr_stmt_delegate(),
        [Sem.SemExprBitcastTo] = expr_stmt_delegate(),
        [Sem.SemExprSatCastTo] = expr_stmt_delegate(),
        [Sem.SemExprSelect] = expr_stmt_delegate(),
        [Sem.SemExprIndex] = expr_stmt_delegate(),
        [Sem.SemExprField] = expr_stmt_delegate(),
        [Sem.SemExprIndexAddr] = expr_stmt_delegate(),
        [Sem.SemExprFieldAddr] = expr_stmt_delegate(),
        [Sem.SemExprLoad] = expr_stmt_delegate(),
        [Sem.SemExprIntrinsicCall] = expr_stmt_delegate(),
        [Sem.SemExprCall] = expr_stmt_delegate(),
        [Sem.SemExprAgg] = expr_stmt_delegate(),
        [Sem.SemExprArrayLit] = expr_stmt_delegate(),
        [Sem.SemExprLoop] = expr_stmt_delegate(),
        [Sem.SemExprBlock] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local body_cmds, body_flow = lower_stmt_list(self.stmts, path .. ".stmts", layout_env, break_block, break_args, continue_block, continue_args)
            local cmds = {}
            copy_cmds(body_cmds, cmds)
            if body_flow == Back.BackFallsThrough then
                local result_plan = one_expr_stmt(self.result, path .. ".result", layout_env, break_block, break_args, continue_block, continue_args)
                copy_cmds(result_plan.cmds, cmds)
                return pvm.once(Back.BackStmtPlan(cmds, result_plan.flow))
            end
            return pvm.once(Back.BackStmtPlan(cmds, body_flow))
        end,
        [Sem.SemExprIf] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local cond = one_expr(self.cond, path .. ".cond", layout_env, break_block, break_args, continue_block, continue_args)
            if expr_terminates(cond) then
                return pvm.once(Back.BackStmtPlan(cond.cmds, Back.BackTerminates))
            end
            local then_plan = one_expr_stmt(self.then_expr, path .. ".then", layout_env, break_block, break_args, continue_block, continue_args)
            local else_plan = one_expr_stmt(self.else_expr, path .. ".else", layout_env, break_block, break_args, continue_block, continue_args)
            local then_block = Back.BackBlockId(path .. ".then.block")
            local else_block = Back.BackBlockId(path .. ".else.block")
            local join_block = Back.BackBlockId(path .. ".join.block")
            local need_join = then_plan.flow == Back.BackFallsThrough or else_plan.flow == Back.BackFallsThrough
            local cmds = {}
            append_expr_cmds(cmds, cond)
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(then_block)
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(else_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
            end
            cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, then_block, {}, else_block, {})
            cmds[#cmds + 1] = Back.BackCmdSealBlock(then_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(else_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(then_block)
            copy_cmds(then_plan.cmds, cmds)
            if then_plan.flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(else_block)
            copy_cmds(else_plan.cmds, cmds)
            if else_plan.flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
            end
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
        end,
        [Sem.SemExprSwitch] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local value_ty = one_sem_expr_type(self.value)
            if not one_type_is_scalar(value_ty) then
                error("sem_to_back_expr_stmt: switch value must currently be scalar in Sem->Back")
            end
            local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args)
            if expr_terminates(value) then
                return pvm.once(Back.BackStmtPlan(value.cmds, Back.BackTerminates))
            end
            local default_plan = one_expr_stmt(self.default_expr, path .. ".default", layout_env, break_block, break_args, continue_block, continue_args)
            local arm_plans = {}
            local need_join = default_plan.flow == Back.BackFallsThrough
            for i = 1, #self.arms do
                local body_cmds, body_flow = lower_stmt_list(self.arms[i].body, path .. ".arm." .. i, layout_env, break_block, break_args, continue_block, continue_args)
                local plan_cmds = {}
                copy_cmds(body_cmds, plan_cmds)
                local plan_flow = body_flow
                if body_flow == Back.BackFallsThrough then
                    local result_plan = one_expr_stmt(self.arms[i].result, path .. ".arm." .. i .. ".result", layout_env, break_block, break_args, continue_block, continue_args)
                    copy_cmds(result_plan.cmds, plan_cmds)
                    plan_flow = result_plan.flow
                end
                arm_plans[i] = Back.BackStmtPlan(plan_cmds, plan_flow)
                if plan_flow == Back.BackFallsThrough then
                    need_join = true
                end
            end
            if #self.arms == 0 then
                local cmds = {}
                append_expr_cmds(cmds, value)
                copy_cmds(default_plan.cmds, cmds)
                return pvm.once(Back.BackStmtPlan(cmds, default_plan.flow))
            end
            local join_block = Back.BackBlockId(path .. ".join.block")
            local default_block = Back.BackBlockId(path .. ".default.block")
            local arm_blocks = {}
            local test_blocks = {}
            local cmds = {}
            append_expr_cmds(cmds, value)
            for i = 1, #self.arms do
                arm_blocks[i] = Back.BackBlockId(path .. ".arm." .. i .. ".block")
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(arm_blocks[i])
                if i > 1 then
                    test_blocks[i] = Back.BackBlockId(path .. ".test." .. i .. ".block")
                    cmds[#cmds + 1] = Back.BackCmdCreateBlock(test_blocks[i])
                end
            end
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(default_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
            end
            for i = 1, #self.arms do
                if i > 1 then
                    cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(test_blocks[i])
                end
                local key = one_expr(self.arms[i].key, path .. ".arm." .. i .. ".key", layout_env, break_block, break_args, continue_block, continue_args)
                append_expr_cmds(cmds, key)
                local else_block = (i < #self.arms) and test_blocks[i + 1] or default_block
                if expr_has_value(key) then
                    local match = Back.BackValId(path .. ".arm." .. i .. ".match")
                    cmds[#cmds + 1] = one_eq_cmd(value_ty, match, Back.BackBool, value.value, key.value)
                    cmds[#cmds + 1] = Back.BackCmdBrIf(match, arm_blocks[i], {}, else_block, {})
                    cmds[#cmds + 1] = Back.BackCmdSealBlock(arm_blocks[i])
                    cmds[#cmds + 1] = Back.BackCmdSealBlock(else_block)
                end
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(arm_blocks[i])
                copy_cmds(arm_plans[i].cmds, cmds)
                if arm_plans[i].flow == Back.BackFallsThrough then
                    cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
                end
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(default_block)
            copy_cmds(default_plan.cmds, cmds)
            if default_plan.flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
            end
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
        end,
    })

    lower_stmt = pvm.phase("sem_to_back_stmt", {
        [Sem.SemStmtLet] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local spec = one_stack_slot_spec(self.ty, layout_env)
            local addr = Back.BackValId(path .. ".addr")
            local cmds = {
                Back.BackCmdCreateStackSlot(local_value_slot_id(self.id), spec.size, spec.align),
                Back.BackCmdStackAddr(addr, local_value_slot_id(self.id)),
            }
            if one_type_is_scalar(self.ty) then
                local init = one_expr(self.init, path .. ".init", layout_env, break_block, break_args, continue_block, continue_args)
                append_expr_cmds(cmds, init)
                if expr_terminates(init) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
                cmds[#cmds + 1] = Back.BackCmdAlias(local_value_id(self.id), init.value)
                cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(self.ty), addr, init.value)
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
            end
            local init_plan = one_expr_into_addr(self.init, addr, path .. ".init_store", layout_env, break_block, break_args, continue_block, continue_args)
            append_addr_cmds(cmds, init_plan)
            return pvm.once(Back.BackStmtPlan(cmds, addr_to_stmt_flow(init_plan)))
        end,
        [Sem.SemStmtVar] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local spec = one_stack_slot_spec(self.ty, layout_env)
            local addr = Back.BackValId(path .. ".addr")
            local cmds = {
                Back.BackCmdCreateStackSlot(local_cell_slot_id(self.id), spec.size, spec.align),
                Back.BackCmdStackAddr(addr, local_cell_slot_id(self.id)),
            }
            if one_type_is_scalar(self.ty) then
                local init = one_expr(self.init, path .. ".init", layout_env, break_block, break_args, continue_block, continue_args)
                append_expr_cmds(cmds, init)
                if expr_terminates(init) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
                cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(self.ty), addr, init.value)
            else
                local init_plan = one_expr_into_addr(self.init, addr, path .. ".init_store", layout_env, break_block, break_args, continue_block, continue_args)
                append_addr_cmds(cmds, init_plan)
                if addr_terminates(init_plan) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
            end
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
        end,
        [Sem.SemStmtSet] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local addr = one_binding_store_addr(self.binding, path .. ".addr")
            local cmds = {}
            append_expr_cmds(cmds, addr)
            if expr_terminates(addr) then
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
            end
            if one_type_is_scalar(self.binding.ty) then
                local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args)
                append_expr_cmds(cmds, value)
                if expr_terminates(value) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
                cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(self.binding.ty), addr.value, value.value)
            else
                local value_plan = one_expr_into_addr(self.value, addr.value, path .. ".value_store", layout_env, break_block, break_args, continue_block, continue_args)
                append_addr_cmds(cmds, value_plan)
                if addr_terminates(value_plan) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
            end
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
        end,
        [Sem.SemStmtExpr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(one_expr_stmt(self.expr, path .. ".expr", layout_env, break_block, break_args, continue_block, continue_args))
        end,
        [Sem.SemStmtStore] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local addr = one_expr(self.addr, path .. ".addr", layout_env, break_block, break_args, continue_block, continue_args)
            local cmds = {}
            append_expr_cmds(cmds, addr)
            if expr_terminates(addr) then
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
            end
            if one_type_is_scalar(self.ty) then
                local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args)
                append_expr_cmds(cmds, value)
                if expr_terminates(value) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
                cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(self.ty), addr.value, value.value)
            else
                local value_plan = one_expr_into_addr(self.value, addr.value, path .. ".value_store", layout_env, break_block, break_args, continue_block, continue_args)
                append_addr_cmds(cmds, value_plan)
                if addr_terminates(value_plan) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
            end
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
        end,
        [Sem.SemStmtIf] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local cond = one_expr(self.cond, path .. ".cond", layout_env, break_block, break_args, continue_block, continue_args)
            if expr_terminates(cond) then
                return pvm.once(Back.BackStmtPlan(cond.cmds, Back.BackTerminates))
            end
            local then_cmds, then_flow = lower_stmt_list(self.then_body, path .. ".then", layout_env, break_block, break_args, continue_block, continue_args)
            local else_cmds, else_flow = lower_stmt_list(self.else_body, path .. ".else", layout_env, break_block, break_args, continue_block, continue_args)
            local then_block = Back.BackBlockId(path .. ".then.block")
            local else_block = Back.BackBlockId(path .. ".else.block")
            local join_block = Back.BackBlockId(path .. ".join.block")
            local need_join = then_flow == Back.BackFallsThrough or else_flow == Back.BackFallsThrough
            local cmds = {}
            append_expr_cmds(cmds, cond)
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(then_block)
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(else_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
            end
            cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, then_block, {}, else_block, {})
            cmds[#cmds + 1] = Back.BackCmdSealBlock(then_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(else_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(then_block)
            copy_cmds(then_cmds, cmds)
            if then_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(else_block)
            copy_cmds(else_cmds, cmds)
            if else_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
            end
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
        end,
        [Sem.SemStmtSwitch] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local value_ty = one_sem_expr_type(self.value)
            if not one_type_is_scalar(value_ty) then
                error("sem_to_back_stmt: switch value must currently be scalar in Sem->Back")
            end
            local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args)
            if expr_terminates(value) then
                return pvm.once(Back.BackStmtPlan(value.cmds, Back.BackTerminates))
            end
            local default_cmds, default_flow = lower_stmt_list(self.default_body, path .. ".default", layout_env, break_block, break_args, continue_block, continue_args)
            local arm_cmds = {}
            local arm_flows = {}
            local need_join = default_flow == Back.BackFallsThrough
            for i = 1, #self.arms do
                arm_cmds[i], arm_flows[i] = lower_stmt_list(self.arms[i].body, path .. ".arm." .. i, layout_env, break_block, break_args, continue_block, continue_args)
                if arm_flows[i] == Back.BackFallsThrough then
                    need_join = true
                end
            end
            if #self.arms == 0 then
                local cmds = {}
                append_expr_cmds(cmds, value)
                copy_cmds(default_cmds, cmds)
                return pvm.once(Back.BackStmtPlan(cmds, default_flow))
            end
            local join_block = Back.BackBlockId(path .. ".join.block")
            local default_block = Back.BackBlockId(path .. ".default.block")
            local arm_blocks = {}
            local test_blocks = {}
            local cmds = {}
            append_expr_cmds(cmds, value)
            for i = 1, #self.arms do
                arm_blocks[i] = Back.BackBlockId(path .. ".arm." .. i .. ".block")
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(arm_blocks[i])
                if i > 1 then
                    test_blocks[i] = Back.BackBlockId(path .. ".test." .. i .. ".block")
                    cmds[#cmds + 1] = Back.BackCmdCreateBlock(test_blocks[i])
                end
            end
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(default_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
            end
            for i = 1, #self.arms do
                if i > 1 then
                    cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(test_blocks[i])
                end
                local key = one_expr(self.arms[i].key, path .. ".arm." .. i .. ".key", layout_env, break_block, break_args, continue_block, continue_args)
                append_expr_cmds(cmds, key)
                local else_block = (i < #self.arms) and test_blocks[i + 1] or default_block
                if expr_has_value(key) then
                    local match = Back.BackValId(path .. ".arm." .. i .. ".match")
                    cmds[#cmds + 1] = one_eq_cmd(value_ty, match, Back.BackBool, value.value, key.value)
                    cmds[#cmds + 1] = Back.BackCmdBrIf(match, arm_blocks[i], {}, else_block, {})
                    cmds[#cmds + 1] = Back.BackCmdSealBlock(arm_blocks[i])
                    cmds[#cmds + 1] = Back.BackCmdSealBlock(else_block)
                end
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(arm_blocks[i])
                copy_cmds(arm_cmds[i], cmds)
                if arm_flows[i] == Back.BackFallsThrough then
                    cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
                end
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(default_block)
            copy_cmds(default_cmds, cmds)
            if default_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
            end
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
        end,
        [Sem.SemStmtAssert] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local cond = one_expr(self.cond, path .. ".cond", layout_env, break_block, break_args, continue_block, continue_args)
            if expr_terminates(cond) then
                return pvm.once(Back.BackStmtPlan(cond.cmds, Back.BackTerminates))
            end
            local ok_block = Back.BackBlockId(path .. ".ok.block")
            local fail_block = Back.BackBlockId(path .. ".fail.block")
            local cmds = {}
            append_expr_cmds(cmds, cond)
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(ok_block)
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(fail_block)
            cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, ok_block, {}, fail_block, {})
            cmds[#cmds + 1] = Back.BackCmdSealBlock(ok_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(fail_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(fail_block)
            cmds[#cmds + 1] = Back.BackCmdTrap
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(ok_block)
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
        end,
        [Sem.SemStmtLoop] = function(self, path, layout_env)
            return pvm.once(one_loop_stmt_plan(self.loop, path, layout_env))
        end,
        [Sem.SemStmtReturnVoid] = function()
            return pvm.once(Back.BackStmtPlan({ Back.BackCmdReturnVoid }, Back.BackTerminates))
        end,
        [Sem.SemStmtReturnValue] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local ret_ty = one_sem_expr_type(self.value)
            if not one_type_is_scalar(ret_ty) then
                error("sem_to_back_stmt: non-scalar return values are not yet supported by the current Back ABI")
            end
            local expr = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args)
            local cmds = {}
            append_expr_cmds(cmds, expr)
            if expr_terminates(expr) then
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
            end
            cmds[#cmds + 1] = Back.BackCmdReturnValue(expr.value)
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
        end,
        [Sem.SemStmtBreak] = function(self, path, layout_env, break_block, break_args)
            if break_block == nil then
                error("sem_to_back_stmt: break is only valid inside a loop body")
            end
            return pvm.once(Back.BackStmtPlan({ Back.BackCmdJump(break_block, break_args or {}) }, Back.BackTerminates))
        end,
        [Sem.SemStmtContinue] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            if continue_block == nil then
                error("sem_to_back_stmt: continue is only valid inside a loop body")
            end
            return pvm.once(Back.BackStmtPlan({ Back.BackCmdJump(continue_block, continue_args or {}) }, Back.BackTerminates))
        end,
    })

    lower_func = pvm.phase("sem_to_back_func", {
        [Sem.SemFuncLocal] = function(self, layout_env)
            local func_text = self.name
            local sig_id = Back.BackSigId("sig:" .. func_text)
            local func_id = Back.BackFuncId(func_text)
            local entry_id = Back.BackBlockId(func_text .. ":entry")
            local params = {}
            local results = {}
            local entry_vals = {}
            for i = 1, #self.params do
                params[i] = one_scalar(self.params[i].ty)
                entry_vals[i] = Back.BackValId("arg:" .. (i - 1) .. ":" .. self.params[i].name)
            end
            if self.result ~= Sem.SemTVoid then
                results[1] = one_scalar(self.result)
            end
            local body_cmds = lower_stmt_list(self.body, "func:" .. func_text, layout_env)
            local cmds = {
                Back.BackCmdCreateSig(sig_id, params, results),
                Back.BackCmdDeclareFuncLocal(func_id, sig_id),
                Back.BackCmdBeginFunc(func_id),
                Back.BackCmdCreateBlock(entry_id),
                Back.BackCmdSwitchToBlock(entry_id),
            }
            if #entry_vals > 0 then
                cmds[#cmds + 1] = Back.BackCmdBindEntryParams(entry_id, entry_vals)
                for i = 1, #self.params do
                    local param = self.params[i]
                    local slot = arg_slot_id(i - 1, param.name)
                    local addr = Back.BackValId("arg.addr:" .. (i - 1) .. ":" .. param.name)
                    local value = Back.BackValId("arg:" .. (i - 1) .. ":" .. param.name)
                    local spec = one_stack_slot_spec(param.ty, layout_env)
                    cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(slot, spec.size, spec.align)
                    cmds[#cmds + 1] = Back.BackCmdStackAddr(addr, slot)
                    cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(param.ty), addr, value)
                end
            end
            copy_cmds(body_cmds, cmds)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(entry_id)
            cmds[#cmds + 1] = Back.BackCmdFinishFunc(func_id)
            return pvm.once(Back.BackFuncPlan(cmds))
        end,
        [Sem.SemFuncExport] = function(self, layout_env)
            local func_text = self.name
            local sig_id = Back.BackSigId("sig:" .. func_text)
            local func_id = Back.BackFuncId(func_text)
            local entry_id = Back.BackBlockId(func_text .. ":entry")
            local params = {}
            local results = {}
            local entry_vals = {}
            for i = 1, #self.params do
                params[i] = one_scalar(self.params[i].ty)
                entry_vals[i] = Back.BackValId("arg:" .. (i - 1) .. ":" .. self.params[i].name)
            end
            if self.result ~= Sem.SemTVoid then
                results[1] = one_scalar(self.result)
            end
            local body_cmds = lower_stmt_list(self.body, "func:" .. func_text, layout_env)
            local cmds = {
                Back.BackCmdCreateSig(sig_id, params, results),
                Back.BackCmdDeclareFuncExport(func_id, sig_id),
                Back.BackCmdBeginFunc(func_id),
                Back.BackCmdCreateBlock(entry_id),
                Back.BackCmdSwitchToBlock(entry_id),
            }
            if #entry_vals > 0 then
                cmds[#cmds + 1] = Back.BackCmdBindEntryParams(entry_id, entry_vals)
                for i = 1, #self.params do
                    local param = self.params[i]
                    local slot = arg_slot_id(i - 1, param.name)
                    local addr = Back.BackValId("arg.addr:" .. (i - 1) .. ":" .. param.name)
                    local value = Back.BackValId("arg:" .. (i - 1) .. ":" .. param.name)
                    local spec = one_stack_slot_spec(param.ty, layout_env)
                    cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(slot, spec.size, spec.align)
                    cmds[#cmds + 1] = Back.BackCmdStackAddr(addr, slot)
                    cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(param.ty), addr, value)
                end
            end
            copy_cmds(body_cmds, cmds)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(entry_id)
            cmds[#cmds + 1] = Back.BackCmdFinishFunc(func_id)
            return pvm.once(Back.BackFuncPlan(cmds))
        end,
    })

    lower_item = pvm.phase("sem_to_back_item", {
        [Sem.SemItemFunc] = function(self, layout_env)
            return pvm.once(Back.BackItemPlan(one_func(self.func, layout_env).cmds))
        end,
        [Sem.SemItemExtern] = function(self)
            local params = {}
            local results = {}
            for i = 1, #self.func.params do
                params[i] = one_scalar(self.func.params[i].ty)
            end
            if self.func.result ~= Sem.SemTVoid then
                results[1] = one_scalar(self.func.result)
            end
            local sig_id = Back.BackSigId("sig:extern:" .. self.func.symbol)
            return pvm.once(Back.BackItemPlan({
                Back.BackCmdCreateSig(sig_id, params, results),
                Back.BackCmdDeclareFuncExtern(Back.BackExternId(self.func.symbol), self.func.symbol, sig_id),
            }))
        end,
        [Sem.SemItemConst] = function(self, layout_env)
            local data_id = const_data_id("", self.c.name)
            local spec = one_stack_slot_spec(self.c.ty, layout_env)
            local cmds = {
                Back.BackCmdDeclareData(data_id, spec.size, spec.align),
            }
            copy_cmds(one_const_data_init(self.c.value, data_id, 0, layout_env), cmds)
            return pvm.once(Back.BackItemPlan(cmds))
        end,
    })

    lower_module = pvm.phase("sem_to_back_module", {
        [Sem.SemModule] = function(self, layout_env)
            local cmds = {}
            for i = 1, #self.items do
                copy_cmds(one_item(self.items[i], layout_env).cmds, cmds)
            end
            cmds[#cmds + 1] = Back.BackCmdFinalizeModule
            return pvm.once(Back.BackProgram(cmds))
        end,
    })

    return {
        lower_scalar = lower_scalar,
        lower_stack_slot_spec = lower_stack_slot_spec,
        lower_binding_value = lower_binding_value,
        lower_binding_expr = lower_binding_expr,
        lower_sig_spec = lower_sig_spec,
        lower_expr = lower_expr,
        lower_stmt = lower_stmt,
        lower_func = lower_func,
        lower_item = lower_item,
        lower_module = lower_module,
    }
end

return M
