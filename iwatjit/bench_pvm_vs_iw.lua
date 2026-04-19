package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local wj = require("watjit")
local wm = require("watjit.wasmtime")
local iw = require("iwatjit")
local S = require("watjit.stream")

local ffi = require("ffi")

local i32 = wj.i32

local function now_ms()
    return os.clock() * 1000.0
end

local function bench_ms(iters, fn)
    local t0 = now_ms()
    local out
    for _ = 1, iters do
        out = fn()
    end
    return now_ms() - t0, out
end

local function print_case(name, ms, iters)
    print(string.format("%-28s %10.3f ms total   %10.3f us/iter", name, ms, ms * 1000.0 / iters))
end

local function build_balanced_root(nodes, mk_row)
    local level = nodes
    while #level > 1 do
        local next_level = {}
        local j = 1
        local i = 1
        while i <= #level do
            if i == #level then
                next_level[j] = level[i]
                i = i + 1
            else
                next_level[j] = mk_row({ level[i], level[i + 1] })
                i = i + 2
            end
            j = j + 1
        end
        level = next_level
    end
    return level[1]
end

local function build_pvm_case(n)
    local T = pvm.context():Define [[
        module Bench {
            Node = Leaf(number value) unique
                 | Row(Bench.Node* children) unique
        }
    ]]

    local leaves = {}
    local expected = 0
    for i = 1, n do
        local v = ((i * 17) % 29) - 7
        expected = expected + v
        leaves[i] = T.Bench.Leaf(v)
    end
    local root = build_balanced_root(leaves, T.Bench.Row)

    local lower
    lower = pvm.phase("bench_lower", {
        [T.Bench.Leaf] = function(self)
            return pvm.once(self.value)
        end,
        [T.Bench.Row] = function(self)
            return pvm.children(lower, self.children)
        end,
    })

    local function sum_root()
        local g, p, c = lower(root)
        return pvm.fold(g, p, c, 0, function(acc, v)
            return acc + v
        end)
    end

    return {
        T = T,
        root = root,
        lower = lower,
        expected = expected,
        sum = sum_root,
    }
end

local function build_iw_runtime_case(n)
    local T = pvm.context():Define [[
        module Bench {
            Node = Leaf(number value) unique
                 | Row(Bench.Node* children) unique
        }
    ]]

    local rt = iw.runtime()
    local leaves = {}
    local expected = 0
    for i = 1, n do
        local v = ((i * 17) % 29) - 7
        expected = expected + v
        leaves[i] = T.Bench.Leaf(v)
    end
    local root = build_balanced_root(leaves, T.Bench.Row)

    local lower
    lower = iw.phase(rt, "bench_lower", {
        [T.Bench.Leaf] = function(self)
            return S.once(i32, self.value)
        end,
        [T.Bench.Row] = function(self)
            local out = S.empty(i32)
            for i = 1, #self.children do
                out = out:concat(lower(self.children[i]))
            end
            return out
        end,
    })

    local function sum_root()
        return iw.sum(lower(root))
    end

    return {
        rt = rt,
        root = root,
        lower = lower,
        expected = expected,
        sum = sum_root,
    }
end

local function build_iw_machine_case(n)
    local scan = iw.phase {
        name = "bench_scan",
        key_t = i32,
        item_t = i32,

        param = {
            { "data_base", i32 },
            { "count", i32 },
        },

        state = {
            { "i", i32 },
        },

        result = {
            storage = "slab_seq",
            item_t = i32,
        },

        cache = {
            args = "none",
            policy = "ephemeral",
        },

        gen = function(P, S, emit, _R)
            local view = wj.view(i32, P.data_base, "in")
            local code = i32("code", iw.CONTINUE())
            local idx = i32("idx", S.i)
            wj.for_(idx, S.i, P.count, function(loop)
                code(emit(view[idx]))
                wj.if_(code:ne(iw.CONTINUE()), function()
                    loop:break_()
                end)
            end)
            return code
        end,
    }

    local sum_fn = scan:gen_fn {
        name = "bench_iw_sum",
        ret = i32,
        body = function(P, S)
            local acc = i32("acc", 0)
            scan.gen(P, S, function(v)
                acc(acc + v)
                return iw.CONTINUE()
            end, {})
            return acc
        end,
    }

    local bytes = 256 + (n * 4)
    local inst = wj.module({ sum_fn }, { memory_pages = wj.pages_for_bytes(bytes) }):compile(wm.engine())
    local run = inst:fn("bench_iw_sum")
    local mem_base = select(1, inst:memory("memory"))
    local mem_i32 = ffi.cast("int32_t*", mem_base)

    local param_base = 0
    local state_base = 64
    local data_base = 128

    local expected = 0
    for i = 0, n - 1 do
        local v = (((i + 1) * 17) % 29) - 7
        expected = expected + v
        mem_i32[(data_base / 4) + i] = v
    end
    mem_i32[(param_base + scan.Param.offsets.data_base.offset) / 4] = data_base
    mem_i32[(param_base + scan.Param.offsets.count.offset) / 4] = n
    mem_i32[(state_base + scan.State.offsets.i.offset) / 4] = 0

    local function sum_array()
        return run(param_base, state_base)
    end

    return {
        scan = scan,
        expected = expected,
        sum = sum_array,
    }
end

local n = tonumber(arg and arg[1]) or 32768
local iters = tonumber(arg and arg[2]) or 400

local p = build_pvm_case(n)
p.lower:reset()
collectgarbage("collect")
local cold_ms, cold_sum = bench_ms(1, p.sum)
assert(cold_sum == p.expected)

local hit_ms, hit_sum = bench_ms(iters, p.sum)
assert(hit_sum == p.expected)

local ir = build_iw_runtime_case(n)
local ir_cold_ms, ir_cold_sum = bench_ms(1, ir.sum)
assert(ir_cold_sum == ir.expected)
local ir_hit_ms, ir_hit_sum = bench_ms(iters, ir.sum)
assert(ir_hit_sum == ir.expected)

local iwc = build_iw_machine_case(n)
assert(iwc.sum() == iwc.expected)
local iw_ms, iw_sum = bench_ms(iters, iwc.sum)
assert(iw_sum == iwc.expected)

print(string.format("pvm vs iwatjit (n=%d, iters=%d)", n, iters))
print_case("pvm cold miss", cold_ms, 1)
print_case("pvm cached hit", hit_ms, iters)
print_case("iw runtime cold miss", ir_cold_ms, 1)
print_case("iw runtime cached hit", ir_hit_ms, iters)
print_case("iw machine compiled", iw_ms, iters)
print("")
print("pvm report")
print(pvm.report_string({ p.lower }))
print("")
print("iw runtime report")
print(iw.report_string(ir.rt))
print("")
print(string.format("iw machine layouts: Param=%d State=%d Result=%d Entry=%d Cursor=%d",
    iwc.scan.Param.size,
    iwc.scan.State.size,
    iwc.scan.Result.size,
    iwc.scan.Entry.size,
    iwc.scan.Cursor.size))
