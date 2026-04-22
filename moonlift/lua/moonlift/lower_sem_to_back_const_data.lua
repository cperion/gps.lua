package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.Define(T, env)
    local Sem = T.MoonliftSem
    local Back = T.MoonliftBack

    local lower_const_agg_value_init_from_type
    local lower_const_value_data_init
    local lower_const_agg_init_from_type
    local lower_const_data_init

    local function one_scalar(node)
        return env.one_scalar(node)
    end

    local function one_type_mem_size(node, layout_env)
        return env.one_type_mem_size(node, layout_env)
    end

    local function one_const_eval(node, const_env, local_env, visiting)
        return env.one_const_eval(node, const_env, local_env, visiting)
    end

    local function require_named_layout(layout_env, module_name, type_name)
        return env.require_named_layout(layout_env, module_name, type_name)
    end

    local function const_data_key(module_name, item_name)
        return env.const_data_key(module_name, item_name)
    end

    local function find_layout_field(layout, field_name)
        return env.find_layout_field(layout, field_name)
    end

    local function find_const_field_value(fields, field_name)
        for i = 1, #fields do
            if fields[i].name == field_name then
                return fields[i].value
            end
        end
        return nil
    end

    local function copy_cmds(src, out)
        return env.copy_cmds(src, out)
    end

    local function one_const_value_data_init(node, data_id, offset, layout_env)
        return pvm.one(lower_const_value_data_init(node, data_id, offset, layout_env))
    end

    local function one_const_data_init(node, data_id, offset, layout_env, const_env, visiting)
        return pvm.one(lower_const_data_init(node, data_id, offset, layout_env, const_env, visiting))
    end

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
        [Sem.SemExprAddrOf] = delegate_const_data_init(),
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

    return {
        lower_const_agg_value_init_from_type = lower_const_agg_value_init_from_type,
        lower_const_value_data_init = lower_const_value_data_init,
        lower_const_agg_init_from_type = lower_const_agg_init_from_type,
        lower_const_data_init = lower_const_data_init,
    }
end

return M
