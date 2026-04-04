-- uilib_impl.lua
--
-- Implementation for the redesigned UI library.
--
-- This module installs methods on the ASDL types from uilib_asdl.lua and
-- provides the runtime/compiler helpers:
--
--   UI.Node --measure--> Facts.Measure
--   UI.Node --compile--> View.Cmd[]
--
-- There is intentionally no recursive Layout.Node layer.

local schema = require("uilib_asdl")
local T = schema.T

local ui = { T = T }

-- ══════════════════════════════════════════════════════════════
--  SINGLETONS / CONSTRUCTORS / METATABLES
-- ══════════════════════════════════════════════════════════════

-- UI singletons
local AXIS_ROW         = T.UI.AxisRow
local AXIS_ROW_REV     = T.UI.AxisRowReverse
local AXIS_COL         = T.UI.AxisCol
local AXIS_COL_REV     = T.UI.AxisColReverse

local WRAP_NO          = T.UI.WrapNoWrap
local WRAP_YES         = T.UI.WrapWrap
local WRAP_REV         = T.UI.WrapWrapReverse

local MAIN_START       = T.UI.MainStart
local MAIN_END         = T.UI.MainEnd
local MAIN_CENTER      = T.UI.MainCenter
local MAIN_BETWEEN     = T.UI.MainSpaceBetween
local MAIN_AROUND      = T.UI.MainSpaceAround
local MAIN_EVENLY      = T.UI.MainSpaceEvenly

local CROSS_AUTO       = T.UI.CrossAuto
local CROSS_START      = T.UI.CrossStart
local CROSS_END        = T.UI.CrossEnd
local CROSS_CENTER     = T.UI.CrossCenter
local CROSS_STRETCH    = T.UI.CrossStretch
local CROSS_BASELINE   = T.UI.CrossBaseline

local CONTENT_START    = T.UI.ContentStart
local CONTENT_END      = T.UI.ContentEnd
local CONTENT_CENTER   = T.UI.ContentCenter
local CONTENT_STRETCH  = T.UI.ContentStretch
local CONTENT_BETWEEN  = T.UI.ContentSpaceBetween
local CONTENT_AROUND   = T.UI.ContentSpaceAround
local CONTENT_EVENLY   = T.UI.ContentSpaceEvenly

local SIZE_AUTO        = T.UI.SizeAuto
local SIZE_CONTENT     = T.UI.SizeContent
local BASIS_AUTO       = T.UI.BasisAuto
local BASIS_CONTENT    = T.UI.BasisContent
local NO_MIN           = T.UI.NoMin
local NO_MAX           = T.UI.NoMax

local TXT_NOWRAP       = T.UI.TextNoWrap
local TXT_WORDWRAP     = T.UI.TextWordWrap
local TXT_CHARWRAP     = T.UI.TextCharWrap

local TXT_START        = T.UI.TextStart
local TXT_CENTER       = T.UI.TextCenter
local TXT_END          = T.UI.TextEnd
local TXT_JUSTIFY      = T.UI.TextJustify

local OV_VISIBLE       = T.UI.OverflowVisible
local OV_CLIP          = T.UI.OverflowClip
local OV_ELLIPSIS      = T.UI.OverflowEllipsis

local LH_AUTO          = T.UI.LineHeightAuto
local UNLIMITED_LINES  = T.UI.UnlimitedLines

-- Facts singletons / ctors
local SPAN_UNBOUNDED   = T.Facts.SpanUnconstrained
local SpanExact        = T.Facts.SpanExact
local SpanAtMost       = T.Facts.SpanAtMost
local BASELINE_NONE    = T.Facts.NoBaseline
local BaselinePx       = T.Facts.BaselinePx
local Constraint       = T.Facts.Constraint
local Frame            = T.Facts.Frame
local Intrinsic        = T.Facts.Intrinsic
local Measure          = T.Facts.Measure

-- View singletons / ctors
local K_RECT           = T.View.Rect
local K_TEXTBLOCK      = T.View.TextBlock
local K_PUSH_CLIP      = T.View.PushClip
local K_POP_CLIP       = T.View.PopClip
local K_PUSH_TX        = T.View.PushTransform
local K_POP_TX         = T.View.PopTransform
local Cmd              = T.View.Cmd
local Fragment         = T.View.Fragment
local PK_PLACE         = T.View.PlaceFragment
local PK_PUSH_CLIP     = T.View.PushClipPlan
local PK_POP_CLIP      = T.View.PopClipPlan
local PK_PUSH_TX       = T.View.PushTransformPlan
local PK_POP_TX        = T.View.PopTransformPlan
local PlanOp           = T.View.PlanOp
local Plan             = T.View.Plan

-- Constructors
local Insets           = T.UI.Insets
local Box              = T.UI.Box
local TextStyle        = T.UI.TextStyle
local FlexItem         = T.UI.FlexItem

-- Metatables for product variants
local mtSizePx         = getmetatable(T.UI.SizePx(0))
local mtSizePercent    = getmetatable(T.UI.SizePercent(0))
local mtBasisPx        = getmetatable(T.UI.BasisPx(0))
local mtBasisPercent   = getmetatable(T.UI.BasisPercent(0))
local mtLineHeightPx   = getmetatable(T.UI.LineHeightPx(0))
local mtLineHeightScl  = getmetatable(T.UI.LineHeightScale(1))
local mtMaxLines       = getmetatable(T.UI.MaxLines(1))
local mtSpanExact      = getmetatable(SpanExact(0))
local mtSpanAtMost     = getmetatable(SpanAtMost(0))
local mtBaselinePx     = getmetatable(BaselinePx(0))
local mtChild          = getmetatable(FlexItem(T.UI.Spacer(Box(SIZE_AUTO, SIZE_AUTO, NO_MIN, NO_MIN, NO_MAX, NO_MAX)), 0, 1, BASIS_AUTO, CROSS_AUTO, Insets(0,0,0,0)))

-- Defaults
local ZERO_INSETS      = Insets(0, 0, 0, 0)
local AUTO_BOX         = Box(SIZE_AUTO, SIZE_AUTO, NO_MIN, NO_MIN, NO_MAX, NO_MAX)
local DEFAULT_TEXTSTYLE = TextStyle(0, 0xffffffff, LH_AUTO, TXT_START, TXT_NOWRAP, OV_VISIBLE, UNLIMITED_LINES)

-- ══════════════════════════════════════════════════════════════
--  STATS / CACHES
-- ══════════════════════════════════════════════════════════════

local measure_cache = setmetatable({}, { __mode = "k" })   -- [node][constraint] = Facts.Measure
local compile_cache = setmetatable({}, { __mode = "k" })   -- [node][frame] = {Cmd*}
local assemble_cache = setmetatable({}, { __mode = "k" })  -- [plan] = {Cmd*}
local stats = {
    measure = { name = "uilib.measure", calls = 0, hits = 0 },
    compile = { name = "uilib.compile", calls = 0, hits = 0 },
    assemble = { name = "uilib.assemble", calls = 0, hits = 0 },
}

-- ══════════════════════════════════════════════════════════════
--  FONT / TEXT HELPERS
-- ══════════════════════════════════════════════════════════════

local fonts = {}

function ui.set_font(id, font)
    fonts[id] = font
end

local function get_font(font_id)
    local f = fonts[font_id]
    if f then return f end
    if love and love.graphics and love.graphics.getFont then
        return love.graphics.getFont()
    end
    return nil
end

local function raw_text_width(font_id, text)
    local f = get_font(font_id)
    if f and f.getWidth then return f:getWidth(text) end
    return #text * 8
end

local function raw_text_height(font_id)
    local f = get_font(font_id)
    if f and f.getHeight then return f:getHeight() end
    return 14
end

local function raw_text_baseline(font_id)
    local f = get_font(font_id)
    if f then
        if f.getBaseline then return f:getBaseline() end
        if f.getAscent then return f:getAscent() end
        if f.getHeight then return f:getHeight() * 0.8 end
    end
    return raw_text_height(font_id) * 0.8
end

local function resolve_line_height(line_height, font_id)
    local fh = raw_text_height(font_id)
    if line_height == LH_AUTO then return fh end
    local mt = getmetatable(line_height)
    if mt == mtLineHeightPx then return line_height.px end
    if mt == mtLineHeightScl then return fh * line_height.scale end
    return fh
end

local function split_lines(text)
    local out = {}
    if text == "" then return { "" } end
    local start = 1
    while true do
        local i = string.find(text, "\n", start, true)
        if not i then
            out[#out + 1] = string.sub(text, start)
            break
        end
        out[#out + 1] = string.sub(text, start, i - 1)
        start = i + 1
    end
    return out
end

local function split_words(s)
    local out = {}
    local i, n = 1, #s
    while i <= n do
        while i <= n and string.sub(s, i, i):match("%s") do i = i + 1 end
        if i > n then break end
        local j = i
        while j <= n and not string.sub(s, j, j):match("%s") do j = j + 1 end
        out[#out + 1] = string.sub(s, i, j - 1)
        i = j
    end
    if #out == 0 then out[1] = "" end
    return out
end

local function split_chars(s)
    local out = {}
    for i = 1, #s do out[i] = string.sub(s, i, i) end
    if #out == 0 then out[1] = "" end
    return out
end

local function truncate_with_ellipsis(font_id, text, max_w)
    local ell = "…"
    if raw_text_width(font_id, text) <= max_w then return text end
    if raw_text_width(font_id, ell) > max_w then return "" end
    local lo, hi, best = 0, #text, ""
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local s = string.sub(text, 1, mid) .. ell
        if raw_text_width(font_id, s) <= max_w then
            best = s
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return best
end

local function wrap_paragraph(font_id, para, max_w, mode)
    if max_w == math.huge then return { para } end
    if para == "" then return { "" } end

    local tokens = (mode == TXT_CHARWRAP) and split_chars(para) or split_words(para)
    local out, line = {}, ""

    for i = 1, #tokens do
        local t = tokens[i]
        local candidate = (line == "") and t or (mode == TXT_CHARWRAP and (line .. t) or (line .. " " .. t))
        if raw_text_width(font_id, candidate) <= max_w then
            line = candidate
        else
            if line ~= "" then out[#out + 1] = line end
            if raw_text_width(font_id, t) <= max_w then
                line = t
            else
                -- token itself is too wide: force char-level breaking
                local chars = split_chars(t)
                local frag = ""
                for j = 1, #chars do
                    local c = chars[j]
                    local cand = frag .. c
                    if frag == "" or raw_text_width(font_id, cand) <= max_w then
                        frag = cand
                    else
                        out[#out + 1] = frag
                        frag = c
                    end
                end
                line = frag
            end
        end
    end
    if line ~= "" then out[#out + 1] = line end
    if #out == 0 then out[1] = "" end
    return out
end

local function text_intrinsic_widths(style, text)
    local paragraphs = split_lines(text)
    local max_w = 0
    local min_w = 0

    for i = 1, #paragraphs do
        local para = paragraphs[i]
        local pw = raw_text_width(style.font_id, para)
        if pw > max_w then max_w = pw end

        local local_min
        if style.wrap == TXT_NOWRAP then
            local_min = pw
        elseif style.wrap == TXT_WORDWRAP then
            local_min = 0
            local words = split_words(para)
            for j = 1, #words do
                local w = raw_text_width(style.font_id, words[j])
                if w > local_min then local_min = w end
            end
        else
            local_min = 0
            local chars = split_chars(para)
            for j = 1, #chars do
                local w = raw_text_width(style.font_id, chars[j])
                if w > local_min then local_min = w end
            end
        end
        if local_min > min_w then min_w = local_min end
    end

    return min_w, max_w
end

local shape_cache = setmetatable({}, { __mode = "k" })

local function shape_text(style, text, max_w, max_h)
    max_w = max_w or math.huge
    max_h = max_h or math.huge

    local line_h = resolve_line_height(style.line_height, style.font_id)
    local baseline = raw_text_baseline(style.font_id)
    local lines = {}
    local paragraphs = split_lines(text)

    if style.wrap == TXT_NOWRAP or max_w == math.huge then
        for i = 1, #paragraphs do lines[#lines + 1] = paragraphs[i] end
    else
        for i = 1, #paragraphs do
            local wrapped = wrap_paragraph(style.font_id, paragraphs[i], max_w, style.wrap)
            for j = 1, #wrapped do lines[#lines + 1] = wrapped[j] end
        end
    end

    local explicit_limit = math.huge
    local mt_ll = getmetatable(style.line_limit)
    if mt_ll == mtMaxLines then explicit_limit = style.line_limit.count end

    local height_limit = math.huge
    if max_h ~= math.huge and line_h > 0 and style.overflow ~= OV_VISIBLE then
        height_limit = math.max(0, math.floor(max_h / line_h))
    end

    local effective_limit = math.min(explicit_limit, height_limit)
    local limited = false
    if effective_limit < math.huge and #lines > effective_limit then
        limited = true
        while #lines > effective_limit do lines[#lines] = nil end
    end

    if max_w ~= math.huge then
        if style.wrap == TXT_NOWRAP then
            if #lines > 0 and style.overflow == OV_ELLIPSIS then
                lines[1] = truncate_with_ellipsis(style.font_id, lines[1] or "", max_w)
            elseif #lines > 0 and style.overflow == OV_CLIP then
                local s = lines[1] or ""
                while #s > 0 and raw_text_width(style.font_id, s) > max_w do
                    s = string.sub(s, 1, #s - 1)
                end
                lines[1] = s
            end
        elseif limited and style.overflow == OV_ELLIPSIS and #lines > 0 then
            lines[#lines] = truncate_with_ellipsis(style.font_id, lines[#lines], max_w)
        end
    end

    local used_w = 0
    for i = 1, #lines do
        local w = raw_text_width(style.font_id, lines[i])
        if w > used_w then used_w = w end
    end
    if max_w ~= math.huge and style.wrap ~= TXT_NOWRAP then
        used_w = math.min(used_w, max_w)
    end

    local used_h = #lines * line_h
    return {
        lines = lines,
        text = table.concat(lines, "\n"),
        used_w = used_w,
        used_h = used_h,
        line_h = line_h,
        baseline = baseline,
        line_count = #lines,
    }
end

local function shaped_text(node, max_w, max_h)
    max_w = max_w or math.huge
    max_h = max_h or math.huge
    local by_node = shape_cache[node]
    if not by_node then
        by_node = {}
        shape_cache[node] = by_node
    end
    local by_w = by_node[max_w]
    if not by_w then
        by_w = {}
        by_node[max_w] = by_w
    end
    local hit = by_w[max_h]
    if hit then return hit end
    local shaped = shape_text(node.style, node.text, max_w, max_h)
    by_w[max_h] = shaped
    return shaped
end

-- ══════════════════════════════════════════════════════════════
--  POLICY / NUMERIC HELPERS
-- ══════════════════════════════════════════════════════════════

local INF = math.huge

local function clamp(v, lo, hi)
    if lo ~= nil and v < lo then v = lo end
    if hi ~= nil and v > hi then v = hi end
    return v
end

local function max_of(a, b) return (a > b) and a or b end

local function span_available(span)
    if span == SPAN_UNBOUNDED then return INF, false end
    local mt = getmetatable(span)
    if mt == mtSpanExact then return span.px, true end
    if mt == mtSpanAtMost then return span.px, false end
    return INF, false
end

local function sub_span(span, delta)
    if delta <= 0 then return span end
    if span == SPAN_UNBOUNDED then return span end
    local mt = getmetatable(span)
    local px = math.max(0, span.px - delta)
    if mt == mtSpanExact then return SpanExact(px) end
    return SpanAtMost(px)
end

local function box_min_value(minv)
    if minv == NO_MIN then return 0 end
    return minv.px
end

local function box_max_value(maxv)
    if maxv == NO_MAX then return INF end
    return maxv.px
end

local function resolve_size_value(spec, available, content_value)
    if spec == SIZE_AUTO or spec == SIZE_CONTENT then return content_value end
    local mt = getmetatable(spec)
    if mt == mtSizePx then return spec.px end
    if mt == mtSizePercent then
        if available ~= INF then return available * spec.ratio end
        return content_value
    end
    return content_value
end

local function resolve_basis_value(spec, available, content_value)
    if spec == BASIS_AUTO or spec == BASIS_CONTENT then return content_value end
    local mt = getmetatable(spec)
    if mt == mtBasisPx then return spec.px end
    if mt == mtBasisPercent then
        if available ~= INF then return available * spec.ratio end
        return content_value
    end
    return content_value
end

local function baseline_num(b)
    if b == BASELINE_NONE or b == nil then return nil end
    if getmetatable(b) == mtBaselinePx then return b.px end
    return nil
end

local function make_baseline(px)
    if not px then return BASELINE_NONE end
    return BaselinePx(px)
end

local function is_row_axis(axis)
    return axis == AXIS_ROW or axis == AXIS_ROW_REV
end

local function is_reverse_axis(axis)
    return axis == AXIS_ROW_REV or axis == AXIS_COL_REV
end

local function is_wrap_reverse(wrap)
    return wrap == WRAP_REV
end

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

local function main_size_of(measure, axis)
    return is_row_axis(axis) and measure.used_w or measure.used_h
end

local function cross_size_of(measure, axis)
    return is_row_axis(axis) and measure.used_h or measure.used_w
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

local function exact_or_atmost(px, exact)
    if px == INF then return SPAN_UNBOUNDED end
    if exact then return SpanExact(px) end
    return SpanAtMost(px)
end

local function box_content_constraint(box, outer)
    local avail_w = span_available(outer.w)
    local avail_h = span_available(outer.h)
    local aw = avail_w
    local ah = avail_h
    local exact_w = false
    local exact_h = false

    local mtw = getmetatable(box.w)
    if mtw == mtSizePx then aw, exact_w = box.w.px, true
    elseif mtw == mtSizePercent and aw ~= INF then aw, exact_w = aw * box.w.ratio, true end

    local mth = getmetatable(box.h)
    if mth == mtSizePx then ah, exact_h = box.h.px, true
    elseif mth == mtSizePercent and ah ~= INF then ah, exact_h = ah * box.h.ratio, true end

    return Constraint(exact_or_atmost(aw, exact_w), exact_or_atmost(ah, exact_h))
end

local function apply_box_measure(box, outer, raw)
    local aw, outer_exact_w = span_available(outer.w)
    local ah, outer_exact_h = span_available(outer.h)

    local min_w = box_min_value(box.min_w)
    local min_h = box_min_value(box.min_h)
    local max_w = box_max_value(box.max_w)
    local max_h = box_max_value(box.max_h)

    local used_w
    if outer_exact_w and (box.w == SIZE_AUTO or box.w == SIZE_CONTENT or getmetatable(box.w) == mtSizePercent) then
        used_w = aw
    else
        used_w = resolve_size_value(box.w, aw, raw.used_w)
    end

    local used_h
    if outer_exact_h and (box.h == SIZE_AUTO or box.h == SIZE_CONTENT or getmetatable(box.h) == mtSizePercent) then
        used_h = ah
    else
        used_h = resolve_size_value(box.h, ah, raw.used_h)
    end

    local intr_min_w = raw.min_w
    local intr_min_h = raw.min_h
    local intr_max_w = raw.max_w
    local intr_max_h = raw.max_h

    local mtw = getmetatable(box.w)
    if mtw == mtSizePx then intr_min_w, intr_max_w = box.w.px, box.w.px
    elseif mtw == mtSizePercent and aw ~= INF then intr_min_w, intr_max_w = aw * box.w.ratio, aw * box.w.ratio end

    local mth = getmetatable(box.h)
    if mth == mtSizePx then intr_min_h, intr_max_h = box.h.px, box.h.px
    elseif mth == mtSizePercent and ah ~= INF then intr_min_h, intr_max_h = ah * box.h.ratio, ah * box.h.ratio end

    intr_min_w = clamp(intr_min_w, min_w, max_w)
    intr_min_h = clamp(intr_min_h, min_h, max_h)
    intr_max_w = clamp(intr_max_w, min_w, max_w)
    intr_max_h = clamp(intr_max_h, min_h, max_h)
    used_w = clamp(used_w, min_w, max_w)
    used_h = clamp(used_h, min_h, max_h)

    if aw ~= INF then used_w = math.min(used_w, aw) end
    if ah ~= INF then used_h = math.min(used_h, ah) end

    return Measure(
        outer,
        Intrinsic(intr_min_w, intr_min_h, intr_max_w, intr_max_h, raw.baseline or BASELINE_NONE),
        used_w,
        used_h,
        raw.baseline or BASELINE_NONE)
end

local function available_constraint_from_frame(frame)
    return Constraint(SpanAtMost(frame.w), SpanAtMost(frame.h))
end

local function exact_constraint_from_frame(frame)
    return Constraint(SpanExact(frame.w), SpanExact(frame.h))
end

-- ══════════════════════════════════════════════════════════════
--  CONVENIENCE API (typed constructors)
-- ══════════════════════════════════════════════════════════════

ui.AUTO = SIZE_AUTO
ui.CONTENT = SIZE_CONTENT

function ui.px(n) return T.UI.SizePx(n) end
function ui.percent(r) return T.UI.SizePercent(r) end
function ui.basis_px(n) return T.UI.BasisPx(n) end
function ui.basis_percent(r) return T.UI.BasisPercent(r) end
function ui.basis_auto() return BASIS_AUTO end
function ui.basis_content() return BASIS_CONTENT end
function ui.min_px(n) return T.UI.MinPx(n) end
function ui.max_px(n) return T.UI.MaxPx(n) end
function ui.no_min() return NO_MIN end
function ui.no_max() return NO_MAX end
function ui.line_height_px(n) return T.UI.LineHeightPx(n) end
function ui.line_height_scale(s) return T.UI.LineHeightScale(s) end
function ui.max_lines(n) return T.UI.MaxLines(n) end
function ui.insets(l, t, r, b) return Insets(l or 0, t or 0, r or 0, b or 0) end
function ui.margin(l, t, r, b) return Insets(l or 0, t or 0, r or 0, b or 0) end
function ui.frame(x, y, w, h) return Frame(x, y, w, h) end
function ui.constraint(w, h) return Constraint(w or SPAN_UNBOUNDED, h or SPAN_UNBOUNDED) end
function ui.exact(n) return SpanExact(n) end
function ui.at_most(n) return SpanAtMost(n) end

function ui.box(opts)
    if opts == nil then return AUTO_BOX end
    if type(opts) ~= "table" then return opts end
    return Box(
        opts.w or SIZE_AUTO,
        opts.h or SIZE_AUTO,
        opts.min_w or NO_MIN,
        opts.min_h or NO_MIN,
        opts.max_w or NO_MAX,
        opts.max_h or NO_MAX)
end

function ui.text_style(opts)
    opts = opts or {}
    return TextStyle(
        opts.font_id or 0,
        opts.rgba8 or 0xffffffff,
        opts.line_height or LH_AUTO,
        opts.align or TXT_START,
        opts.wrap or TXT_NOWRAP,
        opts.overflow or OV_VISIBLE,
        opts.line_limit or UNLIMITED_LINES)
end

function ui.item(node, opts)
    opts = opts or {}
    return FlexItem(
        node,
        opts.grow or 0,
        opts.shrink == nil and 1 or opts.shrink,
        opts.basis or BASIS_AUTO,
        opts.align or CROSS_AUTO,
        opts.margin or ZERO_INSETS)
end

function ui.grow(factor, node, opts)
    opts = opts or {}
    opts.grow = factor
    if opts.shrink == nil then opts.shrink = 1 end
    return ui.item(node, opts)
end

local function ensure_child(x)
    if getmetatable(x) == mtChild then return x end
    return ui.item(x)
end

local function wrap_children(xs)
    local out = {}
    for i = 1, #xs do out[i] = ensure_child(xs[i]) end
    return out
end

function ui.row(gap, children, opts)
    opts = opts or {}
    return T.UI.Flex(
        AXIS_ROW,
        opts.wrap or WRAP_NO,
        gap or 0,
        opts.gap_cross or 0,
        opts.justify or MAIN_START,
        opts.align or CROSS_STRETCH,
        opts.align_content or CONTENT_START,
        ui.box(opts.box),
        wrap_children(children))
end

function ui.col(gap, children, opts)
    opts = opts or {}
    return T.UI.Flex(
        AXIS_COL,
        opts.wrap or WRAP_NO,
        gap or 0,
        opts.gap_cross or 0,
        opts.justify or MAIN_START,
        opts.align or CROSS_STRETCH,
        opts.align_content or CONTENT_START,
        ui.box(opts.box),
        wrap_children(children))
end

function ui.flex(opts)
    opts = opts or {}
    return T.UI.Flex(
        opts.axis or AXIS_ROW,
        opts.wrap or WRAP_NO,
        opts.gap_main or 0,
        opts.gap_cross or 0,
        opts.justify or MAIN_START,
        opts.align_items or CROSS_STRETCH,
        opts.align_content or CONTENT_START,
        ui.box(opts.box),
        wrap_children(opts.children or {}))
end

function ui.pad(insets, child, box)
    return T.UI.Pad(insets or ZERO_INSETS, box or AUTO_BOX, child)
end

function ui.stack(children, box)
    return T.UI.Stack(box or AUTO_BOX, children or {})
end

function ui.clip(child, box)
    return T.UI.Clip(box or AUTO_BOX, child)
end

function ui.transform(tx, ty, child, box)
    return T.UI.Transform(tx or 0, ty or 0, box or AUTO_BOX, child)
end

function ui.sized(box, child)
    return T.UI.Sized(box or AUTO_BOX, child)
end

function ui.rect(tag, rgba8, box)
    return T.UI.Rect(tag or "", box or AUTO_BOX, rgba8 or 0xffffffff)
end

function ui.text(tag, text, style, box)
    return T.UI.Text(tag or "", box or AUTO_BOX, style or DEFAULT_TEXTSTYLE, text or "")
end

function ui.spacer(box)
    return T.UI.Spacer(box or AUTO_BOX)
end

function ui.plan(ops)
    return Plan(ops or {})
end

function ui.place_fragment(x, y, fragment)
    return PlanOp(PK_PLACE, x or 0, y or 0, 0, 0, 0, 0, fragment)
end

function ui.push_clip_plan(x, y, w, h)
    return PlanOp(PK_PUSH_CLIP, x or 0, y or 0, w or 0, h or 0, 0, 0, nil)
end

function ui.pop_clip_plan(x, y, w, h)
    return PlanOp(PK_POP_CLIP, x or 0, y or 0, w or 0, h or 0, 0, 0, nil)
end

function ui.push_transform_plan(tx, ty)
    return PlanOp(PK_PUSH_TX, 0, 0, 0, 0, tx or 0, ty or 0, nil)
end

function ui.pop_transform_plan(tx, ty)
    return PlanOp(PK_POP_TX, 0, 0, 0, 0, tx or 0, ty or 0, nil)
end

ui.AXIS_ROW = AXIS_ROW
ui.AXIS_ROW_REVERSE = AXIS_ROW_REV
ui.AXIS_COL = AXIS_COL
ui.AXIS_COL_REVERSE = AXIS_COL_REV
ui.WRAP_NO = WRAP_NO
ui.WRAP = WRAP_YES
ui.WRAP_REVERSE = WRAP_REV
ui.MAIN_START = MAIN_START
ui.MAIN_END = MAIN_END
ui.MAIN_CENTER = MAIN_CENTER
ui.MAIN_SPACE_BETWEEN = MAIN_BETWEEN
ui.MAIN_SPACE_AROUND = MAIN_AROUND
ui.MAIN_SPACE_EVENLY = MAIN_EVENLY
ui.CROSS_AUTO = CROSS_AUTO
ui.CROSS_START = CROSS_START
ui.CROSS_END = CROSS_END
ui.CROSS_CENTER = CROSS_CENTER
ui.CROSS_STRETCH = CROSS_STRETCH
ui.CROSS_BASELINE = CROSS_BASELINE
ui.CONTENT_START = CONTENT_START
ui.CONTENT_END = CONTENT_END
ui.CONTENT_CENTER = CONTENT_CENTER
ui.CONTENT_STRETCH = CONTENT_STRETCH
ui.CONTENT_SPACE_BETWEEN = CONTENT_BETWEEN
ui.CONTENT_SPACE_AROUND = CONTENT_AROUND
ui.CONTENT_SPACE_EVENLY = CONTENT_EVENLY
ui.TEXT_NOWRAP = TXT_NOWRAP
ui.TEXT_WORDWRAP = TXT_WORDWRAP
ui.TEXT_CHARWRAP = TXT_CHARWRAP
ui.TEXT_START = TXT_START
ui.TEXT_CENTER = TXT_CENTER
ui.TEXT_END = TXT_END
ui.TEXT_JUSTIFY = TXT_JUSTIFY
ui.OVERFLOW_VISIBLE = OV_VISIBLE
ui.OVERFLOW_CLIP = OV_CLIP
ui.OVERFLOW_ELLIPSIS = OV_ELLIPSIS
ui.LINEHEIGHT_AUTO = LH_AUTO
ui.UNLIMITED_LINES = UNLIMITED_LINES

-- ══════════════════════════════════════════════════════════════
--  MEASUREMENT BOUNDARY
-- ══════════════════════════════════════════════════════════════

local function measure_child(node, constraint)
    return ui.measure(node, constraint)
end

local function raw_measure_zero()
    return { min_w = 0, min_h = 0, max_w = 0, max_h = 0, used_w = 0, used_h = 0, baseline = BASELINE_NONE }
end

local function raw_from_child_measure(child)
    return {
        min_w = child.intrinsic.min_w,
        min_h = child.intrinsic.min_h,
        max_w = child.intrinsic.max_w,
        max_h = child.intrinsic.max_h,
        used_w = child.used_w,
        used_h = child.used_h,
        baseline = child.baseline,
    }
end

local function passthrough_measure(box, child, constraint)
    local inner = box_content_constraint(box, constraint)
    local m = measure_child(child, inner)
    return apply_box_measure(box, constraint, raw_from_child_measure(m))
end

function T.UI.Rect:_measure_uncached(constraint)
    local raw = raw_measure_zero()
    return apply_box_measure(self.box, constraint, raw)
end

function T.UI.Spacer:_measure_uncached(constraint)
    local raw = raw_measure_zero()
    return apply_box_measure(self.box, constraint, raw)
end

function T.UI.Text:_measure_uncached(constraint)
    local inner = box_content_constraint(self.box, constraint)
    local max_w = span_available(inner.w)
    local max_h = span_available(inner.h)
    local shape = shaped_text(self, max_w, max_h)
    local min_w, max_intr_w = text_intrinsic_widths(self.style, self.text)
    local raw = {
        min_w = min_w,
        min_h = resolve_line_height(self.style.line_height, self.style.font_id),
        max_w = max_intr_w,
        max_h = shape.used_h,
        used_w = shape.used_w,
        used_h = shape.used_h,
        baseline = make_baseline(shape.baseline),
    }
    return apply_box_measure(self.box, constraint, raw)
end

function T.UI.Sized:_measure_uncached(constraint)
    return passthrough_measure(self.box, self.child, constraint)
end

function T.UI.Transform:_measure_uncached(constraint)
    return passthrough_measure(self.box, self.child, constraint)
end

function T.UI.Clip:_measure_uncached(constraint)
    return passthrough_measure(self.box, self.child, constraint)
end

function T.UI.Pad:_measure_uncached(constraint)
    local inner = box_content_constraint(self.box, constraint)
    inner = Constraint(sub_span(inner.w, self.insets.l + self.insets.r), sub_span(inner.h, self.insets.t + self.insets.b))
    local child = measure_child(self.child, inner)
    local raw = {
        min_w = child.intrinsic.min_w + self.insets.l + self.insets.r,
        min_h = child.intrinsic.min_h + self.insets.t + self.insets.b,
        max_w = child.intrinsic.max_w + self.insets.l + self.insets.r,
        max_h = child.intrinsic.max_h + self.insets.t + self.insets.b,
        used_w = child.used_w + self.insets.l + self.insets.r,
        used_h = child.used_h + self.insets.t + self.insets.b,
        baseline = child.baseline,
    }
    return apply_box_measure(self.box, constraint, raw)
end

function T.UI.Stack:_measure_uncached(constraint)
    local inner = box_content_constraint(self.box, constraint)
    local raw = raw_measure_zero()
    raw.max_w, raw.max_h = 0, 0
    for i = 1, #self.children do
        local m = measure_child(self.children[i], inner)
        raw.min_w = max_of(raw.min_w, m.intrinsic.min_w)
        raw.min_h = max_of(raw.min_h, m.intrinsic.min_h)
        raw.max_w = max_of(raw.max_w, m.intrinsic.max_w)
        raw.max_h = max_of(raw.max_h, m.intrinsic.max_h)
        raw.used_w = max_of(raw.used_w, m.used_w)
        raw.used_h = max_of(raw.used_h, m.used_h)
    end
    return apply_box_measure(self.box, constraint, raw)
end

local function flex_collect_infos(node, constraint)
    local axis = node.axis
    local avail_w = span_available(constraint.w)
    local avail_h = span_available(constraint.h)
    local avail_main = is_row_axis(axis) and avail_w or avail_h
    local avail_cross = is_row_axis(axis) and avail_h or avail_w
    local infos = {}

    for i = 1, #node.children do
        local item = node.children[i]
        local m = measure_child(item.node, constraint)
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
    return infos, avail_main, avail_cross
end

local function distribute_line(infos, indices, avail_main, gap)
    local n = #indices
    local sizes, frozen = {}, {}
    for i = 1, n do
        local idx = indices[i]
        sizes[idx] = infos[idx].base
    end

    if avail_main == INF then return sizes end

    while true do
        local used = gap * math.max(0, n - 1)
        local free, weight = 0, 0

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
        free = avail_main - used
        if math.abs(free) < 1e-6 then break end

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
                if not frozen[idx] and infos[idx].item.shrink > 0 then
                    weight = weight + infos[idx].item.shrink * infos[idx].base
                end
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
                    if inf.item.grow > 0 then
                        target = inf.base + free * (inf.item.grow / weight)
                    else
                        target = inf.base
                    end
                else
                    local sw = inf.item.shrink * inf.base
                    if sw > 0 then
                        target = inf.base + free * (sw / weight)
                    else
                        target = inf.base
                    end
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
                        if inf.item.grow > 0 then
                            sizes[idx] = inf.base + free * (inf.item.grow / weight)
                        else
                            sizes[idx] = inf.base
                        end
                    else
                        local sw = inf.item.shrink * inf.base
                        if sw > 0 then
                            sizes[idx] = inf.base + free * (sw / weight)
                        else
                            sizes[idx] = inf.base
                        end
                    end
                end
            end
            break
        end
    end

    for i = 1, n do
        local idx = indices[i]
        if not sizes[idx] then sizes[idx] = infos[idx].base end
    end

    return sizes
end

local function line_used_main(infos, indices, sizes, gap)
    local used = gap * math.max(0, #indices - 1)
    for i = 1, #indices do
        local idx = indices[i]
        local inf = infos[idx]
        used = used + sizes[idx] + inf.main_margin_start + inf.main_margin_end
    end
    return used
end

function T.UI.Flex:_measure_uncached(constraint)
    local inner = box_content_constraint(self.box, constraint)
    local infos, avail_main, avail_cross = flex_collect_infos(self, inner)
    local axis = self.axis

    local raw = { min_w = 0, min_h = 0, max_w = 0, max_h = 0, used_w = 0, used_h = 0, baseline = BASELINE_NONE }
    if #infos == 0 then return apply_box_measure(self.box, constraint, raw) end

    if self.wrap == WRAP_NO or avail_main == INF then
        local main_sum_min, main_sum_nat, cross_min, cross_nat = 0, 0, 0, 0
        for i = 1, #infos do
            local inf = infos[i]
            main_sum_min = main_sum_min + inf.min_main + inf.main_margin_start + inf.main_margin_end
            main_sum_nat = main_sum_nat + inf.base + inf.main_margin_start + inf.main_margin_end
            cross_min = max_of(cross_min, inf.min_cross + inf.cross_margin_start + inf.cross_margin_end)
            cross_nat = max_of(cross_nat, cross_size_of(inf.measure, axis) + inf.cross_margin_start + inf.cross_margin_end)
        end
        main_sum_min = main_sum_min + self.gap_main * math.max(0, #infos - 1)
        main_sum_nat = main_sum_nat + self.gap_main * math.max(0, #infos - 1)
        if is_row_axis(axis) then
            raw.min_w, raw.max_w, raw.used_w = main_sum_min, main_sum_nat, math.min(main_sum_nat, avail_main)
            raw.min_h, raw.max_h, raw.used_h = cross_min, cross_nat, cross_nat
        else
            raw.min_w, raw.max_w, raw.used_w = cross_min, cross_nat, cross_nat
            raw.min_h, raw.max_h, raw.used_h = main_sum_min, main_sum_nat, math.min(main_sum_nat, avail_main)
        end
    else
        local lines = {}
        local cur, cur_used = {}, 0
        for i = 1, #infos do
            local inf = infos[i]
            local need = inf.base + inf.main_margin_start + inf.main_margin_end
            if #cur > 0 then need = need + self.gap_main end
            if #cur > 0 and cur_used + need > avail_main then
                lines[#lines + 1] = cur
                cur, cur_used = {}, 0
                need = inf.base + inf.main_margin_start + inf.main_margin_end
            end
            cur[#cur + 1] = i
            cur_used = cur_used + need
        end
        if #cur > 0 then lines[#lines + 1] = cur end

        local used_main, used_cross, max_main = 0, 0, 0
        for li = 1, #lines do
            local line = lines[li]
            local lu, lc = 0, 0
            for j = 1, #line do
                local inf = infos[line[j]]
                lu = lu + inf.base + inf.main_margin_start + inf.main_margin_end
                if j > 1 then lu = lu + self.gap_main end
                lc = max_of(lc, cross_size_of(inf.measure, axis) + inf.cross_margin_start + inf.cross_margin_end)
            end
            max_main = max_of(max_main, lu)
            used_cross = used_cross + lc
            if li > 1 then used_cross = used_cross + self.gap_cross end
        end

        local min_line_main = 0
        for i = 1, #infos do
            local inf = infos[i]
            local need = inf.min_main + inf.main_margin_start + inf.main_margin_end
            if need > min_line_main then min_line_main = need end
        end

        if is_row_axis(axis) then
            raw.min_w, raw.max_w, raw.used_w = min_line_main, max_main, math.min(max_main, avail_main)
            raw.min_h, raw.max_h, raw.used_h = used_cross, used_cross, used_cross
        else
            raw.min_w, raw.max_w, raw.used_w = used_cross, used_cross, used_cross
            raw.min_h, raw.max_h, raw.used_h = min_line_main, max_main, math.min(max_main, avail_main)
        end
    end

    return apply_box_measure(self.box, constraint, raw)
end

function ui.measure(node, constraint)
    stats.measure.calls = stats.measure.calls + 1
    constraint = constraint or Constraint(SPAN_UNBOUNDED, SPAN_UNBOUNDED)
    local by_node = measure_cache[node]
    if by_node then
        local hit = by_node[constraint]
        if hit then
            stats.measure.hits = stats.measure.hits + 1
            return hit
        end
    else
        by_node = setmetatable({}, { __mode = "k" })
        measure_cache[node] = by_node
    end
    local out = node:_measure_uncached(constraint)
    by_node[constraint] = out
    return out
end

-- ══════════════════════════════════════════════════════════════
--  EMISSION / COMPILE BOUNDARY
-- ══════════════════════════════════════════════════════════════

local function VRect(tag, x, y, w, h, rgba8)
    return Cmd(K_RECT, tag, x, y, w, h, rgba8, 0, "", 0, 0, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO, nil, 0, 0, 0)
end

local function VText(tag, x, y, w, h, style, text)
    return Cmd(K_TEXTBLOCK, tag, x, y, w, h, style.rgba8, style.font_id, text, 0, 0, style.align, style.wrap, style.overflow, style.line_height, nil, 0, 0, 0)
end

local function VPushClip(x, y, w, h)
    return Cmd(K_PUSH_CLIP, "", x, y, w, h, 0, 0, "", 0, 0, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO, nil, 0, 0, 0)
end

local function VPopClip(x, y, w, h)
    return Cmd(K_POP_CLIP, "", x, y, w, h, 0, 0, "", 0, 0, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO, nil, 0, 0, 0)
end

local function VPushTx(tx, ty)
    return Cmd(K_PUSH_TX, "", 0, 0, 0, 0, 0, 0, "", tx, ty, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO, nil, 0, 0, 0)
end

local function VPopTx(tx, ty)
    return Cmd(K_POP_TX, "", 0, 0, 0, 0, 0, 0, "", tx, ty, TXT_START, TXT_NOWRAP, OV_VISIBLE, LH_AUTO, nil, 0, 0, 0)
end

local function resolve_local_frame(node, outer)
    local m = ui.measure(node, exact_constraint_from_frame(outer))
    return Frame(outer.x, outer.y, m.used_w, m.used_h), m
end

function T.UI.Rect:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    out[#out + 1] = VRect(self.tag, frame.x, frame.y, frame.w, frame.h, self.rgba8)
end

function T.UI.Spacer:_emit(out, outer)
    -- No commands.
end

function T.UI.Text:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    local max_w = (self.style.wrap == TXT_NOWRAP) and INF or frame.w
    local max_h = (self.style.overflow == OV_VISIBLE) and INF or frame.h
    local shape = shaped_text(self, max_w, max_h)
    out[#out + 1] = VText(self.tag, frame.x, frame.y, frame.w, frame.h, self.style, shape.text)
end

function T.UI.Sized:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    self.child:_emit(out, frame)
end

function T.UI.Transform:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    out[#out + 1] = VPushTx(self.tx, self.ty)
    self.child:_emit(out, Frame(frame.x, frame.y, frame.w, frame.h))
    out[#out + 1] = VPopTx(self.tx, self.ty)
end

function T.UI.Clip:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    out[#out + 1] = VPushClip(frame.x, frame.y, frame.w, frame.h)
    self.child:_emit(out, frame)
    out[#out + 1] = VPopClip(frame.x, frame.y, frame.w, frame.h)
end

function T.UI.Pad:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    local inner_w = math.max(0, frame.w - self.insets.l - self.insets.r)
    local inner_h = math.max(0, frame.h - self.insets.t - self.insets.b)
    self.child:_emit(out, Frame(frame.x + self.insets.l, frame.y + self.insets.t, inner_w, inner_h))
end

function T.UI.Stack:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    for i = 1, #self.children do
        self.children[i]:_emit(out, frame)
    end
end

function T.UI.Flex:_emit(out, outer)
    local frame = resolve_local_frame(self, outer)
    local axis = self.axis
    local rowish = is_row_axis(axis)
    local main_size = rowish and frame.w or frame.h
    local cross_size = rowish and frame.h or frame.w
    local wrap = self.wrap

    local inner_constraint = available_constraint_from_frame(frame)
    local infos = flex_collect_infos(self, inner_constraint)
    local child_infos = infos
    if #child_infos == 0 then return end

    -- Build lines
    local lines = {}
    if wrap == WRAP_NO or main_size == INF then
        lines[1] = {}
        for i = 1, #child_infos do lines[1][i] = i end
    else
        local cur, cur_used = {}, 0
        for i = 1, #child_infos do
            local inf = child_infos[i]
            local need = inf.base + inf.main_margin_start + inf.main_margin_end
            if #cur > 0 then need = need + self.gap_main end
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

    local line_infos = {}
    local natural_cross_total = 0

    for li = 1, #lines do
        local idxs = lines[li]
        local sizes = distribute_line(child_infos, idxs, main_size, self.gap_main)
        local used_main = line_used_main(child_infos, idxs, sizes, self.gap_main)
        local line_cross = 0
        local line_baseline = 0
        local items = {}

        for j = 1, #idxs do
            local idx = idxs[j]
            local inf = child_infos[idx]
            local slot_main = sizes[idx]
            local ccon
            if rowish then
                ccon = Constraint(SpanExact(math.max(0, slot_main)), exact_or_atmost(cross_size, false))
            else
                ccon = Constraint(exact_or_atmost(cross_size, false), SpanExact(math.max(0, slot_main)))
            end
            local m = ui.measure(inf.item.node, ccon)
            local actual_main = math.min(slot_main, main_size_of(m, axis))
            local actual_cross = cross_size_of(m, axis)
            local outer_cross = actual_cross + inf.cross_margin_start + inf.cross_margin_end
            local b = baseline_num(m.baseline)
            if b and rowish then
                line_baseline = math.max(line_baseline, b + inf.cross_margin_start)
            end
            line_cross = math.max(line_cross, outer_cross)
            items[j] = {
                idx = idx,
                slot_main = slot_main,
                actual_main = actual_main,
                actual_cross = actual_cross,
                measure = m,
                baseline = b,
            }
        end

        line_infos[li] = {
            items = items,
            used_main = used_main,
            natural_cross = line_cross,
            baseline = line_baseline,
        }
        natural_cross_total = natural_cross_total + line_cross
        if li > 1 then natural_cross_total = natural_cross_total + self.gap_cross end
    end

    -- Pack lines on cross axis
    local line_cross_sizes = {}
    local free_cross = (cross_size == INF) and 0 or math.max(0, cross_size - natural_cross_total)
    local line_lead, line_gap_extra = 0, 0

    if #line_infos == 1 and cross_size ~= INF then
        line_cross_sizes[1] = cross_size
    elseif self.align_content == CONTENT_STRETCH and cross_size ~= INF and #line_infos > 0 then
        local extra = free_cross / #line_infos
        for li = 1, #line_infos do
            line_cross_sizes[li] = line_infos[li].natural_cross + extra
        end
    else
        for li = 1, #line_infos do line_cross_sizes[li] = line_infos[li].natural_cross end
        if self.align_content == CONTENT_END then
            line_lead = free_cross
        elseif self.align_content == CONTENT_CENTER then
            line_lead = free_cross / 2
        elseif self.align_content == CONTENT_BETWEEN then
            line_gap_extra = (#line_infos > 1) and (free_cross / (#line_infos - 1)) or 0
        elseif self.align_content == CONTENT_AROUND then
            line_gap_extra = free_cross / #line_infos
            line_lead = line_gap_extra / 2
        elseif self.align_content == CONTENT_EVENLY then
            line_gap_extra = free_cross / (#line_infos + 1)
            line_lead = line_gap_extra
        end
    end

    local line_cross_pos = {}
    do
        local p = line_lead
        for li = 1, #line_infos do
            line_cross_pos[li] = p
            p = p + line_cross_sizes[li] + self.gap_cross + line_gap_extra
        end
    end

    -- Emit each line
    for li = 1, #line_infos do
        local line = line_infos[li]
        local line_slot_cross = line_cross_sizes[li]
        local used_main = line.used_main
        local free_main = (main_size == INF) and 0 or math.max(0, main_size - used_main)

        local line_start, gap_extra = 0, 0
        if self.justify == MAIN_END then
            line_start = free_main
        elseif self.justify == MAIN_CENTER then
            line_start = free_main / 2
        elseif self.justify == MAIN_BETWEEN then
            gap_extra = (#line.items > 1) and (free_main / (#line.items - 1)) or 0
        elseif self.justify == MAIN_AROUND then
            gap_extra = free_main / #line.items
            line_start = gap_extra / 2
        elseif self.justify == MAIN_EVENLY then
            gap_extra = free_main / (#line.items + 1)
            line_start = gap_extra
        end

        local pmain = line_start
        for j = 1, #line.items do
            local item = line.items[j]
            local inf = child_infos[item.idx]

            local eff_align = inf.item.self_align
            if eff_align == CROSS_AUTO then eff_align = self.align_items end
            if (not rowish) and eff_align == CROSS_BASELINE then eff_align = CROSS_START end

            local cross_inner = math.max(0, line_slot_cross - inf.cross_margin_start - inf.cross_margin_end)
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
                if is_reverse_axis(axis) then
                    x = frame.x + frame.w - logical_main - w
                else
                    x = frame.x + logical_main
                end
                if is_wrap_reverse(wrap) then
                    y = frame.y + frame.h - logical_cross - h
                else
                    y = frame.y + logical_cross
                end
            else
                w, h = actual_cross, item.actual_main
                if is_wrap_reverse(wrap) then
                    x = frame.x + frame.w - logical_cross - w
                else
                    x = frame.x + logical_cross
                end
                if is_reverse_axis(axis) then
                    y = frame.y + frame.h - logical_main - h
                else
                    y = frame.y + logical_main
                end
            end

            inf.item.node:_emit(out, Frame(x, y, w, h))

            pmain = pmain + inf.main_margin_start + item.slot_main + inf.main_margin_end + self.gap_main + gap_extra
        end
    end
end

function ui.compile(node, a, b, c, d)
    stats.compile.calls = stats.compile.calls + 1

    local frame
    if type(a) == "number" and type(b) == "number" and c == nil then
        frame = Frame(0, 0, a, b)
    elseif type(a) == "number" and type(b) == "number" and type(c) == "number" and type(d) == "number" then
        frame = Frame(a, b, c, d)
    else
        frame = a
    end
    if frame == nil then
        error('uilib.compile: expected (node, frame) or (node, w, h) or (node, x, y, w, h)', 2)
    end

    local by_node = compile_cache[node]
    if by_node then
        local hit = by_node[frame]
        if hit then
            stats.compile.hits = stats.compile.hits + 1
            return hit
        end
    else
        by_node = setmetatable({}, { __mode = "k" })
        compile_cache[node] = by_node
    end

    local out = {}
    node:_emit(out, frame)
    by_node[frame] = out
    return out
end

function ui.fragment(node, a, b, c, d)
    local frame
    if type(a) == "number" and type(b) == "number" and c == nil then
        frame = Frame(0, 0, a, b)
    elseif type(a) == "number" and type(b) == "number" and type(c) == "number" and type(d) == "number" then
        frame = Frame(a, b, c, d)
    else
        frame = a
    end
    if frame == nil then
        error('uilib.fragment: expected (node, frame) or (node, w, h) or (node, x, y, w, h)', 2)
    end
    return Fragment(frame.w, frame.h, ui.compile(node, frame))
end

function ui.assemble(plan)
    stats.assemble.calls = stats.assemble.calls + 1
    local hit = assemble_cache[plan]
    if hit then
        stats.assemble.hits = stats.assemble.hits + 1
        return hit
    end
    local out = {}
    local ops = plan.ops
    for i = 1, #ops do
        local op = ops[i]
        local k = op.kind
        if k == PK_PLACE then
            local frag = op.fragment
            if op.x == 0 and op.y == 0 then
                local cmds = frag.cmds
                for j = 1, #cmds do out[#out + 1] = cmds[j] end
            else
                out[#out + 1] = VPushTx(op.x, op.y)
                local cmds = frag.cmds
                for j = 1, #cmds do out[#out + 1] = cmds[j] end
                out[#out + 1] = VPopTx(op.x, op.y)
            end
        elseif k == PK_PUSH_CLIP then
            out[#out + 1] = VPushClip(op.x, op.y, op.w, op.h)
        elseif k == PK_POP_CLIP then
            out[#out + 1] = VPopClip(op.x, op.y, op.w, op.h)
        elseif k == PK_PUSH_TX then
            out[#out + 1] = VPushTx(op.tx, op.ty)
        elseif k == PK_POP_TX then
            out[#out + 1] = VPopTx(op.tx, op.ty)
        end
    end
    assemble_cache[plan] = out
    return out
end

-- ══════════════════════════════════════════════════════════════
--  EXECUTION
-- ══════════════════════════════════════════════════════════════

local function rgba8_to_love(rgba8)
    local a = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local b = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local g = (rgba8 % 256) / 255; rgba8 = math.floor(rgba8 / 256)
    local r = (rgba8 % 256) / 255
    return r, g, b, a
end

local function love_text_align(align)
    if align == TXT_CENTER then return "center" end
    if align == TXT_END then return "right" end
    if align == TXT_JUSTIFY then return "justify" end
    return "left"
end

function ui.paint(cmds, opts)
    opts = opts or {}
    if not (love and love.graphics) then return end

    local hover_tag = opts.hover_tag
    local tx, ty = 0, 0
    local tx_stack, clip_stack = {}, {}

    for i = 1, #cmds do
        local c = cmds[i]
        local k = c.kind

        if k == K_RECT then
            local r, g, b, a = rgba8_to_love(c.rgba8)
            if hover_tag and c.htag ~= "" and c.htag == hover_tag then
                r = math.min(1, r + 0.06)
                g = math.min(1, g + 0.06)
                b = math.min(1, b + 0.06)
            end
            love.graphics.setColor(r, g, b, a)
            love.graphics.rectangle("fill", c.x, c.y, c.w, c.h)

        elseif k == K_TEXTBLOCK then
            local font = get_font(c.font_id)
            if font then love.graphics.setFont(font) end
            love.graphics.setColor(rgba8_to_love(c.rgba8))

            local old_lh = nil
            if font and font.getLineHeight and font.setLineHeight then
                old_lh = font:getLineHeight()
                local lh = resolve_line_height(c.line_height, c.font_id)
                local fh = raw_text_height(c.font_id)
                if fh > 0 then font:setLineHeight(lh / fh) end
            end

            local restore_clip = nil
            if c.overflow ~= OV_VISIBLE then
                local ax, ay, nw, nh = c.x + tx, c.y + ty, c.w, c.h
                local top = clip_stack[#clip_stack]
                if top then
                    local x2 = math.max(ax, top[1])
                    local y2 = math.max(ay, top[2])
                    nw = math.max(0, math.min(ax + c.w, top[1] + top[3]) - x2)
                    nh = math.max(0, math.min(ay + c.h, top[2] + top[4]) - y2)
                    ax, ay = x2, y2
                    restore_clip = top
                end
                love.graphics.setScissor(ax, ay, nw, nh)
            end

            if c.text_wrap == TXT_NOWRAP and c.overflow == OV_VISIBLE then
                love.graphics.print(c.text, c.x, c.y)
            else
                love.graphics.printf(c.text, c.x, c.y, math.max(1, c.w), love_text_align(c.text_align))
            end

            if restore_clip then
                love.graphics.setScissor(restore_clip[1], restore_clip[2], restore_clip[3], restore_clip[4])
            elseif c.overflow ~= OV_VISIBLE then
                love.graphics.setScissor()
            end

            if font and old_lh and font.setLineHeight then
                font:setLineHeight(old_lh)
            end

        elseif k == K_PUSH_CLIP then
            local ax, ay, nw, nh = c.x + tx, c.y + ty, c.w, c.h
            local top = clip_stack[#clip_stack]
            if top then
                local x2 = math.max(ax, top[1])
                local y2 = math.max(ay, top[2])
                nw = math.max(0, math.min(ax + c.w, top[1] + top[3]) - x2)
                nh = math.max(0, math.min(ay + c.h, top[2] + top[4]) - y2)
                ax, ay = x2, y2
            end
            clip_stack[#clip_stack + 1] = { ax, ay, nw, nh }
            love.graphics.setScissor(ax, ay, nw, nh)

        elseif k == K_POP_CLIP then
            clip_stack[#clip_stack] = nil
            local top = clip_stack[#clip_stack]
            if top then
                love.graphics.setScissor(top[1], top[2], top[3], top[4])
            else
                love.graphics.setScissor()
            end

        elseif k == K_PUSH_TX then
            tx_stack[#tx_stack + 1] = { tx, ty }
            tx, ty = tx + c.tx, ty + c.ty
            love.graphics.push("transform")
            love.graphics.translate(c.tx, c.ty)

        elseif k == K_POP_TX then
            love.graphics.pop()
            local t = tx_stack[#tx_stack]
            tx_stack[#tx_stack] = nil
            tx, ty = t[1], t[2]
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function inside(px, py, x, y, w, h)
    return px >= x and py >= y and px < x + w and py < y + h
end

function ui.hit(cmds, mx, my)
    local tx, ty = 0, 0
    local clip_stack = {}

    local function intersect(a, b)
        if not a then return b end
        local x1 = math.max(a[1], b[1])
        local y1 = math.max(a[2], b[2])
        local x2 = math.min(a[1] + a[3], b[1] + b[3])
        local y2 = math.min(a[2] + a[4], b[2] + b[4])
        return { x1, y1, math.max(0, x2 - x1), math.max(0, y2 - y1) }
    end

    for i = #cmds, 1, -1 do
        local c = cmds[i]
        local k = c.kind

        if k == K_POP_TX then
            tx, ty = tx + c.tx, ty + c.ty

        elseif k == K_PUSH_TX then
            tx, ty = tx - c.tx, ty - c.ty

        elseif k == K_POP_CLIP then
            local clip = { c.x + tx, c.y + ty, c.w, c.h }
            clip_stack[#clip_stack + 1] = intersect(clip_stack[#clip_stack], clip)

        elseif k == K_PUSH_CLIP then
            clip_stack[#clip_stack] = nil

        elseif k == K_RECT or k == K_TEXTBLOCK then
            if c.htag ~= "" then
                local x, y = c.x + tx, c.y + ty
                local clip = clip_stack[#clip_stack]
                if (not clip or inside(mx, my, clip[1], clip[2], clip[3], clip[4]))
                and inside(mx, my, x, y, c.w, c.h) then
                    return c.htag
                end
            end
        end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════
--  NODE METHODS / DIAGNOSTICS
-- ══════════════════════════════════════════════════════════════

function T.UI.Node:measure(constraint)
    return ui.measure(self, constraint)
end

function T.UI.Node:compile(frame)
    return ui.compile(self, frame)
end

function T.UI.Node:emit_into(out, frame)
    return self:_emit(out, frame)
end

function T.View.Plan:cmds()
    return ui.assemble(self)
end

function ui.clear_cache()
    measure_cache = setmetatable({}, { __mode = "k" })
    compile_cache = setmetatable({}, { __mode = "k" })
    assemble_cache = setmetatable({}, { __mode = "k" })
    shape_cache = setmetatable({}, { __mode = "k" })
    stats.measure.calls, stats.measure.hits = 0, 0
    stats.compile.calls, stats.compile.hits = 0, 0
    stats.assemble.calls, stats.assemble.hits = 0, 0
end

function ui.report()
    local function line(s)
        local rate = (s.calls > 0) and math.floor((s.hits / s.calls) * 100 + 0.5) or 0
        return string.format("%-16s calls=%-6d hits=%-6d rate=%d%%", s.name, s.calls, s.hits, rate)
    end
    return table.concat({ line(stats.measure), line(stats.compile), line(stats.assemble) }, "\n")
end

return ui
