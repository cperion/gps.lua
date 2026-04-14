local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local tw = require("ui.tw")
local b = require("ui.build")

local T = ui_asdl.T
local Auth = T.Auth

local M = {}

local function classof(v)
    return pvm.classof(v)
end

local function is_node(v)
    local cls = classof(v)
    return cls and Auth.Node.members[cls] or false
end

local function style_group(styles)
    if styles == nil or styles == false then return nil end
    if type(styles) == "table" and not classof(styles) then
        return tw.group(styles)
    end
    return styles
end

local function child_node(v)
    if v == nil or v == false then return nil end
    if is_node(v) then return v end
    if type(v) == "table" and not classof(v) then
        return b.fragment(v)
    end
    if type(v) == "string" or type(v) == "number" then
        return b.text { tostring(v) }
    end
    error("compose helpers expect authored nodes, node arrays, strings, numbers, nil, or false", 3)
end

local function section_box(default_styles, styles, content)
    local child = child_node(content)
    if child == nil then return nil end
    return b.box {
        default_styles and tw.group(default_styles) or nil,
        style_group(styles),
        child,
    }
end

function M.panel(opts)
    opts = opts or {}
    return b.box {
        opts.id,
        tw.flex, tw.col,
        style_group(opts.styles),
        section_box(opts.header_default_styles, opts.header_styles, opts.header),
        section_box(opts.body_default_styles, opts.body_styles, opts.body),
        section_box(opts.footer_default_styles, opts.footer_styles, opts.footer),
    }
end

function M.scroll_panel(opts)
    opts = opts or {}
    if opts.scroll_id == nil then
        error("scroll_panel expects opts.scroll_id", 2)
    end
    if opts.axis == nil then
        error("scroll_panel expects opts.axis", 2)
    end

    return b.box {
        opts.id,
        tw.flex, tw.col,
        style_group(opts.styles),
        section_box(opts.header_default_styles, opts.header_styles, opts.header),
        b.scroll(opts.scroll_id, opts.axis, {
            tw.grow_1, tw.basis_px(0), tw.min_h_px(0),
            style_group(opts.scroll_styles),
            section_box(opts.body_default_styles, opts.body_styles, opts.body),
        }),
        section_box(opts.footer_default_styles, opts.footer_styles, opts.footer),
    }
end

function M.hsplit(opts)
    opts = opts or {}
    return b.box {
        opts.id,
        tw.flex, tw.row,
        style_group(opts.styles),
        child_node(opts.left),
        child_node(opts.right),
        child_node(opts.children),
    }
end

function M.vsplit(opts)
    opts = opts or {}
    return b.box {
        opts.id,
        tw.flex, tw.col,
        style_group(opts.styles),
        child_node(opts.top),
        child_node(opts.bottom),
        child_node(opts.children),
    }
end

function M.workbench(opts)
    opts = opts or {}

    local center = section_box({ tw.grow_1, tw.basis_px(0), tw.min_w_px(0), tw.min_h_px(0) }, opts.center_styles, opts.center)
    if center == nil then
        error("workbench expects opts.center", 2)
    end

    local middle = b.box {
        tw.flex, tw.row,
        tw.grow_1, tw.basis_px(0), tw.min_h_px(0),
        style_group(opts.middle_styles),
        section_box({ tw.shrink_0 }, opts.left_styles, opts.left),
        center,
        section_box({ tw.shrink_0 }, opts.right_styles, opts.right),
    }

    return b.box {
        opts.id,
        tw.flex, tw.col,
        style_group(opts.styles),
        section_box({ tw.shrink_0 }, opts.top_styles, opts.top),
        middle,
        section_box({ tw.shrink_0 }, opts.bottom_styles, opts.bottom),
    }
end

M.T = T

return M
