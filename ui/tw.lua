local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local S = T.Style

local M = {}

local DEFAULT_STATE_COND = S.StateCond(S.ReqAny, S.ReqAny, S.ReqAny, S.ReqAny, S.ReqAny)
local DEFAULT_COND = S.Cond(S.AnyBp, S.AnyScheme, S.AnyMotion, DEFAULT_STATE_COND)
local NO_STATE = S.State(false, false, false, false, false)

local function classof(v)
    return pvm.classof(v)
end

local function is_token(v)
    return classof(v) == S.Token
end

local function is_group(v)
    return classof(v) == S.Group
end

local function is_token_list(v)
    return classof(v) == S.TokenList
end

local function token(atom, cond)
    return S.Token(cond or DEFAULT_COND, atom)
end

local function clone_state_cond(state_cond, hovered, focused, active, selected, disabled)
    state_cond = state_cond or DEFAULT_STATE_COND
    return S.StateCond(
        hovered or state_cond.hovered,
        focused or state_cond.focused,
        active or state_cond.active,
        selected or state_cond.selected,
        disabled or state_cond.disabled
    )
end

local function clone_cond(cond, bp, scheme, motion, state)
    return S.Cond(bp or cond.bp, scheme or cond.scheme, motion or cond.motion, state or cond.state)
end

local function collect_tokens(value, out)
    if value == nil or value == false then
        return
    end

    if is_token(value) then
        out[#out + 1] = value
        return
    end

    if is_group(value) or is_token_list(value) then
        local items = value.items
        for i = 1, #items do
            out[#out + 1] = items[i]
        end
        return
    end

    if type(value) == "table" and not classof(value) then
        for i = 1, #value do
            collect_tokens(value[i], out)
        end
        return
    end

    error("expected Style.Token, Style.Group, Style.TokenList, or token array", 3)
end

local function map_cond(value, bp, scheme, motion)
    if value == nil or value == false then
        return value
    end

    if is_token(value) then
        return S.Token(clone_cond(value.cond, bp, scheme, motion), value.atom)
    end

    if is_group(value) then
        local src = value.items
        local out = {}
        for i = 1, #src do
            out[i] = map_cond(src[i], bp, scheme, motion)
        end
        return S.Group(out)
    end

    if is_token_list(value) then
        local src = value.items
        local out = {}
        for i = 1, #src do
            out[i] = map_cond(src[i], bp, scheme, motion)
        end
        return S.TokenList(out)
    end

    if type(value) == "table" and not classof(value) then
        local out = {}
        for i = 1, #value do
            collect_tokens(map_cond(value[i], bp, scheme, motion), out)
        end
        return S.Group(out)
    end

    error("expected Style.Token, Style.Group, Style.TokenList, or token array", 2)
end

function M.group(items)
    local out = {}
    collect_tokens(items, out)
    return S.Group(out)
end

function M.list(items)
    local out = {}
    collect_tokens(items, out)
    return S.TokenList(out)
end

local space_lookup = {
    ["0"] = S.S0, [0] = S.S0,
    ["0.5"] = S.S0_5, [0.5] = S.S0_5,
    ["1"] = S.S1, [1] = S.S1,
    ["1.5"] = S.S1_5, [1.5] = S.S1_5,
    ["2"] = S.S2, [2] = S.S2,
    ["2.5"] = S.S2_5, [2.5] = S.S2_5,
    ["3"] = S.S3, [3] = S.S3,
    ["3.5"] = S.S3_5, [3.5] = S.S3_5,
    ["4"] = S.S4, [4] = S.S4,
    ["5"] = S.S5, [5] = S.S5,
    ["6"] = S.S6, [6] = S.S6,
    ["7"] = S.S7, [7] = S.S7,
    ["8"] = S.S8, [8] = S.S8,
    ["9"] = S.S9, [9] = S.S9,
    ["10"] = S.S10, [10] = S.S10,
    ["11"] = S.S11, [11] = S.S11,
    ["12"] = S.S12, [12] = S.S12,
    ["14"] = S.S14, [14] = S.S14,
    ["16"] = S.S16, [16] = S.S16,
    ["20"] = S.S20, [20] = S.S20,
    ["24"] = S.S24, [24] = S.S24,
    ["28"] = S.S28, [28] = S.S28,
    ["32"] = S.S32, [32] = S.S32,
    ["36"] = S.S36, [36] = S.S36,
    ["40"] = S.S40, [40] = S.S40,
    ["44"] = S.S44, [44] = S.S44,
    ["48"] = S.S48, [48] = S.S48,
    ["52"] = S.S52, [52] = S.S52,
    ["56"] = S.S56, [56] = S.S56,
    ["60"] = S.S60, [60] = S.S60,
    ["64"] = S.S64, [64] = S.S64,
    ["72"] = S.S72, [72] = S.S72,
    ["80"] = S.S80, [80] = S.S80,
    ["96"] = S.S96, [96] = S.S96,
    ["px"] = S.SPx,
}

local fraction_lookup = {
    ["1/2"] = S.F1_2,
    ["1/3"] = S.F1_3,
    ["2/3"] = S.F2_3,
    ["1/4"] = S.F1_4,
    ["2/4"] = S.F2_4,
    ["3/4"] = S.F3_4,
    ["1/5"] = S.F1_5,
    ["2/5"] = S.F2_5,
    ["3/5"] = S.F3_5,
    ["4/5"] = S.F4_5,
    ["1/6"] = S.F1_6,
    ["2/6"] = S.F2_6,
    ["3/6"] = S.F3_6,
    ["4/6"] = S.F4_6,
    ["5/6"] = S.F5_6,
    ["full"] = S.FFull,
}

local shade_lookup = {
    [50] = S.S50,
    [100] = S.S100,
    [200] = S.S200,
    [300] = S.S300,
    [400] = S.S400,
    [500] = S.S500,
    [600] = S.S600,
    [700] = S.S700,
    [800] = S.S800,
    [900] = S.S900,
    [950] = S.S950,
}

local scale_lookup = {
    slate = S.Slate,
    gray = S.Gray,
    zinc = S.Zinc,
    neutral = S.Neutral,
    stone = S.Stone,
    red = S.Red,
    orange = S.Orange,
    amber = S.Amber,
    yellow = S.Yellow,
    lime = S.Lime,
    green = S.Green,
    emerald = S.Emerald,
    teal = S.Teal,
    cyan = S.Cyan,
    sky = S.Sky,
    blue = S.Blue,
    indigo = S.Indigo,
    violet = S.Violet,
    purple = S.Purple,
    fuchsia = S.Fuchsia,
    pink = S.Pink,
    rose = S.Rose,
}

local function as_space(v)
    local out = space_lookup[v]
    if out then return out end
    if type(v) == "string" then
        out = space_lookup[v:gsub("_", ".")]
        if out then return out end
    end
    error("unknown spacing token: " .. tostring(v), 2)
end

local function as_fraction(v)
    local out = fraction_lookup[v]
    if out then return out end
    error("unknown fraction token: " .. tostring(v), 2)
end

local function as_color_ref(scale, shade)
    if type(scale) == "string" then
        local lower = scale:lower()
        if lower == "white" then return S.WhiteRef end
        if lower == "black" then return S.BlackRef end
        if lower == "transparent" then return S.TransparentRef end
        scale = scale_lookup[lower]
    end
    if not scale then error("unknown color scale", 2) end
    local s = shade_lookup[shade]
    if not s then error("unknown shade", 2) end
    return S.Palette(scale, s)
end

local function len_auto() return S.LAuto end
local function len_hug() return S.LHug end
local function len_fill() return S.LFill end
local function len_px(v) return S.LFixed(v) end
local function len_frac(v) return S.LFrac(as_fraction(v)) end

local function basis_auto() return S.BAuto end
local function basis_hug() return S.BHug end
local function basis_px(v) return S.BFixed(v) end
local function basis_frac(v) return S.BFrac(as_fraction(v)) end

local function track_auto() return S.TAuto end
local function track_fr(v) return S.TFr(v) end
local function track_px(v) return S.TFixed(v) end
local function track_minmax(min_px, max_px) return S.TMinMax(min_px, max_px) end

M.space = as_space
M.frac = as_fraction

M.flex = token(S.ADisplay(S.DisplayFlex))
M.grid = token(S.ADisplay(S.DisplayGrid))
M.flow = token(S.ADisplay(S.DisplayFlow))

M.row = token(S.AAxis(S.AxisRow))
M.col = token(S.AAxis(S.AxisCol))
M.wrap = token(S.AWrap(S.WrapOn))
M.nowrap = token(S.AWrap(S.WrapOff))

M.justify_start = token(S.AJustify(S.JustifyStart))
M.justify_center = token(S.AJustify(S.JustifyCenter))
M.justify_end = token(S.AJustify(S.JustifyEnd))
M.justify_between = token(S.AJustify(S.JustifyBetween))
M.justify_around = token(S.AJustify(S.JustifyAround))
M.justify_evenly = token(S.AJustify(S.JustifyEvenly))

M.items_start = token(S.AItems(S.ItemsStart))
M.items_center = token(S.AItems(S.ItemsCenter))
M.items_end = token(S.AItems(S.ItemsEnd))
M.items_stretch = token(S.AItems(S.ItemsStretch))
M.items_baseline = token(S.AItems(S.ItemsBaseline))

M.self_auto = token(S.ASelf(S.SelfAuto))
M.self_start = token(S.ASelf(S.SelfStart))
M.self_center = token(S.ASelf(S.SelfCenter))
M.self_end = token(S.ASelf(S.SelfEnd))
M.self_stretch = token(S.ASelf(S.SelfStretch))
M.self_baseline = token(S.ASelf(S.SelfBaseline))

local function install_space_series(prefix, ctor)
    for name, space in pairs({
        ["0"] = S.S0, ["0_5"] = S.S0_5, ["1"] = S.S1, ["1_5"] = S.S1_5,
        ["2"] = S.S2, ["2_5"] = S.S2_5, ["3"] = S.S3, ["3_5"] = S.S3_5,
        ["4"] = S.S4, ["5"] = S.S5, ["6"] = S.S6, ["7"] = S.S7,
        ["8"] = S.S8, ["9"] = S.S9, ["10"] = S.S10, ["11"] = S.S11,
        ["12"] = S.S12, ["14"] = S.S14, ["16"] = S.S16, ["20"] = S.S20,
        ["24"] = S.S24, ["28"] = S.S28, ["32"] = S.S32, ["36"] = S.S36,
        ["40"] = S.S40, ["44"] = S.S44, ["48"] = S.S48, ["52"] = S.S52,
        ["56"] = S.S56, ["60"] = S.S60, ["64"] = S.S64, ["72"] = S.S72,
        ["80"] = S.S80, ["96"] = S.S96, ["px"] = S.SPx,
    }) do
        M[prefix .. "_" .. name] = token(ctor(space))
    end
end

install_space_series("p", S.APad)
install_space_series("px", S.APadX)
install_space_series("py", S.APadY)
install_space_series("pt", S.APadTop)
install_space_series("pr", S.APadRight)
install_space_series("pb", S.APadBottom)
install_space_series("pl", S.APadLeft)
install_space_series("m", S.AMargin)
install_space_series("mx", S.AMarginX)
install_space_series("my", S.AMarginY)
install_space_series("mt", S.AMarginTop)
install_space_series("mr", S.AMarginRight)
install_space_series("mb", S.AMarginBottom)
install_space_series("ml", S.AMarginLeft)
install_space_series("gap", S.AGap)
install_space_series("gap_x", S.AGapX)
install_space_series("gap_y", S.AGapY)
install_space_series("col_gap", S.AColGap)
install_space_series("row_gap", S.ARowGap)

M.mx_auto = token(S.AMarginAutoX)
M.ml_auto = token(S.AMarginAutoLeft)
M.mr_auto = token(S.AMarginAutoRight)

function M.p(v) return token(S.APad(as_space(v))) end
function M.px(v) return token(S.APadX(as_space(v))) end
function M.py(v) return token(S.APadY(as_space(v))) end
function M.pt(v) return token(S.APadTop(as_space(v))) end
function M.pr(v) return token(S.APadRight(as_space(v))) end
function M.pb(v) return token(S.APadBottom(as_space(v))) end
function M.pl(v) return token(S.APadLeft(as_space(v))) end
function M.m(v) return token(S.AMargin(as_space(v))) end
function M.mx(v) return token(S.AMarginX(as_space(v))) end
function M.my(v) return token(S.AMarginY(as_space(v))) end
function M.mt(v) return token(S.AMarginTop(as_space(v))) end
function M.mr(v) return token(S.AMarginRight(as_space(v))) end
function M.mb(v) return token(S.AMarginBottom(as_space(v))) end
function M.ml(v) return token(S.AMarginLeft(as_space(v))) end
function M.gap(v) return token(S.AGap(as_space(v))) end
function M.gap_x(v) return token(S.AGapX(as_space(v))) end
function M.gap_y(v) return token(S.AGapY(as_space(v))) end
function M.col_gap(v) return token(S.AColGap(as_space(v))) end
function M.row_gap(v) return token(S.ARowGap(as_space(v))) end

M.w_auto = token(S.AWidth(len_auto()))
M.w_hug = token(S.AWidth(len_hug()))
M.w_fill = token(S.AWidth(len_fill()))
M.w_full = token(S.AWidth(len_frac("full")))
M.w_1_2 = token(S.AWidth(len_frac("1/2")))
M.w_1_3 = token(S.AWidth(len_frac("1/3")))
M.w_2_3 = token(S.AWidth(len_frac("2/3")))
M.w_1_4 = token(S.AWidth(len_frac("1/4")))
M.w_2_4 = token(S.AWidth(len_frac("2/4")))
M.w_3_4 = token(S.AWidth(len_frac("3/4")))
M.w_1_5 = token(S.AWidth(len_frac("1/5")))
M.w_2_5 = token(S.AWidth(len_frac("2/5")))
M.w_3_5 = token(S.AWidth(len_frac("3/5")))
M.w_4_5 = token(S.AWidth(len_frac("4/5")))
M.w_1_6 = token(S.AWidth(len_frac("1/6")))
M.w_2_6 = token(S.AWidth(len_frac("2/6")))
M.w_3_6 = token(S.AWidth(len_frac("3/6")))
M.w_4_6 = token(S.AWidth(len_frac("4/6")))
M.w_5_6 = token(S.AWidth(len_frac("5/6")))

M.h_auto = token(S.AHeight(len_auto()))
M.h_hug = token(S.AHeight(len_hug()))
M.h_fill = token(S.AHeight(len_fill()))
M.h_full = token(S.AHeight(len_frac("full")))

function M.w_px(v) return token(S.AWidth(len_px(v))) end
function M.h_px(v) return token(S.AHeight(len_px(v))) end
function M.min_w_px(v) return token(S.AMinWidth(len_px(v))) end
function M.max_w_px(v) return token(S.AMaxWidth(len_px(v))) end
function M.min_h_px(v) return token(S.AMinHeight(len_px(v))) end
function M.max_h_px(v) return token(S.AMaxHeight(len_px(v))) end
function M.w_frac(v) return token(S.AWidth(len_frac(v))) end
function M.h_frac(v) return token(S.AHeight(len_frac(v))) end
function M.min_w_frac(v) return token(S.AMinWidth(len_frac(v))) end
function M.max_w_frac(v) return token(S.AMaxWidth(len_frac(v))) end
function M.min_h_frac(v) return token(S.AMinHeight(len_frac(v))) end
function M.max_h_frac(v) return token(S.AMaxHeight(len_frac(v))) end

M.grow_0 = token(S.AGrow(0))
M.grow_1 = token(S.AGrow(1))
M.shrink_0 = token(S.AShrink(0))
M.shrink_1 = token(S.AShrink(1))
function M.grow(v) return token(S.AGrow(v)) end
function M.shrink(v) return token(S.AShrink(v)) end

M.basis_auto = token(S.ABasis(basis_auto()))
M.basis_hug = token(S.ABasis(basis_hug()))
M.basis_full = token(S.ABasis(basis_frac("full")))
function M.basis_px(v) return token(S.ABasis(basis_px(v))) end
function M.basis_frac(v) return token(S.ABasis(basis_frac(v))) end

M.rounded_none = token(S.ARounded(S.R0))
M.rounded_sm = token(S.ARounded(S.RSm))
M.rounded = token(S.ARounded(S.RBase))
M.rounded_md = token(S.ARounded(S.RMd))
M.rounded_lg = token(S.ARounded(S.RLg))
M.rounded_xl = token(S.ARounded(S.RXl))
M.rounded_2xl = token(S.ARounded(S.R2xl))
M.rounded_3xl = token(S.ARounded(S.R3xl))
M.rounded_full = token(S.ARounded(S.RFull))

M.border_0 = token(S.ABorderWidth(S.BW0))
M.border_1 = token(S.ABorderWidth(S.BW1))
M.border_2 = token(S.ABorderWidth(S.BW2))
M.border_4 = token(S.ABorderWidth(S.BW4))
M.border_8 = token(S.ABorderWidth(S.BW8))

M.opacity_0 = token(S.AOpacity(S.O0))
M.opacity_5 = token(S.AOpacity(S.O5))
M.opacity_10 = token(S.AOpacity(S.O10))
M.opacity_20 = token(S.AOpacity(S.O20))
M.opacity_25 = token(S.AOpacity(S.O25))
M.opacity_30 = token(S.AOpacity(S.O30))
M.opacity_40 = token(S.AOpacity(S.O40))
M.opacity_50 = token(S.AOpacity(S.O50))
M.opacity_60 = token(S.AOpacity(S.O60))
M.opacity_70 = token(S.AOpacity(S.O70))
M.opacity_75 = token(S.AOpacity(S.O75))
M.opacity_80 = token(S.AOpacity(S.O80))
M.opacity_90 = token(S.AOpacity(S.O90))
M.opacity_95 = token(S.AOpacity(S.O95))
M.opacity_100 = token(S.AOpacity(S.O100))

M.text_xs = token(S.ATextSize(S.TxtXs))
M.text_sm = token(S.ATextSize(S.TxtSm))
M.text_base = token(S.ATextSize(S.TxtBase))
M.text_lg = token(S.ATextSize(S.TxtLg))
M.text_xl = token(S.ATextSize(S.TxtXl))
M.text_2xl = token(S.ATextSize(S.Txt2xl))
M.text_3xl = token(S.ATextSize(S.Txt3xl))
M.text_4xl = token(S.ATextSize(S.Txt4xl))
M.text_5xl = token(S.ATextSize(S.Txt5xl))
M.text_6xl = token(S.ATextSize(S.Txt6xl))

M.font_thin = token(S.ATextWeight(S.Thin))
M.font_extralight = token(S.ATextWeight(S.ExtraLight))
M.font_light = token(S.ATextWeight(S.Light))
M.font_normal = token(S.ATextWeight(S.Normal))
M.font_medium = token(S.ATextWeight(S.Medium))
M.font_semibold = token(S.ATextWeight(S.Semibold))
M.font_bold = token(S.ATextWeight(S.Bold))
M.font_extrabold = token(S.ATextWeight(S.ExtraBold))
M.font_black = token(S.ATextWeight(S.WeightBlack))

M.text_left = token(S.ATextAlign(S.TLeft))
M.text_center = token(S.ATextAlign(S.TCenter))
M.text_right = token(S.ATextAlign(S.TRight))
M.text_justify = token(S.ATextAlign(S.TJustify))

M.leading_none = token(S.ALeading(S.LeadingNone))
M.leading_tight = token(S.ALeading(S.LeadingTight))
M.leading_snug = token(S.ALeading(S.LeadingSnug))
M.leading_normal = token(S.ALeading(S.LeadingNormal))
M.leading_relaxed = token(S.ALeading(S.LeadingRelaxed))
M.leading_loose = token(S.ALeading(S.LeadingLoose))

M.tracking_tighter = token(S.ATracking(S.TrackingTighter))
M.tracking_tight = token(S.ATracking(S.TrackingTight))
M.tracking_normal = token(S.ATracking(S.TrackingNormal))
M.tracking_wide = token(S.ATracking(S.TrackingWide))
M.tracking_wider = token(S.ATracking(S.TrackingWider))
M.tracking_widest = token(S.ATracking(S.TrackingWidest))

M.overflow_x_visible = token(S.AOverflowX(S.OverflowVisible))
M.overflow_x_hidden = token(S.AOverflowX(S.OverflowHidden))
M.overflow_x_scroll = token(S.AOverflowX(S.OverflowScroll))
M.overflow_x_auto = token(S.AOverflowX(S.OverflowAuto))
M.overflow_y_visible = token(S.AOverflowY(S.OverflowVisible))
M.overflow_y_hidden = token(S.AOverflowY(S.OverflowHidden))
M.overflow_y_scroll = token(S.AOverflowY(S.OverflowScroll))
M.overflow_y_auto = token(S.AOverflowY(S.OverflowAuto))

M.cursor_default = token(S.ACursor(S.CursorDefault))
M.cursor_pointer = token(S.ACursor(S.CursorPointer))
M.cursor_text = token(S.ACursor(S.CursorText))
M.cursor_move = token(S.ACursor(S.CursorMove))
M.cursor_grab = token(S.ACursor(S.CursorGrab))
M.cursor_grabbing = token(S.ACursor(S.CursorGrabbing))
M.cursor_not_allowed = token(S.ACursor(S.CursorNotAllowed))

local function build_color_namespace(atom_ctor)
    local out = {}
    for name, scale in pairs(scale_lookup) do
        local shades = {}
        for shade, shade_value in pairs(shade_lookup) do
            shades[shade] = token(atom_ctor(S.Palette(scale, shade_value)))
        end
        out[name] = shades
    end
    out.white = token(atom_ctor(S.WhiteRef))
    out.black = token(atom_ctor(S.BlackRef))
    out.transparent = token(atom_ctor(S.TransparentRef))
    return out
end

M.bg = build_color_namespace(S.ABg)
M.fg = build_color_namespace(S.AFg)
M.border_color = build_color_namespace(S.ABorderColor)

function M.bg_color(scale, shade)
    return token(S.ABg(as_color_ref(scale, shade)))
end
function M.fg_color(scale, shade)
    return token(S.AFg(as_color_ref(scale, shade)))
end
function M.border_color_value(scale, shade)
    return token(S.ABorderColor(as_color_ref(scale, shade)))
end

M.track = {
    auto = track_auto(),
    fr = track_fr,
    px = track_px,
    minmax = track_minmax,
}

local function collect_tracks(args)
    local out = {}
    for i = 1, #args do
        out[#out + 1] = args[i]
    end
    return out
end

function M.cols(...)
    local args = { ... }
    if #args == 1 and type(args[1]) == "table" and not classof(args[1]) then
        args = args[1]
    end
    return token(S.ACols(collect_tracks(args)))
end

function M.rows(...)
    local args = { ... }
    if #args == 1 and type(args[1]) == "table" and not classof(args[1]) then
        args = args[1]
    end
    return token(S.ARows(collect_tracks(args)))
end

for i = 1, 12 do
    local tracks = {}
    for j = 1, i do tracks[j] = track_fr(1) end
    M["cols_" .. i] = token(S.ACols(tracks))
    M["rows_" .. i] = token(S.ARows(tracks))
end

function M.col_start(n) return token(S.AColStart(n)) end
function M.col_span(n) return token(S.AColSpan(n)) end
function M.row_start(n) return token(S.ARowStart(n)) end
function M.row_span(n) return token(S.ARowSpan(n)) end

local function map_state_cond(value, hovered, focused, active, selected, disabled)
    if value == nil or value == false then
        return value
    end

    if is_token(value) then
        local state_cond = clone_state_cond(value.cond.state, hovered, focused, active, selected, disabled)
        return S.Token(clone_cond(value.cond, nil, nil, nil, state_cond), value.atom)
    end

    if is_group(value) then
        local src = value.items
        local out = {}
        for i = 1, #src do
            out[i] = map_state_cond(src[i], hovered, focused, active, selected, disabled)
        end
        return S.Group(out)
    end

    if is_token_list(value) then
        local src = value.items
        local out = {}
        for i = 1, #src do
            out[i] = map_state_cond(src[i], hovered, focused, active, selected, disabled)
        end
        return S.TokenList(out)
    end

    if type(value) == "table" and not classof(value) then
        local out = {}
        for i = 1, #value do
            collect_tokens(map_state_cond(value[i], hovered, focused, active, selected, disabled), out)
        end
        return S.Group(out)
    end

    error("expected Style.Token, Style.Group, Style.TokenList, or token array", 2)
end

function M.state(opts)
    opts = opts or {}
    return S.State(
        not not opts.hovered,
        not not opts.focused,
        not not opts.active,
        not not opts.selected,
        not not opts.disabled
    )
end

function M.sm(v) return map_cond(v, S.SmUp, nil, nil) end
function M.md(v) return map_cond(v, S.MdUp, nil, nil) end
function M.lg(v) return map_cond(v, S.LgUp, nil, nil) end
function M.xl(v) return map_cond(v, S.XlUp, nil, nil) end
function M.x2l(v) return map_cond(v, S.X2lUp, nil, nil) end

function M.light(v) return map_cond(v, nil, S.LightOnly, nil) end
function M.dark(v) return map_cond(v, nil, S.DarkOnly, nil) end

function M.motion_safe(v) return map_cond(v, nil, nil, S.MotionSafeOnly) end
function M.motion_reduce(v) return map_cond(v, nil, nil, S.MotionReduceOnly) end

function M.hover(v) return map_state_cond(v, S.ReqOn, nil, nil, nil, nil) end
function M.focus(v) return map_state_cond(v, nil, S.ReqOn, nil, nil, nil) end
function M.active(v) return map_state_cond(v, nil, nil, S.ReqOn, nil, nil) end
function M.selected(v) return map_state_cond(v, nil, nil, nil, S.ReqOn, nil) end
function M.disabled(v) return map_state_cond(v, nil, nil, nil, nil, S.ReqOn) end
function M.enabled(v) return map_state_cond(v, nil, nil, nil, nil, S.ReqOff) end

M.token = token
M.default_cond = DEFAULT_COND
M.default_state_cond = DEFAULT_STATE_COND
M.no_state = NO_STATE
M.T = T

return M
