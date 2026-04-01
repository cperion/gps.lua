-- gps/init.lua — Gen/Param/State framework
--
-- ASDL is a builtin. No external dependencies beyond LuaJIT.
--
-- Primary usage:
--
--   local GPS = require("gps")
--   local T = GPS.context()
--   T:Define [[ module Source { ... } ]]
--   function T.Source.Osc:compile(sr) return GPS.machine(gen, param, state) end
--   local machine = my_project:compile()
--
-- Low-level usage (no ASDL):
--
--   GPS.machine(gen, param, state_layout)
--   GPS.compose(children, body_fn)
--   GPS.slot()
--   GPS.lower(name, fn)
--   GPS.leaf(gen, state_layout, param_fn)
--   GPS.match(arms) / GPS.match(value, arms)
--   GPS.filter / GPS.take / GPS.map / GPS.fuse

local has_ffi, ffi = pcall(require, "ffi")
local asdl_context = require("gps.asdl_context")

local GPS = {}

-- ═══════════════════════════════════════════════════════════════
-- GPS MACHINE
-- ═══════════════════════════════════════════════════════════════

local EMPTY_STATE = {
    kind = "empty",
    alloc = function() return nil end,
    release = function() end,
}
GPS.EMPTY_STATE = EMPTY_STATE

function GPS.machine(gen, param, state_layout, gen_key)
    return {
        __gps = true,
        gen = gen,
        param = param,
        state_layout = state_layout or EMPTY_STATE,
        gen_key = gen_key,
    }
end

function GPS.is_machine(value)
    return type(value) == "table" and rawget(value, "__gps") == true
end

function GPS.state_ffi(ctype_str, opts)
    if not has_ffi then error("GPS.state_ffi: LuaJIT FFI required", 2) end
    opts = opts or {}
    local ctype = type(ctype_str) == "string" and ffi.typeof(ctype_str) or ctype_str
    return {
        kind = "ffi",
        alloc = function()
            local s = ffi.new(ctype)
            if opts.init then opts.init(s) end
            return s
        end,
        release = opts.release or function() end,
    }
end

function GPS.state_table(init, release)
    return {
        kind = "table",
        alloc = function()
            local s = {}
            if init then
                local r = init(s)
                if r ~= nil then s = r end
            end
            return s
        end,
        release = release or function() end,
    }
end

-- ═══════════════════════════════════════════════════════════════
-- GPS.lower — MEMOIZED BOUNDARY (two-level cache)
-- ═══════════════════════════════════════════════════════════════
--
-- Level 1: node identity → full result (unchanged siblings)
-- Level 2: gen_key → { gen, state_layout } (param-only changes)

function GPS.lower(name, fn)
    if type(name) == "function" and fn == nil then
        fn = name; name = "lower"
    end

    local node_cache = setmetatable({}, { __mode = "k" })
    local gen_cache = {}
    local stats = { name = name, calls = 0, node_hits = 0, gen_hits = 0, gen_misses = 0 }

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

        if GPS.is_machine(result) then
            local gk = result.gen_key or ""
            local entry = gen_cache[gk]
            if entry then
                stats.gen_hits = stats.gen_hits + 1
                result = GPS.machine(entry.gen, result.param, entry.state_layout, gk)
            else
                stats.gen_misses = stats.gen_misses + 1
                gen_cache[gk] = { gen = result.gen, state_layout = result.state_layout }
            end
        end

        if type(input) == "table" then
            node_cache[input] = result
        end
        return result
    end

    function boundary.stats() return stats end
    function boundary.reset()
        node_cache = setmetatable({}, { __mode = "k" })
        gen_cache = {}
        stats = { name = name, calls = 0, node_hits = 0, gen_hits = 0, gen_misses = 0 }
    end

    return setmetatable(boundary, boundary)
end

-- ═══════════════════════════════════════════════════════════════
-- GPS.slot — GEN-AWARE HOT SWAP
-- ═══════════════════════════════════════════════════════════════

function GPS.slot()
    local current = { machine = nil, state = nil, gen_key = nil }
    local retired = {}
    local slot = {}

    function slot.callback(...)
        local m = current.machine
        if m then return m.gen(m.param, current.state, ...) end
    end

    function slot:update(machine)
        if not GPS.is_machine(machine) then
            error("GPS.slot:update: expected GPS machine", 2)
        end
        if current.gen_key ~= nil and current.gen_key == machine.gen_key then
            current.machine = machine
        else
            if current.state and current.machine then
                retired[#retired + 1] = {
                    state = current.state, layout = current.machine.state_layout,
                }
            end
            current.machine = machine
            current.state = machine.state_layout.alloc()
            current.gen_key = machine.gen_key
        end
    end

    function slot:peek() return current.machine, current.state end
    function slot:collect()
        for i = 1, #retired do
            local r = retired[i]
            if r.layout and r.layout.release then r.layout.release(r.state) end
        end
        retired = {}
    end
    function slot:close()
        slot:collect()
        if current.state and current.machine then
            current.machine.state_layout.release(current.state)
        end
        current = { machine = nil, state = nil, gen_key = nil }
    end

    return slot
end

-- ═══════════════════════════════════════════════════════════════
-- GPS.compose — STRUCTURAL COMPOSITION WITH FUSION
-- ═══════════════════════════════════════════════════════════════

function GPS.compose(children, body_fn)
    local n = #children

    local key_parts = {}
    for i = 1, n do key_parts[i] = children[i].gen_key or "" end
    local composite_key = table.concat(key_parts, "|")

    local child_gens = {}
    for i = 1, n do child_gens[i] = children[i].gen end

    local gen
    if body_fn then
        gen = function(param, state, ...)
            return body_fn(child_gens, param, state, ...)
        end
    else
        gen = function(param, state, ...)
            local result = ...
            for i = 1, n do
                result = child_gens[i](param[i], state[i], result)
            end
            return result
        end
    end

    local param = {}
    for i = 1, n do param[i] = children[i].param end

    local state_layout = {
        kind = "compose",
        alloc = function()
            local states = {}
            for i = 1, n do states[i] = children[i].state_layout.alloc() end
            return states
        end,
        release = function(states)
            if not states then return end
            for i = n, 1, -1 do
                if states[i] and children[i].state_layout.release then
                    children[i].state_layout.release(states[i])
                end
            end
        end,
    }

    return GPS.machine(gen, param, state_layout, composite_key)
end

-- ═══════════════════════════════════════════════════════════════
-- GPS.leaf — CURRIED MACHINE BUILDER
-- ═══════════════════════════════════════════════════════════════

function GPS.leaf(gen, state_layout, param_fn)
    state_layout = state_layout or EMPTY_STATE
    return function(node, ...)
        return GPS.machine(gen, param_fn(node, ...), state_layout)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- GPS.match — EXHAUSTIVE DISPATCH
-- ═══════════════════════════════════════════════════════════════

function GPS.match(value_or_arms, arms)
    if arms ~= nil then
        local kind = value_or_arms.kind
        if kind == nil then error("GPS.match: value has no .kind", 2) end
        local arm = arms[kind]
        if type(arm) ~= "function" then
            error("GPS.match: missing arm for '" .. tostring(kind) .. "'", 2)
        end
        return arm(value_or_arms)
    end

    local curried_arms = value_or_arms
    return function(node, ...)
        local kind = node.kind
        if kind == nil then error("GPS.match: value has no .kind", 2) end
        local arm = curried_arms[kind]
        if type(arm) ~= "function" then
            error("GPS.match: missing arm for '" .. tostring(kind) .. "'", 2)
        end
        local result = arm(node, ...)
        if GPS.is_machine(result) and result.gen_key == nil then
            result.gen_key = kind
        end
        return result
    end
end

-- ═══════════════════════════════════════════════════════════════
-- GPS.with — STRUCTURAL SHARING
-- ═══════════════════════════════════════════════════════════════

function GPS.with(node, overrides)
    local mt = getmetatable(node)
    if not mt or not mt.__fields then
        error("GPS.with: not an ASDL node", 2)
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
-- GPS.errors — ERROR COLLECTION
-- ═══════════════════════════════════════════════════════════════

function GPS.errors()
    local self = { items = {} }
    function self:add(err)
        if err ~= nil then self.items[#self.items + 1] = err end
    end
    function self:merge(errs)
        if type(errs) == "table" and errs[1] ~= nil then
            for i = 1, #errs do self:add(errs[i]) end
        elseif errs ~= nil then
            self:add(errs)
        end
    end
    function self:call(target, fn, neutral_fn)
        local ok, result, errs = pcall(fn, target)
        if not ok then
            self:add(result)
            return neutral_fn and neutral_fn(target) or nil
        end
        self:merge(errs)
        return result
    end
    function self:each(items, fn, neutral_fn)
        local out = {}
        for i = 1, #items do
            local value = self:call(items[i], fn, neutral_fn)
            if value ~= nil then out[#out + 1] = value end
        end
        return out
    end
    function self:get()
        if #self.items == 0 then return nil end
        return self.items
    end
    return self
end

-- ═══════════════════════════════════════════════════════════════
-- ITERATION ALGEBRA
-- ═══════════════════════════════════════════════════════════════

function GPS.drive(gen, param, state)
    local last
    for s, v in gen, param, state do last = v end
    return last
end

function GPS.map(gen, param, state, fn)
    local function g(p, s)
        local ns, v = p.g(p.p, s)
        if ns == nil then return nil end
        return ns, fn(v)
    end
    return g, { g = gen, p = param }, state
end

function GPS.filter(gen, param, state, pred)
    local function g(p, s)
        while true do
            local ns, a, b, c, d = p.g(p.p, s)
            if ns == nil then return nil end
            if pred(a, b, c, d) then return ns, a, b, c, d end
            s = ns
        end
    end
    return g, { g = gen, p = param }, state
end

function GPS.take(gen, param, state, n)
    local function g(p, s)
        if s.c >= p.n then return nil end
        local ns, a, b, c, d = p.g(p.p, s.s)
        if ns == nil then return nil end
        return { s = ns, c = s.c + 1 }, a, b, c, d
    end
    return g, { g = gen, p = param, n = n }, { s = state, c = 0 }
end

function GPS.fuse(outer, inner_gen, inner_param, inner_state)
    local function g(p, s)
        local ns, v = p.ig(p.ip, s)
        if ns == nil then return nil end
        return ns, p.o(v)
    end
    return g, { o = outer, ig = inner_gen, ip = inner_param }, inner_state
end

-- ═══════════════════════════════════════════════════════════════
-- COLLECTION HELPERS
-- ═══════════════════════════════════════════════════════════════

function GPS.each(items, fn)
    if type(items) ~= "table" then return end
    for i = 1, #items do fn(items[i], i) end
end

function GPS.map_list(items, fn)
    local out = {}
    if type(items) == "table" then
        for i = 1, #items do out[i] = fn(items[i], i) end
    end
    return out
end

function GPS.fold(items, fn, init)
    local acc = init
    if type(items) == "table" then
        for i = 1, #items do acc = fn(acc, items[i], i) end
    end
    return acc
end

function GPS.find(items, pred)
    if type(items) ~= "table" then return nil end
    for i = 1, #items do
        if pred(items[i], i) then return items[i], i end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════
-- GPS.context — ASDL CONTEXT WITH GPS WIRING
-- ═══════════════════════════════════════════════════════════════

function GPS.context(verb)
    verb = verb or "compile"
    local T = asdl_context.NewContext()

    local orig_Define = T.Define
    function T:Define(text)
        orig_Define(self, text)
        self:_gps_wire(verb)
        return self
    end

    function T:use(module)
        if type(module) == "string" then module = require(module) end
        if type(module) == "function" then module(self, GPS) end
        return self
    end

    function T:_gps_wire(verb)
        local defs = self.definitions
        local gps_key = "_gps_" .. verb

        local sum_types = {}
        local containers = {}

        for name, class in pairs(defs) do
            if class.members then
                local variants = {}
                for member in pairs(class.members) do
                    if member ~= class then
                        variants[#variants + 1] = member
                    end
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
            local dispatch = GPS.lower(name .. ":" .. verb, function(node, ...)
                local method = node[verb]
                if not method then
                    error(name .. ":" .. verb .. ": no :" .. verb .. "() on " .. (node.kind or "?"), 2)
                end
                local result = method(node, ...)
                if GPS.is_machine(result) and result.gen_key == nil then
                    result.gen_key = node.kind or ""
                end
                return result
            end)
            rawset(info.parent, gps_key, dispatch)
        end

        for name, info in pairs(containers) do
            local class = info.class
            local child_fields = info.child_fields

            if not rawget(class, verb) then
                class[verb] = function(node, ...)
                    local all = {}
                    for _, cf in ipairs(child_fields) do
                        local items = node[cf.name]
                        if items then
                            local parent_class = defs[cf.type_name]
                            local gps_dispatch = parent_class and rawget(parent_class, gps_key)
                            for i = 1, #items do
                                local child = items[i]
                                local result
                                if gps_dispatch then
                                    result = gps_dispatch(child, ...)
                                elseif child[verb] then
                                    result = child[verb](child, ...)
                                end
                                if result then all[#all + 1] = result end
                            end
                        end
                    end
                    if #all == 0 then return GPS.machine(function() end, {}, EMPTY_STATE, "empty") end
                    if #all == 1 then return all[1] end
                    return GPS.compose(all)
                end
            end
        end
    end

    return T
end

-- ═══════════════════════════════════════════════════════════════
-- GPS.app — THE LIVE LOOP
-- ═══════════════════════════════════════════════════════════════

function GPS.app(config)
    if type(config) ~= "table" then error("GPS.app: config must be a table", 2) end

    local names = {}
    if config.compile then
        for name in pairs(config.compile) do names[#names + 1] = name end
        table.sort(names)
    end

    local slots = {}
    for i = 1, #names do slots[names[i]] = GPS.slot() end
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
-- GPS.report — DIAGNOSTICS
-- ═══════════════════════════════════════════════════════════════

function GPS.report(boundaries)
    local lines = {}
    for i = 1, #boundaries do
        local s = boundaries[i].stats()
        local total = s.gen_hits + s.gen_misses
        local pct = total > 0 and math.floor(s.gen_hits / total * 100) or 0
        lines[#lines + 1] = string.format(
            "%-30s calls=%-6d node_hits=%-6d gen_hits=%-4d gen_misses=%-4d gen_reuse=%d%%",
            s.name, s.calls, s.node_hits, s.gen_hits, s.gen_misses, pct
        )
    end
    return table.concat(lines, "\n")
end

return GPS
