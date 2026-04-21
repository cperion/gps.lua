# Moonlift Current Implementation Status

Status: implementation inventory for the **current rebooted Moonlift**.

This document is about **what has and has not actually been coded yet**, based on the current implementation and the current ASDL in:

- `moonlift/lua/moonlift/asdl.lua`

This file should be kept in sync eagerly with the implementation.
For the contribution rules that define what counts as an architecturally correct implementation, see:

- `moonlift/CONTRIBUTING.md`

This is **not** a test-status document.
It is intentionally focused on implementation coverage rather than test enumeration.
All current Lua and Rust tests pass as of this review, but this file is about implementation coverage.

For the future open-code / metaprogramming direction, see:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

For the future richer LuaJIT/self-hosted integration and parser-hosting direction, see:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`

---

# 1. Scope of this review

If this file and the code disagree, the file should be fixed immediately.
Do not leave known drift here just because a checklist item or design note existed earlier.

This inventory was based on the current implementation files:

- `moonlift/lua/moonlift/asdl.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_expr.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_loop.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_domain.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_top.lua`
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
- top-level `Surface -> Elab` lowering for params/funcs/externs/consts/items/modules
- top-level `Elab -> Sem` lowering for params/funcs/externs/consts/items/modules
- function-arg env synthesis from params
- sibling-item value env synthesis for funcs/consts/externs
- env-based named-type resolution through `ElabEnv.types`
- semantic layout resolution pass
- large `Sem -> Back` lowering
- `BackCmd` FFI replay
- Cranelift codegen host in Rust

### Still missing to make the language fully working as an authored language
- parser / text frontend in the rebooted codebase
- complete multi-module namespace/import/qualified-path integration
- type / layout synthesis from authored top-level code
- full slice/view lowering model
- authored/frontend intrinsic syntax and binding production
- fuller const evaluation
- fuller aggregate / non-scalar ABI support
- quote/open-code layer (`Meta`) from the design docs

---

# 3. What is already implemented

## 3.1 `Surface -> Elab` for local code and top-level value items is real

Implemented in:

- `moonlift/lua/moonlift/lower_surface_to_elab.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_expr.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_loop.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_domain.lua`
- `moonlift/lua/moonlift/lower_surface_to_elab_top.lua`

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

### Top-level value-item lowering implemented
The current `Surface -> Elab` code also lowers:

- `SurfParam`
- `SurfFunc`
- `SurfExternFunc`
- `SurfConst`
- `SurfItemFunc`
- `SurfItemExtern`
- `SurfItemConst`
- `SurfModule`

And it already synthesizes real value environments for:

- function arguments from params
- sibling function references in module scope
- sibling const references in module scope
- sibling extern references in module scope

So the frontend is now real for local code and top-level value items, not just a sketch.

---

## 3.2 `Elab -> Sem` for local code and top-level value items is real

Implemented in:

- `moonlift/lua/moonlift/lower_elab_to_sem.lua`

Implemented:
- `ElabType -> SemType`
- `ElabParam -> SemParam`
- `ElabBinding -> SemBinding`
- `ElabExpr -> SemExpr`
- `ElabStmt -> SemStmt`
- `ElabDomain -> SemDomain`
- `ElabLoop -> SemLoop`
- `ElabFunc -> SemFunc`
- `ElabExternFunc -> SemExternFunc`
- `ElabConst -> SemConst`
- `ElabItem -> SemItem`
- `ElabModule -> SemModule`

Also implemented:

- call target classification:
  - globals become `SemCallDirect`
  - externs become `SemCallExtern`
  - locals/args become `SemCallIndirect`

Top-level authored funcs currently lower to `SemFuncExport`, since the rebooted Surface layer does not yet expose a visibility/export distinction.

So the elaborated-to-semantic lowering is real for both local code and top-level value items.

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
- direct/extern call lowering without redundant call-site redeclarations
- block params / CFG lowering
- explicit expr-flow lowering through `BackExprLowering`
- explicit address/materialization-flow lowering through `BackAddrLowering`
- `if` / `switch`
- `while` loops
- `over range(...)`
- `over range(start, stop)`
- loop exprs
- loop-carried/index lowering through canonical slots without duplicate backend value ids
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
There is already a thin plain FFI-facing path today; what is still missing is a more polished/stable final public FFI surface.

### Rust side
Implemented in:

- `moonlift/src/lib.rs`
- `moonlift/src/ffi.rs`

The current C ABI already exposes opaque handles for:

- `moonlift_jit_t`
- `moonlift_program_t`
- `moonlift_artifact_t`

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

## 5.1 Top-level `Surface -> Elab` value-item lowering now exists, but authored type/layout declarations and qualified paths are still missing

The reboot now has real frontend lowering for:

- `SurfParam`
- `SurfFunc`
- `SurfExternFunc`
- `SurfConst`
- `SurfItemFunc`
- `SurfItemExtern`
- `SurfItemConst`
- `SurfModule`

What is still missing at this layer is:

- authored type-definition items / layout-definition items
- type/layout env synthesis from authored top-level declarations
- a text parser/frontend that produces those authored top-level items

---

## 5.2 Top-level `Elab -> Sem` value-item lowering now exists, but export/visibility semantics are still minimal

These current ASDL nodes now have real lowering:

- `ElabParam`
- `ElabFunc`
- `ElabExternFunc`
- `ElabConst`
- `ElabItemFunc`
- `ElabItemExtern`
- `ElabItemConst`
- `ElabModule`

Current explicit limitation:

- plain authored `ElabFunc` currently lowers to `SemFuncExport`, because the rebooted authored surface does not yet expose a separate local/export function distinction

---

## 5.3 Param lowering is now implemented at the frontend layers

The current path now supports:

- `SurfParam -> ElabParam`
- `ElabParam -> SemParam`
- function arg env synthesis from params

What is still missing is richer authored parameter semantics beyond plain typed params, if the reboot later grows them.

---

## 5.4 Environment / namespace synthesis is now partial rather than missing

Current authored `Surface -> Elab` now automatically builds real value environments for:

- function argument env construction
- module/global value env construction for sibling items
- sibling function/const/extern name resolution
- env-based qualified value path resolution through `SurfPathRef`

Still missing authored infrastructure includes:

- type env construction
- layout env construction from authored top-level declarations
- a complete multi-module namespace/import story
- clearer shadowing/lookup rules for competing qualified vs local names

---

## 5.5 Qualified path references are now partially implemented

`SurfPathRef` now lowers through the real frontend for value references.
It can resolve:

- env-provided qualified value references
- module-qualified global function refs through `ElabGlobal(module_name, item_name, ...)`
- module-qualified global const refs through `ElabGlobal(module_name, item_name, ...)`

Still missing:
- a complete multi-module authored module/import system that synthesizes those env entries automatically
- explicit shadowing/precedence rules for qualified vs local lookup

So qualified value refs are no longer a total blocker, but real authored module systems are still incomplete.

---

## 5.6 `ElabEnv.types` is now wired into named-type resolution, but type env synthesis is still missing

`ElabEnv` contains:

- `values`
- `types`
- `layouts`

The current frontend now uses `types` for real `SurfTNamed` lowering.
Named type paths must resolve through explicit `ElabEnv.types` entries, with no lexical fallback.
This includes module-qualified type lookup when the env carries entries like `"Foo.Bar"`.

What is still missing is authored infrastructure for automatically constructing those type envs from source modules/imports.

---

## 5.7 `SurfTArray` type lowering now exists, but count elaboration is still limited

`lower_surface_to_elab.lua` now lowers:

- `SurfTArray`

by elaborating the count expression into the `ElabTArray(count, elem)` form.

Current explicit limitation:

- the current non-literal count subset is still intentionally small
- count refs currently work only through explicit index-typed global const bindings / sibling const env synthesis
- broader general const-eval forms are still not implemented here

So currently:

- array literals work
- array type syntax lowers through the real frontend path
- arithmetic array-count expressions like add/sub/mul are supported
- array counts can reference explicit index-typed const bindings by name/path
- sibling module consts are synthesized for count evaluation in top-level lowering
- broader general const/name-driven const eval is still pending

---

## 5.8 Reference/dereference typing now performs the real type transformation in `Surface -> Elab`

`SurfExprRef` and `SurfExprDeref` now lower through explicit typed handling rather than the generic unary helper path.

Implemented type transformations:

- `T -> ptr(T)` for ref
- `ptr(T) -> T` for deref

Current explicit limitation:

- full addressability/lvalue rules are still incomplete downstream, so not every syntactically typable `ref` use is yet machine-lowerable

So ref/deref are now real typed frontend features, but the full lvalue/addressability model is still partial.

---

## 5.9 Logical `and` / `or` now lower as short-circuit boolean control flow

Current lowering treats:

- `SurfExprAnd`
- `SurfExprOr`

as boolean-only operators in the frontend, and `Sem -> Back` lowers them through explicit CFG short-circuiting rather than strict bool bit-ops.

So today they are implemented as short-circuit boolean operations.

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

## 5.11 Intrinsics are implemented in `Sem -> Back` and the Rust backend, but not surfaced at the frontend

The ASDL contains this `SemIntrinsic` family:

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

Current backend status:

### Implemented in `Sem -> Back`
`SemExprIntrinsicCall` now lowers in value position for scalar-result intrinsics and in materialization position where that is meaningful.

Current intrinsic lowering is scalar-only and split as follows:

- integer-like scalar intrinsics:
  - `popcount`
  - `clz`
  - `ctz`
  - `rotl`
  - `rotr`
  - `bswap`
- float scalar intrinsics:
  - `fma`
  - `sqrt`
  - `floor`
  - `ceil`
  - `trunc_float`
  - `round`
- scalar numeric intrinsic:
  - `abs`
    - integer-like or float scalar
- control intrinsics:
  - `trap`
  - `assume`
    - currently stmt-position / void-form control intrinsics in `Sem -> Back`

### Implemented in the Rust backend / FFI replay path
The backend command vocabulary and Rust Cranelift host now include lowering/replay for the intrinsic-backed `BackCmd` forms needed by the currently supported `SemIntrinsic` family.

### Still missing at frontend
There is still no current Surface/Elab frontend syntax or binding path producing `SemIntrinsic` from authored source.

So intrinsic support is now real in the semantic/backend layers, but it is **not yet an authored frontend feature**.

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
- slice-valued bounded `over` loops
- slice-valued `zip_eq` `over` loops
- a complete explicit low-level slice/view representation and bounds model

What is now implemented in this area:

- array-valued `SemDomainBoundedValue` lowering in `Sem -> Back`
- array-valued `SemDomainZipEq` lowering in `Sem -> Back`
- compile-time equal-length enforcement for array-valued `zip_eq`

So slices/domains exist structurally in the IR, array-valued bounded/zip domains now lower, but the full slice/view-backed domain model is still not machine-lowered yet.

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

The address-of / lvalue model is incomplete, but it is stronger than before.

Implemented now:
- address of arguments through canonical entry stack slots
- address of immutable `let` locals through stored-local bindings and canonical stack slots
- address of loop-carried locals and `over`-loop index bindings through canonical loop slots
- address of globals/const data through `SemBindGlobal`

Still missing or restricted:
- address of many computed values except where explicit materialization already exists
- a fully general addressability model across all lvalue categories
- a final documented rule for the remaining manual/internal pure-SSA local cases

So references exist in the IR and now work for args, stored immutable locals, loop-carried/index locals, and globals/const data, but the full lvalue/storage model is still partial.

---

## 5.19 Const evaluation is very limited

Current const-data lowering supports:

Normative subset document:
- `moonlift/CONSTANT_EXPRESSION_SUBSET.md`


- scalar literal constants
- bool literals
- nil as zero-init
- named aggregate literal const data
- array literal const data
- sibling const references within the current module through explicit `SemConstEnv`
- computed scalar constant evaluation for:
  - neg / logical-not / bit-not
  - add / sub / mul / div / rem
  - eq / ne / lt / le / gt / ge
  - bool `and` / `or`
  - bitwise binary ops and shifts
  - scalar casts / trunc / zext / sext / bitcast / saturating cast
  - pure `if` / `select`
- constant `block` / `switch` expressions through explicit `SemConstLocalEnv`
  and `SemConstStmtResult`
- constant loop evaluation through explicit const statement-flow and local-env threading for:
  - `while` stmt loops
  - `while` expr loops
  - `over range(...)`
  - `over range(start, stop)`
- constant statement execution for the currently supported subset:
  - `let`
  - `var`
  - `set`
  - expr stmt
  - `if`
  - `switch`
  - `assert`
  - loop stmt
  - loop-local `break` / `continue`
- aggregate field projection from constant aggregates
- array index projection from constant arrays
- recursive aggregate/array constant materialization through the evaluator

In addition, the type-level array-count evaluator now supports a small explicit subset:

- integer literals
- add/sub/mul over count expressions
- references to explicit index-typed global const bindings through `ElabConstEnv`
- sibling const references in `ElabModule` count lowering

General value-level const evaluation still explicitly does not support several forms, including:

- address-taking / dereference / loads
- intrinsic calls
- normal calls
- `over bounded value` / `zip_eq` constant loops
- store statements in constant blocks
- full multi-module/future-final const-expression coverage beyond the documented current subset
- a complete multi-module const-reference story

So constant evaluation is no longer literal-only, but it is still incomplete.

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

## 5.23 Current codegen-shape limitations exposed by `peek`

Recent direct machine-code inspection of small benchmark kernels shows several real remaining design/codegen gaps:

- dense integer `switch` currently lowers as a compare-chain CFG, not as a preserved switch form that could become a jump table
- plain scalar `if` chooses currently lower as branch CFG, not as an explicit select/branchless choice form
- function arguments are still eagerly spilled to stack slots at entry because the current addressability policy gives args canonical storage unconditionally
- authored unsigned / `index` benchmarking is still awkward because type-directed integer literal elaboration is not yet strong enough
- frontend/authored intrinsic syntax is still missing even though semantic/backend intrinsic lowering now exists

So the current backend is already useful for real codegen observation, but some important machine-shape outcomes are still determined by open frontend/lowering policy decisions rather than by finished intended language semantics.

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

## 6.1 Modules/functions/items now exist as authored frontend forms for value items, but the authored type/layout story is still incomplete

This distinction still matters.

### Implemented today
- `SurfFunc` / `ElabFunc` / `SemFuncExport`
- `SurfExternFunc` / `ElabExternFunc` / `SemExternFunc`
- `SurfConst` / `ElabConst` / `SemConst`
- `SurfItem*` / `ElabItem*` / `SemItem*`
- `SurfModule` / `ElabModule` / `SemModule`
- their downstream `Sem -> Back` lowering

### Still missing today
- authored type-definition items
- authored layout-definition items
- automatic multi-module import/qualified-path env synthesis
- a visibility/export distinction for authored functions

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
- top-level value-item lowering through `Surface -> Elab -> Sem`
- sibling value env synthesis for funcs/consts/externs
- semantic layout resolution
- scalar/backend CFG lowering
- function/module codegen

That is a real compiler middle and backend.

## 8.2 The biggest missing authored-language area

The biggest missing authored-language area is now:

- parser/text frontend
- multi-module namespace/import integration
- authored type/layout declarations and synthesis

Without those, the language still does not yet exist as a complete authored system, even though the closed value-item lowering path is now real.

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

> Moonlift already has a real local frontend core, real top-level value-item lowering through `Surface -> Elab -> Sem`, basic env-based qualified value refs, a layout-resolution pass, and a substantial backend, but it still lacks a complete authored language front door: **parser/text input, multi-module namespace/import integration, authored type/layout synthesis, slices/views, intrinsics, const eval, and fuller non-scalar ABI/value support**.

And if compressed even further:

- **expr/stmt/loop core:** real
- **top-level value-item frontend:** real
- **scalar backend:** real
- **authored type/layout + multi-module namespace frontend:** still incomplete
- **slice/intrinsic/parser/meta path:** not done

---

# 10. Related design docs

This file is intentionally only about implementation coverage.

For the future open-code / metaprogramming layer:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

For the future richer LuaJIT-hosted / parser-hosted integration strategy:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`
