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
    local base_lower_place = expr_api.lower_place
    local lower_expr
    local lower_domain

    local lower_stmt
    local lower_loop_stmt
    local lower_loop_expr
    local lower_loop_carry
    local lower_loop_update
    local lower_switch_stmt_arm
    local lower_switch_expr_arm
    local stmt_env_effect
    local apply_stmt_env_effect
    local combine_loop_expr_exit
    local lower_loop_expr_exit_stmt
    local lower_loop_expr_exit_expr
    local lower_loop_expr_exit_place

    local function one_type(node, env)
        return pvm.one(lower_type(node, env))
    end

    local function one_expr(node, env, expected_ty, allow_bare_break, break_value_ty)
        return pvm.one(lower_expr(node, env, expected_ty, allow_bare_break, break_value_ty))
    end

    local function one_domain(node, env)
        return pvm.one(lower_domain(node, env))
    end

    local function one_place(node, env)
        return pvm.one(base_lower_place(node, env))
    end

    local function one_stmt(node, env, path, allow_bare_break, break_value_ty)
        return pvm.one(lower_stmt(node, env, path, allow_bare_break, break_value_ty))
    end

    local function one_loop_stmt(node, env, path)
        return pvm.one(lower_loop_stmt(node, env, path))
    end

    local function one_loop_expr(node, env, path)
        return pvm.one(lower_loop_expr(node, env, path))
    end

    local function one_carry(node, env, loop_id, port_id)
        return pvm.one(lower_loop_carry(node, env, loop_id, port_id))
    end

    local function one_update(node, env, loop_bindings)
        return pvm.one(lower_loop_update(node, env, loop_bindings))
    end

    local function one_switch_stmt_arm(node, env, path, key_expected_ty, allow_bare_break, break_value_ty)
        return pvm.one(lower_switch_stmt_arm(node, env, path, key_expected_ty, allow_bare_break, break_value_ty))
    end

    local function one_switch_expr_arm(node, env, path, key_expected_ty, expected_ty, allow_bare_break, break_value_ty)
        return pvm.one(lower_switch_expr_arm(node, env, path, key_expected_ty, expected_ty, allow_bare_break, break_value_ty))
    end

    local function one_stmt_effect(node)
        return pvm.one(stmt_env_effect(node))
    end

    local function apply_effect(effect, env)
        return pvm.one(apply_stmt_env_effect(effect, env))
    end

    local function one_loop_expr_exit_stmt(node)
        return pvm.one(lower_loop_expr_exit_stmt(node))
    end

    local function one_loop_expr_exit_expr(node)
        return pvm.one(lower_loop_expr_exit_expr(node))
    end

    local function one_loop_expr_exit_place(node)
        return pvm.one(lower_loop_expr_exit_place(node))
    end

    local function combine_exit(lhs, rhs)
        return pvm.one(combine_loop_expr_exit(lhs, rhs))
    end

    local function loop_expr_exit_from_stmt_list(stmts)
        local exit = Elab.ElabLoopExprEndOnly
        for i = 1, #stmts do
            exit = combine_exit(exit, one_loop_expr_exit_stmt(stmts[i]))
        end
        return exit
    end

    local function loop_expr_exit_from_expr_list(exprs)
        local exit = Elab.ElabLoopExprEndOnly
        for i = 1, #exprs do
            exit = combine_exit(exit, one_loop_expr_exit_expr(exprs[i]))
        end
        return exit
    end

    local function scoped_path(base, suffix)
        if base == nil or base == "" then
            return suffix
        end
        return base .. "." .. suffix
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

    local function lower_stmt_list(stmts, env, base_path, allow_bare_break, break_value_ty)
        local out = {}
        local current_env = env
        for i = 1, #stmts do
            local stmt_path = scoped_path(base_path, "stmt." .. i)
            local stmt = with_path(stmt_path, function()
                return one_stmt(stmts[i], current_env, stmt_path, allow_bare_break, break_value_ty)
            end)
            out[i] = stmt
            current_env = apply_effect(one_stmt_effect(stmt), current_env)
        end
        return out, current_env
    end

    local function lower_carries(bindings, outer_env, loop_id, base_path)
        local out = {}
        local loop_env = outer_env
        local loop_bindings = {}
        for i = 1, #bindings do
            local port_id = scoped_path(base_path, "carry." .. i)
            local carry = with_path(port_id, function()
                return one_carry(bindings[i], outer_env, loop_id, port_id)
            end)
            local binding = Elab.ElabLoopCarry(loop_id, carry.port_id, carry.name, carry.ty)
            out[i] = carry
            loop_bindings[carry.name] = binding
            loop_env = extend_env_value(loop_env, Elab.ElabValueEntry(carry.name, binding))
        end
        return out, loop_env, loop_bindings
    end

    combine_loop_expr_exit = pvm.phase("surface_to_elab_loop_expr_exit_combine", {
        [Elab.ElabLoopExprEndOnly] = function(self, rhs)
            return pvm.once(rhs)
        end,
        [Elab.ElabLoopExprEndOrBreakValue] = function()
            return pvm.once(Elab.ElabLoopExprEndOrBreakValue)
        end,
    })

    lower_loop_expr_exit_place = pvm.phase("surface_to_elab_loop_expr_exit_place", {
        [Surf.SurfPlaceName] = function()
            return pvm.once(Elab.ElabLoopExprEndOnly)
        end,
        [Surf.SurfPlacePath] = function()
            return pvm.once(Elab.ElabLoopExprEndOnly)
        end,
        [Surf.SurfPlaceDeref] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.base))
        end,
        [Surf.SurfPlaceDot] = function(self)
            return pvm.once(one_loop_expr_exit_place(self.base))
        end,
        [Surf.SurfPlaceField] = function(self)
            return pvm.once(one_loop_expr_exit_place(self.base))
        end,
        [Surf.SurfPlaceIndex] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.base), one_loop_expr_exit_expr(self.index)))
        end,
    })

    lower_loop_expr_exit_expr = pvm.phase("surface_to_elab_loop_expr_exit_expr", {
        [Surf.SurfInt] = function() return pvm.once(Elab.ElabLoopExprEndOnly) end,
        [Surf.SurfFloat] = function() return pvm.once(Elab.ElabLoopExprEndOnly) end,
        [Surf.SurfBool] = function() return pvm.once(Elab.ElabLoopExprEndOnly) end,
        [Surf.SurfNil] = function() return pvm.once(Elab.ElabLoopExprEndOnly) end,
        [Surf.SurfNameRef] = function() return pvm.once(Elab.ElabLoopExprEndOnly) end,
        [Surf.SurfPathRef] = function() return pvm.once(Elab.ElabLoopExprEndOnly) end,
        [Surf.SurfExprDot] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.base))
        end,
        [Surf.SurfExprNeg] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.value))
        end,
        [Surf.SurfExprNot] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.value))
        end,
        [Surf.SurfExprBNot] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.value))
        end,
        [Surf.SurfExprRef] = function(self)
            return pvm.once(one_loop_expr_exit_place(self.place))
        end,
        [Surf.SurfExprDeref] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.value))
        end,
        [Surf.SurfExprAdd] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprSub] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprMul] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprDiv] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprRem] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprEq] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprNe] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprLt] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprLe] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprGt] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprGe] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprAnd] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprOr] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprBitAnd] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprBitOr] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprBitXor] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprShl] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprLShr] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprAShr] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.lhs), one_loop_expr_exit_expr(self.rhs)))
        end,
        [Surf.SurfExprCastTo] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.value))
        end,
        [Surf.SurfExprTruncTo] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.value))
        end,
        [Surf.SurfExprZExtTo] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.value))
        end,
        [Surf.SurfExprSExtTo] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.value))
        end,
        [Surf.SurfExprBitcastTo] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.value))
        end,
        [Surf.SurfExprSatCastTo] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.value))
        end,
        [Surf.SurfExprIntrinsicCall] = function(self)
            return pvm.once(loop_expr_exit_from_expr_list(self.args))
        end,
        [Surf.SurfCall] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.callee), loop_expr_exit_from_expr_list(self.args)))
        end,
        [Surf.SurfField] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.base))
        end,
        [Surf.SurfIndex] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_expr(self.base), one_loop_expr_exit_expr(self.index)))
        end,
        [Surf.SurfAgg] = function(self)
            local exit = Elab.ElabLoopExprEndOnly
            for i = 1, #self.fields do
                exit = combine_exit(exit, one_loop_expr_exit_expr(self.fields[i].value))
            end
            return pvm.once(exit)
        end,
        [Surf.SurfArrayLit] = function(self)
            return pvm.once(loop_expr_exit_from_expr_list(self.elems))
        end,
        [Surf.SurfIfExpr] = function(self)
            local exit = combine_exit(one_loop_expr_exit_expr(self.cond), one_loop_expr_exit_expr(self.then_expr))
            return pvm.once(combine_exit(exit, one_loop_expr_exit_expr(self.else_expr)))
        end,
        [Surf.SurfSelectExpr] = function(self)
            local exit = combine_exit(one_loop_expr_exit_expr(self.cond), one_loop_expr_exit_expr(self.then_expr))
            return pvm.once(combine_exit(exit, one_loop_expr_exit_expr(self.else_expr)))
        end,
        [Surf.SurfSwitchExpr] = function(self)
            local exit = one_loop_expr_exit_expr(self.value)
            for i = 1, #self.arms do
                exit = combine_exit(exit, one_loop_expr_exit_expr(self.arms[i].key))
                exit = combine_exit(exit, loop_expr_exit_from_stmt_list(self.arms[i].body))
                exit = combine_exit(exit, one_loop_expr_exit_expr(self.arms[i].result))
            end
            return pvm.once(combine_exit(exit, one_loop_expr_exit_expr(self.default_expr)))
        end,
        [Surf.SurfLoopExprNode] = function()
            return pvm.once(Elab.ElabLoopExprEndOnly)
        end,
        [Surf.SurfBlockExpr] = function(self)
            return pvm.once(combine_exit(loop_expr_exit_from_stmt_list(self.stmts), one_loop_expr_exit_expr(self.result)))
        end,
    })

    lower_loop_expr_exit_stmt = pvm.phase("surface_to_elab_loop_expr_exit_stmt", {
        [Surf.SurfLet] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.init))
        end,
        [Surf.SurfVar] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.init))
        end,
        [Surf.SurfSet] = function(self)
            return pvm.once(combine_exit(one_loop_expr_exit_place(self.place), one_loop_expr_exit_expr(self.value)))
        end,
        [Surf.SurfExprStmt] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.expr))
        end,
        [Surf.SurfIf] = function(self)
            local exit = combine_exit(one_loop_expr_exit_expr(self.cond), loop_expr_exit_from_stmt_list(self.then_body))
            return pvm.once(combine_exit(exit, loop_expr_exit_from_stmt_list(self.else_body)))
        end,
        [Surf.SurfSwitch] = function(self)
            local exit = one_loop_expr_exit_expr(self.value)
            for i = 1, #self.arms do
                exit = combine_exit(exit, one_loop_expr_exit_expr(self.arms[i].key))
                exit = combine_exit(exit, loop_expr_exit_from_stmt_list(self.arms[i].body))
            end
            return pvm.once(combine_exit(exit, loop_expr_exit_from_stmt_list(self.default_body)))
        end,
        [Surf.SurfReturnVoid] = function()
            return pvm.once(Elab.ElabLoopExprEndOnly)
        end,
        [Surf.SurfReturnValue] = function(self)
            return pvm.once(one_loop_expr_exit_expr(self.value))
        end,
        [Surf.SurfBreak] = function()
            return pvm.once(Elab.ElabLoopExprEndOnly)
        end,
        [Surf.SurfBreakValue] = function()
            return pvm.once(Elab.ElabLoopExprEndOrBreakValue)
        end,
        [Surf.SurfContinue] = function()
            return pvm.once(Elab.ElabLoopExprEndOnly)
        end,
        [Surf.SurfLoopStmtNode] = function()
            return pvm.once(Elab.ElabLoopExprEndOnly)
        end,
    })

    stmt_env_effect = pvm.phase("elab_stmt_env_effect", {
        [Elab.ElabLet] = function(self)
            return pvm.once(Elab.ElabAddBinding(Elab.ElabValueEntry(self.name, Elab.ElabLocalValue(self.id, self.name, self.ty))))
        end,
        [Elab.ElabVar] = function(self)
            return pvm.once(Elab.ElabAddBinding(Elab.ElabValueEntry(self.name, Elab.ElabLocalCell(self.id, self.name, self.ty))))
        end,
        [Elab.ElabSet] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabExprStmt] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabIf] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabSwitch] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabReturnVoid] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabReturnValue] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabBreak] = function() return pvm.once(Elab.ElabNoBinding) end,
        [Elab.ElabBreakValue] = function() return pvm.once(Elab.ElabNoBinding) end,
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

    lower_loop_carry = pvm.phase("surface_to_elab_loop_carry", {
        [Surf.SurfLoopCarryInit] = function(self, env, loop_id, port_id)
            local ty = one_type(self.ty, env)
            local init = one_expr(self.init, env, ty)
            return pvm.once(Elab.ElabLoopCarryPort(port_id, self.name, ty, init))
        end,
    })

    lower_loop_update = pvm.phase("surface_to_elab_loop_update", {
        [Surf.SurfLoopNextAssign] = function(self, env, loop_bindings)
            local binding = loop_bindings[self.name]
            if binding == nil then
                error("surface_to_elab_loop: next assignment for unknown loop binding '" .. self.name .. "'")
            end
            return pvm.once(Elab.ElabLoopUpdate(binding.port_id, one_expr(self.value, env, binding.ty)))
        end,
    })

    lower_switch_stmt_arm = pvm.phase("surface_to_elab_switch_stmt_arm", {
        [Surf.SurfSwitchStmtArm] = function(self, env, path, key_expected_ty, allow_bare_break, break_value_ty)
            local key = with_path(path, function()
                return one_expr(self.key, env, key_expected_ty, allow_bare_break, break_value_ty)
            end)
            local body, _ = lower_stmt_list(self.body, env, scoped_path(path, "body"), allow_bare_break, break_value_ty)
            return pvm.once(Elab.ElabSwitchStmtArm(key, body))
        end,
    })

    lower_switch_expr_arm = pvm.phase("surface_to_elab_switch_expr_arm", {
        [Surf.SurfSwitchExprArm] = function(self, env, path, key_expected_ty, expected_ty, allow_bare_break, break_value_ty)
            local key = with_path(path, function()
                return one_expr(self.key, env, key_expected_ty, allow_bare_break, break_value_ty)
            end)
            local body, body_env = lower_stmt_list(self.body, env, scoped_path(path, "body"), allow_bare_break, break_value_ty)
            local result = with_path(scoped_path(path, "result"), function()
                return one_expr(self.result, body_env, expected_ty, allow_bare_break, break_value_ty)
            end)
            return pvm.once(Elab.ElabSwitchExprArm(key, body, result))
        end,
    })

    lower_loop_stmt = pvm.phase("surface_to_elab_loop_stmt", {
        [Surf.SurfLoopWhileStmt] = function(self, env, path)
            local base = path_or_implicit("loop.while.stmt", self, path)
            local loop_id = base
            local carries, loop_env, loop_bindings = lower_carries(self.carries, env, loop_id, scoped_path(base, "carries"))
            local cond = with_path(scoped_path(base, "cond"), function()
                return one_expr(self.cond, loop_env, Elab.ElabTBool, true, nil)
            end)
            local body, body_env = lower_stmt_list(self.body, loop_env, scoped_path(base, "body"), true, nil)
            local next_out = {}
            for i = 1, #self.next do
                local next_path = scoped_path(base, "next." .. i)
                next_out[i] = with_path(next_path, function()
                    return one_update(self.next[i], body_env, loop_bindings)
                end)
            end
            return pvm.once(Elab.ElabLoopWhileStmt(loop_id, carries, cond, body, next_out))
        end,

        [Surf.SurfLoopOverStmt] = function(self, env, path)
            local base = path_or_implicit("loop.over.stmt", self, path)
            local loop_id = base
            local carries, loop_env, loop_bindings = lower_carries(self.carries, env, loop_id, scoped_path(base, "carries"))
            local domain = with_path(scoped_path(base, "domain"), function()
                return one_domain(self.domain, loop_env)
            end)
            local index_port = Elab.ElabLoopIndexPort(self.index_name, Elab.ElabTIndex)
            local index_binding = Elab.ElabLoopIndex(loop_id, self.index_name, Elab.ElabTIndex)
            loop_env = extend_env_value(loop_env, Elab.ElabValueEntry(self.index_name, index_binding))
            local body, body_env = lower_stmt_list(self.body, loop_env, scoped_path(base, "body"), true, nil)
            local next_out = {}
            for i = 1, #self.next do
                local next_path = scoped_path(base, "next." .. i)
                next_out[i] = with_path(next_path, function()
                    return one_update(self.next[i], body_env, loop_bindings)
                end)
            end
            return pvm.once(Elab.ElabLoopOverStmt(loop_id, index_port, domain, carries, body, next_out))
        end,
    })

    lower_loop_expr = pvm.phase("surface_to_elab_loop_expr", {
        [Surf.SurfLoopWhileExpr] = function(self, env, path)
            local base = path_or_implicit("loop.while.expr", self, path)
            local loop_id = base
            local carries, loop_env, loop_bindings = lower_carries(self.carries, env, loop_id, scoped_path(base, "carries"))
            local result = with_path(scoped_path(base, "result"), function()
                return one_expr(self.result, loop_env, nil, false, nil)
            end)
            local result_ty = pvm.one(expr_api.expr_type(result))
            local cond = with_path(scoped_path(base, "cond"), function()
                return one_expr(self.cond, loop_env, Elab.ElabTBool, false, nil)
            end)
            local body, body_env = lower_stmt_list(self.body, loop_env, scoped_path(base, "body"), false, result_ty)
            local exit = loop_expr_exit_from_stmt_list(self.body)
            local next_out = {}
            for i = 1, #self.next do
                local next_path = scoped_path(base, "next." .. i)
                next_out[i] = with_path(next_path, function()
                    return one_update(self.next[i], body_env, loop_bindings)
                end)
            end
            return pvm.once(Elab.ElabLoopExprNode(
                Elab.ElabLoopWhileExpr(loop_id, carries, cond, body, next_out, exit, result),
                result_ty
            ))
        end,

        [Surf.SurfLoopOverExpr] = function(self, env, path)
            local base = path_or_implicit("loop.over.expr", self, path)
            local loop_id = base
            local carries, loop_env, loop_bindings = lower_carries(self.carries, env, loop_id, scoped_path(base, "carries"))
            local domain = with_path(scoped_path(base, "domain"), function()
                return one_domain(self.domain, loop_env)
            end)
            local index_port = Elab.ElabLoopIndexPort(self.index_name, Elab.ElabTIndex)
            local index_binding = Elab.ElabLoopIndex(loop_id, self.index_name, Elab.ElabTIndex)
            loop_env = extend_env_value(loop_env, Elab.ElabValueEntry(self.index_name, index_binding))
            local result = with_path(scoped_path(base, "result"), function()
                return one_expr(self.result, loop_env, nil, false, nil)
            end)
            local result_ty = pvm.one(expr_api.expr_type(result))
            local body, body_env = lower_stmt_list(self.body, loop_env, scoped_path(base, "body"), false, result_ty)
            local exit = loop_expr_exit_from_stmt_list(self.body)
            local next_out = {}
            for i = 1, #self.next do
                local next_path = scoped_path(base, "next." .. i)
                next_out[i] = with_path(next_path, function()
                    return one_update(self.next[i], body_env, loop_bindings)
                end)
            end
            return pvm.once(Elab.ElabLoopExprNode(
                Elab.ElabLoopOverExpr(loop_id, index_port, domain, carries, body, next_out, exit, result),
                result_ty
            ))
        end,

        [Surf.SurfLoopWhileExprTyped] = function(self, env, path)
            local base = path_or_implicit("loop.while.expr.typed", self, path)
            local loop_id = base
            local carries, loop_env, loop_bindings = lower_carries(self.carries, env, loop_id, scoped_path(base, "carries"))
            local declared_ty = one_type(self.result_ty, env)
            local result = with_path(scoped_path(base, "result"), function()
                return one_expr(self.result, loop_env, declared_ty, false, nil)
            end)
            local result_ty = pvm.one(expr_api.expr_type(result))
            if result_ty ~= declared_ty then
                error("surface_to_elab_loop: typed while expr result must currently have the declared elaborated type")
            end
            local cond = with_path(scoped_path(base, "cond"), function()
                return one_expr(self.cond, loop_env, Elab.ElabTBool, false, nil)
            end)
            local body, body_env = lower_stmt_list(self.body, loop_env, scoped_path(base, "body"), false, declared_ty)
            local exit = loop_expr_exit_from_stmt_list(self.body)
            local next_out = {}
            for i = 1, #self.next do
                local next_path = scoped_path(base, "next." .. i)
                next_out[i] = with_path(next_path, function()
                    return one_update(self.next[i], body_env, loop_bindings)
                end)
            end
            return pvm.once(Elab.ElabLoopExprNode(
                Elab.ElabLoopWhileExpr(loop_id, carries, cond, body, next_out, exit, result),
                declared_ty
            ))
        end,

        [Surf.SurfLoopOverExprTyped] = function(self, env, path)
            local base = path_or_implicit("loop.over.expr.typed", self, path)
            local loop_id = base
            local carries, loop_env, loop_bindings = lower_carries(self.carries, env, loop_id, scoped_path(base, "carries"))
            local domain = with_path(scoped_path(base, "domain"), function()
                return one_domain(self.domain, loop_env)
            end)
            local index_port = Elab.ElabLoopIndexPort(self.index_name, Elab.ElabTIndex)
            local index_binding = Elab.ElabLoopIndex(loop_id, self.index_name, Elab.ElabTIndex)
            loop_env = extend_env_value(loop_env, Elab.ElabValueEntry(self.index_name, index_binding))
            local declared_ty = one_type(self.result_ty, env)
            local result = with_path(scoped_path(base, "result"), function()
                return one_expr(self.result, loop_env, declared_ty, false, nil)
            end)
            local result_ty = pvm.one(expr_api.expr_type(result))
            if result_ty ~= declared_ty then
                error("surface_to_elab_loop: typed over expr result must currently have the declared elaborated type")
            end
            local body, body_env = lower_stmt_list(self.body, loop_env, scoped_path(base, "body"), false, declared_ty)
            local exit = loop_expr_exit_from_stmt_list(self.body)
            local next_out = {}
            for i = 1, #self.next do
                local next_path = scoped_path(base, "next." .. i)
                next_out[i] = with_path(next_path, function()
                    return one_update(self.next[i], body_env, loop_bindings)
                end)
            end
            return pvm.once(Elab.ElabLoopExprNode(
                Elab.ElabLoopOverExpr(loop_id, index_port, domain, carries, body, next_out, exit, result),
                declared_ty
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
        [Surf.SurfExprDot] = delegate_base_expr,
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
        [Surf.SurfExprIntrinsicCall] = delegate_base_expr,
        [Surf.SurfSelectExpr] = delegate_base_expr,
        [Surf.SurfIfExpr] = function(self, env, expected_ty, allow_bare_break, break_value_ty)
            local cond = one_expr(self.cond, env, Elab.ElabTBool, allow_bare_break, break_value_ty)
            local then_expr = one_expr(self.then_expr, env, expected_ty, allow_bare_break, break_value_ty)
            local then_ty = pvm.one(expr_api.expr_type(then_expr))
            local else_expr = one_expr(self.else_expr, env, then_ty, allow_bare_break, break_value_ty)
            local else_ty = pvm.one(expr_api.expr_type(else_expr))
            if then_ty ~= else_ty then
                error("surface_to_elab_expr: if expr branches must currently have identical elaborated types")
            end
            return pvm.once(Elab.ElabIfExpr(cond, then_expr, else_expr, then_ty))
        end,
        [Surf.SurfSwitchExpr] = function(self, env, expected_ty, allow_bare_break, break_value_ty)
            local base = implicit_path("switch.expr", self)
            local value = one_expr(self.value, env, nil, allow_bare_break, break_value_ty)
            local value_ty = pvm.one(expr_api.expr_type(value))
            local default_expr = one_expr(self.default_expr, env, expected_ty, allow_bare_break, break_value_ty)
            local result_ty = pvm.one(expr_api.expr_type(default_expr))
            local arms = {}
            for i = 1, #self.arms do
                local arm = one_switch_expr_arm(self.arms[i], env, scoped_path(base, "arm." .. i), value_ty, result_ty, allow_bare_break, break_value_ty)
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
        [Surf.SurfBlockExpr] = function(self, env, expected_ty, allow_bare_break, break_value_ty)
            local base = implicit_path("block.expr", self)
            local stmts, block_env = lower_stmt_list(self.stmts, env, scoped_path(base, "stmts"), allow_bare_break, break_value_ty)
            local result = one_expr(self.result, block_env, expected_ty, allow_bare_break, break_value_ty)
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
        [Surf.SurfExprStmt] = function(self, env, path, allow_bare_break, break_value_ty)
            return pvm.once(Elab.ElabExprStmt(one_expr(self.expr, env, nil, allow_bare_break, break_value_ty)))
        end,
        [Surf.SurfLet] = function(self, env, path, allow_bare_break, break_value_ty)
            local ty = one_type(self.ty, env)
            local id = path_or_implicit("let." .. self.name, self, path)
            return pvm.once(Elab.ElabLet(id, self.name, ty, one_expr(self.init, env, ty, allow_bare_break, break_value_ty)))
        end,
        [Surf.SurfVar] = function(self, env, path, allow_bare_break, break_value_ty)
            local ty = one_type(self.ty, env)
            local id = path_or_implicit("var." .. self.name, self, path)
            return pvm.once(Elab.ElabVar(id, self.name, ty, one_expr(self.init, env, ty, allow_bare_break, break_value_ty)))
        end,
        [Surf.SurfSet] = function(self, env, path, allow_bare_break, break_value_ty)
            local place = one_place(self.place, env)
            return pvm.once(Elab.ElabSet(place, one_expr(self.value, env, pvm.one(expr_api.place_type(place)), allow_bare_break, break_value_ty)))
        end,
        [Surf.SurfIf] = function(self, env, path, allow_bare_break, break_value_ty)
            local base = path_or_implicit("if.stmt", self, path)
            local cond = one_expr(self.cond, env, Elab.ElabTBool, allow_bare_break, break_value_ty)
            local then_body, _ = lower_stmt_list(self.then_body, env, scoped_path(base, "then"), allow_bare_break, break_value_ty)
            local else_body, _ = lower_stmt_list(self.else_body, env, scoped_path(base, "else"), allow_bare_break, break_value_ty)
            return pvm.once(Elab.ElabIf(cond, then_body, else_body))
        end,
        [Surf.SurfSwitch] = function(self, env, path, allow_bare_break, break_value_ty)
            local base = path_or_implicit("switch.stmt", self, path)
            local value = one_expr(self.value, env, nil, allow_bare_break, break_value_ty)
            local value_ty = pvm.one(expr_api.expr_type(value))
            local arms = {}
            for i = 1, #self.arms do
                local arm = one_switch_stmt_arm(self.arms[i], env, scoped_path(base, "arm." .. i), value_ty, allow_bare_break, break_value_ty)
                local key_ty = pvm.one(expr_api.expr_type(arm.key))
                if key_ty ~= value_ty then
                    error("surface_to_elab_stmt: switch arm key must currently have the same elaborated type as the switch value")
                end
                arms[i] = arm
            end
            local default_body, _ = lower_stmt_list(self.default_body, env, scoped_path(base, "default"), allow_bare_break, break_value_ty)
            return pvm.once(Elab.ElabSwitch(value, arms, default_body))
        end,
        [Surf.SurfReturnVoid] = function()
            return pvm.once(Elab.ElabReturnVoid)
        end,
        [Surf.SurfReturnValue] = function(self, env, path, allow_bare_break, break_value_ty)
            return pvm.once(Elab.ElabReturnValue(one_expr(self.value, env, nil, allow_bare_break, break_value_ty)))
        end,
        [Surf.SurfBreak] = function(self, env, path, allow_bare_break, break_value_ty)
            if break_value_ty ~= nil then
                error("surface_to_elab_stmt: bare break is not valid inside an expression loop body")
            end
            if not allow_bare_break then
                error("surface_to_elab_stmt: bare break is only valid inside a statement loop body")
            end
            return pvm.once(Elab.ElabBreak)
        end,
        [Surf.SurfBreakValue] = function(self, env, path, allow_bare_break, break_value_ty)
            if break_value_ty == nil then
                error("surface_to_elab_stmt: valued break is only valid inside an expression loop body")
            end
            local value = one_expr(self.value, env, break_value_ty, false, break_value_ty)
            local value_ty = pvm.one(expr_api.expr_type(value))
            if value_ty ~= break_value_ty then
                error("surface_to_elab_stmt: valued break must currently have the loop expression result type")
            end
            return pvm.once(Elab.ElabBreakValue(value))
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
        lower_place = base_lower_place,
        expr_type = expr_api.expr_type,
        place_type = expr_api.place_type,
        lower_domain = lower_domain,
        lower_stmt = lower_stmt,
        lower_loop_stmt = lower_loop_stmt,
        lower_loop_expr = lower_loop_expr,
        stmt_env_effect = stmt_env_effect,
        apply_stmt_env_effect = apply_stmt_env_effect,
    }
end

return M
