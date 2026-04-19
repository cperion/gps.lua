package.path = "./?.lua;./?/init.lua;" .. package.path

local ui = require("ui")

local FONT = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"
local T = ui.T
local sdl3 = ui.backends.sdl3

local function style_for(state)
    return T.Layout.TextStyle(1, 18, 400, 0xffffffff, 0, 22, 0, state.text)
end

local function layout_for(sys, state)
    local key = ui.text.register("edit-probe", sys)
    return ui.text.layout(style_for(state), T.Layout.Constraint(80, math.huge), key)
end

local function show(label, state, layout)
    local a, b = ui.text_edit.selection_range(state)
    local caret = ui.text_edit.caret_rect(layout, state)
    print(("== %s =="):format(label))
    print(("text=%q anchor=%d active=%d selection=[%d,%d) boundaries=%d"):format(
        state.text, state.anchor, state.active, a, b, #layout.boundaries
    ))
    if caret then
        print(("caret=(%d,%d,%d,%d)"):format(caret.x, caret.y, caret.w, caret.h))
    end
    local rects = ui.text_edit.selection_rects(layout, state)
    for i = 1, #rects do
        local r = rects[i]
        print(("sel[%d]=(%d,%d,%d,%d)"):format(i, r.x, r.y, r.w, r.h))
    end
end

local function main()
    local sys = sdl3.new_text_system({ default_font = FONT })
    local edit = ui.text_edit

    local state = edit.state("abc def ghi jkl mno", 0, 0)
    local layout = layout_for(sys, state)
    show("initial", state, layout)

    state = edit.click(layout, state, 10, 28, false)
    layout = layout_for(sys, state)
    show("click second line", state, layout)

    state = edit.move_right(layout, state, false)
    layout = layout_for(sys, state)
    show("move right", state, layout)

    state = edit.insert_text(state, "ZZ")
    layout = layout_for(sys, state)
    show("insert ZZ", state, layout)

    state = edit.move_left(layout, state, true)
    state = edit.move_left(layout, state, true)
    layout = layout_for(sys, state)
    show("extend selection left twice", state, layout)

    state = edit.replace_selection(state, "*")
    layout = layout_for(sys, state)
    show("replace selection with *", state, layout)

    state = edit.move_down(layout, state, false)
    layout = layout_for(sys, state)
    show("move down", state, layout)

    state = edit.backspace(layout, state)
    layout = layout_for(sys, state)
    show("backspace", state, layout)

    state = edit.delete_forward(layout, state)
    layout = layout_for(sys, state)
    show("delete forward", state, layout)

    sys.close()
end

main()
