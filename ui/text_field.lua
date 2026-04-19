local pvm = require("pvm")
local input = require("ui.input")
local text_edit = require("ui.text_edit")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local TextEdit = T.TextEdit
local TextField = T.TextField

local M = {}

local function with_edit(state, edit)
    return pvm.with(state, { edit = edit })
end

local function clear_composition(state)
    if state.composition_text == "" and state.composition_start == 0 and state.composition_length == 0 then
        return state
    end
    return pvm.with(state, {
        composition_text = "",
        composition_start = 0,
        composition_length = 0,
    })
end

function M.state(text_or_edit, anchor, active, opts)
    opts = opts or {}

    local edit = text_or_edit
    if pvm.classof(edit) ~= TextEdit.State then
        edit = text_edit.state(text_or_edit, anchor, active)
    end

    return TextField.State(
        edit,
        opts.focused == true,
        opts.dragging == true,
        opts.composition_text or "",
        opts.composition_start or 0,
        opts.composition_length or 0
    )
end

function M.edit_state(state)
    return state.edit
end

function M.text(state)
    return state.edit.text
end

function M.set_edit_state(state, edit)
    return pvm.with(state, { edit = edit })
end

function M.selection_range(state)
    return text_edit.selection_range(state.edit)
end

function M.has_selection(state)
    return text_edit.has_selection(state.edit)
end

function M.selected_text(state)
    return text_edit.selected_text(state.edit)
end

function M.caret_offset(state)
    return text_edit.caret_offset(state.edit)
end

function M.caret_rect(layout, state, width)
    return text_edit.caret_rect(layout, state.edit, width)
end

function M.selection_rects(layout, state)
    return text_edit.selection_rects(layout, state.edit)
end

function M.composition_active(state)
    return #state.composition_text > 0
end

function M.focus(state)
    if state.focused then return state end
    return pvm.with(state, { focused = true })
end

function M.blur(state)
    state = clear_composition(state)
    if not state.focused and not state.dragging then return state end
    return pvm.with(state, {
        focused = false,
        dragging = false,
    })
end

function M.pointer_pressed(layout, state, x, y, extend)
    local edit = text_edit.click(layout, state.edit, x, y, extend)
    return clear_composition(pvm.with(state, {
        edit = edit,
        focused = true,
        dragging = true,
    }))
end

function M.pointer_pressed_outside(state)
    return M.blur(state)
end

function M.pointer_moved(layout, state, x, y)
    if not state.focused or not state.dragging then return state end
    return with_edit(state, text_edit.click(layout, state.edit, x, y, true))
end

function M.pointer_released(state)
    if not state.dragging then return state end
    return pvm.with(state, { dragging = false })
end

function M.text_input(state, text)
    if not state.focused then return state end
    return clear_composition(with_edit(state, text_edit.insert_text(state.edit, text or "")))
end

function M.text_editing(state, text, start, length)
    if not state.focused then return state end
    return pvm.with(state, {
        composition_text = text or "",
        composition_start = start or 0,
        composition_length = length or 0,
    })
end

function M.key(layout, state, key, shift, ctrl, opts)
    if not state.focused then return state end

    opts = opts or {}
    if (opts.repeat_ or 0) ~= 0 then
        return state
    end

    local edit = state.edit

    if ctrl and key == input.KeyA then
        edit = text_edit.select_all(edit)
    elseif ctrl and key == input.KeyC then
        if text_edit.has_selection(edit) and opts.set_clipboard_text ~= nil then
            opts.set_clipboard_text(text_edit.selected_text(edit))
        end
        return state
    elseif ctrl and key == input.KeyX then
        if text_edit.has_selection(edit) then
            if opts.set_clipboard_text ~= nil then
                opts.set_clipboard_text(text_edit.selected_text(edit))
            end
            edit = text_edit.replace_selection(edit, "")
        else
            return state
        end
    elseif ctrl and key == input.KeyV then
        local clip = opts.get_clipboard_text and opts.get_clipboard_text() or nil
        if clip == nil then return state end
        edit = text_edit.insert_text(edit, clip)
    elseif key == input.KeyLeft then
        edit = text_edit.move_left(layout, edit, shift)
    elseif key == input.KeyRight then
        edit = text_edit.move_right(layout, edit, shift)
    elseif key == input.KeyUp then
        edit = text_edit.move_up(layout, edit, shift)
    elseif key == input.KeyDown then
        edit = text_edit.move_down(layout, edit, shift)
    elseif key == input.KeyHome then
        edit = text_edit.move_home(layout, edit, shift)
    elseif key == input.KeyEnd then
        edit = text_edit.move_end(layout, edit, shift)
    elseif key == input.KeyBackspace then
        edit = text_edit.backspace(layout, edit)
    elseif key == input.KeyDelete then
        edit = text_edit.delete_forward(layout, edit)
    elseif key == input.KeyReturn then
        edit = text_edit.insert_text(edit, "\n")
    elseif key == input.KeyEscape then
        return M.blur(state)
    else
        return state
    end

    return clear_composition(with_edit(state, edit))
end

function M.input_rect(layout, state, x, y, width)
    if not state.focused then return nil end
    local caret = M.caret_rect(layout, state, width)
    if caret == nil then return nil end
    return {
        x = (x or 0) + caret.x,
        y = (y or 0) + caret.y,
        w = caret.w,
        h = caret.h,
    }
end

M.T = T

return M
