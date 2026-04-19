local types = require("watjit.types")
local ctrl = require("watjit.ctrl")
local funcmod = require("watjit.func")

local function arena(name, capacity)
    assert(type(name) == "string", "arena name must be a string")
    assert(type(capacity) == "number" and capacity >= 0, "arena capacity must be a non-negative number")

    local i32 = types.i32
    local i32ptr = types.ptr(i32)
    local data_offset = 8

    local init = funcmod.fn {
        name = name .. "_init",
        params = { i32 "base" },
        body = function(base)
            local hdr = i32ptr("hdr", base)
            hdr[0] = base + i32(data_offset)
            hdr[1] = i32(capacity)
        end,
    }

    local alloc = funcmod.fn {
        name = name .. "_alloc",
        params = { i32 "base", i32 "size" },
        ret = i32,
        body = function(base, size)
            local hdr = i32ptr("hdr", base)
            local bump = i32("bump", hdr[0])
            local limit = i32("limit", base + i32(data_offset) + hdr[1])
            local aligned_words = i32("aligned_words", (size + 7) / 8)
            local aligned = i32("aligned", aligned_words * 8)
            local next_bump = i32("next_bump", bump + aligned)
            local out = i32("out", -1)

            ctrl.if_(next_bump:le(limit), function()
                hdr[0] = next_bump
                out(bump)
            end)

            return out
        end,
    }

    local reset = funcmod.fn {
        name = name .. "_reset",
        params = { i32 "base" },
        body = function(base)
            local hdr = i32ptr("hdr", base)
            hdr[0] = base + i32(data_offset)
        end,
    }

    return {
        name = name,
        capacity = capacity,
        data_offset = data_offset,
        memory_bytes = data_offset + capacity,
        init = init,
        alloc = alloc,
        reset = reset,
        funcs = function(self)
            return { self.init, self.alloc, self.reset }
        end,
    }
end

return arena
