local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Env = T.Env
local S = T.Style

local M = {}

local BP_RANK = {
    [Env.Sm] = 1,
    [Env.Md] = 2,
    [Env.Lg] = 3,
    [Env.Xl] = 4,
    [Env.X2l] = 5,
}

local ZERO_SPACE = S.S0
local ZERO_MARGIN = S.MSpace(S.S0)
local EMPTY_TRACKS = {}

local DEFAULT_PADDING = S.Padding(ZERO_SPACE, ZERO_SPACE, ZERO_SPACE, ZERO_SPACE)
local DEFAULT_MARGIN = S.Margin(ZERO_MARGIN, ZERO_MARGIN, ZERO_MARGIN, ZERO_MARGIN)
local DEFAULT_GAP = S.GapSpec(ZERO_SPACE, ZERO_SPACE)
local DEFAULT_GRID_PLACEMENT = S.GridPlacement(1, 1, 1, 1)

local DEFAULT_SPEC = S.Spec(
    S.DisplayFlow,
    S.Row,
    S.NoWrap,
    S.JustifyStart,
    S.ItemsStretch,
    S.SelfAuto,

    DEFAULT_PADDING,
    DEFAULT_MARGIN,
    DEFAULT_GAP,

    S.Auto,
    S.Auto,
    S.Auto,
    S.Auto,
    S.Auto,
    S.Auto,

    0,
    1,
    S.BasisAuto,

    S.Palette(S.Slate, S.S900),
    S.TransparentRef,
    S.TransparentRef,
    S.BW0,
    S.R0,
    S.O100,

    S.TxtBase,
    S.Normal,
    S.TLeft,
    S.LeadingNormal,
    S.TrackingNormal,

    S.OverflowVisible,
    S.OverflowVisible,
    S.CursorDefault,

    EMPTY_TRACKS,
    EMPTY_TRACKS,
    DEFAULT_GAP,
    DEFAULT_GRID_PLACEMENT
)

local function bp_matches(cond_bp, env_bp)
    if cond_bp == S.AnyBp or cond_bp == nil then
        return true
    end
    return BP_RANK[env_bp] >= BP_RANK[
        (cond_bp == S.SmUp and Env.Sm)
        or (cond_bp == S.MdUp and Env.Md)
        or (cond_bp == S.LgUp and Env.Lg)
        or (cond_bp == S.XlUp and Env.Xl)
        or (cond_bp == S.X2lUp and Env.X2l)
    ]
end

local function scheme_matches(cond_scheme, env_scheme)
    return cond_scheme == S.AnyScheme
        or (cond_scheme == S.LightOnly and env_scheme == Env.Light)
        or (cond_scheme == S.DarkOnly and env_scheme == Env.Dark)
end

local function motion_matches(cond_motion, env_motion)
    return cond_motion == S.AnyMotion
        or (cond_motion == S.MotionSafeOnly and env_motion == Env.MotionSafe)
        or (cond_motion == S.MotionReduceOnly and env_motion == Env.MotionReduce)
end

local function cond_matches(cond, env)
    return bp_matches(cond.bp, env.bp)
       and scheme_matches(cond.scheme, env.scheme)
       and motion_matches(cond.motion, env.motion)
end

local function normalize_impl(tokens, env)
    local display = DEFAULT_SPEC.display
    local axis = DEFAULT_SPEC.axis
    local wrap = DEFAULT_SPEC.wrap
    local justify = DEFAULT_SPEC.justify
    local items = DEFAULT_SPEC.items
    local self_align = DEFAULT_SPEC.self_align

    local pad_t = DEFAULT_SPEC.padding.top
    local pad_r = DEFAULT_SPEC.padding.right
    local pad_b = DEFAULT_SPEC.padding.bottom
    local pad_l = DEFAULT_SPEC.padding.left

    local mar_t = DEFAULT_SPEC.margin.top
    local mar_r = DEFAULT_SPEC.margin.right
    local mar_b = DEFAULT_SPEC.margin.bottom
    local mar_l = DEFAULT_SPEC.margin.left

    local gap_x = DEFAULT_SPEC.gap.x
    local gap_y = DEFAULT_SPEC.gap.y
    local grid_gap_x = DEFAULT_SPEC.grid_gap.x
    local grid_gap_y = DEFAULT_SPEC.grid_gap.y

    local w = DEFAULT_SPEC.w
    local h = DEFAULT_SPEC.h
    local min_w = DEFAULT_SPEC.min_w
    local max_w = DEFAULT_SPEC.max_w
    local min_h = DEFAULT_SPEC.min_h
    local max_h = DEFAULT_SPEC.max_h

    local grow = DEFAULT_SPEC.grow
    local shrink = DEFAULT_SPEC.shrink
    local basis = DEFAULT_SPEC.basis

    local fg = DEFAULT_SPEC.fg
    local bg = DEFAULT_SPEC.bg
    local border_color = DEFAULT_SPEC.border_color
    local border_w = DEFAULT_SPEC.border_w
    local radius = DEFAULT_SPEC.radius
    local opacity = DEFAULT_SPEC.opacity

    local font_size = DEFAULT_SPEC.font_size
    local font_weight = DEFAULT_SPEC.font_weight
    local text_align = DEFAULT_SPEC.text_align
    local leading = DEFAULT_SPEC.leading
    local tracking = DEFAULT_SPEC.tracking

    local overflow_x = DEFAULT_SPEC.overflow_x
    local overflow_y = DEFAULT_SPEC.overflow_y
    local cursor = DEFAULT_SPEC.cursor

    local cols = DEFAULT_SPEC.cols
    local rows = DEFAULT_SPEC.rows
    local col_start = DEFAULT_SPEC.placement.col_start
    local col_span = DEFAULT_SPEC.placement.col_span
    local row_start = DEFAULT_SPEC.placement.row_start
    local row_span = DEFAULT_SPEC.placement.row_span

    local items_list = tokens.items
    for i = 1, #items_list do
        local tok = items_list[i]
        if cond_matches(tok.cond, env) then
            local atom = tok.atom
            local cls = pvm.classof(atom)

            if cls == S.SetDisplay then
                display = atom.value
            elseif cls == S.SetAxis then
                axis = atom.value
            elseif cls == S.WrapMode then
                wrap = atom.value
            elseif cls == S.JustifyMode then
                justify = atom.value
            elseif cls == S.ItemsMode then
                items = atom.value
            elseif cls == S.SelfMode then
                self_align = atom.value

            elseif cls == S.P then
                pad_t, pad_r, pad_b, pad_l = atom.value, atom.value, atom.value, atom.value
            elseif cls == S.PX then
                pad_l, pad_r = atom.value, atom.value
            elseif cls == S.PY then
                pad_t, pad_b = atom.value, atom.value
            elseif cls == S.PT then
                pad_t = atom.value
            elseif cls == S.PR then
                pad_r = atom.value
            elseif cls == S.PB then
                pad_b = atom.value
            elseif cls == S.PL then
                pad_l = atom.value

            elseif cls == S.M then
                local mv = S.MSpace(atom.value)
                mar_t, mar_r, mar_b, mar_l = mv, mv, mv, mv
            elseif cls == S.MX then
                local mv = S.MSpace(atom.value)
                mar_l, mar_r = mv, mv
            elseif cls == S.MY then
                local mv = S.MSpace(atom.value)
                mar_t, mar_b = mv, mv
            elseif cls == S.MT then
                mar_t = S.MSpace(atom.value)
            elseif cls == S.MR then
                mar_r = S.MSpace(atom.value)
            elseif cls == S.MB then
                mar_b = S.MSpace(atom.value)
            elseif cls == S.ML then
                mar_l = S.MSpace(atom.value)
            elseif atom == S.MAutoX then
                mar_l, mar_r = S.MAuto, S.MAuto
            elseif atom == S.MAutoL then
                mar_l = S.MAuto
            elseif atom == S.MAutoR then
                mar_r = S.MAuto

            elseif cls == S.Gap then
                gap_x, gap_y = atom.value, atom.value
                grid_gap_x, grid_gap_y = atom.value, atom.value
            elseif cls == S.GapX then
                gap_x = atom.value
                grid_gap_x = atom.value
            elseif cls == S.GapY then
                gap_y = atom.value
                grid_gap_y = atom.value
            elseif cls == S.ColGap then
                grid_gap_x = atom.value
            elseif cls == S.RowGap then
                grid_gap_y = atom.value

            elseif cls == S.W then
                w = atom.value
            elseif cls == S.H then
                h = atom.value
            elseif cls == S.MinW then
                min_w = atom.value
            elseif cls == S.MaxW then
                max_w = atom.value
            elseif cls == S.MinH then
                min_h = atom.value
            elseif cls == S.MaxH then
                max_h = atom.value
            elseif cls == S.Grow then
                grow = atom.value
            elseif cls == S.Shrink then
                shrink = atom.value
            elseif cls == S.SetBasis then
                basis = atom.value

            elseif cls == S.Fg then
                fg = atom.value
            elseif cls == S.Bg then
                bg = atom.value
            elseif cls == S.BorderColor then
                border_color = atom.value
            elseif cls == S.BorderWidth then
                border_w = atom.value
            elseif cls == S.Rounded then
                radius = atom.value
            elseif cls == S.OpacityValue then
                opacity = atom.value

            elseif cls == S.TextSize then
                font_size = atom.value
            elseif cls == S.TextWeight then
                font_weight = atom.value
            elseif cls == S.TextAlignMode then
                text_align = atom.value
            elseif cls == S.LeadingValue then
                leading = atom.value
            elseif cls == S.TrackingValue then
                tracking = atom.value

            elseif cls == S.OverflowX then
                overflow_x = atom.value
            elseif cls == S.OverflowY then
                overflow_y = atom.value
            elseif cls == S.CursorValue then
                cursor = atom.value

            elseif cls == S.Cols then
                cols = atom.tracks
            elseif cls == S.Rows then
                rows = atom.tracks
            elseif cls == S.ColStart then
                col_start = atom.value
            elseif cls == S.ColSpan then
                col_span = atom.value
            elseif cls == S.RowStart then
                row_start = atom.value
            elseif cls == S.RowSpan then
                row_span = atom.value
            else
                error("ui.normalize: unhandled style atom", 2)
            end
        end
    end

    return S.Spec(
        display,
        axis,
        wrap,
        justify,
        items,
        self_align,

        S.Padding(pad_t, pad_r, pad_b, pad_l),
        S.Margin(mar_t, mar_r, mar_b, mar_l),
        S.GapSpec(gap_x, gap_y),

        w,
        h,
        min_w,
        max_w,
        min_h,
        max_h,

        grow,
        shrink,
        basis,

        fg,
        bg,
        border_color,
        border_w,
        radius,
        opacity,

        font_size,
        font_weight,
        text_align,
        leading,
        tracking,

        overflow_x,
        overflow_y,
        cursor,

        cols,
        rows,
        S.GapSpec(grid_gap_x, grid_gap_y),
        S.GridPlacement(col_start, col_span, row_start, row_span)
    )
end

local normalize = pvm.lower("ui.normalize", normalize_impl)

M.normalize = normalize
M.default_spec = DEFAULT_SPEC
M.T = T

return M
