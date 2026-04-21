# Moonlift Complete Language / Hosting / FFI Checklist

Status: end-to-end checklist from the **current reboot state** to a **complete Moonlift language implementation**, including:

- full language/compiler implementation
- open-code / quote / meta layer
- richer hosting integration
- plain FFI layer

This document is intentionally a **checklist**, not a narrative status report.
It is a **living document** and should be updated eagerly whenever implementation reality changes.
Boxes should only be checked when the implementation is real and architecturally correct under the ASDL-first rules in:

- `moonlift/CONTRIBUTING.md`

For the current implementation inventory, see:

- `moonlift/CURRENT_IMPLEMENTATION_STATUS.md`

For the open-code / quoting design target, see:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

For the richer future hosting direction, see:

- `moonlift/LUAJIT_HOSTED_INTEGRATION.md`

---

# 1. Definition of “complete”

This checklist treats Moonlift as complete only when all of the following are true:

- authored source code can define and compile real programs/modules
- the full intended language surface is implemented, not just manual IR construction
- the compiler pipeline is coherent from authored source to machine code
- the open-code / quote / fragment system exists and closes into the ordinary compiler path
- the hosted integration path exists for the rich user experience
- the plain FFI layer exists for library/embed users
- the backend/runtime model can handle the language’s core value categories, not only scalars

So “complete” here means:

- **language complete**
- **compiler complete**
- **meta layer complete**
- **hosting complete**
- **FFI layer complete**

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

But it is still missing major authored-language, meta, hosting, and FFI-completion pieces.

Use this file as the forward checklist from that state.

When checking a box, prefer updating this file in the same change that updates the implementation.
If the implementation required an architectural correction, update the wording here too rather than preserving stale milestones.

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
- [x] implement `SurfItemFunc -> ElabItemFunc`
- [x] implement `SurfItemExtern -> ElabItemExtern`
- [x] implement `SurfItemConst -> ElabItemConst`
- [x] implement `SurfModule -> ElabModule`

### Elab -> Sem top-level
- [x] implement `ElabParam -> SemParam`
- [x] implement `ElabFunc -> SemFunc`
- [x] implement `ElabExternFunc -> SemExternFunc`
- [x] implement `ElabConst -> SemConst`
- [x] implement `ElabItemFunc -> SemItemFunc`
- [x] implement `ElabItemExtern -> SemItemExtern`
- [x] implement `ElabItemConst -> SemItemConst`
- [x] implement `ElabModule -> SemModule`

## 3.2 Environment and namespace synthesis

### Value environments
- [x] synthesize function arg envs automatically from params
- [x] synthesize module item envs automatically from sibling items
- [x] support sibling function references in module scope
- [x] support sibling const references in module scope
- [x] support sibling extern references in module scope

### Type environments
- [x] actually wire `ElabEnv.types` into frontend type resolution
- [x] support named type lookup through the real env path
- [x] support module-qualified type lookup

### Layout environments
- [ ] define the current real source of layout information in the reboot
- [ ] synthesize `ElabTypeLayout` from that source
- [ ] synthesize `SemLayoutEnv` automatically for downstream passes
- [ ] make field access and aggregate construction work without manual test-only env injection

## 3.3 Qualified name/path resolution
- [x] implement `SurfPathRef` value resolution
- [x] support module-qualified value references
- [x] support module-qualified function references
- [x] support module-qualified const references
- [x] support module-qualified type references
- [ ] define shadowing and lookup rules clearly

## 3.4 Type-system completion in current language shape
- [x] implement `SurfTArray` lowering fully
- [x] support non-literal array-count elaboration if intended
- [x] fix/complete `ref` typing (`T -> ptr(T)`) in `Surface -> Elab`
- [x] fix/complete `deref` typing (`ptr(T) -> T`) in `Surface -> Elab`
- [ ] define/addressability rules for all referenceable lvalues
- [x] finalize whether `bool and/or` are strict scalar ops or short-circuit operators
- [x] if short-circuiting is intended, implement CFG lowering for them

## 3.5 Complete authored top-level type/layout story

This depends on the intended reboot language surface.

### If the reboot keeps named types/layouts as imported-only for now
- [ ] document that clearly
- [ ] provide a real import/registration mechanism
- [ ] wire it into normal module compilation

### If the reboot grows authored type definitions
- [ ] add `Surface` type-definition items
- [ ] add `Elab` type-definition items
- [ ] add `Sem` type-definition items or equivalent layout-carrying path
- [ ] add layout synthesis from authored type definitions
- [ ] add module/type namespace integration

## 3.6 Control-flow and loop completion
- [ ] validate final semantics of `while` loops
- [ ] validate final semantics of `over range(stop)`
- [ ] validate final semantics of `over range(start, stop)`
- [ ] implement full `over bounded value` lowering
- [ ] implement full `over zip_eq(...)` lowering
- [ ] define/runtime-check equal-length behavior for zip traversal
- [ ] define complete index/domain typing rules
- [ ] define final semantics of loop expr exit/result values

## 3.7 Switch and block completion
- [ ] finalize switch-key type rules
- [ ] support all intended scalar key kinds
- [ ] decide whether non-scalar switch values are part of the language
- [ ] finalize block-expression reachability/termination rules

## 3.8 Const system completion
- [ ] define complete constant-expression subset
- [x] implement unary const eval
- [x] implement arithmetic const eval
- [x] implement comparison const eval
- [x] implement cast const eval
- [x] implement select/if const eval if intended
- [x] implement field/index projection const eval if intended
- [x] implement aggregate/array const eval coherently
- [ ] define whether calls/intrinsics can appear in const eval
- [ ] support const references between sibling consts/modules in the general const-eval system if intended

## 3.9 Intrinsics completion

### Frontend
- [ ] choose frontend intrinsic syntax/binding surface
- [ ] add Surface representation if needed
- [ ] add Elab representation if needed
- [ ] map frontend intrinsic calls into `SemIntrinsic`

### Sem -> Back
- [ ] implement `SemExprIntrinsicCall` lowering in value position
- [ ] implement `SemExprIntrinsicCall` lowering in materialization position where meaningful
- [ ] define which intrinsics are scalar-only vs aggregate/vector-only

### Backend
- [ ] map each `SemIntrinsic` to `BackCmd` and/or direct backend lowering strategy
- [ ] implement/populate support for:
  - [ ] `popcount`
  - [ ] `clz`
  - [ ] `ctz`
  - [ ] `rotl`
  - [ ] `rotr`
  - [ ] `bswap`
  - [ ] `fma`
  - [ ] `sqrt`
  - [ ] `abs`
  - [ ] `floor`
  - [ ] `ceil`
  - [ ] `trunc_float`
  - [ ] `round`
  - [ ] `trap`
  - [ ] `assume`

## 3.10 Aggregate/value-model completion
- [ ] finalize named aggregate representation strategy in the reboot
- [ ] complete aggregate load/store/materialization rules
- [ ] support array value indexing end-to-end
- [ ] support slice value indexing end-to-end
- [ ] support aggregate field addressing and copying uniformly
- [ ] define whether function values are storable/passable and implement accordingly

## 3.11 Sem layout resolution completion
- [ ] ensure all field projections use resolved layout when required
- [ ] ensure all field addresses use resolved offsets when required
- [ ] ensure all named aggregate copies/materializations use resolved layouts automatically
- [ ] define whether unresolved field refs may ever survive past layout resolution

## 3.12 Complete compiler front door
- [ ] define the canonical public compile pipeline for closed code
- [ ] wire `Surface module -> Elab -> Sem -> resolve_sem_layout -> Back -> JIT`
- [ ] make that one official path the default compile path
- [ ] remove/retire stale direct shortcuts that bypass the real architecture

---

# 4. Phase B — Complete the backend/runtime model for the language

Goal:

- make the runtime/codegen layer able to represent the real language, not just a scalar subset

## 4.1 `Sem -> Back` missing pieces
- [ ] implement full slice/view lowering model
- [ ] implement bounded-value domain lowering
- [ ] implement `zip_eq` lowering
- [ ] implement intrinsic lowering
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
- [ ] decide whether slice/view runtime primitives need dedicated `BackCmd` support

## 4.3 ABI completion
- [ ] decide the final value ABI categories:
  - [ ] scalar values
  - [ ] pointers
  - [ ] aggregates by pointer
  - [ ] aggregates by value
  - [ ] slices/views
  - [ ] multi-result returns
- [ ] support non-scalar return values if the language requires them
- [ ] support multi-result returns if the language requires them
- [ ] support non-scalar call arguments/results coherently
- [ ] define extern ABI rules for aggregates/slices
- [ ] define function-pointer ABI rules for indirect calls

## 4.4 Addressability/lvalue model completion
- [ ] define what counts as an addressable lvalue
- [x] support address of args if intended
- [x] support address of immutable locals if intended
- [x] support address of globals/const data where meaningful
- [ ] define when temporaries are materialized to stack
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
- [ ] choose parser implementation language for the reboot path
- [ ] define parser ownership boundary relative to Lua/host/runtime
- [ ] ensure parser produces `MoonliftSurface`

## 5.2 Surface syntax coverage
- [ ] parse all current type forms
- [ ] parse all expr forms
- [ ] parse all stmt forms
- [ ] parse all loop/domain forms
- [ ] parse all top-level item/module forms
- [ ] parse all intended intrinsic forms
- [ ] parse all intended type/layout declarations if the language includes them

## 5.3 Diagnostics
- [ ] source spans/locations
- [ ] parser diagnostics
- [ ] elaboration/name/type diagnostics
- [ ] better layout/type error messages
- [ ] module/path resolution diagnostics

## 5.4 Compile facade
- [ ] `source text -> Surface`
- [ ] `source text -> compiled artifact`
- [ ] `source module -> compiled module`
- [ ] source-level error reporting through the canonical public API

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

# 7. Phase E — Complete the rich hosted integration path

Goal:

- implement the richer path described in `moonlift/LUAJIT_HOSTED_INTEGRATION.md`

This is the preferred rich integration path.

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
- make it explicit, documented, and complete enough for LuaJIT users who do not want the richer hosted path

This is the **secondary** path, not the richer architectural center.

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
- [ ] multi-result handling if supported
- [ ] extern registration APIs if needed

## 8.4 FFI marshalling/documentation
- [ ] document ABI rules for all public-callable types
- [x] document lifetime rules
- [x] provide minimal LuaJIT FFI examples
- [x] provide non-hosted library-loading examples

## 8.5 Relationship to hosted path
- [ ] ensure hosted path can reuse the core native machinery
- [x] ensure FFI path remains a thinner compatibility layer, not a second compiler architecture

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
