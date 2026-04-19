package.path = "./?.lua;./?/init.lua;" .. package.path

local ui = require("ui")

local T = ui.T

local function kb()
    collectgarbage()
    return collectgarbage("count")
end

local function main()
    local before = kb()
    local field = ui.text_field.state("abcdefghijklmnopqrstuvwxyz", 0, 0, { focused = true })

    for i = 1, 5000 do
        local layout = ui.text.approx_layout(
            T.Layout.TextStyle(1, 16, 400, 0xffffffff, 0, 20, 0, ui.text_field.text(field)),
            T.Layout.Constraint(200, math.huge)
        )
        field = ui.text_field.key(layout, field, ui.input.KeyA, false, true, {})
        field = ui.text_field.key(layout, field, ui.input.KeyBackspace, false, false, {})
        field = ui.text_field.text_input(field, "x" .. i)
    end

    local after = kb()
    print("kb-before", before)
    print("kb-after", after)
    print("kb-delta", after - before)
    print("final-text-len", #ui.text_field.text(field))
end

main()
