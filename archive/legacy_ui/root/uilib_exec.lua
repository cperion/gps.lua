-- uilib_exec.lua — emit / compile / paint / hit (separate chunk for local-slot limit)
return function(ui, T, S, stats, measure_cache, compile_cache, assemble_cache, paint_compile_cache)

local NULL_PACK, TXT_START, TXT_NOWRAP = S.NULL_PACK, S.TXT_START, S.TXT_NOWRAP
local TXT_CENTER, TXT_END, TXT_JUSTIFY = S.TXT_CENTER, S.TXT_END, S.TXT_JUSTIFY
local OV_VISIBLE, OV_CLIP, OV_ELLIPSIS = S.OV_VISIBLE, S.OV_CLIP, S.OV_ELLIPSIS
local LH_AUTO, UNLIMITED_LINES, INF, BASELINE_NONE = S.LH_AUTO, S.UNLIMITED_LINES, S.INF, S.BASELINE_NONE
local K_RECT, K_TEXTBLOCK = S.K_RECT, S.K_TEXTBLOCK
local K_PUSH_CLIP, K_POP_CLIP, K_PUSH_TX, K_POP_TX = S.K_PUSH_CLIP, S.K_POP_CLIP, S.K_PUSH_TX, S.K_POP_TX
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

-- ── Static View emit helpers ────────────────────────────────

local function VRect(tag, x, y, w, h, color_pack)
    return VCmd(K_RECT, tag, x, y, w, h, color_pack, 0, "", 0, 0, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO)
end
local function VText(tag, x, y, w, h, style, text)
    return VCmd(K_TEXTBLOCK, tag, x, y, w, h, style.color, style.font_id, text, 0, 0, style.align, style.wrap, style.overflow, style.line_height)
end
local function VPushClip(x, y, w, h)
    return VCmd(K_PUSH_CLIP, "", x, y, w, h, NULL_PACK, 0, "", 0, 0, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO)
end
local function VPopClip(x, y, w, h)
    return VCmd(K_POP_CLIP, "", x, y, w, h, NULL_PACK, 0, "", 0, 0, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO)
end
local function VPushTx(tx, ty)
    return VCmd(K_PUSH_TX, "", 0, 0, 0, 0, NULL_PACK, 0, "", tx, ty, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO)
end
local function VPopTx(tx, ty)
    return VCmd(K_POP_TX, "", 0, 0, 0, 0, NULL_PACK, 0, "", tx, ty, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO)
end

function ui.push_clip_cmd(x, y, w, h)
    return VPushClip(x or 0, y or 0, w or 0, h or 0)
end

function ui.pop_clip_cmd(x, y, w, h)
    return VPopClip(x or 0, y or 0, w or 0, h or 0)
end

function ui.push_transform_cmd(tx, ty)
    return VPushTx(tx or 0, ty or 0)
end

function ui.pop_transform_cmd(tx, ty)
    return VPopTx(tx or 0, ty or 0)
end

function ui.append_fragment_cmds(out, x, y, fragment)
    local cmds = fragment.cmds
    if (x or 0) == 0 and (y or 0) == 0 then
        local n = #out
        for i = 1, #cmds do out[n + i] = cmds[i] end
    else
        out[#out + 1] = VPushTx(x or 0, y or 0)
        for i = 1, #cmds do out[#out + 1] = cmds[i] end
        out[#out + 1] = VPopTx(x or 0, y or 0)
    end
end

local function resolve_local_frame(node, outer)
    local m = ui.measure(node, exact_constraint_from_frame(outer))
    return Frame(outer.x, outer.y, m.used_w, m.used_h), m
end

-- ── Static UI node emit methods ─────────────────────────────

function T.UI.Rect:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    out[#out+1] = VRect(self.tag, frame.x, frame.y, frame.w, frame.h, self.fill)
end

function T.UI.Spacer:_emit() end

function T.UI.Text:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    local max_w = (self.style.wrap == TXT_NOWRAP and self.style.overflow == OV_VISIBLE) and INF or frame.w
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

-- ── Flex emit ───────────────────────────────────────────────

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

-- ── Compile / Fragment / Assemble (static UI) ───────────────

function ui.compile(node, a, b, c, d)
    stats.compile.calls = stats.compile.calls + 1
    local frame
    if type(a) == "number" and type(b) == "number" and c == nil then frame = Frame(0, 0, a, b)
    elseif type(a) == "number" and type(b) == "number" and type(c) == "number" and type(d) == "number" then frame = Frame(a, b, c, d)
    else frame = a end
    if frame == nil then error('uilib.compile: expected (node, frame) or (node, w, h) or (node, x, y, w, h)', 2) end
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
    if frame == nil then error('uilib.fragment', 2) end
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

-- ── Paint tree / runtime paint IR ───────────────────────────

local P_ZERO = T.Paint.ScalarLit(0)
local P_EMPTY_TEXT = T.Paint.TextLit("")
local P_NULL_COLOR = T.Paint.ColorPackLit(NULL_PACK)
local PCmd = T.Paint.Cmd
local PK_FILL, PK_STROKE, PK_LINE, PK_TEXT = T.Paint.FillRectCmd, T.Paint.StrokeRectCmd, T.Paint.LineCmd, T.Paint.TextCmd
local PK_PUSH_CLIP_CMD, PK_POP_CLIP_CMD = T.Paint.PushClipCmd, T.Paint.PopClipCmd
local PK_PUSH_TX_CMD, PK_POP_TX_CMD = T.Paint.PushTransformCmd, T.Paint.PopTransformCmd
local PMT = {}
do
    PMT.ScalarLit = getmetatable(P_ZERO)
    PMT.ScalarFromRef = getmetatable(T.Paint.ScalarFromRef(T.Runtime.NumRef("")))
    PMT.TextLit = getmetatable(P_EMPTY_TEXT)
    PMT.TextFromRef = getmetatable(T.Paint.TextFromRef(T.Runtime.TextRef("")))
    PMT.ColorPackLit = getmetatable(P_NULL_COLOR)
    PMT.ColorFromRef = getmetatable(T.Paint.ColorFromRef(T.Runtime.ColorRef("")))
    PMT.ColorPack = getmetatable(T.DS.ColorPack(0, 0, 0, 0))
end

local function PaintCommand(kind, tag, a, b, c, d, e, f, color, font_id, line_height, text_align, text_wrap, overflow, line_limit, text)
    return PCmd(kind, tag or "", a or P_ZERO, b or P_ZERO, c or P_ZERO, d or P_ZERO, e or P_ZERO, f or P_ZERO,
        color or P_NULL_COLOR, font_id or 0, line_height or LH_AUTO, text_align or TXT_START,
        text_wrap or TXT_NOWRAP, overflow or OV_VISIBLE, line_limit or UNLIMITED_LINES, text or P_EMPTY_TEXT)
end

function T.Paint.Group:_emit(out)
    for i = 1, #self.children do self.children[i]:_emit(out) end
end

function T.Paint.ClipRegion:_emit(out)
    out[#out+1] = PaintCommand(PK_PUSH_CLIP_CMD, "", self.x, self.y, self.w, self.h)
    self.child:_emit(out)
    out[#out+1] = PaintCommand(PK_POP_CLIP_CMD, "", self.x, self.y, self.w, self.h)
end

function T.Paint.Translate:_emit(out)
    out[#out+1] = PaintCommand(PK_PUSH_TX_CMD, "", self.tx, self.ty)
    self.child:_emit(out)
    out[#out+1] = PaintCommand(PK_POP_TX_CMD, "", self.tx, self.ty)
end

function T.Paint.FillRect:_emit(out)
    out[#out+1] = PaintCommand(PK_FILL, self.tag, self.x, self.y, self.w, self.h, nil, nil, self.color)
end

function T.Paint.StrokeRect:_emit(out)
    out[#out+1] = PaintCommand(PK_STROKE, self.tag, self.x, self.y, self.w, self.h, self.thickness, nil, self.color)
end

function T.Paint.Line:_emit(out)
    out[#out+1] = PaintCommand(PK_LINE, self.tag, self.x1, self.y1, self.x2, self.y2, self.thickness, nil, self.color)
end

function T.Paint.Text:_emit(out)
    out[#out+1] = PaintCommand(PK_TEXT, self.tag, self.x, self.y, self.w, self.h, nil, nil,
        self.color, self.font_id, self.line_height, self.align, self.wrap, self.overflow, self.line_limit, self.text)
end

function ui.compile_paint(node)
    stats.paint_compile.calls = stats.paint_compile.calls + 1
    local hit = paint_compile_cache[node]
    if hit then
        stats.paint_compile.hits = stats.paint_compile.hits + 1
        return hit
    end
    local out = {}
    node:_emit(out)
    paint_compile_cache[node] = out
    return out
end
ui.paint_compile = ui.compile_paint

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
    local phase = pointer_for_id(tag or "", hot or {})
    local mt = getmetatable(color_value)
    if mt == PMT.ColorPackLit then return pick(color_value.pack, phase) end
    local v = runtime_lookup(runtime and runtime.colors, color_value.ref.name, 0)
    if getmetatable(v) == PMT.ColorPack then return pick(v, phase) end
    if type(v) == "number" then return v end
    return 0
end

local function rgba8_to_float(rgba8)
    local a = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local b = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local g = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local r = (rgba8 % 256) / 255
    return r, g, b, a
end

local function backend_text_align(align)
    if align == TXT_CENTER then return "center" end; if align == TXT_END then return "right" end; if align == TXT_JUSTIFY then return "justify" end; return "left"
end

local function active_backend(opts)
    return (opts and opts.backend) or (ui.get_backend and ui.get_backend()) or nil
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
    local lh = resolve_line_height(line_height, font_id)
    local fh = raw_text_height(font_id)
    if fh > 0 then font:setLineHeight(lh / fh) end
    return old_lh
end

-- ── Static UI paint ─────────────────────────────────────────

function ui.paint(cmds, opts)
    opts = opts or {}
    local backend = active_backend(opts)
    if not backend then return end
    local hot = opts.hot or {}
    local tx, ty = 0, 0; local tx_stack, clip_stack = {}, {}
    for i = 1, #cmds do
        local c = cmds[i]; local k = c.kind
        if k == K_RECT then
            backend_set_color(backend, pick(c.color, pointer_for_id(c.htag, hot)))
            if backend.fill_rect then backend:fill_rect(c.x, c.y, c.w, c.h) end
        elseif k == K_TEXTBLOCK then
            local font = get_font(c.font_id); if font and backend.set_font then backend:set_font(font) end
            backend_set_color(backend, pick(c.color, pointer_for_id(c.htag, hot)))
            local old_lh = prepare_font_for_draw(font, c.font_id, c.line_height)
            if c.overflow ~= OV_VISIBLE then
                local ax, ay, nw, nh = intersect_clip(c.x + tx, c.y + ty, c.w, c.h, clip_stack[#clip_stack])
                if backend.push_clip then backend:push_clip(ax, ay, nw, nh) end
            end
            if c.text_wrap == TXT_NOWRAP and c.overflow == OV_VISIBLE then backend_draw_text(backend, c.text, c.x, c.y, nil, "left")
            else backend_draw_text(backend, c.text, c.x, c.y, math.max(1, c.w), backend_text_align(c.text_align)) end
            if c.overflow ~= OV_VISIBLE and backend.pop_clip then backend:pop_clip() end
            restore_font_line_height(font, old_lh)
        elseif k == K_PUSH_CLIP then
            local ax, ay, nw, nh = intersect_clip(c.x + tx, c.y + ty, c.w, c.h, clip_stack[#clip_stack])
            clip_stack[#clip_stack+1] = { ax, ay, nw, nh }
            if backend.push_clip then backend:push_clip(ax, ay, nw, nh) end
        elseif k == K_POP_CLIP then
            clip_stack[#clip_stack] = nil
            if backend.pop_clip then backend:pop_clip() end
        elseif k == K_PUSH_TX then
            tx_stack[#tx_stack+1] = { tx, ty }; tx, ty = tx + c.tx, ty + c.ty
            if backend.push_transform then backend:push_transform(c.tx, c.ty) end
        elseif k == K_POP_TX then
            if backend.pop_transform then backend:pop_transform() end
            local t = tx_stack[#tx_stack]; tx_stack[#tx_stack] = nil; tx, ty = t[1], t[2]
        end
    end
    if backend.set_color then backend:set_color(1, 1, 1, 1) end
end

-- ── Generic custom paint ────────────────────────────────────

function ui.paint_custom(cmds, runtime, opts)
    opts = opts or {}
    runtime = runtime or {}
    local backend = active_backend(opts)
    if not backend then return end
    local hot = opts.hot or {}
    local tx, ty = 0, 0; local tx_stack, clip_stack = {}, {}
    for i = 1, #cmds do
        local c = cmds[i]; local k = c.kind
        if k == PK_FILL then
            local x, y = resolve_paint_scalar(runtime, c.a), resolve_paint_scalar(runtime, c.b)
            local w, h = resolve_paint_scalar(runtime, c.c), resolve_paint_scalar(runtime, c.d)
            backend_set_color(backend, resolve_paint_color(runtime, c.color, c.tag, hot))
            if backend.fill_rect then backend:fill_rect(x, y, w, h) end
        elseif k == PK_STROKE then
            local x, y = resolve_paint_scalar(runtime, c.a), resolve_paint_scalar(runtime, c.b)
            local w, h = resolve_paint_scalar(runtime, c.c), resolve_paint_scalar(runtime, c.d)
            local thickness = resolve_paint_scalar(runtime, c.e)
            backend_set_color(backend, resolve_paint_color(runtime, c.color, c.tag, hot))
            if backend.stroke_rect then backend:stroke_rect(x, y, w, h, thickness) end
        elseif k == PK_LINE then
            local x1, y1 = resolve_paint_scalar(runtime, c.a), resolve_paint_scalar(runtime, c.b)
            local x2, y2 = resolve_paint_scalar(runtime, c.c), resolve_paint_scalar(runtime, c.d)
            local thickness = resolve_paint_scalar(runtime, c.e)
            backend_set_color(backend, resolve_paint_color(runtime, c.color, c.tag, hot))
            if backend.draw_line then backend:draw_line(x1, y1, x2, y2, thickness) end
        elseif k == PK_TEXT then
            local x, y = resolve_paint_scalar(runtime, c.a), resolve_paint_scalar(runtime, c.b)
            local w, h = resolve_paint_scalar(runtime, c.c), resolve_paint_scalar(runtime, c.d)
            local font = get_font(c.font_id); if font and backend.set_font then backend:set_font(font) end
            backend_set_color(backend, resolve_paint_color(runtime, c.color, c.tag, hot))
            local text = resolve_paint_text(runtime, c.text)
            local style = { font_id = c.font_id, line_height = c.line_height, align = c.text_align, wrap = c.text_wrap, overflow = c.overflow, line_limit = c.line_limit }
            local max_w = (c.text_wrap == TXT_NOWRAP and c.overflow == OV_VISIBLE) and INF or w
            local max_h = (c.overflow == OV_VISIBLE) and INF or h
            local shaped = shape_text(style, text, max_w, max_h)
            local old_lh = prepare_font_for_draw(font, c.font_id, c.line_height)
            if c.overflow ~= OV_VISIBLE then
                local ax, ay, nw, nh = intersect_clip(x + tx, y + ty, w, h, clip_stack[#clip_stack])
                if backend.push_clip then backend:push_clip(ax, ay, nw, nh) end
            end
            if c.text_wrap == TXT_NOWRAP and c.overflow == OV_VISIBLE then backend_draw_text(backend, shaped.text, x, y, nil, "left")
            else backend_draw_text(backend, shaped.text, x, y, math.max(1, w), backend_text_align(c.text_align)) end
            if c.overflow ~= OV_VISIBLE and backend.pop_clip then backend:pop_clip() end
            restore_font_line_height(font, old_lh)
        elseif k == PK_PUSH_CLIP_CMD then
            local x, y = resolve_paint_scalar(runtime, c.a), resolve_paint_scalar(runtime, c.b)
            local w, h = resolve_paint_scalar(runtime, c.c), resolve_paint_scalar(runtime, c.d)
            local ax, ay, nw, nh = intersect_clip(x + tx, y + ty, w, h, clip_stack[#clip_stack])
            clip_stack[#clip_stack+1] = { ax, ay, nw, nh }
            if backend.push_clip then backend:push_clip(ax, ay, nw, nh) end
        elseif k == PK_POP_CLIP_CMD then
            clip_stack[#clip_stack] = nil
            if backend.pop_clip then backend:pop_clip() end
        elseif k == PK_PUSH_TX_CMD then
            local dx, dy = resolve_paint_scalar(runtime, c.a), resolve_paint_scalar(runtime, c.b)
            tx_stack[#tx_stack+1] = { tx, ty }; tx, ty = tx + dx, ty + dy
            if backend.push_transform then backend:push_transform(dx, dy) end
        elseif k == PK_POP_TX_CMD then
            if backend.pop_transform then backend:pop_transform() end
            local t = tx_stack[#tx_stack]; tx_stack[#tx_stack] = nil; tx, ty = t[1], t[2]
        end
    end
    if backend.set_color then backend:set_color(1, 1, 1, 1) end
end
ui.paint_runtime = ui.paint_custom

-- ── Hit test (static UI) ────────────────────────────────────

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

-- ── Node methods / diagnostics ──────────────────────────────

function T.UI.Node:measure(constraint) return ui.measure(self, constraint) end
function T.UI.Node:compile(frame) return ui.compile(self, frame) end
function T.UI.Node:emit_into(out, frame) return self:_emit(out, frame) end
function T.View.Plan:cmds() return ui.assemble(self) end
function T.Paint.Node:compile() return ui.compile_paint(self) end
function T.Paint.Node:emit_into(out) return self:_emit(out) end

end -- function(ui, T, S, ...)
