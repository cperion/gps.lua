-- uilib_iter.lua
--
-- Immediate/session-based implementation behind canonical `uilib`.
--
-- This file keeps the full authoring vocabulary and DS model, but makes
-- measure/draw/hit work directly over the param tree each frame instead of
-- centering execution around compiled View.Cmd arrays.
--
-- `require("uilib")` is the preferred public entrypoint.
-- `require("uilib_iter")` remains available as a compatibility alias.

local iter = require("iter")
local base = require("uilib_impl")

local ui = {}
for k, v in pairs(base) do ui[k] = v end

local T = ui.T
local S = assert(base._internal, "uilib_iter: uilib_impl internal helpers missing")

local ZERO_INSETS = S.ZERO_INSETS
local AUTO_BOX = S.AUTO_BOX
local INF = S.INF
local BASELINE_NONE = S.BASELINE_NONE

local KEYS = setmetatable({}, { __mode = "k" })
local CUSTOM = setmetatable({}, { __mode = "k" })
local SRC_MT = {}

local function source(kind, t)
    t.kind = kind
    return setmetatable(t, SRC_MT)
end

local function is_source(x) return getmetatable(x) == SRC_MT end
local function is_iter_pipeline(x) return getmetatable(x) == iter.P end

local MT = {
    Flex = getmetatable(base.row(0, {})),
    Pad = getmetatable(base.pad(base.insets(0, 0, 0, 0), base.spacer())),
    Stack = getmetatable(base.stack({})),
    Clip = getmetatable(base.clip(base.spacer())),
    Transform = getmetatable(base.transform(0, 0, base.spacer())),
    Sized = getmetatable(base.sized(base.box(), base.spacer())),
    Rect = getmetatable(base.rect("", base.solid(0), base.box())),
    Text = getmetatable(base.text("", "", base.text_style {}, base.box())),
    Spacer = getmetatable(base.spacer()),
    FlexItem = getmetatable(base.item(base.spacer())),
    SpanExact = getmetatable(base.exact(0)),
    SpanAtMost = getmetatable(base.at_most(0)),
    BasisPx = getmetatable(base.basis_px(0)),
    BasisPercent = getmetatable(base.basis_percent(0)),
}

local PMT = {
    Group = getmetatable(base.paint_group({})),
    ClipRegion = getmetatable(base.paint_clip(0, 0, 0, 0, base.paint_group({}))),
    Translate = getmetatable(base.paint_transform(0, 0, base.paint_group({}))),
    FillRect = getmetatable(base.paint_rect("", 0, 0, 0, 0, 0)),
    StrokeRect = getmetatable(base.paint_stroke("", 0, 0, 0, 0, 1, 0)),
    Line = getmetatable(base.paint_line("", 0, 0, 0, 0, 1, 0)),
    Text = getmetatable(base.paint_text("", 0, 0, 0, 0, base.text_style {}, "")),
    ScalarLit = getmetatable(T.Paint.ScalarLit(0)),
    ScalarFromRef = getmetatable(T.Paint.ScalarFromRef(T.Runtime.NumRef(""))),
    TextLit = getmetatable(T.Paint.TextLit("")),
    TextFromRef = getmetatable(T.Paint.TextFromRef(T.Runtime.TextRef(""))),
    ColorPackLit = getmetatable(T.Paint.ColorPackLit(base.solid(0))),
    ColorFromRef = getmetatable(T.Paint.ColorFromRef(T.Runtime.ColorRef(""))),
    ColorPack = getmetatable(T.DS.ColorPack(0, 0, 0, 0)),
}

local function copy_state(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[k] = copy_state(vv) end
    return out
end

function ui.state(seed)
    return seed and copy_state(seed) or {
        hot = nil,
        active = nil,
        pressed = nil,
        dragging = nil,
        focused = nil,
        widgets = {},
        nav = {},
    }
end

function ui.clone_state(state)
    return copy_state(state)
end

function ui.key(id, node)
    KEYS[node] = id
    return node
end

function ui.when(cond, node)
    return source("when", { cond = cond, node = node })
end

function ui.unless(cond, node)
    return source("when", { cond = not cond, node = node })
end

function ui.concat(items)
    return source("concat", { items = items })
end

function ui.each(items, mapfn)
    return source("each", { items = items, map = mapfn })
end

local function append_node_like(out, x, for_stack)
    if x == nil or x == false then return end
    local mt = getmetatable(x)
    if is_source(x) then
        if x.kind == "when" then
            if x.cond then append_node_like(out, x.node, for_stack) end
        elseif x.kind == "concat" then
            local xs = x.items or {}
            for i = 1, #xs do append_node_like(out, xs[i], for_stack) end
        elseif x.kind == "each" then
            local items = x.items
            if is_iter_pipeline(items) then
                items = items:collect()
            end
            if items ~= nil then
                for i = 1, #items do append_node_like(out, x.map(items[i]), for_stack) end
            end
        end
    elseif is_iter_pipeline(x) then
        local xs = x:collect()
        for i = 1, #xs do append_node_like(out, xs[i], for_stack) end
    elseif mt == MT.FlexItem then
        if for_stack then out[#out + 1] = x.node else out[#out + 1] = x end
    elseif type(x) == "table" and mt == nil and (x[1] ~= nil or next(x) == nil) then
        for i = 1, #x do append_node_like(out, x[i], for_stack) end
    else
        out[#out + 1] = x
    end
end

local function normalize_nodes(children)
    local out = {}
    append_node_like(out, children, true)
    return out
end

local function normalize_flex_children(children)
    local out = {}
    append_node_like(out, children, false)
    return out
end

function ui.stack(children, box)
    return base.stack(normalize_nodes(children or {}), box or AUTO_BOX)
end

function ui.row(gap, children, opts)
    return base.row(gap, normalize_flex_children(children or {}), opts)
end

function ui.col(gap, children, opts)
    return base.col(gap, normalize_flex_children(children or {}), opts)
end

function ui.flex(opts)
    opts = opts or {}
    return base.flex {
        axis = opts.axis,
        wrap = opts.wrap,
        gap_main = opts.gap_main,
        gap_cross = opts.gap_cross,
        justify = opts.justify,
        align_items = opts.align_items,
        align_content = opts.align_content,
        box = opts.box,
        children = normalize_flex_children(opts.children or {}),
    }
end

function ui.custom(paint_node, box)
    local node = base.spacer(box or AUTO_BOX)
    CUSTOM[node] = paint_node
    return node
end

local function parse_frame(a, b, c, d)
    if type(a) == "number" and type(b) == "number" and c == nil then
        return base.frame(0, 0, a, b)
    elseif type(a) == "number" and type(b) == "number" and type(c) == "number" and type(d) == "number" then
        return base.frame(a, b, c, d)
    end
    return a
end

local function exact_constraint_from_frame(frame)
    return base.constraint(base.exact(frame.w), base.exact(frame.h))
end

local function available_constraint_from_frame(frame)
    return base.constraint(base.at_most(frame.w), base.at_most(frame.h))
end

local function span_key(span)
    if span == S.SPAN_UNBOUNDED then return "U" end
    local mt = getmetatable(span)
    if mt == MT.SpanExact then return "E" .. span.px end
    if mt == MT.SpanAtMost then return "A" .. span.px end
    return tostring(span)
end

local function constraint_key(constraint)
    return span_key(constraint.w) .. ":" .. span_key(constraint.h)
end

local function measure_cached(cache, node, constraint)
    if not cache then return base.measure(node, constraint) end
    local by_node = cache[node]
    if not by_node then by_node = {}; cache[node] = by_node end
    local key = constraint_key(constraint)
    local hit = by_node[key]
    if hit then return hit end
    local m = base.measure(node, constraint)
    by_node[key] = m
    return m
end

local function resolve_local_frame(node, outer, cache)
    local m = measure_cached(cache, node, exact_constraint_from_frame(outer))
    return base.frame(outer.x, outer.y, m.used_w, m.used_h), m
end

local function is_row_axis(axis) return axis == ui.AXIS_ROW or axis == ui.AXIS_ROW_REVERSE end
local function is_reverse_axis(axis) return axis == ui.AXIS_ROW_REVERSE or axis == ui.AXIS_COL_REVERSE end
local function is_wrap_reverse(wrap) return wrap == ui.WRAP_REVERSE end
local function clamp(v, lo, hi) if lo and v < lo then v = lo end; if hi and v > hi then v = hi end; return v end
local function main_margins(margin, axis)
    if axis == ui.AXIS_ROW then return margin.l, margin.r end
    if axis == ui.AXIS_ROW_REVERSE then return margin.r, margin.l end
    if axis == ui.AXIS_COL then return margin.t, margin.b end
    return margin.b, margin.t
end
local function cross_margins(margin, axis)
    if axis == ui.AXIS_ROW or axis == ui.AXIS_ROW_REVERSE then return margin.t, margin.b end
    return margin.l, margin.r
end
local function main_size_of(m, axis) return is_row_axis(axis) and m.used_w or m.used_h end
local function cross_size_of(m, axis) return is_row_axis(axis) and m.used_h or m.used_w end
local function intrinsic_min_main(intr, axis) return is_row_axis(axis) and intr.min_w or intr.min_h end
local function intrinsic_max_main(intr, axis) return is_row_axis(axis) and intr.max_w or intr.max_h end
local function intrinsic_min_cross(intr, axis) return is_row_axis(axis) and intr.min_h or intr.min_w end
local function intrinsic_max_cross(intr, axis) return is_row_axis(axis) and intr.max_h or intr.max_w end
local function baseline_num(b) if b == BASELINE_NONE or b == nil then return nil end; return b.px end

local function span_available(span)
    if span == S.SPAN_UNBOUNDED then return INF, false end
    local mt = getmetatable(span)
    if mt == MT.SpanExact then return span.px, true end
    if mt == MT.SpanAtMost then return span.px, false end
    return INF, false
end

local function exact_or_atmost(px, exact)
    if px == INF then return S.SPAN_UNBOUNDED end
    if exact then return base.exact(px) end
    return base.at_most(px)
end

local function resolve_basis_value(spec, available, content_value)
    if spec == T.UI.BasisAuto or spec == T.UI.BasisContent then return content_value end
    local mt = getmetatable(spec)
    if mt == MT.BasisPx then return spec.px end
    if mt == MT.BasisPercent then
        if available ~= INF then return available * spec.ratio end
        return content_value
    end
    return content_value
end

local function flex_collect_infos(node, constraint, cache)
    local axis = node.axis
    local avail_main = is_row_axis(axis) and span_available(constraint.w) or span_available(constraint.h)
    local infos = {}
    for i = 1, #node.children do
        local item = node.children[i]
        local m = measure_cached(cache, item.node, constraint)
        local ml, mr = main_margins(item.margin, axis)
        local mt_, mb = cross_margins(item.margin, axis)
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
            cross_margin_start = mt_,
            cross_margin_end = mb,
        }
    end
    return infos, avail_main
end

local function distribute_line(infos, indices, avail_main, gap)
    local n, sizes, frozen = #indices, {}, {}
    for i = 1, n do sizes[indices[i]] = infos[indices[i]].base end
    if avail_main == INF then return sizes end
    while true do
        local used, free, weight = gap * math.max(0, n - 1), 0, 0
        for i = 1, n do
            local idx = indices[i]
            local inf = infos[idx]
            used = used + inf.main_margin_start + inf.main_margin_end
            if frozen[idx] then used = used + sizes[idx] else used = used + inf.base end
        end
        free = avail_main - used
        if math.abs(free) < 1e-6 then break end
        if free > 0 then
            for i = 1, n do
                local idx = indices[i]
                if not frozen[idx] and infos[idx].item.grow > 0 then weight = weight + infos[idx].item.grow end
            end
        else
            for i = 1, n do
                local idx = indices[i]
                if not frozen[idx] and infos[idx].item.shrink > 0 then weight = weight + infos[idx].item.shrink * infos[idx].base end
            end
        end
        if weight <= 0 then break end
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
                if cl ~= target then sizes[idx] = cl; frozen[idx] = true; clamped = true end
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
    for i = 1, n do local idx = indices[i]; if not sizes[idx] then sizes[idx] = infos[idx].base end end
    return sizes
end

local function line_used_main(infos, indices, sizes, gap)
    local used = gap * math.max(0, #indices - 1)
    for i = 1, #indices do
        local idx = indices[i]
        used = used + sizes[idx] + infos[idx].main_margin_start + infos[idx].main_margin_end
    end
    return used
end

local function flex_layout_children(node, outer, cache)
    local frame = resolve_local_frame(node, outer, cache)
    local axis, rowish = node.axis, is_row_axis(node.axis)
    local main_size = rowish and frame.w or frame.h
    local cross_size = rowish and frame.h or frame.w
    local wrap = node.wrap
    local inner_constraint = available_constraint_from_frame(frame)
    local child_infos = flex_collect_infos(node, inner_constraint, cache)
    if #child_infos == 0 then return {}, frame end

    local lines = {}
    if wrap == ui.WRAP_NO or main_size == INF then
        lines[1] = {}
        for i = 1, #child_infos do lines[1][i] = i end
    else
        local cur, cur_used = {}, 0
        for i = 1, #child_infos do
            local inf = child_infos[i]
            local need = inf.base + inf.main_margin_start + inf.main_margin_end
            if #cur > 0 then need = need + node.gap_main end
            if #cur > 0 and cur_used + need > main_size then
                lines[#lines + 1] = cur
                cur, cur_used = {}, 0
                need = inf.base + inf.main_margin_start + inf.main_margin_end
            end
            cur[#cur + 1] = i
            cur_used = cur_used + need
        end
        if #cur > 0 then lines[#lines + 1] = cur end
    end

    local line_infos, natural_cross_total = {}, 0
    for li = 1, #lines do
        local idxs = lines[li]
        local sizes = distribute_line(child_infos, idxs, main_size, node.gap_main)
        local used_main = line_used_main(child_infos, idxs, sizes, node.gap_main)
        local line_cross, line_baseline, items = 0, 0, {}
        for j = 1, #idxs do
            local idx = idxs[j]
            local inf = child_infos[idx]
            local slot_main = sizes[idx]
            local ccon = rowish
                and base.constraint(base.exact(math.max(0, slot_main)), exact_or_atmost(cross_size, false))
                or base.constraint(exact_or_atmost(cross_size, false), base.exact(math.max(0, slot_main)))
            local m = measure_cached(cache, inf.item.node, ccon)
            local actual_cross = cross_size_of(m, axis)
            local b = baseline_num(m.baseline)
            if b and rowish then line_baseline = math.max(line_baseline, b + inf.cross_margin_start) end
            line_cross = math.max(line_cross, actual_cross + inf.cross_margin_start + inf.cross_margin_end)
            items[j] = {
                idx = idx,
                slot_main = slot_main,
                actual_main = math.min(slot_main, main_size_of(m, axis)),
                actual_cross = actual_cross,
                measure = m,
                baseline = b,
            }
        end
        line_infos[li] = { items = items, used_main = used_main, natural_cross = line_cross, baseline = line_baseline }
        natural_cross_total = natural_cross_total + line_cross
        if li > 1 then natural_cross_total = natural_cross_total + node.gap_cross end
    end

    local line_cross_sizes, line_cross_pos = {}, {}
    local free_cross = (cross_size == INF) and 0 or math.max(0, cross_size - natural_cross_total)
    local line_lead, line_gap_extra = 0, 0
    if #line_infos == 1 and cross_size ~= INF then
        line_cross_sizes[1] = cross_size
    elseif node.align_content == ui.CONTENT_STRETCH and cross_size ~= INF and #line_infos > 0 then
        local extra = free_cross / #line_infos
        for li = 1, #line_infos do line_cross_sizes[li] = line_infos[li].natural_cross + extra end
    else
        for li = 1, #line_infos do line_cross_sizes[li] = line_infos[li].natural_cross end
        if node.align_content == ui.CONTENT_END then line_lead = free_cross
        elseif node.align_content == ui.CONTENT_CENTER then line_lead = free_cross / 2
        elseif node.align_content == ui.CONTENT_SPACE_BETWEEN then line_gap_extra = (#line_infos > 1) and (free_cross / (#line_infos - 1)) or 0
        elseif node.align_content == ui.CONTENT_SPACE_AROUND then line_gap_extra = free_cross / #line_infos; line_lead = line_gap_extra / 2
        elseif node.align_content == ui.CONTENT_SPACE_EVENLY then line_gap_extra = free_cross / (#line_infos + 1); line_lead = line_gap_extra end
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
        local free_main = (main_size == INF) and 0 or math.max(0, main_size - line.used_main)
        local line_start, gap_extra = 0, 0
        if node.justify == ui.MAIN_END then line_start = free_main
        elseif node.justify == ui.MAIN_CENTER then line_start = free_main / 2
        elseif node.justify == ui.MAIN_SPACE_BETWEEN then gap_extra = (#line.items > 1) and (free_main / (#line.items - 1)) or 0
        elseif node.justify == ui.MAIN_SPACE_AROUND then gap_extra = free_main / #line.items; line_start = gap_extra / 2
        elseif node.justify == ui.MAIN_SPACE_EVENLY then gap_extra = free_main / (#line.items + 1); line_start = gap_extra end
        local pmain = line_start
        for j = 1, #line.items do
            local item = line.items[j]
            local inf = child_infos[item.idx]
            local eff_align = inf.item.self_align
            if eff_align == ui.CROSS_AUTO then eff_align = node.align_items end
            if (not rowish) and eff_align == ui.CROSS_BASELINE then eff_align = ui.CROSS_START end
            local cross_inner = math.max(0, line_slot_cross - inf.cross_margin_start - inf.cross_margin_end)
            local actual_cross = item.actual_cross
            if eff_align == ui.CROSS_STRETCH then actual_cross = clamp(cross_inner, inf.min_cross, inf.max_cross)
            else actual_cross = clamp(actual_cross, inf.min_cross, inf.max_cross) end
            local cross_offset
            if eff_align == ui.CROSS_END then cross_offset = line_slot_cross - inf.cross_margin_end - actual_cross
            elseif eff_align == ui.CROSS_CENTER then cross_offset = inf.cross_margin_start + (cross_inner - actual_cross) / 2
            elseif eff_align == ui.CROSS_BASELINE and rowish and item.baseline then cross_offset = line.baseline - item.baseline
            else cross_offset = inf.cross_margin_start end
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
            placed[#placed + 1] = { node = inf.item.node, frame = base.frame(x, y, w, h) }
            pmain = pmain + inf.main_margin_start + item.slot_main + inf.main_margin_end + node.gap_main + gap_extra
        end
    end
    return placed, frame
end

local function rgba8_to_float(rgba8)
    local a = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local b = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local g = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local r = (rgba8 % 256) / 255
    return r, g, b, a
end

local function backend_text_align(align)
    if align == ui.TEXT_CENTER then return "center" end
    if align == ui.TEXT_END then return "right" end
    if align == ui.TEXT_JUSTIFY then return "justify" end
    return "left"
end

local function intersect_clip(x, y, w, h, top)
    if not top then return x, y, w, h end
    local x2 = math.max(x, top[1])
    local y2 = math.max(y, top[2])
    local nw = math.max(0, math.min(x + w, top[1] + top[3]) - x2)
    local nh = math.max(0, math.min(y + h, top[2] + top[4]) - y2)
    return x2, y2, nw, nh
end

local function backend_set_color(backend, rgba8)
    if backend and backend.set_color then backend:set_color(rgba8_to_float(rgba8)) end
end

local function backend_draw_text(backend, text, x, y, width, align)
    if backend and backend.draw_text then backend:draw_text(text, x, y, width, align) end
end

local function restore_font_line_height(font, old_lh)
    if font and old_lh and font.setLineHeight then font:setLineHeight(old_lh) end
end

local function prepare_font_for_draw(font, font_id, line_height)
    if not font or not font.getLineHeight or not font.setLineHeight then return nil end
    local old_lh = font:getLineHeight()
    local lh = S.resolve_line_height(line_height, font_id)
    local fh = S.raw_text_height(font_id)
    if fh > 0 then font:setLineHeight(lh / fh) end
    return old_lh
end

local function draw_context(opts)
    return {
        backend = opts.backend or base.get_backend(),
        hot = opts.hot or {},
        runtime = opts.runtime or opts.env or {},
        tx = 0,
        ty = 0,
        tx_stack = {},
        clip_stack = {},
        measure_cache = opts.measure_cache or {},
    }
end

local function push_transform(ctx, dx, dy)
    ctx.tx_stack[#ctx.tx_stack + 1] = { ctx.tx, ctx.ty }
    ctx.tx, ctx.ty = ctx.tx + dx, ctx.ty + dy
    if ctx.backend and ctx.backend.push_transform then ctx.backend:push_transform(dx, dy) end
end

local function pop_transform(ctx)
    if ctx.backend and ctx.backend.pop_transform then ctx.backend:pop_transform() end
    local t = ctx.tx_stack[#ctx.tx_stack]
    ctx.tx_stack[#ctx.tx_stack] = nil
    ctx.tx, ctx.ty = t[1], t[2]
end

local function push_clip(ctx, x, y, w, h)
    local ax, ay, nw, nh = intersect_clip(x, y, w, h, ctx.clip_stack[#ctx.clip_stack])
    ctx.clip_stack[#ctx.clip_stack + 1] = { ax, ay, nw, nh }
    if ctx.backend and ctx.backend.push_clip then ctx.backend:push_clip(ax, ay, nw, nh) end
end

local function pop_clip(ctx)
    ctx.clip_stack[#ctx.clip_stack] = nil
    if ctx.backend and ctx.backend.pop_clip then ctx.backend:pop_clip() end
end

local function runtime_lookup(map, name, fallback)
    if map then
        local v = map[name]
        if v ~= nil then return v end
    end
    return fallback
end

local function resolve_paint_scalar(runtime, scalar)
    local mt = getmetatable(scalar)
    if mt == PMT.ScalarLit then return scalar.n end
    return runtime_lookup(runtime and runtime.numbers, scalar.ref.name, 0)
end

local function resolve_paint_text(runtime, text_value)
    local mt = getmetatable(text_value)
    if mt == PMT.TextLit then return text_value.text end
    return runtime_lookup(runtime and runtime.texts, text_value.ref.name, "")
end

local function resolve_paint_color(runtime, color_value, tag, hot)
    local phase = S.pointer_for_id(tag or "", hot or {})
    local mt = getmetatable(color_value)
    if mt == PMT.ColorPackLit then return S.pick(color_value.pack, phase) end
    local v = runtime_lookup(runtime and runtime.colors, color_value.ref.name, 0)
    if getmetatable(v) == PMT.ColorPack then return S.pick(v, phase) end
    if type(v) == "number" then return v end
    return 0
end

local draw_paint_node
local draw_node

local function draw_text_node(node, outer, ctx)
    local frame = resolve_local_frame(node, outer, ctx.measure_cache)
    local style = node.style
    local font = S.get_font(style.font_id)
    if font and ctx.backend and ctx.backend.set_font then ctx.backend:set_font(font) end
    backend_set_color(ctx.backend, S.pick(style.color, S.pointer_for_id(node.tag or "", ctx.hot)))
    local max_w = (style.wrap == ui.TEXT_NOWRAP and style.overflow == ui.OVERFLOW_VISIBLE) and INF or frame.w
    local max_h = (style.overflow == ui.OVERFLOW_VISIBLE) and INF or frame.h
    local shaped = S.shape_text(style, node.text, max_w, max_h)
    local old_lh = prepare_font_for_draw(font, style.font_id, style.line_height)
    if style.overflow ~= ui.OVERFLOW_VISIBLE then
        push_clip(ctx, frame.x + ctx.tx, frame.y + ctx.ty, frame.w, frame.h)
    end
    if style.wrap == ui.TEXT_NOWRAP and style.overflow == ui.OVERFLOW_VISIBLE then
        backend_draw_text(ctx.backend, shaped.text, frame.x, frame.y, nil, "left")
    else
        backend_draw_text(ctx.backend, shaped.text, frame.x, frame.y, math.max(1, frame.w), backend_text_align(style.align))
    end
    if style.overflow ~= ui.OVERFLOW_VISIBLE then pop_clip(ctx) end
    restore_font_line_height(font, old_lh)
end

draw_paint_node = function(node, runtime, ctx)
    if not node then return end
    local mt = getmetatable(node)
    if mt == PMT.Group then
        for i = 1, #node.children do draw_paint_node(node.children[i], runtime, ctx) end
    elseif mt == PMT.ClipRegion then
        local x = resolve_paint_scalar(runtime, node.x)
        local y = resolve_paint_scalar(runtime, node.y)
        local w = resolve_paint_scalar(runtime, node.w)
        local h = resolve_paint_scalar(runtime, node.h)
        push_clip(ctx, x + ctx.tx, y + ctx.ty, w, h)
        draw_paint_node(node.child, runtime, ctx)
        pop_clip(ctx)
    elseif mt == PMT.Translate then
        local dx = resolve_paint_scalar(runtime, node.tx)
        local dy = resolve_paint_scalar(runtime, node.ty)
        push_transform(ctx, dx, dy)
        draw_paint_node(node.child, runtime, ctx)
        pop_transform(ctx)
    elseif mt == PMT.FillRect then
        local x = resolve_paint_scalar(runtime, node.x)
        local y = resolve_paint_scalar(runtime, node.y)
        local w = resolve_paint_scalar(runtime, node.w)
        local h = resolve_paint_scalar(runtime, node.h)
        backend_set_color(ctx.backend, resolve_paint_color(runtime, node.color, node.tag, ctx.hot))
        if ctx.backend and ctx.backend.fill_rect then ctx.backend:fill_rect(x, y, w, h) end
    elseif mt == PMT.StrokeRect then
        local x = resolve_paint_scalar(runtime, node.x)
        local y = resolve_paint_scalar(runtime, node.y)
        local w = resolve_paint_scalar(runtime, node.w)
        local h = resolve_paint_scalar(runtime, node.h)
        local thickness = resolve_paint_scalar(runtime, node.thickness)
        backend_set_color(ctx.backend, resolve_paint_color(runtime, node.color, node.tag, ctx.hot))
        if ctx.backend and ctx.backend.stroke_rect then ctx.backend:stroke_rect(x, y, w, h, thickness) end
    elseif mt == PMT.Line then
        local x1 = resolve_paint_scalar(runtime, node.x1)
        local y1 = resolve_paint_scalar(runtime, node.y1)
        local x2 = resolve_paint_scalar(runtime, node.x2)
        local y2 = resolve_paint_scalar(runtime, node.y2)
        local thickness = resolve_paint_scalar(runtime, node.thickness)
        backend_set_color(ctx.backend, resolve_paint_color(runtime, node.color, node.tag, ctx.hot))
        if ctx.backend and ctx.backend.draw_line then ctx.backend:draw_line(x1, y1, x2, y2, thickness) end
    elseif mt == PMT.Text then
        local x = resolve_paint_scalar(runtime, node.x)
        local y = resolve_paint_scalar(runtime, node.y)
        local w = resolve_paint_scalar(runtime, node.w)
        local h = resolve_paint_scalar(runtime, node.h)
        local font = S.get_font(node.font_id)
        if font and ctx.backend and ctx.backend.set_font then ctx.backend:set_font(font) end
        backend_set_color(ctx.backend, resolve_paint_color(runtime, node.color, node.tag, ctx.hot))
        local text_value = resolve_paint_text(runtime, node.text)
        local style = {
            font_id = node.font_id,
            line_height = node.line_height,
            align = node.align,
            wrap = node.wrap,
            overflow = node.overflow,
            line_limit = node.line_limit,
        }
        local max_w = (node.wrap == ui.TEXT_NOWRAP and node.overflow == ui.OVERFLOW_VISIBLE) and INF or w
        local max_h = (node.overflow == ui.OVERFLOW_VISIBLE) and INF or h
        local shaped = S.shape_text(style, text_value, max_w, max_h)
        local old_lh = prepare_font_for_draw(font, node.font_id, node.line_height)
        if node.overflow ~= ui.OVERFLOW_VISIBLE then
            push_clip(ctx, x + ctx.tx, y + ctx.ty, w, h)
        end
        if node.wrap == ui.TEXT_NOWRAP and node.overflow == ui.OVERFLOW_VISIBLE then
            backend_draw_text(ctx.backend, shaped.text, x, y, nil, "left")
        else
            backend_draw_text(ctx.backend, shaped.text, x, y, math.max(1, w), backend_text_align(node.align))
        end
        if node.overflow ~= ui.OVERFLOW_VISIBLE then pop_clip(ctx) end
        restore_font_line_height(font, old_lh)
    else
        error("uilib_iter.draw_paint: unsupported node kind " .. tostring(mt and mt.kind or type(node)), 2)
    end
end

draw_node = function(node, outer, ctx)
    if not node then return end
    local custom = CUSTOM[node]
    if custom then
        local frame = resolve_local_frame(node, outer, ctx.measure_cache)
        push_transform(ctx, frame.x, frame.y)
        draw_paint_node(custom, ctx.runtime, ctx)
        pop_transform(ctx)
        return
    end
    local mt = getmetatable(node)
    if mt == MT.Rect then
        local frame = resolve_local_frame(node, outer, ctx.measure_cache)
        backend_set_color(ctx.backend, S.pick(node.fill, S.pointer_for_id(node.tag or "", ctx.hot)))
        if ctx.backend and ctx.backend.fill_rect then ctx.backend:fill_rect(frame.x, frame.y, frame.w, frame.h) end
    elseif mt == MT.Text then
        draw_text_node(node, outer, ctx)
    elseif mt == MT.Spacer then
        return
    elseif mt == MT.Sized then
        draw_node(node.child, resolve_local_frame(node, outer, ctx.measure_cache), ctx)
    elseif mt == MT.Transform then
        local frame = resolve_local_frame(node, outer, ctx.measure_cache)
        push_transform(ctx, node.tx, node.ty)
        draw_node(node.child, base.frame(frame.x, frame.y, frame.w, frame.h), ctx)
        pop_transform(ctx)
    elseif mt == MT.Clip then
        local frame = resolve_local_frame(node, outer, ctx.measure_cache)
        push_clip(ctx, frame.x + ctx.tx, frame.y + ctx.ty, frame.w, frame.h)
        draw_node(node.child, frame, ctx)
        pop_clip(ctx)
    elseif mt == MT.Pad then
        local frame = resolve_local_frame(node, outer, ctx.measure_cache)
        local iw = math.max(0, frame.w - node.insets.l - node.insets.r)
        local ih = math.max(0, frame.h - node.insets.t - node.insets.b)
        draw_node(node.child, base.frame(frame.x + node.insets.l, frame.y + node.insets.t, iw, ih), ctx)
    elseif mt == MT.Stack then
        local frame = resolve_local_frame(node, outer, ctx.measure_cache)
        for i = 1, #node.children do draw_node(node.children[i], frame, ctx) end
    elseif mt == MT.Flex then
        local placed = flex_layout_children(node, outer, ctx.measure_cache)
        for i = 1, #placed do draw_node(placed[i].node, placed[i].frame, ctx) end
    else
        error("uilib_iter.draw: unsupported node kind " .. tostring(mt and mt.kind or type(node)), 2)
    end
end

local function inside(px, py, x, y, w, h)
    return px >= x and py >= y and px < x + w and py < y + h
end

local function point_visible(ctx, x, y)
    local top = ctx.clip_stack[#ctx.clip_stack]
    return (not top) or inside(x, y, top[1], top[2], top[3], top[4])
end

local hit_node

hit_node = function(node, outer, mx, my, ctx)
    if not node then return nil end
    local mt = getmetatable(node)
    if mt == MT.Rect or mt == MT.Text then
        local frame = resolve_local_frame(node, outer, ctx.measure_cache)
        local x, y = frame.x + ctx.tx, frame.y + ctx.ty
        local tag = node.tag or ""
        if tag ~= "" and point_visible(ctx, mx, my) and inside(mx, my, x, y, frame.w, frame.h) then return tag end
        return nil
    elseif mt == MT.Spacer then
        return nil
    elseif mt == MT.Sized then
        return hit_node(node.child, resolve_local_frame(node, outer, ctx.measure_cache), mx, my, ctx)
    elseif mt == MT.Transform then
        local frame = resolve_local_frame(node, outer, ctx.measure_cache)
        ctx.tx_stack[#ctx.tx_stack + 1] = { ctx.tx, ctx.ty }
        ctx.tx, ctx.ty = ctx.tx + node.tx, ctx.ty + node.ty
        local tag = hit_node(node.child, base.frame(frame.x, frame.y, frame.w, frame.h), mx, my, ctx)
        local t = ctx.tx_stack[#ctx.tx_stack]
        ctx.tx_stack[#ctx.tx_stack] = nil
        ctx.tx, ctx.ty = t[1], t[2]
        return tag
    elseif mt == MT.Clip then
        local frame = resolve_local_frame(node, outer, ctx.measure_cache)
        local ax, ay, nw, nh = intersect_clip(frame.x + ctx.tx, frame.y + ctx.ty, frame.w, frame.h, ctx.clip_stack[#ctx.clip_stack])
        ctx.clip_stack[#ctx.clip_stack + 1] = { ax, ay, nw, nh }
        local tag = hit_node(node.child, frame, mx, my, ctx)
        ctx.clip_stack[#ctx.clip_stack] = nil
        return tag
    elseif mt == MT.Pad then
        local frame = resolve_local_frame(node, outer, ctx.measure_cache)
        local iw = math.max(0, frame.w - node.insets.l - node.insets.r)
        local ih = math.max(0, frame.h - node.insets.t - node.insets.b)
        return hit_node(node.child, base.frame(frame.x + node.insets.l, frame.y + node.insets.t, iw, ih), mx, my, ctx)
    elseif mt == MT.Stack then
        local frame = resolve_local_frame(node, outer, ctx.measure_cache)
        for i = #node.children, 1, -1 do
            local tag = hit_node(node.children[i], frame, mx, my, ctx)
            if tag then return tag end
        end
        return nil
    elseif mt == MT.Flex then
        local placed = flex_layout_children(node, outer, ctx.measure_cache)
        for i = #placed, 1, -1 do
            local tag = hit_node(placed[i].node, placed[i].frame, mx, my, ctx)
            if tag then return tag end
        end
        return nil
    end
    error("uilib_iter.hit: unsupported node kind " .. tostring(mt and mt.kind or type(node)), 2)
end

function ui.draw(node, ...)
    local argv = { ... }
    local opts = (type(argv[#argv]) == "table" and (argv[#argv].backend ~= nil or argv[#argv].hot ~= nil or argv[#argv].state ~= nil or argv[#argv].env ~= nil or argv[#argv].runtime ~= nil or argv[#argv].measure_cache ~= nil)) and table.remove(argv) or {}
    local frame = parse_frame(unpack(argv))
    if not frame then error("uilib_iter.draw: expected (node, frame[, opts]) or (node, w, h[, opts]) or (node, x, y, w, h[, opts])", 2) end
    local ctx = draw_context(opts)
    if not ctx.backend then return end
    draw_node(node, frame, ctx)
    if ctx.backend.set_color then ctx.backend:set_color(1, 1, 1, 1) end
end

function ui.hit(node, ...)
    if getmetatable(node) == nil and type(node) == "table" and node[1] ~= nil and type(node[1]) == "table" and node[1].kind ~= nil and base.hit then
        return base.hit(node, ...)
    end
    local argv = { ... }
    local opts = (type(argv[#argv]) == "table" and (argv[#argv].state ~= nil or argv[#argv].env ~= nil or argv[#argv].measure_cache ~= nil)) and table.remove(argv) or {}
    local frame, mx, my
    if #argv == 3 and type(argv[1]) == "table" then
        frame, mx, my = argv[1], argv[2], argv[3]
    elseif #argv == 4 and type(argv[1]) == "number" then
        frame, mx, my = base.frame(0, 0, argv[1], argv[2]), argv[3], argv[4]
    elseif #argv == 6 then
        frame, mx, my = base.frame(argv[1], argv[2], argv[3], argv[4]), argv[5], argv[6]
    else
        error("uilib_iter.hit: expected (node, frame, mx, my[, opts]) or (node, w, h, mx, my[, opts])", 2)
    end
    local ctx = { tx = 0, ty = 0, tx_stack = {}, clip_stack = {}, state = opts.state, env = opts.env, measure_cache = opts.measure_cache or {} }
    return hit_node(node, frame, mx, my, ctx)
end

local function make_recording_backend(out)
    return {
        set_color = function(_, r, g, b, a) out[#out + 1] = { op = "color", r = r, g = g, b = b, a = a } end,
        set_font = function(_, font) out[#out + 1] = { op = "font", font = font } end,
        fill_rect = function(_, x, y, w, h) out[#out + 1] = { op = "fill_rect", x = x, y = y, w = w, h = h } end,
        stroke_rect = function(_, x, y, w, h, thickness) out[#out + 1] = { op = "stroke_rect", x = x, y = y, w = w, h = h, thickness = thickness } end,
        draw_line = function(_, x1, y1, x2, y2, thickness) out[#out + 1] = { op = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2, thickness = thickness } end,
        draw_text = function(_, text, x, y, width, align) out[#out + 1] = { op = "text", text = text, x = x, y = y, width = width, align = align } end,
        push_clip = function(_, x, y, w, h) out[#out + 1] = { op = "push_clip", x = x, y = y, w = w, h = h } end,
        pop_clip = function(_) out[#out + 1] = { op = "pop_clip" } end,
        push_transform = function(_, tx, ty) out[#out + 1] = { op = "push_transform", tx = tx, ty = ty } end,
        pop_transform = function(_) out[#out + 1] = { op = "pop_transform" } end,
    }
end

local function clear_seq(t)
    for i = #t, 1, -1 do t[i] = nil end
end

local Session = {}
Session.__index = Session

function ui.session(opts)
    opts = opts or {}
    local self = setmetatable({}, Session)
    self.backend = opts.backend or base.get_backend()
    self.state = opts.state or ui.state()
    self.measure_cache = opts.measure_cache or setmetatable({}, { __mode = "k" })
    self.prune_dead_widgets = not not opts.prune_dead_widgets
    self._frame = nil
    self._input = nil
    self._env = nil
    self._hot = { hovered = nil, pressed = nil, dragging = nil }
    self._nav_order = {}
    self._seen_keys = {}
    self._messages = { n = 0, kind = {}, id = {}, a = {}, b = {}, payload = {} }
    self._draw_ctx = {
        backend = self.backend,
        hot = self._hot,
        runtime = nil,
        tx = 0,
        ty = 0,
        tx_stack = {},
        clip_stack = {},
        measure_cache = self.measure_cache,
    }
    self._hit_ctx = {
        tx = 0,
        ty = 0,
        tx_stack = {},
        clip_stack = {},
        measure_cache = self.measure_cache,
    }
    self.stats = {
        frames = 0,
        draws = 0,
        hits = 0,
        paint_draws = 0,
        measure_cache_clears = 0,
    }
    return self
end

function Session:set_backend(backend)
    self.backend = backend
    return self
end

function Session:get_backend()
    return self.backend
end

function Session:get_state()
    return self.state
end

function Session:set_state(state)
    self.state = state or ui.state()
    return self
end

function Session:clone_state()
    return ui.clone_state(self.state)
end

function Session:clear_measure_cache()
    self.measure_cache = setmetatable({}, { __mode = "k" })
    self._draw_ctx.measure_cache = self.measure_cache
    self._hit_ctx.measure_cache = self.measure_cache
    self.stats.measure_cache_clears = self.stats.measure_cache_clears + 1
    return self
end

function Session:clear_widget_state()
    self.state.widgets = {}
    return self
end

function Session:clear_widget(id)
    if self.state.widgets then self.state.widgets[id] = nil end
    return self
end

function Session:reset()
    self.state = ui.state()
    return self:clear_measure_cache()
end

function Session:resolve_key(node, fallback, path)
    local k = KEYS[node]
    if k ~= nil then return k end
    if fallback ~= nil and fallback ~= "" then return fallback end
    return path
end

function Session:widget(id, init_fn)
    if id == nil then return init_fn and init_fn() or {} end
    local widgets = self.state.widgets
    if widgets == nil then widgets = {}; self.state.widgets = widgets end
    local st = widgets[id]
    if st == nil then
        st = init_fn and init_fn() or {}
        widgets[id] = st
    end
    self._seen_keys[id] = true
    return st
end

function Session:reset_messages()
    self._messages.n = 0
end

function Session:emit(kind, id, a, b, payload)
    local m = self._messages
    local n = m.n + 1
    m.n = n
    m.kind[n] = kind
    m.id[n] = id
    m.a[n] = a
    m.b[n] = b
    m.payload[n] = payload
end

function Session:messages()
    return self._messages
end

function Session:is_hovered(id) return self.state.hot == id end
function Session:is_pressed(id) return self.state.pressed == id end
function Session:is_active(id) return self.state.active == id end
function Session:is_dragging(id) return self.state.dragging == id end
function Session:is_focused(id) return self.state.focused == id end

function Session:focus(id) self.state.focused = id; return self end
function Session:blur() self.state.focused = nil; return self end

function Session:hot_table()
    local hot = self._hot
    hot.hovered = self.state.hot
    hot.pressed = self.state.pressed or self.state.active
    hot.dragging = self.state.dragging
    return hot
end

function Session:_reset_draw_ctx(runtime, backend, hot)
    local ctx = self._draw_ctx
    ctx.backend = backend or self.backend or base.get_backend()
    ctx.hot = hot or self:hot_table()
    ctx.runtime = runtime or {}
    ctx.tx, ctx.ty = 0, 0
    clear_seq(ctx.tx_stack)
    clear_seq(ctx.clip_stack)
    ctx.measure_cache = self.measure_cache
    return ctx
end

function Session:_reset_hit_ctx()
    local ctx = self._hit_ctx
    ctx.tx, ctx.ty = 0, 0
    clear_seq(ctx.tx_stack)
    clear_seq(ctx.clip_stack)
    ctx.measure_cache = self.measure_cache
    return ctx
end

function Session:hit(node, opts)
    opts = opts or {}
    local frame = assert(opts.frame, "uilib_iter.session:hit expected opts.frame")
    local mx = assert(opts.mx, "uilib_iter.session:hit expected opts.mx")
    local my = assert(opts.my, "uilib_iter.session:hit expected opts.my")
    local ctx = self:_reset_hit_ctx()
    self.stats.hits = self.stats.hits + 1
    return hit_node(node, frame, mx, my, ctx)
end

function Session:draw(node, opts)
    opts = opts or {}
    local frame = assert(opts.frame, "uilib_iter.session:draw expected opts.frame")
    local ctx = self:_reset_draw_ctx(opts.runtime or opts.env, opts.backend, opts.hot)
    if not ctx.backend then return end
    self.stats.draws = self.stats.draws + 1
    draw_node(node, frame, ctx)
    if ctx.backend.set_color then ctx.backend:set_color(1, 1, 1, 1) end
end

function Session:collect(node, opts)
    local out = {}
    opts = opts or {}
    self:draw(node, {
        frame = assert(opts.frame, "uilib_iter.session:collect expected opts.frame"),
        env = opts.env,
        runtime = opts.runtime,
        hot = opts.hot,
        backend = make_recording_backend(out),
    })
    return out
end

function Session:draw_paint(node, runtime, opts)
    opts = opts or {}
    local ctx = self:_reset_draw_ctx(runtime, opts.backend, opts.hot)
    if not ctx.backend then return end
    self.stats.paint_draws = self.stats.paint_draws + 1
    draw_paint_node(node, runtime or {}, ctx)
    if ctx.backend.set_color then ctx.backend:set_color(1, 1, 1, 1) end
end

function Session:collect_paint(node, runtime, opts)
    local out = {}
    opts = opts or {}
    self:draw_paint(node, runtime, {
        backend = make_recording_backend(out),
        hot = opts.hot,
    })
    return out
end

function Session:frame(node, opts)
    opts = opts or {}
    local frame = assert(opts.frame, "uilib_iter.session:frame expected opts.frame")
    local input = opts.input or {}
    local env = opts.env or opts.runtime or {}
    local overlay = opts.overlay
    local do_pick = opts.pick ~= false
    local do_draw = opts.draw ~= false

    self.stats.frames = self.stats.frames + 1
    self._frame = frame
    self._input = input
    self._env = env
    self:reset_messages()

    if self.prune_dead_widgets then
        for k in pairs(self._seen_keys) do self._seen_keys[k] = nil end
    end

    local hovered = self.state.hot
    if do_pick and input.mouse_x ~= nil and input.mouse_y ~= nil then
        hovered = self:hit(node, { frame = frame, mx = input.mouse_x, my = input.mouse_y })
    end
    self.state.hot = hovered

    if input.mouse_pressed then
        self.state.active = hovered
        self.state.pressed = hovered
        if hovered ~= nil then self.state.focused = hovered end
    elseif input.mouse_released then
        local active = self.state.active
        if active ~= nil and active == hovered then self:emit("click", active) end
        self.state.active = nil
        self.state.pressed = nil
        self.state.dragging = nil
    elseif input.mouse_down then
        self.state.pressed = self.state.active
    else
        self.state.pressed = nil
    end

    if do_draw then
        self:draw(node, {
            frame = frame,
            env = env,
            backend = opts.backend,
            hot = opts.hot,
        })
        if overlay ~= nil then
            self:draw_paint(overlay, env, {
                backend = opts.backend,
                hot = opts.hot,
            })
        end
    end

    if self.prune_dead_widgets and self.state.widgets then
        for k in pairs(self.state.widgets) do
            if not self._seen_keys[k] then self.state.widgets[k] = nil end
        end
    end

    return self.state, self._messages
end

function ui.collect(node, ...)
    local argv = { ... }
    local opts = (type(argv[#argv]) == "table" and (argv[#argv].backend ~= nil or argv[#argv].hot ~= nil or argv[#argv].state ~= nil or argv[#argv].env ~= nil or argv[#argv].runtime ~= nil or argv[#argv].measure_cache ~= nil)) and table.remove(argv) or {}
    local frame = parse_frame(unpack(argv))
    if not frame then error("uilib_iter.collect: expected frame", 2) end
    local session = ui.session {
        backend = opts.backend,
        state = opts.state,
        measure_cache = opts.measure_cache,
    }
    return session:collect(node, {
        frame = frame,
        env = opts.env,
        runtime = opts.runtime,
        hot = opts.hot,
    })
end

function ui.draw_paint(node, runtime, opts)
    opts = opts or {}
    local session = ui.session {
        backend = opts.backend,
        state = opts.state,
        measure_cache = opts.measure_cache,
    }
    return session:draw_paint(node, runtime, opts)
end

function ui.collect_paint(node, runtime, opts)
    opts = opts or {}
    local session = ui.session {
        backend = opts.backend,
        state = opts.state,
        measure_cache = opts.measure_cache,
    }
    return session:collect_paint(node, runtime, opts)
end

function ui.step_frame(node, opts)
    opts = opts or {}
    local session = opts.session or ui.session {
        backend = opts.backend,
        state = opts.state,
        measure_cache = opts.measure_cache,
    }
    local draw = opts.draw
    if draw == nil then draw = opts.backend ~= nil or session:get_backend() ~= nil end
    return session:frame(node, {
        frame = assert(opts.frame, "uilib_iter.step_frame: expected opts.frame"),
        input = opts.input,
        env = opts.env,
        runtime = opts.runtime,
        overlay = opts.overlay,
        backend = opts.backend,
        pick = opts.pick,
        draw = draw,
        hot = opts.hot,
    })
end

return ui
