local Scope = require("watjit.scope")
local types = require("watjit.types")

local Val = types.Val
local coerce = types.coerce
local i32 = types.i32

local function ptr_from_view(view, lane_t)
    if not Val.is(view) or not view.t or view.t.kind ~= "ptr" or view.t.elem ~= lane_t then
        error(("simd load/store expects a view(ptr(%s))"):format(lane_t.name), 3)
    end
    return view
end

local function elem_addr(base_view, index, lane_t)
    local index_val = coerce(index, i32)
    return Val.new({
        op = "add",
        t = i32,
        l = base_view.expr,
        r = {
            op = "mul",
            t = i32,
            l = index_val.expr,
            r = i32(lane_t.size).expr,
        },
    }, i32)
end

local function define_vector_type(name, lane_t, lanes)
    local t = {
        name = name,
        wat = "v128",
        op_wat = name,
        kind = "simd",
        lane_type = lane_t,
        lanes = lanes,
        bytes = 16,
        size = 16,
        align = 16,
        methods = {},
    }

    local function local_value(var_name, init)
        local value = Val.new({ op = "get", name = var_name }, t, {
            name = var_name,
            decl = true,
        })
        local scope = Scope.current()
        if scope then
            scope:declare(var_name, t)
            if init ~= nil then
                value(init)
            end
        end
        return value
    end

    local function vec_binary(op, a, b)
        a = coerce(a, t)
        b = coerce(b, t)
        return Val.new({ op = op, t = t, l = a.expr, r = b.expr }, t)
    end

    local function compare(op, a, b)
        a = coerce(a, t)
        b = coerce(b, t)
        return Val.new({ op = op, t = t, l = a.expr, r = b.expr }, t)
    end

    function t.splat(x)
        local lane = coerce(x, lane_t)
        return Val.new({ op = "splat", t = t, value = lane.expr }, t)
    end

    function t.zero()
        return t.splat(0)
    end

    function t.load(view, index)
        local base_view = ptr_from_view(view, lane_t)
        local addr = elem_addr(base_view, index, lane_t)
        return Val.new({ op = "vload", t = t, ptr = addr.expr }, t)
    end

    function t.store(view, index, value)
        local scope = Scope.current()
        if not scope then
            error("simd store outside of a watjit scope", 2)
        end
        local base_view = ptr_from_view(view, lane_t)
        local addr = elem_addr(base_view, index, lane_t)
        scope:push_stmt({
            op = "vstore",
            t = t,
            ptr = addr.expr,
            value = coerce(value, t).expr,
        })
    end

    function t.extract(value, lane)
        value = coerce(value, t)
        assert(type(lane) == "number" and lane >= 0 and lane < lanes and lane % 1 == 0,
            ("lane must be an integer in [0,%d)"):format(lanes))
        return Val.new({
            op = "extract_lane",
            t = lane_t,
            vec_t = t,
            value = value.expr,
            lane = lane,
        }, lane_t)
    end

    function t.replace(vec, lane, scalar)
        vec = coerce(vec, t)
        scalar = coerce(scalar, lane_t)
        assert(type(lane) == "number" and lane >= 0 and lane < lanes and lane % 1 == 0,
            ("lane must be an integer in [0,%d)"):format(lanes))
        return Val.new({
            op = "replace_lane",
            t = t,
            value = vec.expr,
            scalar = scalar.expr,
            lane = lane,
        }, t)
    end

    function t.select(mask, a, b)
        mask = coerce(mask, t)
        a = coerce(a, t)
        b = coerce(b, t)
        return Val.new({
            op = "vbitselect",
            t = t,
            mask = mask.expr,
            then_ = a.expr,
            else_ = b.expr,
        }, t)
    end

    function t.shuffle(a, b, lane_indices)
        a = coerce(a, t)
        b = coerce(b, t)
        assert(type(lane_indices) == "table", "shuffle lane_indices must be a table")
        assert(#lane_indices == lanes, ("%s.shuffle expects %d lane indices, got %d"):format(name, lanes, #lane_indices))

        local byte_indices = {}
        local lane_bytes = lane_t.size
        for i = 1, lanes do
            local src_lane = lane_indices[i]
            assert(type(src_lane) == "number" and src_lane >= 0 and src_lane < lanes * 2 and src_lane % 1 == 0,
                ("shuffle lane index %d must be an integer in [0,%d)"):format(i, lanes * 2))
            local byte_base = src_lane * lane_bytes
            for j = 0, lane_bytes - 1 do
                byte_indices[#byte_indices + 1] = byte_base + j
            end
        end

        return Val.new({
            op = "shuffle",
            t = t,
            l = a.expr,
            r = b.expr,
            lanes = byte_indices,
        }, t)
    end

    function t.sum(value)
        value = coerce(value, t)
        local acc = t.extract(value, 0)
        for lane = 1, lanes - 1 do
            acc = acc + t.extract(value, lane)
        end
        return acc
    end

    t.methods.eq = function(self, rhs)
        return compare("eq", self, rhs)
    end
    t.methods.ne = function(self, rhs)
        return compare("ne", self, rhs)
    end
    t.methods.lt = function(self, rhs)
        return compare("lt", self, rhs)
    end
    t.methods.le = function(self, rhs)
        return compare("le", self, rhs)
    end
    t.methods.gt = function(self, rhs)
        return compare("gt", self, rhs)
    end
    t.methods.ge = function(self, rhs)
        return compare("ge", self, rhs)
    end
    t.methods.sum = function(self)
        return t.sum(self)
    end
    t.methods.extract = function(self, lane)
        return t.extract(self, lane)
    end
    t.methods.replace = function(self, lane, scalar)
        return t.replace(self, lane, scalar)
    end
    t.methods.select = function(self, a, b)
        return t.select(self, a, b)
    end

    return setmetatable(t, {
        __call = function(self, a, b)
            if type(a) == "string" then
                return local_value(a, b)
            end
            if type(a) == "table" then
                if #a ~= lanes then
                    error(("%s literal expects %d lanes, got %d"):format(name, lanes, #a), 2)
                end
                local lane_exprs = {}
                for i = 1, lanes do
                    lane_exprs[i] = coerce(a[i], lane_t).expr
                end
                return Val.new({ op = "vconst", t = t, lanes = lane_exprs }, t)
            end
            error(("bad call to simd type %s"):format(name), 2)
        end,
        __tostring = function(self)
            return self.name
        end,
        __add = function(a, b)
            return vec_binary("add", a, b)
        end,
        __sub = function(a, b)
            return vec_binary("sub", a, b)
        end,
        __mul = function(a, b)
            return vec_binary("mul", a, b)
        end,
        __div = function(a, b)
            return vec_binary("div", a, b)
        end,
    })
end

local M = {
    f32x4 = define_vector_type("f32x4", types.f32, 4),
    f64x2 = define_vector_type("f64x2", types.f64, 2),
    i32x4 = define_vector_type("i32x4", types.i32, 4),
}

return M
