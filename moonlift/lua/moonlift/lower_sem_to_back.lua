package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local ffi = require("ffi")
ffi.cdef[[
int snprintf(char *str, size_t size, const char *format, ...);
long long strtoll(const char *nptr, char **endptr, int base);
unsigned long long strtoull(const char *nptr, char **endptr, int base);
]]

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
    local lower_const_agg_value_init_from_type
    local lower_const_value_data_init
    local lower_const_data_init
    local sem_const_eval
    local sem_const_stmt_eval
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

    local function one_const_value_data_init(node, data_id, offset, layout_env)
        return pvm.one(lower_const_value_data_init(node, data_id, offset, layout_env))
    end

    local function one_const_data_init(node, data_id, offset, layout_env, const_env, visiting)
        return pvm.one(lower_const_data_init(node, data_id, offset, layout_env, const_env, visiting))
    end

    local function one_const_eval(node, const_env, local_env, visiting)
        return pvm.one(sem_const_eval(node, const_env, local_env, visiting))
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

    local function one_item(node, layout_env, const_env)
        return pvm.one(lower_item(node, layout_env, const_env))
    end

    local function one_module(node, layout_env, const_env)
        return pvm.one(lower_module(node, layout_env, const_env))
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
            local addr = Back.BackValId("loop.slot.addr:" .. bindings[i].id)
            cmds[#cmds + 1] = Back.BackCmdStackAddr(addr, local_value_slot_id(bindings[i].id))
            cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(bindings[i].ty), addr, param_ids[i])
        end
    end

    local function emit_alias_for_index_binding(cmds, binding, value_id)
        local addr = Back.BackValId("loop.index.slot.addr:" .. binding.id)
        cmds[#cmds + 1] = Back.BackCmdStackAddr(addr, local_value_slot_id(binding.id))
        cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(binding.ty), addr, value_id)
    end

    local function loop_binding_value_args(values)
        local args = {}
        for i = 1, #values do
            args[i] = values[i]
        end
        return args
    end

    local function over_loop_current_args(index_value, carry_values)
        local args = { index_value }
        for i = 1, #carry_values do
            args[#args + 1] = carry_values[i]
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
        [Sem.SemBindLocalStoredValue] = function(self, path)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar immutable local '" .. self.name .. "' has no direct value form in Sem->Back; use address-based access")
            end
            local addr = Back.BackValId(path .. ".addr")
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, local_value_slot_id(self.id)),
                Back.BackCmdLoad(dst, ty, addr),
            }, dst, ty))
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

    local const_format_buf = ffi.new("char[96]")
    local INT_CTYPE = {
        [Sem.SemTI8] = "int8_t",
        [Sem.SemTI16] = "int16_t",
        [Sem.SemTI32] = "int32_t",
        [Sem.SemTI64] = "int64_t",
        [Sem.SemTU8] = "uint8_t",
        [Sem.SemTU16] = "uint16_t",
        [Sem.SemTU32] = "uint32_t",
        [Sem.SemTU64] = "uint64_t",
        [Sem.SemTIndex] = "uint64_t",
    }

    local function ensure_const_env(const_env)
        if const_env ~= nil then
            return const_env
        end
        return Sem.SemConstEnv({})
    end

    local function const_entry_key(module_name, item_name)
        if module_name == nil or module_name == "" then
            return item_name
        end
        return module_name .. "." .. item_name
    end

    local function const_binding_key(binding)
        return const_entry_key(binding.module_name, binding.item_name)
    end

    local function with_const_visiting(visiting, key)
        local out = {}
        if visiting ~= nil then
            for k, v in pairs(visiting) do
                out[k] = v
            end
        end
        out[key] = true
        return out
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

    local function int_ctype(ty)
        return INT_CTYPE[ty]
    end

    local function type_is_intlike(ty)
        return int_ctype(ty) ~= nil
    end

    local function type_is_float(ty)
        return ty == Sem.SemTF32 or ty == Sem.SemTF64
    end

    local parse_int_raw
    local const_value_ty
    local find_const_field_value
    local expect_const_bool
    local expect_const_intlike
    local expect_const_numeric_pair

    local const_ops = {
        unsigned_int_ctype = {
            [Sem.SemTI8] = "uint8_t",
            [Sem.SemTI16] = "uint16_t",
            [Sem.SemTI32] = "uint32_t",
            [Sem.SemTI64] = "uint64_t",
            [Sem.SemTU8] = "uint8_t",
            [Sem.SemTU16] = "uint16_t",
            [Sem.SemTU32] = "uint32_t",
            [Sem.SemTU64] = "uint64_t",
            [Sem.SemTIndex] = "uint64_t",
        },
        signed_int_ctype = {
            [Sem.SemTI8] = "int8_t",
            [Sem.SemTI16] = "int16_t",
            [Sem.SemTI32] = "int32_t",
            [Sem.SemTI64] = "int64_t",
            [Sem.SemTU8] = "int8_t",
            [Sem.SemTU16] = "int16_t",
            [Sem.SemTU32] = "int32_t",
            [Sem.SemTU64] = "int64_t",
            [Sem.SemTIndex] = "int64_t",
        },
        float_ctype = {
            [Sem.SemTF32] = "float",
            [Sem.SemTF64] = "double",
        },
        int_bit_width = {
            [Sem.SemTI8] = 8,
            [Sem.SemTI16] = 16,
            [Sem.SemTI32] = 32,
            [Sem.SemTI64] = 64,
            [Sem.SemTU8] = 8,
            [Sem.SemTU16] = 16,
            [Sem.SemTU32] = 32,
            [Sem.SemTU64] = 64,
            [Sem.SemTIndex] = 64,
        },
        signed_min_raw = {
            [Sem.SemTI8] = "-128",
            [Sem.SemTI16] = "-32768",
            [Sem.SemTI32] = "-2147483648",
            [Sem.SemTI64] = "-9223372036854775808",
        },
        signed_max_raw = {
            [Sem.SemTI8] = "127",
            [Sem.SemTI16] = "32767",
            [Sem.SemTI32] = "2147483647",
            [Sem.SemTI64] = "9223372036854775807",
        },
        unsigned_max_raw = {
            [Sem.SemTU8] = "255",
            [Sem.SemTU16] = "65535",
            [Sem.SemTU32] = "4294967295",
            [Sem.SemTU64] = "18446744073709551615",
            [Sem.SemTIndex] = "18446744073709551615",
        },
        u64_zero = ffi.new("uint64_t", 0),
        u64_two = ffi.new("uint64_t", 2),
    }

    local function type_is_signed_int(ty)
        return ty == Sem.SemTI8 or ty == Sem.SemTI16 or ty == Sem.SemTI32 or ty == Sem.SemTI64
    end

    const_ops.type_is_bool = function(ty)
        return ty == Sem.SemTBool
    end

    const_ops.unsigned_int_ctype_of = function(ty)
        return const_ops.unsigned_int_ctype[ty]
    end

    const_ops.signed_int_ctype_of = function(ty)
        return const_ops.signed_int_ctype[ty]
    end

    const_ops.float_ctype_of = function(ty)
        return const_ops.float_ctype[ty]
    end

    const_ops.int_bit_width_of = function(ty)
        return const_ops.int_bit_width[ty]
    end

    const_ops.scalar_bit_width_of = function(ty)
        if type_is_intlike(ty) then return const_ops.int_bit_width_of(ty) end
        if ty == Sem.SemTF32 then return 32 end
        if ty == Sem.SemTF64 then return 64 end
        return nil
    end

    const_ops.node_class = function(node)
        local mt = getmetatable(node)
        if mt ~= nil then
            return mt.__class
        end
        return nil
    end

    const_ops.ensure_local_env = function(local_env)
        if local_env ~= nil then
            return local_env
        end
        return Sem.SemConstLocalEnv({})
    end

    const_ops.same_local_binding = function(lhs, rhs)
        if const_ops.node_class(lhs) ~= const_ops.node_class(rhs) then
            return false
        end
        if lhs.id ~= nil or rhs.id ~= nil then
            return lhs.id ~= nil and rhs.id ~= nil and lhs.id == rhs.id
        end
        if lhs.index ~= nil or rhs.index ~= nil then
            return lhs.index ~= nil and rhs.index ~= nil and lhs.index == rhs.index and lhs.name == rhs.name
        end
        if lhs.symbol ~= nil or rhs.symbol ~= nil then
            return lhs.symbol ~= nil and rhs.symbol ~= nil and lhs.symbol == rhs.symbol
        end
        if lhs.module_name ~= nil or rhs.module_name ~= nil then
            return lhs.module_name ~= nil and rhs.module_name ~= nil and lhs.module_name == rhs.module_name and lhs.item_name == rhs.item_name
        end
        return lhs == rhs
    end

    const_ops.find_local_entry = function(local_env, binding)
        local env = const_ops.ensure_local_env(local_env)
        for i = #env.entries, 1, -1 do
            local entry = env.entries[i]
            if const_ops.same_local_binding(entry.binding, binding) then
                return entry
            end
        end
        return nil
    end

    const_ops.append_local_entry = function(local_env, binding, value)
        local env = const_ops.ensure_local_env(local_env)
        local entries = {}
        for i = 1, #env.entries do
            entries[i] = env.entries[i]
        end
        entries[#entries + 1] = Sem.SemConstLocalEntry(binding, value)
        return Sem.SemConstLocalEnv(entries)
    end

    const_ops.let_binding = function(stmt)
        return Sem.SemBindLocalStoredValue(stmt.id, stmt.name, stmt.ty)
    end

    const_ops.var_binding = function(stmt)
        return Sem.SemBindLocalCell(stmt.id, stmt.name, stmt.ty)
    end

    const_ops.scalar_eq = function(lhs, rhs, context)
        local lhs_ty = const_value_ty(lhs)
        local rhs_ty = const_value_ty(rhs)
        if lhs_ty ~= rhs_ty then
            error("sem_const_eval: " .. context .. " requires matching operand constant types")
        end
        if const_ops.type_is_bool(lhs_ty) then
            return expect_const_bool(lhs, context) == expect_const_bool(rhs, context)
        end
        if type_is_intlike(lhs_ty) then
            return parse_int_raw(lhs_ty, lhs.raw) == parse_int_raw(rhs_ty, rhs.raw)
        end
        if type_is_float(lhs_ty) then
            return tonumber(lhs.raw) == tonumber(rhs.raw)
        end
        if lhs.raw == nil and rhs.raw == nil and lhs.value == nil and rhs.value == nil and lhs.fields == nil and rhs.fields == nil and lhs.elems == nil and rhs.elems == nil then
            return true
        end
        error("sem_const_eval: " .. context .. " requires scalar comparable constants")
    end

    const_ops.stmt_fallthrough_env = function(result, context)
        local cls = const_ops.node_class(result)
        if cls == Sem.SemConstStmtFallsThrough then
            return result.local_env
        end
        if cls == Sem.SemConstStmtReturnVoid or cls == Sem.SemConstStmtReturnValue then
            error("sem_const_eval: " .. context .. " cannot return from constant data")
        end
        if cls == Sem.SemConstStmtBreak then
            error("sem_const_eval: " .. context .. " cannot break from constant data")
        end
        if cls == Sem.SemConstStmtContinue then
            error("sem_const_eval: " .. context .. " cannot continue from constant data")
        end
        error("sem_const_eval: unknown constant statement result")
    end

    const_ops.visible_bindings = function(local_env)
        local env = const_ops.ensure_local_env(local_env)
        local bindings = {}
        for i = 1, #env.entries do
            local binding = env.entries[i].binding
            local seen = false
            for j = 1, #bindings do
                if const_ops.same_local_binding(bindings[j], binding) then
                    seen = true
                    break
                end
            end
            if not seen then
                bindings[#bindings + 1] = binding
            end
        end
        return bindings
    end

    const_ops.project_env_to_bindings = function(local_env, bindings)
        local env = const_ops.ensure_local_env(local_env)
        local entries = {}
        for i = 1, #bindings do
            local entry = const_ops.find_local_entry(env, bindings[i])
            if entry ~= nil then
                entries[#entries + 1] = Sem.SemConstLocalEntry(bindings[i], entry.value)
            end
        end
        return Sem.SemConstLocalEnv(entries)
    end

    const_ops.project_env_to_base = function(local_env, base_env)
        return const_ops.project_env_to_bindings(local_env, const_ops.visible_bindings(base_env))
    end

    const_ops.project_stmt_result_to_bindings = function(result, bindings)
        local cls = const_ops.node_class(result)
        local projected_env = const_ops.project_env_to_bindings(result.local_env, bindings)
        if cls == Sem.SemConstStmtFallsThrough then
            return Sem.SemConstStmtFallsThrough(projected_env)
        end
        if cls == Sem.SemConstStmtReturnVoid then
            return Sem.SemConstStmtReturnVoid(projected_env)
        end
        if cls == Sem.SemConstStmtReturnValue then
            return Sem.SemConstStmtReturnValue(projected_env, result.value)
        end
        if cls == Sem.SemConstStmtBreak then
            return Sem.SemConstStmtBreak(projected_env)
        end
        if cls == Sem.SemConstStmtContinue then
            return Sem.SemConstStmtContinue(projected_env)
        end
        error("sem_const_eval: unknown constant statement result")
    end

    const_ops.loop_binding_as_binding = function(loop_binding)
        return Sem.SemBindLocalStoredValue(loop_binding.id, loop_binding.name, loop_binding.ty)
    end

    const_ops.with_loop_bindings = function(local_env, bindings, values)
        local env = const_ops.ensure_local_env(local_env)
        for i = 1, #bindings do
            env = const_ops.append_local_entry(env, bindings[i], values[i])
        end
        return env
    end

    const_ops.eval_loop_init_values = function(bindings, const_env, local_env, visiting)
        local values = {}
        for i = 1, #bindings do
            values[i] = one_const_eval(bindings[i].init, const_env, local_env, visiting)
            if const_value_ty(values[i]) ~= bindings[i].ty then
                error("sem_const_eval: loop init constant type mismatch")
            end
        end
        return values
    end

    const_ops.eval_loop_next_values = function(nexts, const_env, local_env, visiting)
        local values = {}
        for i = 1, #nexts do
            values[i] = one_const_eval(nexts[i].value, const_env, local_env, visiting)
            if const_value_ty(values[i]) ~= nexts[i].binding.ty then
                error("sem_const_eval: loop next constant type mismatch")
            end
        end
        return values
    end

    const_ops.loop_iteration_limit = 100000

    const_ops.eval_stmt_list = function(stmts, const_env, local_env, visiting)
        local env = const_ops.ensure_local_env(local_env)
        for i = 1, #stmts do
            local result = pvm.one(sem_const_stmt_eval(stmts[i], const_env, env, visiting))
            if const_ops.node_class(result) ~= Sem.SemConstStmtFallsThrough then
                return result
            end
            env = result.local_env
        end
        return Sem.SemConstStmtFallsThrough(env)
    end

    local function format_signed_i64(value)
        ffi.C.snprintf(const_format_buf, 96, "%lld", ffi.cast("long long", value))
        return ffi.string(const_format_buf)
    end

    local function format_unsigned_u64(value)
        ffi.C.snprintf(const_format_buf, 96, "%llu", ffi.cast("unsigned long long", value))
        return ffi.string(const_format_buf)
    end

    parse_int_raw = function(ty, raw)
        local ctype = int_ctype(ty)
        if ctype == nil then
            error("sem_const_eval: expected an integer-like type")
        end
        if type_is_signed_int(ty) then
            return ffi.cast(ctype, ffi.C.strtoll(raw, nil, 10))
        end
        return ffi.cast(ctype, ffi.C.strtoull(raw, nil, 10))
    end

    local function normalize_int(ty, value)
        return ffi.cast(int_ctype(ty), value)
    end

    local function int_raw(ty, value)
        local norm = normalize_int(ty, value)
        if type_is_signed_int(ty) then
            return format_signed_i64(ffi.cast("int64_t", norm))
        end
        return format_unsigned_u64(ffi.cast("uint64_t", norm))
    end

    local function float_raw(ty, value)
        if ty == Sem.SemTF32 then
            return string.format("%.9g", tonumber(ffi.new("float", value)))
        end
        return string.format("%.17g", tonumber(value))
    end

    local function const_int_value(ty, value)
        return Sem.SemConstInt(ty, int_raw(ty, value))
    end

    local function const_float_value(ty, value)
        return Sem.SemConstFloat(ty, float_raw(ty, value))
    end

    const_ops.const_int_value_from_unsigned = function(ty, value)
        return const_int_value(ty, ffi.cast(int_ctype(ty), ffi.cast(const_ops.unsigned_int_ctype_of(ty), value)))
    end

    const_ops.pow2_u64 = function(bits)
        local out = ffi.new("uint64_t", 1)
        for _ = 1, bits do
            out = out + out
        end
        return out
    end

    const_ops.signed_min_value = function(ty)
        return ffi.C.strtoll(const_ops.signed_min_raw[ty], nil, 10)
    end

    const_ops.signed_max_value = function(ty)
        return ffi.C.strtoll(const_ops.signed_max_raw[ty], nil, 10)
    end

    const_ops.unsigned_max_value = function(ty)
        return ffi.C.strtoull(const_ops.unsigned_max_raw[ty], nil, 10)
    end

    const_ops.integer_to_lua_number = function(ty, value)
        if type_is_signed_int(ty) then
            return tonumber(ffi.cast("int64_t", value))
        end
        return tonumber(ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), value)))
    end

    const_ops.const_zero_value = function(ty)
        if const_ops.type_is_bool(ty) then
            return Sem.SemConstBool(false)
        end
        if type_is_float(ty) then
            return const_float_value(ty, 0)
        end
        if type_is_intlike(ty) then
            return const_int_value(ty, 0)
        end
        error("sem_const_eval: no scalar zero value for this type")
    end

    const_ops.bitop_unsigned = function(width, lhs, rhs, mode)
        local a = ffi.cast("uint64_t", lhs)
        local b = ffi.cast("uint64_t", rhs)
        local out = ffi.new("uint64_t", 0)
        local place = ffi.new("uint64_t", 1)
        for _ = 1, width do
            local abit = a % const_ops.u64_two
            local bbit = b % const_ops.u64_two
            local include = false
            if mode == "and" then
                include = abit ~= const_ops.u64_zero and bbit ~= const_ops.u64_zero
            elseif mode == "or" then
                include = abit ~= const_ops.u64_zero or bbit ~= const_ops.u64_zero
            elseif mode == "xor" then
                include = (abit ~= const_ops.u64_zero) ~= (bbit ~= const_ops.u64_zero)
            else
                error("sem_const_eval: unknown bit operation '" .. tostring(mode) .. "'")
            end
            if include then
                out = out + place
            end
            a = a / const_ops.u64_two
            b = b / const_ops.u64_two
            place = place + place
        end
        return out
    end

    const_ops.shift_count_from_const = function(value, context)
        local ty, parsed = expect_const_intlike(value, context)
        local n = tonumber(ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), parsed)))
        if n == nil or n < 0 or n ~= math.floor(n) then
            error("sem_const_eval: " .. context .. " requires a finite non-negative shift count")
        end
        return n
    end

    const_ops.shl_unsigned = function(ty, lhs, count)
        local out = ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), lhs))
        for _ = 1, count do
            out = ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), out + out))
        end
        return out
    end

    const_ops.lshr_unsigned = function(ty, lhs, count)
        local out = ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), lhs))
        for _ = 1, count do
            out = out / const_ops.u64_two
        end
        return out
    end

    const_ops.ashr_unsigned = function(ty, lhs, count)
        local width = const_ops.int_bit_width_of(ty)
        local sign_bit = const_ops.pow2_u64(width - 1)
        local out = ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), lhs))
        for _ = 1, count do
            local sign = out >= sign_bit
            out = out / const_ops.u64_two
            if sign then
                out = out + sign_bit
            end
            out = ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), out))
        end
        return out
    end

    const_ops.scalar_cast_value = function(dest_ty, value, context)
        local src_ty = const_value_ty(value)
        if type_is_intlike(dest_ty) then
            if const_ops.type_is_bool(src_ty) then
                return const_int_value(dest_ty, value.value and 1 or 0)
            end
            if type_is_intlike(src_ty) then
                return const_int_value(dest_ty, parse_int_raw(src_ty, value.raw))
            end
            if type_is_float(src_ty) then
                return const_int_value(dest_ty, ffi.cast(int_ctype(dest_ty), tonumber(value.raw)))
            end
        elseif type_is_float(dest_ty) then
            if const_ops.type_is_bool(src_ty) then
                return const_float_value(dest_ty, value.value and 1 or 0)
            end
            if type_is_intlike(src_ty) then
                return const_float_value(dest_ty, const_ops.integer_to_lua_number(src_ty, parse_int_raw(src_ty, value.raw)))
            end
            if type_is_float(src_ty) then
                return const_float_value(dest_ty, tonumber(value.raw))
            end
        elseif const_ops.type_is_bool(dest_ty) then
            if const_ops.type_is_bool(src_ty) then
                return Sem.SemConstBool(value.value)
            end
            if type_is_intlike(src_ty) then
                return Sem.SemConstBool(parse_int_raw(src_ty, value.raw) ~= 0)
            end
            if type_is_float(src_ty) then
                return Sem.SemConstBool(tonumber(value.raw) ~= 0)
            end
        end
        error("sem_const_eval: " .. context .. " is not supported from '" .. tostring(src_ty) .. "' to '" .. tostring(dest_ty) .. "'")
    end

    const_ops.zext_const_value = function(dest_ty, value)
        local src_ty, parsed = expect_const_intlike(value, "zero-extend")
        if not type_is_intlike(dest_ty) then
            error("sem_const_eval: zero-extend requires an integer-like destination type")
        end
        return const_int_value(dest_ty, ffi.cast(int_ctype(dest_ty), ffi.cast(const_ops.unsigned_int_ctype_of(src_ty), parsed)))
    end

    const_ops.sext_const_value = function(dest_ty, value)
        local src_ty, parsed = expect_const_intlike(value, "sign-extend")
        if not type_is_intlike(dest_ty) then
            error("sem_const_eval: sign-extend requires an integer-like destination type")
        end
        return const_int_value(dest_ty, ffi.cast(int_ctype(dest_ty), ffi.cast(const_ops.signed_int_ctype_of(src_ty), parsed)))
    end

    const_ops.bitcast_const_value = function(dest_ty, value)
        local src_ty = const_value_ty(value)
        local src_bits = const_ops.scalar_bit_width_of(src_ty)
        local dst_bits = const_ops.scalar_bit_width_of(dest_ty)
        if src_bits == nil or dst_bits == nil or src_bits ~= dst_bits then
            error("sem_const_eval: bitcast requires source/destination scalar types with equal bit width")
        end
        if const_ops.type_is_bool(src_ty) or const_ops.type_is_bool(dest_ty) then
            error("sem_const_eval: bitcast does not currently support bool constants")
        end
        local src_storage_ctype
        local src_storage_value
        if type_is_intlike(src_ty) then
            src_storage_ctype = const_ops.unsigned_int_ctype_of(src_ty)
            src_storage_value = ffi.cast(src_storage_ctype, parse_int_raw(src_ty, value.raw))
        elseif type_is_float(src_ty) then
            src_storage_ctype = const_ops.float_ctype_of(src_ty)
            src_storage_value = tonumber(value.raw)
        else
            error("sem_const_eval: bitcast source must be an integer-like or float constant")
        end
        local buf = ffi.new(src_storage_ctype .. "[1]", src_storage_value)
        if type_is_intlike(dest_ty) then
            local raw_value = ffi.cast(const_ops.unsigned_int_ctype_of(dest_ty) .. "*", buf)[0]
            return const_ops.const_int_value_from_unsigned(dest_ty, raw_value)
        end
        if type_is_float(dest_ty) then
            local raw_value = ffi.cast(const_ops.float_ctype_of(dest_ty) .. "*", buf)[0]
            return const_float_value(dest_ty, raw_value)
        end
        error("sem_const_eval: bitcast destination must be an integer-like or float type")
    end

    const_ops.sat_cast_const_value = function(dest_ty, value)
        local src_ty = const_value_ty(value)
        if type_is_float(dest_ty) or const_ops.type_is_bool(dest_ty) then
            return const_ops.scalar_cast_value(dest_ty, value, "saturating cast")
        end
        if not type_is_intlike(dest_ty) then
            error("sem_const_eval: saturating cast requires a scalar destination type")
        end
        if const_ops.type_is_bool(src_ty) then
            return const_int_value(dest_ty, value.value and 1 or 0)
        end
        if type_is_float(src_ty) then
            local n = tonumber(value.raw)
            if n ~= n then
                return const_ops.const_zero_value(dest_ty)
            end
            if type_is_signed_int(dest_ty) then
                local min_n = tonumber(const_ops.signed_min_raw[dest_ty])
                local max_n = tonumber(const_ops.signed_max_raw[dest_ty])
                if n <= min_n then return const_int_value(dest_ty, const_ops.signed_min_value(dest_ty)) end
                if n >= max_n then return const_int_value(dest_ty, const_ops.signed_max_value(dest_ty)) end
            else
                local max_n = tonumber(const_ops.unsigned_max_raw[dest_ty])
                if n <= 0 then return const_ops.const_zero_value(dest_ty) end
                if n >= max_n then return const_int_value(dest_ty, const_ops.unsigned_max_value(dest_ty)) end
            end
            return const_int_value(dest_ty, ffi.cast(int_ctype(dest_ty), n))
        end
        if type_is_intlike(src_ty) then
            local parsed = parse_int_raw(src_ty, value.raw)
            if type_is_signed_int(src_ty) then
                local s = ffi.cast("int64_t", ffi.cast(const_ops.signed_int_ctype_of(src_ty), parsed))
                if type_is_signed_int(dest_ty) then
                    if s <= const_ops.signed_min_value(dest_ty) then return const_int_value(dest_ty, const_ops.signed_min_value(dest_ty)) end
                    if s >= const_ops.signed_max_value(dest_ty) then return const_int_value(dest_ty, const_ops.signed_max_value(dest_ty)) end
                    return const_int_value(dest_ty, s)
                end
                if s <= 0 then return const_ops.const_zero_value(dest_ty) end
                local u = ffi.cast("uint64_t", s)
                if u >= const_ops.unsigned_max_value(dest_ty) then return const_int_value(dest_ty, const_ops.unsigned_max_value(dest_ty)) end
                return const_int_value(dest_ty, u)
            end
            local u = ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(src_ty), parsed))
            if type_is_signed_int(dest_ty) then
                local max_u = ffi.cast("uint64_t", const_ops.signed_max_value(dest_ty))
                if u >= max_u then return const_int_value(dest_ty, const_ops.signed_max_value(dest_ty)) end
                return const_int_value(dest_ty, u)
            end
            if u >= const_ops.unsigned_max_value(dest_ty) then return const_int_value(dest_ty, const_ops.unsigned_max_value(dest_ty)) end
            return const_int_value(dest_ty, u)
        end
        error("sem_const_eval: saturating cast source must be bool/int/float")
    end

    const_value_ty = function(value)
        if value.ty ~= nil then
            return value.ty
        end
        if value.elem_ty ~= nil then
            return Sem.SemTArray(value.elem_ty, #value.elems)
        end
        return Sem.SemTBool
    end

    find_const_field_value = function(fields, field_name)
        for i = 1, #fields do
            if fields[i].name == field_name then
                return fields[i].value
            end
        end
        return nil
    end

    expect_const_bool = function(value, context)
        if value.value == nil or value.ty ~= nil or value.elem_ty ~= nil then
            error("sem_const_eval: " .. context .. " requires a bool constant")
        end
        return value.value
    end

    expect_const_intlike = function(value, context)
        local ty = const_value_ty(value)
        if value.raw == nil or not type_is_intlike(ty) then
            error("sem_const_eval: " .. context .. " requires an integer-like constant")
        end
        return ty, parse_int_raw(ty, value.raw)
    end

    expect_const_numeric_pair = function(lhs, rhs, context)
        local lhs_ty = const_value_ty(lhs)
        local rhs_ty = const_value_ty(rhs)
        if lhs_ty ~= rhs_ty then
            error("sem_const_eval: " .. context .. " requires matching operand constant types")
        end
        if lhs.raw == nil then
            error("sem_const_eval: " .. context .. " requires scalar numeric constants")
        end
        if type_is_intlike(lhs_ty) then
            return lhs_ty, "int", parse_int_raw(lhs_ty, lhs.raw), parse_int_raw(rhs_ty, rhs.raw)
        end
        if type_is_float(lhs_ty) then
            return lhs_ty, "float", tonumber(lhs.raw), tonumber(rhs.raw)
        end
        error("sem_const_eval: " .. context .. " requires scalar numeric constants")
    end

    sem_const_stmt_eval = pvm.phase("sem_const_stmt_eval", {
        [Sem.SemStmtLet] = function(self, const_env, local_env, visiting)
            local value = one_const_eval(self.init, const_env, local_env, visiting)
            if const_value_ty(value) ~= self.ty then
                error("sem_const_stmt_eval: let constant type mismatch")
            end
            return pvm.once(Sem.SemConstStmtFallsThrough(const_ops.append_local_entry(local_env, const_ops.let_binding(self), value)))
        end,
        [Sem.SemStmtVar] = function(self, const_env, local_env, visiting)
            local value = one_const_eval(self.init, const_env, local_env, visiting)
            if const_value_ty(value) ~= self.ty then
                error("sem_const_stmt_eval: var constant type mismatch")
            end
            return pvm.once(Sem.SemConstStmtFallsThrough(const_ops.append_local_entry(local_env, const_ops.var_binding(self), value)))
        end,
        [Sem.SemStmtSet] = function(self, const_env, local_env, visiting)
            if const_ops.node_class(self.binding) ~= Sem.SemBindLocalCell then
                error("sem_const_stmt_eval: set requires a mutable local const binding")
            end
            if const_ops.find_local_entry(local_env, self.binding) == nil then
                error("sem_const_stmt_eval: set target is not available in the current constant local env")
            end
            local value = one_const_eval(self.value, const_env, local_env, visiting)
            if const_value_ty(value) ~= self.binding.ty then
                error("sem_const_stmt_eval: set constant type mismatch")
            end
            return pvm.once(Sem.SemConstStmtFallsThrough(const_ops.append_local_entry(local_env, self.binding, value)))
        end,
        [Sem.SemStmtStore] = function()
            error("sem_const_stmt_eval: store statements are not supported during constant evaluation")
        end,
        [Sem.SemStmtExpr] = function(self, const_env, local_env, visiting)
            one_const_eval(self.expr, const_env, local_env, visiting)
            return pvm.once(Sem.SemConstStmtFallsThrough(const_ops.ensure_local_env(local_env)))
        end,
        [Sem.SemStmtIf] = function(self, const_env, local_env, visiting)
            local cond = one_const_eval(self.cond, const_env, local_env, visiting)
            if expect_const_bool(cond, "if statement condition") then
                return pvm.once(const_ops.eval_stmt_list(self.then_body, const_env, local_env, visiting))
            end
            return pvm.once(const_ops.eval_stmt_list(self.else_body, const_env, local_env, visiting))
        end,
        [Sem.SemStmtSwitch] = function(self, const_env, local_env, visiting)
            local value = one_const_eval(self.value, const_env, local_env, visiting)
            for i = 1, #self.arms do
                local key = one_const_eval(self.arms[i].key, const_env, local_env, visiting)
                if const_ops.scalar_eq(value, key, "switch statement") then
                    return pvm.once(const_ops.eval_stmt_list(self.arms[i].body, const_env, local_env, visiting))
                end
            end
            return pvm.once(const_ops.eval_stmt_list(self.default_body, const_env, local_env, visiting))
        end,
        [Sem.SemStmtAssert] = function(self, const_env, local_env, visiting)
            local cond = one_const_eval(self.cond, const_env, local_env, visiting)
            if not expect_const_bool(cond, "assert condition") then
                error("sem_const_stmt_eval: assertion failed during constant evaluation")
            end
            return pvm.once(Sem.SemConstStmtFallsThrough(const_ops.ensure_local_env(local_env)))
        end,
        [Sem.SemStmtReturnVoid] = function(self, const_env, local_env)
            return pvm.once(Sem.SemConstStmtReturnVoid(const_ops.ensure_local_env(local_env)))
        end,
        [Sem.SemStmtReturnValue] = function(self, const_env, local_env, visiting)
            return pvm.once(Sem.SemConstStmtReturnValue(
                const_ops.ensure_local_env(local_env),
                one_const_eval(self.value, const_env, local_env, visiting)
            ))
        end,
        [Sem.SemStmtBreak] = function(self, const_env, local_env)
            return pvm.once(Sem.SemConstStmtBreak(const_ops.ensure_local_env(local_env)))
        end,
        [Sem.SemStmtContinue] = function(self, const_env, local_env)
            return pvm.once(Sem.SemConstStmtContinue(const_ops.ensure_local_env(local_env)))
        end,
        [Sem.SemStmtLoop] = function(self, const_env, local_env, visiting)
            return const_ops.sem_const_loop_stmt_eval(self.loop, const_env, local_env, visiting)
        end,
    })

    const_ops.sem_const_over_loop_start = pvm.phase("sem_const_over_loop_start", {
        [Sem.SemDomainRange] = function(self, index_ty)
            return pvm.once(const_int_value(index_ty, 0))
        end,
        [Sem.SemDomainRange2] = function(self, index_ty, const_env, local_env, visiting)
            local start = one_const_eval(self.start, const_env, local_env, visiting)
            if const_value_ty(start) ~= index_ty then
                error("sem_const_eval: over-loop start constant type mismatch")
            end
            return pvm.once(start)
        end,
        [Sem.SemDomainBoundedValue] = function()
            error("sem_const_eval: bounded-value over loops are not supported during constant evaluation")
        end,
        [Sem.SemDomainZipEq] = function()
            error("sem_const_eval: zip-eq over loops are not supported during constant evaluation")
        end,
    })

    const_ops.sem_const_over_loop_stop = pvm.phase("sem_const_over_loop_stop", {
        [Sem.SemDomainRange] = function(self, index_ty, const_env, local_env, visiting)
            local stop = one_const_eval(self.stop, const_env, local_env, visiting)
            if const_value_ty(stop) ~= index_ty then
                error("sem_const_eval: over-loop stop constant type mismatch")
            end
            return pvm.once(stop)
        end,
        [Sem.SemDomainRange2] = function(self, index_ty, const_env, local_env, visiting)
            local stop = one_const_eval(self.stop, const_env, local_env, visiting)
            if const_value_ty(stop) ~= index_ty then
                error("sem_const_eval: over-loop stop constant type mismatch")
            end
            return pvm.once(stop)
        end,
        [Sem.SemDomainBoundedValue] = function()
            error("sem_const_eval: bounded-value over loops are not supported during constant evaluation")
        end,
        [Sem.SemDomainZipEq] = function()
            error("sem_const_eval: zip-eq over loops are not supported during constant evaluation")
        end,
    })

    const_ops.sem_const_loop_stmt_eval = pvm.phase("sem_const_loop_stmt_eval", {
        [Sem.SemLoopWhileStmt] = function(self, const_env, local_env, visiting)
            local outer_env = const_ops.ensure_local_env(local_env)
            local outer_bindings = const_ops.visible_bindings(outer_env)
            local loop_bindings = {}
            for i = 1, #self.vars do
                loop_bindings[i] = const_ops.loop_binding_as_binding(self.vars[i])
            end
            local current_outer = outer_env
            local current_values = const_ops.eval_loop_init_values(self.vars, const_env, outer_env, visiting)
            local iterations = 0
            while true do
                iterations = iterations + 1
                if iterations > const_ops.loop_iteration_limit then
                    error("sem_const_eval: exceeded constant loop iteration limit")
                end
                local loop_env = const_ops.with_loop_bindings(current_outer, loop_bindings, current_values)
                local cond = one_const_eval(self.cond, const_env, loop_env, visiting)
                if not expect_const_bool(cond, "while loop condition") then
                    return pvm.once(Sem.SemConstStmtFallsThrough(current_outer))
                end
                local body_result = const_ops.eval_stmt_list(self.body, const_env, loop_env, visiting)
                local cls = const_ops.node_class(body_result)
                if cls == Sem.SemConstStmtFallsThrough or cls == Sem.SemConstStmtContinue then
                    current_outer = const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)
                    current_values = const_ops.eval_loop_next_values(self.next, const_env, body_result.local_env, visiting)
                elseif cls == Sem.SemConstStmtBreak then
                    return pvm.once(Sem.SemConstStmtFallsThrough(const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)))
                else
                    return pvm.once(const_ops.project_stmt_result_to_bindings(body_result, outer_bindings))
                end
            end
        end,
        [Sem.SemLoopOverStmt] = function(self, const_env, local_env, visiting)
            local outer_env = const_ops.ensure_local_env(local_env)
            local outer_bindings = const_ops.visible_bindings(outer_env)
            local current_outer = outer_env
            local carry_bindings = {}
            for i = 1, #self.carries do
                carry_bindings[i] = const_ops.loop_binding_as_binding(self.carries[i])
            end
            local current_values = const_ops.eval_loop_init_values(self.carries, const_env, outer_env, visiting)
            local index_ty = self.index_binding.ty
            local current_index = pvm.one(const_ops.sem_const_over_loop_start(self.domain, index_ty, const_env, outer_env, visiting))
            local iterations = 0
            while true do
                iterations = iterations + 1
                if iterations > const_ops.loop_iteration_limit then
                    error("sem_const_eval: exceeded constant loop iteration limit")
                end
                local loop_env = const_ops.with_loop_bindings(current_outer, carry_bindings, current_values)
                loop_env = const_ops.append_local_entry(loop_env, self.index_binding, current_index)
                local stop = pvm.one(const_ops.sem_const_over_loop_stop(self.domain, index_ty, const_env, loop_env, visiting))
                if parse_int_raw(index_ty, current_index.raw) >= parse_int_raw(index_ty, stop.raw) then
                    return pvm.once(Sem.SemConstStmtFallsThrough(current_outer))
                end
                local body_result = const_ops.eval_stmt_list(self.body, const_env, loop_env, visiting)
                local cls = const_ops.node_class(body_result)
                if cls == Sem.SemConstStmtFallsThrough or cls == Sem.SemConstStmtContinue then
                    current_outer = const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)
                    current_values = const_ops.eval_loop_next_values(self.next, const_env, body_result.local_env, visiting)
                    current_index = const_int_value(index_ty, parse_int_raw(index_ty, current_index.raw) + 1)
                elseif cls == Sem.SemConstStmtBreak then
                    return pvm.once(Sem.SemConstStmtFallsThrough(const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)))
                else
                    return pvm.once(const_ops.project_stmt_result_to_bindings(body_result, outer_bindings))
                end
            end
        end,
        [Sem.SemLoopWhileExpr] = function()
            error("sem_const_loop_stmt_eval: expected stmt loop, got expr loop")
        end,
        [Sem.SemLoopOverExpr] = function()
            error("sem_const_loop_stmt_eval: expected stmt loop, got expr loop")
        end,
    })

    const_ops.sem_const_loop_expr_eval = pvm.phase("sem_const_loop_expr_eval", {
        [Sem.SemLoopWhileExpr] = function(self, const_env, local_env, visiting)
            local outer_env = const_ops.ensure_local_env(local_env)
            local outer_bindings = const_ops.visible_bindings(outer_env)
            local loop_bindings = {}
            for i = 1, #self.vars do
                loop_bindings[i] = const_ops.loop_binding_as_binding(self.vars[i])
            end
            local current_outer = outer_env
            local current_values = const_ops.eval_loop_init_values(self.vars, const_env, outer_env, visiting)
            local iterations = 0
            while true do
                iterations = iterations + 1
                if iterations > const_ops.loop_iteration_limit then
                    error("sem_const_eval: exceeded constant loop iteration limit")
                end
                local loop_env = const_ops.with_loop_bindings(current_outer, loop_bindings, current_values)
                local cond = one_const_eval(self.cond, const_env, loop_env, visiting)
                if not expect_const_bool(cond, "while loop condition") then
                    return pvm.once(one_const_eval(self.result, const_env, loop_env, visiting))
                end
                local body_result = const_ops.eval_stmt_list(self.body, const_env, loop_env, visiting)
                local cls = const_ops.node_class(body_result)
                if cls == Sem.SemConstStmtFallsThrough or cls == Sem.SemConstStmtContinue then
                    current_outer = const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)
                    current_values = const_ops.eval_loop_next_values(self.next, const_env, body_result.local_env, visiting)
                elseif cls == Sem.SemConstStmtBreak then
                    local exit_outer = const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)
                    local exit_env = const_ops.with_loop_bindings(exit_outer, loop_bindings, current_values)
                    return pvm.once(one_const_eval(self.result, const_env, exit_env, visiting))
                else
                    error("sem_const_eval: loop constants cannot return from constant data")
                end
            end
        end,
        [Sem.SemLoopOverExpr] = function(self, const_env, local_env, visiting)
            local outer_env = const_ops.ensure_local_env(local_env)
            local outer_bindings = const_ops.visible_bindings(outer_env)
            local current_outer = outer_env
            local carry_bindings = {}
            for i = 1, #self.carries do
                carry_bindings[i] = const_ops.loop_binding_as_binding(self.carries[i])
            end
            local current_values = const_ops.eval_loop_init_values(self.carries, const_env, outer_env, visiting)
            local index_ty = self.index_binding.ty
            local current_index = pvm.one(const_ops.sem_const_over_loop_start(self.domain, index_ty, const_env, outer_env, visiting))
            local iterations = 0
            while true do
                iterations = iterations + 1
                if iterations > const_ops.loop_iteration_limit then
                    error("sem_const_eval: exceeded constant loop iteration limit")
                end
                local loop_env = const_ops.with_loop_bindings(current_outer, carry_bindings, current_values)
                loop_env = const_ops.append_local_entry(loop_env, self.index_binding, current_index)
                local stop = pvm.one(const_ops.sem_const_over_loop_stop(self.domain, index_ty, const_env, loop_env, visiting))
                if parse_int_raw(index_ty, current_index.raw) >= parse_int_raw(index_ty, stop.raw) then
                    return pvm.once(one_const_eval(self.result, const_env, loop_env, visiting))
                end
                local body_result = const_ops.eval_stmt_list(self.body, const_env, loop_env, visiting)
                local cls = const_ops.node_class(body_result)
                if cls == Sem.SemConstStmtFallsThrough or cls == Sem.SemConstStmtContinue then
                    current_outer = const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)
                    current_values = const_ops.eval_loop_next_values(self.next, const_env, body_result.local_env, visiting)
                    current_index = const_int_value(index_ty, parse_int_raw(index_ty, current_index.raw) + 1)
                elseif cls == Sem.SemConstStmtBreak then
                    local exit_outer = const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)
                    local exit_env = const_ops.with_loop_bindings(exit_outer, carry_bindings, current_values)
                    exit_env = const_ops.append_local_entry(exit_env, self.index_binding, current_index)
                    return pvm.once(one_const_eval(self.result, const_env, exit_env, visiting))
                else
                    error("sem_const_eval: loop constants cannot return from constant data")
                end
            end
        end,
        [Sem.SemLoopWhileStmt] = function()
            error("sem_const_loop_expr_eval: expected expr loop, got stmt loop")
        end,
        [Sem.SemLoopOverStmt] = function()
            error("sem_const_loop_expr_eval: expected expr loop, got stmt loop")
        end,
    })

    sem_const_eval = pvm.phase("sem_const_eval", {
        [Sem.SemExprConstInt] = function(self)
            return pvm.once(Sem.SemConstInt(self.ty, self.raw))
        end,
        [Sem.SemExprConstFloat] = function(self)
            return pvm.once(Sem.SemConstFloat(self.ty, self.raw))
        end,
        [Sem.SemExprConstBool] = function(self)
            return pvm.once(Sem.SemConstBool(self.value))
        end,
        [Sem.SemExprNil] = function(self)
            return pvm.once(Sem.SemConstNil(self.ty))
        end,
        [Sem.SemExprBinding] = function(self, const_env, local_env, visiting)
            local binding = self.binding
            local local_entry = const_ops.find_local_entry(local_env, binding)
            if local_entry ~= nil then
                if const_value_ty(local_entry.value) ~= binding.ty then
                    error("sem_const_eval: local const binding '" .. binding.name .. "' has type drift during const evaluation")
                end
                return pvm.once(local_entry.value)
            end
            if binding.module_name == nil or binding.item_name == nil then
                error("sem_const_eval: constant data cannot capture runtime bindings")
            end
            local key = const_binding_key(binding)
            if visiting ~= nil and visiting[key] then
                error("sem_const_eval: cyclic const dependency at '" .. key .. "'")
            end
            local entry = find_const_entry(const_env, binding.module_name, binding.item_name)
            if entry == nil then
                error("sem_const_eval: unknown const binding '" .. key .. "'")
            end
            if entry.ty ~= binding.ty then
                error("sem_const_eval: const binding '" .. key .. "' has type drift during const evaluation")
            end
            return pvm.once(one_const_eval(entry.value, const_env, nil, with_const_visiting(visiting, key)))
        end,
        [Sem.SemExprNeg] = function(self, const_env, local_env, visiting)
            local value = one_const_eval(self.value, const_env, local_env, visiting)
            local ty = const_value_ty(value)
            if ty ~= self.ty then
                error("sem_const_eval: neg constant type mismatch")
            end
            if type_is_intlike(ty) then
                return pvm.once(const_int_value(ty, -parse_int_raw(ty, value.raw)))
            end
            if type_is_float(ty) then
                return pvm.once(const_float_value(ty, -tonumber(value.raw)))
            end
            error("sem_const_eval: neg requires an integer-like or float constant")
        end,
        [Sem.SemExprNot] = function(self, const_env, local_env, visiting)
            local value = one_const_eval(self.value, const_env, local_env, visiting)
            return pvm.once(Sem.SemConstBool(not expect_const_bool(value, "logical not")))
        end,
        [Sem.SemExprBNot] = function(self, const_env, local_env, visiting)
            local value = one_const_eval(self.value, const_env, local_env, visiting)
            local ty, parsed = expect_const_intlike(value, "bit-not")
            if ty ~= self.ty then
                error("sem_const_eval: bit-not constant type mismatch")
            end
            return pvm.once(const_int_value(ty, -parsed - 1))
        end,
        [Sem.SemExprAdd] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, kind, l, r = expect_const_numeric_pair(lhs, rhs, "add")
            if ty ~= self.ty then error("sem_const_eval: add constant type mismatch") end
            if kind == "int" then return pvm.once(const_int_value(ty, l + r)) end
            return pvm.once(const_float_value(ty, l + r))
        end,
        [Sem.SemExprSub] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, kind, l, r = expect_const_numeric_pair(lhs, rhs, "sub")
            if ty ~= self.ty then error("sem_const_eval: sub constant type mismatch") end
            if kind == "int" then return pvm.once(const_int_value(ty, l - r)) end
            return pvm.once(const_float_value(ty, l - r))
        end,
        [Sem.SemExprMul] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, kind, l, r = expect_const_numeric_pair(lhs, rhs, "mul")
            if ty ~= self.ty then error("sem_const_eval: mul constant type mismatch") end
            if kind == "int" then return pvm.once(const_int_value(ty, l * r)) end
            return pvm.once(const_float_value(ty, l * r))
        end,
        [Sem.SemExprDiv] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, kind, l, r = expect_const_numeric_pair(lhs, rhs, "div")
            if ty ~= self.ty then error("sem_const_eval: div constant type mismatch") end
            if kind == "int" then
                if r == 0 then error("sem_const_eval: division by zero in integer constant") end
                return pvm.once(const_int_value(ty, l / r))
            end
            if r == 0 then error("sem_const_eval: division by zero in float constant") end
            return pvm.once(const_float_value(ty, l / r))
        end,
        [Sem.SemExprRem] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, kind, l, r = expect_const_numeric_pair(lhs, rhs, "rem")
            if ty ~= self.ty then error("sem_const_eval: rem constant type mismatch") end
            if kind == "int" then
                if r == 0 then error("sem_const_eval: remainder by zero in integer constant") end
                return pvm.once(const_int_value(ty, l % r))
            end
            if r == 0 then error("sem_const_eval: remainder by zero in float constant") end
            return pvm.once(const_float_value(ty, l % r))
        end,
        [Sem.SemExprEq] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            return pvm.once(Sem.SemConstBool(const_ops.scalar_eq(lhs, rhs, "eq")))
        end,
        [Sem.SemExprNe] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            return pvm.once(Sem.SemConstBool(not const_ops.scalar_eq(lhs, rhs, "ne")))
        end,
        [Sem.SemExprLt] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, kind, l, r = expect_const_numeric_pair(lhs, rhs, "lt")
            if ty == nil then error("sem_const_eval: lt requires scalar numeric constants") end
            return pvm.once(Sem.SemConstBool(l < r))
        end,
        [Sem.SemExprLe] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, kind, l, r = expect_const_numeric_pair(lhs, rhs, "le")
            if ty == nil then error("sem_const_eval: le requires scalar numeric constants") end
            return pvm.once(Sem.SemConstBool(l <= r))
        end,
        [Sem.SemExprGt] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, kind, l, r = expect_const_numeric_pair(lhs, rhs, "gt")
            if ty == nil then error("sem_const_eval: gt requires scalar numeric constants") end
            return pvm.once(Sem.SemConstBool(l > r))
        end,
        [Sem.SemExprGe] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, kind, l, r = expect_const_numeric_pair(lhs, rhs, "ge")
            if ty == nil then error("sem_const_eval: ge requires scalar numeric constants") end
            return pvm.once(Sem.SemConstBool(l >= r))
        end,
        [Sem.SemExprAnd] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            if not expect_const_bool(lhs, "and lhs") then
                return pvm.once(Sem.SemConstBool(false))
            end
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            return pvm.once(Sem.SemConstBool(expect_const_bool(rhs, "and rhs")))
        end,
        [Sem.SemExprOr] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            if expect_const_bool(lhs, "or lhs") then
                return pvm.once(Sem.SemConstBool(true))
            end
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            return pvm.once(Sem.SemConstBool(expect_const_bool(rhs, "or rhs")))
        end,
        [Sem.SemExprBitAnd] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, l = expect_const_intlike(lhs, "bitand")
            local rhs_ty, r = expect_const_intlike(rhs, "bitand")
            if ty ~= rhs_ty or ty ~= self.ty then
                error("sem_const_eval: bitand constant type mismatch")
            end
            local bits = const_ops.int_bit_width_of(ty)
            local lu = ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), l))
            local ru = ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), r))
            return pvm.once(const_ops.const_int_value_from_unsigned(ty, const_ops.bitop_unsigned(bits, lu, ru, "and")))
        end,
        [Sem.SemExprBitOr] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, l = expect_const_intlike(lhs, "bitor")
            local rhs_ty, r = expect_const_intlike(rhs, "bitor")
            if ty ~= rhs_ty or ty ~= self.ty then
                error("sem_const_eval: bitor constant type mismatch")
            end
            local bits = const_ops.int_bit_width_of(ty)
            local lu = ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), l))
            local ru = ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), r))
            return pvm.once(const_ops.const_int_value_from_unsigned(ty, const_ops.bitop_unsigned(bits, lu, ru, "or")))
        end,
        [Sem.SemExprBitXor] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, l = expect_const_intlike(lhs, "bitxor")
            local rhs_ty, r = expect_const_intlike(rhs, "bitxor")
            if ty ~= rhs_ty or ty ~= self.ty then
                error("sem_const_eval: bitxor constant type mismatch")
            end
            local bits = const_ops.int_bit_width_of(ty)
            local lu = ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), l))
            local ru = ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), r))
            return pvm.once(const_ops.const_int_value_from_unsigned(ty, const_ops.bitop_unsigned(bits, lu, ru, "xor")))
        end,
        [Sem.SemExprShl] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, l = expect_const_intlike(lhs, "shift-left")
            if ty ~= self.ty then
                error("sem_const_eval: shift-left constant type mismatch")
            end
            local count = const_ops.shift_count_from_const(rhs, "shift-left")
            return pvm.once(const_ops.const_int_value_from_unsigned(ty, const_ops.shl_unsigned(ty, l, count)))
        end,
        [Sem.SemExprLShr] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, l = expect_const_intlike(lhs, "logical shift-right")
            if ty ~= self.ty then
                error("sem_const_eval: logical shift-right constant type mismatch")
            end
            local count = const_ops.shift_count_from_const(rhs, "logical shift-right")
            return pvm.once(const_ops.const_int_value_from_unsigned(ty, const_ops.lshr_unsigned(ty, l, count)))
        end,
        [Sem.SemExprAShr] = function(self, const_env, local_env, visiting)
            local lhs = one_const_eval(self.lhs, const_env, local_env, visiting)
            local rhs = one_const_eval(self.rhs, const_env, local_env, visiting)
            local ty, l = expect_const_intlike(lhs, "arithmetic shift-right")
            if ty ~= self.ty then
                error("sem_const_eval: arithmetic shift-right constant type mismatch")
            end
            local count = const_ops.shift_count_from_const(rhs, "arithmetic shift-right")
            return pvm.once(const_ops.const_int_value_from_unsigned(ty, const_ops.ashr_unsigned(ty, l, count)))
        end,
        [Sem.SemExprCastTo] = function(self, const_env, local_env, visiting)
            return pvm.once(const_ops.scalar_cast_value(self.ty, one_const_eval(self.value, const_env, local_env, visiting), "cast"))
        end,
        [Sem.SemExprTruncTo] = function(self, const_env, local_env, visiting)
            return pvm.once(const_ops.scalar_cast_value(self.ty, one_const_eval(self.value, const_env, local_env, visiting), "truncation"))
        end,
        [Sem.SemExprZExtTo] = function(self, const_env, local_env, visiting)
            return pvm.once(const_ops.zext_const_value(self.ty, one_const_eval(self.value, const_env, local_env, visiting)))
        end,
        [Sem.SemExprSExtTo] = function(self, const_env, local_env, visiting)
            return pvm.once(const_ops.sext_const_value(self.ty, one_const_eval(self.value, const_env, local_env, visiting)))
        end,
        [Sem.SemExprBitcastTo] = function(self, const_env, local_env, visiting)
            return pvm.once(const_ops.bitcast_const_value(self.ty, one_const_eval(self.value, const_env, local_env, visiting)))
        end,
        [Sem.SemExprSatCastTo] = function(self, const_env, local_env, visiting)
            return pvm.once(const_ops.sat_cast_const_value(self.ty, one_const_eval(self.value, const_env, local_env, visiting)))
        end,
        [Sem.SemExprSelect] = function(self, const_env, local_env, visiting)
            local cond = one_const_eval(self.cond, const_env, local_env, visiting)
            if expect_const_bool(cond, "select condition") then
                return pvm.once(one_const_eval(self.then_value, const_env, local_env, visiting))
            end
            return pvm.once(one_const_eval(self.else_value, const_env, local_env, visiting))
        end,
        [Sem.SemExprIndex] = function(self, const_env, local_env, visiting)
            local base = one_const_eval(self.base, const_env, local_env, visiting)
            if base.elems == nil then
                error("sem_const_eval: index requires an array constant base")
            end
            local index = one_const_eval(self.index, const_env, local_env, visiting)
            local index_ty, parsed = expect_const_intlike(index, "index")
            local n = tonumber(parsed)
            if n == nil or n < 0 or n ~= math.floor(n) then
                error("sem_const_eval: array constant index must be a non-negative integer")
            end
            local pos = n + 1
            if pos < 1 or pos > #base.elems then
                error("sem_const_eval: array constant index out of bounds")
            end
            return pvm.once(base.elems[pos])
        end,
        [Sem.SemExprField] = function(self, const_env, local_env, visiting)
            local base = one_const_eval(self.base, const_env, local_env, visiting)
            if base.fields == nil then
                error("sem_const_eval: field projection requires an aggregate constant base")
            end
            local value = find_const_field_value(base.fields, self.field.field_name)
            if value == nil then
                error("sem_const_eval: missing field '" .. self.field.field_name .. "' in aggregate constant")
            end
            return pvm.once(value)
        end,
        [Sem.SemExprAgg] = function(self, const_env, local_env, visiting)
            local fields = {}
            for i = 1, #self.fields do
                fields[i] = Sem.SemConstFieldValue(self.fields[i].name, one_const_eval(self.fields[i].value, const_env, local_env, visiting))
            end
            return pvm.once(Sem.SemConstAgg(self.ty, fields))
        end,
        [Sem.SemExprArrayLit] = function(self, const_env, local_env, visiting)
            local elems = {}
            for i = 1, #self.elems do
                elems[i] = one_const_eval(self.elems[i], const_env, local_env, visiting)
            end
            return pvm.once(Sem.SemConstArray(self.elem_ty, elems))
        end,
        [Sem.SemExprBlock] = function(self, const_env, local_env, visiting)
            local result = const_ops.eval_stmt_list(self.stmts, const_env, local_env, visiting)
            local block_env = const_ops.stmt_fallthrough_env(result, "block constant")
            local value = one_const_eval(self.result, const_env, block_env, visiting)
            if const_value_ty(value) ~= self.ty then
                error("sem_const_eval: block constant type mismatch")
            end
            return pvm.once(value)
        end,
        [Sem.SemExprIf] = function(self, const_env, local_env, visiting)
            local cond = one_const_eval(self.cond, const_env, local_env, visiting)
            if expect_const_bool(cond, "if condition") then
                return pvm.once(one_const_eval(self.then_expr, const_env, local_env, visiting))
            end
            return pvm.once(one_const_eval(self.else_expr, const_env, local_env, visiting))
        end,
        [Sem.SemExprSwitch] = function(self, const_env, local_env, visiting)
            local value = one_const_eval(self.value, const_env, local_env, visiting)
            for i = 1, #self.arms do
                local key = one_const_eval(self.arms[i].key, const_env, local_env, visiting)
                if const_ops.scalar_eq(value, key, "switch expression") then
                    local arm_result = const_ops.eval_stmt_list(self.arms[i].body, const_env, local_env, visiting)
                    local arm_env = const_ops.stmt_fallthrough_env(arm_result, "switch constant arm")
                    local out = one_const_eval(self.arms[i].result, const_env, arm_env, visiting)
                    if const_value_ty(out) ~= self.ty then
                        error("sem_const_eval: switch constant type mismatch")
                    end
                    return pvm.once(out)
                end
            end
            local default_result = one_const_eval(self.default_expr, const_env, local_env, visiting)
            if const_value_ty(default_result) ~= self.ty then
                error("sem_const_eval: switch constant type mismatch")
            end
            return pvm.once(default_result)
        end,
        [Sem.SemExprIndexAddr] = function() error("sem_const_eval: address constants are not supported") end,
        [Sem.SemExprFieldAddr] = function() error("sem_const_eval: address constants are not supported") end,
        [Sem.SemExprLoad] = function() error("sem_const_eval: load constants are not supported") end,
        [Sem.SemExprIntrinsicCall] = function() error("sem_const_eval: intrinsic-call constants are not supported") end,
        [Sem.SemExprCall] = function() error("sem_const_eval: call constants are not supported") end,
        [Sem.SemExprLoop] = function(self, const_env, local_env, visiting)
            local value = pvm.one(const_ops.sem_const_loop_expr_eval(self.loop, const_env, local_env, visiting))
            if const_value_ty(value) ~= self.ty then
                error("sem_const_eval: loop constant type mismatch")
            end
            return pvm.once(value)
        end,
        [Sem.SemExprRef] = function() error("sem_const_eval: ref constants are not supported") end,
        [Sem.SemExprDeref] = function() error("sem_const_eval: deref constants are not supported") end,
    })

    lower_const_agg_value_init_from_type = pvm.phase("sem_to_back_const_agg_value_init_from_type", {
        [Sem.SemTNamed] = function(self, value, data_id, offset, layout_env)
            local layout = require_named_layout(layout_env, self.module_name, self.type_name)
            local cmds = {
                Back.BackCmdDataInitZero(data_id, offset, layout.size),
            }
            for i = 1, #layout.fields do
                local field = layout.fields[i]
                local field_value = find_const_field_value(value.fields, field.field_name)
                if field_value == nil then
                    error("sem_to_back_const_data_init: missing field '" .. field.field_name .. "' in aggregate constant for '" .. const_data_key(self.module_name, self.type_name) .. "'")
                end
                copy_cmds(one_const_value_data_init(field_value, data_id, offset + field.offset, layout_env), cmds)
            end
            return pvm.once(cmds)
        end,
        [Sem.SemTArray] = function()
            error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type, not SemTArray")
        end,
        [Sem.SemTVoid] = function() error("sem_to_back_const_data_init: cannot build a void constant object") end,
        [Sem.SemTBool] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTI8] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTI16] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTI32] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTI64] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTU8] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTU16] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTU32] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTU64] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTF32] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTF64] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTPtr] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTIndex] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTPtrTo] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTSlice] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
        [Sem.SemTFunc] = function() error("sem_to_back_const_data_init: aggregate constant object requires a named aggregate type") end,
    })

    lower_const_value_data_init = pvm.phase("sem_to_back_const_value_data_init", {
        [Sem.SemConstInt] = function(self, data_id, offset)
            return pvm.once({ Back.BackCmdDataInitInt(data_id, offset, one_scalar(self.ty), self.raw) })
        end,
        [Sem.SemConstFloat] = function(self, data_id, offset)
            return pvm.once({ Back.BackCmdDataInitFloat(data_id, offset, one_scalar(self.ty), self.raw) })
        end,
        [Sem.SemConstBool] = function(self, data_id, offset)
            return pvm.once({ Back.BackCmdDataInitBool(data_id, offset, self.value) })
        end,
        [Sem.SemConstNil] = function(self, data_id, offset, layout_env)
            return pvm.once({ Back.BackCmdDataInitZero(data_id, offset, one_type_mem_size(self.ty, layout_env)) })
        end,
        [Sem.SemConstAgg] = function(self, data_id, offset, layout_env)
            return pvm.once(pvm.one(lower_const_agg_value_init_from_type(self.ty, self, data_id, offset, layout_env)))
        end,
        [Sem.SemConstArray] = function(self, data_id, offset, layout_env)
            local elem_size = one_type_mem_size(self.elem_ty, layout_env)
            local cmds = {}
            for i = 1, #self.elems do
                copy_cmds(one_const_value_data_init(self.elems[i], data_id, offset + ((i - 1) * elem_size), layout_env), cmds)
            end
            return pvm.once(cmds)
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

    local function delegate_const_data_init()
        return function(self, data_id, offset, layout_env, const_env, visiting)
            return pvm.once(one_const_value_data_init(one_const_eval(self, const_env, nil, visiting), data_id, offset, layout_env))
        end
    end

    lower_const_data_init = pvm.phase("sem_to_back_const_data_init", {
        [Sem.SemExprConstInt] = delegate_const_data_init(),
        [Sem.SemExprConstFloat] = delegate_const_data_init(),
        [Sem.SemExprConstBool] = delegate_const_data_init(),
        [Sem.SemExprNil] = delegate_const_data_init(),
        [Sem.SemExprBinding] = delegate_const_data_init(),
        [Sem.SemExprNeg] = delegate_const_data_init(),
        [Sem.SemExprNot] = delegate_const_data_init(),
        [Sem.SemExprBNot] = delegate_const_data_init(),
        [Sem.SemExprRef] = delegate_const_data_init(),
        [Sem.SemExprDeref] = delegate_const_data_init(),
        [Sem.SemExprAdd] = delegate_const_data_init(),
        [Sem.SemExprSub] = delegate_const_data_init(),
        [Sem.SemExprMul] = delegate_const_data_init(),
        [Sem.SemExprDiv] = delegate_const_data_init(),
        [Sem.SemExprRem] = delegate_const_data_init(),
        [Sem.SemExprEq] = delegate_const_data_init(),
        [Sem.SemExprNe] = delegate_const_data_init(),
        [Sem.SemExprLt] = delegate_const_data_init(),
        [Sem.SemExprLe] = delegate_const_data_init(),
        [Sem.SemExprGt] = delegate_const_data_init(),
        [Sem.SemExprGe] = delegate_const_data_init(),
        [Sem.SemExprAnd] = delegate_const_data_init(),
        [Sem.SemExprOr] = delegate_const_data_init(),
        [Sem.SemExprBitAnd] = delegate_const_data_init(),
        [Sem.SemExprBitOr] = delegate_const_data_init(),
        [Sem.SemExprBitXor] = delegate_const_data_init(),
        [Sem.SemExprShl] = delegate_const_data_init(),
        [Sem.SemExprLShr] = delegate_const_data_init(),
        [Sem.SemExprAShr] = delegate_const_data_init(),
        [Sem.SemExprCastTo] = delegate_const_data_init(),
        [Sem.SemExprTruncTo] = delegate_const_data_init(),
        [Sem.SemExprZExtTo] = delegate_const_data_init(),
        [Sem.SemExprSExtTo] = delegate_const_data_init(),
        [Sem.SemExprBitcastTo] = delegate_const_data_init(),
        [Sem.SemExprSatCastTo] = delegate_const_data_init(),
        [Sem.SemExprSelect] = delegate_const_data_init(),
        [Sem.SemExprIndex] = delegate_const_data_init(),
        [Sem.SemExprField] = delegate_const_data_init(),
        [Sem.SemExprIndexAddr] = delegate_const_data_init(),
        [Sem.SemExprFieldAddr] = delegate_const_data_init(),
        [Sem.SemExprLoad] = delegate_const_data_init(),
        [Sem.SemExprIntrinsicCall] = delegate_const_data_init(),
        [Sem.SemExprCall] = delegate_const_data_init(),
        [Sem.SemExprAgg] = delegate_const_data_init(),
        [Sem.SemExprArrayLit] = delegate_const_data_init(),
        [Sem.SemExprBlock] = delegate_const_data_init(),
        [Sem.SemExprIf] = delegate_const_data_init(),
        [Sem.SemExprSwitch] = delegate_const_data_init(),
        [Sem.SemExprLoop] = delegate_const_data_init(),
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
        [Sem.SemExprIntrinsicCall] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args)
            if self.ty == Sem.SemTVoid then
                error("sem_to_back_expr_into_addr: void intrinsic calls have no materialization form")
            end
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr_into_addr: non-scalar intrinsic results are not supported")
            end
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
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
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdCallValueDirect(dst, ret_ty, Back.BackFuncId(func_text), Back.BackSigId("sig:" .. func_text), args),
            }, dst, ret_ty))
        end,
        [Sem.SemCallExtern] = function(self, dst, ret_ty, path, args)
            return pvm.once(Back.BackExprPlan({
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

    local function short_circuit_bool_expr(path, lhs, rhs, short_value)
        local dst = Back.BackValId(path)
        local rhs_block = Back.BackBlockId(path .. ".rhs.block")
        local short_block = Back.BackBlockId(path .. ".short.block")
        local join_block = Back.BackBlockId(path .. ".join.block")
        local cmds = {}
        append_expr_cmds(cmds, lhs)
        if expr_terminates(lhs) then
            return terminated_expr(cmds)
        end
        cmds[#cmds + 1] = Back.BackCmdCreateBlock(rhs_block)
        cmds[#cmds + 1] = Back.BackCmdCreateBlock(short_block)
        cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
        cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(join_block, dst, Back.BackBool)
        cmds[#cmds + 1] = Back.BackCmdBrIf(lhs.value, rhs_block, {}, short_block, {})
        cmds[#cmds + 1] = Back.BackCmdSealBlock(rhs_block)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(short_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(short_block)
        local short_id = Back.BackValId(path .. ".short")
        cmds[#cmds + 1] = Back.BackCmdConstBool(short_id, short_value)
        cmds[#cmds + 1] = Back.BackCmdJump(join_block, { short_id })
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(rhs_block)
        append_expr_cmds(cmds, rhs)
        if expr_has_value(rhs) then
            cmds[#cmds + 1] = Back.BackCmdJump(join_block, { rhs.value })
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
        if expr_terminates(rhs) then
            return Back.BackExprPlan(cmds, dst, Back.BackBool)
        end
        return Back.BackExprPlan(cmds, dst, Back.BackBool)
    end

    local intr_ops = {}

    intr_ops.expect_arg_count = function(call, expected, context)
        if #call.args ~= expected then
            error("sem_to_back_intrinsic: " .. context .. " expects " .. expected .. " args, got " .. #call.args)
        end
    end

    intr_ops.require_same_arg_type = function(call, index, expected_ty, context)
        local arg_ty = one_sem_expr_type(call.args[index])
        if arg_ty ~= expected_ty then
            error("sem_to_back_intrinsic: " .. context .. " arg " .. index .. " must have type '" .. tostring(expected_ty) .. "'")
        end
    end

    intr_ops.require_intlike_type = function(ty, context)
        if not type_is_intlike(ty) then
            error("sem_to_back_intrinsic: " .. context .. " requires an integer-like scalar type")
        end
    end

    intr_ops.require_float_type = function(ty, context)
        if not type_is_float(ty) then
            error("sem_to_back_intrinsic: " .. context .. " requires a float scalar type")
        end
    end

    intr_ops.require_numeric_abs_type = function(ty)
        if not type_is_intlike(ty) and not type_is_float(ty) then
            error("sem_to_back_intrinsic: abs requires an integer-like or float scalar type")
        end
    end

    intr_ops.collect_args = function(call, path, layout_env, break_block, break_args, continue_block, continue_args)
        local cmds = {}
        local values = {}
        for i = 1, #call.args do
            local arg = one_expr(call.args[i], path .. ".arg." .. i, layout_env, break_block, break_args, continue_block, continue_args)
            append_expr_cmds(cmds, arg)
            if expr_terminates(arg) then
                return cmds, values, true
            end
            values[i] = arg.value
        end
        return cmds, values, false
    end

    intr_ops.lower_value = pvm.phase("sem_to_back_intrinsic_value", {
        [Sem.SemPopcount] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 1, "popcount")
            intr_ops.require_intlike_type(call.ty, "popcount")
            intr_ops.require_same_arg_type(call, 1, call.ty, "popcount")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdPopcount(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemClz] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 1, "clz")
            intr_ops.require_intlike_type(call.ty, "clz")
            intr_ops.require_same_arg_type(call, 1, call.ty, "clz")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdClz(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemCtz] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 1, "ctz")
            intr_ops.require_intlike_type(call.ty, "ctz")
            intr_ops.require_same_arg_type(call, 1, call.ty, "ctz")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdCtz(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemRotl] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 2, "rotl")
            intr_ops.require_intlike_type(call.ty, "rotl")
            intr_ops.require_same_arg_type(call, 1, call.ty, "rotl")
            intr_ops.require_same_arg_type(call, 2, call.ty, "rotl")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdRotl(dst, ty, values[1], values[2])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemRotr] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 2, "rotr")
            intr_ops.require_intlike_type(call.ty, "rotr")
            intr_ops.require_same_arg_type(call, 1, call.ty, "rotr")
            intr_ops.require_same_arg_type(call, 2, call.ty, "rotr")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdRotr(dst, ty, values[1], values[2])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemBswap] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 1, "bswap")
            intr_ops.require_intlike_type(call.ty, "bswap")
            intr_ops.require_same_arg_type(call, 1, call.ty, "bswap")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdBswap(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemFma] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 3, "fma")
            intr_ops.require_float_type(call.ty, "fma")
            intr_ops.require_same_arg_type(call, 1, call.ty, "fma")
            intr_ops.require_same_arg_type(call, 2, call.ty, "fma")
            intr_ops.require_same_arg_type(call, 3, call.ty, "fma")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdFma(dst, ty, values[1], values[2], values[3])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemSqrt] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 1, "sqrt")
            intr_ops.require_float_type(call.ty, "sqrt")
            intr_ops.require_same_arg_type(call, 1, call.ty, "sqrt")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdSqrt(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemAbs] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 1, "abs")
            intr_ops.require_numeric_abs_type(call.ty)
            intr_ops.require_same_arg_type(call, 1, call.ty, "abs")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdAbs(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemFloor] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 1, "floor")
            intr_ops.require_float_type(call.ty, "floor")
            intr_ops.require_same_arg_type(call, 1, call.ty, "floor")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdFloor(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemCeil] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 1, "ceil")
            intr_ops.require_float_type(call.ty, "ceil")
            intr_ops.require_same_arg_type(call, 1, call.ty, "ceil")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdCeil(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemTruncFloat] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 1, "trunc_float")
            intr_ops.require_float_type(call.ty, "trunc_float")
            intr_ops.require_same_arg_type(call, 1, call.ty, "trunc_float")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdTruncFloat(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemRound] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 1, "round")
            intr_ops.require_float_type(call.ty, "round")
            intr_ops.require_same_arg_type(call, 1, call.ty, "round")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdRound(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemTrap] = function()
            error("sem_to_back_expr: trap has no value form; use stmt position")
        end,
        [Sem.SemAssume] = function()
            error("sem_to_back_expr: assume has no value form; use stmt position")
        end,
    })

    intr_ops.lower_stmt = pvm.phase("sem_to_back_intrinsic_stmt", {
        [Sem.SemTrap] = function(_, call)
            intr_ops.expect_arg_count(call, 0, "trap")
            if call.ty ~= Sem.SemTVoid then
                error("sem_to_back_stmt: trap intrinsic must currently use void type")
            end
            return pvm.once(Back.BackStmtPlan({ Back.BackCmdTrap }, Back.BackTerminates))
        end,
        [Sem.SemAssume] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            intr_ops.expect_arg_count(call, 1, "assume")
            if call.ty ~= Sem.SemTVoid then
                error("sem_to_back_stmt: assume intrinsic must currently use void type")
            end
            if one_sem_expr_type(call.args[1]) ~= Sem.SemTBool then
                error("sem_to_back_stmt: assume intrinsic currently requires a bool argument")
            end
            local cond = one_expr(call.args[1], path .. ".arg.1", layout_env, break_block, break_args, continue_block, continue_args)
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
        [Sem.SemPopcount] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemClz] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemCtz] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemRotl] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemRotr] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemBswap] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemFma] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemSqrt] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemAbs] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemFloor] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemCeil] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemTruncFloat] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemRound] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
    })

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
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(short_circuit_bool_expr(path, lhs, rhs, false))
        end,
        [Sem.SemExprOr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(short_circuit_bool_expr(path, lhs, rhs, true))
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
        [Sem.SemExprIntrinsicCall] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(pvm.one(intr_ops.lower_value(self.op, self, path, layout_env, break_block, break_args, continue_block, continue_args)))
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
        [Sem.SemBindLocalStoredValue] = function(self)
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

    const_ops.over_array_count = function(value_ty, context)
        local cls = getmetatable(value_ty) and getmetatable(value_ty).__class or nil
        if cls == Sem.SemTArray then
            return value_ty.count
        end
        if cls == Sem.SemTSlice then
            error(context .. ": slice bounded domains are not yet supported; slice/view layout and bounds lowering must be made explicit first")
        end
        error(context .. ": bounded domains currently require array-valued inputs")
    end

    const_ops.over_zip_eq_array_count = function(values, context)
        if #values == 0 then
            return 0
        end
        local expected = nil
        for i = 1, #values do
            local count = const_ops.over_array_count(one_sem_expr_type(values[i]), context)
            if expected == nil then
                expected = count
            elseif expected ~= count then
                error(context .. ": zip_eq currently requires equal compile-time array lengths")
            end
        end
        return expected or 0
    end

    const_ops.over_prefixed_stmt_plan = function(prefix, flow, plan)
        local cmds = {}
        append_expr_cmds(cmds, prefix)
        if expr_terminates(prefix) then
            return Back.BackStmtPlan(cmds, Back.BackTerminates)
        end
        copy_cmds(plan.cmds, cmds)
        return Back.BackStmtPlan(cmds, plan.flow)
    end

    const_ops.over_prefixed_expr_plan = function(prefix, plan)
        local cmds = {}
        append_expr_cmds(cmds, prefix)
        if expr_terminates(prefix) then
            return terminated_expr(cmds)
        end
        copy_cmds(plan.cmds, cmds)
        return Back.BackExprPlan(cmds, plan.value, plan.ty)
    end

    const_ops.over_prefixed_addr_plan = function(prefix, plan)
        local cmds = {}
        append_expr_cmds(cmds, prefix)
        if expr_terminates(prefix) then
            return terminated_addr(cmds)
        end
        append_addr_cmds(cmds, plan)
        if addr_terminates(plan) then
            return terminated_addr(cmds)
        end
        return addr_writes(cmds)
    end

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
                local cmds = {
            Back.BackCmdCreateStackSlot(local_value_slot_id(loop.index_binding.id), 8, 8),
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
            local carry_spec = one_stack_slot_spec(loop.carries[i].ty, layout_env)
            cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(local_value_slot_id(loop.carries[i].id), carry_spec.size, carry_spec.align)
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
        local body_current_args = over_loop_current_args(body_index, body_carry_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, exit_block, {}, continue_block, body_current_args)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
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
                local cmds = {
            Back.BackCmdCreateStackSlot(local_value_slot_id(loop.index_binding.id), 8, 8),
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
            local carry_spec = one_stack_slot_spec(loop.carries[i].ty, layout_env)
            cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(local_value_slot_id(loop.carries[i].id), carry_spec.size, carry_spec.align)
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
        local body_current_args = over_loop_current_args(body_index, body_carry_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, exit_block, body_current_args, continue_block, body_current_args)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
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
        [Sem.SemDomainBoundedValue] = function(self, loop, path, layout_env)
            local probe = one_addr_of_expr(self.value, path .. ".bounded", layout_env)
            local count = const_ops.over_array_count(one_sem_expr_type(self.value), "sem_to_back_over_stmt_domain")
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty))
            local stop = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".stop"), one_scalar(loop.index_binding.ty), tostring(count)),
            }, Back.BackValId(path .. ".stop"), one_scalar(loop.index_binding.ty))
            return pvm.once(const_ops.over_prefixed_stmt_plan(probe, Back.BackFallsThrough, build_over_stmt_plan(loop, path, start, stop, layout_env)))
        end,
        [Sem.SemDomainZipEq] = function(self, loop, path, layout_env)
            local cmds = {}
            local flow = Back.BackFallsThrough
            for i = 1, #self.values do
                local probe = one_addr_of_expr(self.values[i], path .. ".zip." .. i, layout_env)
                append_expr_cmds(cmds, probe)
                if expr_terminates(probe) then
                    flow = Back.BackTerminates
                    break
                end
            end
            if flow == Back.BackTerminates then
                return pvm.once(Back.BackStmtPlan(cmds, flow))
            end
            local count = const_ops.over_zip_eq_array_count(self.values, "sem_to_back_over_stmt_domain")
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty))
            local stop = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".stop"), one_scalar(loop.index_binding.ty), tostring(count)),
            }, Back.BackValId(path .. ".stop"), one_scalar(loop.index_binding.ty))
            local plan = build_over_stmt_plan(loop, path, start, stop, layout_env)
            copy_cmds(plan.cmds, cmds)
            return pvm.once(Back.BackStmtPlan(cmds, plan.flow))
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
        [Sem.SemDomainBoundedValue] = function(self, loop, path, layout_env)
            local probe = one_addr_of_expr(self.value, path .. ".bounded", layout_env)
            local count = const_ops.over_array_count(one_sem_expr_type(self.value), "sem_to_back_over_expr_domain")
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty))
            local stop = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".stop"), one_scalar(loop.index_binding.ty), tostring(count)),
            }, Back.BackValId(path .. ".stop"), one_scalar(loop.index_binding.ty))
            return pvm.once(const_ops.over_prefixed_expr_plan(probe, build_over_expr_plan(loop, path, start, stop, layout_env)))
        end,
        [Sem.SemDomainZipEq] = function(self, loop, path, layout_env)
            local cmds = {}
            for i = 1, #self.values do
                local probe = one_addr_of_expr(self.values[i], path .. ".zip." .. i, layout_env)
                append_expr_cmds(cmds, probe)
                if expr_terminates(probe) then
                    return pvm.once(terminated_expr(cmds))
                end
            end
            local count = const_ops.over_zip_eq_array_count(self.values, "sem_to_back_over_expr_domain")
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty))
            local stop = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".stop"), one_scalar(loop.index_binding.ty), tostring(count)),
            }, Back.BackValId(path .. ".stop"), one_scalar(loop.index_binding.ty))
            local plan = build_over_expr_plan(loop, path, start, stop, layout_env)
            copy_cmds(plan.cmds, cmds)
            return pvm.once(Back.BackExprPlan(cmds, plan.value, plan.ty))
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
                local cmds = {
            Back.BackCmdCreateStackSlot(local_value_slot_id(loop.index_binding.id), 8, 8),
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
            local carry_spec = one_stack_slot_spec(loop.carries[i].ty, layout_env)
            cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(local_value_slot_id(loop.carries[i].id), carry_spec.size, carry_spec.align)
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
        local body_current_args = over_loop_current_args(body_index, body_carry_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, exit_block, body_current_args, continue_block, body_current_args)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
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
        [Sem.SemDomainBoundedValue] = function(self, loop, addr, path, layout_env)
            local probe = one_addr_of_expr(self.value, path .. ".bounded", layout_env)
            local count = const_ops.over_array_count(one_sem_expr_type(self.value), "sem_to_back_over_expr_into_addr_domain")
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty))
            local stop = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".stop"), one_scalar(loop.index_binding.ty), tostring(count)),
            }, Back.BackValId(path .. ".stop"), one_scalar(loop.index_binding.ty))
            return pvm.once(const_ops.over_prefixed_addr_plan(probe, build_over_expr_into_addr(loop, addr, path, start, stop, layout_env)))
        end,
        [Sem.SemDomainZipEq] = function(self, loop, addr, path, layout_env)
            local cmds = {}
            for i = 1, #self.values do
                local probe = one_addr_of_expr(self.values[i], path .. ".zip." .. i, layout_env)
                append_expr_cmds(cmds, probe)
                if expr_terminates(probe) then
                    return pvm.once(terminated_addr(cmds))
                end
            end
            local count = const_ops.over_zip_eq_array_count(self.values, "sem_to_back_over_expr_into_addr_domain")
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_binding.ty))
            local stop = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".stop"), one_scalar(loop.index_binding.ty), tostring(count)),
            }, Back.BackValId(path .. ".stop"), one_scalar(loop.index_binding.ty))
            local plan = build_over_expr_into_addr(loop, addr, path, start, stop, layout_env)
            append_addr_cmds(cmds, plan)
            if addr_terminates(plan) then
                return pvm.once(terminated_addr(cmds))
            end
            return pvm.once(addr_writes(cmds))
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
                        local cmds = {
                Back.BackCmdCreateBlock(header_block),
                Back.BackCmdCreateBlock(body_block),
                Back.BackCmdCreateBlock(continue_block),
                Back.BackCmdCreateBlock(exit_block),
            }
            local init_values = {}
            for i = 1, #self.vars do
                local var_spec = one_stack_slot_spec(self.vars[i].ty, layout_env)
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(local_value_slot_id(self.vars[i].id), var_spec.size, var_spec.align)
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
            local body_current_args = loop_binding_value_args(body_params)
            local body_cmds, body_flow = lower_stmt_list(self.body, path .. ".body", layout_env, exit_block, {}, continue_block, body_current_args)
            copy_cmds(body_cmds, cmds)
            if body_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
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
                        local cmds = {
                Back.BackCmdCreateBlock(header_block),
                Back.BackCmdCreateBlock(body_block),
                Back.BackCmdCreateBlock(continue_block),
                Back.BackCmdCreateBlock(exit_block),
            }
            local init_values = {}
            for i = 1, #self.vars do
                local var_spec = one_stack_slot_spec(self.vars[i].ty, layout_env)
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(local_value_slot_id(self.vars[i].id), var_spec.size, var_spec.align)
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
            local body_current_args = loop_binding_value_args(body_params)
            local body_cmds, body_flow = lower_stmt_list(self.body, path .. ".body", layout_env, exit_block, body_current_args, continue_block, body_current_args)
            copy_cmds(body_cmds, cmds)
            if body_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
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
                        local cmds = {
                Back.BackCmdCreateBlock(header_block),
                Back.BackCmdCreateBlock(body_block),
                Back.BackCmdCreateBlock(continue_block),
                Back.BackCmdCreateBlock(exit_block),
            }
            local init_values = {}
            for i = 1, #self.vars do
                local var_spec = one_stack_slot_spec(self.vars[i].ty, layout_env)
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(local_value_slot_id(self.vars[i].id), var_spec.size, var_spec.align)
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
            local body_current_args = loop_binding_value_args(body_params)
            local body_cmds, body_flow = lower_stmt_list(self.body, path .. ".body", layout_env, exit_block, body_current_args, continue_block, body_current_args)
            copy_cmds(body_cmds, cmds)
            if body_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
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
        [Sem.SemExprIntrinsicCall] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args)
            return pvm.once(pvm.one(intr_ops.lower_stmt(self.op, self, path, layout_env, break_block, break_args, continue_block, continue_args)))
        end,
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
        [Sem.SemItemConst] = function(self, layout_env, const_env)
            local data_id = const_data_id("", self.c.name)
            local spec = one_stack_slot_spec(self.c.ty, layout_env)
            local cmds = {
                Back.BackCmdDeclareData(data_id, spec.size, spec.align),
            }
            copy_cmds(one_const_data_init(self.c.value, data_id, 0, layout_env, const_env, nil), cmds)
            return pvm.once(Back.BackItemPlan(cmds))
        end,
    })

    lower_module = pvm.phase("sem_to_back_module", {
        [Sem.SemModule] = function(self, layout_env, const_env)
            local env = ensure_const_env(const_env)
            local entries = {}
            for i = 1, #env.entries do
                entries[i] = env.entries[i]
            end
            for i = 1, #self.items do
                local item = self.items[i]
                if item.c ~= nil then
                    entries[#entries + 1] = Sem.SemConstEntry("", item.c.name, item.c.ty, item.c.value)
                end
            end
            local module_const_env = Sem.SemConstEnv(entries)
            local cmds = {}
            for i = 1, #self.items do
                copy_cmds(one_item(self.items[i], layout_env, module_const_env).cmds, cmds)
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
