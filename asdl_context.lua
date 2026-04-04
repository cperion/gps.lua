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
local Quote = require("quote")

local function gen_unique_ctor(n, names, cache, nilkey)
    -- Generate a specialized unique constructor for checked values.
    -- Values are already normalized into v1..vn before the trie walk.
    local q = Quote()
    local args = {}
    local _cache = q:val(cache, "cache")
    local _nilkey = q:val(nilkey, "nilkey")
    local _setmetatable = q:val(setmetatable, "setmetatable")
    local name_refs = {}
    for i = 1, n do
        args[i] = "a" .. i
        name_refs[i] = q:val(names[i], "N" .. i)
    end
    local arglist = table.concat(args, ", ")

    q("return function(self, %s)", arglist)
    for i = 1, n do
        q("  local k%d = a%d; if k%d == nil then k%d = %s end", i, i, i, i, _nilkey)
    end

    if n == 0 then
        q("  local hit = %s[%s]", _cache, _nilkey)
        q("  if hit then return hit end")
        q("  local obj = %s({}, self)", _setmetatable)
        q("  %s[%s] = obj; return obj", _cache, _nilkey)
    elseif n == 1 then
        q("  local hit = %s[k1]", _cache)
        q("  if hit then return hit end")
        q("  local obj = %s({[%s]=a1}, self)", _setmetatable, name_refs[1])
        q("  %s[k1] = obj; return obj", _cache)
    else
        q("  local n1 = %s[k1]", _cache)
        q("  if not n1 then n1 = {}; %s[k1] = n1 end", _cache)
        for i = 2, n - 1 do
            local prev = "n" .. (i - 1)
            local cur = "n" .. i
            q("  local %s = %s[k%d]", cur, prev, i)
            q("  if not %s then %s = {}; %s[k%d] = %s end", cur, cur, prev, i, cur)
        end
        local last_parent = "n" .. (n - 1)
        q("  local hit = %s[k%d]", last_parent, n)
        q("  if hit then return hit end")
        local field_init = {}
        for i = 1, n do field_init[i] = string.format("[%s]=a%d", name_refs[i], i) end
        q("  local obj = %s({%s}, self)", _setmetatable, table.concat(field_init, ","))
        q("  %s[k%d] = obj; return obj", last_parent, n)
    end

    q("end")
    local compiled = q:compile("=(asdl.ctor." .. table.concat(names, ".") .. ")")
    return compiled
end

-- Optimized: all-builtin, no nil possible (number, string, boolean)
local function gen_unique_ctor_fast(n, names, cache)
    -- Even faster: skip nilkey checks entirely.
    -- Valid when all fields are non-nil builtins.
    local q = Quote()
    local args = {}
    local _cache = q:val(cache, "cache")
    local _setmetatable = q:val(setmetatable, "setmetatable")
    local name_refs = {}
    for i = 1, n do
        args[i] = "a" .. i
        name_refs[i] = q:val(names[i], "N" .. i)
    end
    local arglist = table.concat(args, ", ")

    q("return function(self, %s)", arglist)

    if n == 0 then
        q("  local hit = %s[0]", _cache)
        q("  if hit then return hit end")
        q("  local obj = %s({}, self)", _setmetatable)
        q("  %s[0] = obj; return obj", _cache)
    else
        for i = 1, n - 1 do
            local prev = (i == 1) and _cache or ("n" .. (i-1))
            local cur = "n" .. i
            q("  local %s = %s[a%d]; if not %s then %s = {}; %s[a%d] = %s end",
                cur, prev, i, cur, cur, prev, i, cur)
        end
        local last_parent = (n == 1) and _cache or ("n" .. (n-1))
        q("  local hit = %s[a%d]; if hit then return hit end", last_parent, n)
        local fi = {}
        for i = 1, n do fi[i] = string.format("[%s]=a%d", name_refs[i], i) end
        q("  local obj = %s({%s}, self)", _setmetatable, table.concat(fi, ","))
        q("  %s[a%d] = obj; return obj", last_parent, n)
    end

    q("end")
    local compiled = q:compile("=(asdl.ctor_fast." .. table.concat(names, ".") .. ")")
    return compiled
end

local function gen_plain_ctor_fast(n, names)
    local q = Quote()
    local args = {}
    local _setmetatable = q:val(setmetatable, "setmetatable")
    local field_init = {}
    local name_refs = {}
    for i = 1, n do
        args[i] = "a" .. i
        name_refs[i] = q:val(names[i], "N" .. i)
        field_init[i] = string.format("[%s]=a%d", name_refs[i], i)
    end
    local arglist = table.concat(args, ", ")

    q("return function(self, %s)", arglist)
    q("  return %s({%s}, self)", _setmetatable, table.concat(field_init, ","))
    q("end")
    local compiled = q:compile("=(asdl.plain_fast." .. table.concat(names, ".") .. ")")
    return compiled
end

local function gen_checked_ctor(name, names, checks, type_names, unique, cache, nilkey)
    local n = #names
    local q = Quote()
    local args = {}
    local _setmetatable = q:val(setmetatable, "setmetatable")
    local _error = q:val(error, "error")
    local _type = q:val(type, "type")
    local _fmt = q:val(string.format, "fmt")
    local _name = q:val(name, "name")
    local _cache = cache and q:val(cache, "cache") or nil
    local _nilkey = q:val(nilkey, "nilkey")
    local check_refs, type_refs, name_refs = {}, {}, {}

    for i = 1, n do
        args[i] = "a" .. i
        check_refs[i] = q:val(checks[i], "C" .. i)
        type_refs[i] = q:val(type_names[i], "T" .. i)
        name_refs[i] = q:val(names[i], "N" .. i)
    end
    local arglist = table.concat(args, ", ")

    q("return function(self, %s)", arglist)
    for i = 1, n do
        q("  local v%d = a%d", i, i)
        q("  local ok%d, aux%d = %s(v%d)", i, i, check_refs[i], i)
        q("  if not ok%d then", i)
        q("    %s(%s(\"bad arg #%d to '%%s': expected '%%s' got '%%s'%%s\", %s, %s, %s(a%d), aux%d and (\" at index \" .. aux%d) or \"\"), 2)",
            _error, _fmt, i, _name, type_refs[i], _type, i, i, i)
        q("  end")
        q("  if aux%d ~= nil then v%d = aux%d end", i, i, i)
    end

    if unique then
        if n == 0 then
            q("  local hit = %s[%s]", _cache, _nilkey)
            q("  if hit then return hit end")
            q("  local obj = %s({}, self)", _setmetatable)
            q("  %s[%s] = obj; return obj", _cache, _nilkey)
        elseif n == 1 then
            q("  local k1 = v1; if k1 == nil then k1 = %s end", _nilkey)
            q("  local hit = %s[k1]", _cache)
            q("  if hit then return hit end")
            q("  local obj = %s({[%s]=v1}, self)", _setmetatable, name_refs[1])
            q("  %s[k1] = obj; return obj", _cache)
        else
            q("  local k1 = v1; if k1 == nil then k1 = %s end", _nilkey)
            q("  local n1 = %s[k1]", _cache)
            q("  if not n1 then n1 = {}; %s[k1] = n1 end", _cache)
            for i = 2, n - 1 do
                local prev = "n" .. (i - 1)
                local cur = "n" .. i
                q("  local k%d = v%d; if k%d == nil then k%d = %s end", i, i, i, i, _nilkey)
                q("  local %s = %s[k%d]", cur, prev, i)
                q("  if not %s then %s = {}; %s[k%d] = %s end", cur, cur, prev, i, cur)
            end
            q("  local k%d = v%d; if k%d == nil then k%d = %s end", n, n, n, n, _nilkey)
            local last_parent = "n" .. (n - 1)
            q("  local hit = %s[k%d]", last_parent, n)
            q("  if hit then return hit end")
            local field_init = {}
            for i = 1, n do field_init[i] = string.format("[%s]=v%d", name_refs[i], i) end
            q("  local obj = %s({%s}, self)", _setmetatable, table.concat(field_init, ","))
            q("  %s[k%d] = obj; return obj", last_parent, n)
        end
    else
        local field_init = {}
        for i = 1, n do field_init[i] = string.format("[%s]=v%d", name_refs[i], i) end
        q("  return %s({%s}, self)", _setmetatable, table.concat(field_init, ","))
    end

    q("end")
    local compiled = q:compile("=(asdl.checked_ctor." .. name .. ")")
    return compiled
end

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
        if ctx.codegen_constructors then
            if unique then
                local cache = {}
                if all_builtin then
                    mt.__call = gen_unique_ctor_fast(n, names, cache)
                else
                    mt.__call = gen_checked_ctor(name, names, checks, type_names, true, cache, nilkey)
                end
            else
                if all_builtin then
                    mt.__call = gen_plain_ctor_fast(n, names)
                else
                    mt.__call = gen_checked_ctor(name, names, checks, type_names, false, false, nilkey)
                end
            end
        elseif unique then
            local cache = {}
            if all_builtin then
                -- Code-generated: unrolled trie, no loop, no select()
                mt.__call = gen_unique_ctor_fast(n, names, cache)
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
        local singleton = nil
        local function get_singleton(self)
            singleton = singleton or setmetatable({}, self)
            return singleton
        end

        function mt:__call()
            return get_singleton(self)
        end

        -- Allow the singleton value itself to be called like a constructor,
        -- so nullary constructors can be used uniformly as `Ctor()` while
        -- still remaining a canonical interned node when referenced directly.
        class.__call = function()
            return get_singleton(class)
        end

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
                    ctx:_SetDefinition(c.name, child())
                end
            end
        else
            build_class(ctx, d.name, d.type.unique, d.type.fields)
        end
    end
end

-- ── NewContext ────────────────────────────────────────────────

function M.NewContext(opts)
    opts = opts or {}
    local ctx = setmetatable({
        definitions = {},
        namespaces = {},
        checks = setmetatable({}, { __index = builtin_checks }),
        codegen_constructors = not not opts.codegen_constructors,
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
