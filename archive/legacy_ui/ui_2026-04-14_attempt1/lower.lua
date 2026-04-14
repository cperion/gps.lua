local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local normalize = require("ui.normalize")
local resolve = require("ui.resolve")

local T = ui_asdl.T
local Auth = T.Auth
local Layout = T.Layout
local S = T.Style

local M = {}

local lower

local function resolve_style(tokens, theme, env)
    return resolve.resolve(normalize.normalize(tokens, env), theme)
end

local function lower_children_into(out, children, theme, env)
    for i = 1, #children do
        local g, p, c = lower(children[i], theme, env)
        pvm.drain_into(g, p, c, out)
    end
end

local function append_grid_items_into(out, node, theme, env)
    local cls = pvm.classof(node)

    if cls == Auth.Empty then
        return
    end

    if cls == Auth.Fragment then
        local children = node.children
        for i = 1, #children do
            append_grid_items_into(out, children[i], theme, env)
        end
        return
    end

    local lowered = pvm.drain(lower(node, theme, env))
    local resolved = resolve_style(node.styles, theme, env)
    local placement = resolved.placement

    for i = 1, #lowered do
        out[#out + 1] = Layout.GridItem(
            lowered[i],
            placement.col_start,
            placement.col_span,
            placement.row_start,
            placement.row_span,
            placement.col_align,
            placement.row_align
        )
    end
end

lower = pvm.phase("ui.lower", {
    [Auth.Empty] = function(self, theme, env)
        return pvm.empty()
    end,

    [Auth.Fragment] = function(self, theme, env)
        return pvm.children(function(child)
            return lower(child, theme, env)
        end, self.children)
    end,

    [Auth.Text] = function(self, theme, env)
        local r = resolve_style(self.styles, theme, env)
        return pvm.once(Layout.Leaf(
            self.id,
            r.box,
            Layout.TextStyle(
                r.text.font_id,
                r.text.font_size,
                r.text.font_weight,
                r.text.fg,
                r.text.align,
                r.text.leading,
                r.text.tracking,
                self.content
            )
        ))
    end,

    [Auth.Box] = function(self, theme, env)
        local r = resolve_style(self.styles, theme, env)

        if r.display == S.DisplayGrid then
            local items = {}
            local children = self.children
            for i = 1, #children do
                append_grid_items_into(items, children[i], theme, env)
            end
            return pvm.once(Layout.Grid(
                self.id,
                r.box,
                r.cols,
                r.rows,
                r.col_gap,
                r.row_gap,
                items
            ))
        end

        local children = {}
        lower_children_into(children, self.children, theme, env)
        return pvm.once(Layout.Flex(
            self.id,
            r.box,
            r.axis,
            r.wrap,
            r.justify,
            r.items,
            r.gap_x,
            r.gap_y,
            children
        ))
    end,
})

function M.one(node, theme, env)
    return pvm.one(lower(node, theme, env))
end

function M.list(nodes, theme, env)
    local out = {}
    for i = 1, #nodes do
        local g, p, c = lower(nodes[i], theme, env)
        pvm.drain_into(g, p, c, out)
    end
    return out
end

M.phase = lower
M.lower = lower
M.T = T

return M
