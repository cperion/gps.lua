package.path = "./?.lua;./?/init.lua;" .. package.path

local ui = require("ui")

local FONT = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"
local T = ui.T
local sdl3 = ui.backends.sdl3

local function main()
    local sys = sdl3.new_text_system({ default_font = FONT })
    local key = ui.text.register("selection-probe", sys)
    local text = "abc def ghi jkl mno"
    local style = T.Layout.TextStyle(1, 18, 400, 0xffffffff, 0, 22, 0, text)
    local layout = ui.text.layout(style, T.Layout.Constraint(80, math.huge), key)

    print("lines", #layout.lines, "boundaries", #layout.boundaries)
    for i = 1, #layout.lines do
        local line = layout.lines[i]
        print("line", i, line.byte_start, line.byte_end, line.x, line.y, line.w, line.h)
    end

    local cases = {
        { 0, 7 },
        { 0, 8 },
        { 8, 11 },
        { 0, 11 },
    }
    for i = 1, #cases do
        local a, b = cases[i][1], cases[i][2]
        local rects = ui.text_nav.selection_rects(layout, a, b)
        io.write(string.format("sel[%d] [%d,%d) rects=%d", i, a, b, #rects))
        for j = 1, #rects do
            local r = rects[j]
            io.write(string.format(" (%d,%d,%d,%d)", r.x, r.y, r.w, r.h))
        end
        io.write("\n")
    end

    ui.text.unregister(key)
    sys:close()
end

main()
