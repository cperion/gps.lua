# ui/demo

Love2D mock demo for the fresh UI stack.

This version is a **DAW-style mock UI** with the compiler idea tucked inside the shell:

- top transport / mode bar
- left browser / project list
- center arrangement timeline
- bottom device chain / callback strip
- right mixer
- status bar and callback log

The demo app/domain itself is also modeled with ASDL in `ui/demo/asdl.lua`.

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
- the split between structural recompiles and live state tweaks

## Controls

- `TAB` / `SHIFT+TAB` — move keyboard focus
- `ENTER` / `SPACE` — activate the focused item
- `1` / `2` / `3` — switch Arrange / Routing / Machine overlays
- `P` — play / stop transport
- `G` — simulate a **structural edit** (rebuild / recompile)
- `K` — simulate a **live tweak** (state mutation only)
- `LEFT` / `RIGHT` — move selected compiler phase
- `UP` / `DOWN` — move selected track
- `ESC` — quit
