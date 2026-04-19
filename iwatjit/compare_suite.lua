package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("pvm")
local wj = require("watjit")
local wm = require("watjit.wasmtime")
local iw = require("iwatjit")
local S = require("watjit.stream")

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
    return os.clock() * 1000.0 - t0, out
end

local function print_case(name, ms, iters)
    print(string.format("%-30s %10.3f ms total   %10.3f us/iter", name, ms, ms * 1000.0 / iters))
end

local function build_balanced_root(nodes, mk_row)
    local count_by = {}
    local counts = {}
    for i = 1, #nodes do
        count_by[nodes[i]] = 1
        counts[i] = 1
    end
    local level = nodes
    local level_counts = counts
    while #level > 1 do
        local next_level = {}
        local next_counts = {}
        local j = 1
        local i = 1
        while i <= #level do
            if i == #level then
                next_level[j] = level[i]
                next_counts[j] = level_counts[i]
                i = i + 1
            else
                local row = mk_row({ level[i], level[i + 1] })
                local c = level_counts[i] + level_counts[i + 1]
                count_by[row] = c
                next_level[j] = row
                next_counts[j] = c
                i = i + 2
            end
            j = j + 1
        end
        level = next_level
        level_counts = next_counts
    end
    return level[1], count_by
end

local function pvm_sum(boundary, root)
    local g, p, c = boundary(root)
    return pvm.fold(g, p, c, 0, function(acc, v)
        return acc + v
    end)
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
    local root, counts = build_balanced_root(leaves, T.Bench.Row)

    local lower
    lower = pvm.phase("bench_lower", {
        [T.Bench.Leaf] = function(self)
            return pvm.once(self.value)
        end,
        [T.Bench.Row] = function(self)
            return pvm.children(lower, self.children)
        end,
    })

    local function update(node, idx, new_leaf)
        if pvm.classof(node) == T.Bench.Leaf then
            return new_leaf
        end
        local children = node.children
        local out = {}
        local found = false
        for i = 1, #children do
            local child = children[i]
            local child_n = counts[child]
            if not found and idx <= child_n then
                out[i] = update(child, idx, new_leaf)
                found = true
            else
                out[i] = child
                if not found then
                    idx = idx - child_n
                end
            end
        end
        local row = T.Bench.Row(out)
        counts[row] = counts[node]
        return row
    end

    return {
        T = T,
        lower = lower,
        root = root,
        expected = expected,
        sum = function()
            return pvm_sum(lower, root)
        end,
        update = function(index, value)
            return update(root, index, T.Bench.Leaf(value))
        end,
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
    local root, counts = build_balanced_root(leaves, T.Bench.Row)

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

    local function update(node, idx, value)
        if pvm.classof(node) == T.Bench.Leaf then
            return T.Bench.Leaf(value)
        end
        local children = node.children
        local out = {}
        local found = false
        for i = 1, #children do
            local child = children[i]
            local child_n = counts[child]
            if not found and idx <= child_n then
                out[i] = update(child, idx, value)
                found = true
            else
                out[i] = child
                if not found then
                    idx = idx - child_n
                end
            end
        end
        local row = T.Bench.Row(out)
        counts[row] = counts[node]
        return row
    end

    return {
        rt = rt,
        lower = lower,
        root = root,
        expected = expected,
        sum = function()
            return iw.sum(lower(root))
        end,
        update = function(index, value)
            return update(root, index, value)
        end,
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

        gen = function(P, S0, emit, _R)
            local view = wj.view(i32, P.data_base, "in")
            local code = i32("code", iw.CONTINUE())
            local idx = i32("idx", S0.i)
            wj.for_(idx, S0.i, P.count, function(loop)
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
        body = function(P, S0)
            local acc = i32("acc", 0)
            scan.gen(P, S0, function(v)
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

    return {
        scan = scan,
        expected = expected,
        sum = function()
            return run(param_base, state_base)
        end,
    }
end

local function section(title)
    print("")
    print(("="):rep(72))
    print(title)
    print(("="):rep(72))
end

local function run_throughput(n, iters)
    section(string.format("THROUGHPUT (ASDL-centered, n=%d, iters=%d)", n, iters))

    local p = build_pvm_case(n)
    p.lower:reset()
    collectgarbage("collect")
    local p_cold_ms, p_cold_sum = bench_ms(1, p.sum)
    assert(p_cold_sum == p.expected)
    local p_hit_ms, p_hit_sum = bench_ms(iters, p.sum)
    assert(p_hit_sum == p.expected)

    local ir = build_iw_runtime_case(n)
    local ir_cold_ms, ir_cold_sum = bench_ms(1, ir.sum)
    assert(ir_cold_sum == ir.expected)
    local ir_hit_ms, ir_hit_sum = bench_ms(iters, ir.sum)
    assert(ir_hit_sum == ir.expected)

    local im = build_iw_machine_case(n)
    assert(im.sum() == im.expected)
    local im_ms, im_sum = bench_ms(iters, im.sum)
    assert(im_sum == im.expected)

    print_case("pvm cold miss", p_cold_ms, 1)
    print_case("pvm cached hit", p_hit_ms, iters)
    print_case("iw runtime cold miss", ir_cold_ms, 1)
    print_case("iw runtime cached hit", ir_hit_ms, iters)
    print_case("iw machine compiled", im_ms, iters)

    print("")
    print("pvm report")
    print(pvm.report_string({ p.lower }))
    print("")
    print("iw runtime report")
    print(iw.report_string(ir.rt))
    print("")
    print(string.format("iw machine layouts: Param=%d State=%d Result=%d Entry=%d Cursor=%d",
        im.scan.Param.size,
        im.scan.State.size,
        im.scan.Result.size,
        im.scan.Entry.size,
        im.scan.Cursor.size))
end

local function run_partial(n, iters)
    section(string.format("PARTIAL DRAIN / CANCEL (n=%d, iters=%d)", n, iters))
    print("NOTE: pvm has no explicit cancel primitive; this section shows current behavioral difference,")
    print("not a perfect apples-to-apples terminal comparison.")
    print("")

    do
        local T = pvm.context():Define [[
            module Bench {
                Node = Leaf(number value) unique
                     | Row(Bench.Node* children) unique
            }
        ]]
        local leaves = {}
        for i = 1, n do
            leaves[i] = T.Bench.Leaf(i)
        end
        local root = build_balanced_root(leaves, T.Bench.Row)
        local lower
        lower = pvm.phase("partial_lower", {
            [T.Bench.Leaf] = function(self) return pvm.once(self.value) end,
            [T.Bench.Row] = function(self) return pvm.children(lower, self.children) end,
        })

        local function first_only()
            local g, p, c = lower(root)
            local _, v = g(p, c)
            return v
        end

        assert(first_only() == 1)
        local p_ms, p_val = bench_ms(iters, first_only)
        assert(p_val == 1)
        print_case("pvm first-only pull", p_ms, iters)
        print("pvm partial report")
        print(pvm.report_string({ lower }))
    end

    do
        local T = pvm.context():Define [[
            module Bench {
                Node = Leaf(number value) unique
                     | Row(Bench.Node* children) unique
            }
        ]]
        local rt = iw.runtime()
        local leaves = {}
        for i = 1, n do
            leaves[i] = T.Bench.Leaf(i)
        end
        local root = build_balanced_root(leaves, T.Bench.Row)
        local lower
        lower = iw.phase(rt, "partial_lower", {
            [T.Bench.Leaf] = function(self) return S.once(i32, self.value) end,
            [T.Bench.Row] = function(self)
                local out = S.empty(i32)
                for i = 1, #self.children do
                    out = out:concat(lower(self.children[i]))
                end
                return out
            end,
        })

        local function first_and_cancel()
            local cur = iw.open(lower(root))
            local v = cur:next()
            cur:cancel()
            return v
        end

        assert(first_and_cancel() == 1)
        local iw_ms, iw_val = bench_ms(iters, first_and_cancel)
        assert(iw_val == 1)
        print_case("iw first+cancel", iw_ms, iters)
        print("iw partial report")
        print(iw.report_string(rt))
    end
end

local function run_edit_reuse(n)
    section(string.format("EDIT REUSE (n=%d, single-leaf edit)", n))

    do
        local p = build_pvm_case(n)
        assert(p.sum() == p.expected)
        local edited_root = p.update(math.floor(n / 2), 999)
        local edited_sum = pvm_sum(p.lower, edited_root)
        local expected = p.expected - (((math.floor(n / 2) * 17) % 29) - 7) + 999
        assert(edited_sum == expected)
        print("pvm report after warm + one edit")
        print(pvm.report_string({ p.lower }))
    end

    do
        local ir = build_iw_runtime_case(n)
        assert(ir.sum() == ir.expected)
        local edited_root = ir.update(math.floor(n / 2), 999)
        local edited_sum = iw.sum(ir.lower(edited_root))
        local expected = ir.expected - (((math.floor(n / 2) * 17) % 29) - 7) + 999
        assert(edited_sum == expected)
        print("iw runtime report after warm + one edit")
        print(iw.report_string(ir.rt))
    end
end

local n = tonumber(arg and arg[1]) or 16384
local hit_iters = tonumber(arg and arg[2]) or 300
local partial_iters = tonumber(arg and arg[3]) or 3000

run_throughput(n, hit_iters)
run_partial(math.max(256, math.floor(n / 16)), partial_iters)
run_edit_reuse(math.max(1024, math.floor(n / 4)))
