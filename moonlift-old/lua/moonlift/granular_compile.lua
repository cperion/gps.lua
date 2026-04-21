return function(ctx)
    local backend = assert(ctx.backend)
    local wrap_compiled_handle = assert(ctx.wrap_compiled_handle)
    local function_lowered_params = assert(ctx.function_lowered_params)
    local compile_function = assert(ctx.compile_function)

    local M = {}

    local function rewrite_indirect_module_calls(node, addr_to_func)
        if type(node) ~= "table" then return node end
        local tag = node.tag
        if tag == nil then
            local out = {}
            for i = 1, #node do out[i] = rewrite_indirect_module_calls(node[i], addr_to_func) end
            return out
        end
        if tag == "call"
            and node.callee_kind == "indirect"
            and node.packed == true
            and type(node.addr) == "table"
            and node.addr.tag == "ptr"
        then
            local target = addr_to_func[tostring(node.addr.value)]
            if target ~= nil then
                local out = {}
                for k, v in pairs(node) do
                    if k ~= "addr" and k ~= "packed" then
                        out[k] = rewrite_indirect_module_calls(v, addr_to_func)
                    end
                end
                out.callee_kind = "direct"
                out.name = target.name
                out.params = function_lowered_params(target)
                return out
            end
        end
        local out = {}
        for k, v in pairs(node) do
            out[k] = rewrite_indirect_module_calls(v, addr_to_func)
        end
        return out
    end

    function M.canonicalize_module(mod)
        local addr_to_func = {}
        for i = 1, #mod.funcs do
            local f = mod.funcs[i]
            local addr = rawget(f, "__code_addr")
            if type(addr) == "number" then
                addr_to_func[tostring(addr)] = f
            end
        end
        if next(addr_to_func) ~= nil then
            for i = 1, #mod.funcs do
                local f = mod.funcs[i]
                if type(f.lowered) == "table" and f.lowered.body ~= nil then
                    f.lowered = {
                        name = f.lowered.name,
                        params = f.lowered.params,
                        result = f.lowered.result,
                        body = rewrite_indirect_module_calls(f.lowered.body, addr_to_func),
                    }
                end
            end
        end
        mod.__compiled_granular = nil
        for i = 1, #mod.funcs do
            local f = mod.funcs[i]
            f.__compiled = nil
            f.__code_addr = nil
        end
    end

    local function bind_sparse_handles(mod, handles)
        local compiled_by_name = rawget(mod, "__compiled_granular") or {}
        for i = 1, #mod.funcs do
            local handle = handles[i]
            if type(handle) == "number" and handle > 0 then
                local f = mod.funcs[i]
                local existing = compiled_by_name[f.name]
                if existing == nil then
                    local cf = wrap_compiled_handle(f.name, #f.params, handle, function_lowered_params(f), f.result)
                    compiled_by_name[f.name] = cf
                    f.__compiled = cf
                    f.__code_addr = backend.addr(cf.handle)
                end
            end
        end
        mod.__compiled_granular = compiled_by_name
        return compiled_by_name
    end

    function M.compile_entry(mod, func, compile_full_module)
        local source_module = rawget(mod, "__source_module") or rawget(mod, "__native_source")
        local compiled_by_name = rawget(mod, "__compiled_granular")
        if compiled_by_name ~= nil and compiled_by_name[func.name] ~= nil then
            return compiled_by_name[func.name]
        end

        if source_module ~= nil then
            local source_host_env = rawget(mod, "__source_host_env")
            local handles, err = backend.compile_source_module_entry(source_module, func.name, source_host_env)
            assert(type(handles) == "table", err or "moonlift failed to compile source module entry closure")
            return bind_sparse_handles(mod, handles)[func.name]
        end

        local lowered = {}
        for i = 1, #mod.funcs do lowered[i] = mod.funcs[i].lowered end
        local handles, err = backend.compile_module_entry(lowered, func.name)
        if type(handles) == "table" then
            return bind_sparse_handles(mod, handles)[func.name]
        end
        if err ~= nil then
            error(err, 2)
        end
        return compile_full_module(mod)[func.name]
    end

    return M
end
