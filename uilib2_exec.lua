-- uilib2_exec.lua — emit / compile / paint / hit (separate chunk for local-slot limit)
return function(ui, T, S, stats, measure_cache, compile_cache, assemble_cache)

local NULL_PACK, TXT_START, TXT_NOWRAP = S.NULL_PACK, S.TXT_START, S.TXT_NOWRAP
local TXT_CENTER, TXT_END, TXT_JUSTIFY = S.TXT_CENTER, S.TXT_END, S.TXT_JUSTIFY
local OV_VISIBLE, OV_CLIP, OV_ELLIPSIS = S.OV_VISIBLE, S.OV_CLIP, S.OV_ELLIPSIS
local LH_AUTO, INF, BASELINE_NONE = S.LH_AUTO, S.INF, S.BASELINE_NONE
local K_RECT, K_TEXTBLOCK = S.K_RECT, S.K_TEXTBLOCK
local K_PUSH_CLIP, K_POP_CLIP, K_PUSH_TX, K_POP_TX = S.K_PUSH_CLIP, S.K_POP_CLIP, S.K_PUSH_TX, S.K_POP_TX
local K_DYNTEXT, K_DYNMETER, K_DYNPLAYHEAD = S.K_DYNTEXT, S.K_DYNMETER, S.K_DYNPLAYHEAD
local VCmd, Fragment, PlanOp, Plan = S.VCmd, S.Fragment, S.PlanOp, S.Plan
local PK_PLACE, PK_PUSH_CLIP, PK_POP_CLIP = S.PK_PLACE, S.PK_PUSH_CLIP, S.PK_POP_CLIP
local PK_PUSH_TX, PK_POP_TX = S.PK_PUSH_TX, S.PK_POP_TX
local SpanExact, SpanAtMost, Frame, Constraint = S.SpanExact, S.SpanAtMost, S.Frame, S.Constraint
local SPAN_UNBOUNDED = S.SPAN_UNBOUNDED
local AXIS_ROW, AXIS_ROW_REV, AXIS_COL, AXIS_COL_REV = S.AXIS_ROW, S.AXIS_ROW_REV, S.AXIS_COL, S.AXIS_COL_REV
local WRAP_NO, WRAP_REV = S.WRAP_NO, S.WRAP_REV
local MAIN_START, MAIN_END, MAIN_CENTER = S.MAIN_START, S.MAIN_END, S.MAIN_CENTER
local MAIN_BETWEEN, MAIN_AROUND, MAIN_EVENLY = S.MAIN_BETWEEN, S.MAIN_AROUND, S.MAIN_EVENLY
local CROSS_AUTO, CROSS_START, CROSS_END = S.CROSS_AUTO, S.CROSS_START, S.CROSS_END
local CROSS_CENTER, CROSS_STRETCH, CROSS_BASELINE = S.CROSS_CENTER, S.CROSS_STRETCH, S.CROSS_BASELINE
local CONTENT_START, CONTENT_END, CONTENT_CENTER = S.CONTENT_START, S.CONTENT_END, S.CONTENT_CENTER
local CONTENT_STRETCH, CONTENT_BETWEEN, CONTENT_AROUND, CONTENT_EVENLY = S.CONTENT_STRETCH, S.CONTENT_BETWEEN, S.CONTENT_AROUND, S.CONTENT_EVENLY
local resolve_line_height, raw_text_height = S.resolve_line_height, S.raw_text_height
local get_font, shaped_text, shape_text = S.get_font, S.shaped_text, S.shape_text
local text_intrinsic_widths, make_baseline = S.text_intrinsic_widths, S.make_baseline
local pick, pointer_for_id = S.pick, S.pointer_for_id
local resolve_style = S.resolve_style

local function is_row_axis(axis) return axis == AXIS_ROW or axis == AXIS_ROW_REV end
local function is_reverse_axis(axis) return axis == AXIS_ROW_REV or axis == AXIS_COL_REV end
local function is_wrap_reverse(wrap) return wrap == WRAP_REV end
local function clamp(v, lo, hi) if lo and v < lo then v = lo end; if hi and v > hi then v = hi end; return v end
local function max_of(a, b) return (a > b) and a or b end
local function span_available(span) if span == SPAN_UNBOUNDED then return INF, false end; local mt = getmetatable(span); if mt == getmetatable(SpanExact(0)) then return span.px, true end; if mt == getmetatable(SpanAtMost(0)) then return span.px, false end; return INF, false end
local function exact_or_atmost(px, exact) if px == INF then return SPAN_UNBOUNDED end; if exact then return SpanExact(px) end; return SpanAtMost(px) end
local function exact_constraint_from_frame(frame) return Constraint(SpanExact(frame.w), SpanExact(frame.h)) end
local function available_constraint_from_frame(frame) return Constraint(SpanAtMost(frame.w), SpanAtMost(frame.h)) end

local function main_margins(margin, axis)
    if axis == AXIS_ROW then return margin.l, margin.r end
    if axis == AXIS_ROW_REV then return margin.r, margin.l end
    if axis == AXIS_COL then return margin.t, margin.b end
    return margin.b, margin.t
end
local function cross_margins(margin, axis)
    if axis == AXIS_ROW or axis == AXIS_ROW_REV then return margin.t, margin.b end
    return margin.l, margin.r
end
local function main_size_of(m, axis) return is_row_axis(axis) and m.used_w or m.used_h end
local function cross_size_of(m, axis) return is_row_axis(axis) and m.used_h or m.used_w end
local function intrinsic_min_main(intr, axis) return is_row_axis(axis) and intr.min_w or intr.min_h end
local function intrinsic_max_main(intr, axis) return is_row_axis(axis) and intr.max_w or intr.max_h end
local function intrinsic_min_cross(intr, axis) return is_row_axis(axis) and intr.min_h or intr.min_w end
local function intrinsic_max_cross(intr, axis) return is_row_axis(axis) and intr.max_h or intr.max_w end
local function baseline_num(b) if b == BASELINE_NONE or b == nil then return nil end; return b.px end
local function resolve_basis_value(spec, available, content_value)
    if spec == T.UI.BasisAuto or spec == T.UI.BasisContent then return content_value end
    local mt = getmetatable(spec)
    if mt == getmetatable(T.UI.BasisPx(0)) then return spec.px end
    if mt == getmetatable(T.UI.BasisPercent(0)) then if available ~= INF then return available * spec.ratio end; return content_value end
    return content_value
end

-- ── Emit helpers ─────────────────────────────────────────────

local function VRect(tag, x, y, w, h, color_pack)
    return VCmd(K_RECT, tag, x, y, w, h, color_pack, 0, "", 0, 0, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO, nil, nil, nil, nil)
end
local function VText(tag, x, y, w, h, style, text)
    return VCmd(K_TEXTBLOCK, tag, x, y, w, h, style.color, style.font_id, text, 0, 0, style.align, style.wrap, style.overflow, style.line_height, nil, nil, nil, nil)
end
local function VPushClip(x, y, w, h)
    return VCmd(K_PUSH_CLIP, "", x, y, w, h, NULL_PACK, 0, "", 0, 0, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO, nil, nil, nil, nil)
end
local function VPopClip(x, y, w, h)
    return VCmd(K_POP_CLIP, "", x, y, w, h, NULL_PACK, 0, "", 0, 0, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO, nil, nil, nil, nil)
end
local function VPushTx(tx, ty)
    return VCmd(K_PUSH_TX, "", 0, 0, 0, 0, NULL_PACK, 0, "", tx, ty, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO, nil, nil, nil, nil)
end
local function VPopTx(tx, ty)
    return VCmd(K_POP_TX, "", 0, 0, 0, 0, NULL_PACK, 0, "", tx, ty, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO, nil, nil, nil, nil)
end

local function resolve_local_frame(node, outer)
    local m = ui.measure(node, exact_constraint_from_frame(outer))
    return Frame(outer.x, outer.y, m.used_w, m.used_h), m
end

-- ── Node emit methods ────────────────────────────────────────

function T.UI.Rect:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    out[#out+1] = VRect(self.tag, frame.x, frame.y, frame.w, frame.h, self.fill)
end

function T.UI.Spacer:_emit() end

function T.UI.Text:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    local max_w = (self.style.wrap == TXT_NOWRAP) and INF or frame.w
    local max_h = (self.style.overflow == OV_VISIBLE) and INF or frame.h
    local shape = shaped_text(self, max_w, max_h)
    out[#out+1] = VText(self.tag, frame.x, frame.y, frame.w, frame.h, self.style, shape.text)
end

function T.UI.Sized:_emit(out, outer) self.child:_emit(out, resolve_local_frame(self, outer)) end

function T.UI.Transform:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    out[#out+1] = VPushTx(self.tx, self.ty)
    self.child:_emit(out, Frame(frame.x, frame.y, frame.w, frame.h))
    out[#out+1] = VPopTx(self.tx, self.ty)
end

function T.UI.Clip:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    out[#out+1] = VPushClip(frame.x, frame.y, frame.w, frame.h)
    self.child:_emit(out, frame)
    out[#out+1] = VPopClip(frame.x, frame.y, frame.w, frame.h)
end

function T.UI.Pad:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    local iw = math.max(0, frame.w - self.insets.l - self.insets.r)
    local ih = math.max(0, frame.h - self.insets.t - self.insets.b)
    self.child:_emit(out, Frame(frame.x + self.insets.l, frame.y + self.insets.t, iw, ih))
end

function T.UI.Stack:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    for i = 1, #self.children do self.children[i]:_emit(out, frame) end
end

-- ── Flex emit ────────────────────────────────────────────────

local function flex_collect_infos_emit(node, constraint)
    local axis = node.axis
    local avail_main = is_row_axis(axis) and span_available(constraint.w) or span_available(constraint.h)
    local infos = {}
    for i = 1, #node.children do
        local item = node.children[i]
        local m = ui.measure(item.node, constraint)
        local ml, mr = main_margins(item.margin, axis)
        local mt_, mb = cross_margins(item.margin, axis)
        infos[i] = { item = item, measure = m, base = resolve_basis_value(item.basis, avail_main, main_size_of(m, axis)), min_main = intrinsic_min_main(m.intrinsic, axis), max_main = intrinsic_max_main(m.intrinsic, axis), min_cross = intrinsic_min_cross(m.intrinsic, axis), max_cross = intrinsic_max_cross(m.intrinsic, axis), main_margin_start = ml, main_margin_end = mr, cross_margin_start = mt_, cross_margin_end = mb }
    end
    return infos, avail_main
end

local function distribute_line(infos, indices, avail_main, gap)
    local n = #indices; local sizes, frozen = {}, {}
    for i = 1, n do sizes[indices[i]] = infos[indices[i]].base end
    if avail_main == INF then return sizes end
    while true do
        local used = gap * math.max(0, n-1); local free, weight = 0, 0
        for i = 1, n do local idx = indices[i]; local inf = infos[idx]; used = used + inf.main_margin_start + inf.main_margin_end; if frozen[idx] then used = used + sizes[idx] else used = used + inf.base end end
        free = avail_main - used
        if math.abs(free) < 1e-6 then break end
        if free > 0 then for i = 1, n do local idx = indices[i]; if not frozen[idx] and infos[idx].item.grow > 0 then weight = weight + infos[idx].item.grow end end
        else for i = 1, n do local idx = indices[i]; if not frozen[idx] and infos[idx].item.shrink > 0 then weight = weight + infos[idx].item.shrink * infos[idx].base end end end
        if weight <= 0 then break end
        local clamped = false
        for i = 1, n do local idx = indices[i]; if not frozen[idx] then local inf = infos[idx]; local target
            if free > 0 then target = inf.item.grow > 0 and (inf.base + free * (inf.item.grow / weight)) or inf.base
            else local sw = inf.item.shrink * inf.base; target = sw > 0 and (inf.base + free * (sw / weight)) or inf.base end
            local cl = clamp(target, inf.min_main, inf.max_main)
            if cl ~= target then sizes[idx] = cl; frozen[idx] = true; clamped = true end
        end end
        if not clamped then for i = 1, n do local idx = indices[i]; if not frozen[idx] then local inf = infos[idx]
            if free > 0 then sizes[idx] = inf.item.grow > 0 and (inf.base + free * (inf.item.grow / weight)) or inf.base
            else local sw = inf.item.shrink * inf.base; sizes[idx] = sw > 0 and (inf.base + free * (sw / weight)) or inf.base end
        end end; break end
    end
    for i = 1, n do local idx = indices[i]; if not sizes[idx] then sizes[idx] = infos[idx].base end end
    return sizes
end

local function line_used_main(infos, indices, sizes, gap)
    local used = gap * math.max(0, #indices - 1)
    for i = 1, #indices do local idx = indices[i]; used = used + sizes[idx] + infos[idx].main_margin_start + infos[idx].main_margin_end end
    return used
end

function T.UI.Flex:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    local axis, rowish = self.axis, is_row_axis(self.axis)
    local main_size = rowish and frame.w or frame.h
    local cross_size = rowish and frame.h or frame.w
    local wrap = self.wrap
    local inner_constraint = available_constraint_from_frame(frame)
    local child_infos = flex_collect_infos_emit(self, inner_constraint)
    if #child_infos == 0 then return end

    local lines = {}
    if wrap == WRAP_NO or main_size == INF then
        lines[1] = {}; for i = 1, #child_infos do lines[1][i] = i end
    else
        local cur, cur_used = {}, 0
        for i = 1, #child_infos do local inf = child_infos[i]; local need = inf.base + inf.main_margin_start + inf.main_margin_end; if #cur > 0 then need = need + self.gap_main end
            if #cur > 0 and cur_used + need > main_size then lines[#lines+1] = cur; cur, cur_used = {}, 0; need = inf.base + inf.main_margin_start + inf.main_margin_end end
            cur[#cur+1] = i; cur_used = cur_used + need end
        if #cur > 0 then lines[#lines+1] = cur end
    end

    local line_infos, natural_cross_total = {}, 0
    for li = 1, #lines do
        local idxs = lines[li]; local sizes = distribute_line(child_infos, idxs, main_size, self.gap_main)
        local used_main = line_used_main(child_infos, idxs, sizes, self.gap_main)
        local line_cross, line_baseline, items = 0, 0, {}
        for j = 1, #idxs do
            local idx = idxs[j]; local inf = child_infos[idx]; local slot_main = sizes[idx]
            local ccon = rowish and Constraint(SpanExact(math.max(0, slot_main)), exact_or_atmost(cross_size, false)) or Constraint(exact_or_atmost(cross_size, false), SpanExact(math.max(0, slot_main)))
            local m = ui.measure(inf.item.node, ccon)
            local actual_cross = cross_size_of(m, axis); local b = baseline_num(m.baseline)
            if b and rowish then line_baseline = math.max(line_baseline, b + inf.cross_margin_start) end
            line_cross = math.max(line_cross, actual_cross + inf.cross_margin_start + inf.cross_margin_end)
            items[j] = { idx = idx, slot_main = slot_main, actual_main = math.min(slot_main, main_size_of(m, axis)), actual_cross = actual_cross, measure = m, baseline = b }
        end
        line_infos[li] = { items = items, used_main = used_main, natural_cross = line_cross, baseline = line_baseline }
        natural_cross_total = natural_cross_total + line_cross; if li > 1 then natural_cross_total = natural_cross_total + self.gap_cross end
    end

    local line_cross_sizes, line_cross_pos = {}, {}
    local free_cross = (cross_size == INF) and 0 or math.max(0, cross_size - natural_cross_total)
    local line_lead, line_gap_extra = 0, 0
    if #line_infos == 1 and cross_size ~= INF then line_cross_sizes[1] = cross_size
    elseif self.align_content == CONTENT_STRETCH and cross_size ~= INF and #line_infos > 0 then
        local extra = free_cross / #line_infos; for li = 1, #line_infos do line_cross_sizes[li] = line_infos[li].natural_cross + extra end
    else
        for li = 1, #line_infos do line_cross_sizes[li] = line_infos[li].natural_cross end
        if self.align_content == CONTENT_END then line_lead = free_cross
        elseif self.align_content == CONTENT_CENTER then line_lead = free_cross / 2
        elseif self.align_content == CONTENT_BETWEEN then line_gap_extra = (#line_infos > 1) and (free_cross / (#line_infos - 1)) or 0
        elseif self.align_content == CONTENT_AROUND then line_gap_extra = free_cross / #line_infos; line_lead = line_gap_extra / 2
        elseif self.align_content == CONTENT_EVENLY then line_gap_extra = free_cross / (#line_infos + 1); line_lead = line_gap_extra end
    end
    do local p = line_lead; for li = 1, #line_infos do line_cross_pos[li] = p; p = p + line_cross_sizes[li] + self.gap_cross + line_gap_extra end end

    for li = 1, #line_infos do
        local line = line_infos[li]; local line_slot_cross = line_cross_sizes[li]
        local free_main = (main_size == INF) and 0 or math.max(0, main_size - line.used_main)
        local line_start, gap_extra = 0, 0
        if self.justify == MAIN_END then line_start = free_main
        elseif self.justify == MAIN_CENTER then line_start = free_main / 2
        elseif self.justify == MAIN_BETWEEN then gap_extra = (#line.items > 1) and (free_main / (#line.items - 1)) or 0
        elseif self.justify == MAIN_AROUND then gap_extra = free_main / #line.items; line_start = gap_extra / 2
        elseif self.justify == MAIN_EVENLY then gap_extra = free_main / (#line.items + 1); line_start = gap_extra end
        local pmain = line_start
        for j = 1, #line.items do
            local item = line.items[j]; local inf = child_infos[item.idx]
            local eff_align = inf.item.self_align; if eff_align == CROSS_AUTO then eff_align = self.align_items end
            if (not rowish) and eff_align == CROSS_BASELINE then eff_align = CROSS_START end
            local cross_inner = math.max(0, line_slot_cross - inf.cross_margin_start - inf.cross_margin_end)
            local actual_cross = item.actual_cross
            if eff_align == CROSS_STRETCH then actual_cross = clamp(cross_inner, inf.min_cross, inf.max_cross) else actual_cross = clamp(actual_cross, inf.min_cross, inf.max_cross) end
            local cross_offset
            if eff_align == CROSS_END then cross_offset = line_slot_cross - inf.cross_margin_end - actual_cross
            elseif eff_align == CROSS_CENTER then cross_offset = inf.cross_margin_start + (cross_inner - actual_cross) / 2
            elseif eff_align == CROSS_BASELINE and rowish and item.baseline then cross_offset = line.baseline - item.baseline
            else cross_offset = inf.cross_margin_start end
            local logical_main = pmain + inf.main_margin_start
            local logical_cross = line_cross_pos[li] + cross_offset
            local x, y, w, h
            if rowish then w, h = item.actual_main, actual_cross
                x = is_reverse_axis(axis) and (frame.x + frame.w - logical_main - w) or (frame.x + logical_main)
                y = is_wrap_reverse(wrap) and (frame.y + frame.h - logical_cross - h) or (frame.y + logical_cross)
            else w, h = actual_cross, item.actual_main
                x = is_wrap_reverse(wrap) and (frame.x + frame.w - logical_cross - w) or (frame.x + logical_cross)
                y = is_reverse_axis(axis) and (frame.y + frame.h - logical_main - h) or (frame.y + logical_main) end
            inf.item.node:_emit(out, Frame(x, y, w, h))
            pmain = pmain + inf.main_margin_start + item.slot_main + inf.main_margin_end + self.gap_main + gap_extra
        end
    end
end

-- ── Dyn stubs ────────────────────────────────────────────────

function T.UI.DynText:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    out[#out+1] = VCmd(K_DYNTEXT, self.tag, frame.x, frame.y, frame.w, frame.h, self.style.color, self.style.font_id, "", 0, 0, self.style.align, self.style.wrap, self.style.overflow, self.style.line_height, self.slot, nil, nil, nil)
end

function T.UI.DynMeter:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    out[#out+1] = VCmd(K_DYNMETER, self.tag, frame.x, frame.y, frame.w, frame.h, self.bg, 0, "", 0, 0, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO, self.slot, self.fill, self.hot, self.clip)
end

function T.UI.DynPlayhead:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    out[#out+1] = VCmd(K_DYNPLAYHEAD, self.tag, frame.x, frame.y, frame.w, frame.h, self.color, 0, "", 0, 0, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO, self.slot, nil, nil, nil)
end

-- ── Compile / Fragment / Assemble ────────────────────────────

function ui.compile(node, a, b, c, d)
    stats.compile.calls = stats.compile.calls + 1
    local frame
    if type(a) == "number" and type(b) == "number" and c == nil then frame = Frame(0, 0, a, b)
    elseif type(a) == "number" and type(b) == "number" and type(c) == "number" and type(d) == "number" then frame = Frame(a, b, c, d)
    else frame = a end
    if frame == nil then error('uilib2.compile: expected (node, frame) or (node, w, h) or (node, x, y, w, h)', 2) end
    local by_node = compile_cache[node]
    if by_node then local hit = by_node[frame]; if hit then stats.compile.hits = stats.compile.hits + 1; return hit end
    else by_node = setmetatable({}, { __mode = "k" }); compile_cache[node] = by_node end
    local out = {}; node:_emit(out, frame); by_node[frame] = out; return out
end

function ui.fragment(node, a, b, c, d)
    local frame
    if type(a) == "number" and type(b) == "number" and c == nil then frame = Frame(0, 0, a, b)
    elseif type(a) == "number" and type(b) == "number" and type(c) == "number" and type(d) == "number" then frame = Frame(a, b, c, d)
    else frame = a end
    if frame == nil then error('uilib2.fragment', 2) end
    return Fragment(frame.w, frame.h, ui.compile(node, frame))
end

function ui.assemble(plan)
    stats.assemble.calls = stats.assemble.calls + 1
    local hit = assemble_cache[plan]; if hit then stats.assemble.hits = stats.assemble.hits + 1; return hit end
    local out = {}; local ops = plan.ops
    for i = 1, #ops do local op = ops[i]; local k = op.kind
        if k == PK_PLACE then local frag = op.fragment
            if op.x == 0 and op.y == 0 then local cmds = frag.cmds; for j = 1, #cmds do out[#out+1] = cmds[j] end
            else out[#out+1] = VPushTx(op.x, op.y); local cmds = frag.cmds; for j = 1, #cmds do out[#out+1] = cmds[j] end; out[#out+1] = VPopTx(op.x, op.y) end
        elseif k == PK_PUSH_CLIP then out[#out+1] = VPushClip(op.x, op.y, op.w, op.h)
        elseif k == PK_POP_CLIP then out[#out+1] = VPopClip(op.x, op.y, op.w, op.h)
        elseif k == PK_PUSH_TX then out[#out+1] = VPushTx(op.tx, op.ty)
        elseif k == PK_POP_TX then out[#out+1] = VPopTx(op.tx, op.ty) end
    end
    assemble_cache[plan] = out; return out
end

-- ── Paint ────────────────────────────────────────────────────

local function rgba8_to_love(rgba8)
    local a = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local b = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local g = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local r = (rgba8 % 256) / 255
    return r, g, b, a
end

local function love_text_align(align)
    if align == TXT_CENTER then return "center" end; if align == TXT_END then return "right" end; if align == TXT_JUSTIFY then return "justify" end; return "left"
end

function ui.paint(cmds, opts)
    opts = opts or {}
    if not (love and love.graphics) then return end
    local hot = opts.hot or {}
    local tx, ty = 0, 0; local tx_stack, clip_stack = {}, {}
    for i = 1, #cmds do
        local c = cmds[i]; local k = c.kind
        if k == K_RECT then
            love.graphics.setColor(rgba8_to_love(pick(c.color, pointer_for_id(c.htag, hot))))
            love.graphics.rectangle("fill", c.x, c.y, c.w, c.h)
        elseif k == K_TEXTBLOCK then
            local font = get_font(c.font_id); if font then love.graphics.setFont(font) end
            love.graphics.setColor(rgba8_to_love(pick(c.color, pointer_for_id(c.htag, hot))))
            local old_lh = nil
            if font and font.getLineHeight and font.setLineHeight then old_lh = font:getLineHeight(); local lh = resolve_line_height(c.line_height, c.font_id); local fh = raw_text_height(c.font_id); if fh > 0 then font:setLineHeight(lh / fh) end end
            local restore_clip = nil
            if c.overflow ~= OV_VISIBLE then
                local ax, ay, nw, nh = c.x + tx, c.y + ty, c.w, c.h; local top = clip_stack[#clip_stack]
                if top then local x2 = math.max(ax, top[1]); local y2 = math.max(ay, top[2]); nw = math.max(0, math.min(ax + c.w, top[1] + top[3]) - x2); nh = math.max(0, math.min(ay + c.h, top[2] + top[4]) - y2); ax, ay = x2, y2; restore_clip = top end
                love.graphics.setScissor(ax, ay, nw, nh) end
            if c.text_wrap == TXT_NOWRAP and c.overflow == OV_VISIBLE then love.graphics.print(c.text, c.x, c.y) else love.graphics.printf(c.text, c.x, c.y, math.max(1, c.w), love_text_align(c.text_align)) end
            if restore_clip then love.graphics.setScissor(restore_clip[1], restore_clip[2], restore_clip[3], restore_clip[4]) elseif c.overflow ~= OV_VISIBLE then love.graphics.setScissor() end
            if font and old_lh and font.setLineHeight then font:setLineHeight(old_lh) end
        elseif k == K_PUSH_CLIP then
            local ax, ay, nw, nh = c.x + tx, c.y + ty, c.w, c.h; local top = clip_stack[#clip_stack]
            if top then local x2 = math.max(ax, top[1]); local y2 = math.max(ay, top[2]); nw = math.max(0, math.min(ax + c.w, top[1] + top[3]) - x2); nh = math.max(0, math.min(ay + c.h, top[2] + top[4]) - y2); ax, ay = x2, y2 end
            clip_stack[#clip_stack+1] = { ax, ay, nw, nh }; love.graphics.setScissor(ax, ay, nw, nh)
        elseif k == K_POP_CLIP then
            clip_stack[#clip_stack] = nil; local top = clip_stack[#clip_stack]
            if top then love.graphics.setScissor(top[1], top[2], top[3], top[4]) else love.graphics.setScissor() end
        elseif k == K_PUSH_TX then
            tx_stack[#tx_stack+1] = { tx, ty }; tx, ty = tx + c.tx, ty + c.ty
            love.graphics.push("transform"); love.graphics.translate(c.tx, c.ty)
        elseif k == K_POP_TX then
            love.graphics.pop(); local t = tx_stack[#tx_stack]; tx_stack[#tx_stack] = nil; tx, ty = t[1], t[2]
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- ── Hit test ─────────────────────────────────────────────────

local function inside(px, py, x, y, w, h) return px >= x and py >= y and px < x + w and py < y + h end

function ui.hit(cmds, mx, my)
    local tx, ty = 0, 0; local clip_stack = {}
    local function intersect(a, b)
        if not a then return b end
        local x1, y1 = math.max(a[1], b[1]), math.max(a[2], b[2])
        local x2, y2 = math.min(a[1]+a[3], b[1]+b[3]), math.min(a[2]+a[4], b[2]+b[4])
        return { x1, y1, math.max(0, x2-x1), math.max(0, y2-y1) }
    end
    for i = #cmds, 1, -1 do
        local c = cmds[i]; local k = c.kind
        if k == K_POP_TX then tx, ty = tx + c.tx, ty + c.ty
        elseif k == K_PUSH_TX then tx, ty = tx - c.tx, ty - c.ty
        elseif k == K_POP_CLIP then clip_stack[#clip_stack+1] = intersect(clip_stack[#clip_stack], { c.x+tx, c.y+ty, c.w, c.h })
        elseif k == K_PUSH_CLIP then clip_stack[#clip_stack] = nil
        elseif k == K_RECT or k == K_TEXTBLOCK then
            if c.htag ~= "" then local x, y = c.x + tx, c.y + ty; local clip = clip_stack[#clip_stack]
                if (not clip or inside(mx, my, clip[1], clip[2], clip[3], clip[4])) and inside(mx, my, x, y, c.w, c.h) then return c.htag end end
        end
    end
    return nil
end

-- ── Node methods / diagnostics ───────────────────────────────

function T.UI.Node:measure(constraint) return ui.measure(self, constraint) end
function T.UI.Node:compile(frame) return ui.compile(self, frame) end
function T.UI.Node:emit_into(out, frame) return self:_emit(out, frame) end
function T.View.Plan:cmds() return ui.assemble(self) end

end -- function(ui, T, S, ...)
