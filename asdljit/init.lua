if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"] = function()
        return require("asdl_lexer")
    end
end
if not package.preload["gps.asdl_parser"] then
    package.preload["gps.asdl_parser"] = function()
        return require("asdl_parser")
    end
end

local ffi = require("ffi")
local parser = require("asdl_parser")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local M = {}
local DescriptorMT = {}
local SchemaMT = {}
local RuntimeMT = {}
local ListRuntimeMT = {}
DescriptorMT.__index = DescriptorMT
SchemaMT.__index = SchemaMT
RuntimeMT.__index = RuntimeMT
ListRuntimeMT.__index = ListRuntimeMT

local mix_u32 = wj.fn {
    name = "asdljit_mix_u32",
    params = { wj.u32 "h", wj.u32 "x" },
    ret = wj.u32,
    body = function(h, x)
        return (h:bxor(x)) * wj.u32(16777619)
    end,
}

local function basename(name)
    return name:match("([^.]*)$")
end

local function shallow_copy(t)
    local out = {}
    if t ~= nil then
        for k, v in pairs(t) do
            out[k] = v
        end
    end
    return out
end

local function set_definition(schema, name, value)
    local ns = schema.namespaces
    for part in name:gmatch("([^.]*)%.") do
        ns[part] = ns[part] or {}
        ns = ns[part]
    end
    ns[basename(name)] = value
    schema.definitions[name] = value
end

local function resolve_type(type_map, type_name)
    local t = type_map[type_name]
    if t ~= nil then
        return t
    end
    local base = basename(type_name)
    t = type_map[base]
    if t ~= nil then
        return t
    end
    error("asdljit: no watjit type mapping for ASDL type '" .. tostring(type_name) .. "'", 3)
end

local function normalize_field_list(fields)
    local out = {}
    fields = fields or {}
    for i = 1, #fields do
        local f = fields[i]
        out[i] = {
            name = f.name,
            type = f.type,
            optional = f.optional or false,
            list = f.list or false,
        }
    end
    return out
end

local function field_to_u32(v, t)
    assert(type(t) == "table" and t.bits ~= nil and t.signed ~= nil, "asdljit hash only supports integer/enum-like watjit types up to 32 bits")
    assert(t.bits <= 32, "asdljit hash MVP only supports integer/enum-like types up to 32 bits")
    if t.bits == 32 then
        if t.signed then
            return wj.bitcast(wj.u32, v)
        end
        return wj.cast(wj.u32, v)
    end
    if t.signed then
        return wj.bitcast(wj.u32, wj.sext(wj.i32, v))
    end
    return wj.zext(wj.u32, v)
end

local function ffi_ctype_for_type(t)
    if t == wj.i8 then return "int8_t" end
    if t == wj.u8 then return "uint8_t" end
    if t == wj.i16 then return "int16_t" end
    if t == wj.u16 then return "uint16_t" end
    if t == wj.i32 then return "int32_t" end
    if t == wj.u32 then return "uint32_t" end
    if t.kind == "enum" then
        return ffi_ctype_for_type(t.storage)
    end
    error("asdljit runtime MVP only supports integer/enum-like watjit scalar fields up to 32 bits", 3)
end

local function read_field_value(mem_base, offset, t)
    local ctype = ffi_ctype_for_type(t)
    local ptr = ffi.cast(ctype .. "*", mem_base + offset)
    return tonumber(ptr[0])
end

local function write_scalar_values(mem_base, base_offset, t, values)
    local ctype = ffi_ctype_for_type(t)
    local ptr = ffi.cast(ctype .. "*", mem_base + base_offset)
    for i = 1, #values do
        ptr[i - 1] = values[i]
    end
end

local function read_scalar_values(mem_base, base_offset, t, len)
    local ctype = ffi_ctype_for_type(t)
    local ptr = ffi.cast(ctype .. "*", mem_base + base_offset)
    local out = {}
    for i = 1, len do
        out[i] = tonumber(ptr[i - 1])
    end
    return out
end

local function quote_key_from_parts(parts)
    local key = table.concat(parts, "\31")
    return key
end

local function make_list_runtime(schema, type_name, elem_t, opts)
    opts = opts or {}
    local elem_runtime = opts.elem_runtime
    local store_t = elem_runtime and wj.i32 or elem_t
    local name = opts.name or ("List_" .. tostring(type_name)):gsub("[.%-]", "_")
    local Meta = wj.struct(name .. "_Meta", {
        { "offset", wj.i32 },
        { "len", wj.i32 },
    }, { packed = false })

    local hash_fn = wj.fn {
        name = name .. "_hash_fn",
        params = { wj.i32 "data_base", wj.i32 "len" },
        ret = wj.u32,
        body = function(data_base, len)
            local data = wj.view(store_t, data_base, "data")
            local i = wj.i32("i")
            local h = wj.u32("h", wj.u32(2166136261))
            wj.for_(i, len, function()
                h(mix_u32:inline_call(h, field_to_u32(data[i], store_t)))
            end)
            return h
        end,
    }

    local eq_slot_fn = wj.fn {
        name = name .. "_eq_slot_fn",
        params = { wj.i32 "meta_base", wj.i32 "data_base", wj.i32 "slot", wj.i32 "input_base", wj.i32 "len" },
        ret = wj.i32,
        body = function(meta_base, data_base, slot, input_base, len)
            local meta = Meta.at(meta_base + slot * Meta.size)
            local ok = wj.i32("ok", 1)
            local i = wj.i32("i")
            wj.if_(meta.len:eq(len), function()
                local stored = wj.view(store_t, data_base + meta.offset * store_t.size, "stored")
                local incoming = wj.view(store_t, input_base, "incoming")
                wj.for_(i, len, function(loop)
                    ok(ok:band(stored[i]:eq(incoming[i])))
                    wj.if_(ok:eq(0), function()
                        loop:break_()
                    end)
                end)
            end, function()
                ok(0)
            end)
            return ok
        end,
    }

    local store_fn = wj.fn {
        name = name .. "_store_fn",
        params = { wj.i32 "meta_base", wj.i32 "data_base", wj.i32 "slot", wj.i32 "elem_offset", wj.i32 "input_base", wj.i32 "len" },
        body = function(meta_base, data_base, slot, elem_offset, input_base, len)
            local meta = Meta.at(meta_base + slot * Meta.size)
            local stored = wj.view(store_t, data_base + elem_offset * store_t.size, "stored")
            local incoming = wj.view(store_t, input_base, "incoming")
            local i = wj.i32("i")
            meta.offset(elem_offset)
            meta.len(len)
            wj.for_(i, len, function()
                stored[i](incoming[i])
            end)
        end,
    }

    local capacity = opts.capacity or 4096
    local elem_capacity = opts.elem_capacity or 65536
    local scratch_capacity = opts.scratch_capacity or 1024
    local meta_base = opts.meta_base or 128
    local data_base = opts.data_base or (meta_base + Meta.size * capacity)
    local scratch_base = opts.scratch_base or (data_base + store_t.size * elem_capacity)
    local total_bytes = math.max(opts.bytes or 0, scratch_base + store_t.size * scratch_capacity)
    local mod = wj.module({ hash_fn, eq_slot_fn, store_fn }, {
        memory_pages = wj.pages_for_bytes(total_bytes),
    })
    local inst = mod:compile(opts.engine or wm.engine())

    return setmetatable({
        schema = schema,
        type_name = type_name,
        elem_t = elem_t,
        store_t = store_t,
        elem_runtime = elem_runtime,
        Meta = Meta,
        capacity = capacity,
        elem_capacity = elem_capacity,
        scratch_capacity = scratch_capacity,
        count = 0,
        next_elem = 0,
        buckets = {},
        mod = mod,
        inst = inst,
        mem_base = select(1, inst:memory("memory")),
        meta_base = meta_base,
        data_base = data_base,
        scratch_base = scratch_base,
        hash_fn = inst:fn(hash_fn.name),
        eq_slot_fn = inst:fn(eq_slot_fn.name),
        store_fn = inst:fn(store_fn.name),
    }, ListRuntimeMT)
end

function SchemaMT:list_runtime(type_name, opts)
    opts = opts or {}
    self._list_runtime_cache = self._list_runtime_cache or {}
    local elem_runtime = opts.elem_runtime
    local key = tostring(type_name) .. "|" .. tostring(elem_runtime ~= nil)
    if opts.capacity == nil and opts.elem_capacity == nil and opts.scratch_capacity == nil and opts.name == nil and opts.bytes == nil and opts.engine == nil and opts.meta_base == nil and opts.data_base == nil and opts.scratch_base == nil and elem_runtime == nil then
        local hit = self._list_runtime_cache[key]
        if hit ~= nil then
            return hit
        end
    end
    local elem_t
    if elem_runtime ~= nil then
        elem_t = wj.i32
    else
        local ok, resolved = pcall(resolve_type, self.type_map or {}, type_name)
        if ok then
            elem_t = resolved
        else
            error("asdljit list runtime for '" .. tostring(type_name) .. "' requires opts.elem_runtime when the element type is another ASDL descriptor/runtime handle", 2)
        end
    end
    local rt = make_list_runtime(self, type_name, elem_t, opts)
    if opts.capacity == nil and opts.elem_capacity == nil and opts.scratch_capacity == nil and opts.name == nil and opts.bytes == nil and opts.engine == nil and opts.meta_base == nil and opts.data_base == nil and opts.scratch_base == nil and elem_runtime == nil then
        self._list_runtime_cache[key] = rt
    end
    return rt
end

function ListRuntimeMT:descriptor()
    return {
        type_name = self.type_name,
        elem_t = self.elem_t,
        store_t = self.store_t,
        capacity = self.capacity,
        elem_capacity = self.elem_capacity,
        scratch_capacity = self.scratch_capacity,
    }
end

function ListRuntimeMT:handle_count()
    return self.count
end

function ListRuntimeMT:handle_of(values)
    return self:new(values)
end

local function runtime_value_to_handle(runtime, value)
    if type(value) == "number" then
        return value
    end
    assert(type(value) == "table", "asdljit runtime expected a handle number or Lua table input")
    if runtime.desc ~= nil then
        if #value > 0 then
            return runtime:new(table.unpack(value, 1, #value))
        end
        local args = {}
        for i = 1, #runtime.desc.fields do
            local f = runtime.desc.fields[i]
            args[i] = value[f.name]
        end
        return runtime:new(table.unpack(args, 1, #args))
    end
    return runtime:new(value)
end

function ListRuntimeMT:new(values)
    assert(type(values) == "table", "asdljit list runtime expects a plain Lua array")
    local len = #values
    assert(len <= self.scratch_capacity, ("asdljit list runtime scratch capacity exceeded: len=%d cap=%d"):format(len, self.scratch_capacity))
    local encoded = values
    if self.elem_runtime ~= nil then
        encoded = {}
        for i = 1, len do
            encoded[i] = runtime_value_to_handle(self.elem_runtime, values[i])
        end
    end
    write_scalar_values(self.mem_base, self.scratch_base, self.store_t, encoded)
    local hash = self.hash_fn(self.scratch_base, len)
    local bucket = self.buckets[hash]
    if bucket ~= nil then
        for i = 1, #bucket do
            local handle = bucket[i]
            if self.eq_slot_fn(self.meta_base, self.data_base, handle - 1, self.scratch_base, len) ~= 0 then
                return handle
            end
        end
    end
    assert(self.count < self.capacity, ("asdljit list runtime is full (capacity=%d)"):format(self.capacity))
    assert(self.next_elem + len <= self.elem_capacity, ("asdljit list runtime element storage is full (%d + %d > %d)"):format(self.next_elem, len, self.elem_capacity))
    local slot = self.count
    self.store_fn(self.meta_base, self.data_base, slot, self.next_elem, self.scratch_base, len)
    self.next_elem = self.next_elem + len
    local handle = slot + 1
    self.count = handle
    if bucket == nil then
        bucket = {}
        self.buckets[hash] = bucket
    end
    bucket[#bucket + 1] = handle
    return handle
end

function ListRuntimeMT:get_handles(handle)
    assert(type(handle) == "number" and handle >= 1 and handle <= self.count, "asdljit list runtime:get_handles invalid handle")
    local meta_base = self.mem_base + self.meta_base + (handle - 1) * self.Meta.size
    local offset = read_field_value(meta_base, self.Meta.offsets.offset.offset, wj.i32)
    local len = read_field_value(meta_base, self.Meta.offsets.len.offset, wj.i32)
    return read_scalar_values(self.mem_base, self.data_base + offset * self.store_t.size, self.store_t, len)
end

function ListRuntimeMT:get(handle)
    local out = self:get_handles(handle)
    if self.elem_runtime ~= nil then
        for i = 1, #out do
            out[i] = self.elem_runtime:get(out[i])
        end
    end
    return out
end

function ListRuntimeMT:raw(handle)
    return self:get(handle)
end

function ListRuntimeMT:raw_handles(handle)
    return self:get_handles(handle)
end

function ListRuntimeMT:wat()
    return self.mod:wat()
end

function DescriptorMT:param_list(type_map, prefix)
    type_map = type_map or self.schema.type_map or {}
    prefix = prefix or ""
    local out = {}
    for i = 1, #self.fields do
        local f = self.fields[i]
        assert(not f.optional, "asdljit param_list MVP does not support optional fields yet")
        if f.list then
            out[i] = wj.i32(prefix .. f.name .. "_handle")
        else
            out[i] = resolve_type(type_map, f.type)(prefix .. f.name)
        end
    end
    return out
end

function DescriptorMT:eq_param_list(type_map, lhs_prefix, rhs_prefix)
    lhs_prefix = lhs_prefix or "lhs_"
    rhs_prefix = rhs_prefix or "rhs_"
    local out = {}
    local lhs = self:param_list(type_map, lhs_prefix)
    local rhs = self:param_list(type_map, rhs_prefix)
    for i = 1, #lhs do out[#out + 1] = lhs[i] end
    for i = 1, #rhs do out[#out + 1] = rhs[i] end
    return out
end

function DescriptorMT:layout(type_map, opts)
    type_map = type_map or self.schema.type_map or {}
    opts = opts or {}
    local fields = {}
    for i = 1, #self.fields do
        local f = self.fields[i]
        assert(not f.optional, "asdljit layout MVP does not support optional fields yet")
        if f.list then
            fields[i] = { f.name, wj.i32 }
        else
            fields[i] = { f.name, resolve_type(type_map, f.type) }
        end
    end
    return wj.struct((opts.name or self.full_name:gsub("[.%-]", "_") .. "_Storage"), fields, {
        packed = opts.packed,
        align = opts.align,
    })
end

function DescriptorMT:hash_quote(type_map, prefix)
    type_map = type_map or self.schema.type_map or {}
    prefix = prefix or ""
    local cache = rawget(self, "_hash_quote_cache")
    if cache == nil then
        cache = {}
        rawset(self, "_hash_quote_cache", cache)
    end
    local key = quote_key_from_parts({ tostring(prefix) })
    local hit = cache[key]
    if hit ~= nil then
        return hit
    end

    local params = self:param_list(type_map, prefix)
    local param_names = {}
    for i = 1, #params do param_names[i] = params[i].name end

    local q = wj.quote_expr {
        params = params,
        ret = wj.u32,
        body = function(...)
            local args = { ... }
            local acc_hash = wj.u32("acc_hash", wj.u32(2166136261))
            for i = 1, #self.fields do
                local f = self.fields[i]
                local wt = f.list and wj.i32 or resolve_type(type_map, f.type)
                acc_hash(mix_u32:inline_call(acc_hash, field_to_u32(args[i], wt)))
            end
            return acc_hash
        end,
    }
    cache[key] = q
    return q
end

function DescriptorMT:eq_quote(type_map, lhs_prefix, rhs_prefix)
    type_map = type_map or self.schema.type_map or {}
    lhs_prefix = lhs_prefix or "lhs_"
    rhs_prefix = rhs_prefix or "rhs_"
    local cache = rawget(self, "_eq_quote_cache")
    if cache == nil then
        cache = {}
        rawset(self, "_eq_quote_cache", cache)
    end
    local key = quote_key_from_parts({ tostring(lhs_prefix), tostring(rhs_prefix) })
    local hit = cache[key]
    if hit ~= nil then
        return hit
    end

    local params = self:eq_param_list(type_map, lhs_prefix, rhs_prefix)
    local arity = #self.fields
    local q = wj.quote_expr {
        params = params,
        ret = wj.i32,
        body = function(...)
            local args = { ... }
            local ok = wj.i32("ok", 1)
            for i = 1, arity do
                ok(ok:band(args[i]:eq(args[arity + i])))
            end
            return ok
        end,
    }
    cache[key] = q
    return q
end

local function resolve_runtime_arg(runtime, value)
    if type(value) == "number" then
        return value
    end
    return runtime_value_to_handle(runtime, value)
end

function RuntimeMT:descriptor()
    return self.desc
end

function RuntimeMT:len()
    return self.count
end

function RuntimeMT:handle_of(...)
    return self:new(...)
end

function RuntimeMT:_new_resolved(args)
    local hash = self.hash_fn(table.unpack(args, 1, #args))
    local bucket = self.buckets[hash]
    if bucket ~= nil then
        for i = 1, #bucket do
            local handle = bucket[i]
            if self.eq_slot_fn(self.base_offset, handle - 1, table.unpack(args, 1, #args)) ~= 0 then
                return handle
            end
        end
    end
    assert(self.count < self.capacity, ("asdljit runtime for %s is full (capacity=%d)"):format(self.desc.full_name, self.capacity))
    local slot = self.count
    self.store_fn(self.base_offset, slot, table.unpack(args, 1, #args))
    local handle = slot + 1
    self.count = handle
    if bucket == nil then
        bucket = {}
        self.buckets[hash] = bucket
    end
    bucket[#bucket + 1] = handle
    return handle
end

function RuntimeMT:new(...)
    local argc = select("#", ...)
    assert(argc == #self.desc.fields, ("asdljit runtime for %s expects %d args, got %d"):format(self.desc.full_name, #self.desc.fields, argc))
    local args = { ... }
    for i = 1, #args do
        if self.field_runtimes[i] ~= nil then
            args[i] = runtime_value_to_handle(self.field_runtimes[i], args[i])
        elseif self.list_runtimes[i] ~= nil then
            args[i] = self.list_runtimes[i]:new(args[i])
        end
    end
    return self:_new_resolved(args)
end

function RuntimeMT:get_handles(handle)
    assert(type(handle) == "number" and handle >= 1 and handle <= self.count, "asdljit runtime:get_handles invalid handle")
    local slot = handle - 1
    local base = self.mem_base + self.base_offset + slot * self.layout.size
    local out = {}
    for i = 1, #self.desc.fields do
        local f = self.desc.fields[i]
        local entry = self.layout.offsets[f.name]
        out[f.name] = read_field_value(base, entry.offset, self.field_types[i])
    end
    return out
end

function RuntimeMT:get(handle)
    local out = self:get_handles(handle)
    for i = 1, #self.desc.fields do
        local f = self.desc.fields[i]
        local value = out[f.name]
        if self.field_runtimes[i] ~= nil then
            value = self.field_runtimes[i]:get(value)
        elseif self.list_runtimes[i] ~= nil then
            value = self.list_runtimes[i]:get(value)
        end
        out[f.name] = value
    end
    return out
end

function RuntimeMT:raw(handle)
    local rec = self:get(handle)
    local out = {}
    for i = 1, #self.desc.fields do
        out[i] = rec[self.desc.fields[i].name]
    end
    return table.unpack(out, 1, #out)
end

function RuntimeMT:raw_handles(handle)
    local rec = self:get_handles(handle)
    local out = {}
    for i = 1, #self.desc.fields do
        out[i] = rec[self.desc.fields[i].name]
    end
    return table.unpack(out, 1, #out)
end

function RuntimeMT:with(handle, overrides)
    assert(type(overrides) == "table", "asdljit runtime:with expects overrides table")
    local raw = self:get_handles(handle)
    local args = {}
    for i = 1, #self.desc.fields do
        local f = self.desc.fields[i]
        local v = overrides[f.name]
        if v == nil then
            args[i] = raw[f.name]
        elseif self.field_runtimes[i] ~= nil then
            args[i] = resolve_runtime_arg(self.field_runtimes[i], v)
        elseif self.list_runtimes[i] ~= nil then
            args[i] = resolve_runtime_arg(self.list_runtimes[i], v)
        else
            args[i] = v
        end
    end
    return self:_new_resolved(args)
end

function RuntimeMT:wat()
    return self.mod:wat()
end

function DescriptorMT:runtime(opts)
    opts = opts or {}
    assert(self.unique, "asdljit runtime MVP only supports unique descriptors")
    local type_map = opts.type_map or self.schema.type_map or {}
    local fields = self.fields
    for i = 1, #fields do
        assert(not fields[i].optional, "asdljit runtime MVP does not support optional fields yet")
    end

    local runtime_type_map = shallow_copy(type_map)
    local field_runtimes = {}
    local list_runtimes = {}
    local field_types = {}
    for i = 1, #fields do
        local f = fields[i]
        if f.list then
            local provided = opts.list_runtimes and opts.list_runtimes[f.name] or nil
            if provided ~= nil then
                list_runtimes[i] = provided
            else
                local list_opts = opts.list_options and shallow_copy(opts.list_options[f.name]) or {}
                list_opts.type_map = type_map
                if list_opts.elem_runtime == nil and opts.field_runtimes and opts.field_runtimes[f.name] ~= nil then
                    list_opts.elem_runtime = opts.field_runtimes[f.name]
                end
                list_opts.name = list_opts.name or (self.full_name:gsub("[.%-]", "_") .. "_" .. f.name .. "_List")
                list_runtimes[i] = self.schema:list_runtime(f.type, list_opts)
            end
            field_types[i] = wj.i32
        else
            local frt = opts.field_runtimes and opts.field_runtimes[f.name] or nil
            if frt ~= nil then
                field_runtimes[i] = frt
                runtime_type_map[f.type] = wj.i32
                runtime_type_map[basename(f.type)] = wj.i32
                field_types[i] = wj.i32
            else
                field_types[i] = resolve_type(type_map, f.type)
            end
        end
    end

    local layout = self:layout(runtime_type_map, { name = self.full_name:gsub("[.%-]", "_") .. "_RuntimeStorage" })
    local hash_q = self:hash_quote(runtime_type_map, "arg_")
    local params = self:param_list(runtime_type_map, "arg_")
    local hash_fn = wj.fn {
        name = self.full_name:gsub("[.%-]", "_") .. "_hash_fn",
        params = params,
        ret = wj.u32,
        body = function(...)
            return hash_q(...)
        end,
    }

    local eq_params = { wj.i32 "base", wj.i32 "slot" }
    for i = 1, #params do
        eq_params[#eq_params + 1] = params[i]
    end
    local desc = self
    local eq_slot_fn = wj.fn {
        name = self.full_name:gsub("[.%-]", "_") .. "_eq_slot_fn",
        params = eq_params,
        ret = wj.i32,
        body = function(base, slot, ...)
            local args = { ... }
            local node = layout.at(base + slot * layout.size)
            local ok = wj.i32("ok", 1)
            for i = 1, #desc.fields do
                local f = desc.fields[i]
                ok(ok:band(node[f.name]:eq(args[i])))
            end
            return ok
        end,
    }

    local store_params = { wj.i32 "base", wj.i32 "slot" }
    for i = 1, #params do
        store_params[#store_params + 1] = params[i]
    end
    local store_fn = wj.fn {
        name = self.full_name:gsub("[.%-]", "_") .. "_store_fn",
        params = store_params,
        body = function(base, slot, ...)
            local args = { ... }
            local node = layout.at(base + slot * layout.size)
            for i = 1, #desc.fields do
                local f = desc.fields[i]
                node[f.name](args[i])
            end
        end,
    }

    local cap = opts.capacity or 4096
    local bytes = opts.bytes or (256 + layout.size * cap)
    local base_offset = opts.base_offset or 128
    local pages = wj.pages_for_bytes(math.max(bytes, base_offset + layout.size * cap))
    local mod = wj.module({ hash_fn, eq_slot_fn, store_fn }, { memory_pages = pages })
    local inst = mod:compile(opts.engine or wm.engine())

    return setmetatable({
        desc = self,
        layout = layout,
        field_types = field_types,
        field_runtimes = field_runtimes,
        list_runtimes = list_runtimes,
        capacity = cap,
        count = 0,
        buckets = {},
        mod = mod,
        inst = inst,
        mem_base = select(1, inst:memory("memory")),
        base_offset = base_offset,
        hash_fn = inst:fn(hash_fn.name),
        eq_slot_fn = inst:fn(eq_slot_fn.name),
        store_fn = inst:fn(store_fn.name),
    }, RuntimeMT)
end

function DescriptorMT:describe()
    return {
        kind = self.kind,
        name = self.name,
        full_name = self.full_name,
        parent_sum = self.parent_sum,
        unique = self.unique,
        fields = shallow_copy(self.fields),
    }
end

local function make_descriptor(schema, spec)
    return setmetatable({
        schema = schema,
        kind = spec.kind,
        name = basename(spec.name),
        full_name = spec.name,
        parent_sum = spec.parent_sum,
        unique = spec.unique or false,
        fields = normalize_field_list(spec.fields),
    }, DescriptorMT)
end

local function register_definition(schema, def)
    if def.type.kind == "product" then
        set_definition(schema, def.name, make_descriptor(schema, {
            kind = "product",
            name = def.name,
            fields = def.type.fields,
            unique = def.type.unique,
        }))
        return
    end

    if def.type.kind == "sum" then
        local sum_desc = {
            kind = "sum",
            name = def.name,
            full_name = def.name,
            constructors = {},
        }
        set_definition(schema, def.name, sum_desc)
        for i = 1, #def.type.constructors do
            local ctor = def.type.constructors[i]
            local desc = make_descriptor(schema, {
                kind = "constructor",
                name = ctor.name,
                fields = ctor.fields,
                unique = ctor.unique,
                parent_sum = def.name,
            })
            sum_desc.constructors[#sum_desc.constructors + 1] = desc
            set_definition(schema, ctor.name, desc)
        end
    end
end

function M.compile(text, opts)
    assert(type(text) == "string", "asdljit.compile: text must be a string")
    opts = opts or {}
    local defs = parser.parse(text)
    local schema = setmetatable({
        text = text,
        defs = defs,
        definitions = {},
        namespaces = {},
        type_map = shallow_copy(opts.type_map),
    }, SchemaMT)

    for i = 1, #defs do
        register_definition(schema, defs[i])
    end
    return schema
end

function SchemaMT:__index(key)
    return self.namespaces[key] or self.definitions[key] or SchemaMT[key]
end

function SchemaMT:describe()
    local names = {}
    for name, _v in pairs(self.definitions) do
        names[#names + 1] = name
    end
    table.sort(names)
    return {
        text = self.text,
        definitions = names,
    }
end

M.mix_u32 = mix_u32

return M
