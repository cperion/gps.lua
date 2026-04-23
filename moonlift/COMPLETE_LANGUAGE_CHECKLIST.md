# Moonlift Complete Language / Hosting / FFI Checklist

Status: end-to-end checklist from the **current reboot state** to a **complete Moonlift language implementation**, including:

- full language/compiler implementation
- open-code / quote / meta layer
- deferred future hosted integration
- plain FFI layer

This document is intentionally a **checklist**, not a narrative status report.
It is a **living document** and should be updated eagerly whenever implementation reality changes.
Boxes should only be checked when the implementation is real and architecturally correct under the ASDL-first rules in:

- `moonlift/CONTRIBUTING.md`

For the frozen closed-language semantic target, see:

- `moonlift/CLOSED_LANGUAGE_SEMANTIC_DECISIONS.md`

For the current implementation inventory, see:

- `moonlift/CURRENT_IMPLEMENTATION_STATUS.md`

For the open-code / quoting design target, see:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

For the deferred future hosting direction, see:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`

---

# 1. Definition of “complete”

This checklist treats Moonlift as complete only when all of the following are true:

- authored source code can define and compile real programs/modules
- the full intended language surface is implemented, not just manual IR construction
- the compiler pipeline is coherent from authored source to machine code
- the open-code / quote / fragment system exists and closes into the ordinary compiler path
- the hosted integration path exists for the richer future user experience, if that path is still pursued
- the plain FFI layer exists as a stable first-class public path for library/embed/LuaJIT users
- the backend/runtime model can handle the language’s core value categories, not only scalars

So “complete” here means:

- **language complete**
- **compiler complete**
- **meta layer complete**
- **FFI layer complete**
- **hosted layer complete, if/when that deferred path is taken on**

---

# 2. Current checkpoint

The current reboot already has:

- a real ASDL stack:
  - `Surface`
  - `Elab`
  - `Sem`
  - `Back`
- real local expr/stmt/loop/domain lowering
- real `Elab -> Sem`
- real `Sem` layout resolution
- real `Sem -> Back`
- real `Back -> Cranelift`
- real FFI replay of `BackCmd`
- a thin plain FFI path already usable today:
  - opaque `jit/program/artifact` handles
  - `BackProgram -> Artifact` compilation
  - function-pointer lookup
  - explicit free APIs

But it is still missing major authored-language, meta, and FFI-completion pieces, while hosted work is intentionally deferred until after the language and FFI path are complete.

Use this file as the forward checklist from that state.

When checking a box, prefer updating this file in the same change that updates the implementation.
If the implementation required an architectural correction, update the wording here too rather than preserving stale milestones.

Current delivery priority order is:

1. close the language/compiler path
2. stabilize and complete the public FFI path
3. only then revisit hosted/state-aware integration

## 2.1 Immediate codegen-guided priorities from `CODEGEN_FINDINGS.md`

These are the current near-term priorities for the closed compiler path.
They should be treated as **ASDL/phase design work first**, not as backend-only peephole tweaking.

### A. Refactor binding/addressability semantics so value, place, and storage are no longer conflated

- [x] add explicit `ElabPlace` / `SemPlace`-style ASDL for addressable computations instead of representing `ref` targets only as generic exprs
- [x] stop encoding storage decisions directly in early/source-facing binding forms when that choice is really machine-facing
- [x] add a dedicated storage/addressability classification phase boundary rather than forcing `let`/arg/loop binders into stored forms up front
- [x] add an explicit `Sem -> Back` binding-class result shape so backend lowering consumes pure/stored/cell distinctions through ASDL rather than ad hoc residence branching
- [ ] split `Sem` binding classes where lowering materially differs all the way in the core semantic IR:
  - [ ] immutable pure value locals
  - [ ] immutable stored locals
  - [ ] mutable cells
  - [ ] pure value params
  - [ ] stored/address-taken params
  - [ ] pure value loop carries / indices
  - [ ] stored/address-taken loop carries / indices
- [x] make `ref` / `deref` / field-address / index-address semantics flow through explicit place nodes instead of hidden storage assumptions

### B. Refactor loop semantics so loop state/exit are explicit, not implied by stmt-list lowering accidents

- [x] distinguish ordinary locals from loop-state ports explicitly in ASDL
- [x] make loop carry ports and loop index ports explicit semantic nouns instead of reusing generic local-binding shapes
- [x] add an explicit loop early-exit result story for expr loops (e.g. `break value`) if early-exit search/probe kernels are intended
- [ ] add an explicit loop-body control/result shape so branchy loop bodies do not depend on ad hoc stmt-lowering/block-fill behavior
- [ ] make shared latch values and loop-invariant values explicit enough in the loop/body model that they can be preserved without forced recomputation or forced stack homes

### C. Split pure compile-time consts from addressable static data

- [x] stop conflating “compile-time value that should inline/fold” with “global addressable data object” in the item/binding story
- [x] add explicit ASDL distinction between pure const items and addressable static/global data if both are intended
- [x] route typed numeric / `index` constants through the pure-const path so trivial constants do not become data loads by accident

### D. Strengthen the view/index model so it can represent real kernels

- [x] replace or extend the current simple slice/view story with explicit view forms that can carry at least base + length + stride (and offset/windowing if needed)
- [x] make bounded/zip loops consume those explicit views rather than rediscovering shape from arbitrary exprs late in `Sem -> Back`
- [ ] make row-base / segment-base / interleaved-base sharing representable in ASDL instead of hoping later lowering rediscovers repeated scalar arithmetic

### E. Preserve code-shape-sensitive control/math structure explicitly

- [ ] preserve first-class switch structure longer so dense/sparse dispatch is not collapsed too early into compare chains
- [x] add a first-class authored/semantic scalar choose/select form when branchless lowering is intended, instead of expecting generic `if` exprs to imply it
- [ ] keep code-shape-sensitive math/data-parallel work ASDL-first:
  - [x] first-class frontend intrinsic surface for operations like `fma`
  - [ ] later explicit SIMD/vector forms if the language wants more than scalar backend recovery

### F. Complete remaining realism gaps exposed by codegen probing

- [ ] strengthen typed literal elaboration and typed const/immediate propagation for unsigned / `index` code
- [ ] fill remaining cast-heavy lowering gaps exposed by realistic kernels
- [ ] make expression-in-loop lowering consistent for existing forms like `SurfIfExpr` across all authored contexts

---

# 3. Phase A — Complete the closed compiler path

Goal:

- make the ordinary closed compiler path complete before layering on the full meta/hosting surface

```text
Surface -> Elab -> Sem -> Back -> Artifact
```

## 3.1 Top-level frontend lowering

### Surface -> Elab top-level

- [x] implement `SurfParam -> ElabParam`
- [x] implement `SurfFunc -> ElabFunc`
- [x] implement `SurfExternFunc -> ElabExternFunc`
- [x] implement `SurfConst -> ElabConst`
- [x] implement `SurfStatic -> ElabStatic`
- [x] implement `SurfImport -> ElabImport`
- [x] implement `SurfTypeDecl -> ElabTypeDecl`
- [x] implement `SurfItemFunc -> ElabItemFunc`
- [x] implement `SurfItemExtern -> ElabItemExtern`
- [x] implement `SurfItemConst -> ElabItemConst`
- [x] implement `SurfItemStatic -> ElabItemStatic`
- [x] implement `SurfItemImport -> ElabItemImport`
- [x] implement `SurfItemType -> ElabItemType`
- [x] implement `SurfModule -> ElabModule`

### Elab -> Sem top-level

- [x] implement `ElabParam -> SemParam`
- [x] implement `ElabFunc -> SemFunc`
- [x] implement `ElabExternFunc -> SemExternFunc`
- [x] implement `ElabConst -> SemConst`
- [x] implement `ElabStatic -> SemStatic`
- [x] implement `ElabImport -> SemImport`
- [x] implement `ElabTypeDecl -> SemTypeDecl`
- [x] implement `ElabItemFunc -> SemItemFunc`
- [x] implement `ElabItemExtern -> SemItemExtern`
- [x] implement `ElabItemConst -> SemItemConst`
- [x] implement `ElabItemStatic -> SemItemStatic`
- [x] implement `ElabItemImport -> SemItemImport`
- [x] implement `ElabItemType -> SemItemType`
- [x] implement `ElabModule -> SemModule`

## 3.2 Environment and namespace synthesis

### Value environments

- [x] synthesize function arg envs automatically from params
- [x] synthesize module item envs automatically from sibling items
- [x] support sibling function references in module scope
- [x] support sibling const references in module scope
- [x] support sibling extern references in module scope
- [x] support sibling static references in module scope
- [x] synthesize imported qualified module envs through the real named-module package path

### Type environments

- [x] actually wire `ElabEnv.types` into frontend type resolution
- [x] support named type lookup through the real env path
- [x] support module-qualified type lookup

### Layout environments

- [x] define the current real source of layout information in the reboot
- [x] synthesize `ElabTypeLayout` from that source
- [x] synthesize `SemLayoutEnv` automatically for downstream passes
- [x] make field access and aggregate construction work without manual test-only env injection along the real module compile path

## 3.3 Qualified name/path resolution

- [x] implement `SurfPathRef` value resolution
- [x] support module-qualified value references
- [x] support module-qualified function references
- [x] support module-qualified const references
- [x] support module-qualified type references
- [x] define the current shadowing/lookup rule set clearly enough for the current reboot path

## 3.4 Type-system completion in current language shape

- [x] implement `SurfTArray` lowering fully
- [x] support non-literal array-count elaboration if intended
- [x] fix/complete `ref` typing (`T -> ptr(T)`) in `Surface -> Elab`
- [x] fix/complete `deref` typing (`ptr(T) -> T`) in `Surface -> Elab`
- [ ] define/addressability rules for all referenceable lvalues
- [x] add explicit place/lvalue ASDL in `Elab` and `Sem` instead of relying on generic exprs for all addressable operations
- [x] move storage classification later than raw frontend elaboration so source-facing binders do not pretend to know final machine storage too early
- [x] split pure-value params from address-taken params explicitly instead of treating every param as stored by default
- [x] split pure loop-carried/index values from address-taken loop bindings explicitly instead of forcing storage for every carried/index binding
- [ ] improve type-directed integer literal elaboration for unsigned / `index` authored code
- [ ] make typed literal elaboration strong enough that ordinary unsigned / `index` benchmarks do not require helper const globals just to type-check cleanly
- [x] finalize whether `bool and/or` are strict scalar ops or short-circuit operators
- [x] if short-circuiting is intended, implement CFG lowering for them

## 3.5 Complete authored top-level type/layout story
This depends on the intended reboot language surface.

### If the reboot keeps named types/layouts as imported-only for now

- [ ] document that clearly
- [x] provide a real import/registration mechanism
- [x] wire it into normal module compilation

### If the reboot grows authored type definitions

- [x] add `Surface` type-definition items
- [x] add `Elab` type-definition items
- [x] add `Sem` type-definition items or equivalent layout-carrying path
- [x] add layout synthesis from authored type definitions
- [x] add module/type namespace integration for the current named-module import path

## 3.6 Control-flow and loop completion

- [ ] validate final semantics of `while` loops
- [ ] validate final semantics of `over range(stop)`
- [ ] validate final semantics of `over range(start, stop)`
- [x] implement array-backed `over value/view` lowering
- [x] implement full slice/view-backed `over value/view` lowering
- [x] implement array-backed `over zip_eq(...)` lowering
- [x] implement full slice/view-backed `over zip_eq(...)` lowering
- [x] define/runtime-check equal-length behavior for zip traversal
- [ ] define complete index/domain typing rules
- [x] define final semantics of loop expr exit/result values
- [x] implement typed loop-signature/header source syntax without changing current loop semantics
- [x] add explicit loop port/state ASDL rather than treating carries/indexes as generic locals with special helper conventions
- [x] add explicit loop early-exit semantics for expr loops if search/probe/scanner kernels are intended to exit immediately on success
- [x] fix structural lowering for branchy loop bodies inside realistic kernels (`if`, nested choice, mixed stmt/expr control)
- [ ] support body-local shared latch values that feed both output/store effects and loop `next` updates without recomputation or hidden helper state
- [ ] represent loop-invariant values strongly enough that obvious hoists do not depend only on manual source reshaping
- [ ] keep loop-carried state in explicit SSA/block-param form unless the binding class explicitly requires addressable storage

## 3.7 Switch and block completion

- [x] finalize switch-key type rules
- [x] implement all currently intended scalar key kinds (`bool`, integral scalars, `index`)
- [x] decide whether non-scalar switch values are part of the language
- [x] preserve dense switch structure late enough in lowering to allow jump-table-like backend codegen when intended
- [x] preserve first-class switch structure through hot loop bodies / interpreter-style dispatch instead of collapsing it early into compare CFG
- [x] preserve authored `select(...)` as choose-shaped semantic lowering rather than expecting generic `if` exprs to imply it
- [ ] finalize block-expression reachability/termination rules

## 3.8 Const system completion

- [x] define complete constant-expression subset
- [x] implement unary const eval
- [x] implement arithmetic const eval
- [x] implement comparison const eval
- [x] implement cast const eval
- [x] implement select/if const eval if intended
- [x] implement field/index projection const eval if intended
- [x] implement aggregate/array const eval coherently
- [x] define whether calls/intrinsics can appear in const eval
- [ ] support const references between sibling consts/modules in the general const-eval system if intended
- [x] split pure compile-time const items from addressable static data items if the language intends both
- [x] strengthen propagation/immediate folding for typed numeric and `index` consts so codegen-sensitive kernels do not route trivial constants through data objects unnecessarily

## 3.9 Intrinsics completion

### Frontend
- [x] choose frontend intrinsic syntax/binding surface
- [x] add Surface representation if needed
- [x] add Elab representation if needed
- [x] map frontend intrinsic calls into `SemIntrinsic`
- [x] make `fma` reachable from authored/frontend code as a first-class code-shape-sensitive operation

### Sem -> Back

- [x] implement `SemExprIntrinsicCall` lowering in value position
- [x] implement `SemExprIntrinsicCall` lowering in materialization position where meaningful
- [x] define which intrinsics are scalar-only vs aggregate/vector-only

### Backend

- [x] map each `SemIntrinsic` to `BackCmd` and/or direct backend lowering strategy
- [x] implement/populate support for:
  - [x] `popcount`
  - [x] `clz`
  - [x] `ctz`
  - [x] `rotl`
  - [x] `rotr`
  - [x] `bswap`
  - [x] `fma`
  - [x] `sqrt`
  - [x] `abs`
  - [x] `floor`
  - [x] `ceil`
  - [x] `trunc_float`
  - [x] `round`
  - [x] `trap`
  - [x] `assume`

## 3.10 Aggregate/value-model completion

- [ ] finalize named aggregate representation strategy in the reboot
- [ ] complete aggregate load/store/materialization rules
- [ ] support array value indexing end-to-end
- [ ] support slice value indexing end-to-end
- [ ] complete the frozen slice/view descriptor model for strided/interleaved/windowed kernels end-to-end
- [ ] support aggregate field addressing and copying uniformly
- [ ] implement storable/passable immutable function values under the frozen no-closure model

## 3.11 Sem layout resolution completion

- [ ] ensure all field projections use resolved layout when required
- [ ] ensure all field addresses use resolved offsets when required
- [ ] ensure all named aggregate copies/materializations use resolved layouts automatically
- [ ] define whether unresolved field refs may ever survive past layout resolution

## 3.12 Complete compiler front door
- [x] define the canonical public compile pipeline for closed code
- [x] wire `Surface module -> Elab -> Sem -> resolve_sem_layout -> Back -> JIT`
- [ ] make that one official path the default compile path
- [ ] remove/retire stale direct shortcuts that bypass the real architecture

---

# 4. Phase B — Complete the backend/runtime model for the language

Goal:

- make the runtime/codegen layer able to represent the real language, not just a scalar subset

## 4.1 `Sem -> Back` missing pieces

- [ ] implement full slice/view lowering model
- [ ] implement bounded-value domain lowering
- [x] implement `zip_eq` lowering
- [x] implement intrinsic lowering
- [x] stop redeclaring direct/extern callees from call sites during `Sem -> Back`
- [x] make loop-carried/index lowering use backend-valid value naming without duplicate bound ids
- [x] lower explicit binding storage class distinctions through an explicit `SemBackBinding` ASDL result instead of leaving them as ad hoc residence checks inside backend lowering
- [x] lower explicit machine-facing switch-arm key distinctions through `SemBackSwitch*` ASDL results instead of re-probing raw switch expressions inside backend lowering
- [ ] lower explicit `SemPlace`-style addressable forms directly instead of inferring addressability from generic exprs late in the backend
- [x] keep params as pure backend values until an explicit addressability requirement forces materialization to storage
- [x] keep loop-carried/index values as pure backend/block-param values until an explicit addressability requirement forces materialization to storage
- [x] keep pure immutable locals/invariants as backend values unless an explicit addressability requirement forces storage
- [x] fix terminated/block-fill handling for branchy loop bodies and body-local shared values
- [ ] complete `SemExprCastTo` value lowering in the canonical expr path
- [ ] complete non-scalar load lowering where intended
- [ ] complete non-scalar call result lowering where intended
- [ ] complete non-scalar loop expr lowering where intended
- [ ] complete non-scalar switch/if/block expr lowering where intended

## 4.2 Back command set completion

- [ ] decide whether the current `BackCmd` set is sufficient for the finished language
- [ ] if not, extend `BackCmd` deliberately rather than encoding everything indirectly
- [ ] implement `BackCmdFrem` or remove it from the intended surface
- [ ] confirm which casts/conversions need direct backend support vs higher lowering
- [ ] decide whether explicit memcpy/memset/data-copy commands should exist
- [ ] decide whether plain scalar choose forms should lower through explicit `BackCmdSelect`/select-shaped semantics instead of branch CFG when intended
- [x] add first-class backend switch/dispatch support if preserved semantic switch structure is meant to survive into Cranelift cleanly
- [x] decide whether first-class switch preservation needs explicit `BackCmd`/Back-plan support rather than only pre-lowered compare CFG
- [ ] decide whether slice/view runtime primitives need dedicated `BackCmd` support

## 4.3 ABI completion

- [x] decide the final value ABI categories:
  - [x] scalar values by value
  - [x] pointers by value
  - [x] function values by value
  - [x] slice descriptors by value
  - [x] view descriptors by value
  - [x] aggregate values by hidden pointer/materialization path
  - [x] single-result only; multi-result returns are not part of the language
- [ ] support non-scalar return values through the frozen hidden-pointer result path
- [ ] support non-scalar call arguments/results coherently under the frozen descriptor/aggregate ABI
- [ ] define extern ABI rules for aggregates/slices/views/function values
- [ ] define function-pointer ABI rules for indirect calls

## 4.4 Addressability/lvalue model completion

- [x] define what counts as an addressable lvalue
- [x] support address of args if intended
- [x] support address of immutable locals if intended
- [x] support address of globals/const data where meaningful
- [ ] define when temporaries are materialized to stack
- [ ] implement the frozen address-taken/materialization trigger for params from pure values to stored values
- [ ] implement the frozen address-taken/materialization trigger for loop carries/index bindings from pure values to stored values
- [ ] make `ref`/`deref` semantics coherent across scalar and aggregate cases

## 4.5 Memory/layout model completion

- [ ] define complete runtime representation for:
  - [ ] named aggregates
  - [ ] arrays
  - [ ] slices/views
  - [ ] function values if storable
- [ ] complete type-size/alignment queries for all supported runtime types
- [ ] complete copy/materialization logic for all supported storable types

## 4.6 Rust backend completion

- [ ] implement all intended `BackCmd` variants in `src/lib.rs`
- [ ] keep `jit.lua` replay in sync with all `BackCmd` variants
- [ ] support full intended artifact/function retrieval model
- [ ] define stable error behavior for unsupported IR
- [ ] decide whether a persistent session/module model replaces or extends the current artifact model

---

# 5. Phase C — Add the complete parser/text frontend

Goal:

- make Moonlift a real authored language, not only ASDL/manual builder construction

## 5.1 Parser architecture

- [x] choose parser implementation language for the reboot path
- [x] define parser ownership boundary relative to Lua/host/runtime
- [x] ensure parser produces `MoonliftSurface`

Current implemented direction:

- hand-written Lua lexer/parser
- direct construction of `MoonliftSurface` ASDL values
- no separate plain-table parser AST as the main representation

## 5.2 Surface syntax coverage

- [x] parse all current type forms
- [x] parse all expr forms currently present in the reboot `Surface` ASDL
- [x] parse all stmt forms currently present in the reboot `Surface` ASDL
- [x] parse all loop/domain forms currently present in the reboot `Surface` ASDL
- [x] parse all top-level item/module forms currently present in the reboot `Surface` ASDL
- [x] parse all intended intrinsic forms in the current reboot closed language
- [x] parse the current authored type/layout declarations (`type ... = struct { ... }`)

Current implemented reboot parser/frontend now includes:

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
  - call / field / index
  - field-based aggregate literals
  - array literals via `[]T { ... }`
  - `if` expr
  - `select(cond, a, b)`
  - `switch` expr
  - `do ... end` block expr
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
- top-level items:
  - `func`
  - `extern func`
  - `const`
  - `static`
  - `import`
  - `type ... = struct { ... }`
  - module packaging

## 5.3 Diagnostics

- [x] source spans/locations at the parser/bootstrap source-front-end layer
- [x] parser diagnostics
- [ ] elaboration/name/type diagnostics
- [ ] better layout/type error messages
- [ ] module/path resolution diagnostics

Current state:

- parser/token diagnostics are structured
- parser exposes parse-with-spans helpers
- source spans are tracked through a path-keyed span index
- public source helpers can already bridge some lower-stage errors back to source paths/line+column when structural path text is available
- so this area is no longer empty, but it is still not complete enough to check the remaining diagnostics boxes

## 5.4 Compile facade

- [x] `source text -> Surface`
- [x] `source text -> compiled artifact`
- [x] `source module/package -> compiled artifact`
- [ ] source-level error reporting through the canonical public API

Current state:

- `moonlift/lua/moonlift/source.lua` exists
- public helpers already cover:
  - `source text -> Surface`
  - `source text -> Elab`
  - `source text -> Sem`
  - `source text -> resolved Sem + layout env`
  - `source text -> BackProgram`
  - `compile_module`
  - `pipeline_package`
  - `back_package`
  - `compile_package`
  - parse-with-spans helpers
  - try-parse / try-lower / try-sem / try-resolve / try-back / try-compile helpers
- compile facade therefore exists in real bootstrap form; what remains open is final stabilization/documentation of that API plus complete source-level error reporting

---

# 6. Phase D — Implement the complete `Meta` / quote / open-code layer

Goal:

- implement the design in `moonlift/QUOTING_SYSTEM_DESIGN.md`

The target is:

- `MoonliftMeta` as a full open elaborated layer
- closure boundary at `Meta -> Elab`

## 6.1 Add `MoonliftMeta` ASDL

- [ ] add `MoonliftMeta` module to the schema
- [ ] add open type layer
- [ ] add open domain layer
- [ ] add open expr layer
- [ ] add open stmt layer
- [ ] add open loop layer
- [ ] add fragment nodes
- [ ] add function nodes
- [ ] add const nodes
- [ ] add item/module nodes
- [ ] add params/imports/slots/interface nodes

## 6.2 Interface categories

- [ ] implement runtime params as first-class values
- [ ] implement imports as first-class values
- [ ] implement kinded slots as first-class values
- [ ] define binder/symbol identity rules

## 6.3 Builder-side `Meta` construction

- [ ] builder expr fragments
- [ ] builder region fragments
- [ ] builder function templates
- [ ] builder const templates
- [ ] builder module templates
- [ ] builder slot constructors
- [ ] builder import constructors

## 6.4 Source-side quote elaboration

- [ ] source expr quotes -> `MetaExprFrag`
- [ ] source region quotes -> `MetaRegionFrag`
- [ ] source func quotes -> `MetaFunction`
- [ ] source const/module quotes if intended
- [ ] elaboration against explicit `MetaInterface`
- [ ] forbid undeclared free names by default

## 6.5 Structural operations in `Meta`

- [ ] slot filling (`:with`) for all slot kinds
- [ ] fragment use / inline assembly nodes
- [ ] item/module splice expansion
- [ ] deterministic binder rebasing
- [ ] alpha normalization / canonicalization
- [ ] closedness validation

## 6.6 `Meta -> Elab` closure

- [ ] close expr fragments to `ElabExpr`
- [ ] close region fragments to `ElabStmt*`
- [ ] close functions to `ElabFunc`
- [ ] close consts to `ElabConst`
- [ ] close modules to `ElabModule`
- [ ] ensure no open slots/imports survive closure

## 6.7 Query/rewrite/walk tooling

- [ ] `Meta` walk APIs
- [ ] `Meta` query APIs
- [ ] `Meta` rewrite APIs
- [ ] structural equality / identity guarantees
- [ ] PVM phases for open-code normalization and closure

## 6.8 Integration with the closed compiler path

- [ ] canonical compile path from `Meta` through `Elab -> Sem -> Back`
- [ ] function/module sealing integrated with ordinary compile pipeline
- [ ] no accidental second semantic universe beyond `Meta`

---

# 7. Phase E — Deferred hosted integration

Goal:

- keep the richer path described in `moonlift/LUAJIT_HOSTED_INTEGRATION.md` as future design work, but do not prioritize it before the closed language and FFI path are complete

This is **not** the current priority.
Hosted/state-aware integration should be revisited only after the language/compiler and public FFI path are complete and stable.

## 7.1 Lua-state-aware native integration

- [ ] define the hosted/state-aware runtime object model
- [ ] expose real session objects
- [ ] expose real artifact objects
- [ ] expose real compiled function objects
- [ ] expose real callback/function userdata where appropriate
- [ ] add `__gc` lifetime management
- [ ] add direct Lua-callable compiled objects
- [ ] add registry-backed hidden retention of native state

## 7.2 Hosted compile/session model

- [ ] persistent compile session object
- [ ] session-local caches
- [ ] module/function artifact retention
- [ ] stable compiled-object identity rules
- [ ] explicit invalidation/rebuild policy where needed

## 7.3 Hosted parser integration

- [ ] choose final hosted parser integration strategy
- [ ] integrate parser with the hosted environment
- [ ] expose parser-backed fragment syntax if the host/parser model allows it
- [ ] unify hosted syntax with builder/source-string semantics via `Meta`

## 7.4 Rich diagnostics and dev UX

- [ ] direct Lua errors from native/session layer
- [ ] source-mapped diagnostics through hosted parser path
- [ ] object introspection / pretty printing for compiled/session objects
- [ ] disassembly/debug hooks from hosted objects

## 7.5 Hosted callback/runtime ergonomics

- [ ] callback registration surface
- [ ] callback lifetime/ownership rules
- [ ] stateful session wiring for callbacks
- [ ] swap/rebuild/rebind story for compiled callbacks

---

# 8. Phase F — Stabilize and complete the plain FFI layer

Goal:

- keep the existing thin public FFI-facing path
- make it explicit, documented, and complete enough for LuaJIT users
- finish the language/compiler through this path before revisiting hosted integration

This is the **current primary public integration path**, not a secondary compatibility layer.

There is already a thin FFI layer today (`moonlift/src/ffi.rs` + `moonlift/lua/moonlift/jit.lua`).
This phase is about stabilizing, documenting, and extending that path rather than inventing it from scratch.

## 8.1 Stable FFI surface design

- [ ] decide stable C ABI surface
- [ ] define opaque handles for:
  - [ ] session
  - [ ] artifact
  - [ ] compiled function
  - [ ] maybe modules/types/layouts if exposed
- [ ] define ownership/free rules clearly
- [ ] define error reporting surface clearly

## 8.2 FFI compile/build APIs

- [x] compile from `BackProgram`
- [ ] compile from higher-level forms if desired
- [x] function lookup APIs
- [ ] module lookup APIs if desired
- [x] explicit free/destruction APIs

## 8.3 FFI calling APIs

- [ ] scalar call helpers
- [ ] pointer call helpers
- [ ] aggregate-by-pointer helpers if needed
- [x] keep the FFI calling API single-result only in line with the frozen language target
- [ ] extern registration APIs if needed

## 8.4 FFI marshalling/documentation

- [ ] document ABI rules for all public-callable types
- [x] document lifetime rules
- [x] provide minimal LuaJIT FFI examples
- [x] provide non-hosted library-loading examples

## 8.5 Relationship to hosted path
- [ ] ensure any later hosted path can reuse the core native machinery
- [x] ensure the FFI path remains a first-class supported public path for LuaJIT users, not a second compiler architecture

---

# 9. Phase G — Polish, coherence, and architecture cleanup

Goal:

- make the whole system coherent enough to count as finished rather than merely feature-complete

## 9.1 Remove stale/obsolete code paths

- [ ] retire stale `lower_surface_to_sem.lua`
- [ ] remove other obsolete shortcuts that no longer match the real architecture
- [ ] ensure one canonical compile path exists for closed code
- [ ] ensure one canonical closure path exists for `Meta`

## 9.2 Public API coherence

- [ ] define the canonical builder API
- [ ] define the canonical source API
- [ ] define the canonical `Meta`/quote API
- [ ] define the canonical hosted/session API
- [ ] define the canonical FFI API
- [ ] ensure these surfaces are related clearly rather than duplicative

## 9.3 Documentation coherence

- [ ] keep `README.md` aligned with actual architecture
- [ ] keep `CONTRIBUTING.md` aligned with actual architecture discipline
- [ ] keep `CURRENT_IMPLEMENTATION_STATUS.md` current
- [ ] keep this checklist current as a living document whenever boxes become true/false or need wording changes
- [ ] keep `QUOTING_SYSTEM_DESIGN.md` aligned with real implementation
- [ ] keep `LUAJIT_HOSTED_INTEGRATION.md` aligned with real integration plan
- [ ] document the final compile pipeline end-to-end
- [ ] document the final value/layout/ABI model end-to-end

## 9.4 Performance and caching coherence

- [ ] ensure PVM boundaries are correct and stable
- [ ] ensure open-code operations are structural and cache-friendly
- [ ] ensure layout resolution is memoized in the right place
- [ ] ensure compile/session caches are architecturally clean
- [ ] ensure hosted and FFI paths do not create duplicate semantic work

---

# 10. Final completion checklist

Moonlift reaches the intended complete state only when all of these are true:

## 10.1 Closed language/compiler

- [ ] authored source code can define real functions, consts, externs, and modules
- [ ] top-level frontend lowering is complete
- [ ] namespace/env synthesis is complete
- [ ] type/layout story is complete for the intended language
- [ ] loops/domains are complete for the intended language
- [ ] const eval is complete for the intended language
- [ ] intrinsics are complete for the intended language
- [ ] `Surface -> Elab -> Sem -> Back` is coherent and canonical

## 10.2 Runtime/backend

- [ ] scalar backend is complete
- [ ] aggregate/slice/value-model backend is complete
- [ ] ABI is complete for intended public/runtime value categories
- [ ] Rust backend supports the intended `BackCmd` set

## 10.3 Meta/open-code system

- [ ] `MoonliftMeta` exists
- [ ] fragments/functions/modules as open code exist
- [ ] structural slot/import system exists
- [ ] `Meta -> Elab` closure exists
- [ ] source/builder/hosted syntax all converge at `Meta`

## 10.4 Hosted integration

- [ ] state-aware hosted path exists
- [ ] parser-hosted or equivalent rich syntax path exists as intended
- [ ] sessions/artifacts/compiled callables are real host objects

## 10.5 FFI layer

- [ ] plain FFI-facing API exists
- [ ] stable ABI/lifetime/error rules are documented
- [ ] FFI users can compile and call Moonlift cleanly without the rich hosted path

## 10.6 Documentation

- [ ] current status, design docs, and public docs all match reality

---

# 11. Short reading order

A good way to use the current docs together is:

1. `moonlift/CONTRIBUTING.md`
   - the ASDL-first rules for making changes correctly
2. `moonlift/CURRENT_IMPLEMENTATION_STATUS.md`
   - what exists right now
3. `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md`
   - what remains to reach completion
4. `moonlift/QUOTING_SYSTEM_DESIGN.md`
   - the target `Meta` / open-code design
5. `moonlift/LUAJIT_HOSTED_INTEGRATION.md`
   - the richer future hosting strategy

That set is the current roadmap stack.
