> **STATUS — April 2026**: This document is a historical migration plan.
> The migration it describes is **complete**. `pvm.lua` is the current
> implementation. The key change from what this plan anticipated:
>
> - `pvm2.verb_memo` / `pvm2.verb_iter` / `pvm2.verb_flat` are all replaced
>   by the single primitive `pvm.phase` (recording-triplet boundary).
> - Handlers return **triplets** `(g, p, c)`, not values.
> - Caching is lazy: cache fills as a side effect of draining, not eagerly.
> - `pvm.verb` no longer exists. `pvm.phase` is the boundary primitive.
> - `pvm.lower` is unchanged (single-value identity cache).
> - `COMPILER_PATTERN.md` and `PVM_GUIDE.md` have been updated to reflect
>   the current implementation.
>
> The concept inventory (Part A) and design principles remain accurate.
> The code examples in Part B outlines are superseded by the updated docs.

---

# Documentation Plan: Comprehensive Inventory & Migration Map

## Overview

Two documents, both long and detailed:

1. **`docs/COMPILER_PATTERN.md`** — "Modeling Interactive Software as Compilers"
   - The paradigm paper. Philosophy, theory, methodology.
   - Audience: framework designers, language researchers, anyone building interactive systems
   - Tone: assertive, precise, example-rich

2. **`docs/PVM_GUIDE.md`** — "The Complete Guide to pvm/uvm"
   - The implementation guide. How to design and build on this stack.
   - Audience: practitioners using pvm/uvm
   - Tone: tutorial + reference, code-heavy

Both preserve every insight from the old docs. Nothing is lost. Everything is updated to
the pvm/uvm architecture that replaced mgps.

---

## Part A: Concept Inventory & Migration Map

### Legend
- ✅ = concept carries forward unchanged
- 🔄 = concept carries forward with updated vocabulary/implementation
- 🆕 = new concept not in old docs
- ❌ = concept is obsolete (but its insight is preserved in a different form)

---

### A.1 — Core Philosophy (from "Modeling Programs as Compilers")

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 1 | ASDL is a language, not a schema | ✅ | Unchanged. Even stronger — ASDL models widgets, tokens, commands, everything | CP §1 |
| 2 | Interactive software is a compiler | ✅ | Unchanged. The central claim. | CP §1 |
| 3 | The semantic product is a machine | 🔄 | The product is a **flat command array**. For-loop replaces gen/param/state. uvm still has gen/param/state for resumable machines. | CP §2 |
| 4 | The gap has layers, and layers are phases | ✅ | Each recursion class = one ASDL layer. Proven in ui5 (3 layers). | CP §2, PG §II |
| 5 | Source phase is the most important | ✅ | Unchanged. Wrong source → wrong everything downstream. | CP §1 |
| 6 | The hard part | ✅ | Unchanged. Tools don't tell you what to model. | CP §1 |
| 7 | Seven Concepts: Source, Event, Apply, Transitions, Terminals, Proto, Unit | 🔄 | **Five Concepts**: Source ASDL, Event ASDL, Apply, Boundaries (verb+lower), Flat Execution. Proto/Unit/Terminal collapse into "boundaries produce flat arrays, for-loops execute them." | CP §2 |
| 8 | The live loop: poll → apply → compile → execute | ✅ | Unchanged. Proven in ui5. | CP §2 |
| 9 | Hot swap is natural | ✅ | Even simpler — new source → memoized boundaries skip unchanged → only changed subtrees recompile | CP §2 |
| 10 | Multiple compilation targets from one source | ✅ | Same View.Cmd array → paint for-loop + hit for-loop. Proven in ui5. | CP §2, PG §19 |
| 11 | Why stronger than "just use immutable data" | ✅ | Unchanged argument. Immutable data is necessary but not sufficient. | CP §3 |

### A.2 — The Three Levels (Compilation, Realization, Execution)

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 12 | Compilation level (pure, structural, memoized) | ✅ | verb and lower are the compilation primitives | CP §3 |
| 13 | Realization level (machine → installable artifact) | 🔄 | **Codegen level**. quote.lua + loadstring replaces the entire proto/realization vocabulary. Codegen IS realization. It's 148 lines, not a conceptual layer. | CP §3 |
| 14 | Execution level (running the installed result) | 🔄 | **For-loop execution**. One `for i=1,#cmds do` per output. The for-loop IS the slot. | CP §3 |
| 15 | Proto language (thin vs rich) | ❌ | Obsolete as a separate concept. Codegen via quote.lua covers the thin case. There IS no rich case in pvm — if you need richer artifact packaging, use uvm machine algebra. The insight (machine meaning must become installable form) is preserved as "codegen is realization." | CP §3 (briefly) |
| 16 | Unit { fn, state_t } | ❌ | Replaced by flat command arrays. No packaging abstraction needed. The "installed artifact" is just a Lua table of Cmd nodes. | — |
| 17 | Realization as host contract | ❌ | Over-engineered for pvm's world. The for-loop is the host contract. Multiple outputs = multiple for-loops. | — |
| 18 | Three Lua realization patterns (closure, template→blob→bind, source kernel) | 🔄 | Becomes: direct Lua (default), codegen via quote.lua (for hot dispatch), loadstring (for specialized hot paths). Simpler and honest. | CP §3 |
| 19 | Bake / bind / live split | 🔄 | Becomes: **baked into ASDL fields** (interned, immutable), **live in Lua state** (mutable per frame). No middle "bind" — interning IS binding. | CP §5, PG §IV |

### A.3 — Machine Design (gen/param/state)

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 20 | gen/param/state as the canonical machine triple | 🔄 | Still exists in **uvm** (family/image/machine). NOT the primary execution model for most apps. Primary model is: ASDL node (interned) → flat Cmd array → for-loop. gen/param/state is the advanced path for resumable/composable machines. | PG §V (uvm) |
| 21 | Terminal contract: M.emit(gen, state_decl, param) | ❌ | Replaced by: verb handlers return values. Lower caches them. No emit ceremony. | — |
| 22 | State declaration algebra (M.state.*) | ❌ | Replaced by: user manages state however they want. Lua tables, FFI cdata, Love2D objects — pvm doesn't care. The ASDL handles the immutable authored structure; mutable state is outside ASDL. | — |
| 23 | M.compose() for machine composition | ❌ | Replaced by: for-loops over flat arrays. Composition IS concatenation of command lists. `table.move` or building a list. | PG §8 |
| 24 | Family / code_shape / state_shape identity system | ❌ | Replaced by: ASDL interning gives structural identity. verb cache keys on node identity (metatable pointer). No separate shape system. | — |
| 25 | Slot system (slot:update, slot:collect, slot:close) | ❌ | Replaced by: the for-loop IS the slot. Recompile → get new Cmd array → run the for-loop on it. No installation/retirement ceremony. | — |
| 26 | Machine IR (typed machine-feeding layer) | 🔄 | The View.Cmd ASDL IS the machine IR. It's a uniform product type with Kind tag. No separate "machine-feeding" concept — the Cmd array IS what the for-loop consumes. | PG §11 |

### A.4 — ASDL Design Methodology

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 27 | Entity / variant / projection / spine / facet vocabulary | ✅ | Unchanged design vocabulary. Still the right way to think about domain modeling. | CP §5 |
| 28 | Step 1: List the nouns | ✅ | Unchanged | CP §5, PG §VII |
| 29 | Step 2: Find identity nouns (entities) | ✅ | Unchanged | CP §5, PG §VII |
| 30 | Step 3: Find sum types (variants) | ✅ | Even more important — sum types determine verb dispatch | CP §5, PG §VII |
| 31 | Step 4: Find containment hierarchy | ✅ | Unchanged | CP §5, PG §VII |
| 32 | Step 5: Find coupling points | ✅ | Unchanged. Coupling points determine layer count. | CP §5, PG §VII |
| 33 | Step 6: Define phases | 🔄 | Phases = ASDL layers. Each recursion class = one layer. The verb at each boundary IS the phase transition. | CP §5, PG §VII |
| 34 | Save/load test | ✅ | Unchanged | CP §5, PG §VII |
| 35 | Undo test | ✅ | Even simpler — swap root ASDL node, memoized boundaries hit cache | CP §5, PG §VII |
| 36 | Collaboration test | ✅ | Unchanged | CP §5 |
| 37 | Completeness test | ✅ | Unchanged | CP §5, PG §VII |
| 38 | Minimality test | ✅ | Unchanged | CP §5, PG §VII |
| 39 | Orthogonality test | ✅ | Unchanged | CP §5, PG §VII |
| 40 | Testing test (one constructor + one assertion) | ✅ | Unchanged. Even cleaner with pvm — construct ASDL, call verb, assert. | CP §5, PG §VII |
| 41 | Design for incrementality | ✅ | Structural sharing via `pvm.with()`. Memoize = verb/lower cache. | CP §5, PG §VII |
| 42 | Verify parallelism | ✅ | Unchanged argument (ASDL graph IS the execution plan) | CP §5 |
| 43 | View projection design | ✅ | Proven in ui5: App.Widget → UI.Node → View.Cmd. View is a projection. | CP §5, PG §III |
| 44 | The convergence cycle (draft → expansion → collapse) | ✅ | Unchanged | CP §8 |
| 45 | Universal phase pattern (vocabulary → semantic → resolved → classified → scheduled → compiled) | 🔄 | Simplified. Most pvm apps have 2-3 layers, not 6 phases. The pattern is the same but flatter. | CP §5 |

### A.5 — The Flatten-Early Rule & Layer Count

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 46 | Flatten-early rule (tree → flat commands → for-loop) | ✅ | **Promoted to core principle**. This is THE execution model. Not just a pattern — it's the canonical form. | CP §4, PG §8 |
| 47 | State is always a stack (push/pop in flat commands) | 🆕 | Derived from flatten theorem. When you flatten a tree, containment becomes push/pop, which is a stack. The stack is the only state shape. | CP §4, PG §9 |
| 48 | Each recursion class = one ASDL layer | 🆕 | The rule that tells you how many layers you need. Structural recursion (tree nodes) = one layer. Constraint cycle (layout) = one more. | CP §4, PG §10 |
| 49 | Layer count = 1 + dependency cycles | ✅ | Unchanged. Count parent↔child cycles. | CP §4, PG §VII |
| 50 | The uniform Cmd product type | 🆕 | View.Cmd is one table shape with Kind singleton tag. LuaJIT sees one metatable → one trace → golden bytecode. This is WHY flatten-early wins. | PG §11 |
| 51 | The for-loop IS the slot | 🆕 | No M.slot(). No installation. The for-loop over Cmd array IS the execution. Recompile = produce new array. Run = iterate it. | PG §12 |
| 52 | Mutual recursion materializes as layers (Ch 38) | ✅ | Unchanged. The worked example of finding cycles in a UI layout is still excellent. | CP §4, PG §VII |
| 53 | Two-phase layout (constraints down, sizes up) | ✅ | Proven in ui5 measure cache. | PG §18 |

### A.6 — Classification Discipline

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 54 | Central classification problem | 🔄 | Simplified from 4 classes to 3: **code-shaping** (sum type → verb dispatch), **payload** (Cmd fields), **dead** (stripped at boundary). "State-shaping" class disappears because pvm has no state declaration algebra. | CP §6, PG §IV |
| 55 | Four classification errors | 🔄 | Becomes three errors: treating code-shaping as payload (string where enum belongs), treating dead as payload (carrying unused fields), treating payload as code-shaping (switching on a value that should be a sum type) | PG §IV |
| 56 | Classification decision procedure | 🔄 | Simpler: Does F determine which verb handler runs? → code-shaping (sum type). Is F still needed downstream? No → dead. Yes → payload. | PG §IV |
| 57 | Field lifecycle tracing (top to bottom) | ✅ | Excellent pedagogical tool. Redo with ui5 fields. | PG §IV |
| 58 | Container lifecycle (consumed vs surviving) | ✅ | Column consumed by layout. Clip survives as PushClip/PopClip. Unchanged. | PG §8 |
| 59 | Sum types across layers (merge/split/disappear/appear) | ✅ | App.Widget variants → UI.Node variants → View.Kind variants. Different at each layer. | PG §IV |
| 60 | Capacity bucketing | 🔄 | Still valid concept but less central without state declarations. Relevant for any resource allocation strategy the user chooses. | PG §VI |

### A.7 — Structural Mechanics

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 61 | Structural interning (same fields → same object) | ✅ | Core of everything. `unique` in ASDL. Codegen constructors (0ns hit, 1.6ns miss). | PG §3 |
| 62 | The interning trie | ✅ | Now code-generated. Unrolled trie, no loop, no select(). | PG §3 |
| 63 | Memoized boundaries | 🔄 | `pvm.lower(name, fn)` + `pvm.verb(name, handlers, {cache=true})`. Code-generated dispatch. | PG §4-5 |
| 64 | Three cache levels (L1 node, L2 code, L3 state) | 🔄 | Simplified to one: **identity cache**. `node_cache[node]` — if same interned object, return cached result. verb adds metatable dispatch before cache. No L2/L3. | PG §4-5 |
| 65 | Structural updates with M.with | ✅ | `pvm.with(node, overrides)` — same semantics. | PG §6 |
| 66 | M.match for sum type dispatch | 🔄 | Replaced by `pvm.verb`. verb does dispatch + cache + method install in one call. | PG §4 |
| 67 | Auto-wiring from schema | ❌ | pvm does NOT auto-wire. You explicitly declare verb handlers. This is better — no magic, full control. | — |

### A.8 — Codegen & quote.lua

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 68 | Code generation via loadstring | 🆕 | Codegen everywhere: ASDL constructors, verb dispatch, lower boundaries. | PG §7, CP §3 |
| 69 | quote.lua: hygienic codegen | 🆕 | val() auto-captures upvalues, sym() creates gensyms, emit() composes quotes. Terra-style metaprogramming for loadstring. | PG §7 |
| 70 | Inspectable generated source | 🆕 | Every codegen'd function stores .source. `widget_to_ui.source` shows the exact code LuaJIT traces. | PG §VII |
| 71 | Codegen as realization | 🆕 | This IS the proto/realization layer, just honest: 148 lines of quote.lua, not a conceptual architecture. | CP §3 |

### A.9 — uvm: Resumable Machine Algebra

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 72 | family / image / machine | 🆕 | uvm's core abstractions. family = machine type, image = immutable config, machine = running instance. | PG §V |
| 73 | Status protocol (RUN/YIELD/TRAP/HALT) | 🆕 | How machines communicate state. Enables stepping, debugging, composition. | PG §V |
| 74 | Composition ops (chain/guard/limit/fuse) | 🆕 | Machine algebra. chain = sequence, guard = conditional, limit = bounded, fuse = decoder+executor. | PG §V |
| 75 | gen/param/state in uvm | 🔄 | gen/param/state lives here. A uvm machine IS gen+param+state with status protocol on top. | PG §V |
| 76 | Grain size determines overhead | 🆕 | Fine-grained (per token) = 7× slower. Coarse-grained (per definition) = 0% overhead. Step at semantic boundaries, recurse within them. | PG §V |
| 77 | Iterator fusion loses to materialized arrays on LuaJIT | 🆕 | Nested closures = polymorphic call sites = trace aborts. Flat array loops win. Materialize at boundaries. | PG §VI |

### A.10 — Performance & Diagnostics

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 78 | Performance has three costs | 🔄 | Now: **rebuild cost** (recompiling changed subtrees), **codegen cost** (loadstring for new dispatch shapes), **execution cost** (for-loop over Cmd array). Simpler than the old three. | PG §VI |
| 79 | Memoize hit ratio as design quality metric | ✅ | `pvm.report()` shows calls/hits/rate. 72% hit rate in ui5 during animation. | PG §VI |
| 80 | The recursive benchmarking law | ✅ | If execution is slow, inspect Cmd shape. If rebuild is slow, inspect ASDL boundaries. | PG §VI |
| 81 | What LuaJIT traces and what it doesn't | 🆕 | Uniform Cmd type = one metatable = one trace. Polymorphic dispatch = trace abort. This drives the entire design. | PG §VI |
| 82 | Frame budget analysis | 🆕 | build_widgets=14µs, compile=1.6µs, paint=343µs. Love2D draw calls are the bottleneck, not the framework. | PG §VI |

### A.11 — What the Pattern Eliminates

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 83 | State management frameworks | ✅ | Still eliminated. Source ASDL + Apply. | CP §7 |
| 84 | Invalidation frameworks | ✅ | Still eliminated. Identity + memoized boundaries. | CP §7 |
| 85 | Observer buses and event-dispatch webs | ✅ | Still eliminated. Event ASDL + Apply. | CP §7 |
| 86 | Dependency injection containers | ✅ | Still eliminated. Resolution phases. | CP §7 |
| 87 | Hand-built runtime interpretation layers | ✅ | Still eliminated. Verb dispatch compiles away the interpretation. | CP §7 |
| 88 | Redundant test scaffolding | ✅ | Still eliminated. Pure functions. Constructor + assertion. | CP §7 |
| 89 | Ad hoc caches and installer glue | ✅ | Still eliminated. verb/lower cache is the only cache. | CP §7 |
| 90 | Virtual DOM / reconciliation | 🆕 | Now explicitly eliminated. ASDL interning IS reconciliation. Same node = skip. Different node = recompute. No diffing. | CP §7 |

### A.12 — Worked Examples

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 91 | UI / Track Editor (main example) | 🔄 | Updated to ui5 architecture. 3 layers, verb boundary, measure cache, uniform Cmd. | CP §8, PG §III |
| 92 | Audio DSP pipeline | 🔄 | Update to pvm. verb per device type. Flat schedule. No M.compose. | CP §8 |
| 93 | Text editor | 🔄 | Update to pvm. Same domain model, pvm boundaries. | CP §8 |
| 94 | Spreadsheet evaluator | 🔄 | Update to pvm. Formula → expression tree → evaluation via verb. | CP §8 |
| 95 | Game entity system | 🔄 | Update to pvm. Entity ASDL → verb per entity kind → Cmd arrays. | CP §8 |
| 96 | Language compiler / parser | 🔄 | Update to pvm + uvm. ASDL parser as uvm machine (proven in asdl_parser3.lua). | CP §8, PG §V |
| 97 | JSON decoder | 🆕 | Proven benchmark. FFI fused = 100MB/s. pvm 3-layer = 85MB/s (1.3× with full ASDL). | PG §VI |

### A.13 — Philosophy (Part X of old GUIDE)

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 98 | Programs are compilers, not interpreters | ✅ | Central thesis. Unchanged. | CP §1 |
| 99 | Why structural identity over reference identity | ✅ | Unchanged. Even stronger with codegen constructors (0ns). | CP §6 |
| 100 | Why classification over convention | ✅ | Unchanged. | CP §6 |
| 101 | Why structure over keys | ✅ | Unchanged. pvm has NO user-managed keys. | CP §6 |
| 102 | Why ASDL over ad hoc types | ✅ | Unchanged. Sum types, interning, validation, method propagation. | CP §6 |
| 103 | Why compilation over interpretation | ✅ | Unchanged. | CP §6 |
| 104 | The invariant | 🔄 | Updated: "Every distinction that matters at runtime is either resolved in the sum type (verb dispatch), present in the Cmd fields (payload), or stripped (dead). Nothing is lost, duplicated, or misclassified." | CP §6 |
| 105 | Why three roles (gen/param/state) and not two or four | 🔄 | This argument now applies specifically to uvm machines. For most pvm apps, the answer is: you don't need three explicit roles. ASDL nodes are the param. Mutable state is separate Lua values. The for-loop is the gen. The decomposition is implicit and natural. | CP §6 |

### A.14 — Design Checklist & Anti-Patterns

| # | Concept | Status | New Form | Doc |
|---|---------|--------|----------|-----|
| 106 | ASDL design checklist | 🔄 | Updated for pvm. No state declarations. No slots. verb/lower instead. | PG §VII |
| 107 | Anti-pattern: God ASDL | ✅ | Still bad. Split into layers. | PG §VII |
| 108 | Anti-pattern: Runtime dispatch on source structure | ✅ | Still bad. Use verb. | PG §VII |
| 109 | Anti-pattern: Closures as gens | 🔄 | Becomes: closures as verb handlers created per-call. Still bad. Define handlers at module scope. | PG §VII |
| 110 | Anti-pattern: Mutation of interned nodes | ✅ | Still bad. Use pvm.with(). | PG §VII |
| 111 | Anti-pattern: Monolithic lowering | ✅ | Still bad. Insert verb/lower boundaries. | PG §VII |
| 112 | Anti-pattern: Polymorphic Cmd types | 🆕 | Multiple metatables in the command loop = LuaJIT trace abort. Use ONE uniform Cmd product type with Kind singleton. | PG §VII |
| 113 | Anti-pattern: Deep nesting instead of flattening | 🆕 | Trees persisting to execution = nested gen calls = overhead. Flatten early. | PG §VII |

---

## Part B: Document 1 Outline — `docs/COMPILER_PATTERN.md`

### Title: "Modeling Interactive Software as Compilers"

### Structure

```
PART 1: THE CORE INSIGHT
  §1.1  The ASDL is a language
  §1.2  Interactive software is a compiler
  §1.3  The gap has layers, and those layers are your boundaries
  §1.4  The source phase is still the most important
  §1.5  The hard part

PART 2: THE FIVE CONCEPTS AND THE LIVE LOOP
  §2.1  Source ASDL
  §2.2  Event ASDL
  §2.3  Apply: (state, event) → state
  §2.4  Boundaries (verb + lower)
        - verb: type-dispatched cached transform (replaces transitions + terminals)
        - lower: identity-cached function boundary
        - both are memoized: same input → skip
  §2.5  Flat Execution (the for-loop)
        - the for-loop IS the slot
        - the Cmd array IS the installed artifact
        - no proto, no Unit, no realization ceremony
  §2.6  The live loop: poll → apply → compile → execute
  §2.7  Hot swap is the natural execution story
  §2.8  The loop is continuous, not one-shot
  §2.9  Multiple outputs from one source

PART 3: THE THREE LEVELS
  §3.1  The compilation level (pure, structural, memoized)
  §3.2  The codegen level (quote.lua, loadstring, inspectable source)
  §3.3  The execution level (for-loops over flat command arrays)
  §3.4  Why this split matters
  §3.5  Codegen IS realization
        - No proto language needed as a separate concept
        - quote.lua (148 lines) covers what mgps needed 600+ lines of
          proto/realization/Unit machinery for
        - Insight preserved: machine meaning must become executable form.
          In pvm that form is "code-generated verb dispatch."
  §3.6  When the three levels compress
        - Small apps: compilation + execution only (no codegen)
        - Medium apps: verb/lower codegen for hot dispatch
        - Large apps: quote.lua for custom hot-path generation
  §3.7  Error handling by level
  §3.8  Testing by level

PART 4: THE FLATTEN THEOREM
  §4.1  Recursive structures are expensive
  §4.2  The canonical form: tree in, flat out, for-loop forever
  §4.3  State is always a stack
        - Derived from flattening. Containment → push/pop → stack.
        - The stack is the ONLY state shape for structural traversal.
  §4.4  Each recursion class = one ASDL layer
        - Structural recursion (tree nodes) = one flattening layer
        - Constraint cycle (layout needs sizes, sizes need constraints) = one more
        - Total layers = 1 + number of cycles
  §4.5  The uniform command type
        - One product type with Kind singleton tag
        - One metatable → one trace → golden bytecode
        - WHY flatten-early wins on modern JITs
  §4.6  Mutual recursion materializes as passes
        - Count parent↔child dependency cycles
        - Each cycle = one additional pass over the same tree
        - All passes over the SAME tree. Output of LAST pass is flat.
  §4.7  Worked example: finding cycles in a UI layout system
        (preserve the full step-by-step from old GUIDE Ch 38)
  §4.8  When NOT to flatten
        - The authoring ASDL stays a tree (users think in containment)
        - Only the boundary-to-execution IR is flat

PART 5: DESIGNING THE ASDL
  §5.0  The architectural vocabulary
        - Entity, variant, projection, spine, facet
        - Source roles vs lower roles
        (preserve all of old §5.0 subsections)
  §5.1  Step 1: List the nouns
  §5.2  Step 2: Find identity nouns (entities)
  §5.3  Step 3: Find sum types (variants)
  §5.4  Step 4: Find containment hierarchy
  §5.5  Step 5: Find coupling points
  §5.6  Step 6: Define phases / layers
  §5.7  Test the source ASDL
        - Save/load, undo, collaboration, completeness,
          minimality, orthogonality, testing
        (preserve ALL test descriptions from old paper)
  §5.8  Design for incrementality
  §5.9  Verify parallelism
  §5.10 Design the view projection

PART 6: TYPE DESIGN PRINCIPLES
  §6.1  Sum types are domain decisions
  §6.2  Records should be deep modules
  §6.3  IDs should be structural
  §6.4  Lists vs maps
  §6.5  Cross-references are IDs, resolved in later phases
  §6.6  Containment anti-patterns (over/under-flattening)
  §6.7  Missing a phase
  §6.8  The invariant: every distinction resolved, present, or stripped

PART 7: WHAT THE PATTERN ELIMINATES
  §7.1  State management frameworks
  §7.2  Invalidation frameworks
  §7.3  Observer buses and event-dispatch webs
  §7.4  Dependency injection containers
  §7.5  Hand-built runtime interpretation layers
  §7.6  Virtual DOM and reconciliation
  §7.7  Redundant test scaffolding
  §7.8  Ad hoc caches and installer glue
  §7.9  The general principle
  §7.10 What does NOT disappear
  §7.11 Warning against reintroducing eliminated machinery

PART 8: THE ASDL CONVERGENCE CYCLE
  §8.1  Draft → Expansion → Collapse
  §8.2  Stage 1: too coarse (top-down draft)
  §8.3  Stage 2: expansion (profiler-driven)
  §8.4  Stage 3: collapse (structural redundancy)
  §8.5  Why you can't regress
  §8.6  Practical signs for each stage
  §8.7  The convergence criterion

PART 9: WORKED EXAMPLES
  §9.1  Track editor (ui5 — primary example, fully detailed)
  §9.2  Text editor
  §9.3  Spreadsheet
  §9.4  Drawing / vector graphics
  §9.5  Game / simulation
  §9.6  Audio DSP
  §9.7  Parser frontend (pvm + uvm)
  §9.8  The applicability test
  §9.9  What is a weaker fit

PART 10: PHILOSOPHY
  §10.1  Programs are compilers, not interpreters
  §10.2  Why structural identity over reference identity
  §10.3  Why classification over convention
  §10.4  Why structure over keys
  §10.5  Why ASDL over ad hoc types
  §10.6  Why compilation over interpretation
  §10.7  Why flat execution over nested dispatch
  §10.8  Why codegen over generic interpretation

THE MASTER CHECKLIST
  (updated for pvm/uvm — preserve every item, update vocabulary)

SUMMARY / FINAL STATEMENT
```

### Estimated length: ~3000-4000 lines
### Content preserved from old docs: ~90% of insights, ~60% of text (rewritten)

---

## Part C: Document 2 Outline — `docs/PVM_GUIDE.md`

### Title: "The Complete Guide to pvm/uvm"

### Structure

```
PREFACE: What this guide is for

PART I — THE FOUNDATION (pvm in 365 lines)
  Ch 1:  What pvm is
         - 5 primitives: context, with, lower, verb, quote
         - Not a framework. A vocabulary.
         - 365 lines of Lua. Everything else is your domain.
  Ch 2:  ASDL — the universal type system
         - What it gives you: sum types, products, interning, validation
         - Defining schemas with context():Define
         - Module nesting (App.Widget, UI.Node, View.Cmd)
         - unique: when and why (answer: almost always)
  Ch 3:  Interning — same values, same object
         - The trie, code-generated constructors
         - 0ns cache hit, 1.6ns miss
         - Why this matters: identity = equality = caching
         - Lists are interned too
  Ch 4:  verb — type-dispatched cached methods
         - verb(name, handlers, {cache=true})
         - Installs :name() on each type
         - Code-generated if-elseif chain on metatable identity
         - Cache on node identity (same interned node → skip)
         - Stats: calls, hits, rate
         - The generated source (inspectable)
  Ch 5:  lower — identity-cached function boundaries
         - lower(name, fn) → callable with cache
         - For non-dispatched transforms (layout, projection)
         - When to use lower vs verb
  Ch 6:  with — structural update preserving sharing
         - pvm.with(node, {field=new_value})
         - Unchanged fields keep identity → downstream caches hit
         - The M.with + structural sharing story
  Ch 7:  quote — hygienic codegen
         - val(v, "name") — auto-capture upvalue
         - sym("hint") — gensym
         - q("fmt", ...) — append line
         - emit(other_q) — splice quotes
         - compile("=name") — loadstring + env
         - Why we have loadstring AND closures (loadstring can inline/specialize)

PART II — THE EXECUTION MODEL
  Ch 8:  Flatten early — tree in, flat out, for-loop forever
         - The canonical form
         - Why trees are expensive (N recursive dispatches per layer)
         - How flattening works (place() walk appends to flat list)
         - Push/pop for containment
         - One tree walk → flat Cmd array → done
  Ch 9:  State is always a stack
         - Push/pop pairs in the flat command stream
         - The graphics backend maintains a clip stack, transform stack
         - This is the ONLY state shape for structural traversal
  Ch 10: Each recursion class = one ASDL layer
         - App.Widget is structural recursion (widgets contain widgets)
         - UI.Node is structural recursion (layout nodes contain layout nodes)
         - View.Cmd is flat (no recursion — just an array)
         - Rule: each recursion boundary becomes one verb/lower boundary
  Ch 11: The uniform Cmd product type
         - View.Cmd = (Kind, htag, x, y, w, h, rgba8, font_id, text, tx, ty)
         - ONE table shape. ONE metatable. ONE trace.
         - Kind is a singleton sum type (Rect, Text, PushClip, ...)
         - Why NOT polymorphic variants (trace abort on mixed metatables)
         - The golden-trace property
  Ch 12: The for-loop IS the slot
         - No M.slot(). No installation. No retirement.
         - Recompile → get new Cmd array → iterate
         - Paint: for i=1,#cmds do ... end
         - Hit: for i=#cmds,1,-1 do ... end (reverse for z-order)
         - This is the entire execution story

PART III — BUILDING A REAL APP (ui5 walkthrough)
  Ch 13: The three ASDL layers
         - App.Widget — domain vocabulary (11 widget types)
         - UI.Node — layout vocabulary (Column, Row, Rect, Text, ...)
         - View.Cmd — draw vocabulary (one uniform product type)
         - How they connect: verb "ui" at App→UI, place() at UI→View
  Ch 14: Layer 1: App.Widget — widgets as ASDL types
         - Defining widget types (TrackRow, Button, Meter, ...)
         - Immediate-mode authoring: call constructors every frame
         - Interning: same track data → same widget → skip
         - The verb boundary: widget:ui() dispatches + caches
  Ch 15: Layer 2: UI.Node — layout vocabulary
         - Column, Row, Padding, Align, Clip, Transform, Rect, Text
         - :measure(mw) — compute sizes given max width
         - :place(x, y, mw, mh, out) — emit positioned View.Cmd
         - Recursive tree walk that produces flat output
  Ch 16: Layer 3: View.Cmd — flat draw commands
         - The uniform product type
         - Kind: Rect | Text | PushClip | PopClip | PushTransform | PopTransform
         - Why all fields are always present (unused fields = 0 or "")
         - The paint for-loop
         - The hit for-loop (reverse order)
  Ch 17: The verb boundary — widget:ui()
         - pvm.verb("ui", { [T.App.TrackRow] = fn, ... }, {cache=true})
         - Generated dispatch code (11 if-elseif arms)
         - 72% cache hit rate during animated playback
         - Inspecting the generated source
  Ch 18: The measure cache — resolving the constraint cycle
         - Text height depends on available width (constraint from parent)
         - Parent height depends on child heights (measurement from children)
         - One cycle → need cached_measure(node, max_width)
         - Cache on (node identity × constraint width)
         - Why this eliminates the need for a Sized.Node intermediate tree
  Ch 19: Hit testing as a second for-loop
         - Same View.Cmd array. Different consumer.
         - Reverse iteration (top element = last painted = first hit)
         - Clip/Transform state tracked via stack (same push/pop)
         - Returns tag of hit element
  Ch 20: The frame budget — where time actually goes
         - build_widgets = 14.3µs (90%)
         - compile (layout) = 1.6µs (10%)
         - Total framework = 16µs = 1% of 16ms frame budget
         - Paint (Love2D draw calls) = 343µs — the real bottleneck
         - What this means for architecture decisions

PART IV — THE CLASSIFICATION DISCIPLINE
  Ch 21: Code-shaping = sum types = verb dispatch
         - App.Widget variants → different :ui() handlers
         - UI.Node variants → different :measure()/:place() methods
         - View.Kind variants → different branches in the for-loop
         - If you're switching on a string/number at runtime, it should be a sum type
  Ch 22: Payload = Cmd fields
         - x, y, w, h, rgba8, font_id, text — all payload
         - They don't affect which code runs
         - They don't affect caching (Cmd is interned, identity = cache key)
  Ch 23: Dead fields — strip at the boundary
         - tag is dead at paint time (paint doesn't use it)
         - rgba8 is dead at hit time (hit doesn't use color)
         - In ui5: View.Cmd carries everything. Each consumer ignores irrelevant fields.
         - Trade-off: one Cmd type (uniform, fast) vs per-backend Cmd (smaller, more work)
  Ch 24: The interning test
         - Construct two nodes with same fields. Assert they're the same object.
         - If not → unique is missing or bypassed
         - If identity changes on pure-payload edit → structural sharing is broken

PART V — uvm: RESUMABLE MACHINE ALGEBRA
  Ch 25: When you need uvm
         - pvm handles: ASDL schemas, memoized boundaries, flat execution
         - uvm adds: stepping, yielding, resuming, machine composition
         - Use cases: parsers that pause mid-stream, interactive debuggers,
           cooperative multitasking, incremental compilation
  Ch 26: family / image / machine
         - family: the machine type (gen + init + patch + meta)
         - image: an immutable configuration snapshot
         - machine: a running instance (gen + param + state + status)
         - The relationship: family creates images, images spawn machines
  Ch 27: Status protocol
         - RUN = not finished, continue stepping
         - YIELD = produced a value, can continue
         - TRAP = machine signalled an exceptional condition
         - HALT = finished
  Ch 28: Composition ops
         - chain(fa, fb): run A, feed result to B
         - guard(fam, fn): run only if guard passes
         - limit(fam, n): run at most n steps
         - fuse(decoder, exec): decode stream into dispatch
  Ch 29: Worked example: ASDL parser as uvm machine
         - asdl_parser3.lua: coarse-grained (step per definition)
         - Matches recursive speed (1.1×)
         - Full resumability at definition boundaries
         - Shows the grain-size principle
  Ch 30: Grain size determines overhead
         - Fine-grained (per token): 7× slower
         - Coarse-grained (per definition): 0% overhead
         - Rule: step at semantic boundaries, recurse within

PART VI — PERFORMANCE AND DIAGNOSTICS
  Ch 31: pvm.report() — the design-quality metric
         - Shows calls, hits, rate per verb/lower boundary
         - 90%+ = excellent. Below 50% = ASDL design problem.
         - The memoize hit ratio IS the architecture quality metric
  Ch 32: Codegen inspection — reading generated source
         - verb.source shows the dispatch function
         - ASDL constructor codegen shows the interning trie
         - quote.lua stores source on compiled functions
  Ch 33: Bench patterns
         - Cold (first call, cache miss) vs Hot (cache hit)
         - Codegen ASDL ctor: 0ns hit, 1.6ns miss
         - Codegen verb: 0.7ns hit
         - Codegen lower: 0.9ns hit
         - JSON 3-layer benchmark: 85 MB/s (1.3× vs raw FFI)
  Ch 34: What LuaJIT traces and what it doesn't
         - Uniform Cmd type → one metatable → traces
         - Mixed metatables in a loop → trace abort
         - Closures in loops → polymorphic call → abort
         - select()/type() in hot path → NYI → abort
         - This is why: codegen constructors, uniform Cmd, flat arrays

PART VII — DESIGN METHODOLOGY
  Ch 35: The complete design method
         - List nouns, find sums, draw containment, find coupling
         - Count dependency cycles → layer count
         - Start at both ends (user ASDL + terminal for-loop)
         - Meet in the middle
  Ch 36: Test the ASDL
         - Save/load, undo, completeness, minimality, orthogonality, testing
  Ch 37: Design for incrementality
         - unique everywhere. pvm.with() for updates.
         - Structural sharing: unchanged subtrees = same objects = cache hits
  Ch 38: The convergence cycle
         - Draft → expansion → collapse
         - Signs for each stage
         - Convergence criterion
  Ch 39: Leaves-up discovery
         - Imagine the for-loop you want
         - What Cmd fields does it need?
         - What ASDL layer produces those Cmds?
         - What layer above that produces the nodes?
         - Recurse upward until you reach the user's vocabulary
  Ch 40: The design checklist
         (comprehensive, updated for pvm/uvm)
  Ch 41: Common anti-patterns
         - God ASDL, runtime string dispatch, closures per call,
           mutation of interned nodes, polymorphic Cmd types,
           deep nesting instead of flattening, monolithic boundaries

APPENDICES
  A: ASDL syntax quick reference
  B: pvm API reference
  C: uvm API reference
  D: quote.lua API reference
  E: The 9 invariants of a well-designed pvm system
  F: Common layer stacks by domain
  G: Glossary
```

### Estimated length: ~4000-5000 lines
### Content preserved from old guide: ~85% of insights, ~40% of text (heavily rewritten)

---

## Part D: What's Genuinely Lost (and why that's OK)

These concepts from the old docs do NOT appear in the new ones because
pvm/uvm made them unnecessary:

1. **State declaration algebra** (M.state.none/ffi/value/resource/product/array)
   - Why lost: pvm has no state management. User handles mutable state.
   - Insight preserved: the CLASSIFICATION of what's mutable vs immutable still matters.
     It's just not formalized into a framework abstraction.

2. **Family / code_shape / state_shape identity system**
   - Why lost: ASDL interning + verb cache replaces all of this.
   - Insight preserved: same structure = same identity = skip work.

3. **Slot lifecycle (update/collect/close)**
   - Why lost: the for-loop IS the slot.
   - Insight preserved: "the currently installed artifact runs until source changes."

4. **M.compose() and nested gen calls**
   - Why lost: flat arrays + for-loops replace recursive composition.
   - Insight preserved: the flatten-early rule IS the composition story.

5. **Proto language as a first-class concept (14 pages in old paper)**
   - Why lost: codegen via quote.lua (148 lines) covers it.
   - Insight preserved: "machine meaning must become executable form."
     That form is now just "code-generated dispatch function."

6. **Host contract abstraction (audio contract, view contract, etc.)**
   - Why lost: each output is just a for-loop. Multiple outputs = multiple for-loops.
   - Insight preserved: different outputs have different execution shapes.

7. **Auto-wiring from schema (M.context(verb) auto-dispatching)**
   - Why lost: pvm uses explicit verb handler tables. More honest.
   - Insight preserved: sum types determine dispatch.

---

## Part E: Writing Order

Suggested order of writing:

1. **PVM_GUIDE.md Part I** (foundation) — establishes the 5 primitives
2. **PVM_GUIDE.md Part II** (execution model) — flatten theorem, uniform Cmd
3. **COMPILER_PATTERN.md Part 1-2** (core insight, five concepts)
4. **PVM_GUIDE.md Part III** (ui5 walkthrough) — the real proof
5. **COMPILER_PATTERN.md Part 4** (flatten theorem, full treatment)
6. **COMPILER_PATTERN.md Part 5** (ASDL methodology — mostly preserved)
7. **PVM_GUIDE.md Part IV-V** (classification, uvm)
8. **COMPILER_PATTERN.md Part 7-9** (eliminates, convergence, examples)
9. **PVM_GUIDE.md Part VI-VII** (performance, design method)
10. **COMPILER_PATTERN.md Part 6, 10** (type principles, philosophy)
11. **Both: appendices, checklists, glossaries**

This interleaving lets each document inform the other as we write.
