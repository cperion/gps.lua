-- examples/ui7/main.lua — full app with explicit source / view / paint / runtime split
-- Canonical launcher: examples/ui7/main.t (SDL3 + OpenGL + SDL_ttf via Terra)
--
-- Architecture:
--   App.State + App.Viewport
--     ↓ project_view
--   AppView.Node                 -- shared projected spine
--     ↓ static_fragment / static_commands
--   UI fragments / View.Cmd[]    -- static compiled image
--
--   App.State + App.Viewport
--     ↓ project_root_overlay
--   ui.Paint.Node                -- generic custom-drawing tree
--     ↓ ui.compile_paint
--   Paint.Cmd[]                  -- flat generic runtime paint commands
--
--   AppRuntime.Payload           -- live app runtime state (changes every frame)
--     ↓ build_overlay_runtime
--   { numbers, texts, colors }   -- generic paint runtime environment
--
--   Draw:
--     ui.paint(static_cmds)
--     ui.paint_custom(overlay_commands, overlay_runtime)
--
-- Time stepping updates AppRuntime.Payload only.
-- Slider edits update App.State and trigger recompilation.

local THIS_SOURCE = debug.getinfo(1, "S").source
local THIS_DIR = THIS_SOURCE:sub(1, 1) == "@" and THIS_SOURCE:match("^@(.+)/[^/]+$") or "."
local ROOT_DIR = THIS_DIR .. "/../.."
package.path = table.concat({
    ROOT_DIR .. "/?.lua", ROOT_DIR .. "/?/init.lua", package.path
}, ";")

local pvm2 = require("pvm2")
local ui   = require("uilib")

local T = ui.T
local ds = ui.ds

-- ══════════════════════════════════════════════════════════════
--  COLOURS
-- ══════════════════════════════════════════════════════════════

local function hex(argb)
    local a = math.floor(argb / 0x1000000) % 256
    local r = math.floor(argb / 0x10000) % 256
    local g = math.floor(argb / 0x100) % 256
    local b = argb % 256
    return r * 0x1000000 + g * 0x10000 + b * 0x100 + a
end

local C = {
    bg=hex(0xff0e1117), panel=hex(0xff161b22), panel_hi=hex(0xff1c2330),
    border=hex(0xff30363d), text=hex(0xffe6edf3), text_dim=hex(0xff8b949e),
    text_bright=hex(0xffffffff), accent=hex(0xff58a6ff), accent_dim=hex(0xff1f6feb),
    green=hex(0xff3fb950), red=hex(0xfff85149), orange=hex(0xffd29922),
    purple=hex(0xffbc8cff), cyan=hex(0xff79c0ff),
    mute_on=hex(0xffda3633), solo_on=hex(0xff58a6ff),
    meter_bg=hex(0xff21262d), meter_fill=hex(0xff3fb950),
    meter_hot=hex(0xffd29922), meter_clip=hex(0xfff85149),
    knob_bg=hex(0xff30363d), knob_fg=hex(0xff58a6ff),
    transport_bg=hex(0xff0d1117), scrollbar=hex(0xff30363d), scrollthumb=hex(0xff484f58),
    row_even=hex(0xff0d1117), row_odd=hex(0xff161b22),
    row_active=hex(0xff1f2937),
}

-- ══════════════════════════════════════════════════════════════
--  ASDL
-- ══════════════════════════════════════════════════════════════

T:Define [[
    module App {
        Track = (number id,
                 string name,
                 number color,
                 number vol,
                 number pan,
                 boolean mute,
                 boolean solo) unique

        Clip = (number id,
                number track_id,
                number beat_q16,
                number dur_q16,
                string label,
                number color) unique

        Project = (App.Track* tracks,
                   App.Clip* clips,
                   number bpm) unique

        Selection = NoSelection
                  | SelectedTrack(number track_id) unique
                  | SelectedClip(number clip_id) unique

        Session = (App.Selection selection,
                   number scroll_y,
                   boolean playing) unique

        State = (App.Project project,
                 App.Session session) unique

        Viewport = (number window_width,
                    number window_height) unique
    }

    module AppView {
        Node = RootView(AppView.Node track_panel,
                        AppView.Node arrangement_panel,
                        AppView.Node inspector_panel,
                        AppView.Node transport_panel) unique

             | TrackPanelView(number track_count,
                              AppView.Node* track_row_views,
                              number scroll_y,
                              number visible_height) unique

             | TrackRowView(number track_id,
                            number track_index,
                            App.Track track,
                            boolean is_selected) unique

             | ArrangementPanelView(number track_count,
                                    number visible_width,
                                    number visible_height,
                                    number scroll_y,
                                    AppView.Node* clip_views,
                                    number playhead_height) unique

             | ClipView(number clip_id,
                        App.Clip clip,
                        number track_index,
                        boolean is_selected,
                        number scroll_y) unique

             | TrackInspectorView(number track_id,
                                  App.Track track,
                                  number track_index,
                                  number panel_height) unique

             | ClipInspectorView(number clip_id,
                                 App.Clip clip,
                                 App.Track track,
                                 number panel_height) unique

             | TransportPanelView(number bpm,
                                  boolean is_playing,
                                  number panel_width) unique
    }

    module AppRuntime {
        MeterLevelValue = (number track_id,
                           number level) unique

        Payload = (number playhead_x,
                   string transport_time_text,
                   string transport_beat_text,
                   AppRuntime.MeterLevelValue* meter_levels) unique
    }
]]

local Track = T.App.Track
local Clip = T.App.Clip
local Project = T.App.Project
local NoSelection = T.App.NoSelection
local SelectedTrack = T.App.SelectedTrack
local SelectedClip = T.App.SelectedClip
local Session = T.App.Session
local State = T.App.State
local Viewport = T.App.Viewport

local RootView = T.AppView.RootView
local TrackPanelView = T.AppView.TrackPanelView
local TrackRowView = T.AppView.TrackRowView
local ArrangementPanelView = T.AppView.ArrangementPanelView
local ClipView = T.AppView.ClipView
local TrackInspectorView = T.AppView.TrackInspectorView
local ClipInspectorView = T.AppView.ClipInspectorView
local TransportPanelView = T.AppView.TransportPanelView

local MeterLevelValue = T.AppRuntime.MeterLevelValue
local RuntimePayload = T.AppRuntime.Payload

local mtSelectedTrack = getmetatable(SelectedTrack(0))
local mtSelectedClip = getmetatable(SelectedClip(0))

-- ══════════════════════════════════════════════════════════════
--  UILIB SHORTHAND
-- ══════════════════════════════════════════════════════════════

local box, px, insets, text_style = ui.box, ui.px, ui.insets, ui.text_style
local stack, pad, clip, transform, sized, text, spacer =
    ui.stack, ui.pad, ui.clip, ui.transform, ui.sized, ui.text, ui.spacer

local function as_pack(color)
    if type(color) == "number" then return ui.solid(color) end
    return color
end

local function rect(tag, color, b)
    return ui.rect(tag, as_pack(color), b)
end

local FONT_PIXELS = {
    [1] = 18,
    [2] = 13,
    [3] = 15,
    [4] = 10,
}

local function style(font_id, color, opts)
    opts = opts or {}
    return text_style {
        font_id = font_id,
        color = as_pack(color),
        wrap = opts.wrap or ui.TEXT_NOWRAP,
        align = opts.align or ui.TEXT_START,
        overflow = opts.overflow or ui.OVERFLOW_VISIBLE,
        line_height = opts.line_height or ui.LINEHEIGHT_AUTO,
        line_limit = opts.line_limit or ui.UNLIMITED_LINES,
    }
end

-- ══════════════════════════════════════════════════════════════
--  CONSTANTS
-- ══════════════════════════════════════════════════════════════

local ROW_HEIGHT = 48
local HEADER_HEIGHT = 40
local TRACK_PANEL_WIDTH = 260
local TRANSPORT_HEIGHT = 52
local INSPECTOR_WIDTH = 280
local PIXELS_PER_BEAT = 60
local METER_WIDTH = 8
local Q16 = 65536

local TRACK_ROW_PAD_X = 14
local TRACK_ROW_RIGHT_PAD = 16
local TRACK_ROW_BUTTON_W = 24
local TRACK_ROW_BUTTON_H = 20
local TRACK_ROW_BUTTON_GAP = 6
local TRACK_ROW_SLIDER_W = 44
local TRACK_ROW_SLIDER_GAP = 10

local TRANSPORT_PAD_X = 16
local TRANSPORT_MAIN_BUTTON_W = 48
local TRANSPORT_SMALL_BUTTON_W = 22

-- ══════════════════════════════════════════════════════════════
--  DESIGN SYSTEM SURFACES
-- ══════════════════════════════════════════════════════════════

local UI_THEME = ds.theme("ui7", {
    surfaces = {
        ds.surface("track_row_even", {
            ds.paint_rule(ds.sel(), { ds.bg(ds.clit(C.row_even)), ds.fg(ds.clit(C.text)) }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, { ds.bg(ds.clit(C.panel_hi)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, { ds.bg(ds.clit(C.panel)), ds.fg(ds.clit(C.text_bright)) }),
        }),
        ds.surface("track_row_odd", {
            ds.paint_rule(ds.sel(), { ds.bg(ds.clit(C.row_odd)), ds.fg(ds.clit(C.text)) }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, { ds.bg(ds.clit(C.panel_hi)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, { ds.bg(ds.clit(C.panel)), ds.fg(ds.clit(C.text_bright)) }),
        }),
        ds.surface("track_row_selected", {
            ds.paint_rule(ds.sel(), { ds.bg(ds.clit(C.row_active)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, { ds.bg(ds.clit(C.panel_hi)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, { ds.bg(ds.clit(C.accent_dim)), ds.fg(ds.clit(C.text_bright)) }),
        }),
        ds.surface("button", {
            ds.paint_rule(ds.sel(), { ds.bg(ds.clit(C.panel)), ds.fg(ds.clit(C.text)) }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, { ds.bg(ds.clit(C.panel_hi)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, { ds.bg(ds.clit(C.transport_bg)), ds.fg(ds.clit(C.text_bright)) }),
        }),
        ds.surface("mute_button", {
            ds.paint_rule(ds.sel(), { ds.bg(ds.clit(C.panel)), ds.fg(ds.clit(C.text_dim)) }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, { ds.bg(ds.clit(C.panel_hi)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, { ds.bg(ds.clit(C.transport_bg)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { flags = { "active" } }, { ds.bg(ds.clit(C.mute_on)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "hovered", flags = { "active" } }, { ds.bg(ds.clit(C.red)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "pressed", flags = { "active" } }, { ds.bg(ds.clit(C.transport_bg)), ds.fg(ds.clit(C.text_bright)) }),
        }),
        ds.surface("solo_button", {
            ds.paint_rule(ds.sel(), { ds.bg(ds.clit(C.panel)), ds.fg(ds.clit(C.text_dim)) }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, { ds.bg(ds.clit(C.panel_hi)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, { ds.bg(ds.clit(C.transport_bg)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { flags = { "active" } }, { ds.bg(ds.clit(C.solo_on)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "hovered", flags = { "active" } }, { ds.bg(ds.clit(C.accent)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "pressed", flags = { "active" } }, { ds.bg(ds.clit(C.transport_bg)), ds.fg(ds.clit(C.text_bright)) }),
        }),
        ds.surface("transport_play", {
            ds.paint_rule(ds.sel(), { ds.bg(ds.clit(C.panel)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, { ds.bg(ds.clit(C.panel_hi)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, { ds.bg(ds.clit(C.transport_bg)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { flags = { "active" } }, { ds.bg(ds.clit(C.accent_dim)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "hovered", flags = { "active" } }, { ds.bg(ds.clit(C.accent)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "pressed", flags = { "active" } }, { ds.bg(ds.clit(C.transport_bg)), ds.fg(ds.clit(C.text_bright)) }),
        }),
        ds.surface("transport_button", {
            ds.paint_rule(ds.sel(), { ds.bg(ds.clit(C.panel)), ds.fg(ds.clit(C.text)) }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, { ds.bg(ds.clit(C.panel_hi)), ds.fg(ds.clit(C.text_bright)) }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, { ds.bg(ds.clit(C.transport_bg)), ds.fg(ds.clit(C.text_bright)) }),
        }),
    },
})

local function surface_style(name, flags)
    return ds.resolve(ds.query(UI_THEME, name, ds.BLURRED, flags or {}))
end

local function active_flags(on)
    if on then return { ds.ACTIVE } end
    return {}
end

-- ══════════════════════════════════════════════════════════════
--  HELPERS
-- ══════════════════════════════════════════════════════════════

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function q16(n) return math.floor(n * Q16 + 0.5) end
local function from_q16(n) return n / Q16 end

local function track_row_layout(panel_width)
    local slider_w = clamp(math.floor(panel_width * 0.17), 40, 52)
    local meter_x = panel_width - TRACK_ROW_RIGHT_PAD - METER_WIDTH
    local slider_x = meter_x - TRACK_ROW_SLIDER_GAP - slider_w
    local solo_x = slider_x - TRACK_ROW_BUTTON_GAP - TRACK_ROW_BUTTON_W
    local mute_x = solo_x - TRACK_ROW_BUTTON_GAP - TRACK_ROW_BUTTON_W
    local name_x = TRACK_ROW_PAD_X
    local name_w = math.max(48, mute_x - name_x - 10)
    return {
        name_x = name_x,
        name_w = name_w,
        mute_x = mute_x,
        solo_x = solo_x,
        slider_x = slider_x,
        slider_w = slider_w,
        meter_x = meter_x,
    }
end

local function transport_layout(panel_width)
    local play_x = TRANSPORT_PAD_X
    local stop_x = play_x + TRANSPORT_MAIN_BUTTON_W + 32
    local controls_end = stop_x + TRANSPORT_MAIN_BUTTON_W
    local content_x = controls_end + 34
    local right_pad = TRANSPORT_PAD_X
    local min_content_w = 220
    local preferred_status_w = clamp(math.floor(panel_width * 0.16), 0, 140)
    local status_w = math.max(0, math.min(preferred_status_w, panel_width - content_x - right_pad - 24 - min_content_w))
    local status_x = panel_width - right_pad - status_w
    local content_w = math.max(0, status_x - 24 - content_x)
    local gap = math.min(24, math.max(0, math.floor(content_w * 0.05)))
    local preferred_bpm_w = math.max(72, math.floor(content_w * 0.26))
    local bpm_w = math.max(0, math.min(92, preferred_bpm_w, math.max(0, content_w - gap * 2)))
    local info_w = math.max(0, content_w - bpm_w - gap * 2)
    local time_w = math.floor(info_w * 0.62)
    local beat_w = math.max(0, info_w - time_w)
    local time_x = content_x
    local beat_x = time_x + time_w + gap
    local bpm_x = beat_x + beat_w + gap
    return {
        play_x = play_x,
        stop_x = stop_x,
        controls_end = controls_end,
        time_x = time_x,
        time_w = time_w,
        beat_x = beat_x,
        beat_w = beat_w,
        bpm_x = bpm_x,
        bpm_w = bpm_w,
        status_x = status_x,
        status_w = status_w,
    }
end

local source_state
local runtime_payload
local pointer_hot = { hovered = nil, pressed = nil, dragging = nil }
local dragging = nil
local window_width, window_height = 1100, 700
local static_commands = {}
local overlay_commands = {}
local undo_stack = {}
local fonts = {}

local app = {}
local app_host = {}

local function host_renderer()
    return assert(app_host.renderer, "ui7: renderer not installed")
end

local function host_new_font(size)
    if app_host.new_font then return app_host.new_font(size) end
    local renderer = app_host.renderer
    if renderer and renderer.new_font then return renderer:new_font(size) end
    error("ui7: host renderer does not provide new_font(size)", 2)
end

local function host_dimensions()
    if app_host.get_dimensions then return app_host.get_dimensions() end
    local renderer = app_host.renderer
    if renderer and renderer.get_dimensions then return renderer:get_dimensions() end
    return window_width, window_height
end

local function host_set_background_color(r, g, b, a)
    if app_host.set_background_color then return app_host.set_background_color(r, g, b, a) end
    local renderer = app_host.renderer
    if renderer and renderer.set_background_color then return renderer:set_background_color(r, g, b, a) end
end

local function host_quit()
    if app_host.quit then app_host.quit() end
end

local function host_is_key_down(...)
    if app_host.is_key_down then return app_host.is_key_down(...) end
    return false
end

local function viewport_value()
    return Viewport(window_width, window_height)
end

local function track_index_by_id(project, track_id)
    for i = 1, #project.tracks do
        if project.tracks[i].id == track_id then return i end
    end
    return 1
end

local function track_by_id(project, track_id)
    local i = track_index_by_id(project, track_id)
    return project.tracks[i], i
end

local function clip_by_id(project, clip_id)
    for i = 1, #project.clips do
        if project.clips[i].id == clip_id then return project.clips[i], i end
    end
    return nil, nil
end

local function selected_track_id(state)
    local sel = state.session.selection
    if sel == NoSelection then
        return state.project.tracks[1] and state.project.tracks[1].id or 1
    end
    local mt = getmetatable(sel)
    if mt == mtSelectedTrack then return sel.track_id end
    if mt == mtSelectedClip then
        local c = clip_by_id(state.project, sel.clip_id)
        return c and c.track_id or (state.project.tracks[1] and state.project.tracks[1].id or 1)
    end
    return 1
end

local function selected_track(state)
    local t, i = track_by_id(state.project, selected_track_id(state))
    return t, i
end

local function selected_clip(state)
    local sel = state.session.selection
    if getmetatable(sel) == mtSelectedClip then
        return clip_by_id(state.project, sel.clip_id)
    end
    return nil, nil
end

local function lookup_meter_level(payload, track_id)
    for i = 1, #payload.meter_levels do
        local m = payload.meter_levels[i]
        if m.track_id == track_id then return m.level end
    end
    return 0
end

local function update_runtime_payload(fields)
    runtime_payload = pvm2.with(runtime_payload, fields)
end

local function set_session(fields)
    source_state = pvm2.with(source_state, { session = pvm2.with(source_state.session, fields) })
end

local function set_project(fields)
    source_state = pvm2.with(source_state, { project = pvm2.with(source_state.project, fields) })
end

local function set_track_field(track_index, field, value)
    local tracks = {}
    for i = 1, #source_state.project.tracks do
        if i == track_index then
            tracks[i] = pvm2.with(source_state.project.tracks[i], { [field] = value })
        else
            tracks[i] = source_state.project.tracks[i]
        end
    end
    set_project({ tracks = tracks })
end

local function push_undo()
    undo_stack[#undo_stack + 1] = source_state
    if #undo_stack > 50 then table.remove(undo_stack, 1) end
end

local function pop_undo()
    if #undo_stack > 0 then
        source_state = undo_stack[#undo_stack]
        undo_stack[#undo_stack] = nil
    end
end

local function runtime_time_strings(project, time_ms)
    local time_sec = time_ms / 1000
    local beat_f = time_sec * project.bpm / 60
    local time_text = string.format("%02d:%02d.%03d",
        math.floor(time_sec / 60), math.floor(time_sec) % 60,
        math.floor((time_sec * 1000) % 1000))
    local beat_text = string.format("%.1f", beat_f + 1)
    local playhead_x = math.floor(beat_f * PIXELS_PER_BEAT)
    return time_text, beat_text, playhead_x
end

local function rebuild_runtime_payload(time_ms, meter_levels)
    local meter_values = {}
    for i = 1, #source_state.project.tracks do
        meter_values[i] = MeterLevelValue(source_state.project.tracks[i].id, meter_levels[i] or 0)
    end
    local time_text, beat_text, playhead_x = runtime_time_strings(source_state.project, time_ms)
    runtime_payload = RuntimePayload(playhead_x, time_text, beat_text, meter_values)
end

-- ══════════════════════════════════════════════════════════════
--  SOURCE → APPVIEW (SHARED PROJECTED SPINE)
-- ══════════════════════════════════════════════════════════════

local function view_metrics(state, viewport)
    local visible_height = viewport.window_height - TRANSPORT_HEIGHT - HEADER_HEIGHT
    local max_scroll = math.max(0, #state.project.tracks * ROW_HEIGHT - visible_height)
    local scroll_y = clamp(state.session.scroll_y, 0, max_scroll)
    local selected_track_value, selected_track_index = selected_track(state)
    local selected_clip_value = selected_clip(state)
    local arrangement_width = math.max(0, viewport.window_width - TRACK_PANEL_WIDTH - INSPECTOR_WIDTH)
    return {
        visible_height = visible_height,
        scroll_y = scroll_y,
        selected_track = selected_track_value,
        selected_track_index = selected_track_index,
        selected_clip = selected_clip_value,
        arrangement_width = arrangement_width,
    }
end

local function project_track_panel_view(state, viewport)
    local vm = view_metrics(state, viewport)
    local row_views = {}
    for i = 1, #state.project.tracks do
        local track = state.project.tracks[i]
        row_views[i] = TrackRowView(track.id, i, track, track.id == vm.selected_track.id)
    end
    return TrackPanelView(#state.project.tracks, row_views, vm.scroll_y, vm.visible_height)
end

local function project_arrangement_panel_view(state, viewport)
    local vm = view_metrics(state, viewport)
    local clip_views = {}
    local selected = state.session.selection
    local selected_mt = getmetatable(selected)
    for i = 1, #state.project.clips do
        local clip_value = state.project.clips[i]
        clip_views[i] = ClipView(
            clip_value.id,
            clip_value,
            track_index_by_id(state.project, clip_value.track_id),
            selected_mt == mtSelectedClip and selected.clip_id == clip_value.id,
            vm.scroll_y)
    end
    return ArrangementPanelView(#state.project.tracks, vm.arrangement_width, vm.visible_height, vm.scroll_y, clip_views, viewport.window_height - TRANSPORT_HEIGHT)
end

local function project_inspector_view(state, viewport)
    local vm = view_metrics(state, viewport)
    if vm.selected_clip then
        local clip_value = vm.selected_clip
        local track_value = track_by_id(state.project, clip_value.track_id)
        return ClipInspectorView(clip_value.id, clip_value, track_value, viewport.window_height - TRANSPORT_HEIGHT)
    end
    return TrackInspectorView(vm.selected_track.id, vm.selected_track, vm.selected_track_index, viewport.window_height - TRANSPORT_HEIGHT)
end

local function project_transport_panel_view(state, viewport)
    return TransportPanelView(state.project.bpm, state.session.playing, viewport.window_width)
end

local function project_root_view(state, viewport)
    return RootView(
        project_track_panel_view(state, viewport),
        project_arrangement_panel_view(state, viewport),
        project_inspector_view(state, viewport),
        project_transport_panel_view(state, viewport))
end

-- ══════════════════════════════════════════════════════════════
--  SOURCE → ui.Paint (GENERIC CUSTOM DRAWING)
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
--  STATIC UI HELPERS
-- ══════════════════════════════════════════════════════════════

local function button_ui(tag, width, height, bg, fg, font_id, label)
    local label_height = FONT_PIXELS[font_id] or height
    local label_y = math.max(0, math.floor((height - label_height) / 2))
    return stack({
        rect(tag, bg, box { w = px(width), h = px(height) }),
        transform(0, label_y,
            text(tag, label,
                style(font_id, fg, { align = ui.TEXT_CENTER, overflow = ui.OVERFLOW_CLIP }),
                box { w = px(width), h = px(label_height) })),
    })
end

local function kv_row(label, value, tag)
    return stack({
        text("", label, style(4, C.text_dim), box { w = px(84), h = px(18) }),
        transform(88, 0, text("", value, style(2, C.text), box { w = px(160), h = px(18) })),
    })
end

local function volume_slider_background_ui(tag, width, height)
    return stack({
        rect(tag, C.knob_bg, box { w = px(width), h = px(height) }),
        rect("", C.border, box { w = px(width), h = px(1) }),
    })
end

local function pan_slider_background_ui(tag, width, height)
    return stack({
        rect(tag, C.knob_bg, box { w = px(width), h = px(height) }),
        transform(math.floor(width / 2), 0, rect("", C.border, box { w = px(1), h = px(height) })),
    })
end

local function header_fragment_ui(track_count)
    return stack({
        rect("", C.panel, box { w = px(TRACK_PANEL_WIDTH), h = px(HEADER_HEIGHT) }),
        rect("", C.border, box { w = px(TRACK_PANEL_WIDTH), h = px(1) }),
        transform(14, 10, text("", "Tracks", style(3, C.text_bright))),
        transform(92, 12, text("", "(" .. track_count .. ")", style(4, C.text_dim))),
    })
end

local function scrollbar_fragment_ui(track_count, visible_height, scroll_y)
    local total_height = track_count * ROW_HEIGHT
    if total_height <= visible_height then
        return spacer(box { w = px(8), h = px(visible_height) })
    end
    local ratio = visible_height / total_height
    local thumb_height = math.max(20, math.floor(visible_height * ratio))
    local max_scroll = total_height - visible_height
    local thumb_y = math.floor((scroll_y / math.max(1, max_scroll)) * (visible_height - thumb_height))
    return stack({
        rect("", C.scrollbar, box { w = px(8), h = px(visible_height) }),
        transform(0, thumb_y, rect("", C.scrollthumb, box { w = px(8), h = px(thumb_height) })),
    })
end

local function track_row_fragment_ui(self)
    local track = self.track
    local tag = "track:" .. self.track_index
    local row_style = surface_style(
        self.is_selected and "track_row_selected" or ((self.track_index % 2 == 0) and "track_row_even" or "track_row_odd"))
    local mute_style = surface_style("mute_button", active_flags(track.mute))
    local solo_style = surface_style("solo_button", active_flags(track.solo))
    local layout = track_row_layout(TRACK_PANEL_WIDTH)
    return stack({
        rect(tag, row_style.bg, box { w = px(TRACK_PANEL_WIDTH), h = px(ROW_HEIGHT) }),
        rect("", track.color, box { w = px(4), h = px(ROW_HEIGHT) }),
        transform(layout.name_x, 14,
            text(tag, track.name,
                style(2, row_style.fg, { overflow = ui.OVERFLOW_ELLIPSIS }),
                box { w = px(layout.name_w), h = px(18) })),
        transform(layout.mute_x, 14,
            button_ui(tag .. ":mute", TRACK_ROW_BUTTON_W, TRACK_ROW_BUTTON_H,
                mute_style.bg, mute_style.fg,
                4, "M")),
        transform(layout.solo_x, 14,
            button_ui(tag .. ":solo", TRACK_ROW_BUTTON_W, TRACK_ROW_BUTTON_H,
                solo_style.bg, solo_style.fg,
                4, "S")),
        transform(layout.slider_x, 8, volume_slider_background_ui(tag .. ":vol", layout.slider_w, 10)),
        transform(layout.slider_x, 30, pan_slider_background_ui(tag .. ":pan", layout.slider_w, 10)),
        transform(layout.meter_x, 4,
            rect("", C.meter_bg, box { w = px(METER_WIDTH), h = px(ROW_HEIGHT - 8) })),
    })
end

local function clip_fragment_ui(self)
    local clip_value = self.clip
    local width = math.floor(from_q16(clip_value.dur_q16) * PIXELS_PER_BEAT)
    local color = self.is_selected and C.accent or clip_value.color
    return stack({
        rect("clip:" .. clip_value.id, color, box { w = px(width), h = px(ROW_HEIGHT - 8) }),
        transform(6, 2,
            text("", clip_value.label,
                style(4, C.text_bright, { overflow = ui.OVERFLOW_ELLIPSIS }),
                box { w = px(math.max(0, width - 12)), h = px(14) })),
    })
end

local function arrangement_background_fragment_ui(self)
    local grid, ruler, lane_backgrounds = {}, {}, {}
    local visible_width = self.visible_width
    local visible_height = self.visible_height
    local visible_beats = math.floor(visible_width / PIXELS_PER_BEAT) + 4
    for i = 1, self.track_count do
        local y = (i - 1) * ROW_HEIGHT - self.scroll_y
        lane_backgrounds[#lane_backgrounds + 1] = transform(0, y,
            rect("", (i % 2 == 0) and C.row_even or C.row_odd,
                box { w = px(visible_width), h = px(ROW_HEIGHT) }))
    end
    for beat_index = 0, visible_beats do
        local x = beat_index * PIXELS_PER_BEAT
        local grid_color = (beat_index % 4 == 0) and C.border or C.panel
        grid[#grid + 1] = transform(x, 0,
            rect("", grid_color,
                box { w = px(1), h = px(visible_height) }))
        if beat_index % 4 == 0 then
            ruler[#ruler + 1] = transform(x + 4, 0,
                text("", tostring(math.floor(beat_index / 4) + 1), style(4, C.text_dim)))
        end
        ruler[#ruler + 1] = transform(x, 0,
            rect("", C.border,
                box { w = px(1), h = px((beat_index % 4 == 0) and HEADER_HEIGHT or 10) }))
    end
    return stack({
        rect("", C.bg, box { w = px(visible_width), h = px(self.playhead_height) }),
        clip(stack(lane_backgrounds)),
        stack({
            rect("", C.panel, box { w = px(visible_width), h = px(HEADER_HEIGHT) }),
            clip(stack(ruler)),
        }),
        transform(0, HEADER_HEIGHT, clip(stack(grid))),
    })
end

local function track_inspector_fragment_ui(self)
    local track = self.track
    local h = self.panel_height
    local mute_style = surface_style("mute_button", active_flags(track.mute))
    local solo_style = surface_style("solo_button", active_flags(track.solo))
    return stack({
        rect("", C.panel, box { w = px(INSPECTOR_WIDTH), h = px(h) }),
        rect("", C.border, box { w = px(1), h = px(h) }),
        transform(16, 16, text("", "Track Inspector", style(3, C.text_bright))),
        transform(16, 40, rect("", C.border, box { w = px(INSPECTOR_WIDTH - 32), h = px(1) })),
        transform(16, 54, stack({
            kv_row("Track", track.name, "inspector:name"),
            transform(0, 24, kv_row("Index", tostring(self.track_index), "inspector:index")),
            transform(0, 48, kv_row("Volume", string.format("%.0f%%", track.vol * 100), "inspector:volume")),
            transform(0, 72, kv_row("Pan", string.format("%.0f%%", (track.pan - 0.5) * 200), "inspector:pan")),
            transform(0, 96, kv_row("Mute", track.mute and "ON" or "off", "inspector:mute")),
            transform(0, 120, kv_row("Solo", track.solo and "ON" or "off", "inspector:solo")),
        })),
        transform(16, 188, rect("", C.border, box { w = px(INSPECTOR_WIDTH - 32), h = px(1) })),
        transform(16, 202, text("", "Volume", style(4, C.text_dim))),
        transform(16, 224, volume_slider_background_ui("insp:vol_slider", INSPECTOR_WIDTH - 32, 14)),
        transform(16, 248, text("", "Pan", style(4, C.text_dim))),
        transform(16, 270, pan_slider_background_ui("insp:pan_slider", INSPECTOR_WIDTH - 32, 14)),
        transform(16, 296, rect("", C.border, box { w = px(INSPECTOR_WIDTH - 32), h = px(1) })),
        transform(16, 314, button_ui("insp:mute_btn", 70, 28,
            mute_style.bg, mute_style.fg,
            2, track.mute and "MUTED" or "Mute")),
        transform(94, 314, button_ui("insp:solo_btn", 70, 28,
            solo_style.bg, solo_style.fg,
            2, track.solo and "SOLO'D" or "Solo")),
    })
end

local function clip_inspector_fragment_ui(self)
    local h = self.panel_height
    return stack({
        rect("", C.panel, box { w = px(INSPECTOR_WIDTH), h = px(h) }),
        rect("", C.border, box { w = px(1), h = px(h) }),
        transform(16, 16, text("", "Clip Inspector", style(3, C.text_bright))),
        transform(16, 40, rect("", C.border, box { w = px(INSPECTOR_WIDTH - 32), h = px(1) })),
        transform(16, 54, stack({
            kv_row("Clip", self.clip.label, "inspector:clip"),
            transform(0, 24, kv_row("Track", self.track.name, "inspector:track")),
            transform(0, 48, kv_row("Start", string.format("%.1f beats", from_q16(self.clip.beat_q16)), "inspector:start")),
            transform(0, 72, kv_row("Length", string.format("%.1f beats", from_q16(self.clip.dur_q16)), "inspector:length")),
        })),
        transform(16, 160, text("",
            "This clip is projected from the same source object into the arrangement and inspector.",
            style(4, C.text_dim, { wrap = ui.TEXT_WORDWRAP, overflow = ui.OVERFLOW_CLIP }),
            box { w = px(INSPECTOR_WIDTH - 32), h = px(90) })),
    })
end

local function transport_fragment_ui(self)
    local play_label = self.is_playing and "||" or ">"
    local layout = transport_layout(self.panel_width)
    local bpm_value_w = math.max(24, layout.bpm_w - (TRANSPORT_SMALL_BUTTON_W * 2 + 4))
    local play_style = surface_style("transport_play", active_flags(self.is_playing))
    local transport_button = surface_style("transport_button")
    local small_button = surface_style("button")
    return stack({
        rect("", C.transport_bg, box { w = px(self.panel_width), h = px(TRANSPORT_HEIGHT) }),
        rect("", C.border, box { w = px(self.panel_width), h = px(1) }),
        transform(layout.play_x, 11, button_ui("transport:play", TRANSPORT_MAIN_BUTTON_W, 30,
            play_style.bg, play_style.fg, 3, play_label)),
        transform(layout.stop_x, 11, button_ui("transport:stop", TRANSPORT_MAIN_BUTTON_W, 30,
            transport_button.bg, transport_button.fg, 3, "[]")),
        transform(layout.controls_end + 18, 8, rect("", C.border, box { w = px(1), h = px(36) })),
        transform(layout.time_x, 9, text("", "TIME", style(4, C.text_dim))),
        transform(layout.beat_x, 9, text("", "BEAT", style(4, C.text_dim))),
        transform(layout.bpm_x, 9, text("", "BPM", style(4, C.text_dim))),
        transform(layout.bpm_x, 25, button_ui("transport:bpm-", TRANSPORT_SMALL_BUTTON_W, 20,
            small_button.bg, small_button.fg, 4, "-")),
        transform(layout.bpm_x + TRANSPORT_SMALL_BUTTON_W + 2, 25,
            text("", tostring(self.bpm),
                style(3, C.accent, { align = ui.TEXT_CENTER, overflow = ui.OVERFLOW_CLIP }),
                box { w = px(bpm_value_w), h = px(20) })),
        transform(layout.bpm_x + layout.bpm_w - TRANSPORT_SMALL_BUTTON_W, 25,
            button_ui("transport:bpm+", TRANSPORT_SMALL_BUTTON_W, 20,
                small_button.bg, small_button.fg, 4, "+")),
        transform(layout.status_x, 18,
            text("", self.is_playing and "RECORDING" or "STOPPED",
                style(4, C.text_dim, { align = ui.TEXT_END, overflow = ui.OVERFLOW_CLIP }),
                box { w = px(layout.status_w), h = px(18) })),
    })
end

-- ══════════════════════════════════════════════════════════════
--  APPVIEW → STATIC FRAGMENTS / STATIC PLAN
-- ══════════════════════════════════════════════════════════════

local static_fragment = pvm2.lower("ui7.static.fragment", function(self)
    local mt = getmetatable(self)
    if mt == TrackRowView then
        return ui.fragment(track_row_fragment_ui(self), TRACK_PANEL_WIDTH, ROW_HEIGHT)
    elseif mt == ClipView then
        local width = math.floor(from_q16(self.clip.dur_q16) * PIXELS_PER_BEAT)
        return ui.fragment(clip_fragment_ui(self), width, ROW_HEIGHT - 8)
    elseif mt == TrackInspectorView then
        return ui.fragment(track_inspector_fragment_ui(self), INSPECTOR_WIDTH, self.panel_height)
    elseif mt == ClipInspectorView then
        return ui.fragment(clip_inspector_fragment_ui(self), INSPECTOR_WIDTH, self.panel_height)
    elseif mt == TransportPanelView then
        return ui.fragment(transport_fragment_ui(self), self.panel_width, TRANSPORT_HEIGHT)
    end
    error("ui7.static.fragment: no handler for " .. tostring(mt and mt.kind or type(self)), 2)
end, { input = "table" })

function TrackRowView:fragment() return static_fragment(self) end
function ClipView:fragment() return static_fragment(self) end
function TrackInspectorView:fragment() return static_fragment(self) end
function ClipInspectorView:fragment() return static_fragment(self) end
function TransportPanelView:fragment() return static_fragment(self) end

local static_commands_builder = pvm2.verb_memo("static_commands", {
    [T.AppView.RootView] = function(self, out)
        self.track_panel:static_commands(out)
        out[#out + 1] = ui.push_transform_cmd(TRACK_PANEL_WIDTH, 0)
        self.arrangement_panel:static_commands(out)
        out[#out + 1] = ui.pop_transform_cmd(TRACK_PANEL_WIDTH, 0)
        out[#out + 1] = ui.push_transform_cmd(TRACK_PANEL_WIDTH + self.arrangement_panel.visible_width, 0)
        self.inspector_panel:static_commands(out)
        out[#out + 1] = ui.pop_transform_cmd(TRACK_PANEL_WIDTH + self.arrangement_panel.visible_width, 0)
        out[#out + 1] = ui.push_transform_cmd(0, self.arrangement_panel.playhead_height)
        self.transport_panel:static_commands(out)
        out[#out + 1] = ui.pop_transform_cmd(0, self.arrangement_panel.playhead_height)
    end,
    [T.AppView.TrackPanelView] = function(self, out)
        ui.append_fragment_cmds(out, 0, 0,
            ui.fragment(header_fragment_ui(self.track_count), TRACK_PANEL_WIDTH, HEADER_HEIGHT))
        ui.append_fragment_cmds(out, 0, HEADER_HEIGHT,
            ui.fragment(rect("track_panel:bg", C.bg,
                box { w = px(TRACK_PANEL_WIDTH), h = px(self.visible_height) }),
                TRACK_PANEL_WIDTH, self.visible_height))
        out[#out + 1] = ui.push_clip_cmd(0, HEADER_HEIGHT, TRACK_PANEL_WIDTH, self.visible_height)
        out[#out + 1] = ui.push_transform_cmd(0, -self.scroll_y)
        for i = 1, #self.track_row_views do self.track_row_views[i]:static_commands(out) end
        out[#out + 1] = ui.pop_transform_cmd(0, -self.scroll_y)
        out[#out + 1] = ui.pop_clip_cmd(0, HEADER_HEIGHT, TRACK_PANEL_WIDTH, self.visible_height)
        out[#out + 1] = ui.push_transform_cmd(TRACK_PANEL_WIDTH - 8, HEADER_HEIGHT)
        ui.append_fragment_cmds(out, 0, 0,
            ui.fragment(scrollbar_fragment_ui(self.track_count, self.visible_height, self.scroll_y), 8, self.visible_height))
        out[#out + 1] = ui.pop_transform_cmd(TRACK_PANEL_WIDTH - 8, HEADER_HEIGHT)
    end,
    [T.AppView.TrackRowView] = function(self, out)
        ui.append_fragment_cmds(out, 0, (self.track_index - 1) * ROW_HEIGHT, self:fragment())
    end,
    [T.AppView.ArrangementPanelView] = function(self, out)
        ui.append_fragment_cmds(out, 0, 0,
            ui.fragment(arrangement_background_fragment_ui(self), self.visible_width, self.playhead_height))
        out[#out + 1] = ui.push_clip_cmd(0, HEADER_HEIGHT, self.visible_width, self.visible_height)
        for i = 1, #self.clip_views do self.clip_views[i]:static_commands(out) end
        out[#out + 1] = ui.pop_clip_cmd(0, HEADER_HEIGHT, self.visible_width, self.visible_height)
    end,
    [T.AppView.ClipView] = function(self, out)
        local x = math.floor(from_q16(self.clip.beat_q16) * PIXELS_PER_BEAT)
        local y = HEADER_HEIGHT + (self.track_index - 1) * ROW_HEIGHT - self.scroll_y + 4
        ui.append_fragment_cmds(out, x, y, self:fragment())
    end,
    [T.AppView.TrackInspectorView] = function(self, out)
        ui.append_fragment_cmds(out, 0, 0, self:fragment())
    end,
    [T.AppView.ClipInspectorView] = function(self, out)
        ui.append_fragment_cmds(out, 0, 0, self:fragment())
    end,
    [T.AppView.TransportPanelView] = function(self, out)
        ui.append_fragment_cmds(out, 0, 0, self:fragment())
    end,
}, { flat = true, name = "ui7.static.commands" })

-- ══════════════════════════════════════════════════════════════
--  GENERIC ui.Paint / Paint.Cmd[] + RUNTIME ENV
-- ══════════════════════════════════════════════════════════════

local PLAYHEAD_X_REF = ui.num_ref("playhead_x")
local TIME_TEXT_REF = ui.text_ref("transport_time")
local BEAT_TEXT_REF = ui.text_ref("transport_beat")

local function meter_y_ref(track_id)
    return ui.num_ref("meter:" .. track_id .. ":y")
end

local function meter_h_ref(track_id)
    return ui.num_ref("meter:" .. track_id .. ":h")
end

local function meter_color_ref(track_id)
    return ui.color_ref("meter:" .. track_id .. ":color")
end

local function project_root_overlay(state, viewport)
    local vm = view_metrics(state, viewport)
    local meter_children = {}
    local meter_layout = track_row_layout(TRACK_PANEL_WIDTH)
    for i = 1, #state.project.tracks do
        local track = state.project.tracks[i]
        meter_children[i] = ui.paint_rect("meter:" .. track.id,
            meter_layout.meter_x,
            meter_y_ref(track.id),
            METER_WIDTH,
            meter_h_ref(track.id),
            meter_color_ref(track.id))
    end

    local transport = transport_layout(viewport.window_width)

    return ui.paint_group({
        ui.paint_clip(0, HEADER_HEIGHT, TRACK_PANEL_WIDTH, vm.visible_height,
            ui.paint_group(meter_children)),
        ui.paint_transform(TRACK_PANEL_WIDTH, 0,
            ui.paint_line("playhead",
                PLAYHEAD_X_REF, 0,
                PLAYHEAD_X_REF, viewport.window_height - TRANSPORT_HEIGHT,
                2, C.text_bright)),
        ui.paint_transform(0, viewport.window_height - TRANSPORT_HEIGHT,
            ui.paint_group({
                ui.paint_text("transport:time",
                    transport.time_x, 24, transport.time_w, 18,
                    style(3, C.text_bright, { overflow = ui.OVERFLOW_CLIP }),
                    TIME_TEXT_REF),
                ui.paint_text("transport:beat",
                    transport.beat_x, 24, transport.beat_w, 18,
                    style(3, C.text_bright, { overflow = ui.OVERFLOW_CLIP }),
                    BEAT_TEXT_REF),
            })),
    })
end

local function meter_fill_color(level)
    return level > 0.9 and C.meter_clip or (level > 0.7 and C.meter_hot or C.meter_fill)
end

local function build_overlay_runtime(payload)
    local numbers = {
        playhead_x = payload.playhead_x,
    }
    local texts = {
        transport_time = payload.transport_time_text,
        transport_beat = payload.transport_beat_text,
    }
    local colors = {}
    local vm = view_metrics(source_state, viewport_value())
    local meter_h = ROW_HEIGHT - 8

    for i = 1, #source_state.project.tracks do
        local track = source_state.project.tracks[i]
        local level = clamp(lookup_meter_level(payload, track.id), 0, 1)
        local fill = math.floor(meter_h * level)
        numbers["meter:" .. track.id .. ":h"] = fill
        numbers["meter:" .. track.id .. ":y"] = HEADER_HEIGHT + (i - 1) * ROW_HEIGHT - vm.scroll_y + 4 + (meter_h - fill)
        colors["meter:" .. track.id .. ":color"] = meter_fill_color(level)
    end

    return {
        numbers = numbers,
        texts = texts,
        colors = colors,
    }
end

-- ══════════════════════════════════════════════════════════════
--  LIVE STATE + RECOMPILE
-- ══════════════════════════════════════════════════════════════

local NAMES = {"Kick","Snare","Hi-Hat","Bass","Lead Synth","Pad",
               "FX Rise","Vocal Chop","Perc","Sub Bass","Strings","Piano"}
local COLORS = {C.green,C.red,C.orange,C.purple,C.cyan,C.accent,
                C.orange,C.green,C.red,C.purple,C.cyan,C.accent}

local function zero_meter_levels()
    local z = {}
    for i = 1, #source_state.project.tracks do z[i] = 0 end
    return z
end

local function recompile_static()
    local current_viewport = viewport_value()
    local root_view = project_root_view(source_state, current_viewport)
    local _, cmds = root_view:static_commands()
    static_commands = cmds
    overlay_commands = ui.compile_paint(project_root_overlay(source_state, current_viewport))
end

local function active_track_index()
    local _, index = selected_track(source_state)
    return index
end

local function dispatch(track_index, field, value)
    push_undo()
    if field == "selection" then
        set_session({ selection = value })
    elseif field == "scroll_y" then
        set_session({ scroll_y = value })
    elseif field == "bpm" then
        set_project({ bpm = value })
        local time_text, beat_text, playhead_x = runtime_time_strings(source_state.project, 0)
        update_runtime_payload({ transport_time_text = time_text, transport_beat_text = beat_text, playhead_x = playhead_x })
    else
        set_track_field(track_index, field, value)
    end
end

local function handle_click(tag, mouse_x)
    if not tag then return end

    local clip_id = tonumber(tag:match("^clip:(%d+)"))
    if clip_id then
        dispatch(0, "selection", SelectedClip(clip_id))
        return
    end

    local track_index = tonumber(tag:match("^track:(%d+)"))
    if track_index then
        dispatch(0, "selection", SelectedTrack(source_state.project.tracks[track_index].id))
        if tag:find(":mute", 1, true) then
            dispatch(track_index, "mute", not source_state.project.tracks[track_index].mute)
        elseif tag:find(":solo", 1, true) then
            dispatch(track_index, "solo", not source_state.project.tracks[track_index].solo)
        elseif tag:find(":vol", 1, true) then
            dragging = { tag = tag, track_index = track_index, field = "vol", x0 = mouse_x, value0 = source_state.project.tracks[track_index].vol, width = track_row_layout(TRACK_PANEL_WIDTH).slider_w }
        elseif tag:find(":pan", 1, true) then
            dragging = { tag = tag, track_index = track_index, field = "pan", x0 = mouse_x, value0 = source_state.project.tracks[track_index].pan, width = track_row_layout(TRACK_PANEL_WIDTH).slider_w }
        end
        return
    end

    local current_track_index = active_track_index()
    if tag:find("^insp:vol_slider") then
        dragging = { tag = tag, track_index = current_track_index, field = "vol", x0 = mouse_x, value0 = source_state.project.tracks[current_track_index].vol, width = INSPECTOR_WIDTH - 32 }
        return
    end
    if tag:find("^insp:pan_slider") then
        dragging = { tag = tag, track_index = current_track_index, field = "pan", x0 = mouse_x, value0 = source_state.project.tracks[current_track_index].pan, width = INSPECTOR_WIDTH - 32 }
        return
    end
    if tag:find("^insp:mute_btn") then dispatch(current_track_index, "mute", not source_state.project.tracks[current_track_index].mute); return end
    if tag:find("^insp:solo_btn") then dispatch(current_track_index, "solo", not source_state.project.tracks[current_track_index].solo); return end
    if tag:find("^transport:play") then set_session({ playing = not source_state.session.playing }); return end
    if tag:find("^transport:stop") then set_session({ playing = false }); rebuild_runtime_payload(0, zero_meter_levels()); return end
    if tag:find("^transport:bpm%-") then dispatch(0, "bpm", math.max(40, source_state.project.bpm - 5)); return end
    if tag:find("^transport:bpm%+") then dispatch(0, "bpm", math.min(300, source_state.project.bpm + 5)); return end
end

-- ══════════════════════════════════════════════════════════════
--  APP ENTRYPOINT
-- ══════════════════════════════════════════════════════════════

function app.init(host)
    app_host = host or {}
    ui.set_backend(app_host.renderer)

    host_set_background_color(0.054, 0.067, 0.090, 1)
    fonts[1] = host_new_font(18)
    fonts[2] = host_new_font(13)
    fonts[3] = host_new_font(15)
    fonts[4] = host_new_font(10)
    ui.set_font(1, fonts[1])
    ui.set_font(2, fonts[2])
    ui.set_font(3, fonts[3])
    ui.set_font(4, fonts[4])
    if host_renderer().set_font then host_renderer():set_font(fonts[2]) end

    local tracks, clips = {}, {}
    local initial_meter_levels = {}
    for i = 1, #NAMES do
        tracks[i] = Track(i, NAMES[i], COLORS[i], 0.75, 0.5, false, false)
        clips[i] = Clip(i, i, q16((i * 37) % 8), q16(2 + (i % 3)), NAMES[i], COLORS[i])
        initial_meter_levels[i] = 0
    end

    source_state = State(
        Project(tracks, clips, 120),
        Session(SelectedTrack(1), 0, false))

    window_width, window_height = host_dimensions()
    rebuild_runtime_payload(0, initial_meter_levels)
    recompile_static()
end

function app.resize(w, h)
    window_width, window_height = w, h
    recompile_static()
end

function app.update(dt)
    local next_meter_levels = {}
    local current_time_ms = 0
    if runtime_payload then
        current_time_ms = math.floor((runtime_payload.playhead_x / PIXELS_PER_BEAT) * (60 / source_state.project.bpm) * 1000 + 0.5)
    end
    if source_state.session.playing then
        current_time_ms = current_time_ms + math.floor(dt * 1000 + 0.5)
    end

    local time_sec = current_time_ms / 1000
    for i = 1, #source_state.project.tracks do
        local track = source_state.project.tracks[i]
        local target = 0
        if source_state.session.playing and not track.mute then
            target = (0.3 + 0.5 * math.abs(math.sin(time_sec * (1.5 + i * 0.3) + i * 0.7))) * track.vol
        end
        local current = lookup_meter_level(runtime_payload, track.id)
        local next_value = current + (target - current) * math.min(1, dt * 12)
        next_meter_levels[i] = math.floor(next_value * 100) / 100
    end

    rebuild_runtime_payload(current_time_ms, next_meter_levels)
end

function app.keypressed(key)
    if key == "escape" then host_quit() end
    if key == "space" then
        set_session({ playing = not source_state.session.playing })
        recompile_static()
    end
    if key == "up" then
        local _, index = selected_track(source_state)
        index = math.max(1, index - 1)
        dispatch(0, "selection", SelectedTrack(source_state.project.tracks[index].id))
        recompile_static()
    end
    if key == "down" then
        local _, index = selected_track(source_state)
        index = math.min(#source_state.project.tracks, index + 1)
        dispatch(0, "selection", SelectedTrack(source_state.project.tracks[index].id))
        recompile_static()
    end
    if key == "m" then
        local index = active_track_index()
        dispatch(index, "mute", not source_state.project.tracks[index].mute)
        recompile_static()
    end
    if key == "s" then
        local index = active_track_index()
        dispatch(index, "solo", not source_state.project.tracks[index].solo)
        recompile_static()
    end
    if key == "r" then
        set_session({ playing = false })
        rebuild_runtime_payload(0, zero_meter_levels())
        recompile_static()
    end
    if key == "z" and host_is_key_down("lctrl", "rctrl") then
        pop_undo()
        recompile_static()
    end
end

function app.mousepressed(mx, my, button)
    if button == 1 then
        local tag = ui.hit(static_commands, mx, my)
        pointer_hot.pressed = tag
        pointer_hot.hovered = tag
        handle_click(tag, mx)
        recompile_static()
    end
end

function app.mousereleased()
    if dragging then dragging = nil end
    pointer_hot.pressed = nil
    pointer_hot.dragging = nil
end

function app.mousemoved(mx, my)
    if dragging then
        local next_value = clamp(dragging.value0 + (mx - dragging.x0) / dragging.width, 0, 1)
        dispatch(dragging.track_index, dragging.field, next_value)
        pointer_hot.dragging = dragging.tag
        recompile_static()
    else
        pointer_hot.dragging = nil
    end
    pointer_hot.hovered = ui.hit(static_commands, mx, my)
end

function app.wheelmoved(_, wy)
    local visible_height = window_height - TRANSPORT_HEIGHT - HEADER_HEIGHT
    local max_scroll = math.max(0, #source_state.project.tracks * ROW_HEIGHT - visible_height)
    dispatch(0, "scroll_y", clamp(source_state.session.scroll_y - wy * 30, 0, max_scroll))
    recompile_static()
end

function app.draw()
    ui.paint(static_commands, { hot = pointer_hot, backend = app_host.renderer })
    ui.paint_custom(overlay_commands, build_overlay_runtime(runtime_payload), { hot = pointer_hot, backend = app_host.renderer })
end

return app
