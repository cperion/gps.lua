package.path = "../../?.lua;../../?/init.lua;../?.lua;../?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ui = require("ui")
local pvm = require("pvm")

local T = ui.T
local tw = ui.tw
local b = ui.build

local TEXT_SYSTEM = "ui-love-demo"
local LIST_SCROLL_ID = b.id("list-scroll")

local app = {
    selected_id = "task-1",
    items = {},
}

local ui_model
local last_report = nil
local theme
local env_class
local driver

local function P(s50, s100, s200, s300, s400, s500, s600, s700, s800, s900, s950)
    return T.Theme.Palette(s50, s100, s200, s300, s400, s500, s600, s700, s800, s900, s950)
end

local function make_theme()
    local spacing = {}
    for i = 1, 35 do spacing[i] = i end
    return T.Theme.T(
        P(0xf8fafcff, 0xf1f5f9ff, 0xe2e8f0ff, 0xcbd5e1ff, 0x94a3b8ff, 0x64748bff, 0x475569ff, 0x334155ff, 0x1e293bff, 0x0f172aff, 0x020617ff),
        P(0xf9fafbff, 0xf3f4f6ff, 0xe5e7ebff, 0xd1d5dbff, 0x9ca3afff, 0x6b7280ff, 0x4b5563ff, 0x374151ff, 0x1f2937ff, 0x111827ff, 0x030712ff),
        P(0xfafafaff, 0xf4f4f5ff, 0xe4e4e7ff, 0xd4d4d8ff, 0xa1a1aaff, 0x71717aff, 0x52525bff, 0x3f3f46ff, 0x27272aff, 0x18181bff, 0x09090bff),
        P(0xfafafaff, 0xf5f5f5ff, 0xe5e5e5ff, 0xd4d4d4ff, 0xa3a3a3ff, 0x737373ff, 0x525252ff, 0x404040ff, 0x262626ff, 0x171717ff, 0x0a0a0aff),
        P(0xfafaf9ff, 0xf5f5f4ff, 0xe7e5e4ff, 0xd6d3d1ff, 0xa8a29eff, 0x78716cff, 0x57534eff, 0x44403cff, 0x292524ff, 0x1c1917ff, 0x0c0a09ff),
        P(0xfef2f2ff, 0xfee2e2ff, 0xfecacaff, 0xfca5a5ff, 0xf87171ff, 0xef4444ff, 0xdc2626ff, 0xb91c1cff, 0x991b1bff, 0x7f1d1dff, 0x450a0aff),
        P(0xfff7edff, 0xffedd5ff, 0xfed7aaff, 0xfdba74ff, 0xfb923cff, 0xf97316ff, 0xea580cff, 0xc2410cff, 0x9a3412ff, 0x7c2d12ff, 0x431407ff),
        P(0xfffbebff, 0xfef3c7ff, 0xfde68aff, 0xfcd34dff, 0xfbbf24ff, 0xf59e0bff, 0xd97706ff, 0xb45309ff, 0x92400eff, 0x78350fff, 0x451a03ff),
        P(0xfefce8ff, 0xfef9c3ff, 0xfef08aff, 0xfde047ff, 0xfacc15ff, 0xeab308ff, 0xca8a04ff, 0xa16207ff, 0x854d0eff, 0x713f12ff, 0x422006ff),
        P(0xf7fee7ff, 0xecfccbff, 0xd9f99dff, 0xbef264ff, 0xa3e635ff, 0x84cc16ff, 0x65a30dff, 0x4d7c0fff, 0x3f6212ff, 0x365314ff, 0x1a2e05ff),
        P(0xf0fdf4ff, 0xdcfce7ff, 0xbbf7d0ff, 0x86efacff, 0x4ade80ff, 0x22c55eff, 0x16a34aff, 0x15803dff, 0x166534ff, 0x14532dff, 0x052e16ff),
        P(0xecfdf5ff, 0xd1fae5ff, 0xa7f3d0ff, 0x6ee7b7ff, 0x34d399ff, 0x10b981ff, 0x059669ff, 0x047857ff, 0x065f46ff, 0x064e3bff, 0x022c22ff),
        P(0xf0fdfaff, 0xccfbf1ff, 0x99f6e4ff, 0x5eead4ff, 0x2dd4bfff, 0x14b8a6ff, 0x0d9488ff, 0x0f766eff, 0x115e59ff, 0x134e4aff, 0x042f2eff),
        P(0xecfeffff, 0xcffafeff, 0xa5f3fcff, 0x67e8f9ff, 0x22d3eeff, 0x06b6d4ff, 0x0891b2ff, 0x0e7490ff, 0x155e75ff, 0x164e63ff, 0x083344ff),
        P(0xf0f9ffff, 0xe0f2feff, 0xbae6fdff, 0x7dd3fcff, 0x38bdf8ff, 0x0ea5e9ff, 0x0284c7ff, 0x0369a1ff, 0x075985ff, 0x0c4a6eff, 0x082f49ff),
        P(0xeff6ffff, 0xdbeafeff, 0xbfdbfeff, 0x93c5fdff, 0x60a5faff, 0x3b82f6ff, 0x2563ebff, 0x1d4ed8ff, 0x1e40afff, 0x1e3a8aff, 0x172554ff),
        P(0xeef2ffff, 0xe0e7ffff, 0xc7d2feff, 0xa5b4fcff, 0x818cf8ff, 0x6366f1ff, 0x4f46e5ff, 0x4338caff, 0x3730a3ff, 0x312e81ff, 0x1e1b4bff),
        P(0xf5f3ffff, 0xede9feff, 0xddd6feff, 0xc4b5fdff, 0xa78bfaff, 0x8b5cf6ff, 0x7c3aedff, 0x6d28d9ff, 0x5b21b6ff, 0x4c1d95ff, 0x2e1065ff),
        P(0xfaf5ffff, 0xf3e8ffff, 0xe9d5ffff, 0xd8b4feff, 0xc084fcff, 0xa855f7ff, 0x9333eaff, 0x7e22ceff, 0x6b21a8ff, 0x581c87ff, 0x3b0764ff),
        P(0xfdf4ffff, 0xfae8ffff, 0xf5d0feff, 0xf0abfcff, 0xe879f9ff, 0xd946efff, 0xc026d3ff, 0xa21cafff, 0x86198fff, 0x701a75ff, 0x4a044eff),
        P(0xfdf2f8ff, 0xfce7f3ff, 0xfbcfe8ff, 0xf9a8d4ff, 0xf472b6ff, 0xec4899ff, 0xdb2777ff, 0xbe185dff, 0x9d174dff, 0x831843ff, 0x500724ff),
        P(0xfff1f2ff, 0xffe4e6ff, 0xfecdd3ff, 0xfda4afff, 0xfb7185ff, 0xf43f5eff, 0xe11d48ff, 0xbe123cff, 0x9f1239ff, 0x881337ff, 0x4c0519ff),
        0xffffffff,
        0x000000ff,
        0x00000000,
        T.Theme.SpaceScale(unpack(spacing)),
        T.Theme.FontScale(12, 14, 16, 18, 20, 24, 30, 36, 48, 60),
        T.Theme.RadiusScale(0, 2, 4, 6, 8, 12, 16, 24, 9999),
        T.Theme.BorderScale(0, 1, 2, 4, 8),
        T.Theme.OpacityScale(0, 5, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95, 100),
        T.Theme.Fonts(1, 2, 3, 4, 5)
    )
end

local function install_fonts()
    local fonts = {
        [1] = love.graphics.newFont(14),
        [2] = love.graphics.newFont(16),
        [3] = love.graphics.newFont(18),
        [4] = love.graphics.newFont(24),
    }
    ui.text.register(TEXT_SYSTEM, ui.text_love.new({ fonts = fonts }))
    driver = ui.runtime_love.new({ fonts = fonts })
end

local function scroll_y()
    local _, y = ui.interact.scroll_offset(ui_model, LIST_SCROLL_ID)
    return y
end

local function selected_item()
    for i = 1, #app.items do
        local item = app.items[i]
        if item.id == app.selected_id then
            return item
        end
    end
    return app.items[1]
end

local function focused_id_value()
    if ui_model.focus_id == T.Core.NoId then return nil end
    return ui_model.focus_id.value
end

local function hover_id_value()
    if ui_model.hover_id == T.Core.NoId then return nil end
    return ui_model.hover_id.value
end

local function item_row(item)
    local selected = item.id == app.selected_id
    local focused = item.id == focused_id_value()
    local hovered = item.id == hover_id_value()

    return b.with_input(b.id(item.id), T.Interact.ActivateTarget,
        b.box {
            b.id(item.id .. "-card"),
            tw.flow,
            tw.gap_y_2,
            tw.p_3,
            tw.rounded_lg,
            tw.cursor_pointer,
            (focused or hovered) and tw.border_2 or tw.border_1,
            focused and tw.border_color.sky[400]
                or hovered and tw.border_color.blue[400]
                or tw.border_color.slate[700],
            selected and tw.bg.blue[700]
                or hovered and tw.bg.slate[800]
                or tw.bg.slate[900],
            b.text { tw.text_base, tw.font_semibold, tw.fg.white, item.title },
            b.text {
                tw.text_sm,
                selected and tw.fg.sky[100]
                    or hovered and tw.fg.slate[200]
                    or tw.fg.slate[300],
                item.note,
            },
        })
end

local function build_ui(vw, vh)
    local detail = selected_item()
    local list_children = {}
    for i = 1, #app.items do
        list_children[i] = item_row(app.items[i])
    end

    return b.box {
        b.id("root"),
        tw.flex, tw.row,
        tw.w_px(vw), tw.h_px(vh),
        tw.bg.slate[950],

        b.box {
            b.id("sidebar"),
            tw.flow,
            tw.w_px(320), tw.h_px(vh),
            tw.p_4,
            tw.gap_y_4,
            tw.bg.slate[900],
            tw.border_1,
            tw.border_color.slate[800],

            b.text { tw.text_xl, tw.font_semibold, tw.fg.white, "ui/ live demo" },
            b.text {
                tw.text_sm, tw.fg.slate[300],
                "Scroll the list, click items, or press Tab / Shift+Tab to move focus."
            },

            b.box {
                LIST_SCROLL_ID,
                tw.flow,
                tw.h_px(vh - 132),
                tw.gap_y_2,
                tw.pr_2,
                tw.overflow_y_scroll,
                b.fragment(list_children),
            },
        },

        b.box {
            b.id("detail"),
            tw.flow,
            tw.w_px(vw - 320), tw.h_px(vh),
            tw.p_6,
            tw.gap_y_4,
            tw.bg.slate[950],

            b.text { tw.text_sm, tw.fg.sky[300], "selected" },
            b.text { tw.text_xl, tw.font_semibold, tw.fg.white, detail.title },
            b.text { tw.text_base, tw.fg.slate[200], detail.note },
            b.box {
                b.id("detail-card"),
                tw.flow,
                tw.gap_y_3,
                tw.p_4,
                tw.rounded_xl,
                tw.border_1,
                tw.border_color.slate[800],
                tw.bg.slate[900],
                b.text { tw.text_sm, tw.fg.slate[400], "focused id" },
                b.text { tw.text_lg, tw.font_semibold, tw.fg.white, focused_id_value() or "none" },
                b.text { tw.text_sm, tw.fg.slate[400], "scroll y" },
                b.text { tw.text_lg, tw.font_semibold, tw.fg.white, tostring(scroll_y()) },
            },
        },
    }
end

local function cursor_label(cursor)
    if cursor == T.Style.CursorPointer then return "pointer" end
    if cursor == T.Style.CursorText then return "text" end
    if cursor == T.Style.CursorMove then return "move" end
    if cursor == T.Style.CursorGrab then return "grab" end
    if cursor == T.Style.CursorGrabbing then return "grabbing" end
    if cursor == T.Style.CursorNotAllowed then return "not-allowed" end
    return "default"
end

local function apply_app_event(event)
    local cls = pvm.classof(event)
    if cls == T.Interact.Activate then
        app.selected_id = event.id.value
    elseif cls == T.Interact.SetFocus then
        app.selected_id = event.id.value
    end
end

local function dispatch_raw(raw)
    if last_report == nil then
        local cls = pvm.classof(raw)
        if cls == T.Interact.PointerMoved or cls == T.Interact.PointerPressed or cls == T.Interact.PointerReleased or cls == T.Interact.WheelMoved then
            ui_model = ui.interact.apply(ui_model, T.Interact.SetPointer(raw.x, raw.y))
        end
        return
    end

    local events
    ui_model, events = ui.interact.step(ui_model, last_report, raw)
    for i = 1, #events do
        apply_app_event(events[i])
    end
end

local function compile_and_draw()
    local vw, vh = love.graphics.getDimensions()
    local mx, my = love.mouse.getPosition()
    if mx ~= ui_model.pointer_x or my ~= ui_model.pointer_y then
        ui_model = ui.interact.apply(ui_model, T.Interact.SetPointer(mx, my))
    end

    local function run_once()
        local auth = build_ui(vw, vh)
        local layout = pvm.one(ui.lower.phase(auth, theme, env_class))
        driver:reset()
        return ui.runtime.run(driver, {
            pointer_x = ui_model.pointer_x,
            pointer_y = ui_model.pointer_y,
            scrolls = ui_model.scrolls,
        }, ui.render.root(layout, T.Solve.Env(vw, vh, {}), TEXT_SYSTEM))
    end

    last_report = run_once()
    ui_model = ui.interact.clamp_model(ui_model, last_report)
    local next_model = ui.interact.step(ui_model, last_report, ui.interact.pointer_moved(ui_model.pointer_x, ui_model.pointer_y))
    if next_model ~= ui_model then
        ui_model = next_model
        last_report = run_once()
    end

    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setColor(0.72, 0.80, 0.96, 1)
    love.graphics.setFont(driver:get_font(T.Layout.TextStyle(1, 14, 400, 0xffffffff, 0, 20, 0, "")))
    love.graphics.print(string.format(
        "hover=%s  focusables=%d  cursor=%s",
        hover_id_value() or "none",
        #last_report.focusables,
        cursor_label(last_report.cursor)
    ), 12, vh - 24)
    love.graphics.setColor(1, 1, 1, 1)
end

function love.load()
    love.graphics.setBackgroundColor(0.03, 0.05, 0.08, 1)
    theme = make_theme()
    env_class = T.Env.Class(T.Env.Md, T.Env.Dark, T.Env.MotionSafe, T.Env.D2x)
    install_fonts()

    for i = 1, 30 do
        app.items[i] = {
            id = "task-" .. i,
            title = (i % 3 == 0 and "Ship milestone " or i % 2 == 0 and "Review patch " or "Plan sprint ") .. i,
            note = "This item exists to exercise flow, flex, scrolling, text measurement, and op-stream interaction consumption.",
        }
    end

    ui_model = ui.interact.model {
        focus_id = b.id(app.selected_id),
        scrolls = { T.Solve.Scroll(LIST_SCROLL_ID, 0, 0) },
    }
end

function love.mousemoved(x, y)
    dispatch_raw(ui.interact.pointer_moved(x, y))
end

function love.mousepressed(x, y, button)
    dispatch_raw(ui.interact.pointer_pressed(ui.interact.button_from_love(button), x, y))
end

function love.mousereleased(x, y, button)
    dispatch_raw(ui.interact.pointer_released(ui.interact.button_from_love(button), x, y))
end

function love.wheelmoved(x, y)
    dispatch_raw(ui.interact.wheel_moved(x * 28, -y * 28, ui_model.pointer_x, ui_model.pointer_y))
end

function love.keypressed(key)
    if key == "tab" then
        dispatch_raw(love.keyboard.isDown("lshift", "rshift") and ui.interact.focus_prev() or ui.interact.focus_next())
    elseif key == "return" or key == "space" then
        dispatch_raw(ui.interact.activate_focus())
    elseif key == "down" then
        ui_model = ui.interact.apply(ui_model, T.Interact.ScrollBy(LIST_SCROLL_ID, 0, 28), last_report)
    elseif key == "up" then
        ui_model = ui.interact.apply(ui_model, T.Interact.ScrollBy(LIST_SCROLL_ID, 0, -28), last_report)
    end
end

function love.draw()
    compile_and_draw()
end
