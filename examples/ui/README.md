# Track Editor — mgps interactive demo

Run from the repository root:

```bash
love examples/ui
```

A three-panel DAW-style track editor demonstrating the current gps/mgps
architecture: ASDL → layout → View → separate ugps paint and hit-test
terminals, all from one declarative source.

## Layout

- **Left** — Scrollable track list with color pips, names, mute/solo
  buttons, volume/pan sliders, and animated level meters
- **Center** — Arrangement view with beat grid, bar ruler, colored
  clip blocks, and animated playhead
- **Right** — Inspector panel showing selected track details with
  large sliders and toggle buttons
- **Bottom** — Transport bar with play/pause, stop, time/beat display,
  BPM control

## Controls

| Input              | Action                                |
|--------------------|---------------------------------------|
| **Click** track    | Select track                          |
| **Up / Down**      | Keyboard track selection              |
| **Drag** slider    | Adjust volume or pan (inline or inspector) |
| **Click** M / S    | Toggle mute / solo                    |
| **m** / **s**      | Toggle mute / solo on selected track  |
| **Space**          | Play / pause (meters animate, playhead moves) |
| **r**              | Reset playhead to zero                |
| **Mouse wheel**    | Scroll track list                     |
| **BPM +/-**        | Adjust tempo                          |
| **d**              | Toggle debug overlay (cache stats, fps) |
| **Esc**            | Quit                                  |

Window is resizable — all panels adapt.

## Architecture

```
UI ASDL (Column, Row, Rect, Text, Clip, Transform, ...)
    │
    ▼  layout: :measure() + :place(x, y)
View ASDL (Box, Label, Group, Clip, Transform)
    │
    ├──▶ LovePaint tree → flattened ugps command array → paint slot
    │
    └──▶ Hit tree → flattened ugps command array → hit slot
```

Both pipelines are compiled from the same source tree, but the terminal
passes now lower all the way to ugps' flat command-array runtime:
`tree in → flat cmds out → one loop + side stacks`.

## What to notice

- **Hover highlighting** uses the hit-test pipeline — paint and hit
  are completely decoupled
- **Drag interaction** modifies source state, triggers a fresh flatten,
  and the ugps slot reconciles terminal resources separately from execution
- **Animated meters and playhead** flow through the full compiler
  pipeline every frame — the cost is the `build_ui` + flattening, not
  any retained widget state
- Press **d** to see `ugps.report()` output — slot updates, runs,
  resource reuse, and command counts live
