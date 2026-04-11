-- ui/demo/lower.lua
-- Lower the demo widget/view ASDL layer into generic SemUI/UI.

local ui = require("ui.init")
local demo_schema = require("ui.demo.asdl")

local T = ui.T
local V = demo_schema.T.DemoView
local lower = ui.lower
local ds = ui.ds

local M = {
    T = T,
    V = V,
    schema = demo_schema,
    lower = lower,
    ds = ds,
}

local L = T.Layout
local U = T.SemUI
local P = T.Paint
local R = T.Runtime

local math_max = math.max
local string_upper = string.upper
local type = type

local ACTIVE = ds.flag("active")

local TITLEBAR_H = 24
local TOOLBAR_H = 54
local STATUS_H = 24
local BROWSER_RAIL_W = 160
local LAUNCHER_W = 430
local INSPECTOR_W = 270
local DEVICE_H = 120
local REMOTE_W = 250
local HEADER_H = 24
local ARR_HEADER_W = 178
local LAUNCHER_ROW_H = 74
local TRACK_ROW_H = 72
local RULER_H = 22
local TIMELINE_BEATS = 8
local CLIP_CAP = 16
local DEVICE_CAP = 6

local FILL_BOX = L.Box(L.SizePercent(1), L.SizePercent(1), L.NoMin, L.NoMin, L.NoMax, L.NoMax)
local FILL_W_AUTO_H = L.Box(L.SizePercent(1), L.SizeAuto, L.NoMin, L.NoMin, L.NoMax, L.NoMax)
local AUTO_BOX = L.Box(L.SizeAuto, L.SizeAuto, L.NoMin, L.NoMin, L.NoMax, L.NoMax)

local function fill_w_h(h)
    return L.Box(L.SizePercent(1), L.SizePx(h), L.NoMin, L.NoMin, L.NoMax, L.NoMax)
end

local function box_w_fill_h(w)
    return L.Box(L.SizePx(w), L.SizePercent(1), L.NoMin, L.NoMin, L.NoMax, L.NoMax)
end

local function box_w_auto_h(w)
    return L.Box(L.SizePx(w), L.SizeAuto, L.NoMin, L.NoMin, L.NoMax, L.NoMax)
end

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

local function surface(surface_name, flags, box, child)
    return U.Sized(box, U.Surface(surface_name, flags or {}, child))
end

local function panel(surface_name, flags, id, scroll_y, box, child)
    return U.ScrollArea(id or "", L.ScrollY, 0, scroll_y or 0, box, U.Surface(surface_name, flags or {}, child))
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
    return paint_text_value(tag, x, y, w, h, font_id, color, align, line_height,
        L.TextNoWrap, L.OverflowClip, L.MaxLines(1), ref_name)
end

local function paint_text_lit(tag, x, y, w, h, font_id, color, align, line_height, value)
    return P.Text(
        tag or "",
        scalar(x), scalar(y), scalar(w), scalar(h),
        font_id or 2,
        color_value(color),
        line_height or L.LineHeightPx(18),
        align or L.TextStart,
        L.TextNoWrap,
        L.OverflowClip,
        L.MaxLines(1),
        P.TextLit(value or ""))
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

local function titlebar(view)
    return surface("transport", {}, fill_w_h(TITLEBAR_H), row(FILL_BOX, {
        item(text(AUTO_BOX, " " .. view.app_badge), 0, 0),
        item(text(AUTO_BOX, " " .. view.document_title), 0, 0),
        item(U.Spacer(FILL_BOX), 1, 1),
        item(text(AUTO_BOX, view.engine_text .. " "), 0, 0),
    }, { align = L.CrossStretch, gap = 8 }))
end

local function transport_button(btn)
    return item(pressable(btn.id,
        surface("button", btn.active and { ACTIVE } or {}, AUTO_BOX, text(AUTO_BOX, btn.label))), 0, 0)
end

local function toolbar(view)
    local children = {}
    for i = 1, #view.buttons do
        children[#children + 1] = transport_button(view.buttons[i])
        if view.buttons[i].id == "action:live" then
            children[#children + 1] = item(text(AUTO_BOX, " stage · " .. view.phase_verb), 0, 0)
        end
    end
    children[#children + 1] = item(U.Spacer(FILL_BOX), 1, 1)
    children[#children + 1] = item(text(AUTO_BOX, view.bpm_text), 0, 0)
    children[#children + 1] = item(text(AUTO_BOX, view.meter_text), 0, 0)
    children[#children + 1] = item(text(AUTO_BOX, view.clock_text), 0, 0)

    return surface("transport", {}, fill_w_h(TOOLBAR_H), row(FILL_BOX, children, {
        align = L.CrossStretch,
        gap = 8,
    }))
end

local function browser_rail(view)
    return surface("panel", {}, box_w_auto_h(BROWSER_RAIL_W), col(FILL_W_AUTO_H, {
        item(text(fill_w_h(HEADER_H), " " .. view.title), 0, 0),
        item(text(fill_w_h(18), " " .. view.subtitle), 0, 0),
        item(U.Spacer(FILL_BOX), 1, 1),
        item(text(fill_w_h(18), view.empty_message), 0, 0),
        item(U.Spacer(FILL_BOX), 1, 1),
    }, { gap = 8 }))
end

local function launcher_button_widget(btn)
    return item(pressable(btn.id,
        panel("button", btn.active and { ACTIVE } or {}, "", 0, AUTO_BOX, text(AUTO_BOX, btn.label))), 0, 0)
end

local function launcher_slot_widget(slot)
    return item(pressable(slot.id,
        panel("button", slot.active and { ACTIVE } or {}, "", 0, fill_w_h(18), text(fill_w_h(18), slot.label))), 0, 0)
end

local function launcher_track_row(row_view)
    local flags = row_view.active and { ACTIVE } or {}
    local button_row = {}
    for i = 1, #row_view.buttons do
        button_row[#button_row + 1] = launcher_button_widget(row_view.buttons[i])
    end
    local slot_col = {}
    for i = 1, #row_view.slots do
        slot_col[#slot_col + 1] = launcher_slot_widget(row_view.slots[i])
    end
    return item(row(fill_w_h(LAUNCHER_ROW_H), {
        item(pressable(row_view.id,
            panel("browser_item", flags, "", 0, box_w_fill_h(236), col(FILL_BOX, {
                item(text(fill_w_h(18), " " .. row_view.icon .. "  " .. row_view.title), 0, 0),
                item(text(fill_w_h(16), " " .. row_view.subtitle), 0, 0),
                item(row(fill_w_h(18), button_row, { gap = 4 }), 0, 0),
            }, { gap = 2 }))), 0, 0),
        item(col(box_w_fill_h(170), {
            item(text(fill_w_h(16), row_view.meter_text), 0, 0),
            item(col(FILL_W_AUTO_H, slot_col, { gap = 4 }), 0, 0),
        }, { gap = 6 }), 0, 0),
    }, { align = L.CrossStretch, gap = 12 }), 0, 0)
end

local function launcher_panel(view)
    local rows = {
        item(text(fill_w_h(HEADER_H), " " .. view.title), 0, 0),
        item(row(FILL_BOX, {
            item(text(fill_w_h(18), " tracks"), 1, 1),
            item(text(AUTO_BOX, view.scene_title_a), 0, 0),
            item(text(AUTO_BOX, view.scene_title_b), 0, 0),
        }), 0, 0),
    }
    for i = 1, #view.rows do
        rows[#rows + 1] = launcher_track_row(view.rows[i])
    end
    rows[#rows + 1] = item(U.Spacer(FILL_BOX), 1, 1)
    return surface("panel", {}, box_w_fill_h(LAUNCHER_W), col(FILL_BOX, rows, { gap = 6 }))
end

local function arrangement_paint(view)
    local kids = {}
    local lh = L.LineHeightPx(16)
    local small_lh = L.LineHeightPx(14)
    local track_count = #view.tracks

    kids[#kids + 1] = paint_fill("", 0, 0, "arr:w", "arr:h", 0x1d222dff)
    kids[#kids + 1] = paint_stroke("", 0, 0, "arr:w", "arr:h", 1, 0x394255ff)
    kids[#kids + 1] = paint_text_lit("", 12, 6, 240, 18, 2, 0xa4aec9ff, L.TextStart, lh, view.title)
    kids[#kids + 1] = paint_text_lit("", "arr:w_note_x", 6, "arr:note_w", 18, 1, 0x77819bff, L.TextEnd, small_lh, view.note)

    kids[#kids + 1] = paint_fill("", 0, "arr:body_y", "arr:header_w", "arr:body_h", 0x171a22ff)
    kids[#kids + 1] = paint_fill("", "arr:header_w", "arr:body_y", "arr:timeline_w", "arr:body_h", 0x1d222dff)
    kids[#kids + 1] = paint_line("", 0, "arr:ruler_y2", "arr:w", "arr:ruler_y2", 1, 0x394255ff)
    kids[#kids + 1] = paint_line("", "arr:header_w", "arr:body_y", "arr:header_w", "arr:h", 1, 0x394255ff)

    for beat = 0, view.beat_count do
        local base = "arr:beat:" .. beat
        kids[#kids + 1] = paint_line("", base .. ":x", "arr:body_y", base .. ":x", "arr:h", 1, base .. ":color")
        if beat < view.beat_count then
            kids[#kids + 1] = paint_text_ref("", base .. ":x_label", 30, 40, 14, 1, 0x77819bff, L.TextStart, small_lh, base .. ":text")
        end
    end

    for i = 1, track_count do
        local base = "arr:track:" .. i
        kids[#kids + 1] = paint_fill("", 0, base .. ":y", "arr:w", base .. ":h", base .. ":bg")
        kids[#kids + 1] = paint_line("", 0, base .. ":y2", "arr:w", base .. ":y2", 1, 0x2a303dff)
    end

    kids[#kids + 1] = paint_line("", "arr:playhead_x", "arr:body_y", "arr:playhead_x", "arr:h", 2, 0xffd36aff)

    for i = 1, #view.clips do
        local base = "arr:clip:" .. i
        kids[#kids + 1] = paint_fill("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", base .. ":fill")
        kids[#kids + 1] = paint_stroke("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", 1, base .. ":stroke")
        kids[#kids + 1] = paint_text_ref("", base .. ":tx", base .. ":ty", base .. ":tw", 14, 1, 0x11131aff, L.TextStart, small_lh, base .. ":text")
    end

    for i = 1, track_count do
        local base = "arr:routebox:" .. i
        kids[#kids + 1] = paint_fill("", base .. ":x1", base .. ":y", base .. ":w", base .. ":h", base .. ":fill1")
        kids[#kids + 1] = paint_stroke("", base .. ":x1", base .. ":y", base .. ":w", base .. ":h", 1, base .. ":stroke1")
        kids[#kids + 1] = paint_text_ref("", base .. ":x1t", base .. ":yt", base .. ":tw", 14, 1, 0x11131aff, L.TextStart, small_lh, base .. ":text1")
        kids[#kids + 1] = paint_fill("", base .. ":x2", base .. ":y", base .. ":w", base .. ":h", base .. ":fill2")
        kids[#kids + 1] = paint_stroke("", base .. ":x2", base .. ":y", base .. ":w", base .. ":h", 1, base .. ":stroke2")
        kids[#kids + 1] = paint_text_ref("", base .. ":x2t", base .. ":yt", base .. ":tw", 14, 1, 0x11131aff, L.TextStart, small_lh, base .. ":text2")
        kids[#kids + 1] = paint_line("", base .. ":lx1", base .. ":ly", base .. ":lx2", base .. ":ly", 2, base .. ":line")
    end

    for i = 1, track_count do
        for j = 1, 3 do
            local base = "arr:machine:" .. i .. ":" .. j
            kids[#kids + 1] = paint_fill("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", base .. ":fill")
            kids[#kids + 1] = paint_stroke("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", 1, base .. ":stroke")
            kids[#kids + 1] = paint_text_ref("", base .. ":tx", base .. ":ty", base .. ":tw", 14, 1, 0x11131aff, L.TextStart, small_lh, base .. ":text")
        end
    end

    for i = 1, 5 do
        local base = "arr:auto:" .. i
        kids[#kids + 1] = paint_line("", base .. ":x1", base .. ":y1", base .. ":x2", base .. ":y2", 2, base .. ":color")
    end

    return P.ClipRegion(scalar(0), scalar(0), scalar("arr:w"), scalar("arr:h"), P.Group(kids))
end

local function arrangement_header_row(row_view)
    local flags = row_view.active and { ACTIVE } or {}
    return item(pressable(row_view.id,
        surface("browser_item", flags, fill_w_h(TRACK_ROW_H), col(FILL_BOX, {
            item(text(fill_w_h(18), " " .. row_view.title), 0, 0),
            item(text(fill_w_h(16), " " .. row_view.subtitle), 0, 0),
            item(text(fill_w_h(16), " " .. row_view.route), 0, 0),
        }, { gap = 2 }))), 0, 0)
end

local function arrangement_header_panel(view)
    local rows = { item(U.Spacer(fill_w_h(RULER_H + 14)), 0, 0) }
    for i = 1, #view.tracks do
        rows[#rows + 1] = arrangement_header_row(view.tracks[i])
    end
    rows[#rows + 1] = item(U.Spacer(FILL_BOX), 1, 1)
    return col(box_w_fill_h(ARR_HEADER_W), rows, { gap = 0 })
end

local function arrangement_timeline_overlay(view)
    local rows = { item(U.Spacer(fill_w_h(RULER_H + 14)), 0, 0) }
    for i = 1, #view.tracks do
        rows[#rows + 1] = item(pressable(view.tracks[i].id, U.Spacer(fill_w_h(TRACK_ROW_H))), 0, 0)
    end
    rows[#rows + 1] = item(U.Spacer(FILL_BOX), 1, 1)
    return col(FILL_BOX, rows)
end

local function arrangement_panel(view)
    return surface("panel", {}, FILL_BOX, U.Stack(FILL_BOX, {
        U.CustomPaint("arr:paint", FILL_BOX, arrangement_paint(view)),
        row(FILL_BOX, {
            item(arrangement_header_panel(view), 0, 0),
            item(arrangement_timeline_overlay(view), 1, 1),
        }, { align = L.CrossStretch }),
    }))
end

local function inspector_field_widget(field)
    if field.kind == "ValueField" then
        return item(surface("browser_item", field.active and { ACTIVE } or {}, fill_w_h(40), row(FILL_BOX, {
            item(text(fill_w_h(18), " " .. field.label), 0, 0),
            item(U.Spacer(FILL_BOX), 1, 1),
            item(text(fill_w_h(18), field.value .. " "), 0, 0),
        }, { align = L.CrossCenter })), 0, 0)
    end

    if field.kind == "ToggleField" then
        return item(surface("browser_item", field.active and { ACTIVE } or {}, fill_w_h(40), row(FILL_BOX, {
            item(text(fill_w_h(18), " " .. field.label), 0, 0),
            item(U.Spacer(FILL_BOX), 1, 1),
            item(surface("button", field.value and { ACTIVE } or {}, AUTO_BOX, text(AUTO_BOX, field.value and "ON" or "OFF")), 0, 0),
        }, { align = L.CrossCenter, gap = 8 })), 0, 0)
    end

    local choices = {}
    for i = 1, #field.choices do
        choices[#choices + 1] = item(surface("button", (field.choices[i] == field.value) and { ACTIVE } or {}, AUTO_BOX, text(AUTO_BOX, field.choices[i])), 0, 0)
    end
    return item(surface("browser_item", field.active and { ACTIVE } or {}, fill_w_h(56), col(FILL_BOX, {
        item(text(fill_w_h(18), " " .. field.label), 0, 0),
        item(row(fill_w_h(22), choices, { gap = 4 }), 0, 0),
    }, { gap = 4 })), 0, 0)
end

local function inspector_panel(view)
    local rows = {
        item(text(fill_w_h(HEADER_H), " " .. view.title), 0, 0),
    }
    for i = 1, #view.sections do
        local sec = view.sections[i]
        rows[#rows + 1] = item(text(fill_w_h(18), " " .. sec.title), 0, 0)
        for j = 1, #sec.fields do
            rows[#rows + 1] = inspector_field_widget(sec.fields[j])
        end
    end
    rows[#rows + 1] = item(U.Spacer(FILL_BOX), 1, 1)
    return panel("panel", {}, "", 0, box_w_auto_h(INSPECTOR_W), col(FILL_W_AUTO_H, rows, { gap = 6 }))
end

local function devices_paint(view)
    local kids = {}
    local lh = L.LineHeightPx(16)
    local small_lh = L.LineHeightPx(14)

    kids[#kids + 1] = paint_fill("", 0, 0, "dev:w", "dev:h", 0x1d222dff)
    kids[#kids + 1] = paint_stroke("", 0, 0, "dev:w", "dev:h", 1, 0x394255ff)
    kids[#kids + 1] = paint_text_lit("", 12, 8, 280, 18, 2, 0xa4aec9ff, L.TextStart, lh, view.title)
    kids[#kids + 1] = paint_text_lit("", "dev:w_note_x", 8, "dev:note_w", 18, 1, 0x77819bff, L.TextEnd, small_lh,
        view.current_track_name .. " · " .. view.current_phase_name)

    for i = 1, DEVICE_CAP do
        local base = "dev:slot:" .. i
        local card = view.devices[i]
        kids[#kids + 1] = paint_fill("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", base .. ":fill")
        kids[#kids + 1] = paint_stroke("", base .. ":x", base .. ":y", base .. ":w", base .. ":h", 1, base .. ":stroke")
        kids[#kids + 1] = paint_text_lit("", base .. ":tx", base .. ":ty", base .. ":tw", 16, 1, base .. ":title_color", L.TextStart, lh,
            card and card.name or "")
        kids[#kids + 1] = paint_text_lit("", base .. ":tx", base .. ":ty2", base .. ":tw", 14, 1, 0x77819bff, L.TextStart, small_lh,
            card and card.family or "")
        for k = 1, 3 do
            local knob = base .. ":bar:" .. k
            kids[#kids + 1] = paint_stroke("", knob .. ":x", knob .. ":y_box", 14, "dev:bar_box_h", 1, 0x394255ff)
            kids[#kids + 1] = paint_fill("", knob .. ":x", knob .. ":y_fill", 14, knob .. ":h", knob .. ":color")
        end
    end

    kids[#kids + 1] = paint_fill("", "dev:info_x", 34, "dev:info_w", 72, 0x171a22ff)
    kids[#kids + 1] = paint_stroke("", "dev:info_x", 34, "dev:info_w", 72, 1, 0x394255ff)
    kids[#kids + 1] = paint_text_ref("", "dev:info_tx", 42, "dev:info_tw", 16, 1, 0xd6dceaff, L.TextStart, small_lh, "dev:phase")
    kids[#kids + 1] = paint_text_ref("", "dev:info_tx", 60, "dev:info_tw", 16, 1, 0xa4aec9ff, L.TextStart, small_lh, "dev:compile")
    kids[#kids + 1] = paint_text_ref("", "dev:info_tx", 78, "dev:info_tw", 16, 1, 0xa4aec9ff, L.TextStart, small_lh, "dev:split")
    kids[#kids + 1] = paint_stroke("", "dev:sem_x", 100, "dev:bar_w", 8, 1, 0x394255ff)
    kids[#kids + 1] = paint_fill("", "dev:sem_x", 100, "dev:sem_w", 8, 0x76a9ffff)
    kids[#kids + 1] = paint_stroke("", "dev:sem_x", 122, "dev:bar_w", 8, 1, 0x394255ff)
    kids[#kids + 1] = paint_fill("", "dev:sem_x", 122, "dev:terra_w", 8, 0x79d2a6ff)
    kids[#kids + 1] = paint_text_ref("", "dev:sem_x", 132, "dev:info_tw", 14, 1, 0x77819bff, L.TextStart, small_lh, "dev:reuse")

    for i = 1, 4 do
        local base = "dev:log:" .. i
        kids[#kids + 1] = paint_fill("", 0, base .. ":y", "dev:w", 18, base .. ":bg")
        kids[#kids + 1] = paint_text_ref("", 10, base .. ":y", "dev:log_w", 16, 4, base .. ":fg", L.TextStart, small_lh, base .. ":text")
    end

    return P.ClipRegion(scalar(0), scalar(0), scalar("dev:w"), scalar("dev:h"), P.Group(kids))
end

local function devices_panel(view)
    return surface("panel", {}, FILL_BOX, U.CustomPaint("dev:paint", FILL_BOX, devices_paint(view)))
end

local function remote_panel(view)
    return surface("panel", {}, box_w_auto_h(REMOTE_W), col(FILL_W_AUTO_H, {
        item(text(fill_w_h(HEADER_H), " " .. view.title), 0, 0),
        item(text(fill_w_h(18), " " .. view.subtitle), 0, 0),
        item(U.Spacer(FILL_BOX), 1, 1),
        item(text(fill_w_h(36), view.empty_message), 0, 0),
        item(U.Spacer(FILL_BOX), 1, 1),
    }, { gap = 8 }))
end

local function status_bar(view)
    return surface("statusbar", {}, fill_w_h(STATUS_H), row(FILL_BOX, {
        item(text(AUTO_BOX, " " .. view.left), 0, 0),
        item(U.Spacer(FILL_BOX), 1, 1),
        item(text(AUTO_BOX, view.right .. " "), 0, 0),
    }, { align = L.CrossCenter }))
end

function M.sem(view, opts)
    return surface("window", {}, FILL_BOX, col(FILL_BOX, {
        item(titlebar(view.titlebar), 0, 0),
        item(toolbar(view.transport), 0, 0),
        item(row(FILL_W_AUTO_H, {
            item(browser_rail(view.browser_rail), 0, 0),
            item(launcher_panel(view.launcher), 0, 0),
            item(arrangement_panel(view.arrangement), 1, 1),
            item(inspector_panel(view.inspector), 0, 0),
        }, { align = L.CrossStretch }), 1, 1, L.BasisPx(0)),
        item(row(fill_w_h(DEVICE_H), {
            item(devices_panel(view.devices), 1, 1),
            item(remote_panel(view.remote), 0, 0),
        }, { align = L.CrossStretch }), 0, 0, L.BasisPx(DEVICE_H)),
    }))
end

function M.node(theme, view, opts)
    local sem = M.sem(view, opts)
    return lower.node(theme, sem, opts), sem
end

function V.Window:to_sem(opts)
    return M.sem(self, opts)
end

return M
