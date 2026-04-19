local ui_asdl = require("ui.asdl")
local ui_text_field = require("ui.text_field")
local text_field_view = require("ui.text_field_view")
local b = require("ui.build")
local tw = require("ui.tw")

local T = ui_asdl.T

local M = {}

local function copy_table(src)
    local out = {}
    if src ~= nil then
        for k, v in pairs(src) do
            out[k] = v
        end
    end
    return out
end

local function require_id(opts, level)
    local id = opts and opts.id or nil
    if id == nil then
        error("text widget requires opts.id", level or 3)
    end
    return id
end

local function merge_style_value(items, value)
    if value ~= nil and value ~= false then
        items[#items + 1] = value
    end
end

function M.find_hit_box(report, id)
    if report == nil or report.hits == nil then return nil end
    for i = 1, #report.hits do
        local hit = report.hits[i]
        if hit.id == id then return hit end
    end
    return nil
end

function M.build_shell(opts, defaults)
    opts = opts or {}
    defaults = defaults or {}

    local id = require_id(opts, 3)
    local gap_y = opts.gap_y or defaults.gap_y or 8
    local min_h = opts.min_h or defaults.min_h

    local field_box_items = {
        b.id(id.value .. ":field"),
        tw.w_full,
    }
    if min_h ~= nil then
        field_box_items[#field_box_items + 1] = tw.min_h_px(min_h)
    end
    merge_style_value(field_box_items, defaults.field_styles)
    merge_style_value(field_box_items, opts.field_styles)

    local wrapper_items = {
        tw.flow,
        tw.gap_y(gap_y),
    }
    merge_style_value(wrapper_items, defaults.styles)
    merge_style_value(wrapper_items, opts.styles)

    if opts.label ~= nil and opts.label ~= "" then
        wrapper_items[#wrapper_items + 1] = b.text {
            b.id(id.value .. ":label"),
            defaults.label_styles,
            opts.label_styles,
            opts.label,
        }
    end

    if opts.field_node ~= nil then
        wrapper_items[#wrapper_items + 1] = opts.field_node
    else
        wrapper_items[#wrapper_items + 1] = b.with_input(id, T.Interact.EditTarget,
            b.box(field_box_items))
    end

    return b.box(wrapper_items)
end

local function default_placeholder_style(placeholder, base, opts)
    return T.Layout.TextStyle(
        base.font_id,
        base.font_size,
        base.font_weight,
        opts.placeholder_rgba8 or 0x94a3b8ff,
        base.align,
        base.leading,
        base.tracking,
        placeholder
    )
end

local function placeholder_active(field, opts)
    local placeholder = opts.placeholder
    return placeholder ~= nil and placeholder ~= ""
       and ui_text_field.text(field) == ""
       and field.composition_text == ""
end

local function overlay_opts_for_hit(hit, opts)
    local out = copy_table(opts)
    out.x = hit.x
    out.y = hit.y
    out.w = hit.w
    out.h = hit.h
    return out
end

local function draw_placeholder(host, field, hit, opts, resolved)
    if not placeholder_active(field, opts) then return end

    local overlay_opts = overlay_opts_for_hit(hit, opts)
    local base_style = resolved.text_style or (overlay_opts.text_style and overlay_opts.text_style(field, overlay_opts))
    if base_style == nil then return end

    local placeholder = opts.placeholder
    local style
    if opts.placeholder_style ~= nil then
        style = opts.placeholder_style(placeholder, base_style, field, overlay_opts)
    else
        style = default_placeholder_style(placeholder, base_style, overlay_opts)
    end

    local placeholder_field = ui_text_field.state(placeholder, 0, 0, {
        focused = false,
    })

    local placeholder_opts = copy_table(overlay_opts)
    placeholder_opts.text_style = function()
        return style
    end
    placeholder_opts.show_caret = false
    placeholder_opts.apply_text_input_rect = false
    placeholder_opts.bg_rgba8 = nil
    placeholder_opts.border_rgba8 = nil
    placeholder_opts.focus_border_rgba8 = nil
    placeholder_opts.selection_opacity = 0
    placeholder_opts.selection_rgba8 = 0x00000000
    placeholder_opts.composition_rgba8 = 0x00000000
    placeholder_opts.composition_underline_rgba8 = 0x00000000

    local placeholder_resolved = text_field_view.resolve(host, placeholder_field, placeholder_opts)
    text_field_view.draw(host, placeholder_field, placeholder_resolved, placeholder_opts)
end

function M.draw_overlay(host, report, field, opts)
    opts = opts or {}
    local id = require_id(opts, 3)
    local hit = M.find_hit_box(report, id)
    if hit == nil then return nil end

    local overlay_opts = overlay_opts_for_hit(hit, opts)
    local resolved = text_field_view.resolve(host, field, overlay_opts)
    draw_placeholder(host, field, hit, overlay_opts, resolved)
    text_field_view.draw(host, field, resolved, overlay_opts)

    return {
        id = id,
        hit = hit,
        resolved = resolved,
        placeholder = placeholder_active(field, overlay_opts),
    }
end

function M.contains(result, x, y)
    if result == nil or result.resolved == nil then return false end
    return text_field_view.contains(result.resolved, x, y)
end

function M.local_point(result, x, y)
    if result == nil or result.resolved == nil then return nil, nil end
    return text_field_view.local_point(result.resolved, x, y)
end

M.T = T

return M
