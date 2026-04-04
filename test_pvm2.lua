-- test_pvm2.lua — tests for pvm2: the triangle (Quote × ASDL × Triplet)

local pvm2 = require("pvm2")
local T = pvm2.T

local pass, fail = 0, 0
local function check(cond, name)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        io.write("  FAIL: " .. name .. "\n")
    end
end

local function section(name)
    io.write("── " .. name .. " ──\n")
end

-- ══════════════════════════════════════════════════════════════
--  Setup: ASDL types for testing
-- ══════════════════════════════════════════════════════════════

local CTX = pvm2.context():Define [[
    module Ex {
        Expr = BinOp(string op, Ex.Expr lhs, Ex.Expr rhs) unique
             | Lit(number val) unique
             | Call(string name, Ex.Expr* args) unique
    }
]]

-- shortcuts
local BinOp = CTX.Ex.BinOp
local Lit   = CTX.Ex.Lit
local Call  = CTX.Ex.Call

--  build test tree:  (1 + (2 * 3))
local tree = BinOp("+", Lit(1), BinOp("*", Lit(2), Lit(3)))
-- bigger tree: call("f", 1, (2+3))
local tree2 = Call("f", { Lit(1), BinOp("+", Lit(2), Lit(3)) })

-- ══════════════════════════════════════════════════════════════
--  TEST: pvm2.pipe (Pattern 1)
-- ══════════════════════════════════════════════════════════════
section("pvm2.pipe")

do  -- basic value pipe
    local double = function(x) return x * 2 end
    local inc    = function(x) return x + 1 end
    local p = pvm2.pipe("dbl_inc", double, inc)
    check(p(5) == 11, "pipe(5) = 11")
    check(p(0) == 1,  "pipe(0) = 1")
    local s = p:stats()
    check(s.calls == 2, "pipe stats.calls == 2")
    check(s.name == "dbl_inc", "pipe stats.name")
end

do  -- single stage
    local p = pvm2.pipe(function(x) return x * 3 end)
    check(p(7) == 21, "single stage pipe")
end

do  -- pipe with triplet transition
    local expand = function(x) return T.range(1, x) end
    local p = pvm2.pipe("expand", expand)
    local g, param, ctrl = p(3)
    local result = T.collect(g, param, ctrl)
    check(#result == 3, "pipe → triplet expansion count")
    check(result[1] == 1 and result[3] == 3, "pipe → triplet values")
end

do  -- multi-stage with triplet transition
    local expand = function(x) return T.range(1, x) end
    local p = pvm2.pipe("exp_map",
        function(x) return x * 2 end,   -- value → value
        expand,                           -- value → triplet
        function(g, p, c) return T.map(function(v) return v * 10 end, g, p, c) end  -- iter → iter
    )
    local g, param, ctrl = p(3)
    local result = T.collect(g, param, ctrl)
    check(#result == 6, "multi-stage pipe count=6")
    check(result[1] == 10 and result[6] == 60, "multi-stage pipe values")
end

do  -- source is inspectable
    local p = pvm2.pipe("src_test", function(x) return x end, function(x) return x end)
    check(type(p.source) == "string", "pipe .source is string")
    check(p.source:find("stage_1") ~= nil, "pipe source mentions stage_1")
end

do  -- derived name + all_stats mirror pvm.pipe introspection
    local stage1 = setmetatable({ name = "s1" }, {
        __call = function(_, x) return x + 1 end,
    })
    local stage2 = setmetatable({ name = "s2" }, {
        __call = function(_, x) return x * 2 end,
    })
    local p = pvm2.pipe(stage1, stage2)
    check(p(3) == 8, "pipe derived-name result")
    check(p:stats().name == "s1 → s2", "pipe derived name")
    local all = p:all_stats()
    check(#all == 2, "pipe all_stats count")
    check(all[1].name == "s1" and all[2].name == "s2", "pipe all_stats names")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: pvm2.pipe_typed
-- ══════════════════════════════════════════════════════════════
section("pvm2.pipe_typed")

do
    local p = pvm2.pipe_typed("typed_test", {
        { fn = function(x) return x * 2 end,          mode = "value" },
        { fn = function(x) return T.range(1, x) end,  mode = "expand" },
    })
    local g, param, ctrl = p(3)
    local result = T.collect(g, param, ctrl)
    -- 3*2 = 6, range(1,6) = {1,2,3,4,5,6}
    check(#result == 6, "pipe_typed count=6")
    check(result[1] == 1 and result[6] == 6, "pipe_typed values")
end

do  -- iter mode
    local p = pvm2.pipe_typed("iter_mode", {
        { fn = function(x) return T.seq({x, x+1, x+2}) end, mode = "expand" },
        { fn = function(g, p, c) return T.map(function(v) return v * 10 end, g, p, c) end, mode = "iter" },
    })
    local g, param, ctrl = p(1)
    local result = T.collect(g, param, ctrl)
    check(#result == 3, "pipe_typed iter mode count")
    check(result[1] == 10 and result[2] == 20 and result[3] == 30, "pipe_typed iter mode values")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: pvm2.cmds / pvm2.cmds_rev (Pattern 5)
-- ══════════════════════════════════════════════════════════════
section("pvm2.cmds / pvm2.cmds_rev")

do
    local arr = { "a", "b", "c", "d" }

    local fwd = T.collect(pvm2.cmds(arr))
    check(#fwd == 4, "cmds forward count")
    check(fwd[1] == "a" and fwd[4] == "d", "cmds forward order")

    local rev = T.collect(pvm2.cmds_rev(arr))
    check(#rev == 4, "cmds_rev count")
    check(rev[1] == "d" and rev[4] == "a", "cmds_rev order")
end

do  -- explicit n
    local arr = { 10, 20, 30, 40, 50 }
    local partial = T.collect(pvm2.cmds(arr, 3))
    check(#partial == 3, "cmds explicit n=3")
    check(partial[3] == 30, "cmds explicit n value")

    local rpartial = T.collect(pvm2.cmds_rev(arr, 3))
    check(#rpartial == 3, "cmds_rev explicit n=3")
    check(rpartial[1] == 30 and rpartial[3] == 10, "cmds_rev explicit n values")
end

do  -- empty
    local e = T.collect(pvm2.cmds({}))
    check(#e == 0, "cmds empty")
    local er = T.collect(pvm2.cmds_rev({}))
    check(#er == 0, "cmds_rev empty")
end

do  -- composable with triplet combinators
    local arr = { 1, 2, 3, 4, 5, 6 }
    local evens = T.collect(T.filter(function(x) return x % 2 == 0 end, pvm2.cmds(arr)))
    check(#evens == 3, "cmds + T.filter count")
    check(evens[1] == 2 and evens[2] == 4 and evens[3] == 6, "cmds + T.filter values")

    local first3 = T.collect(T.take(3, pvm2.cmds(arr)))
    check(#first3 == 3, "cmds + T.take")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: pvm2.concat_all
-- ══════════════════════════════════════════════════════════════
section("pvm2.concat_all")

do
    local result = T.collect(pvm2.concat_all({
        { T.unit(1) },
        { T.seq({ 2, 3 }) },
        { T.unit(4) },
    }))
    check(#result == 4, "concat_all count=4")
    check(result[1] == 1 and result[2] == 2 and result[3] == 3 and result[4] == 4,
          "concat_all values")
end

do  -- single triplet
    local result = T.collect(pvm2.concat_all({ { T.seq({10, 20}) } }))
    check(#result == 2, "concat_all single")
end

do  -- empty list
    local result = T.collect(pvm2.concat_all({}))
    check(#result == 0, "concat_all empty")
end

do  -- many triplets
    local trips = {}
    for i = 1, 100 do
        trips[i] = { T.unit(i) }
    end
    local result = T.collect(pvm2.concat_all(trips))
    check(#result == 100, "concat_all 100 triplets")
    check(result[1] == 1 and result[100] == 100, "concat_all 100 values")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: pvm2.fuse_maps (Pattern 6)
-- ══════════════════════════════════════════════════════════════
section("pvm2.fuse_maps")

do  -- pure maps
    local chain = pvm2.fuse_maps("dbl_inc", {
        function(x) return x * 2 end,
        function(x) return x + 1 end,
    })
    local result = T.collect(chain(T.seq({ 1, 2, 3 })))
    check(#result == 3, "fuse pure maps count")
    check(result[1] == 3 and result[2] == 5 and result[3] == 7, "fuse pure maps values")
end

do  -- map + filter
    local chain = pvm2.fuse_maps("map_filt", {
        function(x) return x * 2 end,
        { filter = function(x) return x > 4 end },
        function(x) return x + 100 end,
    })
    local result = T.collect(chain(T.seq({ 1, 2, 3, 4, 5 })))
    -- 1→2(skip) 2→4(skip) 3→6→106 4→8→108 5→10→110
    check(#result == 3, "fuse map+filter count")
    check(result[1] == 106 and result[2] == 108 and result[3] == 110, "fuse map+filter values")
end

do  -- multiple filters
    local chain = pvm2.fuse_maps("multi_filt", {
        { filter = function(x) return x > 2 end },
        { filter = function(x) return x < 5 end },
    })
    local result = T.collect(chain(T.seq({ 1, 2, 3, 4, 5, 6 })))
    check(#result == 2, "fuse multi-filter count")
    check(result[1] == 3 and result[2] == 4, "fuse multi-filter values")
end

do  -- stats
    local chain = pvm2.fuse_maps("stats_test", {
        function(x) return x end,
    })
    chain(T.seq({ 1, 2 }))
    chain(T.seq({ 3, 4, 5 }))
    local s = chain:stats()
    check(s.calls == 2, "fuse stats.calls")
    check(s.name == "stats_test", "fuse stats.name")
end

do  -- source is inspectable
    local chain = pvm2.fuse_maps("src_chk", {
        function(x) return x end,
        { filter = function(x) return true end },
    })
    check(type(chain.source) == "string", "fuse .source is string")
    check(chain.source:find("do return") ~= nil, "fuse source has guarded return")
end

do  -- fuse_pipeline convenience
    local g, p, c = pvm2.fuse_pipeline("conv", T.seq({1,2,3}), nil, nil, {
        function(x) return x * 10 end,
    })
    -- Note: fuse_pipeline takes name, then the fuse_maps stages handle
    -- Wait, the API is fuse_pipeline(name, g, p, c, stages)
    -- T.seq returns g, p, c — need to unpack
end

do  -- fuse_pipeline (correct usage)
    local sg, sp, sc = T.seq({ 1, 2, 3 })
    local g, p, c = pvm2.fuse_pipeline("conv", sg, sp, sc, {
        function(x) return x * 10 end,
    })
    local result = T.collect(g, p, c)
    check(#result == 3, "fuse_pipeline count")
    check(result[1] == 10 and result[3] == 30, "fuse_pipeline values")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: pvm2.walk (Pattern 3 — generic)
-- ══════════════════════════════════════════════════════════════
section("pvm2.walk (generic)")

do  -- simple tree: BinOp("+", Lit(1), BinOp("*", Lit(2), Lit(3)))
    local nodes = T.collect(pvm2.walk(tree, CTX.definitions))
    check(#nodes == 5, "walk node count=5")
    -- pre-order DFS: BinOp+, Lit1, BinOp*, Lit2, Lit3
    check(nodes[1] == tree, "walk root first")
    check(nodes[1].kind == "BinOp" and nodes[1].op == "+", "walk root is BinOp+")
    check(nodes[2].kind == "Lit" and nodes[2].val == 1, "walk second is Lit(1)")
    check(nodes[3].kind == "BinOp" and nodes[3].op == "*", "walk third is BinOp*")
    check(nodes[4].kind == "Lit" and nodes[4].val == 2, "walk fourth is Lit(2)")
    check(nodes[5].kind == "Lit" and nodes[5].val == 3, "walk fifth is Lit(3)")
end

do  -- tree with list field: Call("f", {Lit(1), BinOp("+", Lit(2), Lit(3))})
    local nodes = T.collect(pvm2.walk(tree2, CTX.definitions))
    check(#nodes == 5, "walk Call tree count=5")
    check(nodes[1].kind == "Call", "walk Call root")
    check(nodes[2].kind == "Lit" and nodes[2].val == 1, "walk Call arg1")
    check(nodes[3].kind == "BinOp", "walk Call arg2")
    check(nodes[4].kind == "Lit" and nodes[4].val == 2, "walk Call arg2.lhs")
    check(nodes[5].kind == "Lit" and nodes[5].val == 3, "walk Call arg2.rhs")
end

do  -- leaf only
    local nodes = T.collect(pvm2.walk(Lit(42), CTX.definitions))
    check(#nodes == 1, "walk single leaf")
    check(nodes[1].val == 42, "walk leaf value")
end

do  -- composable with triplet combinators
    local lits = T.collect(T.filter(
        function(n) return n.kind == "Lit" end,
        pvm2.walk(tree, CTX.definitions)
    ))
    check(#lits == 3, "walk + filter lits count")
    check(lits[1].val == 1 and lits[2].val == 2 and lits[3].val == 3, "walk + filter lit values")
end

do  -- T.take over walk
    local first2 = T.collect(T.take(2, pvm2.walk(tree, CTX.definitions)))
    check(#first2 == 2, "walk + take(2)")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: pvm2.walk_gen (Pattern 3 — code-generated)
-- ══════════════════════════════════════════════════════════════
section("pvm2.walk_gen (codegen)")

do
    local walker = pvm2.walk_gen(CTX.Ex.Expr, CTX.definitions)

    -- same tree as generic walk
    local nodes = T.collect(walker(tree))
    check(#nodes == 5, "walk_gen node count=5")
    check(nodes[1].kind == "BinOp" and nodes[1].op == "+", "walk_gen root")
    check(nodes[2].kind == "Lit" and nodes[2].val == 1, "walk_gen lhs")
    check(nodes[3].kind == "BinOp" and nodes[3].op == "*", "walk_gen inner")
    check(nodes[4].kind == "Lit" and nodes[4].val == 2, "walk_gen inner.lhs")
    check(nodes[5].kind == "Lit" and nodes[5].val == 3, "walk_gen inner.rhs")

    -- matches generic walk exactly
    local generic = T.collect(pvm2.walk(tree, CTX.definitions))
    local codegen = T.collect(walker(tree))
    check(#generic == #codegen, "walk_gen matches generic count")
    local all_match = true
    for i = 1, #generic do
        if generic[i] ~= codegen[i] then all_match = false end
    end
    check(all_match, "walk_gen matches generic identity")
end

do  -- Call tree
    local walker = pvm2.walk_gen(CTX.Ex.Expr, CTX.definitions)
    local nodes = T.collect(walker(tree2))
    check(#nodes == 5, "walk_gen Call tree count")
    check(nodes[1].kind == "Call", "walk_gen Call root")
    check(nodes[2].val == 1, "walk_gen Call first arg")
end

do  -- source is inspectable
    local walker = pvm2.walk_gen(CTX.Ex.Expr, CTX.definitions)
    check(type(walker.source) == "string", "walk_gen .source is string")
    check(walker.source:find("walk_gen") ~= nil, "walk_gen source has function name")
end

do  -- composable
    local walker = pvm2.walk_gen(CTX.Ex.Expr, CTX.definitions)
    local count = T.count(T.filter(
        function(n) return n.kind == "Lit" end,
        walker(tree)
    ))
    check(count == 3, "walk_gen + filter count lits")
end

do  -- robustness: generated walker matches generic nil-list handling
    local mt = getmetatable(Call("walk_nil_guard", {}))
    local broken = setmetatable({ kind = "Call", name = "walk_nil_guard", args = nil }, mt)
    local generic = T.collect(pvm2.walk(broken, CTX.definitions))
    local walker = pvm2.walk_gen(CTX.Ex.Expr, CTX.definitions)
    local ok, codegen = pcall(function() return T.collect(walker(broken)) end)
    check(ok, "walk_gen tolerates nil list fields")
    if ok then
        check(#codegen == #generic, "walk_gen nil-list count matches generic")
        check(codegen[1] == broken and generic[1] == broken, "walk_gen nil-list yields root")
    end
end

-- ══════════════════════════════════════════════════════════════
--  TEST: pvm2.verb_iter (Pattern 2)
-- ══════════════════════════════════════════════════════════════
section("pvm2.verb_iter")

do
    -- "tokenize": flatten an expression tree to an infix token stream
    local tokenize = pvm2.verb_iter("tokens", {
        [CTX.Ex.Lit] = function(node)
            return T.unit(tostring(node.val))
        end,
        [CTX.Ex.BinOp] = function(node)
            return pvm2.concat_all({
                { node.lhs:tokens() },
                { T.unit(node.op) },
                { node.rhs:tokens() },
            })
        end,
        [CTX.Ex.Call] = function(node)
            -- name ( arg1, arg2, ... )
            local parts = { { T.unit(node.name) }, { T.unit("(") } }
            for i, arg in ipairs(node.args) do
                if i > 1 then parts[#parts + 1] = { T.unit(",") } end
                parts[#parts + 1] = { arg:tokens() }
            end
            parts[#parts + 1] = { T.unit(")") }
            return pvm2.concat_all(parts)
        end,
    })

    -- tree = BinOp("+", Lit(1), BinOp("*", Lit(2), Lit(3)))
    -- infix: 1 + 2 * 3
    local tokens = T.collect(tokenize(tree))
    check(#tokens == 5, "verb_iter token count=5")
    check(tokens[1] == "1", "verb_iter tok[1]")
    check(tokens[2] == "+", "verb_iter tok[2]")
    check(tokens[3] == "2", "verb_iter tok[3]")
    check(tokens[4] == "*", "verb_iter tok[4]")
    check(tokens[5] == "3", "verb_iter tok[5]")
end

do  -- method syntax
    local tokens = T.collect(tree:tokens())
    check(#tokens == 5, "verb_iter method syntax count")
    check(table.concat(tokens, " ") == "1 + 2 * 3", "verb_iter method syntax string")
end

do  -- Call tree: f(1, 2+3)
    local tokens = T.collect(tree2:tokens())
    local s = table.concat(tokens, " ")
    check(s == "f ( 1 , 2 + 3 )", "verb_iter Call tokens: " .. s)
end

do  -- stats
    local s = pvm2.verb_iter("count_calls", {
        [CTX.Ex.Lit]   = function(n) return T.unit(n.val) end,
        [CTX.Ex.BinOp] = function(n) return T.unit(n.op) end,
        [CTX.Ex.Call]   = function(n) return T.unit(n.name) end,
    })
    T.collect(s(Lit(1)))
    T.collect(s(Lit(2)))
    T.collect(s(BinOp("+", Lit(1), Lit(2))))
    local st = s:stats()
    check(st.calls == 3, "verb_iter stats.calls")
end

do  -- source inspectable
    local s = pvm2.verb_iter("src_vi", {
        [CTX.Ex.Lit]   = function(n) return T.unit(n.val) end,
        [CTX.Ex.BinOp] = function(n) return T.unit(n.op) end,
        [CTX.Ex.Call]   = function(n) return T.unit(n.name) end,
    })
    check(type(s.source) == "string", "verb_iter .source")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: pvm2.verb_memo — the key primitive
-- ══════════════════════════════════════════════════════════════
section("pvm2.verb_memo")

do  -- basic: cached dispatch returning sequences
    local emit = pvm2.verb_memo("emit", {
        [CTX.Ex.Lit] = function(node)
            return T.unit(tostring(node.val))
        end,
        [CTX.Ex.BinOp] = function(node)
            return pvm2.concat_all({
                { node.lhs:emit() },
                { T.unit(node.op) },
                { node.rhs:emit() },
            })
        end,
        [CTX.Ex.Call] = function(node)
            local parts = { { T.unit(node.name .. "(") } }
            for i, arg in ipairs(node.args) do
                if i > 1 then parts[#parts + 1] = { T.unit(",") } end
                parts[#parts + 1] = { arg:emit() }
            end
            parts[#parts + 1] = { T.unit(")") }
            return pvm2.concat_all(parts)
        end,
    })

    -- tree = BinOp("+", Lit(1), BinOp("*", Lit(2), Lit(3)))
    local result = T.collect(emit(tree))
    check(#result == 5, "verb_memo basic count")
    check(table.concat(result, " ") == "1 + 2 * 3", "verb_memo basic values")
end

do  -- CACHE HITS: same node → cached result
    local call_count = 0
    local emit2 = pvm2.verb_memo("emit2", {
        [CTX.Ex.Lit] = function(node)
            call_count = call_count + 1
            return T.unit(node.val)
        end,
        [CTX.Ex.BinOp] = function(node)
            call_count = call_count + 1
            return pvm2.concat_all({
                { node.lhs:emit2() },
                { T.unit(node.op) },
                { node.rhs:emit2() },
            })
        end,
        [CTX.Ex.Call] = function(node)
            call_count = call_count + 1
            return T.unit(node.name)
        end,
    })

    -- First call: all handlers run
    call_count = 0
    local r1 = T.collect(emit2(tree))
    local first_calls = call_count
    check(first_calls == 5, "verb_memo first call: 5 handlers ran")

    -- Second call: SAME tree → ALL cache hits, zero handlers run
    call_count = 0
    local r2 = T.collect(emit2(tree))
    check(call_count == 0, "verb_memo same tree: 0 handlers ran")
    check(#r2 == #r1, "verb_memo cached result same length")

    local s = emit2:stats()
    check(s.hits > 0, "verb_memo stats show hits")
end

do  -- STRUCTURAL INCREMENTALITY: change one leaf, only that path recomputes
    local handler_calls = {}
    local emit3 = pvm2.verb_memo("emit3", {
        [CTX.Ex.Lit] = function(node)
            handler_calls[#handler_calls + 1] = "Lit(" .. node.val .. ")"
            return T.unit(node.val)
        end,
        [CTX.Ex.BinOp] = function(node)
            handler_calls[#handler_calls + 1] = "BinOp(" .. node.op .. ")"
            return pvm2.concat_all({
                { node.lhs:emit3() },
                { T.unit(node.op) },
                { node.rhs:emit3() },
            })
        end,
        [CTX.Ex.Call] = function(node)
            handler_calls[#handler_calls + 1] = "Call(" .. node.name .. ")"
            return T.unit(node.name)
        end,
    })

    -- tree = BinOp("+", Lit(1), BinOp("*", Lit(2), Lit(3)))
    -- First call: populates all caches
    handler_calls = {}
    T.collect(emit3(tree))
    check(#handler_calls == 5, "verb_memo initial: all 5 handlers")

    -- Now change ONLY Lit(3) → Lit(99)
    -- tree2 = BinOp("+", Lit(1), BinOp("*", Lit(2), Lit(99)))
    local tree2 = BinOp("+", Lit(1), BinOp("*", Lit(2), Lit(99)))

    handler_calls = {}
    local r = T.collect(emit3(tree2))

    -- What should re-run:
    --   Lit(99)      — new node, cache miss
    --   BinOp("*")   — new node (different rhs), cache miss
    --   BinOp("+")   — new node (different rhs), cache miss
    -- What should NOT re-run:
    --   Lit(1)       — SAME object → cache hit
    --   Lit(2)       — SAME object → cache hit
    check(#handler_calls == 3, "verb_memo incremental: only 3 handlers re-ran (got " .. #handler_calls .. ")")

    -- Verify the changed path
    local found_lit99 = false
    local found_lit1 = false
    for _, h in ipairs(handler_calls) do
        if h == "Lit(99)" then found_lit99 = true end
        if h == "Lit(1)" then found_lit1 = true end
    end
    check(found_lit99, "verb_memo incremental: Lit(99) DID run")
    check(not found_lit1, "verb_memo incremental: Lit(1) did NOT run")

    -- Verify correct result
    check(r[1] == 1 and r[3] == 2 and r[5] == 99, "verb_memo incremental: correct output")
    check(r[2] == "+" and r[4] == "*", "verb_memo incremental: ops correct")
end

do  -- method syntax works
    -- emit was installed earlier on the types
    local r = T.collect(Lit(42):emit())
    check(#r == 1 and r[1] == "42", "verb_memo method syntax")
end

do  -- works with pvm.report()
    local emit4 = pvm2.verb_memo("emit4", {
        [CTX.Ex.Lit]   = function(n) return T.unit(n.val) end,
        [CTX.Ex.BinOp] = function(n) return pvm2.concat_all({
            {n.lhs:emit4()}, {T.unit(n.op)}, {n.rhs:emit4()}
        }) end,
        [CTX.Ex.Call]   = function(n) return T.unit(n.name) end,
    })
    T.collect(emit4(tree))
    T.collect(emit4(tree))  -- second call: all hits
    local report = pvm2.report({ emit4 })
    check(report:find("verb_memo") ~= nil, "verb_memo in report")
    check(report:find("hits") ~= nil, "verb_memo report shows hits")
end

do  -- source is inspectable
    local emit5 = pvm2.verb_memo("emit5", {
        [CTX.Ex.Lit]   = function(n) return T.unit(n.val) end,
        [CTX.Ex.BinOp] = function(n) return T.unit(n.op) end,
        [CTX.Ex.Call]   = function(n) return T.unit(n.name) end,
    })
    check(type(emit5.source) == "string", "verb_memo .source")
    check(emit5.source:find("cache") ~= nil, "verb_memo source has cache logic")
    check(emit5.source:find("seq_gen") ~= nil, "verb_memo source has seq_gen")
end

do  -- reset clears cache
    local emit6 = pvm2.verb_memo("emit6", {
        [CTX.Ex.Lit]   = function(n) return T.unit(n.val) end,
        [CTX.Ex.BinOp] = function(n) return pvm2.concat_all({
            {n.lhs:emit6()}, {T.unit(n.op)}, {n.rhs:emit6()}
        }) end,
        [CTX.Ex.Call]   = function(n) return T.unit(n.name) end,
    })
    T.collect(emit6(tree))
    T.collect(emit6(tree))  -- hits
    local s1 = emit6:stats()
    check(s1.hits > 0, "verb_memo has hits before reset")
    emit6:reset()
    local s2 = emit6:stats()
    check(s2.calls == 0 and s2.hits == 0, "verb_memo reset clears stats")
    T.collect(emit6(tree))  -- all misses after reset
    check(emit6:stats().hits == 0, "verb_memo all misses after reset")
end

do  -- extra args participate in cache key
    local calls = 0
    local emit_ctx = pvm2.verb_memo("emit_ctx", {
        [CTX.Ex.Lit] = function(node, prefix)
            calls = calls + 1
            return T.unit(prefix .. tostring(node.val))
        end,
        [CTX.Ex.BinOp] = function(node, prefix)
            calls = calls + 1
            return pvm2.concat_all({
                { node.lhs:emit_ctx(prefix) },
                { T.unit(prefix .. node.op) },
                { node.rhs:emit_ctx(prefix) },
            })
        end,
        [CTX.Ex.Call] = function(node, prefix)
            calls = calls + 1
            return T.unit(prefix .. node.name)
        end,
    }, { name = "custom_emit_ctx", args = true })

    calls = 0
    local r1 = T.collect(emit_ctx(tree, "@"))
    check(calls == 5, "verb_memo args first call")
    check(r1[1] == "@1" and r1[2] == "@+" and r1[5] == "@3", "verb_memo args first values")

    calls = 0
    local r2 = T.collect(emit_ctx(tree, "@"))
    check(calls == 0, "verb_memo args same arg hits cache")
    check(r2[1] == "@1" and r2[5] == "@3", "verb_memo args cached values")

    calls = 0
    local r3 = T.collect(emit_ctx(tree, "#"))
    check(calls == 5, "verb_memo args different arg misses")
    check(r3[1] == "#1" and r3[2] == "#+" and r3[5] == "#3", "verb_memo args different values")
    check(emit_ctx:stats().name == "custom_emit_ctx", "verb_memo opts.name")
end

do  -- extra args are rejected unless opts.args=true
    local emit_noargs = pvm2.verb_memo("emit_noargs", {
        [CTX.Ex.Lit]   = function(n) return T.unit(n.val) end,
        [CTX.Ex.BinOp] = function(n) return T.unit(n.op) end,
        [CTX.Ex.Call]  = function(n) return T.unit(n.name) end,
    })
    local ok, err = pcall(function() return emit_noargs(Lit(1), "bad") end)
    check(not ok, "verb_memo rejects extra args by default")
    check(type(err) == "string" and err:find("opts%.args = true") ~= nil,
        "verb_memo extra-args error mentions opts.args")
end

do  -- flat recursive path: handlers append to arrays, top-level still returns seq(array)
    local calls = 0
    local emit_flat_memo = pvm2.verb_memo("emit_flat_memo", {
        [CTX.Ex.Lit] = function(node, out)
            calls = calls + 1
            out[#out + 1] = tostring(node.val)
        end,
        [CTX.Ex.BinOp] = function(node, out)
            calls = calls + 1
            node.lhs:emit_flat_memo(out)
            out[#out + 1] = node.op
            node.rhs:emit_flat_memo(out)
        end,
        [CTX.Ex.Call] = function(node, out)
            calls = calls + 1
            out[#out + 1] = node.name
        end,
    }, { flat = true, name = "flat_emit_memo" })

    calls = 0
    local g, arr, c = emit_flat_memo(tree)
    check(type(g) == "function" and c == 0, "verb_memo flat returns seq triplet")
    check(calls == 5, "verb_memo flat first call")
    check(table.concat(arr, " ") == "1 + 2 * 3", "verb_memo flat values")
    check(emit_flat_memo:stats().name == "flat_emit_memo", "verb_memo flat opts.name")

    calls = 0
    local _, arr2 = emit_flat_memo(tree)
    check(calls == 0, "verb_memo flat cached top-level")
    check(arr2 == arr, "verb_memo flat reuses cached array")

    calls = 0
    local out = {}
    tree:emit_flat_memo(out)
    check(calls == 0, "verb_memo flat cached recursive append")
    check(table.concat(out, " ") == "1 + 2 * 3", "verb_memo flat append output")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: Integration — walk_gen + fuse_maps
-- ══════════════════════════════════════════════════════════════
section("Integration")

do  -- walk + fuse: collect all literal values doubled
    local walker = pvm2.walk_gen(CTX.Ex.Expr, CTX.definitions)
    local chain = pvm2.fuse_maps("lit_vals", {
        { filter = function(n) return n.kind == "Lit" end },
        function(n) return n.val * 2 end,
    })
    local result = T.collect(chain(walker(tree)))
    check(#result == 3, "walk+fuse count")
    check(result[1] == 2 and result[2] == 4 and result[3] == 6, "walk+fuse values")
end

do  -- verb_iter + cmds: flatten then iterate
    local tokens = T.collect(tree:tokens())
    -- now treat tokens as a cmd array
    local upper = T.collect(T.map(string.upper, pvm2.cmds(tokens)))
    check(upper[1] == "1" and upper[2] == "+", "verb_iter → cmds → map")
end

do  -- pipe_typed with walk_gen inside
    local walker = pvm2.walk_gen(CTX.Ex.Expr, CTX.definitions)
    local p = pvm2.pipe_typed("walk_pipe", {
        { fn = function(root) return walker(root) end, mode = "expand" },
        { fn = function(g, p, c) return T.filter(function(n) return n.kind == "Lit" end, g, p, c) end, mode = "iter" },
        { fn = function(g, p, c) return T.map(function(n) return n.val end, g, p, c) end, mode = "iter" },
    })
    local g, param, ctrl = p(tree)
    local result = T.collect(g, param, ctrl)
    check(#result == 3, "pipe_typed with walk_gen count")
    check(result[1] == 1 and result[2] == 2 and result[3] == 3, "pipe_typed with walk_gen values")
end

-- ══════════════════════════════════════════════════════════════
--  TEST: canonical API surface
-- ══════════════════════════════════════════════════════════════
section("canonical API")

do
    -- Foundation: kept from pvm
    check(type(pvm2.context) == "function", "context exists")
    check(type(pvm2.with) == "function", "with exists")
    check(type(pvm2.lower) == "function", "lower exists")
    check(type(pvm2.report) == "function", "report exists")
    check(type(pvm2.T) == "table", "T (triplet) exists")

    -- Dispatch: pvm2 native
    check(type(pvm2.verb_memo) == "function", "verb_memo exists")
    check(type(pvm2.verb_iter) == "function", "verb_iter exists")
    check(type(pvm2.verb_flat) == "function", "verb_flat exists")

    -- Traversal
    check(type(pvm2.walk) == "function", "walk exists")
    check(type(pvm2.walk_gen) == "function", "walk_gen exists")

    -- Pipeline
    check(type(pvm2.pipe) == "function", "pipe exists")
    check(type(pvm2.pipe_typed) == "function", "pipe_typed exists")
    check(type(pvm2.fuse_maps) == "function", "fuse_maps exists")

    -- Array + composition
    check(type(pvm2.cmds) == "function", "cmds exists")
    check(type(pvm2.cmds_rev) == "function", "cmds_rev exists")
    check(type(pvm2.concat_all) == "function", "concat_all exists")

    -- Dropped from pvm: verb, old pipe, collect/fold/each/count
    check(pvm2.verb == nil, "verb removed (use verb_memo/verb_iter)")
    check(pvm2.collect == nil, "collect removed (use T.collect)")
    check(pvm2.fold == nil, "fold removed (use T.fold)")
    check(pvm2.each == nil, "each removed (use T.each)")
    check(pvm2.count == nil, "count removed (use T.count)")

    -- with still works
    local new_lit = pvm2.with(Lit(10), { val = 20 })
    check(new_lit.val == 20, "with works")
    check(new_lit == Lit(20), "with interns correctly")

    -- lower still works (caches on string identity)
    local cached_fn = pvm2.lower("test_lower", function(x) return x .. "!" end, { input = "string" })
    check(cached_fn("hi") == "hi!", "lower works")
    check(cached_fn("hi") == "hi!", "lower caches")
    check(cached_fn:stats().hits == 1, "lower tracks hits")
end

-- ══════════════════════════════════════════════════════════════
--  REPORT
-- ══════════════════════════════════════════════════════════════

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
if fail > 0 then os.exit(1) end
