#!/usr/bin/env luajit
-- json_huge_parse_bench.lua
--
-- Real-world-ish JSON payload benchmark using archive/grammar3 parser.
-- Measures parse throughput for large arrays/objects.

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local asdl_context = require("asdl_context")
local G3_api = require("archive.grammar3")({ lex = require("archive.lex") }, asdl_context)
local G = G3_api()

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
local PARSER = G3_api(SPEC)

local function gen_json_array(n)
    local t = {}
    for i = 1, n do t[i] = tostring(i) end
    return "[" .. table.concat(t, ",") .. "]"
end

local function gen_json_object(n)
    local t = {}
    for i = 1, n do t[i] = string.format('"k%d":%d', i, i) end
    return "{" .. table.concat(t, ",") .. "}"
end

local function pick_iters(bytes)
    if bytes < 2e4 then return 2000 end
    if bytes < 2e5 then return 500 end
    if bytes < 1e6 then return 120 end
    return 40
end

local function bench_us(iters, fn)
    for _ = 1, math.min(20, iters) do fn() end
    collectgarbage(); collectgarbage()
    local t0 = os.clock()
    for _ = 1, iters do fn() end
    local dt = os.clock() - t0
    return dt * 1e6 / iters, dt
end

local function run_case(label, input)
    local iters = pick_iters(#input)
    local us, dt = bench_us(iters, function()
        assert(PARSER:match(input))
    end)
    local mb = #input / 1e6
    local mbps = (mb * iters) / dt
    print(string.format("  %-14s size=%8dB  %9.2f us/op  %7.2f MB/s",
        label, #input, us, mbps))
end

print("json huge parse benchmark (archive/grammar3, compile once, :match)")
print("")

for _, n in ipairs({ 100, 1000, 5000, 10000, 20000 }) do
    run_case("array[" .. n .. "]", gen_json_array(n))
end

print("")
for _, n in ipairs({ 100, 1000, 5000, 10000 }) do
    run_case("object{" .. n .. "}", gen_json_object(n))
end

print("")
local big = gen_json_array(20000)
local us_compile_parse = bench_us(40, function()
    local p = G3_api(SPEC)
    assert(p:match(big))
end)
print(string.format("  %-14s size=%8dB  %9.2f us/op", "compile+parse", #big, us_compile_parse))
