local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local tw = require("ui.tw")
local b = require("ui.build")

local T = ui_asdl.T
local Compose = T.Compose
local Auth = T.Auth

local M = {}

local function style_value(v)
    if v == nil or v == false then return nil end
    return v
end

local function gather(...)
    local n = select("#", ...)
    local out = {}
    for i = 1, n do
        local v = select(i, ...)
        if v ~= nil then
            out[#out + 1] = v
        end
    end
    return out
end

local function lower_one(node)
    if node == nil then return nil end
    return pvm.one(M.phase(node))
end

local function lower_many(nodes)
    local out = {}
    for i = 1, #nodes do
        local child = lower_one(nodes[i])
        if child ~= nil and child ~= Auth.Empty then
            out[#out + 1] = child
        end
    end
    return out
end

local function section_box(default_styles, styles, content)
    local child = lower_one(content)
    if child == nil or child == Auth.Empty then return nil end
    return b.box(gather(
        default_styles and tw.group(default_styles) or nil,
        style_value(styles),
        child
    ))
end

M.phase = pvm.phase("ui.compose", {
    [Compose.Raw] = function(self)
        return pvm.once(self.child)
    end,

    [Compose.Fragment] = function(self)
        return pvm.once(b.fragment(lower_many(self.children)))
    end,

    [Compose.Panel] = function(self)
        return pvm.once(b.box(gather(
            self.id,
            tw.flex, tw.col,
            tw.items_stretch,
            style_value(self.styles),
            section_box(nil, self.header_styles, self.header),
            section_box(nil, self.body_styles, self.body),
            section_box(nil, self.footer_styles, self.footer)
        )))
    end,

    [Compose.ScrollPanel] = function(self)
        return pvm.once(b.box(gather(
            self.id,
            tw.flex, tw.col,
            tw.items_stretch,
            style_value(self.styles),
            section_box(nil, self.header_styles, self.header),
            b.scroll(self.scroll_id, self.axis, gather(
                tw.grow_1, tw.basis_px(0), tw.min_h_px(0),
                style_value(self.scroll_styles),
                section_box(nil, self.body_styles, self.body)
            )),
            section_box(nil, self.footer_styles, self.footer)
        )))
    end,

    [Compose.HSplit] = function(self)
        return pvm.once(b.box(gather(
            self.id,
            tw.flex, tw.row,
            tw.items_stretch,
            style_value(self.styles),
            b.fragment(lower_many(self.children))
        )))
    end,

    [Compose.VSplit] = function(self)
        return pvm.once(b.box(gather(
            self.id,
            tw.flex, tw.col,
            tw.items_stretch,
            style_value(self.styles),
            b.fragment(lower_many(self.children))
        )))
    end,

    [Compose.Workbench] = function(self)
        local center = section_box({ tw.flex, tw.col, tw.items_stretch, tw.grow_1, tw.basis_px(0), tw.min_w_px(0), tw.min_h_px(0) }, self.center_styles, self.center)
        local middle = b.box(gather(
            tw.flex, tw.row,
            tw.items_stretch,
            tw.grow_1, tw.basis_px(0), tw.min_h_px(0),
            style_value(self.middle_styles),
            section_box({ tw.flex, tw.col, tw.items_stretch, tw.shrink_0 }, self.left_styles, self.left),
            center,
            section_box({ tw.flex, tw.col, tw.items_stretch, tw.shrink_0 }, self.right_styles, self.right)
        ))

        return pvm.once(b.box(gather(
            self.id,
            tw.flex, tw.col,
            tw.items_stretch,
            style_value(self.styles),
            section_box({ tw.flex, tw.col, tw.items_stretch, tw.shrink_0 }, self.top_styles, self.top),
            middle,
            section_box({ tw.flex, tw.col, tw.items_stretch, tw.shrink_0 }, self.bottom_styles, self.bottom)
        )))
    end,
})

function M.root(node)
    return pvm.one(M.phase(node))
end

M.T = T

return M
