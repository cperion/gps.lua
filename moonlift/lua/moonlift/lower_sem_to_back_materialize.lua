package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.Define(T, env)
    local Sem = T.MoonliftSem
    local Back = T.MoonliftBack

    local lower_agg_expr_into_addr_from_type
    local lower_copy_type_addr
    local lower_expr_into_addr

    local function one_scalar(node)
        return env.one_scalar(node)
    end

    local function one_type_is_scalar(node)
        return env.one_type_is_scalar(node)
    end

    local function one_type_is_void(node)
        return env.one_type_is_void(node)
    end

    local function one_type_mem_size(node, layout_env)
        return env.one_type_mem_size(node, layout_env)
    end

    local function one_expr(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return env.one_expr(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
    end

    local function one_sem_expr_type(node)
        return env.one_sem_expr_type(node)
    end

    local function one_addr_of_expr(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return env.one_addr_of_expr(node, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
    end

    local function one_add_cmd(node, dst, ty, lhs, rhs)
        return env.one_add_cmd(node, dst, ty, lhs, rhs)
    end

    local function one_eq_cmd(node, dst, ty, lhs, rhs)
        return env.one_eq_cmd(node, dst, ty, lhs, rhs)
    end

    local function one_loop_expr_into_addr(node, addr, path, layout_env, residence_plan)
        return env.one_loop_expr_into_addr(node, addr, path, layout_env, residence_plan)
    end

    local function one_expr_into_addr(node, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return env.one_expr_into_addr(node, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
    end

    local function one_copy_type_addr(node, src_addr, dst_addr, path, layout_env)
        return pvm.one(lower_copy_type_addr(node, src_addr, dst_addr, path, layout_env))
    end

    local function require_named_layout(layout_env, module_name, type_name)
        return env.require_named_layout(layout_env, module_name, type_name)
    end

    local function find_field_init(fields, field_name)
        return env.find_field_init(fields, field_name)
    end

    local function copy_cmds(src, out)
        return env.copy_cmds(src, out)
    end

    local function append_expr_cmds(out, plan)
        return env.append_expr_cmds(out, plan)
    end

    local function append_addr_cmds(out, plan)
        return env.append_addr_cmds(out, plan)
    end

    local function expr_has_value(plan)
        return env.expr_has_value(plan)
    end

    local function expr_terminates(plan)
        return env.expr_terminates(plan)
    end

    local function terminated_addr(cmds)
        return env.terminated_addr(cmds)
    end

    local function addr_continues(plan)
        return env.addr_continues(plan)
    end

    local function addr_terminates(plan)
        return env.addr_terminates(plan)
    end

    local function addr_writes(cmds)
        return env.addr_writes(cmds)
    end

    local function lower_stmt_list(nodes, base_path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        return env.lower_stmt_list(nodes, base_path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
    end

    local function switch_int_case_raws(value_ty, arms)
        return env.switch_int_case_raws(value_ty, arms)
    end

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
            return pvm.once({ Back.BackCmdLoad(value, one_scalar(self), src_addr), Back.BackCmdStore(one_scalar(self), dst_addr, value) })
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
        [Sem.SemTSlice] = function(self, src_addr, dst_addr, path)
            local src_data_cmds, src_data = addr_with_offset(src_addr, 0, path .. ".src.data")
            local dst_data_cmds, dst_data = addr_with_offset(dst_addr, 0, path .. ".dst.data")
            local src_len_cmds, src_len = addr_with_offset(src_addr, 8, path .. ".src.len")
            local dst_len_cmds, dst_len = addr_with_offset(dst_addr, 8, path .. ".dst.len")
            local data = Back.BackValId(path .. ".data")
            local len = Back.BackValId(path .. ".len")
            local cmds = {}
            copy_cmds(src_data_cmds, cmds)
            copy_cmds(dst_data_cmds, cmds)
            copy_cmds(src_len_cmds, cmds)
            copy_cmds(dst_len_cmds, cmds)
            cmds[#cmds + 1] = Back.BackCmdLoad(data, Back.BackPtr, src_data)
            cmds[#cmds + 1] = Back.BackCmdStore(Back.BackPtr, dst_data, data)
            cmds[#cmds + 1] = Back.BackCmdLoad(len, Back.BackIndex, src_len)
            cmds[#cmds + 1] = Back.BackCmdStore(Back.BackIndex, dst_len, len)
            return pvm.once(cmds)
        end,
        [Sem.SemTView] = function(self, src_addr, dst_addr, path)
            local src_data_cmds, src_data = addr_with_offset(src_addr, 0, path .. ".src.data")
            local dst_data_cmds, dst_data = addr_with_offset(dst_addr, 0, path .. ".dst.data")
            local src_len_cmds, src_len = addr_with_offset(src_addr, 8, path .. ".src.len")
            local dst_len_cmds, dst_len = addr_with_offset(dst_addr, 8, path .. ".dst.len")
            local src_stride_cmds, src_stride = addr_with_offset(src_addr, 16, path .. ".src.stride")
            local dst_stride_cmds, dst_stride = addr_with_offset(dst_addr, 16, path .. ".dst.stride")
            local data = Back.BackValId(path .. ".data")
            local len = Back.BackValId(path .. ".len")
            local stride = Back.BackValId(path .. ".stride")
            local cmds = {}
            copy_cmds(src_data_cmds, cmds)
            copy_cmds(dst_data_cmds, cmds)
            copy_cmds(src_len_cmds, cmds)
            copy_cmds(dst_len_cmds, cmds)
            copy_cmds(src_stride_cmds, cmds)
            copy_cmds(dst_stride_cmds, cmds)
            cmds[#cmds + 1] = Back.BackCmdLoad(data, Back.BackPtr, src_data)
            cmds[#cmds + 1] = Back.BackCmdStore(Back.BackPtr, dst_data, data)
            cmds[#cmds + 1] = Back.BackCmdLoad(len, Back.BackIndex, src_len)
            cmds[#cmds + 1] = Back.BackCmdStore(Back.BackIndex, dst_len, len)
            cmds[#cmds + 1] = Back.BackCmdLoad(stride, Back.BackIndex, src_stride)
            cmds[#cmds + 1] = Back.BackCmdStore(Back.BackIndex, dst_stride, stride)
            return pvm.once(cmds)
        end,
        [Sem.SemTVoid] = function()
            error("sem_to_back_copy_type_addr: cannot copy void")
        end,
        [Sem.SemTFunc] = function()
            error("sem_to_back_copy_type_addr: function values are not storable in Sem->Back")
        end,
    })

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
            one_expr(expr, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args, residence_plan),
            addr,
            store_ty
        )
    end

    local function lower_expr_copy_into_addr(expr, expr_ty, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        if one_type_is_scalar(expr_ty) then
            return lower_scalar_expr_into_addr(expr, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(expr_ty))
        end
        return copy_value_into_addr(
            expr_ty,
            one_addr_of_expr(expr, path .. ".src", layout_env, break_block, break_args, continue_block, continue_args, residence_plan),
            addr,
            path,
            layout_env
        )
    end

    local function build_switch_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        local value_ty = one_sem_expr_type(self.value)
        if not one_type_is_scalar(value_ty) then
            error("sem_to_back_expr_into_addr: switch value must currently be scalar in Sem->Back")
        end
        local value = one_expr(self.value, path .. ".value", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        local cmds = {}
        append_expr_cmds(cmds, value)
        if expr_terminates(value) then
            return terminated_addr(cmds)
        end
        if #self.arms == 0 then
            local default_plan = one_expr_into_addr(self.default_expr, addr, path .. ".default", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            append_addr_cmds(cmds, default_plan)
            if addr_terminates(default_plan) then
                return terminated_addr(cmds)
            end
            return addr_writes(cmds)
        end
        local arm_body_cmds = {}
        local arm_result_plans = {}
        local default_plan = one_expr_into_addr(self.default_expr, addr, path .. ".default", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
        local need_join = addr_continues(default_plan)
        for i = 1, #self.arms do
            local body_cmds, body_flow = lower_stmt_list(self.arms[i].body, path .. ".arm." .. i, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            arm_body_cmds[i] = body_cmds
            if body_flow == Back.BackFallsThrough then
                arm_result_plans[i] = one_expr_into_addr(self.arms[i].result, addr, path .. ".arm." .. i .. ".result", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
        local case_raws = switch_int_case_raws(value_ty, self.arms)
        if case_raws ~= nil then
            local cases = {}
            for i = 1, #self.arms do
                arm_blocks[i] = Back.BackBlockId(path .. ".arm." .. i .. ".block")
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(arm_blocks[i])
                cases[i] = Back.BackSwitchCase(case_raws[i], arm_blocks[i])
            end
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(default_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdCreateBlock(join_block)
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchInt(value.value, one_scalar(value_ty), cases, default_block)
            for i = 1, #self.arms do
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(arm_blocks[i])
                copy_cmds(arm_body_cmds[i], cmds)
                append_addr_cmds(cmds, arm_result_plans[i])
                if addr_continues(arm_result_plans[i]) then
                    cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
                end
                cmds[#cmds + 1] = Back.BackCmdSealBlock(arm_blocks[i])
            end
            cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(default_block)
            append_addr_cmds(cmds, default_plan)
            if addr_continues(default_plan) then
                cmds[#cmds + 1] = Back.BackCmdJump(join_block, {})
            end
            cmds[#cmds + 1] = Back.BackCmdSealBlock(default_block)
            if need_join then
                cmds[#cmds + 1] = Back.BackCmdSealBlock(join_block)
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(join_block)
                return addr_writes(cmds)
            end
            return terminated_addr(cmds)
        end
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
            local key = one_expr(self.arms[i].key, path .. ".arm." .. i .. ".key", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
        [Sem.SemExprArrayLit] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local cmds = {}
            local elem_size = one_type_mem_size(self.elem_ty, layout_env)
            for i = 1, #self.elems do
                local elem_cmds, elem_addr = addr_with_offset(addr, (i - 1) * elem_size, path .. ".elem." .. i)
                copy_cmds(elem_cmds, cmds)
                local elem_plan = one_expr_into_addr(self.elems[i], elem_addr, path .. ".elem_init." .. i, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
                append_addr_cmds(cmds, elem_plan)
                if addr_terminates(elem_plan) then
                    return pvm.once(terminated_addr(cmds))
                end
            end
            return pvm.once(addr_writes(cmds))
        end,
        [Sem.SemExprBinding] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_expr_copy_into_addr(self, one_sem_expr_type(self), addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprField] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_expr_copy_into_addr(self, one_sem_expr_type(self), addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprIndex] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_expr_copy_into_addr(self, one_sem_expr_type(self), addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprConstInt] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprConstFloat] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprConstBool] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprNil] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprAddrOf] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprDeref] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_expr_copy_into_addr(self, one_sem_expr_type(self), addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprAdd] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprSub] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprMul] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprDiv] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprRem] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprEq] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprNe] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprLt] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprLe] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprGt] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprGe] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, Back.BackBool))
        end,
        [Sem.SemExprAnd] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprOr] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprBitAnd] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprBitOr] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprBitXor] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprShl] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprLShr] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprAShr] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprCastTo] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprTruncTo] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprZExtTo] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprSExtTo] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprBitcastTo] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprSatCastTo] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprSelect] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprLoad] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local expr_ty = one_sem_expr_type(self)
            if not one_type_is_scalar(expr_ty) then
                error("sem_to_back_expr_into_addr: non-scalar load results are not yet supported")
            end
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(expr_ty)))
        end,
        [Sem.SemExprIntrinsicCall] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if one_type_is_void(self.ty) then
                error("sem_to_back_expr_into_addr: void intrinsic calls have no materialization form")
            end
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr_into_addr: non-scalar intrinsic results are not supported")
            end
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprCall] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if not one_type_is_scalar(self.ty) then
                error("sem_to_back_expr_into_addr: non-scalar call results are not yet supported")
            end
            return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
        end,
        [Sem.SemExprBlock] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local body_cmds, body_flow = lower_stmt_list(self.stmts, path .. ".stmts", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local cmds = {}
            copy_cmds(body_cmds, cmds)
            if body_flow ~= Back.BackFallsThrough then
                return pvm.once(terminated_addr(cmds))
            end
            local result = one_expr_into_addr(self.result, addr, path .. ".result", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            append_addr_cmds(cmds, result)
            if addr_terminates(result) then
                return pvm.once(terminated_addr(cmds))
            end
            return pvm.once(addr_writes(cmds))
        end,
        [Sem.SemExprIf] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local cond = one_expr(self.cond, path .. ".cond", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local then_block = Back.BackBlockId(path .. ".then.block")
            local else_block = Back.BackBlockId(path .. ".else.block")
            local join_block = Back.BackBlockId(path .. ".join.block")
            local then_plan = one_expr_into_addr(self.then_expr, addr, path .. ".then", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            local else_plan = one_expr_into_addr(self.else_expr, addr, path .. ".else", layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
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
        [Sem.SemExprSwitch] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            return pvm.once(build_switch_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan))
        end,
        [Sem.SemExprLoop] = function(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, residence_plan)
            if one_type_is_scalar(self.ty) then
                return pvm.once(lower_scalar_expr_into_addr(self, addr, path, layout_env, break_block, break_args, continue_block, continue_args, one_scalar(self.ty)))
            end
            return pvm.once(one_loop_expr_into_addr(self.loop, addr, path .. ".loop", layout_env, residence_plan))
        end,
    })

    return {
        lower_copy_type_addr = lower_copy_type_addr,
        lower_expr_into_addr = lower_expr_into_addr,
    }
end

return M
