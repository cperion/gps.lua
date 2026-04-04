-- uilib_impl.lua
--
-- Implementation for uilib: UI library with design system, pointer-variant packs, and generic paint primitives.
--
-- Core idea: leaf colors are DS.ColorPack (4 pointer-phase variants), resolved at
-- compile time by the DS boundary. The paint loop selects one variant per command
-- based on the current pointer phase — no rule matching, no token lookup.

local pvm2 = require("pvm2")
local schema = require("uilib_asdl")
local T = schema.T

local ui = { T = T }
local ds = {}
ui.ds = ds

function ui.set_backend(backend) ui._backend = backend end
function ui.get_backend() return ui._backend end

-- ══════════════════════════════════════════════════════════════
--  SINGLETONS / CONSTRUCTORS / METATABLES
-- ══════════════════════════════════════════════════════════════

-- Interact
local POINTER_IDLE     = T.Interact.Idle
local POINTER_HOVERED  = T.Interact.Hovered
local POINTER_PRESSED  = T.Interact.Pressed
local POINTER_DRAGGING = T.Interact.Dragging
local FOCUS_BLURRED    = T.Interact.Blurred
local FOCUS_FOCUSED    = T.Interact.Focused

-- DS singletons
local FLAG_ACTIVE      = T.DS.Active
local FLAG_DISABLED    = T.DS.Disabled
local FLAG_SELECTED    = T.DS.Selected
local ANY_POINTER      = T.DS.AnyPointer
local ANY_FOCUS        = T.DS.AnyFocus
local ANY_FLAGS        = T.DS.AnyFlags

-- DS constructors
local ColorPack        = T.DS.ColorPack
local NumPack          = T.DS.NumPack
local Style            = T.DS.Style
local Query            = T.DS.Query
local Selector         = T.DS.Selector
local StructSel        = T.DS.StructSel
local Cond             = T.DS.Cond
local Surface          = T.DS.Surface
local Theme            = T.DS.Theme

-- DS metatables for dispatch (consolidated into table to reduce local count)
local DS_MT = {}
do
    local CL = T.DS.ColorLit(0); local SL = T.DS.SpaceLit(0); local SC = T.DS.ScaleLit(0); local FL = T.DS.FontLit(0)
    DS_MT.WhenPointer = getmetatable(T.DS.WhenPointer(POINTER_IDLE))
    DS_MT.WhenFocus = getmetatable(T.DS.WhenFocus(FOCUS_BLURRED))
    DS_MT.RequireFlags = getmetatable(T.DS.RequireFlags({}))
    DS_MT.ColorTok = getmetatable(T.DS.ColorTok(""))
    DS_MT.ColorLit = getmetatable(CL)
    DS_MT.SpaceTok = getmetatable(T.DS.SpaceTok(""))
    DS_MT.SpaceLit = getmetatable(SL)
    DS_MT.ScaleLit = getmetatable(SC)
    DS_MT.FontTok = getmetatable(T.DS.FontTok(""))
    DS_MT.FontLit = getmetatable(FL)
    DS_MT.SetBg = getmetatable(T.DS.SetBg(CL))
    DS_MT.SetFg = getmetatable(T.DS.SetFg(CL))
    DS_MT.SetBorder = getmetatable(T.DS.SetBorder(CL))
    DS_MT.SetAccent = getmetatable(T.DS.SetAccent(CL))
    DS_MT.SetRadius = getmetatable(T.DS.SetRadius(SL))
    DS_MT.SetOpacity = getmetatable(T.DS.SetOpacity(SC))
    DS_MT.SetPadH = getmetatable(T.DS.SetPadH(SL))
    DS_MT.SetPadV = getmetatable(T.DS.SetPadV(SL))
    DS_MT.SetGap = getmetatable(T.DS.SetGap(SL))
    DS_MT.SetBorderWidth = getmetatable(T.DS.SetBorderWidth(SL))
    DS_MT.SetFont = getmetatable(T.DS.SetFont(FL))
end

-- UI singletons (consolidated via multi-assign to stay under 200-local limit)
local AXIS_ROW, AXIS_ROW_REV, AXIS_COL, AXIS_COL_REV = T.UI.AxisRow, T.UI.AxisRowReverse, T.UI.AxisCol, T.UI.AxisColReverse
local WRAP_NO, WRAP_YES, WRAP_REV = T.UI.WrapNoWrap, T.UI.WrapWrap, T.UI.WrapWrapReverse
local MAIN_START, MAIN_END, MAIN_CENTER = T.UI.MainStart, T.UI.MainEnd, T.UI.MainCenter
local MAIN_BETWEEN, MAIN_AROUND, MAIN_EVENLY = T.UI.MainSpaceBetween, T.UI.MainSpaceAround, T.UI.MainSpaceEvenly
local CROSS_AUTO, CROSS_START, CROSS_END = T.UI.CrossAuto, T.UI.CrossStart, T.UI.CrossEnd
local CROSS_CENTER, CROSS_STRETCH, CROSS_BASELINE = T.UI.CrossCenter, T.UI.CrossStretch, T.UI.CrossBaseline
local CONTENT_START, CONTENT_END, CONTENT_CENTER, CONTENT_STRETCH = T.UI.ContentStart, T.UI.ContentEnd, T.UI.ContentCenter, T.UI.ContentStretch
local CONTENT_BETWEEN, CONTENT_AROUND, CONTENT_EVENLY = T.UI.ContentSpaceBetween, T.UI.ContentSpaceAround, T.UI.ContentSpaceEvenly
local SIZE_AUTO, SIZE_CONTENT = T.UI.SizeAuto, T.UI.SizeContent
local BASIS_AUTO, BASIS_CONTENT = T.UI.BasisAuto, T.UI.BasisContent
local NO_MIN, NO_MAX = T.UI.NoMin, T.UI.NoMax
local TXT_NOWRAP, TXT_WORDWRAP, TXT_CHARWRAP = T.UI.TextNoWrap, T.UI.TextWordWrap, T.UI.TextCharWrap
local TXT_START, TXT_CENTER, TXT_END, TXT_JUSTIFY = T.UI.TextStart, T.UI.TextCenter, T.UI.TextEnd, T.UI.TextJustify
local OV_VISIBLE, OV_CLIP, OV_ELLIPSIS = T.UI.OverflowVisible, T.UI.OverflowClip, T.UI.OverflowEllipsis
local LH_AUTO, UNLIMITED_LINES = T.UI.LineHeightAuto, T.UI.UnlimitedLines

local Insets           = T.UI.Insets
local Box              = T.UI.Box
local TextStyle        = T.UI.TextStyle
local FlexItem         = T.UI.FlexItem

local mtSizePx         = getmetatable(T.UI.SizePx(0))
local mtSizePercent    = getmetatable(T.UI.SizePercent(0))
local mtBasisPx        = getmetatable(T.UI.BasisPx(0))
local mtBasisPercent   = getmetatable(T.UI.BasisPercent(0))
local mtLineHeightPx   = getmetatable(T.UI.LineHeightPx(0))
local mtLineHeightScl  = getmetatable(T.UI.LineHeightScale(1))
local mtMaxLines       = getmetatable(T.UI.MaxLines(1))

-- Facts
local SPAN_UNBOUNDED, BASELINE_NONE = T.Facts.SpanUnconstrained, T.Facts.NoBaseline
local SpanExact, SpanAtMost, BaselinePx = T.Facts.SpanExact, T.Facts.SpanAtMost, T.Facts.BaselinePx
local Constraint, Frame, Intrinsic, Measure = T.Facts.Constraint, T.Facts.Frame, T.Facts.Intrinsic, T.Facts.Measure
local mtSpanExact, mtSpanAtMost, mtBaselinePx = getmetatable(SpanExact(0)), getmetatable(SpanAtMost(0)), getmetatable(BaselinePx(0))

-- View (static UI flat command IR)
local K_RECT, K_TEXTBLOCK, K_PUSH_CLIP, K_POP_CLIP, K_PUSH_TX, K_POP_TX =
    T.View.Rect, T.View.TextBlock, T.View.PushClip, T.View.PopClip, T.View.PushTransform, T.View.PopTransform
local VCmd, Fragment, PlanOp, Plan = T.View.Cmd, T.View.Fragment, T.View.PlanOp, T.View.Plan
local PK_PLACE, PK_PUSH_CLIP, PK_POP_CLIP, PK_PUSH_TX, PK_POP_TX =
    T.View.PlaceFragment, T.View.PushClipPlan, T.View.PopClipPlan, T.View.PushTransformPlan, T.View.PopTransformPlan

-- Defaults
local ZERO_INSETS      = Insets(0, 0, 0, 0)
local AUTO_BOX         = Box(SIZE_AUTO, SIZE_AUTO, NO_MIN, NO_MIN, NO_MAX, NO_MAX)
local NULL_PACK        = ColorPack(0, 0, 0, 0)
local ONES_NUM_PACK    = NumPack(1, 1, 1, 1)
local ZERO_NUM_PACK    = NumPack(0, 0, 0, 0)
local WHITE_PACK       = ColorPack(0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff)
local DEFAULT_TEXTSTYLE = TextStyle(0, WHITE_PACK, LH_AUTO, TXT_START, TXT_NOWRAP, OV_VISIBLE, UNLIMITED_LINES)
local DEFAULT_STYLE    = Style(0, 0, 0, 0, 0, NULL_PACK, NULL_PACK, NULL_PACK, NULL_PACK, ZERO_NUM_PACK, ONES_NUM_PACK)

local mtChild          = getmetatable(FlexItem(T.UI.Spacer(AUTO_BOX), 0, 1, BASIS_AUTO, CROSS_AUTO, ZERO_INSETS))

-- Phase selection constants (integers for fast dispatch in paint loop)
local PHASE_IDLE       = 1
local PHASE_HOVERED    = 2
local PHASE_PRESSED    = 3
local PHASE_DRAGGING   = 4

-- ══════════════════════════════════════════════════════════════
--  PACK HELPERS
-- ══════════════════════════════════════════════════════════════

local function solid(rgba8)
    return ColorPack(rgba8, rgba8, rgba8, rgba8)
end
ui.solid = solid

local function solid_num(n)
    return NumPack(n, n, n, n)
end
ui.solid_num = solid_num

local function pick(pack, phase)
    if phase == 1 then return pack.idle end
    if phase == 2 then return pack.hovered end
    if phase == 3 then return pack.pressed end
    return pack.dragging
end

local function pointer_for_id(id, hot)
    if id == "" then return PHASE_IDLE end
    if hot.dragging and id == hot.dragging then return PHASE_DRAGGING end
    if hot.pressed and id == hot.pressed then return PHASE_PRESSED end
    if hot.hovered and id == hot.hovered then return PHASE_HOVERED end
    return PHASE_IDLE
end

-- ══════════════════════════════════════════════════════════════
--  DS RESOLVER
-- ══════════════════════════════════════════════════════════════

-- Lookup caches (weak on theme identity)
local surface_map_cache = setmetatable({}, { __mode = "k" })
local color_tok_cache   = setmetatable({}, { __mode = "k" })
local space_tok_cache   = setmetatable({}, { __mode = "k" })
local font_tok_cache    = setmetatable({}, { __mode = "k" })

local function build_map(theme, cache, field_name)
    local map = cache[theme]
    if map then return map end
    map = {}
    local list = theme[field_name]
    for i = 1, #list do
        map[list[i].name] = list[i]
    end
    cache[theme] = map
    return map
end

local function get_surface(theme, name)
    return build_map(theme, surface_map_cache, "surfaces")[name]
end

local function resolve_color_val(theme, val)
    local mt = getmetatable(val)
    if mt == DS_MT.ColorLit then return val.rgba8 end
    local map = build_map(theme, color_tok_cache, "colors")
    local b = map[val.name]
    return b and b.rgba8 or 0
end

local function resolve_space_val(theme, val)
    local mt = getmetatable(val)
    if mt == DS_MT.SpaceLit then return val.px end
    local map = build_map(theme, space_tok_cache, "spaces")
    local b = map[val.name]
    return b and b.px or 0
end

local function resolve_font_val(theme, val)
    local mt = getmetatable(val)
    if mt == DS_MT.FontLit then return val.font_id end
    local map = build_map(theme, font_tok_cache, "fonts")
    local b = map[val.name]
    return b and b.font_id or 0
end

local function resolve_scale_val(val)
    return val.n
end

-- Selector matching

local function match_fsel(fsel, focus)
    if fsel == ANY_FOCUS then return true end
    return fsel.f == focus
end

local function match_gsel(gsel, flags)
    if gsel == ANY_FLAGS then return true end
    local req = gsel.required
    for i = 1, #req do
        local found = false
        for j = 1, #flags do
            if req[i] == flags[j] then found = true; break end
        end
        if not found then return false end
    end
    return true
end

local function match_psel(psel, pointer)
    if psel == ANY_POINTER then return true end
    return psel.p == pointer
end

local function match_selector(sel, pointer, focus, flags)
    return match_psel(sel.pointer, pointer)
       and match_fsel(sel.focus, focus)
       and match_gsel(sel.flags, flags)
end

local function match_struct_sel(sel, focus, flags)
    return match_fsel(sel.focus, focus) and match_gsel(sel.flags, flags)
end

-- Core resolver

local POINTER_PHASES = { POINTER_IDLE, POINTER_HOVERED, POINTER_PRESSED, POINTER_DRAGGING }

local function resolve_style_impl(query)
    local theme = query.theme
    local surface = get_surface(theme, query.surface)
    if not surface then return DEFAULT_STYLE end

    local focus = query.focus
    local flags = query.flags

    -- Resolve struct rules
    local pad_h, pad_v, gap, border_w, font_id = 0, 0, 0, 0, 0
    local srules = surface.struct_rules
    for i = 1, #srules do
        local rule = srules[i]
        if match_struct_sel(rule.when, focus, flags) then
            local set = rule.set
            for j = 1, #set do
                local d = set[j]
                local mt = getmetatable(d)
                if     mt == DS_MT.SetPadH then pad_h = resolve_space_val(theme, d.val)
                elseif mt == DS_MT.SetPadV then pad_v = resolve_space_val(theme, d.val)
                elseif mt == DS_MT.SetGap then gap = resolve_space_val(theme, d.val)
                elseif mt == DS_MT.SetBorderWidth then border_w = resolve_space_val(theme, d.val)
                elseif mt == DS_MT.SetFont then font_id = resolve_font_val(theme, d.val)
                end
            end
        end
    end

    -- Resolve paint rules for each pointer phase
    local bg, fg, border, accent = {}, {}, {}, {}
    local radius, opacity = {}, {}
    local prules = surface.paint_rules

    for pi = 1, 4 do
        local pointer = POINTER_PHASES[pi]
        local bg_v, fg_v, border_v, accent_v = 0, 0, 0, 0
        local radius_v, opacity_v = 0, 1

        for i = 1, #prules do
            local rule = prules[i]
            if match_selector(rule.when, pointer, focus, flags) then
                local set = rule.set
                for j = 1, #set do
                    local d = set[j]
                    local mt = getmetatable(d)
                    if     mt == DS_MT.SetBg then bg_v = resolve_color_val(theme, d.val)
                    elseif mt == DS_MT.SetFg then fg_v = resolve_color_val(theme, d.val)
                    elseif mt == DS_MT.SetBorder then border_v = resolve_color_val(theme, d.val)
                    elseif mt == DS_MT.SetAccent then accent_v = resolve_color_val(theme, d.val)
                    elseif mt == DS_MT.SetRadius then radius_v = resolve_space_val(theme, d.val)
                    elseif mt == DS_MT.SetOpacity then opacity_v = resolve_scale_val(d.val)
                    end
                end
            end
        end

        bg[pi] = bg_v; fg[pi] = fg_v; border[pi] = border_v; accent[pi] = accent_v
        radius[pi] = radius_v; opacity[pi] = opacity_v
    end

    return Style(
        pad_h, pad_v, gap, border_w, font_id,
        ColorPack(bg[1], bg[2], bg[3], bg[4]),
        ColorPack(fg[1], fg[2], fg[3], fg[4]),
        ColorPack(border[1], border[2], border[3], border[4]),
        ColorPack(accent[1], accent[2], accent[3], accent[4]),
        NumPack(radius[1], radius[2], radius[3], radius[4]),
        NumPack(opacity[1], opacity[2], opacity[3], opacity[4]))
end

local resolve_style = pvm2.lower("ds.resolve_style", resolve_style_impl)

function ds.resolve(query)
    return resolve_style(query)
end

function ds.query(theme, surface_name, focus, flags)
    return Query(theme, surface_name, focus or FOCUS_BLURRED, flags or {})
end

-- ══════════════════════════════════════════════════════════════
--  DS CONVENIENCE API
-- ══════════════════════════════════════════════════════════════
do -- scope DS convenience

-- Value constructors
function ds.ctok(name) return T.DS.ColorTok(name) end
function ds.clit(rgba8) return T.DS.ColorLit(rgba8) end
function ds.stok(name) return T.DS.SpaceTok(name) end
function ds.slit(px) return T.DS.SpaceLit(px) end
function ds.ftok(name) return T.DS.FontTok(name) end
function ds.flit(id) return T.DS.FontLit(id) end
function ds.sclit(n) return T.DS.ScaleLit(n) end

-- Paint declaration constructors
function ds.bg(val) return T.DS.SetBg(val) end
function ds.fg(val) return T.DS.SetFg(val) end
function ds.border_color(val) return T.DS.SetBorder(val) end
function ds.accent(val) return T.DS.SetAccent(val) end
function ds.radius(val) return T.DS.SetRadius(val) end
function ds.opacity(val) return T.DS.SetOpacity(val) end

-- Struct declaration constructors
function ds.pad_h(val) return T.DS.SetPadH(val) end
function ds.pad_v(val) return T.DS.SetPadV(val) end
function ds.gap_decl(val) return T.DS.SetGap(val) end
function ds.border_w(val) return T.DS.SetBorderWidth(val) end
function ds.font(val) return T.DS.SetFont(val) end

-- Selector constructors
local POINTER_MAP = {
    idle = POINTER_IDLE, hovered = POINTER_HOVERED,
    pressed = POINTER_PRESSED, dragging = POINTER_DRAGGING,
}
local FOCUS_MAP = { blurred = FOCUS_BLURRED, focused = FOCUS_FOCUSED }
local FLAG_MAP = { active = FLAG_ACTIVE, disabled = FLAG_DISABLED, selected = FLAG_SELECTED }

function ds.sel(opts)
    if not opts then return Selector(ANY_POINTER, ANY_FOCUS, ANY_FLAGS) end
    local psel = ANY_POINTER
    if opts.pointer then psel = T.DS.WhenPointer(POINTER_MAP[opts.pointer]) end
    local fsel = ANY_FOCUS
    if opts.focus then fsel = T.DS.WhenFocus(FOCUS_MAP[opts.focus]) end
    local gsel = ANY_FLAGS
    if opts.flags then
        local f = {}
        for i = 1, #opts.flags do f[i] = FLAG_MAP[opts.flags[i]] end
        gsel = T.DS.RequireFlags(f)
    end
    return Selector(psel, fsel, gsel)
end

function ds.ssel(opts)
    if not opts then return StructSel(ANY_FOCUS, ANY_FLAGS) end
    local fsel = ANY_FOCUS
    if opts.focus then fsel = T.DS.WhenFocus(FOCUS_MAP[opts.focus]) end
    local gsel = ANY_FLAGS
    if opts.flags then
        local f = {}
        for i = 1, #opts.flags do f[i] = FLAG_MAP[opts.flags[i]] end
        gsel = T.DS.RequireFlags(f)
    end
    return StructSel(fsel, gsel)
end

function ds.paint_rule(sel, decls)
    return T.DS.PaintRule(sel, decls)
end

function ds.struct_rule(sel, decls)
    return T.DS.StructRule(sel, decls)
end

function ds.surface(name, paint_rules, struct_rules)
    return Surface(name, paint_rules or {}, struct_rules or {})
end

function ds.theme(name, opts)
    opts = opts or {}
    local colors, spaces, fonts, surfaces = {}, {}, {}, {}
    if opts.colors then
        for i = 1, #opts.colors do
            colors[i] = T.DS.ColorBinding(opts.colors[i][1], opts.colors[i][2])
        end
    end
    if opts.spaces then
        for i = 1, #opts.spaces do
            spaces[i] = T.DS.SpaceBinding(opts.spaces[i][1], opts.spaces[i][2])
        end
    end
    if opts.fonts then
        for i = 1, #opts.fonts do
            fonts[i] = T.DS.FontBinding(opts.fonts[i][1], opts.fonts[i][2])
        end
    end
    if opts.surfaces then surfaces = opts.surfaces end
    return Theme(name, colors, spaces, fonts, surfaces)
end

-- Expose singletons
ds.ACTIVE = FLAG_ACTIVE
ds.DISABLED = FLAG_DISABLED
ds.SELECTED = FLAG_SELECTED
ds.IDLE = POINTER_IDLE
ds.HOVERED = POINTER_HOVERED
ds.PRESSED = POINTER_PRESSED
ds.DRAGGING = POINTER_DRAGGING
ds.BLURRED = FOCUS_BLURRED
ds.FOCUSED = FOCUS_FOCUSED

end -- scope DS convenience

-- ══════════════════════════════════════════════════════════════
--  STATS / CACHES
-- ══════════════════════════════════════════════════════════════

local measure_cache = setmetatable({}, { __mode = "k" })
local compile_cache = setmetatable({}, { __mode = "k" })
local assemble_cache = setmetatable({}, { __mode = "k" })
local paint_compile_cache = setmetatable({}, { __mode = "k" })
local stats = {
    measure = { name = "uilib.measure", calls = 0, hits = 0 },
    compile = { name = "uilib.compile", calls = 0, hits = 0 },
    assemble = { name = "uilib.assemble", calls = 0, hits = 0 },
    paint_compile = { name = "uilib.paint_compile", calls = 0, hits = 0 },
}

-- ══════════════════════════════════════════════════════════════
--  FONT / TEXT HELPERS (wrapped in do...end to limit local slots)
-- ══════════════════════════════════════════════════════════════

local fonts = {}
local get_font, raw_text_width, raw_text_height, raw_text_baseline, resolve_line_height
local text_intrinsic_widths, shaped_text, shape_text, shape_cache
do

function ui.set_font(id, font) fonts[id] = font end

get_font = function(font_id)
    local f = fonts[font_id]
    if f then return f end
    local b = ui._backend
    if b and b.get_default_font then return b:get_default_font() end
    return nil
end

raw_text_width = function(font_id, text)
    local f = get_font(font_id)
    if f and f.getWidth then return f:getWidth(text) end
    return #text * 8
end

raw_text_height = function(font_id)
    local f = get_font(font_id)
    if f and f.getHeight then return f:getHeight() end
    return 14
end

raw_text_baseline = function(font_id)
    local f = get_font(font_id)
    if f then
        if f.getBaseline then return f:getBaseline() end
        if f.getAscent then return f:getAscent() end
        if f.getHeight then return f:getHeight() * 0.8 end
    end
    return raw_text_height(font_id) * 0.8
end

resolve_line_height = function(lh, font_id)
    local fh = raw_text_height(font_id)
    if lh == LH_AUTO then return fh end
    local mt = getmetatable(lh)
    if mt == mtLineHeightPx then return lh.px end
    if mt == mtLineHeightScl then return fh * lh.scale end
    return fh
end

local function split_lines(text)
    local out = {}
    if text == "" then return { "" } end
    local start = 1
    while true do
        local i = string.find(text, "\n", start, true)
        if not i then out[#out+1] = string.sub(text, start); break end
        out[#out+1] = string.sub(text, start, i-1)
        start = i + 1
    end
    return out
end

local function split_chars(s)
    local out, i, n = {}, 1, #s
    while i <= n do
        local b = string.byte(s, i)
        local len
        if not b then break
        elseif b < 0x80 then len = 1
        elseif b >= 0xC2 and b < 0xE0 then len = 2
        elseif b >= 0xE0 and b < 0xF0 then len = 3
        elseif b >= 0xF0 and b < 0xF5 then len = 4
        else len = 1 end
        out[#out+1] = string.sub(s, i, math.min(n, i + len - 1))
        i = i + len
    end
    if #out == 0 then out[1] = "" end
    return out
end

local function split_word_runs(s)
    local chars = split_chars(s)
    if #chars == 1 and chars[1] == "" then return { { text = "", is_space = false } } end
    local out = {}
    local run = chars[1]
    local is_space = run:match("%s") ~= nil
    for i = 2, #chars do
        local ch = chars[i]
        local ch_space = ch:match("%s") ~= nil
        if ch_space == is_space then run = run .. ch
        else
            out[#out+1] = { text = run, is_space = is_space }
            run = ch
            is_space = ch_space
        end
    end
    out[#out+1] = { text = run, is_space = is_space }
    return out
end

local function concat_chars(chars, i, j)
    if j < i then return "" end
    return table.concat(chars, "", i, j)
end

local function truncate_to_width(font_id, text, max_w)
    if raw_text_width(font_id, text) <= max_w then return text end
    local chars = split_chars(text)
    local lo, hi, best = 0, #chars, ""
    while lo <= hi do
        local mid = math.floor((lo+hi)/2)
        local s = concat_chars(chars, 1, mid)
        if raw_text_width(font_id, s) <= max_w then best = s; lo = mid+1
        else hi = mid-1 end
    end
    return best
end

local function truncate_with_ellipsis(font_id, text, max_w)
    local ell = "…"
    if raw_text_width(font_id, text) <= max_w then return text end
    if raw_text_width(font_id, ell) > max_w then return "" end
    local chars = split_chars(text)
    local lo, hi, best = 0, #chars, ell
    while lo <= hi do
        local mid = math.floor((lo+hi)/2)
        local s = concat_chars(chars, 1, mid) .. ell
        if raw_text_width(font_id, s) <= max_w then best = s; lo = mid+1
        else hi = mid-1 end
    end
    return best
end

local function wrap_paragraph(font_id, para, max_w, mode)
    if max_w == math.huge then return { para } end
    if para == "" then return { "" } end
    local chars = split_chars(para)
    local out = {}
    local line_start, last_break, idx = 1, nil, 1
    while idx <= #chars do
        local candidate = concat_chars(chars, line_start, idx)
        if line_start == idx or raw_text_width(font_id, candidate) <= max_w then
            if mode == TXT_WORDWRAP and chars[idx]:match("%s") then last_break = idx end
            idx = idx + 1
        else
            if mode == TXT_WORDWRAP and last_break and last_break >= line_start then
                out[#out+1] = concat_chars(chars, line_start, last_break)
                line_start = last_break + 1
                idx = line_start
            elseif idx > line_start then
                out[#out+1] = concat_chars(chars, line_start, idx - 1)
                line_start = idx
            else
                out[#out+1] = chars[idx]
                idx = idx + 1
                line_start = idx
            end
            last_break = nil
        end
    end
    if line_start <= #chars then out[#out+1] = concat_chars(chars, line_start, #chars) end
    if #out == 0 then out[1] = "" end
    return out
end

local function wordwrap_min_width(font_id, para)
    local runs = split_word_runs(para)
    local local_min = 0
    for i = 1, #runs do
        local run = runs[i]
        if run.is_space then
            local chars = split_chars(run.text)
            for j = 1, #chars do
                local w = raw_text_width(font_id, chars[j])
                if w > local_min then local_min = w end
            end
        else
            local w = raw_text_width(font_id, run.text)
            if w > local_min then local_min = w end
        end
    end
    return local_min
end

text_intrinsic_widths = function(style, text)
    local paragraphs = split_lines(text)
    local max_w, min_w = 0, 0
    for i = 1, #paragraphs do
        local para = paragraphs[i]
        local pw = raw_text_width(style.font_id, para)
        if pw > max_w then max_w = pw end
        local local_min
        if style.wrap == TXT_NOWRAP then local_min = pw
        elseif style.wrap == TXT_WORDWRAP then
            local_min = wordwrap_min_width(style.font_id, para)
        else
            local_min = 0
            local chars = split_chars(para)
            for j = 1, #chars do local w = raw_text_width(style.font_id, chars[j]); if w > local_min then local_min = w end end
        end
        if local_min > min_w then min_w = local_min end
    end
    return min_w, max_w
end

shape_cache = setmetatable({}, { __mode = "k" })

shape_text = function(style, text, max_w, max_h)
    max_w = max_w or math.huge; max_h = max_h or math.huge
    local line_h = resolve_line_height(style.line_height, style.font_id)
    local baseline = raw_text_baseline(style.font_id)
    local lines, paragraphs = {}, split_lines(text)
    if style.wrap == TXT_NOWRAP or max_w == math.huge then
        for i = 1, #paragraphs do lines[#lines+1] = paragraphs[i] end
    else
        for i = 1, #paragraphs do
            local wrapped = wrap_paragraph(style.font_id, paragraphs[i], max_w, style.wrap)
            for j = 1, #wrapped do lines[#lines+1] = wrapped[j] end
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
            if #lines > 0 and style.overflow == OV_ELLIPSIS then lines[1] = truncate_with_ellipsis(style.font_id, lines[1] or "", max_w)
            elseif #lines > 0 and style.overflow == OV_CLIP then
                lines[1] = truncate_to_width(style.font_id, lines[1] or "", max_w)
            end
        elseif limited and style.overflow == OV_ELLIPSIS and #lines > 0 then
            lines[#lines] = truncate_with_ellipsis(style.font_id, lines[#lines], max_w)
        end
    end
    local used_w = 0
    for i = 1, #lines do local w = raw_text_width(style.font_id, lines[i]); if w > used_w then used_w = w end end
    if max_w ~= math.huge and style.wrap ~= TXT_NOWRAP then used_w = math.min(used_w, max_w) end
    return { lines = lines, text = table.concat(lines, "\n"), used_w = used_w, used_h = #lines * line_h, line_h = line_h, baseline = baseline, line_count = #lines }
end

shaped_text = function(node, max_w, max_h)
    max_w = max_w or math.huge; max_h = max_h or math.huge
    local by_node = shape_cache[node]
    if not by_node then by_node = {}; shape_cache[node] = by_node end
    local by_w = by_node[max_w]
    if not by_w then by_w = {}; by_node[max_w] = by_w end
    local hit = by_w[max_h]
    if hit then return hit end
    local shaped = shape_text(node.style, node.text, max_w, max_h)
    by_w[max_h] = shaped
    return shaped
end
end -- do text helpers

-- ══════════════════════════════════════════════════════════════
--  POLICY / NUMERIC HELPERS
-- ══════════════════════════════════════════════════════════════

local INF = math.huge
local function clamp(v, lo, hi) if lo and v < lo then v = lo end; if hi and v > hi then v = hi end; return v end
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

local function box_min_value(minv) if minv == NO_MIN then return 0 end; return minv.px end
local function box_max_value(maxv) if maxv == NO_MAX then return INF end; return maxv.px end

local function resolve_size_value(spec, available, content_value)
    if spec == SIZE_AUTO or spec == SIZE_CONTENT then return content_value end
    local mt = getmetatable(spec)
    if mt == mtSizePx then return spec.px end
    if mt == mtSizePercent then if available ~= INF then return available * spec.ratio end; return content_value end
    return content_value
end

local function resolve_basis_value(spec, available, content_value)
    if spec == BASIS_AUTO or spec == BASIS_CONTENT then return content_value end
    local mt = getmetatable(spec)
    if mt == mtBasisPx then return spec.px end
    if mt == mtBasisPercent then if available ~= INF then return available * spec.ratio end; return content_value end
    return content_value
end

local function baseline_num(b) if b == BASELINE_NONE or b == nil then return nil end; if getmetatable(b) == mtBaselinePx then return b.px end; return nil end
local function make_baseline(px) if not px then return BASELINE_NONE end; return BaselinePx(px) end
local function is_row_axis(axis) return axis == AXIS_ROW or axis == AXIS_ROW_REV end
local function is_reverse_axis(axis) return axis == AXIS_ROW_REV or axis == AXIS_COL_REV end
local function is_wrap_reverse(wrap) return wrap == WRAP_REV end

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

local function main_size_of(measure, axis) return is_row_axis(axis) and measure.used_w or measure.used_h end
local function cross_size_of(measure, axis) return is_row_axis(axis) and measure.used_h or measure.used_w end
local function intrinsic_min_main(intr, axis) return is_row_axis(axis) and intr.min_w or intr.min_h end
local function intrinsic_max_main(intr, axis) return is_row_axis(axis) and intr.max_w or intr.max_h end
local function intrinsic_min_cross(intr, axis) return is_row_axis(axis) and intr.min_h or intr.min_w end
local function intrinsic_max_cross(intr, axis) return is_row_axis(axis) and intr.max_h or intr.max_w end

local function exact_or_atmost(px, exact)
    if px == INF then return SPAN_UNBOUNDED end
    if exact then return SpanExact(px) end
    return SpanAtMost(px)
end

local function box_content_constraint(box, outer)
    local avail_w = span_available(outer.w)
    local avail_h = span_available(outer.h)
    local aw, ah = avail_w, avail_h
    local exact_w, exact_h = false, false
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
    local min_w, min_h = box_min_value(box.min_w), box_min_value(box.min_h)
    local max_w, max_h = box_max_value(box.max_w), box_max_value(box.max_h)
    local used_w = outer_exact_w and (box.w == SIZE_AUTO or box.w == SIZE_CONTENT or getmetatable(box.w) == mtSizePercent) and aw or resolve_size_value(box.w, aw, raw.used_w)
    local used_h = outer_exact_h and (box.h == SIZE_AUTO or box.h == SIZE_CONTENT or getmetatable(box.h) == mtSizePercent) and ah or resolve_size_value(box.h, ah, raw.used_h)
    local intr_min_w, intr_min_h = raw.min_w, raw.min_h
    local intr_max_w, intr_max_h = raw.max_w, raw.max_h
    local mtw = getmetatable(box.w)
    if mtw == mtSizePx then intr_min_w, intr_max_w = box.w.px, box.w.px
    elseif mtw == mtSizePercent and aw ~= INF then intr_min_w, intr_max_w = aw * box.w.ratio, aw * box.w.ratio end
    local mth = getmetatable(box.h)
    if mth == mtSizePx then intr_min_h, intr_max_h = box.h.px, box.h.px
    elseif mth == mtSizePercent and ah ~= INF then intr_min_h, intr_max_h = ah * box.h.ratio, ah * box.h.ratio end
    intr_min_w = clamp(intr_min_w, min_w, max_w); intr_min_h = clamp(intr_min_h, min_h, max_h)
    intr_max_w = clamp(intr_max_w, min_w, max_w); intr_max_h = clamp(intr_max_h, min_h, max_h)
    used_w = clamp(used_w, min_w, max_w); used_h = clamp(used_h, min_h, max_h)
    if aw ~= INF then used_w = math.min(used_w, aw) end
    if ah ~= INF then used_h = math.min(used_h, ah) end
    return Measure(outer, Intrinsic(intr_min_w, intr_min_h, intr_max_w, intr_max_h, raw.baseline or BASELINE_NONE), used_w, used_h, raw.baseline or BASELINE_NONE)
end

local function available_constraint_from_frame(frame) return Constraint(SpanAtMost(frame.w), SpanAtMost(frame.h)) end
local function exact_constraint_from_frame(frame) return Constraint(SpanExact(frame.w), SpanExact(frame.h)) end

-- ══════════════════════════════════════════════════════════════
--  CONVENIENCE API (typed constructors)
-- ══════════════════════════════════════════════════════════════

ui.AUTO = SIZE_AUTO
ui.CONTENT = SIZE_CONTENT
function ui.px(n) return T.UI.SizePx(n) end
function ui.percent(r) return T.UI.SizePercent(r) end
function ui.basis_px(n) return T.UI.BasisPx(n) end
function ui.basis_percent(r) return T.UI.BasisPercent(r) end
function ui.min_px(n) return T.UI.MinPx(n) end
function ui.max_px(n) return T.UI.MaxPx(n) end
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
    return Box(opts.w or SIZE_AUTO, opts.h or SIZE_AUTO, opts.min_w or NO_MIN, opts.min_h or NO_MIN, opts.max_w or NO_MAX, opts.max_h or NO_MAX)
end

function ui.text_style(opts)
    opts = opts or {}
    return TextStyle(opts.font_id or 0, opts.color or WHITE_PACK, opts.line_height or LH_AUTO, opts.align or TXT_START, opts.wrap or TXT_NOWRAP, opts.overflow or OV_VISIBLE, opts.line_limit or UNLIMITED_LINES)
end

function ui.item(node, opts)
    opts = opts or {}
    return FlexItem(node, opts.grow or 0, opts.shrink == nil and 1 or opts.shrink, opts.basis or BASIS_AUTO, opts.align or CROSS_AUTO, opts.margin or ZERO_INSETS)
end

function ui.grow(factor, node, opts)
    opts = opts or {}; opts.grow = factor; if opts.shrink == nil then opts.shrink = 1 end
    return ui.item(node, opts)
end

local function ensure_child(x) if getmetatable(x) == mtChild then return x end; return ui.item(x) end
local function wrap_children(xs) local out = {}; for i = 1, #xs do out[i] = ensure_child(xs[i]) end; return out end

function ui.row(gap, children, opts)
    opts = opts or {}
    return T.UI.Flex(AXIS_ROW, opts.wrap or WRAP_NO, gap or 0, opts.gap_cross or 0, opts.justify or MAIN_START, opts.align or CROSS_STRETCH, opts.align_content or CONTENT_START, ui.box(opts.box), wrap_children(children))
end

function ui.col(gap, children, opts)
    opts = opts or {}
    return T.UI.Flex(AXIS_COL, opts.wrap or WRAP_NO, gap or 0, opts.gap_cross or 0, opts.justify or MAIN_START, opts.align or CROSS_STRETCH, opts.align_content or CONTENT_START, ui.box(opts.box), wrap_children(children))
end

function ui.flex(opts)
    opts = opts or {}
    return T.UI.Flex(opts.axis or AXIS_ROW, opts.wrap or WRAP_NO, opts.gap_main or 0, opts.gap_cross or 0, opts.justify or MAIN_START, opts.align_items or CROSS_STRETCH, opts.align_content or CONTENT_START, ui.box(opts.box), wrap_children(opts.children or {}))
end

function ui.pad(insets, child, box) return T.UI.Pad(insets or ZERO_INSETS, box or AUTO_BOX, child) end
function ui.stack(children, box) return T.UI.Stack(box or AUTO_BOX, children or {}) end
function ui.clip(child, box) return T.UI.Clip(box or AUTO_BOX, child) end
function ui.transform(tx, ty, child, box) return T.UI.Transform(tx or 0, ty or 0, box or AUTO_BOX, child) end
function ui.sized(box, child) return T.UI.Sized(box or AUTO_BOX, child) end
function ui.rect(tag, fill, box) return T.UI.Rect(tag or "", box or AUTO_BOX, fill or NULL_PACK) end
function ui.text(tag, text, style, box) return T.UI.Text(tag or "", box or AUTO_BOX, style or DEFAULT_TEXTSTYLE, text or "") end
function ui.spacer(box) return T.UI.Spacer(box or AUTO_BOX) end

local PAINT_MT = {}
do
    PAINT_MT.NumRef = getmetatable(T.Runtime.NumRef(""))
    PAINT_MT.TextRef = getmetatable(T.Runtime.TextRef(""))
    PAINT_MT.ColorRef = getmetatable(T.Runtime.ColorRef(""))
    PAINT_MT.ColorPack = getmetatable(WHITE_PACK)
end

local function paint_scalar(v)
    if type(v) == "number" then return T.Paint.ScalarLit(v) end
    if not v then return T.Paint.ScalarLit(0) end
    if getmetatable(v) == PAINT_MT.NumRef then return T.Paint.ScalarFromRef(v) end
    return v
end

local function paint_text_value(v)
    if type(v) == "string" then return T.Paint.TextLit(v) end
    if not v then return T.Paint.TextLit("") end
    if getmetatable(v) == PAINT_MT.TextRef then return T.Paint.TextFromRef(v) end
    return v
end

local function paint_color_value(v)
    if type(v) == "number" then return T.Paint.ColorPackLit(solid(v)) end
    if not v then return T.Paint.ColorPackLit(NULL_PACK) end
    local mt = getmetatable(v)
    if mt == PAINT_MT.ColorPack then return T.Paint.ColorPackLit(v) end
    if mt == PAINT_MT.ColorRef then return T.Paint.ColorFromRef(v) end
    return v
end

function ui.num_ref(name) return T.Runtime.NumRef(name or "") end
function ui.text_ref(name) return T.Runtime.TextRef(name or "") end
function ui.color_ref(name) return T.Runtime.ColorRef(name or "") end

function ui.paint_group(children) return T.Paint.Group(children or {}) end
function ui.paint_clip(x, y, w, h, child) return T.Paint.ClipRegion(paint_scalar(x), paint_scalar(y), paint_scalar(w), paint_scalar(h), child) end
function ui.paint_transform(tx, ty, child) return T.Paint.Translate(paint_scalar(tx), paint_scalar(ty), child) end
function ui.paint_rect(tag, x, y, w, h, color) return T.Paint.FillRect(tag or "", paint_scalar(x), paint_scalar(y), paint_scalar(w), paint_scalar(h), paint_color_value(color)) end
function ui.paint_stroke(tag, x, y, w, h, thickness, color) return T.Paint.StrokeRect(tag or "", paint_scalar(x), paint_scalar(y), paint_scalar(w), paint_scalar(h), paint_scalar(thickness or 1), paint_color_value(color)) end
function ui.paint_line(tag, x1, y1, x2, y2, thickness, color) return T.Paint.Line(tag or "", paint_scalar(x1), paint_scalar(y1), paint_scalar(x2), paint_scalar(y2), paint_scalar(thickness or 1), paint_color_value(color)) end
function ui.paint_text(tag, x, y, w, h, style, text, color)
    style = style or DEFAULT_TEXTSTYLE
    return T.Paint.Text(tag or "", paint_scalar(x), paint_scalar(y), paint_scalar(w), paint_scalar(h),
        style.font_id, paint_color_value(color or style.color), style.line_height,
        style.align, style.wrap, style.overflow, style.line_limit, paint_text_value(text))
end

function ui.plan(ops) return Plan(ops or {}) end
function ui.place_fragment(x, y, fragment) return PlanOp(PK_PLACE, x or 0, y or 0, 0, 0, 0, 0, fragment) end
function ui.push_clip_plan(x, y, w, h) return PlanOp(PK_PUSH_CLIP, x or 0, y or 0, w or 0, h or 0, 0, 0, nil) end
function ui.pop_clip_plan(x, y, w, h) return PlanOp(PK_POP_CLIP, x or 0, y or 0, w or 0, h or 0, 0, 0, nil) end
function ui.push_transform_plan(tx, ty) return PlanOp(PK_PUSH_TX, 0, 0, 0, 0, tx or 0, ty or 0, nil) end
function ui.pop_transform_plan(tx, ty) return PlanOp(PK_POP_TX, 0, 0, 0, 0, tx or 0, ty or 0, nil) end

-- Expose layout singletons
ui.AXIS_ROW = AXIS_ROW; ui.AXIS_ROW_REVERSE = AXIS_ROW_REV; ui.AXIS_COL = AXIS_COL; ui.AXIS_COL_REVERSE = AXIS_COL_REV
ui.WRAP_NO = WRAP_NO; ui.WRAP = WRAP_YES; ui.WRAP_REVERSE = WRAP_REV
ui.MAIN_START = MAIN_START; ui.MAIN_END = MAIN_END; ui.MAIN_CENTER = MAIN_CENTER
ui.MAIN_SPACE_BETWEEN = MAIN_BETWEEN; ui.MAIN_SPACE_AROUND = MAIN_AROUND; ui.MAIN_SPACE_EVENLY = MAIN_EVENLY
ui.CROSS_AUTO = CROSS_AUTO; ui.CROSS_START = CROSS_START; ui.CROSS_END = CROSS_END
ui.CROSS_CENTER = CROSS_CENTER; ui.CROSS_STRETCH = CROSS_STRETCH; ui.CROSS_BASELINE = CROSS_BASELINE
ui.CONTENT_START = CONTENT_START; ui.CONTENT_END = CONTENT_END; ui.CONTENT_CENTER = CONTENT_CENTER
ui.CONTENT_STRETCH = CONTENT_STRETCH; ui.CONTENT_SPACE_BETWEEN = CONTENT_BETWEEN
ui.CONTENT_SPACE_AROUND = CONTENT_AROUND; ui.CONTENT_SPACE_EVENLY = CONTENT_EVENLY
ui.TEXT_NOWRAP = TXT_NOWRAP; ui.TEXT_WORDWRAP = TXT_WORDWRAP; ui.TEXT_CHARWRAP = TXT_CHARWRAP
ui.TEXT_START = TXT_START; ui.TEXT_CENTER = TXT_CENTER; ui.TEXT_END = TXT_END; ui.TEXT_JUSTIFY = TXT_JUSTIFY
ui.OVERFLOW_VISIBLE = OV_VISIBLE; ui.OVERFLOW_CLIP = OV_CLIP; ui.OVERFLOW_ELLIPSIS = OV_ELLIPSIS
ui.LINEHEIGHT_AUTO = LH_AUTO; ui.UNLIMITED_LINES = UNLIMITED_LINES

-- ══════════════════════════════════════════════════════════════
--  MEASUREMENT BOUNDARY
-- ══════════════════════════════════════════════════════════════

local function measure_child(node, constraint) return ui.measure(node, constraint) end
local function raw_measure_zero() return { min_w = 0, min_h = 0, max_w = 0, max_h = 0, used_w = 0, used_h = 0, baseline = BASELINE_NONE } end
local function raw_from_child_measure(child) return { min_w = child.intrinsic.min_w, min_h = child.intrinsic.min_h, max_w = child.intrinsic.max_w, max_h = child.intrinsic.max_h, used_w = child.used_w, used_h = child.used_h, baseline = child.baseline } end

local function passthrough_measure(box, child, constraint)
    local inner = box_content_constraint(box, constraint)
    local m = measure_child(child, inner)
    return apply_box_measure(box, constraint, raw_from_child_measure(m))
end

function T.UI.Rect:_measure_uncached(constraint) return apply_box_measure(self.box, constraint, raw_measure_zero()) end
function T.UI.Spacer:_measure_uncached(constraint) return apply_box_measure(self.box, constraint, raw_measure_zero()) end

function T.UI.Text:_measure_uncached(constraint)
    local inner = box_content_constraint(self.box, constraint)
    local max_w = span_available(inner.w); local max_h = span_available(inner.h)
    local shape = shaped_text(self, max_w, max_h)
    local min_w, max_intr_w = text_intrinsic_widths(self.style, self.text)
    local raw = { min_w = min_w, min_h = resolve_line_height(self.style.line_height, self.style.font_id), max_w = max_intr_w, max_h = shape.used_h, used_w = shape.used_w, used_h = shape.used_h, baseline = make_baseline(shape.baseline) }
    return apply_box_measure(self.box, constraint, raw)
end

function T.UI.Sized:_measure_uncached(constraint) return passthrough_measure(self.box, self.child, constraint) end
function T.UI.Transform:_measure_uncached(constraint) return passthrough_measure(self.box, self.child, constraint) end
function T.UI.Clip:_measure_uncached(constraint) return passthrough_measure(self.box, self.child, constraint) end

function T.UI.Pad:_measure_uncached(constraint)
    local inner = box_content_constraint(self.box, constraint)
    inner = Constraint(sub_span(inner.w, self.insets.l + self.insets.r), sub_span(inner.h, self.insets.t + self.insets.b))
    local child = measure_child(self.child, inner)
    local raw = { min_w = child.intrinsic.min_w + self.insets.l + self.insets.r, min_h = child.intrinsic.min_h + self.insets.t + self.insets.b, max_w = child.intrinsic.max_w + self.insets.l + self.insets.r, max_h = child.intrinsic.max_h + self.insets.t + self.insets.b, used_w = child.used_w + self.insets.l + self.insets.r, used_h = child.used_h + self.insets.t + self.insets.b, baseline = child.baseline }
    return apply_box_measure(self.box, constraint, raw)
end

function T.UI.Stack:_measure_uncached(constraint)
    local inner = box_content_constraint(self.box, constraint)
    local raw = raw_measure_zero(); raw.max_w, raw.max_h = 0, 0
    for i = 1, #self.children do
        local m = measure_child(self.children[i], inner)
        raw.min_w = max_of(raw.min_w, m.intrinsic.min_w); raw.min_h = max_of(raw.min_h, m.intrinsic.min_h)
        raw.max_w = max_of(raw.max_w, m.intrinsic.max_w); raw.max_h = max_of(raw.max_h, m.intrinsic.max_h)
        raw.used_w = max_of(raw.used_w, m.used_w); raw.used_h = max_of(raw.used_h, m.used_h)
    end
    return apply_box_measure(self.box, constraint, raw)
end

-- Flex measurement (collect infos, distribute, wrap)

local function flex_collect_infos(node, constraint)
    local axis = node.axis
    local avail_w = span_available(constraint.w)
    local avail_h = span_available(constraint.h)
    local avail_main = is_row_axis(axis) and avail_w or avail_h
    local infos = {}
    for i = 1, #node.children do
        local item = node.children[i]
        local m = measure_child(item.node, constraint)
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

function T.UI.Flex:_measure_uncached(constraint)
    local inner = box_content_constraint(self.box, constraint)
    local infos, avail_main = flex_collect_infos(self, inner)
    local axis = self.axis
    local raw = { min_w = 0, min_h = 0, max_w = 0, max_h = 0, used_w = 0, used_h = 0, baseline = BASELINE_NONE }
    if #infos == 0 then return apply_box_measure(self.box, constraint, raw) end

    if self.wrap == WRAP_NO or avail_main == INF then
        local main_sum_min, main_sum_nat, cross_min, cross_nat = 0, 0, 0, 0
        for i = 1, #infos do local inf = infos[i]
            main_sum_min = main_sum_min + inf.min_main + inf.main_margin_start + inf.main_margin_end
            main_sum_nat = main_sum_nat + inf.base + inf.main_margin_start + inf.main_margin_end
            cross_min = max_of(cross_min, inf.min_cross + inf.cross_margin_start + inf.cross_margin_end)
            cross_nat = max_of(cross_nat, cross_size_of(inf.measure, axis) + inf.cross_margin_start + inf.cross_margin_end)
        end
        main_sum_min = main_sum_min + self.gap_main * math.max(0, #infos-1)
        main_sum_nat = main_sum_nat + self.gap_main * math.max(0, #infos-1)
        if is_row_axis(axis) then raw.min_w, raw.max_w, raw.used_w = main_sum_min, main_sum_nat, math.min(main_sum_nat, avail_main); raw.min_h, raw.max_h, raw.used_h = cross_min, cross_nat, cross_nat
        else raw.min_w, raw.max_w, raw.used_w = cross_min, cross_nat, cross_nat; raw.min_h, raw.max_h, raw.used_h = main_sum_min, main_sum_nat, math.min(main_sum_nat, avail_main) end
    else
        local lines, cur, cur_used = {}, {}, 0
        for i = 1, #infos do local inf = infos[i]; local need = inf.base + inf.main_margin_start + inf.main_margin_end; if #cur > 0 then need = need + self.gap_main end
            if #cur > 0 and cur_used + need > avail_main then lines[#lines+1] = cur; cur, cur_used = {}, 0; need = inf.base + inf.main_margin_start + inf.main_margin_end end
            cur[#cur+1] = i; cur_used = cur_used + need
        end
        if #cur > 0 then lines[#lines+1] = cur end
        local used_cross, max_main, min_line_main = 0, 0, 0
        for li = 1, #lines do local line = lines[li]; local lu, lc = 0, 0
            for j = 1, #line do local inf = infos[line[j]]; lu = lu + inf.base + inf.main_margin_start + inf.main_margin_end; if j > 1 then lu = lu + self.gap_main end
                lc = max_of(lc, cross_size_of(inf.measure, axis) + inf.cross_margin_start + inf.cross_margin_end) end
            max_main = max_of(max_main, lu); used_cross = used_cross + lc; if li > 1 then used_cross = used_cross + self.gap_cross end
        end
        for i = 1, #infos do local need = infos[i].min_main + infos[i].main_margin_start + infos[i].main_margin_end; if need > min_line_main then min_line_main = need end end
        if is_row_axis(axis) then raw.min_w, raw.max_w, raw.used_w = min_line_main, max_main, math.min(max_main, avail_main); raw.min_h, raw.max_h, raw.used_h = used_cross, used_cross, used_cross
        else raw.min_w, raw.max_w, raw.used_w = used_cross, used_cross, used_cross; raw.min_h, raw.max_h, raw.used_h = min_line_main, max_main, math.min(max_main, avail_main) end
    end
    return apply_box_measure(self.box, constraint, raw)
end

function ui.measure(node, constraint)
    stats.measure.calls = stats.measure.calls + 1
    constraint = constraint or Constraint(SPAN_UNBOUNDED, SPAN_UNBOUNDED)
    local by_node = measure_cache[node]
    if by_node then local hit = by_node[constraint]; if hit then stats.measure.hits = stats.measure.hits + 1; return hit end
    else by_node = setmetatable({}, { __mode = "k" }); measure_cache[node] = by_node end
    local out = node:_measure_uncached(constraint)
    by_node[constraint] = out
    return out
end

-- ══════════════════════════════════════════════════════════════
--  EMISSION / COMPILE / PAINT / HIT (loaded as separate chunk)
-- ══════════════════════════════════════════════════════════════
local function wipe(t)
    if not t then return end
    for k in pairs(t) do t[k] = nil end
end

function ui.clear_cache()
    -- Wipe in place: exec module holds refs to these same table objects
    wipe(measure_cache); wipe(compile_cache); wipe(assemble_cache); wipe(paint_compile_cache)
    wipe(shape_cache)
    wipe(surface_map_cache); wipe(color_tok_cache)
    wipe(space_tok_cache); wipe(font_tok_cache)
    resolve_style:reset()
    stats.measure.calls, stats.measure.hits = 0, 0
    stats.compile.calls, stats.compile.hits = 0, 0
    stats.assemble.calls, stats.assemble.hits = 0, 0
    stats.paint_compile.calls, stats.paint_compile.hits = 0, 0
end

function ui.report()
    local function line(s) local rate = (s.calls > 0) and math.floor((s.hits / s.calls) * 100 + 0.5) or 0; return string.format("%-20s calls=%-6d hits=%-6d rate=%d%%", s.name, s.calls, s.hits, rate) end
    local rs = resolve_style:stats()
    return table.concat({ line(stats.measure), line(stats.compile), line(stats.assemble), line(stats.paint_compile), string.format("%-20s calls=%-6d hits=%-6d rate=%d%%", rs.name, rs.calls, rs.hits, (rs.calls > 0) and math.floor((rs.hits / rs.calls) * 100 + 0.5) or 0) }, "\n")
end

require("uilib_exec")(ui, T, {
    NULL_PACK = NULL_PACK, TXT_START = TXT_START, TXT_NOWRAP = TXT_NOWRAP,
    TXT_CENTER = TXT_CENTER, TXT_END = TXT_END, TXT_JUSTIFY = TXT_JUSTIFY,
    OV_VISIBLE = OV_VISIBLE, OV_CLIP = OV_CLIP, OV_ELLIPSIS = OV_ELLIPSIS,
    LH_AUTO = LH_AUTO, UNLIMITED_LINES = UNLIMITED_LINES, INF = INF, BASELINE_NONE = BASELINE_NONE,
    K_RECT = K_RECT, K_TEXTBLOCK = K_TEXTBLOCK, K_PUSH_CLIP = K_PUSH_CLIP,
    K_POP_CLIP = K_POP_CLIP, K_PUSH_TX = K_PUSH_TX, K_POP_TX = K_POP_TX,
    VCmd = VCmd, Fragment = Fragment, PlanOp = PlanOp, Plan = Plan,
    PK_PLACE = PK_PLACE, PK_PUSH_CLIP = PK_PUSH_CLIP, PK_POP_CLIP = PK_POP_CLIP,
    PK_PUSH_TX = PK_PUSH_TX, PK_POP_TX = PK_POP_TX,
    SpanExact = SpanExact, SpanAtMost = SpanAtMost, Frame = Frame, Constraint = Constraint,
    SPAN_UNBOUNDED = SPAN_UNBOUNDED,
    AXIS_ROW = AXIS_ROW, AXIS_ROW_REV = AXIS_ROW_REV, AXIS_COL = AXIS_COL, AXIS_COL_REV = AXIS_COL_REV,
    WRAP_NO = WRAP_NO, WRAP_REV = WRAP_REV,
    MAIN_START = MAIN_START, MAIN_END = MAIN_END, MAIN_CENTER = MAIN_CENTER,
    MAIN_BETWEEN = MAIN_BETWEEN, MAIN_AROUND = MAIN_AROUND, MAIN_EVENLY = MAIN_EVENLY,
    CROSS_AUTO = CROSS_AUTO, CROSS_START = CROSS_START, CROSS_END = CROSS_END,
    CROSS_CENTER = CROSS_CENTER, CROSS_STRETCH = CROSS_STRETCH, CROSS_BASELINE = CROSS_BASELINE,
    CONTENT_START = CONTENT_START, CONTENT_END = CONTENT_END, CONTENT_CENTER = CONTENT_CENTER,
    CONTENT_STRETCH = CONTENT_STRETCH, CONTENT_BETWEEN = CONTENT_BETWEEN,
    CONTENT_AROUND = CONTENT_AROUND, CONTENT_EVENLY = CONTENT_EVENLY,
    resolve_line_height = resolve_line_height, raw_text_height = raw_text_height,
    get_font = get_font, shaped_text = shaped_text, shape_text = shape_text,
    text_intrinsic_widths = text_intrinsic_widths, make_baseline = make_baseline,
    pick = pick, pointer_for_id = pointer_for_id,
    resolve_style = resolve_style,
}, stats, measure_cache, compile_cache, assemble_cache, paint_compile_cache)

return ui
