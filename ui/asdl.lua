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

            ScrollAxis = ScrollX | ScrollY | ScrollBoth

            Overflow = OverflowVisible | OverflowHidden | OverflowScroll | OverflowAuto

            Display = DisplayFlow | DisplayFlex | DisplayGrid
            Axis = AxisRow | AxisCol
            Wrap = WrapOff | WrapOn

            Justify = JustifyStart | JustifyCenter | JustifyEnd
                    | JustifyBetween | JustifyAround | JustifyEvenly

            Items = ItemsStart | ItemsCenter | ItemsEnd | ItemsStretch | ItemsBaseline
            Self = SelfAuto | SelfStart | SelfCenter | SelfEnd | SelfStretch | SelfBaseline

            Length = LAuto
                   | LHug
                   | LFill
                   | LFixed(number px) unique
                   | LFrac(Style.Fraction value) unique

            Basis = BAuto
                  | BHug
                  | BFixed(number px) unique
                  | BFrac(Style.Fraction value) unique

            Track = TAuto
                  | TFr(number fr) unique
                  | TFixed(number px) unique
                  | TMinMax(number min_px, number max_px) unique

            BpCond = AnyBp | SmUp | MdUp | LgUp | XlUp | X2lUp
            SchemeCond = AnyScheme | LightOnly | DarkOnly
            MotionCond = AnyMotion | MotionSafeOnly | MotionReduceOnly

            Cond = (Style.BpCond bp,
                    Style.SchemeCond scheme,
                    Style.MotionCond motion) unique

            Atom = ADisplay(Style.Display value) unique
                 | AAxis(Style.Axis value) unique
                 | AWrap(Style.Wrap value) unique
                 | AJustify(Style.Justify value) unique
                 | AItems(Style.Items value) unique
                 | ASelf(Style.Self value) unique

                 | AGap(Style.Space value) unique
                 | AGapX(Style.Space value) unique
                 | AGapY(Style.Space value) unique

                 | APad(Style.Space value) unique
                 | APadX(Style.Space value) unique
                 | APadY(Style.Space value) unique
                 | APadTop(Style.Space value) unique
                 | APadRight(Style.Space value) unique
                 | APadBottom(Style.Space value) unique
                 | APadLeft(Style.Space value) unique

                 | AMargin(Style.Space value) unique
                 | AMarginX(Style.Space value) unique
                 | AMarginY(Style.Space value) unique
                 | AMarginTop(Style.Space value) unique
                 | AMarginRight(Style.Space value) unique
                 | AMarginBottom(Style.Space value) unique
                 | AMarginLeft(Style.Space value) unique
                 | AMarginAutoX
                 | AMarginAutoLeft
                 | AMarginAutoRight

                 | AWidth(Style.Length value) unique
                 | AHeight(Style.Length value) unique
                 | AMinWidth(Style.Length value) unique
                 | AMaxWidth(Style.Length value) unique
                 | AMinHeight(Style.Length value) unique
                 | AMaxHeight(Style.Length value) unique

                 | AGrow(number value) unique
                 | AShrink(number value) unique
                 | ABasis(Style.Basis value) unique

                 | AFg(Style.ColorRef value) unique
                 | ABg(Style.ColorRef value) unique
                 | ABorderColor(Style.ColorRef value) unique
                 | ABorderWidth(Style.BorderW value) unique
                 | ARounded(Style.Radius value) unique
                 | AOpacity(Style.Opacity value) unique

                 | ATextSize(Style.FontSize value) unique
                 | ATextWeight(Style.FontWeight value) unique
                 | ATextAlign(Style.TextAlign value) unique
                 | ALeading(Style.Leading value) unique
                 | ATracking(Style.Tracking value) unique

                 | AOverflowX(Style.Overflow value) unique
                 | AOverflowY(Style.Overflow value) unique
                 | ACursor(Style.Cursor value) unique

                 | ACols(Style.Track* tracks) unique
                 | ARows(Style.Track* tracks) unique
                 | AColGap(Style.Space value) unique
                 | ARowGap(Style.Space value) unique

                 | AColStart(number value) unique
                 | AColSpan(number value) unique
                 | ARowStart(number value) unique
                 | ARowSpan(number value) unique

            Token = (Style.Cond cond,
                     Style.Atom atom) unique

            TokenList = (Style.Token* items) unique
            Group = (Style.Token* items) unique

            MarginVal = MarginAuto
                      | MarginSpace(Style.Space value) unique

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

            Decl = DDisplay(Style.Display value) unique
                 | DAxis(Style.Axis value) unique
                 | DWrap(Style.Wrap value) unique
                 | DJustify(Style.Justify value) unique
                 | DItems(Style.Items value) unique
                 | DSelf(Style.Self value) unique

                 | DPadTop(Style.Space value) unique
                 | DPadRight(Style.Space value) unique
                 | DPadBottom(Style.Space value) unique
                 | DPadLeft(Style.Space value) unique

                 | DMarginTop(Style.MarginVal value) unique
                 | DMarginRight(Style.MarginVal value) unique
                 | DMarginBottom(Style.MarginVal value) unique
                 | DMarginLeft(Style.MarginVal value) unique

                 | DGapX(Style.Space value) unique
                 | DGapY(Style.Space value) unique
                 | DGridGapX(Style.Space value) unique
                 | DGridGapY(Style.Space value) unique

                 | DWidth(Style.Length value) unique
                 | DHeight(Style.Length value) unique
                 | DMinWidth(Style.Length value) unique
                 | DMaxWidth(Style.Length value) unique
                 | DMinHeight(Style.Length value) unique
                 | DMaxHeight(Style.Length value) unique

                 | DGrow(number value) unique
                 | DShrink(number value) unique
                 | DBasis(Style.Basis value) unique

                 | DFg(Style.ColorRef value) unique
                 | DBg(Style.ColorRef value) unique
                 | DBorderColor(Style.ColorRef value) unique
                 | DBorderWidth(Style.BorderW value) unique
                 | DRadius(Style.Radius value) unique
                 | DOpacity(Style.Opacity value) unique

                 | DFontSize(Style.FontSize value) unique
                 | DFontWeight(Style.FontWeight value) unique
                 | DTextAlign(Style.TextAlign value) unique
                 | DLeading(Style.Leading value) unique
                 | DTracking(Style.Tracking value) unique

                 | DOverflowX(Style.Overflow value) unique
                 | DOverflowY(Style.Overflow value) unique
                 | DCursor(Style.Cursor value) unique

                 | DCols(Style.Track* tracks) unique
                 | DRows(Style.Track* tracks) unique
                 | DColStart(number value) unique
                 | DColSpan(number value) unique
                 | DRowStart(number value) unique
                 | DRowSpan(number value) unique

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

        module Paint {
            Stroke = (number rgba8,
                      number width) unique

            Fill = NoFill
                 | SolidFill(number rgba8) unique

            MeshMode = MeshTriangles | MeshStrip | MeshFan

            Vertex = (number x,
                      number y,
                      number u,
                      number v) unique

            Program = Line(number x1,
                           number y1,
                           number x2,
                           number y2,
                           Paint.Stroke stroke) unique

                    | Polyline(number* xy,
                               Paint.Stroke stroke) unique

                    | Polygon(number* xy,
                              Paint.Fill fill,
                              Paint.Stroke? stroke) unique

                    | Circle(number cx,
                             number cy,
                             number r,
                             Paint.Fill fill,
                             Paint.Stroke? stroke) unique

                    | Arc(number cx,
                          number cy,
                          number r,
                          number a1,
                          number a2,
                          number segments,
                          Paint.Stroke stroke) unique

                    | Bezier(number* xy,
                             number segments,
                             Paint.Stroke stroke) unique

                    | Mesh(Paint.MeshMode mode,
                           Paint.Vertex* vertices,
                           Core.Id? image_id,
                           number tint_rgba8,
                           number opacity) unique

                    | Image(Core.Id image_id,
                            number src_x,
                            number src_y,
                            number src_w,
                            number src_h,
                            number tint_rgba8,
                            number opacity) unique

            ProgramList = (Paint.Program* items) unique
        }

        module Auth {
            Node = Box(Core.Id id,
                       Style.TokenList styles,
                       Auth.Node* children) unique
                 | Text(Core.Id id,
                        Style.TokenList styles,
                        string content) unique
                 | Paint(Core.Id id,
                         Style.TokenList styles,
                         Paint.ProgramList paint) unique
                 | Scroll(Core.Id id,
                          Style.TokenList styles,
                          Style.ScrollAxis axis,
                          Auth.Node child) unique
                 | WithInput(Core.Id id,
                             Interact.Role role,
                             Auth.Node child) unique
                 | Fragment(Auth.Node* children) unique
                 | Empty unique
        }

        module Resolved {
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
                             number row_span) unique

            Style = (Style.Display display,
                     Layout.Axis axis,
                     Layout.Wrap wrap,
                     Layout.MainAlign justify,
                     Layout.CrossAlign items,
                     Layout.BoxStyle box,
                     Resolved.TextStyle text,
                     Layout.Track* cols,
                     Layout.Track* rows,
                     number gap_x,
                     number gap_y,
                     number col_gap,
                     number row_gap,
                     Resolved.GridPlacement placement) unique
        }

        module Layout {
            Constraint = (number max_w,
                          number max_h) unique

            Size = (number w,
                    number h,
                    number baseline) unique

            Axis = LRow | LCol
            Wrap = LWrapOff | LWrapOn

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
                          number baseline,
                          string* lines) unique

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

            Node = Flow(Core.Id id,
                        Layout.BoxStyle box,
                        Layout.MainAlign justify,
                        Layout.CrossAlign items,
                        number gap_y,
                        Layout.Node* children) unique

                 | Flex(Core.Id id,
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

                 | Paint(Core.Id id,
                         Layout.BoxStyle box,
                         Paint.ProgramList paint) unique

                 | Scroll(Core.Id id,
                          Layout.BoxStyle box,
                          Style.ScrollAxis axis,
                          Layout.Node child) unique

                 | WithInput(Core.Id id,
                             Interact.Role role,
                             Layout.Node child) unique
        }

        module View {
            Kind = KRect | KText | KPaint | KPushClip | KPopClip | KPushTx | KPopTx
                 | KPushScroll | KPopScroll
                 | KHit | KFocus | KCursor

            Op = (View.Kind kind,
                  Core.Id id,
                  number x,
                  number y,
                  number w,
                  number h,
                  number dx,
                  number dy,
                  Layout.Visual? visual,
                  Layout.TextLayout? text,
                  Style.Cursor? cursor,
                  Style.ScrollAxis? scroll_axis,
                  Paint.ProgramList? paint) unique
        }

        module Interact {
            Role = Passive | HitTarget | FocusTarget | ActivateTarget | EditTarget

            Hover = NoHover
                  | Hovered(Core.Id id) unique

            Focus = NoFocus
                  | Focused(Core.Id id,
                            number slot) unique

            Drag = NoDrag
                 | DragPending(Core.Id id) unique
                 | Dragging(Core.Id id) unique

            HitBox = (Core.Id id,
                      number x,
                      number y,
                      number w,
                      number h) unique

            FocusBox = (Core.Id id,
                        number slot,
                        number x,
                        number y,
                        number w,
                        number h) unique

            ScrollBox = (Core.Id id,
                         Style.ScrollAxis axis,
                         number x,
                         number y,
                         number w,
                         number h) unique

            Report = (Core.Id hover_id,
                      Core.Id cursor_id,
                      Style.Cursor cursor,
                      Core.Id scroll_id,
                      Interact.HitBox* hits,
                      Interact.FocusBox* focusables,
                      Interact.ScrollBox* scrollables) unique

            Button = BtnLeft | BtnMiddle | BtnRight

            Raw = PointerMoved(number x, number y) unique
                | PointerPressed(Interact.Button button,
                                 number x,
                                 number y) unique
                | PointerReleased(Interact.Button button,
                                  number x,
                                  number y) unique
                | WheelMoved(number dx,
                             number dy,
                             number x,
                             number y) unique
                | FocusNext
                | FocusPrev
                | ActivateFocus

            Event = SetPointer(number x,
                               number y) unique
                  | SetHover(Core.Id id) unique
                  | ClearHover
                  | SetFocus(Core.Id id) unique
                  | ClearFocus
                  | Activate(Core.Id id) unique
                  | ScrollBy(Core.Id id,
                             number dx,
                             number dy) unique

            Model = (number pointer_x,
                     number pointer_y,
                     Core.Id hover_id,
                     Core.Id focus_id,
                     Solve.Scroll* scrolls) unique

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
