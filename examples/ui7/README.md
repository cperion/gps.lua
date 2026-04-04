# ui7 — SDL3 + OpenGL + Terra

`main.lua` contains the app logic and returns an app object.

`main.t` is the canonical launcher/runtime:
- SDL3 creates the window and drives events
- OpenGL renders directly
- SDL_ttf provides font measurement and text rasterization
- `uilib` paints through a backend interface, not through Love2D

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
