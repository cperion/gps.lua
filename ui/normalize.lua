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

local ANY_STATE_COND = S.StateCond(S.ReqAny, S.ReqAny, S.ReqAny, S.ReqAny, S.ReqAny)
local NO_STATE = S.State(false, false, false, false, false)

local ZERO_SPACE = S.S0
local ZERO_MARGIN = S.MarginSpace(S.S0)
local EMPTY_TRACKS = {}

local DEFAULT_SPEC = S.Spec(
    S.DisplayFlow,
    S.AxisRow,
    S.WrapOff,
    S.JustifyStart,
    S.ItemsStretch,
    S.SelfAuto,

    S.Padding(ZERO_SPACE, ZERO_SPACE, ZERO_SPACE, ZERO_SPACE),
    S.Margin(ZERO_MARGIN, ZERO_MARGIN, ZERO_MARGIN, ZERO_MARGIN),
    S.GapSpec(ZERO_SPACE, ZERO_SPACE),

    S.LAuto,
    S.LAuto,
    S.LAuto,
    S.LAuto,
    S.LAuto,
    S.LAuto,

    0,
    1,
    S.BAuto,

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
    S.GapSpec(ZERO_SPACE, ZERO_SPACE),
    S.GridPlacement(1, 1, 1, 1)
)

local function req_matches(req, value)
    return req == S.ReqAny
        or (req == S.ReqOn and value)
        or (req == S.ReqOff and not value)
end

local function bp_matches(cond_bp, env_bp)
    if cond_bp == S.AnyBp or cond_bp == nil then
        return true
    end
    local min_bp = (cond_bp == S.SmUp and Env.Sm)
        or (cond_bp == S.MdUp and Env.Md)
        or (cond_bp == S.LgUp and Env.Lg)
        or (cond_bp == S.XlUp and Env.Xl)
        or (cond_bp == S.X2lUp and Env.X2l)
    return BP_RANK[env_bp] >= BP_RANK[min_bp]
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

local function state_matches(cond_state, state)
    cond_state = cond_state or ANY_STATE_COND
    state = state or NO_STATE
    return req_matches(cond_state.hovered, state.hovered)
       and req_matches(cond_state.focused, state.focused)
       and req_matches(cond_state.active, state.active)
       and req_matches(cond_state.selected, state.selected)
       and req_matches(cond_state.disabled, state.disabled)
end

local function cond_matches(cond, env, state)
    return bp_matches(cond.bp, env.bp)
       and scheme_matches(cond.scheme, env.scheme)
       and motion_matches(cond.motion, env.motion)
       and state_matches(cond.state, state)
end

local function pad_top(v)    return S.DPadTop(v) end
local function pad_right(v)  return S.DPadRight(v) end
local function pad_bottom(v) return S.DPadBottom(v) end
local function pad_left(v)   return S.DPadLeft(v) end

local function margin_top(v)    return S.DMarginTop(v) end
local function margin_right(v)  return S.DMarginRight(v) end
local function margin_bottom(v) return S.DMarginBottom(v) end
local function margin_left(v)   return S.DMarginLeft(v) end

local function gap_x(v) return S.DGapX(v) end
local function gap_y(v) return S.DGapY(v) end
local function grid_gap_x(v) return S.DGridGapX(v) end
local function grid_gap_y(v) return S.DGridGapY(v) end

local expand_decl_phase = pvm.phase("ui.expand_decl", {
    [S.Token] = function(self, env, state)
        if not cond_matches(self.cond, env, state) then
            return pvm.empty()
        end

        local atom = self.atom
        local cls = pvm.classof(atom)

        if cls == S.ADisplay then return pvm.once(S.DDisplay(atom.value)) end
        if cls == S.AAxis then return pvm.once(S.DAxis(atom.value)) end
        if cls == S.AWrap then return pvm.once(S.DWrap(atom.value)) end
        if cls == S.AJustify then return pvm.once(S.DJustify(atom.value)) end
        if cls == S.AItems then return pvm.once(S.DItems(atom.value)) end
        if cls == S.ASelf then return pvm.once(S.DSelf(atom.value)) end

        if cls == S.AGap then
            return pvm.seq({
                gap_x(atom.value), gap_y(atom.value),
                grid_gap_x(atom.value), grid_gap_y(atom.value),
            })
        end
        if cls == S.AGapX then
            return pvm.seq({ gap_x(atom.value), grid_gap_x(atom.value) })
        end
        if cls == S.AGapY then
            return pvm.seq({ gap_y(atom.value), grid_gap_y(atom.value) })
        end

        if cls == S.APad then
            return pvm.seq({
                pad_top(atom.value), pad_right(atom.value),
                pad_bottom(atom.value), pad_left(atom.value),
            })
        end
        if cls == S.APadX then return pvm.seq({ pad_left(atom.value), pad_right(atom.value) }) end
        if cls == S.APadY then return pvm.seq({ pad_top(atom.value), pad_bottom(atom.value) }) end
        if cls == S.APadTop then return pvm.once(pad_top(atom.value)) end
        if cls == S.APadRight then return pvm.once(pad_right(atom.value)) end
        if cls == S.APadBottom then return pvm.once(pad_bottom(atom.value)) end
        if cls == S.APadLeft then return pvm.once(pad_left(atom.value)) end

        if cls == S.AMargin then
            local mv = S.MarginSpace(atom.value)
            return pvm.seq({ margin_top(mv), margin_right(mv), margin_bottom(mv), margin_left(mv) })
        end
        if cls == S.AMarginX then
            local mv = S.MarginSpace(atom.value)
            return pvm.seq({ margin_left(mv), margin_right(mv) })
        end
        if cls == S.AMarginY then
            local mv = S.MarginSpace(atom.value)
            return pvm.seq({ margin_top(mv), margin_bottom(mv) })
        end
        if cls == S.AMarginTop then return pvm.once(margin_top(S.MarginSpace(atom.value))) end
        if cls == S.AMarginRight then return pvm.once(margin_right(S.MarginSpace(atom.value))) end
        if cls == S.AMarginBottom then return pvm.once(margin_bottom(S.MarginSpace(atom.value))) end
        if cls == S.AMarginLeft then return pvm.once(margin_left(S.MarginSpace(atom.value))) end
        if atom == S.AMarginAutoX then return pvm.seq({ margin_left(S.MarginAuto), margin_right(S.MarginAuto) }) end
        if atom == S.AMarginAutoLeft then return pvm.once(margin_left(S.MarginAuto)) end
        if atom == S.AMarginAutoRight then return pvm.once(margin_right(S.MarginAuto)) end

        if cls == S.AWidth then return pvm.once(S.DWidth(atom.value)) end
        if cls == S.AHeight then return pvm.once(S.DHeight(atom.value)) end
        if cls == S.AMinWidth then return pvm.once(S.DMinWidth(atom.value)) end
        if cls == S.AMaxWidth then return pvm.once(S.DMaxWidth(atom.value)) end
        if cls == S.AMinHeight then return pvm.once(S.DMinHeight(atom.value)) end
        if cls == S.AMaxHeight then return pvm.once(S.DMaxHeight(atom.value)) end

        if cls == S.AGrow then return pvm.once(S.DGrow(atom.value)) end
        if cls == S.AShrink then return pvm.once(S.DShrink(atom.value)) end
        if cls == S.ABasis then return pvm.once(S.DBasis(atom.value)) end

        if cls == S.AFg then return pvm.once(S.DFg(atom.value)) end
        if cls == S.ABg then return pvm.once(S.DBg(atom.value)) end
        if cls == S.ABorderColor then return pvm.once(S.DBorderColor(atom.value)) end
        if cls == S.ABorderWidth then return pvm.once(S.DBorderWidth(atom.value)) end
        if cls == S.ARounded then return pvm.once(S.DRadius(atom.value)) end
        if cls == S.AOpacity then return pvm.once(S.DOpacity(atom.value)) end

        if cls == S.ATextSize then return pvm.once(S.DFontSize(atom.value)) end
        if cls == S.ATextWeight then return pvm.once(S.DFontWeight(atom.value)) end
        if cls == S.ATextAlign then return pvm.once(S.DTextAlign(atom.value)) end
        if cls == S.ALeading then return pvm.once(S.DLeading(atom.value)) end
        if cls == S.ATracking then return pvm.once(S.DTracking(atom.value)) end

        if cls == S.AOverflowX then return pvm.once(S.DOverflowX(atom.value)) end
        if cls == S.AOverflowY then return pvm.once(S.DOverflowY(atom.value)) end
        if cls == S.ACursor then return pvm.once(S.DCursor(atom.value)) end

        if cls == S.ACols then return pvm.once(S.DCols(atom.tracks)) end
        if cls == S.ARows then return pvm.once(S.DRows(atom.tracks)) end
        if cls == S.AColGap then return pvm.once(grid_gap_x(atom.value)) end
        if cls == S.ARowGap then return pvm.once(grid_gap_y(atom.value)) end
        if cls == S.AColStart then return pvm.once(S.DColStart(atom.value)) end
        if cls == S.AColSpan then return pvm.once(S.DColSpan(atom.value)) end
        if cls == S.ARowStart then return pvm.once(S.DRowStart(atom.value)) end
        if cls == S.ARowSpan then return pvm.once(S.DRowSpan(atom.value)) end

        error("ui.expand_decl: unhandled style atom", 2)
    end,
})

local expand_decls_phase = pvm.phase("ui.expand_decls", {
    [S.TokenList] = function(self, env, state)
        local items = self.items
        local n = #items
        if n == 0 then
            return pvm.empty()
        end
        local trips = {}
        for i = 1, n do
            local g, p, c = expand_decl_phase(items[i], env, state)
            trips[i] = { g, p, c }
        end
        return pvm.concat_all(trips)
    end,
})

local function with_padding(spec, key, value)
    return pvm.with(spec, { padding = pvm.with(spec.padding, { [key] = value }) })
end

local function with_margin(spec, key, value)
    return pvm.with(spec, { margin = pvm.with(spec.margin, { [key] = value }) })
end

local function with_gap(spec, key, value)
    return pvm.with(spec, { gap = pvm.with(spec.gap, { [key] = value }) })
end

local function with_grid_gap(spec, key, value)
    return pvm.with(spec, { grid_gap = pvm.with(spec.grid_gap, { [key] = value }) })
end

local function with_placement(spec, key, value)
    return pvm.with(spec, { placement = pvm.with(spec.placement, { [key] = value }) })
end

local function apply_decl(spec, decl)
    local cls = pvm.classof(decl)

    if cls == S.DDisplay then return pvm.with(spec, { display = decl.value }) end
    if cls == S.DAxis then return pvm.with(spec, { axis = decl.value }) end
    if cls == S.DWrap then return pvm.with(spec, { wrap = decl.value }) end
    if cls == S.DJustify then return pvm.with(spec, { justify = decl.value }) end
    if cls == S.DItems then return pvm.with(spec, { items = decl.value }) end
    if cls == S.DSelf then return pvm.with(spec, { self_align = decl.value }) end

    if cls == S.DPadTop then return with_padding(spec, "top", decl.value) end
    if cls == S.DPadRight then return with_padding(spec, "right", decl.value) end
    if cls == S.DPadBottom then return with_padding(spec, "bottom", decl.value) end
    if cls == S.DPadLeft then return with_padding(spec, "left", decl.value) end

    if cls == S.DMarginTop then return with_margin(spec, "top", decl.value) end
    if cls == S.DMarginRight then return with_margin(spec, "right", decl.value) end
    if cls == S.DMarginBottom then return with_margin(spec, "bottom", decl.value) end
    if cls == S.DMarginLeft then return with_margin(spec, "left", decl.value) end

    if cls == S.DGapX then return with_gap(spec, "x", decl.value) end
    if cls == S.DGapY then return with_gap(spec, "y", decl.value) end
    if cls == S.DGridGapX then return with_grid_gap(spec, "x", decl.value) end
    if cls == S.DGridGapY then return with_grid_gap(spec, "y", decl.value) end

    if cls == S.DWidth then return pvm.with(spec, { w = decl.value }) end
    if cls == S.DHeight then return pvm.with(spec, { h = decl.value }) end
    if cls == S.DMinWidth then return pvm.with(spec, { min_w = decl.value }) end
    if cls == S.DMaxWidth then return pvm.with(spec, { max_w = decl.value }) end
    if cls == S.DMinHeight then return pvm.with(spec, { min_h = decl.value }) end
    if cls == S.DMaxHeight then return pvm.with(spec, { max_h = decl.value }) end

    if cls == S.DGrow then return pvm.with(spec, { grow = decl.value }) end
    if cls == S.DShrink then return pvm.with(spec, { shrink = decl.value }) end
    if cls == S.DBasis then return pvm.with(spec, { basis = decl.value }) end

    if cls == S.DFg then return pvm.with(spec, { fg = decl.value }) end
    if cls == S.DBg then return pvm.with(spec, { bg = decl.value }) end
    if cls == S.DBorderColor then return pvm.with(spec, { border_color = decl.value }) end
    if cls == S.DBorderWidth then return pvm.with(spec, { border_w = decl.value }) end
    if cls == S.DRadius then return pvm.with(spec, { radius = decl.value }) end
    if cls == S.DOpacity then return pvm.with(spec, { opacity = decl.value }) end

    if cls == S.DFontSize then return pvm.with(spec, { font_size = decl.value }) end
    if cls == S.DFontWeight then return pvm.with(spec, { font_weight = decl.value }) end
    if cls == S.DTextAlign then return pvm.with(spec, { text_align = decl.value }) end
    if cls == S.DLeading then return pvm.with(spec, { leading = decl.value }) end
    if cls == S.DTracking then return pvm.with(spec, { tracking = decl.value }) end

    if cls == S.DOverflowX then return pvm.with(spec, { overflow_x = decl.value }) end
    if cls == S.DOverflowY then return pvm.with(spec, { overflow_y = decl.value }) end
    if cls == S.DCursor then return pvm.with(spec, { cursor = decl.value }) end

    if cls == S.DCols then return pvm.with(spec, { cols = decl.tracks }) end
    if cls == S.DRows then return pvm.with(spec, { rows = decl.tracks }) end
    if cls == S.DColStart then return with_placement(spec, "col_start", decl.value) end
    if cls == S.DColSpan then return with_placement(spec, "col_span", decl.value) end
    if cls == S.DRowStart then return with_placement(spec, "row_start", decl.value) end
    if cls == S.DRowSpan then return with_placement(spec, "row_span", decl.value) end

    error("ui.normalize: unhandled style decl", 2)
end

local normalize_phase = pvm.phase("ui.normalize", function(token_list, env, state)
    local g, p, c = expand_decls_phase(token_list, env, state or NO_STATE)
    return pvm.fold(g, p, c, DEFAULT_SPEC, apply_decl)
end)

M.default_spec = DEFAULT_SPEC
M.any_state_cond = ANY_STATE_COND
M.no_state = NO_STATE
M.expand_decl_phase = expand_decl_phase
M.expand_decls_phase = expand_decls_phase
M.normalize_phase = normalize_phase
M.T = T

return M
