return function(ctx)
    local backend = assert(ctx.backend)
    local new_type = assert(ctx.new_type)
    local types = assert(ctx.types)
    local is_expr = assert(ctx.is_expr)
    local is_agg_init = assert(ctx.is_agg_init)
    local is_layout_view = assert(ctx.is_layout_view)
    local StructScalarVarMT = assert(ctx.StructScalarVarMT)
    local make_ptr = assert(ctx.make_ptr)
    local make_array = assert(ctx.make_array)
    local make_slice = assert(ctx.make_slice)
    local make_struct = assert(ctx.make_struct)
    local make_union = assert(ctx.make_union)
    local make_tagged_union = assert(ctx.make_tagged_union)
    local make_enum = assert(ctx.make_enum)
    local build_function = assert(ctx.build_function)
    local bind_let = assert(ctx.bind_let)
    local bind_var = assert(ctx.bind_var)
    local as_expr = assert(ctx.as_expr)
    local expr = assert(ctx.expr)
    local capture_stmt_block = assert(ctx.capture_stmt_block)
    local emit_stmt = assert(ctx.emit_stmt)
    local lower_call_arg = assert(ctx.lower_call_arg)
    local lower_param = assert(ctx.lower_param)
    local lower_type_name = assert(ctx.lower_type_name)
    local is_layout_type = assert(ctx.is_layout_type)
    local is_void_type = assert(ctx.is_void_type)
    local type_size = assert(ctx.type_size)
    local type_align = assert(ctx.type_align)
    local layout_type_of_value = assert(ctx.layout_type_of_value)
    local layout_ptr_of_value = assert(ctx.layout_ptr_of_value)
    local hole = assert(ctx.hole)
    local cast = assert(ctx.cast)
    local trunc = assert(ctx.trunc)
    local zext = assert(ctx.zext)
    local sext = assert(ctx.sext)
    local bitcast = assert(ctx.bitcast)
    local load = assert(ctx.load)
    local store = assert(ctx.store)
    local memcpy = assert(ctx.memcpy)
    local memmove = assert(ctx.memmove)
    local memset = assert(ctx.memset)
    local memcmp = assert(ctx.memcmp)
    local block = assert(ctx.block)
    local if_ = assert(ctx.if_)
    local switch_ = assert(ctx.switch_)
    local while_ = assert(ctx.while_)
    local break_ = assert(ctx.break_)
    local continue_ = assert(ctx.continue_)
    local FunctionMT = assert(ctx.FunctionMT)
    local module_ctor = assert(ctx.module_ctor)

    local function decode_backend_ast(label, text)
        local chunk, err
        if type(loadstring) == "function" then
            chunk, err = loadstring("return " .. text, "=(moonlift." .. label .. ")")
            assert(chunk, err)
            if type(setfenv) == "function" then
                setfenv(chunk, {})
            end
            return chunk()
        end
        chunk, err = load("return " .. text, "=(moonlift." .. label .. ")", "t", {})
        assert(chunk, err)
        return chunk()
    end

    local function eval_host_source(source, host_env, label)
        local chunk, err
        if type(loadstring) == "function" then
            chunk, err = loadstring("return " .. source, label or "=(moonlift.splice)")
            assert(chunk, err)
            if type(setfenv) == "function" then
                setfenv(chunk, host_env)
            end
            return chunk()
        end
        chunk, err = load("return " .. source, label or "=(moonlift.splice)", "t", host_env)
        assert(chunk, err)
        return chunk()
    end

    local AstMT

    local function ast_is_array(t)
        local n = #t
        for k, _ in pairs(t) do
            if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
                return false, n
            end
        end
        return true, n
    end

    local ast_key_rank = {
        tag = 1,
        visibility = 2,
        name = 3,
        item = 4,
        sig = 5,
        params = 6,
        result = 7,
        ty = 8,
        value = 9,
        body = 10,
        fields = 11,
        items = 12,
        attrs = 13,
    }

    local function ast_scalar_string(x)
        local tx = type(x)
        if tx == "string" then return string.format("%q", x) end
        if tx == "number" or tx == "boolean" or x == nil then return tostring(x) end
        return tx
    end

    local function ast_sorted_keys(t)
        local keys = {}
        for k, _ in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            local ra = ast_key_rank[a] or 100
            local rb = ast_key_rank[b] or 100
            if ra ~= rb then return ra < rb end
            return ast_scalar_string(a) < ast_scalar_string(b)
        end)
        return keys
    end

    local function ast_inline_format(x, seen)
        local tx = type(x)
        if tx ~= "table" then return ast_scalar_string(x) end
        if seen[x] then return "<cycle>" end
        seen[x] = true

        local out
        local is_array, n = ast_is_array(x)
        if is_array then
            if n == 0 then
                out = "[]"
            else
                local parts = {}
                for i = 1, n do parts[i] = ast_inline_format(x[i], seen) end
                out = "[ " .. table.concat(parts, ", ") .. " ]"
            end
        else
            local keys = ast_sorted_keys(x)
            if #keys == 0 then
                out = "{}"
            else
                local parts = {}
                for i = 1, #keys do
                    local k = keys[i]
                    parts[i] = tostring(k) .. " = " .. ast_inline_format(x[k], seen)
                end
                out = "{ " .. table.concat(parts, ", ") .. " }"
            end
        end

        seen[x] = nil
        return out
    end

    local function ast_can_inline(x, seen)
        local tx = type(x)
        if tx ~= "table" then return true end
        if seen[x] then return true end
        seen[x] = true

        local ok = true
        local is_array, n = ast_is_array(x)
        if is_array then
            if n > 4 then
                ok = false
            else
                for i = 1, n do
                    if not ast_can_inline(x[i], seen) then ok = false break end
                end
            end
        else
            local keys = ast_sorted_keys(x)
            if #keys > 5 then
                ok = false
            else
                for i = 1, #keys do
                    if not ast_can_inline(x[keys[i]], seen) then ok = false break end
                end
            end
        end

        seen[x] = nil
        if not ok then return false end
        local inline = ast_inline_format(x, {})
        return #inline <= 96 and inline:find("\n", 1, true) == nil
    end

    local function ast_format(x, indent, seen)
        local tx = type(x)
        if tx ~= "table" then return ast_scalar_string(x) end
        if ast_can_inline(x, {}) then
            return ast_inline_format(x, {})
        end
        if seen[x] then return "<cycle>" end
        seen[x] = true

        local pad = string.rep("  ", indent)
        local child_pad = string.rep("  ", indent + 1)
        local is_array, n = ast_is_array(x)
        if is_array then
            if n == 0 then
                seen[x] = nil
                return "[]"
            end
            local parts = { "[" }
            for i = 1, n do
                parts[#parts + 1] = child_pad .. ast_format(x[i], indent + 1, seen)
                if i < n then parts[#parts] = parts[#parts] .. "," end
            end
            parts[#parts + 1] = pad .. "]"
            seen[x] = nil
            return table.concat(parts, "\n")
        end

        local keys = ast_sorted_keys(x)
        if #keys == 0 then
            seen[x] = nil
            return "{}"
        end
        local parts = { "{" }
        for i = 1, #keys do
            local k = keys[i]
            parts[#parts + 1] = child_pad .. tostring(k) .. " = " .. ast_format(x[k], indent + 1, seen)
            if i < #keys then parts[#parts] = parts[#parts] .. "," end
        end
        parts[#parts + 1] = pad .. "}"
        seen[x] = nil
        return table.concat(parts, "\n")
    end

    AstMT = {
        __tostring = function(self)
            return ast_format(self, 0, {})
        end,
    }

    local function attach_ast_meta(x, seen)
        if type(x) ~= "table" then return x end
        seen = seen or {}
        if seen[x] then return x end
        seen[x] = true
        if getmetatable(x) == nil then
            setmetatable(x, AstMT)
        end
        for _, v in pairs(x) do
            attach_ast_meta(v, seen)
        end
        return x
    end

    local function clone_ast(x, seen)
        if type(x) ~= "table" then return x end
        seen = seen or {}
        if seen[x] ~= nil then return seen[x] end
        local out = {}
        seen[x] = out
        for k, v in pairs(x) do
            out[clone_ast(k, seen)] = clone_ast(v, seen)
        end
        local mt = getmetatable(x)
        if mt ~= nil then setmetatable(out, mt) end
        return out
    end

    local ast_cache = {}

    local function parse_backend_ast(backend_fn, source, label)
        local bucket = ast_cache[label]
        if bucket == nil then
            bucket = {}
            ast_cache[label] = bucket
        end
        local cached = bucket[source]
        if cached ~= nil then
            if cached.ok then
                return clone_ast(cached.ast)
            end
            return nil, cached.err
        end

        local text, err = backend_fn(source)
        if text == nil then
            bucket[source] = { ok = false, err = err }
            return nil, err
        end
        local ok, out = pcall(decode_backend_ast, label, text)
        if not ok then
            bucket[source] = { ok = false, err = out }
            return nil, out
        end
        out = attach_ast_meta(out)
        bucket[source] = { ok = true, ast = out }
        return clone_ast(out)
    end

    local function caller_env(level)
        if type(getfenv) == "function" then
            local ok, env = pcall(getfenv, (level or 1) + 1)
            if ok and type(env) == "table" then
                return env
            end
        end
        return _G
    end

    local native_code_meta_cache = {}
    local native_module_meta_cache = {}

    local function source_scalar_type_by_name(name)
        local T = types[name]
        assert(T ~= nil, "moonlift native source fast path does not know scalar type '" .. tostring(name) .. "'")
        return T
    end

    local function source_native_params_from_meta(params)
        local out = {}
        for i = 1, #(params or {}) do
            local param_meta = params[i]
            out[i] = {
                name = param_meta.name,
                t = source_scalar_type_by_name(param_meta.type),
            }
        end
        return out
    end

    local function source_make_native_function(meta, source)
        local params = source_native_params_from_meta(meta.params)
        local result_t = source_scalar_type_by_name(meta.result)
        local lowered_params = {}
        for i = 1, #params do
            lowered_params[i] = lower_type_name(params[i].t)
        end
        return setmetatable({
            name = meta.name,
            params = params,
            result = result_t,
            arity = #params,
            body = nil,
            lowered = {
                name = meta.name,
                params = lowered_params,
                result = lower_type_name(result_t),
            },
            __native_source = source,
        }, FunctionMT)
    end

    local function source_make_native_module(meta, source)
        local funcs = {}
        for i = 1, #(meta.funcs or {}) do
            funcs[i] = source_make_native_function(meta.funcs[i], source)
        end
        local mod = module_ctor(funcs)
        mod.__native_source = source
        for i = 1, #funcs do funcs[i].__owner_module = mod end
        return mod
    end

    local function try_native_source_code(source)
        if type(backend.source_meta_code) ~= "function" then return nil end
        local meta = native_code_meta_cache[source]
        if meta == false then return nil end
        if meta == nil then
            local out, err = backend.source_meta_code(source)
            if out == nil then
                if type(err) == "string" and err:find("^unsupported native source fast path:") ~= nil then
                    native_code_meta_cache[source] = false
                    return nil
                end
                assert(out ~= nil, err)
            end
            meta = out
            native_code_meta_cache[source] = meta
        end
        return source_make_native_function(meta, source)
    end

    local function try_native_source_module(source)
        if type(backend.source_meta_module) ~= "function" then return nil end
        local meta = native_module_meta_cache[source]
        if meta == false then return nil end
        if meta == nil then
            local out, err = backend.source_meta_module(source)
            if out == nil then
                if type(err) == "string" and err:find("^unsupported native source fast path:") ~= nil then
                    native_module_meta_cache[source] = false
                    return nil
                end
                assert(out ~= nil, err)
            end
            meta = out
            native_module_meta_cache[source] = meta
        end
        return source_make_native_module(meta, source)
    end

    local function shallow_copy(t)
        local out = {}
        for k, v in pairs(t) do out[k] = v end
        return out
    end

    local function unwrap_source_item(ast)
        if type(ast) == "table" and ast.item ~= nil then
            local item = ast.item
            item.visibility = ast.visibility
            item.attrs = ast.attrs
            return item
        end
        return ast
    end

    local function path_last_segment(path)
        return path.segments[#path.segments]
    end

    local function make_source_func_type(params, result_t)
        local parts = {}
        for i = 1, #params do parts[i] = params[i].name end
        return new_type {
            name = ("func(%s)->%s"):format(table.concat(parts, ","), result_t and result_t.name or "void"),
            lowering_name = "ptr",
            const_tag = "ptr",
            family = "funcptr",
            bits = 64,
            size = 8,
            align = 8,
            params = params,
            result = result_t,
        }
    end

    local function source_new_env(host_env)
        return {
            host_env = host_env or _G,
            locals = {},
            types = setmetatable({}, { __index = types }),
            values = {},
            func_infos = {},
            extern_infos = {},
            method_infos = {},
            const_infos = {},
            exports = {},
        }
    end

    local function source_child_env(env)
        return {
            host_env = env.host_env,
            locals = shallow_copy(env.locals),
            types = env.types,
            values = env.values,
            func_infos = env.func_infos,
            extern_infos = env.extern_infos,
            method_infos = env.method_infos,
            const_infos = env.const_infos,
            exports = env.exports,
        }
    end

    local function source_attr(item, name)
        local attrs = item.attrs or {}
        for i = 1, #attrs do
            if attrs[i].name == name then return attrs[i] end
        end
        return nil
    end

    local function source_attr_string(item, name)
        local attr = source_attr(item, name)
        if attr == nil or attr.args == nil or attr.args[1] == nil then return nil end
        return attr.args[1].value
    end

    local function source_lookup_path(root, segments, start_i)
        local value = root
        for i = start_i or 1, #segments do
            if value == nil then return nil end
            value = value[segments[i]]
        end
        return value
    end

    local source_lower_expr
    local source_lower_block_value
    local source_lower_block_void
    local source_lower_code_item
    local source_block_contains_return
    local source_block_always_returns
    local source_infer_expr_type
    local source_infer_function_result
    local source_resolve_callable
    local source_resolve_path_value
    local source_const_cast_value
    local source_eval_const_expr
    local source_eval_const_integer

    local function source_resolve_type(ast, env)
        if ast.tag == "path" then
            local first = ast.segments[1]
            local value = env.types[first] or types[first]
            assert(value ~= nil, ("unknown Moonlift type '%s'"):format(first))
            return source_lookup_path(value, ast.segments, 2)
        elseif ast.tag == "pointer" then
            return make_ptr(source_resolve_type(ast.inner, env))
        elseif ast.tag == "array" then
            return make_array(source_resolve_type(ast.elem, env), source_eval_const_integer(ast.len, env, "array length"))
        elseif ast.tag == "slice" then
            return make_slice(source_resolve_type(ast.elem, env))
        elseif ast.tag == "func_type" then
            local params = {}
            for i = 1, #(ast.params or {}) do
                params[i] = { name = tostring(i), t = source_resolve_type(ast.params[i], env) }
            end
            local result_t = ast.result and source_resolve_type(ast.result, env) or types.void
            return make_source_func_type(params, result_t)
        elseif ast.tag == "splice" then
            return eval_host_source(ast.source, env.host_env, "=(moonlift.type.splice)")
        else
            error("unsupported Moonlift source type tag: " .. tostring(ast.tag), 2)
        end
    end

    local function source_value_type(v)
        if is_expr(v) then return v.t end
        if is_agg_init(v) then return v._layout end
        if is_layout_view(v) then return layout_type_of_value(v) end
        if type(v) == "table" and getmetatable(v) == StructScalarVarMT then
            return rawget(v, "_struct")
        end
        return nil
    end

    local function source_coerce_value(v, want_t)
        if want_t == nil then return v end
        if is_layout_type(want_t) then
            local got_t = source_value_type(v)
            assert(got_t == want_t or (is_agg_init(v) and v._layout == want_t), "moonlift source aggregate type mismatch")
            return v
        end
        return as_expr(v, want_t)
    end

    local function source_zero_value(t)
        if is_layout_type(t) then
            if t.layout_kind == "struct" then
                local values = {}
                for i = 1, #(t.fields or {}) do
                    local f = t.fields[i]
                    values[f.name] = source_zero_value(f.type)
                end
                return t(values)
            elseif t.layout_kind == "array" then
                local values = {}
                for i = 1, t.count do
                    values[i] = source_zero_value(t.elem)
                end
                return t(values)
            end
        end
        if t.family == "bool" then return types.bool(false) end
        if t.family == "float" then return t(0) end
        if t.family == "int" or t.family == "enum" or t.family == "ptr" or t.family == "funcptr" then
            return t(0)
        end
        error("moonlift source cannot synthesize a zero value for type " .. tostring(t and t.name), 2)
    end

    local function source_emit_side_effect_expr(v)
        if v == nil then return nil end
        if is_expr(v) or is_agg_init(v) or is_layout_view(v) then
            return bind_let(v)
        end
        return v
    end

    local function source_make_return_state(result_t, void_function)
        return {
            result_t = result_t,
            result_ref = (not void_function) and bind_var(source_zero_value(result_t)) or nil,
            returned_ref = bind_var(types.bool(false)),
            void_function = void_function,
        }
    end

    local function source_emit_return_stmt(stmt, env, in_loop, return_state)
        assert(return_state ~= nil, "moonlift internal source return state is missing")
        if return_state.void_function then
            assert(stmt.value == nil, "moonlift void function return must not return a value")
        else
            assert(stmt.value ~= nil, "moonlift non-void function return must return a value")
            return_state.result_ref:set(source_coerce_value(source_lower_expr(stmt.value, env), return_state.result_t))
        end
        return_state.returned_ref:set(types.bool(true))
        if in_loop then break_() end
        return true
    end

    local function source_capture_lowered_block(block_ast, env, in_loop, void_function, return_state)
        if block_ast == nil then return {} end
        return capture_stmt_block(function()
            source_lower_block_void(block_ast, env, in_loop, void_function, return_state)
        end)
    end

    local function source_stmt_has_return(stmt)
        if stmt.tag == "return" then
            return true
        elseif stmt.tag == "if" then
            for i = 1, #(stmt.branches or {}) do
                if source_block_contains_return(stmt.branches[i].body) then return true end
            end
            return stmt.else_body ~= nil and source_block_contains_return(stmt.else_body) or false
        elseif stmt.tag == "switch" then
            for i = 1, #(stmt.cases or {}) do
                if source_block_contains_return(stmt.cases[i].body) then return true end
            end
            return stmt.default ~= nil and source_block_contains_return(stmt.default) or false
        elseif stmt.tag == "while" or stmt.tag == "for" then
            return source_block_contains_return(stmt.body)
        end
        return false
    end

    local next_infer_var_id = 0

    local function source_new_infer_var(label)
        next_infer_var_id = next_infer_var_id + 1
        return {
            _infer_kind = "typevar",
            id = next_infer_var_id,
            label = label,
            name = ("<infer:%s#%d>"):format(label, next_infer_var_id),
        }
    end

    local function source_prune_type(t)
        while type(t) == "table" and t._infer_kind == "typevar" and t.resolved ~= nil do
            t = t.resolved
        end
        return t
    end

    local function source_is_infer_var(t)
        t = source_prune_type(t)
        return type(t) == "table" and t._infer_kind == "typevar"
    end

    local function source_require_resolved_type(t, label)
        t = source_prune_type(t)
        if source_is_infer_var(t) then
            error(("moonlift source could not infer %s; add an explicit type annotation"):format(label), 2)
        end
        return t
    end

    local function source_type_name(t)
        t = source_prune_type(t)
        if source_is_infer_var(t) then
            return t.name
        end
        return t and t.name or tostring(t)
    end

    local function source_unify_type(a, b, label)
        a = source_prune_type(a)
        b = source_prune_type(b)
        if a == nil then return b end
        if b == nil then return a end
        if a == b then return a end
        if source_is_infer_var(a) then
            a.resolved = b
            return b
        end
        if source_is_infer_var(b) then
            b.resolved = a
            return a
        end
        assert(
            a == b,
            ("moonlift source inferred conflicting %s types: %s vs %s"):format(
                label,
                source_type_name(a),
                source_type_name(b)
            )
        )
        return a
    end

    local function source_info_label(info)
        return info.label or info.name or info.symbol or "<anonymous>"
    end

    local function source_const_runtime_value(t, value)
        t = source_prune_type(t)
        if t == nil or is_layout_type(t) then return nil end
        value = source_const_cast_value(t, value)
        if type(value) == "boolean" then
            return types.bool(value)
        elseif type(value) == "number" then
            return t(value)
        end
        return nil
    end

    local function source_bind_local(env, name, value, t, mutable)
        env.locals[name] = {
            value = value,
            t = t or source_value_type(value),
            mutable = mutable,
        }
        return value
    end

    local function source_infer_const_type(info, env)
        if info.t ~= nil then return info.t end
        if info._inferring then
            error(("moonlift source cannot infer recursive const '%s'; add an explicit type annotation"):format(info.name), 2)
        end
        info._inferring = true
        local t = info.ty_ast and source_resolve_type(info.ty_ast, env) or source_infer_expr_type(info.value_ast, env)
        info._inferring = nil
        info.t = t
        return t
    end

    local function source_infer_info_result(info, env)
        if info.result ~= nil and not source_is_infer_var(info.result) then return info.result end
        if info._inferring then
            info.result = info.result or source_new_infer_var(("result of %s"):format(source_info_label(info)))
            return info.result
        end
        info._inferring = true
        info.result = info.result or source_new_infer_var(("result of %s"):format(source_info_label(info)))
        local infer_env = source_child_env(env)
        for i = 1, #(info.params or {}) do
            local p = info.params[i]
            source_bind_local(infer_env, p.name, nil, p.t, false)
        end
        local inferred = source_infer_function_result(info.ast, infer_env, source_info_label(info))
        info._inferring = nil
        info.result = source_require_resolved_type(
            source_unify_type(info.result, inferred, ("result type for %s"):format(source_info_label(info))),
            ("result type for %s"):format(source_info_label(info))
        )
        return info.result
    end

    local function source_infer_value_type(value, env)
        if value == nil then return nil end
        if type(value) == "number" then return types.i32 end
        if type(value) == "boolean" then return types.bool end
        if type(value) == "table" and value.params ~= nil and value.result ~= nil then
            return make_source_func_type(value.params, source_prune_type(value.result))
        end
        if type(value) == "table" and getmetatable(value) == FunctionMT then
            return make_source_func_type(value.params, source_prune_type(value.result))
        end
        local t = source_value_type(value)
        return source_prune_type(t)
    end

    local function source_member_type(base_t, key, env)
        local host_t = base_t
        if host_t ~= nil and host_t.family == "ptr" and host_t.elem ~= nil then
            host_t = host_t.elem
        end
        if host_t ~= nil and host_t.layout_kind == "struct" then
            local field = host_t.field_lookup and host_t.field_lookup[key]
            if field ~= nil then return field.type end
            local method_bucket = env.method_infos[host_t.name]
            local method = method_bucket and method_bucket[key] or nil
            if method ~= nil then
                return make_source_func_type(method.params, source_infer_info_result(method, env))
            end
        elseif host_t ~= nil and host_t.layout_kind == "array" then
            if key == "count" or key == "size" then return types.usize end
        end
        return nil
    end

    local function source_infer_path_type(ast, env)
        local segs = ast.segments
        local base_t
        local start_i = 2

        local local_entry = env.locals[segs[1]]
        if local_entry ~= nil then
            base_t = local_entry.t or source_value_type(local_entry.value)
        end

        if base_t == nil then
            local info = env.func_infos[segs[1]] or env.extern_infos[segs[1]]
            if info ~= nil then
                base_t = make_source_func_type(info.params, source_infer_info_result(info, env))
            end
        end

        if base_t == nil then
            local const_info = env.const_infos[segs[1]]
            if const_info ~= nil then
                base_t = source_infer_const_type(const_info, env)
            end
        end

        if base_t == nil then
            local value = env.values[segs[1]]
            if value ~= nil then
                base_t = source_infer_value_type(value, env)
            end
        end

        if base_t == nil then
            local value = env.types[segs[1]] or types[segs[1]]
            if value ~= nil then
                for i = 2, #segs do value = value[segs[i]] end
                base_t = source_infer_value_type(value, env)
                start_i = #segs + 1
            end
        end

        assert(base_t ~= nil, ("unknown Moonlift name '%s'"):format(path_last_segment(ast)))
        for i = start_i, #segs do
            local next_t = source_member_type(base_t, segs[i], env)
            assert(
                next_t ~= nil,
                ("moonlift source cannot resolve member '%s' on type %s"):format(segs[i], source_type_name(base_t))
            )
            base_t = next_t
        end
        return base_t
    end

    local function source_infer_index_type(base_t)
        base_t = source_prune_type(base_t)
        if base_t ~= nil and base_t.family == "ptr" and base_t.elem ~= nil then
            return base_t.elem
        elseif base_t ~= nil and base_t.layout_kind == "array" then
            return base_t.elem
        end
        error(("moonlift source cannot index value of type %s"):format(source_type_name(base_t)), 2)
    end

    local bitlib = rawget(_G, "bit")

    source_const_cast_value = function(to_t, value)
        to_t = source_prune_type(to_t)
        if to_t == nil then return value end
        if to_t.family == "bool" then
            return not not value
        elseif to_t.family == "float" then
            return tonumber(value)
        elseif to_t.family == "int" or to_t.family == "enum" or to_t.family == "ptr" or to_t.family == "funcptr" then
            if type(value) == "boolean" then return value and 1 or 0 end
            return assert(tonumber(value), "moonlift source constant cast requires a numeric value")
        end
        return value
    end

    local function source_extract_const_atom(value)
        if type(value) == "number" or type(value) == "boolean" then return value end
        if is_expr(value) and value.node ~= nil and value.node.value ~= nil then
            return value.node.value
        end
        return nil
    end

    source_eval_const_expr = function(ast, env)
        local tag = ast.tag
        if tag == "number" then
            return assert(tonumber(ast.raw), "invalid Moonlift numeric literal")
        elseif tag == "bool" then
            return ast.value
        elseif tag == "path" then
            local value = source_resolve_path_value(ast, env)
            if value ~= nil then
                local atom = source_extract_const_atom(value)
                if atom ~= nil then return atom end
            end
            local const_info = env.const_infos and env.const_infos[ast.segments[1]] or nil
            if const_info ~= nil then
                if const_info._evaluating then
                    error(("moonlift source constant '%s' is recursively defined"):format(const_info.name), 2)
                end
                const_info._evaluating = true
                const_info.const_value = source_eval_const_expr(const_info.value_ast, env)
                const_info._evaluating = nil
                return const_info.const_value
            end
        elseif tag == "if" then
            for i = 1, #(ast.branches or {}) do
                local branch = ast.branches[i]
                if source_eval_const_expr(branch.cond, env) then
                    return source_eval_const_expr(branch.value, source_child_env(env))
                end
            end
            return source_eval_const_expr(ast.else_value, source_child_env(env))
        elseif tag == "switch" then
            local key = source_eval_const_expr(ast.value, env)
            for i = 1, #(ast.cases or {}) do
                local case = ast.cases[i]
                if key == source_eval_const_expr(case.value, env) then
                    return source_eval_const_expr(case.body, source_child_env(env))
                end
            end
            return source_eval_const_expr(ast.default, source_child_env(env))
        elseif tag == "unary" then
            local v = source_eval_const_expr(ast.expr, env)
            if ast.op == "neg" then return -v end
            if ast.op == "not" then return not v end
            if ast.op == "bnot" then
                bitlib = bitlib or require("bit")
                return bitlib.bnot(v)
            end
        elseif tag == "binary" then
            local a = source_eval_const_expr(ast.lhs, env)
            local b = source_eval_const_expr(ast.rhs, env)
            if ast.op == "add" then return a + b end
            if ast.op == "sub" then return a - b end
            if ast.op == "mul" then return a * b end
            if ast.op == "div" then return a / b end
            if ast.op == "rem" then return a % b end
            if ast.op == "eq" then return a == b end
            if ast.op == "ne" then return a ~= b end
            if ast.op == "lt" then return a < b end
            if ast.op == "le" then return a <= b end
            if ast.op == "gt" then return a > b end
            if ast.op == "ge" then return a >= b end
            if ast.op == "and" then return a and b end
            if ast.op == "or" then return a or b end
            bitlib = bitlib or require("bit")
            if ast.op == "band" then return bitlib.band(a, b) end
            if ast.op == "bor" then return bitlib.bor(a, b) end
            if ast.op == "bxor" then return bitlib.bxor(a, b) end
            if ast.op == "shl" then return bitlib.lshift(a, b) end
            if ast.op == "shr" or ast.op == "shr_u" then return bitlib.rshift(a, b) end
        elseif tag == "sizeof" then
            return type_size(source_resolve_type(ast.ty, env))
        elseif tag == "alignof" then
            return type_align(source_resolve_type(ast.ty, env))
        elseif tag == "offsetof" then
            local T = source_resolve_type(ast.ty, env)
            local field = assert(T.field_lookup and T.field_lookup[ast.field], "unknown field for offsetof")
            return field.offset
        elseif tag == "cast" or tag == "trunc" or tag == "zext" or tag == "sext" or tag == "bitcast" then
            return source_const_cast_value(source_resolve_type(ast.ty, env), source_eval_const_expr(ast.value, env))
        elseif tag == "splice" then
            local value = eval_host_source(ast.source, env.host_env, "=(moonlift.const.splice)")
            local atom = source_extract_const_atom(value)
            if atom ~= nil then return atom end
        end
        error("moonlift source expression is not a compile-time constant", 2)
    end

    source_eval_const_integer = function(ast, env, label)
        local v = source_eval_const_expr(ast, env)
        assert(type(v) == "number", ("moonlift source %s must be numeric constant"):format(label))
        local iv = tonumber(v)
        assert(iv ~= nil and iv == math.floor(iv), ("moonlift source %s must be an integer constant"):format(label))
        return iv
    end

    local function source_collect_result_candidates(block_ast, env, label)
        local candidates = {}
        local stmts = block_ast.stmts or {}
        local work_env = source_child_env(env)
        local always_returns = source_block_always_returns(block_ast)
        local tail_expr = nil
        local last_i = #stmts

        if not always_returns then
            local tail_stmt = stmts[last_i]
            if tail_stmt ~= nil and tail_stmt.tag == "expr" then
                tail_expr = tail_stmt.expr
                last_i = last_i - 1
            end
        end

        local function add_candidate(t, why)
            candidates[#candidates + 1] = { t = t, why = why }
        end

        local function infer_stmt(stmt, infer_env)
            if stmt.tag == "let" or stmt.tag == "var" then
                local init_t = source_infer_expr_type(stmt.value, infer_env)
                local t = stmt.ty and source_resolve_type(stmt.ty, infer_env) or init_t
                source_unify_type(t, init_t, ("initializer for %s '%s'"):format(stmt.tag, stmt.name))
                source_bind_local(infer_env, stmt.name, nil, t, stmt.tag == "var")
            elseif stmt.tag == "assign" then
                source_infer_expr_type(stmt.value, infer_env)
            elseif stmt.tag == "expr" then
                source_infer_expr_type(stmt.expr, infer_env)
            elseif stmt.tag == "memcpy" then
                source_infer_expr_type(stmt.dst, infer_env)
                source_infer_expr_type(stmt.src, infer_env)
                source_infer_expr_type(stmt.len, infer_env)
            elseif stmt.tag == "memmove" then
                source_infer_expr_type(stmt.dst, infer_env)
                source_infer_expr_type(stmt.src, infer_env)
                source_infer_expr_type(stmt.len, infer_env)
            elseif stmt.tag == "memset" then
                source_infer_expr_type(stmt.dst, infer_env)
                source_infer_expr_type(stmt.byte, infer_env)
                source_infer_expr_type(stmt.len, infer_env)
            elseif stmt.tag == "store" then
                local store_t = source_resolve_type(stmt.ty, infer_env)
                source_unify_type(store_t, source_infer_expr_type(stmt.value, infer_env), "store")
                source_infer_expr_type(stmt.dst, infer_env)
            elseif stmt.tag == "return" then
                add_candidate(stmt.value and source_infer_expr_type(stmt.value, infer_env) or types.void, "return")
            elseif stmt.tag == "if" then
                for i = 1, #(stmt.branches or {}) do
                    local branch = stmt.branches[i]
                    source_unify_type(types.bool, source_infer_expr_type(branch.cond, infer_env), "if condition")
                    local nested = source_collect_result_candidates(branch.body, source_child_env(infer_env), label)
                    for j = 1, #nested do add_candidate(nested[j].t, nested[j].why) end
                end
                if stmt.else_body ~= nil then
                    local nested = source_collect_result_candidates(stmt.else_body, source_child_env(infer_env), label)
                    for j = 1, #nested do add_candidate(nested[j].t, nested[j].why) end
                end
            elseif stmt.tag == "switch" then
                source_infer_expr_type(stmt.value, infer_env)
                for i = 1, #(stmt.cases or {}) do
                    local case = stmt.cases[i]
                    source_infer_expr_type(case.value, infer_env)
                    local nested = source_collect_result_candidates(case.body, source_child_env(infer_env), label)
                    for j = 1, #nested do add_candidate(nested[j].t, nested[j].why) end
                end
                if stmt.default ~= nil then
                    local nested = source_collect_result_candidates(stmt.default, source_child_env(infer_env), label)
                    for j = 1, #nested do add_candidate(nested[j].t, nested[j].why) end
                end
            elseif stmt.tag == "while" then
                source_unify_type(types.bool, source_infer_expr_type(stmt.cond, infer_env), "while condition")
                local nested = source_collect_result_candidates(stmt.body, source_child_env(infer_env), label)
                for j = 1, #nested do add_candidate(nested[j].t, nested[j].why) end
            elseif stmt.tag == "for" then
                local start_t = source_infer_expr_type(stmt.start, infer_env)
                source_unify_type(start_t, source_infer_expr_type(stmt.finish, infer_env), "for range")
                if stmt.step ~= nil then
                    source_unify_type(start_t, source_infer_expr_type(stmt.step, infer_env), "for step")
                end
                local loop_env = source_child_env(infer_env)
                source_bind_local(loop_env, stmt.name, nil, start_t, true)
                local nested = source_collect_result_candidates(stmt.body, loop_env, label)
                for j = 1, #nested do add_candidate(nested[j].t, nested[j].why) end
            end
        end

        for i = 1, last_i do infer_stmt(stmts[i], work_env) end
        if tail_expr ~= nil then
            add_candidate(source_infer_expr_type(tail_expr, work_env), "tail expression")
        end
        return candidates, tail_expr ~= nil, always_returns
    end

    local function source_infer_block_result_type(block_ast, env, label)
        local candidates, has_tail, always_returns = source_collect_result_candidates(block_ast, env, label)
        if not has_tail and not always_returns then
            error(("moonlift source %s does not produce a value; add a final expression or explicit return"):format(label), 2)
        end
        assert(#candidates > 0, ("moonlift source %s does not produce a value"):format(label))
        local result_t = nil
        for i = 1, #candidates do
            result_t = source_unify_type(result_t, candidates[i].t, label)
        end
        assert(result_t ~= types.void, ("moonlift source %s inferred void where a value is required"):format(label))
        return result_t
    end

    source_infer_function_result = function(func_ast, env, label)
        local candidates, has_tail, always_returns = source_collect_result_candidates(func_ast.body, env, label)
        local result_t = nil
        for i = 1, #candidates do
            result_t = source_unify_type(result_t, candidates[i].t, ("result type for %s"):format(label))
        end
        if not always_returns and not has_tail then
            if result_t ~= nil and source_prune_type(result_t) ~= types.void then
                error(("moonlift source %s has value returns but no final fallthrough value; add a final expression or explicit -> T"):format(label), 2)
            end
            return types.void
        end
        return source_prune_type(result_t) or types.void
    end

    source_infer_expr_type = function(ast, env)
        local tag = ast.tag
        if tag == "path" then
            return source_infer_path_type(ast, env)
        elseif tag == "number" then
            return ast.kind == "float" and types.f64 or types.i32
        elseif tag == "bool" then
            return types.bool
        elseif tag == "nil" then
            return types.void
        elseif tag == "string" then
            error("moonlift source cannot infer a Moonlift type from a raw string expression; add an explicit result type", 2)
        elseif tag == "aggregate" then
            if ast.ctor.tag == "array_ctor" then
                local elem_t = source_resolve_type(ast.ctor.elem, env)
                return make_array(elem_t, source_eval_const_integer(ast.ctor.len, env, "array constructor length"))
            end
            return source_resolve_type(ast.ctor, env)
        elseif tag == "cast" or tag == "trunc" or tag == "zext" or tag == "sext" or tag == "bitcast" then
            return source_resolve_type(ast.ty, env)
        elseif tag == "sizeof" or tag == "alignof" or tag == "offsetof" then
            return types.usize
        elseif tag == "load" then
            return source_resolve_type(ast.ty, env)
        elseif tag == "memcmp" then
            return types.i32
        elseif tag == "block" then
            return source_infer_block_result_type(ast, source_child_env(env), "block expression")
        elseif tag == "if" then
            local result_t = source_infer_expr_type(ast.else_value, source_child_env(env))
            for i = 1, #(ast.branches or {}) do
                local branch = ast.branches[i]
                source_unify_type(types.bool, source_infer_expr_type(branch.cond, env), "if condition")
                result_t = source_unify_type(result_t, source_infer_expr_type(branch.value, source_child_env(env)), "if expression")
            end
            return result_t
        elseif tag == "switch" then
            source_infer_expr_type(ast.value, env)
            local result_t = source_infer_expr_type(ast.default, source_child_env(env))
            for i = 1, #(ast.cases or {}) do
                local case = ast.cases[i]
                source_infer_expr_type(case.value, env)
                result_t = source_unify_type(result_t, source_infer_expr_type(case.body, source_child_env(env)), "switch expression")
            end
            return result_t
        elseif tag == "unary" then
            if ast.op == "not" then return types.bool end
            local inner_t = source_prune_type(source_infer_expr_type(ast.expr, env))
            if ast.op == "addr_of" then return make_ptr(inner_t) end
            if ast.op == "deref" then
                assert(inner_t ~= nil and inner_t.family == "ptr" and inner_t.elem ~= nil, "moonlift source '*' expects a pointer type")
                return inner_t.elem
            end
            return inner_t
        elseif tag == "binary" then
            local lhs_t = source_prune_type(source_infer_expr_type(ast.lhs, env))
            local rhs_t = source_prune_type(source_infer_expr_type(ast.rhs, env))
            if ast.op == "eq" or ast.op == "ne" or ast.op == "lt" or ast.op == "le" or ast.op == "gt" or ast.op == "ge"
                or ast.op == "and" or ast.op == "or" then
                if ast.op == "and" or ast.op == "or" then
                    source_unify_type(types.bool, lhs_t, ast.op)
                    source_unify_type(types.bool, rhs_t, ast.op)
                else
                    source_unify_type(lhs_t, rhs_t, ast.op)
                end
                return types.bool
            end
            return source_unify_type(lhs_t, rhs_t, ast.op)
        elseif tag == "field" then
            local base_t = source_infer_expr_type(ast.base, env)
            local field_t = source_member_type(base_t, ast.name, env)
            assert(field_t ~= nil, ("moonlift source cannot resolve field '%s' on type %s"):format(ast.name, source_type_name(base_t)))
            return field_t
        elseif tag == "index" then
            source_infer_expr_type(ast.index, env)
            return source_infer_index_type(source_infer_expr_type(ast.base, env))
        elseif tag == "call" then
            local direct = source_resolve_callable(ast.callee, env)
            if direct ~= nil then return source_prune_type(source_infer_info_result(direct, env)) end
            local callee_t = source_prune_type(source_infer_expr_type(ast.callee, env))
            assert(callee_t ~= nil and callee_t.family == "funcptr", "moonlift source call target is not callable")
            return source_prune_type(callee_t.result) or types.void
        elseif tag == "method_call" then
            local recv_t = source_prune_type(source_infer_expr_type(ast.receiver, env))
            local host_t = recv_t and recv_t.family == "ptr" and recv_t.elem or recv_t
            local method_bucket = host_t and env.method_infos[host_t.name] or nil
            local method = method_bucket and method_bucket[ast.method] or nil
            if method ~= nil then return source_prune_type(source_infer_info_result(method, env)) end
            local method_t = source_prune_type(source_member_type(recv_t, ast.method, env))
            assert(method_t ~= nil and method_t.family == "funcptr", "moonlift source method target is not callable")
            return source_prune_type(method_t.result) or types.void
        elseif tag == "splice" then
            local value = eval_host_source(ast.source, env.host_env, "=(moonlift.expr.splice.infer)")
            local value_t = source_infer_value_type(value, env)
            assert(value_t ~= nil, "moonlift source could not infer type of @{...}; add an explicit -> T or return a typed Moonlift value")
            return value_t
        elseif tag == "hole" then
            return source_resolve_type(ast.ty, env)
        elseif tag == "anonymous_func" then
            local params = source_lower_params(ast.func.sig.params, env)
            local anon_env = source_child_env(env)
            for i = 1, #params do source_bind_local(anon_env, params[i].name, nil, params[i].t, false) end
            local result_t = ast.func.sig.result and source_resolve_type(ast.func.sig.result, env)
                or source_require_resolved_type(source_infer_function_result(ast.func, anon_env, "anonymous func"), "anonymous func result")
            return make_source_func_type(params, result_t)
        end
        error("unsupported Moonlift source expr tag during inference: " .. tostring(tag), 2)
    end

    local function source_resolve_pending_results(env)
        for _, info in pairs(env.func_infos) do
            source_infer_info_result(info, env)
        end
        for _, bucket in pairs(env.method_infos) do
            for _, info in pairs(bucket) do
                source_infer_info_result(info, env)
            end
        end
    end

    source_resolve_path_value = function(ast, env)
        local segs = ast.segments
        local local_entry = env.locals[segs[1]]
        if local_entry ~= nil then
            local value = local_entry.value
            for i = 2, #segs do value = value[segs[i]] end
            return value
        end
        local value = env.values[segs[1]]
        if value ~= nil then
            for i = 2, #segs do value = value[segs[i]] end
            return value
        end
        value = env.types[segs[1]] or types[segs[1]]
        if value ~= nil then
            for i = 2, #segs do value = value[segs[i]] end
            return value
        end
        return nil
    end

    source_resolve_callable = function(ast, env)
        if ast.tag ~= "path" or #ast.segments ~= 1 then return nil end
        local name = ast.segments[1]
        return env.func_infos[name] or env.extern_infos[name]
    end

    local function direct_invoke_named(name, params, result_t, ...)
        local argc = select("#", ...)
        assert(argc == #params, ("moonlift direct invoke expected %d args, got %d"):format(#params, argc))
        local args = { ... }
        local lowered_args = {}
        local lowered_params = {}
        for i = 1, #params do
            local p = params[i]
            lowered_params[i] = lower_param(p)
            if is_layout_type(p.t) then
                lowered_args[i] = lower_call_arg(args[i], p.t)
            else
                lowered_args[i] = as_expr(args[i], p.t).node
            end
        end
        result_t = result_t or types.void
        local node = {
            tag = "call",
            callee_kind = "direct",
            name = name,
            params = lowered_params,
            result = lower_type_name(result_t),
            args = lowered_args,
            type = lower_type_name(result_t),
        }
        if is_void_type(result_t) then
            emit_stmt(node)
            return nil
        end
        return expr(node, result_t)
    end

    local function source_apply_unary(op, value)
        if op == "neg" then return -as_expr(value)
        elseif op == "not" then return as_expr(value, types.bool):not_()
        elseif op == "bnot" then return as_expr(value):bnot()
        elseif op == "addr_of" then
            local ptr = layout_ptr_of_value(value)
            assert(ptr ~= nil, "moonlift source '&' currently supports layout values/views only")
            return ptr
        elseif op == "deref" then
            local ptr = as_expr(value)
            local elem_t = assert(ptr.t and ptr.t.elem, "moonlift source '*' expects a pointer value")
            return load(elem_t, ptr)
        end
        error("unknown Moonlift unary op " .. tostring(op), 2)
    end

    local function source_apply_binary(op, lhs, rhs)
        if op == "add" then return lhs + rhs
        elseif op == "sub" then return lhs - rhs
        elseif op == "mul" then return lhs * rhs
        elseif op == "div" then return lhs / rhs
        elseif op == "rem" then return lhs % rhs
        elseif op == "eq" then return as_expr(lhs):eq(rhs)
        elseif op == "ne" then return as_expr(lhs):ne(rhs)
        elseif op == "lt" then return as_expr(lhs):lt(rhs)
        elseif op == "le" then return as_expr(lhs):le(rhs)
        elseif op == "gt" then return as_expr(lhs):gt(rhs)
        elseif op == "ge" then return as_expr(lhs):ge(rhs)
        elseif op == "and" then return as_expr(lhs, types.bool):and_(rhs)
        elseif op == "or" then return as_expr(lhs, types.bool):or_(rhs)
        elseif op == "band" then return as_expr(lhs):band(rhs)
        elseif op == "bor" then return as_expr(lhs):bor(rhs)
        elseif op == "bxor" then return as_expr(lhs):bxor(rhs)
        elseif op == "shl" then return as_expr(lhs):shl(rhs)
        elseif op == "shr" then return as_expr(lhs):shr_s(rhs)
        elseif op == "shr_u" then return as_expr(lhs):shr_u(rhs)
        end
        error("unknown Moonlift binary op " .. tostring(op), 2)
    end

    local function source_lower_branch_value(node, env)
        if type(node) == "table" and node.tag == "block" then
            return block(function()
                return source_lower_block_value(node, source_child_env(env), false)
            end)
        end
        return source_lower_expr(node, env)
    end

    source_block_contains_return = function(block_ast)
        for i = 1, #(block_ast.stmts or {}) do
            local stmt = block_ast.stmts[i]
            if stmt.tag == "return" then
                return true
            elseif stmt.tag == "if" then
                for j = 1, #(stmt.branches or {}) do
                    if source_block_contains_return(stmt.branches[j].body) then return true end
                end
                if stmt.else_body ~= nil and source_block_contains_return(stmt.else_body) then return true end
            elseif stmt.tag == "switch" then
                for j = 1, #(stmt.cases or {}) do
                    if source_block_contains_return(stmt.cases[j].body) then return true end
                end
                if stmt.default ~= nil and source_block_contains_return(stmt.default) then return true end
            elseif stmt.tag == "while" or stmt.tag == "for" then
                if source_block_contains_return(stmt.body) then return true end
            end
        end
        return false
    end

    local function source_stmt_always_returns(stmt)
        if stmt.tag == "return" then return true end
        if stmt.tag == "if" then
            if stmt.else_body == nil then return false end
            for i = 1, #(stmt.branches or {}) do
                if not source_block_always_returns(stmt.branches[i].body) then return false end
            end
            return source_block_always_returns(stmt.else_body)
        elseif stmt.tag == "switch" then
            if stmt.default == nil then return false end
            for i = 1, #(stmt.cases or {}) do
                if not source_block_always_returns(stmt.cases[i].body) then return false end
            end
            return source_block_always_returns(stmt.default)
        end
        return false
    end

    source_block_always_returns = function(block_ast)
        for i = 1, #(block_ast.stmts or {}) do
            if source_stmt_always_returns(block_ast.stmts[i]) then
                return true
            end
        end
        return false
    end

    local function source_lower_terminal_stmt_value(stmt, env)
        if stmt.tag == "return" then
            return stmt.value and source_lower_expr(stmt.value, env) or nil
        elseif stmt.tag == "if" then
            local function build_branch(i)
                local branch = stmt.branches[i]
                if branch == nil then
                    return source_lower_block_value(stmt.else_body, source_child_env(env), false)
                end
                return if_(
                    source_lower_expr(branch.cond, env),
                    function() return source_lower_block_value(branch.body, source_child_env(env), false) end,
                    function() return build_branch(i + 1) end
                )
            end
            return build_branch(1)
        elseif stmt.tag == "switch" then
            local cases = {}
            for i = 1, #(stmt.cases or {}) do
                local case = stmt.cases[i]
                cases[source_lower_expr(case.value, env)] = function()
                    return source_lower_block_value(case.body, source_child_env(env), false)
                end
            end
            return switch_(
                source_lower_expr(stmt.value, env),
                cases,
                function() return source_lower_block_value(stmt.default, source_child_env(env), false) end
            )
        elseif stmt.tag == "expr" then
            return source_lower_expr(stmt.expr, env)
        end
        error("moonlift source block cannot produce a value from statement tag " .. tostring(stmt.tag), 2)
    end

    local function source_set_target(target, value, env)
        if target.tag == "path" then
            local segs = target.segments
            local entry = env.locals[segs[1]]
            assert(entry ~= nil, ("moonlift assignment target '%s' must be a local binding"):format(segs[1]))
            if #segs == 1 then
                assert(entry.mutable, ("moonlift local '%s' is immutable"):format(segs[1]))
                entry.value:set(source_coerce_value(value, entry.t))
                return
            end
            local base = entry.value
            for i = 2, #segs - 1 do base = base[segs[i]] end
            base[segs[#segs]] = value
            return
        elseif target.tag == "field" then
            local base = source_lower_expr(target.base, env)
            base[target.name] = value
            return
        elseif target.tag == "index" then
            local base = source_lower_expr(target.base, env)
            local index = source_lower_expr(target.index, env)
            base[index] = value
            return
        elseif target.tag == "unary" and target.op == "deref" then
            local ptr = source_lower_expr(target.expr, env)
            local ptr_t = source_value_type(ptr)
            local elem_t = assert(ptr_t and ptr_t.elem, "moonlift '*' assignment expects a pointer")
            store(elem_t, ptr, value)
            return
        end
        error("unsupported Moonlift assignment target: " .. tostring(target.tag), 2)
    end

    local function source_lower_stmt_void(stmt, env, in_loop, void_function, return_state)
        if stmt.tag == "let" then
            local t = stmt.ty and source_resolve_type(stmt.ty, env) or nil
            local v = source_coerce_value(source_lower_expr(stmt.value, env), t)
            source_bind_local(env, stmt.name, bind_let(v), t, false)
            return false
        elseif stmt.tag == "var" then
            local t = stmt.ty and source_resolve_type(stmt.ty, env) or nil
            local v = source_coerce_value(source_lower_expr(stmt.value, env), t)
            source_bind_local(env, stmt.name, bind_var(v), t, true)
            return false
        elseif stmt.tag == "assign" then
            source_set_target(stmt.target, source_lower_expr(stmt.value, env), env)
            return false
        elseif stmt.tag == "expr" then
            source_emit_side_effect_expr(source_lower_expr(stmt.expr, env))
            return false
        elseif stmt.tag == "memcpy" then
            memcpy(source_lower_expr(stmt.dst, env), source_lower_expr(stmt.src, env), source_lower_expr(stmt.len, env))
            return false
        elseif stmt.tag == "memmove" then
            memmove(source_lower_expr(stmt.dst, env), source_lower_expr(stmt.src, env), source_lower_expr(stmt.len, env))
            return false
        elseif stmt.tag == "memset" then
            memset(source_lower_expr(stmt.dst, env), source_lower_expr(stmt.byte, env), source_lower_expr(stmt.len, env))
            return false
        elseif stmt.tag == "store" then
            store(source_resolve_type(stmt.ty, env), source_lower_expr(stmt.dst, env), source_lower_expr(stmt.value, env))
            return false
        elseif stmt.tag == "break" then
            break_()
            return true
        elseif stmt.tag == "continue" then
            continue_()
            return true
        elseif stmt.tag == "return" then
            if return_state ~= nil then
                return source_emit_return_stmt(stmt, env, in_loop, return_state)
            end
            assert(not in_loop, "moonlift source lowering does not yet support return inside loops")
            assert(void_function, "moonlift non-void source blocks must lower through value returns")
            assert(stmt.value == nil, "moonlift void function return must not return a value")
            return true
        elseif stmt.tag == "if" then
            local function build_branch(i)
                local branch = stmt.branches[i]
                if branch == nil then
                    return source_capture_lowered_block(stmt.else_body, source_child_env(env), in_loop, void_function, return_state)
                end
                return {
                    {
                        tag = "if",
                        cond = source_lower_expr(branch.cond, env).node,
                        then_body = source_capture_lowered_block(branch.body, source_child_env(env), in_loop, void_function, return_state),
                        else_body = build_branch(i + 1),
                    },
                }
            end
            local stmts = build_branch(1)
            for i = 1, #stmts do emit_stmt(stmts[i]) end
            return source_stmt_always_returns(stmt)
        elseif stmt.tag == "switch" then
            local switch_value = bind_let(as_expr(source_lower_expr(stmt.value, env)))
            local function build_case(i)
                local case = stmt.cases[i]
                if case == nil then
                    return source_capture_lowered_block(stmt.default, source_child_env(env), in_loop, void_function, return_state)
                end
                return {
                    {
                        tag = "if",
                        cond = switch_value:eq(source_lower_expr(case.value, env)).node,
                        then_body = source_capture_lowered_block(case.body, source_child_env(env), in_loop, void_function, return_state),
                        else_body = build_case(i + 1),
                    },
                }
            end
            local stmts = build_case(1)
            for i = 1, #stmts do emit_stmt(stmts[i]) end
            return source_stmt_always_returns(stmt)
        elseif stmt.tag == "while" then
            if return_state == nil then
                assert(not source_block_contains_return(stmt.body), "moonlift source lowering does not yet support return inside while bodies")
            end
            local cond = source_lower_expr(stmt.cond, env)
            if return_state ~= nil then
                cond = return_state.returned_ref:not_():and_(cond)
            end
            while_(cond, function()
                source_lower_block_void(stmt.body, source_child_env(env), true, void_function, return_state)
            end)
            return false
        elseif stmt.tag == "for" then
            if return_state == nil then
                assert(not source_block_contains_return(stmt.body), "moonlift source lowering does not yet support return inside for bodies")
            end
            local start_v = source_lower_expr(stmt.start, env)
            local finish_v = source_lower_expr(stmt.finish, env)
            local loop_ref = bind_var(start_v)
            local loop_t = source_value_type(loop_ref) or source_value_type(start_v) or types.i32
            local finish_e = source_coerce_value(finish_v, loop_t)
            local step_e = stmt.step and source_coerce_value(source_lower_expr(stmt.step, env), loop_t) or as_expr(1, loop_t)
            local cond = loop_ref:le(finish_e)
            if return_state ~= nil then
                cond = return_state.returned_ref:not_():and_(cond)
            end
            while_(cond, function()
                local body_env = source_child_env(env)
                source_bind_local(body_env, stmt.name, loop_ref, loop_t, true)
                source_lower_block_void(stmt.body, body_env, true, void_function, return_state)
                if return_state ~= nil then
                    emit_stmt {
                        tag = "if",
                        cond = return_state.returned_ref:not_().node,
                        then_body = capture_stmt_block(function()
                            loop_ref:set(loop_ref + step_e)
                        end),
                        else_body = {},
                    }
                else
                    loop_ref:set(loop_ref + step_e)
                end
            end)
            return false
        end
        error("unsupported Moonlift source statement tag: " .. tostring(stmt.tag), 2)
    end

    local function source_lower_stmt_range(stmts, first_i, last_i, env, in_loop, void_function, return_state)
        local i = first_i
        while i <= last_i do
            local stmt = stmts[i]
            local stop = source_lower_stmt_void(stmt, env, in_loop, void_function, return_state)
            if stop then return true end
            if return_state ~= nil and source_stmt_has_return(stmt) and i < last_i then
                emit_stmt {
                    tag = "if",
                    cond = return_state.returned_ref:not_().node,
                    then_body = capture_stmt_block(function()
                        source_lower_stmt_range(stmts, i + 1, last_i, env, in_loop, void_function, return_state)
                    end),
                    else_body = {},
                }
                return false
            end
            i = i + 1
        end
        return false
    end

    source_lower_block_void = function(block_ast, env, in_loop, void_function, return_state)
        return source_lower_stmt_range(block_ast.stmts or {}, 1, #(block_ast.stmts or {}), env, in_loop, void_function, return_state)
    end

    source_lower_block_value = function(block_ast, env, in_loop)
        for i = 1, #(block_ast.stmts or {}) do
            local stmt = block_ast.stmts[i]
            if stmt.tag == "return" or source_stmt_always_returns(stmt) or (stmt.tag == "expr" and i == #(block_ast.stmts or {})) then
                return source_lower_terminal_stmt_value(stmt, env)
            end
            local stop = source_lower_stmt_void(stmt, env, in_loop, false)
            if stop then
                error("moonlift source lowering hit unsupported control flow in value block", 2)
            end
        end
        error("moonlift source block does not produce a value", 2)
    end

    local function source_lower_function_body(func_ast, body_env, result_t)
        if result_t == nil then
            return source_lower_block_value(func_ast.body, body_env, false)
        end
        if is_void_type(result_t) then
            local return_state = source_make_return_state(result_t, true)
            source_lower_block_void(func_ast.body, body_env, false, true, return_state)
            return nil
        end

        local stmts = {}
        local body_stmts = func_ast.body.stmts or {}
        for i = 1, #body_stmts do stmts[i] = body_stmts[i] end
        if not source_block_always_returns(func_ast.body) then
            local tail_stmt = stmts[#stmts]
            if tail_stmt == nil or tail_stmt.tag ~= "expr" then
                error("moonlift source block does not produce a value", 2)
            end
            stmts[#stmts] = { tag = "return", value = tail_stmt.expr }
        end

        local return_state = source_make_return_state(result_t, false)
        source_lower_stmt_range(stmts, 1, #stmts, body_env, false, false, return_state)
        return return_state.result_ref
    end

    source_lower_expr = function(ast, env)
        local tag = ast.tag
        if tag == "path" then
            local value = source_resolve_path_value(ast, env)
            assert(value ~= nil, ("unknown Moonlift name '%s'"):format(path_last_segment(ast)))
            return value
        elseif tag == "number" then
            local n = assert(tonumber(ast.raw), "invalid Moonlift numeric literal: " .. tostring(ast.raw))
            if ast.kind == "float" then return types.f64(n) end
            return types.i32(n)
        elseif tag == "bool" then
            return types.bool(ast.value)
        elseif tag == "nil" then
            return nil
        elseif tag == "string" then
            return ast.value
        elseif tag == "aggregate" then
            local ctor
            if ast.ctor.tag == "array_ctor" then
                local elem_t = source_resolve_type(ast.ctor.elem, env)
                ctor = make_array(elem_t, source_eval_const_integer(ast.ctor.len, env, "array constructor length"))
            else
                ctor = source_resolve_type(ast.ctor, env)
            end
            local values = {}
            local all_named = true
            for i = 1, #(ast.fields or {}) do
                if ast.fields[i].tag ~= "named" then all_named = false break end
            end
            if all_named then
                for i = 1, #(ast.fields or {}) do
                    values[ast.fields[i].name] = source_lower_expr(ast.fields[i].value, env)
                end
            else
                for i = 1, #(ast.fields or {}) do
                    values[i] = source_lower_expr(ast.fields[i].value, env)
                end
            end
            return ctor(values)
        elseif tag == "cast" then
            return cast(source_resolve_type(ast.ty, env), source_lower_expr(ast.value, env))
        elseif tag == "trunc" then
            return trunc(source_resolve_type(ast.ty, env), source_lower_expr(ast.value, env))
        elseif tag == "zext" then
            return zext(source_resolve_type(ast.ty, env), source_lower_expr(ast.value, env))
        elseif tag == "sext" then
            return sext(source_resolve_type(ast.ty, env), source_lower_expr(ast.value, env))
        elseif tag == "bitcast" then
            return bitcast(source_resolve_type(ast.ty, env), source_lower_expr(ast.value, env))
        elseif tag == "sizeof" then
            return types.usize(type_size(source_resolve_type(ast.ty, env)))
        elseif tag == "alignof" then
            return types.usize(type_align(source_resolve_type(ast.ty, env)))
        elseif tag == "offsetof" then
            local T = source_resolve_type(ast.ty, env)
            local field = assert(T.field_lookup and T.field_lookup[ast.field], "unknown field for offsetof")
            return types.usize(field.offset)
        elseif tag == "load" then
            return load(source_resolve_type(ast.ty, env), source_lower_expr(ast.ptr, env))
        elseif tag == "memcmp" then
            return memcmp(source_lower_expr(ast.a, env), source_lower_expr(ast.b, env), source_lower_expr(ast.len, env))
        elseif tag == "block" then
            return block(function()
                return source_lower_block_value(ast, source_child_env(env), false)
            end)
        elseif tag == "if" then
            local function build_branch(i)
                local branch = ast.branches[i]
                if branch == nil then
                    return source_lower_branch_value(ast.else_value, source_child_env(env))
                end
                return if_(
                    source_lower_expr(branch.cond, env),
                    function() return source_lower_branch_value(branch.value, source_child_env(env)) end,
                    function() return build_branch(i + 1) end
                )
            end
            return build_branch(1)
        elseif tag == "switch" then
            local cases = {}
            for i = 1, #(ast.cases or {}) do
                local case = ast.cases[i]
                cases[source_lower_expr(case.value, env)] = function()
                    return source_lower_branch_value(case.body, source_child_env(env))
                end
            end
            return switch_(
                source_lower_expr(ast.value, env),
                cases,
                function() return source_lower_branch_value(ast.default, source_child_env(env)) end
            )
        elseif tag == "unary" then
            return source_apply_unary(ast.op, source_lower_expr(ast.expr, env))
        elseif tag == "binary" then
            return source_apply_binary(ast.op, source_lower_expr(ast.lhs, env), source_lower_expr(ast.rhs, env))
        elseif tag == "field" then
            local base = source_lower_expr(ast.base, env)
            return base[ast.name]
        elseif tag == "index" then
            local base = source_lower_expr(ast.base, env)
            return base[source_lower_expr(ast.index, env)]
        elseif tag == "call" then
            local direct = source_resolve_callable(ast.callee, env)
            local args = {}
            for i = 1, #(ast.args or {}) do args[i] = source_lower_expr(ast.args[i], env) end
            if direct ~= nil then
                return direct_invoke_named(direct.symbol or direct.name, direct.params, direct.result, unpack(args, 1, #args))
            end
            local callee = source_lower_expr(ast.callee, env)
            if type(callee) == "table" and getmetatable(callee) == FunctionMT then
                return callee(unpack(args, 1, #args))
            end
            error("moonlift source call target is not callable", 2)
        elseif tag == "method_call" then
            local receiver = source_lower_expr(ast.receiver, env)
            local recv_t = source_value_type(receiver)
            local method_bucket = recv_t and env.method_infos[recv_t.name] or nil
            local method = method_bucket and method_bucket[ast.method] or nil
            local args = {}
            for i = 1, #(ast.args or {}) do args[i] = source_lower_expr(ast.args[i], env) end
            if method ~= nil then
                return direct_invoke_named(method.symbol, method.params, method.result, receiver, unpack(args, 1, #args))
            end
            return receiver[ast.method](receiver, unpack(args, 1, #args))
        elseif tag == "splice" then
            return eval_host_source(ast.source, env.host_env, "=(moonlift.expr.splice)")
        elseif tag == "hole" then
            return hole(ast.name, source_resolve_type(ast.ty, env))
        elseif tag == "anonymous_func" then
            return source_lower_code_item(ast.func, env.host_env, env)
        end
        error("unsupported Moonlift source expr tag: " .. tostring(tag), 2)
    end

    local function source_lower_params(params_ast, env)
        local params = {}
        for i = 1, #(params_ast or {}) do
            params[i] = { name = params_ast[i].name, t = source_resolve_type(params_ast[i].ty, env) }
        end
        return params
    end

    local function source_make_function(func_ast, env, owner_module)
        local sig = func_ast.sig
        local name_info = sig.name
        assert(name_info.tag == "named", "moonlift source free functions must be named")
        local name = name_info.name
        local info = env.func_infos[name]
        local params = info and info.params or source_lower_params(sig.params, env)
        local result_t = info and info.result or (sig.result and source_resolve_type(sig.result, env) or nil)
        if result_t ~= nil then result_t = source_require_resolved_type(result_t, ("result type for %s"):format(name)) end
        local function body_fn(...)
            local body_env = source_child_env(env)
            local args = { ... }
            for i = 1, #params do
                source_bind_local(body_env, params[i].name, args[i], params[i].t, false)
            end
            return source_lower_function_body(func_ast, body_env, result_t)
        end
        local fn = build_function(name, params, result_t, body_fn)
        fn.__owner_module = owner_module
        return fn
    end

    local function source_make_method(target_t, method_name, func_ast, env, owner_module)
        local method_info = env.method_infos[target_t.name] and env.method_infos[target_t.name][method_name] or nil
        local params = method_info and method_info.params or source_lower_params(func_ast.sig.params, env)
        local result_t = method_info and method_info.result or (func_ast.sig.result and source_resolve_type(func_ast.sig.result, env) or nil)
        if result_t ~= nil then result_t = source_require_resolved_type(result_t, ("result type for %s.%s"):format(target_t.name, method_name)) end
        local symbol = target_t.name .. "_" .. method_name
        local function body_fn(...)
            local body_env = source_child_env(env)
            local args = { ... }
            for i = 1, #params do
                source_bind_local(body_env, params[i].name, args[i], params[i].t, false)
            end
            return source_lower_function_body(func_ast, body_env, result_t)
        end
        local fn = build_function(symbol, params, result_t, body_fn)
        rawget(target_t, "method_lookup")[method_name] = fn
        fn.__owner_module = owner_module
        return fn
    end

    local function source_register_type_item(item, env)
        local tag = item.tag
        if tag == "struct" then
            local fields = {}
            for i = 1, #(item.fields or {}) do
                fields[i] = { item.fields[i].name, source_resolve_type(item.fields[i].ty, env) }
            end
            local T = make_struct(item.name, fields)
            env.types[item.name] = T
            env.exports[item.name] = T
            return T
        elseif tag == "union" then
            local fields = {}
            for i = 1, #(item.fields or {}) do
                fields[i] = { item.fields[i].name, source_resolve_type(item.fields[i].ty, env) }
            end
            local T = make_union(item.name, fields)
            env.types[item.name] = T
            env.exports[item.name] = T
            return T
        elseif tag == "tagged_union" then
            local variants = {}
            for i = 1, #(item.variants or {}) do
                local v = item.variants[i]
                local fields = {}
                for j = 1, #(v.fields or {}) do
                    fields[j] = { v.fields[j].name, source_resolve_type(v.fields[j].ty, env) }
                end
                variants[v.name] = fields
            end
            local spec = { variants = variants }
            if item.base_ty ~= nil then spec.base = source_resolve_type(item.base_ty, env) end
            local T = make_tagged_union(item.name, spec)
            env.types[item.name] = T
            env.exports[item.name] = T
            return T
        elseif tag == "enum" then
            local items = {}
            local base_t = item.base_ty and source_resolve_type(item.base_ty, env) or types.u8
            local temp_enum = { name = item.name }
            local eval_env = source_child_env(env)
            eval_env.values = setmetatable({}, { __index = env.values })
            env.types[item.name] = temp_enum
            eval_env.types[item.name] = temp_enum
            for i = 1, #(item.members or {}) do
                local m = item.members[i]
                local value = m.value and source_eval_const_expr(m.value, eval_env) or (i - 1)
                value = source_const_cast_value(base_t, value)
                value = assert(tonumber(value), ("moonlift enum member '%s' must lower to a numeric constant"):format(m.name))
                items[m.name] = value
                temp_enum[m.name] = value
                eval_env.values[m.name] = value
            end
            local T = make_enum(item.name, base_t, items)
            env.types[item.name] = T
            env.exports[item.name] = T
            return T
        elseif tag == "opaque" then
            local T = new_type { name = item.name, family = "opaque" }
            env.types[item.name] = T
            env.exports[item.name] = T
            return T
        elseif tag == "slice_decl" then
            local T = make_slice(source_resolve_type(item.ty, env))
            env.types[item.name] = T
            env.exports[item.name] = T
            return T
        elseif tag == "type_alias" then
            local T = source_resolve_type(item.ty, env)
            env.types[item.name] = T
            env.exports[item.name] = T
            return T
        end
        return nil
    end

    local function source_predeclare_func(item, env)
        local func_ast = item.item or item
        local name = func_ast.sig.name.name
        env.func_infos[name] = {
            kind = "direct",
            name = name,
            label = name,
            symbol = name,
            ast = func_ast,
            params = source_lower_params(func_ast.sig.params, env),
            result = func_ast.sig.result and source_resolve_type(func_ast.sig.result, env) or nil,
        }
    end

    local function source_predeclare_extern(item, env)
        local link_name = source_attr_string(item, "link_name") or item.name
        env.extern_infos[item.name] = {
            kind = "direct",
            name = item.name,
            label = item.name,
            symbol = link_name,
            params = source_lower_params(item.params, env),
            result = item.result and source_resolve_type(item.result, env) or types.void,
        }
        env.exports[item.name] = env.extern_infos[item.name]
    end

    local function source_predeclare_const(item, env)
        env.const_infos[item.name] = {
            name = item.name,
            ty_ast = item.ty,
            value_ast = item.value,
        }
    end

    local function source_lower_const_item(item, env)
        local info = env.const_infos[item.name]
        local t = info and info.t or (item.ty and source_resolve_type(item.ty, env) or source_infer_expr_type(item.value, env))
        local ok, const_value = pcall(source_eval_const_expr, item.value, env)
        if ok then
            local runtime_value = source_const_runtime_value(t, const_value)
            if runtime_value ~= nil then
                if info ~= nil then info.t = source_prune_type(t) end
                return runtime_value
            end
        end
        local value = source_lower_expr(item.value, env)
        if info ~= nil and info.t == nil then
            info.t = source_infer_value_type(value, env)
        end
        return value
    end

    local function source_predeclare_impl(item, env)
        local target_t = source_resolve_type(item.target, env)
        local bucket = env.method_infos[target_t.name] or {}
        env.method_infos[target_t.name] = bucket
        for i = 1, #(item.items or {}) do
            local func_ast = item.items[i].item
            local method_name = func_ast.sig.name.name
            bucket[method_name] = {
                kind = "direct",
                name = method_name,
                label = target_t.name .. "." .. method_name,
                symbol = target_t.name .. "_" .. method_name,
                ast = func_ast,
                params = source_lower_params(func_ast.sig.params, env),
                result = func_ast.sig.result and source_resolve_type(func_ast.sig.result, env) or nil,
            }
        end
    end

    local function source_lower_module_ast(module_ast, host_env)
        local env = source_new_env(host_env)
        local funcs = {}

        for i = 1, #(module_ast.items or {}) do
            local item = unwrap_source_item(module_ast.items[i])
            source_register_type_item(item, env)
        end
        for i = 1, #(module_ast.items or {}) do
            local item = unwrap_source_item(module_ast.items[i])
            if item.tag == "extern_func" then
                source_predeclare_extern(item, env)
            elseif item.tag == "func" then
                source_predeclare_func(item, env)
            elseif item.tag == "const" then
                source_predeclare_const(item, env)
            elseif item.tag == "impl" then
                source_predeclare_impl(item, env)
            end
        end
        source_resolve_pending_results(env)
        for i = 1, #(module_ast.items or {}) do
            local item = unwrap_source_item(module_ast.items[i])
            if item.tag == "const" then
                env.values[item.name] = source_lower_const_item(item, env)
                env.exports[item.name] = env.values[item.name]
                local const_info = env.const_infos[item.name]
                if const_info ~= nil and const_info.t == nil then
                    const_info.t = source_infer_value_type(env.values[item.name], env)
                end
            end
        end

        for i = 1, #(module_ast.items or {}) do
            local item = unwrap_source_item(module_ast.items[i])
            if item.tag == "func" then
                local fn = source_make_function(item, env, nil)
                funcs[#funcs + 1] = fn
                env.values[fn.name] = fn
                env.exports[fn.name] = fn
            elseif item.tag == "impl" then
                local target_t = source_resolve_type(item.target, env)
                for j = 1, #(item.items or {}) do
                    local func_ast = item.items[j].item
                    local method_name = func_ast.sig.name.name
                    local fn = source_make_method(target_t, method_name, func_ast, env, nil)
                    funcs[#funcs + 1] = fn
                    env.exports[fn.name] = fn
                end
            end
        end

        local mod = module_ctor(funcs)
        mod.__needs_direct_compile = true
        mod.types = env.exports
        for k, v in pairs(env.exports) do mod[k] = v end
        for i = 1, #funcs do funcs[i].__owner_module = mod end
        return mod
    end

    source_lower_code_item = function(item_ast, host_env, env_override)
        local item = unwrap_source_item(item_ast)
        local env = env_override or source_new_env(host_env)
        if item.tag == "func" then
            source_predeclare_func(item, env)
            source_resolve_pending_results(env)
            local fn = source_make_function(item, env, nil)
            env.values[fn.name] = fn
            return fn
        elseif item.tag == "extern_func" then
            source_predeclare_extern(item, env)
            return env.extern_infos[item.name]
        elseif item.tag == "const" then
            source_predeclare_const(item, env)
            local value = source_lower_const_item(item, env)
            env.values[item.name] = value
            local const_info = env.const_infos[item.name]
            if const_info ~= nil and const_info.t == nil then
                const_info.t = source_infer_value_type(value, env)
            end
            return value
        else
            local T = source_register_type_item(item, env)
            if T ~= nil then return T end
        end
        error("moonlift source code item is not yet supported: " .. tostring(item.tag), 2)
    end

    local function source_lower_externs(items_ast, host_env)
        local env = source_new_env(host_env)
        local out = {}
        for i = 1, #(items_ast or {}) do
            local item = unwrap_source_item(items_ast[i])
            source_predeclare_extern(item, env)
            out[i] = env.extern_infos[item.name]
            out[item.name] = out[i]
        end
        if #out == 1 then return out[1] end
        return out
    end

    local parse_api = {
        try_code = function(source) return parse_backend_ast(backend.ast_code, source, "code") end,
        try_module = function(source) return parse_backend_ast(backend.ast_module, source, "module") end,
        try_expr = function(source) return parse_backend_ast(backend.ast_expr, source, "expr") end,
        try_type = function(source) return parse_backend_ast(backend.ast_type, source, "type") end,
        try_extern = function(source) return parse_backend_ast(backend.ast_extern, source, "extern") end,
        code = function(source)
            local out, err = parse_backend_ast(backend.ast_code, source, "code")
            assert(out ~= nil, err)
            return out
        end,
        module = function(source)
            local out, err = parse_backend_ast(backend.ast_module, source, "module")
            assert(out ~= nil, err)
            return out
        end,
        expr = function(source)
            local out, err = parse_backend_ast(backend.ast_expr, source, "expr")
            assert(out ~= nil, err)
            return out
        end,
        type = function(source)
            local out, err = parse_backend_ast(backend.ast_type, source, "type")
            assert(out ~= nil, err)
            return out
        end,
        extern = function(source)
            local out, err = parse_backend_ast(backend.ast_extern, source, "extern")
            assert(out ~= nil, err)
            return out
        end,
        dump_code = backend.parse_code,
        dump_module = backend.parse_module,
        dump_expr = backend.parse_expr,
        dump_type = backend.parse_type,
        dump_extern = backend.parse_extern,
        pretty = function(ast)
            return tostring(ast)
        end,
    }

    local function source_code(source, host_env)
        local native = try_native_source_code(source)
        if native ~= nil then return native end
        local ast, err = parse_api.try_code(source)
        assert(ast ~= nil, err)
        return source_lower_code_item(ast, host_env or caller_env(2))
    end

    local function source_module(source, host_env)
        local native = try_native_source_module(source)
        if native ~= nil then return native end
        local ast, err = parse_api.try_module(source)
        assert(ast ~= nil, err)
        return source_lower_module_ast(ast, host_env or caller_env(2))
    end

    local function source_expr(source, host_env)
        local ast, err = parse_api.try_expr(source)
        assert(ast ~= nil, err)
        local fn = build_function("__moonlift_expr", {}, nil, function()
            return source_lower_expr(ast, source_new_env(host_env or caller_env(2)))
        end)
        return fn.body
    end

    local function source_type(source, host_env)
        local ast, err = parse_api.try_type(source)
        assert(ast ~= nil, err)
        return source_resolve_type(ast, source_new_env(host_env or caller_env(2)))
    end

    local function looks_like_source_snippet(s)
        return s:find("%s") ~= nil or s:match("^@") ~= nil or s:match("^extern") ~= nil
    end

    local function source_extern(source, host_env)
        local ast, err = parse_api.try_extern(source)
        assert(ast ~= nil, err)
        return source_lower_externs(ast, host_env or caller_env(2))
    end

    local lower_api = {
        code = function(ast, host_env)
            return source_lower_code_item(clone_ast(ast), host_env or caller_env(2))
        end,
        module = function(ast, host_env)
            return source_lower_module_ast(clone_ast(ast), host_env or caller_env(2))
        end,
        expr = function(ast, host_env)
            return source_lower_expr(clone_ast(ast), source_new_env(host_env or caller_env(2)))
        end,
        type = function(ast, host_env)
            return source_resolve_type(clone_ast(ast), source_new_env(host_env or caller_env(2)))
        end,
        extern = function(ast, host_env)
            return source_lower_externs(clone_ast(ast), host_env or caller_env(2))
        end,
    }

    parse_api.clone = function(ast)
        return clone_ast(ast)
    end

    return {
        parse = parse_api,
        lower = lower_api,
        code = source_code,
        module = source_module,
        expr = source_expr,
        type = source_type,
        extern = source_extern,
        looks_like_source_snippet = looks_like_source_snippet,
        caller_env = caller_env,
    }
end
