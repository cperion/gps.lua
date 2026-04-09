-- examples/ui3/main.lua — Rich authoring ASDL + flex layout
--
-- Architecture (same as ui/, enriched vocabulary):
--
--   User ASDL (UI.*)           ← what the app author writes
--     → layout (measure/place) ← Level ② : constraints down, sizes up
--   View ASDL (View.*)         ← positioned nodes, backend-agnostic
--     → paint_ast / hit_ast    ← projection to backend IR
--   Paint flat cmds            ← lovepaint slot
--   Hit flat cmds              ← hittest slot
--
-- What's new vs ui/:
--   • UiCore vocabulary: Color, Brush, Corners, Shadow, Stroke, Font, TextStyle
--   • Rich leaf types: Box with fill/stroke/corners/shadow, RichText, Image
--   • Flex layout: grow/shrink/basis on Row/Column children
--   • Rounded rects, box shadows in the paint backend
--
-- Layer count (GUIDE.md Ch.38):
--   Dependency cycles: 1 (flex: natural size up → distribute → resolve down)
--   Passes: 2 (measure natural + place with constraint)
--   Total layers: UI ASDL → View flat list → paint/hit flat cmds
--
-- The ui5 proto ASDL had ShapeKey, ArtifactKey, ProgramFamily,
-- BatchFamily, ResidencySlot, UploadPacket, DrawPacket...
-- All of that is gone. The machine underneath is Love2D. We talk to Love2D.

package.path = table.concat({
    "../../?.lua",
    "../../?/init.lua",
    package.path,
}, ";")

local M = require("gps")

-- ══════════════════════════════════════════════════════════════
--  CORE VOCABULARY (from ui5's UiCore, cleaned up)
-- ══════════════════════════════════════════════════════════════
--
-- These are the authoring primitives. They model what the user
-- thinks about: colors, brushes, corners, shadows, strokes, fonts.
-- They do NOT model GL state, buffer slots, or residency.

local CTX = M.context():Define [[
    module UiCore {
        Color = (number r, number g, number b, number a) unique

        Brush = Solid(UiCore.Color color) unique
              | LinearGradient(UiCore.Color from, UiCore.Color to,
                               number angle) unique
              | None

        Corners = (number tl, number tr, number br, number bl) unique

        Shadow = BoxShadow(UiCore.Brush brush, number blur, number spread,
                           number dx, number dy) unique
               | NoShadow

        Stroke = Border(UiCore.Brush brush, number width) unique
               | NoStroke

        Font = (number id, number size) unique

        TextStyle = (UiCore.Font font, UiCore.Color color) unique

        TextWrap = NoWrap | WordWrap | CharWrap
        TextOverflow = Visible | Clip | Ellipsis
        TextAlign = AlignLeft | AlignCenter | AlignRight
        ImageFit = Contain | Cover | Fill | ScaleDown

        Size = Fixed(number value) unique
             | Flex(number basis, number grow, number shrink) unique
             | Auto
    }
]]

-- convenience constructors
local function rgba(r, g, b, a)
    return CTX.UiCore.Color(r, g, b, a or 1)
end

local function hex(c)
    -- 0xRRGGBB or 0xAARRGGBB
    if c > 0xFFFFFF then
        local a = math.floor(c / 0x1000000) % 256
        local r = math.floor(c / 0x10000) % 256
        local g = math.floor(c / 0x100) % 256
        local b = c % 256
        return CTX.UiCore.Color(r/255, g/255, b/255, a/255)
    else
        local r = math.floor(c / 0x10000) % 256
        local g = math.floor(c / 0x100) % 256
        local b = c % 256
        return CTX.UiCore.Color(r/255, g/255, b/255, 1)
    end
end

local function solid(color) return CTX.UiCore.Solid(color) end
local function corners(r)
    if type(r) == "number" then return CTX.UiCore.Corners(r, r, r, r) end
    return CTX.UiCore.Corners(r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 0)
end
local function shadow(color, blur, spread, dx, dy)
    return CTX.UiCore.BoxShadow(solid(color), blur or 4, spread or 0, dx or 0, dy or 2)
end
local function stroke(color, width)
    return CTX.UiCore.Border(solid(color), width or 1)
end

local NoShadow = CTX.UiCore.NoShadow
local NoStroke  = CTX.UiCore.NoStroke
local NoBrush   = CTX.UiCore.None
local ZERO_CORNERS = corners(0)

-- ══════════════════════════════════════════════════════════════
--  VIEW LAYER (positioned scene graph, backend-agnostic)
-- ══════════════════════════════════════════════════════════════

-- View is FLAT: no Node* recursive fields. place() emits these directly.
-- Clip/Transform become push/pop pairs. Group disappears entirely.
CTX:Define [[
    module View {
        Cmd = PushClip(number x, number y, number w, number h) unique
            | PopClip
            | PushTransform(number tx, number ty) unique
            | PopTransform
            | RoundRect(string tag, number x, number y, number w, number h,
                       UiCore.Brush fill, UiCore.Stroke stroke,
                       UiCore.Corners corners, UiCore.Shadow shadow) unique
            | Label(string tag, number x, number y, number w, number h,
                   UiCore.TextStyle style, string text) unique
    }
]]

-- ══════════════════════════════════════════════════════════════
--  USER ASDL (what the app author writes)
-- ══════════════════════════════════════════════════════════════

CTX:Define [[
    module UI {
        Node = Column(number spacing, UI.Node* children) unique
             | Row(number spacing, UI.Node* children) unique
             | Stack(UI.Node* children) unique
             | Padding(number left, number top, number right, number bottom,
                       UI.Node child) unique
             | Align(number w, number h, UI.AlignH halign, UI.AlignV valign,
                     UI.Node child) unique
             | Clip(number w, number h, UI.Node child) unique
             | Transform(number tx, number ty, UI.Node child) unique
             | Box(string tag, number w, number h,
                   UiCore.Brush fill, UiCore.Stroke stroke,
                   UiCore.Corners corners, UiCore.Shadow shadow) unique
             | Text(string tag, UiCore.TextStyle style, string text) unique
             | Spacer(number w, number h) unique
             | FlexItem(UiCore.Size size, UI.Node child) unique
        AlignH = Left | Center | Right
        AlignV = Top | Middle | Bottom
    }
]]

-- ══════════════════════════════════════════════════════════════
--  LAYOUT ENGINE (Level ② : 2-pass, constraints down + sizes up)
-- ══════════════════════════════════════════════════════════════

local fonts = {}
local function text_w(fid, text)
    local f = fonts[fid] or love.graphics.getFont()
    return f:getWidth(text)
end
local function text_h(fid)
    return (fonts[fid] or love.graphics.getFont()):getHeight()
end

-- measure(node) → natural_w, natural_h
-- Returns the "natural" (unconstrained) size of a node.
-- This is pass 1 (bottom-up).

local function measure(n)
    local k = n.kind

    if k == "Box" then return n.w, n.h
    elseif k == "Spacer" then return n.w, n.h
    elseif k == "Text" then
        return text_w(n.style.font.id, n.text), text_h(n.style.font.id)

    elseif k == "Padding" then
        local cw, ch = measure(n.child)
        return n.left + cw + n.right, n.top + ch + n.bottom

    elseif k == "Align" then return n.w, n.h
    elseif k == "Clip" then return n.w, n.h

    elseif k == "Transform" then return measure(n.child)

    elseif k == "FlexItem" then
        local s = n.size
        if s.kind == "Fixed" then return s.value, select(2, measure(n.child))
        elseif s.kind == "Auto" then return measure(n.child)
        else -- Flex
            local _, ch = measure(n.child)
            return s.basis, ch
        end

    elseif k == "Column" then
        local w, h = 0, 0
        for i = 1, #n.children do
            local cw, ch = measure(n.children[i])
            if cw > w then w = cw end
            h = h + ch; if i > 1 then h = h + n.spacing end
        end
        return w, h

    elseif k == "Row" then
        local w, h = 0, 0
        for i = 1, #n.children do
            local cw, ch = measure(n.children[i])
            w = w + cw; if i > 1 then w = w + n.spacing end
            if ch > h then h = ch end
        end
        return w, h

    elseif k == "Stack" then
        local w, h = 0, 0
        for i = 1, #n.children do
            local cw, ch = measure(n.children[i])
            if cw > w then w = cw end
            if ch > h then h = ch end
        end
        return w, h
    end
    return 0, 0
end

-- place(node, x, y, avail_w, avail_h, out) → nil
-- Emits FLAT View.Cmd* into out. No intermediate tree.
-- This is the ONE recursive walk that consumes UI tree structure.
-- After this, everything is flat forever.

local PushClip = CTX.View.PushClip
local PopClip = CTX.View.PopClip()
local PushTransform = CTX.View.PushTransform
local PopTransform = CTX.View.PopTransform()
local RoundRect = CTX.View.RoundRect
local VLabel = CTX.View.Label

local function place(n, x, y, aw, ah, out)
    local k = n.kind

    if k == "Box" then
        out[#out+1] = RoundRect(n.tag, x, y, n.w, n.h,
                                n.fill, n.stroke, n.corners, n.shadow)

    elseif k == "Spacer" then
        -- nothing

    elseif k == "Text" then
        local w = text_w(n.style.font.id, n.text)
        local h = text_h(n.style.font.id)
        out[#out+1] = VLabel(n.tag, x, y, w, h, n.style, n.text)

    elseif k == "Padding" then
        place(n.child, x + n.left, y + n.top,
              (aw or 0) - n.left - n.right,
              (ah or 0) - n.top - n.bottom, out)

    elseif k == "Align" then
        local cw, ch = measure(n.child)
        local cx, cy = x, y
        if n.halign.kind == "Center" then cx = x + math.floor((n.w - cw) / 2)
        elseif n.halign.kind == "Right" then cx = x + (n.w - cw) end
        if n.valign.kind == "Middle" then cy = y + math.floor((n.h - ch) / 2)
        elseif n.valign.kind == "Bottom" then cy = y + (n.h - ch) end
        place(n.child, cx, cy, n.w, n.h, out)

    elseif k == "Clip" then
        out[#out+1] = PushClip(x, y, n.w, n.h)
        place(n.child, x, y, n.w, n.h, out)
        out[#out+1] = PopClip

    elseif k == "Transform" then
        out[#out+1] = PushTransform(n.tx, n.ty)
        place(n.child, x, y, aw, ah, out)
        out[#out+1] = PopTransform

    elseif k == "FlexItem" then
        place(n.child, x, y, aw, ah, out)

    elseif k == "Column" then
        local children = n.children
        local nc = #children
        local total_spacing = (nc > 1) and (nc - 1) * n.spacing or 0
        local avail = (ah or 0) - total_spacing
        local natural_sizes = {}
        local total_natural = 0
        local total_grow = 0
        for i = 1, nc do
            local _, ch = measure(children[i])
            natural_sizes[i] = ch
            total_natural = total_natural + ch
            local c = children[i]
            if c.kind == "FlexItem" and c.size.kind == "Flex" then
                total_grow = total_grow + c.size.grow
            end
        end
        local leftover = math.max(0, avail - total_natural)
        local assigned = {}
        for i = 1, nc do
            local c = children[i]
            local extra = 0
            if total_grow > 0 and c.kind == "FlexItem" and c.size.kind == "Flex" then
                extra = leftover * (c.size.grow / total_grow)
            end
            assigned[i] = natural_sizes[i] + extra
        end
        local cy = y
        for i = 1, nc do
            place(children[i], x, cy, aw, assigned[i], out)
            cy = cy + assigned[i] + n.spacing
        end

    elseif k == "Row" then
        local children = n.children
        local nc = #children
        local total_spacing = (nc > 1) and (nc - 1) * n.spacing or 0
        local avail = (aw or 0) - total_spacing
        local natural_sizes = {}
        local total_natural = 0
        local total_grow = 0
        for i = 1, nc do
            local cw = measure(children[i])
            natural_sizes[i] = cw
            total_natural = total_natural + cw
            local c = children[i]
            if c.kind == "FlexItem" and c.size.kind == "Flex" then
                total_grow = total_grow + c.size.grow
            end
        end
        local leftover = math.max(0, avail - total_natural)
        local assigned = {}
        for i = 1, nc do
            local c = children[i]
            local extra = 0
            if total_grow > 0 and c.kind == "FlexItem" and c.size.kind == "Flex" then
                extra = leftover * (c.size.grow / total_grow)
            end
            assigned[i] = natural_sizes[i] + extra
        end
        local cx = x
        for i = 1, nc do
            place(children[i], cx, y, assigned[i], ah, out)
            cx = cx + assigned[i] + n.spacing
        end

    elseif k == "Stack" then
        for i = 1, #n.children do
            place(n.children[i], x, y, aw, ah, out)
        end
    end
end

-- ══════════════════════════════════════════════════════════════
--  VIEW.Cmd* → PAINT COMMANDS (linear projection, NOT recursive)
-- ══════════════════════════════════════════════════════════════
--
-- View.Cmd* is already flat. This is a LINEAR SCAN, not a tree walk.
-- Each View.Cmd maps to zero or more paint commands.

local function project_paint(view_cmds)
    local out = {}
    for i = 1, #view_cmds do
        local cmd = view_cmds[i]
        local k = cmd.kind

        if k == "PushClip" then
            out[#out+1] = { kind="PushClip", x=cmd.x, y=cmd.y, w=cmd.w, h=cmd.h }
        elseif k == "PopClip" then
            out[#out+1] = { kind="PopClip" }
        elseif k == "PushTransform" then
            out[#out+1] = { kind="PushTransform", tx=cmd.tx, ty=cmd.ty }
        elseif k == "PopTransform" then
            out[#out+1] = { kind="PopTransform" }

        elseif k == "RoundRect" then
            if cmd.shadow.kind == "BoxShadow" then
                local s = cmd.shadow
                out[#out+1] = { kind="Shadow",
                    x=cmd.x+s.dx, y=cmd.y+s.dy,
                    w=cmd.w+s.spread*2, h=cmd.h+s.spread*2,
                    blur=s.blur, brush=s.brush, corners=cmd.corners }
            end
            if cmd.fill.kind ~= "None" then
                out[#out+1] = { kind="RoundRectFill",
                    x=cmd.x, y=cmd.y, w=cmd.w, h=cmd.h,
                    brush=cmd.fill, corners=cmd.corners, tag=cmd.tag }
            end
            if cmd.stroke.kind == "Border" then
                out[#out+1] = { kind="RoundRectStroke",
                    x=cmd.x, y=cmd.y, w=cmd.w, h=cmd.h,
                    brush=cmd.stroke.brush, width=cmd.stroke.width,
                    corners=cmd.corners, tag=cmd.tag }
            end

        elseif k == "Label" then
            out[#out+1] = { kind="Text",
                x=cmd.x, y=cmd.y, font_id=cmd.style.font.id,
                rgba_r=cmd.style.color.r, rgba_g=cmd.style.color.g,
                rgba_b=cmd.style.color.b, rgba_a=cmd.style.color.a,
                text=cmd.text, tag=cmd.tag }
        end
    end
    return out
end

-- ══════════════════════════════════════════════════════════════
--  VIEW.Cmd* → HIT COMMANDS (linear projection, NOT recursive)
-- ══════════════════════════════════════════════════════════════

local function project_hit(view_cmds)
    -- Paint order is back-to-front. The LAST match is the front-most.
    -- We emit in paint order and the hit backend accumulates (no early return).
    -- A final Flush command returns the accumulated result.
    local out = {}
    for i = 1, #view_cmds do
        local cmd = view_cmds[i]
        local k = cmd.kind

        if k == "PushClip" then
            out[#out+1] = { kind="PushClip", x=cmd.x, y=cmd.y, w=cmd.w, h=cmd.h }
        elseif k == "PopClip" then
            out[#out+1] = { kind="PopClip" }
        elseif k == "PushTransform" then
            out[#out+1] = { kind="PushTransform", tx=cmd.tx, ty=cmd.ty }
        elseif k == "PopTransform" then
            out[#out+1] = { kind="PopTransform" }
        elseif k == "RoundRect" then
            if cmd.tag ~= "" then
                out[#out+1] = { kind="Rect", x=cmd.x, y=cmd.y,
                                w=cmd.w, h=cmd.h, tag=cmd.tag }
            end
        elseif k == "Label" then
            if cmd.tag ~= "" then
                out[#out+1] = { kind="Rect", x=cmd.x, y=cmd.y,
                                w=cmd.w, h=cmd.h, tag=cmd.tag }
            end
        end
    end
    out[#out+1] = { kind="Flush" } -- returns accumulated last-hit
    return out
end

-- ══════════════════════════════════════════════════════════════
--  PAINT BACKEND (Love2D)
-- ══════════════════════════════════════════════════════════════

local function brush_to_love(brush)
    if brush.kind == "Solid" then
        return brush.color.r, brush.color.g, brush.color.b, brush.color.a
    elseif brush.kind == "LinearGradient" then
        -- approximation: use midpoint color
        local f, t = brush.from, brush.to
        return (f.r+t.r)/2, (f.g+t.g)/2, (f.b+t.b)/2, (f.a+t.a)/2
    end
    return 0, 0, 0, 0
end

local function has_corners(c)
    return c.tl > 0 or c.tr > 0 or c.br > 0 or c.bl > 0
end

local function love_rounded_rect(mode, x, y, w, h, c)
    if has_corners(c) then
        -- use uniform radius (average) — Love2D only supports uniform
        local r = math.max(1, (c.tl + c.tr + c.br + c.bl) / 4)
        r = math.min(r, w/2, h/2)
        love.graphics.rectangle(mode, x, y, w, h, r, r)
    else
        love.graphics.rectangle(mode, x, y, w, h)
    end
end

local paint_backend = M.backend("ui3.paint", {
    _meta = { arity = 1, stacks = { "transform", "clip" } },

    PushClip = function(cmd, ctx, _, g)
        local tx, ty = 0, 0
        local top = ctx:peek_transform()
        if top then tx, ty = top[1], top[2] end
        local ax, ay = cmd.x + tx, cmd.y + ty
        -- intersect with parent clip
        local pc = ctx:peek_clip()
        if pc then
            local x2 = math.max(ax, pc[1])
            local y2 = math.max(ay, pc[2])
            local r2 = math.min(ax + cmd.w, pc[1] + pc[3])
            local b2 = math.min(ay + cmd.h, pc[2] + pc[4])
            ax, ay = x2, y2
            cmd_w = math.max(0, r2 - x2)
            cmd_h = math.max(0, b2 - y2)
            ctx:push_clip({ ax, ay, cmd_w, cmd_h })
            love.graphics.setScissor(ax, ay, cmd_w, cmd_h)
        else
            ctx:push_clip({ ax, ay, cmd.w, cmd.h })
            love.graphics.setScissor(ax, ay, cmd.w, cmd.h)
        end
    end,

    PopClip = function(cmd, ctx)
        ctx:pop_clip()
        local top = ctx:peek_clip()
        if top then love.graphics.setScissor(top[1], top[2], top[3], top[4])
        else love.graphics.setScissor() end
    end,

    PushTransform = function(cmd, ctx)
        local tx, ty = 0, 0
        local top = ctx:peek_transform()
        if top then tx, ty = top[1], top[2] end
        ctx:push_transform({ tx + cmd.tx, ty + cmd.ty })
        love.graphics.push("transform")
        love.graphics.translate(cmd.tx, cmd.ty)
    end,

    PopTransform = function(cmd, ctx)
        ctx:pop_transform()
        love.graphics.pop()
    end,

    Shadow = function(cmd, ctx)
        -- simple shadow: draw a slightly larger, blurred rect behind
        -- Love2D doesn't have native blur, so we approximate with alpha layers
        local r, g, b, a = brush_to_love(cmd.brush)
        local blur = cmd.blur
        local steps = math.min(blur, 6)
        for i = steps, 1, -1 do
            local f = i / steps
            local expand = blur * f
            love.graphics.setColor(r, g, b, a * (1 - f) * 0.15)
            love_rounded_rect("fill",
                cmd.x - expand, cmd.y - expand,
                cmd.w + expand*2, cmd.h + expand*2,
                cmd.corners)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end,

    RoundRectFill = function(cmd, ctx)
        local r, g, b, a = brush_to_love(cmd.brush)
        love.graphics.setColor(r, g, b, a)
        love_rounded_rect("fill", cmd.x, cmd.y, cmd.w, cmd.h, cmd.corners)
        love.graphics.setColor(1, 1, 1, 1)
    end,

    RoundRectStroke = function(cmd, ctx)
        local r, g, b, a = brush_to_love(cmd.brush)
        love.graphics.setColor(r, g, b, a)
        love.graphics.setLineWidth(cmd.width)
        love_rounded_rect("line", cmd.x, cmd.y, cmd.w, cmd.h, cmd.corners)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
    end,

    Text = function(cmd, ctx, _, g)
        local font = fonts[cmd.font_id] or love.graphics.getFont()
        love.graphics.setFont(font)
        love.graphics.setColor(cmd.rgba_r, cmd.rgba_g, cmd.rgba_b, cmd.rgba_a)
        love.graphics.print(cmd.text, cmd.x, cmd.y)
        love.graphics.setColor(1, 1, 1, 1)
    end,
})

-- ══════════════════════════════════════════════════════════════
--  HIT BACKEND (same as ui/, unchanged)
-- ══════════════════════════════════════════════════════════════

local function inside(px, py, x, y, w, h)
    return px >= x and py >= y and px < x + w and py < y + h
end

local hit_backend = M.backend("ui3.hit", {
    _meta = { arity = 1, stacks = { "transform", "clip", "result" } },
    PushTransform = function(cmd, ctx)
        local tx, ty = 0, 0
        local top = ctx:peek_transform()
        if top then tx, ty = top[1], top[2] end
        ctx:push_transform({ tx + cmd.tx, ty + cmd.ty })
    end,
    PopTransform = function(cmd, ctx) ctx:pop_transform() end,
    PushClip = function(cmd, ctx)
        local tx, ty = 0, 0
        local top = ctx:peek_transform()
        if top then tx, ty = top[1], top[2] end
        ctx:push_clip({ cmd.x + tx, cmd.y + ty, cmd.w, cmd.h })
    end,
    PopClip = function(cmd, ctx) ctx:pop_clip() end,
    Rect = function(cmd, ctx, _, query)
        local tx, ty = 0, 0
        local top = ctx:peek_transform()
        if top then tx, ty = top[1], top[2] end
        local x, y = cmd.x + tx, cmd.y + ty
        local clip = ctx:peek_clip()
        if clip and not inside(query.x, query.y, clip[1], clip[2], clip[3], clip[4]) then
            return nil
        end
        if inside(query.x, query.y, x, y, cmd.w, cmd.h) then
            -- accumulate: last match = front-most (paint order is back-to-front)
            ctx._last_hit = { tag = cmd.tag, x = x, y = y, w = cmd.w, h = cmd.h }
        end
        return nil -- never return early
    end,
    Flush = function(cmd, ctx, _, query)
        local result = ctx._last_hit
        ctx._last_hit = nil
        return result
    end,
})

-- ══════════════════════════════════════════════════════════════
--  COMPILE PIPELINE
-- ══════════════════════════════════════════════════════════════

local paint_slot = M.slot(paint_backend)
local hit_slot   = M.slot(hit_backend)

local function compile(ui_root, win_w, win_h)
    -- ONE recursive walk: UI tree → flat View.Cmd*
    local view_cmds = {}
    place(ui_root, 0, 0, win_w, win_h, view_cmds)

    -- TWO linear projections: View.Cmd* → paint cmds, hit cmds
    paint_slot:update(project_paint(view_cmds))
    hit_slot:update(project_hit(view_cmds))
end

-- ══════════════════════════════════════════════════════════════
--  PALETTE (same dark theme, using UiCore.Color)
-- ══════════════════════════════════════════════════════════════

local C = {
    bg          = hex(0xff0e1117),
    panel       = hex(0xff161b22),
    panel_hi    = hex(0xff1c2330),
    border      = hex(0xff30363d),
    border_hi   = hex(0xff58a6ff),
    text        = hex(0xffe6edf3),
    text_dim    = hex(0xff8b949e),
    text_bright = hex(0xffffffff),
    accent      = hex(0xff58a6ff),
    accent_dim  = hex(0xff1f6feb),
    green       = hex(0xff3fb950),
    red         = hex(0xfff85149),
    orange      = hex(0xffd29922),
    purple      = hex(0xffbc8cff),
    cyan        = hex(0xff79c0ff),
    mute_on     = hex(0xffda3633),
    solo_on     = hex(0xff58a6ff),
    meter_bg    = hex(0xff21262d),
    meter_fill  = hex(0xff3fb950),
    meter_hot   = hex(0xffd29922),
    meter_clip  = hex(0xfff85149),
    knob_bg     = hex(0xff30363d),
    knob_fg     = hex(0xff58a6ff),
    transport_bg = hex(0xff0d1117),
    scrollbar   = hex(0xff30363d),
    scrollthumb = hex(0xff484f58),
    row_even    = hex(0xff0d1117),
    row_odd     = hex(0xff161b22),
    row_hover   = hex(0xff1c2330),
    row_active  = hex(0xff1f2937),
}

-- ══════════════════════════════════════════════════════════════
--  SHORTHAND CONSTRUCTORS
-- ══════════════════════════════════════════════════════════════

local Col, Row, Stk, Pad, Ali, Clp, Tfm, Spc =
    CTX.UI.Column, CTX.UI.Row, CTX.UI.Stack, CTX.UI.Padding, CTX.UI.Align,
    CTX.UI.Clip, CTX.UI.Transform, CTX.UI.Spacer
local Lft, Cen, Rgt = CTX.UI.Left(), CTX.UI.Center(), CTX.UI.Right()
local Top, Mid, Bot = CTX.UI.Top(), CTX.UI.Middle(), CTX.UI.Bottom()
local Flx = CTX.UI.FlexItem
local FixedSz = CTX.UiCore.Fixed()
local FlexSz = CTX.UiCore.Flex()
local AutoSz = CTX.UiCore.Auto()

-- Box with defaults
local function Box(tag, w, h, fill, opts)
    opts = opts or {}
    return CTX.UI.Box(tag, w, h,
        fill and solid(fill) or NoBrush,
        opts.stroke or NoStroke,
        opts.corners or ZERO_CORNERS,
        opts.shadow or NoShadow)
end

-- Text with font+color
local function Txt(tag, fid, color, text)
    return CTX.UI.Text(tag, CTX.UiCore.TextStyle(
        CTX.UiCore.Font(fid, 0), color), text)
end

-- Button (box + centered label)
local function Btn(tag, w, h, bg, fg, fid, label, hovered)
    local real_bg = hovered and C.panel_hi or bg
    return Stk({
        Box(tag, w, h, real_bg, { corners = corners(3) }),
        Ali(w, h, Cen, Mid, Txt(tag..":l", fid, fg, label)),
    })
end

-- ══════════════════════════════════════════════════════════════
--  APPLICATION STATE
-- ══════════════════════════════════════════════════════════════

local TRACK_NAMES = {
    "Kick", "Snare", "Hi-Hat", "Bass", "Lead Synth",
    "Pad", "FX Rise", "Vocal Chop", "Perc", "Sub Bass",
    "Strings", "Piano",
}
local TRACK_COLORS = {
    C.green, C.red, C.orange, C.purple, C.cyan,
    C.accent, C.orange, C.green, C.red, C.purple,
    C.cyan, C.accent,
}

local ROW_H, HEADER_H, TRACK_W, METER_W = 48, 40, 220, 6
local TRANSPORT_H, INSP_W = 52, 280

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

local S -- state

local function make_state()
    local tracks = {}
    for i = 1, #TRACK_NAMES do
        tracks[i] = {
            name=TRACK_NAMES[i], color=TRACK_COLORS[i],
            vol=0.75, pan=0.5, mute=false, solo=false, meter=0,
        }
    end
    return {
        tracks=tracks, selected=1, hover_tag=nil, scroll_y=0,
        bpm=120, playing=false, beat=0, time_sec=0,
        dragging=nil, win_w=1200, win_h=750,
    }
end

-- ══════════════════════════════════════════════════════════════
--  WIDGETS (same track editor, using rich ASDL)
-- ══════════════════════════════════════════════════════════════

local function meter_bar(tag, w, h, level)
    local fill = math.floor(w * clamp(level, 0, 1))
    local col = level > 0.9 and C.meter_clip or (level > 0.7 and C.meter_hot or C.meter_fill)
    return Stk({
        Box(tag, w, h, C.meter_bg),
        Box(tag..":f", fill, h, col),
    })
end

local function vol_widget(tag, w, h, vol, hovered)
    local fill = math.floor(w * clamp(vol, 0, 1))
    return Stk({
        Box(tag, w, h, hovered and C.panel_hi or C.knob_bg, {corners=corners(2)}),
        Box(tag..":v", fill, h, C.knob_fg, {corners=corners(2)}),
    })
end

local function pan_widget(tag, w, h, pan_val, hovered)
    local center = math.floor(w / 2)
    local pos = math.floor(pan_val * w)
    local left = math.min(center, pos)
    local bar_w = math.max(2, math.abs(pos - center))
    return Stk({
        Box(tag, w, h, hovered and C.panel_hi or C.knob_bg, {corners=corners(2)}),
        Tfm(left, 0, Box(tag..":v", bar_w, h, C.knob_fg)),
    })
end

local function track_row(i, t, selected, hover)
    local tag = "track:"..i
    local htag = hover or ""
    local is_hovered = htag == tag or htag:sub(1, #tag+1) == tag..":"
    local bg = (i == selected) and C.row_active
             or is_hovered and C.row_hover
             or (i % 2 == 0) and C.row_even or C.row_odd
    local name_fg = (i == selected) and C.text_bright or C.text

    return Stk({
        Box(tag, TRACK_W, ROW_H, bg),
        Row(0, {
            Box(tag..":pip", 4, ROW_H, t.color),
            Pad(8,0,0,0, Ali(120, ROW_H, Lft, Mid,
                Txt(tag..":name", 2, name_fg, t.name))),
            Pad(0,14,4,14, Row(4, {
                Btn(tag..":mute", 24, 20,
                    t.mute and C.mute_on or C.panel,
                    t.mute and C.text_bright or C.text_dim, 4, "M",
                    htag == tag..":mute"),
                Btn(tag..":solo", 24, 20,
                    t.solo and C.solo_on or C.panel,
                    t.solo and C.text_bright or C.text_dim, 4, "S",
                    htag == tag..":solo"),
            })),
            Pad(0,19,0,19, vol_widget(tag..":vol", 60, 10, t.vol,
                htag == tag..":vol" or htag == tag..":vol:v")),
            Pad(4,19,4,19, pan_widget(tag..":pan", 40, 10, t.pan,
                htag == tag..":pan" or htag == tag..":pan:v")),
            Pad(2,4,4,4, meter_bar(tag..":meter", METER_W, ROW_H-8, t.meter)),
        }),
    })
end

local function transport_bar(s)
    local htag = s.hover_tag or ""
    local play_label = s.playing and "||" or ">"
    local min = math.floor(s.time_sec / 60)
    local sec = math.floor(s.time_sec) % 60
    local ms  = math.floor((s.time_sec * 1000) % 1000)
    local time_str = string.format("%02d:%02d.%03d", min, sec, ms)
    local beat_str = string.format("%.1f", s.beat + 1)

    return Stk({
        Box("transport", s.win_w, TRANSPORT_H, C.transport_bg),
        Box("transport:border", s.win_w, 1, C.border),
        Pad(16,0,16,0, Row(16, {
            Ali(80, TRANSPORT_H, Cen, Mid,
                Btn("transport:play", 48, 30,
                    s.playing and C.accent_dim or C.panel,
                    C.text_bright, 3, play_label, htag=="transport:play")),
            Ali(60, TRANSPORT_H, Cen, Mid,
                Btn("transport:stop", 48, 30, C.panel, C.text, 3, "[]",
                    htag=="transport:stop")),
            Box("transport:sep1", 1, TRANSPORT_H-16, C.border),
            Ali(100, TRANSPORT_H, Cen, Mid, Col(2, {
                Txt("transport:time_l", 4, C.text_dim, "TIME"),
                Txt("transport:time", 3, C.text_bright, time_str),
            })),
            Ali(60, TRANSPORT_H, Cen, Mid, Col(2, {
                Txt("transport:beat_l", 4, C.text_dim, "BEAT"),
                Txt("transport:beat", 3, C.text_bright, beat_str),
            })),
            Box("transport:sep2", 1, TRANSPORT_H-16, C.border),
            Ali(80, TRANSPORT_H, Cen, Mid, Col(2, {
                Txt("transport:bpm_l", 4, C.text_dim, "BPM"),
                Row(4, {
                    Btn("transport:bpm-", 22, 20, C.panel, C.text, 4, "-",
                        htag=="transport:bpm-"),
                    Txt("transport:bpm", 3, C.accent, tostring(s.bpm)),
                    Btn("transport:bpm+", 22, 20, C.panel, C.text, 4, "+",
                        htag=="transport:bpm+"),
                }),
            })),
            Spc(20, 1),
            Ali(200, TRANSPORT_H, Lft, Mid,
                Txt("transport:status", 4, C.text_dim,
                    s.playing and "RECORDING" or "STOPPED")),
        })),
    })
end

local function inspector_panel(s)
    local t = s.tracks[s.selected]
    local htag = s.hover_tag or ""
    local function kv(key, val, tag)
        return Row(0, {
            Ali(90, 22, Lft, Mid, Txt(tag..":k", 4, C.text_dim, key)),
            Ali(160, 22, Lft, Mid, Txt(tag..":v", 2, C.text, val)),
        })
    end
    return Stk({
        Box("insp", INSP_W, s.win_h - TRANSPORT_H, C.panel),
        Box("insp:border", 1, s.win_h - TRANSPORT_H, C.border),
        Pad(16,16,16,16, Col(10, {
            Txt("insp:title", 3, C.text_bright, "Inspector"),
            Box("insp:sep", INSP_W-32, 1, C.border),
            Col(4, {
                kv("Track", t.name, "insp:name"),
                kv("Index", tostring(s.selected), "insp:idx"),
                kv("Volume", string.format("%.0f%%", t.vol*100), "insp:vol"),
                kv("Pan", string.format("%.0f%%", (t.pan-0.5)*200), "insp:pan"),
                kv("Mute", t.mute and "ON" or "off", "insp:mute"),
                kv("Solo", t.solo and "ON" or "off", "insp:solo"),
            }),
            Box("insp:sep2", INSP_W-32, 1, C.border),
            Txt("insp:vol_label", 4, C.text_dim, "Volume"),
            vol_widget("insp:vol_slider", INSP_W-32, 14, t.vol,
                       htag:match("^insp:vol_slider")),
            Txt("insp:pan_label", 4, C.text_dim, "Pan"),
            pan_widget("insp:pan_slider", INSP_W-32, 14, t.pan,
                       htag:match("^insp:pan_slider")),
            Box("insp:sep3", INSP_W-32, 1, C.border),
            Row(8, {
                Btn("insp:mute_btn", 70, 28,
                    t.mute and C.mute_on or C.panel,
                    t.mute and C.text_bright or C.text, 2,
                    t.mute and "MUTED" or "Mute", htag=="insp:mute_btn"),
                Btn("insp:solo_btn", 70, 28,
                    t.solo and C.solo_on or C.panel,
                    t.solo and C.text_bright or C.text, 2,
                    t.solo and "SOLO'D" or "Solo", htag=="insp:solo_btn"),
            }),
        })),
    })
end

local function vscrollbar(tag, total_h, view_h, scroll_y, bar_h, hover)
    if total_h <= view_h then return Spc(0, 0) end
    local ratio = view_h / total_h
    local thumb_h = math.max(20, math.floor(bar_h * ratio))
    local max_scroll = total_h - view_h
    local thumb_y = math.floor((scroll_y / max_scroll) * (bar_h - thumb_h))
    return Stk({
        Box(tag, 8, bar_h, C.scrollbar),
        Tfm(0, thumb_y, Box(tag..":thumb", 8, thumb_h,
            (hover and hover:match("^"..tag)) and C.accent or C.scrollthumb,
            { corners = corners(4) })),
    })
end

local function build_ui(s)
    local list_h = #s.tracks * ROW_H
    local view_h = s.win_h - TRANSPORT_H - HEADER_H
    local scroll = clamp(s.scroll_y, 0, math.max(0, list_h - view_h))

    -- track list
    local track_rows = {}
    for i = 1, #s.tracks do
        track_rows[i] = Tfm(0, (i-1)*ROW_H,
            track_row(i, s.tracks[i], s.selected, s.hover_tag))
    end

    -- header
    local header = Stk({
        Box("header", TRACK_W+8, HEADER_H, C.panel),
        Box("header:border", TRACK_W+8, 1, C.border),
        Pad(14,0,0,0, Ali(TRACK_W, HEADER_H, Lft, Mid,
            Row(12, {
                Txt("header:title", 3, C.text_bright, "Tracks"),
                Txt("header:count", 4, C.text_dim,
                    string.format("(%d)", #s.tracks)),
            })
        )),
    })

    -- left panel
    local left = Col(0, {
        header,
        Stk({
            Box("tracklist_bg", TRACK_W+8, view_h, C.bg),
            Clp(TRACK_W, view_h, Tfm(0, -scroll, Stk(track_rows))),
            Tfm(TRACK_W, 0,
                vscrollbar("scroll", list_h, view_h, scroll, view_h, s.hover_tag)),
        }),
    })

    -- arrangement area
    local arr_w = s.win_w - TRACK_W - 8 - INSP_W
    local arr_h = s.win_h - TRANSPORT_H
    local px_per_beat = 60
    local visible_beats = math.ceil(arr_w / px_per_beat) + 1

    local grid = {}
    for b = 0, visible_beats do
        grid[#grid+1] = Tfm(b * px_per_beat, 0,
            Box("grid:"..b, 1, arr_h - HEADER_H,
                (b % 4 == 0) and C.border or C.panel))
    end

    local lanes = {}
    for i = 1, #s.tracks do
        local t = s.tracks[i]
        local clip_x = ((i * 37) % 8) * px_per_beat
        local clip_w = (2 + (i % 3)) * px_per_beat
        lanes[#lanes+1] = Tfm(clip_x, (i-1)*ROW_H - scroll + 4, Stk({
            Box("clip:"..i, clip_w, ROW_H-8, t.color, {corners=corners(4)}),
            Pad(6,2,0,0, Txt("clip:"..i..":name", 4, C.text_bright, t.name)),
        }))
    end

    local playhead_x = math.floor(s.beat * px_per_beat)

    local ruler = {}
    for b = 0, visible_beats do
        local bx = b * px_per_beat
        if b % 4 == 0 then
            ruler[#ruler+1] = Tfm(bx+4, 0,
                Txt("ruler:"..b, 4, C.text_dim, tostring(math.floor(b/4)+1)))
        end
        ruler[#ruler+1] = Tfm(bx, 0,
            Box("ruler:tick:"..b, 1, (b%4==0) and HEADER_H or 10, C.border))
    end

    local arrangement = Stk({
        Box("arr_bg", arr_w, arr_h, C.bg),
        Stk({
            Box("ruler_bg", arr_w, HEADER_H, C.panel),
            Clp(arr_w, HEADER_H, Stk(ruler)),
        }),
        Tfm(0, HEADER_H, Clp(arr_w, arr_h-HEADER_H, Stk(lanes))),
        Tfm(0, HEADER_H, Clp(arr_w, arr_h-HEADER_H, Stk(grid))),
        Tfm(playhead_x, 0, Box("playhead", 2, arr_h, C.text_bright)),
    })

    return Col(0, {
        Row(0, { left, arrangement, inspector_panel(s) }),
        transport_bar(s),
    })
end

-- ══════════════════════════════════════════════════════════════
--  RECOMPILE + INPUT
-- ══════════════════════════════════════════════════════════════

local function recompile()
    compile(build_ui(S), S.win_w, S.win_h)
end

local function update_hover(mx, my)
    local hit = hit_slot:run({ x = mx, y = my })
    local next_tag = hit and hit.tag or nil
    if next_tag ~= S.hover_tag then
        S.hover_tag = next_tag
        recompile()
    end
end

local function track_from_tag(tag)
    return tonumber(tag:match("^track:(%d+)"))
end

-- ══════════════════════════════════════════════════════════════
--  LOVE CALLBACKS
-- ══════════════════════════════════════════════════════════════

function love.load()
    love.graphics.setBackgroundColor(0.054, 0.067, 0.090, 1)
    fonts[1] = love.graphics.newFont(18)
    fonts[2] = love.graphics.newFont(13)
    fonts[3] = love.graphics.newFont(15)
    fonts[4] = love.graphics.newFont(10)
    love.graphics.setFont(fonts[2])

    S = make_state()
    S.win_w, S.win_h = love.graphics.getDimensions()
    recompile()
end

function love.resize(w, h)
    S.win_w, S.win_h = w, h; recompile()
end

function love.update(dt)
    local changed = false
    for i = 1, #S.tracks do
        local t = S.tracks[i]
        local target = 0
        if S.playing and not t.mute then
            target = 0.3 + 0.5 * math.abs(math.sin(S.time_sec * (1.5 + i * 0.3) + i * 0.7))
            target = target * t.vol
        end
        local old = t.meter
        t.meter = t.meter + (target - t.meter) * math.min(1, dt * 12)
        if math.abs(t.meter - old) > 0.002 then changed = true end
    end
    if S.playing then
        S.time_sec = S.time_sec + dt
        S.beat = S.time_sec * S.bpm / 60
        changed = true
    end
    if changed then recompile() end
end

function love.keypressed(key)
    if key == "escape" then love.event.quit(); return end
    if key == "space" then
        S.playing = not S.playing
        if not S.playing then for i = 1, #S.tracks do S.tracks[i].meter = 0 end end
        recompile(); return
    end
    if key == "up" then S.selected = math.max(1, S.selected-1); recompile() end
    if key == "down" then S.selected = math.min(#S.tracks, S.selected+1); recompile() end
    if key == "m" then S.tracks[S.selected].mute = not S.tracks[S.selected].mute; recompile() end
    if key == "s" then S.tracks[S.selected].solo = not S.tracks[S.selected].solo; recompile() end
    if key == "r" then
        S.time_sec=0; S.beat=0; S.playing=false
        for i = 1, #S.tracks do S.tracks[i].meter = 0 end; recompile()
    end
end

function love.mousepressed(mx, my, btn_idx)
    if btn_idx ~= 1 then return end
    local hit = hit_slot:run({ x = mx, y = my })
    if not hit then return end
    local tag = hit.tag
    local ti = track_from_tag(tag)
    if ti then
        S.selected = ti
        if tag:match(":mute") then S.tracks[ti].mute = not S.tracks[ti].mute
        elseif tag:match(":solo") then S.tracks[ti].solo = not S.tracks[ti].solo
        elseif tag:match(":vol") then
            S.dragging = { tag="track:"..ti..":vol", idx=ti, field="vol",
                           x0=mx, val0=S.tracks[ti].vol, w=60 }
        elseif tag:match(":pan") then
            S.dragging = { tag="track:"..ti..":pan", idx=ti, field="pan",
                           x0=mx, val0=S.tracks[ti].pan, w=40 }
        end
        recompile(); return
    end
    if tag:match("^insp:vol_slider") then
        S.dragging = { tag="insp:vol_slider", idx=S.selected, field="vol",
                       x0=mx, val0=S.tracks[S.selected].vol, w=INSP_W-32 }
        recompile(); return
    end
    if tag:match("^insp:pan_slider") then
        S.dragging = { tag="insp:pan_slider", idx=S.selected, field="pan",
                       x0=mx, val0=S.tracks[S.selected].pan, w=INSP_W-32 }
        recompile(); return
    end
    if tag:match("^insp:mute_btn") then
        S.tracks[S.selected].mute = not S.tracks[S.selected].mute; recompile(); return end
    if tag:match("^insp:solo_btn") then
        S.tracks[S.selected].solo = not S.tracks[S.selected].solo; recompile(); return end
    if tag == "transport:play" then
        S.playing = not S.playing
        if not S.playing then for i = 1, #S.tracks do S.tracks[i].meter = 0 end end
        recompile(); return
    end
    if tag == "transport:stop" then
        S.playing=false; S.time_sec=0; S.beat=0
        for i = 1, #S.tracks do S.tracks[i].meter = 0 end; recompile(); return
    end
    if tag == "transport:bpm-" then S.bpm = math.max(40, S.bpm-5); recompile() end
    if tag == "transport:bpm+" then S.bpm = math.min(300, S.bpm+5); recompile() end
end

function love.mousereleased()
    if S.dragging then S.dragging = nil; recompile() end
end

function love.mousemoved(mx, my)
    if S.dragging then
        local d = S.dragging
        local delta = (mx - d.x0) / d.w
        S.tracks[d.idx][d.field] = clamp(d.val0 + delta, 0, 1)
        recompile()
    end
    update_hover(mx, my)
end

function love.wheelmoved(_, wy)
    local list_h = #S.tracks * ROW_H
    local view_h = S.win_h - TRANSPORT_H - HEADER_H
    S.scroll_y = clamp(S.scroll_y - wy * 30, 0, math.max(0, list_h - view_h))
    recompile()
    update_hover(love.mouse.getPosition())
end

function love.draw()
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
    paint_slot:run(nil)
end
