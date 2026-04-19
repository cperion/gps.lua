local Stream = {}
local StreamMT = { __index = Stream }

local function new_stream(plan)
    return setmetatable(plan, StreamMT)
end

local function inherit_meta(plan, ...)
    for i = 1, select("#", ...) do
        local src = select(i, ...)
        if src ~= nil then
            local rt = rawget(src, "_iwj_rt")
            if rt ~= nil then
                plan._iwj_rt = rt
                plan._iwj_phase_name = rawget(src, "_iwj_phase_name")
                return plan
            end
        end
    end
    return plan
end

local function assert_same_item_type(a, b)
    assert(a.item_t == b.item_t, "stream item types must match")
end

function Stream:map(out_t, f)
    assert(type(f) == "function", "map requires a function")
    return inherit_meta(new_stream({
        kind = "map",
        item_t = out_t,
        count_hint = self.count_hint,
        src = self,
        f = f,
    }), self)
end

function Stream:filter(pred)
    assert(type(pred) == "function", "filter requires a function")
    return inherit_meta(new_stream({
        kind = "filter",
        item_t = self.item_t,
        count_hint = nil,
        src = self,
        pred = pred,
    }), self)
end

function Stream:concat(other)
    assert_same_item_type(self, other)
    local count_hint
    if self.count_hint ~= nil and other.count_hint ~= nil then
        count_hint = self.count_hint + other.count_hint
    end
    return inherit_meta(new_stream({
        kind = "concat",
        item_t = self.item_t,
        count_hint = count_hint,
        left = self,
        right = other,
    }), self, other)
end

function Stream:simd_map(vector_t, out_t, vf, sf)
    assert(type(vf) == "function", "simd_map requires a vector function")
    assert(type(sf) == "function", "simd_map requires a scalar fallback function")
    return inherit_meta(new_stream({
        kind = "simd_map",
        item_t = out_t,
        count_hint = self.count_hint,
        src = self,
        vector_t = vector_t,
        vf = vf,
        sf = sf,
    }), self)
end

function Stream:take(n)
    local count_hint
    if self.count_hint ~= nil and type(n) == "number" then
        count_hint = math.min(self.count_hint, n)
    end
    return inherit_meta(new_stream({
        kind = "take",
        item_t = self.item_t,
        count_hint = count_hint,
        src = self,
        n = n,
    }), self)
end

function Stream:drop(n)
    local count_hint
    if self.count_hint ~= nil and type(n) == "number" then
        count_hint = math.max(0, self.count_hint - n)
    end
    return inherit_meta(new_stream({
        kind = "drop",
        item_t = self.item_t,
        count_hint = count_hint,
        src = self,
        n = n,
    }), self)
end

local M = {}

local function range_count(start, stop, step)
    if type(start) ~= "number" or type(stop) ~= "number" or type(step) ~= "number" then
        return nil
    end
    if step == 0 then
        return nil
    end
    if step > 0 then
        if start >= stop then return 0 end
        return math.max(0, math.ceil((stop - start) / step))
    end
    if start <= stop then return 0 end
    return math.max(0, math.ceil((start - stop) / (-step)))
end

function M.seq(item_t, base, count)
    return new_stream({
        kind = "seq",
        item_t = item_t,
        count_hint = type(count) == "number" and count or nil,
        base = base,
        count = count,
    })
end

function M.once(item_t, value)
    return new_stream({
        kind = "once",
        item_t = item_t,
        count_hint = 1,
        value = value,
    })
end

function M.empty(item_t)
    return new_stream({
        kind = "empty",
        item_t = item_t,
        count_hint = 0,
    })
end

function M.range(item_t, start, stop, step)
    step = step or 1
    return new_stream({
        kind = "range",
        item_t = item_t,
        count_hint = range_count(start, stop, step),
        start = start,
        stop = stop,
        step = step,
    })
end

function M.cached_seq(item_t, values, count)
    if count == nil then
        assert(values ~= nil, "cached_seq requires values or count")
        count = #values
    end
    return new_stream({
        kind = "cached_seq",
        item_t = item_t,
        count_hint = count,
        values = values,
        count = count,
    })
end

function M.map(src, out_t, f)
    return src:map(out_t, f)
end

function M.filter(src, pred)
    return src:filter(pred)
end

function M.concat(a, b)
    return a:concat(b)
end

function M.simd_map(src, vector_t, out_t, vf, sf)
    return src:simd_map(vector_t, out_t, vf, sf)
end

function M.take(src, n)
    return src:take(n)
end

function M.drop(src, n)
    return src:drop(n)
end

M.Stream = Stream
M.new_stream = new_stream

return M
