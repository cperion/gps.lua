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
    local lower_field_decl
    local lower_type_decl
    local lower_import
    local lower_item_type_entry
    local lower_item_type_layout
    local lower_item_value_entry
    local count_decl_type
    local lower_func
    local lower_extern_func
    local lower_const
    local lower_static
    local lower_item
    local lower_module

    local function one_type(node, env)
        return pvm.one(lower_type(node, env))
    end

    local function one_expr(node, env, expected_ty)
        return pvm.one(lower_expr(node, env, expected_ty))
    end

    local function one_stmt(node, env, path)
        return pvm.one(lower_stmt(node, env, path))
    end

    local function one_param(node, env)
        return pvm.one(lower_param(node, env))
    end

    local function one_param_entry(node, env, index)
        return pvm.one(lower_param_entry(node, env, index))
    end

    local function one_field_decl(node, env)
        return pvm.one(lower_field_decl(node, env))
    end

    local function one_type_decl(node, env)
        return pvm.one(lower_type_decl(node, env))
    end

    local function one_import(node)
        return pvm.one(lower_import(node))
    end

    local function one_item_type_entry(node, env)
        return pvm.one(lower_item_type_entry(node, env))
    end

    local function one_item_type_layout(node, env)
        return pvm.one(lower_item_type_layout(node, env))
    end

    local function one_item_value_entry(node, env)
        return pvm.one(lower_item_value_entry(node, env))
    end

    local function one_count_decl_type(node)
        return pvm.one(count_decl_type(node))
    end

    local function one_func(node, env)
        return pvm.one(lower_func(node, env))
    end

    local function one_extern_func(node, env)
        return pvm.one(lower_extern_func(node, env))
    end

    local function one_const(node, env)
        return pvm.one(lower_const(node, env))
    end

    local function one_static(node, env)
        return pvm.one(lower_static(node, env))
    end

    local function one_item(node, env)
        return pvm.one(lower_item(node, env))
    end

    local function ensure_env(env)
        if env ~= nil then
            return env
        end
        return Elab.ElabEnv("", {}, {}, {})
    end

    local function current_module_name(env)
        local base = ensure_env(env)
        return base.module_name or ""
    end

    local function path_text(path)
        local parts = {}
        for i = 1, #path.parts do
            parts[i] = path.parts[i].text
        end
        return table.concat(parts, ".")
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

    local function extend_env_types(env, entries)
        local base = ensure_env(env)
        local types = {}
        local old_types = base.types or {}
        for i = 1, #old_types do
            types[i] = old_types[i]
        end
        for i = 1, #entries do
            types[#types + 1] = entries[i]
        end
        return pvm.with(base, { types = types })
    end

    local function extend_env_layouts(env, entries)
        local base = ensure_env(env)
        local layouts = {}
        local old_layouts = base.layouts or {}
        for i = 1, #old_layouts do
            layouts[i] = old_layouts[i]
        end
        for i = 1, #entries do
            layouts[#layouts + 1] = entries[i]
        end
        return pvm.with(base, { layouts = layouts })
    end

    local function with_path(path, fn)
        local ok, result = xpcall(fn, function(err)
            if type(err) == "string" and path ~= nil and path ~= "" and not string.find(err, path, 1, true) then
                return path .. ": " .. err
            end
            return err
        end)
        if not ok then
            error(result, 0)
        end
        return result
    end

    lower_param = pvm.phase("surface_to_elab_param", {
        [Surf.SurfParam] = function(self, env)
            return pvm.once(Elab.ElabParam(self.name, one_type(self.ty, env)))
        end,
    })

    lower_param_entry = pvm.phase("surface_to_elab_param_entry", {
        [Surf.SurfParam] = function(self, env, index)
            local ty = one_type(self.ty, env)
            return pvm.once(Elab.ElabValueEntry(self.name, Elab.ElabArg(index, self.name, ty)))
        end,
    })

    lower_field_decl = pvm.phase("surface_to_elab_field_decl", {
        [Surf.SurfFieldDecl] = function(self, env)
            return pvm.once(Elab.ElabFieldType(self.field_name, one_type(self.ty, env)))
        end,
    })

    lower_type_decl = pvm.phase("surface_to_elab_type_decl", {
        [Surf.SurfStruct] = function(self, env)
            local fields = {}
            for i = 1, #self.fields do
                fields[i] = one_field_decl(self.fields[i], env)
            end
            return pvm.once(Elab.ElabStruct(self.name, fields))
        end,
    })

    lower_import = pvm.phase("surface_to_elab_import", {
        [Surf.SurfImport] = function(self)
            return pvm.once(Elab.ElabImport(path_text(self.path)))
        end,
    })

    lower_item_type_entry = pvm.phase("surface_to_elab_item_type_entry", {
        [Surf.SurfItemType] = function(self, env)
            local module_name = current_module_name(env)
            return pvm.once(Elab.ElabTypeEntry(self.t.name, Elab.ElabTNamed(module_name, self.t.name)))
        end,
    })

    lower_item_type_layout = pvm.phase("surface_to_elab_item_type_layout", {
        [Surf.SurfItemType] = function(self, env)
            local t = one_type_decl(self.t, env)
            return pvm.once(Elab.ElabLayoutNamed(current_module_name(env), t.name, t.fields))
        end,
    })

    lower_item_value_entry = pvm.phase("surface_to_elab_item_value_entry", {
        [Surf.SurfItemFunc] = function(self, env)
            local params = {}
            for i = 1, #self.func.params do
                params[i] = one_type(self.func.params[i].ty, env)
            end
            local fn_ty = Elab.ElabTFunc(params, one_type(self.func.result, env))
            return pvm.once(Elab.ElabValueEntry(self.func.name, Elab.ElabGlobalFunc(current_module_name(env), self.func.name, fn_ty)))
        end,
        [Surf.SurfItemExtern] = function(self, env)
            local params = {}
            for i = 1, #self.func.params do
                params[i] = one_type(self.func.params[i].ty, env)
            end
            local fn_ty = Elab.ElabTFunc(params, one_type(self.func.result, env))
            return pvm.once(Elab.ElabValueEntry(self.func.name, Elab.ElabExtern(self.func.symbol, fn_ty)))
        end,
        [Surf.SurfItemConst] = function(self, env)
            return pvm.once(Elab.ElabValueEntry(self.c.name, Elab.ElabGlobalConst(current_module_name(env), self.c.name, one_type(self.c.ty, env))))
        end,
        [Surf.SurfItemStatic] = function(self, env)
            return pvm.once(Elab.ElabValueEntry(self.s.name, Elab.ElabGlobalStatic(current_module_name(env), self.s.name, one_type(self.s.ty, env))))
        end,
    })

    count_decl_type = pvm.phase("surface_to_elab_count_decl_type", {
        [Surf.SurfTIndex] = function() return pvm.once(true) end,
        [Surf.SurfTVoid] = function() return pvm.once(false) end,
        [Surf.SurfTBool] = function() return pvm.once(false) end,
        [Surf.SurfTI8] = function() return pvm.once(false) end,
        [Surf.SurfTI16] = function() return pvm.once(false) end,
        [Surf.SurfTI32] = function() return pvm.once(false) end,
        [Surf.SurfTI64] = function() return pvm.once(false) end,
        [Surf.SurfTU8] = function() return pvm.once(false) end,
        [Surf.SurfTU16] = function() return pvm.once(false) end,
        [Surf.SurfTU32] = function() return pvm.once(false) end,
        [Surf.SurfTU64] = function() return pvm.once(false) end,
        [Surf.SurfTF32] = function() return pvm.once(false) end,
        [Surf.SurfTF64] = function() return pvm.once(false) end,
        [Surf.SurfTPtr] = function() return pvm.once(false) end,
        [Surf.SurfTArray] = function() return pvm.once(false) end,
        [Surf.SurfTSlice] = function() return pvm.once(false) end,
        [Surf.SurfTFunc] = function() return pvm.once(false) end,
        [Surf.SurfTView] = function() return pvm.once(false) end,
        [Surf.SurfTNamed] = function() return pvm.once(false) end,
    })

    lower_func = pvm.phase("surface_to_elab_func", {
        [Surf.SurfFunc] = function(self, env)
            local module_env = ensure_env(env)
            local params = {}
            local param_entries = {}
            for i = 1, #self.params do
                params[i] = one_param(self.params[i], module_env)
                param_entries[i] = one_param_entry(self.params[i], module_env, i - 1)
            end
            local body_env = extend_env_values(module_env, param_entries)
            local body = {}
            local current_env = body_env
            for i = 1, #self.body do
                local stmt_path = "func." .. self.name .. ".stmt." .. i
                local stmt = with_path(stmt_path, function()
                    return one_stmt(self.body[i], current_env, stmt_path)
                end)
                body[i] = stmt
                local effect = pvm.one(api.stmt_env_effect(stmt))
                current_env = pvm.one(api.apply_stmt_env_effect(effect, current_env))
            end
            return pvm.once(Elab.ElabFunc(self.name, params, one_type(self.result, module_env), body))
        end,
    })

    lower_extern_func = pvm.phase("surface_to_elab_extern_func", {
        [Surf.SurfExternFunc] = function(self, env)
            local params = {}
            for i = 1, #self.params do
                params[i] = one_param(self.params[i], ensure_env(env))
            end
            return pvm.once(Elab.ElabExternFunc(self.name, self.symbol, params, one_type(self.result, ensure_env(env))))
        end,
    })

    lower_const = pvm.phase("surface_to_elab_const", {
        [Surf.SurfConst] = function(self, env)
            local ty = one_type(self.ty, ensure_env(env))
            return pvm.once(Elab.ElabConst(self.name, ty, one_expr(self.value, ensure_env(env), ty)))
        end,
    })

    lower_static = pvm.phase("surface_to_elab_static", {
        [Surf.SurfStatic] = function(self, env)
            local ty = one_type(self.ty, ensure_env(env))
            return pvm.once(Elab.ElabStatic(self.name, ty, one_expr(self.value, ensure_env(env), ty)))
        end,
    })

    lower_item = pvm.phase("surface_to_elab_item", {
        [Surf.SurfItemFunc] = function(self, env)
            return pvm.once(Elab.ElabItemFunc(one_func(self.func, env)))
        end,
        [Surf.SurfItemExtern] = function(self, env)
            return pvm.once(Elab.ElabItemExtern(one_extern_func(self.func, env)))
        end,
        [Surf.SurfItemConst] = function(self, env)
            return pvm.once(Elab.ElabItemConst(one_const(self.c, env)))
        end,
        [Surf.SurfItemStatic] = function(self, env)
            return pvm.once(Elab.ElabItemStatic(one_static(self.s, env)))
        end,
        [Surf.SurfItemImport] = function(self)
            return pvm.once(Elab.ElabItemImport(one_import(self.imp)))
        end,
        [Surf.SurfItemType] = function(self, env)
            return pvm.once(Elab.ElabItemType(one_type_decl(self.t, env)))
        end,
    })

    lower_module = pvm.phase("surface_to_elab_module", {
        [Surf.SurfModule] = function(self, env)
            local module_env = ensure_env(env)

            local provisional_count_entries = {}
            for i = 1, #self.items do
                local item = self.items[i]
                if item.c ~= nil and one_count_decl_type(item.c.ty) then
                    provisional_count_entries[#provisional_count_entries + 1] = Elab.ElabValueEntry(item.c.name, Elab.ElabGlobalConst(current_module_name(module_env), item.c.name, Elab.ElabTIndex))
                end
            end
            local count_env = extend_env_values(module_env, provisional_count_entries)

            local type_entries = {}
            for i = 1, #self.items do
                local item = self.items[i]
                if item.t ~= nil then
                    type_entries[#type_entries + 1] = one_item_type_entry(item, count_env)
                end
            end
            local type_env = extend_env_types(count_env, type_entries)

            local type_layouts = {}
            for i = 1, #self.items do
                local item = self.items[i]
                if item.t ~= nil then
                    type_layouts[#type_layouts + 1] = one_item_type_layout(item, type_env)
                end
            end
            local layout_env = extend_env_layouts(type_env, type_layouts)

            local item_entries = {}
            for i = 1, #self.items do
                local item = self.items[i]
                if item.func ~= nil or item.c ~= nil or item.s ~= nil then
                    item_entries[#item_entries + 1] = one_item_value_entry(item, layout_env)
                end
            end
            local lowered_env = extend_env_values(layout_env, item_entries)

            local items = {}
            for i = 1, #self.items do
                items[i] = one_item(self.items[i], lowered_env)
            end
            return pvm.once(Elab.ElabModule(current_module_name(module_env), items))
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
        lower_import = lower_import,
        lower_func = lower_func,
        lower_extern_func = lower_extern_func,
        lower_const = lower_const,
        lower_static = lower_static,
        lower_item = lower_item,
        lower_module = lower_module,
    }
end

return M
