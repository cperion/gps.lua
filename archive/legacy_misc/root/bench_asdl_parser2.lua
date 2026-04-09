-- bench_asdl_parser2.lua — benchmark all three parsers

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local P1 = require("asdl_parser")
local P2 = require("asdl_parser2")
local P3 = require("asdl_parser3")

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

-- ── verify correctness ──────────────────────────────────────

local function deep_eq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

for _, input in ipairs({SMALL, MEDIUM, LARGE, XLARGE}) do
    local r1 = P1.parse(input)
    local r3 = P3.parse(input)
    assert(deep_eq(r1, r3), "P3 mismatch!")
end
print("Correctness: P1 == P3 ✓\n")

-- ── benchmark ────────────────────────────────────────────────

local function bench(fn, iterations)
    for i = 1, math.min(iterations, 50) do fn() end
    collectgarbage("collect"); collectgarbage("collect")
    local t0 = os.clock()
    for i = 1, iterations do fn() end
    return (os.clock() - t0) / iterations
end

local function run(label, input, iters)
    local t1 = bench(function() P1.parse(input) end, iters)
    local t2 = bench(function() P2.parse(input) end, iters)
    local t3 = bench(function() P3.parse(input) end, iters)

    print(string.format("  %-10s  p1(recursive): %6.1fus   p2(uvm fine): %6.1fus [%.1fx]   p3(uvm coarse): %6.1fus [%.1fx]",
        label, t1*1e6, t2*1e6, t2/t1, t3*1e6, t3/t1))
end

print("p1 = asdl_parser   (recursive descent, not resumable)")
print("p2 = asdl_parser2  (uvm, step per token — fully resumable)")
print("p3 = asdl_parser3  (uvm, step per definition — resumable at boundaries)")
print(string.rep("-", 100))

run("small", SMALL, 10000)
run("medium", MEDIUM, 5000)
run("large", LARGE, 1000)
run("xlarge", XLARGE, 200)
