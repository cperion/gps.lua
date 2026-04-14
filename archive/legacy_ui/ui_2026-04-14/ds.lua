-- ui/ds.lua
--
-- Design-system helpers and style resolution for the fresh UI library.
--
-- Canonical boundary:
--   DS.Query(theme, surface, focus, flags) -> DS.ResolvedStyle
--
-- This is a natural pvm.lower(...) boundary because queries are interned ASDL
-- nodes and the resolved style is a pure, immutable artifact.

local pvm = require("pvm")
local classof = pvm.classof
local schema = require("ui.asdl")
local T = schema.T

local ds = { T = T, schema = schema }

local type = type

-- ─────────────────────────────────────────────────────────────
-- Interact / DS constructors and singletons
-- ─────────────────────────────────────────────────────────────

local POINTER_IDLE     = T.Interact.Idle
local POINTER_HOVERED  = T.Interact.Hovered
local POINTER_PRESSED  = T.Interact.Pressed
local POINTER_DRAGGING = T.Interact.Dragging
local FOCUS_BLURRED    = T.Interact.Blurred
local FOCUS_FOCUSED    = T.Interact.Focused

local ANY_POINTER = T.DS.AnyPointer
local ANY_FOCUS   = T.DS.AnyFocus
local ANY_FLAGS   = T.DS.AnyFlags

local ColorPack        = T.DS.ColorPack
local NumPack          = T.DS.NumPack
local ResolvedPaint    = T.DS.ResolvedPaint
local ResolvedMetrics  = T.DS.ResolvedMetrics
local ResolvedText     = T.DS.ResolvedText
local ResolvedStyle    = T.DS.ResolvedStyle
local Query            = T.DS.Query
local Surface          = T.DS.Surface
local Theme            = T.DS.Theme
local PaintSel         = T.DS.PaintSel
local StateSel         = T.DS.StateSel

local LH_AUTO          = T.Layout.LineHeightAuto
local TXT_START        = T.Layout.TextStart
local TXT_NOWRAP       = T.Layout.TextNoWrap
local OV_VISIBLE       = T.Layout.OverflowVisible
local UNLIMITED_LINES  = T.Layout.UnlimitedLines

local MT = {}
do
    local CL = T.DS.ColorLit(0)
    local SL = T.DS.SpaceLit(0)
    local SC = T.DS.ScaleLit(0)
    local FL = T.DS.FontLit(0)
    MT.WhenPointer = classof(T.DS.WhenPointer(POINTER_IDLE))
    MT.WhenFocus = classof(T.DS.WhenFocus(FOCUS_BLURRED))
    MT.RequireFlags = classof(T.DS.RequireFlags({}))
    MT.ColorLit = classof(CL)
    MT.SpaceLit = classof(SL)
    MT.ScaleLit = classof(SC)
    MT.FontLit = classof(FL)
    MT.SetBg = classof(T.DS.SetBg(CL))
    MT.SetFg = classof(T.DS.SetFg(CL))
    MT.SetBorder = classof(T.DS.SetBorder(CL))
    MT.SetAccent = classof(T.DS.SetAccent(CL))
    MT.SetRadius = classof(T.DS.SetRadius(SL))
    MT.SetOpacity = classof(T.DS.SetOpacity(SC))
    MT.SetPadH = classof(T.DS.SetPadH(SL))
    MT.SetPadV = classof(T.DS.SetPadV(SL))
    MT.SetGap = classof(T.DS.SetGap(SL))
    MT.SetGapCross = classof(T.DS.SetGapCross(SL))
    MT.SetBorderWidth = classof(T.DS.SetBorderWidth(SL))
    MT.SetFont = classof(T.DS.SetFont(FL))
    MT.SetLineHeight = classof(T.DS.SetLineHeight(LH_AUTO))
    MT.SetTextAlign = classof(T.DS.SetTextAlign(TXT_START))
    MT.SetTextWrap = classof(T.DS.SetTextWrap(TXT_NOWRAP))
    MT.SetOverflow = classof(T.DS.SetOverflow(OV_VISIBLE))
    MT.SetLineLimit = classof(T.DS.SetLineLimit(UNLIMITED_LINES))
end

local ZERO_COLOR_PACK = ColorPack(0, 0, 0, 0)
local ZERO_NUM_PACK = NumPack(0, 0, 0, 0)
local ONES_NUM_PACK = NumPack(1, 1, 1, 1)
local DEFAULT_METRICS = ResolvedMetrics(0, 0, 0, 0, 0)
local DEFAULT_PAINT = ResolvedPaint(
    ZERO_COLOR_PACK,
    ZERO_COLOR_PACK,
    ZERO_COLOR_PACK,
    ZERO_COLOR_PACK,
    ZERO_NUM_PACK,
    ONES_NUM_PACK)
local DEFAULT_TEXT = ResolvedText(0, LH_AUTO, TXT_START, TXT_NOWRAP, OV_VISIBLE, UNLIMITED_LINES)
local DEFAULT_STYLE = ResolvedStyle(DEFAULT_METRICS, DEFAULT_PAINT, DEFAULT_TEXT)

-- ─────────────────────────────────────────────────────────────
-- Lookup caches (weak on theme identity)
-- ─────────────────────────────────────────────────────────────

local surface_map_cache = setmetatable({}, { __mode = "k" })
local color_tok_cache   = setmetatable({}, { __mode = "k" })
local space_tok_cache   = setmetatable({}, { __mode = "k" })
local font_tok_cache    = setmetatable({}, { __mode = "k" })

local function build_map(theme, cache, field_name)
    local map = cache[theme]
    if map then
        return map
    end
    map = {}
    local list = theme[field_name]
    for i = 1, #list do
        map[list[i].name] = list[i]
    end
    cache[theme] = map
    return map
end

local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local function require_binding(theme, field_name, cache, name, what)
    local b = build_map(theme, cache, field_name)[name]
    if not b then
        error(string.format("ui.ds.resolve: unknown %s '%s' in theme '%s'", what, tostring(name), tostring(theme.name)), 2)
    end
    return b
end

local function get_surface(theme, name)
    return require_binding(theme, "surfaces", surface_map_cache, name, "surface")
end

local function resolve_color_val(theme, val)
    if classof(val) == MT.ColorLit then
        return val.rgba8
    end
    return require_binding(theme, "colors", color_tok_cache, val.name, "color token").rgba8
end

local function resolve_space_val(theme, val)
    if classof(val) == MT.SpaceLit then
        return val.px
    end
    return require_binding(theme, "spaces", space_tok_cache, val.name, "space token").px
end

local function resolve_font_val(theme, val)
    if classof(val) == MT.FontLit then
        return val.font_id
    end
    return require_binding(theme, "fonts", font_tok_cache, val.name, "font token").font_id
end

local function resolve_scale_val(val)
    return val.n
end

-- ─────────────────────────────────────────────────────────────
-- Selector matching
-- ─────────────────────────────────────────────────────────────

local function match_psel(psel, pointer)
    if psel == ANY_POINTER then
        return true
    end
    return psel.pointer == pointer
end

local function match_fsel(fsel, focus)
    if fsel == ANY_FOCUS then
        return true
    end
    return fsel.focus == focus
end

local function match_gsel(gsel, flags)
    if gsel == ANY_FLAGS then
        return true
    end
    local req = gsel.required
    for i = 1, #req do
        local found = false
        for j = 1, #flags do
            if req[i] == flags[j] then
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end
    return true
end

local function match_paint_sel(sel, pointer, focus, flags)
    return match_psel(sel.pointer, pointer)
       and match_fsel(sel.focus, focus)
       and match_gsel(sel.flags, flags)
end

local function match_state_sel(sel, focus, flags)
    return match_fsel(sel.focus, focus)
       and match_gsel(sel.flags, flags)
end

-- ─────────────────────────────────────────────────────────────
-- Resolver
-- ─────────────────────────────────────────────────────────────

local POINTER_PHASES = {
    POINTER_IDLE,
    POINTER_HOVERED,
    POINTER_PRESSED,
    POINTER_DRAGGING,
}

local function resolve_style_impl(query)
    local theme = query.theme
    local surface = get_surface(theme, query.surface)

    local focus = query.focus
    local flags = query.flags

    local pad_h, pad_v, gap, gap_cross, border_w = 0, 0, 0, 0, 0
    local metric_rules = surface.metric_rules
    for i = 1, #metric_rules do
        local rule = metric_rules[i]
        if match_state_sel(rule.when, focus, flags) then
            local set = rule.set
            for j = 1, #set do
                local d = set[j]
                local mt = classof(d)
                if mt == MT.SetPadH then
                    pad_h = resolve_space_val(theme, d.val)
                elseif mt == MT.SetPadV then
                    pad_v = resolve_space_val(theme, d.val)
                elseif mt == MT.SetGap then
                    gap = resolve_space_val(theme, d.val)
                elseif mt == MT.SetGapCross then
                    gap_cross = resolve_space_val(theme, d.val)
                elseif mt == MT.SetBorderWidth then
                    border_w = resolve_space_val(theme, d.val)
                end
            end
        end
    end

    local font_id = 0
    local line_height = LH_AUTO
    local align = TXT_START
    local wrap = TXT_NOWRAP
    local overflow = OV_VISIBLE
    local line_limit = UNLIMITED_LINES
    local text_rules = surface.text_rules
    for i = 1, #text_rules do
        local rule = text_rules[i]
        if match_state_sel(rule.when, focus, flags) then
            local set = rule.set
            for j = 1, #set do
                local d = set[j]
                local mt = classof(d)
                if mt == MT.SetFont then
                    font_id = resolve_font_val(theme, d.val)
                elseif mt == MT.SetLineHeight then
                    line_height = d.val
                elseif mt == MT.SetTextAlign then
                    align = d.val
                elseif mt == MT.SetTextWrap then
                    wrap = d.val
                elseif mt == MT.SetOverflow then
                    overflow = d.val
                elseif mt == MT.SetLineLimit then
                    line_limit = d.val
                end
            end
        end
    end

    local bg, fg, border, accent = {}, {}, {}, {}
    local radius, opacity = {}, {}
    local paint_rules = surface.paint_rules

    for pi = 1, 4 do
        local pointer = POINTER_PHASES[pi]
        local bg_v, fg_v, border_v, accent_v = 0, 0, 0, 0
        local radius_v, opacity_v = 0, 1

        for i = 1, #paint_rules do
            local rule = paint_rules[i]
            if match_paint_sel(rule.when, pointer, focus, flags) then
                local set = rule.set
                for j = 1, #set do
                    local d = set[j]
                    local mt = classof(d)
                    if mt == MT.SetBg then
                        bg_v = resolve_color_val(theme, d.val)
                    elseif mt == MT.SetFg then
                        fg_v = resolve_color_val(theme, d.val)
                    elseif mt == MT.SetBorder then
                        border_v = resolve_color_val(theme, d.val)
                    elseif mt == MT.SetAccent then
                        accent_v = resolve_color_val(theme, d.val)
                    elseif mt == MT.SetRadius then
                        radius_v = resolve_space_val(theme, d.val)
                    elseif mt == MT.SetOpacity then
                        opacity_v = resolve_scale_val(d.val)
                    end
                end
            end
        end

        bg[pi] = bg_v
        fg[pi] = fg_v
        border[pi] = border_v
        accent[pi] = accent_v
        radius[pi] = radius_v
        opacity[pi] = opacity_v
    end

    return ResolvedStyle(
        ResolvedMetrics(pad_h, pad_v, gap, gap_cross, border_w),
        ResolvedPaint(
            ColorPack(bg[1], bg[2], bg[3], bg[4]),
            ColorPack(fg[1], fg[2], fg[3], fg[4]),
            ColorPack(border[1], border[2], border[3], border[4]),
            ColorPack(accent[1], accent[2], accent[3], accent[4]),
            NumPack(radius[1], radius[2], radius[3], radius[4]),
            NumPack(opacity[1], opacity[2], opacity[3], opacity[4])),
        ResolvedText(font_id, line_height, align, wrap, overflow, line_limit))
end

local resolve_style = pvm.lower("ui.ds.resolve", resolve_style_impl)

local normalize_focus
local normalize_flags

-- ─────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────

function ds.resolve(query)
    return resolve_style(query)
end

function ds.query(theme, surface_name, focus, flags)
    return Query(theme, surface_name or "", normalize_focus(focus) or FOCUS_BLURRED, normalize_flags(flags) or {})
end

function ds.stats()
    return resolve_style:stats()
end

function ds.reset()
    wipe(surface_map_cache)
    wipe(color_tok_cache)
    wipe(space_tok_cache)
    wipe(font_tok_cache)
    resolve_style:reset()
end

-- Value constructors
function ds.flag(name) return T.DS.Flag(name or "") end
function ds.ctok(name) return T.DS.ColorTok(name or "") end
function ds.clit(rgba8) return T.DS.ColorLit(rgba8 or 0) end
function ds.stok(name) return T.DS.SpaceTok(name or "") end
function ds.slit(px) return T.DS.SpaceLit(px or 0) end
function ds.ftok(name) return T.DS.FontTok(name or "") end
function ds.flit(id) return T.DS.FontLit(id or 0) end
function ds.sclit(n) return T.DS.ScaleLit(n or 0) end

function ds.solid(rgba8)
    rgba8 = rgba8 or 0
    return ColorPack(rgba8, rgba8, rgba8, rgba8)
end

function ds.solid_num(n)
    n = n or 0
    return NumPack(n, n, n, n)
end

-- Paint declarations
function ds.bg(val) return T.DS.SetBg(val) end
function ds.fg(val) return T.DS.SetFg(val) end
function ds.border_color(val) return T.DS.SetBorder(val) end
function ds.accent(val) return T.DS.SetAccent(val) end
function ds.radius(val) return T.DS.SetRadius(val) end
function ds.opacity(val) return T.DS.SetOpacity(val) end

-- Metric declarations
function ds.pad_h(val) return T.DS.SetPadH(val) end
function ds.pad_v(val) return T.DS.SetPadV(val) end
function ds.gap(val) return T.DS.SetGap(val) end
function ds.gap_cross(val) return T.DS.SetGapCross(val) end
function ds.border_w(val) return T.DS.SetBorderWidth(val) end

-- Text declarations
function ds.font(val) return T.DS.SetFont(val) end
function ds.line_height(val) return T.DS.SetLineHeight(val) end
function ds.text_align(val) return T.DS.SetTextAlign(val) end
function ds.text_wrap(val) return T.DS.SetTextWrap(val) end
function ds.overflow(val) return T.DS.SetOverflow(val) end
function ds.line_limit(val) return T.DS.SetLineLimit(val) end

local POINTER_MAP = {
    idle = POINTER_IDLE,
    hovered = POINTER_HOVERED,
    pressed = POINTER_PRESSED,
    dragging = POINTER_DRAGGING,
}

local FOCUS_MAP = {
    blurred = FOCUS_BLURRED,
    focused = FOCUS_FOCUSED,
}

local function normalize_pointer(pointer)
    if pointer == nil then
        return nil
    end
    if type(pointer) == "string" then
        local p = POINTER_MAP[pointer]
        if not p then
            error("ui.ds.paint_sel: unknown pointer '" .. tostring(pointer) .. "'", 2)
        end
        return p
    end
    return pointer
end

normalize_focus = function(focus)
    if focus == nil then
        return nil
    end
    if type(focus) == "string" then
        local f = FOCUS_MAP[focus]
        if not f then
            error("ui.ds.state_sel: unknown focus '" .. tostring(focus) .. "'", 2)
        end
        return f
    end
    return focus
end

normalize_flags = function(flags)
    if flags == nil then
        return nil
    end
    local out = {}
    for i = 1, #flags do
        local flag = flags[i]
        out[i] = (type(flag) == "string") and ds.flag(flag) or flag
    end
    return out
end

function ds.paint_sel(opts)
    if not opts then
        return PaintSel(ANY_POINTER, ANY_FOCUS, ANY_FLAGS)
    end
    local psel = ANY_POINTER
    local pointer = normalize_pointer(opts.pointer)
    if pointer ~= nil then
        psel = T.DS.WhenPointer(pointer)
    end
    local fsel = ANY_FOCUS
    local focus = normalize_focus(opts.focus)
    if focus ~= nil then
        fsel = T.DS.WhenFocus(focus)
    end
    local gsel = ANY_FLAGS
    local flags = normalize_flags(opts.flags)
    if flags ~= nil then
        gsel = T.DS.RequireFlags(flags)
    end
    return PaintSel(psel, fsel, gsel)
end

function ds.state_sel(opts)
    if not opts then
        return StateSel(ANY_FOCUS, ANY_FLAGS)
    end
    local fsel = ANY_FOCUS
    local focus = normalize_focus(opts.focus)
    if focus ~= nil then
        fsel = T.DS.WhenFocus(focus)
    end
    local gsel = ANY_FLAGS
    local flags = normalize_flags(opts.flags)
    if flags ~= nil then
        gsel = T.DS.RequireFlags(flags)
    end
    return StateSel(fsel, gsel)
end

-- Compatibility aliases for the old naming instinct.
ds.sel = ds.paint_sel
function ds.ssel(opts)
    return ds.state_sel(opts)
end

function ds.paint_rule(sel, decls)
    return T.DS.PaintRule(sel, decls or {})
end

function ds.metric_rule(sel, decls)
    return T.DS.MetricRule(sel, decls or {})
end

function ds.text_rule(sel, decls)
    return T.DS.TextRule(sel, decls or {})
end

function ds.surface(name, paint_rules, metric_rules, text_rules)
    return Surface(name, paint_rules or {}, metric_rules or {}, text_rules or {})
end

function ds.theme(name, opts)
    opts = opts or {}
    local colors, spaces, fonts, surfaces = {}, {}, {}, {}
    if opts.colors then
        for i = 1, #opts.colors do
            local item = opts.colors[i]
            colors[i] = T.DS.ColorBinding(item[1], item[2])
        end
    end
    if opts.spaces then
        for i = 1, #opts.spaces do
            local item = opts.spaces[i]
            spaces[i] = T.DS.SpaceBinding(item[1], item[2])
        end
    end
    if opts.fonts then
        for i = 1, #opts.fonts do
            local item = opts.fonts[i]
            fonts[i] = T.DS.FontBinding(item[1], item[2])
        end
    end
    if opts.surfaces then
        surfaces = opts.surfaces
    end
    return Theme(name, colors, spaces, fonts, surfaces)
end

-- Expose useful singletons / defaults.
ds.IDLE = POINTER_IDLE
ds.HOVERED = POINTER_HOVERED
ds.PRESSED = POINTER_PRESSED
ds.DRAGGING = POINTER_DRAGGING
ds.BLURRED = FOCUS_BLURRED
ds.FOCUSED = FOCUS_FOCUSED
ds.ANY_POINTER = ANY_POINTER
ds.ANY_FOCUS = ANY_FOCUS
ds.ANY_FLAGS = ANY_FLAGS
ds.DEFAULT_STYLE = DEFAULT_STYLE

ds.ZERO_COLOR_PACK = ZERO_COLOR_PACK
ds.ZERO_NUM_PACK = ZERO_NUM_PACK
ds.ONES_NUM_PACK = ONES_NUM_PACK

-- Direct ASDL methods.
-- These are installed via ordinary class assignment so ASDL's own method model
-- stays in charge (`class.__index = class`, plus sum-parent propagation through
-- `__newindex` in asdl_context.lua).
function T.DS.Query:resolve()
    return ds.resolve(self)
end

function T.DS.Theme:query(surface_name, focus, flags)
    return ds.query(self, surface_name, focus, flags)
end

function T.DS.Theme:resolve(surface_name, focus, flags)
    return ds.resolve(ds.query(self, surface_name, focus, flags))
end

return ds
