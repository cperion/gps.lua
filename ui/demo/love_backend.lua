-- ui/demo/love_backend.lua
--
-- Minimal Love2D backend adapter for `ui.draw`.

local M = {}

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
