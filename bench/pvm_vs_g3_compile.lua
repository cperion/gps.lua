#!/usr/bin/env luajit
-- pvm_vs_g3_compile.lua
--
-- Head-to-head compile benchmark:
--   - pvm pipeline from bench/pvm_grammar_v2.lua
--   - archive/grammar3.lua compile path
--
-- Reports cold/warm/incremental and speedup ratios.

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local pvm = require("pvm")
local asdl_context = require("asdl_context")

local G3_api = require("archive.grammar3")({ lex = require("archive.lex") }, asdl_context)
local G = G3_api()

local function bench_us(n, fn)
    for _ = 1, math.min(20, n) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    for _ = 1, n do fn() end
    return (os.clock() - t0) * 1e6 / n
end

local function json_spec()
    return G.Grammar.Spec(
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
end

local function arith_spec()
    return G.Grammar.Spec(
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
end

local function mutate_json(spec)
    local rules = spec.parse.rules
    local old = rules[1]
    local patched = pvm.with(old, {
        body = G.Grammar.Seq({ old.body, G.Grammar.Tok("NUMBER") })
    })
    local nr = {}
    for i = 1, #rules do nr[i] = rules[i] end
    nr[1] = patched
    return pvm.with(spec, { parse = pvm.with(spec.parse, { rules = nr }) })
end

local function mutate_arith(spec)
    local rules = spec.parse.rules
    local old = rules[1]
    local patched = pvm.with(old, {
        body = G.Grammar.Seq({ old.body, G.Grammar.Lit("__edit") })
    })
    local nr = {}
    for i = 1, #rules do nr[i] = rules[i] end
    nr[1] = patched
    return pvm.with(spec, { parse = pvm.with(spec.parse, { rules = nr }) })
end

local function bench_g3(mk_spec, mutate)
    local base = mk_spec()
    local changed = mutate(base)

    local cold = bench_us(200, function() G3_api(base) end)
    local warm = bench_us(200, function() G3_api(base) end)
    local inc  = bench_us(200, function() G3_api(base); G3_api(changed) end)

    return { cold = cold, warm = warm, inc = inc }
end

local function run_capture(cmd)
    local p = io.popen(cmd, "r")
    if not p then error("failed to run: " .. cmd) end
    local out = p:read("*a")
    p:close()
    return out
end

local function parse_pvm_v2_metrics(backend)
    local out = run_capture("./bench/pvm_grammar_v2.lua " .. backend)

    local cold = tonumber(out:match("cold %(reset %+ build%)%s+([0-9%.]+) us/op"))
    local warm = tonumber(out:match("warm %(build%)%s+([0-9%.]+) us/op"))
    local inc  = tonumber(out:match("incremental %(base%+changed%)%s+([0-9%.]+) us/pair"))

    if not (cold and warm and inc) then
        io.stderr:write("Could not parse pvm metrics for backend " .. backend .. "\n")
        io.stderr:write(out .. "\n")
        os.exit(1)
    end

    return { cold = cold, warm = warm, inc = inc }
end

local function row(name, p, g)
    local warm_x = g.warm / p.warm
    local inc_x = g.inc / p.inc
    local cold_x = g.cold / p.cold
    print(string.format("%-12s | pvm cold=%8.2f warm=%8.2f inc=%8.2f | g3 cold=%8.2f warm=%8.2f inc=%8.2f | warm x%.1f inc x%.1f cold x%.2f",
        name, p.cold, p.warm, p.inc, g.cold, g.warm, g.inc, warm_x, inc_x, cold_x))
end

print("pvm(v2) vs archive/grammar3 compile")
print("(x-ratios are g3_time / pvm_time: >1 means pvm faster)")
print("")

local p_json = parse_pvm_v2_metrics("archive-json")
local p_arith = parse_pvm_v2_metrics("archive-arith")

local g_json = bench_g3(json_spec, mutate_json)
local g_arith = bench_g3(arith_spec, mutate_arith)

row("json", p_json, g_json)
row("arith", p_arith, g_arith)
