package.path = "./?.lua;./?/init.lua;" .. package.path

local ui = require("ui")

local FONT = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"
local T = ui.T
local sdl3 = ui.backends.sdl3

local function dump_rects(rects)
    for i = 1, #rects do
        local r = rects[i]
        print(("  rect[%d]=(%d,%d,%d,%d)"):format(i, r.x, r.y, r.w, r.h))
    end
end

local function main()
    local sys = sdl3.new_text_system({ default_font = FONT })
    local key = ui.text.register("nav-probe", sys)
    local style = T.Layout.TextStyle(1, 18, 400, 0xffffffff, 0, 22, 0, "abc def ghi jkl mno")
    local layout = ui.text.layout(style, T.Layout.Constraint(80, math.huge), key)
    local nav = ui.text_nav

    print("boundaries", #layout.boundaries)

    local b0 = nav.boundary_at_offset(layout, 0, "forward")
    local b7 = nav.boundary_at_offset(layout, 7, "nearest")
    local bp = nav.boundary_at_point(layout, 10, 28)
    local prev = nav.prev_boundary(layout, bp)
    local nextb = nav.next_boundary(layout, bp)
    local caret = nav.caret_rect(layout, bp)
    local rects = nav.selection_rects(layout, 4, 15)

    print(("offset0 -> line=%d byte=%d x=%d"):format(b0.line_index, b0.byte_offset, b0.x))
    print(("offset7 -> line=%d byte=%d x=%d"):format(b7.line_index, b7.byte_offset, b7.x))
    print(("point(10,28) -> line=%d byte=%d x=%d"):format(bp.line_index, bp.byte_offset, bp.x))
    if prev then print(("prev -> line=%d byte=%d x=%d"):format(prev.line_index, prev.byte_offset, prev.x)) end
    if nextb then print(("next -> line=%d byte=%d x=%d"):format(nextb.line_index, nextb.byte_offset, nextb.x)) end
    print(("caret=(%d,%d,%d,%d)"):format(caret.x, caret.y, caret.w, caret.h))
    print("selection rects")
    dump_rects(rects)

    sys.close()
end

main()
