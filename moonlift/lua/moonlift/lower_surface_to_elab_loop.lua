package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local LowerExpr = require("moonlift.lower_surface_to_elab_expr")

local M = {}

function M.Define(T)
    local Surf = T.MoonliftSurface
    local Elab = T.MoonliftElab

    local expr_api = LowerExpr.Define(T)
    local lower_type = expr_api.lower_type
    local base_lower_expr = expr_api.lower_expr
    local lower_expr
    local lower_domain

    local lower_stmt
    local lower_loop_stmt
    local lower_loop_expr
    local lower_loop_binding
    local lower_loop_next
    local lower_switch_stmt_arm
    local lower_switch_expr_arm
    local stmt_env_effect
    local apply_stmt_env_effect
    local set_target_binding

    local function one_type(node, env)
        return pvm.one(lower_type(node, env))
    end

    local function one_expr(node, env, expected_ty)
        return pvm.one(lower_expr(node, env, expected_ty))
    end

    local function one_domain(node, env)
        return pvm.one(lower_domain(node, env))
    end

    local function one_stmt(node, env, path)
        return pvm.one(lower_stmt(node, env, path))
    end

    local function one_loop_stmt(node, env, path)
        return pvm.one(lower_loop_stmt(node, env, path))
    end

    local function one_loop_expr(node, env, path)
        return pvm.one(lower_loop_expr(node, env, path))
    end

    local function one_binding(node, env, id)
        return pvm.one(lower_loop_binding(node, env, id))
    end

    local function one_next(node, env, loop_bindings)
        return pvm.one(lower_loop_next(node, env, loop_bindings))
    end

    local function one_switch_stmt_arm(node, env, path)
        return pvm.one(lower_switch_stmt_arm(node, env, path))
    end

    local function one_switch_expr_arm(node, env, path, expected_ty)
        return pvm.one(lower_switch_expr_arm(node, env, path, expected_ty))
    end

    local function one_stmt_effect(node)
        return pvm.one(stmt_env_effect(node))
    end

    local function apply_effect(effect, env)
        return pvm.one(apply_stmt_env_effect(effect, env))
    end

    local function one_set_target_binding(binding)
        return pvm.one(set_target_binding(binding))
    end

    local function scoped_path(base, suffix)
        if base == nil or base == "" then
            return suffix
        end
        return base .. "." .. suffix
    end

    local function implicit_path(tag, node)
        return tag .. "." .. string.gsub(tostring(node), "[^%w]", "_")
    end

    local function path_or_implicit(tag, node, path)
        if path ~= nil and path ~= "" then
            return path
        end
        return implicit_path(tag, node)
    end

    local function extend_env_value(env, entry)
        local values = {}
        local old_values = env.values or {}
        for i = 1, #old_values do values[i] = old_values[i] end
        values[#values + 1] = entry
        return pvm.with(env, { values = values })
    end

    local function lower_stmt_list(stmts, env, base_path)
        local out = {}
        local current_env = env
        for i = 1, #stmts do
            local stmt = one_stmt(stmts[i], current_env, scoped_path(base_path, "stmt." .. i))
            out[i] = stmt
            current_env = apply_effect(one_stmt_effect(stmt), current_env)
        end
        return out, current_env
    end

    local function lower_bindings(bindings, outer_env, base_path)
        local out = {}
        local loop_env = outer_env
        local loop_bindings = {}
        for i = 1, #bindings do
            local id = scoped_path(base_path, "binding." .. i)
            local b = one_binding(bindings[i], outer_env, id)
            local binding = Elab.ElabLocalStoredValue(b.id, b.name, b.ty)
            out[i] = b
            loop_bindings[b.name] = binding
            loop_env = extend_env_value(loop_env, Elab.ElabValueEntry(b.name, binding))
        end
        return out, loop_env, loop_bindings
    end

    stmt_env_effect = pvm.phase("elab_stmt_env_effect", {
        [Elab.ElabLet] = function(self)
            return pvm.once(Elab.ElabAddBinding(Elab.ElabValueEntry(self.name, Elab.ElabLocalStoredValue(self.id, self.name, self.ty))))
        end,
        [Elab.ElabVar] = function(self)
            return pvm.once(Elab.ElabAddBinding(Elab.ElabValueEntry(self.name, Elab.ElabLocalCell(self.id, self.name, self.ty))))
        end,
        [Elab.ElabSet] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabStore] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabExprStmt] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabIf] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabSwitch] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabReturnVoid] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabReturnValue] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabBreak] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabContinue] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabLoopStmtNode] = function() return pvm.once(Elab.ElabNoBinding) end,
    })

    apply_stmt_env_effect = pvm.phase("apply_elab_stmt_env_effect", {
        [Elab.ElabNoBinding] = function(self, env)
            return pvm.once(env)
        end,
        [Elab.ElabAddBinding] = function(self, env)
            return pvm.once(extend_env_value(env, self.entry))
        end,
    })

    set_target_binding = pvm.phase("elab_set_target_binding", {
        [Elab.ElabLocalCell] = function(self)
            return pvm.once(self)
        end,
        [Elab.ElabLocalValue] = function(self)
            error("surface_to_elab_stmt: cannot assign to immutable local '" .. self.name .. "'")
        end,
        [Elab.ElabLocalStoredValue] = function(self)
            error("surface_to_elab_stmt: cannot assign to immutable local '" .. self.name .. "'")
        end,
        [Elab.ElabArg] = function(self)
            error("surface_to_elab_stmt: cannot assign to argument '" .. self.name .. "'")
        end,
        [Elab.ElabGlobal] = function(self)
            error("surface_to_elab_stmt: assignment to globals is not yet supported ('" .. self.item_name .. "')")
        end,
        [Elab.ElabExtern] = function(self)
            error("surface_to_elab_stmt: cannot assign to extern '" .. self.symbol .. "'")
        end,
    })

    lower_loop_binding = pvm.phase("surface_to_elab_loop_binding", {
        [Surf.SurfLoopVarInit] = function(self, env, id)
            local ty = one_type(self.ty, env)
            local init = one_expr(self.init, env, ty)
            return pvm.once(Elab.ElabLoopBinding(id, self.name, ty, init))
        end,
    })

    lower_loop_next = pvm.phase("surface_to_elab_loop_next", {
        [Surf.SurfLoopNextAssign] = function(self, env, loop_bindings)
            local binding = loop_bindings[self.name]
            if binding == nil then
                error("surface_to_elab_loop: next assignment for unknown loop binding '" .. self.name .. "'")
            end
            return pvm.once(Elab.ElabLoopNext(binding, one_expr(self.value, env, binding.ty)))
        end,
    })

    lower_switch_stmt_arm = pvm.phase("surface_to_elab_switch_stmt_arm", {
        [Surf.SurfSwitchStmtArm] = function(self, env, path)
            local key = one_expr(self.key, env, nil)
            local body, _ = lower_stmt_list(self.body, env, scoped_path(path, "body"))
            return pvm.once(Elab.ElabSwitchStmtArm(key, body))
        end,
    })

    lower_switch_expr_arm = pvm.phase("surface_to_elab_switch_expr_arm", {
        [Surf.SurfSwitchExprArm] = function(self, env, path, expected_ty)
            local key = one_expr(self.key, env, nil)
            local body, body_env = lower_stmt_list(self.body, env, scoped_path(path, "body"))
            local result = one_expr(self.result, body_env, expected_ty)
            return pvm.once(Elab.ElabSwitchExprArm(key, body, result))
        end,
    })

    lower_loop_stmt = pvm.phase("surface_to_elab_loop_stmt", {
        [Surf.SurfLoopWhileStmt] = function(self, env, path)
            local base = path_or_implicit("loop.while.stmt", self, path)
            local vars, loop_env, loop_bindings = lower_bindings(self.vars, env, scoped_path(base, "vars"))
            local cond = one_expr(self.cond, loop_env, Elab.ElabTBool)
            local body, body_env = lower_stmt_list(self.body, loop_env, scoped_path(base, "body"))
            local next_out = {}
            for i = 1, #self.next do
                next_out[i] = one_next(self.next[i], body_env, loop_bindings)
            end
            return pvm.once(Elab.ElabLoopWhileStmt(vars, cond, body, next_out))
        end,

        [Surf.SurfLoopOverStmt] = function(self, env, path)
            local base = path_or_implicit("loop.over.stmt", self, path)
            local carries, loop_env, loop_bindings = lower_bindings(self.carries, env, scoped_path(base, "carries"))
            local domain = one_domain(self.domain, loop_env)
            local index_binding = Elab.ElabLocalStoredValue(scoped_path(base, "index"), self.index_name, Elab.ElabTIndex)
            loop_env = extend_env_value(loop_env, Elab.ElabValueEntry(self.index_name, index_binding))
            local body, body_env = lower_stmt_list(self.body, loop_env, scoped_path(base, "body"))
            local next_out = {}
            for i = 1, #self.next do
                next_out[i] = one_next(self.next[i], body_env, loop_bindings)
            end
            return pvm.once(Elab.ElabLoopOverStmt(index_binding, domain, carries, body, next_out))
        end,
    })

    lower_loop_expr = pvm.phase("surface_to_elab_loop_expr", {
        [Surf.SurfLoopWhileExpr] = function(self, env, path)
            local base = path_or_implicit("loop.while.expr", self, path)
            local vars, loop_env, loop_bindings = lower_bindings(self.vars, env, scoped_path(base, "vars"))
            local cond = one_expr(self.cond, loop_env, Elab.ElabTBool)
            local body, body_env = lower_stmt_list(self.body, loop_env, scoped_path(base, "body"))
            local next_out = {}
            for i = 1, #self.next do
                next_out[i] = one_next(self.next[i], body_env, loop_bindings)
            end
            local result = one_expr(self.result, loop_env, nil)
            return pvm.once(Elab.ElabLoopExprNode(
                Elab.ElabLoopWhileExpr(vars, cond, body, next_out, result),
                pvm.one(expr_api.expr_type(result))
            ))
        end,

        [Surf.SurfLoopOverExpr] = function(self, env, path)
            local base = path_or_implicit("loop.over.expr", self, path)
            local carries, loop_env, loop_bindings = lower_bindings(self.carries, env, scoped_path(base, "carries"))
            local domain = one_domain(self.domain, loop_env)
            local index_binding = Elab.ElabLocalStoredValue(scoped_path(base, "index"), self.index_name, Elab.ElabTIndex)
            loop_env = extend_env_value(loop_env, Elab.ElabValueEntry(self.index_name, index_binding))
            local body, body_env = lower_stmt_list(self.body, loop_env, scoped_path(base, "body"))
            local next_out = {}
            for i = 1, #self.next do
                next_out[i] = one_next(self.next[i], body_env, loop_bindings)
            end
            local result = one_expr(self.result, loop_env, nil)
            return pvm.once(Elab.ElabLoopExprNode(
                Elab.ElabLoopOverExpr(index_binding, domain, carries, body, next_out, result),
                pvm.one(expr_api.expr_type(result))
            ))
        end,
    })

    local function delegate_base_expr(self, env, expected_ty)
        return pvm.once(pvm.one(base_lower_expr(self, env, expected_ty)))
    end

    lower_expr = pvm.phase("surface_to_elab_control_expr", {
        [Surf.SurfInt] = delegate_base_expr,
        [Surf.SurfFloat] = delegate_base_expr,
        [Surf.SurfBool] = delegate_base_expr,
        [Surf.SurfNil] = delegate_base_expr,
        [Surf.SurfNameRef] = delegate_base_expr,
        [Surf.SurfPathRef] = delegate_base_expr,
        [Surf.SurfExprNeg] = delegate_base_expr,
        [Surf.SurfExprNot] = delegate_base_expr,
        [Surf.SurfExprBNot] = delegate_base_expr,
        [Surf.SurfExprRef] = delegate_base_expr,
        [Surf.SurfExprDeref] = delegate_base_expr,
        [Surf.SurfExprAdd] = delegate_base_expr,
        [Surf.SurfExprSub] = delegate_base_expr,
        [Surf.SurfExprMul] = delegate_base_expr,
        [Surf.SurfExprDiv] = delegate_base_expr,
        [Surf.SurfExprRem] = delegate_base_expr,
        [Surf.SurfExprEq] = delegate_base_expr,
        [Surf.SurfExprNe] = delegate_base_expr,
        [Surf.SurfExprLt] = delegate_base_expr,
        [Surf.SurfExprLe] = delegate_base_expr,
        [Surf.SurfExprGt] = delegate_base_expr,
        [Surf.SurfExprGe] = delegate_base_expr,
        [Surf.SurfExprAnd] = delegate_base_expr,
        [Surf.SurfExprOr] = delegate_base_expr,
        [Surf.SurfExprBitAnd] = delegate_base_expr,
        [Surf.SurfExprBitOr] = delegate_base_expr,
        [Surf.SurfExprBitXor] = delegate_base_expr,
        [Surf.SurfExprShl] = delegate_base_expr,
        [Surf.SurfExprLShr] = delegate_base_expr,
        [Surf.SurfExprAShr] = delegate_base_expr,
        [Surf.SurfExprCastTo] = delegate_base_expr,
        [Surf.SurfExprTruncTo] = delegate_base_expr,
        [Surf.SurfExprZExtTo] = delegate_base_expr,
        [Surf.SurfExprSExtTo] = delegate_base_expr,
        [Surf.SurfExprBitcastTo] = delegate_base_expr,
        [Surf.SurfExprSatCastTo] = delegate_base_expr,
        [Surf.SurfIfExpr] = function(self, env, expected_ty)
            local cond = one_expr(self.cond, env, Elab.ElabTBool)
            local then_expr = one_expr(self.then_expr, env, expected_ty)
            local then_ty = pvm.one(expr_api.expr_type(then_expr))
            local else_expr = one_expr(self.else_expr, env, then_ty)
            local else_ty = pvm.one(expr_api.expr_type(else_expr))
            if then_ty ~= else_ty then
                error("surface_to_elab_expr: if expr branches must currently have identical elaborated types")
            end
            return pvm.once(Elab.ElabIfExpr(cond, then_expr, else_expr, then_ty))
        end,
        [Surf.SurfSwitchExpr] = function(self, env, expected_ty)
            local base = implicit_path("switch.expr", self)
            local value = one_expr(self.value, env, nil)
            local value_ty = pvm.one(expr_api.expr_type(value))
            local default_expr = one_expr(self.default_expr, env, expected_ty)
            local result_ty = pvm.one(expr_api.expr_type(default_expr))
            local arms = {}
            for i = 1, #self.arms do
                local arm = one_switch_expr_arm(self.arms[i], env, scoped_path(base, "arm." .. i), result_ty)
                local key_ty = pvm.one(expr_api.expr_type(arm.key))
                local arm_result_ty = pvm.one(expr_api.expr_type(arm.result))
                if key_ty ~= value_ty then
                    error("surface_to_elab_expr: switch expr arm key must currently have the same elaborated type as the switch value")
                end
                if arm_result_ty ~= result_ty then
                    error("surface_to_elab_expr: switch expr arm results must currently have identical elaborated types")
                end
                arms[i] = arm
            end
            return pvm.once(Elab.ElabSwitchExpr(value, arms, default_expr, result_ty))
        end,
        [Surf.SurfLoopExprNode] = function(self, env)
            return pvm.once(one_loop_expr(self.loop, env, implicit_path("loop.expr", self)))
        end,
        [Surf.SurfBlockExpr] = function(self, env, expected_ty)
            local base = implicit_path("block.expr", self)
            local stmts, block_env = lower_stmt_list(self.stmts, env, scoped_path(base, "stmts"))
            local result = one_expr(self.result, block_env, expected_ty)
            return pvm.once(Elab.ElabBlockExpr(stmts, result, pvm.one(expr_api.expr_type(result))))
        end,
        [Surf.SurfCall] = delegate_base_expr,
        [Surf.SurfField] = delegate_base_expr,
        [Surf.SurfIndex] = delegate_base_expr,
        [Surf.SurfAgg] = delegate_base_expr,
        [Surf.SurfArrayLit] = delegate_base_expr,
    })

    lower_domain = pvm.phase("surface_to_elab_domain", {
        [Surf.SurfDomainRange] = function(self, env)
            return pvm.once(Elab.ElabDomainRange(one_expr(self.stop, env, nil)))
        end,
        [Surf.SurfDomainRange2] = function(self, env)
            return pvm.once(Elab.ElabDomainRange2(one_expr(self.start, env, nil), one_expr(self.stop, env, nil)))
        end,
        [Surf.SurfDomainZipEq] = function(self, env)
            local out = {}
            for i = 1, #self.values do
                out[i] = one_expr(self.values[i], env, nil)
            end
            return pvm.once(Elab.ElabDomainZipEq(out))
        end,
        [Surf.SurfDomainValue] = function(self, env)
            return pvm.once(Elab.ElabDomainValue(one_expr(self.value, env, nil)))
        end,
    })

    lower_stmt = pvm.phase("surface_to_elab_stmt", {
        [Surf.SurfExprStmt] = function(self, env, path)
            return pvm.once(Elab.ElabExprStmt(one_expr(self.expr, env, nil)))
        end,
        [Surf.SurfLet] = function(self, env, path)
            local ty = one_type(self.ty, env)
            local id = path_or_implicit("let." .. self.name, self, path)
            return pvm.once(Elab.ElabLet(id, self.name, ty, one_expr(self.init, env, ty)))
        end,
        [Surf.SurfVar] = function(self, env, path)
            local ty = one_type(self.ty, env)
            local id = path_or_implicit("var." .. self.name, self, path)
            return pvm.once(Elab.ElabVar(id, self.name, ty, one_expr(self.init, env, ty)))
        end,
        [Surf.SurfSet] = function(self, env, path)
            local binding = nil
            local values = env and env.values or {}
            for i = #values, 1, -1 do
                if values[i].name == self.name then
                    binding = values[i].binding
                    break
                end
            end
            if binding == nil then
                error("surface_to_elab_stmt: unknown binding '" .. self.name .. "'")
            end
            binding = one_set_target_binding(binding)
            return pvm.once(Elab.ElabSet(binding, one_expr(self.value, env, binding.ty)))
        end,
        [Surf.SurfStore] = function(self, env)
            local ty = one_type(self.ty, env)
            return pvm.once(Elab.ElabStore(
                ty,
                one_expr(self.addr, env, Elab.ElabTPtr(ty)),
                one_expr(self.value, env, ty)
            ))
        end,
        [Surf.SurfIf] = function(self, env, path)
            local base = path_or_implicit("if.stmt", self, path)
            local cond = one_expr(self.cond, env, Elab.ElabTBool)
            local then_body, _ = lower_stmt_list(self.then_body, env, scoped_path(base, "then"))
            local else_body, _ = lower_stmt_list(self.else_body, env, scoped_path(base, "else"))
            return pvm.once(Elab.ElabIf(cond, then_body, else_body))
        end,
        [Surf.SurfSwitch] = function(self, env, path)
            local base = path_or_implicit("switch.stmt", self, path)
            local value = one_expr(self.value, env, nil)
            local value_ty = pvm.one(expr_api.expr_type(value))
            local arms = {}
            for i = 1, #self.arms do
                local arm = one_switch_stmt_arm(self.arms[i], env, scoped_path(base, "arm." .. i))
                local key_ty = pvm.one(expr_api.expr_type(arm.key))
                if key_ty ~= value_ty then
                    error("surface_to_elab_stmt: switch arm key must currently have the same elaborated type as the switch value")
                end
                arms[i] = arm
            end
            local default_body, _ = lower_stmt_list(self.default_body, env, scoped_path(base, "default"))
            return pvm.once(Elab.ElabSwitch(value, arms, default_body))
        end,
        [Surf.SurfReturnVoid] = function()
            return pvm.once(Elab.ElabReturnVoid)
        end,
        [Surf.SurfReturnValue] = function(self, env)
            return pvm.once(Elab.ElabReturnValue(one_expr(self.value, env, nil)))
        end,
        [Surf.SurfBreak] = function()
            return pvm.once(Elab.ElabBreak)
        end,
        [Surf.SurfContinue] = function()
            return pvm.once(Elab.ElabContinue)
        end,
        [Surf.SurfLoopStmtNode] = function(self, env, path)
            return pvm.once(Elab.ElabLoopStmtNode(one_loop_stmt(self.loop, env, path_or_implicit("loop.stmt", self, path))))
        end,
    })

    return {
        lower_type = lower_type,
        lower_expr = lower_expr,
        expr_type = expr_api.expr_type,
        lower_domain = lower_domain,
        lower_stmt = lower_stmt,
        lower_loop_stmt = lower_loop_stmt,
        lower_loop_expr = lower_loop_expr,
        stmt_env_effect = stmt_env_effect,
        apply_stmt_env_effect = apply_stmt_env_effect,
    }
end

return M
