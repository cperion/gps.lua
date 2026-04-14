local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Layout = T.Layout

local M = {}

local HUGE = math.huge
local systems = {}

local function finite(n)
    return n ~= nil and n < HUGE
end

local function max0(n)
    if n < 0 then return 0 end
    return n
end

local function round(n)
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

local function approx_advance(style)
    local advance = style.font_size * 0.6 + (style.tracking or 0)
    if advance < 1 then advance = 1 end
    return advance
end

local function approx_baseline(style)
    return round(style.font_size * 0.8)
end

local function line_width_approx(style, text)
    if text == nil or #text == 0 then return 0 end
    return round(#text * approx_advance(style))
end

local function split_paragraphs(text)
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

local function wrap_para_approx(style, para, max_w)
    if not finite(max_w) then
        return { para }, line_width_approx(style, para)
    end

    local limit = max0(max_w)
    if limit <= 0 then
        return { "" }, 0
    end

    if para == "" then
        return { "" }, 0
    end

    local lines = {}
    local line = ""
    local line_w = 0
    local max_line_w = 0

    local i = 1
    while i <= #para do
        local ws_s, ws_e = string.find(para, "^%s+", i)
        if ws_s then
            i = ws_e + 1
        else
            local w_s, w_e = string.find(para, "^%S+", i)
            if not w_s then break end
            local word = string.sub(para, w_s, w_e)
            i = w_e + 1

            local candidate = line == "" and word or (line .. " " .. word)
            local candidate_w = line_width_approx(style, candidate)
            if line == "" or candidate_w <= limit then
                line = candidate
                line_w = candidate_w
            else
                lines[#lines + 1] = line
                if line_w > max_line_w then max_line_w = line_w end

                if line_width_approx(style, word) <= limit then
                    line = word
                    line_w = line_width_approx(style, word)
                else
                    local chars_per_line = math.max(1, math.floor(limit / approx_advance(style)))
                    local pos = 1
                    while pos <= #word do
                        local piece = string.sub(word, pos, pos + chars_per_line - 1)
                        local piece_w = line_width_approx(style, piece)
                        lines[#lines + 1] = piece
                        if piece_w > max_line_w then max_line_w = piece_w end
                        pos = pos + chars_per_line
                    end
                    line = ""
                    line_w = 0
                end
            end
        end
    end

    if line ~= "" or #lines == 0 then
        lines[#lines + 1] = line
        if line_w > max_line_w then max_line_w = line_w end
    end

    return lines, max_line_w
end

function M.approx_layout(style, constraint)
    local leading = style.leading > 0 and style.leading or style.font_size
    local baseline = approx_baseline(style)
    local paragraphs = split_paragraphs(style.content or "")
    local lines = {}
    local measured_w = 0

    for i = 1, #paragraphs do
        local wrapped, para_w = wrap_para_approx(style, paragraphs[i], constraint.max_w)
        for j = 1, #wrapped do
            lines[#lines + 1] = wrapped[j]
        end
        if para_w > measured_w then measured_w = para_w end
    end

    if #lines == 0 then lines[1] = "" end

    return Layout.TextLayout(
        style,
        constraint.max_w,
        measured_w,
        #lines * leading,
        baseline,
        lines
    )
end

local function from_result(style, constraint, result)
    if pvm.classof(result) == Layout.TextLayout then
        return result
    end

    if type(result) ~= "table" then
        error("ui.text: backend measure must return Layout.TextLayout or a table", 3)
    end

    local lines = result.lines or { style.content or "" }
    local measured_w = result.measured_w or result.width or 0
    local measured_h = result.measured_h or result.height or 0
    local baseline = result.baseline or approx_baseline(style)

    return Layout.TextLayout(
        style,
        result.max_w or constraint.max_w,
        measured_w,
        measured_h,
        baseline,
        lines
    )
end

function M.layout(style, constraint, system_key)
    if system_key == nil then
        return M.approx_layout(style, constraint)
    end

    local system = systems[system_key]
    if system == nil then
        return M.approx_layout(style, constraint)
    end

    local measure
    if type(system) == "function" then
        measure = system
    else
        measure = system.measure
    end
    if type(measure) ~= "function" then
        error("ui.text: registered system must be a function or { measure = fn }", 2)
    end

    return from_result(style, constraint, measure(style, constraint))
end

function M.register(key, system)
    local kt = type(key)
    if kt ~= "string" and kt ~= "number" and kt ~= "boolean" then
        error("ui.text.register: key must be string, number, or boolean", 2)
    end
    if type(system) ~= "function" and type(system) ~= "table" then
        error("ui.text.register: system must be a function or table", 2)
    end
    systems[key] = system
    return key
end

function M.unregister(key)
    systems[key] = nil
end

function M.lookup(key)
    return systems[key]
end

M.T = T

return M
