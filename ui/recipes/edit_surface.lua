local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local core = require("ui.recipes._core")
local common = require("ui.widgets._text_common")
local text_field_view = require("ui.text_field_view")
local interact = require("ui.interact")
local tw = require("ui.tw")

local T = ui_asdl.T
local Style = T.Style
local Solve = T.Solve

local DEFAULTS = {
    gap_y = 8,
    label_styles = tw.list {
        tw.text_sm,
        tw.font_semibold,
        tw.fg.slate[300],
    },
    field_styles = tw.list {
        tw.rounded_xl,
        tw.border_1,
        tw.border_color.slate[800],
        tw.bg.slate[950],
        tw.cursor_text,
    },
}

local function copy_table(src)
    local out = {}
    if src ~= nil then
        for k, v in pairs(src) do
            out[k] = v
        end
    end
    return out
end

local function merge_opts(base, extra)
    local out = copy_table(base)
    if extra ~= nil then
        for k, v in pairs(extra) do
            out[k] = v
        end
    end
    return out
end

local function max0(n)
    if n < 0 then return 0 end
    return n
end

local function clamp01(t)
    if t < 0 then return 0 end
    if t > 1 then return 1 end
    return t
end

local function rect_contains(r, x, y)
    return r ~= nil and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h
end

local function axis_enabled(axis, axis_name)
    return axis == Style.ScrollBoth
        or (axis_name == "x" and axis == Style.ScrollX)
        or (axis_name == "y" and axis == Style.ScrollY)
end

local function thickness_px(opts)
    return opts.thickness or 8
end

local function inset_px(opts)
    return opts.inset or 2
end

local function reserve_space_px(opts)
    if opts.reserve_space_px ~= nil then return opts.reserve_space_px end
    return thickness_px(opts) + inset_px(opts) * 2
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

local function resolved_padding(base_padding, axis, reserve_visible, opts)
    local pad = padding_spec(base_padding)
    if reserve_visible then
        local reserve = reserve_space_px(opts)
        if axis_enabled(axis, "y") then
            pad.right = pad.right + reserve
        end
        if axis_enabled(axis, "x") then
            pad.bottom = pad.bottom + reserve
        end
    end
    return pad
end

local function want_reserved_gutter(reserve_mode, visible)
    if reserve_mode == "auto" then
        return visible == true
    end
    return reserve_mode == true
end

local function update_scroll_model(model, id, x, y)
    local scrolls = model.scrolls
    local index = 0
    for i = 1, #scrolls do
        if scrolls[i].id == id then
            index = i
            break
        end
    end

    if index > 0 then
        local cur = scrolls[index]
        if cur.x == x and cur.y == y then
            return model
        end

        local out = {}
        if x == 0 and y == 0 then
            local n = 0
            for i = 1, #scrolls do
                if i ~= index then
                    n = n + 1
                    out[n] = scrolls[i]
                end
            end
        else
            for i = 1, #scrolls do
                out[i] = (i == index) and Solve.Scroll(id, x, y) or scrolls[i]
            end
        end
        return pvm.with(model, { scrolls = out })
    end

    if x == 0 and y == 0 then
        return model
    end

    local out = {}
    for i = 1, #scrolls do out[i] = scrolls[i] end
    out[#out + 1] = Solve.Scroll(id, x, y)
    return pvm.with(model, { scrolls = out })
end

local function axis_geometry(metrics, axis_name, has_cross, opts)
    local resolved = metrics.resolved
    local hit = metrics.hit
    local inset = inset_px(opts)
    local thickness = thickness_px(opts)
    local reserve = reserve_space_px(opts)
    local cross_reserve = has_cross and (thickness + inset) or 0

    local viewport = axis_name == "y" and resolved.inner_h or resolved.inner_w
    local content = axis_name == "y" and resolved.layout.measured_h or resolved.layout.measured_w
    local max_offset = axis_name == "y" and resolved.max_scroll_y or resolved.max_scroll_x
    if viewport <= 0 or content <= viewport or max_offset <= 0 then
        return nil
    end

    local track
    if axis_name == "y" then
        local strip = reserve
        local extra = max0(strip - thickness)
        track = {
            x = hit.x + hit.w - strip + math.floor(extra * 0.5),
            y = hit.y + inset,
            w = thickness,
            h = max0(hit.h - inset * 2 - cross_reserve),
        }
    else
        local strip = reserve
        local extra = max0(strip - thickness)
        track = {
            x = hit.x + inset,
            y = hit.y + hit.h - strip + math.floor(extra * 0.5),
            w = max0(hit.w - inset * 2 - cross_reserve),
            h = thickness,
        }
    end
    if track.w <= 0 or track.h <= 0 then return nil end

    local track_len = axis_name == "y" and track.h or track.w
    local thumb_len = math.floor(track_len * (viewport / content) + 0.5)
    local min_thumb_px = opts.min_thumb_px or 20
    if thumb_len < min_thumb_px then thumb_len = min_thumb_px end
    if thumb_len > track_len then thumb_len = track_len end

    local travel = track_len - thumb_len
    local offset = axis_name == "y" and resolved.scroll_y or resolved.scroll_x
    local t = max_offset > 0 and clamp01(offset / max_offset) or 0
    local thumb_pos = (axis_name == "y" and track.y or track.x) + travel * t

    local thumb
    if axis_name == "y" then
        thumb = { x = track.x, y = thumb_pos, w = track.w, h = thumb_len }
    else
        thumb = { x = thumb_pos, y = track.y, w = thumb_len, h = track.h }
    end

    return {
        axis = axis_name,
        viewport = viewport,
        content = content,
        max = max_offset,
        offset = offset,
        track = track,
        thumb = thumb,
        travel = travel,
    }
end

local function hit_part(metrics, x, y)
    local vertical = metrics.vertical
    local horizontal = metrics.horizontal

    if vertical ~= nil then
        if rect_contains(vertical.thumb, x, y) then
            return { axis = "y", part = "thumb", geom = vertical }
        end
        if rect_contains(vertical.track, x, y) then
            return { axis = "y", part = "track", geom = vertical }
        end
    end

    if horizontal ~= nil then
        if rect_contains(horizontal.thumb, x, y) then
            return { axis = "x", part = "thumb", geom = horizontal }
        end
        if rect_contains(horizontal.track, x, y) then
            return { axis = "x", part = "track", geom = horizontal }
        end
    end

    return nil
end

local function target_offset_for_track_click(hit, x, y, opts)
    local geom = hit.geom
    local track_click = opts.track_click or "jump"

    if track_click == "page" then
        local page = geom.viewport * (opts.page_fraction or 0.9)
        local thumb_center = hit.axis == "y"
            and (geom.thumb.y + geom.thumb.h * 0.5)
            or (geom.thumb.x + geom.thumb.w * 0.5)
        local point = hit.axis == "y" and y or x
        if point < thumb_center then
            return geom.offset - page
        end
        return geom.offset + page
    end

    local track_start = hit.axis == "y" and geom.track.y or geom.track.x
    local thumb_len = hit.axis == "y" and geom.thumb.h or geom.thumb.w
    local point = hit.axis == "y" and y or x
    if geom.travel <= 0 then return 0 end

    local t = (point - track_start - thumb_len * 0.5) / geom.travel
    return geom.max * clamp01(t)
end

local function drag_target_offset(drag, x, y)
    local geom = drag.geom
    if geom.travel <= 0 then return 0 end
    local point = drag.axis == "y" and y or x
    local track_start = drag.axis == "y" and geom.track.y or geom.track.x
    local t = (point - track_start - drag.grab_offset) / geom.travel
    return geom.max * clamp01(t)
end

local function clamp_target(metrics, axis_name, target)
    local max_offset = axis_name == "y" and metrics.resolved.max_scroll_y or metrics.resolved.max_scroll_x
    if target < 0 then return 0 end
    if target > max_offset then return max_offset end
    return target
end

local function scroll_to_axis(metrics, model, scroll_id, axis_name, target)
    target = clamp_target(metrics, axis_name, target)
    local x = metrics.resolved.scroll_x
    local y = metrics.resolved.scroll_y
    if axis_name == "y" then
        y = target
    else
        x = target
    end
    return update_scroll_model(model, scroll_id, x, y)
end

return function(opts)
    opts = opts or {}
    if opts.id == nil then error("edit_surface recipe requires opts.id", 2) end

    local defaults = copy_table(DEFAULTS)
    if opts.defaults ~= nil then
        for k, v in pairs(opts.defaults) do
            defaults[k] = v
        end
    end

    local axis = opts.scroll_axis or opts.axis or Style.ScrollY
    local scroll_id = opts.scroll_id or opts.id
    local node = common.build_shell(opts, defaults)
    local surfaces = {
        edit = {},
    }
    core.add_surface(surfaces.edit, opts.id, { id = opts.id })

    local function resolve_metrics(host, report, model, field, draw_opts)
        local hit = common.find_hit_box(report, opts.id)
        if hit == nil then return nil end

        local merged = merge_opts(opts, draw_opts)
        local reserve_mode = merged.reserve_track_space
        local reserve_visible = reserve_mode == true
        local cur_x, cur_y = model and interact.scroll_offset(model, scroll_id) or 0, 0

        local function resolve_with(reserve_now)
            return text_field_view.resolve(host, field, {
                x = hit.x,
                y = hit.y,
                w = hit.w,
                h = hit.h,
                padding = resolved_padding(merged.padding, axis, reserve_now, merged),
                text_key = merged.text_key,
                text_style = merged.text_style,
                composition_style = merged.composition_style,
                show_caret = merged.show_caret,
                blink_on = merged.blink_on,
                wrap = merged.wrap,
                wrap_width = merged.wrap_width,
                scroll_x = cur_x,
                scroll_y = cur_y,
            })
        end

        local resolved = resolve_with(reserve_visible)
        local visible = (axis_enabled(axis, "y") and resolved.max_scroll_y > 0)
            or (axis_enabled(axis, "x") and resolved.max_scroll_x > 0)

        if reserve_mode == "auto" and visible then
            reserve_visible = true
            resolved = resolve_with(true)
        end

        local metrics = {
            id = opts.id,
            scroll_id = scroll_id,
            axis = axis,
            hit = hit,
            resolved = resolved,
            visible = visible,
            reserve_visible = reserve_visible,
        }

        local has_vertical = axis_enabled(axis, "y") and resolved.max_scroll_y > 0
        local has_horizontal = axis_enabled(axis, "x") and resolved.max_scroll_x > 0
        metrics.vertical = has_vertical and axis_geometry(metrics, "y", has_horizontal, merged) or nil
        metrics.horizontal = has_horizontal and axis_geometry(metrics, "x", has_vertical, merged) or nil

        local pointer_x = model and model.pointer_x or nil
        local pointer_y = model and model.pointer_y or nil
        if pointer_x ~= nil and pointer_y ~= nil then
            metrics.hover = hit_part(metrics, pointer_x, pointer_y)
        end

        return metrics, merged
    end

    return core.bundle(node, surfaces, core.empty_route(), {
        sync_scroll = function(self, host, model, report, field, draw_opts)
            local metrics, merged = resolve_metrics(host, report, model, field, draw_opts)
            if metrics == nil then return model, false end

            local next_x, next_y = text_field_view.scroll_to_caret(
                metrics.resolved,
                field,
                metrics.resolved.scroll_x,
                metrics.resolved.scroll_y,
                merged.scroll_margin or 12
            )
            local next_model = update_scroll_model(model, scroll_id, next_x, next_y)
            return next_model, next_model ~= model
        end,

        draw = function(self, host, report, field, draw_opts)
            local scroll_model = draw_opts and draw_opts.scroll_model or nil
            local metrics, merged = resolve_metrics(host, report, scroll_model, field, draw_opts)
            if metrics == nil then return nil end

            local overlay_opts = merge_opts(merged, {
                padding = metrics.resolved.padding,
                scroll_x = metrics.resolved.scroll_x,
                scroll_y = metrics.resolved.scroll_y,
            })
            local result = common.draw_overlay(host, report, field, overlay_opts)
            if result ~= nil then
                result.scrollbar = metrics
                result.scrollbar_visible = metrics.visible
            end
            return result
        end,

        clamp_scroll_model = function(self, model, result)
            local metrics = result and result.scrollbar or nil
            if metrics == nil then return model end
            return update_scroll_model(model, scroll_id, metrics.resolved.scroll_x, metrics.resolved.scroll_y)
        end,

        draw_scrollbar = function(self, host, result, draw_opts)
            local metrics = result and result.scrollbar or nil
            if metrics == nil or not metrics.visible then return nil end

            local merged = merge_opts(opts, draw_opts)
            local drag = merged.drag
            local track_rgba8 = merged.track_rgba8 or 0x0f172aff
            local track_opacity = merged.track_opacity or 0.55
            local focused = merged.focused == true
            local hover_track_rgba8 = merged.hover_track_rgba8 or track_rgba8
            local focus_track_rgba8 = merged.focus_track_rgba8 or hover_track_rgba8
            local thumb_rgba8 = merged.thumb_rgba8 or 0x475569ff
            local thumb_hover_rgba8 = merged.thumb_hover_rgba8 or 0x93c5fdff
            local thumb_focus_rgba8 = merged.thumb_focus_rgba8 or thumb_hover_rgba8
            local thumb_drag_rgba8 = merged.thumb_drag_rgba8 or thumb_hover_rgba8
            local thumb_opacity = merged.thumb_opacity or 0.95
            local border_rgba8 = merged.border_rgba8
            local hover_border_rgba8 = merged.hover_border_rgba8 or border_rgba8
            local focus_border_rgba8 = merged.focus_border_rgba8 or hover_border_rgba8
            local border_opacity = merged.border_opacity or 1

            local function draw_axis(geom, hover, dragging)
                if geom == nil then return end
                local axis_track_rgba8 = hover and hover_track_rgba8 or (focused and focus_track_rgba8 or track_rgba8)
                local axis_thumb_rgba8 = dragging and thumb_drag_rgba8
                    or (hover and thumb_hover_rgba8)
                    or (focused and thumb_focus_rgba8)
                    or thumb_rgba8
                local axis_border_rgba8 = dragging and focus_border_rgba8
                    or (hover and hover_border_rgba8)
                    or (focused and focus_border_rgba8)
                    or border_rgba8

                host:fill_rect(geom.track.x, geom.track.y, geom.track.w, geom.track.h, axis_track_rgba8, track_opacity)
                host:fill_rect(geom.thumb.x, geom.thumb.y, geom.thumb.w, geom.thumb.h, axis_thumb_rgba8, thumb_opacity)
                if axis_border_rgba8 ~= nil then
                    host:stroke_rect(geom.thumb.x, geom.thumb.y, geom.thumb.w, geom.thumb.h, axis_border_rgba8, border_opacity)
                end
            end

            draw_axis(metrics.vertical,
                metrics.hover ~= nil and metrics.hover.axis == "y",
                drag ~= nil and drag.axis == "y")
            draw_axis(metrics.horizontal,
                metrics.hover ~= nil and metrics.hover.axis == "x",
                drag ~= nil and drag.axis == "x")

            if host.driver ~= nil and host.driver.set_cursor_kind ~= nil then
                if drag ~= nil then
                    host.driver:set_cursor_kind(Style.CursorGrabbing)
                elseif metrics.hover ~= nil then
                    if metrics.hover.part == "thumb" then
                        host.driver:set_cursor_kind(Style.CursorGrab)
                    else
                        host.driver:set_cursor_kind(Style.CursorPointer)
                    end
                end
            end

            return metrics
        end,

        contains = function(self, result, x, y)
            if result == nil or result.resolved == nil then return false end
            return text_field_view.contains(result.resolved, x, y)
        end,

        local_point = function(self, result, x, y)
            if result == nil or result.resolved == nil then return nil, nil end
            return text_field_view.local_point(result.resolved, x, y)
        end,

        scrollbar_contains = function(self, result, x, y)
            local metrics = result and result.scrollbar or nil
            return metrics ~= nil and hit_part(metrics, x, y) ~= nil
        end,

        scroll_pointer_pressed = function(self, model, result, x, y, draw_opts)
            local metrics = result and result.scrollbar or nil
            if metrics == nil then return model, false, nil end

            local hit = hit_part(metrics, x, y)
            if hit == nil then return model, false, nil end
            if hit.part == "thumb" then
                local grab_offset = hit.axis == "y"
                    and (y - hit.geom.thumb.y)
                    or (x - hit.geom.thumb.x)
                return model, true, {
                    id = scroll_id,
                    axis = hit.axis,
                    geom = hit.geom,
                    grab_offset = grab_offset,
                    draw_opts = merge_opts(opts, draw_opts),
                }
            end

            local target = target_offset_for_track_click(hit, x, y, merge_opts(opts, draw_opts))
            local next_model = scroll_to_axis(metrics, model, scroll_id, hit.axis, target)
            return next_model, true, nil
        end,

        scroll_pointer_moved = function(self, model, drag, x, y)
            if drag == nil or drag.id ~= scroll_id then return model, false, drag end
            local target = drag_target_offset(drag, x, y)
            local axis_name = drag.axis
            local current_x, current_y = interact.scroll_offset(model, scroll_id)
            local metrics = {
                resolved = {
                    scroll_x = current_x,
                    scroll_y = current_y,
                    max_scroll_x = axis_name == "x" and drag.geom.max or 0,
                    max_scroll_y = axis_name == "y" and drag.geom.max or 0,
                },
            }
            local next_model = scroll_to_axis(metrics, model, scroll_id, axis_name, target)
            return next_model, true, drag
        end,

        scroll_pointer_released = function(self, model, drag)
            if drag == nil or drag.id ~= scroll_id then return model, false, nil end
            return model, true, nil
        end,

        scroll_key = function(self, model, result, key, key_opts)
            local metrics = result and result.scrollbar or nil
            if metrics == nil or not metrics.visible then return model, false end
            key_opts = key_opts or {}

            local line_step = key_opts.line_step or 40
            local page_fraction = key_opts.page_fraction or 0.9
            local cur_x = metrics.resolved.scroll_x
            local cur_y = metrics.resolved.scroll_y

            if axis_enabled(axis, "y") then
                if key == "up" then
                    return scroll_to_axis(metrics, model, scroll_id, "y", cur_y - line_step), true
                elseif key == "down" then
                    return scroll_to_axis(metrics, model, scroll_id, "y", cur_y + line_step), true
                elseif key == "pageup" then
                    return scroll_to_axis(metrics, model, scroll_id, "y", cur_y - metrics.resolved.inner_h * page_fraction), true
                elseif key == "pagedown" then
                    return scroll_to_axis(metrics, model, scroll_id, "y", cur_y + metrics.resolved.inner_h * page_fraction), true
                elseif key == "home" then
                    return scroll_to_axis(metrics, model, scroll_id, "y", 0), true
                elseif key == "end" then
                    return scroll_to_axis(metrics, model, scroll_id, "y", metrics.resolved.max_scroll_y), true
                end
            end

            if axis_enabled(axis, "x") then
                if key == "left" then
                    return scroll_to_axis(metrics, model, scroll_id, "x", cur_x - line_step), true
                elseif key == "right" then
                    return scroll_to_axis(metrics, model, scroll_id, "x", cur_x + line_step), true
                elseif key == "home" then
                    return scroll_to_axis(metrics, model, scroll_id, "x", 0), true
                elseif key == "end" then
                    return scroll_to_axis(metrics, model, scroll_id, "x", metrics.resolved.max_scroll_x), true
                end
            end

            return model, false
        end,

        scroll_wheel = function(self, model, result, dx, dy, x, y)
            local metrics = result and result.scrollbar or nil
            if metrics == nil or not metrics.visible then return model, false end
            if not rect_contains(metrics.hit, x, y) then return model, false end

            local next_dx, next_dy = dx or 0, dy or 0
            if axis == Style.ScrollX then
                next_dy = 0
            elseif axis == Style.ScrollY then
                next_dx = 0
            end
            if next_dx == 0 and next_dy == 0 then return model, false end

            local next_model = model
            if next_dx ~= 0 then
                next_model = scroll_to_axis(metrics, next_model, scroll_id, "x", metrics.resolved.scroll_x + next_dx)
            end
            if next_dy ~= 0 then
                next_model = scroll_to_axis(metrics, next_model, scroll_id, "y", metrics.resolved.scroll_y + next_dy)
            end
            return next_model, next_model ~= model
        end,
    })
end
