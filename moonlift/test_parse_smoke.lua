package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Parse = require("moonlift.parse")

local T = pvm.context()
A.Define(T)
local P = Parse.Define(T)
local Surf = T.MoonliftSurface

local ty = P.parse_type("func(i32, &u8) -> [N + 1]i32")
assert(ty == Surf.SurfTFunc({
    Surf.SurfTI32,
    Surf.SurfTPtr(Surf.SurfTU8),
}, Surf.SurfTArray(
    Surf.SurfExprAdd(Surf.SurfNameRef("N"), Surf.SurfInt("1")),
    Surf.SurfTI32
)))

local view_ty = P.parse_type("view(i32)")
assert(view_ty == Surf.SurfTView(Surf.SurfTI32))

local expr = P.parse_expr("cast<f64>(popcount(x) + 1)")
assert(expr == Surf.SurfExprCastTo(
    Surf.SurfTF64,
    Surf.SurfExprAdd(
        Surf.SurfExprIntrinsicCall(Surf.SurfPopcount, { Surf.SurfNameRef("x") }),
        Surf.SurfInt("1")
    )
))

local if_expr = P.parse_expr("if flag then x else y end")
assert(if_expr == Surf.SurfIfExpr(
    Surf.SurfNameRef("flag"),
    Surf.SurfNameRef("x"),
    Surf.SurfNameRef("y")
))

local select_expr = P.parse_expr("select(flag, x, y)")
assert(select_expr == Surf.SurfSelectExpr(
    Surf.SurfNameRef("flag"),
    Surf.SurfNameRef("x"),
    Surf.SurfNameRef("y")
))

local qualified_dot = P.parse_expr("Demo.K")
assert(qualified_dot == Surf.SurfExprDot(
    Surf.SurfNameRef("Demo"),
    "K"
))

local field_dot = P.parse_expr("p.left")
assert(field_dot == Surf.SurfExprDot(
    Surf.SurfNameRef("p"),
    "left"
))

local dot_set = P.parse_stmt("p.left = 1")
assert(dot_set == Surf.SurfSet(
    Surf.SurfPlaceDot(Surf.SurfPlaceName("p"), "left"),
    Surf.SurfInt("1")
))

local stmt = P.parse_stmt("dst[i] = src[i] + 1")
assert(stmt == Surf.SurfSet(
    Surf.SurfPlaceIndex(Surf.SurfNameRef("dst"), Surf.SurfNameRef("i")),
    Surf.SurfExprAdd(
        Surf.SurfIndex(Surf.SurfNameRef("src"), Surf.SurfNameRef("i")),
        Surf.SurfInt("1")
    )
))

local block_expr = P.parse_expr([[
do
    let x: i32 = 20
    x + 22
end
]])
assert(block_expr == Surf.SurfBlockExpr(
    { Surf.SurfLet("x", Surf.SurfTI32, Surf.SurfInt("20")) },
    Surf.SurfExprAdd(Surf.SurfNameRef("x"), Surf.SurfInt("22"))
))

local switch_expr = P.parse_expr([[
switch x do
case 1 then
    let y: i32 = 2
    y + 1
default then
    0
end
]])
assert(switch_expr == Surf.SurfSwitchExpr(
    Surf.SurfNameRef("x"),
    {
        Surf.SurfSwitchExprArm(
            Surf.SurfInt("1"),
            { Surf.SurfLet("y", Surf.SurfTI32, Surf.SurfInt("2")) },
            Surf.SurfExprAdd(Surf.SurfNameRef("y"), Surf.SurfInt("1"))
        ),
    },
    Surf.SurfInt("0")
))

local switch_stmt = P.parse_stmt([[
switch x do
case 1 then
    y = 2
default then
    return
end
]])
assert(switch_stmt == Surf.SurfSwitch(
    Surf.SurfNameRef("x"),
    {
        Surf.SurfSwitchStmtArm(
            Surf.SurfInt("1"),
            { Surf.SurfSet(Surf.SurfPlaceName("y"), Surf.SurfInt("2")) }
        ),
    },
    { Surf.SurfReturnVoid }
))

local typed_loop_expr = P.parse_expr([[
loop (i: index = 0, acc: i32 = 0) -> i32 while i < n
    let xi: i32 = xs[i]
next
    acc = acc + xi
    i = i + 1
end -> acc
]])
assert(typed_loop_expr == Surf.SurfLoopExprNode(Surf.SurfLoopWhileExprTyped(
    {
        Surf.SurfLoopCarryInit("i", Surf.SurfTIndex, Surf.SurfInt("0")),
        Surf.SurfLoopCarryInit("acc", Surf.SurfTI32, Surf.SurfInt("0")),
    },
    Surf.SurfTI32,
    Surf.SurfExprLt(Surf.SurfNameRef("i"), Surf.SurfNameRef("n")),
    {
        Surf.SurfLet("xi", Surf.SurfTI32, Surf.SurfIndex(Surf.SurfNameRef("xs"), Surf.SurfNameRef("i"))),
    },
    {
        Surf.SurfLoopNextAssign("acc", Surf.SurfExprAdd(Surf.SurfNameRef("acc"), Surf.SurfNameRef("xi"))),
        Surf.SurfLoopNextAssign("i", Surf.SurfExprAdd(Surf.SurfNameRef("i"), Surf.SurfInt("1"))),
    },
    Surf.SurfNameRef("acc")
)))

local typed_over_stmt = P.parse_stmt([[
loop (i: index over range(n), acc: i32 = 0)
    acc = acc + 1
next
    acc = acc + 1
end
]])
assert(typed_over_stmt == Surf.SurfLoopStmtNode(Surf.SurfLoopOverStmt(
    "i",
    Surf.SurfDomainRange(Surf.SurfNameRef("n")),
    {
        Surf.SurfLoopCarryInit("acc", Surf.SurfTI32, Surf.SurfInt("0")),
    },
    {
        Surf.SurfSet(Surf.SurfPlaceName("acc"), Surf.SurfExprAdd(Surf.SurfNameRef("acc"), Surf.SurfInt("1"))),
    },
    {
        Surf.SurfLoopNextAssign("acc", Surf.SurfExprAdd(Surf.SurfNameRef("acc"), Surf.SurfInt("1"))),
    }
)))

local loop_zip = P.parse_stmt([[
loop (i: index over zip_eq(dst, src), y: i32 = 0)
    y = y + src[i]
next
    y = y + 1
end
]])
assert(loop_zip == Surf.SurfLoopStmtNode(Surf.SurfLoopOverStmt(
    "i",
    Surf.SurfDomainZipEq({ Surf.SurfNameRef("dst"), Surf.SurfNameRef("src") }),
    {
        Surf.SurfLoopCarryInit("y", Surf.SurfTI32, Surf.SurfInt("0")),
    },
    {
        Surf.SurfSet(
            Surf.SurfPlaceName("y"),
            Surf.SurfExprAdd(Surf.SurfNameRef("y"), Surf.SurfIndex(Surf.SurfNameRef("src"), Surf.SurfNameRef("i")))
        ),
    },
    {
        Surf.SurfLoopNextAssign("y", Surf.SurfExprAdd(Surf.SurfNameRef("y"), Surf.SurfInt("1"))),
    }
)))

local agg_expr = P.parse_expr("Pair { left = 1, right = 2 }")
assert(agg_expr == Surf.SurfAgg(
    Surf.SurfTNamed(Surf.SurfPath({ Surf.SurfName("Pair") })),
    {
        Surf.SurfFieldInit("left", Surf.SurfInt("1")),
        Surf.SurfFieldInit("right", Surf.SurfInt("2")),
    }
))

local arr_expr = P.parse_expr("[]i32 { 1, 2, 3 }")
assert(arr_expr == Surf.SurfArrayLit(Surf.SurfTI32, {
    Surf.SurfInt("1"),
    Surf.SurfInt("2"),
    Surf.SurfInt("3"),
}))

local break_value = P.parse_stmt("break x + 1")
assert(break_value == Surf.SurfBreakValue(
    Surf.SurfExprAdd(Surf.SurfNameRef("x"), Surf.SurfInt("1"))
))

local bad_expr, bad_diag = P.try_parse_expr("@")
assert(bad_expr == nil)
assert(bad_diag ~= nil)
assert((bad_diag.kind == "lex") or (bad_diag.kind == "parse"))
assert(bad_diag.line == 1)
assert(bad_diag.col == 1)
assert(bad_diag.offset ~= nil)

local import_item = P.parse_item([[import Demo]])
assert(import_item == Surf.SurfItemImport(Surf.SurfImport(
    Surf.SurfPath({ Surf.SurfName("Demo") })
)))

local type_item = P.parse_item([[type Pair = struct { left: i32, right: i32 }]])
assert(type_item == Surf.SurfItemType(Surf.SurfStruct(
    "Pair",
    {
        Surf.SurfFieldDecl("left", Surf.SurfTI32),
        Surf.SurfFieldDecl("right", Surf.SurfTI32),
    }
)))

local func_item, func_spans = P.parse_item_with_spans([[
func add(a: i32, b: i32) -> i32
    let s: i32 = a + b
    if a < b then
        return s
    else
        return a
    end
    return s
end
]])
assert(func_spans:get("func.add") ~= nil)
assert(func_spans:get("func.add.param.1") ~= nil)
assert(func_spans:get("func.add.stmt.1") ~= nil)
assert(func_item == Surf.SurfItemFunc(Surf.SurfFunc(
    "add",
    {
        Surf.SurfParam("a", Surf.SurfTI32),
        Surf.SurfParam("b", Surf.SurfTI32),
    },
    Surf.SurfTI32,
    {
        Surf.SurfLet("s", Surf.SurfTI32, Surf.SurfExprAdd(Surf.SurfNameRef("a"), Surf.SurfNameRef("b"))),
        Surf.SurfIf(
            Surf.SurfExprLt(Surf.SurfNameRef("a"), Surf.SurfNameRef("b")),
            { Surf.SurfReturnValue(Surf.SurfNameRef("s")) },
            { Surf.SurfReturnValue(Surf.SurfNameRef("a")) }
        ),
        Surf.SurfReturnValue(Surf.SurfNameRef("s")),
    }
)))

local mod, mod_spans = P.parse_module_with_spans([[
import Demo
type Pair = struct { left: i32, right: i32 }
extern func ext(x: i32) -> i32
const K: i32 = 7
static G: i32 = 9
func main(x: i32) -> i32
    let y: i32 = ext(x)
    return y + K
end
]])
assert(mod_spans:get("module") ~= nil)
assert(mod_spans:get("item.1") ~= nil)
assert(mod_spans:get("import.Demo") ~= nil)
assert(mod_spans:get("type.Pair") ~= nil)
assert(mod_spans:get("extern.ext") ~= nil)
assert(mod_spans:get("const.K") ~= nil)
assert(mod_spans:get("static.G") ~= nil)
assert(mod_spans:get("func.main.stmt.1") ~= nil)
assert(mod == Surf.SurfModule({
    Surf.SurfItemImport(Surf.SurfImport(
        Surf.SurfPath({ Surf.SurfName("Demo") })
    )),
    Surf.SurfItemType(Surf.SurfStruct(
        "Pair",
        {
            Surf.SurfFieldDecl("left", Surf.SurfTI32),
            Surf.SurfFieldDecl("right", Surf.SurfTI32),
        }
    )),
    Surf.SurfItemExtern(Surf.SurfExternFunc(
        "ext",
        "ext",
        { Surf.SurfParam("x", Surf.SurfTI32) },
        Surf.SurfTI32
    )),
    Surf.SurfItemConst(Surf.SurfConst("K", Surf.SurfTI32, Surf.SurfInt("7"))),
    Surf.SurfItemStatic(Surf.SurfStatic("G", Surf.SurfTI32, Surf.SurfInt("9"))),
    Surf.SurfItemFunc(Surf.SurfFunc(
        "main",
        { Surf.SurfParam("x", Surf.SurfTI32) },
        Surf.SurfTI32,
        {
            Surf.SurfLet("y", Surf.SurfTI32, Surf.SurfCall(Surf.SurfNameRef("ext"), { Surf.SurfNameRef("x") })),
            Surf.SurfReturnValue(Surf.SurfExprAdd(Surf.SurfNameRef("y"), Surf.SurfNameRef("K"))),
        }
    )),
}))

local bad_typed_loop, bad_typed_loop_diag = P.try_parse_stmt([[
loop (i: i32 = 0) -> i32 while i < 4
next
    i = i + 1
end
]])
assert(bad_typed_loop == nil)
assert(bad_typed_loop_diag ~= nil)
assert(bad_typed_loop_diag.kind == "parse")
assert(bad_typed_loop_diag.message:find("loop statements cannot declare a header result type", 1, true) ~= nil)

local bad_old_loop_expr, bad_old_loop_expr_diag = P.try_parse_expr([[
loop i: index = 0, acc: i32 = 0 while i < n
next
    acc = acc + 1
    i = i + 1
end -> acc
]])
assert(bad_old_loop_expr == nil)
assert(bad_old_loop_expr_diag ~= nil)
assert(bad_old_loop_expr_diag.kind == "parse")
assert(bad_old_loop_expr_diag.message:find("expected '('", 1, true) ~= nil)

local bad_old_loop_stmt, bad_old_loop_stmt_diag = P.try_parse_stmt([[
loop i over range(n), acc: i32 = 0
next
    acc = acc + 1
end
]])
assert(bad_old_loop_stmt == nil)
assert(bad_old_loop_stmt_diag ~= nil)
assert(bad_old_loop_stmt_diag.kind == "parse")
assert(bad_old_loop_stmt_diag.message:find("expected '('", 1, true) ~= nil)

print("moonlift parse bootstrap smoke ok")
