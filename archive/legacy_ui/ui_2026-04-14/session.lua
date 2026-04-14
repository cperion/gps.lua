-- ui/session.lua
--
-- Explicit UI session state, generic message handling, and reducer wiring.
-- Includes keyboard focus traversal and focused-item activation hooks.
--
-- This module stays reducer-friendly:
--   - state is plain data
--   - widget-local state is keyed explicitly
--   - messages are typed `Msg.Event` values
--   - hit-testing and drawing are delegated to `ui.hit` / `ui.draw`
--   - no hidden retained widget graph exists

local pvm = require("pvm")
local classof = pvm.classof
local schema = require("ui.asdl")
local solve = require("ui.solve")
local hit = require("ui.hit")
local draw = require("ui.draw")

local T = schema.T

local session = { T = T, schema = schema, solve_reducer = solve, hit_reducer = hit, draw_reducer = draw }

local type = type
local setmetatable = setmetatable

local POINTER_IDLE     = T.Interact.Idle
local POINTER_HOVERED  = T.Interact.Hovered
local POINTER_PRESSED  = T.Interact.Pressed
local POINTER_DRAGGING = T.Interact.Dragging

local FOCUS_BLURRED = T.Interact.Blurred
local FOCUS_FOCUSED = T.Interact.Focused

local AXIS_ROW_REV = T.Layout.AxisRowReverse
local AXIS_COL_REV = T.Layout.AxisColReverse

local KIND_CLICK       = T.Msg.Click
local KIND_PRESS       = T.Msg.Press
local KIND_RELEASE     = T.Msg.Release
local KIND_HOVER_ENTER = T.Msg.HoverEnter
local KIND_HOVER_LEAVE = T.Msg.HoverLeave
local KIND_FOCUS       = T.Msg.Focus
local KIND_BLUR        = T.Msg.Blur
local KIND_SCROLL      = T.Msg.Scroll
local KIND_CHANGE      = T.Msg.Change
local KIND_SUBMIT      = T.Msg.Submit
local KIND_CANCEL      = T.Msg.Cancel

local PAYLOAD_NONE = T.Msg.None
local PAYLOAD_NUM_MT = classof(T.Msg.Num(0))
local PAYLOAD_BOOL_MT = classof(T.Msg.Bool(false))
local PAYLOAD_TEXT_MT = classof(T.Msg.Text(""))
local PAYLOAD_PAIR_MT = classof(T.Msg.Pair(0, 0))

local MISS = T.Facts.Miss

local Event = T.Msg.Event
local PayloadNum = T.Msg.Num
local PayloadBool = T.Msg.Bool
local PayloadText = T.Msg.Text
local PayloadPair = T.Msg.Pair
local KindCustom = T.Msg.Custom

local KIND_MAP = {
    click = KIND_CLICK,
    press = KIND_PRESS,
    release = KIND_RELEASE,
    hover_enter = KIND_HOVER_ENTER,
    hover_leave = KIND_HOVER_LEAVE,
    focus = KIND_FOCUS,
    blur = KIND_BLUR,
    scroll = KIND_SCROLL,
    change = KIND_CHANGE,
    submit = KIND_SUBMIT,
    cancel = KIND_CANCEL,
}

local function copy_state(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, vv in pairs(v) do
        out[k] = copy_state(vv)
    end
    return out
end

function session.state(seed)
    return seed and copy_state(seed) or {
        hot = nil,
        active = nil,
        pressed = nil,
        dragging = nil,
        focused = nil,
        widgets = {},
        nav = {},
    }
end

function session.clone_state(state)
    return copy_state(state)
end

local function normalize_kind(kind)
    if type(kind) == "string" then
        return KIND_MAP[kind] or KindCustom(kind)
    end
    return kind or KindCustom("")
end

local function normalize_payload(payload)
    if payload == nil or payload == PAYLOAD_NONE then
        return PAYLOAD_NONE
    end
    local tp = type(payload)
    if tp == "number" then
        return PayloadNum(payload)
    end
    if tp == "boolean" then
        return PayloadBool(payload)
    end
    if tp == "string" then
        return PayloadText(payload)
    end
    if tp == "table" then
        local mt = classof(payload)
        if mt == PAYLOAD_NUM_MT or mt == PAYLOAD_BOOL_MT or mt == PAYLOAD_TEXT_MT or mt == PAYLOAD_PAIR_MT then
            return payload
        end
        if payload.a ~= nil and payload.b ~= nil then
            return PayloadPair(payload.a, payload.b)
        end
        if payload[1] ~= nil and payload[2] ~= nil then
            return PayloadPair(payload[1], payload[2])
        end
    end
    error("ui.session: unsupported message payload type " .. tostring(tp), 2)
end

function session.pointer_for_id(state, id)
    if not id or id == "" then
        return POINTER_IDLE
    end
    if state.dragging == id then
        return POINTER_DRAGGING
    end
    if state.pressed == id or state.active == id then
        return POINTER_PRESSED
    end
    if state.hot == id then
        return POINTER_HOVERED
    end
    return POINTER_IDLE
end

function session.focus_for_id(state, id)
    if id ~= nil and id ~= "" and state.focused == id then
        return FOCUS_FOCUSED
    end
    return FOCUS_BLURRED
end

local function clear_seq(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

local function first_field(t, ...)
    if not t then
        return nil
    end
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        local v = t[key]
        if v ~= nil then
            return v
        end
    end
    return nil
end

local function input_xy(input)
    return first_field(input, "x", "mx", "mouse_x", "pointer_x"),
           first_field(input, "y", "my", "mouse_y", "pointer_y")
end

local function input_pressed(input)
    return not not first_field(input, "pressed", "mouse_pressed")
end

local function input_released(input)
    return not not first_field(input, "released", "mouse_released")
end

local function input_down(input)
    return not not first_field(input, "down", "mouse_down")
end

local function input_dragging(input)
    return first_field(input, "dragging", "mouse_dragging")
end

local function input_scroll(input)
    return first_field(input, "scroll_x", "wheel_x"),
           first_field(input, "scroll_y", "wheel_y")
end

local function input_focus_next(input)
    return not not first_field(input, "focus_next", "tab_next")
end

local function input_focus_prev(input)
    return not not first_field(input, "focus_prev", "tab_prev")
end

local function input_activate(input)
    return not not first_field(input, "activate", "click_focused")
end

local function input_submit(input)
    return not not first_field(input, "submit")
end

local function input_cancel(input)
    return not not first_field(input, "cancel")
end

local Session = {}
Session.__index = Session
session.Session = Session

function session.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Session)
    self.state = opts.state or session.state()
    if self.state.nav == nil then
        self.state.nav = {}
    end
    self.backend = opts.backend
    self.prune_dead_widgets = opts.prune_dead_widgets ~= false
    self._messages = {}
    self._seen_keys = {}
    self._nav_index = {}
    self._nav_seen = {}
    self._frame = nil
    self._input = nil
    self._env = nil
    self.stats = {
        frames = 0,
        messages = 0,
        widget_inits = 0,
        widget_prunes = 0,
        hits = 0,
        draws = 0,
        paint_draws = 0,
    }
    return self
end

session.session = session.new

local function reducer_opts(self, opts, backend)
    opts = opts or {}
    return {
        backend = backend or opts.backend or self.backend,
        state = opts.state or self.state,
        session = opts.session or self,
        hot = opts.hot,
        runtime = opts.runtime or opts.env,
        env = opts.env,
        measure = opts.measure,
        text_measure = opts.text_measure,
        font_height = opts.font_height,
        measure_stats = opts.measure_stats,
        text_draw = opts.text_draw,
        resolve_runtime_text = opts.resolve_runtime_text,
        resolve_custom_paint = opts.resolve_custom_paint,
        draw_custom_paint = opts.draw_custom_paint,
        view = opts.view,
    }
end

local function set_focused_emitting(self, id)
    local prev = self.state.focused
    if prev == id then
        return self
    end
    if prev ~= nil and prev ~= "" then
        self:emit(KIND_BLUR, prev)
    end
    self.state.focused = id
    local nav = self.state.nav
    if nav ~= nil then
        nav.focused_index = (id ~= nil and id ~= "" and self._nav_index[id]) or 0
    end
    if id ~= nil and id ~= "" then
        self:emit(KIND_FOCUS, id)
    end
    return self
end

local function clear_map(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local function nav_state(self)
    local nav = self.state.nav
    if nav == nil then
        nav = {}
        self.state.nav = nav
    end
    local order = nav.order
    if order == nil then
        order = {}
        nav.order = order
    end
    return nav, order
end

local function is_reverse_axis(axis)
    return axis == AXIS_ROW_REV or axis == AXIS_COL_REV
end

local function collect_focus_ids(node, order, seen)
    if node == nil then
        return
    end

    local kind = node.kind
    if kind == "Interact" then
        local id = node.focus_id
        if id ~= nil and id ~= "" and not seen[id] then
            seen[id] = true
            order[#order + 1] = id
        end
        collect_focus_ids(node.child, order, seen)
    elseif kind == "Pad" or kind == "Clip" or kind == "Transform"
        or kind == "ScrollArea" or kind == "Panel" then
        collect_focus_ids(node.child, order, seen)
    elseif kind == "Flex" then
        local children = node.children
        if is_reverse_axis(node.axis) then
            for i = #children, 1, -1 do
                collect_focus_ids(children[i].node, order, seen)
            end
        else
            for i = 1, #children do
                collect_focus_ids(children[i].node, order, seen)
            end
        end
    elseif kind == "Grid" then
        local children = node.children
        for i = 1, #children do
            collect_focus_ids(children[i].node, order, seen)
        end
    elseif kind == "Stack" then
        local children = node.children
        for i = 1, #children do
            collect_focus_ids(children[i], order, seen)
        end
    elseif kind == "Overlay" then
        collect_focus_ids(node.base, order, seen)
    end
end

local function sync_focus_nav(self, node)
    local nav, order = nav_state(self)
    local index = self._nav_index
    local seen = self._nav_seen

    clear_seq(order)
    clear_map(index)
    clear_map(seen)

    if node ~= nil then
        collect_focus_ids(node, order, seen)
        for i = 1, #order do
            index[order[i]] = i
        end
    end

    nav.count = #order
    nav.focused_index = (self.state.focused ~= nil and self.state.focused ~= "" and index[self.state.focused]) or 0
    return nav, order, index
end

local function move_focus_from_nav(self, order, index, delta, opts)
    local n = #order
    if n == 0 then
        return nil
    end

    local cur = self.state.focused
    local cur_i = (cur ~= nil and cur ~= "" and index[cur]) or nil
    local wrap = opts == nil or opts.wrap ~= false
    local next_i

    if cur_i == nil then
        next_i = (delta >= 0) and 1 or n
    else
        next_i = cur_i + delta
        if wrap then
            if next_i < 1 then
                next_i = n
            elseif next_i > n then
                next_i = 1
            end
        else
            if next_i < 1 then
                next_i = 1
            elseif next_i > n then
                next_i = n
            end
        end
    end

    local id = order[next_i]
    if id ~= nil then
        set_focused_emitting(self, id)
    end
    return id
end

function Session:get_state()
    return self.state
end

function Session:set_state(state)
    self.state = state or session.state()
    if self.state.nav == nil then
        self.state.nav = {}
    end
    return self
end

function Session:set_backend(backend)
    self.backend = backend
    return self
end

function Session:get_backend()
    return self.backend
end

function Session:clone_state()
    return session.clone_state(self.state)
end

function Session:reset_state(seed)
    self.state = session.state(seed)
    return self
end

function Session:reset_messages()
    clear_seq(self._messages)
    return self
end

function Session:messages()
    return self._messages
end

function Session:drain_messages()
    local out = self._messages
    self._messages = {}
    return out
end

function Session:emit(kind, id, payload)
    local event = Event(normalize_kind(kind), id or "", normalize_payload(payload))
    local out = self._messages
    out[#out + 1] = event
    self.stats.messages = self.stats.messages + 1
    return event
end

function Session:begin_frame()
    self.stats.frames = self.stats.frames + 1
    self:reset_messages()
    if self.prune_dead_widgets then
        for k in pairs(self._seen_keys) do
            self._seen_keys[k] = nil
        end
    end
    return self
end

function Session:end_frame()
    if self.prune_dead_widgets and self.state.widgets then
        for k in pairs(self.state.widgets) do
            if not self._seen_keys[k] then
                self.state.widgets[k] = nil
                self.stats.widget_prunes = self.stats.widget_prunes + 1
            end
        end
    end
    return self
end

function Session:mark_seen(id)
    if id ~= nil and id ~= "" then
        self._seen_keys[id] = true
    end
    return self
end

function Session:widget(id, init_fn)
    if id == nil or id == "" then
        return init_fn and init_fn() or {}
    end
    local widgets = self.state.widgets
    if widgets == nil then
        widgets = {}
        self.state.widgets = widgets
    end
    local st = widgets[id]
    if st == nil then
        st = init_fn and init_fn() or {}
        widgets[id] = st
        self.stats.widget_inits = self.stats.widget_inits + 1
    end
    self:mark_seen(id)
    return st
end

function Session:clear_widget_state()
    self.state.widgets = {}
    return self
end

function Session:clear_widget(id)
    local widgets = self.state.widgets
    if widgets then
        widgets[id] = nil
    end
    self._seen_keys[id] = nil
    return self
end

function Session:is_hovered(id)
    return self.state.hot == id
end

function Session:is_pressed(id)
    return self.state.pressed == id or self.state.active == id
end

function Session:is_active(id)
    return self.state.active == id
end

function Session:is_dragging(id)
    return self.state.dragging == id
end

function Session:is_focused(id)
    return self.state.focused == id
end

function Session:pointer_for(id)
    return session.pointer_for_id(self.state, id)
end

function Session:focus_for(id)
    return session.focus_for_id(self.state, id)
end

function Session:focus_next(node, opts)
    local _, order, index = sync_focus_nav(self, node)
    return move_focus_from_nav(self, order, index, 1, opts)
end

function Session:focus_prev(node, opts)
    local _, order, index = sync_focus_nav(self, node)
    return move_focus_from_nav(self, order, index, -1, opts)
end

function Session:set_hot(id)
    self.state.hot = id
    return self
end

function Session:set_active(id)
    self.state.active = id
    return self
end

function Session:set_pressed(id)
    self.state.pressed = id
    return self
end

function Session:set_dragging(id)
    self.state.dragging = id
    return self
end

function Session:focus(id)
    self.state.focused = id
    local nav = self.state.nav
    if nav ~= nil then
        nav.focused_index = (id ~= nil and id ~= "" and self._nav_index[id]) or 0
    end
    return self
end

function Session:blur()
    self.state.focused = nil
    local nav = self.state.nav
    if nav ~= nil then
        nav.focused_index = 0
    end
    return self
end

function Session:clear_interaction()
    self.state.hot = nil
    self.state.active = nil
    self.state.pressed = nil
    self.state.dragging = nil
    return self
end

function Session:hit_result(node, opts)
    opts = opts or {}
    local frame = assert(opts.frame, "ui.session:hit_result expected opts.frame")
    local x = first_field(opts, "x", "mx", "mouse_x", "pointer_x")
    local y = first_field(opts, "y", "my", "mouse_y", "pointer_y")
    if x == nil or y == nil then
        error("ui.session:hit_result expected opts.x/opts.y (or mx/my, mouse_x/mouse_y)", 2)
    end
    self.stats.hits = self.stats.hits + 1
    return hit.hit(node, frame, x, y, reducer_opts(self, opts))
end

function Session:hit(node, opts)
    local result = self:hit_result(node, opts)
    if result == MISS then
        return nil
    end
    return result.id
end

local function same_frame(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

function Session:draw(node, opts)
    opts = opts or {}
    local frame = assert(opts.frame, "ui.session:draw expected opts.frame")
    local backend = opts.backend or self.backend
    if not backend then
        return self
    end
    self.stats.draws = self.stats.draws + 1
    local ropts = reducer_opts(self, opts, backend)
    local solved = opts.solved
    if solved == nil and self._solved ~= nil and self._solved_node == node and same_frame(self._solved_frame, frame) then
        solved = self._solved
    end
    if solved ~= nil then
        draw.draw_solved(solved, frame, ropts)
    else
        draw.draw(node, frame, ropts)
    end
    return self
end

function Session:draw_paint(node, opts)
    opts = opts or {}
    local frame = opts.frame or self._frame
    if not frame then
        error("ui.session:draw_paint expected opts.frame (or prior Session:frame call)", 2)
    end
    local backend = opts.backend or self.backend
    if not backend then
        return self
    end
    self.stats.paint_draws = self.stats.paint_draws + 1
    draw.paint(node, frame, reducer_opts(self, opts, backend))
    return self
end

function Session:frame(node, opts)
    opts = opts or {}
    local frame = assert(opts.frame, "ui.session:frame expected opts.frame")
    local input = opts.input or {}
    local do_pick = opts.pick ~= false
    local do_draw = opts.draw
    if do_draw == nil then
        do_draw = (opts.backend or self.backend) ~= nil
    end

    self._frame = frame
    self._input = input
    self._env = opts.runtime or opts.env

    self:begin_frame()

    local solved = (do_pick or do_draw) and solve.node(node, frame, {
        text_measure = opts.text_measure,
        font_height = opts.font_height,
        measure_stats = opts.measure_stats,
    }) or nil
    self._solved = solved
    self._solved_node = node
    self._solved_frame = frame

    local _, nav_order, nav_index = sync_focus_nav(self, node)
    if input_focus_prev(input) then
        move_focus_from_nav(self, nav_order, nav_index, -1)
    elseif input_focus_next(input) then
        move_focus_from_nav(self, nav_order, nav_index, 1)
    end

    local prev_hot = self.state.hot
    local hovered = prev_hot
    local scroll_target = hovered
    local x, y = input_xy(input)
    local sx, sy = input_scroll(input)
    local want_scroll_target = ((sx ~= nil and sx ~= 0) or (sy ~= nil and sy ~= 0))
    if do_pick and x ~= nil and y ~= nil then
        local pick_opts = {
            frame = frame,
            x = x,
            y = y,
            state = opts.state,
            hot = opts.hot,
            measure = opts.measure,
            text_measure = opts.text_measure,
            font_height = opts.font_height,
            measure_stats = opts.measure_stats,
        }
        hovered = hit.id_solved(solved, frame, x, y, reducer_opts(self, pick_opts))
        if want_scroll_target then
            scroll_target = hit.scroll_id_solved(solved, frame, x, y, reducer_opts(self, pick_opts)) or hovered
        else
            scroll_target = hovered
        end
    end

    if hovered ~= prev_hot then
        if prev_hot ~= nil and prev_hot ~= "" then
            self:emit(KIND_HOVER_LEAVE, prev_hot)
        end
        if hovered ~= nil and hovered ~= "" then
            self:emit(KIND_HOVER_ENTER, hovered)
        end
    end
    self.state.hot = hovered

    local pressed = input_pressed(input)
    local released = input_released(input)
    local down = input_down(input)
    local dragging = input_dragging(input)

    if pressed then
        self.state.active = hovered
        self.state.pressed = hovered
        if hovered ~= nil then
            set_focused_emitting(self, hovered)
            self:emit(KIND_PRESS, hovered)
        else
            set_focused_emitting(self, nil)
        end
    elseif released then
        local active = self.state.active
        if active ~= nil then
            self:emit(KIND_RELEASE, active)
        end
        if active ~= nil and active == hovered then
            self:emit(KIND_CLICK, active)
        end
        self.state.active = nil
        self.state.pressed = nil
        self.state.dragging = nil
    elseif down then
        self.state.pressed = self.state.active
        if dragging == true then
            self.state.dragging = self.state.active
        elseif type(dragging) == "string" then
            self.state.dragging = dragging
        end
    else
        self.state.pressed = nil
        if dragging == false then
            self.state.dragging = nil
        end
    end

    local focused = self.state.focused
    if focused ~= nil and focused ~= "" then
        if input_activate(input) then
            self:emit(KIND_PRESS, focused)
            self:emit(KIND_RELEASE, focused)
            self:emit(KIND_CLICK, focused)
        end
        if input_submit(input) then
            self:emit(KIND_SUBMIT, focused)
        end
        if input_cancel(input) then
            self:emit(KIND_CANCEL, focused)
        end
    end

    if scroll_target ~= nil and want_scroll_target then
        self:emit(KIND_SCROLL, scroll_target, { sx or 0, sy or 0 })
    end

    if do_draw then
        draw.draw_solved(solved, frame, reducer_opts(self, {
            frame = frame,
            backend = opts.backend,
            state = opts.state,
            hot = opts.hot,
            runtime = opts.runtime,
            env = opts.env,
            measure = opts.measure,
            text_measure = opts.text_measure,
            font_height = opts.font_height,
            measure_stats = opts.measure_stats,
            text_draw = opts.text_draw,
        }, opts.backend or self.backend))
        if opts.overlay ~= nil then
            self:draw_paint(opts.overlay, {
                frame = frame,
                backend = opts.backend,
                state = opts.state,
                hot = opts.hot,
                runtime = opts.runtime,
                env = opts.env,
                measure = opts.measure,
                text_measure = opts.text_measure,
                font_height = opts.font_height,
                measure_stats = opts.measure_stats,
                text_draw = opts.text_draw,
            })
        end
    end

    self:end_frame()
    return self.state, self._messages
end

function Session:report_string()
    return table.concat({
        string.format("  %-24s %d", "frames", self.stats.frames),
        string.format("  %-24s %d", "messages", self.stats.messages),
        string.format("  %-24s %d", "widget_inits", self.stats.widget_inits),
        string.format("  %-24s %d", "widget_prunes", self.stats.widget_prunes),
        string.format("  %-24s %d", "hits", self.stats.hits),
        string.format("  %-24s %d", "draws", self.stats.draws),
        string.format("  %-24s %d", "paint_draws", self.stats.paint_draws),
    }, "\n")
end

return session
