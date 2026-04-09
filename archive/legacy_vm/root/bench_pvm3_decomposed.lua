-- bench_pvm3_decomposed.lua — separate build/reset/run costs
--
-- Goal: answer whether pvm3 is paying for uncached codegen.
--
-- We split cost into:
--   1) boundary construction
--   2) reset only
--   3) first run after construction (build excluded)
--   4) warm steady-state run
--   5) reset + run (the old "cold-style" benchmark pattern)
--
-- This makes codegen/build cost visible instead of mixing it into runtime.

local pvm2 = require("pvm2")
local pvm3 = require("pvm3")
local T = pvm2.T

-- ══════════════════════════════════════════════════════════════
--  SETUP
-- ══════════════════════════════════════════════════════════════

local CTX = pvm3.context():Define [[
    module Ex {
        Expr = BinOp(string op, Ex.Expr lhs, Ex.Expr rhs) unique
             | Lit(number val) unique
    }
]]
local BinOp, Lit = CTX.Ex.BinOp, CTX.Ex.Lit

local function make_tree(depth)
    if depth <= 0 then return Lit(depth) end
    return BinOp("+", make_tree(depth - 1), make_tree(depth - 1))
end

local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function handwritten(root)
    local out, n = {}, 0
    local function go(node)
        if node.kind == "Lit" then
            n = n + 1
            out[n] = tostring(node.val)
        else
            go(node.lhs)
            n = n + 1
            out[n] = node.op
            go(node.rhs)
        end
    end
    go(root)
    return out
end

-- ══════════════════════════════════════════════════════════════
--  FACTORIES
-- ══════════════════════════════════════════════════════════════

local build_id = 0
local function unique_name(prefix)
    build_id = build_id + 1
    return prefix .. "_" .. build_id
end

local function make_pvm2_trip()
    local name = unique_name("p2_trip")
    local emit
    emit = pvm2.verb_memo(name, {
        [CTX.Ex.Lit] = function(node)
            return T.unit(tostring(node.val))
        end,
        [CTX.Ex.BinOp] = function(node)
            return pvm2.concat_all({
                { emit(node.lhs) },
                { T.unit(node.op) },
                { emit(node.rhs) },
            })
        end,
    })
    return {
        label = "pvm2 verb_memo + collect",
        run = function(root) return T.collect(emit(root)) end,
        reset = function() emit:reset() end,
    }
end

local function make_pvm3_trip()
    local name = unique_name("p3_phase")
    local emit
    emit = pvm3.phase(name, {
        [CTX.Ex.Lit] = function(node)
            return pvm3.once(tostring(node.val))
        end,
        [CTX.Ex.BinOp] = function(node)
            local g1, p1, c1 = emit(node.lhs)
            local g2, p2, c2 = pvm3.once(node.op)
            local g3, p3, c3 = emit(node.rhs)
            return pvm3.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
        end,
    })
    return {
        label = "pvm3 phase + drain",
        run = function(root) return pvm3.drain(emit(root)) end,
        reset = function() emit:reset() end,
    }
end

local function make_pvm2_flat()
    local name = unique_name("p2_flat")
    local emit
    emit = pvm2.verb_flat(name, {
        [CTX.Ex.Lit] = function(node, out)
            out[#out + 1] = tostring(node.val)
        end,
        [CTX.Ex.BinOp] = function(node, out)
            emit(node.lhs, out)
            out[#out + 1] = node.op
            emit(node.rhs, out)
        end,
    })
    return {
        label = "pvm2 verb_flat",
        run = function(root)
            local out = {}
            emit(root, out)
            return out
        end,
        reset = function() emit:reset() end,
    }
end

local function make_pvm3_into()
    local name = unique_name("p3_into")
    local emit
    emit = pvm3.phase(name, {
        [CTX.Ex.Lit] = function(node)
            return pvm3.once(tostring(node.val))
        end,
        [CTX.Ex.BinOp] = function(node)
            local g1, p1, c1 = emit(node.lhs)
            local g2, p2, c2 = pvm3.once(node.op)
            local g3, p3, c3 = emit(node.rhs)
            return pvm3.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
        end,
    })
    return {
        label = "pvm3 phase + drain_into",
        run = function(root)
            local out = {}
            local g, p, c = emit(root)
            return pvm3.drain_into(g, p, c, out)
        end,
        reset = function() emit:reset() end,
    }
end

local function make_pvm2_lower()
    local emit_name = unique_name("p2_flat_lower_emit")
    local compile_name = unique_name("p2_flat_lower_compile")
    local emit
    emit = pvm2.verb_flat(emit_name, {
        [CTX.Ex.Lit] = function(node, out)
            out[#out + 1] = tostring(node.val)
        end,
        [CTX.Ex.BinOp] = function(node, out)
            emit(node.lhs, out)
            out[#out + 1] = node.op
            emit(node.rhs, out)
        end,
    })
    local compile = pvm2.lower(compile_name, function(root)
        local out = {}
        emit(root, out)
        return out
    end)
    return {
        label = "pvm2 verb_flat + lower",
        run = function(root) return compile(root) end,
        reset = function() emit:reset(); compile:reset() end,
    }
end

local function make_pvm3_lower()
    local emit_name = unique_name("p3_lower_emit")
    local compile_name = unique_name("p3_lower_compile")
    local emit
    emit = pvm3.phase(emit_name, {
        [CTX.Ex.Lit] = function(node)
            return pvm3.once(tostring(node.val))
        end,
        [CTX.Ex.BinOp] = function(node)
            local g1, p1, c1 = emit(node.lhs)
            local g2, p2, c2 = pvm3.once(node.op)
            local g3, p3, c3 = emit(node.rhs)
            return pvm3.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
        end,
    })
    local compile = pvm3.lower(compile_name, function(root)
        return pvm3.drain(emit(root))
    end)
    return {
        label = "pvm3 phase + lower",
        run = function(root) return compile(root) end,
        reset = function() emit:reset(); compile:reset() end,
    }
end

local variants = {
    make_pvm2_trip,
    make_pvm3_trip,
    make_pvm2_flat,
    make_pvm3_into,
    make_pvm2_lower,
    make_pvm3_lower,
}

-- ══════════════════════════════════════════════════════════════
--  TIMING HELPERS
-- ══════════════════════════════════════════════════════════════

local function gc_full()
    collectgarbage("collect")
    collectgarbage("collect")
end

local function measure_build(factory, iters)
    gc_full()
    local objs = {}
    local t0 = os.clock()
    for i = 1, iters do
        objs[i] = factory()
    end
    local elapsed = os.clock() - t0
    return elapsed / iters * 1e6, objs
end

local function measure_reset(factory, iters)
    gc_full()
    local obj = factory()
    local t0 = os.clock()
    for i = 1, iters do
        obj.reset()
    end
    local elapsed = os.clock() - t0
    return elapsed / iters * 1e6
end

local function measure_first_run(factory, tree, iters)
    gc_full()
    local objs = {}
    for i = 1, iters do
        objs[i] = factory()
    end
    local sink
    local t0 = os.clock()
    for i = 1, iters do
        sink = objs[i].run(tree)
    end
    local elapsed = os.clock() - t0
    return elapsed / iters * 1e6, sink
end

local function measure_warm(factory, tree, iters)
    gc_full()
    local obj = factory()
    local sink = obj.run(tree) -- prime
    local t0 = os.clock()
    for i = 1, iters do
        sink = obj.run(tree)
    end
    local elapsed = os.clock() - t0
    return elapsed / iters * 1e6, sink
end

local function measure_reset_run(factory, tree, iters)
    gc_full()
    local obj = factory()
    local sink
    local t0 = os.clock()
    for i = 1, iters do
        obj.reset()
        sink = obj.run(tree)
    end
    local elapsed = os.clock() - t0
    return elapsed / iters * 1e6, sink
end

local function fmt(us)
    return string.format("%8.1f µs", us)
end

local function print_row(label, a, b)
    local ratio = b and string.format("  (%4.2fx)", a / b) or ""
    print(string.format("  %-32s %s%s", label, fmt(a), ratio))
end

-- ══════════════════════════════════════════════════════════════
--  SANITY
-- ══════════════════════════════════════════════════════════════

do
    local tree = make_tree(8)
    local ref = handwritten(tree)
    for i = 1, #variants do
        local obj = variants[i]()
        local got = obj.run(tree)
        assert(same(ref, got), obj.label .. " sanity mismatch")
    end
end

-- ══════════════════════════════════════════════════════════════
--  BUILD + RESET COSTS (tree-size independent)
-- ══════════════════════════════════════════════════════════════

print("═══ Boundary construction / reset cost ═══")
for i = 1, #variants do
    local factory = variants[i]
    local probe = factory()
    local build_us = measure_build(factory, 300)
    local reset_us = measure_reset(factory, 300)
    print(string.format("\n%s", probe.label))
    print_row("build", build_us)
    print_row("reset", reset_us)
end

-- ══════════════════════════════════════════════════════════════
--  EXECUTION COSTS
-- ══════════════════════════════════════════════════════════════

for _, depth in ipairs({ 8, 10, 12 }) do
    local tree = make_tree(depth)
    local nodes = 2 ^ (depth + 1) - 1
    local iters = math.max(40, math.floor(40000 / nodes))
    local hand = handwritten(tree)

    print(string.format("\n═══ Execution depth=%d  nodes=%d  tokens=%d  iters=%d ═══", depth, nodes, #hand, iters))

    for i = 1, #variants do
        local factory = variants[i]
        local probe = factory()
        local first_us, first_sink = measure_first_run(factory, tree, iters)
        local warm_us, warm_sink = measure_warm(factory, tree, iters)
        local reset_run_us, reset_run_sink = measure_reset_run(factory, tree, iters)
        assert(same(hand, first_sink), probe.label .. " first-run mismatch")
        assert(same(hand, warm_sink), probe.label .. " warm mismatch")
        assert(same(hand, reset_run_sink), probe.label .. " reset+run mismatch")

        print(string.format("\n%s", probe.label))
        print_row("first run after build", first_us)
        print_row("warm steady-state", warm_us, first_us)
        print_row("reset + run", reset_run_us, first_us)
    end
end
