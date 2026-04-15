# ui/

Fresh restart.

The previous restart attempt was archived to:

- `archive/legacy_ui/ui_2026-04-14_attempt1/`

We are restarting from the ASDL design.

Current files:
- `ui/asdl.lua` — fresh iterator-first schema draft
- `ui/normalize.lua` — style normalization built as stream expansion (`Token -> Decl*`) plus fold (`TokenList -> Spec`)
- `ui/resolve.lua` — theme resolution from canonical `Style.Spec` to concrete resolved/layout-ready values
- `ui/tw.lua` — typed Tailwind-style authoring surface over `Style.Token`
- `ui/build.lua` — immediate-mode authored node builders for `Auth.Box`, `Auth.Text`, `Auth.Paint`, `Auth.Scroll`, `Auth.Fragment`, and `Auth.WithInput`
- `ui/compose.lua` — `Compose.Node -> Auth.Node` lowering phase for recurring shell/panel composition nouns defined in `module Compose`
- `ui/paint.lua` — typed custom paint primitives (`Line`, `Polyline`, `Polygon`, `Circle`, `Arc`, `Bezier`, `Mesh`, `Image`) plus builder helpers
- `ui/lower.lua` — authored tree lowering phase (`Auth.Node × Theme.T × Env.Class -> Layout.Node*`)
- `ui/text.lua` — text layout backend bridge; provides default approximate layout plus explicit backend-keyed registration for real measurers
- `ui/text_love.lua` — concrete Love2D text measurement adapter that plugs into `ui.text.register(...)`
- `ui/interact.lua` — typed interaction layer over the runtime report: raw input ASDL → semantic event stream → pure interaction-model apply (`classify_phase`, `apply`, `step`, `focus_move`, `state`)
- `ui/plan.lua` — shared layout planning helpers used by both measure and render; currently owns shared flow/flex/grid planning helpers
- `ui/measure.lua` — measurement phase over lowered layout nodes (`Layout.Node × Layout.Constraint × text_system? -> Layout.Size`)
- `ui/render.lua` — streamed relative-op render phase (`Layout.Node × width × height × text_system? -> View.Op*`), with `render.root(node, env, text_system)` using only root viewport size; scroll is represented by streamed scroll ops rather than cache-keyed runtime env
- `ui/runtime.lua` — direct `View.Op` consumer; executes the op stream through transform/clip/scroll stacks and simultaneously gathers hit/focus/cursor facts from the same stream as a typed `Interact.Report`
- `ui/runtime_love.lua` — concrete Love2D executor backend for `ui.runtime`, including `KPaint` execution for Love lines/shapes/meshes/images
- `ui/init.lua` — minimal facade exposing `ui.asdl`, `ui.T`, `ui.normalize`, `ui.resolve`, `ui.tw`, `ui.build`, `ui.compose`, `ui.paint`, `ui.text`, `ui.text_love`, `ui.interact`, `ui.lower`, `ui.measure`, `ui.render`, `ui.runtime`, and `ui.runtime_love`

Current design fixes already applied:
- render no longer keys subtree caches on changing runtime scroll env
- interaction semantics are explicit via `WithInput(id, role, child)` instead of inferring hit/focus from plain ids
- scroll is now structural too: `Auth.Scroll(id, axis, child)` lowers to `Layout.Scroll`, and runtime scrolling is driven by that structural viewport rather than being inferred only from overflow style
- focus order is stream order; there is no explicit focus-order field on view ops
- `DisplayFlow` is no longer silently lowered as flex; it lowers to its own `Layout.Flow` vocabulary and uses a shared flow planner in both measure and render
- flow auto-width semantics are now display-specific: flow containers and flow children with `auto` width fill available width when constrained, instead of collapsing to hug semantics everywhere
- flex planning is now shared too: `ui.plan.flex_plan(...)` drives both `measure` and `render`
- authored flex `grow`, `shrink`, and `basis` now participate in flex line planning instead of being dead fields
- row-wrap line breaking now happens in shared flex planning rather than only in measure
- grid planning is now shared too: `ui.plan.grid_plan(...)` drives both `measure` and `render`
- grid row tracks are now actually solved from authored row tracks plus item content, instead of always being derived ad hoc from measured child heights
- implicit auto tracks are synthesized when grid items reference rows/columns beyond the authored track arrays
- text layout is now an explicit backend bridge: `ui.text_layout(style, constraint, text_system)` is a parametric sub-phase, and `measure`/`render` accept an explicit `text_system` cache dimension
- `ui.text.register(key, system)` allows a real text measurer to participate without hiding the dependency; caches separate on the explicit `text_system` key
- `Layout.TextLayout` now carries wrapped `lines`, so the measured text fact is closer to an execution-ready text layout artifact rather than just width/height scalars

## Compose layer

`module Compose` is now a real ASDL layer for recurring shell/panel patterns.
`ui.compose.phase(node)` lowers `Compose.Node` values into ordinary `Auth.Node` trees.

Available nouns:
- `Compose.Raw(Auth.Node child)`
- `Compose.Fragment(Compose.Node* children)`
- `Compose.Panel(...)`
- `Compose.ScrollPanel(...)`
- `Compose.HSplit(...)`
- `Compose.VSplit(...)`
- `Compose.Workbench(...)`

Preferred authoring style:

```lua
local ui = require("ui")
local T = ui.T
local F = T:FastBuilders()
local b = ui.build
local tw = ui.tw

local shell = F.Compose.ScrollPanel {
    id = b.id("browser-panel"),
    styles = tw.list {
        tw.flex, tw.col,
        tw.w_px(320), tw.h_px(480),
        tw.p_4, tw.gap_y_4,
        tw.bg.slate[900],
        tw.border_1, tw.border_color.slate[800],
    },
    header = F.Compose.Raw {
        child = b.text { tw.text_xl, tw.font_semibold, tw.fg.white, "Browser" },
    },
    scroll_id = b.id("browser-scroll"),
    axis = T.Style.ScrollY,
    body = F.Compose.Raw {
        child = b.fragment(rows),
    },
}

local auth = ui.compose.root(shell)
```

Design rule:
- recurring shell/panel composition should live in ASDL when it is a real noun
- `ui.compose` is a lowering phase, not a callback helper layer
- use raw `ui.build` directly when the pattern is local and not worth naming

## Structural scroll

`ui/` now has a first-class authored/layout scroll wrapper:

```lua
local b = ui.build
local T = ui.T
local tw = ui.tw

local node = b.scroll_y(b.id("browser-scroll"), {
    tw.h_px(320),
    tw.border_1, tw.border_color.slate[800],
    tw.bg.slate[950],
    b.fragment(rows),
})
```

Available builders:
- `b.scroll(id, T.Style.ScrollX | ScrollY | ScrollBoth, { ... })`
- `b.scroll_x(id, { ... })`
- `b.scroll_y(id, { ... })`
- `b.scroll_both(id, { ... })`

Design rule:
- **clipping is style** (`overflow_hidden`)
- **scrolling is structure** (`Auth.Scroll`)

For compatibility, authored boxes that still use `overflow_scroll` / `overflow_auto` are lowered through a compatibility path to structural `Layout.Scroll`, but new code should prefer explicit scroll wrappers.

Compiler-pattern audit: still-open gaps worth fixing next
- flex semantics are better but still not full CSS flexbox: no explicit `align-content`, no special auto-margin behavior on the flex main axis, and baseline alignment is still approximate
- grid semantics are better but still not full CSS grid: content-based multi-span resolution is simple, item-specific alignment vocabulary is not authored yet, and dense/auto-placement does not exist
- real text shaping is now pluggable, and `ui.text_love` provides a concrete Love2D measurer, but other backends still need their own adapters
- the execution side now has a real op-stream consumer: `ui.runtime.run(driver, opts, render_triplet...)` walks the same `View.Op*` stream to draw, clip, scroll, hit-test, build focus order, and choose cursor
- the runtime result is now a typed `Interact.Report` ASDL value rather than an ad hoc Lua table, so the execution-side facts are visible to the rest of the system
- `Interact.Raw`, `Interact.Event`, and `Interact.Model` now define a generic typed event/apply loop for UI interaction
- `ui.interact.classify_phase(raw, model, report)` turns raw host input plus the current typed runtime report into semantic UI events
- `ui.interact.apply(model, event)` and `ui.interact.step(model, report, raw)` provide the pure reducer layer over interaction state
- `examples/ui_love_demo/main.lua` uses that typed loop for pointer movement, clicking, wheel scrolling, focus navigation, and activation
- `examples/ui_studio_demo/main.lua` is a richer multi-pane Love2D workspace demo intended to show off the current library honestly: browser rail, live matrix, inspector, device dock, multiple scroll regions, and typed interaction wiring

## Custom paint

`ui/` now has first-class typed custom paint support.

Architecture:

```text
Auth.Paint -> Layout.Paint -> View.KPaint -> runtime driver:draw_paint(...)
```

Important rules:
- paint programs are ASDL values, not callbacks
- paint coordinates are local to the paint box
- clipping / transforms / scrolling are still handled by the normal `View.Op` runtime
- a paint node currently has no intrinsic content measurement beyond its styled box/padding, so author width/height explicitly

Authoring example:

```lua
local ui = require("ui")
local b = ui.build
local tw = ui.tw
local paint = ui.paint

local node = b.paint {
    b.id("scope"),
    tw.w_px(240), tw.h_px(96),
    tw.rounded_lg,
    tw.border_1, tw.border_color.slate[800],
    tw.bg.slate[950],

    paint.line(0, 48, 240, 48, paint.stroke(0x334155ff, 1)),
    paint.polyline({ 0,48, 40,30, 80,60, 120,20, 160,70, 240,40 }, paint.stroke(0x38bdf8ff, 2)),
    paint.circle(180, 32, 6, paint.fill(0x38bdf8ff), nil),
}
```

Available primitives:
- `paint.line(...)`
- `paint.polyline(...)`
- `paint.polygon(...)`
- `paint.circle(...)`
- `paint.arc(...)`
- `paint.bezier(...)`
- `paint.mesh(...)`
- `paint.image(...)`

Mesh helpers:
- `paint.vertex(x, y, u?, v?)`
- `paint.mesh_triangles`
- `paint.mesh_strip`
- `paint.mesh_fan`

Love backend notes:
- `ui.runtime_love` supports all primitives above
- `paint.image(...)` / textured `paint.mesh(...)` resolve images through `ui.runtime_love.new { resolve_image = fn }` or `images = { [id.value] = image }`

Examples:
- `love examples/ui_paint_demo`
- `love examples/ui_love_demo`
- `love examples/ui_studio_demo`
