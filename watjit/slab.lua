local types = require("watjit.types")
local ctrl = require("watjit.ctrl")
local funcmod = require("watjit.func")

local function slab(name, slot_size, capacity)
    assert(type(name) == "string", "slab name must be a string")
    assert(type(slot_size) == "number" and slot_size > 0, "slab slot_size must be a positive number")
    assert(type(capacity) == "number" and capacity >= 0, "slab capacity must be a non-negative number")

    local i32 = types.i32
    local i32ptr = types.ptr(i32)
    local header_words = 4
    local data_offset = header_words * 4

    local function slot_addr_expr(base, index)
        return base + i32(data_offset) + index * i32(slot_size)
    end

    local init = funcmod.fn {
        name = name .. "_init",
        params = { i32 "base" },
        body = function(base)
            local hdr = i32ptr("hdr", base)
            hdr[0] = -1          -- free_head
            hdr[1] = capacity    -- capacity
            hdr[2] = slot_size   -- slot_size
            hdr[3] = 0           -- next_unused
        end,
    }

    local alloc = funcmod.fn {
        name = name .. "_alloc",
        params = { i32 "base" },
        ret = i32,
        body = function(base)
            local hdr = i32ptr("hdr", base)
            local free_head = i32("free_head", hdr[0])
            local next_unused = i32("next_unused", hdr[3])
            local idx = i32("idx", -1)
            local next_free = i32("next_free", -1)

            ctrl.if_(free_head:ne(-1), function()
                local slot_ptr = i32("slot_ptr", slot_addr_expr(base, free_head))
                local slot_mem = i32ptr("slot_mem", slot_ptr)
                idx(free_head)
                next_free(slot_mem[0])
                hdr[0] = next_free
            end, function()
                ctrl.if_(next_unused:lt(capacity), function()
                    idx(next_unused)
                    hdr[3] = next_unused + 1
                end)
            end)

            return idx
        end,
    }

    local free = funcmod.fn {
        name = name .. "_free",
        params = { i32 "base", i32 "index" },
        body = function(base, index)
            local hdr = i32ptr("hdr", base)
            local slot_ptr = i32("slot_ptr", slot_addr_expr(base, index))
            local slot_mem = i32ptr("slot_mem", slot_ptr)
            slot_mem[0] = hdr[0]
            hdr[0] = index
        end,
    }

    local addr = funcmod.fn {
        name = name .. "_addr",
        params = { i32 "base", i32 "index" },
        ret = i32,
        body = function(base, index)
            return slot_addr_expr(base, index)
        end,
    }

    local reset = funcmod.fn {
        name = name .. "_reset",
        params = { i32 "base" },
        body = function(base)
            local hdr = i32ptr("hdr", base)
            hdr[0] = -1
            hdr[3] = 0
        end,
    }

    return {
        name = name,
        slot_size = slot_size,
        capacity = capacity,
        data_offset = data_offset,
        memory_bytes = data_offset + slot_size * capacity,
        init = init,
        alloc = alloc,
        free = free,
        addr = addr,
        reset = reset,
        funcs = function(self)
            return { self.init, self.alloc, self.free, self.addr, self.reset }
        end,
    }
end

return slab
