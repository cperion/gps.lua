package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local wj = require("watjit")
local wm = require("watjit.wasmtime")
local iw = require("iwatjit")

local i32 = wj.i32
local u8 = wj.u8

local rt = iw.runtime {
    memory = {
        result_bytes = 1024,
        temp_bytes = 256,
    },
    tables = {
        entry_capacity = 64,
    },
}

assert(rt.memory.result_bytes == 1024)
assert(rt.memory.temp_bytes == 256)
assert(rt.tables.entry_capacity == 64)

local lower = iw.phase {
    name = "lower",
    key_t = i32,
    item_t = i32,

    param = {
        { "node", i32 },
        { "max_w", i32 },
    },

    state = {
        { "pc", u8 },
        { "child_i", i32 },
    },

    result = {
        storage = "slab_seq",
        item_t = i32,
        inline_capacity = 4,
    },

    cache = {
        args = "last",
        policy = "bounded_lru",
    },

    gen = function(P, S, emit, _R)
        local code = emit(P.node + P.max_w + S.child_i)
        S.child_i(S.child_i + i32(1))
        return code
    end,
}

assert(lower.Param.size >= 8)
assert(lower.State.size >= 8)
assert(lower.Result.size >= 16)
assert(lower.Entry.size >= 24)
assert(lower.Cursor.size >= 20)
assert(lower.Param.offsets.node.offset == 0)
assert(lower.Param.offsets.max_w.offset == 4)
assert(lower.State.offsets.pc.offset == 0)
assert(lower.State.offsets.child_i.offset == 4)
assert(lower.cache.args == "last")
assert(lower.Status.Live ~= nil)

local solve = iw.scalar_phase {
    name = "solve",
    key_t = i32,
    value_t = i32,

    param = {
        node = i32,
        max_w = i32,
    },

    cache = {
        args = "last",
        policy = "latest_only",
    },

    compute = function(P, extra)
        return P.node + P.max_w + extra
    end,
}

assert(solve.Param.offsets.max_w.offset == 0)
assert(solve.Param.offsets.node.offset == 4)
assert(solve.Result.offsets.value ~= nil)

local draw = iw.terminal {
    name = "draw",
    item_t = i32,
    state = {
        count = i32,
    },
    step = function(S, item)
        S.count(S.count + item)
        return iw.CONTINUE()
    end,
}

assert(draw.State.offsets.count.offset == 0)

local lower_run = lower:gen_fn {
    name = "lower_run",
    params = { i32 "out_base" },
    ret = i32,
    body = function(P, S, out_base)
        local out = wj.view(i32, out_base, "out")
        local written = i32("written", 0)
        return lower.gen(P, S, function(v)
            out[written](v)
            written(written + i32(1))
            return iw.CONTINUE()
        end, {
            rt = rt,
        })
    end,
}

local solve_run = solve:compute_fn {
    name = "solve_run",
    params = { i32 "extra" },
    ret = i32,
    body = function(P, extra)
        return solve.compute(P, extra)
    end,
}

local draw_step = draw:step_fn {
    name = "draw_step",
    params = { i32 "item" },
    ret = i32,
    body = function(S, item)
        return draw.step(S, item)
    end,
}

local mod = wj.module({ lower_run, solve_run, draw_step })
local inst = mod:compile(wm.engine())
local run_lower = inst:fn("lower_run")
local run_solve = inst:fn("solve_run")
local run_draw = inst:fn("draw_step")
local mem_base = select(1, inst:memory("memory"))
local mem_i32 = ffi.cast("int32_t*", mem_base)
local mem_u8 = ffi.cast("uint8_t*", mem_base)

local param_base = 0
local state_base = 64
local out_base = 128
local draw_state_base = 192

mem_i32[(param_base + lower.Param.offsets.node.offset) / 4] = 7
mem_i32[(param_base + lower.Param.offsets.max_w.offset) / 4] = 10
mem_u8[state_base + lower.State.offsets.pc.offset] = 1
mem_i32[(state_base + lower.State.offsets.child_i.offset) / 4] = 3

assert(run_lower(param_base, state_base, out_base) == iw.CONTINUE_VALUE)
assert(mem_i32[out_base / 4] == 20)
assert(mem_i32[(state_base + lower.State.offsets.child_i.offset) / 4] == 4)

mem_i32[(param_base + solve.Param.offsets.max_w.offset) / 4] = 5
mem_i32[(param_base + solve.Param.offsets.node.offset) / 4] = 2
assert(run_solve(param_base, 9) == 16)

mem_i32[draw_state_base / 4] = 11
assert(run_draw(draw_state_base, 4) == iw.CONTINUE_VALUE)
assert(mem_i32[draw_state_base / 4] == 15)

print("iwatjit: machine spec prototype ok")
