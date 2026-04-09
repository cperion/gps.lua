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
--
-- Design note:
--   Constructors are closure-only at runtime. The only codegen that remains is
--   a fixed set of generic arity-specialized kernels generated once when this
--   file loads. There is no per-schema or hot-path runtime codegen.

local M = {}
local Quote = require("quote")

local type = type
local error = error
local pairs = pairs
local ipairs = ipairs
local select = select
local tostring = tostring
local rawset = rawset
local getmetatable = getmetatable
local setmetatable = setmetatable
local tconcat = table.concat
local sfmt = string.format

local NIL = {}
local LEAF = {}
local MAX_SPECIAL_ARITY = 16

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

-- ── Normalization / triplet helpers ─────────────────────────

local function normalize_field(fp, arg, argi, ctor_name)
    local ok, aux = fp.normalize(arg)
    if not ok then
        error(sfmt(
            "bad arg #%d to '%s': expected '%s' got '%s'%s",
            argi, ctor_name, fp.type_name, type(arg),
            aux and (" at index " .. aux) or ""), 2)
    end
    local value = (aux ~= nil) and aux or arg
    local key = (value == nil) and NIL or value
    return value, key
end

local function norm_fields_gen(state, i)
    i = i + 1
    local fp = state.fields[i]
    if fp == nil then
        return nil
    end
    local value, key = normalize_field(fp, state.args[i], i, state.name)
    return i, fp, value, key
end

local function plain_sink(self, plan, g, p, c)
    local obj = {}
    while true do
        c, fp, value = g(p, c)
        if c == nil then
            break
        end
        obj[fp.name] = value
    end
    return setmetatable(obj, self)
end

local function unique_sink(self, plan, g, p, c)
    local values = {}
    local keys = {}
    local n = 0
    while true do
        c, _, value, key = g(p, c)
        if c == nil then
            break
        end
        n = n + 1
        values[n] = value
        keys[n] = key
    end

    local node = plan.cache
    for i = 1, n do
        local next = node[keys[i]]
        if next == nil then
            next = {}
            node[keys[i]] = next
        end
        node = next
    end

    local hit = node[LEAF]
    if hit ~= nil then
        return hit
    end

    local obj = {}
    local names = plan.names
    for i = 1, n do
        obj[names[i]] = values[i]
    end
    obj = setmetatable(obj, self)
    node[LEAF] = obj
    return obj
end

local function pack_args(n, ...)
    local args = {}
    for i = 1, n do
        args[i] = select(i, ...)
    end
    return args
end

local function make_generic_ctor(plan)
    local n = plan.arity
    if plan.unique then
        return function(self, ...)
            local state = {
                name = plan.name,
                fields = plan.fields,
                args = pack_args(n, ...),
            }
            return unique_sink(self, plan, norm_fields_gen, state, 0)
        end
    end
    return function(self, ...)
        local state = {
            name = plan.name,
            fields = plan.fields,
            args = pack_args(n, ...),
        }
        return plain_sink(self, plan, norm_fields_gen, state, 0)
    end
end

-- ── Load-time generated arity kernels ───────────────────────

local function gen_plain_factory(n)
    local q = Quote()
    local _normalize_field = q:val(normalize_field, "normalize_field")
    local _setmetatable = q:val(setmetatable, "setmetatable")
    local args = {}
    for i = 1, n do args[i] = "a" .. i end
    local arglist = tconcat(args, ", ")

    q("return function(plan)")
    q("  local fields = plan.fields")
    q("  local names = plan.names")
    q("  local ctor_name = plan.name")
    if n == 0 then
        q("  return function(self)")
        q("    return %s({}, self)", _setmetatable)
        q("  end")
    else
        q("  return function(self, %s)", arglist)
        for i = 1, n do
            q("    local v%d = %s(fields[%d], a%d, %d, ctor_name)", i, _normalize_field, i, i, i)
        end
        q("    return %s({", _setmetatable)
        for i = 1, n do
            q("      [names[%d]] = v%d,", i, i)
        end
        q("    }, self)")
        q("  end")
    end
    q("end")
    return q:compile("=(asdl.ctor.plain." .. n .. ")")
end

local function gen_unique_factory(n)
    local q = Quote()
    local _normalize_field = q:val(normalize_field, "normalize_field")
    local _setmetatable = q:val(setmetatable, "setmetatable")
    local _LEAF = q:val(LEAF, "LEAF")
    local args = {}
    for i = 1, n do args[i] = "a" .. i end
    local arglist = tconcat(args, ", ")

    q("return function(plan)")
    q("  local fields = plan.fields")
    q("  local names = plan.names")
    q("  local cache = plan.cache")
    q("  local ctor_name = plan.name")
    if n == 0 then
        q("  return function(self)")
        q("    local hit = cache[%s]", _LEAF)
        q("    if hit ~= nil then return hit end")
        q("    local obj = %s({}, self)", _setmetatable)
        q("    cache[%s] = obj", _LEAF)
        q("    return obj")
        q("  end")
    else
        q("  return function(self, %s)", arglist)
        for i = 1, n do
            q("    local v%d, k%d = %s(fields[%d], a%d, %d, ctor_name)", i, i, _normalize_field, i, i, i)
        end
        q("    local node = cache")
        for i = 1, n do
            q("    local next%d = node[k%d]", i, i)
            q("    if next%d == nil then", i)
            q("      next%d = {}", i)
            q("      node[k%d] = next%d", i, i)
            q("    end")
            q("    node = next%d", i)
        end
        q("    local hit = node[%s]", _LEAF)
        q("    if hit ~= nil then return hit end")
        q("    local obj = %s({", _setmetatable)
        for i = 1, n do
            q("      [names[%d]] = v%d,", i, i)
        end
        q("    }, self)")
        q("    node[%s] = obj", _LEAF)
        q("    return obj")
        q("  end")
    end
    q("end")
    return q:compile("=(asdl.ctor.unique." .. n .. ")")
end

local function build_ctor_kernels(max_arity)
    local kernels = { plain = {}, unique = {} }
    for n = 0, max_arity do
        kernels.plain[n] = gen_plain_factory(n)
        kernels.unique[n] = gen_unique_factory(n)
    end
    return kernels
end

local KERNELS = build_ctor_kernels(MAX_SPECIAL_ARITY)

-- ── Field checking ───────────────────────────────────────────

local function make_list_check(check, type_name, unique_parent)
    if unique_parent then
        local intern_trie = {}
        local seen = setmetatable({}, { __mode = "kv" })
        return function(vs)
            if type(vs) ~= "table" then
                return false
            end

            local fast = seen[vs]
            if fast ~= nil then
                return true, fast
            end

            local len = #vs
            local elems = nil
            for i = 1, len do
                local elem = vs[i]
                local ok, aux = check(elem)
                if not ok then
                    return false, i
                end
                local value = (aux ~= nil) and aux or elem
                if elems ~= nil then
                    elems[i] = value
                elseif value ~= elem then
                    elems = {}
                    for j = 1, i - 1 do elems[j] = vs[j] end
                    elems[i] = value
                end
            end

            local src = elems or vs
            local node = intern_trie[len]
            if node == nil then
                node = {}
                intern_trie[len] = node
            end
            for i = 1, len do
                local key = src[i]
                if key == nil then key = NIL end
                local next = node[key]
                if next == nil then
                    next = {}
                    node[key] = next
                end
                node = next
            end

            local existing = node[LEAF]
            if existing == nil then
                existing = {}
                for i = 1, len do existing[i] = src[i] end
                node[LEAF] = existing
            end
            seen[vs] = existing
            return true, existing
        end, type_name .. "*"
    end

    return function(vs)
        if type(vs) ~= "table" then
            return false
        end
        local len = #vs
        local elems = nil
        for i = 1, len do
            local elem = vs[i]
            local ok, aux = check(elem)
            if not ok then
                return false, i
            end
            local value = (aux ~= nil) and aux or elem
            if elems ~= nil then
                elems[i] = value
            elseif value ~= elem then
                elems = {}
                for j = 1, i - 1 do elems[j] = vs[j] end
                elems[i] = value
            end
        end
        return true, elems
    end, type_name .. "*"
end

local function make_check(ctx, field, unique_parent)
    local type_name = field.type
    local check = ctx.checks[type_name]
    if not check then
        error("ASDL: unknown type '" .. type_name .. "' in field '" .. (field.name or "?") .. "'")
    end

    if field.list then
        return make_list_check(check, type_name, unique_parent)
    elseif field.optional then
        return function(v)
            if v == nil then
                return true
            end
            return check(v)
        end, type_name .. "?"
    else
        return check, type_name
    end
end

-- ── Class building ───────────────────────────────────────────

local function build_ctor_plan(ctx, name, class, unique, fields)
    for _, f in ipairs(fields) do
        if f.namespace then
            local fq = f.namespace .. f.type
            if ctx.definitions[fq] then f.type = fq end
            f.namespace = nil
        end
    end

    local names = {}
    local field_plans = {}
    for i, f in ipairs(fields) do
        local normalize, type_name = make_check(ctx, f, unique)
        names[i] = f.name
        field_plans[i] = {
            name = f.name,
            type_name = type_name,
            normalize = normalize,
        }
    end

    return {
        name = name,
        class = class,
        arity = #fields,
        unique = unique,
        names = names,
        fields = field_plans,
        cache = unique and {} or nil,
    }
end

local function install_ctor(mt, plan)
    local n = plan.arity
    if n <= MAX_SPECIAL_ARITY then
        if plan.unique then
            mt.__call = KERNELS.unique[n](plan)
        else
            mt.__call = KERNELS.plain[n](plan)
        end
    else
        mt.__call = make_generic_ctor(plan)
    end
end

local function build_class(ctx, name, unique, fields)
    local class = ctx.definitions[name]
    class.__fields = fields
    class.__index = class
    class.members = class.members or {}
    class.members[class] = true

    local mt = {}

    if fields then
        local plan = build_ctor_plan(ctx, name, class, unique, fields)
        install_ctor(mt, plan)

        function class:__tostring()
            local parts = {}
            for i, f in ipairs(fields) do
                local v = self[f.name]
                if v ~= nil or not f.optional then
                    if f.list then
                        local elems = {}
                        for j = 1, #v do elems[j] = tostring(v[j]) end
                        parts[#parts + 1] = f.name .. " = {" .. tconcat(elems, ",") .. "}"
                    else
                        parts[#parts + 1] = f.name .. " = " .. tostring(v)
                    end
                end
            end
            return name .. "(" .. tconcat(parts, ", ") .. ")"
        end
    else
        local singleton = nil
        local function get_singleton(self)
            singleton = singleton or setmetatable({}, self)
            return singleton
        end

        function mt:__call()
            return get_singleton(self)
        end

        class.__call = function()
            return get_singleton(class)
        end

        function class:__tostring()
            return name
        end
    end

    function mt:__newindex(k, v)
        for member in pairs(self.members) do
            rawset(member, k, v)
        end
    end

    function mt:__tostring()
        return sfmt("Class(%s)", name)
    end

    function class:isclassof(obj)
        return self.members[getmetatable(obj) or false] or false
    end

    setmetatable(class, mt)
    return class
end

-- ── Define: process parsed definitions ───────────────────────

function M.define(ctx, definitions)
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

    for _, d in ipairs(definitions) do
        if d.type.kind == "sum" then
            local parent = build_class(ctx, d.name, false, nil)
            for _, c in ipairs(d.type.constructors) do
                local child = build_class(ctx, c.name, c.unique, c.fields)
                parent.members[child] = true
                child.kind = basename(c.name)
                if not c.fields then
                    ctx:_SetDefinition(c.name, child())
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
