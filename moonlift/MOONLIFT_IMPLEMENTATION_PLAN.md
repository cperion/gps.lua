# Moonlift Implementation Plan

Status: staged implementation plan from the current Moonlift builder/runtime to the full Moonlift-native parsed language described in:

- `moonlift/MOONLIFT_SPEC.md`
- `moonlift/MOONLIFT_NAMING.md`
- `moonlift/MOONLIFT_GRAMMAR.md`

This plan is intentionally practical and file-oriented. It assumes the current repository layout:

- `moonlift/lua/moonlift/init.lua` — host API, builder DSL, quoting, layout helpers
- `moonlift/src/runtime.rs` — Lua<->Rust bridge, lowered-table ingestion
- `moonlift/src/cranelift_jit.rs` — typed IR definitions + Cranelift lowering/codegen
- `moonlift/src/luajit.rs` — LuaJIT FFI bindings
- `moonlift/examples/*.lua` — integration tests/examples/benches

---

## 1. Current baseline

Today Moonlift already has useful pieces:

### 1.1 Present strengths

- typed scalar system
- pointer/layout surface
- structs/arrays/unions/tagged unions/enums/slices in the builder layer
- quote / hole / rewrite / walk / query support
- Cranelift lowering for a useful low-level subset
- Lua-hosted interop surface
- executable examples and benchmark scripts

### 1.2 Current architectural shape

The current stack is roughly:

```text
Lua builder DSL
    -> lowered Lua tables
        -> Rust parse_function_spec / parse_expr / parse_stmt
            -> FunctionSpec / Expr / Stmt
                -> Cranelift lowering
                    -> machine code
```

### 1.3 Main gap

The main gap is not “missing helpers.”
It is:

> the absence of a real Moonlift source frontend.

Until Moonlift has a parser and typed source AST, it will continue to feel primarily like a builder DSL.

---

## 2. Target end state

The target architecture is:

```text
Moonlift source string
    -> lexer
    -> parser
    -> source AST
    -> name resolution
    -> type checking / layout resolution
    -> typed Moonlift IR
    -> optional quote / rewrite transforms
    -> direct-call module lowering
    -> Cranelift backend
    -> machine code
```

The current builder DSL remains, but moves down one layer:

```text
builder DSL / quotes / rewrites
    -> same typed Moonlift IR
```

That shared IR is the key design constraint.

---

## 3. Guiding rules

### 3.1 Do not fork semantics
The parser frontend and the builder frontend must lower to the same typed IR model.

### 3.2 Keep the current builder layer alive
Do not replace `lua/moonlift/init.lua` with a parser-only surface. Keep the builder DSL as:

- macro substrate
- IR construction layer
- escape hatch
- bootstrap layer

### 3.3 Make direct calls a first-class compiler feature
Known Moonlift-to-Moonlift calls must become direct calls inside a compiled unit/module.

### 3.4 Stabilize determinism before adding syntax sugar
The compiler core must stay deterministic under:

- tagged union numbering
- switch lowering
- specialization cache keys
- quote expansion

### 3.5 Add diagnostics early
Do not bolt diagnostics on at the end.
Spans and source mapping should appear in the parser/typechecker stage, not after everything is lowered.

---

## 4. Proposed milestone plan

## Milestone 0 — lock down current builder/runtime invariants

Goal: make the current implementation a reliable foundation.

### Deliverables

- keep bool semantics canonical
- keep deterministic `switch_` lowering
- keep deterministic tagged-union tag assignment
- keep expression-block termination errors non-panicking
- expand regression coverage around these invariants

### Files

- `moonlift/src/cranelift_jit.rs`
- `moonlift/src/runtime.rs`
- `moonlift/lua/moonlift/init.lua`
- `moonlift/examples/hello.lua`

### Exit criteria

- no known correctness regressions in the builder layer
- examples remain green
- the lowered-table path is stable enough to treat as the initial IR ingestion path

---

## Milestone 1 — introduce frontend infrastructure in Rust

Goal: create the substrate for a real parser without yet replacing the current builder path.

### New files

Recommended additions:

- `moonlift/src/source.rs`
- `moonlift/src/token.rs`
- `moonlift/src/lexer.rs`
- `moonlift/src/ast.rs`
- `moonlift/src/parser.rs`
- `moonlift/src/diag.rs`

### Responsibilities

#### `src/source.rs`
Own:

- source text storage
- file/virtual-file naming
- byte offsets
- line/column mapping
- span utilities

#### `src/token.rs`
Own:

- token kinds
- punctuation/op classification
- keyword classification

#### `src/lexer.rs`
Own:

- lexing Moonlift source
- comment skipping
- string/integer/float tokenization
- splice token boundaries (`@{...}`)
- hole token boundaries (`?name: Type` start)

#### `src/ast.rs`
Own untyped source AST:

- module items
- statements
- expressions
- type syntax
- attributes
- spans on all nodes

#### `src/parser.rs`
Own:

- `parse_code_item`
- `parse_module`
- `parse_expr`
- `parse_type`
- `parse_extern_block`

#### `src/diag.rs`
Own:

- structured diagnostics
- primary/secondary spans
- formatted error strings

### Host integration

Add new Rust entry points callable from Lua for parsing only, before typechecking/compilation.

Possible runtime exports:

- `__moonlift_backend.parse_code`
- `__moonlift_backend.parse_module`
- `__moonlift_backend.parse_expr`
- `__moonlift_backend.parse_type`

These can initially return debug strings or temporary serialized ASTs for bring-up.

### Exit criteria

- parser can round-trip canonical examples from docs
- parser diagnostics point at sensible spans
- no backend compilation required yet

---

## Milestone 2 — define a real typed IR boundary

Goal: stop treating lowered Lua tables as the only frontend IR.

### Current issue

Today `runtime.rs` parses ad hoc lowered Lua tables directly into:

- `FunctionSpec`
- `Expr`
- `Stmt`

This is fine for the builder path, but the parser frontend needs a cleaner typed-IR boundary.

### Plan

Introduce a distinct layer in Rust:

- source AST
- typed IR

Recommended new file:

- `moonlift/src/ir.rs`

### Suggested split

#### Source AST (`ast.rs`)
Unresolved syntax tree:

- names are textual
- types may be unresolved names
- spans preserved
- sugar still present

#### Typed IR (`ir.rs`)
Resolved/lowered tree:

- concrete type IDs or resolved type descriptors
- explicit function signatures
- explicit layout decisions where needed
- direct-call targets represented distinctly from indirect-call targets
- deterministic item ordering

### Interaction with current `cranelift_jit.rs`
There are two good options.

#### Option A
Move IR definitions out of `cranelift_jit.rs` into `ir.rs`, and have `cranelift_jit.rs` consume them.

#### Option B
Keep the current IR types in `cranelift_jit.rs` temporarily, but define a typed lowering layer that targets those existing structs.

Recommendation:

- do **Option B first** for lower churn
- move to **Option A** once the parser/typechecker path is stable

### Exit criteria

- parser frontend can lower to the same typed IR shape that builder-generated lowered tables target
- existing builder path still works unchanged or with a thin adapter

---

## Milestone 3 — name resolution and type checking

Goal: make Moonlift source semantically meaningful.

### New files

Recommended additions:

- `moonlift/src/scope.rs`
- `moonlift/src/typesys.rs`
- `moonlift/src/typecheck.rs`
- `moonlift/src/layout.rs`

### Responsibilities

#### `src/scope.rs`
Own:

- lexical scopes
- module item scopes
- impl method lookup scopes
- duplicate declaration checks

#### `src/typesys.rs`
Own:

- canonical scalar types
- named types
- pointer/array/slice/function type constructors
- enum/tagged/aggregate type identities

#### `src/layout.rs`
Own:

- struct field offsets
- union size/alignment
- array stride
- tagged-union layout expansion
- `sizeof/alignof/offsetof`

#### `src/typecheck.rs`
Own:

- expression type inference/checking
- statement checking
- lvalue checking
- aggregate literal checking
- method resolution
- cast validity
- function signature checking

### Important semantic jobs

- `func(...) -> T` type parsing and checking
- `extern func` validation
- pointer auto-projection (`p.x`, `p[i]` where `p: &T`)
- bool canonical semantics in checked IR
- block-value rules
- quote hole typing

### Exit criteria

- parser examples typecheck
- diagnostics contain spans and useful messages
- successful typechecked AST lowers to backend IR

---

## Milestone 4 — direct-call module compilation

Goal: make Moonlift feel like a real compiled language rather than a function-pointer DSL.

### Current issue

The current system tends to compile functions one at a time and represent Moonlift-to-Moonlift calls indirectly.

That hurts:

- recursion
- mutual recursion
- inlining
- optimizer quality
- user perception

### Plan

Add a module compilation pipeline that:

1. declares all functions first
2. creates stable internal symbols / function IDs
3. resolves known callees to direct call targets
4. lowers bodies afterward
5. finalizes the module at the end

### Likely file changes

- `moonlift/src/cranelift_jit.rs`
- maybe new `moonlift/src/compile.rs`
- maybe new `moonlift/src/symbols.rs`

### Suggested compiler split

#### `src/compile.rs`
Own:

- module compilation orchestration
- declaration pass
- definition pass
- specialization cache integration

#### `src/symbols.rs`
Own:

- item symbol table
- exported symbol naming
- link names
- internal symbol identity

### Cranelift changes

Teach call lowering to distinguish:

- direct internal Moonlift call
- imported direct extern call
- indirect function-pointer call

### Exit criteria

- functions in one module call each other directly
- recursion works
- mutual recursion works
- indirect call path still exists where semantically required

---

## Milestone 5 — Lua host API for parsed source

Goal: expose the real language to users without dropping the builder API.

### Main file

- `moonlift/lua/moonlift/init.lua`

### Add canonical parser-facing APIs

- `ml.code[[...]]`
- `ml.module[[...]]`
- `ml.expr[[...]]`
- `ml.type[[...]]`
- `ml.extern[[...]]`
- `ml.cimport[[...]]`
- `ml.quote.func[[...]]`
- `ml.quote.expr[[...]]`
- `ml.quote.block[[...]]`
- `ml.quote.type[[...]]`
- `ml.quote.module[[...]]`

### Implementation approach

#### Stage 1
String goes to Rust parser, which returns a typed/serialized structure that Lua wraps.

#### Stage 2
Lua receives first-class handles for:

- source item
- module
- quote fragment
- typed expression
- type object

### Important design constraint

Do not hide the existing builder layer.

Instead structure the public API like this:

```text
ml.code / ml.module / ml.expr / ml.type   -- parsed frontend
ml.quote.*                                 -- parsed quote frontend
ml.func / let / var / block / quote        -- raw builder / IR layer
```

### Exit criteria

- docs/examples can be written primarily in parsed source syntax
- old builder examples still work

---

## Milestone 6 — unify quote system across parser and builder paths

Goal: keep Moonlift's strongest differentiator: structured staged metaprogramming.

### Current strength

The current Lua quote/rewrite/walk/query facilities are already a strong seed.

### Problem

If the parsed source frontend grows separately from the builder quote path, Moonlift ends up with two meta systems.

### Plan
All parsed quote forms must lower to the same underlying quote/IR representation used by the current quote machinery, or at least to a compatible representation with the same operations.

### Requirements

Quotes from source syntax must support:

- `:splice(...)`
- `:bind{...}`
- `:rewrite{...}`
- `:walk(...)`
- `:query(...)`

### Likely changes

- `moonlift/lua/moonlift/init.lua`
- possibly new Rust serialization helpers for quote fragments
- possibly new AST/IR conversion layer for quote round-trip

### Exit criteria

- parsed quote fragments and builder quote fragments behave identically from Lua
- quote hygiene and hole typing are preserved

---

## Milestone 7 — C import and interop upgrade

Goal: reach Terra-adjacent interop quality without Terra naming.

### Current state

Manual interop exists via:

- `extern(...)`
- `import_module(...)`
- numeric/code-address call paths

### Missing piece

A real import frontend.

### Plan

Add:

- `ml.cimport[[ ... ]]`

with one of two stages.

#### Stage A — manual parser for a constrained C declaration subset
Support:

- function prototypes
- typedef aliases
- structs
- enums
- opaque forward declarations

#### Stage B — libclang-backed importer
Preferred long-term route.

### New file candidates

- `moonlift/src/cimport.rs`
- maybe `moonlift/src/clang.rs`

### Exit criteria

- `cimport` produces Moonlift-visible externs/types
- layout matches C ABI for imported declarations
- imported functions call cleanly from parsed Moonlift source

---

## Milestone 8 — diagnostics and tooling

Goal: make Moonlift feel like a compiler, not just a runtime wrapper.

### New or expanded files

- `moonlift/src/diag.rs`
- `moonlift/src/source.rs`
- `moonlift/lua/moonlift/init.lua`

### Add tooling methods

Target surface:

- `f:dump_source()`
- `f:dump_ir()`
- `f:dump_clif()`
- `f:dump_asm()`
- `mod:dump_symbols()`
- `quote:dump()`

### Diagnostics must include

- parse spans
- type mismatch notes
- duplicate declaration spans
- quote expansion origin notes
- splice origin notes

### Exit criteria

- compilation failures produce good source-oriented messages
- users can inspect typed IR and backend IR

---

## Milestone 9 — optimization and specialization

Goal: make Moonlift-generated code feel more competitive and language-like.

### Needed work

- module-level constant folding
- dead code elimination before backend lowering
- direct-call inlining hooks
- specialization cache keyed on typed IR + compile-time inputs

### New file candidates

- `moonlift/src/opt.rs`
- `moonlift/src/specialize.rs`

### Important note

Do not start here.
This milestone only pays off once the parser, typechecker, and direct-call module compilation exist.

### Exit criteria

- direct internal calls inline when profitable
- specialization of spliced/quoted code is cached deterministically

---

## 5. Detailed file-by-file recommendations

## `moonlift/lua/moonlift/init.lua`

### Keep

- builder DSL
- quote/rewrite/walk/query user surface
- layout/type host objects
- compiled function handle wrappers

### Add

- parsed-source APIs (`code`, `module`, `expr`, `type`, `extern`, `cimport`)
- parsed quote APIs (`ml.quote.func`, etc.)
- pretty-printer / dump hooks
- canonical aliases only where helpful (`source` as optional alias for `code`)

### Avoid

- duplicating parser logic in Lua
- building a separate semantic model in Lua for the parsed frontend

Lua should remain the host and meta surface, not the main parser/typechecker implementation.

---

## `moonlift/src/runtime.rs`

### Current role

- bridge between Lua and Rust
- parse lowered Lua tables into `FunctionSpec` / `Expr` / `Stmt`
- invoke compilation and calls

### Evolve into

- unified frontend bridge
- lowered-table ingestion for builder path
- parsed-source ingestion for parser path
- diagnostics marshalling back to Lua

### Add exports for

- parse source fragments
- compile source fragments
- pretty-print typed IR
- dump backend IR

---

## `moonlift/src/cranelift_jit.rs`

### Current role

- core IR types and lowering
- compilation cache
- call packing/unpacking

### Problems to solve

- IR is currently too entangled with backend ownership
- module/direct-call compilation needs a cleaner orchestration layer

### Evolve into

- backend-focused lowering/codegen file
- consumes typed IR rather than owning all frontend concepts
- supports direct internal calls distinctly from indirect calls

### Specific refactors

1. extract or at least isolate IR definitions
2. add module declaration/definition phases
3. add symbol-table-based direct-call lowering
4. support better debugging dumps

---

## `moonlift/src/luajit.rs`

### Keep role narrow

This file should stay as:

- LuaJIT FFI binding layer
- helper wrappers for safe-ish Lua stack operations

### Avoid

Do not let parser/typechecker/compiler policy leak into this file.

---

## `moonlift/examples/*.lua`

### Evolve examples into test suites

Keep examples as executable docs, but make them cover both paths.

Recommended split:

- builder-path examples
- parser-path examples
- quote/rewrite examples
- C import examples
- direct-call / recursion examples
- diagnostics examples

### Add new examples

Recommended new files:

- `moonlift/examples/source_hello.lua`
- `moonlift/examples/source_quotes.lua`
- `moonlift/examples/source_structs.lua`
- `moonlift/examples/source_extern.lua`
- `moonlift/examples/source_recursion.lua`

---

## 6. Suggested PR sequence

This is the practical sequence I would use.

### PR 1
Add frontend infrastructure skeleton.

- `source.rs`
- `token.rs`
- `lexer.rs`
- `diag.rs`
- minimal parser for `expr` and `type`

### PR 2
Add AST and parser for items/statements.

- `ast.rs`
- `parser.rs`
- `ml.code`, `ml.module`, `ml.expr`, `ml.type` stubs

### PR 3
Add type system + layout engine.

- `typesys.rs`
- `layout.rs`
- `scope.rs`
- `typecheck.rs`

### PR 4
Add lowering from typed AST to existing backend IR.

- adapter layer into current `FunctionSpec` / `Expr` / `Stmt`
- source-based examples compile through existing backend

### PR 5
Add direct-call module compilation.

- module declare/define passes
- recursion support
- direct internal call lowering

### PR 6
Unify quote system.

- parsed quotes + builder quotes share operations
- `ml.quote.func`, `ml.quote.expr`, etc.

### PR 7
Add diagnostics and dump tooling.

### PR 8
Add `cimport` subset.

### PR 9
Optimization and specialization work.

This PR order minimizes thrash.

---

## 7. Testing strategy

### 7.1 Keep executable examples
Use the existing `examples/hello.lua` style as a golden integration test style.

### 7.2 Add Rust unit tests for frontend pieces
Recommended test files:

- `moonlift/src/test_lexer.rs`
- `moonlift/src/test_parser.rs`
- `moonlift/src/test_typecheck.rs`
- `moonlift/src/test_layout.rs`
- `moonlift/src/test_source_compile.rs`

### 7.3 Add parser diagnostics goldens
Have golden-output tests for:

- parse errors
- type errors
- duplicate declarations
- invalid `break`/`continue`
- invalid aggregate literals

### 7.4 Add direct-call tests
Must explicitly test:

- self recursion
- mutual recursion
- module-internal direct calls
- extern direct calls
- function-pointer indirect calls

### 7.5 Add determinism tests
Test stability of:

- tagged-union tags
- switch lowering
- specialization cache keys
- quote rewrite ordering

---

## 8. Risk register

### Risk 1 — duplicated semantic layers
If the parsed frontend and builder frontend diverge semantically, Moonlift becomes confusing.

**Mitigation:** one typed IR model, one layout model, one quote model.

### Risk 2 — premature syntax work
A fancy parser on top of unstable semantics creates long-term pain.

**Mitigation:** land typed IR, typechecker, and layout before large-scale syntax polish.

### Risk 3 — indirect calls remain the default
If direct-call compilation is delayed too long, Moonlift will keep feeling like a DSL instead of a language.

**Mitigation:** prioritize module compilation earlier than optimization passes.

### Risk 4 — diagnostics bolted on late
Source syntax without source diagnostics feels half-built.

**Mitigation:** add spans and `diag.rs` in Milestone 1.

### Risk 5 — quote system forks
Two quote systems would be fatal to Moonlift's identity.

**Mitigation:** unify parsed quotes and builder quotes as soon as parsed fragments exist.

---

## 9. Recommended immediate next steps

If work starts now, the highest-value next steps are:

1. add `source.rs`, `token.rs`, `lexer.rs`, `diag.rs`
2. implement `ml.type[[...]]` and `ml.expr[[...]]` parsing first
3. add `ast.rs` and statement/item parsing
4. build type/layout checking
5. implement module-level direct-call compilation
6. expose `ml.code[[...]]`

That sequence gets Moonlift from “nice builder DSL” to “real Moonlift language” as quickly as possible without throwing away current work.

---

## 10. Final summary

To bring Moonlift close to Terra-level feel while keeping Moonlift identity:

- keep the builder DSL
- add a real parser frontend
- add a real typed AST/typechecker/layout engine
- unify both paths through one typed IR
- compile modules with direct internal calls
- make diagnostics source-oriented
- preserve quotes and rewrites as a first-class differentiator

The core idea is not to replace current Moonlift.
It is to give current Moonlift a real language frontend and a compiler pipeline worthy of it.
