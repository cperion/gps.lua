-- pvm.lua — pico VM
--
-- Canonical implementation: code-generated constructors, lowerings, and verbs.
--
-- Philosophy:
--   * use interned ASDL nodes for immutable authored structure
--   * use lower() memo boundaries to skip unchanged work
--   * use iterators to avoid unnecessary materialization
--   * use codegen to present LuaJIT with the tightest possible hot shape
--
-- API:
--   pvm.context()             → ASDL context (with code-generated constructors)
--   pvm.with(node, overrides) → structural update (re-interns)
--   pvm.lower(name, fn, opts) → code-generated memoized boundary
--   pvm.verb(name, handlers, opts) → code-generated dispatch + cache
--   pvm.pipe(source, ...)     → compose value and iterator stages
--   pvm.collect/fold/each/count/report

local pvm = {}
local unpack = table.unpack or unpack

-- ══════════════════════════════════════════════════════════════
--  CODEGEN HELPER
-- ══════════════════════════════════════════════════════════════

local function compile_chunk(src, env, chunkname)
    local fn, err
    if loadstring then
        fn, err = loadstring(src, chunkname)
        if not fn then error(err, 2) end
        if setfenv then setfenv(fn, env) end
    else
        fn, err = load(src, chunkname, "t", env)
        if not fn then error(err, 2) end
    end
    return fn()
end

-- ══════════════════════════════════════════════════════════════
--  ASDL
-- ══════════════════════════════════════════════════════════════

local function get_asdl()
    if not package.preload["gps.asdl_lexer"] then
        package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    end
    if not package.preload["gps.asdl_parser"] then
        package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    end
    if not package.preload["gps.asdl_context"] then
        package.preload["gps.asdl_context"] = function() return require("asdl_context") end
    end
    return require("gps.asdl_context")
end

function pvm.context()
    local ctx = get_asdl().NewContext({ codegen_constructors = true })
    local orig = ctx.Define
    function ctx:Define(text) orig(self, text); return self end
    return ctx
end

function pvm.with(node, overrides)
    local mt = getmetatable(node)
    if not mt or not mt.__fields then error("pvm.with: not an ASDL node", 2) end
    local fields = mt.__fields
    local args = {}
    for i = 1, #fields do
        local name = fields[i].name
        args[i] = overrides[name] ~= nil and overrides[name] or node[name]
    end
    return mt(unpack(args, 1, #fields))
end

-- ══════════════════════════════════════════════════════════════
--  LOWER — code-generated memoized boundary
--
--  opts.input = "table" | "string" | "any" (default: "any")
--    Specializes the cache lookup. "table" = weak-key only.
--    "string" = string hash only. "any" = both (generic).
-- ══════════════════════════════════════════════════════════════

function pvm.lower(name, fn, opts)
    if type(name) == "function" and fn == nil then
        fn = name; name = "lower"
    end
    opts = opts or {}

    local input_type = opts.input or "any"
    local cache = setmetatable({}, { __mode = "k" })
    local str_cache = {}
    local stats = { name = name, calls = 0, hits = 0 }

    local src = {}
    src[#src+1] = "return function(input)"
    src[#src+1] = "  stats.calls = stats.calls + 1"

    if input_type == "table" then
        -- Specialized: input is always an ASDL node (table)
        src[#src+1] = "  local hit = cache[input]"
        src[#src+1] = "  if hit ~= nil then stats.hits = stats.hits + 1; return hit end"
        src[#src+1] = "  local result = fn(input)"
        src[#src+1] = "  cache[input] = result"
        src[#src+1] = "  return result"
    elseif input_type == "string" then
        -- Specialized: input is always a string
        src[#src+1] = "  local hit = str_cache[input]"
        src[#src+1] = "  if hit ~= nil then stats.hits = stats.hits + 1; return hit end"
        src[#src+1] = "  local result = fn(input)"
        src[#src+1] = "  str_cache[input] = result"
        src[#src+1] = "  return result"
    else
        -- Generic: handle both table and string
        src[#src+1] = "  local tp = type(input)"
        src[#src+1] = '  if tp == "table" then'
        src[#src+1] = "    local hit = cache[input]"
        src[#src+1] = "    if hit ~= nil then stats.hits = stats.hits + 1; return hit end"
        src[#src+1] = '  elseif tp == "string" then'
        src[#src+1] = "    local hit = str_cache[input]"
        src[#src+1] = "    if hit ~= nil then stats.hits = stats.hits + 1; return hit end"
        src[#src+1] = "  end"
        src[#src+1] = "  local result = fn(input)"
        src[#src+1] = '  if tp == "table" then cache[input] = result'
        src[#src+1] = '  elseif tp == "string" then str_cache[input] = result end'
        src[#src+1] = "  return result"
    end

    src[#src+1] = "end"

    local call_fn = compile_chunk(
        table.concat(src, "\n"),
        { fn = fn, cache = cache, str_cache = str_cache, stats = stats, type = type },
        "=(pvm.lower." .. name .. ")"
    )

    local self = {}
    self.__call = function(_, input) return call_fn(input) end
    function self:stats() return stats end
    function self:reset()
        cache = setmetatable({}, { __mode = "k" }); str_cache = {}
        stats.calls = 0; stats.hits = 0
        -- regenerate with fresh caches
        local env = { fn = fn, cache = cache, str_cache = str_cache, stats = stats, type = type }
        call_fn = compile_chunk(table.concat(src, "\n"), env, "=(pvm.lower." .. name .. ")")
        self.__call = function(_, input) return call_fn(input) end
    end

    return setmetatable(self, self)
end

-- ══════════════════════════════════════════════════════════════
--  VERB — code-generated dispatch + cache
--
--  Generates an if/elseif chain on metatable identity.
--  Handlers are upvalues. No table lookup at runtime.
--  Cache is per-node weak-key, specialized for 0-arg (most common).
-- ══════════════════════════════════════════════════════════════

function pvm.verb(name, handlers, opts)
    opts = opts or {}
    if type(handlers) ~= "table" then error("pvm.verb: handlers must be a table", 2) end

    local normalized = {}
    for key, fn in pairs(handlers) do
        local class = key
        if type(key) == "table" and rawget(key, "__fields") == nil and rawget(key, "members") == nil then
            local mt = getmetatable(key)
            if type(mt) == "table" then class = mt end
        end
        normalized[class] = fn
    end
    handlers = normalized

    local cache_enabled = not not opts.cache
    local node_cache = cache_enabled and setmetatable({}, { __mode = "k" }) or nil
    local stats = { name = opts.name or ("verb:" .. tostring(name)), calls = 0, hits = 0 }

    -- Collect handler classes and assign indices
    local classes = {}
    local handler_fns = {}
    for class, fn in pairs(handlers) do
        classes[#classes+1] = class
        handler_fns[#handler_fns+1] = fn
    end

    -- Generate dispatch function
    local src = {}

    if cache_enabled then
        -- Cached verb, 0 extra args (most common case)
        src[#src+1] = "return function(node)"
        src[#src+1] = "  stats.calls = stats.calls + 1"
        src[#src+1] = "  local hit = node_cache[node]"
        src[#src+1] = "  if hit ~= nil then stats.hits = stats.hits + 1; return hit end"
        src[#src+1] = "  local mt = getmetatable(node)"
        src[#src+1] = "  local result"
        for i = 1, #classes do
            local kw = (i == 1) and "if" or "elseif"
            src[#src+1] = string.format("  %s mt == C_%d then result = H_%d(node)", kw, i, i)
        end
        src[#src+1] = "  else error('pvm.verb \"" .. name .. "\": no handler for ' .. tostring(mt and mt.kind or type(node)), 2)"
        src[#src+1] = "  end"
        src[#src+1] = "  node_cache[node] = result"
        src[#src+1] = "  return result"
        src[#src+1] = "end"
    else
        -- Uncached verb with varargs
        src[#src+1] = "return function(node, ...)"
        src[#src+1] = "  stats.calls = stats.calls + 1"
        src[#src+1] = "  local mt = getmetatable(node)"
        for i = 1, #classes do
            local kw = (i == 1) and "if" or "elseif"
            src[#src+1] = string.format("  %s mt == C_%d then return H_%d(node, ...)", kw, i, i)
        end
        src[#src+1] = "  else error('pvm.verb \"" .. name .. "\": no handler for ' .. tostring(mt and mt.kind or type(node)), 2)"
        src[#src+1] = "  end"
        src[#src+1] = "end"
    end

    local env = {
        getmetatable = getmetatable,
        tostring = tostring,
        type = type,
        error = error,
        stats = stats,
        node_cache = node_cache,
    }
    for i = 1, #classes do
        env["C_" .. i] = classes[i]
        env["H_" .. i] = handler_fns[i]
    end

    local dispatch = compile_chunk(
        table.concat(src, "\n"),
        env,
        "=(pvm.verb." .. name .. ")"
    )

    -- Install :name() method on each type class
    for i = 1, #classes do
        rawset(classes[i], name, function(self, ...)
            return dispatch(self, ...)
        end)
    end

    local boundary = {}
    boundary.__call = function(_, node, ...) return dispatch(node, ...) end
    function boundary:stats() return stats end
    function boundary:reset()
        node_cache = cache_enabled and setmetatable({}, { __mode = "k" }) or nil
        stats.calls = 0; stats.hits = 0
        env.node_cache = node_cache
        env.stats = stats
        dispatch = compile_chunk(table.concat(src, "\n"), env, "=(pvm.verb." .. name .. ")")
        boundary.__call = function(_, node, ...) return dispatch(node, ...) end
        for i = 1, #classes do
            rawset(classes[i], name, function(self, ...) return dispatch(self, ...) end)
        end
    end

    -- Store generated source for inspection
    boundary.source = table.concat(src, "\n")

    return setmetatable(boundary, boundary)
end

-- ══════════════════════════════════════════════════════════════
--  PIPE — compose value stages and iterator stages into one factory
-- ══════════════════════════════════════════════════════════════
--
-- A stage may be:
--   * value -> value
--   * value -> gen,param,state
--   * gen,param,state -> gen,param,state
--
-- Once a stage returns an iterator triple, the remaining stages are
-- called in iterator mode.

function pvm.pipe(...)
    local stages = { ... }
    local n = #stages
    if n == 0 then error("pvm.pipe: expected at least one stage", 2) end

    local names = {}
    for i = 1, n do
        local stage = stages[i]
        names[i] = type(stage) == "table" and (stage.name or tostring(stage)) or tostring(stage)
    end
    local pipe_name = table.concat(names, " → ")
    local stats = { name = pipe_name, calls = 0, hits = 0 }
    local self = { name = pipe_name, stages = stages }

    function self:__call(input, ...)
        stats.calls = stats.calls + 1
        local a, b, c = stages[1](input, ...)
        local iterator_mode = type(a) == "function"
        for i = 2, n do
            if iterator_mode then
                a, b, c = stages[i](a, b, c)
            else
                a, b, c = stages[i](a)
                iterator_mode = type(a) == "function"
            end
        end
        return a, b, c
    end

    function self:stats() return stats end
    function self:all_stats()
        local out = {}
        for i = 1, n do
            local stage = stages[i]
            if type(stage) == "table" and type(stage.stats) == "function" then
                out[i] = stage:stats()
            else
                out[i] = {
                    name = type(stage) == "table" and (stage.name or tostring(stage)) or tostring(stage),
                    calls = 0,
                    hits = 0,
                }
            end
        end
        return out
    end

    return setmetatable(self, self)
end

-- ══════════════════════════════════════════════════════════════
--  ITERATOR TERMINALS
-- ══════════════════════════════════════════════════════════════

function pvm.collect(gen, param, state)
    local out, n = {}, 0
    while true do
        local val; state, val = gen(param, state)
        if state == nil then return out end
        n = n + 1; out[n] = val
    end
end

function pvm.fold(gen, param, state, step, acc)
    while true do
        local val; state, val = gen(param, state)
        if state == nil then return acc end
        acc = step(acc, val)
    end
end

function pvm.count(gen, param, state)
    local n = 0
    while true do
        state = gen(param, state)
        if state == nil then return n end
        n = n + 1
    end
end

function pvm.each(gen, param, state, fn)
    while true do
        local val; state, val = gen(param, state)
        if state == nil then return end
        fn(val)
    end
end

-- ══════════════════════════════════════════════════════════════
--  REPORT
-- ══════════════════════════════════════════════════════════════

function pvm.report(items)
    local lines = {}
    for i = 1, #items do
        local s = type(items[i].stats) == "function" and items[i]:stats() or items[i]
        local rate = s.calls > 0 and math.floor((s.hits or 0) / s.calls * 100) or 0
        lines[#lines + 1] = string.format("  %-30s calls=%-6d hits=%-6d rate=%d%%",
            s.name, s.calls, s.hits or 0, rate)
    end
    return table.concat(lines, "\n")
end

return pvm
