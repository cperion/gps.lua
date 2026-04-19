local Scope = require("watjit.scope")

local methods = {}
local ValMT = {}
local i32, i64, u32, u64

local function is_layout_type(t)
    return type(t) == "table" and (t.layout_kind == "struct" or t.layout_kind == "array" or t.layout_kind == "union")
end

local function is_val(x)
    return getmetatable(x) == ValMT
end

local function is_integer_type(t)
    return type(t) == "table" and t.family == "int"
end

local function is_float_type(t)
    return type(t) == "table" and (t.wat == "f32" or t.wat == "f64")
end

local function new_val(expr, t, extra)
    local value = extra or {}
    value.expr = expr
    value.t = t
    return setmetatable(value, ValMT)
end

local function expect_type(t, message)
    if t == nil then
        error(message, 3)
    end
    return t
end

local function coerce(x, t)
    if is_val(x) then
        return x
    end
    if type(x) == "number" then
        t = expect_type(t, "cannot coerce number without a target type")
        return new_val({ op = "const", t = t, value = x }, t)
    end
    if type(x) == "string" then
        t = expect_type(t, "cannot coerce name without a target type")
        return new_val({ op = "get", name = x }, t)
    end
    error("cannot coerce value of type " .. type(x), 3)
end

local function common_type(a, b)
    if is_val(a) then
        return a.t
    end
    if is_val(b) then
        return b.t
    end
    error("binary expression needs at least one typed operand", 3)
end

local function binary(op, a, b)
    local t = common_type(a, b)
    a = coerce(a, t)
    b = coerce(b, t)
    return new_val({ op = op, t = t, l = a.expr, r = b.expr }, t)
end

local function compare(op, a, b)
    local t = common_type(a, b)
    a = coerce(a, t)
    b = coerce(b, t)
    return new_val({ op = op, t = t, l = a.expr, r = b.expr }, i32)
end

local function select_expr(cond, a, b)
    local t = common_type(a, b)
    return new_val({
        op = "select",
        t = t,
        cond = coerce(cond, i32).expr,
        then_ = coerce(a, t).expr,
        else_ = coerce(b, t).expr,
    }, t)
end

local function with_assign(value, assign)
    value.assign = assign
    return value
end

local function emit_store(ptr_expr, t, rhs)
    local scope = Scope.current()
    if not scope then
        error("store outside of a watjit scope", 3)
    end
    scope:push_stmt({
        op = "store",
        t = t,
        ptr = ptr_expr,
        value = rhs.expr,
    })
end

local function assign_value(self, rhs)
    rhs = coerce(rhs, self.t)
    if self.assign then
        return self.assign(rhs)
    end
    if self.name ~= nil then
        local scope = Scope.current()
        if not scope then
            error("assignment outside of a watjit scope", 3)
        end
        scope:assign(self.name, rhs)
        return nil
    end
    error("cannot assign to this value", 3)
end

local function pointer_addr(self, key)
    local index = coerce(key, i32)
    local scale = i32(self.t.elem.size)
    return new_val({
        op = "add",
        t = i32,
        l = self.expr,
        r = {
            op = "mul",
            t = i32,
            l = index.expr,
            r = scale.expr,
        },
    }, i32)
end

ValMT.__index = function(self, key)
    if type(key) == "string" then
        if self.t and self.t.methods then
            local method = self.t.methods[key]
            if method ~= nil then
                return method
            end
        end
        local method = methods[key]
        if method ~= nil then
            return method
        end
        return nil
    end
    if self.t and self.t.kind == "ptr" then
        local addr = pointer_addr(self, key)
        local elem_t = self.t.elem
        if is_layout_type(elem_t) then
            return elem_t.at(addr)
        end
        return with_assign(new_val({
            op = "load",
            t = elem_t,
            ptr = addr.expr,
        }, elem_t), function(rhs)
            emit_store(addr.expr, elem_t, rhs)
        end)
    end
    return nil
end

ValMT.__newindex = function(self, key, value)
    if self.t and self.t.kind == "ptr" and type(key) ~= "string" then
        local addr = pointer_addr(self, key)
        emit_store(addr.expr, self.t.elem, coerce(value, self.t.elem))
        return
    end
    rawset(self, key, value)
end

ValMT.__call = function(self, ...)
    if select("#", ...) ~= 1 then
        error("value call expects exactly one rhs argument", 2)
    end
    return assign_value(self, ...)
end

ValMT.__add = function(a, b)
    return binary("add", a, b)
end

ValMT.__sub = function(a, b)
    return binary("sub", a, b)
end

ValMT.__mul = function(a, b)
    return binary("mul", a, b)
end

ValMT.__div = function(a, b)
    return binary("div", a, b)
end

ValMT.__mod = function(a, b)
    return binary("rem", a, b)
end

ValMT.__unm = function(a)
    return binary("sub", coerce(0, a.t), a)
end

methods.lt = function(self, rhs)
    return compare("lt", self, rhs)
end

methods.le = function(self, rhs)
    return compare("le", self, rhs)
end

methods.gt = function(self, rhs)
    return compare("gt", self, rhs)
end

methods.ge = function(self, rhs)
    return compare("ge", self, rhs)
end

methods.eq = function(self, rhs)
    return compare("eq", self, rhs)
end

methods.ne = function(self, rhs)
    return compare("ne", self, rhs)
end

methods.lt_u = function(self, rhs)
    return compare("lt_u", self, rhs)
end

methods.le_u = function(self, rhs)
    return compare("le_u", self, rhs)
end

methods.gt_u = function(self, rhs)
    return compare("gt_u", self, rhs)
end

methods.ge_u = function(self, rhs)
    return compare("ge_u", self, rhs)
end

methods.div_s = function(self, rhs)
    return binary("div_s", self, rhs)
end

methods.div_u = function(self, rhs)
    return binary("div_u", self, rhs)
end

methods.rem_s = function(self, rhs)
    return binary("rem_s", self, rhs)
end

methods.rem_u = function(self, rhs)
    return binary("rem_u", self, rhs)
end

methods.band = function(self, rhs)
    return binary("band", self, rhs)
end

methods.bor = function(self, rhs)
    return binary("bor", self, rhs)
end

methods.bxor = function(self, rhs)
    return binary("bxor", self, rhs)
end

methods.bnot = function(self)
    local t = self.t
    if not is_integer_type(t) then
        error("bnot requires an integer value", 2)
    end
    return binary("bxor", self, coerce(-1, t))
end

methods.shl = function(self, rhs)
    return binary("shl", self, rhs)
end

methods.shr_u = function(self, rhs)
    return binary("shr_u", self, rhs)
end

methods.shr_s = function(self, rhs)
    return binary("shr_s", self, rhs)
end

methods.rotl = function(self, rhs)
    return binary("rotl", self, rhs)
end

methods.rotr = function(self, rhs)
    return binary("rotr", self, rhs)
end

local function carrier_bits(t)
    if t.wat == "i32" or t.wat == "f32" then
        return 32
    end
    if t.wat == "i64" or t.wat == "f64" then
        return 64
    end
    error("unsupported carrier type: " .. tostring(t and t.name), 3)
end

local function carrier_int_type(t, unsigned)
    if t.wat == "i32" then
        return unsigned and u32 or i32
    end
    if t.wat == "i64" then
        return unsigned and u64 or i64
    end
    error("expected integer carrier type, got " .. tostring(t and t.name), 3)
end

local function unary_wat(target_t, wat_op, value)
    return new_val({
        op = "wat_unary",
        t = target_t,
        wat_op = wat_op,
        value = value.expr,
    }, target_t)
end

local function normalize_unsigned_value(x, bits)
    local cbits = carrier_bits(x.t)
    if bits == nil or bits >= cbits then
        return x
    end
    local mask_t = carrier_int_type(x.t, true)
    local mask = 2 ^ bits - 1
    return x:band(mask_t(mask))
end

local function normalize_signed_value(x, bits)
    local cbits = carrier_bits(x.t)
    if bits == nil or bits >= cbits then
        return x
    end
    local sh = cbits - bits
    return x:shl(sh):shr_s(sh)
end

methods.clz = function(self)
    if not is_integer_type(self.t) then
        error("clz requires an integer value", 2)
    end
    return new_val({
        op = "wat_unary",
        t = self.t,
        wat_op = self.t.wat .. ".clz",
        value = self.expr,
    }, self.t)
end

methods.ctz = function(self)
    if not is_integer_type(self.t) then
        error("ctz requires an integer value", 2)
    end
    return new_val({
        op = "wat_unary",
        t = self.t,
        wat_op = self.t.wat .. ".ctz",
        value = self.expr,
    }, self.t)
end

methods.popcnt = function(self)
    if not is_integer_type(self.t) then
        error("popcnt requires an integer value", 2)
    end
    return new_val({
        op = "wat_unary",
        t = self.t,
        wat_op = self.t.wat .. ".popcnt",
        value = self.expr,
    }, self.t)
end

methods.bswap = function(self)
    if not is_integer_type(self.t) then
        error("bswap requires an integer value", 2)
    end
    local bits = self.t.bits or carrier_bits(self.t)
    if bits % 8 ~= 0 then
        error("bswap requires an integer width that is a multiple of 8 bits", 2)
    end
    if bits == 8 then
        return new_val(self.expr, self.t)
    end

    local carrier_u = carrier_int_type(self.t, true)
    local x = new_val(self.expr, carrier_u)
    if bits < carrier_bits(self.t) then
        x = normalize_unsigned_value(x, bits)
    end

    local byte_count = bits / 8
    local mask_ff = carrier_u(0xff)
    local acc = nil
    for i = 0, byte_count - 1 do
        local part = x:shr_u(i * 8):band(mask_ff)
        local shift = (byte_count - 1 - i) * 8
        if shift > 0 then
            part = part:shl(shift)
        end
        if acc == nil then
            acc = part
        else
            acc = acc:bor(part)
        end
    end
    if bits < carrier_bits(self.t) then
        acc = normalize_unsigned_value(acc, bits)
    end
    return new_val(acc.expr, self.t)
end

local function trunc(target_t, x)
    assert(type(target_t) == "table" and is_integer_type(target_t), "trunc target must be an integer type")
    x = coerce(x, target_t)
    assert(is_integer_type(x.t), "trunc source must be an integer value")

    local v = x
    if v.t.wat ~= target_t.wat then
        if v.t.wat == "i64" and target_t.wat == "i32" then
            v = unary_wat(carrier_int_type(target_t, true), "i32.wrap_i64", v)
        elseif v.t.wat == "i32" and target_t.wat == "i64" then
            v = unary_wat(carrier_int_type(target_t, true), "i64.extend_i32_u", v)
        else
            error(("unsupported trunc from %s to %s"):format(v.t.name, target_t.name), 2)
        end
    end

    v = new_val(v.expr, target_t)
    if target_t.bits and target_t.bits < carrier_bits(target_t) then
        if target_t.signed then
            v = new_val(normalize_signed_value(v, target_t.bits).expr, target_t)
        else
            v = new_val(normalize_unsigned_value(v, target_t.bits).expr, target_t)
        end
    end
    return v
end

local function zext(target_t, x)
    assert(type(target_t) == "table" and is_integer_type(target_t), "zext target must be an integer type")
    x = coerce(x, target_t)
    assert(is_integer_type(x.t), "zext source must be an integer value")

    local src_bits = x.t.bits or carrier_bits(x.t)
    local v = normalize_unsigned_value(x, src_bits)

    if v.t.wat ~= target_t.wat then
        if v.t.wat == "i32" and target_t.wat == "i64" then
            v = unary_wat(carrier_int_type(target_t, true), "i64.extend_i32_u", v)
        elseif v.t.wat == "i64" and target_t.wat == "i32" then
            v = unary_wat(carrier_int_type(target_t, true), "i32.wrap_i64", v)
        else
            error(("unsupported zext from %s to %s"):format(x.t.name, target_t.name), 2)
        end
    end

    v = new_val(v.expr, target_t)
    if target_t.bits and target_t.bits < carrier_bits(target_t) then
        v = new_val(normalize_unsigned_value(v, target_t.bits).expr, target_t)
    end
    return v
end

local function sext(target_t, x)
    assert(type(target_t) == "table" and is_integer_type(target_t), "sext target must be an integer type")
    x = coerce(x, target_t)
    assert(is_integer_type(x.t), "sext source must be an integer value")

    local src_bits = x.t.bits or carrier_bits(x.t)
    local v = normalize_signed_value(x, src_bits)

    if v.t.wat ~= target_t.wat then
        if v.t.wat == "i32" and target_t.wat == "i64" then
            v = unary_wat(carrier_int_type(target_t, false), "i64.extend_i32_s", v)
        elseif v.t.wat == "i64" and target_t.wat == "i32" then
            v = unary_wat(carrier_int_type(target_t, false), "i32.wrap_i64", v)
        else
            error(("unsupported sext from %s to %s"):format(x.t.name, target_t.name), 2)
        end
    end

    v = new_val(v.expr, target_t)
    if target_t.bits and target_t.bits < carrier_bits(target_t) then
        v = new_val(normalize_signed_value(v, target_t.bits).expr, target_t)
    end
    return v
end

local function cast(target_t, x)
    assert(type(target_t) == "table" and target_t.wat, "cast target must be a watjit type")
    x = coerce(x, target_t)
    if x.t == target_t then
        return x
    end

    if is_integer_type(target_t) and is_integer_type(x.t) then
        local src_bits = x.t.bits or carrier_bits(x.t)
        local v = x.t.signed == false and normalize_unsigned_value(x, src_bits) or normalize_signed_value(x, src_bits)

        if v.t.wat ~= target_t.wat then
            if v.t.wat == "i32" and target_t.wat == "i64" then
                v = unary_wat(carrier_int_type(target_t, target_t.signed == false),
                    "i64.extend_i32_" .. ((v.t.signed == false) and "u" or "s"), v)
            elseif v.t.wat == "i64" and target_t.wat == "i32" then
                v = unary_wat(carrier_int_type(target_t, target_t.signed == false), "i32.wrap_i64", v)
            else
                error(("unsupported integer cast from %s to %s"):format(x.t.name, target_t.name), 2)
            end
        end

        v = new_val(v.expr, target_t)
        if target_t.bits and target_t.bits < carrier_bits(target_t) then
            if target_t.signed then
                v = new_val(normalize_signed_value(v, target_t.bits).expr, target_t)
            else
                v = new_val(normalize_unsigned_value(v, target_t.bits).expr, target_t)
            end
        end
        return v
    end

    if is_float_type(target_t) and is_float_type(x.t) then
        if target_t.wat == x.t.wat then
            return new_val(x.expr, target_t)
        end
        if target_t.wat == "f64" and x.t.wat == "f32" then
            return unary_wat(target_t, "f64.promote_f32", x)
        end
        if target_t.wat == "f32" and x.t.wat == "f64" then
            return unary_wat(target_t, "f32.demote_f64", x)
        end
    end

    if is_float_type(target_t) and is_integer_type(x.t) then
        local src_bits = x.t.bits or carrier_bits(x.t)
        local v = x.t.signed == false and normalize_unsigned_value(x, src_bits) or normalize_signed_value(x, src_bits)
        return unary_wat(target_t, target_t.wat .. ".convert_" .. v.t.wat .. "_" .. ((v.t.signed == false) and "u" or "s"), v)
    end

    if is_integer_type(target_t) and is_float_type(x.t) then
        local v = unary_wat(target_t, target_t.wat .. ".trunc_" .. x.t.wat .. "_" .. ((target_t.signed == false) and "u" or "s"), x)
        if target_t.bits and target_t.bits < carrier_bits(target_t) then
            if target_t.signed then
                v = new_val(normalize_signed_value(v, target_t.bits).expr, target_t)
            else
                v = new_val(normalize_unsigned_value(v, target_t.bits).expr, target_t)
            end
        end
        return v
    end

    if target_t.wat == x.t.wat then
        return new_val(x.expr, target_t)
    end

    error(("unsupported cast from %s to %s"):format(tostring(x.t and x.t.name), tostring(target_t.name)), 2)
end

local function bitcast(target_t, x)
    assert(type(target_t) == "table" and target_t.wat, "bitcast target must be a watjit type")
    x = coerce(x, target_t)

    if x.t.wat == target_t.wat and x.t.size == target_t.size then
        return new_val(x.expr, target_t)
    end
    if x.t.wat == "f32" and target_t.wat == "i32" and x.t.size == target_t.size then
        return unary_wat(target_t, "i32.reinterpret_f32", x)
    end
    if x.t.wat == "i32" and target_t.wat == "f32" and x.t.size == target_t.size then
        return unary_wat(target_t, "f32.reinterpret_i32", x)
    end
    if x.t.wat == "f64" and target_t.wat == "i64" and x.t.size == target_t.size then
        return unary_wat(target_t, "i64.reinterpret_f64", x)
    end
    if x.t.wat == "i64" and target_t.wat == "f64" and x.t.size == target_t.size then
        return unary_wat(target_t, "f64.reinterpret_i64", x)
    end
    error(("unsupported bitcast from %s to %s"):format(tostring(x.t and x.t.name), tostring(target_t.name)), 2)
end

local function make_type(name, size, wat_name, extra)
    extra = extra or {}
    local t = {
        name = name,
        size = size,
        align = extra.align or size,
        wat = wat_name,
        kind = extra.kind or "scalar",
        elem = extra.elem or nil,
        family = extra.family,
        signed = extra.signed,
        bits = extra.bits,
        load_op = extra.load_op,
        store_op = extra.store_op,
    }

    return setmetatable(t, {
        __call = function(self, a, b)
            if type(a) == "number" then
                return new_val({ op = "const", t = self, value = a }, self)
            end
            if type(a) == "string" then
                local value = with_assign(new_val({ op = "get", name = a }, self, {
                    name = a,
                    decl = true,
                }), function(rhs)
                    local scope = Scope.current()
                    if not scope then
                        error("assignment outside of a watjit scope", 3)
                    end
                    scope:assign(a, rhs)
                end)
                local scope = Scope.current()
                if scope then
                    scope:declare(a, self)
                    if b ~= nil then
                        assign_value(value, b)
                    end
                end
                return value
            end
            error(("bad call to type %s"):format(self.name), 2)
        end,
        __tostring = function(self)
            return self.name
        end,
    })
end

local function int_type(name, size, wat_name, signed, bits, extra)
    extra = extra or {}
    extra.family = "int"
    extra.signed = signed
    extra.bits = bits
    return make_type(name, size, wat_name, extra)
end

i32 = int_type("i32", 4, "i32", true, 32)
i64 = int_type("i64", 8, "i64", true, 64)
local i8 = int_type("i8", 1, "i32", true, 8, {
    load_op = "i32.load8_s",
    store_op = "i32.store8",
})
local i16 = int_type("i16", 2, "i32", true, 16, {
    load_op = "i32.load16_s",
    store_op = "i32.store16",
})
local u8 = int_type("u8", 1, "i32", false, 8, {
    load_op = "i32.load8_u",
    store_op = "i32.store8",
})
local u16 = int_type("u16", 2, "i32", false, 16, {
    load_op = "i32.load16_u",
    store_op = "i32.store16",
})
u32 = int_type("u32", 4, "i32", false, 32)
u64 = int_type("u64", 8, "i64", false, 64)
local f32 = make_type("f32", 4, "f32")
local f64 = make_type("f64", 8, "f64")

local function enum(name, storage_t, values)
    assert(type(name) == "string", "enum name must be a string")
    assert(type(storage_t) == "table" and storage_t.size and storage_t.wat, "enum storage_t must be a watjit scalar type")
    assert(type(values) == "table", "enum values must be a table")

    local t = make_type(name, storage_t.size, storage_t.wat, {
        kind = "enum",
        align = storage_t.align,
        family = storage_t.family,
        signed = storage_t.signed,
        bits = storage_t.bits,
        load_op = storage_t.load_op,
        store_op = storage_t.store_op,
    })
    t.storage = storage_t
    t.values = {}

    for k, v in pairs(values) do
        assert(type(k) == "string", "enum member names must be strings")
        assert(type(v) == "number", ("enum member %s must be a number"):format(k))
        local c = new_val({ op = "const", t = t, value = v }, t)
        t[k] = c
        t.values[k] = c
    end

    return t
end

local function ptr(elem_t)
    return make_type("ptr(" .. elem_t.name .. ")", 4, "i32", {
        kind = "ptr",
        elem = elem_t,
    })
end

local function let(t, name, init)
    return t(name, init)
end

local function lets(t, ...)
    local names = { ... }
    local out = {}
    for i = 1, #names do
        out[i] = t(names[i])
    end
    return table.unpack(out, 1, #out)
end

local function view(elem_t, base, name)
    if is_layout_type(elem_t) then
        return elem_t.at(base)
    end
    local ptr_t = ptr(elem_t)
    local base_val = coerce(base, i32)
    if name ~= nil then
        return ptr_t(name, base_val)
    end
    return new_val(base_val.expr, ptr_t)
end

return {
    Val = {
        new = new_val,
        is = is_val,
    },
    coerce = coerce,
    select = select_expr,
    cast = cast,
    trunc = trunc,
    zext = zext,
    sext = sext,
    bitcast = bitcast,
    i8 = i8,
    i16 = i16,
    i32 = i32,
    i64 = i64,
    u8 = u8,
    u16 = u16,
    u32 = u32,
    u64 = u64,
    f32 = f32,
    f64 = f64,
    ptr = ptr,
    enum = enum,
    let = let,
    lets = lets,
    view = view,
    void = { name = "void" },
}
