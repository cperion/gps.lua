local types = require("watjit.types")
local ctrl = require("watjit.ctrl")
local funcmod = require("watjit.func")

local function lru(name, capacity)
    assert(type(name) == "string", "lru name must be a string")
    assert(type(capacity) == "number" and capacity >= 0, "lru capacity must be a non-negative number")

    local i32 = types.i32
    local i32ptr = types.ptr(i32)

    local header_words = 3
    local meta_words = 3
    local data_offset = header_words * 4
    local meta_stride = meta_words * 4

    local function meta_addr(base, index)
        return base + i32(data_offset) + index * i32(meta_stride)
    end

    local init = funcmod.fn {
        name = name .. "_init",
        params = { i32 "base" },
        body = function(base)
            local hdr = i32ptr("hdr", base)
            local i = i32("i")

            hdr[0] = -1
            hdr[1] = -1
            hdr[2] = capacity

            ctrl.for_(i, i32(capacity), function()
                local meta_base = i32("meta_base", meta_addr(base, i))
                local meta = i32ptr("meta", meta_base)
                meta[0] = -1
                meta[1] = -1
                meta[2] = 0
            end)
        end,
    }

    local push_head = funcmod.fn {
        name = name .. "_push_head",
        params = { i32 "base", i32 "index" },
        body = function(base, index)
            local hdr = i32ptr("hdr", base)
            local old_head = i32("old_head", hdr[0])
            local meta_base = i32("meta_base", meta_addr(base, index))
            local meta = i32ptr("meta", meta_base)

            meta[0] = -1
            meta[1] = old_head
            meta[2] = 1

            ctrl.if_(old_head:ne(-1), function()
                local old_base = i32("old_base", meta_addr(base, old_head))
                local old_meta = i32ptr("old_meta", old_base)
                old_meta[0] = index
            end, function()
                hdr[1] = index
            end)

            hdr[0] = index
        end,
    }

    local remove = funcmod.fn {
        name = name .. "_remove",
        params = { i32 "base", i32 "index" },
        body = function(base, index)
            local hdr = i32ptr("hdr", base)
            local meta_base = i32("meta_base", meta_addr(base, index))
            local meta = i32ptr("meta", meta_base)
            local prev = i32("prev", meta[0])
            local next_ = i32("next_", meta[1])
            local linked = i32("linked", meta[2])

            ctrl.if_(linked:ne(0), function()
                ctrl.if_(prev:ne(-1), function()
                    local prev_base = i32("prev_base", meta_addr(base, prev))
                    local prev_meta = i32ptr("prev_meta", prev_base)
                    prev_meta[1] = next_
                end, function()
                    hdr[0] = next_
                end)

                ctrl.if_(next_:ne(-1), function()
                    local next_base = i32("next_base", meta_addr(base, next_))
                    local next_meta = i32ptr("next_meta", next_base)
                    next_meta[0] = prev
                end, function()
                    hdr[1] = prev
                end)

                meta[0] = -1
                meta[1] = -1
                meta[2] = 0
            end)
        end,
    }

    local touch = funcmod.fn {
        name = name .. "_touch",
        params = { i32 "base", i32 "index" },
        body = function(base, index)
            local hdr = i32ptr("hdr", base)
            ctrl.if_(hdr[0]:ne(index), function()
                remove(base, index)
                push_head(base, index)
            end)
        end,
    }

    local pop_tail = funcmod.fn {
        name = name .. "_pop_tail",
        params = { i32 "base" },
        ret = i32,
        body = function(base)
            local hdr = i32ptr("hdr", base)
            local old_tail = i32("old_tail", hdr[1])
            local out = i32("out", -1)

            ctrl.if_(old_tail:ne(-1), function()
                out(old_tail)
                remove(base, old_tail)
            end)

            return out
        end,
    }

    local head = funcmod.fn {
        name = name .. "_head",
        params = { i32 "base" },
        ret = i32,
        body = function(base)
            return i32ptr("hdr", base)[0]
        end,
    }

    local tail = funcmod.fn {
        name = name .. "_tail",
        params = { i32 "base" },
        ret = i32,
        body = function(base)
            return i32ptr("hdr", base)[1]
        end,
    }

    local is_linked = funcmod.fn {
        name = name .. "_is_linked",
        params = { i32 "base", i32 "index" },
        ret = i32,
        body = function(base, index)
            local meta = i32ptr("meta", meta_addr(base, index))
            return meta[2]
        end,
    }

    local reset = funcmod.fn {
        name = name .. "_reset",
        params = { i32 "base" },
        body = function(base)
            init(base)
        end,
    }

    return {
        name = name,
        capacity = capacity,
        data_offset = data_offset,
        meta_stride = meta_stride,
        memory_bytes = data_offset + capacity * meta_stride,
        init = init,
        push_head = push_head,
        remove = remove,
        touch = touch,
        pop_tail = pop_tail,
        head = head,
        tail = tail,
        is_linked = is_linked,
        reset = reset,
        funcs = function(self)
            return {
                self.init,
                self.push_head,
                self.remove,
                self.touch,
                self.pop_tail,
                self.head,
                self.tail,
                self.is_linked,
                self.reset,
            }
        end,
    }
end

return lru
