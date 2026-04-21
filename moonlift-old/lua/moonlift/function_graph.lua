return function()
    local registry = setmetatable({}, { __mode = "v" })

    local function lowered_collect_direct_call_names(node, out)
        if type(node) ~= "table" then return end
        if node.tag == "call" and node.callee_kind == "direct" and type(node.name) == "string" then
            out[node.name] = true
        end
        for _, v in pairs(node) do
            if type(v) == "table" then
                if v.tag ~= nil then
                    lowered_collect_direct_call_names(v, out)
                else
                    for i = 1, #v do
                        lowered_collect_direct_call_names(v[i], out)
                    end
                end
            end
        end
    end

    local function collect_function_direct_closure(func, out, seen)
        if type(func) ~= "table" or seen[func.name] then return end
        seen[func.name] = true
        out[#out + 1] = func
        local lowered = rawget(func, "lowered")
        if type(lowered) == "table" and lowered.body ~= nil then
            local names = {}
            lowered_collect_direct_call_names(lowered.body, names)
            for name in pairs(names) do
                local dep = registry[name]
                if dep ~= nil then
                    collect_function_direct_closure(dep, out, seen)
                end
            end
        end
    end

    return {
        register = function(fn)
            registry[fn.name] = fn
        end,
        collect = function(fn)
            local out = {}
            collect_function_direct_closure(fn, out, {})
            return out
        end,
    }
end
