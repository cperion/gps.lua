local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Core = T.Core
local View = T.View
local Style = T.Style

local M = {}

local HUGE = math.huge
local WORLD = 1000000000

local function max0(n)
    if n < 0 then return 0 end
    return n
end

local function id_key(id)
    if id == nil or id == Core.NoId then
        return nil
    end
    return id.value
end

local function rect_intersect(ax, ay, aw, ah, bx, by, bw, bh)
    local x1 = math.max(ax, bx)
    local y1 = math.max(ay, by)
    local x2 = math.min(ax + aw, bx + bw)
    local y2 = math.min(ay + ah, by + bh)
    local w = x2 - x1
    local h = y2 - y1
    if w <= 0 or h <= 0 then
        return nil
    end
    return x1, y1, w, h
end

local function scroll_lookup(scrolls, id)
    if scrolls == nil or id == nil or id == Core.NoId then
        return 0, 0
    end

    local k = id_key(id)
    if type(scrolls) == "table" and not pvm.classof(scrolls) and scrolls[k] ~= nil then
        local v = scrolls[k]
        if type(v) == "table" then
            return v.x or 0, v.y or 0
        end
    end

    for i = 1, #scrolls do
        local s = scrolls[i]
        if s.id == id then
            return s.x, s.y
        end
    end

    return 0, 0
end

local function cursor_name(cursor)
    if cursor == nil or cursor == Style.CursorDefault then return "default" end
    if cursor == Style.CursorPointer then return "pointer" end
    if cursor == Style.CursorText then return "text" end
    if cursor == Style.CursorMove then return "move" end
    if cursor == Style.CursorGrab then return "grab" end
    if cursor == Style.CursorGrabbing then return "grabbing" end
    if cursor == Style.CursorNotAllowed then return "not-allowed" end
    return "default"
end

local function pointer_inside_xywh(x, y, rx, ry, rw, rh)
    return x ~= nil and y ~= nil
       and x >= rx and y >= ry
       and x < rx + rw and y < ry + rh
end

local function driver_push_clip_rect(driver, x, y, w, h)
    if driver == nil then return end
    if driver.push_clip_rect then
        driver:push_clip_rect(x, y, w, h)
        return
    end
    if driver.push_clip then
        driver:push_clip(x, y, w, h)
    end
end

local function driver_pop_clip_rect(driver)
    if driver == nil then return end
    if driver.pop_clip_rect then
        driver:pop_clip_rect()
        return
    end
    if driver.pop_clip then
        driver:pop_clip()
    end
end

local function driver_draw_box(driver, x, y, w, h, box_visual)
    if driver == nil then return end
    if driver.draw_box then
        driver:draw_box(x, y, w, h, box_visual)
        return
    end
    if driver.draw_rect then
        driver:draw_rect(x, y, w, h, box_visual)
    end
end

local function run_common(driver, opts, want_report, g, p, c)
    opts = opts or {}

    local KPushTx = View.KPushTx
    local KPopTx = View.KPopTx
    local KPushClipRect = View.KPushClipRect
    local KPopClip = View.KPopClip
    local KPushScroll = View.KPushScroll
    local KPopScroll = View.KPopScroll
    local KBox = View.KBox
    local KText = View.KText
    local KPaint = View.KPaint
    local KHit = View.KHit
    local KFocus = View.KFocus
    local KCursor = View.KCursor
    local KDragSource = View.KDragSource
    local KDropTarget = View.KDropTarget
    local KDropSlot = View.KDropSlot

    local tx_x, tx_y = 0, 0
    local tx_stack_x, tx_stack_y = {}, {}
    local tx_top = 0

    local clip_x = { -WORLD }
    local clip_y = { -WORLD }
    local clip_w = { WORLD * 2 }
    local clip_h = { WORLD * 2 }
    local clip_top = 1

    local scroll_stack_x, scroll_stack_y = {}, {}
    local scroll_top = 0

    local pointer_x = opts.pointer_x
    local pointer_y = opts.pointer_y
    local hover_id = Core.NoId
    local cursor_id = Core.NoId
    local cursor = Style.CursorDefault
    local scroll_id = Core.NoId
    local collect_hits = want_report and opts.collect_hits or false
    local hits = want_report and {} or nil
    local focusables = want_report and {} or nil
    local scrollables = want_report and {} or nil
    local drag_sources = want_report and {} or nil
    local drop_targets = want_report and {} or nil
    local drop_slots = want_report and {} or nil

    for _, op in g, p, c do
        local kind = op.kind

        if kind == KPushTx then
            tx_top = tx_top + 1
            tx_stack_x[tx_top] = tx_x
            tx_stack_y[tx_top] = tx_y
            tx_x = tx_x + op.dx
            tx_y = tx_y + op.dy

        elseif kind == KPopTx then
            tx_x = tx_stack_x[tx_top] or 0
            tx_y = tx_stack_y[tx_top] or 0
            tx_stack_x[tx_top] = nil
            tx_stack_y[tx_top] = nil
            tx_top = tx_top - 1

        elseif kind == KPushClipRect then
            local abs_x = tx_x + op.x
            local abs_y = tx_y + op.y
            local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, op.w, op.h, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
            clip_top = clip_top + 1
            if ix == nil then
                clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top] = abs_x, abs_y, 0, 0
            else
                clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top] = ix, iy, iw, ih
            end
            driver_push_clip_rect(driver, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])

        elseif kind == KPopClip then
            driver_pop_clip_rect(driver)
            clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top] = nil, nil, nil, nil
            clip_top = clip_top - 1

        elseif kind == KPushScroll then
            local abs_x = tx_x + op.x
            local abs_y = tx_y + op.y
            local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, op.w, op.h, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
            local max_x = max0((op.dx or 0) - op.w)
            local max_y = max0((op.dy or 0) - op.h)
            if op.scroll_axis == Style.ScrollX then
                max_y = 0
            elseif op.scroll_axis == Style.ScrollY then
                max_x = 0
            end

            if want_report and ix ~= nil then
                scrollables[#scrollables + 1] = T.Interact.ScrollBox(
                    op.id,
                    op.scroll_axis or Style.ScrollBoth,
                    ix,
                    iy,
                    iw,
                    ih,
                    op.dx or 0,
                    op.dy or 0,
                    max_x,
                    max_y
                )
                if pointer_inside_xywh(pointer_x, pointer_y, ix, iy, iw, ih) then
                    scroll_id = op.id
                end
            end

            scroll_top = scroll_top + 1
            scroll_stack_x[scroll_top] = tx_x
            scroll_stack_y[scroll_top] = tx_y

            clip_top = clip_top + 1
            if ix == nil then
                clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top] = abs_x, abs_y, 0, 0
            else
                clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top] = ix, iy, iw, ih
            end
            driver_push_clip_rect(driver, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])

            local scroll_x, scroll_y = scroll_lookup(opts.scrolls, op.id)
            if scroll_x < 0 then scroll_x = 0 elseif scroll_x > max_x then scroll_x = max_x end
            if scroll_y < 0 then scroll_y = 0 elseif scroll_y > max_y then scroll_y = max_y end
            tx_x = tx_x - scroll_x
            tx_y = tx_y - scroll_y

        elseif kind == KPopScroll then
            driver_pop_clip_rect(driver)
            clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top] = nil, nil, nil, nil
            clip_top = clip_top - 1

            tx_x = scroll_stack_x[scroll_top] or 0
            tx_y = scroll_stack_y[scroll_top] or 0
            scroll_stack_x[scroll_top], scroll_stack_y[scroll_top] = nil, nil
            scroll_top = scroll_top - 1

        elseif kind == KBox then
            local abs_x = tx_x + op.x
            local abs_y = tx_y + op.y
            local ix = rect_intersect(abs_x, abs_y, op.w, op.h, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
            if ix ~= nil then
                driver_draw_box(driver, abs_x, abs_y, op.w, op.h, op.box_visual)
            end

        elseif kind == KText then
            local abs_x = tx_x + op.x
            local abs_y = tx_y + op.y
            local ix = rect_intersect(abs_x, abs_y, op.w, op.h, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
            if ix ~= nil and driver and driver.draw_text then
                driver:draw_text(abs_x, abs_y, op.w, op.h, op.text)
            end

        elseif kind == KPaint then
            local abs_x = tx_x + op.x
            local abs_y = tx_y + op.y
            local ix = rect_intersect(abs_x, abs_y, op.w, op.h, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
            if ix ~= nil and driver and driver.draw_paint and op.paint ~= nil then
                driver:draw_paint(abs_x, abs_y, op.w, op.h, op.paint)
            end

        elseif kind == KHit then
            if want_report then
                local abs_x = tx_x + op.x
                local abs_y = tx_y + op.y
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, op.w, op.h, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil then
                    if collect_hits then
                        hits[#hits + 1] = T.Interact.HitBox(op.id, ix, iy, iw, ih)
                    end
                    if pointer_inside_xywh(pointer_x, pointer_y, ix, iy, iw, ih) then
                        hover_id = op.id
                    end
                end
            end

        elseif kind == KFocus then
            if want_report then
                local abs_x = tx_x + op.x
                local abs_y = tx_y + op.y
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, op.w, op.h, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil then
                    local slot = #focusables + 1
                    focusables[slot] = T.Interact.FocusBox(op.id, slot, ix, iy, iw, ih)
                end
            end

        elseif kind == KCursor then
            if want_report then
                local abs_x = tx_x + op.x
                local abs_y = tx_y + op.y
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, op.w, op.h, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil and pointer_inside_xywh(pointer_x, pointer_y, ix, iy, iw, ih) then
                    cursor = op.cursor
                    cursor_id = op.id
                end
            end

        elseif kind == KDragSource then
            if want_report then
                local abs_x = tx_x + op.x
                local abs_y = tx_y + op.y
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, op.w, op.h, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil then
                    drag_sources[#drag_sources + 1] = T.Interact.DragSourceBox(op.id, ix, iy, iw, ih)
                end
            end

        elseif kind == KDropTarget then
            if want_report then
                local abs_x = tx_x + op.x
                local abs_y = tx_y + op.y
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, op.w, op.h, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil then
                    drop_targets[#drop_targets + 1] = T.Interact.DropTargetBox(op.id, ix, iy, iw, ih)
                end
            end

        elseif kind == KDropSlot then
            if want_report then
                local abs_x = tx_x + op.x
                local abs_y = tx_y + op.y
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, op.w, op.h, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil then
                    drop_slots[#drop_slots + 1] = T.Interact.DropSlotBox(op.id, ix, iy, iw, ih)
                end
            end
        end
    end

    if want_report then
        if driver and driver.set_cursor_kind then
            driver:set_cursor_kind(cursor)
        elseif driver and driver.set_cursor then
            driver:set_cursor(cursor_name(cursor))
        end

        return T.Interact.Report(
            hover_id,
            cursor_id,
            cursor,
            scroll_id,
            hits,
            focusables,
            scrollables,
            drag_sources,
            drop_targets,
            drop_slots
        )
    end
end

function M.run(driver, opts, g, p, c)
    return run_common(driver, opts, true, g, p, c)
end

function M.draw(driver, g, p, c)
    return run_common(driver, nil, false, g, p, c)
end

M.T = T

return M
