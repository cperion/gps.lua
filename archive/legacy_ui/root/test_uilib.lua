-- test_uilib.lua — tests for uilib design system + pack-based paint

local pvm = require("pvm")
local ui  = require("uilib")
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
--  11. Generic custom paint
-- ══════════════════════════════════════════════════════════════

print("── Generic custom paint ──")

local overlay = ui.paint_group({
    ui.paint_transform(5, 7,
        ui.paint_rect("meter", ui.num_ref("playhead_x"), 2, 10, 4, ui.color_ref("meter_color"))),
    ui.paint_line("cursor", ui.num_ref("playhead_x"), 0, ui.num_ref("playhead_x"), 40, 2, ui.solid(0xffffffff)),
    ui.paint_text("runtime_text", 0, 0, 32, 20,
        ui.text_style { overflow = ui.OVERFLOW_ELLIPSIS },
        ui.text_ref("transport_time")),
})

local paint_cmds = ui.compile_paint(overlay)
check("paint compiled", #paint_cmds > 0)
check("paint compile cached", overlay:compile() == paint_cmds)
check("paint starts with push transform", paint_cmds[1].kind == T.Paint.PushTransformCmd)
check("paint includes fill rect", paint_cmds[2].kind == T.Paint.FillRectCmd)
check("paint includes line", paint_cmds[4].kind == T.Paint.LineCmd)
check("paint includes runtime text", paint_cmds[5].kind == T.Paint.TextCmd)

local paint_log = {}
local backend = {
    set_color = function(_, ...) paint_log[#paint_log + 1] = { op = "color", args = { ... } } end,
    fill_rect = function(_, x, y, w, h) paint_log[#paint_log + 1] = { op = "rect", mode = "fill", x = x, y = y, w = w, h = h } end,
    stroke_rect = function(_, x, y, w, h, thickness) paint_log[#paint_log + 1] = { op = "rect", mode = "line", x = x, y = y, w = w, h = h, thickness = thickness } end,
    draw_line = function(_, x1, y1, x2, y2, thickness) paint_log[#paint_log + 1] = { op = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2, thickness = thickness } end,
    draw_text = function(_, text, x, y, w, align)
        paint_log[#paint_log + 1] = { op = w and "printf" or "print", text = text, x = x, y = y, w = w, align = align }
    end,
    push_clip = function(_, ...) paint_log[#paint_log + 1] = { op = "push_clip", args = { ... } } end,
    pop_clip = function(_) paint_log[#paint_log + 1] = { op = "pop_clip" } end,
    push_transform = function(_, tx, ty) paint_log[#paint_log + 1] = { op = "translate", tx = tx, ty = ty } end,
    pop_transform = function(_) paint_log[#paint_log + 1] = { op = "pop_transform" } end,
    set_font = function(_, font) paint_log[#paint_log + 1] = { op = "font", font = font } end,
}

ui.set_backend(backend)
ui.paint_custom(paint_cmds, {
    numbers = { playhead_x = 11 },
    texts = { transport_time = "Hello" },
    colors = { meter_color = 0xff112233 },
})
ui.set_backend(nil)

local function find_log(op)
    for i = 1, #paint_log do
        if paint_log[i].op == op then return paint_log[i] end
    end
    return nil
end

local tf = find_log("translate")
check("paint runtime resolved transform", tf and tf.tx == 5 and tf.ty == 7)
local rect_log = find_log("rect")
check("paint runtime resolved rect geometry", rect_log and rect_log.mode == "fill" and rect_log.x == 11 and rect_log.y == 2 and rect_log.w == 10 and rect_log.h == 4)
local line_log = find_log("line")
check("paint runtime resolved line geometry", line_log and line_log.x1 == 11 and line_log.y1 == 0 and line_log.x2 == 11 and line_log.y2 == 40)
local printf_log = find_log("printf")
check("paint runtime resolved dynamic text with ellipsis", printf_log and printf_log.text == "H…")

-- ══════════════════════════════════════════════════════════════
--  12. Text edge cases / cache clearing
-- ══════════════════════════════════════════════════════════════

print("── Text edge cases / cache clearing ──")

local function text_for(tag, cmds)
    for i = 1, #cmds do
        local c = cmds[i]
        if c.kind == T.View.TextBlock and c.htag == tag then return c.text end
    end
    return nil
end

local ellipsis_cmds = ui.compile(
    ui.text("ellipsis", "Hello", ui.text_style { overflow = ui.OVERFLOW_ELLIPSIS }, box { w = px(32), h = px(20) }),
    32, 20)
check("nowrap ellipsis clips at compile time", text_for("ellipsis", ellipsis_cmds) == "H…")

local clip_cmds = ui.compile(
    ui.text("clip", "Hello", ui.text_style { overflow = ui.OVERFLOW_CLIP }, box { w = px(16), h = px(20) }),
    16, 20)
check("nowrap clip clips at compile time", text_for("clip", clip_cmds) == "He")

local utf8_wrap_cmds = ui.compile(
    ui.text("utf8", "éé", ui.text_style { wrap = ui.TEXT_CHARWRAP, overflow = ui.OVERFLOW_CLIP }, box { w = px(16), h = px(40) }),
    16, 40)
check("utf8 char wrap keeps codepoints intact", text_for("utf8", utf8_wrap_cmds) == "é\né")

local ws_cmds = ui.compile(
    ui.text("ws", "a  b", ui.text_style { wrap = ui.TEXT_WORDWRAP, overflow = ui.OVERFLOW_CLIP }, box { w = px(64), h = px(20) }),
    64, 20)
check("word wrap preserves repeated spaces", text_for("ws", ws_cmds) == "a  b")

local ok_clear = pcall(ui.clear_cache)
check("clear_cache does not crash", ok_clear)
local after_clear_cmds = ui.compile(btn, 100, 30)
check("compile works after clear_cache", #after_clear_cmds > 0)

-- ══════════════════════════════════════════════════════════════
--  13. Report
-- ══════════════════════════════════════════════════════════════

print("── Report ──")
print(ui.report())

-- ══════════════════════════════════════════════════════════════

print(string.format("\n══ %d passed, %d failed ══", pass, fail))
if fail > 0 then os.exit(1) end
