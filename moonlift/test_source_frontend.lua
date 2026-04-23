package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local Source = require("moonlift.source")

local T = pvm.context()
A.Define(T)
local S = Source.Define(T)

local Surf = T.MoonliftSurface
local Elab = T.MoonliftElab
local Sem = T.MoonliftSem
local Back = T.MoonliftBack

local agg, agg_spans = S.parse_expr_with_spans("Pair { left = 1, right = 2 }")
assert(agg_spans:get("expr") ~= nil)
assert(agg == Surf.SurfAgg(
    Surf.SurfTNamed(Surf.SurfPath({ Surf.SurfName("Pair") })),
    {
        Surf.SurfFieldInit("left", Surf.SurfInt("1")),
        Surf.SurfFieldInit("right", Surf.SurfInt("2")),
    }
))

local arr = S.parse_expr("[]i32 { 1, 2, 3 }")
assert(arr == Surf.SurfArrayLit(Surf.SurfTI32, {
    Surf.SurfInt("1"),
    Surf.SurfInt("2"),
    Surf.SurfInt("3"),
}))

local select_expr = S.parse_expr("select(flag, x, y)")
assert(select_expr == Surf.SurfSelectExpr(
    Surf.SurfNameRef("flag"),
    Surf.SurfNameRef("x"),
    Surf.SurfNameRef("y")
))

local view_ty = S.parse_type("view(i32)")
assert(view_ty == Surf.SurfTView(Surf.SurfTI32))

local qualified_dot = S.parse_expr("Demo.K")
assert(qualified_dot == Surf.SurfExprDot(Surf.SurfNameRef("Demo"), "K"))

local field_dot = S.parse_expr("pair.left")
assert(field_dot == Surf.SurfExprDot(Surf.SurfNameRef("pair"), "left"))

local bad, diag = S.try_parse_expr("if x then")
assert(bad == nil)
assert(diag ~= nil)
assert(diag.kind == "parse")
assert(diag.line == 1)
assert(diag.col >= 1)
assert(diag.message:find("expected expression", 1, true) ~= nil or diag.message:find("expected 'else'", 1, true) ~= nil)
assert(diag.offset ~= nil)

local env = Elab.ElabEnv("", {
    Elab.ElabValueEntry("pair", Elab.ElabLocalValue("env.pair", "pair", Elab.ElabTNamed("", "Pair"))),
    Elab.ElabValueEntry("Demo.K", Elab.ElabGlobalConst("Demo", "K", Elab.ElabTI32)),
    Elab.ElabValueEntry("Demo.N", Elab.ElabGlobalConst("Demo", "N", Elab.ElabTIndex)),
}, {
    Elab.ElabTypeEntry("Pair", Elab.ElabTNamed("", "Pair")),
}, {
    Elab.ElabLayoutNamed("", "Pair", {
        Elab.ElabFieldType("left", Elab.ElabTI32),
        Elab.ElabFieldType("right", Elab.ElabTI32),
    }),
})

local select_env = Elab.ElabEnv("", {
    Elab.ElabValueEntry("flag", Elab.ElabArg(0, "flag", Elab.ElabTBool)),
    Elab.ElabValueEntry("x", Elab.ElabArg(1, "x", Elab.ElabTI32)),
    Elab.ElabValueEntry("y", Elab.ElabArg(2, "y", Elab.ElabTI32)),
}, env.types, env.layouts)

local lowered_count_ty = S.lower_type("[Demo.N]i32", env)
assert(lowered_count_ty == Elab.ElabTArray(
    Elab.ElabBindingExpr(Elab.ElabGlobalConst("Demo", "N", Elab.ElabTIndex)),
    Elab.ElabTI32
))

local lowered_expr = S.lower_expr("Pair { left = 1, right = 2 }.left", env)
assert(lowered_expr == Elab.ElabField(
    Elab.ElabAgg(
        Elab.ElabTNamed("", "Pair"),
        {
            Elab.ElabFieldInit("left", Elab.ElabInt("1", Elab.ElabTI32)),
            Elab.ElabFieldInit("right", Elab.ElabInt("2", Elab.ElabTI32)),
        }
    ),
    "left",
    Elab.ElabTI32
))

local lowered_qualified = S.lower_expr("Demo.K + 1", env)
assert(lowered_qualified == Elab.ElabExprAdd(
    Elab.ElabTI32,
    Elab.ElabBindingExpr(Elab.ElabGlobalConst("Demo", "K", Elab.ElabTI32)),
    Elab.ElabInt("1", Elab.ElabTI32)
))

local lowered_field = S.lower_expr("pair.left", env)
assert(lowered_field == Elab.ElabField(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("env.pair", "pair", Elab.ElabTNamed("", "Pair"))),
    "left",
    Elab.ElabTI32
))

local lowered_select = S.lower_expr("select(flag, x, y)", select_env)
assert(lowered_select == Elab.ElabSelectExpr(
    Elab.ElabBindingExpr(Elab.ElabArg(0, "flag", Elab.ElabTBool)),
    Elab.ElabBindingExpr(Elab.ElabArg(1, "x", Elab.ElabTI32)),
    Elab.ElabBindingExpr(Elab.ElabArg(2, "y", Elab.ElabTI32)),
    Elab.ElabTI32
))

local shadow_env = Elab.ElabEnv("", {
    Elab.ElabValueEntry("Demo", Elab.ElabLocalValue("env.Demo", "Demo", Elab.ElabTNamed("", "Pair"))),
    Elab.ElabValueEntry("Demo.left", Elab.ElabGlobalConst("Demo", "left", Elab.ElabTI32)),
}, env.types, env.layouts)
local lowered_shadow = S.lower_expr("Demo.left", shadow_env)
assert(lowered_shadow == Elab.ElabField(
    Elab.ElabBindingExpr(Elab.ElabLocalValue("env.Demo", "Demo", Elab.ElabTNamed("", "Pair"))),
    "left",
    Elab.ElabTI32
))

local stages = S.pipeline_module_with_spans([[
const K: i32 = 7
func main(x: i32) -> i32
    loop (i: index = 0, acc: i32 = 0) while i < 3
    next
        acc = acc + x
        i = i + 1
    end
    switch x do
    case 0 then
        return K
    default then
        return x
    end
end
]])
assert(stages.surface ~= nil)
assert(stages.spans ~= nil)
assert(stages.elab ~= nil)
assert(stages.sem ~= nil)
assert(stages.surface.items[1].c.name == "K")
assert(stages.surface.items[2].func.name == "main")
assert(stages.spans:get("module") ~= nil)
assert(stages.spans:get("func.main") ~= nil)
assert(stages.spans:get("func.main.stmt.1") ~= nil)
assert(stages.elab.items[1].c.name == "K")
assert(stages.sem.items[2].func.name == "main")

local lowered = S.lower_module([[
const K: i32 = 7
func main(x: i32) -> i32
    return x + K
end
]])
assert(lowered.items[2].func.name == "main")

local sem_mod = S.sem_module([[
const K: i32 = 7
func main(x: i32) -> i32
    return x + K
end
]])
assert(sem_mod.items[2].func.name == "main")

local select_sem_mod = S.sem_module([[
func choose(flag: bool, x: i32, y: i32) -> i32
    return select(flag, x, y)
end
]])
assert(select_sem_mod.items[1].func.body[1] == Sem.SemStmtReturnValue(
    Sem.SemExprSelect(
        Sem.SemExprBinding(Sem.SemBindArg(0, "flag", Sem.SemTBool)),
        Sem.SemExprBinding(Sem.SemBindArg(1, "x", Sem.SemTI32)),
        Sem.SemExprBinding(Sem.SemBindArg(2, "y", Sem.SemTI32)),
        Sem.SemTI32
    )
))

local select_back_mod = S.back_module([[
func choose(flag: bool, x: i32, y: i32) -> i32
    return select(flag, x, y)
end
]])
local saw_select = false
for i = 1, #select_back_mod.cmds do
    if select_back_mod.cmds[i] == Back.BackCmdSelect(
        Back.BackValId("func:choose.stmt.1.value"),
        Back.BackI32,
        Back.BackValId("arg:0:flag"),
        Back.BackValId("arg:1:x"),
        Back.BackValId("arg:2:y")
    ) then
        saw_select = true
    end
end
assert(saw_select)

local switch_bool_sem_mod = S.sem_module([[
func switch_bool(flag: bool) -> i32
    return switch flag do
    case true then
        11
    default then
        22
    end
end
]])
assert(switch_bool_sem_mod.items[1].func.body[1] == Sem.SemStmtReturnValue(
    Sem.SemExprSwitch(
        Sem.SemExprBinding(Sem.SemBindArg(0, "flag", Sem.SemTBool)),
        {
            Sem.SemSwitchExprArm(
                Sem.SemExprConstBool(true),
                {},
                Sem.SemExprConstInt(Sem.SemTI32, "11")
            ),
        },
        Sem.SemExprConstInt(Sem.SemTI32, "22"),
        Sem.SemTI32
    )
))

local switch_u32_back_mod = S.back_module([[
func switch_u32(x: u32) -> i32
    return switch x do
    case 0 then
        10
    case 5 then
        50
    default then
        99
    end
end
]])
local saw_switch_u32 = false
for i = 1, #switch_u32_back_mod.cmds do
    if switch_u32_back_mod.cmds[i] == Back.BackCmdSwitchInt(
        Back.BackValId("arg:0:x"),
        Back.BackU32,
        {
            Back.BackSwitchCase("0", Back.BackBlockId("func:switch_u32.stmt.1.value.arm.1.block")),
            Back.BackSwitchCase("5", Back.BackBlockId("func:switch_u32.stmt.1.value.arm.2.block")),
        },
        Back.BackBlockId("func:switch_u32.stmt.1.value.default.block")
    ) then
        saw_switch_u32 = true
    end
end
assert(saw_switch_u32)

local switch_index_back_mod = S.back_module([[
func switch_index(i: index) -> i32
    return switch i do
    case 0 then
        10
    case 3 then
        30
    default then
        99
    end
end
]])
local saw_switch_index = false
for i = 1, #switch_index_back_mod.cmds do
    if switch_index_back_mod.cmds[i] == Back.BackCmdSwitchInt(
        Back.BackValId("arg:0:i"),
        Back.BackIndex,
        {
            Back.BackSwitchCase("0", Back.BackBlockId("func:switch_index.stmt.1.value.arm.1.block")),
            Back.BackSwitchCase("3", Back.BackBlockId("func:switch_index.stmt.1.value.arm.2.block")),
        },
        Back.BackBlockId("func:switch_index.stmt.1.value.default.block")
    ) then
        saw_switch_index = true
    end
end
assert(saw_switch_index)

local const_fold_back_mod = S.back_module([[
const ONE: index = 1
const TWO: index = ONE + ONE
const HALF: f64 = 0.5
func bump_index(i: index) -> index
    return i + TWO
end
func add_half(x: f64) -> f64
    return x + HALF
end
]])
local saw_folded_two = false
local saw_folded_half = false
for i = 1, #const_fold_back_mod.cmds do
    if const_fold_back_mod.cmds[i] == Back.BackCmdConstInt(
        Back.BackValId("func:bump_index.stmt.1.value.rhs"),
        Back.BackIndex,
        "2"
    ) then
        saw_folded_two = true
    end
    if const_fold_back_mod.cmds[i] == Back.BackCmdConstFloat(
        Back.BackValId("func:add_half.stmt.1.value.rhs"),
        Back.BackF64,
        "0.5"
    ) then
        saw_folded_half = true
    end
end
assert(saw_folded_two)
assert(saw_folded_half)

local typed_stages = S.pipeline_module_with_spans([[
type Pair = struct { left: i32, right: i32 }
func get_left() -> i32
    return Pair { left = 1, right = 2 }.left
end
]])
assert(typed_stages.surface.items[1].t.name == "Pair")
assert(typed_stages.elab.items[1].t.name == "Pair")
assert(typed_stages.sem.items[1].t.name == "Pair")
assert(typed_stages.layout_env.layouts[1] == Sem.SemLayoutNamed("", "Pair", {
    Sem.SemFieldLayout("left", 0, Sem.SemTI32),
    Sem.SemFieldLayout("right", 4, Sem.SemTI32),
}, 8, 4))

local resolved_mod = S.resolve_module([[
type Pair = struct { left: i32, right: i32 }
func get_left() -> i32
    return Pair { left = 1, right = 2 }.left
end
]])
assert(resolved_mod.items[1].t.name == "Pair")
assert(resolved_mod.items[2].func.body[1] == Sem.SemStmtReturnValue(
    Sem.SemExprField(
        Sem.SemExprAgg(
            Sem.SemTNamed("", "Pair"),
            {
                Sem.SemFieldInit("left", Sem.SemExprConstInt(Sem.SemTI32, "1")),
                Sem.SemFieldInit("right", Sem.SemExprConstInt(Sem.SemTI32, "2")),
            }
        ),
        Sem.SemFieldByOffset("left", 0, Sem.SemTI32)
    )
))

local back_mod = S.back_module([[
type Pair = struct { left: i32, right: i32 }
func get_left() -> i32
    return Pair { left = 1, right = 2 }.left
end
]])
assert(back_mod.cmds[#back_mod.cmds] == Back.BackCmdFinalizeModule)

local package_stages = S.pipeline_package({
    {
        name = "Demo",
        text = [[
type Pair = struct { left: i32, right: i32 }
const K: i32 = 7
func inc(x: i32) -> i32
    return x + K
end
]],
    },
    {
        name = "Main",
        text = [[
import Demo
func get_demo_left() -> i32
    return Demo.Pair { left = Demo.K, right = 9 }.left
end
func main(x: i32) -> i32
    return Demo.inc(x)
end
]],
    },
})
assert(package_stages.module_map.Demo.elab.module_name == "Demo")
assert(package_stages.module_map.Main.elab.module_name == "Main")
assert(package_stages.module_map.Main.elab.items[1].imp.module_name == "Demo")
assert(package_stages.module_map.Main.resolved.items[2].func.body[1] == Sem.SemStmtReturnValue(
    Sem.SemExprField(
        Sem.SemExprAgg(
            Sem.SemTNamed("Demo", "Pair"),
            {
                Sem.SemFieldInit("left", Sem.SemExprBinding(Sem.SemBindGlobalConst("Demo", "K", Sem.SemTI32))),
                Sem.SemFieldInit("right", Sem.SemExprConstInt(Sem.SemTI32, "9")),
            }
        ),
        Sem.SemFieldByOffset("left", 0, Sem.SemTI32)
    )
))

local back_package, package_back_stages = S.back_package({
    {
        name = "Demo",
        text = [[
func inc(x: i32) -> i32
    return x + 7
end
]],
    },
    {
        name = "Main",
        text = [[
import Demo
func main(x: i32) -> i32
    return Demo.inc(x)
end
]],
    },
})
assert(package_back_stages.module_map.Main.resolved.module_name == "Main")
assert(back_package.cmds[#back_package.cmds] == Back.BackCmdFinalizeModule)
local saw_demo_inc = false
local saw_main = false
for i = 1, #back_package.cmds do
    if back_package.cmds[i] == Back.BackCmdDeclareFuncExport(Back.BackFuncId("Demo::inc"), Back.BackSigId("sig:Demo::inc")) then
        saw_demo_inc = true
    end
    if back_package.cmds[i] == Back.BackCmdDeclareFuncExport(Back.BackFuncId("Main::main"), Back.BackSigId("sig:Main::main")) then
        saw_main = true
    end
end
assert(saw_demo_inc)
assert(saw_main)

local bad_lower, lower_diag = S.try_lower_expr("Pair { left = 1, right = missing }", env)
assert(bad_lower == nil)
assert(lower_diag ~= nil)
assert(lower_diag.kind == "lower")
assert(lower_diag.path == "expr")
assert(lower_diag.line == 1)

local bad_mod, mod_diag = S.try_lower_module([[
func main(n: index) -> void
    loop (i: index = 0) while i < n
    next
        j = i
    end
    return
end
]])
assert(bad_mod == nil)
assert(mod_diag ~= nil)
assert(mod_diag.kind == "lower")
assert(mod_diag.path == "func.main.stmt.1.next.1")
assert(mod_diag.line == 4)
assert(mod_diag.col == 9)

local typed_loop_back = S.back_module([[
func sum_typed(n: i32) -> i32
    return loop (i: i32 = 0, acc: i32 = 0) -> i32 while i < n
    next
        i = i + 1
        acc = acc + i
    end -> acc
end
]])
assert(typed_loop_back.cmds[#typed_loop_back.cmds] == Back.BackCmdFinalizeModule)

local bad_typed_result, bad_typed_result_diag = S.try_lower_module([[
func bad(flag: bool) -> i32
    return loop () -> i32 while flag
    next
    end -> true
end
]])
assert(bad_typed_result == nil)
assert(bad_typed_result_diag ~= nil)
assert(bad_typed_result_diag.kind == "lower")
assert(bad_typed_result_diag.message:find("typed while expr result", 1, true) ~= nil)

local bad_typed_break, bad_typed_break_diag = S.try_lower_module([[
func bad_break(flag: bool) -> i32
    return loop () -> i32 while flag
        break true
    next
    end -> 0
end
]])
assert(bad_typed_break == nil)
assert(bad_typed_break_diag ~= nil)
assert(bad_typed_break_diag.kind == "lower")
assert(bad_typed_break_diag.message:find("valued break must currently have the loop expression result type", 1, true) ~= nil)

print("moonlift source frontend ok")
