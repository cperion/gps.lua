package.path = "./?.lua;./?/init.lua;" .. package.path

local ui = require("ui")

local T = ui.T
local b = ui.build

local function main()
    local recipe = ui.recipes.scroll_view {
        id = b.id("probe-scroll"),
        items = {},
    }

    local report = T.Interact.Report(
        T.Core.NoId,
        T.Core.NoId,
        T.Style.CursorDefault,
        T.Core.NoId,
        {},
        {},
        {
            T.Interact.ScrollBox(b.id("probe-scroll"), T.Style.ScrollY, 10, 20, 120, 80, 120, 320, 0, 240),
        },
        {},
        {},
        {}
    )

    local model = ui.interact.model {
        pointer_x = 125,
        pointer_y = 45,
        scrolls = {
            T.Solve.Scroll(b.id("probe-scroll"), 0, 60),
        },
    }

    local resolved = recipe:resolve(report, model, {
        thickness = 10,
        inset = 4,
        min_thumb_px = 24,
    })
    assert(resolved ~= nil)
    assert(resolved.vertical ~= nil)

    local next_model, handled = recipe:pointer_pressed(model, report, 125, 90, {
        thickness = 10,
        inset = 4,
        min_thumb_px = 24,
    })
    local x, y = ui.interact.scroll_offset(next_model, b.id("probe-scroll"))

    local key_model, key_handled = recipe:key(model, report, ui.input.KeyPageDown)
    local _, key_y = ui.interact.scroll_offset(key_model, b.id("probe-scroll"))

    local thumb_x = resolved.vertical.thumb.x + 2
    local thumb_y = resolved.vertical.thumb.y + 2
    local drag_model, drag_handled, _, drag = recipe:pointer_pressed(model, report, thumb_x, thumb_y, {
        thickness = 10,
        inset = 4,
        min_thumb_px = 24,
    })
    drag_model, drag_handled, drag = recipe:pointer_moved(drag_model, report, drag, thumb_x, resolved.vertical.track.y + resolved.vertical.track.h)
    local _, drag_y = ui.interact.scroll_offset(drag_model, b.id("probe-scroll"))

    print("scroll-view-ok", handled and 1 or 0, resolved.vertical.track.h, resolved.vertical.thumb.h, x, y, key_handled and 1 or 0, key_y, drag_handled and 1 or 0, drag_y)
end

main()
