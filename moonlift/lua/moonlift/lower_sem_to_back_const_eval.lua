package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local ffi = require("ffi")
ffi.cdef[[
int snprintf(char *str, size_t size, const char *format, ...);
long long strtoll(const char *nptr, char **endptr, int base);
unsigned long long strtoull(const char *nptr, char **endptr, int base);
]]

local M = {}

function M.Define(T, aux)
    local Sem = T.MoonliftSem
    local sem_const_eval
    local sem_const_stmt_eval
    local sem_type_is_integral_scalar
    local sem_type_is_fp_scalar
    local sem_type_is_signed_integral
    local sem_type_is_boolean
    local function one_const_eval(node, const_env, local_env, visiting)
        return pvm.one(sem_const_eval(node, const_env, local_env, visiting))
    end

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

    local function one_sem_type_is_integral_scalar(ty)
        return pvm.one(sem_type_is_integral_scalar(ty))
    end

    local function one_sem_type_is_fp_scalar(ty)
        return pvm.one(sem_type_is_fp_scalar(ty))
    end

    local function one_sem_type_is_signed_integral(ty)
        return pvm.one(sem_type_is_signed_integral(ty))
    end

    local function one_sem_type_is_boolean(ty)
        return pvm.one(sem_type_is_boolean(ty))
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
        float_bit_width = {
            [Sem.SemTF32] = 32,
            [Sem.SemTF64] = 64,
        },
        float_raw_precision = {
            [Sem.SemTF32] = 9,
            [Sem.SemTF64] = 17,
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

    sem_type_is_integral_scalar = pvm.phase("moonlift_const_eval_sem_type_is_integral_scalar", {
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
        [Sem.SemTIndex] = function() return pvm.once(true) end,
        [Sem.SemTPtr] = function() return pvm.once(false) end,
        [Sem.SemTPtrTo] = function() return pvm.once(false) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTView] = function() return pvm.once(false) end,
        [Sem.SemTFunc] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    sem_type_is_fp_scalar = pvm.phase("moonlift_const_eval_sem_type_is_fp_scalar", {
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
        [Sem.SemTIndex] = function() return pvm.once(false) end,
        [Sem.SemTPtr] = function() return pvm.once(false) end,
        [Sem.SemTPtrTo] = function() return pvm.once(false) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTView] = function() return pvm.once(false) end,
        [Sem.SemTFunc] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    sem_type_is_signed_integral = pvm.phase("moonlift_const_eval_sem_type_is_signed_integral", {
        [Sem.SemTVoid] = function() return pvm.once(false) end,
        [Sem.SemTBool] = function() return pvm.once(false) end,
        [Sem.SemTI8] = function() return pvm.once(true) end,
        [Sem.SemTI16] = function() return pvm.once(true) end,
        [Sem.SemTI32] = function() return pvm.once(true) end,
        [Sem.SemTI64] = function() return pvm.once(true) end,
        [Sem.SemTU8] = function() return pvm.once(false) end,
        [Sem.SemTU16] = function() return pvm.once(false) end,
        [Sem.SemTU32] = function() return pvm.once(false) end,
        [Sem.SemTU64] = function() return pvm.once(false) end,
        [Sem.SemTF32] = function() return pvm.once(false) end,
        [Sem.SemTF64] = function() return pvm.once(false) end,
        [Sem.SemTIndex] = function() return pvm.once(false) end,
        [Sem.SemTPtr] = function() return pvm.once(false) end,
        [Sem.SemTPtrTo] = function() return pvm.once(false) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTView] = function() return pvm.once(false) end,
        [Sem.SemTFunc] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    sem_type_is_boolean = pvm.phase("moonlift_const_eval_sem_type_is_boolean", {
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
        [Sem.SemTIndex] = function() return pvm.once(false) end,
        [Sem.SemTPtr] = function() return pvm.once(false) end,
        [Sem.SemTPtrTo] = function() return pvm.once(false) end,
        [Sem.SemTArray] = function() return pvm.once(false) end,
        [Sem.SemTSlice] = function() return pvm.once(false) end,
        [Sem.SemTView] = function() return pvm.once(false) end,
        [Sem.SemTFunc] = function() return pvm.once(false) end,
        [Sem.SemTNamed] = function() return pvm.once(false) end,
    })

    const_ops.type_is_bool = function(ty)
        return one_sem_type_is_boolean(ty)
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
        if one_sem_type_is_integral_scalar(ty) then return const_ops.int_bit_width_of(ty) end
        if one_sem_type_is_fp_scalar(ty) then return const_ops.float_bit_width[ty] end
        return nil
    end

    const_ops.ensure_local_env = function(local_env)
        if local_env ~= nil then
            return local_env
        end
        return Sem.SemConstLocalEnv({})
    end

    const_ops.same_local_binding = function(lhs, rhs)
        if lhs == nil or rhs == nil then
            return false
        end
        return pvm.one(aux.binding_key(lhs)) == pvm.one(aux.binding_key(rhs))
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
        return Sem.SemBindLocalValue(stmt.id, stmt.name, stmt.ty)
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
        if one_sem_type_is_integral_scalar(lhs_ty) then
            return parse_int_raw(lhs_ty, lhs.raw) == parse_int_raw(rhs_ty, rhs.raw)
        end
        if one_sem_type_is_fp_scalar(lhs_ty) then
            return tonumber(lhs.raw) == tonumber(rhs.raw)
        end
        if lhs.raw == nil and rhs.raw == nil and lhs.value == nil and rhs.value == nil and lhs.fields == nil and rhs.fields == nil and lhs.elems == nil and rhs.elems == nil then
            return true
        end
        error("sem_const_eval: " .. context .. " requires scalar comparable constants")
    end

    aux.const_stmt_result_is_falls_through = pvm.phase("sem_const_stmt_result_is_falls_through", {
        [Sem.SemConstStmtFallsThrough] = function() return pvm.once(true) end,
        [Sem.SemConstStmtReturnVoid] = function() return pvm.once(false) end,
        [Sem.SemConstStmtReturnValue] = function() return pvm.once(false) end,
        [Sem.SemConstStmtBreak] = function() return pvm.once(false) end,
        [Sem.SemConstStmtBreakValue] = function() return pvm.once(false) end,
        [Sem.SemConstStmtContinue] = function() return pvm.once(false) end,
    })

    aux.const_stmt_result_is_continue_like = pvm.phase("sem_const_stmt_result_is_continue_like", {
        [Sem.SemConstStmtFallsThrough] = function() return pvm.once(true) end,
        [Sem.SemConstStmtContinue] = function() return pvm.once(true) end,
        [Sem.SemConstStmtReturnVoid] = function() return pvm.once(false) end,
        [Sem.SemConstStmtReturnValue] = function() return pvm.once(false) end,
        [Sem.SemConstStmtBreak] = function() return pvm.once(false) end,
        [Sem.SemConstStmtBreakValue] = function() return pvm.once(false) end,
    })

    aux.const_stmt_result_is_break = pvm.phase("sem_const_stmt_result_is_break", {
        [Sem.SemConstStmtBreak] = function() return pvm.once(true) end,
        [Sem.SemConstStmtFallsThrough] = function() return pvm.once(false) end,
        [Sem.SemConstStmtContinue] = function() return pvm.once(false) end,
        [Sem.SemConstStmtReturnVoid] = function() return pvm.once(false) end,
        [Sem.SemConstStmtReturnValue] = function() return pvm.once(false) end,
        [Sem.SemConstStmtBreakValue] = function() return pvm.once(false) end,
    })

    aux.const_stmt_result_is_break_value = pvm.phase("sem_const_stmt_result_is_break_value", {
        [Sem.SemConstStmtBreakValue] = function() return pvm.once(true) end,
        [Sem.SemConstStmtFallsThrough] = function() return pvm.once(false) end,
        [Sem.SemConstStmtContinue] = function() return pvm.once(false) end,
        [Sem.SemConstStmtReturnVoid] = function() return pvm.once(false) end,
        [Sem.SemConstStmtReturnValue] = function() return pvm.once(false) end,
        [Sem.SemConstStmtBreak] = function() return pvm.once(false) end,
    })

    aux.const_stmt_result_fallthrough_env = pvm.phase("sem_const_stmt_result_fallthrough_env", {
        [Sem.SemConstStmtFallsThrough] = function(self)
            return pvm.once(self.local_env)
        end,
        [Sem.SemConstStmtReturnVoid] = function(self, context)
            error("sem_const_eval: " .. context .. " cannot return from constant data")
        end,
        [Sem.SemConstStmtReturnValue] = function(self, context)
            error("sem_const_eval: " .. context .. " cannot return from constant data")
        end,
        [Sem.SemConstStmtBreak] = function(self, context)
            error("sem_const_eval: " .. context .. " cannot break from constant data")
        end,
        [Sem.SemConstStmtBreakValue] = function(self, context)
            error("sem_const_eval: " .. context .. " cannot break from constant data")
        end,
        [Sem.SemConstStmtContinue] = function(self, context)
            error("sem_const_eval: " .. context .. " cannot continue from constant data")
        end,
    })

    const_ops.stmt_fallthrough_env = function(result, context)
        return pvm.one(aux.const_stmt_result_fallthrough_env(result, context))
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

    aux.const_stmt_result_project_bindings = pvm.phase("sem_const_stmt_result_project_bindings", {
        [Sem.SemConstStmtFallsThrough] = function(self, bindings)
            return pvm.once(Sem.SemConstStmtFallsThrough(const_ops.project_env_to_bindings(self.local_env, bindings)))
        end,
        [Sem.SemConstStmtReturnVoid] = function(self, bindings)
            return pvm.once(Sem.SemConstStmtReturnVoid(const_ops.project_env_to_bindings(self.local_env, bindings)))
        end,
        [Sem.SemConstStmtReturnValue] = function(self, bindings)
            return pvm.once(Sem.SemConstStmtReturnValue(const_ops.project_env_to_bindings(self.local_env, bindings), self.value))
        end,
        [Sem.SemConstStmtBreak] = function(self, bindings)
            return pvm.once(Sem.SemConstStmtBreak(const_ops.project_env_to_bindings(self.local_env, bindings)))
        end,
        [Sem.SemConstStmtBreakValue] = function(self, bindings)
            return pvm.once(Sem.SemConstStmtBreakValue(const_ops.project_env_to_bindings(self.local_env, bindings), self.value))
        end,
        [Sem.SemConstStmtContinue] = function(self, bindings)
            return pvm.once(Sem.SemConstStmtContinue(const_ops.project_env_to_bindings(self.local_env, bindings)))
        end,
    })

    const_ops.project_stmt_result_to_bindings = function(result, bindings)
        return pvm.one(aux.const_stmt_result_project_bindings(result, bindings))
    end

    const_ops.loop_binding_as_binding = function(loop_binding, loop_id)
        return Sem.SemBindLoopCarry(loop_id, loop_binding.port_id, loop_binding.name, loop_binding.ty)
    end

    const_ops.loop_index_as_binding = function(loop)
        return Sem.SemBindLoopIndex(loop.loop_id, loop.index_port.name, loop.index_port.ty)
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

    const_ops.eval_loop_next_values = function(carries, nexts, const_env, local_env, visiting)
        local values = {}
        local seen = {}
        for i = 1, #carries do
            local carry = carries[i]
            local update = nil
            for j = 1, #nexts do
                if nexts[j].port_id == carry.port_id then
                    if update ~= nil then
                        error("sem_const_eval: duplicate loop update for port '" .. carry.port_id .. "'")
                    end
                    update = nexts[j]
                    seen[j] = true
                end
            end
            if update == nil then
                error("sem_const_eval: missing loop update for port '" .. carry.port_id .. "'")
            end
            values[i] = one_const_eval(update.value, const_env, local_env, visiting)
            if const_value_ty(values[i]) ~= carry.ty then
                error("sem_const_eval: loop next constant type mismatch")
            end
        end
        for j = 1, #nexts do
            if not seen[j] then
                error("sem_const_eval: loop update targets unknown port '" .. nexts[j].port_id .. "'")
            end
        end
        return values
    end

    const_ops.loop_iteration_limit = 100000

    const_ops.eval_stmt_list = function(stmts, const_env, local_env, visiting)
        local env = const_ops.ensure_local_env(local_env)
        for i = 1, #stmts do
            local result = pvm.one(sem_const_stmt_eval(stmts[i], const_env, env, visiting))
            if not pvm.one(aux.const_stmt_result_is_falls_through(result)) then
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
        if one_sem_type_is_signed_integral(ty) then
            return ffi.cast(ctype, ffi.C.strtoll(raw, nil, 10))
        end
        return ffi.cast(ctype, ffi.C.strtoull(raw, nil, 10))
    end

    local function normalize_int(ty, value)
        return ffi.cast(int_ctype(ty), value)
    end

    local function int_raw(ty, value)
        local norm = normalize_int(ty, value)
        if one_sem_type_is_signed_integral(ty) then
            return format_signed_i64(ffi.cast("int64_t", norm))
        end
        return format_unsigned_u64(ffi.cast("uint64_t", norm))
    end

    local function float_raw(ty, value)
        if const_ops.float_raw_precision[ty] == 9 then
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
        if one_sem_type_is_signed_integral(ty) then
            return tonumber(ffi.cast("int64_t", value))
        end
        return tonumber(ffi.cast("uint64_t", ffi.cast(const_ops.unsigned_int_ctype_of(ty), value)))
    end

    const_ops.const_zero_value = function(ty)
        if const_ops.type_is_bool(ty) then
            return Sem.SemConstBool(false)
        end
        if one_sem_type_is_fp_scalar(ty) then
            return const_float_value(ty, 0)
        end
        if one_sem_type_is_integral_scalar(ty) then
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
        if one_sem_type_is_integral_scalar(dest_ty) then
            if const_ops.type_is_bool(src_ty) then
                return const_int_value(dest_ty, value.value and 1 or 0)
            end
            if one_sem_type_is_integral_scalar(src_ty) then
                return const_int_value(dest_ty, parse_int_raw(src_ty, value.raw))
            end
            if one_sem_type_is_fp_scalar(src_ty) then
                return const_int_value(dest_ty, ffi.cast(int_ctype(dest_ty), tonumber(value.raw)))
            end
        elseif one_sem_type_is_fp_scalar(dest_ty) then
            if const_ops.type_is_bool(src_ty) then
                return const_float_value(dest_ty, value.value and 1 or 0)
            end
            if one_sem_type_is_integral_scalar(src_ty) then
                return const_float_value(dest_ty, const_ops.integer_to_lua_number(src_ty, parse_int_raw(src_ty, value.raw)))
            end
            if one_sem_type_is_fp_scalar(src_ty) then
                return const_float_value(dest_ty, tonumber(value.raw))
            end
        elseif const_ops.type_is_bool(dest_ty) then
            if const_ops.type_is_bool(src_ty) then
                return Sem.SemConstBool(value.value)
            end
            if one_sem_type_is_integral_scalar(src_ty) then
                return Sem.SemConstBool(parse_int_raw(src_ty, value.raw) ~= 0)
            end
            if one_sem_type_is_fp_scalar(src_ty) then
                return Sem.SemConstBool(tonumber(value.raw) ~= 0)
            end
        end
        error("sem_const_eval: " .. context .. " is not supported from '" .. tostring(src_ty) .. "' to '" .. tostring(dest_ty) .. "'")
    end

    const_ops.zext_const_value = function(dest_ty, value)
        local src_ty, parsed = expect_const_intlike(value, "zero-extend")
        if not one_sem_type_is_integral_scalar(dest_ty) then
            error("sem_const_eval: zero-extend requires an integer-like destination type")
        end
        return const_int_value(dest_ty, ffi.cast(int_ctype(dest_ty), ffi.cast(const_ops.unsigned_int_ctype_of(src_ty), parsed)))
    end

    const_ops.sext_const_value = function(dest_ty, value)
        local src_ty, parsed = expect_const_intlike(value, "sign-extend")
        if not one_sem_type_is_integral_scalar(dest_ty) then
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
        if one_sem_type_is_integral_scalar(src_ty) then
            src_storage_ctype = const_ops.unsigned_int_ctype_of(src_ty)
            src_storage_value = ffi.cast(src_storage_ctype, parse_int_raw(src_ty, value.raw))
        elseif one_sem_type_is_fp_scalar(src_ty) then
            src_storage_ctype = const_ops.float_ctype_of(src_ty)
            src_storage_value = tonumber(value.raw)
        else
            error("sem_const_eval: bitcast source must be an integer-like or float constant")
        end
        local buf = ffi.new(src_storage_ctype .. "[1]", src_storage_value)
        if one_sem_type_is_integral_scalar(dest_ty) then
            local raw_value = ffi.cast(const_ops.unsigned_int_ctype_of(dest_ty) .. "*", buf)[0]
            return const_ops.const_int_value_from_unsigned(dest_ty, raw_value)
        end
        if one_sem_type_is_fp_scalar(dest_ty) then
            local raw_value = ffi.cast(const_ops.float_ctype_of(dest_ty) .. "*", buf)[0]
            return const_float_value(dest_ty, raw_value)
        end
        error("sem_const_eval: bitcast destination must be an integer-like or float type")
    end

    const_ops.sat_cast_const_value = function(dest_ty, value)
        local src_ty = const_value_ty(value)
        if one_sem_type_is_fp_scalar(dest_ty) or const_ops.type_is_bool(dest_ty) then
            return const_ops.scalar_cast_value(dest_ty, value, "saturating cast")
        end
        if not one_sem_type_is_integral_scalar(dest_ty) then
            error("sem_const_eval: saturating cast requires a scalar destination type")
        end
        if const_ops.type_is_bool(src_ty) then
            return const_int_value(dest_ty, value.value and 1 or 0)
        end
        if one_sem_type_is_fp_scalar(src_ty) then
            local n = tonumber(value.raw)
            if n ~= n then
                return const_ops.const_zero_value(dest_ty)
            end
            if one_sem_type_is_signed_integral(dest_ty) then
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
        if one_sem_type_is_integral_scalar(src_ty) then
            local parsed = parse_int_raw(src_ty, value.raw)
            if one_sem_type_is_signed_integral(src_ty) then
                local s = ffi.cast("int64_t", ffi.cast(const_ops.signed_int_ctype_of(src_ty), parsed))
                if one_sem_type_is_signed_integral(dest_ty) then
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
            if one_sem_type_is_signed_integral(dest_ty) then
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
        if value.raw == nil or not one_sem_type_is_integral_scalar(ty) then
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
        if one_sem_type_is_integral_scalar(lhs_ty) then
            return lhs_ty, "int", parse_int_raw(lhs_ty, lhs.raw), parse_int_raw(rhs_ty, rhs.raw)
        end
        if one_sem_type_is_fp_scalar(lhs_ty) then
            return lhs_ty, "float", tonumber(lhs.raw), tonumber(rhs.raw)
        end
        error("sem_const_eval: " .. context .. " requires scalar numeric constants")
    end

    aux.place_const_set_binding = pvm.phase("sem_const_set_place_binding", {
        [Sem.SemPlaceBinding] = function(self)
            return pvm.once(self.binding)
        end,
        [Sem.SemPlaceDeref] = function()
            error("sem_const_stmt_eval: deref set targets are not supported during constant evaluation")
        end,
        [Sem.SemPlaceField] = function()
            error("sem_const_stmt_eval: projected set targets are not supported during constant evaluation")
        end,
        [Sem.SemPlaceIndex] = function()
            error("sem_const_stmt_eval: projected set targets are not supported during constant evaluation")
        end,
    })

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
            local binding = pvm.one(aux.place_const_set_binding(self.place))
            if not pvm.one(aux.binding_is_local_cell(binding)) then
                error("sem_const_stmt_eval: set requires a mutable local const binding")
            end
            if const_ops.find_local_entry(local_env, binding) == nil then
                error("sem_const_stmt_eval: set target is not available in the current constant local env")
            end
            local value = one_const_eval(self.value, const_env, local_env, visiting)
            if const_value_ty(value) ~= binding.ty then
                error("sem_const_stmt_eval: set constant type mismatch")
            end
            return pvm.once(Sem.SemConstStmtFallsThrough(const_ops.append_local_entry(local_env, binding, value)))
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
        [Sem.SemStmtBreakValue] = function(self, const_env, local_env, visiting)
            return pvm.once(Sem.SemConstStmtBreakValue(
                const_ops.ensure_local_env(local_env),
                one_const_eval(self.value, const_env, local_env, visiting)
            ))
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
        [Sem.SemDomainView] = function()
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
        [Sem.SemDomainView] = function()
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
            for i = 1, #self.carries do
                loop_bindings[i] = const_ops.loop_binding_as_binding(self.carries[i], self.loop_id)
            end
            local current_outer = outer_env
            local current_values = const_ops.eval_loop_init_values(self.carries, const_env, outer_env, visiting)
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
                if pvm.one(aux.const_stmt_result_is_continue_like(body_result)) then
                    current_outer = const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)
                    current_values = const_ops.eval_loop_next_values(self.carries, self.next, const_env, body_result.local_env, visiting)
                elseif pvm.one(aux.const_stmt_result_is_break(body_result)) then
                    return pvm.once(Sem.SemConstStmtFallsThrough(const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)))
                elseif pvm.one(aux.const_stmt_result_is_break_value(body_result)) then
                    error("sem_const_eval: break values are only valid in expression loops")
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
            local index_binding = const_ops.loop_index_as_binding(self)
            for i = 1, #self.carries do
                carry_bindings[i] = const_ops.loop_binding_as_binding(self.carries[i], self.loop_id)
            end
            local current_values = const_ops.eval_loop_init_values(self.carries, const_env, outer_env, visiting)
            local index_ty = self.index_port.ty
            local current_index = pvm.one(const_ops.sem_const_over_loop_start(self.domain, index_ty, const_env, outer_env, visiting))
            local iterations = 0
            while true do
                iterations = iterations + 1
                if iterations > const_ops.loop_iteration_limit then
                    error("sem_const_eval: exceeded constant loop iteration limit")
                end
                local loop_env = const_ops.with_loop_bindings(current_outer, carry_bindings, current_values)
                loop_env = const_ops.append_local_entry(loop_env, index_binding, current_index)
                local stop = pvm.one(const_ops.sem_const_over_loop_stop(self.domain, index_ty, const_env, loop_env, visiting))
                if parse_int_raw(index_ty, current_index.raw) >= parse_int_raw(index_ty, stop.raw) then
                    return pvm.once(Sem.SemConstStmtFallsThrough(current_outer))
                end
                local body_result = const_ops.eval_stmt_list(self.body, const_env, loop_env, visiting)
                if pvm.one(aux.const_stmt_result_is_continue_like(body_result)) then
                    current_outer = const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)
                    current_values = const_ops.eval_loop_next_values(self.carries, self.next, const_env, body_result.local_env, visiting)
                    current_index = const_int_value(index_ty, parse_int_raw(index_ty, current_index.raw) + 1)
                elseif pvm.one(aux.const_stmt_result_is_break(body_result)) then
                    return pvm.once(Sem.SemConstStmtFallsThrough(const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)))
                elseif pvm.one(aux.const_stmt_result_is_break_value(body_result)) then
                    error("sem_const_eval: break values are only valid in expression loops")
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
            for i = 1, #self.carries do
                loop_bindings[i] = const_ops.loop_binding_as_binding(self.carries[i], self.loop_id)
            end
            local current_outer = outer_env
            local current_values = const_ops.eval_loop_init_values(self.carries, const_env, outer_env, visiting)
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
                if pvm.one(aux.const_stmt_result_is_continue_like(body_result)) then
                    current_outer = const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)
                    current_values = const_ops.eval_loop_next_values(self.carries, self.next, const_env, body_result.local_env, visiting)
                elseif pvm.one(aux.const_stmt_result_is_break(body_result)) then
                    local exit_outer = const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)
                    local exit_env = const_ops.with_loop_bindings(exit_outer, loop_bindings, current_values)
                    return pvm.once(one_const_eval(self.result, const_env, exit_env, visiting))
                elseif pvm.one(aux.const_stmt_result_is_break_value(body_result)) then
                    return pvm.once(body_result.value)
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
            local index_binding = const_ops.loop_index_as_binding(self)
            for i = 1, #self.carries do
                carry_bindings[i] = const_ops.loop_binding_as_binding(self.carries[i], self.loop_id)
            end
            local current_values = const_ops.eval_loop_init_values(self.carries, const_env, outer_env, visiting)
            local index_ty = self.index_port.ty
            local current_index = pvm.one(const_ops.sem_const_over_loop_start(self.domain, index_ty, const_env, outer_env, visiting))
            local iterations = 0
            while true do
                iterations = iterations + 1
                if iterations > const_ops.loop_iteration_limit then
                    error("sem_const_eval: exceeded constant loop iteration limit")
                end
                local loop_env = const_ops.with_loop_bindings(current_outer, carry_bindings, current_values)
                loop_env = const_ops.append_local_entry(loop_env, index_binding, current_index)
                local stop = pvm.one(const_ops.sem_const_over_loop_stop(self.domain, index_ty, const_env, loop_env, visiting))
                if parse_int_raw(index_ty, current_index.raw) >= parse_int_raw(index_ty, stop.raw) then
                    return pvm.once(one_const_eval(self.result, const_env, loop_env, visiting))
                end
                local body_result = const_ops.eval_stmt_list(self.body, const_env, loop_env, visiting)
                if pvm.one(aux.const_stmt_result_is_continue_like(body_result)) then
                    current_outer = const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)
                    current_values = const_ops.eval_loop_next_values(self.carries, self.next, const_env, body_result.local_env, visiting)
                    current_index = const_int_value(index_ty, parse_int_raw(index_ty, current_index.raw) + 1)
                elseif pvm.one(aux.const_stmt_result_is_break(body_result)) then
                    local exit_outer = const_ops.project_env_to_bindings(body_result.local_env, outer_bindings)
                    local exit_env = const_ops.with_loop_bindings(exit_outer, carry_bindings, current_values)
                    exit_env = const_ops.append_local_entry(exit_env, index_binding, current_index)
                    return pvm.once(one_const_eval(self.result, const_env, exit_env, visiting))
                elseif pvm.one(aux.const_stmt_result_is_break_value(body_result)) then
                    return pvm.once(body_result.value)
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

    aux.const_binding_eval = pvm.phase("sem_const_eval_binding", {
        [Sem.SemBindLocalValue] = function(self, const_env, local_env)
            local entry = const_ops.find_local_entry(local_env, self)
            if entry == nil then
                error("sem_const_eval: constant data cannot capture runtime bindings")
            end
            if const_value_ty(entry.value) ~= self.ty then
                error("sem_const_eval: local const binding '" .. self.name .. "' has type drift during const evaluation")
            end
            return pvm.once(entry.value)
        end,
        [Sem.SemBindLocalCell] = function(self, const_env, local_env)
            local entry = const_ops.find_local_entry(local_env, self)
            if entry == nil then
                error("sem_const_eval: constant data cannot capture runtime bindings")
            end
            if const_value_ty(entry.value) ~= self.ty then
                error("sem_const_eval: local const binding '" .. self.name .. "' has type drift during const evaluation")
            end
            return pvm.once(entry.value)
        end,
        [Sem.SemBindLoopCarry] = function(self, const_env, local_env)
            local entry = const_ops.find_local_entry(local_env, self)
            if entry == nil then
                error("sem_const_eval: constant data cannot capture runtime bindings")
            end
            if const_value_ty(entry.value) ~= self.ty then
                error("sem_const_eval: local const binding '" .. self.name .. "' has type drift during const evaluation")
            end
            return pvm.once(entry.value)
        end,
        [Sem.SemBindLoopIndex] = function(self, const_env, local_env)
            local entry = const_ops.find_local_entry(local_env, self)
            if entry == nil then
                error("sem_const_eval: constant data cannot capture runtime bindings")
            end
            if const_value_ty(entry.value) ~= self.ty then
                error("sem_const_eval: local const binding '" .. self.name .. "' has type drift during const evaluation")
            end
            return pvm.once(entry.value)
        end,
        [Sem.SemBindArg] = function()
            error("sem_const_eval: constant data cannot capture runtime bindings")
        end,
        [Sem.SemBindGlobalConst] = function(self, const_env, local_env, visiting)
            local key = const_binding_key(self)
            if visiting ~= nil and visiting[key] then
                error("sem_const_eval: cyclic const dependency at '" .. key .. "'")
            end
            local entry = find_const_entry(const_env, self.module_name, self.item_name)
            if entry == nil then
                error("sem_const_eval: unknown const binding '" .. key .. "'")
            end
            if entry.ty ~= self.ty then
                error("sem_const_eval: const binding '" .. key .. "' has type drift during const evaluation")
            end
            return pvm.once(one_const_eval(entry.value, const_env, nil, with_const_visiting(visiting, key)))
        end,
        [Sem.SemBindGlobalStatic] = function()
            error("sem_const_eval: constant data cannot capture runtime bindings")
        end,
        [Sem.SemBindGlobalFunc] = function()
            error("sem_const_eval: constant data cannot capture runtime bindings")
        end,
        [Sem.SemBindExtern] = function()
            error("sem_const_eval: constant data cannot capture runtime bindings")
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
            return pvm.once(pvm.one(aux.const_binding_eval(self.binding, const_env, local_env, visiting)))
        end,
        [Sem.SemExprNeg] = function(self, const_env, local_env, visiting)
            local value = one_const_eval(self.value, const_env, local_env, visiting)
            local ty = const_value_ty(value)
            if ty ~= self.ty then
                error("sem_const_eval: neg constant type mismatch")
            end
            if one_sem_type_is_integral_scalar(ty) then
                return pvm.once(const_int_value(ty, -parse_int_raw(ty, value.raw)))
            end
            if one_sem_type_is_fp_scalar(ty) then
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
        [Sem.SemExprAddrOf] = function() error("sem_const_eval: address constants are not supported") end,
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
        [Sem.SemExprDeref] = function() error("sem_const_eval: deref constants are not supported") end,
    })

    return {
        ensure_const_env = ensure_const_env,
        sem_const_eval = sem_const_eval,
        sem_const_stmt_eval = sem_const_stmt_eval,
        const_ops = const_ops,
    }
end

return M
