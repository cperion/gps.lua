-- ui/demo/love_backend.lua
--
-- Minimal Love2D backend adapter for `ui.draw`.

local M = {}

local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil

local function rgba8_to_float(rgba8, opacity)
    opacity = opacity or 1
    local a = ((rgba8 % 256) / 255) * opacity
    rgba8 = math.floor(rgba8 / 256)
    local b = (rgba8 % 256) / 255
    rgba8 = math.floor(rgba8 / 256)
    local g = (rgba8 % 256) / 255
    rgba8 = math.floor(rgba8 / 256)
    local r = (rgba8 % 256) / 255
    return r, g, b, a
end

local function line_height_ratio(font, line_height)
    if not line_height then
        return nil
    end
    local kind = line_height.kind
    if kind == "LineHeightScale" then
        return line_height.scale
    end
    if kind == "LineHeightPx" then
        local h = font:getHeight()
        return (h > 0) and (line_height.px / h) or 1
    end
    return 1
end

local function split_lines(text)
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
    if #out == 0 then
        out[1] = ""
    end
    return out
end

function M.new(opts)
    opts = opts or {}
    local sizes = opts.sizes or {}
    local fonts = {}

    for font_id, size in pairs(sizes) do
        fonts[font_id] = love.graphics.newFont(size)
    end
    if not fonts[0] then
        fonts[0] = love.graphics.newFont(14)
    end

    local self = {
        fonts = fonts,
        current_font_id = 0,
        clip_stack = {},
    }

    function self:get_font(font_id)
        return self.fonts[font_id] or self.fonts[0]
    end

    function self:set_color_rgba8(rgba8, opacity)
        love.graphics.setColor(rgba8_to_float(rgba8, opacity))
    end

    function self:set_font_id(font_id)
        self.current_font_id = font_id or 0
        love.graphics.setFont(self:get_font(self.current_font_id))
    end

    function self:fill_rect(x, y, w, h, radius)
        radius = radius or 0
        love.graphics.rectangle("fill", x, y, w, h, radius, radius)
    end

    function self:stroke_rect(x, y, w, h, thickness, radius)
        local old = love.graphics.getLineWidth()
        love.graphics.setLineWidth(thickness or 1)
        radius = radius or 0
        love.graphics.rectangle("line", x, y, w, h, radius, radius)
        love.graphics.setLineWidth(old)
    end

    function self:draw_line(x1, y1, x2, y2, thickness)
        local old = love.graphics.getLineWidth()
        love.graphics.setLineWidth(thickness or 1)
        love.graphics.line(x1, y1, x2, y2)
        love.graphics.setLineWidth(old)
    end

    function self:draw_text(text, x, y, width, align)
        local font = self:get_font(self.current_font_id)
        love.graphics.setFont(font)
        if width and width > 0 then
            love.graphics.printf(text, x, y, width, align or "left")
        else
            love.graphics.print(text, x, y)
        end
    end

    function self:draw_text_box(text, x, y, w, h, style)
        local font = self:get_font(style.font_id or self.current_font_id)
        local old = font:getLineHeight()
        font:setLineHeight(line_height_ratio(font, style.line_height) or 1)
        love.graphics.setFont(font)
        love.graphics.printf(text, x, y, math.max(1, w), (style.align and style.align.kind == "TextCenter") and "center"
            or (style.align and style.align.kind == "TextEnd") and "right"
            or (style.align and style.align.kind == "TextJustify") and "justify"
            or "left")
        font:setLineHeight(old)
    end

    function self:measure_text(style, text, max_w, max_h)
        text = text or ""
        local font = self:get_font(style.font_id or self.current_font_id)
        local ratio = line_height_ratio(font, style.line_height) or 1
        local base_h = font:getHeight()
        local line_h = base_h * ratio
        local lines = split_lines(text)
        local raw_w = 0
        local min_w = 0
        local used_w = 0
        local wrapped_lines = 0

        for i = 1, #lines do
            local line = lines[i]
            local line_w = font:getWidth(line)
            if line_w > raw_w then
                raw_w = line_w
            end
            if line_w > min_w then
                min_w = line_w
            end

            if style.wrap and style.wrap.kind ~= "TextNoWrap" and max_w ~= math.huge and max_w and max_w > 0 then
                local _, wrapped = font:getWrap(line, math_max(1, max_w))
                local count = math_max(1, #wrapped)
                wrapped_lines = wrapped_lines + count
                local wrapped_w = 0
                for j = 1, #wrapped do
                    local ww = font:getWidth(wrapped[j])
                    if ww > wrapped_w then
                        wrapped_w = ww
                    end
                end
                if wrapped_w > used_w then
                    used_w = wrapped_w
                end
            else
                wrapped_lines = wrapped_lines + 1
                if line_w > used_w then
                    used_w = line_w
                end
            end
        end

        if style.wrap and style.wrap.kind ~= "TextNoWrap" and max_w ~= math.huge and max_w and max_w > 0 then
            used_w = math_min(used_w, max_w)
        end

        local line_limit = style.line_limit
        if line_limit and line_limit.kind == "MaxLines" then
            wrapped_lines = math_min(wrapped_lines, line_limit.count)
        end

        local used_h = wrapped_lines * line_h
        if max_h ~= math.huge and max_h and max_h > 0 then
            used_h = math_min(used_h, max_h)
        end

        return {
            min_w = min_w,
            min_h = #lines * line_h,
            max_w = raw_w,
            max_h = #lines * line_h,
            used_w = used_w,
            used_h = used_h,
            baseline = math_floor(base_h * 0.8 + 0.5),
        }
    end

    function self:push_clip(x, y, w, h)
        local sx, sy, sw, sh = love.graphics.getScissor()
        self.clip_stack[#self.clip_stack + 1] = { sx, sy, sw, sh }
        love.graphics.setScissor(x, y, w, h)
    end

    function self:pop_clip()
        local top = self.clip_stack[#self.clip_stack]
        self.clip_stack[#self.clip_stack] = nil
        if top and top[1] ~= nil then
            love.graphics.setScissor(top[1], top[2], top[3], top[4])
        else
            love.graphics.setScissor()
        end
    end

    return self
end

return M
