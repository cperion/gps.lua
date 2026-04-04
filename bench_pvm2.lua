-- bench_pvm2.lua — head-to-head: pvm vs pvm2
--
-- Tests the SAME domain (expression tree → flat token stream)
-- with both architectures, measuring cold, warm, and incremental.

local pvm  = require("pvm")
local pvm2 = require("pvm2")
local T    = pvm2.T

-- ══════════════════════════════════════════════════════════════
--  SETUP: shared ASDL types
-- ══════════════════════════════════════════════════════════════

local CTX = pvm2.context():Define [[
    module Ex {
        Expr = BinOp(string op, Ex.Expr lhs, Ex.Expr rhs) unique
             | Lit(number val) unique
    }
]]
local BinOp, Lit = CTX.Ex.BinOp, CTX.Ex.Lit

-- Build a balanced binary tree of depth D → 2^(D+1)-1 nodes
local function make_tree(depth)
    if depth <= 0 then return Lit(depth) end
    return BinOp("+", make_tree(depth - 1), make_tree(depth - 1))
end

-- ══════════════════════════════════════════════════════════════
--  PVM APPROACH: verb (tree→tree) + lower (tree→flat)
--  Two boundaries, intermediate "Token" ASDL layer
-- ══════════════════════════════════════════════════════════════

-- Intermediate token type
CTX:Define [[
    module Tok {
        Kind = Num | Op
        Token = (Tok.Kind kind, string text) unique
    }
]]
local K_NUM, K_OP = CTX.Tok.Num, CTX.Tok.Op
local Token = CTX.Tok.Token

-- Boundary 1: verb (Expr → Token list, cached per node)
local expr_to_tokens = pvm.verb("to_toks", {
    [CTX.Ex.Lit] = function(node)
        return { Token(K_NUM, tostring(node.val)) }
    end,
    [CTX.Ex.BinOp] = function(node)
        local lhs = node.lhs:to_toks()
        local rhs = node.rhs:to_toks()
        local out = {}
        for i = 1, #lhs do out[#out + 1] = lhs[i] end
        out[#out + 1] = Token(K_OP, node.op)
        for i = 1, #rhs do out[#out + 1] = rhs[i] end
        return out
    end,
}, { cache = true })

-- Boundary 2: lower (Token list → flat string array)
local compile_pvm = pvm.lower("compile", function(root)
    local tokens = root:to_toks()
    local out = {}
    for i = 1, #tokens do out[i] = tokens[i].text end
    return out
end)

-- Full pvm pipeline
local function run_pvm(root)
    return compile_pvm(root)
end

-- ══════════════════════════════════════════════════════════════
--  PVM2 APPROACH: verb_memo with flat recursive handlers
--  Top-level call still returns T.seq(cached_array), but misses
--  are built via direct array append instead of triplet collect.
-- ══════════════════════════════════════════════════════════════

local emit = pvm2.verb_memo("emit_bench", {
    [CTX.Ex.Lit] = function(node, out)
        out[#out + 1] = tostring(node.val)
    end,
    [CTX.Ex.BinOp] = function(node, out)
        node.lhs:emit_bench(out)
        out[#out + 1] = node.op
        node.rhs:emit_bench(out)
    end,
}, { flat = true })

-- Full pvm2 pipeline
-- verb_memo already materializes to a cached flat array,
-- returned as T.seq(array). For array-oriented consumers,
-- take the param directly instead of re-collecting.
local function run_pvm2(root)
    local _, out = emit(root)
    return out
end

-- ══════════════════════════════════════════════════════════════
--  PVM2 APPROACH 2: verb_iter (uncached, one-shot)
-- ══════════════════════════════════════════════════════════════

local emit_iter = pvm2.verb_iter("emit_iter", {
    [CTX.Ex.Lit] = function(node)
        return T.unit(tostring(node.val))
    end,
    [CTX.Ex.BinOp] = function(node)
        return pvm2.concat_all({
            { node.lhs:emit_iter() },
            { T.unit(node.op) },
            { node.rhs:emit_iter() },
        })
    end,
})

local function run_pvm2_iter(root)
    return T.collect(emit_iter(root))
end

-- ══════════════════════════════════════════════════════════════
--  PVM2 APPROACH 3: verb_flat (cached, array-append, no triplets)
-- ══════════════════════════════════════════════════════════════

local emit_flat = pvm2.verb_flat("emit_flat", {
    [CTX.Ex.Lit] = function(node, out)
        out[#out + 1] = tostring(node.val)
    end,
    [CTX.Ex.BinOp] = function(node, out)
        node.lhs:emit_flat(out)
        out[#out + 1] = node.op
        node.rhs:emit_flat(out)
    end,
})

local function run_pvm2_flat(root)
    local out = {}
    emit_flat(root, out)
    return out
end

-- verb_flat + lower wrapper (zero-cost warm)
local compile_flat = pvm2.lower("compile_flat", function(root)
    local out = {}
    emit_flat(root, out)
    return out
end)

local function run_pvm2_flat_lower(root)
    return compile_flat(root)
end

-- ══════════════════════════════════════════════════════════════
--  BASELINE: hand-written recursive flatten (no framework)
-- ══════════════════════════════════════════════════════════════

local function run_handwritten(root)
    local out, n = {}, 0
    local function go(node)
        if node.kind == "Lit" then
            n = n + 1; out[n] = tostring(node.val)
        elseif node.kind == "BinOp" then
            go(node.lhs)
            n = n + 1; out[n] = node.op
            go(node.rhs)
        end
    end
    go(root)
    return out
end

-- ══════════════════════════════════════════════════════════════
--  HARNESS
-- ══════════════════════════════════════════════════════════════

local function bench(label, fn, tree, iters)
    -- warmup
    for i = 1, math.min(iters, 100) do fn(tree) end

    local t0 = os.clock()
    local result
    for i = 1, iters do
        result = fn(tree)
    end
    local elapsed = os.clock() - t0
    local per_iter = elapsed / iters * 1e6  -- µs
    return per_iter, result, elapsed
end

local function bench_incremental(label, setup_fn, run_fn, tree1, tree2, iters)
    -- prime caches on tree1
    setup_fn()
    run_fn(tree1)

    -- now alternate: run tree2 (incremental from tree1)
    -- tree2 differs in ONE leaf
    for i = 1, math.min(iters, 100) do
        setup_fn()
        run_fn(tree1)
        run_fn(tree2)
    end

    local t0 = os.clock()
    for i = 1, iters do
        setup_fn()
        run_fn(tree1)   -- cold compile, fills caches
        run_fn(tree2)   -- incremental: most nodes cached
    end
    local elapsed = os.clock() - t0
    local per_pair = elapsed / iters * 1e6  -- µs for the pair
    return per_pair, elapsed
end

-- ══════════════════════════════════════════════════════════════
--  RUN
-- ══════════════════════════════════════════════════════════════

for _, depth in ipairs({6, 8, 10, 12}) do
    local tree = make_tree(depth)
    local nodes = 2^(depth+1) - 1
    local tokens = 2^(depth+1) - 1  -- each node emits 1 token

    -- verify correctness
    local r1 = run_pvm(tree)
    local r2 = run_pvm2(tree)
    local r3 = run_handwritten(tree)
    emit_flat:reset()
    local r4 = run_pvm2_flat(tree)
    assert(#r1 == #r2 and #r2 == #r3 and #r3 == #r4,
        string.format("depth=%d: size mismatch %d/%d/%d/%d", depth, #r1, #r2, #r3, #r4))
    for i = 1, #r1 do
        assert(r1[i] == r2[i] and r2[i] == r3[i] and r3[i] == r4[i],
            string.format("depth=%d pos=%d mismatch", depth, i))
    end

    local N = math.max(100, math.floor(50000 / nodes))

    print(string.format("\n═══ depth=%d  nodes=%d  tokens=%d  iters=%d ═══", depth, nodes, #r1, N))

    -- Cold: no cache, first run
    local function reset_all()
        expr_to_tokens:reset()
        compile_pvm:reset()
        emit:reset()
    end

    -- Measure cold compile
    local cold_hand = bench("handwritten", run_handwritten, tree, N)
    
    reset_all()
    local cold_pvm = bench("pvm (cold)", function(t)
        expr_to_tokens:reset(); compile_pvm:reset()
        return run_pvm(t)
    end, tree, N)

    reset_all()
    local cold_pvm2 = bench("pvm2 verb_memo (cold)", function(t)
        emit:reset()
        return run_pvm2(t)
    end, tree, N)

    reset_all()
    local cold_flat = bench("pvm2 verb_flat (cold)", function(t)
        emit_flat:reset()
        return run_pvm2_flat(t)
    end, tree, N)

    local cold_iter = bench("pvm2 verb_iter (no cache)", run_pvm2_iter, tree, N)

    -- Warm: cache fully primed, same tree every call
    reset_all()
    run_pvm(tree)  -- prime
    local warm_pvm = bench("pvm (warm)", run_pvm, tree, N)

    emit:reset()
    run_pvm2(tree)  -- prime
    local warm_pvm2 = bench("pvm2 verb_memo (warm)", run_pvm2, tree, N)

    emit_flat:reset()
    run_pvm2_flat(tree)  -- prime
    local warm_flat = bench("pvm2 verb_flat (warm)", run_pvm2_flat, tree, N)

    compile_flat:reset(); emit_flat:reset()
    run_pvm2_flat_lower(tree)  -- prime
    local warm_flat_lower = bench("pvm2 flat+lower (warm)", run_pvm2_flat_lower, tree, N)

    -- Incremental: change one leaf, measure recompile
    local tree2 = BinOp("+", tree.lhs, pvm2.with(tree.rhs, { lhs = Lit(999) }))

    local inc_pvm = bench_incremental("pvm incremental",
        function() expr_to_tokens:reset(); compile_pvm:reset() end,
        run_pvm, tree, tree2, N)

    local inc_pvm2 = bench_incremental("pvm2 incremental",
        function() emit:reset() end,
        run_pvm2, tree, tree2, N)

    local inc_flat = bench_incremental("pvm2 flat incremental",
        function() emit_flat:reset(); compile_flat:reset() end,
        run_pvm2_flat_lower, tree, tree2, N)

    print(string.format("  %-35s %8.1f µs", "handwritten (no cache)", cold_hand))
    print("  ─────────────────────────────────────────────────")
    print(string.format("  %-35s %8.1f µs", "pvm cold (verb+lower)", cold_pvm))
    print(string.format("  %-35s %8.1f µs", "pvm2 verb_memo cold", cold_pvm2))
    print(string.format("  %-35s %8.1f µs  ←", "pvm2 verb_flat cold", cold_flat))
    print("  ─────────────────────────────────────────────────")
    print(string.format("  %-35s %8.1f µs", "pvm warm (verb+lower)", warm_pvm))
    print(string.format("  %-35s %8.1f µs", "pvm2 verb_memo warm", warm_pvm2))
    print(string.format("  %-35s %8.1f µs", "pvm2 verb_flat warm", warm_flat))
    print(string.format("  %-35s %8.1f µs  ←", "pvm2 verb_flat+lower warm", warm_flat_lower))
    print("  ─────────────────────────────────────────────────")
    print(string.format("  %-35s %8.1f µs/pair", "pvm incremental", inc_pvm))
    print(string.format("  %-35s %8.1f µs/pair", "pvm2 verb_memo incremental", inc_pvm2))
    print(string.format("  %-35s %8.1f µs/pair  ←", "pvm2 verb_flat+lower incremental", inc_flat))
end

-- ══════════════════════════════════════════════════════════════
--  CACHE QUALITY
-- ══════════════════════════════════════════════════════════════

print("\n═══ Cache quality (depth=10, edit one leaf) ═══")
local tree = make_tree(10)
local tree2 = BinOp("+", tree.lhs, pvm2.with(tree.rhs, { lhs = Lit(999) }))

expr_to_tokens:reset(); compile_pvm:reset()
run_pvm(tree); run_pvm(tree2)
print("\npvm (verb + lower):")
print(pvm.report({ expr_to_tokens, compile_pvm }))

emit:reset()
run_pvm2(tree); run_pvm2(tree2)
print("\npvm2 (verb_memo):")
print(pvm2.report({ emit }))
