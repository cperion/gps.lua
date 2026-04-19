package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")

local function has(text, pattern)
    assert(text:find(pattern, 1, true), ("missing %q in:\n%s"):format(pattern, text))
end

local State = wj.enum("State", wj.u8, {
    Empty = 0,
    Live = 1,
    Tomb = 2,
})

local Slot = wj.struct("Slot", {
    { "state", State },
    { "value", wj.u32 },
})

local write_slot = wj.fn {
    name = "write_slot",
    params = { wj.i32 "base", wj.u32 "value" },
    body = function(base, value)
        local slot = Slot.at(base)
        local state = State("state", State.Empty)
        wj.if_(value:eq(0), function()
            state(State.Tomb)
        end, function()
            state(State.Live)
        end)
        slot.state(state)
        slot.value(value)
    end,
}

local is_live = wj.fn {
    name = "is_live",
    params = { wj.i32 "base" },
    ret = wj.i32,
    body = function(base)
        local slot = Slot.at(base)
        return slot.state:eq(State.Live)
    end,
}

local next_state = wj.fn {
    name = "next_state",
    params = { State "state" },
    ret = State,
    body = function(state)
        local out = State("out", State.Empty)
        wj.if_(state:eq(State.Empty), function()
            out(State.Live)
        end, function()
            out(State.Tomb)
        end)
        return out
    end,
}

local mod = wj.module({ write_slot, is_live, next_state })
local wat = mod:wat()

has(wat, '(func $next_state (export "next_state")')
has(wat, '(param $state i32)')
has(wat, '(result i32)')
has(wat, '(local $out i32)')
has(wat, '(local $state i32)')
has(wat, '(i32.store8')
has(wat, '(i32.load8_u')
has(wat, '(i32.eq')

local inst = mod:compile(wm.engine())
local write = inst:fn("write_slot")
local live = inst:fn("is_live")
local next = inst:fn("next_state")
local mem_base = select(1, inst:memory("memory"))
local mem_u8 = ffi.cast("uint8_t*", mem_base)
local value32_at = function(byte_offset)
    return ffi.cast("uint32_t*", mem_base + byte_offset)[0]
end

write(0, 7)
assert(mem_u8[0] == 1)
assert(value32_at(1) == 7)
assert(live(0) == 1)
assert(next(0) == 1)
assert(next(1) == 2)

write(8, 0)
assert(mem_u8[8] == 2)
assert(live(8) == 0)

print("watjit: enum ok")
