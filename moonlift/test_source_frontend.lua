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
    loop i: index = 0, acc: i32 = 0 while i < 3
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
    loop i: index = 0 while i < n
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

print("moonlift source frontend ok")
