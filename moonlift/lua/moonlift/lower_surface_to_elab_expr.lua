package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local LowerType = require("moonlift.lower_surface_to_elab")

local M = {}

function M.Define(T)
    local Surf = T.MoonliftSurface
    local Elab = T.MoonliftElab

    local type_lower = LowerType.Define(T).lower_type
    local lower_expr
    local expr_type
    local call_sig
    local index_elem_type
    local field_type
    local ref_result_type
    local deref_result_type
    local path_binding_matches

    local function one_type(node, env)
        return pvm.one(type_lower(node, env))
    end

    local function one_expr(node, env, expected_ty)
        return pvm.one(lower_expr(node, env, expected_ty))
    end

    local function one_expr_type(node)
        return pvm.one(expr_type(node))
    end

    local function find_value_binding(env, name)
        local values = env and env.values or nil
        if values == nil then return nil end
        for i = #values, 1, -1 do
            local entry = values[i]
            if entry.name == name then
                return entry.binding
            end
        end
        return nil
    end

    local function collect_name_parts(path)
        local parts = {}
        local arr = path.parts
        for i = 1, #arr do
            parts[i] = arr[i].text
        end
        return parts
    end

    local function split_value_path(path)
        local parts = collect_name_parts(path)
        if #parts == 0 then
            error("surface_to_elab_expr: empty value path")
        end
        local full_text = table.concat(parts, ".")
        if #parts == 1 then
            return full_text, "", parts[1]
        end
        local item_name = parts[#parts]
        parts[#parts] = nil
        return full_text, table.concat(parts, "."), item_name
    end

    local function find_path_binding(env, path)
        local values = env and env.values or nil
        if values == nil then return nil end
        local full_text, module_name, item_name = split_value_path(path)
        for i = #values, 1, -1 do
            local entry = values[i]
            if pvm.one(path_binding_matches(entry.binding, entry.name, full_text, module_name, item_name)) then
                return entry.binding
            end
        end
        return nil
    end

    local function binding_ty(binding)
        return binding.ty
    end

    local function find_named_layout(env, module_name, type_name)
        local layouts = env and env.layouts or nil
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

    local function is_integral_type(ty)
        return ty == Elab.ElabTI8 or ty == Elab.ElabTI16 or ty == Elab.ElabTI32 or ty == Elab.ElabTI64
            or ty == Elab.ElabTU8 or ty == Elab.ElabTU16 or ty == Elab.ElabTU32 or ty == Elab.ElabTU64
            or ty == Elab.ElabTIndex
    end

    local function is_float_type(ty)
        return ty == Elab.ElabTF32 or ty == Elab.ElabTF64
    end

    local function default_int_ty(expected_ty)
        if expected_ty ~= nil and is_integral_type(expected_ty) then
            return expected_ty
        end
        return Elab.ElabTI32
    end

    local function default_float_ty(expected_ty)
        if expected_ty ~= nil and is_float_type(expected_ty) then
            return expected_ty
        end
        return Elab.ElabTF64
    end

    local function comparison_result_ty()
        return Elab.ElabTBool
    end

    local function one_call_sig(node)
        return pvm.one(call_sig(node))
    end

    local function one_index_elem_type(node)
        return pvm.one(index_elem_type(node))
    end

    local function one_field_type(node, env, field_name)
        return pvm.one(field_type(node, env, field_name))
    end

    local function same_type_binary(ctor)
        return function(self, env)
            local lhs = one_expr(self.lhs, env, nil)
            local lhs_ty = one_expr_type(lhs)
            local rhs = one_expr(self.rhs, env, lhs_ty)
            local rhs_ty = one_expr_type(rhs)
            if lhs_ty ~= rhs_ty then
                error("surface_to_elab_expr: binary operands must currently have identical elaborated types")
            end
            return pvm.once(ctor(lhs_ty, lhs, rhs))
        end
    end

    local function cmp_binary(ctor)
        return function(self, env)
            local lhs = one_expr(self.lhs, env, nil)
            local lhs_ty = one_expr_type(lhs)
            local rhs = one_expr(self.rhs, env, lhs_ty)
            local rhs_ty = one_expr_type(rhs)
            if lhs_ty ~= rhs_ty then
                error("surface_to_elab_expr: comparison operands must currently have identical elaborated types")
            end
            return pvm.once(ctor(comparison_result_ty(), lhs, rhs))
        end
    end

    local function bool_binary(ctor)
        return function(self, env)
            local lhs = one_expr(self.lhs, env, Elab.ElabTBool)
            local lhs_ty = one_expr_type(lhs)
            local rhs = one_expr(self.rhs, env, Elab.ElabTBool)
            local rhs_ty = one_expr_type(rhs)
            if lhs_ty ~= Elab.ElabTBool or rhs_ty ~= Elab.ElabTBool then
                error("surface_to_elab_expr: logical and/or currently require bool operands")
            end
            return pvm.once(ctor(Elab.ElabTBool, lhs, rhs))
        end
    end

    local function unary_same_type(ctor)
        return function(self, env, expected_ty)
            local value = one_expr(self.value, env, expected_ty)
            local ty = expected_ty or one_expr_type(value)
            return pvm.once(ctor(ty, value))
        end
    end

    local function cast_handler(ctor)
        return function(self, env)
            local ty = one_type(self.ty, env)
            local value = one_expr(self.value, env, nil)
            return pvm.once(ctor(ty, value))
        end
    end

    ref_result_type = pvm.phase("surface_to_elab_ref_result_type", {
        [Elab.ElabTVoid] = function(self)
            return pvm.once(Elab.ElabTPtr(self))
        end,
        [Elab.ElabTBool] = function(self)
            return pvm.once(Elab.ElabTPtr(self))
        end,
        [Elab.ElabTI8] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTI16] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTI32] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTI64] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTU8] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTU16] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTU32] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTU64] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTF32] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTF64] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTIndex] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTPtr] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTArray] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTSlice] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTFunc] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
        [Elab.ElabTNamed] = function(self) return pvm.once(Elab.ElabTPtr(self)) end,
    })

    deref_result_type = pvm.phase("surface_to_elab_deref_result_type", {
        [Elab.ElabTPtr] = function(self)
            return pvm.once(self.elem)
        end,
        [Elab.ElabTVoid] = function() error("surface_to_elab_expr: cannot dereference a void-typed value") end,
        [Elab.ElabTBool] = function() error("surface_to_elab_expr: cannot dereference a bool-typed value") end,
        [Elab.ElabTI8] = function() error("surface_to_elab_expr: cannot dereference an integer-typed value") end,
        [Elab.ElabTI16] = function() error("surface_to_elab_expr: cannot dereference an integer-typed value") end,
        [Elab.ElabTI32] = function() error("surface_to_elab_expr: cannot dereference an integer-typed value") end,
        [Elab.ElabTI64] = function() error("surface_to_elab_expr: cannot dereference an integer-typed value") end,
        [Elab.ElabTU8] = function() error("surface_to_elab_expr: cannot dereference an integer-typed value") end,
        [Elab.ElabTU16] = function() error("surface_to_elab_expr: cannot dereference an integer-typed value") end,
        [Elab.ElabTU32] = function() error("surface_to_elab_expr: cannot dereference an integer-typed value") end,
        [Elab.ElabTU64] = function() error("surface_to_elab_expr: cannot dereference an integer-typed value") end,
        [Elab.ElabTF32] = function() error("surface_to_elab_expr: cannot dereference a float-typed value") end,
        [Elab.ElabTF64] = function() error("surface_to_elab_expr: cannot dereference a float-typed value") end,
        [Elab.ElabTIndex] = function() error("surface_to_elab_expr: cannot dereference an index-typed value") end,
        [Elab.ElabTArray] = function() error("surface_to_elab_expr: cannot dereference an array-typed value") end,
        [Elab.ElabTSlice] = function() error("surface_to_elab_expr: cannot dereference a slice-typed value") end,
        [Elab.ElabTFunc] = function() error("surface_to_elab_expr: cannot dereference a function-typed value") end,
        [Elab.ElabTNamed] = function() error("surface_to_elab_expr: cannot dereference a named aggregate value") end,
    })

    path_binding_matches = pvm.phase("surface_to_elab_path_binding_matches", {
        [Elab.ElabLocalValue] = function(self, entry_name, full_text)
            return pvm.once(entry_name == full_text)
        end,
        [Elab.ElabLocalStoredValue] = function(self, entry_name, full_text)
            return pvm.once(entry_name == full_text)
        end,
        [Elab.ElabLocalCell] = function(self, entry_name, full_text)
            return pvm.once(entry_name == full_text)
        end,
        [Elab.ElabArg] = function(self, entry_name, full_text)
            return pvm.once(entry_name == full_text)
        end,
        [Elab.ElabExtern] = function(self, entry_name, full_text)
            return pvm.once(entry_name == full_text)
        end,
        [Elab.ElabGlobal] = function(self, entry_name, full_text, module_name, item_name)
            if entry_name == full_text then
                return pvm.once(true)
            end
            return pvm.once(self.module_name == module_name and self.item_name == item_name)
        end,
    })

    call_sig = pvm.phase("surface_to_elab_call_sig", {
        [Elab.ElabTFunc] = function(self)
            return pvm.once(self)
        end,
        [Elab.ElabTVoid] = function()
            error("surface_to_elab_expr: cannot call a void-typed value")
        end,
        [Elab.ElabTBool] = function()
            error("surface_to_elab_expr: cannot call a bool-typed value")
        end,
        [Elab.ElabTI8] = function() error("surface_to_elab_expr: cannot call an integer-typed value") end,
        [Elab.ElabTI16] = function() error("surface_to_elab_expr: cannot call an integer-typed value") end,
        [Elab.ElabTI32] = function() error("surface_to_elab_expr: cannot call an integer-typed value") end,
        [Elab.ElabTI64] = function() error("surface_to_elab_expr: cannot call an integer-typed value") end,
        [Elab.ElabTU8] = function() error("surface_to_elab_expr: cannot call an integer-typed value") end,
        [Elab.ElabTU16] = function() error("surface_to_elab_expr: cannot call an integer-typed value") end,
        [Elab.ElabTU32] = function() error("surface_to_elab_expr: cannot call an integer-typed value") end,
        [Elab.ElabTU64] = function() error("surface_to_elab_expr: cannot call an integer-typed value") end,
        [Elab.ElabTF32] = function() error("surface_to_elab_expr: cannot call a float-typed value") end,
        [Elab.ElabTF64] = function() error("surface_to_elab_expr: cannot call a float-typed value") end,
        [Elab.ElabTIndex] = function() error("surface_to_elab_expr: cannot call an index-typed value") end,
        [Elab.ElabTPtr] = function() error("surface_to_elab_expr: cannot call a pointer-typed value") end,
        [Elab.ElabTArray] = function() error("surface_to_elab_expr: cannot call an array-typed value") end,
        [Elab.ElabTSlice] = function() error("surface_to_elab_expr: cannot call a slice-typed value") end,
        [Elab.ElabTNamed] = function() error("surface_to_elab_expr: cannot call a named aggregate value") end,
    })

    index_elem_type = pvm.phase("surface_to_elab_index_elem_type", {
        [Elab.ElabTPtr] = function(self) return pvm.once(self.elem) end,
        [Elab.ElabTArray] = function(self) return pvm.once(self.elem) end,
        [Elab.ElabTSlice] = function(self) return pvm.once(self.elem) end,
        [Elab.ElabTVoid] = function() error("surface_to_elab_expr: cannot index a void-typed value") end,
        [Elab.ElabTBool] = function() error("surface_to_elab_expr: cannot index a bool-typed value") end,
        [Elab.ElabTI8] = function() error("surface_to_elab_expr: cannot index an integer-typed value") end,
        [Elab.ElabTI16] = function() error("surface_to_elab_expr: cannot index an integer-typed value") end,
        [Elab.ElabTI32] = function() error("surface_to_elab_expr: cannot index an integer-typed value") end,
        [Elab.ElabTI64] = function() error("surface_to_elab_expr: cannot index an integer-typed value") end,
        [Elab.ElabTU8] = function() error("surface_to_elab_expr: cannot index an integer-typed value") end,
        [Elab.ElabTU16] = function() error("surface_to_elab_expr: cannot index an integer-typed value") end,
        [Elab.ElabTU32] = function() error("surface_to_elab_expr: cannot index an integer-typed value") end,
        [Elab.ElabTU64] = function() error("surface_to_elab_expr: cannot index an integer-typed value") end,
        [Elab.ElabTF32] = function() error("surface_to_elab_expr: cannot index a float-typed value") end,
        [Elab.ElabTF64] = function() error("surface_to_elab_expr: cannot index a float-typed value") end,
        [Elab.ElabTIndex] = function() error("surface_to_elab_expr: cannot index an index-typed value") end,
        [Elab.ElabTFunc] = function() error("surface_to_elab_expr: cannot index a function-typed value") end,
        [Elab.ElabTNamed] = function() error("surface_to_elab_expr: cannot index a named aggregate value without an explicit indexable representation") end,
    })

    field_type = pvm.phase("surface_to_elab_field_type", {
        [Elab.ElabTNamed] = function(self, env, field_name)
            local layout = find_named_layout(env, self.module_name, self.type_name)
            if layout == nil then
                error("surface_to_elab_expr: missing field layout for named type '" .. (self.module_name ~= "" and (self.module_name .. ".") or "") .. self.type_name .. "'")
            end
            local field = find_layout_field(layout, field_name)
            if field == nil then
                error("surface_to_elab_expr: unknown field '" .. field_name .. "' on named type '" .. (self.module_name ~= "" and (self.module_name .. ".") or "") .. self.type_name .. "'")
            end
            return pvm.once(field.ty)
        end,
        [Elab.ElabTVoid] = function() error("surface_to_elab_expr: cannot select a field from void") end,
        [Elab.ElabTBool] = function() error("surface_to_elab_expr: cannot select a field from bool") end,
        [Elab.ElabTI8] = function() error("surface_to_elab_expr: cannot select a field from an integer value") end,
        [Elab.ElabTI16] = function() error("surface_to_elab_expr: cannot select a field from an integer value") end,
        [Elab.ElabTI32] = function() error("surface_to_elab_expr: cannot select a field from an integer value") end,
        [Elab.ElabTI64] = function() error("surface_to_elab_expr: cannot select a field from an integer value") end,
        [Elab.ElabTU8] = function() error("surface_to_elab_expr: cannot select a field from an integer value") end,
        [Elab.ElabTU16] = function() error("surface_to_elab_expr: cannot select a field from an integer value") end,
        [Elab.ElabTU32] = function() error("surface_to_elab_expr: cannot select a field from an integer value") end,
        [Elab.ElabTU64] = function() error("surface_to_elab_expr: cannot select a field from an integer value") end,
        [Elab.ElabTF32] = function() error("surface_to_elab_expr: cannot select a field from a float value") end,
        [Elab.ElabTF64] = function() error("surface_to_elab_expr: cannot select a field from a float value") end,
        [Elab.ElabTIndex] = function() error("surface_to_elab_expr: cannot select a field from an index value") end,
        [Elab.ElabTPtr] = function() error("surface_to_elab_expr: cannot select a field from a pointer value; dereference first if the pointee is an aggregate") end,
        [Elab.ElabTArray] = function() error("surface_to_elab_expr: cannot select a named field from an array value") end,
        [Elab.ElabTSlice] = function() error("surface_to_elab_expr: cannot select a named field from a slice value") end,
        [Elab.ElabTFunc] = function() error("surface_to_elab_expr: cannot select a field from a function value") end,
    })

    expr_type = pvm.phase("elab_expr_type", {
        [Elab.ElabInt] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabFloat] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabBool] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabNil] = function(self) return pvm.once(self.ty) end,
        [Elab.ElabBindingExpr] = function(self) return pvm.once(binding_ty(self.binding)) end,
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

    lower_expr = pvm.phase("surface_to_elab_expr", {
        [Surf.SurfInt] = function(self, env, expected_ty)
            return pvm.once(Elab.ElabInt(self.raw, default_int_ty(expected_ty)))
        end,
        [Surf.SurfFloat] = function(self, env, expected_ty)
            return pvm.once(Elab.ElabFloat(self.raw, default_float_ty(expected_ty)))
        end,
        [Surf.SurfBool] = function(self)
            return pvm.once(Elab.ElabBool(self.value, Elab.ElabTBool))
        end,
        [Surf.SurfNil] = function(self, env, expected_ty)
            if expected_ty == nil then
                error("surface_to_elab_expr: nil requires an expected type")
            end
            return pvm.once(Elab.ElabNil(expected_ty))
        end,
        [Surf.SurfNameRef] = function(self, env)
            local binding = find_value_binding(env, self.name)
            if binding == nil then
                error("surface_to_elab_expr: unknown binding '" .. self.name .. "'")
            end
            return pvm.once(Elab.ElabBindingExpr(binding))
        end,
        [Surf.SurfPathRef] = function(self, env)
            local binding = find_path_binding(env, self.path)
            if binding == nil then
                local full_text = split_value_path(self.path)
                error("surface_to_elab_expr: unknown qualified binding '" .. full_text .. "'")
            end
            return pvm.once(Elab.ElabBindingExpr(binding))
        end,
        [Surf.SurfExprNeg] = unary_same_type(Elab.ElabExprNeg),
        [Surf.SurfExprNot] = unary_same_type(Elab.ElabExprNot),
        [Surf.SurfExprBNot] = unary_same_type(Elab.ElabExprBNot),
        [Surf.SurfExprRef] = function(self, env)
            local value = one_expr(self.value, env, nil)
            return pvm.once(Elab.ElabExprRef(pvm.one(ref_result_type(one_expr_type(value))), value))
        end,
        [Surf.SurfExprDeref] = function(self, env)
            local value = one_expr(self.value, env, nil)
            return pvm.once(Elab.ElabExprDeref(pvm.one(deref_result_type(one_expr_type(value))), value))
        end,
        [Surf.SurfExprAdd] = same_type_binary(Elab.ElabExprAdd),
        [Surf.SurfExprSub] = same_type_binary(Elab.ElabExprSub),
        [Surf.SurfExprMul] = same_type_binary(Elab.ElabExprMul),
        [Surf.SurfExprDiv] = same_type_binary(Elab.ElabExprDiv),
        [Surf.SurfExprRem] = same_type_binary(Elab.ElabExprRem),
        [Surf.SurfExprEq] = cmp_binary(Elab.ElabExprEq),
        [Surf.SurfExprNe] = cmp_binary(Elab.ElabExprNe),
        [Surf.SurfExprLt] = cmp_binary(Elab.ElabExprLt),
        [Surf.SurfExprLe] = cmp_binary(Elab.ElabExprLe),
        [Surf.SurfExprGt] = cmp_binary(Elab.ElabExprGt),
        [Surf.SurfExprGe] = cmp_binary(Elab.ElabExprGe),
        [Surf.SurfExprAnd] = bool_binary(Elab.ElabExprAnd),
        [Surf.SurfExprOr] = bool_binary(Elab.ElabExprOr),
        [Surf.SurfExprBitAnd] = same_type_binary(Elab.ElabExprBitAnd),
        [Surf.SurfExprBitOr] = same_type_binary(Elab.ElabExprBitOr),
        [Surf.SurfExprBitXor] = same_type_binary(Elab.ElabExprBitXor),
        [Surf.SurfExprShl] = same_type_binary(Elab.ElabExprShl),
        [Surf.SurfExprLShr] = same_type_binary(Elab.ElabExprLShr),
        [Surf.SurfExprAShr] = same_type_binary(Elab.ElabExprAShr),
        [Surf.SurfExprCastTo] = cast_handler(Elab.ElabExprCastTo),
        [Surf.SurfExprTruncTo] = cast_handler(Elab.ElabExprTruncTo),
        [Surf.SurfExprZExtTo] = cast_handler(Elab.ElabExprZExtTo),
        [Surf.SurfExprSExtTo] = cast_handler(Elab.ElabExprSExtTo),
        [Surf.SurfExprBitcastTo] = cast_handler(Elab.ElabExprBitcastTo),
        [Surf.SurfExprSatCastTo] = cast_handler(Elab.ElabExprSatCastTo),
        [Surf.SurfCall] = function(self, env)
            local callee = one_expr(self.callee, env, nil)
            local sig = one_call_sig(one_expr_type(callee))
            if #self.args ~= #sig.params then
                error("surface_to_elab_expr: call argument count does not match function type")
            end
            local args = {}
            for i = 1, #self.args do
                args[i] = one_expr(self.args[i], env, sig.params[i])
            end
            return pvm.once(Elab.ElabCall(callee, sig.result, args))
        end,
        [Surf.SurfField] = function(self, env)
            local base = one_expr(self.base, env, nil)
            local ty = one_field_type(one_expr_type(base), env, self.name)
            return pvm.once(Elab.ElabField(base, self.name, ty))
        end,
        [Surf.SurfIndex] = function(self, env)
            local base = one_expr(self.base, env, nil)
            local elem_ty = one_index_elem_type(one_expr_type(base))
            local index = one_expr(self.index, env, Elab.ElabTIndex)
            return pvm.once(Elab.ElabIndex(base, index, elem_ty))
        end,
        [Surf.SurfAgg] = function(self, env)
            local ty = one_type(self.ty, env)
            local fields = {}
            for i = 1, #self.fields do
                local field_init = self.fields[i]
                fields[i] = Elab.ElabFieldInit(field_init.name, one_expr(field_init.value, env, one_field_type(ty, env, field_init.name)))
            end
            return pvm.once(Elab.ElabAgg(ty, fields))
        end,
        [Surf.SurfArrayLit] = function(self, env)
            local elem_ty = one_type(self.elem_ty, env)
            local elems = {}
            for i = 1, #self.elems do
                elems[i] = one_expr(self.elems[i], env, elem_ty)
            end
            return pvm.once(Elab.ElabArrayLit(Elab.ElabTArray(Elab.ElabInt(tostring(#self.elems), Elab.ElabTIndex), elem_ty), elems))
        end,
    })

    return {
        lower_type = type_lower,
        lower_expr = lower_expr,
        expr_type = expr_type,
    }
end

return M
