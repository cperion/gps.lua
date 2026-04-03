-- bench_asdl_parser.lua — benchmark asdl_parser vs asdl_parser2

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local P1 = require("asdl_parser")
local P2 = require("asdl_parser2")

-- ── test inputs ──────────────────────────────────────────────

local SMALL = [[
    module M {
        Foo = (number x, number y) unique
        Bar = A(string s) | B(number n) unique | C
    }
]]

local MEDIUM = [[
    module Grammar {
        Spec = (Grammar.Lex lex, Grammar.Parse parse) unique
        Lex = (Grammar.TokenDef* tokens, Grammar.SkipDef* skip) unique
        TokenDef = Symbol(string text) unique
                 | Keyword(string text) unique
                 | Ident(string name) unique
                 | Number(string name) unique
                 | String(string name, string quote) unique
        SkipDef = Whitespace
                | LineComment(string open) unique
                | BlockComment(string open, string close) unique
        Parse = (Grammar.Rule* rules, string start) unique
        Rule = (string name, Grammar.Expr body) unique
        Expr = Seq(Grammar.Expr* items) unique
             | Choice(Grammar.Expr* arms) unique
             | ZeroOrMore(Grammar.Expr body) unique
             | OneOrMore(Grammar.Expr body) unique
             | Optional(Grammar.Expr body) unique
             | Between(Grammar.Expr open, Grammar.Expr body, Grammar.Expr close) unique
             | SepBy(Grammar.Expr item, Grammar.Expr sep) unique
             | Assoc(Grammar.Expr key, Grammar.Expr sep, Grammar.Expr value) unique
             | Ref(string name) unique
             | Tok(string name) unique
             | Lit(string text) unique
             | Num
             | Str
             | Empty
    }
]]

-- build a large input by repeating a module pattern
local function make_large(n_types)
    local parts = { "module Big {" }
    for i = 1, n_types do
        if i % 3 == 0 then
            parts[#parts+1] = string.format(
                "    Type%d = Variant%dA(number x, string y) unique | Variant%dB(number z) | Variant%dC",
                i, i, i, i)
        elseif i % 3 == 1 then
            parts[#parts+1] = string.format(
                "    Type%d = (number a, number b, string c, boolean? d) unique", i)
        else
            parts[#parts+1] = string.format(
                "    Type%d = Alpha%d(Big.Type%d ref) unique | Beta%d", i, i, math.max(1,i-1), i)
        end
    end
    parts[#parts+1] = "}"
    return table.concat(parts, "\n")
end

local LARGE = make_large(100)
local XLARGE = make_large(500)

-- ── benchmark harness ────────────────────────────────────────

local function bench(name, fn, iterations)
    -- warmup
    for i = 1, math.min(iterations, 50) do fn() end

    collectgarbage("collect")
    collectgarbage("collect")

    local t0 = os.clock()
    for i = 1, iterations do
        fn()
    end
    local elapsed = os.clock() - t0

    return elapsed, elapsed / iterations
end

local function run_bench(label, input, iterations)
    iterations = iterations or 1000

    local e1, per1 = bench("p1", function() P1.parse(input) end, iterations)
    local e2, per2 = bench("p2", function() P2.parse(input) end, iterations)

    local ratio = per2 / per1
    print(string.format("  %-12s  p1: %.1fus  p2: %.1fus  ratio: %.2fx  (%d iters)",
        label, per1*1e6, per2*1e6, ratio, iterations))
end

-- ── run ──────────────────────────────────────────────────────

print(string.format("Input sizes: small=%dB medium=%dB large=%dB xlarge=%dB",
    #SMALL, #MEDIUM, #LARGE, #XLARGE))
print()

-- verify correctness first
assert(#P1.parse(SMALL) == #P2.parse(SMALL), "small mismatch")
assert(#P1.parse(MEDIUM) == #P2.parse(MEDIUM), "medium mismatch")
assert(#P1.parse(LARGE) == #P2.parse(LARGE), "large mismatch")
assert(#P1.parse(XLARGE) == #P2.parse(XLARGE), "xlarge mismatch")
print("Correctness: OK\n")

print("Benchmark: asdl_parser (recursive) vs asdl_parser2 (uvm state machine)")
print(string.rep("-", 72))

run_bench("small", SMALL, 10000)
run_bench("medium", MEDIUM, 5000)
run_bench("large", LARGE, 1000)
run_bench("xlarge", XLARGE, 200)
