# ui_multiwindow_demo

A real SDL3 multi-window notes workspace built on `ui.session`, authored with `ui.build` + `ui.tw`, and using the SDL3 text-field overlay only at the actual text-edit seam.

The demo now runs in dirty-redraw mode and uses timed session redraw scheduling for caret blink instead of relying on per-frame `window_update` polling.

## Run

```bash
luajit examples/ui_multiwindow_demo/main.lua
```

Headless smoke test:

```bash
SDL_VIDEODRIVER=dummy AUTO_QUIT_MS=80 luajit examples/ui_multiwindow_demo/main.lua
```

## What it does

This is no longer just a styled shell.

It is a small notes application with shared project state and explicit semantic drag state:

- a **browser window** for:
  - selecting notes
  - creating notes
  - deleting the selected note
  - drag-and-drop reordering of notes
  - previewing the selected note
- an **editor window** for:
  - editing the selected note title
  - editing the selected note body
  - seeing note stats update live
- both windows are attached to the same in-memory project state
- both windows are SDL3 **resizable** windows
- resize is handled without baking live viewport pixels into the authored root tree; the demo uses structural `w_full`/`h_full` roots, and the width-sensitive ui phases keep only the latest arg-keyed result per node instead of accumulating every historical window size
- the demo now splits **structural project identity** from **volatile note text**: note order/selection live in interned `Project`, while editable title/body text lives in non-interned `Docs`; authored dynamic text uses `Auth.TextRef` + explicit `Content.Store` so live edit strings do not get interned into the recursive ui tree
- selecting a note in the browser immediately changes what the editor window edits
- editing in the editor updates the local editor window immediately, while browser/shared previews update on the explicit draft-commit seam (idle or blur)

## Architecture

- **Domain model**: ASDL types in `demo_asdl.lua`
- **Reducer / state transitions**: `demo_apply.lua`
- **Authored UI + recipes**: `widgets.lua`
- **SDL3 session/window orchestration**: `app.lua`

`MultiNotes.State` now carries:
- the shared structural `Project`
- the volatile `Docs` payload for editable note text
- semantic drag preview state (`DragNote`, `InsertAt`)

So the browser's drag affordances are no longer ad hoc host-local state; they are reducer-visible app state.

The important split is:

- application chrome, panes, lists, buttons, layout: **authored UI**
- list reordering surfaces: canonical `ui.recipes.reorderable_list`
- browser scrolling + scrollbar overlay: canonical `ui.recipes.scroll_view`, using `reserve_track_space = "auto"`, `sync_visibility(...)`, draggable thumbs, and keyboard scrolling so gutter space appears only when a scrollbar is actually present
- editor body uses `ui.recipes.edit_surface` as a pure authored edit shell; wheel scrolling, PageUp/PageDown, caret visibility, and scrollbar geometry are derived from the live `ui.text_field_view` result instead of from transparent authored ghost text
- editor title uses the same dynamic edit-surface seam horizontally, so long unwrapped titles scroll without wrapping and keep the caret visible without embedding the live title string in the UI tree
- drag mechanics: generic `ui.interact`
- drag meaning: explicit `MultiNotes.State.drag` + `MultiNotes.State.drop`
- title/body text editing: canonical `ui.recipes.edit_surface` built on authored `EditTarget` regions plus `ui.text_field`

## Files

- `examples/ui_multiwindow_demo/main.lua` — launcher
- `examples/ui_multiwindow_demo/app.lua` — session + window orchestration
- `examples/ui_multiwindow_demo/demo_asdl.lua` — app/domain types
- `examples/ui_multiwindow_demo/demo_apply.lua` — app reducer
- `examples/ui_multiwindow_demo/widgets.lua` — authored UI
