#!/usr/bin/env luajit
-- pvm_grammar_skeleton.lua
--
-- A first grammar-compiler skeleton on top of pvm:
--   grammar AST -> normalize (lower boundaries) -> emit bytecode (phase boundaries)
--
-- Focus: show cold/warm/incremental behavior and cache reuse ratios.

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local pvm = require("pvm")

-- ══════════════════════════════════════════════════════════════
--  Grammar model (identity-interned ASDL nodes)
-- ══════════════════════════════════════════════════════════════

local CTX = pvm.context():Define [[
module G {
  Expr = Empty()
       | Lit(string text) unique
       | Ref(string name) unique
       | Seq(G.Expr* items) unique
       | Choice(G.Expr* alts) unique
       | ZeroOrMore(G.Expr expr) unique
       | OneOrMore(G.Expr expr) unique
       | Optional(G.Expr expr) unique

  Rule = Rule(string name, G.Expr expr) unique
  Grammar = Grammar(G.Rule* rules, string start) unique
}
]]

local Empty      = CTX.G.Empty
local Lit        = CTX.G.Lit
local Ref        = CTX.G.Ref
local Seq        = CTX.G.Seq
local Choice     = CTX.G.Choice
local ZeroOrMore = CTX.G.ZeroOrMore
local OneOrMore  = CTX.G.OneOrMore
local Optional   = CTX.G.Optional
local Rule       = CTX.G.Rule
local Grammar    = CTX.G.Grammar

-- ══════════════════════════════════════════════════════════════
--  Synthetic grammar generator
-- ══════════════════════════════════════════════════════════════

local function make_expr(seed, depth, n_rules)
    if depth == 0 then
        if seed % 2 == 0 then
            return Lit("tok_" .. tostring(seed % 29))
        end
        return Ref("R" .. tostring((seed % n_rules) + 1))
    end

    local a = make_expr(seed + 1, depth - 1, n_rules)
    local b = make_expr(seed + 7, depth - 1, n_rules)

    if depth % 3 == 0 then
        -- intentionally repeats `a` to stress in-flight sharing (pending cache reuse)
        return Seq({ a, a, b })
    elseif depth % 3 == 1 then
        return Choice({ a, Optional(b), ZeroOrMore(Lit("sep_" .. tostring(seed % 3))) })
    else
        return OneOrMore(Choice({ a, b }))
    end
end

local function make_grammar(n_rules, depth)
    local rules = {}
    for i = 1, n_rules do
        rules[i] = Rule("R" .. tostring(i), make_expr(i, depth, n_rules))
    end
    return Grammar(rules, "R1")
end

local function mutate_one_rule(grammar, index)
    local old_rule = grammar.rules[index]
    local patched_expr = Seq({ old_rule.expr, Lit("hotfix_" .. tostring(index)) })
    local patched_rule = pvm.with(old_rule, { expr = patched_expr })

    local new_rules = {}
    for i = 1, #grammar.rules do
        new_rules[i] = grammar.rules[i]
    end
    new_rules[index] = patched_rule

    return pvm.with(grammar, { rules = new_rules })
end

-- ══════════════════════════════════════════════════════════════
--  Normalization pass (value boundaries via pvm.lower)
-- ══════════════════════════════════════════════════════════════

local function flatten_tagged(list, tag)
    local out, n = {}, 0
    for i = 1, #list do
        local it = list[i]
        if it.kind == tag then
            local sub = (tag == "Seq") and it.items or it.alts
            for j = 1, #sub do
                n = n + 1
                out[n] = sub[j]
            end
        else
            n = n + 1
            out[n] = it
        end
    end
    return out
end

local norm_expr
norm_expr = pvm.lower("grammar.norm_expr", function(node)
    local kind = node.kind

    if kind == "Empty" or kind == "Lit" or kind == "Ref" then
        return node
    end

    if kind == "Optional" then
        local e = norm_expr(node.expr)
        return Choice({ e, Empty() })
    end

    if kind == "OneOrMore" then
        local e = norm_expr(node.expr)
        return Seq({ e, ZeroOrMore(e) })
    end

    if kind == "ZeroOrMore" then
        local e = norm_expr(node.expr)
        if e == node.expr then
            return node
        end
        return pvm.with(node, { expr = e })
    end

    if kind == "Seq" then
        local tmp, changed = {}, false
        for i = 1, #node.items do
            local old = node.items[i]
            local new = norm_expr(old)
            tmp[i] = new
            if new ~= old then changed = true end
        end
        local flat = flatten_tagged(tmp, "Seq")
        if #flat ~= #node.items then changed = true end
        if #flat == 1 then return flat[1] end
        if not changed then return node end
        return Seq(flat)
    end

    if kind == "Choice" then
        local tmp, changed = {}, false
        for i = 1, #node.alts do
            local old = node.alts[i]
            local new = norm_expr(old)
            tmp[i] = new
            if new ~= old then changed = true end
        end
        local flat = flatten_tagged(tmp, "Choice")
        if #flat ~= #node.alts then changed = true end

        -- identity dedup
        local dedup, n = {}, 0
        local seen = {}
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

        if #dedup == 1 then return dedup[1] end
        if not changed then return node end
        return Choice(dedup)
    end

    error("norm_expr: unexpected kind " .. tostring(kind))
end)

local norm_rule = pvm.lower("grammar.norm_rule", function(rule)
    local expr = norm_expr(rule.expr)
    if expr == rule.expr then
        return rule
    end
    return pvm.with(rule, { expr = expr })
end)

local norm_grammar = pvm.lower("grammar.norm_grammar", function(grammar)
    local changed = false
    local rules = {}
    for i = 1, #grammar.rules do
        local old = grammar.rules[i]
        local new = norm_rule(old)
        rules[i] = new
        if new ~= old then changed = true end
    end
    if not changed then
        return grammar
    end
    return pvm.with(grammar, { rules = rules })
end)

-- ══════════════════════════════════════════════════════════════
--  Bytecode emission (stream boundaries via pvm.phase)
-- ══════════════════════════════════════════════════════════════

local emit_expr
emit_expr = pvm.phase("emit_expr", {
    [Empty] = function(_)
        return pvm.once("EPS")
    end,

    [Lit] = function(n)
        return pvm.once("LIT " .. n.text)
    end,

    [Ref] = function(n)
        return pvm.once("REF " .. n.name)
    end,

    [Seq] = function(n)
        local g1, p1, c1 = pvm.once("SEQ[")
        local g2, p2, c2 = pvm.children(emit_expr, n.items)
        local g3, p3, c3 = pvm.once("]")
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [Choice] = function(n)
        local g1, p1, c1 = pvm.once("CHOICE[")
        local g2, p2, c2 = pvm.children(emit_expr, n.alts)
        local g3, p3, c3 = pvm.once("]")
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [ZeroOrMore] = function(n)
        local g1, p1, c1 = pvm.once("ZOM[")
        local g2, p2, c2 = emit_expr(n.expr)
        local g3, p3, c3 = pvm.once("]")
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [OneOrMore] = function(n)
        local g1, p1, c1 = pvm.once("OOM[")
        local g2, p2, c2 = emit_expr(n.expr)
        local g3, p3, c3 = pvm.once("]")
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [Optional] = function(n)
        local g1, p1, c1 = pvm.once("OPT[")
        local g2, p2, c2 = emit_expr(n.expr)
        local g3, p3, c3 = pvm.once("]")
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,
})

local emit_rule = pvm.phase("emit_rule", {
    [Rule] = function(r)
        local g1, p1, c1 = pvm.once("RULE " .. r.name)
        local g2, p2, c2 = emit_expr(r.expr)
        local g3, p3, c3 = pvm.once("END")
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,
})

local function build_program(grammar)
    local g = norm_grammar(grammar)
    local out = {}
    for i = 1, #g.rules do
        local rule = g.rules[i]
        out[rule.name] = pvm.drain(emit_rule(rule))
    end
    return out
end

local compile_program = pvm.lower("grammar.compile", build_program)

-- ══════════════════════════════════════════════════════════════
--  Bench helpers
-- ══════════════════════════════════════════════════════════════

local function reset_all()
    emit_expr:reset()
    emit_rule:reset()
    norm_expr:reset()
    norm_rule:reset()
    norm_grammar:reset()
    compile_program:reset()
end

local function bench_us(iters, fn)
    for _ = 1, math.min(20, iters) do fn() end -- warmup
    local t0 = os.clock()
    for _ = 1, iters do fn() end
    return (os.clock() - t0) * 1e6 / iters
end

local function print_lower_stats(items)
    for i = 1, #items do
        local s = items[i]:stats()
        local ratio = s.calls > 0 and (s.hits / s.calls) or 1.0
        print(string.format("  %-24s calls=%-6d hits=%-6d hit=%.1f%%",
            s.name, s.calls, s.hits, ratio * 100))
    end
end

-- ══════════════════════════════════════════════════════════════
--  Run
-- ══════════════════════════════════════════════════════════════

local N_RULES = 180
local DEPTH = 4
local EDIT_AT = 73

local base = make_grammar(N_RULES, DEPTH)
local changed = mutate_one_rule(base, EDIT_AT)

-- quick sanity
local p1 = build_program(base)
local p2 = build_program(changed)
print("pvm grammar skeleton")
print(string.format("  rules=%d depth=%d", N_RULES, DEPTH))
print(string.format("  sample opcount: base[R%d]=%d changed[R%d]=%d",
    EDIT_AT, #p1["R" .. EDIT_AT], EDIT_AT, #p2["R" .. EDIT_AT]))
print("")

-- cold (full reset each run)
local cold = bench_us(20, function()
    reset_all()
    build_program(base)
end)

-- warm (same grammar, caches stay hot)
reset_all()
build_program(base) -- prime
local warm = bench_us(800, function()
    build_program(base)
end)

-- incremental pair (base then changed)
reset_all()
build_program(base) -- prime
local inc_pair = bench_us(250, function()
    build_program(base)
    build_program(changed)
end)

print("timings (build_program)")
print(string.format("  %-28s %9.2f us/op", "cold (reset + build)", cold))
print(string.format("  %-28s %9.2f us/op", "warm (build)", warm))
print(string.format("  %-28s %9.2f us/pair", "incremental (base+changed)", inc_pair))
print("")

print("phase report (build_program)")
print(pvm.report_string({ emit_rule, emit_expr }))
print("")

print("lower report (build_program)")
print_lower_stats({ norm_expr, norm_rule, norm_grammar })
print("")

-- top-level lower wrapper (shows whole-grammar identity hit)
reset_all()
compile_program(base) -- prime
local warm_compiled = bench_us(2000, function()
    compile_program(base)
end)

print("timings (compile_program wrapper)")
print(string.format("  %-28s %9.2f us/op", "warm (compile lower)", warm_compiled))
print("")

print("lower report (compile wrapper)")
print_lower_stats({ compile_program })
