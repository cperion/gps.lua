local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local S = T.Style
local Theme = T.Theme
local Resolved = T.Resolved
local Layout = T.Layout

local M = {}

local function round(n)
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

local function fraction_value(frac)
    if frac == S.F1_2 then return 1 / 2 end
    if frac == S.F1_3 then return 1 / 3 end
    if frac == S.F2_3 then return 2 / 3 end
    if frac == S.F1_4 then return 1 / 4 end
    if frac == S.F2_4 then return 2 / 4 end
    if frac == S.F3_4 then return 3 / 4 end
    if frac == S.F1_5 then return 1 / 5 end
    if frac == S.F2_5 then return 2 / 5 end
    if frac == S.F3_5 then return 3 / 5 end
    if frac == S.F4_5 then return 4 / 5 end
    if frac == S.F1_6 then return 1 / 6 end
    if frac == S.F2_6 then return 2 / 6 end
    if frac == S.F3_6 then return 3 / 6 end
    if frac == S.F4_6 then return 4 / 6 end
    if frac == S.F5_6 then return 5 / 6 end
    if frac == S.FFull then return 1 end
    error("ui.resolve: unknown fraction", 2)
end

local function resolve_space(space, theme)
    local scale = theme.spacing
    if space == S.S0 then return scale.s0 end
    if space == S.S0_5 then return scale.s0_5 end
    if space == S.S1 then return scale.s1 end
    if space == S.S1_5 then return scale.s1_5 end
    if space == S.S2 then return scale.s2 end
    if space == S.S2_5 then return scale.s2_5 end
    if space == S.S3 then return scale.s3 end
    if space == S.S3_5 then return scale.s3_5 end
    if space == S.S4 then return scale.s4 end
    if space == S.S5 then return scale.s5 end
    if space == S.S6 then return scale.s6 end
    if space == S.S7 then return scale.s7 end
    if space == S.S8 then return scale.s8 end
    if space == S.S9 then return scale.s9 end
    if space == S.S10 then return scale.s10 end
    if space == S.S11 then return scale.s11 end
    if space == S.S12 then return scale.s12 end
    if space == S.S14 then return scale.s14 end
    if space == S.S16 then return scale.s16 end
    if space == S.S20 then return scale.s20 end
    if space == S.S24 then return scale.s24 end
    if space == S.S28 then return scale.s28 end
    if space == S.S32 then return scale.s32 end
    if space == S.S36 then return scale.s36 end
    if space == S.S40 then return scale.s40 end
    if space == S.S44 then return scale.s44 end
    if space == S.S48 then return scale.s48 end
    if space == S.S52 then return scale.s52 end
    if space == S.S56 then return scale.s56 end
    if space == S.S60 then return scale.s60 end
    if space == S.S64 then return scale.s64 end
    if space == S.S72 then return scale.s72 end
    if space == S.S80 then return scale.s80 end
    if space == S.S96 then return scale.s96 end
    if space == S.SPx then return scale.px end
    error("ui.resolve: unknown space", 2)
end

local function resolve_palette(theme, scale)
    if scale == S.Slate then return theme.slate end
    if scale == S.Gray then return theme.gray end
    if scale == S.Zinc then return theme.zinc end
    if scale == S.Neutral then return theme.neutral end
    if scale == S.Stone then return theme.stone end
    if scale == S.Red then return theme.red end
    if scale == S.Orange then return theme.orange end
    if scale == S.Amber then return theme.amber end
    if scale == S.Yellow then return theme.yellow end
    if scale == S.Lime then return theme.lime end
    if scale == S.Green then return theme.green end
    if scale == S.Emerald then return theme.emerald end
    if scale == S.Teal then return theme.teal end
    if scale == S.Cyan then return theme.cyan end
    if scale == S.Sky then return theme.sky end
    if scale == S.Blue then return theme.blue end
    if scale == S.Indigo then return theme.indigo end
    if scale == S.Violet then return theme.violet end
    if scale == S.Purple then return theme.purple end
    if scale == S.Fuchsia then return theme.fuchsia end
    if scale == S.Pink then return theme.pink end
    if scale == S.Rose then return theme.rose end
    error("ui.resolve: unknown color scale", 2)
end

local function resolve_shade(palette, shade)
    if shade == S.S50 then return palette.s50 end
    if shade == S.S100 then return palette.s100 end
    if shade == S.S200 then return palette.s200 end
    if shade == S.S300 then return palette.s300 end
    if shade == S.S400 then return palette.s400 end
    if shade == S.S500 then return palette.s500 end
    if shade == S.S600 then return palette.s600 end
    if shade == S.S700 then return palette.s700 end
    if shade == S.S800 then return palette.s800 end
    if shade == S.S900 then return palette.s900 end
    if shade == S.S950 then return palette.s950 end
    error("ui.resolve: unknown shade", 2)
end

local function resolve_color(color_ref, theme)
    local cls = pvm.classof(color_ref)
    if cls == S.Palette then
        return resolve_shade(resolve_palette(theme, color_ref.scale), color_ref.shade)
    end
    if color_ref == S.WhiteRef then return theme.white end
    if color_ref == S.BlackRef then return theme.black end
    if color_ref == S.TransparentRef then return theme.transparent end
    error("ui.resolve: unknown color ref", 2)
end

local function resolve_border_width(border_w, theme)
    local scale = theme.borders
    if border_w == S.BW0 then return scale.bw0 end
    if border_w == S.BW1 then return scale.bw1 end
    if border_w == S.BW2 then return scale.bw2 end
    if border_w == S.BW4 then return scale.bw4 end
    if border_w == S.BW8 then return scale.bw8 end
    error("ui.resolve: unknown border width", 2)
end

local function resolve_radius(radius, theme)
    local scale = theme.radii
    if radius == S.R0 then return scale.r0 end
    if radius == S.RSm then return scale.rsm end
    if radius == S.RBase then return scale.rbase end
    if radius == S.RMd then return scale.rmd end
    if radius == S.RLg then return scale.rlg end
    if radius == S.RXl then return scale.rxl end
    if radius == S.R2xl then return scale.r2xl end
    if radius == S.R3xl then return scale.r3xl end
    if radius == S.RFull then return scale.rfull end
    error("ui.resolve: unknown radius", 2)
end

local function resolve_opacity(opacity, theme)
    local scale = theme.opacities
    if opacity == S.O0 then return scale.o0 end
    if opacity == S.O5 then return scale.o5 end
    if opacity == S.O10 then return scale.o10 end
    if opacity == S.O20 then return scale.o20 end
    if opacity == S.O25 then return scale.o25 end
    if opacity == S.O30 then return scale.o30 end
    if opacity == S.O40 then return scale.o40 end
    if opacity == S.O50 then return scale.o50 end
    if opacity == S.O60 then return scale.o60 end
    if opacity == S.O70 then return scale.o70 end
    if opacity == S.O75 then return scale.o75 end
    if opacity == S.O80 then return scale.o80 end
    if opacity == S.O90 then return scale.o90 end
    if opacity == S.O95 then return scale.o95 end
    if opacity == S.O100 then return scale.o100 end
    error("ui.resolve: unknown opacity", 2)
end

local function resolve_font_size(font_size, theme)
    local scale = theme.font_sizes
    if font_size == S.TxtXs then return scale.xs end
    if font_size == S.TxtSm then return scale.sm end
    if font_size == S.TxtBase then return scale.base end
    if font_size == S.TxtLg then return scale.lg end
    if font_size == S.TxtXl then return scale.xl end
    if font_size == S.Txt2xl then return scale.x2l end
    if font_size == S.Txt3xl then return scale.x3l end
    if font_size == S.Txt4xl then return scale.x4l end
    if font_size == S.Txt5xl then return scale.x5l end
    if font_size == S.Txt6xl then return scale.x6l end
    error("ui.resolve: unknown font size", 2)
end

local function resolve_font(theme, weight)
    local fonts = theme.fonts
    if weight == S.Medium then return fonts.medium, 500 end
    if weight == S.Semibold then return fonts.semibold, 600 end
    if weight == S.Bold then return fonts.bold, 700 end
    if weight == S.ExtraBold then return fonts.bold, 800 end
    if weight == S.WeightBlack then return fonts.bold, 900 end
    if weight == S.Thin then return fonts.regular, 100 end
    if weight == S.ExtraLight then return fonts.regular, 200 end
    if weight == S.Light then return fonts.regular, 300 end
    return fonts.regular, 400
end

local function resolve_text_align(value)
    if value == S.TLeft then return 0 end
    if value == S.TCenter then return 1 end
    if value == S.TRight then return 2 end
    if value == S.TJustify then return 3 end
    error("ui.resolve: unknown text align", 2)
end

local function resolve_leading(value, font_px)
    if value == S.LeadingNone then return round(font_px * 1.0) end
    if value == S.LeadingTight then return round(font_px * 1.1) end
    if value == S.LeadingSnug then return round(font_px * 1.25) end
    if value == S.LeadingNormal then return round(font_px * 1.5) end
    if value == S.LeadingRelaxed then return round(font_px * 1.625) end
    if value == S.LeadingLoose then return round(font_px * 2.0) end
    error("ui.resolve: unknown leading", 2)
end

local function resolve_tracking(value, font_px)
    if value == S.TrackingTighter then return font_px * -0.05 end
    if value == S.TrackingTight then return font_px * -0.025 end
    if value == S.TrackingNormal then return 0 end
    if value == S.TrackingWide then return font_px * 0.025 end
    if value == S.TrackingWider then return font_px * 0.05 end
    if value == S.TrackingWidest then return font_px * 0.1 end
    error("ui.resolve: unknown tracking", 2)
end

local function resolve_axis(axis)
    if axis == S.AxisRow then return Layout.LRow end
    return Layout.LCol
end

local function resolve_wrap(wrap)
    if wrap == S.WrapOn then return Layout.LWrapOn end
    return Layout.LWrapOff
end

local function resolve_justify(justify)
    if justify == S.JustifyStart then return Layout.MStart end
    if justify == S.JustifyCenter then return Layout.MCenter end
    if justify == S.JustifyEnd then return Layout.MEnd end
    if justify == S.JustifyBetween then return Layout.MBetween end
    if justify == S.JustifyAround then return Layout.MAround end
    if justify == S.JustifyEvenly then return Layout.MEvenly end
    error("ui.resolve: unknown justify", 2)
end

local function resolve_items(items)
    if items == S.ItemsStart then return Layout.CStart end
    if items == S.ItemsCenter then return Layout.CCenter end
    if items == S.ItemsEnd then return Layout.CEnd end
    if items == S.ItemsStretch then return Layout.CStretch end
    if items == S.ItemsBaseline then return Layout.CBaseline end
    error("ui.resolve: unknown items", 2)
end

local function resolve_self_align(self_align)
    if self_align == S.SelfAuto then return Layout.SelfAuto end
    if self_align == S.SelfStart then return Layout.SelfStart end
    if self_align == S.SelfCenter then return Layout.SelfCenter end
    if self_align == S.SelfEnd then return Layout.SelfEnd end
    if self_align == S.SelfStretch then return Layout.SelfStretch end
    if self_align == S.SelfBaseline then return Layout.SelfBaseline end
    error("ui.resolve: unknown self align", 2)
end

local function resolve_sizing(length)
    local cls = pvm.classof(length)
    if length == S.LAuto then return Layout.SAuto end
    if length == S.LHug then return Layout.SHug end
    if length == S.LFill then return Layout.SFill end
    if cls == S.LFixed then return Layout.SFixed(length.px) end
    if cls == S.LFrac then return Layout.SFrac(fraction_value(length.value)) end
    error("ui.resolve: unknown sizing", 2)
end

local function resolve_basis(basis)
    local cls = pvm.classof(basis)
    if basis == S.BAuto then return Layout.BasisAuto end
    if basis == S.BHug then return Layout.BasisHug end
    if cls == S.BFixed then return Layout.BasisFixed(basis.px) end
    if cls == S.BFrac then return Layout.BasisFrac(fraction_value(basis.value)) end
    error("ui.resolve: unknown basis", 2)
end

local function resolve_min(length)
    local cls = pvm.classof(length)
    if length == S.LAuto or length == S.LHug then return Layout.NoMin end
    if length == S.LFill then return Layout.MinFrac(1) end
    if cls == S.LFixed then return Layout.MinPx(length.px) end
    if cls == S.LFrac then return Layout.MinFrac(fraction_value(length.value)) end
    error("ui.resolve: unknown min", 2)
end

local function resolve_max(length)
    local cls = pvm.classof(length)
    if length == S.LAuto or length == S.LHug then return Layout.NoMax end
    if length == S.LFill then return Layout.MaxFrac(1) end
    if cls == S.LFixed then return Layout.MaxPx(length.px) end
    if cls == S.LFrac then return Layout.MaxFrac(fraction_value(length.value)) end
    error("ui.resolve: unknown max", 2)
end

local function resolve_overflow(value)
    if value == S.OverflowVisible then return Layout.OVisible end
    if value == S.OverflowHidden then return Layout.OHidden end
    if value == S.OverflowScroll then return Layout.OScroll end
    if value == S.OverflowAuto then return Layout.OAuto end
    error("ui.resolve: unknown overflow", 2)
end

local function resolve_margin_value(value, theme)
    local cls = pvm.classof(value)
    if value == S.MarginAuto then
        return Layout.MarginAuto
    end
    if cls == S.MarginSpace then
        return Layout.MarginPx(resolve_space(value.value, theme))
    end
    error("ui.resolve: unknown margin value", 2)
end

local function resolve_track(track)
    local cls = pvm.classof(track)
    if track == S.TAuto then return Layout.TrackAuto end
    if cls == S.TFr then return Layout.TrackFr(track.fr) end
    if cls == S.TFixed then return Layout.TrackFixed(track.px) end
    if cls == S.TMinMax then return Layout.TrackMinMax(track.min_px, track.max_px) end
    error("ui.resolve: unknown track", 2)
end

local function resolve_tracks(tracks)
    local out = {}
    for i = 1, #tracks do
        out[i] = resolve_track(tracks[i])
    end
    return out
end

local resolve_phase = pvm.phase("ui.resolve", function(spec, theme)
    local font_px = resolve_font_size(spec.font_size, theme)
    local font_id, font_weight = resolve_font(theme, spec.font_weight)

    local text = Resolved.TextStyle(
        font_id,
        font_px,
        font_weight,
        resolve_color(spec.fg, theme),
        resolve_text_align(spec.text_align),
        resolve_leading(spec.leading, font_px),
        resolve_tracking(spec.tracking, font_px)
    )

    local box = Layout.BoxStyle(
        resolve_sizing(spec.w),
        resolve_sizing(spec.h),
        resolve_min(spec.min_w),
        resolve_max(spec.max_w),
        resolve_min(spec.min_h),
        resolve_max(spec.max_h),
        spec.grow,
        spec.shrink,
        resolve_basis(spec.basis),
        resolve_self_align(spec.self_align),
        Layout.Edges(
            resolve_space(spec.padding.top, theme),
            resolve_space(spec.padding.right, theme),
            resolve_space(spec.padding.bottom, theme),
            resolve_space(spec.padding.left, theme)
        ),
        Layout.Margin(
            resolve_margin_value(spec.margin.top, theme),
            resolve_margin_value(spec.margin.right, theme),
            resolve_margin_value(spec.margin.bottom, theme),
            resolve_margin_value(spec.margin.left, theme)
        ),
        Layout.Visual(
            resolve_color(spec.bg, theme),
            resolve_color(spec.fg, theme),
            resolve_color(spec.border_color, theme),
            resolve_border_width(spec.border_w, theme),
            resolve_radius(spec.radius, theme),
            resolve_opacity(spec.opacity, theme)
        ),
        resolve_overflow(spec.overflow_x),
        resolve_overflow(spec.overflow_y),
        spec.cursor
    )

    return Resolved.Style(
        spec.display,
        resolve_axis(spec.axis),
        resolve_wrap(spec.wrap),
        resolve_justify(spec.justify),
        resolve_items(spec.items),
        box,
        text,
        resolve_tracks(spec.cols),
        resolve_tracks(spec.rows),
        resolve_space(spec.gap.x, theme),
        resolve_space(spec.gap.y, theme),
        resolve_space(spec.grid_gap.x, theme),
        resolve_space(spec.grid_gap.y, theme),
        Resolved.GridPlacement(
            spec.placement.col_start,
            spec.placement.col_span,
            spec.placement.row_start,
            spec.placement.row_span
        )
    )
end)

M.phase = resolve_phase
M.T = T

return M
