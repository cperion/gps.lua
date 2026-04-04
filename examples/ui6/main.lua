-- examples/ui6/main.lua — fixes from deep review of ui5
--
-- Changes from ui5:
--   1. Track has stable ID (not position-based identity)
--   2. hover removed from all widget types → paint-time effect
--   3. string hover removed from Transport/Inspector
--   4. meter split out of Track → separate meters[] array
--   5. Arrangement split: ArrangementGrid (stable) + Playhead (per-frame)
--   6. pvm.with() everywhere (no raw constructors for mutation)
--   7. App state is ASDL (undo-friendly, structural sharing at root)
--   8. Event ASDL + pure Apply function
--   9. Tag dispatch → structured App.Action sum type
--
-- Three ASDL layers (same architecture as ui5):
--   App.Widget → UI.Node → View.Cmd

package.path = table.concat({
    "../../?.lua", "../../?/init.lua", package.path
}, ";")

local pvm = require("pvm")

-- ══════════════════════════════════════════════════════════════
--  COLOUR HELPERS
-- ══════════════════════════════════════════════════════════════

local function hex(argb)
    local a = math.floor(argb / 0x1000000) % 256
    local r = math.floor(argb / 0x10000) % 256
    local g = math.floor(argb / 0x100) % 256
    local b = argb % 256
    return r * 0x1000000 + g * 0x10000 + b * 0x100 + a
end

local function rgba8_to_love(rgba8)
    local a = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local b = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local g = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local r = (rgba8 % 256) / 255
    return r, g, b, a
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
    knob_bg=hex(0xff30363d), knob_fg=hex(0xff58a6ff), knob_arc=hex(0xff484f58),
    transport_bg=hex(0xff0d1117), scrollbar=hex(0xff30363d), scrollthumb=hex(0xff484f58),
    row_even=hex(0xff0d1117), row_odd=hex(0xff161b22),
    row_hover=hex(0xff1c2330), row_active=hex(0xff1f2937),
    hover_tint=hex(0x18ffffff),  -- semi-transparent white overlay for hover
}

-- ══════════════════════════════════════════════════════════════
--  LAYER 0: ASDL — domain types + events + actions
-- ══════════════════════════════════════════════════════════════

local T = pvm.context():Define [[
    module App {
        Track = (number id, string name, number color, number vol, number pan,
                 boolean mute, boolean solo) unique

        State = (App.Track* tracks, number selected, number scroll_y,
                 number bpm) unique

        Action = SelectTrack(number idx)
               | ToggleMute(number idx)
               | ToggleSolo(number idx)
               | SetVol(number idx, number vol)
               | SetPan(number idx, number pan)
               | TogglePlay
               | Stop
               | Reset
               | BpmUp
               | BpmDown
               | Scroll(number delta)

        Widget = TrackRow(number index, App.Track track, boolean selected) unique
               | TrackList(App.Widget* rows, number scroll_y, number view_h) unique
               | Header(number count) unique
               | Scrollbar(number total_h, number view_h, number scroll_y) unique
               | Transport(number win_w, number bpm, boolean playing,
                           string time_str, string beat_str) unique
               | Inspector(App.Track track, number selected_idx, number win_h) unique
               | ArrangementGrid(App.Track* tracks, number arr_w, number arr_h,
                                  number scroll_y) unique
               | Playhead(number beat, number arr_h) unique
               | Button(string tag, number w, number h,
                        number bg, number fg, number font_id, string label) unique
               | Meter(string tag, number w, number h, number level) unique
               | VolSlider(string tag, number w, number h, number vol) unique
               | PanSlider(string tag, number w, number h, number pan) unique
    }
]]

-- ══════════════════════════════════════════════════════════════
--  LAYER 1: UI.Node — layout primitives (unchanged from ui5)
-- ══════════════════════════════════════════════════════════════

T:Define [[
    module UI {
        Node = Column(number spacing, UI.Node* children) unique
             | Row(number spacing, UI.Node* children) unique
             | Group(UI.Node* children) unique
             | Padding(number left, number top, number right, number bottom,
                       UI.Node child) unique
             | Align(number w, number h, UI.AlignH halign, UI.AlignV valign,
                     UI.Node child) unique
             | Clip(number w, number h, UI.Node child) unique
             | Transform(number tx, number ty, UI.Node child) unique
             | Rect(string tag, number w, number h, number rgba8) unique
             | Text(string tag, number font_id, number rgba8, string text) unique
             | Spacer(number w, number h) unique
        AlignH = Left | Center | Right
        AlignV = Top | Middle | Bottom
    }
]]

-- ══════════════════════════════════════════════════════════════
--  LAYER 2: View.Cmd — flat draw commands (unchanged from ui5)
-- ══════════════════════════════════════════════════════════════

T:Define [[
    module View {
        Kind = Rect | Text | PushClip | PopClip | PushTransform | PopTransform

        Cmd = (View.Kind kind, string htag,
               number x, number y, number w, number h,
               number rgba8, number font_id, string text,
               number tx, number ty) unique
    }
]]

-- Shorthand constructors
local Col, Row, Grp, Pad, Ali, Clp, Tfm, Rct, Txt, Spc =
    T.UI.Column, T.UI.Row, T.UI.Group, T.UI.Padding, T.UI.Align,
    T.UI.Clip, T.UI.Transform, T.UI.Rect, T.UI.Text, T.UI.Spacer
local Lft, Cen, Rgt = T.UI.Left, T.UI.Center, T.UI.Right
local Top, Mid, Bot = T.UI.Top, T.UI.Middle, T.UI.Bottom

local K_RECT      = T.View.Rect
local K_TEXT      = T.View.Text
local K_PUSH_CLIP = T.View.PushClip
local K_POP_CLIP  = T.View.PopClip
local K_PUSH_TX   = T.View.PushTransform
local K_POP_TX    = T.View.PopTransform

local VCmd = T.View.Cmd
local function VRect(tag, x, y, w, h, rgba8)
    return VCmd(K_RECT, tag, x, y, w, h, rgba8, 0, "", 0, 0) end
local function VText(tag, x, y, w, h, font_id, rgba8, text)
    return VCmd(K_TEXT, tag, x, y, w, h, rgba8, font_id, text, 0, 0) end
local function VPushClip(x, y, w, h)
    return VCmd(K_PUSH_CLIP, "", x, y, w, h, 0, 0, "", 0, 0) end
local VPopClip = VCmd(K_POP_CLIP, "", 0, 0, 0, 0, 0, 0, "", 0, 0)
local function VPushTx(tx, ty)
    return VCmd(K_PUSH_TX, "", 0, 0, 0, 0, 0, 0, "", tx, ty) end
local VPopTx = VCmd(K_POP_TX, "", 0, 0, 0, 0, 0, 0, "", 0, 0)

local Track, State = T.App.Track, T.App.State
local ROW_H, HEADER_H, TRACK_W, METER_W = 48, 40, 220, 6
local TRANSPORT_H, INSP_W = 52, 280
local PX_PER_BEAT = 60

-- ══════════════════════════════════════════════════════════════
--  FONTS
-- ══════════════════════════════════════════════════════════════

local fonts = {}
local function text_metrics(fid, text)
    local f = fonts[fid] or love.graphics.getFont()
    return f:getWidth(text), f:getHeight()
end

-- ══════════════════════════════════════════════════════════════
--  PURE APPLY (fix #8: Event ASDL + pure reducer)
-- ══════════════════════════════════════════════════════════════

local function clamp(x,lo,hi) return math.max(lo, math.min(hi, x)) end

-- Update one track by index using pvm.with (fix #6)
local function update_track(state, idx, overrides)
    local new_tracks = {}
    for i = 1, #state.tracks do
        if i == idx then
            new_tracks[i] = pvm.with(state.tracks[i], overrides)
        else
            new_tracks[i] = state.tracks[i]  -- structural sharing
        end
    end
    return pvm.with(state, { tracks = new_tracks })
end

-- Pure reducer: (State, Action) → State (fix #8)
local function apply(state, action)
    local k = action.kind
    if k == "SelectTrack" then
        return pvm.with(state, { selected = action.idx })
    elseif k == "ToggleMute" then
        local t = state.tracks[action.idx]
        return update_track(state, action.idx, { mute = not t.mute })
    elseif k == "ToggleSolo" then
        local t = state.tracks[action.idx]
        return update_track(state, action.idx, { solo = not t.solo })
    elseif k == "SetVol" then
        return update_track(state, action.idx, { vol = action.vol })
    elseif k == "SetPan" then
        return update_track(state, action.idx, { pan = action.pan })
    elseif k == "BpmUp" then
        return pvm.with(state, { bpm = math.min(300, state.bpm + 5) })
    elseif k == "BpmDown" then
        return pvm.with(state, { bpm = math.max(40, state.bpm - 5) })
    elseif k == "Scroll" then
        local max_scroll = math.max(0, #state.tracks * ROW_H - 400) -- approx
        return pvm.with(state, { scroll_y = clamp(state.scroll_y + action.delta, 0, max_scroll) })
    end
    return state  -- TogglePlay, Stop, Reset handled in transient state
end

-- ══════════════════════════════════════════════════════════════
--  TAG → ACTION mapping (fix #9: structured dispatch)
-- ══════════════════════════════════════════════════════════════

local function tag_to_action(tag, tracks, selected)
    if not tag then return nil end

    -- Track-level: "track:3", "track:3:mute", "track:3:solo", etc.
    local ti_str = tag:match("^track:(%d+)")
    if ti_str then
        local ti = tonumber(ti_str)
        if tag:find(":mute", 1, true) then
            return T.App.SelectTrack(ti), T.App.ToggleMute(ti)
        elseif tag:find(":solo", 1, true) then
            return T.App.SelectTrack(ti), T.App.ToggleSolo(ti)
        elseif tag:find(":vol", 1, true) then
            return T.App.SelectTrack(ti), "drag_vol", ti
        elseif tag:find(":pan", 1, true) then
            return T.App.SelectTrack(ti), "drag_pan", ti
        else
            return T.App.SelectTrack(ti)
        end
    end

    -- Inspector actions
    if tag:find("^insp:vol_slider") then return "drag_vol", selected end
    if tag:find("^insp:pan_slider") then return "drag_pan", selected end
    if tag:find("^insp:mute_btn") then return T.App.ToggleMute(selected) end
    if tag:find("^insp:solo_btn") then return T.App.ToggleSolo(selected) end

    -- Transport
    if tag == "transport:play" then return T.App.TogglePlay() end
    if tag == "transport:stop" then return T.App.Stop() end
    if tag == "transport:bpm-" then return T.App.BpmDown() end
    if tag == "transport:bpm+" then return T.App.BpmUp() end

    return nil
end

-- ══════════════════════════════════════════════════════════════
--  VERB: App.Widget → UI.Node
--
--  No hover in any widget type (fix #2, #3).
--  Widgets produce "normal" appearance. Hover applied at paint time.
-- ══════════════════════════════════════════════════════════════

local widget_to_ui = pvm.verb("ui", {

[T.App.Button] = function(self)
    return Grp({
        Rct(self.tag, self.w, self.h, self.bg),
        Ali(self.w, self.h, Cen, Mid,
            Txt(self.tag..":l", self.font_id, self.fg, self.label)),
    })
end,

[T.App.Meter] = function(self)
    local fill = math.floor(self.w * math.max(0, math.min(1, self.level)))
    local col = self.level > 0.9 and C.meter_clip
              or self.level > 0.7 and C.meter_hot or C.meter_fill
    return Grp({
        Rct(self.tag, self.w, self.h, C.meter_bg),
        Rct(self.tag..":f", fill, self.h, col),
    })
end,

[T.App.VolSlider] = function(self)
    local fill = math.floor(self.w * math.max(0, math.min(1, self.vol)))
    return Grp({
        Rct(self.tag, self.w, self.h, C.knob_bg),
        Rct(self.tag..":v", fill, self.h, C.knob_fg),
    })
end,

[T.App.PanSlider] = function(self)
    local center = math.floor(self.w / 2)
    local pos = math.floor(self.pan * self.w)
    local left = math.min(center, pos)
    local bar_w = math.max(2, math.abs(pos - center))
    return Grp({
        Rct(self.tag, self.w, self.h, C.knob_bg),
        Tfm(left, 0, Rct(self.tag..":v", bar_w, self.h, C.knob_fg)),
    })
end,

-- TrackRow: no hovered field (fix #2). selected stays (changes rarely).
[T.App.TrackRow] = function(self)
    local i, t = self.index, self.track
    local tag = "track:"..i
    local bg = self.selected and C.row_active
             or (i % 2 == 0) and C.row_even or C.row_odd
    local name_fg = self.selected and C.text_bright or C.text

    return Grp({
        Rct(tag, TRACK_W, ROW_H, bg),
        Row(0, {
            Rct(tag..":pip", 4, ROW_H, t.color),
            Pad(8,0,0,0, Ali(120, ROW_H, Lft, Mid,
                Txt(tag..":name", 2, name_fg, t.name))),
            Pad(0,14,4,14, Row(4, {
                T.App.Button(tag..":mute", 24, 20,
                    t.mute and C.mute_on or C.panel,
                    t.mute and C.text_bright or C.text_dim, 4, "M"):ui(),
                T.App.Button(tag..":solo", 24, 20,
                    t.solo and C.solo_on or C.panel,
                    t.solo and C.text_bright or C.text_dim, 4, "S"):ui(),
            })),
            Pad(0,19,0,19,
                T.App.VolSlider(tag..":vol", 60, 10, t.vol):ui()),
            Pad(4,19,4,19,
                T.App.PanSlider(tag..":pan", 40, 10, t.pan):ui()),
            -- Meter reads from meters[] array, NOT from Track (fix #4)
            -- Meter widget is passed in from build_widgets, not constructed here
        }),
    })
end,

[T.App.Header] = function(self)
    return Grp({
        Rct("header", TRACK_W+8, HEADER_H, C.panel),
        Rct("header:b", TRACK_W+8, 1, C.border),
        Pad(14,0,0,0, Ali(TRACK_W, HEADER_H, Lft, Mid,
            Row(12, {
                Txt("hdr:t", 3, C.text_bright, "Tracks"),
                Txt("hdr:c", 4, C.text_dim, "("..self.count..")"),
            }))),
    })
end,

-- Scrollbar: no hovered field (fix #2)
[T.App.Scrollbar] = function(self)
    if self.total_h <= self.view_h then return Spc(0, 0) end
    local ratio = self.view_h / self.total_h
    local thumb_h = math.max(20, math.floor(self.view_h * ratio))
    local max_scroll = self.total_h - self.view_h
    local thumb_y = math.floor((self.scroll_y / math.max(1, max_scroll)) * (self.view_h - thumb_h))
    return Grp({
        Rct("scroll", 8, self.view_h, C.scrollbar),
        Tfm(0, thumb_y, Rct("scroll:thumb", 8, thumb_h, C.scrollthumb)),
    })
end,

[T.App.TrackList] = function(self)
    local track_nodes = {}
    for i = 1, #self.rows do
        track_nodes[i] = Tfm(0, (i-1)*ROW_H, self.rows[i]:ui())
    end
    return Grp({
        Rct("tl_bg", TRACK_W+8, self.view_h, C.bg),
        Clp(TRACK_W, self.view_h,
            Tfm(0, -self.scroll_y, Grp(track_nodes))),
        Tfm(TRACK_W, 0,
            T.App.Scrollbar(#self.rows * ROW_H, self.view_h, self.scroll_y):ui()),
    })
end,

-- Transport: no hover field (fix #3). All buttons show normal colors.
[T.App.Transport] = function(self)
    local play_l = self.playing and "||" or ">"
    return Grp({
        Rct("transport", self.win_w, TRANSPORT_H, C.transport_bg),
        Rct("transport:b", self.win_w, 1, C.border),
        Pad(16,0,16,0, Row(16, {
            Ali(80, TRANSPORT_H, Cen, Mid,
                T.App.Button("transport:play", 48, 30,
                    self.playing and C.accent_dim or C.panel,
                    C.text_bright, 3, play_l):ui()),
            Ali(60, TRANSPORT_H, Cen, Mid,
                T.App.Button("transport:stop", 48, 30,
                    C.panel, C.text, 3, "[]"):ui()),
            Rct("t:sep1", 1, TRANSPORT_H-16, C.border),
            Ali(100, TRANSPORT_H, Cen, Mid, Col(2, {
                Txt("t:time_l", 4, C.text_dim, "TIME"),
                Txt("t:time", 3, C.text_bright, self.time_str) })),
            Ali(60, TRANSPORT_H, Cen, Mid, Col(2, {
                Txt("t:beat_l", 4, C.text_dim, "BEAT"),
                Txt("t:beat", 3, C.text_bright, self.beat_str) })),
            Rct("t:sep2", 1, TRANSPORT_H-16, C.border),
            Ali(80, TRANSPORT_H, Cen, Mid, Col(2, {
                Txt("t:bpm_l", 4, C.text_dim, "BPM"),
                Row(4, {
                    T.App.Button("transport:bpm-", 22, 20,
                        C.panel, C.text, 4, "-"):ui(),
                    Txt("t:bpm", 3, C.accent, tostring(self.bpm)),
                    T.App.Button("transport:bpm+", 22, 20,
                        C.panel, C.text, 4, "+"):ui(),
                }) })),
            Spc(20, 1),
            Ali(200, TRANSPORT_H, Lft, Mid,
                Txt("t:status", 4, C.text_dim,
                    self.playing and "RECORDING" or "STOPPED")),
        })),
    })
end,

-- Inspector: no hover field (fix #3). Sliders show normal colors.
[T.App.Inspector] = function(self)
    local t = self.track
    local function kv(key, val, tag)
        return Row(0, {
            Ali(90, 22, Lft, Mid, Txt(tag..":k", 4, C.text_dim, key)),
            Ali(160, 22, Lft, Mid, Txt(tag..":v", 2, C.text, val)) })
    end
    local h = self.win_h - TRANSPORT_H
    return Grp({
        Rct("insp", INSP_W, h, C.panel),
        Rct("insp:b", 1, h, C.border),
        Pad(16,16,16,16, Col(10, {
            Txt("insp:title", 3, C.text_bright, "Inspector"),
            Rct("insp:sep", INSP_W-32, 1, C.border),
            Col(4, {
                kv("Track", t.name, "insp:name"),
                kv("Index", tostring(self.selected_idx), "insp:idx"),
                kv("Volume", string.format("%.0f%%", t.vol*100), "insp:vol"),
                kv("Pan", string.format("%.0f%%", (t.pan-0.5)*200), "insp:pan"),
                kv("Mute", t.mute and "ON" or "off", "insp:mute"),
                kv("Solo", t.solo and "ON" or "off", "insp:solo"),
            }),
            Rct("insp:sep2", INSP_W-32, 1, C.border),
            Txt("insp:vol_l", 4, C.text_dim, "Volume"),
            T.App.VolSlider("insp:vol_slider", INSP_W-32, 14, t.vol):ui(),
            Txt("insp:pan_l", 4, C.text_dim, "Pan"),
            T.App.PanSlider("insp:pan_slider", INSP_W-32, 14, t.pan):ui(),
            Rct("insp:sep3", INSP_W-32, 1, C.border),
            Row(8, {
                T.App.Button("insp:mute_btn", 70, 28,
                    t.mute and C.mute_on or C.panel,
                    t.mute and C.text_bright or C.text, 2,
                    t.mute and "MUTED" or "Mute"):ui(),
                T.App.Button("insp:solo_btn", 70, 28,
                    t.solo and C.solo_on or C.panel,
                    t.solo and C.text_bright or C.text, 2,
                    t.solo and "SOLO'D" or "Solo"):ui(),
            }),
        })),
    })
end,

-- ArrangementGrid: stable during playback (fix #5). No beat field.
[T.App.ArrangementGrid] = function(self)
    local arr_w, arr_h = self.arr_w, self.arr_h
    local vb = math.ceil(arr_w / PX_PER_BEAT) + 1

    local grid = {}
    for b = 0, vb do
        grid[#grid+1] = Tfm(b*PX_PER_BEAT, 0,
            Rct("grid:"..b, 1, arr_h-HEADER_H, (b%4==0) and C.border or C.panel))
    end

    local lanes = {}
    for i = 1, #self.tracks do
        local t = self.tracks[i]
        local cx = ((i*37)%8)*PX_PER_BEAT
        local cw = (2+(i%3))*PX_PER_BEAT
        lanes[#lanes+1] = Tfm(cx, (i-1)*ROW_H - self.scroll_y + 4, Grp({
            Rct("clip:"..i, cw, ROW_H-8, t.color),
            Pad(6,2,0,0, Txt("clip:"..i..":n", 4, C.text_bright, t.name)),
        }))
    end

    local ruler = {}
    for b = 0, vb do
        local bx = b * PX_PER_BEAT
        if b%4==0 then
            ruler[#ruler+1] = Tfm(bx+4, 0,
                Txt("ruler:"..b, 4, C.text_dim, tostring(b/4+1)))
        end
        ruler[#ruler+1] = Tfm(bx, 0,
            Rct("rt:"..b, 1, (b%4==0) and HEADER_H or 10, C.border))
    end

    return Grp({
        Rct("arr_bg", arr_w, arr_h, C.bg),
        Grp({ Rct("ruler_bg", arr_w, HEADER_H, C.panel), Clp(arr_w, HEADER_H, Grp(ruler)) }),
        Tfm(0, HEADER_H, Clp(arr_w, arr_h-HEADER_H, Grp(lanes))),
        Tfm(0, HEADER_H, Clp(arr_w, arr_h-HEADER_H, Grp(grid))),
    })
end,

-- Playhead: changes every frame during playback (fix #5). Cheap to recompile.
[T.App.Playhead] = function(self)
    return Tfm(math.floor(self.beat*PX_PER_BEAT), 0,
        Rct("playhead", 2, self.arr_h, C.text_bright))
end,

}, { cache = true })

-- ══════════════════════════════════════════════════════════════
--  MEASURE + PLACE (unchanged from ui5)
-- ══════════════════════════════════════════════════════════════

local INF_W = 1e9
local measure_cache = setmetatable({}, { __mode = "k" })

local function cached_measure(node, mw)
    local by_mw = measure_cache[node]
    if by_mw then
        local hit = by_mw[mw]
        if hit then return hit[1], hit[2] end
    else
        by_mw = {}; measure_cache[node] = by_mw
    end
    local w, h = node:_measure(mw)
    by_mw[mw] = { w, h }
    return w, h
end

function T.UI.Rect:_measure(mw)    return self.w, self.h end
function T.UI.Spacer:_measure(mw)  return self.w, self.h end
function T.UI.Align:_measure(mw)   return self.w, self.h end
function T.UI.Clip:_measure(mw)    return self.w, self.h end
function T.UI.Text:_measure(mw)    return text_metrics(self.font_id, self.text) end
function T.UI.Transform:_measure(mw) return cached_measure(self.child, mw) end
function T.UI.Padding:_measure(mw)
    local cw, ch = cached_measure(self.child, (mw or INF_W) - self.left - self.right)
    return self.left + cw + self.right, self.top + ch + self.bottom
end
function T.UI.Column:_measure(mw)
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = cached_measure(self.children[i], mw)
        if cw > w then w = cw end; h = h + ch; if i > 1 then h = h + self.spacing end
    end; return w, h
end
function T.UI.Row:_measure(mw)
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = cached_measure(self.children[i], mw)
        w = w + cw; if i > 1 then w = w + self.spacing end; if ch > h then h = ch end
    end; return w, h
end
function T.UI.Group:_measure(mw)
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = cached_measure(self.children[i], mw)
        if cw > w then w = cw end; if ch > h then h = ch end
    end; return w, h
end

function T.UI.Rect:place(x,y,mw,mh,out)
    out[#out+1] = VRect(self.tag, x, y, self.w, self.h, self.rgba8) end
function T.UI.Text:place(x,y,mw,mh,out)
    local w,h = cached_measure(self, mw)
    out[#out+1] = VText(self.tag, x, y, w, h, self.font_id, self.rgba8, self.text) end
function T.UI.Spacer:place(x,y,mw,mh,out) end
function T.UI.Padding:place(x,y,mw,mh,out)
    self.child:place(x+self.left, y+self.top,
        (mw or INF_W)-self.left-self.right, (mh or INF_W)-self.top-self.bottom, out) end
function T.UI.Align:place(x,y,mw,mh,out)
    local cw,ch = cached_measure(self.child, self.w)
    local cx,cy = x,y
    if self.halign.kind=="Center" then cx=x+math.floor((self.w-cw)/2)
    elseif self.halign.kind=="Right" then cx=x+(self.w-cw) end
    if self.valign.kind=="Middle" then cy=y+math.floor((self.h-ch)/2)
    elseif self.valign.kind=="Bottom" then cy=y+(self.h-ch) end
    self.child:place(cx, cy, self.w, self.h, out) end
function T.UI.Clip:place(x,y,mw,mh,out)
    out[#out+1] = VPushClip(x, y, self.w, self.h)
    self.child:place(x, y, self.w, self.h, out)
    out[#out+1] = VPopClip end
function T.UI.Transform:place(x,y,mw,mh,out)
    out[#out+1] = VPushTx(self.tx, self.ty)
    self.child:place(x, y, mw, mh, out)
    out[#out+1] = VPopTx end
function T.UI.Column:place(x,y,mw,mh,out)
    local cy = y
    for i = 1, #self.children do
        local c = self.children[i]; local _,ch = cached_measure(c, mw)
        c:place(x, cy, mw, ch, out); cy = cy + ch + self.spacing
    end end
function T.UI.Row:place(x,y,mw,mh,out)
    local cx = x
    for i = 1, #self.children do
        local c = self.children[i]; local cw = cached_measure(c, mw)
        c:place(cx, y, cw, mh, out); cx = cx + cw + self.spacing
    end end
function T.UI.Group:place(x,y,mw,mh,out)
    for i = 1, #self.children do self.children[i]:place(x, y, mw, mh, out) end end

-- ══════════════════════════════════════════════════════════════
--  PAINT + HIT (hover applied at paint time — fix #2)
-- ══════════════════════════════════════════════════════════════

local function inside(px,py,x,y,w,h) return px>=x and py>=y and px<x+w and py<y+h end

-- hover_tag is a module-level variable, read by paint loop
local hover_tag = nil

local function paint(cmds)
    local tx, ty = 0, 0
    local tx_stack, clip_stack = {}, {}

    for i = 1, #cmds do
        local c = cmds[i]
        local k = c.kind

        if k == K_RECT then
            local r, g, b, a = rgba8_to_love(c.rgba8)
            -- Fix #2: apply hover tint at paint time
            if c.htag ~= "" and hover_tag and c.htag == hover_tag then
                r = math.min(1, r + 0.06)
                g = math.min(1, g + 0.06)
                b = math.min(1, b + 0.06)
            end
            love.graphics.setColor(r, g, b, a)
            love.graphics.rectangle("fill", c.x, c.y, c.w, c.h)

        elseif k == K_TEXT then
            love.graphics.setFont(fonts[c.font_id] or love.graphics.getFont())
            love.graphics.setColor(rgba8_to_love(c.rgba8))
            love.graphics.print(c.text, c.x, c.y)

        elseif k == K_PUSH_CLIP then
            local ax, ay, nw, nh = c.x + tx, c.y + ty, c.w, c.h
            local top = clip_stack[#clip_stack]
            if top then
                local x2, y2 = math.max(ax, top[1]), math.max(ay, top[2])
                nw = math.max(0, math.min(ax+c.w, top[1]+top[3]) - x2)
                nh = math.max(0, math.min(ay+c.h, top[2]+top[4]) - y2)
                ax, ay = x2, y2
            end
            clip_stack[#clip_stack+1] = { ax, ay, nw, nh }
            love.graphics.setScissor(ax, ay, nw, nh)

        elseif k == K_POP_CLIP then
            clip_stack[#clip_stack] = nil
            local top = clip_stack[#clip_stack]
            if top then love.graphics.setScissor(top[1],top[2],top[3],top[4])
            else love.graphics.setScissor() end

        elseif k == K_PUSH_TX then
            tx_stack[#tx_stack+1] = { tx, ty }
            tx, ty = tx + c.tx, ty + c.ty
            love.graphics.push("transform")
            love.graphics.translate(c.tx, c.ty)

        elseif k == K_POP_TX then
            love.graphics.pop()
            local t = tx_stack[#tx_stack]; tx_stack[#tx_stack] = nil
            tx, ty = t[1], t[2]
        end
    end
    love.graphics.setColor(1,1,1,1)
end

local function hit_test(cmds, mx, my)
    local tx, ty = 0, 0
    local tx_stack, clip_stack = {}, {}
    local result = nil

    for i = 1, #cmds do
        local c = cmds[i]
        local k = c.kind

        if k == K_RECT or k == K_TEXT then
            if c.htag ~= "" then
                local x, y = c.x + tx, c.y + ty
                local cl = clip_stack[#clip_stack]
                if (not cl or inside(mx, my, cl[1], cl[2], cl[3], cl[4])) and
                   inside(mx, my, x, y, c.w, c.h) then
                    result = c.htag
                end
            end
        elseif k == K_PUSH_CLIP then
            clip_stack[#clip_stack+1] = { c.x+tx, c.y+ty, c.w, c.h }
        elseif k == K_POP_CLIP then
            clip_stack[#clip_stack] = nil
        elseif k == K_PUSH_TX then
            tx_stack[#tx_stack+1] = { tx, ty }
            tx, ty = tx + c.tx, ty + c.ty
        elseif k == K_POP_TX then
            local t = tx_stack[#tx_stack]; tx_stack[#tx_stack] = nil
            tx, ty = t[1], t[2]
        end
    end
    return result
end

-- ══════════════════════════════════════════════════════════════
--  COMPILE PIPELINE
-- ══════════════════════════════════════════════════════════════

local compile_cache = setmetatable({}, { __mode = "k" })
local compile_w, compile_h = 0, 0

local function compile(ui_tree, win_w, win_h)
    if win_w ~= compile_w or win_h ~= compile_h then
        compile_cache = setmetatable({}, { __mode = "k" })
        compile_w, compile_h = win_w, win_h
    end
    local hit = compile_cache[ui_tree]
    if hit then return hit end
    local out = {}
    ui_tree:place(0, 0, win_w, win_h, out)
    compile_cache[ui_tree] = out
    return out
end

-- ══════════════════════════════════════════════════════════════
--  APP STATE (fix #7: domain state is ASDL, transient state is plain Lua)
-- ══════════════════════════════════════════════════════════════

local NAMES = {"Kick","Snare","Hi-Hat","Bass","Lead Synth","Pad",
               "FX Rise","Vocal Chop","Perc","Sub Bass","Strings","Piano"}
local COLORS = {C.green,C.red,C.orange,C.purple,C.cyan,C.accent,
                C.orange,C.green,C.red,C.purple,C.cyan,C.accent}

local function make_initial_state()
    local tracks = {}
    for i = 1, #NAMES do
        tracks[i] = Track(i, NAMES[i], COLORS[i], 0.75, 0.5, false, false) -- fix #1: id field
    end
    return State(tracks, 1, 0, 120) -- tracks, selected, scroll_y, bpm
end

-- Domain state (ASDL, undoable, structural sharing) (fix #7)
local S = nil       -- App.State (set in love.load)
local undo_stack = {}
local undo_max = 50

-- Transient state (plain Lua, NOT undoable)
local playing = false
local beat = 0
local time_sec = 0
local meters = {}   -- fix #4: meters split from Track
local dragging = nil
local win_w, win_h = 1100, 700
local cmds = {}

local function push_undo()
    undo_stack[#undo_stack + 1] = S
    if #undo_stack > undo_max then
        table.remove(undo_stack, 1)
    end
end

local function pop_undo()
    if #undo_stack > 0 then
        S = undo_stack[#undo_stack]
        undo_stack[#undo_stack] = nil
    end
end

-- Dispatch action through pure apply (fix #8)
local function dispatch(action)
    if not action then return end
    local new_state = apply(S, action)
    if new_state ~= S then
        push_undo()
        S = new_state
    end
end

-- ══════════════════════════════════════════════════════════════
--  BUILD WIDGETS (meter is separate, no hover on widgets)
-- ══════════════════════════════════════════════════════════════

local function build_widgets()
    local view_h = win_h - TRANSPORT_H - HEADER_H
    local scroll = clamp(S.scroll_y, 0, math.max(0, #S.tracks * ROW_H - view_h))
    local arr_w = win_w - TRACK_W - 8 - INSP_W
    local arr_h = win_h - TRANSPORT_H

    -- Track rows: meter is a separate widget, not part of Track (fix #4)
    local rows = {}
    for i = 1, #S.tracks do
        local row_ui = T.App.TrackRow(i, S.tracks[i], i == S.selected):ui()
        -- Append meter to each row's UI
        local meter_ui = Pad(2,4,4,4,
            T.App.Meter("track:"..i..":meter", METER_W, ROW_H-8, meters[i] or 0):ui())
        -- Compose: row + meter side by side
        rows[i] = T.App.TrackRow(i, S.tracks[i], i == S.selected)
    end

    -- Build track row UIs with meters appended
    local track_ui_nodes = {}
    for i = 1, #S.tracks do
        local row_node = rows[i]:ui()
        local meter_widget = T.App.Meter("track:"..i..":meter", METER_W, ROW_H-8, meters[i] or 0)
        -- We need to combine row UI + meter UI. The TrackRow handler doesn't emit meter
        -- (since meter is no longer on Track). We combine at this level:
        track_ui_nodes[i] = Row(0, { row_node, Pad(2,4,4,4, meter_widget:ui()) })
    end

    -- Wrap in TrackList-like structure (we inline it since we build custom row nodes)
    local positioned = {}
    for i = 1, #track_ui_nodes do
        positioned[i] = Tfm(0, (i-1)*ROW_H, track_ui_nodes[i])
    end
    local track_list_ui = Grp({
        Rct("tl_bg", TRACK_W+8, view_h, C.bg),
        Clp(TRACK_W, view_h,
            Tfm(0, -scroll, Grp(positioned))),
        Tfm(TRACK_W, 0,
            T.App.Scrollbar(#S.tracks * ROW_H, view_h, scroll):ui()),
    })

    local time_str = string.format("%02d:%02d.%03d",
        math.floor(time_sec/60), math.floor(time_sec)%60,
        math.floor((time_sec*1000)%1000))
    local beat_str = string.format("%.1f", beat + 1)

    -- ArrangementGrid is stable during playback (fix #5)
    -- Playhead changes every frame but is a trivial widget
    return Col(0, {
        Row(0, {
            Col(0, {
                T.App.Header(#S.tracks):ui(),
                track_list_ui,
            }),
            Grp({
                T.App.ArrangementGrid(S.tracks, arr_w, arr_h, scroll):ui(),
                T.App.Playhead(beat, arr_h):ui(),
            }),
            T.App.Inspector(S.tracks[S.selected], S.selected, win_h):ui(),
        }),
        T.App.Transport(win_w, S.bpm, playing, time_str, beat_str):ui(),
    })
end

local function recompile()
    local ui_tree = build_widgets()
    cmds = compile(ui_tree, win_w, win_h)
end

local function update_hover(mx, my)
    local tag = hit_test(cmds, mx, my)
    if tag ~= hover_tag then
        hover_tag = tag
        -- No recompile needed! Hover is paint-time only (fix #2)
    end
end

-- ══════════════════════════════════════════════════════════════
--  LOVE CALLBACKS
-- ══════════════════════════════════════════════════════════════

function love.load()
    love.graphics.setBackgroundColor(0.054, 0.067, 0.090, 1)
    fonts[1] = love.graphics.newFont(18)
    fonts[2] = love.graphics.newFont(13)
    fonts[3] = love.graphics.newFont(15)
    fonts[4] = love.graphics.newFont(10)
    love.graphics.setFont(fonts[2])
    S = make_initial_state()
    win_w, win_h = love.graphics.getDimensions()
    for i = 1, #NAMES do meters[i] = 0 end
    recompile()
end

function love.resize(w, h) win_w, win_h = w, h; recompile() end

function love.update(dt)
    local changed = false

    -- Animate meters (fix #4: meters are separate from Track)
    for i = 1, #S.tracks do
        local t = S.tracks[i]
        local target = 0
        if playing and not t.mute then
            target = (0.3 + 0.5*math.abs(math.sin(time_sec*(1.5+i*0.3)+i*0.7))) * t.vol
        end
        local new_meter = meters[i] + (target - meters[i]) * math.min(1, dt * 12)
        if math.abs(new_meter - meters[i]) > 0.002 then
            meters[i] = math.floor(new_meter * 100) / 100
            changed = true
        end
    end

    -- Animate transport
    if playing then
        time_sec = time_sec + dt; beat = time_sec * S.bpm / 60
        changed = true
    end

    if changed then recompile() end
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    if key == "space" then
        playing = not playing
        if not playing then
            for i = 1, #meters do meters[i] = 0 end
        end
        recompile()
    end
    if key == "up" then
        dispatch(T.App.SelectTrack(math.max(1, S.selected-1)))
        recompile()
    end
    if key == "down" then
        dispatch(T.App.SelectTrack(math.min(#S.tracks, S.selected+1)))
        recompile()
    end
    if key == "m" then dispatch(T.App.ToggleMute(S.selected)); recompile() end
    if key == "s" then dispatch(T.App.ToggleSolo(S.selected)); recompile() end
    if key == "r" then
        playing = false; time_sec = 0; beat = 0
        for i = 1, #meters do meters[i] = 0 end
        recompile()
    end
    if key == "z" and love.keyboard.isDown("lctrl", "rctrl") then
        pop_undo(); recompile()
    end
end

function love.mousepressed(mx, my, btn)
    if btn ~= 1 then return end
    local tag = hit_test(cmds, mx, my); if not tag then return end

    -- Fix #9: structured dispatch via tag_to_action
    local a1, a2, a3 = tag_to_action(tag, S.tracks, S.selected)

    if type(a1) == "string" then
        -- Drag initiation
        if a1 == "drag_vol" then
            dragging = {idx=a2, field="vol", x0=mx, val0=S.tracks[a2].vol, w=60}
        elseif a1 == "drag_pan" then
            dragging = {idx=a2, field="pan", x0=mx, val0=S.tracks[a2].pan, w=40}
        end
        recompile(); return
    end

    if a1 then dispatch(a1) end
    if a2 and type(a2) ~= "string" then dispatch(a2) end

    -- Handle transient actions locally
    if tag == "transport:play" then
        playing = not playing
        if not playing then for i=1,#meters do meters[i]=0 end end
    elseif tag == "transport:stop" then
        playing = false; time_sec = 0; beat = 0
        for i=1,#meters do meters[i]=0 end
    end

    recompile()
end

function love.mousereleased() if dragging then dragging=nil; recompile() end end

function love.mousemoved(mx, my)
    if dragging then
        local d = dragging
        local new_val = clamp(d.val0 + (mx - d.x0) / d.w, 0, 1)
        if d.field == "vol" then
            dispatch(T.App.SetVol(d.idx, new_val))
        else
            dispatch(T.App.SetPan(d.idx, new_val))
        end
        recompile()
    end
    update_hover(mx, my)
end

function love.wheelmoved(_, wy)
    dispatch(T.App.Scroll(-wy * 30))
    recompile(); update_hover(love.mouse.getPosition())
end

function love.draw()
    love.graphics.origin(); love.graphics.setScissor(); love.graphics.setColor(1,1,1,1)
    paint(cmds)
end
