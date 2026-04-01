-- mgps.lua — structural GPS redesign
--
-- Public contract:
--   - ASDL-first
--   - keyless API
--   - lowerings emit: gen + structural state declaration + payload
--   - framework derives code/state identity automatically
--
-- Core API:
--   local M = require("mgps")
--   local T = M.context("paint"):Define [[ module View { ... } ]]
--   function T.View.Rect:paint(env)
--       return M.emit(rect_gen, M.state.none(), { ... })
--   end
--
-- Newcomer note: mgps is organized around a simple machine triplet:
--
--   gen   = code to run
--   param = residual authored payload
--   state = mutable retained runtime data
--
-- A slot runs an installed machine as:
--
--   gen(param, state, input...)
--
-- This is iterator-shaped, but more general than Lua's exact generic-for
-- protocol.
--
-- Internally this file sometimes wraps code in small callable tables so the
-- same split stays visible everywhere: code in gen, payload in param, retained
-- data in state.
--
-- See MGPS.md for the full design manifesto.

local has_ffi, ffi = pcall(require, "ffi")

-- Make the existing ASDL implementation available under gps.* names when mgps.lua
-- is loaded as a standalone file in a flat source tree.
if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"] = function() return require("asdl_lexer") end
end
if not package.preload["gps.asdl_parser"] then
    package.preload["gps.asdl_parser"] = function() return require("asdl_parser") end
end
if not package.preload["gps.asdl_context"] then
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local asdl_context = require("gps.asdl_context")

local M = {}
M.state = {}

-- ═══════════════════════════════════════════════════════════════
-- SMALL HELPERS
-- ═══════════════════════════════════════════════════════════════

local function shallow_copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, subv in pairs(v) do out[deep_copy(k)] = deep_copy(subv) end
    return out
end

local function sorted_keys(t)
    local ks = {}
    for k in pairs(t) do ks[#ks + 1] = k end
    table.sort(ks, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return tostring(a) < tostring(b)
    end)
    return ks
end

local function stable_encode(v, seen)
    seen = seen or {}
    local tv = type(v)
    if tv == "nil" then return "nil" end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "number" then return string.format("%q", tostring(v)) end
    if tv == "string" then return string.format("%q", v) end
    if tv == "function" or tv == "userdata" or tv == "thread" then
        return tv .. ":" .. tostring(v)
    end
    if tv == "cdata" then
        return "cdata:" .. tostring(v)
    end
    if tv ~= "table" then
        return tv .. ":" .. tostring(v)
    end
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local parts = {}
    local ks = sorted_keys(v)
    for i = 1, #ks do
        local k = ks[i]
        parts[i] = "[" .. stable_encode(k, seen) .. "]=" .. stable_encode(v[k], seen)
    end
    seen[v] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

-- ═══════════════════════════════════════════════════════════════
-- STATE DECLARATIONS
-- ═══════════════════════════════════════════════════════════════

local function is_state_decl(v)
    return type(v) == "table" and rawget(v, "__mgps_state_decl") == true
end

local NONE_DECL = { __mgps_state_decl = true, tag = "none" }

local function ensure_state_decl(v)
    if v == nil then return NONE_DECL end
    if not is_state_decl(v) then
        error("mgps: expected structural state declaration", 3)
    end
    return v
end

function M.state.none()
    return NONE_DECL
end

function M.state.ffi(ctype, opts)
    opts = opts or {}
    return {
        __mgps_state_decl = true,
        tag = "ffi",
        ctype = ctype,
        shape = opts.shape or (type(ctype) == "string" and ctype or tostring(ctype)),
        init = opts.init,
        release = opts.release,
    }
end

function M.state.table(name, opts)
    opts = opts or {}
    return {
        __mgps_state_decl = true,
        tag = "table",
        name = name or "table",
        shape = opts.shape,
        init = opts.init,
        alloc = opts.alloc,
        release = opts.release,
    }
end

function M.state.value(initial)
    return {
        __mgps_state_decl = true,
        tag = "value",
        initial = initial,
    }
end

function M.state.f64(initial)
    return {
        __mgps_state_decl = true,
        tag = "f64",
        initial = initial or 0,
    }
end

function M.state.record(name, fields)
    return {
        __mgps_state_decl = true,
        tag = "record",
        name = name or "record",
        fields = fields or {},
    }
end

function M.state.product(name, children)
    return {
        __mgps_state_decl = true,
        tag = "product",
        name = name or "product",
        children = children or {},
    }
end

function M.state.array(of_decl, n)
    return {
        __mgps_state_decl = true,
        tag = "array",
        of = ensure_state_decl(of_decl),
        n = n or 0,
    }
end

function M.state.resource(kind, spec, ops)
    ops = ops or {}
    return {
        __mgps_state_decl = true,
        tag = "resource",
        kind = kind,
        spec = spec or {},
        alloc = ops.alloc,
        release = ops.release,
    }
end

-- Back-compat aliases for older GPS surface names.
M.state_ffi = M.state.ffi
M.state_table = function(init, release, shape)
    return M.state.table("table", {
        init = init,
        release = release,
        shape = shape,
    })
end

local function state_shape_of(decl)
    decl = ensure_state_decl(decl)
    local tag = decl.tag

    if tag == "none" then
        return "none"
    elseif tag == "ffi" then
        return "ffi(" .. stable_encode(decl.shape) .. ")"
    elseif tag == "table" then
        return "table(" .. stable_encode({ name = decl.name, shape = decl.shape }) .. ")"
    elseif tag == "value" then
        return "value(" .. stable_encode(decl.initial) .. ")"
    elseif tag == "f64" then
        return "f64(" .. stable_encode(decl.initial) .. ")"
    elseif tag == "record" then
        local parts = {}
        local ks = sorted_keys(decl.fields)
        for i = 1, #ks do
            local k = ks[i]
            parts[i] = tostring(k) .. ":" .. state_shape_of(decl.fields[k])
        end
        return "record(" .. tostring(decl.name) .. "|" .. table.concat(parts, ",") .. ")"
    elseif tag == "product" then
        local parts = {}
        for i = 1, #decl.children do parts[i] = state_shape_of(decl.children[i]) end
        return "product(" .. tostring(decl.name) .. "|" .. table.concat(parts, ",") .. ")"
    elseif tag == "array" then
        return "array(" .. state_shape_of(decl.of) .. "," .. tostring(decl.n) .. ")"
    elseif tag == "resource" then
        return "resource(" .. tostring(decl.kind) .. "|" .. stable_encode(decl.spec) .. ")"
    end

    error("mgps: unknown state declaration tag '" .. tostring(tag) .. "'", 3)
end

local EMPTY_LAYOUT = {
    kind = "empty",
    alloc = function() return nil end,
    release = function() end,
}

local realized_state_cache = {}

local function realize_state(decl)
    decl = ensure_state_decl(decl)
    local shape = state_shape_of(decl)
    local hit = realized_state_cache[shape]
    if hit then return hit end

    local tag = decl.tag
    local layout

    if tag == "none" then
        layout = EMPTY_LAYOUT

    elseif tag == "ffi" then
        if not has_ffi then error("mgps: ffi state requires LuaJIT FFI", 3) end
        local ctype = type(decl.ctype) == "string" and ffi.typeof(decl.ctype) or decl.ctype
        layout = {
            kind = "ffi",
            state_shape = shape,
            alloc = function()
                local s = ffi.new(ctype)
                if decl.init then decl.init(s) end
                return s
            end,
            release = decl.release or function() end,
        }

    elseif tag == "table" then
        layout = {
            kind = "table",
            state_shape = shape,
            alloc = function()
                if decl.alloc then return decl.alloc() end
                local s = {}
                if decl.init then
                    local r = decl.init(s)
                    if r ~= nil then s = r end
                end
                return s
            end,
            release = decl.release or function() end,
        }

    elseif tag == "value" then
        layout = {
            kind = "value",
            state_shape = shape,
            alloc = function() return deep_copy(decl.initial) end,
            release = function() end,
        }

    elseif tag == "f64" then
        layout = {
            kind = "f64",
            state_shape = shape,
            alloc = function()
                if has_ffi then return ffi.new("double[1]", decl.initial or 0) end
                return decl.initial or 0
            end,
            release = function() end,
        }

    elseif tag == "record" then
        local child_layouts = {}
        local keys = sorted_keys(decl.fields)
        for i = 1, #keys do
            local k = keys[i]
            child_layouts[k] = realize_state(decl.fields[k])
        end
        layout = {
            kind = "record",
            state_shape = shape,
            alloc = function()
                local out = {}
                for i = 1, #keys do
                    local k = keys[i]
                    out[k] = child_layouts[k].alloc()
                end
                return out
            end,
            release = function(s)
                if not s then return end
                for i = #keys, 1, -1 do
                    local k = keys[i]
                    child_layouts[k].release(s[k])
                end
            end,
        }

    elseif tag == "product" then
        local child_layouts = {}
        for i = 1, #decl.children do
            child_layouts[i] = realize_state(decl.children[i])
        end
        layout = {
            kind = "product",
            state_shape = shape,
            alloc = function()
                local out = {}
                for i = 1, #child_layouts do out[i] = child_layouts[i].alloc() end
                return out
            end,
            release = function(s)
                if not s then return end
                for i = #child_layouts, 1, -1 do child_layouts[i].release(s[i]) end
            end,
        }

    elseif tag == "array" then
        local child_layout = realize_state(decl.of)
        layout = {
            kind = "array",
            state_shape = shape,
            alloc = function()
                local out = {}
                for i = 1, decl.n do out[i] = child_layout.alloc() end
                return out
            end,
            release = function(s)
                if not s then return end
                for i = #s, 1, -1 do child_layout.release(s[i]) end
            end,
        }

    elseif tag == "resource" then
        layout = {
            kind = "resource",
            state_shape = shape,
            alloc = function()
                if decl.alloc then return decl.alloc(deep_copy(decl.spec)) end
                return { kind = decl.kind, spec = deep_copy(decl.spec) }
            end,
            release = decl.release or function() end,
        }

    else
        error("mgps: unknown state declaration tag '" .. tostring(tag) .. "'", 3)
    end

    layout.state_decl = decl
    realized_state_cache[shape] = layout
    return layout
end

-- ═══════════════════════════════════════════════════════════════
-- EMITTED TERMS / FAMILIES / BOUND VALUES
--
-- A leaf lowering emits the public machine form:
--
--   emit(gen, state_decl, param)
--
-- That is still not quite runnable: we first realize the structural state
-- declaration into an alloc/release layout and then bind a particular payload
-- value to a reusable family. The split is:
--
--   family = code + state layout + structural identities
--   bound  = family + concrete param payload
--
-- Runtime execution is always the triplet call:
--
--   gen(param, state, input...)
--
-- Internally, mgps normalizes framework-built code into small callable tables.
-- User leaf code can still be plain Lua functions; emit() wraps them into the
-- same canonical representation so the core keeps one clear execution model.
-- ═══════════════════════════════════════════════════════════════

local function is_emit(v)
    return type(v) == "table" and rawget(v, "__mgps_emit") == true
end

local function is_bound(v)
    return type(v) == "table" and rawget(v, "__mgps_bound") == true
end

local function is_gen_table(v)
    return type(v) == "table" and rawget(v, "__mgps_gen") == true
end

local run_triplet

local GEN_MT = {}
function GEN_MT:__call(param, state, ...)
    return run_triplet(self, param, state, ...)
end

local function make_gen_table(tag, fields)
    fields = fields or {}
    fields.__mgps_gen = true
    fields.tag = tag
    return setmetatable(fields, GEN_MT)
end

local function normalize_gen(gen)
    if is_gen_table(gen) then return gen end
    if type(gen) == "function" then
        return make_gen_table("lua_fn", { fn = gen })
    end
    error("mgps.emit: expected gen function or internal gen table", 3)
end

local function describe_gen(gen)
    gen = normalize_gen(gen)
    if gen.tag == "lua_fn" then
        return "gen:" .. tostring(gen.fn)
    end
    return "gen:" .. tostring(gen.tag)
end

local function bind_family(family, param)
    return {
        __mgps_bound = true,
        family = family,
        param = param,
        gen = family.gen,
        state_layout = family.state_layout,
        code_shape = family.code_shape,
        state_shape = family.state_shape,
    }
end

local function run_child_gens_forward(child_gens, param, state, threaded)
    for i = 1, #child_gens do
        threaded = run_triplet(child_gens[i], param[i], state[i], threaded) or threaded
    end
    return threaded
end

run_triplet = function(gen, param, state, ...)
    gen = normalize_gen(gen)

    local tag = gen.tag
    if tag == "lua_fn" then
        return gen.fn(param, state, ...)
    elseif tag == "empty" then
        return nil
    elseif tag == "compose_seq" then
        return run_child_gens_forward(gen.child_gens, param, state, ...)
    elseif tag == "compose_body" then
        return gen.body_fn(gen.child_gens, param, state, ...)
    end

    error("mgps: unknown gen tag '" .. tostring(tag) .. "'", 3)
end

function M.emit(gen, state_decl, param)
    return {
        __mgps_emit = true,
        gen = normalize_gen(gen),
        state_decl = ensure_state_decl(state_decl),
        param = param,
    }
end

local function stamp_code_shape(result, shape)
    if is_emit(result) then
        if result.code_shape == nil then result.code_shape = shape end
    elseif is_bound(result) then
        if result.family.code_shape == nil then result.family.code_shape = shape end
        result.code_shape = result.family.code_shape
    end
    return result
end

local function ensure_bound(result)
    if is_bound(result) then return result end
    if not is_emit(result) then
        error("mgps: expected emitted or bound result", 3)
    end

    local code_shape = result.code_shape or describe_gen(result.gen)
    local state_decl = ensure_state_decl(result.state_decl)
    local state_shape = state_shape_of(state_decl)
    local state_layout = realize_state(state_decl)
    local family = {
        __mgps_family = true,
        gen = normalize_gen(result.gen),
        state_decl = state_decl,
        state_layout = state_layout,
        code_shape = code_shape,
        state_shape = state_shape,
    }
    return bind_family(family, result.param)
end

function M.is_compiled(v)
    return is_emit(v) or is_bound(v)
end

-- ═══════════════════════════════════════════════════════════════
-- LEAF HELPERS
--
-- These helpers used to manufacture fresh Lua closures. They now return small
-- callable tables so the triplet split stays obvious. The emitted machine is
-- still the same public form: emit(gen, state_decl, param).
-- ═══════════════════════════════════════════════════════════════

local LEAF_CALL_MT = {}
function LEAF_CALL_MT:__call(node, ...)
    local state_fn = self.state_fn
    local state_decl = state_fn and state_fn(node, ...) or NONE_DECL
    local param_fn = self.param_fn
    local param = param_fn and param_fn(node, ...) or nil
    return M.emit(self.gen, state_decl, param)
end

function M.leaf(gen, state_fn, param_fn)
    return setmetatable({
        gen = gen,
        state_fn = state_fn,
        param_fn = param_fn,
    }, LEAF_CALL_MT)
end

local VARIANT_CALL_MT = {}
function VARIANT_CALL_MT:__call(node, ...)
    local spec = self.spec
    local shape = spec.classify and spec.classify(node, ...) or {}
    local gen = spec.gen and spec.gen(shape, ...) or spec.rule or spec[1]
    if type(gen) ~= "function" then
        error("mgps.variant: missing gen(shape, ...) function", 2)
    end
    local state_decl
    if type(spec.state) == "function" then
        state_decl = spec.state(shape, ...)
    elseif spec.state ~= nil then
        state_decl = spec.state
    else
        state_decl = NONE_DECL
    end
    local param = spec.param and spec.param(node, shape, ...) or nil
    local out = M.emit(gen, state_decl, param)
    if spec.code_shape ~= nil then out.code_shape = spec.code_shape end
    return out
end

function M.variant(spec)
    return setmetatable({ spec = spec or {} }, VARIANT_CALL_MT)
end

-- ═══════════════════════════════════════════════════════════════
-- STRUCTURAL COMPOSITION
-- ═══════════════════════════════════════════════════════════════

local EMPTY_GEN = make_gen_table("empty")

local function collect_children(children)
    local n = #children
    local code_parts = {}
    local state_decls = {}
    local param = {}
    local child_gens = {}

    for i = 1, n do
        local child = ensure_bound(children[i])
        code_parts[i] = child.code_shape or describe_gen(child.gen)
        state_decls[i] = child.family.state_decl
        param[i] = child.param
        child_gens[i] = child.gen
    end

    return n, code_parts, state_decls, param, child_gens
end

local function emit_composed(children, gen, compose_tag)
    local n, code_parts, state_decls, param = collect_children(children)
    if n == 0 then
        local out = M.emit(EMPTY_GEN, NONE_DECL, {})
        out.code_shape = "empty"
        return out
    end
    if n == 1 and compose_tag == "seq" then return children[1] end

    local out = M.emit(gen, M.state.product("Compose", state_decls), param)
    out.code_shape = "compose(" .. compose_tag .. "|" .. table.concat(code_parts, ",") .. ")"
    return out
end

function M.compose(children, body_fn)
    -- Composition keeps the split explicit:
    --   code in gen
    --   payload in param
    --   retained data in state
    --
    -- The internal helper here is deliberately tiny. It exists only so the core
    -- itself reads in triplet form.
    if body_fn ~= nil then
        local _, _, _, _, child_gens = collect_children(children)
        return emit_composed(children, make_gen_table("compose_body", {
            child_gens = child_gens,
            body_fn = body_fn,
        }), "body:" .. tostring(body_fn))
    end

    local _, _, _, _, child_gens = collect_children(children)
    return emit_composed(children, make_gen_table("compose_seq", {
        child_gens = child_gens,
    }), "seq")
end

-- ═══════════════════════════════════════════════════════════════
-- DISPATCH
-- ═══════════════════════════════════════════════════════════════

local function dispatch_match(node, arms, ...)
    local kind = node.kind
    if kind == nil then error("mgps.match: value has no .kind", 3) end
    local arm = arms[kind]
    if type(arm) ~= "function" then
        error("mgps.match: missing arm for '" .. tostring(kind) .. "'", 3)
    end
    return stamp_code_shape(arm(node, ...), kind)
end

local MATCH_CALL_MT = {}
function MATCH_CALL_MT:__call(node, ...)
    return dispatch_match(node, self.arms, ...)
end

function M.match(value_or_arms, arms)
    -- match() now uses a shared callable dispatcher rather than allocating a
    -- fresh curried closure for each arm table.
    if arms ~= nil then
        return dispatch_match(value_or_arms, arms)
    end

    return setmetatable({ arms = value_or_arms }, MATCH_CALL_MT)
end

-- ═══════════════════════════════════════════════════════════════
-- BOUNDARIES
-- ═══════════════════════════════════════════════════════════════

local function fresh_lower_stats(name)
    return {
        name = name,
        calls = 0,
        node_hits = 0,
        code_hits = 0,
        code_misses = 0,
        state_hits = 0,
        state_misses = 0,
    }
end

local LOWER_CALL_MT = {}

function LOWER_CALL_MT:__call(input, ...)
    local stats = self._stats
    stats.calls = stats.calls + 1

    local node_cache = self._node_cache
    if select("#", ...) == 0 and type(input) == "table" then
        local cached = node_cache[input]
        if cached ~= nil then
            stats.node_hits = stats.node_hits + 1
            return cached
        end
    end

    local result = self._fn(input, ...)

    if M.is_compiled(result) then
        local bound = ensure_bound(result)
        local code_shape = bound.code_shape
        local state_shape = bound.state_shape

        local code_cache = self._code_cache
        local cached_gen = code_cache[code_shape]
        if cached_gen ~= nil then
            stats.code_hits = stats.code_hits + 1
        else
            stats.code_misses = stats.code_misses + 1
            code_cache[code_shape] = bound.family.gen
            cached_gen = bound.family.gen
        end

        local state_cache = self._state_cache
        local cached_state = state_cache[state_shape]
        if cached_state ~= nil then
            stats.state_hits = stats.state_hits + 1
        else
            stats.state_misses = stats.state_misses + 1
            state_cache[state_shape] = {
                state_decl = bound.family.state_decl,
                state_layout = bound.family.state_layout,
            }
            cached_state = state_cache[state_shape]
        end

        local family = {
            __mgps_family = true,
            gen = cached_gen,
            state_decl = cached_state.state_decl,
            state_layout = cached_state.state_layout,
            code_shape = code_shape,
            state_shape = state_shape,
        }
        result = bind_family(family, bound.param)
    end

    if type(input) == "table" then node_cache[input] = result end
    return result
end

function M.lower(name, fn)
    -- A boundary memoizes structural compilation.
    --
    -- The user-facing fiction is keyless: callers just lower authored values.
    -- Internally we cache three different things:
    --   - node cache: exact source object reuse
    --   - code cache: reusable gen family by code shape
    --   - state cache: reusable state layout by state shape
    --
    -- lower() returns a small callable table with shared __call logic rather
    -- than a bespoke per-boundary closure. The machine semantics stay the same:
    --
    --   gen(param, state, input...)
    if type(name) == "function" and fn == nil then
        fn = name
        name = "lower"
    end

    local boundary = setmetatable({
        _name = name,
        _fn = fn,
        _node_cache = setmetatable({}, { __mode = "k" }),
        _code_cache = {},
        _state_cache = {},
        _stats = fresh_lower_stats(name),
    }, LOWER_CALL_MT)

    function boundary.stats() return boundary._stats end
    function boundary.reset()
        boundary._node_cache = setmetatable({}, { __mode = "k" })
        boundary._code_cache = {}
        boundary._state_cache = {}
        boundary._stats = fresh_lower_stats(boundary._name)
    end

    return boundary
end

-- ═══════════════════════════════════════════════════════════════
-- SLOT / RUNTIME
-- ═══════════════════════════════════════════════════════════════

function M.slot()
    -- A slot is the runtime installation point for one compiled machine.
    --
    -- Its callback is the clearest place to see the mgps triplet in action:
    --
    --   local gen   = bound.family.gen
    --   local param = bound.param
    --   local state = current.state
    --   return gen(param, state, input...)
    --
    -- If code shape and state shape stay the same across updates, the slot keeps
    -- the realized state and only swaps in the new bound payload.
    local current = {
        bound = nil,
        state = nil,
        code_shape = nil,
        state_shape = nil,
    }
    local retired = {}
    local slot = {}

    function slot.callback(...)
        local bound = current.bound
        if not bound then return nil end

        local gen = bound.family.gen
        local param = bound.param
        local state = current.state
        return run_triplet(gen, param, state, ...)
    end

    function slot:update(compiled)
        if not M.is_compiled(compiled) then
            error("mgps.slot:update: expected compiled mgps result", 2)
        end

        local bound = ensure_bound(compiled)
        local same_code = current.code_shape ~= nil and current.code_shape == bound.code_shape
        local same_state = current.state_shape ~= nil and current.state_shape == bound.state_shape

        if same_code and same_state then
            current.bound = bound
            return
        end

        if current.state and current.bound then
            retired[#retired + 1] = {
                state = current.state,
                layout = current.bound.family.state_layout,
            }
        end

        current.bound = bound
        current.state = bound.family.state_layout.alloc()
        current.code_shape = bound.code_shape
        current.state_shape = bound.state_shape
    end

    function slot:peek()
        return current.bound, current.state
    end

    function slot:collect()
        for i = 1, #retired do
            local r = retired[i]
            r.layout.release(r.state)
        end
        retired = {}
    end

    function slot:close()
        slot:collect()
        if current.state and current.bound then
            current.bound.family.state_layout.release(current.state)
        end
        current = { bound = nil, state = nil, code_shape = nil, state_shape = nil }
    end

    return slot
end

-- ═══════════════════════════════════════════════════════════════
-- STRUCTURAL HELPERS
-- ═══════════════════════════════════════════════════════════════

function M.with(node, overrides)
    local mt = getmetatable(node)
    if not mt or not mt.__fields then
        error("mgps.with: not an ASDL node", 2)
    end
    local fields = mt.__fields
    local args = {}
    for i = 1, #fields do
        local name = fields[i].name
        if overrides[name] ~= nil then
            args[i] = overrides[name]
        else
            args[i] = node[name]
        end
    end
    return mt(table.unpack(args, 1, #args))
end

-- ═══════════════════════════════════════════════════════════════
-- CONTEXT / ASDL AUTO-WIRING
-- ═══════════════════════════════════════════════════════════════

local AUTO_CONTAINER_METHOD_MT = {}
function AUTO_CONTAINER_METHOD_MT:__call(node, ...)
    local all = {}
    local child_fields = self.child_fields
    local defs = self.defs
    local mgps_key = self.mgps_key
    local verb_name = self.verb_name

    for _, cf in ipairs(child_fields) do
        local items = node[cf.name]
        if items then
            local parent_class = defs[cf.type_name]
            local dispatch = parent_class and rawget(parent_class, mgps_key)
            for i = 1, #items do
                local child = items[i]
                local result
                if dispatch then
                    result = dispatch(child, ...)
                elseif child[verb_name] then
                    result = child[verb_name](child, ...)
                end
                if result then all[#all + 1] = result end
            end
        end
    end

    if #all == 0 then
        local out = M.emit(EMPTY_GEN, NONE_DECL, {})
        out.code_shape = "empty"
        return out
    end
    if #all == 1 then return all[1] end
    return M.compose(all)
end

function M.context(verb)
    verb = verb or "compile"
    local T = asdl_context.NewContext()

    local orig_Define = T.Define
    function T:Define(text)
        orig_Define(self, text)
        self:_mgps_wire(verb)
        return self
    end

    function T:use(module)
        if type(module) == "string" then module = require(module) end
        if type(module) == "function" then module(self, M) end
        return self
    end

    function T:_mgps_wire(verb_name)
        local defs = self.definitions
        local mgps_key = "_mgps_" .. verb_name

        local sum_types = {}
        local containers = {}

        for name, class in pairs(defs) do
            if class.members then
                local variants = {}
                for member in pairs(class.members) do
                    if member ~= class then variants[#variants + 1] = member end
                end
                if #variants > 0 then
                    sum_types[name] = { parent = class, variants = variants }
                end
            end

            if class.__fields then
                local child_fields = {}
                for _, field in ipairs(class.__fields) do
                    if field.list and defs[field.type] then
                        child_fields[#child_fields + 1] = {
                            name = field.name,
                            type_name = field.type,
                        }
                    end
                end
                if #child_fields > 0 then
                    containers[name] = { class = class, child_fields = child_fields }
                end
            end
        end

        for name, info in pairs(sum_types) do
            local dispatch = M.lower(name .. ":" .. verb_name, function(node, ...)
                local method = node[verb_name]
                if not method then
                    error(name .. ":" .. verb_name .. ": no :" .. verb_name .. "() on " .. (node.kind or "?"), 2)
                end
                return stamp_code_shape(method(node, ...), node.kind or "")
            end)
            rawset(info.parent, mgps_key, dispatch)
        end

        for _, info in pairs(containers) do
            local class = info.class
            local child_fields = info.child_fields

            if not rawget(class, verb_name) then
                class[verb_name] = setmetatable({
                    child_fields = child_fields,
                    defs = defs,
                    mgps_key = mgps_key,
                    verb_name = verb_name,
                }, AUTO_CONTAINER_METHOD_MT)
            end
        end
    end

    return T
end

-- ═══════════════════════════════════════════════════════════════
-- APP LOOP
-- ═══════════════════════════════════════════════════════════════

function M.app(config)
    if type(config) ~= "table" then error("mgps.app: config must be a table", 2) end

    local names = {}
    if config.compile then
        for name in pairs(config.compile) do names[#names + 1] = name end
        table.sort(names)
    end

    local slots = {}
    for i = 1, #names do slots[names[i]] = M.slot() end
    local source = config.initial()

    for i = 1, #names do
        local name = names[i]
        slots[name]:update(config.compile[name](source))
    end

    if config.start then
        for i = 1, #names do
            local name = names[i]
            if config.start[name] then config.start[name](slots[name].callback) end
        end
    end

    while source.running ~= false do
        local event = config.poll and config.poll() or nil
        if not event then break end
        local new_source = config.apply(source, event)
        if new_source ~= source then
            source = new_source
            for i = 1, #names do
                local name = names[i]
                slots[name]:update(config.compile[name](source))
            end
        end
    end

    if config.stop then
        for i = 1, #names do
            local name = names[i]
            if config.stop[name] then config.stop[name]() end
        end
    end

    for i = 1, #names do slots[names[i]]:close() end
    return source
end

-- ═══════════════════════════════════════════════════════════════
-- DIAGNOSTICS
-- ═══════════════════════════════════════════════════════════════

function M.report(boundaries)
    local lines = {}
    for i = 1, #boundaries do
        local s = boundaries[i].stats()
        local code_total = s.code_hits + s.code_misses
        local state_total = s.state_hits + s.state_misses
        local code_pct = code_total > 0 and math.floor(s.code_hits / code_total * 100) or 0
        local state_pct = state_total > 0 and math.floor(s.state_hits / state_total * 100) or 0
        lines[#lines + 1] = string.format(
            "%-28s calls=%-6d node_hits=%-6d code_hits=%-4d code_misses=%-4d code_reuse=%d%% state_hits=%-4d state_misses=%-4d state_reuse=%d%%",
            s.name, s.calls, s.node_hits, s.code_hits, s.code_misses, code_pct,
            s.state_hits, s.state_misses, state_pct
        )
    end
    return table.concat(lines, "\n")
end

local function not_yet_ported(name)
    return function()
        error("gps." .. name .. " is not yet ported to the new mgps core", 2)
    end
end

M.lex = not_yet_ported("lex")
M.rd = not_yet_ported("rd")
M.grammar = not_yet_ported("grammar")
M.parse = not_yet_ported("parse")

return M
