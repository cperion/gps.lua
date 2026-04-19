local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local text_nav = require("ui.text_nav")

local T = ui_asdl.T
local TextEdit = T.TextEdit

local M = {}

local AFF_BACKWARD = -1
local AFF_NONE = 0
local AFF_FORWARD = 1

local function min2(a, b)
    if a < b then return a end
    return b
end

local function max2(a, b)
    if a > b then return a end
    return b
end

local function clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function affinity_mode(affinity)
    if affinity ~= nil and affinity < 0 then return "backward" end
    if affinity ~= nil and affinity > 0 then return "forward" end
    return "nearest"
end

local function clear_preferred(state)
    if state.has_preferred_x then
        return pvm.with(state, { has_preferred_x = false, preferred_x = 0 })
    end
    return state
end

local function set_preferred(state, x)
    return pvm.with(state, { has_preferred_x = true, preferred_x = x })
end

local function make_state(text, anchor, active, anchor_affinity, active_affinity)
    return TextEdit.State(text, anchor, active, anchor_affinity or AFF_NONE, active_affinity or AFF_NONE, 0, false)
end

local function collapse(state, offset, affinity)
    affinity = affinity or AFF_NONE
    return TextEdit.State(state.text, offset, offset, affinity, affinity, 0, false)
end

local function selection_range(state)
    return min2(state.anchor, state.active), max2(state.anchor, state.active)
end

local function replace_range(text, start_offset, end_offset, replacement)
    local left = start_offset > 0 and string.sub(text, 1, start_offset) or ""
    local right = string.sub(text, end_offset + 1)
    return left .. (replacement or "") .. right
end

local function boundary_for_offset(layout, offset, affinity)
    return text_nav.boundary_at_offset(layout, offset, affinity_mode(affinity))
end

local function current_boundary(layout, state)
    return boundary_for_offset(layout, state.active, state.active_affinity)
end

local function move_to_boundary(layout, state, boundary, extend, preferred_x)
    if boundary == nil then return state end
    local affinity = text_nav.boundary_affinity(layout, boundary)
    local next_state
    if extend then
        next_state = pvm.with(state, {
            active = boundary.byte_offset,
            active_affinity = affinity,
        })
    else
        next_state = pvm.with(state, {
            anchor = boundary.byte_offset,
            active = boundary.byte_offset,
            anchor_affinity = affinity,
            active_affinity = affinity,
        })
    end
    if preferred_x ~= nil then
        return set_preferred(next_state, preferred_x)
    end
    return clear_preferred(next_state)
end

function M.state(text, anchor, active)
    text = text or ""
    local n = #text
    anchor = clamp(anchor or 0, 0, n)
    active = clamp(active or anchor, 0, n)
    return make_state(text, anchor, active, AFF_NONE, AFF_NONE)
end

function M.selection_range(state)
    return selection_range(state)
end

function M.has_selection(state)
    return state.anchor ~= state.active
end

function M.caret_offset(state)
    return state.active
end

function M.caret_rect(layout, state, width)
    local boundary = boundary_for_offset(layout, state.active, state.active_affinity)
    if boundary == nil then return nil end
    return text_nav.caret_rect(layout, boundary, width)
end

function M.selection_rects(layout, state)
    local a, b = selection_range(state)
    return text_nav.selection_rects(layout, a, b)
end

function M.set_text(state, text)
    text = text or ""
    local n = #text
    return make_state(
        text,
        clamp(state.anchor, 0, n),
        clamp(state.active, 0, n),
        state.anchor_affinity or AFF_NONE,
        state.active_affinity or AFF_NONE
    )
end

function M.select_all(state)
    return make_state(state.text, 0, #state.text, AFF_NONE, AFF_NONE)
end

function M.collapse_to_start(state)
    local a = selection_range(state)
    return collapse(state, a, AFF_NONE)
end

function M.collapse_to_end(state)
    local _, b = selection_range(state)
    return collapse(state, b, AFF_NONE)
end

function M.click(layout, state, x, y, extend)
    local boundary = text_nav.boundary_at_point(layout, x, y)
    if boundary == nil then return state end
    return move_to_boundary(layout, state, boundary, extend, nil)
end

function M.move_left(layout, state, extend)
    if not extend and M.has_selection(state) then
        local a = selection_range(state)
        return collapse(state, a, AFF_NONE)
    end
    local here = current_boundary(layout, state)
    local prev = here and text_nav.prev_boundary(layout, here) or nil
    if prev == nil then return clear_preferred(state) end
    return move_to_boundary(layout, state, prev, extend, nil)
end

function M.move_right(layout, state, extend)
    if not extend and M.has_selection(state) then
        local _, b = selection_range(state)
        return collapse(state, b, AFF_NONE)
    end
    local here = current_boundary(layout, state)
    local nxt = here and text_nav.next_boundary(layout, here) or nil
    if nxt == nil then return clear_preferred(state) end
    return move_to_boundary(layout, state, nxt, extend, nil)
end

function M.move_home(layout, state, extend)
    local here = current_boundary(layout, state)
    if here == nil then return state end
    for i = 1, #layout.boundaries do
        local b = layout.boundaries[i]
        if b.line_index == here.line_index and b.line_start then
            return move_to_boundary(layout, state, b, extend, nil)
        end
    end
    return state
end

function M.move_end(layout, state, extend)
    local here = current_boundary(layout, state)
    if here == nil then return state end
    for i = 1, #layout.boundaries do
        local b = layout.boundaries[i]
        if b.line_index == here.line_index and b.line_end then
            return move_to_boundary(layout, state, b, extend, nil)
        end
    end
    return state
end

local function vertical_move(layout, state, dir, extend)
    local caret = M.caret_rect(layout, state, 1)
    if caret == nil then return state end
    local x = state.has_preferred_x and state.preferred_x or caret.x
    local target_y = caret.y + dir * caret.h + math.floor(caret.h * 0.5)
    local boundary = text_nav.boundary_at_point(layout, x, target_y)
    if boundary == nil then return set_preferred(state, x) end
    return move_to_boundary(layout, state, boundary, extend, x)
end

function M.move_up(layout, state, extend)
    return vertical_move(layout, state, -1, extend)
end

function M.move_down(layout, state, extend)
    return vertical_move(layout, state, 1, extend)
end

function M.insert_text(state, inserted)
    inserted = inserted or ""
    local a, b = selection_range(state)
    local text = replace_range(state.text, a, b, inserted)
    local caret = a + #inserted
    return make_state(text, caret, caret, AFF_NONE, AFF_NONE)
end

function M.backspace(layout, state)
    if M.has_selection(state) then
        return M.insert_text(state, "")
    end
    local here = current_boundary(layout, state)
    local prev = here and text_nav.prev_boundary(layout, here) or nil
    if prev == nil then return state end
    local affinity = text_nav.boundary_affinity(layout, prev)
    local text = replace_range(state.text, prev.byte_offset, here.byte_offset, "")
    return make_state(text, prev.byte_offset, prev.byte_offset, affinity, affinity)
end

function M.delete_forward(layout, state)
    if M.has_selection(state) then
        return M.insert_text(state, "")
    end
    local here = current_boundary(layout, state)
    local nxt = here and text_nav.next_boundary(layout, here) or nil
    if nxt == nil then return state end
    local affinity = text_nav.boundary_affinity(layout, here)
    local text = replace_range(state.text, here.byte_offset, nxt.byte_offset, "")
    return make_state(text, here.byte_offset, here.byte_offset, affinity, affinity)
end

function M.replace_selection(state, text)
    return M.insert_text(state, text)
end

function M.selected_text(state)
    local a, b = selection_range(state)
    return string.sub(state.text, a + 1, b)
end

M.T = T

return M
