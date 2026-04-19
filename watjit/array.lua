local Scope = require("watjit.scope")
local types = require("watjit.types")

local coerce = types.coerce
local i32 = types.i32
local new_val = types.Val.new

local function is_layout_type(t)
    return type(t) == "table" and (t.layout_kind == "struct" or t.layout_kind == "array" or t.layout_kind == "union")
end

local function elem_addr(base, elem_t, index)
    local base_val = coerce(base, i32)
    local index_val = coerce(index, i32)
    return base_val + index_val * i32(elem_t.size)
end

local function array(elem_t, count)
    assert(type(elem_t) == "table", "array elem_t must be a watjit type")
    assert(type(count) == "number" and count >= 0 and count % 1 == 0, "array count must be a non-negative integer")

    local A = {
        name = ("array(%s,%d)"):format(elem_t.name or "?", count),
        elem = elem_t,
        count = count,
        size = elem_t.size * count,
        align = elem_t.align or elem_t.size or 1,
        layout_kind = "array",
    }

    function A.at(base)
        return setmetatable({
            _base = coerce(base, i32),
            _array = A,
        }, {
            __index = function(self, key)
                if type(key) == "string" then
                    if key == "count" then
                        return count
                    elseif key == "size" then
                        return A.size
                    elseif key == "base" then
                        return self._base
                    end
                    return nil
                end

                local addr = elem_addr(self._base, elem_t, key)
                if is_layout_type(elem_t) then
                    return elem_t.at(addr)
                end
                return new_val({
                    op = "load",
                    t = elem_t,
                    ptr = addr.expr,
                }, elem_t, {
                    assign = function(rhs)
                        local scope = Scope.current()
                        if not scope then
                            error("array store outside of a watjit scope", 3)
                        end
                        scope:push_stmt({
                            op = "store",
                            t = elem_t,
                            ptr = addr.expr,
                            value = rhs.expr,
                        })
                    end,
                })
            end,
            __newindex = function(self, key, value)
                if type(key) == "string" then
                    rawset(self, key, value)
                    return
                end
                if is_layout_type(elem_t) then
                    error("cannot assign aggregate array elements directly", 2)
                end
                local scope = Scope.current()
                if not scope then
                    error("array store outside of a watjit scope", 2)
                end
                local addr = elem_addr(self._base, elem_t, key)
                scope:push_stmt({
                    op = "store",
                    t = elem_t,
                    ptr = addr.expr,
                    value = coerce(value, elem_t).expr,
                })
            end,
        })
    end

    return A
end

return array
