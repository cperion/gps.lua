local types = require("watjit.types")
local ctrl = require("watjit.ctrl")
local funcmod = require("watjit.func")

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

local function hashtable(name, capacity)
    assert(type(name) == "string", "hashtable name must be a string")
    assert(type(capacity) == "number" and capacity > 0 and capacity % 1 == 0, "hashtable capacity must be a positive integer")

    local i32 = types.i32
    local u8 = types.u8
    local u32 = types.u32

    local EMPTY = 0
    local LIVE = 1
    local TOMB = 2

    local header_words = 2
    local header_bytes = header_words * 4
    local states_offset = header_bytes
    local keys_offset = align_up(states_offset + capacity, 4)
    local values_offset = keys_offset + capacity * 4
    local memory_bytes = values_offset + capacity * 4

    local function mix32(x)
        x = x:bxor(x:shr_u(16))
        x = x * u32(0x7feb352d)
        x = x:bxor(x:shr_u(15))
        x = x * u32(0x846ca68b)
        x = x:bxor(x:shr_u(16))
        return x
    end

    local function state_idx(i)
        return i
    end

    local function key_idx(i)
        return i
    end

    local function value_idx(i)
        return i
    end

    local init = funcmod.fn {
        name = name .. "_init",
        params = { i32 "base" },
        body = function(base)
            local hdr = types.view(i32, base, "hdr")
            local states = types.view(u8, base + i32(states_offset), "states")
            local i = i32("i")

            hdr[0](0)
            hdr[1](capacity)
            ctrl.for_(i, i32(capacity), function()
                states[state_idx(i)](EMPTY)
            end)
        end,
    }

    local clear = funcmod.fn {
        name = name .. "_clear",
        params = { i32 "base" },
        body = function(base)
            local hdr = types.view(i32, base, "hdr")
            local states = types.view(u8, base + i32(states_offset), "states")
            local i = i32("i")

            hdr[0](0)
            ctrl.for_(i, i32(capacity), function()
                states[state_idx(i)](EMPTY)
            end)
        end,
    }

    local len = funcmod.fn {
        name = name .. "_len",
        params = { i32 "base" },
        ret = i32,
        body = function(base)
            local hdr = types.view(i32, base, "hdr")
            return hdr[0]
        end,
    }

    local get = funcmod.fn {
        name = name .. "_get",
        params = { i32 "base", i32 "key", i32 "default" },
        ret = i32,
        body = function(base, key, default)
            local states = types.view(u8, base + i32(states_offset), "states")
            local keys = types.view(i32, base + i32(keys_offset), "keys")
            local values = types.view(i32, base + i32(values_offset), "values")
            local idx = i32("idx", types.cast(i32, mix32(types.cast(u32, key)):rem_u(u32(capacity))))
            local remain = i32("remain", capacity)
            local out = i32("out", default)
            local active = i32("active", 1)

            ctrl.while_(active:ne(0), function(loop)
                local st = u8("st", states[state_idx(idx)])
                ctrl.if_(st:eq(EMPTY), function()
                    active(0)
                end, function()
                    ctrl.if_(st:eq(LIVE), function()
                        ctrl.if_(keys[key_idx(idx)]:eq(key), function()
                            out(values[value_idx(idx)])
                            active(0)
                        end)
                    end)
                    ctrl.if_(active:ne(0), function()
                        remain(remain - 1)
                        ctrl.if_(remain:eq(0), function()
                            active(0)
                        end, function()
                            idx((idx + 1):rem_u(capacity))
                            loop:continue_()
                        end)
                    end)
                end)
            end)
            return out
        end,
    }

    local has = funcmod.fn {
        name = name .. "_has",
        params = { i32 "base", i32 "key" },
        ret = i32,
        body = function(base, key)
            local states = types.view(u8, base + i32(states_offset), "states")
            local keys = types.view(i32, base + i32(keys_offset), "keys")
            local idx = i32("idx", types.cast(i32, mix32(types.cast(u32, key)):rem_u(u32(capacity))))
            local remain = i32("remain", capacity)
            local out = i32("out", 0)
            local active = i32("active", 1)

            ctrl.while_(active:ne(0), function(loop)
                local st = u8("st", states[state_idx(idx)])
                ctrl.if_(st:eq(EMPTY), function()
                    active(0)
                end, function()
                    ctrl.if_(st:eq(LIVE), function()
                        ctrl.if_(keys[key_idx(idx)]:eq(key), function()
                            out(1)
                            active(0)
                        end)
                    end)
                    ctrl.if_(active:ne(0), function()
                        remain(remain - 1)
                        ctrl.if_(remain:eq(0), function()
                            active(0)
                        end, function()
                            idx((idx + 1):rem_u(capacity))
                            loop:continue_()
                        end)
                    end)
                end)
            end)
            return out
        end,
    }

    local set = funcmod.fn {
        name = name .. "_set",
        params = { i32 "base", i32 "key", i32 "value" },
        ret = i32,
        body = function(base, key, value)
            local hdr = types.view(i32, base, "hdr")
            local states = types.view(u8, base + i32(states_offset), "states")
            local keys = types.view(i32, base + i32(keys_offset), "keys")
            local values = types.view(i32, base + i32(values_offset), "values")
            local idx = i32("idx", types.cast(i32, mix32(types.cast(u32, key)):rem_u(u32(capacity))))
            local remain = i32("remain", capacity)
            local first_tomb = i32("first_tomb", -1)
            local out = i32("out", 0)
            local active = i32("active", 1)

            ctrl.while_(active:ne(0), function(loop)
                local st = u8("st", states[state_idx(idx)])
                ctrl.if_(st:eq(LIVE), function()
                    ctrl.if_(keys[key_idx(idx)]:eq(key), function()
                        values[value_idx(idx)](value)
                        out(1)
                        active(0)
                    end)
                end, function()
                    ctrl.if_(st:eq(EMPTY), function()
                        local dst = i32("dst", idx)
                        ctrl.if_(first_tomb:ge(0), function()
                            dst(first_tomb)
                        end)
                        states[state_idx(dst)](LIVE)
                        keys[key_idx(dst)](key)
                        values[value_idx(dst)](value)
                        hdr[0](hdr[0] + 1)
                        out(1)
                        active(0)
                    end, function()
                        ctrl.if_(first_tomb:lt(0), function()
                            first_tomb(idx)
                        end)
                    end)
                end)
                ctrl.if_(active:ne(0), function()
                    remain(remain - 1)
                    ctrl.if_(remain:eq(0), function()
                        ctrl.if_(first_tomb:ge(0), function()
                            states[state_idx(first_tomb)](LIVE)
                            keys[key_idx(first_tomb)](key)
                            values[value_idx(first_tomb)](value)
                            hdr[0](hdr[0] + 1)
                            out(1)
                        end)
                        active(0)
                    end, function()
                        idx((idx + 1):rem_u(capacity))
                        loop:continue_()
                    end)
                end)
            end)
            return out
        end,
    }

    local del = funcmod.fn {
        name = name .. "_del",
        params = { i32 "base", i32 "key" },
        ret = i32,
        body = function(base, key)
            local hdr = types.view(i32, base, "hdr")
            local states = types.view(u8, base + i32(states_offset), "states")
            local keys = types.view(i32, base + i32(keys_offset), "keys")
            local idx = i32("idx", types.cast(i32, mix32(types.cast(u32, key)):rem_u(u32(capacity))))
            local remain = i32("remain", capacity)
            local out = i32("out", 0)
            local active = i32("active", 1)

            ctrl.while_(active:ne(0), function(loop)
                local st = u8("st", states[state_idx(idx)])
                ctrl.if_(st:eq(EMPTY), function()
                    active(0)
                end, function()
                    ctrl.if_(st:eq(LIVE), function()
                        ctrl.if_(keys[key_idx(idx)]:eq(key), function()
                            states[state_idx(idx)](TOMB)
                            hdr[0](hdr[0] - 1)
                            out(1)
                            active(0)
                        end)
                    end)
                    ctrl.if_(active:ne(0), function()
                        remain(remain - 1)
                        ctrl.if_(remain:eq(0), function()
                            active(0)
                        end, function()
                            idx((idx + 1):rem_u(capacity))
                            loop:continue_()
                        end)
                    end)
                end)
            end)
            return out
        end,
    }

    return {
        name = name,
        capacity = capacity,
        state_empty = EMPTY,
        state_live = LIVE,
        state_tomb = TOMB,
        header_words = header_words,
        states_offset = states_offset,
        keys_offset = keys_offset,
        values_offset = values_offset,
        memory_bytes = memory_bytes,
        init = init,
        clear = clear,
        len = len,
        get = get,
        has = has,
        set = set,
        del = del,
        funcs = function(self)
            return {
                self.init,
                self.clear,
                self.len,
                self.get,
                self.has,
                self.set,
                self.del,
            }
        end,
    }
end

return hashtable
