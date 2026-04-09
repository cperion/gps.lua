-- ui/lower.lua
--
-- Lower authored semantic UI (SemUI) to concrete reducer-facing UI.
--
-- Canonical boundary:
--   Lower.Request(theme, focused_id, focus, style, node) -> UI.Node
--
-- Notes:
--   - DS.Surface is treated as a style scope in this first pass. It changes the
--     inherited resolved style for its subtree but does not force a concrete
--     panel node by itself.
--   - Focus-sensitive style resolution happens when entering Focusable(id,...):
--     the lowered child subtree sees Focused when id == focused_id.
--   - Pointer state stays dynamic at runtime via DS.ColorPack / DS.NumPack.

local pvm = require("pvm")
local schema = require("ui.asdl")
local ds = require("ui.ds")

local T = schema.T

T:Define [[
    module Lower {
        Request = (DS.Theme theme,
                   string focused_id,
                   Interact.Focus focus,
                   DS.ResolvedStyle style,
                   SemUI.Node node) unique

        TextRequest = (DS.Theme theme,
                       DS.ResolvedStyle style,
                       SemUI.TextSpec spec) unique
    }
]]

local lower = { T = T, schema = schema, ds = ds }

local type = type
local getmetatable = getmetatable

local Request = T.Lower.Request
local TextRequest = T.Lower.TextRequest

local FOCUS_BLURRED = T.Interact.Blurred
local FOCUS_FOCUSED = T.Interact.Focused

local UIEmpty = T.UI.Empty

local BoxStyle = T.UI.BoxStyle
local UITextStyle = T.UI.TextStyle
local UIFlexItem = T.UI.FlexItem

local ZERO_COLOR_PACK = ds.ZERO_COLOR_PACK
local ONES_NUM_PACK = ds.ONES_NUM_PACK
local DEFAULT_STYLE = ds.DEFAULT_STYLE

local USE_SURFACE_FONT = T.SemUI.UseSurfaceFont
local USE_SURFACE_LINE_HEIGHT = T.SemUI.UseSurfaceLineHeight
local USE_SURFACE_TEXT_ALIGN = T.SemUI.UseSurfaceTextAlign
local USE_SURFACE_TEXT_WRAP = T.SemUI.UseSurfaceTextWrap
local USE_SURFACE_OVERFLOW = T.SemUI.UseSurfaceOverflow
local USE_SURFACE_LINE_LIMIT = T.SemUI.UseSurfaceLineLimit

local MT = {}
do
    MT.OverrideFont = getmetatable(T.SemUI.OverrideFont(T.DS.FontLit(0)))
    MT.OverrideLineHeight = getmetatable(T.SemUI.OverrideLineHeight(T.Layout.LineHeightAuto))
    MT.OverrideTextAlign = getmetatable(T.SemUI.OverrideTextAlign(T.Layout.TextStart))
    MT.OverrideTextWrap = getmetatable(T.SemUI.OverrideTextWrap(T.Layout.TextNoWrap))
    MT.OverrideOverflow = getmetatable(T.SemUI.OverrideOverflow(T.Layout.OverflowVisible))
    MT.OverrideLineLimit = getmetatable(T.SemUI.OverrideLineLimit(T.Layout.UnlimitedLines))
    MT.FontLit = getmetatable(T.DS.FontLit(0))
end

-- ─────────────────────────────────────────────────────────────
-- Token resolution needed for TextSpec font overrides.
-- Keep local to the lowering layer for now.
-- ─────────────────────────────────────────────────────────────

local font_tok_cache = setmetatable({}, { __mode = "k" })

local function build_font_map(theme)
    local map = font_tok_cache[theme]
    if map then
        return map
    end
    map = {}
    local list = theme.fonts
    for i = 1, #list do
        map[list[i].name] = list[i]
    end
    font_tok_cache[theme] = map
    return map
end

local function resolve_font_val(theme, val)
    if getmetatable(val) == MT.FontLit then
        return val.font_id
    end
    local b = build_font_map(theme)[val.name]
    return b and b.font_id or 0
end

local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

-- ─────────────────────────────────────────────────────────────
-- Style projections
-- ─────────────────────────────────────────────────────────────

local lower_box_style = pvm.lower("ui.lower.box_style", function(style)
    local metrics = style.metrics
    local paint = style.paint
    return BoxStyle(
        metrics.pad_h,
        metrics.pad_v,
        metrics.border_w,
        paint.bg,
        paint.border,
        paint.accent,
        paint.radius,
        paint.opacity)
end)

local lower_text_style = pvm.lower("ui.lower.text_style", function(req)
    local theme = req.theme
    local style = req.style
    local spec = req.spec

    local base = style.text
    local paint = style.paint

    local font_id = base.font_id
    local line_height = base.line_height
    local align = base.align
    local wrap = base.wrap
    local overflow = base.overflow
    local line_limit = base.line_limit

    local font_choice = spec.font
    if font_choice ~= USE_SURFACE_FONT then
        font_id = resolve_font_val(theme, font_choice.font)
    end

    local line_height_choice = spec.line_height
    if line_height_choice ~= USE_SURFACE_LINE_HEIGHT then
        line_height = line_height_choice.line_height
    end

    local align_choice = spec.align
    if align_choice ~= USE_SURFACE_TEXT_ALIGN then
        align = align_choice.align
    end

    local wrap_choice = spec.wrap
    if wrap_choice ~= USE_SURFACE_TEXT_WRAP then
        wrap = wrap_choice.wrap
    end

    local overflow_choice = spec.overflow
    if overflow_choice ~= USE_SURFACE_OVERFLOW then
        overflow = overflow_choice.overflow
    end

    local limit_choice = spec.line_limit
    if limit_choice ~= USE_SURFACE_LINE_LIMIT then
        line_limit = limit_choice.line_limit
    end

    return UITextStyle(
        font_id,
        paint.fg or ZERO_COLOR_PACK,
        paint.opacity or ONES_NUM_PACK,
        line_height,
        align,
        wrap,
        overflow,
        line_limit)
end)

local function box_style(style)
    return lower_box_style(style)
end

local function text_style(theme, style, spec)
    return lower_text_style(TextRequest(theme, style, spec))
end

lower.box_style = box_style
lower.text_style = text_style

-- ─────────────────────────────────────────────────────────────
-- Main lowering
-- ─────────────────────────────────────────────────────────────

local lower_node

local function lower_child(theme, focused_id, focus, style, node)
    return lower_node(Request(theme, focused_id, focus, style, node))
end

local function lower_flex_items(theme, focused_id, focus, style, items)
    local out = {}
    for i = 1, #items do
        local item = items[i]
        out[i] = UIFlexItem(
            lower_child(theme, focused_id, focus, style, item.node),
            item.grow,
            item.shrink,
            item.basis,
            item.self_align,
            item.margin)
    end
    return out
end

local function lower_nodes(theme, focused_id, focus, style, nodes)
    local out = {}
    for i = 1, #nodes do
        out[i] = lower_child(theme, focused_id, focus, style, nodes[i])
    end
    return out
end

lower_node = pvm.lower("ui.lower.node", function(req)
    local theme = req.theme
    local focused_id = req.focused_id
    local focus = req.focus
    local style = req.style
    local node = req.node

    local kind = node.kind

    if kind == "Empty" then
        return UIEmpty
    elseif kind == "Key" then
        return T.UI.Key(node.id, lower_child(theme, focused_id, focus, style, node.child))
    elseif kind == "HitBox" then
        return T.UI.HitBox(node.id, lower_child(theme, focused_id, focus, style, node.child))
    elseif kind == "Pressable" then
        return T.UI.Pressable(node.id, lower_child(theme, focused_id, focus, style, node.child))
    elseif kind == "Focusable" then
        local child_focus = (node.id ~= "" and node.id == focused_id) and FOCUS_FOCUSED or FOCUS_BLURRED
        return T.UI.Focusable(node.id, lower_child(theme, focused_id, child_focus, style, node.child))
    elseif kind == "Surface" then
        local next_style = ds.resolve(ds.query(theme, node.name, focus, node.flags))
        return lower_child(theme, focused_id, focus, next_style, node.child)
    elseif kind == "Flex" then
        return T.UI.Flex(
            node.axis,
            node.wrap,
            node.gap_main,
            node.gap_cross,
            node.justify,
            node.align_items,
            node.align_content,
            node.box,
            lower_flex_items(theme, focused_id, focus, style, node.children))
    elseif kind == "Pad" then
        return T.UI.Pad(node.insets, node.box, lower_child(theme, focused_id, focus, style, node.child))
    elseif kind == "Stack" then
        return T.UI.Stack(node.box, lower_nodes(theme, focused_id, focus, style, node.children))
    elseif kind == "Clip" then
        return T.UI.Clip(node.box, lower_child(theme, focused_id, focus, style, node.child))
    elseif kind == "Transform" then
        return T.UI.Transform(node.tx, node.ty, node.box, lower_child(theme, focused_id, focus, style, node.child))
    elseif kind == "Sized" then
        return T.UI.Sized(node.box, lower_child(theme, focused_id, focus, style, node.child))
    elseif kind == "ScrollArea" then
        return T.UI.ScrollArea(
            node.id,
            node.axis,
            node.scroll_x,
            node.scroll_y,
            node.box,
            box_style(style),
            lower_child(theme, focused_id, focus, style, node.child))
    elseif kind == "Rect" then
        return T.UI.Rect(node.tag, node.box, box_style(style))
    elseif kind == "Text" then
        return T.UI.Text(node.tag, node.box, text_style(theme, style, node.spec), node.text)
    elseif kind == "CustomPaint" then
        return T.UI.CustomPaint(node.tag, node.box, node.paint)
    elseif kind == "Overlay" then
        return T.UI.Overlay(lower_child(theme, focused_id, focus, style, node.base), node.overlay)
    elseif kind == "Spacer" then
        return T.UI.Spacer(node.box)
    end

    error("ui.lower: unsupported SemUI node kind " .. tostring(kind), 2)
end)

-- ─────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────

function lower.request(theme, node, opts)
    opts = opts or {}
    return Request(
        theme,
        opts.focused_id or "",
        opts.focus or FOCUS_BLURRED,
        opts.style or DEFAULT_STYLE,
        node)
end

function lower.node(theme, node, opts)
    return lower_node(lower.request(theme, node, opts))
end

function lower.stats()
    return {
        node = lower_node:stats(),
        box_style = lower_box_style:stats(),
        text_style = lower_text_style:stats(),
    }
end

function lower.reset()
    wipe(font_tok_cache)
    lower_node:reset()
    lower_box_style:reset()
    lower_text_style:reset()
end

function lower.report_string()
    local s = lower.stats()
    local function line(stat)
        local calls = stat.calls or 0
        local hits = stat.hits or 0
        local rate = calls > 0 and (hits / calls) * 100 or 100.0
        return string.format("  %-24s calls=%-6d hits=%-6d rate=%.1f%%", stat.name or "lower", calls, hits, rate)
    end
    return table.concat({
        line(s.node),
        line(s.box_style),
        line(s.text_style),
    }, "\n")
end

-- Direct ASDL methods.
-- `T.SemUI.Node` is a sum parent, so ordinary assignment propagates methods to
-- all concrete members through asdl_context.lua's `__newindex` propagation.
function T.SemUI.Node:lower(theme, opts)
    return lower.node(theme, self, opts)
end

return lower
