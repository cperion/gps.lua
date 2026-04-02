package.path = table.concat({
    "../../?.lua",
    "../../?/init.lua",
    package.path,
}, ";")

local M = require("gps")

-- ══════════════════════════════════════════════════════════════
--  COLOUR
-- ══════════════════════════════════════════════════════════════

-- palette stored as RRGGBBAA (what the Love backend reads)
local function hex(argb)
    local a = math.floor(argb / 0x1000000) % 256
    local r = math.floor(argb / 0x10000) % 256
    local g = math.floor(argb / 0x100) % 256
    local b = argb % 256
    return r * 0x1000000 + g * 0x10000 + b * 0x100 + a
end

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
--  FLAT COMMAND SCHEMAS  (the canonical flatten-early IRs)
--
--  No recursion. Cmd* is a flat array.
--  Containment = PushClip/PopClip, PushTransform/PopTransform.
-- ══════════════════════════════════════════════════════════════

local D = M.context("draw"):Define [[
    module Draw {
        Frame = (Cmd* cmds) unique
        Cmd = FillRect(number x, number y, number w, number h, number rgba8) unique
            | DrawText(number x, number y, number font_id, number rgba8, string text) unique
            | PushClip(number x, number y, number w, number h) unique
            | PopClip unique
            | PushTransform(number tx, number ty) unique
            | PopTransform unique
    }
]]

local H = M.context("probe"):Define [[
    module Hit {
        Frame = (HCmd* cmds) unique
        HCmd = Rect(number x, number y, number w, number h, string tag) unique
             | PushClip(number x, number y, number w, number h) unique
             | PopClip unique
             | PushTransform(number tx, number ty) unique
             | PopTransform unique
    }
]]

-- shorthand
local FR  = D.Draw.FillRect
local DT  = D.Draw.DrawText
local DPC = D.Draw.PushClip
local DXC = D.Draw.PopClip
local DPT = D.Draw.PushTransform
local DXT = D.Draw.PopTransform

local HR  = H.Hit.Rect
local HPC = H.Hit.PushClip
local HXC = H.Hit.PopClip
local HPT = H.Hit.PushTransform
local HXT = H.Hit.PopTransform

-- ══════════════════════════════════════════════════════════════
--  FLAT TERMINALS  — one gen per backend, linear loop
-- ══════════════════════════════════════════════════════════════

local function rgba8_to_love(v)
    local a = (v % 256) / 255; v = math.floor(v / 256)
    local b = (v % 256) / 255; v = math.floor(v / 256)
    local g = (v % 256) / 255; v = math.floor(v / 256)
    local r = (v % 256) / 255
    return r, g, b, a
end

local fonts = {}

local function next_pow2(n)
    local p = 1; while p < n do p = p * 2 end; return p
end

-- Paint gen: walks Cmd* linearly
local function paint_gen(param, state, _)
    local cmds = param.cmds
    local lg = love.graphics
    for i = 1, #cmds do
        local c = cmds[i]
        local k = c.kind
        if k == "FillRect" then
            lg.setColor(rgba8_to_love(c.rgba8))
            lg.rectangle("fill", c.x, c.y, c.w, c.h)
        elseif k == "DrawText" then
            -- text resource management in state
            local cap = next_pow2(#c.text)
            local res = state.text_res[i]
            local font = fonts[c.font_id] or lg.getFont()
            if not res or res.cap < cap or res.font ~= font then
                if res and res.obj then res.obj:release() end
                local obj = lg.newText(font)
                res = { obj = obj, cap = cap, font = font, cache = false }
                state.text_res[i] = res
            end
            if res.cache ~= c.text then
                res.obj:set(c.text)
                res.cache = c.text
            end
            lg.setColor(rgba8_to_love(c.rgba8))
            lg.draw(res.obj, c.x, c.y)
        elseif k == "PushClip" then
            -- intersect with current scissor
            local sd = state.clip_depth + 1
            state.clip_depth = sd
            local nx, ny, nw, nh = c.x, c.y, c.w, c.h
            if sd > 1 then
                local p = state.clip_stack[sd - 1]
                local x2 = math.max(nx, p[1])
                local y2 = math.max(ny, p[2])
                local r2 = math.min(nx + nw, p[1] + p[3])
                local b2 = math.min(ny + nh, p[2] + p[4])
                nx, ny, nw, nh = x2, y2, math.max(0, r2 - x2), math.max(0, b2 - y2)
            end
            state.clip_stack[sd] = { nx, ny, nw, nh }
            lg.setScissor(nx, ny, nw, nh)
        elseif k == "PopClip" then
            state.clip_depth = state.clip_depth - 1
            if state.clip_depth > 0 then
                local p = state.clip_stack[state.clip_depth]
                lg.setScissor(p[1], p[2], p[3], p[4])
            else
                lg.setScissor()
            end
        elseif k == "PushTransform" then
            lg.push("transform")
            lg.translate(c.tx, c.ty)
        elseif k == "PopTransform" then
            lg.pop()
        end
    end
    lg.setColor(1, 1, 1, 1)
    lg.setScissor()
end

-- Hit gen: walks HCmd* linearly, returns first hit (back-to-front)
local function hit_gen(param, state, query)
    local cmds = param.cmds
    local best = nil
    local tx, ty = 0, 0
    local tstack = state.tstack
    local tdepth = 0
    local clip_ok = true
    local cstack = state.cstack
    local cdepth = 0

    for i = 1, #cmds do
        local c = cmds[i]
        local k = c.kind
        if k == "Rect" then
            if clip_ok then
                local ax, ay = c.x + tx, c.y + ty
                local qx, qy = query.x, query.y
                if qx >= ax and qy >= ay and qx < ax + c.w and qy < ay + c.h then
                    best = { tag = c.tag, x = ax, y = ay, w = c.w, h = c.h }
                end
            end
        elseif k == "PushTransform" then
            tdepth = tdepth + 1
            tstack[tdepth] = { tx, ty }
            tx, ty = tx + c.tx, ty + c.ty
        elseif k == "PopTransform" then
            local p = tstack[tdepth]; tdepth = tdepth - 1
            tx, ty = p[1], p[2]
        elseif k == "PushClip" then
            cdepth = cdepth + 1
            local ax, ay = c.x + tx, c.y + ty
            cstack[cdepth] = clip_ok
            if clip_ok then
                local qx, qy = query.x, query.y
                if not (qx >= ax and qy >= ay and qx < ax + c.w and qy < ay + c.h) then
                    clip_ok = false
                end
            end
        elseif k == "PopClip" then
            clip_ok = cstack[cdepth]; cdepth = cdepth - 1
        end
    end
    return best
end

-- State alloc/shapes for the two terminals
local paint_state_decl = M.state.table("paint_state", {
    init = function()
        return { text_res = {}, clip_stack = {}, clip_depth = 0 }
    end,
    release = function(s)
        for _, r in pairs(s.text_res) do
            if r.obj then r.obj:release() end
        end
    end,
})

local hit_state_decl = M.state.table("hit_state", {
    init = function()
        return { tstack = {}, cstack = {} }
    end,
})

-- ══════════════════════════════════════════════════════════════
--  UI ASDL  (user-authored tree — the ONLY recursive structure)
-- ══════════════════════════════════════════════════════════════

local U = M.context("flatten"):Define [[
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

local function text_metrics(fid, text)
    local f = fonts[fid] or love.graphics.getFont()
    return f:getWidth(text), f:getHeight()
end

-- ── measure (pure, no output) ────────────────────────────────

function U.UI.Rect:measure()    return self.w, self.h end
function U.UI.Text:measure()    return text_metrics(self.font_id, self.text) end
function U.UI.Spacer:measure()  return self.w, self.h end
function U.UI.Padding:measure()
    local cw, ch = self.child:measure()
    return self.left + cw + self.right, self.top + ch + self.bottom
end
function U.UI.Column:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        if cw > w then w = cw end; h = h + ch; if i > 1 then h = h + self.spacing end
    end; return w, h
end
function U.UI.Row:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        w = w + cw; if i > 1 then w = w + self.spacing end; if ch > h then h = ch end
    end; return w, h
end
function U.UI.Group:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        if cw > w then w = cw end; if ch > h then h = ch end
    end; return w, h
end
function U.UI.Align:measure()     return self.w, self.h end
function U.UI.Clip:measure()      return self.w, self.h end
function U.UI.Transform:measure() return self.child:measure() end

-- ── place (the ONE recursive pass — outputs to flat cmd lists) ─

function U.UI.Rect:place(x, y, dc, hc)
    dc[#dc+1] = FR(x, y, self.w, self.h, self.rgba8)
    hc[#hc+1] = HR(x, y, self.w, self.h, self.tag)
end
function U.UI.Text:place(x, y, dc, hc)
    local w, h = self:measure()
    dc[#dc+1] = DT(x, y, self.font_id, self.rgba8, self.text)
    hc[#hc+1] = HR(x, y, w, h, self.tag)
end
function U.UI.Spacer:place() end
function U.UI.Padding:place(x, y, dc, hc)
    self.child:place(x + self.left, y + self.top, dc, hc)
end
function U.UI.Column:place(x, y, dc, hc)
    local cy = y
    for i = 1, #self.children do
        local c = self.children[i]
        local _, ch = c:measure()
        c:place(x, cy, dc, hc)
        cy = cy + ch + self.spacing
    end
end
function U.UI.Row:place(x, y, dc, hc)
    local cx = x
    for i = 1, #self.children do
        local c = self.children[i]
        local cw = c:measure()
        c:place(cx, y, dc, hc)
        cx = cx + cw + self.spacing
    end
end
function U.UI.Group:place(x, y, dc, hc)
    for i = 1, #self.children do
        self.children[i]:place(x, y, dc, hc)
    end
end
function U.UI.Align:place(x, y, dc, hc)
    local cw, ch = self.child:measure()
    local cx, cy = x, y
    if     self.halign.kind == "Center" then cx = x + math.floor((self.w - cw) / 2)
    elseif self.halign.kind == "Right"  then cx = x + (self.w - cw) end
    if     self.valign.kind == "Middle" then cy = y + math.floor((self.h - ch) / 2)
    elseif self.valign.kind == "Bottom" then cy = y + (self.h - ch) end
    self.child:place(cx, cy, dc, hc)
end
function U.UI.Clip:place(x, y, dc, hc)
    dc[#dc+1] = DPC(x, y, self.w, self.h)
    hc[#hc+1] = HPC(x, y, self.w, self.h)
    self.child:place(x, y, dc, hc)
    dc[#dc+1] = DXC
    hc[#hc+1] = HXC
end
function U.UI.Transform:place(x, y, dc, hc)
    dc[#dc+1] = DPT(self.tx, self.ty)
    hc[#hc+1] = HPT(self.tx, self.ty)
    self.child:place(x, y, dc, hc)
    dc[#dc+1] = DXT
    hc[#hc+1] = HXT
end

-- ── Root:flatten — the public entry: tree in, two flat lists out ─

function U.UI.Root:flatten()
    local dc, hc = {}, {}
    self.body:place(0, 0, dc, hc)
    return D.Draw.Frame(dc), H.Hit.Frame(hc)
end

-- ══════════════════════════════════════════════════════════════
--  PIPELINES  — one M.lower per backend, single emit each
-- ══════════════════════════════════════════════════════════════

local compile_paint = M.lower("paint", function(root)
    local draw_frame = root:flatten()  -- uses cached hit_frame too, see below
    return M.emit(paint_gen, paint_state_decl, { cmds = draw_frame.cmds })
end)

-- We need both frames from one flatten call. Cache it.
local flatten_cache_key = nil
local flatten_cache_draw = nil
local flatten_cache_hit  = nil

local function get_frames(root)
    if flatten_cache_key == root then
        return flatten_cache_draw, flatten_cache_hit
    end
    local df, hf = root:flatten()
    flatten_cache_key  = root
    flatten_cache_draw = df
    flatten_cache_hit  = hf
    return df, hf
end

local compile_paint2 = M.lower("paint", function(root)
    local df = get_frames(root)
    return M.emit(paint_gen, paint_state_decl, { cmds = df.cmds })
end)

local compile_hit2 = M.lower("hit", function(root)
    local _, hf = get_frames(root)
    return M.emit(hit_gen, hit_state_decl, { cmds = hf.cmds })
end)

-- ══════════════════════════════════════════════════════════════
--  APPLICATION STATE  (identical to ui1)
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

local ROW_H, HEADER_H, TRACK_W, METER_W = 48, 40, 220, 6
local TRANSPORT_H, INSP_W = 52, 280

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

local Col, Row, Grp, Pad, Ali, Clp, Tfm, Rct, Txt, Spc =
    U.UI.Column, U.UI.Row, U.UI.Group, U.UI.Padding, U.UI.Align,
    U.UI.Clip, U.UI.Transform, U.UI.Rect, U.UI.Text, U.UI.Spacer
local Lft, Cen, Rgt = U.UI.Left, U.UI.Center, U.UI.Right
local Top, Mid, Bot = U.UI.Top, U.UI.Middle, U.UI.Bottom

local function make_initial_state()
    local tracks = {}
    for i = 1, #TRACK_NAMES do
        tracks[i] = {
            name = TRACK_NAMES[i], color = TRACK_COLORS[i],
            vol = 0.75, pan = 0.5, mute = false, solo = false, meter = 0,
        }
    end
    return {
        tracks = tracks, selected = 1, hover_tag = nil, scroll_y = 0,
        bpm = 120, playing = false, beat = 0, time_sec = 0,
        dragging = nil, show_debug = false, win_w = 1100, win_h = 700,
    }
end

local S
local paint_slot, hit_slot

-- ══════════════════════════════════════════════════════════════
--  WIDGET BUILDERS  (identical to ui1)
-- ══════════════════════════════════════════════════════════════

local function btn(tag, w, h, bg, fg, fid, label, hovered)
    return Grp({
        Rct(tag, w, h, hovered and C.panel_hi or bg),
        Ali(w, h, Cen, Mid, Txt(tag..":l", fid, fg, label)),
    })
end

local function meter_w(tag, w, h, level)
    local fill = math.floor(w * clamp(level, 0, 1))
    local col = level > 0.9 and C.meter_clip or (level > 0.7 and C.meter_hot or C.meter_fill)
    return Grp({ Rct(tag, w, h, C.meter_bg), Rct(tag..":f", fill, h, col) })
end

local function pan_widget(tag, w, h, pv, hovered)
    local center = math.floor(w / 2)
    local pos = math.floor(pv * w)
    local left, right = math.min(center, pos), math.max(center, pos)
    return Grp({
        Rct(tag, w, h, hovered and C.knob_arc or C.knob_bg),
        Tfm(left, 0, Rct(tag..":v", math.max(2, right - left), h, C.knob_fg)),
    })
end

local function vol_widget(tag, w, h, vol, hovered)
    local fill = math.floor(w * clamp(vol, 0, 1))
    return Grp({
        Rct(tag, w, h, hovered and C.knob_arc or C.knob_bg),
        Rct(tag..":v", fill, h, C.knob_fg),
    })
end

local function track_row(i, t, selected, hover)
    local tag = "track:"..i
    local htag = hover or ""
    local is_hovered = hover and (hover == tag or hover:sub(1, #tag+1) == tag..":")
    local bg = (i == selected) and C.row_active
             or is_hovered and C.row_hover
             or (i % 2 == 0) and C.row_even or C.row_odd
    local nfg = (i == selected) and C.text_bright or C.text
    return Grp({
        Rct(tag, TRACK_W, ROW_H, bg),
        Row(0, {
            Rct(tag..":pip", 4, ROW_H, t.color),
            Pad(8,0,0,0, Ali(120, ROW_H, Lft, Mid, Txt(tag..":name", 2, nfg, t.name))),
            Pad(0,14,4,14, Row(4, {
                btn(tag..":mute", 24, 20, t.mute and C.mute_on or C.panel,
                    t.mute and C.text_bright or C.text_dim, 4, "M", htag==tag..":mute"),
                btn(tag..":solo", 24, 20, t.solo and C.solo_on or C.panel,
                    t.solo and C.text_bright or C.text_dim, 4, "S", htag==tag..":solo"),
            })),
            Pad(0,19,0,19, vol_widget(tag..":vol", 60, 10, t.vol,
                htag==tag..":vol" or htag==tag..":vol:v")),
            Pad(4,19,4,19, pan_widget(tag..":pan", 40, 10, t.pan,
                htag==tag..":pan" or htag==tag..":pan:v")),
            Pad(2,4,4,4, meter_w(tag..":meter", METER_W, ROW_H-8, t.meter)),
        }),
    })
end

local function transport_bar(s)
    local htag = s.hover_tag or ""
    local play_label = s.playing and "||" or ">"
    local m = math.floor(s.time_sec / 60)
    local sc = math.floor(s.time_sec) % 60
    local ms = math.floor((s.time_sec * 1000) % 1000)
    return Grp({
        Rct("transport", s.win_w, TRANSPORT_H, C.transport_bg),
        Rct("transport:border", s.win_w, 1, C.border),
        Pad(16,0,16,0, Row(16, {
            Ali(80, TRANSPORT_H, Cen, Mid,
                btn("transport:play", 48, 30, s.playing and C.accent_dim or C.panel,
                    C.text_bright, 3, play_label, htag=="transport:play")),
            Ali(60, TRANSPORT_H, Cen, Mid,
                btn("transport:stop", 48, 30, C.panel, C.text, 3, "[]", htag=="transport:stop")),
            Rct("transport:sep1", 1, TRANSPORT_H-16, C.border),
            Ali(100, TRANSPORT_H, Cen, Mid, Col(2, {
                Txt("transport:tl", 4, C.text_dim, "TIME"),
                Txt("transport:time", 3, C.text_bright, string.format("%02d:%02d.%03d", m, sc, ms)),
            })),
            Ali(60, TRANSPORT_H, Cen, Mid, Col(2, {
                Txt("transport:bl", 4, C.text_dim, "BEAT"),
                Txt("transport:beat", 3, C.text_bright, string.format("%.1f", s.beat+1)),
            })),
            Rct("transport:sep2", 1, TRANSPORT_H-16, C.border),
            Ali(80, TRANSPORT_H, Cen, Mid, Col(2, {
                Txt("transport:bpml", 4, C.text_dim, "BPM"),
                Row(4, {
                    btn("transport:bpm-", 22, 20, C.panel, C.text, 4, "-", htag=="transport:bpm-"),
                    Txt("transport:bpm", 3, C.accent, tostring(s.bpm)),
                    btn("transport:bpm+", 22, 20, C.panel, C.text, 4, "+", htag=="transport:bpm+"),
                }),
            })),
            Spc(20,1),
            Ali(200, TRANSPORT_H, Lft, Mid,
                Txt("transport:status", 4, C.text_dim, s.playing and "RECORDING" or "STOPPED")),
        })),
    })
end

local function inspector_panel(s)
    local t = s.tracks[s.selected]
    local htag = s.hover_tag or ""
    local function kv(key, val, tag)
        return Row(0, {
            Ali(90,22,Lft,Mid, Txt(tag..":k",4,C.text_dim,key)),
            Ali(160,22,Lft,Mid, Txt(tag..":v",2,C.text,val)),
        })
    end
    return Grp({
        Rct("insp", INSP_W, s.win_h-TRANSPORT_H, C.panel),
        Rct("insp:border", 1, s.win_h-TRANSPORT_H, C.border),
        Pad(16,16,16,16, Col(10, {
            Txt("insp:title", 3, C.text_bright, "Inspector"),
            Rct("insp:sep", INSP_W-32, 1, C.border),
            Col(4, {
                kv("Track", t.name, "insp:name"),
                kv("Index", tostring(s.selected), "insp:idx"),
                kv("Volume", string.format("%.0f%%", t.vol*100), "insp:vol"),
                kv("Pan", string.format("%.0f%%", (t.pan-0.5)*200), "insp:pan"),
                kv("Mute", t.mute and "ON" or "off", "insp:mute"),
                kv("Solo", t.solo and "ON" or "off", "insp:solo"),
            }),
            Rct("insp:sep2", INSP_W-32, 1, C.border),
            Txt("insp:vl", 4, C.text_dim, "Volume"),
            vol_widget("insp:vol_slider", INSP_W-32, 14, t.vol, htag:match("^insp:vol_slider")),
            Txt("insp:pl", 4, C.text_dim, "Pan"),
            pan_widget("insp:pan_slider", INSP_W-32, 14, t.pan, htag:match("^insp:pan_slider")),
            Rct("insp:sep3", INSP_W-32, 1, C.border),
            Row(8, {
                btn("insp:mute_btn", 70, 28,
                    t.mute and C.mute_on or C.panel, t.mute and C.text_bright or C.text,
                    2, t.mute and "MUTED" or "Mute", htag=="insp:mute_btn"),
                btn("insp:solo_btn", 70, 28,
                    t.solo and C.solo_on or C.panel, t.solo and C.text_bright or C.text,
                    2, t.solo and "SOLO'D" or "Solo", htag=="insp:solo_btn"),
            }),
        })),
    })
end

local function vscrollbar(tag, total_h, view_h, scroll_y, bar_h, hover)
    if total_h <= view_h then return Spc(0,0) end
    local ratio = view_h / total_h
    local thumb_h = math.max(20, math.floor(bar_h * ratio))
    local max_s = total_h - view_h
    local thumb_y = math.floor((scroll_y / max_s) * (bar_h - thumb_h))
    return Grp({
        Rct(tag, 8, bar_h, C.scrollbar),
        Tfm(0, thumb_y, Rct(tag..":thumb", 8, thumb_h,
            (hover and hover:match("^"..tag)) and C.accent or C.scrollthumb)),
    })
end

local function build_ui(s)
    local list_h = #s.tracks * ROW_H
    local view_h = s.win_h - TRANSPORT_H - HEADER_H
    local scroll = clamp(s.scroll_y, 0, math.max(0, list_h - view_h))

    local track_rows = {}
    for i = 1, #s.tracks do
        track_rows[i] = Tfm(0, (i-1)*ROW_H,
            track_row(i, s.tracks[i], s.selected, s.hover_tag))
    end

    local header = Grp({
        Rct("header", TRACK_W+8, HEADER_H, C.panel),
        Rct("header:border", TRACK_W+8, 1, C.border),
        Pad(14,0,0,0, Ali(TRACK_W, HEADER_H, Lft, Mid,
            Row(12, {
                Txt("header:title", 3, C.text_bright, "Tracks"),
                Txt("header:count", 4, C.text_dim, string.format("(%d)", #s.tracks)),
            }))),
    })

    local left = Col(0, {
        header,
        Grp({
            Rct("tracklist_bg", TRACK_W+8, view_h, C.bg),
            Clp(TRACK_W, view_h, Tfm(0, -scroll, Grp(track_rows))),
            Tfm(TRACK_W, 0, vscrollbar("scroll", list_h, view_h, scroll, view_h, s.hover_tag)),
        }),
    })

    -- arrangement
    local arr_w = s.win_w - TRACK_W - 8 - INSP_W
    local arr_h = s.win_h - TRANSPORT_H
    local px_per_beat = 60
    local nbeats = math.ceil(arr_w / px_per_beat) + 1

    local grid = {}
    for b = 0, nbeats do
        local bx = b * px_per_beat
        grid[#grid+1] = Tfm(bx, 0,
            Rct("grid:"..b, 1, arr_h-HEADER_H, (b%4==0) and C.border or C.panel))
    end

    local lanes = {}
    for i = 1, #s.tracks do
        local t = s.tracks[i]
        local ly = (i-1)*ROW_H - scroll
        local cx = ((i*37)%8)*px_per_beat
        local cw = (2+(i%3))*px_per_beat
        lanes[#lanes+1] = Tfm(cx, ly+4, Grp({
            Rct("clip:"..i, cw, ROW_H-8, t.color),
            Pad(6,2,0,0, Txt("clip:"..i..":n", 4, C.text_bright, t.name)),
        }))
    end

    local ruler = {}
    for b = 0, nbeats do
        local bx = b * px_per_beat
        if b % 4 == 0 then
            ruler[#ruler+1] = Tfm(bx+4, 0,
                Txt("ruler:"..b, 4, C.text_dim, tostring(math.floor(b/4)+1)))
        end
        ruler[#ruler+1] = Tfm(bx, 0,
            Rct("ruler:t:"..b, 1, (b%4==0) and HEADER_H or 10, C.border))
    end

    local playhead_x = math.floor(s.beat * px_per_beat)

    local arrangement = Grp({
        Rct("arr_bg", arr_w, arr_h, C.bg),
        Grp({ Rct("ruler_bg", arr_w, HEADER_H, C.panel), Clp(arr_w, HEADER_H, Grp(ruler)) }),
        Tfm(0, HEADER_H, Clp(arr_w, arr_h-HEADER_H, Grp(lanes))),
        Tfm(0, HEADER_H, Clp(arr_w, arr_h-HEADER_H, Grp(grid))),
        Tfm(playhead_x, 0, Rct("playhead", 2, arr_h, C.text_bright)),
    })

    return U.UI.Root(Col(0, {
        Row(0, { left, arrangement, inspector_panel(s) }),
        transport_bar(s),
    }))
end

-- ══════════════════════════════════════════════════════════════
--  RECOMPILE + INPUT  (identical logic to ui1)
-- ══════════════════════════════════════════════════════════════

local function recompile()
    flatten_cache_key = nil  -- invalidate shared cache
    local root = build_ui(S)
    paint_slot:update(compile_paint2(root))
    hit_slot:update(compile_hit2(root))
end

local function update_hover(mx, my)
    local hit = hit_slot.callback({ x = mx, y = my })
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
    paint_slot = M.slot()
    hit_slot   = M.slot()
    recompile()
end

function love.resize(w, h)
    S.win_w, S.win_h = w, h
    recompile()
end

function love.update(dt)
    local changed = false
    for i = 1, #S.tracks do
        local t = S.tracks[i]
        local target = 0
        if S.playing and not t.mute then
            target = (0.3 + 0.5 * math.abs(math.sin(S.time_sec*(1.5+i*0.3)+i*0.7))) * t.vol
        end
        local old = t.meter
        t.meter = t.meter + (target - t.meter) * math.min(1, dt * 12)
        if math.abs(t.meter - old) > 0.002 then changed = true end
    end
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
        if not S.playing then for i=1,#S.tracks do S.tracks[i].meter=0 end end
        recompile(); return
    end
    if key == "d" then S.show_debug = not S.show_debug; return end
    if key == "up"   then S.selected = math.max(1, S.selected-1); recompile(); return end
    if key == "down" then S.selected = math.min(#S.tracks, S.selected+1); recompile(); return end
    if key == "m" then S.tracks[S.selected].mute = not S.tracks[S.selected].mute; recompile(); return end
    if key == "s" then S.tracks[S.selected].solo = not S.tracks[S.selected].solo; recompile(); return end
    if key == "r" then
        S.time_sec=0; S.beat=0; S.playing=false
        for i=1,#S.tracks do S.tracks[i].meter=0 end; recompile(); return
    end
end

function love.mousepressed(mx, my, bi)
    if bi ~= 1 then return end
    local hit = hit_slot.callback({ x = mx, y = my })
    if not hit then return end
    local tag = hit.tag
    local ti = track_from_tag(tag)
    if ti then
        S.selected = ti
        if tag:match(":mute") then S.tracks[ti].mute = not S.tracks[ti].mute
        elseif tag:match(":solo") then S.tracks[ti].solo = not S.tracks[ti].solo
        elseif tag:match(":vol") then
            S.dragging = {idx=ti,field="vol",x0=mx,val0=S.tracks[ti].vol,w=60}
        elseif tag:match(":pan") then
            S.dragging = {idx=ti,field="pan",x0=mx,val0=S.tracks[ti].pan,w=40}
        end; recompile(); return
    end
    if tag:match("^insp:vol_slider") then
        S.dragging = {idx=S.selected,field="vol",x0=mx,val0=S.tracks[S.selected].vol,w=INSP_W-32}
        recompile(); return end
    if tag:match("^insp:pan_slider") then
        S.dragging = {idx=S.selected,field="pan",x0=mx,val0=S.tracks[S.selected].pan,w=INSP_W-32}
        recompile(); return end
    if tag:match("^insp:mute_btn") then S.tracks[S.selected].mute = not S.tracks[S.selected].mute; recompile(); return end
    if tag:match("^insp:solo_btn") then S.tracks[S.selected].solo = not S.tracks[S.selected].solo; recompile(); return end
    if tag == "transport:play" then
        S.playing = not S.playing
        if not S.playing then for i=1,#S.tracks do S.tracks[i].meter=0 end end; recompile(); return end
    if tag == "transport:stop" then
        S.playing=false; S.time_sec=0; S.beat=0
        for i=1,#S.tracks do S.tracks[i].meter=0 end; recompile(); return end
    if tag == "transport:bpm-" then S.bpm = math.max(40, S.bpm-5); recompile(); return end
    if tag == "transport:bpm+" then S.bpm = math.min(300, S.bpm+5); recompile(); return end
end

function love.mousereleased()
    if S.dragging then S.dragging = nil; recompile() end
end

function love.mousemoved(mx, my)
    if S.dragging then
        local d = S.dragging
        S.tracks[d.idx][d.field] = clamp(d.val0 + (mx - d.x0) / d.w, 0, 1)
        recompile()
    end
    update_hover(mx, my)
end

function love.wheelmoved(_, wy)
    local list_h = #S.tracks * ROW_H
    local view_h = S.win_h - TRANSPORT_H - HEADER_H
    S.scroll_y = clamp(S.scroll_y - wy*30, 0, math.max(0, list_h - view_h))
    recompile()
    update_hover(love.mouse.getPosition())
end

function love.draw()
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setColor(1,1,1,1)
    paint_slot.callback()

    if S.show_debug then
        local report = M.report({ compile_paint2, compile_hit2 })
        love.graphics.setFont(fonts[4])
        love.graphics.setColor(0,0,0,0.75)
        love.graphics.rectangle("fill", 4, S.win_h-80, 600, 76)
        love.graphics.setColor(0.7,0.85,1,1)
        love.graphics.print(report, 8, S.win_h-76)
        love.graphics.print(string.format(
            "hover: %s  sel: %d  fps: %d  dt: %.1fms  draw_cmds: %d  hit_cmds: %d",
            tostring(S.hover_tag), S.selected,
            love.timer.getFPS(), love.timer.getAverageDelta()*1000,
            flatten_cache_draw and #flatten_cache_draw.cmds or 0,
            flatten_cache_hit and #flatten_cache_hit.cmds or 0),
            8, S.win_h-30)
        love.graphics.setColor(1,1,1,1)
    end
end
