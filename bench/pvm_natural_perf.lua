#!/usr/bin/env luajit
-- pvm_natural_perf.lua
--
-- Minimal, pvm-only performance story:
--   grammar AST -> normalize(lower) -> emit(phase) -> drain
--
-- No VM comparison, no extra architecture.
-- Just pvm boundaries + structural sharing and the resulting perf.

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local bit = require("bit")
local pvm = require("pvm")

-- ══════════════════════════════════════════════════════════════
--  ASDL model
-- ══════════════════════════════════════════════════════════════

local CTX = pvm.context():Define [[
module G {
  Expr = Empty
       | Tok(string name) unique
       | Ref(string name) unique
       | Seq(G.Expr* items) unique
       | Choice(G.Expr* alts) unique
       | ZeroOrMore(G.Expr body) unique

  Rule = Rule(string name, G.Expr body) unique
  Grammar = Grammar(G.Rule* rules, string start) unique
}
]]

local Empty      = CTX.G.Empty
local Tok        = CTX.G.Tok
local Ref        = CTX.G.Ref
local Seq        = CTX.G.Seq
local Choice     = CTX.G.Choice
local ZeroOrMore = CTX.G.ZeroOrMore
local Rule       = CTX.G.Rule
local Grammar    = CTX.G.Grammar

local function sid(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, s:byte(i))
        h = bit.tobit(h * 16777619)
    end
    return bit.band(h, 0x7fffffff)
end

-- ══════════════════════════════════════════════════════════════
--  Synthetic source + tiny edit
-- ══════════════════════════════════════════════════════════════

local function make_expr(seed, depth, n_rules)
    if depth == 0 then
        if seed % 2 == 0 then
            return Tok("T" .. tostring(seed % 41))
        end
        return Ref("R" .. tostring((seed % n_rules) + 1))
    end

    local a = make_expr(seed + 1, depth - 1, n_rules)
    local b = make_expr(seed + 7, depth - 1, n_rules)

    if depth % 4 == 0 then
        return Seq({ a, b })
    elseif depth % 4 == 1 then
        return Choice({ a, b, ZeroOrMore(Tok("S" .. tostring(seed % 7))) })
    elseif depth % 4 == 2 then
        return Seq({ a, a, b }) -- duplicate `a` (in-flight sharing stress)
    else
        return Choice({ a, a, b })
    end
end

local function make_grammar(n_rules, depth)
    local rules = {}
    for i = 1, n_rules do
        rules[i] = Rule("R" .. tostring(i), make_expr(i * 13, depth, n_rules))
    end
    return Grammar(rules, "R1")
end

local function mutate_tiny(grammar, idx)
    local old = grammar.rules[idx]
    local patched = pvm.with(old, {
        body = Seq({ old.body, Tok("__EDIT") })
    })
    local nr = {}
    for i = 1, #grammar.rules do nr[i] = grammar.rules[i] end
    nr[idx] = patched
    return pvm.with(grammar, { rules = nr })
end

-- ══════════════════════════════════════════════════════════════
--  Simple normalization lowers
-- ══════════════════════════════════════════════════════════════

local function flatten_tagged(list, tag, field)
    local out, n = {}, 0
    for i = 1, #list do
        local it = list[i]
        if it.kind == tag then
            local arr = it[field]
            for j = 1, #arr do
                n = n + 1
                out[n] = arr[j]
            end
        else
            n = n + 1
            out[n] = it
        end
    end
    return out
end

local norm_expr
norm_expr = pvm.lower("np.norm_expr", function(node)
    local k = node.kind

    if k == "Empty" or k == "Tok" or k == "Ref" then
        return node
    end

    if k == "ZeroOrMore" then
        local b = norm_expr(node.body)
        if b == node.body then return node end
        return pvm.with(node, { body = b })
    end

    if k == "Seq" then
        local tmp, changed = {}, false
        for i = 1, #node.items do
            local old = node.items[i]
            local new = norm_expr(old)
            tmp[i] = new
            if new ~= old then changed = true end
        end
        local flat = flatten_tagged(tmp, "Seq", "items")
        if #flat ~= #node.items then changed = true end
        if #flat == 1 then return flat[1] end
        if not changed then return node end
        return Seq(flat)
    end

    if k == "Choice" then
        local tmp, changed = {}, false
        for i = 1, #node.alts do
            local old = node.alts[i]
            local new = norm_expr(old)
            tmp[i] = new
            if new ~= old then changed = true end
        end
        local flat = flatten_tagged(tmp, "Choice", "alts")
        if #flat ~= #node.alts then changed = true end

        local seen = {}
        local dedup, n = {}, 0
        for i = 1, #flat do
            local v = flat[i]
            if not seen[v] then
                seen[v] = true
                n = n + 1
                dedup[n] = v
            else
                changed = true
            end
        end

        if n == 1 then return dedup[1] end
        if not changed then return node end
        return Choice(dedup)
    end

    error("norm_expr: unexpected kind " .. tostring(k))
end)

local norm_rule = pvm.lower("np.norm_rule", function(rule)
    local b = norm_expr(rule.body)
    if b == rule.body then return rule end
    return pvm.with(rule, { body = b })
end)

local norm_grammar = pvm.lower("np.norm_grammar", function(grammar)
    local changed = false
    local rules = {}
    for i = 1, #grammar.rules do
        local old = grammar.rules[i]
        local new = norm_rule(old)
        rules[i] = new
        if new ~= old then changed = true end
    end
    if not changed then return grammar end
    return pvm.with(grammar, { rules = rules })
end)

-- ══════════════════════════════════════════════════════════════
--  Emission phases
-- ══════════════════════════════════════════════════════════════

local OP_RULE = 1
local OP_ENDR = 2
local OP_EMPTY = 3
local OP_TOK = 4
local OP_REF = 5
local OP_SEQ_OPEN = 6
local OP_SEQ_CLOSE = 7
local OP_ALT_OPEN = 8
local OP_ALT_CLOSE = 9
local OP_ZOM_OPEN = 10
local OP_ZOM_CLOSE = 11

local emit_expr
emit_expr = pvm.phase("np.emit_expr", {
    [Empty] = function(_)
        return pvm.seq({ OP_EMPTY, 0 })
    end,

    [Tok] = function(n)
        return pvm.seq({ OP_TOK, sid(n.name) })
    end,

    [Ref] = function(n)
        return pvm.seq({ OP_REF, sid(n.name) })
    end,

    [Seq] = function(n)
        local g1, p1, c1 = pvm.seq({ OP_SEQ_OPEN, #n.items })
        local g2, p2, c2 = pvm.children(emit_expr, n.items)
        local g3, p3, c3 = pvm.seq({ OP_SEQ_CLOSE, 0 })
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [Choice] = function(n)
        local g1, p1, c1 = pvm.seq({ OP_ALT_OPEN, #n.alts })
        local g2, p2, c2 = pvm.children(emit_expr, n.alts)
        local g3, p3, c3 = pvm.seq({ OP_ALT_CLOSE, 0 })
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [ZeroOrMore] = function(n)
        local g1, p1, c1 = pvm.seq({ OP_ZOM_OPEN, 0 })
        local g2, p2, c2 = emit_expr(n.body)
        local g3, p3, c3 = pvm.seq({ OP_ZOM_CLOSE, 0 })
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,
})

local emit_rule = pvm.phase("np.emit_rule", {
    [Rule] = function(r)
        local g1, p1, c1 = pvm.seq({ OP_RULE, sid(r.name) })
        local g2, p2, c2 = emit_expr(r.body)
        local g3, p3, c3 = pvm.seq({ OP_ENDR, 0 })
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,
})

local function build(grammar)
    local g = norm_grammar(grammar)
    local out = {}
    for i = 1, #g.rules do
        local rg, rp, rc = emit_rule(g.rules[i])
        pvm.drain_into(rg, rp, rc, out)
    end
    return out
end

local compile = pvm.lower("np.compile", build)

local function reset_all()
    norm_expr:reset()
    norm_rule:reset()
    norm_grammar:reset()
    emit_expr:reset()
    emit_rule:reset()
    compile:reset()
end

local function bench_us(iters, fn)
    for _ = 1, math.min(20, iters) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    for _ = 1, iters do fn() end
    return (os.clock() - t0) * 1e6 / iters
end

local function run_case(n_rules, depth)
    local base = make_grammar(n_rules, depth)
    local changed = mutate_tiny(base, math.max(1, math.floor(n_rules * 0.5)))

    local cold_iters = n_rules <= 150 and 20 or (n_rules <= 500 and 10 or 4)
    local warm_iters = n_rules <= 150 and 700 or (n_rules <= 500 and 350 or 120)
    local inc_iters  = n_rules <= 150 and 250 or (n_rules <= 500 and 150 or 60)

    -- cold
    local cold = bench_us(cold_iters, function()
        reset_all()
        build(base)
    end)

    -- warm build (internal phase/lower reuse)
    reset_all(); build(base)
    local warm = bench_us(warm_iters, function()
        build(base)
    end)

    -- incremental tiny edit
    reset_all(); build(base)
    local inc = bench_us(inc_iters, function()
        build(base)
        build(changed)
    end)

    local phase_stats = pvm.report({ emit_rule, emit_expr })
    local expr_reuse = phase_stats[2].reuse_ratio * 100

    local s_norm = norm_grammar:stats()
    local norm_hit = (s_norm.calls > 0) and (100 * s_norm.hits / s_norm.calls) or 100

    -- top-level lower identity hit
    reset_all(); compile(base)
    local compile_hit = bench_us(2000, function() compile(base) end)

    local warm_x = cold / warm
    local inc_vs_2cold_x = (2 * cold) / inc

    print(string.format(
        "rules=%-5d cold=%9.2f us  warm=%8.2f us  inc_pair=%8.2f us  warm_x=%6.1f  inc_vs_2cold_x=%5.1f  expr_reuse=%5.1f%%  norm_hit=%5.1f%%  top_hit=%5.2f us",
        n_rules, cold, warm, inc, warm_x, inc_vs_2cold_x, expr_reuse, norm_hit, compile_hit
    ))
end

local sizes = {}
for i = 1, #arg do
    local n = tonumber(arg[i])
    if n then sizes[#sizes + 1] = n end
end
if #sizes == 0 then
    sizes = { 120, 400, 1200 }
end

print("pvm natural perf (simple pipeline, tiny edit in huge grammar)")
print("(pass sizes as args, e.g. ./bench/pvm_natural_perf.lua 200 800 2000)")
print("")
for i = 1, #sizes do
    run_case(sizes[i], 4)
end
