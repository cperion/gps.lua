-- asdl_context.lua — GC-backed ASDL context builder
--
-- Builds live ASDL classes from parser output:
--   - callable classes
--   - structural interning for `unique`
--   - sum type dispatch via `members`
--   - field metadata (`__fields`)
--   - structural update via generated `__with`
--   - generated raw getters for hot paths (`__raw`, `__raw_<field>`)
--
-- Memory model:
--   ASDL values are ordinary GC-managed Lua objects. Old worlds die by
--   reachability. There is no user-visible lifecycle step.
--
-- Performance model:
--   The backend stays simple (plain GC-managed objects) but still uses codegen
--   for the hot constructor / updater / raw-getter paths. Arity-specialized
--   kernels up to MAX_SPECIAL_ARITY keep the common cases monomorphic without
--   reintroducing slot/gen lifetime machinery.

local M = {}
local Quote = require("quote")

local type = type
local error = error
local pairs = pairs
local ipairs = ipairs
local select = select
local tostring = tostring
local rawset = rawset
local rawget = rawget
local setmetatable = setmetatable
local getmetatable = getmetatable
local tconcat = table.concat
local sfmt = string.format
local unpack = table.unpack or unpack

local NIL = {}
local LEAF = {}
local WEAK_VALUE_MT = { __mode = "v" }
local MAX_SPECIAL_ARITY = 16
local normalize_field
local classof_fast

-- ── Builtin type checks ─────────────────────────────────────

local builtin_checks = {}
for _, name in ipairs({ "nil", "number", "string", "boolean", "table", "function" }) do
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
    self._builders = nil
    self._fast_builders = nil
end

function Context:Extern(name, check_fn)
    self.checks[name] = check_fn
end

local function make_named_builder(class, trusted)
    local fields = rawget(class, "__fields")
    local plan = rawget(class, "__plan")
    local name = plan and plan.name or tostring(class)
    local allowed = {}
    for i = 1, #fields do
        allowed[fields[i].name] = true
    end

    local q = Quote()
    local _ctor = q:val(class, "ctor")

    q("return function(spec)")
    if not trusted then
        local _type = q:val(type, "type")
        local _getmetatable = q:val(getmetatable, "getmetatable")
        local _classof_fast = q:val(classof_fast, "classof_fast")
        local _pairs = q:val(pairs, "pairs")
        local _tostring = q:val(tostring, "tostring")
        local _allowed = q:val(allowed, "allowed")

        q("  if %s(spec) ~= 'table' or %s(spec) ~= nil or %s(spec) then", _type, _getmetatable, _classof_fast)
        q("    error(%q, 2)", "builder for '" .. name .. "' expects one plain Lua table")
        q("  end")
        q("  for k in %s(spec) do", _pairs)
        q("    if %s[k] == nil then", _allowed)
        q("      error(\"unknown field '\" .. %s(k) .. \"' for '%s'\", 2)", _tostring, name)
        q("    end")
        q("  end")
    end

    local args = {}
    for i = 1, #fields do
        local f = fields[i]
        q("  local v%d = spec[%q]", i, f.name)
        if not trusted and not f.optional then
            q("  if v%d == nil then error(%q, 2) end", i, "missing required field '" .. f.name .. "' for '" .. name .. "'")
        end
        args[i] = "v" .. i
    end

    q("  return %s(%s)", _ctor, tconcat(args, ", "))
    q("end")
    return q:compile("=(asdl.builder." .. tostring(name) .. "." .. tostring(trusted) .. ")")
end

local function build_builder_tree(src, trusted)
    local out = {}
    for k, v in pairs(src) do
        if type(v) == "table" and not classof_fast(v) and rawget(v, "members") ~= nil then
            if rawget(v, "__fields") then
                local slot = trusted and "__fast_builder" or "__builder"
                out[k] = rawget(v, slot) or make_named_builder(v, trusted)
                rawset(v, slot, out[k])
            else
                out[k] = v
            end
        elseif type(v) == "table" and not classof_fast(v) and getmetatable(v) == nil then
            out[k] = build_builder_tree(v, trusted)
        else
            out[k] = v
        end
    end
    return out
end

function Context:Builders(opts)
    opts = opts or false
    local trusted = opts == true or (type(opts) == "table" and opts.trusted) or false
    local cache_key = trusted and "_fast_builders" or "_builders"
    local cached = rawget(self, cache_key)
    if cached ~= nil then return cached end
    local built = build_builder_tree(self.namespaces, trusted)
    rawset(self, cache_key, built)
    return built
end

function Context:FastBuilders()
    return self:Builders(true)
end

classof_fast = function(v)
    if type(v) ~= "table" then
        return false
    end
    local mt = getmetatable(v)
    return (mt and mt.__class) or false
end

function M.ClassOf(v)
    return classof_fast(v)
end

-- ── Interning helpers ───────────────────────────────────────

local function alloc_leaf_box(value)
    local box = setmetatable({}, WEAK_VALUE_MT)
    box[1] = value
    return box
end

local function intern_value(cache, keys, build)
    if cache == nil then
        return build()
    end

    local node = cache
    for i = 1, #keys do
        local next = node[keys[i]]
        if next == nil then
            next = {}
            node[keys[i]] = next
        end
        node = next
    end

    local leaf = node[LEAF]
    if leaf ~= nil then
        local hit = leaf[1]
        if hit ~= nil then
            return hit
        end
        node[LEAF] = nil
    end

    local value = build()
    node[LEAF] = alloc_leaf_box(value)
    return value
end

-- ── Normalization / checking ────────────────────────────────

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
            local keys = { len }
            for i = 1, len do
                keys[i + 1] = (src[i] == nil) and NIL or src[i]
            end

            local canonical = intern_value(intern_trie, keys, function()
                local out = {}
                for i = 1, len do out[i] = src[i] end
                return out
            end)
            seen[vs] = canonical
            return true, canonical
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

normalize_field = function(fp, arg, argi, ctor_name)
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

-- ── Constructors / with / raw ───────────────────────────────

local function make_instance_mt(class, instance_tostring, field_lookup)
    return {
        __class = class,
        __index = function(self, k)
            local v = rawget(self, k)
            if v ~= nil then
                return v
            end
            if field_lookup[k] then
                return nil
            end
            return class[k]
        end,
        __newindex = function()
            error("ASDL nodes are immutable; use pvm.with(...)", 2)
        end,
        __tostring = instance_tostring,
    }
end

-- Generate arity-specialized constructors for GC-backed objects.
--
-- This keeps the old good part of the backend — straight-line constructor
-- code with unrolled normalization and intern-trie walks — while the objects
-- themselves remain ordinary GC-managed Lua tables.
local function gen_ctor_factory(n, trusted)
    local q = Quote()
    local _normalize_field = q:val(normalize_field, "normalize_field")
    local _setmetatable = q:val(setmetatable, "setmetatable")
    local _alloc_leaf_box = q:val(alloc_leaf_box, "alloc_leaf_box")
    local _NIL = q:val(NIL, "NIL")
    local _LEAF = q:val(LEAF, "LEAF")
    local args = {}
    for i = 1, n do args[i] = "a" .. i end
    local arglist = tconcat(args, ", ")

    q("return function(plan)")
    q("  local cache = plan.cache")
    q("  local ctor_name = plan.name")
    q("  local mt = plan.instance_mt")
    if not trusted then
        q("  local fields = plan.fields")
    end
    for i = 1, n do
        q("  local k%d = plan.names[%d]", i, i)
    end
    q("  return function(self, %s)", arglist)
    for i = 1, n do
        if trusted then
            q("    local v%d = a%d", i, i)
            q("    local key%d = (v%d == nil) and %s or v%d", i, i, _NIL, i)
        else
            q("    local v%d, key%d = %s(fields[%d], a%d, %d, ctor_name)", i, i, _normalize_field, i, i, i)
        end
    end
    q("    local node = cache")
    q("    if node ~= nil then")
    for i = 1, n do
        q("      local next%d = node[key%d]", i, i)
        q("      if next%d == nil then", i)
        q("        next%d = {}", i)
        q("        node[key%d] = next%d", i, i)
        q("      end")
        q("      node = next%d", i)
    end
    q("      local leaf = node[%s]", _LEAF)
    q("      if leaf ~= nil then")
    q("        local hit = leaf[1]")
    q("        if hit ~= nil then return hit end")
    q("        node[%s] = nil", _LEAF)
    q("      end")
    q("    end")
    q("    local obj = %s({", _setmetatable)
    for i = 1, n do
        q("      [%s] = v%d,", "k" .. i, i)
    end
    q("    }, mt)")
    q("    if node ~= nil then node[%s] = %s(obj) end", _LEAF, _alloc_leaf_box)
    q("    return obj")
    q("  end")
    q("end")
    return q:compile("=(asdl.gc_ctor." .. tostring(n) .. "." .. tostring(trusted) .. ")")
end

local CTOR_KERNELS = {}
local TRUSTED_CTOR_KERNELS = {}
for n = 1, MAX_SPECIAL_ARITY do
    CTOR_KERNELS[n] = gen_ctor_factory(n, false)
    TRUSTED_CTOR_KERNELS[n] = gen_ctor_factory(n, true)
end

local function make_ctor(plan)
    local n = plan.arity
    if n >= 1 and n <= MAX_SPECIAL_ARITY then
        return CTOR_KERNELS[n](plan)
    end
    return function(self, ...)
        local values = {}
        local keys = {}
        for i = 1, n do
            local value, key = normalize_field(plan.fields[i], select(i, ...), i, plan.name)
            values[plan.names[i]] = value
            keys[i] = key
        end
        return intern_value(plan.cache, keys, function()
            return setmetatable(values, plan.instance_mt)
        end)
    end
end

local function make_with_updater(class, plan, fields)
    local n = #fields
    if n >= 1 and n <= MAX_SPECIAL_ARITY then
        local q = Quote()
        local _class = q:val(class, "class")
        q("return function(self, overrides, NIL_SENTINEL)")
        for i = 1, n do
            local name = fields[i].name
            q("  local v%d = overrides[%q]", i, name)
            q("  if v%d == NIL_SENTINEL then", i)
            q("    v%d = nil", i)
            q("  elseif v%d == nil then", i)
            q("    v%d = rawget(self, %q)", i, name)
            q("  end")
        end
        local args = {}
        for i = 1, n do args[i] = "v" .. i end
        q("  return %s(%s)", _class, tconcat(args, ", "))
        q("end")
        return q:compile("=(asdl.with_gc." .. plan.name .. ")")
    end
    return function(self, overrides, NIL_SENTINEL)
        local args = {}
        for i = 1, n do
            local name = fields[i].name
            local v = overrides[name]
            if v == NIL_SENTINEL then
                v = nil
            elseif v == nil then
                v = rawget(self, name)
            end
            args[i] = v
        end
        return class(unpack(args, 1, n))
    end
end

local function make_raw_getter(fields)
    local n = #fields
    if n >= 1 and n <= MAX_SPECIAL_ARITY then
        local q = Quote()
        q("return function(self)")
        local outs = {}
        for i = 1, n do
            local name = fields[i].name
            q("  local v%d = rawget(self, %q)", i, name)
            outs[i] = "v" .. i
        end
        q("  return %s", tconcat(outs, ", "))
        q("end")
        return q:compile("=(asdl.raw_gc." .. tostring(n) .. ")")
    end
    return function(self)
        local out = {}
        for i = 1, n do
            out[i] = rawget(self, fields[i].name)
        end
        return unpack(out, 1, n)
    end
end

local function build_ctor_plan(ctx, name, class, unique, fields, instance_tostring)
    for _, f in ipairs(fields) do
        if f.namespace then
            local fq = f.namespace .. f.type
            if ctx.definitions[fq] then
                f.type = fq
            end
            f.namespace = nil
        end
    end

    local names = {}
    local field_plans = {}
    local field_lookup = {}
    for i, f in ipairs(fields) do
        local normalize, type_name = make_check(ctx, f, unique)
        names[i] = f.name
        field_lookup[f.name] = true
        field_plans[i] = {
            name = f.name,
            type_name = type_name,
            normalize = normalize,
        }
    end

    local instance_mt = make_instance_mt(class, instance_tostring, field_lookup)

    return {
        name = name,
        class = class,
        arity = #fields,
        unique = unique,
        names = names,
        fields = field_plans,
        cache = unique and {} or nil,
        backend = "gc_object",
        field_lookup = field_lookup,
        instance_mt = instance_mt,
    }
end

-- ── Class building ───────────────────────────────────────────

local function build_class(ctx, name, unique, fields)
    local class = ctx.definitions[name]
    class.__fields = fields
    class.__index = class
    class.__class = class
    class.__cacheclass = false
    class.__cachekey = false
    class.members = class.members or {}
    class.members[class] = true

    local mt = {}

    if fields then
        local function instance_tostring(self)
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

        local plan = build_ctor_plan(ctx, name, class, unique, fields, instance_tostring)
        mt.__call = make_ctor(plan)
        class.__storage = plan.backend
        class.__ctype = nil
        class.__plan = plan
        class.__instance_mt = plan.instance_mt
        class.__with = make_with_updater(class, plan, fields)
        class.__raw = make_raw_getter(fields)
        class.__tostring = instance_tostring
        for i = 1, #fields do
            if fields[i].list then
                class["__raw_" .. fields[i].name] = function(self)
                    local v = rawget(self, fields[i].name)
                    if v == nil then
                        return nil, nil, 0, false
                    end
                    return v, 1, #v, true
                end
            end
        end
    else
        local function instance_tostring()
            return name
        end

        local instance_mt = {
            __class = class,
            __index = function(self, k)
                return class[k]
            end,
            __newindex = function()
                error("ASDL nodes are immutable; use pvm.with(...)", 2)
            end,
            __tostring = instance_tostring,
        }

        local singleton = setmetatable({}, instance_mt)

        function mt:__call()
            return singleton
        end

        class.__storage = "gc_singleton"
        class.__ctype = nil
        class.__plan = {
            name = name,
            class = class,
            arity = 0,
            unique = true,
            names = {},
            fields = {},
            cache = nil,
            backend = "gc_singleton",
            instance_mt = instance_mt,
        }
        class.__instance_mt = instance_mt
        class.__singleton = singleton
        class.__tostring = instance_tostring
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
        return self.members[classof_fast(obj)] or false
    end

    setmetatable(class, mt)
    return class
end

-- ── Define: process parsed definitions ───────────────────────

function M.define(ctx, definitions)
    for _, d in ipairs(definitions) do
        ctx.definitions[d.name] = ctx.definitions[d.name] or { members = {} }
        do
            local members = ctx.definitions[d.name].members
            ctx.checks[d.name] = function(v)
                return members[classof_fast(v)] or false
            end
        end
        ctx:_SetDefinition(d.name, ctx.definitions[d.name])

        if d.type.kind == "sum" then
            for _, c in ipairs(d.type.constructors) do
                ctx.definitions[c.name] = ctx.definitions[c.name] or { members = {} }
                do
                    local members = ctx.definitions[c.name].members
                    ctx.checks[c.name] = function(v)
                        return members[classof_fast(v)] or false
                    end
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

-- ── NewContext ───────────────────────────────────────────────

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
