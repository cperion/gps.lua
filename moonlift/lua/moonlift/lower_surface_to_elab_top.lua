package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local Lower = require("moonlift.lower_surface_to_elab_loop")

local M = {}

function M.Define(T)
    local Surf = T.MoonliftSurface
    local Elab = T.MoonliftElab

    local api = Lower.Define(T)
    local lower_type = api.lower_type
    local lower_expr = api.lower_expr
    local expr_type = api.expr_type
    local lower_domain = api.lower_domain
    local lower_stmt = api.lower_stmt
    local lower_loop_stmt = api.lower_loop_stmt
    local lower_loop_expr = api.lower_loop_expr

    local lower_param
    local lower_param_entry
    local lower_item_value_entry
    local lower_func
    local lower_extern_func
    local lower_const
    local lower_item
    local lower_module

    local function one_type(node)
        return pvm.one(lower_type(node))
    end

    local function one_expr(node, env, expected_ty)
        return pvm.one(lower_expr(node, env, expected_ty))
    end

    local function one_stmt(node, env, path)
        return pvm.one(lower_stmt(node, env, path))
    end

    local function one_param(node)
        return pvm.one(lower_param(node))
    end

    local function one_param_entry(node, index)
        return pvm.one(lower_param_entry(node, index))
    end

    local function one_item_value_entry(node)
        return pvm.one(lower_item_value_entry(node))
    end

    local function one_func(node, env)
        return pvm.one(lower_func(node, env))
    end

    local function one_extern_func(node)
        return pvm.one(lower_extern_func(node))
    end

    local function one_const(node, env)
        return pvm.one(lower_const(node, env))
    end

    local function one_item(node, env)
        return pvm.one(lower_item(node, env))
    end

    local function ensure_env(env)
        if env ~= nil then
            return env
        end
        return Elab.ElabEnv({}, {}, {})
    end

    local function extend_env_values(env, entries)
        local base = ensure_env(env)
        local values = {}
        local old_values = base.values or {}
        for i = 1, #old_values do
            values[i] = old_values[i]
        end
        for i = 1, #entries do
            values[#values + 1] = entries[i]
        end
        return pvm.with(base, { values = values })
    end

    lower_param = pvm.phase("surface_to_elab_param", {
        [Surf.SurfParam] = function(self)
            return pvm.once(Elab.ElabParam(self.name, one_type(self.ty)))
        end,
    })

    lower_param_entry = pvm.phase("surface_to_elab_param_entry", {
        [Surf.SurfParam] = function(self, index)
            local ty = one_type(self.ty)
            return pvm.once(Elab.ElabValueEntry(self.name, Elab.ElabArg(index, self.name, ty)))
        end,
    })

    lower_item_value_entry = pvm.phase("surface_to_elab_item_value_entry", {
        [Surf.SurfItemFunc] = function(self)
            local params = {}
            for i = 1, #self.func.params do
                params[i] = one_type(self.func.params[i].ty)
            end
            local fn_ty = Elab.ElabTFunc(params, one_type(self.func.result))
            return pvm.once(Elab.ElabValueEntry(self.func.name, Elab.ElabGlobal("", self.func.name, fn_ty)))
        end,
        [Surf.SurfItemExtern] = function(self)
            local params = {}
            for i = 1, #self.func.params do
                params[i] = one_type(self.func.params[i].ty)
            end
            local fn_ty = Elab.ElabTFunc(params, one_type(self.func.result))
            return pvm.once(Elab.ElabValueEntry(self.func.name, Elab.ElabExtern(self.func.symbol, fn_ty)))
        end,
        [Surf.SurfItemConst] = function(self)
            return pvm.once(Elab.ElabValueEntry(self.c.name, Elab.ElabGlobal("", self.c.name, one_type(self.c.ty))))
        end,
    })

    lower_func = pvm.phase("surface_to_elab_func", {
        [Surf.SurfFunc] = function(self, env)
            local module_env = ensure_env(env)
            local params = {}
            local param_entries = {}
            for i = 1, #self.params do
                params[i] = one_param(self.params[i])
                param_entries[i] = one_param_entry(self.params[i], i - 1)
            end
            local body_env = extend_env_values(module_env, param_entries)
            local body = {}
            local current_env = body_env
            for i = 1, #self.body do
                local stmt = one_stmt(self.body[i], current_env, "func." .. self.name .. ".stmt." .. i)
                body[i] = stmt
                local effect = pvm.one(api.stmt_env_effect(stmt))
                current_env = pvm.one(api.apply_stmt_env_effect(effect, current_env))
            end
            return pvm.once(Elab.ElabFunc(self.name, params, one_type(self.result), body))
        end,
    })

    lower_extern_func = pvm.phase("surface_to_elab_extern_func", {
        [Surf.SurfExternFunc] = function(self)
            local params = {}
            for i = 1, #self.params do
                params[i] = one_param(self.params[i])
            end
            return pvm.once(Elab.ElabExternFunc(self.name, self.symbol, params, one_type(self.result)))
        end,
    })

    lower_const = pvm.phase("surface_to_elab_const", {
        [Surf.SurfConst] = function(self, env)
            local ty = one_type(self.ty)
            return pvm.once(Elab.ElabConst(self.name, ty, one_expr(self.value, ensure_env(env), ty)))
        end,
    })

    lower_item = pvm.phase("surface_to_elab_item", {
        [Surf.SurfItemFunc] = function(self, env)
            return pvm.once(Elab.ElabItemFunc(one_func(self.func, env)))
        end,
        [Surf.SurfItemExtern] = function(self)
            return pvm.once(Elab.ElabItemExtern(one_extern_func(self.func)))
        end,
        [Surf.SurfItemConst] = function(self, env)
            return pvm.once(Elab.ElabItemConst(one_const(self.c, env)))
        end,
    })

    lower_module = pvm.phase("surface_to_elab_module", {
        [Surf.SurfModule] = function(self, env)
            local module_env = ensure_env(env)
            local item_entries = {}
            for i = 1, #self.items do
                item_entries[i] = one_item_value_entry(self.items[i])
            end
            local lowered_env = extend_env_values(module_env, item_entries)
            local items = {}
            for i = 1, #self.items do
                items[i] = one_item(self.items[i], lowered_env)
            end
            return pvm.once(Elab.ElabModule(items))
        end,
    })

    return {
        lower_type = lower_type,
        lower_expr = lower_expr,
        expr_type = expr_type,
        lower_domain = lower_domain,
        lower_stmt = lower_stmt,
        lower_loop_stmt = lower_loop_stmt,
        lower_loop_expr = lower_loop_expr,
        stmt_env_effect = api.stmt_env_effect,
        apply_stmt_env_effect = api.apply_stmt_env_effect,
        lower_param = lower_param,
        lower_func = lower_func,
        lower_extern_func = lower_extern_func,
        lower_const = lower_const,
        lower_item = lower_item,
        lower_module = lower_module,
    }
end

return M
