local ffi = require("ffi")

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function script_path()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then return src:sub(2) end
    return "examples/ui7/main.t"
end

local SCRIPT_FILE = script_path()
local SCRIPT_DIR = SCRIPT_FILE:match("^(.*)/[^/]+$") or "."
local ROOT_DIR = SCRIPT_DIR .. "/../.."
package.path = table.concat({
    ROOT_DIR .. "/?.lua", ROOT_DIR .. "/?/init.lua", package.path
}, ";")

local function has_flag(name)
    local args = rawget(_G, "arg") or {}
    for i = 1, #args do
        if args[i] == name then return true end
    end
    return false
end

local function new_headless_host()
    local function mkfont(size)
        local lh = 1
        return {
            getWidth = function(_, s) return #s * math.floor(size * 0.6) end,
            getHeight = function() return size end,
            getLineHeight = function() return lh end,
            setLineHeight = function(_, v) lh = v end,
            getBaseline = function() return math.floor(size * 0.8) end,
        }
    end

    local current_font
    local renderer = {}

    function renderer:set_background_color(...) end
    function renderer:new_font(size) return mkfont(size) end
    function renderer:set_font(font) current_font = font end
    function renderer:get_default_font() return current_font end
    function renderer:get_dimensions() return 1100, 700 end
    function renderer:set_color(...) end
    function renderer:fill_rect(...) end
    function renderer:stroke_rect(...) end
    function renderer:draw_line(...) end
    function renderer:draw_text(...) end
    function renderer:push_clip(...) end
    function renderer:pop_clip() end
    function renderer:push_transform(...) end
    function renderer:pop_transform() end

    local host = {
        renderer = renderer,
        new_font = function(size) return renderer:new_font(size) end,
        get_dimensions = function() return renderer:get_dimensions() end,
        set_background_color = function(r, g, b, a) renderer:set_background_color(r, g, b, a) end,
        is_key_down = function(...) return false end,
        quit = function() end,
    }

    function host.run(app)
        app.init(host)
        if app.update then app.update(0.016) end
        if app.draw then app.draw() end
    end

    return host
end

local function new_sdl_host()
    local function first_existing(candidates)
        for i = 1, #candidates do
            local path = candidates[i]
            if path and path ~= "" then
                if path:find("/") then
                    if file_exists(path) then return path end
                else
                    return path
                end
            end
        end
        return nil
    end

    terralib.linklibrary(assert(first_existing({ "/lib64/libSDL3.so", "/lib/libSDL3.so", "libSDL3.so" })))
    terralib.linklibrary(assert(first_existing({ "/lib64/libSDL3_ttf.so", "/lib/libSDL3_ttf.so", "libSDL3_ttf.so" })))
    terralib.linklibrary(assert(first_existing({ "/lib64/libGL.so", "/lib/libGL.so", "libGL.so" })))

    local C = terralib.includecstring [[
        #define SDL_MAIN_HANDLED
        #include <SDL3/SDL.h>
        #include <SDL3/SDL_opengl.h>
        #include <SDL3_ttf/SDL_ttf.h>
    ]]

    -- Terra imports most SDL constants fine, but these window flags are uint64
    -- preprocessor macros and do not show up through includec on this system.
    local SDL_WINDOW_OPENGL = 0x0000000000000002
    local SDL_WINDOW_RESIZABLE = 0x0000000000000020

    local function sdl_error(prefix)
        return string.format("%s: %s", prefix, ffi.string(C.SDL_GetError()))
    end

    local function check(ok, prefix)
        if not ok then error(sdl_error(prefix), 2) end
    end

    local function find_font_path()
        local env_font = os.getenv("UI7_FONT")
        if env_font and file_exists(env_font) then return env_font end
        local candidates = {
            "/usr/share/fonts/liberation-sans-fonts/LiberationSans-Regular.ttf",
            "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/google-noto/NotoSans-Regular.ttf",
        }
        for i = 1, #candidates do
            if file_exists(candidates[i]) then return candidates[i] end
        end
        error("ui7/main.t: could not find a TTF font; set UI7_FONT=/path/to/font.ttf", 2)
    end

    check(C.SDL_Init(C.SDL_INIT_VIDEO), "SDL_Init")
    check(C.TTF_Init(), "TTF_Init")

    check(C.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_PROFILE_MASK, C.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY), "SDL_GL_SetAttribute(profile)")
    check(C.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_MAJOR_VERSION, 2), "SDL_GL_SetAttribute(major)")
    check(C.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_MINOR_VERSION, 1), "SDL_GL_SetAttribute(minor)")
    check(C.SDL_GL_SetAttribute(C.SDL_GL_DOUBLEBUFFER, 1), "SDL_GL_SetAttribute(doublebuffer)")
    check(C.SDL_GL_SetAttribute(C.SDL_GL_RED_SIZE, 8), "SDL_GL_SetAttribute(red)")
    check(C.SDL_GL_SetAttribute(C.SDL_GL_GREEN_SIZE, 8), "SDL_GL_SetAttribute(green)")
    check(C.SDL_GL_SetAttribute(C.SDL_GL_BLUE_SIZE, 8), "SDL_GL_SetAttribute(blue)")
    check(C.SDL_GL_SetAttribute(C.SDL_GL_ALPHA_SIZE, 8), "SDL_GL_SetAttribute(alpha)")

    local window = C.SDL_CreateWindow("ui7 - SDL3 + OpenGL + Terra", 1100, 700,
        SDL_WINDOW_OPENGL + SDL_WINDOW_RESIZABLE)
    if window == nil then error(sdl_error("SDL_CreateWindow"), 2) end

    local glctx = C.SDL_GL_CreateContext(window)
    if glctx == nil then error(sdl_error("SDL_GL_CreateContext"), 2) end
    check(C.SDL_GL_MakeCurrent(window, glctx), "SDL_GL_MakeCurrent")
    C.SDL_GL_SetSwapInterval(1)

    local state = {
        window = window,
        glctx = glctx,
        running = true,
        font_path = find_font_path(),
        fonts = {},
        next_font_id = 1,
        current_font = nil,
        texture_cache = {},
        texture_cache_count = 0,
        texture_cache_age = 0,
        texture_cache_limit = 512,
        window_w = 1100,
        window_h = 700,
        bg = { 0.054, 0.067, 0.090, 1.0 },
        color = { 1, 1, 1, 1 },
        clip_stack = {},
        key_down = {},
    }

    local function clamp01(x)
        if x < 0 then return 0 end
        if x > 1 then return 1 end
        return x
    end

    local function update_window_size()
        local w = terralib.new(int[1])
        local h = terralib.new(int[1])
        check(C.SDL_GetWindowSize(state.window, w, h), "SDL_GetWindowSize")
        state.window_w = tonumber(w[0])
        state.window_h = tonumber(h[0])
    end
    update_window_size()

    local function split_lines(text)
        if text == "" then return { "" } end
        local out = {}
        local start = 1
        while true do
            local i = text:find("\n", start, true)
            if not i then
                out[#out + 1] = text:sub(start)
                break
            end
            out[#out + 1] = text:sub(start, i - 1)
            start = i + 1
        end
        return out
    end

    local function rgba_key(color)
        local r = math.floor(clamp01(color[1]) * 255 + 0.5)
        local g = math.floor(clamp01(color[2]) * 255 + 0.5)
        local b = math.floor(clamp01(color[3]) * 255 + 0.5)
        local a = math.floor(clamp01(color[4] or 1) * 255 + 0.5)
        return string.format("%02x%02x%02x%02x", r, g, b, a), r, g, b, a
    end

    local function destroy_texture(tex)
        local buf = terralib.new(C.GLuint[1])
        buf[0] = tex
        C.glDeleteTextures(1, buf)
    end

    local function evict_oldest_texture()
        local oldest_key, oldest_age = nil, nil
        for k, v in pairs(state.texture_cache) do
            if not oldest_age or v.age < oldest_age then
                oldest_key, oldest_age = k, v.age
            end
        end
        if oldest_key then
            local v = state.texture_cache[oldest_key]
            if v.tex and v.tex ~= 0 then destroy_texture(v.tex) end
            state.texture_cache[oldest_key] = nil
            state.texture_cache_count = math.max(0, state.texture_cache_count - 1)
        end
    end

    local function make_font(size)
        local handle = C.TTF_OpenFont(state.font_path, size)
        if handle == nil then error(sdl_error("TTF_OpenFont(" .. tostring(size) .. ")"), 2) end
        local font = {
            _id = state.next_font_id,
            _font = handle,
            _size = size,
            _line_height = 1,
        }
        state.next_font_id = state.next_font_id + 1

        function font:getWidth(s)
            local w = terralib.new(int[1])
            local h = terralib.new(int[1])
            if not C.TTF_GetStringSize(self._font, s, #s, w, h) then
                return #s * math.floor(self._size * 0.6)
            end
            return tonumber(w[0])
        end

        function font:getHeight()
            return tonumber(C.TTF_GetFontHeight(self._font))
        end

        function font:getBaseline()
            return tonumber(C.TTF_GetFontAscent(self._font))
        end

        function font:getLineHeight()
            return self._line_height
        end

        function font:setLineHeight(v)
            self._line_height = v
        end

        state.fonts[#state.fonts + 1] = font
        return font
    end

    local function get_text_texture(font, text, color)
        local key, r, g, b, a = rgba_key(color)
        local cache_key = table.concat({ tostring(font._id), key, text }, "\31")
        local hit = state.texture_cache[cache_key]
        if hit then
            state.texture_cache_age = state.texture_cache_age + 1
            hit.age = state.texture_cache_age
            return hit
        end
        if text == "" then
            state.texture_cache_age = state.texture_cache_age + 1
            hit = { tex = 0, w = 0, h = font:getHeight(), empty = true, age = state.texture_cache_age }
            state.texture_cache[cache_key] = hit
            state.texture_cache_count = state.texture_cache_count + 1
            if state.texture_cache_count > state.texture_cache_limit then evict_oldest_texture() end
            return hit
        end

        local fg = terralib.new(C.SDL_Color[1])
        fg[0].r, fg[0].g, fg[0].b, fg[0].a = r, g, b, a

        local surf = C.TTF_RenderText_Blended(font._font, text, #text, fg[0])
        if surf == nil then error(sdl_error("TTF_RenderText_Blended"), 2) end
        if surf.format ~= C.SDL_PIXELFORMAT_RGBA32 then
            local converted = C.SDL_ConvertSurface(surf, C.SDL_PIXELFORMAT_RGBA32)
            C.SDL_DestroySurface(surf)
            surf = converted
            if surf == nil then error(sdl_error("SDL_ConvertSurface"), 2) end
        end

        local texbuf = terralib.new(C.GLuint[1])
        C.glGenTextures(1, texbuf)
        local tex = tonumber(texbuf[0])
        C.glBindTexture(C.GL_TEXTURE_2D, tex)
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MIN_FILTER, C.GL_LINEAR)
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MAG_FILTER, C.GL_LINEAR)
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_WRAP_S, C.GL_CLAMP)
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_WRAP_T, C.GL_CLAMP)
        C.glPixelStorei(C.GL_UNPACK_ALIGNMENT, 1)
        C.glTexImage2D(C.GL_TEXTURE_2D, 0, C.GL_RGBA, surf.w, surf.h, 0, C.GL_RGBA, C.GL_UNSIGNED_BYTE, surf.pixels)
        C.glBindTexture(C.GL_TEXTURE_2D, 0)

        state.texture_cache_age = state.texture_cache_age + 1
        hit = { tex = tex, w = tonumber(surf.w), h = tonumber(surf.h), empty = false, age = state.texture_cache_age }
        state.texture_cache[cache_key] = hit
        state.texture_cache_count = state.texture_cache_count + 1
        if state.texture_cache_count > state.texture_cache_limit then evict_oldest_texture() end
        C.SDL_DestroySurface(surf)
        return hit
    end

    local function draw_textured_quad(tex, x, y, w, h)
        C.glEnable(C.GL_TEXTURE_2D)
        C.glBindTexture(C.GL_TEXTURE_2D, tex)
        C.glColor4f(1, 1, 1, 1)
        C.glBegin(C.GL_QUADS)
            C.glTexCoord2f(0, 0); C.glVertex2f(x, y)
            C.glTexCoord2f(1, 0); C.glVertex2f(x + w, y)
            C.glTexCoord2f(1, 1); C.glVertex2f(x + w, y + h)
            C.glTexCoord2f(0, 1); C.glVertex2f(x, y + h)
        C.glEnd()
        C.glBindTexture(C.GL_TEXTURE_2D, 0)
        C.glDisable(C.GL_TEXTURE_2D)
    end

    local function draw_text_block(text, x, y, width, align)
        local font = state.current_font
        if not font then return end
        local line_h = font:getHeight() * font:getLineHeight()
        local lines = split_lines(text)
        for i = 1, #lines do
            local line = lines[i]
            local dx = x
            if width and align ~= "left" and align ~= "justify" then
                local lw = font:getWidth(line)
                if align == "center" then dx = x + math.max(0, (width - lw) / 2)
                elseif align == "right" then dx = x + math.max(0, width - lw) end
            end
            if line ~= "" then
                local tex = get_text_texture(font, line, state.color)
                if not tex.empty then draw_textured_quad(tex.tex, dx, y + (i - 1) * line_h, tex.w, tex.h) end
            end
        end
    end

    local renderer = {}

    function renderer:set_background_color(r, g, b, a)
        state.bg[1], state.bg[2], state.bg[3], state.bg[4] = r or 0, g or 0, b or 0, a or 1
    end

    function renderer:new_font(size)
        return make_font(size)
    end

    function renderer:set_font(font)
        state.current_font = font
    end

    function renderer:get_default_font()
        return state.current_font
    end

    function renderer:get_dimensions()
        return state.window_w, state.window_h
    end

    function renderer:set_color(r, g, b, a)
        state.color[1], state.color[2], state.color[3], state.color[4] = r or 1, g or 1, b or 1, a or 1
        C.glColor4f(state.color[1], state.color[2], state.color[3], state.color[4])
    end

    function renderer:fill_rect(x, y, w, h)
        C.glDisable(C.GL_TEXTURE_2D)
        C.glBegin(C.GL_QUADS)
            C.glVertex2f(x, y)
            C.glVertex2f(x + w, y)
            C.glVertex2f(x + w, y + h)
            C.glVertex2f(x, y + h)
        C.glEnd()
    end

    function renderer:stroke_rect(x, y, w, h, thickness)
        C.glDisable(C.GL_TEXTURE_2D)
        C.glLineWidth(thickness or 1)
        C.glBegin(C.GL_LINE_LOOP)
            C.glVertex2f(x, y)
            C.glVertex2f(x + w, y)
            C.glVertex2f(x + w, y + h)
            C.glVertex2f(x, y + h)
        C.glEnd()
    end

    function renderer:draw_line(x1, y1, x2, y2, thickness)
        C.glDisable(C.GL_TEXTURE_2D)
        C.glLineWidth(thickness or 1)
        C.glBegin(C.GL_LINES)
            C.glVertex2f(x1, y1)
            C.glVertex2f(x2, y2)
        C.glEnd()
    end

    function renderer:draw_text(text, x, y, width, align)
        draw_text_block(text, x, y, width, align or "left")
    end

    function renderer:push_clip(x, y, w, h)
        state.clip_stack[#state.clip_stack + 1] = { x, y, w, h }
        C.glEnable(C.GL_SCISSOR_TEST)
        local sy = state.window_h - (y + h)
        C.glScissor(math.floor(x), math.floor(sy), math.floor(w), math.floor(h))
    end

    function renderer:pop_clip()
        state.clip_stack[#state.clip_stack] = nil
        local top = state.clip_stack[#state.clip_stack]
        if top then
            local sy = state.window_h - (top[2] + top[4])
            C.glEnable(C.GL_SCISSOR_TEST)
            C.glScissor(math.floor(top[1]), math.floor(sy), math.floor(top[3]), math.floor(top[4]))
        else
            C.glDisable(C.GL_SCISSOR_TEST)
        end
    end

    function renderer:push_transform(tx, ty)
        C.glMatrixMode(C.GL_MODELVIEW)
        C.glPushMatrix()
        C.glTranslatef(tx, ty, 0)
    end

    function renderer:pop_transform()
        C.glMatrixMode(C.GL_MODELVIEW)
        C.glPopMatrix()
    end

    local function set_projection()
        C.glViewport(0, 0, state.window_w, state.window_h)
        C.glMatrixMode(C.GL_PROJECTION)
        C.glLoadIdentity()
        C.glOrtho(0, state.window_w, state.window_h, 0, -1, 1)
        C.glMatrixMode(C.GL_MODELVIEW)
        C.glLoadIdentity()
    end

    local function begin_frame()
        update_window_size()
        state.clip_stack = {}
        set_projection()
        C.glDisable(C.GL_DEPTH_TEST)
        C.glDisable(C.GL_SCISSOR_TEST)
        C.glEnable(C.GL_BLEND)
        C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
        C.glClearColor(state.bg[1], state.bg[2], state.bg[3], state.bg[4])
        C.glClear(C.GL_COLOR_BUFFER_BIT)
        renderer:set_color(1, 1, 1, 1)
    end

    local function end_frame()
        C.glFlush()
        C.SDL_GL_SwapWindow(state.window)
    end

    local function shutdown()
        for _, tex in pairs(state.texture_cache) do
            if tex.tex and tex.tex ~= 0 then destroy_texture(tex.tex) end
        end
        for i = 1, #state.fonts do
            if state.fonts[i]._font ~= nil then C.TTF_CloseFont(state.fonts[i]._font) end
        end
        C.SDL_GL_DestroyContext(state.glctx)
        C.SDL_DestroyWindow(state.window)
        C.TTF_Quit()
        C.SDL_Quit()
    end

    local key_name = {
        [tonumber(C.SDL_SCANCODE_ESCAPE)] = "escape",
        [tonumber(C.SDL_SCANCODE_SPACE)] = "space",
        [tonumber(C.SDL_SCANCODE_UP)] = "up",
        [tonumber(C.SDL_SCANCODE_DOWN)] = "down",
        [tonumber(C.SDL_SCANCODE_M)] = "m",
        [tonumber(C.SDL_SCANCODE_S)] = "s",
        [tonumber(C.SDL_SCANCODE_R)] = "r",
        [tonumber(C.SDL_SCANCODE_Z)] = "z",
        [tonumber(C.SDL_SCANCODE_LCTRL)] = "lctrl",
        [tonumber(C.SDL_SCANCODE_RCTRL)] = "rctrl",
    }

    local mouse_button = {
        [tonumber(C.SDL_BUTTON_LEFT)] = 1,
        [tonumber(C.SDL_BUTTON_RIGHT)] = 2,
        [tonumber(C.SDL_BUTTON_MIDDLE)] = 3,
    }

    local host = {
        renderer = renderer,
        new_font = function(size) return renderer:new_font(size) end,
        get_dimensions = function() return renderer:get_dimensions() end,
        set_background_color = function(r, g, b, a) renderer:set_background_color(r, g, b, a) end,
        is_key_down = function(...)
            for i = 1, select("#", ...) do
                if state.key_down[select(i, ...)] then return true end
            end
            return false
        end,
        quit = function() state.running = false end,
    }

    function host.run(app)
        local last_ticks = tonumber(C.SDL_GetTicks())
        app.init(host)
        local ev = terralib.new(C.SDL_Event[1])
        while state.running do
            while C.SDL_PollEvent(ev) do
                local e = ev[0]
                local et = tonumber(e.type)
                if et == tonumber(C.SDL_EVENT_QUIT) then
                    state.running = false
                elseif et == tonumber(C.SDL_EVENT_WINDOW_RESIZED) then
                    state.window_w = tonumber(e.window.data1)
                    state.window_h = tonumber(e.window.data2)
                    if app.resize then app.resize(state.window_w, state.window_h) end
                elseif et == tonumber(C.SDL_EVENT_KEY_DOWN) then
                    local name = key_name[tonumber(e.key.scancode)]
                    if name then state.key_down[name] = true end
                    if not e.key["repeat"] and name and app.keypressed then app.keypressed(name) end
                elseif et == tonumber(C.SDL_EVENT_KEY_UP) then
                    local name = key_name[tonumber(e.key.scancode)]
                    if name then state.key_down[name] = nil end
                elseif et == tonumber(C.SDL_EVENT_MOUSE_MOTION) then
                    if app.mousemoved then app.mousemoved(tonumber(e.motion.x), tonumber(e.motion.y)) end
                elseif et == tonumber(C.SDL_EVENT_MOUSE_BUTTON_DOWN) then
                    if app.mousepressed then
                        app.mousepressed(tonumber(e.button.x), tonumber(e.button.y), mouse_button[tonumber(e.button.button)] or 0)
                    end
                elseif et == tonumber(C.SDL_EVENT_MOUSE_BUTTON_UP) then
                    if app.mousereleased then
                        app.mousereleased(tonumber(e.button.x), tonumber(e.button.y), mouse_button[tonumber(e.button.button)] or 0)
                    end
                elseif et == tonumber(C.SDL_EVENT_MOUSE_WHEEL) then
                    if app.wheelmoved then
                        local wx = tonumber(e.wheel.integer_x)
                        local wy = tonumber(e.wheel.integer_y)
                        if wx == 0 then wx = tonumber(e.wheel.x) end
                        if wy == 0 then wy = tonumber(e.wheel.y) end
                        app.wheelmoved(wx, wy)
                    end
                end
            end

            local now = tonumber(C.SDL_GetTicks())
            local dt = (now - last_ticks) / 1000.0
            last_ticks = now
            if app.update then app.update(dt) end
            begin_frame()
            if app.draw then app.draw() end
            end_frame()
        end
        shutdown()
    end

    return host
end

local host
if os.getenv("UI7_HEADLESS") == "1" or has_flag("--headless") then
    host = new_headless_host()
else
    host = new_sdl_host()
end

local app = assert(dofile(SCRIPT_DIR .. "/main.lua"))
host.run(app)
