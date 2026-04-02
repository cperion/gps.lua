-- mgps v2 — flat command path only
--
-- The GPS triple in normal form:
--   gen   = one loop over a flat command array
--   param = the command array itself
--   state = stacks (derived from push/pop) + resource table
--
-- Public API:
--   M.context()             — ASDL context (define types)
--   M.lower(name, fn)       — memoized structural boundary
--   M.backend(name, spec)   — register command dispatch + resources
--   M.slot(backend)          — flat command slot (one loop, one stack)
--   M.with(node, overrides)  — structural ASDL update
--   M.report(slots_or_lowers) — diagnostics

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

local M = {}

-- ═══════════════════════════════════════════════════════════════
-- CONTEXT — define ASDL types
-- ═══════════════════════════════════════════════════════════════

function M.context()
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
    return mt(table.unpack(args, 1, #args))
end

-- ═══════════════════════════════════════════════════════════════
-- LOWER — memoized structural boundary
--
-- Caches by input identity (interned ASDL node).
-- Same interned tree → return cached result → skip entire walk.
-- This is where subtree-level work skipping lives.
-- ═══════════════════════════════════════════════════════════════

function M.lower(name, fn)
    if type(name) == "function" and fn == nil then
        fn = name; name = "lower"
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

    function boundary.stats() return stats end
    function boundary.reset()
        node_cache = setmetatable({}, { __mode = "k" })
        stats = { name = name, calls = 0, node_hits = 0 }
    end

    return setmetatable(boundary, boundary)
end

-- ═══════════════════════════════════════════════════════════════
-- BACKEND — register command dispatch
--
-- Simple command:
--   KindName = function(cmd, ctx, resource, ...) end
--
-- Resource command:
--   KindName = {
--       run = function(cmd, ctx, resource, ...) end,
--       resource = {
--           key = function(cmd) return comparable_key end,
--           alloc = function(cmd) return resource_value end,
--           release = function(resource) end,  -- optional
--       },
--   }
-- ═══════════════════════════════════════════════════════════════

local registered_backends = {}

function M.backend(name, spec)
    local handlers = {}
    for kind, v in pairs(spec) do
        if type(v) == "function" then
            handlers[kind] = { run = v, resource = nil }
        elseif type(v) == "table" then
            handlers[kind] = {
                run = v.run or v[1],
                resource = v.resource or nil,
            }
        end
    end
    registered_backends[name] = handlers
    return handlers
end

-- ═══════════════════════════════════════════════════════════════
-- SLOT — flat command executor
--
-- One loop. One stack (per push/pop kind). Resource table.
--
--   local slot = M.slot("paint")
--   slot:update(cmds)   -- install flat Cmd*, reconcile resources
--   slot:run(...)        -- execute: one loop with dispatch
--   slot:close()         -- release all resources
-- ═══════════════════════════════════════════════════════════════

function M.slot(backend_name_or_handlers)
    local handlers
    if type(backend_name_or_handlers) == "string" then
        handlers = registered_backends[backend_name_or_handlers]
        if not handlers then
            error("mgps.slot: unknown backend '" .. backend_name_or_handlers .. "'", 2)
        end
    elseif type(backend_name_or_handlers) == "table" then
        handlers = backend_name_or_handlers
    else
        error("mgps.slot: expected backend name or handler table", 2)
    end

    local cur_cmds = nil
    local res_slots = {}
    local stats = {
        updates = 0, skipped = 0, runs = 0,
        res_allocs = 0, res_reuses = 0, res_releases = 0,
    }

    -- Reusable context with stack helpers
    local ctx_stacks = {}
    local ctx = { stacks = ctx_stacks }

    function ctx:push(name, frame)
        local s = ctx_stacks[name]
        if not s then s = {}; ctx_stacks[name] = s end
        s[#s + 1] = frame
    end
    function ctx:pop(name)
        local s = ctx_stacks[name]
        if s and #s > 0 then local f = s[#s]; s[#s] = nil; return f end
    end
    function ctx:peek(name)
        local s = ctx_stacks[name]
        return s and s[#s] or nil
    end
    function ctx:depth(name)
        local s = ctx_stacks[name]
        return s and #s or 0
    end

    local function reset_stacks()
        for _, s in pairs(ctx_stacks) do
            for i = #s, 1, -1 do s[i] = nil end
        end
    end

    local slot = {}

    function slot:update(cmds)
        stats.updates = stats.updates + 1
        if cmds == cur_cmds then
            stats.skipped = stats.skipped + 1
            return false
        end

        -- Pool old resources by key
        local old_pool = {}
        for i, r in pairs(res_slots) do
            local k = r.key
            if k ~= nil then
                local bucket = old_pool[k]
                if not bucket then bucket = {}; old_pool[k] = bucket end
                bucket[#bucket + 1] = { value = r.value, release = r.release }
            end
        end

        -- Assign resources to new commands
        local new_res = {}
        for i = 1, #cmds do
            local cmd = cmds[i]
            local h = handlers[cmd.kind]
            if h and h.resource then
                local key = h.resource.key(cmd)
                local bucket = old_pool[key]
                if bucket and #bucket > 0 then
                    local entry = bucket[#bucket]; bucket[#bucket] = nil
                    new_res[i] = { key = key, value = entry.value, release = h.resource.release }
                    stats.res_reuses = stats.res_reuses + 1
                else
                    new_res[i] = {
                        key = key,
                        value = h.resource.alloc(cmd),
                        release = h.resource.release,
                    }
                    stats.res_allocs = stats.res_allocs + 1
                end
            end
        end

        -- Release unclaimed
        for _, bucket in pairs(old_pool) do
            for _, entry in ipairs(bucket) do
                if entry.release then entry.release(entry.value) end
                stats.res_releases = stats.res_releases + 1
            end
        end

        res_slots = new_res
        cur_cmds = cmds
        return true
    end

    function slot:run(...)
        if not cur_cmds then return nil end
        stats.runs = stats.runs + 1
        reset_stacks()
        local cmds = cur_cmds
        for i = 1, #cmds do
            local cmd = cmds[i]
            local h = handlers[cmd.kind]
            if h then
                local res = res_slots[i]
                local result = h.run(cmd, ctx, res and res.value or nil, ...)
                if result ~= nil then return result end
            end
        end
        return nil
    end

    function slot:close()
        for _, r in pairs(res_slots) do
            if r.release then r.release(r.value) end
            stats.res_releases = stats.res_releases + 1
        end
        res_slots = {}
        cur_cmds = nil
        reset_stacks()
    end

    function slot:cmd_count()
        return cur_cmds and #cur_cmds or 0
    end

    slot.stats = function() return stats end

    return slot
end

-- ═══════════════════════════════════════════════════════════════
-- REPORT — diagnostics
-- ═══════════════════════════════════════════════════════════════

function M.report(items)
    local lines = {}
    for i = 1, #items do
        local s = items[i].stats and items[i]:stats() or items[i].stats()
        if s.name then
            -- lower boundary
            lines[#lines + 1] = string.format(
                "  %-24s calls=%-6d node_hits=%-6d hit_rate=%d%%",
                s.name, s.calls, s.node_hits,
                s.calls > 0 and math.floor(s.node_hits / s.calls * 100) or 0)
        else
            -- slot
            lines[#lines + 1] = string.format(
                "  slot[%d]: updates=%d skipped=%d runs=%d alloc=%d reuse=%d release=%d cmds=%d",
                i, s.updates or 0, s.skipped or 0, s.runs or 0,
                s.res_allocs or 0, s.res_reuses or 0, s.res_releases or 0,
                items[i].cmd_count and items[i]:cmd_count() or 0)
        end
    end
    return table.concat(lines, "\n")
end

return M
