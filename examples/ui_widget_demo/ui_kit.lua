local ui = require("ui")
local ds = require("ds")

local T = ui.T
local tw = ui.tw
local b = ui.build

local M = {}

local function id_value(v, suffix)
    if v == nil then return nil end
    if suffix then return b.id(v .. suffix) end
    return b.id(v)
end

local function style_state(opts)
    opts = opts or {}
    return tw.state {
        hovered = opts.hovered,
        focused = opts.focused,
        active = opts.active,
        selected = opts.selected,
        disabled = opts.disabled,
    }
end

local function with_state_and_input(state, id, role, disabled, child)
    if id and not disabled then
        child = b.with_input(id_value(id), role, child)
    end
    return b.with_state(state or tw.no_state, child)
end

local function scalar_text(v)
    if v == nil or v == false then return nil end
    if type(v) == "string" or type(v) == "number" then return tostring(v) end
    error("expected string, number, nil, or false", 3)
end

local function content_node(v, text_style)
    if v == nil or v == false then return nil end
    if type(v) == "string" or type(v) == "number" then
        return b.text { text_style or ds.text.body, tostring(v) }
    end
    return v
end

function M.SectionTitle(opts)
    opts = opts or {}
    return b.box {
        tw.flow,
        tw.gap_y_1,
        tw.mb_6,
        opts.styles,
        b.text { ds.text.section_title, opts.title or "" },
        opts.subtitle and b.text { ds.text.section_subtitle, opts.subtitle } or nil,
    }
end

function M.Label(opts)
    if type(opts) == "string" or type(opts) == "number" then
        opts = { text = tostring(opts) }
    else
        opts = opts or {}
    end
    return b.text {
        ds.text.label,
        opts.styles,
        opts.text or "",
    }
end

function M.Description(opts)
    if type(opts) == "string" or type(opts) == "number" then
        opts = { text = tostring(opts) }
    else
        opts = opts or {}
    end
    return b.text {
        ds.text.body,
        opts.styles,
        opts.text or "",
    }
end

function M.Button(opts)
    opts = opts or {}
    local variant = opts.variant or "primary"
    local size = opts.size or "md"
    local state = opts.state or style_state {
        selected = opts.selected,
        disabled = opts.disabled,
    }

    local frame = b.box {
        id_value(opts.id, ":frame"),
        ds.button.frame.base,
        ds.button.frame[size] or ds.button.frame.md,
        ds.button.frame[variant] or ds.button.frame.primary,
        ds.ring.focus,
        opts.block and tw.w_full or nil,
        opts.styles,
        b.text {
            ds.button.label.base,
            ds.button.label[size] or ds.button.label.md,
            ds.button.label[variant] or ds.button.label.primary,
            opts.label or "",
        }
    }

    return with_state_and_input(state, opts.id, T.Interact.ActivateTarget, opts.disabled, frame)
end

function M.Input(opts)
    opts = opts or {}
    local value = scalar_text(opts.value or "") or ""
    local placeholder = scalar_text(opts.placeholder or "") or ""
    local has_value = value ~= ""
    local state = opts.state or style_state {
        disabled = opts.disabled,
    }

    local frame = b.box {
        id_value(opts.id, ":field"),
        ds.input.frame.base,
        ds.ring.focus,
        opts.styles,
        b.text {
            has_value and ds.input.value.default or ds.input.placeholder.default,
            has_value and value or placeholder,
        }
    }

    return with_state_and_input(state, opts.id, T.Interact.EditTarget, opts.disabled, frame)
end

function M.Toolbar(opts)
    opts = opts or {}
    return b.box {
        ds.toolbar.frame,
        opts.inset and ds.toolbar.inset or nil,
        opts.styles,
        b.fragment(opts.children or {}),
    }
end

function M.Card(opts)
    opts = opts or {}
    local header = nil
    if opts.title or opts.subtitle then
        header = b.box {
            ds.card.header,
            b.text { ds.text.card_title, opts.title or "" },
            opts.subtitle and b.text { ds.text.body, opts.subtitle } or nil,
        }
    end

    local body = nil
    if opts.body then
        body = b.box {
            ds.card.body,
            content_node(opts.body, ds.text.body),
        }
    end

    local footer = nil
    if opts.footer then
        footer = b.box {
            ds.card.footer,
            content_node(opts.footer),
        }
    end

    return b.box {
        ds.card.frame,
        opts.styles,
        header,
        body,
        footer,
    }
end

function M.ListItem(opts)
    opts = opts or {}
    local state = opts.state or style_state {
        selected = opts.selected,
        disabled = opts.disabled,
    }

    local frame = b.box {
        id_value(opts.id, ":row"),
        ds.list_item.frame.base,
        opts.interactive == false and nil or ds.list_item.frame.interactive,
        opts.styles,
        b.box {
            tw.flow,
            tw.gap_y_0_5,
            tw.min_w_px(0),
            b.text { ds.list_item.title, opts.title or "" },
            opts.subtitle and b.text { ds.list_item.subtitle, opts.subtitle } or nil,
        },
        content_node(opts.trailing, ds.text.body)
    }

    if opts.interactive == false then
        return b.with_state(state, frame)
    end
    return with_state_and_input(state, opts.id, T.Interact.ActivateTarget, opts.disabled, frame)
end

M.state = style_state

return M
