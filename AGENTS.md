# AGENTS.md — gps.lua

This file tells AI coding agents how this codebase works and what matters.

---

## What this repo is

A Lua framework for building interactive software as compilers. The centerpiece
is `pvm.lua`: ASDL types + recording-triplet phase boundaries.

The core claim: interactive software is best understood as a live compiler from
authored intent to flat executable commands. Every phase boundary in pvm is a
memoized, lazy transformation from one ASDL layer to the next.

The repo also now contains adjacent active projects:

- `watjit/` — a typed Lua→WAT/Wasmtime low-level language toolkit with
  scalar integer types, structs/arrays/unions/tagged unions, packed/aligned
  layouts, imports, SIMD, memory helpers, a fixed-capacity hashtable, and
  stream compilation
- `iwatjit/` — a bounded-memory pvm-successor runtime on top of `watjit`,
  with an additional spec-first machine DSL layered on top
- `asdljit/` — an early native-ASDL runtime scaffold built on `watjit`,
  focused on schema/codegen/quotes/inlining

The old first `iwatjit` runtime experiment remains archived under
`archive/iwatjit_retired/`, but the active `iwatjit/` directory now contains a
restored/continued runtime plus newer machine-spec work.

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

`watjit/` is an active standalone subproject. Treat it as its own library layer.
`watjit` must stay usable standalone.

When working on `watjit`, read:

- `watjit/README.md` for the current implemented surface
- `new/WATJIT_LANGUAGE.md` for the target design direction

When working on `iwatjit`, read:

- `iwatjit/README.md`
- `new/IWATJIT_MACHINE_SPEC.md`
- `new/IWATJIT_RUNTIME_LAYOUT.md`
- `new/IWATJIT_PVM_PARITY_CHECKLIST.md`
- `new/ASDLJIT.md`
- `asdljit/README.md`

---

## pvm — one boundary primitive

### `pvm.phase(name, handlers)` — type-dispatched streaming boundary

The primary boundary primitive. Handlers dispatch by ASDL type and return
a **triplet** `(g, p, c)`, not a value.

`pvm.phase` may also take explicit extra arguments. Those arguments become
additional cache-key dimensions:

```lua
local measure = pvm.phase("measure", {
    [T.UI.Text] = function(self, max_w)
        return pvm.once(Size(wrap_w(self.text, max_w), wrap_h(self.text, max_w)))
    end,
})

local size = pvm.one(measure(node, 200))
-- cache key: (node identity, 200)
```

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

Method form: `pvm.phase` installs `node:name(...)` on each handled type.

### `pvm.phase(name, fn)` — scalar boundary as lazy single-element stream

For boundaries that compute one value per node, define phase directly with a function:

```lua
local solve_phase = pvm.phase("solve", function(tree)
    return layout_solver(tree)
end)
local result = pvm.one(solve_phase(node))
```

The function form also accepts explicit extra arguments, which become part of
the cache key:

```lua
local measure_phase = pvm.phase("measure", function(tree, max_w)
    return Size(compute_w(tree, max_w), compute_h(tree, max_w))
end)
local size = pvm.one(measure_phase(node, 200))
```

Scalar boundaries are consumed explicitly with `pvm.one(...)`:

```lua
local solve_phase = pvm.phase("solve", function(tree)
    return layout_solver(tree)
end)
local solved = pvm.one(solve_phase(node))
```

With extra arguments:

```lua
local measure_phase = pvm.phase("measure", function(tree, max_w)
    return Size(compute_w(tree, max_w), compute_h(tree, max_w))
end)
local size = pvm.one(measure_phase(node, 200))
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

local B = T:Builders()      -- safe named-field builders
local F = T:FastBuilders()  -- trusted named-field builders
```

Key rules:

- **Prefer named-field builders** for normal authored code, semantic lowering, and
  readability-sensitive code:

```lua
local btn = B.App.Button {
    tag = "x",
    w = 10,
    h = 10,
    rgba8 = 0xff,
}
```

- Once the code is stable and you want named parameters with lower overhead,
  switch to **fast named builders**:

```lua
local btn = F.App.Button {
    tag = "x",
    w = 10,
    h = 10,
    rgba8 = 0xff,
}
```

- Use raw positional constructors `T.*(...)` only when you specifically want the
  maximum-speed exact path in hot code, parsers, or benchmarks.
- **`unique`** on every type — enables structural interning (same fields → same
  canonical ASDL value). This is what makes phase cache hits work.
- Constructors intern: `T.App.Button("x",10,10,0xff) == T.App.Button("x",10,10,0xff)` is `true`.
  `B.*`, `F.*`, and `T.*` all produce the same canonical interned ASDL values.
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
local K_RECT = T.View.Rect   -- a canonical singleton value, used as a tag
cmd.kind == K_RECT            -- object identity comparison, fast
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
  ↓ pvm.phase(name, fn) + pvm.one
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
- `ui/lower.lua` — `SemUI → UI` lowering
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
boundaries consumed with `pvm.one(pvm.phase(...))`. Reducers (measure/hit/draw)
run over `UI.*` nodes.

---

## bench/

Performance benchmarks. All use pvm directly. Good reference for pvm usage
patterns in real contexts (grammar compilation, ASDL parsing, JSON decoding).
See `bench/RESULTS.md` for numbers.

## watjit/

A separate active project in this repo.

Key files:

- `watjit/init.lua` — public facade (`require("watjit")`)
- `watjit/types.lua` — typed value system and pointer/view surface
- `watjit/func.lua` — function/module construction
- `watjit/emit.lua` — WAT emission
- `watjit/wasmtime.lua` — Wasmtime FFI bridge
- `watjit/struct.lua`, `watjit/array.lua` — typed memory layouts
- `watjit/arena.lua`, `watjit/slab.lua`, `watjit/lru.lua` — deterministic memory/runtime helpers
- `watjit/simd.lua` — SIMD vector types and helpers
- `watjit/stream.lua`, `watjit/stream_compile.lua` — stream algebra + compiled terminals
- `watjit/test_*.lua`, `watjit/bench_*.lua` — executable examples, tests, and benchmarks

When working in `watjit/`:

- treat it as a standalone typed WAT/Wasmtime toolkit, not as pvm internals
- preserve the layering: `watjit` must not depend on retired experiments

## asdljit/

A new experimental subproject in this repo, intended as the native-ASDL runtime
path built on `watjit/`.

Key files:

- `asdljit/init.lua` — current schema/codegen scaffold
- `asdljit/README.md` — current scope and limitations
- `asdljit/test_codegen.lua` — quote/inlining/codegen validation
- `new/ASDLJIT.md` — target architecture document

When working in `asdljit/`:

- keep ASDL semantics intact: immutability, `unique`, structural update, canonical lists
- lean on `watjit` quotes, inlining, and code generation rather than inventing bigger mechanisms
- prefer small composable generated kernels (hash, eq, getter, update) over monolithic magic
- treat the current code as a scaffold toward a full native handle/interner runtime

## iwatjit/

A separate experimental project in this repo, built on `watjit/`.

Key files:

- `iwatjit/init.lua` — public facade (`require("iwatjit")`)
- `iwatjit/README.md` — runtime + machine-spec status
- `iwatjit/test_phase.lua`, `iwatjit/test_recording.lua`, `iwatjit/test_eviction.lua`, etc. — runtime validation
- `iwatjit/test_machine_spec.lua` — machine-spec overlay test
- `iwatjit/bench_pvm_vs_iw.lua` — comparison bench against current pvm

When working in `iwatjit/`:

- treat it as a real runtime layer, not just docs or a sketch
- preserve the full runtime behavior: recording, shared, seq-hit replay, bounded caches, eviction, memory accounting
- also preserve the spec-first machine surface where possible
- keep execution-layer thinking aligned with fused traversal/replay internals
- use `archive/iwatjit_retired/` as historical reference only; do not edit it

## archive/

- `archive/iwatjit_retired/` — retired first `iwatjit` runtime experiment and notes

---

## docs/

- `docs/COMPILER_PATTERN.md` — the paradigm paper: five concepts, flatten
  theorem, ASDL design methodology, what the pattern eliminates
- `docs/PVM_GUIDE.md` — complete pvm implementation guide: all primitives,
  ui5 walkthrough, classification discipline, uvm, performance, checklists
- `docs/LIBUI_AUTHORING_GUIDE.md` — how to author apps on top of ui/

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

# PVM Discipline Rules for AI Coding

> This document defines the architectural discipline for working with pvm.
> Every rule exists because violating it silently degrades caching, type
> safety, memory management, or performance. There are no optional rules.

---

## The One Principle

**If it isn't an ASDL value, it doesn't exist to the system.**

Phase caches key on ASDL identity. Structural sharing works through ASDL
interning. Type dispatch works through ASDL class lookup. `pvm.with` operates
on ASDL nodes. `pvm.report` diagnoses ASDL-keyed caches.

The moment something meaningful lives outside the ASDL — in a ctx, a closure,
a registry, a global, a plain table — it becomes invisible to every mechanism
that makes pvm work.

---

## The Execution Model

There is no separate "execution layer." The phase boundary returns a triplet
`(gen, param, state)`. You consume it. That IS execution.

```lua
for _, v in phase(node) do
    -- this is the machine running
end
```

Or equivalently: `pvm.each(phase(node), fn)`, `pvm.drain(phase(node))`,
`pvm.fold(phase(node), init, fn)`.

The triplet is not an abstraction over execution. It IS execution factored
into its three irreducible roles: step function, invariant environment,
mutable cursor. Every phase boundary returns one. Every consumer runs one.
Cache fills as a side effect of full consumption. There is nothing else.

---

## ASDL Rules

### R1: No plain tables as domain values

NEVER:

```lua
{ tag = "btn", w = 100, h = 30 }
```

ALWAYS:

```lua
T.App.Button("btn", 100, 30, ...)
```

Plain tables have no interning, no identity, no cache keying, no structural
sharing, no type safety, no `pvm.with`, no phase dispatch, and no weak-key
compatibility with pvm's cache system.

### R2: No strings where sum types belong

NEVER:

```lua
kind = "button"
```

ALWAYS:

```lua
Kind = Button | Slider | Meter
```

Strings lose exhaustiveness, variant-specific fields, singleton identity
comparison, and phase dispatch.

Every boolean flag that constrains another boolean is a sum type:

```lua
-- WRONG: boolean soup with implicit constraints
is_playing = true, is_recording = false, is_paused = false

-- RIGHT: impossible invalid state
TransportState = Stopped | Playing | Recording | Paused
```

### R3: No optional fields as variant discrimination

NEVER branch behavior on nil-checking an optional field.
ALWAYS use a sum type with explicit variants:

```lua
-- WRONG
Param = (number value, Automation? automation) unique
-- then: if node.automation ~= nil then ...

-- RIGHT
ParamSource = Static(number value) unique
            | Automated(Automation curve) unique
```

### R4: No derived data in source ASDL

If a value is computed from other values, it belongs in a later phase.

```lua
-- WRONG: coefficients are derived from freq and q
Filter = (number freq, number q, number b0, number b1, number b2) unique

-- RIGHT: source has only authored fields
Filter = (number freq, number q) unique
-- coefficients computed in a phase boundary
```

The source ASDL answers: what did the user author? What survives save/load?
What does undo restore? Nothing else belongs there.

### R5: Always mark types `unique`

Types without `unique` don't intern. Every constructor allocates a new object.
Phase caches never hit because identity comparison fails. The code runs. It
just runs slowly and leaks.

### R6: Never mutate ASDL nodes

NEVER use `rawset(node, field, value)` or any other mutation path.
ALWAYS use `pvm.with(node, { field = value })`.

Mutation corrupts the interning trie. The node stored at the old key now has
different values. Every future lookup for those keys returns a corrupt node.
Interning is globally and silently broken.

The `__newindex` error on ASDL nodes exists for this reason. Do not bypass it.

### R7: Use `pvm.with`, not manual reconstruction

```lua
-- WRONG: fragile, breaks when fields are added
local new = T.App.Track(t.name, t.color, new_vol, t.pan, t.mute, t.solo, t.level)

-- RIGHT: only name what changes
local new = pvm.with(t, { vol = new_vol })
```

### R8: Use `pvm.with`, not deep copy

Deep copy creates new objects for everything. Every cache lookup misses.
Zero structural sharing.

`pvm.with` produces a new node for changed fields only. All unchanged fields
keep their interned identity. All phase caches hit on unchanged subtrees.

---

## Phase Boundary Rules

### R9: Handlers MUST return triplets

NEVER return nil, a raw value, or a table from a phase handler.
ALWAYS return `(gen, param, ctrl)`:

```lua
-- One output element
return pvm.once(value)

-- Map phase over children
return pvm.children(phase_fn, self.children)

-- Multiple elements
return pvm.concat2(pvm.once(a), pvm.once(b))

-- Zero output
return pvm.empty()
```

Returning nil from a handler is an error. Returning a raw value or table
breaks the recording protocol.

### R10: No parallel caching

NEVER add `local cache = {}` or `local memo = {}` alongside pvm phases.
NEVER write manual memoization wrappers.

```lua
-- WRONG: parallel cache with string keys, manual invalidation, strong refs
local memo = {}
local function get_layout(node)
    local key = node.tag .. ":" .. node.w .. ":" .. node.h
    if memo[key] then return memo[key] end
    local result = compute_layout(node)
    memo[key] = result
    return result
end
```

The phase boundary IS the cache. `pvm.phase` records on miss, commits on
full drain, and returns seq on hit. If you see `local cache = {}` or
`local memo = {}` anywhere outside pvm's own machinery, it is a bug.

Either the work belongs in a `pvm.phase` boundary (which caches
automatically), or it's genuinely ephemeral and shouldn't be cached at all.

If the cached computation depends on a node **and explicit extra inputs**,
pass those inputs to the phase:

```lua
local measure_phase = pvm.phase("measure", function(node, max_width)
    return Size(compute_w(node, max_width), compute_h(node, max_width))
end)

local size = pvm.one(measure_phase(node, 200))
-- cache key: (node identity, 200)
```

There are no side-cache exceptions.

### R11: No ctx / bag-of-state arguments

NEVER thread an opaque context table through handlers or build functions:

```lua
-- WRONG
local function build_row(ctx, track, index)
    local bg = index == ctx.selected and ACTIVE or NORMAL
    ...
end
```

If a handler's output depends on a value, that value MUST be a field on the
ASDL node:

```lua
-- RIGHT: everything the handler needs is in the node
T.App.TrackRow(index, track, is_selected, is_hovered)
```

**Why this is fatal:** Phase caches key on node identity. The ctx is invisible
to the cache. When ctx changes but the node doesn't, the cache returns stale
results. The AI introduces an invisible dependency that the phase boundary
cannot track.

**The fix is always the same:** whatever the handler reads from ctx belongs as
a field on the ASDL type. If `hover_tag` affects output, it's a field. If
`theme` affects colors, resolve theme to concrete color values BEFORE
constructing the node.

### R12: No closures over mutable state in handlers

```lua
-- WRONG: output depends on captured `selected`, cache keys on node only
local selected = 1
[T.App.TrackRow] = function(self)
    if self.index == selected then ...  -- captured mutable!
```

The value of `selected` must be a field on the node itself. Same reason as
R11: the cache can't see it.

### R13: Call phases, not handlers directly

NEVER call a handler function directly or inline its logic.
ALWAYS call through the phase boundary:

```lua
-- WRONG: bypasses recording, caching, shared deduplication
local result = my_handler_fn(node)

-- RIGHT: goes through the phase machinery
for _, v in phase(node) do ... end
```

### R14: Understand partial drain

If a for-loop over a phase triplet breaks early, the recording does NOT
commit to cache. This is correct and safe. Do NOT add manual caching to
"fix" the re-evaluation on next access.

If you need the full cache, drain fully.

---

## Memory Rules

### R15: No strong references to ASDL nodes in external tables

pvm's caches use `__mode = "k"` (weak keys). When a node leaves the live
source tree, GC collects it and its cache entries die naturally.

If you store nodes in a plain table without weak keys, those nodes and all
their downstream cache entries are pinned forever:

```lua
-- WRONG: strong key, pins node and all downstream forever
local index = {}
index[node] = data

-- RIGHT: weak key, node dies when no longer in live tree
local index = setmetatable({}, { __mode = "k" })
index[node] = data
```

**This is the primary memory leak vector in pvm applications.**

### R16: No accumulating results across frames

NEVER append to a growing table each frame:

```lua
-- WRONG: grows forever, pins all nodes
all_results[#all_results + 1] = pvm.drain(phase(root))

-- RIGHT: replace, old results become garbage
current_results = pvm.drain(phase(root))
```

### R17: No non-ASDL wrappers holding ASDL nodes

NEVER wrap an ASDL node in a plain Lua object:

```lua
-- WRONG: strong reference pins the node
local wrapper = { node = my_node, extra = "stuff" }
```

If you need extra data associated with a node, either add it as a field on
the ASDL type, or store it in a weak-keyed side table.

---

## Anti-Pattern Catalog

These are patterns that look like normal good programming but are
fundamentally incompatible with pvm.

### Functions that take IDs instead of values

```lua
-- WRONG: indirection, opaque lookup, untestable without the table
local function render_track(track_id, tracks_table)
    local track = tracks_table[track_id]
    ...
end

-- RIGHT: the node IS the value, pass it directly
local function render_track(track_node)
    ...
end
```

IDs belong only where there is a real authored cross-reference between
independent subtrees (a send referencing another track). Even then, resolve
the ID in an explicit early phase, producing a new ASDL node carrying the
resolved value.

### Mutable accumulator threading

```lua
-- WRONG: output depends on call order, caching impossible
local function build_ui(node, state)
    state.y = state.y + ROW_H
    state.count = state.count + 1
    ...
end
```

Phase handlers must be pure functions of their node. If position depends on
sibling layout, that's a layout pass that runs inside a scalar phase boundary
and caches the entire result.

### Observer / callback registration

```lua
-- WRONG: interpreter pattern, breaks interning
node.on_click = function() ... end
node:addEventListener("hover", fn)
```

In pvm, input is Event ASDL, state change is `Apply : (state, event) → state`,
the new state compiles through phases. There is no listener. There is no
event bus. There is: poll → apply → compile → execute.

Callbacks also break interning — function identity is reference identity in
Lua, so two structurally identical nodes with different closures can never
intern to the same value.

### Managers and registries

```lua
-- WRONG: opaque mutable container, invisible to ASDL and caching
local WidgetManager = {
    widgets = {},
    register = function(self, w) ... end,
    update = function(self, id, props) ... end,
}
```

The collection is an ASDL list field: `Project(App.Track* tracks) unique`.
Updating a track is `pvm.with(project, { tracks = new_tracks })`. No manager.

### Ad hoc type wrappers / classes

```lua
-- WRONG: reinventing types outside ASDL
local Button = {}
Button.__index = Button
function Button.new(tag, w, h)
    return setmetatable({ tag = tag, w = w, h = h }, Button)
end
```

This is an ASDL type: `Button = (string tag, number w, number h) unique`.
ASDL gives you interning, immutability, type checking, phase dispatch,
`pvm.with`, and structural sharing. The ad hoc class gives you none of those.

### Imperative state machines with mode flags

```lua
-- WRONG: mode string controlling behavior
local mode = "editing"
if mode == "editing" then ...
elseif mode == "previewing" then ...
```

This is a sum type in the source ASDL:

```
AppMode = Editing(EditState state) unique
        | Previewing(PreviewState state) unique
```

Phase handlers dispatch on the variant. Each variant carries its own state.
Impossible to be in "editing" mode with preview state.

---

## The Diagnostic Questions

When reviewing or writing pvm code, apply these tests:

### The one-constructor test

> Can you test this function with one ASDL constructor call and one assertion,
> with nothing else?

If the answer requires building a ctx, populating a registry, setting up a
listener, initializing a mutable accumulator, constructing a lookup table,
or resetting a manual cache — the ASDL is incomplete, a dependency is hidden,
or the work is in the wrong layer.

### The cache-correctness test

> If this node is unchanged next frame, will the phase cache return the
> correct result?

If the handler reads ANYTHING not in the node (globals, captures, ctx,
side tables), the answer is no. The cache will return stale results.

### The memory test

> If this node leaves the source tree, will it be garbage collected?

If anything holds a strong reference to it (a plain table without `__mode`,
a closure capture, a non-ASDL wrapper), the answer is no. The node and its
entire cache chain are pinned.

### The pvm.report test

> Does `pvm.report_string` show healthy reuse ratios?

- 90%+ = healthy, structural sharing works, incrementality is real
- 70-90% = acceptable during genuine change (animation, editing)
- Below 50% = ASDL design problem — types aren't interning, boundaries
  are wrong, or invisible dependencies are defeating the cache

If the hit ratio is low but the data hasn't changed, something outside the
ASDL is varying (ctx, capture, accumulator) and poisoning the cache key.

---

## Summary of What pvm Eliminates

When the discipline is followed, these things do not exist in the codebase:

- State managers, stores, or reducers (Apply is a pure function, source ASDL is the state)
- Observer patterns, event buses, or listener registration (Event ASDL + Apply)
- Manual caching, memoization wrappers, or invalidation logic (phase boundaries)
- Dirty flags or change tracking (ASDL identity comparison)
- Virtual DOM or diffing (structural sharing via `pvm.with` + interning)
- Object-relational mapping or ID-based registries (ASDL nodes are values, pass them)
- Deep equality checks (interned `==` is reference equality)
- Type-checking boilerplate (ASDL constructors validate)
- Opaque context threading (all inputs are ASDL fields)
- Ad hoc Lua classes or metatables for domain types (ASDL types)
- Manager objects or service containers (ASDL list fields + `pvm.with`)

Every item on this list represents a failure mode where an AI will reach for
the standard solution instead of the ASDL-first solution. The standard
solution will appear to work. It will silently degrade caching, leak memory,
defeat type safety, or introduce stale-data bugs that are invisible until
`pvm.report` reveals the damage.
