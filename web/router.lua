local M = {}

local function normalize_path(path)
    path = tostring(path or "/")
    local q = path:find("?", 1, true)
    if q then
        path = path:sub(1, q - 1)
    end
    if path == "" then
        return "/"
    end
    if path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end
    if #path > 1 and path:sub(-1) == "/" then
        path = path:sub(1, -2)
    end
    return path
end

local function split_path(path)
    path = normalize_path(path)
    if path == "/" then
        return {}
    end
    local out, n = {}, 0
    for seg in path:gmatch("[^/]+") do
        n = n + 1
        out[n] = seg
    end
    return out
end

local function compile_one(spec)
    if type(spec) ~= "table" then
        error("web.router.compile: route spec must be a table", 2)
    end
    if spec.build == nil then
        error("web.router.compile: route spec is missing build(req, state, params, loaded)", 2)
    end

    local parts = split_path(spec.path or "/")
    local compiled = {
        method = string.upper(tostring(spec.method or "GET")),
        path = normalize_path(spec.path or "/"),
        load = spec.load,
        build = spec.build,
        parts = parts,
    }

    return compiled
end

local function match_parts(parts, path_parts)
    if #parts ~= #path_parts then
        return nil
    end
    local params = {}
    for i = 1, #parts do
        local want = parts[i]
        local have = path_parts[i]
        if want:sub(1, 1) == ":" then
            params[want:sub(2)] = have
        elseif want ~= have then
            return nil
        end
    end
    return params
end

function M.compile(specs)
    local routes, n = {}, 0
    for i = 1, #specs do
        n = n + 1
        routes[n] = compile_one(specs[i])
    end

    return function(method, path)
        local m = string.upper(tostring(method or "GET"))
        local path_parts = split_path(path)
        local normalized = normalize_path(path)

        for i = 1, #routes do
            local route = routes[i]
            if route.method == m then
                local params = match_parts(route.parts, path_parts)
                if params ~= nil then
                    params._path = normalized
                    return route, params
                end
            end
        end

        return nil, nil
    end
end

M.normalize_path = normalize_path
M.split_path = split_path

return M
