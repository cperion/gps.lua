-- test_uilib_iter.lua — smoke/regression tests for canonical immediate/session uilib

local iter = require("iter")
local ui = require("uilib")
local ds = ui.ds

local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1; io.write("  ✓ " .. name .. "\n")
    else fail = fail + 1; io.write("  ✗ " .. name .. "\n") end
end

print("── Immediate DS parity ──")

local theme = ds.theme("iter-dark", {
    colors = {
        { "panel", 0xff161b22 },
        { "panel_hi", 0xff1c2330 },
        { "text", 0xffe6edf3 },
    },
    spaces = {
        { "pad_sm", 4 },
    },
    fonts = {
        { "body", 2 },
    },
    surfaces = {
        ds.surface("chip", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("panel")),
                ds.fg(ds.ctok("text")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.bg(ds.ctok("panel_hi")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("pad_sm")),
                ds.font(ds.ftok("body")),
            }),
        }),
    },
})

local chip = ds.resolve(ds.query(theme, "chip"))
check("theme resolves style", chip ~= nil)
check("chip idle bg", chip.bg.idle == 0xff161b22)
check("chip hovered bg", chip.bg.hovered == 0xff1c2330)
check("chip font", chip.font_id == 2)

print("── Child-source normalization ──")

local row = ui.row(0, ui.each(iter.range(3), function(i)
    return ui.rect("r" .. i, ui.solid(0xff000000 + i), ui.box { w = ui.px(10), h = ui.px(5) })
end))
local m = ui.measure(row)
check("iter row width", m.used_w == 30)
check("iter row height", m.used_h == 5)

local stacked = ui.stack(ui.concat({
    ui.when(true, ui.rect("a", ui.solid(0xff00ff00), ui.box { w = ui.px(4), h = ui.px(4) })),
    ui.when(false, ui.rect("b", ui.solid(0xffff0000), ui.box { w = ui.px(4), h = ui.px(4) })),
    iter.once(ui.rect("c", ui.solid(0xff0000ff), ui.box { w = ui.px(4), h = ui.px(4) })),
}))
local ops = ui.collect(stacked, 4, 4)
local rects = 0
for i = 1, #ops do if ops[i].op == "fill_rect" then rects = rects + 1 end end
check("concat/when/iter flatten children", rects == 2)

print("── Immediate hit testing ──")

local hit_node = ui.stack({
    ui.rect("bg", ui.solid(0xff000000), ui.box { w = ui.px(50), h = ui.px(30) }),
    ui.transform(10, 8,
        ui.clip(
            ui.rect("btn", ui.solid(0xffff0000), ui.box { w = ui.px(20), h = ui.px(10) }),
            ui.box { w = ui.px(20), h = ui.px(10) }))
})
check("hit immediate inside transformed child", ui.hit(hit_node, ui.frame(0, 0, 50, 30), 12, 10) == "btn")
check("hit immediate outside child falls back", ui.hit(hit_node, ui.frame(0, 0, 50, 30), 2, 2) == "bg")
check("hit immediate outside all nil", ui.hit(hit_node, ui.frame(0, 0, 50, 30), 80, 80) == nil)

print("── Immediate text shaping ──")

ui.set_font(0, {
    getWidth = function(_, s)
        local n = 0
        for _ in string.gmatch(s, "[\1-\127\194-\244][\128-\191]*") do n = n + 1 end
        return n * 8
    end,
    getHeight = function() return 16 end,
    getLineHeight = function() return 1 end,
    setLineHeight = function() end,
    getBaseline = function() return 12 end,
})

local ellipsis = ui.text("ellipsis", "Hello",
    ui.text_style { overflow = ui.OVERFLOW_ELLIPSIS },
    ui.box { w = ui.px(16), h = ui.px(20) })
local text_ops = ui.collect(ellipsis, 16, 20)
local shaped_text
for i = 1, #text_ops do
    if text_ops[i].op == "text" then shaped_text = text_ops[i].text; break end
end
check("collect records shaped text", shaped_text == "H…")

print("── Generic paint bridge ──")

local paint = ui.paint_group({
    ui.paint_transform(3, 4,
        ui.paint_rect("meter", ui.num_ref("x"), 2, 6, 5, ui.color_ref("meter_color"))),
    ui.paint_text("runtime_text", 0, 0, 32, 20,
        ui.text_style { overflow = ui.OVERFLOW_ELLIPSIS },
        ui.text_ref("label")),
})
local paint_ops = ui.collect_paint(paint, {
    numbers = { x = 7 },
    texts = { label = "Hello" },
    colors = { meter_color = 0xff112233 },
})
local saw_transform, saw_rect, saw_text = false, false, false
for i = 1, #paint_ops do
    local op = paint_ops[i].op
    if op == "push_transform" then saw_transform = (paint_ops[i].tx == 3 and paint_ops[i].ty == 4) or saw_transform end
    if op == "fill_rect" then saw_rect = (paint_ops[i].x == 7 and paint_ops[i].y == 2) or saw_rect end
    if op == "text" then saw_text = (paint_ops[i].text == "Hel…") or saw_text end
end
check("paint bridge transform", saw_transform)
check("paint bridge rect", saw_rect)
check("paint bridge shaped text", saw_text)

print("── Embedded custom paint ──")

local custom_root = ui.stack({
    ui.rect("shell", ui.solid(0xff000000), ui.box { w = ui.px(30), h = ui.px(24) }),
    ui.transform(4, 5,
        ui.custom(
            ui.paint_group({
                ui.paint_rect("live", ui.num_ref("x"), 1, 6, 4, ui.color_ref("accent")),
                ui.paint_text("live:text", 0, 0, 20, 20,
                    ui.text_style { overflow = ui.OVERFLOW_ELLIPSIS },
                    ui.text_ref("label")),
            }),
            ui.box { w = ui.px(20), h = ui.px(20) }))
})
local custom_ops = ui.collect(custom_root, 30, 24, {
    env = {
        numbers = { x = 7 },
        texts = { label = "Hello" },
        colors = { accent = 0xff336699 },
    },
})
local custom_rect, custom_text = false, false
for i = 1, #custom_ops do
    if custom_ops[i].op == "fill_rect" and custom_ops[i].x == 7 and custom_ops[i].y == 1 then custom_rect = true end
    if custom_ops[i].op == "text" and custom_ops[i].text == "H…" then custom_text = true end
end
check("custom node draws runtime rect", custom_rect)
check("custom node draws runtime text", custom_text)

print("── Explicit state ──")

local state = ui.state()
local next_state = select(1, ui.step_frame(hit_node, {
    frame = ui.frame(0, 0, 50, 30),
    input = { mouse_x = 12, mouse_y = 10 },
    state = state,
}))
check("step_frame updates hot id", next_state.hot == "btn")
local cloned = ui.clone_state(next_state)
cloned.hot = "other"
check("clone_state deep copies", next_state.hot == "btn" and cloned.hot == "other")

print("── Session API ──")

local session = ui.session({ state = ui.state() })
local st1 = select(1, session:frame(hit_node, {
    frame = ui.frame(0, 0, 50, 30),
    input = { mouse_x = 12, mouse_y = 10, mouse_pressed = true, mouse_down = true },
    draw = false,
}))
check("session frame updates hover", st1.hot == "btn")
check("session frame sets active", st1.active == "btn")
local st2, msgs2 = session:frame(hit_node, {
    frame = ui.frame(0, 0, 50, 30),
    input = { mouse_x = 12, mouse_y = 10, mouse_released = true },
    draw = false,
})
check("session click emits message", msgs2.n == 1 and msgs2.kind[1] == "click" and msgs2.id[1] == "btn")
check("session clears active on release", st2.active == nil and st2.pressed == nil)

print("\n══ " .. pass .. " passed, " .. fail .. " failed ══")
os.exit(fail == 0 and 0 or 1)
