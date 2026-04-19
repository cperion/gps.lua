# asdljit

Early native-ASDL subproject scaffold.

This directory is the start of the `new/ASDLJIT.md` direction:

> use `watjit`'s simple primitives — quotes, inlining, code generation, typed
> layouts, and small runtime helpers — to build a native ASDL implementation.

## Current scope

Today `asdljit/` is not a full native ASDL runtime yet.
It is the first **codegen-oriented scaffold** for that direction.

Implemented so far:

- parse ASDL schema text via `asdl_parser.lua`
- build schema/constructor descriptors in a new standalone subfolder
- generate `watjit` layouts from product/constructor field specs
- generate inline quote-based helpers from schema descriptors:
  - hash quotes
  - equality quotes
- use `watjit` quotes and `fn:inline_call(...)` as the central codegen/inlining mechanism
- first runtime MVP for unique product/constructor descriptors:
  - generated hash/store/slot-equality kernels
  - handle-returning constructor runtime
  - canonical uniqueness by generated hash + generated slot equality
  - native storage in Wasm linear memory
- first canonical list runtime MVP:
  - generated list hash/store/slot-equality kernels
  - canonical list handles
  - descriptor runtimes can now use list handles for list fields
- nested-handle runtime support:
  - descriptor fields can now be backed by other descriptor runtimes via `field_runtimes = { ... }`
  - list runtimes can hold descriptor handles via `elem_runtime = ...`
  - descriptor list fields can now be backed by list-of-handle runtimes
- structural update MVP:
  - `runtime:with(handle, overrides)`
  - preserves canonical uniqueness by re-entering the generated constructor path
  - works for scalar fields, nested handle fields, and list/list-of-handle fields

## Why this matters

The future native ASDL runtime will need generated kernels for:

- constructor key hashing
- structural equality checks during interning
- raw getter layouts
- structural update helpers

The current runtime MVP already exercises the first three ideas in a small,
concrete form, and now includes the first native canonical-list path too.

The current scaffold starts with exactly those kinds of code-generated pieces.

## Example

```lua
local aj = require("asdljit")
local wj = require("watjit")

local S = aj.compile([[
module Bench {
    Point = (i32 x, i32 y) unique
}
]], {
    type_map = {
        i32 = wj.i32,
    },
})

local Point = S.Bench.Point
local Layout = Point:layout()
local hash_q = Point:hash_quote()
local eq_q = Point:eq_quote()
```

## Current limitations

MVP restrictions in the active scaffold:

- optional fields are not supported yet
- scalar storage currently targets integer/enum-like `watjit` scalar fields up to 32 bits
- nested descriptor fields/lists are represented as `i32` handles backed by other runtimes
- uniqueness buckets are still Lua-side tables keyed by generated native hashes
- there is not yet a unified whole-schema global handle namespace across all descriptors
- this is not yet the full canonical handle/interner runtime described in `new/ASDLJIT.md`

## Test

```bash
luajit asdljit/test_codegen.lua
luajit asdljit/test_runtime_mvp.lua
luajit asdljit/test_list_runtime_mvp.lua
luajit asdljit/test_nested_handle_runtime.lua
luajit asdljit/test_with_mvp.lua
```
