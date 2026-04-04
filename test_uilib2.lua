-- test_uilib2.lua — tests for uilib2 design system + pack-based paint

local pvm = require("pvm")
local ui  = require("uilib2")
local ds  = ui.ds
local T   = ui.T

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1; io.write("  ✓ " .. name .. "\n")
    else fail = fail + 1; io.write("  ✗ " .. name .. "\n") end
end

-- ══════════════════════════════════════════════════════════════
--  1. DS: Theme creation
-- ══════════════════════════════════════════════════════════════

print("── DS: Theme ──")

local theme = ds.theme("dark", {
    colors = {
        { "panel",      0xff161b22 },
        { "panel_hi",   0xff1c2330 },
        { "panel_press",0xff12161e },
        { "danger",     0xffda3633 },
        { "danger_hi",  0xffe04542 },
        { "text_dim",   0xff8b949e },
        { "text_bright",0xffffffff },
    },
    spaces = {
        { "pad_sm", 4 },
        { "pad_md", 8 },
    },
    fonts = {
        { "body", 2 },
    },
})

check("theme created", theme ~= nil)
check("theme name", theme.name == "dark")
check("theme colors count", #theme.colors == 7)

-- ══════════════════════════════════════════════════════════════
--  2. DS: Surface definition
-- ══════════════════════════════════════════════════════════════

print("── DS: Surface ──")

local mute_surface = ds.surface("mute_button",
    -- paint rules
    {
        ds.paint_rule(ds.sel(), {
            ds.bg(ds.ctok("panel")),
            ds.fg(ds.ctok("text_dim")),
        }),
        ds.paint_rule(ds.sel{pointer="hovered"}, {
            ds.bg(ds.ctok("panel_hi")),
        }),
        ds.paint_rule(ds.sel{pointer="pressed"}, {
            ds.bg(ds.ctok("panel_press")),
        }),
        ds.paint_rule(ds.sel{flags={"active"}}, {
            ds.bg(ds.ctok("danger")),
            ds.fg(ds.ctok("text_bright")),
        }),
        ds.paint_rule(ds.sel{pointer="hovered", flags={"active"}}, {
            ds.bg(ds.ctok("danger_hi")),
        }),
    },
    -- struct rules
    {
        ds.struct_rule(ds.ssel(), {
            ds.pad_h(ds.stok("pad_md")),
            ds.pad_v(ds.stok("pad_sm")),
            ds.font(ds.ftok("body")),
        }),
    }
)

check("surface created", mute_surface ~= nil)
check("surface name", mute_surface.name == "mute_button")
check("paint rules count", #mute_surface.paint_rules == 5)
check("struct rules count", #mute_surface.struct_rules == 1)

-- Rebuild theme with surface included
local pvm = require("pvm")
theme = pvm.with(theme, { surfaces = { mute_surface } })

-- ══════════════════════════════════════════════════════════════
--  3. DS: Style resolution
-- ══════════════════════════════════════════════════════════════

print("── DS: Resolve ──")

-- Resolve style for idle, no flags
local q1 = ds.query(theme, "mute_button")
local s1 = ds.resolve(q1)

check("struct: pad_h = 8", s1.pad_h == 8)
check("struct: pad_v = 4", s1.pad_v == 4)
check("struct: font_id = 2", s1.font_id == 2)

-- bg pack: idle=panel, hovered=panel_hi, pressed=panel_press, dragging=panel
check("bg.idle = panel",      s1.bg.idle == 0xff161b22)
check("bg.hovered = panel_hi",s1.bg.hovered == 0xff1c2330)
check("bg.pressed = panel_press", s1.bg.pressed == 0xff12161e)
check("bg.dragging = panel",  s1.bg.dragging == 0xff161b22)

-- fg pack: all phases = text_dim (only default rule matched)
check("fg.idle = text_dim",     s1.fg.idle == 0xff8b949e)
check("fg.hovered = text_dim",  s1.fg.hovered == 0xff8b949e)

-- Resolve with Active flag
local q2 = ds.query(theme, "mute_button", nil, { ds.ACTIVE })
local s2 = ds.resolve(q2)

check("active: bg.idle = danger",     s2.bg.idle == 0xffda3633)
check("active: bg.hovered = danger_hi", s2.bg.hovered == 0xffe04542)
-- Rule 3 (pressed=panel_press) and Rule 4 (active=danger) both match for pressed+active.
-- Last match wins → danger overrides panel_press.
-- Actually: pressed rule has AnyFlags so it matches even with Active. Last match wins.
-- Order: default(panel) → pressed(panel_press) → active(danger)
-- For pressed phase: default matches, pressed matches (panel_press), active matches (danger).
-- Last match wins → danger. Wait let me re-check...
-- Rules in order:
--   1. sel()                        → bg=panel       (matches all)
--   2. sel{pointer=hovered}         → bg=panel_hi    (matches hovered only)
--   3. sel{pointer=pressed}         → bg=panel_press (matches pressed only)
--   4. sel{flags={active}}          → bg=danger      (matches when active)
--   5. sel{pointer=hovered, flags={active}} → bg=danger_hi (matches hovered+active)
-- For pressed+active phase:
--   Rule 1 matches → bg=panel
--   Rule 3 matches → bg=panel_press
--   Rule 4 matches → bg=danger
--   Last match for bg = danger
-- So active: bg.pressed = danger (rule 4 overrides rule 3)
check("active: bg.pressed = danger (active overrides pressed)", s2.bg.pressed == 0xffda3633)
check("active: fg.idle = text_bright", s2.fg.idle == 0xffffffff)

-- Caching: same query should hit
local s2b = ds.resolve(q2)
check("resolve cache hit (identity)", s2 == s2b)

-- Different query should miss
local q3 = ds.query(theme, "mute_button", ds.FOCUSED, {})
local s3 = ds.resolve(q3)
check("different query = different style", s3 ~= s2)
check("focused no flags: bg.idle = panel", s3.bg.idle == 0xff161b22)

-- ══════════════════════════════════════════════════════════════
--  4. DS: Solid pack helper
-- ══════════════════════════════════════════════════════════════

print("── DS: Solid pack ──")

local sp = ui.solid(0xffaabbcc)
check("solid: all phases equal", sp.idle == sp.hovered and sp.hovered == sp.pressed and sp.pressed == sp.dragging)
check("solid: value correct", sp.idle == 0xffaabbcc)

-- Interning
local sp2 = ui.solid(0xffaabbcc)
check("solid interning", sp == sp2)

-- ══════════════════════════════════════════════════════════════
--  5. UI: Build with ColorPack
-- ══════════════════════════════════════════════════════════════

print("── UI: Build ──")

local box, px = ui.box, ui.px

local btn = ui.stack({
    ui.rect("btn:mute", s1.bg, box{ w = px(100), h = px(30) }),
    ui.text("btn:mute:label", "M",
        ui.text_style{ font_id = s1.font_id, color = s1.fg },
        box{ w = px(100), h = px(30) }),
})

check("stack created", btn ~= nil)
check("stack kind", btn.kind == "Stack")

-- Row with solid colors (non-themed)
local panel = ui.row(4, {
    ui.rect("", ui.solid(0xff222222), box{ w = px(200), h = px(40) }),
    btn,
})

check("row created", panel ~= nil)

-- ══════════════════════════════════════════════════════════════
--  6. Compile
-- ══════════════════════════════════════════════════════════════

print("── Compile ──")

local cmds = ui.compile(btn, 100, 30)
check("compiled to commands", #cmds > 0)

-- Find the rect command
local rect_cmd = nil
for i = 1, #cmds do
    if cmds[i].kind == T.View.Rect and cmds[i].htag == "btn:mute" then
        rect_cmd = cmds[i]; break
    end
end
check("found rect cmd", rect_cmd ~= nil)
check("rect has color pack", rect_cmd.color ~= nil)
check("rect color.idle = panel", rect_cmd.color.idle == 0xff161b22)
check("rect color.hovered = panel_hi", rect_cmd.color.hovered == 0xff1c2330)

-- Find the text command
local text_cmd = nil
for i = 1, #cmds do
    if cmds[i].kind == T.View.TextBlock and cmds[i].htag == "btn:mute:label" then
        text_cmd = cmds[i]; break
    end
end
check("found text cmd", text_cmd ~= nil)
check("text color.idle = text_dim", text_cmd.color.idle == 0xff8b949e)

-- ══════════════════════════════════════════════════════════════
--  7. Measure
-- ══════════════════════════════════════════════════════════════

print("── Measure ──")

local m = ui.measure(btn)
check("measure width", m.used_w == 100)
check("measure height", m.used_h == 30)

-- Flex measure
local row = ui.row(10, {
    ui.rect("a", ui.solid(0xff000000), box{ w = px(50), h = px(20) }),
    ui.rect("b", ui.solid(0xff000000), box{ w = px(60), h = px(20) }),
})
local rm = ui.measure(row)
check("row measure: width = 50+10+60 = 120", rm.used_w == 120)
check("row measure: height = 20", rm.used_h == 20)

-- ══════════════════════════════════════════════════════════════
--  8. Hit test
-- ══════════════════════════════════════════════════════════════

print("── Hit test ──")

local hit_cmds = ui.compile(ui.stack({
    ui.rect("bg", ui.solid(0xff000000), box{ w = px(200), h = px(100) }),
    ui.transform(10, 10,
        ui.rect("btn", ui.solid(0xffff0000), box{ w = px(50), h = px(30) })),
}), 200, 100)

check("hit inside btn", ui.hit(hit_cmds, 20, 20) == "btn")
check("hit outside btn", ui.hit(hit_cmds, 100, 50) == "bg")
check("hit outside all", ui.hit(hit_cmds, 300, 300) == nil)

-- ══════════════════════════════════════════════════════════════
--  9. Fragment / Plan
-- ══════════════════════════════════════════════════════════════

print("── Fragment / Plan ──")

local frag = ui.fragment(ui.rect("f", ui.solid(0xffff0000), box{ w = px(40), h = px(20) }), 40, 20)
check("fragment created", frag ~= nil)
check("fragment has cmds", #frag.cmds > 0)

local p = ui.plan({
    ui.place_fragment(10, 20, frag),
})
local plan_cmds = ui.assemble(p)
check("plan assembled", #plan_cmds > 0)
-- Should have PushTx, Rect, PopTx
check("plan has transform wrap", plan_cmds[1].kind == T.View.PushTransform)

-- ══════════════════════════════════════════════════════════════
--  10. Design system interning / caching
-- ══════════════════════════════════════════════════════════════

print("── Interning / Caching ──")

-- Same query → same object
local qa = ds.query(theme, "mute_button", ds.BLURRED, {})
local qb = ds.query(theme, "mute_button", ds.BLURRED, {})
check("query interning", qa == qb)

-- Same style resolution → same object
local sa = ds.resolve(qa)
local sb = ds.resolve(qb)
check("style interning via resolve cache", sa == sb)

-- ColorPack interning
local p1 = T.DS.ColorPack(1, 2, 3, 4)
local p2 = T.DS.ColorPack(1, 2, 3, 4)
check("color pack interning", p1 == p2)

-- ══════════════════════════════════════════════════════════════
--  11. Report
-- ══════════════════════════════════════════════════════════════

print("── Report ──")
print(ui.report())

-- ══════════════════════════════════════════════════════════════

print(string.format("\n══ %d passed, %d failed ══", pass, fail))
if fail > 0 then os.exit(1) end
