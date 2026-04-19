# watjit as a proper low-level Lua-native language

*Target design document.*

This document describes the intended end state for `watjit` as a real low-level
language embedded in Lua. It is not a milestone plan. It is the target.

For the current implemented surface in the repo, see `watjit/README.md`.

---

## Table of contents

1. [What watjit should be](#what-watjit-should-be)
2. [Current status snapshot](#current-status-snapshot)
3. [The core split: Lua builds, watjit runs](#the-core-split-lua-builds-watjit-runs)
4. [Design goals](#design-goals)
5. [Language principles](#language-principles)
6. [Type system target](#type-system-target)
7. [Values, lvalues, and assignment](#values-lvalues-and-assignment)
8. [Integer and bit-level operations](#integer-and-bit-level-operations)
9. [Conversions and casts](#conversions-and-casts)
10. [Memory model target](#memory-model-target)
11. [Layouts: struct, array, union, enum](#layouts-struct-array-union-enum)
12. [Control flow target](#control-flow-target)
13. [SIMD target](#simd-target)
14. [Functions, modules, imports, exports](#functions-modules-imports-exports)
15. [Lua-native surface design](#lua-native-surface-design)
16. [The standard low-level library watjit should ship](#the-standard-low-level-library-watjit-should-ship)
17. [Optimization and staging model](#optimization-and-staging-model)
18. [Diagnostics and introspection](#diagnostics-and-introspection)
19. [Implementation notes](#implementation-notes)
20. [Example target style](#example-target-style)
21. [The thesis](#the-thesis)

---

## What watjit should be

watjit should be a **proper low-level language** embedded in Lua.

It should be good at writing:

- allocators
- hash tables
- caches
- parsers
- bytecode interpreters
- runtime metadata systems
- SIMD kernels
- specialized terminals
- deterministic memory subsystems
- staged machine generators

It should not be understood primarily as:

- “a Lua DSL that emits WAT”
- “a small kernel toy”
- “a thin wrapper over Wasmtime”

Those are implementation facts. The architectural role is bigger:

> watjit is a low-level systems language whose macro system is Lua.

That means it should aim to replace a large class of code currently written in:

- C
- Terra
- ad hoc Lua+FFI kernels
- handwritten runtime internals

Not by imitating their syntax, but by offering the right combination of:

- explicit machine semantics
- typed memory and layout control
- good runtime/data-structure libraries
- Lua-native staging and composition

---

## Current status snapshot

A substantial subset of this document is now implemented in the repo.

Implemented today:

- scalar integer types: `i8/i16/i32/i64`, `u8/u16/u32/u64`
- floats: `f32`, `f64`
- pointers: `ptr(T)`
- layouts: `struct`, `array`, `union`, `enum`, `tagged_union`
- packed/aligned layout control
- integer bit ops, shifts, rotates, signed/unsigned div/rem
- integer utility ops: `clz`, `ctz`, `popcnt`, `bswap`
- casts: `cast`, `trunc`, `zext`, `sext`, `bitcast`
- structured control: labels, block/loop/br/br_if, `goto_`, `switch`, break/continue sugar
- imports and cross-instance linking through Wasmtime externs
- SIMD arithmetic, comparisons, mask select, shuffle, and lane ops
- runtime helper libraries: arena, slab, lru, mem primitives, fixed-capacity hashtable
- stream and stream compilation support

Still better understood here as target-space / direction-space:

- richer SIMD coverage beyond the current vector families and ops
- more runtime libraries and higher-level low-level containers
- more import/binding ergonomics
- additional diagnostics and optimization passes
- any future backend/generalization work beyond the current Wasmtime-centered model

For the current concrete API, examples, and tested surface, use `watjit/README.md`.

## The core split: Lua builds, watjit runs

This is the central design rule.

### Lua is for:

- declarative specs
- specialization
- code generation
- library assembly
- schemas
- compile-time tables
- builders
- staging logic
- higher-order composition

### watjit is for:

- explicit types
- explicit values
- explicit memory
- explicit layout
- explicit control flow
- explicit effects
- explicit calls
- explicit machine-level semantics

Short version:

> **Lua builds the machine. watjit is the machine.**

This split must stay sharp. If watjit tries to become a second dynamic scripting
language, it loses focus. If Lua has to simulate machine semantics directly, the
system loses honesty and predictability.

---

## Design goals

watjit should feel:

### 1. Low-level
You can write allocators, metadata-packed structs, hash probes, buffer walkers,
SIMD kernels, and state machines without escaping to C.

### 2. Explicit
You can point to every important semantic fact:

- type
- layout
- size
- alignment
- address
- load/store
- branch
- conversion

### 3. Native to Lua
The surface should lean into Lua’s strengths:

- table specs
- callable objects
- metatables
- method syntax
- no-parens builder style
- closures as code builders

### 4. Small
The language core should stay compact and inspectable. A large part of the
power should come from libraries and staging, not from a huge compiler front-end.

### 5. Good for runtimes, not just kernels
watjit should excel not only at numeric loops, but at runtime construction:

- memory systems
- lookup structures
- caches
- staged execution machinery

### 6. Able to reduce C dependence materially
The better watjit gets, the less frequently this repo should need C.

---

## Language principles

### P1. Explicit machine semantics over hidden convenience
No hidden heap. No hidden object graph. No hidden shape changes. No magical
runtime reinterpretation.

### P2. Lua-native authoring over fake C syntax
Do not fight Lua. Do not bolt on awkward pseudo-C. Lean into:

- spec tables
- methods
- callable values/types
- field/index access
- closures

### P3. Data layout is first-class
A low-level language is not serious unless layouts are serious.

### P4. Effects must be visible
Loads, stores, calls, branches, casts, and vector ops should be explicit in the
surface or in the derived IR.

### P5. Libraries matter as much as syntax
To replace C in practice, watjit needs a strong standard low-level library, not
just a strong core syntax.

---

## Type system target

The type system should be small, explicit, and layout-oriented.

### Scalar integer types

```lua
wj.u8
wj.u16
wj.u32
wj.u64

wj.i8
wj.i16
wj.i32
wj.i64
```

### Floating-point types

```lua
wj.f32
wj.f64
```

### Pointer types

```lua
wj.ptr(T)
```

Optional later distinctions:

```lua
wj.addr      -- raw address-sized integer-ish storage handle
wj.rawptr    -- raw untyped pointer, if needed
```

If introduced, those distinctions must clarify semantics rather than create
type noise.

### Vector types

```lua
wj.simd.f32x4
wj.simd.f64x2
wj.simd.i32x4
```

Eventually also:

- unsigned vector lane types where relevant
- mask/vector condition types if needed by the backend model

### Layout types

```lua
wj.struct(...)
wj.array(...)
```

Eventually:

```lua
wj.union(...)
wj.enum(...)
wj.tagged_union(...)
```

### Boolean model
`bool` can exist as surface convenience, but the machine truth model should stay
crisp. If booleans are represented as integers in the backend, that should not
be hidden in a confusing way.

---

## Values, lvalues, and assignment

watjit should preserve a clean distinction between:

- host Lua values
- staged watjit values
- readable lvalues
- writable lvalues

### Declaration style
This surface is already good and should remain fundamental:

```lua
local i = wj.i32 "i"
local sum = wj.f64("sum", 0)
local p = wj.ptr(wj.u8) "p"
```

### Parameter style

```lua
params = { wj.i32 "a", wj.i32 "b" }
```

### Assignment style
The current callable-lvalue model is excellent and should remain canonical:

```lua
x(42)
mem[i](v)
node.count(node.count + 1)
```

Why this is right:

- it is valid Lua
- it is visually distinct from host assignment
- it preserves Lua-native syntax
- it works equally for locals, memory slots, and projected fields

### Reads
Reads should stay natural:

```lua
x
mem[i]
node.count
```

### Comparison and non-operator methods
Because Lua does not provide all operator hooks we want, methods are the right
place for many low-level operations:

```lua
x:eq(y)
x:lt(y)
x:ge(y)
```

That principle should be extended to bit ops, unsigned ops, and cast-like helpers.

---

## Integer and bit-level operations

This is the biggest gap between “good kernel DSL” and “proper low-level language”.

watjit needs a complete enough integer core to express:

- hashing
- masks
- bit packing
- probe logic
- parser state machines
- tagged metadata
- compact headers
- modulo arithmetic
- alignment arithmetic

### Required bitwise operations

```lua
x:band(mask)
x:bor(mask)
x:bxor(mask)
x:bnot()
```

Optional functional forms may also exist:

```lua
wj.band(a, b)
wj.bor(a, b)
wj.bxor(a, b)
wj.bnot(a)
```

But method form should feel primary.

### Required shifts and rotates

```lua
x:shl(n)
x:shr_u(n)
x:shr_s(n)
x:rotl(n)
x:rotr(n)
```

### Required remainder/division variants

```lua
x:div_u(y)
x:div_s(y)

x:rem_u(y)
x:rem_s(y)
```

### Required unsigned comparisons

```lua
x:lt_u(y)
x:le_u(y)
x:gt_u(y)
x:ge_u(y)
```

### Useful later integer ops

```lua
x:clz()
x:ctz()
x:popcnt()
x:bswap()
```

These are not luxuries. They are standard equipment for a language that wants
to replace C for systems code.

---

## Conversions and casts

watjit needs a crisp and explicit cast vocabulary.

### Proposed surface

```lua
wj.cast(T, x)     -- numeric or semantic conversion
wj.bitcast(T, x)  -- reinterpret bits
wj.trunc(T, x)    -- narrowing conversion
wj.zext(T, x)     -- zero extension
wj.sext(T, x)     -- sign extension
```

### Examples

```lua
local y = wj.zext(wj.u32, b)
local z = wj.trunc(wj.u16, x)
local bits = wj.bitcast(wj.u32, f)
```

### Design note
Do not overload all conversions onto the ordinary `wj.cast` surface. Low-level
code benefits from having semantic intent visible in the program.

---

## Memory model target

watjit’s memory model should support three layers cleanly.

### Layer 1: raw address arithmetic
This is for people writing allocators, caches, buffers, parsers, and metadata-packed runtimes.

Need good support for:

- explicit byte offsets
- explicit alignment
- explicit size reasoning
- raw address math

### Layer 2: typed projections
This is the ergonomic layer for real code.

```lua
local mem = wj.view(wj.i32, base, "mem")
mem[0](42)

local slot = Entry.at(base)
slot.key(123)
```

### Layer 3: memory-region abstractions
This is where watjit can eliminate lots of C.

It should be good at expressing and shipping:

- arena allocators
- slabs
- free lists
- ring buffers
- LRU metadata stores
- hash tables
- temp allocators
- append-only buffers

### Additional surface helpers
Useful memory-level helpers:

```lua
wj.offset(ptr, bytes)
wj.elem_offset(ptr, T, i)
wj.addr(lvalue)
wj.align_up(x, a)
wj.align_down(x, a)
```

Whether these are host helpers, staged helpers, or both depends on the use case,
but the vocabulary should exist.

### Byte-level views
Essential for real systems code:

```lua
local bytes = wj.view(wj.u8, base, "bytes")
```

Without this, many low-level tasks become awkward or impossible.

---

## Layouts: struct, array, union, enum

### Structs
The current `struct` direction is correct.

Target shape:

```lua
local Entry = wj.struct("Entry", {
  { "key",   wj.u32 },
  { "value", wj.u32 },
  { "state", wj.u8  },
}, {
  align = 8,
  packed = false,
})
```

Desired properties:

- predictable offsets
- visible `size`
- visible alignment
- field access by projection
- nested layout projection

### Arrays
Target shape remains simple:

```lua
local Slots = wj.array(Entry, 1024)
```

Need:

- correct size
- projection by `.at(base)`
- nested aggregate support

### Unions
Required for serious low-level work.

```lua
local Value = wj.union("Value", {
  { "i", wj.i32 },
  { "f", wj.f32 },
  { "p", wj.ptr(wj.u8) },
})
```

### Enums
These should be declarative and Lua-native.

```lua
local State = wj.enum("State", wj.u8, {
  Empty = 0,
  Live  = 1,
  Tomb  = 2,
})
```

Then used as plain constants:

```lua
slot.state(State.Live)
wj.if_(slot.state:eq(State.Tomb), function() ... end)
```

### Tagged unions
These are common enough to deserve a helper abstraction rather than being rebuilt by hand every time.

---

## Control flow target

Current structured forms are a good base:

- `for_`
- `while_`
- `if_`

A proper low-level language should add:

### break / continue
Possible surface shapes:

```lua
wj.for_(i, n, function(ctrl)
  wj.if_(done, function()
    ctrl:break_()
  end)
end)
```

or equivalent structured loop objects.

### switch

```lua
wj.switch(tag, {
  [State.Empty] = function() ... end,
  [State.Live]  = function() ... end,
}, function()
  ... -- default
end)
```

### branchless select

```lua
wj.select(cond, a, b)
```

or method equivalent.

### trap / unreachable / assert

```lua
wj.unreachable()
wj.trap("bad state")
wj.assert(cond, "overflow")
```

These are important in systems code and should not require host-side hacks.

---

## SIMD target

watjit already has the beginnings of a strong SIMD surface.

The target should include:

### Current fundamentals
- vector types
- splat
- load/store
- lane extract/replace
- arithmetic
- horizontal sum helper

### Required additions

#### Vector comparisons
```lua
v1:eq(v2)
v1:lt(v2)
v1:gt(v2)
```

#### Select/blend
```lua
V.select(mask, a, b)
```

#### Shuffle
```lua
V.shuffle(a, b, { 0, 1, 2, 3 })
```

#### Better reduction helpers
```lua
v:sum()
v:min()
v:max()
```

#### Tail handling helpers
Useful for writing kernels without lots of scalar cleanup boilerplate.

### Design note
SIMD should feel like a first-class low-level subsystem, not an afterthought.
The language should make it natural to write explicit microkernels.

---

## Functions, modules, imports, exports

A real low-level language should support complete subsystem construction.

### Functions
The current table-driven function spec is already in the right family:

```lua
wj.fn {
  name = "add",
  params = { wj.i32 "a", wj.i32 "b" },
  ret = wj.i32,
  body = function(a, b)
    return a + b
  end,
}
```

### Modules
Modules should eventually support clearer visibility control.

Target style:

```lua
local mod = wj.module {
  funcs = { helper, public_fn },
  exports = { "public_fn" },
}
```

### Imports
Need first-class imported functions.

```lua
local memcpy = wj.import {
  module = "env",
  name = "memcpy",
  params = { wj.i32, wj.i32, wj.i32 },
  ret = wj.i32,
}
```

### Memory and globals
Eventually, the module surface should be able to express a larger Wasm machine shape where needed, while still keeping the language small.

---

## Lua-native surface design

This is where watjit should deliberately lean into Lua’s strengths.

### Table-first declarative specs
Anything declarative should prefer table-based APIs.

Good:

```lua
wj.fn { ... }
wj.module { ... }
wj.struct("Entry", { ... })
```

### Callable objects
These are one of Lua’s best tricks and watjit should use them heavily.

Good examples:

```lua
wj.i32 "x"
wj.f64 "sum"
```

### No-parens style where it helps
Not for everything, but where it improves readability.

### Method syntax for low-level ops
Because Lua does not expose enough custom operators, methods are the correct place for:

- bit ops
- unsigned ops
- shifts
- special comparisons
- vector utilities

Examples:

```lua
hash:band(mask)
idx:rem_u(cap)
word:shr_u(5)
vec:sum()
```

### Do not imitate C too hard
watjit should not try to pretend Lua is C. That path usually produces bad embedded languages.

The right approach is:

- keep Lua visible
- keep machine semantics explicit
- let the embedding be a strength

---

## The standard low-level library watjit should ship

The standard low-level library is critical. Syntax alone will not replace C.

### Memory primitives
Need watjit-native implementations of:

- `memcpy`
- `memmove`
- `memset`
- `memcmp`
- byte copy/fill loops

### Memory/data-structure building blocks
Need high-quality versions of:

- arena
- slab
- free list
- ring buffer
- LRU
- hash table
- temp allocator
- append buffer

### Hashing utilities
Need a compact set of standard hashing/mixing helpers for:

- integers
- byte slices
- small fixed layouts

### Buffer utilities
Useful for parsers and runtime systems:

- byte cursor
- append buffer
- growable-ish policies built on fixed arenas where appropriate

### SIMD helpers
Small standard kernels and utilities so common patterns are not reimplemented everywhere.

### Why this matters
A low-level language replaces C not only by being expressive, but by making the common low-level tasks already solved inside the language ecosystem.

---

## Optimization and staging model

watjit should treat Lua as the meta layer for specialization.

### Good uses of Lua-side staging
- compile-time loops
- schema-driven generation
- kernel specialization by dimensions
- table-driven dispatch generation
- layout generation
- code library assembly

### Good uses of watjit-side semantics
- the final machine shape
- explicit values and memory accesses
- runtime control flow
- runtime arithmetic

### The right mental model
watjit should not try to become self-hosting source syntax inside Lua.
The strength is that Lua can already do the macro/meta job very well.

---

## Diagnostics and introspection

A proper low-level language needs good introspection.

### Should expose clearly
- generated WAT
- layout sizes and offsets
- module shape
- imported/exported functions
- memory sizes
- maybe estimated footprint of common structures

### Helpful extras
- IR dump
- validation helpers
- easier assertion failures on illegal staging patterns
- optional pretty printing for generated code objects

If people are writing runtimes in watjit, they need visibility into what is being built.

---

## Implementation notes

This section describes target implementation properties, not a staged delivery plan.

### 1. Keep the semantic core small
The core IR should stay compact and regular. Power should come from:

- a small explicit IR
- good low-level libraries
- Lua-side staging

not from a sprawling compiler front-end.

### 2. Integer ops must be first-class in the IR
Bit ops and unsigned ops cannot remain “later conveniences”. They are required
for the language to be credible as a systems language.

### 3. Unsignedness must be real
If unsigned semantics are only faked at the API level, low-level code becomes fragile.
They need first-class representation in the op model and emitter.

### 4. Layout metadata should be inspectable
Structs, arrays, unions, and enums should expose:

- size
- alignment
- field offsets
- representation details where relevant

### 5. Assignment machinery should continue to unify locals and memory
One of watjit’s best current design choices is that locals, view elements, and
projected fields all behave similarly as readable and callable writable things.
That uniformity should be preserved.

### 6. Library code should be written in watjit where possible
If an allocator, buffer, hash table, or lookup structure can be written cleanly
in watjit, it should be. That is how the language proves itself and reduces the
need for C.

### 7. Host boundary should stay explicit
The Wasmtime bridge should remain an honest boundary. Fast paths are good, but
semantics should not be hidden behind magical host behavior.

### 8. The language should stay Wasm-shaped, not C-shaped
watjit should become stronger by becoming more complete and more composable in
its own model, not by trying to mimic every surface habit of C.

### 9. Prefer method expansion over fake operators
Where Lua has no operator support, use methods. This keeps the surface simple,
explicit, and Lua-native.

### 10. Keep room for optimization passes
Even if early implementations are direct, the language design should not block:

- canonicalization
- simplification
- staging recognizers
- specialized terminal lowering
- pattern-driven rewrites

The existing stream specialization direction is a good precedent.

---

## Example target style

### Enum + struct + hash probe

```lua
local State = wj.enum("State", wj.u8, {
  Empty = 0,
  Live  = 1,
  Tomb  = 2,
})

local Slot = wj.struct("Slot", {
  { "state", State },
  { "key",   wj.u32 },
  { "value", wj.u32 },
})

local function mix32(x)
  x = x:bxor(x:shr_u(16))
  x = x * wj.u32(0x7feb352d)
  x = x:bxor(x:shr_u(15))
  x = x * wj.u32(0x846ca68b)
  x = x:bxor(x:shr_u(16))
  return x
end

local lookup = wj.fn {
  name = "ht_lookup",
  params = { wj.i32 "base", wj.u32 "key", wj.u32 "mask" },
  ret = wj.u32,
  body = function(base, key, mask)
    local slots = wj.view(Slot, base, "slots")
    local idx = wj.u32("idx", mix32(key):band(mask))
    local probe = wj.u32("probe", 0)
    local miss = wj.u32(0xffffffff)
    local out = wj.u32("out", miss)
    local active = wj.u32("active", 1)

    wj.while_(active:ne(0), function(ctrl)
      local slot = slots[idx]

      wj.if_(slot.state:eq(State.Empty), function()
        out(miss)
        active(0)
      end)

      wj.if_(slot.state:eq(State.Live), function()
        wj.if_(slot.key:eq(key), function()
          out(slot.value)
          active(0)
        end)
      end)

      wj.if_(active:ne(0), function()
        probe(probe + 1)
        idx((idx + 1):band(mask))
        wj.if_(probe:gt(mask), function()
          out(miss)
          active(0)
        end)
      end)
    end)

    return out
  end,
}
```

### Byte copy

```lua
local memcpy_u8 = wj.fn {
  name = "memcpy_u8",
  params = { wj.i32 "dst_base", wj.i32 "src_base", wj.u32 "n" },
  body = function(dst_base, src_base, n)
    local dst = wj.view(wj.u8, dst_base, "dst")
    local src = wj.view(wj.u8, src_base, "src")
    local i = wj.u32("i", 0)

    wj.for_(i, n, function()
      dst[i](src[i])
    end)
  end,
}
```

### Branchless select target style

```lua
local clamp = wj.fn {
  name = "clamp_i32",
  params = { wj.i32 "x", wj.i32 "lo", wj.i32 "hi" },
  ret = wj.i32,
  body = function(x, lo, hi)
    local y = wj.select(x:lt(lo), lo, x)
    return wj.select(y:gt(hi), hi, y)
  end,
}
```

This is the kind of code watjit should make natural.

---

## The thesis

> watjit should become a proper low-level language embedded in Lua: explicit in
> types, memory, layout, control flow, and machine effects; native to Lua in its
> authoring surface through table specs, callable typed objects, metatables,
> method-based operations, and Lua-powered staging. Its power should come not
> only from syntax, but from being able to express the runtime building blocks
> themselves — allocators, buffers, hash tables, metadata stores, SIMD kernels,
> and specialized terminals — directly in watjit. The better watjit gets, the
> less this codebase should need C.
