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
    local aux = {}
    aux.residence = require("moonlift.resolve_sem_residence").Define(T)
    aux.ops = require("moonlift.lower_sem_to_back_ops").Define(T)

    local lower_scalar
    local lower_type_is_scalar
    local lower_type_is_void
    local lower_type_is_index
    local lower_type_is_bool
    local lower_type_is_pointer_like
    local lower_type_is_integral_scalar
    local lower_type_is_fp_scalar
    local lower_stack_slot_spec
    local lower_binding_value
    local lower_binding_expr
    local lower_binding_addr
    local lower_binding_store_addr
    local lower_back_binding_value
    local lower_back_binding_expr
    local lower_back_binding_addr
    local lower_back_binding_store_addr
    local lower_place_type
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
    local lower_view_lowering_has_value
    local lower_view_lowering_flow
    local lower_call_value
    local sem_expr_type
    local lower_loop_stmt_plan
    local lower_loop_expr_plan
    local lower_loop_expr_into_addr
    local require_index_expr
    local require_pointer_expr
    local lower_over_stmt_domain
    local lower_over_expr_domain
    local lower_over_expr_into_addr_domain
    local lower_addr_of_expr
    local lower_place_addr
    local lower_index_base_addr
    local sem_const_eval
    local sem_const_stmt_eval
    local lower_func
    local lower_item
    local lower_module

    local function binding_residence(binding, residence_plan)
        if residence_plan ~= nil then
            for i = 1, #residence_plan.entries do
                local entry = residence_plan.entries[i]
                if entry.binding == binding then
                    return entry.residence
                end
            end
        end
        return pvm.one(aux.residence.lower_binding_residence(binding))
    end

    local function one_back_binding(node, residence_plan)
        return pvm.one(aux.residence.lower_back_binding(node, residence_plan))
    end

    local function one_scalar(node)
        return pvm.one(lower_scalar(node))
    end

    local function one_type_is_scalar(node)
        return pvm.one(lower_type_is_scalar(node))
    end

    local function one_type_is_void(node)
        return pvm.one(lower_type_is_void(node))
    end

    local function one_type_is_index(node)
        return pvm.one(lower_type_is_index(node))
    end

    local function one_type_is_bool(node)
        return pvm.one(lower_type_is_bool(node))
    end

    local function one_type_is_pointer_like(node)
        return pvm.one(lower_type_is_pointer_like(node))
    end

    local function one_type_is_integral_scalar(node)
        return pvm.one(lower_type_is_integral_scalar(node))
    end

    local function one_type_is_fp_scalar(node)
        return pvm.one(lower_type_is_fp_scalar(node))
    end

    local function one_stack_slot_spec(node, layout_env)
        return pvm.one(lower_stack_slot_spec(node, layout_env))
    end

    local function one_binding_expr(node, path, residence_plan)
        return pvm.one(lower_binding_expr(node, path, residence_plan))
    end

    local function one_binding_addr(node, path, residence_plan)
        return pvm.one(lower_binding_addr(node, path, residence_plan))
    end

    local function one_binding_store_addr(node, path, residence_plan)
        return pvm.one(lower_binding_store_addr(node, path, residence_plan))
    end

    local function one_back_binding_value(node)
        return pvm.one(lower_back_binding_value(node))
    end

    local function one_back_binding_expr(node, path)
        return pvm.one(lower_back_binding_expr(node, path))
    end

    local function one_back_binding_addr(node, path)
        return pvm.one(lower_back_binding_addr(node, path))
    end

    local function one_back_binding_store_addr(node, path)
        return pvm.one(lower_back_binding_store_addr(node, path))
    end

    local function one_place_type(node)
        return pvm.one(lower_place_type(node))
    end

    local function one_type_mem_size(node, layout_env)
        return pvm.one(lower_type_mem_size(node, layout_env))
    end

    local function one_field_ref_type(node)
        return pvm.one(lower_field_ref_type(node))
    end

    local function one_field_addr_from_ref(node, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return pvm.one(lower_field_addr_from_ref(node, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
    end

    local function one_field_expr_from_ref(node, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return pvm.one(lower_field_expr_from_ref(node, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
    end

    local function one_sig_spec(node)
        return pvm.one(lower_sig_spec(node))
    end

    local function one_expr(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return pvm.one(lower_expr(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
    end

    local function one_plain_expr(node, path, layout_env, residence_plan)
        return one_expr(node, path, layout_env, nil, nil, nil, nil, residence_plan)
    end

    local function one_stmt(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return pvm.one(lower_stmt(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
    end

    local function one_expr_stmt(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return pvm.one(lower_expr_stmt(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
    end

    local function one_loop_stmt_plan(node, path, layout_env, residence_plan)
        return pvm.one(lower_loop_stmt_plan(node, path, layout_env, residence_plan))
    end

    local function one_loop_expr_plan(node, path, layout_env, residence_plan)
        return pvm.one(lower_loop_expr_plan(node, path, layout_env, residence_plan))
    end

    local function one_loop_expr_into_addr(node, addr, path, layout_env, residence_plan)
        return pvm.one(lower_loop_expr_into_addr(node, addr, path, layout_env, residence_plan))
    end

    local function one_over_stmt_domain(node, loop, path, layout_env, residence_plan)
        return pvm.one(lower_over_stmt_domain(node, loop, path, layout_env, residence_plan))
    end

    local function one_over_expr_domain(node, loop, path, layout_env, residence_plan)
        return pvm.one(lower_over_expr_domain(node, loop, path, layout_env, residence_plan))
    end

    local function one_over_expr_into_addr_domain(node, loop, addr, path, layout_env, residence_plan)
        return pvm.one(lower_over_expr_into_addr_domain(node, loop, addr, path, layout_env, residence_plan))
    end

    local function one_addr_of_expr(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return pvm.one(lower_addr_of_expr(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
    end

    local function one_plain_addr_of_expr(node, path, layout_env, residence_plan)
        return one_addr_of_expr(node, path, layout_env, nil, nil, nil, nil, residence_plan)
    end

    local function one_place_addr(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return pvm.one(lower_place_addr(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
    end

    local function one_index_base_addr(node, index, elem_size, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return pvm.one(lower_index_base_addr(node, index, elem_size, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
    end

    local function one_const_value_data_init(node, data_id, offset, layout_env)
        return pvm.one(aux.const_data.lower_const_value_data_init(node, data_id, offset, layout_env))
    end

    local function one_const_data_init(node, data_id, offset, layout_env, const_env, visiting)
        return pvm.one(aux.const_data.lower_const_data_init(node, data_id, offset, layout_env, const_env, visiting))
    end

    local function one_const_eval(node, const_env, local_env, visiting)
        return pvm.one(sem_const_eval(node, const_env, local_env, visiting))
    end

    local function one_copy_type_addr(node, src_addr, dst_addr, path, layout_env)
        return pvm.one(aux.materialize.lower_copy_type_addr(node, src_addr, dst_addr, path, layout_env))
    end

    local function one_expr_into_addr(node, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return pvm.one(aux.materialize.lower_expr_into_addr(node, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
    end

    local function one_plain_expr_into_addr(node, addr, path, layout_env, residence_plan)
        return one_expr_into_addr(node, addr, path, layout_env, nil, nil, nil, nil, residence_plan)
    end

    local function one_func_residence_plan(node)
        return pvm.one(aux.residence.lower_func_residence_plan(node))
    end

    local function one_func(node, module_name, layout_env)
        return pvm.one(lower_func(node, module_name, layout_env))
    end

    local function one_item(node, module_name, layout_env, const_env)
        return pvm.one(lower_item(node, module_name, layout_env, const_env))
    end

    local function one_sem_expr_type(node)
        return pvm.one(sem_expr_type(node))
    end

    local function one_call_value(node, dst, ret_ty, path, args, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return pvm.one(lower_call_value(node, dst, ret_ty, path, args, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
    end

    local function one_bounded_view(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return pvm.one(aux.lower_bounded_view(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
    end

    local function one_plain_bounded_view(node, path, layout_env, residence_plan)
        return one_bounded_view(node, path, layout_env, nil, nil, nil, nil, residence_plan)
    end

    local function one_add_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_add_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_sub_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_sub_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_mul_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_mul_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_div_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_div_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_rem_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_rem_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_lt_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_lt_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_le_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_le_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_gt_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_gt_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_ge_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_ge_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_eq_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_eq_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_ne_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_ne_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_neg_cmd(node, dst, ty, value)
        return pvm.one(aux.ops.lower_neg_cmd(node, dst, ty, value))
    end

    local function one_not_cmd(node, dst, value)
        return pvm.one(aux.ops.lower_not_cmd(node, dst, value))
    end

    local function one_bnot_cmd(node, dst, ty, value)
        return pvm.one(aux.ops.lower_bnot_cmd(node, dst, ty, value))
    end

    local function one_band_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_band_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_bor_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_bor_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_bxor_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_bxor_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_shl_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_shl_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_lshr_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_lshr_cmd(node, dst, ty, lhs, rhs))
    end

    local function one_ashr_cmd(node, dst, ty, lhs, rhs)
        return pvm.one(aux.ops.lower_ashr_cmd(node, dst, ty, lhs, rhs))
    end

    local function copy_cmds(src, out)
        for i = 1, #src do
            out[#out + 1] = src[i]
        end
    end

    local function append_expr_cmds(out, plan)
        copy_cmds(plan.cmds, out)
    end

    local function append_view_cmds(out, plan)
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

    local function view_has_value(plan)
        return pvm.one(lower_view_lowering_has_value(plan))
    end

    local function view_terminates(plan)
        return pvm.one(lower_view_lowering_flow(plan)) == Back.BackTerminates
    end

    local function terminated_view(cmds)
        return Back.BackViewTerminated(cmds)
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

    local function ptr_with_const_offset(base, offset, path)
        local dst = Back.BackValId(path)
        if offset == 0 then
            return { Back.BackCmdAlias(dst, base) }, dst
        end
        local off = Back.BackValId(path .. ".offset")
        return {
            Back.BackCmdConstInt(off, Back.BackIndex, tostring(offset)),
            one_add_cmd(Sem.SemTPtr, dst, Back.BackPtr, base, off),
        }, dst
    end

    local function load_from_const_offset(base, offset, ty, path)
        local addr_cmds, addr = ptr_with_const_offset(base, offset, path .. ".addr")
        local value = Back.BackValId(path)
        local cmds = {}
        copy_cmds(addr_cmds, cmds)
        cmds[#cmds + 1] = Back.BackCmdLoad(value, ty, addr)
        return cmds, value
    end

    local function prefix_stmt_plan_with_view(view, plan)
        local cmds = {}
        append_view_cmds(cmds, view)
        if view_terminates(view) then
            return Back.BackStmtPlan(cmds, Back.BackTerminates)
        end
        copy_cmds(plan.cmds, cmds)
        return Back.BackStmtPlan(cmds, plan.flow)
    end

    local function prefix_expr_plan_with_view(view, plan)
        local cmds = {}
        append_view_cmds(cmds, view)
        if view_terminates(view) then
            return terminated_expr(cmds)
        end
        copy_cmds(plan.cmds, cmds)
        return Back.BackExprPlan(cmds, plan.value, plan.ty)
    end

    local function prefix_addr_plan_with_view(view, plan)
        local cmds = {}
        append_view_cmds(cmds, view)
        if view_terminates(view) then
            return terminated_addr(cmds)
        end
        append_addr_cmds(cmds, plan)
        if addr_terminates(plan) then
            return terminated_addr(cmds)
        end
        return addr_writes(cmds)
    end

    local function append_stmt_cmds(out, plan)
        copy_cmds(plan.cmds, out)
    end

    local function lower_stmt_list(nodes, base_path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        local cmds = {}
        local flow = Back.BackFallsThrough
        for i = 1, #nodes do
            if flow == Back.BackTerminates then
                break
            end
            local plan = one_stmt(nodes[i], base_path .. ".stmt." .. i, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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

    local function break_value_flag_slot_id(block)
        return Back.BackStackSlotId("slot:breakvalue:flag:" .. block.text)
    end

    local function break_value_value_slot_id(block)
        return Back.BackStackSlotId("slot:breakvalue:value:" .. block.text)
    end

    local function temp_slot_id(path)
        return Back.BackStackSlotId(path .. ".slot")
    end

    local function materialize_expr_temp(expr, ty, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        local spec = one_stack_slot_spec(ty, layout_env)
        local addr = Back.BackValId(path)
        local cmds = {
            Back.BackCmdCreateStackSlot(temp_slot_id(path), spec.size, spec.align),
            Back.BackCmdStackAddr(addr, temp_slot_id(path)),
        }
        local init = one_expr_into_addr(expr, addr, path .. ".init", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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

    local function static_data_id(module_name, item_name)
        return Back.BackDataId("data:static:" .. const_data_key(module_name, item_name))
    end

    local function find_named_layout(layout_env, module_name, type_name)
        local layouts = layout_env and layout_env.layouts or nil
        if layouts == nil then return nil end
        for i = #layouts, 1, -1 do
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

    aux.const_data = require("moonlift.lower_sem_to_back_const_data").Define(T, {
        one_scalar = one_scalar,
        one_type_mem_size = one_type_mem_size,
        one_const_eval = one_const_eval,
        require_named_layout = require_named_layout,
        const_data_key = const_data_key,
        find_layout_field = find_layout_field,
        copy_cmds = copy_cmds,
    })

    aux.materialize = require("moonlift.lower_sem_to_back_materialize").Define(T, {
        one_scalar = one_scalar,
        one_type_is_scalar = one_type_is_scalar,
        one_type_is_void = one_type_is_void,
        one_type_mem_size = one_type_mem_size,
        one_expr = one_expr,
        one_sem_expr_type = one_sem_expr_type,
        one_addr_of_expr = one_addr_of_expr,
        one_add_cmd = one_add_cmd,
        one_eq_cmd = one_eq_cmd,
        one_loop_expr_into_addr = one_loop_expr_into_addr,
        one_expr_into_addr = one_expr_into_addr,
        require_named_layout = require_named_layout,
        find_field_init = find_field_init,
        copy_cmds = copy_cmds,
        append_expr_cmds = append_expr_cmds,
        append_addr_cmds = append_addr_cmds,
        expr_has_value = expr_has_value,
        expr_terminates = expr_terminates,
        terminated_addr = terminated_addr,
        addr_continues = addr_continues,
        addr_terminates = addr_terminates,
        addr_writes = addr_writes,
        lower_stmt_list = lower_stmt_list,
        one_back_switch_expr_arms = function(arms, value_ty)
            return aux.lower_back_switch_expr_arms(arms, value_ty)
        end,
        back_switch_expr_arms_is_const = function(node)
            return pvm.one(aux.back_switch_expr_arms_is_const(node))
        end,
        one_back_switch_key_raw = function(node)
            return pvm.one(aux.back_switch_key_raw(node))
        end,
        one_back_switch_key_expr = function(node, value_ty, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.one(aux.lower_back_switch_key_expr(node, value_ty, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
    })

    local function loop_carry_binding(loop_id, carry)
        return Sem.SemBindLoopCarry(loop_id, carry.port_id, carry.name, carry.ty)
    end

    local function loop_index_binding(loop)
        return Sem.SemBindLoopIndex(loop.loop_id, loop.index_port.name, loop.index_port.ty)
    end

    local function loop_carry_slot_id(loop_id, port_id)
        return Back.BackStackSlotId("slot:loopcarry:" .. loop_id .. ":" .. port_id)
    end

    local function loop_index_slot_id(loop_id, name)
        return Back.BackStackSlotId("slot:loopindex:" .. loop_id .. ":" .. name)
    end

    local function loop_carry_value_id(loop_id, port_id)
        return Back.BackValId("local:loopcarry:" .. loop_id .. ":" .. port_id)
    end

    local function loop_index_value_id(loop_id, name)
        return Back.BackValId("local:loopindex:" .. loop_id .. ":" .. name)
    end

    local function realized_loop_binding(binding, default_loop_id)
        if binding.id ~= nil or (binding.loop_id ~= nil and binding.port_id == nil) then
            return binding
        end
        if binding.port_id ~= nil then
            return Sem.SemBindLoopCarry(default_loop_id, binding.port_id, binding.name, binding.ty)
        end
        return Sem.SemBindLoopIndex(binding.loop_id, binding.name, binding.ty)
    end

    local function loop_binding_value_id(binding, default_loop_id)
        local realized = realized_loop_binding(binding, default_loop_id)
        if realized.id ~= nil then
            return local_value_id(realized.id)
        end
        if realized.port_id ~= nil then
            return loop_carry_value_id(realized.loop_id, realized.port_id)
        end
        return loop_index_value_id(realized.loop_id, realized.name)
    end

    local function emit_aliases_for_loop_bindings(cmds, bindings, param_ids, default_loop_id, residence_plan)
        for i = 1, #bindings do
            local binding = realized_loop_binding(bindings[i], default_loop_id)
            if binding_residence(binding, residence_plan) == Sem.SemResidenceStack then
                local slot_id = binding.id ~= nil and local_value_slot_id(binding.id)
                    or (binding.port_id ~= nil and loop_carry_slot_id(binding.loop_id, binding.port_id))
                    or loop_index_slot_id(binding.loop_id, binding.name)
                local addr = Back.BackValId("loop.slot.addr:" .. i)
                cmds[#cmds + 1] = Back.BackCmdStackAddr(addr, slot_id)
                cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(binding.ty), addr, param_ids[i])
            else
                cmds[#cmds + 1] = Back.BackCmdAlias(loop_binding_value_id(binding, default_loop_id), param_ids[i])
            end
        end
    end

    local function emit_alias_for_index_binding(cmds, binding, value_id, residence_plan)
        if binding_residence(binding, residence_plan) == Sem.SemResidenceStack then
            local addr = Back.BackValId("loop.index.slot.addr:" .. binding.loop_id .. ":" .. binding.name)
            cmds[#cmds + 1] = Back.BackCmdStackAddr(addr, loop_index_slot_id(binding.loop_id, binding.name))
            cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(binding.ty), addr, value_id)
        else
            cmds[#cmds + 1] = Back.BackCmdAlias(loop_index_value_id(binding.loop_id, binding.name), value_id)
        end
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

    local function eval_loop_nexts(carries, nexts, path, layout_env, residence_plan)
        local cmds = {}
        local values = {}
        local seen = {}
        for i = 1, #carries do
            local carry = carries[i]
            local update = nil
            for j = 1, #nexts do
                if nexts[j].port_id == carry.port_id then
                    if update ~= nil then
                        error("sem_to_back: duplicate loop update for port '" .. carry.port_id .. "'")
                    end
                    update = nexts[j]
                    seen[j] = true
                end
            end
            if update == nil then
                error("sem_to_back: missing loop update for port '" .. carry.port_id .. "'")
            end
            local expr = one_plain_expr(update.value, path .. ".next." .. i, layout_env, residence_plan)
            append_expr_cmds(cmds, expr)
            if expr_terminates(expr) then
                return cmds, values, Back.BackTerminates
            end
            values[i] = expr.value
        end
        for j = 1, #nexts do
            if not seen[j] then
                error("sem_to_back: loop update targets unknown port '" .. nexts[j].port_id .. "'")
            end
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
        [Sem.SemTView] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    lower_type_is_void = pvm.phase("sem_to_back_type_is_void", {
        [Sem.SemTVoid] = function() return pvm.once(true) end,
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
        [Sem.SemTIndex] = function() return pvm.once(false) end,
        [Sem.SemTPtrTo] = function() return pvm.once(false) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTView] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    lower_type_is_index = pvm.phase("sem_to_back_type_is_index", {
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
        [Sem.SemTIndex] = function() return pvm.once(true) end,
        [Sem.SemTPtrTo] = function() return pvm.once(false) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTView] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    lower_type_is_bool = pvm.phase("sem_to_back_type_is_bool", {
        [Sem.SemTVoid] = function() return pvm.once(false) end,
        [Sem.SemTBool] = function() return pvm.once(true) end,
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
        [Sem.SemTIndex] = function() return pvm.once(false) end,
        [Sem.SemTPtrTo] = function() return pvm.once(false) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTView] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    lower_type_is_pointer_like = pvm.phase("sem_to_back_type_is_pointer_like", {
        [Sem.SemTPtr] = function() return pvm.once(true) end,
        [Sem.SemTPtrTo] = function() return pvm.once(true) end,
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
        [Sem.SemTIndex] = function() return pvm.once(false) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTView] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    lower_type_is_integral_scalar = pvm.phase("sem_to_back_type_is_integral_scalar", {
        [Sem.SemTVoid] = function() return pvm.once(false) end,
        [Sem.SemTBool] = function() return pvm.once(false) end,
        [Sem.SemTI8] = function() return pvm.once(true) end,
        [Sem.SemTI16] = function() return pvm.once(true) end,
        [Sem.SemTI32] = function() return pvm.once(true) end,
        [Sem.SemTI64] = function() return pvm.once(true) end,
        [Sem.SemTU8] = function() return pvm.once(true) end,
        [Sem.SemTU16] = function() return pvm.once(true) end,
        [Sem.SemTU32] = function() return pvm.once(true) end,
        [Sem.SemTU64] = function() return pvm.once(true) end,
        [Sem.SemTF32] = function() return pvm.once(false) end,
        [Sem.SemTF64] = function() return pvm.once(false) end,
        [Sem.SemTPtr] = function() return pvm.once(false) end,
        [Sem.SemTIndex] = function() return pvm.once(true) end,
        [Sem.SemTPtrTo] = function() return pvm.once(false) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTView] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    lower_type_is_fp_scalar = pvm.phase("sem_to_back_type_is_fp_scalar", {
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
        [Sem.SemTF32] = function() return pvm.once(true) end,
        [Sem.SemTF64] = function() return pvm.once(true) end,
        [Sem.SemTPtr] = function() return pvm.once(false) end,
        [Sem.SemTIndex] = function() return pvm.once(false) end,
        [Sem.SemTPtrTo] = function() return pvm.once(false) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTView] = function() return pvm.once(false) end,
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
        [Sem.SemTSlice] = function() return pvm.once(Back.BackStackSlotSpec(16, 8)) end,
        [Sem.SemTView] = function() return pvm.once(Back.BackStackSlotSpec(24, 8)) end,
        [Sem.SemTArray] = function(self, layout_env)
            return pvm.once(Back.BackStackSlotSpec(one_type_mem_size(self, layout_env), one_stack_slot_spec(self.elem, layout_env).align))
        end,
        [Sem.SemTNamed] = function(self, layout_env)
            local layout = require_named_layout(layout_env, self.module_name, self.type_name)
            return pvm.once(Back.BackStackSlotSpec(layout.size, layout.align))
        end,
    })

    lower_back_binding_value = pvm.phase("sem_to_back_binding_value", {
        [Sem.SemBackLocalValue] = function(self)
            return pvm.once(local_value_id(self.id))
        end,
        [Sem.SemBackArgValue] = function(self)
            return pvm.once(Back.BackValId("arg:" .. self.index .. ":" .. self.name))
        end,
        [Sem.SemBackLoopCarryValue] = function(self)
            error("sem_to_back_binding_value: loop carry '" .. self.name .. "' has no raw direct value id in Sem->Back; use expression lowering so storage is made explicit")
        end,
        [Sem.SemBackLoopIndexValue] = function(self)
            error("sem_to_back_binding_value: loop index '" .. self.name .. "' has no raw direct value id in Sem->Back; use expression lowering so storage is made explicit")
        end,
        [Sem.SemBackLocalStored] = function(self)
            error("sem_to_back_binding_value: stored immutable local '" .. self.name .. "' has no raw direct value id in Sem->Back")
        end,
        [Sem.SemBackArgStored] = function(self)
            error("sem_to_back_binding_value: stored argument '" .. self.name .. "' has no raw direct value id in Sem->Back")
        end,
        [Sem.SemBackLoopCarryStored] = function(self)
            error("sem_to_back_binding_value: stored loop carry '" .. self.name .. "' has no raw direct value id in Sem->Back")
        end,
        [Sem.SemBackLoopIndexStored] = function(self)
            error("sem_to_back_binding_value: stored loop index '" .. self.name .. "' has no raw direct value id in Sem->Back")
        end,
        [Sem.SemBackLocalCell] = function(self)
            error("sem_to_back_binding_value: mutable local cell '" .. self.name .. "' has no raw direct value id in Sem->Back")
        end,
        [Sem.SemBackGlobalFunc] = function(self)
            error("sem_to_back_binding_value: direct function binding reads are not yet supported ('" .. self.item_name .. "')")
        end,
        [Sem.SemBackGlobalConst] = function(self)
            error("sem_to_back_binding_value: pure const globals should be folded/lowered before direct runtime binding reads ('" .. self.item_name .. "')")
        end,
        [Sem.SemBackGlobalStatic] = function(self)
            error("sem_to_back_binding_value: static global '" .. self.item_name .. "' must be loaded through expression/address lowering")
        end,
        [Sem.SemBackExtern] = function(self)
            error("sem_to_back_binding_value: direct extern binding reads are not yet supported ('" .. self.symbol .. "')")
        end,
    })

    lower_back_binding_expr = pvm.phase("sem_to_back_binding_expr", {
        [Sem.SemBackLocalValue] = function(self, path)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar immutable local '" .. self.name .. "' has no direct value form in Sem->Back; use address-based access")
            end
            return pvm.once(Back.BackExprPlan({}, local_value_id(self.id), one_scalar(self.ty)))
        end,
        [Sem.SemBackLocalStored] = function(self, path)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar stored immutable local '" .. self.name .. "' has no direct value form in Sem->Back; use address-based access")
            end
            local addr = Back.BackValId(path .. ".addr")
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, local_value_slot_id(self.id)),
                Back.BackCmdLoad(dst, ty, addr),
            }, dst, ty))
        end,
        [Sem.SemBackArgValue] = function(self)
            local ty = one_scalar(self.ty)
            return pvm.once(Back.BackExprPlan({}, Back.BackValId("arg:" .. self.index .. ":" .. self.name), ty))
        end,
        [Sem.SemBackArgStored] = function(self, path)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar stored argument '" .. self.name .. "' has no direct value form in Sem->Back")
            end
            local addr = Back.BackValId(path .. ".addr")
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, arg_slot_id(self.index, self.name)),
                Back.BackCmdLoad(dst, ty, addr),
            }, dst, ty))
        end,
        [Sem.SemBackLoopCarryValue] = function(self)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar loop carry '" .. self.name .. "' has no direct value form in Sem->Back")
            end
            return pvm.once(Back.BackExprPlan({}, loop_carry_value_id(self.loop_id, self.port_id), one_scalar(self.ty)))
        end,
        [Sem.SemBackLoopCarryStored] = function(self, path)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar stored loop carry '" .. self.name .. "' has no direct value form in Sem->Back")
            end
            local addr = Back.BackValId(path .. ".addr")
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, loop_carry_slot_id(self.loop_id, self.port_id)),
                Back.BackCmdLoad(dst, ty, addr),
            }, dst, ty))
        end,
        [Sem.SemBackLoopIndexValue] = function(self)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar loop index '" .. self.name .. "' has no direct value form in Sem->Back")
            end
            return pvm.once(Back.BackExprPlan({}, loop_index_value_id(self.loop_id, self.name), one_scalar(self.ty)))
        end,
        [Sem.SemBackLoopIndexStored] = function(self, path)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar stored loop index '" .. self.name .. "' has no direct value form in Sem->Back")
            end
            local addr = Back.BackValId(path .. ".addr")
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, loop_index_slot_id(self.loop_id, self.name)),
                Back.BackCmdLoad(dst, ty, addr),
            }, dst, ty))
        end,
        [Sem.SemBackLocalCell] = function(self, path)
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
        [Sem.SemBackGlobalConst] = function(self)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar const global '" .. self.item_name .. "' has no direct value form in Sem->Back")
            end
            error("sem_to_back_binding_expr: pure const globals should be folded/lowered before direct runtime binding reads ('" .. self.item_name .. "')")
        end,
        [Sem.SemBackGlobalStatic] = function(self, path)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_binding_expr: non-scalar static global '" .. self.item_name .. "' has no direct value form in Sem->Back; use address-based access")
            end
            local addr = Back.BackValId(path .. ".addr")
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            local data_id = static_data_id(self.module_name, self.item_name)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdDataAddr(addr, data_id),
                Back.BackCmdLoad(dst, ty, addr),
            }, dst, ty))
        end,
        [Sem.SemBackGlobalFunc] = function(self)
            error("sem_to_back_binding_expr: direct function binding reads are not yet supported ('" .. self.item_name .. "')")
        end,
        [Sem.SemBackExtern] = function(self)
            error("sem_to_back_binding_expr: direct extern binding reads are not yet supported ('" .. self.symbol .. "')")
        end,
    })

    lower_back_binding_addr = pvm.phase("sem_to_back_binding_addr", {
        [Sem.SemBackLocalCell] = function(self, path)
            local addr = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, local_cell_slot_id(self.id)),
            }, addr, Back.BackPtr))
        end,
        [Sem.SemBackGlobalStatic] = function(self, path)
            local addr = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdDataAddr(addr, static_data_id(self.module_name, self.item_name)),
            }, addr, Back.BackPtr))
        end,
        [Sem.SemBackLocalStored] = function(self, path)
            local addr = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, local_value_slot_id(self.id)),
            }, addr, Back.BackPtr))
        end,
        [Sem.SemBackArgStored] = function(self, path)
            local addr = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, arg_slot_id(self.index, self.name)),
            }, addr, Back.BackPtr))
        end,
        [Sem.SemBackLoopCarryStored] = function(self, path)
            local addr = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, loop_carry_slot_id(self.loop_id, self.port_id)),
            }, addr, Back.BackPtr))
        end,
        [Sem.SemBackLoopIndexStored] = function(self, path)
            local addr = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, loop_index_slot_id(self.loop_id, self.name)),
            }, addr, Back.BackPtr))
        end,
        [Sem.SemBackLocalValue] = function(self)
            error("sem_to_back_binding_addr: pure immutable local '" .. self.name .. "' has no canonical storage in Sem->Back")
        end,
        [Sem.SemBackArgValue] = function(self)
            error("sem_to_back_binding_addr: pure value argument '" .. self.name .. "' has no canonical storage in Sem->Back yet")
        end,
        [Sem.SemBackLoopCarryValue] = function(self)
            error("sem_to_back_binding_addr: pure value loop carry '" .. self.name .. "' has no canonical storage in Sem->Back")
        end,
        [Sem.SemBackLoopIndexValue] = function(self)
            error("sem_to_back_binding_addr: pure value loop index '" .. self.name .. "' has no canonical storage in Sem->Back")
        end,
        [Sem.SemBackGlobalConst] = function(self)
            error("sem_to_back_binding_addr: pure const global '" .. self.item_name .. "' has no addressable storage in Sem->Back; use static items for addressable globals")
        end,
        [Sem.SemBackGlobalFunc] = function(self)
            error("sem_to_back_binding_addr: function '" .. self.item_name .. "' has no addressable storage in Sem->Back")
        end,
        [Sem.SemBackExtern] = function(self)
            error("sem_to_back_binding_addr: extern '" .. self.symbol .. "' has no addressable storage in Sem->Back")
        end,
    })

    lower_back_binding_store_addr = pvm.phase("sem_to_back_binding_store_addr", {
        [Sem.SemBackLocalCell] = function(self, path)
            local addr = Back.BackValId(path)
            return pvm.once(Back.BackExprPlan({
                Back.BackCmdStackAddr(addr, local_cell_slot_id(self.id)),
            }, addr, Back.BackPtr))
        end,
        [Sem.SemBackLocalValue] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to immutable local '" .. self.name .. "'")
        end,
        [Sem.SemBackLocalStored] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to immutable local '" .. self.name .. "'")
        end,
        [Sem.SemBackArgValue] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to argument '" .. self.name .. "'")
        end,
        [Sem.SemBackArgStored] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to argument '" .. self.name .. "'")
        end,
        [Sem.SemBackLoopCarryValue] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to immutable loop carry '" .. self.name .. "'")
        end,
        [Sem.SemBackLoopCarryStored] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to immutable loop carry '" .. self.name .. "'")
        end,
        [Sem.SemBackLoopIndexValue] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to loop index '" .. self.name .. "'")
        end,
        [Sem.SemBackLoopIndexStored] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to loop index '" .. self.name .. "'")
        end,
        [Sem.SemBackGlobalConst] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to const global '" .. self.item_name .. "'")
        end,
        [Sem.SemBackGlobalStatic] = function(self)
            error("sem_to_back_binding_store_addr: global set lowering is not yet supported ('" .. self.item_name .. "')")
        end,
        [Sem.SemBackGlobalFunc] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to function '" .. self.item_name .. "'")
        end,
        [Sem.SemBackExtern] = function(self)
            error("sem_to_back_binding_store_addr: cannot assign to extern '" .. self.symbol .. "'")
        end,
    })

    local function delegate_binding_value(self, residence_plan)
        return pvm.once(one_back_binding_value(one_back_binding(self, residence_plan)))
    end

    local function delegate_binding_expr(self, path, residence_plan)
        return pvm.once(one_back_binding_expr(one_back_binding(self, residence_plan), path))
    end

    local function delegate_binding_addr(self, path, residence_plan)
        return pvm.once(one_back_binding_addr(one_back_binding(self, residence_plan), path))
    end

    local function delegate_binding_store_addr(self, path, residence_plan)
        return pvm.once(one_back_binding_store_addr(one_back_binding(self, residence_plan), path))
    end

    lower_binding_value = pvm.phase("sem_to_back_binding_value", {
        [Sem.SemBindLocalValue] = delegate_binding_value,
        [Sem.SemBindLocalCell] = delegate_binding_value,
        [Sem.SemBindArg] = delegate_binding_value,
        [Sem.SemBindLoopCarry] = delegate_binding_value,
        [Sem.SemBindLoopIndex] = delegate_binding_value,
        [Sem.SemBindGlobalFunc] = delegate_binding_value,
        [Sem.SemBindGlobalConst] = delegate_binding_value,
        [Sem.SemBindGlobalStatic] = delegate_binding_value,
        [Sem.SemBindExtern] = delegate_binding_value,
    })

    lower_binding_expr = pvm.phase("sem_to_back_binding_expr", {
        [Sem.SemBindLocalValue] = delegate_binding_expr,
        [Sem.SemBindLocalCell] = delegate_binding_expr,
        [Sem.SemBindArg] = delegate_binding_expr,
        [Sem.SemBindLoopCarry] = delegate_binding_expr,
        [Sem.SemBindLoopIndex] = delegate_binding_expr,
        [Sem.SemBindGlobalFunc] = delegate_binding_expr,
        [Sem.SemBindGlobalConst] = delegate_binding_expr,
        [Sem.SemBindGlobalStatic] = delegate_binding_expr,
        [Sem.SemBindExtern] = delegate_binding_expr,
    })

    lower_binding_addr = pvm.phase("sem_to_back_binding_addr", {
        [Sem.SemBindLocalValue] = delegate_binding_addr,
        [Sem.SemBindLocalCell] = delegate_binding_addr,
        [Sem.SemBindArg] = delegate_binding_addr,
        [Sem.SemBindLoopCarry] = delegate_binding_addr,
        [Sem.SemBindLoopIndex] = delegate_binding_addr,
        [Sem.SemBindGlobalFunc] = delegate_binding_addr,
        [Sem.SemBindGlobalConst] = delegate_binding_addr,
        [Sem.SemBindGlobalStatic] = delegate_binding_addr,
        [Sem.SemBindExtern] = delegate_binding_addr,
    })

    lower_binding_store_addr = pvm.phase("sem_to_back_binding_store_addr", {
        [Sem.SemBindLocalValue] = delegate_binding_store_addr,
        [Sem.SemBindLocalCell] = delegate_binding_store_addr,
        [Sem.SemBindArg] = delegate_binding_store_addr,
        [Sem.SemBindLoopCarry] = delegate_binding_store_addr,
        [Sem.SemBindLoopIndex] = delegate_binding_store_addr,
        [Sem.SemBindGlobalFunc] = delegate_binding_store_addr,
        [Sem.SemBindGlobalConst] = delegate_binding_store_addr,
        [Sem.SemBindGlobalStatic] = delegate_binding_store_addr,
        [Sem.SemBindExtern] = delegate_binding_store_addr,
    })

    aux.binding_key = pvm.phase("sem_binding_key_for_back", {
        [Sem.SemBindLocalValue] = function(self)
            return pvm.once("local_value:" .. self.id)
        end,
        [Sem.SemBindLocalCell] = function(self)
            return pvm.once("local_cell:" .. self.id)
        end,
        [Sem.SemBindArg] = function(self)
            return pvm.once("arg:" .. self.index .. ":" .. self.name)
        end,
        [Sem.SemBindLoopCarry] = function(self)
            return pvm.once("loop_carry:" .. self.loop_id .. ":" .. self.port_id)
        end,
        [Sem.SemBindLoopIndex] = function(self)
            return pvm.once("loop_index:" .. self.loop_id .. ":" .. self.name)
        end,
        [Sem.SemBindGlobalFunc] = function(self)
            return pvm.once("global_func:" .. const_data_key(self.module_name, self.item_name))
        end,
        [Sem.SemBindGlobalConst] = function(self)
            return pvm.once("global_const:" .. const_data_key(self.module_name, self.item_name))
        end,
        [Sem.SemBindGlobalStatic] = function(self)
            return pvm.once("global_static:" .. const_data_key(self.module_name, self.item_name))
        end,
        [Sem.SemBindExtern] = function(self)
            return pvm.once("extern:" .. self.symbol)
        end,
    })

    aux.binding_is_local_cell = pvm.phase("sem_binding_is_local_cell_for_back", {
        [Sem.SemBindLocalCell] = function() return pvm.once(true) end,
        [Sem.SemBindLocalValue] = function() return pvm.once(false) end,
        [Sem.SemBindArg] = function() return pvm.once(false) end,
        [Sem.SemBindLoopCarry] = function() return pvm.once(false) end,
        [Sem.SemBindLoopIndex] = function() return pvm.once(false) end,
        [Sem.SemBindGlobalFunc] = function() return pvm.once(false) end,
        [Sem.SemBindGlobalConst] = function() return pvm.once(false) end,
        [Sem.SemBindGlobalStatic] = function() return pvm.once(false) end,
        [Sem.SemBindExtern] = function() return pvm.once(false) end,
    })

    lower_place_type = pvm.phase("sem_place_type_for_back", {
        [Sem.SemPlaceBinding] = function(self)
            return pvm.once(self.binding.ty)
        end,
        [Sem.SemPlaceDeref] = function(self)
            return pvm.once(self.elem)
        end,
        [Sem.SemPlaceField] = function(self)
            return pvm.once(one_field_ref_type(self.field))
        end,
        [Sem.SemPlaceIndex] = function(self)
            return pvm.once(self.ty)
        end,
    })

    aux.place_store_addr = pvm.phase("sem_to_back_place_store_addr", {
        [Sem.SemPlaceBinding] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_binding_store_addr(self.binding, path, residence_plan))
        end,
        [Sem.SemPlaceDeref] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_expr(self.base, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemPlaceField] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local base = pvm.one(aux.place_store_addr(self.base, path .. ".base", layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            local dst = Back.BackValId(path)
            local offset = Back.BackValId(path .. ".offset")
            local cmds = {}
            append_expr_cmds(cmds, base)
            if expr_terminates(base) then
                return pvm.once(terminated_expr(cmds))
            end
            if self.field.offset == nil then
                error("sem_to_back_place_store_addr: field layout is not yet resolved for '" .. self.field.field_name .. "'")
            end
            cmds[#cmds + 1] = Back.BackCmdConstInt(offset, Back.BackIndex, tostring(self.field.offset))
            cmds[#cmds + 1] = one_add_cmd(Sem.SemTPtr, dst, Back.BackPtr, base.value, offset)
            return pvm.once(Back.BackExprPlan(cmds, dst, Back.BackPtr))
        end,
        [Sem.SemPlaceIndex] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(pvm.one(aux.index_base_store_addr(self.base, self.index, one_type_mem_size(self.ty, layout_env), path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)))
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
            return pvm.once(16)
        end,
        [Sem.SemTView] = function()
            return pvm.once(24)
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
        [Sem.SemFieldByOffset] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local base = one_addr_of_expr(base_expr, path .. ".base", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
        [Sem.SemFieldByOffset] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_field_expr_from_ref: non-scalar field '" .. self.field_name .. "' has no direct value form in Sem->Back; use address-based access")
            end
            local addr = one_field_addr_from_ref(self, base_expr, path .. ".addr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
            if not one_type_is_void(self.result) then
                results[1] = one_scalar(self.result)
            end
            return pvm.once(Back.BackSigSpec(params, results))
        end,
    })

    aux.lower_and_cmd = aux.ops.lower_and_cmd
    aux.lower_or_cmd = aux.ops.lower_or_cmd

    sem_expr_type = pvm.phase("sem_expr_type_for_back", {
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
        [Sem.SemExprField] = function(self) return pvm.once(one_field_ref_type(self.field)) end,
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

    lower_view_lowering_has_value = pvm.phase("back_view_lowering_has_value", {
        [Back.BackViewPlan] = function()
            return pvm.once(true)
        end,
        [Back.BackViewTerminated] = function()
            return pvm.once(false)
        end,
    })

    lower_view_lowering_flow = pvm.phase("back_view_lowering_flow", {
        [Back.BackViewPlan] = function()
            return pvm.once(Back.BackFallsThrough)
        end,
        [Back.BackViewTerminated] = function()
            return pvm.once(Back.BackTerminates)
        end,
    })

    lower_index_base_addr = pvm.phase("sem_to_back_index_base_addr", {
        [Sem.SemIndexBasePlace] = function(self, index, elem_size, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local index_ty = one_sem_expr_type(index)
            if not one_type_is_index(index_ty) then
                error("sem_to_back_index_base_addr: pointer indexing currently requires an explicit SemTIndex index expression")
            end
            local base = one_place_addr(self.base, path .. ".base", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local idx = one_expr(index, path .. ".index", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
        [Sem.SemIndexBaseView] = function(self, index, elem_size, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local idx = require_index_expr(index, path .. ".index", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_index_base_addr")
            local view = one_bounded_view(self.view, path .. ".view", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local offset = Back.BackValId(path .. ".offset")
            local dst = Back.BackValId(path)
            local cmds = {}
            append_view_cmds(cmds, view)
            if view_terminates(view) then
                return pvm.once(terminated_expr(cmds))
            end
            append_expr_cmds(cmds, idx)
            if expr_terminates(idx) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = one_mul_cmd(Sem.SemTIndex, offset, Back.BackIndex, idx.value, view.stride)
            cmds[#cmds + 1] = one_add_cmd(Sem.SemTPtr, dst, Back.BackPtr, view.data, offset)
            return pvm.once(Back.BackExprPlan(cmds, dst, Back.BackPtr))
        end,
    })

    aux.index_base_store_addr = pvm.phase("sem_to_back_index_base_store_addr", {
        [Sem.SemIndexBasePlace] = function(self, index, elem_size, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local index_ty = one_sem_expr_type(index)
            if not one_type_is_index(index_ty) then
                error("sem_to_back_index_base_store_addr: pointer indexing currently requires an explicit SemTIndex index expression")
            end
            local base = pvm.one(aux.place_store_addr(self.base, path .. ".base", layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            local idx = one_expr(index, path .. ".index", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
        [Sem.SemIndexBaseView] = function(self, index, elem_size, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local idx = require_index_expr(index, path .. ".index", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_index_base_store_addr")
            local view = one_bounded_view(self.view, path .. ".view", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local offset = Back.BackValId(path .. ".offset")
            local dst = Back.BackValId(path)
            local cmds = {}
            append_view_cmds(cmds, view)
            if view_terminates(view) then
                return pvm.once(terminated_expr(cmds))
            end
            append_expr_cmds(cmds, idx)
            if expr_terminates(idx) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = one_mul_cmd(Sem.SemTIndex, offset, Back.BackIndex, idx.value, view.stride)
            cmds[#cmds + 1] = one_add_cmd(Sem.SemTPtr, dst, Back.BackPtr, view.data, offset)
            return pvm.once(Back.BackExprPlan(cmds, dst, Back.BackPtr))
        end,
    })

    aux.index_addr_from_base_type = pvm.phase("sem_to_back_index_addr_from_base_type", {
        [Sem.SemTPtrTo] = function(self, base_expr, index_expr, elem_ty, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            error("sem_to_back_index_addr_from_base_type: legacy base-type indexing path is no longer used; lower explicit SemIndexBase instead")
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

    lower_place_addr = pvm.phase("sem_to_back_place_addr", {
        [Sem.SemPlaceBinding] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_binding_addr(self.binding, path, residence_plan))
        end,
        [Sem.SemPlaceDeref] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_expr(self.base, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemPlaceField] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local base = one_place_addr(self.base, path .. ".base", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local offset = Back.BackValId(path .. ".offset")
            local cmds = {}
            append_expr_cmds(cmds, base)
            if expr_terminates(base) then
                return pvm.once(terminated_expr(cmds))
            end
            if self.field.offset == nil then
                error("sem_to_back_place_addr: field layout is not yet resolved for '" .. self.field.field_name .. "'")
            end
            cmds[#cmds + 1] = Back.BackCmdConstInt(offset, Back.BackIndex, tostring(self.field.offset))
            cmds[#cmds + 1] = one_add_cmd(Sem.SemTPtr, dst, Back.BackPtr, base.value, offset)
            return pvm.once(Back.BackExprPlan(cmds, dst, Back.BackPtr))
        end,
        [Sem.SemPlaceIndex] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_index_base_addr(self.base, self.index, one_type_mem_size(self.ty, layout_env), path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
    })

    lower_addr_of_expr = pvm.phase("sem_to_back_addr_of_expr", {
        [Sem.SemExprBinding] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_binding_addr(self.binding, path, residence_plan))
        end,
        [Sem.SemExprAddrOf] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_place_addr(self.place, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprDeref] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_expr(self.value, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprIndex] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_index_base_addr(self.base, self.index, one_type_mem_size(self.ty, layout_env), path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
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
        [Sem.SemExprField] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_field_addr_from_ref(self.field, self.base, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprLoad] = function() error("sem_to_back_addr_of_expr: cannot take address of a loaded value result") end,
        [Sem.SemExprIntrinsicCall] = function() error("sem_to_back_addr_of_expr: cannot take address of an intrinsic call result") end,
        [Sem.SemExprCall] = function() error("sem_to_back_addr_of_expr: cannot take address of a call result") end,
        [Sem.SemExprAgg] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(materialize_expr_temp(self, self.ty, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprArrayLit] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(materialize_expr_temp(self, one_sem_expr_type(self), path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprBlock] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(materialize_expr_temp(self, self.ty, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprIf] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(materialize_expr_temp(self, self.ty, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprSwitch] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(materialize_expr_temp(self, self.ty, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprLoop] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(materialize_expr_temp(self, self.ty, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
    })

    local const_eval = require("moonlift.lower_sem_to_back_const_eval").Define(T, aux)
    sem_const_eval = const_eval.sem_const_eval
    sem_const_stmt_eval = const_eval.sem_const_stmt_eval
    local const_ops = const_eval.const_ops
    aux.const_scalars = require("moonlift.fold_sem_const_scalars").Define(T, {
        one_const_eval = function(node, const_env, local_env, visiting)
            return one_const_eval(node, const_env, local_env, visiting)
        end,
    })

    local function switch_value_supports_int_cmd(value_ty)
        return one_type_is_bool(value_ty) or one_type_is_integral_scalar(value_ty) or one_type_is_index(value_ty)
    end

    local lower_switch_const_case_raw = pvm.phase("sem_to_back_switch_const_case_raw", {
        [Sem.SemConstBool] = function(self, value_ty)
            if not one_type_is_bool(value_ty) then
                return pvm.once(nil)
            end
            return pvm.once(self.value and "1" or "0")
        end,
        [Sem.SemConstInt] = function(self, value_ty)
            if one_type_is_bool(value_ty) or not switch_value_supports_int_cmd(value_ty) or self.ty ~= value_ty then
                return pvm.once(nil)
            end
            return pvm.once(self.raw)
        end,
        [Sem.SemConstFloat] = function()
            return pvm.once(nil)
        end,
        [Sem.SemConstNil] = function()
            return pvm.once(nil)
        end,
        [Sem.SemConstAgg] = function()
            return pvm.once(nil)
        end,
        [Sem.SemConstArray] = function()
            return pvm.once(nil)
        end,
    })

    local function switch_case_const_raw(key, value_ty)
        local ok, const_value = pcall(one_const_eval, key, nil, nil, nil)
        if not ok then
            return nil
        end
        return pvm.one(lower_switch_const_case_raw(const_value, value_ty))
    end

    aux.lower_back_switch_key = function(key, value_ty)
        local raw = switch_case_const_raw(key, value_ty)
        if raw ~= nil then
            return Sem.SemBackSwitchKeyConst(raw)
        end
        return Sem.SemBackSwitchKeyExpr(key)
    end

    aux.back_switch_key_is_const = pvm.phase("sem_to_back_back_switch_key_is_const", {
        [Sem.SemBackSwitchKeyConst] = function()
            return pvm.once(true)
        end,
        [Sem.SemBackSwitchKeyExpr] = function()
            return pvm.once(false)
        end,
    })

    aux.back_switch_key_raw = pvm.phase("sem_to_back_back_switch_key_raw", {
        [Sem.SemBackSwitchKeyConst] = function(self)
            return pvm.once(self.raw)
        end,
        [Sem.SemBackSwitchKeyExpr] = function()
            error("sem_to_back_back_switch_key_raw: expected constant switch key")
        end,
    })

    aux.lower_back_switch_stmt_arm = pvm.phase("sem_to_back_back_switch_stmt_arm", {
        [Sem.SemSwitchStmtArm] = function(self, value_ty)
            return pvm.once(Sem.SemBackSwitchStmtArm(aux.lower_back_switch_key(self.key, value_ty), self.body))
        end,
    })

    aux.lower_back_switch_expr_arm = pvm.phase("sem_to_back_back_switch_expr_arm", {
        [Sem.SemSwitchExprArm] = function(self, value_ty)
            return pvm.once(Sem.SemBackSwitchExprArm(aux.lower_back_switch_key(self.key, value_ty), self.body, self.result))
        end,
    })

    aux.back_switch_stmt_arms_is_const = pvm.phase("sem_to_back_back_switch_stmt_arms_is_const", {
        [Sem.SemBackSwitchStmtArmsConst] = function()
            return pvm.once(true)
        end,
        [Sem.SemBackSwitchStmtArmsExpr] = function()
            return pvm.once(false)
        end,
    })

    aux.back_switch_expr_arms_is_const = pvm.phase("sem_to_back_back_switch_expr_arms_is_const", {
        [Sem.SemBackSwitchExprArmsConst] = function()
            return pvm.once(true)
        end,
        [Sem.SemBackSwitchExprArmsExpr] = function()
            return pvm.once(false)
        end,
    })

    aux.lower_back_switch_stmt_arms = function(arms, value_ty)
        local out = {}
        local all_const = switch_value_supports_int_cmd(value_ty)
        local seen = {}
        for i = 1, #arms do
            out[i] = pvm.one(aux.lower_back_switch_stmt_arm(arms[i], value_ty))
            if all_const and pvm.one(aux.back_switch_key_is_const(out[i].key)) then
                local raw = pvm.one(aux.back_switch_key_raw(out[i].key))
                if seen[raw] then
                    all_const = false
                else
                    seen[raw] = true
                end
            else
                all_const = false
            end
        end
        if all_const then
            return Sem.SemBackSwitchStmtArmsConst(out)
        end
        return Sem.SemBackSwitchStmtArmsExpr(out)
    end

    aux.lower_back_switch_expr_arms = function(arms, value_ty)
        local out = {}
        local all_const = switch_value_supports_int_cmd(value_ty)
        local seen = {}
        for i = 1, #arms do
            out[i] = pvm.one(aux.lower_back_switch_expr_arm(arms[i], value_ty))
            if all_const and pvm.one(aux.back_switch_key_is_const(out[i].key)) then
                local raw = pvm.one(aux.back_switch_key_raw(out[i].key))
                if seen[raw] then
                    all_const = false
                else
                    seen[raw] = true
                end
            else
                all_const = false
            end
        end
        if all_const then
            return Sem.SemBackSwitchExprArmsConst(out)
        end
        return Sem.SemBackSwitchExprArmsExpr(out)
    end

    aux.lower_back_switch_key_expr = pvm.phase("sem_to_back_back_switch_key_expr", {
        [Sem.SemBackSwitchKeyConst] = function(self, value_ty, path)
            local dst = Back.BackValId(path)
            if one_type_is_bool(value_ty) then
                return pvm.once(Back.BackExprPlan({ Back.BackCmdConstBool(dst, self.raw == "1") }, dst, Back.BackBool))
            end
            return pvm.once(Back.BackExprPlan({ Back.BackCmdConstInt(dst, one_scalar(value_ty), self.raw) }, dst, one_scalar(value_ty)))
        end,
        [Sem.SemBackSwitchKeyExpr] = function(self, value_ty, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_expr(self.key, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
    })

    local function build_switch_expr_value(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        local value_ty = one_sem_expr_type(self.value)
        if not one_type_is_scalar(value_ty) then
            error("sem_to_back_expr: switch value must currently be scalar in Sem->Back")
        end
        if not one_type_is_scalar(self.ty) then
            error("sem_to_back_expr: non-scalar switch expr results have no direct value form in Sem->Back; use an address/materialization context")
        end
        local result_back_ty = one_scalar(self.ty)
        local dst = Back.BackValId(path)
        local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        local cmds = {}
        append_expr_cmds(cmds, value)
        if expr_terminates(value) then
            return terminated_expr(cmds)
        end
        if #self.arms == 0 then
            local default_plan = one_expr(self.default_expr, path .. ".default", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            append_expr_cmds(cmds, default_plan)
            if expr_terminates(default_plan) then
                return terminated_expr(cmds)
            end
            return Back.BackExprPlan(cmds, default_plan.value, result_back_ty)
        end

        local back_arms = aux.lower_back_switch_expr_arms(self.arms, value_ty)
        local default_plan = one_expr(self.default_expr, path .. ".default", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        local arm_plans = {}
        local need_join = expr_has_value(default_plan)
        for i = 1, #back_arms.arms do
            local body_cmds, body_flow = lower_stmt_list(back_arms.arms[i].body, path .. ".arm." .. i, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local plan_cmds = {}
            copy_cmds(body_cmds, plan_cmds)
            local plan = terminated_expr(plan_cmds)
            if body_flow == Back.BackFallsThrough then
                local result_plan = one_expr(back_arms.arms[i].result, path .. ".arm." .. i .. ".result", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                append_expr_cmds(plan_cmds, result_plan)
                if expr_has_value(result_plan) then
                    plan = Back.BackExprPlan(plan_cmds, result_plan.value, result_back_ty)
                else
                    plan = terminated_expr(plan_cmds)
                end
            end
            arm_plans[i] = plan
            if expr_has_value(plan) then
                need_join = true
            end
        end

        local join_block = Back.BackBlockId(path .. ".join.block")
        local default_block = Back.BackBlockId(path .. ".default.block")
        local arm_blocks = {}
        if pvm.one(aux.back_switch_expr_arms_is_const(back_arms)) then
            local cases = {}
            for i = 1, #back_arms.arms do
                arm_blocks[i] = Back.BackBlockId(path .. ".arm." .. i .. ".block")
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(arm_blocks[i])
                cases[i] = Back.BackSwitchCase(pvm.one(aux.back_switch_key_raw(back_arms.arms[i].key)), arm_blocks[i])
            end
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(default_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(join_block, dst, result_back_ty)
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchInt(value.value, one_scalar(value_ty), cases, default_block)
            for i = 1, #back_arms.arms do
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(arm_blocks[i])
                append_expr_cmds(cmds, arm_plans[i])
                if expr_has_value(arm_plans[i]) then
                    cmds[#cmds + 1] = Back.BackCmdJump(join_block, { arm_plans[i].value })
                end
                cmds[#cmds + 1] = Back.BackCmdSealBlock(arm_blocks[i])
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(default_block)
            append_expr_cmds(cmds, default_plan)
            if expr_has_value(default_plan) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, { default_plan.value })
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(default_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                return Back.BackExprPlan(cmds, dst, result_back_ty)
            end
            return terminated_expr(cmds)
        end

        local test_blocks = {}
        for i = 1, #back_arms.arms do
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
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(join_block, dst, result_back_ty)
        end
        for i = 1, #back_arms.arms do
            if i > 1 then
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(test_blocks[i])
            end
            local key = pvm.one(aux.lower_back_switch_key_expr(back_arms.arms[i].key, value_ty, path .. ".arm." .. i .. ".key", layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            append_expr_cmds(cmds, key)
            local else_block = (i < #back_arms.arms) and test_blocks[i + 1] or default_block
            if expr_has_value(key) then
                local match = Back.BackValId(path .. ".arm." .. i .. ".match")
                cmds[#cmds + 1] = one_eq_cmd(value_ty, match, Back.BackBool, value.value, key.value)
                cmds[#cmds + 1] = Back.BackCmdBrIf(match, arm_blocks[i], {}, else_block, {})
                cmds[#cmds + 1] = Back.BackCmdSealBlock(arm_blocks[i])
                cmds[#cmds + 1] = Back.BackCmdSealBlock(else_block)
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(arm_blocks[i])
            append_expr_cmds(cmds, arm_plans[i])
            if expr_has_value(arm_plans[i]) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, { arm_plans[i].value })
            end
        end
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(default_block)
        append_expr_cmds(cmds, default_plan)
        if expr_has_value(default_plan) then
            cmds[#cmds + 1] = Back.BackCmdJump(join_block, { default_plan.value })
        end
        if need_join then
            cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
            return Back.BackExprPlan(cmds, dst, result_back_ty)
        end
        return terminated_expr(cmds)
    end

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
        [Sem.SemCallIndirect] = function(self, dst, ret_ty, path, args, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local callee = one_expr(self.callee, path .. ".callee", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(short_block)
        local short_id = Back.BackValId(path .. ".short")
        cmds[#cmds + 1] = Back.BackCmdConstBool(short_id, short_value)
        cmds[#cmds + 1] = Back.BackCmdJump(join_block, { short_id })
        cmds[#cmds + 1] = Back.BackCmdSealBlock(short_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(rhs_block)
        append_expr_cmds(cmds, rhs)
        if expr_has_value(rhs) then
            cmds[#cmds + 1] = Back.BackCmdJump(join_block, { rhs.value })
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(rhs_block)
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
        if not one_type_is_integral_scalar(ty) then
            error("sem_to_back_intrinsic: " .. context .. " requires an integer-like scalar type")
        end
    end

    intr_ops.require_float_type = function(ty, context)
        if not one_type_is_fp_scalar(ty) then
            error("sem_to_back_intrinsic: " .. context .. " requires a float scalar type")
        end
    end

    intr_ops.require_numeric_abs_type = function(ty)
        if not one_type_is_integral_scalar(ty) and not one_type_is_fp_scalar(ty) then
            error("sem_to_back_intrinsic: abs requires an integer-like or float scalar type")
        end
    end

    intr_ops.collect_args = function(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        local cmds = {}
        local values = {}
        for i = 1, #call.args do
            local arg = one_expr(call.args[i], path .. ".arg." .. i, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            append_expr_cmds(cmds, arg)
            if expr_terminates(arg) then
                return cmds, values, true
            end
            values[i] = arg.value
        end
        return cmds, values, false
    end

    intr_ops.lower_value = pvm.phase("sem_to_back_intrinsic_value", {
        [Sem.SemPopcount] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 1, "popcount")
            intr_ops.require_intlike_type(call.ty, "popcount")
            intr_ops.require_same_arg_type(call, 1, call.ty, "popcount")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdPopcount(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemClz] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 1, "clz")
            intr_ops.require_intlike_type(call.ty, "clz")
            intr_ops.require_same_arg_type(call, 1, call.ty, "clz")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdClz(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemCtz] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 1, "ctz")
            intr_ops.require_intlike_type(call.ty, "ctz")
            intr_ops.require_same_arg_type(call, 1, call.ty, "ctz")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdCtz(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemRotl] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 2, "rotl")
            intr_ops.require_intlike_type(call.ty, "rotl")
            intr_ops.require_same_arg_type(call, 1, call.ty, "rotl")
            intr_ops.require_same_arg_type(call, 2, call.ty, "rotl")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdRotl(dst, ty, values[1], values[2])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemRotr] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 2, "rotr")
            intr_ops.require_intlike_type(call.ty, "rotr")
            intr_ops.require_same_arg_type(call, 1, call.ty, "rotr")
            intr_ops.require_same_arg_type(call, 2, call.ty, "rotr")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdRotr(dst, ty, values[1], values[2])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemBswap] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 1, "bswap")
            intr_ops.require_intlike_type(call.ty, "bswap")
            intr_ops.require_same_arg_type(call, 1, call.ty, "bswap")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdBswap(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemFma] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 3, "fma")
            intr_ops.require_float_type(call.ty, "fma")
            intr_ops.require_same_arg_type(call, 1, call.ty, "fma")
            intr_ops.require_same_arg_type(call, 2, call.ty, "fma")
            intr_ops.require_same_arg_type(call, 3, call.ty, "fma")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdFma(dst, ty, values[1], values[2], values[3])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemSqrt] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 1, "sqrt")
            intr_ops.require_float_type(call.ty, "sqrt")
            intr_ops.require_same_arg_type(call, 1, call.ty, "sqrt")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdSqrt(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemAbs] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 1, "abs")
            intr_ops.require_numeric_abs_type(call.ty)
            intr_ops.require_same_arg_type(call, 1, call.ty, "abs")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdAbs(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemFloor] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 1, "floor")
            intr_ops.require_float_type(call.ty, "floor")
            intr_ops.require_same_arg_type(call, 1, call.ty, "floor")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdFloor(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemCeil] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 1, "ceil")
            intr_ops.require_float_type(call.ty, "ceil")
            intr_ops.require_same_arg_type(call, 1, call.ty, "ceil")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdCeil(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemTruncFloat] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 1, "trunc_float")
            intr_ops.require_float_type(call.ty, "trunc_float")
            intr_ops.require_same_arg_type(call, 1, call.ty, "trunc_float")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if terminated then return pvm.once(terminated_expr(cmds)) end
            cmds[#cmds + 1] = Back.BackCmdTruncFloat(dst, ty, values[1])
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemRound] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 1, "round")
            intr_ops.require_float_type(call.ty, "round")
            intr_ops.require_same_arg_type(call, 1, call.ty, "round")
            local dst = Back.BackValId(path)
            local ty = one_scalar(call.ty)
            local cmds, values, terminated = intr_ops.collect_args(call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
            if not one_type_is_void(call.ty) then
                error("sem_to_back_stmt: trap intrinsic must currently use void type")
            end
            return pvm.once(Back.BackStmtPlan({ Back.BackCmdTrap }, Back.BackTerminates))
        end,
        [Sem.SemAssume] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            intr_ops.expect_arg_count(call, 1, "assume")
            if not one_type_is_void(call.ty) then
                error("sem_to_back_stmt: assume intrinsic must currently use void type")
            end
            if not one_type_is_bool(one_sem_expr_type(call.args[1])) then
                error("sem_to_back_stmt: assume intrinsic currently requires a bool argument")
            end
            local cond = one_expr(call.args[1], path .. ".arg.1", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(fail_block)
            cmds[#cmds + 1] = Back.BackCmdTrap
            cmds[#cmds + 1] = Back.BackCmdSealBlock(fail_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(ok_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(ok_block)
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
        end,
        [Sem.SemPopcount] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemClz] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemCtz] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemRotl] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemRotr] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemBswap] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemFma] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemSqrt] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemAbs] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemFloor] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemCeil] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemTruncFloat] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            return pvm.once(Back.BackStmtPlan(expr.cmds, expr_to_stmt_flow(expr)))
        end,
        [Sem.SemRound] = function(_, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = pvm.one(intr_ops.lower_value(call.op, call, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
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
        [Sem.SemExprBinding] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_binding_expr(self.binding, path, residence_plan))
        end,
        [Sem.SemExprAddrOf] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_place_addr(self.place, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprDeref] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local addr = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            local cmds = {}
            append_expr_cmds(cmds, addr)
            if expr_terminates(addr) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdLoad(dst, ty, addr.value)
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemExprNeg] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(unary_expr_plan(value, dst, ty, function(v)
                return one_neg_cmd(self.ty, dst, ty, v)
            end))
        end,
        [Sem.SemExprNot] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(unary_expr_plan(value, dst, Back.BackBool, function(v)
                return one_not_cmd(self.ty, dst, v)
            end))
        end,
        [Sem.SemExprBNot] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(unary_expr_plan(value, dst, ty, function(v)
                return one_bnot_cmd(self.ty, dst, ty, v)
            end))
        end,
        [Sem.SemExprAdd] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_add_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprSub] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_sub_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprMul] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_mul_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprDiv] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_div_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprRem] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_rem_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprEq] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local lhs_ty = one_sem_expr_type(self.lhs)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, Back.BackBool, function(l, r)
                return one_eq_cmd(lhs_ty, dst, Back.BackBool, l, r)
            end))
        end,
        [Sem.SemExprNe] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local lhs_ty = one_sem_expr_type(self.lhs)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, Back.BackBool, function(l, r)
                return one_ne_cmd(lhs_ty, dst, Back.BackBool, l, r)
            end))
        end,
        [Sem.SemExprLt] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local lhs_ty = one_sem_expr_type(self.lhs)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, Back.BackBool, function(l, r)
                return one_lt_cmd(lhs_ty, dst, Back.BackBool, l, r)
            end))
        end,
        [Sem.SemExprLe] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local lhs_ty = one_sem_expr_type(self.lhs)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, Back.BackBool, function(l, r)
                return one_le_cmd(lhs_ty, dst, Back.BackBool, l, r)
            end))
        end,
        [Sem.SemExprGt] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local lhs_ty = one_sem_expr_type(self.lhs)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, Back.BackBool, function(l, r)
                return one_gt_cmd(lhs_ty, dst, Back.BackBool, l, r)
            end))
        end,
        [Sem.SemExprGe] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local lhs_ty = one_sem_expr_type(self.lhs)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, Back.BackBool, function(l, r)
                return one_ge_cmd(lhs_ty, dst, Back.BackBool, l, r)
            end))
        end,
        [Sem.SemExprAnd] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(short_circuit_bool_expr(path, lhs, rhs, false))
        end,
        [Sem.SemExprOr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(short_circuit_bool_expr(path, lhs, rhs, true))
        end,
        [Sem.SemExprBitAnd] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_band_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprBitOr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_bor_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprBitXor] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_bxor_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprShl] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_shl_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprLShr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_lshr_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprAShr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local lhs = one_expr(self.lhs, path .. ".lhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local rhs = one_expr(self.rhs, path .. ".rhs", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            return pvm.once(binary_expr_plan(lhs, rhs, dst, ty, function(l, r)
                return one_ashr_cmd(self.ty, dst, ty, l, r)
            end))
        end,
        [Sem.SemExprSelect] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local dst = Back.BackValId(path)
            local cond = one_expr(self.cond, path .. ".cond", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local then_value = one_expr(self.then_value, path .. ".then", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local else_value = one_expr(self.else_value, path .. ".else", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
        [Sem.SemExprIndex] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr: non-scalar index results have no direct value form in Sem->Back; use address-based access")
            end
            local dst = Back.BackValId(path)
            local addr = one_addr_of_expr(self, path .. ".addr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            local cmds = {}
            append_expr_cmds(cmds, addr)
            if expr_terminates(addr) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdLoad(dst, ty, addr.value)
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemExprField] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_field_expr_from_ref(self.field, self.base, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprLoad] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr: non-scalar load results have no direct value form in Sem->Back; use an address/materialization context")
            end
            local dst = Back.BackValId(path)
            local addr = one_expr(self.addr, path .. ".addr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ty = one_scalar(self.ty)
            local cmds = {}
            append_expr_cmds(cmds, addr)
            if expr_terminates(addr) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdLoad(dst, ty, addr.value)
            return pvm.once(Back.BackExprPlan(cmds, dst, ty))
        end,
        [Sem.SemExprIntrinsicCall] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(pvm.one(intr_ops.lower_value(self.op, self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)))
        end,
        [Sem.SemExprAgg] = function()
            error("sem_to_back_expr: aggregate exprs have no direct value form in Sem->Back; use an address/materialization context")
        end,
        [Sem.SemExprArrayLit] = function()
            error("sem_to_back_expr: array literal exprs have no direct value form in Sem->Back; use an address/materialization context")
        end,
        [Sem.SemExprCall] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr: non-scalar call results have no direct value form in Sem->Back; use an address/materialization context")
            end
            local dst = Back.BackValId(path)
            local ret_ty = one_scalar(self.ty)
            local cmds = {}
            local args = {}
            for i = 1, #self.args do
                local arg = one_expr(self.args[i], path .. ".arg." .. i, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                append_expr_cmds(cmds, arg)
                if expr_terminates(arg) then
                    return pvm.once(terminated_expr(cmds))
                end
                args[i] = arg.value
            end
            local call_plan = one_call_value(self.target, dst, ret_ty, path, args, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
            return pvm.once(one_loop_expr_plan(self.loop, path, layout_env, residence_plan))
        end,
        [Sem.SemExprIf] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr: non-scalar if expr results have no direct value form in Sem->Back; use an address/materialization context")
            end
            local dst = Back.BackValId(path)
            local ty = one_scalar(self.ty)
            local cond = one_expr(self.cond, path .. ".cond", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local then_expr = one_expr(self.then_expr, path .. ".then", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local else_expr = one_expr(self.else_expr, path .. ".else", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(then_block)
            append_expr_cmds(cmds, then_expr)
            if expr_has_value(then_expr) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, { then_expr.value })
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(then_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(else_block)
            append_expr_cmds(cmds, else_expr)
            if expr_has_value(else_expr) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, { else_expr.value })
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(else_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                return pvm.once(Back.BackExprPlan(cmds, dst, ty))
            end
            return pvm.once(terminated_expr(cmds))
        end,
        [Sem.SemExprBlock] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr: non-scalar block expr results have no direct value form in Sem->Back; use an address/materialization context")
            end
            local body_cmds, body_flow = lower_stmt_list(self.stmts, path .. ".stmts", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local cmds = {}
            copy_cmds(body_cmds, cmds)
            if body_flow ~= Back.BackFallsThrough then
                return pvm.once(terminated_expr(cmds))
            end
            local result = one_expr(self.result, path .. ".result", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            append_expr_cmds(cmds, result)
            if expr_terminates(result) then
                return pvm.once(terminated_expr(cmds))
            end
            return pvm.once(Back.BackExprPlan(cmds, result.value, one_scalar(self.ty)))
        end,
        [Sem.SemExprSwitch] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(build_switch_expr_value(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
    })

    aux.over_index_value = pvm.phase("sem_to_back_over_index_value", {
        [Sem.SemBindLocalValue] = function(self)
            return pvm.once(local_value_id(self.id))
        end,
        [Sem.SemBindLoopIndex] = function(self)
            return pvm.once(loop_index_value_id(self.loop_id, self.name))
        end,
        [Sem.SemBindLocalCell] = function(self)
            error("sem_to_back_over_index_value: over-loop index binding must be immutable; got mutable local '" .. self.name .. "'")
        end,
        [Sem.SemBindArg] = function(self)
            error("sem_to_back_over_index_value: over-loop index binding must be a local value, not argument '" .. self.name .. "'")
        end,
        [Sem.SemBindGlobalConst] = function(self)
            error("sem_to_back_over_index_value: over-loop index binding must be a local value, not const global '" .. self.item_name .. "'")
        end,
        [Sem.SemBindGlobalStatic] = function(self)
            error("sem_to_back_over_index_value: over-loop index binding must be a local value, not static global '" .. self.item_name .. "'")
        end,
        [Sem.SemBindGlobalFunc] = function(self)
            error("sem_to_back_over_index_value: over-loop index binding must be a local value, not global function '" .. self.item_name .. "'")
        end,
        [Sem.SemBindExtern] = function(self)
            error("sem_to_back_over_index_value: over-loop index binding must be a local value, not extern '" .. self.symbol .. "'")
        end,
    })

    require_index_expr = function(expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
        if not one_type_is_index(one_sem_expr_type(expr)) then
            error(context .. ": expected an explicit SemTIndex expression")
        end
        return one_expr(expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
    end

    require_pointer_expr = function(expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
        if not one_type_is_pointer_like(one_sem_expr_type(expr)) then
            error(context .. ": expected a pointer-typed data expression")
        end
        return one_expr(expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
    end

    aux.bounded_view_value_from_type = pvm.phase("sem_to_back_bounded_view_value_from_type", {
        [Sem.SemTArray] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            local base = one_addr_of_expr(base_expr, path .. ".base", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local data = Back.BackValId(path .. ".data")
            local len = Back.BackValId(path .. ".len")
            local stride = Back.BackValId(path .. ".stride")
            local cmds = {}
            append_expr_cmds(cmds, base)
            if expr_terminates(base) then
                return pvm.once(terminated_view(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdAlias(data, base.value)
            cmds[#cmds + 1] = Back.BackCmdConstInt(len, Back.BackIndex, tostring(self.count))
            cmds[#cmds + 1] = Back.BackCmdConstInt(stride, Back.BackIndex, tostring(one_type_mem_size(self.elem, layout_env)))
            return pvm.once(Back.BackViewPlan(cmds, data, len, stride))
        end,
        [Sem.SemTSlice] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            local base = one_addr_of_expr(base_expr, path .. ".base", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local stride = Back.BackValId(path .. ".stride")
            local cmds = {}
            append_expr_cmds(cmds, base)
            if expr_terminates(base) then
                return pvm.once(terminated_view(cmds))
            end
            local data_cmds, data = load_from_const_offset(base.value, 0, Back.BackPtr, path .. ".data")
            local len_cmds, len = load_from_const_offset(base.value, 8, Back.BackIndex, path .. ".len")
            copy_cmds(data_cmds, cmds)
            copy_cmds(len_cmds, cmds)
            cmds[#cmds + 1] = Back.BackCmdConstInt(stride, Back.BackIndex, tostring(one_type_mem_size(self.elem, layout_env)))
            return pvm.once(Back.BackViewPlan(cmds, data, len, stride))
        end,
        [Sem.SemTView] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            local base = one_addr_of_expr(base_expr, path .. ".base", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local cmds = {}
            append_expr_cmds(cmds, base)
            if expr_terminates(base) then
                return pvm.once(terminated_view(cmds))
            end
            local data_cmds, data = load_from_const_offset(base.value, 0, Back.BackPtr, path .. ".data")
            local len_cmds, len = load_from_const_offset(base.value, 8, Back.BackIndex, path .. ".len")
            local stride_cmds, stride = load_from_const_offset(base.value, 16, Back.BackIndex, path .. ".stride")
            copy_cmds(data_cmds, cmds)
            copy_cmds(len_cmds, cmds)
            copy_cmds(stride_cmds, cmds)
            return pvm.once(Back.BackViewPlan(cmds, data, len, stride))
        end,
        [Sem.SemTPtr] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": raw pointer values have no bounded length; use an explicit SemViewContiguous/SemViewStrided form")
        end,
        [Sem.SemTPtrTo] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": raw pointer values have no bounded length; use an explicit SemViewContiguous/SemViewStrided form")
        end,
        [Sem.SemTVoid] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTBool] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTI8] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTI16] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTI32] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTI64] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTU8] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTU16] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTU32] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTU64] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTF32] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTF64] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTIndex] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTFunc] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
        [Sem.SemTNamed] = function(self, base_expr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, context)
            error(context .. ": bounded view values require array/slice/view typed expressions")
        end,
    })

    aux.lower_bounded_view = pvm.phase("sem_to_back_bounded_view", {
        [Sem.SemViewValue] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(pvm.one(aux.bounded_view_value_from_type(one_sem_expr_type(self.base), self.base, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_bounded_view")))
        end,
        [Sem.SemViewContiguous] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local data = require_pointer_expr(self.data, path .. ".data.expr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_bounded_view")
            local len = require_index_expr(self.len, path .. ".len.expr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_bounded_view")
            local stride = Back.BackValId(path .. ".stride")
            local cmds = {}
            append_expr_cmds(cmds, data)
            if expr_terminates(data) then
                return pvm.once(terminated_view(cmds))
            end
            append_expr_cmds(cmds, len)
            if expr_terminates(len) then
                return pvm.once(terminated_view(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdConstInt(stride, Back.BackIndex, tostring(one_type_mem_size(self.elem, layout_env)))
            return pvm.once(Back.BackViewPlan(cmds, data.value, len.value, stride))
        end,
        [Sem.SemViewStrided] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local data = require_pointer_expr(self.data, path .. ".data.expr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_bounded_view")
            local len = require_index_expr(self.len, path .. ".len.expr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_bounded_view")
            local stride_elems = require_index_expr(self.stride, path .. ".stride.expr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_bounded_view")
            local elem_size = Back.BackValId(path .. ".elem_size")
            local stride = Back.BackValId(path .. ".stride")
            local cmds = {}
            append_expr_cmds(cmds, data)
            if expr_terminates(data) then
                return pvm.once(terminated_view(cmds))
            end
            append_expr_cmds(cmds, len)
            if expr_terminates(len) then
                return pvm.once(terminated_view(cmds))
            end
            append_expr_cmds(cmds, stride_elems)
            if expr_terminates(stride_elems) then
                return pvm.once(terminated_view(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdConstInt(elem_size, Back.BackIndex, tostring(one_type_mem_size(self.elem, layout_env)))
            cmds[#cmds + 1] = one_mul_cmd(Sem.SemTIndex, stride, Back.BackIndex, stride_elems.value, elem_size)
            return pvm.once(Back.BackViewPlan(cmds, data.value, len.value, stride))
        end,
        [Sem.SemViewWindow] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local base = one_bounded_view(self.base, path .. ".base", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local start = require_index_expr(self.start, path .. ".start.expr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_bounded_view")
            local len = require_index_expr(self.len, path .. ".len.expr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_bounded_view")
            local offset = Back.BackValId(path .. ".offset")
            local data = Back.BackValId(path .. ".data")
            local cmds = {}
            append_view_cmds(cmds, base)
            if view_terminates(base) then
                return pvm.once(terminated_view(cmds))
            end
            append_expr_cmds(cmds, start)
            if expr_terminates(start) then
                return pvm.once(terminated_view(cmds))
            end
            append_expr_cmds(cmds, len)
            if expr_terminates(len) then
                return pvm.once(terminated_view(cmds))
            end
            cmds[#cmds + 1] = one_mul_cmd(Sem.SemTIndex, offset, Back.BackIndex, start.value, base.stride)
            cmds[#cmds + 1] = one_add_cmd(Sem.SemTPtr, data, Back.BackPtr, base.data, offset)
            return pvm.once(Back.BackViewPlan(cmds, data, len.value, base.stride))
        end,
        [Sem.SemViewInterleaved] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local data_expr = require_pointer_expr(self.data, path .. ".data.expr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_bounded_view")
            local len = require_index_expr(self.len, path .. ".len.expr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_bounded_view")
            local stride_elems = require_index_expr(self.stride, path .. ".stride.expr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_bounded_view")
            local lane = require_index_expr(self.lane, path .. ".lane.expr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan, "sem_to_back_bounded_view")
            local elem_size = Back.BackValId(path .. ".elem_size")
            local lane_offset = Back.BackValId(path .. ".lane_offset")
            local stride = Back.BackValId(path .. ".stride")
            local data = Back.BackValId(path .. ".data")
            local cmds = {}
            append_expr_cmds(cmds, data_expr)
            if expr_terminates(data_expr) then
                return pvm.once(terminated_view(cmds))
            end
            append_expr_cmds(cmds, len)
            if expr_terminates(len) then
                return pvm.once(terminated_view(cmds))
            end
            append_expr_cmds(cmds, stride_elems)
            if expr_terminates(stride_elems) then
                return pvm.once(terminated_view(cmds))
            end
            append_expr_cmds(cmds, lane)
            if expr_terminates(lane) then
                return pvm.once(terminated_view(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdConstInt(elem_size, Back.BackIndex, tostring(one_type_mem_size(self.elem, layout_env)))
            cmds[#cmds + 1] = one_mul_cmd(Sem.SemTIndex, lane_offset, Back.BackIndex, lane.value, elem_size)
            cmds[#cmds + 1] = one_mul_cmd(Sem.SemTIndex, stride, Back.BackIndex, stride_elems.value, elem_size)
            cmds[#cmds + 1] = one_add_cmd(Sem.SemTPtr, data, Back.BackPtr, data_expr.value, lane_offset)
            return pvm.once(Back.BackViewPlan(cmds, data, len.value, stride))
        end,
    })

    local function build_over_stmt_plan(loop, path, start_plan, stop_plan, layout_env, residence_plan)
        local index_binding = loop_index_binding(loop)
        local index_ty = index_binding.ty
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
            Back.BackCmdCreateBlock(header_block),
            Back.BackCmdCreateBlock(body_block),
            Back.BackCmdCreateBlock(continue_block),
            Back.BackCmdCreateBlock(exit_block),
            Back.BackCmdAppendBlockParam(header_block, header_index, index_back_ty),
            Back.BackCmdAppendBlockParam(body_block, body_index, index_back_ty),
            Back.BackCmdAppendBlockParam(continue_block, continue_index, index_back_ty),
        }
        if binding_residence(index_binding, residence_plan) == Sem.SemResidenceStack then
            table.insert(cmds, 1, Back.BackCmdCreateStackSlot(loop_index_slot_id(index_binding.loop_id, index_binding.name), 8, 8))
        end
        local init_args = {}
        append_expr_cmds(cmds, start_plan)
        if expr_terminates(start_plan) then
            return Back.BackStmtPlan(cmds, Back.BackTerminates)
        end
        init_args[1] = start_plan.value
        for i = 1, #loop.carries do
            local carry = loop.carries[i]
            local carry_spec = one_stack_slot_spec(carry.ty, layout_env)
            if binding_residence(loop_carry_binding(loop.loop_id, carry), residence_plan) == Sem.SemResidenceStack then
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(loop_carry_slot_id(loop.loop_id, carry.port_id), carry_spec.size, carry_spec.align)
            end
            local header_param = Back.BackValId(path .. ".header.carry." .. i)
            local body_param = Back.BackValId(path .. ".body.carry." .. i)
            local continue_param = Back.BackValId(path .. ".continue.carry." .. i)
            header_carry_params[i] = header_param
            body_carry_params[i] = body_param
            continue_carry_params[i] = continue_param
            header_jump_args[#header_jump_args + 1] = header_param
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(carry.ty))
            local init = one_plain_expr(carry.init, path .. ".carry_init." .. i, layout_env, residence_plan)
            append_expr_cmds(cmds, init)
            if expr_terminates(init) then
                return Back.BackStmtPlan(cmds, Back.BackTerminates)
            end
            init_args[#init_args + 1] = init.value
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_args)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
        emit_alias_for_index_binding(cmds, index_binding, header_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, header_carry_params, loop.loop_id, residence_plan)
        append_expr_cmds(cmds, stop_plan)
        if expr_terminates(stop_plan) then
            return Back.BackStmtPlan(cmds, Back.BackTerminates)
        end
        local cond_value = Back.BackValId(path .. ".cond")
        cmds[#cmds + 1] = one_lt_cmd(index_ty, cond_value, Back.BackBool, header_index, stop_plan.value)
        cmds[#cmds + 1] = Back.BackCmdBrIf(cond_value, body_block, header_jump_args, exit_block, {})
        cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
        emit_alias_for_index_binding(cmds, index_binding, body_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, body_carry_params, loop.loop_id, residence_plan)
        local body_current_args = over_loop_current_args(body_index, body_carry_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, exit_block, {}, continue_block, body_current_args, residence_plan)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
        emit_alias_for_index_binding(cmds, index_binding, continue_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, continue_carry_params, loop.loop_id, residence_plan)
        local one_id = Back.BackValId(path .. ".index.step")
        local next_index = Back.BackValId(path .. ".index.next")
        local next_cmds, next_values, next_flow = eval_loop_nexts(loop.carries, loop.next, path, layout_env, residence_plan)
        cmds[#cmds + 1] = Back.BackCmdConstInt(one_id, index_back_ty, "1")
        cmds[#cmds + 1] = one_add_cmd(index_ty, next_index, index_back_ty, continue_index, one_id)
        copy_cmds(next_cmds, cmds)
        if next_flow == Back.BackTerminates then
            return Back.BackStmtPlan(cmds, Back.BackTerminates)
        end
        local jump_args = { next_index }
        for i = 1, #next_values do
            jump_args[#jump_args + 1] = next_values[i]
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, jump_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
        return Back.BackStmtPlan(cmds, Back.BackFallsThrough)
    end

    local function build_over_expr_end_only_plan(loop, path, start_plan, stop_plan, layout_env, residence_plan)
        local index_binding = loop_index_binding(loop)
        local index_ty = index_binding.ty
        local result_ty = one_sem_expr_type(loop.result)
        local result_back_ty = one_scalar(result_ty)
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
        local dst = Back.BackValId(path)
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
        if binding_residence(index_binding, residence_plan) == Sem.SemResidenceStack then
            table.insert(cmds, 1, Back.BackCmdCreateStackSlot(loop_index_slot_id(index_binding.loop_id, index_binding.name), 8, 8))
        end
        local init_args = {}
        append_expr_cmds(cmds, start_plan)
        if expr_terminates(start_plan) then
            return terminated_expr(cmds)
        end
        init_args[1] = start_plan.value
        for i = 1, #loop.carries do
            local carry = loop.carries[i]
            local carry_spec = one_stack_slot_spec(carry.ty, layout_env)
            if binding_residence(loop_carry_binding(loop.loop_id, carry), residence_plan) == Sem.SemResidenceStack then
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(loop_carry_slot_id(loop.loop_id, carry.port_id), carry_spec.size, carry_spec.align)
            end
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
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit_block, exit_param, one_scalar(carry.ty))
            local init = one_plain_expr(carry.init, path .. ".carry_init." .. i, layout_env, residence_plan)
            append_expr_cmds(cmds, init)
            if expr_terminates(init) then
                return terminated_expr(cmds)
            end
            init_args[#init_args + 1] = init.value
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_args)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
        emit_alias_for_index_binding(cmds, index_binding, header_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, header_carry_params, loop.loop_id, residence_plan)
        append_expr_cmds(cmds, stop_plan)
        if expr_terminates(stop_plan) then
            return terminated_expr(cmds)
        end
        local cond_value = Back.BackValId(path .. ".cond")
        cmds[#cmds + 1] = one_lt_cmd(index_ty, cond_value, Back.BackBool, header_index, stop_plan.value)
        cmds[#cmds + 1] = Back.BackCmdBrIf(cond_value, body_block, header_jump_args, exit_block, exit_jump_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
        emit_alias_for_index_binding(cmds, index_binding, body_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, body_carry_params, loop.loop_id, residence_plan)
        local body_current_args = over_loop_current_args(body_index, body_carry_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, nil, nil, continue_block, body_current_args, residence_plan)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
        emit_alias_for_index_binding(cmds, index_binding, continue_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, continue_carry_params, loop.loop_id, residence_plan)
        local one_id = Back.BackValId(path .. ".index.step")
        local next_index = Back.BackValId(path .. ".index.next")
        local next_cmds, next_values, next_flow = eval_loop_nexts(loop.carries, loop.next, path, layout_env, residence_plan)
        cmds[#cmds + 1] = Back.BackCmdConstInt(one_id, index_back_ty, "1")
        cmds[#cmds + 1] = one_add_cmd(index_ty, next_index, index_back_ty, continue_index, one_id)
        copy_cmds(next_cmds, cmds)
        if next_flow == Back.BackTerminates then
            return terminated_expr(cmds)
        end
        local jump_args = { next_index }
        for i = 1, #next_values do
            jump_args[#jump_args + 1] = next_values[i]
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, jump_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
        emit_alias_for_index_binding(cmds, index_binding, exit_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, exit_carry_params, loop.loop_id, residence_plan)
        local result = one_plain_expr(loop.result, path .. ".result", layout_env, residence_plan)
        append_expr_cmds(cmds, result)
        if expr_terminates(result) then
            return terminated_expr(cmds)
        end
        return Back.BackExprPlan(cmds, result.value, result_back_ty)
    end

    local function build_over_expr_plan(loop, path, start_plan, stop_plan, layout_env, residence_plan)
        local index_binding = loop_index_binding(loop)
        local index_ty = index_binding.ty
        local result_ty = one_sem_expr_type(loop.result)
        local result_back_ty = one_scalar(result_ty)
        local index_back_ty = one_scalar(index_ty)
        local header_block = Back.BackBlockId(path .. ".header.block")
        local body_block = Back.BackBlockId(path .. ".body.block")
        local continue_block = Back.BackBlockId(path .. ".continue.block")
        local exit_block = Back.BackBlockId(path .. ".exit.block")
        local normal_block = Back.BackBlockId(path .. ".normal.block")
        local break_taken_block = Back.BackBlockId(path .. ".break_taken.block")
        local join_block = Back.BackBlockId(path .. ".join.block")
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
        local break_flag_slot = break_value_flag_slot_id(exit_block)
        local break_value_slot = break_value_value_slot_id(exit_block)
        local break_flag_addr = Back.BackValId(path .. ".break.flag.addr")
        local break_flag_init = Back.BackValId(path .. ".break.flag.init")
        local break_flag_value = Back.BackValId(path .. ".break.flag.value")
        local break_value_addr = Back.BackValId(path .. ".break.value.addr")
        local break_loaded_value = Back.BackValId(path .. ".break.value.loaded")
        local dst = Back.BackValId(path)
        local result_spec = one_stack_slot_spec(result_ty, layout_env)
        local cmds = {
            Back.BackCmdCreateStackSlot(break_flag_slot, 1, 1),
            Back.BackCmdCreateStackSlot(break_value_slot, result_spec.size, result_spec.align),
            Back.BackCmdCreateBlock(header_block),
            Back.BackCmdCreateBlock(body_block),
            Back.BackCmdCreateBlock(continue_block),
            Back.BackCmdCreateBlock(exit_block),
            Back.BackCmdCreateBlock(normal_block),
            Back.BackCmdCreateBlock(break_taken_block),
            Back.BackCmdCreateBlock(join_block),
            Back.BackCmdAppendBlockParam(header_block, header_index, index_back_ty),
            Back.BackCmdAppendBlockParam(body_block, body_index, index_back_ty),
            Back.BackCmdAppendBlockParam(continue_block, continue_index, index_back_ty),
            Back.BackCmdAppendBlockParam(exit_block, exit_index, index_back_ty),
            Back.BackCmdAppendBlockParam(join_block, dst, result_back_ty),
            Back.BackCmdStackAddr(break_flag_addr, break_flag_slot),
            Back.BackCmdStackAddr(break_value_addr, break_value_slot),
            Back.BackCmdConstBool(break_flag_init, false),
            Back.BackCmdStore(Back.BackBool, break_flag_addr, break_flag_init),
        }
        if binding_residence(index_binding, residence_plan) == Sem.SemResidenceStack then
            table.insert(cmds, 1, Back.BackCmdCreateStackSlot(loop_index_slot_id(index_binding.loop_id, index_binding.name), 8, 8))
        end
        local init_args = {}
        append_expr_cmds(cmds, start_plan)
        if expr_terminates(start_plan) then
            return terminated_expr(cmds)
        end
        init_args[1] = start_plan.value
        for i = 1, #loop.carries do
            local carry = loop.carries[i]
            local carry_spec = one_stack_slot_spec(carry.ty, layout_env)
            if binding_residence(loop_carry_binding(loop.loop_id, carry), residence_plan) == Sem.SemResidenceStack then
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(loop_carry_slot_id(loop.loop_id, carry.port_id), carry_spec.size, carry_spec.align)
            end
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
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit_block, exit_param, one_scalar(carry.ty))
            local init = one_plain_expr(carry.init, path .. ".carry_init." .. i, layout_env, residence_plan)
            append_expr_cmds(cmds, init)
            if expr_terminates(init) then
                return terminated_expr(cmds)
            end
            init_args[#init_args + 1] = init.value
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_args)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
        emit_alias_for_index_binding(cmds, index_binding, header_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, header_carry_params, loop.loop_id, residence_plan)
        append_expr_cmds(cmds, stop_plan)
        if expr_terminates(stop_plan) then
            return terminated_expr(cmds)
        end
        local cond_value = Back.BackValId(path .. ".cond")
        cmds[#cmds + 1] = one_lt_cmd(index_ty, cond_value, Back.BackBool, header_index, stop_plan.value)
        cmds[#cmds + 1] = Back.BackCmdBrIf(cond_value, body_block, header_jump_args, exit_block, exit_jump_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
        emit_alias_for_index_binding(cmds, index_binding, body_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, body_carry_params, loop.loop_id, residence_plan)
        local body_current_args = over_loop_current_args(body_index, body_carry_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, exit_block, body_current_args, continue_block, body_current_args, residence_plan)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
        emit_alias_for_index_binding(cmds, index_binding, continue_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, continue_carry_params, loop.loop_id, residence_plan)
        local one_id = Back.BackValId(path .. ".index.step")
        local next_index = Back.BackValId(path .. ".index.next")
        local next_cmds, next_values, next_flow = eval_loop_nexts(loop.carries, loop.next, path, layout_env, residence_plan)
        cmds[#cmds + 1] = Back.BackCmdConstInt(one_id, index_back_ty, "1")
        cmds[#cmds + 1] = one_add_cmd(index_ty, next_index, index_back_ty, continue_index, one_id)
        copy_cmds(next_cmds, cmds)
        if next_flow == Back.BackTerminates then
            return terminated_expr(cmds)
        end
        local jump_args = { next_index }
        for i = 1, #next_values do
            jump_args[#jump_args + 1] = next_values[i]
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, jump_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
        emit_alias_for_index_binding(cmds, index_binding, exit_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, exit_carry_params, loop.loop_id, residence_plan)
        cmds[#cmds + 1] = Back.BackCmdLoad(break_flag_value, Back.BackBool, break_flag_addr)
        cmds[#cmds + 1] = Back.BackCmdBrIf(break_flag_value, break_taken_block, {}, normal_block, {})
        cmds[#cmds + 1] = Back.BackCmdSealBlock(break_taken_block)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(normal_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(break_taken_block)
        cmds[#cmds + 1] = Back.BackCmdLoad(break_loaded_value, result_back_ty, break_value_addr)
        cmds[#cmds + 1] = Back.BackCmdJump(join_block, { break_loaded_value })
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(normal_block)
        local result = one_plain_expr(loop.result, path .. ".result", layout_env, residence_plan)
        append_expr_cmds(cmds, result)
        if expr_has_value(result) then
            cmds[#cmds + 1] = Back.BackCmdJump(join_block, { result.value })
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
        return Back.BackExprPlan(cmds, dst, result_back_ty)
    end

    local function build_over_expr_end_only_into_addr(loop, addr, path, start_plan, stop_plan, layout_env, residence_plan)
        local index_binding = loop_index_binding(loop)
        local index_ty = index_binding.ty
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
            Back.BackCmdCreateBlock(header_block),
            Back.BackCmdCreateBlock(body_block),
            Back.BackCmdCreateBlock(continue_block),
            Back.BackCmdCreateBlock(exit_block),
            Back.BackCmdAppendBlockParam(header_block, header_index, index_back_ty),
            Back.BackCmdAppendBlockParam(body_block, body_index, index_back_ty),
            Back.BackCmdAppendBlockParam(continue_block, continue_index, index_back_ty),
            Back.BackCmdAppendBlockParam(exit_block, exit_index, index_back_ty),
        }
        if binding_residence(index_binding, residence_plan) == Sem.SemResidenceStack then
            table.insert(cmds, 1, Back.BackCmdCreateStackSlot(loop_index_slot_id(index_binding.loop_id, index_binding.name), 8, 8))
        end
        local init_args = {}
        append_expr_cmds(cmds, start_plan)
        if expr_terminates(start_plan) then
            return terminated_addr(cmds)
        end
        init_args[1] = start_plan.value
        for i = 1, #loop.carries do
            local carry = loop.carries[i]
            local carry_spec = one_stack_slot_spec(carry.ty, layout_env)
            if binding_residence(loop_carry_binding(loop.loop_id, carry), residence_plan) == Sem.SemResidenceStack then
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(loop_carry_slot_id(loop.loop_id, carry.port_id), carry_spec.size, carry_spec.align)
            end
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
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit_block, exit_param, one_scalar(carry.ty))
            local init = one_plain_expr(carry.init, path .. ".carry_init." .. i, layout_env, residence_plan)
            append_expr_cmds(cmds, init)
            if expr_terminates(init) then
                return terminated_addr(cmds)
            end
            init_args[#init_args + 1] = init.value
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_args)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
        emit_alias_for_index_binding(cmds, index_binding, header_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, header_carry_params, loop.loop_id, residence_plan)
        append_expr_cmds(cmds, stop_plan)
        if expr_terminates(stop_plan) then
            return terminated_addr(cmds)
        end
        local cond_value = Back.BackValId(path .. ".cond")
        cmds[#cmds + 1] = one_lt_cmd(index_ty, cond_value, Back.BackBool, header_index, stop_plan.value)
        cmds[#cmds + 1] = Back.BackCmdBrIf(cond_value, body_block, header_jump_args, exit_block, exit_jump_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
        emit_alias_for_index_binding(cmds, index_binding, body_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, body_carry_params, loop.loop_id, residence_plan)
        local body_current_args = over_loop_current_args(body_index, body_carry_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, nil, nil, continue_block, body_current_args, residence_plan)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
        emit_alias_for_index_binding(cmds, index_binding, continue_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, continue_carry_params, loop.loop_id, residence_plan)
        local one_id = Back.BackValId(path .. ".index.step")
        local next_index = Back.BackValId(path .. ".index.next")
        local next_cmds, next_values, next_flow = eval_loop_nexts(loop.carries, loop.next, path, layout_env, residence_plan)
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
        cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
        emit_alias_for_index_binding(cmds, index_binding, exit_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, exit_carry_params, loop.loop_id, residence_plan)
        local result = one_plain_expr_into_addr(loop.result, addr, path .. ".result", layout_env, residence_plan)
        append_addr_cmds(cmds, result)
        if addr_terminates(result) then
            return terminated_addr(cmds)
        end
        return addr_writes(cmds)
    end

    local function build_over_expr_into_addr(loop, addr, path, start_plan, stop_plan, layout_env, residence_plan)
        local index_binding = loop_index_binding(loop)
        local index_ty = index_binding.ty
        local result_ty = one_sem_expr_type(loop.result)
        local result_spec = one_stack_slot_spec(result_ty, layout_env)
        local index_back_ty = one_scalar(index_ty)
        local header_block = Back.BackBlockId(path .. ".header.block")
        local body_block = Back.BackBlockId(path .. ".body.block")
        local continue_block = Back.BackBlockId(path .. ".continue.block")
        local exit_block = Back.BackBlockId(path .. ".exit.block")
        local normal_block = Back.BackBlockId(path .. ".normal.block")
        local break_taken_block = Back.BackBlockId(path .. ".break_taken.block")
        local join_block = Back.BackBlockId(path .. ".join.block")
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
        local break_flag_slot = break_value_flag_slot_id(exit_block)
        local break_value_slot = break_value_value_slot_id(exit_block)
        local break_flag_addr = Back.BackValId(path .. ".break.flag.addr")
        local break_flag_init = Back.BackValId(path .. ".break.flag.init")
        local break_flag_value = Back.BackValId(path .. ".break.flag.value")
        local break_value_addr = Back.BackValId(path .. ".break.value.addr")
        local cmds = {
            Back.BackCmdCreateStackSlot(break_flag_slot, 1, 1),
            Back.BackCmdCreateStackSlot(break_value_slot, result_spec.size, result_spec.align),
            Back.BackCmdCreateBlock(header_block),
            Back.BackCmdCreateBlock(body_block),
            Back.BackCmdCreateBlock(continue_block),
            Back.BackCmdCreateBlock(exit_block),
            Back.BackCmdCreateBlock(normal_block),
            Back.BackCmdCreateBlock(break_taken_block),
            Back.BackCmdCreateBlock(join_block),
            Back.BackCmdAppendBlockParam(header_block, header_index, index_back_ty),
            Back.BackCmdAppendBlockParam(body_block, body_index, index_back_ty),
            Back.BackCmdAppendBlockParam(continue_block, continue_index, index_back_ty),
            Back.BackCmdAppendBlockParam(exit_block, exit_index, index_back_ty),
            Back.BackCmdStackAddr(break_flag_addr, break_flag_slot),
            Back.BackCmdStackAddr(break_value_addr, break_value_slot),
            Back.BackCmdConstBool(break_flag_init, false),
            Back.BackCmdStore(Back.BackBool, break_flag_addr, break_flag_init),
        }
        if binding_residence(index_binding, residence_plan) == Sem.SemResidenceStack then
            table.insert(cmds, 1, Back.BackCmdCreateStackSlot(loop_index_slot_id(index_binding.loop_id, index_binding.name), 8, 8))
        end
        local init_args = {}
        append_expr_cmds(cmds, start_plan)
        if expr_terminates(start_plan) then
            return terminated_addr(cmds)
        end
        init_args[1] = start_plan.value
        for i = 1, #loop.carries do
            local carry = loop.carries[i]
            local carry_spec = one_stack_slot_spec(carry.ty, layout_env)
            if binding_residence(loop_carry_binding(loop.loop_id, carry), residence_plan) == Sem.SemResidenceStack then
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(loop_carry_slot_id(loop.loop_id, carry.port_id), carry_spec.size, carry_spec.align)
            end
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
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit_block, exit_param, one_scalar(carry.ty))
            local init = one_plain_expr(carry.init, path .. ".carry_init." .. i, layout_env, residence_plan)
            append_expr_cmds(cmds, init)
            if expr_terminates(init) then
                return terminated_addr(cmds)
            end
            init_args[#init_args + 1] = init.value
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_args)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
        emit_alias_for_index_binding(cmds, index_binding, header_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, header_carry_params, loop.loop_id, residence_plan)
        append_expr_cmds(cmds, stop_plan)
        if expr_terminates(stop_plan) then
            return terminated_addr(cmds)
        end
        local cond_value = Back.BackValId(path .. ".cond")
        cmds[#cmds + 1] = one_lt_cmd(index_ty, cond_value, Back.BackBool, header_index, stop_plan.value)
        cmds[#cmds + 1] = Back.BackCmdBrIf(cond_value, body_block, header_jump_args, exit_block, exit_jump_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
        emit_alias_for_index_binding(cmds, index_binding, body_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, body_carry_params, loop.loop_id, residence_plan)
        local body_current_args = over_loop_current_args(body_index, body_carry_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, exit_block, body_current_args, continue_block, body_current_args, residence_plan)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
        emit_alias_for_index_binding(cmds, index_binding, continue_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, continue_carry_params, loop.loop_id, residence_plan)
        local one_id = Back.BackValId(path .. ".index.step")
        local next_index = Back.BackValId(path .. ".index.next")
        local next_cmds, next_values, next_flow = eval_loop_nexts(loop.carries, loop.next, path, layout_env, residence_plan)
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
        cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
        emit_alias_for_index_binding(cmds, index_binding, exit_index, residence_plan)
        emit_aliases_for_loop_bindings(cmds, loop.carries, exit_carry_params, loop.loop_id, residence_plan)
        cmds[#cmds + 1] = Back.BackCmdLoad(break_flag_value, Back.BackBool, break_flag_addr)
        cmds[#cmds + 1] = Back.BackCmdBrIf(break_flag_value, break_taken_block, {}, normal_block, {})
        cmds[#cmds + 1] = Back.BackCmdSealBlock(break_taken_block)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(normal_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(break_taken_block)
        copy_cmds(one_copy_type_addr(result_ty, break_value_addr, addr, path .. ".break.copy", layout_env), cmds)
        cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(normal_block)
        local result = one_plain_expr_into_addr(loop.result, addr, path .. ".result", layout_env, residence_plan)
        append_addr_cmds(cmds, result)
        if addr_continues(result) then
            cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
        if addr_terminates(result) then
            return terminated_addr(cmds)
        end
        return addr_writes(cmds)
    end

    local function build_zip_eq_view_prefix(views, path, layout_env, residence_plan)
        local cmds = {}
        if #views == 0 then
            local zero = Back.BackValId(path .. ".len")
            cmds[#cmds + 1] = Back.BackCmdConstInt(zero, Back.BackIndex, "0")
            return cmds, zero, Back.BackFallsThrough
        end
        local first = one_plain_bounded_view(views[1], path .. ".view.1", layout_env, residence_plan)
        append_view_cmds(cmds, first)
        if view_terminates(first) then
            return cmds, nil, Back.BackTerminates
        end
        local expected = first.len
        for i = 2, #views do
            local view = one_plain_bounded_view(views[i], path .. ".view." .. i, layout_env, residence_plan)
            append_view_cmds(cmds, view)
            if view_terminates(view) then
                return cmds, nil, Back.BackTerminates
            end
            local match = Back.BackValId(path .. ".match." .. i)
            local ok_block = Back.BackBlockId(path .. ".ok." .. i)
            local fail_block = Back.BackBlockId(path .. ".fail." .. i)
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(ok_block)
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(fail_block)
            cmds[#cmds + 1] = one_eq_cmd(Sem.SemTIndex, match, Back.BackBool, expected, view.len)
            cmds[#cmds + 1] = Back.BackCmdBrIf(match, ok_block, {}, fail_block, {})
            cmds[#cmds + 1] = Back.BackCmdSealBlock(ok_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(fail_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(fail_block)
            cmds[#cmds + 1] = Back.BackCmdTrap
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(ok_block)
        end
        return cmds, expected, Back.BackFallsThrough
    end

    lower_over_stmt_domain = pvm.phase("sem_to_back_over_stmt_domain", {
        [Sem.SemDomainRange] = function(self, loop, path, layout_env, residence_plan)
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty))
            return pvm.once(build_over_stmt_plan(loop, path, start, one_plain_expr(self.stop, path .. ".stop", layout_env, residence_plan), layout_env, residence_plan))
        end,
        [Sem.SemDomainRange2] = function(self, loop, path, layout_env, residence_plan)
            return pvm.once(build_over_stmt_plan(loop, path, one_plain_expr(self.start, path .. ".start", layout_env, residence_plan), one_plain_expr(self.stop, path .. ".stop", layout_env, residence_plan), layout_env, residence_plan))
        end,
        [Sem.SemDomainView] = function(self, loop, path, layout_env, residence_plan)
            local view = one_plain_bounded_view(self.view, path .. ".view", layout_env, residence_plan)
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty))
            local stop = Back.BackExprPlan({}, view.len, Back.BackIndex)
            return pvm.once(prefix_stmt_plan_with_view(view, build_over_stmt_plan(loop, path, start, stop, layout_env, residence_plan)))
        end,
        [Sem.SemDomainZipEq] = function(self, loop, path, layout_env, residence_plan)
            local cmds, len, flow = build_zip_eq_view_prefix(self.views, path .. ".zip", layout_env, residence_plan)
            if flow == Back.BackTerminates then
                return pvm.once(Back.BackStmtPlan(cmds, flow))
            end
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty))
            local stop = Back.BackExprPlan({}, len, Back.BackIndex)
            local plan = build_over_stmt_plan(loop, path, start, stop, layout_env, residence_plan)
            copy_cmds(plan.cmds, cmds)
            return pvm.once(Back.BackStmtPlan(cmds, plan.flow))
        end,
    })

    lower_over_expr_domain = pvm.phase("sem_to_back_over_expr_domain", {
        [Sem.SemDomainRange] = function(self, loop, path, layout_env, residence_plan)
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty))
            if loop.exit == Sem.SemLoopExprEndOnly then
                return pvm.once(build_over_expr_end_only_plan(loop, path, start, one_plain_expr(self.stop, path .. ".stop", layout_env, residence_plan), layout_env, residence_plan))
            end
            return pvm.once(build_over_expr_plan(loop, path, start, one_plain_expr(self.stop, path .. ".stop", layout_env, residence_plan), layout_env, residence_plan))
        end,
        [Sem.SemDomainRange2] = function(self, loop, path, layout_env, residence_plan)
            if loop.exit == Sem.SemLoopExprEndOnly then
                return pvm.once(build_over_expr_end_only_plan(loop, path, one_plain_expr(self.start, path .. ".start", layout_env, residence_plan), one_plain_expr(self.stop, path .. ".stop", layout_env, residence_plan), layout_env, residence_plan))
            end
            return pvm.once(build_over_expr_plan(loop, path, one_plain_expr(self.start, path .. ".start", layout_env, residence_plan), one_plain_expr(self.stop, path .. ".stop", layout_env, residence_plan), layout_env, residence_plan))
        end,
        [Sem.SemDomainView] = function(self, loop, path, layout_env, residence_plan)
            local view = one_plain_bounded_view(self.view, path .. ".view", layout_env, residence_plan)
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty))
            local stop = Back.BackExprPlan({}, view.len, Back.BackIndex)
            if loop.exit == Sem.SemLoopExprEndOnly then
                return pvm.once(prefix_expr_plan_with_view(view, build_over_expr_end_only_plan(loop, path, start, stop, layout_env, residence_plan)))
            end
            return pvm.once(prefix_expr_plan_with_view(view, build_over_expr_plan(loop, path, start, stop, layout_env, residence_plan)))
        end,
        [Sem.SemDomainZipEq] = function(self, loop, path, layout_env, residence_plan)
            local cmds, len, flow = build_zip_eq_view_prefix(self.views, path .. ".zip", layout_env, residence_plan)
            if flow == Back.BackTerminates then
                return pvm.once(terminated_expr(cmds))
            end
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty))
            local stop = Back.BackExprPlan({}, len, Back.BackIndex)
            local plan
            if loop.exit == Sem.SemLoopExprEndOnly then
                plan = build_over_expr_end_only_plan(loop, path, start, stop, layout_env, residence_plan)
            else
                plan = build_over_expr_plan(loop, path, start, stop, layout_env, residence_plan)
            end
            copy_cmds(plan.cmds, cmds)
            return pvm.once(Back.BackExprPlan(cmds, plan.value, plan.ty))
        end,
    })

    lower_over_expr_into_addr_domain = pvm.phase("sem_to_back_over_expr_into_addr_domain", {
        [Sem.SemDomainRange] = function(self, loop, addr, path, layout_env, residence_plan)
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty))
            if loop.exit == Sem.SemLoopExprEndOnly then
                return pvm.once(build_over_expr_end_only_into_addr(loop, addr, path, start, one_plain_expr(self.stop, path .. ".stop", layout_env, residence_plan), layout_env, residence_plan))
            end
            return pvm.once(build_over_expr_into_addr(loop, addr, path, start, one_plain_expr(self.stop, path .. ".stop", layout_env, residence_plan), layout_env, residence_plan))
        end,
        [Sem.SemDomainRange2] = function(self, loop, addr, path, layout_env, residence_plan)
            if loop.exit == Sem.SemLoopExprEndOnly then
                return pvm.once(build_over_expr_end_only_into_addr(loop, addr, path, one_plain_expr(self.start, path .. ".start", layout_env, residence_plan), one_plain_expr(self.stop, path .. ".stop", layout_env, residence_plan), layout_env, residence_plan))
            end
            return pvm.once(build_over_expr_into_addr(loop, addr, path, one_plain_expr(self.start, path .. ".start", layout_env, residence_plan), one_plain_expr(self.stop, path .. ".stop", layout_env, residence_plan), layout_env, residence_plan))
        end,
        [Sem.SemDomainView] = function(self, loop, addr, path, layout_env, residence_plan)
            local view = one_plain_bounded_view(self.view, path .. ".view", layout_env, residence_plan)
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty))
            local stop = Back.BackExprPlan({}, view.len, Back.BackIndex)
            if loop.exit == Sem.SemLoopExprEndOnly then
                return pvm.once(prefix_addr_plan_with_view(view, build_over_expr_end_only_into_addr(loop, addr, path, start, stop, layout_env, residence_plan)))
            end
            return pvm.once(prefix_addr_plan_with_view(view, build_over_expr_into_addr(loop, addr, path, start, stop, layout_env, residence_plan)))
        end,
        [Sem.SemDomainZipEq] = function(self, loop, addr, path, layout_env, residence_plan)
            local cmds, len, flow = build_zip_eq_view_prefix(self.views, path .. ".zip", layout_env, residence_plan)
            if flow == Back.BackTerminates then
                return pvm.once(terminated_addr(cmds))
            end
            local start = Back.BackExprPlan({
                Back.BackCmdConstInt(Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty), "0"),
            }, Back.BackValId(path .. ".start"), one_scalar(loop.index_port.ty))
            local stop = Back.BackExprPlan({}, len, Back.BackIndex)
            local plan
            if loop.exit == Sem.SemLoopExprEndOnly then
                plan = build_over_expr_end_only_into_addr(loop, addr, path, start, stop, layout_env, residence_plan)
            else
                plan = build_over_expr_into_addr(loop, addr, path, start, stop, layout_env, residence_plan)
            end
            append_addr_cmds(cmds, plan)
            if addr_terminates(plan) then
                return pvm.once(terminated_addr(cmds))
            end
            return pvm.once(addr_writes(cmds))
        end,
    })

    lower_loop_stmt_plan = pvm.phase("sem_to_back_loop_stmt", {
        [Sem.SemLoopWhileStmt] = function(self, path, layout_env, residence_plan)
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
            for i = 1, #self.carries do
                local carry = self.carries[i]
                local carry_spec = one_stack_slot_spec(carry.ty, layout_env)
                if binding_residence(loop_carry_binding(self.loop_id, carry), residence_plan) == Sem.SemResidenceStack then
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(loop_carry_slot_id(self.loop_id, carry.port_id), carry_spec.size, carry_spec.align)
            end
                local header_param = Back.BackValId(path .. ".header.param." .. i)
                local body_param = Back.BackValId(path .. ".body.param." .. i)
                local continue_param = Back.BackValId(path .. ".continue.param." .. i)
                header_params[i] = header_param
                body_params[i] = body_param
                continue_params[i] = continue_param
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(carry.ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(carry.ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(carry.ty))
                local init = one_plain_expr(carry.init, path .. ".init." .. i, layout_env, residence_plan)
                append_expr_cmds(cmds, init)
                if expr_terminates(init) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
                init_values[i] = init.value
            end
            cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_values)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
            emit_aliases_for_loop_bindings(cmds, self.carries, header_params, self.loop_id, residence_plan)
            local cond = one_plain_expr(self.cond, path .. ".cond", layout_env, residence_plan)
            append_expr_cmds(cmds, cond)
            if expr_terminates(cond) then
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
            end
            cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, body_block, header_params, exit_block, {})
            cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
            emit_aliases_for_loop_bindings(cmds, self.carries, body_params, self.loop_id, residence_plan)
            local body_current_args = loop_binding_value_args(body_params)
            local body_cmds, body_flow = lower_stmt_list(self.body, path .. ".body", layout_env, exit_block, {}, continue_block, body_current_args, residence_plan)
            copy_cmds(body_cmds, cmds)
            if body_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
            emit_aliases_for_loop_bindings(cmds, self.carries, continue_params, self.loop_id, residence_plan)
            local next_cmds, next_values, next_flow = eval_loop_nexts(self.carries, self.next, path, layout_env, residence_plan)
            copy_cmds(next_cmds, cmds)
            if next_flow == Back.BackTerminates then
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
            end
            cmds[#cmds + 1] = Back.BackCmdJump(header_block, next_values)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
        end,
        [Sem.SemLoopOverStmt] = function(self, path, layout_env, residence_plan)
            return pvm.once(one_over_stmt_domain(self.domain, self, path, layout_env, residence_plan))
        end,
        [Sem.SemLoopWhileExpr] = function()
            error("sem_to_back_loop_stmt: expected stmt loop, got expr loop")
        end,
        [Sem.SemLoopOverExpr] = function()
            error("sem_to_back_loop_stmt: expected stmt loop, got expr loop")
        end,
    })

    local function build_while_expr_end_only_plan(loop, path, layout_env, residence_plan)
        local result_ty = one_sem_expr_type(loop.result)
        local result_back_ty = one_scalar(result_ty)
        local header_block = Back.BackBlockId(path .. ".header.block")
        local body_block = Back.BackBlockId(path .. ".body.block")
        local continue_block = Back.BackBlockId(path .. ".continue.block")
        local exit_block = Back.BackBlockId(path .. ".exit.block")
        local header_params = {}
        local body_params = {}
        local continue_params = {}
        local exit_params = {}
        local dst = Back.BackValId(path)
        local cmds = {
            Back.BackCmdCreateBlock(header_block),
            Back.BackCmdCreateBlock(body_block),
            Back.BackCmdCreateBlock(continue_block),
            Back.BackCmdCreateBlock(exit_block),
        }
        local init_values = {}
        for i = 1, #loop.carries do
            local carry = loop.carries[i]
            local carry_spec = one_stack_slot_spec(carry.ty, layout_env)
            if binding_residence(loop_carry_binding(loop.loop_id, carry), residence_plan) == Sem.SemResidenceStack then
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(loop_carry_slot_id(loop.loop_id, carry.port_id), carry_spec.size, carry_spec.align)
            end
            local header_param = Back.BackValId(path .. ".header.param." .. i)
            local body_param = Back.BackValId(path .. ".body.param." .. i)
            local continue_param = Back.BackValId(path .. ".continue.param." .. i)
            local exit_param = Back.BackValId(path .. ".exit.param." .. i)
            header_params[i] = header_param
            body_params[i] = body_param
            continue_params[i] = continue_param
            exit_params[i] = exit_param
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit_block, exit_param, one_scalar(carry.ty))
            local init = one_plain_expr(carry.init, path .. ".init." .. i, layout_env, residence_plan)
            append_expr_cmds(cmds, init)
            if expr_terminates(init) then
                return terminated_expr(cmds)
            end
            init_values[i] = init.value
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_values)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
        emit_aliases_for_loop_bindings(cmds, loop.carries, header_params, loop.loop_id, residence_plan)
        local cond = one_plain_expr(loop.cond, path .. ".cond", layout_env, residence_plan)
        append_expr_cmds(cmds, cond)
        if expr_terminates(cond) then
            return terminated_expr(cmds)
        end
        cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, body_block, header_params, exit_block, header_params)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
        emit_aliases_for_loop_bindings(cmds, loop.carries, body_params, loop.loop_id, residence_plan)
        local body_current_args = loop_binding_value_args(body_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, nil, nil, continue_block, body_current_args, residence_plan)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
        emit_aliases_for_loop_bindings(cmds, loop.carries, continue_params, loop.loop_id, residence_plan)
        local next_cmds, next_values, next_flow = eval_loop_nexts(loop.carries, loop.next, path, layout_env, residence_plan)
        copy_cmds(next_cmds, cmds)
        if next_flow == Back.BackTerminates then
            return terminated_expr(cmds)
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, next_values)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
        emit_aliases_for_loop_bindings(cmds, loop.carries, exit_params, loop.loop_id, residence_plan)
        local result = one_plain_expr(loop.result, path .. ".result", layout_env, residence_plan)
        append_expr_cmds(cmds, result)
        if expr_terminates(result) then
            return terminated_expr(cmds)
        end
        return Back.BackExprPlan(cmds, result.value, result_back_ty)
    end

    local function build_while_expr_end_only_into_addr(loop, addr, path, layout_env, residence_plan)
        local result_ty = one_sem_expr_type(loop.result)
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
        for i = 1, #loop.carries do
            local carry = loop.carries[i]
            local carry_spec = one_stack_slot_spec(carry.ty, layout_env)
            if binding_residence(loop_carry_binding(loop.loop_id, carry), residence_plan) == Sem.SemResidenceStack then
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(loop_carry_slot_id(loop.loop_id, carry.port_id), carry_spec.size, carry_spec.align)
            end
            local header_param = Back.BackValId(path .. ".header.param." .. i)
            local body_param = Back.BackValId(path .. ".body.param." .. i)
            local continue_param = Back.BackValId(path .. ".continue.param." .. i)
            local exit_param = Back.BackValId(path .. ".exit.param." .. i)
            header_params[i] = header_param
            body_params[i] = body_param
            continue_params[i] = continue_param
            exit_params[i] = exit_param
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(carry.ty))
            cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit_block, exit_param, one_scalar(carry.ty))
            local init = one_plain_expr(carry.init, path .. ".init." .. i, layout_env, residence_plan)
            append_expr_cmds(cmds, init)
            if expr_terminates(init) then
                return terminated_addr(cmds)
            end
            init_values[i] = init.value
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_values)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
        emit_aliases_for_loop_bindings(cmds, loop.carries, header_params, loop.loop_id, residence_plan)
        local cond = one_plain_expr(loop.cond, path .. ".cond", layout_env, residence_plan)
        append_expr_cmds(cmds, cond)
        if expr_terminates(cond) then
            return terminated_addr(cmds)
        end
        cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, body_block, header_params, exit_block, header_params)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
        emit_aliases_for_loop_bindings(cmds, loop.carries, body_params, loop.loop_id, residence_plan)
        local body_current_args = loop_binding_value_args(body_params)
        local body_cmds, body_flow = lower_stmt_list(loop.body, path .. ".body", layout_env, nil, nil, continue_block, body_current_args, residence_plan)
        copy_cmds(body_cmds, cmds)
        if body_flow == Back.BackFallsThrough then
            cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
        end
        cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
        emit_aliases_for_loop_bindings(cmds, loop.carries, continue_params, loop.loop_id, residence_plan)
        local next_cmds, next_values, next_flow = eval_loop_nexts(loop.carries, loop.next, path, layout_env, residence_plan)
        copy_cmds(next_cmds, cmds)
        if next_flow == Back.BackTerminates then
            return terminated_addr(cmds)
        end
        cmds[#cmds + 1] = Back.BackCmdJump(header_block, next_values)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
        emit_aliases_for_loop_bindings(cmds, loop.carries, exit_params, loop.loop_id, residence_plan)
        local result = one_plain_expr_into_addr(loop.result, addr, path .. ".result", layout_env, residence_plan)
        append_addr_cmds(cmds, result)
        if addr_terminates(result) then
            return terminated_addr(cmds)
        end
        return addr_writes(cmds)
    end

    lower_loop_expr_plan = pvm.phase("sem_to_back_loop_expr", {
        [Sem.SemLoopWhileExpr] = function(self, path, layout_env, residence_plan)
            if self.exit == Sem.SemLoopExprEndOnly then
                return pvm.once(build_while_expr_end_only_plan(self, path, layout_env, residence_plan))
            end
            local result_ty = one_sem_expr_type(self.result)
            local result_back_ty = one_scalar(result_ty)
            local header_block = Back.BackBlockId(path .. ".header.block")
            local body_block = Back.BackBlockId(path .. ".body.block")
            local continue_block = Back.BackBlockId(path .. ".continue.block")
            local exit_block = Back.BackBlockId(path .. ".exit.block")
            local normal_block = Back.BackBlockId(path .. ".normal.block")
            local break_taken_block = Back.BackBlockId(path .. ".break_taken.block")
            local join_block = Back.BackBlockId(path .. ".join.block")
            local header_params = {}
            local body_params = {}
            local continue_params = {}
            local exit_params = {}
            local break_flag_slot = break_value_flag_slot_id(exit_block)
            local break_value_slot = break_value_value_slot_id(exit_block)
            local break_flag_addr = Back.BackValId(path .. ".break.flag.addr")
            local break_flag_init = Back.BackValId(path .. ".break.flag.init")
            local break_flag_value = Back.BackValId(path .. ".break.flag.value")
            local break_value_addr = Back.BackValId(path .. ".break.value.addr")
            local break_loaded_value = Back.BackValId(path .. ".break.value.loaded")
            local dst = Back.BackValId(path)
            local result_spec = one_stack_slot_spec(result_ty, layout_env)
            local cmds = {
                Back.BackCmdCreateStackSlot(break_flag_slot, 1, 1),
                Back.BackCmdCreateStackSlot(break_value_slot, result_spec.size, result_spec.align),
                Back.BackCmdCreateBlock(header_block),
                Back.BackCmdCreateBlock(body_block),
                Back.BackCmdCreateBlock(continue_block),
                Back.BackCmdCreateBlock(exit_block),
                Back.BackCmdCreateBlock(normal_block),
                Back.BackCmdCreateBlock(break_taken_block),
                Back.BackCmdCreateBlock(join_block),
                Back.BackCmdAppendBlockParam(join_block, dst, result_back_ty),
                Back.BackCmdStackAddr(break_flag_addr, break_flag_slot),
                Back.BackCmdStackAddr(break_value_addr, break_value_slot),
                Back.BackCmdConstBool(break_flag_init, false),
                Back.BackCmdStore(Back.BackBool, break_flag_addr, break_flag_init),
            }
            local init_values = {}
            for i = 1, #self.carries do
                local carry = self.carries[i]
                local carry_spec = one_stack_slot_spec(carry.ty, layout_env)
                if binding_residence(loop_carry_binding(self.loop_id, carry), residence_plan) == Sem.SemResidenceStack then
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(loop_carry_slot_id(self.loop_id, carry.port_id), carry_spec.size, carry_spec.align)
            end
                local header_param = Back.BackValId(path .. ".header.param." .. i)
                local body_param = Back.BackValId(path .. ".body.param." .. i)
                local continue_param = Back.BackValId(path .. ".continue.param." .. i)
                local exit_param = Back.BackValId(path .. ".exit.param." .. i)
                header_params[i] = header_param
                body_params[i] = body_param
                continue_params[i] = continue_param
                exit_params[i] = exit_param
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(carry.ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(carry.ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(carry.ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit_block, exit_param, one_scalar(carry.ty))
                local init = one_plain_expr(carry.init, path .. ".init." .. i, layout_env, residence_plan)
                append_expr_cmds(cmds, init)
                if expr_terminates(init) then
                    return pvm.once(terminated_expr(cmds))
                end
                init_values[i] = init.value
            end
            cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_values)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
            emit_aliases_for_loop_bindings(cmds, self.carries, header_params, self.loop_id, residence_plan)
            local cond = one_plain_expr(self.cond, path .. ".cond", layout_env, residence_plan)
            append_expr_cmds(cmds, cond)
            if expr_terminates(cond) then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, body_block, header_params, exit_block, header_params)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
            emit_aliases_for_loop_bindings(cmds, self.carries, body_params, self.loop_id, residence_plan)
            local body_current_args = loop_binding_value_args(body_params)
            local body_cmds, body_flow = lower_stmt_list(self.body, path .. ".body", layout_env, exit_block, body_current_args, continue_block, body_current_args, residence_plan)
            copy_cmds(body_cmds, cmds)
            if body_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
            emit_aliases_for_loop_bindings(cmds, self.carries, continue_params, self.loop_id, residence_plan)
            local next_cmds, next_values, next_flow = eval_loop_nexts(self.carries, self.next, path, layout_env, residence_plan)
            copy_cmds(next_cmds, cmds)
            if next_flow == Back.BackTerminates then
                return pvm.once(terminated_expr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdJump(header_block, next_values)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
            emit_aliases_for_loop_bindings(cmds, self.carries, exit_params, self.loop_id, residence_plan)
            cmds[#cmds + 1] = Back.BackCmdLoad(break_flag_value, Back.BackBool, break_flag_addr)
            cmds[#cmds + 1] = Back.BackCmdBrIf(break_flag_value, break_taken_block, {}, normal_block, {})
            cmds[#cmds + 1] = Back.BackCmdSealBlock(break_taken_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(normal_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(break_taken_block)
            cmds[#cmds + 1] = Back.BackCmdLoad(break_loaded_value, result_back_ty, break_value_addr)
            cmds[#cmds + 1] = Back.BackCmdJump(join_block, { break_loaded_value })
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(normal_block)
            local result = one_plain_expr(self.result, path .. ".result", layout_env, residence_plan)
            append_expr_cmds(cmds, result)
            if expr_has_value(result) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, { result.value })
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
            return pvm.once(Back.BackExprPlan(cmds, dst, result_back_ty))
        end,
        [Sem.SemLoopOverExpr] = function(self, path, layout_env, residence_plan)
            return pvm.once(one_over_expr_domain(self.domain, self, path, layout_env, residence_plan))
        end,
        [Sem.SemLoopWhileStmt] = function()
            error("sem_to_back_loop_expr: expected expr loop, got stmt loop")
        end,
        [Sem.SemLoopOverStmt] = function()
            error("sem_to_back_loop_expr: expected expr loop, got stmt loop")
        end,
    })

    lower_loop_expr_into_addr = pvm.phase("sem_to_back_loop_expr_into_addr", {
        [Sem.SemLoopWhileExpr] = function(self, addr, path, layout_env, residence_plan)
            if self.exit == Sem.SemLoopExprEndOnly then
                return pvm.once(build_while_expr_end_only_into_addr(self, addr, path, layout_env, residence_plan))
            end
            local result_ty = one_sem_expr_type(self.result)
            local result_spec = one_stack_slot_spec(result_ty, layout_env)
            local header_block = Back.BackBlockId(path .. ".header.block")
            local body_block = Back.BackBlockId(path .. ".body.block")
            local continue_block = Back.BackBlockId(path .. ".continue.block")
            local exit_block = Back.BackBlockId(path .. ".exit.block")
            local normal_block = Back.BackBlockId(path .. ".normal.block")
            local break_taken_block = Back.BackBlockId(path .. ".break_taken.block")
            local join_block = Back.BackBlockId(path .. ".join.block")
            local header_params = {}
            local body_params = {}
            local continue_params = {}
            local exit_params = {}
            local break_flag_slot = break_value_flag_slot_id(exit_block)
            local break_value_slot = break_value_value_slot_id(exit_block)
            local break_flag_addr = Back.BackValId(path .. ".break.flag.addr")
            local break_flag_init = Back.BackValId(path .. ".break.flag.init")
            local break_flag_value = Back.BackValId(path .. ".break.flag.value")
            local break_value_addr = Back.BackValId(path .. ".break.value.addr")
            local cmds = {
                Back.BackCmdCreateStackSlot(break_flag_slot, 1, 1),
                Back.BackCmdCreateStackSlot(break_value_slot, result_spec.size, result_spec.align),
                Back.BackCmdCreateBlock(header_block),
                Back.BackCmdCreateBlock(body_block),
                Back.BackCmdCreateBlock(continue_block),
                Back.BackCmdCreateBlock(exit_block),
                Back.BackCmdCreateBlock(normal_block),
                Back.BackCmdCreateBlock(break_taken_block),
                Back.BackCmdCreateBlock(join_block),
                Back.BackCmdStackAddr(break_flag_addr, break_flag_slot),
                Back.BackCmdStackAddr(break_value_addr, break_value_slot),
                Back.BackCmdConstBool(break_flag_init, false),
                Back.BackCmdStore(Back.BackBool, break_flag_addr, break_flag_init),
            }
            local init_values = {}
            for i = 1, #self.carries do
                local carry = self.carries[i]
                local carry_spec = one_stack_slot_spec(carry.ty, layout_env)
                if binding_residence(loop_carry_binding(self.loop_id, carry), residence_plan) == Sem.SemResidenceStack then
                cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(loop_carry_slot_id(self.loop_id, carry.port_id), carry_spec.size, carry_spec.align)
            end
                local header_param = Back.BackValId(path .. ".header.param." .. i)
                local body_param = Back.BackValId(path .. ".body.param." .. i)
                local continue_param = Back.BackValId(path .. ".continue.param." .. i)
                local exit_param = Back.BackValId(path .. ".exit.param." .. i)
                header_params[i] = header_param
                body_params[i] = body_param
                continue_params[i] = continue_param
                exit_params[i] = exit_param
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(header_block, header_param, one_scalar(carry.ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(body_block, body_param, one_scalar(carry.ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(continue_block, continue_param, one_scalar(carry.ty))
                cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit_block, exit_param, one_scalar(carry.ty))
                local init = one_plain_expr(carry.init, path .. ".init." .. i, layout_env, residence_plan)
                append_expr_cmds(cmds, init)
                if expr_terminates(init) then
                    return pvm.once(terminated_addr(cmds))
                end
                init_values[i] = init.value
            end
            cmds[#cmds + 1] = Back.BackCmdJump(header_block, init_values)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header_block)
            emit_aliases_for_loop_bindings(cmds, self.carries, header_params, self.loop_id, residence_plan)
            local cond = one_plain_expr(self.cond, path .. ".cond", layout_env, residence_plan)
            append_expr_cmds(cmds, cond)
            if expr_terminates(cond) then
                return pvm.once(terminated_addr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdBrIf(cond.value, body_block, header_params, exit_block, header_params)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(body_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body_block)
            emit_aliases_for_loop_bindings(cmds, self.carries, body_params, self.loop_id, residence_plan)
            local body_current_args = loop_binding_value_args(body_params)
            local body_cmds, body_flow = lower_stmt_list(self.body, path .. ".body", layout_env, exit_block, body_current_args, continue_block, body_current_args, residence_plan)
            copy_cmds(body_cmds, cmds)
            if body_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(continue_block, body_current_args)
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(continue_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(continue_block)
            emit_aliases_for_loop_bindings(cmds, self.carries, continue_params, self.loop_id, residence_plan)
            local next_cmds, next_values, next_flow = eval_loop_nexts(self.carries, self.next, path, layout_env, residence_plan)
            copy_cmds(next_cmds, cmds)
            if next_flow == Back.BackTerminates then
                return pvm.once(terminated_addr(cmds))
            end
            cmds[#cmds + 1] = Back.BackCmdJump(header_block, next_values)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(header_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(exit_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit_block)
            emit_aliases_for_loop_bindings(cmds, self.carries, exit_params, self.loop_id, residence_plan)
            cmds[#cmds + 1] = Back.BackCmdLoad(break_flag_value, Back.BackBool, break_flag_addr)
            cmds[#cmds + 1] = Back.BackCmdBrIf(break_flag_value, break_taken_block, {}, normal_block, {})
            cmds[#cmds + 1] = Back.BackCmdSealBlock(break_taken_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(normal_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(break_taken_block)
            copy_cmds(one_copy_type_addr(result_ty, break_value_addr, addr, path .. ".break.copy", layout_env), cmds)
            cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(normal_block)
            local result = one_plain_expr_into_addr(self.result, addr, path .. ".result", layout_env, residence_plan)
            append_addr_cmds(cmds, result)
            if addr_continues(result) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
            if addr_terminates(result) then
                return pvm.once(terminated_addr(cmds))
            end
            return pvm.once(addr_writes(cmds))
        end,
        [Sem.SemLoopOverExpr] = function(self, addr, path, layout_env, residence_plan)
            return pvm.once(one_over_expr_into_addr_domain(self.domain, self, addr, path, layout_env, residence_plan))
        end,
        [Sem.SemLoopWhileStmt] = function()
            error("sem_to_back_loop_expr_into_addr: expected expr loop, got stmt loop")
        end,
        [Sem.SemLoopOverStmt] = function()
            error("sem_to_back_loop_expr_into_addr: expected expr loop, got stmt loop")
        end,
    })

    local function expr_stmt_delegate()
        return function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr = one_expr(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
        [Sem.SemExprAddrOf] = expr_stmt_delegate(),
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
        [Sem.SemExprLoad] = expr_stmt_delegate(),
        [Sem.SemExprIntrinsicCall] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(pvm.one(intr_ops.lower_stmt(self.op, self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)))
        end,
        [Sem.SemExprCall] = expr_stmt_delegate(),
        [Sem.SemExprAgg] = expr_stmt_delegate(),
        [Sem.SemExprArrayLit] = expr_stmt_delegate(),
        [Sem.SemExprLoop] = expr_stmt_delegate(),
        [Sem.SemExprBlock] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local body_cmds, body_flow = lower_stmt_list(self.stmts, path .. ".stmts", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local cmds = {}
            copy_cmds(body_cmds, cmds)
            if body_flow == Back.BackFallsThrough then
                local result_plan = one_expr_stmt(self.result, path .. ".result", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                copy_cmds(result_plan.cmds, cmds)
                return pvm.once(Back.BackStmtPlan(cmds, result_plan.flow))
            end
            return pvm.once(Back.BackStmtPlan(cmds, body_flow))
        end,
        [Sem.SemExprIf] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local cond = one_expr(self.cond, path .. ".cond", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if expr_terminates(cond) then
                return pvm.once(Back.BackStmtPlan(cond.cmds, Back.BackTerminates))
            end
            local then_plan = one_expr_stmt(self.then_expr, path .. ".then", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local else_plan = one_expr_stmt(self.else_expr, path .. ".else", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
        [Sem.SemExprSwitch] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local value_ty = one_sem_expr_type(self.value)
            if not one_type_is_scalar(value_ty) then
                error("sem_to_back_expr_stmt: switch value must currently be scalar in Sem->Back")
            end
            local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if expr_terminates(value) then
                return pvm.once(Back.BackStmtPlan(value.cmds, Back.BackTerminates))
            end
            local default_plan = one_expr_stmt(self.default_expr, path .. ".default", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local back_arms = aux.lower_back_switch_expr_arms(self.arms, value_ty)
            local arm_plans = {}
            local need_join = default_plan.flow == Back.BackFallsThrough
            for i = 1, #back_arms.arms do
                local body_cmds, body_flow = lower_stmt_list(back_arms.arms[i].body, path .. ".arm." .. i, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                local plan_cmds = {}
                copy_cmds(body_cmds, plan_cmds)
                local plan_flow = body_flow
                if body_flow == Back.BackFallsThrough then
                    local result_plan = one_expr_stmt(back_arms.arms[i].result, path .. ".arm." .. i .. ".result", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                    copy_cmds(result_plan.cmds, plan_cmds)
                    plan_flow = result_plan.flow
                end
                arm_plans[i] = Back.BackStmtPlan(plan_cmds, plan_flow)
                if plan_flow == Back.BackFallsThrough then
                    need_join = true
                end
            end
            if #back_arms.arms == 0 then
                local cmds = {}
                append_expr_cmds(cmds, value)
                copy_cmds(default_plan.cmds, cmds)
                return pvm.once(Back.BackStmtPlan(cmds, default_plan.flow))
            end
            local join_block = Back.BackBlockId(path .. ".join.block")
            local default_block = Back.BackBlockId(path .. ".default.block")
            local arm_blocks = {}
            local cmds = {}
            append_expr_cmds(cmds, value)
            if pvm.one(aux.back_switch_expr_arms_is_const(back_arms)) then
                local cases = {}
                for i = 1, #back_arms.arms do
                    arm_blocks[i] = Back.BackBlockId(path .. ".arm." .. i .. ".block")
                    cmds[#cmds + 1] = Back.BackCmdCreateBlock(arm_blocks[i])
                    cases[i] = Back.BackSwitchCase(pvm.one(aux.back_switch_key_raw(back_arms.arms[i].key)), arm_blocks[i])
                end
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(default_block)
                if need_join then
                    cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
                end
                cmds[#cmds + 1] = Back.BackCmdSwitchInt(value.value, one_scalar(value_ty), cases, default_block)
                for i = 1, #back_arms.arms do
                    cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(arm_blocks[i])
                    copy_cmds(arm_plans[i].cmds, cmds)
                    if arm_plans[i].flow == Back.BackFallsThrough then
                        cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
                    end
                    cmds[#cmds + 1] = Back.BackCmdSealBlock(arm_blocks[i])
                end
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(default_block)
                copy_cmds(default_plan.cmds, cmds)
                if default_plan.flow == Back.BackFallsThrough then
                    cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
                end
                cmds[#cmds + 1] = Back.BackCmdSealBlock(default_block)
                if need_join then
                    cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                    cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
                end
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
            end
            local test_blocks = {}
            for i = 1, #back_arms.arms do
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
            for i = 1, #back_arms.arms do
                if i > 1 then
                    cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(test_blocks[i])
                end
                local key = pvm.one(aux.lower_back_switch_key_expr(back_arms.arms[i].key, value_ty, path .. ".arm." .. i .. ".key", layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
                append_expr_cmds(cmds, key)
                local else_block = (i < #back_arms.arms) and test_blocks[i + 1] or default_block
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
        [Sem.SemStmtLet] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local binding = Sem.SemBindLocalValue(self.id, self.name, self.ty)
            local residence = binding_residence(binding, residence_plan)
            if residence == Sem.SemResidenceValue then
                local init = one_expr(self.init, path .. ".init", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                local cmds = {}
                append_expr_cmds(cmds, init)
                if expr_terminates(init) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
                cmds[#cmds + 1] = Back.BackCmdAlias(local_value_id(self.id), init.value)
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
            end
            local spec = one_stack_slot_spec(self.ty, layout_env)
            local addr = Back.BackValId(path .. ".addr")
            local cmds = {
                Back.BackCmdCreateStackSlot(local_value_slot_id(self.id), spec.size, spec.align),
                Back.BackCmdStackAddr(addr, local_value_slot_id(self.id)),
            }
            local init_plan = one_expr_into_addr(self.init, addr, path .. ".init_store", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            append_addr_cmds(cmds, init_plan)
            return pvm.once(Back.BackStmtPlan(cmds, addr_to_stmt_flow(init_plan)))
        end,
        [Sem.SemStmtVar] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local spec = one_stack_slot_spec(self.ty, layout_env)
            local addr = Back.BackValId(path .. ".addr")
            local cmds = {
                Back.BackCmdCreateStackSlot(local_cell_slot_id(self.id), spec.size, spec.align),
                Back.BackCmdStackAddr(addr, local_cell_slot_id(self.id)),
            }
            if one_type_is_scalar(self.ty) then
                local init = one_expr(self.init, path .. ".init", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                append_expr_cmds(cmds, init)
                if expr_terminates(init) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
                cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(self.ty), addr, init.value)
            else
                local init_plan = one_expr_into_addr(self.init, addr, path .. ".init_store", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                append_addr_cmds(cmds, init_plan)
                if addr_terminates(init_plan) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
            end
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
        end,
        [Sem.SemStmtSet] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local addr = pvm.one(aux.place_store_addr(self.place, path .. ".addr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
            local place_ty = one_place_type(self.place)
            local cmds = {}
            append_expr_cmds(cmds, addr)
            if expr_terminates(addr) then
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
            end
            if one_type_is_scalar(place_ty) then
                local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                append_expr_cmds(cmds, value)
                if expr_terminates(value) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
                cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(place_ty), addr.value, value.value)
            else
                local value_plan = one_expr_into_addr(self.value, addr.value, path .. ".value_store", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                append_addr_cmds(cmds, value_plan)
                if addr_terminates(value_plan) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
            end
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
        end,
        [Sem.SemStmtExpr] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(one_expr_stmt(self.expr, path .. ".expr", layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemStmtIf] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local cond = one_expr(self.cond, path .. ".cond", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if expr_terminates(cond) then
                return pvm.once(Back.BackStmtPlan(cond.cmds, Back.BackTerminates))
            end
            local then_cmds, then_flow = lower_stmt_list(self.then_body, path .. ".then", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local else_cmds, else_flow = lower_stmt_list(self.else_body, path .. ".else", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(then_block)
            copy_cmds(then_cmds, cmds)
            if then_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(then_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(else_block)
            copy_cmds(else_cmds, cmds)
            if else_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(else_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
            end
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
        end,
        [Sem.SemStmtSwitch] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local value_ty = one_sem_expr_type(self.value)
            if not one_type_is_scalar(value_ty) then
                error("sem_to_back_stmt: switch value must currently be scalar in Sem->Back")
            end
            local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if expr_terminates(value) then
                return pvm.once(Back.BackStmtPlan(value.cmds, Back.BackTerminates))
            end
            local default_cmds, default_flow = lower_stmt_list(self.default_body, path .. ".default", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local back_arms = aux.lower_back_switch_stmt_arms(self.arms, value_ty)
            local arm_cmds = {}
            local arm_flows = {}
            local need_join = default_flow == Back.BackFallsThrough
            for i = 1, #back_arms.arms do
                arm_cmds[i], arm_flows[i] = lower_stmt_list(back_arms.arms[i].body, path .. ".arm." .. i, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                if arm_flows[i] == Back.BackFallsThrough then
                    need_join = true
                end
            end
            if #back_arms.arms == 0 then
                local cmds = {}
                append_expr_cmds(cmds, value)
                copy_cmds(default_cmds, cmds)
                return pvm.once(Back.BackStmtPlan(cmds, default_flow))
            end
            local join_block = Back.BackBlockId(path .. ".join.block")
            local default_block = Back.BackBlockId(path .. ".default.block")
            local arm_blocks = {}
            local cmds = {}
            append_expr_cmds(cmds, value)
            if pvm.one(aux.back_switch_stmt_arms_is_const(back_arms)) then
                local cases = {}
                for i = 1, #back_arms.arms do
                    arm_blocks[i] = Back.BackBlockId(path .. ".arm." .. i .. ".block")
                    cmds[#cmds + 1] = Back.BackCmdCreateBlock(arm_blocks[i])
                    cases[i] = Back.BackSwitchCase(pvm.one(aux.back_switch_key_raw(back_arms.arms[i].key)), arm_blocks[i])
                end
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(default_block)
                if need_join then
                    cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
                end
                cmds[#cmds + 1] = Back.BackCmdSwitchInt(value.value, one_scalar(value_ty), cases, default_block)
                for i = 1, #back_arms.arms do
                    cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(arm_blocks[i])
                    copy_cmds(arm_cmds[i], cmds)
                    if arm_flows[i] == Back.BackFallsThrough then
                        cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
                    end
                    cmds[#cmds + 1] = Back.BackCmdSealBlock(arm_blocks[i])
                end
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(default_block)
                copy_cmds(default_cmds, cmds)
                if default_flow == Back.BackFallsThrough then
                    cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
                end
                cmds[#cmds + 1] = Back.BackCmdSealBlock(default_block)
                if need_join then
                    cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                    cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
                end
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
            end
            local test_blocks = {}
            for i = 1, #back_arms.arms do
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
            for i = 1, #back_arms.arms do
                if i > 1 then
                    cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(test_blocks[i])
                end
                local key = pvm.one(aux.lower_back_switch_key_expr(back_arms.arms[i].key, value_ty, path .. ".arm." .. i .. ".key", layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
                append_expr_cmds(cmds, key)
                local else_block = (i < #back_arms.arms) and test_blocks[i + 1] or default_block
                if expr_has_value(key) then
                    local match = Back.BackValId(path .. ".arm." .. i .. ".match")
                    cmds[#cmds + 1] = one_eq_cmd(value_ty, match, Back.BackBool, value.value, key.value)
                    cmds[#cmds + 1] = Back.BackCmdBrIf(match, arm_blocks[i], {}, else_block, {})
                end
            end
            for i = 2, #back_arms.arms do
                cmds[#cmds + 1] = Back.BackCmdSealBlock(test_blocks[i])
            end
            for i = 1, #back_arms.arms do
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(arm_blocks[i])
                copy_cmds(arm_cmds[i], cmds)
                if arm_flows[i] == Back.BackFallsThrough then
                    cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
                end
                cmds[#cmds + 1] = Back.BackCmdSealBlock(arm_blocks[i])
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(default_block)
            copy_cmds(default_cmds, cmds)
            if default_flow == Back.BackFallsThrough then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(default_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
            end
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
        end,
        [Sem.SemStmtAssert] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local cond = one_expr(self.cond, path .. ".cond", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(fail_block)
            cmds[#cmds + 1] = Back.BackCmdTrap
            cmds[#cmds + 1] = Back.BackCmdSealBlock(fail_block)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(ok_block)
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(ok_block)
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackFallsThrough))
        end,
        [Sem.SemStmtLoop] = function(self, path, layout_env)
            return pvm.once(one_loop_stmt_plan(self.loop, path, layout_env, residence_plan))
        end,
        [Sem.SemStmtReturnVoid] = function()
            return pvm.once(Back.BackStmtPlan({ Back.BackCmdReturnVoid }, Back.BackTerminates))
        end,
        [Sem.SemStmtReturnValue] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local ret_ty = one_sem_expr_type(self.value)
            if not one_type_is_scalar(ret_ty) then
                error("sem_to_back_stmt: non-scalar return values are not yet supported by the current Back ABI")
            end
            local expr = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
        [Sem.SemStmtBreakValue] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if break_block == nil then
                error("sem_to_back_stmt: break_value is only valid inside an expression loop body")
            end
            local result_ty = one_sem_expr_type(self.value)
            local flag_addr = Back.BackValId(path .. ".break_value.flag.addr")
            local flag_value = Back.BackValId(path .. ".break_value.flag.value")
            local cmds = {
                Back.BackCmdStackAddr(flag_addr, break_value_flag_slot_id(break_block)),
                Back.BackCmdConstBool(flag_value, true),
            }
            if one_type_is_scalar(result_ty) then
                local value = one_expr(self.value, path .. ".break_value.value", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                append_expr_cmds(cmds, value)
                if expr_terminates(value) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
                local value_addr = Back.BackValId(path .. ".break_value.value.addr")
                cmds[#cmds + 1] = Back.BackCmdStackAddr(value_addr, break_value_value_slot_id(break_block))
                cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(result_ty), value_addr, value.value)
            else
                local value_addr = Back.BackValId(path .. ".break_value.value.addr")
                cmds[#cmds + 1] = Back.BackCmdStackAddr(value_addr, break_value_value_slot_id(break_block))
                local value_plan = one_expr_into_addr(self.value, value_addr, path .. ".break_value.store", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                append_addr_cmds(cmds, value_plan)
                if addr_terminates(value_plan) then
                    return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
                end
            end
            cmds[#cmds + 1] = Back.BackCmdStore(Back.BackBool, flag_addr, flag_value)
            cmds[#cmds + 1] = Back.BackCmdJump(break_block, break_args or {})
            return pvm.once(Back.BackStmtPlan(cmds, Back.BackTerminates))
        end,
        [Sem.SemStmtContinue] = function(self, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if continue_block == nil then
                error("sem_to_back_stmt: continue is only valid inside a loop body")
            end
            return pvm.once(Back.BackStmtPlan({ Back.BackCmdJump(continue_block, continue_args or {}) }, Back.BackTerminates))
        end,
    })

    lower_func = pvm.phase("sem_to_back_func", {
        [Sem.SemFuncLocal] = function(self, module_name, layout_env)
            local func_text = func_id_text(module_name, self.name)
            local residence_plan = one_func_residence_plan(self)
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
            if not one_type_is_void(self.result) then
                results[1] = one_scalar(self.result)
            end
            local body_cmds = lower_stmt_list(self.body, "func:" .. func_text, layout_env, nil, nil, nil, nil, residence_plan)
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
                    local binding = Sem.SemBindArg(i - 1, param.name, param.ty)
                    local residence = binding_residence(binding, residence_plan)
                    if residence == Sem.SemResidenceStack then
                        local slot = arg_slot_id(i - 1, param.name)
                        local addr = Back.BackValId("arg.addr:" .. (i - 1) .. ":" .. param.name)
                        local value = Back.BackValId("arg:" .. (i - 1) .. ":" .. param.name)
                        local spec = one_stack_slot_spec(param.ty, layout_env)
                        cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(slot, spec.size, spec.align)
                        cmds[#cmds + 1] = Back.BackCmdStackAddr(addr, slot)
                        cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(param.ty), addr, value)
                    end
                end
            end
            copy_cmds(body_cmds, cmds)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(entry_id)
            cmds[#cmds + 1] = Back.BackCmdFinishFunc(func_id)
            return pvm.once(Back.BackFuncPlan(cmds))
        end,
        [Sem.SemFuncExport] = function(self, module_name, layout_env)
            local func_text = func_id_text(module_name, self.name)
            local residence_plan = one_func_residence_plan(self)
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
            if not one_type_is_void(self.result) then
                results[1] = one_scalar(self.result)
            end
            local body_cmds = lower_stmt_list(self.body, "func:" .. func_text, layout_env, nil, nil, nil, nil, residence_plan)
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
                    local binding = Sem.SemBindArg(i - 1, param.name, param.ty)
                    local residence = binding_residence(binding, residence_plan)
                    if residence == Sem.SemResidenceStack then
                        local slot = arg_slot_id(i - 1, param.name)
                        local addr = Back.BackValId("arg.addr:" .. (i - 1) .. ":" .. param.name)
                        local value = Back.BackValId("arg:" .. (i - 1) .. ":" .. param.name)
                        local spec = one_stack_slot_spec(param.ty, layout_env)
                        cmds[#cmds + 1] = Back.BackCmdCreateStackSlot(slot, spec.size, spec.align)
                        cmds[#cmds + 1] = Back.BackCmdStackAddr(addr, slot)
                        cmds[#cmds + 1] = Back.BackCmdStore(one_scalar(param.ty), addr, value)
                    end
                end
            end
            copy_cmds(body_cmds, cmds)
            cmds[#cmds + 1] = Back.BackCmdSealBlock(entry_id)
            cmds[#cmds + 1] = Back.BackCmdFinishFunc(func_id)
            return pvm.once(Back.BackFuncPlan(cmds))
        end,
    })

    lower_item = pvm.phase("sem_to_back_item", {
        [Sem.SemItemFunc] = function(self, module_name, layout_env)
            return pvm.once(Back.BackItemPlan(one_func(self.func, module_name, layout_env).cmds))
        end,
        [Sem.SemItemExtern] = function(self)
            local params = {}
            local results = {}
            for i = 1, #self.func.params do
                params[i] = one_scalar(self.func.params[i].ty)
            end
            if not one_type_is_void(self.func.result) then
                results[1] = one_scalar(self.func.result)
            end
            local sig_id = Back.BackSigId("sig:extern:" .. self.func.symbol)
            return pvm.once(Back.BackItemPlan({
                Back.BackCmdCreateSig(sig_id, params, results),
                Back.BackCmdDeclareFuncExtern(Back.BackExternId(self.func.symbol), self.func.symbol, sig_id),
            }))
        end,
        [Sem.SemItemConst] = function(self, module_name, layout_env, const_env)
            return pvm.once(Back.BackItemPlan({}))
        end,
        [Sem.SemItemStatic] = function(self, module_name, layout_env, const_env)
            local data_id = static_data_id(module_name, self.s.name)
            local spec = one_stack_slot_spec(self.s.ty, layout_env)
            local cmds = {
                Back.BackCmdDeclareData(data_id, spec.size, spec.align),
            }
            copy_cmds(one_const_data_init(self.s.value, data_id, 0, layout_env, const_env, nil), cmds)
            return pvm.once(Back.BackItemPlan(cmds))
        end,
        [Sem.SemItemImport] = function()
            return pvm.once(Back.BackItemPlan({}))
        end,
        [Sem.SemItemType] = function()
            return pvm.once(Back.BackItemPlan({}))
        end,
    })

    aux.lower_module_plan = pvm.phase("sem_to_back_module_plan", {
        [Sem.SemModule] = function(self, layout_env, const_env)
            local env = const_eval.ensure_const_env(const_env)
            local entries = {}
            for i = 1, #env.entries do
                entries[i] = env.entries[i]
            end
            for i = 1, #self.items do
                local item = self.items[i]
                if item.c ~= nil then
                    entries[#entries + 1] = Sem.SemConstEntry(self.module_name, item.c.name, item.c.ty, item.c.value)
                end
            end
            local module_const_env = Sem.SemConstEnv(entries)
            local folded = pvm.one(aux.const_scalars.fold_module(self, module_const_env))
            local cmds = {}
            for i = 1, #folded.items do
                copy_cmds(one_item(folded.items[i], folded.module_name, layout_env, module_const_env).cmds, cmds)
            end
            return pvm.once(Back.BackItemPlan(cmds))
        end,
    })

    lower_module = pvm.phase("sem_to_back_module", {
        [Sem.SemModule] = function(self, layout_env, const_env)
            local cmds = {}
            copy_cmds(pvm.one(aux.lower_module_plan(self, layout_env, const_env)).cmds, cmds)
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
        lower_module_plan = aux.lower_module_plan,
        lower_module = lower_module,
    }
end

return M
