local ui = require("ui")
local hit = require("ui.hit")
local measure = require("ui.measure")

local T = ui.T
local L = T.Layout
local U = T.UI

local ZERO_COLOR = T.DS.ColorPack(0, 0, 0, 0)
local ZERO_NUM = T.DS.NumPack(0, 0, 0, 0)
local ONE_NUM = T.DS.NumPack(1, 1, 1, 1)
local BOX_STYLE = U.BoxStyle(0, 0, 0, ZERO_COLOR, ZERO_COLOR, ZERO_COLOR, ZERO_NUM, ONE_NUM)
local AUTO_BOX = L.Box(L.SizeAuto, L.SizeAuto, L.NoMin, L.NoMin, L.NoMax, L.NoMax)
local ZERO_INSETS = L.Insets(0, 0, 0, 0)

local passed = 0
local failed = 0

local function check(name, got, want)
    if got ~= want then
        io.stderr:write(("FAIL %s: got %s want %s\n"):format(name, tostring(got), tostring(want)))
        failed = failed + 1
        return
    end
    passed = passed + 1
end

local function rect(tag, h, min_w, max_w)
    return U.Rect(tag or "",
        L.Box(L.SizeAuto, L.SizePx(h or 20), min_w or L.NoMin, L.NoMin, max_w or L.NoMax, L.NoMax),
        BOX_STYLE)
end

local function sized_rect(tag, w, h)
    return U.Rect(tag or "",
        L.Box(L.SizePx(w), L.SizePx(h or 20), L.NoMin, L.NoMin, L.NoMax, L.NoMax),
        BOX_STYLE)
end

local function text_node(tag, text, line_height_px)
    return U.Text(tag or "", AUTO_BOX,
        U.TextStyle(0, ZERO_COLOR, ONE_NUM,
            L.LineHeightPx(line_height_px or 16),
            L.TextStart,
            L.TextNoWrap,
            L.OverflowVisible,
            L.UnlimitedLines),
        text or "A")
end

local function hitbox(id, node)
    return U.Interact("", id, "", "", node)
end

local function item(node, opts)
    opts = opts or {}
    return U.FlexItem(
        node,
        opts.grow or 0,
        opts.shrink or 0,
        opts.basis or L.BasisAuto,
        opts.align or L.CrossAuto,
        opts.margin or ZERO_INSETS)
end

local function row(children, opts)
    opts = opts or {}
    return U.Flex(
        opts.axis or L.AxisRow,
        opts.wrap or L.WrapNoWrap,
        opts.gap_main or 0,
        opts.gap_cross or 0,
        opts.justify or L.MainStart,
        opts.align_items or L.CrossStart,
        opts.align_content or L.ContentStart,
        AUTO_BOX,
        children)
end

local function grid(cols, children, opts)
    opts = opts or {}
    local col_tracks = {}
    for i = 1, cols do
        col_tracks[i] = L.TrackFr(1)
    end
    local row_tracks = {}
    local rows = math.max(1, math.ceil(#children / cols))
    for i = 1, rows do
        row_tracks[i] = L.TrackAuto
    end
    local items = {}
    for i = 1, #children do
        items[i] = U.GridItem(children[i], ((i - 1) % cols) + 1, math.floor((i - 1) / cols) + 1, 1, 1)
    end
    return U.Grid(col_tracks, row_tracks, opts.gap_x or 0, opts.gap_y or 0, opts.box or AUTO_BOX, items)
end

local function scroll(id, child)
    return U.ScrollArea(id, L.ScrollX, 0, 0, AUTO_BOX, BOX_STYLE, child)
end

local function hit_id(node, w, h, x, y)
    return hit.id(node, ui.frame(0, 0, w, h), x, y)
end

local function scroll_id(node, w, h, x, y)
    return hit.scroll_id(node, ui.frame(0, 0, w, h), x, y)
end

-- Grow path: max-clamped item should freeze and leave the rest of the free space
-- to later items.
do
    local node = row({
        item(hitbox("a", rect("a", 20, L.NoMin, L.MaxPx(40))), {
            grow = 1,
            shrink = 1,
            basis = L.BasisPx(30),
        }),
        item(hitbox("b", rect("b", 20)), {
            grow = 1,
            shrink = 1,
            basis = L.BasisPx(30),
        }),
    })
    check("grow-freeze-left", hit_id(node, 100, 20, 35, 10), "a")
    check("grow-freeze-right", hit_id(node, 100, 20, 45, 10), "b")
end

-- Wrap should use clamped hypothetical main size, not raw basis.
do
    local node = row({
        item(hitbox("a", rect("a", 20, L.MinPx(60), L.NoMax)), {
            basis = L.BasisPx(10),
        }),
        item(hitbox("b", rect("b", 20)), {
            basis = L.BasisPx(10),
        }),
    }, {
        wrap = L.WrapWrap,
    })
    check("wrap-hypo-first-line", hit_id(node, 65, 40, 5, 5), "a")
    check("wrap-hypo-second-line", hit_id(node, 65, 40, 5, 25), "b")

    local m = measure.measure(node, measure.constraint(measure.at_most(65), measure.UNCONSTRAINED))
    check("measure-wrap-hypo-height", m.used_h, 40)
end

-- Negative free space with center alignment should center overflow, not silently
-- fall back to start packing.
do
    local node = row({
        item(hitbox("a", rect("a", 20)), {
            basis = L.BasisPx(80),
            shrink = 0,
        }),
        item(hitbox("b", rect("b", 20)), {
            basis = L.BasisPx(80),
            shrink = 0,
        }),
    }, {
        justify = L.MainCenter,
    })
    check("overflow-center-left", hit_id(node, 100, 20, 20, 10), "a")
    check("overflow-center-right", hit_id(node, 100, 20, 70, 10), "b")
end

-- Reverse flow should reverse placement, not item order.
do
    local node = row({
        item(hitbox("a", rect("a", 20)), { basis = L.BasisPx(20) }),
        item(hitbox("b", rect("b", 20)), { basis = L.BasisPx(20) }),
    }, {
        axis = L.AxisRowReverse,
    })
    check("row-reverse-left", hit_id(node, 40, 20, 5, 10), "b")
    check("row-reverse-right", hit_id(node, 40, 20, 35, 10), "a")
end

-- Wrap-reverse should stack later lines above earlier ones.
do
    local node = row({
        item(hitbox("a", rect("a", 20)), { basis = L.BasisPx(30) }),
        item(hitbox("b", rect("b", 20)), { basis = L.BasisPx(30) }),
        item(hitbox("c", rect("c", 20)), { basis = L.BasisPx(30) }),
    }, {
        wrap = L.WrapWrapReverse,
    })
    check("wrap-reverse-top", hit_id(node, 60, 40, 5, 5), "c")
    check("wrap-reverse-bottom", hit_id(node, 60, 40, 5, 25), "a")
end

-- Baseline alignment should synthesize a baseline for non-text items so shorter
-- boxes align to the text baseline instead of sticking to cross-start.
do
    local node = row({
        item(hitbox("a", text_node("a", "A", 40)), { basis = L.BasisPx(20) }),
        item(hitbox("b", rect("b", 20)), { basis = L.BasisPx(20) }),
    }, {
        align_items = L.CrossBaseline,
    })
    check("baseline-synth-miss-top", hit_id(node, 40, 40, 25, 5), nil)
    check("baseline-synth-hit-shifted", hit_id(node, 40, 40, 25, 15), "b")
end

-- Scroll containers inside flex should still be discoverable by scroll hit
-- routing at their placed frame.
do
    local node = row({
        item(rect("left", 20), { basis = L.BasisPx(20) }),
        item(scroll("scroll", sized_rect("content", 200, 20)), {
            basis = L.BasisPx(20),
            grow = 1,
        }),
    })
    check("scroll-in-flex-outside", scroll_id(node, 100, 20, 10, 10), nil)
    check("scroll-in-flex-inside", scroll_id(node, 100, 20, 30, 10), "scroll")
end

-- Simple equal-cell grid should place children row-major and expose their hit ids.
do
    local node = grid(2, {
        hitbox("a", sized_rect("a", 20, 20)),
        hitbox("b", sized_rect("b", 20, 20)),
        hitbox("c", sized_rect("c", 20, 20)),
    }, { gap_x = 4, gap_y = 4, box = L.Box(L.SizePx(44), L.SizeAuto, L.NoMin, L.NoMin, L.NoMax, L.NoMax) })
    check("grid-top-left", hit_id(node, 44, 44, 5, 5), "a")
    check("grid-top-right", hit_id(node, 44, 44, 27, 5), "b")
    check("grid-bottom-left", hit_id(node, 44, 44, 5, 27), "c")
end

-- Grid intrinsic height should account for rows and row gaps.
do
    local node = grid(2, {
        sized_rect("a", 20, 10),
        sized_rect("b", 20, 10),
        sized_rect("c", 20, 10),
    }, { gap_x = 4, gap_y = 6, box = AUTO_BOX })
    local m = measure.measure(node, measure.constraint(measure.at_most(44), measure.UNCONSTRAINED))
    check("grid-measure-height", m.used_h, 26)
end

-- Spanning should cover multiple tracks and preserve hit geometry.
do
    local node = U.Grid(
        { L.TrackPx(20), L.TrackPx(20) },
        { L.TrackAuto, L.TrackAuto },
        4,
        6,
        L.Box(L.SizePx(44), L.SizeAuto, L.NoMin, L.NoMin, L.NoMax, L.NoMax),
        {
            U.GridItem(hitbox("span", sized_rect("span", 44, 10)), 1, 1, 2, 1),
            U.GridItem(hitbox("bottom", sized_rect("bottom", 20, 10)), 1, 2, 1, 1),
        })
    check("grid-span-hit-left", hit_id(node, 44, 26, 5, 5), "span")
    check("grid-span-hit-right", hit_id(node, 44, 26, 35, 5), "span")
    check("grid-span-hit-bottom", hit_id(node, 44, 26, 5, 20), "bottom")
end

io.stdout:write(("%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then
    os.exit(1)
end
