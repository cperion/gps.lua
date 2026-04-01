package.path = table.concat({
    "../../?.lua",
    "../../?/init.lua",
    package.path,
}, ";")

local M = require("gps")
local Paint = require("examples/ui/lovepaint")(M)
local Hit = require("examples/ui/hittest")(M)

-- ──────────────────────────────────────────────────────────────
-- VIEW LAYER
-- ──────────────────────────────────────────────────────────────

local V = M.context("paint_ast")
    :Define [[
        module View {
            Root = (VNode* nodes) unique

            VNode = Group(VNode* children) unique
                  | Clip(number x, number y, number w, number h, VNode* body) unique
                  | Transform(number tx, number ty, VNode* body) unique
                  | Box(string tag, number x, number y, number w, number h, number rgba8) unique
                  | Label(string tag, number x, number y, number w, number h, number font_id, number rgba8, string text) unique
        }
    ]]

function V.View.Root:paint_ast()
    local out = {}
    for i = 1, #self.nodes do out[i] = self.nodes[i]:paint_ast() end
    return Paint.LovePaint.Frame({ Paint.LovePaint.Screen(out) })
end

function V.View.Root:hit_ast()
    local out = {}
    for i = 1, #self.nodes do out[i] = self.nodes[i]:hit_ast() end
    return Hit.Hit.Root(out)
end

function V.View.Group:paint_ast()
    local out = {}
    for i = 1, #self.children do out[i] = self.children[i]:paint_ast() end
    return Paint.LovePaint.Group(out)
end

function V.View.Group:hit_ast()
    local out = {}
    for i = 1, #self.children do out[i] = self.children[i]:hit_ast() end
    return Hit.Hit.Group(out)
end

function V.View.Clip:paint_ast()
    local out = {}
    for i = 1, #self.body do out[i] = self.body[i]:paint_ast() end
    return Paint.LovePaint.Clip(self.x, self.y, self.w, self.h, out)
end

function V.View.Clip:hit_ast()
    local out = {}
    for i = 1, #self.body do out[i] = self.body[i]:hit_ast() end
    return Hit.Hit.Clip(self.x, self.y, self.w, self.h, out)
end

function V.View.Transform:paint_ast()
    local out = {}
    for i = 1, #self.body do out[i] = self.body[i]:paint_ast() end
    return Paint.LovePaint.Transform(self.tx, self.ty, out)
end

function V.View.Transform:hit_ast()
    local out = {}
    for i = 1, #self.body do out[i] = self.body[i]:hit_ast() end
    return Hit.Hit.Transform(self.tx, self.ty, out)
end

function V.View.Box:paint_ast()
    return Paint.LovePaint.RectFill(self.x, self.y, self.w, self.h, self.rgba8)
end

function V.View.Box:hit_ast()
    return Hit.Hit.Rect(self.x, self.y, self.w, self.h, self.tag)
end

function V.View.Label:paint_ast()
    return Paint.LovePaint.Text(self.x, self.y, self.font_id, self.rgba8, self.text)
end

function V.View.Label:hit_ast()
    return Hit.Hit.Text(self.x, self.y, self.w, self.h, self.tag)
end

-- ──────────────────────────────────────────────────────────────
-- UI LAYER
-- ──────────────────────────────────────────────────────────────

local U = M.context("view")
    :Define [[
        module UI {
            Root = (Node body) unique

            Node = Column(number spacing, Node* children) unique
                 | Row(number spacing, Node* children) unique
                 | Group(Node* children) unique
                 | Padding(number left, number top, number right, number bottom, Node child) unique
                 | Align(number w, number h, AlignH halign, AlignV valign, Node child) unique
                 | Clip(number w, number h, Node child) unique
                 | Transform(number tx, number ty, Node child) unique
                 | Rect(string tag, number w, number h, number rgba8) unique
                 | Text(string tag, number font_id, number rgba8, string text) unique

            AlignH = Left | Center | Right
            AlignV = Top | Middle | Bottom
        }
    ]]

local fonts = {}
local function text_metrics(font_id, text)
    local font = fonts[font_id] or love.graphics.getFont()
    return font:getWidth(text), font:getHeight()
end

local function append_all(dst, src)
    for i = 1, #src do dst[#dst + 1] = src[i] end
    return dst
end

function U.UI.Root:view()
    return V.View.Root(self.body:place(0, 0))
end

function U.UI.Rect:measure()
    return self.w, self.h
end

function U.UI.Rect:place(x, y)
    return { V.View.Box(self.tag, x, y, self.w, self.h, self.rgba8) }
end

function U.UI.Text:measure()
    return text_metrics(self.font_id, self.text)
end

function U.UI.Text:place(x, y)
    local w, h = self:measure()
    return { V.View.Label(self.tag, x, y, w, h, self.font_id, self.rgba8, self.text) }
end

function U.UI.Padding:measure()
    local cw, ch = self.child:measure()
    return self.left + cw + self.right, self.top + ch + self.bottom
end

function U.UI.Padding:place(x, y)
    return self.child:place(x + self.left, y + self.top)
end

function U.UI.Column:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        if cw > w then w = cw end
        h = h + ch
        if i > 1 then h = h + self.spacing end
    end
    return w, h
end

function U.UI.Column:place(x, y)
    local out = {}
    local cy = y
    for i = 1, #self.children do
        local child = self.children[i]
        local _, ch = child:measure()
        append_all(out, child:place(x, cy))
        cy = cy + ch + self.spacing
    end
    return out
end

function U.UI.Row:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        w = w + cw
        if i > 1 then w = w + self.spacing end
        if ch > h then h = ch end
    end
    return w, h
end

function U.UI.Row:place(x, y)
    local out = {}
    local cx = x
    for i = 1, #self.children do
        local child = self.children[i]
        local cw = child:measure()
        append_all(out, child:place(cx, y))
        cx = cx + cw + self.spacing
    end
    return out
end

function U.UI.Group:measure()
    local w, h = 0, 0
    for i = 1, #self.children do
        local cw, ch = self.children[i]:measure()
        if cw > w then w = cw end
        if ch > h then h = ch end
    end
    return w, h
end

function U.UI.Group:place(x, y)
    local out = {}
    for i = 1, #self.children do
        append_all(out, self.children[i]:place(x, y))
    end
    return out
end

function U.UI.Align:measure()
    return self.w, self.h
end

function U.UI.Align:place(x, y)
    local cw, ch = self.child:measure()
    local cx = x
    if self.halign.kind == "Center" then
        cx = x + math.floor((self.w - cw) / 2)
    elseif self.halign.kind == "Right" then
        cx = x + (self.w - cw)
    end
    local cy = y
    if self.valign.kind == "Middle" then
        cy = y + math.floor((self.h - ch) / 2)
    elseif self.valign.kind == "Bottom" then
        cy = y + (self.h - ch)
    end
    return self.child:place(cx, cy)
end

function U.UI.Clip:measure()
    return self.w, self.h
end

function U.UI.Clip:place(x, y)
    return { V.View.Clip(x, y, self.w, self.h, self.child:place(x, y)) }
end

function U.UI.Transform:measure()
    return self.child:measure()
end

function U.UI.Transform:place(x, y)
    return { V.View.Transform(self.tx, self.ty, self.child:place(x, y)) }
end

-- ──────────────────────────────────────────────────────────────
-- PIPELINES
-- ──────────────────────────────────────────────────────────────

local compile_paint = M.lower("ui_to_paint", function(root)
    local view = root:view()
    return view:paint_ast():draw()
end)

local compile_hit = M.lower("ui_to_hit", function(root)
    local view = root:view()
    return view:hit_ast():probe()
end)

-- ──────────────────────────────────────────────────────────────
-- DEMO STATE / HELPERS
-- ──────────────────────────────────────────────────────────────

local paint_slot
local hit_slot
local gfx
local source

local BUTTON_W = 104
local BUTTON_H = 34
local VIEWPORT_W = 560
local VIEWPORT_H = 92
local TRACK_W = 560
local TRACK_H = 8
local KNOB_W = 18
local KNOB_H = 26
local ROOT_PAD_X = 28
local ROOT_PAD_Y = 24

local TEXT_CHOICES = {
    { key = "1", label = "short",  text = "mgps" },
    { key = "2", label = "medium", text = "mgps keeps keying implicit and structure explicit" },
    { key = "3", label = "long",   text = "mgps classifies authored distinctions into code shape, state shape, and payload, then derives reusable families automatically from the emitted structure" },
}

local function rgba(hex)
    return hex
end

local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

local function selected_choice()
    return TEXT_CHOICES[source.choice]
end

local function selected_text()
    return selected_choice().text
end

local function selected_text_width()
    local w = text_metrics(1, selected_text())
    return w
end

local function max_scroll_px()
    return math.max(0, selected_text_width() + 24 - VIEWPORT_W)
end

local function current_scroll_px()
    return math.floor(source.slider_t * max_scroll_px())
end

local function button(tag, label, selected, hovered)
    local bg = rgba(0xff243246)
    local fg = rgba(0xffd7e3ff)
    if selected then
        bg = rgba(0xff5b7cff)
        fg = rgba(0xffffffff)
    elseif hovered then
        bg = rgba(0xff344763)
        fg = rgba(0xffffffff)
    end

    return U.UI.Group({
        U.UI.Rect(tag, BUTTON_W, BUTTON_H, bg),
        U.UI.Align(BUTTON_W, BUTTON_H, U.UI.Center, U.UI.Middle,
            U.UI.Text(tag .. ":label", 2, fg, label)
        ),
    })
end

local function build_ui()
    local hover = source.hover_tag
    local scroll_px = current_scroll_px()
    local knob_x = math.floor(source.slider_t * (TRACK_W - KNOB_W))

    local button_row = U.UI.Row(10, {
        button("btn:1", "short",  source.choice == 1, hover == "btn:1"),
        button("btn:2", "medium", source.choice == 2, hover == "btn:2"),
        button("btn:3", "long",   source.choice == 3, hover == "btn:3"),
    })

    local viewport = U.UI.Group({
        U.UI.Rect("viewport", VIEWPORT_W, VIEWPORT_H, rgba(0xff141c28)),
        U.UI.Clip(VIEWPORT_W, VIEWPORT_H,
            U.UI.Transform(12 - scroll_px, 0,
                U.UI.Align(VIEWPORT_W, VIEWPORT_H, U.UI.Left, U.UI.Middle,
                    U.UI.Text("preview_text", 1,
                        hover == "preview_text" and rgba(0xffffb3ff) or rgba(0xffffffff),
                        selected_text()
                    )
                )
            )
        ),
    })

    local slider = U.UI.Group({
        U.UI.Transform(0, math.floor((KNOB_H - TRACK_H) / 2),
            U.UI.Rect("slider_track", TRACK_W, TRACK_H,
                hover == "slider_track" and rgba(0xff4f6487) or rgba(0xff324257)
            )
        ),
        U.UI.Transform(knob_x, 0,
            U.UI.Rect("slider_knob", KNOB_W, KNOB_H,
                (source.dragging or hover == "slider_knob") and rgba(0xff8fb3ff) or rgba(0xffd8e7ff)
            )
        ),
    })

    local selected = selected_choice()
    local footer = U.UI.Text("help", 2, rgba(0xffcfd8e6),
        string.format("[%s] short  [%s] medium  [%s] long   •   drag slider   •   hover for hit-test   •   esc quits",
            TEXT_CHOICES[1].key, TEXT_CHOICES[2].key, TEXT_CHOICES[3].key)
    )

    local status = U.UI.Text("status", 2, rgba(0xff8ea4c0),
        string.format("selected=%s  scroll=%d/%d  hover=%s",
            selected.label, scroll_px, max_scroll_px(), tostring(source.hover_tag))
    )

    return U.UI.Root(
        U.UI.Padding(ROOT_PAD_X, ROOT_PAD_Y, ROOT_PAD_X, ROOT_PAD_Y,
            U.UI.Column(18, {
                U.UI.Text("title", 3, rgba(0xfff5fbff), "mgps UI demo"),
                U.UI.Text("subtitle", 2, rgba(0xff9db0c9), "separate paint + hit pipelines, clip + transform, payload-only vs state-shaping updates"),
                button_row,
                viewport,
                slider,
                status,
                footer,
            })
        )
    )
end

local function recompile_all()
    source.root = build_ui()
    paint_slot:update(compile_paint(source.root))
    hit_slot:update(compile_hit(source.root))
end

local function set_slider_from_mouse(mx)
    local track_x = ROOT_PAD_X
    local t = (mx - track_x - KNOB_W * 0.5) / (TRACK_W - KNOB_W)
    source.slider_t = clamp(t, 0, 1)
end

local function update_hover(mx, my)
    local hit = hit_slot.callback({ x = mx, y = my })
    local next_hover = hit and hit.tag or nil
    if next_hover ~= source.hover_tag then
        source.hover_tag = next_hover
        recompile_all()
    end
end

local function apply_click(mx, my)
    local hit = hit_slot.callback({ x = mx, y = my })
    if not hit then return end

    if hit.tag == "btn:1" then
        source.choice = 1
        source.slider_t = 0
        recompile_all()
        return
    elseif hit.tag == "btn:2" then
        source.choice = 2
        source.slider_t = 0
        recompile_all()
        return
    elseif hit.tag == "btn:3" then
        source.choice = 3
        source.slider_t = 0
        recompile_all()
        return
    elseif hit.tag == "slider_track" or hit.tag == "slider_knob" then
        source.dragging = true
        set_slider_from_mouse(mx)
        recompile_all()
        return
    end
end

-- ──────────────────────────────────────────────────────────────
-- LOVE APP
-- ──────────────────────────────────────────────────────────────

function love.load()
    love.graphics.setBackgroundColor(0.07, 0.09, 0.12, 1)
    fonts[1] = love.graphics.newFont(20)
    fonts[2] = love.graphics.newFont(13)
    fonts[3] = love.graphics.newFont(28)
    love.graphics.setFont(fonts[1])

    paint_slot = M.slot()
    hit_slot = M.slot()
    gfx = Paint:new_love_graphics(fonts)

    source = {
        choice = 1,
        hover_tag = nil,
        slider_t = 0,
        dragging = false,
        root = nil,
    }

    recompile_all()
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
        return
    end
    for i = 1, #TEXT_CHOICES do
        if key == TEXT_CHOICES[i].key then
            source.choice = i
            source.slider_t = 0
            recompile_all()
            local mx, my = love.mouse.getPosition()
            update_hover(mx, my)
            return
        end
    end
end

function love.mousepressed(x, y, button_idx)
    if button_idx == 1 then
        apply_click(x, y)
        update_hover(x, y)
    end
end

function love.mousereleased(x, y, button_idx)
    if button_idx == 1 and source.dragging then
        source.dragging = false
        recompile_all()
        update_hover(x, y)
    end
end

function love.mousemoved(x, y)
    if source.dragging then
        set_slider_from_mouse(x)
        recompile_all()
    end
    update_hover(x, y)
end

function love.draw()
    gfx:reset()
    paint_slot.callback(gfx)

    local bound = select(1, paint_slot:peek())
    local report = M.report({ compile_paint, compile_hit })

    love.graphics.setFont(fonts[2])
    love.graphics.setColor(0.86, 0.92, 1.0, 1.0)
    love.graphics.print("paint code_shape: " .. tostring(bound and bound.code_shape or nil), 28, 286)
    love.graphics.print("paint state_shape: " .. tostring(bound and bound.state_shape or nil), 28, 304)
    love.graphics.print(report, 28, 324)
    love.graphics.setColor(1, 1, 1, 1)
end
