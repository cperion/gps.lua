local Scope = require("watjit.scope")
local types = require("watjit.types")

local coerce = types.coerce
local i32 = types.i32
local new_val = types.Val.new

local function is_layout_type(t)
    return type(t) == "table" and (t.layout_kind == "struct" or t.layout_kind == "array" or t.layout_kind == "union")
end

local function field_addr(base, offset)
    local base_val = coerce(base, i32)
    return base_val + i32(offset)
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

local function type_align(t)
    return (t and t.align) or (t and t.size) or 1
end

local function field_align(field_type, field_opts)
    local a = type_align(field_type)
    local extra = nil
    if type(field_opts) == "number" then
        extra = field_opts
    elseif type(field_opts) == "table" then
        extra = field_opts.align
    end
    if extra ~= nil then
        assert(type(extra) == "number" and extra >= 1 and extra % 1 == 0, "field align must be a positive integer")
        if extra > a then
            a = extra
        end
    end
    return a
end

local function struct(name, fields, opts)
    assert(type(name) == "string", "struct name must be a string")
    assert(type(fields) == "table", "struct fields must be a table")
    opts = opts or {}

    local packed = opts.packed ~= false
    local ordered = {}
    local lookup = {}
    local offset = 0
    local max_align = 1

    for i = 1, #fields do
        local field = fields[i]
        local field_name = assert(field[1], "struct field missing name")
        local field_type = assert(field[2], "struct field missing type")
        local field_opts = field[3]
        assert(type(field_name) == "string", "struct field name must be a string")
        assert(type(field_type) == "table" and field_type.size, "struct field type must have a size")
        assert(lookup[field_name] == nil, "duplicate struct field: " .. field_name)

        local fa = packed and 1 or field_align(field_type, field_opts)
        if fa > max_align then
            max_align = fa
        end
        offset = align_up(offset, fa)

        local entry = {
            name = field_name,
            type = field_type,
            offset = offset,
            align = fa,
        }
        ordered[#ordered + 1] = entry
        lookup[field_name] = entry
        offset = offset + field_type.size
    end

    local explicit_align = opts.align
    if explicit_align ~= nil then
        assert(type(explicit_align) == "number" and explicit_align >= 1 and explicit_align % 1 == 0, "struct opts.align must be a positive integer")
        if explicit_align > max_align then
            max_align = explicit_align
        end
    end
    local final_align = packed and (explicit_align or 1) or max_align

    local S = {
        name = name,
        fields = ordered,
        offsets = lookup,
        size = align_up(offset, final_align),
        align = final_align,
        packed = packed,
        layout_kind = "struct",
    }

    function S.at(base)
        return setmetatable({
            _base = coerce(base, i32),
            _struct = S,
        }, {
            __index = function(self, key)
                if key == "base" then
                    return self._base
                end
                local field = lookup[key]
                if not field then
                    return nil
                end
                local addr = field_addr(self._base, field.offset)
                if is_layout_type(field.type) then
                    return field.type.at(addr)
                end
                return new_val({
                    op = "load",
                    t = field.type,
                    ptr = addr.expr,
                }, field.type, {
                    assign = function(rhs)
                        local scope = Scope.current()
                        if not scope then
                            error("struct store outside of a watjit scope", 3)
                        end
                        scope:push_stmt({
                            op = "store",
                            t = field.type,
                            ptr = addr.expr,
                            value = rhs.expr,
                        })
                    end,
                })
            end,
            __newindex = function(self, key, value)
                local field = lookup[key]
                if not field then
                    rawset(self, key, value)
                    return
                end
                if is_layout_type(field.type) then
                    error("cannot assign aggregate struct fields directly", 2)
                end
                local scope = Scope.current()
                if not scope then
                    error("struct store outside of a watjit scope", 2)
                end
                local addr = field_addr(self._base, field.offset)
                scope:push_stmt({
                    op = "store",
                    t = field.type,
                    ptr = addr.expr,
                    value = coerce(value, field.type).expr,
                })
            end,
        })
    end

    return S
end

return struct
