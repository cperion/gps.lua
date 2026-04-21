return function(ctx)
    local backend = assert(ctx.backend)
    local code = ctx.code

    local M = {}

    local function normalize_disasm(text)
        assert(type(text) == "string", "moonlift.debug.normalize_disasm expects a string")
        text = text:gsub("function%s+u%d+:%d+", "function <fn>")
        text = text:gsub("moonlift_dbg_%d+_", "moonlift_dbg_<id>_")
        text = text:gsub("moonlift_fn_%d+_", "moonlift_fn_<id>_")
        return text
    end

    local function normalize_spec(text)
        assert(type(text) == "string", "moonlift.debug.normalize_spec expects a string")
        return text
    end

    function M.normalize_disasm(text)
        return normalize_disasm(text)
    end

    function M.normalize_spec(text)
        return normalize_spec(text)
    end

    function M.dump_disasm(lowered)
        return assert(backend.dump_disasm(lowered))
    end

    function M.dump_raw_disasm(lowered)
        return assert(backend.dump_unoptimized_disasm(lowered))
    end

    function M.dump_source_code_disasm(source, env)
        return assert(backend.dump_source_code_disasm(source, env))
    end

    function M.dump_raw_source_code_disasm(source, env)
        return assert(backend.dump_unoptimized_source_code_disasm(source, env))
    end

    function M.dump_optimized_spec(lowered)
        return assert(backend.dump_optimized_spec(lowered))
    end

    function M.dump_optimized_source_code_spec(source, env)
        return assert(backend.dump_optimized_source_code_spec(source, env))
    end

    function M.compare_disasm(a, b)
        local na = normalize_disasm(a)
        local nb = normalize_disasm(b)
        return {
            same = na == nb,
            lhs = a,
            rhs = b,
            lhs_normalized = na,
            rhs_normalized = nb,
        }
    end

    function M.compare_spec(a, b)
        local na = normalize_spec(a)
        local nb = normalize_spec(b)
        return {
            same = na == nb,
            lhs = a,
            rhs = b,
            lhs_normalized = na,
            rhs_normalized = nb,
        }
    end

    local function resolve_source_lowered(source)
        if code == nil then return nil end
        local lowered = code(source)
        if type(lowered) == "table" and lowered.lowered ~= nil then
            return lowered.lowered
        end
        return nil
    end

    function M.compare_source_builder(source, lowered)
        local source_spec, spec_err = backend.dump_optimized_source_code_spec(source)
        local source_disasm, disasm_err = backend.dump_source_code_disasm(source)
        if source_spec == nil or source_disasm == nil then
            local source_lowered = assert(resolve_source_lowered(source), spec_err or disasm_err or "moonlift.debug could not lower source for comparison")
            source_spec = M.dump_optimized_spec(source_lowered)
            source_disasm = M.dump_disasm(source_lowered)
        end
        local builder_spec = M.dump_optimized_spec(lowered)
        local builder_disasm = M.dump_disasm(lowered)
        return {
            spec = M.compare_spec(source_spec, builder_spec),
            disasm = M.compare_disasm(source_disasm, builder_disasm),
            source_spec = source_spec,
            builder_spec = builder_spec,
            source_disasm = source_disasm,
            builder_disasm = builder_disasm,
        }
    end

    return M
end
