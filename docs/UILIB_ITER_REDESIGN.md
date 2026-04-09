# uilib immediate / iter redesign

Status: historical redesign note

This document describes the redesign that moved canonical `uilib` from the
older retained/compiled center toward the current immediate/session-based
execution model.

Public naming today:
- `require("uilib")` — canonical public entrypoint
- `require("uilib_iter")` — compatibility alias / implementation file name
- `require("uilib_im")` — compatibility shim to canonical `uilib`

Goal: replace retained compiled-widget execution with a data-driven immediate UI engine built around explicit `gen / param / state` traversal, while preserving the **full feature set** of current `uilib` / former `uilib2`:

- typed semantic data via ASDL
- full flex layout model
- DS themes / surfaces / pointer-phase packs
- text wrap / clip / ellipsis / line-height / line-limit
- transforms / clips / hit testing
- generic custom paint
- backend independence

The big change is architectural:

- **current**: author tree -> measure -> compile -> arrays of commands -> patch with runtime paint
- **new**: author param tree -> immediate reducers walk it each frame -> optional recording/debug arrays only when needed

---

## 1. Core model

The canonical model is:

- `param`: a pure UI description tree
- `state`: explicit local UI state (focus, hot, scroll, text edit buffers, widget-local registers)
- `gen`: the reducer / walker / interpreter

A single UI may have multiple reducers over the same param:

- measure / layout
- paint
- hit / pick
- focus / nav
- debug / collect

So the engine is not "single pass only"; it is **one param, multiple explicit reducers**.

---

## 2. What stays from current uilib

These concepts stay, with the same semantics:

### 2.1 Design system

Keep `ui.ds` largely unchanged:

- `ds.theme(...)`
- `ds.surface(...)`
- `ds.paint_rule(...)`
- `ds.struct_rule(...)`
- `ds.resolve(...)`
- pointer/focus/flag selectors
- `DS.ColorPack`, `DS.NumPack`, `DS.Style`

Theme/style resolution remains data-driven and cached.

### 2.2 Text engine

Keep the current text shaping behavior and caches:

- width / height / baseline measurement
- nowrap / word wrap / char wrap
- visible / clip / ellipsis overflow
- line height / line limit
- UTF-8 safe wrapping and truncation

Text shaping and raster caching remain the main performance caches.

### 2.3 Layout vocabulary

Keep the layout feature set:

- row / col / flex
- pad / stack / clip / transform / sized
- rect / text / spacer
- basis / grow / shrink / margins
- justify / align / align_content
- percent / px / content / min / max

### 2.4 Generic paint

Keep generic custom paint as a first-class feature:

- fill rect
- stroke rect
- line
- text
- clip / translate
- runtime refs (`num_ref`, `text_ref`, `color_ref`)

The difference is that custom paint is executed as part of immediate reducers, not as a separate retained compiled plan.

---

## 3. What changes

### 3.1 No compiled command arrays as the center of the architecture

Compiled arrays may still exist for:

- debugging
- recording
- profiling
- backend capture
- optional specialization later

But they are **not** the canonical authored/runtime artifact.

### 3.2 Static vs dynamic is no longer an architectural split

Instead of forcing authors to decide what gets compiled and what becomes runtime paint, the engine simply walks current param and state every frame.

Only expensive primitives are cached:

- shaped text
- font metrics
- text textures / glyph cache
- optional variable-height list metrics

### 3.3 Child expansion becomes iterator-native

Dynamic child sets can be driven by `iter` pipelines directly.

This gives immediate support for:

- filtering
- mapping
- flat expansion
- grouping
- virtualized windows (`skip` / `take`)
- enumerated rows
- section headers + rows via `group_by(...):flatmap(...)`

---

## 4. Module shape

Historically, the redesign landed first in:

- `uilib_iter.lua`

That implementation is now the engine behind canonical `uilib`.

---

## 5. Public API target

## 5.1 Constructors and constants

These should stay source-compatible where possible.

```lua
local ui = require("uilib")

ui.AUTO
ui.CONTENT

ui.px(n)
ui.percent(r)
ui.min_px(n)
ui.max_px(n)
ui.basis_px(n)
ui.basis_percent(r)
ui.line_height_px(n)
ui.line_height_scale(s)
ui.max_lines(n)

ui.insets(l, t, r, b)
ui.margin(l, t, r, b)
ui.box(opts)
ui.text_style(opts)
ui.frame(x, y, w, h)
ui.constraint(w, h)
ui.exact(n)
ui.at_most(n)
```

Layout / text constants should remain available:

```lua
ui.AXIS_ROW
ui.AXIS_ROW_REVERSE
ui.AXIS_COL
ui.AXIS_COL_REVERSE

ui.WRAP_NO
ui.WRAP
ui.WRAP_REVERSE

ui.MAIN_START
ui.MAIN_END
ui.MAIN_CENTER
ui.MAIN_SPACE_BETWEEN
ui.MAIN_SPACE_AROUND
ui.MAIN_SPACE_EVENLY

ui.CROSS_AUTO
ui.CROSS_START
ui.CROSS_END
ui.CROSS_CENTER
ui.CROSS_STRETCH
ui.CROSS_BASELINE

ui.CONTENT_START
ui.CONTENT_END
ui.CONTENT_CENTER
ui.CONTENT_STRETCH
ui.CONTENT_SPACE_BETWEEN
ui.CONTENT_SPACE_AROUND
ui.CONTENT_SPACE_EVENLY

ui.TEXT_NOWRAP
ui.TEXT_WORDWRAP
ui.TEXT_CHARWRAP

ui.TEXT_START
ui.TEXT_CENTER
ui.TEXT_END
ui.TEXT_JUSTIFY

ui.OVERFLOW_VISIBLE
ui.OVERFLOW_CLIP
ui.OVERFLOW_ELLIPSIS

ui.LINEHEIGHT_AUTO
ui.UNLIMITED_LINES
```

---

## 5.2 Node builders

The primary authoring layer remains pure data.

```lua
ui.item(node, opts)
ui.grow(factor, node, opts)

ui.row(gap, children, opts)
ui.col(gap, children, opts)
ui.flex(opts)

ui.pad(insets, child, box)
ui.stack(children, box)
ui.clip(child, box)
ui.transform(tx, ty, child, box)
ui.sized(box, child)
ui.rect(tag, fill, box)
ui.text(tag, text, style, box)
ui.spacer(box)
```

### Child sources

Any child slot that currently accepts `Node[]` should also accept:

- Lua arrays of nodes
- `iter` pipelines that yield nodes
- helper wrappers such as `ui.each(...)` and `ui.when(...)`

Convenience helpers:

```lua
ui.when(cond, node)
ui.unless(cond, node)
ui.each(source, mapfn, opts)
ui.concat(children_or_pipelines)
ui.key(id, node)
```

#### Notes

- `ui.key(id, node)` anchors local widget state and identity.
- `ui.each(...)` is the standard dynamic-list bridge to `iter`.
- `ui.concat(...)` flattens arrays / iter pipelines / conditional nodes into a child source.

---

## 5.3 Generic paint builders

Keep the current generic paint builders, but execute them immediately via reducers.

```lua
ui.num_ref(name)
ui.text_ref(name)
ui.color_ref(name)

ui.paint_group(children)
ui.paint_clip(x, y, w, h, child)
ui.paint_transform(tx, ty, child)
ui.paint_rect(tag, x, y, w, h, color)
ui.paint_stroke(tag, x, y, w, h, thickness, color)
ui.paint_line(tag, x1, y1, x2, y2, thickness, color)
ui.paint_text(tag, x, y, w, h, style, text, color)
```

And a bridge node:

```lua
ui.custom(paint_node, runtime)
```

So custom paint becomes a normal subtree inside the immediate UI, not a separate architecture.

---

## 5.4 Reducers

These become the primary execution API.

### Measure

```lua
local m = ui.measure(node, constraint, opts)
```

Returns facts equivalent to current `Facts.Measure`.

### Paint

```lua
ui.draw(node, frame, {
    backend = backend,
    state = ui_state,
    env = env,
    hot = hot,
    focus = focus,
})
```

This is the canonical draw entrypoint for UI nodes.

### Pick / hit

```lua
local tag = ui.hit(node, frame, mx, my, {
    state = ui_state,
    env = env,
})
```

### Generic paint draw

```lua
ui.draw_paint(paint_node, runtime, {
    backend = backend,
    state = ui_state,
    hot = hot,
})
```

### Collect / record (debugging only)

```lua
local ops = ui.collect(node, frame, opts)
local paint_ops = ui.collect_paint(paint_node, runtime, opts)
```

These replace the old compile/assemble mindset. They are optional materializations, not the core execution path.

### Full frame convenience

```lua
local next_state, messages = ui.step_frame(node, {
    frame = ui.frame(0, 0, w, h),
    backend = backend,
    input = input,
    state = ui_state,
    env = env,
})
```

This should orchestrate:

- focus / hover / pressed tracking
- interaction routing
- drawing
- message emission

Apps may still use lower-level reducers directly.

---

## 5.5 State API

Explicit state is a first-class value.

```lua
local st = ui.state()
local st2 = ui.clone_state(st)
local st3 = ui.restore_state(snapshot)
```

State goals:

- snapshot-friendly
- serializable
- forkable
- deterministic
- keyed by stable semantic IDs when available

State contents should be plain data:

- hot / active / focus ids
- widget-local state table
- scroll positions
- text edit buffers
- cursor/selection info
- nav/focus order registers

### Keying model

Widget-local state should be keyed by:

1. explicit `ui.key(id, node)` when present
2. stable semantic ids from ASDL/domain data when provided by widgets
3. structural path fallback for anonymous nodes

---

## 6. Internal representation

## 6.1 Param tree

The param tree may still use ASDL for typed nodes, but execution should treat it as plain data.

Recommended approach:

- keep ASDL for DS / Facts / Paint / semantic view types
- UI param nodes may remain typed ASDL nodes **or** move to compact tagged arrays
- child expansion uses `iter` triplets directly where useful

The important part is not the exact storage format; it is that the tree is explicit data and reducers walk it directly.

## 6.2 Optional op IR

A compact op IR remains useful for debug/record:

```text
PushClip / PopClip
PushTx / PopTx
FillRect
StrokeRect
Line
Text
HitBox
CustomPaint
```

But this IR is a reducer output, not the canonical authored artifact.

---

## 7. Iter integration details

## 7.1 Direct child pipelines

Examples:

```lua
ui.col(0,
    iter.from(items)
        :filter(is_visible)
        :map(render_row))
```

```lua
ui.stack(ui.concat({
    ui.when(show_header, header_node),
    iter.from(tracks):map(track_row),
    footer_node,
}))
```

## 7.2 Virtual lists

Fixed-height rows:

```lua
local rows = iter.from(items)
    :skip(scroll_index)
    :take(visible_count)
    :map(render_row)
```

Variable-height lists need a measurement prefix cache, but the same model still applies.

## 7.3 Grouped sections

```lua
iter.from(contacts)
    :group_by(first_letter)
    :flatmap(function(group)
        return iter.once(section_header(group.key))
            :chain(iter.from(group.items):map(contact_row))
    end)
```

---

## 8. Performance model

The performance strategy is:

### Cache these

- DS surface/style resolution
- text measurement / shaping / wrapping
- glyph / text textures
- optional variable-height list metrics

### Do not make these the primary cache boundary

- whole UI compile products
- static/dynamic partitions authored by hand

The engine should be fast because reducers are simple and local, not because the whole UI is compiled into a second retained structure.

---

## 9. Migration plan

The original migration plan is kept here as historical context.

## Phase 1 — parallel module

Add `uilib_iter.lua` alongside current `uilib`.

Initial goals:

- preserve DS API
- preserve constructor API
- add immediate reducers
- support iter child sources
- reuse current text engine and backend abstraction where possible

## Phase 2 — ui7 port

Port `examples/ui7` to the new module.

Targets:

- no static/dynamic architectural split
- dynamic rows / sliders / meters are just current param + current state
- list rendering uses iter child sources

## Phase 3 — completeness

Add the full set of:

- focus/nav
- text edit widgets
- scroll areas
- keyed widget-local state
- custom paint embedding

## Phase 4 — canonical promotion

This phase has effectively happened:
- canonical public entrypoint is now `uilib`
- `uilib_iter` remains as a compatibility alias / implementation file name
- `ui7` runs on canonical `uilib`

---

## 10. Parity checklist

The redesign is not considered complete until it covers all current `uilib` capability:

- [ ] full DS API
- [ ] full box/flex sizing model
- [ ] text wrap/clip/ellipsis parity
- [ ] transforms and clipping
- [ ] hit testing parity
- [ ] generic paint parity
- [ ] backend abstraction parity
- [ ] diagnostic/reporting hooks
- [ ] complete examples ported

---

## 11. Recommended first implementation scope

Implement in this order:

1. `uilib_iter.lua` module shell
2. constructor parity layer
3. child-source normalization (`array | iter | when | each | concat`)
4. immediate measure reducer
5. immediate draw reducer
6. immediate hit reducer
7. generic paint bridge
8. state store + `ui.key`
9. `ui7` port

This gives a usable complete core without reintroducing the retained compile architecture.
