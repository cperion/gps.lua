local pvm = require("pvm")
local sdl3 = require("ui._sdl3")
local ui_asdl = require("ui.asdl")

local ffi = sdl3.ffi
local sdl = sdl3.sdl
local ttf = sdl3.ttf

local T = ui_asdl.T
local Core = T.Core
local Style = T.Style
local Paint = T.Paint

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

local function default_font_path()
    local candidates = {
        "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf",
        "/usr/share/fonts/google-noto/NotoSans-Regular.ttf",
        "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
    }
    for i = 1, #candidates do
        local f = io.open(candidates[i], "rb")
        if f then f:close(); return candidates[i] end
    end
    return nil
end

local function normalize_font_spec(spec, default_path)
    if type(spec) == "string" then return { path = spec } end
    if type(spec) == "table" then return spec end
    if spec == nil and default_path ~= nil then return { path = default_path } end
    return nil
end

local function normalize_align(align)
    if align == 1 then return ffi.C.TTF_HORIZONTAL_ALIGN_CENTER end
    if align == 2 then return ffi.C.TTF_HORIZONTAL_ALIGN_RIGHT end
    return ffi.C.TTF_HORIZONTAL_ALIGN_LEFT
end

local function cursor_name(cursor)
    if cursor == nil or cursor == Style.CursorDefault then return nil end
    if cursor == Style.CursorPointer then return sdl3.SDL_SYSTEM_CURSOR_POINTER end
    if cursor == Style.CursorText then return sdl3.SDL_SYSTEM_CURSOR_TEXT end
    if cursor == Style.CursorMove then return sdl3.SDL_SYSTEM_CURSOR_MOVE end
    if cursor == Style.CursorNotAllowed then return sdl3.SDL_SYSTEM_CURSOR_NOT_ALLOWED end
    if cursor == Style.CursorGrab or cursor == Style.CursorGrabbing then return sdl3.SDL_SYSTEM_CURSOR_POINTER end
    return nil
end

local function with_color(renderer, rgba8, opacity)
    local r, g, b, a = rgba8_bytes(rgba8, opacity)
    if sdl.SDL_SetRenderDrawColor(renderer, r, g, b, a) == 0 then
        sdl3.err("ui.runtime_sdl3: SDL_SetRenderDrawColor failed")
    end
end

local function frect(x, y, w, h)
    local r = ffi.new("SDL_FRect[1]")
    r[0].x = x
    r[0].y = y
    r[0].w = w
    r[0].h = h
    return r
end

local function srect(x, y, w, h)
    local r = ffi.new("SDL_Rect[1]")
    r[0].x = round(x)
    r[0].y = round(y)
    r[0].w = round(w)
    r[0].h = round(h)
    return r
end

local function poly_points(xy, ox, oy)
    local n = math.floor(#xy / 2)
    local pts = ffi.new("SDL_FPoint[?]", n)
    local k = 0
    for i = 1, #xy, 2 do
        pts[k].x = ox + xy[i]
        pts[k].y = oy + xy[i + 1]
        k = k + 1
    end
    return pts, n
end

local function circle_points(cx, cy, r, segments)
    segments = math.max(12, segments or math.floor(r * 0.8))
    local pts = ffi.new("SDL_FPoint[?]", segments + 1)
    for i = 0, segments do
        local a = (i / segments) * math.pi * 2
        pts[i].x = cx + math.cos(a) * r
        pts[i].y = cy + math.sin(a) * r
    end
    return pts, segments + 1
end

local function arc_points(cx, cy, r, a1, a2, segments)
    segments = math.max(8, segments or 24)
    local pts = ffi.new("SDL_FPoint[?]", segments + 1)
    for i = 0, segments do
        local t = i / segments
        local a = a1 + (a2 - a1) * t
        pts[i].x = cx + math.cos(a) * r
        pts[i].y = cy + math.sin(a) * r
    end
    return pts, segments + 1
end

function M.new(opts)
    opts = opts or {}
    local renderer = opts.renderer
    if renderer == nil then
        error("ui.runtime_sdl3.new requires opts.renderer", 2)
    end

    sdl3.ensure_ttf()

    local provided_fonts = opts.fonts or {}
    local resolve_font = opts.resolve_font
    local default_font = opts.default_font or default_font_path()
    local engine = ttf.TTF_CreateRendererTextEngine(renderer)
    if engine == nil then
        sdl3.err("ui.runtime_sdl3: TTF_CreateRendererTextEngine failed")
    end

    local clip_stack = {}
    local cursor_cache = {}
    local current_cursor_id = false
    local font_cache = {}
    local closed = false

    local self = {}

    local function font_spec_for(font_id, style)
        local spec
        if resolve_font ~= nil then
            spec = resolve_font(font_id, style)
        else
            spec = provided_fonts[font_id]
        end
        spec = normalize_font_spec(spec, default_font)
        if spec == nil or spec.path == nil then
            error("ui.runtime_sdl3: no font path for font_id=" .. tostring(font_id), 3)
        end
        return spec
    end

    local function font_key(path, size)
        return path .. "\0" .. tostring(size)
    end

    local function get_font(font_id, font_size, style)
        local spec = font_spec_for(font_id, style)
        local key = font_key(spec.path, font_size)
        local font = font_cache[key]
        if font == nil then
            font = ttf.TTF_OpenFont(spec.path, font_size)
            if font == nil then
                sdl3.err("ui.runtime_sdl3: TTF_OpenFont failed for " .. tostring(spec.path))
            end
            font_cache[key] = font
        end
        ttf.TTF_SetFontWrapAlignment(font, normalize_align(style and style.align or 0))
        return font
    end

    function self:draw_rect(x, y, w, h, visual)
        if visual == nil then return end
        local opacity = (visual.opacity or 100) / 100
        if visual.bg ~= 0 then
            with_color(renderer, visual.bg, opacity)
            if sdl.SDL_RenderFillRect(renderer, frect(x, y, w, h)) == 0 then
                sdl3.err("ui.runtime_sdl3: SDL_RenderFillRect failed")
            end
        end
        if visual.border_w > 0 and visual.border_color ~= 0 then
            with_color(renderer, visual.border_color, opacity)
            if sdl.SDL_RenderRect(renderer, frect(x, y, w, h)) == 0 then
                sdl3.err("ui.runtime_sdl3: SDL_RenderRect failed")
            end
        end
    end

    function self:draw_text(x, y, w, h, layout)
        if layout == nil then return end
        local align = layout.style.align
        for i = 1, #layout.lines do
            local line = layout.lines[i]
            local draw_x = x + line.x
            if align == 1 then
                draw_x = draw_x + math.max(0, math.floor((w - line.w) / 2))
            elseif align == 2 then
                draw_x = draw_x + math.max(0, w - line.w)
            end
            local draw_y = y + line.y
            for j = 1, #line.runs do
                local run = line.runs[j]
                local font = get_font(run.font_id, run.font_size, layout.style)
                local text = ttf.TTF_CreateText(engine, font, run.text, #run.text)
                if text == nil then
                    sdl3.err("ui.runtime_sdl3: TTF_CreateText failed")
                end
                local r, g, b, a = rgba8_bytes(run.fg, 1)
                if ttf.TTF_SetTextColor(text, r, g, b, a) == 0 then
                    ttf.TTF_DestroyText(text)
                    sdl3.err("ui.runtime_sdl3: TTF_SetTextColor failed")
                end
                if ttf.TTF_DrawRendererText(text, round(draw_x + run.x), round(draw_y + run.y)) == 0 then
                    ttf.TTF_DestroyText(text)
                    sdl3.err("ui.runtime_sdl3: TTF_DrawRendererText failed")
                end
                ttf.TTF_DestroyText(text)
            end
        end
    end

    function self:draw_paint(x, y, w, h, paint)
        if paint == nil then return end
        local items = paint.items or paint
        for i = 1, #items do
            local item = items[i]
            local cls = pvm.classof(item)
            if cls == Paint.Line then
                with_color(renderer, item.stroke.rgba8, 1)
                sdl.SDL_RenderLine(renderer, x + item.x1, y + item.y1, x + item.x2, y + item.y2)
            elseif cls == Paint.Polyline then
                if #item.xy >= 4 then
                    local pts, n = poly_points(item.xy, x, y)
                    with_color(renderer, item.stroke.rgba8, 1)
                    sdl.SDL_RenderLines(renderer, pts, n)
                end
            elseif cls == Paint.Polygon then
                if #item.xy >= 4 and item.stroke ~= nil then
                    local pts, n = poly_points(item.xy, x, y)
                    with_color(renderer, item.stroke.rgba8, 1)
                    sdl.SDL_RenderLines(renderer, pts, n)
                end
            elseif cls == Paint.Circle then
                local pts, n = circle_points(x + item.cx, y + item.cy, item.r, 24)
                local stroke = item.stroke
                if stroke ~= nil then
                    with_color(renderer, stroke.rgba8, 1)
                    sdl.SDL_RenderLines(renderer, pts, n)
                elseif item.fill ~= Paint.NoFill then
                    with_color(renderer, item.fill.rgba8, 1)
                    sdl.SDL_RenderLines(renderer, pts, n)
                end
            elseif cls == Paint.Arc then
                local pts, n = arc_points(x + item.cx, y + item.cy, item.r, item.a1, item.a2, item.segments)
                with_color(renderer, item.stroke.rgba8, 1)
                sdl.SDL_RenderLines(renderer, pts, n)
            elseif cls == Paint.Bezier then
                local xy = item.xy
                if #xy >= 8 then
                    local segments = math.max(8, round(item.segments))
                    local pts = ffi.new("SDL_FPoint[?]", segments + 1)
                    local function eval(t)
                        local mt = 1 - t
                        local x1, y1 = xy[1], xy[2]
                        local x2, y2 = xy[3], xy[4]
                        local x3, y3 = xy[5], xy[6]
                        local x4, y4 = xy[7], xy[8]
                        local px = mt^3 * x1 + 3 * mt^2 * t * x2 + 3 * mt * t^2 * x3 + t^3 * x4
                        local py = mt^3 * y1 + 3 * mt^2 * t * y2 + 3 * mt * t^2 * y3 + t^3 * y4
                        return px, py
                    end
                    for j = 0, segments do
                        local px, py = eval(j / segments)
                        pts[j].x = x + px
                        pts[j].y = y + py
                    end
                    with_color(renderer, item.stroke.rgba8, 1)
                    sdl.SDL_RenderLines(renderer, pts, segments + 1)
                end
            end
        end
    end

    function self:push_clip(x, y, w, h)
        local top = srect(x, y, w, h)
        clip_stack[#clip_stack + 1] = top
        if sdl.SDL_SetRenderClipRect(renderer, top) == 0 then
            sdl3.err("ui.runtime_sdl3: SDL_SetRenderClipRect failed")
        end
    end

    function self:pop_clip()
        clip_stack[#clip_stack] = nil
        local top = clip_stack[#clip_stack]
        if top == nil then
            if sdl.SDL_SetRenderClipRect(renderer, nil) == 0 then
                sdl3.err("ui.runtime_sdl3: SDL_SetRenderClipRect clear failed")
            end
        else
            if sdl.SDL_SetRenderClipRect(renderer, top) == 0 then
                sdl3.err("ui.runtime_sdl3: SDL_SetRenderClipRect restore failed")
            end
        end
    end

    function self:set_cursor_kind(cursor)
        local id = cursor_name(cursor)
        if current_cursor_id == id then
            sdl.SDL_ShowCursor()
            return
        end

        current_cursor_id = id

        if id == nil then
            sdl.SDL_SetCursor(nil)
            sdl.SDL_ShowCursor()
            return
        end

        local c = cursor_cache[id]
        if c == nil then
            c = sdl.SDL_CreateSystemCursor(id)
            cursor_cache[id] = c or false
        end
        if c == false then
            sdl.SDL_SetCursor(nil)
        else
            sdl.SDL_SetCursor(c)
        end
        sdl.SDL_ShowCursor()
    end

    function self:set_cursor(name)
        if name == "text" then
            return self:set_cursor_kind(Style.CursorText)
        elseif name == "pointer" then
            return self:set_cursor_kind(Style.CursorPointer)
        elseif name == "move" then
            return self:set_cursor_kind(Style.CursorMove)
        elseif name == "not-allowed" then
            return self:set_cursor_kind(Style.CursorNotAllowed)
        end
        return self:set_cursor_kind(Style.CursorDefault)
    end

    function self:reset()
        if sdl.SDL_SetRenderClipRect(renderer, nil) == 0 then
            sdl3.err("ui.runtime_sdl3: SDL_SetRenderClipRect reset failed")
        end
        clip_stack = {}
    end

    function self:close()
        if closed then return end
        closed = true
        for _, font in pairs(font_cache) do
            ttf.TTF_CloseFont(font)
        end
        for _, cursor in pairs(cursor_cache) do
            if cursor ~= nil then
                sdl.SDL_DestroyCursor(cursor)
            end
        end
        if engine ~= nil then
            ttf.TTF_DestroyRendererTextEngine(engine)
            engine = nil
        end
        sdl3.release_ttf()
    end

    return self
end

M.T = T

return M
