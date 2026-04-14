-- ui/demo/lower.lua
-- Lower the demo widget/view ASDL layer into generic SemUI/UI.

local pvm = require("pvm")
local classof = pvm.classof
local ui = require("ui.init")
local demo_schema = require("ui.demo.asdl")

local T = ui.T
local V = demo_schema.T.DemoView
local Slot = demo_schema.T.DemoSlot
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

local MTV = {}
do
    local titlebar = V.TitleBar("", "", "")
    local transport = V.TransportBar("", "", "", Slot.Clock, {})
    local browser = V.BrowserRail("", "", "")
    local launcher = V.LauncherPanel("", "", "", {})
    local arrangement = V.ArrangementPanel("", "", "", 0, {}, {}, Slot.Arrangement)
    local inspector = V.InspectorPanel("", {})
    local devices = V.DevicesPanel("", Slot.DevicesSubtitle, {}, Slot.Devices)
    local remote = V.RemotePanel("", "", "")
    local status = V.StatusBar("", Slot.StatusRight)

    MTV.Window = classof(V.Window(titlebar, transport, browser, launcher, arrangement, inspector, devices, remote, status))
    MTV.TitleBar = classof(titlebar)
    MTV.TransportBar = classof(transport)
    MTV.TransportButton = classof(V.TransportButton("", ""))
    MTV.BrowserRail = classof(browser)
    MTV.LauncherButton = classof(V.LauncherButton("", ""))
    MTV.LauncherSlot = classof(V.LauncherSlot("", ""))
    MTV.LauncherTrackRow = classof(V.LauncherTrackRow(0, "", "", "", "", "", {}, {}))
    MTV.LauncherPanel = classof(launcher)
    MTV.ArrangementTrackRow = classof(V.ArrangementTrackRow(0, "", "", "", "", 0))
    MTV.ArrangementPanel = classof(arrangement)
    MTV.ValueField = classof(V.ValueField("", "", false))
    MTV.LiveValueField = classof(V.LiveValueField("", Slot.Reuse, false))
    MTV.ToggleField = classof(V.ToggleField("", false, false))
    MTV.ChoiceField = classof(V.ChoiceField("", "", {}, false))
    MTV.InspectorSection = classof(V.InspectorSection("", {}))
    MTV.InspectorPanel = classof(inspector)
    MTV.DevicesPanel = classof(devices)
    MTV.RemotePanel = classof(remote)
    MTV.StatusBar = classof(status)
end

local ACTIVE = ds.flag("active")

local function text_slot_name(slot)
    if slot == Slot.Clock then
        return "transport:clock"
    elseif slot == Slot.Reuse then
        return "inspector:reuse"
    elseif slot == Slot.DevicesSubtitle then
        return "devices:subtitle"
    elseif slot == Slot.StatusRight then
        return "status:right"
    end
    error("ui.demo.lower: unsupported text slot", 2)
end

local function paint_slot_name(slot)
    if slot == Slot.Arrangement then
        return "arr:paint"
    elseif slot == Slot.Devices then
        return "dev:paint"
    end
    error("ui.demo.lower: unsupported paint slot", 2)
end

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

local function ui_text(v)
    return v or ""
end

local function make_text_spec(opts)
    opts = opts or {}
    return U.TextSpec(
        opts.font or U.UseSurfaceFont,
        opts.line_height or U.UseSurfaceLineHeight,
        opts.align and U.OverrideTextAlign(opts.align) or U.UseSurfaceTextAlign,
        opts.wrap and U.OverrideTextWrap(opts.wrap) or U.UseSurfaceTextWrap,
        opts.overflow and U.OverrideOverflow(opts.overflow) or U.UseSurfaceOverflow,
        opts.line_limit and U.OverrideLineLimit(opts.line_limit) or U.UseSurfaceLineLimit)
end

local function text(box, txt)
    return U.Text("", box, make_text_spec(), ui_text(txt))
end

local function runtime_text(tag, box, opts)
    return U.RuntimeText(tag or "", box, make_text_spec(opts), "")
end

local function surface(surface_name, flags, box, child)
    return U.Panel(surface_name, flags or {}, box, child)
end

local function scroll_panel(surface_name, flags, id, scroll_y, box, child)
    return U.ScrollPanel(surface_name, flags or {}, id or "", L.ScrollY, 0, scroll_y or 0, box, child)
end

local function pressable(id, child)
    return U.Interact("", id, id, id, child)
end

local EMPTY_PAINT = P.Group({})

local lower_view
local lower_window
local lower_titlebar
local lower_transport_bar
local lower_transport_button
local lower_browser_rail
local lower_launcher_button
local lower_launcher_slot
local lower_launcher_track_row
local lower_launcher_panel
local lower_arrangement_track_row
local lower_arrangement_panel
local lower_inspector_field
local lower_inspector_section
local lower_inspector_panel
local lower_devices_panel
local lower_remote_panel
local lower_status_bar

local function titlebar(view)
    return surface("transport", {}, fill_w_h(TITLEBAR_H), row(FILL_BOX, {
        item(text(AUTO_BOX, " " .. view.app_badge), 0, 0),
        item(text(AUTO_BOX, " " .. view.document_title), 0, 0),
        item(U.Spacer(FILL_BOX), 1, 1),
        item(text(AUTO_BOX, view.engine_text), 0, 0),
    }, { align = L.CrossStretch, gap = 8 }))
end

local function toolbar(view)
    local children = {}
    for i = 1, #view.buttons do
        children[#children + 1] = item(lower_view(view.buttons[i]), 0, 0)
        if view.buttons[i].id == "action:live" then
            children[#children + 1] = item(text(AUTO_BOX, view.phase_text), 0, 0)
        end
    end
    children[#children + 1] = item(U.Spacer(FILL_BOX), 1, 1)
    children[#children + 1] = item(text(AUTO_BOX, view.bpm_text), 0, 0)
    children[#children + 1] = item(text(AUTO_BOX, view.meter_text), 0, 0)
    children[#children + 1] = item(runtime_text(text_slot_name(view.clock_slot), box_w_auto_h(84), { align = L.TextEnd }), 0, 0)

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

local function launcher_track_row(row_view)
    local button_row = {}
    for i = 1, #row_view.buttons do
        button_row[#button_row + 1] = item(lower_view(row_view.buttons[i]), 0, 0)
    end
    local slot_cols = { L.TrackFr(1), L.TrackFr(1) }
    local slot_rows = { L.TrackAuto }
    local slot_items = {}
    for i = 1, #row_view.slots do
        slot_items[i] = U.GridItem(lower_view(row_view.slots[i]), i, 1, 1, 1)
    end
    return item(row(fill_w_h(LAUNCHER_ROW_H), {
        item(pressable(row_view.id,
            surface("browser_item", {}, box_w_fill_h(236), col(FILL_BOX, {
                item(text(fill_w_h(18), row_view.title), 0, 0),
                item(text(fill_w_h(16), " " .. row_view.subtitle), 0, 0),
                item(row(fill_w_h(18), button_row, { gap = 4 }), 0, 0),
            }, { gap = 2 }))), 0, 0),
        item(col(box_w_fill_h(170), {
            item(text(fill_w_h(16), row_view.meter_text), 0, 0),
            item(U.Grid(slot_cols, slot_rows, 4, 0, fill_w_h(18), slot_items), 0, 0),
        }, { gap = 6 }), 0, 0),
    }, { align = L.CrossStretch, gap = 12 }), 0, 0)
end

local function launcher_panel(view)
    local header_cols = { L.TrackPx(236), L.TrackFr(1), L.TrackFr(1) }
    local header_rows = { L.TrackAuto }
    local rows = {
        item(text(fill_w_h(HEADER_H), " " .. view.title), 0, 0),
        item(U.Grid(header_cols, header_rows, 12, 0, fill_w_h(18), {
            U.GridItem(text(fill_w_h(18), " tracks"), 1, 1, 1, 1),
            U.GridItem(text(AUTO_BOX, view.scene_title_a), 2, 1, 1, 1),
            U.GridItem(text(AUTO_BOX, view.scene_title_b), 3, 1, 1, 1),
        }), 0, 0),
    }
    for i = 1, #view.rows do
        rows[#rows + 1] = item(lower_view(view.rows[i]), 0, 0)
    end
    rows[#rows + 1] = item(U.Spacer(FILL_BOX), 1, 1)
    return surface("panel", {}, box_w_fill_h(LAUNCHER_W), col(FILL_BOX, rows, { gap = 6 }))
end

local function arrangement_header_row(row_view)
    return item(pressable(row_view.id,
        surface("browser_item", {}, fill_w_h(TRACK_ROW_H), col(FILL_BOX, {
            item(text(fill_w_h(18), row_view.title), 0, 0),
            item(text(fill_w_h(16), " " .. row_view.subtitle), 0, 0),
            item(text(fill_w_h(16), " " .. row_view.route), 0, 0),
        }, { gap = 2 }))), 0, 0)
end

local function arrangement_header_panel(view)
    local rows = { item(U.Spacer(fill_w_h(RULER_H + 14)), 0, 0) }
    for i = 1, #view.tracks do
        rows[#rows + 1] = item(lower_view(view.tracks[i]), 0, 0)
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

local function inspector_field_widget(field)
    if field.kind == "ValueField" then
        return item(surface("browser_item", field.active and { ACTIVE } or {}, fill_w_h(40), row(FILL_BOX, {
            item(text(AUTO_BOX, " " .. field.label), 0, 0),
            item(U.Spacer(FILL_BOX), 1, 1),
            item(text(AUTO_BOX, field.value), 0, 0),
        }, { align = L.CrossCenter, gap = 8 })), 0, 0)
    end

    if field.kind == "LiveValueField" then
        return item(surface("browser_item", field.active and { ACTIVE } or {}, fill_w_h(40), row(FILL_BOX, {
            item(text(AUTO_BOX, " " .. field.label), 0, 0),
            item(U.Spacer(FILL_BOX), 1, 1),
            item(runtime_text(text_slot_name(field.text_slot), box_w_auto_h(88), { align = L.TextEnd }), 0, 0),
        }, { align = L.CrossCenter, gap = 8 })), 0, 0)
    end

    if field.kind == "ToggleField" then
        return item(surface("browser_item", field.active and { ACTIVE } or {}, fill_w_h(40), row(FILL_BOX, {
            item(text(AUTO_BOX, " " .. field.label), 0, 0),
            item(U.Spacer(FILL_BOX), 1, 1),
            item(surface("button", field.value and { ACTIVE } or {}, AUTO_BOX, text(AUTO_BOX, field.value and "ON" or "OFF")), 0, 0),
        }, { align = L.CrossCenter, gap = 8 })), 0, 0)
    end

    local cols = {}
    local rows = { L.TrackAuto }
    local choices = {}
    for i = 1, #field.choices do
        cols[i] = L.TrackFr(1)
        choices[i] = U.GridItem(
            surface("button", (field.choices[i] == field.value) and { ACTIVE } or {}, AUTO_BOX, text(AUTO_BOX, field.choices[i])),
            i,
            1,
            1,
            1)
    end
    return item(surface("browser_item", field.active and { ACTIVE } or {}, fill_w_h(56), col(FILL_BOX, {
        item(text(AUTO_BOX, " " .. field.label), 0, 0),
        item(U.Grid(cols, rows, 4, 0, fill_w_h(22), choices), 0, 0),
    }, { gap = 4 })), 0, 0)
end

local function inspector_panel(view)
    local rows = {
        item(text(fill_w_h(HEADER_H), " " .. view.title), 0, 0),
    }
    for i = 1, #view.sections do
        local section = view.sections[i]
        local srows = { item(text(fill_w_h(18), " " .. section.title), 0, 0) }
        for j = 1, #section.fields do
            srows[#srows + 1] = item(lower_inspector_field(section.fields[j]), 0, 0)
        end
        rows[#rows + 1] = item(col(FILL_W_AUTO_H, srows, { gap = 6 }), 0, 0)
    end
    rows[#rows + 1] = item(U.Spacer(FILL_BOX), 1, 1)
    return scroll_panel("panel", {}, "", 0, box_w_auto_h(INSPECTOR_W), col(FILL_W_AUTO_H, rows, { gap = 6 }))
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
        item(text(AUTO_BOX, view.left), 0, 0),
        item(U.Spacer(FILL_BOX), 1, 1),
        item(runtime_text(text_slot_name(view.right_slot), box_w_auto_h(360), { align = L.TextEnd }), 0, 0),
    }, { align = L.CrossCenter }))
end

lower_titlebar = pvm.lower("ui.demo.lower.titlebar", titlebar)
lower_transport_button = pvm.lower("ui.demo.lower.transport_button", function(view)
    return pressable(view.id, surface("button", {}, AUTO_BOX, text(AUTO_BOX, view.label)))
end)
lower_transport_bar = pvm.lower("ui.demo.lower.transport_bar", toolbar)
lower_browser_rail = pvm.lower("ui.demo.lower.browser_rail", browser_rail)
lower_launcher_button = pvm.lower("ui.demo.lower.launcher_button", function(view)
    return pressable(view.id, surface("button", {}, AUTO_BOX, text(AUTO_BOX, view.label)))
end)
lower_launcher_slot = pvm.lower("ui.demo.lower.launcher_slot", function(view)
    return pressable(view.id, surface("button", {}, fill_w_h(18), text(fill_w_h(18), view.label)))
end)
lower_launcher_track_row = pvm.lower("ui.demo.lower.launcher_track_row", function(view)
    return launcher_track_row(view).node
end)
lower_launcher_panel = pvm.lower("ui.demo.lower.launcher_panel", launcher_panel)
lower_arrangement_track_row = pvm.lower("ui.demo.lower.arrangement_track_row", function(view)
    return arrangement_header_row(view).node
end)
lower_arrangement_panel = pvm.lower("ui.demo.lower.arrangement_panel", function(view)
    return surface("panel", {}, FILL_BOX, U.Stack(FILL_BOX, {
        U.CustomPaint(paint_slot_name(view.overlay_slot), FILL_BOX, EMPTY_PAINT),
        row(FILL_BOX, {
            item(arrangement_header_panel(view), 0, 0),
            item(arrangement_timeline_overlay(view), 1, 1),
        }, { align = L.CrossStretch }),
    }))
end)
lower_inspector_field = pvm.lower("ui.demo.lower.inspector_field", function(view)
    return inspector_field_widget(view).node
end)
lower_inspector_section = pvm.lower("ui.demo.lower.inspector_section", function(view)
    local rows = { item(text(fill_w_h(18), " " .. view.title), 0, 0) }
    for i = 1, #view.fields do
        rows[#rows + 1] = item(lower_view(view.fields[i]), 0, 0)
    end
    return col(FILL_W_AUTO_H, rows, { gap = 6 })
end)
lower_inspector_panel = pvm.lower("ui.demo.lower.inspector_panel", inspector_panel)
lower_devices_panel = pvm.lower("ui.demo.lower.devices_panel", function(view)
    return surface("panel", {}, FILL_BOX, U.CustomPaint(paint_slot_name(view.overlay_slot), FILL_BOX, EMPTY_PAINT))
end)
lower_remote_panel = pvm.lower("ui.demo.lower.remote_panel", remote_panel)
lower_status_bar = pvm.lower("ui.demo.lower.status_bar", status_bar)
lower_window = pvm.lower("ui.demo.lower.window", function(view)
    return surface("window", {}, FILL_BOX, col(FILL_BOX, {
        item(lower_titlebar(view.titlebar), 0, 0),
        item(lower_transport_bar(view.transport), 0, 0),
        item(row(FILL_W_AUTO_H, {
            item(lower_browser_rail(view.browser_rail), 0, 0),
            item(lower_launcher_panel(view.launcher), 0, 0),
            item(lower_arrangement_panel(view.arrangement), 1, 1),
            item(lower_inspector_panel(view.inspector), 0, 0),
        }, { align = L.CrossStretch }), 1, 1, L.BasisPx(0)),
        item(row(fill_w_h(DEVICE_H), {
            item(lower_devices_panel(view.devices), 1, 1),
            item(lower_remote_panel(view.remote), 0, 0),
        }, { align = L.CrossStretch }), 0, 0, L.BasisPx(DEVICE_H)),
        item(lower_status_bar(view.status), 0, 0),
    }))
end)

lower_view = pvm.lower("ui.demo.lower.view", function(view)
    local mt = classof(view)

    if mt == MTV.Window then
        return lower_window(view)
    elseif mt == MTV.TitleBar then
        return lower_titlebar(view)
    elseif mt == MTV.TransportBar then
        return lower_transport_bar(view)
    elseif mt == MTV.TransportButton then
        return lower_transport_button(view)
    elseif mt == MTV.BrowserRail then
        return lower_browser_rail(view)
    elseif mt == MTV.LauncherButton then
        return lower_launcher_button(view)
    elseif mt == MTV.LauncherSlot then
        return lower_launcher_slot(view)
    elseif mt == MTV.LauncherTrackRow then
        return lower_launcher_track_row(view)
    elseif mt == MTV.LauncherPanel then
        return lower_launcher_panel(view)
    elseif mt == MTV.ArrangementTrackRow then
        return lower_arrangement_track_row(view)
    elseif mt == MTV.ArrangementPanel then
        return lower_arrangement_panel(view)
    elseif mt == MTV.ValueField or mt == MTV.LiveValueField or mt == MTV.ToggleField or mt == MTV.ChoiceField then
        return lower_inspector_field(view)
    elseif mt == MTV.InspectorSection then
        return lower_inspector_section(view)
    elseif mt == MTV.InspectorPanel then
        return lower_inspector_panel(view)
    elseif mt == MTV.DevicesPanel then
        return lower_devices_panel(view)
    elseif mt == MTV.RemotePanel then
        return lower_remote_panel(view)
    elseif mt == MTV.StatusBar then
        return lower_status_bar(view)
    end

    error("ui.demo.lower.view: unsupported DemoView node", 2)
end)

function M.sem(view)
    return lower_view(view)
end

function M.node(theme, view, opts)
    opts = opts or {}
    local sem = M.sem(view, opts)
    return lower.node(theme, sem, opts), sem
end

function M.stats()
    return {
        view = lower_view:stats(),
        window = lower_window:stats(),
        titlebar = lower_titlebar:stats(),
        transport_bar = lower_transport_bar:stats(),
        transport_button = lower_transport_button:stats(),
        browser_rail = lower_browser_rail:stats(),
        launcher_button = lower_launcher_button:stats(),
        launcher_slot = lower_launcher_slot:stats(),
        launcher_track_row = lower_launcher_track_row:stats(),
        launcher_panel = lower_launcher_panel:stats(),
        arrangement_track_row = lower_arrangement_track_row:stats(),
        arrangement_panel = lower_arrangement_panel:stats(),
        inspector_field = lower_inspector_field:stats(),
        inspector_section = lower_inspector_section:stats(),
        inspector_panel = lower_inspector_panel:stats(),
        devices_panel = lower_devices_panel:stats(),
        remote_panel = lower_remote_panel:stats(),
        status_bar = lower_status_bar:stats(),
        lower = lower.stats(),
    }
end

function M.reset()
    lower_view:reset()
    lower_window:reset()
    lower_titlebar:reset()
    lower_transport_bar:reset()
    lower_transport_button:reset()
    lower_browser_rail:reset()
    lower_launcher_button:reset()
    lower_launcher_slot:reset()
    lower_launcher_track_row:reset()
    lower_launcher_panel:reset()
    lower_arrangement_track_row:reset()
    lower_arrangement_panel:reset()
    lower_inspector_field:reset()
    lower_inspector_section:reset()
    lower_inspector_panel:reset()
    lower_devices_panel:reset()
    lower_remote_panel:reset()
    lower_status_bar:reset()
    lower.reset()
end

function V.Window:to_sem(opts)
    return M.sem(self, opts)
end

return M
