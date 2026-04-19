local bit = require("bit")
local input = require("ui.input")
local sdl3 = require("ui._sdl3")
local runtime_sdl3 = require("ui.runtime_sdl3")
local text_sdl3 = require("ui.text_sdl3")

local ffi = sdl3.ffi
local sdl = sdl3.sdl

local M = {}

local function round(n)
    if n >= 0 then return math.floor(n + 0.5) end
    return math.ceil(n - 0.5)
end

local function rgba8_bytes(rgba8, opacity)
    opacity = opacity or 1
    local a = ((rgba8 % 256) / 255) * opacity
    rgba8 = math.floor(rgba8 / 256)
    local b = rgba8 % 256
    rgba8 = math.floor(rgba8 / 256)
    local g = rgba8 % 256
    rgba8 = math.floor(rgba8 / 256)
    local r = rgba8 % 256
    return r, g, b, round(a * 255)
end

local function frect(x, y, w, h)
    local r = ffi.new("SDL_FRect[1]")
    r[0].x = x
    r[0].y = y
    r[0].w = w
    r[0].h = h
    return r
end

local function normalize_button(button)
    if button == 1 then return input.ButtonLeft end
    if button == 2 then return input.ButtonMiddle end
    if button == 3 then return input.ButtonRight end
    if button == 4 then return input.ButtonX1 end
    if button == 5 then return input.ButtonX2 end
    return button
end

local function normalize_key(key)
    if key == sdl3.SDLK_RETURN then return input.KeyReturn end
    if key == sdl3.SDLK_ESCAPE then return input.KeyEscape end
    if key == sdl3.SDLK_BACKSPACE then return input.KeyBackspace end
    if key == sdl3.SDLK_DELETE then return input.KeyDelete end
    if key == sdl3.SDLK_HOME then return input.KeyHome end
    if key == sdl3.SDLK_END then return input.KeyEnd end
    if key == sdl3.SDLK_PAGEUP then return input.KeyPageUp end
    if key == sdl3.SDLK_PAGEDOWN then return input.KeyPageDown end
    if key == sdl3.SDLK_LEFT then return input.KeyLeft end
    if key == sdl3.SDLK_RIGHT then return input.KeyRight end
    if key == sdl3.SDLK_UP then return input.KeyUp end
    if key == sdl3.SDLK_DOWN then return input.KeyDown end
    if key == sdl3.SDLK_A then return input.KeyA end
    if key == sdl3.SDLK_C then return input.KeyC end
    if key == sdl3.SDLK_V then return input.KeyV end
    if key == sdl3.SDLK_X then return input.KeyX end
    return key
end

local function event_window_id(ev, t)
    if t == sdl3.SDL_EVENT_WINDOW_CLOSE_REQUESTED
    or t == sdl3.SDL_EVENT_WINDOW_RESIZED
    or t == sdl3.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED
    or t == sdl3.SDL_EVENT_WINDOW_FOCUS_GAINED
    or t == sdl3.SDL_EVENT_WINDOW_FOCUS_LOST then
        return tonumber(ev.window.windowID)
    end
    if t == sdl3.SDL_EVENT_KEY_DOWN or t == sdl3.SDL_EVENT_KEY_UP then
        return tonumber(ev.key.windowID)
    end
    if t == sdl3.SDL_EVENT_TEXT_INPUT then
        return tonumber(ev.text.windowID)
    end
    if t == sdl3.SDL_EVENT_TEXT_EDITING then
        return tonumber(ev.edit.windowID)
    end
    if t == sdl3.SDL_EVENT_MOUSE_MOTION then
        return tonumber(ev.motion.windowID)
    end
    if t == sdl3.SDL_EVENT_MOUSE_BUTTON_DOWN or t == sdl3.SDL_EVENT_MOUSE_BUTTON_UP then
        return tonumber(ev.button.windowID)
    end
    if t == sdl3.SDL_EVENT_MOUSE_WHEEL then
        return tonumber(ev.wheel.windowID)
    end
    return nil
end

local function normalize_event(ev)
    local t = tonumber(ev.type)
    local window_id = event_window_id(ev, t)

    if t == sdl3.SDL_EVENT_QUIT then
        return { type = "quit" }
    elseif t == sdl3.SDL_EVENT_WINDOW_CLOSE_REQUESTED then
        return { type = "window_close_requested", window_id = window_id }
    elseif t == sdl3.SDL_EVENT_WINDOW_RESIZED or t == sdl3.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED then
        return {
            type = "window_resized",
            window_id = window_id,
            w = tonumber(ev.window.data1),
            h = tonumber(ev.window.data2),
        }
    elseif t == sdl3.SDL_EVENT_WINDOW_FOCUS_GAINED then
        return { type = "focus_gained", window_id = window_id }
    elseif t == sdl3.SDL_EVENT_WINDOW_FOCUS_LOST then
        return { type = "focus_lost", window_id = window_id }
    elseif t == sdl3.SDL_EVENT_MOUSE_MOTION then
        local mod = tonumber(sdl.SDL_GetModState())
        return {
            type = "mouse_moved",
            window_id = window_id,
            x = tonumber(ev.motion.x),
            y = tonumber(ev.motion.y),
            dx = tonumber(ev.motion.xrel),
            dy = tonumber(ev.motion.yrel),
            shift = bit.band(mod, sdl3.SDL_KMOD_SHIFT) ~= 0,
            ctrl = bit.band(mod, sdl3.SDL_KMOD_CTRL) ~= 0,
        }
    elseif t == sdl3.SDL_EVENT_MOUSE_BUTTON_DOWN or t == sdl3.SDL_EVENT_MOUSE_BUTTON_UP then
        local mod = tonumber(sdl.SDL_GetModState())
        return {
            type = t == sdl3.SDL_EVENT_MOUSE_BUTTON_DOWN and "mouse_pressed" or "mouse_released",
            window_id = window_id,
            button = normalize_button(tonumber(ev.button.button)),
            x = tonumber(ev.button.x),
            y = tonumber(ev.button.y),
            clicks = tonumber(ev.button.clicks),
            shift = bit.band(mod, sdl3.SDL_KMOD_SHIFT) ~= 0,
            ctrl = bit.band(mod, sdl3.SDL_KMOD_CTRL) ~= 0,
        }
    elseif t == sdl3.SDL_EVENT_MOUSE_WHEEL then
        local mod = tonumber(sdl.SDL_GetModState())
        return {
            type = "mouse_wheel",
            window_id = window_id,
            dx = tonumber(ev.wheel.x),
            dy = tonumber(ev.wheel.y),
            integer_dx = tonumber(ev.wheel.integer_x),
            integer_dy = tonumber(ev.wheel.integer_y),
            x = tonumber(ev.wheel.mouse_x),
            y = tonumber(ev.wheel.mouse_y),
            shift = bit.band(mod, sdl3.SDL_KMOD_SHIFT) ~= 0,
            ctrl = bit.band(mod, sdl3.SDL_KMOD_CTRL) ~= 0,
        }
    elseif t == sdl3.SDL_EVENT_TEXT_INPUT then
        return {
            type = "text_input",
            window_id = window_id,
            text = ev.text.text ~= nil and ffi.string(ev.text.text) or "",
        }
    elseif t == sdl3.SDL_EVENT_TEXT_EDITING then
        return {
            type = "text_editing",
            window_id = window_id,
            text = ev.edit.text ~= nil and ffi.string(ev.edit.text) or "",
            start = tonumber(ev.edit.start),
            length = tonumber(ev.edit.length),
        }
    elseif t == sdl3.SDL_EVENT_KEY_DOWN or t == sdl3.SDL_EVENT_KEY_UP then
        local mod = tonumber(ev.key.mod)
        return {
            type = t == sdl3.SDL_EVENT_KEY_DOWN and "key_down" or "key_up",
            window_id = window_id,
            key = normalize_key(tonumber(ev.key.key)),
            mod = mod,
            repeat_ = tonumber(ev.key["repeat"]),
            shift = bit.band(mod, sdl3.SDL_KMOD_SHIFT) ~= 0,
            ctrl = bit.band(mod, sdl3.SDL_KMOD_CTRL) ~= 0,
        }
    end

    return nil
end

function M.poll_events()
    local out = {}
    local event = ffi.new("SDL_Event[1]")
    while sdl.SDL_PollEvent(event) ~= 0 do
        local normalized = normalize_event(event[0])
        if normalized ~= nil then
            out[#out + 1] = normalized
        end
    end
    return out
end

function M.filter_events(host_or_window_id, events)
    local window_id = host_or_window_id
    if type(host_or_window_id) == "table" then
        window_id = host_or_window_id.window_id
    end

    local out = {}
    for i = 1, #events do
        local ev = events[i]
        if ev.window_id == nil or ev.window_id == window_id then
            out[#out + 1] = ev
        end
    end
    return out
end

function M.partition_events(events)
    local out = { global = {} }
    for i = 1, #events do
        local ev = events[i]
        local key = ev.window_id
        if key == nil then
            out.global[#out.global + 1] = ev
        else
            local bucket = out[key]
            if bucket == nil then
                bucket = {}
                out[key] = bucket
            end
            bucket[#bucket + 1] = ev
        end
    end
    return out
end

function M.new(opts)
    opts = opts or {}
    sdl3.ensure_sdl(opts.init_flags or sdl3.SDL_INIT_VIDEO)

    local title = opts.title or "gps.lua SDL3 host"
    local width = opts.width or 1280
    local height = opts.height or 800
    local window_flags = opts.window_flags or 0

    local window_p = ffi.new("SDL_Window*[1]")
    local renderer_p = ffi.new("SDL_Renderer*[1]")
    if sdl.SDL_CreateWindowAndRenderer(title, width, height, window_flags, window_p, renderer_p) == 0 then
        sdl3.err("ui.host_sdl3: SDL_CreateWindowAndRenderer failed")
    end

    local window = window_p[0]
    local renderer = renderer_p[0]
    local window_id = tonumber(sdl.SDL_GetWindowID(window))

    if opts.vsync ~= nil then
        if sdl.SDL_SetRenderVSync(renderer, opts.vsync and 1 or 0) == 0 then
            sdl3.err("ui.host_sdl3: SDL_SetRenderVSync failed")
        end
    end

    local driver = runtime_sdl3.new {
        renderer = renderer,
        fonts = opts.fonts,
        resolve_font = opts.resolve_font,
        default_font = opts.default_font,
    }

    local text_system = opts.text_system or text_sdl3.new {
        fonts = opts.fonts,
        resolve_font = opts.resolve_font,
        default_font = opts.default_font,
        direction = opts.direction,
        script = opts.script,
        language = opts.language,
        wrap_whitespace_visible = opts.wrap_whitespace_visible,
    }

    local closed = false
    local self = {
        window = window,
        renderer = renderer,
        window_id = window_id,
        driver = driver,
        text_system = text_system,
    }

    function self:id()
        return window_id
    end

    function self:matches_event(ev)
        return ev ~= nil and (ev.window_id == nil or ev.window_id == window_id)
    end

    function self:filter_events(events)
        return M.filter_events(window_id, events)
    end

    function self:poll_events()
        return M.filter_events(window_id, M.poll_events())
    end

    function self:size()
        local w = ffi.new("int[1]")
        local h = ffi.new("int[1]")
        if sdl.SDL_GetRenderOutputSize(renderer, w, h) == 0 then
            sdl3.err("ui.host_sdl3: SDL_GetRenderOutputSize failed")
        end
        return tonumber(w[0]), tonumber(h[0])
    end

    function self:now_ms()
        return tonumber(sdl.SDL_GetTicks())
    end

    function self:begin_frame(clear_rgba8)
        if clear_rgba8 ~= nil then
            local r, g, b, a = rgba8_bytes(clear_rgba8, 1)
            if sdl.SDL_SetRenderDrawColor(renderer, r, g, b, a) == 0 then
                sdl3.err("ui.host_sdl3: SDL_SetRenderDrawColor failed")
            end
        end
        if sdl.SDL_RenderClear(renderer) == 0 then
            sdl3.err("ui.host_sdl3: SDL_RenderClear failed")
        end
        if driver and driver.reset then
            driver:reset()
        end
    end

    function self:present()
        if sdl.SDL_RenderPresent(renderer) == 0 then
            sdl3.err("ui.host_sdl3: SDL_RenderPresent failed")
        end
    end

    function self:delay(ms)
        sdl.SDL_Delay(ms or 0)
    end

    function self:get_mod_state()
        return tonumber(sdl.SDL_GetModState())
    end

    function self:set_text_input(enabled)
        if enabled then
            if sdl.SDL_StartTextInput(window) == 0 then
                sdl3.err("ui.host_sdl3: SDL_StartTextInput failed")
            end
        else
            if sdl.SDL_StopTextInput(window) == 0 then
                sdl3.err("ui.host_sdl3: SDL_StopTextInput failed")
            end
        end
    end

    function self:set_text_input_rect(x, y, w, h, cursor)
        local r = ffi.new("SDL_Rect[1]")
        r[0].x = round(x)
        r[0].y = round(y)
        r[0].w = round(w)
        r[0].h = round(h)
        if sdl.SDL_SetTextInputArea(window, r, round(cursor or 0)) == 0 then
            sdl3.err("ui.host_sdl3: SDL_SetTextInputArea failed")
        end
    end

    function self:set_clipboard_text(text)
        if sdl.SDL_SetClipboardText(text or "") == 0 then
            sdl3.err("ui.host_sdl3: SDL_SetClipboardText failed")
        end
    end

    function self:get_clipboard_text()
        local ptr = sdl.SDL_GetClipboardText()
        if ptr == nil then return "" end
        local value = ffi.string(ptr)
        sdl.SDL_free(ptr)
        return value
    end

    function self:has_clipboard_text()
        return sdl.SDL_HasClipboardText() ~= 0
    end

    function self:fill_rect(x, y, w, h, rgba8, opacity)
        local r, g, b, a = rgba8_bytes(rgba8, opacity or 1)
        if sdl.SDL_SetRenderDrawColor(renderer, r, g, b, a) == 0 then
            sdl3.err("ui.host_sdl3: SDL_SetRenderDrawColor fill failed")
        end
        if sdl.SDL_RenderFillRect(renderer, frect(x, y, w, h)) == 0 then
            sdl3.err("ui.host_sdl3: SDL_RenderFillRect failed")
        end
    end

    function self:stroke_rect(x, y, w, h, rgba8, opacity)
        local r, g, b, a = rgba8_bytes(rgba8, opacity or 1)
        if sdl.SDL_SetRenderDrawColor(renderer, r, g, b, a) == 0 then
            sdl3.err("ui.host_sdl3: SDL_SetRenderDrawColor stroke failed")
        end
        if sdl.SDL_RenderRect(renderer, frect(x, y, w, h)) == 0 then
            sdl3.err("ui.host_sdl3: SDL_RenderRect failed")
        end
    end

    function self:draw_line(x1, y1, x2, y2, rgba8, opacity)
        local r, g, b, a = rgba8_bytes(rgba8, opacity or 1)
        if sdl.SDL_SetRenderDrawColor(renderer, r, g, b, a) == 0 then
            sdl3.err("ui.host_sdl3: SDL_SetRenderDrawColor line failed")
        end
        if sdl.SDL_RenderLine(renderer, x1, y1, x2, y2) == 0 then
            sdl3.err("ui.host_sdl3: SDL_RenderLine failed")
        end
    end

    function self:close()
        if closed then return end
        closed = true
        if driver and driver.close then driver:close() end
        if text_system and text_system.close and opts.text_system == nil then text_system:close() end
        sdl.SDL_DestroyRenderer(renderer)
        sdl.SDL_DestroyWindow(window)
        sdl3.release_sdl()
    end

    return self
end

M.T = require("ui.asdl").T
M.input = input
M.constants = input

return M
