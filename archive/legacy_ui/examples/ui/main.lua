package.path = table.concat({
    "../../?.lua",
    "../../?/init.lua",
    package.path,
}, ";")

local M = require("gps")
local Paint = require("examples/ui/lovepaint")(M)
local Hit   = require("examples/ui/hittest")(M)

-- ══════════════════════════════════════════════════════════════
--  COLOUR HELPERS
-- ══════════════════════════════════════════════════════════════

local function rgba(r, g, b, a)
    a = a or 1
    local ri = math.floor(r * 255 + .5)
    local gi = math.floor(g * 255 + .5)
    local bi = math.floor(b * 255 + .5)
    local ai = math.floor(a * 255 + .5)
    return ri * 0x1000000 + gi * 0x10000 + bi * 0x100 + ai
end

-- Convert 0xAARRGGBB → 0xRRGGBBAA (what lovepaint expects)
local function hex(argb)
    local a = math.floor(argb / 0x1000000) % 256
    local r = math.floor(argb / 0x10000) % 256
    local g = math.floor(argb / 0x100) % 256
    local b = argb % 256
    return r * 0x1000000 + g * 0x10000 + b * 0x100 + a
end

-- palette --
local C = {
    bg          = hex(0xff0e1117),
    panel       = hex(0xff161b22),
    panel_hi    = hex(0xff1c2330),
    border      = hex(0xff30363d),
    border_hi   = hex(0xff58a6ff),
    text        = hex(0xffe6edf3),
    text_dim    = hex(0xff8b949e),
    text_bright = hex(0xffffffff),
    accent      = hex(0xff58a6ff),
    accent_dim  = hex(0xff1f6feb),
    green       = hex(0xff3fb950),
    red         = hex(0xfff85149),
    orange      = hex(0xffd29922),
    purple      = hex(0xffbc8cff),
    cyan        = hex(0xff79c0ff),
    yellow_bg   = hex(0xff3b2e00),
    selection   = hex(0xff264f78),
    row_even    = hex(0xff0d1117),
    row_odd     = hex(0xff161b22),
    row_hover   = hex(0xff1c2330),
    row_active  = hex(0xff1f2937),
    mute_on     = hex(0xffda3633),
    solo_on     = hex(0xff58a6ff),
    meter_bg    = hex(0xff21262d),
    meter_fill  = hex(0xff3fb950),
    meter_hot   = hex(0xffd29922),
    meter_clip  = hex(0xfff85149),
    knob_bg     = hex(0xff30363d),
    knob_fg     = hex(0xff58a6ff),
    knob_arc    = hex(0xff484f58),
    transport_bg = hex(0xff0d1117),
    scrollbar   = hex(0xff30363d),
    scrollthumb = hex(0xff484f58),
}

-- ══════════════════════════════════════════════════════════════
--  VIEW LAYER  (positioned scene-graph, backend-agnostic)
-- ══════════════════════════════════════════════════════════════

local V = M.context("paint_ast")
    :Define [[
        module View {
            Root = (VNode* nodes) unique
            VNode = Group(VNode* children) unique
                  | Clip(number x, number y, number w, number h, VNode* body) unique
                  | Transform(number tx, number ty, VNode* body) unique
                  | Box(string tag, number x, number y, number w, number h, number rgba8) unique
                  | Label(string tag, number x, number y, number w, number h,
                          number font_id, number rgba8, string text) unique
        }
    ]]

function V.View.Root:paint_ast()
    local out = {}
    for i = 1, #self.nodes do out[i] = self.nodes[i]:paint_ast() end
    return Paint.LovePaint.Frame({ Paint.LovePaint.Screen(out) })
end
function V.View.Root:hit_ast()
    local out = {}
    for i = 1, #self.nodes do out[i] = self.nodes[i]:hit_ast() end
    return Hit.Hit.Root(out)
end
function V.View.Group:paint_ast()
    local out = {}
    for i = 1, #self.children do out[i] = self.children[i]:paint_ast() end
    return Paint.LovePaint.Group(out)
end
function V.View.Group:hit_ast()
    local out = {}
    for i = 1, #self.children do out[i] = self.children[i]:hit_ast() end
    return Hit.Hit.Group(out)
end
function V.View.Clip:paint_ast()
    local out = {}
    for i = 1, #self.body do out[i] = self.body[i]:paint_ast() end
    return Paint.LovePaint.Clip(self.x, self.y, self.w, self.h, out)
end
function V.View.Clip:hit_ast()
    local out = {}
    for i = 1, #self.body do out[i] = self.body[i]:hit_ast() end
    return Hit.Hit.Clip(self.x, self.y, self.w, self.h, out)
end
function V.View.Transform:paint_ast()
    local out = {}
    for i = 1, #self.body do out[i] = self.body[i]:paint_ast() end
    return Paint.LovePaint.Transform(self.tx, self.ty, out)
end
function V.View.Transform:hit_ast()
    local out = {}
    for i = 1, #self.body do out[i] = self.body[i]:hit_ast() end
    return Hit.Hit.Transform(self.tx, self.ty, out)
end
function V.View.Box:paint_ast()
    return Paint.LovePaint.RectFill(self.x, self.y, self.w, self.h, self.rgba8)
end
function V.View.Box:hit_ast()
    return Hit.Hit.Rect(self.x, self.y, self.w, self.h, self.tag)
end
function V.View.Label:paint_ast()
    return Paint.LovePaint.Text(self.x, self.y, self.font_id, self.rgba8, self.text)
end
function V.View.Label:hit_ast()
    return Hit.Hit.Text(self.x, self.y, self.w, self.h, self.tag)
end

-- ══════════════════════════════════════════════════════════════
--  UI WIDGETS  (declarative, layout-agnostic)
-- ══════════════════════════════════════════════════════════════

local U = M.context("view")
    :Define [[
        module UI {
            Root = (Node body) unique
            Node = Column(number spacing, Node* children) unique
                 | Row(number spacing, Node* children) unique
                 | Group(Node* children) unique
                 | Padding(number left, number top, number right, number bottom, Node child) unique
                 | Align(number w, number h, AlignH halign, AlignV valign, Node child) unique
                 | Clip(number w, number h, Node child) unique
                 | Transform(number tx, number ty, Node child) unique
                 | Rect(string tag, number w, number h, number rgba8) unique
                 | Text(string tag, number font_id, number rgba8, string text) unique
                 | Spacer(number w, number h) unique
            AlignH = Left | Center | Right
            AlignV = Top | Middle | Bottom
        }
    ]]

local fonts = {}
local function text_metrics(fid, text)
    local f = fonts[fid] or love.graphics.getFont()
    return f:getWidth(text), f:getHeight()
end
local function font_h(fid)
    return (fonts[fid] or love.graphics.getFont()):getHeight()
end

local function append_all(d, s)
    for i = 1, #s do d[#d+1] = s[i] end; return d
end

-- layout methods --
function U.UI.Root:view()         return V.View.Root(self.body:place(0,0)) end
function U.UI.Rect:measure()      return self.w, self.h end
function U.UI.Rect:place(x,y)     return { V.View.Box(self.tag, x,y, self.w, self.h, self.rgba8) } end
function U.UI.Text:measure()      return text_metrics(self.font_id, self.text) end
function U.UI.Text:place(x,y)
    local w,h = self:measure()
    return { V.View.Label(self.tag, x,y, w,h, self.font_id, self.rgba8, self.text) }
end
function U.UI.Spacer:measure()    return self.w, self.h end
function U.UI.Spacer:place()      return {} end
function U.UI.Padding:measure()
    local cw,ch = self.child:measure()
    return self.left+cw+self.right, self.top+ch+self.bottom
end
function U.UI.Padding:place(x,y)  return self.child:place(x+self.left, y+self.top) end
function U.UI.Column:measure()
    local w,h = 0,0
    for i=1,#self.children do
        local cw,ch = self.children[i]:measure()
        if cw>w then w=cw end; h=h+ch; if i>1 then h=h+self.spacing end
    end; return w,h
end
function U.UI.Column:place(x,y)
    local out,cy = {},y
    for i=1,#self.children do
        local c=self.children[i]; local _,ch=c:measure()
        append_all(out, c:place(x,cy)); cy=cy+ch+self.spacing
    end; return out
end
function U.UI.Row:measure()
    local w,h = 0,0
    for i=1,#self.children do
        local cw,ch = self.children[i]:measure()
        w=w+cw; if i>1 then w=w+self.spacing end; if ch>h then h=ch end
    end; return w,h
end
function U.UI.Row:place(x,y)
    local out,cx = {},x
    for i=1,#self.children do
        local c=self.children[i]; local cw=c:measure()
        append_all(out, c:place(cx,y)); cx=cx+cw+self.spacing
    end; return out
end
function U.UI.Group:measure()
    local w,h = 0,0
    for i=1,#self.children do
        local cw,ch = self.children[i]:measure()
        if cw>w then w=cw end; if ch>h then h=ch end
    end; return w,h
end
function U.UI.Group:place(x,y)
    local out={}
    for i=1,#self.children do append_all(out, self.children[i]:place(x,y)) end; return out
end
function U.UI.Align:measure() return self.w, self.h end
function U.UI.Align:place(x,y)
    local cw,ch = self.child:measure()
    local cx,cy = x,y
    if self.halign.kind=="Center" then cx=x+math.floor((self.w-cw)/2)
    elseif self.halign.kind=="Right" then cx=x+(self.w-cw) end
    if self.valign.kind=="Middle" then cy=y+math.floor((self.h-ch)/2)
    elseif self.valign.kind=="Bottom" then cy=y+(self.h-ch) end
    return self.child:place(cx,cy)
end
function U.UI.Clip:measure() return self.w, self.h end
function U.UI.Clip:place(x,y)
    return { V.View.Clip(x,y, self.w, self.h, self.child:place(x,y)) }
end
function U.UI.Transform:measure() return self.child:measure() end
function U.UI.Transform:place(x,y)
    return { V.View.Transform(self.tx, self.ty, self.child:place(x,y)) }
end

-- shorthand constructors --
local Col, Row, Grp, Pad, Ali, Clp, Tfm, Rct, Txt, Spc =
    U.UI.Column, U.UI.Row, U.UI.Group, U.UI.Padding, U.UI.Align,
    U.UI.Clip, U.UI.Transform, U.UI.Rect, U.UI.Text, U.UI.Spacer
local Lft, Cen, Rgt = U.UI.Left(), U.UI.Center(), U.UI.Right()
local Top, Mid, Bot = U.UI.Top(), U.UI.Middle(), U.UI.Bottom()

-- ══════════════════════════════════════════════════════════════
--  PIPELINES
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
--  APPLICATION STATE
-- ══════════════════════════════════════════════════════════════

local TRACK_NAMES = {
    "Kick", "Snare", "Hi-Hat", "Bass", "Lead Synth",
    "Pad", "FX Rise", "Vocal Chop", "Perc", "Sub Bass",
    "Strings", "Piano",
}

local TRACK_COLORS = {
    C.green, C.red, C.orange, C.purple, C.cyan,
    C.accent, C.orange, C.green, C.red, C.purple,
    C.cyan, C.accent,
}

local function make_initial_state()
    local tracks = {}
    for i = 1, #TRACK_NAMES do
        tracks[i] = {
            name   = TRACK_NAMES[i],
            color  = TRACK_COLORS[i],
            vol    = 0.75,
            pan    = 0.5,
            mute   = false,
            solo   = false,
            meter  = 0,     -- animated
        }
    end
    return {
        tracks       = tracks,
        selected     = 1,
        hover_tag    = nil,
        scroll_y     = 0,
        bpm          = 120,
        playing      = false,
        beat         = 0,     -- animated
        time_sec     = 0,     -- animated
        dragging     = nil,   -- { tag=..., start_val=... }
        show_debug   = false,
        win_w        = 1100,
        win_h        = 700,
    }
end

local S   -- current state
local paint_slot, hit_slot, gfx

-- ══════════════════════════════════════════════════════════════
--  WIDGET BUILDERS
-- ══════════════════════════════════════════════════════════════

local ROW_H       = 48
local HEADER_H    = 40
local TRACK_W     = 220
local METER_W     = 6
local KNOB_SZ     = 32
local TRANSPORT_H = 52
local INSP_W      = 280

local function clamp(x, lo, hi)
    return math.max(lo, math.min(hi, x))
end

-- tiny rounded-feel button
local function btn(tag, w, h, bg, fg, fid, label, hovered)
    local real_bg = hovered and C.panel_hi or bg
    return Grp({
        Rct(tag, w, h, real_bg),
        Ali(w, h, Cen, Mid, Txt(tag..":l", fid, fg, label)),
    })
end

-- horizontal meter bar
local function meter(tag, w, h, level)
    local fill = math.floor(w * clamp(level, 0, 1))
    local col = level > 0.9 and C.meter_clip or (level > 0.7 and C.meter_hot or C.meter_fill)
    return Grp({
        Rct(tag, w, h, C.meter_bg),
        Rct(tag..":f", fill, h, col),
    })
end

-- pan knob (drawn as a small horizontal bar)
local function pan_widget(tag, w, h, pan_val, hovered)
    local center = math.floor(w / 2)
    local pos    = math.floor(pan_val * w)
    local left   = math.min(center, pos)
    local right  = math.max(center, pos)
    local bar_w  = math.max(2, right - left)
    return Grp({
        Rct(tag, w, h, hovered and C.knob_arc or C.knob_bg),
        Tfm(left, 0, Rct(tag..":v", bar_w, h, C.knob_fg)),
    })
end

-- volume slider (vertical feel, horizontal bar)
local function vol_widget(tag, w, h, vol, hovered)
    local fill = math.floor(w * clamp(vol, 0, 1))
    return Grp({
        Rct(tag, w, h, hovered and C.knob_arc or C.knob_bg),
        Rct(tag..":v", fill, h, C.knob_fg),
    })
end

-- one track row
local function track_row(i, t, selected, hover)
    local tag = "track:"..i
    local htag = hover or ""
    local is_hovered = hover and (hover == tag or hover:sub(1, #tag+1) == tag..":")
    local bg = (i == selected) and C.row_active
             or is_hovered and C.row_hover
             or (i % 2 == 0) and C.row_even or C.row_odd

    local name_fg = (i == selected) and C.text_bright or C.text

    local color_pip = Rct(tag..":pip", 4, ROW_H, t.color)

    local name_col = Pad(8,0,0,0,
        Ali(120, ROW_H, Lft, Mid, Txt(tag..":name", 2, name_fg, t.name))
    )

    local mute_bg = t.mute and C.mute_on or C.panel
    local solo_bg = t.solo and C.solo_on or C.panel
    local mute_fg = t.mute and C.text_bright or C.text_dim
    local solo_fg = t.solo and C.text_bright or C.text_dim

    local mute_btn = btn(tag..":mute", 24, 20, mute_bg, mute_fg, 4, "M",
                         htag == tag..":mute")
    local solo_btn = btn(tag..":solo", 24, 20, solo_bg, solo_fg, 4, "S",
                         htag == tag..":solo")

    local vol_bar = vol_widget(tag..":vol", 60, 10, t.vol,
                               htag == tag..":vol" or htag == tag..":vol:v")
    local pan_bar = pan_widget(tag..":pan", 40, 10, t.pan,
                               htag == tag..":pan" or htag == tag..":pan:v")
    local lvl = meter(tag..":meter", METER_W, ROW_H - 8, t.meter)

    return Grp({
        Rct(tag, TRACK_W, ROW_H, bg),
        Row(0, {
            color_pip,
            name_col,
            Pad(0,14,4,14, Row(4, { mute_btn, solo_btn })),
            Pad(0,19,0,19, vol_bar),
            Pad(4,19,4,19, pan_bar),
            Pad(2,4,4,4, lvl),
        }),
    })
end

-- transport bar
local function transport_bar(s)
    local htag = s.hover_tag or ""
    local play_label = s.playing and "||" or ">"
    local min = math.floor(s.time_sec / 60)
    local sec = math.floor(s.time_sec) % 60
    local ms  = math.floor((s.time_sec * 1000) % 1000)
    local time_str = string.format("%02d:%02d.%03d", min, sec, ms)
    local beat_str = string.format("%.1f", s.beat + 1)

    return Grp({
        Rct("transport", s.win_w, TRANSPORT_H, C.transport_bg),
        Rct("transport:border", s.win_w, 1, C.border),
        Pad(16, 0, 16, 0,
            Row(16, {
                Ali(80, TRANSPORT_H, Cen, Mid,
                    btn("transport:play", 48, 30, s.playing and C.accent_dim or C.panel,
                        C.text_bright, 3, play_label, htag == "transport:play")),
                Ali(60, TRANSPORT_H, Cen, Mid,
                    btn("transport:stop", 48, 30, C.panel,
                        C.text, 3, "[]", htag == "transport:stop")),
                Rct("transport:sep1", 1, TRANSPORT_H - 16, C.border),
                Ali(100, TRANSPORT_H, Cen, Mid,
                    Col(2, {
                        Txt("transport:time_l", 4, C.text_dim, "TIME"),
                        Txt("transport:time", 3, C.text_bright, time_str),
                    })),
                Ali(60, TRANSPORT_H, Cen, Mid,
                    Col(2, {
                        Txt("transport:beat_l", 4, C.text_dim, "BEAT"),
                        Txt("transport:beat", 3, C.text_bright, beat_str),
                    })),
                Rct("transport:sep2", 1, TRANSPORT_H - 16, C.border),
                Ali(80, TRANSPORT_H, Cen, Mid,
                    Col(2, {
                        Txt("transport:bpm_l", 4, C.text_dim, "BPM"),
                        Row(4, {
                            btn("transport:bpm-", 22, 20, C.panel, C.text, 4, "-", htag == "transport:bpm-"),
                            Txt("transport:bpm", 3, C.accent, tostring(s.bpm)),
                            btn("transport:bpm+", 22, 20, C.panel, C.text, 4, "+", htag == "transport:bpm+"),
                        }),
                    })),
                Spc(20, 1),
                Ali(200, TRANSPORT_H, Lft, Mid,
                    Txt("transport:status", 4, C.text_dim,
                        s.playing and "RECORDING" or "STOPPED")),
            })
        ),
    })
end

-- inspector panel (right side)
local function inspector_panel(s)
    local t = s.tracks[s.selected]
    local htag = s.hover_tag or ""

    local function row_kv(key, val, tag)
        return Row(0, {
            Ali(90, 22, Lft, Mid, Txt(tag..":k", 4, C.text_dim, key)),
            Ali(160, 22, Lft, Mid, Txt(tag..":v", 2, C.text, val)),
        })
    end

    return Grp({
        Rct("insp", INSP_W, s.win_h - TRANSPORT_H, C.panel),
        Rct("insp:border", 1, s.win_h - TRANSPORT_H, C.border),
        Pad(16, 16, 16, 16,
            Col(10, {
                Txt("insp:title", 3, C.text_bright, "Inspector"),
                Rct("insp:sep", INSP_W - 32, 1, C.border),
                Col(4, {
                    row_kv("Track",  t.name, "insp:name"),
                    row_kv("Index",  tostring(s.selected), "insp:idx"),
                    row_kv("Volume", string.format("%.0f%%", t.vol * 100), "insp:vol"),
                    row_kv("Pan",    string.format("%.0f%%", (t.pan - 0.5) * 200), "insp:pan"),
                    row_kv("Mute",   t.mute and "ON" or "off", "insp:mute"),
                    row_kv("Solo",   t.solo and "ON" or "off", "insp:solo"),
                }),
                Rct("insp:sep2", INSP_W - 32, 1, C.border),
                Txt("insp:vol_label", 4, C.text_dim, "Volume"),
                vol_widget("insp:vol_slider", INSP_W - 32, 14, t.vol,
                           htag:match("^insp:vol_slider")),
                Txt("insp:pan_label", 4, C.text_dim, "Pan"),
                pan_widget("insp:pan_slider", INSP_W - 32, 14, t.pan,
                           htag:match("^insp:pan_slider")),
                Rct("insp:sep3", INSP_W - 32, 1, C.border),
                Row(8, {
                    btn("insp:mute_btn", 70, 28,
                        t.mute and C.mute_on or C.panel, t.mute and C.text_bright or C.text,
                        2, t.mute and "MUTED" or "Mute", htag == "insp:mute_btn"),
                    btn("insp:solo_btn", 70, 28,
                        t.solo and C.solo_on or C.panel, t.solo and C.text_bright or C.text,
                        2, t.solo and "SOLO'D" or "Solo", htag == "insp:solo_btn"),
                }),
            })
        ),
    })
end

-- scrollbar (vertical)
local function vscrollbar(tag, total_h, view_h, scroll_y, bar_h, hover)
    if total_h <= view_h then return Spc(0, 0) end
    local ratio   = view_h / total_h
    local thumb_h = math.max(20, math.floor(bar_h * ratio))
    local max_scroll = total_h - view_h
    local thumb_y = math.floor((scroll_y / max_scroll) * (bar_h - thumb_h))
    return Grp({
        Rct(tag, 8, bar_h, C.scrollbar),
        Tfm(0, thumb_y, Rct(tag..":thumb", 8, thumb_h,
            (hover and hover:match("^"..tag)) and C.accent or C.scrollthumb)),
    })
end

-- full UI tree
local function build_ui(s)
    local list_h = #s.tracks * ROW_H
    local view_h = s.win_h - TRANSPORT_H - HEADER_H
    local scroll = clamp(s.scroll_y, 0, math.max(0, list_h - view_h))

    -- track list --
    local track_rows = {}
    for i = 1, #s.tracks do
        track_rows[i] = Tfm(0, (i-1) * ROW_H,
            track_row(i, s.tracks[i], s.selected, s.hover_tag))
    end
    local track_col = Grp(track_rows)

    -- header --
    local header = Grp({
        Rct("header", TRACK_W + 8, HEADER_H, C.panel),
        Rct("header:border", TRACK_W + 8, 1, C.border),
        Pad(14, 0, 0, 0,
            Ali(TRACK_W, HEADER_H, Lft, Mid,
                Row(12, {
                    Txt("header:title", 3, C.text_bright, "Tracks"),
                    Txt("header:count", 4, C.text_dim,
                        string.format("(%d)", #s.tracks)),
                })
            )
        ),
    })

    -- assemble left panel --
    local left = Col(0, {
        header,
        Grp({
            Rct("tracklist_bg", TRACK_W + 8, view_h, C.bg),
            Clp(TRACK_W, view_h,
                Tfm(0, -scroll, track_col)
            ),
            Tfm(TRACK_W, 0,
                vscrollbar("scroll", list_h, view_h, scroll, view_h, s.hover_tag)),
        }),
    })

    -- arrangement placeholder (center area) --
    local arr_w = s.win_w - TRACK_W - 8 - INSP_W
    local arr_h = s.win_h - TRANSPORT_H

    -- beat grid lines
    local grid_lines = {}
    local px_per_beat = 60
    local visible_beats = math.ceil(arr_w / px_per_beat) + 1
    for b = 0, visible_beats do
        local bx = b * px_per_beat
        local is_bar = (b % 4 == 0)
        grid_lines[#grid_lines+1] = Tfm(bx, 0,
            Rct("grid:"..b, 1, arr_h - HEADER_H, is_bar and C.border or C.panel))
    end

    -- track lanes in arrangement
    local lane_nodes = {}
    for i = 1, #s.tracks do
        local t = s.tracks[i]
        local lane_y = (i-1) * ROW_H - scroll
        -- coloured clip blocks (fake arrangement data)
        local clip_x = ((i * 37) % 8) * px_per_beat
        local clip_w = (2 + (i % 3)) * px_per_beat
        lane_nodes[#lane_nodes+1] = Tfm(clip_x, lane_y + 4,
            Grp({
                Rct("clip:"..i, clip_w, ROW_H - 8, t.color),
                Pad(6, 2, 0, 0,
                    Txt("clip:"..i..":name", 4, C.text_bright, t.name)),
            })
        )
    end

    -- playhead
    local playhead_x = math.floor(s.beat * px_per_beat)
    local playhead = Tfm(playhead_x, 0,
        Rct("playhead", 2, arr_h, C.text_bright))

    -- beat ruler at top
    local ruler_nodes = {}
    for b = 0, visible_beats do
        local bx = b * px_per_beat
        local lbl = (b % 4 == 0) and tostring(math.floor(b/4)+1) or ""
        if lbl ~= "" then
            ruler_nodes[#ruler_nodes+1] = Tfm(bx + 4, 0,
                Txt("ruler:"..b, 4, C.text_dim, lbl))
        end
        ruler_nodes[#ruler_nodes+1] = Tfm(bx, 0,
            Rct("ruler:tick:"..b, 1, (b%4==0) and HEADER_H or 10, C.border))
    end

    local arrangement = Grp({
        Rct("arr_bg", arr_w, arr_h, C.bg),
        -- ruler
        Grp({
            Rct("ruler_bg", arr_w, HEADER_H, C.panel),
            Clp(arr_w, HEADER_H, Grp(ruler_nodes)),
        }),
        -- lanes
        Tfm(0, HEADER_H,
            Clp(arr_w, arr_h - HEADER_H, Grp(lane_nodes))),
        -- grid
        Tfm(0, HEADER_H,
            Clp(arr_w, arr_h - HEADER_H, Grp(grid_lines))),
        -- playhead
        playhead,
    })

    local right = inspector_panel(s)

    return U.UI.Root(
        Col(0, {
            Row(0, {
                left,
                arrangement,
                right,
            }),
            transport_bar(s),
        })
    )
end

-- ══════════════════════════════════════════════════════════════
--  RECOMPILE + INPUT
-- ══════════════════════════════════════════════════════════════

local function recompile()
    local ui = build_ui(S)
    local view = ui:view()
    paint_slot:update(view:paint_ast():draw())
    hit_slot:update(view:hit_ast():probe())
end

local function update_hover(mx, my)
    local hit = hit_slot:run({ x = mx, y = my })
    local next_tag = hit and hit.tag or nil
    if next_tag ~= S.hover_tag then
        S.hover_tag = next_tag
        recompile()
    end
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

    S = make_initial_state()
    S.win_w, S.win_h = love.graphics.getDimensions()
    paint_slot = Paint:new_slot()
    hit_slot   = Hit:new_slot()
    gfx = Paint:new_love_graphics(fonts)
    recompile()
end

function love.resize(w, h)
    S.win_w, S.win_h = w, h
    recompile()
end

function love.update(dt)
    -- animate meters
    local changed = false
    for i = 1, #S.tracks do
        local t = S.tracks[i]
        local target = 0
        if S.playing and not t.mute then
            target = 0.3 + 0.5 * math.abs(math.sin(S.time_sec * (1.5 + i * 0.3) + i * 0.7))
            target = target * t.vol
        end
        local old = t.meter
        t.meter = t.meter + (target - t.meter) * math.min(1, dt * 12)
        if math.abs(t.meter - old) > 0.002 then changed = true end
    end
    -- advance playhead
    if S.playing then
        S.time_sec = S.time_sec + dt
        S.beat = S.time_sec * S.bpm / 60
        changed = true
    end
    if changed then recompile() end
end

function love.keypressed(key)
    if key == "escape" then love.event.quit(); return end
    if key == "space" then
        S.playing = not S.playing
        if not S.playing then
            for i = 1, #S.tracks do S.tracks[i].meter = 0 end
        end
        recompile(); return
    end
    if key == "d" then S.show_debug = not S.show_debug; return end
    if key == "up" then
        S.selected = math.max(1, S.selected - 1); recompile(); return
    end
    if key == "down" then
        S.selected = math.min(#S.tracks, S.selected + 1); recompile(); return
    end
    if key == "m" then
        S.tracks[S.selected].mute = not S.tracks[S.selected].mute; recompile(); return
    end
    if key == "s" then
        S.tracks[S.selected].solo = not S.tracks[S.selected].solo; recompile(); return
    end
    if key == "r" then
        -- reset
        S.time_sec = 0; S.beat = 0; S.playing = false
        for i = 1, #S.tracks do S.tracks[i].meter = 0 end
        recompile(); return
    end
end

function love.mousepressed(mx, my, btn_idx)
    if btn_idx ~= 1 then return end
    local hit = hit_slot:run({ x = mx, y = my })
    if not hit then return end
    local tag = hit.tag

    -- track selection
    local ti = track_from_tag(tag)
    if ti then
        S.selected = ti
        -- check sub-tags
        if tag:match(":mute") then
            S.tracks[ti].mute = not S.tracks[ti].mute
        elseif tag:match(":solo") then
            S.tracks[ti].solo = not S.tracks[ti].solo
        elseif tag:match(":vol") then
            S.dragging = { tag = "track:"..ti..":vol", idx = ti, field = "vol",
                           x0 = mx, val0 = S.tracks[ti].vol, w = 60 }
        elseif tag:match(":pan") then
            S.dragging = { tag = "track:"..ti..":pan", idx = ti, field = "pan",
                           x0 = mx, val0 = S.tracks[ti].pan, w = 40 }
        end
        recompile(); return
    end

    -- inspector sliders
    if tag:match("^insp:vol_slider") then
        S.dragging = { tag = "insp:vol_slider", idx = S.selected, field = "vol",
                       x0 = mx, val0 = S.tracks[S.selected].vol, w = INSP_W - 32 }
        recompile(); return
    end
    if tag:match("^insp:pan_slider") then
        S.dragging = { tag = "insp:pan_slider", idx = S.selected, field = "pan",
                       x0 = mx, val0 = S.tracks[S.selected].pan, w = INSP_W - 32 }
        recompile(); return
    end
    if tag:match("^insp:mute_btn") then
        S.tracks[S.selected].mute = not S.tracks[S.selected].mute
        recompile(); return
    end
    if tag:match("^insp:solo_btn") then
        S.tracks[S.selected].solo = not S.tracks[S.selected].solo
        recompile(); return
    end

    -- transport
    if tag == "transport:play" then
        S.playing = not S.playing
        if not S.playing then
            for i = 1, #S.tracks do S.tracks[i].meter = 0 end
        end
        recompile(); return
    end
    if tag == "transport:stop" then
        S.playing = false; S.time_sec = 0; S.beat = 0
        for i = 1, #S.tracks do S.tracks[i].meter = 0 end
        recompile(); return
    end
    if tag == "transport:bpm-" then
        S.bpm = math.max(40, S.bpm - 5); recompile(); return
    end
    if tag == "transport:bpm+" then
        S.bpm = math.min(300, S.bpm + 5); recompile(); return
    end
end

function love.mousereleased()
    if S.dragging then
        S.dragging = nil
        recompile()
    end
end

function love.mousemoved(mx, my)
    if S.dragging then
        local d = S.dragging
        local delta = (mx - d.x0) / d.w
        S.tracks[d.idx][d.field] = clamp(d.val0 + delta, 0, 1)
        recompile()
    end
    update_hover(mx, my)
end

function love.wheelmoved(_, wy)
    local list_h = #S.tracks * ROW_H
    local view_h = S.win_h - TRANSPORT_H - HEADER_H
    S.scroll_y = clamp(S.scroll_y - wy * 30, 0, math.max(0, list_h - view_h))
    recompile()
    local mx, my = love.mouse.getPosition()
    update_hover(mx, my)
end

function love.draw()
    gfx:reset()
    paint_slot:run(gfx)

    -- debug overlay
    if S.show_debug then
        local report = M.report({ paint_slot, hit_slot })
        love.graphics.setFont(fonts[4])
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", 4, S.win_h - 80, 520, 76)
        love.graphics.setColor(0.7, 0.85, 1, 1)
        love.graphics.print(report, 8, S.win_h - 76)
        love.graphics.print(string.format("hover: %s  sel: %d  fps: %d  dt: %.1fms",
            tostring(S.hover_tag), S.selected,
            love.timer.getFPS(), love.timer.getAverageDelta()*1000),
            8, S.win_h - 30)
        love.graphics.setColor(1, 1, 1, 1)
    end
end
