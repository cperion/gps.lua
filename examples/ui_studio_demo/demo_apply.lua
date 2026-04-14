local pvm = require("pvm")
local ui = require("ui")
local studio_asdl = require("demo_asdl")

local T = studio_asdl.T
local Studio = T.Studio
local Core = T.Core

local M = {}

local BROWSER_SCROLL_ID = Core.IdValue("browser-scroll")
local LAUNCHER_SCROLL_ID = Core.IdValue("launcher-scroll")
local DETAIL_SCROLL_ID = Core.IdValue("detail-scroll")

local function browser_id(index)
    return Core.IdValue("browser:" .. index)
end

local function track_id(index)
    return Core.IdValue("track:" .. index)
end

local function scene_id(index)
    return Core.IdValue("scene:" .. index)
end

local function clip_id(track_index, scene_index)
    return Core.IdValue(string.format("clip:%d:%d", track_index, scene_index))
end

local function device_id(index)
    return Core.IdValue("device:" .. index)
end

local function transport_id()
    return Core.IdValue("transport:play")
end

local function theme_toggle_id()
    return Core.IdValue("theme:toggle")
end

function M.selection_id(selection)
    if selection == Studio.SelNone then return Core.NoId end
    if selection == Studio.SelTransport then return transport_id() end

    local cls = pvm.classof(selection)
    if cls == Studio.SelBrowser then return browser_id(selection.index) end
    if cls == Studio.SelTrack then return track_id(selection.index) end
    if cls == Studio.SelScene then return scene_id(selection.index) end
    if cls == Studio.SelClip then return clip_id(selection.track_index, selection.scene_index) end
    if cls == Studio.SelDevice then return device_id(selection.index) end
    return Core.NoId
end

function M.selection_from_id(id)
    if id == nil or id == Core.NoId then return Studio.SelNone end
    local value = id.value
    if value == "transport:play" then return Studio.SelTransport end

    local browser_i = string.match(value, "^browser:(%d+)$")
    if browser_i then return Studio.SelBrowser(tonumber(browser_i)) end

    local track_i = string.match(value, "^track:(%d+)$")
    if track_i then return Studio.SelTrack(tonumber(track_i)) end

    local scene_i = string.match(value, "^scene:(%d+)$")
    if scene_i then return Studio.SelScene(tonumber(scene_i)) end

    local clip_t, clip_s = string.match(value, "^clip:(%d+):(%d+)$")
    if clip_t then return Studio.SelClip(tonumber(clip_t), tonumber(clip_s)) end

    local device_i = string.match(value, "^device:(%d+)$")
    if device_i then return Studio.SelDevice(tonumber(device_i)) end

    return Studio.SelNone
end

local function append_log(logs, text)
    local out = {}
    local start = #logs >= 18 and 2 or 1
    for i = start, #logs do
        out[#out + 1] = logs[i]
    end
    out[#out + 1] = text
    return out
end

local function selection_title(app, selection)
    if selection == Studio.SelTransport then
        return "Transport"
    end

    local cls = pvm.classof(selection)
    if cls == Studio.SelBrowser then
        local item = app.browser_items[selection.index]
        return item and item.title or "Browser"
    end
    if cls == Studio.SelTrack then
        local track = app.tracks[selection.index]
        return track and track.name or "Track"
    end
    if cls == Studio.SelScene then
        local scene = app.scenes[selection.index]
        return scene and scene.name or "Scene"
    end
    if cls == Studio.SelClip then
        local track = app.tracks[selection.track_index]
        local scene = app.scenes[selection.scene_index]
        if track and scene then return track.name .. " / " .. scene.name end
        return "Clip"
    end
    if cls == Studio.SelDevice then
        local device = app.devices[selection.index]
        return device and device.name or "Device"
    end
    return "Selection"
end

function M.event_from_ui(ui_event)
    local cls = pvm.classof(ui_event)
    if cls == T.Interact.SetFocus then
        local id = ui_event.id
        if id == nil or id == Core.NoId or id == theme_toggle_id() then
            return nil
        end
        return Studio.FocusSelection(M.selection_from_id(id))
    end
    if cls == T.Interact.Activate then
        if ui_event.id == theme_toggle_id() then
            return Studio.ToggleTheme
        end
        return Studio.ActivateSelection(M.selection_from_id(ui_event.id))
    end
end

local function apply_app(app, event)
    local cls = pvm.classof(event)
    if cls == Studio.FocusSelection then
        local selection = event.selection
        if selection == Studio.SelNone or selection == Studio.SelTransport or selection == app.selection then
            return app
        end
        return pvm.with(app, { selection = selection })
    end

    if cls == Studio.ActivateSelection then
        local selection = event.selection
        if selection == Studio.SelNone then
            return app
        end

        if selection == Studio.SelTransport then
            local playing = not app.playing
            return pvm.with(app, {
                playing = playing,
                logs = append_log(app.logs, playing and "Transport engaged." or "Transport stopped."),
            })
        end

        return pvm.with(app, {
            selection = selection,
            logs = append_log(app.logs, "Selected " .. selection_title(app, selection)),
        })
    end

    if event == Studio.ToggleTheme then
        local next_mode = app.theme_mode == Studio.ThemeDark and Studio.ThemeLight or Studio.ThemeDark
        return pvm.with(app, {
            theme_mode = next_mode,
            logs = append_log(app.logs, next_mode == Studio.ThemeLight and "Switched to light workspace." or "Switched to dark workspace."),
        })
    end

    return app
end

function M.apply(state, event)
    local next_app = apply_app(state.app, event)
    if next_app == state.app then return state end
    return pvm.with(state, { app = next_app })
end

function M.initial_app()
    local browser_items = {}
    local browser_titles = { "Quartz Bloom", "Pulse Garden", "Nebula Drum Rack", "Cloud Ribbon", "Solar Pad", "Nocturne Bells" }
    local browser_tags = { "instrument", "audio fx", "modulator", "macro" }
    local browser_notes = { "evolving texture", "tight transient", "slow shimmer", "performance rack" }
    for i = 1, 24 do
        browser_items[i] = Studio.BrowserItem(
            browser_titles[(i - 1) % #browser_titles + 1] .. " " .. i,
            browser_tags[(i - 1) % #browser_tags + 1],
            browser_notes[(i - 1) % #browser_notes + 1]
        )
    end

    local tracks = {}
    local track_names = { "Drums", "Bass", "Keys", "Vocals", "FX", "Master" }
    local routes = { "Bus A", "Sub", "Chord Bus", "Vocal Print", "FX Return", "Stereo Out" }
    local groups = { "rhythm", "low end", "harmony", "lead", "space", "sum" }
    for i = 1, #track_names do
        tracks[i] = Studio.Track(
            track_names[i],
            string.upper(string.sub(track_names[i], 1, 2)),
            routes[i],
            groups[i]
        )
    end

    local scenes = {}
    local scene_names = { "Intro", "Build", "Verse", "Lift", "Break", "Drop", "Bridge", "Finale" }
    local lengths = { "16 bars", "8 bars", "32 bars", "16 bars", "8 bars", "32 bars", "16 bars", "24 bars" }
    for i = 1, #scene_names do
        scenes[i] = Studio.Scene(
            scene_names[i],
            string.upper(string.sub(scene_names[i], 1, 2)),
            lengths[i]
        )
    end

    local devices = {
        Studio.Device(Studio.Instrument, "Granular Bloom", "Spectral grains with macro morphing and harmonic spread."),
        Studio.Device(Studio.Mixer, "Punch Glue", "Parallel compression with transient recovery and saturating clip stage."),
        Studio.Device(Studio.Mod, "Motion Grid", "Macro sequencer routing scene energy into launch intensity."),
        Studio.Device(Studio.Fx, "Prism Space", "Dark hall with diffused shimmer and tempo-locked bloom."),
    }

    local logs = {
        "Compiler shell ready.",
        "Launcher matrix warmed with shared flow/flex/grid planners.",
        "Love text measurer registered as explicit text system.",
    }

    return Studio.App(
        "Aurora Set",
        124,
        true,
        Studio.ThemeDark,
        Studio.SelClip(1, 1),
        browser_items,
        tracks,
        scenes,
        devices,
        logs
    )
end

local function clamp_ui_model(model)
    local changed = false
    local scrolls = model.scrolls
    local out = {}
    for i = 1, #scrolls do
        local s = scrolls[i]
        local x = s.x < 0 and 0 or s.x
        local y = s.y < 0 and 0 or s.y
        if x ~= s.x or y ~= s.y then
            changed = true
            out[i] = T.Solve.Scroll(s.id, x, y)
        else
            out[i] = s
        end
    end
    if changed then
        return pvm.with(model, { scrolls = out })
    end
    return model
end

function M.with_ui_model(state, next_ui_model)
    next_ui_model = clamp_ui_model(next_ui_model)
    if next_ui_model == state.ui_model then return state end
    return pvm.with(state, { ui_model = next_ui_model })
end

function M.initial_state()
    local app = M.initial_app()
    local ui_model = ui.interact.model {
        focus_id = M.selection_id(app.selection),
        scrolls = {
            T.Solve.Scroll(BROWSER_SCROLL_ID, 0, 0),
            T.Solve.Scroll(LAUNCHER_SCROLL_ID, 0, 0),
            T.Solve.Scroll(DETAIL_SCROLL_ID, 0, 0),
        },
    }
    return Studio.State(app, clamp_ui_model(ui_model))
end

function M.step(state, report, raw)
    if report == nil then
        local cls = pvm.classof(raw)
        if cls == T.Interact.PointerMoved or cls == T.Interact.PointerPressed or cls == T.Interact.PointerReleased or cls == T.Interact.WheelMoved then
            return M.with_ui_model(state, ui.interact.apply(state.ui_model, T.Interact.SetPointer(raw.x, raw.y))), {}, {}
        end
        return state, {}, {}
    end

    local next_ui_model, ui_events = ui.interact.step(state.ui_model, report, raw)
    local next_state = M.with_ui_model(state, next_ui_model)
    local app_events = {}
    for i = 1, #ui_events do
        local app_event = M.event_from_ui(ui_events[i])
        if app_event ~= nil then
            app_events[#app_events + 1] = app_event
            next_state = M.apply(next_state, app_event)
        end
    end
    return next_state, ui_events, app_events
end

return M
