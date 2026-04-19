local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local b = require("ui.build")
local tw = require("ui.tw")
local interact = require("ui.interact")
local core = require("ui.recipes._core")

local T = ui_asdl.T
local Auth = T.Auth
local Style = T.Style

local function classof(v)
    return pvm.classof(v)
end

local function is_token(v)
    local cls = classof(v)
    return cls == Style.Token or cls == Style.Group or cls == Style.TokenList
end

local function is_node(v)
    local cls = classof(v)
    return cls and Auth.Node.members[cls] or false
end

local function merge_opts(base, extra)
    local out = {}
    if base ~= nil then
        for k, v in pairs(base) do out[k] = v end
    end
    if extra ~= nil then
        for k, v in pairs(extra) do out[k] = v end
    end
    return out
end

local function append_items(out, items)
    for i = 1, #items do out[#out + 1] = items[i] end
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

local function want_reserve_space(opts)
    local mode = opts.reserve_track_space
    if mode == "auto" then
        return opts.scrollbar_visible == true
    end
    return mode == true
end

local function reserve_space_px(opts)
    if not want_reserve_space(opts) then return 0 end
    if opts.reserve_space_px ~= nil then return opts.reserve_space_px end
    return thickness_px(opts) + inset_px(opts) * 2
end

local function collect_source_items(opts)
    if opts.items ~= nil then
        return opts.items
    end

    local items = {}
    if opts.styles ~= nil then
        items[#items + 1] = opts.styles
    end
    if opts.child ~= nil then
        items[#items + 1] = opts.child
    elseif opts.children ~= nil then
        append_items(items, opts.children)
    else
        error("scroll_view recipe requires opts.items, opts.child, or opts.children", 3)
    end
    return items
end

local function finish_child(children)
    if #children == 0 then return Auth.Empty end
    if #children == 1 then return children[1] end
    return b.fragment(children)
end

local SPACE_STEPS = { 0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 72, 80, 96 }

local function space_token_for_px(px)
    for i = 1, #SPACE_STEPS do
        if SPACE_STEPS[i] >= px then return SPACE_STEPS[i] end
    end
    return SPACE_STEPS[#SPACE_STEPS]
end

local function build_node(opts)
    local items = collect_source_items(opts)
    local axis = opts.axis or Style.ScrollY
    local styles = {}
    local children = {}

    for i = 1, #items do
        local v = items[i]
        if v ~= nil and v ~= false then
            if is_token(v) then
                styles[#styles + 1] = v
            elseif is_node(v) then
                children[#children + 1] = v
            else
                error("scroll_view recipe items accept only style tokens/groups/lists and authored child nodes", 3)
            end
        end
    end

    local reserve = reserve_space_px(opts)
    local child = finish_child(children)
    if reserve > 0 then
        local reserve_space = space_token_for_px(reserve)
        local wrapper_items = {}
        if axis_enabled(axis, "y") then
            wrapper_items[#wrapper_items + 1] = tw.w_full
            wrapper_items[#wrapper_items + 1] = tw.pr(reserve_space)
        end
        if axis_enabled(axis, "x") then
            wrapper_items[#wrapper_items + 1] = tw.h_full
            wrapper_items[#wrapper_items + 1] = tw.pb(reserve_space)
        end
        wrapper_items[#wrapper_items + 1] = child
        child = b.box(wrapper_items)
    end

    local scroll_items = {}
    append_items(scroll_items, styles)
    scroll_items[#scroll_items + 1] = child
    return b.scroll(opts.id, axis, scroll_items)
end

local function axis_geometry(box, axis_name, offset, has_cross, opts)
    local inset = inset_px(opts)
    local thickness = thickness_px(opts)
    local reserve_space = reserve_space_px(opts)
    local reserve = has_cross and (thickness + inset) or 0

    local viewport = axis_name == "y" and box.h or box.w
    local content = axis_name == "y" and box.content_h or box.content_w
    local max_offset = axis_name == "y" and box.max_y or box.max_x
    if viewport <= 0 or content <= viewport or max_offset <= 0 then
        return nil
    end

    local track
    if axis_name == "y" then
        local strip = reserve_space > 0 and reserve_space or (thickness + inset * 2)
        local extra = max0(strip - thickness)
        track = {
            x = box.x + box.w - strip + math.floor(extra * 0.5),
            y = box.y + inset,
            w = thickness,
            h = max0(box.h - inset * 2 - reserve),
        }
    else
        local strip = reserve_space > 0 and reserve_space or (thickness + inset * 2)
        local extra = max0(strip - thickness)
        track = {
            x = box.x + inset,
            y = box.y + box.h - strip + math.floor(extra * 0.5),
            w = max0(box.w - inset * 2 - reserve),
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

local function hit_part(resolved, x, y)
    local vertical = resolved.vertical
    local horizontal = resolved.horizontal

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

local function scroll_to_axis_offset(model, report, id, axis_name, target)
    local cur_x, cur_y = interact.scroll_offset(model, id)
    local next_x, next_y = cur_x, cur_y
    if axis_name == "y" then
        next_y = select(2, interact.clamp_scroll_position(report, id, cur_x, target))
        return interact.apply(model, T.Interact.ScrollBy(id, 0, next_y - cur_y), report)
    end
    next_x = interact.clamp_scroll_position(report, id, target, cur_y)
    return interact.apply(model, T.Interact.ScrollBy(id, next_x - cur_x, 0), report)
end

local function key_scroll(model, report, id, axis, key, opts)
    opts = opts or {}
    local box = interact.scroll_box(report, id)
    if box == nil then return model, false end

    local line_step = opts.line_step or 40
    local page_fraction = opts.page_fraction or 0.9
    local cur_x, cur_y = interact.scroll_offset(model, id)

    if axis_enabled(axis, "y") then
        if key == "up" then
            return scroll_to_axis_offset(model, report, id, "y", cur_y - line_step), true
        elseif key == "down" then
            return scroll_to_axis_offset(model, report, id, "y", cur_y + line_step), true
        elseif key == "pageup" then
            return scroll_to_axis_offset(model, report, id, "y", cur_y - box.h * page_fraction), true
        elseif key == "pagedown" then
            return scroll_to_axis_offset(model, report, id, "y", cur_y + box.h * page_fraction), true
        elseif key == "home" then
            return scroll_to_axis_offset(model, report, id, "y", 0), true
        elseif key == "end" then
            return scroll_to_axis_offset(model, report, id, "y", box.max_y), true
        end
    end

    if axis_enabled(axis, "x") then
        if key == "left" then
            return scroll_to_axis_offset(model, report, id, "x", cur_x - line_step), true
        elseif key == "right" then
            return scroll_to_axis_offset(model, report, id, "x", cur_x + line_step), true
        elseif key == "home" then
            return scroll_to_axis_offset(model, report, id, "x", 0), true
        elseif key == "end" then
            return scroll_to_axis_offset(model, report, id, "x", box.max_x), true
        end
    end

    return model, false
end

return function(opts)
    opts = opts or {}
    if opts.id == nil then error("scroll_view recipe requires opts.id", 2) end

    local axis = opts.axis or Style.ScrollY
    local node = build_node(opts)
    local surfaces = { scroll = {} }
    core.add_surface(surfaces.scroll, opts.id, { id = opts.id, axis = axis })

    return core.bundle(node, surfaces, core.empty_route(), {
        visible = function(self, report)
            local box = interact.scroll_box(report, opts.id)
            if box == nil then return false end
            return (axis_enabled(axis, "y") and box.max_y > 0)
                or (axis_enabled(axis, "x") and box.max_x > 0)
        end,

        sync_visibility = function(self, report, current_visible)
            local visible = self:visible(report)
            return visible, visible ~= (current_visible == true)
        end,

        resolve = function(self, report, model, draw_opts)
            draw_opts = merge_opts(opts, draw_opts)
            local box = interact.scroll_box(report, opts.id)
            if box == nil then return nil end

            local offset_x, offset_y = interact.scroll_offset(model, opts.id)
            offset_x, offset_y = interact.clamp_scroll_position(report, opts.id, offset_x, offset_y)

            local wants_vertical = axis_enabled(axis, "y")
            local wants_horizontal = axis_enabled(axis, "x")
            local has_vertical = wants_vertical and box.max_y > 0
            local has_horizontal = wants_horizontal and box.max_x > 0

            local resolved = {
                id = opts.id,
                axis = axis,
                box = box,
                offset_x = offset_x,
                offset_y = offset_y,
                vertical = axis_geometry(box, "y", offset_y, has_horizontal, draw_opts),
                horizontal = axis_geometry(box, "x", offset_x, has_vertical, draw_opts),
            }

            local pointer_x = model and model.pointer_x or nil
            local pointer_y = model and model.pointer_y or nil
            if pointer_x ~= nil and pointer_y ~= nil then
                resolved.hover = hit_part(resolved, pointer_x, pointer_y)
            end
            return resolved
        end,

        draw = function(self, host, report, model, draw_opts)
            local resolved = self:resolve(report, model, draw_opts)
            if resolved == nil then return nil end

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
                host:fill_rect(
                    geom.thumb.x,
                    geom.thumb.y,
                    geom.thumb.w,
                    geom.thumb.h,
                    axis_thumb_rgba8,
                    thumb_opacity
                )
                if axis_border_rgba8 ~= nil then
                    host:stroke_rect(geom.thumb.x, geom.thumb.y, geom.thumb.w, geom.thumb.h, axis_border_rgba8, border_opacity)
                end
            end

            draw_axis(resolved.vertical,
                resolved.hover ~= nil and resolved.hover.axis == "y",
                drag ~= nil and drag.axis == "y")
            draw_axis(resolved.horizontal,
                resolved.hover ~= nil and resolved.hover.axis == "x",
                drag ~= nil and drag.axis == "x")

            if host.driver ~= nil and host.driver.set_cursor_kind ~= nil then
                if drag ~= nil then
                    host.driver:set_cursor_kind(Style.CursorGrabbing)
                elseif resolved.hover ~= nil then
                    if resolved.hover.part == "thumb" then
                        host.driver:set_cursor_kind(Style.CursorGrab)
                    else
                        host.driver:set_cursor_kind(Style.CursorPointer)
                    end
                end
            end

            return resolved
        end,

        contains = function(self, result, x, y)
            if result == nil then return false end
            return hit_part(result, x, y) ~= nil
        end,

        pointer_pressed = function(self, model, report, x, y, draw_opts)
            local resolved = self:resolve(report, model, draw_opts)
            if resolved == nil then return model, false, resolved, nil end

            local hit = hit_part(resolved, x, y)
            if hit == nil then return model, false, resolved, nil end

            local next_model = interact.apply(model, T.Interact.SetPointer(x, y), report)
            if hit.part == "thumb" then
                local grab_offset = hit.axis == "y"
                    and (y - hit.geom.thumb.y)
                    or (x - hit.geom.thumb.x)
                return next_model, true, resolved, {
                    id = opts.id,
                    axis = hit.axis,
                    geom = hit.geom,
                    grab_offset = grab_offset,
                    draw_opts = merge_opts(opts, draw_opts),
                }
            end

            local current = hit.axis == "y" and resolved.offset_y or resolved.offset_x
            local target = target_offset_for_track_click(hit, x, y, merge_opts(opts, draw_opts))
            local delta = target - current
            if hit.axis == "y" then
                next_model = interact.apply(next_model, T.Interact.ScrollBy(opts.id, 0, delta), report)
            else
                next_model = interact.apply(next_model, T.Interact.ScrollBy(opts.id, delta, 0), report)
            end
            return next_model, true, resolved, nil
        end,

        pointer_moved = function(self, model, report, drag, x, y)
            if drag == nil or drag.id ~= opts.id then return model, false, drag end
            local next_model = interact.apply(model, T.Interact.SetPointer(x, y), report)
            local target = drag_target_offset(drag, x, y)
            local current_x, current_y = interact.scroll_offset(next_model, opts.id)
            if drag.axis == "y" then
                next_model = interact.apply(next_model, T.Interact.ScrollBy(opts.id, 0, target - current_y), report)
            else
                next_model = interact.apply(next_model, T.Interact.ScrollBy(opts.id, target - current_x, 0), report)
            end
            local resolved = self:resolve(report, next_model, drag.draw_opts)
            if resolved ~= nil then
                local geom = drag.axis == "y" and resolved.vertical or resolved.horizontal
                if geom ~= nil then drag.geom = geom end
            end
            return next_model, true, drag
        end,

        pointer_released = function(self, model, report, drag, x, y)
            if drag == nil or drag.id ~= opts.id then return model, false, nil end
            local next_model = interact.apply(model, T.Interact.SetPointer(x, y), report)
            return next_model, true, nil
        end,

        key = function(self, model, report, key, key_opts)
            return key_scroll(model, report, opts.id, axis, key, key_opts)
        end,
    })
end
