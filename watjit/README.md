# watjit

A low-level Lua-native language toolkit that stages typed code to WAT/Wasmtime.

`watjit` is not just a numeric kernel DSL. It is a small systems-language core
embedded in Lua, with Lua used as the metalanguage for specialization and
assembly.

---

## Current implemented surface

### Scalar types

```lua
wj.i8   wj.i16   wj.i32   wj.i64
wj.u8   wj.u16   wj.u32   wj.u64
wj.f32  wj.f64
wj.ptr(T)
```

### Layouts

```lua
wj.struct(name, fields, opts?)
wj.array(elem_t, count)
wj.union(name, fields, opts?)
wj.enum(name, storage_t, values)
wj.tagged_union(name, spec)
```

Implemented layout features:

- packed and aligned `struct`
- packed and aligned `union`
- per-field alignment override
- layout metadata: `size`, `align`, `packed`, field offsets
- tagged unions built from enum tag + payload union + outer struct

### Control flow

```lua
wj.if_(cond, then_body, else_body?)
wj.for_(i, n, body)
wj.while_(cond, body)

wj.label(name?)
wj.block(label?, body)
wj.loop(label?, body)
wj.br(label)
wj.br_if(label, cond)
wj.goto_(label)
wj.switch(tag, cases, default?)
```

Implemented structured low-level control includes:

- `break_()` / `continue_()` on loop control objects
- labeled structured branching
- no-fallthrough `switch`

### Integer ops

Implemented integer surface includes:

- arithmetic and comparisons
- signed/unsigned compare variants
- signed/unsigned div/rem variants
- bitwise ops: `band`, `bor`, `bxor`, `bnot`
- shifts/rotates: `shl`, `shr_u`, `shr_s`, `rotl`, `rotr`
- bit utilities: `clz`, `ctz`, `popcnt`, `bswap`

### Casts

```lua
wj.cast(T, x)
wj.trunc(T, x)
wj.zext(T, x)
wj.sext(T, x)
wj.bitcast(T, x)
```

### SIMD

Implemented vector types:

```lua
wj.simd.f32x4
wj.simd.f64x2
wj.simd.i32x4
```

Implemented SIMD operations include:

- load/store
- splat
- lane extract/replace
- arithmetic via operators
- vector comparisons
- mask select via `v128.bitselect`
- lane-space shuffle via `i8x16.shuffle`
- horizontal `sum()` helper

### Functions, modules, imports, quotes

```lua
wj.fn { ... }
wj.import { ... }
wj.module(funcs, opts?)
wj.quote_expr { ... }
wj.quote_block { ... }
```

Implemented module/import features include:

- exported functions
- imported functions
- instance extern lookup via `instance:extern(name)`
- linking imported functions from another instance
- Wasmtime-backed compilation/instantiation
- hygienic inline quotes via `quote_expr` / `quote_block`
- `fn:inline_call(...)` sugar for functions created through `wj.fn`

### Memory/runtime libraries

Implemented runtime helpers:

- `wj.arena(...)`
- `wj.slab(...)`
- `wj.lru(...)`
- `wj.mem(...)`
- `wj.hashtable(...)`

#### `wj.mem(name)` currently provides

- `memcpy_u8`
- `memset_u8`
- `memmove_u8`
- `memcmp_u8`

#### `wj.hashtable(name, capacity)` currently provides

A fixed-capacity `i32 -> i32` open-addressing table with tombstones:

- `init(base)`
- `clear(base)`
- `len(base)`
- `get(base, key, default)`
- `has(base, key)`
- `set(base, key, value)`
- `del(base, key)`

### Streams and fused traversal algebra

`watjit` also contains:

- `watjit.stream`
- `watjit.iter`
- `watjit.stream_compile`

`watjit.stream` builds stream plans.
`watjit.iter` lowers those plans as a fused traversal algebra: sources lower into sinks, transducers wrap sinks, and terminals close the machine.
`watjit.stream_compile` is now a compatibility shim over `watjit.iter`'s compiled terminals.

Current iterator-algebra surface includes:

- sources: `seq`, `cached_seq`, `range`, `once`, `empty`
- transducers: `map`, `filter`, `take`, `drop`, `concat`, `simd_map`
- terminals: `sum`, `count`, `one`, `fold`, `drain_into`
- quote-first helpers: `iter.sink_expr`, `iter.sink_block`, `iter.reducer_expr`, `iter.bind`

Control codes are explicit:

- `iter.CONTINUE()`
- `iter.BREAK()`
- `iter.HALT()`

See also: `../new/WATJIT_ITER_ALGEBRA.md`

---

## Lua-native authoring style

### Locals and params

```lua
local x = wj.i32 "x"
local sum = wj.i32("sum", 0)
```

### Assignment

```lua
x(42)
mem[i](v)
node.count(node.count + 1)
```

### Function definitions

```lua
local add = wj.fn {
    name = "add",
    params = { wj.i32 "a", wj.i32 "b" },
    ret = wj.i32,
    body = function(a, b)
        return a + b
    end,
}
```

### Imported functions

```lua
local ext_add = wj.import {
    module = "env",
    name = "add",
    as = "host_add",
    params = { wj.i32 "a", wj.i32 "b" },
    ret = wj.i32,
}
```

### Layouts

```lua
local Entry = wj.struct("Entry", {
    { "tag", wj.u8 },
    { "value", wj.u32, { align = 8 } },
}, {
    packed = false,
})
```

### Quotes

```lua
local mix32 = wj.quote_expr {
    params = { wj.u32 "x" },
    ret = wj.u32,
    body = function(x)
        local t = wj.u32("t", x:bxor(x:shr_u(16)))
        t(t * wj.u32(0x7feb352d))
        t(t:bxor(t:shr_u(15)))
        t(t * wj.u32(0x846ca68b))
        t(t:bxor(t:shr_u(16)))
        return t
    end,
}
```

Quotes splice inline into the current builder scope rather than emitting a real
Wasm `call`.

Functions created through `wj.fn` also expose:

```lua
helper:inline_call(...)
```

### Tagged unions

```lua
local Value = wj.tagged_union("Value", {
    tag_t = wj.u8,
    packed = false,
    variants = {
        { "I32", wj.i32 },
        { "F32", wj.f32 },
    },
})

local v = Value.at(base)
v.tag(Value.I32)
v.payload.I32(123)
```

### Hashtable runtime library

```lua
local ht = wj.hashtable("ht", 1024)
local mod = wj.module(ht:funcs(), {
    memory_pages = wj.pages_for_bytes(ht.memory_bytes),
})
```

---

## Example: integer low-level code

```lua
local mix = wj.fn {
    name = "mix32",
    params = { wj.u32 "x" },
    ret = wj.u32,
    body = function(x)
        x = x:bxor(x:shr_u(16))
        x = x * wj.u32(0x7feb352d)
        x = x:bxor(x:shr_u(15))
        x = x * wj.u32(0x846ca68b)
        x = x:bxor(x:shr_u(16))
        return x
    end,
}
```

## Example: SIMD mask select

```lua
local S = wj.simd

local kernel = wj.fn {
    name = "sel",
    params = { wj.i32 "a_base", wj.i32 "b_base", wj.i32 "out_base" },
    body = function(a_base, b_base, out_base)
        local a = wj.view(wj.i32, a_base, "a")
        local b = wj.view(wj.i32, b_base, "b")
        local out = wj.view(wj.i32, out_base, "out")
        local va = S.i32x4.load(a, 0)
        local vb = S.i32x4.load(b, 0)
        local mask = va:lt(vb)
        S.i32x4.store(out, 0, S.i32x4.select(mask, va, vb))
    end,
}
```

---

## Tests

Representative tests in `watjit/` now cover:

- quotes and inline-call expansion
- core WAT emission
- structs / arrays / unions / tagged unions
- enums
- imports
- control flow and switch
- casts and bitcasts
- integer low-level ops and bit utilities
- SIMD arithmetic and masks/select/shuffle
- arena / slab / lru
- memory primitives
- fixed-capacity hashtable
- streams / stream compilation
- Wasmtime backend integration

---

## Relationship to the long-form design doc

For the long-form language and architecture vision, see:

- `WATJIT_LANGUAGE.md`
- `../new/WATJIT_QUOTES.md`

That document explains the correct layering around the retired `archive/iwatjit_retired/IWATJIT.md` design:
`iwatjit` was the planned pvm replacement, while `watjit` is the language/substrate underneath.
This README describes the implemented surface in the repo today.
