-- examples/ui7/main.lua — immediate ui7 demo on top of canonical uilib
-- Canonical launcher: examples/ui7/main.t (SDL3 + OpenGL + SDL_ttf via Terra)
--
-- Architecture:
--   App.State + App.Viewport
--     ↓ project_view
--   AppView.Node                 -- typed semantic view spine
--     ↓ root_view_ui(...)
--   immediate UI param tree      -- rebuilt directly from current state each frame
--
--   AppRuntime.Payload           -- live transport/meters/playhead state
--   live_track_fields            -- in-progress slider drags before commit
--
--   Draw:
--     ui.draw(current_root_ui(), frame, ...)
--
-- No retained command compilation is used in the demo path anymore.

local THIS_SOURCE = debug.getinfo(1, "S").source
local THIS_DIR = THIS_SOURCE:sub(1, 1) == "@" and THIS_SOURCE:match("^@(.+)/[^/]+$") or "."
local ROOT_DIR = THIS_DIR .. "/../.."
package.path = table.concat({
    ROOT_DIR .. "/?.lua", ROOT_DIR .. "/?/init.lua", package.path
}, ";")

local pvm2 = require("pvm2")
local iter = require("iter")
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
    bg=hex(0xff0e1117),
    panel=hex(0xff161b22),
    panel_hi=hex(0xff1c2330),
    panel_alt=hex(0xff11161d),
    panel_elevated=hex(0xff202734),
    border=hex(0xff30363d),
    border_soft=hex(0xff242c36),
    border_strong=hex(0xff3d4654),
    text=hex(0xffe6edf3),
    text_soft=hex(0xffc9d1d9),
    text_dim=hex(0xff8b949e),
    text_faint=hex(0xff6e7681),
    text_bright=hex(0xffffffff),
    accent=hex(0xff58a6ff),
    accent_dim=hex(0xff1f6feb),
    accent_hi=hex(0xff79c0ff),
    green=hex(0xff3fb950),
    green_hi=hex(0xff56d364),
    red=hex(0xfff85149),
    red_hi=hex(0xffff7b72),
    orange=hex(0xffd29922),
    purple=hex(0xffbc8cff),
    cyan=hex(0xff79c0ff),
    mute_on=hex(0xffda3633),
    solo_on=hex(0xff58a6ff),
    meter_bg=hex(0xff21262d),
    meter_fill=hex(0xff3fb950),
    meter_hot=hex(0xffd29922),
    meter_clip=hex(0xfff85149),
    knob_bg=hex(0xff30363d),
    knob_fg=hex(0xff58a6ff),
    knob_pan=hex(0xffbc8cff),
    transport_bg=hex(0xff0d1117),
    scrollbar=hex(0xff30363d),
    scrollthumb=hex(0xff484f58),
    badge_bg=hex(0xff21262d),
    badge_hi=hex(0xff30363d),
    row_even=hex(0xff0d1117),
    row_odd=hex(0xff161b22),
    row_active=hex(0xff1f2937),
    clip_bg=hex(0xff1d2430),
    overlay=hex(0x66161b22),
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
local TRACK_ROW_SLIDER_H = 10
local INSPECTOR_SLIDER_H = 16
local SLIDER_THUMB_W = 6

local TRANSPORT_PAD_X = 16
local TRANSPORT_MAIN_BUTTON_W = 48
local TRANSPORT_SMALL_BUTTON_W = 22

-- ══════════════════════════════════════════════════════════════
--  DESIGN SYSTEM SURFACES
-- ══════════════════════════════════════════════════════════════

local UI_THEME = ds.theme("ui7", {
    colors = {
        { "canvas", C.bg },
        { "panel", C.panel },
        { "panel_hi", C.panel_hi },
        { "panel_alt", C.panel_alt },
        { "panel_elevated", C.panel_elevated },
        { "border", C.border },
        { "border_soft", C.border_soft },
        { "border_strong", C.border_strong },
        { "text", C.text },
        { "text_soft", C.text_soft },
        { "text_dim", C.text_dim },
        { "text_faint", C.text_faint },
        { "text_bright", C.text_bright },
        { "accent", C.accent },
        { "accent_dim", C.accent_dim },
        { "accent_hi", C.accent_hi },
        { "success", C.green },
        { "success_hi", C.green_hi },
        { "danger", C.mute_on },
        { "danger_hi", C.red_hi },
        { "warning", C.orange },
        { "solo", C.solo_on },
        { "meter_bg", C.meter_bg },
        { "slider_track", C.knob_bg },
        { "slider_fill", C.knob_fg },
        { "slider_pan", C.knob_pan },
        { "badge_bg", C.badge_bg },
        { "badge_hi", C.badge_hi },
        { "transport_bg", C.transport_bg },
        { "scrollbar", C.scrollbar },
        { "scrollthumb", C.scrollthumb },
        { "row_even", C.row_even },
        { "row_odd", C.row_odd },
        { "row_active", C.row_active },
    },
    spaces = {
        { "hair", 1 },
        { "xs", 4 },
        { "sm", 6 },
        { "md", 8 },
        { "lg", 12 },
        { "xl", 16 },
        { "xxl", 20 },
    },
    fonts = {
        { "display", 1 },
        { "body", 2 },
        { "title", 3 },
        { "label", 4 },
    },
    surfaces = {
        ds.surface("panel_shell", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("panel")), ds.fg(ds.ctok("text")),
                ds.border_color(ds.ctok("border_soft")), ds.accent(ds.ctok("accent")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("xl")), ds.pad_v(ds.stok("xl")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("body")),
            }),
        }),
        ds.surface("panel_card", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("panel_alt")), ds.fg(ds.ctok("text")),
                ds.border_color(ds.ctok("border_soft")), ds.accent(ds.ctok("accent")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.bg(ds.ctok("panel_hi")), ds.border_color(ds.ctok("border")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("lg")), ds.pad_v(ds.stok("lg")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("body")),
            }),
        }),
        ds.surface("panel_chip", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("badge_bg")), ds.fg(ds.ctok("text_soft")), ds.border_color(ds.ctok("border_soft")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("md")), ds.pad_v(ds.stok("xs")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("label")),
            }),
        }),
        ds.surface("readout", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("panel_alt")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border_soft")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("md")), ds.pad_v(ds.stok("sm")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("title")),
            }),
        }),
        ds.surface("track_row_even", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("row_even")), ds.fg(ds.ctok("text")), ds.border_color(ds.ctok("border_soft")), ds.accent(ds.ctok("accent")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.bg(ds.ctok("panel_hi")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border")),
            }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, {
                ds.bg(ds.ctok("panel")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border_strong")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("lg")), ds.pad_v(ds.stok("md")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("body")), ds.gap_decl(ds.stok("sm")),
            }),
        }),
        ds.surface("track_row_odd", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("row_odd")), ds.fg(ds.ctok("text")), ds.border_color(ds.ctok("border_soft")), ds.accent(ds.ctok("accent")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.bg(ds.ctok("panel_hi")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border")),
            }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, {
                ds.bg(ds.ctok("panel")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border_strong")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("lg")), ds.pad_v(ds.stok("md")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("body")), ds.gap_decl(ds.stok("sm")),
            }),
        }),
        ds.surface("track_row_selected", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("row_active")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("accent_dim")), ds.accent(ds.ctok("accent_hi")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.bg(ds.ctok("panel_hi")), ds.border_color(ds.ctok("accent")),
            }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, {
                ds.bg(ds.ctok("accent_dim")), ds.border_color(ds.ctok("accent_hi")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("lg")), ds.pad_v(ds.stok("md")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("body")), ds.gap_decl(ds.stok("sm")),
            }),
        }),
        ds.surface("button", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("panel_alt")), ds.fg(ds.ctok("text_soft")), ds.border_color(ds.ctok("border_soft")), ds.accent(ds.ctok("accent")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.bg(ds.ctok("panel_hi")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border")),
            }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, {
                ds.bg(ds.ctok("panel")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border_strong")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("md")), ds.pad_v(ds.stok("sm")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("body")),
            }),
        }),
        ds.surface("mute_button", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("panel_alt")), ds.fg(ds.ctok("text_dim")), ds.border_color(ds.ctok("border_soft")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.bg(ds.ctok("panel_hi")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border")),
            }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, {
                ds.bg(ds.ctok("transport_bg")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border_strong")),
            }),
            ds.paint_rule(ds.sel { flags = { "active" } }, {
                ds.bg(ds.ctok("danger")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("danger_hi")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered", flags = { "active" } }, {
                ds.bg(ds.ctok("danger_hi")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("sm")), ds.pad_v(ds.stok("xs")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("label")),
            }),
        }),
        ds.surface("solo_button", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("panel_alt")), ds.fg(ds.ctok("text_dim")), ds.border_color(ds.ctok("border_soft")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.bg(ds.ctok("panel_hi")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border")),
            }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, {
                ds.bg(ds.ctok("transport_bg")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border_strong")),
            }),
            ds.paint_rule(ds.sel { flags = { "active" } }, {
                ds.bg(ds.ctok("solo")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("accent_hi")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered", flags = { "active" } }, {
                ds.bg(ds.ctok("accent")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("sm")), ds.pad_v(ds.stok("xs")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("label")),
            }),
        }),
        ds.surface("transport_play", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("panel_alt")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border_soft")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.bg(ds.ctok("panel_hi")), ds.border_color(ds.ctok("accent")),
            }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, {
                ds.bg(ds.ctok("transport_bg")), ds.border_color(ds.ctok("accent_hi")),
            }),
            ds.paint_rule(ds.sel { flags = { "active" } }, {
                ds.bg(ds.ctok("accent_dim")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("accent_hi")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered", flags = { "active" } }, {
                ds.bg(ds.ctok("accent")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("md")), ds.pad_v(ds.stok("sm")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("title")),
            }),
        }),
        ds.surface("transport_button", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("panel_alt")), ds.fg(ds.ctok("text_soft")), ds.border_color(ds.ctok("border_soft")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.bg(ds.ctok("panel_hi")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border")),
            }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, {
                ds.bg(ds.ctok("transport_bg")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border_strong")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("md")), ds.pad_v(ds.stok("sm")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("title")),
            }),
        }),
        ds.surface("slider_track", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("slider_track")), ds.fg(ds.ctok("text")), ds.border_color(ds.ctok("border_soft")), ds.accent(ds.ctok("slider_fill")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.border_color(ds.ctok("accent_dim")),
            }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, {
                ds.border_color(ds.ctok("accent_hi")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("xs")), ds.pad_v(ds.stok("xs")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("label")),
            }),
        }),
        ds.surface("slider_pan_track", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("slider_track")), ds.fg(ds.ctok("text")), ds.border_color(ds.ctok("border_soft")), ds.accent(ds.ctok("slider_pan")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.border_color(ds.ctok("accent_dim")),
            }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, {
                ds.border_color(ds.ctok("accent_hi")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("xs")), ds.pad_v(ds.stok("xs")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("label")),
            }),
        }),
        ds.surface("slider_fill", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("accent_dim")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("accent_hi")), ds.accent(ds.ctok("accent_hi")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("label")),
            }),
        }),
        ds.surface("slider_pan_fill", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("slider_pan")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("accent_hi")), ds.accent(ds.ctok("accent_hi")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("label")),
            }),
        }),
        ds.surface("slider_thumb", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("text_bright")), ds.fg(ds.ctok("panel")), ds.border_color(ds.ctok("accent_dim")),
            }),
            ds.paint_rule(ds.sel { pointer = "hovered" }, {
                ds.bg(ds.ctok("accent_hi")),
            }),
            ds.paint_rule(ds.sel { pointer = "pressed" }, {
                ds.bg(ds.ctok("accent")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("label")),
            }),
        }),
        ds.surface("status_idle", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("badge_bg")), ds.fg(ds.ctok("text_dim")), ds.border_color(ds.ctok("border_soft")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("md")), ds.pad_v(ds.stok("xs")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("label")),
            }),
        }),
        ds.surface("status_live", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("success")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("success_hi")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.pad_h(ds.stok("md")), ds.pad_v(ds.stok("xs")),
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("label")),
            }),
        }),
        ds.surface("scroll_track", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("scrollbar")), ds.fg(ds.ctok("text_dim")), ds.border_color(ds.ctok("border_soft")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("label")),
            }),
        }),
        ds.surface("scroll_thumb", {
            ds.paint_rule(ds.sel(), {
                ds.bg(ds.ctok("scrollthumb")), ds.fg(ds.ctok("text_bright")), ds.border_color(ds.ctok("border")),
            }),
        }, {
            ds.struct_rule(ds.ssel(), {
                ds.border_w(ds.stok("hair")), ds.font(ds.ftok("label")),
            }),
        }),
    },
})

local fonts

local function surface_style(name, flags, focus)
    return ds.resolve(ds.query(UI_THEME, name, focus or ds.BLURRED, flags or {}))
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
local ui_session
local input_state = {
    mouse_x = 0,
    mouse_y = 0,
    mouse_down = false,
    mouse_pressed = false,
    mouse_released = false,
}
local dragging = nil
local live_track_fields = {}
local window_width, window_height = 1100, 700
local undo_stack = {}
fonts = {}

local app = {}
local app_host = {}
local active_track_index
local meter_fill_color
local project_root_overlay
local cached_root_ui = nil
local cached_overlay_paint = nil
local cached_root_viewport_w = nil
local cached_root_viewport_h = nil
local cached_overlay_viewport_w = nil
local cached_overlay_viewport_h = nil

local function invalidate_structure()
    cached_root_ui = nil
    cached_overlay_paint = nil
end

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

local function live_track_value(track_index, field)
    local track = source_state.project.tracks[track_index]
    local live = track and live_track_fields[track.id]
    if live and live[field] ~= nil then return live[field] end
    return track and track[field] or nil
end

local function set_live_track_value(track_index, field, value)
    local track = source_state.project.tracks[track_index]
    if not track then return end
    local live = live_track_fields[track.id]
    if not live then live = {}; live_track_fields[track.id] = live end
    live[field] = value
end

local function clear_live_track_value(track_index, field)
    local track = source_state.project.tracks[track_index]
    if not track then return end
    local live = live_track_fields[track.id]
    if not live then return end
    live[field] = nil
    if next(live) == nil then live_track_fields[track.id] = nil end
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
    local payload = runtime_payload or {
        playhead_x = 0,
        transport_time_text = "00:00.000",
        transport_beat_text = "1.0",
        meter_levels = {},
    }
    runtime_payload = {
        playhead_x = fields.playhead_x ~= nil and fields.playhead_x or payload.playhead_x,
        transport_time_text = fields.transport_time_text ~= nil and fields.transport_time_text or payload.transport_time_text,
        transport_beat_text = fields.transport_beat_text ~= nil and fields.transport_beat_text or payload.transport_beat_text,
        meter_levels = fields.meter_levels ~= nil and fields.meter_levels or payload.meter_levels,
    }
end

local function set_session(fields)
    source_state = pvm2.with(source_state, { session = pvm2.with(source_state.session, fields) })
    invalidate_structure()
end

local function set_project(fields)
    source_state = pvm2.with(source_state, { project = pvm2.with(source_state.project, fields) })
    invalidate_structure()
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
        invalidate_structure()
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
        meter_values[i] = { track_id = source_state.project.tracks[i].id, level = meter_levels[i] or 0 }
    end
    local time_text, beat_text, playhead_x = runtime_time_strings(source_state.project, time_ms)
    local same = runtime_payload ~= nil
        and runtime_payload.playhead_x == playhead_x
        and runtime_payload.transport_time_text == time_text
        and runtime_payload.transport_beat_text == beat_text
        and #runtime_payload.meter_levels == #meter_values
    if same then
        for i = 1, #meter_values do
            local a, b = runtime_payload.meter_levels[i], meter_values[i]
            if not a or a.track_id ~= b.track_id or a.level ~= b.level then same = false; break end
        end
    end
    if not same then
        runtime_payload = {
            playhead_x = playhead_x,
            transport_time_text = time_text,
            transport_beat_text = beat_text,
            meter_levels = meter_values,
        }
    end
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

local function font_height(font_id)
    local f = fonts and fonts[font_id]
    if f and f.getHeight then return f:getHeight() end
    return FONT_PIXELS[font_id] or 14
end

local function center_text_y(font_id, outer_h)
    return math.max(0, math.floor((outer_h - font_height(font_id)) / 2))
end

local function line_box(font_id, width)
    return box { w = px(width), h = px(font_height(font_id)) }
end

local function framed_surface_ui(tag, surface, width, height, opts)
    opts = opts or {}
    local border_w = opts.border_w or surface.border_w or 0
    local children = {
        rect(tag or "", opts.bg or surface.bg, box { w = px(width), h = px(height) }),
    }
    if opts.left_accent and (opts.left_accent_w or 0) > 0 then
        children[#children + 1] = rect("", opts.left_accent, box { w = px(opts.left_accent_w), h = px(height) })
    end
    if border_w > 0 then
        children[#children + 1] = rect("", opts.border or surface.border, box { w = px(width), h = px(border_w) })
        children[#children + 1] = transform(0, height - border_w,
            rect("", opts.border or surface.border, box { w = px(width), h = px(border_w) }))
        children[#children + 1] = rect("", opts.border or surface.border, box { w = px(border_w), h = px(height) })
        children[#children + 1] = transform(width - border_w, 0,
            rect("", opts.border or surface.border, box { w = px(border_w), h = px(height) }))
    end
    return stack(children)
end

local function label_ui(tag, value, font_id, color, width, opts)
    opts = opts or {}
    return text(tag or "", value,
        style(font_id, color, {
            align = opts.align or ui.TEXT_START,
            overflow = opts.overflow or ui.OVERFLOW_CLIP,
            wrap = opts.wrap or ui.TEXT_NOWRAP,
        }),
        box { w = px(width), h = px(opts.height or font_height(font_id)) })
end

local function button_ui(tag, surface_name, width, height, label, opts)
    opts = opts or {}
    local surface = surface_style(surface_name, opts.flags)
    local font_id = opts.font_id or surface.font_id or 2
    local pad_x = opts.pad_x or surface.pad_h or 0
    local inner_w = math.max(0, width - pad_x * 2)
    return stack({
        framed_surface_ui(tag, surface, width, height, opts.frame),
        transform(pad_x, center_text_y(font_id, height),
            label_ui(tag, label, font_id, opts.color or surface.fg, inner_w, {
                align = opts.align or ui.TEXT_CENTER,
                overflow = opts.overflow or ui.OVERFLOW_ELLIPSIS,
                wrap = opts.wrap or ui.TEXT_NOWRAP,
            })),
    })
end

local function chip_ui(tag, surface_name, width, height, label, opts)
    opts = opts or {}
    opts.font_id = opts.font_id or 4
    return button_ui(tag, surface_name, width, height, label, opts)
end

local function kv_row(label, value, tag)
    return stack({
        label_ui("", label, 4, C.text_dim, 78, { overflow = ui.OVERFLOW_CLIP }),
        transform(88, -1, chip_ui(tag or "", "panel_chip", 156, font_height(2) + 8, value, {
            font_id = 2,
            align = ui.TEXT_START,
            pad_x = 10,
            color = surface_style("panel_chip").fg,
        })),
    })
end

local function slider_layout(width, height, kind)
    local track_surface = surface_style(kind == "pan" and "slider_pan_track" or "slider_track")
    local fill_surface = surface_style(kind == "pan" and "slider_pan_fill" or "slider_fill")
    local thumb_surface = surface_style("slider_thumb")
    local inset_x = track_surface.pad_h or 2
    local inset_y = track_surface.pad_v or 2
    local inner_w = math.max(1, width - inset_x * 2)
    local inner_h = math.max(2, height - inset_y * 2)
    return {
        track = track_surface,
        fill = fill_surface,
        thumb = thumb_surface,
        inset_x = inset_x,
        inset_y = inset_y,
        inner_w = inner_w,
        inner_h = inner_h,
        thumb_w = SLIDER_THUMB_W,
    }
end

local function slider_geometry(width, height, value, kind)
    local g = slider_layout(width, height, kind)
    local thumb_center = g.inset_x + math.floor(g.inner_w * clamp(value, 0, 1) + 0.5)
    local thumb_x = clamp(thumb_center - math.floor(g.thumb_w / 2), g.inset_x, g.inset_x + g.inner_w - g.thumb_w)
    local fill_x, fill_w = g.inset_x, math.max(0, math.floor(g.inner_w * clamp(value, 0, 1) + 0.5))
    if kind == "pan" then
        local center_x = g.inset_x + math.floor(g.inner_w / 2)
        local pan = clamp((value - 0.5) * 2, -1, 1)
        if pan < 0 then
            fill_w = math.max(0, math.floor((-pan) * (g.inner_w / 2) + 0.5))
            fill_x = center_x - fill_w
        elseif pan > 0 then
            fill_w = math.max(0, math.floor(pan * (g.inner_w / 2) + 0.5))
            fill_x = center_x
        else
            fill_w = 0
            fill_x = center_x
        end
    end
    return {
        fill_x = fill_x,
        fill_w = fill_w,
        fill_y = g.inset_y,
        fill_h = g.inner_h,
        thumb_x = thumb_x,
        thumb_w = g.thumb_w,
        thumb_h = height,
    }, g
end

local function slider_shell_ui(tag, width, height, kind)
    local g = slider_layout(width, height, kind)
    local children = {
        framed_surface_ui(tag, g.track, width, height),
    }
    if kind == "pan" then
        local center_x = g.inset_x + math.floor(g.inner_w / 2)
        children[#children + 1] = transform(center_x, 1,
            rect("", g.track.border, box { w = px(1), h = px(math.max(0, height - 2)) }))
    end
    return stack(children)
end

local function slider_ui(tag, width, height, value, kind)
    local geom, g = slider_geometry(width, height, value, kind)
    local children = {
        slider_shell_ui(tag, width, height, kind),
    }
    if geom.fill_w > 0 then
        children[#children + 1] = transform(geom.fill_x, geom.fill_y,
            rect("", g.fill.bg, box { w = px(geom.fill_w), h = px(geom.fill_h) }))
    end
    children[#children + 1] = transform(geom.thumb_x, 0,
        framed_surface_ui("", g.thumb, g.thumb_w, height))
    return stack(children)
end

local function header_fragment_ui(track_count)
    local shell = surface_style("panel_shell")
    return stack({
        framed_surface_ui("", shell, TRACK_PANEL_WIDTH, HEADER_HEIGHT),
        transform(14, center_text_y(3, HEADER_HEIGHT),
            label_ui("", "Tracks", 3, C.text_bright, 90)),
        transform(TRACK_PANEL_WIDTH - 50, center_text_y(4, HEADER_HEIGHT),
            chip_ui("", "panel_chip", 36, font_height(4) + 8, tostring(track_count))),
    })
end

local function pan_readout(value)
    local pan = math.floor(math.abs(value - 0.5) * 200 + 0.5)
    if pan == 0 then return "C" end
    return (value < 0.5 and "L" or "R") .. tostring(pan)
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
        framed_surface_ui("", surface_style("scroll_track"), 8, visible_height),
        transform(0, thumb_y, framed_surface_ui("", surface_style("scroll_thumb"), 8, thumb_height)),
    })
end

local function track_row_fragment_ui(self)
    local track = self.track
    local tag = "track:" .. self.track_index
    local row_style = surface_style(
        self.is_selected and "track_row_selected" or ((self.track_index % 2 == 0) and "track_row_even" or "track_row_odd"))
    local layout = track_row_layout(TRACK_PANEL_WIDTH)
    local status_text = track.mute and "Muted" or (track.solo and "Solo" or (self.is_selected and "Selected" or "Ready"))
    local meta_text = string.format("VOL %02d%%  ·  PAN %s  ·  %s", math.floor(track.vol * 100 + 0.5), pan_readout(track.pan), status_text)
    local meter_box_h = ROW_HEIGHT - 8
    return stack({
        framed_surface_ui(tag, row_style, TRACK_PANEL_WIDTH, ROW_HEIGHT, {
            left_accent = track.color,
            left_accent_w = 4,
        }),
        transform(layout.name_x, 8,
            label_ui(tag, track.name, 2, row_style.fg, layout.name_w, {
                overflow = ui.OVERFLOW_ELLIPSIS,
            })),
        transform(layout.name_x, 24,
            label_ui("", meta_text, 4, C.text_dim, layout.name_w, {
                overflow = ui.OVERFLOW_ELLIPSIS,
            })),
        transform(layout.mute_x, 14,
            button_ui(tag .. ":mute", "mute_button", TRACK_ROW_BUTTON_W, TRACK_ROW_BUTTON_H, "M", {
                flags = active_flags(track.mute),
                font_id = 4,
            })),
        transform(layout.solo_x, 14,
            button_ui(tag .. ":solo", "solo_button", TRACK_ROW_BUTTON_W, TRACK_ROW_BUTTON_H, "S", {
                flags = active_flags(track.solo),
                font_id = 4,
            })),
        transform(layout.slider_x, 8, slider_shell_ui(tag .. ":vol", layout.slider_w, TRACK_ROW_SLIDER_H, "vol")),
        transform(layout.slider_x, 30, slider_shell_ui(tag .. ":pan", layout.slider_w, TRACK_ROW_SLIDER_H, "pan")),
        transform(layout.meter_x, 4,
            framed_surface_ui("", surface_style("panel_chip"), METER_WIDTH, meter_box_h, {
                bg = C.meter_bg,
                border = C.border_soft,
            })),
    })
end

local function clip_fragment_ui(self)
    local clip_value = self.clip
    local width = math.floor(from_q16(clip_value.dur_q16) * PIXELS_PER_BEAT)
    local height = ROW_HEIGHT - 8
    local meta = string.format("%.1fb", from_q16(clip_value.dur_q16))
    local bg = self.is_selected and C.accent_dim or clip_value.color
    local border = self.is_selected and C.accent_hi or C.border_soft
    local children = {
        framed_surface_ui("clip:" .. clip_value.id, surface_style("panel_card"), width, height, {
            bg = bg,
            border = border,
            left_accent = self.is_selected and C.text_bright or C.overlay,
            left_accent_w = 3,
        }),
        transform(8, 5,
            label_ui("", clip_value.label, 4, C.text_bright, math.max(0, width - 16), {
                overflow = ui.OVERFLOW_ELLIPSIS,
            })),
    }
    if width >= 72 then
        children[#children + 1] = transform(8, 20,
            label_ui("", meta, 4, C.text_soft, math.max(0, width - 16), {
                overflow = ui.OVERFLOW_CLIP,
            }))
    end
    return stack(children)
end

local function arrangement_background_fragment_ui(self)
    local grid, ruler, lane_backgrounds = {}, {}, {}
    local visible_width = self.visible_width
    local visible_height = self.visible_height
    local visible_beats = math.floor(visible_width / PIXELS_PER_BEAT) + 4
    for i = 1, self.track_count do
        local y = (i - 1) * ROW_HEIGHT - self.scroll_y
        lane_backgrounds[#lane_backgrounds + 1] = transform(0, y, stack({
            rect("", (i % 2 == 0) and C.row_even or C.row_odd, box { w = px(visible_width), h = px(ROW_HEIGHT) }),
            transform(0, ROW_HEIGHT - 1, rect("", C.border_soft, box { w = px(visible_width), h = px(1) })),
        }))
    end
    for beat_index = 0, visible_beats do
        local x = beat_index * PIXELS_PER_BEAT
        local major = (beat_index % 4 == 0)
        local grid_color = major and C.border_strong or C.border_soft
        grid[#grid + 1] = transform(x, 0,
            rect("", grid_color,
                box { w = px(1), h = px(visible_height) }))
        if major then
            ruler[#ruler + 1] = transform(x + 6, 9,
                label_ui("", tostring(math.floor(beat_index / 4) + 1), 4, C.text_dim, 22))
        end
        ruler[#ruler + 1] = transform(x, 0,
            rect("", grid_color,
                box { w = px(1), h = px(major and HEADER_HEIGHT or 12) }))
    end
    return stack({
        rect("", C.bg, box { w = px(visible_width), h = px(self.playhead_height) }),
        clip(stack(lane_backgrounds)),
        stack({
            framed_surface_ui("", surface_style("panel_shell"), visible_width, HEADER_HEIGHT, {
                bg = C.panel_alt,
                border = C.border_soft,
            }),
            clip(stack(ruler)),
        }),
        transform(0, HEADER_HEIGHT, clip(stack(grid))),
    })
end

local function track_inspector_fragment_ui(self)
    local track = self.track
    local h = self.panel_height
    local card_w = INSPECTOR_WIDTH - 32
    return stack({
        framed_surface_ui("", surface_style("panel_shell"), INSPECTOR_WIDTH, h, {
            bg = C.panel,
            border = C.border_soft,
        }),
        transform(16, 16, label_ui("", "Track Inspector", 3, C.text_bright, card_w)),
        transform(16, 48, chip_ui("", "panel_chip", 68, font_height(4) + 8, "TRACK " .. self.track_index)),

        transform(16, 82, framed_surface_ui("", surface_style("panel_card"), card_w, 144)),
        transform(28, 96, label_ui("", track.name, 2, C.text_bright, card_w - 56, { overflow = ui.OVERFLOW_ELLIPSIS })),
        transform(card_w - 12, 96, framed_surface_ui("", surface_style("panel_chip"), 24, 24, {
            bg = track.color,
            border = C.border_strong,
        })),
        transform(28, 120, label_ui("", string.format("Volume %.0f%%  ·  Pan %s", track.vol * 100, pan_readout(track.pan)), 4, C.text_dim, card_w - 24, {
            overflow = ui.OVERFLOW_ELLIPSIS,
        })),
        transform(28, 144, stack({
            kv_row("Track", track.name, "inspector:name"),
            transform(0, 24, kv_row("Mute", track.mute and "Armed" or "Off", "inspector:mute")),
            transform(0, 48, kv_row("Solo", track.solo and "Focused" or "Off", "inspector:solo")),
            transform(0, 72, kv_row("State", track.mute and "Muted" or (track.solo and "Solo" or "Ready"), "inspector:state")),
        })),

        transform(16, 244, framed_surface_ui("", surface_style("panel_card"), card_w, 120)),
        transform(28, 258, label_ui("", "Volume", 4, C.text_dim, 64)),
        transform(28, 280, slider_shell_ui("insp:vol_slider", card_w - 24, INSPECTOR_SLIDER_H, "vol")),
        transform(28, 308, label_ui("", "Pan", 4, C.text_dim, 64)),
        transform(28, 330, slider_shell_ui("insp:pan_slider", card_w - 24, INSPECTOR_SLIDER_H, "pan")),

        transform(16, 384, button_ui("insp:mute_btn", "mute_button", 92, 30,
            track.mute and "Muted" or "Mute", {
                flags = active_flags(track.mute),
                font_id = 2,
            })),
        transform(118, 384, button_ui("insp:solo_btn", "solo_button", 92, 30,
            track.solo and "Solo'd" or "Solo", {
                flags = active_flags(track.solo),
                font_id = 2,
            })),
        transform(16, 428, label_ui("", "This inspector is immediate: drag controls update live without recompiling a retained UI image.", 4, C.text_faint, card_w, {
            wrap = ui.TEXT_WORDWRAP,
            overflow = ui.OVERFLOW_CLIP,
            height = 42,
        })),
    })
end

local function clip_inspector_fragment_ui(self)
    local h = self.panel_height
    local card_w = INSPECTOR_WIDTH - 32
    local clip_w_beats = from_q16(self.clip.dur_q16)
    return stack({
        framed_surface_ui("", surface_style("panel_shell"), INSPECTOR_WIDTH, h, {
            bg = C.panel,
            border = C.border_soft,
        }),
        transform(16, 16, label_ui("", "Clip Inspector", 3, C.text_bright, card_w)),
        transform(16, 48, chip_ui("", "panel_chip", 60, font_height(4) + 8, "CLIP")),

        transform(16, 82, framed_surface_ui("", surface_style("panel_card"), card_w, 116)),
        transform(28, 96, label_ui("", self.clip.label, 2, C.text_bright, card_w - 24, { overflow = ui.OVERFLOW_ELLIPSIS })),
        transform(28, 122, stack({
            kv_row("Track", self.track.name, "inspector:track"),
            transform(0, 24, kv_row("Start", string.format("%.1f beats", from_q16(self.clip.beat_q16)), "inspector:start")),
            transform(0, 48, kv_row("Length", string.format("%.1f beats", clip_w_beats), "inspector:length")),
        })),

        transform(16, 220, framed_surface_ui("", surface_style("panel_card"), card_w, 92)),
        transform(28, 236, label_ui("", "Projection note", 4, C.text_dim, card_w - 24)),
        transform(28, 258, label_ui("",
            "This clip is projected from the same source object into both the arrangement lane and this inspector card.",
            4, C.text_soft, card_w - 24, {
                wrap = ui.TEXT_WORDWRAP,
                overflow = ui.OVERFLOW_CLIP,
                height = 42,
            })),
    })
end

local function transport_fragment_ui(self)
    local play_label = self.is_playing and "||" or ">"
    local layout = transport_layout(self.panel_width)
    local bpm_value_w = math.max(24, layout.bpm_w - (TRANSPORT_SMALL_BUTTON_W * 2 + 4))
    local status_surface = self.is_playing and "status_live" or "status_idle"
    local readout = surface_style("readout")
    return stack({
        framed_surface_ui("", surface_style("panel_shell"), self.panel_width, TRANSPORT_HEIGHT, {
            bg = C.transport_bg,
            border = C.border_soft,
        }),
        transform(layout.play_x, 10,
            button_ui("transport:play", "transport_play", TRANSPORT_MAIN_BUTTON_W, 32, play_label, {
                flags = active_flags(self.is_playing),
                font_id = 3,
            })),
        transform(layout.stop_x, 10,
            button_ui("transport:stop", "transport_button", TRANSPORT_MAIN_BUTTON_W, 32, "[]", {
                font_id = 3,
            })),
        transform(layout.controls_end + 18, 8, rect("", C.border_soft, box { w = px(1), h = px(36) })),

        transform(layout.time_x, 7, label_ui("", "TIME", 4, C.text_dim, math.max(24, layout.time_w))),
        transform(layout.time_x, 22, framed_surface_ui("", readout, layout.time_w, 20)),

        transform(layout.beat_x, 7, label_ui("", "BEAT", 4, C.text_dim, math.max(24, layout.beat_w))),
        transform(layout.beat_x, 22, framed_surface_ui("", readout, layout.beat_w, 20)),

        transform(layout.bpm_x, 7, label_ui("", "BPM", 4, C.text_dim, layout.bpm_w)),
        transform(layout.bpm_x, 23,
            button_ui("transport:bpm-", "button", TRANSPORT_SMALL_BUTTON_W, 20, "-", {
                font_id = 4,
            })),
        transform(layout.bpm_x + TRANSPORT_SMALL_BUTTON_W + 2, 22,
            framed_surface_ui("", readout, bpm_value_w, 20)),
        transform(layout.bpm_x + TRANSPORT_SMALL_BUTTON_W + 2, 22 + center_text_y(3, 20),
            label_ui("", tostring(self.bpm), 3, C.accent_hi, bpm_value_w, {
                align = ui.TEXT_CENTER,
            })),
        transform(layout.bpm_x + layout.bpm_w - TRANSPORT_SMALL_BUTTON_W, 23,
            button_ui("transport:bpm+", "button", TRANSPORT_SMALL_BUTTON_W, 20, "+", {
                font_id = 4,
            })),

        transform(layout.status_x, 17,
            chip_ui("", status_surface, layout.status_w, 20,
                self.is_playing and "LIVE" or "STOPPED", {
                    align = ui.TEXT_CENTER,
                })),
    })
end

local function track_panel_ui(self)
    return stack({
        header_fragment_ui(self.track_count),
        transform(0, HEADER_HEIGHT,
            rect("", C.bg, box { w = px(TRACK_PANEL_WIDTH), h = px(self.visible_height) })),
        transform(0, HEADER_HEIGHT,
            clip(
                transform(0, -self.scroll_y,
                    stack(ui.each(iter.from(self.track_row_views), function(row_view)
                        return transform(0, (row_view.track_index - 1) * ROW_HEIGHT, track_row_fragment_ui(row_view))
                    end))),
                box { w = px(TRACK_PANEL_WIDTH), h = px(self.visible_height) })),
        transform(TRACK_PANEL_WIDTH - 8, HEADER_HEIGHT,
            scrollbar_fragment_ui(self.track_count, self.visible_height, self.scroll_y)),
    }, box { w = px(TRACK_PANEL_WIDTH), h = px(HEADER_HEIGHT + self.visible_height) })
end

local function arrangement_panel_ui(self)
    return stack({
        arrangement_background_fragment_ui(self),
        transform(0, HEADER_HEIGHT,
            clip(
                stack(ui.each(iter.from(self.clip_views), function(clip_view)
                    local x = math.floor(from_q16(clip_view.clip.beat_q16) * PIXELS_PER_BEAT)
                    local y = (clip_view.track_index - 1) * ROW_HEIGHT - self.scroll_y + 4
                    return transform(x, y, clip_fragment_ui(clip_view))
                end)),
                box { w = px(self.visible_width), h = px(self.visible_height) })),
    }, box { w = px(self.visible_width), h = px(self.playhead_height) })
end

local function inspector_panel_ui(self)
    local mt = getmetatable(self)
    if mt == TrackInspectorView then return track_inspector_fragment_ui(self) end
    return clip_inspector_fragment_ui(self)
end

local function transport_panel_ui(self)
    return transport_fragment_ui(self)
end

local function root_view_ui(self)
    return stack({
        track_panel_ui(self.track_panel),
        transform(TRACK_PANEL_WIDTH, 0, arrangement_panel_ui(self.arrangement_panel)),
        transform(TRACK_PANEL_WIDTH + self.arrangement_panel.visible_width, 0, inspector_panel_ui(self.inspector_panel)),
        transform(0, self.arrangement_panel.playhead_height, transport_panel_ui(self.transport_panel)),
    }, box { w = px(window_width), h = px(window_height) })
end

local function current_root_ui()
    if cached_root_ui and cached_root_viewport_w == window_width and cached_root_viewport_h == window_height then
        return cached_root_ui
    end
    cached_root_ui = root_view_ui(project_root_view(source_state, viewport_value()))
    cached_root_viewport_w, cached_root_viewport_h = window_width, window_height
    return cached_root_ui
end

local function current_overlay_paint()
    if cached_overlay_paint and cached_overlay_viewport_w == window_width and cached_overlay_viewport_h == window_height then
        return cached_overlay_paint
    end
    cached_overlay_paint = project_root_overlay(source_state, viewport_value())
    cached_overlay_viewport_w, cached_overlay_viewport_h = window_width, window_height
    return cached_overlay_paint
end

-- ══════════════════════════════════════════════════════════════
--  LEGACY RETAINED-PATH HELPERS (unused by ui7 immediate runtime)
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
--  IMMEDIATE RUNTIME PAINT OVERLAY HELPERS
-- ══════════════════════════════════════════════════════════════

local PLAYHEAD_X_REF = ui.num_ref("playhead_x")
local TIME_TEXT_REF = ui.text_ref("transport_time")
local BEAT_TEXT_REF = ui.text_ref("transport_beat")
local INSP_VOL_TEXT_REF = ui.text_ref("insp:vol_text")
local INSP_PAN_TEXT_REF = ui.text_ref("insp:pan_text")

local function meter_y_ref(track_id)
    return ui.num_ref("meter:" .. track_id .. ":y")
end

local function meter_h_ref(track_id)
    return ui.num_ref("meter:" .. track_id .. ":h")
end

local function meter_color_ref(track_id)
    return ui.color_ref("meter:" .. track_id .. ":color")
end

local function slider_fill_x_ref(scope, field)
    return ui.num_ref(scope .. ":" .. field .. ":fill_x")
end

local function slider_fill_w_ref(scope, field)
    return ui.num_ref(scope .. ":" .. field .. ":fill_w")
end

local function slider_thumb_x_ref(scope, field)
    return ui.num_ref(scope .. ":" .. field .. ":thumb_x")
end

local function slider_overlay(scope, field, tag, width, height, kind)
    local g = slider_layout(width, height, kind)
    return ui.paint_group({
        ui.paint_rect(tag,
            slider_fill_x_ref(scope, field), g.inset_y,
            slider_fill_w_ref(scope, field), g.inner_h,
            g.fill.bg),
        ui.paint_rect(tag,
            slider_thumb_x_ref(scope, field), 0,
            g.thumb_w, height,
            g.thumb.bg),
    })
end

project_root_overlay = function(state, viewport)
    local vm = view_metrics(state, viewport)
    local meter_children = {}
    local track_slider_children = {}
    local meter_layout = track_row_layout(TRACK_PANEL_WIDTH)
    for i = 1, #state.project.tracks do
        local track = state.project.tracks[i]
        meter_children[i] = ui.paint_rect("meter:" .. track.id,
            meter_layout.meter_x,
            meter_y_ref(track.id),
            METER_WIDTH,
            meter_h_ref(track.id),
            meter_color_ref(track.id))
        local row_y = HEADER_HEIGHT + (i - 1) * ROW_HEIGHT - vm.scroll_y
        track_slider_children[#track_slider_children + 1] = ui.paint_transform(meter_layout.slider_x, row_y + 8,
            slider_overlay("track:" .. track.id, "vol", "track:" .. i .. ":vol", meter_layout.slider_w, TRACK_ROW_SLIDER_H, "vol"))
        track_slider_children[#track_slider_children + 1] = ui.paint_transform(meter_layout.slider_x, row_y + 30,
            slider_overlay("track:" .. track.id, "pan", "track:" .. i .. ":pan", meter_layout.slider_w, TRACK_ROW_SLIDER_H, "pan"))
    end

    local inspector_overlay = nil
    if not selected_clip(state) then
        local inspector_x = TRACK_PANEL_WIDTH + vm.arrangement_width
        local inspector_slider_w = INSPECTOR_WIDTH - 56
        inspector_overlay = ui.paint_transform(inspector_x, 0,
            ui.paint_group({
                ui.paint_transform(104, 258,
                    ui.paint_text("insp:vol_value", 0, 0, 180, font_height(2),
                        style(2, C.accent_hi, { overflow = ui.OVERFLOW_CLIP }),
                        INSP_VOL_TEXT_REF)),
                ui.paint_transform(28, 280,
                    slider_overlay("insp", "vol", "insp:vol_slider", inspector_slider_w, INSPECTOR_SLIDER_H, "vol")),
                ui.paint_transform(104, 308,
                    ui.paint_text("insp:pan_value", 0, 0, 180, font_height(2),
                        style(2, C.purple, { overflow = ui.OVERFLOW_CLIP }),
                        INSP_PAN_TEXT_REF)),
                ui.paint_transform(28, 330,
                    slider_overlay("insp", "pan", "insp:pan_slider", inspector_slider_w, INSPECTOR_SLIDER_H, "pan")),
            }))
    end

    local transport = transport_layout(viewport.window_width)
    local readout = surface_style("readout")
    local readout_pad = readout.pad_h or 8
    local readout_h = font_height(3)

    local children = {
        ui.paint_clip(0, HEADER_HEIGHT, TRACK_PANEL_WIDTH, vm.visible_height,
            ui.paint_group(meter_children)),
        ui.paint_clip(0, HEADER_HEIGHT, TRACK_PANEL_WIDTH, vm.visible_height,
            ui.paint_group(track_slider_children)),
        ui.paint_transform(TRACK_PANEL_WIDTH, 0,
            ui.paint_line("playhead",
                PLAYHEAD_X_REF, 0,
                PLAYHEAD_X_REF, viewport.window_height - TRANSPORT_HEIGHT,
                2, C.accent_hi)),
        ui.paint_transform(0, viewport.window_height - TRANSPORT_HEIGHT,
            ui.paint_group({
                ui.paint_text("transport:time",
                    transport.time_x + readout_pad, 24, math.max(0, transport.time_w - readout_pad * 2), readout_h,
                    style(3, C.text_bright, { overflow = ui.OVERFLOW_CLIP }),
                    TIME_TEXT_REF),
                ui.paint_text("transport:beat",
                    transport.beat_x + readout_pad, 24, math.max(0, transport.beat_w - readout_pad * 2), readout_h,
                    style(3, C.text_bright, { overflow = ui.OVERFLOW_CLIP }),
                    BEAT_TEXT_REF),
            })),
    }
    if inspector_overlay then children[#children + 1] = inspector_overlay end
    return ui.paint_group(children)
end

meter_fill_color = function(level)
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
    local meter_layout = track_row_layout(TRACK_PANEL_WIDTH)

    for i = 1, #source_state.project.tracks do
        local track = source_state.project.tracks[i]
        local level = clamp(lookup_meter_level(payload, track.id), 0, 1)
        local fill = math.floor(meter_h * level)
        numbers["meter:" .. track.id .. ":h"] = fill
        numbers["meter:" .. track.id .. ":y"] = HEADER_HEIGHT + (i - 1) * ROW_HEIGHT - vm.scroll_y + 4 + (meter_h - fill)
        colors["meter:" .. track.id .. ":color"] = meter_fill_color(level)

        local vol_geom = slider_geometry(meter_layout.slider_w, TRACK_ROW_SLIDER_H, live_track_value(i, "vol"), "vol")
        numbers["track:" .. track.id .. ":vol:fill_x"] = vol_geom.fill_x
        numbers["track:" .. track.id .. ":vol:fill_w"] = vol_geom.fill_w
        numbers["track:" .. track.id .. ":vol:thumb_x"] = vol_geom.thumb_x

        local pan_geom = slider_geometry(meter_layout.slider_w, TRACK_ROW_SLIDER_H, live_track_value(i, "pan"), "pan")
        numbers["track:" .. track.id .. ":pan:fill_x"] = pan_geom.fill_x
        numbers["track:" .. track.id .. ":pan:fill_w"] = pan_geom.fill_w
        numbers["track:" .. track.id .. ":pan:thumb_x"] = pan_geom.thumb_x
    end

    local current_track_index = active_track_index()
    local current_track = source_state.project.tracks[current_track_index]
    if current_track then
        local inspector_slider_w = INSPECTOR_WIDTH - 56
        local vol_value = live_track_value(current_track_index, "vol")
        local pan_value = live_track_value(current_track_index, "pan")
        local insp_vol_geom = slider_geometry(inspector_slider_w, INSPECTOR_SLIDER_H, vol_value, "vol")
        local insp_pan_geom = slider_geometry(inspector_slider_w, INSPECTOR_SLIDER_H, pan_value, "pan")
        numbers["insp:vol:fill_x"] = insp_vol_geom.fill_x
        numbers["insp:vol:fill_w"] = insp_vol_geom.fill_w
        numbers["insp:vol:thumb_x"] = insp_vol_geom.thumb_x
        numbers["insp:pan:fill_x"] = insp_pan_geom.fill_x
        numbers["insp:pan:fill_w"] = insp_pan_geom.fill_w
        numbers["insp:pan:thumb_x"] = insp_pan_geom.thumb_x
        texts["insp:vol_text"] = string.format("Volume %.0f%%", vol_value * 100)
        texts["insp:pan_text"] = "Pan " .. pan_readout(pan_value)
    else
        numbers["insp:vol:fill_x"] = 0
        numbers["insp:vol:fill_w"] = 0
        numbers["insp:vol:thumb_x"] = 0
        numbers["insp:pan:fill_x"] = 0
        numbers["insp:pan:fill_w"] = 0
        numbers["insp:pan:thumb_x"] = 0
        texts["insp:vol_text"] = ""
        texts["insp:pan_text"] = ""
    end

    return {
        numbers = numbers,
        texts = texts,
        colors = colors,
    }
end

local function current_runtime_env()
    return build_overlay_runtime(runtime_payload or {
        playhead_x = 0,
        transport_time_text = "00:00.000",
        transport_beat_text = "1.0",
        meter_levels = {},
    })
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
    invalidate_structure()
end

active_track_index = function()
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
    if not tag then return false end

    local clip_id = tonumber(tag:match("^clip:(%d+)"))
    if clip_id then
        local current_clip = selected_clip(source_state)
        if not current_clip or current_clip.id ~= clip_id then
            dispatch(0, "selection", SelectedClip(clip_id))
            return true
        end
        return false
    end

    local track_index = tonumber(tag:match("^track:(%d+)"))
    if track_index then
        local needs_recompile = false
        local selected_id = selected_track_id(source_state)
        local track_id = source_state.project.tracks[track_index].id
        if selected_id ~= track_id or selected_clip(source_state) then
            dispatch(0, "selection", SelectedTrack(track_id))
            needs_recompile = true
        end
        if tag:find(":mute", 1, true) then
            dispatch(track_index, "mute", not source_state.project.tracks[track_index].mute)
            return true
        elseif tag:find(":solo", 1, true) then
            dispatch(track_index, "solo", not source_state.project.tracks[track_index].solo)
            return true
        elseif tag:find(":vol", 1, true) then
            dragging = { tag = tag, track_index = track_index, field = "vol", x0 = mouse_x, value0 = live_track_value(track_index, "vol"), width = track_row_layout(TRACK_PANEL_WIDTH).slider_w }
            return needs_recompile
        elseif tag:find(":pan", 1, true) then
            dragging = { tag = tag, track_index = track_index, field = "pan", x0 = mouse_x, value0 = live_track_value(track_index, "pan"), width = track_row_layout(TRACK_PANEL_WIDTH).slider_w }
            return needs_recompile
        end
        return needs_recompile
    end

    local current_track_index = active_track_index()
    if tag:find("^insp:vol_slider") then
        dragging = { tag = tag, track_index = current_track_index, field = "vol", x0 = mouse_x, value0 = live_track_value(current_track_index, "vol"), width = INSPECTOR_WIDTH - 56 }
        return false
    end
    if tag:find("^insp:pan_slider") then
        dragging = { tag = tag, track_index = current_track_index, field = "pan", x0 = mouse_x, value0 = live_track_value(current_track_index, "pan"), width = INSPECTOR_WIDTH - 56 }
        return false
    end
    if tag:find("^insp:mute_btn") then dispatch(current_track_index, "mute", not source_state.project.tracks[current_track_index].mute); return true end
    if tag:find("^insp:solo_btn") then dispatch(current_track_index, "solo", not source_state.project.tracks[current_track_index].solo); return true end
    if tag:find("^transport:play") then set_session({ playing = not source_state.session.playing }); return true end
    if tag:find("^transport:stop") then set_session({ playing = false }); rebuild_runtime_payload(0, zero_meter_levels()); return true end
    if tag:find("^transport:bpm%-") then dispatch(0, "bpm", math.max(40, source_state.project.bpm - 5)); return true end
    if tag:find("^transport:bpm%+") then dispatch(0, "bpm", math.min(300, source_state.project.bpm + 5)); return true end
    return false
end

-- ══════════════════════════════════════════════════════════════
--  APP ENTRYPOINT
-- ══════════════════════════════════════════════════════════════

function app.init(host)
    app_host = host or {}
    ui.set_backend(app_host.renderer)
    ui_session = ui.session({ backend = app_host.renderer, state = ui.state() })

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
            target = (0.3 + 0.5 * math.abs(math.sin(time_sec * (1.5 + i * 0.3) + i * 0.7))) * live_track_value(i, "vol")
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
        input_state.mouse_x = mx
        input_state.mouse_y = my
        input_state.mouse_down = true
        input_state.mouse_pressed = true
    end
end

function app.mousereleased()
    input_state.mouse_down = false
    input_state.mouse_released = true
    if dragging then
        local committed_value = live_track_value(dragging.track_index, dragging.field)
        clear_live_track_value(dragging.track_index, dragging.field)
        if committed_value ~= nil and committed_value ~= source_state.project.tracks[dragging.track_index][dragging.field] then
            dispatch(dragging.track_index, dragging.field, committed_value)
        end
        dragging = nil
    end
    if ui_session then ui_session:get_state().dragging = nil end
end

function app.mousemoved(mx, my)
    input_state.mouse_x = mx
    input_state.mouse_y = my
    if dragging then
        local next_value = clamp(dragging.value0 + (mx - dragging.x0) / dragging.width, 0, 1)
        set_live_track_value(dragging.track_index, dragging.field, next_value)
    end
end

function app.wheelmoved(_, wy)
    local visible_height = window_height - TRANSPORT_HEIGHT - HEADER_HEIGHT
    local max_scroll = math.max(0, #source_state.project.tracks * ROW_HEIGHT - visible_height)
    dispatch(0, "scroll_y", clamp(source_state.session.scroll_y - wy * 30, 0, max_scroll))
    recompile_static()
end

function app.draw()
    local frame = ui.frame(0, 0, window_width, window_height)
    local runtime = current_runtime_env()

    ui_session:set_backend(app_host.renderer)
    local state = select(1, ui_session:frame(current_root_ui(), {
        frame = frame,
        input = input_state,
        env = runtime,
        backend = app_host.renderer,
        draw = false,
    }))

    if input_state.mouse_pressed and state.active then
        if handle_click(state.active, input_state.mouse_x) then recompile_static() end
        state = ui_session:get_state()
    end

    state.dragging = dragging and dragging.tag or nil

    ui_session:draw(current_root_ui(), {
        frame = frame,
        env = runtime,
        backend = app_host.renderer,
    })
    ui_session:draw_paint(current_overlay_paint(), runtime, {
        backend = app_host.renderer,
    })

    input_state.mouse_pressed = false
    input_state.mouse_released = false
end

return app
