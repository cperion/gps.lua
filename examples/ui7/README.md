# ui7 — SDL3 + OpenGL + Terra

`main.lua` contains the app logic and returns an app object.

The demo now uses canonical `uilib` for immediate UI authoring.
(`uilib` now resolves to the immediate/session-based implementation formerly
introduced as `uilib_iter`.)

- the UI param tree is rebuilt directly from current state each frame
- no retained command compilation is used in the demo path
- sliders/meters/readouts update live without recompilation boundaries

`main.t` is the canonical launcher/runtime:
- SDL3 creates the window and drives events
- OpenGL renders directly
- SDL_ttf provides font measurement and text rasterization
- the backend is SDL3/GL, not Love2D

## Run

From the repo root:

```bash
../terra/build/bin/terra examples/ui7/main.t
```

Or if `terra` is on your `PATH`:

```bash
terra examples/ui7/main.t
```

## Headless smoke test

```bash
UI7_HEADLESS=1 ../terra/build/bin/terra examples/ui7/main.t
```

## Font override

If the default system font is missing, set:

```bash
UI7_FONT=/path/to/font.ttf ../terra/build/bin/terra examples/ui7/main.t
```
