# iwatjit runtime layout

*Target/prototype design document.*

This document complements `new/IWATJIT_MACHINE_SPEC.md`.
It focuses on the generated runtime layouts implied by the machine-spec DSL.

The purpose of this document is simple:

> if `iwatjit` is a machine-definition layer, then the shapes of its runtime
> objects must be explicit, generated, and inspectable.

---

## Thesis

A bounded-memory pvm successor should not hide its runtime objects in closures,
Lua tables, and incidental helper state.

It should generate explicit typed layouts for:

- invocation params
- mutable machine state
- committed results
- cache entries
- live cursors
- status tags

That is the real meaning of saying `iwatjit` is a machine DSL.

---

## The generated object family

Given a declaration like:

```lua
local lower = iw.phase {
  name = "lower",
  key_t = NodeRef,
  item_t = Cmd,
  param = { ... },
  state = { ... },
  result = { ... },
  cache = { ... },
  gen = function(P, S, emit, R) ... end,
}
```

The runtime should synthesize a family of related layouts.

## 1. `Phase.Status`

A small enum describing lifecycle state.

Prototype members:

- `Empty`
- `Recording`
- `Live`
- `Shared`
- `Evicted`

This status enum should be used consistently across `Result`, `Entry`, and
`Cursor` metadata.

---

## 2. `Phase.Param`

The stable per-invocation environment.

This is the explicit replacement for the old vague “param role”.
Anything read by the machine body that is stable during a run belongs here.

Typical fields:

- source node reference
- width/height constraints
- theme or content-store handle
- extra explicit arg dimensions

Prototype rule:

- generated as a packed=`false` `watjit.struct`
- deterministic field order
- inspectable offsets and total size

### Field order rule

For spec stability, `iwatjit` should accept two forms:

### Explicit ordered form

```lua
param = {
  { "node", NodeRef },
  { "max_w", wj.i32 },
}
```

### Map form

```lua
param = {
  node = NodeRef,
  max_w = wj.i32,
}
```

Map form should be canonicalized in deterministic sorted-name order.
If order matters for readability or ABI expectations, use the explicit array
form.

---

## 3. `Phase.State`

The mutable machine cursor.

This is where suspended or resumable execution state lives.

Typical fields:

- program counter / tag
- child index
- replay cursor offset
- temporary traversal substate
- pending child slot

Prototype rule:

- generated as packed=`false`
- stable inspectable offsets
- no hidden closure state

---

## 4. `Phase.Result`

The committed replayable result descriptor.

The exact fields depend on the declared result policy.

### Scalar result shape

For scalar boundaries:

- `status`
- `value`
- `cost_bytes`

### Sequence result shape

For replayable flat sequences:

- `status`
- `len`
- `cap`
- `data`
- `cost_bytes`

Later this can be refined into more specialized variants:

- inline-small sequence
- slab-backed sequence
- arena-owned sequence
- external borrowed sequence

But the core principle stays the same:

> the committed replay form is explicit data, not an implicit Lua object graph.

---

## 5. `Phase.Entry`

Persistent cache entry metadata.

This object is the ownership/control record for a cached phase key.

Prototype fields:

- `status`
- `key`
- `arg_tag`
- `result`
- `lru_prev`
- `lru_next`
- `cost_bytes`

### Interpretation

- `key` — structural key root
- `arg_tag` — extra-arg discriminator / hash / mode-dependent stamp
- `result` — pointer/reference to committed result descriptor
- `lru_prev`, `lru_next` — bounded cache ownership links
- `cost_bytes` — accounting value used for eviction/reporting

This is the object that turns cache policy into explicit runtime data.

---

## 6. `Phase.Cursor`

Transient in-flight machine instance.

Prototype fields:

- `status`
- `param`
- `state`
- `entry`
- `result`
- `progress`

### Interpretation

- `param` — pointer/reference to current invocation param payload
- `state` — pointer/reference to mutable machine state payload
- `entry` — owning cache entry
- `result` — in-progress or target result descriptor
- `progress` — machine-local progress marker

The cursor is the bridge between the abstract machine declaration and the live
runtime currently stepping or replaying it.

---

## How these objects fit together

```text
Phase.Entry  --->  Phase.Result
     ^                ^
     |                |
     +---- Phase.Cursor ---+
             |             |
             v             v
         Phase.Param   Phase.State
```

This graph is the explicit runtime shape hidden implicitly inside the old GC
implementation style.

---

## Three lifetime classes

The layout family maps directly to three lifetime classes.

### Structural / policy lifetime

- phase descriptors
- enum/layout metadata
- cache tables

### Committed result lifetime

- `Entry`
- `Result`

### In-flight lifetime

- `Cursor`
- temp recording state
- transient param/state instances

This is the real runtime meaning of the earlier `gen / param / state` insight.

---

## Why generating these layouts matters

Because then `iwatjit` can expose real diagnostics.

Examples:

- `Phase.Param.size`
- `Phase.State.size`
- `Phase.Result.size`
- `Phase.Entry.size`
- `Phase.Cursor.size`
- total live entry bytes
- total committed result bytes
- temp cursor pressure
- average bytes per key

Without explicit generated layouts, those numbers are guesses.
With generated layouts, they are architecture facts.

---

## Relationship to `watjit`

`iwatjit` should not implement a second type/layout system.

Instead:

- `iwatjit` spec tables normalize declarations
- `watjit.struct` / `watjit.enum` build the concrete layouts
- wrapper helpers build concrete functions from those layouts

So the stack stays clean:

- `watjit` builds layouts/functions
- `iwatjit` decides which layouts/functions should exist

---

## Prototype status

The current prototype in `iwatjit/init.lua` already generates:

- `Status`
- `Param`
- `State`
- `Result`
- `Entry`
- `Cursor`

and exposes wrapper-generation helpers:

- `phase:gen_fn { ... }`
- `scalar_phase:compute_fn { ... }`
- `terminal:step_fn { ... }`

That is intentionally modest.

It proves the key point:

> machine specs can generate both structs and functions from one declaration.

The next step is not “more wrappers”.
It is attaching real bounded replay/recording runtime behavior to this layout
family.

---

## Direction summary

The correct runtime-layout direction for `iwatjit` is:

- explicit generated layout families per machine
- explicit status/result/entry/cursor objects
- policy encoded in data shape, not informal convention
- bounded-memory ownership reflected directly in the layout graph
- `watjit` as the low-level generator for all of it

That is how the pvm successor becomes a real machine system rather than a pile
of clever runtime tables.
