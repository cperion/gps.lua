-- examples/ui/lovepaint.lua
--
-- Minimal LovePaint terminal on top of mgps.
-- It compiles a small paint IR into emitted mgps terms whose gens draw into
-- a graphics-like object passed at runtime.

local function next_power_of_two(n)
    local p = 1
    while p < n do p = p * 2 end
    return p
end

return function(M)
    local T = M.context("draw")
        :Define [[
            module LovePaint {
                Frame = (Pass* passes) unique

                Pass = Screen(Node* body) unique

                Node = Group(Node* children) unique
                     | Clip(number x, number y, number w, number h, Node* body) unique
                     | Transform(number tx, number ty, Node* body) unique
                     | RectFill(number x, number y, number w, number h, number rgba8) unique
                     | Text(number x, number y, number font_id, number rgba8, string text) unique
            }
        ]]

    local resource_counter = 0
    local function alloc_text_blob(spec)
        resource_counter = resource_counter + 1
        local text_obj = nil
        if love and love.graphics then
            local font = love.graphics.getFont()
            if font and love.graphics.newText then
                text_obj = love.graphics.newText(font)
            end
        end
        return {
            kind = "TextBlob",
            resource_id = resource_counter,
            spec = spec,
            text_obj = text_obj,
            text_cache = false,
        }
    end

    local function rgba8_to_love(rgba8)
        local a = (rgba8 % 256) / 255
        rgba8 = math.floor(rgba8 / 256)
        local b = (rgba8 % 256) / 255
        rgba8 = math.floor(rgba8 / 256)
        local g = (rgba8 % 256) / 255
        rgba8 = math.floor(rgba8 / 256)
        local r = (rgba8 % 256) / 255
        return r, g, b, a
    end

    local function rect_fill_gen(param, state, g)
        g:fill_rect(param.x, param.y, param.w, param.h, param.rgba8)
        return g
    end

    local function text_gen(param, state, g)
        g:draw_text(state, param.font_id, param.text, param.x, param.y, param.rgba8)
        return g
    end

    function T.LovePaint.Clip:draw()
        local children, child_shapes = {}, {}
        for i = 1, #self.body do
            children[i] = self.body[i]:draw()
            child_shapes[i] = tostring(children[i].code_shape or self.body[i].kind or "child")
        end
        local out = M.compose(children, function(child_gens, param, state, g)
            g:push_clip(param.x, param.y, param.w, param.h)
            for i = 1, #child_gens do
                g = child_gens[i](param[i], state[i], g) or g
            end
            g:pop_clip()
            return g
        end)
        out.param.x = self.x
        out.param.y = self.y
        out.param.w = self.w
        out.param.h = self.h
        out.code_shape = "Clip(" .. table.concat(child_shapes, ",") .. ")"
        return out
    end

    function T.LovePaint.Transform:draw()
        local children, child_shapes = {}, {}
        for i = 1, #self.body do
            children[i] = self.body[i]:draw()
            child_shapes[i] = tostring(children[i].code_shape or self.body[i].kind or "child")
        end
        local out = M.compose(children, function(child_gens, param, state, g)
            g:push_transform(param.tx, param.ty)
            for i = 1, #child_gens do
                g = child_gens[i](param[i], state[i], g) or g
            end
            g:pop_transform()
            return g
        end)
        out.param.tx = self.tx
        out.param.ty = self.ty
        out.code_shape = "Transform(" .. table.concat(child_shapes, ",") .. ")"
        return out
    end

    function T.LovePaint.RectFill:draw()
        return M.emit(
            rect_fill_gen,
            M.state.none(),
            {
                x = self.x,
                y = self.y,
                w = self.w,
                h = self.h,
                rgba8 = self.rgba8,
            }
        )
    end

    function T.LovePaint.Text:draw()
        return M.emit(
            text_gen,
            M.state.resource("TextBlob", {
                cap = next_power_of_two(#self.text),
                font_id = self.font_id,
            }, {
                alloc = alloc_text_blob,
            }),
            {
                x = self.x,
                y = self.y,
                font_id = self.font_id,
                rgba8 = self.rgba8,
                text = self.text,
            }
        )
    end

    local FakeGraphics = {}
    FakeGraphics.__index = FakeGraphics

    function FakeGraphics:new()
        return setmetatable({
            ops = {},
            tx = 0,
            ty = 0,
            transform_stack = {},
            clip_stack = {},
        }, self)
    end

    function FakeGraphics:reset()
        self.ops = {}
        self.tx = 0
        self.ty = 0
        self.transform_stack = {}
        self.clip_stack = {}
    end

    function FakeGraphics:push_transform(tx, ty)
        self.transform_stack[#self.transform_stack + 1] = { self.tx, self.ty }
        self.tx = self.tx + tx
        self.ty = self.ty + ty
        self.ops[#self.ops + 1] = { op = "push_transform", tx = tx, ty = ty, abs_tx = self.tx, abs_ty = self.ty }
    end

    function FakeGraphics:pop_transform()
        local top = self.transform_stack[#self.transform_stack]
        self.transform_stack[#self.transform_stack] = nil
        self.tx, self.ty = top[1], top[2]
        self.ops[#self.ops + 1] = { op = "pop_transform", abs_tx = self.tx, abs_ty = self.ty }
    end

    function FakeGraphics:push_clip(x, y, w, h)
        local ax, ay = x + self.tx, y + self.ty
        self.clip_stack[#self.clip_stack + 1] = { ax, ay, w, h }
        self.ops[#self.ops + 1] = { op = "push_clip", x = ax, y = ay, w = w, h = h }
    end

    function FakeGraphics:pop_clip()
        self.clip_stack[#self.clip_stack] = nil
        self.ops[#self.ops + 1] = { op = "pop_clip" }
    end

    function FakeGraphics:fill_rect(x, y, w, h, rgba8)
        self.ops[#self.ops + 1] = {
            op = "fill_rect",
            x = x + self.tx,
            y = y + self.ty,
            w = w,
            h = h,
            rgba8 = rgba8,
        }
    end

    function FakeGraphics:draw_text(resource, font_id, text, x, y, rgba8)
        self.ops[#self.ops + 1] = {
            op = "draw_text",
            resource_id = resource and resource.resource_id or nil,
            cap = resource and resource.spec and resource.spec.cap or nil,
            font_id = font_id,
            text = text,
            x = x + self.tx,
            y = y + self.ty,
            rgba8 = rgba8,
        }
    end

    function FakeGraphics:dump(label)
        if label then print("\n== " .. label .. " ==") end
        for i = 1, #self.ops do
            local op = self.ops[i]
            if op.op == "fill_rect" then
                print(string.format("fill_rect x=%d y=%d w=%d h=%d rgba=%08x",
                    op.x, op.y, op.w, op.h, op.rgba8))
            elseif op.op == "draw_text" then
                print(string.format("draw_text x=%d y=%d text=%q font=%d resource_id=%s cap=%s rgba=%08x",
                    op.x, op.y, op.text, op.font_id,
                    tostring(op.resource_id), tostring(op.cap), op.rgba8))
            elseif op.op == "push_transform" then
                print(string.format("push_transform tx=%d ty=%d abs_tx=%d abs_ty=%d",
                    op.tx, op.ty, op.abs_tx, op.abs_ty))
            elseif op.op == "pop_transform" then
                print(string.format("pop_transform abs_tx=%d abs_ty=%d", op.abs_tx, op.abs_ty))
            elseif op.op == "push_clip" then
                print(string.format("push_clip x=%d y=%d w=%d h=%d", op.x, op.y, op.w, op.h))
            elseif op.op == "pop_clip" then
                print("pop_clip")
            end
        end
    end

    function T:new_fake_graphics()
        return FakeGraphics:new()
    end

    local LoveGraphics = {}
    LoveGraphics.__index = LoveGraphics

    function LoveGraphics:new(fonts)
        return setmetatable({
            fonts = fonts or {},
            clip_stack = {},
        }, self)
    end

    function LoveGraphics:reset()
        if love and love.graphics then
            love.graphics.origin()
            love.graphics.setScissor()
            love.graphics.setColor(1, 1, 1, 1)
        end
        self.clip_stack = {}
    end

    function LoveGraphics:push_transform(tx, ty)
        love.graphics.push("transform")
        love.graphics.translate(tx, ty)
    end

    function LoveGraphics:pop_transform()
        love.graphics.pop()
    end

    function LoveGraphics:push_clip(x, y, w, h)
        local stack = self.clip_stack
        local nx, ny, nw, nh = x, y, w, h
        local top = stack[#stack]
        if top then
            local x2 = math.max(nx, top[1])
            local y2 = math.max(ny, top[2])
            local r2 = math.min(nx + nw, top[1] + top[3])
            local b2 = math.min(ny + nh, top[2] + top[4])
            nx, ny, nw, nh = x2, y2, math.max(0, r2 - x2), math.max(0, b2 - y2)
        end
        stack[#stack + 1] = { nx, ny, nw, nh }
        love.graphics.setScissor(nx, ny, nw, nh)
    end

    function LoveGraphics:pop_clip()
        local stack = self.clip_stack
        stack[#stack] = nil
        local top = stack[#stack]
        if top then
            love.graphics.setScissor(top[1], top[2], top[3], top[4])
        else
            love.graphics.setScissor()
        end
    end

    function LoveGraphics:fill_rect(x, y, w, h, rgba8)
        love.graphics.setColor(rgba8_to_love(rgba8))
        love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(1, 1, 1, 1)
    end

    function LoveGraphics:draw_text(resource, font_id, text, x, y, rgba8)
        local font = self.fonts[font_id] or love.graphics.getFont()
        if resource.text_obj and font and resource.spec.font_id == font_id then
            if resource.font ~= font then
                resource.font = font
                resource.text_obj = love.graphics.newText(font)
                resource.text_cache = false
            end
            if resource.text_cache ~= text then
                resource.text_obj:set(text)
                resource.text_cache = text
            end
            love.graphics.setColor(rgba8_to_love(rgba8))
            love.graphics.draw(resource.text_obj, x, y)
            love.graphics.setColor(1, 1, 1, 1)
        else
            if font then love.graphics.setFont(font) end
            love.graphics.setColor(rgba8_to_love(rgba8))
            love.graphics.print(text, x, y)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    function T:new_love_graphics(fonts)
        return LoveGraphics:new(fonts)
    end

    return T
end
