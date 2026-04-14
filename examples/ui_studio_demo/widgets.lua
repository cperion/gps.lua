local pvm = require("pvm")
local ui = require("ui")
local studio_asdl = require("demo_asdl")
local demo_apply = require("demo_apply")

local T = studio_asdl.T
local Studio = T.Studio
local View = T.StudioView
local Core = T.Core
local tw = ui.tw
local b = ui.build
local paint = ui.paint

local BROWSER_SCROLL_ID = b.id("browser-scroll")
local LAUNCHER_SCROLL_ID = b.id("launcher-scroll")
local DETAIL_SCROLL_ID = b.id("detail-scroll")

local TOPBAR_H = 96
local SIDE_PANEL_W = 318
local INSPECTOR_W = 372
local CENTER_W_PAD = SIDE_PANEL_W + INSPECTOR_W
local DOCK_H = 244
local CENTER_COLUMN_GAP = 16
local TRACK_HEADER_H = 106
local MATRIX_ROW_H = 142
local SCENE_COL_W = 132

local M = {}

local function id_value(id)
    if id == nil or id == Core.NoId then return nil end
    return id.value
end

local function id_matches(id, value)
    return id ~= nil and id ~= Core.NoId and id.value == value
end

local function is_dark(mode)
    return mode == Studio.ThemeDark
end

local function fg_main(mode)
    return is_dark(mode) and tw.fg.slate[50] or tw.fg.slate[900]
end

local function fg_soft(mode)
    return is_dark(mode) and tw.fg.slate[300] or tw.fg.slate[600]
end

local function fg_dim(mode)
    return is_dark(mode) and tw.fg.slate[500] or tw.fg.slate[500]
end

local function bg_root(mode)
    return is_dark(mode) and tw.bg.slate[950] or tw.bg.slate[100]
end

local function bg_panel(mode)
    return is_dark(mode) and tw.bg.slate[900] or tw.bg.white
end

local function bg_panel_alt(mode)
    return is_dark(mode) and tw.bg.slate[950] or tw.bg.slate[50]
end

local function bg_hover(mode)
    return is_dark(mode) and tw.bg.slate[900] or tw.bg.slate[100]
end

local function bg_selected(mode)
    return is_dark(mode) and tw.bg.slate[900] or tw.bg.white
end

local function border_soft(mode)
    return is_dark(mode) and tw.border_color.slate[800] or tw.border_color.slate[200]
end

local function border_hover(mode)
    return is_dark(mode) and tw.border_color.slate[600] or tw.border_color.slate[300]
end

local function accent_border(mode)
    return is_dark(mode) and tw.border_color.sky[400] or tw.border_color.sky[300]
end

local function accent_text(mode)
    return is_dark(mode) and tw.fg.sky[200] or tw.fg.sky[700]
end

local function tone_fg(mode, tone)
    if tone == View.ToneGreen then return is_dark(mode) and tw.fg.green[300] or tw.fg.green[700] end
    if tone == View.ToneAmber then return is_dark(mode) and tw.fg.amber[300] or tw.fg.amber[700] end
    if tone == View.ToneRose then return is_dark(mode) and tw.fg.rose[300] or tw.fg.rose[700] end
    if tone == View.ToneNeutral then return fg_dim(mode) end
    return is_dark(mode) and tw.fg.blue[300] or tw.fg.blue[700]
end

local function rgba_bg(mode)
    return is_dark(mode) and 0x0f172aff or 0xffffffff
end

local function rgba_panel(mode)
    return is_dark(mode) and 0x020617ff or 0xf8fafcff
end

local function rgba_line(mode)
    return is_dark(mode) and 0x334155ff or 0xcbd5e1ff
end

local function rgba_text(mode)
    return is_dark(mode) and 0xe2e8f0ff or 0x0f172aff
end

local function rgba_muted(mode)
    return is_dark(mode) and 0x94a3b8ff or 0x64748bff
end

local function rgba_accent(mode)
    return is_dark(mode) and 0x38bdf8ff or 0x0284c7ff
end

local function rgba_green(mode)
    return is_dark(mode) and 0x34d399ff or 0x059669ff
end

local function rgba_amber(mode)
    return is_dark(mode) and 0xfbbf24ff or 0xd97706ff
end

local function rgba_violet(mode)
    return is_dark(mode) and 0x93c5fdff or 0x2563ebff
end

local function rgba_rose(mode)
    return is_dark(mode) and 0xfb7185ff or 0xe11d48ff
end

local function rgba_for_tone(mode, tone)
    if tone == View.ToneGreen then return rgba_green(mode) end
    if tone == View.ToneAmber then return rgba_amber(mode) end
    if tone == View.ToneRose then return rgba_rose(mode) end
    if tone == View.ToneNeutral then return rgba_muted(mode) end
    return rgba_accent(mode)
end

local function with_alpha(rgba8, alpha)
    return math.floor(rgba8 / 0x100) * 0x100 + alpha
end

local function eyebrow(mode, text)
    return b.text { tw.text_sm, tw.font_medium, tw.tracking_widest, fg_dim(mode), string.upper(text) }
end

local function device_kind_label(kind)
    if kind == Studio.Instrument then return "instrument" end
    if kind == Studio.Mixer then return "mixer" end
    if kind == Studio.Mod then return "mod" end
    if kind == Studio.Fx then return "fx" end
    return "device"
end

local function selection_summary(app)
    local selection = app.selection
    if selection == Studio.SelTransport then
        return "Transport", app.playing and "The engine is rolling. Macro scenes are armed and transport is live." or "The engine is stopped. Cue the next scene and punch in when ready.", "transport"
    end

    local cls = pvm.classof(selection)
    if cls == Studio.SelBrowser then
        local item = app.browser_items[selection.index]
        return item and item.title or "Browser Item", item and item.note or "Selected browser entry.", "browser"
    elseif cls == Studio.SelTrack then
        local track = app.tracks[selection.index]
        return track and track.name or "Track", track and track.route or "Signal path", "track"
    elseif cls == Studio.SelScene then
        local scene = app.scenes[selection.index]
        return scene and scene.name or "Scene", scene and scene.length or "Performance row", "scene"
    elseif cls == Studio.SelClip then
        local track = app.tracks[selection.track_index]
        local scene = app.scenes[selection.scene_index]
        return (track and scene) and (track.name .. " / " .. scene.name) or "Clip", "Launcher slot with layered texture, launch state, and a tiny custom paint preview.", "clip"
    elseif cls == Studio.SelDevice then
        local dev = app.devices[selection.index]
        return dev and dev.name or "Device", dev and dev.summary or "Processing block", "device"
    end
    return "Selection", "Choose something in the workspace.", "generic"
end

local function brand_mark(mode)
    return b.paint {
        tw.w_px(42), tw.h_px(42),
        paint.circle(21, 21, 18, paint.fill(is_dark(mode) and 0x0b1220ff or 0xf1f5f9ff), paint.stroke(is_dark(mode) and 0x334155ff or 0xcbd5e1ff, 1)),
        paint.arc(21, 21, 12, 3.35, 6.0, 24, paint.stroke(rgba_accent(mode), 3)),
        paint.arc(21, 21, 8, 3.1, 5.15, 24, paint.stroke(rgba_line(mode), 2)),
        paint.polyline({ 10, 25, 16, 18, 21, 22, 27, 13, 32, 16 }, paint.stroke(rgba_accent(mode), 2)),
        paint.circle(29, 16, 3, paint.fill(rgba_amber(mode)), nil),
    }
end

local function theme_icon(mode)
    if is_dark(mode) then
        return b.paint {
            tw.w_px(18), tw.h_px(18),
            paint.circle(9, 9, 5, paint.fill(0xf8fafcff), nil),
            paint.circle(12, 7, 5, paint.fill(rgba_panel(mode)), nil),
        }
    end
    return b.paint {
        tw.w_px(18), tw.h_px(18),
        paint.circle(9, 9, 4, paint.fill(0xf59e0bff), nil),
        paint.line(9, 0, 9, 3, paint.stroke(0xf59e0bff, 1)),
        paint.line(9, 15, 9, 18, paint.stroke(0xf59e0bff, 1)),
        paint.line(0, 9, 3, 9, paint.stroke(0xf59e0bff, 1)),
        paint.line(15, 9, 18, 9, paint.stroke(0xf59e0bff, 1)),
        paint.line(3, 3, 5, 5, paint.stroke(0xf59e0bff, 1)),
        paint.line(13, 13, 15, 15, paint.stroke(0xf59e0bff, 1)),
        paint.line(13, 5, 15, 3, paint.stroke(0xf59e0bff, 1)),
        paint.line(3, 15, 5, 13, paint.stroke(0xf59e0bff, 1)),
    }
end

local function transport_icon(mode, playing)
    return b.paint {
        tw.w_px(18), tw.h_px(18),
        playing and paint.circle(9, 9, 4, paint.fill(rgba_green(mode)), nil)
            or paint.polygon({ 5, 4, 14, 9, 5, 14 }, paint.fill(rgba_text(mode)), nil),
    }
end

local function mini_tone_spark(mode, tone)
    local c = rgba_for_tone(mode, tone)
    return b.paint {
        tw.w_px(24), tw.h_px(16),
        paint.line(0, 12, 24, 12, paint.stroke(rgba_line(mode), 1)),
        paint.polyline({ 0, 11, 5, 9, 9, 12, 13, 5, 17, 7, 24, 3 }, paint.stroke(c, 2)),
    }
end

local function browser_icon(mode, index)
    local c = index % 3 == 0 and rgba_green(mode) or index % 2 == 0 and rgba_amber(mode) or rgba_accent(mode)
    return b.paint {
        tw.w_px(28), tw.h_px(28),
        paint.polygon({ 5, 9, 10, 9, 12, 7, 23, 7, 23, 21, 5, 21 }, paint.fill(with_alpha(c, is_dark(mode) and 18 or 22)), paint.stroke(rgba_line(mode), 1)),
        paint.line(8, 13, 20, 13, paint.stroke(c, 2)),
        paint.line(8, 17, 18, 17, paint.stroke(rgba_muted(mode), 1)),
    }
end

local function track_icon(mode, index)
    local accent = index % 3 == 0 and rgba_green(mode) or index % 2 == 0 and rgba_amber(mode) or rgba_accent(mode)
    return b.paint {
        tw.w_px(26), tw.h_px(26),
        paint.line(5, 20, 5, 8, paint.stroke(rgba_line(mode), 2)),
        paint.line(13, 20, 13, 6, paint.stroke(accent, 2)),
        paint.line(21, 20, 21, 11, paint.stroke(rgba_line(mode), 2)),
        paint.line(4, 20, 22, 20, paint.stroke(rgba_muted(mode), 1)),
        paint.circle(13, 8, 2.5, paint.fill(accent), nil),
    }
end

local function scene_icon(mode, index)
    local accent = index % 2 == 0 and rgba_amber(mode) or rgba_accent(mode)
    return b.paint {
        tw.w_px(26), tw.h_px(26),
        paint.polygon({ 6, 6, 20, 6, 20, 20, 6, 20 }, paint.fill(with_alpha(accent, is_dark(mode) and 12 or 16)), paint.stroke(rgba_line(mode), 1)),
        paint.line(9, 13, 17, 13, paint.stroke(accent, 2)),
        paint.circle(13, 13, 2.5, paint.fill(accent), nil),
    }
end

local function clip_preview(mode, self)
    local c = self.armed and rgba_green(mode) or rgba_accent(mode)
    local ghost = with_alpha(c, is_dark(mode) and 70 or 76)
    local w = 84
    local h = 34
    local px = function(t) return math.floor(t * w + 0.5) end
    local py = function(v) return math.floor((1 - v) * (h - 10) + 5 + 0.5) end
    local p0x, p0y = 0, py(self.level_a)
    local p1x, p1y = px(0.22), py(self.level_b)
    local p2x, p2y = px(0.45), py(self.level_c)
    local p3x, p3y = px(0.68), py((self.level_a + self.level_c) * 0.5)
    local p4x, p4y = w, py(self.level_b * 0.92)
    return b.paint {
        tw.w_px(w), tw.h_px(h),
        paint.line(0, h - 5, w, h - 5, paint.stroke(rgba_line(mode), 1)),
        paint.line(0, math.floor(h * 0.5), w, math.floor(h * 0.5), paint.stroke(is_dark(mode) and 0x1e293bff or 0xe2e8f0ff, 1)),
        paint.polyline({ p0x, p0y + 5, p1x, p1y + 5, p2x, p2y + 5, p3x, p3y + 5, p4x, p4y + 5 }, paint.stroke(ghost, 1)),
        paint.polyline({ p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y }, paint.stroke(c, 2)),
        paint.line(math.floor(self.playhead * w + 0.5), 3, math.floor(self.playhead * w + 0.5), h - 3, paint.stroke(rgba_text(mode), 1)),
        paint.circle(p2x, p2y, 2.5, paint.fill(c), nil),
    }
end

local function device_macro_strip(mode, va, vb, vc)
    local bar = function(x, v, rgba)
        return {
            paint.line(x, 4, x, 30, paint.stroke(rgba_line(mode), 3)),
            paint.line(x, 30 - math.floor(v * 20 + 0.5), x, 30, paint.stroke(rgba, 3)),
            paint.circle(x, 30 - math.floor(v * 20 + 0.5), 3, paint.fill(rgba), nil),
        }
    end
    local ops = {}
    local function append(t)
        for i = 1, #t do ops[#ops + 1] = t[i] end
    end
    append(bar(8, va, rgba_muted(mode)))
    append(bar(18, vb, rgba_accent(mode)))
    append(bar(28, vc, rgba_amber(mode)))
    return b.paint { tw.w_px(36), tw.h_px(34), paint.list(ops) }
end

local function waveform_widget(mode, title, samples, playhead, tone, w, h)
    local c = rgba_for_tone(mode, tone)
    local ghost = with_alpha(c, is_dark(mode) and 72 or 84)
    local points = {}
    local ghost_points = {}
    local n = #samples
    if n > 0 then
        for i = 1, n do
            local t = (i - 1) / math.max(1, n - 1)
            local x = math.floor(t * w + 0.5)
            local y = math.floor((1 - samples[i]) * (h - 22) + 10 + 0.5)
            points[#points + 1] = x
            points[#points + 1] = y
            ghost_points[#ghost_points + 1] = x
            ghost_points[#ghost_points + 1] = math.min(h - 6, y + 8)
        end
    end
    return b.box {
        tw.flow,
        tw.gap_y_2,
        eyebrow(mode, title),
        b.paint {
            tw.w_px(w), tw.h_px(h),
            tw.rounded_lg,
            tw.border_1, border_soft(mode), bg_panel_alt(mode),
            paint.line(0, math.floor(h * 0.5), w, math.floor(h * 0.5), paint.stroke(rgba_line(mode), 1)),
            paint.polyline(ghost_points, paint.stroke(ghost, 1)),
            paint.polyline(points, paint.stroke(c, 2)),
            paint.line(math.floor(playhead * w + 0.5), 4, math.floor(playhead * w + 0.5), h - 4, paint.stroke(rgba_text(mode), 1)),
        },
    }
end

local function device_icon(mode, kind)
    if kind == Studio.Instrument then
        return b.paint {
            tw.w_px(36), tw.h_px(36),
            paint.circle(18, 18, 11, paint.fill(with_alpha(rgba_accent(mode), is_dark(mode) and 16 or 20)), paint.stroke(rgba_accent(mode), 1)),
            paint.polyline({ 9, 21, 13, 16, 18, 20, 23, 12, 28, 16 }, paint.stroke(rgba_accent(mode), 2)),
        }
    elseif kind == Studio.Mixer then
        return b.paint {
            tw.w_px(36), tw.h_px(36),
            paint.line(10, 8, 10, 28, paint.stroke(rgba_amber(mode), 2)),
            paint.line(18, 8, 18, 28, paint.stroke(rgba_muted(mode), 2)),
            paint.line(26, 8, 26, 28, paint.stroke(rgba_accent(mode), 2)),
            paint.circle(10, 14, 4, paint.fill(rgba_amber(mode)), nil),
            paint.circle(18, 22, 4, paint.fill(rgba_muted(mode)), nil),
            paint.circle(26, 12, 4, paint.fill(rgba_accent(mode)), nil),
        }
    elseif kind == Studio.Mod then
        return b.paint {
            tw.w_px(36), tw.h_px(36),
            paint.polyline({ 4, 25, 10, 20, 16, 22, 22, 10, 28, 14, 32, 8 }, paint.stroke(rgba_green(mode), 2)),
            paint.line(4, 28, 32, 28, paint.stroke(rgba_line(mode), 1)),
        }
    end
    return b.paint {
        tw.w_px(36), tw.h_px(36),
        paint.arc(18, 18, 10, 3.4, 6.0, 20, paint.stroke(rgba_accent(mode), 3)),
        paint.arc(18, 18, 6, 3.1, 5.5, 20, paint.stroke(rgba_muted(mode), 2)),
    }
end

local function inspector_preview(mode, kind)
    if kind == "device" then
        return b.paint {
            tw.w_px(300), tw.h_px(120), tw.rounded_lg, bg_panel_alt(mode),
            paint.polygon({ 18, 90, 66, 40, 118, 76, 170, 28, 236, 88, 282, 52, 282, 104, 18, 104 }, paint.fill(with_alpha(rgba_accent(mode), is_dark(mode) and 24 or 20)), paint.stroke(rgba_accent(mode), 2)),
            paint.circle(86, 46, 7, paint.fill(rgba_muted(mode)), nil),
            paint.circle(190, 38, 7, paint.fill(rgba_amber(mode)), nil),
        }
    elseif kind == "clip" then
        return b.paint {
            tw.w_px(300), tw.h_px(120), tw.rounded_lg, bg_panel_alt(mode),
            paint.line(16, 60, 284, 60, paint.stroke(rgba_line(mode), 1)),
            paint.polyline({ 16, 76, 44, 40, 82, 88, 118, 32, 158, 78, 194, 42, 232, 86, 284, 52 }, paint.stroke(with_alpha(rgba_green(mode), is_dark(mode) and 72 or 80), 1)),
            paint.polyline({ 16, 68, 44, 32, 82, 80, 118, 24, 158, 70, 194, 34, 232, 78, 284, 44 }, paint.stroke(rgba_green(mode), 3)),
            paint.line(164, 18, 164, 102, paint.stroke(rgba_text(mode), 1)),
        }
    end
    return b.paint {
        tw.w_px(300), tw.h_px(120), tw.rounded_lg, bg_panel_alt(mode),
        paint.circle(64, 60, 18, paint.fill(with_alpha(rgba_accent(mode), is_dark(mode) and 26 or 22)), paint.stroke(rgba_accent(mode), 1)),
        paint.arc(154, 60, 28, 3.14, 5.9, 24, paint.stroke(rgba_line(mode), 6)),
        paint.arc(154, 60, 28, 3.14, 4.86, 24, paint.stroke(rgba_accent(mode), 6)),
        paint.polyline({ 210, 84, 226, 56, 246, 66, 266, 34, 284, 48 }, paint.stroke(rgba_green(mode), 3)),
    }
end

local function status_dot(mode, rgba)
    return b.paint {
        tw.w_px(10), tw.h_px(10),
        paint.circle(5, 5, 4, paint.fill(rgba), paint.stroke(is_dark(mode) and 0x0f172aff or 0xffffffff, 1)),
    }
end

local function interactive_card(mode, id, body, selected, hovered, focused, accent_border_token, idle_bg_token, extra_styles)
    local border = selected and accent_border_token or focused and accent_border(mode) or hovered and border_hover(mode) or border_soft(mode)
    local bg = selected and bg_selected(mode) or (hovered or focused) and bg_hover(mode) or idle_bg_token or bg_panel_alt(mode)
    return b.with_input(b.id(id), T.Interact.ActivateTarget,
        b.box {
            b.id(id .. ":frame"),
            tw.flow,
            tw.gap_y_2,
            tw.p_4,
            tw.rounded_xl,
            tw.cursor_pointer,
            tw.border_1,
            border,
            bg,
            extra_styles and tw.group(extra_styles) or nil,
            b.fragment(body),
        })
end

local function make_wave(seed, count)
    local out = {}
    for i = 1, count do
        local t = (i - 1) / math.max(1, count - 1)
        local v = 0.5
            + math.sin((t * 6.28318 * (1.5 + seed * 0.07))) * 0.24
            + math.cos((t * 6.28318 * (3.2 + seed * 0.11))) * 0.10
            + math.sin((t * 6.28318 * (7.3 + seed * 0.05))) * 0.05
        if v < 0.06 then v = 0.06 end
        if v > 0.94 then v = 0.94 end
        out[i] = v
    end
    return out
end

M.semantic_phase = pvm.phase("studio_demo.semantic", function(state)
    local app = state.app
    local ui_model = state.ui_model
    local hover_value = id_value(ui_model.hover_id) or "none"
    local focus_value = id_value(ui_model.focus_id) or "none"
    local selected_id = demo_apply.selection_id(app.selection)

    local stats = {
        View.TopStat("tempo", tostring(app.bpm), "bpm", View.ToneAmber),
        View.TopStat("cpu", app.theme_mode == Studio.ThemeDark and "24" or "18", "%", View.ToneGreen),
        View.TopStat("buffer", "64", "smp", View.ToneBlue),
    }

    local browser_meta = {
        View.BrowserMeta("patches", tostring(#app.browser_items)),
        View.BrowserMeta("favorites", "12"),
    }

    local browser_rows = {}
    for i = 1, #app.browser_items do
        local id = "browser:" .. i
        browser_rows[i] = View.BrowserRow(
            i,
            app.browser_items[i],
            id_matches(selected_id, id),
            id_matches(ui_model.hover_id, id),
            id_matches(ui_model.focus_id, id)
        )
    end

    local track_headers = {}
    for i = 1, #app.tracks do
        local id = "track:" .. i
        track_headers[i] = View.TrackHeader(
            i,
            app.tracks[i],
            id_matches(selected_id, id),
            id_matches(ui_model.hover_id, id),
            id_matches(ui_model.focus_id, id)
        )
    end

    local scene_buttons = {}
    for i = 1, #app.scenes do
        local id = "scene:" .. i
        scene_buttons[i] = View.SceneButton(
            i,
            app.scenes[i],
            id_matches(selected_id, id),
            id_matches(ui_model.hover_id, id),
            id_matches(ui_model.focus_id, id)
        )
    end

    local clips = {}
    local clip_i = 0
    for scene_i = 1, #app.scenes do
        for track_i = 1, #app.tracks do
            clip_i = clip_i + 1
            local id = string.format("clip:%d:%d", track_i, scene_i)
            clips[clip_i] = View.ClipCell(
                track_i,
                scene_i,
                app.tracks[track_i],
                app.scenes[scene_i],
                (((track_i * 13 + scene_i * 7) % 70) / 100) + 0.18,
                (((track_i * 7 + scene_i * 17) % 65) / 100) + 0.20,
                (((track_i * 19 + scene_i * 5) % 72) / 100) + 0.16,
                (((track_i * 5 + scene_i * 3) % 80) / 100) + 0.10,
                (track_i + scene_i) % 3 == 0,
                id_matches(selected_id, id),
                id_matches(ui_model.hover_id, id),
                id_matches(ui_model.focus_id, id)
            )
        end
    end

    local function device_card(index)
        local id = "device:" .. index
        return View.DeviceCard(
            index,
            app.devices[index],
            (((index * 13) % 70) / 100) + 0.18,
            (((index * 29) % 65) / 100) + 0.22,
            (((index * 41) % 60) / 100) + 0.20,
            id_matches(selected_id, id),
            id_matches(ui_model.hover_id, id),
            id_matches(ui_model.focus_id, id)
        )
    end

    local inspector_devices = { device_card(1), device_card(2), device_card(3) }
    local dock_devices = {}
    for i = 1, #app.devices do dock_devices[i] = device_card(i) end

    local logs = {}
    for i = 1, #app.logs do logs[i] = View.ActivityItem(app.logs[i]) end

    local title, summary, kind = selection_summary(app)
    local inspector_stats = {
        View.InspectorStat("kind", kind, View.ToneBlue),
        View.InspectorStat("focus", focus_value, View.ToneAmber),
        View.InspectorStat("hover", hover_value, View.ToneRose),
    }
    local inspector_wave = View.Waveform("selection signal", make_wave(#app.logs + #app.tracks * 3, 48), 0.58, kind == "clip" and View.ToneGreen or kind == "device" and View.ToneAmber or View.ToneBlue)
    local dock_wave = View.Waveform("master output", make_wave(app.bpm, 64), 0.72, View.ToneBlue)

    return View.Workspace(
        View.Topbar(View.Branding("gps.lua", "compiler ui"), app.project_name, app.playing, stats),
        View.BrowserPanel(browser_meta, browser_rows),
        View.LauncherPanel(track_headers, scene_buttons, clips),
        View.InspectorPanel(title, summary, inspector_stats, inspector_wave, inspector_devices, "Custom paint is now a first-class part of the generic ui library, so icons, previews, waveforms, and bespoke chrome still live inside the typed compiler pipeline."),
        View.Dock(dock_devices, dock_wave, logs)
    )
end)

M.auth_phase = pvm.phase("studio_demo.auth", {
    [View.Workspace] = function(self, vw, vh, mode)
        local center_w = vw - CENTER_W_PAD
        return pvm.once(b.box {
            b.id("root"),
            tw.flex, tw.col,
            tw.w_px(vw), tw.h_px(vh),
            bg_root(mode),

            pvm.one(M.auth_phase(self.topbar, vw, vh, mode)),

            b.box {
                b.id("workspace"),
                tw.flex, tw.row,
                tw.grow_1, tw.basis_px(0),
                tw.min_h_px(0),
                tw.w_px(vw),
                pvm.one(M.auth_phase(self.browser, vw, vh, mode)),
                b.box {
                    b.id("center-column"),
                    tw.flex, tw.col,
                    tw.grow_1, tw.basis_px(0),
                    tw.min_h_px(0),
                    tw.w_px(center_w),
                    tw.gap_y_4,
                    pvm.one(M.auth_phase(self.launcher, vw, vh, mode)),
                    pvm.one(M.auth_phase(self.dock, vw, vh, mode)),
                },
                pvm.one(M.auth_phase(self.inspector, vw, vh, mode)),
            },
        })
    end,

    [View.Branding] = function(self, _, _, mode)
        return pvm.once(b.box {
            tw.flex, tw.row,
            tw.items_center,
            tw.gap_3,
            brand_mark(mode),
            b.box {
                tw.flow,
                tw.gap_y_1,
                b.text { tw.text_base, tw.font_semibold, fg_main(mode), self.title },
                b.text { tw.text_sm, fg_dim(mode), self.subtitle },
            },
        })
    end,

    [View.Topbar] = function(self, vw, _, mode)
        local right_w = 492
        local center_w = 188
        local left_w = vw - right_w - center_w - 56
        local stats = {}
        for i = 1, #self.stats do stats[i] = pvm.one(M.auth_phase(self.stats[i], vw, 0, mode)) end
        return pvm.once(b.box {
            b.id("topbar"),
            tw.flex, tw.row,
            tw.w_px(vw), tw.h_px(TOPBAR_H),
            tw.px_6, tw.py_4,
            bg_panel(mode),
            tw.border_1, border_soft(mode),
            tw.items_center,
            tw.justify_between,

            b.box {
                tw.flex, tw.row,
                tw.items_center,
                tw.gap_4,
                tw.w_px(left_w),
                pvm.one(M.auth_phase(self.branding, vw, 0, mode)),
                b.box {
                    tw.flow,
                    tw.gap_y_1,
                    eyebrow(mode, "workspace"),
                    b.text { tw.text_xl, tw.font_semibold, fg_main(mode), self.project_name },
                    b.text { tw.text_sm, fg_soft(mode), is_dark(mode) and "live compiler workstation" or "live compiler workstation · light" },
                },
            },

            b.box {
                tw.flex, tw.row,
                tw.items_center,
                tw.justify_center,
                tw.w_px(center_w),
                b.with_input(b.id("transport:play"), T.Interact.ActivateTarget,
                    b.box {
                        b.id("transport:play:frame"),
                        tw.flex, tw.row,
                        tw.items_center,
                        tw.justify_center,
                        tw.w_px(152), tw.h_px(48),
                        tw.gap_3,
                        tw.rounded_xl,
                        tw.cursor_pointer,
                        tw.border_1,
                        self.playing and (is_dark(mode) and tw.border_color.green[500] or tw.border_color.green[400]) or border_soft(mode),
                        bg_panel_alt(mode),
                        transport_icon(mode, self.playing),
                        b.box {
                            tw.flow,
                            tw.gap_y_1,
                            eyebrow(mode, "transport"),
                            b.text { tw.text_base, tw.font_semibold, self.playing and tone_fg(mode, View.ToneGreen) or fg_main(mode), self.playing and "Playing" or "Stopped" },
                        },
                    }),
            },

            b.box {
                tw.flex, tw.row,
                tw.items_center,
                tw.justify_end,
                tw.w_px(right_w),
                tw.gap_3,
                b.with_input(b.id("theme:toggle"), T.Interact.ActivateTarget,
                    b.box {
                        b.id("theme:toggle:frame"),
                        tw.flex, tw.row,
                        tw.items_center,
                        tw.justify_center,
                        tw.gap_3,
                        tw.w_px(118), tw.h_px(48),
                        tw.rounded_xl,
                        tw.cursor_pointer,
                        tw.border_1,
                        border_soft(mode),
                        bg_panel_alt(mode),
                        theme_icon(mode),
                        b.text { tw.text_base, tw.font_semibold, fg_main(mode), is_dark(mode) and "Dark" or "Light" },
                    }),
                b.fragment(stats),
            },
        })
    end,

    [View.TopStat] = function(self, _, _, mode)
        return pvm.once(b.box {
            tw.flow,
            tw.w_px(116),
            tw.gap_y_2,
            tw.p_3,
            tw.rounded_xl,
            tw.border_1,
            border_soft(mode),
            bg_panel_alt(mode),
            b.box { tw.flex, tw.row, tw.justify_between, tw.items_center,
                b.text { tw.text_sm, tw.font_medium, tone_fg(mode, self.tone), string.upper(self.label) },
                mini_tone_spark(mode, self.tone),
            },
            b.box {
                tw.flex, tw.row,
                tw.items_end,
                tw.gap_1,
                b.text { tw.text_lg, tw.font_semibold, fg_main(mode), self.value },
                self.suffix ~= "" and b.text { tw.text_sm, fg_dim(mode), self.suffix } or nil,
            },
        })
    end,

    [View.BrowserMeta] = function(self, _, _, mode)
        return pvm.once(b.box {
            tw.flex, tw.row,
            tw.items_center,
            tw.w_hug,
            tw.gap_2,
            tw.px_3, tw.py_2,
            tw.rounded_md,
            tw.border_1, border_soft(mode), bg_panel_alt(mode),
            b.text { tw.text_sm, tw.font_medium, fg_dim(mode), string.upper(self.label) },
            b.text { tw.text_sm, tw.font_semibold, fg_main(mode), self.value },
        })
    end,

    [View.BrowserPanel] = function(self, _, vh, mode)
        local meta = {}
        for i = 1, #self.meta do meta[i] = pvm.one(M.auth_phase(self.meta[i], 0, vh, mode)) end
        local rows = {}
        for i = 1, #self.rows do rows[i] = pvm.one(M.auth_phase(self.rows[i], 0, vh, mode)) end
        return pvm.once(b.box {
            b.id("browser-panel"),
            tw.flex, tw.col,
            tw.w_px(SIDE_PANEL_W),
            tw.h_full,
            tw.p_5,
            tw.gap_y_4,
            bg_panel(mode),
            tw.border_1, border_soft(mode),

            b.box {
                tw.flow,
                tw.gap_y_1,
                eyebrow(mode, "browser"),
                b.text { tw.text_xl, tw.font_semibold, fg_main(mode), "Material Library" },
                b.text { tw.text_sm, fg_soft(mode), "Curated instruments, textures, and macro devices." },
                b.box { tw.flex, tw.row, tw.gap_4, b.fragment(meta) },
            },
            b.box {
                BROWSER_SCROLL_ID,
                tw.flow,
                tw.grow_1, tw.basis_px(0),
                tw.min_h_px(0),
                tw.gap_y_2,
                tw.pr_2,
                tw.overflow_y_scroll,
                b.fragment(rows),
            },
        })
    end,

    [View.BrowserRow] = function(self, _, _, mode)
        local id = "browser:" .. self.index
        local item = self.item
        return pvm.once(interactive_card(mode, id, {
            b.box {
                tw.flex, tw.row,
                tw.items_start,
                tw.gap_3,
                browser_icon(mode, self.index),
                b.box {
                    tw.flow,
                    tw.gap_y_1,
                    b.text { tw.text_base, tw.font_medium, fg_main(mode), item.title },
                    b.text { tw.text_sm, tw.font_medium, tone_fg(mode, self.index % 3 == 0 and View.ToneGreen or self.index % 2 == 0 and View.ToneAmber or View.ToneBlue), string.upper(item.tag) },
                    b.text { tw.text_sm, self.selected and accent_text(mode) or fg_soft(mode), item.note },
                },
            },
        }, self.selected, self.hovered, self.focused, accent_border(mode), bg_panel_alt(mode)))
    end,

    [View.LauncherPanel] = function(self, vw, vh, mode)
        local cols = { tw.track.px(SCENE_COL_W) }
        for i = 1, #self.tracks do cols[#cols + 1] = tw.track.fr(1) end
        local rows = { tw.track.px(TRACK_HEADER_H) }
        for i = 1, #self.scenes do rows[#rows + 1] = tw.track.px(MATRIX_ROW_H) end

        local grid_children = {}
        for i = 1, #self.tracks do
            local header = self.tracks[i]
            grid_children[#grid_children + 1] = b.box {
                tw.col_start(header.index + 1), tw.row_start(1),
                pvm.one(M.auth_phase(header, vw, vh, mode)),
            }
        end
        for i = 1, #self.scenes do
            local scene = self.scenes[i]
            grid_children[#grid_children + 1] = b.box {
                tw.col_start(1), tw.row_start(scene.index + 1),
                pvm.one(M.auth_phase(scene, vw, vh, mode)),
            }
        end
        for i = 1, #self.clips do
            local clip = self.clips[i]
            grid_children[#grid_children + 1] = b.box {
                tw.col_start(clip.track_index + 1), tw.row_start(clip.scene_index + 1),
                pvm.one(M.auth_phase(clip, vw, vh, mode)),
            }
        end

        local center_w = vw - CENTER_W_PAD
        return pvm.once(b.box {
            b.id("launcher-panel"),
            tw.flex, tw.col,
            tw.w_px(center_w),
            tw.grow_1, tw.basis_px(0),
            tw.min_h_px(0),
            tw.p_5,
            tw.gap_y_4,
            bg_root(mode),
            tw.border_1, border_soft(mode),

            b.box {
                tw.flex, tw.row, tw.justify_between, tw.items_end,
                b.box {
                    tw.flow,
                    tw.gap_y_1,
                    eyebrow(mode, "launcher"),
                    b.text { tw.text_xl, tw.font_semibold, fg_main(mode), "Live Matrix" },
                    b.text { tw.text_sm, fg_soft(mode), "Scene launch surface with typed semantic cells and paint previews." },
                },
                b.text { tw.text_sm, fg_dim(mode), tostring(#self.tracks) .. " tracks · " .. tostring(#self.scenes) .. " scenes · " .. tostring(#self.clips) .. " clips" },
            },

            b.box {
                LAUNCHER_SCROLL_ID,
                tw.flow,
                tw.grow_1, tw.basis_px(0),
                tw.min_h_px(0),
                tw.overflow_y_scroll,
                b.box {
                    b.id("launcher-grid"),
                    tw.grid,
                    tw.cols(cols),
                    tw.rows(rows),
                    tw.col_gap_3,
                    tw.row_gap_3,
                    b.fragment(grid_children),
                },
            },
        })
    end,

    [View.TrackHeader] = function(self, _, _, mode)
        local id = "track:" .. self.index
        local track = self.track
        return pvm.once(interactive_card(mode, id, {
            b.box {
                tw.flex, tw.row,
                tw.items_center,
                tw.gap_3,
                track_icon(mode, self.index),
                b.box {
                    tw.flow,
                    tw.gap_y_1,
                    b.text { tw.text_sm, tw.font_medium, fg_dim(mode), string.upper(track.group) },
                    b.text { tw.text_base, tw.font_semibold, fg_main(mode), track.name },
                    b.text { tw.text_sm, fg_soft(mode), track.route },
                },
            },
        }, self.selected, self.hovered, self.focused, accent_border(mode), bg_panel_alt(mode), { tw.h_px(TRACK_HEADER_H) }))
    end,

    [View.SceneButton] = function(self, _, _, mode)
        local id = "scene:" .. self.index
        local scene = self.scene
        return pvm.once(interactive_card(mode, id, {
            b.box {
                tw.flex, tw.row,
                tw.items_center,
                tw.gap_3,
                scene_icon(mode, self.index),
                b.box {
                    tw.flow,
                    tw.gap_y_1,
                    eyebrow(mode, "scene"),
                    b.text { tw.text_base, tw.font_semibold, fg_main(mode), scene.name },
                    b.text { tw.text_sm, fg_soft(mode), scene.length },
                },
            },
        }, self.selected, self.hovered, self.focused, accent_border(mode), bg_panel_alt(mode), { tw.h_px(MATRIX_ROW_H) }))
    end,

    [View.ClipCell] = function(self, _, _, mode)
        local id = string.format("clip:%d:%d", self.track_index, self.scene_index)
        local idle_bg = self.armed and (is_dark(mode) and tw.bg.emerald[950] or tw.bg.emerald[50]) or bg_panel_alt(mode)
        return pvm.once(interactive_card(mode, id, {
            b.box {
                tw.flex, tw.col,
                tw.justify_between,
                tw.h_full,
                b.box {
                    tw.flow,
                    tw.gap_y_2,
                    b.box {
                        tw.flex, tw.row,
                        tw.justify_between,
                        tw.items_start,
                        b.box {
                            tw.flow,
                            tw.gap_y_1,
                            b.text { tw.text_sm, tw.font_medium, self.armed and tone_fg(mode, View.ToneGreen) or fg_dim(mode), string.upper(self.armed and "armed" or "idle") },
                            b.text { tw.text_base, tw.font_semibold, fg_main(mode), self.track.short .. " · " .. self.scene.short },
                            b.text { tw.text_sm, fg_soft(mode), ((self.track_index * self.scene_index) % 2 == 0 and "Warped texture" or "Punchy groove") },
                        },
                        b.box { tw.flex, tw.row, tw.items_center, tw.gap_2,
                            status_dot(mode, self.armed and rgba_green(mode) or rgba_muted(mode)),
                            b.text { tw.text_sm, tw.font_medium, fg_dim(mode), string.format("%db", 4 + ((self.track_index + self.scene_index) % 4) * 4) },
                        },
                    },
                },
                clip_preview(mode, self),
            },
        }, self.selected, self.hovered, self.focused, self.armed and (is_dark(mode) and tw.border_color.emerald[500] or tw.border_color.emerald[400]) or accent_border(mode), idle_bg, { tw.h_px(MATRIX_ROW_H) }))
    end,

    [View.Waveform] = function(self, _, _, mode)
        return pvm.once(waveform_widget(mode, self.title, self.samples, self.playhead, self.tone, 300, 116))
    end,

    [View.InspectorPanel] = function(self, _, vh, mode)
        local stats = {}
        for i = 1, #self.stats do stats[i] = pvm.one(M.auth_phase(self.stats[i], 0, vh, mode)) end
        local devices = {}
        for i = 1, #self.devices do devices[i] = pvm.one(M.auth_phase(self.devices[i], 0, vh, mode)) end
        local waveform = pvm.one(M.auth_phase(self.waveform, 0, vh, mode))
        return pvm.once(b.box {
            b.id("inspector-panel"),
            tw.flex, tw.col,
            tw.w_px(INSPECTOR_W),
            tw.h_full,
            tw.p_5,
            tw.gap_y_4,
            bg_panel(mode),
            tw.border_1, border_soft(mode),

            b.box {
                tw.flow,
                tw.gap_y_1,
                eyebrow(mode, "inspector"),
                b.text { tw.text_xl, tw.font_semibold, fg_main(mode), self.title },
                b.text { tw.text_base, fg_soft(mode), self.summary },
            },

            inspector_preview(mode, self.stats[1].value),
            waveform,
            b.box { tw.flow, tw.gap_y_2, b.fragment(stats) },

            b.box {
                DETAIL_SCROLL_ID,
                tw.flow,
                tw.grow_1, tw.basis_px(0),
                tw.min_h_px(0),
                tw.gap_y_3,
                tw.pr_2,
                tw.overflow_y_scroll,
                b.fragment(devices),
                b.box {
                    tw.flow,
                    tw.gap_y_2,
                    tw.p_4,
                    tw.rounded_lg,
                    tw.border_1, border_soft(mode), bg_panel_alt(mode),
                    eyebrow(mode, "notes"),
                    b.text { tw.text_base, fg_soft(mode), self.notes },
                },
            },
        })
    end,

    [View.InspectorStat] = function(self, _, _, mode)
        return pvm.once(b.box {
            tw.flex, tw.row,
            tw.justify_between,
            tw.items_center,
            tw.px_3, tw.py_2,
            tw.rounded_md,
            bg_panel_alt(mode),
            tw.border_1, border_soft(mode),
            b.box { tw.flex, tw.row, tw.items_center, tw.gap_2,
                status_dot(mode, rgba_for_tone(mode, self.tone)),
                b.text { tw.text_sm, tw.font_medium, tone_fg(mode, self.tone), string.upper(self.label) },
            },
            b.text { tw.text_sm, tw.font_semibold, fg_main(mode), self.value },
        })
    end,

    [View.DeviceCard] = function(self, _, _, mode)
        local id = "device:" .. self.index
        local device = self.device
        local accent = device.kind == Studio.Mixer and (is_dark(mode) and tw.border_color.amber[500] or tw.border_color.amber[400])
            or device.kind == Studio.Mod and (is_dark(mode) and tw.border_color.green[500] or tw.border_color.green[400])
            or device.kind == Studio.Fx and (is_dark(mode) and tw.border_color.sky[500] or tw.border_color.sky[400])
            or (is_dark(mode) and tw.border_color.slate[500] or tw.border_color.slate[400])
        return pvm.once(interactive_card(mode, id, {
            b.box {
                tw.flex, tw.row,
                tw.items_start,
                tw.gap_3,
                device_icon(mode, device.kind),
                b.box {
                    tw.flow,
                    tw.gap_y_2,
                    b.box {
                        tw.flow,
                        tw.gap_y_1,
                        b.text { tw.text_sm, tw.font_medium, tone_fg(mode, device.kind == Studio.Mixer and View.ToneAmber or device.kind == Studio.Mod and View.ToneGreen or device.kind == Studio.Fx and View.ToneBlue or View.ToneNeutral), string.upper(device_kind_label(device.kind)) },
                        b.text { tw.text_base, tw.font_semibold, fg_main(mode), device.name },
                        b.text { tw.text_sm, fg_soft(mode), device.summary },
                    },
                    b.box { tw.flex, tw.row, tw.items_end, tw.justify_between,
                        device_macro_strip(mode, self.macro_a, self.macro_b, self.macro_c),
                        b.box {
                            tw.flow,
                            tw.gap_y_1,
                            eyebrow(mode, "macro"),
                            b.text { tw.text_sm, fg_main(mode), string.format("A %.0f  B %.0f  C %.0f", self.macro_a * 100, self.macro_b * 100, self.macro_c * 100) },
                        },
                    },
                },
            },
        }, self.selected, self.hovered, self.focused, accent, bg_panel_alt(mode)))
    end,

    [View.Dock] = function(self, vw, _, mode)
        local device_children = {}
        for i = 1, #self.devices do
            device_children[i] = b.box {
                tw.w_px(232),
                pvm.one(M.auth_phase(self.devices[i], vw, 0, mode)),
            }
        end
        local logs = {}
        for i = 1, #self.logs do logs[i] = pvm.one(M.auth_phase(self.logs[i], vw, 0, mode)) end
        local waveform = pvm.one(M.auth_phase(self.waveform, vw, 0, mode))
        local dock_w = vw - CENTER_W_PAD
        return pvm.once(b.box {
            b.id("bottom-dock"),
            tw.flex, tw.row,
            tw.w_px(dock_w), tw.h_px(DOCK_H),
            tw.shrink_0,
            tw.gap_4,
            tw.p_5,
            bg_root(mode),
            tw.border_1, border_soft(mode),

            b.box {
                b.id("devices-panel"),
                tw.flow,
                tw.grow_1, tw.basis_px(0),
                tw.min_w_px(0),
                tw.h_full,
                tw.gap_y_3,
                eyebrow(mode, "devices"),
                b.box { tw.flex, tw.row, tw.wrap, tw.gap_3, b.fragment(device_children) },
            },

            b.box {
                b.id("monitor-panel"),
                tw.flow,
                tw.w_px(316), tw.h_full,
                tw.shrink_0,
                tw.gap_y_3,
                eyebrow(mode, "monitor"),
                waveform,
            },

            b.box {
                b.id("log-panel"),
                tw.flow,
                tw.w_px(300), tw.h_full,
                tw.shrink_0,
                tw.gap_y_3,
                eyebrow(mode, "activity"),
                b.box { tw.flow, tw.gap_y_2, b.fragment(logs) },
            },
        })
    end,

    [View.ActivityItem] = function(self, _, _, mode)
        return pvm.once(b.box {
            tw.flex, tw.row,
            tw.items_start,
            tw.gap_3,
            tw.p_3,
            tw.rounded_md,
            tw.border_1, border_soft(mode), bg_panel_alt(mode),
            status_dot(mode, rgba_green(mode)),
            b.text { tw.text_sm, fg_soft(mode), self.text },
        })
    end,
})

function M.auth_root(state, vw, vh)
    local semantic = pvm.one(M.semantic_phase(state))
    return pvm.one(M.auth_phase(semantic, vw, vh, state.app.theme_mode))
end

return M
