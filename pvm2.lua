-- pvm2.lua — the triangle: Quote × ASDL × Triplet
--
-- One system, three primitives, fully composable with each other.
-- Quote generates triplet code. ASDL drives codegen.
-- Triplets carry ASDL nodes. The triangle closes.
--
-- ── Foundation ──────────────────────────────────────────────
--   pvm2.context()                ASDL type system (interned, immutable)
--   pvm2.with(node, overrides)    structural update preserving sharing
--   pvm2.lower(name, fn, opts)    identity-cached function boundary
--   pvm2.report(items)            cache behavior diagnostics
--   pvm2.T                        the triplet algebra module
--
-- ── Dispatch ────────────────────────────────────────────────
--   pvm2.verb_memo(name, handlers, opts?)
--       cached dispatch → flat sequences
--       opts.flat = true  → flat-array recursive handlers
--       opts.args = true  → arg-aware memoization for triplet handlers
--   pvm2.verb_iter(name, handlers)   uncached dispatch → lazy triplets
--   pvm2.verb_flat(name, handlers)   direct array-append specialization
--
-- ── Traversal ───────────────────────────────────────────────
--   pvm2.walk(root, defs)            generic ASDL DFS iterator
--   pvm2.walk_gen(sum_type, defs)    code-generated specialized walker
--
-- ── Pipeline ────────────────────────────────────────────────
--   pvm2.pipe(name?, stages...)      code-generated straight-line pipe
--   pvm2.pipe_typed(name, stages)    fully specialized pipe (zero checks)
--   pvm2.fuse_maps(name, stages)     code-generated map+filter chain
--   pvm2.fuse_pipeline(...)          baked source + fused transforms
--
-- ── Array iteration ─────────────────────────────────────────
--   pvm2.cmds(array, n?)             forward triplet
--   pvm2.cmds_rev(array, n?)         reverse triplet
--
-- ── Composition ─────────────────────────────────────────────
--   pvm2.concat_all(trips)           N-way triplet concatenation

local _pvm = require("pvm")
local Triplet = require("triplet")
local Quote = require("quote")

local pvm2 = {}
local getmetatable = getmetatable
local type = type
local rawset = rawset
local select = select

local function stage_name(stage)
    if type(stage) == "table" then
        return stage.name or tostring(stage)
    end
    return tostring(stage)
end

-- ══════════════════════════════════════════════════════════════
--  FOUNDATION — from pvm, unchanged
-- ══════════════════════════════════════════════════════════════

pvm2.context = _pvm.context
pvm2.with    = _pvm.with
pvm2.lower   = _pvm.lower
pvm2.report  = _pvm.report
pvm2.T       = Triplet

-- ══════════════════════════════════════════════════════════════
--  CODEGEN PIPE
--
--  Replaces pvm.pipe's runtime loop with Quote-generated
--  straight-line code. Each stage is a direct function call
--  in the generated source — no loop, no table lookup.
-- ══════════════════════════════════════════════════════════════

function pvm2.pipe(...)
    local args = { ... }
    local name, stages
    if type(args[1]) == "string" then
        name = args[1]
        stages = {}
        for i = 2, #args do stages[#stages + 1] = args[i] end
    else
        stages = args
        local names = {}
        for i = 1, #stages do
            names[i] = stage_name(stages[i])
        end
        name = table.concat(names, " → ")
    end
    local n = #stages
    if n == 0 then error("pvm2.pipe: expected at least one stage", 2) end

    local stats = { name = name, calls = 0, hits = 0 }
    local source

    local function build()
        local q = Quote()
        local _stats = q:val(stats, "stats")
        local _type  = q:val(type, "type")
        local refs = {}
        for i = 1, n do
            refs[i] = q:val(stages[i], "stage_" .. i)
        end

        q("return function(input, ...)")
        q("  %s.calls = %s.calls + 1", _stats, _stats)
        q("  local a, b, c = %s(input, ...)", refs[1])
        for i = 2, n do
            q("  if %s(a) == 'function' then", _type)
            q("    a, b, c = %s(a, b, c)", refs[i])
            q("  else")
            q("    a, b, c = %s(a)", refs[i])
            q("  end")
        end
        q("  return a, b, c")
        q("end")

        local compiled, src = q:compile("=(pvm2.pipe." .. name .. ")")
        source = src
        return compiled
    end

    local call_fn = build()
    local self = {}
    self.name = name
    self.source = source
    self.stages = stages
    self.__call = function(_, ...) return call_fn(...) end
    function self:stats() return stats end
    function self:all_stats()
        local out = {}
        for i = 1, n do
            local stage = stages[i]
            if type(stage) == "table" and type(stage.stats) == "function" then
                out[i] = stage:stats()
            else
                out[i] = {
                    name = stage_name(stage),
                    calls = 0,
                    hits = 0,
                }
            end
        end
        return out
    end
    function self:reset()
        stats.calls = 0; stats.hits = 0
        call_fn = build()
        self.__call = function(_, ...) return call_fn(...) end
        self.source = source
    end
    return setmetatable(self, self)
end

-- Fully typed pipe: each stage declares its mode.
-- stage = { fn = function, mode = "value"|"iter"|"expand" }
function pvm2.pipe_typed(name, stages)
    local n = #stages
    if n == 0 then error("pvm2.pipe_typed: expected at least one stage", 2) end

    local stats = { name = name, calls = 0, hits = 0 }
    local source

    local function build()
        local q = Quote()
        local _stats = q:val(stats, "stats")
        local refs = {}
        for i = 1, n do
            refs[i] = q:val(stages[i].fn, "stage_" .. i)
        end

        q("return function(input)")
        q("  %s.calls = %s.calls + 1", _stats, _stats)
        q("  local a, b, c = input, nil, nil")
        for i = 1, n do
            local mode = stages[i].mode or "value"
            if mode == "value" then
                q("  a = %s(a)", refs[i])
            elseif mode == "iter" then
                q("  a, b, c = %s(a, b, c)", refs[i])
            elseif mode == "expand" then
                q("  a, b, c = %s(a)", refs[i])
            else
                error("pvm2.pipe_typed: unknown mode '" .. mode .. "'", 2)
            end
        end
        q("  return a, b, c")
        q("end")

        local compiled, src = q:compile("=(pvm2.pipe_typed." .. name .. ")")
        source = src
        return compiled
    end

    local call_fn = build()
    local self = {}
    self.name = name
    self.source = source
    self.__call = function(_, input) return call_fn(input) end
    function self:stats() return stats end
    function self:reset()
        stats.calls = 0; stats.hits = 0
        call_fn = build()
        self.__call = function(_, input) return call_fn(input) end
        self.source = source
    end
    return setmetatable(self, self)
end

-- ══════════════════════════════════════════════════════════════
--  ARRAY AS TRIPLET
--
--  Flat command arrays become triplets. Composable with
--  T.filter, T.map, T.take, T.concat, etc.
-- ══════════════════════════════════════════════════════════════

function pvm2.cmds(array, n)
    n = n or #array
    local function gen(a, i)
        i = i + 1
        if i > n then return nil end
        return i, a[i]
    end
    return gen, array, 0
end

function pvm2.cmds_rev(array, n)
    n = n or #array
    local function gen(a, i)
        i = i - 1
        if i < 1 then return nil end
        return i, a[i]
    end
    return gen, array, n + 1
end

-- ══════════════════════════════════════════════════════════════
--  MULTI-CONCAT
--
--  Concatenate N triplets sequentially.
--  Each element is a packed triplet: {g, p, c}.
-- ══════════════════════════════════════════════════════════════

function pvm2.concat_all(trips)
    local function meta_gen(param, i)
        i = i + 1
        if i > #param then return nil end
        return i, param[i][1], param[i][2], param[i][3]
    end
    return Triplet.flatten(meta_gen, trips, 0)
end

-- ══════════════════════════════════════════════════════════════
--  CODEGEN PIPELINE FUSION
--
--  Fuse N map/filter stages into ONE code-generated gen function.
--  No state tables. No nested calls. One trace.
--
--  Stages: plain function = map, { filter = fn } = filter.
--  Returns a chain: chain(src_g, src_p, src_c) → fused g,p,c
-- ══════════════════════════════════════════════════════════════

function pvm2.fuse_maps(name, stages)
    local n = #stages
    if n == 0 then error("pvm2.fuse_maps: need at least one stage", 2) end

    local has_filter = false
    local descs = {}
    for i = 1, n do
        local s = stages[i]
        if type(s) == "function" then
            descs[i] = { kind = "map", fn = s }
        elseif type(s) == "table" and s.filter then
            descs[i] = { kind = "filter", fn = s.filter }
            has_filter = true
        else
            error("pvm2.fuse_maps: stage " .. i .. " must be function or {filter=fn}", 2)
        end
    end

    local stats = { name = name or "fuse", calls = 0, hits = 0 }
    local source

    local q = Quote()
    local _stats = q:val(stats, "stats")
    local refs = {}
    for i = 1, n do
        local hint = descs[i].kind == "map" and "map_" or "filt_"
        refs[i] = q:val(descs[i].fn, hint .. i)
    end

    q("return function(src_g, src_p, src_c)")
    q("  %s.calls = %s.calls + 1", _stats, _stats)
    q("  local _c = src_c")
    q("  return function(_, _)")

    if has_filter then
        q("    while true do")
        q("      local nc, v = src_g(src_p, _c)")
        q("      if nc == nil then return nil end")
        q("      _c = nc")
        local filter_depth = 0
        for i = 1, n do
            local pad = string.rep("  ", filter_depth)
            if descs[i].kind == "map" then
                q("      %sv = %s(v)", pad, refs[i])
            else
                q("      %sif %s(v) then", pad, refs[i])
                filter_depth = filter_depth + 1
            end
        end
        local pad = string.rep("  ", filter_depth)
        q("      %sdo return true, v end", pad)
        for d = filter_depth, 1, -1 do
            q("      %send", string.rep("  ", d - 1))
        end
        q("    end")
    else
        q("    local nc, v = src_g(src_p, _c)")
        q("    if nc == nil then return nil end")
        q("    _c = nc")
        for i = 1, n do
            q("    v = %s(v)", refs[i])
        end
        q("    return true, v")
    end

    q("  end, nil, true")
    q("end")

    local compiled, src = q:compile("=(pvm2.fuse." .. (name or "anon") .. ")")
    source = src

    local self = {}
    self.name = name
    self.source = source
    self.__call = function(_, g, p, c) return compiled(g, p, c) end
    function self:stats() return stats end
    function self:reset()
        stats.calls = 0; stats.hits = 0
    end
    return setmetatable(self, self)
end

function pvm2.fuse_pipeline(name, g, p, c, stages)
    local chain = pvm2.fuse_maps(name, stages)
    return chain(g, p, c)
end

-- ══════════════════════════════════════════════════════════════
--  WALK — ASDL-driven DFS iterator
--
--  Generic: inspects __fields at runtime.
--  Generated: code-generates per-type child-push logic.
--  Both yield nodes in pre-order DFS.
-- ══════════════════════════════════════════════════════════════

function pvm2.walk(root, defs)
    local state = { stack = { root }, top = 1 }

    return function(s, _)
        if s.top == 0 then return nil end
        local node = s.stack[s.top]
        s.top = s.top - 1

        local mt = getmetatable(node)
        if mt and mt.__fields then
            local fields = mt.__fields
            for i = #fields, 1, -1 do
                local f = fields[i]
                if defs[f.type] then
                    if f.list then
                        local list = node[f.name]
                        if list then
                            for j = #list, 1, -1 do
                                s.top = s.top + 1
                                s.stack[s.top] = list[j]
                            end
                        end
                    elseif f.optional then
                        local fv = node[f.name]
                        if fv ~= nil then
                            s.top = s.top + 1
                            s.stack[s.top] = fv
                        end
                    else
                        s.top = s.top + 1
                        s.stack[s.top] = node[f.name]
                    end
                end
            end
        end

        return true, node
    end, state, true
end

function pvm2.walk_gen(sum_type, defs)
    local members = sum_type.members
    if not members then
        error("pvm2.walk_gen: expected a sum type with .members", 2)
    end

    local classes = {}
    for cls in pairs(members) do
        if cls.__fields then
            classes[#classes + 1] = cls
        end
    end
    table.sort(classes, function(a, b)
        return (a.kind or "") < (b.kind or "")
    end)

    local q = Quote()
    local _gmt = q:val(getmetatable, "getmetatable")
    local class_refs = {}
    for i, cls in ipairs(classes) do
        class_refs[i] = q:val(cls, "cls_" .. (cls.kind or i))
    end

    q("local function walk_gen(s, _)")
    q("  if s.top == 0 then return nil end")
    q("  local node = s.stack[s.top]")
    q("  s.top = s.top - 1")
    q("  local mt = %s(node)", _gmt)

    local first = true
    for i, cls in ipairs(classes) do
        local fields = cls.__fields
        local pushes = {}
        for fi = #fields, 1, -1 do
            local f = fields[fi]
            if defs[f.type] then
                pushes[#pushes + 1] = f
            end
        end
        if #pushes > 0 then
            local kw = first and "if" or "elseif"
            first = false
            q("  %s mt == %s then", kw, class_refs[i])
            for _, f in ipairs(pushes) do
                if f.list then
                    q("    local _ls = node.%s", f.name)
                    q("    if _ls ~= nil then")
                    q("      for _j = #_ls, 1, -1 do")
                    q("        s.top = s.top + 1; s.stack[s.top] = _ls[_j]")
                    q("      end")
                    q("    end")
                elseif f.optional then
                    q("    local _fv = node.%s", f.name)
                    q("    if _fv ~= nil then s.top = s.top + 1; s.stack[s.top] = _fv end")
                else
                    q("    s.top = s.top + 1; s.stack[s.top] = node.%s", f.name)
                end
            end
        end
    end
    if not first then q("  end") end

    q("  return true, node")
    q("end")

    q("return function(root)")
    q("  return walk_gen, { stack = { root }, top = 1 }, true")
    q("end")

    local factory, src = q:compile("=(pvm2.walk_gen." .. (sum_type.kind or "walk") .. ")")

    local wrapper = { factory = factory, source = src }
    wrapper.__call = function(_, root) return factory(root) end
    return setmetatable(wrapper, wrapper)
end

-- ══════════════════════════════════════════════════════════════
--  VERB_ITER — uncached dispatch returning triplets
--
--  Handlers return (g, p, c). No caching.
--  For one-shot transforms, analysis, serialization.
-- ══════════════════════════════════════════════════════════════

local function normalize_handlers(handlers)
    local normalized = {}
    for key, fn in pairs(handlers) do
        local class = key
        if type(key) == "table" and rawget(key, "__fields") == nil
           and rawget(key, "members") == nil then
            local mt = getmetatable(key)
            if type(mt) == "table" then class = mt end
        end
        normalized[class] = fn
    end
    local classes, handler_fns = {}, {}
    for cls, fn in pairs(normalized) do
        classes[#classes + 1] = cls
        handler_fns[#handler_fns + 1] = fn
    end
    return classes, handler_fns
end

function pvm2.verb_iter(name, handlers)
    if type(handlers) ~= "table" then
        error("pvm2.verb_iter: handlers must be a table", 2)
    end

    local classes, handler_fns = normalize_handlers(handlers)
    local stats = { name = "verb_iter:" .. name, calls = 0, hits = 0 }
    local source

    local function build_dispatch()
        local q = Quote()
        local _stats    = q:val(stats, "stats")
        local _gmt      = q:val(getmetatable, "getmetatable")
        local _tostring = q:val(tostring, "tostring")
        local _type_fn  = q:val(type, "type")
        local _error    = q:val(error, "error")

        local cls_refs, h_refs = {}, {}
        for i = 1, #classes do
            cls_refs[i] = q:val(classes[i], "cls_" .. (classes[i].kind or i))
            h_refs[i]   = q:val(handler_fns[i], "h_" .. (classes[i].kind or i))
        end

        q("return function(node, ...)")
        q("  %s.calls = %s.calls + 1", _stats, _stats)
        q("  local mt = %s(node)", _gmt)
        for i = 1, #classes do
            local kw = (i == 1) and "if" or "elseif"
            q("  %s mt == %s then return %s(node, ...)", kw, cls_refs[i], h_refs[i])
        end
        q("  else %s('pvm2.verb_iter %q: no handler for ' .. %s(mt and mt.kind or %s(node)), 2)",
            _error, name, _tostring, _type_fn)
        q("  end")
        q("end")

        local compiled, src = q:compile("=(pvm2.verb_iter." .. name .. ")")
        source = src
        return compiled
    end

    local dispatch = build_dispatch()

    for i = 1, #classes do
        rawset(classes[i], name, function(self, ...)
            return dispatch(self, ...)
        end)
    end

    local self = {}
    self.name = name
    self.source = source
    self.__call = function(_, node, ...) return dispatch(node, ...) end
    function self:stats() return stats end
    function self:reset()
        stats.calls = 0; stats.hits = 0
        dispatch = build_dispatch()
        self.__call = function(_, node, ...) return dispatch(node, ...) end
        self.source = source
        for i = 1, #classes do
            rawset(classes[i], name, function(s, ...) return dispatch(s, ...) end)
        end
    end
    return setmetatable(self, self)
end

-- ══════════════════════════════════════════════════════════════
--  VERB_MEMO — cached dispatch returning triplets
--
--  The key primitive. Combines:
--   • verb's caching (identity-keyed, weak-ref)
--   • verb_iter's composability (triplet output)
--   • automatic collect+cache on miss
--   • T.seq over cached array on hit
--
--  Handlers return triplets. By default this is a zero-arg
--  cached boundary, matching the hot recursive case.
--
--    local render = pvm2.verb_memo("render", handlers)
--    render(node)          -- fast weak-key node cache
--
--  If handlers need extra parameters, opt in with opts.args = true:
--
--    local render = pvm2.verb_memo("render", handlers, { args = true })
--    render(node, theme)   -- node+args memoization via arg trie
--
--  Recursive calls to children hit their caches — structural
--  sharing means unchanged subtrees are the same object, so
--  their caches are instant.
--
--  This eliminates intermediate ASDL layers:
--    pvm:   Widget →verb→ UI.Node →lower→ Cmd[]  (2 boundaries)
--    pvm2:  Widget →verb_memo→ Cmd[]              (1 boundary)
-- ══════════════════════════════════════════════════════════════

local function _seq_gen(t, i)
    i = i + 1
    if i > #t then return nil end
    return i, t[i]
end

local _arg_nil = {}
local _arg_value = {}

local function _cache_args_get(cache, node, argc, ...)
    local t = cache[node]
    if t == nil then return nil end
    for i = 1, argc do
        local key = select(i, ...)
        if key == nil then key = _arg_nil end
        t = t[key]
        if t == nil then return nil end
    end
    return t[_arg_value]
end

local function _cache_args_put(cache, node, result, argc, ...)
    local t = cache[node]
    if t == nil then
        t = {}
        cache[node] = t
    end
    for i = 1, argc do
        local key = select(i, ...)
        if key == nil then key = _arg_nil end
        local next_t = t[key]
        if next_t == nil then
            next_t = {}
            t[key] = next_t
        end
        t = next_t
    end
    t[_arg_value] = result
end

function pvm2.verb_memo(name, handlers, opts)
    opts = opts or {}
    if type(handlers) ~= "table" then
        error("pvm2.verb_memo: handlers must be a table", 2)
    end
    if opts.flat and opts.args then
        error("pvm2.verb_memo: opts.flat and opts.args are mutually exclusive", 2)
    end

    local classes, handler_fns = normalize_handlers(handlers)
    local cache = setmetatable({}, { __mode = "k" })
    local arg_cache = opts.args and setmetatable({}, { __mode = "k" }) or nil
    local stats = { name = opts.name or ("verb_memo:" .. tostring(name)), calls = 0, hits = 0 }
    local source

    local function build_dispatch_zero()
        local q = Quote()
        local _stats     = q:val(stats, "stats")
        local _cache     = q:val(cache, "cache")
        local _seq       = q:val(_seq_gen, "seq_gen")
        local _gmt       = q:val(getmetatable, "getmetatable")
        local _tostring  = q:val(tostring, "tostring")
        local _type_fn   = q:val(type, "type")
        local _error     = q:val(error, "error")

        local cls_refs, h_refs = {}, {}
        for i = 1, #classes do
            cls_refs[i] = q:val(classes[i], "cls_" .. (classes[i].kind or i))
            h_refs[i]   = q:val(handler_fns[i], "h_" .. (classes[i].kind or i))
        end

        q("return function(node)")
        q("  %s.calls = %s.calls + 1", _stats, _stats)
        q("  local hit = %s[node]", _cache)
        q("  if hit ~= nil then")
        q("    %s.hits = %s.hits + 1", _stats, _stats)
        q("    return %s, hit, 0", _seq)
        q("  end")

        q("  local mt = %s(node)", _gmt)
        q("  local g, p, c")
        for i = 1, #classes do
            local kw = (i == 1) and "if" or "elseif"
            q("  %s mt == %s then g, p, c = %s(node)", kw, cls_refs[i], h_refs[i])
        end
        q("  else %s('pvm2.verb_memo %q: no handler for ' .. %s(mt and mt.kind or %s(node)), 2)",
            _error, name, _tostring, _type_fn)
        q("  end")

        q("  local result, rn = {}, 0")
        q("  while true do")
        q("    local val; c, val = g(p, c)")
        q("    if c == nil then break end")
        q("    rn = rn + 1; result[rn] = val")
        q("  end")
        q("  %s[node] = result", _cache)
        q("  return %s, result, 0", _seq)
        q("end")

        local compiled, src = q:compile("=(pvm2.verb_memo." .. name .. ".zero)")
        source = src
        return compiled
    end

    local function build_dispatch_flat()
        local q = Quote()
        local _stats     = q:val(stats, "stats")
        local _cache     = q:val(cache, "cache")
        local _seq       = q:val(_seq_gen, "seq_gen")
        local _gmt       = q:val(getmetatable, "getmetatable")
        local _tostring  = q:val(tostring, "tostring")
        local _type_fn   = q:val(type, "type")
        local _error     = q:val(error, "error")

        local cls_refs, h_refs = {}, {}
        for i = 1, #classes do
            cls_refs[i] = q:val(classes[i], "cls_" .. (classes[i].kind or i))
            h_refs[i]   = q:val(handler_fns[i], "h_" .. (classes[i].kind or i))
        end

        q("local function miss(node, out, start, reuse_out)")
        q("  local mt = %s(node)", _gmt)
        for i = 1, #classes do
            local kw = (i == 1) and "if" or "elseif"
            q("  %s mt == %s then %s(node, out)", kw, cls_refs[i], h_refs[i])
        end
        q("  else %s('pvm2.verb_memo %q: no handler for ' .. %s(mt and mt.kind or %s(node)), 2)",
            _error, name, _tostring, _type_fn)
        q("  end")
        q("  local result")
        q("  if reuse_out then")
        q("    result = out")
        q("  else")
        q("    result = {}")
        q("    local rn = 0")
        q("    for i = start + 1, #out do rn = rn + 1; result[rn] = out[i] end")
        q("  end")
        q("  %s[node] = result", _cache)
        q("  return result")
        q("end")

        q("local function append(node, out)")
        q("  %s.calls = %s.calls + 1", _stats, _stats)
        q("  local hit = %s[node]", _cache)
        q("  if hit ~= nil then")
        q("    %s.hits = %s.hits + 1", _stats, _stats)
        q("    local n = #out")
        q("    for i = 1, #hit do out[n + i] = hit[i] end")
        q("    return")
        q("  end")
        q("  miss(node, out, #out, false)")
        q("end")

        q("return function(node, out)")
        q("  if out ~= nil then")
        q("    return append(node, out)")
        q("  end")
        q("  %s.calls = %s.calls + 1", _stats, _stats)
        q("  local hit = %s[node]", _cache)
        q("  if hit ~= nil then")
        q("    %s.hits = %s.hits + 1", _stats, _stats)
        q("    return %s, hit, 0", _seq)
        q("  end")
        q("  local result = {}")
        q("  miss(node, result, 0, true)")
        q("  return %s, result, 0", _seq)
        q("end")

        local compiled, src = q:compile("=(pvm2.verb_memo." .. name .. ".flat)")
        source = src
        return compiled
    end

    local function build_dispatch_args()
        local q = Quote()
        local _stats          = q:val(stats, "stats")
        local _cache          = q:val(cache, "cache")
        local _arg_cache      = q:val(arg_cache, "arg_cache")
        local _cache_args_get = q:val(_cache_args_get, "cache_args_get")
        local _cache_args_put = q:val(_cache_args_put, "cache_args_put")
        local _select         = q:val(select, "select")
        local _seq            = q:val(_seq_gen, "seq_gen")
        local _gmt            = q:val(getmetatable, "getmetatable")
        local _tostring       = q:val(tostring, "tostring")
        local _type_fn        = q:val(type, "type")
        local _error          = q:val(error, "error")

        local cls_refs, h_refs = {}, {}
        for i = 1, #classes do
            cls_refs[i] = q:val(classes[i], "cls_" .. (classes[i].kind or i))
            h_refs[i]   = q:val(handler_fns[i], "h_" .. (classes[i].kind or i))
        end

        q("return function(node, ...)")
        q("  %s.calls = %s.calls + 1", _stats, _stats)
        q("  local argc = %s('#', ...)", _select)
        q("  local hit")
        q("  if argc == 0 then")
        q("    hit = %s[node]", _cache)
        q("  else")
        q("    hit = %s(%s, node, argc, ...)", _cache_args_get, _arg_cache)
        q("  end")
        q("  if hit ~= nil then")
        q("    %s.hits = %s.hits + 1", _stats, _stats)
        q("    return %s, hit, 0", _seq)
        q("  end")

        q("  local mt = %s(node)", _gmt)
        q("  local g, p, c")
        for i = 1, #classes do
            local kw = (i == 1) and "if" or "elseif"
            q("  %s mt == %s then g, p, c = %s(node, ...)", kw, cls_refs[i], h_refs[i])
        end
        q("  else %s('pvm2.verb_memo %q: no handler for ' .. %s(mt and mt.kind or %s(node)), 2)",
            _error, name, _tostring, _type_fn)
        q("  end")

        q("  local result, rn = {}, 0")
        q("  while true do")
        q("    local val; c, val = g(p, c)")
        q("    if c == nil then break end")
        q("    rn = rn + 1; result[rn] = val")
        q("  end")
        q("  if argc == 0 then")
        q("    %s[node] = result", _cache)
        q("  else")
        q("    %s(%s, node, result, argc, ...)", _cache_args_put, _arg_cache)
        q("  end")
        q("  return %s, result, 0", _seq)
        q("end")

        local compiled, src = q:compile("=(pvm2.verb_memo." .. name .. ".args)")
        source = src
        return compiled
    end

    local dispatch
    if opts.flat then
        dispatch = build_dispatch_flat()
    elseif opts.args then
        dispatch = build_dispatch_args()
    else
        dispatch = build_dispatch_zero()
    end

    for i = 1, #classes do
        if opts.flat then
            rawset(classes[i], name, function(self, out)
                return dispatch(self, out)
            end)
        elseif opts.args then
            rawset(classes[i], name, function(self, ...)
                return dispatch(self, ...)
            end)
        else
            rawset(classes[i], name, function(self)
                return dispatch(self)
            end)
        end
    end

    local boundary = {}
    boundary.name = stats.name
    boundary.source = source
    if opts.flat then
        boundary.__call = function(_, node, out, ...)
            if select('#', ...) ~= 0 then
                error("pvm2.verb_memo " .. tostring(name) .. ": flat mode accepts at most one output array", 2)
            end
            return dispatch(node, out)
        end
    elseif opts.args then
        boundary.__call = function(_, node, ...) return dispatch(node, ...) end
    else
        boundary.__call = function(_, node, ...)
            if select('#', ...) ~= 0 then
                error("pvm2.verb_memo " .. tostring(name) .. ": extra args require opts.args = true", 2)
            end
            return dispatch(node)
        end
    end
    function boundary:stats() return stats end
    function boundary:reset()
        cache = setmetatable({}, { __mode = "k" })
        arg_cache = opts.args and setmetatable({}, { __mode = "k" }) or nil
        stats.calls = 0; stats.hits = 0
        if opts.flat then
            dispatch = build_dispatch_flat()
        elseif opts.args then
            dispatch = build_dispatch_args()
        else
            dispatch = build_dispatch_zero()
        end
        if opts.flat then
            boundary.__call = function(_, node, out, ...)
                if select('#', ...) ~= 0 then
                    error("pvm2.verb_memo " .. tostring(name) .. ": flat mode accepts at most one output array", 2)
                end
                return dispatch(node, out)
            end
        elseif opts.args then
            boundary.__call = function(_, node, ...) return dispatch(node, ...) end
        else
            boundary.__call = function(_, node, ...)
                if select('#', ...) ~= 0 then
                    error("pvm2.verb_memo " .. tostring(name) .. ": extra args require opts.args = true", 2)
                end
                return dispatch(node)
            end
        end
        boundary.source = source
        for i = 1, #classes do
            if opts.flat then
                rawset(classes[i], name, function(s, out) return dispatch(s, out) end)
            elseif opts.args then
                rawset(classes[i], name, function(s, ...) return dispatch(s, ...) end)
            else
                rawset(classes[i], name, function(s)
                    return dispatch(s)
                end)
            end
        end
    end
    return setmetatable(boundary, boundary)
end

-- ══════════════════════════════════════════════════════════════
--  VERB_FLAT — cached dispatch with array-append output
--
--  The low-level fast path. Same caching as verb_memo's
--  opts.flat mode, but exposed directly for callers that already
--  own an output array and want append-only recursion.
--  No iterator state tables. No T.flatten overhead.
--
--  Handler signature: function(node, out)
--    append to out with: out[#out+1] = value
--    recurse with:       node.child:method(out)
--
--  On cache miss: run handler, record what was appended, cache it.
--  On cache hit: copy cached elements to output array.
--
--  Top-level call:
--    local out = {}
--    render(root, out)   -- out is now the flat command array
--
--  Wrap in lower() for zero-cost warm frames:
--    local compile = pvm2.lower("compile", function(root)
--        local out = {}; render(root, out); return out
--    end)
-- ══════════════════════════════════════════════════════════════

function pvm2.verb_flat(name, handlers, opts)
    opts = opts or {}
    if type(handlers) ~= "table" then
        error("pvm2.verb_flat: handlers must be a table", 2)
    end

    local classes, handler_fns = normalize_handlers(handlers)
    local cache = setmetatable({}, { __mode = "k" })
    local stats = { name = "verb_flat:" .. name, calls = 0, hits = 0 }
    local source

    local function build_dispatch()
        local q = Quote()
        local _stats    = q:val(stats, "stats")
        local _cache    = q:val(cache, "cache")
        local _gmt      = q:val(getmetatable, "getmetatable")
        local _tostring = q:val(tostring, "tostring")
        local _type_fn  = q:val(type, "type")
        local _error    = q:val(error, "error")

        local cls_refs, h_refs = {}, {}
        for i = 1, #classes do
            cls_refs[i] = q:val(classes[i], "cls_" .. (classes[i].kind or i))
            h_refs[i]   = q:val(handler_fns[i], "h_" .. (classes[i].kind or i))
        end

        q("return function(node, out)")
        q("  %s.calls = %s.calls + 1", _stats, _stats)

        -- cache hit: copy cached elements to out
        q("  local hit = %s[node]", _cache)
        q("  if hit ~= nil then")
        q("    %s.hits = %s.hits + 1", _stats, _stats)
        q("    local n = #out")
        q("    for i = 1, #hit do out[n + i] = hit[i] end")
        q("    return")
        q("  end")

        -- cache miss: dispatch, track output, cache
        q("  local mt = %s(node)", _gmt)
        q("  local start = #out")
        for i = 1, #classes do
            local kw = (i == 1) and "if" or "elseif"
            q("  %s mt == %s then %s(node, out)", kw, cls_refs[i], h_refs[i])
        end
        q("  else %s('pvm2.verb_flat %q: no handler for ' .. %s(mt and mt.kind or %s(node)), 2)",
            _error, name, _tostring, _type_fn)
        q("  end")

        -- cache what was appended
        q("  local result, rn = {}, 0")
        q("  for i = start + 1, #out do rn = rn + 1; result[rn] = out[i] end")
        q("  %s[node] = result", _cache)

        q("end")

        local compiled, src = q:compile("=(pvm2.verb_flat." .. name .. ")")
        source = src
        return compiled
    end

    local dispatch = build_dispatch()

    for i = 1, #classes do
        rawset(classes[i], name, function(self, out)
            return dispatch(self, out)
        end)
    end

    local boundary = {}
    boundary.name = name
    boundary.source = source
    boundary.__call = function(_, node, out) return dispatch(node, out) end
    function boundary:stats() return stats end
    function boundary:reset()
        cache = setmetatable({}, { __mode = "k" })
        stats.calls = 0; stats.hits = 0
        dispatch = build_dispatch()
        boundary.__call = function(_, node, out) return dispatch(node, out) end
        boundary.source = source
        for i = 1, #classes do
            rawset(classes[i], name, function(self, out) return dispatch(self, out) end)
        end
    end
    return setmetatable(boundary, boundary)
end

return pvm2
