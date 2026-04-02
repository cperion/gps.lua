#!/usr/bin/env luajit
-- Quick smoke test: grammar2.lua vs grammar.lua on real grammars

package.path = "./?.lua;./?/init.lua;" .. package.path

-- Set up preloads so asdl_context can find gps.asdl_*
if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local asdl_context = require("asdl_context")
local lex = require("lex")

-- Provide a GPS-like table with .lex
local GPS = { lex = lex }

local G1_api = require("grammar")(GPS, asdl_context)
local G2_api = require("grammar2")(GPS, asdl_context)
-- Use G1's Grammar types for both (they share the same ASDL shape)
local G = G1_api()

local pass, fail = 0, 0

local function check(name, a, b)
    -- deep compare for tables
    local function eq(x, y)
        if x == y then return true end
        if type(x) ~= "table" or type(y) ~= "table" then return false end
        for k, v in pairs(x) do if not eq(v, y[k]) then return false end end
        for k, v in pairs(y) do if not eq(v, x[k]) then return false end end
        return true
    end
    if eq(a, b) then
        pass = pass + 1
    else
        fail = fail + 1
        print("FAIL: " .. name)
        print("  g1:", type(a) == "table" and require("inspect")(a) or tostring(a))
        print("  g2:", type(b) == "table" and require("inspect")(b) or tostring(b))
    end
end

local function check_ok(name, ok1, v1, ok2, v2)
    if ok1 ~= ok2 then
        fail = fail + 1
        print("FAIL: " .. name .. " (ok mismatch: g1=" .. tostring(ok1) .. " g2=" .. tostring(ok2) .. ")")
        if not ok1 then print("  g1 err:", v1 and v1.message or tostring(v1)) end
        if not ok2 then print("  g2 err:", v2 and v2.message or tostring(v2)) end
        return false
    end
    if not ok1 then
        pass = pass + 1
        return false
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════
-- TEST 1: Simple token-mode grammar (JSON subset)
-- ═══════════════════════════════════════════════════════════════

print("== Token-mode grammar (JSON subset) ==")

local json_spec = function(G)
    return G.Grammar.Spec(
        G.Grammar.Lex(
            {
                G.Grammar.Symbol("{"), G.Grammar.Symbol("}"),
                G.Grammar.Symbol("["), G.Grammar.Symbol("]"),
                G.Grammar.Symbol(","), G.Grammar.Symbol(":"),
                G.Grammar.String("STRING", '"'),
                G.Grammar.Number("NUMBER"),

            },
            { G.Grammar.Whitespace }
        ),
        G.Grammar.Parse(
            {
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
            },
            "value"
        )
    )
end

local p1 = G1_api(json_spec(G))
local p2 = G2_api(json_spec(G))

local json_tests = {
    '"hello"',
    '42',

    '{"a": 1, "b": 2}',
    '[1, 2, 3]',
    '{"nested": {"x": [1, "two", true, null]}}',
    '[]',
    '{}',
}

for _, input in ipairs(json_tests) do
    -- match
    local ok1 = p1:match(input)
    local ok2 = p2:match(input)
    check("match: " .. input, ok1, ok2)

    -- tree
    local ok1t, v1t = p1:try_tree(input)
    local ok2t, v2t = p2:try_tree(input)
    if check_ok("tree: " .. input, ok1t, v1t, ok2t, v2t) then
        check("tree value: " .. input, v1t, v2t)
    end

    -- reduce (identity)
    local ok1r, v1r = p1:try_reduce(input)
    local ok2r, v2r = p2:try_reduce(input)
    if check_ok("reduce: " .. input, ok1r, v1r, ok2r, v2r) then
        check("reduce value: " .. input, v1r, v2r)
    end
end

-- Error cases
local bad = { "", "{{", "[,]", "{:}" }
for _, input in ipairs(bad) do
    local ok1 = p1:match(input)
    local ok2 = p2:match(input)
    check("bad match: " .. input, ok1, ok2)
end

-- ═══════════════════════════════════════════════════════════════
-- TEST 2: Direct-mode grammar (arithmetic)
-- ═══════════════════════════════════════════════════════════════

print("== Direct-mode grammar (arithmetic) ==")

local arith_spec = function(G)
    return G.Grammar.Spec(
        G.Grammar.Lex({}, { G.Grammar.Whitespace }),
        G.Grammar.Parse(
            {
                G.Grammar.Rule("expr", G.Grammar.Seq({
                    G.Grammar.Ref("atom"),
                    G.Grammar.ZeroOrMore(G.Grammar.Seq({
                        G.Grammar.Choice({ G.Grammar.Lit("+"), G.Grammar.Lit("-") }),
                        G.Grammar.Ref("atom"),
                    })),
                })),
                G.Grammar.Rule("atom", G.Grammar.Choice({
                    G.Grammar.Num,
                    G.Grammar.Between(G.Grammar.Lit("("), G.Grammar.Ref("expr"), G.Grammar.Lit(")")),
                })),
            },
            "expr"
        )
    )
end

local a1 = G1_api(arith_spec(G))
local a2 = G2_api(arith_spec(G))

local arith_tests = { "42", "1 + 2", "1 + 2 + 3", "(1 + 2) - 3", "((42))" }

for _, input in ipairs(arith_tests) do
    local ok1 = a1:match(input)
    local ok2 = a2:match(input)
    check("arith match: " .. input, ok1, ok2)

    local ok1t, v1t = a1:try_tree(input)
    local ok2t, v2t = a2:try_tree(input)
    if check_ok("arith tree: " .. input, ok1t, v1t, ok2t, v2t) then
        check("arith tree value: " .. input, v1t, v2t)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- TEST 3: Emit mode
-- ═══════════════════════════════════════════════════════════════

print("== Emit mode ==")

local emit_tests = { '"hello"', '42', '{"a": 1}', '[1, 2]', '{}', '[]' }
for _, input in ipairs(emit_tests) do
    local log1 = {}
    local log2 = {}
    local sink1 = {
        token = function(_, name, src, st, sp) log1[#log1+1] = {"tok", name, st, sp} end,
        rule  = function(_, name, src, st, sp) log1[#log1+1] = {"rule", name, st, sp} end,
    }
    local sink2 = {
        token = function(_, name, src, st, sp) log2[#log2+1] = {"tok", name, st, sp} end,
        rule  = function(_, name, src, st, sp) log2[#log2+1] = {"rule", name, st, sp} end,
    }
    local ok1, _ = pcall(function() p1:emit(input, sink1) end)
    local ok2, _ = pcall(function() p2:emit(input, sink2) end)
    if ok1 and ok2 then
        check("emit: " .. input, log1, log2)
    elseif ok1 == ok2 then
        pass = pass + 1 -- both fail or both succeed
    else
        fail = fail + 1; print("FAIL: emit mismatch on " .. input)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- TEST 4: Custom reduce actions
-- ═══════════════════════════════════════════════════════════════

print("== Custom reduce actions ==")

local eval_actions = {
    tokens = {
        NUMBER = function(src, st, sp) return tonumber(src:sub(st+1, sp)) end,
    },
    rules = {
        expr = function(val) 
            if type(val) ~= "table" then return val end
            local result = val[1]
            if type(result) == "table" and #result > 0 then
                -- atom followed by (op, atom) pairs
                result = val[1]
                for i = 2, #val do
                    local pair = val[i]
                    if type(pair) == "table" and #pair >= 2 then
                        if pair[1] == "+" then result = result + pair[2]
                        elseif pair[1] == "-" then result = result - pair[2] end
                    end
                end
            end
            return result
        end,
        atom = function(val) return val end,
    },
}

local eval_tests = {
    { "42", 42 },
    { "1 + 2", nil },  -- complex reduce, just check g1 == g2
    { "10 - 3", nil },
}

for _, t in ipairs(eval_tests) do
    local ok1, v1 = a1:try_reduce(t[1], eval_actions)
    local ok2, v2 = a2:try_reduce(t[1], eval_actions)
    if check_ok("eval: " .. t[1], ok1, v1, ok2, v2) then
        check("eval value: " .. t[1], v1, v2)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- SUMMARY
-- ═══════════════════════════════════════════════════════════════

print("")
print(string.format("Results: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
