-- ui/demo/app.lua
-- DAW-style mock demo for the fresh UI stack.
--
-- This is a mock UI, not a real DAW. The main goal is to look and feel like a
-- modern DAW shell while still surfacing the core idea:
--
--   structural edits rebuild the compiled machine
--   live control edits mutate runtime state only

local pvm = require("pvm")
local ui = require("ui.init")
local demo_schema = require("ui.demo.asdl")

local T = ui.T
local D = demo_schema.T.Demo
local ds = ui.ds
local lower = ui.lower

local Phase = D.Phase
local Clip = D.Clip
local Device = D.Device
local Track = D.Track
local State = D.State

local M = {
    ui = ui,
    T = T,
    D = D,
    ds = ds,
    lower = lower,
    schema = demo_schema,
}

local math_abs = math.abs
local math_cos = math.cos
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_sin = math.sin
local string_format = string.format
local string_upper = string.upper
local table_concat = table.concat
local type = type

-- ─────────────────────────────────────────────────────────────
-- Theme
-- ─────────────────────────────────────────────────────────────

local C = {
    crust = 0x11131aff,
    mantle = 0x171a22ff,
    base = 0x1d222dff,
    surface0 = 0x2a303dff,
    surface1 = 0x394255ff,
    overlay0 = 0x77819bff,
    text = 0xd6dceaff,
    subtext0 = 0xa4aec9ff,
    blue = 0x76a9ffff,
    green = 0x79d2a6ff,
    red = 0xff7f8eff,
    yellow = 0xffd36aff,
    mauve = 0xc89dffff,
    teal = 0x6ed9e2ff,
    orange = 0xffaa66ff,
}

local FONT_HEIGHTS = { [1] = 12, [2] = 14, [3] = 16, [4] = 13 }
function M.font_sizes() return FONT_HEIGHTS end
function M.font_height(id) return FONT_HEIGHTS[id] or 14 end

local ACTIVE = ds.flag("active")
local function flags_active(active)
    return active and { ACTIVE } or {}
end

local THEME = ds.theme("daw_mock", {
    colors = {
        { "crust", C.crust }, { "mantle", C.mantle }, { "base", C.base },
        { "surface0", C.surface0 }, { "surface1", C.surface1 },
        { "overlay", C.overlay0 }, { "text", C.text }, { "subtext", C.subtext0 },
        { "blue", C.blue }, { "green", C.green }, { "red", C.red },
        { "yellow", C.yellow }, { "mauve", C.mauve }, { "teal", C.teal },
        { "orange", C.orange },
    },
    spaces = {
        { "xs", 4 }, { "sm", 8 }, { "md", 12 }, { "lg", 16 }, { "bw", 1 },
    },
    fonts = {
        { "ui_sm", 1 }, { "ui_md", 2 }, { "ui_lg", 3 }, { "mono", 4 },
    },
    surfaces = {
        ds.surface("window", {
            ds.paint_rule(ds.paint_sel(), { ds.bg(ds.ctok("crust")), ds.fg(ds.ctok("text")) }),
        }, {}, {
            ds.text_rule(ds.state_sel(), {
                ds.font(ds.ftok("ui_md")),
                ds.line_height(T.Layout.LineHeightPx(18)),
                ds.text_wrap(T.Layout.TextWordWrap),
            })
        }),

        ds.surface("transport", {
            ds.paint_rule(ds.paint_sel(), { ds.bg(ds.ctok("mantle")), ds.fg(ds.ctok("text")), ds.border_color(ds.ctok("surface0")) }),
        }, {
            ds.metric_rule(ds.state_sel(), { ds.border_w(ds.stok("bw")), ds.pad_h(ds.stok("sm")), ds.pad_v(ds.stok("sm")) })
        }, {
            ds.text_rule(ds.state_sel(), { ds.font(ds.ftok("ui_md")), ds.text_wrap(T.Layout.TextNoWrap) })
        }),

        ds.surface("panel", {
            ds.paint_rule(ds.paint_sel(), { ds.bg(ds.ctok("mantle")), ds.fg(ds.ctok("text")), ds.border_color(ds.ctok("surface0")) }),
        }, {
            ds.metric_rule(ds.state_sel(), { ds.border_w(ds.stok("bw")) })
        }, {
            ds.text_rule(ds.state_sel(), {
                ds.font(ds.ftok("ui_sm")),
                ds.line_height(T.Layout.LineHeightPx(18)),
                ds.text_wrap(T.Layout.TextWordWrap),
            })
        }),

        ds.surface("button", {
            ds.paint_rule(ds.paint_sel(), { ds.bg(ds.ctok("base")), ds.fg(ds.ctok("subtext")), ds.border_color(ds.ctok("surface0")) }),
            ds.paint_rule(ds.paint_sel({ pointer = "hovered" }), { ds.bg(ds.ctok("surface0")), ds.fg(ds.ctok("text")) }),
            ds.paint_rule(ds.paint_sel({ flags = { "active" } }), { ds.bg(ds.ctok("surface1")), ds.fg(ds.ctok("blue")), ds.border_color(ds.ctok("blue")) }),
            ds.paint_rule(ds.paint_sel({ focus = "focused" }), { ds.border_color(ds.ctok("mauve")) }),
        }, {
            ds.metric_rule(ds.state_sel(), { ds.border_w(ds.stok("bw")), ds.pad_h(ds.stok("md")), ds.pad_v(ds.stok("sm")) })
        }, {
            ds.text_rule(ds.state_sel(), { ds.font(ds.ftok("ui_sm")), ds.text_wrap(T.Layout.TextNoWrap) })
        }),

        ds.surface("browser_item", {
            ds.paint_rule(ds.paint_sel(), { ds.bg(ds.clit(0)), ds.fg(ds.ctok("subtext")), ds.border_color(ds.clit(0)) }),
            ds.paint_rule(ds.paint_sel({ pointer = "hovered" }), { ds.bg(ds.ctok("surface0")), ds.fg(ds.ctok("text")), ds.border_color(ds.ctok("surface0")) }),
            ds.paint_rule(ds.paint_sel({ flags = { "active" } }), { ds.bg(ds.ctok("base")), ds.fg(ds.ctok("teal")), ds.border_color(ds.ctok("teal")) }),
            ds.paint_rule(ds.paint_sel({ focus = "focused" }), { ds.border_color(ds.ctok("mauve")) }),
        }, {
            ds.metric_rule(ds.state_sel(), { ds.border_w(ds.stok("bw")), ds.pad_h(ds.stok("md")), ds.pad_v(ds.stok("sm")) })
        }, {
            ds.text_rule(ds.state_sel(), { ds.font(ds.ftok("ui_sm")), ds.text_wrap(T.Layout.TextNoWrap) })
        }),

        ds.surface("statusbar", {
            ds.paint_rule(ds.paint_sel(), { ds.bg(ds.ctok("blue")), ds.fg(ds.ctok("crust")) }),
        }, {
            ds.metric_rule(ds.state_sel(), { ds.pad_h(ds.stok("md")), ds.pad_v(ds.slit(2)) })
        }, {
            ds.text_rule(ds.state_sel(), { ds.font(ds.ftok("ui_sm")), ds.text_wrap(T.Layout.TextNoWrap) })
        }),
    }
})

M.theme = THEME

-- ─────────────────────────────────────────────────────────────
-- Typed helpers
-- ─────────────────────────────────────────────────────────────

local L = T.Layout
local U = T.SemUI
local P = T.Paint
local R = T.Runtime

local FILL_BOX = L.Box(L.SizePercent(1), L.SizePercent(1), L.NoMin, L.NoMin, L.NoMax, L.NoMax)
local AUTO_BOX = L.Box(L.SizeAuto, L.SizeAuto, L.NoMin, L.NoMin, L.NoMax, L.NoMax)

local function fill_w_h(h) return L.Box(L.SizePercent(1), L.SizePx(h), L.NoMin, L.NoMin, L.NoMax, L.NoMax) end
local function box_w_fill_h(w) return L.Box(L.SizePx(w), L.SizePercent(1), L.NoMin, L.NoMin, L.NoMax, L.NoMax) end

local function item(node, grow, shrink, basis, align)
    return U.FlexItem(node, grow or 0, shrink or 0, basis or L.BasisAuto, align or L.CrossAuto, L.Insets(0, 0, 0, 0))
end

local function row(box, children, opts)
    opts = opts or {}
    return U.Flex(L.AxisRow, opts.wrap or L.WrapNoWrap, opts.gap or 0, opts.gap_cross or 0,
        opts.justify or L.MainStart, opts.align or L.CrossStart, opts.align_content or L.ContentStart,
        box, children)
end

local function col(box, children, opts)
    opts = opts or {}
    return U.Flex(L.AxisCol, opts.wrap or L.WrapNoWrap, opts.gap or 0, opts.gap_cross or 0,
        opts.justify or L.MainStart, opts.align or L.CrossStart, opts.align_content or L.ContentStart,
        box, children)
end

local function text(box, txt)
    local spec = U.TextSpec(U.UseSurfaceFont, U.UseSurfaceLineHeight, U.UseSurfaceTextAlign, U.UseSurfaceTextWrap, U.UseSurfaceOverflow, U.UseSurfaceLineLimit)
    return U.Text("", box, spec, txt)
end

local function panel(surface, flags, id, scroll_y, box, child)
    return U.Surface(surface, flags or {}, U.ScrollArea(id or "", L.ScrollY, 0, scroll_y or 0, box, child))
end

local function pressable(id, child)
    return U.Focusable(id, U.Pressable(id, child))
end

local function scalar(v)
    if type(v) == "string" then
        return P.ScalarFromRef(R.NumRef(v))
    end
    return P.ScalarLit(v or 0)
end

local function text_value(v)
    if type(v) == "string" then
        return P.TextFromRef(R.TextRef(v))
    end
    return P.TextLit(v or "")
end

local function color_value(v)
    if type(v) == "string" then
        return P.ColorFromRef(R.ColorRef(v))
    end
    return P.ColorPackLit(ds.solid(v or 0))
end

local function paint_text_value(tag, x, y, w, h, font_id, color, align, line_height, wrap, overflow, line_limit, value)
    return P.Text(
        tag or "",
        scalar(x), scalar(y), scalar(w), scalar(h),
        font_id or 2,
        color_value(color),
        line_height or L.LineHeightPx(18),
        align or L.TextStart,
        wrap or L.TextNoWrap,
        overflow or L.OverflowClip,
        line_limit or L.MaxLines(1),
        text_value(value))
end

local function paint_text_ref(tag, x, y, w, h, font_id, color, align, line_height, ref_name)
    return paint_text_value(tag, x, y, w, h, font_id, color, align, line_height, L.TextNoWrap, L.OverflowClip, L.MaxLines(1), ref_name)
end

local function paint_text_multiline_ref(tag, x, y, w, h, font_id, color, align, line_height, ref_name)
    return paint_text_value(tag, x, y, w, h, font_id, color, align, line_height, L.TextWordWrap, L.OverflowClip, L.UnlimitedLines, ref_name)
end

local function paint_fill(tag, x, y, w, h, color)
    return P.FillRect(tag or "", scalar(x), scalar(y), scalar(w), scalar(h), color_value(color))
end

local function paint_stroke(tag, x, y, w, h, thickness, color)
    return P.StrokeRect(tag or "", scalar(x), scalar(y), scalar(w), scalar(h), scalar(thickness or 1), color_value(color))
end

local function paint_line(tag, x1, y1, x2, y2, thickness, color)
    return P.Line(tag or "", scalar(x1), scalar(y1), scalar(x2), scalar(y2), scalar(thickness or 1), color_value(color))
end

-- ─────────────────────────────────────────────────────────────
-- Mock domain
-- ─────────────────────────────────────────────────────────────

local PHASES = {
    Phase("spec", "DawProjectSpec", "parse", "XML / interchange", "faithful representation of the exchange format"),
    Phase("normalized", "DawProjectNormalized", "normalize", "scope / defaults / ambiguity", "consume inherited ambiguity and close open cases"),
    Phase("source", "DawSource", "lower", "interchange grammar", "canonical authored DAW language"),
    Phase("bound", "DawBound", "bind", "refs to tracks / assets / params", "all references become validated targets"),
    Phase("graph", "DawGraph", "lower_graph", "containment / routing / sends", "explicit processing graph and use-sites"),
    Phase("classified", "DawClassified", "classify", "generic graph nodes", "execution domain, rate, processor family"),
    Phase("schedule", "DawSchedule", "schedule", "unordered classified graph", "topological jobs, spans, slices, state slots"),
    Phase("machine", "DawMachine.Audio", "define_machine", "scheduled plan", "canonical gen / param / state audio machine"),
    Phase("proto", "DawProtoTerra.Audio", "realize", "machine meaning", "Terra-native realization and installed callback"),
}

local TRACKS = {
    Track("trk:drums", "Drum Bus", "group", "Master", {
        Device("dev:drums:1", "Transient", "AudioFX", true),
        Device("dev:drums:2", "Bus Comp", "AudioFX", true),
        Device("dev:drums:3", "Limiter", "AudioFX", true),
    }, {
        Clip("clip:drums:1", "Verse", 0.0, 2.0, 1, C.blue, false),
        Clip("clip:drums:2", "Break", 2.0, 1.5, 1, C.teal, false),
        Clip("clip:drums:3", "Drop", 4.0, 3.5, 1, C.green, false),
    }),
    Track("trk:bass", "Bass Synth", "instrument", "Drum Bus", {
        Device("dev:bass:1", "Chord FX", "NoteFX", true),
        Device("dev:bass:2", "Juno Voice", "Instrument", true),
        Device("dev:bass:3", "Saturator", "AudioFX", true),
    }, {
        Clip("clip:bass:1", "Verse Riff", 0.0, 3.0, 1, C.mauve, false),
        Clip("clip:bass:2", "Drop Pulse", 3.5, 4.0, 1, C.orange, false),
    }),
    Track("trk:vocal", "Vox Chops", "audio", "Master", {
        Device("dev:vocal:1", "Warp Map", "AudioClip", true),
        Device("dev:vocal:2", "Granulator", "AudioFX", true),
        Device("dev:vocal:3", "Echo", "AudioFX", true),
    }, {
        Clip("clip:vocal:1", "Hook A", 0.5, 1.25, 1, C.red, true),
        Clip("clip:vocal:2", "Hook B", 2.5, 1.25, 1, C.yellow, true),
        Clip("clip:vocal:3", "Lift", 5.5, 1.5, 1, C.red, true),
    }),
    Track("trk:return", "Cloud Return", "return", "Master", {
        Device("dev:return:1", "Diffusion", "AudioFX", true),
        Device("dev:return:2", "Meter", "Analyzer", true),
    }, {}),
}

local INITIAL_LOGS = {
    "installed callback from DawProtoTerra.Audio",
    "structural identity rides on ASDL unique nodes",
    "realization identity rides on terralib.memoize shapes",
    "turning a knob writes state.live_params only",
    "rerouting or changing clips rebuilds the machine",
}

local ROUTES = { "Master", "Drum Bus", "Parallel", "Cloud Return" }

-- ─────────────────────────────────────────────────────────────
-- Layout constants
-- ─────────────────────────────────────────────────────────────

local TOPBAR_H = 54
local STATUS_H = 24
local BROWSER_W = 228
local MIXER_W = 268
local DEVICE_H = 214
local HEADER_H = 24
local BROWSER_TRACK_ROW_H = 56
local TRACK_ROW_H = 72
local RULER_H = 22
local TIMELINE_BEATS = 8
local CLIP_CAP = 16
local DEVICE_CAP = 6
local LOG_ROWS = 4
local MIXER_ROWS = 4
local PHASE_SHORT = {
    spec = "spec",
    normalized = "normalize",
    source = "source",
    bound = "bind",
    graph = "graph",
    classified = "classify",
    schedule = "schedule",
    machine = "machine",
    proto = "realize",
}

-- ─────────────────────────────────────────────────────────────
-- Utility
-- ─────────────────────────────────────────────────────────────

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function copy_seq(seq)
    local out = {}
    for i = 1, #seq do
        out[i] = seq[i]
    end
    return out
end

local function touch(state)
    return pvm.with(state, { rev = state.rev + 1 })
end

local function append_log(state, message)
    local logs = copy_seq(state.logs)
    logs[#logs + 1] = message
    while #logs > 24 do
        table.remove(logs, 1)
    end
    return pvm.with(state, { logs = logs })
end

local function replace_number_at(seq, index, value)
    local out = copy_seq(seq)
    out[index] = value
    return out
end

local function replace_track_at(state, index, track)
    local tracks = copy_seq(state.tracks)
    tracks[index] = track
    return pvm.with(state, { tracks = tracks })
end

local function selected_phase(state)
    return state.phases[state.selected_phase]
end

local function selected_track(state)
    return state.tracks[state.selected_track]
end

local function next_route(route)
    for i = 1, #ROUTES do
        if ROUTES[i] == route then
            return ROUTES[(i % #ROUTES) + 1]
        end
    end
    return ROUTES[1]
end

local function rotate_devices(devices)
    local out = copy_seq(devices)
    if #out > 1 then
        local first = out[1]
        for i = 1, #out - 1 do
            out[i] = out[i + 1]
        end
        out[#out] = first
    end
    return out
end

local function fmt_percent(n)
    return string_format("%d%%", math_floor((n or 0) * 100 + 0.5))
end

local function fmt_db(v)
    return string_format("%.1f dB", v or 0)
end

local function fmt_pan(v)
    v = v or 0
    if math_abs(v) < 0.05 then
        return "C"
    elseif v < 0 then
        return string_format("L %.2f", math_abs(v))
    end
    return string_format("R %.2f", v)
end

local function meter_level(state, i)
    local gain = state.gains_db[i] or 0
    local base = state.playing and (0.33 + 0.22 * (0.5 + 0.5 * math_sin(state.time * 2.1 + i * 0.7))) or 0.06
    local shape = 0.16 * (0.5 + 0.5 * math_cos(state.time * 5.2 + i))
    return clamp(base + shape + ((gain + 12) / 24) * 0.22, 0.03, 1.0)
end

local function track_color(i)
    if i == 1 then return C.blue end
    if i == 2 then return C.green end
    if i == 3 then return C.red end
    return C.teal
end

local function device_color(family)
    if family == "Instrument" then return C.green end
    if family == "NoteFX" then return C.teal end
    if family == "Analyzer" then return C.yellow end
    if family == "AudioClip" then return C.red end
    return C.blue
end

local function track_icon(role)
    if role == "group" then return "▣" end
    if role == "instrument" then return "◉" end
    if role == "audio" then return "◍" end
    return "↺"
end

local function mixer_label(track)
    if track.role == "group" then return "DRUM" end
    if track.role == "instrument" then return "BASS" end
    if track.role == "audio" then return "VOX" end
    if track.role == "return" then return "RVRB" end
    return string_upper((track.name or "TRK"):sub(1, 5))
end

-- ─────────────────────────────────────────────────────────────
-- Paint graphs
-- ─────────────────────────────────────────────────────────────

local function arrangement_paint()
    local kids = {}
    local lh = L.LineHeightPx(16)
    local small_lh = L.LineHeightPx(14)

    kids[#kids + 1] = paint_fill("", 0, 0, "arr:w", "arr:h", C.base)
    kids[#kids + 1] = paint_stroke("", 0, 0, "arr:w", "arr:h", 1, C.surface1)
    kids[#kids + 1] = paint_text_ref("", 12, 6, 220, 18, 2, C.subtext0, L.TextStart, lh, "arr:title")
    kids[#kids + 1] = paint_text_ref("", "arr:w_note_x", 6, "arr:note_w", 18, 1, C.overlay0, L.TextEnd, small_lh, "arr:note")

    kids[#kids + 1] = paint_fill("", 0, "arr:body_y", "arr:header_w", "arr:body_h", C.mantle)
    kids[#kids + 1] = paint_fill("", "arr:header_w", "arr:body_y", "arr:timeline_w", "arr:body_h", C.base)
    kids[#kids + 1] = paint_line("", 0, "arr:ruler_y2", "arr:w", "arr:ruler_y2", 1, C.surface1)
    kids[#kids + 1] = paint_line("", "arr:header_w", "arr:body_y", "arr:header_w", "arr:h", 1, C.surface1)

    for beat = 0, TIMELINE_BEATS do
        local base = "arr:beat:" .. beat
        kids[#kids + 1] = paint_line("", base .. ":x", "arr:body_y", base .. ":x", "arr:h", 1, base .. ":color")
        if beat < TIMELINE_BEATS then
            kids[#kids + 1] = paint_text_ref("", base .. ":x_label", 30, 40, 14, 1, C.overlay0, L.TextStart, small_lh, base .. ":text")
        end
    end

    for i = 1, #TRACKS do
        local base = "arr:track:" .. i
        kids[#kids + 1] = paint_fill("", 0, base .. ":y", "arr:w", base .. ":h", base .. ":bg")
        kids[#kids + 1] = paint_line("", 0, base .. ":y2", "arr:w", base .. ":y2", 1, C.surface0)
        kids[#kids + 1] = paint_text_ref("", 14, base .. ":title_y", 132, 16, 2, base .. ":title_color", L.TextStart, lh, base .. ":name")
        kids[#kids + 1] = paint_text_ref("", 14, base .. ":meta_y", 156, 14, 1, C.overlay0, L.TextStart, small_lh, base .. ":meta")
        kids[#kids + 1] = paint_text_ref("", 110, base .. ":meta_y", 60, 14, 1, base .. ":route_color", L.TextEnd, small_lh, base .. ":route")
    end

    kids[#kids + 1] = paint_line("", "arr:playhead_x", "arr:body_y", "arr:playhead_x", "arr:h", 2, C.yellow)

    for i = 1, CLIP_CAP do
        local base = "arr:clip:" .. i
        kids[#kids + 1] = paint_fill("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", base .. ":fill")
        kids[#kids + 1] = paint_stroke("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", 1, base .. ":stroke")
        kids[#kids + 1] = paint_text_ref("", base .. ":tx", base .. ":ty", base .. ":tw", 14, 1, C.crust, L.TextStart, small_lh, base .. ":text")
    end

    for i = 1, #TRACKS do
        local base = "arr:routebox:" .. i
        kids[#kids + 1] = paint_fill("", base .. ":x1", base .. ":y", base .. ":w", base .. ":h", base .. ":fill1")
        kids[#kids + 1] = paint_stroke("", base .. ":x1", base .. ":y", base .. ":w", base .. ":h", 1, base .. ":stroke1")
        kids[#kids + 1] = paint_text_ref("", base .. ":x1t", base .. ":yt", base .. ":tw", 14, 1, C.crust, L.TextStart, small_lh, base .. ":text1")
        kids[#kids + 1] = paint_fill("", base .. ":x2", base .. ":y", base .. ":w", base .. ":h", base .. ":fill2")
        kids[#kids + 1] = paint_stroke("", base .. ":x2", base .. ":y", base .. ":w", base .. ":h", 1, base .. ":stroke2")
        kids[#kids + 1] = paint_text_ref("", base .. ":x2t", base .. ":yt", base .. ":tw", 14, 1, C.crust, L.TextStart, small_lh, base .. ":text2")
        kids[#kids + 1] = paint_line("", base .. ":lx1", base .. ":ly", base .. ":lx2", base .. ":ly", 2, base .. ":line")
    end

    for i = 1, #TRACKS do
        for j = 1, 3 do
            local base = "arr:machine:" .. i .. ":" .. j
            kids[#kids + 1] = paint_fill("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", base .. ":fill")
            kids[#kids + 1] = paint_stroke("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", 1, base .. ":stroke")
            kids[#kids + 1] = paint_text_ref("", base .. ":tx", base .. ":ty", base .. ":tw", 14, 1, C.crust, L.TextStart, small_lh, base .. ":text")
        end
    end

    for i = 1, 5 do
        local base = "arr:auto:" .. i
        kids[#kids + 1] = paint_line("", base .. ":x1", base .. ":y1", base .. ":x2", base .. ":y2", 2, base .. ":color")
    end

    return P.ClipRegion(scalar(0), scalar(0), scalar("arr:w"), scalar("arr:h"), P.Group(kids))
end

local function devices_paint()
    local kids = {}
    local lh = L.LineHeightPx(16)
    local small_lh = L.LineHeightPx(14)

    kids[#kids + 1] = paint_fill("", 0, 0, "dev:w", "dev:h", C.base)
    kids[#kids + 1] = paint_stroke("", 0, 0, "dev:w", "dev:h", 1, C.surface1)
    kids[#kids + 1] = paint_text_ref("", 12, 8, 280, 18, 2, C.subtext0, L.TextStart, lh, "dev:title")
    kids[#kids + 1] = paint_text_ref("", "dev:w_note_x", 8, "dev:note_w", 18, 1, C.overlay0, L.TextEnd, small_lh, "dev:note")

    for i = 1, DEVICE_CAP do
        local base = "dev:slot:" .. i
        kids[#kids + 1] = paint_fill("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", base .. ":fill")
        kids[#kids + 1] = paint_stroke("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", 1, base .. ":stroke")
        kids[#kids + 1] = paint_text_ref("", base .. ":tx", base .. ":ty", base .. ":tw", 16, 1, base .. ":title_color", L.TextStart, lh, base .. ":name")
        kids[#kids + 1] = paint_text_ref("", base .. ":tx", base .. ":ty2", base .. ":tw", 14, 1, C.overlay0, L.TextStart, small_lh, base .. ":family")
        for k = 1, 3 do
            local knob = base .. ":bar:" .. k
            kids[#kids + 1] = paint_stroke("", knob .. ":x", knob .. ":y_box", 14, "dev:bar_box_h", 1, C.surface1)
            kids[#kids + 1] = paint_fill("", knob .. ":x", knob .. ":y_fill", 14, knob .. ":h", knob .. ":color")
        end
    end

    kids[#kids + 1] = paint_fill("", "dev:info_x", 34, "dev:info_w", 72, C.mantle)
    kids[#kids + 1] = paint_stroke("", "dev:info_x", 34, "dev:info_w", 72, 1, C.surface1)
    kids[#kids + 1] = paint_text_ref("", "dev:info_tx", 42, "dev:info_tw", 16, 1, C.text, L.TextStart, small_lh, "dev:phase")
    kids[#kids + 1] = paint_text_ref("", "dev:info_tx", 60, "dev:info_tw", 16, 1, C.subtext0, L.TextStart, small_lh, "dev:compile")
    kids[#kids + 1] = paint_text_ref("", "dev:info_tx", 78, "dev:info_tw", 16, 1, C.subtext0, L.TextStart, small_lh, "dev:split")
    kids[#kids + 1] = paint_stroke("", "dev:sem_x", 100, "dev:bar_w", 8, 1, C.surface1)
    kids[#kids + 1] = paint_fill("", "dev:sem_x", 100, "dev:sem_w", 8, C.blue)
    kids[#kids + 1] = paint_stroke("", "dev:sem_x", 122, "dev:bar_w", 8, 1, C.surface1)
    kids[#kids + 1] = paint_fill("", "dev:sem_x", 122, "dev:terra_w", 8, C.green)
    kids[#kids + 1] = paint_text_ref("", "dev:sem_x", 132, "dev:info_tw", 14, 1, C.overlay0, L.TextStart, small_lh, "dev:reuse")

    for i = 1, LOG_ROWS do
        local base = "dev:log:" .. i
        kids[#kids + 1] = paint_fill("", 0, base .. ":y", "dev:w", 18, base .. ":bg")
        kids[#kids + 1] = paint_text_ref("", 10, base .. ":y", "dev:log_w", 16, 4, base .. ":fg", L.TextStart, small_lh, base .. ":text")
    end

    return P.ClipRegion(scalar(0), scalar(0), scalar("dev:w"), scalar("dev:h"), P.Group(kids))
end

local function mixer_paint()
    local kids = {}
    local lh = L.LineHeightPx(16)
    local small_lh = L.LineHeightPx(14)

    kids[#kids + 1] = paint_fill("", 0, 0, "mix:w", "mix:h", C.base)
    kids[#kids + 1] = paint_stroke("", 0, 0, "mix:w", "mix:h", 1, C.surface1)

    for i = 1, MIXER_ROWS do
        local base = "mix:strip:" .. i
        kids[#kids + 1] = paint_fill("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", base .. ":fill")
        kids[#kids + 1] = paint_stroke("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", 1, base .. ":stroke")
        kids[#kids + 1] = paint_text_ref("", base .. ":tx", base .. ":ty", base .. ":tw", 16, 1, base .. ":name_color", L.TextCenter, small_lh, base .. ":name")
        kids[#kids + 1] = paint_stroke("", base .. ":meter_x", base .. ":meter_y", 12, "mix:meter_box_h", 1, C.surface1)
        kids[#kids + 1] = paint_fill("", base .. ":meter_x", base .. ":meter_fill_y", 12, base .. ":meter_h", base .. ":meter_color")
        kids[#kids + 1] = paint_stroke("", base .. ":fader_x", base .. ":fader_y", 14, "mix:fader_box_h", 1, C.surface1)
        kids[#kids + 1] = paint_fill("", base .. ":fader_x", base .. ":handle_y", 14, 10, C.text)
        kids[#kids + 1] = paint_text_ref("", base .. ":tx", base .. ":gain_y", base .. ":tw", 16, 1, C.subtext0, L.TextCenter, small_lh, base .. ":gain")
        kids[#kids + 1] = paint_text_ref("", base .. ":tx", base .. ":pan_y", base .. ":tw", 16, 1, C.overlay0, L.TextCenter, small_lh, base .. ":pan")
    end

    return P.ClipRegion(scalar(0), scalar(0), scalar("mix:w"), scalar("mix:h"), P.Group(kids))
end

local function status_paint()
    local lh = L.LineHeightPx(14)
    return P.Group({
        paint_text_ref("", 0, 0, "status:left_w", "status:h", 1, C.crust, L.TextStart, lh, "status:left"),
        paint_text_ref("", "status:right_x", 0, "status:right_w", "status:h", 1, C.crust, L.TextEnd, lh, "status:right"),
    })
end

-- ─────────────────────────────────────────────────────────────
-- Structural UI
-- ─────────────────────────────────────────────────────────────

local function transport_button(id, label, active)
    return item(pressable(id, panel("button", flags_active(active), "", 0, AUTO_BOX, text(AUTO_BOX, label))), 0, 0)
end

local function transport_bar(state)
    local phase = selected_phase(state)
    return panel("transport", {}, "", 0, fill_w_h(TOPBAR_H), row(FILL_BOX, {
        item(text(AUTO_BOX, " PROJECT · midnight circuits"), 0, 0),
        transport_button("view:arrange", "ARRANGE", state.selected_view == "arrange"),
        transport_button("view:routing", "ROUTING", state.selected_view == "routing"),
        transport_button("view:machine", "MACHINE", state.selected_view == "machine"),
        transport_button("action:play", state.playing and "STOP" or "PLAY", state.playing),
        transport_button("action:struct", "ROUTE", false),
        transport_button("action:live", "KNOB", false),
        transport_button("action:phase_prev", "<", false),
        item(text(AUTO_BOX, " stage · " .. phase.verb), 0, 0),
        transport_button("action:phase_next", ">", false),
        item(U.Spacer(FILL_BOX), 1, 1),
        item(text(AUTO_BOX, string_format("tempo %d", state.bpm)), 0, 0),
        item(text(AUTO_BOX, string_format("compile #%d", state.compile_gen)), 0, 0),
    }, { align = L.CrossStretch, gap = 8 }))
end

local function browser_track_row(state, track, index)
    local label = string_format(" %s  %s", track_icon(track.role), track.name)
    local meta = string_format(" %s  →  %s", track.role, track.destination)
    return item(pressable("browser:track:" .. index,
        panel("browser_item", flags_active(index == state.selected_track), "", 0, fill_w_h(BROWSER_TRACK_ROW_H), col(FILL_BOX, {
            item(text(fill_w_h(18), label), 0, 0),
            item(text(fill_w_h(16), meta), 0, 0),
        }))), 0, 0)
end

local function browser_panel(state)
    local phase = selected_phase(state)
    local track = selected_track(state)
    local rows = {
        item(text(fill_w_h(HEADER_H), " BROWSER"), 0, 0),
        item(text(fill_w_h(18), " project tracks"), 0, 0),
    }
    for i = 1, #state.tracks do
        rows[#rows + 1] = browser_track_row(state, state.tracks[i], i)
    end
    rows[#rows + 1] = item(text(fill_w_h(18), " collections"), 0, 0)
    rows[#rows + 1] = item(text(fill_w_h(18), " drums"), 0, 0)
    rows[#rows + 1] = item(text(fill_w_h(18), " instruments"), 0, 0)
    rows[#rows + 1] = item(text(fill_w_h(18), " vocals"), 0, 0)
    rows[#rows + 1] = item(text(fill_w_h(18), " returns"), 0, 0)
    rows[#rows + 1] = item(U.Spacer(FILL_BOX), 1, 1)
    rows[#rows + 1] = item(text(fill_w_h(HEADER_H), " COMPILE STATUS"), 0, 0)
    rows[#rows + 1] = item(text(fill_w_h(18), " phase · " .. phase.title), 0, 0)
    rows[#rows + 1] = item(text(fill_w_h(18), " track · " .. track.name), 0, 0)
    rows[#rows + 1] = item(text(fill_w_h(18), " structural edits rebuild callbacks"), 0, 0)
    rows[#rows + 1] = item(text(fill_w_h(18), " live tweaks mutate state.live_params"), 0, 0)

    return panel("panel", {}, "", 0, box_w_fill_h(BROWSER_W), col(FILL_BOX, rows, { gap = 6 }))
end

local function arrangement_overlay()
    local rows = { item(U.Spacer(fill_w_h(RULER_H + 14)), 0, 0) }
    for i = 1, #TRACKS do
        rows[#rows + 1] = item(pressable("arr:track:" .. i, U.Spacer(fill_w_h(TRACK_ROW_H))), 0, 0)
    end
    rows[#rows + 1] = item(U.Spacer(FILL_BOX), 1, 1)
    return col(FILL_BOX, rows)
end

local function arrangement_panel()
    return panel("panel", {}, "", 0, FILL_BOX, U.Stack(FILL_BOX, {
        U.CustomPaint("arr:paint", FILL_BOX, arrangement_paint()),
        arrangement_overlay(),
    }))
end

local function devices_panel()
    return panel("panel", {}, "", 0, fill_w_h(DEVICE_H), U.CustomPaint("dev:paint", FILL_BOX, devices_paint()))
end

local function mixer_overlay()
    local strips = {}
    for i = 1, MIXER_ROWS do
        strips[#strips + 1] = item(pressable("mix:track:" .. i, U.Spacer(FILL_BOX)), 1, 1)
    end
    return row(FILL_BOX, strips, { gap = 8, align = L.CrossStretch })
end

local function mixer_panel()
    return panel("panel", {}, "", 0, box_w_fill_h(MIXER_W), col(FILL_BOX, {
        item(text(fill_w_h(HEADER_H), " MIXER"), 0, 0),
        item(U.Stack(FILL_BOX, {
            U.CustomPaint("mix:paint", FILL_BOX, mixer_paint()),
            mixer_overlay(),
        }), 1, 1),
    }))
end

local function status_bar()
    return panel("statusbar", {}, "", 0, fill_w_h(STATUS_H), U.CustomPaint("status:paint", FILL_BOX, status_paint()))
end

function M.build_tree(state, layout, opts)
    local focused_id = opts and opts.focused_id or ""

    local sem = panel("window", {}, "", 0, FILL_BOX, col(FILL_BOX, {
        item(transport_bar(state)),
        item(row(FILL_BOX, {
            item(browser_panel(state)),
            item(col(FILL_BOX, {
                item(arrangement_panel(), 1, 1),
                item(devices_panel()),
            }), 1, 1),
            item(mixer_panel()),
        }, { align = L.CrossStretch }), 1, 1),
        item(status_bar()),
    }))

    return lower.node(THEME, sem, { focused_id = focused_id }), sem
end

-- ─────────────────────────────────────────────────────────────
-- Runtime build
-- ─────────────────────────────────────────────────────────────

function M.compute_layout(w, h)
    local body_h = math_max(0, h - TOPBAR_H - STATUS_H)
    local center_w = math_max(0, w - BROWSER_W - MIXER_W)
    local arrange_h = math_max(160, body_h - DEVICE_H)
    return {
        width = w,
        height = h,
        body_h = body_h,
        center_w = center_w,
        arrange_h = arrange_h,
        device_h = DEVICE_H,
    }
end

function M.build_runtime(state, layout, opts)
    local runtime = { numbers = {}, texts = {}, colors = {} }
    local numbers = runtime.numbers
    local texts = runtime.texts
    local colors = runtime.colors

    local phase = selected_phase(state)
    local track = selected_track(state)

    -- status
    numbers["status:h"] = STATUS_H - 4
    numbers["status:left_w"] = math_floor(layout.width * 0.6)
    numbers["status:right_x"] = numbers["status:left_w"]
    numbers["status:right_w"] = math_max(0, layout.width - numbers["status:left_w"] - 16)
    texts["status:left"] = string_format(" mode %s   ·   phase %s   ·   track %s ", state.selected_view, phase.title, track.name)
    texts["status:right"] = string_format(" semantic %s   terra %s   cpu %.1f%% ", fmt_percent(state.semantic_reuse), fmt_percent(state.terra_reuse), state.cpu_usage)

    -- arrangement
    numbers["arr:w"] = math_max(0, layout.center_w - 2)
    numbers["arr:h"] = math_max(0, layout.arrange_h - 2)
    numbers["arr:header_w"] = 178
    numbers["arr:body_y"] = RULER_H + 14
    numbers["arr:body_h"] = math_max(0, numbers["arr:h"] - numbers["arr:body_y"])
    numbers["arr:ruler_y2"] = numbers["arr:body_y"]
    numbers["arr:timeline_w"] = math_max(80, numbers["arr:w"] - numbers["arr:header_w"] - 12)
    numbers["arr:w_note_x"] = math_max(10, numbers["arr:w"] - 220)
    numbers["arr:note_w"] = 200
    texts["arr:title"] = (state.selected_view == "arrange") and "ARRANGEMENT"
        or (state.selected_view == "routing") and "ROUTING OVERLAY"
        or "MACHINE OVERLAY"
    texts["arr:note"] = (state.selected_view == "arrange") and "clips / automation / playhead"
        or (state.selected_view == "routing") and "routing and send topology"
        or "compiled slices / jobs / state families"

    for beat = 0, TIMELINE_BEATS do
        local base = "arr:beat:" .. beat
        local x = numbers["arr:header_w"] + math_floor((beat / TIMELINE_BEATS) * numbers["arr:timeline_w"])
        numbers[base .. ":x"] = x
        numbers[base .. ":x_label"] = x + 4
        texts[base .. ":text"] = tostring(beat + 1)
        colors[base .. ":color"] = (beat % 2 == 0) and C.surface1 or C.surface0
    end

    for i = 1, #state.tracks do
        local t = state.tracks[i]
        local base = "arr:track:" .. i
        local y = numbers["arr:body_y"] + (i - 1) * TRACK_ROW_H
        numbers[base .. ":y"] = y
        numbers[base .. ":y2"] = y + TRACK_ROW_H
        numbers[base .. ":h"] = TRACK_ROW_H
        numbers[base .. ":title_y"] = y + 10
        numbers[base .. ":meta_y"] = y + 28
        texts[base .. ":name"] = t.name
        texts[base .. ":meta"] = t.role
        texts[base .. ":route"] = t.destination
        colors[base .. ":bg"] = (i == state.selected_track) and C.surface0 or C.mantle
        colors[base .. ":title_color"] = (i == state.selected_track) and C.text or track_color(i)
        colors[base .. ":route_color"] = (i == state.selected_track) and C.mauve or C.overlay0
    end

    numbers["arr:playhead_x"] = numbers["arr:header_w"]
        + math_floor(((state.transport_beat % TIMELINE_BEATS) / TIMELINE_BEATS) * numbers["arr:timeline_w"])

    do
        local clip_slot = 1
        for ti = 1, #state.tracks do
            local t = state.tracks[ti]
            for j = 1, #t.clips do
                local c = t.clips[j]
                if clip_slot <= CLIP_CAP then
                    local base = "arr:clip:" .. clip_slot
                    local x = numbers["arr:header_w"] + math_floor((c.start_beat / TIMELINE_BEATS) * numbers["arr:timeline_w"]) + 3
                    local y = numbers["arr:track:" .. ti .. ":y"] + 8
                    local w = math_max(24, math_floor((c.length_beat / TIMELINE_BEATS) * numbers["arr:timeline_w"]) - 6)
                    local visible = (state.selected_view == "arrange") and 1 or 0
                    numbers[base .. ":x"] = visible * x
                    numbers[base .. ":y"] = visible * y
                    numbers[base .. ":w"] = visible * w
                    numbers[base .. ":h"] = visible * (TRACK_ROW_H - 16)
                    numbers[base .. ":tx"] = visible * (x + 8)
                    numbers[base .. ":ty"] = visible * (y + 6)
                    numbers[base .. ":tw"] = visible * math_max(8, w - 12)
                    texts[base .. ":text"] = c.label .. (c.warped and " · warp" or "")
                    colors[base .. ":fill"] = c.color
                    colors[base .. ":stroke"] = c.warped and C.mauve or C.crust
                    clip_slot = clip_slot + 1
                end
            end
        end
        while clip_slot <= CLIP_CAP do
            local base = "arr:clip:" .. clip_slot
            numbers[base .. ":x"] = 0
            numbers[base .. ":y"] = 0
            numbers[base .. ":w"] = 0
            numbers[base .. ":h"] = 0
            numbers[base .. ":tx"] = 0
            numbers[base .. ":ty"] = 0
            numbers[base .. ":tw"] = 0
            texts[base .. ":text"] = ""
            colors[base .. ":fill"] = 0
            colors[base .. ":stroke"] = 0
            clip_slot = clip_slot + 1
        end
    end

    for i = 1, #state.tracks do
        local base = "arr:routebox:" .. i
        local y = numbers["arr:track:" .. i .. ":y"] + 14
        local visible = (state.selected_view == "routing") and 1 or 0
        local x1 = numbers["arr:header_w"] + 28
        local x2 = numbers["arr:w"] - 170
        local w = 110
        numbers[base .. ":x1"] = visible * x1
        numbers[base .. ":x2"] = visible * x2
        numbers[base .. ":y"] = visible * y
        numbers[base .. ":w"] = visible * w
        numbers[base .. ":h"] = visible * 28
        numbers[base .. ":x1t"] = visible * (x1 + 8)
        numbers[base .. ":x2t"] = visible * (x2 + 8)
        numbers[base .. ":yt"] = visible * (y + 7)
        numbers[base .. ":tw"] = visible * (w - 10)
        numbers[base .. ":lx1"] = visible * (x1 + w)
        numbers[base .. ":lx2"] = visible * x2
        numbers[base .. ":ly"] = visible * (y + 14)
        texts[base .. ":text1"] = state.tracks[i].name
        texts[base .. ":text2"] = state.tracks[i].destination
        colors[base .. ":fill1"] = track_color(i)
        colors[base .. ":fill2"] = C.surface1
        colors[base .. ":stroke1"] = C.crust
        colors[base .. ":stroke2"] = C.crust
        colors[base .. ":line"] = (i == state.selected_track) and C.yellow or C.overlay0
    end

    for i = 1, #state.tracks do
        for j = 1, 3 do
            local base = "arr:machine:" .. i .. ":" .. j
            local visible = (state.selected_view == "machine") and 1 or 0
            local box_w = math_max(48, math_floor((numbers["arr:timeline_w"] - 40) / 3))
            local x = numbers["arr:header_w"] + 16 + (j - 1) * (box_w + 10)
            local y = numbers["arr:track:" .. i .. ":y"] + 14
            local labels = { "feeder", "chain", "out" }
            local fills = { C.teal, C.blue, C.green }
            numbers[base .. ":x"] = visible * x
            numbers[base .. ":y"] = visible * y
            numbers[base .. ":w"] = visible * box_w
            numbers[base .. ":h"] = visible * 28
            numbers[base .. ":tx"] = visible * (x + 8)
            numbers[base .. ":ty"] = visible * (y + 7)
            numbers[base .. ":tw"] = visible * (box_w - 10)
            texts[base .. ":text"] = labels[j]
            colors[base .. ":fill"] = fills[j]
            colors[base .. ":stroke"] = (i == state.selected_track) and C.yellow or C.crust
        end
    end

    do
        local selected_y = numbers["arr:track:" .. state.selected_track .. ":y"] + TRACK_ROW_H - 18
        for i = 1, 5 do
            local base = "arr:auto:" .. i
            local x1 = numbers["arr:header_w"] + math_floor(((i - 1) / 5) * numbers["arr:timeline_w"])
            local x2 = numbers["arr:header_w"] + math_floor((i / 5) * numbers["arr:timeline_w"])
            local y1 = selected_y - math_floor((0.5 + 0.5 * math_sin(state.time * 0.8 + i * 0.4)) * 20)
            local y2 = selected_y - math_floor((0.5 + 0.5 * math_cos(state.time * 1.1 + i * 0.5)) * 18)
            local visible = (state.selected_view == "arrange") and 1 or 0
            numbers[base .. ":x1"] = visible * x1
            numbers[base .. ":y1"] = visible * y1
            numbers[base .. ":x2"] = visible * x2
            numbers[base .. ":y2"] = visible * y2
            colors[base .. ":color"] = (i == 3) and C.yellow or C.orange
        end
    end

    -- devices
    numbers["dev:w"] = math_max(0, layout.center_w - 2)
    numbers["dev:h"] = DEVICE_H - 2
    numbers["dev:w_note_x"] = math_max(10, numbers["dev:w"] - 220)
    numbers["dev:note_w"] = 200
    texts["dev:title"] = "DEVICE CHAIN"
    texts["dev:note"] = string_format("selected track · %s", track.name)

    do
        local slots = math_max(1, #track.devices)
        local gap = 10
        local info_w = 270
        local content_w = math_max(120, numbers["dev:w"] - info_w - 26)
        local slot_w = math_max(52, math_floor((content_w - gap * math_max(0, slots - 1)) / slots))
        local y = 34
        for i = 1, DEVICE_CAP do
            local base = "dev:slot:" .. i
            if i <= #track.devices then
                local dev = track.devices[i]
                local x = 12 + (i - 1) * (slot_w + gap)
                numbers[base .. ":x"] = x
                numbers[base .. ":y"] = y
                numbers[base .. ":w"] = slot_w
                numbers[base .. ":h"] = 92
                numbers[base .. ":tx"] = x + 8
                numbers[base .. ":ty"] = y + 8
                numbers[base .. ":ty2"] = y + 28
                numbers[base .. ":tw"] = math_max(10, slot_w - 12)
                texts[base .. ":name"] = dev.name
                texts[base .. ":family"] = dev.family
                colors[base .. ":fill"] = device_color(dev.family)
                colors[base .. ":stroke"] = (i == 1) and C.yellow or C.crust
                colors[base .. ":title_color"] = C.crust
                for k = 1, 3 do
                    local knob = base .. ":bar:" .. k
                    local level = 0.2 + 0.65 * (0.5 + 0.5 * math_sin(state.time * (1.4 + k * 0.2) + i + k))
                    numbers[knob .. ":x"] = x + 12 + (k - 1) * 20
                    numbers[knob .. ":y_box"] = y + 48
                    numbers[knob .. ":h"] = math_floor(24 * level)
                    numbers[knob .. ":y_fill"] = y + 72 - numbers[knob .. ":h"]
                    colors[knob .. ":color"] = (k == 2) and C.yellow or C.crust
                end
            else
                numbers[base .. ":x"] = 0
                numbers[base .. ":y"] = 0
                numbers[base .. ":w"] = 0
                numbers[base .. ":h"] = 0
                numbers[base .. ":tx"] = 0
                numbers[base .. ":ty"] = 0
                numbers[base .. ":ty2"] = 0
                numbers[base .. ":tw"] = 0
                texts[base .. ":name"] = ""
                texts[base .. ":family"] = ""
                colors[base .. ":fill"] = 0
                colors[base .. ":stroke"] = 0
                colors[base .. ":title_color"] = 0
                for k = 1, 3 do
                    local knob = base .. ":bar:" .. k
                    numbers[knob .. ":x"] = 0
                    numbers[knob .. ":y_box"] = 0
                    numbers[knob .. ":h"] = 0
                    numbers[knob .. ":y_fill"] = 0
                    colors[knob .. ":color"] = 0
                end
            end
        end

        numbers["dev:bar_box_h"] = 24
        numbers["dev:info_x"] = numbers["dev:w"] - info_w - 12
        numbers["dev:info_w"] = info_w
        numbers["dev:info_tx"] = numbers["dev:info_x"] + 10
        numbers["dev:info_tw"] = info_w - 16
        numbers["dev:sem_x"] = numbers["dev:info_x"] + 10
        numbers["dev:bar_w"] = info_w - 20
        numbers["dev:sem_w"] = math_floor(numbers["dev:bar_w"] * clamp(state.semantic_reuse, 0, 1))
        numbers["dev:terra_w"] = math_floor(numbers["dev:bar_w"] * clamp(state.terra_reuse, 0, 1))
        texts["dev:phase"] = string_format("stage · %s", PHASE_SHORT[phase.key] or phase.verb)
        texts["dev:compile"] = string_format("cb #%d", state.compile_gen)
        texts["dev:split"] = "compiled / live split"
        texts["dev:reuse"] = string_format("sem %s · terra %s", fmt_percent(state.semantic_reuse), fmt_percent(state.terra_reuse))
    end

    do
        local first = math_max(1, #state.logs - LOG_ROWS + 1)
        numbers["dev:log_w"] = math_max(10, numbers["dev:w"] - 20)
        for i = 1, LOG_ROWS do
            local line = state.logs[first + i - 1] or ""
            local base = "dev:log:" .. i
            numbers[base .. ":y"] = 132 + (i - 1) * 18
            texts[base .. ":text"] = line
            if line:find("no recompile", 1, true) then
                colors[base .. ":fg"] = C.green
            elseif line:find("rebuild", 1, true) or line:find("new machine", 1, true) or line:find("compile", 1, true) then
                colors[base .. ":fg"] = C.yellow
            else
                colors[base .. ":fg"] = C.subtext0
            end
            colors[base .. ":bg"] = 0
        end
    end

    -- mixer
    numbers["mix:w"] = math_max(0, MIXER_W - 2)
    numbers["mix:h"] = math_max(0, layout.body_h - HEADER_H - 2)
    numbers["mix:meter_box_h"] = math_max(40, numbers["mix:h"] - 92)
    numbers["mix:fader_box_h"] = math_max(40, numbers["mix:h"] - 92)

    do
        local gap = 8
        local inner_w = numbers["mix:w"] - 12
        local strip_w = math_max(40, math_floor((inner_w - gap * (MIXER_ROWS - 1)) / MIXER_ROWS))
        for i = 1, MIXER_ROWS do
            local base = "mix:strip:" .. i
            local x = 6 + (i - 1) * (strip_w + gap)
            local y = 0
            local meter = meter_level(state, i)
            local handle = clamp((state.gains_db[i] or 0 + 12) / 24, 0, 1)
            numbers[base .. ":x"] = x
            numbers[base .. ":y"] = y
            numbers[base .. ":w"] = strip_w
            numbers[base .. ":h"] = numbers["mix:h"]
            numbers[base .. ":tx"] = x + 4
            numbers[base .. ":ty"] = 8
            numbers[base .. ":tw"] = strip_w - 8
            numbers[base .. ":meter_x"] = x + 12
            numbers[base .. ":meter_y"] = 38
            numbers[base .. ":meter_h"] = math_floor(numbers["mix:meter_box_h"] * meter)
            numbers[base .. ":meter_fill_y"] = 38 + numbers["mix:meter_box_h"] - numbers[base .. ":meter_h"]
            numbers[base .. ":fader_x"] = x + strip_w - 26
            numbers[base .. ":fader_y"] = 38
            numbers[base .. ":handle_y"] = 38 + math_floor((1 - handle) * (numbers["mix:fader_box_h"] - 10))
            numbers[base .. ":gain_y"] = numbers["mix:h"] - 34
            numbers[base .. ":pan_y"] = numbers["mix:h"] - 18
            texts[base .. ":name"] = mixer_label(state.tracks[i])
            texts[base .. ":gain"] = fmt_db(state.gains_db[i])
            texts[base .. ":pan"] = fmt_pan(state.pans[i])
            colors[base .. ":fill"] = (i == state.selected_track) and C.surface0 or C.mantle
            colors[base .. ":stroke"] = (i == state.selected_track) and C.mauve or C.surface1
            colors[base .. ":name_color"] = (i == state.selected_track) and C.text or track_color(i)
            colors[base .. ":meter_color"] = (meter > 0.82) and C.red or (meter > 0.62) and C.yellow or C.green
        end
    end

    return runtime
end

-- ─────────────────────────────────────────────────────────────
-- State transitions
-- ─────────────────────────────────────────────────────────────

function M.new_state()
    return State(
        1,
        0,
        false,
        "arrange",
        7,
        2,
        12,
        13.25,
        128,
        21.0,
        0.96,
        0.91,
        4,
        18,
        "warm callback installed",
        { -2.5, -1.0, -4.0, -6.0 },
        { 0.0, -0.12, 0.14, 0.0 },
        PHASES,
        TRACKS,
        INITIAL_LOGS)
end

local function set_view(state, view)
    if state.selected_view == view then
        return state
    end
    return touch(pvm.with(state, { selected_view = view }))
end

local function set_phase(state, index)
    index = clamp(index, 1, #state.phases)
    if state.selected_phase == index then
        return state
    end
    return touch(pvm.with(state, { selected_phase = index }))
end

local function set_track(state, index)
    index = clamp(index, 1, #state.tracks)
    if state.selected_track == index then
        return state
    end
    return touch(pvm.with(state, { selected_track = index }))
end

local function toggle_play(state)
    state = pvm.with(state, { playing = not state.playing })
    state = append_log(state, state.playing
        and "transport started; callback reuses current installed machine"
        or "transport stopped; callback remains installed")
    return touch(state)
end

local function apply_structural_edit(state)
    local index = state.selected_track
    local track = state.tracks[index]
    local new_dest = next_route(track.destination)
    local new_track = Track(track.id, track.name, track.role, new_dest, rotate_devices(track.devices), track.clips)
    state = replace_track_at(state, index, new_track)
    state = pvm.with(state, {
        compile_gen = state.compile_gen + 1,
        structural_edits = state.structural_edits + 1,
        semantic_reuse = 0.84 + ((state.compile_gen % 4) * 0.03),
        terra_reuse = 0.72 + ((state.compile_gen % 3) * 0.05),
        last_compile_kind = "structural edit → rebuild schedule → compile new callback",
    })
    state = append_log(state, string_format("%s rerouted to %s → new machine shape → compile #%d", track.name, new_dest, state.compile_gen))
    return touch(state)
end

local function apply_live_tweak(state)
    local index = state.selected_track
    local gain_step = (state.live_edits % 2 == 0) and 1.25 or -0.75
    local pan_step = ((state.live_edits % 3) - 1) * 0.08
    local gains = replace_number_at(state.gains_db, index, clamp((state.gains_db[index] or 0) + gain_step, -12, 12))
    local pans = replace_number_at(state.pans, index, clamp((state.pans[index] or 0) + pan_step, -1, 1))
    state = pvm.with(state, {
        gains_db = gains,
        pans = pans,
        live_edits = state.live_edits + 1,
        semantic_reuse = 1.0,
        terra_reuse = 1.0,
        last_compile_kind = "live tweak → mutate state.live_params only",
    })
    state = append_log(state, string_format("%s live tweak → %s / %s (no recompile)", state.tracks[index].name, fmt_db(gains[index]), fmt_pan(pans[index])))
    return state
end

function M.update(state, dt)
    local time = state.time + dt
    local transport = state.transport_beat
    if state.playing then
        transport = transport + dt * (state.bpm / 60)
    end

    local cpu = 11 + (state.playing and 9 or 2) + math_abs(math_sin(time * 1.7)) * 7
    local semantic = state.semantic_reuse
    local terra = state.terra_reuse
    if semantic < 0.999 then
        semantic = math_min(1.0, semantic + dt * 0.08)
    end
    if terra < 0.999 then
        terra = math_min(1.0, terra + dt * 0.05)
    end

    return pvm.with(state, {
        time = time,
        transport_beat = transport,
        cpu_usage = cpu,
        semantic_reuse = semantic,
        terra_reuse = terra,
    })
end

function M.handle_event(state, event, layout)
    if event.kind == T.Msg.Click or event.kind == T.Msg.Submit then
        local browser_track = tonumber(event.id:match("^browser:track:(%d+)$"))
        if browser_track then
            return set_track(state, browser_track)
        end

        local arr_track = tonumber(event.id:match("^arr:track:(%d+)$"))
        if arr_track then
            return set_track(state, arr_track)
        end

        local mix_track = tonumber(event.id:match("^mix:track:(%d+)$"))
        if mix_track then
            return set_track(state, mix_track)
        end

        local view = event.id:match("^view:(.+)$")
        if view then
            return set_view(state, view)
        end

        if event.id == "action:play" then
            return toggle_play(state)
        elseif event.id == "action:struct" then
            return apply_structural_edit(state)
        elseif event.id == "action:live" then
            return apply_live_tweak(state)
        elseif event.id == "action:phase_prev" then
            return set_phase(state, state.selected_phase - 1)
        elseif event.id == "action:phase_next" then
            return set_phase(state, state.selected_phase + 1)
        end
    end

    return state
end

function M.handle_messages(state, messages, layout)
    for i = 1, #messages do
        state = M.handle_event(state, messages[i], layout)
    end
    return state
end

function M.keypressed(state, key, opts)
    if key == "1" then
        return set_view(state, "arrange"), true
    elseif key == "2" then
        return set_view(state, "routing"), true
    elseif key == "3" then
        return set_view(state, "machine"), true
    elseif key == "p" then
        return toggle_play(state), true
    elseif key == "g" then
        return apply_structural_edit(state), true
    elseif key == "k" then
        return apply_live_tweak(state), true
    elseif key == "left" then
        return set_phase(state, state.selected_phase - 1), true
    elseif key == "right" then
        return set_phase(state, state.selected_phase + 1), true
    elseif key == "up" then
        return set_track(state, state.selected_track - 1), true
    elseif key == "down" then
        return set_track(state, state.selected_track + 1), true
    end
    return state, false
end

function M.textinput(state, text_value, opts)
    return state, false
end

function M.build(state, opts)
    local layout = M.compute_layout(opts and opts.width or 1280, opts and opts.height or 720)
    local ui_node, sem = M.build_tree(state, layout, opts)
    return ui_node, M.build_runtime(state, layout, opts), layout, sem
end

function M.footer(state)
    local phase = selected_phase(state)
    local track = selected_track(state)
    local left = string_format("mode %s   phase %s   track %s", state.selected_view, phase.title, track.name)
    local right = string_format("compile #%d   semantic %s   terra %s   cpu %.1f%%", state.compile_gen, fmt_percent(state.semantic_reuse), fmt_percent(state.terra_reuse), state.cpu_usage)
    return left, right
end

return M
