local ui_asdl = require("ui.asdl")
local text = require("ui.text")
local text_field = require("ui.text_field")

local T = ui_asdl.T

local M = {}

local function max0(n)
    if n < 0 then return 0 end
    return n
end

local function padding_spec(padding)
    if type(padding) == "table" then
        return {
            left = padding.left or padding.x or padding[1] or 0,
            top = padding.top or padding.y or padding[2] or padding[1] or 0,
            right = padding.right or padding.x or padding[3] or padding[1] or 0,
            bottom = padding.bottom or padding.y or padding[4] or padding[2] or padding[1] or 0,
        }
    end
    local p = padding or 0
    return { left = p, top = p, right = p, bottom = p }
end

local function default_text_style(field)
    return T.Layout.TextStyle(1, 16, 400, 0xffffffff, 0, 20, 0, text_field.text(field))
end

local function default_composition_style(field, base)
    return T.Layout.TextStyle(
        base.font_id,
        base.font_size,
        base.font_weight,
        base.fg,
        base.align,
        base.leading,
        base.tracking,
        field.composition_text
    )
end

local function draw_text_layout(host, layout, x, y, wrap_w)
    host.driver:draw_text(x, y, wrap_w or layout.measured_w, layout.measured_h, {
        style = layout.style,
        lines = layout.lines,
    })
end

function M.resolve(host, field, opts)
    opts = opts or {}
    local pad = padding_spec(opts.padding)
    local vw, vh = host:size()
    local outer_x = opts.x or 0
    local outer_y = opts.y or 0
    local outer_w = opts.w or vw
    local outer_h = opts.h or vh
    local inner_x = outer_x + pad.left
    local inner_y = outer_y + pad.top
    local inner_w = max0(outer_w - pad.left - pad.right)
    local inner_h = max0(outer_h - pad.top - pad.bottom)

    local text_style = opts.text_style and opts.text_style(field, opts) or default_text_style(field)
    local wrap_w = inner_w
    if opts.wrap_width ~= nil then
        wrap_w = opts.wrap_width
    elseif opts.wrap == false then
        wrap_w = math.huge
    end
    local layout = text.layout(text_style, T.Layout.Constraint(wrap_w, math.huge), opts.text_key)

    local composition_layout = nil
    if text_field.composition_active(field) then
        local comp_style = opts.composition_style and opts.composition_style(field, text_style, opts) or default_composition_style(field, text_style)
        composition_layout = text.layout(comp_style, T.Layout.Constraint(inner_w, math.huge), opts.text_key)
    end

    local blink_on
    if opts.show_caret == false then
        blink_on = false
    elseif opts.blink_on ~= nil then
        if type(opts.blink_on) == "function" then
            blink_on = opts.blink_on(field, host, opts)
        else
            blink_on = opts.blink_on and true or false
        end
    else
        blink_on = field.focused and (text_field.composition_active(field) or (math.floor(host:now_ms() / 530) % 2 == 0))
    end

    local max_scroll_x = max0(layout.measured_w - inner_w)
    local max_scroll_y = max0(layout.measured_h - inner_h)
    local scroll_x = opts.scroll_x or 0
    local scroll_y = opts.scroll_y or 0
    if scroll_x < 0 then scroll_x = 0 elseif scroll_x > max_scroll_x then scroll_x = max_scroll_x end
    if scroll_y < 0 then scroll_y = 0 elseif scroll_y > max_scroll_y then scroll_y = max_scroll_y end

    return {
        vw = vw,
        vh = vh,
        outer_x = outer_x,
        outer_y = outer_y,
        outer_w = outer_w,
        outer_h = outer_h,
        inner_x = inner_x,
        inner_y = inner_y,
        inner_w = inner_w,
        inner_h = inner_h,
        content_x = inner_x - scroll_x,
        content_y = inner_y - scroll_y,
        scroll_x = scroll_x,
        scroll_y = scroll_y,
        max_scroll_x = max_scroll_x,
        max_scroll_y = max_scroll_y,
        padding = pad,
        wrap_w = wrap_w,
        text_style = text_style,
        layout = layout,
        composition_layout = composition_layout,
        blink_on = blink_on,
    }
end

function M.contains(resolved, x, y)
    return x >= resolved.outer_x and y >= resolved.outer_y
       and x < resolved.outer_x + resolved.outer_w and y < resolved.outer_y + resolved.outer_h
end

function M.local_point(resolved, x, y)
    return x - resolved.inner_x + resolved.scroll_x, y - resolved.inner_y + resolved.scroll_y
end

function M.apply_text_input_rect(host, field, resolved, width)
    local rect = text_field.input_rect(resolved.layout, field, resolved.content_x, resolved.content_y, width or 1)
    if rect ~= nil then
        host:set_text_input_rect(rect.x, rect.y, rect.w, rect.h, 0)
    end
    return rect
end

function M.clamp_scroll(resolved, scroll_x, scroll_y)
    scroll_x = scroll_x or 0
    scroll_y = scroll_y or 0
    if scroll_x < 0 then scroll_x = 0 elseif scroll_x > resolved.max_scroll_x then scroll_x = resolved.max_scroll_x end
    if scroll_y < 0 then scroll_y = 0 elseif scroll_y > resolved.max_scroll_y then scroll_y = resolved.max_scroll_y end
    return scroll_x, scroll_y
end

function M.scroll_to_caret(resolved, field, scroll_x, scroll_y, margin)
    scroll_x, scroll_y = M.clamp_scroll(resolved, scroll_x, scroll_y)
    local caret = text_field.caret_rect(resolved.layout, field, 1)
    if caret == nil then return scroll_x, scroll_y end
    margin = margin or 12

    if caret.x < scroll_x + margin then
        scroll_x = math.max(0, caret.x - margin)
    elseif caret.x + caret.w > scroll_x + resolved.inner_w - margin then
        scroll_x = math.min(resolved.max_scroll_x, caret.x + caret.w - resolved.inner_w + margin)
    end

    if caret.y < scroll_y + margin then
        scroll_y = math.max(0, caret.y - margin)
    elseif caret.y + caret.h > scroll_y + resolved.inner_h - margin then
        scroll_y = math.min(resolved.max_scroll_y, caret.y + caret.h - resolved.inner_h + margin)
    end

    return scroll_x, scroll_y
end

function M.draw(host, field, resolved, opts)
    if opts == nil then
        opts = resolved or {}
        resolved = nil
    end
    resolved = resolved or M.resolve(host, field, opts)
    opts = opts or {}

    if opts.apply_text_input_rect ~= false then
        M.apply_text_input_rect(host, field, resolved, opts.caret_w or 1)
    end

    if opts.bg_rgba8 ~= nil then
        host:fill_rect(resolved.outer_x, resolved.outer_y, resolved.outer_w, resolved.outer_h, opts.bg_rgba8, opts.bg_opacity or 1)
    end

    local border_rgba8 = field.focused and (opts.focus_border_rgba8 or opts.border_rgba8) or opts.border_rgba8
    if border_rgba8 ~= nil then
        host:stroke_rect(resolved.outer_x - 1, resolved.outer_y - 1, resolved.outer_w + 2, resolved.outer_h + 2, border_rgba8, opts.border_opacity or 1)
    end

    local pushed_clip = false
    if host.driver ~= nil and host.driver.push_clip ~= nil and host.driver.pop_clip ~= nil then
        host.driver:push_clip(resolved.inner_x, resolved.inner_y, resolved.inner_w, resolved.inner_h)
        pushed_clip = true
    end

    local selection_rects = text_field.selection_rects(resolved.layout, field)
    local selection_rgba8 = opts.selection_rgba8 or 0x1e40afff
    local selection_opacity = opts.selection_opacity or 0.78
    for i = 1, #selection_rects do
        local r = selection_rects[i]
        host:fill_rect(resolved.content_x + r.x, resolved.content_y + r.y, r.w, r.h, selection_rgba8, selection_opacity)
    end

    draw_text_layout(host, resolved.layout, resolved.content_x, resolved.content_y, resolved.inner_w)

    if resolved.composition_layout ~= nil and field.focused then
        local caret = text_field.caret_rect(resolved.layout, field, opts.caret_w or 1)
        if caret ~= nil then
            draw_text_layout(host, resolved.composition_layout, resolved.content_x + caret.x, resolved.content_y + caret.y, resolved.inner_w)
            host:draw_line(
                resolved.content_x + caret.x,
                resolved.content_y + caret.y + resolved.composition_layout.baseline + 3,
                resolved.content_x + caret.x + resolved.composition_layout.measured_w,
                resolved.content_y + caret.y + resolved.composition_layout.baseline + 3,
                opts.composition_underline_rgba8 or opts.composition_rgba8 or 0x93c5fdff,
                opts.composition_underline_opacity or 1
            )
        end
    end

    if resolved.blink_on then
        local caret = text_field.caret_rect(resolved.layout, field, opts.caret_w or 1)
        if caret ~= nil then
            host:fill_rect(resolved.content_x + caret.x, resolved.content_y + caret.y, caret.w, caret.h, opts.caret_rgba8 or 0xf8fafcff, opts.caret_opacity or 1)
        end
    end

    if pushed_clip then
        host.driver:pop_clip()
    end

    return resolved
end

M.T = T

return M
