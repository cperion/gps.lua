-- test_asdl_parser2.lua — verify asdl_parser2 matches asdl_parser

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local P1 = require("asdl_parser")
local P2 = require("asdl_parser2")
local uvm = require("uvm")

local pass, fail = 0, 0

local function deep_eq(a, b, path)
    path = path or ""
    if type(a) ~= type(b) then
        return false, string.format("%s: type mismatch %s vs %s", path, type(a), type(b))
    end
    if type(a) ~= "table" then
        if a ~= b then
            return false, string.format("%s: %s ~= %s", path, tostring(a), tostring(b))
        end
        return true
    end
    for k, v in pairs(a) do
        local ok, msg = deep_eq(v, b[k], path .. "." .. tostring(k))
        if not ok then return false, msg end
    end
    for k, v in pairs(b) do
        if a[k] == nil then
            return false, string.format("%s.%s: missing in first", path, tostring(k))
        end
    end
    return true
end

local function test(name, input)
    local ok1, r1 = pcall(P1.parse, input)
    local ok2, r2 = pcall(P2.parse, input)

    if ok1 ~= ok2 then
        fail = fail + 1
        print(string.format("FAIL %s: p1 ok=%s p2 ok=%s", name, tostring(ok1), tostring(ok2)))
        if not ok1 then print("  p1 err:", r1) end
        if not ok2 then print("  p2 err:", r2) end
        return
    end

    if not ok1 then
        -- both errored — that's fine
        pass = pass + 1
        return
    end

    local eq, msg = deep_eq(r1, r2)
    if not eq then
        fail = fail + 1
        print(string.format("FAIL %s: %s", name, msg))
        -- dump for debugging
        local function dump(t, indent)
            indent = indent or ""
            if type(t) ~= "table" then return tostring(t) end
            local parts = {}
            for k, v in pairs(t) do
                parts[#parts + 1] = indent .. tostring(k) .. " = " .. dump(v, indent .. "  ")
            end
            return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
        end
        if #r1 < 4 and #r2 < 4 then
            print("  p1:", dump(r1))
            print("  p2:", dump(r2))
        end
    else
        pass = pass + 1
    end
end

-- ══════════════════════════════════════════════════════════════
--  TEST CASES
-- ══════════════════════════════════════════════════════════════

print("== Basic types ==")
test("empty", "")
test("product", "Foo = (number x, number y)")
test("product unique", "Foo = (number x) unique")
test("sum simple", "Foo = A | B | C")
test("sum with fields", "Foo = A(number x) | B(string s)")
test("sum unique", "Foo = A(number x) unique | B")
test("sum mixed", "Foo = A(number x) unique | B | C(string s, number n) unique")
test("product no fields", "Foo = ()")

print("\n== Modules ==")
test("module empty", "module M {}")
test("module one def", "module M { Foo = (number x) }")
test("module sum", "module M { Foo = A | B(number x) }")
test("module two defs", "module M { Foo = A | B  Bar = (number x) }")

print("\n== Qualified names ==")
test("qualified field type", "Foo = (Other.Bar x)")
test("deep qualified", "Foo = (A.B.C x)")

print("\n== Field modifiers ==")
test("optional field", "Foo = (number? x)")
test("list field", "Foo = (number* items)")
test("mixed fields", "Foo = (number x, string* names, boolean? flag)")

print("\n== Attributes ==")
test("sum attributes", "Foo = A(number x) | B attributes (number id)")

print("\n== Nested modules ==")
test("nested module", "module Outer { module Inner { Foo = (number x) } }")

print("\n== The actual ASDL schema used by gps ==")
test("grammar schema", [[
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
]])

print("\n== The UiCore schema from ui3 ==")
test("uicore schema", [[
    module UiCore {
        Color = (number r, number g, number b, number a) unique

        Brush = Solid(UiCore.Color color) unique
              | LinearGradient(UiCore.Color from, UiCore.Color to,
                               number angle) unique
              | None

        Corners = (number tl, number tr, number br, number bl) unique

        Shadow = BoxShadow(UiCore.Brush brush, number blur, number spread,
                           number dx, number dy) unique
               | NoShadow

        Stroke = Border(UiCore.Brush brush, number width) unique
               | NoStroke

        Font = (number id, number size) unique
        TextStyle = (UiCore.Font font, UiCore.Color color) unique

        Size = Fixed(number value) unique
             | Flex(number basis, number grow, number shrink) unique
             | Auto
    }
]])

-- ══════════════════════════════════════════════════════════════
--  UVM-SPECIFIC TESTS (stepping, status, inspection)
-- ══════════════════════════════════════════════════════════════

print("\n== uvm machine features ==")

do
    local param = P2.compile("Foo = (number x)")
    local machine = P2.family:spawn(param)

    -- step-by-step execution
    local steps = 0
    local yields = 0
    while true do
        local status, a = machine:step()
        steps = steps + 1
        if status == uvm.status.YIELD then
            yields = yields + 1
            assert(a.name == "Foo", "expected Foo, got " .. tostring(a.name))
        elseif status == uvm.status.HALT then
            break
        elseif status == uvm.status.TRAP then
            error("unexpected trap: " .. tostring(a))
        end
        assert(steps < 1000, "infinite loop")
    end
    assert(yields == 1, "expected 1 yield, got " .. yields)
    print(string.format("  step-by-step: %d steps, %d yields", steps, yields))
    pass = pass + 1
end

do
    local param = P2.compile("Foo = A | B  Bar = (number x)")
    local machine = P2.family:spawn(param)
    local defs, status = uvm.run.collect(machine, 10000)
    assert(status == uvm.status.HALT, "expected HALT")
    assert(#defs == 2, "expected 2 defs, got " .. #defs)
    assert(defs[1][1].name == "Foo")
    assert(defs[2][1].name == "Bar")
    print("  collect: " .. #defs .. " definitions")
    pass = pass + 1
end

-- ══════════════════════════════════════════════════════════════

print(string.format("\n== RESULTS: %d pass, %d fail ==", pass, fail))
if fail > 0 then os.exit(1) end
