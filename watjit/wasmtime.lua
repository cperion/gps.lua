local ok, ffi = pcall(require, "ffi")
if not ok then
    error("watjit.wasmtime requires LuaJIT ffi", 2)
end

ffi.cdef[[
    typedef struct wasm_engine_t wasm_engine_t;
    typedef struct wasm_trap_t wasm_trap_t;
    typedef struct wasm_valtype_t wasm_valtype_t;
    typedef struct wasm_functype_t wasm_functype_t;
    typedef struct wasmtime_store wasmtime_store_t;
    typedef struct wasmtime_context wasmtime_context_t;
    typedef struct wasmtime_module wasmtime_module_t;
    typedef struct wasmtime_error wasmtime_error_t;

    typedef char byte_t;
    typedef byte_t wasm_byte_t;

    typedef struct wasm_byte_vec_t {
        size_t size;
        wasm_byte_t* data;
    } wasm_byte_vec_t;
    typedef wasm_byte_vec_t wasm_name_t;

    typedef uint8_t wasm_valkind_t;
    typedef struct wasm_valtype_vec_t {
        size_t size;
        wasm_valtype_t** data;
    } wasm_valtype_vec_t;

    typedef struct wasmtime_func {
        uint64_t store_id;
        void* __private;
    } wasmtime_func_t;

    typedef struct wasmtime_anyref {
        uint64_t store_id;
        uint32_t __private1;
        uint32_t __private2;
        void* __private3;
    } wasmtime_anyref_t;

    typedef struct wasmtime_externref {
        uint64_t store_id;
        uint32_t __private1;
        uint32_t __private2;
        void* __private3;
    } wasmtime_externref_t;

    typedef struct wasmtime_memory {
        struct {
            uint64_t store_id;
            uint32_t __private1;
        };
        uint32_t __private2;
    } wasmtime_memory_t;

    typedef struct wasmtime_global {
        uint64_t store_id;
        uint32_t __private1;
        uint32_t __private2;
        uint32_t __private3;
    } wasmtime_global_t;

    typedef struct wasmtime_table {
        struct {
            uint64_t store_id;
            uint32_t __private1;
        };
        uint32_t __private2;
    } wasmtime_table_t;

    typedef uint8_t wasmtime_extern_kind_t;
    typedef union wasmtime_extern_union_t {
        wasmtime_func_t func;
        wasmtime_global_t global;
        wasmtime_table_t table;
        wasmtime_memory_t memory;
        void* sharedmemory;
    } wasmtime_extern_union_t;
    typedef struct wasmtime_extern {
        wasmtime_extern_kind_t kind;
        wasmtime_extern_union_t of;
    } wasmtime_extern_t;

    typedef struct wasmtime_instance {
        uint64_t store_id;
        size_t __private;
    } wasmtime_instance_t;

    typedef uint8_t wasmtime_valkind_t;
    typedef union wasmtime_valunion {
        int32_t i32;
        int64_t i64;
        float f32;
        double f64;
        uint8_t v128[16];
        wasmtime_anyref_t anyref;
        wasmtime_externref_t externref;
        wasmtime_func_t funcref;
    } wasmtime_valunion_t;
    typedef struct wasmtime_val {
        wasmtime_valkind_t kind;
        wasmtime_valunion_t of;
    } wasmtime_val_t;

    typedef union wasmtime_val_raw {
        int32_t i32;
        int64_t i64;
        float f32;
        double f64;
        uint8_t v128[16];
        uint32_t anyref;
        uint32_t externref;
        void* funcref;
    } wasmtime_val_raw_t;

    wasm_engine_t* wasm_engine_new(void);
    void wasm_engine_delete(wasm_engine_t*);

    void wasm_byte_vec_delete(wasm_byte_vec_t*);
    void wasm_trap_delete(wasm_trap_t*);
    void wasm_trap_message(const wasm_trap_t*, wasm_name_t* out);

    void wasm_functype_delete(wasm_functype_t*);
    const wasm_valtype_vec_t* wasm_functype_params(const wasm_functype_t*);
    const wasm_valtype_vec_t* wasm_functype_results(const wasm_functype_t*);
    wasm_valkind_t wasm_valtype_kind(const wasm_valtype_t*);

    wasmtime_store_t* wasmtime_store_new(wasm_engine_t*, void*, void (*)(void*));
    void wasmtime_store_delete(wasmtime_store_t*);
    wasmtime_context_t* wasmtime_store_context(wasmtime_store_t*);

    wasmtime_error_t* wasmtime_wat2wasm(const char*, size_t, wasm_byte_vec_t*);
    wasmtime_error_t* wasmtime_module_new(wasm_engine_t*, const uint8_t*, size_t, wasmtime_module_t**);
    void wasmtime_module_delete(wasmtime_module_t*);

    void wasmtime_error_message(const wasmtime_error_t*, wasm_name_t*);
    void wasmtime_error_delete(wasmtime_error_t*);

    wasmtime_error_t* wasmtime_instance_new(
        wasmtime_context_t*,
        const wasmtime_module_t*,
        const wasmtime_extern_t*,
        size_t,
        wasmtime_instance_t*,
        wasm_trap_t**
    );
    bool wasmtime_instance_export_get(
        wasmtime_context_t*,
        const wasmtime_instance_t*,
        const char*,
        size_t,
        wasmtime_extern_t*
    );
    void wasmtime_extern_delete(wasmtime_extern_t*);

    wasm_functype_t* wasmtime_func_type(const wasmtime_context_t*, const wasmtime_func_t*);
    wasmtime_error_t* wasmtime_func_call(
        wasmtime_context_t*,
        const wasmtime_func_t*,
        const wasmtime_val_t*,
        size_t,
        wasmtime_val_t*,
        size_t,
        wasm_trap_t**
    );
    wasmtime_error_t* wasmtime_func_call_unchecked(
        wasmtime_context_t*,
        const wasmtime_func_t*,
        wasmtime_val_raw_t*,
        size_t,
        wasm_trap_t**
    );

    uint8_t* wasmtime_memory_data(const wasmtime_context_t*, const wasmtime_memory_t*);
    size_t wasmtime_memory_data_size(const wasmtime_context_t*, const wasmtime_memory_t*);
]]

local WASM_I32 = 0
local WASM_I64 = 1
local WASM_F32 = 2
local WASM_F64 = 3

local WASMTIME_EXTERN_FUNC = 0
local WASMTIME_EXTERN_MEMORY = 3

local WASMTIME_I32 = 0
local WASMTIME_I64 = 1
local WASMTIME_F32 = 2
local WASMTIME_F64 = 3

local function dirname(path)
    return (path:gsub("/+$", ""):match("^(.*)/[^/]+$") or ".")
end

local function module_dir()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then
        return dirname(source:sub(2))
    end
    return "."
end

local function join_path(...)
    local parts = { ... }
    return table.concat(parts, "/")
end

local function platform_candidates(root)
    return {
        join_path(root, "third_party", "wasmtime", "target", "release", "libwasmtime.so"),
        join_path(root, "third_party", "wasmtime", "target", "debug", "libwasmtime.so"),
        join_path(root, "third_party", "wasmtime", "target", "release", "libwasmtime.dylib"),
        join_path(root, "third_party", "wasmtime", "target", "debug", "libwasmtime.dylib"),
        join_path(root, "third_party", "wasmtime", "target", "release", "wasmtime.dll"),
        join_path(root, "third_party", "wasmtime", "target", "debug", "wasmtime.dll"),
    }
end

local function load_wasmtime()
    local root = dirname(module_dir())
    local candidates = {
        os.getenv("WATJIT_WASMTIME_LIB"),
    }

    local repo_candidates = platform_candidates(root)
    for i = 1, #repo_candidates do
        candidates[#candidates + 1] = repo_candidates[i]
    end

    candidates[#candidates + 1] = "wasmtime"
    candidates[#candidates + 1] = "libwasmtime.so"
    candidates[#candidates + 1] = "libwasmtime.dylib"
    candidates[#candidates + 1] = "wasmtime.dll"

    for i = 1, #candidates do
        local candidate = candidates[i]
        if candidate and candidate ~= "" then
            local ok_load, lib = pcall(ffi.load, candidate)
            if ok_load then
                return lib, candidate
            end
        end
    end

    error(
        "could not load Wasmtime shared library; build third_party/wasmtime (see watjit/build_wasmtime.sh) or set WATJIT_WASMTIME_LIB",
        2
    )
end

local wt, loaded_from = load_wasmtime()

local function vec_string(vec)
    local n = tonumber(vec.size)
    if n == 0 or vec.data == nil then
        return ""
    end
    local text = ffi.string(vec.data, n)
    if n > 0 and text:byte(-1) == 0 then
        text = text:sub(1, -2)
    end
    return text
end

local function delete_trap(trap)
    if trap ~= nil then
        wt.wasm_trap_delete(trap)
    end
end

local function trap_message(trap)
    local msg = ffi.new("wasm_name_t")
    wt.wasm_trap_message(trap, msg)
    local text = vec_string(msg)
    wt.wasm_byte_vec_delete(msg)
    return text
end

local function check(err)
    if err == nil then
        return
    end
    local msg = ffi.new("wasm_name_t")
    wt.wasmtime_error_message(err, msg)
    local text = vec_string(msg)
    wt.wasm_byte_vec_delete(msg)
    wt.wasmtime_error_delete(err)
    error("wasmtime: " .. text, 2)
end

local function check_trap(err, trap)
    if err ~= nil then
        check(err)
    end
    if trap ~= nil and trap[0] ~= nil then
        local text = trap_message(trap[0])
        delete_trap(trap[0])
        error("wasm trap: " .. text, 2)
    end
end

local function read_valkind(kind)
    kind = tonumber(kind)
    if kind == WASM_I32 then
        return "i32"
    elseif kind == WASM_I64 then
        return "i64"
    elseif kind == WASM_F32 then
        return "f32"
    elseif kind == WASM_F64 then
        return "f64"
    end
    error("unsupported wasm value kind: " .. tostring(kind), 3)
end

local function marshal_arg(slot, kind, value)
    if kind == "i32" then
        slot.kind = WASMTIME_I32
        slot.of.i32 = tonumber(value)
        return
    elseif kind == "i64" then
        slot.kind = WASMTIME_I64
        slot.of.i64 = tonumber(value)
        return
    elseif kind == "f32" then
        slot.kind = WASMTIME_F32
        slot.of.f32 = tonumber(value)
        return
    elseif kind == "f64" then
        slot.kind = WASMTIME_F64
        slot.of.f64 = tonumber(value)
        return
    end
    error("unsupported argument kind: " .. tostring(kind), 3)
end

local function marshal_raw_arg(slot, kind, value)
    if kind == "i32" then
        slot.i32 = tonumber(value)
        return
    elseif kind == "i64" then
        slot.i64 = tonumber(value)
        return
    elseif kind == "f32" then
        slot.f32 = tonumber(value)
        return
    elseif kind == "f64" then
        slot.f64 = tonumber(value)
        return
    end
    error("unsupported raw argument kind: " .. tostring(kind), 3)
end

local function unmarshal_result(slot, kind)
    if kind == "i32" then
        return tonumber(slot.of.i32)
    elseif kind == "i64" then
        return tonumber(slot.of.i64)
    elseif kind == "f32" then
        return tonumber(slot.of.f32)
    elseif kind == "f64" then
        return tonumber(slot.of.f64)
    end
    error("unsupported result kind: " .. tostring(kind), 3)
end

local function unmarshal_raw_result(slot, kind)
    if kind == "i32" then
        return tonumber(slot.i32)
    elseif kind == "i64" then
        return tonumber(slot.i64)
    elseif kind == "f32" then
        return tonumber(slot.f32)
    elseif kind == "f64" then
        return tonumber(slot.f64)
    end
    error("unsupported raw result kind: " .. tostring(kind), 3)
end

local function all_numeric(sig)
    for i = 1, #sig.params do
        local k = sig.params[i]
        if k ~= "i32" and k ~= "i64" and k ~= "f32" and k ~= "f64" then
            return false
        end
    end
    for i = 1, #sig.results do
        local k = sig.results[i]
        if k ~= "i32" and k ~= "i64" and k ~= "f32" and k ~= "f64" then
            return false
        end
    end
    return true
end

local function func_signature(context, func)
    local ft = wt.wasmtime_func_type(context, func)
    if ft == nil then
        error("wasmtime: could not query function type", 2)
    end

    local params_vec = wt.wasm_functype_params(ft)
    local results_vec = wt.wasm_functype_results(ft)

    local params = {}
    for i = 0, tonumber(params_vec.size) - 1 do
        params[#params + 1] = read_valkind(wt.wasm_valtype_kind(params_vec.data[i]))
    end

    local results = {}
    for i = 0, tonumber(results_vec.size) - 1 do
        results[#results + 1] = read_valkind(wt.wasm_valtype_kind(results_vec.data[i]))
    end

    wt.wasm_functype_delete(ft)
    return {
        params = params,
        results = results,
    }
end

local function get_export(context, instance, name)
    local item = ffi.new("wasmtime_extern_t")
    local ok_export = wt.wasmtime_instance_export_get(context, instance, name, #name, item)
    if not ok_export then
        error("no export named '" .. name .. "'", 2)
    end
    return item
end

local function resolve_import_extern(import_spec, imports)
    if imports == nil then
        error(("missing imports table for %s.%s"):format(import_spec.import_module, import_spec.import_name), 3)
    end

    local direct = imports[import_spec.name]
    if direct ~= nil then
        return direct
    end

    local mod_tbl = imports[import_spec.import_module]
    if type(mod_tbl) == "table" then
        local by_name = mod_tbl[import_spec.import_name]
        if by_name ~= nil then
            return by_name
        end
        local by_alias = mod_tbl[import_spec.name]
        if by_alias ~= nil then
            return by_alias
        end
    end

    error(("missing import binding for %s.%s as $%s"):format(import_spec.import_module, import_spec.import_name, import_spec.name), 3)
end

local function copy_extern(x)
    if type(x) == "cdata" and ffi.istype("wasmtime_extern_t", x) then
        return ffi.new("wasmtime_extern_t", x)
    end
    if type(x) == "table" and x.kind ~= nil and x.of ~= nil then
        return ffi.new("wasmtime_extern_t", x)
    end
    return nil
end

local function import_array(import_specs, imports)
    if import_specs == nil or #import_specs == 0 then
        return nil, 0
    end
    local arr = ffi.new("wasmtime_extern_t[?]", #import_specs)
    local owner_instance = nil
    for i = 1, #import_specs do
        local binding = resolve_import_extern(import_specs[i], imports)
        if type(binding) == "table" and binding.instance ~= nil then
            owner_instance = owner_instance or binding.instance
            binding = binding.extern
        end
        local ext = copy_extern(binding)
        if ext == nil then
            error(("import %s.%s must be a wasmtime extern from instance:extern(name)"):format(import_specs[i].import_module, import_specs[i].import_name), 2)
        end
        arr[i - 1] = ext
    end
    return arr, #import_specs, owner_instance
end

local M = {
    _loaded_from = loaded_from,
}

function M.engine()
    local engine = wt.wasm_engine_new()
    ffi.gc(engine, wt.wasm_engine_delete)
    return engine
end

function M.compile(engine, wat_text)
    local wasm = ffi.new("wasm_byte_vec_t")
    check(wt.wasmtime_wat2wasm(wat_text, #wat_text, wasm))

    local module_ptr = ffi.new("wasmtime_module_t*[1]")
    check(wt.wasmtime_module_new(engine, ffi.cast("const uint8_t*", wasm.data), wasm.size, module_ptr))
    wt.wasm_byte_vec_delete(wasm)

    ffi.gc(module_ptr[0], wt.wasmtime_module_delete)
    return module_ptr[0]
end

function M.instantiate(engine, module, import_specs, imports)
    local externs, extern_count, owner_instance = import_array(import_specs, imports)
    local store, context
    local owns_store = false
    if owner_instance ~= nil then
        store = owner_instance.store
        context = owner_instance.context
    else
        store = wt.wasmtime_store_new(engine, nil, nil)
        ffi.gc(store, wt.wasmtime_store_delete)
        context = wt.wasmtime_store_context(store)
        owns_store = true
    end

    local instance = ffi.new("wasmtime_instance_t")
    local trap = ffi.new("wasm_trap_t*[1]", nil)
    local err = wt.wasmtime_instance_new(context, module, externs, extern_count, instance, trap)
    check_trap(err, trap)

    return {
        store = store,
        context = context,
        instance = instance,
        owns_store = owns_store,

        extern = function(self, name)
            return {
                extern = get_export(self.context, self.instance, name),
                instance = self,
            }
        end,

        fn = function(self, name)
            local item = get_export(self.context, self.instance, name)
            if tonumber(item.kind) ~= WASMTIME_EXTERN_FUNC then
                wt.wasmtime_extern_delete(item)
                error("export '" .. name .. "' is not a function", 2)
            end

            local func = ffi.new("wasmtime_func_t", item.of.func)
            local sig = func_signature(self.context, func)
            local use_raw = all_numeric(sig)
            wt.wasmtime_extern_delete(item)

            if use_raw then
                local raw_len = math.max(#sig.params, #sig.results)
                return function(...)
                    local argc = select("#", ...)
                    if argc ~= #sig.params then
                        error(
                            string.format(
                                "function '%s' expects %d arguments, got %d",
                                name,
                                #sig.params,
                                argc
                            ),
                            2
                        )
                    end

                    local raw = raw_len > 0 and ffi.new("wasmtime_val_raw_t[?]", raw_len) or nil
                    for i = 1, #sig.params do
                        marshal_raw_arg(raw[i - 1], sig.params[i], select(i, ...))
                    end

                    local trap2 = ffi.new("wasm_trap_t*[1]", nil)
                    local err2 = wt.wasmtime_func_call_unchecked(
                        self.context,
                        func,
                        raw,
                        raw_len,
                        trap2
                    )
                    check_trap(err2, trap2)

                    if #sig.results == 0 then
                        return nil
                    end
                    if #sig.results == 1 then
                        return unmarshal_raw_result(raw[0], sig.results[1])
                    end

                    local out = {}
                    for i = 1, #sig.results do
                        out[i] = unmarshal_raw_result(raw[i - 1], sig.results[i])
                    end
                    return table.unpack(out, 1, #out)
                end
            end

            return function(...)
                local argc = select("#", ...)
                if argc ~= #sig.params then
                    error(
                        string.format(
                            "function '%s' expects %d arguments, got %d",
                            name,
                            #sig.params,
                            argc
                        ),
                        2
                    )
                end

                local args = #sig.params > 0 and ffi.new("wasmtime_val_t[?]", #sig.params) or nil
                for i = 1, #sig.params do
                    marshal_arg(args[i - 1], sig.params[i], select(i, ...))
                end

                local results = #sig.results > 0 and ffi.new("wasmtime_val_t[?]", #sig.results) or nil
                local trap2 = ffi.new("wasm_trap_t*[1]", nil)
                local err2 = wt.wasmtime_func_call(
                    self.context,
                    func,
                    args,
                    #sig.params,
                    results,
                    #sig.results,
                    trap2
                )
                check_trap(err2, trap2)

                if #sig.results == 0 then
                    return nil
                end
                if #sig.results == 1 then
                    return unmarshal_result(results[0], sig.results[1])
                end

                local out = {}
                for i = 1, #sig.results do
                    out[i] = unmarshal_result(results[i - 1], sig.results[i])
                end
                return table.unpack(out, 1, #out)
            end
        end,

        memory = function(self, name, ctype)
            local item = get_export(self.context, self.instance, name)
            if tonumber(item.kind) ~= WASMTIME_EXTERN_MEMORY then
                wt.wasmtime_extern_delete(item)
                error("export '" .. name .. "' is not a memory", 2)
            end

            local memory = ffi.new("wasmtime_memory_t", item.of.memory)
            local base = wt.wasmtime_memory_data(self.context, memory)
            local size = tonumber(wt.wasmtime_memory_data_size(self.context, memory))
            wt.wasmtime_extern_delete(item)

            if ctype == nil then
                return base, size
            end

            return ffi.cast(ffi.typeof(ctype .. "*"), base), size
        end,
    }
end

return M
