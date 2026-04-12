# AGENTS.md — gps.lua

This file tells AI coding agents how this codebase works and what matters.

---

## What this repo is

A Lua framework for building interactive software as compilers. The centerpiece
is `pvm.lua`: ASDL types + recording-triplet phase boundaries.

The core claim: interactive software is best understood as a live compiler from
authored intent to flat executable commands. Every phase boundary in pvm is a
memoized, lazy transformation from one ASDL layer to the next.

---

## The six files at root

```
pvm.lua          — the ONE boundary primitive (phase) + one + drain/each/fold +
                   once/children/concat + seq + report
triplet.lua      — iterator algebra (map/filter/flatmap/zip/scan/...) used inside handlers
quote.lua        — hygienic codegen via loadstring (used by asdl_context for interning tries)
asdl_context.lua — ASDL type system: interning, constructors, metatable dispatch
asdl_lexer.lua   — ASDL schema lexer
asdl_parser.lua  — ASDL schema parser (recursive descent, lexer-fused, 212 lines)
```

Dependency chain (everything flows from pvm):

```
pvm.lua → triplet.lua
        → asdl_context.lua → quote.lua
                           → asdl_parser.lua → asdl_lexer.lua
```

`archive/` holds historical files (gps/mgps era). Do not touch them.

---

## pvm — one boundary primitive

### `pvm.phase(name, handlers)` — type-dispatched streaming boundary

The primary boundary primitive. Handlers dispatch by ASDL type and return
a **triplet** `(g, p, c)`, not a value.

```lua
local lower = pvm.phase("lower", {
    [T.App.Button] = function(self)
        return pvm.once(Cmd(self.tag, self.w, self.h, self.rgba8))
    end,
    [T.App.Row] = function(self)
        return pvm.children(lower, self.children)
    end,
})
```

Three-way cache per call:
- **hit** — node fully drained before → `seq_gen` over cached array, zero work
- **shared** — same node being recorded by another consumer → share the recording
- **miss** — handler dispatches, returns triplet, wrapped in recording_gen, commits to cache on full drain

Method form: `pvm.phase` installs `node:name()` on each handled type.

### `pvm.phase(name, fn)` — scalar boundary as lazy single-element stream

For boundaries that compute one value per node, define phase directly with a function:

```lua
local solve_phase = pvm.phase("solve", function(tree)
    return layout_solver(tree)
end)
local result = pvm.one(solve_phase(node))
```

### `pvm.lower(name, fn)` — compatibility wrapper

`pvm.lower` remains as sugar for legacy call sites:

```lua
local solve = pvm.lower("solve", function(tree)
    return layout_solver(tree)
end)
-- equivalent to pvm.one(pvm.phase("solve", fn)(node))
```

---

## Handler contract — handlers MUST return triplets

This is the most important rule. A `pvm.phase` handler returns a triplet
`(gen, param, ctrl)`, never a plain value.

| Situation | Use |
|-----------|-----|
| Leaf: one output element | `return pvm.once(value)` |
| Leaf: no output | `return pvm.empty()` |
| Two elements | `return pvm.concat2(pvm.once(a), pvm.once(b))` |
| Three elements | `return pvm.concat3(...)` |
| N elements from array | `return pvm.seq(array)` |
| Children via same phase | `return pvm.children(phase_fn, self.children)` |
| Complex composition | `return pvm.concat_all({ {g1,p1,c1}, {g2,p2,c2}, ... })` |
| From triplet algebra | `return pvm.T.map(f, g, p, c)` etc. |

**Never** return a raw value from a phase handler. The caching machinery won't
work and you'll get a confusing runtime error.

---

## Consumption — native `for` first, terminals second

Nothing evaluates until a consumer pulls from the triplet.

```lua
-- Canonical executor: Lua generic for (gen, param, state)
for _, cmd in phase(root) do
    draw(cmd)
end

-- Materialize to array (iterate twice, e.g. hit-test)
local cmds = pvm.drain(phase(root))

-- Append to existing array (sink optimization)
pvm.drain_into(phase(root), out)

-- Reduce to single value contract
local total = pvm.fold(phase(root), 0, function(acc, cmd) return acc + cmd.w end)
local solved = pvm.one(solve_phase(root))
```

Cache fills as a side effect of full exhaustion. Next call to `phase(same_node)` is a seq hit.

---

## ASDL — the type system

All domain types are ASDL types. Define them with `pvm.context()`:

```lua
local T = pvm.context():Define [[
    module App {
        Widget = Button(string tag, number w, number h, number rgba8) unique
               | Row(App.Widget* children)                             unique
    }
]]
```

Key rules:
- **`unique`** on every type — enables structural interning (same fields → same
  Lua table). This is what makes phase cache hits work.
- Constructors intern: `T.App.Button("x",10,10,0xff) == T.App.Button("x",10,10,0xff)` is `true`.
- **Never mutate interned nodes.** Use `pvm.with(node, {field=value})` for
  structural update — returns a new interned node, unchanged fields keep identity.

```lua
local new_widget = pvm.with(old_widget, { rgba8 = 0x00ff00ff })
-- new_widget.tag == old_widget.tag  -- same string object
-- new_widget ~= old_widget          -- different node (different rgba8)
```

Singleton sum variants (no fields) are values, not constructors:

```lua
T:Define [[ module View { Kind = Rect | Text | PushClip | PopClip } ]]
local K_RECT = T.View.Rect   -- a singleton table, used as a tag
cmd.kind == K_RECT            -- pointer comparison, fast
```

---

## The live loop

```
poll → apply → phase(source) → for/drain → execute
```

- **poll**: read input
- **apply**: pure reducer `(source_asdl, event) → source_asdl`
- **phase(source)**: returns a triplet, nothing evaluates
- **for/drain**: pulls through the chain; misses run handlers; caches fill
- **execute**: draw/audio/backend calls

On the next frame: unchanged nodes return `seq_gen` instantly. Only changed
subtrees run handlers. This is structural incrementality — not bolted on.

---

## Incrementality and structural sharing

Incrementality is a direct consequence of ASDL `unique` + `pvm.with`:

```lua
-- User changes one track's volume
local new_source = pvm.with(source, {
    tracks = update_track(source.tracks, 2, function(t)
        return pvm.with(t, { vol = 80 })
    end)
})
-- Track 2 is a new object → cache miss → handler runs
-- All other tracks are SAME objects → cache hit → instant
```

The `reuse_ratio` in `pvm.report_string` is the architecture quality metric:

```
  lower    calls=4174  hits=3037  shared=892  reuse=93.3%
```

- **90%+** — excellent, structural sharing works
- **70–90%** — good during animation
- **below 50%** — ASDL design problem, check boundaries

---

## ASDL layer design

Every app has layers. The rule: each recursive type is one layer; the final
layer is flat (no recursion, just a command array).

Typical three-layer stack:

```
Layer 0: App.*     — domain vocabulary (what the user edits)
  ↓ pvm.phase
Layer 1: UI.*      — layout/structure vocabulary
  ↓ pvm.phase(name, fn) + pvm.one (or `pvm.lower` compatibility)
Layer 2: View.Cmd  — flat command array (uniform product type + Kind singleton)
  ↓ native for-loop (or pvm.each/drain terminals)
Execution
```

The flat command type must be **one product type** with a Kind singleton tag —
not a sum type with per-variant metatables. One metatable = one LuaJIT trace.

---

## The ui/ library

A full UI library built on pvm. Key files:

- `ui/asdl.lua` — all ASDL schemas (Interact, Layout, DS, SemUI, UI, Facts,
  Paint, Msg)
- `ui/lower.lua` — `SemUI → UI` lowering (currently via `pvm.lower`, compatible with scalar phase form)
- `ui/ds.lua` — design system: theme/surface → resolved style packs
- `ui/measure.lua` — measurement reducer
- `ui/hit.lua` — hit-testing reducer
- `ui/draw.lua` — drawing reducer
- `ui/_flex.lua` — shared flex kernel (private, used by measure/hit/draw)
- `ui/session.lua` — runtime state, messages, focus, reducer wiring
- `ui/init.lua` — public facade (`require("ui")`)
- `ui/demo/` — Love2D showcase with DAW project ASDL

Architecture: app/domain semantics stay outside the library. The library owns
generic UI semantics only. DS resolution and semantic lowering are scalar
boundaries (implemented with `pvm.lower(...)` today, equivalent to
`pvm.phase(name, fn)` + `pvm.one`). Reducers (measure/hit/draw) run over `UI.*` nodes.

---

## bench/

Performance benchmarks. All use pvm directly. Good reference for pvm usage
patterns in real contexts (grammar compilation, ASDL parsing, JSON decoding).
See `bench/RESULTS.md` for numbers.

---

## docs/

- `docs/COMPILER_PATTERN.md` — the paradigm paper: five concepts, flatten
  theorem, ASDL design methodology, what the pattern eliminates
- `docs/PVM_GUIDE.md` — complete pvm implementation guide: all primitives,
  ui5 walkthrough, classification discipline, uvm, performance, checklists
- `docs/LIBUI_AUTHORING_GUIDE.md` — how to author apps on top of ui/
- `docs/PLAN.md` — historical migration plan (complete, kept for context)

**Read these before making architectural decisions.**

---

## What NOT to do

| Wrong | Right |
|-------|-------|
| Return a value from a phase handler | Return `pvm.once(value)` |
| Use `pvm.verb` | Use `pvm.phase` — verb doesn't exist |
| Mutate an interned node's fields | Use `pvm.with(node, overrides)` |
| Use string dispatch `if kind == "rect"` | Use sum types + phase dispatch |
| Create closures inside a handler per call | Define phase at module scope |
| Mix layout and projection in one handler | Split into boundaries (phase + scalar phase/one) |
| Use a sum type for the flat Cmd type | Use one product type + Kind singleton |
| Build intermediate trees that persist to execution | Flatten to Cmd array |
| Call `pvm.report` with one boundary and ignore result | Check `reuse_ratio`, not just `hit_ratio` |

---

## Common patterns

### Leaf that emits one command
```lua
[T.App.Button] = function(self)
    return pvm.once(Cmd(K_RECT, self.tag, 0, 0, self.w, self.h, self.rgba8))
end,
```

### Container that recurses over children
```lua
[T.App.Row] = function(self)
    return pvm.children(lower, self.children)
end,
```

### Container with push/pop markers around children
```lua
[T.UI.Clip] = function(self)
    return pvm.concat3(
        pvm.once(PushClip(self.w, self.h)),
        pvm.children(lower, self.children),
        pvm.once(PopClip)
    )
end,
```

### Two elements (avoid concat_all overhead for small N)
```lua
[T.App.Meter] = function(self)
    return pvm.concat2(
        pvm.once(Fill(self.tag.."|fill", fill_w, self.h, color)),
        pvm.once(Fill(self.tag.."|bg",   self.w - fill_w, self.h, bg))
    )
end,
```

### Structural update in the apply reducer
```lua
local function apply(state, event)
    if event.kind == "SetVolume" then
        local new_track = pvm.with(state.tracks[event.id], { vol = event.value })
        return pvm.with(state, {
            tracks = replace(state.tracks, event.id, new_track)
        })
    end
    return state
end
```

### Checking cache health
```lua
print(pvm.report_string({ lower_phase, solve_boundary }))
--   lower    calls=4174  hits=3037  shared=892  reuse=93.3%
--   solve    calls=120   hits=118   shared=0    reuse=98.3%
```

---

## Package path setup

Most files in bench/ and examples/ do this at the top:

```lua
package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end
```

The ASDL modules are exposed under the `gps.*` namespace internally; the
preload aliases make them available under their short names too.

---

## Runtime: LuaJIT

This codebase targets LuaJIT. Design decisions flow from that:

- The flat Cmd type uses one product + Kind singleton so the execution for-loop
  sees one metatable → one trace → golden bytecode
- `pvm.phase` dispatch uses `getmetatable(node)` table lookup — no loadstring,
  no generated source, just a plain table read (JIT-friendly)
- ASDL constructors ARE code-generated (unrolled interning tries, no loops) via
  `quote.lua` + `loadstring` — this happens once at definition time
- `triplet.lua` combinators are designed to trace cleanly: no `select()`, no
  `pairs()`, minimal allocation in hot paths
- `seq_gen` (the cache hit path) is `i = i+1; if i > #t then return nil end;
  return i, t[i]` — as traceable as it gets
