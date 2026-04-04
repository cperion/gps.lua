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
local Quote = require("quote")

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
    local source

    local function build_call_fn()
        local q = Quote()
        local _stats = q:val(stats, "stats")
        local _cache = q:val(cache, "cache")
        local _str_cache = q:val(str_cache, "str_cache")
        local _fn = q:val(fn, "fn")
        local _type = q:val(type, "type")

        q("return function(input)")
        q("  %s.calls = %s.calls + 1", _stats, _stats)

        if input_type == "table" then
            q("  local hit = %s[input]", _cache)
            q("  if hit ~= nil then %s.hits = %s.hits + 1; return hit end", _stats, _stats)
            q("  local result = %s(input)", _fn)
            q("  %s[input] = result", _cache)
            q("  return result")
        elseif input_type == "string" then
            q("  local hit = %s[input]", _str_cache)
            q("  if hit ~= nil then %s.hits = %s.hits + 1; return hit end", _stats, _stats)
            q("  local result = %s(input)", _fn)
            q("  %s[input] = result", _str_cache)
            q("  return result")
        else
            q("  local tp = %s(input)", _type)
            q("  if tp == \"table\" then")
            q("    local hit = %s[input]", _cache)
            q("    if hit ~= nil then %s.hits = %s.hits + 1; return hit end", _stats, _stats)
            q("  elseif tp == \"string\" then")
            q("    local hit = %s[input]", _str_cache)
            q("    if hit ~= nil then %s.hits = %s.hits + 1; return hit end", _stats, _stats)
            q("  end")
            q("  local result = %s(input)", _fn)
            q("  if tp == \"table\" then %s[input] = result", _cache)
            q("  elseif tp == \"string\" then %s[input] = result end", _str_cache)
            q("  return result")
        end

        q("end")
        local compiled, src = q:compile("=(pvm.lower." .. name .. ")")
        source = src
        return compiled
    end

    local call_fn = build_call_fn()

    local self = {}
    self.__call = function(_, input) return call_fn(input) end
    self.source = source
    function self:stats() return stats end
    function self:reset()
        cache = setmetatable({}, { __mode = "k" })
        str_cache = {}
        stats.calls = 0; stats.hits = 0
        call_fn = build_call_fn()
        self.__call = function(_, input) return call_fn(input) end
        self.source = source
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
    local source

    local classes = {}
    local handler_fns = {}
    for class, fn in pairs(handlers) do
        classes[#classes+1] = class
        handler_fns[#handler_fns+1] = fn
    end

    local function build_dispatch()
        local q = Quote()
        local _stats = q:val(stats, "stats")
        local _node_cache = q:val(node_cache, "node_cache")
        local _getmetatable = q:val(getmetatable, "getmetatable")
        local _tostring = q:val(tostring, "tostring")
        local _type = q:val(type, "type")
        local _error = q:val(error, "error")
        local class_names, handler_names = {}, {}
        for i = 1, #classes do
            class_names[i] = q:val(classes[i], "class_" .. i)
            handler_names[i] = q:val(handler_fns[i], "handler_" .. i)
        end

        if cache_enabled then
            q("return function(node)")
            q("  %s.calls = %s.calls + 1", _stats, _stats)
            q("  local hit = %s[node]", _node_cache)
            q("  if hit ~= nil then %s.hits = %s.hits + 1; return hit end", _stats, _stats)
            q("  local mt = %s(node)", _getmetatable)
            q("  local result")
            for i = 1, #classes do
                local kw = (i == 1) and "if" or "elseif"
                q("  %s mt == %s then result = %s(node)", kw, class_names[i], handler_names[i])
            end
            q("  else %s('pvm.verb %q: no handler for ' .. %s(mt and mt.kind or %s(node)), 2)", _error, name, _tostring, _type)
            q("  end")
            q("  %s[node] = result", _node_cache)
            q("  return result")
            q("end")
        else
            q("return function(node, ...)")
            q("  %s.calls = %s.calls + 1", _stats, _stats)
            q("  local mt = %s(node)", _getmetatable)
            for i = 1, #classes do
                local kw = (i == 1) and "if" or "elseif"
                q("  %s mt == %s then return %s(node, ...)", kw, class_names[i], handler_names[i])
            end
            q("  else %s('pvm.verb %q: no handler for ' .. %s(mt and mt.kind or %s(node)), 2)", _error, name, _tostring, _type)
            q("  end")
            q("end")
        end

        local compiled, src = q:compile("=(pvm.verb." .. name .. ")")
        source = src
        return compiled
    end

    local dispatch = build_dispatch()

    for i = 1, #classes do
        rawset(classes[i], name, function(self, ...)
            return dispatch(self, ...)
        end)
    end

    local boundary = {}
    boundary.__call = function(_, node, ...) return dispatch(node, ...) end
    boundary.source = source
    function boundary:stats() return stats end
    function boundary:reset()
        node_cache = cache_enabled and setmetatable({}, { __mode = "k" }) or nil
        stats.calls = 0; stats.hits = 0
        dispatch = build_dispatch()
        boundary.__call = function(_, node, ...) return dispatch(node, ...) end
        boundary.source = source
        for i = 1, #classes do
            rawset(classes[i], name, function(self, ...) return dispatch(self, ...) end)
        end
    end

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
