local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Layout = T.Layout

local M = {}

local function max0(n)
    if n < 0 then return 0 end
    return n
end

local function abs(n)
    if n < 0 then return -n end
    return n
end

local function rect_distance_y(line, y)
    if y < line.y then return line.y - y end
    if y >= line.y + line.h then return y - (line.y + line.h) end
    return 0
end

local function clamp_index(i, n)
    if n <= 0 then return nil end
    if i < 1 then return 1 end
    if i > n then return n end
    return i
end

local function boundary_index(layout, boundary_or_index)
    if boundary_or_index == nil then return nil end
    if type(boundary_or_index) == "number" then
        return clamp_index(boundary_or_index, #layout.boundaries)
    end
    if pvm.classof(boundary_or_index) == Layout.TextBoundary then
        return clamp_index(boundary_or_index.boundary_index, #layout.boundaries)
    end
    error("ui.text_nav: expected boundary index or Layout.TextBoundary", 3)
end

local function line_boundaries(layout, line_index)
    local out = {}
    for i = 1, #layout.boundaries do
        local b = layout.boundaries[i]
        if b.line_index == line_index then
            out[#out + 1] = b
        end
    end
    return out
end

local function nearest_line_index(layout, y)
    local best_i = nil
    local best_d = nil
    for i = 1, #layout.lines do
        local d = rect_distance_y(layout.lines[i], y)
        if best_d == nil or d < best_d then
            best_d = d
            best_i = i
        end
    end
    return best_i
end

function M.first_boundary(layout)
    return layout.boundaries[1]
end

function M.last_boundary(layout)
    return layout.boundaries[#layout.boundaries]
end

function M.prev_boundary(layout, boundary_or_index, steps)
    local i = boundary_index(layout, boundary_or_index)
    if i == nil then return nil end
    i = i - (steps or 1)
    if i < 1 then return nil end
    return layout.boundaries[i]
end

function M.next_boundary(layout, boundary_or_index, steps)
    local i = boundary_index(layout, boundary_or_index)
    if i == nil then return nil end
    i = i + (steps or 1)
    if i > #layout.boundaries then return nil end
    return layout.boundaries[i]
end

function M.boundary_index_at_offset(layout, byte_offset, affinity)
    local n = #layout.boundaries
    if n == 0 then return nil end

    affinity = affinity or "nearest"

    local exact_first = nil
    local exact_last = nil
    local less = nil
    local greater = nil

    for i = 1, n do
        local b = layout.boundaries[i]
        if b.byte_offset == byte_offset then
            if exact_first == nil then exact_first = i end
            exact_last = i
        elseif b.byte_offset < byte_offset then
            less = i
        elseif greater == nil then
            greater = i
        end
    end

    if affinity == "backward" or affinity == "left" then
        if exact_first ~= nil then return exact_first end
        return less or greater or 1
    end

    if affinity == "forward" or affinity == "right" then
        if exact_last ~= nil then return exact_last end
        return greater or less or n
    end

    if exact_last ~= nil then
        return exact_last
    end

    local best = 1
    local best_d = abs(layout.boundaries[1].byte_offset - byte_offset)
    for i = 2, n do
        local d = abs(layout.boundaries[i].byte_offset - byte_offset)
        if d < best_d then
            best = i
            best_d = d
        end
    end
    return best
end

function M.boundary_at_offset(layout, byte_offset, affinity)
    local i = M.boundary_index_at_offset(layout, byte_offset, affinity)
    if i == nil then return nil end
    return layout.boundaries[i]
end

function M.boundary_index_at_point(layout, x, y)
    if #layout.boundaries == 0 or #layout.lines == 0 then
        return nil
    end

    local line_index = nearest_line_index(layout, y)
    if line_index == nil then return nil end

    local bs = line_boundaries(layout, line_index)
    if #bs == 0 then return nil end
    if #bs == 1 then return bs[1].boundary_index end

    if x <= bs[1].x then return bs[1].boundary_index end

    for i = 1, #bs - 1 do
        local a = bs[i]
        local b = bs[i + 1]
        local split = a.x + ((b.x - a.x) * 0.5)
        if x < split then
            return a.boundary_index
        end
    end

    return bs[#bs].boundary_index
end

function M.boundary_at_point(layout, x, y)
    local i = M.boundary_index_at_point(layout, x, y)
    if i == nil then return nil end
    return layout.boundaries[i]
end

function M.boundary_affinity(layout, boundary_or_index)
    local i = boundary_index(layout, boundary_or_index)
    if i == nil then return 0 end
    local b = layout.boundaries[i]
    local prev = layout.boundaries[i - 1]
    local nextb = layout.boundaries[i + 1]
    if nextb ~= nil and nextb.byte_offset == b.byte_offset then
        return -1
    end
    if prev ~= nil and prev.byte_offset == b.byte_offset then
        return 1
    end
    return 0
end

function M.caret_rect(layout, boundary_or_index, width)
    local i = boundary_index(layout, boundary_or_index)
    if i == nil then return nil end
    local b = layout.boundaries[i]
    return Layout.Rect(b.x, b.y, width or 1, b.h)
end

function M.selection_rects(layout, start_offset, end_offset)
    local n = #layout.boundaries
    if n == 0 then return {} end

    start_offset = start_offset or 0
    end_offset = end_offset or start_offset
    if start_offset == end_offset then return {} end

    local a = M.boundary_index_at_offset(layout, start_offset, "forward")
    local b = M.boundary_index_at_offset(layout, end_offset, "forward")
    if a == nil or b == nil then return {} end
    if a > b then a, b = b, a end

    local rects = {}
    for line_index = 1, #layout.lines do
        local first = nil
        local last = nil
        for i = a, b do
            local boundary = layout.boundaries[i]
            if boundary.line_index == line_index then
                if first == nil then first = boundary end
                last = boundary
            end
        end
        if first ~= nil and last ~= nil then
            local x1 = first.x
            local x2 = last.x
            if x2 < x1 then x1, x2 = x2, x1 end
            local w = max0(x2 - x1)
            if w > 0 then
                rects[#rects + 1] = Layout.Rect(x1, first.y, w, first.h)
            end
        end
    end
    return rects
end

M.T = T

return M
