# asdljit

*Target design document.*

This document describes the intended native ASDL implementation direction for
this repo.

The core claim is simple:

> If ASDL is the centerpiece, then ASDL itself should eventually have a native
> `watjit`-powered runtime.

Not just faster phases.
Not just faster caches.
The **ASDL value world itself** should become a compiled, canonical,
handle-based runtime.

---

## Table of contents

1. [Why this exists](#why-this-exists)
2. [The thesis](#the-thesis)
3. [What must stay the same semantically](#what-must-stay-the-same-semantically)
4. [What changes operationally](#what-changes-operationally)
5. [Why ASDL runtime speed matters more than schema parse speed](#why-asdl-runtime-speed-matters-more-than-schema-parse-speed)
6. [The target stack](#the-target-stack)
7. [Runtime model](#runtime-model)
8. [Schema compilation model](#schema-compilation-model)
9. [Native constructors](#native-constructors)
10. [Native uniqueness / interning](#native-uniqueness--interning)
11. [Canonical list storage](#canonical-list-storage)
12. [Structural update](#structural-update)
13. [Raw getters and hot-kernel hooks](#raw-getters-and-hot-kernel-hooks)
14. [Type tags, handles, and dispatch](#type-tags-handles-and-dispatch)
15. [Schema parsing](#schema-parsing)
16. [Relationship to pvm](#relationship-to-pvm)
17. [Relationship to iwatjit](#relationship-to-iwatjit)
18. [Suggested implementation phases](#suggested-implementation-phases)
19. [Non-goals](#non-goals)
20. [The thesis again](#the-thesis-again)

---

## Why this exists

Today the repo has a very strong architectural center:

- ASDL defines the value world
- `pvm` caches on ASDL identity
- structural sharing is expressed through ASDL `unique`
- `pvm.with(...)` depends on ASDL immutability + canonical reconstruction
- raw getters (`__raw`, `__raw_<field>`) already expose what the hot path wants

That means ASDL is not “just data syntax”.
It is the actual identity and reuse substrate of the whole system.

If that is true, then the long-term performance architecture should not stop at:

- faster terminals
- faster replay
- faster phase caches

It should continue one layer deeper:

> the ASDL runtime itself should become a compiled runtime.

That is what `asdljit` means.

---

## The thesis

`asdljit` should be:

> a native, handle-based, canonical ASDL runtime built on `watjit`, preserving
> ASDL semantics exactly while replacing the current GC-table implementation
> with compiled constructors, native interning, canonical list storage, and
> raw typed accessors.

This is not “replace ASDL with mutable structs”.
It is:

- same semantics
- better machinery

---

## What must stay the same semantically

This part is non-negotiable.

A native ASDL runtime is only correct if it preserves the existing ASDL meaning.

### Must remain true

- **Immutability**
- **`unique` means canonical structural interning**
- **lists are canonicalized where uniqueness requires it**
- **sum variants remain real type distinctions**
- **singleton no-field variants remain canonical singleton values**
- **`pvm.with(node, overrides)` remains structural update**
- **field validation and type integrity remain constructor properties**
- **identity of unchanged structure remains stable**

### Must not become

- mutable objects with best-effort deduplication
- plain ids with ad hoc side lookup semantics
- user-managed struct lifetimes that bypass structural meaning
- optional “unique if you remember to call hashcons()” behavior

So the rule is:

> **change the implementation, not the semantics**

---

## What changes operationally

Today the active backend is GC-managed Lua objects with code-generated
constructors and interning tries.

The target backend changes that to:

- native typed storage
- handle-based value identity
- native interning tables
- native canonical list storage
- native field accessors
- native update kernels

So instead of “the ASDL value is the Lua table”, the model becomes:

> the ASDL value is a stable handle into a native canonical store

Lua-facing objects may still exist as thin wrappers when needed, but the true
identity substrate becomes native.

---

## Why ASDL runtime speed matters more than schema parse speed

There are two separate performance questions.

### A. schema parse / definition speed
This is startup-time / define-time cost.
Usually paid once.

### B. ASDL value runtime speed
This is hot-path cost.
Paid constantly:

- every constructor call
- every `with`
- every uniqueness lookup
- every field access in hot reducers
- every phase key lookup based on ASDL identity

The second one matters far more.

So `asdljit` should prioritize:

1. native constructors
2. native uniqueness/interning
3. native canonical lists
4. native raw getters
5. native structural update

Native schema-string parsing is good and should happen eventually, but it is not
where the biggest runtime payoff is.

---

## The target stack

The intended layering should be:

```text
watjit
  ↓
asdljit
  ↓
pvm / iwatjit
```

### `watjit`
Owns:

- low-level types
- memory/layouts
- functions
- quotes
- hash tables
- slab/arena helpers
- bytes/parser helpers

### `asdljit`
Owns:

- schema compilation
- canonical ASDL storage
- constructors
- uniqueness
- list interning
- `with`
- raw getters
- type/variant descriptors

### `pvm` / `iwatjit`
Consume:

- canonical ASDL handles
- raw getters
- type tags / descriptors

That is the clean architecture.

---

## Runtime model

At runtime, a native ASDL world should have at least these conceptual pieces.

## 1. Schema descriptor block

One per defined schema universe.
Contains:

- type descriptors
- field descriptors
- variant descriptors
- constructor metadata
- list element-type metadata
- singleton handles

## 2. Canonical node stores

Per product type / variant family.
Each entry stores:

- type tag / variant tag
- field payload refs / scalars
- maybe hash
- maybe cached class/descriptor ref

## 3. Canonical list stores

Per element type or per normalized list family.
Each entry stores:

- length
- element refs/scalars
- maybe hash

## 4. Intern tables

For `unique` values, keyed structurally.
Likely:

- per-type open-addressing tables
- per-list-type open-addressing tables

## 5. Handle namespace

A handle is the stable identity of an ASDL value.

A handle could be:

- a tagged integer
- or `(kind, slot)` encoded into one integer
- or a small struct-like value with type+slot

The exact encoding is an implementation detail.
The semantics are:

- stable while live
- canonical for `unique`
- cheap to compare
- cheap to hash

---

## Schema compilation model

Input:

- ASDL schema string

Output:

- compiled schema plan
- generated constructor/update/getter kernels
- runtime descriptor objects

There are two stages.

### Stage 1: front-end schema parse
Turn source text into a schema AST / IR.

### Stage 2: schema lowering
Lower schema IR into:

- type ids
- variant ids
- field layouts
- normalization plans
- constructor/interner plans
- list interner plans
- raw getter plans

This second stage is where `watjit` should start to matter heavily.

---

## Native constructors

A constructor for a `unique` product type should do the same logical work as the
current system.

### Logical steps

1. validate/coerce each field
2. canonicalize child lists if needed
3. build structural key
4. probe native intern table
5. return existing canonical handle on hit
6. allocate/store on miss
7. publish handle into intern table
8. return canonical handle

### Important point

This should still be **constructor-driven semantics**.
Users should not need to manually “intern” after constructing.

That is exactly the current good property of ASDL and must survive.

---

## Native uniqueness / interning

This is the heart of the runtime.

### Product-type uniqueness

For a type like:

```asdl
Button = (string tag, number w, number h, number rgba8) unique
```

interner key is effectively:

```text
(tag, w, h, rgba8)
```

### Sum-type uniqueness

For a sum variant:

```asdl
Widget = Button(...) unique | Row(Widget* children) unique
```

each variant gets its own type/variant identity and own constructor plan.

### Singleton variants

For no-field variants:

- one stable singleton handle
- no constructor allocation after init

### Intern table design

Likely MVP:

- open addressing
- linear probing
- fixed-capacity or growable by controlled rehash
- keys stored structurally via field refs/scalars

Longer-term:

- per-type load-factor management
- byte accounting
- maybe tombstones / rehash policy

---

## Canonical list storage

Lists are essential.
They are not a side detail.

A lot of ASDL structure is really:

- product fields
- plus recursive child lists

If lists are not canonicalized, then node uniqueness becomes weaker and reuse
collapses.

### Native list runtime should provide

- canonical list handles
- length metadata
- contiguous element storage or slab-chunk storage
- structural interning by element sequence

### Required semantics

If two lists have the same canonical element sequence, and uniqueness requires
canonicalization, they must resolve to the same canonical list handle.

### Why this matters to pvm/iwatjit

Because list identity is often subtree identity.
If list identity is unstable, phase reuse suffers badly.

---

## Structural update

`pvm.with(node, overrides)` is one of the best parts of the current system.
That exact semantic operation must remain.

### Native implementation model

For node handle `h`:

1. read old fields from `h`
2. apply explicit overrides
3. call the same canonical constructor kernel
4. get canonical result handle back

That gives:

- unchanged fields preserve identity transitively
- changed fields produce a new canonical value
- structure-sharing survives naturally

This is the same trick as today, just faster.

---

## Raw getters and hot-kernel hooks

The current runtime already tells us what hot kernels need.

### Existing conceptual hooks

- `node:__raw()`
- `node:__raw_<field>()`

A native backend should provide equivalents.

### Target semantics

#### Scalar field unpack

```lua
local a, b, c = node:__raw()
```

Should cheaply expose scalar/product fields in schema order.

#### List field access

```lua
local buffer, start, len, present = node:__raw_children()
```

Should cheaply expose:

- storage base / pointer / handle
- start offset
- length
- optional presence

The precise surface may change slightly, but the **hot information content**
should remain the same.

These hooks are how reducers and phase handlers stay fast.

---

## Type tags, handles, and dispatch

A native ASDL runtime should make dispatch cheaper and more explicit.

### Likely runtime metadata

Per value handle, we want access to:

- type id
- variant id
- schema descriptor ref

This enables:

- fast type switch dispatch
- fast handler lookup
- fast singleton comparison
- cheap schema-local introspection

### Handle design possibilities

#### Option A: tagged integer handle
Cheap and simple.
Good for hashing and comparisons.

#### Option B: lightweight wrapper object over integer handle
Good if Lua-facing ergonomics still want methods/metatables.

Most likely the runtime wants integer handles internally, with optional Lua
wrapper views at the boundary.

---

## Schema parsing

Yes, the schema string itself can eventually be parsed fast too.

Possible route:

- `watjit.bytes`
- native lexer over `u8*`
- native parser for the ASDL grammar
- direct compiled schema-plan builder

But again, the important priority is:

> native value runtime before native schema parsing

A fast schema parser is nice.
A fast canonical constructor runtime changes everything.

---

## Relationship to pvm

`pvm` should be able to consume `asdljit` values with the same semantics it
expects today.

That means `pvm` should still get:

- canonical identity
- stable structural sharing
- class/tag dispatch
- raw field access
- `with` semantics

The difference is that the underlying identity is now a native handle world,
not a GC-table world.

This is how `pvm` could keep its current architecture while getting a better
value substrate.

---

## Relationship to iwatjit

This is where the biggest payoff lands.

If `iwatjit` consumes native ASDL handles directly, then:

- structural cache keys become native handles
- native cache tables become the default path
- replay/cursor/runtime layers stop bridging back and forth to GC tables
- the whole system becomes more coherent

In other words:

> `asdljit` is the missing native identity substrate for `iwatjit`

Without it, `iwatjit` still depends on GC-backed ASDL identity for the
centerpiece structural-sharing story.

With it, the whole stack can become native all the way down.

---

## Suggested implementation phases

## Phase 1 — native handle-bearing backend MVP

Goal:

- per-type ids
- stable node handles
- native constructor interning
- native raw field access
- native `with`

This is the smallest version that can start replacing the current identity
substrate.

## Phase 2 — native canonical lists

Goal:

- canonical list handles
- structural list interning
- hot list raw getters

This is mandatory for real recursive tree performance.

## Phase 3 — generated schema-specific kernels

Goal:

- generated constructor/update/getter code from schema plan
- fast variant/tag dispatch support
- singleton initialization

## Phase 4 — pvm / iwatjit integration path

Goal:

- let `pvm` cache on native handles
- let `iwatjit` cache on native handles
- benchmark parity and then superiority

## Phase 5 — native schema parser (optional but desirable)

Goal:

- fast lexer/parser for schema strings
- direct compiled schema-plan production

---

## Non-goals

`asdljit` should not become:

- a different type system unrelated to ASDL
- a mutable scene graph API
- a user-facing manual memory management API for normal authored values
- an excuse to weaken `unique`
- “just ids, trust me” semantics

The whole point is to preserve the good ASDL meaning while improving the
implementation substrate.

---

## The thesis again

If ASDL is truly the centerpiece of this architecture, then the endgame is not
just faster phase caches.

It is:

> **a native ASDL runtime built on `watjit`, with canonical constructors,
> structural interning, canonical list storage, handle-based identity, and raw
> hot-path accessors, consumed directly by `pvm` and `iwatjit`.**

That is the path that keeps the current semantics and lets the whole stack get
faster together.
