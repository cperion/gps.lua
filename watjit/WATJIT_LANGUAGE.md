# Watjit: the language underneath iwatjit

This document recontextualizes the old speculative `archive/iwatjit_retired/IWATJIT.md` from the perspective of the code that actually exists today.

That archive file described a future `iwatjit`: a pvm replacement, built as a memoized phase runtime on top of deterministic typed memory.

That layering matters:

- **pvm** was the original memoized phase boundary framework
- **iwatjit** was the intended replacement runtime for pvm
- **watjit** is the low-level language and machine substrate underneath

`watjit/` is the concrete active result that actually exists in this repo today.

So the key update is:

> iwatjit was the planned pvm replacement.
> watjit is the language layer underneath that made such a replacement possible:
> a typed low-level toolkit in Lua that stages code to WAT/Wasmtime, with
> explicit layouts, deterministic memory helpers, stream compilation, and
> native kernels.

Watjit is not itself the pvm replacement. It is the substrate below that layer.

- **pvm** answers: how should authored intent compile incrementally?
- **iwatjit** aimed to answer: how should pvm's runtime be rebuilt on explicit memory?
- **watjit** answers: what should the compiled machine layer and implementation language look like?

pvm gave us the compiler pattern. iwatjit was the replacement-runtime ambition. watjit gives us the machine substrate.

---

## 1. Status

The old `iwatjit` effort is retired.

But it is important to say precisely what it was: `iwatjit` was meant to be a **pvm replacement**.

What survives from that effort in active code is not the full replacement runtime. What survives is the language and substrate work that had to exist underneath it:

- explicit memory instead of hoping GC does the right thing
- typed layouts instead of ad hoc Lua tables in hot paths
- reusable allocators instead of special-purpose cache internals
- compiled kernels instead of runtime interpretation
- flat executable streams instead of recursive runtime rediscovery

Those ideas now live in `watjit/` as a standalone toolkit.

This is the correct shape.

The earlier design tried to jump directly from pvm to a fully native incremental cache runtime. The current implementation took the right path instead: build the substrate first, make it independently useful, and only then build higher-level systems on top of it.

---

## 2. What watjit is

`watjit` is a Lua-native systems-language toolkit that stages typed code to WAT and runs it through Wasmtime.

It currently provides:

### Typed scalar values

- `i8 i16 i32 i64`
- `u8 u16 u32 u64`
- `f32 f64`
- `ptr(T)`

### Typed layouts

- `struct`
- `array`
- `union`
- `enum`
- `tagged_union`

### Low-level structured control flow

- `if_`
- `for_`
- `while_`
- `block`
- `loop`
- `br`
- `br_if`
- `goto_`
- `switch`

### Function/module construction

- `fn`
- `import`
- `module`
- WAT emission
- Wasmtime-backed compilation/instantiation

### Deterministic runtime helpers

- `arena`
- `slab`
- `lru`
- `mem`
- `hashtable`

### Stream staging

- `stream`
- `stream_compile`

### SIMD

- vector types
- vector load/store
- lane ops
- comparisons
- mask select
- shuffle
- horizontal sum helpers

This is already enough to write real low-level kernels in a typed, layout-aware, memory-explicit style from Lua.

---

## 3. The redesign: from iwatjit plan to watjit reality

The archive design was centered on one hypothetical library: `iwatjit`.

That original intent should be preserved: `iwatjit` was the planned native-memory **replacement for pvm**.

What changed is not the layering, but the implementation path.

The implemented redesign is:

> if you want a real pvm replacement runtime, you first need the language,
> layouts, allocators, streams, and codegen substrate underneath it.

That is what `watjit/` became.

| Retired `iwatjit` plan | Current `watjit` reality |
|---|---|
| Build a pvm replacement runtime | Build the language/toolkit needed underneath such a runtime |
| Three-arena cache runtime as the headline feature | Reusable arena/slab/lru/hashtable libraries as standalone parts |
| Native machinery mostly hidden behind phase APIs | Native machinery directly authorable in Lua |
| Success means a full `iwatjit` runtime | Success means a solid machine substrate that a future runtime could use |
| Cache runtime and substrate developed together | Substrate built first, as its own library |
| Mostly speculative architecture | Implemented modules with tests |

This is the redesign.

The old document imagined the replacement runtime first.
The new repo reality built the layer underneath first.

---

## 4. The watjit architecture

Watjit has five layers.

### 4.1 Lua as metalanguage

Lua is used to specialize and assemble programs.

You do not write strings of WAT by hand. You write Lua that builds typed expressions, layouts, functions, and modules.

```lua
local wj = require("watjit")

local add = wj.fn {
    name = "add",
    params = { wj.i32 "a", wj.i32 "b" },
    ret = wj.i32,
    body = function(a, b)
        return a + b
    end,
}
```

Lua stays the host language. Watjit supplies the staged low-level target language.

### 4.2 Typed values and layouts

The core unit is not a Lua table. It is a typed value or typed layout.

```lua
local Entry = wj.struct("Entry", {
    { "tag", wj.u8 },
    { "value", wj.u32 },
})
```

Layouts know their size, alignment, and field offsets. This matters because memory is explicit and codegen is layout-driven.

### 4.3 Structured low-level control

Watjit gives structured low-level control flow that still lowers cleanly to Wasm.

```lua
local sum_to = wj.fn {
    name = "sum_to",
    params = { wj.i32 "n" },
    ret = wj.i32,
    body = function(n)
        local i = wj.let(wj.i32, "i")
        local acc = wj.let(wj.i32, "acc", 0)
        wj.for_(i, n, function()
            acc(acc + i)
        end)
        return acc
    end,
}
```

This is not a macro veneer over Lua execution. It is staged control that emits real target code.

### 4.4 Deterministic memory libraries

This is where watjit becomes the real machine substrate.

The runtime helpers are concrete, standalone, and tested:

- **arena** — bump allocation + reset
- **slab** — fixed-size slot allocation
- **lru** — O(1) usage ordering metadata
- **hashtable** — fixed-capacity open-addressing `i32 -> i32`
- **mem** — basic memory primitives

These are not hypothetical internals of a future runtime. They are reusable libraries you can compose today.

```lua
local ht = wj.hashtable("ht", 1024)
local mod = wj.module(ht:funcs(), {
    memory_pages = wj.pages_for_bytes(ht.memory_bytes),
})
```

That is a major architectural correction from the archive design: the substrate exists independently of any one framework story.

### 4.5 Streams and compiled terminals

The closest current descendant of pvm's execution model is not a phase cache API. It is `stream` + `stream_compile`.

A stream plan can be built compositionally:

```lua
local S = wj.stream

local plan = S.range(wj.i32, wj.i32(0), wj.i32(16), wj.i32(1))
    :map(wj.i32, function(v) return v * wj.i32(2) end)
    :filter(function(v) return v:gt(0) end)
```

Then compiled into a specialized terminal:

```lua
local SC = wj.stream_compile

local sum = SC.compile_sum {
    name = "sum_evenish",
    params = {},
    ret = wj.i32,
    init = 0,
    build = function()
        return plan
    end,
}
```

This matters because it keeps the important pvm lesson:

> execution should consume a flat executable stream, not rediscover recursive source meaning at runtime.

In pvm that flat stream came from memoized phases over ASDL.
In watjit it comes from staged stream plans and compiled terminals.

---

## 5. What carried forward from pvm

Watjit is not the pvm replacement itself. It carries forward the machine-side lessons that the planned `iwatjit` replacement needed.

What carries forward is the architectural discipline:

### 5.1 Flat execution wins

pvm taught that the runtime should consume flat executable facts.
Watjit follows that directly.

Its stream layer and compiled terminals move toward the same end state:

- specialize early
- flatten before execution
- make runtime loops simple
- remove redispatch from the hot path

### 5.2 Separate authored structure from machine structure

pvm's source ASDL and phase boundaries separate domain meaning from execution facts.
Watjit continues the split at the lower layer:

- high-level authored structure belongs above
- low-level layouts, buffers, and kernels belong below

Watjit does not replace the need for good source modeling. It replaces ad hoc low-level execution code.

### 5.3 Memory policy must be explicit

The old `iwatjit` document was absolutely right about one thing: explicit lifetimes and explicit memory policy are better than hidden GC coupling in hot systems.

Watjit realizes that idea concretely:

- capacity is explicit
- memory footprint is inspectable
- layouts are stable
- allocators are deterministic

### 5.4 Keep the layers honest

pvm is a framework-level architectural primitive.
iwatjit was meant to be a replacement runtime at that same architectural level.
Watjit is the machine-layer toolkit underneath.

That division is healthy.

It keeps `watjit/` standalone and reusable, exactly as it should be.

---

## 6. What changed from the archive thesis

The archive `IWATJIT.md` made several bets. Some were right in spirit but wrong in shape.

### 6.1 Right insight: typed deterministic memory

Correct, and now implemented.

Watjit's arenas, slabs, LRU metadata, typed layouts, and fixed-capacity hashtable are the concrete version of that insight.

### 6.2 Right insight: native hot paths

Correct, and now implemented more generally than originally planned.

Instead of hardcoding only a memoized phase runtime hot path, watjit lets you author arbitrary low-level kernels.

### 6.3 The replacement-runtime ambition was right; the implementation had to start lower

The mistake was not wanting an `iwatjit` replacement runtime.
The mistake would have been trying to build it before the substrate existed.

So the correct move was to first build:

- types
- layouts
- control
- memory helpers
- streams
- compilation

Only after those exist does it make sense to build higher runtimes.

### 6.4 Immediate pvm compatibility was not the first success criterion

Compatibility can be useful later, but it was not the first implementation target.

The first goal had to be a strong enough low-level substrate that multiple systems can be built on it, including any future iwatjit-like runtime:

- compiled stream pipelines
- deterministic allocators
- typed data structures
- future schedulers/runtime layers
- possibly a future post-pvm incremental system

That is a much better success criterion.

---

## 7. How to think about pvm and watjit together

Use this split:

### pvm

- source language / ASDL architecture
- memoized phase boundaries
- structural sharing
- interactive compiler design
- cache reuse as an architectural metric

### watjit

- typed machine-level language toolkit
- memory layouts and allocators
- staged kernels
- compiled stream terminals
- Wasm/Wasmtime execution substrate

So the relationship is not:

> pvm old, watjit same thing but faster

It is:

> pvm solves the architecture of meaning.
> iwatjit was meant to replace pvm at the runtime/framework layer.
> watjit solves the architecture of execution underneath that layer.

That is the correct stack.

---

## 8. A concrete mental model

Think in three layers:

### Layer 1: authored program

This is pvm territory:

- ASDL values
- structural identity
- pure reducers
- phase boundaries
- compiler-style incrementalization

### Layer 2: lowered executable plan

This is the boundary between the two worlds.

Examples:

- flat command streams
- schedules
- typed execution plans
- buffer layouts
- resolved tables

### Layer 3: machine kernels

This is watjit territory:

- structs, arrays, unions, tagged unions
- typed pointers/views
- arenas, slabs, LRU, hash tables
- compiled loops
- SIMD kernels
- Wasmtime execution

If a future runtime replaces part of pvm's Lua-side execution machinery, it should be built here, as a watjit library, on top of these layers.

---

## 9. Example: watjit as the machine layer

### 9.1 Typed memory write

```lua
local write_pair = wj.fn {
    name = "write_pair",
    params = { wj.i32 "base" },
    body = function(base)
        local mem = wj.view(wj.i32, base, "mem")
        mem[0](5)
        mem[1](9)
        mem[2](mem[0] + mem[1])
    end,
}
```

This is the kind of code that should exist below a compiler boundary, not inside a high-level domain reducer.

### 9.2 Composable runtime pieces

```lua
local Entry = wj.struct("Entry", {
    { "key", wj.i32 },
    { "value", wj.i32 },
})

local temp = wj.arena("temp", 64 * 1024)
local store = wj.slab("entries", Entry.size, 256)
local order = wj.lru("entries_lru", 256)
local index = wj.hashtable("entries_index", 512)
```

This is exactly the kind of substrate the archive design wanted, but now it exists as ordinary reusable libraries instead of one imagined monolith.

### 9.3 Compiled streams

```lua
local S = wj.stream
local SC = wj.stream_compile

local drain = SC.compile_drain_into {
    name = "drain_scaled",
    params = { wj.i32 "x_base", wj.i32 "n", wj.i32 "out_base" },
    build = function(x_base, n, out_base)
        local src = S.seq(wj.i32, x_base, n)
            :map(wj.i32, function(v) return v * wj.i32(2) end)
            :take(8)
        return src, out_base
    end,
}
```

This is already a specialized executable lowering pipeline.

---

## 10. Non-claims

To keep the design honest:

### Watjit is not the pvm replacement

That role belonged to the retired `iwatjit` effort.

Watjit is the language/substrate underneath.

### Watjit is not an ASDL system

It does not replace source modeling. It complements it.

### Watjit should remain standalone

This is critical.

The archive document already understood this, and the repo instructions are explicit: `watjit/` is its own active library layer and must stay usable standalone.

### A future native incremental runtime, if built, should be a watjit library

Not a competing substrate. Not a parallel universe.

Watjit comes first.

---

## 11. The new thesis

> pvm discovered that interactive software should be treated as compilation from authored intent to flat executable facts.
>
> iwatjit was the intended replacement for pvm: a runtime/framework rebuild on explicit typed memory.
>
> watjit is the language and machine substrate underneath that effort: typed values, explicit layouts, deterministic allocators, compiled stream terminals, SIMD kernels, and Wasmtime execution, all authored from Lua as a metalanguage.
>
> The right way to pursue a post-pvm runtime is not to skip the substrate. It is to build the machine layer beneath it with watjit first.

---

## 12. Practical repo reading order

If you are new to the current design, read in this order:

1. `docs/COMPILER_PATTERN.md`
2. `docs/PVM_GUIDE.md`
3. `watjit/README.md`
4. `watjit/WATJIT_LANGUAGE.md` (this file)
5. `watjit/types.lua`
6. `watjit/func.lua`
7. `watjit/arena.lua`, `watjit/slab.lua`, `watjit/lru.lua`, `watjit/hashtable.lua`
8. `watjit/stream.lua`, `watjit/stream_compile.lua`
9. `watjit/test_*.lua`

That path moves from architecture, to phase discipline, to the new machine substrate.

---

## 13. Bottom line

The archive `iwatjit` document described an imagined replacement for pvm.

That should be stated plainly: `iwatjit` was the pvm-replacement layer.

What `watjit` gives us today is the layer underneath: typed memory, execution kernels, compiled streams, deterministic runtime structures, and a programmable low-level language for building future runtimes correctly.

That is the redesign.
