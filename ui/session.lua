local text = require("ui.text")

local M = {}

local function first_window(session)
    local id = session.order[1]
    if id == nil then return nil end
    return session.windows[id]
end

local function remove_order(session, window_id)
    local order = session.order
    for i = 1, #order do
        if order[i] == window_id then
            table.remove(order, i)
            return
        end
    end
end

local function env_number(name)
    local value = os.getenv(name)
    if value == nil or value == "" then return nil end
    return tonumber(value)
end

local function clamp_nonnegative(n)
    if n == nil then return nil end
    if n < 0 then return 0 end
    return n
end

local function soonest_redraw_at(session)
    local soonest = nil
    for i = 1, #session.order do
        local window = session.windows[session.order[i]]
        if window ~= nil and window.redraw_at_ms ~= nil then
            if soonest == nil or window.redraw_at_ms < soonest then
                soonest = window.redraw_at_ms
            end
        end
    end
    return soonest
end

local function arm_due_redraws(session, now_ms)
    for i = 1, #session.order do
        local window = session.windows[session.order[i]]
        if window ~= nil and window.redraw_at_ms ~= nil and window.redraw_at_ms <= now_ms then
            window.redraw_at_ms = nil
            window.needs_redraw = true
        end
    end
end

function M.new(opts)
    opts = opts or {}

    local backend = opts.backend
    if backend == nil then
        error("ui.session.new requires opts.backend", 2)
    end

    local shared_text_system = opts.text_system
    local own_text_system = false
    local text_key = opts.text_key
    local text_registered = false
    local closed = false

    if shared_text_system == nil and opts.shared_text_system ~= false and backend.new_text_system ~= nil then
        shared_text_system = backend.new_text_system {
            fonts = opts.fonts,
            resolve_font = opts.resolve_font,
            default_font = opts.default_font,
            direction = opts.direction,
            script = opts.script,
            language = opts.language,
            wrap_whitespace_visible = opts.wrap_whitespace_visible,
        }
        own_text_system = shared_text_system ~= nil
    end

    if text_key ~= nil and shared_text_system ~= nil then
        text.register(text_key, shared_text_system)
        text_registered = true
    end

    local self = {
        backend = backend,
        windows = {},
        order = {},
        text_system = shared_text_system,
        text_key = text_key,
        redraw_mode = opts.redraw_mode or "always",
        frame_delay_ms = opts.frame_delay_ms or 8,
        running = false,
        stop_requested = false,
        dt_ms = 0,
    }

    function self:get_window(window_id)
        return self.windows[window_id]
    end

    function self:list_windows()
        local out = {}
        for i = 1, #self.order do
            out[i] = self.windows[self.order[i]]
        end
        return out
    end

    function self:first_window()
        return first_window(self)
    end

    function self:now_ms()
        local win = first_window(self)
        if win ~= nil then
            return win.host:now_ms()
        end
        return 0
    end

    function self:delay(ms)
        local win = first_window(self)
        if win ~= nil then
            return win.host:delay(ms)
        end
    end

    function self:request_redraw(window_or_id)
        local window = window_or_id
        if type(window_or_id) ~= "table" then
            window = self.windows[window_or_id]
        end
        if window ~= nil then
            window.needs_redraw = true
        end
    end

    function self:request_redraw_at(window_or_id, when_ms)
        local window = window_or_id
        if type(window_or_id) ~= "table" then
            window = self.windows[window_or_id]
        end
        if window == nil then return end
        if when_ms == nil then
            window.redraw_at_ms = nil
            return
        end
        if when_ms <= self:now_ms() then
            window.redraw_at_ms = nil
            window.needs_redraw = true
            return
        end
        if window.redraw_at_ms == nil or when_ms < window.redraw_at_ms then
            window.redraw_at_ms = when_ms
        end
    end

    function self:request_redraw_after(window_or_id, delay_ms)
        local window = window_or_id
        if type(window_or_id) ~= "table" then
            window = self.windows[window_or_id]
        end
        if window == nil then return end
        delay_ms = clamp_nonnegative(delay_ms)
        if delay_ms == nil then
            window.redraw_at_ms = nil
            return
        end
        if delay_ms == 0 then
            window.redraw_at_ms = nil
            window.needs_redraw = true
            return
        end
        self:request_redraw_at(window, self:now_ms() + delay_ms)
    end

    function self:cancel_redraw(window_or_id)
        local window = window_or_id
        if type(window_or_id) ~= "table" then
            window = self.windows[window_or_id]
        end
        if window ~= nil then
            window.redraw_at_ms = nil
        end
    end

    function self:request_all_redraw()
        for i = 1, #self.order do
            local win = self.windows[self.order[i]]
            if win ~= nil then
                win.needs_redraw = true
            end
        end
    end

    function self:request_all_redraw_after(delay_ms)
        for i = 1, #self.order do
            local win = self.windows[self.order[i]]
            if win ~= nil then
                self:request_redraw_after(win, delay_ms)
            end
        end
    end

    function self:create_window(spec)
        spec = spec or {}

        if backend.new_host == nil then
            error("ui.session: backend.new_host is required", 2)
        end

        local host = spec.host or backend.new_host {
            title = spec.title or opts.title,
            width = spec.width or opts.width,
            height = spec.height or opts.height,
            window_flags = spec.window_flags or opts.window_flags,
            vsync = spec.vsync,
            fonts = spec.fonts or opts.fonts,
            resolve_font = spec.resolve_font or opts.resolve_font,
            default_font = spec.default_font or opts.default_font,
            direction = spec.direction or opts.direction,
            script = spec.script or opts.script,
            language = spec.language or opts.language,
            wrap_whitespace_visible = spec.wrap_whitespace_visible,
            text_system = spec.text_system ~= nil and spec.text_system or shared_text_system,
        }

        local window = {
            session = self,
            host = host,
            window_id = host.window_id,
            state = spec.state,
            userdata = spec.userdata,
            title = spec.title,
            needs_redraw = spec.needs_redraw ~= false,
            redraw_on_event = spec.redraw_on_event ~= false,
            auto_close = spec.auto_close ~= false,
            on_init = spec.on_init or spec.init or opts.window_init,
            on_event = spec.on_event or spec.event or opts.window_event,
            on_update = spec.on_update or spec.update or opts.window_update,
            on_draw = spec.on_draw or spec.draw or opts.window_draw,
            on_close = spec.on_close or spec.close or opts.window_close,
            redraw_at_ms = nil,
        }

        function window:request_redraw()
            self.needs_redraw = true
        end

        function window:request_redraw_at(when_ms)
            return self.session:request_redraw_at(self, when_ms)
        end

        function window:request_redraw_after(delay_ms)
            return self.session:request_redraw_after(self, delay_ms)
        end

        function window:cancel_redraw()
            return self.session:cancel_redraw(self)
        end

        function window:close()
            return self.session:close_window(self.window_id)
        end

        self.windows[window.window_id] = window
        self.order[#self.order + 1] = window.window_id

        if window.on_init ~= nil then
            window.on_init(self, window)
        end

        return window
    end

    function self:close_window(window_or_id)
        local window = window_or_id
        if type(window_or_id) ~= "table" then
            window = self.windows[window_or_id]
        end
        if window == nil then return end

        local window_id = window.window_id
        if self.windows[window_id] == nil then return end

        self.windows[window_id] = nil
        remove_order(self, window_id)

        if window.on_close ~= nil then
            window.on_close(self, window)
        end
        if window.host ~= nil then
            window.host:close()
        end
    end

    function self:stop()
        self.stop_requested = true
    end

    function self:dispatch_event(ev)
        if opts.on_global_event ~= nil then
            opts.on_global_event(self, ev)
        end

        if ev.type == "quit" then
            self:stop()
            return
        end

        local window = ev.window_id ~= nil and self.windows[ev.window_id] or nil
        if window == nil then
            return
        end

        if window.on_event ~= nil then
            window.on_event(self, window, ev)
        end

        if self.windows[window.window_id] == nil then
            return
        end

        if ev.type == "window_close_requested" and window.auto_close then
            self:close_window(window.window_id)
            return
        end

        if window.redraw_on_event then
            window.needs_redraw = true
        end
    end

    function self:poll_events()
        if backend.poll_events == nil then
            return {}
        end
        return backend.poll_events()
    end

    function self:update(dt_ms)
        self.dt_ms = dt_ms or 0
        arm_due_redraws(self, self:now_ms())

        if opts.on_tick ~= nil then
            opts.on_tick(self, self.dt_ms)
        end

        for i = 1, #self.order do
            local window = self.windows[self.order[i]]
            if window ~= nil and window.on_update ~= nil then
                local changed = window.on_update(self, window, self.dt_ms)
                if changed then
                    window.needs_redraw = true
                end
            end
        end
    end

    function self:draw()
        arm_due_redraws(self, self:now_ms())
        local always = self.redraw_mode ~= "dirty"
        for i = 1, #self.order do
            local window = self.windows[self.order[i]]
            if window ~= nil and window.on_draw ~= nil and (always or window.needs_redraw) then
                window.redraw_at_ms = nil
                window.on_draw(self, window)
                if self.windows[window.window_id] ~= nil then
                    window.needs_redraw = false
                end
            end
        end
    end

    function self:step(dt_ms)
        local events = self:poll_events()
        for i = 1, #events do
            self:dispatch_event(events[i])
            if self.stop_requested then break end
        end
        if not self.stop_requested then
            self:update(dt_ms)
            self:draw()
            if opts.on_idle ~= nil then
                opts.on_idle(self)
            end
        end
        return events
    end

    function self:run(run_opts)
        run_opts = run_opts or {}
        if self.running then
            error("ui.session: session is already running", 2)
        end

        local auto_quit_ms = run_opts.auto_quit_ms
        if auto_quit_ms == nil then auto_quit_ms = opts.auto_quit_ms end
        if auto_quit_ms == nil then auto_quit_ms = env_number("AUTO_QUIT_MS") end

        local frame_delay_ms = run_opts.frame_delay_ms
        if frame_delay_ms == nil then frame_delay_ms = self.frame_delay_ms end

        local close_on_exit = run_opts.close_on_exit
        if close_on_exit == nil then close_on_exit = true end

        local started_ms = self:now_ms()
        local last_ms = started_ms

        self.running = true
        self.stop_requested = false

        while not self.stop_requested and next(self.windows) ~= nil do
            local now = self:now_ms()
            local dt_ms = now - last_ms
            last_ms = now

            self:step(dt_ms)

            if auto_quit_ms ~= nil and self:now_ms() - started_ms >= auto_quit_ms then
                self.stop_requested = true
                break
            end

            local delay_ms = frame_delay_ms
            local redraw_at_ms = soonest_redraw_at(self)
            if redraw_at_ms ~= nil then
                local until_redraw_ms = clamp_nonnegative(redraw_at_ms - self:now_ms())
                if delay_ms == nil or until_redraw_ms < delay_ms then
                    delay_ms = until_redraw_ms
                end
            end

            if delay_ms ~= nil and delay_ms > 0 then
                self:delay(delay_ms)
            end
        end

        self.running = false

        if close_on_exit then
            self:close()
        end
    end

    function self:close()
        if closed then return end
        closed = true
        self.running = false
        self.stop_requested = true

        while true do
            local window_id = next(self.windows)
            if window_id == nil then break end
            self:close_window(window_id)
        end

        if text_registered then
            text.unregister(text_key)
            text_registered = false
        end
        if own_text_system and shared_text_system ~= nil and shared_text_system.close ~= nil then
            shared_text_system:close()
            shared_text_system = nil
            self.text_system = nil
        end
    end

    return self
end

return M
