# Moonlift Current Implementation Status

Status: implementation inventory for the **current rebooted Moonlift**.

This document is about **what has and has not actually been coded yet**, based on the current implementation and the current ASDL in:

- `moonlift/lua/moonlift/asdl.lua`

This is **not** a test-status document.
It is intentionally focused on implementation coverage, even if some tests may currently fail or drift.

For the future open-code / metaprogramming direction, see:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

For the future richer LuaJIT/self-hosted integration and parser-hosting direction, see:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`

---

# 1. Scope of this review

This inventory was based on the current implementation files:

- `moonlift/lua/moonlift/asdl.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_expr.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_loop.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_domain.lua`
- `moonlift/lua/moonlift/lower_elab_to_sem.lua`
- `moonlift/lua/moonlift/resolve_sem_layout.lua`
- `moonlift/lua/moonlift/lower_sem_to_back.lua`
- `moonlift/lua/moonlift/jit.lua`
- `moonlift/src/lib.rs`
- `moonlift/src/ffi.rs`

One file appears to be stale / obsolete and should **not** be treated as the current pipeline:

- `moonlift/lua/moonlift/lower_surface_to_sem.lua`

---

# 2. Current real compiler shape

The current actual ASDL defines a real closed compiler stack:

- `MoonliftSurface`
- `MoonliftElab`
- `MoonliftSem`
- `MoonliftBack`

And the current implementation already contains a real middle/back-end path for significant parts of that stack.

## High-level summary

### Real and coded today
- local expression lowering
- local statement lowering
- local loop and domain lowering
- `Elab -> Sem` lowering for local code
- semantic layout resolution pass
- large `Sem -> Back` lowering
- `BackCmd` FFI replay
- Cranelift codegen host in Rust

### Still missing to make the language fully working as an authored language
- top-level authored frontend lowering for funcs/externs/consts/modules
- param lowering at the frontend layers
- environment / namespace / layout synthesis from authored top-level code
- parser / text frontend in the rebooted codebase
- full slice/view lowering model
- intrinsic lowering
- fuller const evaluation
- fuller aggregate / non-scalar ABI support
- quote/open-code layer (`Meta`) from the design docs

---

# 3. What is already implemented

## 3.1 `Surface -> Elab` for local code is real

Implemented in:

- `moonlift/lua/moonlift/lower_surface_to_elab.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_expr.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_loop.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_domain.lua`

### Types implemented
- `SurfTVoid`
- `SurfTBool`
- all signed integer widths
- all unsigned integer widths
- `SurfTF32`
- `SurfTF64`
- `SurfTIndex`
- `SurfTPtr`
- `SurfTSlice`
- `SurfTFunc`
- `SurfTNamed`

### Expressions implemented
- integer / float / bool / nil literals
- `SurfNameRef`
- unary ops
- binary ops
- cast forms
- calls
- field access
- index access
- aggregate literals
- array literals
- `if` expr
- `switch` expr
- block expr
- loop expr

### Statements implemented
- `let`
- `var`
- `set`
- `store`
- expr stmt
- `if`
- `switch`
- `return`
- `break`
- `continue`
- loop stmt

### Loop/domain forms implemented
- `SurfLoopWhileStmt`
- `SurfLoopOverStmt`
- `SurfLoopWhileExpr`
- `SurfLoopOverExpr`
- `SurfDomainRange`
- `SurfDomainRange2`
- `SurfDomainZipEq`
- `SurfDomainValue`

### Block-local environment threading implemented
The current `Surface -> Elab` code already threads local env effects for:

- `let`
- `var`
- block expr stmt lists
- loop carry bindings and `next`

So the local frontend is real, not just a sketch.

---

## 3.2 `Elab -> Sem` for local code is real

Implemented in:

- `moonlift/lua/moonlift/lower_elab_to_sem.lua`

Implemented:
- `ElabType -> SemType`
- `ElabBinding -> SemBinding`
- `ElabExpr -> SemExpr`
- `ElabStmt -> SemStmt`
- `ElabDomain -> SemDomain`
- `ElabLoop -> SemLoop`

Also implemented:

- call target classification:
  - globals become `SemCallDirect`
  - externs become `SemCallExtern`
  - locals/args become `SemCallIndirect`

So the local elaborated-to-semantic lowering is real.

---

## 3.3 Semantic layout resolution is real

Implemented in:

- `moonlift/lua/moonlift/resolve_sem_layout.lua`

Implemented:
- named-layout lookup through `SemLayoutEnv`
- `SemFieldByName -> SemFieldByOffset`
- recursive resolution over exprs
- recursive resolution over stmts
- recursive resolution over loops
- recursive resolution over funcs/consts/items/modules
- recursive resolution over `SemIndexBaseView`
- recursive resolution over call targets and field refs

This is an important real pass, not a stub.

---

## 3.4 `Sem -> Back` is large and real

Implemented in:

- `moonlift/lua/moonlift/lower_sem_to_back.lua`

### Strongly implemented areas
- scalar integer lowering
- scalar float lowering
- bool lowering
- comparisons
- bitwise ops
- cast / extend / reduce / promote / demote / float-int conversion command emission
- select
- direct / extern / indirect calls
- block params / CFG lowering
- `if` / `switch`
- `while` loops
- `over range(...)`
- `over range(start, stop)`
- loop exprs
- block exprs
- assert -> trap lowering
- const data object emission
- function lowering from `SemFunc`
- item lowering from `SemItem`
- module lowering from `SemModule`

### Aggregate-ish support that is already real
- named aggregate copies via layout env
- named aggregate materialization into memory
- array literal materialization into memory
- named aggregate const-data initialization
- array const-data initialization

So `Sem -> Back` is already a serious implementation, especially on the scalar/CFG side.

---

## 3.5 FFI replay and Rust backend are real

### LuaJIT side
Implemented in:

- `moonlift/lua/moonlift/jit.lua`

This currently replays the `BackCmd` stream into the Rust builder via FFI.

### Rust side
Implemented in:

- `moonlift/src/lib.rs`
- `moonlift/src/ffi.rs`

The Rust host already supports a broad subset of current `BackCmd`, including:

- data declarations and initialization
- function declarations
- blocks and block params
- stack slots
- constants
- scalar ops
- comparisons
- loads / stores
- direct / extern / indirect calls
- select
- branches / jumps / returns / trap

So the backend is not speculative.
It exists.

---

# 4. What exists only as manual/internal IR today

Some ASDL forms exist and are supported downstream, but they are not yet produced by a complete authored frontend.

These include:

- `SemExprSelect`
- `SemExprIndexAddr`
- `SemExprFieldAddr`
- `SemExprLoad`
- `SemExprIntrinsicCall`
- `SemStmtAssert`
- `SemFieldByOffset`
- `SemIndexBaseView`
- `SemIndexBasePtr`

These are useful real internal forms, but many of them are currently reached only by:

- manual `Sem` construction in tests/debugging
- or by internal passes like `resolve_sem_layout`

rather than by a full top-level authored language path.

---

# 5. Major missing pieces

This is the core missing-work inventory.

## 5.1 Top-level `Surface -> Elab` lowering is missing

These current ASDL nodes have no real current frontend lowering:

- `SurfParam`
- `SurfFunc`
- `SurfExternFunc`
- `SurfConst`
- `SurfItemFunc`
- `SurfItemExtern`
- `SurfItemConst`
- `SurfModule`

So today there is **no full authored top-level frontend path** for:

- functions
- extern declarations
- const declarations
- items
- modules

This is one of the biggest gaps.

---

## 5.2 Top-level `Elab -> Sem` lowering is missing

These current ASDL nodes likewise have no current lowering:

- `ElabParam`
- `ElabFunc`
- `ElabExternFunc`
- `ElabConst`
- `ElabItemFunc`
- `ElabItemExtern`
- `ElabItemConst`
- `ElabModule`

So even if top-level `Elab` were produced, there is no complete current path to semantic IR for those top-level authored forms.

---

## 5.3 Param lowering is missing at the frontend layers

The ASDL contains:

- `SurfParam`
- `ElabParam`
- `SemParam`

But the current frontend path only really uses `SemParam` in manually-built semantic examples/tests.

Missing:
- `SurfParam -> ElabParam`
- `ElabParam -> SemParam`
- function arg env synthesis from params

---

## 5.4 Environment / namespace synthesis is missing

Current `Surface -> Elab` works because tests/debug code manually build `ElabEnv`.

Missing authored infrastructure includes:

- function argument env construction
- module/global env construction
- sibling item name resolution
- extern env construction
- type env construction
- layout env construction from authored top-level declarations

Right now these are not created automatically by a top-level frontend.

---

## 5.5 Qualified path references are not implemented

`SurfPathRef` exists in the ASDL, but current lowering explicitly errors on it.

So missing:
- qualified path value references
- namespace/module-qualified refs
- proper global item path resolution

This blocks real module authoring.

---

## 5.6 `ElabEnv.types` is effectively unused in the current frontend

`ElabEnv` contains:

- `values`
- `types`
- `layouts`

But the current frontend mostly uses:

- `values`
- `layouts`

The `types` side is not meaningfully wired into real type-name resolution yet.

So type namespaces/imports are still incomplete.

---

## 5.7 `SurfTArray` type lowering is still missing

This is explicit in the code.

`lower_surface_to_elab.lua` errors on:

- `SurfTArray`

because array-count expression elaboration for type lowering has not been implemented.

So currently:

- array literals work
- array type syntax at the Surface layer does not fully lower through the real frontend path

---

## 5.8 Reference/dereference typing is incomplete in `Surface -> Elab`

`SurfExprRef` and `SurfExprDeref` currently go through the generic unary helper path.

That means the frontend is not yet clearly performing the proper type transformations:

- `T -> ptr(T)` for ref
- `ptr(T) -> T` for deref

So ref/deref are present in the IR but not yet fully implemented as a proper typed frontend feature.

---

## 5.9 Logical `and` / `or` are currently strict bool ops, not short-circuit control flow

Current lowering treats:

- `SurfExprAnd`
- `SurfExprOr`

as typed binary operations, and `Sem -> Back` lowers them as bool bit-ops.

So today they are implemented as strict boolean operations.

If the intended language semantics require short-circuiting, that implementation is still missing.

This should be treated as a semantic decision point.

---

## 5.10 Named types/layouts are only manually usable today

The current frontend can work with:

- `SurfTNamed`
- field access on named types
- aggregate literals for named types

but only if matching layouts are manually supplied through env/layout data.

There is no current authored top-level path for:

- defining named types
- deriving/registering their layouts
- making them available to the normal frontend automatically

So named aggregate support currently exists only in a manual-context sense.

---

## 5.11 Intrinsics are not implemented end-to-end

The ASDL already contains a substantial `SemIntrinsic` family:

- `SemPopcount`
- `SemClz`
- `SemCtz`
- `SemRotl`
- `SemRotr`
- `SemBswap`
- `SemFma`
- `SemSqrt`
- `SemAbs`
- `SemFloor`
- `SemCeil`
- `SemTruncFloat`
- `SemRound`
- `SemTrap`
- `SemAssume`

But current status is:

### Missing at frontend
There is no current Surface/Elab frontend for intrinsic syntax or intrinsic binding production.

### Missing in `Sem -> Back`
`SemExprIntrinsicCall` is not actually lowered to `BackCmd` value code.
It explicitly errors in address/materialization lowering, and there is no real value-lowering case for it in `sem_to_back_expr`.

So intrinsic support is currently **not implemented end-to-end**.

---

## 5.12 `SemStmtAssert` is only partially integrated

`SemStmtAssert` exists and is lowered in `Sem -> Back`.

But there is no current:
- `Surface` assert node
- `Elab` assert node
- authored frontend path producing it

So assert exists as an internal/manual semantic feature, not as a fully surfaced language feature.

---

## 5.13 Slice/view support is incomplete

This is one of the biggest backend/runtime gaps.

### Present in the ASDL
- `SurfTSlice`
- `ElabTSlice`
- `SemTSlice`
- `SemIndexBaseView`
- `SemDomainBoundedValue`
- `SemDomainZipEq`

### Missing end-to-end in lowering
Current `Sem -> Back` explicitly lacks full support for:

- slice/view indexing
- slice/view mem sizing in key cases
- slice runtime copying
- bounded-value `over` loops
- `zip_eq` `over` loops
- a complete explicit low-level slice/view representation and bounds model

So slices/domains exist structurally in the IR but are not fully machine-lowered yet.

---

## 5.14 Array indexing is not fully supported end-to-end

Arrays are partially implemented.

What exists:
- array literals
- array materialization into memory
- array copy logic
- array const-data init

What is still missing:
- true array-value indexing all the way through `Sem -> Back`

Current `Sem -> Back` rejects array-value indexing paths that need explicit aggregate layout/value indexing support.

So arrays are partially real, but not fully first-class indexed values all the way down.

---

## 5.15 Aggregate / non-scalar ABI is incomplete

Current backend/lowering is still heavily scalar-oriented.

Missing or restricted:
- non-scalar load results
- non-scalar call results
- non-scalar return values in the current Back ABI path
- multi-result direct function-pointer artifact API
- multi-result raw-pointer extern ABI path
- full function-value storage semantics

So the effective callable ABI today is mostly:

- scalar/pointer-ish single-result

rather than full aggregate/multi-result values.

---

## 5.16 Global mutation is not implemented

`SemBindGlobal` exists.
Const/global reads exist.

But global assignment/store lowering is explicitly not implemented in `Sem -> Back`.

So mutable globals are not currently a real feature.

---

## 5.17 Externs are not first-class runtime values

Extern calls work through call-target lowering.

But direct extern binding reads are not supported, and externs are not addressable as ordinary values in the current lowering model.

So externs are callable, but not fully first-class values.

---

## 5.18 Addressability is still partial

The address-of / lvalue model is incomplete.

Missing or restricted:
- address of arguments
- address of immutable scalar locals
- address of many computed values
- a fully general addressability model across all lvalue categories

So references exist in the IR, but the lvalue/storage model is still partial.

---

## 5.19 Const evaluation is very limited

Current const-data lowering supports:

- scalar literal constants
- bool literals
- nil as zero-init
- named aggregate literal const data
- array literal const data

But it explicitly does not support many computed constant forms, including:

- unary ops
- arithmetic
- comparisons
- casts
- select
- field/index projections
- loads
- intrinsic calls
- normal calls
- block/if/switch/loop constant expressions

So constant evaluation is still very incomplete.

---

## 5.20 Floating remainder is not implemented end-to-end

Current state:
- Surface has remainder syntax
- Sem has `SemExprRem`
- Back ASDL has `BackCmdFrem`

But:
- `Sem -> Back` does not meaningfully complete float rem support
- Rust explicitly rejects `BackCmdFrem`

So floating remainder is not currently implemented end-to-end.

---

## 5.21 No parser / text frontend exists yet in the reboot

Right now the rebooted Moonlift is still authored by constructing ASDL values directly.

That means there is no current reboot-native:
- parser
- text frontend
- hosted fragment syntax
- integrated source compiler front door

So the current implementation is a compiler core and builder/IR layer, not yet a full authored text language.

---

## 5.22 No integrated top-level compile facade yet

The pipeline pieces exist, but the complete user-facing authored compile flow is still missing.

Still missing as a coherent top-level path:
- authored top-level `Surface` module construction from source text
- env synthesis
- top-level `Surface -> Elab`
- top-level `Elab -> Sem`
- automatic layout resolution pass insertion
- normal top-level compile facade into JIT artifact/session objects

Right now these pieces are still manual / semi-manual.

---

## 5.23 No `Meta` / quote / open-code implementation yet

The metaprogramming layer discussed in:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

does **not** exist in code yet.

Missing entirely:
- `MoonliftMeta`
- fragment values
- open elaborated templates
- slot/import machinery
- `Meta -> Elab` closure phases
- quote-time walk/query/rewrite over open code

So the meta side is still design-only.

---

# 6. What is partly implemented but still incomplete

## 6.1 Modules/functions/items exist at `Sem -> Back`, but not as authored frontend forms

This distinction matters.

### Implemented today
- `SemFuncLocal`
- `SemFuncExport`
- `SemItemFunc`
- `SemItemExtern`
- `SemItemConst`
- `SemModule`
- their `Sem -> Back` lowering

### Missing today
- authored top-level frontend production of those forms from `Surface` / `Elab`

So module/function lowering exists, but only from manually-built semantic IR.

---

## 6.2 Field and layout machinery exists, but still needs authored integration

Current real support includes:
- named layout env
- field-name resolution to offset
- named aggregate copying/materialization
- field-address and field-load support downstream

But current real missing parts include:
- authored top-level type declaration path
- automatic layout synthesis from authored program items
- fully integrated type namespace handling

---

## 6.3 Loops are strong on `while` and `range`, weak on bounded-value / zip-domain lowering

Current real support:
- while loops
- `over range(stop)`
- `over range(start, stop)`
- loop exprs and stmt loops
- carry/next machinery

Missing/partial:
- `over` bounded aggregate/slice values
- `zip_eq(...)` lowering to machine code
- complete low-level domain model for multi-domain traversal

---

# 7. Rust/FFI-specific explicit backend limitations

These are concrete, explicit limitations in the current backend layer.

## 7.1 `BackCmdFrem` is not implemented in Rust

Rust explicitly errors on it.

## 7.2 Raw pointer API does not support multi-result extern ABIs

Rust explicitly rejects multi-result extern declarations for the raw pointer API.

## 7.3 Direct artifact API is effectively single-result oriented

Direct function-pointer retrieval is limited to the current single-result shape.

These are backend limitations, separate from the frontend gaps above.

---

# 8. Current practical progress read

## 8.1 The strongest completed area

The strongest completed area is:

- local expression/statement/loop/domain lowering
- semantic layout resolution
- scalar/backend CFG lowering
- manual-semantic function/module codegen

That is a real compiler middle and backend.

## 8.2 The biggest missing authored-language area

The biggest missing authored-language area is:

- top-level frontend lowering and env synthesis

Without that, the language does not yet exist as a complete authored system, even though a large amount of the compiler core already exists.

## 8.3 The biggest missing runtime/value-model areas

The biggest incomplete runtime/value-model areas are:

- slices/views
- intrinsics
- fuller const evaluation
- non-scalar ABI/value support
- top-level type/layout integration

## 8.4 The biggest missing future-architecture area

The biggest planned-but-not-implemented area is the open-code/meta layer described in:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

And the richer future host/parser integration strategy described in:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`

---

# 9. Short summary

If compressed to one sentence:

> Moonlift already has a real local frontend core, semantic middle, layout-resolution pass, and substantial backend, but it does **not yet** have a fully wired top-level authored language, and several important semantic/runtime areas are still incomplete: **params/modules/env synthesis, slices/views, intrinsics, const eval, and non-scalar ABI/value support**.

And if compressed even further:

- **expr/stmt/loop core:** real
- **top-level authored language frontend:** not done
- **scalar backend:** real
- **aggregate/layout path:** partial/manual
- **slice/intrinsic/parser/meta path:** not done

---

# 10. Related design docs

This file is intentionally only about implementation coverage.

For the future open-code / metaprogramming layer:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

For the future richer LuaJIT-hosted / parser-hosted integration strategy:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`
