-- ui/draw.lua
--
-- Concrete UI drawing reducer.
--
-- This reducer walks lowered `UI.Node` trees, resolves local frames through
-- `ui.measure`, picks pointer-variant style packs from explicit interaction
-- wrappers, and emits drawing calls to a backend.
--
-- Minimal backend surface used by the default path:
--   :set_color_rgba8(rgba8, opacity)   -- preferred
--   or :set_color(r, g, b, a)
--   :set_font_id(font_id)              -- preferred
--   or :set_font(font_id)
--   :fill_rect(x, y, w, h[, radius])
--   :stroke_rect(x, y, w, h, thickness[, radius])
--   :draw_line(x1, y1, x2, y2, thickness)
--   :draw_text(text, x, y, width, align)
--   :draw_text_box(text, x, y, w, h, style) -- optional richer path
--   :push_clip(x, y, w, h)
--   :pop_clip()
--
-- Text drawing stays backend-pluggable. Callers may override it with
-- `opts.text_draw(args)` to integrate a real text backend.

local schema = require("ui.asdl")
local measure = require("ui.measure")

local T = schema.T

local draw = { T = T, schema = schema, measure = measure }

local math_abs = math.abs
local math_floor = math.floor
local math_huge = math.huge
local math_max = math.max
local math_min = math.min
local getmetatable = getmetatable

local INF = math_huge

local POINTER_IDLE = T.Interact.Idle
local POINTER_HOVERED = T.Interact.Hovered
local POINTER_PRESSED = T.Interact.Pressed
local POINTER_DRAGGING = T.Interact.Dragging

local AXIS_ROW = T.Layout.AxisRow
local AXIS_ROW_REV = T.Layout.AxisRowReverse
local AXIS_COL = T.Layout.AxisCol
local AXIS_COL_REV = T.Layout.AxisColReverse

local WRAP_NO = T.Layout.WrapNoWrap
local WRAP_WRAP_REV = T.Layout.WrapWrapReverse

local MAIN_END = T.Layout.MainEnd
local MAIN_CENTER = T.Layout.MainCenter
local MAIN_SPACE_BETWEEN = T.Layout.MainSpaceBetween
local MAIN_SPACE_AROUND = T.Layout.MainSpaceAround
local MAIN_SPACE_EVENLY = T.Layout.MainSpaceEvenly

local CROSS_AUTO = T.Layout.CrossAuto
local CROSS_START = T.Layout.CrossStart
local CROSS_END = T.Layout.CrossEnd
local CROSS_CENTER = T.Layout.CrossCenter
local CROSS_STRETCH = T.Layout.CrossStretch
local CROSS_BASELINE = T.Layout.CrossBaseline

local CONTENT_END = T.Layout.ContentEnd
local CONTENT_CENTER = T.Layout.ContentCenter
local CONTENT_STRETCH = T.Layout.ContentStretch
local CONTENT_SPACE_BETWEEN = T.Layout.ContentSpaceBetween
local CONTENT_SPACE_AROUND = T.Layout.ContentSpaceAround
local CONTENT_SPACE_EVENLY = T.Layout.ContentSpaceEvenly

local BASIS_AUTO = T.Layout.BasisAuto
local BASIS_CONTENT = T.Layout.BasisContent

local TEXT_CENTER = T.Layout.TextCenter
local TEXT_END = T.Layout.TextEnd
local TEXT_JUSTIFY = T.Layout.TextJustify
local TEXT_NOWRAP = T.Layout.TextNoWrap
local OVERFLOW_VISIBLE = T.Layout.OverflowVisible

local mtSpanExact = getmetatable(measure.exact(0))
local mtSpanAtMost = getmetatable(measure.at_most(0))
local mtBasisPx = getmetatable(T.Layout.BasisPx(0))
local mtBasisPercent = getmetatable(T.Layout.BasisPercent(0))
local mtColorPack = getmetatable(T.DS.ColorPack(0, 0, 0, 0))

local function clamp(v, lo, hi)
    if lo and v < lo then
        v = lo
    end
    if hi and v > hi then
        v = hi
    end
    return v
end

local function mkframe(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

local function is_row_axis(axis)
    return axis == AXIS_ROW or axis == AXIS_ROW_REV
end

local function is_reverse_axis(axis)
    return axis == AXIS_ROW_REV or axis == AXIS_COL_REV
end

local function is_wrap_reverse(wrap)
    return wrap == WRAP_WRAP_REV
end

local function span_available(span)
    if span == measure.UNCONSTRAINED then
        return INF, false
    end
    local mt = getmetatable(span)
    if mt == mtSpanExact then
        return span.px, true
    end
    if mt == mtSpanAtMost then
        return span.px, false
    end
    return INF, false
end

local function exact_or_atmost(px, exact)
    if px == INF then
        return measure.UNCONSTRAINED
    end
    if exact then
        return measure.exact(px)
    end
    return measure.at_most(px)
end

local function baseline_num(baseline)
    if baseline == measure.NO_BASELINE or baseline == nil then
        return nil
    end
    return baseline.px
end

local function style_insets(style)
    local h = (style.pad_h or 0) + (style.border_w or 0)
    local v = (style.pad_v or 0) + (style.border_w or 0)
    return h, v
end

local function main_margins(margin, axis)
    if axis == AXIS_ROW then
        return margin.l, margin.r
    end
    if axis == AXIS_ROW_REV then
        return margin.r, margin.l
    end
    if axis == AXIS_COL then
        return margin.t, margin.b
    end
    return margin.b, margin.t
end

local function cross_margins(margin, axis)
    if axis == AXIS_ROW or axis == AXIS_ROW_REV then
        return margin.t, margin.b
    end
    return margin.l, margin.r
end

local function main_size_of(m, axis)
    return is_row_axis(axis) and m.used_w or m.used_h
end

local function cross_size_of(m, axis)
    return is_row_axis(axis) and m.used_h or m.used_w
end

local function intrinsic_min_main(intr, axis)
    return is_row_axis(axis) and intr.min_w or intr.min_h
end

local function intrinsic_max_main(intr, axis)
    return is_row_axis(axis) and intr.max_w or intr.max_h
end

local function intrinsic_min_cross(intr, axis)
    return is_row_axis(axis) and intr.min_h or intr.min_w
end

local function intrinsic_max_cross(intr, axis)
    return is_row_axis(axis) and intr.max_h or intr.max_w
end

local function resolve_basis_value(spec, available, content_value)
    if spec == BASIS_AUTO or spec == BASIS_CONTENT then
        return content_value
    end
    local mt = getmetatable(spec)
    if mt == mtBasisPx then
        return spec.px
    end
    if mt == mtBasisPercent then
        if available ~= INF then
            return available * spec.ratio
        end
        return content_value
    end
    return content_value
end

local function build_measure_opts(opts)
    opts = opts or {}
    if opts.measure then
        return opts.measure
    end
    return {
        cache = opts.measure_cache or opts.cache,
        text_measure = opts.text_measure,
        font_height = opts.font_height,
        stats = opts.measure_stats,
    }
end

local function resolve_local_frame(node, outer, measure_opts)
    local m = measure.measure(node, measure.exact_constraint_from_frame(outer), measure_opts)
    return mkframe(outer.x, outer.y, m.used_w, m.used_h), m
end

local function inside(px, py, x, y, w, h)
    return px >= x and py >= y and px < x + w and py < y + h
end

local function intersect_clip(x, y, w, h, top)
    if not top then
        return x, y, w, h
    end
    local x2 = math_max(x, top[1])
    local y2 = math_max(y, top[2])
    local nw = math_max(0, math_min(x + w, top[1] + top[3]) - x2)
    local nh = math_max(0, math_min(y + h, top[2] + top[4]) - y2)
    return x2, y2, nw, nh
end

local function pointer_for_id_from_state(state, id)
    if not id or id == "" or not state then
        return POINTER_IDLE
    end
    if state.dragging == id then
        return POINTER_DRAGGING
    end
    if state.pressed == id or state.active == id then
        return POINTER_PRESSED
    end
    if state.hot == id then
        return POINTER_HOVERED
    end
    return POINTER_IDLE
end

local function pointer_for_id_from_hot(hot, id)
    if not id or id == "" or not hot then
        return POINTER_IDLE
    end
    if hot.dragging == id then
        return POINTER_DRAGGING
    end
    if hot.pressed == id or hot.active == id then
        return POINTER_PRESSED
    end
    if hot.hovered == id or hot.hot == id then
        return POINTER_HOVERED
    end
    return POINTER_IDLE
end

local function pointer_for_id(opts, id)
    if opts.pointer_for then
        return opts.pointer_for(id, opts)
    end
    if opts.state then
        return pointer_for_id_from_state(opts.state, id)
    end
    if opts.session and opts.session.state then
        return pointer_for_id_from_state(opts.session.state, id)
    end
    if opts.hot then
        return pointer_for_id_from_hot(opts.hot, id)
    end
    return POINTER_IDLE
end

local function pick_pack(pack, pointer)
    if not pack then
        return 0
    end
    if pointer == POINTER_HOVERED then
        return pack.hovered
    end
    if pointer == POINTER_PRESSED then
        return pack.pressed
    end
    if pointer == POINTER_DRAGGING then
        return pack.dragging
    end
    return pack.idle
end

local function text_align_name(align)
    if align == TEXT_CENTER then
        return "center"
    end
    if align == TEXT_END then
        return "right"
    end
    if align == TEXT_JUSTIFY then
        return "justify"
    end
    return "left"
end

local function rgba8_to_float(rgba8)
    local a = (rgba8 % 256) / 255
    rgba8 = math_floor(rgba8 / 256)
    local b = (rgba8 % 256) / 255
    rgba8 = math_floor(rgba8 / 256)
    local g = (rgba8 % 256) / 255
    rgba8 = math_floor(rgba8 / 256)
    local r = (rgba8 % 256) / 255
    return r, g, b, a
end

local function backend_set_color(backend, rgba8, opacity)
    if not backend then
        return
    end
    opacity = opacity or 1
    if backend.set_color_rgba8 then
        backend:set_color_rgba8(rgba8, opacity)
        return
    end
    if backend.set_color then
        local r, g, b, a = rgba8_to_float(rgba8)
        backend:set_color(r, g, b, a * opacity)
    end
end

local function backend_set_font(backend, font_id)
    if not backend then
        return
    end
    if backend.set_font_id then
        backend:set_font_id(font_id)
    elseif backend.set_font then
        backend:set_font(font_id)
    end
end

local function build_ctx(frame, opts)
    opts = opts or {}
    return {
        backend = opts.backend,
        frame = frame,
        opts = opts,
        measure_opts = build_measure_opts(opts),
        tx = 0,
        ty = 0,
        tx_stack = {},
        clip_stack = {},
    }
end

local function push_offset(ctx, dx, dy)
    ctx.tx_stack[#ctx.tx_stack + 1] = { ctx.tx, ctx.ty }
    ctx.tx = ctx.tx + dx
    ctx.ty = ctx.ty + dy
end

local function pop_offset(ctx)
    local t = ctx.tx_stack[#ctx.tx_stack]
    ctx.tx_stack[#ctx.tx_stack] = nil
    ctx.tx = t[1]
    ctx.ty = t[2]
end

local function push_clip(ctx, x, y, w, h)
    local ax, ay, nw, nh = intersect_clip(x, y, w, h, ctx.clip_stack[#ctx.clip_stack])
    ctx.clip_stack[#ctx.clip_stack + 1] = { ax, ay, nw, nh }
    if ctx.backend and ctx.backend.push_clip then
        ctx.backend:push_clip(ax, ay, nw, nh)
    end
end

local function pop_clip(ctx)
    ctx.clip_stack[#ctx.clip_stack] = nil
    if ctx.backend and ctx.backend.pop_clip then
        ctx.backend:pop_clip()
    end
end

local function visible_in_clip(ctx, x, y, w, h)
    local top = ctx.clip_stack[#ctx.clip_stack]
    if not top then
        return true
    end
    return not (x + w <= top[1] or y + h <= top[2] or x >= top[1] + top[3] or y >= top[2] + top[4])
end

local function resolve_draw_id(active_id, fallback)
    if active_id ~= nil and active_id ~= "" then
        return active_id
    end
    if fallback ~= nil and fallback ~= "" then
        return fallback
    end
    return nil
end

local function fill_rect(backend, x, y, w, h, radius)
    if not backend then
        return
    end
    if radius and radius > 0 and backend.fill_round_rect then
        backend:fill_round_rect(x, y, w, h, radius)
    elseif backend.fill_rect then
        backend:fill_rect(x, y, w, h, radius)
    end
end

local function stroke_rect(backend, x, y, w, h, thickness, radius)
    if not backend then
        return
    end
    if radius and radius > 0 and backend.stroke_round_rect then
        backend:stroke_round_rect(x, y, w, h, thickness, radius)
    elseif backend.stroke_rect then
        backend:stroke_rect(x, y, w, h, thickness, radius)
    end
end

local function draw_box_chrome(frame, style, active_id, fallback_tag, ctx)
    local id = resolve_draw_id(active_id, fallback_tag)
    local pointer = pointer_for_id(ctx.opts, id)
    local bg = pick_pack(style.bg, pointer)
    local border = pick_pack(style.border, pointer)
    local opacity = pick_pack(style.opacity, pointer)
    local radius = pick_pack(style.radius, pointer)
    local x = frame.x + ctx.tx
    local y = frame.y + ctx.ty
    local w = frame.w
    local h = frame.h

    if not visible_in_clip(ctx, x, y, w, h) then
        return
    end

    if bg and bg ~= 0 then
        backend_set_color(ctx.backend, bg, opacity)
        fill_rect(ctx.backend, x, y, w, h, radius)
    end

    if style.border_w and style.border_w > 0 and border and border ~= 0 then
        backend_set_color(ctx.backend, border, opacity)
        stroke_rect(ctx.backend, x, y, w, h, style.border_w, radius)
    end
end

local function runtime_lookup(map, name, fallback)
    if map then
        local v = map[name]
        if v ~= nil then
            return v
        end
    end
    return fallback
end

local function resolve_paint_scalar(runtime, scalar)
    if scalar.kind == "ScalarLit" then
        return scalar.n
    end
    return runtime_lookup(runtime and runtime.numbers, scalar.ref.name, 0)
end

local function resolve_paint_text(runtime, text_value)
    if text_value.kind == "TextLit" then
        return text_value.text
    end
    return runtime_lookup(runtime and runtime.texts, text_value.ref.name, "")
end

local function resolve_paint_color(runtime, color_value, active_id, tag, opts)
    local id = resolve_draw_id(active_id, tag)
    local pointer = pointer_for_id(opts, id)
    if color_value.kind == "ColorPackLit" then
        return pick_pack(color_value.pack, pointer), 1
    end
    local v = runtime_lookup(runtime and runtime.colors, color_value.ref.name, 0)
    if getmetatable(v) == mtColorPack then
        return pick_pack(v, pointer), 1
    end
    if type(v) == "table" and v.idle ~= nil then
        return pick_pack(v, pointer), 1
    end
    return v or 0, 1
end

local function draw_text_payload(text, x, y, w, h, style, active_id, ctx)
    local id = resolve_draw_id(active_id, nil)
    local pointer = pointer_for_id(ctx.opts, id)
    local color = pick_pack(style.color, pointer)
    local opacity = pick_pack(style.opacity, pointer)

    if not visible_in_clip(ctx, x, y, w, h) then
        return
    end

    backend_set_font(ctx.backend, style.font_id)
    backend_set_color(ctx.backend, color, opacity)

    if ctx.opts.text_draw then
        ctx.opts.text_draw({
            backend = ctx.backend,
            text = text,
            x = x,
            y = y,
            w = w,
            h = h,
            style = style,
            id = id,
            pointer = pointer,
        })
        return
    end

    if ctx.backend and ctx.backend.draw_text_box then
        ctx.backend:draw_text_box(text, x, y, w, h, style)
        return
    end

    if ctx.backend and ctx.backend.draw_text then
        local width = (style.wrap == TEXT_NOWRAP and style.overflow == OVERFLOW_VISIBLE) and nil or math_max(1, w)
        ctx.backend:draw_text(text, x, y, width, text_align_name(style.align))
    end
end

local function flex_collect_infos(node, constraint, measure_opts)
    local axis = node.axis
    local avail_w = span_available(constraint.w)
    local avail_h = span_available(constraint.h)
    local avail_main = is_row_axis(axis) and avail_w or avail_h
    local infos = {}
    for i = 1, #node.children do
        local item = node.children[i]
        local m = measure.measure(item.node, constraint, measure_opts)
        local ml, mr = main_margins(item.margin, axis)
        local mt, mb = cross_margins(item.margin, axis)
        infos[i] = {
            item = item,
            measure = m,
            base = resolve_basis_value(item.basis, avail_main, main_size_of(m, axis)),
            min_main = intrinsic_min_main(m.intrinsic, axis),
            max_main = intrinsic_max_main(m.intrinsic, axis),
            min_cross = intrinsic_min_cross(m.intrinsic, axis),
            max_cross = intrinsic_max_cross(m.intrinsic, axis),
            main_margin_start = ml,
            main_margin_end = mr,
            cross_margin_start = mt,
            cross_margin_end = mb,
        }
    end
    return infos, avail_main
end

local function distribute_line(infos, indices, avail_main, gap)
    local n = #indices
    local sizes = {}
    local frozen = {}
    for i = 1, n do
        sizes[indices[i]] = infos[indices[i]].base
    end
    if avail_main == INF then
        return sizes
    end
    while true do
        local used = gap * math_max(0, n - 1)
        local weight = 0
        for i = 1, n do
            local idx = indices[i]
            local inf = infos[idx]
            used = used + inf.main_margin_start + inf.main_margin_end
            if frozen[idx] then
                used = used + sizes[idx]
            else
                used = used + inf.base
            end
        end
        local free = avail_main - used
        if math_abs(free) < 1e-6 then
            break
        end
        if free > 0 then
            for i = 1, n do
                local idx = indices[i]
                if not frozen[idx] and infos[idx].item.grow > 0 then
                    weight = weight + infos[idx].item.grow
                end
            end
        else
            for i = 1, n do
                local idx = indices[i]
                local inf = infos[idx]
                if not frozen[idx] and inf.item.shrink > 0 then
                    weight = weight + inf.item.shrink * inf.base
                end
            end
        end
        if weight <= 0 then
            break
        end
        local clamped = false
        for i = 1, n do
            local idx = indices[i]
            if not frozen[idx] then
                local inf = infos[idx]
                local target
                if free > 0 then
                    target = inf.item.grow > 0 and (inf.base + free * (inf.item.grow / weight)) or inf.base
                else
                    local sw = inf.item.shrink * inf.base
                    target = sw > 0 and (inf.base + free * (sw / weight)) or inf.base
                end
                local cl = clamp(target, inf.min_main, inf.max_main)
                if cl ~= target then
                    sizes[idx] = cl
                    frozen[idx] = true
                    clamped = true
                end
            end
        end
        if not clamped then
            for i = 1, n do
                local idx = indices[i]
                if not frozen[idx] then
                    local inf = infos[idx]
                    if free > 0 then
                        sizes[idx] = inf.item.grow > 0 and (inf.base + free * (inf.item.grow / weight)) or inf.base
                    else
                        local sw = inf.item.shrink * inf.base
                        sizes[idx] = sw > 0 and (inf.base + free * (sw / weight)) or inf.base
                    end
                end
            end
            break
        end
    end
    for i = 1, n do
        local idx = indices[i]
        if not sizes[idx] then
            sizes[idx] = infos[idx].base
        end
    end
    return sizes
end

local function line_used_main(infos, indices, sizes, gap)
    local used = gap * math_max(0, #indices - 1)
    for i = 1, #indices do
        local idx = indices[i]
        used = used + sizes[idx] + infos[idx].main_margin_start + infos[idx].main_margin_end
    end
    return used
end

local function flex_layout_children(node, outer, measure_opts)
    local frame = resolve_local_frame(node, outer, measure_opts)
    local axis = node.axis
    local rowish = is_row_axis(axis)
    local main_size = rowish and frame.w or frame.h
    local cross_size = rowish and frame.h or frame.w
    local wrap = node.wrap
    local inner_constraint = measure.available_constraint_from_frame(frame)
    local child_infos = flex_collect_infos(node, inner_constraint, measure_opts)

    if #child_infos == 0 then
        return {}, frame
    end

    local lines = {}
    if wrap == WRAP_NO or main_size == INF then
        lines[1] = {}
        for i = 1, #child_infos do
            lines[1][i] = i
        end
    else
        local cur = {}
        local cur_used = 0
        for i = 1, #child_infos do
            local inf = child_infos[i]
            local need = inf.base + inf.main_margin_start + inf.main_margin_end
            if #cur > 0 then
                need = need + node.gap_main
            end
            if #cur > 0 and cur_used + need > main_size then
                lines[#lines + 1] = cur
                cur = {}
                cur_used = 0
                need = inf.base + inf.main_margin_start + inf.main_margin_end
            end
            cur[#cur + 1] = i
            cur_used = cur_used + need
        end
        if #cur > 0 then
            lines[#lines + 1] = cur
        end
    end

    local line_infos = {}
    local natural_cross_total = 0

    for li = 1, #lines do
        local idxs = lines[li]
        local sizes = distribute_line(child_infos, idxs, main_size, node.gap_main)
        local used_main = line_used_main(child_infos, idxs, sizes, node.gap_main)
        local line_cross = 0
        local line_baseline = 0
        local items = {}

        for j = 1, #idxs do
            local idx = idxs[j]
            local inf = child_infos[idx]
            local slot_main = sizes[idx]
            local ccon = rowish
                and measure.constraint(measure.exact(math_max(0, slot_main)), exact_or_atmost(cross_size, false))
                or measure.constraint(exact_or_atmost(cross_size, false), measure.exact(math_max(0, slot_main)))
            local m = measure.measure(inf.item.node, ccon, measure_opts)
            local actual_cross = cross_size_of(m, axis)
            local baseline = baseline_num(m.baseline)
            if baseline and rowish then
                line_baseline = math_max(line_baseline, baseline + inf.cross_margin_start)
            end
            line_cross = math_max(line_cross, actual_cross + inf.cross_margin_start + inf.cross_margin_end)
            items[j] = {
                idx = idx,
                slot_main = slot_main,
                actual_main = math_min(slot_main, main_size_of(m, axis)),
                actual_cross = actual_cross,
                measure = m,
                baseline = baseline,
            }
        end

        line_infos[li] = {
            items = items,
            used_main = used_main,
            natural_cross = line_cross,
            baseline = line_baseline,
        }
        natural_cross_total = natural_cross_total + line_cross
        if li > 1 then
            natural_cross_total = natural_cross_total + node.gap_cross
        end
    end

    local line_cross_sizes = {}
    local line_cross_pos = {}
    local free_cross = (cross_size == INF) and 0 or math_max(0, cross_size - natural_cross_total)
    local line_lead = 0
    local line_gap_extra = 0

    if #line_infos == 1 and cross_size ~= INF then
        line_cross_sizes[1] = cross_size
    elseif node.align_content == CONTENT_STRETCH and cross_size ~= INF and #line_infos > 0 then
        local extra = free_cross / #line_infos
        for li = 1, #line_infos do
            line_cross_sizes[li] = line_infos[li].natural_cross + extra
        end
    else
        for li = 1, #line_infos do
            line_cross_sizes[li] = line_infos[li].natural_cross
        end
        if node.align_content == CONTENT_END then
            line_lead = free_cross
        elseif node.align_content == CONTENT_CENTER then
            line_lead = free_cross / 2
        elseif node.align_content == CONTENT_SPACE_BETWEEN then
            line_gap_extra = (#line_infos > 1) and (free_cross / (#line_infos - 1)) or 0
        elseif node.align_content == CONTENT_SPACE_AROUND then
            line_gap_extra = free_cross / #line_infos
            line_lead = line_gap_extra / 2
        elseif node.align_content == CONTENT_SPACE_EVENLY then
            line_gap_extra = free_cross / (#line_infos + 1)
            line_lead = line_gap_extra
        end
    end

    do
        local p = line_lead
        for li = 1, #line_infos do
            line_cross_pos[li] = p
            p = p + line_cross_sizes[li] + node.gap_cross + line_gap_extra
        end
    end

    local placed = {}
    for li = 1, #line_infos do
        local line = line_infos[li]
        local line_slot_cross = line_cross_sizes[li]
        local free_main = (main_size == INF) and 0 or math_max(0, main_size - line.used_main)
        local line_start = 0
        local gap_extra = 0

        if node.justify == MAIN_END then
            line_start = free_main
        elseif node.justify == MAIN_CENTER then
            line_start = free_main / 2
        elseif node.justify == MAIN_SPACE_BETWEEN then
            gap_extra = (#line.items > 1) and (free_main / (#line.items - 1)) or 0
        elseif node.justify == MAIN_SPACE_AROUND then
            gap_extra = free_main / #line.items
            line_start = gap_extra / 2
        elseif node.justify == MAIN_SPACE_EVENLY then
            gap_extra = free_main / (#line.items + 1)
            line_start = gap_extra
        end

        local pmain = line_start
        for j = 1, #line.items do
            local item = line.items[j]
            local inf = child_infos[item.idx]
            local eff_align = inf.item.self_align
            if eff_align == CROSS_AUTO then
                eff_align = node.align_items
            end
            if (not rowish) and eff_align == CROSS_BASELINE then
                eff_align = CROSS_START
            end

            local cross_inner = math_max(0, line_slot_cross - inf.cross_margin_start - inf.cross_margin_end)
            local actual_cross = item.actual_cross
            if eff_align == CROSS_STRETCH then
                actual_cross = clamp(cross_inner, inf.min_cross, inf.max_cross)
            else
                actual_cross = clamp(actual_cross, inf.min_cross, inf.max_cross)
            end

            local cross_offset
            if eff_align == CROSS_END then
                cross_offset = line_slot_cross - inf.cross_margin_end - actual_cross
            elseif eff_align == CROSS_CENTER then
                cross_offset = inf.cross_margin_start + (cross_inner - actual_cross) / 2
            elseif eff_align == CROSS_BASELINE and rowish and item.baseline then
                cross_offset = line.baseline - item.baseline
            else
                cross_offset = inf.cross_margin_start
            end

            local logical_main = pmain + inf.main_margin_start
            local logical_cross = line_cross_pos[li] + cross_offset

            local x, y, w, h
            if rowish then
                w, h = item.actual_main, actual_cross
                x = is_reverse_axis(axis) and (frame.x + frame.w - logical_main - w) or (frame.x + logical_main)
                y = is_wrap_reverse(wrap) and (frame.y + frame.h - logical_cross - h) or (frame.y + logical_cross)
            else
                w, h = actual_cross, item.actual_main
                x = is_wrap_reverse(wrap) and (frame.x + frame.w - logical_cross - w) or (frame.x + logical_cross)
                y = is_reverse_axis(axis) and (frame.y + frame.h - logical_main - h) or (frame.y + logical_main)
            end

            placed[#placed + 1] = {
                node = inf.item.node,
                frame = mkframe(x, y, w, h),
            }

            pmain = pmain + inf.main_margin_start + item.slot_main + inf.main_margin_end + node.gap_main + gap_extra
        end
    end

    return placed, frame
end

local draw_paint_node
local draw_ui_node

local function draw_text_node(node, frame, active_id, ctx)
    local x = frame.x + ctx.tx
    local y = frame.y + ctx.ty
    local clipped = node.style.overflow ~= OVERFLOW_VISIBLE
    if clipped then
        push_clip(ctx, x, y, frame.w, frame.h)
    end
    draw_text_payload(node.text, x, y, frame.w, frame.h, node.style, resolve_draw_id(active_id, node.tag), ctx)
    if clipped then
        pop_clip(ctx)
    end
end

draw_paint_node = function(node, active_id, ctx)
    if not node then
        return
    end

    local runtime = ctx.opts.runtime or ctx.opts.env
    local kind = node.kind

    if kind == "Group" then
        for i = 1, #node.children do
            draw_paint_node(node.children[i], active_id, ctx)
        end
    elseif kind == "ClipRegion" then
        local x = resolve_paint_scalar(runtime, node.x) + ctx.tx
        local y = resolve_paint_scalar(runtime, node.y) + ctx.ty
        local w = resolve_paint_scalar(runtime, node.w)
        local h = resolve_paint_scalar(runtime, node.h)
        push_clip(ctx, x, y, w, h)
        draw_paint_node(node.child, active_id, ctx)
        pop_clip(ctx)
    elseif kind == "Translate" then
        local dx = resolve_paint_scalar(runtime, node.tx)
        local dy = resolve_paint_scalar(runtime, node.ty)
        push_offset(ctx, dx, dy)
        draw_paint_node(node.child, active_id, ctx)
        pop_offset(ctx)
    elseif kind == "FillRect" then
        local x = resolve_paint_scalar(runtime, node.x) + ctx.tx
        local y = resolve_paint_scalar(runtime, node.y) + ctx.ty
        local w = resolve_paint_scalar(runtime, node.w)
        local h = resolve_paint_scalar(runtime, node.h)
        if visible_in_clip(ctx, x, y, w, h) then
            local color, opacity = resolve_paint_color(runtime, node.color, active_id, node.tag, ctx.opts)
            backend_set_color(ctx.backend, color, opacity)
            fill_rect(ctx.backend, x, y, w, h)
        end
    elseif kind == "StrokeRect" then
        local x = resolve_paint_scalar(runtime, node.x) + ctx.tx
        local y = resolve_paint_scalar(runtime, node.y) + ctx.ty
        local w = resolve_paint_scalar(runtime, node.w)
        local h = resolve_paint_scalar(runtime, node.h)
        local thickness = resolve_paint_scalar(runtime, node.thickness)
        if visible_in_clip(ctx, x, y, w, h) then
            local color, opacity = resolve_paint_color(runtime, node.color, active_id, node.tag, ctx.opts)
            backend_set_color(ctx.backend, color, opacity)
            stroke_rect(ctx.backend, x, y, w, h, thickness)
        end
    elseif kind == "Line" then
        local x1 = resolve_paint_scalar(runtime, node.x1) + ctx.tx
        local y1 = resolve_paint_scalar(runtime, node.y1) + ctx.ty
        local x2 = resolve_paint_scalar(runtime, node.x2) + ctx.tx
        local y2 = resolve_paint_scalar(runtime, node.y2) + ctx.ty
        local thickness = resolve_paint_scalar(runtime, node.thickness)
        if ctx.backend and ctx.backend.draw_line then
            local color, opacity = resolve_paint_color(runtime, node.color, active_id, node.tag, ctx.opts)
            backend_set_color(ctx.backend, color, opacity)
            ctx.backend:draw_line(x1, y1, x2, y2, thickness)
        end
    elseif kind == "Text" then
        local x = resolve_paint_scalar(runtime, node.x) + ctx.tx
        local y = resolve_paint_scalar(runtime, node.y) + ctx.ty
        local w = resolve_paint_scalar(runtime, node.w)
        local h = resolve_paint_scalar(runtime, node.h)
        local color, opacity = resolve_paint_color(runtime, node.color, active_id, node.tag, ctx.opts)
        draw_text_payload(resolve_paint_text(runtime, node.text), x, y, w, h, {
            font_id = node.font_id,
            color = T.DS.ColorPack(color, color, color, color),
            opacity = T.DS.NumPack(opacity, opacity, opacity, opacity),
            line_height = node.line_height,
            align = node.align,
            wrap = node.wrap,
            overflow = node.overflow,
            line_limit = node.line_limit,
        }, resolve_draw_id(active_id, node.tag), ctx)
    else
        error("ui.draw: unsupported Paint node kind " .. tostring(kind), 2)
    end
end

draw_ui_node = function(node, outer, active_id, ctx)
    if not node then
        return
    end

    local measure_opts = ctx.measure_opts
    local kind = node.kind

    if kind == "Empty" then
        return
    elseif kind == "Key" then
        return draw_ui_node(node.child, outer, active_id, ctx)
    elseif kind == "HitBox" or kind == "Pressable" or kind == "Focusable" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        local next_id = resolve_draw_id(node.id, active_id)
        return draw_ui_node(node.child, frame, next_id, ctx)
    elseif kind == "Flex" then
        local placed = flex_layout_children(node, outer, measure_opts)
        for i = 1, #placed do
            draw_ui_node(placed[i].node, placed[i].frame, active_id, ctx)
        end
        return
    elseif kind == "Pad" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        local iw = math_max(0, frame.w - node.insets.l - node.insets.r)
        local ih = math_max(0, frame.h - node.insets.t - node.insets.b)
        return draw_ui_node(node.child, mkframe(frame.x + node.insets.l, frame.y + node.insets.t, iw, ih), active_id, ctx)
    elseif kind == "Stack" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        for i = 1, #node.children do
            draw_ui_node(node.children[i], frame, active_id, ctx)
        end
        return
    elseif kind == "Clip" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        push_clip(ctx, frame.x + ctx.tx, frame.y + ctx.ty, frame.w, frame.h)
        draw_ui_node(node.child, frame, active_id, ctx)
        pop_clip(ctx)
        return
    elseif kind == "Transform" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        push_offset(ctx, node.tx, node.ty)
        draw_ui_node(node.child, mkframe(frame.x, frame.y, frame.w, frame.h), active_id, ctx)
        pop_offset(ctx)
        return
    elseif kind == "Sized" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        return draw_ui_node(node.child, frame, active_id, ctx)
    elseif kind == "ScrollArea" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        draw_box_chrome(frame, node.style, resolve_draw_id(node.id, active_id), node.id, ctx)
        local inset_h, inset_v = style_insets(node.style)
        local viewport_w = math_max(0, frame.w - inset_h * 2)
        local viewport_h = math_max(0, frame.h - inset_v * 2)
        local viewport_x = frame.x + inset_h
        local viewport_y = frame.y + inset_v
        push_clip(ctx, viewport_x + ctx.tx, viewport_y + ctx.ty, viewport_w, viewport_h)
        draw_ui_node(node.child, mkframe(viewport_x - node.scroll_x, viewport_y - node.scroll_y, viewport_w, viewport_h), resolve_draw_id(node.id, active_id), ctx)
        pop_clip(ctx)
        return
    elseif kind == "Panel" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        draw_box_chrome(frame, node.style, active_id, node.tag, ctx)
        local inset_h, inset_v = style_insets(node.style)
        return draw_ui_node(
            node.child,
            mkframe(
                frame.x + inset_h,
                frame.y + inset_v,
                math_max(0, frame.w - inset_h * 2),
                math_max(0, frame.h - inset_v * 2)),
            active_id,
            ctx)
    elseif kind == "Rect" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        draw_box_chrome(frame, node.style, active_id, node.tag, ctx)
        return
    elseif kind == "Text" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        draw_text_node(node, frame, resolve_draw_id(active_id, node.tag), ctx)
        return
    elseif kind == "CustomPaint" then
        local frame = resolve_local_frame(node, outer, measure_opts)
        push_offset(ctx, frame.x, frame.y)
        draw_paint_node(node.paint, resolve_draw_id(active_id, node.tag), ctx)
        pop_offset(ctx)
        return
    elseif kind == "Overlay" then
        draw_ui_node(node.base, outer, active_id, ctx)
        local frame = resolve_local_frame(node.base, outer, measure_opts)
        push_offset(ctx, frame.x, frame.y)
        draw_paint_node(node.overlay, active_id, ctx)
        pop_offset(ctx)
        return
    elseif kind == "Spacer" then
        return
    end

    error("ui.draw: unsupported UI node kind " .. tostring(kind), 2)
end

function draw.draw(node, frame, opts)
    local ctx = build_ctx(frame, opts)
    draw_ui_node(node, frame, nil, ctx)
end

function draw.paint(node, frame, opts)
    local ctx = build_ctx(frame, opts)
    push_offset(ctx, frame.x, frame.y)
    draw_paint_node(node, nil, ctx)
    pop_offset(ctx)
end

function draw.recording_backend(out)
    out = out or {}
    return {
        set_color_rgba8 = function(_, rgba8, opacity)
            out[#out + 1] = { op = "color", rgba8 = rgba8, opacity = opacity or 1 }
        end,
        set_font_id = function(_, font_id)
            out[#out + 1] = { op = "font", font_id = font_id }
        end,
        fill_rect = function(_, x, y, w, h, radius)
            out[#out + 1] = { op = "fill_rect", x = x, y = y, w = w, h = h, radius = radius or 0 }
        end,
        stroke_rect = function(_, x, y, w, h, thickness, radius)
            out[#out + 1] = { op = "stroke_rect", x = x, y = y, w = w, h = h, thickness = thickness, radius = radius or 0 }
        end,
        draw_line = function(_, x1, y1, x2, y2, thickness)
            out[#out + 1] = { op = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2, thickness = thickness }
        end,
        draw_text = function(_, text, x, y, width, align)
            out[#out + 1] = { op = "text", text = text, x = x, y = y, width = width, align = align }
        end,
        draw_text_box = function(_, text, x, y, w, h, style)
            out[#out + 1] = {
                op = "text_box",
                text = text,
                x = x,
                y = y,
                w = w,
                h = h,
                font_id = style.font_id,
                align = style.align,
                wrap = style.wrap,
                overflow = style.overflow,
                line_height = style.line_height,
                line_limit = style.line_limit,
            }
        end,
        push_clip = function(_, x, y, w, h)
            out[#out + 1] = { op = "push_clip", x = x, y = y, w = w, h = h }
        end,
        pop_clip = function(_)
            out[#out + 1] = { op = "pop_clip" }
        end,
    }, out
end

function draw.record(node, frame, opts)
    opts = opts or {}
    local backend, out = draw.recording_backend(opts.out)
    opts.backend = backend
    draw.draw(node, frame, opts)
    return out
end

function draw.record_paint(node, frame, opts)
    opts = opts or {}
    local backend, out = draw.recording_backend(opts.out)
    opts.backend = backend
    draw.paint(node, frame, opts)
    return out
end

-- Direct ASDL methods.
function T.UI.Node:draw(frame, opts)
    return draw.draw(self, frame, opts)
end

function T.UI.Node:record(frame, opts)
    return draw.record(self, frame, opts)
end

function T.Paint.Node:draw(frame, opts)
    return draw.paint(self, frame, opts)
end

function T.Paint.Node:record(frame, opts)
    return draw.record_paint(self, frame, opts)
end

return draw
