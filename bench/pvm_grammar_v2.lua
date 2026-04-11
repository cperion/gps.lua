#!/usr/bin/env luajit
-- pvm_grammar_v2.lua
--
-- v2 stress harness for pvm-based grammar compilation:
--   1) ASDL grammar AST (identity interned)
--   2) normalization lowers
--   3) analysis lowers: NULLABLE, FIRST, FOLLOW
--   4) compact wordcode emission phases
--   5) cold / warm / incremental benchmarks + cache reports
--
-- Backends:
--   synthetic         (default)
--   archive-json      (build grammar from archive/grammar3 constructors)
--   archive-arith

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local bit = require("bit")
local pvm = require("pvm")

-- ══════════════════════════════════════════════════════════════
--  ASDL grammar model
-- ══════════════════════════════════════════════════════════════

local CTX = pvm.context():Define [[
module G {
  Expr = Empty
       | Tok(string name) unique
       | Lit(string text) unique
       | Num
       | Str
       | Ref(string name) unique
       | Seq(G.Expr* items) unique
       | Choice(G.Expr* alts) unique
       | ZeroOrMore(G.Expr body) unique
       | OneOrMore(G.Expr body) unique
       | Optional(G.Expr body) unique
       | Between(G.Expr open, G.Expr body, G.Expr close) unique
       | SepBy(G.Expr item, G.Expr sep) unique
       | Assoc(G.Expr key, G.Expr sep, G.Expr value) unique

  Rule = Rule(string name, G.Expr body) unique
  Grammar = Grammar(G.Rule* rules, string start) unique
}
]]

local Empty      = CTX.G.Empty
local Tok        = CTX.G.Tok
local Lit        = CTX.G.Lit
local Num        = CTX.G.Num
local Str        = CTX.G.Str
local Ref        = CTX.G.Ref
local Seq        = CTX.G.Seq
local Choice     = CTX.G.Choice
local ZeroOrMore = CTX.G.ZeroOrMore
local OneOrMore  = CTX.G.OneOrMore
local Optional   = CTX.G.Optional
local Between    = CTX.G.Between
local SepBy      = CTX.G.SepBy
local Assoc      = CTX.G.Assoc
local Rule       = CTX.G.Rule
local Grammar    = CTX.G.Grammar

-- ══════════════════════════════════════════════════════════════
--  Utilities
-- ══════════════════════════════════════════════════════════════

local function clone_set(s)
    local out = {}
    for k in pairs(s) do out[k] = true end
    return out
end

local function union_into(dst, src)
    local changed = false
    for k in pairs(src) do
        if not dst[k] then
            dst[k] = true
            changed = true
        end
    end
    return changed
end

local function set_size(s)
    local n = 0
    for _ in pairs(s) do n = n + 1 end
    return n
end

local function set_to_sorted_array(s)
    local out, n = {}, 0
    for k in pairs(s) do
        n = n + 1
        out[n] = k
    end
    table.sort(out)
    return out
end

local function fmt_set(s, max_items)
    max_items = max_items or 10
    local arr = set_to_sorted_array(s)
    if #arr <= max_items then
        return "{" .. table.concat(arr, ", ") .. "}"
    end
    local head = {}
    for i = 1, max_items do head[i] = arr[i] end
    return "{" .. table.concat(head, ", ") .. ", ... +" .. tostring(#arr - max_items) .. "}"
end

-- stable string id (32-bit FNV-1a)
local function sid(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, s:byte(i))
        h = bit.tobit(h * 16777619)
    end
    return bit.band(h, 0x7fffffff)
end

local function term_key(expr)
    local k = expr.kind
    if k == "Tok" then return "tok:" .. expr.name end
    if k == "Lit" then return "lit:" .. expr.text end
    if k == "Num" then return "num" end
    if k == "Str" then return "str" end
    return nil
end

-- ══════════════════════════════════════════════════════════════
--  Synthetic grammar generator
-- ══════════════════════════════════════════════════════════════

local function make_expr(seed, depth, n_rules)
    if depth == 0 then
        local m = seed % 4
        if m == 0 then return Tok("T" .. tostring(seed % 31)) end
        if m == 1 then return Lit("l" .. tostring(seed % 17)) end
        if m == 2 then return Num() end
        return Ref("R" .. tostring((seed % n_rules) + 1))
    end

    local a = make_expr(seed + 1, depth - 1, n_rules)
    local b = make_expr(seed + 7, depth - 1, n_rules)

    if depth % 5 == 0 then
        return Between(Lit("("), Choice({ a, b }), Lit(")"))
    elseif depth % 5 == 1 then
        return Seq({ a, a, b }) -- duplicate `a` on purpose: good shared-hit stress
    elseif depth % 5 == 2 then
        return Choice({ a, Optional(b), ZeroOrMore(Lit("sep" .. tostring(seed % 3))) })
    elseif depth % 5 == 3 then
        return OneOrMore(Choice({ a, b }))
    else
        return SepBy(Choice({ a, b }), Lit(","))
    end
end

local function make_synthetic_grammar(n_rules, depth)
    local rules = {}
    for i = 1, n_rules do
        rules[i] = Rule("R" .. tostring(i), make_expr(i * 11, depth, n_rules))
    end
    return Grammar(rules, "R1")
end

local function mutate_rule_append_lit(grammar, index)
    local old = grammar.rules[index]
    local patched = pvm.with(old, {
        body = Seq({ old.body, Lit("__edit_" .. tostring(index)) })
    })
    local new_rules = {}
    for i = 1, #grammar.rules do new_rules[i] = grammar.rules[i] end
    new_rules[index] = patched
    return pvm.with(grammar, { rules = new_rules })
end

local function mutate_rule_by_name(grammar, name)
    local idx = nil
    for i = 1, #grammar.rules do
        if grammar.rules[i].name == name then
            idx = i
            break
        end
    end
    if not idx then return grammar end
    return mutate_rule_append_lit(grammar, idx)
end

-- ══════════════════════════════════════════════════════════════
--  Adapter: archive/grammar3 spec -> this ASDL Grammar
-- ══════════════════════════════════════════════════════════════

local function adapt_archive_expr(e)
    local k = e.kind
    if k == "Empty" then return Empty() end
    if k == "Tok" then return Tok(e.name) end
    if k == "Lit" then return Lit(e.text) end
    if k == "Num" then return Num() end
    if k == "Str" then return Str() end
    if k == "Ref" then return Ref(e.name) end

    if k == "Seq" then
        local out = {}
        for i = 1, #e.items do out[i] = adapt_archive_expr(e.items[i]) end
        return Seq(out)
    end

    if k == "Choice" then
        local out = {}
        for i = 1, #e.arms do out[i] = adapt_archive_expr(e.arms[i]) end
        return Choice(out)
    end

    if k == "ZeroOrMore" then return ZeroOrMore(adapt_archive_expr(e.body)) end
    if k == "OneOrMore" then return OneOrMore(adapt_archive_expr(e.body)) end
    if k == "Optional" then return Optional(adapt_archive_expr(e.body)) end

    if k == "Between" then
        return Between(adapt_archive_expr(e.open), adapt_archive_expr(e.body), adapt_archive_expr(e.close))
    end

    if k == "Assoc" then
        return Assoc(adapt_archive_expr(e.key), adapt_archive_expr(e.sep), adapt_archive_expr(e.value))
    end

    if k == "SepBy" then
        return SepBy(adapt_archive_expr(e.item), adapt_archive_expr(e.sep))
    end

    error("adapt_archive_expr: unsupported kind " .. tostring(k))
end

local function adapt_archive_spec(spec)
    local rules = {}
    for i = 1, #spec.parse.rules do
        local r = spec.parse.rules[i]
        rules[i] = Rule(r.name, adapt_archive_expr(r.body))
    end
    return Grammar(rules, spec.parse.start)
end

local function make_archive_json_grammar()
    local asdl_context = require("asdl_context")
    local G3_api = require("archive.grammar3")({ lex = require("archive.lex") }, asdl_context)
    local G = G3_api()

    local spec = G.Grammar.Spec(
        G.Grammar.Lex(
            {
                G.Grammar.Symbol("{"), G.Grammar.Symbol("}"),
                G.Grammar.Symbol("["), G.Grammar.Symbol("]"),
                G.Grammar.Symbol(","), G.Grammar.Symbol(":"),
                G.Grammar.String("STRING", '"'),
                G.Grammar.Number("NUMBER"),
            },
            { G.Grammar.Whitespace() }
        ),
        G.Grammar.Parse({
            G.Grammar.Rule("value", G.Grammar.Choice({
                G.Grammar.Tok("STRING"),
                G.Grammar.Tok("NUMBER"),
                G.Grammar.Ref("object"),
                G.Grammar.Ref("array"),
            })),
            G.Grammar.Rule("object", G.Grammar.Between(
                G.Grammar.Tok("{"),
                G.Grammar.SepBy(
                    G.Grammar.Assoc(G.Grammar.Tok("STRING"), G.Grammar.Tok(":"), G.Grammar.Ref("value")),
                    G.Grammar.Tok(",")
                ),
                G.Grammar.Tok("}")
            )),
            G.Grammar.Rule("array", G.Grammar.Between(
                G.Grammar.Tok("["),
                G.Grammar.SepBy(G.Grammar.Ref("value"), G.Grammar.Tok(",")),
                G.Grammar.Tok("]")
            )),
        }, "value")
    )

    return adapt_archive_spec(spec)
end

local function make_archive_arith_grammar()
    local asdl_context = require("asdl_context")
    local G3_api = require("archive.grammar3")({ lex = require("archive.lex") }, asdl_context)
    local G = G3_api()

    local spec = G.Grammar.Spec(
        G.Grammar.Lex({}, { G.Grammar.Whitespace() }),
        G.Grammar.Parse({
            G.Grammar.Rule("expr", G.Grammar.Seq({
                G.Grammar.Ref("atom"),
                G.Grammar.ZeroOrMore(G.Grammar.Seq({
                    G.Grammar.Choice({ G.Grammar.Lit("+"), G.Grammar.Lit("-"), G.Grammar.Lit("*") }),
                    G.Grammar.Ref("atom"),
                })),
            })),
            G.Grammar.Rule("atom", G.Grammar.Choice({
                G.Grammar.Num(),
                G.Grammar.Between(G.Grammar.Lit("("), G.Grammar.Ref("expr"), G.Grammar.Lit(")")),
            })),
        }, "expr")
    )

    return adapt_archive_spec(spec)
end

-- ══════════════════════════════════════════════════════════════
--  Normalization lowers
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
norm_expr = pvm.lower("g2.norm_expr", function(node)
    local k = node.kind

    if k == "Empty" or k == "Tok" or k == "Lit" or k == "Num" or k == "Str" or k == "Ref" then
        return node
    end

    if k == "Between" then
        return Seq({ norm_expr(node.open), norm_expr(node.body), norm_expr(node.close) })
    end

    if k == "Assoc" then
        return Seq({ norm_expr(node.key), norm_expr(node.sep), norm_expr(node.value) })
    end

    if k == "SepBy" then
        local item = norm_expr(node.item)
        local sep = norm_expr(node.sep)
        local tail = ZeroOrMore(Seq({ sep, item }))
        return Choice({ Seq({ item, tail }), Empty() })
    end

    if k == "Optional" then
        return Choice({ norm_expr(node.body), Empty() })
    end

    if k == "OneOrMore" then
        local e = norm_expr(node.body)
        return Seq({ e, ZeroOrMore(e) })
    end

    if k == "ZeroOrMore" then
        local e = norm_expr(node.body)
        if e == node.body then return node end
        return pvm.with(node, { body = e })
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

        -- drop explicit Empty in sequences
        local kept, n = {}, 0
        for i = 1, #flat do
            if flat[i].kind ~= "Empty" then
                n = n + 1
                kept[n] = flat[i]
            else
                changed = true
            end
        end

        if n == 0 then return Empty() end
        if n == 1 then return kept[1] end
        if not changed then return node end
        return Seq(kept)
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

        if n == 0 then return Empty() end
        if n == 1 then return dedup[1] end
        if not changed then return node end
        return Choice(dedup)
    end

    error("norm_expr: unexpected kind " .. tostring(k))
end)

local norm_rule = pvm.lower("g2.norm_rule", function(rule)
    local b = norm_expr(rule.body)
    if b == rule.body then return rule end
    return pvm.with(rule, { body = b })
end)

local norm_grammar = pvm.lower("g2.norm_grammar", function(grammar)
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
--  Analysis lowers: NULLABLE / FIRST / FOLLOW
-- ══════════════════════════════════════════════════════════════

local function grammar_rule_map(grammar)
    local rm = {}
    for i = 1, #grammar.rules do
        local r = grammar.rules[i]
        rm[r.name] = r
    end
    return rm
end

local analysis_nullable = pvm.lower("g2.nullable", function(grammar)
    grammar = norm_grammar(grammar)
    local rm = grammar_rule_map(grammar)

    local nullable = {}
    for i = 1, #grammar.rules do nullable[grammar.rules[i].name] = false end

    local function nullable_expr(e)
        local k = e.kind
        if k == "Empty" then return true end
        if k == "Tok" or k == "Lit" or k == "Num" or k == "Str" then return false end
        if k == "Ref" then return nullable[e.name] or false end
        if k == "Seq" then
            for i = 1, #e.items do
                if not nullable_expr(e.items[i]) then return false end
            end
            return true
        end
        if k == "Choice" then
            for i = 1, #e.alts do
                if nullable_expr(e.alts[i]) then return true end
            end
            return false
        end
        if k == "ZeroOrMore" then return true end
        if k == "OneOrMore" then return nullable_expr(e.body) end
        if k == "Optional" then return true end
        return false
    end

    local changed = true
    while changed do
        changed = false
        for i = 1, #grammar.rules do
            local r = grammar.rules[i]
            local v = nullable_expr(r.body)
            if v ~= nullable[r.name] then
                nullable[r.name] = v
                changed = true
            end
        end
    end

    return nullable
end)

local analysis_first = pvm.lower("g2.first", function(grammar)
    grammar = norm_grammar(grammar)
    local rm = grammar_rule_map(grammar)
    local nullable = analysis_nullable(grammar)

    local first = {}
    for i = 1, #grammar.rules do first[grammar.rules[i].name] = {} end

    local first_expr -- fwd
    local function seq_first(items)
        local out = {}
        local all_nullable = true
        for i = 1, #items do
            local fs, fn = first_expr(items[i])
            union_into(out, fs)
            if not fn then
                all_nullable = false
                break
            end
        end
        return out, all_nullable
    end

    first_expr = function(e)
        local k = e.kind
        if k == "Empty" then return {}, true end

        local tk = term_key(e)
        if tk then return { [tk] = true }, false end

        if k == "Ref" then
            return clone_set(first[e.name] or {}), nullable[e.name] or false
        end

        if k == "Seq" then
            return seq_first(e.items)
        end

        if k == "Choice" then
            local out = {}
            local any_nullable = false
            for i = 1, #e.alts do
                local fs, fn = first_expr(e.alts[i])
                union_into(out, fs)
                if fn then any_nullable = true end
            end
            return out, any_nullable
        end

        if k == "ZeroOrMore" then
            local fs = first_expr(e.body)
            return fs, true
        end

        if k == "OneOrMore" then
            local fs, fn = first_expr(e.body)
            return fs, fn
        end

        if k == "Optional" then
            local fs = first_expr(e.body)
            return fs, true
        end

        return {}, false
    end

    local changed = true
    while changed do
        changed = false
        for i = 1, #grammar.rules do
            local r = grammar.rules[i]
            local fs = first_expr(r.body)
            if union_into(first[r.name], fs) then
                changed = true
            end
        end
    end

    return first
end)

local analysis_follow = pvm.lower("g2.follow", function(grammar)
    grammar = norm_grammar(grammar)
    local nullable = analysis_nullable(grammar)
    local first = analysis_first(grammar)

    local follow = {}
    for i = 1, #grammar.rules do follow[grammar.rules[i].name] = {} end
    follow[grammar.start]["$"] = true

    local first_expr -- fwd
    local function seq_first(items, start_i)
        local out = {}
        local all_nullable = true
        for i = start_i, #items do
            local fs, fn = first_expr(items[i])
            union_into(out, fs)
            if not fn then
                all_nullable = false
                break
            end
        end
        return out, all_nullable
    end

    first_expr = function(e)
        local k = e.kind
        if k == "Empty" then return {}, true end
        local tk = term_key(e)
        if tk then return { [tk] = true }, false end
        if k == "Ref" then return clone_set(first[e.name] or {}), nullable[e.name] or false end
        if k == "Seq" then return seq_first(e.items, 1) end
        if k == "Choice" then
            local out = {}
            local any_nullable = false
            for i = 1, #e.alts do
                local fs, fn = first_expr(e.alts[i])
                union_into(out, fs)
                if fn then any_nullable = true end
            end
            return out, any_nullable
        end
        if k == "ZeroOrMore" then
            local fs = first_expr(e.body)
            return fs, true
        end
        if k == "OneOrMore" then
            local fs, fn = first_expr(e.body)
            return fs, fn
        end
        if k == "Optional" then
            local fs = first_expr(e.body)
            return fs, true
        end
        return {}, false
    end

    local changed = true
    while changed do
        changed = false

        local function visit(e, trailing)
            local k = e.kind

            if k == "Ref" then
                if union_into(follow[e.name], trailing) then changed = true end
                return
            end

            if k == "Seq" then
                for i = 1, #e.items do
                    local suffix_first, suffix_nullable = seq_first(e.items, i + 1)
                    local t = clone_set(suffix_first)
                    if suffix_nullable then union_into(t, trailing) end
                    visit(e.items[i], t)
                end
                return
            end

            if k == "Choice" then
                for i = 1, #e.alts do visit(e.alts[i], trailing) end
                return
            end

            if k == "Optional" then
                visit(e.body, trailing)
                return
            end

            if k == "ZeroOrMore" or k == "OneOrMore" then
                local body_first = first_expr(e.body)
                local t = clone_set(trailing)
                union_into(t, body_first)
                visit(e.body, t)
                return
            end
        end

        for i = 1, #grammar.rules do
            local r = grammar.rules[i]
            visit(r.body, follow[r.name])
        end
    end

    return follow
end)

-- ══════════════════════════════════════════════════════════════
--  Compact wordcode emission
-- ══════════════════════════════════════════════════════════════

local OP_END         = 0
local OP_RULE_OPEN   = 1
local OP_RULE_CLOSE  = 2
local OP_EMPTY       = 3
local OP_TOK         = 4
local OP_LIT         = 5
local OP_NUM         = 6
local OP_STR         = 7
local OP_REF         = 8
local OP_SEQ_OPEN    = 9
local OP_SEQ_CLOSE   = 10
local OP_ALT_OPEN    = 11
local OP_ALT_CLOSE   = 12
local OP_OPT_OPEN    = 13
local OP_OPT_CLOSE   = 14
local OP_ZOM_OPEN    = 15
local OP_ZOM_CLOSE   = 16
local OP_OOM_OPEN    = 17
local OP_OOM_CLOSE   = 18

local emit_expr_words
emit_expr_words = pvm.phase("g2.emit_expr_words", {
    [Empty] = function(_)
        return pvm.seq({ OP_EMPTY, 0 })
    end,

    [Tok] = function(n)
        return pvm.seq({ OP_TOK, sid("tok:" .. n.name) })
    end,

    [Lit] = function(n)
        return pvm.seq({ OP_LIT, sid("lit:" .. n.text) })
    end,

    [Num] = function(_)
        return pvm.seq({ OP_NUM, 0 })
    end,

    [Str] = function(_)
        return pvm.seq({ OP_STR, 0 })
    end,

    [Ref] = function(n)
        return pvm.seq({ OP_REF, sid("rule:" .. n.name) })
    end,

    [Seq] = function(n)
        local g1, p1, c1 = pvm.seq({ OP_SEQ_OPEN, #n.items })
        local g2, p2, c2 = pvm.children(emit_expr_words, n.items)
        local g3, p3, c3 = pvm.seq({ OP_SEQ_CLOSE, 0 })
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [Choice] = function(n)
        local g1, p1, c1 = pvm.seq({ OP_ALT_OPEN, #n.alts })
        local g2, p2, c2 = pvm.children(emit_expr_words, n.alts)
        local g3, p3, c3 = pvm.seq({ OP_ALT_CLOSE, 0 })
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [Optional] = function(n)
        local g1, p1, c1 = pvm.seq({ OP_OPT_OPEN, 0 })
        local g2, p2, c2 = emit_expr_words(n.body)
        local g3, p3, c3 = pvm.seq({ OP_OPT_CLOSE, 0 })
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [ZeroOrMore] = function(n)
        local g1, p1, c1 = pvm.seq({ OP_ZOM_OPEN, 0 })
        local g2, p2, c2 = emit_expr_words(n.body)
        local g3, p3, c3 = pvm.seq({ OP_ZOM_CLOSE, 0 })
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [OneOrMore] = function(n)
        local g1, p1, c1 = pvm.seq({ OP_OOM_OPEN, 0 })
        local g2, p2, c2 = emit_expr_words(n.body)
        local g3, p3, c3 = pvm.seq({ OP_OOM_CLOSE, 0 })
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [Between] = function(n)
        -- usually gone after normalization, but keep handler for safety
        local g1, p1, c1 = emit_expr_words(n.open)
        local g2, p2, c2 = emit_expr_words(n.body)
        local g3, p3, c3 = emit_expr_words(n.close)
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,

    [SepBy] = function(n)
        -- usually gone after normalization
        local item = n.item
        local sep = n.sep
        local rewritten = Choice({ Seq({ item, ZeroOrMore(Seq({ sep, item })) }), Empty() })
        return emit_expr_words(rewritten)
    end,

    [Assoc] = function(n)
        local rewritten = Seq({ n.key, n.sep, n.value })
        return emit_expr_words(rewritten)
    end,
})

local emit_rule_words = pvm.phase("g2.emit_rule_words", {
    [Rule] = function(r)
        local g1, p1, c1 = pvm.seq({ OP_RULE_OPEN, sid("rule:" .. r.name) })
        local g2, p2, c2 = emit_expr_words(r.body)
        local g3, p3, c3 = pvm.seq({ OP_RULE_CLOSE, 0 })
        return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
    end,
})

local function build_wordcode(grammar)
    local g = norm_grammar(grammar)

    local nullable = analysis_nullable(g)
    local first = analysis_first(g)
    local follow = analysis_follow(g)

    local words = {}
    for i = 1, #g.rules do
        local rg, rp, rc = emit_rule_words(g.rules[i])
        pvm.drain_into(rg, rp, rc, words)
    end
    words[#words + 1] = OP_END
    words[#words + 1] = 0

    return {
        words = words,
        n_words = #words,
        start = g.start,
        nullable = nullable,
        first = first,
        follow = follow,
    }
end

local compile_wordcode = pvm.lower("g2.compile_wordcode", build_wordcode)

-- ══════════════════════════════════════════════════════════════
--  Bench helpers / reporting
-- ══════════════════════════════════════════════════════════════

local function reset_all()
    norm_expr:reset()
    norm_rule:reset()
    norm_grammar:reset()
    analysis_nullable:reset()
    analysis_first:reset()
    analysis_follow:reset()
    emit_expr_words:reset()
    emit_rule_words:reset()
    compile_wordcode:reset()
end

local function bench_us(iters, fn)
    for _ = 1, math.min(20, iters) do fn() end
    local t0 = os.clock()
    for _ = 1, iters do fn() end
    return (os.clock() - t0) * 1e6 / iters
end

local function print_lower_stats(items)
    for i = 1, #items do
        local s = items[i]:stats()
        local ratio = s.calls > 0 and (s.hits / s.calls) or 1.0
        print(string.format("  %-22s calls=%-6d hits=%-6d hit=%.1f%%",
            s.name, s.calls, s.hits, ratio * 100))
    end
end

local function print_rule_analysis(code, grammar, max_rules)
    max_rules = math.min(max_rules or 3, #grammar.rules)
    for i = 1, max_rules do
        local rn = grammar.rules[i].name
        local n = code.nullable[rn] and "yes" or "no"
        local f = code.first[rn] or {}
        local w = code.follow[rn] or {}
        print(string.format("  rule %-12s nullable=%-3s first=%-18s follow=%s",
            rn, n, fmt_set(f, 5), fmt_set(w, 5)))
    end
end

-- ══════════════════════════════════════════════════════════════
--  Tiny validators: AST matcher + wordcode matcher
-- ══════════════════════════════════════════════════════════════

local TERM_NUM = -1
local TERM_STR = -2

local function collect_term_ids(grammar)
    grammar = norm_grammar(grammar)
    local seen = {}

    local function walk(e)
        local k = e.kind
        if k == "Tok" then
            seen[sid("tok:" .. e.name)] = true
        elseif k == "Lit" then
            seen[sid("lit:" .. e.text)] = true
        elseif k == "Num" then
            seen[TERM_NUM] = true
        elseif k == "Str" then
            seen[TERM_STR] = true
        elseif k == "Seq" then
            for i = 1, #e.items do walk(e.items[i]) end
        elseif k == "Choice" then
            for i = 1, #e.alts do walk(e.alts[i]) end
        elseif k == "ZeroOrMore" or k == "OneOrMore" or k == "Optional" then
            walk(e.body)
        end
    end

    for i = 1, #grammar.rules do walk(grammar.rules[i].body) end

    local out = {}
    for k in pairs(seen) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local function make_ast_machine(grammar)
    grammar = norm_grammar(grammar)

    local rm = {}
    for i = 1, #grammar.rules do
        rm[grammar.rules[i].name] = grammar.rules[i].body
    end

    local function run(tokens)
        local n = #tokens
        local memo = {}
        local active = {}

        local parse_expr, parse_rule

        parse_rule = function(name, pos)
            local body = rm[name]
            if not body then return false, pos end

            local mn = memo[name]
            if not mn then
                mn = {}
                memo[name] = mn
            end
            local hit = mn[pos]
            if hit ~= nil then
                return hit.ok, hit.np
            end

            local an = active[name]
            if not an then
                an = {}
                active[name] = an
            end
            if an[pos] then
                return false, pos -- left-recursion guard
            end

            an[pos] = true
            local ok, np = parse_expr(body, pos)
            an[pos] = nil
            mn[pos] = { ok = ok, np = np }
            return ok, np
        end

        parse_expr = function(e, pos)
            local k = e.kind
            if k == "Empty" then return true, pos end
            if k == "Tok" then
                if tokens[pos] == sid("tok:" .. e.name) then return true, pos + 1 end
                return false, pos
            end
            if k == "Lit" then
                if tokens[pos] == sid("lit:" .. e.text) then return true, pos + 1 end
                return false, pos
            end
            if k == "Num" then
                if tokens[pos] == TERM_NUM then return true, pos + 1 end
                return false, pos
            end
            if k == "Str" then
                if tokens[pos] == TERM_STR then return true, pos + 1 end
                return false, pos
            end
            if k == "Ref" then return parse_rule(e.name, pos) end

            if k == "Seq" then
                local p = pos
                for i = 1, #e.items do
                    local ok, np = parse_expr(e.items[i], p)
                    if not ok then return false, pos end
                    p = np
                end
                return true, p
            end

            if k == "Choice" then
                for i = 1, #e.alts do
                    local ok, np = parse_expr(e.alts[i], pos)
                    if ok then return true, np end
                end
                return false, pos
            end

            if k == "Optional" then
                local ok, np = parse_expr(e.body, pos)
                if ok then return true, np end
                return true, pos
            end

            if k == "ZeroOrMore" then
                local p = pos
                while true do
                    local ok, np = parse_expr(e.body, p)
                    if not ok or np == p then break end
                    p = np
                end
                return true, p
            end

            if k == "OneOrMore" then
                local ok, p = parse_expr(e.body, pos)
                if not ok or p == pos then return false, pos end
                while true do
                    local ok2, np = parse_expr(e.body, p)
                    if not ok2 or np == p then break end
                    p = np
                end
                return true, p
            end

            return false, pos
        end

        local ok, np = parse_rule(grammar.start, 1)
        return ok and np == n + 1
    end

    return { run = run }
end

local function decode_wordcode(code)
    local words = code.words

    local parse_expr
    parse_expr = function(ip)
        local op, arg = words[ip], words[ip + 1]
        if op == OP_EMPTY or op == OP_TOK or op == OP_LIT or op == OP_NUM or op == OP_STR or op == OP_REF then
            return { op = op, arg = arg }, ip + 2
        end

        if op == OP_SEQ_OPEN then
            local items = {}
            local n = arg
            ip = ip + 2
            for i = 1, n do
                items[i], ip = parse_expr(ip)
            end
            assert(words[ip] == OP_SEQ_CLOSE, "wordcode decode: expected SEQ_CLOSE")
            return { op = OP_SEQ_OPEN, items = items }, ip + 2
        end

        if op == OP_ALT_OPEN then
            local alts = {}
            local n = arg
            ip = ip + 2
            for i = 1, n do
                alts[i], ip = parse_expr(ip)
            end
            assert(words[ip] == OP_ALT_CLOSE, "wordcode decode: expected ALT_CLOSE")
            return { op = OP_ALT_OPEN, alts = alts }, ip + 2
        end

        if op == OP_OPT_OPEN or op == OP_ZOM_OPEN or op == OP_OOM_OPEN then
            local close = (op == OP_OPT_OPEN and OP_OPT_CLOSE)
                or (op == OP_ZOM_OPEN and OP_ZOM_CLOSE)
                or OP_OOM_CLOSE
            ip = ip + 2
            local body
            body, ip = parse_expr(ip)
            assert(words[ip] == close, "wordcode decode: expected matching close")
            return { op = op, body = body }, ip + 2
        end

        error("wordcode decode: unexpected op " .. tostring(op) .. " at ip=" .. tostring(ip))
    end

    local rules = {}
    local ip = 1
    while true do
        local op, arg = words[ip], words[ip + 1]
        if op == OP_END then break end
        assert(op == OP_RULE_OPEN, "wordcode decode: expected RULE_OPEN")
        local rid = arg
        local body
        body, ip = parse_expr(ip + 2)
        assert(words[ip] == OP_RULE_CLOSE, "wordcode decode: expected RULE_CLOSE")
        ip = ip + 2
        rules[rid] = body
    end

    return {
        rules = rules,
        start_id = sid("rule:" .. code.start),
    }
end

local function make_wordcode_machine(code)
    local dec = decode_wordcode(code)

    local function run(tokens)
        local n = #tokens
        local memo = {}
        local active = {}

        local parse_expr, parse_rule

        parse_rule = function(rule_id, pos)
            local body = dec.rules[rule_id]
            if not body then return false, pos end

            local mr = memo[rule_id]
            if not mr then
                mr = {}
                memo[rule_id] = mr
            end
            local hit = mr[pos]
            if hit ~= nil then
                return hit.ok, hit.np
            end

            local ar = active[rule_id]
            if not ar then
                ar = {}
                active[rule_id] = ar
            end
            if ar[pos] then
                return false, pos -- left-recursion guard
            end

            ar[pos] = true
            local ok, np = parse_expr(body, pos)
            ar[pos] = nil
            mr[pos] = { ok = ok, np = np }
            return ok, np
        end

        parse_expr = function(node, pos)
            local op = node.op
            if op == OP_EMPTY then return true, pos end
            if op == OP_TOK or op == OP_LIT then
                if tokens[pos] == node.arg then return true, pos + 1 end
                return false, pos
            end
            if op == OP_NUM then
                if tokens[pos] == TERM_NUM then return true, pos + 1 end
                return false, pos
            end
            if op == OP_STR then
                if tokens[pos] == TERM_STR then return true, pos + 1 end
                return false, pos
            end
            if op == OP_REF then
                return parse_rule(node.arg, pos)
            end

            if op == OP_SEQ_OPEN then
                local p = pos
                local items = node.items
                for i = 1, #items do
                    local ok, np = parse_expr(items[i], p)
                    if not ok then return false, pos end
                    p = np
                end
                return true, p
            end

            if op == OP_ALT_OPEN then
                local alts = node.alts
                for i = 1, #alts do
                    local ok, np = parse_expr(alts[i], pos)
                    if ok then return true, np end
                end
                return false, pos
            end

            if op == OP_OPT_OPEN then
                local ok, np = parse_expr(node.body, pos)
                if ok then return true, np end
                return true, pos
            end

            if op == OP_ZOM_OPEN then
                local p = pos
                while true do
                    local ok, np = parse_expr(node.body, p)
                    if not ok or np == p then break end
                    p = np
                end
                return true, p
            end

            if op == OP_OOM_OPEN then
                local ok, p = parse_expr(node.body, pos)
                if not ok or p == pos then return false, pos end
                while true do
                    local ok2, np = parse_expr(node.body, p)
                    if not ok2 or np == p then break end
                    p = np
                end
                return true, p
            end

            return false, pos
        end

        local ok, np = parse_rule(dec.start_id, 1)
        return ok and np == n + 1
    end

    return { run = run }
end

local function lex_arith_ids(src)
    local out = {}
    local i, n = 1, #src
    while i <= n do
        local c = src:byte(i)
        if c == 32 or c == 9 or c == 10 or c == 13 then
            i = i + 1
        elseif c >= 48 and c <= 57 then
            i = i + 1
            while i <= n do
                local d = src:byte(i)
                if d >= 48 and d <= 57 then i = i + 1 else break end
            end
            out[#out + 1] = TERM_NUM
        elseif c == 43 or c == 45 or c == 42 or c == 40 or c == 41 then
            out[#out + 1] = sid("lit:" .. string.char(c))
            i = i + 1
        else
            return nil, "arith lexer: bad char at " .. tostring(i)
        end
    end
    return out
end

local function lex_json_ids(src)
    local out = {}
    local i, n = 1, #src

    local function skip_ws()
        while i <= n do
            local c = src:byte(i)
            if c == 32 or c == 9 or c == 10 or c == 13 then i = i + 1 else break end
        end
    end

    local function scan_string()
        i = i + 1 -- opening quote
        while i <= n do
            local c = src:byte(i)
            if c == 34 then
                i = i + 1
                return true
            elseif c == 92 then
                i = i + 2
            else
                i = i + 1
            end
        end
        return false
    end

    local function scan_number()
        local start = i
        local c = src:byte(i)
        if c == 45 then i = i + 1 end
        if i > n then return false end

        c = src:byte(i)
        if c < 48 or c > 57 then return false end
        if c == 48 then
            i = i + 1
        else
            i = i + 1
            while i <= n do
                c = src:byte(i)
                if c >= 48 and c <= 57 then i = i + 1 else break end
            end
        end

        if i <= n and src:byte(i) == 46 then
            i = i + 1
            if i > n then return false end
            c = src:byte(i)
            if c < 48 or c > 57 then return false end
            i = i + 1
            while i <= n do
                c = src:byte(i)
                if c >= 48 and c <= 57 then i = i + 1 else break end
            end
        end

        if i <= n then
            c = src:byte(i)
            if c == 101 or c == 69 then
                i = i + 1
                if i <= n then
                    c = src:byte(i)
                    if c == 43 or c == 45 then i = i + 1 end
                end
                if i > n then return false end
                c = src:byte(i)
                if c < 48 or c > 57 then return false end
                i = i + 1
                while i <= n do
                    c = src:byte(i)
                    if c >= 48 and c <= 57 then i = i + 1 else break end
                end
            end
        end

        return i > start
    end

    while true do
        skip_ws()
        if i > n then break end
        local c = src:byte(i)

        if c == 123 or c == 125 or c == 91 or c == 93 or c == 44 or c == 58 then
            out[#out + 1] = sid("tok:" .. string.char(c))
            i = i + 1
        elseif c == 34 then
            if not scan_string() then return nil, "json lexer: unterminated string" end
            out[#out + 1] = sid("tok:STRING")
        elseif c == 45 or (c >= 48 and c <= 57) then
            if not scan_number() then return nil, "json lexer: bad number at " .. tostring(i) end
            out[#out + 1] = sid("tok:NUMBER")
        else
            return nil, "json lexer: bad char at " .. tostring(i)
        end
    end

    return out
end

local function build_validation_cases(backend, grammar)
    if backend == "archive-arith" then
        local srcs = {
            "42",
            "1+2",
            "1 + 2 + 3",
            "(1+2)-3",
            "((42))",
            "1+",
            "(",
        }
        local out = {}
        for i = 1, #srcs do
            local ids = assert(lex_arith_ids(srcs[i]))
            out[#out + 1] = { label = srcs[i], ids = ids }
        end
        return out
    end

    if backend == "archive-json" then
        local srcs = {
            '"hello"',
            "42",
            "{\"a\":1}",
            "[1,2,3]",
            "[]",
            "{}",
            "{\"a\":[1,2]}",
            "{",
            "[, ]",
            "{:}",
        }
        local out = {}
        for i = 1, #srcs do
            local ids = lex_json_ids(srcs[i])
            if ids then
                out[#out + 1] = { label = srcs[i], ids = ids }
            end
        end
        return out
    end

    -- synthetic
    local terms = collect_term_ids(grammar)
    local out = { { label = "<empty>", ids = {} } }

    for i = 1, math.min(8, #terms) do
        out[#out + 1] = { label = "one:" .. tostring(i), ids = { terms[i] } }
    end

    math.randomseed(1337)
    for i = 1, 50 do
        local len = math.random(0, 8)
        local ids = {}
        for j = 1, len do
            ids[j] = terms[math.random(1, #terms)]
        end
        out[#out + 1] = { label = "rand:" .. tostring(i), ids = ids }
    end
    return out
end

local function run_equivalence_validation(backend, base, changed, code_base, code_changed)
    local ast_base = make_ast_machine(base)
    local ast_changed = make_ast_machine(changed)
    local wc_base = make_wordcode_machine(code_base)
    local wc_changed = make_wordcode_machine(code_changed)

    local cases = build_validation_cases(backend, base)

    local mismatches = 0
    local base_changed_diff = 0
    local shown = 0

    for i = 1, #cases do
        local c = cases[i]
        local ab = ast_base.run(c.ids)
        local wb = wc_base.run(c.ids)
        local ac = ast_changed.run(c.ids)
        local wc = wc_changed.run(c.ids)

        if ab ~= wb then
            mismatches = mismatches + 1
            if shown < 4 then
                shown = shown + 1
                print(string.format("  mismatch(base)   case=%s ast=%s wordcode=%s",
                    c.label, tostring(ab), tostring(wb)))
            end
        end

        if ac ~= wc then
            mismatches = mismatches + 1
            if shown < 4 then
                shown = shown + 1
                print(string.format("  mismatch(changed) case=%s ast=%s wordcode=%s",
                    c.label, tostring(ac), tostring(wc)))
            end
        end

        if ab ~= ac then
            base_changed_diff = base_changed_diff + 1
        end
    end

    return {
        n_cases = #cases,
        mismatches = mismatches,
        base_changed_diff = base_changed_diff,
    }
end

-- ══════════════════════════════════════════════════════════════
--  Select backend
-- ══════════════════════════════════════════════════════════════

local backend = arg[1] or "synthetic"

local base
if backend == "synthetic" then
    local n_rules = tonumber(arg[2]) or 220
    local depth = tonumber(arg[3]) or 4
    base = make_synthetic_grammar(n_rules, depth)
elseif backend == "archive-json" then
    base = make_archive_json_grammar()
elseif backend == "archive-arith" then
    base = make_archive_arith_grammar()
else
    io.stderr:write("usage: ./bench/pvm_grammar_v2.lua [synthetic [n_rules depth] | archive-json | archive-arith]\n")
    os.exit(2)
end

local changed
-- mutate start rule so validation corpus sees a semantic delta reliably
changed = mutate_rule_by_name(base, base.start)

-- ══════════════════════════════════════════════════════════════
--  Run
-- ══════════════════════════════════════════════════════════════

-- sanity compile once
local c1 = build_wordcode(base)
local c2 = build_wordcode(changed)

print("pvm grammar v2 (wordcode + nullable/first/follow)")
print(string.format("  backend=%s rules=%d", backend, #base.rules))
print(string.format("  wordcode words: base=%d changed=%d delta=%+d", c1.n_words, c2.n_words, c2.n_words - c1.n_words))
print("  sample analysis:")
print_rule_analysis(c1, base, 3)
print("")

local validation = run_equivalence_validation(backend, base, changed, c1, c2)
print("equivalence validation (AST vs wordcode)")
print(string.format("  cases=%d mismatches=%d base_changed_divergence=%d",
    validation.n_cases, validation.mismatches, validation.base_changed_diff))
print("")

-- Bench build_wordcode (exercises phases/analysis directly)
local cold = bench_us(18, function()
    reset_all()
    build_wordcode(base)
end)

reset_all()
build_wordcode(base)
local warm = bench_us(700, function()
    build_wordcode(base)
end)

reset_all()
build_wordcode(base)
local inc_pair = bench_us(250, function()
    build_wordcode(base)
    build_wordcode(changed)
end)

print("timings (build_wordcode)")
print(string.format("  %-28s %9.2f us/op", "cold (reset + build)", cold))
print(string.format("  %-28s %9.2f us/op", "warm (build)", warm))
print(string.format("  %-28s %9.2f us/pair", "incremental (base+changed)", inc_pair))
print("")

print("phase report (build_wordcode)")
print(pvm.report_string({ emit_rule_words, emit_expr_words }))
print("")

print("lower report (build_wordcode)")
print_lower_stats({ norm_expr, norm_rule, norm_grammar, analysis_nullable, analysis_first, analysis_follow })
print("")

-- Bench compile lower wrapper
reset_all()
compile_wordcode(base)
local warm_compile = bench_us(2000, function()
    compile_wordcode(base)
end)

print("timings (compile_wordcode lower)")
print(string.format("  %-28s %9.2f us/op", "warm (compile lower)", warm_compile))
print("")

print("lower report (compile wrapper)")
print_lower_stats({ compile_wordcode })
