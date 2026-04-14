# ui/demo

Love2D mock demo for the fresh UI stack.

This version is a **Bitwig-style DAW mock UI** with the compiler idea tucked inside the shell:

- title bar + transport / mode toolbar
- left detail rail
- launcher / track list panel
- center arrangement timeline
- right project / inspector panel
- bottom device chain editor
- bottom project remotes panel
- status bar

The demo app/domain is modeled with ASDL in `ui/demo/asdl.lua`.

It now has explicit layers:
- DAW project/domain ASDL
- demo widget/view ASDL (`DemoView`)
- `ui/demo/lower.lua` for `DemoView -> SemUI`
- generic `ui.lower` for `SemUI -> UI`
- richer app widgets in `DemoView` for launcher rows, launcher buttons/slots, arrangement track headers/clips, and inspector controls
- custom draw for audio-heavy surfaces like arrangement and the device editor

## Run

From the repo root:

```bash
love ui/demo
```

## What it demonstrates

- `SemUI -> UI` lowering via `ui.lower`
- measurement-driven reducers
- hit testing via `ui.hit`
- reducer-wired session/frame stepping via `ui.session`
- drawing via `ui.draw`
- Love2D backend adapter
- reducer-driven keyboard focus navigation + activation
- a runtime-driven mock DAW dashboard with bounded structural identity
- demo/domain state modeled with ASDL (`ui/demo/asdl.lua`)
- an explicit ASDL widget/view layer between project data and generic UI
- the split between structural recompiles and live state tweaks

## Controls

- launcher buttons (`M/S/R`) are real widgets and clip slots are real launch widgets
- `TAB` / `SHIFT+TAB` — move keyboard focus
- `ENTER` / `SPACE` — activate the focused item
- `1` / `2` / `3` — switch Arrange / Routing / Machine overlays
- `P` — play / stop transport
- `G` — simulate a **structural edit** (rebuild / recompile)
- `K` — simulate a **live tweak** (state mutation only)
- `LEFT` / `RIGHT` — move selected compiler phase
- `UP` / `DOWN` — move selected track
- `ESC` — quit
