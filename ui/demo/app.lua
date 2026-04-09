-- ui/demo/app.lua
--
-- Pure demo application model / theme / view builder for the fresh UI stack.
-- Love2D glue lives in `ui/demo/main.lua`; this file is intentionally plain Lua
-- so the authored UI and runtime shaping can be smoke-tested without Love.

local ui = require("ui.init")

local T = ui.T
local ds = ui.ds
local lower = ui.lower

local M = { ui = ui, T = T, ds = ds, lower = lower }

local math_abs = math.abs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_sin = math.sin
local math_random = math.random

-- ─────────────────────────────────────────────────────────────
-- Theme constants
-- ─────────────────────────────────────────────────────────────

local C = {
    bg0 = 0x07111cff,
    bg1 = 0x0d1726ff,
    bg2 = 0x102033ff,
    panel = 0x102033ee,
    panel_hi = 0x152741ff,
    panel_press = 0x0d1829ff,
    panel_active = 0x132b40ff,
    border = 0x223755ff,
    border_hi = 0x39557dff,
    fg = 0xe8f0ffff,
    muted = 0x86a0c4ff,
    dim = 0x5d7698ff,
    accent = 0x68d5ffff,
    accent_hi = 0x9ceaffff,
    accent_soft = 0x163a56ff,
    accent2 = 0xff96d8ff,
    good = 0x79f3a6ff,
    warn = 0xffcf7cff,
    danger = 0xff7f9eff,
    gold = 0xffe69aff,
    line = 0x17324cff,
}

local S = {
    bw = 1,
    radius = 14,
    shell_pad = 18,
    panel_pad = 14,
    panel_gap = 14,
    button_pad_h = 12,
    button_pad_v = 10,
    chip_pad_h = 8,
    chip_pad_v = 5,
}

local FONT_HEIGHTS = {
    [0] = 14,
    [1] = 14,
    [2] = 24,
    [3] = 46,
    [4] = 12,
}

function M.font_height(font_id)
    return FONT_HEIGHTS[font_id] or 14
end

function M.font_sizes()
    return FONT_HEIGHTS
end

local FLAG_ACTIVE = ds.flag("active")

local function flags_active(active)
    return active and { FLAG_ACTIVE } or {}
end

local THEME = ds.theme("aurora-control", {
    colors = {
        { "bg0", C.bg0 },
        { "bg1", C.bg1 },
        { "bg2", C.bg2 },
        { "panel", C.panel },
        { "panel_hi", C.panel_hi },
        { "panel_press", C.panel_press },
        { "panel_active", C.panel_active },
        { "border", C.border },
        { "border_hi", C.border_hi },
        { "fg", C.fg },
        { "muted", C.muted },
        { "dim", C.dim },
        { "accent", C.accent },
        { "accent_hi", C.accent_hi },
        { "accent_soft", C.accent_soft },
        { "accent2", C.accent2 },
        { "good", C.good },
        { "warn", C.warn },
        { "danger", C.danger },
        { "gold", C.gold },
        { "line", C.line },
    },
    spaces = {
        { "bw", S.bw },
        { "radius", S.radius },
        { "shell_pad", S.shell_pad },
        { "panel_pad", S.panel_pad },
        { "panel_gap", S.panel_gap },
        { "button_pad_h", S.button_pad_h },
        { "button_pad_v", S.button_pad_v },
        { "chip_pad_h", S.chip_pad_h },
        { "chip_pad_v", S.chip_pad_v },
    },
    fonts = {
        { "body", 1 },
        { "title", 2 },
        { "hero", 3 },
        { "mono", 4 },
    },
    surfaces = {
        ds.surface("shell", {
            ds.paint_rule(ds.paint_sel(), {
                ds.bg(ds.ctok("bg0")),
                ds.border_color(ds.ctok("bg0")),
                ds.radius(ds.slit(0)),
                ds.fg(ds.ctok("fg")),
            }),
        }, {
            ds.metric_rule(ds.state_sel(), {
                ds.pad_h(ds.stok("shell_pad")),
                ds.pad_v(ds.stok("shell_pad")),
                ds.border_w(ds.slit(0)),
            }),
        }, {
            ds.text_rule(ds.state_sel(), {
                ds.font(ds.ftok("body")),
                ds.line_height(T.Layout.LineHeightPx(16)),
                ds.text_align(T.Layout.TextStart),
                ds.text_wrap(T.Layout.TextNoWrap),
            }),
        }),

        ds.surface("panel", {
            ds.paint_rule(ds.paint_sel(), {
                ds.bg(ds.ctok("panel")),
                ds.border_color(ds.ctok("border")),
                ds.radius(ds.stok("radius")),
                ds.fg(ds.ctok("fg")),
            }),
            ds.paint_rule(ds.paint_sel({ flags = { "active" } }), {
                ds.bg(ds.ctok("panel_active")),
                ds.border_color(ds.ctok("accent")),
            }),
            ds.paint_rule(ds.paint_sel({ focus = "focused" }), {
                ds.border_color(ds.ctok("accent2")),
            }),
        }, {
            ds.metric_rule(ds.state_sel(), {
                ds.pad_h(ds.stok("panel_pad")),
                ds.pad_v(ds.stok("panel_pad")),
                ds.gap(ds.stok("panel_gap")),
                ds.gap_cross(ds.stok("panel_gap")),
                ds.border_w(ds.stok("bw")),
            }),
        }, {
            ds.text_rule(ds.state_sel(), {
                ds.font(ds.ftok("body")),
                ds.line_height(T.Layout.LineHeightPx(16)),
                ds.text_align(T.Layout.TextStart),
                ds.text_wrap(T.Layout.TextNoWrap),
            }),
        }),

        ds.surface("hero", {
            ds.paint_rule(ds.paint_sel(), {
                ds.bg(ds.ctok("bg1")),
                ds.border_color(ds.ctok("accent")),
                ds.radius(ds.stok("radius")),
                ds.fg(ds.ctok("fg")),
            }),
            ds.paint_rule(ds.paint_sel({ flags = { "active" } }), {
                ds.border_color(ds.ctok("accent2")),
            }),
        }, {
            ds.metric_rule(ds.state_sel(), {
                ds.pad_h(ds.slit(20)),
                ds.pad_v(ds.slit(18)),
                ds.gap(ds.slit(12)),
                ds.gap_cross(ds.slit(12)),
                ds.border_w(ds.stok("bw")),
            }),
        }, {
            ds.text_rule(ds.state_sel(), {
                ds.font(ds.ftok("body")),
                ds.line_height(T.Layout.LineHeightPx(18)),
                ds.text_align(T.Layout.TextStart),
                ds.text_wrap(T.Layout.TextNoWrap),
            }),
        }),

        ds.surface("nav", {
            ds.paint_rule(ds.paint_sel(), {
                ds.bg(ds.ctok("panel")),
                ds.border_color(ds.ctok("border")),
                ds.radius(ds.stok("radius")),
                ds.fg(ds.ctok("muted")),
            }),
            ds.paint_rule(ds.paint_sel({ pointer = "hovered" }), {
                ds.bg(ds.ctok("panel_hi")),
                ds.border_color(ds.ctok("border_hi")),
                ds.fg(ds.ctok("fg")),
            }),
            ds.paint_rule(ds.paint_sel({ pointer = "pressed" }), {
                ds.bg(ds.ctok("accent_soft")),
                ds.border_color(ds.ctok("accent")),
                ds.fg(ds.ctok("fg")),
            }),
            ds.paint_rule(ds.paint_sel({ flags = { "active" } }), {
                ds.bg(ds.ctok("accent_soft")),
                ds.border_color(ds.ctok("accent")),
                ds.fg(ds.ctok("accent_hi")),
            }),
            ds.paint_rule(ds.paint_sel({ focus = "focused" }), {
                ds.border_color(ds.ctok("accent2")),
            }),
        }, {
            ds.metric_rule(ds.state_sel(), {
                ds.pad_h(ds.stok("button_pad_h")),
                ds.pad_v(ds.stok("button_pad_v")),
                ds.border_w(ds.stok("bw")),
            }),
        }, {
            ds.text_rule(ds.state_sel(), {
                ds.font(ds.ftok("title")),
                ds.line_height(T.Layout.LineHeightPx(18)),
                ds.text_align(T.Layout.TextStart),
                ds.text_wrap(T.Layout.TextNoWrap),
            }),
        }),

        ds.surface("button", {
            ds.paint_rule(ds.paint_sel(), {
                ds.bg(ds.ctok("panel")),
                ds.border_color(ds.ctok("border")),
                ds.radius(ds.stok("radius")),
                ds.fg(ds.ctok("fg")),
            }),
            ds.paint_rule(ds.paint_sel({ pointer = "hovered" }), {
                ds.bg(ds.ctok("panel_hi")),
                ds.border_color(ds.ctok("border_hi")),
            }),
            ds.paint_rule(ds.paint_sel({ pointer = "pressed" }), {
                ds.bg(ds.ctok("accent_soft")),
                ds.border_color(ds.ctok("accent")),
            }),
            ds.paint_rule(ds.paint_sel({ flags = { "active" } }), {
                ds.bg(ds.ctok("accent_soft")),
                ds.border_color(ds.ctok("accent")),
                ds.fg(ds.ctok("accent_hi")),
            }),
            ds.paint_rule(ds.paint_sel({ focus = "focused" }), {
                ds.border_color(ds.ctok("accent2")),
            }),
        }, {
            ds.metric_rule(ds.state_sel(), {
                ds.pad_h(ds.stok("button_pad_h")),
                ds.pad_v(ds.stok("button_pad_v")),
                ds.border_w(ds.stok("bw")),
            }),
        }, {
            ds.text_rule(ds.state_sel(), {
                ds.font(ds.ftok("body")),
                ds.line_height(T.Layout.LineHeightPx(16)),
                ds.text_align(T.Layout.TextCenter),
                ds.text_wrap(T.Layout.TextNoWrap),
            }),
        }),

        ds.surface("chip", {
            ds.paint_rule(ds.paint_sel(), {
                ds.bg(ds.ctok("bg2")),
                ds.border_color(ds.ctok("border")),
                ds.radius(ds.slit(999)),
                ds.fg(ds.ctok("muted")),
            }),
            ds.paint_rule(ds.paint_sel({ flags = { "active" } }), {
                ds.bg(ds.ctok("accent_soft")),
                ds.border_color(ds.ctok("accent")),
                ds.fg(ds.ctok("accent_hi")),
            }),
        }, {
            ds.metric_rule(ds.state_sel(), {
                ds.pad_h(ds.stok("chip_pad_h")),
                ds.pad_v(ds.stok("chip_pad_v")),
                ds.border_w(ds.stok("bw")),
            }),
        }, {
            ds.text_rule(ds.state_sel(), {
                ds.font(ds.ftok("mono")),
                ds.line_height(T.Layout.LineHeightPx(12)),
                ds.text_align(T.Layout.TextCenter),
                ds.text_wrap(T.Layout.TextNoWrap),
            }),
        }),

        ds.surface("logline", {
            ds.paint_rule(ds.paint_sel(), {
                ds.bg(ds.clit(0)),
                ds.border_color(ds.clit(0)),
                ds.radius(ds.slit(8)),
                ds.fg(ds.ctok("muted")),
            }),
        }, {
            ds.metric_rule(ds.state_sel(), {
                ds.pad_h(ds.slit(8)),
                ds.pad_v(ds.slit(6)),
                ds.border_w(ds.slit(0)),
            }),
        }, {
            ds.text_rule(ds.state_sel(), {
                ds.font(ds.ftok("mono")),
                ds.line_height(T.Layout.LineHeightPx(12)),
                ds.text_align(T.Layout.TextStart),
                ds.text_wrap(T.Layout.TextNoWrap),
            }),
        }),
    },
})

M.theme = THEME

-- ─────────────────────────────────────────────────────────────
-- Typed shortcuts / layout helpers
-- ─────────────────────────────────────────────────────────────

local L = T.Layout
local U = T.SemUI
local P = T.Paint
local R = T.Runtime

local AXIS_ROW = L.AxisRow
local AXIS_COL = L.AxisCol
local WRAP_NO = L.WrapNoWrap
local WRAP_WRAP = L.WrapWrap
local MAIN_START = L.MainStart
local MAIN_CENTER = L.MainCenter
local CROSS_START = L.CrossStart
local CROSS_CENTER = L.CrossCenter
local CROSS_STRETCH = L.CrossStretch
local CONTENT_START = L.ContentStart

local SCROLL_Y = L.ScrollY

local SIZE_AUTO = L.SizeAuto
local SIZE_CONTENT = L.SizeContent
local NO_MIN = L.NoMin
local NO_MAX = L.NoMax
local BASIS_AUTO = L.BasisAuto
local CROSS_AUTO = L.CrossAuto

local USE_FONT = U.UseSurfaceFont
local USE_LINE_HEIGHT = U.UseSurfaceLineHeight
local USE_ALIGN = U.UseSurfaceTextAlign
local USE_WRAP = U.UseSurfaceTextWrap
local USE_OVERFLOW = U.UseSurfaceOverflow
local USE_LINE_LIMIT = U.UseSurfaceLineLimit

local ZERO_INSETS = L.Insets(0, 0, 0, 0)
local FILL_BOX = L.Box(L.SizePercent(1), L.SizePercent(1), NO_MIN, NO_MIN, NO_MAX, NO_MAX)
local AUTO_BOX = L.Box(SIZE_AUTO, SIZE_AUTO, NO_MIN, NO_MIN, NO_MAX, NO_MAX)
local FILL_W_BOX = L.Box(L.SizePercent(1), SIZE_AUTO, NO_MIN, NO_MIN, NO_MAX, NO_MAX)

local LEFT_W = 248
local RIGHT_W = 320
local ROOT_GAP = 18
local HERO_H = 244
local TRANSPORT_H = 84
local CHANNEL_CARD_W = 472
local CHANNEL_CARD_H = 164
local CHANNEL_GAP = 16
local PANEL_INSET = S.panel_pad + S.bw
local LOG_HEADER_H = 82
local METER_H = 34
local METER_W = CHANNEL_CARD_W - PANEL_INSET * 2 - 4

local BODY_TEXT = U.TextSpec(USE_FONT, USE_LINE_HEIGHT, USE_ALIGN, USE_WRAP, USE_OVERFLOW, USE_LINE_LIMIT)
local LABEL_TEXT = U.TextSpec(
    USE_FONT,
    U.OverrideLineHeight(L.LineHeightPx(16)),
    USE_ALIGN,
    USE_WRAP,
    USE_OVERFLOW,
    USE_LINE_LIMIT)
local CENTER_TEXT = U.TextSpec(
    USE_FONT,
    USE_LINE_HEIGHT,
    U.OverrideTextAlign(L.TextCenter),
    USE_WRAP,
    USE_OVERFLOW,
    USE_LINE_LIMIT)
local MONO_TEXT = U.TextSpec(
    U.OverrideFont(ds.ftok("mono")),
    U.OverrideLineHeight(L.LineHeightPx(12)),
    USE_ALIGN,
    USE_WRAP,
    USE_OVERFLOW,
    USE_LINE_LIMIT)
local HERO_TITLE_TEXT = U.TextSpec(
    U.OverrideFont(ds.ftok("hero")),
    U.OverrideLineHeight(L.LineHeightPx(46)),
    USE_ALIGN,
    USE_WRAP,
    USE_OVERFLOW,
    U.OverrideLineLimit(L.MaxLines(1)))
local HERO_BODY_TEXT = U.TextSpec(
    U.OverrideFont(ds.ftok("body")),
    U.OverrideLineHeight(L.LineHeightPx(18)),
    USE_ALIGN,
    U.OverrideTextWrap(L.TextWordWrap),
    USE_OVERFLOW,
    U.OverrideLineLimit(L.MaxLines(3)))
local WRAP_BODY_TEXT = U.TextSpec(
    U.OverrideFont(ds.ftok("body")),
    U.OverrideLineHeight(L.LineHeightPx(16)),
    USE_ALIGN,
    U.OverrideTextWrap(L.TextWordWrap),
    USE_OVERFLOW,
    U.OverrideLineLimit(L.MaxLines(4)))
local TITLE_TEXT = U.TextSpec(
    U.OverrideFont(ds.ftok("title")),
    U.OverrideLineHeight(L.LineHeightPx(24)),
    USE_ALIGN,
    USE_WRAP,
    USE_OVERFLOW,
    U.OverrideLineLimit(L.MaxLines(1)))

local function insets_all(px)
    return L.Insets(px, px, px, px)
end

local function box_px(w, h)
    return L.Box(L.SizePx(w), L.SizePx(h), NO_MIN, NO_MIN, NO_MAX, NO_MAX)
end

local function box_w(w)
    return L.Box(L.SizePx(w), SIZE_AUTO, NO_MIN, NO_MIN, NO_MAX, NO_MAX)
end

local function box_h(h)
    return L.Box(SIZE_AUTO, L.SizePx(h), NO_MIN, NO_MIN, NO_MAX, NO_MAX)
end

local function fill_w_h(h)
    return L.Box(L.SizePercent(1), L.SizePx(h), NO_MIN, NO_MIN, NO_MAX, NO_MAX)
end

local function item(node, grow, shrink, basis, self_align, margin)
    return U.FlexItem(node, grow or 0, shrink or 0, basis or BASIS_AUTO, self_align or CROSS_AUTO, margin or ZERO_INSETS)
end

local function row(box, children, opts)
    opts = opts or {}
    return U.Flex(
        AXIS_ROW,
        opts.wrap or WRAP_NO,
        opts.gap_main or 0,
        opts.gap_cross or 0,
        opts.justify or MAIN_START,
        opts.align_items or CROSS_START,
        opts.align_content or CONTENT_START,
        box,
        children)
end

local function col(box, children, opts)
    opts = opts or {}
    return U.Flex(
        AXIS_COL,
        opts.wrap or WRAP_NO,
        opts.gap_main or 0,
        opts.gap_cross or 0,
        opts.justify or MAIN_START,
        opts.align_items or CROSS_START,
        opts.align_content or CONTENT_START,
        box,
        children)
end

local function center_box(box, child)
    return col(box, {
        item(child, 1, 1, BASIS_AUTO, CROSS_CENTER),
    }, {
        justify = MAIN_CENTER,
        align_items = CROSS_CENTER,
        align_content = CONTENT_START,
    })
end

local function text(tag, box, spec, value)
    return U.Text(tag or "", box or AUTO_BOX, spec or BODY_TEXT, value or "")
end

local function panel(surface_name, flags, id, scroll_y, box, child)
    return U.Surface(surface_name, flags or {}, U.ScrollArea(id or "", SCROLL_Y, 0, scroll_y or 0, box, child))
end

local function button(surface_name, id, label, box, active)
    return U.Focusable(id,
        U.Pressable(id,
            panel(surface_name or "button", flags_active(active), "", 0, box,
                center_box(FILL_BOX, text(id .. ":label", AUTO_BOX, CENTER_TEXT, label)))))
end

local function chip(label, active)
    return panel("chip", flags_active(active), "", 0, box_px(74, 26), center_box(FILL_BOX, text("", AUTO_BOX, CENTER_TEXT, label)))
end

local function ref_num(name)
    return P.ScalarFromRef(R.NumRef(name))
end

local function scalar(n)
    return P.ScalarLit(n)
end

local function color_pack(rgba8)
    return P.ColorPackLit(ds.solid(rgba8))
end

local function text_ref(name)
    return P.TextFromRef(R.TextRef(name))
end

local function dynamic_text_box(ref_name, w, h, font_id, line_height, align, rgba8)
    return U.CustomPaint(
        ref_name,
        box_px(w, h),
        P.Text(
            "",
            scalar(0),
            scalar(0),
            scalar(w),
            scalar(h),
            font_id,
            color_pack(rgba8),
            line_height,
            align,
            L.TextNoWrap,
            L.OverflowVisible,
            L.MaxLines(1),
            text_ref(ref_name)))
end

local HERO_BARS = 28
local hero_paint_cache = {}
local meter_paint_cache = {}
local backdrop_paint_cache = {}

local function hero_paint()
    local hit = hero_paint_cache[1]
    if hit then
        return hit
    end

    local children = {}
    for i = 0, 3 do
        children[#children + 1] = P.Line(
            "",
            scalar(0),
            ref_num("hero:grid:y:" .. i),
            ref_num("hero:w"),
            ref_num("hero:grid:y:" .. i),
            scalar(1),
            color_pack(C.line))
    end

    for i = 1, HERO_BARS do
        local color = (i % 5 == 0) and C.accent2 or ((i % 3 == 0) and C.good or C.accent)
        children[#children + 1] = P.FillRect(
            "",
            ref_num("hero:bar:" .. i .. ":x"),
            ref_num("hero:bar:" .. i .. ":y"),
            ref_num("hero:bar:" .. i .. ":w"),
            ref_num("hero:bar:" .. i .. ":h"),
            color_pack(color))
    end

    children[#children + 1] = P.FillRect("", scalar(0), ref_num("hero:scan:y"), ref_num("hero:w"), scalar(2), color_pack(C.accent_hi))
    children[#children + 1] = P.StrokeRect("", scalar(0), scalar(0), ref_num("hero:w"), ref_num("hero:h"), scalar(1), color_pack(C.border_hi))

    hit = P.Group(children)
    hero_paint_cache[1] = hit
    return hit
end

local function meter_paint(prefix, fill_rgba8)
    local key = prefix .. ":" .. fill_rgba8
    local hit = meter_paint_cache[key]
    if hit then
        return hit
    end

    hit = P.Group({
        P.FillRect("", scalar(0), scalar(0), ref_num(prefix .. ":w"), ref_num(prefix .. ":h"), color_pack(C.bg2)),
        P.FillRect("", scalar(0), scalar(0), ref_num(prefix .. ":meter:w"), ref_num(prefix .. ":h"), color_pack(fill_rgba8)),
        P.FillRect("", ref_num(prefix .. ":peak:x"), scalar(0), scalar(3), ref_num(prefix .. ":h"), color_pack(C.gold)),
        P.StrokeRect("", scalar(0), scalar(0), ref_num(prefix .. ":w"), ref_num(prefix .. ":h"), scalar(1), color_pack(C.border_hi)),
    })
    meter_paint_cache[key] = hit
    return hit
end

local function backdrop_paint()
    local hit = backdrop_paint_cache[1]
    if hit then
        return hit
    end

    local children = {
        P.FillRect("", scalar(0), scalar(0), ref_num("bg:w"), ref_num("bg:h"), color_pack(C.bg0)),
    }

    for i = 0, 10 do
        children[#children + 1] = P.Line("", scalar(0), ref_num("bg:grid:y:" .. i), ref_num("bg:w"), ref_num("bg:grid:y:" .. i), scalar(1), color_pack(C.line))
    end
    for i = 0, 8 do
        children[#children + 1] = P.Line("", ref_num("bg:grid:x:" .. i), scalar(0), ref_num("bg:grid:x:" .. i), ref_num("bg:h"), scalar(1), color_pack(C.line))
    end
    children[#children + 1] = P.FillRect("", scalar(0), ref_num("bg:scan:y"), ref_num("bg:w"), scalar(2), color_pack(C.accent_soft))

    hit = P.Group(children)
    backdrop_paint_cache[1] = hit
    return hit
end

-- ─────────────────────────────────────────────────────────────
-- Demo state
-- ─────────────────────────────────────────────────────────────

local SCENES = {
    { name = "NEBULA", subtitle = "Reactive cloud routing over the Helios lattice.", eyebrow = "SCENE // 01" },
    { name = "ORBIT", subtitle = "Pinned signal arcs with staged gravity compensation.", eyebrow = "SCENE // 02" },
    { name = "CASCADE", subtitle = "Crossfade spill woven through the auxiliary bus garden.", eyebrow = "SCENE // 03" },
    { name = "MIRAGE", subtitle = "Specular shimmer mode for harmonic drift visualization.", eyebrow = "SCENE // 04" },
}

local CHANNEL_NAMES = {
    "AURORA BUS",
    "GLASS DRONE",
    "ION PULSE",
    "LATTICE FM",
    "PHASE RAIN",
    "NOCTILUX",
}

local function touch_structure(state)
    state.rev = (state.rev or 0) + 1
end

local function append_log(state, text_value)
    local stamp = string.format("%06.2f", state.time)
    table.insert(state.log, 1, stamp .. "  " .. text_value)
    while #state.log > 160 do
        state.log[#state.log] = nil
    end
    touch_structure(state)
end

local function make_channels()
    local out = {}
    for i = 1, #CHANNEL_NAMES do
        out[i] = {
            id = i,
            name = CHANNEL_NAMES[i],
            mute = false,
            solo = (i == 2),
            arm = (i == 4),
            level = 0.2 + i * 0.05,
            peak = 0.7,
            gain = -6 + i * 1.5,
        }
    end
    return out
end

function M.new_state()
    local state = {
        rev = 1,
        time = 0,
        playing = true,
        scene = 1,
        selected_channel = 2,
        master = 0.78,
        drift = 0.34,
        latency = 12.8,
        cpu = 18.0,
        burst = 0,
        log_scroll = 0,
        log = {
            "boot sequence complete",
            "render graph fused with cached lower boundary",
            "pointer packs pre-resolved for active scene",
            "scope braid synced to aurora bus",
            "love backend warmed and tracing cleanly",
        },
        channels = make_channels(),
    }
    append_log(state, "aurora control shell online")
    return state
end

local function clamp_scroll(state, layout)
    local content_h = #state.log * 28
    local max_scroll = math_max(0, content_h - layout.log_view_h)
    state.log_scroll = math_max(0, math_min(state.log_scroll, max_scroll))
end

local function has_any_solo(state)
    for i = 1, #state.channels do
        if state.channels[i].solo then
            return true
        end
    end
    return false
end

function M.update(state, dt)
    state.time = state.time + dt
    state.burst = math_max(0, state.burst - dt * 0.8)

    local solo = has_any_solo(state)
    local t = state.time
    local scene_phase = state.scene * 0.7
    local energy = 0

    for i = 1, #state.channels do
        local ch = state.channels[i]
        local wave = 0.18 + 0.82 * (0.5 + 0.5 * math_sin(t * (1.2 + i * 0.12) + scene_phase + i * 0.9))
        local target = wave
        if not state.playing then
            target = target * 0.15
        end
        if solo and not ch.solo then
            target = target * 0.08
        end
        if ch.mute then
            target = target * 0.05
        end
        if ch.arm then
            target = math_min(1, target + 0.08)
        end
        if state.burst > 0 then
            target = math_min(1, target + state.burst * 0.35)
        end

        ch.level = ch.level + (target - ch.level) * math_min(1, dt * 5.5)
        ch.peak = math_max(ch.level, ch.peak - dt * 0.22)
        ch.gain = -18 + ch.level * 24
        energy = energy + ch.level
    end

    energy = energy / #state.channels
    state.master = state.master + ((energy * 0.72 + 0.18) - state.master) * math_min(1, dt * 3.5)
    state.drift = 0.5 + 0.5 * math_sin(t * 0.65 + scene_phase)
    state.latency = 9.5 + 7.5 * (0.5 + 0.5 * math_sin(t * 0.4 + 1.7))
    state.cpu = 11 + 22 * energy + (state.playing and 6 or 0)
end

local function shuffle_targets(state)
    state.burst = 1
    for i = 1, #state.channels do
        local ch = state.channels[i]
        ch.mute = false
        ch.solo = false
        ch.arm = (math_random() > 0.66)
        ch.level = 0.1 + math_random() * 0.8
        ch.peak = math_min(1, ch.level + math_random() * 0.15)
    end
    append_log(state, "spectral matrix shuffled")
end

local function toggle_scene(state, scene_id)
    if scene_id >= 1 and scene_id <= #SCENES and scene_id ~= state.scene then
        state.scene = scene_id
        state.burst = 0.7
        append_log(state, "scene switched to " .. SCENES[scene_id].name)
    end
end

local function handle_click(state, id)
    if id == nil then
        return
    end

    local scene_id = tonumber(id:match("^scene:(%d+)$"))
    if scene_id then
        return toggle_scene(state, scene_id)
    end

    local ch_card = tonumber(id:match("^channel:(%d+)$"))
    if ch_card then
        state.selected_channel = ch_card
        append_log(state, "focused channel " .. CHANNEL_NAMES[ch_card])
        return
    end

    local ch_mute = tonumber(id:match("^channel:(%d+):mute$"))
    if ch_mute then
        local ch = state.channels[ch_mute]
        ch.mute = not ch.mute
        append_log(state, (ch.mute and "muted " or "unmuted ") .. ch.name)
        return
    end

    local ch_solo = tonumber(id:match("^channel:(%d+):solo$"))
    if ch_solo then
        local ch = state.channels[ch_solo]
        ch.solo = not ch.solo
        append_log(state, (ch.solo and "solo enabled on " or "solo cleared on ") .. ch.name)
        return
    end

    local ch_arm = tonumber(id:match("^channel:(%d+):arm$"))
    if ch_arm then
        local ch = state.channels[ch_arm]
        ch.arm = not ch.arm
        append_log(state, (ch.arm and "armed " or "disarmed ") .. ch.name)
        return
    end

    if id == "transport:play" then
        state.playing = not state.playing
        append_log(state, state.playing and "transport resumed" or "transport paused")
        return
    end

    if id == "transport:shuffle" then
        return shuffle_targets(state)
    end

    if id == "transport:flare" then
        state.burst = 1
        append_log(state, "flare pulse injected into master bus")
        return
    end
end

function M.handle_event(state, event, layout)
    if event.kind == T.Msg.Click then
        handle_click(state, event.id)
    elseif event.kind == T.Msg.Scroll and event.id == "log:scroll" then
        local prev = state.log_scroll
        state.log_scroll = state.log_scroll - (event.payload.b * 28)
        if layout then
            clamp_scroll(state, layout)
        end
        if state.log_scroll ~= prev then
            touch_structure(state)
        end
    end
end

function M.handle_messages(state, messages, layout)
    for i = 1, #messages do
        M.handle_event(state, messages[i], layout)
    end
end

function M.keypressed(state, key)
    if key == "space" then
        state.playing = not state.playing
        append_log(state, state.playing and "transport resumed from keyboard" or "transport paused from keyboard")
    elseif key == "tab" then
        toggle_scene(state, (state.scene % #SCENES) + 1)
    elseif key == "r" then
        shuffle_targets(state)
    elseif key == "f" then
        state.burst = 1
        append_log(state, "manual flare pulse")
    else
        local scene_id = tonumber(key)
        if scene_id and SCENES[scene_id] then
            toggle_scene(state, scene_id)
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Layout + runtime shaping
-- ─────────────────────────────────────────────────────────────

function M.compute_layout(width, height)
    local shell_inner_w = math_max(0, width - (S.shell_pad * 2))
    local shell_inner_h = math_max(0, height - (S.shell_pad * 2))
    local center_w = math_max(0, shell_inner_w - LEFT_W - RIGHT_W - ROOT_GAP * 2)
    local hero_inner_w = math_max(0, center_w - PANEL_INSET * 2)
    local hero_inner_h = math_max(0, HERO_H - PANEL_INSET * 2)
    local log_inner_h = math_max(0, shell_inner_h - PANEL_INSET * 2)
    local log_view_h = math_max(0, log_inner_h - LOG_HEADER_H - 10)

    return {
        width = width,
        height = height,
        shell_inner_w = shell_inner_w,
        shell_inner_h = shell_inner_h,
        left_w = LEFT_W,
        right_w = RIGHT_W,
        center_w = center_w,
        gap = ROOT_GAP,
        hero_h = HERO_H,
        transport_h = TRANSPORT_H,
        channel_w = CHANNEL_CARD_W,
        channel_h = CHANNEL_CARD_H,
        channel_gap = CHANNEL_GAP,
        panel_inset = PANEL_INSET,
        hero_inner_w = hero_inner_w,
        hero_inner_h = hero_inner_h,
        log_header_h = LOG_HEADER_H,
        log_view_h = log_view_h,
        meter_w = METER_W,
        meter_h = METER_H,
    }
end

function M.build_runtime(state, layout)
    local numbers = {}
    local texts = {
        ["stat:master"] = string.format("%.0f%%", state.master * 100),
        ["stat:drift"] = string.format("%.0f%%", state.drift * 100),
        ["stat:latency"] = string.format("%.1f ms", state.latency),
        ["stat:cpu"] = string.format("%.0f%%", state.cpu),
    }

    numbers["bg:w"] = layout.shell_inner_w
    numbers["bg:h"] = layout.shell_inner_h
    numbers["bg:scan:y"] = math_floor((0.5 + 0.5 * math_sin(state.time * 0.35)) * math_max(0, layout.shell_inner_h - 2))
    for i = 0, 10 do
        numbers["bg:grid:y:" .. i] = math_floor(layout.shell_inner_h * (i / 10))
    end
    for i = 0, 8 do
        numbers["bg:grid:x:" .. i] = math_floor(layout.shell_inner_w * (i / 8))
    end

    numbers["hero:w"] = layout.hero_inner_w
    numbers["hero:h"] = layout.hero_inner_h
    numbers["hero:scan:y"] = math_floor((0.5 + 0.5 * math_sin(state.time * 0.95 + 0.7)) * math_max(0, layout.hero_inner_h - 2))
    for i = 0, 3 do
        numbers["hero:grid:y:" .. i] = math_floor(math_max(0, layout.hero_inner_h - 20) * (i / 3))
    end

    do
        local pad_x = 8
        local gap = 4
        local bar_w = math_max(6, math_floor((layout.hero_inner_w - pad_x * 2) / HERO_BARS) - gap)
        local max_bar_h = math_max(3, layout.hero_inner_h - 12)
        for i = 1, HERO_BARS do
            local wave = 0.18 + 0.82 * (0.5 + 0.5 * math_sin(state.time * (1.6 + i * 0.02) + state.scene * 0.9 + i * 0.35))
            if not state.playing then
                wave = wave * 0.12
            end
            if state.burst > 0 then
                wave = math_min(1, wave + state.burst * 0.25)
            end
            local h = math_max(3, math_floor(wave * max_bar_h))
            numbers["hero:bar:" .. i .. ":x"] = pad_x + (i - 1) * (bar_w + gap)
            numbers["hero:bar:" .. i .. ":w"] = bar_w
            numbers["hero:bar:" .. i .. ":h"] = h
            numbers["hero:bar:" .. i .. ":y"] = max_bar_h - h
        end
    end

    for i = 1, #state.channels do
        local ch = state.channels[i]
        local prefix = "channel:" .. i
        texts[prefix .. ":gain"] = string.format("%+.1f dB", ch.gain)
        numbers[prefix .. ":w"] = layout.meter_w
        numbers[prefix .. ":h"] = layout.meter_h
        numbers[prefix .. ":meter:w"] = math_floor(ch.level * layout.meter_w)
        numbers[prefix .. ":peak:x"] = math_floor(ch.peak * layout.meter_w)
    end

    return {
        numbers = numbers,
        texts = texts,
        colors = {},
    }
end

-- ─────────────────────────────────────────────────────────────
-- View builders
-- ─────────────────────────────────────────────────────────────

local function nav_button(scene_id, active)
    local scene = SCENES[scene_id]
    return button("nav", "scene:" .. scene_id, scene.name, box_px(LEFT_W, 52), active)
end

local function stat_panel(title_value, value_ref, box)
    return panel("panel", {}, "", 0, box,
        col(FILL_BOX, {
            item(text("", AUTO_BOX, MONO_TEXT, title_value)),
            item(dynamic_text_box(value_ref, box.w.px - 2 * (S.panel_pad + S.bw), 28, 2, L.LineHeightPx(24), L.TextStart, C.fg)),
        }, {
            gap_main = 6,
            justify = MAIN_CENTER,
            align_items = CROSS_START,
        }))
end

local function sidebar(state)
    return col(box_w(LEFT_W), {
        item(panel("panel", {}, "", 0, box_px(LEFT_W, 126),
            col(FILL_BOX, {
                item(text("brand:eyebrow", AUTO_BOX, MONO_TEXT, "PI // FRESH UI STACK")),
                item(text("brand:title", AUTO_BOX, HERO_TITLE_TEXT, "AURORA")),
                item(text("brand:sub", AUTO_BOX, HERO_BODY_TEXT, "A Love2D showcase built on the new reducer-first UI architecture.")),
            }, { gap_main = 8 }))),

        item(panel("panel", {}, "", 0, box_px(LEFT_W, 296),
            col(FILL_BOX, {
                item(text("scene:hdr", AUTO_BOX, MONO_TEXT, "SCENE SELECTION")),
                item(nav_button(1, state.scene == 1)),
                item(nav_button(2, state.scene == 2)),
                item(nav_button(3, state.scene == 3)),
                item(nav_button(4, state.scene == 4)),
            }, { gap_main = 10 }))),

        item(panel("panel", {}, "", 0, box_px(LEFT_W, 170),
            col(FILL_BOX, {
                item(text("tips:hdr", AUTO_BOX, MONO_TEXT, "LIVE CONTROLS")),
                item(text("tips:1", AUTO_BOX, BODY_TEXT, "SPACE  pause / resume transport")),
                item(text("tips:2", AUTO_BOX, BODY_TEXT, "TAB    cycle scenes")),
                item(text("tips:3", AUTO_BOX, BODY_TEXT, "R      shuffle channels")),
                item(text("tips:4", AUTO_BOX, BODY_TEXT, "mouse wheel over log to scroll")),
            }, { gap_main = 8 }))),

        item(panel("panel", {}, "", 0, box_px(LEFT_W, 160),
            col(FILL_BOX, {
                item(text("focus:hdr", AUTO_BOX, MONO_TEXT, "FOCUSED CHANNEL")),
                item(text("focus:name", AUTO_BOX, TITLE_TEXT, state.channels[state.selected_channel].name)),
                item(row(FILL_BOX, {
                    item(chip(state.channels[state.selected_channel].mute and "MUTED" or "OPEN", state.channels[state.selected_channel].mute)),
                    item(chip(state.channels[state.selected_channel].solo and "SOLO" or "WIDE", state.channels[state.selected_channel].solo)),
                    item(chip(state.channels[state.selected_channel].arm and "ARM" or "SAFE", state.channels[state.selected_channel].arm)),
                }, { gap_main = 8 })),
            }, { gap_main = 10 })), 1, 1),
    }, {
        gap_main = 16,
        align_items = CROSS_START,
    })
end

local function hero_panel(state)
    local scene = SCENES[state.scene]
    return panel("hero", flags_active(state.playing), "", 0, box_h(HERO_H),
        T.SemUI.Stack(FILL_BOX, {
            U.CustomPaint("hero:paint", FILL_BOX, hero_paint()),
            col(FILL_BOX, {
                item(text("hero:eyebrow", AUTO_BOX, MONO_TEXT, scene.eyebrow)),
                item(text("hero:title", AUTO_BOX, HERO_TITLE_TEXT, scene.name)),
                item(text("hero:subtitle", fill_w_h(64), HERO_BODY_TEXT, scene.subtitle)),
                item(row(box_h(44), {
                    item(button("button", "transport:play", state.playing and "PAUSE" or "PLAY", box_px(120, 44), state.playing)),
                    item(button("button", "transport:shuffle", "SHUFFLE", box_px(128, 44), false)),
                    item(button("button", "transport:flare", "FLARE", box_px(112, 44), false)),
                }, {
                    gap_main = 10,
                    align_items = CROSS_CENTER,
                })),
            }, {
                gap_main = 10,
                justify = MAIN_START,
                align_items = CROSS_START,
            }),
        }))
end

local function transport_panel()
    return panel("panel", {}, "", 0, box_h(TRANSPORT_H),
        row(FILL_BOX, {
            item(stat_panel("MASTER", "stat:master", box_px(132, TRANSPORT_H - 2 * PANEL_INSET))),
            item(stat_panel("DRIFT", "stat:drift", box_px(132, TRANSPORT_H - 2 * PANEL_INSET))),
            item(stat_panel("LATENCY", "stat:latency", box_px(150, TRANSPORT_H - 2 * PANEL_INSET))),
            item(stat_panel("CPU", "stat:cpu", box_px(120, TRANSPORT_H - 2 * PANEL_INSET))),
        }, {
            gap_main = 12,
            justify = MAIN_START,
            align_items = CROSS_CENTER,
        }))
end

local function channel_card(state, index)
    local ch = state.channels[index]
    local surface_flags = flags_active(state.selected_channel == index)
    local meter_color = ch.mute and C.dim or (ch.solo and C.gold or C.accent)
    local meter = U.CustomPaint(
        "channel:" .. index,
        box_px(METER_W, METER_H),
        meter_paint("channel:" .. index, meter_color))

    return U.Focusable("channel:" .. index,
        U.Pressable("channel:" .. index,
            panel("panel", surface_flags, "", 0, box_px(CHANNEL_CARD_W, CHANNEL_CARD_H),
                col(FILL_BOX, {
                    item(row(box_px(CHANNEL_CARD_W - PANEL_INSET * 2, 28), {
                        item(text("channel:name:" .. index, AUTO_BOX, TITLE_TEXT, ch.name), 1, 1),
                        item(dynamic_text_box("channel:" .. index .. ":gain", 84, 18, 4, L.LineHeightPx(12), L.TextEnd, C.muted)),
                    }, { gap_main = 8, align_items = CROSS_CENTER })),

                    item(text("channel:meta:" .. index, AUTO_BOX, BODY_TEXT,
                        string.format("scene vector %02d  //  focus lane %02d", state.scene, index))),

                    item(meter),

                    item(row(box_px(CHANNEL_CARD_W - PANEL_INSET * 2, 34), {
                        item(button("button", "channel:" .. index .. ":mute", "MUTE", box_px(82, 34), ch.mute)),
                        item(button("button", "channel:" .. index .. ":solo", "SOLO", box_px(82, 34), ch.solo)),
                        item(button("button", "channel:" .. index .. ":arm", "ARM", box_px(78, 34), ch.arm)),
                    }, { gap_main = 8 })),
                }, {
                    gap_main = 10,
                    justify = MAIN_START,
                    align_items = CROSS_START,
                }))))
end

local function channels_grid(state)
    local children = {}
    for i = 1, #state.channels do
        children[#children + 1] = item(channel_card(state, i), 0, 0, BASIS_AUTO, CROSS_AUTO)
    end
    return row(AUTO_BOX, children, {
        wrap = WRAP_WRAP,
        gap_main = CHANNEL_GAP,
        gap_cross = CHANNEL_GAP,
        align_items = CROSS_START,
        align_content = CONTENT_START,
    })
end

local function log_view(state)
    local line_box = box_px(RIGHT_W - PANEL_INSET * 4, 28)
    local lines = {}
    for i = 1, #state.log do
        lines[#lines + 1] = item(panel("logline", {}, "", 0, line_box,
            row(FILL_BOX, {
                item(text("log:" .. i, AUTO_BOX, MONO_TEXT, state.log[i]), 1, 1),
            }, { align_items = CROSS_CENTER })))
    end

    return panel("panel", {}, "", 0, box_w(RIGHT_W),
        col(FILL_BOX, {
            item(text("log:hdr", AUTO_BOX, MONO_TEXT, "EVENT TAP")),
            item(text("log:sub", box_px(RIGHT_W - PANEL_INSET * 2, 48), WRAP_BODY_TEXT, "Hovered widgets, focus transitions, and demo actions stream here in real time.")),
            item(panel("panel", {}, "log:scroll", state.log_scroll, AUTO_BOX,
                col(FILL_BOX, lines, { gap_main = 0, align_items = CROSS_START })), 1, 1),
        }, {
            gap_main = 10,
            align_items = CROSS_START,
        }))
end

local function center_column(state)
    return col(AUTO_BOX, {
        item(hero_panel(state)),
        item(transport_panel()),
        item(channels_grid(state), 1, 1),
    }, {
        gap_main = 16,
        align_items = CROSS_START,
    })
end

function M.build_semui(state, layout)
    return panel("shell", {}, "", 0, FILL_BOX,
        T.SemUI.Stack(FILL_BOX, {
            U.CustomPaint("backdrop", FILL_BOX, backdrop_paint()),
            row(FILL_BOX, {
                item(sidebar(state), 0, 0),
                item(center_column(state), 1, 1),
                item(log_view(state), 0, 0),
            }, {
                gap_main = ROOT_GAP,
                align_items = CROSS_START,
            }),
        }))
end

function M.build_tree(state, layout, opts)
    opts = opts or {}
    clamp_scroll(state, layout)
    local sem = M.build_semui(state, layout)
    local ui_node = lower.node(THEME, sem, {
        focused_id = opts.focused_id or "",
    })
    return ui_node, sem
end

function M.build(state, opts)
    opts = opts or {}
    local width = opts.width or 1600
    local height = opts.height or 920
    local layout = M.compute_layout(width, height)
    local ui_node, sem = M.build_tree(state, layout, opts)
    local runtime = M.build_runtime(state, layout)
    return ui_node, runtime, layout, sem
end

return M
