local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Core = T.Core
local Layout = T.Layout
local Style = T.Style
local Paint = T.Paint

local M = {}

local function round(n)
	if n >= 0 then
		return math.floor(n + 0.5)
	end
	return math.ceil(n - 0.5)
end

local function resolved_round_rect_radius(box_visual, w, h)
	if box_visual == nil then
		return 0
	end
	if box_visual.shape ~= Layout.ShapeRoundRect then
		return 0
	end
	local max_r = math.max(0, math.min(w, h) * 0.5)
	local r = box_visual.radius or 0
	if r < 0 then
		return 0
	end
	if r > max_r then
		return max_r
	end
	return r
end

local function draw_box_shape_fill(shape, x, y, w, h, radius)
	if w <= 0 or h <= 0 then
		return
	end

	if shape == Layout.ShapeCapsule then
		if w == h then
			love.graphics.circle("fill", x + w * 0.5, y + h * 0.5, w * 0.5)
			return
		end

		if w > h then
			local r = h * 0.5
			if w > h then
				love.graphics.rectangle("fill", x + r, y, w - h, h)
			end
			love.graphics.circle("fill", x + r, y + r, r)
			love.graphics.circle("fill", x + w - r, y + r, r)
			return
		end

		local r = w * 0.5
		if h > w then
			love.graphics.rectangle("fill", x, y + r, w, h - w)
		end
		love.graphics.circle("fill", x + r, y + r, r)
		love.graphics.circle("fill", x + r, y + h - r, r)
		return
	end

	if shape == Layout.ShapeRoundRect then
		love.graphics.rectangle("fill", x, y, w, h, radius, radius)
		return
	end

	love.graphics.rectangle("fill", x, y, w, h)
end

local function inner_shape_radius(shape, radius, inset)
	if shape == Layout.ShapeRoundRect then
		local r = radius - inset
		if r < 0 then
			return 0
		end
		return r
	end
	return 0
end

local function draw_box_border_inside(x, y, w, h, box_visual)
	local border_w = box_visual.border_w or 0
	if border_w <= 0 or box_visual.border_color == 0 then
		return
	end
	border_w = math.max(1, round(border_w))

	local shape = box_visual.shape or Layout.ShapeRect
	local radius = resolved_round_rect_radius(box_visual, w, h)
	love.graphics.setColor(rgba8_to_love(box_visual.border_color, (box_visual.opacity or 100) / 100))

	if border_w * 2 >= w or border_w * 2 >= h then
		draw_box_shape_fill(shape, x, y, w, h, radius)
		return
	end

	local ix = x + border_w
	local iy = y + border_w
	local iw = w - border_w * 2
	local ih = h - border_w * 2
	local inner_radius = inner_shape_radius(shape, radius, border_w)

	love.graphics.stencil(function()
		draw_box_shape_fill(shape, ix, iy, iw, ih, inner_radius)
	end, "replace", 1, false)
	love.graphics.setStencilTest("less", 1)
	draw_box_shape_fill(shape, x, y, w, h, radius)
	love.graphics.setStencilTest()
end

local function rgba8_to_love(rgba8, opacity)
	opacity = opacity or 1
	local a = ((rgba8 % 256) / 255) * opacity
	rgba8 = math.floor(rgba8 / 256)
	local b = (rgba8 % 256) / 255
	rgba8 = math.floor(rgba8 / 256)
	local g = (rgba8 % 256) / 255
	rgba8 = math.floor(rgba8 / 256)
	local r = (rgba8 % 256) / 255
	return r, g, b, a
end

local function cursor_name(cursor)
	if cursor == nil or cursor == Style.CursorDefault then
		return "arrow"
	end
	if cursor == Style.CursorPointer then
		return "hand"
	end
	if cursor == Style.CursorText then
		return "ibeam"
	end
	if cursor == Style.CursorMove then
		return "sizeall"
	end
	if cursor == Style.CursorGrab then
		return "hand"
	end
	if cursor == Style.CursorGrabbing then
		return "hand"
	end
	if cursor == Style.CursorNotAllowed then
		return "no"
	end
	return "arrow"
end

local function cursor_from_string(name)
	if name == nil or name == "default" then
		return "arrow"
	end
	if name == "pointer" then
		return "hand"
	end
	if name == "text" then
		return "ibeam"
	end
	if name == "move" then
		return "sizeall"
	end
	if name == "grab" then
		return "hand"
	end
	if name == "grabbing" then
		return "hand"
	end
	if name == "not-allowed" then
		return "no"
	end
	return "arrow"
end

local function mesh_mode_name(mode)
	if mode == Paint.MeshStrip then
		return "strip"
	end
	if mode == Paint.MeshFan then
		return "fan"
	end
	return "triangles"
end

function M.new(opts)
	if not (love and love.graphics) then
		error("ui.runtime_love.new requires Love2D", 2)
	end

	opts = opts or {}
	local provided_fonts = opts.fonts or {}
	local sized_fonts = {}
	local clip_stack = {}
	local cursor_cache = {}
	local resolve_image = opts.resolve_image
	local images = opts.images
	local quad_cache = setmetatable({}, { __mode = "k" })
	local mesh_cache = setmetatable({}, { __mode = "k" })
	local bezier_cache = setmetatable({}, { __mode = "k" })

	local self = {}

	local function lookup_image(id)
		if id == nil or id == Core.NoId then
			return nil
		end
		if resolve_image then
			local img = resolve_image(id)
			if img ~= nil then
				return img
			end
		end
		return images and images[id.value] or nil
	end

	local function cached_quad(item, image)
		local q = quad_cache[item]
		if q ~= nil then
			return q
		end
		local iw, ih = image:getDimensions()
		q = love.graphics.newQuad(item.src_x, item.src_y, item.src_w, item.src_h, iw, ih)
		quad_cache[item] = q
		return q
	end

	local function cached_mesh(item)
		local m = mesh_cache[item]
		if m ~= nil then
			return m
		end
		local vertices = {}
		for i = 1, #item.vertices do
			local v = item.vertices[i]
			vertices[i] = { v.x, v.y, v.u, v.v, 1, 1, 1, 1 }
		end
		m = love.graphics.newMesh(vertices, mesh_mode_name(item.mode), "static")
		mesh_cache[item] = m
		return m
	end

	local function cached_bezier_points(item)
		local pts = bezier_cache[item]
		if pts ~= nil then
			return pts
		end
		local curve = love.math.newBezierCurve(item.xy)
		local segments = math.max(4, round(item.segments))
		pts = {}
		for i = 0, segments do
			local x, y = curve:evaluate(i / segments)
			pts[#pts + 1] = x
			pts[#pts + 1] = y
		end
		bezier_cache[item] = pts
		return pts
	end

	function self:get_font_fields(font_id, font_size)
		local font = provided_fonts[font_id]
		if font ~= nil then
			return font
		end
		local key = font_size
		font = sized_fonts[key]
		if font == nil then
			font = love.graphics.newFont(key)
			sized_fonts[key] = font
		end
		return font
	end

	function self:draw_box(x, y, w, h, box_visual)
		if box_visual == nil then
			return
		end

		x, y, w, h = round(x), round(y), round(w), round(h)
		local shape = box_visual.shape or Layout.ShapeRect
		local radius = resolved_round_rect_radius(box_visual, w, h)

		if box_visual.bg ~= 0 then
			love.graphics.setColor(rgba8_to_love(box_visual.bg, (box_visual.opacity or 100) / 100))
			draw_box_shape_fill(shape, x, y, w, h, radius)
		end

		if box_visual.border_w > 0 and box_visual.border_color ~= 0 then
			draw_box_border_inside(x, y, w, h, box_visual)
		end

		love.graphics.setColor(1, 1, 1, 1)
	end

	self.draw_rect = self.draw_box

	function self:draw_text(x, y, w, h, layout)
		if layout == nil then
			return
		end
		local style = layout.style

		x, y, w, h = round(x), round(y), round(w), round(h)
		local lines = layout.lines
		local align = style.align

		for i = 1, #lines do
			local line = lines[i]
			local draw_x = x + round(line.x or 0)
			if align == 1 then
				draw_x = draw_x + math.max(0, math.floor((w - round(line.w or 0)) / 2))
			elseif align == 2 then
				draw_x = draw_x + math.max(0, w - round(line.w or 0))
			end
			local draw_y = y + round(line.y or 0)
			local runs = line.runs

			for j = 1, #runs do
				local run = runs[j]
				local font = self:get_font_fields(run.font_id, run.font_size)
				love.graphics.setFont(font)
				love.graphics.setColor(rgba8_to_love(run.fg, 1))
				love.graphics.print(run.text, round(draw_x + (run.x or 0)), round(draw_y + (run.y or 0)))
			end
		end

		love.graphics.setColor(1, 1, 1, 1)
	end

	function self:draw_paint(x, y, w, h, paint)
		if paint == nil then
			return
		end
		local items = paint.items or paint
		love.graphics.push()
		love.graphics.translate(round(x), round(y))

		for i = 1, #items do
			local item = items[i]
			local cls = pvm.classof(item)

			if cls == Paint.Line then
				local stroke = item.stroke
				local old = love.graphics.getLineWidth()
				love.graphics.setLineWidth(math.max(1, round(stroke.width)))
				love.graphics.setColor(rgba8_to_love(stroke.rgba8, 1))
				love.graphics.line(round(item.x1), round(item.y1), round(item.x2), round(item.y2))
				love.graphics.setLineWidth(old)
			elseif cls == Paint.Polyline then
				if #item.xy >= 4 then
					local old = love.graphics.getLineWidth()
					love.graphics.setLineWidth(math.max(1, round(item.stroke.width)))
					love.graphics.setColor(rgba8_to_love(item.stroke.rgba8, 1))
					love.graphics.line(item.xy)
					love.graphics.setLineWidth(old)
				end
			elseif cls == Paint.Polygon then
				if #item.xy >= 6 then
					if item.fill ~= Paint.NoFill then
						love.graphics.setColor(rgba8_to_love(item.fill.rgba8, 1))
						love.graphics.polygon("fill", item.xy)
					end
					if item.stroke ~= nil then
						local old = love.graphics.getLineWidth()
						love.graphics.setLineWidth(math.max(1, round(item.stroke.width)))
						love.graphics.setColor(rgba8_to_love(item.stroke.rgba8, 1))
						love.graphics.polygon("line", item.xy)
						love.graphics.setLineWidth(old)
					end
				end
			elseif cls == Paint.Circle then
				if item.fill ~= Paint.NoFill then
					love.graphics.setColor(rgba8_to_love(item.fill.rgba8, 1))
					love.graphics.circle("fill", round(item.cx), round(item.cy), math.max(0, item.r))
				end
				if item.stroke ~= nil then
					local old = love.graphics.getLineWidth()
					love.graphics.setLineWidth(math.max(1, round(item.stroke.width)))
					love.graphics.setColor(rgba8_to_love(item.stroke.rgba8, 1))
					love.graphics.circle("line", round(item.cx), round(item.cy), math.max(0, item.r))
					love.graphics.setLineWidth(old)
				end
			elseif cls == Paint.Arc then
				local old = love.graphics.getLineWidth()
				love.graphics.setLineWidth(math.max(1, round(item.stroke.width)))
				love.graphics.setColor(rgba8_to_love(item.stroke.rgba8, 1))
				love.graphics.arc(
					"line",
					"open",
					round(item.cx),
					round(item.cy),
					math.max(0, item.r),
					item.a1,
					item.a2,
					math.max(3, round(item.segments))
				)
				love.graphics.setLineWidth(old)
			elseif cls == Paint.Bezier then
				if #item.xy >= 8 then
					local points = cached_bezier_points(item)
					local old = love.graphics.getLineWidth()
					love.graphics.setLineWidth(math.max(1, round(item.stroke.width)))
					love.graphics.setColor(rgba8_to_love(item.stroke.rgba8, 1))
					love.graphics.line(points)
					love.graphics.setLineWidth(old)
				end
			elseif cls == Paint.Mesh then
				local mesh = cached_mesh(item)
				local image = lookup_image(item.image_id)
				if image ~= nil then
					mesh:setTexture(image)
				end
				love.graphics.setColor(rgba8_to_love(item.tint_rgba8, (item.opacity or 100) / 100))
				love.graphics.draw(mesh, 0, 0)
			elseif cls == Paint.Image then
				local image = lookup_image(item.image_id)
				if image ~= nil then
					local quad = cached_quad(item, image)
					local sx = item.src_w ~= 0 and (w / item.src_w) or 1
					local sy = item.src_h ~= 0 and (h / item.src_h) or 1
					love.graphics.setColor(rgba8_to_love(item.tint_rgba8, (item.opacity or 100) / 100))
					love.graphics.draw(image, quad, 0, 0, 0, sx, sy)
				end
			end
		end

		love.graphics.pop()
		love.graphics.setColor(1, 1, 1, 1)
	end

	function self:push_clip_rect(x, y, w, h)
		local sx, sy, sw, sh = love.graphics.getScissor()
		clip_stack[#clip_stack + 1] = { sx, sy, sw, sh }
		love.graphics.setScissor(round(x), round(y), round(w), round(h))
	end

	function self:pop_clip_rect()
		local top = clip_stack[#clip_stack]
		clip_stack[#clip_stack] = nil
		if top and top[1] ~= nil then
			love.graphics.setScissor(top[1], top[2], top[3], top[4])
		else
			love.graphics.setScissor()
		end
	end

	self.push_clip = self.push_clip_rect
	self.pop_clip = self.pop_clip_rect

	function self:set_cursor(name)
		local love_name = cursor_from_string(name)
		local cursor = cursor_cache[love_name]
		if cursor == nil then
			cursor = love.mouse.getSystemCursor(love_name)
			cursor_cache[love_name] = cursor
		end
		if cursor then
			love.mouse.setCursor(cursor)
		end
	end

	function self:set_cursor_kind(cursor)
		local love_name = cursor_name(cursor)
		local c = cursor_cache[love_name]
		if c == nil then
			c = love.mouse.getSystemCursor(love_name)
			cursor_cache[love_name] = c
		end
		if c then
			love.mouse.setCursor(c)
		end
	end

	function self:reset()
		love.graphics.origin()
		love.graphics.setScissor()
		love.graphics.setColor(1, 1, 1, 1)
	end

	return self
end

return M
