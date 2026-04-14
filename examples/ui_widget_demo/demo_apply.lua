local pvm = require("pvm")
local ui = require("ui")
local demo_asdl = require("demo_asdl")

local T = demo_asdl.T
local W = T.Widget
local Core = T.Core

local M = {}

local CONTENT_SCROLL_ID = Core.IdValue("content-scroll")

local function append_log(logs, text)
    local out = {}
    local start = #logs >= 18 and 2 or 1
    for i = start, #logs do
        out[#out + 1] = logs[i]
    end
    out[#out + 1] = text
    return out
end

local function apply_app(app, event)
    local cls = pvm.classof(event)

    if cls == W.SetSection then
        return pvm.with(app, { section = event.section })
    end

    if cls == W.SetTab then
        return pvm.with(app, { tab = event.tab })
    end

    if event == W.ToggleTheme then
        local next_mode = app.theme_mode == W.ThemeDark and W.ThemeLight or W.ThemeDark
        return pvm.with(app, { theme_mode = next_mode })
    end

    if cls == W.FlipToggle then
        local toggles = {}
        for i = 1, #app.toggles do
            if i == event.index then
                local old = app.toggles[i]
                toggles[i] = pvm.with(old, {
                    state = old.state == W.On and W.Off or W.On,
                })
            else
                toggles[i] = app.toggles[i]
            end
        end
        return pvm.with(app, { toggles = toggles })
    end

    if cls == W.SlideTo then
        local sliders = {}
        for i = 1, #app.sliders do
            if i == event.index then
                sliders[i] = pvm.with(app.sliders[i], { value = event.value })
            else
                sliders[i] = app.sliders[i]
            end
        end
        return pvm.with(app, { sliders = sliders })
    end

    if cls == W.EditText then
        local text_inputs = {}
        for i = 1, #app.text_inputs do
            if i == event.index then
                text_inputs[i] = pvm.with(app.text_inputs[i], { value = event.value })
            else
                text_inputs[i] = app.text_inputs[i]
            end
        end
        return pvm.with(app, { text_inputs = text_inputs })
    end

    if event == W.Tick then
        local tick = app.tick + 1

        local progresses = {}
        for i = 1, #app.progresses do
            local p = app.progresses[i]
            local speed = 0.003 + i * 0.002
            local f = p.fraction + speed
            if f > 1 then f = f - 1 end
            progresses[i] = pvm.with(p, { fraction = f })
        end

        return pvm.with(app, { tick = tick, progresses = progresses })
    end

    return app
end

function M.apply(state, event)
    local next_app = apply_app(state.app, event)
    if next_app == state.app then return state end
    return pvm.with(state, { app = next_app })
end

function M.initial_app()
    local toggles = {
        W.ToggleItem("Dark mode", W.On),
        W.ToggleItem("Notifications", W.On),
        W.ToggleItem("Auto-save", W.Off),
        W.ToggleItem("Compact view", W.Off),
        W.ToggleItem("Show grid", W.On),
    }

    local sliders = {
        W.SliderItem("Volume", 0.72),
        W.SliderItem("Brightness", 0.55),
        W.SliderItem("Opacity", 0.90),
        W.SliderItem("Blur", 0.30),
        W.SliderItem("Scale", 1.00),
    }

    local text_inputs = {
        W.TextInputItem("Name", "Enter your name...", ""),
        W.TextInputItem("Email", "you@example.com", ""),
        W.TextInputItem("Search", "Search...", ""),
    }

    local progresses = {
        W.ProgressItem("Upload", 0.0),
        W.ProgressItem("Download", 0.33),
        W.ProgressItem("Processing", 0.66),
    }

    local badges = {
        W.BadgeItem("Default", W.BadgeDefault),
        W.BadgeItem("Primary", W.BadgePrimary),
        W.BadgeItem("Success", W.BadgeSuccess),
        W.BadgeItem("Warning", W.BadgeWarning),
        W.BadgeItem("Error", W.BadgeError),
    }

    local alerts = {
        W.AlertItem("Information", "A new version is available. Update when ready.", W.AlertInfo),
        W.AlertItem("Success", "Your changes have been saved successfully.", W.AlertSuccess),
        W.AlertItem("Warning", "Your session will expire in 5 minutes.", W.AlertWarning),
        W.AlertItem("Error", "Failed to connect to the server. Please retry.", W.AlertError),
    }

    local cards = {
        W.CardItem("Getting Started", "Explore the widget gallery to see all available components.", "Guide"),
        W.CardItem("Theming", "Switch between light and dark themes using the toggle in the sidebar.", "Design"),
        W.CardItem("Interactions", "Click buttons, flip toggles, and watch the UI respond instantly.", "UX"),
        W.CardItem("Performance", "Every widget is compiled through the pvm pipeline with structural sharing.", "Tech"),
    }

    local avatars = {
        W.AvatarItem("AB", 210),
        W.AvatarItem("CD", 140),
        W.AvatarItem("EF", 30),
        W.AvatarItem("GH", 270),
        W.AvatarItem("IJ", 60),
        W.AvatarItem("KL", 180),
    }

    local tooltips = {
        W.TooltipItem("Hover me", "This is a helpful tooltip"),
        W.TooltipItem("Settings", "Configure application preferences"),
        W.TooltipItem("Save", "Save current changes"),
        W.TooltipItem("Delete", "Remove this item permanently"),
    }

    return W.App(
        W.ThemeDark,
        W.Buttons,
        W.Home,
        toggles,
        sliders,
        text_inputs,
        progresses,
        badges,
        alerts,
        cards,
        avatars,
        tooltips,
        0
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
        scrolls = {
            T.Solve.Scroll(CONTENT_SCROLL_ID, 0, 0),
        },
    }
    return W.State(app, clamp_ui_model(ui_model))
end

function M.event_from_ui(ui_event)
    local cls = pvm.classof(ui_event)

    if cls == T.Interact.Activate then
        local id = ui_event.id
        if id == nil or id == Core.NoId then return nil end
        local value = id.value

        if value == "theme:toggle" then
            return W.ToggleTheme
        end

        local section_map = {
            ["nav:buttons"] = W.Buttons,
            ["nav:toggles"] = W.Toggles,
            ["nav:text-inputs"] = W.TextInputs,
            ["nav:sliders"] = W.Sliders,
            ["nav:progress"] = W.ProgressBars,
            ["nav:badges"] = W.Badges,
            ["nav:cards"] = W.Cards,
            ["nav:alerts"] = W.Alerts,
            ["nav:tabs"] = W.Tabs,
            ["nav:avatars"] = W.Avatars,
            ["nav:tooltips"] = W.Tooltips,
        }
        if section_map[value] then
            return W.SetSection(section_map[value])
        end

        local tab_map = {
            ["tab:home"] = W.Home,
            ["tab:profile"] = W.Profile,
            ["tab:settings"] = W.Settings,
            ["tab:notifications"] = W.Notifications,
        }
        if tab_map[value] then
            return W.SetTab(tab_map[value])
        end

        local toggle_i = string.match(value, "^toggle:(%d+)$")
        if toggle_i then
            return W.FlipToggle(tonumber(toggle_i))
        end

        local slider_idx, slider_val = string.match(value, "^slider:(%d+):(.+)$")
        if slider_idx then
            return W.SlideTo(tonumber(slider_idx), tonumber(slider_val))
        end
    end

    return nil
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

M.CONTENT_SCROLL_ID = CONTENT_SCROLL_ID

return M
