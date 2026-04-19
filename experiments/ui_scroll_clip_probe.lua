package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local ui = require("ui")

local T = ui.T
local View = T.View
local Style = T.Style
local Core = T.Core

local function id(s)
    return Core.IdValue(s)
end

local function op(kind, id_, x, y, w, h, dx, dy, scroll_axis)
    return View.Op(kind, id_ or Core.NoId, x or 0, y or 0, w or 0, h or 0, dx or 0, dy or 0, nil, nil, nil, scroll_axis, nil)
end

local SCROLL_ID = id("scroll")
local HIT_ID = id("child-hit")
local DRAG_ID = id("child-drag")
local SLOT_ID = id("child-slot")

local ops = {
    op(View.KPushClip, Core.NoId, 0, 0, 100, 45),
    op(View.KPushScroll, SCROLL_ID, 0, 0, 100, 50, 100, 200, Style.ScrollY),
    op(View.KHit, HIT_ID, 0, 70, 100, 20),
    op(View.KDragSource, DRAG_ID, 0, 70, 100, 20),
    op(View.KDropSlot, SLOT_ID, 0, 70, 100, 20),
    op(View.KPopScroll),
    op(View.KPopClip),
}

local function run(opts)
    return ui.runtime.run(nil, opts or {}, pvm.seq(ops))
end

local function assert_eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function main()
    local report0 = run {
        pointer_x = 10,
        pointer_y = 46,
        collect_hits = true,
    }
    assert_eq(#report0.scrollables, 1, "scrollables count")
    assert_eq(report0.scrollables[1].h, 45, "scroll viewport clipped by parent clip")
    assert_eq(report0.scroll_id, Core.NoId, "scroll hit outside visible clipped region")
    assert_eq(#report0.hits, 0, "fully clipped child hit hidden")

    local report1 = run {
        pointer_x = 10,
        pointer_y = 10,
        collect_hits = true,
    }
    assert_eq(report1.scroll_id, SCROLL_ID, "scroll hit inside visible clipped region")
    assert_eq(report1.scrollables[1].content_h, 200, "scroll content_h")
    assert_eq(report1.scrollables[1].max_y, 150, "scroll max_y clamp")

    local model = ui.interact.model {}
    model = ui.interact.apply(model, T.Interact.ScrollBy(SCROLL_ID, 0, 999), report1)
    local _, clamped_y = ui.interact.scroll_offset(model, SCROLL_ID)
    assert_eq(clamped_y, 150, "manual scroll clamp")

    local stepped_model, events = ui.interact.step(model, report1, ui.interact.wheel_moved(0, 500, 10, 10))
    local _, stepped_y = ui.interact.scroll_offset(stepped_model, SCROLL_ID)
    assert_eq(stepped_y, 150, "wheel does not absorb past max")
    assert_eq(#events, 2, "wheel emits only pointer+hover when already clamped")

    local report2 = run {
        pointer_x = 10,
        pointer_y = 42,
        collect_hits = true,
        scrolls = {
            T.Solve.Scroll(SCROLL_ID, 0, 30),
        },
    }
    assert_eq(#report2.hits, 1, "partially visible child hit survives")
    assert_eq(report2.hits[1].y, 40, "hit translated by scroll")
    assert_eq(report2.hits[1].h, 5, "hit clipped by parent+scroll viewport")
    assert_eq(#report2.drag_sources, 1, "drag source clipped with scroll")
    assert_eq(report2.drag_sources[1].h, 5, "drag source clipped height")
    assert_eq(#report2.drop_slots, 1, "drop slot clipped with scroll")
    assert_eq(report2.drop_slots[1].h, 5, "drop slot clipped height")

    print("scroll-clip-ok", report1.scrollables[1].max_y, report2.hits[1].h, #report2.drag_sources, #report2.drop_slots)
end

main()
