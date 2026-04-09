-- ui/asdl.lua
--
-- Fresh UI library schema, designed for a pvm3-era architecture.
--
-- Architectural layers:
--   Interact  — runtime interaction phases used by styling and session logic
--   Layout    — shared geometry / layout / text-policy vocabulary
--   DS        — design system: themes, surfaces, rules, resolved style packs
--   Runtime   — generic runtime refs for late-bound paint data
--   SemUI     — authored generic UI semantics (surfaces, identity, interaction)
--   UI        — lowered concrete UI tree with resolved styles
--   Facts     — typed measurement / placement facts
--   Paint     — generic custom paint tree + optional flat paint IR
--   Msg       — typed generic UI messages/events
--
-- Notes:
--   - The design-system model keeps the strongest idea from the old uilib:
--       surface + focus + flags -> fully resolved style packs.
--   - Pointer phase is not part of the DS query because resolution precomputes
--     all four pointer variants into packs.
--   - SemUI is the authored layer. UI is the lowered concrete layer.
--   - View/compile IR is intentionally absent; reducers over UI are intended to
--     be canonical, with flat IR only as an optional later product.
--   - Virtualized / source-driven collections are intentionally left out of the
--     core schema for now; they likely want a dedicated source/window algebra
--     above SemUI rather than a naive Node* field here.

local pvm = require("pvm")

local M = {}
local T = pvm.context()
M.T = T

-- ─────────────────────────────────────────────────────────────
-- Interact
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module Interact {
        Pointer = Idle | Hovered | Pressed | Dragging
        Focus = Blurred | Focused
    }
]]

-- ─────────────────────────────────────────────────────────────
-- Layout
-- Shared layout / geometry / text-policy vocabulary.
-- SemUI and UI both refer to these types.
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module Layout {
        Axis = AxisRow | AxisRowReverse | AxisCol | AxisColReverse

        ScrollAxis = ScrollX | ScrollY | ScrollBoth

        FlexWrap = WrapNoWrap | WrapWrap | WrapWrapReverse

        MainAlign = MainStart | MainEnd | MainCenter
                  | MainSpaceBetween | MainSpaceAround | MainSpaceEvenly

        CrossAlign = CrossAuto | CrossStart | CrossEnd
                   | CrossCenter | CrossStretch | CrossBaseline

        ContentAlign = ContentStart | ContentEnd | ContentCenter
                     | ContentStretch
                     | ContentSpaceBetween | ContentSpaceAround | ContentSpaceEvenly

        Size = SizeAuto | SizePx(number px) unique | SizePercent(number ratio) unique | SizeContent

        Basis = BasisAuto | BasisPx(number px) unique
              | BasisPercent(number ratio) unique | BasisContent

        Min = NoMin | MinPx(number px) unique
        Max = NoMax | MaxPx(number px) unique

        TextWrap = TextNoWrap | TextWordWrap | TextCharWrap
        TextAlign = TextStart | TextCenter | TextEnd | TextJustify
        Overflow = OverflowVisible | OverflowClip | OverflowEllipsis

        LineHeight = LineHeightAuto
                   | LineHeightPx(number px) unique
                   | LineHeightScale(number scale) unique

        LineLimit = UnlimitedLines | MaxLines(number count) unique

        Insets = (number l, number t, number r, number b) unique

        Box = (Layout.Size w, Layout.Size h,
               Layout.Min min_w, Layout.Min min_h,
               Layout.Max max_w, Layout.Max max_h) unique
    }
]]

-- ─────────────────────────────────────────────────────────────
-- DS — design system
--
-- Fresh-start changes from old uilib:
--   - flags are now open-ended tokens instead of a fixed enum.
--   - paint, metric, and text rules are split explicitly.
--   - the resolved result is structured, not one giant bag.
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module DS {
        Flag = (string name) unique

        PSel = AnyPointer
             | WhenPointer(Interact.Pointer pointer)

        FSel = AnyFocus
             | WhenFocus(Interact.Focus focus)

        GSel = AnyFlags
             | RequireFlags(DS.Flag* required)

        PaintSel = (DS.PSel pointer,
                    DS.FSel focus,
                    DS.GSel flags) unique

        StateSel = (DS.FSel focus,
                    DS.GSel flags) unique

        ColorVal = ColorTok(string name) unique
                 | ColorLit(number rgba8) unique

        SpaceVal = SpaceTok(string name) unique
                 | SpaceLit(number px) unique

        ScaleVal = ScaleLit(number n) unique

        FontVal = FontTok(string name) unique
                | FontLit(number font_id) unique

        PaintDecl = SetBg(DS.ColorVal val) unique
                  | SetFg(DS.ColorVal val) unique
                  | SetBorder(DS.ColorVal val) unique
                  | SetAccent(DS.ColorVal val) unique
                  | SetRadius(DS.SpaceVal val) unique
                  | SetOpacity(DS.ScaleVal val) unique

        MetricDecl = SetPadH(DS.SpaceVal val) unique
                   | SetPadV(DS.SpaceVal val) unique
                   | SetGap(DS.SpaceVal val) unique
                   | SetGapCross(DS.SpaceVal val) unique
                   | SetBorderWidth(DS.SpaceVal val) unique

        TextDecl = SetFont(DS.FontVal val) unique
                 | SetLineHeight(Layout.LineHeight val) unique
                 | SetTextAlign(Layout.TextAlign val) unique
                 | SetTextWrap(Layout.TextWrap val) unique
                 | SetOverflow(Layout.Overflow val) unique
                 | SetLineLimit(Layout.LineLimit val) unique

        PaintRule = (DS.PaintSel when,
                     DS.PaintDecl* set) unique

        MetricRule = (DS.StateSel when,
                      DS.MetricDecl* set) unique

        TextRule = (DS.StateSel when,
                    DS.TextDecl* set) unique

        Surface = (string name,
                   DS.PaintRule* paint_rules,
                   DS.MetricRule* metric_rules,
                   DS.TextRule* text_rules) unique

        ColorBinding = (string name, number rgba8) unique
        SpaceBinding = (string name, number px) unique
        FontBinding = (string name, number font_id) unique

        Theme = (string name,
                 DS.ColorBinding* colors,
                 DS.SpaceBinding* spaces,
                 DS.FontBinding* fonts,
                 DS.Surface* surfaces) unique

        ColorPack = (number idle, number hovered,
                     number pressed, number dragging) unique

        NumPack = (number idle, number hovered,
                   number pressed, number dragging) unique

        ResolvedPaint = (DS.ColorPack bg,
                         DS.ColorPack fg,
                         DS.ColorPack border,
                         DS.ColorPack accent,
                         DS.NumPack radius,
                         DS.NumPack opacity) unique

        ResolvedMetrics = (number pad_h,
                           number pad_v,
                           number gap,
                           number gap_cross,
                           number border_w) unique

        ResolvedText = (number font_id,
                        Layout.LineHeight line_height,
                        Layout.TextAlign align,
                        Layout.TextWrap wrap,
                        Layout.Overflow overflow,
                        Layout.LineLimit line_limit) unique

        ResolvedStyle = (DS.ResolvedMetrics metrics,
                         DS.ResolvedPaint paint,
                         DS.ResolvedText text) unique

        Query = (DS.Theme theme,
                 string surface,
                 Interact.Focus focus,
                 DS.Flag* flags) unique
    }
]]

-- ─────────────────────────────────────────────────────────────
-- Runtime
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module Runtime {
        NumRef = (string name) unique
        TextRef = (string name) unique
        ColorRef = (string name) unique
    }
]]

-- ─────────────────────────────────────────────────────────────
-- Paint
--
-- Generic custom drawing. This remains intentionally app-agnostic.
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module Paint {
        Scalar = ScalarLit(number n) unique
               | ScalarFromRef(Runtime.NumRef ref) unique

        TextValue = TextLit(string text) unique
                  | TextFromRef(Runtime.TextRef ref) unique

        ColorValue = ColorPackLit(DS.ColorPack pack) unique
                   | ColorFromRef(Runtime.ColorRef ref) unique

        Node = Group(Paint.Node* children) unique
             | ClipRegion(Paint.Scalar x,
                          Paint.Scalar y,
                          Paint.Scalar w,
                          Paint.Scalar h,
                          Paint.Node child) unique
             | Translate(Paint.Scalar tx,
                         Paint.Scalar ty,
                         Paint.Node child) unique
             | FillRect(string tag,
                        Paint.Scalar x,
                        Paint.Scalar y,
                        Paint.Scalar w,
                        Paint.Scalar h,
                        Paint.ColorValue color) unique
             | StrokeRect(string tag,
                          Paint.Scalar x,
                          Paint.Scalar y,
                          Paint.Scalar w,
                          Paint.Scalar h,
                          Paint.Scalar thickness,
                          Paint.ColorValue color) unique
             | Line(string tag,
                    Paint.Scalar x1,
                    Paint.Scalar y1,
                    Paint.Scalar x2,
                    Paint.Scalar y2,
                    Paint.Scalar thickness,
                    Paint.ColorValue color) unique
             | Text(string tag,
                    Paint.Scalar x,
                    Paint.Scalar y,
                    Paint.Scalar w,
                    Paint.Scalar h,
                    number font_id,
                    Paint.ColorValue color,
                    Layout.LineHeight line_height,
                    Layout.TextAlign align,
                    Layout.TextWrap wrap,
                    Layout.Overflow overflow,
                    Layout.LineLimit line_limit,
                    Paint.TextValue text) unique

        Kind = FillRectCmd | StrokeRectCmd | LineCmd | TextCmd
             | PushClipCmd | PopClipCmd | PushTransformCmd | PopTransformCmd

        Cmd = (Paint.Kind kind,
               string tag,
               Paint.Scalar a,
               Paint.Scalar b,
               Paint.Scalar c,
               Paint.Scalar d,
               Paint.Scalar e,
               Paint.Scalar f,
               Paint.ColorValue color,
               number font_id,
               Layout.LineHeight line_height,
               Layout.TextAlign text_align,
               Layout.TextWrap text_wrap,
               Layout.Overflow overflow,
               Layout.LineLimit line_limit,
               Paint.TextValue text) unique
    }
]]

-- ─────────────────────────────────────────────────────────────
-- SemUI — authored generic UI semantics
--
-- This is the library-facing tree. It carries identity, interaction wrappers,
-- surface application, and authored layout.
--
-- Surface(name, flags, child) is a semantic style scope. Lowering threads the
-- resolved style down the subtree and may also emit concrete panel chrome.
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module SemUI {
        FontChoice = UseSurfaceFont
                   | OverrideFont(DS.FontVal font) unique

        LineHeightChoice = UseSurfaceLineHeight
                         | OverrideLineHeight(Layout.LineHeight line_height) unique

        TextAlignChoice = UseSurfaceTextAlign
                        | OverrideTextAlign(Layout.TextAlign align) unique

        TextWrapChoice = UseSurfaceTextWrap
                       | OverrideTextWrap(Layout.TextWrap wrap) unique

        OverflowChoice = UseSurfaceOverflow
                       | OverrideOverflow(Layout.Overflow overflow) unique

        LineLimitChoice = UseSurfaceLineLimit
                        | OverrideLineLimit(Layout.LineLimit line_limit) unique

        TextSpec = (SemUI.FontChoice font,
                    SemUI.LineHeightChoice line_height,
                    SemUI.TextAlignChoice align,
                    SemUI.TextWrapChoice wrap,
                    SemUI.OverflowChoice overflow,
                    SemUI.LineLimitChoice line_limit) unique

        FlexItem = (SemUI.Node node,
                    number grow,
                    number shrink,
                    Layout.Basis basis,
                    Layout.CrossAlign self_align,
                    Layout.Insets margin) unique

        Node = Empty

             | Key(string id,
                   SemUI.Node child) unique

             | HitBox(string id,
                      SemUI.Node child) unique

             | Pressable(string id,
                         SemUI.Node child) unique

             | Focusable(string id,
                         SemUI.Node child) unique

             | Surface(string name,
                       DS.Flag* flags,
                       SemUI.Node child) unique

             | Flex(Layout.Axis axis,
                    Layout.FlexWrap wrap,
                    number gap_main,
                    number gap_cross,
                    Layout.MainAlign justify,
                    Layout.CrossAlign align_items,
                    Layout.ContentAlign align_content,
                    Layout.Box box,
                    SemUI.FlexItem* children) unique

             | Pad(Layout.Insets insets,
                   Layout.Box box,
                   SemUI.Node child) unique

             | Stack(Layout.Box box,
                     SemUI.Node* children) unique

             | Clip(Layout.Box box,
                    SemUI.Node child) unique

             | Transform(number tx, number ty,
                         Layout.Box box,
                         SemUI.Node child) unique

             | Sized(Layout.Box box,
                     SemUI.Node child) unique

             | ScrollArea(string id,
                          Layout.ScrollAxis axis,
                          number scroll_x,
                          number scroll_y,
                          Layout.Box box,
                          SemUI.Node child) unique

             | Rect(string tag,
                    Layout.Box box) unique

             | Text(string tag,
                    Layout.Box box,
                    SemUI.TextSpec spec,
                    string text) unique

             | CustomPaint(string tag,
                           Layout.Box box,
                           Paint.Node paint) unique

             | Overlay(SemUI.Node base,
                       Paint.Node overlay) unique

             | Spacer(Layout.Box box) unique
    }
]]

-- ─────────────────────────────────────────────────────────────
-- UI — lowered concrete UI tree
--
-- This is the reducer-facing tree. Design-system resolution has already happened.
-- Interaction wrappers remain explicit because hit/focus/session reducers still
-- need them.
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module UI {
        BoxStyle = (number pad_h,
                    number pad_v,
                    number border_w,
                    DS.ColorPack bg,
                    DS.ColorPack border,
                    DS.ColorPack accent,
                    DS.NumPack radius,
                    DS.NumPack opacity) unique

        TextStyle = (number font_id,
                     DS.ColorPack color,
                     DS.NumPack opacity,
                     Layout.LineHeight line_height,
                     Layout.TextAlign align,
                     Layout.TextWrap wrap,
                     Layout.Overflow overflow,
                     Layout.LineLimit line_limit) unique

        FlexItem = (UI.Node node,
                    number grow,
                    number shrink,
                    Layout.Basis basis,
                    Layout.CrossAlign self_align,
                    Layout.Insets margin) unique

        Node = Empty

             | Key(string id,
                   UI.Node child) unique

             | HitBox(string id,
                      UI.Node child) unique

             | Pressable(string id,
                         UI.Node child) unique

             | Focusable(string id,
                         UI.Node child) unique

             | Flex(Layout.Axis axis,
                    Layout.FlexWrap wrap,
                    number gap_main,
                    number gap_cross,
                    Layout.MainAlign justify,
                    Layout.CrossAlign align_items,
                    Layout.ContentAlign align_content,
                    Layout.Box box,
                    UI.FlexItem* children) unique

             | Pad(Layout.Insets insets,
                   Layout.Box box,
                   UI.Node child) unique

             | Stack(Layout.Box box,
                     UI.Node* children) unique

             | Clip(Layout.Box box,
                    UI.Node child) unique

             | Transform(number tx, number ty,
                         Layout.Box box,
                         UI.Node child) unique

             | Sized(Layout.Box box,
                     UI.Node child) unique

             | ScrollArea(string id,
                          Layout.ScrollAxis axis,
                          number scroll_x,
                          number scroll_y,
                          Layout.Box box,
                          UI.BoxStyle style,
                          UI.Node child) unique

             | Panel(string tag,
                     Layout.Box box,
                     UI.BoxStyle style,
                     UI.Node child) unique

             | Rect(string tag,
                    Layout.Box box,
                    UI.BoxStyle style) unique

             | Text(string tag,
                    Layout.Box box,
                    UI.TextStyle style,
                    string text) unique

             | CustomPaint(string tag,
                           Layout.Box box,
                           Paint.Node paint) unique

             | Overlay(UI.Node base,
                       Paint.Node overlay) unique

             | Spacer(Layout.Box box) unique
    }
]]

-- ─────────────────────────────────────────────────────────────
-- Facts
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module Facts {
        Span = SpanUnconstrained
             | SpanExact(number px) unique
             | SpanAtMost(number px) unique

        Baseline = NoBaseline | BaselinePx(number px) unique

        Constraint = (Facts.Span w,
                      Facts.Span h) unique

        Frame = (number x, number y,
                 number w, number h) unique

        Intrinsic = (number min_w, number min_h,
                     number max_w, number max_h,
                     Facts.Baseline baseline) unique

        Measure = (Facts.Constraint constraint,
                   Facts.Intrinsic intrinsic,
                   number used_w, number used_h,
                   Facts.Baseline baseline) unique

        ScrollExtent = (number content_w, number content_h,
                        number viewport_w, number viewport_h) unique

        Hit = Miss
            | HitId(string id)
    }
]]

-- ─────────────────────────────────────────────────────────────
-- Msg
--
-- Generic event/message vocabulary for the session layer.
-- ─────────────────────────────────────────────────────────────

T:Define [[
    module Msg {
        Kind = Click
             | Press
             | Release
             | HoverEnter
             | HoverLeave
             | Focus
             | Blur
             | Scroll
             | Change
             | Submit
             | Cancel
             | Custom(string name) unique

        Payload = None
                | Num(number value) unique
                | Bool(boolean value) unique
                | Text(string value) unique
                | Pair(number a, number b) unique

        Event = (Msg.Kind kind,
                 string id,
                 Msg.Payload payload) unique
    }
]]

return M
