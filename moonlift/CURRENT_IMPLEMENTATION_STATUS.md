# Moonlift Current Implementation Status

Status: implementation inventory for the **current rebooted Moonlift**.

This document is about **what has and has not actually been coded yet**, based on the current implementation and the current ASDL in:

- `moonlift/lua/moonlift/asdl.lua`

This file should be kept in sync eagerly with the implementation.
For the contribution rules that define what counts as an architecturally correct implementation, see:

- `moonlift/CONTRIBUTING.md`

This is **not** a test-status document.
It is intentionally focused on implementation coverage rather than test enumeration.
Tests, local build prerequisites, and shared-library availability may still drift independently of this inventory; this file is about implementation coverage.

For the current reboot source-language shape, parser target, and span strategy, see:

- `moonlift/REBOOT_SOURCE_SPEC.md`
- `moonlift/REBOOT_SOURCE_GRAMMAR.md`
- `moonlift/SOURCE_SPAN_STRATEGY.md`

For the future open-code / metaprogramming direction, see:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

For the deferred future LuaJIT-hosted / self-hosted integration and parser-hosting direction, see:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`

---

# 1. Scope of this review

If this file and the code disagree, the file should be fixed immediately.
Do not leave known drift here just because a checklist item or design note existed earlier.

This inventory was based on the current implementation files:

- `moonlift/lua/moonlift/asdl.lua`
- `moonlift/lua/moonlift/parse_lexer.lua`
- `moonlift/lua/moonlift/parse.lua`
- `moonlift/lua/moonlift/source.lua`
- `moonlift/lua/moonlift/source_spans.lua`
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
- top-level `Surface -> Elab` lowering for params/funcs/externs/consts/statics/imports/type-items/modules
- top-level `Elab -> Sem` lowering for params/funcs/externs/consts/statics/imports/type-items/modules
- function-arg env synthesis from params
- sibling-item value env synthesis for funcs/consts/externs/statics
- explicit named-module package/import synthesis for qualified cross-module value/type lookup
- module-local type/layout env synthesis from authored `type ... = struct { ... }` items
- env-based named-type resolution through `ElabEnv.types`
- authored intrinsic parsing/lowering through the current closed frontend path
- semantic layout resolution pass with automatic module layout synthesis
- large `Sem -> Back` lowering
- combined package `Sem -> Back` lowering for imported named modules
- bootstrap source front door helpers in `moonlift.source`, including module/package pipeline + compile helpers
- `BackCmd` FFI replay
- Cranelift codegen host in Rust
- initial reboot text parser/front-end that constructs `MoonliftSurface` directly

### Still missing to make the language fully working as an authored language
- complete reboot parser coverage beyond the current bootstrap subset
- richer module/package features beyond the current explicit named-module + `import` path
- richer authored type-definition coverage beyond the current named-struct path
- full slice/view lowering model
- fuller const evaluation and immediate propagation
- fuller aggregate / non-scalar ABI support
- richer diagnostics and source mapping through later layers
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
- `SurfTView`
- `SurfTFunc`
- `SurfTNamed`

### Expressions implemented
- integer / float / bool / nil literals
- `SurfNameRef`
- authored dotted value syntax with later resolution (`SurfExprDot`)
- unary ops
- binary ops
- cast forms
- intrinsic calls
- calls
- index access
- aggregate literals
- array literals
- explicit `select(cond, a, b)`
- `if` expr
- `switch` expr
- block expr
- loop expr

### Statements implemented
- `let`
- `var`
- `set`
- expr stmt
- `if`
- `switch`
- `return`
- `break`
- `break value`
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

### Top-level item lowering implemented
The current `Surface -> Elab` code also lowers:

- `SurfParam`
- `SurfFunc`
- `SurfExternFunc`
- `SurfConst`
- `SurfStatic`
- `SurfImport`
- authored `SurfStruct` type items
- `SurfItemFunc`
- `SurfItemExtern`
- `SurfItemConst`
- `SurfItemStatic`
- `SurfItemImport`
- `SurfItemType`
- `SurfModule`

And it already synthesizes real module environments for:

- function arguments from params
- sibling function references in module scope
- sibling const references in module scope
- sibling extern references in module scope
- sibling static references in module scope
- sibling named types/layouts from authored type items
- imported qualified module namespaces through the named-package source front door

So the frontend is now real for local code and top-level items, not just a sketch.

---

## 3.2 `Elab -> Sem` for local code and top-level items is real

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
- `ElabImport -> SemImport`
- `ElabItem -> SemItem`
- `ElabModule -> SemModule`

Also implemented:

- call target classification:
  - globals become `SemCallDirect`
  - externs become `SemCallExtern`
  - locals/args become `SemCallIndirect`

Top-level authored funcs currently lower to `SemFuncExport`, since the rebooted Surface layer does not yet expose a visibility/export distinction.

So the elaborated-to-semantic lowering is real for both local code and top-level items.

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
There is already a thin plain FFI-facing path today, and that FFI path is the current practical/project-priority integration route while the language is completed.
What is still missing there is a more polished/stable final public FFI surface.
Practical use through `moonlift.jit` still requires building the shared library with cargo and either letting the default `target/...` search path find it or passing an explicit `libpath`; that build/load requirement is separate from the backend implementation coverage described here.

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

# 4. What still exists mainly as internal / pass-produced IR today

Some semantic forms are real and used downstream, but are still reached mostly through internal passes, lower-level helper lowering, or manual `Sem` construction in tests rather than through broad first-class authored syntax.

Important current examples include:

- `SemStmtAssert`
- `SemExprLoad`
- resolved field refs like `SemFieldByOffset`
- lower-level explicit view/index forms such as `SemView*` and `SemIndexBaseView`

These are useful real semantic forms, but they should be understood as part of the current internal/compiler IR story rather than as uniformly surfaced authored constructs.

---

# 5. Major missing pieces

This is the core missing-work inventory.

## 5.1 Top-level `Surface -> Elab` item lowering is now real for value items, imports, and authored struct types

The reboot now has real frontend lowering for:

- `SurfParam`
- `SurfFunc`
- `SurfExternFunc`
- `SurfConst`
- `SurfStatic`
- `SurfImport`
- `SurfTypeDecl`
- `SurfItemFunc`
- `SurfItemExtern`
- `SurfItemConst`
- `SurfItemStatic`
- `SurfItemImport`
- `SurfItemType`
- `SurfModule`

What is still missing at this layer is not the existence of authored top-level items, but broader completion around:

- richer authored type-definition families beyond the current named-struct path
- broader package/module features beyond the current named-module import path
- clearer final surface rules for visibility/export semantics

---

## 5.2 Top-level `Elab -> Sem` item lowering now exists, but export/visibility semantics are still minimal

These current ASDL nodes now have real lowering:

- `ElabParam`
- `ElabFunc`
- `ElabExternFunc`
- `ElabConst`
- `ElabStatic`
- `ElabImport`
- `ElabTypeDecl`
- `ElabItemFunc`
- `ElabItemExtern`
- `ElabItemConst`
- `ElabItemStatic`
- `ElabItemImport`
- `ElabItemType`
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

## 5.4 Environment / namespace synthesis is now real but still intentionally narrow

Current authored `Surface -> Elab` now automatically builds real value/type/layout environments for:

- function argument env construction
- module/global value env construction for sibling items
- sibling function/const/extern/static name resolution
- module-local type/layout env construction from authored type items
- explicit named-module package imports through `import Demo`
- env-based qualified value path resolution through `SurfPathRef`

Still missing authored infrastructure includes:

- richer package/module features beyond the current named-module host API
- import aliasing / renaming if the reboot later wants it
- clearer documented shadowing/lookup rules for every namespace corner case

---

## 5.5 Qualified path references are now partially implemented

The frontend now supports qualified value lookup, and the reboot parser preserves authored dotted value syntax explicitly before elaboration resolves it.

Current value-name behavior:

- explicit already-disambiguated `SurfPathRef` still lowers through the real frontend
- authored dotted value syntax parses as `SurfExprDot(...)`
- if the head of a dotted chain resolves as a local/runtime value binding, lowering treats the chain as field projection
- otherwise lowering may resolve the chain as a qualified value binding

What currently resolves:

- env-provided qualified value references
- module-qualified global function refs through `ElabGlobalFunc(module_name, item_name, ...)`
- module-qualified global const refs through `ElabGlobalConst(module_name, item_name, ...)`
- explicit named-package imports that synthesize those env entries automatically for direct imports

Still missing:
- a broader documented namespace story beyond the current authored-dot local-head rule and qualified-only imports
- richer module/package features beyond the current named-module package API

So qualified value refs are no longer a blocker, and the reboot now has a real authored import path, but the broader package story can still grow.

---

## 5.6 `ElabEnv.types` is wired into named-type resolution, and current authored type env synthesis now exists

`ElabEnv` contains:

- `module_name`
- `values`
- `types`
- `layouts`

The current frontend now uses `types` for real `SurfTNamed` lowering.
Named type paths must resolve through explicit `ElabEnv.types` entries, with no lexical fallback.
This includes module-qualified type lookup when the env carries entries like `"Foo.Bar"`.

Current authored infrastructure now synthesizes those type envs from:

- local authored type items
- explicit named-module imports through the package front door

What is still missing is broader namespace/import surface beyond the current qualified import model.

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

## 5.10 Named struct types/layouts are now authored and integrated on the current reboot path

The current frontend now supports an authored top-level path for:

- defining named struct types with `type Name = struct { ... }`
- synthesizing matching layout/type env entries
- using those named types in aggregate literals, field access, and qualified module paths
- carrying them through `Surface -> Elab -> Sem -> resolve_sem_layout`

So named aggregate support is no longer only manual-context support.

Current explicit limitations:

- the authored type-definition story is still basically the named-struct path
- broader type-definition families / richer layout declarations are still future work
- the broader namespace/import story can still grow beyond the current qualified named-module path

---

## 5.11 Intrinsics are now real from authored source through `Sem -> Back` and the Rust backend

The ASDL now carries an explicit intrinsic family across the current closed path:

- `MoonliftSurface.SurfIntrinsic`
- `MoonliftElab.ElabIntrinsic`
- `MoonliftSem.SemIntrinsic`

Authored source can now parse and lower intrinsic calls through the normal frontend path into `SemExprIntrinsicCall`.

Current implemented scalar intrinsic family includes:

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

### Frontend status
The reboot parser and frontend lowering now include intrinsic call parsing/binding and lower those calls through:

- `SurfExprIntrinsicCall`
- `ElabExprIntrinsicCall`
- `SemExprIntrinsicCall`

### `Sem -> Back` status
`SemExprIntrinsicCall` lowers in value position for scalar-result intrinsics and in materialization position where that is meaningful.

### Rust backend / FFI replay status
The backend command vocabulary and Rust Cranelift host include lowering/replay for the intrinsic-backed `BackCmd` forms needed by the currently supported scalar intrinsic family.

Current explicit limitations:

- intrinsic lowering is still scalar-oriented
- intrinsics are not yet part of const evaluation
- there is not yet a richer user-facing intrinsic namespace/binding story beyond the current direct intrinsic call surface

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
- `SemView`
- `SemIndexBaseView`
- `SemDomainView`
- `SemDomainZipEq`

### What is now implemented in lowering
`Sem -> Back` now has an explicit bounded-view lowering path with a real backend result shape for:

- slice/view indexing through `SemIndexBaseView`
- slice/view-backed `SemDomainView` lowering
- slice/view-backed `zip_eq` `over` loops
- explicit contiguous/strided/window/interleaved `SemView*` lowering
- slice/view mem sizing in key runtime cases
- slice/view stack-slot sizing for stack-resident values
- slice/view runtime copying for stack-resident values
- runtime equal-length checks for dynamic `zip_eq` traversal

Still missing or still restricted:

- a fully finished authored-language story for constructing/passing slice/view values through the current non-scalar ABI/value path
- a complete explicit low-level slice/view bounds/checking model beyond the current bounded-view lowering shape
- broader non-scalar load/call/result/materialization completion around slice/view values

So slices/views/domains no longer stop at array-only machine lowering: the backend now lowers bounded slice/view indexing and traversal directly, but the broader non-scalar language/runtime story is still not complete.

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

The global binding space is now split explicitly:

- `SemBindGlobalFunc`
- `SemBindGlobalConst`
- `SemBindGlobalStatic`

Runtime reads exist for statics, while consts are expected to fold or lower through constant-data initialization rather than ordinary runtime binding reads.

But global assignment/store lowering is explicitly not implemented in `Sem -> Back`.

So mutable globals are not currently a real feature.

---

## 5.17 Externs are not first-class runtime values

Extern calls work through call-target lowering.

But direct extern binding reads are not supported, and externs are not addressable as ordinary values in the current lowering model.

So externs are callable, but not fully first-class values.

---

## 5.18 Addressability is still partial

The address-of / place model is explicit now, but still incomplete.

Implemented now:
- address of mutable locals through canonical local-cell stack slots
- address of static globals through `SemBindGlobalStatic`
- address of projected/deref/index places built from those addressable bases
- a real function-scoped `SemResidencePlan` phase boundary for storage/addressability classification
- place-root bindings (`SemPlaceBinding(...)`) now force stack residence in that plan instead of relying only on default-by-type answers

Still missing or restricted:
- the broader not-yet-finished non-scalar/value-model path
- address of pure const globals (`SemBindGlobalConst`)
- address of many computed values except where explicit materialization already exists
- a fully general addressability model across all place categories

So references/places exist in the IR, storage/addressability now has an explicit function-scoped phase answer, and `Sem -> Back` now consumes that answer for pure-value locals/args/loop values, but the broader non-scalar/general-place story is still incomplete.

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

## 5.21 A bootstrap parser / text frontend now exists and already covers most of the current closed reboot surface

There is now an initial reboot parser/front-end in:

- `moonlift/lua/moonlift/parse_lexer.lua`
- `moonlift/lua/moonlift/parse.lua`
- `moonlift/test_parse_smoke.lua`

It already constructs `MoonliftSurface` ASDL values directly for a substantial bootstrap/front-door surface, including:

- top-level items:
  - `func`
  - `extern func`
  - `const`
  - `static`
  - `import`
  - `type ... = struct { ... }`
- types:
  - scalar
  - pointer
  - array
  - slice
  - `view(T)`
  - function type
  - named path
- expressions:
  - literals
  - names / paths
  - unary / binary ops
  - casts
  - intrinsic calls
  - calls / field / index
  - field-based aggregate literals
  - array literals via `[]T { ... }`
  - explicit `select(cond, a, b)`
  - `if` expr
  - `switch` expr
  - block expr
  - canonical loop expr
- statements:
  - `let`
  - `var`
  - `set`
  - expr stmt
  - `if`
  - `switch`
  - `return`
  - `break`
  - `break value`
  - `continue`
  - canonical loop stmt
- public helper facade:
  - `moonlift/lua/moonlift/source.lua`
  - `moonlift/lua/moonlift/source_spans.lua`
  - parse helpers
  - parse-with-spans helpers
  - try-parse helpers with structured diagnostics
  - try-lower / try-sem / try-resolve / try-back / try-compile helpers
  - `parse -> Surface -> Elab`
  - `parse -> Surface -> Elab -> Sem`
  - `pipeline_module`
  - `pipeline_package`
  - `back_module`
  - `back_package`
  - `compile_module`
  - `compile_package`
- current source spans are stored in a parallel **path-keyed** span index rather than a naive `node -> span` map, because interned `Surface` values do not preserve occurrence identity by object identity alone
- current public source helpers can already bridge some lower-stage errors back to source paths/line+column when the lower-stage error carries structural path text

But it is still a bootstrap/front-door rather than the final frozen authored language.

Still missing from the reboot authored front door:

- complete grammar coverage for everything already present in `Surface`
- frozen authored syntax for currently open `Surface` areas such as `view`
- richer diagnostics and source span plumbing through later compiler layers
- hosted fragment / quote syntax

So the reboot is no longer parser-less, and it now has a real authored source front door, but it is not yet the final complete authored text language.

---

## 5.22 A bootstrap top-level compile facade now exists

The pipeline pieces are no longer only manual / semi-manual.
`moonlift/lua/moonlift/source.lua` now exposes real authored-source helpers for:

- `source text -> Surface`
- `source text -> Elab`
- `source text -> Sem`
- `source text -> resolved Sem + synthesized layout env`
- `source text -> BackProgram`
- `source text -> compiled artifact` via `compile_module`
- named source package/module sets -> compiled artifact via `compile_package`

The closed compile path used by those helpers is the real reboot path:

- parse -> `Surface`
- `Surface -> Elab`
- `Elab -> Sem`
- synthesize/resolve layout
- `Sem -> Back`
- JIT compile

What is still missing here is not the existence of a compile facade, but its final stabilization as the single clearly documented public front door, plus richer source-level diagnostics and retirement of stale shortcut paths.

---

## 5.23 Current codegen-shape limitations exposed by `peek`

Recent direct machine-code inspection of small benchmark kernels shows several real remaining design/codegen gaps:

- dense integer `switch` currently lowers as a compare-chain CFG, not as a preserved switch form that could become a jump table
- plain scalar `if` chooses currently lower as branch CFG, not as an explicit select/branchless choice form
- scalar function arguments now stay as backend entry values by default, and function-scoped residence planning materializes storage only when addressability requires it; the same policy now also covers pure scalar loop carries/indices, while general-place/non-scalar cases are still less complete
- authored unsigned / `index` benchmarking is still awkward because type-directed integer literal elaboration is not yet strong enough

So the current backend is already useful for real codegen observation, but some important machine-shape outcomes are still determined by open frontend/lowering policy decisions—especially switch preservation, select/branchless choice, and the still-incomplete storage/addressability policy—rather than by finished intended language semantics.

---

## 5.24 No `Meta` / quote / open-code implementation yet

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

## 6.1 Modules/functions/items and authored struct type items now exist, but the broader language story is still incomplete

This distinction still matters.

### Implemented today
- `SurfFunc` / `ElabFunc` / `SemFuncExport`
- `SurfExternFunc` / `ElabExternFunc` / `SemExternFunc`
- `SurfConst` / `ElabConst` / `SemConst`
- `SurfStatic` / `ElabStatic` / `SemStatic`
- `SurfImport` / `ElabImport` / `SemImport`
- `SurfStruct` / `ElabStruct` / `SemStruct`
- `SurfItem*` / `ElabItem*` / `SemItem*`
- `SurfModule` / `ElabModule` / `SemModule`
- named-module package imports / qualified refs/types through the source helpers
- their downstream `Sem -> Back` lowering

### Still missing today
- broader type-definition families beyond named structs
- broader package/module surface beyond the current named-module path
- a visibility/export distinction for authored functions

---

## 6.2 Field and layout machinery is integrated for the current named-struct path, but broader completion remains

Current real support includes:
- authored top-level struct type declarations
- automatic layout synthesis from authored program items
- named layout env
- field-name resolution to offset
- named aggregate copying/materialization
- field-address and field-load support downstream

But current real missing parts include:
- broader type/layout families beyond the current struct path
- finalizing which unresolved forms may survive past layout resolution
- fuller non-scalar / view-driven layout and value-model completion

---

## 6.3 Loops are strong on `while`, `range`, and bounded view/zip domains; broader non-scalar domain/value completion is still open

Current real support:
- while loops
- `over range(stop)`
- `over range(start, stop)`
- array-backed `over value/view`
- slice/view-backed `over value/view`
- array-backed `zip_eq(...)`
- slice/view-backed `zip_eq(...)` with runtime equal-length checks
- loop exprs and stmt loops
- carry/next machinery

Missing/partial:
- complete low-level domain model for broader multi-domain traversal
- broader non-scalar value creation/ABI/materialization around slice/view values

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

- finalizing and documenting the bootstrap source front door as the clear public authored entry path
- richer diagnostics / source mapping through later compiler layers
- broader package/module surface beyond the current named-module import path
- finishing currently open authored areas such as the final `view` surface story

So the language now has a real authored front door, but that front door is still incomplete and still visibly in bootstrap form.

## 8.3 The biggest missing runtime/value-model areas

The biggest incomplete runtime/value-model areas are:

- slices/views
- fuller const evaluation / immediate propagation
- non-scalar ABI/value support
- storage/addressability classification cleanup
- code-shape preservation for switch/select-sensitive lowering

The repo now also has a ratcheting semantic-dispatch audit for active semantic/backend compiler files:

- `moonlift/test_semantic_dispatch_audit.lua`
- `moonlift/semantic_dispatch_audit_baseline.txt`

The audited active semantic/backend files are currently at **zero baseline findings**.
That means the previously-inventoried raw `.kind` / raw helper type-classification debt in those audited files has been paid down, and new sites should now fail as immediate regressions.

## 8.4 The biggest missing future-architecture area

The biggest planned-but-not-implemented area is the open-code/meta layer described in:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

And the deferred future host/parser integration strategy described in:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`

---

# 9. Short summary

If compressed to one sentence:

> Moonlift already has a real authored parser/source front door, real top-level item lowering through `Surface -> Elab -> Sem`, qualified module imports, authored struct type/layout synthesis, a layout-resolution pass, bootstrap `compile_module` / `compile_package` helpers, and a substantial backend, but it still needs slices/views, fuller const/value-model/ABI completion, richer diagnostics, and the future `Meta` layer; hosted integration remains deferred until after the language and FFI path are finished.

And if compressed even further:

- **expr/stmt/loop core:** real
- **top-level value/type/module frontend:** real
- **bootstrap source compile/package facade:** real
- **scalar backend:** real
- **slice/value-model/meta path:** still incomplete

---

# 10. Related design docs

This file is intentionally only about implementation coverage.

For the future open-code / metaprogramming layer:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

For the deferred future LuaJIT-hosted / parser-hosted integration strategy:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`
