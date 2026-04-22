local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Core = T.Core
local Paint = T.Paint

local M = {}

local function classof(v)
    return pvm.classof(v)
end

local function is_id(v)
    local cls = classof(v)
    return cls and Core.Id.members[cls] or false
end

local function is_program(v)
    local cls = classof(v)
    return cls and Paint.Program.members[cls] or false
end

local function is_program_list(v)
    return classof(v) == Paint.ProgramList
end

local function is_vertex(v)
    return classof(v) == Paint.Vertex
end

local function plain_array_last(items)
    local max = 0
    for k in pairs(items) do
        if type(k) == "number" and k >= 1 and k == math.floor(k) and k > max then
            max = k
        end
    end
    return max
end

local function expect_plain_array(items, level)
    if type(items) ~= "table" or classof(items) then
        error("paint list expects one plain Lua array table", level or 3)
    end
    return items
end

local function collect_vertices(items, level)
    items = expect_plain_array(items, level)
    local out = {}
    local n = plain_array_last(items)
    for i = 1, n do
        local v = items[i]
        if is_vertex(v) then
            out[#out + 1] = v
        elseif v ~= nil and v ~= false then
            error("paint mesh vertices accept only Paint.Vertex, nil, or false", (level or 2) + 1)
        end
    end
    return out
end

function M.stroke(rgba8, width)
    return Paint.Stroke(rgba8, width)
end

function M.fill(rgba8)
    return Paint.SolidFill(rgba8)
end

function M.vertex(x, y, u, v)
    return Paint.Vertex(x, y, u or 0, v or 0)
end

M.no_fill = Paint.NoFill
M.mesh_triangles = Paint.MeshTriangles
M.mesh_strip = Paint.MeshStrip
M.mesh_fan = Paint.MeshFan

function M.line(x1, y1, x2, y2, stroke)
    return Paint.Line(x1, y1, x2, y2, stroke)
end

function M.polyline(xy, stroke)
    return Paint.Polyline(expect_plain_array(xy, 2), stroke)
end

function M.polygon(xy, fill, stroke)
    return Paint.Polygon(expect_plain_array(xy, 2), fill or Paint.NoFill, stroke)
end

function M.circle(cx, cy, r, fill, stroke)
    return Paint.Circle(cx, cy, r, fill or Paint.NoFill, stroke)
end

function M.arc(cx, cy, r, a1, a2, segments, stroke)
    return Paint.Arc(cx, cy, r, a1, a2, segments or 24, stroke)
end

function M.bezier(xy, segments, stroke)
    return Paint.Bezier(expect_plain_array(xy, 2), segments or 24, stroke)
end

function M.mesh(mode, vertices, image_id, tint_rgba8, opacity)
    if image_id ~= nil and image_id ~= false and image_id ~= Core.NoId and not is_id(image_id) then
        error("paint.mesh image_id must be a ui id, nil, false, or NoId", 2)
    end
    return Paint.Mesh(
        mode or Paint.MeshTriangles,
        collect_vertices(vertices, 2),
        (image_id == false) and nil or image_id,
        tint_rgba8 or 0xffffffff,
        opacity or 100
    )
end

function M.image(image_id, src_x, src_y, src_w, src_h, tint_rgba8, opacity)
    if not is_id(image_id) then
        error("paint.image expects a ui id as first argument", 2)
    end
    return Paint.Image(image_id, src_x, src_y, src_w, src_h, tint_rgba8 or 0xffffffff, opacity or 100)
end

function M.list(items)
    items = expect_plain_array(items, 2)
    local out = {}
    local n = plain_array_last(items)
    for i = 1, n do
        local v = items[i]
        if is_program(v) then
            out[#out + 1] = v
        elseif is_program_list(v) then
            local src = v.items
            for j = 1, #src do
                out[#out + 1] = src[j]
            end
        elseif v ~= nil and v ~= false then
            error("paint list accepts only Paint.Program, Paint.ProgramList, nil, or false", 2)
        end
    end
    return Paint.ProgramList(out)
end

M.T = T

return M
