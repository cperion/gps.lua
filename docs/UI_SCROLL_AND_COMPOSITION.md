# ui/ architecture note: structural scroll and composition patterns

This note captures the design lesson from the first serious shell/showcase pressure-test of the new `ui/` stack.

The problem was not paint, styling, or Love2D polish. The real issue was shell composition:

- browser/sidebar panels
- launcher/editor regions
- inspector rails
- docked bottom panes
- header + scroll-body panels
- dense workstation-style surfaces

Those patterns exposed one important design smell:

> scrolling currently lives too much in style (`overflow_*`) and not enough in structure.

And a second one:

> app-shell composition is expressible with raw `Auth.Box` + tokens, but too easy to get wrong.

This document proposes the next architectural direction.

---

## 1. What already feels correct

These parts of the architecture still look right:

- `Auth -> Layout -> View.Op* -> runtime`
- streamed relative render ops
- typed interaction reports (`Interact.Report`)
- typed interaction reducer loop (`Interact.Raw/Event/Model`)
- shared planners in `ui.plan`
- explicit text backend cache dimension (`text_system`)
- explicit interaction wrappers (`WithInput(id, role, child)`)
- typed paint pipeline (`Auth.Paint -> Layout.Paint -> View.KPaint`)

The shell problems did **not** invalidate the core iterator-first compiler architecture.

---

## 2. The actual smell

Today, scroll behavior is inferred from style:

- `overflow_x` / `overflow_y` live in `Style`, then in `Layout.BoxStyle`
- `ui.plan.is_scroll_container(box)` decides whether a node is scrollable
- `ui.render` emits `KPushScroll/KPopScroll` for any node whose box has scroll-ish overflow
- `ui.runtime` reports scrollable hit regions from those ops
- `ui.interact` turns wheel input into `ScrollBy(id, dx, dy)` based on the runtime report

This works, but it conflates two different things:

1. **visual clipping policy**
2. **interactive scrolling behavior**

Those are related, but they are not the same concept.

We already learned this lesson once for input:

- plain ids were too weak
- `WithInput(id, role, child)` made input structural

Scrolling wants the same treatment.

---

## 3. Architectural claim

> Scrolling is behavioral structure, not just visual style.

A scroll region is not merely “a box whose overflow happens to scroll.”
It is a semantic viewport relationship:

- there is a **viewport**
- there is **content larger than the viewport on some axis**
- there is a **scroll state key**
- user wheel/trackpad input targets that viewport
- runtime translates content relative to viewport state
- clipping is part of the viewport execution contract

That is enough behavior that it should be structurally visible in ASDL.

---

## 4. Proposed model: structural scroll node

## 4.1 Auth layer

Add a structural authored node for scroll:

```text
Auth.Node +=
  Scroll(Core.Id id,
         Style.TokenList styles,
         Layout.Axis axis,
         Auth.Node child) unique
```

Or if two-axis scroll matters:

```text
ScrollAxis = ScrollX | ScrollY | ScrollBoth

Auth.Node +=
  Scroll(Core.Id id,
         Style.TokenList styles,
         ScrollAxis axis,
         Auth.Node child) unique
```

Meaning:

- `styles` describe the viewport box itself
- `id` is the stable interaction/runtime state key
- `axis` says which directions are allowed to scroll
- `child` is the full scrollable content tree

This is exactly analogous to `WithInput`: a behavioral wrapper around normal authored content.

---

## 4.2 Layout layer

Lower to a structural layout node:

```text
Layout.Node +=
  Scroll(Core.Id id,
         Layout.BoxStyle box,
         Layout.Axis axis,
         Layout.Node child) unique
```

The layout node means:

- measure a viewport box using `box`
- measure child content with scroll-aware constraints
- render viewport chrome and clip
- render child translated by runtime scroll offset
- report scroll hit region through runtime

---

## 4.3 View layer

`View.KPushScroll / KPopScroll` can stay.

The difference is not necessarily new view ops.
The difference is **where those ops come from**:

- today: inferred from `box.overflow_*`
- proposed: emitted only from structural `Layout.Scroll`

That keeps the op-stream runtime model intact.

---

## 5. Measure semantics for structural scroll

This is where the proposal becomes cleaner than style-driven overflow.

For a vertical scroll viewport:

- viewport width is constrained by parent width rules
- viewport height is constrained by parent height rules
- child content is measured with:
  - constrained width = viewport inner width
  - unconstrained/huge height on the scroll axis

For a horizontal scroll viewport:

- analogous, with width/height swapped by axis

For two-axis scroll:

- child may measure in large/unbounded space on both axes

The key point:

> the scroll container has one size; its content has another.

That distinction should be explicit in layout semantics, not smuggled through overflow style.

---

## 6. Render/runtime semantics

Rendering a `Layout.Scroll` node should be:

1. emit viewport visual ops
2. push clip for viewport inner rect
3. push scroll transform bound to `id` and axis
4. render child content
5. pop scroll
6. pop clip

Runtime behavior:

- report a scroll box for the viewport
- choose the hovered/targeted scroll viewport from structure
- apply runtime scroll offsets only inside the scroll scope

This matches the current runtime model well.

---

## 7. What happens to `overflow_*`?

This is the main migration question.

### Recommendation

Split the meanings.

- keep `overflow_hidden` / `overflow_visible` as visual clipping policy
- stop treating `overflow_scroll` / `overflow_auto` as the source of interactive scroll behavior inside `ui/`

Longer term, the cleanest result is probably:

- visual clip remains style-level
- interactive scroll becomes structural

There are two migration options.

### Option A — soft migration

Keep all style overflow tokens for compatibility, but change lowering so:

- `overflow_hidden` still affects clipping
- `overflow_scroll/auto` are discouraged in docs
- new code should use `Auth.Scroll`

### Option B — hard migration

Remove scroll-bearing overflow semantics from generic UI authoring guidance and reserve scrolling for structural nodes only.

My recommendation: **Option A first**.

---

## 8. Why this is better

Structural scroll improves:

### 8.1 Correctness

A node is scrollable because it is a scroll viewport, not because some style token happened to imply runtime behavior.

### 8.2 Composability

A panel can be described honestly:

- frame
- header
- `Scroll(id, child)` body

### 8.3 Interaction clarity

Wheel routing and scroll-state ownership are structurally obvious.

### 8.4 Cache clarity

The runtime scroll offset remains execution state, not a render cache key.
The scroll viewport itself remains part of the authored/layout structure.

### 8.5 Documentation clarity

We can teach one clean rule:

> clipping is style; scrolling is structure.

---

## 9. Second proposal: composition ASDL layer

Structural scroll alone does not solve the second problem:
raw shell composition is too easy to get wrong.

The stronger follow-up is an explicit `Compose` ASDL layer above `Auth`.

Shape:

```text
Compose.Node -> Auth.Node -> Layout.Node -> View.Op*
```

Example nouns:

- `Compose.Raw(Auth.Node child)`
- `Compose.Panel(...)`
- `Compose.ScrollPanel(...)`
- `Compose.HSplit(...)`
- `Compose.VSplit(...)`
- `Compose.Workbench(...)`

Preferred authoring surface:

```lua
local F = T:FastBuilders()

local node = F.Compose.ScrollPanel {
    id = b.id("browser"),
    scroll_id = b.id("browser-scroll"),
    axis = T.Style.ScrollY,
    header = F.Compose.Raw { child = header_ui },
    body = F.Compose.Raw { child = body_ui },
}
```

Then `ui.compose.phase(node)` lowers that composition noun into ordinary
`Auth.Node` structure using structural `Auth.Scroll(...)` where needed.

This is better than a plain Lua helper layer because the composition pattern:

- is visible as ASDL
- has identity
- is testable directly
- participates honestly in the architecture

---

## 10. Guidance: flow vs flex vs grid

The shell pressure-test also suggests these rules.

### Use `flow` for:
- local content stacks
- text and metadata groups
- small intrinsic blocks

### Use `flex` for:
- header/body panels
- editor/dock splits
- any region where one child should take the remaining space

### Use `grid` for:
- explicit 2D partitions
- shells with named/sidebar/inspector columns
- dense surfaces with known track semantics

### Do not use `flow` for:
- app shells
- panel bodies that must fill remainder
- docked workspaces

---

## 11. Guidance: dense work surfaces

Surfaces like launchers/timelines/track matrices are not generic content layouts.
They should be treated as semantic work surfaces.

For those surfaces, choose one explicit philosophy:

### Fixed-metric surface
- row/column metrics are deliberate semantic constants
- child cards are designed to fit those metrics
- clipping is expected

### Measured surface
- content drives row/column requirements
- planner solves tracks from content facts
- more expensive but more adaptive

The worst state is an implicit hybrid where card internals and grid metrics drift independently.

---

## 12. Recommended implementation order

1. **Add structural scroll node** to `Auth` and `Layout`
2. Update `lower`, `measure`, `render`, `runtime`, and `interact` to use it
3. Keep style overflow clip behavior, but stop deriving interactive scroll from it
4. Add a `Compose` ASDL layer plus `ui.compose` lowering for panel/shell composition
5. Update docs to teach:
   - scroll is structural
   - panel bodies use flex growth
   - shells should prefer flex/grid over flow

---

## 13. Summary

The architecture does not need more core primitives in `pvm`.
The main missing piece is better structural expression inside `ui/`:

- **scroll should be structural**
- **shell composition should have canonical helpers**
- **dense work surfaces should be explicitly semantic**

The core compiler model already fits these changes.
The next step is to make the authored/layout vocabulary express them directly.
