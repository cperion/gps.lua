local ffi = require("ffi")
local wj = require("watjit")
local S = require("watjit.stream")
local SC = require("watjit.stream_compile")
local wm = require("watjit.wasmtime")
local slabmod = require("watjit.slab")
local lrumod = require("watjit.lru")
local ok_pvm, maybe_pvm = pcall(require, "pvm")
local pvm_classof = ok_pvm and maybe_pvm.classof or nil

local REF_SLOT_STRIDE = 1048576
local entry_state
local entry_set_state
local entry_active_cursors
local entry_add_active_cursors
local entry_result_bytes
local entry_set_result_bytes
local entry_lru_slot
local entry_set_lru_slot
local entry_phase_slot
local entry_set_phase_slot
local entry_cache_slot
local entry_set_cache_slot
local native_cursor_meta_manager
local init_cursor_payload_store

local function weak_key_table()
    return setmetatable({}, { __mode = "k" })
end

local function native_node_key(node)
    if type(node) ~= "table" then
        return nil
    end
    local mt = getmetatable(node)
    local class = mt and mt.__class or nil
    if class == nil then
        return nil
    end
    local class_id = rawget(class, "__ref_class_id")
    local slot = rawget(node, "__slot")
    if class_id == nil or slot == nil then
        return nil
    end
    return class_id * REF_SLOT_STRIDE + slot
end

local function cache_lookup_entry(cache, node, ...)
    local argc = select("#", ...)
    if argc == 0 and cache.native ~= nil then
        local key = native_node_key(node)
        if key ~= nil then
            local slot = cache.native.lookup(cache.native.slot_base, key, key)
            if slot ~= nil and slot > 0 then
                return cache.native.entries[slot]
            end
        end
    end
    local root = cache.weak[node]
    if root == nil then
        return nil
    end
    if argc == 0 then
        return root.entry
    end
    local t = root.args
    for i = 1, argc do
        if t == nil then
            return nil
        end
        t = t[select(i, ...)]
    end
    return t
end

local function cache_store_entry(cache, node, entry, ...)
    local argc = select("#", ...)
    if argc == 0 and cache.native ~= nil then
        local key = native_node_key(node)
        if key ~= nil then
            if entry_cache_slot(entry) == 0 then
                local slot = cache.native.alloc(cache.native.slot_base)
                if slot ~= nil and slot >= 0 then
                    entry_set_cache_slot(entry, slot + 1)
                    cache.native.entries[entry_cache_slot(entry)] = entry
                end
            end
            if entry_cache_slot(entry) ~= 0 then
                cache.native.entries[entry_cache_slot(entry)] = entry
                cache.native.store(cache.native.slot_base, key, key, entry_cache_slot(entry))
            end
        end
    end
    local root = cache.weak[node]
    if root == nil then
        root = {}
        cache.weak[node] = root
    end
    if argc == 0 then
        root.entry = entry
        return entry
    end
    local t = root.args
    if t == nil then
        t = {}
        root.args = t
    end
    for i = 1, argc - 1 do
        local key = select(i, ...)
        local next_t = t[key]
        if next_t == nil then
            next_t = {}
            t[key] = next_t
        end
        t = next_t
    end
    t[select(argc, ...)] = entry
    return entry
end

local function cache_clear_entry(cache, node, ...)
    local argc = select("#", ...)
    if argc == 0 and cache.native ~= nil then
        local key = native_node_key(node)
        if key ~= nil then
            local slot = cache.native.lookup(cache.native.slot_base, key, key)
            if slot ~= nil and slot > 0 then
                cache.native.clear(cache.native.slot_base, key, key)
                cache.native.entries[slot] = nil
                cache.native.free(cache.native.slot_base, slot - 1)
            end
        end
    end
    local root = cache.weak[node]
    if root == nil then
        return
    end
    if argc == 0 then
        root.entry = nil
        return
    end
    local t = root.args
    for i = 1, argc - 1 do
        if t == nil then
            return
        end
        t = t[select(i, ...)]
    end
    if t ~= nil then
        t[select(argc, ...)] = nil
    end
end

local function scalar_ctype(item_t)
    if item_t == wj.i32 then return "int32_t" end
    if item_t == wj.i64 then return "int64_t" end
    if item_t == wj.f32 then return "float" end
    if item_t == wj.f64 then return "double" end
    error("iwatjit.drain only supports scalar numeric item types", 3)
end

local HOST_CURSOR_RT = false

local function ensure_host_cursor_rt()
    if HOST_CURSOR_RT ~= false then
        return HOST_CURSOR_RT
    end
    local engine = wm.engine()
    local cursor_meta = native_cursor_meta_manager("iwj_host_cursor", 262144, engine)
    HOST_CURSOR_RT = {
        engine = engine,
        cursor_meta = cursor_meta,
        cursor_payload = init_cursor_payload_store(cursor_meta.capacity),
    }
    return HOST_CURSOR_RT
end

local function infer_runtime(plan)
    if plan == nil then
        return ensure_host_cursor_rt()
    end
    local rt = rawget(plan, "_iwj_rt")
    if rt ~= nil then
        return rt
    end
    local kind = rawget(plan, "kind")
    if kind == "map" or kind == "filter" or kind == "take" or kind == "drop" or kind == "simd_map" then
        return infer_runtime(plan.src)
    elseif kind == "concat" then
        return infer_runtime(plan.left or plan.right)
    elseif kind == "recording" and plan.entry ~= nil then
        return plan.entry.rt
    end
    return ensure_host_cursor_rt()
end

local function terminal_entry(rt, plan, terminal)
    local entry = rt.terminals[plan]
    if entry == nil then
        entry = {}
        rt.terminals[plan] = entry
    end
    local t = entry[terminal]
    if t == nil then
        t = {}
        entry[terminal] = t
    end
    return t
end

local function compile_count_kernel(rt, plan)
    local entry = terminal_entry(rt, plan, "count")
    if entry.fn ~= nil then
        return entry.fn, entry.inst
    end
    rt.serial = rt.serial + 1
    local fn = SC.compile_count {
        name = ("iwj_count_%d"):format(rt.serial),
        params = {},
        build = function()
            return plan
        end,
    }
    local inst = wj.module({ fn }):compile(rt.engine)
    entry.fn = inst:fn(fn.name)
    entry.inst = inst
    return entry.fn, inst
end

local function known_count(rt, plan)
    local n = rawget(plan, "count_hint")
    if n ~= nil then
        return n
    end
    local entry = terminal_entry(rt, plan, "count")
    if entry.value ~= nil then
        return entry.value
    end
    local fn = compile_count_kernel(rt, plan)
    entry.value = fn()
    return entry.value
end

local function compile_drain_kernel(rt, plan)
    local entry = terminal_entry(rt, plan, "drain")
    if entry.fn ~= nil then
        return entry.fn, entry.inst
    end
    local n = known_count(rt, plan)
    local pages = wj.pages_for_bytes(math.max(1, n * plan.item_t.size))
    rt.serial = rt.serial + 1
    local fn = SC.compile_drain_into {
        name = ("iwj_drain_%d"):format(rt.serial),
        params = { wj.i32 "out_base" },
        build = function(out_base)
            return plan, out_base
        end,
    }
    local inst = wj.module({ fn }, { memory_pages = pages }):compile(rt.engine)
    entry.fn = inst:fn(fn.name)
    entry.inst = inst
    return entry.fn, inst
end

local function compile_sum_kernel(rt, plan, vector_t)
    local key = vector_t or false
    local entry = terminal_entry(rt, plan, "sum")
    local sub = entry[key]
    if sub ~= nil then
        return sub.fn, sub.inst
    end
    rt.serial = rt.serial + 1
    local fn = SC.compile_sum {
        name = ("iwj_sum_%d"):format(rt.serial),
        params = {},
        ret = plan.item_t,
        vector_t = vector_t,
        build = function()
            return plan
        end,
    }
    local inst = wj.module({ fn }):compile(rt.engine)
    sub = { fn = inst:fn(fn.name), inst = inst }
    entry[key] = sub
    return sub.fn, inst
end

local function compile_one_kernel(rt, plan, default)
    local entry = terminal_entry(rt, plan, "one")
    if entry.fn ~= nil then
        return entry.fn, entry.inst
    end
    rt.serial = rt.serial + 1
    local fn = SC.compile_one {
        name = ("iwj_one_%d"):format(rt.serial),
        params = {},
        ret = plan.item_t,
        default = default,
        build = function()
            return plan
        end,
    }
    local inst = wj.module({ fn }):compile(rt.engine)
    entry.fn = inst:fn(fn.name)
    entry.inst = inst
    return entry.fn, inst
end

local function host_value(v)
    if type(v) == "table" and v.expr ~= nil and v.expr.op == "const" then
        return v.expr.value
    end
    return v
end

local function align_up(n, a)
    if a == nil or a <= 1 then
        return n
    end
    local r = n % a
    if r == 0 then
        return n
    end
    return n + (a - r)
end

local function native_phase_index_manager(name, capacity, engine)
    if capacity == nil or capacity <= 0 then
        return nil
    end
    local slot_count = 1
    while slot_count < capacity * 2 do
        slot_count = slot_count * 2
    end
    local slab = slabmod(name .. "_cache_slots", 4, capacity)
    local i32 = wj.i32
    local keys_base = align_up(slab.memory_bytes, 8)
    local vals_base = keys_base + slot_count * 4
    local memory_bytes = vals_base + slot_count * 4
    local mask = slot_count - 1

    local lookup = wj.fn {
        name = name .. "_lookup",
        params = { i32 "base", i32 "hash", i32 "key" },
        ret = i32,
        body = function(base, hash, key)
            local keys = wj.view(i32, i32(keys_base))
            local vals = wj.view(i32, i32(vals_base))
            local idx = wj.let(i32, "idx", hash - (hash / i32(slot_count)) * i32(slot_count))
            local remain = wj.let(i32, "remain", slot_count)
            local out = wj.let(i32, "out", 0)
            local active = wj.let(i32, "active", 1)
            local zero = i32(0)
            local one = i32(1)
            local tomb = i32(-1)
            wj.while_(active:ne(0), function()
                local k = wj.let(i32, "k", keys[idx])
                wj.if_(k:eq(zero), function()
                    active(0)
                end, function()
                    wj.if_(k:eq(key), function()
                        out(vals[idx])
                        active(0)
                    end, function()
                        remain(remain - one)
                        wj.if_(remain:eq(0), function()
                            active(0)
                        end, function()
                            wj.if_(k:eq(tomb), function()
                            end)
                            wj.if_((idx + one):lt(i32(slot_count)), function()
                                idx(idx + one)
                            end, function()
                                idx(zero)
                            end)
                        end)
                    end)
                end)
            end)
            return out
        end,
    }

    local store = wj.fn {
        name = name .. "_store",
        params = { i32 "base", i32 "hash", i32 "key", i32 "value" },
        body = function(base, hash, key, value)
            local keys = wj.view(i32, i32(keys_base))
            local vals = wj.view(i32, i32(vals_base))
            local idx = wj.let(i32, "idx", hash - (hash / i32(slot_count)) * i32(slot_count))
            local remain = wj.let(i32, "remain", slot_count)
            local active = wj.let(i32, "active", 1)
            local first_tomb = wj.let(i32, "first_tomb", -1)
            local zero = i32(0)
            local one = i32(1)
            local tomb = i32(-1)
            wj.while_(active:ne(0), function()
                local k = wj.let(i32, "k", keys[idx])
                wj.if_(k:eq(key), function()
                    vals[idx](value)
                    active(0)
                end, function()
                    wj.if_(k:eq(zero), function()
                        local dst = wj.let(i32, "dst", idx)
                        wj.if_(first_tomb:ge(zero), function()
                            dst(first_tomb)
                        end)
                        keys[dst](key)
                        vals[dst](value)
                        active(0)
                    end, function()
                        wj.if_(k:eq(tomb), function()
                            wj.if_(first_tomb:lt(zero), function()
                                first_tomb(idx)
                            end)
                        end)
                        remain(remain - one)
                        wj.if_(remain:eq(0), function()
                            wj.if_(first_tomb:ge(zero), function()
                                keys[first_tomb](key)
                                vals[first_tomb](value)
                            end)
                            active(0)
                        end, function()
                            wj.if_((idx + one):lt(i32(slot_count)), function()
                                idx(idx + one)
                            end, function()
                                idx(zero)
                            end)
                        end)
                    end)
                end)
            end)
        end,
    }

    local clear = wj.fn {
        name = name .. "_clear",
        params = { i32 "base", i32 "hash", i32 "key" },
        body = function(base, hash, key)
            local keys = wj.view(i32, i32(keys_base))
            local vals = wj.view(i32, i32(vals_base))
            local idx = wj.let(i32, "idx", hash - (hash / i32(slot_count)) * i32(slot_count))
            local remain = wj.let(i32, "remain", slot_count)
            local active = wj.let(i32, "active", 1)
            local zero = i32(0)
            local one = i32(1)
            local tomb = i32(-1)
            wj.while_(active:ne(0), function()
                local k = wj.let(i32, "k", keys[idx])
                wj.if_(k:eq(zero), function()
                    active(0)
                end, function()
                    wj.if_(k:eq(key), function()
                        keys[idx](tomb)
                        vals[idx](zero)
                        active(0)
                    end, function()
                        remain(remain - one)
                        wj.if_(remain:eq(0), function()
                            active(0)
                        end, function()
                            wj.if_((idx + one):lt(i32(slot_count)), function()
                                idx(idx + one)
                            end, function()
                                idx(zero)
                            end)
                        end)
                    end)
                end)
            end)
        end,
    }

    local mod = wj.module({ slab.init, slab.alloc, slab.free, lookup, store, clear }, {
        memory_pages = wj.pages_for_bytes(memory_bytes),
    })
    local inst = mod:compile(engine)
    inst:fn(slab.init.name)(0)
    return {
        slot_base = 0,
        alloc = inst:fn(slab.alloc.name),
        free = inst:fn(slab.free.name),
        lookup = inst:fn(lookup.name),
        store = inst:fn(store.name),
        clear = inst:fn(clear.name),
        entries = {},
        inst = inst,
    }
end

local function native_lru_manager(name, capacity, engine)
    if capacity == nil or capacity <= 0 then
        return nil
    end
    local slab = slabmod(name .. "_slab", 4, capacity)
    local lru = lrumod(name .. "_lru", capacity)
    local slab_base = 0
    local lru_base = align_up(slab.memory_bytes, 8)
    local mod = wj.module({
        slab.init, slab.alloc, slab.free, slab.addr, slab.reset,
        lru.init, lru.push_head, lru.remove, lru.touch, lru.pop_tail, lru.head, lru.tail, lru.is_linked, lru.reset,
    }, {
        memory_pages = wj.pages_for_bytes(lru_base + lru.memory_bytes),
    })
    local inst = mod:compile(engine)
    inst:fn(slab.init.name)(slab_base)
    inst:fn(lru.init.name)(lru_base)
    return {
        capacity = capacity,
        slab_base = slab_base,
        lru_base = lru_base,
        alloc = inst:fn(slab.alloc.name),
        free = inst:fn(slab.free.name),
        push_head = inst:fn(lru.push_head.name),
        remove = inst:fn(lru.remove.name),
        touch = inst:fn(lru.touch.name),
        head = inst:fn(lru.head.name),
        tail = inst:fn(lru.tail.name),
        entries = {},
        inst = inst,
    }
end

local function native_lru_alloc_slot(manager, entry)
    if manager == nil then
        return nil
    end
    local slot = manager.alloc(manager.slab_base)
    if slot == nil or slot < 0 then
        return nil
    end
    manager.entries[slot] = entry
    return slot
end

local function native_lru_free_slot(manager, slot)
    if manager == nil or slot == nil then
        return
    end
    manager.remove(manager.lru_base, slot)
    manager.entries[slot] = nil
    manager.free(manager.slab_base, slot)
end

local function native_lru_push_head(manager, slot)
    if manager ~= nil and slot ~= nil then
        manager.push_head(manager.lru_base, slot)
    end
end

local function native_lru_touch(manager, slot)
    if manager ~= nil and slot ~= nil then
        manager.touch(manager.lru_base, slot)
    end
end

local function native_lru_tail_entry(manager)
    if manager == nil then
        return nil
    end
    local slot = manager.tail(manager.lru_base)
    if slot == nil or slot < 0 then
        return nil
    end
    return manager.entries[slot], slot
end

local STATE_PENDING = 1
local STATE_COMMITTED = 2
local STATE_CANCELLED = 3
local STATE_EVICTED = 4

local function native_entry_meta_manager(name, capacity, engine)
    local slab = slabmod(name .. "_entry_meta", 24, capacity)
    local mod = wj.module({ slab.init, slab.alloc, slab.free, slab.addr, slab.reset }, {
        memory_pages = wj.pages_for_bytes(slab.memory_bytes),
    })
    local inst = mod:compile(engine)
    local init = inst:fn(slab.init.name)
    init(0)
    local base = ffi.cast("uint8_t*", select(1, inst:memory("memory")))
    return {
        slot_base = 0,
        alloc = inst:fn(slab.alloc.name),
        free = inst:fn(slab.free.name),
        base = base,
        data_offset = slab.data_offset,
        slot_size = slab.slot_size,
        inst = inst,
    }
end

local function entry_meta_ptr(entry)
    local meta = entry.rt.entry_meta
    return ffi.cast("int32_t*", meta.base + meta.data_offset + entry.meta_slot * meta.slot_size)
end

entry_state = function(entry)
    return entry_meta_ptr(entry)[0]
end

entry_set_state = function(entry, state)
    entry_meta_ptr(entry)[0] = state
end

entry_active_cursors = function(entry)
    return entry_meta_ptr(entry)[1]
end

entry_add_active_cursors = function(entry, delta)
    local meta = entry_meta_ptr(entry)
    meta[1] = meta[1] + delta
    return meta[1]
end

entry_result_bytes = function(entry)
    return entry_meta_ptr(entry)[2]
end

entry_set_result_bytes = function(entry, n)
    entry_meta_ptr(entry)[2] = n or 0
end

entry_lru_slot = function(entry)
    return entry_meta_ptr(entry)[3]
end

entry_set_lru_slot = function(entry, slot)
    entry_meta_ptr(entry)[3] = slot == nil and -1 or slot
end

entry_phase_slot = function(entry)
    return entry_meta_ptr(entry)[4]
end

entry_set_phase_slot = function(entry, slot)
    entry_meta_ptr(entry)[4] = slot == nil and -1 or slot
end

entry_cache_slot = function(entry)
    return entry_meta_ptr(entry)[5]
end

entry_set_cache_slot = function(entry, slot)
    entry_meta_ptr(entry)[5] = slot == nil and 0 or slot
end

local function alloc_entry_meta(rt)
    local slot = rt.entry_meta.alloc(rt.entry_meta.slot_base)
    if slot == nil or slot < 0 then
        error("iwatjit: native entry metadata exhausted", 2)
    end
    local meta = ffi.cast("int32_t*", rt.entry_meta.base + rt.entry_meta.data_offset + slot * rt.entry_meta.slot_size)
    meta[0] = STATE_PENDING
    meta[1] = 0
    meta[2] = 0
    meta[3] = -1
    meta[4] = -1
    meta[5] = 0
    return slot
end

local function free_entry_meta(entry)
    if entry == nil or entry.meta_slot == nil then
        return
    end
    entry.rt.entry_meta.free(entry.rt.entry_meta.slot_base, entry.meta_slot)
    entry.meta_slot = nil
end

native_cursor_meta_manager = function(name, capacity, engine)
    local slab = slabmod(name .. "_cursor_meta", 24, capacity)
    local mod = wj.module({ slab.init, slab.alloc, slab.free, slab.addr, slab.reset }, {
        memory_pages = wj.pages_for_bytes(slab.memory_bytes),
    })
    local inst = mod:compile(engine)
    local init = inst:fn(slab.init.name)
    init(0)
    local base = ffi.cast("uint8_t*", select(1, inst:memory("memory")))
    return {
        slot_base = 0,
        capacity = capacity,
        alloc = inst:fn(slab.alloc.name),
        free = inst:fn(slab.free.name),
        base = base,
        data_offset = slab.data_offset,
        slot_size = slab.slot_size,
        inst = inst,
    }
end

local function cursor_meta_ptr(cursor)
    if cursor == nil or cursor.meta_slot == nil then
        return nil
    end
    local meta = cursor.rt.cursor_meta
    return ffi.cast("int32_t*", meta.base + meta.data_offset + cursor.meta_slot * meta.slot_size)
end

local function alloc_cursor_meta(rt, index)
    local slot = rt.cursor_meta.alloc(rt.cursor_meta.slot_base)
    if slot == nil or slot < 0 then
        error("iwatjit: native cursor metadata exhausted", 2)
    end
    local meta = ffi.cast("int32_t*", rt.cursor_meta.base + rt.cursor_meta.data_offset + slot * rt.cursor_meta.slot_size)
    meta[0] = index or 0
    meta[1] = 0
    meta[2] = 0
    meta[3] = 0
    meta[4] = 0
    return slot
end

local function free_cursor_meta(cursor)
    if cursor == nil or cursor.meta_slot == nil then
        return
    end
    cursor.rt.cursor_meta.free(cursor.rt.cursor_meta.slot_base, cursor.meta_slot)
    cursor.meta_slot = nil
end

init_cursor_payload_store = function(capacity)
    return {
        ref0 = {},
        ref1 = {},
        ref2 = {},
        num0 = ffi.new("double[?]", capacity),
        num1 = ffi.new("double[?]", capacity),
        num2 = ffi.new("double[?]", capacity),
    }
end

local function cursor_payload(cursor)
    return cursor.rt.cursor_payload
end

local function cursor_payload_clear(cursor)
    if cursor == nil or cursor.meta_slot == nil then
        return
    end
    local slot = cursor.meta_slot
    local p = cursor.rt.cursor_payload
    p.ref0[slot] = nil
    p.ref1[slot] = nil
    p.ref2[slot] = nil
    p.num0[slot] = 0
    p.num1[slot] = 0
    p.num2[slot] = 0
end

local function cursor_index(cursor)
    local meta = cursor_meta_ptr(cursor)
    return meta and meta[0] or 0
end

local function cursor_set_index(cursor, n)
    local meta = cursor_meta_ptr(cursor)
    if meta ~= nil then
        meta[0] = n
    end
end

local function cursor_closed(cursor)
    local meta = cursor_meta_ptr(cursor)
    return meta == nil or meta[1] ~= 0
end

local function cursor_set_closed(cursor, yes)
    local meta = cursor_meta_ptr(cursor)
    if meta ~= nil then
        meta[1] = yes and 1 or 0
    end
end

local function cursor_kind(cursor)
    local meta = cursor_meta_ptr(cursor)
    return meta and meta[2] or 0
end

local function cursor_set_kind(cursor, kind)
    local meta = cursor_meta_ptr(cursor)
    if meta ~= nil then
        meta[2] = kind or 0
    end
end

local function cursor_aux0(cursor)
    local meta = cursor_meta_ptr(cursor)
    return meta and meta[3] or 0
end

local function cursor_set_aux0(cursor, n)
    local meta = cursor_meta_ptr(cursor)
    if meta ~= nil then
        meta[3] = n
    end
end

local function cursor_aux1(cursor)
    local meta = cursor_meta_ptr(cursor)
    return meta and meta[4] or 0
end

local function cursor_set_aux1(cursor, n)
    local meta = cursor_meta_ptr(cursor)
    if meta ~= nil then
        meta[4] = n
    end
end

local function resolve_stream(plan)
    if plan == nil then
        return nil
    end
    if plan.kind == "recording" then
        local entry = plan.entry
        if entry ~= nil and entry.stream ~= nil and entry.stream ~= plan then
            return resolve_stream(entry.stream)
        end
    end
    local seq = rawget(plan, "_iwj_seq")
    if seq ~= nil and seq ~= plan then
        return resolve_stream(seq)
    end
    return plan
end

local needs_host_eval
local open_host_cursor
local host_count
local touch_entry
local attach_runtime

local function next_pow2(n)
    local p = 1
    while p < n do
        p = p * 2
    end
    return p
end

attach_runtime = function(plan, rt, phase_name, seen)
    if plan == nil or type(plan) ~= "table" then
        return plan
    end
    seen = seen or weak_key_table()
    if seen[plan] then
        return plan
    end
    seen[plan] = true
    if rawget(plan, "_iwj_rt") == nil then
        plan._iwj_rt = rt
    end
    if rawget(plan, "_iwj_phase_name") == nil then
        plan._iwj_phase_name = phase_name
    end
    local kind = rawget(plan, "kind")
    if kind == "map" or kind == "filter" or kind == "take" or kind == "drop" or kind == "simd_map" then
        attach_runtime(plan.src, rt, phase_name, seen)
    elseif kind == "concat" then
        attach_runtime(plan.left, rt, phase_name, seen)
        attach_runtime(plan.right, rt, phase_name, seen)
    end
    return plan
end

local function result_bucket(rt, item_t, count)
    local by_type = rt.result.by_type[item_t]
    if by_type == nil then
        by_type = {
            item_t = item_t,
            ctype = scalar_ctype(item_t),
            buckets = {},
        }
        rt.result.by_type[item_t] = by_type
    end

    local slot_count = next_pow2(math.max(1, count))
    local bucket = by_type.buckets[slot_count]
    if bucket == nil then
        bucket = {
            ctype = by_type.ctype,
            item_t = item_t,
            slot_count = slot_count,
            slots_per_chunk = 64,
            chunks = {},
            free = {},
            next_slot = 0,
        }
        by_type.buckets[slot_count] = bucket
    end
    return bucket
end

local function alloc_slab_seq(rt, item_t, values, count)
    local bucket = result_bucket(rt, item_t, count)
    local slot_id = table.remove(bucket.free)
    if slot_id == nil then
        slot_id = bucket.next_slot
        bucket.next_slot = slot_id + 1
        if slot_id >= #bucket.chunks * bucket.slots_per_chunk then
            bucket.chunks[#bucket.chunks + 1] = ffi.new(bucket.ctype .. "[?]", bucket.slot_count * bucket.slots_per_chunk)
        end
    end

    local chunk_index = math.floor(slot_id / bucket.slots_per_chunk) + 1
    local slot_in_chunk = slot_id % bucket.slots_per_chunk
    local base = ffi.cast(bucket.ctype .. "*", bucket.chunks[chunk_index]) + slot_in_chunk * bucket.slot_count
    for i = 1, count do
        base[i - 1] = values[i]
    end

    local bytes = bucket.slot_count * item_t.size
    rt.result.used_bytes = rt.result.used_bytes + bytes
    rt.result.live_slots = rt.result.live_slots + 1
    return {
        bucket = bucket,
        slot_id = slot_id,
        ptr = base,
        count = count,
        capacity = bucket.slot_count,
        item_t = item_t,
        bytes = bytes,
    }
end

local function free_slab_seq(rt, slab)
    if slab == nil or slab.freed then
        return
    end
    slab.freed = true
    slab.bucket.free[#slab.bucket.free + 1] = slab.slot_id
    rt.result.used_bytes = rt.result.used_bytes - slab.capacity * slab.item_t.size
    rt.result.live_slots = rt.result.live_slots - 1
end

local function read_slab_seq(slab)
    local out = {}
    for i = 0, slab.count - 1 do
        out[#out + 1] = tonumber(slab.ptr[i])
    end
    return out
end

local function read_cached_seq_values(plan)
    if plan.slab ~= nil then
        return read_slab_seq(plan.slab)
    end
    return assert(plan.values, "cached_seq is missing slab and values storage")
end

local function plan_has_recording(plan)
    plan = resolve_stream(plan)
    local kind = plan.kind
    if kind == "recording" then
        return true
    elseif kind == "map" or kind == "filter" or kind == "take" or kind == "drop" or kind == "simd_map" then
        return plan_has_recording(plan.src)
    elseif kind == "concat" then
        return plan_has_recording(plan.left) or plan_has_recording(plan.right)
    end
    return false
end

local function plan_has_cached_seq(plan)
    plan = resolve_stream(plan)
    local kind = plan.kind
    if kind == "cached_seq" then
        return true
    elseif kind == "map" or kind == "filter" or kind == "take" or kind == "drop" or kind == "simd_map" then
        return plan_has_cached_seq(plan.src)
    elseif kind == "concat" then
        return plan_has_cached_seq(plan.left) or plan_has_cached_seq(plan.right)
    end
    return false
end

local function touch_cached_seq_leaves(plan, seen)
    plan = resolve_stream(plan)
    seen = seen or weak_key_table()
    if seen[plan] then
        return
    end
    seen[plan] = true
    local kind = plan.kind
    if kind == "cached_seq" then
        touch_entry(plan._iwj_cache_entry)
    elseif kind == "map" or kind == "filter" or kind == "take" or kind == "drop" or kind == "simd_map" then
        touch_cached_seq_leaves(plan.src, seen)
    elseif kind == "concat" then
        touch_cached_seq_leaves(plan.left, seen)
        touch_cached_seq_leaves(plan.right, seen)
    end
end

local function staged_plan_info(plan, out_item_t, out_count)
    local leaves = {}
    local offsets = setmetatable({}, { __mode = "k" })
    local offset = 0

    local function leaf_seq(node)
        local rec = offsets[node]
        if rec == nil then
            offset = align_up(offset, node.item_t.size)
            rec = {
                node = node,
                base = offset,
                count = node.count,
            }
            offsets[node] = rec
            leaves[#leaves + 1] = rec
            offset = offset + node.count * node.item_t.size
        end
        return S.seq(node.item_t, rec.base, rec.count)
    end

    local function rewrite(node)
        node = resolve_stream(node)
        local kind = node.kind
        if kind == "cached_seq" then
            return leaf_seq(node)
        elseif kind == "map" then
            return rewrite(node.src):map(node.item_t, node.f)
        elseif kind == "filter" then
            return rewrite(node.src):filter(node.pred)
        elseif kind == "concat" then
            return rewrite(node.left):concat(rewrite(node.right))
        elseif kind == "take" then
            return rewrite(node.src):take(node.n)
        elseif kind == "drop" then
            return rewrite(node.src):drop(node.n)
        elseif kind == "simd_map" then
            return rewrite(node.src):simd_map(node.vector_t, node.item_t, node.vf, node.sf)
        end
        return node
    end

    local rewritten = rewrite(plan)
    local out_base
    if out_item_t ~= nil and out_count ~= nil then
        offset = align_up(offset, out_item_t.size)
        out_base = offset
        offset = offset + out_count * out_item_t.size
    end
    return {
        rewritten = rewritten,
        leaves = leaves,
        out_base = out_base,
        total_bytes = offset,
    }
end

local function stage_cached_leaves(inst, info)
    local mem_base = select(1, inst:memory("memory"))
    for i = 1, #info.leaves do
        local leaf = info.leaves[i]
        local node = leaf.node
        local dst = mem_base + leaf.base
        if node.slab ~= nil then
            ffi.copy(dst, node.slab.ptr, node.count * node.item_t.size)
        else
            local dst_t = ffi.cast(scalar_ctype(node.item_t) .. "*", dst)
            local values = read_cached_seq_values(node)
            for j = 1, node.count do
                dst_t[j - 1] = values[j]
            end
        end
    end
end

local function compile_staged_count_kernel(rt, plan)
    local entry = terminal_entry(rt, plan, "staged_count")
    if entry.fn ~= nil then
        return entry.fn, entry.inst, entry.info
    end
    local info = staged_plan_info(plan)
    rt.serial = rt.serial + 1
    local fn = SC.compile_count {
        name = ("iwj_staged_count_%d"):format(rt.serial),
        params = {},
        build = function()
            return info.rewritten
        end,
    }
    local inst = wj.module({ fn }, { memory_pages = wj.pages_for_bytes(math.max(1, info.total_bytes)) }):compile(rt.engine)
    stage_cached_leaves(inst, info)
    entry.fn = inst:fn(fn.name)
    entry.inst = inst
    entry.info = info
    return entry.fn, inst, info
end

local function compile_staged_sum_kernel(rt, plan, vector_t)
    local key = vector_t or false
    local entry = terminal_entry(rt, plan, "staged_sum")
    local sub = entry[key]
    if sub ~= nil then
        return sub.fn, sub.inst, sub.info
    end
    local info = staged_plan_info(plan)
    rt.serial = rt.serial + 1
    local fn = SC.compile_sum {
        name = ("iwj_staged_sum_%d"):format(rt.serial),
        params = {},
        ret = info.rewritten.item_t,
        vector_t = vector_t,
        build = function()
            return info.rewritten
        end,
    }
    local inst = wj.module({ fn }, { memory_pages = wj.pages_for_bytes(math.max(1, info.total_bytes)) }):compile(rt.engine)
    stage_cached_leaves(inst, info)
    sub = { fn = inst:fn(fn.name), inst = inst, info = info }
    entry[key] = sub
    return sub.fn, inst, info
end

local function compile_staged_one_kernel(rt, plan, default)
    local key = default or false
    local entry = terminal_entry(rt, plan, "staged_one")
    local sub = entry[key]
    if sub ~= nil then
        return sub.fn, sub.inst, sub.info
    end
    local info = staged_plan_info(plan)
    rt.serial = rt.serial + 1
    local fn = SC.compile_one {
        name = ("iwj_staged_one_%d"):format(rt.serial),
        params = {},
        ret = info.rewritten.item_t,
        default = default,
        build = function()
            return info.rewritten
        end,
    }
    local inst = wj.module({ fn }, { memory_pages = wj.pages_for_bytes(math.max(1, info.total_bytes)) }):compile(rt.engine)
    stage_cached_leaves(inst, info)
    sub = { fn = inst:fn(fn.name), inst = inst, info = info }
    entry[key] = sub
    return sub.fn, inst, info
end

local function compile_staged_drain_kernel(rt, plan)
    local entry = terminal_entry(rt, plan, "staged_drain")
    if entry.fn ~= nil then
        return entry.fn, entry.inst, entry.info
    end
    local out_count = rawget(plan, "count_hint")
    if out_count == nil then
        local count_fn = compile_staged_count_kernel(rt, plan)
        out_count = count_fn()
    end
    local info = staged_plan_info(plan, plan.item_t, out_count)
    rt.serial = rt.serial + 1
    local fn = SC.compile_drain_into {
        name = ("iwj_staged_drain_%d"):format(rt.serial),
        params = {},
        build = function()
            return info.rewritten, info.out_base
        end,
    }
    local inst = wj.module({ fn }, { memory_pages = wj.pages_for_bytes(math.max(1, info.total_bytes)) }):compile(rt.engine)
    stage_cached_leaves(inst, info)
    entry.fn = inst:fn(fn.name)
    entry.inst = inst
    entry.info = info
    return entry.fn, inst, info
end

local function lru_remove(rt, entry)
    local slot = entry and entry_lru_slot(entry) or -1
    if slot >= 0 then
        rt.result.lru.entries[slot] = entry
        rt.result.lru.remove(rt.result.lru.lru_base, slot)
    end
end

local function lru_push_head(rt, entry)
    local slot = entry and entry_lru_slot(entry) or -1
    if slot < 0 then
        return
    end
    rt.result.lru.entries[slot] = entry
    native_lru_push_head(rt.result.lru, slot)
end

local function lru_touch(rt, entry)
    local slot = entry and entry_lru_slot(entry) or -1
    if entry ~= nil and entry_state(entry) == STATE_COMMITTED and slot >= 0 then
        rt.result.lru.entries[slot] = entry
        native_lru_touch(rt.result.lru, slot)
    end
end

local function phase_lru_remove(phase_cache, entry)
    local slot = entry and entry_phase_slot(entry) or -1
    if phase_cache == nil or slot < 0 then
        return
    end
    phase_cache.lru.entries[slot] = entry
    phase_cache.lru.remove(phase_cache.lru.lru_base, slot)
end

local function phase_lru_push_head(phase_cache, entry)
    local slot = entry and entry_phase_slot(entry) or -1
    if phase_cache == nil or slot < 0 then
        return
    end
    phase_cache.lru.entries[slot] = entry
    native_lru_push_head(phase_cache.lru, slot)
end

local function phase_lru_touch(entry)
    local phase_cache = entry.phase_cache
    local slot = entry and entry_phase_slot(entry) or -1
    if phase_cache ~= nil and entry_state(entry) == STATE_COMMITTED and slot >= 0 then
        phase_cache.lru.entries[slot] = entry
        native_lru_touch(phase_cache.lru, slot)
    end
end

function touch_entry(entry)
    if entry ~= nil and entry_state(entry) == STATE_COMMITTED then
        lru_touch(entry.rt, entry)
        phase_lru_touch(entry)
    end
end

local function evict_entry(rt, entry)
    if entry == nil or entry_state(entry) ~= STATE_COMMITTED then
        return false
    end
    if entry_lru_slot(entry) >= 0 then
        lru_remove(rt, entry)
        native_lru_free_slot(rt.result.lru, entry_lru_slot(entry))
        entry_set_lru_slot(entry, nil)
    end
    if entry_phase_slot(entry) >= 0 and entry.phase_cache ~= nil then
        phase_lru_remove(entry.phase_cache, entry)
        native_lru_free_slot(entry.phase_cache.lru, entry_phase_slot(entry))
        entry_set_phase_slot(entry, nil)
        entry.phase_cache.live = entry.phase_cache.live - 1
        entry.phase_cache.used_bytes = entry.phase_cache.used_bytes - entry_result_bytes(entry)
        entry.stats.live = entry.phase_cache.live
        entry.stats.memory = entry.phase_cache.used_bytes
    end
    local stream = entry.stream
    if stream ~= nil and stream.kind == "cached_seq" and stream.slab ~= nil then
        stream.values = read_slab_seq(stream.slab)
        free_slab_seq(rt, stream.slab)
        stream.slab = nil
        stream._iwj_gc = nil
    end
    entry_set_state(entry, STATE_EVICTED)
    entry.evicted = true
    entry.stats.evictions = entry.stats.evictions + 1
    rt.result.evictions = rt.result.evictions + 1
    cache_clear_entry(entry.cache, entry.cache_node, unpack(entry.cache_args))
    entry_set_cache_slot(entry, nil)
    return true
end

local function enforce_phase_capacity(phase_cache, keep)
    if phase_cache == nil or phase_cache.bounded == nil then
        return
    end
    while phase_cache.live > phase_cache.bounded do
        local tail = native_lru_tail_entry(phase_cache.lru)
        if tail == nil then
            break
        end
        if tail == keep then
            phase_lru_remove(phase_cache, keep)
            local next_tail = native_lru_tail_entry(phase_cache.lru)
            phase_lru_push_head(phase_cache, keep)
            tail = next_tail
        end
        if tail == nil or not evict_entry(tail.rt, tail) then
            break
        end
    end
end

local function enforce_result_capacity(rt, keep)
    local cap = rt.result.capacity
    if cap == nil then
        return
    end
    while rt.result.used_bytes > cap do
        local tail = native_lru_tail_entry(rt.result.lru)
        if tail == nil then
            break
        end
        if tail == keep then
            lru_remove(rt, keep)
            local next_tail = native_lru_tail_entry(rt.result.lru)
            lru_push_head(rt, keep)
            tail = next_tail
        end
        if tail == nil or not evict_entry(rt, tail) then
            break
        end
    end
end

local function commit_entry(entry)
    if entry_state(entry) == STATE_COMMITTED then
        touch_entry(entry)
        return entry.stream
    end
    local count = #entry.values
    local slab = alloc_slab_seq(entry.rt, entry.item_t, entry.values, count)
    local cached = S.cached_seq(entry.item_t, nil, count)
    cached.slab = slab
    cached.count = count
    cached.count_hint = count
    cached._iwj_rt = entry.rt
    cached._iwj_phase_name = entry.phase_name
    cached._iwj_cache_entry = entry
    cached._iwj_gc = ffi.gc(ffi.new("uint8_t[1]"), function()
        free_slab_seq(entry.rt, slab)
    end)
    entry_set_state(entry, STATE_COMMITTED)
    entry.stream = cached
    entry.count_hint = count
    entry.source_cursor = nil
    entry_set_result_bytes(entry, slab.bytes)
    entry.stats.commits = entry.stats.commits + 1
    if entry_lru_slot(entry) < 0 then
        entry_set_lru_slot(entry, native_lru_alloc_slot(entry.rt.result.lru, entry))
        while entry_lru_slot(entry) < 0 do
            local victim = native_lru_tail_entry(entry.rt.result.lru)
            if victim == nil or victim == entry or not evict_entry(entry.rt, victim) then
                error("iwatjit: global native LRU metadata exhausted", 2)
            end
            entry_set_lru_slot(entry, native_lru_alloc_slot(entry.rt.result.lru, entry))
        end
    end
    lru_push_head(entry.rt, entry)
    if entry.phase_cache ~= nil then
        if entry.phase_cache.lru ~= nil and entry_phase_slot(entry) < 0 then
            entry_set_phase_slot(entry, native_lru_alloc_slot(entry.phase_cache.lru, entry))
            if entry_phase_slot(entry) < 0 then
                local victim = native_lru_tail_entry(entry.phase_cache.lru)
                if victim ~= nil and victim ~= entry then
                    evict_entry(victim.rt, victim)
                    entry_set_phase_slot(entry, native_lru_alloc_slot(entry.phase_cache.lru, entry))
                end
            end
            if entry_phase_slot(entry) < 0 then
                error("iwatjit: phase native LRU metadata exhausted", 2)
            end
        end
        entry.phase_cache.live = entry.phase_cache.live + 1
        entry.phase_cache.used_bytes = entry.phase_cache.used_bytes + entry_result_bytes(entry)
        entry.stats.live = entry.phase_cache.live
        entry.stats.memory = entry.phase_cache.used_bytes
        phase_lru_push_head(entry.phase_cache, entry)
        enforce_phase_capacity(entry.phase_cache, entry)
    end
    enforce_result_capacity(entry.rt, entry)
    if entry_active_cursors(entry) == 0 then
        entry.values = nil
    end
    return cached
end

local function cancel_entry(entry)
    if entry_state(entry) ~= STATE_PENDING then
        return
    end
    entry_set_state(entry, STATE_CANCELLED)
    if entry.source_cursor ~= nil and entry.source_cursor.cancel ~= nil then
        entry.source_cursor:cancel()
    end
    entry.source_cursor = nil
    entry.values = {}
    entry.stream = nil
    cache_clear_entry(entry.cache, entry.cache_node, unpack(entry.cache_args))
    entry_set_cache_slot(entry, nil)
    entry.stats.cancels = entry.stats.cancels + 1
end

local function ensure_recording_source(entry)
    if entry.source_cursor ~= nil then
        return entry.source_cursor
    end
    entry.source_cursor = open_host_cursor(entry.plan)
    return entry.source_cursor
end

local function recording_advance(entry)
    if entry_state(entry) == STATE_COMMITTED then
        return nil
    end
    if entry_state(entry) ~= STATE_PENDING then
        return nil
    end
    local cursor = ensure_recording_source(entry)
    local v = cursor:next()
    if v == nil then
        commit_entry(entry)
        return nil
    end
    v = host_value(v)
    entry.values[#entry.values + 1] = v
    return v
end

local CURSOR_RECORDING  = 1
local CURSOR_CACHED_SLAB = 2
local CURSOR_CACHED_VALUES = 3
local CURSOR_RANGE = 4
local CURSOR_ONCE = 5
local CURSOR_EMPTY = 6
local CURSOR_MAP = 7
local CURSOR_FILTER = 8
local CURSOR_CONCAT = 9
local CURSOR_TAKE = 10
local CURSOR_DROP = 11
local CURSOR_SIMD_MAP = 12

local HostCursorMT = {}
HostCursorMT.__index = HostCursorMT

function HostCursorMT:cancel()
    if cursor_closed(self) then
        return
    end
    cursor_set_closed(self, true)
    local kind = cursor_kind(self)
    local p = cursor_payload(self)
    local slot = self.meta_slot
    if kind == CURSOR_RECORDING then
        local entry = p.ref0[slot]
        cursor_payload_clear(self)
        free_cursor_meta(self)
        local active = entry_add_active_cursors(entry, -1)
        if active == 0 then
            if entry_state(entry) == STATE_PENDING then
                cancel_entry(entry)
            elseif entry_state(entry) == STATE_COMMITTED then
                entry.values = nil
            end
        end
        return
    end
    local src = p.ref0[slot]
    local left = p.ref0[slot]
    local right = p.ref1[slot]
    cursor_payload_clear(self)
    free_cursor_meta(self)
    if kind == CURSOR_MAP or kind == CURSOR_FILTER or kind == CURSOR_TAKE or kind == CURSOR_DROP or kind == CURSOR_SIMD_MAP then
        if src ~= nil then src:cancel() end
    elseif kind == CURSOR_CONCAT then
        if left ~= nil then left:cancel() end
        if right ~= nil then right:cancel() end
    end
end

function HostCursorMT:next()
    if cursor_closed(self) then
        return nil
    end

    local kind = cursor_kind(self)
    local p = cursor_payload(self)
    local slot = self.meta_slot
    if kind == CURSOR_RECORDING then
        local entry = p.ref0[slot]
        local index = cursor_index(self)
        while index > #entry.values and entry_state(entry) == STATE_PENDING do
            local v = recording_advance(entry)
            if v == nil then
                break
            end
        end
        if index <= #entry.values then
            local v = entry.values[index]
            cursor_set_index(self, index + 1)
            return v
        end
        self:cancel()
        return nil
    elseif kind == CURSOR_CACHED_SLAB then
        local slab = p.ref0[slot]
        local index = cursor_index(self)
        if index >= slab.count then
            self:cancel()
            return nil
        end
        local v = tonumber(slab.ptr[index])
        cursor_set_index(self, index + 1)
        return v
    elseif kind == CURSOR_CACHED_VALUES then
        local values = p.ref0[slot]
        local count = cursor_aux0(self)
        local index = cursor_index(self)
        if index > count then
            self:cancel()
            return nil
        end
        local v = values[index]
        cursor_set_index(self, index + 1)
        return v
    elseif kind == CURSOR_RANGE then
        local current = p.num0[slot]
        local stop = p.num1[slot]
        local step = p.num2[slot]
        if step > 0 then
            if current >= stop then
                self:cancel()
                return nil
            end
        else
            if current <= stop then
                self:cancel()
                return nil
            end
        end
        p.num0[slot] = current + step
        return current
    elseif kind == CURSOR_ONCE then
        if cursor_aux0(self) ~= 0 then
            self:cancel()
            return nil
        end
        cursor_set_aux0(self, 1)
        return p.ref0[slot]
    elseif kind == CURSOR_EMPTY then
        self:cancel()
        return nil
    elseif kind == CURSOR_MAP then
        local src = p.ref0[slot]
        local f = p.ref1[slot]
        local v = src:next()
        if v == nil then
            self:cancel()
            return nil
        end
        return f(v)
    elseif kind == CURSOR_FILTER then
        local src = p.ref0[slot]
        local pred = p.ref1[slot]
        while true do
            local v = src:next()
            if v == nil then
                self:cancel()
                return nil
            end
            if pred(v) then
                return v
            end
        end
    elseif kind == CURSOR_CONCAT then
        local left = p.ref0[slot]
        local right = p.ref1[slot]
        if cursor_aux0(self) ~= 0 then
            local v = left:next()
            if v ~= nil then
                return v
            end
            cursor_set_aux0(self, 0)
        end
        local v = right:next()
        if v == nil then
            self:cancel()
        end
        return v
    elseif kind == CURSOR_TAKE then
        local src = p.ref0[slot]
        local remaining = cursor_aux0(self)
        if remaining <= 0 then
            self:cancel()
            return nil
        end
        local v = src:next()
        if v == nil then
            self:cancel()
            return nil
        end
        cursor_set_aux0(self, remaining - 1)
        return v
    elseif kind == CURSOR_DROP then
        local src = p.ref0[slot]
        while cursor_aux0(self) > 0 do
            local skipped = src:next()
            if skipped == nil then
                self:cancel()
                return nil
            end
            cursor_set_aux0(self, cursor_aux0(self) - 1)
        end
        local v = src:next()
        if v == nil then
            self:cancel()
        end
        return v
    elseif kind == CURSOR_SIMD_MAP then
        local src = p.ref0[slot]
        local sf = p.ref1[slot]
        local v = src:next()
        if v == nil then
            self:cancel()
            return nil
        end
        return sf(v)
    end

    error("iwatjit host cursor does not know cursor kind: " .. tostring(kind), 2)
end

local function make_host_cursor(rt, kind, init_index, extra)
    local cursor = { rt = rt, meta_slot = alloc_cursor_meta(rt, init_index or 0) }
    cursor_set_kind(cursor, kind)
    if extra ~= nil then
        local p = cursor_payload(cursor)
        local slot = cursor.meta_slot
        p.ref0[slot] = extra.ref0
        p.ref1[slot] = extra.ref1
        p.ref2[slot] = extra.ref2
        p.num0[slot] = extra.num0 or 0
        p.num1[slot] = extra.num1 or 0
        p.num2[slot] = extra.num2 or 0
        if extra.aux0 ~= nil then cursor_set_aux0(cursor, extra.aux0) end
        if extra.aux1 ~= nil then cursor_set_aux1(cursor, extra.aux1) end
    end
    return setmetatable(cursor, HostCursorMT)
end

local function open_recording_cursor(entry)
    entry_add_active_cursors(entry, 1)
    return make_host_cursor(entry.rt, CURSOR_RECORDING, 1, {
        ref0 = entry,
    })
end

local function open_cached_seq_cursor(plan)
    local rt = infer_runtime(plan)
    if plan.slab ~= nil then
        return make_host_cursor(rt, CURSOR_CACHED_SLAB, 0, {
            ref0 = plan.slab,
        })
    end
    return make_host_cursor(rt, CURSOR_CACHED_VALUES, 1, {
        ref0 = assert(plan.values, "cached_seq is missing slab and values storage"),
        aux0 = plan.count,
    })
end

local function open_range_cursor(plan)
    local start = host_value(plan.start)
    local stop = host_value(plan.stop)
    local step = host_value(plan.step or 1)
    assert(type(start) == "number" and type(stop) == "number" and type(step) == "number", "iwatjit host range requires numeric bounds")
    assert(step ~= 0, "iwatjit host range requires non-zero step")
    return make_host_cursor(infer_runtime(plan), CURSOR_RANGE, 0, {
        num0 = start,
        num1 = stop,
        num2 = step,
    })
end

local function open_once_cursor(plan)
    return make_host_cursor(infer_runtime(plan), CURSOR_ONCE, 0, {
        ref0 = host_value(plan.value),
    })
end

local function open_empty_cursor(plan)
    return make_host_cursor(infer_runtime(plan), CURSOR_EMPTY, 0, {})
end

local function open_map_cursor(plan)
    return make_host_cursor(infer_runtime(plan), CURSOR_MAP, 0, {
        ref0 = open_host_cursor(plan.src),
        ref1 = plan.f,
    })
end

local function open_filter_cursor(plan)
    return make_host_cursor(infer_runtime(plan), CURSOR_FILTER, 0, {
        ref0 = open_host_cursor(plan.src),
        ref1 = plan.pred,
    })
end

local function open_concat_cursor(plan)
    local cursor = make_host_cursor(infer_runtime(plan), CURSOR_CONCAT, 0, {
        ref0 = open_host_cursor(plan.left),
        ref1 = open_host_cursor(plan.right),
        aux0 = 1,
    })
    return cursor
end

local function open_take_cursor(plan)
    local remaining = host_value(plan.n)
    assert(type(remaining) == "number", "iwatjit host take requires numeric n")
    local cursor = make_host_cursor(infer_runtime(plan), CURSOR_TAKE, 0, {
        ref0 = open_host_cursor(plan.src),
        aux0 = remaining,
    })
    return cursor
end

local function open_drop_cursor(plan)
    local remaining = host_value(plan.n)
    assert(type(remaining) == "number", "iwatjit host drop requires numeric n")
    local cursor = make_host_cursor(infer_runtime(plan), CURSOR_DROP, 0, {
        ref0 = open_host_cursor(plan.src),
        aux0 = remaining,
    })
    return cursor
end

local function open_simd_map_cursor(plan)
    return make_host_cursor(infer_runtime(plan), CURSOR_SIMD_MAP, 0, {
        ref0 = open_host_cursor(plan.src),
        ref1 = plan.sf,
    })
end

function open_host_cursor(plan)
    plan = resolve_stream(plan)
    local kind = plan.kind
    if kind == "recording" then
        return open_recording_cursor(plan.entry)
    elseif kind == "cached_seq" then
        return open_cached_seq_cursor(plan)
    elseif kind == "once" then
        return open_once_cursor(plan)
    elseif kind == "empty" then
        return open_empty_cursor(plan)
    elseif kind == "range" then
        return open_range_cursor(plan)
    elseif kind == "map" then
        return open_map_cursor(plan)
    elseif kind == "filter" then
        return open_filter_cursor(plan)
    elseif kind == "concat" then
        return open_concat_cursor(plan)
    elseif kind == "take" then
        return open_take_cursor(plan)
    elseif kind == "drop" then
        return open_drop_cursor(plan)
    elseif kind == "simd_map" then
        return open_simd_map_cursor(plan)
    end
    error("iwatjit host cursor does not know stream kind: " .. tostring(kind), 2)
end

function needs_host_eval(plan)
    plan = resolve_stream(plan)
    local kind = plan.kind
    if kind == "recording" or kind == "cached_seq" then
        return true
    elseif kind == "map" or kind == "filter" or kind == "take" or kind == "drop" or kind == "simd_map" then
        return needs_host_eval(plan.src)
    elseif kind == "concat" then
        return needs_host_eval(plan.left) or needs_host_eval(plan.right)
    end
    return false
end

local function host_drain(plan)
    local cursor = open_host_cursor(plan)
    local out = {}
    while true do
        local v = cursor:next()
        if v == nil then
            break
        end
        out[#out + 1] = host_value(v)
    end
    cursor:cancel()
    return out
end

function host_count(plan)
    local cursor = open_host_cursor(plan)
    local n = 0
    while true do
        local v = cursor:next()
        if v == nil then
            break
        end
        n = n + 1
    end
    cursor:cancel()
    return n
end

local function host_sum(plan)
    local cursor = open_host_cursor(plan)
    local acc = 0
    while true do
        local v = cursor:next()
        if v == nil then
            break
        end
        acc = acc + host_value(v)
    end
    cursor:cancel()
    return acc
end

local function host_one(plan, default)
    local cursor = open_host_cursor(plan)
    local v = cursor:next()
    cursor:cancel()
    if v == nil then
        return default
    end
    return host_value(v)
end

local M = {}

function M.runtime(opts)
    opts = opts or {}
    local engine = wm.engine()
    local cursor_meta = native_cursor_meta_manager("iwj_cursor", opts.cursor_capacity or 262144, engine)
    return {
        engine = engine,
        terminals = weak_key_table(),
        serial = 0,
        phases = {},
        entry_meta = native_entry_meta_manager("iwj_entry", opts.entry_capacity or 262144, engine),
        cursor_meta = cursor_meta,
        cursor_payload = init_cursor_payload_store(cursor_meta.capacity),
        result = {
            by_type = {},
            used_bytes = 0,
            live_slots = 0,
            evictions = 0,
            capacity = opts.result_capacity,
            lru = native_lru_manager("iwj_result", opts.entry_capacity or 262144, engine),
        },
    }
end

function M.phase(rt, name, handlers, opts)
    assert(type(rt) == "table", "iwatjit.phase: rt must be a runtime")
    assert(type(name) == "string", "iwatjit.phase: name must be a string")
    assert(type(handlers) == "table" or type(handlers) == "function", "iwatjit.phase: handlers must be a table or function")
    opts = opts or {}
    assert(opts.bounded == nil or (type(opts.bounded) == "number" and opts.bounded >= 0), "iwatjit.phase: opts.bounded must be nil or a non-negative number")

    local cache = {
        weak = weak_key_table(),
        native = native_phase_index_manager("iwj_cache_" .. name, opts.entry_capacity or 262144, rt.engine),
    }
    local phase_cache = {
        bounded = opts.bounded,
        live = 0,
        used_bytes = 0,
        lru = opts.bounded and native_lru_manager("iwj_phase_" .. name, math.max(1, opts.bounded), rt.engine) or nil,
    }
    local stats = {
        name = name,
        calls = 0,
        hits = 0,
        shared = 0,
        misses = 0,
        seq_hits = 0,
        commits = 0,
        cancels = 0,
        evictions = 0,
        bounded = opts.bounded,
        live = 0,
        memory = 0,
    }
    rt.phases[#rt.phases + 1] = stats
    local phase

    local function build(node, ...)
        if type(handlers) == "function" then
            return handlers(node, ...)
        end
        local mt = getmetatable(node)
        local handler = handlers[mt] or handlers[node.kind] or handlers[node._tag]
        if handler == nil and pvm_classof ~= nil then
            handler = handlers[pvm_classof(node)]
        end
        assert(handler ~= nil, ("iwatjit.phase(%s): no handler for node"):format(name))
        return handler(node, ...)
    end

    local function recording_stream(entry)
        local stream = S.new_stream {
            kind = "recording",
            item_t = entry.item_t,
            count_hint = entry.plan.count_hint,
            entry = entry,
        }
        stream._iwj_rt = entry.rt
        stream._iwj_phase_name = entry.phase_name
        return stream
    end

    local call = function(node, ...)
        stats.calls = stats.calls + 1
        local entry = cache_lookup_entry(cache, node, ...)
        if entry ~= nil and entry_state(entry) ~= STATE_CANCELLED and entry_state(entry) ~= STATE_EVICTED then
            if entry_state(entry) == STATE_COMMITTED then
                stats.hits = stats.hits + 1
                stats.seq_hits = stats.seq_hits + 1
                touch_entry(entry)
                return entry.stream
            end
            stats.shared = stats.shared + 1
            return entry.stream
        end

        stats.misses = stats.misses + 1
        local plan = build(node, ...)
        assert(type(plan) == "table" and plan.kind ~= nil, "iwatjit phase handlers must return a watjit.stream plan")
        entry = {
            rt = rt,
            phase_name = name,
            stats = stats,
            plan = plan,
            item_t = plan.item_t,
            values = {},
            source_cursor = nil,
            cache = cache,
            cache_node = node,
            cache_args = { ... },
            phase_cache = phase_cache,
            meta_slot = alloc_entry_meta(rt),
        }
        entry._meta_gc = false
        entry.stream = recording_stream(entry)
        attach_runtime(plan, rt, name)
        cache_store_entry(cache, node, entry, ...)
        return entry.stream
    end

    phase = setmetatable({ stats = stats }, {
        __call = function(_, ...)
            return call(...)
        end,
    })
    return phase
end

function M.open(plan)
    local resolved = resolve_stream(plan)
    if not needs_host_eval(resolved) and resolved.kind ~= "cached_seq" then
        error("iwatjit.open currently supports recording/cached host streams only", 2)
    end
    local cursor = open_host_cursor(resolved)
    return setmetatable({ _cursor = cursor }, {
        __index = {
            next = function(self)
                return self._cursor:next()
            end,
            cancel = function(self)
                return self._cursor:cancel()
            end,
            drain = function(self)
                local out = {}
                while true do
                    local v = self._cursor:next()
                    if v == nil then
                        break
                    end
                    out[#out + 1] = host_value(v)
                end
                self._cursor:cancel()
                return out
            end,
        },
    })
end

function M.count(plan)
    local resolved = resolve_stream(plan)
    if plan_has_recording(resolved) then
        return host_count(resolved)
    end
    if plan_has_cached_seq(resolved) then
        touch_cached_seq_leaves(resolved)
        local rt = infer_runtime(resolved)
        local fn = compile_staged_count_kernel(rt, resolved)
        return fn()
    end
    local rt = infer_runtime(resolved)
    return known_count(rt, resolved)
end

function M.sum(plan, opts)
    opts = opts or {}
    local resolved = resolve_stream(plan)
    if plan_has_recording(resolved) then
        return host_sum(resolved)
    end
    if plan_has_cached_seq(resolved) then
        touch_cached_seq_leaves(resolved)
        local rt = infer_runtime(resolved)
        local fn = compile_staged_sum_kernel(rt, resolved, opts.vector_t)
        return fn()
    end
    local rt = infer_runtime(resolved)
    local fn = compile_sum_kernel(rt, resolved, opts.vector_t)
    return fn()
end

function M.one(plan, default)
    local resolved = resolve_stream(plan)
    if plan_has_recording(resolved) then
        return host_one(resolved, default or 0)
    end
    if plan_has_cached_seq(resolved) then
        touch_cached_seq_leaves(resolved)
        local rt = infer_runtime(resolved)
        local fn = compile_staged_one_kernel(rt, resolved, default or 0)
        return fn()
    end
    local rt = infer_runtime(resolved)
    local fn = compile_one_kernel(rt, resolved, default or 0)
    return fn()
end

function M.drain(plan)
    local resolved = resolve_stream(plan)
    if plan_has_recording(resolved) then
        return host_drain(resolved)
    end
    if plan_has_cached_seq(resolved) then
        touch_cached_seq_leaves(resolved)
        local rt = infer_runtime(resolved)
        local fn, inst, info = compile_staged_drain_kernel(rt, resolved)
        local written = fn()
        local base = select(1, inst:memory("memory")) + info.out_base
        local ptr = ffi.cast(scalar_ctype(resolved.item_t) .. "*", base)
        local out = {}
        for i = 0, written - 1 do
            out[#out + 1] = tonumber(ptr[i])
        end
        return out
    end
    local rt = infer_runtime(resolved)
    local fn, inst = compile_drain_kernel(rt, resolved)
    local written = fn(0)
    local ptr = ffi.cast(scalar_ctype(resolved.item_t) .. "*", select(1, inst:memory("memory")))
    local out = {}
    for i = 0, written - 1 do
        out[#out + 1] = tonumber(ptr[i])
    end
    return out
end

function M.host_count(plan)
    return host_count(resolve_stream(plan))
end

function M.host_sum(plan)
    return host_sum(resolve_stream(plan))
end

function M.host_one(plan, default)
    return host_one(resolve_stream(plan), default or 0)
end

function M.host_drain(plan)
    return host_drain(resolve_stream(plan))
end

function M.phase_stats(phase)
    local s = assert(phase and phase.stats, "iwatjit.phase_stats: expected a phase")
    local calls = s.calls or 0
    local reuse_ratio = calls > 0 and ((s.hits + s.shared) / calls) or 0
    return {
        name = s.name,
        calls = s.calls,
        hits = s.hits,
        shared = s.shared,
        misses = s.misses,
        seq_hits = s.seq_hits,
        commits = s.commits,
        cancels = s.cancels,
        evictions = s.evictions,
        live = s.live,
        bounded = s.bounded,
        memory = s.memory,
        reuse_ratio = reuse_ratio,
    }
end

function M.memory_stats(rt)
    local phases = {}
    for i = 1, #rt.phases do
        local s = rt.phases[i]
        phases[i] = {
            name = s.name,
            used = s.memory,
            live = s.live,
            bound = s.bounded,
            evictions = s.evictions,
        }
    end
    return {
        result = {
            used = rt.result.used_bytes,
            cap = rt.result.capacity,
            live_slots = rt.result.live_slots,
            evictions = rt.result.evictions,
        },
        phases = phases,
    }
end

function M.report_string(rt)
    local lines = {}
    for i = 1, #rt.phases do
        local s = rt.phases[i]
        local reuse = s.calls > 0 and ((s.hits + s.shared) / s.calls * 100.0) or 0.0
        lines[#lines + 1] = string.format(
            "%-12s calls=%-4d hits=%-4d shared=%-4d misses=%-4d seq_hits=%-4d commits=%-4d cancels=%-4d evict=%-4d live=%-4d mem=%-6d bound=%-4s reuse=%5.1f%%",
            s.name, s.calls, s.hits, s.shared, s.misses, s.seq_hits, s.commits, s.cancels, s.evictions, s.live or 0, s.memory or 0, tostring(s.bounded or "-"), reuse)
    end
    return table.concat(lines, "\n")
end

return M
