package.path = "./?.lua;./?/init.lua;" .. package.path

local ui = require("ui")

local FONT = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"
local T = ui.T
local sdl3 = ui.backends.sdl3

local function style_for(text, fg)
    return T.Layout.TextStyle(1, 18, 400, fg or 0xffffffff, 0, 22, 0, text)
end

local function main()
    local host = sdl3.new_host {
        title = "text-field-view-probe",
        width = 320,
        height = 200,
        default_font = FONT,
    }
    local key = ui.text.register("field-view-probe", host.text_system)
    local field = ui.text_field.state("abc def ghi", 4, 7, {
        focused = true,
        composition_text = "ime",
        composition_start = 1,
        composition_length = 2,
    })

    local resolved = ui.text_field_view.resolve(host, field, {
        x = 10,
        y = 20,
        w = 200,
        h = 80,
        padding = 8,
        text_key = key,
        text_style = function(f)
            return style_for(ui.text_field.text(f))
        end,
        composition_style = function(f)
            return style_for(f.composition_text, 0x93c5fdff)
        end,
    })

    local rect = ui.text_field_view.apply_text_input_rect(host, field, resolved, 1)
    print("resolved", resolved.outer_w, resolved.outer_h, resolved.inner_w, #resolved.layout.lines, #ui.text_field.selection_rects(resolved.layout, field))
    print("contains", ui.text_field_view.contains(resolved, 15, 25), ui.text_field_view.contains(resolved, 500, 500))
    print("local", ui.text_field_view.local_point(resolved, 15, 25))
    print("input-rect", rect and rect.x or -1, rect and rect.y or -1, rect and rect.w or -1, rect and rect.h or -1)

    host:close()
end

main()
