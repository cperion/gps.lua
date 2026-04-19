# iwatjit machine spec

*Target design document.*

This document describes the intended public authoring model for the next
`iwatjit` direction after the retired `archive/iwatjit_retired/` experiment.

The core change is deliberate:

> `iwatjit` should not expose raw low-level `watjit` authoring directly.
> It should expose a higher-level, spec-first machine DSL.

That means:

- **no-parens table specs** for major runtime objects
- explicit **`param` / `state` / `gen`** declarations
- generated structs and generated functions from one spec
- fused traversal/replay internals underneath, not a pile of host wrappers

`watjit` remains the low-level substrate.
`iwatjit` becomes the machine-definition layer built on top of it.

---

## Table of contents

1. [Why the authoring style should change](#why-the-authoring-style-should-change)
2. [The layer split: watjit vs iwatjit](#the-layer-split-watjit-vs-iwatjit)
3. [The core thesis](#the-core-thesis)
4. [Public surface sketch](#public-surface-sketch)
5. [Phase spec](#phase-spec)
6. [Generated artifacts](#generated-artifacts)
7. [Machine body semantics](#machine-body-semantics)
8. [Cache and result policy](#cache-and-result-policy)
9. [Hit / shared / miss in the new model](#hit--shared--miss-in-the-new-model)
10. [How traversal fusion fits underneath](#how-traversal-fusion-fits-underneath)
11. [Suggested auxiliary specs](#suggested-auxiliary-specs)
12. [Worked examples](#worked-examples)
13. [Migration intent from pvm](#migration-intent-from-pvm)
14. [What not to do](#what-not-to-do)
15. [The thesis](#the-thesis)

---

## Why the authoring style should change

The retired `iwatjit` experiment stayed too close to the old pvm surface:

- runtime objects first
- boundary call behavior first
- cache/runtime machinery visible early

That was useful for proving bounded memory, native replay, and deterministic
allocation. But it inherited too much of the old execution storytelling.

The new direction should instead treat `iwatjit` as a **machine definition DSL**.

Why?

Because a pvm successor is fundamentally about a small number of explicit
runtime machine kinds:

- phase cache entries
- replay cursors
- recording state
- shared readers
- bounded result owners
- eviction/accounting state

Those are not ad hoc functions. They are typed runtime machines with known
layout and known lifetime roles.

Lua table specs are the right authoring medium for those.

And `watjit` already gives us the implementation substrate:

- struct layout from specs
- function generation from specs
- quotes for inline staged fragments
- deterministic runtime helpers

So `iwatjit` should lean into that instead of pretending it is just hand-coded
`watjit` with a few helpers.

---

## The layer split: watjit vs iwatjit

### `watjit`

`watjit` is the low-level language.

It owns:

- scalar/vector types
- structs/unions/arrays
- control flow
- memory operations
- quotes
- runtime helper libraries
- fused traversal lowering substrate

### `iwatjit`

`iwatjit` is the machine-spec layer.

It should own:

- phase declarations
- runtime entry/cursor/result schemas
- cache policy declarations
- recording/replay ownership rules
- generated machine artifacts
- reporting and accounting surfaces

So the rule is:

> `watjit` is how the machine is built.
> `iwatjit` is how the machine is declared.

---

## The core thesis

A pvm successor should expose two levels at once:

### Public authoring model

A **spec-first machine DSL**:

```lua
local lower = iw.phase {
  name = "lower",
  key_t = NodeRef,
  item_t = Cmd,

  param = {
    node  = NodeRef,
    max_w = wj.i32,
  },

  state = {
    pc      = wj.u8,
    child_i = wj.i32,
  },

  result = {
    storage = "slab_seq",
    item_t  = Cmd,
  },

  cache = {
    args   = "full",
    policy = "bounded_lru",
  },

  gen = function(P, S, emit, R)
    ...
  end,
}
```

### Internal execution model

A **compiled traversal/replay algebra**:

- producers lower into sinks
- replay is a source kind
- recording is a sink/publication seam
- terminals close the machine
- hit/shared/miss are runtime source-selection concerns

The public syntax can stay explicit and machine-shaped without forcing the
internal execution substrate to become a literal `next()`-style port.

---

## Public surface sketch

The main high-level forms should be no-parens table specs:

```lua
local rt = iw.runtime {
  memory = {
    result_bytes = 64 * 1024 * 1024,
    temp_bytes   =  4 * 1024 * 1024,
  },
}

local lower = iw.phase {
  ...
}

local solve = iw.scalar_phase {
  ...
}

local draw = iw.terminal {
  ...
}
```

This style is not cosmetic. It says:

- this is declarative machine definition
- the tables are inputs to code generation
- layout and behavior are peers in one spec

---

## Phase spec

The central declaration should be `iw.phase { ... }`.

### Minimal shape

```lua
local lower = iw.phase {
  name = "lower",
  key_t = NodeRef,
  item_t = Cmd,

  param = {
    node = NodeRef,
  },

  state = {
    pc = wj.u8,
  },

  gen = function(P, S, emit, R)
    ...
  end,
}
```

### Recommended full shape

```lua
local lower = iw.phase {
  name = "lower",

  key_t = NodeRef,
  item_t = Cmd,

  param = {
    node  = NodeRef,
    max_w = wj.i32,
  },

  state = {
    pc         = wj.u8,
    child_i    = wj.i32,
    child_slot = wj.i32,
  },

  result = {
    storage = "slab_seq",
    item_t  = Cmd,
    inline_capacity = 4,
  },

  cache = {
    args   = "full",      -- full | last | none
    policy = "bounded_lru",
    cost   = "bytes",
  },

  memory = {
    temp = "bump",
  },

  hooks = {
    bytes = function(P, S, R)
      ...
    end,
  },

  gen = function(P, S, emit, R)
    ...
  end,
}
```

### Field meaning

#### `name`
Human-readable phase name used for diagnostics, reporting, and generated symbol
prefixes.

#### `key_t`
The cache key type for the structural part of the lookup. In a pvm-successor
setting this is usually some node identity / intern handle type.

#### `item_t`
The flat emitted item type.

#### `param`
Stable per-invocation environment.

This is the explicit replacement for the vague “param role” from triplets.
Whatever varies per call but is stable while one machine runs belongs here.

Typical examples:

- source node handle
- width/height constraints
- resolved theme handle
- content store handle
- backend/runtime handle reference

#### `state`
Mutable cursor state for a suspended or in-flight machine.

Typical examples:

- program counter / tag
- child index
- pending iterator slot
- replay cursor offset
- recording cursor position

#### `result`
Declaration of committed output storage shape.

This is where the machine tells the runtime what replayable result form it
publishes on success.

#### `cache`
Declaration of key policy and bounded ownership policy.

#### `memory`
Hints or requirements for temp/recording allocation behavior.

#### `hooks`
Optional accounting / sizing / debug helpers.

#### `gen`
The machine body.

---

## Generated artifacts

A single `iw.phase { ... }` spec should generate more than one thing.

At minimum:

- `Phase.Param`
- `Phase.State`
- `Phase.Result`
- `Phase.Entry`
- `Phase.Cursor`
- `Phase.Stats`
- `Phase.gen`
- `Phase.resume`
- `Phase.replay`
- `Phase.record`
- `Phase.lookup`
- `Phase.report`

### Suggested generated layout types

#### `Phase.Param`
Struct generated from the `param` table.

#### `Phase.State`
Struct generated from the `state` table.

#### `Phase.Result`
Result storage layout derived from `result`.
For example:

- inline small-seq form
- slab-backed seq form
- scalar value form

#### `Phase.Entry`
Persistent cache entry metadata.
Likely fields:

- key hash
- param hash/arg mode discriminator
- result ref
- LRU links
- status tag (`empty/live/recording/shared/...`)
- byte cost

#### `Phase.Cursor`
Transient in-flight machine instance.
Likely fields:

- param payload
- state payload
- recording buffer ref
- parent/shared links
- progress tag

### Suggested generated functions

#### `Phase.lookup(...)`
Runtime lookup for hit/shared/miss routing.

#### `Phase.resume(...)`
Continue a suspended/in-flight machine.

#### `Phase.record(...)`
Miss path that records a fresh result.

#### `Phase.replay(...)`
Hit path over committed result.

#### `Phase.gen(...)`
Lowered machine body implementation from the `gen` spec.

#### `Phase.report(...)`
Stats and accounting extraction.

---

## Machine body semantics

The public body form is still called `gen`, but it should not be understood as
“just a hand-written `next()` callback”.

It is better understood as:

> the declared generation logic for one phase machine

The body should receive explicit typed handles:

```lua
gen = function(P, S, emit, R)
  ...
end
```

Where:

- `P` is a typed view of `Phase.Param`
- `S` is a typed view of `Phase.State`
- `emit(item)` is the output continuation / sink edge
- `R` is a runtime helper namespace

### What `emit` returns

`emit(item)` returns a control code:

- `iw.CONTINUE()`
- `iw.BREAK()`
- `iw.HALT()`

These are the same logical control forms used by the traversal algebra.

### What `R` should contain

Likely helpers:

- `R.emit_children(phase, child_base, child_count, emit)`
- `R.replay(result_ref, emit)`
- `R.record_append(item)`
- `R.publish_result(...)`
- `R.lookup_child(...)`
- `R.touch(entry_ref)`
- `R.fail(...)`
- `R.stop(code)`

The body should be explicit about machine control, but not forced to manually
spell every low-level storage detail.

---

## Cache and result policy

Unlike pvm, the successor should make cache ownership policy explicit in the
spec.

### Example

```lua
cache = {
  args   = "last",
  policy = "bounded_lru",
  cost   = "bytes",
}

result = {
  storage = "slab_seq",
  item_t  = Cmd,
  inline_capacity = 8,
}
```

### `args`
Controls how extra call arguments affect key retention.

- `full` — full arg-keyed caching
- `last` — retain only the most recent arg dimension per key root
- `none` — do not cache by args

This is the bounded-memory successor to the unbounded arg history problem.

### `policy`
Controls ownership and eviction.

Likely first-class policies:

- `bounded_lru`
- `latest_only`
- `ephemeral`
- `pinned`

### `cost`
Controls what the runtime uses for pressure accounting.

Likely:

- `bytes`
- `entries`
- explicit hook

---

## Hit / shared / miss in the new model

The public phase spec should still preserve the three important operational
cases from pvm:

- **hit**
- **shared**
- **miss**

But they should no longer be explained as “three branches returning three kinds
of Lua triplets”.

They should be explained as runtime source selection.

### Hit

Lookup finds a committed replayable result.
The runtime chooses a replay source and lowers it into the terminal.

### Shared

Lookup finds an in-flight recording already producing a result for the same key.
The runtime attaches a shared reader / replay cursor to that in-flight state.

### Miss

Lookup allocates recording state, runs the machine body, and records items into
transient/publishable storage.

If full commit succeeds, the result becomes a stable replay source.

This framing is much cleaner than treating hit/shared/miss as three unrelated
execution APIs.

---

## How traversal fusion fits underneath

This is the critical architectural point.

The public spec can be explicit about `param`, `state`, and `gen`, while the
internal execution substrate is still the fused traversal algebra described in
`new/WATJIT_ITER_ALGEBRA.md`.

That means:

- replay is a source
- recording is a sink/publication seam
- `emit` is a sink edge
- terminals are fused reducers/drains
- source/transducer/terminal composition remains the operational substrate

So the machine-spec layer does **not** imply a return to a purely pull-style
runtime wrapper architecture.

It just gives the author a better way to define runtime machines.

---

## Suggested auxiliary specs

Besides `iw.phase`, the public surface should likely also expose:

### `iw.scalar_phase { ... }`

For one-value-per-key boundaries.

```lua
local solve = iw.scalar_phase {
  name = "solve",
  key_t = NodeRef,
  value_t = Layout,

  param = {
    node  = NodeRef,
    max_w = wj.i32,
  },

  cache = {
    args   = "last",
    policy = "bounded_lru",
  },

  compute = function(P, R)
    ...
  end,
}
```

### `iw.terminal { ... }`

For sinks that consume flat items.

```lua
local draw = iw.terminal {
  name = "draw",
  item_t = Cmd,

  state = {
    i = wj.i32,
  },

  step = function(S, cmd, R)
    ...
  end,
}
```

### `iw.result { ... }`

Explicit result storage templates.

```lua
local CmdSeq = iw.result {
  kind = "seq",
  item_t = Cmd,
  storage = "slab",
  inline_capacity = 4,
}
```

### `iw.runtime { ... }`

Explicit bounded-memory runtime declaration.

```lua
local rt = iw.runtime {
  memory = {
    result_bytes = 64 * 1024 * 1024,
    temp_bytes   =  4 * 1024 * 1024,
  },

  tables = {
    entry_capacity = 1 << 20,
  },
}
```

---

## Worked examples

## Example 1: a trivial leaf phase

```lua
local lower_button = iw.phase {
  name = "lower_button",
  key_t = NodeRef,
  item_t = Cmd,

  param = {
    node = NodeRef,
  },

  state = {
    pc = wj.u8,
  },

  result = {
    storage = "slab_seq",
    item_t  = Cmd,
  },

  cache = {
    args   = "none",
    policy = "bounded_lru",
  },

  gen = function(P, S, emit, R)
    local cmd = R.make_rect_cmd(P.node)
    return emit(cmd)
  end,
}
```

## Example 2: a container phase

```lua
local lower_row = iw.phase {
  name = "lower_row",
  key_t = NodeRef,
  item_t = Cmd,

  param = {
    node = NodeRef,
  },

  state = {
    pc      = wj.u8,
    child_i = wj.i32,
  },

  result = {
    storage = "slab_seq",
    item_t  = Cmd,
  },

  cache = {
    args   = "none",
    policy = "bounded_lru",
  },

  gen = function(P, S, emit, R)
    return R.emit_children("lower", P.node.children, emit)
  end,
}
```

## Example 3: width-dependent measured phase

```lua
local measure = iw.scalar_phase {
  name = "measure",
  key_t = NodeRef,
  value_t = Size,

  param = {
    node  = NodeRef,
    max_w = wj.i32,
  },

  cache = {
    args   = "last",
    policy = "latest_only",
  },

  compute = function(P, R)
    return R.measure_node(P.node, P.max_w)
  end,
}
```

This explicitly encodes the “volatile width constraint” policy in the boundary
spec instead of letting it become an accidental memory leak.

---

## Migration intent from pvm

This design is not trying to preserve the exact pvm call syntax.

It is trying to preserve the important semantics:

- structural keying
- hit/shared/miss behavior
- lazy / streamed production
- replay of flat committed outputs
- partial consumption correctness
- bounded ownership policy
- explicit reuse diagnostics

### Old pvm idea

```lua
local lower = pvm.phase("lower", handlers)
for _, cmd in lower(root) do
  draw(cmd)
end
```

### New iwatjit idea

```lua
local lower = iw.phase {
  name = "lower",
  ...
}

local draw = iw.terminal {
  name = "draw",
  ...
}

lower:run(rt, {
  node = root_ref,
}, draw)
```

The authoring surface changes because the runtime contract is now more explicit.
That is a feature, not a regression.

---

## What not to do

### Wrong: make `iwatjit` just a thin prettified wrapper over raw `watjit`

`iwatjit` should be a real machine-spec DSL.

### Wrong: rebuild a purely host-style iterator wrapper stack

The internal substrate should stay fused and compiled.

### Wrong: hide memory/result policy outside the phase spec

If retention policy matters, it belongs in the declaration.

### Wrong: rely on closures as hidden machine state

If state matters, it belongs in `state` or `result` or explicit runtime tables.

### Wrong: force every user to hand-build struct layouts that the phase spec
already knows

The whole point of the DSL is to synthesize those layouts from the machine
schema.

---

## The thesis

The correct public shape for a pvm successor is not “raw `watjit`, but with
memoization”.

It is:

> a declarative machine-spec DSL where phase boundaries explicitly declare
> `param`, `state`, `result`, and cache policy, and where those specs generate
> the runtime structs and machine kernels automatically.

And the correct internal shape is not “a direct port of triplet pull wrappers”.

It is:

> a fused traversal/replay substrate where replay is a source, recording is a
> sink/publication seam, and hit/shared/miss are runtime source-selection
> concerns.

That combination — **spec-first public authoring, fused traversal internals** —
is the right architectural direction for the next `iwatjit`.
