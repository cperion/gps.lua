-- uilib2_asdl.lua
--
-- ASDL for uilib2: UI library with design system and pointer-variant paint packs.
--
-- Architecture:
--   Interact      — pointer/focus state (runtime output from interaction tracker)
--   DS            — design system (surfaces, themes, style resolution, color/num packs)
--   Dyn           — runtime slot language for live execution payload
--   UI            — authored recursive layout tree (leaf colors are ColorPacks)
--   Facts         — typed pass facts for measurement and layout
--   View          — flat executable command array (carries ColorPacks, not raw rgba8)
--
-- Key design:
--   DS resolves ALL four pointer variants (idle/hovered/pressed/dragging) at compile time.
--   View.Cmd carries ColorPacks as payload. The paint loop selects one variant by
--   pointer phase — no rule matching, no token lookup, no semantic interpretation.

local pvm = require("pvm")

local M = {}
local T = pvm.context()
M.T = T

-- ─────────────────────────────────────────────────────────────
-- Interact: behavior output
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module Interact {
        Pointer  = Idle | Hovered | Pressed | Dragging
        Focus    = Blurred | Focused
    }
]]

-- ─────────────────────────────────────────────────────────────
-- DS: design system
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module DS {
        Flag         = Active | Disabled | Selected

        Cond         = (Interact.Pointer pointer,
                        Interact.Focus focus,
                        DS.Flag* flags) unique

        PSel         = AnyPointer
                     | WhenPointer(Interact.Pointer p)

        FSel         = AnyFocus
                     | WhenFocus(Interact.Focus f)

        GSel         = AnyFlags
                     | RequireFlags(DS.Flag* required)

        Selector     = (DS.PSel pointer,
                        DS.FSel focus,
                        DS.GSel flags) unique

        StructSel    = (DS.FSel focus,
                        DS.GSel flags) unique

        ColorVal     = ColorTok(string name) unique
                     | ColorLit(number rgba8) unique

        SpaceVal     = SpaceTok(string name) unique
                     | SpaceLit(number px) unique

        ScaleVal     = ScaleLit(number n) unique

        FontVal      = FontTok(string name) unique
                     | FontLit(number font_id) unique

        PaintDecl    = SetBg(DS.ColorVal val) unique
                     | SetFg(DS.ColorVal val) unique
                     | SetBorder(DS.ColorVal val) unique
                     | SetAccent(DS.ColorVal val) unique
                     | SetRadius(DS.SpaceVal val) unique
                     | SetOpacity(DS.ScaleVal val) unique

        PaintRule    = (DS.Selector when,
                        DS.PaintDecl* set) unique

        StructDecl   = SetPadH(DS.SpaceVal val) unique
                     | SetPadV(DS.SpaceVal val) unique
                     | SetGap(DS.SpaceVal val) unique
                     | SetBorderWidth(DS.SpaceVal val) unique
                     | SetFont(DS.FontVal val) unique

        StructRule   = (DS.StructSel when,
                        DS.StructDecl* set) unique

        Surface      = (string name,
                        DS.PaintRule* paint_rules,
                        DS.StructRule* struct_rules) unique

        ColorBinding = (string name, number rgba8) unique
        SpaceBinding = (string name, number px) unique
        FontBinding  = (string name, number font_id) unique

        Theme        = (string name,
                        DS.ColorBinding* colors,
                        DS.SpaceBinding* spaces,
                        DS.FontBinding* fonts,
                        DS.Surface* surfaces) unique

        ColorPack    = (number idle, number hovered,
                        number pressed, number dragging) unique

        NumPack      = (number idle, number hovered,
                        number pressed, number dragging) unique

        Style        = (number pad_h, number pad_v,
                        number gap, number border_w, number font_id,
                        DS.ColorPack bg, DS.ColorPack fg,
                        DS.ColorPack border, DS.ColorPack accent,
                        DS.NumPack radius, DS.NumPack opacity) unique

        Query        = (DS.Theme theme, string surface,
                        Interact.Focus focus, DS.Flag* flags) unique
    }
]]

-- ─────────────────────────────────────────────────────────────
-- Dyn: runtime slot language for live execution payload
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module Dyn {
        Slot = PlayheadX
             | TimeText
             | BeatText
             | MeterLevel(number track_id) unique
    }
]]

-- ─────────────────────────────────────────────────────────────
-- UI: authored layout tree
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module UI {
        Axis = AxisRow | AxisRowReverse | AxisCol | AxisColReverse

        FlexWrap = WrapNoWrap | WrapWrap | WrapWrapReverse

        MainAlign = MainStart | MainEnd | MainCenter
                  | MainSpaceBetween | MainSpaceAround | MainSpaceEvenly

        CrossAlign = CrossAuto | CrossStart | CrossEnd
                   | CrossCenter | CrossStretch | CrossBaseline

        ContentAlign = ContentStart | ContentEnd | ContentCenter
                     | ContentStretch
                     | ContentSpaceBetween | ContentSpaceAround | ContentSpaceEvenly

        Size = SizeAuto | SizePx(number px) | SizePercent(number ratio) | SizeContent

        Basis = BasisAuto | BasisPx(number px)
              | BasisPercent(number ratio) | BasisContent

        Min = NoMin | MinPx(number px)
        Max = NoMax | MaxPx(number px)

        TextWrap = TextNoWrap | TextWordWrap | TextCharWrap

        TextAlign = TextStart | TextCenter | TextEnd | TextJustify

        Overflow = OverflowVisible | OverflowClip | OverflowEllipsis

        LineHeight = LineHeightAuto
                   | LineHeightPx(number px)
                   | LineHeightScale(number scale)

        LineLimit = UnlimitedLines | MaxLines(number count)

        Insets = (number l, number t, number r, number b) unique

        Box = (UI.Size w, UI.Size h,
               UI.Min min_w, UI.Min min_h,
               UI.Max max_w, UI.Max max_h) unique

        TextStyle = (number font_id, DS.ColorPack color,
                     UI.LineHeight line_height,
                     UI.TextAlign align,
                     UI.TextWrap wrap,
                     UI.Overflow overflow,
                     UI.LineLimit line_limit) unique

        FlexItem = (UI.Node node,
                    number grow,
                    number shrink,
                    UI.Basis basis,
                    UI.CrossAlign self_align,
                    UI.Insets margin) unique

        Node = Flex(UI.Axis axis,
                    UI.FlexWrap wrap,
                    number gap_main,
                    number gap_cross,
                    UI.MainAlign justify,
                    UI.CrossAlign align_items,
                    UI.ContentAlign align_content,
                    UI.Box box,
                    UI.FlexItem* children) unique

             | Pad(UI.Insets insets,
                   UI.Box box,
                   UI.Node child) unique

             | Stack(UI.Box box,
                     UI.Node* children) unique

             | Clip(UI.Box box,
                    UI.Node child) unique

             | Transform(number tx, number ty,
                         UI.Box box,
                         UI.Node child) unique

             | Sized(UI.Box box,
                     UI.Node child) unique

             | Rect(string tag,
                    UI.Box box,
                    DS.ColorPack fill) unique

             | Text(string tag,
                    UI.Box box,
                    UI.TextStyle style,
                    string text) unique

             | DynText(string tag,
                       UI.Box box,
                       UI.TextStyle style,
                       Dyn.Slot slot,
                       string sample) unique

             | DynMeter(string tag,
                        UI.Box box,
                        Dyn.Slot slot,
                        DS.ColorPack bg,
                        DS.ColorPack fill,
                        DS.ColorPack hot,
                        DS.ColorPack clip) unique

             | DynPlayhead(string tag,
                           UI.Box box,
                           Dyn.Slot slot,
                           DS.ColorPack color) unique

             | Spacer(UI.Box box) unique
    }
]]

-- ─────────────────────────────────────────────────────────────
-- Facts: typed pass facts for measurement and layout
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module Facts {
        Span = SpanUnconstrained
             | SpanExact(number px)
             | SpanAtMost(number px)

        Baseline = NoBaseline | BaselinePx(number px)

        Constraint = (Facts.Span w, Facts.Span h) unique

        Frame = (number x, number y, number w, number h) unique

        Intrinsic = (number min_w, number min_h,
                     number max_w, number max_h,
                     Facts.Baseline baseline) unique

        Measure = (Facts.Constraint constraint,
                   Facts.Intrinsic intrinsic,
                   number used_w, number used_h,
                   Facts.Baseline baseline) unique

        FlexLine = (number start_idx, number end_idx,
                    number main_used, number cross_used,
                    Facts.Baseline baseline) unique
    }
]]

-- ─────────────────────────────────────────────────────────────
-- View: flat executable command array
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module View {
        Kind = Rect | TextBlock | DynText | DynMeter | DynPlayhead
             | PushClip | PopClip | PushTransform | PopTransform

        Cmd = (View.Kind kind, string htag,
               number x, number y, number w, number h,
               DS.ColorPack color,
               number font_id, string text,
               number tx, number ty,
               UI.TextAlign text_align,
               UI.TextWrap text_wrap,
               UI.Overflow overflow,
               UI.LineHeight line_height,
               Dyn.Slot? slot,
               DS.ColorPack? aux_color1,
               DS.ColorPack? aux_color2,
               DS.ColorPack? aux_color3) unique

        Fragment = (number w, number h, View.Cmd* cmds) unique

        PlanKind = PlaceFragment | PushClipPlan | PopClipPlan
                 | PushTransformPlan | PopTransformPlan

        PlanOp = (View.PlanKind kind,
                  number x, number y, number w, number h,
                  number tx, number ty,
                  View.Fragment? fragment) unique

        Plan = (View.PlanOp* ops) unique
    }
]]

return M
