-- mgps v3 — flat command runtime with one more lowering pass
--
-- Architecture:
--   ASDL tree
--     -> lower(...) structural boundary
--     -> flat command array
--     -> specialized slot runner
--
-- The triple in this runtime normal form is:
--   gen   = backend-specialized fixed-arity loop
--   param = specialized runtime command array
--   state = explicit stacks + resource table
--
-- Public API:
--   M.context(name?)
--   M.with(node, overrides)
--   M.lower(name, fn)
--   M.backend(name, spec)
--   M.slot(backend_name_or_handlers)
--   M.report(items)
--
-- Backend spec:
--   {
--     _meta = {
--       arity = 0|1|2,          -- optional hot-path specialization hint
--       stacks = { ... },       -- optional declared stack names
--     },
--
--     KindName = function(cmd, ctx, resource, ...) end,
--
--     ResourceKind = {
--       run = function(cmd, ctx, resource, ...) end,
--       resource = {
--         key = function(cmd) return comparable_key end,
--         alloc = function(cmd) return resource_value end,
--         release = function(resource) end, -- optional
--       },
--     },
--   }
--
-- The generic :run(...) fallback remains, but the hot path should prefer
-- :run0(), :run1(a), or :run2(a, b).

local has_ffi, ffi = pcall(require, "ffi")

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
end
if not package.preload["gps.asdl_parser"] then
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
end
if not package.preload["gps.asdl_context"] then
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local asdl_context = require("gps.asdl_context")
local unpack = table.unpack or unpack

local M = {}

-- ═══════════════════════════════════════════════════════════════
-- CONTEXT — define ASDL types
-- ═══════════════════════════════════════════════════════════════

function M.context(_)
    local T = asdl_context.NewContext()

    local orig_Define = T.Define
    function T:Define(text)
        orig_Define(self, text)
        return self
    end

    function T:use(mod)
        if type(mod) == "string" then mod = require(mod) end
        if type(mod) == "function" then mod(self, M) end
        return self
    end

    return T
end

-- ═══════════════════════════════════════════════════════════════
-- STRUCTURAL HELPER
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
        args[i] = overrides[name] ~= nil and overrides[name] or node[name]
    end
    return mt(unpack(args, 1, #args))
end

-- ═══════════════════════════════════════════════════════════════
-- LOWER — memoized structural boundary
-- ═══════════════════════════════════════════════════════════════

function M.lower(name, fn)
    if type(name) == "function" and fn == nil then
        fn = name
        name = "lower"
    end

    local node_cache = setmetatable({}, { __mode = "k" })
    local stats = { name = name, calls = 0, node_hits = 0 }

    local boundary = {}

    function boundary:__call(input, ...)
        stats.calls = stats.calls + 1

        if select("#", ...) == 0 and type(input) == "table" then
            local cached = node_cache[input]
            if cached ~= nil then
                stats.node_hits = stats.node_hits + 1
                return cached
            end
        end

        local result = fn(input, ...)

        if type(input) == "table" then
            node_cache[input] = result
        end
        return result
    end

    function boundary:stats()
        return stats
    end

    function boundary:reset()
        node_cache = setmetatable({}, { __mode = "k" })
        stats = { name = name, calls = 0, node_hits = 0 }
    end

    return setmetatable(boundary, boundary)
end

-- ═══════════════════════════════════════════════════════════════
-- BACKEND NORMALIZATION / SPECIALIZATION
-- ═══════════════════════════════════════════════════════════════

local registered_backends = {}

local function compile_chunk(src, env, chunkname)
    if loadstring then
        local f, err = loadstring(src, chunkname)
        if not f then error(err, 2) end
        if setfenv then setfenv(f, env) end
        return f()
    end
    local f, err = load(src, chunkname, "t", env)
    if not f then error(err, 2) end
    return f()
end

local function shallow_copy_command(cmd)
    local out = {}
    for k, v in pairs(cmd) do out[k] = v end
    return out
end

local function build_ctx(stack_names)
    local stack_count = #stack_names
    local stack_ids = {}
    local fixed_stacks = {}
    local fixed_tops = {}
    local named_stacks = {}

    for i = 1, stack_count do
        local name = stack_names[i]
        stack_ids[name] = i
        fixed_stacks[i] = {}
        fixed_tops[i] = 0
        named_stacks[name] = fixed_stacks[i]
    end

    local extra_stacks = {}
    local extra_tops = {}

    local ctx = {
        stacks = named_stacks,
        _stack_ids = stack_ids,
        _fixed_stacks = fixed_stacks,
        _fixed_tops = fixed_tops,
        _extra_stacks = extra_stacks,
        _extra_tops = extra_tops,
    }

    function ctx:push(name, frame)
        local id = stack_ids[name]
        if id ~= nil then
            local n = fixed_tops[id] + 1
            fixed_tops[id] = n
            fixed_stacks[id][n] = frame
            return frame
        end

        local s = extra_stacks[name]
        if not s then
            s = {}
            extra_stacks[name] = s
            extra_tops[name] = 0
            named_stacks[name] = s
        end
        local n = extra_tops[name] + 1
        extra_tops[name] = n
        s[n] = frame
        return frame
    end

    function ctx:pop(name)
        local id = stack_ids[name]
        if id ~= nil then
            local n = fixed_tops[id]
            if n > 0 then
                local s = fixed_stacks[id]
                local v = s[n]
                s[n] = nil
                fixed_tops[id] = n - 1
                return v
            end
            return nil
        end

        local n = extra_tops[name] or 0
        if n > 0 then
            local s = extra_stacks[name]
            local v = s[n]
            s[n] = nil
            extra_tops[name] = n - 1
            return v
        end
        return nil
    end

    function ctx:peek(name)
        local id = stack_ids[name]
        if id ~= nil then
            local n = fixed_tops[id]
            return n > 0 and fixed_stacks[id][n] or nil
        end

        local n = extra_tops[name] or 0
        return n > 0 and extra_stacks[name][n] or nil
    end

    function ctx:depth(name)
        local id = stack_ids[name]
        if id ~= nil then return fixed_tops[id] end
        return extra_tops[name] or 0
    end

    for i = 1, stack_count do
        local name = stack_names[i]
        if name:match("^[_%a][_%w]*$") then
            local s = fixed_stacks[i]
            local top = fixed_tops
            local id = i
            ctx["push_" .. name] = function(self, frame)
                local n = top[id] + 1
                top[id] = n
                s[n] = frame
                return frame
            end
            ctx["pop_" .. name] = function(self)
                local n = top[id]
                if n > 0 then
                    local v = s[n]
                    s[n] = nil
                    top[id] = n - 1
                    return v
                end
                return nil
            end
            ctx["peek_" .. name] = function(self)
                local n = top[id]
                return n > 0 and s[n] or nil
            end
            ctx["depth_" .. name] = function(self)
                return top[id]
            end
        end
    end

    local function reset_stacks()
        for i = 1, stack_count do
            local top = fixed_tops[i]
            if top > 0 then
                local s = fixed_stacks[i]
                for j = top, 1, -1 do s[j] = nil end
                fixed_tops[i] = 0
            end
        end
        for name, top in pairs(extra_tops) do
            if top > 0 then
                local s = extra_stacks[name]
                for j = top, 1, -1 do s[j] = nil end
                extra_tops[name] = 0
            end
        end
    end

    return ctx, reset_stacks
end

local function make_specialized_runner(backend, arity)
    local src = {}
    src[#src + 1] = "return function(slot"
    if arity >= 1 then src[#src + 1] = ", a" end
    if arity >= 2 then src[#src + 1] = ", b" end
    src[#src + 1] = ")\n"
    src[#src + 1] = "  local cmds = slot._cmds\n"
    src[#src + 1] = "  if not cmds then return nil end\n"
    src[#src + 1] = "  local stats = slot._stats\n"
    src[#src + 1] = "  stats.runs = stats.runs + 1\n"
    src[#src + 1] = "  slot._reset_stacks()\n"
    src[#src + 1] = "  local ctx = slot._ctx\n"
    src[#src + 1] = "  local n = slot._cmd_count\n"
    src[#src + 1] = "  for i = 1, n do\n"
    src[#src + 1] = "    local cmd = cmds[i]\n"
    src[#src + 1] = "    local op = cmd.op\n"
    src[#src + 1] = "    local result\n"

    if #backend.ops == 0 then
        src[#src + 1] = "    result = nil\n"
    else
        for i = 1, #backend.ops do
            if i == 1 then
                src[#src + 1] = string.format("    if op == %d then\n", i)
            else
                src[#src + 1] = string.format("    elseif op == %d then\n", i)
            end
            if arity == 0 then
                src[#src + 1] = string.format("      result = run_%d(cmd, ctx, cmd.res)\n", i)
            elseif arity == 1 then
                src[#src + 1] = string.format("      result = run_%d(cmd, ctx, cmd.res, a)\n", i)
            else
                src[#src + 1] = string.format("      result = run_%d(cmd, ctx, cmd.res, a, b)\n", i)
            end
        end
        src[#src + 1] = "    end\n"
    end

    src[#src + 1] = "    if result ~= nil then return result end\n"
    src[#src + 1] = "  end\n"
    src[#src + 1] = "  return nil\n"
    src[#src + 1] = "end\n"

    local env = {}
    for i = 1, #backend.ops do
        env["run_" .. i] = backend.ops[i].run
    end
    return compile_chunk(table.concat(src), env, "=(mgps.init3.runner." .. backend.name .. "." .. arity .. ")")
end

local function normalize_backend(name, spec)
    local meta = rawget(spec, "_meta") or {}
    local ops = {}
    local kind_to_opcode = {}

    for kind, v in pairs(spec) do
        if kind ~= "_meta" then
            local op
            if type(v) == "function" then
                op = { kind = kind, run = v, resource = nil }
            elseif type(v) == "table" then
                op = {
                    kind = kind,
                    run = v.run or v[1],
                    resource = v.resource or nil,
                }
            end
            if op then
                if type(op.run) ~= "function" then
                    error("mgps.backend(" .. tostring(name) .. "): command " .. tostring(kind) .. " is missing a run function", 2)
                end
                ops[#ops + 1] = op
                kind_to_opcode[kind] = #ops
            end
        end
    end

    local backend = {
        name = name,
        meta = meta,
        arity = meta.arity,
        stack_names = meta.stacks or {},
        ops = ops,
        kind_to_opcode = kind_to_opcode,
    }

    backend.run0 = make_specialized_runner(backend, 0)
    backend.run1 = make_specialized_runner(backend, 1)
    backend.run2 = make_specialized_runner(backend, 2)

    registered_backends[name] = backend
    return backend
end

function M.backend(name, spec)
    return normalize_backend(name, spec)
end

-- ═══════════════════════════════════════════════════════════════
-- SLOT — flat command executor with specialized runners
-- ═══════════════════════════════════════════════════════════════

function M.slot(backend_name_or_handlers)
    local backend
    if type(backend_name_or_handlers) == "string" then
        backend = registered_backends[backend_name_or_handlers]
        if not backend then
            error("mgps.slot: unknown backend '" .. backend_name_or_handlers .. "'", 2)
        end
    elseif type(backend_name_or_handlers) == "table" then
        if backend_name_or_handlers.ops and backend_name_or_handlers.kind_to_opcode then
            backend = backend_name_or_handlers
        else
            backend = normalize_backend("<anonymous>", backend_name_or_handlers)
        end
    else
        error("mgps.slot: expected backend name or handler table", 2)
    end

    local ctx, reset_stacks = build_ctx(backend.stack_names)

    local source_cmds = nil
    local cur_cmds = nil
    local cur_res_slots = {}
    local stats = {
        updates = 0,
        skipped = 0,
        runs = 0,
        res_allocs = 0,
        res_reuses = 0,
        res_releases = 0,
    }

    local slot = {
        _backend = backend,
        _ctx = ctx,
        _reset_stacks = reset_stacks,
        _cmds = nil,
        _cmd_count = 0,
        _stats = stats,
    }

    local function reconcile_resources(cmds)
        local old_pool = {}
        for i, r in pairs(cur_res_slots) do
            local k = r.key
            if k ~= nil then
                local bucket = old_pool[k]
                if not bucket then
                    bucket = {}
                    old_pool[k] = bucket
                end
                bucket[#bucket + 1] = { value = r.value, release = r.release }
            end
        end

        local new_res_slots = {}
        for i = 1, #cmds do
            local cmd = cmds[i]
            local opcode = backend.kind_to_opcode[cmd.kind]
            if opcode == nil then
                error("mgps.slot:update: unknown command kind '" .. tostring(cmd.kind) .. "' for backend '" .. tostring(backend.name) .. "'", 2)
            end

            local op = backend.ops[opcode]
            local res_value = nil
            if op.resource then
                local key = op.resource.key(cmd)
                local bucket = old_pool[key]
                if bucket and #bucket > 0 then
                    local entry = bucket[#bucket]
                    bucket[#bucket] = nil
                    new_res_slots[i] = { key = key, value = entry.value, release = op.resource.release }
                    res_value = entry.value
                    stats.res_reuses = stats.res_reuses + 1
                else
                    local value = op.resource.alloc(cmd)
                    new_res_slots[i] = { key = key, value = value, release = op.resource.release }
                    res_value = value
                    stats.res_allocs = stats.res_allocs + 1
                end
            end

            local rt = shallow_copy_command(cmd)
            rt.op = opcode
            rt.res = res_value
            cmds[i] = rt
        end

        for _, bucket in pairs(old_pool) do
            for j = 1, #bucket do
                local entry = bucket[j]
                if entry.release then entry.release(entry.value) end
                stats.res_releases = stats.res_releases + 1
            end
        end

        cur_res_slots = new_res_slots
        return cmds
    end

    function slot:update(cmds)
        stats.updates = stats.updates + 1

        if cmds == source_cmds then
            stats.skipped = stats.skipped + 1
            return false
        end

        source_cmds = cmds
        cur_cmds = reconcile_resources(shallow_copy_command(cmds))
        slot._cmds = cur_cmds
        slot._cmd_count = #cur_cmds
        return true
    end

    function slot:run0()
        return backend.run0(self)
    end

    function slot:run1(a)
        return backend.run1(self, a)
    end

    function slot:run2(a, b)
        return backend.run2(self, a, b)
    end

    function slot:run(...)
        local argc = select("#", ...)
        if argc == 0 then
            return self:run0()
        elseif argc == 1 then
            return self:run1((...))
        elseif argc == 2 then
            local a, b = ...
            return self:run2(a, b)
        end

        if not self._cmds then return nil end
        stats.runs = stats.runs + 1
        reset_stacks()
        local ctx_local = ctx
        local cmds_local = self._cmds
        for i = 1, self._cmd_count do
            local cmd = cmds_local[i]
            local op = backend.ops[cmd.op]
            local result = op.run(cmd, ctx_local, cmd.res, ...)
            if result ~= nil then return result end
        end
        return nil
    end

    function slot:close()
        for _, r in pairs(cur_res_slots) do
            if r.release then r.release(r.value) end
            stats.res_releases = stats.res_releases + 1
        end
        cur_res_slots = {}
        source_cmds = nil
        cur_cmds = nil
        self._cmds = nil
        self._cmd_count = 0
        reset_stacks()
    end

    function slot:cmd_count()
        return self._cmd_count or 0
    end

    function slot:stats()
        return stats
    end

    return slot
end

-- ═══════════════════════════════════════════════════════════════
-- REPORT — diagnostics
-- ═══════════════════════════════════════════════════════════════

function M.report(items)
    local lines = {}
    for i = 1, #items do
        local item = items[i]
        local s
        if item.stats and type(item.stats) == "function" then
            s = item:stats()
        else
            s = item.stats()
        end

        if s.name then
            lines[#lines + 1] = string.format(
                "  %-24s calls=%-6d node_hits=%-6d hit_rate=%d%%",
                s.name,
                s.calls or 0,
                s.node_hits or 0,
                (s.calls or 0) > 0 and math.floor((s.node_hits or 0) / s.calls * 100) or 0)
        else
            lines[#lines + 1] = string.format(
                "  slot[%d]: updates=%d skipped=%d runs=%d alloc=%d reuse=%d release=%d cmds=%d",
                i,
                s.updates or 0,
                s.skipped or 0,
                s.runs or 0,
                s.res_allocs or 0,
                s.res_reuses or 0,
                s.res_releases or 0,
                item.cmd_count and item:cmd_count() or 0)
        end
    end
    return table.concat(lines, "\n")
end

return M
