-- bench_pvm3.lua — head-to-head: pvm2 vs pvm3
--
-- Same domain for both systems:
--   expression tree -> flat token array
--
-- We compare three usage styles:
--   1) canonical triplet path: pvm2.verb_memo vs pvm3.phase+drain
--   2) append sink terminal:   pvm2.verb_flat vs pvm3.phase+drain_into
--   3) cached root artifact:   pvm2.verb_flat+lower vs pvm3.phase+lower

local pvm2 = require("pvm2")
local pvm3 = require("pvm3")
local T    = pvm2.T

-- ══════════════════════════════════════════════════════════════
--  SETUP: shared ASDL types
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

-- ══════════════════════════════════════════════════════════════
--  VARIANT 1: triplet materialization
-- ══════════════════════════════════════════════════════════════

local emit2_trip
emit2_trip = pvm2.verb_memo("emit2_trip", {
    [CTX.Ex.Lit] = function(node)
        return T.unit(tostring(node.val))
    end,
    [CTX.Ex.BinOp] = function(node)
        return pvm2.concat_all({
            { emit2_trip(node.lhs) },
            { T.unit(node.op) },
            { emit2_trip(node.rhs) },
        })
    end,
})

local emit3
emit3 = pvm3.phase("emit3", {
    [CTX.Ex.Lit] = function(node)
        return pvm3.once(tostring(node.val))
    end,
    [CTX.Ex.BinOp] = function(node)
        local g1, p1, c1 = emit3(node.lhs)
        local g2, p2, c2 = pvm3.once(node.op)
        local g3, p3, c3 = emit3(node.rhs)
        return pvm3.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,
})

local function run_pvm2_trip(root)
    return T.collect(emit2_trip(root))
end

local function run_pvm3_phase(root)
    return pvm3.drain(emit3(root))
end

-- ══════════════════════════════════════════════════════════════
--  VARIANT 2: append into caller-owned array
-- ══════════════════════════════════════════════════════════════

local emit2_flat
emit2_flat = pvm2.verb_flat("emit2_flat", {
    [CTX.Ex.Lit] = function(node, out)
        out[#out + 1] = tostring(node.val)
    end,
    [CTX.Ex.BinOp] = function(node, out)
        emit2_flat(node.lhs, out)
        out[#out + 1] = node.op
        emit2_flat(node.rhs, out)
    end,
})

local function run_pvm2_flat(root)
    local out = {}
    emit2_flat(root, out)
    return out
end

local function run_pvm3_into(root)
    local out = {}
    local g, p, c = emit3(root)
    return pvm3.drain_into(g, p, c, out)
end

-- ══════════════════════════════════════════════════════════════
--  VARIANT 3: cached root artifact
-- ══════════════════════════════════════════════════════════════

local compile2_flat = pvm2.lower("compile2_flat", function(root)
    local out = {}
    emit2_flat(root, out)
    return out
end)

local compile3 = pvm3.lower("compile3", function(root)
    return pvm3.drain(emit3(root))
end)

local function run_pvm2_flat_lower(root)
    return compile2_flat(root)
end

local function run_pvm3_lower(root)
    return compile3(root)
end

-- ══════════════════════════════════════════════════════════════
--  BASELINE
-- ══════════════════════════════════════════════════════════════

local function run_handwritten(root)
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
--  HARNESS
-- ══════════════════════════════════════════════════════════════

local function bench(fn, tree, iters)
    for i = 1, math.min(iters, 50) do fn(tree) end

    local t0 = os.clock()
    local result
    for i = 1, iters do
        result = fn(tree)
    end
    local elapsed = os.clock() - t0
    return elapsed / iters * 1e6, result
end

local function bench_pair(setup_fn, run_fn, tree1, tree2, iters)
    for i = 1, math.min(iters, 30) do
        setup_fn()
        run_fn(tree1)
        run_fn(tree2)
    end

    local t0 = os.clock()
    for i = 1, iters do
        setup_fn()
        run_fn(tree1)
        run_fn(tree2)
    end
    local elapsed = os.clock() - t0
    return elapsed / iters * 1e6
end

local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function fmt_us(us)
    return string.format("%8.1f µs", us)
end

local function print_row(label, us, ref)
    local ratio = ref and string.format("  (%4.2fx hand)", us / ref) or ""
    print(string.format("  %-32s %s%s", label, fmt_us(us), ratio))
end

-- ══════════════════════════════════════════════════════════════
--  RUN
-- ══════════════════════════════════════════════════════════════

for _, depth in ipairs({ 6, 8, 10, 12 }) do
    local tree = make_tree(depth)
    local nodes = 2 ^ (depth + 1) - 1

    local hand = run_handwritten(tree)
    emit2_trip:reset()
    emit2_flat:reset()
    compile2_flat:reset()
    emit3:reset()
    compile3:reset()

    local trip2 = run_pvm2_trip(tree)
    local phase3 = run_pvm3_phase(tree)
    emit2_flat:reset()
    local flat2 = run_pvm2_flat(tree)
    emit3:reset()
    local into3 = run_pvm3_into(tree)
    compile2_flat:reset(); emit2_flat:reset()
    local lower2 = run_pvm2_flat_lower(tree)
    compile3:reset(); emit3:reset()
    local lower3 = run_pvm3_lower(tree)

    assert(same(hand, trip2),  "pvm2 trip mismatch")
    assert(same(hand, phase3), "pvm3 phase mismatch")
    assert(same(hand, flat2),  "pvm2 flat mismatch")
    assert(same(hand, into3),  "pvm3 into mismatch")
    assert(same(hand, lower2), "pvm2 lower mismatch")
    assert(same(hand, lower3), "pvm3 lower mismatch")

    local N = math.max(100, math.floor(50000 / nodes))

    print(string.format("\n═══ depth=%d  nodes=%d  tokens=%d  iters=%d ═══", depth, nodes, #hand, N))

    local cold_hand = bench(run_handwritten, tree, N)

    local cold_pvm2_trip = bench(function(t)
        emit2_trip:reset()
        return run_pvm2_trip(t)
    end, tree, N)

    local cold_pvm3_phase = bench(function(t)
        emit3:reset()
        return run_pvm3_phase(t)
    end, tree, N)

    local cold_pvm2_flat = bench(function(t)
        emit2_flat:reset()
        return run_pvm2_flat(t)
    end, tree, N)

    local cold_pvm3_into = bench(function(t)
        emit3:reset()
        return run_pvm3_into(t)
    end, tree, N)

    local cold_pvm2_lower = bench(function(t)
        emit2_flat:reset()
        compile2_flat:reset()
        return run_pvm2_flat_lower(t)
    end, tree, N)

    local cold_pvm3_lower = bench(function(t)
        emit3:reset()
        compile3:reset()
        return run_pvm3_lower(t)
    end, tree, N)

    emit2_trip:reset(); run_pvm2_trip(tree)
    local warm_pvm2_trip = bench(run_pvm2_trip, tree, N)

    emit3:reset(); run_pvm3_phase(tree)
    local warm_pvm3_phase = bench(run_pvm3_phase, tree, N)

    emit2_flat:reset(); run_pvm2_flat(tree)
    local warm_pvm2_flat = bench(run_pvm2_flat, tree, N)

    emit3:reset(); run_pvm3_into(tree)
    local warm_pvm3_into = bench(run_pvm3_into, tree, N)

    emit2_flat:reset(); compile2_flat:reset(); run_pvm2_flat_lower(tree)
    local warm_pvm2_lower = bench(run_pvm2_flat_lower, tree, N)

    emit3:reset(); compile3:reset(); run_pvm3_lower(tree)
    local warm_pvm3_lower = bench(run_pvm3_lower, tree, N)

    local tree2 = BinOp("+", tree.lhs, pvm3.with(tree.rhs, { lhs = Lit(999) }))

    local inc_pvm2_trip = bench_pair(function()
        emit2_trip:reset()
    end, run_pvm2_trip, tree, tree2, N)

    local inc_pvm3_phase = bench_pair(function()
        emit3:reset()
    end, run_pvm3_phase, tree, tree2, N)

    local inc_pvm2_flat = bench_pair(function()
        emit2_flat:reset()
    end, run_pvm2_flat, tree, tree2, N)

    local inc_pvm3_into = bench_pair(function()
        emit3:reset()
    end, run_pvm3_into, tree, tree2, N)

    local inc_pvm2_lower = bench_pair(function()
        emit2_flat:reset()
        compile2_flat:reset()
    end, run_pvm2_flat_lower, tree, tree2, N)

    local inc_pvm3_lower = bench_pair(function()
        emit3:reset()
        compile3:reset()
    end, run_pvm3_lower, tree, tree2, N)

    print("  cold")
    print_row("handwritten", cold_hand)
    print_row("pvm2 verb_memo + collect", cold_pvm2_trip, cold_hand)
    print_row("pvm3 phase + drain", cold_pvm3_phase, cold_hand)
    print_row("pvm2 verb_flat", cold_pvm2_flat, cold_hand)
    print_row("pvm3 phase + drain_into", cold_pvm3_into, cold_hand)
    print_row("pvm2 verb_flat + lower", cold_pvm2_lower, cold_hand)
    print_row("pvm3 phase + lower", cold_pvm3_lower, cold_hand)

    print("  warm")
    print_row("pvm2 verb_memo + collect", warm_pvm2_trip, cold_hand)
    print_row("pvm3 phase + drain", warm_pvm3_phase, cold_hand)
    print_row("pvm2 verb_flat", warm_pvm2_flat, cold_hand)
    print_row("pvm3 phase + drain_into", warm_pvm3_into, cold_hand)
    print_row("pvm2 verb_flat + lower", warm_pvm2_lower, cold_hand)
    print_row("pvm3 phase + lower", warm_pvm3_lower, cold_hand)

    print("  incremental (tree1 -> tree2, per pair)")
    print_row("pvm2 verb_memo + collect", inc_pvm2_trip, cold_hand)
    print_row("pvm3 phase + drain", inc_pvm3_phase, cold_hand)
    print_row("pvm2 verb_flat", inc_pvm2_flat, cold_hand)
    print_row("pvm3 phase + drain_into", inc_pvm3_into, cold_hand)
    print_row("pvm2 verb_flat + lower", inc_pvm2_lower, cold_hand)
    print_row("pvm3 phase + lower", inc_pvm3_lower, cold_hand)
end

print("\n═══ Cache quality snapshot (depth=10, edit one leaf) ═══")
local tree = make_tree(10)
local tree2 = BinOp("+", tree.lhs, pvm3.with(tree.rhs, { lhs = Lit(999) }))

emit2_trip:reset()
run_pvm2_trip(tree)
run_pvm2_trip(tree2)
print("\npvm2 triplet boundary:")
print(pvm2.report({ emit2_trip }))

emit2_flat:reset(); compile2_flat:reset()
run_pvm2_flat_lower(tree)
run_pvm2_flat_lower(tree2)
print("\npvm2 flat+lower:")
print(pvm2.report({ emit2_flat, compile2_flat }))

emit3:reset()
run_pvm3_phase(tree)
run_pvm3_phase(tree2)
print("\npvm3 phase:")
print(pvm3.report_string({ emit3 }))

emit3:reset(); compile3:reset()
run_pvm3_lower(tree)
run_pvm3_lower(tree2)
print("\npvm3 phase+lower:")
print(pvm3.report_string({ emit3, compile3 }))
