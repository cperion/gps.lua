local pvm = require("pvm")

local M = {}

function M.Define(T)
    T:Define [[
        module Core {
            Id = NoId
               | IdValue(string value) unique
        }

        module Env {
            Breakpoint = Sm | Md | Lg | Xl | X2l
            Scheme = Light | Dark
            Motion = MotionSafe | MotionReduce
            Density = D1x | D2x | D3x

            Class = (Env.Breakpoint bp,
                     Env.Scheme scheme,
                     Env.Motion motion,
                     Env.Density density) unique
        }

        module Style {
            Space = S0 | S0_5 | S1 | S1_5 | S2 | S2_5 | S3 | S3_5
                  | S4 | S5 | S6 | S7 | S8 | S9 | S10 | S11 | S12
                  | S14 | S16 | S20 | S24 | S28 | S32 | S36 | S40
                  | S44 | S48 | S52 | S56 | S60 | S64 | S72 | S80
                  | S96 | SPx

            Fraction = F1_2 | F1_3 | F2_3
                     | F1_4 | F2_4 | F3_4
                     | F1_5 | F2_5 | F3_5 | F4_5
                     | F1_6 | F2_6 | F3_6 | F4_6 | F5_6
                     | FFull

            ColorScale = Slate | Gray | Zinc | Neutral | Stone
                       | Red | Orange | Amber | Yellow | Lime | Green
                       | Emerald | Teal | Cyan | Sky | Blue | Indigo
                       | Violet | Purple | Fuchsia | Pink | Rose
                       | White | Black | Transparent

            Shade = S50 | S100 | S200 | S300 | S400
                  | S500 | S600 | S700 | S800 | S900 | S950

            ColorRef = Palette(Style.ColorScale scale, Style.Shade shade) unique
                     | WhiteRef
                     | BlackRef
                     | TransparentRef

            Radius = R0 | RSm | RBase | RMd | RLg | RXl | R2xl | R3xl | RFull
            BorderW = BW0 | BW1 | BW2 | BW4 | BW8

            Opacity = O0 | O5 | O10 | O20 | O25 | O30 | O40 | O50
                    | O60 | O70 | O75 | O80 | O90 | O95 | O100

            FontSize = TxtXs | TxtSm | TxtBase | TxtLg | TxtXl
                     | Txt2xl | Txt3xl | Txt4xl | Txt5xl | Txt6xl

            FontWeight = Thin | ExtraLight | Light | Normal | Medium
                       | Semibold | Bold | ExtraBold | WeightBlack

            TextAlign = TLeft | TCenter | TRight | TJustify

            Leading = LeadingNone | LeadingTight | LeadingSnug
                    | LeadingNormal | LeadingRelaxed | LeadingLoose

            Tracking = TrackingTighter | TrackingTight | TrackingNormal
                     | TrackingWide | TrackingWider | TrackingWidest

            Cursor = CursorDefault | CursorPointer | CursorText
                   | CursorMove | CursorGrab | CursorGrabbing
                   | CursorNotAllowed

            Overflow = OverflowVisible | OverflowHidden | OverflowScroll | OverflowAuto

            Axis = Row | Col
            Wrap = NoWrap | WrapOn

            Justify = JustifyStart | JustifyCenter | JustifyEnd
                    | JustifyBetween | JustifyAround | JustifyEvenly

            Items = ItemsStart | ItemsCenter | ItemsEnd | ItemsStretch | ItemsBaseline
            Self = SelfAuto | SelfStart | SelfCenter | SelfEnd | SelfStretch | SelfBaseline

            Display = DisplayFlow | DisplayFlex | DisplayGrid

            Length = Auto
                   | Hug
                   | Fill
                   | Fixed(number px) unique
                   | Frac(Style.Fraction value) unique

            Basis = BasisAuto
                  | BasisHug
                  | BasisFixed(number px) unique
                  | BasisFrac(Style.Fraction value) unique

            Track = TrackAuto
                  | TrackFr(number fr) unique
                  | TrackFixed(number px) unique
                  | TrackMinMax(number min_px, number max_px) unique

            BpCond = AnyBp | SmUp | MdUp | LgUp | XlUp | X2lUp
            SchemeCond = AnyScheme | LightOnly | DarkOnly
            MotionCond = AnyMotion | MotionSafeOnly | MotionReduceOnly

            Cond = (Style.BpCond bp,
                    Style.SchemeCond scheme,
                    Style.MotionCond motion) unique

            Atom = SetDisplay(Style.Display value) unique
                 | SetAxis(Style.Axis value) unique
                 | WrapMode(Style.Wrap value) unique
                 | JustifyMode(Style.Justify value) unique
                 | ItemsMode(Style.Items value) unique
                 | SelfMode(Style.Self value) unique

                 | Gap(Style.Space value) unique
                 | GapX(Style.Space value) unique
                 | GapY(Style.Space value) unique

                 | P(Style.Space value) unique
                 | PX(Style.Space value) unique
                 | PY(Style.Space value) unique
                 | PT(Style.Space value) unique
                 | PR(Style.Space value) unique
                 | PB(Style.Space value) unique
                 | PL(Style.Space value) unique

                 | M(Style.Space value) unique
                 | MX(Style.Space value) unique
                 | MY(Style.Space value) unique
                 | MT(Style.Space value) unique
                 | MR(Style.Space value) unique
                 | MB(Style.Space value) unique
                 | ML(Style.Space value) unique
                 | MAutoX
                 | MAutoL
                 | MAutoR

                 | W(Style.Length value) unique
                 | H(Style.Length value) unique
                 | MinW(Style.Length value) unique
                 | MaxW(Style.Length value) unique
                 | MinH(Style.Length value) unique
                 | MaxH(Style.Length value) unique

                 | Grow(number value) unique
                 | Shrink(number value) unique
                 | SetBasis(Style.Basis value) unique

                 | Fg(Style.ColorRef value) unique
                 | Bg(Style.ColorRef value) unique
                 | BorderColor(Style.ColorRef value) unique
                 | BorderWidth(Style.BorderW value) unique
                 | Rounded(Style.Radius value) unique
                 | OpacityValue(Style.Opacity value) unique

                 | TextSize(Style.FontSize value) unique
                 | TextWeight(Style.FontWeight value) unique
                 | TextAlignMode(Style.TextAlign value) unique
                 | LeadingValue(Style.Leading value) unique
                 | TrackingValue(Style.Tracking value) unique

                 | OverflowX(Style.Overflow value) unique
                 | OverflowY(Style.Overflow value) unique
                 | CursorValue(Style.Cursor value) unique

                 | Cols(Style.Track* tracks) unique
                 | Rows(Style.Track* tracks) unique
                 | ColGap(Style.Space value) unique
                 | RowGap(Style.Space value) unique

                 | ColStart(number value) unique
                 | ColSpan(number value) unique
                 | RowStart(number value) unique
                 | RowSpan(number value) unique

            Token = (Style.Cond cond,
                     Style.Atom atom) unique

            TokenList = (Style.Token* items) unique
            Group = (Style.Token* items) unique

            MarginVal = MAuto
                      | MSpace(Style.Space value) unique

            Padding = (Style.Space top,
                       Style.Space right,
                       Style.Space bottom,
                       Style.Space left) unique

            Margin = (Style.MarginVal top,
                      Style.MarginVal right,
                      Style.MarginVal bottom,
                      Style.MarginVal left) unique

            GapSpec = (Style.Space x,
                       Style.Space y) unique

            GridPlacement = (number col_start,
                             number col_span,
                             number row_start,
                             number row_span) unique

            Spec = (Style.Display display,
                    Style.Axis axis,
                    Style.Wrap wrap,
                    Style.Justify justify,
                    Style.Items items,
                    Style.Self self_align,

                    Style.Padding padding,
                    Style.Margin margin,
                    Style.GapSpec gap,

                    Style.Length w,
                    Style.Length h,
                    Style.Length min_w,
                    Style.Length max_w,
                    Style.Length min_h,
                    Style.Length max_h,

                    number grow,
                    number shrink,
                    Style.Basis basis,

                    Style.ColorRef fg,
                    Style.ColorRef bg,
                    Style.ColorRef border_color,
                    Style.BorderW border_w,
                    Style.Radius radius,
                    Style.Opacity opacity,

                    Style.FontSize font_size,
                    Style.FontWeight font_weight,
                    Style.TextAlign text_align,
                    Style.Leading leading,
                    Style.Tracking tracking,

                    Style.Overflow overflow_x,
                    Style.Overflow overflow_y,
                    Style.Cursor cursor,

                    Style.Track* cols,
                    Style.Track* rows,
                    Style.GapSpec grid_gap,
                    Style.GridPlacement placement) unique
        }

        module Theme {
            Palette = (number s50, number s100, number s200, number s300,
                       number s400, number s500, number s600, number s700,
                       number s800, number s900, number s950) unique

            SpaceScale = (number s0, number s0_5, number s1, number s1_5,
                          number s2, number s2_5, number s3, number s3_5,
                          number s4, number s5, number s6, number s7,
                          number s8, number s9, number s10, number s11,
                          number s12, number s14, number s16, number s20,
                          number s24, number s28, number s32, number s36,
                          number s40, number s44, number s48, number s52,
                          number s56, number s60, number s64, number s72,
                          number s80, number s96, number px) unique

            FontScale = (number xs, number sm, number base, number lg,
                         number xl, number x2l, number x3l,
                         number x4l, number x5l, number x6l) unique

            RadiusScale = (number r0, number rsm, number rbase, number rmd,
                           number rlg, number rxl, number r2xl,
                           number r3xl, number rfull) unique

            BorderScale = (number bw0, number bw1, number bw2,
                           number bw4, number bw8) unique

            OpacityScale = (number o0, number o5, number o10, number o20,
                            number o25, number o30, number o40, number o50,
                            number o60, number o70, number o75, number o80,
                            number o90, number o95, number o100) unique

            Fonts = (number regular,
                     number medium,
                     number semibold,
                     number bold,
                     number mono) unique

            T = (Theme.Palette slate, Theme.Palette gray, Theme.Palette zinc,
                 Theme.Palette neutral, Theme.Palette stone,
                 Theme.Palette red, Theme.Palette orange, Theme.Palette amber,
                 Theme.Palette yellow, Theme.Palette lime, Theme.Palette green,
                 Theme.Palette emerald, Theme.Palette teal, Theme.Palette cyan,
                 Theme.Palette sky, Theme.Palette blue, Theme.Palette indigo,
                 Theme.Palette violet, Theme.Palette purple, Theme.Palette fuchsia,
                 Theme.Palette pink, Theme.Palette rose,
                 number white,
                 number black,
                 number transparent,
                 Theme.SpaceScale spacing,
                 Theme.FontScale font_sizes,
                 Theme.RadiusScale radii,
                 Theme.BorderScale borders,
                 Theme.OpacityScale opacities,
                 Theme.Fonts fonts) unique
        }

        module Auth {
            Node = Box(Core.Id id,
                       Style.TokenList styles,
                       Auth.Node* children) unique
                 | Text(Core.Id id,
                        Style.TokenList styles,
                        string content) unique
                 | Fragment(Auth.Node* children) unique
                 | Empty unique
        }

        module Layout {
            Constraint = (number max_w,
                          number max_h) unique

            Size = (number w,
                    number h,
                    number baseline) unique

            Axis = LRow | LCol
            Wrap = LNoWrap | LWrap

            MainAlign = MStart | MCenter | MEnd | MBetween | MAround | MEvenly
            CrossAlign = CStart | CCenter | CEnd | CStretch | CBaseline
            SelfAlign = SelfAuto | SelfStart | SelfCenter | SelfEnd | SelfStretch | SelfBaseline

            Sizing = SAuto
                   | SHug
                   | SFill
                   | SFixed(number px) unique
                   | SFrac(number value) unique

            Basis = BasisAuto
                  | BasisHug
                  | BasisFixed(number px) unique
                  | BasisFrac(number value) unique

            Min = NoMin | MinPx(number px) unique | MinFrac(number value) unique
            Max = NoMax | MaxPx(number px) unique | MaxFrac(number value) unique

            Overflow = OVisible | OHidden | OScroll | OAuto

            Edges = (number top,
                     number right,
                     number bottom,
                     number left) unique

            MarginVal = MarginAuto
                      | MarginPx(number px) unique

            Margin = (Layout.MarginVal top,
                      Layout.MarginVal right,
                      Layout.MarginVal bottom,
                      Layout.MarginVal left) unique

            Visual = (number bg,
                      number fg,
                      number border_color,
                      number border_w,
                      number radius,
                      number opacity) unique

            TextStyle = (number font_id,
                         number font_size,
                         number font_weight,
                         number fg,
                         number align,
                         number leading,
                         number tracking,
                         string content) unique

            TextLayout = (Layout.TextStyle style,
                          number max_w,
                          number measured_w,
                          number measured_h,
                          number baseline) unique

            Track = TrackAuto
                  | TrackFr(number fr) unique
                  | TrackFixed(number px) unique
                  | TrackMinMax(number min_px, number max_px) unique

            BoxStyle = (Layout.Sizing w,
                        Layout.Sizing h,
                        Layout.Min min_w,
                        Layout.Max max_w,
                        Layout.Min min_h,
                        Layout.Max max_h,
                        number grow,
                        number shrink,
                        Layout.Basis basis,
                        Layout.SelfAlign self_align,
                        Layout.Edges padding,
                        Layout.Margin margin,
                        Layout.Visual visual,
                        Layout.Overflow overflow_x,
                        Layout.Overflow overflow_y,
                        Style.Cursor cursor) unique

            GridItem = (Layout.Node node,
                        number col_start,
                        number col_span,
                        number row_start,
                        number row_span,
                        Layout.CrossAlign col_align,
                        Layout.CrossAlign row_align) unique

            Node = Flex(Core.Id id,
                        Layout.BoxStyle box,
                        Layout.Axis axis,
                        Layout.Wrap wrap,
                        Layout.MainAlign justify,
                        Layout.CrossAlign items,
                        number gap_x,
                        number gap_y,
                        Layout.Node* children) unique

                 | Grid(Core.Id id,
                        Layout.BoxStyle box,
                        Layout.Track* cols,
                        Layout.Track* rows,
                        number col_gap,
                        number row_gap,
                        Layout.GridItem* items) unique

                 | Leaf(Core.Id id,
                        Layout.BoxStyle box,
                        Layout.TextStyle? text) unique
        }

        module Resolve {
            TextStyle = (number font_id,
                         number font_size,
                         number font_weight,
                         number fg,
                         number align,
                         number leading,
                         number tracking) unique

            GridPlacement = (number col_start,
                             number col_span,
                             number row_start,
                             number row_span,
                             Layout.CrossAlign col_align,
                             Layout.CrossAlign row_align) unique

            Style = (Style.Display display,
                     Layout.Axis axis,
                     Layout.Wrap wrap,
                     Layout.MainAlign justify,
                     Layout.CrossAlign items,
                     Layout.BoxStyle box,
                     Resolve.TextStyle text,
                     Layout.Track* cols,
                     Layout.Track* rows,
                     number gap_x,
                     number gap_y,
                     number col_gap,
                     number row_gap,
                     Resolve.GridPlacement placement) unique
        }

        module View {
            Kind = Rect | Text | PushClip | PopClip

            Cmd = (View.Kind kind,
                   Core.Id id,
                   number x,
                   number y,
                   number w,
                   number h,
                   Layout.Visual? visual,
                   Layout.TextLayout? text_layout) unique

            Hit = (Core.Id id,
                   number x,
                   number y,
                   number w,
                   number h,
                   number z) unique

            FocusItem = (Core.Id id,
                         number order,
                         number x,
                         number y,
                         number w,
                         number h) unique

            CursorRegion = (Core.Id id,
                            Style.Cursor cursor,
                            number x,
                            number y,
                            number w,
                            number h) unique

            Frame = (View.Cmd* draw,
                     View.Hit* hit,
                     View.FocusItem* focus,
                     View.CursorRegion* cursors) unique
        }

        module Interact {
            Hover = NoHover
                  | Hovered(Core.Id id) unique

            Focus = NoFocus
                  | Focused(Core.Id id,
                            number slot) unique

            Drag = NoDrag
                 | DragPending(Core.Id id) unique
                 | Dragging(Core.Id id) unique

            State = (Interact.Hover hover,
                     Interact.Focus focus,
                     Interact.Drag drag) unique
        }

        module Solve {
            Scroll = (Core.Id id,
                      number x,
                      number y) unique

            Env = (number vw,
                   number vh,
                   Solve.Scroll* scrolls) unique
        }
    ]]
    return T
end

M.T = M.Define(pvm.context())

return M
