-- ui/demo/app.lua
-- DAW-style mock demo for the fresh UI stack.
--
-- This is a mock UI, not a real DAW. The main goal is to look and feel like a
-- modern Bitwig-style DAW shell while still surfacing the core idea:
--
--   project/domain ASDL -> demo widget/view ASDL -> generic SemUI/UI
--   structural edits rebuild the compiled machine
--   live control edits mutate runtime state only

local pvm = require("pvm")
local ui = require("ui.init")
local demo_schema = require("ui.demo.asdl")
local demo_lower = require("ui.demo.lower")
local demo_bind = require("ui.demo.bind")

local T = ui.T
local D = demo_schema.T.Demo
local V = demo_schema.T.DemoView
local Live = demo_schema.T.DemoLive
local Core = demo_schema.T.DawProjectCore
local Root = demo_schema.T.DawProjectRoot
local NCore = demo_schema.T.DawProjectNormalizedCore
local NProject = demo_schema.T.DawProjectNormalized
local NParams = demo_schema.T.DawProjectNormalizedParams
local NAutomation = demo_schema.T.DawProjectNormalizedAutomation
local NDevices = demo_schema.T.DawProjectNormalizedDevices
local NMixer = demo_schema.T.DawProjectNormalizedMixer
local NTimeline = demo_schema.T.DawProjectNormalizedTimeline
local ds = ui.ds
local lower = ui.lower

local Phase = D.Phase
local State = D.State
local Slot = demo_schema.T.DemoSlot
local LiveTexts = Live.Texts
local LiveArrangement = Live.Arrangement
local LiveDevices = Live.Devices
local LiveWindow = Live.Window

local SLOT_CLOCK = Slot.Clock
local SLOT_REUSE = Slot.Reuse
local SLOT_DEVICES_SUBTITLE = Slot.DevicesSubtitle
local SLOT_STATUS_RIGHT = Slot.StatusRight
local SLOT_ARRANGEMENT_OVERLAY = Slot.Arrangement
local SLOT_DEVICES_OVERLAY = Slot.Devices

local M = {
    ui = ui,
    T = T,
    D = D,
    ds = ds,
    lower = lower,
    demo_lower = demo_lower,
    schema = demo_schema,
    V = V,
}

local math_abs = math.abs
local math_cos = math.cos
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_sin = math.sin
local string_format = string.format
local string_upper = string.upper
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

local function hex_rgba8(rgba8)
    return string_format("#%08x", rgba8)
end

local function param_header(id, name, parameter_id)
    return NCore.ParameterHeader(id, name, nil, nil, parameter_id)
end

local function real_parameter(id, name, unit, value, min, max, parameter_id)
    return NParams.RealParameter(param_header(id, name, parameter_id), unit, min, max, value)
end

local function bool_parameter(id, name, value, parameter_id)
    return NParams.BoolParameter(param_header(id, name, parameter_id), value)
end

local function make_device_header(id, name, color, role, vendor)
    return NCore.DeviceHeader(id, name, color, nil, role, true, name, id, vendor)
end

local function make_plugin(id, name, color, role, format, version, vendor, parameters)
    return NDevices.PluginNode(NDevices.PluginDevice(
        make_device_header(id, name, color, role, vendor),
        format,
        version,
        bool_parameter(id .. ":enabled", "Enabled", true),
        NCore.NoState,
        parameters or {}))
end

local function make_builtin_base(id, name, color, role, vendor, extra_parameters)
    return NDevices.BuiltinDevice(
        make_device_header(id, name, color, role, vendor),
        bool_parameter(id .. ":enabled", "Enabled", true),
        NCore.NoState,
        extra_parameters or {})
end

local function make_compressor(id, name, color)
    local base = make_builtin_base(id, name, color, Core.AudioFX, "Bitwig")
    return NDevices.CompressorNode(NDevices.Compressor(
        base,
        real_parameter(id .. ":threshold", "Threshold", Core.Decibel, -10, -60, 0),
        real_parameter(id .. ":ratio", "Ratio", Core.Linear, 4, 1, 20),
        real_parameter(id .. ":attack", "Attack", Core.SecondsUnit, 0.012, 0.001, 0.2),
        real_parameter(id .. ":release", "Release", Core.SecondsUnit, 0.08, 0.01, 1.5),
        real_parameter(id .. ":input", "Input", Core.Decibel, 0, -18, 18),
        real_parameter(id .. ":output", "Output", Core.Decibel, 0, -18, 18),
        bool_parameter(id .. ":auto_makeup", "Auto Makeup", true)))
end

local function make_eq(id, name, color)
    local base = make_builtin_base(id, name, color, Core.AudioFX, "Bitwig")
    return NDevices.EqualizerNode(NDevices.Equalizer(
        base,
        {
            NDevices.EqBand(Core.HighPass, 2,
                real_parameter(id .. ":hp:freq", "HP Freq", Core.Hertz, 38, 20, 20000),
                nil,
                real_parameter(id .. ":hp:q", "HP Q", Core.Linear, 0.71, 0.1, 24),
                bool_parameter(id .. ":hp:enabled", "HP Enabled", true)),
            NDevices.EqBand(Core.Bell, 2,
                real_parameter(id .. ":bell:freq", "Bell Freq", Core.Hertz, 2100, 20, 20000),
                real_parameter(id .. ":bell:gain", "Bell Gain", Core.Decibel, 2.5, -18, 18),
                real_parameter(id .. ":bell:q", "Bell Q", Core.Linear, 1.4, 0.1, 24),
                bool_parameter(id .. ":bell:enabled", "Bell Enabled", true)),
            NDevices.EqBand(Core.LowPass, 2,
                real_parameter(id .. ":lp:freq", "LP Freq", Core.Hertz, 16000, 20, 20000),
                nil,
                real_parameter(id .. ":lp:q", "LP Q", Core.Linear, 0.71, 0.1, 24),
                bool_parameter(id .. ":lp:enabled", "LP Enabled", true)),
        },
        real_parameter(id .. ":input", "Input", Core.Decibel, 0, -18, 18),
        real_parameter(id .. ":output", "Output", Core.Decibel, 0, -18, 18)))
end

local function make_limiter(id, name, color)
    local base = make_builtin_base(id, name, color, Core.AudioFX, "Bitwig")
    return NDevices.LimiterNode(NDevices.Limiter(
        base,
        real_parameter(id .. ":threshold", "Threshold", Core.Decibel, -0.2, -24, 0),
        real_parameter(id .. ":input", "Input", Core.Decibel, 0, -18, 18),
        real_parameter(id .. ":output", "Output", Core.Decibel, 0, -18, 18),
        real_parameter(id .. ":attack", "Attack", Core.SecondsUnit, 0.002, 0.0001, 0.1),
        real_parameter(id .. ":release", "Release", Core.SecondsUnit, 0.09, 0.01, 1.0)))
end

local function make_track(id, name, color, role, destination, content_type, volume, pan, sends, devices)
    return NMixer.Track(
        NCore.TrackHeader(id, name, color, nil, content_type, true),
        NMixer.Channel(
            NCore.ChannelHeader(id .. ":channel", name, color, nil, role, 2, false, destination),
            real_parameter(id .. ":volume", "Volume", Core.Decibel, volume or 0, -24, 12),
            real_parameter(id .. ":pan", "Pan", Core.Linear, pan or 0, -1, 1),
            bool_parameter(id .. ":mute", "Mute", false),
            sends or {},
            devices or {}),
        {})
end

local function make_send(id, name, destination, volume, pan)
    return NMixer.Send(
        NCore.SendHeader(id, name, nil, nil, Core.Post, destination),
        real_parameter(id .. ":volume", "Send Volume", Core.Decibel, volume or -8, -24, 12),
        real_parameter(id .. ":pan", "Send Pan", Core.Linear, pan or 0, -1, 1),
        bool_parameter(id .. ":enable", "Enable", true))
end

local function timeline_header(id, name, color, comment, track, time_unit)
    return NCore.TimelineHeader(id, name, color, comment, NCore.TimelineScope(track, time_unit or Core.Beats))
end

local function make_clip(id, name, color, start_beat, length_beat, reference)
    return NTimeline.Clip(
        NCore.Nameable(name, color, nil),
        NCore.ClipTiming(start_beat, length_beat),
        true,
        NCore.ClipContentTiming(Core.Beats, 0, length_beat, 0, length_beat),
        NCore.ClipFade(Core.Beats, 0.02, 0.04),
        NTimeline.Referenced(reference or id))
end

local function make_warped_clip(id, name, color, start_beat, length_beat, file_path)
    local audio = NTimeline.Audio(
        timeline_header(id .. ":audio", name, color, nil, nil, Core.Seconds),
        48000,
        2,
        "elastique-pro",
        length_beat,
        Root.FileReference(file_path, false))
    local warps = NTimeline.Warps(
        timeline_header(id .. ":warps", name, color, "warped vocal region", nil, Core.Beats),
        Core.Beats,
        {
            NTimeline.Warp(0, 0),
            NTimeline.Warp(length_beat * 0.45, length_beat * 0.34),
            NTimeline.Warp(length_beat, length_beat),
        },
        NTimeline.AudioNode(audio))
    return NTimeline.Clip(
        NCore.Nameable(name, color, "warp"),
        NCore.ClipTiming(start_beat, length_beat),
        true,
        NCore.ClipContentTiming(Core.Beats, 0, length_beat, 0, length_beat),
        NCore.ClipFade(Core.Beats, 0.03, 0.05),
        NTimeline.Embedded(NTimeline.WarpsNode(warps)))
end

local function make_clips_lane(id, name, color, track_id, clips)
    return NTimeline.ClipsNode(NTimeline.Clips(
        timeline_header(id, name, color, nil, track_id, Core.Beats),
        clips))
end

local function make_sample_project()
    local drums = make_track("trk:drums", "Drum Bus", hex_rgba8(C.blue), Core.Submix, "Master",
        { Core.AudioContent, Core.AutomationContent }, -2.5, 0.0, {}, {
            make_plugin("dev:drums:1", "Transient", hex_rgba8(C.blue), Core.AudioFX, Core.CLAP, "1.2.0", "Sonic Bits", {
                NParams.RealParam(real_parameter("dev:drums:1:mix", "Mix", Core.Percent, 72, 0, 100)),
                NParams.RealParam(real_parameter("dev:drums:1:punch", "Punch", Core.Percent, 65, 0, 100)),
            }),
            make_compressor("dev:drums:2", "Bus Comp", hex_rgba8(C.teal)),
            make_limiter("dev:drums:3", "Limiter", hex_rgba8(C.green)),
        })

    local bass = make_track("trk:bass", "Bass Synth", hex_rgba8(C.mauve), Core.Regular, "Drum Bus",
        { Core.NotesContent, Core.AudioContent, Core.AutomationContent }, -1.0, -0.12, {
            make_send("send:bass:return", "Cloud", "Cloud Return", -10, 0.08),
        }, {
            make_plugin("dev:bass:1", "Chord FX", hex_rgba8(C.teal), Core.NoteFX, Core.CLAP, "0.9.1", "Bitwig", {
                NParams.RealParam(real_parameter("dev:bass:1:spread", "Spread", Core.Percent, 40, 0, 100)),
            }),
            make_plugin("dev:bass:2", "Juno Voice", hex_rgba8(C.green), Core.Instrument, Core.VST3, "3.4.2", "TAL", {
                NParams.RealParam(real_parameter("dev:bass:2:cutoff", "Cutoff", Core.Hertz, 2200, 20, 20000)),
                NParams.RealParam(real_parameter("dev:bass:2:reso", "Resonance", Core.Linear, 0.22, 0, 1)),
            }),
            make_plugin("dev:bass:3", "Saturator", hex_rgba8(C.orange), Core.AudioFX, Core.CLAP, "2.0.0", "Goodhertz", {
                NParams.RealParam(real_parameter("dev:bass:3:drive", "Drive", Core.Decibel, 4.2, 0, 24)),
            }),
        })

    local vocal = make_track("trk:vocal", "Vox Chops", hex_rgba8(C.red), Core.Regular, "Master",
        { Core.AudioContent, Core.AutomationContent }, -4.0, 0.14, {
            make_send("send:vocal:return", "Cloud", "Cloud Return", -9, -0.04),
        }, {
            make_eq("dev:vocal:1", "Warp EQ", hex_rgba8(C.red)),
            make_plugin("dev:vocal:2", "Granulator", hex_rgba8(C.yellow), Core.AudioFX, Core.CLAP, "1.5.3", "Bitwig", {
                NParams.RealParam(real_parameter("dev:vocal:2:grain", "Grain", Core.SecondsUnit, 0.09, 0.005, 0.2)),
            }),
            make_plugin("dev:vocal:3", "Echo", hex_rgba8(C.orange), Core.AudioFX, Core.VST3, "5.1.0", "Valhalla", {
                NParams.RealParam(real_parameter("dev:vocal:3:feedback", "Feedback", Core.Percent, 33, 0, 100)),
            }),
        })

    local ret = make_track("trk:return", "Cloud Return", hex_rgba8(C.teal), Core.Effect, "Master",
        { Core.AudioContent }, -6.0, 0.0, {}, {
            make_plugin("dev:return:1", "Diffusion", hex_rgba8(C.teal), Core.AudioFX, Core.VST3, "1.0.4", "Valhalla", {
                NParams.RealParam(real_parameter("dev:return:1:decay", "Decay", Core.SecondsUnit, 2.4, 0.1, 20)),
            }),
            make_plugin("dev:return:2", "Meter", hex_rgba8(C.yellow), Core.Analyzer, Core.GenericPlugin, "0.3.0", "Bitwig", {
                NParams.BoolParam(bool_parameter("dev:return:2:peak", "Peak Hold", true)),
            }),
        })

    local arrangement = NTimeline.Arrangement(
        NCore.RefHeader("arr:main", NCore.Nameable("Main Arrangement", nil, "bitwig-like widget view")),
        nil,
        NAutomation.RealPoints(
            NAutomation.PointsHeader(timeline_header("tempo:auto", "Tempo", nil, nil, nil, Core.Beats)),
            NAutomation.ParameterTarget("transport:tempo"),
            Core.BPM,
            {
                NAutomation.RealPoint(0, 128, Core.Hold),
                NAutomation.RealPoint(4, 130, Core.LinearInterp),
                NAutomation.RealPoint(8, 128, Core.LinearInterp),
            }),
        NTimeline.Markers(
            timeline_header("markers", "Markers", nil, nil, nil, Core.Beats),
            {
                NTimeline.Marker(NCore.Nameable("Verse", hex_rgba8(C.blue), nil), 0),
                NTimeline.Marker(NCore.Nameable("Drop", hex_rgba8(C.orange), nil), 4),
            }),
        NTimeline.Lanes(
            timeline_header("lanes:main", "Main", nil, nil, nil, Core.Beats),
            {
                make_clips_lane("lane:drums", "Drums", hex_rgba8(C.blue), "trk:drums", {
                    make_clip("clip:drums:1", "Verse", hex_rgba8(C.blue), 0.0, 2.0, "drums/verse"),
                    make_clip("clip:drums:2", "Break", hex_rgba8(C.teal), 2.0, 1.5, "drums/break"),
                    make_clip("clip:drums:3", "Drop", hex_rgba8(C.green), 4.0, 3.5, "drums/drop"),
                }),
                make_clips_lane("lane:bass", "Bass", hex_rgba8(C.mauve), "trk:bass", {
                    make_clip("clip:bass:1", "Verse Riff", hex_rgba8(C.mauve), 0.0, 3.0, "bass/verse_riff"),
                    make_clip("clip:bass:2", "Drop Pulse", hex_rgba8(C.orange), 3.5, 4.0, "bass/drop_pulse"),
                }),
                make_clips_lane("lane:vocal", "Vocal", hex_rgba8(C.red), "trk:vocal", {
                    make_warped_clip("clip:vocal:1", "Hook A", hex_rgba8(C.red), 0.5, 1.25, "audio/hook_a.wav"),
                    make_warped_clip("clip:vocal:2", "Hook B", hex_rgba8(C.yellow), 2.5, 1.25, "audio/hook_b.wav"),
                    make_warped_clip("clip:vocal:3", "Lift", hex_rgba8(C.red), 5.5, 1.5, "audio/lift.wav"),
                }),
            }))

    return NProject.Project(
        "0.2.0",
        Root.Application("Bitwig Studio", "mock-compiler-demo"),
        Root.MetaData("Midnight Circuits", "Demo Artist", "Compiler Session", nil, nil, nil, nil, nil, "2026", "Electronica", nil, nil, "project normalized into widget view"),
        NProject.Transport(
            real_parameter("transport:tempo", "Tempo", Core.BPM, 128, 40, 220),
            NParams.TimeSignatureParameter(param_header("transport:ts", "Time Signature", nil), 4, 4)),
        {
            NProject.TrackNode(drums),
            NProject.TrackNode(bass),
            NProject.TrackNode(vocal),
            NProject.TrackNode(ret),
        },
        arrangement,
        {
            NTimeline.Scene(NCore.RefHeader("scene:a", NCore.Nameable("A", nil, nil)), {}),
        })
end

local PROJECT = make_sample_project()

local INITIAL_LOGS = {
    "installed callback from DawProto.Audio",
    "structural identity rides on ASDL unique nodes",
    "compiled machine identity follows structural sharing",
    "turning a knob writes state.live_params only",
    "rerouting or changing clips rebuilds the machine",
}

local ROUTES = { "Master", "Drum Bus", "Parallel", "Cloud Return" }

-- ─────────────────────────────────────────────────────────────
-- Layout constants
-- ─────────────────────────────────────────────────────────────

local TITLEBAR_H = 24
local TOPBAR_H = 54
local STATUS_H = 24
local BROWSER_RAIL_W = 160
local BROWSER_W = 430
local INSPECTOR_W = 270
local REMOTE_W = 250
local MIXER_W = 268
local DEVICE_H = 120
local HEADER_H = 24
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

local function toggle_string_member(seq, value)
    local out = {}
    local found = false
    for i = 1, #seq do
        local cur = seq[i]
        if cur == value then
            found = true
        else
            out[#out + 1] = cur
        end
    end
    if not found then
        out[#out + 1] = value
    end
    return out, not found
end

local function remove_prefixed(seq, prefix)
    local out = {}
    for i = 1, #seq do
        local cur = seq[i]
        if cur:sub(1, #prefix) ~= prefix then
            out[#out + 1] = cur
        end
    end
    return out
end

local function all_tracks(state)
    return state:tracks()
end

local function replace_track_tree(cur, target_id, replacement)
    if cur:track_id() == target_id then
        return replacement, true
    end

    local changed = false
    local children = cur.tracks
    local out = children
    for i = 1, #children do
        local next_child, child_changed = replace_track_tree(children[i], target_id, replacement)
        if child_changed then
            if not changed then
                out = copy_seq(children)
                changed = true
            end
            out[i] = next_child
        end
    end

    if changed then
        return pvm.with(cur, { tracks = out }), true
    end
    return cur, false
end

local function replace_track_at(state, index, track)
    local target = all_tracks(state)[index]
    if not target then
        return state
    end

    local target_id = target:track_id()
    local roots = state.project.structure
    local out = roots
    local changed = false

    for i = 1, #roots do
        local node = roots[i]
        if node.kind == "TrackNode" then
            local next_track, node_changed = replace_track_tree(node.track, target_id, track)
            if node_changed then
                if not changed then
                    out = copy_seq(roots)
                    changed = true
                end
                out[i] = NProject.TrackNode(next_track)
                break
            end
        end
    end

    if not changed then
        return state
    end

    return pvm.with(state, {
        project = pvm.with(state.project, { structure = out })
    })
end

local function selected_phase(state)
    return state:current_phase()
end

local function selected_track(state)
    return state:current_track()
end

local function parse_html_color(value, fallback)
    if type(value) ~= "string" then
        return fallback or C.surface1
    end
    local hex = value:match("^#([0-9a-fA-F]+)$")
    if not hex then
        return fallback or C.surface1
    end
    if #hex == 6 then
        hex = hex .. "ff"
    elseif #hex ~= 8 then
        return fallback or C.surface1
    end
    return tonumber(hex, 16) or fallback or C.surface1
end

local function track_name(track)
    return (track and track:display_name()) or "Track"
end

local function track_role(track)
    return (track and track:display_role()) or "track"
end

local function track_destination(track)
    return (track and track:destination_name()) or "Master"
end

local function track_devices(track)
    return (track and track:device_chain()) or {}
end

local function track_clips(state, track)
    return state:clips_for_track(track)
end

local function clip_name(clip)
    return (clip and clip:display_name()) or "Clip"
end

local function clip_start(clip)
    return (clip and clip:start_beat()) or 0
end

local function clip_length(clip)
    return (clip and clip:length_beat()) or 1
end

local function clip_warped(clip)
    return clip and clip:is_warped() or false
end

local function clip_color(clip, fallback)
    return parse_html_color(clip and clip:display_color() or nil, fallback)
end

local function device_name(device)
    return (device and device:display_name()) or "Device"
end

local function device_family(device)
    return (device and device:family_name()) or "Device"
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

local function fmt_clock(beats, bpm)
    local secs = (beats or 0) * 60 / math_max(1, bpm or 120)
    local mins = math_floor(secs / 60)
    local rem = secs - mins * 60
    return string_format("%d:%06.3f", mins, rem)
end

local function fmt_real_value(param)
    if not param then
        return "-"
    end
    local value = param.value
    local unit = param.unit and param.unit.kind or "Linear"
    if value == nil then
        return "-"
    elseif unit == "Decibel" then
        return fmt_db(value)
    elseif unit == "BPM" then
        return string_format("%.2f BPM", value)
    elseif unit == "Percent" then
        return string_format("%.0f%%", value)
    elseif unit == "Hertz" then
        return string_format("%.0f Hz", value)
    elseif unit == "SecondsUnit" then
        return string_format("%.3f s", value)
    end
    return string_format("%.2f", value)
end

local function meter_level(state, i)
    local gain = state.gains_db[i] or 0
    local base = state.playing and (0.33 + 0.22 * (0.5 + 0.5 * math_sin(state.time * 2.1 + i * 0.7))) or 0.06
    local shape = 0.16 * (0.5 + 0.5 * math_cos(state.time * 5.2 + i))
    return clamp(base + shape + ((gain + 12) / 24) * 0.22, 0.03, 1.0)
end

local function fallback_track_color(i)
    if i == 1 then return C.blue end
    if i == 2 then return C.green end
    if i == 3 then return C.red end
    return C.teal
end

local function track_color(track, i)
    if type(track) == "number" then
        i, track = track, nil
    end
    return parse_html_color(track and track.header and track.header.color or nil, fallback_track_color(i or 1))
end

local function device_color(family)
    if family == "Instrument" or family == "CLAP" then return C.green end
    if family == "NoteFX" then return C.teal end
    if family == "Analyzer" then return C.yellow end
    if family == "AudioFX" or family == "VST3" or family == "VST2" or family == "AU" then return C.blue end
    return C.orange
end

local function track_icon(role)
    if role == "group" then return "▣" end
    if role == "instrument" then return "◉" end
    if role == "audio" then return "◍" end
    if role == "return" then return "↺" end
    return "□"
end

local function mixer_label(track)
    local role = track_role(track)
    if role == "group" then return "DRUM" end
    if role == "instrument" then return "BASS" end
    if role == "audio" then return "VOX" end
    if role == "return" then return "RVRB" end
    return string_upper(track_name(track):sub(1, 5))
end

function M.build_view(state, layout, opts)
    local phase = selected_phase(state)
    local track = selected_track(state)
    local tracks = all_tracks(state)
    local project_title = (state.project.metadata and state.project.metadata.title) or "midnight circuits"
    local app_name = state.project.application and state.project.application.name or "Bitwig Studio"
    local buttons = {
        V.TransportButton("action:play", state.playing and "STOP" or "PLAY"),
        V.TransportButton("action:struct", "ROUTE"),
        V.TransportButton("action:live", "LIVE"),
        V.TransportButton("view:arrange", (state.selected_view == "arrange") and "[ARRANGE]" or "ARRANGE"),
        V.TransportButton("view:routing", (state.selected_view == "routing") and "[ROUTING]" or "ROUTING"),
        V.TransportButton("view:machine", (state.selected_view == "machine") and "[MACHINE]" or "MACHINE"),
        V.TransportButton("action:phase_prev", "<"),
        V.TransportButton("action:phase_next", ">"),
    }

    local launcher_rows = {}
    local arrangement_tracks = {}
    local arrangement_clips = {}
    local clip_index = 0
    for i = 1, #tracks do
        local t = tracks[i]
        local role = track_role(t)
        local clips = track_clips(state, t)
        local track_id = t:track_id()
        local muted = (t.channel and t.channel.mute and t.channel.mute.value) or false
        local solo = (t.channel and t.channel.header and t.channel.header.solo) or false
        local armed = state:is_track_armed(track_id)
        local buttons = {
            V.LauncherButton("launcher:track:" .. i .. ":mute", muted and "[M]" or "M"),
            V.LauncherButton("launcher:track:" .. i .. ":solo", solo and "[S]" or "S"),
            V.LauncherButton("launcher:track:" .. i .. ":arm", armed and "[R]" or "R"),
        }
        local slots = {
            V.LauncherSlot("launcher:track:" .. i .. ":slot:1", (state:is_slot_launched("launcher:track:" .. i .. ":slot:1") and "> " or "") .. (clips[1] and clip_name(clips[1]) or "Scene 1")),
            V.LauncherSlot("launcher:track:" .. i .. ":slot:2", (state:is_slot_launched("launcher:track:" .. i .. ":slot:2") and "> " or "") .. (clips[2] and clip_name(clips[2]) or "Scene 2")),
        }
        launcher_rows[i] = V.LauncherTrackRow(
            i,
            "browser:track:" .. i,
            track_icon(role),
            ((i == state.selected_track) and "> " or "  ") .. track_icon(role) .. "  " .. track_name(t),
            string_format("%s  →  %s", role, track_destination(t)),
            fmt_db(state.gains_db[i]),
            buttons,
            slots)
        arrangement_tracks[i] = V.ArrangementTrackRow(
            i,
            "arr:track:" .. i,
            (i == state.selected_track) and ("> " .. track_name(t)) or ("  " .. track_name(t)),
            role,
            track_destination(t),
            track_color(t, i))
        for j = 1, #clips do
            clip_index = clip_index + 1
            if clip_index <= CLIP_CAP then
                local c = clips[j]
                arrangement_clips[clip_index] = V.ArrangementClip(
                    clip_index,
                    c.meta.name or ("clip:" .. clip_index),
                    i,
                    clip_name(c),
                    clip_start(c),
                    clip_length(c),
                    clip_color(c, track_color(t, i)),
                    clip_warped(c))
            end
        end
    end

    local device_cards = {}
    local devices = track_devices(track)
    for i = 1, #devices do
        local d = devices[i]
        local header = d:header()
        device_cards[i] = V.DeviceCard(i, header.id or ("dev:" .. i), device_name(d), device_family(d), d:is_active())
    end

    local channel = track.channel
    local inspector_sections = {
        V.InspectorSection("TRACK", {
            V.ValueField("Name", track_name(track), true),
            V.ValueField("Role", track_role(track), false),
            V.ValueField("Destination", track_destination(track), false),
        }),
        V.InspectorSection("CHANNEL", {
            V.ValueField("Volume", fmt_real_value(channel and channel.volume), true),
            V.ValueField("Pan", fmt_real_value(channel and channel.pan), false),
            V.ToggleField("Mute", (channel and channel.mute and channel.mute.value) or false, false),
        }),
        V.InspectorSection("COMPILE", {
            V.ValueField("Stage", phase.title, true),
            V.ChoiceField("Mode", state.selected_view, { "arrange", "routing", "machine" }, false),
            V.LiveValueField("Reuse", SLOT_REUSE, false),
        }),
    }

    local arrange_title = (state.selected_view == "arrange") and "ARRANGEMENT"
        or (state.selected_view == "routing") and "ROUTING OVERLAY"
        or "MACHINE OVERLAY"
    local arrange_note = (state.selected_view == "arrange") and "clips / automation / playhead"
        or (state.selected_view == "routing") and "routing and send topology"
        or "compiled slices / jobs / state families"

    return V.Window(
        V.TitleBar("DEMO", app_name .. " - " .. project_title, string_format("callback #%d", state.compile_gen)),
        V.TransportBar(
            string_format(" stage · %s", phase.verb),
            string_format("%.2f", state.bpm),
            "4/4",
            SLOT_CLOCK,
            buttons),
        V.BrowserRail("DETAIL", project_title, "No item selected"),
        V.LauncherPanel("PROJECT", "SCENE 1", "SCENE 2", launcher_rows),
        V.ArrangementPanel(arrange_title, arrange_note, state.selected_view, TIMELINE_BEATS, arrangement_tracks, arrangement_clips, SLOT_ARRANGEMENT_OVERLAY),
        V.InspectorPanel("PROJECT PANEL", inspector_sections),
        V.DevicesPanel("DEVICE CHAIN", SLOT_DEVICES_SUBTITLE, device_cards, SLOT_DEVICES_OVERLAY),
        V.RemotePanel("PROJECT REMOTES", "No Pages", "+"),
        V.StatusBar(
            string_format(" mode %s   ·   phase %s   ·   track %s ", state.selected_view, phase.title, track_name(track)),
            SLOT_STATUS_RIGHT))
end

function M.build_tree(state, layout, opts)
    local focused_id = opts and opts.focused_id or ""
    local view = (opts and opts.view) or M.build_view(state, layout, opts)
    return demo_lower.node(THEME, view, { focused_id = focused_id })
end

-- ─────────────────────────────────────────────────────────────
-- Runtime build
-- ─────────────────────────────────────────────────────────────

function M.compute_layout(w, h)
    local upper_h = math_max(0, h - TITLEBAR_H - TOPBAR_H - DEVICE_H - STATUS_H)
    local arrange_w = math_max(240, w - BROWSER_RAIL_W - BROWSER_W - INSPECTOR_W)
    local device_w = math_max(240, w - REMOTE_W)
    return {
        width = w,
        height = h,
        body_h = upper_h,
        center_w = arrange_w,
        arrange_h = upper_h,
        arrange_w = arrange_w,
        device_h = DEVICE_H,
        device_w = device_w,
        browser_rail_w = BROWSER_RAIL_W,
        launcher_w = BROWSER_W,
        inspector_w = INSPECTOR_W,
        remote_w = REMOTE_W,
    }
end

function M.build_live(state, layout, opts)
    opts = opts or {}
    local phase = selected_phase(state)
    local track = selected_track(state)
    return LiveWindow(
        LiveTexts(
            fmt_clock(state.transport_beat, state.bpm),
            fmt_percent(state.reuse),
            string_format("%s · %s", track_name(track), phase.title),
            string_format(" compile #%d   reuse %s   cpu %.1f%% ", state.compile_gen, fmt_percent(state.reuse), state.cpu_usage)),
        LiveArrangement(
            state.transport_beat,
            state.time,
            state.selected_track,
            state.selected_view),
        LiveDevices(
            state.selected_track,
            phase.title,
            phase.verb,
            state.compile_gen,
            state.reuse,
            state.time,
            state.logs))
end

function M.build_runtime(state, layout, opts)
    return M.build_live(state, layout, opts)
end

function M.resolve_runtime_text(node, opts)
    return demo_bind.resolve_runtime_text(node, opts)
end

function M.draw_custom_paint(node, active_id, ctx, api)
    return demo_bind.draw_custom_paint(node, active_id, ctx, api)
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
        4,
        18,
        "warm callback installed",
        { -2.5, -1.0, -4.0, -6.0 },
        { 0.0, -0.12, 0.14, 0.0 },
        PHASES,
        PROJECT,
        {},
        {},
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
    index = clamp(index, 1, #all_tracks(state))
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
    local track = all_tracks(state)[index]
    local channel = track.channel
    local new_dest = next_route(track_destination(track))
    local new_header = NCore.ChannelHeader(
        channel.header.id,
        channel.header.name,
        channel.header.color,
        channel.header.comment,
        channel.header.role,
        channel.header.audio_channels,
        channel.header.solo,
        new_dest)
    local new_channel = NMixer.Channel(
        new_header,
        channel.volume,
        channel.pan,
        channel.mute,
        channel.sends,
        rotate_devices(track_devices(track)))
    local new_track = NMixer.Track(track.header, new_channel, track.tracks)
    state = replace_track_at(state, index, new_track)
    state = pvm.with(state, {
        compile_gen = state.compile_gen + 1,
        structural_edits = state.structural_edits + 1,
        reuse = 0.84 + ((state.compile_gen % 4) * 0.03),
        last_compile_kind = "structural edit → rebuild schedule → compile new callback",
    })
    state = append_log(state, string_format("%s rerouted to %s → new machine shape → compile #%d", track_name(track), new_dest, state.compile_gen))
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
        reuse = 1.0,
        last_compile_kind = "live tweak → mutate state.live_params only",
    })
    state = append_log(state, string_format("%s live tweak → %s / %s (no recompile)", track_name(all_tracks(state)[index]), fmt_db(gains[index]), fmt_pan(pans[index])))
    return state
end

local function toggle_track_mute(state, index)
    local track = all_tracks(state)[index]
    local channel = track and track.channel
    if not channel or not channel.mute then
        return state
    end
    local new_mute = NParams.BoolParameter(channel.mute.header, not (channel.mute.value or false))
    local new_channel = NMixer.Channel(channel.header, channel.volume, channel.pan, new_mute, channel.sends, channel.devices)
    local new_track = NMixer.Track(track.header, new_channel, track.tracks)
    state = replace_track_at(state, index, new_track)
    state = pvm.with(state, { selected_track = index })
    state = append_log(state, string_format("%s mute %s", track_name(track), new_mute.value and "enabled" or "disabled"))
    return touch(state)
end

local function toggle_track_solo(state, index)
    local track = all_tracks(state)[index]
    local channel = track and track.channel
    if not channel then
        return state
    end
    local header = channel.header
    local new_header = NCore.ChannelHeader(
        header.id,
        header.name,
        header.color,
        header.comment,
        header.role,
        header.audio_channels,
        not header.solo,
        header.destination)
    local new_channel = NMixer.Channel(new_header, channel.volume, channel.pan, channel.mute, channel.sends, channel.devices)
    local new_track = NMixer.Track(track.header, new_channel, track.tracks)
    state = replace_track_at(state, index, new_track)
    state = pvm.with(state, { selected_track = index })
    state = append_log(state, string_format("%s solo %s", track_name(track), new_header.solo and "enabled" or "disabled"))
    return touch(state)
end

local function toggle_track_arm(state, index)
    local track = all_tracks(state)[index]
    if not track then
        return state
    end
    local armed_tracks, armed = toggle_string_member(state.armed_tracks, track:track_id())
    state = pvm.with(state, {
        selected_track = index,
        armed_tracks = armed_tracks,
    })
    state = append_log(state, string_format("%s record arm %s", track_name(track), armed and "enabled" or "disabled"))
    return touch(state)
end

local function launch_slot(state, index, slot_index)
    local track = all_tracks(state)[index]
    if not track then
        return state
    end
    local clips = track_clips(state, track)
    local clip = clips[slot_index]
    local slot_id = string_format("launcher:track:%d:slot:%d", index, slot_index)
    local prefix = string_format("launcher:track:%d:slot:", index)
    local launched = remove_prefixed(state.launched_slots, prefix)
    local activated = not state:is_slot_launched(slot_id)
    if activated and clip then
        launched[#launched + 1] = slot_id
    end
    state = pvm.with(state, {
        selected_track = index,
        launched_slots = launched,
        playing = clip and activated and true or state.playing,
    })
    if clip then
        state = append_log(state, string_format("%s %s on %s", activated and "launched" or "stopped", clip_name(clip), track_name(track)))
    else
        state = append_log(state, string_format("%s slot %d is empty", track_name(track), slot_index))
    end
    return touch(state)
end

function M.update(state, dt)
    local time = state.time + dt
    local transport = state.transport_beat
    if state.playing then
        transport = transport + dt * (state.bpm / 60)
    end

    local cpu = 11 + (state.playing and 9 or 2) + math_abs(math_sin(time * 1.7)) * 7
    local reuse = state.reuse
    if reuse < 0.999 then
        reuse = math_min(1.0, reuse + dt * 0.08)
    end

    return pvm.with(state, {
        time = time,
        transport_beat = transport,
        cpu_usage = cpu,
        reuse = reuse,
    })
end

function M.handle_event(state, event, layout)
    if event.kind == T.Msg.Click or event.kind == T.Msg.Submit then
        local slot_track, slot_index = event.id:match("^launcher:track:(%d+):slot:(%d+)$")
        if slot_track then
            return launch_slot(state, tonumber(slot_track), tonumber(slot_index))
        end

        local launcher_track, launcher_action = event.id:match("^launcher:track:(%d+):([%a_]+)$")
        if launcher_track then
            local index = tonumber(launcher_track)
            if launcher_action == "mute" then
                return toggle_track_mute(state, index)
            elseif launcher_action == "solo" then
                return toggle_track_solo(state, index)
            elseif launcher_action == "arm" then
                return toggle_track_arm(state, index)
            end
        end

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
    local view = M.build_view(state, layout, opts)
    local ui_node, sem = M.build_tree(state, layout, { focused_id = opts and opts.focused_id or "", view = view })
    return ui_node, M.build_runtime(state, layout, { view = view }), layout, sem
end

function M.footer(state)
    local phase = selected_phase(state)
    local track = selected_track(state)
    local left = string_format("mode %s   phase %s   track %s", state.selected_view, phase.title, track_name(track))
    local right = string_format("compile #%d   reuse %s   cpu %.1f%%", state.compile_gen, fmt_percent(state.reuse), state.cpu_usage)
    return left, right
end

return M
