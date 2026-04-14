local M = {}

local HUGE = math.huge

local function finite(n)
    return n ~= nil and n < HUGE
end

local function split_lines(text)
    local out = {}
    local start_i = 1
    while true do
        local i = string.find(text, "\n", start_i, true)
        if i == nil then
            out[#out + 1] = string.sub(text, start_i)
            break
        end
        out[#out + 1] = string.sub(text, start_i, i - 1)
        start_i = i + 1
    end
    if #out == 0 then out[1] = "" end
    return out
end

local function round(n)
    if n >= 0 then return math.floor(n + 0.5) end
    return math.ceil(n - 0.5)
end

local function line_height_ratio(font, leading)
    if not leading then return 1 end
    local h = font:getHeight()
    if h <= 0 then return 1 end
    return leading / h
end

function M.new(opts)
    if not (love and love.graphics and love.graphics.newFont) then
        error("ui.text_love.new requires Love2D", 2)
    end

    opts = opts or {}
    local provided_fonts = opts.fonts or {}
    local sized_fonts = {}

    local function get_font(style)
        local font = provided_fonts[style.font_id]
        if font ~= nil then
            return font
        end
        local key = style.font_size
        font = sized_fonts[key]
        if font == nil then
            font = love.graphics.newFont(key)
            sized_fonts[key] = font
        end
        return font
    end

    return {
        measure = function(style, constraint)
            local font = get_font(style)
            local lines = {}
            local measured_w = 0
            local base_h = font:getHeight()
            local ratio = line_height_ratio(font, style.leading)
            local line_h = round(base_h * ratio)
            local old_ratio = font:getLineHeight()
            font:setLineHeight(ratio)

            local raw_lines = split_lines(style.content or "")
            local max_w = constraint.max_w

            for i = 1, #raw_lines do
                local line = raw_lines[i]
                if finite(max_w) and max_w > 0 then
                    local wrap_w = math.max(1, round(max_w))
                    local _, wrapped = font:getWrap(line, wrap_w)
                    if #wrapped == 0 then wrapped[1] = "" end
                    for j = 1, #wrapped do
                        local piece = wrapped[j]
                        lines[#lines + 1] = piece
                        local w = round(font:getWidth(piece))
                        if w > measured_w then measured_w = w end
                    end
                elseif finite(max_w) and max_w <= 0 then
                    lines[#lines + 1] = ""
                else
                    lines[#lines + 1] = line
                    local w = round(font:getWidth(line))
                    if w > measured_w then measured_w = w end
                end
            end

            if #lines == 0 then lines[1] = "" end

            local measured_h = #lines * line_h
            if finite(constraint.max_h) then
                measured_h = math.min(measured_h, constraint.max_h)
            end

            font:setLineHeight(old_ratio)

            return {
                measured_w = round(measured_w),
                measured_h = round(measured_h),
                baseline = round(base_h * 0.8),
                lines = lines,
            }
        end,
    }
end

return M
