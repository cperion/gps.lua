package.path = "../../?.lua;../../?/init.lua;../?.lua;../?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ui = require("ui")
local pvm = require("pvm")
local studio_asdl = require("demo_asdl")
local demo_apply = require("demo_apply")
local widgets = require("widgets")

local T = studio_asdl.T

local TEXT_SYSTEM = "ui-studio-demo"
local BROWSER_SCROLL_ID = T.Core.IdValue("browser-scroll")

local state
local last_report = nil
local theme
local driver
local hud_font
local show_hud = false
local perf = {
    frame_ms = 0,
    compile_ms = 0,
    auth_ms = 0,
    lower_ms = 0,
    runtime_ms = 0,
    avg_frame_ms = 0,
    avg_compile_ms = 0,
    avg_auth_ms = 0,
    avg_lower_ms = 0,
    avg_runtime_ms = 0,
    dt_ms = 0,
    rebuilds_frame = 0,
    rebuilds_total = 0,
    ui_events = 0,
    app_events = 0,
    hover_rerun = false,
    pending_action_at = nil,
    pending_action_serial = 0,
    rendered_action_serial = 0,
    pending_action_label = nil,
    last_action_label = "none",
    action_to_render_ms = 0,
}

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

local function current_env_class()
    local mode = state and state.app.theme_mode or T.Studio.ThemeDark
    return T.Env.Class(T.Env.Lg, mode == T.Studio.ThemeLight and T.Env.Light or T.Env.Dark, T.Env.MotionSafe, T.Env.D2x)
end

local function install_fonts()
    local fonts = {
        [1] = love.graphics.newFont(13),
        [2] = love.graphics.newFont(15),
        [3] = love.graphics.newFont(18),
        [4] = love.graphics.newFont(28),
    }
    hud_font = love.graphics.newFont(12)
    ui.text.register(TEXT_SYSTEM, ui.text_love.new({ fonts = fonts }))
    driver = ui.runtime_love.new({ fonts = fonts })
end

local function now_ms()
    return love.timer.getTime() * 1000
end

local function update_avg(key, value)
    local avg_key = "avg_" .. key
    local prev = perf[avg_key]
    if prev == nil or prev == 0 then
        perf[avg_key] = value
    else
        perf[avg_key] = prev + (value - prev) * 0.15
    end
end

local function mark_action(label)
    perf.pending_action_serial = perf.pending_action_serial + 1
    perf.pending_action_at = now_ms()
    perf.pending_action_label = label or "action"
end

local function apply_ui_model(next_ui_model)
    state = demo_apply.with_ui_model(state, next_ui_model)
end

local function build_ui(vw, vh)
    return widgets.auth_root(state, vw, vh)
end

local function dispatch_raw(raw, label)
    if label ~= nil then
        mark_action(label)
    end
    local next_state, ui_events, app_events = demo_apply.step(state, last_report, raw)
    state = next_state
    perf.ui_events = #ui_events
    perf.app_events = #app_events
end

local function run_frame(vw, vh, accum)
    local t0 = now_ms()
    local auth = build_ui(vw, vh)
    local t1 = now_ms()
    local layout = pvm.one(ui.lower.phase(auth, theme, current_env_class()))
    local t2 = now_ms()
    driver:reset()
    local report = ui.runtime.run(driver, {
        pointer_x = state.ui_model.pointer_x,
        pointer_y = state.ui_model.pointer_y,
        scrolls = state.ui_model.scrolls,
    }, ui.render.root(layout, T.Solve.Env(vw, vh, {}), TEXT_SYSTEM))
    local t3 = now_ms()

    accum.auth_ms = accum.auth_ms + (t1 - t0)
    accum.lower_ms = accum.lower_ms + (t2 - t1)
    accum.runtime_ms = accum.runtime_ms + (t3 - t2)
    accum.rebuilds = accum.rebuilds + 1
    perf.rebuilds_total = perf.rebuilds_total + 1

    return report
end

local function compile_and_draw()
    local frame_t0 = now_ms()
    local vw, vh = love.graphics.getDimensions()
    local ui_model = state.ui_model
    local mx, my = love.mouse.getPosition()
    local accum = {
        auth_ms = 0,
        lower_ms = 0,
        runtime_ms = 0,
        rebuilds = 0,
    }

    if mx ~= ui_model.pointer_x or my ~= ui_model.pointer_y then
        apply_ui_model(ui.interact.apply(ui_model, T.Interact.SetPointer(mx, my)))
    end

    last_report = run_frame(vw, vh, accum)
    apply_ui_model(ui.interact.clamp_model(state.ui_model, last_report))

    local next_state = demo_apply.step(
        state,
        last_report,
        ui.interact.pointer_moved(state.ui_model.pointer_x, state.ui_model.pointer_y)
    )
    local hover_rerun = next_state ~= state
    if hover_rerun then
        state = next_state
        last_report = run_frame(vw, vh, accum)
    end

    love.graphics.origin()
    love.graphics.setScissor()

    perf.auth_ms = accum.auth_ms
    perf.lower_ms = accum.lower_ms
    perf.runtime_ms = accum.runtime_ms
    perf.compile_ms = accum.auth_ms + accum.lower_ms + accum.runtime_ms
    perf.frame_ms = now_ms() - frame_t0
    perf.rebuilds_frame = accum.rebuilds
    perf.hover_rerun = hover_rerun

    update_avg("auth_ms", perf.auth_ms)
    update_avg("lower_ms", perf.lower_ms)
    update_avg("runtime_ms", perf.runtime_ms)
    update_avg("compile_ms", perf.compile_ms)
    update_avg("frame_ms", perf.frame_ms)

    if perf.pending_action_at ~= nil and perf.rendered_action_serial ~= perf.pending_action_serial then
        perf.action_to_render_ms = now_ms() - perf.pending_action_at
        perf.last_action_label = perf.pending_action_label or "action"
        perf.rendered_action_serial = perf.pending_action_serial
    end
end

local function draw_hud()
    if not show_hud then return end
    local lines = {
        string.format("fps=%d  dt=%.2f ms  frame=%.2f ms (avg %.2f)", love.timer.getFPS(), perf.dt_ms, perf.frame_ms, perf.avg_frame_ms),
        string.format("compile=%.2f ms (avg %.2f)  auth=%.2f  lower=%.2f  runtime=%.2f", perf.compile_ms, perf.avg_compile_ms, perf.auth_ms, perf.lower_ms, perf.runtime_ms),
        string.format("rebuilds frame=%d  total=%d  hover-rerun=%s", perf.rebuilds_frame, perf.rebuilds_total, perf.hover_rerun and "yes" or "no"),
        string.format("last action=%s  action→render=%.2f ms  ui_events=%d  app_events=%d", perf.last_action_label, perf.action_to_render_ms, perf.ui_events, perf.app_events),
    }

    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setFont(hud_font)

    local x, y = 12, 12
    local line_h = hud_font:getHeight() + 2
    local w = 0
    for i = 1, #lines do
        local lw = hud_font:getWidth(lines[i])
        if lw > w then w = lw end
    end
    local h = #lines * line_h + 12

    love.graphics.setColor(0.02, 0.04, 0.08, 0.88)
    love.graphics.rectangle("fill", x - 8, y - 6, w + 16, h, 8, 8)
    love.graphics.setColor(0.20, 0.32, 0.52, 0.95)
    love.graphics.rectangle("line", x - 8, y - 6, w + 16, h, 8, 8)
    love.graphics.setColor(0.84, 0.90, 1.0, 1)
    for i = 1, #lines do
        love.graphics.print(lines[i], x, y + (i - 1) * line_h)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function love.load()
    love.graphics.setBackgroundColor(0.03, 0.05, 0.08, 1)
    theme = make_theme()
    install_fonts()
    state = demo_apply.initial_state()
end

function love.mousemoved(x, y)
    dispatch_raw(ui.interact.pointer_moved(x, y))
end

function love.mousepressed(x, y, button)
    dispatch_raw(ui.interact.pointer_pressed(ui.interact.button_from_love(button), x, y), "mouse-press")
end

function love.mousereleased(x, y, button)
    dispatch_raw(ui.interact.pointer_released(ui.interact.button_from_love(button), x, y), "mouse-release")
end

function love.wheelmoved(x, y)
    dispatch_raw(ui.interact.wheel_moved(x * 28, -y * 32, state.ui_model.pointer_x, state.ui_model.pointer_y), "wheel")
end

function love.keypressed(key)
    if key == "f1" then
        show_hud = not show_hud
    elseif key == "tab" then
        dispatch_raw(love.keyboard.isDown("lshift", "rshift") and ui.interact.focus_prev() or ui.interact.focus_next(), "tab-focus")
    elseif key == "return" or key == "space" then
        dispatch_raw(ui.interact.activate_focus(), "activate-focus")
    elseif key == "down" then
        mark_action("scroll-down")
        apply_ui_model(ui.interact.apply(state.ui_model, T.Interact.ScrollBy(BROWSER_SCROLL_ID, 0, 32), last_report))
    elseif key == "up" then
        mark_action("scroll-up")
        apply_ui_model(ui.interact.apply(state.ui_model, T.Interact.ScrollBy(BROWSER_SCROLL_ID, 0, -32), last_report))
    elseif key == "t" then
        mark_action("toggle-theme")
        state = demo_apply.apply(state, T.Studio.ToggleTheme)
    end
end

function love.update(dt)
    perf.dt_ms = dt * 1000
end

function love.draw()
    love.graphics.setBackgroundColor(state.app.theme_mode == T.Studio.ThemeLight and 0.94 or 0.03, state.app.theme_mode == T.Studio.ThemeLight and 0.96 or 0.05, state.app.theme_mode == T.Studio.ThemeLight and 0.98 or 0.08, 1)
    compile_and_draw()
    draw_hud()
end
