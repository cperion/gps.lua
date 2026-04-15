local pvm = require("pvm")
local ui = require("ui")
local demo_asdl = require("demo_asdl")
local demo_apply = require("demo_apply")

local T = demo_asdl.T
local F = T:FastBuilders()
local W = T.Widget
local Core = T.Core
local tw = ui.tw
local b = ui.build
local paint = ui.paint

local CONTENT_SCROLL_ID = demo_apply.CONTENT_SCROLL_ID
local SIDEBAR_W = 240

local M = {}

-- ── Shadcn-inspired Colors ─────────────────────────────────────────────

local hex = {
    slate = {
        [50]  = 0xf8fafcff, [100] = 0xf1f5f9ff, [200] = 0xe2e8f0ff,
        [300] = 0xcbd5e1ff, [400] = 0x94a3b8ff, [500] = 0x64748bff,
        [600] = 0x475569ff, [700] = 0x334155ff, [800] = 0x1e293bff,
        [900] = 0x0f172aff, [950] = 0x020617ff,
    },
    red = {
        [50]  = 0xfef2f2ff, [500] = 0xef4444ff,
        [600] = 0xdc2626ff, [800] = 0x991b1bff, [900] = 0x7f1d1dff,
    },
    white = 0xffffffff, black = 0x000000ff,
}

local function ctx_from_state(state)
    local mode = state.app.theme_mode
    local ui_model = state.ui_model
    local hover_val = (ui_model.hover_id ~= Core.NoId) and ui_model.hover_id.value or nil
    local focus_val = (ui_model.focus_id ~= Core.NoId) and ui_model.focus_id.value or nil

    return {
        mode = mode,
        is_dark = mode == W.ThemeDark,
        is_hovered = function(id_str)
            return hover_val == id_str or hover_val == id_str .. ":frame" or hover_val == id_str .. ":field" or hover_val == id_str .. ":row"
        end,
        is_focused = function(id_str)
            return focus_val == id_str or focus_val == id_str .. ":frame" or focus_val == id_str .. ":field" or focus_val == id_str .. ":row"
        end
    }
end

local function fg_main(ctx)    return ctx.is_dark and tw.fg.slate[50]  or tw.fg.slate[950] end
local function fg_muted(ctx)   return ctx.is_dark and tw.fg.slate[400] or tw.fg.slate[500] end
local function fg_primary(ctx) return ctx.is_dark and tw.fg.slate[900] or tw.fg.slate[50] end

local function bg_background(ctx) return ctx.is_dark and tw.bg.slate[950]  or tw.bg.white end
local function bg_surface(ctx)    return ctx.is_dark and tw.bg.slate[950]  or tw.bg.white end
local function bg_muted(ctx)      return ctx.is_dark and tw.bg.slate[800]  or tw.bg.slate[100] end
local function bg_muted_hover(ctx)return ctx.is_dark and tw.bg.slate[700]  or tw.bg.slate[200] end

local function bg_primary(ctx)    return ctx.is_dark and tw.bg.slate[50]   or tw.bg.slate[900] end
local function bg_primary_hover(ctx) return ctx.is_dark and tw.bg.slate[200] or tw.bg.slate[800] end

local function border_subtle(ctx) return ctx.is_dark and tw.border_color.slate[800] or tw.border_color.slate[200] end
local function border_strong(ctx) return ctx.is_dark and tw.border_color.slate[700] or tw.border_color.slate[300] end
local function border_focus(ctx)  return ctx.is_dark and tw.border_color.slate[400] or tw.border_color.slate[900] end

local function hex_primary(ctx) return ctx.is_dark and hex.slate[50] or hex.slate[900] end
local function hex_muted(ctx) return ctx.is_dark and hex.slate[800] or hex.slate[200] end
local function hex_background(ctx) return ctx.is_dark and hex.slate[950] or hex.white end
local function hex_border(ctx) return ctx.is_dark and hex.slate[800] or hex.slate[200] end
local function hex_border_focus(ctx) return ctx.is_dark and hex.slate[400] or hex.slate[900] end

-- ── Micro-Widgets ──────────────────────────────────────────────────────

local function section_title(ctx, title, subtitle)
    return b.box {
        tw.flow, tw.gap_y_1, tw.mb_6,
        b.text { tw.text_2xl, tw.font_semibold, tw.tracking_tight, fg_main(ctx), title },
        subtitle and b.text { tw.text_sm, fg_muted(ctx), subtitle } or nil,
    }
end

local function label(ctx, text)
    return b.text { tw.text_sm, tw.font_medium, tw.leading_none, fg_main(ctx), text }
end

local function description(ctx, text)
    return b.text { tw.text_sm, fg_muted(ctx), text }
end

local function ui_button(ctx, id, text, variant, size)
    local is_hov = ctx.is_hovered(id)
    local is_foc = ctx.is_focused(id)

    local bg, fg, border
    if variant == "primary" then
        bg = is_hov and bg_primary_hover(ctx) or bg_primary(ctx)
        fg = fg_primary(ctx)
    elseif variant == "secondary" then
        bg = is_hov and bg_muted_hover(ctx) or bg_muted(ctx)
        fg = fg_main(ctx)
    elseif variant == "outline" then
        bg = is_hov and bg_muted(ctx) or nil
        fg = fg_main(ctx)
        border = border_subtle(ctx)
    elseif variant == "ghost" then
        bg = is_hov and bg_muted(ctx) or nil
        fg = fg_main(ctx)
    elseif variant == "destructive" then
        bg = is_hov and (ctx.is_dark and tw.bg.red[800] or tw.bg.red[800]) or (ctx.is_dark and tw.bg.red[900] or tw.bg.red[600])
        fg = tw.fg.white
    end

    local px, py, text_size, rounded = tw.px_4, tw.py_2, tw.text_sm, tw.rounded_md
    if size == "sm" then
        px, py, text_size = tw.px_3, tw.py_1, tw.text_xs
    elseif size == "lg" then
        px, py, text_size = tw.px_8, tw.py_3, tw.text_base
    elseif size == "icon" then
        px, py, text_size, rounded = tw.w_px(40), tw.h_px(40), tw.text_lg, tw.rounded_md
    end

    local label_node
    if size == "icon" then
        label_node = b.text { tw.text_lg, tw.font_medium, fg, text }
    else
        label_node = b.text { text_size, tw.font_medium, fg, text }
    end

    return b.with_input(b.id(id), T.Interact.ActivateTarget,
        b.box {
            b.id(id .. ":frame"),
            tw.flex, tw.row, tw.items_center, tw.justify_center,
            px, py, rounded,
            tw.cursor_pointer,
            bg,
            border and tw.border_1 or nil,
            border,
            is_foc and tw.border_2 or nil,
            is_foc and border_focus(ctx) or nil,
            label_node,
        })
end

local function ui_switch(ctx, id, is_on)
    local is_hov = ctx.is_hovered(id)
    local is_foc = ctx.is_focused(id)
    
    local track_c = is_on and hex_primary(ctx) or hex_muted(ctx)
    local knob_c = hex_background(ctx)
    
    local w, h = 44, 24
    local knob_r = 10
    local knob_x = is_on and (w - knob_r*2 - 2) or 2
    local knob_cy = h * 0.5

    local ring = is_foc and paint.circle(w*0.5, h*0.5, w*0.5+4, nil, paint.stroke(hex_border_focus(ctx), 2)) or nil

    local p = b.paint {
        tw.w_px(w), tw.h_px(h),
        paint.circle(h*0.5, h*0.5, h*0.5, paint.fill(track_c), nil),
        paint.circle(w - h*0.5, h*0.5, h*0.5, paint.fill(track_c), nil),
        paint.polygon({h*0.5, 0, w - h*0.5, 0, w - h*0.5, h, h*0.5, h}, paint.fill(track_c), nil),
        paint.circle(knob_x + knob_r, knob_cy, knob_r, paint.fill(knob_c), nil),
        ring
    }
    
    return b.with_input(b.id(id), T.Interact.ActivateTarget,
        b.box { b.id(id..":frame"), tw.cursor_pointer, p })
end

local function ui_text_input(ctx, id, value, placeholder)
    local is_hov = ctx.is_hovered(id)
    local is_foc = ctx.is_focused(id)
    local has_value = #value > 0

    return b.with_input(b.id(id), T.Interact.EditTarget,
        b.box {
            b.id(id..":field"),
            tw.flex, tw.row, tw.items_center,
            tw.w_full, tw.px_3, tw.py_2,
            tw.rounded_md, tw.border_1,
            is_foc and border_focus(ctx) or border_subtle(ctx),
            bg_background(ctx),
            tw.cursor_text,
            b.text { tw.text_sm, has_value and fg_main(ctx) or fg_muted(ctx), has_value and value or placeholder }
        })
end

local function ui_slider(ctx, id, value, w)
    w = w or 300
    local h = 20
    local track_h = 6
    local track_bg = hex_muted(ctx)
    local track_fg = hex_primary(ctx)
    
    local fill_w = math.floor(value * w)
    local knob_r = 10
    local knob_cx = fill_w
    if knob_cx < knob_r then knob_cx = knob_r end
    if knob_cx > w - knob_r then knob_cx = w - knob_r end
    
    return b.box {
        tw.flex, tw.row, tw.items_center,
        b.paint {
            tw.w_px(w), tw.h_px(h),
            paint.line(0, h*0.5, w, h*0.5, paint.stroke(track_bg, track_h)),
            paint.line(0, h*0.5, fill_w, h*0.5, paint.stroke(track_fg, track_h)),
            paint.circle(knob_cx, h*0.5, knob_r, paint.fill(hex_background(ctx)), paint.stroke(hex_border_focus(ctx), 2)),
        }
    }
end

local function ui_progress(ctx, fraction, w)
    w = w or 300
    local h = 8
    local fill_w = math.floor(fraction * w)
    
    return b.paint {
        tw.w_px(w), tw.h_px(h),
        paint.line(0, h*0.5, w, h*0.5, paint.stroke(hex_muted(ctx), h)),
        fill_w > 0 and paint.line(0, h*0.5, fill_w, h*0.5, paint.stroke(hex_primary(ctx), h)) or nil,
    }
end

local function ui_badge(ctx, label_text, variant)
    local bg, fg, border
    if variant == "primary" then
        bg = ctx.is_dark and tw.bg.slate[50] or tw.bg.slate[900]
        fg = ctx.is_dark and tw.fg.slate[900] or tw.fg.slate[50]
        border = nil
    elseif variant == "secondary" then
        bg = ctx.is_dark and tw.bg.slate[800] or tw.bg.slate[100]
        fg = ctx.is_dark and tw.fg.slate[50] or tw.fg.slate[900]
        border = nil
    elseif variant == "destructive" then
        bg = ctx.is_dark and tw.bg.red[900] or tw.bg.red[500]
        fg = tw.fg.white
        border = nil
    elseif variant == "outline" then
        bg = nil
        fg = fg_main(ctx)
        border = border_subtle(ctx)
    end

    return b.box {
        tw.flex, tw.row, tw.items_center,
        tw.px_2_5, tw.py_0_5, tw.rounded_full,
        bg, border and tw.border_1 or nil, border,
        b.text { tw.text_xs, tw.font_semibold, fg, label_text }
    }
end

-- ── Gallery Sections (Returning Auth.Node) ─────────────────────────────

local function section_buttons(ctx)
    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Buttons", "Displays a button or a component that looks like a button."),
        b.box { tw.flow, tw.gap_y_4, label(ctx, "Variants"),
            b.box { tw.flex, tw.row, tw.wrap, tw.gap_4,
                ui_button(ctx, "btn:primary", "Primary", "primary"),
                ui_button(ctx, "btn:secondary", "Secondary", "secondary"),
                ui_button(ctx, "btn:outline", "Outline", "outline"),
                ui_button(ctx, "btn:ghost", "Ghost", "ghost"),
                ui_button(ctx, "btn:danger", "Destructive", "destructive"),
            }
        },
        b.box { tw.flow, tw.gap_y_4, label(ctx, "Sizes"),
            b.box { tw.flex, tw.row, tw.wrap, tw.gap_4, tw.items_center,
                ui_button(ctx, "btn:sm", "Small", "primary", "sm"),
                ui_button(ctx, "btn:md", "Default", "primary", "md"),
                ui_button(ctx, "btn:lg", "Large", "primary", "lg"),
                ui_button(ctx, "btn:icon1", "+", "outline", "icon"),
            }
        }
    }
end

local function section_toggles(ctx, toggles)
    local rows = {}
    for i = 1, #toggles do
        local t = toggles[i]
        local is_on = t.state == W.On
        rows[i] = b.box {
            tw.flex, tw.row, tw.items_center, tw.justify_between,
            tw.w_full, tw.p_4, tw.rounded_xl, tw.border_1, border_subtle(ctx), bg_surface(ctx),
            b.box { tw.flow, tw.gap_y_1, label(ctx, t.label), description(ctx, "Manage " .. string.lower(t.label) .. " settings.") },
            ui_switch(ctx, "toggle:" .. i, is_on)
        }
    end
    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Switches", "A control that allows the user to toggle between checked and not checked."),
        b.box { tw.flow, tw.gap_y_3, b.fragment(rows) }
    }
end

local function section_text_inputs(ctx, text_inputs)
    local rows = {}
    for i = 1, #text_inputs do
        local t = text_inputs[i]
        rows[i] = b.box {
            tw.flow, tw.gap_y_2, tw.w_full,
            label(ctx, t.label),
            ui_text_input(ctx, "text-input:" .. i, t.value, t.placeholder),
            description(ctx, "Enter your " .. string.lower(t.label) .. " here."),
        }
    end
    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Inputs", "Displays a form input field or a component that looks like an input field."),
        b.box { tw.flow, tw.gap_y_6, b.fragment(rows) }
    }
end

local function section_sliders(ctx, sliders)
    local rows = {}
    for i = 1, #sliders do
        local s = sliders[i]
        rows[i] = b.box {
            tw.flow, tw.gap_y_4, tw.w_full,
            b.box { tw.flex, tw.row, tw.justify_between, label(ctx, s.label), b.text { tw.text_sm, tw.font_medium, fg_muted(ctx), string.format("%.0f%%", s.value * 100) } },
            ui_slider(ctx, "slider:" .. i, s.value, 400),
        }
    end
    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Sliders", "An input where the user selects a value from within a given range."),
        b.box { tw.flow, tw.gap_y_8, b.fragment(rows) }
    }
end

local function section_progress(ctx, progresses)
    local rows = {}
    for i = 1, #progresses do
        local p = progresses[i]
        local pct = math.floor(p.fraction * 100 + 0.5)
        rows[i] = b.box {
            tw.flow, tw.gap_y_2, tw.w_full,
            b.box { tw.flex, tw.row, tw.justify_between, label(ctx, p.label), b.text { tw.text_sm, tw.font_medium, fg_muted(ctx), pct .. "%" } },
            ui_progress(ctx, p.fraction, 400),
        }
    end
    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Progress", "Displays an indicator showing the completion progress of a task."),
        b.box { tw.flow, tw.gap_y_8, b.fragment(rows) }
    }
end

local function section_badges(ctx, badges)
    local badge_rows = {}
    for i = 1, #badges do
        local badge = badges[i]
        local variant = "secondary"
        if badge.tone == W.BadgePrimary then variant = "primary"
        elseif badge.tone == W.BadgeSuccess then variant = "outline"
        elseif badge.tone == W.BadgeWarning then variant = "outline"
        elseif badge.tone == W.BadgeError then variant = "destructive"
        end
        badge_rows[i] = ui_badge(ctx, badge.label, variant)
    end
    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Badges", "Displays a badge or a component that looks like a badge."),
        b.box { tw.flex, tw.row, tw.wrap, tw.gap_3, b.fragment(badge_rows) }
    }
end

local function section_cards(ctx, cards)
    local grid = {}
    for i = 1, #cards do
        local c = cards[i]
        grid[i] = b.box {
            tw.flow, tw.w_px(300), tw.p_6,
            tw.rounded_xl, tw.border_1, border_subtle(ctx), bg_surface(ctx),
            b.box { tw.flow, tw.gap_y_1_5, tw.mb_4,
                b.text { tw.text_lg, tw.font_semibold, tw.leading_none, tw.tracking_tight, fg_main(ctx), c.title },
                b.text { tw.text_sm, fg_muted(ctx), c.body },
            },
            ui_button(ctx, "card_btn:"..i, c.meta, "outline", "sm")
        }
    end
    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Cards", "Displays a card with header, content, and footer."),
        b.box { tw.flex, tw.row, tw.wrap, tw.gap_6, b.fragment(grid) }
    }
end

local function section_alerts(ctx, alerts)
    local rows = {}
    for i = 1, #alerts do
        local a = alerts[i]
        local is_dest = a.tone == W.AlertError
        local border_c = is_dest and (ctx.is_dark and tw.border_color.red[900] or tw.border_color.red[500]) or border_subtle(ctx)
        local bg_c = is_dest and (ctx.is_dark and tw.bg.red[950] or tw.bg.white) or bg_surface(ctx)
        local text_c = is_dest and (ctx.is_dark and tw.fg.red[50] or tw.fg.red[600]) or fg_main(ctx)
        
        rows[i] = b.box {
            tw.flow, tw.w_full, tw.p_4, tw.rounded_lg, tw.border_1, border_c, bg_c,
            b.box { tw.flow, tw.gap_y_1,
                b.text { tw.text_sm, tw.font_medium, tw.leading_none, tw.tracking_tight, text_c, a.title },
                b.text { tw.text_sm, is_dest and text_c or fg_muted(ctx), a.body },
            }
        }
    end
    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Alerts", "Displays a callout for user attention."),
        b.box { tw.flow, tw.gap_y_4, b.fragment(rows) }
    }
end

local function section_tabs(ctx, active_tab)
    local tabs = {
        { id = "tab:home",          label = "Home",          kind = W.Home },
        { id = "tab:profile",       label = "Profile",       kind = W.Profile },
        { id = "tab:settings",      label = "Settings",      kind = W.Settings },
        { id = "tab:notifications", label = "Notifications", kind = W.Notifications },
    }

    local tab_bar = b.box {
        tw.flex, tw.row, tw.gap_1, tw.p_1, tw.rounded_lg, bg_muted(ctx),
        b.fragment(tab_items)
    }
    local tab_items = {}
    for i = 1, #tabs do
        local t = tabs[i]
        local is_active = active_tab == t.kind
        tab_items[i] = b.with_input(b.id(t.id), T.Interact.ActivateTarget,
            b.box {
                b.id(t.id .. ":tab"), tw.flex, tw.row, tw.items_center, tw.justify_center,
                tw.px_3, tw.py_1_5, tw.rounded_md, tw.cursor_pointer, is_active and bg_surface(ctx) or nil,
                b.text { tw.text_sm, tw.font_medium, is_active and fg_main(ctx) or fg_muted(ctx), t.label },
            })
    end

    local content_title, content_body = "", ""
    if active_tab == W.Home then
        content_title, content_body = "Home", "Make changes to your dashboard here."
    elseif active_tab == W.Profile then
        content_title, content_body = "Profile", "Manage your account settings."
    elseif active_tab == W.Settings then
        content_title, content_body = "Settings", "Configure preferences."
    else
        content_title, content_body = "Notifications", "Choose what updates you want to receive."
    end

    local tab_content = b.box {
        tw.flow, tw.mt_2, tw.p_6, tw.w_full, tw.rounded_xl, tw.border_1, border_subtle(ctx), bg_surface(ctx),
        b.box { tw.flow, tw.gap_y_1_5, tw.mb_6,
            b.text { tw.text_lg, tw.font_semibold, tw.leading_none, tw.tracking_tight, fg_main(ctx), content_title },
            description(ctx, content_body),
        },
        ui_button(ctx, "tab_save", "Save changes", "primary", "sm")
    }

    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Tabs", "A set of layered sections of content."),
        b.box { tw.flow, tw.gap_y_3, tab_bar, tab_content }
    }
end

local function section_avatars(ctx, avatars)
    local sizes = { 32, 40, 48, 56, 64 }
    local size_items = {}
    for i = 1, #sizes do
        size_items[i] = b.box {
            tw.flex, tw.row, tw.items_center, tw.justify_center,
            tw.w_px(sizes[i]), tw.h_px(sizes[i]), tw.rounded_full, bg_muted(ctx),
            b.text { tw.text_sm, tw.font_medium, fg_main(ctx), "AB" }
        }
    end

    local color_items = {}
    for i = 1, #avatars do
        local a = avatars[i]
        color_items[i] = b.box {
            tw.flex, tw.row, tw.items_center, tw.justify_center,
            tw.w_px(48), tw.h_px(48), tw.rounded_full, tw.border_1, border_subtle(ctx), bg_surface(ctx),
            b.text { tw.text_sm, tw.font_medium, fg_main(ctx), a.initials }
        }
    end

    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Avatar", "An image element with a fallback for representing the user."),
        b.box { tw.flow, tw.gap_y_4, label(ctx, "Sizes"), b.box { tw.flex, tw.row, tw.gap_4, tw.items_end, b.fragment(size_items) } },
        b.box { tw.flow, tw.gap_y_4, label(ctx, "Fallbacks"), b.box { tw.flex, tw.row, tw.gap_4, tw.items_end, b.fragment(color_items) } }
    }
end

local function section_tooltips(ctx, tooltips)
    local rows = {}
    for i = 1, #tooltips do
        local t = tooltips[i]
        rows[i] = b.box {
            tw.flow, tw.gap_y_2,
            ui_button(ctx, "tooltip_btn:"..i, t.label, "outline"),
            b.box {
                tw.flex, tw.row, tw.items_center, tw.px_3, tw.py_1_5,
                tw.rounded_md, ctx.is_dark and tw.bg.slate[50] or tw.bg.slate[900],
                b.text { tw.text_xs, tw.font_medium, ctx.is_dark and tw.fg.slate[900] or tw.fg.slate[50], t.tip }
            }
        }
    end
    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Tooltip", "A popup that displays information related to an element."),
        b.box { tw.flex, tw.row, tw.wrap, tw.gap_8, b.fragment(rows) }
    }
end

local function build_section(ctx, app)
    local section = app.section
    if section == W.Buttons then      return section_buttons(ctx) end
    if section == W.Toggles then      return section_toggles(ctx, app.toggles) end
    if section == W.TextInputs then   return section_text_inputs(ctx, app.text_inputs) end
    if section == W.Sliders then      return section_sliders(ctx, app.sliders) end
    if section == W.ProgressBars then return section_progress(ctx, app.progresses) end
    if section == W.Badges then       return section_badges(ctx, app.badges) end
    if section == W.Cards then        return section_cards(ctx, app.cards) end
    if section == W.Alerts then       return section_alerts(ctx, app.alerts) end
    if section == W.Tabs then         return section_tabs(ctx, app.tab) end
    if section == W.Avatars then      return section_avatars(ctx, app.avatars) end
    if section == W.Tooltips then     return section_tooltips(ctx, app.tooltips) end
    return section_buttons(ctx)
end

-- ── Shell / Layout ─────────────────────────────────────────────────────

local NAV_ITEMS = {
    { id = "nav:buttons",      label = "Buttons",       section = W.Buttons },
    { id = "nav:toggles",      label = "Switches",      section = W.Toggles },
    { id = "nav:text-inputs",  label = "Inputs",        section = W.TextInputs },
    { id = "nav:sliders",      label = "Sliders",       section = W.Sliders },
    { id = "nav:progress",     label = "Progress",      section = W.ProgressBars },
    { id = "nav:badges",       label = "Badges",        section = W.Badges },
    { id = "nav:cards",        label = "Cards",         section = W.Cards },
    { id = "nav:alerts",       label = "Alerts",        section = W.Alerts },
    { id = "nav:tabs",         label = "Tabs",          section = W.Tabs },
    { id = "nav:avatars",      label = "Avatars",       section = W.Avatars },
    { id = "nav:tooltips",     label = "Tooltips",      section = W.Tooltips },
}

local function build_sidebar(ctx, app)
    local nav_rows = {}
    for i = 1, #NAV_ITEMS do
        local item = NAV_ITEMS[i]
        local is_selected = app.section == item.section
        local is_hov = ctx.is_hovered(item.id)
        
        local bg = is_selected and bg_muted(ctx) or (is_hov and bg_muted_hover(ctx) or nil)
        local fg = (is_selected or is_hov) and fg_main(ctx) or fg_muted(ctx)
        
        nav_rows[i] = b.with_input(b.id(item.id), T.Interact.ActivateTarget,
            b.box {
                b.id(item.id .. ":row"), tw.flex, tw.row, tw.items_center,
                tw.w_full, tw.px_3, tw.py_2, tw.rounded_md, tw.cursor_pointer,
                bg,
                b.text { tw.text_sm, tw.font_medium, fg, item.label },
            })
    end

    return F.Compose.Raw {
        child = b.box {
            tw.flex, tw.col,
            tw.h_full,
            tw.gap_y_8,
            b.box {
                tw.flow, tw.px_2,
                b.text { tw.text_lg, tw.font_semibold, tw.tracking_tight, fg_main(ctx), "shadcn/ui" },
                b.text { tw.text_xs, fg_muted(ctx), "Widget Gallery" },
            },
            b.box { tw.flow, tw.gap_y_1, b.fragment(nav_rows) },
            b.box { tw.grow_1, tw.basis_px(0), tw.min_h_px(0) },
            b.box { tw.w_full, tw.px_2, ui_button(ctx, "theme:toggle", ctx.is_dark and "Light Mode" or "Dark Mode", "outline", "sm") }
        }
    }
end

function M.compose_root(state, vw, vh)
    local ctx = ctx_from_state(state)
    
    return F.Compose.Workbench {
        id = b.id("root"),
        styles = tw.list {
            tw.w_px(vw), tw.h_px(vh),
            bg_background(ctx),
            tw.fg.slate[950],
        },
        
        left = build_sidebar(ctx, state.app),
        left_styles = tw.list {
            tw.w_px(SIDEBAR_W),
            tw.px_4, tw.py_6,
            tw.border_r_1, border_subtle(ctx),
        },
        
        center = F.Compose.ScrollPanel {
            id = b.id("main-panel"),
            styles = tw.list { tw.grow_1, tw.basis_px(0), tw.min_h_px(0) },
            scroll_id = CONTENT_SCROLL_ID,
            axis = T.Style.ScrollY,
            body_styles = tw.list { tw.flex, tw.row, tw.justify_center, tw.w_full },
            body = F.Compose.Raw {
                child = b.box {
                    tw.w_full, tw.max_w_px(800),
                    tw.py_10, tw.px_8,
                    build_section(ctx, state.app)
                }
            }
        }
    }
end

M.auth_root = M.compose_root

return M
