# libui Widget and App Authoring Guide

This guide explains how to build good applications on top of `uilib`.

The short version is:

> Treat `uilib` as a typed layout and paint compiler.
> Keep app meaning in app-specific ASDL.
> Project app state into explicit view nouns.
> Build small pure `UI.Node` trees from those view nouns.
> Keep per-frame runtime visuals out of the static widget tree.

If you follow that pattern, the code stays readable, structural identity stays useful, and recompilation happens only when the structure actually changes.

---

## 1. What `uilib` is for

`uilib` is not your app architecture.
It is the UI compilation layer.

Its core shape is:

```text
UI.Node   -- authored recursive widget tree
  ↓ measure / compile
View.Cmd[] -- flat executable command array
```

That means `uilib` is best used for:

- layout
- static paint structure
- hit surfaces via tags
- flattening a widget tree into efficient commands

It is **not** the right place to put all of your app semantics.
Those should live in your own app-specific types.

---

## 2. The main recommended architecture

For a real app, use this split:

```text
App.State + App.Viewport
  ↓ project
AppView.*              -- typed projected view spine
  ↓ build widgets
UI.Node                -- widget tree
  ↓ compile / assemble
View.Cmd[]             -- static command image

App.State + App.Viewport
  ↓ project
AppPaint.*             -- optional app-specific dynamic paint facet
  ↓ lower
ui.Paint.Node          -- generic paint tree
  ↓ compile
Paint.Cmd[]            -- flat runtime paint plan

AppRuntime.*           -- live payload updated every frame
  ↓ build runtime env
{ numbers, texts, colors }
```

At draw time:

```text
ui.paint(static_cmds)
ui.paint_custom(paint_cmds, runtime_env)
```

This is the main pattern for substantial apps.

See `examples/ui7/main.lua` for a full example.

---

## 3. The most important rule

## Project first, render second

Do **not** build a large widget tree directly from raw source state.

Prefer:

```text
App.State -> AppView.TrackRowView -> UI.Node
```

instead of:

```text
App.State -> giant function full of business logic -> UI.Node
```

A good `UI.Node` tree should mostly express:

- layout
- text
- colours
- tags
- clipping
- transforms
- composition

It should **not** be where your app's domain logic becomes hard to see.

---

## 4. Layer responsibilities

## 4.1 `App.*` — source truth

This is your real app state.
Examples:

- project data
- selection
- session state
- viewport
- document contents
- transport state

This layer should be the thing you save, load, diff, undo, and test.

---

## 4.2 `AppView.*` — shared projected spine

This is the main authoring layer for UI-facing semantics.

It should answer questions like:

- which panel is visible?
- which track is selected?
- what row index is this track?
- what clips are in view?
- what labels and numbers should the inspector show?

Typical view nouns:

- `TrackRowView`
- `ClipView`
- `TransportPanelView`
- `InspectorView`
- `HeaderView`

A good `AppView` layer preserves identity and makes UI code obvious.

---

## 4.3 `UI.Node` — widget tree

This is where you express layout and static visuals.

Use `UI.Node` for:

- `row` / `col` / `flex`
- `stack`
- `pad`
- `clip`
- `transform`
- `sized`
- `rect`
- `text`
- `spacer`

A good widget tree is made from small pure functions.

---

## 4.4 `AppPaint.*` and `AppRuntime.*` — live dynamic visuals

If something changes every frame, do **not** make it part of your structural widget tree unless you truly want recompilation every frame.

Examples:

- playhead position
- animated meters
- transport time readout
- flashing indicators
- waveform cursors
- rapidly changing diagnostics

Instead:

- keep static structure in `UI.Node`
- keep dynamic payload in `AppRuntime.*`
- keep dynamic drawing in either:
  - app-specific `AppPaint.*` projected into generic `ui.Paint.Node`, or
  - generic `ui.Paint.Node` directly if no extra app paint facet is needed

Then compile with `ui.compile_paint(...)` and execute with `ui.paint_custom(...)`.

That is the preferred pattern for nontrivial apps.

---

## 5. The main authoring style for widgets

The default style is:

1. define app-specific view types
2. write one small function per UI noun
3. each function returns a `UI.Node`
4. compose those functions into larger widgets

Example:

```lua
local ui = require("uilib")
local box, px, text_style = ui.box, ui.px, ui.text_style
local row, stack, rect, text, transform =
    ui.row, ui.stack, ui.rect, ui.text, ui.transform

local function label_style(color)
    return text_style { font_id = 2, color = ui.solid(color) }
end

local function mute_button_ui(is_on)
    return stack({
        rect("track:mute", ui.solid(is_on and 0xffcc3333 or 0xff30363d),
            box { w = px(24), h = px(20) }),
        text("track:mute:label", "M", label_style(0xffffffff),
            box { w = px(24), h = px(20) }),
    })
end

local function track_row_ui(view)
    return stack({
        rect("track:" .. view.track_id, ui.solid(view.is_selected and 0xff1f2937 or 0xff161b22),
            box { w = px(260), h = px(48) }),
        transform(12, 14,
            text("track:" .. view.track_id .. ":name", view.track_name,
                label_style(0xffffffff))),
        transform(120, 14, mute_button_ui(view.mute)),
    })
end
```

This is the main authoring pattern.

---

## 6. What a good widget function looks like

A good widget function is:

- pure
- small
- named after a UI noun
- driven by a typed view object
- mostly free of business logic
- explicit about sizing and tags

Good:

```lua
local function transport_panel_ui(view) ... end
local function clip_inspector_ui(view) ... end
local function track_row_ui(view) ... end
```

Less good:

```lua
local function build_everything(app_state, many_flags, random_tables, ...) ... end
```

If a widget function is hard to understand, the fix is often to improve the `AppView` layer, not to add more conditionals to the widget tree.

---

## 7. Keep widgets tied to real nouns

A useful test is:

> Can I point at this function and name the thing on screen that it represents?

Good widget names:

- `track_row_ui`
- `arrangement_header_ui`
- `transport_panel_ui`
- `scrollbar_ui`
- `meter_background_ui`

Bad widget names:

- `build_center`
- `build_part2`
- `make_left_stuff`

If the names are vague, the structure usually is too.

---

## 8. Use `AppView` to absorb app logic

Your projection step should resolve app questions before widget construction.

For example, this is the right kind of work for projection:

- selectedness
- panel choice
- visible ordering
- track index lookup
- clip-to-row mapping
- text formatting that is part of view meaning
- deciding which inspector variant to show

Then widget code becomes straightforward:

```lua
if view.is_selected then ... end
```

instead of:

```lua
if state.session.selection.kind == ... and find_track(...) and maybe_clip(...) then ... end
```

Projection makes the widget tree simple.

---

## 9. Keep `UI.Node` trees structural, not clever

Prefer direct composition:

```lua
stack({
    rect(...),
    text(...),
    transform(..., button_ui(...)),
})
```

Avoid inventing unnecessary intermediate recursive trees between `AppView` and `View.Cmd[]`.

The compiler pattern in this repo strongly prefers:

- passes over one real tree
- explicit artifact layers only when they are justified
- flattening once meaning is resolved

So do not create extra layers just to feel abstract.
Create a new layer only if it names a real artifact or a real semantic boundary.

---

## 10. When to use `row` / `col` vs `stack`

### Use `row` / `col` / `flex` for layout relationships

Use these when children participate in measured layout.

Examples:

- toolbar items
- sidebar sections
- forms
- button rows
- vertically stacked panels

### Use `stack` for overlaying in one frame

Use `stack` when children share the same frame and simply paint on top of one another.

Examples:

- button background + label
- card background + border + icon + title
- clip rect + clip text
- row background + decorations

A common good pattern is:

- `row`/`col` for coarse layout
- `stack` inside leaf widgets for layered visuals

---

## 11. Use `transform` and `clip` deliberately

### `transform`
Use it when the child is conceptually the same widget, just offset.

Examples:

- place a label inside a row
- place a knob marker within a slider
- place a clip at its beat position

### `clip`
Use it when containment is a real visible rule.

Examples:

- scroll area
- panel viewport
- arrangement lane region
- text or content that must not bleed out

Do not wrap everything in `clip` by default.
Clipping is a real semantic boundary.

---

## 12. Stable tags are how hits stay sane

`uilib` hit testing works through tags on compiled commands.

So use stable, meaningful tags.

Good:

```lua
"track:12"
"track:12:mute"
"clip:44"
"transport:play"
```

Less good:

```lua
"button"
"x1"
"tmp42"
```

A good tag usually includes:

- widget noun
- entity identity if relevant
- subpart if relevant

That makes click handling simple and readable.

---

## 13. How to structure hit handling

Prefer this pattern:

1. build stable tags in widgets
2. use `ui.hit(cmds, mx, my)`
3. decode the tag in one event-handling layer
4. apply app updates there

Example:

```lua
local tag = ui.hit(static_cmds, mx, my)

if tag == "transport:play" then
    toggle_play()
    return
end

local clip_id = tonumber(tag:match("^clip:(%d+)$"))
if clip_id then
    select_clip(clip_id)
    return
end
```

This keeps input policy outside the widget tree.

---

## 14. Prefer small reusable leaf helpers

Common leaf helpers are worth extracting:

- `button_ui(...)`
- `label_ui(...)`
- `value_row_ui(...)`
- `slider_background_ui(...)`
- `panel_frame_ui(...)`

These should stay generic enough to reuse within your app, but not so generic that their meaning disappears.

Good reuse is local and concrete.
Bad reuse usually means a fake abstraction.

---

## 15. Fragments and plans: when to use them

`uilib` provides:

- `ui.fragment(node, w, h)`
- `ui.plan(ops)`
- `ui.place_fragment(...)`
- `ui.push_clip_plan(...)`
- `ui.pop_clip_plan(...)`
- `ui.push_transform_plan(...)`
- `ui.pop_transform_plan(...)`

Use these when there is a **real artifact boundary**.

That usually means:

- independently compiled pieces
- independently reusable paint pieces
- flat scene assembly
- a large app where preserving identity at artifact granularity matters

Good uses:

- track row fragment
- clip fragment
- inspector fragment
- transport panel fragment
- assembling a whole screen from compiled pieces

Less good use:

- every tiny helper becoming its own fragment for no reason

If there is no real artifact boundary, just author `UI.Node` directly.

---

## 16. Static vs dynamic: the central split

This is the most important app-level decision.

### Put it in static `UI.Node` when:

- it changes only when source/view structure changes
- it is part of layout
- it affects hits structurally
- it is normal label/rect content derived from source state

Examples:

- panel backgrounds
- clip labels
- row names
- button shells
- inspector layout
- selection highlighting

### Put it in runtime paint when:

- it changes every frame or frequently
- it should not trigger recompilation
- it is better expressed as a payload-driven overlay

Examples:

- playhead position
- live meter fills
- transport time text
- animation overlays
- temporary diagnostics

For substantial apps, this split is what keeps the system fast and conceptually clean.

---

## 17. The preferred runtime pattern

For dynamic visuals, use an app-specific runtime payload.

Example shape:

```text
AppRuntime.Payload = (
    playhead_x,
    transport_time_text,
    transport_beat_text,
    meter_levels
)
```

Then update that payload during your app's update step (for example, `app.update(dt)`).

Do not rebuild the structural widget tree just because time advanced.

That is the key architectural win.

---

## 18. A minimal app shape

A good app often looks like this:

```lua
local function project_root_view(app_state, viewport)
    ...
    return RootView(...)
end

local function build_root_ui(root_view)
    return stack({
        build_left_panel_ui(root_view.left_panel),
        build_main_panel_ui(root_view.main_panel),
        build_right_panel_ui(root_view.right_panel),
    })
end

local function recompile_static()
    local root_view = project_root_view(app_state, viewport)
    static_cmds = ui.compile(build_root_ui(root_view), viewport.w, viewport.h)
end

function app.update(dt)
    runtime_payload = step_runtime(runtime_payload, dt)
end

function app.draw(renderer)
    ui.paint(static_cmds, { backend = renderer })
    ui.paint_custom(runtime_cmds, runtime_env, { backend = renderer })
end
```

For larger apps, replace `build_root_ui(...)` with fragment/plan assembly.

---

## 19. When you should define app-specific ASDL view types

Define app-specific view types when:

- the screen has real semantic parts
- the same source entity appears in multiple places
- you want explicit inspector/panel/row/clip nouns
- you care about preserving identity cleanly
- the UI is large enough that a raw table view-model would become vague

For tiny demos, you can often skip this.
For serious apps, you usually should not.

---

## 20. Identity and preservation

One of the biggest benefits of ASDL-first design is stable structural identity.

To get the most from it:

- keep source entities explicit
- preserve real IDs in view nodes
- do not throw identity away during projection
- do not merge unrelated concerns into one giant node

If one track row changes, you want that change to stay local conceptually.
That is much easier when your view spine has real nouns like `TrackRowView(track_id, ...)`.

---

## 21. Sizing advice

Be explicit about important sizes.

Useful patterns:

```lua
box { w = px(260), h = px(48) }
box { w = ui.CONTENT, h = px(20) }
box { w = ui.percent(1.0), h = px(40) }
```

Good practice:

- hard-code real widget sizes when the design wants fixed sizes
- use content sizing for text-sized leaves
- use flex containers for larger flow relationships
- keep size choices local and readable

If sizing feels mysterious, make it more explicit.

---

## 22. Text authoring advice

Prefer shared style helpers:

```lua
local function label_style(color)
    return ui.text_style { font_id = 2, color = ui.solid(color) }
end
```

Then use them consistently.

For text:

- use nowrap when clipping/ellipsis is not needed
- use wrap and overflow only where the design truly needs it
- keep text formatting in projection if it is semantic
- keep font/color/layout choices in widget code if they are presentational

A useful split is:

- projection decides **what string** should appear
- widget code decides **how it is laid out and styled**

---

## 23. What not to do

### Do not put business logic deep inside widget helpers
Bad:

```lua
local function row_ui(state, project, selection, viewport, transport, cache, ...)
```

### Do not rebuild the whole UI every frame for time-only changes
Bad if avoidable:

```lua
function app.update(dt)
    app_state.time = app_state.time + dt
    recompile_static()
end
```

### Do not invent fake intermediate trees
If a layer is not a real semantic layer or a real artifact layer, it is probably unnecessary.

### Do not use vague raw tables everywhere
Typed app view nodes are usually better than unstructured ad-hoc tables for large apps.

### Do not rely on app-specific dynamic concepts in core `uilib`
For serious apps, prefer app-level `AppPaint` and `AppRuntime` layers, or project directly to generic `ui.Paint`, rather than stuffing dynamic app semantics into core widget kinds.

---

## 24. Practical checklist for a new widget

When writing a new widget, ask:

1. What real screen noun is this?
2. What app-specific view type should feed it?
3. Is this a leaf widget or a composed widget?
4. Does it need stable hit tags?
5. Is any part of it changing every frame?
6. If yes, should that part move to runtime paint?
7. Is a fragment boundary justified here?
8. Are the sizes and transforms obvious from the code?

If those answers are clear, the widget is usually on the right path.

---

## 25. Practical checklist for a new app screen

When designing a screen, ask:

1. What is source truth?
2. What are the screen nouns?
3. Which of those nouns belong in `AppView`?
4. Which parts are static structure vs dynamic runtime visuals?
5. Do I need one widget tree, or fragments plus a flat plan?
6. What tags will drive hit handling?
7. What state changes should force recompilation?
8. What state changes should only update runtime payload?

That last distinction is usually the most important one.

---

## 26. Recommended default pattern

If you do not know what to do, use this default:

### Small app

```text
App.State
  -> project view tables / ASDL view nodes
  -> build one UI.Node tree
  -> ui.compile(...)
  -> ui.paint(...)
```

### Medium or large app

```text
App.State + Viewport
  -> AppView
  -> fragments / plan
  -> static View.Cmd[]

App.State + Viewport
  -> AppPaint (optional)
  -> ui.Paint.Node
  -> Paint.Cmd[]

AppRuntime.Payload
  -> runtime env { numbers, texts, colors }
  -> ui.paint_custom(...)
```

That default will take you a long way.

---

## 27. Final rule of thumb

A good libui app usually has this feel:

- app types are explicit
- projection is easy to read
- widget functions are small and pure
- tags are stable
- static paint is compiled once per structural change
- dynamic visuals update through runtime payload
- there are no mysterious extra tree layers

If your code has that shape, you are probably using `uilib` well.

---

## 28. Where to look next

- `examples/ui7/main.lua` — full app example with source/view/paint/runtime split
- `docs/COMPILER_PATTERN.md` — broader design doctrine
- `docs/PVM_GUIDE.md` — pvm/uvm methodology and layering discipline
