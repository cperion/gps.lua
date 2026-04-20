local backend = assert(rawget(_G, "__moonlift_backend"), "moonlift backend not installed")

local M
local ExprMT = {}
local TypeMT = {}
local PtrTypeMT = {}
local StructViewMT
local ArrayViewMT
local StructScalarVarMT = {}
local FunctionMT = {}
local ExternMT = {}
local ModuleMT = {}
local ImportModuleMT = {}
local ImportExternStage1MT = {}
local CompiledFnMT = {}
local FuncStage1MT = {}
local ExternStage1MT = {}
local LetMT = {}
local VarMT = {}
local QuoteMT = {}
local IRQuoteMT = QuoteMT

local compiled_cache = setmetatable({}, { __mode = "v" })
local body_env_cache = setmetatable({}, { __mode = "k" })
local _ffi_cache = false
local _packed_fn_type_cache = {}

local current_builder = nil
local param
local if_
local cast
local trunc
local zext
local sext
local bitcast
local switch_
local break_
local continue_
local invoke
local extern
local import_module
local emit_stmt
local compile_function
local load
local store
local copy
local store_aggregate
local memcpy
local memmove
local memset
local memcmp
local make_ptr
local type_size
local type_align
local is_struct_type
local is_array_type
local is_layout_type
local layout_type_of_value
local layout_ptr_of_value
local alloc_stack_slot
local bind_layout_local
local bind_let
local bind_var
local is_agg_init
local is_layout_view
local materialize_struct_scalar_proxy
local can_scalarize_struct_init
local quote
local quote_ir
local quote_expr
local quote_block
local hole
local q
local make_field_load
local make_field_store
local make_array_elem_load
local make_array_elem_store

local unpack = table.unpack or unpack

local function pack(...)
    return { n = select("#", ...), ... }
end

local function unpack_from(t, i)
    return unpack(t, i or 1, t.n)
end

local function is_expr(x)
    return type(x) == "table" and getmetatable(x) == ExprMT
end

local function is_ir_quote(x)
    return type(x) == "table" and getmetatable(x) == IRQuoteMT
end

local function is_plain_table(x)
    return type(x) == "table" and getmetatable(x) == nil
end

local function lower_type_name(t)
    return (t and t.lowering_name) or (t and t.name)
end

local function is_type(x)
    if type(x) ~= "table" then
        return false
    end
    local mt = getmetatable(x)
    return mt == TypeMT or mt == PtrTypeMT
end

local function is_function(x)
    return type(x) == "table" and getmetatable(x) == FunctionMT
end

local function stable_serialize_atom(x)
    local tx = type(x)
    if tx == "string" then
        return "s:" .. string.format("%q", x)
    elseif tx == "number" then
        return "n:" .. string.format("%.17g", x)
    elseif tx == "boolean" then
        return x and "b:1" or "b:0"
    elseif x == nil then
        return "nil"
    end
    error("moonlift stable serialization does not support values of type " .. tx, 2)
end

local function stable_serialize_value(x, out, seen)
    local tx = type(x)
    if tx ~= "table" then
        out[#out + 1] = stable_serialize_atom(x)
        return
    end
    if is_expr(x) then
        stable_serialize_value(x.node, out, seen)
        return
    end
    if seen[x] then
        error("moonlift stable serialization does not support cyclic tables", 2)
    end
    seen[x] = true
    out[#out + 1] = "{"
    local keys = {}
    for k, _ in pairs(x) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return stable_serialize_atom(a) < stable_serialize_atom(b)
    end)
    for i = 1, #keys do
        local k = keys[i]
        out[#out + 1] = stable_serialize_atom(k)
        out[#out + 1] = "="
        stable_serialize_value(x[k], out, seen)
        out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
    seen[x] = nil
end

local function stable_value_key(x)
    local out = {}
    stable_serialize_value(x, out, {})
    return table.concat(out)
end

local function ordered_named_entries(t, label)
    assert(type(t) == "table", ("moonlift %s must be a table"):format(label))
    local out = {}
    local seen = {}
    local array_n = #t

    for i = 1, array_n do
        local entry = assert(t[i], ("moonlift %s entry %d is missing"):format(label, i))
        assert(type(entry) == "table", ("moonlift %s array entries must be tables"):format(label))
        local name = assert(entry[1], ("moonlift %s entry %d is missing a name"):format(label, i))
        assert(type(name) == "string", ("moonlift %s entry %d name must be a string"):format(label, i))
        assert(not seen[name], ("duplicate moonlift %s entry: %s"):format(label, name))
        out[#out + 1] = { name, entry[2] }
        seen[name] = true
    end

    local names = {}
    for k, _ in pairs(t) do
        local is_array_key = type(k) == "number" and k >= 1 and k <= array_n and k == math.floor(k)
        if not is_array_key then
            assert(type(k) == "string", ("moonlift %s keys must be strings"):format(label))
            assert(not seen[k], ("duplicate moonlift %s entry: %s"):format(label, k))
            names[#names + 1] = k
        end
    end
    table.sort(names)
    for i = 1, #names do
        local name = names[i]
        out[#out + 1] = { name, t[name] }
    end

    return out
end

local function current_frame()
    local builder = current_builder
    if builder == nil or builder.frame == nil then
        return nil
    end
    return builder.frame
end

local expr_methods = {}

local function expr(node, t, methods)
    if node == nil then
        error(debug.traceback("moonlift internal error: expr node is nil"), 2)
    end
    if node.type == nil then
        node.type = lower_type_name(t)
    end
    return setmetatable({ node = node, t = t, __methods = methods }, ExprMT)
end

local function is_numeric_type(t)
    return is_type(t) and (t.family == "int" or t.family == "float" or t.family == "enum")
end

local function is_integer_type(t)
    return is_type(t) and (t.family == "int" or t.family == "ptr" or t.family == "enum")
end

local function is_float_type(t)
    return is_type(t) and t.family == "float"
end

local function is_void_type(t)
    return is_type(t) and t.family == "void"
end

local function is_bool_type(t)
    return is_type(t) and t.family == "bool"
end

local function as_expr(x, want_t)
    if is_expr(x) then
        if want_t ~= nil and x.t ~= want_t then
            error(("moonlift type mismatch: expected %s, got %s"):format(want_t.name, x.t.name), 3)
        end
        return x
    end
    if is_ir_quote(x) then
        if x._param_count ~= 0 then
            error("moonlift quote with params must be explicitly spliced/called with arguments", 3)
        end
        local out = x:splice()
        if want_t ~= nil and out.t ~= want_t then
            error(("moonlift type mismatch: expected %s, got %s"):format(want_t.name, out.t.name), 3)
        end
        return out
    end
    if type(x) == "number" then
        local t = want_t or M.i32
        assert(not is_bool_type(t), "cannot coerce Lua number to Moonlift bool without an explicit boolean")
        return t(x)
    end
    if type(x) == "boolean" then
        local t = want_t or M.bool
        assert(is_bool_type(t), "cannot coerce Lua boolean to non-bool Moonlift type")
        return t(x)
    end
    error("cannot convert value to moonlift expression: " .. type(x), 3)
end

local function wrap_frame_block(frame, result_expr)
    if #frame.stmts == 0 then
        return result_expr
    end
    return expr({
        tag = "block",
        stmts = frame.stmts,
        result = result_expr.node,
    }, result_expr.t)
end

local function body_env(base_env)
    local cached = body_env_cache[base_env]
    if cached ~= nil then
        return cached
    end
    local env = setmetatable({}, {
        __index = function(_, k)
            if M ~= nil then
                if M[k] ~= nil then
                    return M[k]
                end
                if M.types ~= nil and M.types[k] ~= nil then
                    return M.types[k]
                end
            end
            return base_env[k]
        end,
        __newindex = base_env,
    })
    body_env_cache[base_env] = env
    return env
end

local function get_ffi()
    if _ffi_cache == false then
        local ok, mod = pcall(require, "ffi")
        _ffi_cache = ok and mod or nil
    end
    return _ffi_cache
end

local function symbol_address(x)
    if type(x) == "number" then
        return x
    end
    local ffi = get_ffi()
    if ffi == nil then
        error("moonlift import symbol resolution requires LuaJIT ffi when symbol is not already numeric", 3)
    end
    return tonumber(ffi.cast("intptr_t", x))
end

local function packed_fn_type(arity)
    local cached = _packed_fn_type_cache[arity]
    if cached ~= nil then return cached end
    local ffi = get_ffi()
    if ffi == nil then return nil end
    local sig
    if arity == 0 then
        sig = "uint64_t (*)(void)"
    elseif arity == 1 then
        sig = "uint64_t (*)(uint64_t)"
    elseif arity == 2 then
        sig = "uint64_t (*)(uint64_t, uint64_t)"
    elseif arity == 3 then
        sig = "uint64_t (*)(uint64_t, uint64_t, uint64_t)"
    elseif arity == 4 then
        sig = "uint64_t (*)(uint64_t, uint64_t, uint64_t, uint64_t)"
    else
        return nil
    end
    local ty = ffi.typeof(sig)
    _packed_fn_type_cache[arity] = ty
    return ty
end

local function pack_host_arg(value, ty_name)
    local ffi = get_ffi()
    if ty_name == "bool" then
        return value and 1 or 0
    elseif ty_name == "i8" then
        return ffi.cast("uint64_t", ffi.cast("int8_t", value))
    elseif ty_name == "i16" then
        return ffi.cast("uint64_t", ffi.cast("int16_t", value))
    elseif ty_name == "i32" then
        return ffi.cast("uint64_t", ffi.cast("int32_t", value))
    elseif ty_name == "i64" then
        return ffi.cast("uint64_t", ffi.cast("int64_t", value))
    elseif ty_name == "u8" or ty_name == "byte" then
        return ffi.cast("uint64_t", ffi.cast("uint8_t", value))
    elseif ty_name == "u16" then
        return ffi.cast("uint64_t", ffi.cast("uint16_t", value))
    elseif ty_name == "u32" then
        return ffi.cast("uint64_t", ffi.cast("uint32_t", value))
    elseif ty_name == "u64" or ty_name == "usize" or ty_name == "ptr" then
        return ffi.cast("uint64_t", value)
    elseif ty_name == "f32" then
        local u = ffi.new("union { float f; uint32_t u; }")
        u.f = value
        return ffi.cast("uint64_t", u.u)
    elseif ty_name == "f64" then
        local u = ffi.new("union { double d; uint64_t u; }")
        u.d = value
        return u.u
    end
    return nil
end

local function unpack_host_result(bits, result_t)
    local ffi = get_ffi()
    local ty_name = lower_type_name(result_t)
    if ty_name == nil or ty_name == "void" then
        return nil
    elseif ty_name == "bool" then
        return ffi.cast("uint64_t", bits) ~= 0
    elseif ty_name == "i8" then
        return tonumber(ffi.cast("int8_t", bits))
    elseif ty_name == "i16" then
        return tonumber(ffi.cast("int16_t", bits))
    elseif ty_name == "i32" then
        return tonumber(ffi.cast("int32_t", bits))
    elseif ty_name == "i64" then
        return tonumber(ffi.cast("int64_t", bits))
    elseif ty_name == "u8" or ty_name == "byte" then
        return tonumber(ffi.cast("uint8_t", bits))
    elseif ty_name == "u16" then
        return tonumber(ffi.cast("uint16_t", bits))
    elseif ty_name == "u32" then
        return tonumber(ffi.cast("uint32_t", bits))
    elseif ty_name == "u64" or ty_name == "usize" or ty_name == "ptr" then
        return tonumber(ffi.cast("uint64_t", bits))
    elseif ty_name == "f32" then
        local u = ffi.new("union { float f; uint32_t u; }")
        u.u = ffi.cast("uint32_t", bits)
        return tonumber(u.f)
    elseif ty_name == "f64" then
        local u = ffi.new("union { double d; uint64_t u; }")
        u.u = ffi.cast("uint64_t", bits)
        return tonumber(u.d)
    end
    return nil
end

local function make_fast_host_call(addr, arity, param_types, result_t)
    local ffi = get_ffi()
    if ffi == nil or addr == nil or param_types == nil or result_t == nil then
        return nil
    end
    local fn_ty = packed_fn_type(arity)
    if fn_ty == nil then return nil end
    local fp = ffi.cast(fn_ty, addr)
    if arity == 0 then
        return function()
            return unpack_host_result(fp(), result_t)
        end
    elseif arity == 1 then
        return function(a)
            return unpack_host_result(fp(pack_host_arg(a, param_types[1])), result_t)
        end
    elseif arity == 2 then
        return function(a, b)
            return unpack_host_result(fp(pack_host_arg(a, param_types[1]), pack_host_arg(b, param_types[2])), result_t)
        end
    elseif arity == 3 then
        return function(a, b, c)
            return unpack_host_result(fp(pack_host_arg(a, param_types[1]), pack_host_arg(b, param_types[2]), pack_host_arg(c, param_types[3])), result_t)
        end
    elseif arity == 4 then
        return function(a, b, c, d)
            return unpack_host_result(fp(pack_host_arg(a, param_types[1]), pack_host_arg(b, param_types[2]), pack_host_arg(c, param_types[3]), pack_host_arg(d, param_types[4])), result_t)
        end
    end
    return nil
end

local function run_builder_fn(f, ...)
    if type(getfenv) == "function" and type(setfenv) == "function" then
        local old_env = getfenv(f)
        local new_env = body_env(old_env)
        local applied = false
        if old_env ~= new_env then
            setfenv(f, new_env)
            applied = true
        end
        local out = pack(pcall(f, ...))
        if applied then
            setfenv(f, old_env)
        end
        if not out[1] then
            error(out[2], 0)
        end
        return unpack_from(out, 2)
    end
    return f(...)
end

local function with_builder(builder, f)
    local prev = current_builder
    current_builder = builder
    local out = pack(pcall(f))
    current_builder = prev
    if not out[1] then
        error(out[2], 0)
    end
    return unpack_from(out, 2)
end

local function with_frame_result(f)
    local builder = current_builder
    if builder == nil then
        error("moonlift block context is not active", 2)
    end
    local prev = builder.frame
    local frame = { stmts = {}, parent = prev }
    builder.frame = frame
    local out = pack(pcall(run_builder_fn, f))
    builder.frame = prev
    if not out[1] then
        error(out[2], 0)
    end
    return wrap_frame_block(frame, as_expr(out[2]))
end

local function capture_stmt_block(f)
    local builder = current_builder
    if builder == nil then
        error("moonlift statement context is not active", 2)
    end
    local prev = builder.frame
    local frame = { stmts = {}, parent = prev }
    builder.frame = frame
    local out = pack(pcall(run_builder_fn, f))
    builder.frame = prev
    if not out[1] then
        error(out[2], 0)
    end
    if out.n >= 2 and out[2] ~= nil then
        error("moonlift while_ body must not return a value", 2)
    end
    return frame.stmts
end

local function is_zero_const_expr(x)
    if not is_expr(x) then return false end
    local node = x.node
    if type(node) ~= "table" then return false end
    local tag = node.tag
    if tag == "bool" then
        return node.value == false
    elseif tag == "i8" or tag == "i16" or tag == "i32" or tag == "i64"
        or tag == "u8" or tag == "u16" or tag == "u32" or tag == "u64"
        or tag == "ptr" or tag == "f32" or tag == "f64" then
        return node.value == 0
    end
    return false
end

local function common_type(a, b)
    if is_expr(a) and is_expr(b) then
        assert(a.t == b.t, ("moonlift operand type mismatch: %s vs %s"):format(a.t.name, b.t.name))
        return a.t
    elseif is_expr(a) then
        return a.t
    elseif is_expr(b) then
        return b.t
    end
    return M.i32
end

local function binary(tag, a, b)
    local t = common_type(a, b)
    a = as_expr(a, t)
    b = as_expr(b, t)
    if tag == "rem" then
        assert(is_integer_type(t), "moonlift remainder expects integer operands")
    elseif t.family == "ptr" then
        assert(tag == "add" or tag == "sub", ("moonlift %s is not valid for pointer operands"):format(tag))
    else
        assert(is_numeric_type(t), ("moonlift %s expects numeric operands"):format(tag))
    end
    return expr({ tag = tag, lhs = a.node, rhs = b.node, type = lower_type_name(t) }, t)
end

local function integer_binary(tag, a, b)
    local t = common_type(a, b)
    a = as_expr(a, t)
    b = as_expr(b, t)
    assert(is_integer_type(t), ("moonlift %s expects integer or pointer operands"):format(tag))
    return expr({ tag = tag, lhs = a.node, rhs = b.node, type = lower_type_name(t) }, t)
end

local function cast_like(tag, to_t, value)
    assert(is_type(to_t), ("moonlift %s target must be a Moonlift type"):format(tag))
    value = as_expr(value)
    return expr({ tag = tag, value = value.node, type = lower_type_name(to_t) }, to_t)
end

local function compare(tag, a, b)
    local t = common_type(a, b)
    a = as_expr(a, t)
    b = as_expr(b, t)
    if tag == "eq" or tag == "ne" then
        assert(is_numeric_type(t) or is_bool_type(t) or t.family == "ptr", ("moonlift %s expects scalar operands"):format(tag))
    else
        assert(is_numeric_type(t) or t.family == "ptr", ("moonlift %s expects numeric operands"):format(tag))
    end
    return expr({ tag = tag, lhs = a.node, rhs = b.node }, M.bool)
end

local function bool_unary(tag, x)
    x = as_expr(x, M.bool)
    return expr({ tag = tag, value = x.node }, M.bool)
end

local function bool_binary(tag, a, b)
    a = as_expr(a, M.bool)
    b = as_expr(b, M.bool)
    return expr({ tag = tag, lhs = a.node, rhs = b.node }, M.bool)
end

ExprMT.__tostring = function(self)
    return string.format("moonlift.expr<%s:%s>", self.t and self.t.name or "?", self.node.tag or "?")
end

ExprMT.__add = function(a, b)
    return binary("add", a, b)
end

ExprMT.__sub = function(a, b)
    return binary("sub", a, b)
end

ExprMT.__mul = function(a, b)
    return binary("mul", a, b)
end

ExprMT.__div = function(a, b)
    return binary("div", a, b)
end

ExprMT.__mod = function(a, b)
    return binary("rem", a, b)
end

ExprMT.__unm = function(a)
    a = as_expr(a)
    assert(is_numeric_type(a.t), "moonlift unary minus expects numeric operand")
    return expr({ tag = "neg", value = a.node }, a.t)
end

ExprMT.__call = function(self, then_value, else_value)
    if is_bool_type(self.t) then
        return if_(self, then_value, else_value)
    end
    error("only Moonlift bool expressions are callable as conditional selectors", 2)
end

ExprMT.__index = function(self, key)
    local methods = rawget(self, "__methods")
    if methods ~= nil and methods[key] ~= nil then
        return methods[key]
    end
    return expr_methods[key]
end

expr_methods.eq = function(self, rhs)
    return compare("eq", self, rhs)
end
expr_methods.ne = function(self, rhs)
    return compare("ne", self, rhs)
end
expr_methods.lt = function(self, rhs)
    return compare("lt", self, rhs)
end
expr_methods.le = function(self, rhs)
    return compare("le", self, rhs)
end
expr_methods.gt = function(self, rhs)
    return compare("gt", self, rhs)
end
expr_methods.ge = function(self, rhs)
    return compare("ge", self, rhs)
end
expr_methods.not_ = function(self)
    return bool_unary("not", self)
end
expr_methods.and_ = function(self, rhs)
    return bool_binary("and", self, rhs)
end
expr_methods.or_ = function(self, rhs)
    return bool_binary("or", self, rhs)
end
expr_methods.band = function(self, rhs)
    return integer_binary("band", self, rhs)
end
expr_methods.bor = function(self, rhs)
    return integer_binary("bor", self, rhs)
end
expr_methods.bxor = function(self, rhs)
    return integer_binary("bxor", self, rhs)
end
expr_methods.bnot = function(self)
    self = as_expr(self)
    assert(is_integer_type(self.t), "moonlift bnot expects integer or pointer operand")
    return expr({ tag = "bnot", value = self.node, type = lower_type_name(self.t) }, self.t)
end
expr_methods.shl = function(self, rhs)
    return integer_binary("shl", self, rhs)
end
expr_methods.shr_u = function(self, rhs)
    return integer_binary("shr_u", self, rhs)
end
expr_methods.shr_s = function(self, rhs)
    return integer_binary("shr_s", self, rhs)
end
expr_methods.cast = function(self, to_t)
    return cast(to_t, self)
end
expr_methods.trunc = function(self, to_t)
    return trunc(to_t, self)
end
expr_methods.zext = function(self, to_t)
    return zext(to_t, self)
end
expr_methods.sext = function(self, to_t)
    return sext(to_t, self)
end
expr_methods.bitcast = function(self, to_t)
    return bitcast(to_t, self)
end
expr_methods.select = function(self, then_value, else_value)
    return if_(self, then_value, else_value)
end
expr_methods.set = function()
    error("moonlift.set is only valid on mutable variables", 2)
end

local function new_type(spec)
    return setmetatable(spec, TypeMT)
end

TypeMT.__tostring = function(self)
    return string.format("moonlift.type<%s>", self.name)
end

TypeMT.__call = function(self, value)
    if is_void_type(self) then
        error("void may only be used as a function result type", 2)
    end
    if type(value) == "string" then
        return param(value, self)
    end
    if type(value) == "number" then
        return expr({ tag = self.const_tag, value = value }, self)
    end
    if type(value) == "boolean" and is_bool_type(self) then
        return expr({ tag = self.const_tag, value = value }, self)
    end
    error(("%s(...) expects a constant literal or parameter name"):format(self.name), 2)
end

cast = function(to_t, value)
    return cast_like("cast", to_t, value)
end

trunc = function(to_t, value)
    return cast_like("trunc", to_t, value)
end

zext = function(to_t, value)
    return cast_like("zext", to_t, value)
end

sext = function(to_t, value)
    return cast_like("sext", to_t, value)
end

bitcast = function(to_t, value)
    return cast_like("bitcast", to_t, value)
end

param = function(name, t)
    assert(type(name) == "string", "moonlift.param name must be a string")
    local is_layout = type(t) == "table" and (t.layout_kind == "struct" or t.layout_kind == "array")
    assert(is_type(t) or is_layout, "moonlift.param requires a Moonlift type")
    return { name = name, t = t }
end

local function arg(index, t)
    assert(type(index) == "number", "moonlift.arg index must be a number")
    assert(is_type(t), "moonlift.arg requires a Moonlift type")
    return expr({ tag = "arg", index = index }, t)
end

local function lower_param(p)
    if is_layout_type ~= nil and is_layout_type(p.t) then
        return "ptr"
    end
    return lower_type_name(p.t)
end

local function block(body)
    assert(type(body) == "function", "moonlift.block expects a function")
    return with_frame_result(body)
end

if_ = function(cond, then_value, else_value)
    cond = as_expr(cond, M.bool)
    local then_is_fn = type(then_value) == "function"
    local else_is_fn = type(else_value) == "function"
    if then_is_fn then
        then_value = block(then_value)
    end
    if else_is_fn then
        else_value = block(else_value)
    end
    then_value = as_expr(then_value)
    else_value = as_expr(else_value)
    assert(then_value.t == else_value.t, "moonlift.if_ branches must have the same type")
    if not then_is_fn and not else_is_fn and not is_void_type(then_value.t) then
        if is_integer_type(then_value.t) and is_zero_const_expr(else_value) then
            local mask = -zext(then_value.t, cond)
            return then_value:band(mask)
        elseif is_integer_type(then_value.t) and is_zero_const_expr(then_value) then
            local mask = -zext(else_value.t, cond:not_())
            return else_value:band(mask)
        end
        return expr({
            tag = "select",
            cond = cond.node,
            then_ = then_value.node,
            else_ = else_value.node,
        }, then_value.t)
    end
    return expr({
        tag = "if",
        cond = cond.node,
        then_ = then_value.node,
        else_ = else_value.node,
    }, then_value.t)
end

local _next_quote_capture_id = 0

local function fresh_local_name(prefix)
    local builder = current_builder
    local frame = current_frame()
    if builder == nil or frame == nil then
        error("moonlift local binding may only be used inside moonlift.fn bodies or moonlift.block", 2)
    end
    builder.next_local_id = builder.next_local_id + 1
    if builder.quote_prefix ~= nil then
        return string.format("%s_%s$%d", builder.quote_prefix, prefix, builder.next_local_id), frame
    end
    return string.format("%s$%d", prefix, builder.next_local_id), frame
end

local function make_var_methods(lowered_name, t)
    if is_layout_type(t) then
        return {
            set = function(self, value)
                store(t, self, value)
                return self
            end,
        }
    end
    return {
        set = function(self, value)
            local frame = current_frame()
            if frame == nil then
                error("moonlift variable assignment may only be used inside moonlift blocks", 2)
            end
            value = as_expr(value, t)
            frame.stmts[#frame.stmts + 1] = {
                tag = "set",
                name = lowered_name,
                value = value.node,
            }
            return self
        end,
    }
end

bind_layout_local = function(init, prefix, mutable)
    if mutable then
        local T, values = can_scalarize_struct_init(init)
        if T ~= nil then
            local refs = {}
            for i = 1, #T.fields do
                local f = T.fields[i]
                refs[f.name] = bind_var(values[f.name])
            end
            return setmetatable({ _struct = T, _fields = refs }, StructScalarVarMT)
        end
    end
    local T = assert(layout_type_of_value(init), "moonlift aggregate binding expects a layout value")
    local ptr_ref = alloc_stack_slot(T, prefix, mutable and make_var_methods(prefix, T) or nil)
    if is_agg_init(init) then
        store_aggregate(T, ptr_ref, init)
    else
        local src_ptr = assert(layout_ptr_of_value(init, T))
        copy(T, ptr_ref, src_ptr)
    end
    return ptr_ref
end

bind_let = function(init)
    if layout_type_of_value(init) ~= nil then
        return bind_layout_local(init, "let", false)
    end
    init = as_expr(init)
    local lowered_name, frame = fresh_local_name("let")
    local local_ref = expr({ tag = "local", name = lowered_name }, init.t)
    frame.stmts[#frame.stmts + 1] = {
        tag = "let",
        name = lowered_name,
        type = lower_type_name(init.t),
        init = init.node,
    }
    return local_ref
end

bind_var = function(init)
    if layout_type_of_value(init) ~= nil then
        return bind_layout_local(init, "var", true)
    end
    init = as_expr(init)
    local lowered_name, frame = fresh_local_name("var")
    local var_ref = expr({ tag = "local", name = lowered_name }, init.t, make_var_methods(lowered_name, init.t))
    frame.stmts[#frame.stmts + 1] = {
        tag = "var",
        name = lowered_name,
        type = lower_type_name(init.t),
        init = init.node,
    }
    return var_ref
end

local function while_(cond, body)
    local frame = current_frame()
    if frame == nil then
        error("moonlift.while_ may only be used inside moonlift blocks", 2)
    end
    cond = as_expr(cond, M.bool)
    assert(type(body) == "function", "moonlift.while_ body must be a function")
    frame.stmts[#frame.stmts + 1] = {
        tag = "while",
        cond = cond.node,
        body = capture_stmt_block(body),
    }
    return nil
end

break_ = function()
    return emit_stmt({ tag = "break" })
end

continue_ = function()
    return emit_stmt({ tag = "continue" })
end

switch_ = function(value, cases, default_case)
    value = as_expr(value)
    assert(type(cases) == "table", "moonlift.switch_ expects a case table")
    local default = default_case or cases.default
    assert(default ~= nil, "moonlift.switch_ requires a default case")
    local entries = {}
    for k, v in pairs(cases) do
        if k ~= "default" then
            local key_expr = is_expr(k) and k or as_expr(k, value.t)
            entries[#entries + 1] = {
                key = key_expr,
                sort_key = stable_value_key(key_expr.node),
                value = v,
            }
        end
    end
    table.sort(entries, function(a, b)
        return a.sort_key < b.sort_key
    end)
    for i = 2, #entries do
        assert(
            entries[i - 1].sort_key ~= entries[i].sort_key,
            "moonlift.switch_ requires distinct case keys after normalization"
        )
    end
    local out = default
    for i = #entries, 1, -1 do
        local entry = entries[i]
        out = if_(value:eq(entry.key), entry.value, out)
    end
    return out
end

emit_stmt = function(stmt)
    local frame = current_frame()
    if frame == nil then
        error("moonlift statement context is not active", 2)
    end
    frame.stmts[#frame.stmts + 1] = stmt
    return nil
end

local clone_quote_expr
local clone_quote_stmt
local validate_quote_expr
local validate_quote_stmt
local transform_quote_expr
local transform_quote_stmt
local walk_quote_expr
local walk_quote_stmt
local QuoteNS = {}

local function copy_kv_table(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

local function normalize_quote_spec(spec)
    local body = spec
    local params = {}
    if is_plain_table(spec) and not is_ir_quote(spec) then
        body = spec.body or spec[1]
        params = spec.params or {}
    end
    assert(type(body) == "function", "moonlift quote expects a function or { params = ..., body = fn }")
    return body, params
end

local function quote_result_parts(result)
    if result.node.tag == "block" then
        return result.node.stmts or {}, result.node.result, result.t
    end
    return {}, result.node, result.t
end

local function make_quote(data)
    return setmetatable(data, QuoteMT)
end

clone_quote_expr = function(node, ctx)
    if type(node) ~= "table" then return node end
    local tag = node.tag
    if tag == "quote_param" then
        return assert(ctx.arg_nodes[node.index], "moonlift quote parameter missing during splice")
    elseif tag == "quote_hole" then
        return assert(ctx.hole_nodes[node.name], ("moonlift quote hole '%s' is unbound"):format(node.name))
    elseif tag == "local" then
        return {
            tag = "local",
            name = assert(ctx.local_names[node.name], "moonlift quote local reference escaped capture"),
            type = node.type,
        }
    elseif tag == "stack_addr" then
        return {
            tag = "stack_addr",
            name = assert(ctx.slot_names[node.name], "moonlift quote stack slot reference escaped capture"),
            type = node.type,
        }
    elseif tag == "block" then
        local out = { tag = "block", stmts = {}, result = false, type = node.type }
        for i = 1, #(node.stmts or {}) do out.stmts[i] = clone_quote_stmt(node.stmts[i], ctx) end
        out.result = clone_quote_expr(node.result, ctx)
        return out
    elseif tag == "if" or tag == "select" then
        return {
            tag = tag,
            cond = clone_quote_expr(node.cond, ctx),
            then_ = clone_quote_expr(node.then_, ctx),
            else_ = clone_quote_expr(node.else_, ctx),
            type = node.type,
        }
    elseif tag == "load" then
        return { tag = "load", addr = clone_quote_expr(node.addr, ctx), type = node.type }
    elseif tag == "memcmp" then
        return {
            tag = "memcmp",
            a = clone_quote_expr(node.a, ctx),
            b = clone_quote_expr(node.b, ctx),
            len = clone_quote_expr(node.len, ctx),
            type = node.type,
        }
    elseif tag == "call" then
        local args = {}
        for i = 1, #(node.args or {}) do args[i] = clone_quote_expr(node.args[i], ctx) end
        return {
            tag = "call",
            callee_kind = node.callee_kind,
            name = node.name,
            addr = node.addr and clone_quote_expr(node.addr, ctx) or nil,
            params = node.params,
            result = node.result,
            args = args,
            type = node.type,
        }
    elseif tag == "neg" or tag == "not" or tag == "bnot" or tag == "cast" or tag == "trunc" or tag == "zext" or tag == "sext" or tag == "bitcast" then
        return { tag = tag, value = clone_quote_expr(node.value, ctx), type = node.type }
    elseif tag == "add" or tag == "sub" or tag == "mul" or tag == "div" or tag == "rem"
        or tag == "eq" or tag == "ne" or tag == "lt" or tag == "le" or tag == "gt" or tag == "ge"
        or tag == "and" or tag == "or" or tag == "band" or tag == "bor" or tag == "bxor"
        or tag == "shl" or tag == "shr_u" or tag == "shr_s" then
        return {
            tag = tag,
            lhs = clone_quote_expr(node.lhs, ctx),
            rhs = clone_quote_expr(node.rhs, ctx),
            type = node.type,
        }
    end
    local out = {}
    for k, v in pairs(node) do out[k] = type(v) == "table" and clone_quote_expr(v, ctx) or v end
    return out
end

clone_quote_stmt = function(stmt, ctx)
    if type(stmt) ~= "table" then return stmt end
    local tag = stmt.tag
    if tag == "let" or tag == "var" then
        local new_name = fresh_local_name(tag)
        ctx.local_names[stmt.name] = new_name
        return { tag = tag, name = new_name, type = stmt.type, init = clone_quote_expr(stmt.init, ctx) }
    elseif tag == "set" then
        return { tag = "set", name = assert(ctx.local_names[stmt.name], "moonlift quote set escaped capture"), value = clone_quote_expr(stmt.value, ctx) }
    elseif tag == "while" then
        local body = {}
        for i = 1, #(stmt.body or {}) do body[i] = clone_quote_stmt(stmt.body[i], ctx) end
        return { tag = "while", cond = clone_quote_expr(stmt.cond, ctx), body = body }
    elseif tag == "store" then
        return { tag = "store", type = stmt.type, addr = clone_quote_expr(stmt.addr, ctx), value = clone_quote_expr(stmt.value, ctx) }
    elseif tag == "stack_slot" then
        local new_name = fresh_local_name("slot")
        ctx.slot_names[stmt.name] = new_name
        return { tag = "stack_slot", name = new_name, size = stmt.size, align = stmt.align, align_shift = stmt.align_shift }
    elseif tag == "memcpy" or tag == "memmove" then
        return { tag = tag, dst = clone_quote_expr(stmt.dst, ctx), src = clone_quote_expr(stmt.src, ctx), len = clone_quote_expr(stmt.len, ctx) }
    elseif tag == "memset" then
        return { tag = "memset", dst = clone_quote_expr(stmt.dst, ctx), byte = clone_quote_expr(stmt.byte, ctx), len = clone_quote_expr(stmt.len, ctx) }
    elseif tag == "call" then
        local args = {}
        for i = 1, #(stmt.args or {}) do args[i] = clone_quote_expr(stmt.args[i], ctx) end
        return {
            tag = "call",
            callee_kind = stmt.callee_kind,
            name = stmt.name,
            addr = stmt.addr and clone_quote_expr(stmt.addr, ctx) or nil,
            params = stmt.params,
            result = stmt.result,
            args = args,
        }
    elseif tag == "break" or tag == "continue" then
        return { tag = tag }
    end
    local out = {}
    for k, v in pairs(stmt) do out[k] = type(v) == "table" and clone_quote_expr(v, ctx) or v end
    return out
end

validate_quote_expr = function(node, state)
    if type(node) ~= "table" then return end
    local tag = node.tag
    if tag == "local" then
        if not state.locals[node.name] then
            error(("moonlift quote does not allow free local reference '%s'"):format(node.name), 2)
        end
        return
    elseif tag == "stack_addr" then
        if not state.slots[node.name] then
            error(("moonlift quote does not allow free stack-slot reference '%s'"):format(node.name), 2)
        end
        return
    elseif tag == "arg" then
        error("moonlift quote does not allow free function arg references; use q.* params", 2)
    elseif tag == "quote_param" then
        return
    elseif tag == "quote_hole" then
        local prev = state.holes[node.name]
        if prev ~= nil then
            assert(prev == node.hole_type, "moonlift quote hole reused with different types")
        else
            state.holes[node.name] = node.hole_type
        end
        return
    elseif tag == "block" then
        for i = 1, #(node.stmts or {}) do validate_quote_stmt(node.stmts[i], state) end
        if node.result ~= nil then validate_quote_expr(node.result, state) end
        return
    elseif tag == "if" or tag == "select" then
        validate_quote_expr(node.cond, state)
        validate_quote_expr(node.then_, state)
        validate_quote_expr(node.else_, state)
        return
    elseif tag == "call" then
        if node.addr ~= nil then validate_quote_expr(node.addr, state) end
        for i = 1, #(node.args or {}) do validate_quote_expr(node.args[i], state) end
        return
    elseif tag == "memcmp" then
        validate_quote_expr(node.a, state)
        validate_quote_expr(node.b, state)
        validate_quote_expr(node.len, state)
        return
    end
    for _, v in pairs(node) do if type(v) == "table" then validate_quote_expr(v, state) end end
end

validate_quote_stmt = function(stmt, state)
    if type(stmt) ~= "table" then return end
    local tag = stmt.tag
    if tag == "let" or tag == "var" then
        validate_quote_expr(stmt.init, state)
        state.locals[stmt.name] = true
    elseif tag == "set" then
        if not state.locals[stmt.name] then
            error(("moonlift quote does not allow free set target '%s'"):format(stmt.name), 2)
        end
        validate_quote_expr(stmt.value, state)
    elseif tag == "while" then
        validate_quote_expr(stmt.cond, state)
        for i = 1, #(stmt.body or {}) do validate_quote_stmt(stmt.body[i], state) end
    elseif tag == "store" then
        validate_quote_expr(stmt.addr, state)
        validate_quote_expr(stmt.value, state)
    elseif tag == "stack_slot" then
        state.slots[stmt.name] = true
    elseif tag == "memcpy" or tag == "memmove" then
        validate_quote_expr(stmt.dst, state)
        validate_quote_expr(stmt.src, state)
        validate_quote_expr(stmt.len, state)
    elseif tag == "memset" then
        validate_quote_expr(stmt.dst, state)
        validate_quote_expr(stmt.byte, state)
        validate_quote_expr(stmt.len, state)
    elseif tag == "call" then
        if stmt.addr ~= nil then validate_quote_expr(stmt.addr, state) end
        for i = 1, #(stmt.args or {}) do validate_quote_expr(stmt.args[i], state) end
    end
end

local function collect_quote_meta(stmts, result_node)
    local state = { locals = {}, slots = {}, holes = {} }
    for i = 1, #(stmts or {}) do validate_quote_stmt(stmts[i], state) end
    if result_node ~= nil then validate_quote_expr(result_node, state) end
    return state.holes
end

local function resolve_quote_value(expected_t, value, label)
    if is_layout_type(expected_t) then
        local ptr_v, actual_t = layout_ptr_of_value(value, expected_t)
        if ptr_v ~= nil then
            assert(actual_t == expected_t, ("moonlift quote %s type mismatch"):format(label))
            return ptr_v.node
        end
        if is_agg_init(value) and value._layout == expected_t then
            return bind_layout_local(value, "quote", false).node
        end
        error(("moonlift quote expected a %s %s or pointer source"):format(expected_t.name, label), 2)
    end
    return as_expr(value, expected_t).node
end

local function normalize_quote_expr_replacement(replacement, fallback_t)
    if replacement == nil then return nil, fallback_t end
    if is_expr(replacement) then
        return replacement.node, replacement.t
    end
    assert(type(replacement) == "table" and replacement.tag ~= nil, "moonlift quote expr rewrite must return nil, an expr, or an expr node")
    return replacement, fallback_t
end

local function append_stmt_rewrite_result(out, replacement, fallback_stmt)
    if replacement == nil then
        out[#out + 1] = fallback_stmt
        return
    end
    if replacement == false then
        return
    end
    assert(type(replacement) == "table" and not is_expr(replacement), "moonlift quote stmt rewrite must return nil, false, a stmt node, or a stmt-node list")
    if replacement.tag ~= nil then
        out[#out + 1] = replacement
        return
    end
    for i = 1, #replacement do
        local stmt = replacement[i]
        assert(type(stmt) == "table" and stmt.tag ~= nil, "moonlift quote stmt rewrite list must contain stmt nodes")
        out[#out + 1] = stmt
    end
end

local function rewrite_quote_parts(self, expr_mapper, stmt_mapper)
    local new_stmts = {}
    for i = 1, #(self.stmts or {}) do
        append_stmt_rewrite_result(new_stmts, transform_quote_stmt(self.stmts[i], expr_mapper, stmt_mapper), self.stmts[i])
    end

    local new_result_node = self.result_node
    local new_result_t = self.result_t
    if self.result_node ~= nil then
        new_result_node, new_result_t = transform_quote_expr(self.result_node, self.result_t, expr_mapper, stmt_mapper)
    end

    local final_result_t = new_result_t or self.result_t or M.void
    if new_result_node == nil then
        final_result_t = M.void
    end

    return make_quote({
        stmts = new_stmts,
        result_node = new_result_node,
        result_t = final_result_t,
        params = self.params,
        _param_count = self._param_count,
        hole_types = collect_quote_meta(new_stmts, new_result_node),
        hole_bindings = copy_kv_table(self.hole_bindings),
    })
end

local function walk_quote_node_children(node, expr_visitor, stmt_visitor)
    if type(node) ~= "table" then return end
    local tag = node.tag
    if tag == "block" then
        for i = 1, #(node.stmts or {}) do walk_quote_stmt(node.stmts[i], expr_visitor, stmt_visitor) end
        if node.result ~= nil then walk_quote_expr(node.result, expr_visitor, stmt_visitor) end
        return
    elseif tag == "if" or tag == "select" then
        walk_quote_expr(node.cond, expr_visitor, stmt_visitor)
        walk_quote_expr(node.then_, expr_visitor, stmt_visitor)
        walk_quote_expr(node.else_, expr_visitor, stmt_visitor)
        return
    elseif tag == "load" then
        walk_quote_expr(node.addr, expr_visitor, stmt_visitor)
        return
    elseif tag == "memcmp" then
        walk_quote_expr(node.a, expr_visitor, stmt_visitor)
        walk_quote_expr(node.b, expr_visitor, stmt_visitor)
        walk_quote_expr(node.len, expr_visitor, stmt_visitor)
        return
    elseif tag == "call" then
        if node.addr ~= nil then walk_quote_expr(node.addr, expr_visitor, stmt_visitor) end
        for i = 1, #(node.args or {}) do walk_quote_expr(node.args[i], expr_visitor, stmt_visitor) end
        return
    elseif tag == "neg" or tag == "not" or tag == "bnot" or tag == "cast" or tag == "trunc" or tag == "zext" or tag == "sext" or tag == "bitcast" then
        walk_quote_expr(node.value, expr_visitor, stmt_visitor)
        return
    elseif tag == "add" or tag == "sub" or tag == "mul" or tag == "div" or tag == "rem"
        or tag == "eq" or tag == "ne" or tag == "lt" or tag == "le" or tag == "gt" or tag == "ge"
        or tag == "and" or tag == "or" or tag == "band" or tag == "bor" or tag == "bxor"
        or tag == "shl" or tag == "shr_u" or tag == "shr_s" then
        walk_quote_expr(node.lhs, expr_visitor, stmt_visitor)
        walk_quote_expr(node.rhs, expr_visitor, stmt_visitor)
        return
    end

    for _, v in pairs(node) do
        if type(v) == "table" then
            if v.tag ~= nil then
                if v.type ~= nil or v.tag == "block" or v.tag == "quote_param" or v.tag == "quote_hole" or v.tag == "local" or v.tag == "stack_addr" then
                    walk_quote_expr(v, expr_visitor, stmt_visitor)
                else
                    walk_quote_stmt(v, expr_visitor, stmt_visitor)
                end
            else
                for i = 1, #v do
                    local item = v[i]
                    if type(item) == "table" and item.tag ~= nil then
                        if item.type ~= nil or item.tag == "block" or item.tag == "quote_param" or item.tag == "quote_hole" or item.tag == "local" or item.tag == "stack_addr" then
                            walk_quote_expr(item, expr_visitor, stmt_visitor)
                        else
                            walk_quote_stmt(item, expr_visitor, stmt_visitor)
                        end
                    end
                end
            end
        end
    end
end

walk_quote_expr = function(node, expr_visitor, stmt_visitor)
    if type(node) ~= "table" then return end
    local descend = true
    if expr_visitor ~= nil then
        local out = expr_visitor(node)
        if out == false then descend = false end
    end
    if descend then
        walk_quote_node_children(node, expr_visitor, stmt_visitor)
    end
end

walk_quote_stmt = function(stmt, expr_visitor, stmt_visitor)
    if type(stmt) ~= "table" then return end
    local descend = true
    if stmt_visitor ~= nil then
        local out = stmt_visitor(stmt)
        if out == false then descend = false end
    end
    if not descend then return end
    local tag = stmt.tag
    if tag == "let" or tag == "var" then
        walk_quote_expr(stmt.init, expr_visitor, stmt_visitor)
    elseif tag == "set" then
        walk_quote_expr(stmt.value, expr_visitor, stmt_visitor)
    elseif tag == "while" then
        walk_quote_expr(stmt.cond, expr_visitor, stmt_visitor)
        for i = 1, #(stmt.body or {}) do walk_quote_stmt(stmt.body[i], expr_visitor, stmt_visitor) end
    elseif tag == "store" then
        walk_quote_expr(stmt.addr, expr_visitor, stmt_visitor)
        walk_quote_expr(stmt.value, expr_visitor, stmt_visitor)
    elseif tag == "memcpy" or tag == "memmove" then
        walk_quote_expr(stmt.dst, expr_visitor, stmt_visitor)
        walk_quote_expr(stmt.src, expr_visitor, stmt_visitor)
        walk_quote_expr(stmt.len, expr_visitor, stmt_visitor)
    elseif tag == "memset" then
        walk_quote_expr(stmt.dst, expr_visitor, stmt_visitor)
        walk_quote_expr(stmt.byte, expr_visitor, stmt_visitor)
        walk_quote_expr(stmt.len, expr_visitor, stmt_visitor)
    elseif tag == "call" then
        if stmt.addr ~= nil then walk_quote_expr(stmt.addr, expr_visitor, stmt_visitor) end
        for i = 1, #(stmt.args or {}) do walk_quote_expr(stmt.args[i], expr_visitor, stmt_visitor) end
    end
end

local function normalize_walk_spec(spec)
    if type(spec) == "function" then
        return function(node) return spec("expr", node) end, function(node) return spec("stmt", node) end
    end
    assert(is_plain_table(spec), "moonlift quote walk/query expects a function or { expr = fn?, stmt = fn? }")
    local expr_visitor = spec.expr
    local stmt_visitor = spec.stmt
    if expr_visitor ~= nil then assert(type(expr_visitor) == "function", "moonlift quote expr visitor must be a function") end
    if stmt_visitor ~= nil then assert(type(stmt_visitor) == "function", "moonlift quote stmt visitor must be a function") end
    return expr_visitor, stmt_visitor
end

local function walk_quote_parts(self, spec)
    local expr_visitor, stmt_visitor = normalize_walk_spec(spec)
    for i = 1, #(self.stmts or {}) do walk_quote_stmt(self.stmts[i], expr_visitor, stmt_visitor) end
    if self.result_node ~= nil then walk_quote_expr(self.result_node, expr_visitor, stmt_visitor) end
end

local function query_quote_parts(self, spec)
    local out = {}
    local expr_visitor, stmt_visitor = normalize_walk_spec(spec)
    local function collect(v)
        if v ~= nil and v ~= false then out[#out + 1] = v end
        return nil
    end
    walk_quote_parts(self, {
        expr = expr_visitor and function(node) return collect(expr_visitor(node)) end or nil,
        stmt = stmt_visitor and function(node) return collect(stmt_visitor(node)) end or nil,
    })
    return out
end

transform_quote_expr = function(node, node_t, expr_mapper, stmt_mapper)
    if type(node) ~= "table" then return node, node_t end
    local tag = node.tag
    local out
    if tag == "block" then
        local stmts = {}
        for i = 1, #(node.stmts or {}) do
            append_stmt_rewrite_result(stmts, transform_quote_stmt(node.stmts[i], expr_mapper, stmt_mapper), node.stmts[i])
        end
        local result_node, result_t = transform_quote_expr(node.result, node_t, expr_mapper, stmt_mapper)
        out = { tag = "block", stmts = stmts, result = result_node, type = node.type }
        local replacement, replacement_t = normalize_quote_expr_replacement(expr_mapper and expr_mapper(out) or nil, result_t)
        return replacement or out, replacement_t or result_t
    elseif tag == "if" or tag == "select" then
        local cond = select(1, transform_quote_expr(node.cond, M.bool, expr_mapper, stmt_mapper))
        local then_node = select(1, transform_quote_expr(node.then_, node_t, expr_mapper, stmt_mapper))
        local else_node = select(1, transform_quote_expr(node.else_, node_t, expr_mapper, stmt_mapper))
        out = { tag = tag, cond = cond, then_ = then_node, else_ = else_node, type = node.type }
    elseif tag == "load" then
        out = { tag = "load", addr = select(1, transform_quote_expr(node.addr, nil, expr_mapper, stmt_mapper)), type = node.type }
    elseif tag == "memcmp" then
        out = {
            tag = "memcmp",
            a = select(1, transform_quote_expr(node.a, nil, expr_mapper, stmt_mapper)),
            b = select(1, transform_quote_expr(node.b, nil, expr_mapper, stmt_mapper)),
            len = select(1, transform_quote_expr(node.len, M.usize, expr_mapper, stmt_mapper)),
            type = node.type,
        }
    elseif tag == "call" then
        local args = {}
        for i = 1, #(node.args or {}) do
            args[i] = select(1, transform_quote_expr(node.args[i], nil, expr_mapper, stmt_mapper))
        end
        out = {
            tag = "call",
            callee_kind = node.callee_kind,
            name = node.name,
            addr = node.addr and select(1, transform_quote_expr(node.addr, nil, expr_mapper, stmt_mapper)) or nil,
            params = node.params,
            result = node.result,
            args = args,
            type = node.type,
        }
    elseif tag == "neg" or tag == "not" or tag == "bnot" or tag == "cast" or tag == "trunc" or tag == "zext" or tag == "sext" or tag == "bitcast" then
        out = { tag = tag, value = select(1, transform_quote_expr(node.value, nil, expr_mapper, stmt_mapper)), type = node.type }
    elseif tag == "add" or tag == "sub" or tag == "mul" or tag == "div" or tag == "rem"
        or tag == "eq" or tag == "ne" or tag == "lt" or tag == "le" or tag == "gt" or tag == "ge"
        or tag == "and" or tag == "or" or tag == "band" or tag == "bor" or tag == "bxor"
        or tag == "shl" or tag == "shr_u" or tag == "shr_s" then
        out = {
            tag = tag,
            lhs = select(1, transform_quote_expr(node.lhs, nil, expr_mapper, stmt_mapper)),
            rhs = select(1, transform_quote_expr(node.rhs, nil, expr_mapper, stmt_mapper)),
            type = node.type,
        }
    else
        out = {}
        for k, v in pairs(node) do out[k] = v end
    end

    local replacement, replacement_t = normalize_quote_expr_replacement(expr_mapper and expr_mapper(out) or nil, node_t)
    return replacement or out, replacement_t or node_t
end

transform_quote_stmt = function(stmt, expr_mapper, stmt_mapper)
    if type(stmt) ~= "table" then return stmt end
    local tag = stmt.tag
    local out
    if tag == "let" or tag == "var" then
        out = { tag = tag, name = stmt.name, type = stmt.type, init = select(1, transform_quote_expr(stmt.init, nil, expr_mapper, stmt_mapper)) }
    elseif tag == "set" then
        out = { tag = "set", name = stmt.name, value = select(1, transform_quote_expr(stmt.value, nil, expr_mapper, stmt_mapper)) }
    elseif tag == "while" then
        local body = {}
        for i = 1, #(stmt.body or {}) do
            append_stmt_rewrite_result(body, transform_quote_stmt(stmt.body[i], expr_mapper, stmt_mapper), stmt.body[i])
        end
        out = { tag = "while", cond = select(1, transform_quote_expr(stmt.cond, M.bool, expr_mapper, stmt_mapper)), body = body }
    elseif tag == "store" then
        out = {
            tag = "store",
            type = stmt.type,
            addr = select(1, transform_quote_expr(stmt.addr, nil, expr_mapper, stmt_mapper)),
            value = select(1, transform_quote_expr(stmt.value, nil, expr_mapper, stmt_mapper)),
        }
    elseif tag == "stack_slot" then
        out = { tag = "stack_slot", name = stmt.name, size = stmt.size, align = stmt.align, align_shift = stmt.align_shift }
    elseif tag == "memcpy" or tag == "memmove" then
        out = {
            tag = tag,
            dst = select(1, transform_quote_expr(stmt.dst, nil, expr_mapper, stmt_mapper)),
            src = select(1, transform_quote_expr(stmt.src, nil, expr_mapper, stmt_mapper)),
            len = select(1, transform_quote_expr(stmt.len, M.usize, expr_mapper, stmt_mapper)),
        }
    elseif tag == "memset" then
        out = {
            tag = "memset",
            dst = select(1, transform_quote_expr(stmt.dst, nil, expr_mapper, stmt_mapper)),
            byte = select(1, transform_quote_expr(stmt.byte, nil, expr_mapper, stmt_mapper)),
            len = select(1, transform_quote_expr(stmt.len, M.usize, expr_mapper, stmt_mapper)),
        }
    elseif tag == "call" then
        local args = {}
        for i = 1, #(stmt.args or {}) do
            args[i] = select(1, transform_quote_expr(stmt.args[i], nil, expr_mapper, stmt_mapper))
        end
        out = {
            tag = "call",
            callee_kind = stmt.callee_kind,
            name = stmt.name,
            addr = stmt.addr and select(1, transform_quote_expr(stmt.addr, nil, expr_mapper, stmt_mapper)) or nil,
            params = stmt.params,
            result = stmt.result,
            args = args,
        }
    elseif tag == "break" or tag == "continue" then
        out = { tag = tag }
    else
        out = {}
        for k, v in pairs(stmt) do out[k] = v end
    end
    if stmt_mapper ~= nil then
        return stmt_mapper(out)
    end
    return out
end

local function capture_quote(kind, spec)
    local body, params = normalize_quote_spec(spec)
    local builder = {
        next_local_id = 0,
        frame = { stmts = {}, parent = nil },
        is_quote_capture = true,
        quote_prefix = "q" .. tostring(_next_quote_capture_id + 1),
    }
    _next_quote_capture_id = _next_quote_capture_id + 1

    local args = {}
    for i = 1, #params do
        local p = params[i]
        assert(type(p) == "table" and p.t ~= nil, "moonlift quote params must come from moonlift.param or type(name)")
        local qt = is_layout_type(p.t) and make_ptr(p.t) or p.t
        args[i] = expr({ tag = "quote_param", index = i, type = lower_type_name(qt) }, qt)
    end

    local stmts, result_node, result_t
    if kind == "stmt" then
        stmts = with_builder(builder, function()
            return capture_stmt_block(function()
                local out = run_builder_fn(body, unpack(args, 1, #args))
                if out ~= nil then
                    error("moonlift q.stmt body must not return a value", 2)
                end
            end)
        end)
        result_node = nil
        result_t = M.void
    else
        local result = with_builder(builder, function()
            return block(function()
                return run_builder_fn(body, unpack(args, 1, #args))
            end)
        end)
        stmts, result_node, result_t = quote_result_parts(result)
        if kind == "expr" then
            assert(not is_void_type(result_t), "moonlift q.expr must produce a value")
        end
    end

    return make_quote({
        stmts = stmts,
        result_node = result_node,
        result_t = result_t,
        params = params,
        _param_count = #params,
        hole_types = collect_quote_meta(stmts, result_node),
        hole_bindings = {},
    })
end

hole = function(name, t)
    local builder = current_builder
    if builder == nil or not builder.is_quote_capture then
        error("moonlift.hole may only be used inside quote capture", 2)
    end
    assert(type(name) == "string", "moonlift.hole name must be a string")
    local qt = is_layout_type(t) and make_ptr(t) or t
    assert(is_type(qt), "moonlift.hole requires a Moonlift type")
    return expr({ tag = "quote_hole", name = name, type = lower_type_name(qt), hole_type = t }, qt)
end

QuoteNS.block = function(spec)
    return capture_quote("block", spec)
end

QuoteNS.expr = function(spec)
    return capture_quote("expr", spec)
end

QuoteNS.stmt = function(spec)
    return capture_quote("stmt", spec)
end

QuoteNS.nop = function()
    return make_quote({
        stmts = {},
        result_node = nil,
        result_t = M.void,
        params = {},
        _param_count = 0,
        hole_types = {},
        hole_bindings = {},
    })
end

QuoteNS.from_expr = function(e)
    e = as_expr(e)
    return make_quote({
        stmts = {},
        result_node = e.node,
        result_t = e.t,
        params = {},
        _param_count = 0,
        hole_types = {},
        hole_bindings = {},
    })
end

QuoteNS.rewrite = function(quote_value, spec)
    return quote_value:rewrite(spec)
end

QuoteNS.map_expr = function(quote_value, fn)
    return quote_value:map_expr(fn)
end

QuoteNS.map_stmt = function(quote_value, fn)
    return quote_value:map_stmt(fn)
end

QuoteNS.walk = function(quote_value, spec)
    return quote_value:walk(spec)
end

QuoteNS.query = function(quote_value, spec)
    return quote_value:query(spec)
end

QuoteNS.seq_all = function(list)
    assert(type(list) == "table", "moonlift q.seq_all expects a table")
    if #list == 0 then return QuoteNS.nop() end
    local out = list[1]
    for i = 2, #list do out = out:then_(list[i]) end
    return out
end

quote = QuoteNS.block
quote_ir = QuoteNS.block
quote_expr = QuoteNS.expr
quote_block = QuoteNS.block

QuoteMT.__tostring = function(self)
    return string.format("moonlift.quote<%d params, %d holes>", self._param_count or 0, next(self.hole_types or {}) and 1 or 0)
end

QuoteMT.__concat = function(a, b)
    return a:then_(b)
end

QuoteMT.__call = function(self, ...)
    return self:splice(...)
end

QuoteMT.__index = {
    bind = function(self, bindings)
        assert(is_plain_table(bindings), "moonlift quote:bind expects a plain table")
        local merged = copy_kv_table(self.hole_bindings)
        for k, v in pairs(bindings) do merged[k] = v end
        return make_quote({
            stmts = self.stmts,
            result_node = self.result_node,
            result_t = self.result_t,
            params = self.params,
            _param_count = self._param_count,
            hole_types = self.hole_types,
            hole_bindings = merged,
        })
    end,
    subst = function(self, name, value)
        local t = assert(self.hole_types[name], ("moonlift quote has no hole '%s'"):format(name))
        if is_layout_type(t) then
            resolve_quote_value(t, value, "hole")
        else
            as_expr(value, t)
        end
        return self:bind({ [name] = value })
    end,
    subst_many = function(self, bindings)
        return self:bind(bindings)
    end,
    then_ = function(self, other)
        assert(is_ir_quote(other), "moonlift quote:then_ expects another quote")
        assert((self._param_count or 0) == (other._param_count or 0), "moonlift cannot sequence quotes with different arities")
        for i = 1, (self._param_count or 0) do
            assert(self.params[i].t == other.params[i].t, "moonlift cannot sequence quotes with different param types")
        end
        local hole_types = copy_kv_table(self.hole_types)
        for name, t in pairs(other.hole_types or {}) do
            local prev = hole_types[name]
            assert(prev == nil or prev == t, ("moonlift quote hole '%s' has conflicting types"):format(name))
            hole_types[name] = t
        end
        local hole_bindings = copy_kv_table(self.hole_bindings)
        for name, v in pairs(other.hole_bindings or {}) do
            hole_bindings[name] = v
        end
        local stmts = {}
        for i = 1, #(self.stmts or {}) do stmts[#stmts + 1] = self.stmts[i] end
        for i = 1, #(other.stmts or {}) do stmts[#stmts + 1] = other.stmts[i] end
        local result_node, result_t = self.result_node, self.result_t
        if other.result_node ~= nil then
            result_node, result_t = other.result_node, other.result_t
        end
        return make_quote({
            stmts = stmts,
            result_node = result_node,
            result_t = result_t,
            params = self.params,
            _param_count = self._param_count,
            hole_types = hole_types,
            hole_bindings = hole_bindings,
        })
    end,
    seq_all = function(self, list)
        local out = self
        for i = 1, #list do out = out:then_(list[i]) end
        return out
    end,
    map_expr = function(self, fn)
        assert(type(fn) == "function", "moonlift quote:map_expr expects a function")
        return rewrite_quote_parts(self, fn, nil)
    end,
    map_stmt = function(self, fn)
        assert(type(fn) == "function", "moonlift quote:map_stmt expects a function")
        return rewrite_quote_parts(self, nil, fn)
    end,
    rewrite = function(self, spec)
        if type(spec) == "function" then
            return rewrite_quote_parts(self, function(node) return spec("expr", node) end, function(node) return spec("stmt", node) end)
        end
        assert(is_plain_table(spec), "moonlift quote:rewrite expects a function or { expr = fn?, stmt = fn? }")
        local expr_mapper = spec.expr
        local stmt_mapper = spec.stmt
        if expr_mapper ~= nil then assert(type(expr_mapper) == "function", "moonlift quote:rewrite expr mapper must be a function") end
        if stmt_mapper ~= nil then assert(type(stmt_mapper) == "function", "moonlift quote:rewrite stmt mapper must be a function") end
        return rewrite_quote_parts(self, expr_mapper, stmt_mapper)
    end,
    walk = function(self, spec)
        walk_quote_parts(self, spec)
        return self
    end,
    query = function(self, spec)
        return query_quote_parts(self, spec)
    end,
    splice = function(self, ...)
        local builder = current_builder
        if builder == nil then
            error("moonlift quote:splice() may only be used inside Moonlift function bodies", 2)
        end
        assert(select("#", ...) == (self._param_count or 0), ("moonlift quote expected %d args, got %d"):format(self._param_count or 0, select("#", ...)))
        local arg_nodes = {}
        for i = 1, (self._param_count or 0) do
            arg_nodes[i] = resolve_quote_value(self.params[i].t, select(i, ...), "argument")
        end
        local hole_nodes = {}
        for name, ht in pairs(self.hole_types or {}) do
            local hv = self.hole_bindings[name]
            assert(hv ~= nil, ("moonlift quote hole '%s' is unbound"):format(name))
            hole_nodes[name] = resolve_quote_value(ht, hv, "hole")
        end
        local ctx = { arg_nodes = arg_nodes, hole_nodes = hole_nodes, local_names = {}, slot_names = {} }
        for i = 1, #(self.stmts or {}) do emit_stmt(clone_quote_stmt(self.stmts[i], ctx)) end
        if self.result_node == nil then return nil end
        return expr(clone_quote_expr(self.result_node, ctx), self.result_t)
    end,
    type = function(self)
        return self.result_t
    end,
    result_type = function(self)
        return self.result_t
    end,
    free_holes = function(self)
        local out = {}
        for name, t in pairs(self.hole_types or {}) do
            if self.hole_bindings[name] == nil then out[name] = t end
        end
        return out
    end,
    arity = function(self)
        return self._param_count or 0
    end,
    param_count = function(self)
        return self._param_count or 0
    end,
    is_expr = function(self)
        return self.result_node ~= nil
    end,
    is_stmt = function(self)
        return self.result_node == nil
    end,
    is_block = function(self)
        return #(self.stmts or {}) > 0
    end,
}

q = QuoteNS

LetMT.__call = function(_, init)
    return bind_let(init)
end

VarMT.__call = function(_, init)
    return bind_var(init)
end

local function root_stack_slot_name(node)
    if type(node) ~= "table" then return nil end
    if node.tag == "stack_addr" then
        return node.name
    end
    return root_stack_slot_name(node.value)
        or root_stack_slot_name(node.addr)
        or root_stack_slot_name(node.lhs)
        or root_stack_slot_name(node.rhs)
        or root_stack_slot_name(node.a)
        or root_stack_slot_name(node.b)
        or root_stack_slot_name(node.len)
        or root_stack_slot_name(node.cond)
        or root_stack_slot_name(node.then_)
        or root_stack_slot_name(node.else_)
        or root_stack_slot_name(node.result)
end

local function root_arg_index(node)
    if type(node) ~= "table" then return nil end
    if node.tag == "arg" then
        return node.index
    end
    return root_arg_index(node.value)
        or root_arg_index(node.addr)
        or root_arg_index(node.lhs)
        or root_arg_index(node.rhs)
        or root_arg_index(node.a)
        or root_arg_index(node.b)
        or root_arg_index(node.len)
        or root_arg_index(node.cond)
        or root_arg_index(node.then_)
        or root_arg_index(node.else_)
        or root_arg_index(node.result)
end

local function analyze_layout_param_copies(root, copies)
    local tracked = {}
    for i = 1, #copies do
        local c = copies[i]
        tracked[c.slot_name] = {
            arg_node = c.arg_node,
            arg_index = c.arg_index,
            mutable = false,
            escape = false,
        }
    end

    local visit_expr, visit_stmt

    visit_expr = function(node)
        if type(node) ~= "table" then return end
        local tag = node.tag
        if tag == "block" then
            local stmts = node.stmts or {}
            for i = 1, #stmts do visit_stmt(stmts[i]) end
            visit_expr(node.result)
        elseif tag == "if" then
            visit_expr(node.cond)
            visit_expr(node.then_)
            visit_expr(node.else_)
        elseif tag == "call" then
            if node.addr ~= nil then visit_expr(node.addr) end
            local args = node.args or {}
            for i = 1, #args do
                visit_expr(args[i])
                local slot = root_stack_slot_name(args[i])
                if slot ~= nil and tracked[slot] ~= nil then
                    tracked[slot].escape = true
                end
            end
        elseif tag == "memcmp" then
            visit_expr(node.a)
            visit_expr(node.b)
            visit_expr(node.len)
        else
            visit_expr(node.value)
            visit_expr(node.addr)
            visit_expr(node.lhs)
            visit_expr(node.rhs)
            visit_expr(node.a)
            visit_expr(node.b)
            visit_expr(node.len)
            visit_expr(node.cond)
            visit_expr(node.then_)
            visit_expr(node.else_)
            visit_expr(node.result)
        end
    end

    visit_stmt = function(stmt)
        if type(stmt) ~= "table" then return end
        local tag = stmt.tag
        if tag == "while" then
            visit_expr(stmt.cond)
            local body = stmt.body or {}
            for i = 1, #body do visit_stmt(body[i]) end
        elseif tag == "if" then
            visit_expr(stmt.cond)
            local then_body = stmt.then_body or {}
            local else_body = stmt.else_body or {}
            for i = 1, #then_body do visit_stmt(then_body[i]) end
            for i = 1, #else_body do visit_stmt(else_body[i]) end
        elseif tag == "store" then
            visit_expr(stmt.addr)
            visit_expr(stmt.value)
            local slot = root_stack_slot_name(stmt.addr)
            if slot ~= nil and tracked[slot] ~= nil then
                tracked[slot].mutable = true
            end
        elseif tag == "memcpy" or tag == "memmove" then
            visit_expr(stmt.dst)
            visit_expr(stmt.src)
            visit_expr(stmt.len)
            local slot = root_stack_slot_name(stmt.dst)
            if slot ~= nil and tracked[slot] ~= nil then
                local info = tracked[slot]
                local src_arg = root_arg_index(stmt.src)
                if not (tag == "memcpy" and src_arg ~= nil and src_arg == info.arg_index) then
                    info.mutable = true
                end
            end
        elseif tag == "memset" then
            visit_expr(stmt.dst)
            visit_expr(stmt.byte)
            visit_expr(stmt.len)
            local slot = root_stack_slot_name(stmt.dst)
            if slot ~= nil and tracked[slot] ~= nil then
                tracked[slot].mutable = true
            end
        elseif tag == "call" then
            if stmt.addr ~= nil then visit_expr(stmt.addr) end
            local args = stmt.args or {}
            for i = 1, #args do
                visit_expr(args[i])
                local slot = root_stack_slot_name(args[i])
                if slot ~= nil and tracked[slot] ~= nil then
                    tracked[slot].escape = true
                end
            end
        else
            visit_expr(stmt.init)
            visit_expr(stmt.value)
        end
    end

    visit_expr(root)
    return tracked
end

local function rewrite_layout_param_copies(root, tracked)
    local replacements = {}
    local remove_slots = {}
    for slot_name, info in pairs(tracked) do
        if not info.mutable and not info.escape then
            replacements[slot_name] = info.arg_node
            remove_slots[slot_name] = true
        end
    end
    if next(remove_slots) == nil then
        return root
    end

    local rewrite_expr, rewrite_stmt

    rewrite_expr = function(node)
        if type(node) ~= "table" then return node end
        if node.tag == "stack_addr" and replacements[node.name] ~= nil then
            return replacements[node.name]
        end
        local tag = node.tag
        if tag == "block" then
            local old = node.stmts or {}
            local new = {}
            for i = 1, #old do
                local stmt = rewrite_stmt(old[i])
                if stmt ~= nil then new[#new + 1] = stmt end
            end
            node.stmts = new
            node.result = rewrite_expr(node.result)
            return node
        elseif tag == "if" then
            node.cond = rewrite_expr(node.cond)
            node.then_ = rewrite_expr(node.then_)
            node.else_ = rewrite_expr(node.else_)
            return node
        elseif tag == "call" then
            if node.addr ~= nil then node.addr = rewrite_expr(node.addr) end
            local args = node.args or {}
            for i = 1, #args do args[i] = rewrite_expr(args[i]) end
            return node
        elseif tag == "memcmp" then
            node.a = rewrite_expr(node.a)
            node.b = rewrite_expr(node.b)
            node.len = rewrite_expr(node.len)
            return node
        else
            if node.value ~= nil then node.value = rewrite_expr(node.value) end
            if node.addr ~= nil then node.addr = rewrite_expr(node.addr) end
            if node.lhs ~= nil then node.lhs = rewrite_expr(node.lhs) end
            if node.rhs ~= nil then node.rhs = rewrite_expr(node.rhs) end
            if node.a ~= nil then node.a = rewrite_expr(node.a) end
            if node.b ~= nil then node.b = rewrite_expr(node.b) end
            if node.len ~= nil then node.len = rewrite_expr(node.len) end
            if node.cond ~= nil then node.cond = rewrite_expr(node.cond) end
            if node.then_ ~= nil then node.then_ = rewrite_expr(node.then_) end
            if node.else_ ~= nil then node.else_ = rewrite_expr(node.else_) end
            if node.result ~= nil then node.result = rewrite_expr(node.result) end
            return node
        end
    end

    rewrite_stmt = function(stmt)
        if type(stmt) ~= "table" then return stmt end
        if stmt.tag == "stack_slot" and remove_slots[stmt.name] then
            return nil
        end
        if stmt.tag == "memcpy" and remove_slots[root_stack_slot_name(stmt.dst)] then
            return nil
        end
        if stmt.tag == "while" then
            stmt.cond = rewrite_expr(stmt.cond)
            local old = stmt.body or {}
            local new = {}
            for i = 1, #old do
                local child = rewrite_stmt(old[i])
                if child ~= nil then new[#new + 1] = child end
            end
            stmt.body = new
            return stmt
        elseif stmt.tag == "if" then
            stmt.cond = rewrite_expr(stmt.cond)
            local old_then = stmt.then_body or {}
            local new_then = {}
            for i = 1, #old_then do
                local child = rewrite_stmt(old_then[i])
                if child ~= nil then new_then[#new_then + 1] = child end
            end
            stmt.then_body = new_then
            local old_else = stmt.else_body or {}
            local new_else = {}
            for i = 1, #old_else do
                local child = rewrite_stmt(old_else[i])
                if child ~= nil then new_else[#new_else + 1] = child end
            end
            stmt.else_body = new_else
            return stmt
        elseif stmt.tag == "store" then
            stmt.addr = rewrite_expr(stmt.addr)
            stmt.value = rewrite_expr(stmt.value)
            return stmt
        elseif stmt.tag == "memcpy" or stmt.tag == "memmove" then
            stmt.dst = rewrite_expr(stmt.dst)
            stmt.src = rewrite_expr(stmt.src)
            stmt.len = rewrite_expr(stmt.len)
            return stmt
        elseif stmt.tag == "memset" then
            stmt.dst = rewrite_expr(stmt.dst)
            stmt.byte = rewrite_expr(stmt.byte)
            stmt.len = rewrite_expr(stmt.len)
            return stmt
        elseif stmt.tag == "call" then
            if stmt.addr ~= nil then stmt.addr = rewrite_expr(stmt.addr) end
            local args = stmt.args or {}
            for i = 1, #args do args[i] = rewrite_expr(args[i]) end
            return stmt
        else
            if stmt.init ~= nil then stmt.init = rewrite_expr(stmt.init) end
            if stmt.value ~= nil then stmt.value = rewrite_expr(stmt.value) end
            return stmt
        end
    end

    return rewrite_expr(root)
end

local function build_function(name, params, result_t, body_fn)
    assert(type(name) == "string", "moonlift function name must be a string")
    assert(type(params) == "table", "moonlift function params must be a table")
    assert(type(body_fn) == "function" or is_ir_quote(body_fn), "moonlift function body must be a function or quote_ir")
    assert(result_t == nil or is_type(result_t), "moonlift function result must be a Moonlift type")

    local builder = {
        next_local_id = 0,
        frame = nil,
    }

    local abi_args = {}
    local lowered_params = {}
    for i = 1, #params do
        local p = params[i]
        assert(type(p) == "table" and p.name and p.t, "moonlift function params must come from moonlift.param or type(name)")
        if is_layout_type(p.t) then
            abi_args[i] = arg(i, make_ptr(p.t))
            lowered_params[i] = "ptr"
        else
            abi_args[i] = arg(i, p.t)
            lowered_params[i] = lower_param(p)
        end
    end

    local layout_param_copies = {}

    local function materialize_args()
        local args = {}
        for i = 1, #params do
            local p = params[i]
            if is_layout_type(p.t) then
                local arg_ref = bind_layout_local(abi_args[i], "arg", false)
                args[i] = arg_ref
                if arg_ref.node ~= nil and arg_ref.node.tag == "stack_addr" then
                    layout_param_copies[#layout_param_copies + 1] = {
                        slot_name = arg_ref.node.name,
                        arg_node = abi_args[i].node,
                        arg_index = i,
                    }
                end
            else
                args[i] = abi_args[i]
            end
        end
        return args
    end

    local body_expr
    if result_t ~= nil and is_void_type(result_t) then
        body_expr = with_builder(builder, function()
            local stmts = capture_stmt_block(function()
                local args = materialize_args()
                local out
                if is_ir_quote(body_fn) then
                    out = body_fn:splice(unpack(args, 1, #args))
                else
                    out = run_builder_fn(body_fn, unpack(args, 1, #args))
                end
                if out ~= nil then
                    error("moonlift void function body must not return a value", 2)
                end
            end)
            return expr({
                tag = "block",
                stmts = stmts,
                result = { tag = "u8", value = 0, type = "u8" },
                type = "u8",
            }, M.u8)
        end)
    else
        body_expr = with_builder(builder, function()
            return block(function()
                local args = materialize_args()
                if is_ir_quote(body_fn) then
                    return body_fn:splice(unpack(args, 1, #args))
                end
                return run_builder_fn(body_fn, unpack(args, 1, #args))
            end)
        end)
    end

    if #layout_param_copies > 0 then
        local tracked = analyze_layout_param_copies(body_expr.node, layout_param_copies)
        body_expr = expr(rewrite_layout_param_copies(body_expr.node, tracked), body_expr.t)
    end

    local inferred_result = result_t or body_expr.t
    assert(is_type(inferred_result), "moonlift function body did not produce a typed result")
    if not is_void_type(inferred_result) then
        assert(body_expr.t == inferred_result, "moonlift function body result type does not match declared result")
    end

    local lowered = {
        name = name,
        params = lowered_params,
        result = lower_type_name(inferred_result),
        body = body_expr.node,
    }

    return setmetatable({
        name = name,
        params = params,
        result = inferred_result,
        arity = #params,
        body = body_expr,
        lowered = lowered,
    }, FunctionMT)
end

local function parse_function_spec(name, spec)
    assert(type(spec) == "table", "moonlift function spec must be a table")
    local params = spec.params
    local body = spec.body
    local result_t = spec.result or spec.ret

    if params == nil then
        params = {}
        local n = #spec
        if body == nil and n > 0 and (type(spec[n]) == "function" or is_ir_quote(spec[n])) then
            body = spec[n]
            n = n - 1
        end
        if result_t == nil and n > 0 and is_type(spec[n]) then
            result_t = spec[n]
            n = n - 1
        end
        for i = 1, n do
            params[i] = spec[i]
        end
    end

    if body == nil and (type(spec[#spec]) == "function" or is_ir_quote(spec[#spec])) then
        body = spec[#spec]
    end

    return build_function(name, params, result_t, assert(body, "moonlift function spec.body must be present"))
end

local function func(name)
    assert(type(name) == "string", "moonlift.func name must be a string")
    return setmetatable({ name = name }, FuncStage1MT)
end

local function parse_extern_spec(name, spec)
    assert(type(spec) == "table", "moonlift extern spec must be a table")
    local params = spec.params
    local result_t = spec.result or spec.ret
    local addr = spec.addr
    if params == nil then
        params = {}
        local n = #spec
        if result_t == nil and n > 0 and is_type(spec[n]) then
            result_t = spec[n]
            n = n - 1
        end
        for i = 1, n do
            params[i] = spec[i]
        end
    end
    result_t = result_t or M.void
    local lowered_params = {}
    for i = 1, #params do
        local p = params[i]
        assert(type(p) == "table" and p.name and p.t, "moonlift extern params must come from moonlift.param or type(name)")
        assert(not is_layout_type(p.t), "moonlift extern params do not yet support by-value layout types")
        lowered_params[i] = lower_param(p)
    end
    assert(type(addr) == "number", "moonlift extern requires numeric addr field")
    return setmetatable({
        name = name,
        params = params,
        result = result_t,
        arity = #params,
        addr = addr,
        lowered = {
            name = name,
            params = lowered_params,
            result = lower_type_name(result_t),
            addr = addr,
        },
    }, ExternMT)
end

local function extern(name)
    assert(type(name) == "string", "moonlift.extern name must be a string")
    return setmetatable({ name = name }, ExternStage1MT)
end

local function resolve_import_addr(resolver, symbol)
    if type(resolver) == "function" then
        return symbol_address(resolver(symbol))
    end
    return symbol_address(resolver[symbol])
end

import_module = function(name, resolver)
    if resolver == nil then
        resolver = name
        name = "imports"
    end
    assert(type(name) == "string", "moonlift.import_module name must be a string")
    assert(resolver ~= nil, "moonlift.import_module requires a resolver")
    return setmetatable({ name = name, resolver = resolver }, ImportModuleMT)
end

ImportModuleMT.__tostring = function(self)
    return string.format("moonlift.import_module<%s>", self.name)
end

ImportModuleMT.__index = {
    addr = function(self, symbol)
        assert(type(symbol) == "string", "moonlift import symbol must be a string")
        return resolve_import_addr(self.resolver, symbol)
    end,
    extern = function(self, symbol)
        assert(type(symbol) == "string", "moonlift import symbol must be a string")
        return setmetatable({ module = self, symbol = symbol, name = symbol }, ImportExternStage1MT)
    end,
}

FuncStage1MT.__call = function(self, spec)
    return parse_function_spec(self.name, spec)
end

ExternStage1MT.__call = function(self, spec)
    return parse_extern_spec(self.name, spec)
end

ImportExternStage1MT.__call = function(self, spec)
    spec = spec or {}
    if spec.addr == nil then
        spec.addr = self.module:addr(self.symbol)
    end
    return parse_extern_spec(self.name, spec)
end

local function lower_call_arg(value, param_t)
    if is_layout_type(param_t) then
        local ptr_v, actual_t = layout_ptr_of_value(value, param_t)
        if ptr_v ~= nil then
            assert(actual_t == param_t, "moonlift.invoke layout argument type mismatch")
            return ptr_v.node
        end
        if is_agg_init(value) and value._layout == param_t then
            return bind_layout_local(value, "call", false).node
        end
        error(("moonlift.invoke expected a %s value or pointer source"):format(param_t.name), 3)
    end
    return as_expr(value, param_t).node
end

invoke = function(callee, ...)
    local argc = select("#", ...)
    local args = { n = argc, ... }
    local builder = current_builder
    if builder == nil then
        error("moonlift.invoke may only be used inside Moonlift function bodies", 2)
    end

    local target
    local result_t
    local param_count
    if is_function(callee) then
        local compiled = callee.__compiled
        if compiled == nil then
            compiled = compile_function(callee)
            callee.__compiled = compiled
            callee.__code_addr = backend.addr(compiled.handle)
        end
        target = {
            kind = "indirect",
            addr = { tag = "ptr", value = callee.__code_addr, type = "ptr" },
            params = callee.lowered.params,
            result = lower_type_name(callee.result),
        }
        result_t = callee.result
        param_count = #callee.params
    elseif type(callee) == "table" and getmetatable(callee) == ExternMT then
        target = {
            kind = "indirect",
            addr = { tag = "ptr", value = callee.addr, type = "ptr" },
            params = callee.lowered.params,
            result = lower_type_name(callee.result),
        }
        result_t = callee.result
        param_count = #callee.params
    else
        error("moonlift.invoke expects a Moonlift function or extern", 2)
    end

    assert(argc == param_count, ("moonlift.invoke expected %d args, got %d"):format(param_count, argc))
    local lowered_args = {}
    if is_function(callee) then
        for i = 1, argc do
            lowered_args[i] = lower_call_arg(args[i], callee.params[i].t)
        end
    else
        for i = 1, argc do
            lowered_args[i] = as_expr(args[i], callee.params[i].t).node
        end
    end

    local node = {
        tag = "call",
        callee_kind = target.kind,
        name = target.name,
        addr = target.addr,
        params = target.params,
        result = target.result,
        args = lowered_args,
        type = lower_type_name(result_t),
    }
    if is_void_type(result_t) then
        emit_stmt(node)
        return nil
    end
    return expr(node, result_t)
end

local function module(list)
    if type(list) == "table" and list.funcs ~= nil then
        list = list.funcs
    end
    assert(type(list) == "table", "moonlift.module expects a table of functions")
    local out = {}
    for i = 1, #list do
        local f = list[i]
        assert(is_function(f), "moonlift.module entries must be Moonlift functions")
        out[i] = f
    end
    return setmetatable({ funcs = out }, ModuleMT)
end

CompiledFnMT.__index = {
    call = function(self, ...)
        return self(...)
    end,
}

CompiledFnMT.__tostring = function(self)
    return string.format("moonlift.compiled<%s/%d>#%d", self.name, self.arity, self.handle)
end

CompiledFnMT.__call = function(self, ...)
    local argc = select("#", ...)
    if argc ~= self.arity then
        error(("compiled function '%s' expects %d arguments, got %d"):format(self.name, self.arity, argc), 2)
    end
    local fast = rawget(self, "__fast_call")
    if fast ~= nil then
        return fast(...)
    end
    if argc == 0 then
        return backend.call0(self.handle)
    elseif argc == 1 then
        return backend.call1(self.handle, ...)
    elseif argc == 2 then
        return backend.call2(self.handle, ...)
    elseif argc == 3 then
        return backend.call3(self.handle, ...)
    elseif argc == 4 then
        return backend.call4(self.handle, ...)
    end
    return backend.call(self.handle, ...)
end

local function wrap_compiled_handle(name, arity, handle, param_types, result_t)
    local key = tostring(handle) .. ":" .. tostring(arity)
    local cached = compiled_cache[key]
    if cached ~= nil then
        return cached
    end
    local code_addr = backend.addr(handle)
    local wrapped = setmetatable({
        name = name or "<anon>",
        arity = arity,
        handle = handle,
        __fast_call = make_fast_host_call(code_addr, arity, param_types, result_t),
    }, CompiledFnMT)
    compiled_cache[key] = wrapped
    return wrapped
end

local function function_lowered_params(f)
    if f.lowered ~= nil and f.lowered.params ~= nil then
        return f.lowered.params
    end
    local out = {}
    for i = 1, #f.params do
        out[i] = lower_type_name(f.params[i].t)
    end
    return out
end

compile_function = function(f)
    local handle, err
    if rawget(f, "__native_source") ~= nil and type(backend.compile_source_code) == "function" then
        handle, err = backend.compile_source_code(f.__native_source)
    else
        handle, err = backend.compile(f.lowered)
    end
    assert(
        type(handle) == "number" and handle > 0,
        err or (("moonlift failed to compile function '%s'"):format(f.name))
    )
    return wrap_compiled_handle(f.name, #f.params, handle, function_lowered_params(f), f.result)
end

local function lowered_has_direct_call(node)
    if type(node) ~= "table" then return false end
    if node.tag == "call" and node.callee_kind == "direct" then
        return true
    end
    for _, v in pairs(node) do
        if type(v) == "table" then
            if v.tag ~= nil then
                if lowered_has_direct_call(v) then return true end
            else
                for i = 1, #v do
                    if lowered_has_direct_call(v[i]) then return true end
                end
            end
        end
    end
    return false
end

local function module_needs_direct_compile(mod)
    if rawget(mod, "__needs_direct_compile") then return true end
    if rawget(mod, "__native_source") ~= nil then return true end
    for i = 1, #mod.funcs do
        local lowered = mod.funcs[i].lowered
        if lowered ~= nil and lowered_has_direct_call(lowered.body) then
            return true
        end
    end
    return false
end

local function compile_module(mod)
    local cached = rawget(mod, "__compiled")
    if cached ~= nil then return cached end

    local compiled = {}
    if rawget(mod, "__native_source") ~= nil and type(backend.compile_source_module) == "function" then
        local handles, err = backend.compile_source_module(mod.__native_source)
        assert(type(handles) == "table", err or "moonlift failed to compile native source module")
        for i = 1, #mod.funcs do
            local f = mod.funcs[i]
            local cf = wrap_compiled_handle(f.name, #f.params, handles[i], function_lowered_params(f), f.result)
            compiled[i] = cf
            compiled[f.name] = cf
            f.__compiled = cf
            f.__code_addr = backend.addr(cf.handle)
        end
    elseif module_needs_direct_compile(mod) then
        local lowered = {}
        for i = 1, #mod.funcs do
            lowered[i] = mod.funcs[i].lowered
        end
        local handles, err = backend.compile_module(lowered)
        assert(type(handles) == "table", err or "moonlift failed to compile module")
        for i = 1, #mod.funcs do
            local f = mod.funcs[i]
            local cf = wrap_compiled_handle(f.name, #f.params, handles[i], function_lowered_params(f), f.result)
            compiled[i] = cf
            compiled[f.name] = cf
            f.__compiled = cf
            f.__code_addr = backend.addr(cf.handle)
        end
    else
        for i = 1, #mod.funcs do
            local f = mod.funcs[i]
            local cf = compile_function(f)
            compiled[i] = cf
            compiled[f.name] = cf
        end
    end

    mod.__compiled = compiled
    return compiled
end

FunctionMT.__tostring = function(self)
    return string.format("moonlift.func<%s/%d>", self.name, #self.params)
end

FunctionMT.__call = function(self, ...)
    if current_builder ~= nil then
        return invoke(self, ...)
    end
    local argc = select("#", ...)
    if argc ~= 0 then
        error(("moonlift function '%s' compile call expects 0 args outside builder, got %d"):format(self.name, argc), 2)
    end
    local owner_module = rawget(self, "__owner_module")
    if owner_module ~= nil and module_needs_direct_compile(owner_module) then
        return compile_module(owner_module)[self.name]
    end
    if self.lowered ~= nil and lowered_has_direct_call(self.lowered.body) then
        local temp_module = setmetatable({ funcs = { self }, __needs_direct_compile = true }, ModuleMT)
        self.__owner_module = temp_module
        return compile_module(temp_module)[self.name]
    end
    return compile_function(self)
end

ExternMT.__tostring = function(self)
    return string.format("moonlift.extern<%s/%d>", self.name, #self.params)
end

ExternMT.__call = function(self, ...)
    return invoke(self, ...)
end

ModuleMT.__tostring = function(self)
    return string.format("moonlift.module<%d functions>", #self.funcs)
end

ModuleMT.__call = function(self)
    return compile_module(self)
end

local function alias_lookup(base_env, k)
    if k == "ml" then
        return M
    elseif M ~= nil and M[k] ~= nil then
        return M[k]
    elseif M ~= nil and M.types ~= nil and M.types[k] ~= nil then
        return M.types[k]
    end
    return base_env[k]
end

local function env(base_env)
    if base_env == nil then
        if type(getfenv) == "function" then
            base_env = getfenv(2)
        else
            base_env = _G
        end
    end
    assert(type(base_env) == "table", "moonlift.env expects an environment table")
    return setmetatable({}, {
        __index = function(_, k)
            return alias_lookup(base_env, k)
        end,
        __newindex = base_env,
    })
end

local function use(base_env)
    if base_env == nil then
        if type(getfenv) == "function" then
            base_env = getfenv(2)
        else
            base_env = _G
        end
    end
    assert(type(base_env) == "table", "moonlift.use expects an environment table")
    local keys = {
        "ml",
        "code",
        "expr",
        "func",
        "module",
        "asdl",
        "extern",
        "import_module",
        "invoke",
        "compile",
        "call",
        "call0",
        "call1",
        "call2",
        "call3",
        "call4",
        "stats",
        "parse",
        "load",
        "store",
        "copy",
        "memcpy",
        "memmove",
        "memset",
        "memcmp",
        "let",
        "var",
        "block",
        "if_",
        "switch_",
        "while_",
        "break_",
        "continue_",
        "quote",
        "q",
        "quote_ir",
        "quote_expr",
        "quote_block",
        "hole",
        "cast",
        "trunc",
        "zext",
        "sext",
        "bitcast",
        "void",
        "bool",
        "ptr",
        "struct_",
        "union",
        "tagged_union",
        "array",
        "slice",
        "enum",
        "i8",
        "i16",
        "i32",
        "i64",
        "u8",
        "u16",
        "u32",
        "u64",
        "byte",
        "isize",
        "usize",
        "f32",
        "f64",
    }
    for i = 1, #keys do
        local k = keys[i]
        base_env[k] = alias_lookup(base_env, k)
    end
    return base_env
end

local function compile(x)
    if is_function(x) then
        return compile_function(x)
    end
    if type(x) == "table" and getmetatable(x) == ModuleMT then
        return compile_module(x)
    end
    if type(x) == "table" then
        local params = x.params or {}
        local handle, err = backend.compile(x)
        assert(type(handle) == "number" and handle > 0, err or "moonlift failed to compile lowered table")
        return wrap_compiled_handle(x.name, #params, handle, params, nil)
    end
    error("moonlift.compile expects a Moonlift function, module, or lowered table", 2)
end

local types = {
    void = new_type { name = "void", family = "void" },
    bool = new_type { name = "bool", const_tag = "bool", family = "bool" },
    i8 = new_type { name = "i8", const_tag = "i8", family = "int", signed = true, bits = 8 },
    i16 = new_type { name = "i16", const_tag = "i16", family = "int", signed = true, bits = 16 },
    i32 = new_type { name = "i32", const_tag = "i32", family = "int", signed = true, bits = 32 },
    i64 = new_type { name = "i64", const_tag = "i64", family = "int", signed = true, bits = 64 },
    u8 = new_type { name = "u8", const_tag = "u8", family = "int", signed = false, bits = 8 },
    u16 = new_type { name = "u16", const_tag = "u16", family = "int", signed = false, bits = 16 },
    u32 = new_type { name = "u32", const_tag = "u32", family = "int", signed = false, bits = 32 },
    u64 = new_type { name = "u64", const_tag = "u64", family = "int", signed = false, bits = 64 },
    f32 = new_type { name = "f32", const_tag = "f32", family = "float", bits = 32 },
    f64 = new_type { name = "f64", const_tag = "f64", family = "float", bits = 64 },
}
types.byte = types.u8
types.isize = types.i64
types.usize = types.u64

local StructMT = {}
local ArrayTypeMT = {}
local UnionMT = {}
local slice_cache = {}
local make_enum

local function align_up(n, a)
    if a == nil or a <= 1 then return n end
    local r = n % a
    if r == 0 then return n end
    return n + (a - r)
end

type_size = function(t)
    if t.size then return t.size end
    if t.bits then return math.ceil(t.bits / 8) end
    if t.family == "bool" then return 1 end
    error("moonlift type has no known size: " .. tostring(t.name), 2)
end

type_align = function(t)
    return t.align or type_size(t)
end

local function make_struct(name, fields)
    assert(type(name) == "string", "moonlift.struct name must be a string")
    assert(type(fields) == "table", "moonlift.struct fields must be a table")

    local ordered = {}
    local lookup = {}
    local offset = 0
    local max_align = 1

    for i = 1, #fields do
        local field = fields[i]
        local field_name = assert(field[1], "struct field missing name")
        local field_type = assert(field[2], "struct field missing type")
        assert(type(field_name) == "string", "struct field name must be a string")
        assert(lookup[field_name] == nil, "duplicate struct field: " .. field_name)

        local fa = type_align(field_type)
        if fa > max_align then max_align = fa end
        offset = align_up(offset, fa)

        local entry = {
            name = field_name,
            type = field_type,
            offset = offset,
            size = type_size(field_type),
        }
        ordered[#ordered + 1] = entry
        lookup[field_name] = entry
        offset = offset + entry.size
    end

    local S = setmetatable({
        name = name,
        layout_kind = "struct",
        fields = ordered,
        field_lookup = lookup,
        method_lookup = {},
        size = align_up(offset, max_align),
        align = max_align,
    }, StructMT)
    return S
end

local AggInitMT = {}

local function agg_init(layout, values)
    return setmetatable({ _layout = layout, _values = values }, AggInitMT)
end

is_agg_init = function(x)
    return type(x) == "table" and getmetatable(x) == AggInitMT
end

is_layout_view = function(x)
    if type(x) ~= "table" then return false end
    local mt = getmetatable(x)
    return (mt == StructViewMT or mt == ArrayViewMT) and rawget(x, "_addr") ~= nil
end

StructMT.__tostring = function(self)
    return string.format("moonlift.struct<%s size=%d align=%d>", self.name, self.size, self.align)
end

StructMT.__call = function(self, values)
    if type(values) == "string" then
        return param(values, self)
    end
    assert(type(values) == "table", "moonlift struct/union literal expects a table")
    return agg_init(self, values)
end

local function define_struct_method(struct_t, method_name, spec)
    assert(type(method_name) == "string", "moonlift struct method name must be a string")
    assert(type(spec) == "table", "moonlift struct method spec must be a table")
    local params = spec.params
    local body = spec.body
    local result_t = spec.result or spec.ret

    if params == nil then
        params = {}
        local n = #spec
        if body == nil and n > 0 and (type(spec[n]) == "function" or is_ir_quote(spec[n])) then
            body = spec[n]
            n = n - 1
        end
        if result_t == nil and n > 0 and is_type(spec[n]) then
            result_t = spec[n]
            n = n - 1
        end
        for i = 1, n do
            params[i] = spec[i]
        end
    end

    local full_params = { make_ptr(struct_t)("self") }
    for i = 1, #params do
        full_params[#full_params + 1] = params[i]
    end

    local fn = build_function(struct_t.name .. "_" .. method_name, full_params, result_t, assert(body, "moonlift struct method body must be present"))
    rawget(struct_t, "method_lookup")[method_name] = fn
    return fn
end

StructMT.__index = function(self, key)
    if key == "name" or key == "layout_kind" or key == "fields" or key == "field_lookup"
       or key == "method_lookup" or key == "size" or key == "align" then
        return rawget(self, key)
    end
    if key == "method" then
        return function(struct_t, method_name, spec)
            if spec ~= nil then
                return define_struct_method(struct_t, method_name, spec)
            end
            return function(inner_spec)
                return define_struct_method(struct_t, method_name, inner_spec)
            end
        end
    end
    local f = rawget(self, "field_lookup")
    if f and f[key] ~= nil then return f[key] end
    local m = rawget(self, "method_lookup")
    if m and m[key] ~= nil then return m[key] end
    return nil
end

local function make_union(name, fields)
    assert(type(name) == "string", "moonlift.union name must be a string")
    assert(type(fields) == "table", "moonlift.union fields must be a table")

    local ordered = {}
    local lookup = {}
    local max_size = 0
    local max_align = 1

    for i = 1, #fields do
        local field = fields[i]
        local field_name = assert(field[1], "union field missing name")
        local field_type = assert(field[2], "union field missing type")
        assert(type(field_name) == "string", "union field name must be a string")
        assert(lookup[field_name] == nil, "duplicate union field: " .. field_name)
        local fa = type_align(field_type)
        local fs = type_size(field_type)
        if fa > max_align then max_align = fa end
        if fs > max_size then max_size = fs end
        local entry = {
            name = field_name,
            type = field_type,
            offset = 0,
            size = fs,
        }
        ordered[#ordered + 1] = entry
        lookup[field_name] = entry
    end

    return setmetatable({
        name = name,
        layout_kind = "struct",
        union_kind = true,
        fields = ordered,
        field_lookup = lookup,
        method_lookup = {},
        size = align_up(max_size, max_align),
        align = max_align,
    }, StructMT)
end

local function make_tagged_union(name, spec)
    assert(type(name) == "string", "moonlift.tagged_union name must be a string")
    assert(type(spec) == "table", "moonlift.tagged_union spec must be a table")
    local base_t = spec.base or types.u8
    local variants = assert(spec.variants, "moonlift.tagged_union requires variants")
    local ordered_variants = ordered_named_entries(variants, "tagged_union variants")
    local tag_items = {}
    local payload_fields = {}
    for i = 1, #ordered_variants do
        local variant_name = ordered_variants[i][1]
        local fields = ordered_variants[i][2]
        tag_items[variant_name] = i - 1
        local payload_t
        if type(fields) == "table" and fields.layout_kind then
            payload_t = fields
        else
            local field_list = {}
            if #fields > 0 then
                for j = 1, #fields do field_list[j] = fields[j] end
            else
                for fk, fv in pairs(fields) do
                    field_list[#field_list + 1] = { fk, fv }
                end
                table.sort(field_list, function(a, b) return a[1] < b[1] end)
            end
            payload_t = make_struct(name .. "_" .. variant_name, field_list)
        end
        payload_fields[#payload_fields + 1] = { variant_name, payload_t }
    end
    local Tag = make_enum(name .. "Tag", base_t, tag_items)
    local Payload = make_union(name .. "Payload", payload_fields)
    local Outer = make_struct(name, {
        { "tag", Tag },
        { "payload", Payload },
    })
    Outer.Tag = Tag
    Outer.Payload = Payload
    Outer.variants = variants
    for i = 1, #ordered_variants do
        local variant_name = ordered_variants[i][1]
        Outer[variant_name] = Tag[variant_name]
    end
    return Outer
end

local function make_array(elem_t, count)
    assert(type(count) == "number" and count >= 0, "moonlift.array count must be a non-negative number")
    return setmetatable({
        name = ("array(%s,%d)"):format(elem_t.name or "?", count),
        layout_kind = "array",
        elem = elem_t,
        count = count,
        size = type_size(elem_t) * count,
        align = type_align(elem_t),
    }, ArrayTypeMT)
end

make_enum = function(name, base_t, items)
    assert(type(name) == "string", "moonlift.enum name must be a string")
    assert(is_type(base_t) and is_integer_type(base_t) and not is_bool_type(base_t) and not is_void_type(base_t),
        "moonlift.enum base type must be an integer-like Moonlift type")
    assert(type(items) == "table", "moonlift.enum items must be a table")
    local E = new_type {
        name = name,
        lowering_name = lower_type_name(base_t),
        const_tag = base_t.const_tag,
        family = "enum",
        base = base_t,
        bits = base_t.bits,
        signed = base_t.signed,
        size = type_size(base_t),
        align = type_align(base_t),
    }
    for k, v in pairs(items) do
        assert(type(k) == "string", "moonlift.enum keys must be strings")
        assert(type(v) == "number", "moonlift.enum values must be numbers")
        E[k] = expr({ tag = base_t.const_tag, value = v, type = lower_type_name(base_t) }, E)
    end
    return E
end

ArrayTypeMT.__tostring = function(self)
    return string.format("moonlift.array<%s x %d>", self.elem.name or "?", self.count)
end

ArrayTypeMT.__call = function(self, values)
    if type(values) == "string" then
        return param(values, self)
    end
    assert(type(values) == "table", "moonlift array literal expects a table")
    return agg_init(self, values)
end

UnionMT.__tostring = function(self)
    return string.format("moonlift.union<%s size=%d align=%d>", self.name, self.size, self.align)
end

local ptr_cache = {}

make_ptr = function(elem_t)
    local cached = ptr_cache[elem_t]
    if cached then return cached end
    local P = setmetatable({
        name = "ptr",
        const_tag = "ptr",
        family = "ptr",
        elem = elem_t,
        bits = 64,
        size = 8,
        align = 8,
    }, PtrTypeMT)
    ptr_cache[elem_t] = P
    return P
end

PtrTypeMT.__tostring = function(self)
    local en = self.elem and (self.elem.name or tostring(self.elem)) or "void"
    return string.format("moonlift.ptr<%s>", en)
end

PtrTypeMT.__call = function(self, value)
    if type(value) == "string" then
        return param(value, self)
    end
    if type(value) == "number" then
        return expr({ tag = "ptr", value = value, type = "ptr" }, self)
    end
    error("ptr(...) expects a constant address or parameter name", 2)
end

local function make_slice(elem_t)
    assert(elem_t ~= nil, "moonlift.slice requires an element type")
    local cached = slice_cache[elem_t]
    if cached ~= nil then
        return cached
    end
    local S = make_struct(("slice(%s)"):format(elem_t.name or "?"), {
        { "ptr", make_ptr(elem_t) },
        { "len", types.usize },
    })
    S.slice_elem = elem_t
    slice_cache[elem_t] = S
    return S
end

local function is_ptr_type(t)
    return is_type(t) and (t.family == "ptr" or getmetatable(t) == PtrTypeMT)
end

is_struct_type = function(t)
    return type(t) == "table" and t.layout_kind == "struct"
end

is_array_type = function(t)
    return type(t) == "table" and t.layout_kind == "array"
end

is_layout_type = function(t)
    return is_struct_type(t) or is_array_type(t)
end

local function is_struct_scalar_proxy(x)
    return type(x) == "table" and getmetatable(x) == StructScalarVarMT
end

can_scalarize_struct_init = function(init)
    if not is_agg_init(init) then return nil end
    local T = init._layout
    if not is_struct_type(T) or T.union_kind then return nil end
    local values = init._values
    for i = 1, #T.fields do
        local f = T.fields[i]
        if not is_type(f.type) or values[f.name] == nil then
            return nil
        end
    end
    return T, values
end

local function assign_struct_scalar_proxy(self, value)
    local T = rawget(self, "_struct")
    local fields = rawget(self, "_fields")
    if is_agg_init(value) then
        assert(value._layout == T, "moonlift aggregate literal type mismatch")
        value = value._values
    end
    for i = 1, #T.fields do
        local f = T.fields[i]
        local ref = fields[f.name]
        local src = value[f.name]
        if src ~= nil then
            ref:set(src)
        end
    end
    return self
end

local function make_bound_struct_method(receiver, struct_t, method_fn, materialize_self)
    return function(_, ...)
        local self_value = materialize_self(receiver, struct_t)
        local out = invoke(method_fn, self_value, ...)
        return out
    end
end

StructScalarVarMT.__index = function(self, key)
    if key == "_struct" or key == "_fields" then return rawget(self, key) end
    if key == "set" then
        return function(this, value)
            return assign_struct_scalar_proxy(this, value)
        end
    end
    local ref = rawget(self, "_fields")[key]
    if ref ~= nil then return ref end
    local s = rawget(self, "_struct")
    local method = s.method_lookup and s.method_lookup[key]
    if method ~= nil then
        return function(_, ...)
            local ptr_ref = materialize_struct_scalar_proxy(self, "method")
            local out = invoke(method, ptr_ref, ...)
            local loaded = load(s, ptr_ref)
            assign_struct_scalar_proxy(self, loaded)
            return out
        end
    end
    error(("struct '%s' has no field '%s'"):format(s.name, tostring(key)), 2)
end

StructScalarVarMT.__newindex = function(self, key, value)
    local ref = rawget(self, "_fields")[key]
    if ref ~= nil then
        ref:set(value)
        return
    end
    rawset(self, key, value)
end

materialize_struct_scalar_proxy = function(x, prefix)
    local T = rawget(x, "_struct")
    local ptr_ref = alloc_stack_slot(T, prefix or "spill")
    local fields = rawget(x, "_fields")
    for i = 1, #T.fields do
        local f = T.fields[i]
        make_field_store(ptr_ref, f, fields[f.name])
    end
    return ptr_ref
end

layout_type_of_value = function(x)
    if is_agg_init(x) then
        return x._layout
    end
    if is_layout_view(x) then
        return rawget(x, "_struct") or rawget(x, "_array")
    end
    if is_struct_scalar_proxy(x) then
        return rawget(x, "_struct")
    end
    if is_expr(x) and is_ptr_type(x.t) and is_layout_type(x.t.elem) then
        return x.t.elem
    end
    return nil
end

layout_ptr_of_value = function(x, want_t)
    local t = want_t or layout_type_of_value(x)
    if t == nil then
        return nil, nil
    end
    if is_layout_view(x) then
        return expr(rawget(x, "_addr"), make_ptr(t)), t
    end
    if is_struct_scalar_proxy(x) then
        return materialize_struct_scalar_proxy(x, "proxy"), t
    end
    if is_expr(x) and is_ptr_type(x.t) and x.t.elem == t then
        return x, t
    end
    return nil, t
end

local function align_shift(n)
    local shift = 0
    local v = 1
    while v < n do
        v = v * 2
        shift = shift + 1
    end
    return shift
end

alloc_stack_slot = function(T, prefix, methods)
    local slot_name, frame = fresh_local_name(prefix)
    frame.stmts[#frame.stmts + 1] = {
        tag = "stack_slot",
        name = slot_name,
        size = type_size(T),
        align = type_align(T),
        align_shift = align_shift(type_align(T)),
    }
    return expr({ tag = "stack_addr", name = slot_name, type = "ptr" }, make_ptr(T), methods)
end

make_field_load = function(base_expr, field_entry)
    local ft = field_entry.type
    local offset_val = { tag = "i64", value = field_entry.offset, type = "i64" }
    local addr = { tag = "add", lhs = base_expr.node, rhs = offset_val, type = "ptr" }

    if is_layout_type(ft) then
        return make_struct_view(addr, ft)
    end

    local scalar_t
    if is_type(ft) then
        scalar_t = ft
    else
        error("moonlift field type is not a scalar type: " .. tostring(ft.name), 2)
    end
    return expr({ tag = "load", addr = addr, type = lower_type_name(scalar_t) }, scalar_t)
end

make_field_store = function(base_expr, field_entry, value)
    local ft = field_entry.type
    local offset_val = { tag = "i64", value = field_entry.offset, type = "i64" }
    local addr = { tag = "add", lhs = base_expr.node, rhs = offset_val, type = "ptr" }
    if is_layout_type(ft) then
        return store(ft, expr(addr, make_ptr(ft)), value)
    end
    local scalar_t
    if is_type(ft) then
        scalar_t = ft
    else
        error("moonlift field type is not a scalar type: " .. tostring(ft.name), 2)
    end
    value = as_expr(value, scalar_t)
    local frame = current_frame()
    if frame == nil then
        error("moonlift store outside of a block context", 2)
    end
    frame.stmts[#frame.stmts + 1] = {
        tag = "store",
        type = lower_type_name(scalar_t),
        addr = addr,
        value = value.node,
    }
end

make_array_elem_load = function(base_expr, elem_t, index_expr)
    index_expr = as_expr(index_expr)
    local elem_size = type_size(elem_t)
    local scaled = { tag = "mul", lhs = index_expr.node, rhs = { tag = "i64", value = elem_size, type = "i64" }, type = "i64" }
    local addr = { tag = "add", lhs = base_expr.node, rhs = scaled, type = "ptr" }

    if is_layout_type(elem_t) then
        return make_struct_view(addr, elem_t)
    end

    local scalar_t = elem_t
    return expr({ tag = "load", addr = addr, type = lower_type_name(scalar_t) }, scalar_t)
end

make_array_elem_store = function(base_expr, elem_t, index_expr, value)
    index_expr = as_expr(index_expr)
    local elem_size = type_size(elem_t)
    local scaled = { tag = "mul", lhs = index_expr.node, rhs = { tag = "i64", value = elem_size, type = "i64" }, type = "i64" }
    local addr = { tag = "add", lhs = base_expr.node, rhs = scaled, type = "ptr" }
    if is_layout_type(elem_t) then
        return store(elem_t, expr(addr, make_ptr(elem_t)), value)
    end
    value = as_expr(value, elem_t)
    local frame = current_frame()
    if frame == nil then
        error("moonlift store outside of a block context", 2)
    end
    frame.stmts[#frame.stmts + 1] = {
        tag = "store",
        type = lower_type_name(elem_t),
        addr = addr,
        value = value.node,
    }
end

StructViewMT = {}

function make_struct_view(addr_node, struct_t)
    return setmetatable({
        _addr = addr_node,
        _struct = struct_t,
    }, StructViewMT)
end

StructViewMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if key == "_addr" or key == "_struct" then return rawget(self, key) end
    local s = rawget(self, "_struct")
    local f = s.field_lookup[key]
    if f ~= nil then
        local base = expr(rawget(self, "_addr"), make_ptr(s))
        return make_field_load(base, f)
    end
    local method = s.method_lookup and s.method_lookup[key]
    if method ~= nil then
        return make_bound_struct_method(self, s, method, function(view, struct_t)
            return expr(rawget(view, "_addr"), make_ptr(struct_t))
        end)
    end
    error(("struct '%s' has no field '%s'"):format(s.name, key), 2)
end

StructViewMT.__newindex = function(self, key, value)
    if key == "_addr" or key == "_struct" then rawset(self, key, value); return end
    local s = rawget(self, "_struct")
    local f = s.field_lookup[key]
    if f == nil then
        error(("struct '%s' has no field '%s'"):format(s.name, key), 2)
    end
    local base = expr(rawget(self, "_addr"), make_ptr(s))
    make_field_store(base, f, value)
end

ArrayViewMT = {}

local function make_array_view(addr_node, array_t)
    return setmetatable({
        _addr = addr_node,
        _array = array_t,
    }, ArrayViewMT)
end

ArrayViewMT.__index = function(self, key)
    if type(key) == "string" then
        if key == "_addr" or key == "_array" then return rawget(self, key) end
        if key == "count" then return rawget(self, "_array").count end
        if key == "size" then return rawget(self, "_array").size end
        return nil
    end
    local a = rawget(self, "_array")
    local base = expr(rawget(self, "_addr"), make_ptr(a.elem))
    return make_array_elem_load(base, a.elem, key)
end

ArrayViewMT.__newindex = function(self, key, value)
    if type(key) == "string" then
        rawset(self, key, value)
        return
    end
    local a = rawget(self, "_array")
    local base = expr(rawget(self, "_addr"), make_ptr(a.elem))
    make_array_elem_store(base, a.elem, key, value)
end

local orig_expr_index = ExprMT.__index
ExprMT.__index = function(self, key)
    if is_ptr_type(self.t) and self.t.elem ~= nil then
        local elem = self.t.elem
        if is_struct_type(elem) and type(key) == "string" then
            local f = elem.field_lookup[key]
            if f ~= nil then
                return make_field_load(self, f)
            end
            local method = elem.method_lookup and elem.method_lookup[key]
            if method ~= nil then
                return make_bound_struct_method(self, elem, method, function(receiver)
                    return receiver
                end)
            end
        end
        if is_array_type(elem) then
            if key == "count" then return elem.count end
            if key == "size" then return elem.size end
        end
        if type(key) == "number" or is_expr(key) then
            return make_array_elem_load(self, elem, key)
        end
    end
    if type(orig_expr_index) == "function" then
        return orig_expr_index(self, key)
    elseif type(orig_expr_index) == "table" then
        return orig_expr_index[key]
    end
    return nil
end

local orig_expr_newindex = ExprMT.__newindex
ExprMT.__newindex = function(self, key, value)
    if is_ptr_type(self.t) and self.t.elem ~= nil then
        local elem = self.t.elem
        if is_struct_type(elem) and type(key) == "string" then
            local f = elem.field_lookup[key]
            if f ~= nil then
                make_field_store(self, f, value)
                return
            end
        end
        if type(key) == "number" or is_expr(key) then
            make_array_elem_store(self, elem, key, value)
            return
        end
    end
    if orig_expr_newindex then
        orig_expr_newindex(self, key, value)
    else
        rawset(self, key, value)
    end
end

local function as_byte_ptr(x)
    return cast(make_ptr(types.byte), as_expr(x))
end

load = function(T, p)
    assert(T ~= nil, "moonlift.load requires a type")
    local ptr_t = make_ptr(T)
    local ptr_v = as_expr(p, ptr_t)
    if is_struct_type(T) then
        return make_struct_view(ptr_v.node, T)
    elseif is_array_type(T) then
        return make_array_view(ptr_v.node, T)
    else
        return expr({ tag = "load", addr = ptr_v.node, type = lower_type_name(T) }, T)
    end
end

memcpy = function(dst, src, len)
    emit_stmt {
        tag = "memcpy",
        dst = as_byte_ptr(dst).node,
        src = as_byte_ptr(src).node,
        len = as_expr(len, types.usize).node,
    }
    return nil
end

memmove = function(dst, src, len)
    emit_stmt {
        tag = "memmove",
        dst = as_byte_ptr(dst).node,
        src = as_byte_ptr(src).node,
        len = as_expr(len, types.usize).node,
    }
    return nil
end

memset = function(dst, byte_value, len)
    emit_stmt {
        tag = "memset",
        dst = as_byte_ptr(dst).node,
        byte = as_expr(byte_value, types.byte).node,
        len = as_expr(len, types.usize).node,
    }
    return nil
end

memcmp = function(a, b, len)
    return expr({
        tag = "memcmp",
        a = as_byte_ptr(a).node,
        b = as_byte_ptr(b).node,
        len = as_expr(len, types.usize).node,
        type = lower_type_name(types.i32),
    }, types.i32)
end

copy = function(T, dst, src)
    assert(T ~= nil, "moonlift.copy requires a type")
    if is_struct_type(T) or is_array_type(T) then
        if is_agg_init(src) or (type(src) == "table" and not is_expr(src) and not is_layout_view(src)) then
            return store_aggregate(T, as_expr(dst, make_ptr(T)), src)
        end
        memcpy(as_byte_ptr(as_expr(dst, make_ptr(T))), as_byte_ptr(as_expr(src, make_ptr(T))), types.usize(type_size(T)))
        return nil
    end
    local dst_ptr = as_expr(dst, make_ptr(T))
    local value
    if is_expr(src) then
        if is_ptr_type(src.t) then
            value = load(T, src)
        else
            value = as_expr(src, T)
        end
    else
        value = as_expr(src, T)
    end
    emit_stmt({ tag = "store", type = lower_type_name(T), addr = dst_ptr.node, value = value.node })
    return nil
end

store_aggregate = function(T, dst_ptr_expr, value)
    if is_agg_init(value) then
        assert(value._layout == T, "moonlift aggregate literal type mismatch")
        value = value._values
    end
    if is_layout_view(value) then
        local src_addr = expr(rawget(value, "_addr"), make_ptr(T))
        return copy(T, dst_ptr_expr, src_addr)
    elseif is_expr(value) and is_ptr_type(value.t) and value.t.elem == T then
        return copy(T, dst_ptr_expr, value)
    elseif type(value) == "table" and not is_expr(value) then
        if is_struct_type(T) then
            local base = as_expr(dst_ptr_expr, make_ptr(T))
            for i = 1, #T.fields do
                local f = T.fields[i]
                local v = value[f.name]
                if v ~= nil then
                    make_field_store(base, f, v)
                end
            end
            return nil
        elseif is_array_type(T) then
            local base = bitcast(make_ptr(T.elem), as_expr(dst_ptr_expr, make_ptr(T)))
            for i = 1, T.count do
                local v = value[i]
                if v ~= nil then
                    make_array_elem_store(base, T.elem, i - 1, v)
                end
            end
            return nil
        end
    end
    error("moonlift.store aggregate expects a pointer/view source or aggregate literal table", 2)
end

store = function(T, dst, value)
    assert(T ~= nil, "moonlift.store requires a type")
    if is_struct_type(T) or is_array_type(T) then
        local dst_ptr = as_expr(dst, make_ptr(T))
        return store_aggregate(T, dst_ptr, value)
    end
    return copy(T, dst, value)
end

local source_frontend = require("moonlift.source_frontend") {
    backend = backend,
    new_type = new_type,
    types = types,
    is_expr = is_expr,
    is_agg_init = is_agg_init,
    is_layout_view = is_layout_view,
    StructScalarVarMT = StructScalarVarMT,
    make_ptr = make_ptr,
    make_array = make_array,
    make_slice = make_slice,
    make_struct = make_struct,
    make_union = make_union,
    make_tagged_union = make_tagged_union,
    make_enum = make_enum,
    build_function = build_function,
    bind_let = bind_let,
    bind_var = bind_var,
    as_expr = as_expr,
    expr = expr,
    capture_stmt_block = capture_stmt_block,
    emit_stmt = emit_stmt,
    lower_call_arg = lower_call_arg,
    lower_param = lower_param,
    lower_type_name = lower_type_name,
    is_layout_type = is_layout_type,
    is_void_type = is_void_type,
    type_size = type_size,
    type_align = type_align,
    layout_type_of_value = layout_type_of_value,
    layout_ptr_of_value = layout_ptr_of_value,
    hole = hole,
    cast = cast,
    trunc = trunc,
    zext = zext,
    sext = sext,
    bitcast = bitcast,
    load = load,
    store = store,
    memcpy = memcpy,
    memmove = memmove,
    memset = memset,
    memcmp = memcmp,
    block = block,
    if_ = if_,
    switch_ = switch_,
    while_ = while_,
    break_ = break_,
    continue_ = continue_,
    FunctionMT = FunctionMT,
    module_ctor = module,
}

local asdl_frontend = require("moonlift.asdl") {
    parse = source_frontend.parse,
    caller_env = source_frontend.caller_env,
}

M = {
    types = types,
    void = types.void,
    bool = types.bool,
    i8 = types.i8,
    i16 = types.i16,
    i32 = types.i32,
    i64 = types.i64,
    u8 = types.u8,
    u16 = types.u16,
    u32 = types.u32,
    u64 = types.u64,
    usize = types.usize,
    byte = types.byte,
    isize = types.isize,
    f32 = types.f32,
    f64 = types.f64,
    ptr = make_ptr,
    struct_ = make_struct,
    union = make_union,
    tagged_union = make_tagged_union,
    array = make_array,
    slice = make_slice,
    enum = make_enum,
    param = param,
    arg = arg,
    let = setmetatable({}, LetMT),
    var = setmetatable({}, VarMT),
    block = block,
    quote = quote,
    q = q,
    quote_ir = quote_ir,
    quote_expr = quote_expr,
    quote_block = quote_block,
    hole = hole,
    cast = cast,
    trunc = trunc,
    zext = zext,
    sext = sext,
    bitcast = bitcast,
    code = function(source)
        return source_frontend.code(source, source_frontend.caller_env(1))
    end,
    expr = function(source)
        return source_frontend.expr(source, source_frontend.caller_env(1))
    end,
    type = function(source)
        return source_frontend.type(source, source_frontend.caller_env(1))
    end,
    asdl = function(source)
        return asdl_frontend.compile(source, asdl_frontend.caller_env(1))
    end,
    func = func,
    extern = function(x)
        if type(x) == "string" and source_frontend.looks_like_source_snippet(x) then
            return source_frontend.extern(x, source_frontend.caller_env(1))
        end
        return extern(x)
    end,
    import_module = import_module,
    invoke = invoke,
    module = function(x)
        if type(x) == "string" then
            return source_frontend.module(x, source_frontend.caller_env(1))
        end
        return module(x)
    end,
    if_ = if_,
    switch_ = switch_,
    while_ = while_,
    break_ = break_,
    continue_ = continue_,
    env = env,
    use = use,
    compile = compile,
    add = backend.add,
    call = backend.call,
    call0 = backend.call0,
    addr = backend.addr,
    call1 = backend.call1,
    call2 = backend.call2,
    call3 = backend.call3,
    call4 = backend.call4,
    stats = backend.stats,
    parse = source_frontend.parse,
    lower = source_frontend.lower,
    load = load,
    store = store,
    copy = copy,
    memcpy = memcpy,
    memmove = memmove,
    memset = memset,
    memcmp = memcmp,
}

return M
