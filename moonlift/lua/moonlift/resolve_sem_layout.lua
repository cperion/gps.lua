package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.Define(T)
    local Sem = T.MoonliftSem

    local sem_expr_type
    local sem_place_type
    local resolve_type_mem_layout
    local resolve_type_layout
    local resolve_layout_field
    local resolve_field_ref_from_base_type
    local resolve_field_ref
    local resolve_view
    local resolve_place
    local resolve_index_base
    local resolve_call_target
    local resolve_field_init
    local resolve_switch_stmt_arm
    local resolve_switch_expr_arm
    local resolve_loop_carry
    local resolve_loop_update
    local resolve_domain
    local resolve_expr
    local resolve_stmt
    local resolve_loop
    local resolve_func
    local resolve_const
    local resolve_static
    local synthesize_layout_env
    local resolve_item
    local resolve_module

    local function one_sem_expr_type(node)
        return pvm.one(sem_expr_type(node))
    end

    local function one_sem_place_type(node)
        return pvm.one(sem_place_type(node))
    end

    local function one_type_mem_layout(node, layout_env, module, cache, visiting)
        return pvm.one(resolve_type_mem_layout(node, layout_env, module, cache, visiting))
    end

    local function one_type_layout(node, layout_env)
        return pvm.one(resolve_type_layout(node, layout_env))
    end

    local function one_layout_field(node, field_ref)
        return pvm.one(resolve_layout_field(node, field_ref))
    end

    local function one_field_ref_from_base_type(node, field_ref, layout_env)
        return pvm.one(resolve_field_ref_from_base_type(node, field_ref, layout_env))
    end

    local function one_field_ref(node, base_ty, layout_env)
        return pvm.one(resolve_field_ref(node, base_ty, layout_env))
    end

    local function one_view(node, layout_env)
        return pvm.one(resolve_view(node, layout_env))
    end

    local function one_place(node, layout_env)
        return pvm.one(resolve_place(node, layout_env))
    end

    local function one_index_base(node, layout_env)
        return pvm.one(resolve_index_base(node, layout_env))
    end

    local function one_call_target(node, layout_env)
        return pvm.one(resolve_call_target(node, layout_env))
    end

    local function one_field_init(node, layout_env)
        return pvm.one(resolve_field_init(node, layout_env))
    end

    local function one_switch_stmt_arm(node, layout_env)
        return pvm.one(resolve_switch_stmt_arm(node, layout_env))
    end

    local function one_switch_expr_arm(node, layout_env)
        return pvm.one(resolve_switch_expr_arm(node, layout_env))
    end

    local function one_loop_carry(node, layout_env)
        return pvm.one(resolve_loop_carry(node, layout_env))
    end

    local function one_loop_update(node, layout_env)
        return pvm.one(resolve_loop_update(node, layout_env))
    end

    local function one_domain(node, layout_env)
        return pvm.one(resolve_domain(node, layout_env))
    end

    local function one_expr(node, layout_env)
        return pvm.one(resolve_expr(node, layout_env))
    end

    local function one_stmt(node, layout_env)
        return pvm.one(resolve_stmt(node, layout_env))
    end

    local function one_loop(node, layout_env)
        return pvm.one(resolve_loop(node, layout_env))
    end

    local function one_func(node, layout_env)
        return pvm.one(resolve_func(node, layout_env))
    end

    local function one_const(node, layout_env)
        return pvm.one(resolve_const(node, layout_env))
    end

    local function one_static(node, layout_env)
        return pvm.one(resolve_static(node, layout_env))
    end

    local function one_synthesized_layout_env(node, layout_env)
        return pvm.one(synthesize_layout_env(node, layout_env))
    end

    local function one_item(node, layout_env)
        return pvm.one(resolve_item(node, layout_env))
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

    local function resolve_expr_list(nodes, layout_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_expr(nodes[i], layout_env)
        end
        return out
    end

    local function resolve_stmt_list(nodes, layout_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_stmt(nodes[i], layout_env)
        end
        return out
    end

    local function resolve_field_init_list(nodes, layout_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_field_init(nodes[i], layout_env)
        end
        return out
    end

    local function resolve_switch_stmt_arm_list(nodes, layout_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_switch_stmt_arm(nodes[i], layout_env)
        end
        return out
    end

    local function resolve_switch_expr_arm_list(nodes, layout_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_switch_expr_arm(nodes[i], layout_env)
        end
        return out
    end

    local function resolve_loop_carry_list(nodes, layout_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_loop_carry(nodes[i], layout_env)
        end
        return out
    end

    local function resolve_loop_update_list(nodes, layout_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_loop_update(nodes[i], layout_env)
        end
        return out
    end

    local function resolve_view_list(nodes, layout_env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_view(nodes[i], layout_env)
        end
        return out
    end

    local function named_type_text(module_name, type_name)
        if module_name == nil or module_name == "" then
            return type_name
        end
        return module_name .. "." .. type_name
    end

    local function ensure_layout_env(layout_env)
        if layout_env ~= nil then
            return layout_env
        end
        return Sem.SemLayoutEnv({})
    end

    local function extend_layout_env(layout_env, layouts)
        local base = ensure_layout_env(layout_env)
        local out = {}
        for i = 1, #base.layouts do
            out[i] = base.layouts[i]
        end
        for i = 1, #layouts do
            out[#out + 1] = layouts[i]
        end
        return Sem.SemLayoutEnv(out)
    end

    local function align_up(value, align)
        return math.floor((value + align - 1) / align) * align
    end

    local function find_module_type_item(module, type_name)
        for i = 1, #module.items do
            local item = module.items[i]
            if item.t ~= nil and item.t.name == type_name then
                return item.t
            end
        end
        return nil
    end

    resolve_type_mem_layout = pvm.phase("moonlift_sem_layout_type_mem_layout", {
        [Sem.SemTVoid] = function()
            return pvm.once(Sem.SemMemLayout(0, 1))
        end,
        [Sem.SemTBool] = function()
            return pvm.once(Sem.SemMemLayout(1, 1))
        end,
        [Sem.SemTI8] = function()
            return pvm.once(Sem.SemMemLayout(1, 1))
        end,
        [Sem.SemTU8] = function()
            return pvm.once(Sem.SemMemLayout(1, 1))
        end,
        [Sem.SemTI16] = function()
            return pvm.once(Sem.SemMemLayout(2, 2))
        end,
        [Sem.SemTU16] = function()
            return pvm.once(Sem.SemMemLayout(2, 2))
        end,
        [Sem.SemTI32] = function()
            return pvm.once(Sem.SemMemLayout(4, 4))
        end,
        [Sem.SemTU32] = function()
            return pvm.once(Sem.SemMemLayout(4, 4))
        end,
        [Sem.SemTF32] = function()
            return pvm.once(Sem.SemMemLayout(4, 4))
        end,
        [Sem.SemTI64] = function()
            return pvm.once(Sem.SemMemLayout(8, 8))
        end,
        [Sem.SemTU64] = function()
            return pvm.once(Sem.SemMemLayout(8, 8))
        end,
        [Sem.SemTF64] = function()
            return pvm.once(Sem.SemMemLayout(8, 8))
        end,
        [Sem.SemTPtr] = function()
            return pvm.once(Sem.SemMemLayout(8, 8))
        end,
        [Sem.SemTIndex] = function()
            return pvm.once(Sem.SemMemLayout(8, 8))
        end,
        [Sem.SemTPtrTo] = function()
            return pvm.once(Sem.SemMemLayout(8, 8))
        end,
        [Sem.SemTArray] = function(self, base_layout_env, module, cache, visiting)
            local elem = one_type_mem_layout(self.elem, base_layout_env, module, cache, visiting)
            return pvm.once(Sem.SemMemLayout(elem.size * self.count, elem.align))
        end,
        [Sem.SemTNamed] = function(self, base_layout_env, module, cache, visiting)
            local key = named_type_text(self.module_name, self.type_name)
            local layout = find_named_layout(base_layout_env, self.module_name, self.type_name)
            if layout ~= nil then
                return pvm.once(Sem.SemMemLayout(layout.size, layout.align))
            end
            if cache[key] ~= nil then
                return pvm.once(Sem.SemMemLayout(cache[key].size, cache[key].align))
            end
            if visiting[key] then
                error("resolve_sem_layout: recursive named type layout is not yet supported for '" .. key .. "'")
            end
            local current_module_name = module.module_name or ""
            if self.module_name ~= current_module_name then
                error("resolve_sem_layout: missing layout for named type '" .. key .. "'")
            end
            local item = find_module_type_item(module, self.type_name)
            if item == nil then
                error("resolve_sem_layout: missing layout for named type '" .. key .. "'")
            end
            visiting[key] = true
            local offset = 0
            local struct_align = 1
            local fields = {}
            for i = 1, #item.fields do
                local field = item.fields[i]
                local field_layout = one_type_mem_layout(field.ty, base_layout_env, module, cache, visiting)
                offset = align_up(offset, field_layout.align)
                fields[i] = Sem.SemFieldLayout(field.field_name, offset, field.ty)
                offset = offset + field_layout.size
                if field_layout.align > struct_align then
                    struct_align = field_layout.align
                end
            end
            local size = align_up(offset, struct_align)
            local synthesized = Sem.SemLayoutNamed(current_module_name, item.name, fields, size, struct_align)
            cache[key] = synthesized
            visiting[key] = nil
            return pvm.once(Sem.SemMemLayout(synthesized.size, synthesized.align))
        end,
        [Sem.SemTSlice] = function()
            return pvm.once(Sem.SemMemLayout(16, 8))
        end,
        [Sem.SemTView] = function()
            return pvm.once(Sem.SemMemLayout(24, 8))
        end,
        [Sem.SemTFunc] = function()
            error("resolve_sem_layout: function-valued fields are not yet supported in named layouts")
        end,
    })

    synthesize_layout_env = pvm.phase("moonlift_sem_layout_synthesize_layout_env", {
        [Sem.SemModule] = function(self, layout_env)
            local base = ensure_layout_env(layout_env)
            local cache = {}
            local visiting = {}
            local layouts = {}
            for i = 1, #self.items do
                local item = self.items[i]
                if item.t ~= nil then
                    local key = named_type_text(self.module_name, item.t.name)
                    if cache[key] == nil then
                        one_type_mem_layout(Sem.SemTNamed(self.module_name, item.t.name), base, self, cache, visiting)
                    end
                    layouts[#layouts + 1] = cache[key]
                end
            end
            return pvm.once(extend_layout_env(base, layouts))
        end,
    })

    sem_expr_type = pvm.phase("moonlift_sem_layout_resolve_expr_type", {
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
        [Sem.SemExprField] = function(self) return pvm.once(self.field.ty) end,
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

    sem_place_type = pvm.phase("moonlift_sem_layout_resolve_place_type", {
        [Sem.SemPlaceBinding] = function(self) return pvm.once(self.binding.ty) end,
        [Sem.SemPlaceDeref] = function(self) return pvm.once(self.elem) end,
        [Sem.SemPlaceField] = function(self) return pvm.once(self.field.ty) end,
        [Sem.SemPlaceIndex] = function(self) return pvm.once(self.ty) end,
    })

    resolve_type_layout = pvm.phase("moonlift_sem_layout_resolve_type_layout", {
        [Sem.SemTNamed] = function(self, layout_env)
            local layout = find_named_layout(layout_env, self.module_name, self.type_name)
            if layout == nil then
                error("resolve_sem_layout: missing layout for named type '" .. named_type_text(self.module_name, self.type_name) .. "'")
            end
            return pvm.once(layout)
        end,
        [Sem.SemTVoid] = function() error("resolve_sem_layout: void has no field layout") end,
        [Sem.SemTBool] = function() error("resolve_sem_layout: bool has no field layout") end,
        [Sem.SemTI8] = function() error("resolve_sem_layout: i8 has no field layout") end,
        [Sem.SemTI16] = function() error("resolve_sem_layout: i16 has no field layout") end,
        [Sem.SemTI32] = function() error("resolve_sem_layout: i32 has no field layout") end,
        [Sem.SemTI64] = function() error("resolve_sem_layout: i64 has no field layout") end,
        [Sem.SemTU8] = function() error("resolve_sem_layout: u8 has no field layout") end,
        [Sem.SemTU16] = function() error("resolve_sem_layout: u16 has no field layout") end,
        [Sem.SemTU32] = function() error("resolve_sem_layout: u32 has no field layout") end,
        [Sem.SemTU64] = function() error("resolve_sem_layout: u64 has no field layout") end,
        [Sem.SemTF32] = function() error("resolve_sem_layout: f32 has no field layout") end,
        [Sem.SemTF64] = function() error("resolve_sem_layout: f64 has no field layout") end,
        [Sem.SemTPtr] = function() error("resolve_sem_layout: raw pointers have no named field layout") end,
        [Sem.SemTIndex] = function() error("resolve_sem_layout: index has no field layout") end,
        [Sem.SemTPtrTo] = function() error("resolve_sem_layout: pointer-to values have no direct field layout; deref before field access") end,
        [Sem.SemTArray] = function() error("resolve_sem_layout: arrays have no named field layout") end,
        [Sem.SemTSlice] = function() error("resolve_sem_layout: slices have no named field layout yet") end,
        [Sem.SemTView] = function() error("resolve_sem_layout: views have no named field layout yet") end,
        [Sem.SemTFunc] = function() error("resolve_sem_layout: functions have no field layout") end,
    })

    resolve_layout_field = pvm.phase("moonlift_sem_layout_resolve_layout_field", {
        [Sem.SemLayoutNamed] = function(self, field_ref)
            for i = 1, #self.fields do
                local field = self.fields[i]
                if field.field_name == field_ref.field_name then
                    if field.ty ~= field_ref.ty then
                        error("resolve_sem_layout: field '" .. field_ref.field_name .. "' on type '" .. named_type_text(self.module_name, self.type_name) .. "' has type mismatch between reference and layout")
                    end
                    return pvm.once(Sem.SemFieldByOffset(field.field_name, field.offset, field.ty))
                end
            end
            error("resolve_sem_layout: unknown field '" .. field_ref.field_name .. "' on type '" .. named_type_text(self.module_name, self.type_name) .. "'")
        end,
    })

    resolve_field_ref_from_base_type = pvm.phase("moonlift_sem_layout_resolve_field_ref_from_base_type", {
        [Sem.SemTNamed] = function(self, field_ref, layout_env)
            return pvm.once(one_layout_field(one_type_layout(self, layout_env), field_ref))
        end,
        [Sem.SemTVoid] = function() error("resolve_sem_layout: cannot resolve a field on void") end,
        [Sem.SemTBool] = function() error("resolve_sem_layout: cannot resolve a field on bool") end,
        [Sem.SemTI8] = function() error("resolve_sem_layout: cannot resolve a field on i8") end,
        [Sem.SemTI16] = function() error("resolve_sem_layout: cannot resolve a field on i16") end,
        [Sem.SemTI32] = function() error("resolve_sem_layout: cannot resolve a field on i32") end,
        [Sem.SemTI64] = function() error("resolve_sem_layout: cannot resolve a field on i64") end,
        [Sem.SemTU8] = function() error("resolve_sem_layout: cannot resolve a field on u8") end,
        [Sem.SemTU16] = function() error("resolve_sem_layout: cannot resolve a field on u16") end,
        [Sem.SemTU32] = function() error("resolve_sem_layout: cannot resolve a field on u32") end,
        [Sem.SemTU64] = function() error("resolve_sem_layout: cannot resolve a field on u64") end,
        [Sem.SemTF32] = function() error("resolve_sem_layout: cannot resolve a field on f32") end,
        [Sem.SemTF64] = function() error("resolve_sem_layout: cannot resolve a field on f64") end,
        [Sem.SemTPtr] = function() error("resolve_sem_layout: cannot resolve a field on raw pointer values") end,
        [Sem.SemTIndex] = function() error("resolve_sem_layout: cannot resolve a field on index") end,
        [Sem.SemTPtrTo] = function() error("resolve_sem_layout: cannot resolve a field on pointer-to values; deref before field access") end,
        [Sem.SemTArray] = function() error("resolve_sem_layout: cannot resolve a named field on arrays") end,
        [Sem.SemTSlice] = function() error("resolve_sem_layout: cannot resolve a named field on slices yet") end,
        [Sem.SemTView] = function() error("resolve_sem_layout: cannot resolve a named field on views yet") end,
        [Sem.SemTFunc] = function() error("resolve_sem_layout: cannot resolve a field on function values") end,
    })

    resolve_field_ref = pvm.phase("moonlift_sem_layout_resolve_field_ref", {
        [Sem.SemFieldByOffset] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemFieldByName] = function(self, base_ty, layout_env)
            return pvm.once(one_field_ref_from_base_type(base_ty, self, layout_env))
        end,
    })

    resolve_view = pvm.phase("moonlift_sem_layout_resolve_view", {
        [Sem.SemViewValue] = function(self, layout_env)
            return pvm.once(Sem.SemViewValue(one_expr(self.base, layout_env), self.elem))
        end,
        [Sem.SemViewContiguous] = function(self, layout_env)
            return pvm.once(Sem.SemViewContiguous(one_expr(self.data, layout_env), self.elem, one_expr(self.len, layout_env)))
        end,
        [Sem.SemViewStrided] = function(self, layout_env)
            return pvm.once(Sem.SemViewStrided(one_expr(self.data, layout_env), self.elem, one_expr(self.len, layout_env), one_expr(self.stride, layout_env)))
        end,
        [Sem.SemViewWindow] = function(self, layout_env)
            return pvm.once(Sem.SemViewWindow(one_view(self.base, layout_env), one_expr(self.start, layout_env), one_expr(self.len, layout_env)))
        end,
        [Sem.SemViewInterleaved] = function(self, layout_env)
            return pvm.once(Sem.SemViewInterleaved(one_expr(self.data, layout_env), self.elem, one_expr(self.len, layout_env), one_expr(self.stride, layout_env), one_expr(self.lane, layout_env)))
        end,
    })

    resolve_place = pvm.phase("moonlift_sem_layout_resolve_place", {
        [Sem.SemPlaceBinding] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemPlaceDeref] = function(self, layout_env)
            return pvm.once(Sem.SemPlaceDeref(one_expr(self.base, layout_env), self.elem))
        end,
        [Sem.SemPlaceField] = function(self, layout_env)
            local base = one_place(self.base, layout_env)
            return pvm.once(Sem.SemPlaceField(base, one_field_ref(self.field, one_sem_place_type(base), layout_env)))
        end,
        [Sem.SemPlaceIndex] = function(self, layout_env)
            return pvm.once(Sem.SemPlaceIndex(one_index_base(self.base, layout_env), one_expr(self.index, layout_env), self.ty))
        end,
    })

    resolve_index_base = pvm.phase("moonlift_sem_layout_resolve_index_base", {
        [Sem.SemIndexBasePlace] = function(self, layout_env)
            return pvm.once(Sem.SemIndexBasePlace(one_place(self.base, layout_env), self.elem))
        end,
        [Sem.SemIndexBaseView] = function(self, layout_env)
            return pvm.once(Sem.SemIndexBaseView(one_view(self.view, layout_env)))
        end,
    })

    resolve_call_target = pvm.phase("moonlift_sem_layout_resolve_call_target", {
        [Sem.SemCallDirect] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemCallExtern] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemCallIndirect] = function(self, layout_env)
            return pvm.once(Sem.SemCallIndirect(one_expr(self.callee, layout_env), self.fn_ty))
        end,
    })

    resolve_field_init = pvm.phase("moonlift_sem_layout_resolve_field_init", {
        [Sem.SemFieldInit] = function(self, layout_env)
            return pvm.once(Sem.SemFieldInit(self.name, one_expr(self.value, layout_env)))
        end,
    })

    resolve_switch_stmt_arm = pvm.phase("moonlift_sem_layout_resolve_switch_stmt_arm", {
        [Sem.SemSwitchStmtArm] = function(self, layout_env)
            return pvm.once(Sem.SemSwitchStmtArm(one_expr(self.key, layout_env), resolve_stmt_list(self.body, layout_env)))
        end,
    })

    resolve_switch_expr_arm = pvm.phase("moonlift_sem_layout_resolve_switch_expr_arm", {
        [Sem.SemSwitchExprArm] = function(self, layout_env)
            return pvm.once(Sem.SemSwitchExprArm(one_expr(self.key, layout_env), resolve_stmt_list(self.body, layout_env), one_expr(self.result, layout_env)))
        end,
    })

    resolve_loop_carry = pvm.phase("moonlift_sem_layout_resolve_loop_carry", {
        [Sem.SemLoopCarryPort] = function(self, layout_env)
            return pvm.once(Sem.SemLoopCarryPort(self.port_id, self.name, self.ty, one_expr(self.init, layout_env)))
        end,
    })

    resolve_loop_update = pvm.phase("moonlift_sem_layout_resolve_loop_update", {
        [Sem.SemLoopUpdate] = function(self, layout_env)
            return pvm.once(Sem.SemLoopUpdate(self.port_id, one_expr(self.value, layout_env)))
        end,
    })

    resolve_domain = pvm.phase("moonlift_sem_layout_resolve_domain", {
        [Sem.SemDomainRange] = function(self, layout_env)
            return pvm.once(Sem.SemDomainRange(one_expr(self.stop, layout_env)))
        end,
        [Sem.SemDomainRange2] = function(self, layout_env)
            return pvm.once(Sem.SemDomainRange2(one_expr(self.start, layout_env), one_expr(self.stop, layout_env)))
        end,
        [Sem.SemDomainView] = function(self, layout_env)
            return pvm.once(Sem.SemDomainView(one_view(self.view, layout_env)))
        end,
        [Sem.SemDomainZipEq] = function(self, layout_env)
            return pvm.once(Sem.SemDomainZipEq(resolve_view_list(self.views, layout_env)))
        end,
    })

    resolve_expr = pvm.phase("moonlift_sem_layout_resolve_expr", {
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
        [Sem.SemExprBinding] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemExprNeg] = function(self, layout_env)
            return pvm.once(Sem.SemExprNeg(self.ty, one_expr(self.value, layout_env)))
        end,
        [Sem.SemExprNot] = function(self, layout_env)
            return pvm.once(Sem.SemExprNot(self.ty, one_expr(self.value, layout_env)))
        end,
        [Sem.SemExprBNot] = function(self, layout_env)
            return pvm.once(Sem.SemExprBNot(self.ty, one_expr(self.value, layout_env)))
        end,
        [Sem.SemExprAddrOf] = function(self, layout_env)
            return pvm.once(Sem.SemExprAddrOf(one_place(self.place, layout_env), self.ty))
        end,
        [Sem.SemExprDeref] = function(self, layout_env)
            return pvm.once(Sem.SemExprDeref(self.ty, one_expr(self.value, layout_env)))
        end,
        [Sem.SemExprAdd] = function(self, layout_env)
            return pvm.once(Sem.SemExprAdd(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprSub] = function(self, layout_env)
            return pvm.once(Sem.SemExprSub(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprMul] = function(self, layout_env)
            return pvm.once(Sem.SemExprMul(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprDiv] = function(self, layout_env)
            return pvm.once(Sem.SemExprDiv(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprRem] = function(self, layout_env)
            return pvm.once(Sem.SemExprRem(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprEq] = function(self, layout_env)
            return pvm.once(Sem.SemExprEq(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprNe] = function(self, layout_env)
            return pvm.once(Sem.SemExprNe(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprLt] = function(self, layout_env)
            return pvm.once(Sem.SemExprLt(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprLe] = function(self, layout_env)
            return pvm.once(Sem.SemExprLe(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprGt] = function(self, layout_env)
            return pvm.once(Sem.SemExprGt(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprGe] = function(self, layout_env)
            return pvm.once(Sem.SemExprGe(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprAnd] = function(self, layout_env)
            return pvm.once(Sem.SemExprAnd(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprOr] = function(self, layout_env)
            return pvm.once(Sem.SemExprOr(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprBitAnd] = function(self, layout_env)
            return pvm.once(Sem.SemExprBitAnd(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprBitOr] = function(self, layout_env)
            return pvm.once(Sem.SemExprBitOr(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprBitXor] = function(self, layout_env)
            return pvm.once(Sem.SemExprBitXor(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprShl] = function(self, layout_env)
            return pvm.once(Sem.SemExprShl(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprLShr] = function(self, layout_env)
            return pvm.once(Sem.SemExprLShr(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprAShr] = function(self, layout_env)
            return pvm.once(Sem.SemExprAShr(self.ty, one_expr(self.lhs, layout_env), one_expr(self.rhs, layout_env)))
        end,
        [Sem.SemExprCastTo] = function(self, layout_env)
            return pvm.once(Sem.SemExprCastTo(self.ty, one_expr(self.value, layout_env)))
        end,
        [Sem.SemExprTruncTo] = function(self, layout_env)
            return pvm.once(Sem.SemExprTruncTo(self.ty, one_expr(self.value, layout_env)))
        end,
        [Sem.SemExprZExtTo] = function(self, layout_env)
            return pvm.once(Sem.SemExprZExtTo(self.ty, one_expr(self.value, layout_env)))
        end,
        [Sem.SemExprSExtTo] = function(self, layout_env)
            return pvm.once(Sem.SemExprSExtTo(self.ty, one_expr(self.value, layout_env)))
        end,
        [Sem.SemExprBitcastTo] = function(self, layout_env)
            return pvm.once(Sem.SemExprBitcastTo(self.ty, one_expr(self.value, layout_env)))
        end,
        [Sem.SemExprSatCastTo] = function(self, layout_env)
            return pvm.once(Sem.SemExprSatCastTo(self.ty, one_expr(self.value, layout_env)))
        end,
        [Sem.SemExprSelect] = function(self, layout_env)
            return pvm.once(Sem.SemExprSelect(one_expr(self.cond, layout_env), one_expr(self.then_value, layout_env), one_expr(self.else_value, layout_env), self.ty))
        end,
        [Sem.SemExprIndex] = function(self, layout_env)
            return pvm.once(Sem.SemExprIndex(one_index_base(self.base, layout_env), one_expr(self.index, layout_env), self.ty))
        end,
        [Sem.SemExprField] = function(self, layout_env)
            local base = one_expr(self.base, layout_env)
            return pvm.once(Sem.SemExprField(base, one_field_ref(self.field, one_sem_expr_type(base), layout_env)))
        end,
        [Sem.SemExprLoad] = function(self, layout_env)
            return pvm.once(Sem.SemExprLoad(self.ty, one_expr(self.addr, layout_env)))
        end,
        [Sem.SemExprIntrinsicCall] = function(self, layout_env)
            return pvm.once(Sem.SemExprIntrinsicCall(self.op, self.ty, resolve_expr_list(self.args, layout_env)))
        end,
        [Sem.SemExprCall] = function(self, layout_env)
            return pvm.once(Sem.SemExprCall(one_call_target(self.target, layout_env), self.ty, resolve_expr_list(self.args, layout_env)))
        end,
        [Sem.SemExprAgg] = function(self, layout_env)
            return pvm.once(Sem.SemExprAgg(self.ty, resolve_field_init_list(self.fields, layout_env)))
        end,
        [Sem.SemExprArrayLit] = function(self, layout_env)
            return pvm.once(Sem.SemExprArrayLit(self.elem_ty, resolve_expr_list(self.elems, layout_env)))
        end,
        [Sem.SemExprBlock] = function(self, layout_env)
            return pvm.once(Sem.SemExprBlock(resolve_stmt_list(self.stmts, layout_env), one_expr(self.result, layout_env), self.ty))
        end,
        [Sem.SemExprIf] = function(self, layout_env)
            return pvm.once(Sem.SemExprIf(one_expr(self.cond, layout_env), one_expr(self.then_expr, layout_env), one_expr(self.else_expr, layout_env), self.ty))
        end,
        [Sem.SemExprSwitch] = function(self, layout_env)
            return pvm.once(Sem.SemExprSwitch(one_expr(self.value, layout_env), resolve_switch_expr_arm_list(self.arms, layout_env), one_expr(self.default_expr, layout_env), self.ty))
        end,
        [Sem.SemExprLoop] = function(self, layout_env)
            return pvm.once(Sem.SemExprLoop(one_loop(self.loop, layout_env), self.ty))
        end,
    })

    resolve_stmt = pvm.phase("moonlift_sem_layout_resolve_stmt", {
        [Sem.SemStmtLet] = function(self, layout_env)
            return pvm.once(Sem.SemStmtLet(self.id, self.name, self.ty, one_expr(self.init, layout_env)))
        end,
        [Sem.SemStmtVar] = function(self, layout_env)
            return pvm.once(Sem.SemStmtVar(self.id, self.name, self.ty, one_expr(self.init, layout_env)))
        end,
        [Sem.SemStmtSet] = function(self, layout_env)
            return pvm.once(Sem.SemStmtSet(one_place(self.place, layout_env), one_expr(self.value, layout_env)))
        end,
        [Sem.SemStmtExpr] = function(self, layout_env)
            return pvm.once(Sem.SemStmtExpr(one_expr(self.expr, layout_env)))
        end,
        [Sem.SemStmtIf] = function(self, layout_env)
            return pvm.once(Sem.SemStmtIf(one_expr(self.cond, layout_env), resolve_stmt_list(self.then_body, layout_env), resolve_stmt_list(self.else_body, layout_env)))
        end,
        [Sem.SemStmtSwitch] = function(self, layout_env)
            return pvm.once(Sem.SemStmtSwitch(one_expr(self.value, layout_env), resolve_switch_stmt_arm_list(self.arms, layout_env), resolve_stmt_list(self.default_body, layout_env)))
        end,
        [Sem.SemStmtAssert] = function(self, layout_env)
            return pvm.once(Sem.SemStmtAssert(one_expr(self.cond, layout_env)))
        end,
        [Sem.SemStmtReturnVoid] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemStmtReturnValue] = function(self, layout_env)
            return pvm.once(Sem.SemStmtReturnValue(one_expr(self.value, layout_env)))
        end,
        [Sem.SemStmtBreak] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemStmtBreakValue] = function(self, layout_env)
            return pvm.once(Sem.SemStmtBreakValue(one_expr(self.value, layout_env)))
        end,
        [Sem.SemStmtContinue] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemStmtLoop] = function(self, layout_env)
            return pvm.once(Sem.SemStmtLoop(one_loop(self.loop, layout_env)))
        end,
    })

    resolve_loop = pvm.phase("moonlift_sem_layout_resolve_loop", {
        [Sem.SemLoopWhileStmt] = function(self, layout_env)
            return pvm.once(Sem.SemLoopWhileStmt(self.loop_id, resolve_loop_carry_list(self.carries, layout_env), one_expr(self.cond, layout_env), resolve_stmt_list(self.body, layout_env), resolve_loop_update_list(self.next, layout_env)))
        end,
        [Sem.SemLoopOverStmt] = function(self, layout_env)
            return pvm.once(Sem.SemLoopOverStmt(self.loop_id, self.index_port, one_domain(self.domain, layout_env), resolve_loop_carry_list(self.carries, layout_env), resolve_stmt_list(self.body, layout_env), resolve_loop_update_list(self.next, layout_env)))
        end,
        [Sem.SemLoopWhileExpr] = function(self, layout_env)
            return pvm.once(Sem.SemLoopWhileExpr(self.loop_id, resolve_loop_carry_list(self.carries, layout_env), one_expr(self.cond, layout_env), resolve_stmt_list(self.body, layout_env), resolve_loop_update_list(self.next, layout_env), one_expr(self.result, layout_env)))
        end,
        [Sem.SemLoopOverExpr] = function(self, layout_env)
            return pvm.once(Sem.SemLoopOverExpr(self.loop_id, self.index_port, one_domain(self.domain, layout_env), resolve_loop_carry_list(self.carries, layout_env), resolve_stmt_list(self.body, layout_env), resolve_loop_update_list(self.next, layout_env), one_expr(self.result, layout_env)))
        end,
    })

    resolve_func = pvm.phase("moonlift_sem_layout_resolve_func", {
        [Sem.SemFuncLocal] = function(self, layout_env)
            return pvm.once(Sem.SemFuncLocal(self.name, self.params, self.result, resolve_stmt_list(self.body, layout_env)))
        end,
        [Sem.SemFuncExport] = function(self, layout_env)
            return pvm.once(Sem.SemFuncExport(self.name, self.params, self.result, resolve_stmt_list(self.body, layout_env)))
        end,
    })

    resolve_const = pvm.phase("moonlift_sem_layout_resolve_const", {
        [Sem.SemConst] = function(self, layout_env)
            return pvm.once(Sem.SemConst(self.name, self.ty, one_expr(self.value, layout_env)))
        end,
    })

    resolve_static = pvm.phase("moonlift_sem_layout_resolve_static", {
        [Sem.SemStatic] = function(self, layout_env)
            return pvm.once(Sem.SemStatic(self.name, self.ty, one_expr(self.value, layout_env)))
        end,
    })

    resolve_item = pvm.phase("moonlift_sem_layout_resolve_item", {
        [Sem.SemItemFunc] = function(self, layout_env)
            return pvm.once(Sem.SemItemFunc(one_func(self.func, layout_env)))
        end,
        [Sem.SemItemExtern] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemItemConst] = function(self, layout_env)
            return pvm.once(Sem.SemItemConst(one_const(self.c, layout_env)))
        end,
        [Sem.SemItemStatic] = function(self, layout_env)
            return pvm.once(Sem.SemItemStatic(one_static(self.s, layout_env)))
        end,
        [Sem.SemItemImport] = function(self)
            return pvm.once(self)
        end,
        [Sem.SemItemType] = function(self)
            return pvm.once(self)
        end,
    })

    resolve_module = pvm.phase("moonlift_sem_layout_resolve_module", {
        [Sem.SemModule] = function(self, layout_env)
            local use_layout_env = one_synthesized_layout_env(self, layout_env)
            local items = {}
            for i = 1, #self.items do
                items[i] = one_item(self.items[i], use_layout_env)
            end
            return pvm.once(Sem.SemModule(self.module_name, items))
        end,
    })

    return {
        sem_expr_type = sem_expr_type,
        sem_place_type = sem_place_type,
        synthesize_layout_env = synthesize_layout_env,
        resolve_type_mem_layout = resolve_type_mem_layout,
        resolve_type_layout = resolve_type_layout,
        resolve_field_ref = resolve_field_ref,
        resolve_view = resolve_view,
        resolve_place = resolve_place,
        resolve_expr = resolve_expr,
        resolve_stmt = resolve_stmt,
        resolve_loop = resolve_loop,
        resolve_domain = resolve_domain,
        resolve_func = resolve_func,
        resolve_const = resolve_const,
        resolve_static = resolve_static,
        resolve_item = resolve_item,
        resolve_module = resolve_module,
    }
end

return M
