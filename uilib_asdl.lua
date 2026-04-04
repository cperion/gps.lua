-- uilib_asdl.lua
--
-- Target ASDL for the redesigned UI library.
--
-- Architecture:
--   Layer 1: UI.Node      -- authored recursive layout tree
--   Facts:  typed pass facts (constraints, measures, frames, flex lines)
--   Layer 2: View.Cmd     -- flat executable command array
--
-- Notes:
--   * There is intentionally NO recursive Layout.Node layer.
--   * Multi-pass layout is expressed as passes over UI.Node using Facts.*.
--   * All structural distinctions are modeled in ASDL:
--       - sizing modes
--       - flex basis
--       - wrapping
--       - alignment
--       - overflow
--       - text behavior
--       - command kinds

local pvm = require("pvm")

local M = {}
local T = pvm.context()

M.T = T

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
-- UI: authored layout language
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

        TextStyle = (number font_id, number rgba8,
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
                    number rgba8) unique

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
                        number bg_rgba8,
                        number fill_rgba8,
                        number hot_rgba8,
                        number clip_rgba8) unique

             | DynPlayhead(string tag,
                           UI.Box box,
                           Dyn.Slot slot,
                           number rgba8) unique

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
-- View: flat executable command language
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module View {
        Kind = Rect | TextBlock | DynText | DynMeter | DynPlayhead
             | PushClip | PopClip | PushTransform | PopTransform

        Cmd = (View.Kind kind, string htag,
               number x, number y, number w, number h,
               number rgba8, number font_id, string text,
               number tx, number ty,
               UI.TextAlign text_align,
               UI.TextWrap text_wrap,
               UI.Overflow overflow,
               UI.LineHeight line_height,
               Dyn.Slot? slot,
               number aux0, number aux1, number aux2) unique

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
