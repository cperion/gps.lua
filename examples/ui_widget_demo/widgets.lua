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
local ds = require("ds")
local kit = require("ui_kit")

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

local function matches_interact_id(value, id_str)
    return value == id_str
        or value == id_str .. ":frame"
        or value == id_str .. ":field"
        or value == id_str .. ":row"
        or value == id_str .. ":tab"
end

local function ctx_from_state(state)
    local mode = state.app.theme_mode
    local ui_model = state.ui_model
    local hover_val = (ui_model.hover_id ~= Core.NoId) and ui_model.hover_id.value or nil
    local focus_val = (ui_model.focus_id ~= Core.NoId) and ui_model.focus_id.value or nil
    local pressed_val = (ui_model.pressed_id ~= Core.NoId) and ui_model.pressed_id.value or nil

    return {
        mode = mode,
        is_dark = mode == W.ThemeDark,
        is_hovered = function(id_str)
            return matches_interact_id(hover_val, id_str)
        end,
        is_focused = function(id_str)
            return matches_interact_id(focus_val, id_str)
        end,
        is_pressed = function(id_str)
            return matches_interact_id(pressed_val, id_str)
        end,
        state_for = function(id_str, opts)
            opts = opts or {}
            return tw.state {
                hovered = matches_interact_id(hover_val, id_str),
                focused = matches_interact_id(focus_val, id_str),
                active = matches_interact_id(pressed_val, id_str),
                selected = opts.selected,
                disabled = opts.disabled,
            }
        end,
    }
end

local function fg_main(ctx)      return ctx.is_dark and tw.fg.slate[50]   or tw.fg.slate[900] end
local function fg_muted(ctx)     return ctx.is_dark and tw.fg.slate[300]  or tw.fg.slate[500] end
local function fg_primary(ctx)   return tw.fg.white end
local function fg_accent(ctx)    return ctx.is_dark and tw.fg.violet[200] or tw.fg.violet[700] end

local function bg_background(ctx)    return ctx.is_dark and tw.bg.slate[950]   or tw.bg.violet[50] end
local function bg_surface(ctx)       return ctx.is_dark and tw.bg.slate[900]   or tw.bg.white end
local function bg_surface_soft(ctx)  return ctx.is_dark and tw.bg.slate[800]   or tw.bg.violet[100] end
local function bg_muted(ctx)         return ctx.is_dark and tw.bg.slate[800]   or tw.bg.violet[100] end
local function bg_muted_hover(ctx)   return ctx.is_dark and tw.bg.slate[700]   or tw.bg.violet[200] end
local function bg_primary(ctx)       return ctx.is_dark and tw.bg.violet[400]  or tw.bg.violet[500] end
local function bg_primary_hover(ctx) return ctx.is_dark and tw.bg.violet[300]  or tw.bg.violet[400] end
local function bg_primary_active(ctx)return ctx.is_dark and tw.bg.violet[200]  or tw.bg.violet[300] end
local function bg_accent_soft(ctx)   return ctx.is_dark and tw.bg.violet[950]  or tw.bg.pink[50] end
local function bg_info_soft(ctx)     return ctx.is_dark and tw.bg.sky[950]     or tw.bg.sky[50] end
local function bg_success_soft(ctx)  return ctx.is_dark and tw.bg.emerald[950] or tw.bg.emerald[50] end
local function bg_warning_soft(ctx)  return ctx.is_dark and tw.bg.amber[950]   or tw.bg.amber[50] end
local function bg_error_soft(ctx)    return ctx.is_dark and tw.bg.red[950]     or tw.bg.rose[50] end

local function border_subtle(ctx) return ctx.is_dark and tw.border_color.slate[700]  or tw.border_color.violet[200] end
local function border_strong(ctx) return ctx.is_dark and tw.border_color.slate[600]  or tw.border_color.violet[300] end
local function border_focus(ctx)  return ctx.is_dark and tw.border_color.violet[300] or tw.border_color.violet[500] end
local function border_info(ctx)   return ctx.is_dark and tw.border_color.sky[800]    or tw.border_color.sky[200] end
local function border_success(ctx)return ctx.is_dark and tw.border_color.emerald[800] or tw.border_color.emerald[200] end
local function border_warning(ctx)return ctx.is_dark and tw.border_color.amber[800]   or tw.border_color.amber[200] end
local function border_error(ctx)  return ctx.is_dark and tw.border_color.red[800]     or tw.border_color.rose[200] end

local function hex_primary(ctx)       return ctx.is_dark and 0xc4b5fdff or 0x8b5cf6ff end
local function hex_primary_hover(ctx) return ctx.is_dark and 0xddd6feff or 0xa78bfaff end
local function hex_muted(ctx)         return ctx.is_dark and hex.slate[700] or 0xe9d5ffff end
local function hex_background(ctx)    return ctx.is_dark and 0x0f172aff or 0xffffffff end
local function hex_border(ctx)        return ctx.is_dark and hex.slate[700] or 0xc4b5fdff end
local function hex_border_focus(ctx)  return ctx.is_dark and 0xc4b5fdff or 0x8b5cf6ff end

-- ── Micro-Widgets ──────────────────────────────────────────────────────

local function section_title(ctx, title, subtitle)
    return kit.SectionTitle {
        title = title,
        subtitle = subtitle,
    }
end

local function label(ctx, text)
    return kit.Label { text = text }
end

local function description(ctx, text)
    return kit.Description { text = text }
end

local function ui_button(ctx, id, text, variant, size)
    return kit.Button {
        id = id,
        label = text,
        variant = variant,
        size = size,
        state = ctx.state_for(id),
    }
end

local function ui_switch(ctx, id, is_on)
    local state = ctx.state_for(id)
    local is_hov = ctx.is_hovered(id)
    local is_foc = ctx.is_focused(id)
    local is_act = ctx.is_pressed(id)

    local track_c
    if is_on then
        track_c = is_act and hex_primary_hover(ctx) or hex_primary(ctx)
    else
        track_c = is_hov and hex_border(ctx) or hex_muted(ctx)
    end
    local knob_c = hex_background(ctx)

    local w, h = 48, 28
    local knob_r = 11
    local knob_x = is_on and (w - knob_r * 2 - 3) or 3
    if is_act then knob_x = knob_x + (is_on and -1 or 1) end
    local knob_cy = h * 0.5

    local ring = is_foc and paint.circle(w * 0.5, h * 0.5, w * 0.5 + 4, nil, paint.stroke(hex_border_focus(ctx), 2)) or nil

    local p = b.paint {
        tw.w_px(w), tw.h_px(h),
        paint.circle(h * 0.5, h * 0.5, h * 0.5, paint.fill(track_c), nil),
        paint.circle(w - h * 0.5, h * 0.5, h * 0.5, paint.fill(track_c), nil),
        paint.polygon({ h * 0.5, 0, w - h * 0.5, 0, w - h * 0.5, h, h * 0.5, h }, paint.fill(track_c), nil),
        paint.circle(knob_x + knob_r, knob_cy, knob_r, paint.fill(knob_c), paint.stroke(hex_border(ctx), 1)),
        ring
    }

    return b.with_state(state,
        b.with_input(b.id(id), T.Interact.ActivateTarget,
            b.box {
                b.id(id..":frame"),
                tw.p_1, tw.rounded_full, tw.cursor_pointer,
                tw.hover(bg_surface_soft(ctx)),
                tw.active(bg_muted(ctx)),
                p,
            }))
end

local function ui_text_input(ctx, id, value, placeholder)
    return kit.Input {
        id = id,
        value = value,
        placeholder = placeholder,
        state = ctx.state_for(id),
    }
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
        bg = ctx.is_dark and tw.bg.violet[400] or tw.bg.violet[500]
        fg = tw.fg.white
        border = nil
    elseif variant == "secondary" then
        bg = bg_surface_soft(ctx)
        fg = fg_main(ctx)
        border = border_subtle(ctx)
    elseif variant == "destructive" then
        bg = ctx.is_dark and tw.bg.rose[900] or tw.bg.rose[500]
        fg = tw.fg.white
        border = nil
    elseif variant == "outline" then
        bg = bg_accent_soft(ctx)
        fg = fg_accent(ctx)
        border = border_subtle(ctx)
    end

    return b.box {
        tw.flex, tw.row, tw.items_center,
        tw.px_2, tw.py_0_5, tw.rounded_md,
        bg,
        border and tw.border_1 or nil,
        border,
        b.text { tw.text_xs, tw.font_semibold, tw.leading_none, fg, label_text }
    }
end

-- ── Gallery Sections (Returning Auth.Node) ─────────────────────────────

local function section_buttons(ctx)
    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Buttons", "Displays a button or a component that looks like a button."),
        b.box { tw.flow, tw.gap_y_4, label(ctx, "Variants"),
            kit.Toolbar {
                styles = tw.gap_4,
                children = {
                    ui_button(ctx, "btn:primary", "Primary", "primary"),
                    ui_button(ctx, "btn:secondary", "Secondary", "secondary"),
                    ui_button(ctx, "btn:outline", "Outline", "outline"),
                    ui_button(ctx, "btn:ghost", "Ghost", "ghost"),
                    ui_button(ctx, "btn:danger", "Destructive", "destructive"),
                }
            }
        },
        b.box { tw.flow, tw.gap_y_4, label(ctx, "Sizes"),
            kit.Toolbar {
                styles = tw.gap_4,
                children = {
                    ui_button(ctx, "btn:sm", "Small", "primary", "sm"),
                    ui_button(ctx, "btn:md", "Default", "primary", "md"),
                    ui_button(ctx, "btn:lg", "Large", "primary", "lg"),
                    ui_button(ctx, "btn:icon1", "+", "outline", "icon"),
                }
            }
        }
    }
end

local function section_toggles(ctx, toggles)
    local rows = {}
    for i = 1, #toggles do
        local t = toggles[i]
        local is_on = t.state == W.On
        rows[i] = b.with_state(ctx.state_for("toggle:" .. i),
            b.box {
                tw.flex, tw.row, tw.items_center, tw.justify_between,
                tw.w_full, tw.p_4, tw.rounded_xl, tw.border_1, border_subtle(ctx), bg_surface(ctx),
                tw.hover(bg_surface_soft(ctx)),
                b.box { tw.flow, tw.gap_y_1, label(ctx, t.label), description(ctx, "Manage " .. string.lower(t.label) .. " settings.") },
                ui_switch(ctx, "toggle:" .. i, is_on)
            })
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
        grid[i] = kit.Card {
            styles = tw.w_px(300),
            title = c.title,
            subtitle = c.body,
            footer = kit.Toolbar {
                children = {
                    ui_button(ctx, "card_btn:" .. i, c.meta, "outline", "sm")
                }
            }
        }
    end
    return b.box {
        tw.flow, tw.w_full, tw.gap_y_8,
        section_title(ctx, "Cards", "Displays a card with header, content, and footer."),
        kit.Toolbar { styles = tw.gap_6, children = grid }
    }
end

local function section_alerts(ctx, alerts)
    local rows = {}
    for i = 1, #alerts do
        local a = alerts[i]
        local border_c, bg_c, text_c
        if a.tone == W.AlertInfo then
            border_c, bg_c, text_c = border_info(ctx), bg_info_soft(ctx), ctx.is_dark and tw.fg.sky[100] or tw.fg.sky[700]
        elseif a.tone == W.AlertSuccess then
            border_c, bg_c, text_c = border_success(ctx), bg_success_soft(ctx), ctx.is_dark and tw.fg.emerald[100] or tw.fg.emerald[700]
        elseif a.tone == W.AlertWarning then
            border_c, bg_c, text_c = border_warning(ctx), bg_warning_soft(ctx), ctx.is_dark and tw.fg.amber[100] or tw.fg.amber[700]
        else
            border_c, bg_c, text_c = border_error(ctx), bg_error_soft(ctx), ctx.is_dark and tw.fg.rose[100] or tw.fg.rose[700]
        end

        rows[i] = b.box {
            tw.flow, tw.w_full, tw.p_4, tw.rounded_lg, tw.border_1, border_c, bg_c,
            b.box { tw.flow, tw.gap_y_1,
                b.text { tw.text_sm, tw.font_medium, tw.leading_none, tw.tracking_tight, text_c, a.title },
                b.text { tw.text_sm, fg_muted(ctx), a.body },
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

    local tab_items = {}
    for i = 1, #tabs do
        local t = tabs[i]
        local is_active = active_tab == t.kind
        tab_items[i] = b.with_state(ctx.state_for(t.id, { selected = is_active }),
            b.with_input(b.id(t.id), T.Interact.ActivateTarget,
                b.box {
                    b.id(t.id .. ":tab"), tw.flex, tw.row, tw.items_center, tw.justify_center,
                    tw.px_3, tw.py_1_5, tw.rounded_md, tw.cursor_pointer,
                    tw.selected(bg_surface(ctx)),
                    tw.hover(bg_surface(ctx)),
                    tw.active(bg_surface(ctx)),
                    b.text {
                        tw.text_sm, tw.font_medium, fg_muted(ctx),
                        tw.selected(fg_main(ctx)),
                        tw.hover(fg_main(ctx)),
                        tw.active(fg_main(ctx)),
                        t.label
                    },
                }))
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

    local tab_bar = kit.Toolbar {
        inset = true,
        styles = tw.gap_1,
        children = tab_items,
    }

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
                tw.rounded_md, tw.border_1, border_subtle(ctx), bg_accent_soft(ctx),
                b.text { tw.text_xs, tw.font_medium, fg_accent(ctx), t.tip }
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

        nav_rows[i] = kit.ListItem {
            id = item.id,
            title = item.label,
            selected = is_selected,
            state = ctx.state_for(item.id, { selected = is_selected }),
        }
    end

    return F.Compose.Raw {
        child = b.box {
            tw.flex, tw.col,
            tw.h_full,
            tw.gap_y_8,
            b.box {
                tw.flow, tw.px_2,
                b.text { ds.text.brand_title, "petal/ui" },
                b.text { ds.text.brand_subtitle, "Cute Widget Garden" },
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
            ds.surface.app,
            tw.fg.slate[900],
            tw.dark(tw.fg.slate[100]),
        },
        
        left = build_sidebar(ctx, state.app),
        left_styles = tw.list {
            tw.w_px(SIDEBAR_W),
            tw.px_4, tw.py_6,
            ds.surface.panel_soft,
        },
        
        center = F.Compose.ScrollPanel {
            id = b.id("main-panel"),
            styles = tw.list { tw.grow_1, tw.basis_px(0), tw.min_h_px(0) },
            scroll_id = CONTENT_SCROLL_ID,
            axis = T.Style.ScrollY,
            body_styles = tw.list { tw.flex, tw.row, tw.justify_center, tw.w_full },
            body = F.Compose.Raw {
                child = b.box {
                    tw.w_full, tw.max_w_px(860),
                    tw.py_10, tw.px_8,
                    tw.rounded_3xl,
                    ds.surface.panel,
                    build_section(ctx, state.app)
                }
            }
        }
    }
end

M.auth_root = M.compose_root

return M
