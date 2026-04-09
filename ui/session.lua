-- ui/session.lua
--
-- Explicit UI session state, generic message handling, and reducer wiring.
--
-- This module stays reducer-friendly:
--   - state is plain data
--   - widget-local state is keyed explicitly
--   - messages are typed `Msg.Event` values
--   - hit-testing and drawing are delegated to `ui.hit` / `ui.draw`
--   - no hidden retained widget graph exists

local schema = require("ui.asdl")
local hit = require("ui.hit")
local draw = require("ui.draw")

local T = schema.T

local session = { T = T, schema = schema, hit_reducer = hit, draw_reducer = draw }

local type = type
local setmetatable = setmetatable

local POINTER_IDLE     = T.Interact.Idle
local POINTER_HOVERED  = T.Interact.Hovered
local POINTER_PRESSED  = T.Interact.Pressed
local POINTER_DRAGGING = T.Interact.Dragging

local FOCUS_BLURRED = T.Interact.Blurred
local FOCUS_FOCUSED = T.Interact.Focused

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
local PAYLOAD_NUM_MT = getmetatable(T.Msg.Num(0))
local PAYLOAD_BOOL_MT = getmetatable(T.Msg.Bool(false))
local PAYLOAD_TEXT_MT = getmetatable(T.Msg.Text(""))
local PAYLOAD_PAIR_MT = getmetatable(T.Msg.Pair(0, 0))

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

local function new_measure_cache()
    return setmetatable({}, { __mode = "k" })
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
    if payload == nil then
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
        local mt = getmetatable(payload)
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

local Session = {}
Session.__index = Session
session.Session = Session

function session.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Session)
    self.state = opts.state or session.state()
    self.backend = opts.backend
    self.measure_cache = opts.measure_cache or new_measure_cache()
    self.prune_dead_widgets = opts.prune_dead_widgets ~= false
    self._messages = {}
    self._seen_keys = {}
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
        measure_cache = opts.measure_cache or self.measure_cache,
        text_measure = opts.text_measure,
        font_height = opts.font_height,
        measure_stats = opts.measure_stats,
        text_draw = opts.text_draw,
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
    if id ~= nil and id ~= "" then
        self:emit(KIND_FOCUS, id)
    end
    return self
end

function Session:get_state()
    return self.state
end

function Session:set_state(state)
    self.state = state or session.state()
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

function Session:clear_measure_cache()
    for k in pairs(self.measure_cache) do
        self.measure_cache[k] = nil
    end
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
    return self
end

function Session:blur()
    self.state.focused = nil
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

function Session:draw(node, opts)
    opts = opts or {}
    local frame = assert(opts.frame, "ui.session:draw expected opts.frame")
    local backend = opts.backend or self.backend
    if not backend then
        return self
    end
    self.stats.draws = self.stats.draws + 1
    draw.draw(node, frame, reducer_opts(self, opts, backend))
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

    local prev_hot = self.state.hot
    local hovered = prev_hot
    local x, y = input_xy(input)
    if do_pick and x ~= nil and y ~= nil then
        hovered = self:hit(node, {
            frame = frame,
            x = x,
            y = y,
            state = opts.state,
            hot = opts.hot,
            measure = opts.measure,
            measure_cache = opts.measure_cache,
            text_measure = opts.text_measure,
            font_height = opts.font_height,
            measure_stats = opts.measure_stats,
        })
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

    local sx, sy = input_scroll(input)
    if hovered ~= nil and ((sx ~= nil and sx ~= 0) or (sy ~= nil and sy ~= 0)) then
        self:emit(KIND_SCROLL, hovered, { sx or 0, sy or 0 })
    end

    if do_draw then
        self:draw(node, {
            frame = frame,
            backend = opts.backend,
            state = opts.state,
            hot = opts.hot,
            runtime = opts.runtime,
            env = opts.env,
            measure = opts.measure,
            measure_cache = opts.measure_cache,
            text_measure = opts.text_measure,
            font_height = opts.font_height,
            measure_stats = opts.measure_stats,
            text_draw = opts.text_draw,
        })
        if opts.overlay ~= nil then
            self:draw_paint(opts.overlay, {
                frame = frame,
                backend = opts.backend,
                state = opts.state,
                hot = opts.hot,
                runtime = opts.runtime,
                env = opts.env,
                measure = opts.measure,
                measure_cache = opts.measure_cache,
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
