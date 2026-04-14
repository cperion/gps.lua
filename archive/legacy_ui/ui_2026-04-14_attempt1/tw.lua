local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local S = T.Style

local M = {}

local TOKEN = S.Token
local GROUP = S.Group
local TOKEN_LIST = S.TokenList

local DEFAULT_COND = S.Cond(S.AnyBp, S.AnyScheme, S.AnyMotion)

local function classof(v)
    return pvm.classof(v)
end

local function is_token(v)
    return classof(v) == TOKEN
end

local function is_group(v)
    return classof(v) == GROUP
end

local function is_token_list(v)
    return classof(v) == TOKEN_LIST
end

local function token(atom, cond)
    return S.Token(cond or DEFAULT_COND, atom)
end

local function clone_cond(cond, bp, scheme, motion)
    return S.Cond(bp or cond.bp, scheme or cond.scheme, motion or cond.motion)
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
    if not scale then
        error("unknown color scale: " .. tostring(scale), 2)
    end
    local s = shade_lookup[shade]
    if not s then
        error("unknown shade: " .. tostring(shade), 2)
    end
    return S.Palette(scale, s)
end

local function length_auto() return S.Auto end
local function length_hug() return S.Hug end
local function length_fill() return S.Fill end
local function length_px(v) return S.Fixed(v) end
local function length_frac(v) return S.Frac(as_fraction(v)) end

local function basis_auto() return S.BasisAuto end
local function basis_hug() return S.BasisHug end
local function basis_px(v) return S.BasisFixed(v) end
local function basis_frac(v) return S.BasisFrac(as_fraction(v)) end

local function track_auto() return S.TrackAuto end
local function track_fr(v) return S.TrackFr(v) end
local function track_px(v) return S.TrackFixed(v) end
local function track_minmax(min_px, max_px) return S.TrackMinMax(min_px, max_px) end

M.space = as_space
M.frac = as_fraction

M.flex = token(S.SetDisplay(S.DisplayFlex))
M.grid = token(S.SetDisplay(S.DisplayGrid))
M.flow = token(S.SetDisplay(S.DisplayFlow))

M.row = token(S.SetAxis(S.Row))
M.col = token(S.SetAxis(S.Col))
M.wrap = token(S.WrapMode(S.WrapOn))
M.nowrap = token(S.WrapMode(S.NoWrap))

M.justify_start = token(S.JustifyMode(S.JustifyStart))
M.justify_center = token(S.JustifyMode(S.JustifyCenter))
M.justify_end = token(S.JustifyMode(S.JustifyEnd))
M.justify_between = token(S.JustifyMode(S.JustifyBetween))
M.justify_around = token(S.JustifyMode(S.JustifyAround))
M.justify_evenly = token(S.JustifyMode(S.JustifyEvenly))

M.items_start = token(S.ItemsMode(S.ItemsStart))
M.items_center = token(S.ItemsMode(S.ItemsCenter))
M.items_end = token(S.ItemsMode(S.ItemsEnd))
M.items_stretch = token(S.ItemsMode(S.ItemsStretch))
M.items_baseline = token(S.ItemsMode(S.ItemsBaseline))

M.self_auto = token(S.SelfMode(S.SelfAuto))
M.self_start = token(S.SelfMode(S.SelfStart))
M.self_center = token(S.SelfMode(S.SelfCenter))
M.self_end = token(S.SelfMode(S.SelfEnd))
M.self_stretch = token(S.SelfMode(S.SelfStretch))
M.self_baseline = token(S.SelfMode(S.SelfBaseline))

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

install_space_series("p", S.P)
install_space_series("px", S.PX)
install_space_series("py", S.PY)
install_space_series("pt", S.PT)
install_space_series("pr", S.PR)
install_space_series("pb", S.PB)
install_space_series("pl", S.PL)
install_space_series("m", S.M)
install_space_series("mx", S.MX)
install_space_series("my", S.MY)
install_space_series("mt", S.MT)
install_space_series("mr", S.MR)
install_space_series("mb", S.MB)
install_space_series("ml", S.ML)
install_space_series("gap", S.Gap)
install_space_series("gap_x", S.GapX)
install_space_series("gap_y", S.GapY)
install_space_series("col_gap", S.ColGap)
install_space_series("row_gap", S.RowGap)

M.mx_auto = token(S.MAutoX)
M.ml_auto = token(S.MAutoL)
M.mr_auto = token(S.MAutoR)

function M.p(v) return token(S.P(as_space(v))) end
function M.px(v) return token(S.PX(as_space(v))) end
function M.py(v) return token(S.PY(as_space(v))) end
function M.pt(v) return token(S.PT(as_space(v))) end
function M.pr(v) return token(S.PR(as_space(v))) end
function M.pb(v) return token(S.PB(as_space(v))) end
function M.pl(v) return token(S.PL(as_space(v))) end
function M.m(v) return token(S.M(as_space(v))) end
function M.mx(v) return token(S.MX(as_space(v))) end
function M.my(v) return token(S.MY(as_space(v))) end
function M.mt(v) return token(S.MT(as_space(v))) end
function M.mr(v) return token(S.MR(as_space(v))) end
function M.mb(v) return token(S.MB(as_space(v))) end
function M.ml(v) return token(S.ML(as_space(v))) end
function M.gap(v) return token(S.Gap(as_space(v))) end
function M.gap_x(v) return token(S.GapX(as_space(v))) end
function M.gap_y(v) return token(S.GapY(as_space(v))) end
function M.col_gap(v) return token(S.ColGap(as_space(v))) end
function M.row_gap(v) return token(S.RowGap(as_space(v))) end

M.w_auto = token(S.W(length_auto()))
M.w_hug = token(S.W(length_hug()))
M.w_fill = token(S.W(length_fill()))
M.w_full = token(S.W(length_frac("full")))
M.w_1_2 = token(S.W(length_frac("1/2")))
M.w_1_3 = token(S.W(length_frac("1/3")))
M.w_2_3 = token(S.W(length_frac("2/3")))
M.w_1_4 = token(S.W(length_frac("1/4")))
M.w_2_4 = token(S.W(length_frac("2/4")))
M.w_3_4 = token(S.W(length_frac("3/4")))
M.w_1_5 = token(S.W(length_frac("1/5")))
M.w_2_5 = token(S.W(length_frac("2/5")))
M.w_3_5 = token(S.W(length_frac("3/5")))
M.w_4_5 = token(S.W(length_frac("4/5")))
M.w_1_6 = token(S.W(length_frac("1/6")))
M.w_2_6 = token(S.W(length_frac("2/6")))
M.w_3_6 = token(S.W(length_frac("3/6")))
M.w_4_6 = token(S.W(length_frac("4/6")))
M.w_5_6 = token(S.W(length_frac("5/6")))

M.h_auto = token(S.H(length_auto()))
M.h_hug = token(S.H(length_hug()))
M.h_fill = token(S.H(length_fill()))
M.h_full = token(S.H(length_frac("full")))

M.min_w_auto = token(S.MinW(length_auto()))
M.min_w_hug = token(S.MinW(length_hug()))
M.min_w_fill = token(S.MinW(length_fill()))
M.max_w_auto = token(S.MaxW(length_auto()))
M.max_w_hug = token(S.MaxW(length_hug()))
M.max_w_fill = token(S.MaxW(length_fill()))
M.min_h_auto = token(S.MinH(length_auto()))
M.min_h_hug = token(S.MinH(length_hug()))
M.min_h_fill = token(S.MinH(length_fill()))
M.max_h_auto = token(S.MaxH(length_auto()))
M.max_h_hug = token(S.MaxH(length_hug()))
M.max_h_fill = token(S.MaxH(length_fill()))

function M.w_px(v) return token(S.W(length_px(v))) end
function M.h_px(v) return token(S.H(length_px(v))) end
function M.min_w_px(v) return token(S.MinW(length_px(v))) end
function M.max_w_px(v) return token(S.MaxW(length_px(v))) end
function M.min_h_px(v) return token(S.MinH(length_px(v))) end
function M.max_h_px(v) return token(S.MaxH(length_px(v))) end
function M.w_frac(v) return token(S.W(length_frac(v))) end
function M.h_frac(v) return token(S.H(length_frac(v))) end
function M.min_w_frac(v) return token(S.MinW(length_frac(v))) end
function M.max_w_frac(v) return token(S.MaxW(length_frac(v))) end
function M.min_h_frac(v) return token(S.MinH(length_frac(v))) end
function M.max_h_frac(v) return token(S.MaxH(length_frac(v))) end

M.grow_0 = token(S.Grow(0))
M.grow_1 = token(S.Grow(1))
M.shrink_0 = token(S.Shrink(0))
M.shrink_1 = token(S.Shrink(1))
function M.grow(v) return token(S.Grow(v)) end
function M.shrink(v) return token(S.Shrink(v)) end

M.basis_auto = token(S.SetBasis(basis_auto()))
M.basis_hug = token(S.SetBasis(basis_hug()))
M.basis_full = token(S.SetBasis(basis_frac("full")))
M.basis_1_2 = token(S.SetBasis(basis_frac("1/2")))
M.basis_1_3 = token(S.SetBasis(basis_frac("1/3")))
M.basis_2_3 = token(S.SetBasis(basis_frac("2/3")))
function M.basis_px(v) return token(S.SetBasis(basis_px(v))) end
function M.basis_frac(v) return token(S.SetBasis(basis_frac(v))) end

M.rounded_none = token(S.Rounded(S.R0))
M.rounded_sm = token(S.Rounded(S.RSm))
M.rounded = token(S.Rounded(S.RBase))
M.rounded_md = token(S.Rounded(S.RMd))
M.rounded_lg = token(S.Rounded(S.RLg))
M.rounded_xl = token(S.Rounded(S.RXl))
M.rounded_2xl = token(S.Rounded(S.R2xl))
M.rounded_3xl = token(S.Rounded(S.R3xl))
M.rounded_full = token(S.Rounded(S.RFull))

M.border_0 = token(S.BorderWidth(S.BW0))
M.border_1 = token(S.BorderWidth(S.BW1))
M.border_2 = token(S.BorderWidth(S.BW2))
M.border_4 = token(S.BorderWidth(S.BW4))
M.border_8 = token(S.BorderWidth(S.BW8))

M.opacity_0 = token(S.OpacityValue(S.O0))
M.opacity_5 = token(S.OpacityValue(S.O5))
M.opacity_10 = token(S.OpacityValue(S.O10))
M.opacity_20 = token(S.OpacityValue(S.O20))
M.opacity_25 = token(S.OpacityValue(S.O25))
M.opacity_30 = token(S.OpacityValue(S.O30))
M.opacity_40 = token(S.OpacityValue(S.O40))
M.opacity_50 = token(S.OpacityValue(S.O50))
M.opacity_60 = token(S.OpacityValue(S.O60))
M.opacity_70 = token(S.OpacityValue(S.O70))
M.opacity_75 = token(S.OpacityValue(S.O75))
M.opacity_80 = token(S.OpacityValue(S.O80))
M.opacity_90 = token(S.OpacityValue(S.O90))
M.opacity_95 = token(S.OpacityValue(S.O95))
M.opacity_100 = token(S.OpacityValue(S.O100))

M.text_xs = token(S.TextSize(S.TxtXs))
M.text_sm = token(S.TextSize(S.TxtSm))
M.text_base = token(S.TextSize(S.TxtBase))
M.text_lg = token(S.TextSize(S.TxtLg))
M.text_xl = token(S.TextSize(S.TxtXl))
M.text_2xl = token(S.TextSize(S.Txt2xl))
M.text_3xl = token(S.TextSize(S.Txt3xl))
M.text_4xl = token(S.TextSize(S.Txt4xl))
M.text_5xl = token(S.TextSize(S.Txt5xl))
M.text_6xl = token(S.TextSize(S.Txt6xl))

M.font_thin = token(S.TextWeight(S.Thin))
M.font_extralight = token(S.TextWeight(S.ExtraLight))
M.font_light = token(S.TextWeight(S.Light))
M.font_normal = token(S.TextWeight(S.Normal))
M.font_medium = token(S.TextWeight(S.Medium))
M.font_semibold = token(S.TextWeight(S.Semibold))
M.font_bold = token(S.TextWeight(S.Bold))
M.font_extrabold = token(S.TextWeight(S.ExtraBold))
M.font_black = token(S.TextWeight(S.WeightBlack))

M.text_left = token(S.TextAlignMode(S.TLeft))
M.text_center = token(S.TextAlignMode(S.TCenter))
M.text_right = token(S.TextAlignMode(S.TRight))
M.text_justify = token(S.TextAlignMode(S.TJustify))

M.leading_none = token(S.LeadingValue(S.LeadingNone))
M.leading_tight = token(S.LeadingValue(S.LeadingTight))
M.leading_snug = token(S.LeadingValue(S.LeadingSnug))
M.leading_normal = token(S.LeadingValue(S.LeadingNormal))
M.leading_relaxed = token(S.LeadingValue(S.LeadingRelaxed))
M.leading_loose = token(S.LeadingValue(S.LeadingLoose))

M.tracking_tighter = token(S.TrackingValue(S.TrackingTighter))
M.tracking_tight = token(S.TrackingValue(S.TrackingTight))
M.tracking_normal = token(S.TrackingValue(S.TrackingNormal))
M.tracking_wide = token(S.TrackingValue(S.TrackingWide))
M.tracking_wider = token(S.TrackingValue(S.TrackingWider))
M.tracking_widest = token(S.TrackingValue(S.TrackingWidest))

M.overflow_x_visible = token(S.OverflowX(S.OverflowVisible))
M.overflow_x_hidden = token(S.OverflowX(S.OverflowHidden))
M.overflow_x_scroll = token(S.OverflowX(S.OverflowScroll))
M.overflow_x_auto = token(S.OverflowX(S.OverflowAuto))
M.overflow_y_visible = token(S.OverflowY(S.OverflowVisible))
M.overflow_y_hidden = token(S.OverflowY(S.OverflowHidden))
M.overflow_y_scroll = token(S.OverflowY(S.OverflowScroll))
M.overflow_y_auto = token(S.OverflowY(S.OverflowAuto))

M.cursor_default = token(S.CursorValue(S.CursorDefault))
M.cursor_pointer = token(S.CursorValue(S.CursorPointer))
M.cursor_text = token(S.CursorValue(S.CursorText))
M.cursor_move = token(S.CursorValue(S.CursorMove))
M.cursor_grab = token(S.CursorValue(S.CursorGrab))
M.cursor_grabbing = token(S.CursorValue(S.CursorGrabbing))
M.cursor_not_allowed = token(S.CursorValue(S.CursorNotAllowed))

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

M.bg = build_color_namespace(S.Bg)
M.fg = build_color_namespace(S.Fg)
M.border_color = build_color_namespace(S.BorderColor)

function M.bg_color(scale, shade)
    return token(S.Bg(as_color_ref(scale, shade)))
end

function M.fg_color(scale, shade)
    return token(S.Fg(as_color_ref(scale, shade)))
end

function M.border_color_value(scale, shade)
    return token(S.BorderColor(as_color_ref(scale, shade)))
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
    return token(S.Cols(collect_tracks(args)))
end

function M.rows(...)
    local args = { ... }
    if #args == 1 and type(args[1]) == "table" and not classof(args[1]) then
        args = args[1]
    end
    return token(S.Rows(collect_tracks(args)))
end

function M.col_start(n) return token(S.ColStart(n)) end
function M.col_span(n) return token(S.ColSpan(n)) end
function M.row_start(n) return token(S.RowStart(n)) end
function M.row_span(n) return token(S.RowSpan(n)) end

function M.sm(v) return map_cond(v, S.SmUp, nil, nil) end
function M.md(v) return map_cond(v, S.MdUp, nil, nil) end
function M.lg(v) return map_cond(v, S.LgUp, nil, nil) end
function M.xl(v) return map_cond(v, S.XlUp, nil, nil) end
function M.x2l(v) return map_cond(v, S.X2lUp, nil, nil) end

function M.light(v) return map_cond(v, nil, S.LightOnly, nil) end
function M.dark(v) return map_cond(v, nil, S.DarkOnly, nil) end

function M.motion_safe(v) return map_cond(v, nil, nil, S.MotionSafeOnly) end
function M.motion_reduce(v) return map_cond(v, nil, nil, S.MotionReduceOnly) end

M.token = token
M.default_cond = DEFAULT_COND
M.T = T

return M
