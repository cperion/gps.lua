-- asdl/context.lua — ASDL context builder
--
-- Takes the parse output (list of definitions) and creates live types:
--   - constructors (callable classes)
--   - unique interning (structural sharing)
--   - sum type dispatch (members, kind)
--   - field metadata (__fields)
--   - method propagation (__newindex on sum parents)
--   - isclassof checks
--
-- No List type. Plain Lua tables are lists.
--   Device* devices = { osc, filter, gain }

local M = {}

-- ── Builtin type checks ─────────────────────────────────────

local builtin_checks = {}
for _, name in ipairs({ "nil", "number", "string", "boolean", "table", "function", "cdata" }) do
    builtin_checks[name] = function(v) return type(v) == name end
end
builtin_checks["any"] = function() return true end

-- ── Context ──────────────────────────────────────────────────

local Context = {}
function Context:__index(key)
    return self.definitions[key] or self.namespaces[key] or Context[key]
end

local function basename(name)
    return name:match("([^.]*)$")
end

function Context:_SetDefinition(name, value)
    local ns = self.namespaces
    for part in name:gmatch("([^.]*)%.") do
        ns[part] = ns[part] or {}
        ns = ns[part]
    end
    ns[basename(name)] = value
    self.definitions[name] = value
end

function Context:Extern(name, check_fn)
    self.checks[name] = check_fn
end

-- ── Field checking ───────────────────────────────────────────

local nilkey = {}

local function make_check(ctx, field, unique)
    local type_name = field.type
    local check = ctx.checks[type_name]
    if not check then
        error("ASDL: unknown type '" .. type_name .. "' in field '" .. (field.name or "?") .. "'")
    end

    if field.list then
        if unique then
            -- Unique list interning: same elements → same table object.
            -- Uses element-walk trie to find or create the canonical list.
            -- The interned list is then used as a single key in the parent's trie.
            local intern_trie = {}
            local seen = setmetatable({}, { __mode = "kv" })  -- fast path: table identity
            return function(vs)
                if type(vs) ~= "table" then return false end
                -- Fast: same table object seen before?
                local hit = seen[vs]
                if hit then return true, hit end
                -- Slow: walk elements
                local node = intern_trie
                local len = #vs
                local next = node[len]
                if not next then next = {}; node[len] = next end
                node = next
                for i = 1, len do
                    local elem = vs[i]
                    if not check(elem) then return false, i end
                    local key = elem
                    if key == nil then key = nilkey end
                    next = node[key]
                    if not next then next = {}; node[key] = next end
                    node = next
                end
                local existing = node[nilkey]
                if not existing then
                    local interned = {}
                    for i = 1, len do interned[i] = vs[i] end
                    node[nilkey] = interned
                    existing = interned
                end
                seen[vs] = existing
                return true, existing
            end, type_name .. "*"
        else
            return function(vs)
                if type(vs) ~= "table" then return false end
                for i = 1, #vs do
                    if not check(vs[i]) then return false, i end
                end
                return true
            end, type_name .. "*"
        end
    elseif field.optional then
        return function(v) return v == nil or check(v) end, type_name .. "?"
    else
        return check, type_name
    end
end

-- ── Class building ───────────────────────────────────────────

local function build_class(ctx, name, unique, fields)
    local class = ctx.definitions[name]
    class.__fields = fields
    class.__index = class
    class.members = class.members or {}
    class.members[class] = true

    local mt = {}

    if fields then
        -- Resolve field types
        for _, f in ipairs(fields) do
            if f.namespace then
                local fq = f.namespace .. f.type
                if ctx.definitions[fq] then f.type = fq end
                f.namespace = nil
            end
        end

        -- Build field names, checks, type names
        local names, checks, type_names = {}, {}, {}
        for i, f in ipairs(fields) do
            names[i] = f.name
            checks[i], type_names[i] = make_check(ctx, f, unique)
        end
        local n = #names

        -- Detect fast-path: all fields are builtins (no list, no optional, no ASDL types)
        local all_builtin = true
        for i = 1, n do
            if fields[i].list or fields[i].optional then all_builtin = false end
            if not builtin_checks[fields[i].type] then all_builtin = false end
        end

        -- Constructor
        if unique then
            local cache = {}
            if all_builtin then
                -- Fast path: no type checks, direct trie walk
                function mt:__call(...)
                    local node, key = cache, nilkey
                    for i = 1, n do
                        local next = node[key]
                        if not next then next = {}; node[key] = next end
                        node = next
                        key = select(i, ...)
                        if key == nil then key = nilkey end
                    end
                    local existing = node[key]
                    if not existing then
                        local obj = {}
                        for i = 1, n do obj[names[i]] = select(i, ...) end
                        existing = setmetatable(obj, self)
                        node[key] = existing
                    end
                    return existing
                end
            else
                function mt:__call(...)
                    local obj = {}
                    local node, key = cache, nilkey
                    for i = 1, n do
                        local v = select(i, ...)
                        local ok, interned = checks[i](v)
                        if not ok then
                            error(string.format("bad arg #%d to '%s': expected '%s' got '%s'%s",
                                i, name, type_names[i], type(v),
                                interned and (" at index " .. interned) or ""), 2)
                        end
                        v = interned or v
                        obj[names[i]] = v
                        local next = node[key]
                        if not next then next = {}; node[key] = next end
                        node = next
                        key = v
                        if key == nil then key = nilkey end
                    end
                    local existing = node[key]
                    if not existing then
                        existing = setmetatable(obj, self)
                        node[key] = existing
                    end
                    return existing
                end
            end
        else
            if all_builtin then
                function mt:__call(...)
                    local obj = {}
                    for i = 1, n do obj[names[i]] = select(i, ...) end
                    return setmetatable(obj, self)
                end
            else
                function mt:__call(...)
                    local obj = {}
                    for i = 1, n do
                        local v = select(i, ...)
                        local ok, idx = checks[i](v)
                        if not ok then
                            error(string.format("bad arg #%d to '%s': expected '%s' got '%s'%s",
                                i, name, type_names[i], type(v),
                                idx and (" at index " .. idx) or ""), 2)
                        end
                        obj[names[i]] = v
                    end
                    return setmetatable(obj, self)
                end
            end
        end

        -- __tostring
        function class:__tostring()
            local parts = {}
            for i, f in ipairs(fields) do
                local v = self[f.name]
                if v ~= nil or not f.optional then
                    if f.list then
                        local elems = {}
                        for j = 1, #v do elems[j] = tostring(v[j]) end
                        parts[#parts + 1] = f.name .. " = {" .. table.concat(elems, ",") .. "}"
                    else
                        parts[#parts + 1] = f.name .. " = " .. tostring(v)
                    end
                end
            end
            return name .. "(" .. table.concat(parts, ", ") .. ")"
        end
    else
        function class:__tostring() return name end
    end

    -- Method propagation
    function mt:__newindex(k, v)
        for member in pairs(self.members) do
            rawset(member, k, v)
        end
    end

    function mt:__tostring() return string.format("Class(%s)", name) end

    function class:isclassof(obj)
        return self.members[getmetatable(obj) or false] or false
    end

    setmetatable(class, mt)
    return class
end

-- ── Define: process parsed definitions ───────────────────────

function M.define(ctx, definitions)
    -- Phase 1: declare all classes
    for _, d in ipairs(definitions) do
        ctx.definitions[d.name] = ctx.definitions[d.name] or { members = {} }
        ctx.checks[d.name] = function(v)
            return (ctx.definitions[d.name].members or {})[getmetatable(v) or false] or false
        end
        ctx:_SetDefinition(d.name, ctx.definitions[d.name])

        if d.type.kind == "sum" then
            for _, c in ipairs(d.type.constructors) do
                ctx.definitions[c.name] = ctx.definitions[c.name] or { members = {} }
                ctx.checks[c.name] = function(v)
                    return (ctx.definitions[c.name].members or {})[getmetatable(v) or false] or false
                end
                ctx:_SetDefinition(c.name, ctx.definitions[c.name])
            end
        end
    end

    -- Phase 2: build classes
    for _, d in ipairs(definitions) do
        if d.type.kind == "sum" then
            local parent = build_class(ctx, d.name, false, nil)
            for _, c in ipairs(d.type.constructors) do
                local child = build_class(ctx, c.name, c.unique, c.fields)
                parent.members[child] = true
                child.kind = basename(c.name)
                if not c.fields then
                    ctx:_SetDefinition(c.name, setmetatable({}, child))
                end
            end
        else
            build_class(ctx, d.name, d.type.unique, d.type.fields)
        end
    end
end

-- ── NewContext ────────────────────────────────────────────────

function M.NewContext()
    local ctx = setmetatable({
        definitions = {},
        namespaces = {},
        checks = setmetatable({}, { __index = builtin_checks }),
    }, Context)

    function ctx:Define(text)
        local parser = require("gps.asdl_parser")
        local defs = parser.parse(text)
        M.define(ctx, defs)
        return ctx
    end

    return ctx
end

return M
