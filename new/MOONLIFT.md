# Moonlift

*LuaJIT staging + direct Cranelift lowering.*

Moonlift is a new project direction emerging out of `watjit/`.

It keeps the strongest parts of watjit:

- Lua as the metalanguage
- typed low-level values and layouts
- quotes and inline expansion
- structured control lowering
- explicit memory/runtime thinking

and replaces the final backend story:

- instead of primarily emitting WAT text and then compiling it,
- Moonlift lowers directly to Cranelift IR through a Rust runtime.

The result is a Terra-like architecture:

> one native runtime binary embeds LuaJIT, runs Moonlift scripts, expands
> quotes/inlines in Lua, lowers directly into Cranelift's own IR in the first
> implementation, and compiles functions at function granularity.

---

## 1. Why Moonlift exists

Watjit proved several important things:

- Lua is an excellent staging and specialization language
- typed low-level code can be authored ergonomically from Lua
- quotes + inline expansion make code generation much cleaner
- explicit traversal lowering (`iter.lower`) is a better center than ad hoc terminal hacks

But watjit still pays a structural cost at the backend boundary:

- WAT text is a debug-friendly artifact, but a poor final IR boundary
- WAT parse/compile is coarser than the real structure of the source program
- function-granular incremental rebuilds are harder than they should be
- the backend does not directly see the frontend's structured lowering decisions

Moonlift exists to fix that.

Its core claim is:

> once the frontend has quotes, inline expansion, typed layouts, and a proper
> lowering algebra, the right backend target is no longer WAT text. It is a
> direct native IR builder such as Cranelift.

---

## 2. Relationship to pvm, iwatjit, and watjit

### pvm

`pvm` is the architecture of interactive software as compilation:

- ASDL source language
- structural sharing
- memoized boundaries
- flat executable facts
- loop as execution

### iwatjit

`iwatjit` was the planned replacement runtime for pvm:

- native-memory runtime ambition
- more explicit memory/control over execution substrate

### watjit

`watjit` is the language and systems substrate underneath that ambition:

- typed values
- layouts
- control flow
- memory helpers
- stream plans
- compiled traversal algebra
- quotes and inlining

### Moonlift

Moonlift is the next step beyond watjit:

- keep LuaJIT staging
- keep typed low-level IR authoring
- keep quotes/inlining/lowering
- replace WAT as the primary backend boundary
- lower directly to Cranelift through Rust

So the relationship is:

- `pvm` — architecture of meaning
- `watjit` — typed low-level language toolkit
- `Moonlift` — embedded language runtime with direct native backend

Moonlift is not "rename watjit".
It is the project that begins once watjit has matured enough to deserve a direct backend.

---

## 3. The central idea

Moonlift is a **native runtime binary** that embeds **LuaJIT** and exposes a
language/runtime/compiler stack.

A Moonlift program is authored in Lua syntax, but it is not "just a Lua library".
It is a staged compiled language environment.

The stack is:

```text
Moonlift binary
  ├── embedded LuaJIT state
  ├── Moonlift Lua frontend
  │     ├── types
  │     ├── ctrl
  │     ├── func
  │     ├── quote
  │     ├── iter
  │     └── normalization / lowering
  └── Rust backend
        ├── Lua-facing runtime services
        ├── direct Cranelift IR construction
        ├── JIT / object emission
        └── runtime symbol binding
```

The important principle is:

> Lua is the staging and authoring layer. Rust owns backend lowering and runtime.

---

## 4. What Moonlift keeps from watjit

Moonlift should keep the best parts of watjit intact.

### 4.1 Lua as metalanguage

Lua remains the place where users:

- write generators and specializers
- build typed programs
- expand quotes
- choose inlining structure
- compose traversal algebras

This is essential. Moonlift should not become a Rust-authored DSL with Lua bolted on.

### 4.2 Typed low-level surface

Moonlift should preserve the typed authoring model:

- `i8/i16/i32/i64`
- `u8/u16/u32/u64`
- `f32/f64`
- `ptr(T)`
- `struct`
- `array`
- `union`
- `enum`
- `tagged_union`

### 4.3 Structured control

The `ctrl` layer is already the right front-end shape:

- `if_`
- `for_`
- `while_`
- structured blocks/loops/branches

This should lower to structured control in Rust and then to Cranelift blocks.

### 4.4 Quotes and inline expansion

Quotes are one of the strongest reasons Moonlift is now viable.

They allow:

- hygienic specialization
- small helper abstraction without backend opacity
- selective inlining
- backend-visible expanded structure

Moonlift should treat quotes/inlining as foundational, not optional sugar.

### 4.5 Iterator/traversal lowering

The new `watjit.iter` is a compiled traversal algebra.
That is exactly the kind of frontend primitive Moonlift should keep.

The key operation is not generic host iteration anymore.
It is:

```lua
iter.lower(plan, emit, ctx)
```

This already looks like a lowering pass into a backend builder.
That makes it a natural frontend primitive for Moonlift.

---

## 5. What Moonlift changes

### 5.1 WAT is no longer the primary backend boundary

WAT may remain useful for:

- debugging
- textual dumps
- validation/reference backend

But it should stop being the primary final artifact.

### 5.2 The primary backend is direct Cranelift lowering

Moonlift should lower directly into Cranelift's own IR through Rust in the first implementation.

This gives:

- direct SSA/block construction
- function-granular compilation
- faster rebuilds
- more faithful lowering of frontend control structure

### 5.3 The runtime is owned by one native binary

Rather than a Lua script importing a backend library through ad hoc FFI,
Moonlift should own the whole runtime process:

- LuaJIT state
- backend/compiler state
- compiled function handles
- symbol tables
- runtime trampolines

This is the Terra-like move.

---

## 6. Why direct Cranelift matters

Direct Cranelift lowering is valuable for more than raw speed.
It fixes the unit of compilation.

### 6.1 Function-granular compilation

With Cranelift, the natural compilation atom is a function.

That means:

- compile one helper
- rebuild one reducer
- rebuild one sink
- rebuild one traversal terminal
- preserve other compiled functions

This is much more natural than regenerating a large WAT module text artifact.

### 6.2 Better composition

Moonlift can compose code in three modes:

- separate function calls
- quote-expanded inline fragments
- mixed function + inline structure

That means compile-time vs runtime tradeoffs become explicit and controllable.

### 6.3 Better incremental rebuilds

Once functions are separate compilation units, rebuild policy becomes straightforward:

- unchanged function IR → reuse compiled artifact
- changed function IR → rebuild only that function
- relink runtime/module graph

This is one of Moonlift's biggest architectural advantages.

---

## 7. The correct Lua ↔ Rust boundary

This boundary determines whether Moonlift is elegant or painful.

### The rule

> Lua must not drive Cranelift instruction-by-instruction.

That would leak backend mechanics upward and create a terrible FFI boundary.

### Instead

Lua should perform:

- quote expansion
- inline expansion
- normalization
- iterator lowering preparation

Then Rust should consume that lowered structure in coarse-grained calls such as:

- compile one function
- compile one module
- emit one object
- install one compiled module in runtime

In the first implementation, Rust should build **Cranelift's own IR directly** rather than forcing an additional Moonlift-specific IR layer too early.

### Good boundary

```lua
local compiled = backend.compile_module(my_module)
```

### Bad boundary

```lua
backend.create_block()
backend.ins_iadd(...)
backend.ins_load(...)
backend.ins_br(...)
```

The former is Moonlift.
The latter is frontend collapse into backend detail.

---

## 8. Start with Cranelift's own IR

Moonlift does **not** need a separate backend-neutral IR to get started.

The first implementation should:

- keep Lua as the staging/frontend layer
- keep quotes, inline expansion, normalization, and iterator lowering in Lua
- have Rust translate the lowered function/module structure directly into Cranelift's own IR

This is the most pragmatic path because it avoids inventing an extra IR before we know exactly what the backend boundary wants.

### What to preserve structurally

Even without a separate Moonlift IR, the compilation unit should still be:

- typed
- structured
- function-separated
- explicit about control and memory operations

### Why this is enough initially

Cranelift already gives us:

- functions
- signatures
- blocks
- SSA values
- loads/stores
- calls
- returns

So the immediate goal is not to design another IR, but to map Moonlift's lowered structure into Cranelift cleanly.

### Later possibility

A separate canonical Moonlift IR may still become useful later for:

- backend independence
- dumping/debugging
- content hashing
- incremental cache keys
- multi-backend support

But that should be extracted from experience, not imposed before the first backend works.

---

## 9. The runtime interaction model

Moonlift-generated code should **not** manipulate Lua directly.

Generated code should talk to Rust runtime helpers.
Rust runtime helpers may then talk to the embedded Lua state.

### Why

Direct Lua stack manipulation from generated code would be:

- fragile
- backend-polluting
- hard to reason about
- expensive to expose safely

### Better model

Generated code imports runtime symbols such as:

- panic/trap helpers
- memory helpers
- runtime registry accessors
- Lua callback trampolines through handles

These imported symbols are registered in the JIT through the Cranelift JIT symbol API.

### Consequence

Compiled code sees:

- integers
- floats
- pointers
- handles
- runtime-call signatures

Not `lua_State` stack protocol details.

---

## 10. Embedded LuaJIT runtime model

Moonlift should embed a single `lua_State*` inside a Rust runtime object.

Conceptually:

```text
Runtime {
  lua_state,
  compiled_modules,
  function_handles,
  runtime_symbols,
  memory,
  caches,
}
```

This runtime object owns:

- the LuaJIT state
- backend/compiler state
- compiled code lifetime
- symbol registration
- module caches

Generated code may receive a runtime/context pointer explicitly as part of its ABI.

---

## 11. Runtime ABI direction

Moonlift should define a small explicit runtime ABI.

Examples of imported helpers:

- `moonlift_rt_panic(rt, code)`
- `moonlift_rt_alloc(rt, bytes) -> ptr`
- `moonlift_rt_bounds_fail(rt, index, limit)`
- `moonlift_rt_call_lua_handle(rt, handle, args_ptr, args_len, out_ptr)`

These are only examples. The important point is the discipline:

> compiled code talks to a runtime ABI, not directly to Lua internals.

---

## 12. Memory model

Moonlift should begin conservatively.

### Recommendation

Preserve the current linear-memory style initially.

That means:

- one contiguous memory model
- explicit offsets/views
- predictable lowering of structs/arrays/pointers
- easier migration from watjit

This can later evolve if needed, but starting with a Wasm-like linear memory discipline keeps the system conceptually stable while the backend changes.

---

## 13. Moonlift and iterator lowering

The current iterator/traversal story is one of the strongest foundations Moonlift has.

`iter.lower(plan, emit, ctx)` is already a frontend lowering primitive.

Moonlift should preserve that and let it lower directly toward Rust-side Cranelift construction, not into WAT strings.

This means the pipeline becomes:

```text
stream plan
  -> normalize
  -> iter.lower(...)
  -> Rust-side Cranelift IR construction
```

That is a clean architecture.

---

## 14. Incremental compilation model

Moonlift should take advantage of function-granular compilation.

### Function identity

Each function should have:

- stable name / symbol identity
- stable signature
- content hash after quote/inline/normalize/lower

### Rebuild rule

- if hash unchanged → reuse compiled artifact
- if hash changed → rebuild only that function
- if callee set unchanged and callees reused → relink/reinstall quickly

This makes Moonlift much better suited for interactive and incremental development than a text-WAT pipeline.

---

## 15. What Moonlift is not

Moonlift is **not**:

- raw Lua emitting Cranelift one instruction at a time
- a thin Rust FFI wrapper around Cranelift APIs
- a mere rename of watjit
- a host-runtime hack where generated code directly drives Lua stack calls

Moonlift is a language/runtime architecture.

---

## 16. Initial implementation plan

### Milestone 0 — runtime shell

- create Moonlift runtime binary in Rust
- embed LuaJIT
- preload frontend Lua modules
- run scripts from the binary

### Milestone 1 — direct Cranelift integration

- keep the current Lua frontend/lowering structure
- compile the first functions by constructing Cranelift IR directly in Rust
- support inspection through Cranelift textual dumps where useful

### Milestone 2 — minimal Cranelift backend

Support:

- scalar types
- locals
- arithmetic
- comparisons
- loads/stores
- if/loop/block
- return
- direct calls

### Milestone 3 — first iterator terminals

Compile through Moonlift backend:

- `iter.compile_sum`
- `iter.compile_count`
- `iter.compile_one`
- `iter.compile_drain_into`

### Milestone 4 — runtime symbols

Add imported runtime helper binding through Cranelift JIT symbol registration.

### Milestone 5 — incremental rebuild cache

- function hashing
- changed-function recompilation
- module/runtime relinking

---

## 17. Development modes

Moonlift should expose clear CLI modes.

Examples:

```bash
moonlift run script.lua
moonlift ir script.lua
moonlift wat script.lua
moonlift clif script.lua
moonlift build script.lua -o out.o
```

Useful development outputs:

- optional WAT debug dump
- Cranelift textual IR dump
- runtime/function metadata dump

These will matter a lot for debugging the compiler pipeline.

---

## 18. Why this is exciting

Moonlift feels like it solves many problems because it aligns several layers at once:

- Lua authoring ergonomics
- typed low-level systems programming
- quotes and hygienic specialization
- direct native backend lowering
- function-granular composition
- incremental rebuild potential
- one owned runtime process

That is not a small improvement.
It is a coherent language architecture.

---

## 19. The thesis

> Moonlift is a Terra-like embedded language/runtime architecture built from the lessons of watjit.
>
> LuaJIT remains the staging and metaprogramming environment. Quotes, inline expansion, typed layouts, structured control, and traversal lowering remain frontend primitives. But instead of treating WAT text as the final backend boundary, Moonlift begins by lowering directly into Cranelift's own IR through a Rust runtime that owns compilation, symbols, memory, and the embedded Lua state.
>
> This enables function-granular native compilation, faster rebuilds, better specialization/composition tradeoffs, and a much cleaner alignment between authored low-level structure and executable machine code.

---

## 20. Immediate next questions

The next concrete design questions for Moonlift are:

1. What is the first stable runtime ABI?
2. What is the first Cranelift-backed subset?
3. How are function identities and hashes computed?
4. Which parts of current watjit move into Moonlift unchanged, and which become compatibility layers?
5. At what point does a separate Moonlift IR become worth extracting from the working implementation?

Those should be answered before deep implementation proceeds.
