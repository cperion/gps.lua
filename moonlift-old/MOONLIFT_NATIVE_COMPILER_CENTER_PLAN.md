# Moonlift Native Compiler Center Plan

Status: active design document.

This document is the single combined design plan for Moonlift's long-term direction.
It supersedes and combines the earlier separate documents about:

- native `data` / replacing ASDL
- extensible language / parser extensions

The current design center is:

> Moonlift should not grow by bolting a second schema language onto a Terra-like core.
> It should grow into a language/runtime for compiler-shaped systems:
> native recursive data trees, native passes over them, native memoized execution boundaries, and eventually carefully designed language extensibility over one coherent semantic model.

This document is explicit about five things:

1. exactly how Moonlift `data` replaces the role currently played by ASDL
2. how the new approach integrates into the Moonlift system as a whole
3. how memoization works in a fresh Rust-native design
4. how extensible syntax should work without fragmenting semantics
5. why this may be where Moonlift's value over Terra truly lives

It also states one important constraint clearly:

> We do **not** need backward compatibility with the current ASDL or pvm APIs.
> We do **not** need to start by porting pvm as-is.
> We can design the new approach freshly in Rust, using the current system as architectural reference rather than compatibility target.

---

## 1. The thesis

Moonlift's long-term value over Terra is probably **not** just:

- better parser sugar
- more low-level helpers
- more host entry points
- more keywords

It is more likely this:

> Moonlift can unify low-level staged code generation, native recursive compiler/data trees, native pass authoring, native memoized compiler-style execution boundaries, and imported domain-specific language surfaces under one coherent model.

That is a stronger identity than “typed staged low-level language hosted by Lua.”

---

## 2. What ASDL is doing today

In this repo, ASDL is currently doing several jobs at once.

It is:

- a schema language for recursive typed trees
- a parser/lexer pair for that schema language
- a Lua runtime for interned immutable values
- a constructor/update API
- the identity substrate used by pvm caching and type dispatch

Those jobs need to be separated.

The correct replacement is **not** “Moonlift gets ASDL syntax.”
The correct replacement is:

- Moonlift gets native recursive `data` declarations
- Rust owns their semantics
- native memoized boundaries key on native data identity

---

## 3. Exact replacement: ASDL role -> Moonlift role

This section states the replacement precisely.

## 3.1 Schema language replacement

### Old role
ASDL is the language used to declare recursive compiler/data trees.

### New role
Moonlift `data` declarations replace that role.

#### Old

```text
module Lang {
    Expr = Int(i64 value) unique
         | Add(Lang.Expr lhs, Lang.Expr rhs) unique
         | Hole
}
```

#### New

```moonlift
@unique
data tagged union Expr
    Int
        value: i64
    end

    Add
        lhs: Expr
        rhs: Expr
    end

    Hole
end
```

Exact replacement statement:

> New recursive compiler/data trees are no longer authored in ASDL schema text.
> They are authored directly in Moonlift source.

---

## 3.2 Product types

### Old

```text
Point = (i32 x, i32 y) unique
```

### New

```moonlift
@unique
data struct Point
    x: i32
    y: i32
end
```

So:

- ASDL product type -> `data struct`

---

## 3.3 Sum types / tagged unions

### Old

```text
Expr = Int(i64 value)
     | Add(Expr lhs, Expr rhs)
     | Hole
```

### New

```moonlift
data tagged union Expr
    Int
        value: i64
    end

    Add
        lhs: Expr
        rhs: Expr
    end

    Hole
end
```

So:

- ASDL sum type -> `data tagged union`

Fieldless variants remain real fieldless variants.

---

## 3.4 Lists

### Old

```text
Widget* children
```

### New

```moonlift
children: []Widget
```

So:

- ASDL `T*` -> Moonlift `[]T`

Moonlift's own type syntax becomes the only surface.

---

## 3.5 Optional structure

ASDL often uses optionals.
Moonlift should **not** initially carry optionals into `data` as implicit nil-based variant logic.

Instead, optionals should be modeled explicitly:

```moonlift
data tagged union MaybeExpr
    None
    Some
        value: Expr
    end
end
```

So:

- ASDL optionals -> explicit Moonlift `data` unions

This keeps the model algebraic and context-free.

---

## 3.6 `unique`

### Old
`unique` is part of the ASDL declaration and means canonical structural identity.

### New
`unique` becomes an orthogonal attribute on `data` declarations:

```moonlift
@unique
data struct Point
    x: i32
    y: i32
end
```

```moonlift
@unique
data tagged union Expr
    ...
end
```

So:

- ASDL `unique` -> Moonlift `@unique`

Important design point:

- `data` means “recursive compiler/data declaration kind”
- `@unique` means “canonical identity policy”

They are separate and should remain separate.

---

## 3.7 Namespace role

### Old
ASDL has its own internal `module X { ... }` namespace system.

### New
Moonlift's ordinary source/module namespace replaces that.

So:

- ASDL's inner schema module language disappears for new code
- Moonlift modules/files/names become the only namespace system

---

## 3.8 Constructor surface

### Old
ASDL runtime construction looks like constructor calls or named-field builders.

### New
Construction should use native Moonlift value syntax:

```moonlift
let p = Point { x = 20, y = 22 }

let e = Expr.Add {
    lhs = Expr.Int { value = 40 },
    rhs = Expr.Int { value = 2 },
}

let h = Expr.Hole
```

So:

- ASDL constructor API -> native Moonlift value construction over `data`

---

## 3.9 Structural update

### Old
Structural update lives in a helper like:

```lua
pvm.with(node, { field = value })
```

### New
Structural update becomes a native runtime operation over Moonlift `data` values.

The exact final surface syntax does not need to be fixed yet, but the semantics do:

- update is structural, never mutation
- unchanged children preserve identity
- `@unique` values re-enter canonical construction

So:

- ASDL structural update -> native Moonlift data-runtime update

---

## 3.10 Identity substrate

### Old
ASDL runtime values are the identity substrate used by caching and dispatch.

### New
Moonlift `data` values must provide the same architectural role through a fresh Rust runtime:

- stable descriptor/class identity
- singleton fieldless variants
- `@unique` canonical identity
- list identity
- structural update support

So the full replacement claim is not just syntactic.
It is also operational.

---

## 4. One language, three layers

The stack should be:

```text
Lua      = host/meta/orchestration/staging
Moonlift = authored compiler/data/pass language
Rust     = parser, semantic analysis, data runtime, backend, memoized execution runtime
```

That means:

### Lua remains responsible for

- host metaprogramming
- module orchestration
- quote/rewrite control
- specialization control
- compile-time scripting
- integration glue

### Moonlift becomes responsible for

- recursive data-tree declarations
- pass/lowering code over those trees
- low-level implementation kernels
- future native compiler-like execution surfaces where appropriate

### Rust owns

- parsing
- AST
- semantic passes
- resolved data-world IR
- data runtime
- memoized boundary runtime
- backend lowering/codegen

This is the architectural split.

---

## 5. Native source surface

The long-term Moonlift source center should include at least:

- `type`
- `enum`
- `data struct`
- `data tagged union`
- `impl`
- `func`
- `match`

### Example

```moonlift
type Symbol = string

enum BinOp : u8
    Add = 0
    Mul = 1
end

@unique
data tagged union Expr
    Int
        value: i64
    end

    Var
        name: Symbol
    end

    Add
        lhs: Expr
        rhs: Expr
    end
end

@unique
data struct Func
    name: Symbol
    body: Expr
end

impl Expr
    func lower(self: Expr) -> Lir
        match self do
        case Int { value } then
            return Lir.Const { value = value }

        case Var { name } then
            return Lir.Local { name = name }

        case Add { lhs, rhs } then
            return Lir.AddI {
                lhs = lhs:lower(),
                rhs = rhs:lower(),
            }
        end
    end
end
```

This replaces the old pattern:

- schema in ASDL
- runtime in Lua ASDL objects
- passes written against that separate world

Now the tree world and pass world are both native Moonlift.

---

## 6. Context-free declaration rule

This is a non-negotiable rule.

A `data` declaration must be resolvable from source text and module-local declarations alone.

Allowed inside `data`:

- scalar types
- `string`
- `bytes`
- `enum`
- `type` aliases that resolve to allowed forms
- other `data` declarations
- `[]T`
- `[N]T`

Rejected inside `data`:

- pointers (`&T`)
- function types (`func(...) -> T`)
- splices in type position
- layout-only constructs
- host-dependent declarations

This is what makes `data` replace ASDL as a **context-free declaration system** rather than a loose builder layer.

---

## 7. `impl` and `match` are the pass surface

The pass layer should stay ordinary Moonlift code.

### `impl` is for

- lowerings
- analyses
- validation
- printers
- rewrites
- tree utilities

### `match` is for

- branching on `data tagged union` variants
- shallow destructuring of fields
- compiler-style variant dispatch

V1 `match` should stay small:

- fieldless variant cases
- shallow field destructuring
- shallow renaming
- optional wildcard/default

No nested pattern language is needed at first.

---

## 8. Fresh Rust-native data runtime

This is the operational core that replaces the runtime role of ASDL.

## 8.1 Core rule

A Moonlift `data` value is an **opaque handle into a Rust-owned world**.

It is not:

- a Lua table
- a GC tree object
- an ad hoc builder value

The Rust-owned world owns:

- descriptors
- stores
- interning tables
- singleton values
- list stores
- structural update
- memoization-relevant identity

---

## 8.2 Runtime IDs

The runtime should use explicit ids for families, descriptors, lists, and enums.

```rust
pub struct FamilyId(pub u32);
pub struct DescId(pub u32);
pub struct ListId(pub u32);
pub struct EnumId(pub u32);
```

---

## 8.3 Handles

KISS handle model first:

```rust
pub struct NodeHandle(pub u64);
pub struct ListHandle(pub u64);
```

And side metadata:

```rust
enum HandleMeta {
    Node { desc_id: DescId, slot: u32 },
    List { list_id: ListId, slot: u32 },
}
```

Do not start by bit-packing everything.
Opaque handle ids plus metadata are simpler and good enough for the first serious runtime.

---

## 8.4 Resolved types

After semantic resolution, `data` field types should lower to a compact Rust type universe such as:

```rust
enum ResolvedType {
    Scalar(ScalarKind),
    String,
    Bytes,
    Enum(EnumId),
    Node(FamilyId),
    Seq(ListId),
    Array(ListId, usize),
}
```

---

## 8.5 Stored field values

Node/list slots should store normalized runtime values:

```rust
enum FieldValue {
    Bool(bool),
    I64(i64),
    U64(u64),
    F64Bits(u64),
    StringAtom(Arc<str>),
    BytesAtom(Arc<[u8]>),
    EnumValue(u32),
    Node(NodeHandle),
    List(ListHandle),
}
```

This is the value universe used by interning, update, and memoization keys.

---

## 8.6 Descriptors

The runtime should have explicit family/descriptor/list descriptions.

```rust
struct FamilyDesc {
    id: FamilyId,
    name: String,
    descs: Vec<DescId>,
}

struct NodeDesc {
    id: DescId,
    family: FamilyId,
    name: String,
    fqname: String,
    fields: Vec<FieldDesc>,
    unique: bool,
    is_singleton: bool,
    variant_tag: Option<u32>,
}

struct ListDesc {
    id: ListId,
    elem: ResolvedType,
    fixed_len: Option<usize>,
}
```

This replaces the class/descriptor role currently provided indirectly by the ASDL runtime.

---

## 8.7 Stores

Per concrete descriptor and per list descriptor:

```rust
struct NodeSlot {
    fields: Box<[FieldValue]>,
}

struct ListSlot {
    elems: Box<[FieldValue]>,
}

struct NodeStore {
    desc: DescId,
    slots: Vec<NodeSlot>,
    interner: Option<HashMap<NodeKey, u32>>,
    singleton: Option<NodeHandle>,
}

struct ListStore {
    desc: ListId,
    slots: Vec<ListSlot>,
    interner: HashMap<ListKey, u32>,
}
```

Per-descriptor stores keep field layout fixed and make dispatch/getters simple.

---

## 8.8 The world object

```rust
struct DataWorld {
    families: Vec<FamilyDesc>,
    descs: Vec<NodeDesc>,
    lists: Vec<ListDesc>,

    node_stores: Vec<NodeStore>,
    list_stores: Vec<ListStore>,

    handle_meta: Vec<HandleMeta>,
    next_handle: u64,
}
```

This `DataWorld` is the fresh Rust-native replacement for the value-world role historically played by ASDL runtime objects.

---

## 9. Exact semantics of `@unique`

`@unique` means canonical structural identity.

That means construction works like this:

1. normalize fields to `FieldValue`
2. build a structural key
3. look in the interner for that descriptor
4. if found, return the existing handle
5. otherwise allocate a new slot and handle

Consequences:

- equal `@unique` structures get the same handle
- unchanged children keep the same handle
- memoized boundaries can key on handle identity

This is the exact replacement for ASDL `unique` as identity substrate.

---

## 10. Singleton variants

Fieldless variants must be canonical singleton values.

For:

```moonlift
data tagged union Expr
    Hole
end
```

there is one preallocated handle/value for `Expr.Hole`.

This preserves the same important architectural property current ASDL systems rely on:

- fieldless variants are identity-stable canonical values

---

## 11. Lists

All `data` lists should be native immutable list values in Rust.

KISS rule:

> canonicalize all `data` lists from the start.

That simplifies:

- structural equality
- `@unique`
- memoization keys
- sharing

So a `[]T` field stores a `ListHandle`, not a plain Lua table.

---

## 12. Structural update

Structural update is the native replacement for `pvm.with`.

Semantics:

1. read old fields from the handle's slot
2. overlay changed fields
3. re-enter ordinary constructor path

This guarantees:

- no mutation
- unchanged children preserve identity
- `@unique` values re-canonicalize automatically

This is the correct runtime story for persistent structural update.

---

## 13. Dispatch identity

To support later compiler/runtime boundaries, the data runtime must expose exact class/descriptor identity.

Minimum operations:

```rust
fn classof(world: &DataWorld, h: NodeHandle) -> DescId;
fn familyof(world: &DataWorld, h: NodeHandle) -> FamilyId;
```

This replaces the architectural role of ASDL metatable/class identity.

---

## 14. Memoization model

The rule is:

> We memoize explicit boundaries, not arbitrary helper functions.

Memoization depends on native `data` identity.
That means it depends on the `NodeHandle` / `ListHandle` world above.

## 14.1 Boundary key

A memoized boundary key should be:

```text
(phase_id, self_handle, extra_args...)
```

In Rust form:

```rust
pub struct PhaseId(pub u32);

enum KeyAtom {
    Bool(bool),
    I64(i64),
    U64(u64),
    F64Bits(u64),
    Enum(u32),
    Node(NodeHandle),
    List(ListHandle),
}

struct PhaseKey {
    phase: PhaseId,
    self_handle: NodeHandle,
    extras: SmallVec<[KeyAtom; 4]>,
}
```

This is the exact way Moonlift-native memoization replaces the identity-keyed role current pvm caches get from ASDL objects.

---

## 14.2 Two boundary kinds

There are two important memoization shapes.

### Scalar boundaries
One result per input.
Examples:

- lower to one value
- compute size
- compute type
- normalize one node

### Stream boundaries
Zero or more replayable outputs.
Examples:

- draw facts
- command streams
- flattened execution facts

The runtime should treat these as separate cache kinds.

---

## 14.3 Scalar cache

```rust
struct ScalarPhaseCache<V> {
    entries: HashMap<PhaseKey, ScalarEntry<V>>,
    stats: PhaseStats,
}

enum ScalarEntry<V> {
    Done(V),
    Busy,
}
```

Behavior:

- `Done` = hit
- absent = miss
- `Busy` = optional recursion/in-progress protection

This is enough for many compiler-style analyses and lowerings.

---

## 14.4 Stream cache

For replayable multi-output boundaries, the fresh Rust runtime should use pvm-like semantics conceptually, but not necessarily the same API.

Required states:

- **hit**: fully recorded before, replay from buffer
- **shared**: currently being recorded, new consumers share the recording
- **miss**: first consumer, start recording

Suggested structures:

```rust
struct StreamPhaseCache<T> {
    entries: HashMap<PhaseKey, Rc<RefCell<StreamEntry<T>>>>,
    stats: PhaseStats,
}

struct StreamEntry<T> {
    buffer: Vec<T>,
    status: StreamStatus<T>,
}

enum StreamStatus<T> {
    Recording { producer: Box<dyn StreamProducer<T>> },
    Done,
}

trait StreamProducer<T> {
    fn next(&mut self) -> Option<T>;
}

struct StreamCursor<T> {
    entry: Rc<RefCell<StreamEntry<T>>>,
    index: usize,
}
```

This is the fresh Rust-native memoization model for replayable boundaries.
It preserves the important semantics without requiring compatibility with current Lua triplet APIs.

---

## 14.5 Statistics

Memoized boundaries need explicit stats.

```rust
struct PhaseStats {
    calls: u64,
    hits: u64,
    shared: u64,
    misses: u64,
}
```

Reuse ratio remains an important diagnostic idea:

```text
reuse = (hits + shared) / calls
```

This preserves one of the most valuable architectural diagnostics from the current compiler-pattern work.

---

## 15. Exact replacement of current ASDL/pvm roles

## 15.1 Source ASDL -> Moonlift `data`

Current role:

- source ASDL declares authored/compiler trees

Replacement:

- `data struct`
- `data tagged union`

## 15.2 Event ASDL -> Moonlift `data`

Current role:

- event ASDL declares event languages

Replacement:

- event trees are also ordinary `data tagged union`

## 15.3 ASDL `unique` -> Moonlift `@unique`

Current role:

- canonical structural identity

Replacement:

- Rust-native interning over `@unique data`

## 15.4 ASDL constructor/runtime world -> Rust `DataWorld`

Current role:

- runtime values, descriptors, constructors, singleton identity, structural update

Replacement:

- Rust-native `DataWorld`
- Rust-native descriptors/stores/handles
- Rust-native singleton/list/update/interner logic

## 15.5 pvm identity-keyed cache substrate -> native boundary caches on handles

Current role:

- ASDL object identity keys pvm caches

Replacement:

- `NodeHandle` / `ListHandle` identity keys native boundary caches

## 15.6 `pvm.with` -> native structural update

Current role:

- persistent update helper over ASDL values

Replacement:

- native structural update in the Rust data runtime

## 15.7 pvm phase semantics -> fresh Rust-native memoized boundary runtime

Current role:

- miss/shared/hit recording and replay

Replacement:

- fresh Rust-native scalar/stream boundary caches
- same architectural idea, fresh implementation

Important:

- this is **not** a requirement to keep the old pvm API names
- it is a requirement to preserve the important memoization semantics where they remain valuable

---

## 16. Moonlift as an extensible language

Moonlift should eventually support **language extensibility**, but the extensibility must obey one rule:

> Extensions may add surface syntax, but they must lower into one core Moonlift semantic model.

The value is **not**:

- arbitrary grammar mutation forever
- dozens of unrelated mini-languages
- syntax tricks detached from the runtime and type system

The value is:

- specialized surface forms for compiler/data/runtime domains
- without fragmenting semantics

This is especially important for Moonlift because its likely long-term surface may need to express things like:

- recursive data declarations
- pass declarations
- memoized boundaries
- machine descriptions
- grammar descriptions
- query/transformation DSLs
- structured execution/layout DSLs
- future compiler-pattern forms that are not obvious yet

---

## 17. Core language vs extension layer

## 17.1 Core language
The core language should stay relatively small and stable.

Likely core candidates:

- `func`
- `impl`
- `type`
- `enum`
- `data struct`
- `data tagged union`
- `match`
- low-level expression/statement/type machinery

This is the semantic backbone.

## 17.2 Extension layer
The extension layer is where domain-specific surface forms can live.

Examples of plausible future extensions:

- `phase`
- `machine`
- `grammar`
- `pipeline`
- `query`
- `layout`
- other compiler-pattern DSLs

These should not have to be globally reserved forever.

---

## 18. Soft keywords, not hard keyword sprawl

Moonlift should distinguish between:

### Hard keywords
Always reserved by the core language.
These should stay few.

Examples:

- `func`
- `impl`
- `data`
- `match`
- `enum`
- `type`

### Soft keywords
Only act as introducers when an active syntax extension claims them in a valid parse position.
Otherwise they remain ordinary identifiers.

Examples:

- `phase`
- `machine`
- `grammar`
- `pipeline`

This gives extensibility without keyword pollution.

---

## 19. Explicit syntax imports

Extensions should not be globally active by default.
They should be imported explicitly.

Possible surface forms:

```moonlift
use syntax pvm
use syntax machine
use syntax grammar
```

The exact spelling can be decided later, but the principle should be fixed:

> syntax extensions are explicit, local, and opt-in

This keeps code understandable and tooling predictable.

---

## 20. Structured parser extension points

The parser should expose structured extension points, not unrestricted mutation of every parse function.

A good KISS set of extension contexts is:

- top-level item position
- statement position
- expression position
- pattern position
- type position

That is enough to build serious extensions.

Examples:

- `phase` might be a top-level item extension
- `machine` might be a top-level item extension
- `query` might be an expression extension
- custom pattern forms might be pattern-position extensions
- grammar combinator type forms might be type-position extensions

---

## 21. Suggested parser extension interface

The exact Rust API can evolve, but conceptually Moonlift should support something like:

```rust
trait SyntaxExtension {
    fn item_introducers(&self) -> &[&str];
    fn stmt_introducers(&self) -> &[&str];
    fn expr_introducers(&self) -> &[&str];
    fn pattern_introducers(&self) -> &[&str];
    fn type_introducers(&self) -> &[&str];

    fn parse_item(&self, p: &mut Parser) -> Result<Option<ExtItemAst>, ParseError>;
    fn parse_stmt(&self, p: &mut Parser) -> Result<Option<ExtStmtAst>, ParseError>;
    fn parse_expr(&self, p: &mut Parser) -> Result<Option<ExtExprAst>, ParseError>;
    fn parse_pattern(&self, p: &mut Parser) -> Result<Option<ExtPatternAst>, ParseError>;
    fn parse_type(&self, p: &mut Parser) -> Result<Option<ExtTypeAst>, ParseError>;
}
```

The important idea is:

- extensions claim introducers
- parser asks active extensions in well-defined contexts
- result is a structured extension AST, not raw text substitution

---

## 22. Lowering rule for extensions

Every extension form must lower to one of:

- core Moonlift AST
- core typed IR
- a standard intermediate extension AST that is later lowered into the core model

The key rule is:

> extensions may change syntax, but not the semantic foundation

Examples:

### `phase`
Could introduce pleasant syntax for memoized boundaries, but must lower to the same core memoized-boundary representation.

### `machine`
Could introduce a compact machine DSL, but must lower to core declarations, descriptors, functions, and runtime concepts.

Extensions are surface architecture, not disconnected semantic worlds.

---

## 23. Why extensibility matters specifically here

Moonlift's extensibility only becomes deeply valuable if the core language already has the right center:

- native recursive `data`
- `@unique`
- `impl`
- `match`
- Rust-native `DataWorld`
- native memoized boundaries

Then syntax extensions become a way to build domain-specific surface forms **on top of that center**.

Without that center, extensibility is clever syntax.
With that center, extensibility becomes a serious language strategy.

---

## 24. What we are deliberately **not** doing

### 24.1 No backward compatibility layer first
We do not need to preserve the old schema/runtime entry points as the main path.

### 24.2 No ASDL parser compatibility target
The Rust Moonlift frontend is the new path.

### 24.3 No Lua-owned data semantics
Lua remains host/meta/orchestration, not the owner of the data runtime.

### 24.4 No direct pvm API port as phase 1
We extract the right architectural ideas and build a fresh Rust runtime.

### 24.5 No keyword explosion
The first job is to own the semantics, not to turn every runtime idea into syntax.

### 24.6 No arbitrary parser mutation everywhere
The parser must retain structure.

### 24.7 No semantically disconnected mini-languages
Everything must lower to the same semantic center.

---

## 25. Recommended implementation order

## Phase A — native source declarations and pass surface

Deliverables:

- `data struct`
- `data tagged union`
- `@unique`
- `match`
- `impl` / `func` over `data`

Rust work:

- parser updates
- AST updates
- semantic pass for context-free `data` declarations
- `match` typing over `data tagged union`

Result:

- ASDL is replaced as the declaration language for new compiler/data trees

---

## Phase B — Rust-native `DataWorld`

Deliverables:

- descriptors
- stores
- handles
- singleton variants
- canonical lists
- `@unique` interning
- structural update

Result:

- ASDL is replaced as the runtime identity/value substrate

---

## Phase C — native memoized boundaries

Deliverables:

- scalar boundary caches
- stream boundary caches
- keying on `(phase_id, self_handle, extras...)`
- reuse diagnostics

Result:

- the important memoization role historically played by pvm is now native Rust runtime semantics over native Moonlift data

---

## Phase D — extension-friendly parser architecture

Deliverables:

- soft keyword awareness
- explicit syntax import model
- structured extension contexts
- extension AST + lowering discipline

Result:

- Moonlift becomes ready for imported syntax layers without fragmenting semantics

---

## Phase E — a few strategic syntax extensions

Only after the core is real:

- add a small number of high-value extensions such as `phase`, `machine`, or `grammar`
- keep them lowering-oriented
- do not allow them to invent disconnected runtime universes

---

## 26. Final recommendation

The exact plan is:

1. replace ASDL as the declaration language with Moonlift `data`
2. preserve `unique` as `@unique`
3. implement the replacement freshly in Rust, not as a compatibility layer
4. make Rust own the `data` runtime through handles, descriptors, stores, interning, and structural update
5. memoize explicit execution boundaries by native handle identity
6. design Moonlift as an extensible language with soft-keyword imported syntax extensions that always lower into the same core semantic model

In one sentence:

> Moonlift replaces ASDL by making recursive compiler/data trees a native part of Moonlift source, replaces ASDL's runtime role by a fresh Rust-native `DataWorld`, uses canonical handles as the substrate for native memoized compiler-style boundaries, and eventually supports imported syntax extensions that elaborate domain-specific surfaces over that same core semantic center.
