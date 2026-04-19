package.path = "./?.lua;./?/init.lua;" .. package.path

local ui = require("ui")

local FONT = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"
local KEY = "text-field-sdl3-demo"

local T = ui.T
local text_field = ui.text_field
local text_field_view = ui.text_field_view
local input = ui.input
local sdl3 = ui.backends.sdl3

local function style_for(text, fg)
    return T.Layout.TextStyle(1, 20, 400, fg or 0xe5e7ebff, 0, 26, 0, text)
end

local function composition_style_for(text)
    return T.Layout.TextStyle(1, 20, 400, 0x93c5fdff, 0, 26, 0, text)
end

local function header_layouts(host)
    local vw, vh = host:size()
    local title = ui.text.layout(style_for("SDL3 text field demo", 0xbfdbfeff), T.Layout.Constraint(vw - 64, math.huge), KEY)
    local hint = ui.text.layout(
        style_for("Click in the field. Type, Shift+Arrows, Ctrl+A/C/X/V, Home/End, Backspace/Delete, Enter for newline, Esc to blur.", 0x94a3b8ff),
        T.Layout.Constraint(vw - 64, math.huge),
        KEY
    )
    return vw, vh, title, hint
end

local function view_opts(host)
    local vw, vh, title, hint = header_layouts(host)
    local top_y = 18 + title.measured_h + 8 + hint.measured_h + 16
    local bottom_pad = 56
    return {
        x = 32,
        y = top_y,
        w = vw - 64,
        h = math.max(80, vh - top_y - bottom_pad),
        padding = 14,
        text_key = KEY,
        text_style = function(field)
            return style_for(text_field.text(field))
        end,
        composition_style = function(field)
            return composition_style_for(field.composition_text)
        end,
        bg_rgba8 = 0x0f172aff,
        border_rgba8 = 0x334155ff,
        focus_border_rgba8 = 0x3b82f6ff,
        selection_rgba8 = 0x1e40afff,
        caret_rgba8 = 0xf8fafcff,
        composition_underline_rgba8 = 0x93c5fdff,
        header_title = title,
        header_hint = hint,
    }
end

local function draw_text_layout(host, layout, x, y, wrap_w)
    host.driver:draw_text(x, y, wrap_w or layout.measured_w, layout.measured_h, {
        style = layout.style,
        lines = layout.lines,
    })
end

local function draw_simple_text(host, text, x, y, wrap_w, rgba8)
    local layout = ui.text.layout(style_for(text, rgba8), T.Layout.Constraint(wrap_w or math.huge, math.huge), KEY)
    draw_text_layout(host, layout, x, y, wrap_w)
end

local function main()
    local host = sdl3.new_host {
        title = "gps.lua SDL3 text field demo",
        width = 920,
        height = 640,
        vsync = true,
        default_font = FONT,
    }
    ui.text.register(KEY, host.text_system)

    local field = text_field.state("Click here, type, select, copy/paste, and use arrows.\nThis demo is using ui.text_field + ui.text_field_view.", 0, 0, {
        focused = true,
    })
    local running = true
    local auto_quit_ms = tonumber(os.getenv("AUTO_QUIT_MS") or "")
    local start_ticks = host:now_ms()

    host:set_text_input(true)

    while running do
        local opts = view_opts(host)
        local resolved = text_field_view.resolve(host, field, opts)

        for _, ev in ipairs(host:poll_events()) do
            if ev.type == "quit" or ev.type == "window_close_requested" then
                running = false

            elseif ev.type == "mouse_pressed" and ev.button == input.ButtonLeft then
                local was_focused = field.focused
                if text_field_view.contains(resolved, ev.x, ev.y) then
                    local lx, ly = text_field_view.local_point(resolved, ev.x, ev.y)
                    field = text_field.pointer_pressed(resolved.layout, field, lx, ly, ev.shift)
                    if not was_focused and field.focused then
                        host:set_text_input(true)
                    end
                else
                    field = text_field.pointer_pressed_outside(field)
                    if was_focused and not field.focused then
                        host:set_text_input(false)
                    end
                end

            elseif ev.type == "mouse_released" and ev.button == input.ButtonLeft then
                field = text_field.pointer_released(field)

            elseif ev.type == "mouse_moved" then
                local lx, ly = text_field_view.local_point(resolved, ev.x, ev.y)
                field = text_field.pointer_moved(resolved.layout, field, lx, ly)

            elseif ev.type == "text_input" then
                field = text_field.text_input(field, ev.text)

            elseif ev.type == "text_editing" then
                field = text_field.text_editing(field, ev.text, ev.start, ev.length)

            elseif ev.type == "key_down" then
                local was_focused = field.focused
                field = text_field.key(resolved.layout, field, ev.key, ev.shift, ev.ctrl, {
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
                if was_focused and not field.focused then
                    host:set_text_input(false)
                end
            end
        end

        opts = view_opts(host)
        resolved = text_field_view.resolve(host, field, opts)

        host:begin_frame(0x020617ff)
        text_field_view.draw(host, field, resolved, opts)

        local status = string.format(
            "focus=%s  anchor=%d active=%d  composition=%q start=%d len=%d  selected=%q",
            field.focused and "yes" or "no",
            field.edit.anchor,
            field.edit.active,
            field.composition_text,
            field.composition_start,
            field.composition_length,
            text_field.selected_text(field)
        )

        draw_text_layout(host, opts.header_title, 32, 18, resolved.vw - 64)
        draw_text_layout(host, opts.header_hint, 32, 18 + opts.header_title.measured_h + 8, resolved.vw - 64)
        draw_simple_text(host, status, 32, resolved.vh - 34, resolved.vw - 64, 0x60a5faff)

        host:present()

        if auto_quit_ms ~= nil and host:now_ms() - start_ticks >= auto_quit_ms then
            running = false
        end

        host:delay(8)
    end

    ui.text.unregister(KEY)
    host:close()
end

main()
