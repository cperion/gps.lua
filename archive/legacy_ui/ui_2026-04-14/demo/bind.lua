-- ui/demo/bind.lua
-- Demo-specific terminal binding. No PVM boundaries here.

local M = {}

local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_sin = math.sin
local math_cos = math.cos

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

local RULER_H = 22
local TRACK_ROW_H = 72
local DEVICE_CAP = 6
local LOG_ROWS = 4

local function text_align_name(align)
    if align == "center" then return "center" end
    if align == "right" then return "right" end
    if align == "justify" then return "justify" end
    return "left"
end

local function device_color(family)
    if family == "Instrument" or family == "CLAP" then return C.green end
    if family == "NoteFX" then return C.teal end
    if family == "Analyzer" then return C.yellow end
    if family == "AudioFX" or family == "VST3" or family == "VST2" or family == "AU" then return C.blue end
    return C.orange
end

local function backend_text(ctx, api, text, x, y, w, font_id, color, align)
    if not api.visible_in_clip(ctx, x, y, w, 16) then
        return
    end
    api.backend_set_font(ctx.backend, font_id or 2)
    api.backend_set_color(ctx.backend, color, 1)
    if ctx.backend and ctx.backend.draw_text then
        ctx.backend:draw_text(text or "", x, y, math_max(1, w or 1), text_align_name(align))
    end
end

local function fill(ctx, api, x, y, w, h, color)
    if w <= 0 or h <= 0 or not api.visible_in_clip(ctx, x, y, w, h) then
        return
    end
    api.backend_set_color(ctx.backend, color, 1)
    api.fill_rect(ctx.backend, x, y, w, h)
end

local function stroke(ctx, api, x, y, w, h, thickness, color)
    if w <= 0 or h <= 0 or not api.visible_in_clip(ctx, x, y, w, h) then
        return
    end
    api.backend_set_color(ctx.backend, color, 1)
    api.stroke_rect(ctx.backend, x, y, w, h, thickness or 1)
end

local function line(ctx, api, x1, y1, x2, y2, thickness, color)
    local min_x = math_min(x1, x2)
    local min_y = math_min(y1, y2)
    local max_x = math_max(x1, x2)
    local max_y = math_max(y1, y2)
    if not api.visible_in_clip(ctx, min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) then
        return
    end
    if ctx.backend and ctx.backend.draw_line then
        api.backend_set_color(ctx.backend, color, 1)
        ctx.backend:draw_line(x1, y1, x2, y2, thickness or 1)
    end
end

function M.resolve_runtime_text(node, opts)
    local live = opts and (opts.runtime or opts.env)
    if not live then
        return node.text or ""
    end
    local tag = node.tag
    local texts = live.texts
    if tag == "transport:clock" then
        return texts.clock
    elseif tag == "inspector:reuse" then
        return texts.reuse
    elseif tag == "devices:subtitle" then
        return texts.devices_subtitle
    elseif tag == "status:right" then
        return texts.status_right
    end
    return node.text or ""
end

local function draw_arrangement(node, ctx, api, live, view)
    local frame = node.frame
    local x0, y0, w, h = frame.x, frame.y, frame.w, frame.h
    local body_y = y0 + RULER_H + 14
    local header_w = 178
    local body_h = math_max(0, h - (RULER_H + 14))
    local timeline_x = x0 + header_w
    local timeline_w = math_max(80, w - header_w - 12)
    local note_x = x0 + math_max(10, w - 220)
    local note_w = 200
    local beat_count = math_max(1, view.beat_count)

    api.push_clip(ctx, x0, y0, w, h)

    fill(ctx, api, x0, y0, w, h, C.base)
    stroke(ctx, api, x0, y0, w, h, 1, C.surface1)
    backend_text(ctx, api, view.title, x0 + 12, y0 + 6, 240, 2, C.subtext0, "left")
    backend_text(ctx, api, view.note, note_x, y0 + 6, note_w, 1, C.overlay0, "right")

    fill(ctx, api, x0, body_y, header_w, body_h, C.mantle)
    fill(ctx, api, timeline_x, body_y, timeline_w, body_h, C.base)
    line(ctx, api, x0, body_y, x0 + w, body_y, 1, C.surface1)
    line(ctx, api, timeline_x, body_y, timeline_x, y0 + h, 1, C.surface1)

    for beat = 0, beat_count do
        local bx = timeline_x + math_floor((beat / beat_count) * timeline_w)
        line(ctx, api, bx, body_y, bx, y0 + h, 1, (beat % 2 == 0) and C.surface1 or C.surface0)
        if beat < beat_count then
            backend_text(ctx, api, tostring(beat + 1), bx + 4, y0 + 30, 40, 1, C.overlay0, "left")
        end
    end

    for i = 1, #view.tracks do
        local track = view.tracks[i]
        local ty = body_y + (i - 1) * TRACK_ROW_H
        fill(ctx, api, x0, ty, w, TRACK_ROW_H, (i == live.selected_track) and C.surface0 or C.mantle)
        line(ctx, api, x0, ty + TRACK_ROW_H, x0 + w, ty + TRACK_ROW_H, 1, C.surface0)
        if view.overlay_mode == "routing" then
            local rx1 = timeline_x + 28
            local rx2 = x0 + w - 170
            local rw = 110
            local ry = ty + 14
            fill(ctx, api, rx1, ry, rw, 28, track.color)
            stroke(ctx, api, rx1, ry, rw, 28, 1, C.crust)
            backend_text(ctx, api, track.title, rx1 + 8, ry + 7, rw - 10, 1, C.crust, "left")
            fill(ctx, api, rx2, ry, rw, 28, C.surface1)
            stroke(ctx, api, rx2, ry, rw, 28, 1, C.crust)
            backend_text(ctx, api, track.route, rx2 + 8, ry + 7, rw - 10, 1, C.crust, "left")
            line(ctx, api, rx1 + rw, ry + 14, rx2, ry + 14, 2, (i == live.selected_track) and C.yellow or C.overlay0)
        elseif view.overlay_mode == "machine" then
            local box_w = math_max(48, math_floor((timeline_w - 40) / 3))
            local labels = { "feeder", "chain", "out" }
            local fills = { C.teal, C.blue, C.green }
            for j = 1, 3 do
                local mx = timeline_x + 16 + (j - 1) * (box_w + 10)
                local my = ty + 14
                fill(ctx, api, mx, my, box_w, 28, fills[j])
                stroke(ctx, api, mx, my, box_w, 28, 1, (i == live.selected_track) and C.yellow or C.crust)
                backend_text(ctx, api, labels[j], mx + 8, my + 7, box_w - 10, 1, C.crust, "left")
            end
        end
    end

    local playhead_x = timeline_x + math_floor(((live.transport_beat % beat_count) / beat_count) * timeline_w)
    line(ctx, api, playhead_x, body_y, playhead_x, y0 + h, 2, C.yellow)

    if view.overlay_mode == "arrange" then
        for i = 1, #view.clips do
            local clip = view.clips[i]
            local cx = timeline_x + math_floor((clip.start_beat / beat_count) * timeline_w) + 3
            local cy = body_y + (clip.track_index - 1) * TRACK_ROW_H + 8
            local cw = math_max(24, math_floor((clip.length_beat / beat_count) * timeline_w) - 6)
            fill(ctx, api, cx, cy, cw, TRACK_ROW_H - 16, clip.color)
            stroke(ctx, api, cx, cy, cw, TRACK_ROW_H - 16, 1, clip.warped and C.mauve or C.crust)
            backend_text(ctx, api, clip.label .. (clip.warped and " · warp" or ""), cx + 8, cy + 6, math_max(8, cw - 12), 1, C.crust, "left")
        end

        local selected_y = body_y + (live.selected_track - 1) * TRACK_ROW_H + TRACK_ROW_H - 18
        for i = 1, 5 do
            local x1 = timeline_x + math_floor(((i - 1) / 5) * timeline_w)
            local x2 = timeline_x + math_floor((i / 5) * timeline_w)
            local y1 = selected_y - math_floor((0.5 + 0.5 * math_sin(live.time * 0.8 + i * 0.4)) * 20)
            local y2 = selected_y - math_floor((0.5 + 0.5 * math_cos(live.time * 1.1 + i * 0.5)) * 18)
            line(ctx, api, x1, y1, x2, y2, 2, (i == 3) and C.yellow or C.orange)
        end
    end

    api.pop_clip(ctx)
end

local function draw_devices(node, ctx, api, live, view, subtitle)
    local frame = node.frame
    local x0, y0, w, h = frame.x, frame.y, frame.w, frame.h
    local note_x = x0 + math_max(10, w - 220)
    local note_w = 200
    local cards = view.devices
    local slots = math_max(1, #cards)
    local gap = 10
    local info_w = 270
    local content_w = math_max(120, w - info_w - 26)
    local slot_w = math_max(52, math_floor((content_w - gap * math_max(0, slots - 1)) / slots))
    local info_x = x0 + w - info_w - 12
    local bar_w = info_w - 20
    local reuse_w = math_floor(bar_w * math_max(0, math_min(1, live.reuse or 0)))

    api.push_clip(ctx, x0, y0, w, h)

    fill(ctx, api, x0, y0, w, h, C.base)
    stroke(ctx, api, x0, y0, w, h, 1, C.surface1)
    backend_text(ctx, api, view.title, x0 + 12, y0 + 8, 280, 2, C.subtext0, "left")
    backend_text(ctx, api, subtitle or "", note_x, y0 + 8, note_w, 1, C.overlay0, "right")

    for i = 1, #cards do
        local card = cards[i]
        local sx = x0 + 12 + (i - 1) * (slot_w + gap)
        local sy = y0 + 34
        fill(ctx, api, sx, sy, slot_w, 92, device_color(card.family))
        stroke(ctx, api, sx, sy, slot_w, 92, 1, (i == 1) and C.yellow or C.crust)
        backend_text(ctx, api, card.name, sx + 8, sy + 8, math_max(10, slot_w - 12), 1, C.crust, "left")
        backend_text(ctx, api, card.family, sx + 8, sy + 28, math_max(10, slot_w - 12), 1, C.overlay0, "left")
        for k = 1, 3 do
            local level = 0.2 + 0.65 * (0.5 + 0.5 * math_sin(live.time * (1.4 + k * 0.2) + i + k))
            local bar_h = math_floor(24 * level)
            local bar_x = sx + 12 + (k - 1) * 20
            stroke(ctx, api, bar_x, sy + 48, 14, 24, 1, C.surface1)
            fill(ctx, api, bar_x, sy + 72 - bar_h, 14, bar_h, (k == 2) and C.yellow or C.crust)
        end
    end

    fill(ctx, api, info_x, y0 + 34, info_w, 72, C.mantle)
    stroke(ctx, api, info_x, y0 + 34, info_w, 72, 1, C.surface1)
    backend_text(ctx, api, "stage · " .. (live.phase_verb or ""), info_x + 10, y0 + 42, info_w - 16, 1, C.text, "left")
    backend_text(ctx, api, "cb #" .. tostring(live.compile_gen or 0), info_x + 10, y0 + 60, info_w - 16, 1, C.subtext0, "left")
    backend_text(ctx, api, live.phase_title or "", info_x + 10, y0 + 78, info_w - 16, 1, C.subtext0, "left")
    stroke(ctx, api, info_x + 10, y0 + 100, bar_w, 8, 1, C.surface1)
    fill(ctx, api, info_x + 10, y0 + 100, reuse_w, 8, C.blue)
    backend_text(ctx, api,
        string.format("reuse %s", string.format("%.1f%%", (live.reuse or 0) * 100)),
        info_x + 10, y0 + 114, info_w - 16, 4, C.overlay0, "left")

    local first = math_max(1, #live.logs - LOG_ROWS + 1)
    for i = 1, LOG_ROWS do
        local line_text = live.logs[first + i - 1] or ""
        local fg = C.subtext0
        if line_text:find("no recompile", 1, true) then
            fg = C.green
        elseif line_text:find("rebuild", 1, true) or line_text:find("new machine", 1, true) or line_text:find("compile", 1, true) then
            fg = C.yellow
        end
        backend_text(ctx, api, line_text, x0 + 10, y0 + 132 + (i - 1) * 18, math_max(10, w - 20), 4, fg, "left")
    end

    api.pop_clip(ctx)
end

function M.draw_custom_paint(node, active_id, ctx, api)
    local live = ctx.opts and (ctx.opts.runtime or ctx.opts.env)
    local view = ctx.opts and ctx.opts.view
    if not live or not view then
        return false
    end
    if node.tag == "arr:paint" then
        draw_arrangement(node, ctx, api, live.arrangement, view.arrangement)
        return true
    elseif node.tag == "dev:paint" then
        draw_devices(node, ctx, api, live.devices, view.devices, live.texts.devices_subtitle)
        return true
    end
    return false
end

return M
