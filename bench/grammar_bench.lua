#!/usr/bin/env luajit
-- grammar_bench.lua — head-to-head: grammar.lua vs grammar2.lua
--
-- Workloads:
--   1. JSON token-mode:  parse JSON strings of increasing size
--   2. Arithmetic direct-mode: parse arithmetic expressions
--   3. Emit mode: parse + emit log
--   4. Reduce mode: parse + build value tree

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local ffi = require("ffi")
local asdl_context = require("asdl_context")
local lex = require("lex")
local GPS = { lex = lex }

local G1_api = require("grammar")(GPS, asdl_context)
local G2_api = require("grammar2")(GPS, asdl_context)
local G = G1_api() -- shared Grammar types

-- ═══════════════════════════════════════════════════════════════
-- TIMER
-- ═══════════════════════════════════════════════════════════════

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } gbench_ts;
    int clock_gettime(int, gbench_ts *);
]]
local ts = ffi.new("gbench_ts")
local function now()
    ffi.C.clock_gettime(1, ts)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

-- ═══════════════════════════════════════════════════════════════
-- JSON GRAMMAR (token mode)
-- ═══════════════════════════════════════════════════════════════

local json_spec = G.Grammar.Spec(
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

local jp1 = G1_api(json_spec)
local jp2 = G2_api(json_spec)

-- ═══════════════════════════════════════════════════════════════
-- ARITHMETIC GRAMMAR (direct mode)
-- ═══════════════════════════════════════════════════════════════

local arith_spec = G.Grammar.Spec(
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

local ap1 = G1_api(arith_spec)
local ap2 = G2_api(arith_spec)

-- ═══════════════════════════════════════════════════════════════
-- INPUT GENERATORS
-- ═══════════════════════════════════════════════════════════════

local function gen_json_flat_array(n)
    local parts = {}
    for i = 1, n do parts[i] = tostring(i) end
    return "[" .. table.concat(parts, ", ") .. "]"
end

local function gen_json_object(n)
    local parts = {}
    for i = 1, n do parts[i] = string.format('"k%d": %d', i, i * 7) end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function gen_json_nested(depth)
    if depth <= 0 then return "42" end
    return '{"a": ' .. gen_json_nested(depth - 1) .. ', "b": [1, 2]}'
end

local function gen_arith(n)
    local parts = {}
    for i = 1, n do parts[i] = tostring(i) end
    return table.concat(parts, " + ")
end

local function gen_arith_nested(depth)
    if depth <= 0 then return "1" end
    return "(" .. gen_arith_nested(depth - 1) .. " + 2) * 3"
end

-- ═══════════════════════════════════════════════════════════════
-- BENCHMARK RUNNER
-- ═══════════════════════════════════════════════════════════════

local function bench(name, fn, iters)
    -- warmup
    for i = 1, math.min(50, iters) do fn() end
    -- measure
    local t0 = now()
    for i = 1, iters do fn() end
    local elapsed = now() - t0
    return elapsed / iters * 1e6 -- µs per call
end

local function run_pair(label, fn1, fn2, iters)
    local us1 = bench(label .. " g1", fn1, iters)
    local us2 = bench(label .. " g2", fn2, iters)
    local ratio = us1 / us2
    local winner = ratio > 1 and "g2" or "g1"
    local factor = ratio > 1 and ratio or (1 / ratio)
    print(string.format("  %-40s  g1: %8.2f µs   g2: %8.2f µs   %s %.2f×",
        label, us1, us2, winner, factor))
end

-- ═══════════════════════════════════════════════════════════════
-- RUN
-- ═══════════════════════════════════════════════════════════════

print("grammar_bench: grammar.lua (g1) vs grammar2.lua (g2)")
print("")

-- JSON match
print("── JSON token-mode: match ──")
for _, n in ipairs({ 10, 50, 200, 1000 }) do
    local input = gen_json_flat_array(n)
    run_pair(string.format("array[%d] match", n),
        function() jp1:match(input) end,
        function() jp2:match(input) end,
        n > 200 and 500 or 2000)
end
for _, n in ipairs({ 10, 50, 200 }) do
    local input = gen_json_object(n)
    run_pair(string.format("object{%d} match", n),
        function() jp1:match(input) end,
        function() jp2:match(input) end,
        2000)
end
for _, d in ipairs({ 5, 10, 20 }) do
    local input = gen_json_nested(d)
    run_pair(string.format("nested(d=%d) match", d),
        function() jp1:match(input) end,
        function() jp2:match(input) end,
        2000)
end

-- JSON tree (reduce with tree actions)
print("")
print("── JSON token-mode: tree ──")
for _, n in ipairs({ 10, 50, 200 }) do
    local input = gen_json_flat_array(n)
    run_pair(string.format("array[%d] tree", n),
        function() jp1:tree(input) end,
        function() jp2:tree(input) end,
        2000)
end
for _, n in ipairs({ 10, 50, 200 }) do
    local input = gen_json_object(n)
    run_pair(string.format("object{%d} tree", n),
        function() jp1:tree(input) end,
        function() jp2:tree(input) end,
        2000)
end

-- JSON reduce (custom actions)
print("")
print("── JSON token-mode: reduce (custom) ──")
local json_eval = {
    tokens = {
        STRING = function(src, st, sp) return src:sub(st+2, sp-1) end,
        NUMBER = function(src, st, sp) return tonumber(src:sub(st+1, sp)) end,
    },
    rules = {
        value  = function(v) return v end,
        object = function(v)
            local out = {}
            if type(v) == "table" then
                for i = 1, #v do
                    local pair = v[i]
                    if type(pair) == "table" and #pair >= 2 then out[pair[1]] = pair[2] end
                end
            end
            return out
        end,
        array  = function(v) return v end,
    },
}
for _, n in ipairs({ 10, 50, 200 }) do
    local input = gen_json_flat_array(n)
    run_pair(string.format("array[%d] reduce", n),
        function() jp1:reduce(input, json_eval) end,
        function() jp2:reduce(input, json_eval) end,
        2000)
end

-- Arithmetic direct-mode
print("")
print("── Arithmetic direct-mode: match ──")
for _, n in ipairs({ 10, 50, 200, 1000 }) do
    local input = gen_arith(n)
    run_pair(string.format("%d-term match", n),
        function() ap1:match(input) end,
        function() ap2:match(input) end,
        n > 200 and 500 or 2000)
end
for _, d in ipairs({ 5, 10, 20 }) do
    local input = gen_arith_nested(d)
    run_pair(string.format("nested(d=%d) match", d),
        function() ap1:match(input) end,
        function() ap2:match(input) end,
        5000)
end

print("")
print("── Arithmetic direct-mode: tree ──")
for _, n in ipairs({ 10, 50, 200 }) do
    local input = gen_arith(n)
    run_pair(string.format("%d-term tree", n),
        function() ap1:tree(input) end,
        function() ap2:tree(input) end,
        2000)
end
