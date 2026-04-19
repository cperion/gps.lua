# watjit iterator algebra

*Target/current-direction document.*

This document describes the traversal algebra now emerging in `watjit.iter`.
It is the intended semantic replacement direction for the old runtime-iterator /
triplet-wrapper mindset.

---

## Thesis

Iteration should not be modeled as a stack of runtime `next()` wrappers.

It should be modeled as:

> **a producer lowered into a sink, with explicit control codes and fused
> transducer rewriting**

So the core object is not a pull cursor. The core object is a traversal plan
that can lower itself into one machine.

---

## The three semantic layers

### 1. Sources

Sources define traversal shape.

Current source forms:

- `seq(item_t, base, count)`
- `cached_seq(item_t, values, count)`
- `range(item_t, start, stop, step)`
- `once(item_t, value)`
- `empty(item_t)`

### 2. Transducers

Transducers do not create runtime iterators. They rewrite the sink path.

Current transducers:

- `map`
- `filter`
- `take`
- `drop`
- `concat`
- `simd_map`

### 3. Terminals

Terminals close the traversal with a result contract.

Current terminals:

- `sum`
- `count`
- `one`
- `fold`
- `drain_into`

---

## Control protocol

Traversal control is explicit and minimal.

- `CONTINUE = 0`
- `BREAK = 1`
- `HALT = 2`

Interpretation:

- `CONTINUE` — keep traversing normally
- `BREAK` — stop the current producer segment, but do not globally poison later
  concat segments
- `HALT` — stop the whole traversal

This distinction matters.

For example, `take(3):concat(rest)` should stop the left segment after three
items without meaning "globally cancel the entire outer traversal machine for
all future composition forever". By contrast, terminals like `one()` or
`find(...)` naturally want global halt.

---

## Quote-first surface

The algebra should feel native to `watjit`'s quote system.

Current helpers in `watjit.iter`:

- `iter.sink_expr { ... }`
- `iter.sink_block { ... }`
- `iter.reducer_expr { ... }`
- `iter.bind(quote_or_fn, ...)`

These are the intended ergonomic bridge between traversal algebra and hygienic
IR templates.

### `sink_expr`

A sink quote that returns a control code.

```lua
local first_gt = I.sink_expr {
    params = { wj.i32 "out", wj.i32 "limit" },
    item = wj.i32 "v",
    body = function(out, limit, v)
        local code = wj.i32("code", I.CONTINUE())
        wj.if_(v:gt(limit), function()
            out(v)
            code(I.HALT())
        end)
        return code
    end,
}
```

### `sink_block`

A sink quote that emits statements only. It implicitly means `CONTINUE`.

```lua
local accumulate = I.sink_block {
    params = { wj.ptr(wj.i32) "slot" },
    item = wj.i32 "v",
    body = function(slot, _v)
        slot[0](slot[0] + wj.i32(1))
    end,
}
```

### `reducer_expr`

A quote-first reducer for `fold`.

```lua
local scaled = I.reducer_expr {
    params = { wj.i32 "scale" },
    acc = wj.i32 "acc",
    item = wj.i32 "v",
    ret = wj.i32,
    body = function(scale, acc, v)
        return acc + (v * scale)
    end,
}
```

### `bind`

`iter.bind(...)` pre-binds quote/function arguments. Traversal-provided values
are appended last.

```lua
S.seq(wj.i32, base, n):lower(I.bind(accumulate, slot))
local total = S.seq(wj.i32, base, n):fold(0, I.bind(scaled, scale), wj.i32)
```

---

## What `cached_seq` means here

`cached_seq` is the first important bridge to a pvm successor.

A cached sequence is not a special terminal. It is a source:

```lua
I.cached_seq(item_t, values, count)
```

Semantically this means:

> the expensive producer work already happened, and we now have a materialized
> replayable flat sequence

That fits the traversal algebra naturally:

- miss path -> produce / record
- hit path -> replay through `cached_seq`

This is the right shape.

---

## How recording fits

The next major source kind should be a recording source / boundary pair.

Conceptually:

- on miss, lower the original producer while also appending each emitted item to
  a recording buffer
- if traversal fully commits, publish a replayable cached result
- future hits become `cached_seq`

So the operational path is:

1. lower original producer into a recording sink
2. terminal drives traversal
3. if completed, materialize stable replay source
4. later traversals use `cached_seq`

The key insight is that recording is not a second execution model. It is just a
special sink-plus-publication seam around the same traversal algebra.

---

## How shared replay fits

Shared replay should also be understood as a source-level concern.

There are really three interesting runtime cases:

1. **hit** — stable published result exists -> lower `cached_seq`
2. **recording/shared** — another consumer is currently recording the same
   producer -> attach to shared replay state
3. **miss** — run original producer and record

In the traversal algebra, this can still stay clean if we model a source that
may be in one of those operational states.

The important thing is not to leak ad hoc runtime cache logic into every
transducer or terminal.

Transducers and terminals should stay oblivious.

They just consume a source.

---

## Proposed runtime layering for a pvm successor

The likely successor runtime shape is:

- **authored/tree world** — ASDL / source identity / structural sharing
- **phase runtime** — cache lookup, recording publication, replay source choice
- **traversal algebra** — source/transducer/terminal lowering
- **backend** — watjit codegen / memory / result storage

In that layering:

- pvm-style cache policy belongs in the phase runtime
- traversal fusion belongs in the iterator algebra
- replay belongs to source selection
- reduction/drain semantics belong to terminals

---

## Why this is better than porting triplets directly

Triplets were a very good factoring of streaming execution in Lua:

- step function
- invariant environment
- mutable cursor

But for the `watjit` successor path, directly rebuilding triplets as runtime
wrappers would preserve the old operational substrate too literally.

The deeper invariant we want to preserve is not the exact pull API.
It is:

- streaming
- laziness
- compositional traversal
- replay of flat cached results
- partial consumption / early stop
- no mandatory materialization

A fused traversal algebra preserves those semantics while moving the operational
substrate to quote-native compiled machines.

---

## Current status

Today `watjit.iter` already does the following:

- normalizes stream plans
- lowers sources into sink functions
- rewrites `map/filter/take/drop` as sink transformers
- composes `concat` structurally
- exposes compiled terminals through `iter` and `stream_compile`
- exposes quote-first sink/reducer helpers

It is still early.

The next real step is integrating:

- recording buffers
- published replay sources
- shared in-flight replay state
- bounded-memory result ownership

without regressing the simplicity of the source/transducer/terminal model.

---

## Direction summary

The correct long-term direction is:

> `triplet.lua` should be replaced semantically by a compiled traversal algebra
> whose primitive is not `next()`, but producer-to-sink lowering with explicit
> control and replayable flat result sources.
