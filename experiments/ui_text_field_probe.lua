package.path = "./?.lua;./?/init.lua;" .. package.path

local ui = require("ui")

local FONT = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"
local T = ui.T
local input = ui.input
local sdl3 = ui.backends.sdl3

local function layout_for(field, key)
    local style = T.Layout.TextStyle(1, 18, 400, 0xffffffff, 0, 22, 0, ui.text_field.text(field))
    return ui.text.layout(style, T.Layout.Constraint(80, math.huge), key)
end

local function show(label, field, layout)
    print(("== %s =="):format(label))
    print(("focus=%s drag=%s text=%q anchor=%d active=%d composition=%q"):format(
        field.focused and "yes" or "no",
        field.dragging and "yes" or "no",
        field.edit.text,
        field.edit.anchor,
        field.edit.active,
        field.composition_text
    ))
    local caret = ui.text_field.caret_rect(layout, field, 1)
    if caret then
        print(("caret=(%d,%d,%d,%d)"):format(caret.x, caret.y, caret.w, caret.h))
    end
end

local function main()
    local sys = sdl3.new_text_system({ default_font = FONT })
    local key = ui.text.register("field-probe", sys)
    local field = ui.text_field.state("abc def ghi jkl mno", 0, 0, { focused = true })
    local layout = layout_for(field, key)
    show("initial", field, layout)

    field = ui.text_field.pointer_pressed(layout, field, 10, 28, false)
    layout = layout_for(field, key)
    show("click", field, layout)

    field = ui.text_field.pointer_moved(layout, field, 28, 28)
    field = ui.text_field.pointer_released(field)
    layout = layout_for(field, key)
    show("drag", field, layout)

    field = ui.text_field.key(layout, field, input.KeyC, false, true, {
        set_clipboard_text = function(text) print("copy", text) end,
    })
    field = ui.text_field.key(layout, field, input.KeyX, false, true, {
        set_clipboard_text = function(text) print("cut", text) end,
    })
    layout = layout_for(field, key)
    show("cut", field, layout)

    field = ui.text_field.text_input(field, "ZZ")
    layout = layout_for(field, key)
    show("insert", field, layout)

    field = ui.text_field.text_editing(field, "ime", 1, 2)
    layout = layout_for(field, key)
    show("composition", field, layout)

    field = ui.text_field.key(layout, field, input.KeyEscape, false, false)
    layout = layout_for(field, key)
    show("escape", field, layout)

    sys:close()
end

main()
