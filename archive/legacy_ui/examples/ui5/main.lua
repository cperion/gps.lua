-- examples/ui5/main.lua — widgets as ASDL types
--
-- Three ASDL layers:
--
--   App.Widget  — domain vocabulary (TrackRow, Transport, Inspector, ...)
--     :ui() → UI.Node  (memoized on Widget identity)
--
--   UI.Node     — layout vocabulary (Column, Row, Rect, Text, ...)
--     :place(x, y, mw, mh, out) → View.Cmd*  (terminal traversal)
--
--   View.Cmd    — draw vocabulary (RectCmd, TextCmd, PushClip, ...)
--     :paint(g)  :hit(h)  (one for loop each)
--
-- Every layer is ASDL. Every boundary is pvm.lower().
-- Widgets are interned. Same track data → same widget → cached UI subtree.
-- Immediate-mode authoring. Retained-mode performance.

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
}

-- ══════════════════════════════════════════════════════════════
--  LAYER 0: App.Widget — domain types
-- ══════════════════════════════════════════════════════════════

local T = pvm.context():Define [[
    module App {
        Track = (string name, number color, number vol, number pan,
                 boolean mute, boolean solo, number meter) unique

        Widget = TrackRow(number index, App.Track track,
                          boolean selected, boolean hovered) unique
               | TrackList(App.Widget* rows, number scroll_y,
                           number view_h) unique
               | Header(number count) unique
               | Scrollbar(number total_h, number view_h,
                           number scroll_y, boolean hovered) unique
               | Transport(number win_w, number bpm, boolean playing,
                           string time_str, string beat_str,
                           string hover) unique
               | Inspector(App.Track track, number selected_idx,
                           number win_h, string hover) unique
               | Arrangement(App.Track* tracks, number arr_w,
                             number arr_h, number scroll_y,
                             number beat) unique
               | Button(string tag, number w, number h,
                        number bg, number fg, number font_id,
                        string label, boolean hovered) unique
               | Meter(string tag, number w, number h,
                       number level) unique
               | VolSlider(string tag, number w, number h,
                           number vol, boolean hovered) unique
               | PanSlider(string tag, number w, number h,
                           number pan, boolean hovered) unique
    }
]]

-- ══════════════════════════════════════════════════════════════
--  LAYER 1: UI.Node — layout primitives
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
--  LAYER 2: View.Cmd — flat draw commands (no recursion)
-- ══════════════════════════════════════════════════════════════

-- View.Cmd — FLAT layer. Uniform product type. One shape.
-- Kind is a singleton sum (no fields, just identity — pointer comparison).
-- Cmd is a fixed-shape product (same fields for every command).
-- LuaJIT sees one table shape in the loop → one trace → golden bytecode.
T:Define [[
    module View {
        Kind = Rect | Text | PushClip | PopClip | PushTransform | PopTransform

        Cmd = (View.Kind kind, string htag,
               number x, number y, number w, number h,
               number rgba8, number font_id, string text,
               number tx, number ty) unique
    }
]]

-- shorthand
local Col, Row, Grp, Pad, Ali, Clp, Tfm, Rct, Txt, Spc =
    T.UI.Column, T.UI.Row, T.UI.Group, T.UI.Padding, T.UI.Align,
    T.UI.Clip, T.UI.Transform, T.UI.Rect, T.UI.Text, T.UI.Spacer
local Lft, Cen, Rgt = T.UI.Left, T.UI.Center, T.UI.Right
local Top, Mid, Bot = T.UI.Top, T.UI.Middle, T.UI.Bottom

-- View.Kind singletons (pointer-comparable)
local K_RECT      = T.View.Rect
local K_TEXT      = T.View.Text
local K_PUSH_CLIP = T.View.PushClip
local K_POP_CLIP  = T.View.PopClip
local K_PUSH_TX   = T.View.PushTransform
local K_POP_TX    = T.View.PopTransform

-- View.Cmd constructor helpers (fill unused fields with defaults)
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

local Track = T.App.Track

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
--  LAYER 0 → 1: App.Widget :ui() → UI.Node
--
--  Each widget type knows how to describe itself in layout primitives.
--  Memoized: same Widget pointer → cached UI.Node (skip :ui() entirely).
-- ══════════════════════════════════════════════════════════════

local widget_to_ui = pvm.verb("ui", {

[T.App.Button] = function(self)
    local bg = self.hovered and C.panel_hi or self.bg
    return Grp({
        Rct(self.tag, self.w, self.h, bg),
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
        Rct(self.tag, self.w, self.h, self.hovered and C.knob_arc or C.knob_bg),
        Rct(self.tag..":v", fill, self.h, C.knob_fg),
    })
end,

[T.App.PanSlider] = function(self)
    local center = math.floor(self.w / 2)
    local pos = math.floor(self.pan * self.w)
    local left = math.min(center, pos)
    local bar_w = math.max(2, math.abs(pos - center))
    return Grp({
        Rct(self.tag, self.w, self.h, self.hovered and C.knob_arc or C.knob_bg),
        Tfm(left, 0, Rct(self.tag..":v", bar_w, self.h, C.knob_fg)),
    })
end,

[T.App.TrackRow] = function(self)
    local i, t = self.index, self.track
    local tag = "track:"..i
    local bg = self.selected and C.row_active
             or self.hovered and C.row_hover
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
                    t.mute and C.text_bright or C.text_dim, 4, "M", false):ui(),
                T.App.Button(tag..":solo", 24, 20,
                    t.solo and C.solo_on or C.panel,
                    t.solo and C.text_bright or C.text_dim, 4, "S", false):ui(),
            })),
            Pad(0,19,0,19, 
                T.App.VolSlider(tag..":vol", 60, 10, t.vol, false):ui()),
            Pad(4,19,4,19, 
                T.App.PanSlider(tag..":pan", 40, 10, t.pan, false):ui()),
            Pad(2,4,4,4, 
                T.App.Meter(tag..":meter", METER_W, ROW_H-8, t.meter):ui()),
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

[T.App.Scrollbar] = function(self)
    if self.total_h <= self.view_h then return Spc(0, 0) end
    local ratio = self.view_h / self.total_h
    local thumb_h = math.max(20, math.floor(self.view_h * ratio))
    local max_scroll = self.total_h - self.view_h
    local thumb_y = math.floor((self.scroll_y / math.max(1, max_scroll)) * (self.view_h - thumb_h))
    return Grp({
        Rct("scroll", 8, self.view_h, C.scrollbar),
        Tfm(0, thumb_y, Rct("scroll:thumb", 8, thumb_h,
            self.hovered and C.accent or C.scrollthumb)),
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
            T.App.Scrollbar(#self.rows * ROW_H, self.view_h, self.scroll_y, false):ui()),
    })
end,

[T.App.Transport] = function(self)
    local htag = self.hover
    local play_l = self.playing and "||" or ">"
    return Grp({
        Rct("transport", self.win_w, TRANSPORT_H, C.transport_bg),
        Rct("transport:b", self.win_w, 1, C.border),
        Pad(16,0,16,0, Row(16, {
            Ali(80, TRANSPORT_H, Cen, Mid,
                T.App.Button("transport:play", 48, 30,
                    self.playing and C.accent_dim or C.panel,
                    C.text_bright, 3, play_l, htag=="transport:play"):ui()),
            Ali(60, TRANSPORT_H, Cen, Mid,
                T.App.Button("transport:stop", 48, 30,
                    C.panel, C.text, 3, "[]", htag=="transport:stop"):ui()),
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
                        C.panel, C.text, 4, "-", htag=="transport:bpm-"):ui(),
                    Txt("t:bpm", 3, C.accent, tostring(self.bpm)),
                    T.App.Button("transport:bpm+", 22, 20,
                        C.panel, C.text, 4, "+", htag=="transport:bpm+"):ui(),
                }) })),
            Spc(20, 1),
            Ali(200, TRANSPORT_H, Lft, Mid,
                Txt("t:status", 4, C.text_dim,
                    self.playing and "RECORDING" or "STOPPED")),
        })),
    })
end,

[T.App.Inspector] = function(self)
    local t, htag = self.track, self.hover
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
            T.App.VolSlider("insp:vol_slider", INSP_W-32, 14, t.vol,
                htag and htag:match("^insp:vol_slider") and true or false):ui(),
            Txt("insp:pan_l", 4, C.text_dim, "Pan"),
            T.App.PanSlider("insp:pan_slider", INSP_W-32, 14, t.pan,
                htag and htag:match("^insp:pan_slider") and true or false):ui(),
            Rct("insp:sep3", INSP_W-32, 1, C.border),
            Row(8, {
                T.App.Button("insp:mute_btn", 70, 28,
                    t.mute and C.mute_on or C.panel,
                    t.mute and C.text_bright or C.text, 2,
                    t.mute and "MUTED" or "Mute", htag=="insp:mute_btn"):ui(),
                T.App.Button("insp:solo_btn", 70, 28,
                    t.solo and C.solo_on or C.panel,
                    t.solo and C.text_bright or C.text, 2,
                    t.solo and "SOLO'D" or "Solo", htag=="insp:solo_btn"):ui(),
            }),
        })),
    })
end,

[T.App.Arrangement] = function(self)
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
        Tfm(math.floor(self.beat*PX_PER_BEAT), 0, Rct("playhead", 2, arr_h, C.text_bright)),
    })
end,

}, { cache = true })

-- ══════════════════════════════════════════════════════════════
--  UI.Node :measure() and :place()  (same as ui4)
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

-- :place() — terminal traversal, emits flat View.Cmd
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
--  PAINT + HIT: one for loop each, kind dispatch (golden trace)
--
--  All cmds have the same table shape (View.Cmd product type).
--  LuaJIT sees one metatable → one trace → no side exits.
--  Dispatch on cmd.kind is pointer comparison on local singletons.
-- ══════════════════════════════════════════════════════════════

local function inside(px,py,x,y,w,h) return px>=x and py>=y and px<x+w and py<y+h end

local function paint(cmds)
    local tx, ty = 0, 0
    local tx_stack, clip_stack = {}, {}

    for i = 1, #cmds do
        local c = cmds[i]
        local k = c.kind

        if k == K_RECT then
            love.graphics.setColor(rgba8_to_love(c.rgba8))
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
--  PIPELINE
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
--  APP STATE + BUILD
-- ══════════════════════════════════════════════════════════════

local NAMES = {"Kick","Snare","Hi-Hat","Bass","Lead Synth","Pad",
               "FX Rise","Vocal Chop","Perc","Sub Bass","Strings","Piano"}
local COLORS = {C.green,C.red,C.orange,C.purple,C.cyan,C.accent,
                C.orange,C.green,C.red,C.purple,C.cyan,C.accent}

local function clamp(x,lo,hi) return math.max(lo, math.min(hi, x)) end

local S -- state
local cmds

local function make_state()
    local tracks = {}
    for i = 1, #NAMES do
        tracks[i] = Track(NAMES[i], COLORS[i], 0.75, 0.5, false, false, 0)
    end
    return {
        tracks=tracks, selected=1, hover_tag=nil, scroll_y=0,
        bpm=120, playing=false, beat=0, time_sec=0,
        dragging=nil, win_w=1100, win_h=700,
    }
end

-- Build the widget tree — App.Widget layer
local function build_widgets(s)
    local htag = s.hover_tag or ""
    local view_h = s.win_h - TRANSPORT_H - HEADER_H
    local scroll = clamp(s.scroll_y, 0, math.max(0, #s.tracks * ROW_H - view_h))

    -- track rows (each is an App.TrackRow — interned!)
    local rows = {}
    for i = 1, #s.tracks do
        local is_hovered = htag == "track:"..i or htag:sub(1, #("track:"..i)+1) == "track:"..i..":"
        rows[i] = T.App.TrackRow(i, s.tracks[i], i == s.selected, is_hovered)
    end

    local arr_w = s.win_w - TRACK_W - 8 - INSP_W
    local arr_h = s.win_h - TRANSPORT_H

    local time_str = string.format("%02d:%02d.%03d",
        math.floor(s.time_sec/60), math.floor(s.time_sec)%60,
        math.floor((s.time_sec*1000)%1000))
    local beat_str = string.format("%.1f", s.beat + 1)

    -- Compose widgets → UI.Node via :ui() verb (codegen dispatch + cache)
    return Col(0, {
        Row(0, {
            Col(0, {
                T.App.Header(#s.tracks):ui(),
                T.App.TrackList(rows, scroll, view_h):ui(),
            }),
            T.App.Arrangement(s.tracks, arr_w, arr_h, scroll, s.beat):ui(),
            T.App.Inspector(s.tracks[s.selected], s.selected, s.win_h, htag):ui(),
        }),
        T.App.Transport(s.win_w, s.bpm, s.playing, time_str, beat_str, htag):ui(),
    })
end

local function recompile()
    local ui_tree = build_widgets(S)
    cmds = compile(ui_tree, S.win_w, S.win_h)
end

local function update_hover(mx, my)
    local tag = hit_test(cmds, mx, my)
    if tag ~= S.hover_tag then S.hover_tag = tag; recompile() end
end

local function track_from_tag(tag)
    return tonumber(tag:match("^track:(%d+)"))
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
    S = make_state()
    S.win_w, S.win_h = love.graphics.getDimensions()
    recompile()
end

function love.resize(w, h) S.win_w, S.win_h = w, h; recompile() end

function love.update(dt)
    local changed = false
    for i = 1, #S.tracks do
        local t = S.tracks[i]
        local target = 0
        if S.playing and not t.mute then
            target = (0.3 + 0.5*math.abs(math.sin(S.time_sec*(1.5+i*0.3)+i*0.7))) * t.vol
        end
        local old_meter = t.meter
        local new_meter = t.meter + (target - t.meter) * math.min(1, dt * 12)
        if math.abs(new_meter - old_meter) > 0.002 then
            -- Create new Track with updated meter (ASDL unique)
            S.tracks[i] = Track(t.name, t.color, t.vol, t.pan, t.mute, t.solo,
                                math.floor(new_meter * 100) / 100)
            changed = true
        end
    end
    if S.playing then
        S.time_sec = S.time_sec + dt; S.beat = S.time_sec * S.bpm / 60
        changed = true
    end
    if changed then recompile() end
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    if key == "space" then
        S.playing = not S.playing
        if not S.playing then
            for i = 1, #S.tracks do
                local t = S.tracks[i]
                S.tracks[i] = Track(t.name, t.color, t.vol, t.pan, t.mute, t.solo, 0)
            end
        end; recompile()
    end
    if key == "up" then S.selected = math.max(1, S.selected-1); recompile() end
    if key == "down" then S.selected = math.min(#S.tracks, S.selected+1); recompile() end
    if key == "m" then
        local t = S.tracks[S.selected]
        S.tracks[S.selected] = Track(t.name, t.color, t.vol, t.pan, not t.mute, t.solo, t.meter)
        recompile()
    end
    if key == "s" then
        local t = S.tracks[S.selected]
        S.tracks[S.selected] = Track(t.name, t.color, t.vol, t.pan, t.mute, not t.solo, t.meter)
        recompile()
    end
    if key == "r" then
        S.time_sec=0; S.beat=0; S.playing=false
        for i = 1, #S.tracks do
            local t = S.tracks[i]
            S.tracks[i] = Track(t.name, t.color, t.vol, t.pan, t.mute, t.solo, 0)
        end; recompile()
    end
end

function love.mousepressed(mx, my, btn)
    if btn ~= 1 then return end
    local tag = hit_test(cmds, mx, my); if not tag then return end
    local ti = track_from_tag(tag)
    if ti then
        S.selected = ti
        local t = S.tracks[ti]
        if tag:match(":mute") then
            S.tracks[ti] = Track(t.name,t.color,t.vol,t.pan,not t.mute,t.solo,t.meter)
        elseif tag:match(":solo") then
            S.tracks[ti] = Track(t.name,t.color,t.vol,t.pan,t.mute,not t.solo,t.meter)
        elseif tag:match(":vol") then
            S.dragging = {idx=ti, field="vol", x0=mx, val0=t.vol, w=60}
        elseif tag:match(":pan") then
            S.dragging = {idx=ti, field="pan", x0=mx, val0=t.pan, w=40}
        end; recompile(); return
    end
    if tag:match("^insp:vol_slider") then
        S.dragging = {idx=S.selected,field="vol",x0=mx,val0=S.tracks[S.selected].vol,w=INSP_W-32}; recompile(); return end
    if tag:match("^insp:pan_slider") then
        S.dragging = {idx=S.selected,field="pan",x0=mx,val0=S.tracks[S.selected].pan,w=INSP_W-32}; recompile(); return end
    if tag:match("^insp:mute_btn") then
        local t = S.tracks[S.selected]
        S.tracks[S.selected] = Track(t.name,t.color,t.vol,t.pan,not t.mute,t.solo,t.meter); recompile(); return end
    if tag:match("^insp:solo_btn") then
        local t = S.tracks[S.selected]
        S.tracks[S.selected] = Track(t.name,t.color,t.vol,t.pan,t.mute,not t.solo,t.meter); recompile(); return end
    if tag == "transport:play" then
        S.playing = not S.playing
        if not S.playing then for i=1,#S.tracks do local t=S.tracks[i]
            S.tracks[i]=Track(t.name,t.color,t.vol,t.pan,t.mute,t.solo,0) end end; recompile(); return end
    if tag == "transport:stop" then S.playing=false; S.time_sec=0; S.beat=0
        for i=1,#S.tracks do local t=S.tracks[i]
            S.tracks[i]=Track(t.name,t.color,t.vol,t.pan,t.mute,t.solo,0) end; recompile(); return end
    if tag == "transport:bpm-" then S.bpm = math.max(40, S.bpm-5); recompile() end
    if tag == "transport:bpm+" then S.bpm = math.min(300, S.bpm+5); recompile() end
end

function love.mousereleased() if S.dragging then S.dragging=nil; recompile() end end

function love.mousemoved(mx, my)
    if S.dragging then
        local d = S.dragging
        local t = S.tracks[d.idx]
        local new_val = clamp(d.val0 + (mx - d.x0) / d.w, 0, 1)
        if d.field == "vol" then
            S.tracks[d.idx] = Track(t.name,t.color,new_val,t.pan,t.mute,t.solo,t.meter)
        else
            S.tracks[d.idx] = Track(t.name,t.color,t.vol,new_val,t.mute,t.solo,t.meter)
        end
        recompile()
    end
    update_hover(mx, my)
end

function love.wheelmoved(_, wy)
    local list_h = #S.tracks * ROW_H
    local view_h = S.win_h - TRANSPORT_H - HEADER_H
    S.scroll_y = clamp(S.scroll_y - wy*30, 0, math.max(0, list_h - view_h))
    recompile(); update_hover(love.mouse.getPosition())
end

function love.draw()
    love.graphics.origin(); love.graphics.setScissor(); love.graphics.setColor(1,1,1,1)
    paint(cmds)
end
