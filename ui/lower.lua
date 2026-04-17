local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local norm = require("ui.normalize")
local resolve = require("ui.resolve")

local T = ui_asdl.T
local Core = T.Core
local Auth = T.Auth
local S = T.Style
local Layout = T.Layout

local M = {}

local NO_STATE = T.Style.State(false, false, false, false, false)

local lower_phase

local function merge_state(parent, child)
    parent = parent or NO_STATE
    child = child or NO_STATE
    return T.Style.State(
        parent.hovered or child.hovered,
        parent.focused or child.focused,
        parent.active or child.active,
        parent.selected or child.selected,
        parent.disabled or child.disabled
    )
end

local function resolve_style(tokens, theme, env, state)
    local sg, sp, sc = norm.normalize_phase(tokens, env, state or NO_STATE)
    local spec = pvm.one(sg, sp, sc)
    local rg, rp, rc = resolve.phase(spec, theme)
    return pvm.one(rg, rp, rc)
end

local function lower_children_into(out, children, theme, env, state)
    for i = 1, #children do
        local g, p, c = lower_phase(children[i], theme, env, state)
        pvm.drain_into(g, p, c, out)
    end
end

local function placement_source(auth_node)
    local cls = pvm.classof(auth_node)
    if cls == Auth.WithInput or cls == Auth.WithState then
        return placement_source(auth_node.child)
    end
    return auth_node
end

local function has_scroll_overflow(box)
    return box.overflow_x == Layout.OScroll or box.overflow_x == Layout.OAuto
        or box.overflow_y == Layout.OScroll or box.overflow_y == Layout.OAuto
end

local function scroll_axis_from_box(box)
    local sx = box.overflow_x == Layout.OScroll or box.overflow_x == Layout.OAuto
    local sy = box.overflow_y == Layout.OScroll or box.overflow_y == Layout.OAuto
    if sx and sy then return S.ScrollBoth end
    if sx then return S.ScrollX end
    if sy then return S.ScrollY end
    return nil
end

local function visible_box(box)
    return pvm.with(box, {
        overflow_x = Layout.OVisible,
        overflow_y = Layout.OVisible,
    })
end

local function content_box_for_scroll(axis)
    local w = (axis == S.ScrollY) and Layout.SFill or Layout.SHug
    local h = (axis == S.ScrollX) and Layout.SFill or Layout.SHug
    if axis == S.ScrollBoth then
        w, h = Layout.SFill, Layout.SFill
    end
    return Layout.BoxStyle(
        w,
        h,
        Layout.NoMin,
        Layout.NoMax,
        Layout.NoMin,
        Layout.NoMax,
        0,
        1,
        Layout.BasisAuto,
        Layout.SelfAuto,
        Layout.Edges(0, 0, 0, 0),
        Layout.Margin(Layout.MarginPx(0), Layout.MarginPx(0), Layout.MarginPx(0), Layout.MarginPx(0)),
        Layout.Visual(0, 0, 0, 0, 0, 100),
        Layout.OVisible,
        Layout.OVisible,
        S.CursorDefault
    )
end

local function wrap_layout_children_for_scroll(axis, nodes)
    if #nodes == 0 then
        return Layout.Flow(Core.NoId, content_box_for_scroll(axis), Layout.MStart, Layout.CStart, 0, {})
    end
    if #nodes == 1 then
        return nodes[1]
    end
    return Layout.Flow(Core.NoId, content_box_for_scroll(axis), Layout.MStart, Layout.CStart, 0, nodes)
end

local function maybe_wrap_scroll(id, box, axis, child)
    return Layout.Scroll(id, visible_box(box), axis, child)
end

local function append_grid_items(out, auth_node, theme, env, state)
    local cls = pvm.classof(auth_node)

    if cls == Auth.Empty then
        return
    end

    if cls == Auth.Fragment then
        local children = auth_node.children
        for i = 1, #children do
            append_grid_items(out, children[i], theme, env, state)
        end
        return
    end

    local source = placement_source(auth_node)
    local resolved = resolve_style(source.styles, theme, env, state)
    local gp = resolved.placement
    local nodes = pvm.drain(lower_phase(auth_node, theme, env, state))

    for i = 1, #nodes do
        out[#out + 1] = Layout.GridItem(
            nodes[i],
            gp.col_start,
            gp.col_span,
            gp.row_start,
            gp.row_span,
            Layout.CStretch,
            Layout.CStretch
        )
    end
end

lower_phase = pvm.phase("ui.lower", {
    [Auth.Empty] = function(self, theme, env, state)
        return pvm.empty()
    end,

    [Auth.Fragment] = function(self, theme, env, state)
        local children = self.children
        local n = #children
        if n == 0 then
            return pvm.empty()
        end
        local trips = {}
        for i = 1, n do
            local g, p, c = lower_phase(children[i], theme, env, state)
            trips[i] = { g, p, c }
        end
        return pvm.concat_all(trips)
    end,

    [Auth.WithState] = function(self, theme, env, state)
        return lower_phase(self.child, theme, env, merge_state(state, self.state))
    end,

    [Auth.WithInput] = function(self, theme, env, state)
        local lowered = pvm.drain(lower_phase(self.child, theme, env, state))
        if #lowered == 0 then
            return pvm.empty()
        end
        if #lowered == 1 then
            return pvm.once(Layout.WithInput(self.id, self.role, lowered[1]))
        end
        local trips = {}
        for i = 1, #lowered do
            trips[i] = { pvm.once(Layout.WithInput(self.id, self.role, lowered[i])) }
        end
        return pvm.concat_all(trips)
    end,

    [Auth.Text] = function(self, theme, env, state)
        local r = resolve_style(self.styles, theme, env, state)
        local text = Layout.TextStyle(
            r.text.font_id,
            r.text.font_size,
            r.text.font_weight,
            r.text.fg,
            r.text.align,
            r.text.leading,
            r.text.tracking,
            self.content
        )
        if has_scroll_overflow(r.box) then
            local axis = scroll_axis_from_box(r.box)
            local inner = Layout.Leaf(Core.NoId, content_box_for_scroll(axis), text)
            return pvm.once(maybe_wrap_scroll(self.id, r.box, axis, inner))
        end
        return pvm.once(Layout.Leaf(self.id, r.box, text))
    end,

    [Auth.Paint] = function(self, theme, env, state)
        local r = resolve_style(self.styles, theme, env, state)
        if has_scroll_overflow(r.box) then
            local axis = scroll_axis_from_box(r.box)
            local inner = Layout.Paint(Core.NoId, content_box_for_scroll(axis), self.paint)
            return pvm.once(maybe_wrap_scroll(self.id, r.box, axis, inner))
        end
        return pvm.once(Layout.Paint(self.id, r.box, self.paint))
    end,

    [Auth.Scroll] = function(self, theme, env, state)
        local r = resolve_style(self.styles, theme, env, state)
        local lowered = pvm.drain(lower_phase(self.child, theme, env, state))
        return pvm.once(Layout.Scroll(
            self.id,
            visible_box(r.box),
            self.axis,
            wrap_layout_children_for_scroll(self.axis, lowered)
        ))
    end,

    [Auth.Box] = function(self, theme, env, state)
        local r = resolve_style(self.styles, theme, env, state)

        if has_scroll_overflow(r.box) then
            local axis = scroll_axis_from_box(r.box)
            if r.display == S.DisplayGrid then
                local items = {}
                append_grid_items(items, Auth.Fragment(self.children), theme, env, state)
                return pvm.once(maybe_wrap_scroll(self.id, r.box, axis, Layout.Grid(
                    Core.NoId,
                    content_box_for_scroll(axis),
                    r.cols,
                    r.rows,
                    r.col_gap,
                    r.row_gap,
                    items
                )))
            end

            local children = {}
            lower_children_into(children, self.children, theme, env, state)
            if r.display == S.DisplayFlex then
                return pvm.once(maybe_wrap_scroll(self.id, r.box, axis, Layout.Flex(
                    Core.NoId,
                    content_box_for_scroll(axis),
                    r.axis,
                    r.wrap,
                    r.justify,
                    r.items,
                    r.gap_x,
                    r.gap_y,
                    children
                )))
            end

            return pvm.once(maybe_wrap_scroll(self.id, r.box, axis, Layout.Flow(
                Core.NoId,
                content_box_for_scroll(axis),
                r.justify,
                r.items,
                r.gap_y,
                children
            )))
        end

        if r.display == S.DisplayGrid then
            local items = {}
            append_grid_items(items, Auth.Fragment(self.children), theme, env, state)
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
        lower_children_into(children, self.children, theme, env, state)

        if r.display == S.DisplayFlex then
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
        end

        return pvm.once(Layout.Flow(
            self.id,
            r.box,
            r.justify,
            r.items,
            r.gap_y,
            children
        ))
    end,
})

M.phase = lower_phase
M.T = T

return M
