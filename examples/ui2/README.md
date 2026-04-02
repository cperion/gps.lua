# Track Editor — ui2: flatten-early architecture

Same app as `examples/ui`. Same visuals, same interaction.
Different architecture: **flatten-early**.

```bash
love examples/ui2
```

## Architecture difference

**ui1** (tree all the way down):
```
UI ASDL (tree)
  → View ASDL (tree)           ← recursive traversal #2
    → LovePaint ASDL (tree)    ← recursive traversal #3
      → M.compose() (tree)     ← recursive traversal #4
        → nested gen calls
```

**ui2** (flatten-early):
```
UI ASDL (tree)
  │
  │  :place() — the ONE recursive pass
  │  outputs two flat Cmd* arrays simultaneously
  ▼
Draw.Frame(Cmd*) + Hit.Frame(HCmd*)    ← flat, no recursion
  │
  │  one emit() per backend, flat-loop gen
  ▼
Linear execution                        ← single for loop
```

## What changed

- **No View ASDL** — eliminated entirely
- **No LovePaint tree ASDL** — replaced by flat `Draw.Frame(Cmd*)`
- **No Hit tree ASDL** — replaced by flat `Hit.Frame(HCmd*)`
- **No M.compose()** — no recursive gen nesting
- **No lovepaint.lua / hittest.lua** — backends are inline flat-loop gens
- **Containment** via `PushClip/PopClip`, `PushTransform/PopTransform` commands
- **One tree walk** (:place) produces both flat command lists simultaneously
- **Paint gen**: single `for i=1,#cmds` loop with inline Love2D calls
- **Hit gen**: single `for i=1,#cmds` loop with inline point-in-rect tests
- **State management**: text resources tracked per-command-slot in a flat array

## Controls

Same as ui1 — see `examples/ui/README.md`. Press `d` for debug overlay
showing command counts and cache stats.
