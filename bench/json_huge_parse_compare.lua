#!/usr/bin/env luajit
-- json_huge_parse_compare.lua
--
-- Compare archive/grammar.lua vs archive/grammar3.lua on large JSON arrays.

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local asdl_context = require("asdl_context")
local lex = require("archive.lex")
local GPS = { lex = lex }

local G1_api = require("archive.grammar")(GPS, asdl_context)
local G3_api = require("archive.grammar3")(GPS, asdl_context)
local G = G1_api()

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

local SPEC = json_spec()
local P1 = G1_api(SPEC)
local P3 = G3_api(SPEC)

local function gen_json_array(n)
    local t = {}
    for i = 1, n do t[i] = tostring(i) end
    return "[" .. table.concat(t, ",") .. "]"
end

local function bench_us(iters, fn)
    for _ = 1, math.min(10, iters) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    for _ = 1, iters do fn() end
    local dt = os.clock() - t0
    return dt * 1e6 / iters, dt
end

local function run_case(n, iters)
    local src = gen_json_array(n)
    local mb = #src / 1e6

    local u1, d1 = bench_us(iters, function() assert(P1:match(src)) end)
    local u3, d3 = bench_us(iters, function() assert(P3:match(src)) end)

    local m1 = (mb * iters) / d1
    local m3 = (mb * iters) / d3

    print(string.format("array[%6d] size=%7.2f MB | g1 %9.0f us  %7.2f MB/s | g3 %9.0f us  %7.2f MB/s | g1/g3 x%.2f",
        n, mb, u1, m1, u3, m3, u3 / u1))
end

print("huge-json parse compare (compile once, :match)")
run_case(20000, 30)
run_case(100000, 8)
