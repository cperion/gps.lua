# Moonlift Quoting / Metaprogramming / Open-Code Design

Status: current design document for the rebooted `moonlift/` architecture.

The `MoonliftMeta` layer described here is **not** implemented yet.
What is implemented today is the closed compiler stack that this document builds on.

This document replaces the earlier lighter fragment proposal with a design that is grounded in the **current actual ASDL** in:

- `moonlift/lua/moonlift/asdl.lua`

The key update is that Moonlift already has a real closed compiler stack:

- `MoonliftSurface`
- `MoonliftElab`
- `MoonliftSem`
- `MoonliftBack`

After rereading that stack carefully, the correct conclusion is:

> Moonlift quoting must not be modeled as open source strings and it should not be modeled as open `Sem`.
>
> It should be modeled as a **full open elaborated layer** that mirrors `MoonliftElab` and closes into ordinary `Elab` before the existing `Elab -> Sem -> Back` path.

This document gives the **complete design**, not a minimal subset.
Implementation may still be staged later, but the semantic model described here is the intended final one.

---

# Executive summary

## The current compiler already tells us the right quote layer

The current ASDL stack strongly implies:

- `Surface` is too early for hygienic reusable code
- `Sem` is too late and too machine-facing for open-code assembly
- `Elab` is the right center of gravity

So Moonlift should introduce:

- **`MoonliftMeta`** = a full **open elaborated** layer

This layer should mirror `MoonliftElab`, not replace it.

## The core split still matters

The deepest semantic split remains:

- **Fragment** = inline, assemblable, open code
- **Function** = callable, sealable, graph-visible code

But the full design also needs:

- **Const templates**
- **Module templates / assembly groups**

because the current real compiler already has:

- funcs
- extern funcs
- consts
- modules

## The interface is larger than params and slots

A complete quote system needs three interface classes:

- **runtime params**
- **compile-time slots**
- **explicit imports**

The current ASDL makes this unavoidable because `Elab` already depends on:

- value bindings
- type bindings
- layout information
- globals
- externs

## The open layer must mirror `Elab`

The open layer must be able to represent open versions of the current elaborated categories:

- types
- domains
- exprs
- stmts
- loops
- consts
- funcs
- items
- modules

Not because we want a second compiler universe, but because complete structural metaprogramming over the current compiler requires an open version of the elaborated language.

## The closure boundary is `Meta -> Elab`

The intended architecture is:

### Closed compiler path
- `Surface -> Elab -> Sem -> Back`

### Open metaprogramming path
- builder/source/hosted-parser forms -> `Meta`
- assemble / fill / normalize in `Meta`
- **close / seal into ordinary `Elab`**
- then continue through the normal compiler path

This is the key architectural boundary.

## Public/common forms vs full internal support

The common user-facing forms should still emphasize:

- expr fragments
- region fragments
- functions
- modules

But the **complete internal model** must also support open:

- types
- domains
- consts
- item lists
- module packaging

## The final slogan

> Moonlift quotes should be a **full open elaborated layer** with explicit params, slots, and imports.
>
> Fragments assemble inline in `Meta`; functions and modules seal into ordinary current `Elab`; `Sem` remains the downstream semantic/machine layer.

---

# 1. Why the earlier lighter proposal is no longer enough

The earlier proposal got several high-level ideas right:

- Fragment vs Function is a good deep split
- `expr` and `region` are the right common fragment shapes
- hygiene should be structural
- builder and source forms must converge
- `region` is important now, not later

But after rereading the actual current ASDL, several parts were too small.

## 1.1 The old proposal was too late in the pipeline

It leaned too much toward:

- a small wrapper layer
- openness surviving near or into `Sem`

That no longer looks right.

The current `MoonliftSem` already commits to details like:

- `SemCallTarget`
- `SemIndexBase`
- `SemFieldRef`
- `SemExprIndexAddr`
- `SemExprLoad`
- `SemIntrinsic`
- explicit loop and assertion structure

That is excellent for semantic lowering and backend work.
But it is already **downstream of hygienic open-code assembly**.

## 1.2 The old proposal under-modeled environment dependencies

The earlier proposal emphasized:

- params
- slots

But the real compiler already depends explicitly on:

- value environments
- type environments
- layout environments

through `ElabEnv` and `ElabTypeLayout`.

That means a real quote system must model explicit:

- imports of values
- imports of types
- imports of layouts
- imports of globals / externs / helper functions

## 1.3 The old proposal under-modeled top-level assembly

The actual current compiler already has:

- `SurfConst` / `ElabConst` / `SemConst`
- `SurfExternFunc` / `ElabExternFunc` / `SemExternFunc`
- `SurfModule` / `ElabModule` / `SemModule`

So the complete quote design cannot stop at:

- expr fragments
- region fragments
- function values

It must also describe:

- const templates
- extern declarations
- module assembly / packaging

---

# 2. The current closed compiler path

The actual current compiler stack is:

## 2.1 `MoonliftSurface`
Author-facing, string-name-centric, syntax-shaped nodes.

Important characteristics:

- still string-name based
- still unresolved
- still source-ish
- loops/domains already explicit

## 2.2 `MoonliftElab`
Resolved, typed, hygienic compiler IR.

Important characteristics:

- value bindings are explicit:
  - local value
  - local cell
  - arg
  - global
  - extern
- types are explicit
- field typing uses layout information
- loops already have explicit typed bindings and `next`

This is already the layer where hygienic meaning exists.

## 2.3 `MoonliftSem`
Machine-facing semantic layer.

Important characteristics:

- direct / extern / indirect call targets
- explicit load/address/index machinery
- explicit intrinsic family
- explicit bounded-domain forms
- still structured loops and statements

This is downstream of quote assembly.

## 2.4 `MoonliftBack`
Explicit backend command stream.

This is the execution-facing backend layer.

## 2.5 Conclusion

The quote system should not try to be:

- open `Surface`
- open `Sem`

It should be:

- **open `Elab`**

---

# 3. The complete open-code architecture

The complete architecture should therefore be:

## 3.1 Closed path

```text
Surface -> Elab -> Sem -> Back
```

## 3.2 Open path

```text
builder/source/parser-hosted quote forms
    -> Meta   (open elaborated layer)
    -> assembly / substitution / normalization / closure
    -> Elab   (ordinary closed elaborated IR)
    -> Sem
    -> Back
```

## 3.3 Why this is the right boundary

This gives Moonlift all of the important properties at once:

- hygienic open code
- structural cacheability through ASDL identity
- reuse of the existing current lowerings
- no need to invent a second downstream semantic/backend universe
- a clean separation between:
  - assembly-time structure
  - ordinary compiled program semantics

---

# 4. Core semantic categories

The complete design needs the following categories.

## 4.1 Types as first-class values

These already matter pervasively in the current compiler.

Examples:

- `i32`
- `f32`
- `ptr(T)`
- `array(N, T)`
- `slice(T)`
- `func({T1, T2}, R)`
- named types

In the quote system, types must be first-class because:

- type slots exist
- type imports exist
- fragment and function interfaces are typed
- consts and modules may depend on imported named types/layouts

## 4.2 Domains as first-class values

The current ASDL already treats domains explicitly:

- `range(stop)`
- `range(start, stop)`
- `zip_eq(...)`
- bounded domain values

So domains should be considered first-class values in the complete design.

This matters because:

- loops are not just sugar anymore
- loop assembly often wants domain-level reuse
- domain holes/slots are meaningful

## 4.3 Fragments

A fragment is:

- open
- elaborated
- hygienic
- inline by nature
- assemblable into larger code
- not itself the compile unit

### Common/public fragment shapes
The most important user-facing shapes remain:

- **expression fragment**
- **region fragment**

### Internal/full fragment shape lattice
The complete internal open-code layer also needs open forms for:

- types
- domains
- item lists / module splices

But the common user-facing center of gravity should still be expr + region.

## 4.4 Functions

A function is:

- callable
- open or closed
- elaborated
- hygienic
- graph-visible
- sealable
- the natural compile-unit candidate

A function is not just “a fragment with share policy”.
That is too weak a distinction.

Functions are structurally different because they:

- participate in direct-call graphs
- belong in modules / namespaces
- become ordinary current function/module lowering inputs

## 4.5 Consts

Consts are part of the current real compiler and therefore part of the complete quote system.

A const template is:

- open or closed
- elaborated
- hygienic
- module-packaged
- not a runtime parametric function

## 4.6 Modules / assembly groups

Modules are required in the complete design because the current compiler already has them.

A module template is the place where Moonlift assembles:

- funcs
- externs
- consts
- item splices
- mutually recursive groups
- exported entrypoints / helper namespaces

Modules are not the deepest peer of Fragment and Function, but they are a required packaging layer in the complete model.

---

# 5. Interface model: params, imports, and slots

A complete quote interface needs three different kinds of things.

## 5.1 Runtime params

These are runtime values.

Examples:

- `x: i32`
- `out: &f32`
- `n: index`

Params are what the fragment/function actually receives at runtime.

## 5.2 Compile-time slots

These are structural holes filled during assembly.

They are not imports.
They are not runtime params.
They are compile-time structural placeholders.

Important slot kinds in the complete design:

- type slot
- expr slot
- domain slot
- region slot
- function slot
- const slot
- items slot
- module slot

## 5.3 Explicit imports

Imports are fixed nonlocal dependencies.

They are the complete-design answer to the current compiler’s explicit dependence on:

- values
- types
- layouts
- globals
- externs

Examples:

- imported value
- imported helper function
- imported global function/const
- imported extern symbol binding
- imported type alias/name
- imported layout information for named types

## 5.4 Why slots and imports are not the same

A slot means:

- “this is a hole to be filled structurally later”

An import means:

- “this quote depends on this external thing as a stable part of its meaning”

That distinction is important.

### Use a slot when:
- you want late assembly-time substitution
- you want the quote to remain abstract over some code/type/domain/module part

### Use an import when:
- you want a fixed external dependency
- you want a stable referenced helper/global/extern/type/layout

---

# 6. Hygiene and structural identity

## 6.1 The default rule

A source-origin quote may refer only to names that are:

- declared params
- declared imports
- declared slots where that context allows slot references
- internally introduced locals
- module-local sibling items made available by module assembly

Anything else is an error by default.

## 6.2 Builder code must obey the same architecture

Builder forms must not smuggle meaningful dependencies through invisible Lua captures.

If something materially affects the assembled code, it must appear structurally as one of:

- a param
- an import
- a slot
- or an explicit referenced function/module object

Otherwise the dependency is invisible to ASDL identity and PVM caching.

## 6.3 Deterministic local binder identity

Current `Elab` binders already use string ids.
So the quote system must preserve the invariant:

> internal binder ids are deterministic from structure, not random gensyms.

Examples of the intended rule:

- a local binder id is derived from:
  - owning template identity
  - structural path
  - binder role
- a fragment use expansion rebases local ids deterministically from:
  - fragment identity
  - use-site path

The exact printed spelling is unimportant.
The invariant is essential:

- no random gensyms
- no accidental capture
- stable structural identities for caching

## 6.4 Structural substitution only

All slot filling and fragment assembly must be structural:

- never textual
- never token replacement
- never string interpolation masquerading as semantics

This is what makes hygiene and structural caching compatible.

---

# 7. Why the complete open layer must mirror `Elab`

This is the central design point.

## 7.1 Why `Surface` is the wrong center

`Surface` is still:

- string-name centric
- unresolved
- too syntax-shaped
- too early for stable hygienic open code

Open code should not stay at raw source-tree level.

## 7.2 Why `Sem` is the wrong center

`Sem` already encodes downstream semantic decisions such as:

- call target classification
- field/index address structure
- intrinsic families
- load/address semantics

Open-code assembly should happen **before** that commitment.

## 7.3 Why `Elab` is the right center

`Elab` already makes explicit exactly the kinds of things quotes need:

- bindings
- mutability distinction (`LocalValue` vs `LocalCell`)
- args/globals/externs
- typed exprs and stmts
- typed loops and carries
- layout-aware field typing

So the complete quote layer should be:

- a **full open mirror of `Elab`**

not a partial wrapper around source strings and not a second downstream semantic IR.

---

# 8. Proposed `MoonliftMeta` ASDL

The following is the intended **complete semantic shape** of the open-code layer.

It is not meant to be a second independent compiler universe.
It is meant to be an **open elaborated mirror** of the current closed elaborated language.

```asdl
module MoonliftMeta {
    MetaExport = MetaLocal
               | MetaExported

    MetaNameHint = MetaNoNameHint
                 | MetaNameHint(string text) unique

    -- Types: mirror ElabType, plus open type slots.
    MetaType = MetaTVoid
             | MetaTBool
             | MetaTI8 | MetaTI16 | MetaTI32 | MetaTI64
             | MetaTU8 | MetaTU16 | MetaTU32 | MetaTU64
             | MetaTF32 | MetaTF64
             | MetaTIndex
             | MetaTPtr(MoonliftMeta.MetaType elem) unique
             | MetaTArray(MoonliftMeta.MetaExpr count, MoonliftMeta.MetaType elem) unique
             | MetaTSlice(MoonliftMeta.MetaType elem) unique
             | MetaTFunc(MoonliftMeta.MetaType* params, MoonliftMeta.MetaType result) unique
             | MetaTNamed(string module_name, string type_name) unique
             | MetaTSlot(MoonliftMeta.MetaTypeSlot slot) unique

    -- Runtime params.
    MetaParam = (string key, string pretty_name, MoonliftMeta.MetaType ty) unique

    -- Fixed nonlocal imports.
    MetaValueImport = MetaImportValue(string key, string pretty_name, MoonliftMeta.MetaType ty) unique
                    | MetaImportGlobal(string key, string pretty_name, string module_name, string item_name, MoonliftMeta.MetaType ty) unique
                    | MetaImportExtern(string key, string pretty_name, string symbol, MoonliftMeta.MetaType ty) unique

    MetaTypeImport = (string key, string local_name, MoonliftMeta.MetaType ty) unique
    MetaFieldType = (string field_name, MoonliftMeta.MetaType ty) unique
    MetaTypeLayout = MetaLayoutNamed(string module_name, string type_name, MoonliftMeta.MetaFieldType* fields) unique

    -- Compile-time slots.
    MetaTypeSlot   = (string key, string pretty_name) unique
    MetaExprSlot   = (string key, string pretty_name, MoonliftMeta.MetaType ty) unique
    MetaDomainSlot = (string key, string pretty_name) unique
    MetaRegionSlot = (string key, string pretty_name) unique
    MetaFuncSlot   = (string key, string pretty_name, MoonliftMeta.MetaType fn_ty) unique
    MetaConstSlot  = (string key, string pretty_name, MoonliftMeta.MetaType ty) unique
    MetaItemsSlot  = (string key, string pretty_name) unique
    MetaModuleSlot = (string key, string pretty_name) unique

    MetaSlot = MetaSlotType(MoonliftMeta.MetaTypeSlot slot) unique
             | MetaSlotExpr(MoonliftMeta.MetaExprSlot slot) unique
             | MetaSlotDomain(MoonliftMeta.MetaDomainSlot slot) unique
             | MetaSlotRegion(MoonliftMeta.MetaRegionSlot slot) unique
             | MetaSlotFunc(MoonliftMeta.MetaFuncSlot slot) unique
             | MetaSlotConst(MoonliftMeta.MetaConstSlot slot) unique
             | MetaSlotItems(MoonliftMeta.MetaItemsSlot slot) unique
             | MetaSlotModule(MoonliftMeta.MetaModuleSlot slot) unique

    -- Public interface of an open quote/template.
    MetaInterface = (
        MoonliftMeta.MetaParam* params,
        MoonliftMeta.MetaValueImport* value_imports,
        MoonliftMeta.MetaTypeImport* type_imports,
        MoonliftMeta.MetaTypeLayout* layouts,
        MoonliftMeta.MetaSlot* slots
    ) unique

    -- Symbols for module-local graph-visible items.
    MetaFuncSym = (string key, string pretty_name, MoonliftMeta.MetaType fn_ty) unique
    MetaExternSym = (string key, string pretty_name, string symbol, MoonliftMeta.MetaType fn_ty) unique
    MetaConstSym = (string key, string pretty_name, MoonliftMeta.MetaType ty) unique

    -- Resolved open bindings.
    MetaBinding = MetaBindParam(MoonliftMeta.MetaParam param) unique
                | MetaBindLocalValue(string id, string name, MoonliftMeta.MetaType ty) unique
                | MetaBindLocalCell(string id, string name, MoonliftMeta.MetaType ty) unique
                | MetaBindImport(MoonliftMeta.MetaValueImport import) unique
                | MetaBindFunc(MoonliftMeta.MetaFuncSym func) unique
                | MetaBindExternFunc(MoonliftMeta.MetaExternSym func) unique
                | MetaBindConst(MoonliftMeta.MetaConstSym c) unique
                | MetaBindFuncSlot(MoonliftMeta.MetaFuncSlot slot) unique
                | MetaBindConstSlot(MoonliftMeta.MetaConstSlot slot) unique

    MetaFieldInit = (string name, MoonliftMeta.MetaExpr value) unique
    MetaSwitchStmtArm = (MoonliftMeta.MetaExpr key, MoonliftMeta.MetaStmt* body) unique
    MetaSwitchExprArm = (MoonliftMeta.MetaExpr key, MoonliftMeta.MetaStmt* body, MoonliftMeta.MetaExpr result) unique
    MetaLoopBinding = (string id, string name, MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr init) unique
    MetaLoopNext = (MoonliftMeta.MetaBinding binding, MoonliftMeta.MetaExpr value) unique

    -- Open domains: mirror ElabDomain, plus slots.
    MetaDomain = MetaDomainRange(MoonliftMeta.MetaExpr stop) unique
               | MetaDomainRange2(MoonliftMeta.MetaExpr start, MoonliftMeta.MetaExpr stop) unique
               | MetaDomainZipEq(MoonliftMeta.MetaExpr* values) unique
               | MetaDomainValue(MoonliftMeta.MetaExpr value) unique
               | MetaDomainSlotValue(MoonliftMeta.MetaDomainSlot slot) unique

    -- Open elaborated expressions: mirror ElabExpr, plus slots and fragment-use nodes.
    MetaExpr = MetaInt(string raw, MoonliftMeta.MetaType ty) unique
             | MetaFloat(string raw, MoonliftMeta.MetaType ty) unique
             | MetaBool(boolean value, MoonliftMeta.MetaType ty) unique
             | MetaNil(MoonliftMeta.MetaType ty) unique
             | MetaBindingExpr(MoonliftMeta.MetaBinding binding) unique
             | MetaExprNeg(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprNot(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprBNot(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprRef(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprDeref(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprAdd(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprSub(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprMul(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprDiv(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprRem(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprEq(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprNe(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprLt(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprLe(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprGt(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprGe(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprAnd(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprOr(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprBitAnd(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprBitOr(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprBitXor(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprShl(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprLShr(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprAShr(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr lhs, MoonliftMeta.MetaExpr rhs) unique
             | MetaExprCastTo(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprTruncTo(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprZExtTo(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprSExtTo(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprBitcastTo(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaExprSatCastTo(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr value) unique
             | MetaCall(MoonliftMeta.MetaExpr callee, MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr* args) unique
             | MetaField(MoonliftMeta.MetaExpr base, string name, MoonliftMeta.MetaType ty) unique
             | MetaIndex(MoonliftMeta.MetaExpr base, MoonliftMeta.MetaExpr index, MoonliftMeta.MetaType ty) unique
             | MetaAgg(MoonliftMeta.MetaType ty, MoonliftMeta.MetaFieldInit* fields) unique
             | MetaArrayLit(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr* elems) unique
             | MetaIfExpr(MoonliftMeta.MetaExpr cond, MoonliftMeta.MetaExpr then_expr, MoonliftMeta.MetaExpr else_expr, MoonliftMeta.MetaType ty) unique
             | MetaSwitchExpr(MoonliftMeta.MetaExpr value, MoonliftMeta.MetaSwitchExprArm* arms, MoonliftMeta.MetaExpr default_expr, MoonliftMeta.MetaType ty) unique
             | MetaLoopExprNode(MoonliftMeta.MetaLoop loop, MoonliftMeta.MetaType ty) unique
             | MetaBlockExpr(MoonliftMeta.MetaStmt* stmts, MoonliftMeta.MetaExpr result, MoonliftMeta.MetaType ty) unique
             | MetaExprSlotValue(MoonliftMeta.MetaExprSlot slot, MoonliftMeta.MetaType ty) unique
             | MetaExprUseExprFrag(MoonliftMeta.MetaExprFrag frag, MoonliftMeta.MetaExpr* args, MoonliftMeta.MetaSlotBinding* fills, MoonliftMeta.MetaType ty) unique

    -- Open elaborated loops: mirror ElabLoop.
    MetaLoop = MetaLoopWhileStmt(MoonliftMeta.MetaLoopBinding* vars, MoonliftMeta.MetaExpr cond, MoonliftMeta.MetaStmt* body, MoonliftMeta.MetaLoopNext* next) unique
             | MetaLoopOverStmt(MoonliftMeta.MetaBinding index_binding, MoonliftMeta.MetaDomain domain, MoonliftMeta.MetaLoopBinding* carries, MoonliftMeta.MetaStmt* body, MoonliftMeta.MetaLoopNext* next) unique
             | MetaLoopWhileExpr(MoonliftMeta.MetaLoopBinding* vars, MoonliftMeta.MetaExpr cond, MoonliftMeta.MetaStmt* body, MoonliftMeta.MetaLoopNext* next, MoonliftMeta.MetaExpr result) unique
             | MetaLoopOverExpr(MoonliftMeta.MetaBinding index_binding, MoonliftMeta.MetaDomain domain, MoonliftMeta.MetaLoopBinding* carries, MoonliftMeta.MetaStmt* body, MoonliftMeta.MetaLoopNext* next, MoonliftMeta.MetaExpr result) unique

    -- Open elaborated statements: mirror ElabStmt, plus region-slot/use nodes.
    MetaStmt = MetaLet(string id, string name, MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr init) unique
             | MetaVar(string id, string name, MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr init) unique
             | MetaSet(MoonliftMeta.MetaBinding binding, MoonliftMeta.MetaExpr value) unique
             | MetaStore(MoonliftMeta.MetaType ty, MoonliftMeta.MetaExpr addr, MoonliftMeta.MetaExpr value) unique
             | MetaExprStmt(MoonliftMeta.MetaExpr expr) unique
             | MetaIf(MoonliftMeta.MetaExpr cond, MoonliftMeta.MetaStmt* then_body, MoonliftMeta.MetaStmt* else_body) unique
             | MetaSwitch(MoonliftMeta.MetaExpr value, MoonliftMeta.MetaSwitchStmtArm* arms, MoonliftMeta.MetaStmt* default_body) unique
             | MetaReturnVoid
             | MetaReturnValue(MoonliftMeta.MetaExpr value) unique
             | MetaBreak
             | MetaContinue
             | MetaLoopStmtNode(MoonliftMeta.MetaLoop loop) unique
             | MetaStmtUseRegionSlot(MoonliftMeta.MetaRegionSlot slot) unique
             | MetaStmtUseRegionFrag(MoonliftMeta.MetaRegionFrag frag, MoonliftMeta.MetaExpr* args, MoonliftMeta.MetaSlotBinding* fills) unique

    -- Primary public fragment shapes.
    MetaExprFrag = (MoonliftMeta.MetaInterface interface, MoonliftMeta.MetaExpr body, MoonliftMeta.MetaType result) unique
    MetaRegionFrag = (MoonliftMeta.MetaInterface interface, MoonliftMeta.MetaStmt* body) unique

    -- Top-level callable / packageable forms.
    MetaFunction = (
        MoonliftMeta.MetaFuncSym sym,
        MoonliftMeta.MetaExport linkage,
        MoonliftMeta.MetaInterface interface,
        MoonliftMeta.MetaType result,
        MoonliftMeta.MetaStmt* body
    ) unique

    MetaExternDecl = (MoonliftMeta.MetaExternSym sym) unique
    MetaConstDecl = (MoonliftMeta.MetaConstSym sym, MoonliftMeta.MetaInterface interface, MoonliftMeta.MetaExpr value) unique

    MetaItem = MetaItemFunc(MoonliftMeta.MetaFunction func) unique
             | MetaItemExtern(MoonliftMeta.MetaExternDecl func) unique
             | MetaItemConst(MoonliftMeta.MetaConstDecl c) unique
             | MetaItemUseItemsSlot(MoonliftMeta.MetaItemsSlot slot) unique
             | MetaItemUseModule(MoonliftMeta.MetaModule module, MoonliftMeta.MetaSlotBinding* fills) unique

    MetaModule = (MoonliftMeta.MetaInterface interface, MoonliftMeta.MetaItem* items) unique

    -- Compile-time slot filling values.
    MetaSlotValue = MetaSlotValueType(MoonliftMeta.MetaType ty) unique
                  | MetaSlotValueExpr(MoonliftMeta.MetaExpr expr) unique
                  | MetaSlotValueDomain(MoonliftMeta.MetaDomain domain) unique
                  | MetaSlotValueRegion(MoonliftMeta.MetaStmt* body) unique
                  | MetaSlotValueFunction(MoonliftMeta.MetaFunction func) unique
                  | MetaSlotValueConst(MoonliftMeta.MetaConstDecl c) unique
                  | MetaSlotValueItems(MoonliftMeta.MetaItem* items) unique
                  | MetaSlotValueModule(MoonliftMeta.MetaModule module) unique

    MetaSlotBinding = (MoonliftMeta.MetaSlot slot, MoonliftMeta.MetaSlotValue value) unique
}
```

## 8.1 Important properties of this schema

### It mirrors `Elab`
This is deliberate.

### It is not open `Sem`
There is no `MetaCallTarget`, `MetaIndexBase`, or other downstream semantic commitment.

### It includes imports explicitly
This reflects the real current dependency shape of elaboration.

### It includes slot kinds explicitly
This makes structural substitution complete, not ad hoc.

### It includes module packaging explicitly
This reflects the actual current compiler.

---

# 9. Semantics of the major open forms

## 9.1 Expr fragments

A `MetaExprFrag` is:

- an open elaborated expression
- with explicit params/imports/slots
- typed
- hygienic
- inline by nature

Its body may contain:

- param refs
- import refs
- local binders
- expr slots
- type slots
- domain slots through loop/domain structure
- nested fragment uses
- calls through binding refs to functions/imports/slots of function type

## 9.2 Region fragments

A `MetaRegionFrag` is:

- an open elaborated stmt sequence
- with explicit params/imports/slots
- hygienic
- inline by nature

This is the right unit for:

- loops
- branchy control flow
- block assembly
- DSP step pipelines
- stateful callback loop bodies

## 9.3 Functions

A `MetaFunction` is:

- callable
- graph-visible
- sealable
- module-packagable
- not just an inline fragment

Its interface may still have:

- params
- imports
- slots

But after sealing it becomes ordinary current function IR, not a new long-lived semantic universe.

## 9.4 Consts

A `MetaConstDecl` is an open const template.

Important restriction:

- it may use imports and slots
- it does **not** conceptually have runtime params

In the schema above this is represented by `MetaInterface`, but a const declaration is expected to have `#params == 0`.

## 9.5 Modules

A `MetaModule` is an open package of items.

It supports:

- funcs
- externs
- consts
- item-list slots
- nested module use/splicing

During module assembly, the module synthesizes an internal scope containing:

- sibling function syms
- sibling extern syms
- sibling const syms

so bodies can refer to them hygienically and structurally.

---

# 10. Assembly semantics in `Meta`

## 10.1 Fragment use is an assembly-time operation

Expr and region fragments are for assembly.

That means fragment use should exist in `Meta`, not in `Sem`.

Examples:

- `MetaExprUseExprFrag`
- `MetaStmtUseRegionFrag`

These are **meta-level use nodes**.
They may survive for a while in `Meta` for caching and normalization purposes, but they should be normalized/closed away before ordinary `Elab -> Sem` lowering.

## 10.2 Function use is different

Function references and function calls should survive as real callable structure.

That is why functions are represented by:

- symbols
- module items
- binding references of function type
- ordinary call expressions

rather than by inline fragment use.

## 10.3 Slots are filled structurally

`MetaSlotBinding` values substitute structurally according to slot kind.

Examples:

- type slot -> `MetaType`
- expr slot -> `MetaExpr`
- region slot -> stmt list
- domain slot -> `MetaDomain`
- function slot -> `MetaFunction`
- items slot -> item list
- module slot -> module template

## 10.4 Imports are not slot-filled by default

Imports are fixed dependencies, not holes.

If the user wants something to be late-filled structurally, it should be a slot.
If they want a stable external dependency, it should be an import.

---

# 11. Builder and source convergence

A hard rule remains:

> builder, source-string, and later hosted-parser quote forms must all converge to the same `MoonliftMeta` representation.

## 11.1 Source quote path

Source path should be:

1. parse to `MoonliftSurface`
2. elaborate against an explicit `MetaInterface`
3. produce `MoonliftMeta`
4. assemble / normalize / close
5. lower closed `Elab -> Sem -> Back`

## 11.2 Builder quote path

Builder path should be:

1. construct `MoonliftMeta` directly
2. using explicit params/imports/slots
3. assemble / normalize / close in the same way as source quotes
4. then continue through the same closed compiler path

## 11.3 Why this convergence point is correct

Converging at `Meta` means:

- source quotes are hygienic as soon as they are elaborated
- builder quotes and source quotes share the same structural identity model
- rewrites/queries operate on one open-code representation
- downstream lowerings stay ordinary

---

# 12. Sealing / closure to ordinary `Elab`

The closure boundary is:

- `Meta -> Elab`

## 12.1 A closed expr fragment seals to

- ordinary `ElabExpr`

## 12.2 A closed region fragment seals to

- ordinary `ElabStmt*`

## 12.3 A closed function seals to

- ordinary `ElabFunc`

## 12.4 A closed const seals to

- ordinary `ElabConst`

## 12.5 A closed module seals to

- ordinary `ElabModule`

## 12.6 What “closed” means

A meta object is closed when:

- all slots are filled
- all imports are resolved/fixed
- all fragment-use nodes are normalized away appropriately
- all module item splices are resolved
- all binder identities are deterministically finalized

At that point the current compiler continues normally.

---

# 13. What must remain out of `Sem`

Because the open layer is `Meta`, the following should **not** be the primary home of quote openness:

- open expr slots in `Sem`
- open region splices in `Sem`
- module/item splicing in `Sem`
- quote import environments in `Sem`

`Sem` should receive ordinary closed elaborated code after `Meta -> Elab` closure.

This keeps the current compiler layering clean.

---

# 14. PVM phase structure

The quote system should be implemented as explicit PVM phases over ASDL values.

## 14.1 Construction phases

Examples:

- `build_meta_expr_frag`
- `build_meta_region_frag`
- `build_meta_function`
- `build_meta_const`
- `build_meta_module`
- `parse_source_quote_to_meta`

## 14.2 Interface/env synthesis phases

Examples:

- `meta_interface_value_env`
- `meta_interface_type_env`
- `meta_interface_layout_env`
- `meta_module_scope_env`

These construct the actual elaboration environment used by source quote elaboration.

## 14.3 Normalization phases

Examples:

- `meta_alpha_normalize`
- `meta_expand_fragment_uses`
- `meta_expand_region_slots`
- `meta_expand_item_splices`
- `meta_validate_closedness`

## 14.4 Slot filling phases

Examples:

- `meta_with_slots`
- `meta_with_items`
- `meta_with_module`

## 14.5 Sealing phases

Examples:

- `seal_meta_expr_to_elab`
- `seal_meta_region_to_elab`
- `seal_meta_func_to_elab`
- `seal_meta_const_to_elab`
- `seal_meta_module_to_elab`

## 14.6 Downstream existing phases remain ordinary

After sealing, existing phases continue unchanged in spirit:

- `Elab -> Sem`
- `Sem -> Back`
- `Back -> Artifact`

---

# 15. User-facing API implications

The semantic model is complete and bigger than the common API.
The everyday API can still stay focused.

## 15.1 Common public forms

The common path should emphasize:

- `q.expr(interface, body)`
- `q.region(interface, body)`
- `q.func(name, interface, body)`
- `q.const(name, interface, body)`
- `q.module(interface, items)`

## 15.2 Common interface values

The host should expose first-class values for:

- types
- domains
- params
- imports
- slots
- fragments
- functions
- consts
- modules

## 15.3 Slot constructors should be kinded

Examples:

- `q.slot.type("T")`
- `q.slot.expr(i32)("rhs")`
- `q.slot.domain("D")`
- `q.slot.region("body")`
- `q.slot.func(fn_ty)("helper")`
- `q.slot.items("extra_items")`
- `q.slot.module("pkg")`

## 15.4 Assembly operations

Examples of intended operations:

- `frag:with { ... }`
- `func:with { ... }`
- `module:with { ... }`
- using a fragment in a builder quote creates a `MetaExprUseExprFrag` or `MetaStmtUseRegionFrag`
- using a function in a builder quote creates binding/call structure, not inline fragment use

## 15.5 Query/rewrite/walk should target `Meta`

The complete design should eventually make quote transformations operate on:

- `MetaType`
- `MetaDomain`
- `MetaExpr`
- `MetaStmt`
- `MetaLoop`
- `MetaItem`
- `MetaModule`

not on raw strings and not primarily on downstream `Sem`.

---

# 16. Modules, sibling references, and recursion

The complete design needs to support real module assembly, including recursive/helper relationships.

## 16.1 Why symbols are needed

Module-local functions and consts need stable symbolic identities before final sealing.

That is why the design includes:

- `MetaFuncSym`
- `MetaExternSym`
- `MetaConstSym`

## 16.2 How sibling use works

Inside a module template, sibling functions/externs/consts are made available through synthesized bindings.

That allows:

- direct helper calls
- recursive calls
- mutually recursive groups
- const references

all without relying on fragile string capture.

## 16.3 When these become ordinary globals/externs

During `MetaModule -> ElabModule` sealing, these symbolic references become ordinary current closed references of the existing pipeline.

That keeps module/package assembly explicit while still using the ordinary downstream compiler.

---

# 17. Current compiler reality about types and layouts

This is important to state explicitly.

## 17.1 Current module items today

The current actual `Surface/Elab/Sem` module items are:

- funcs
- extern funcs
- consts

There are **not yet** current ASDL top-level type-definition items in the rebooted compiler.

## 17.2 Consequence for the quote design today

Therefore, in the complete design **today**:

- named types are imported context
- layouts are imported context
- field access/aggregate assembly relies on explicit type/layout imports
- module templates package funcs/externs/consts, not current local type definitions

## 17.3 Future extension path

If future Moonlift adds top-level type-definition items, the correct extension is:

- extend `MetaItem`
- extend closed `Surface/Elab/Sem` item families
- keep the same open-vs-closed architecture

The core design does not need to change.

---

# 18. Audio callback consequence

The current ASDL reread only strengthens the earlier conclusion that `region` is important now.

Why?

Because the current compiler already has explicit structured:

- loops
- switches
- block exprs
- domains
- mutable bindings

A real audio callback wants:

- a function as the exported/sealed entry
- one or a few hot loops
- region fragments assembled into the loop body
- maybe const/module packaging around helpers and externs

That maps perfectly onto:

- `MetaRegionFrag` for loop-body reuse
- `MetaFunction` for callback entry
- `MetaModule` for helper packaging

So `region` remains absolutely central.

---

# 19. Complete design summary

The full design, grounded in the current ASDL, is:

1. Moonlift keeps the ordinary closed compiler path:
   - `Surface -> Elab -> Sem -> Back`
2. Moonlift adds a full open-code layer:
   - `MoonliftMeta`
3. `MoonliftMeta` is an **open elaborated mirror** of `MoonliftElab`
4. The open layer includes complete support for:
   - types
   - domains
   - exprs
   - stmts
   - loops
   - consts
   - funcs
   - items
   - modules
5. The interface model has three parts:
   - runtime params
   - imports
   - slots
6. Hygiene is structural:
   - explicit interface references
   - deterministic local binder ids
   - no implicit free capture by default
7. Fragment use lives in `Meta` and normalizes away before `Sem`
8. Function/module identities survive closure and become ordinary closed code structure
9. The sealing boundary is:
   - `Meta -> Elab`
10. Downstream lowering remains:
   - ordinary `Elab -> Sem -> Back`

---

# 20. Final recommendation

The design recommendation is now very specific:

> Moonlift should implement a **complete `MoonliftMeta` layer** as a full open elaborated mirror of the current `MoonliftElab` family, with explicit params, imports, slots, deterministic binder identities, fragment-use nodes, and module packaging nodes.

And the operational boundary should be:

> **All open-code assembly happens in `Meta`; all ordinary program compilation continues from closed `Elab`.**

That is the design that matches the current ASDL and gives Moonlift a complete metaprogramming model rather than a partial quote wrapper.
