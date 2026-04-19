local ui = require("ui")
local pvm = require("pvm")
local demo_asdl = require("demo_asdl")
local demo_apply = require("demo_apply")
local widgets = require("widgets")

local T = ui.T
local b = ui.build
local text_field = ui.text_field
local input = ui.input
local sdl3 = ui.backends.sdl3

local MNotes = demo_asdl.T.MultiNotes

local M = {}

local DEFAULT_FONT = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"
local TEXT_KEY = "ui-multiwindow-demo"
local CARET_BLINK_MS = 530
local EDITOR_COMMIT_IDLE_MS = 120

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

local THEME = make_theme()
local ENV_CLASS = T.Env.Class(T.Env.Lg, T.Env.Dark, T.Env.MotionSafe, T.Env.D2x)
local app_state = demo_apply.initial_state()

local function selected_note()
    return demo_apply.selected_note(app_state)
end

local function apply_event(event)
    local next_state = demo_apply.apply(app_state, event)
    local changed = next_state ~= app_state
    app_state = next_state
    return changed
end

local function title_overlay_opts()
    return {
        id = b.id("editor:title"),
        placeholder = "Untitled",
        padding = 16,
        text_key = TEXT_KEY,
        wrap = false,
        text_style = function(field)
            return T.Layout.TextStyle(1, 24, 600, 0xf8fafcff, 0, 30, 0, text_field.text(field))
        end,
        composition_style = function(field)
            return T.Layout.TextStyle(1, 24, 600, 0x93c5fdff, 0, 30, 0, field.composition_text)
        end,
        placeholder_style = function(placeholder, base)
            return T.Layout.TextStyle(base.font_id, base.font_size, base.font_weight, 0x94a3b8ff, base.align, base.leading, base.tracking, placeholder)
        end,
        selection_rgba8 = 0x1d4ed8ff,
        caret_rgba8 = 0xf8fafcff,
        composition_underline_rgba8 = 0x93c5fdff,
    }
end

local function body_overlay_opts()
    return {
        id = b.id("editor:body"),
        placeholder = "Write here...",
        padding = 16,
        text_key = TEXT_KEY,
        text_style = function(field)
            return T.Layout.TextStyle(1, 18, 400, 0xe5e7ebff, 0, 26, 0, text_field.text(field))
        end,
        composition_style = function(field)
            return T.Layout.TextStyle(1, 18, 400, 0x93c5fdff, 0, 26, 0, field.composition_text)
        end,
        placeholder_style = function(placeholder, base)
            return T.Layout.TextStyle(base.font_id, base.font_size, base.font_weight, 0x94a3b8ff, base.align, base.leading, base.tracking, placeholder)
        end,
        selection_rgba8 = 0x1e40afff,
        caret_rgba8 = 0xf8fafcff,
        composition_underline_rgba8 = 0x93c5fdff,
    }
end

local function browser_scrollbar_opts(drag)
    return { drag = drag }
end

local function editor_title_scrollbar_opts(drag, focused)
    return {
        drag = drag,
        focused = focused,
    }
end

local function editor_body_scrollbar_opts(drag, focused)
    return {
        drag = drag,
        focused = focused,
    }
end

local function make_browser_state()
    return {
        kind = "browser",
        last_report = nil,
        ui_model = ui.interact.model {},
        browser_view = nil,
        browser_scrollbar = nil,
        browser_scrollbar_drag = nil,
        browser_scrollbar_visible = false,
    }
end

local function make_editor_state()
    local note = selected_note()
    return {
        kind = "editor",
        pointer_x = 0,
        pointer_y = 0,
        last_report = nil,
        bound_note_id = note and note.id or "",
        title_field = text_field.state(note and note.title or "", 0, 0, {}),
        body_field = text_field.state(note and note.body or "", 0, 0, {}),
        draft_dirty = false,
        draft_commit_at_ms = nil,
        editor_ui_model = ui.interact.model {},
        title_scrollbar = nil,
        title_scrollbar_drag = nil,
        body_scrollbar = nil,
        body_scrollbar_drag = nil,
        editor_view = nil,
        title_widget = nil,
        body_widget = nil,
    }
end

local function sync_editor_state(state)
    local note = selected_note()
    local note_id = note and note.id or ""
    local title = note and note.title or ""
    local body = note and note.body or ""

    if state.bound_note_id ~= note_id then
        state.bound_note_id = note_id
        state.title_field = text_field.state(title, 0, 0, {})
        state.body_field = text_field.state(body, 0, 0, {})
        state.draft_dirty = false
        state.draft_commit_at_ms = nil
        state.editor_ui_model = ui.interact.model {
            pointer_x = state.pointer_x,
            pointer_y = state.pointer_y,
        }
        state.title_scrollbar_drag = nil
        state.body_scrollbar_drag = nil
        return
    end

    if not state.title_field.focused and text_field.text(state.title_field) ~= title then
        state.title_field = text_field.state(title, 0, 0, {})
    end
    if not state.body_field.focused and text_field.text(state.body_field) ~= body then
        state.body_field = text_field.state(body, 0, 0, {})
    end
end

local function request_editor_commit_redraws(session, editor_window)
    session:request_redraw(editor_window)
    for i = 1, #session.order do
        local win = session.windows[session.order[i]]
        if win ~= nil and win ~= editor_window then
            session:request_redraw_after(win, 24)
        end
    end
end

local function editor_note_dirty(state)
    local note = selected_note()
    if note == nil then return false end
    return text_field.text(state.title_field) ~= note.title
        or text_field.text(state.body_field) ~= note.body
end

local function schedule_editor_commit(window, state, now_ms)
    state.draft_dirty = editor_note_dirty(state)
    if not state.draft_dirty then
        state.draft_commit_at_ms = nil
        return
    end
    state.draft_commit_at_ms = (now_ms or window.host:now_ms()) + EDITOR_COMMIT_IDLE_MS
end

local function commit_editor_fields(session, window, state)
    local note = selected_note()
    if note == nil then
        state.draft_dirty = false
        state.draft_commit_at_ms = nil
        return false
    end

    local changed = false
    local title = text_field.text(state.title_field)
    local body = text_field.text(state.body_field)

    if title ~= note.title then
        changed = apply_event(MNotes.UpdateSelectedTitle(title)) or changed
    end
    if body ~= note.body then
        changed = apply_event(MNotes.UpdateSelectedBody(body)) or changed
    end

    state.draft_dirty = false
    state.draft_commit_at_ms = nil

    if changed then
        request_editor_commit_redraws(session, window)
    end
    return changed
end

local function flush_editor_drafts(session, except_window)
    for i = 1, #session.order do
        local win = session.windows[session.order[i]]
        if win ~= nil and win ~= except_window and win.state ~= nil and win.state.kind == "editor" and win.state.draft_dirty then
            commit_editor_fields(session, win, win.state)
        end
    end
end

local function active_editor_part(state)
    if state.title_field.focused then return "title" end
    if state.body_field.focused then return "body" end
    return nil
end

local function blur_editor(host, state)
    local focused = state.title_field.focused or state.body_field.focused
    state.title_field = text_field.blur(state.title_field)
    state.body_field = text_field.blur(state.body_field)
    if focused then host:set_text_input(false) end
end

local function editor_text_changed(window, state)
    schedule_editor_commit(window, state)
    window:request_redraw()
end

local function draw_browser(window)
    local host = window.host
    local state = window.state
    local vw, vh = host:size()

    local function run_browser_pass(scrollbar_visible)
        state.browser_view = widgets.browser_root(app_state, {
            scrollbar_visible = scrollbar_visible,
        })
        local layout = pvm.one(ui.lower.phase(state.browser_view.node, THEME, ENV_CLASS))
        return ui.runtime.run(host.driver, {
            pointer_x = state.ui_model.pointer_x,
            pointer_y = state.ui_model.pointer_y,
            scrolls = state.ui_model.scrolls,
            collect_hits = true,
        }, ui.render.root(layout, T.Solve.Env(vw, vh, {}), TEXT_KEY, state.browser_view.content_store))
    end

    host.driver:reset()
    host:begin_frame(0x020617ff)
    state.last_report = run_browser_pass(state.browser_scrollbar_visible)

    if state.browser_view ~= nil and state.browser_view.scroll_view ~= nil then
        local visible, changed = state.browser_view.scroll_view:sync_visibility(state.last_report, state.browser_scrollbar_visible)
        if changed then
            state.browser_scrollbar_visible = visible
            host.driver:reset()
            host:begin_frame(0x020617ff)
            state.last_report = run_browser_pass(state.browser_scrollbar_visible)
        end
    else
        state.browser_scrollbar_visible = false
    end

    state.ui_model = ui.interact.clamp_model(state.ui_model, state.last_report)
    if state.browser_view ~= nil and state.browser_view.scroll_view ~= nil and state.browser_scrollbar_visible then
        state.browser_scrollbar = state.browser_view.scroll_view:draw(host, state.last_report, state.ui_model, browser_scrollbar_opts(state.browser_scrollbar_drag))
    else
        state.browser_scrollbar = nil
    end
    host:present()
end

local function schedule_editor_redraw(window)
    local host = window.host
    local state = window.state
    local title_composing = text_field.composition_active(state.title_field)
    local body_composing = text_field.composition_active(state.body_field)
    local composing = title_composing or body_composing
    local focused = state.title_field.focused or state.body_field.focused
    local now = host:now_ms()
    local next_at = composing and nil or state.draft_commit_at_ms

    if not composing and focused then
        local delay_ms = CARET_BLINK_MS - (now % CARET_BLINK_MS)
        if delay_ms <= 0 then delay_ms = CARET_BLINK_MS end
        local blink_at = now + delay_ms
        if next_at == nil or blink_at < next_at then
            next_at = blink_at
        end
    end

    if next_at == nil then
        window:cancel_redraw()
        return
    end
    window:request_redraw_at(next_at)
end

local function sync_editor_surface_scroll(host, state, surface_name, field, overlay_opts)
    if state.last_report == nil or state.editor_view == nil then return false end
    local surface = state.editor_view[surface_name]
    if surface == nil then return false end
    local next_model, changed = surface:sync_scroll(host, state.editor_ui_model, state.last_report, field, overlay_opts)
    if changed then
        state.editor_ui_model = next_model
        return true
    end
    return false
end

local function draw_editor(session, window)
    local host = window.host
    local state = window.state
    sync_editor_state(state)

    if state.draft_commit_at_ms ~= nil and host:now_ms() >= state.draft_commit_at_ms and not text_field.composition_active(state.title_field) and not text_field.composition_active(state.body_field) then
        commit_editor_fields(session, window, state)
    end

    local vw, vh = host:size()
    local title_opts = title_overlay_opts()
    local body_opts = body_overlay_opts()

    local function run_editor_pass()
        state.editor_view = widgets.editor_root(app_state, {
            title_text = text_field.text(state.title_field),
            body_text = text_field.text(state.body_field),
            dirty = state.draft_dirty,
        })
        local layout = pvm.one(ui.lower.phase(state.editor_view.node, THEME, ENV_CLASS))
        return ui.runtime.run(host.driver, {
            pointer_x = state.editor_ui_model.pointer_x,
            pointer_y = state.editor_ui_model.pointer_y,
            scrolls = state.editor_ui_model.scrolls,
            collect_hits = true,
        }, ui.render.root(layout, T.Solve.Env(vw, vh, {}), TEXT_KEY, state.editor_view.content_store))
    end

    local title_draw_opts = {
        wrap = title_opts.wrap,
        scroll_model = state.editor_ui_model,
        text_key = title_opts.text_key,
        text_style = title_opts.text_style,
        composition_style = title_opts.composition_style,
        placeholder_style = title_opts.placeholder_style,
        placeholder = title_opts.placeholder,
        padding = title_opts.padding,
        selection_rgba8 = title_opts.selection_rgba8,
        caret_rgba8 = title_opts.caret_rgba8,
        composition_underline_rgba8 = title_opts.composition_underline_rgba8,
    }
    local body_draw_opts = {
        scroll_model = state.editor_ui_model,
        text_key = body_opts.text_key,
        text_style = body_opts.text_style,
        composition_style = body_opts.composition_style,
        placeholder_style = body_opts.placeholder_style,
        placeholder = body_opts.placeholder,
        padding = body_opts.padding,
        selection_rgba8 = body_opts.selection_rgba8,
        caret_rgba8 = body_opts.caret_rgba8,
        composition_underline_rgba8 = body_opts.composition_underline_rgba8,
    }

    host.driver:reset()
    host:begin_frame(0x020617ff)
    state.last_report = run_editor_pass()

    state.editor_ui_model = ui.interact.clamp_model(state.editor_ui_model, state.last_report)

    title_draw_opts.scroll_model = state.editor_ui_model
    body_draw_opts.scroll_model = state.editor_ui_model
    state.title_widget = state.editor_view.title_surface:draw(host, state.last_report, state.title_field, title_draw_opts)
    state.editor_ui_model = state.editor_view.title_surface:clamp_scroll_model(state.editor_ui_model, state.title_widget)
    state.body_widget = state.editor_view.body_surface:draw(host, state.last_report, state.body_field, body_draw_opts)
    state.editor_ui_model = state.editor_view.body_surface:clamp_scroll_model(state.editor_ui_model, state.body_widget)

    state.title_scrollbar = state.editor_view.title_surface:draw_scrollbar(host, state.title_widget, editor_title_scrollbar_opts(state.title_scrollbar_drag, state.title_field.focused))
    state.body_scrollbar = state.editor_view.body_surface:draw_scrollbar(host, state.body_widget, editor_body_scrollbar_opts(state.body_scrollbar_drag, state.body_field.focused))

    host:present()
    schedule_editor_redraw(window)
end

local function handle_browser_ui_events(session, state, events)
    local changed = false
    if state.browser_view == nil then return end

    local app_events = state.browser_view:route_ui_events(events)
    if #app_events > 0 then
        flush_editor_drafts(session)
    end
    for i = 1, #app_events do
        changed = apply_event(app_events[i]) or changed
    end

    if changed then
        session:request_all_redraw()
    end
end

local function handle_browser_event(session, window, ev)
    local state = window.state

    if ev.type == "window_resized" then
        state.last_report = nil
        state.browser_view = nil
        state.browser_scrollbar = nil
        state.browser_scrollbar_drag = nil
        state.browser_scrollbar_visible = false
        session:request_all_redraw()
        return
    end

    if ev.type == "focus_lost" then
        if state.last_report ~= nil then
            local next_model, ui_events = ui.interact.step(state.ui_model, state.last_report, ui.interact.cancel_pointer())
            state.ui_model = next_model
            state.browser_scrollbar_drag = nil
            handle_browser_ui_events(session, state, ui_events)
            session:request_redraw(window)
        end
        return
    end

    if ev.type == "key_down" and (ev.key == input.KeyDelete or ev.key == input.KeyBackspace) then
        flush_editor_drafts(session)
        if apply_event(MNotes.DeleteSelected) then
            session:request_all_redraw()
        end
        return
    end

    if ev.type == "key_down" and state.last_report ~= nil and state.browser_view ~= nil and state.browser_view.scroll_view ~= nil then
        local next_model, handled = state.browser_view.scroll_view:key(state.ui_model, state.last_report, ev.key)
        if handled then
            state.ui_model = next_model
            session:request_redraw(window)
            return
        end
    end

    local raw = nil
    if ev.type == "mouse_moved" then
        if state.browser_scrollbar_drag ~= nil and state.browser_view ~= nil and state.browser_view.scroll_view ~= nil and state.last_report ~= nil then
            local next_model, handled, next_drag = state.browser_view.scroll_view:pointer_moved(
                state.ui_model,
                state.last_report,
                state.browser_scrollbar_drag,
                ev.x,
                ev.y
            )
            if handled then
                state.ui_model = next_model
                state.browser_scrollbar_drag = next_drag
                session:request_redraw(window)
                return
            end
        end
        raw = ui.interact.pointer_moved(ev.x, ev.y)
    elseif ev.type == "mouse_pressed" and ev.button == input.ButtonLeft then
        if state.browser_view ~= nil and state.browser_view.scroll_view ~= nil and state.last_report ~= nil then
            local next_model, handled, _, drag = state.browser_view.scroll_view:pointer_pressed(
                state.ui_model,
                state.last_report,
                ev.x,
                ev.y
            )
            if handled then
                state.ui_model = next_model
                state.browser_scrollbar_drag = drag
                session:request_redraw(window)
                return
            end
        end
        raw = ui.interact.pointer_pressed(T.Interact.BtnLeft, ev.x, ev.y)
    elseif ev.type == "mouse_released" and ev.button == input.ButtonLeft then
        if state.browser_scrollbar_drag ~= nil and state.browser_view ~= nil and state.browser_view.scroll_view ~= nil and state.last_report ~= nil then
            local next_model, handled = state.browser_view.scroll_view:pointer_released(
                state.ui_model,
                state.last_report,
                state.browser_scrollbar_drag,
                ev.x,
                ev.y
            )
            if handled then
                state.ui_model = next_model
                state.browser_scrollbar_drag = nil
                session:request_redraw(window)
                return
            end
            state.browser_scrollbar_drag = nil
        end
        raw = ui.interact.pointer_released(T.Interact.BtnLeft, ev.x, ev.y)
    elseif ev.type == "mouse_wheel" then
        raw = ui.interact.wheel_moved(ev.dx * 28, -ev.dy * 32, state.ui_model.pointer_x, state.ui_model.pointer_y)
    end

    if raw == nil then
        return
    end

    if state.last_report == nil then
        local cls = pvm.classof(raw)
        if cls == T.Interact.PointerMoved or cls == T.Interact.PointerPressed or cls == T.Interact.PointerReleased or cls == T.Interact.WheelMoved then
            state.ui_model = ui.interact.apply(state.ui_model, T.Interact.SetPointer(raw.x, raw.y))
        end
        session:request_redraw(window)
        return
    end

    local next_model, ui_events = ui.interact.step(state.ui_model, state.last_report, raw, { drag_threshold_px = 4 })
    state.ui_model = next_model
    handle_browser_ui_events(session, state, ui_events)
end

local function handle_editor_pointer_press(host, state, x, y, shift)
    local title_hit = state.editor_view ~= nil and state.editor_view.title_surface:contains(state.title_widget, x, y)
    local body_hit = state.editor_view ~= nil and state.editor_view.body_surface:contains(state.body_widget, x, y)

    if title_hit then
        local lx, ly = state.editor_view.title_surface:local_point(state.title_widget, x, y)
        state.body_field = text_field.blur(state.body_field)
        state.title_field = text_field.pointer_pressed(state.title_widget.resolved.layout, text_field.focus(state.title_field), lx, ly, shift)
        host:set_text_input(true)
        return true
    end

    if body_hit then
        local lx, ly = state.editor_view.body_surface:local_point(state.body_widget, x, y)
        state.title_field = text_field.blur(state.title_field)
        state.body_field = text_field.pointer_pressed(state.body_widget.resolved.layout, text_field.focus(state.body_field), lx, ly, shift)
        host:set_text_input(true)
        return true
    end

    blur_editor(host, state)
    return false
end

local function handle_editor_drag(state, x, y)
    if state.editor_view == nil then return end
    if state.title_field.dragging and state.title_widget ~= nil then
        local lx, ly = state.editor_view.title_surface:local_point(state.title_widget, x, y)
        state.title_field = text_field.pointer_moved(state.title_widget.resolved.layout, state.title_field, lx, ly)
    elseif state.body_field.dragging and state.body_widget ~= nil then
        local lx, ly = state.editor_view.body_surface:local_point(state.body_widget, x, y)
        state.body_field = text_field.pointer_moved(state.body_widget.resolved.layout, state.body_field, lx, ly)
    end
end

local function handle_editor_key(host, state, ev)
    local part = active_editor_part(state)
    if part == nil then return false end

    if part == "title" and ev.key == input.KeyReturn then
        state.title_field = text_field.blur(state.title_field)
        state.body_field = text_field.focus(state.body_field)
        host:set_text_input(true)
        return true
    end

    if ev.ctrl and (ev.key == input.KeyHome or ev.key == input.KeyEnd) then
        if part == "title" and state.editor_view ~= nil and state.editor_view.title_surface ~= nil then
            local next_model, handled = state.editor_view.title_surface:scroll_key(state.editor_ui_model, state.title_widget, ev.key)
            if handled then
                state.editor_ui_model = next_model
                return true
            end
        elseif part == "body" and state.editor_view ~= nil and state.editor_view.body_surface ~= nil then
            local next_model, handled = state.editor_view.body_surface:scroll_key(state.editor_ui_model, state.body_widget, ev.key)
            if handled then
                state.editor_ui_model = next_model
                return true
            end
        end
    end

    local field = part == "title" and state.title_field or state.body_field
    local widget = part == "title" and state.title_widget or state.body_widget
    if widget == nil or widget.resolved == nil then return false end

    field = text_field.key(widget.resolved.layout, field, ev.key, ev.shift, ev.ctrl, {
        repeat_ = ev.repeat_,
        get_clipboard_text = function()
            if host:has_clipboard_text() then
                return host:get_clipboard_text()
            end
            return nil
        end,
        set_clipboard_text = function(text)
            host:set_clipboard_text(text)
        end,
    })

    if part == "title" then
        state.title_field = field
        if not field.focused then host:set_text_input(false) end
    else
        state.body_field = field
        if not field.focused then host:set_text_input(false) end
    end
    return true
end

local function handle_editor_event(session, window, ev)
    local host = window.host
    local state = window.state
    sync_editor_state(state)

    if ev.x ~= nil then state.pointer_x = ev.x end
    if ev.y ~= nil then state.pointer_y = ev.y end

    if ev.type == "window_resized" then
        state.last_report = nil
        state.editor_view = nil
        state.title_widget = nil
        state.body_widget = nil
        state.title_scrollbar = nil
        state.title_scrollbar_drag = nil
        state.body_scrollbar = nil
        state.body_scrollbar_drag = nil
        session:request_all_redraw()
        return
    end

    if ev.type == "focus_lost" then
        state.title_scrollbar_drag = nil
        state.body_scrollbar_drag = nil
        blur_editor(host, state)
        if state.draft_dirty then
            commit_editor_fields(session, window, state)
        end
        return
    end

    state.editor_ui_model = ui.interact.apply(state.editor_ui_model, T.Interact.SetPointer(state.pointer_x, state.pointer_y))

    if ev.type == "mouse_pressed" and ev.button == input.ButtonLeft then
        if state.editor_view ~= nil and state.last_report ~= nil then
            if state.editor_view.title_surface ~= nil then
                local next_model, handled, drag = state.editor_view.title_surface:scroll_pointer_pressed(
                    state.editor_ui_model,
                    state.title_widget,
                    ev.x,
                    ev.y,
                    editor_title_scrollbar_opts(state.title_scrollbar_drag, state.title_field.focused)
                )
                if handled then
                    state.editor_ui_model = next_model
                    state.title_scrollbar_drag = drag
                    session:request_redraw(window)
                    return
                end
            end
            if state.editor_view.body_surface ~= nil then
                local next_model, handled, drag = state.editor_view.body_surface:scroll_pointer_pressed(
                    state.editor_ui_model,
                    state.body_widget,
                    ev.x,
                    ev.y,
                    editor_body_scrollbar_opts(state.body_scrollbar_drag, state.body_field.focused)
                )
                if handled then
                    state.editor_ui_model = next_model
                    state.body_scrollbar_drag = drag
                    session:request_redraw(window)
                    return
                end
            end
        end
        local focused_editor = handle_editor_pointer_press(host, state, ev.x, ev.y, ev.shift)
        sync_editor_surface_scroll(host, state, "title_surface", state.title_field, title_overlay_opts())
        sync_editor_surface_scroll(host, state, "body_surface", state.body_field, body_overlay_opts())
        if not focused_editor and state.draft_dirty then
            commit_editor_fields(session, window, state)
        end
        return
    end

    if ev.type == "mouse_moved" then
        if state.title_scrollbar_drag ~= nil and state.editor_view ~= nil and state.editor_view.title_surface ~= nil then
            local next_model, handled, next_drag = state.editor_view.title_surface:scroll_pointer_moved(
                state.editor_ui_model,
                state.title_scrollbar_drag,
                ev.x,
                ev.y
            )
            if handled then
                state.editor_ui_model = next_model
                state.title_scrollbar_drag = next_drag
                session:request_redraw(window)
                return
            end
        end
        if state.body_scrollbar_drag ~= nil and state.editor_view ~= nil and state.editor_view.body_surface ~= nil then
            local next_model, handled, next_drag = state.editor_view.body_surface:scroll_pointer_moved(
                state.editor_ui_model,
                state.body_scrollbar_drag,
                ev.x,
                ev.y
            )
            if handled then
                state.editor_ui_model = next_model
                state.body_scrollbar_drag = next_drag
                session:request_redraw(window)
                return
            end
        end
        handle_editor_drag(state, ev.x, ev.y)
        sync_editor_surface_scroll(host, state, "title_surface", state.title_field, title_overlay_opts())
        sync_editor_surface_scroll(host, state, "body_surface", state.body_field, body_overlay_opts())
        return
    end

    if ev.type == "mouse_released" and ev.button == input.ButtonLeft then
        if state.title_scrollbar_drag ~= nil and state.editor_view ~= nil and state.editor_view.title_surface ~= nil then
            local next_model, handled = state.editor_view.title_surface:scroll_pointer_released(
                state.editor_ui_model,
                state.title_scrollbar_drag
            )
            if handled then
                state.editor_ui_model = next_model
                state.title_scrollbar_drag = nil
                session:request_redraw(window)
                return
            end
            state.title_scrollbar_drag = nil
        end
        if state.body_scrollbar_drag ~= nil and state.editor_view ~= nil and state.editor_view.body_surface ~= nil then
            local next_model, handled = state.editor_view.body_surface:scroll_pointer_released(
                state.editor_ui_model,
                state.body_scrollbar_drag
            )
            if handled then
                state.editor_ui_model = next_model
                state.body_scrollbar_drag = nil
                session:request_redraw(window)
                return
            end
            state.body_scrollbar_drag = nil
        end
        state.title_field = text_field.pointer_released(state.title_field)
        state.body_field = text_field.pointer_released(state.body_field)
        return
    end

    if ev.type == "text_input" then
        if state.title_field.focused then
            state.title_field = text_field.text_input(state.title_field, ev.text)
            sync_editor_surface_scroll(host, state, "title_surface", state.title_field, title_overlay_opts())
            editor_text_changed(window, state)
        elseif state.body_field.focused then
            state.body_field = text_field.text_input(state.body_field, ev.text)
            sync_editor_surface_scroll(host, state, "body_surface", state.body_field, body_overlay_opts())
            editor_text_changed(window, state)
        end
        return
    end

    if ev.type == "text_editing" then
        if state.title_field.focused then
            state.title_field = text_field.text_editing(state.title_field, ev.text, ev.start, ev.length)
            sync_editor_surface_scroll(host, state, "title_surface", state.title_field, title_overlay_opts())
        elseif state.body_field.focused then
            state.body_field = text_field.text_editing(state.body_field, ev.text, ev.start, ev.length)
            sync_editor_surface_scroll(host, state, "body_surface", state.body_field, body_overlay_opts())
        end
        return
    end

    if ev.type == "mouse_wheel" and state.last_report ~= nil and state.editor_view ~= nil then
        if state.editor_view.title_surface ~= nil then
            local next_model, handled = state.editor_view.title_surface:scroll_wheel(
                state.editor_ui_model,
                state.title_widget,
                ev.dx * 28,
                -ev.dy * 32,
                state.editor_ui_model.pointer_x,
                state.editor_ui_model.pointer_y
            )
            if handled then
                state.editor_ui_model = next_model
                session:request_redraw(window)
                return
            end
        end
        if state.editor_view.body_surface ~= nil then
            local next_model, handled = state.editor_view.body_surface:scroll_wheel(
                state.editor_ui_model,
                state.body_widget,
                ev.dx * 28,
                -ev.dy * 32,
                state.editor_ui_model.pointer_x,
                state.editor_ui_model.pointer_y
            )
            if handled then
                state.editor_ui_model = next_model
                session:request_redraw(window)
                return
            end
        end
    end

    if ev.type == "key_down" then
        if state.title_field.focused and ev.ctrl and state.editor_view ~= nil and state.editor_view.title_surface ~= nil then
            local key = nil
            if ev.key == input.KeyHome or ev.key == input.KeyEnd then key = ev.key end
            if key ~= nil then
                local next_model, handled = state.editor_view.title_surface:scroll_key(state.editor_ui_model, state.title_widget, key)
                if handled then
                    state.editor_ui_model = next_model
                    session:request_redraw(window)
                    return
                end
            end
        end
        if state.body_field.focused and state.editor_view ~= nil and state.editor_view.body_surface ~= nil then
            local key = nil
            if ev.key == input.KeyPageUp or ev.key == input.KeyPageDown then key = ev.key end
            if ev.ctrl and (ev.key == input.KeyHome or ev.key == input.KeyEnd) then key = ev.key end
            if key ~= nil then
                local next_model, handled = state.editor_view.body_surface:scroll_key(state.editor_ui_model, state.body_widget, key)
                if handled then
                    state.editor_ui_model = next_model
                    session:request_redraw(window)
                    return
                end
            end
        end
        local before_title = text_field.text(state.title_field)
        local before_body = text_field.text(state.body_field)
        if handle_editor_key(host, state, ev) then
            if state.title_field.focused then
                sync_editor_surface_scroll(host, state, "title_surface", state.title_field, title_overlay_opts())
            end
            if state.body_field.focused then
                sync_editor_surface_scroll(host, state, "body_surface", state.body_field, body_overlay_opts())
            end
            local after_title = text_field.text(state.title_field)
            local after_body = text_field.text(state.body_field)
            if after_title ~= before_title or after_body ~= before_body then
                editor_text_changed(window, state)
            elseif not state.title_field.focused and not state.body_field.focused and state.draft_dirty then
                commit_editor_fields(session, window, state)
            else
                session:request_redraw(window)
            end
        end
    end
end

local function on_draw(session, window)
    if window.state.kind == "browser" then
        draw_browser(window)
    else
        draw_editor(session, window)
    end
end

local function on_event(session, window, ev)
    if window.state.kind == "browser" then
        handle_browser_event(session, window, ev)
    else
        handle_editor_event(session, window, ev)
    end
end

function M.new_session(opts)
    opts = opts or {}
    return ui.session.new {
        backend = sdl3,
        redraw_mode = opts.redraw_mode or "dirty",
        text_key = opts.text_key or TEXT_KEY,
        default_font = opts.default_font or DEFAULT_FONT,
        window_event = on_event,
        window_draw = on_draw,
    }
end

function M.install_default_windows(session)
    session:create_window {
        title = "gps.lua notes / browser",
        width = 1280,
        height = 820,
        window_flags = sdl3.ffi.SDL_WINDOW_RESIZABLE,
        state = make_browser_state(),
    }

    session:create_window {
        title = "gps.lua notes / editor",
        width = 1280,
        height = 820,
        window_flags = sdl3.ffi.SDL_WINDOW_RESIZABLE,
        state = make_editor_state(),
    }

    session:request_all_redraw()
end

function M.run(opts)
    local session = M.new_session(opts)
    M.install_default_windows(session)
    session:run(opts)
end

return M
