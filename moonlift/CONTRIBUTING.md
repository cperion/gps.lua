# Moonlift Contribution Guide

This guide defines how to contribute to Moonlift without breaking its architecture.

Moonlift is not a generic Lua project with some IR structs.
It is an **ASDL-first compiler** built around explicit layers and `pvm` phase boundaries.
If a change does not respect that, it is not a valid contribution even if it makes a test pass.

This guide is grounded in:

- `docs/COMPILER_PATTERN.md`
- `moonlift/CLOSED_LANGUAGE_SEMANTIC_DECISIONS.md`
- `moonlift/CURRENT_IMPLEMENTATION_STATUS.md`
- `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md`

---

# 1. The one rule

> If the compiler needs to distinguish it, that distinction must be explicit in ASDL.

That means:

- if lowering differs, the ASDL should differ
- if typing differs, the ASDL should differ
- if control flow differs, the ASDL should differ
- if materialization/result shape differs, the ASDL should differ
- if name resolution/layout resolution depends on it, the ASDL should differ

Do **not** hide semantic choices in:

- Lua helper switches
- string tags
- context tables
- opaque wrapper objects
- metatable checks
- ad hoc booleans sprinkled through helpers

If you feel tempted to do that, stop and fix the ASDL first.

---

# 2. The compiler pattern Moonlift follows

Moonlift follows the compiler pattern described in `docs/COMPILER_PATTERN.md`.
The current frozen closed-language target is defined in:

- `moonlift/CLOSED_LANGUAGE_SEMANTIC_DECISIONS.md`

That target is implemented through the same compiler pattern:

- the user authors a program in a domain language
- the source ASDL is the architecture
- boundaries are memoized `pvm.phase(...)` transforms
- execution is a loop over compiled facts

For Moonlift specifically, the current canonical closed compiler path is:

```text
Surface -> Elab -> Sem -> Back -> Artifact
```

Meaning:

- `Surface` = authored/unresolved syntax-shaped language
- `Elab` = resolved, typed, hygienic middle layer
- `Sem` = machine-facing semantic layer
- `Back` = symbolic backend builder command layer
- `Artifact` = compiled runtime code

Do not bypass this architecture just because a shortcut seems smaller.

---

# 3. Mandatory architecture rules

## 3.1 Do not skip layers

If a construct is still authored/unresolved, it does **not** belong in `Sem`.
If a construct is already backend-command-shaped, it does **not** belong in `Elab`.

Typical rule:

- authored names / authored syntax choices live in `Surface`
- resolved bindings / explicit types live in `Elab`
- call target class, addressability, layout-resolved field refs, runtime lowering distinctions live in `Sem`
- backend block/value/stack/data commands live in `Back`

## 3.2 Do not invent side IRs

Do not create:

- a hidden Lua IR that sits “between” ASDL layers
- a manual tag-based backend IR in Rust
- an ad hoc table protocol used by helpers instead of ASDL nodes

If a new intermediate representation is needed, put it in ASDL and give it a real layer or result type.

## 3.3 Rust is thin

Rust should not define a second Moonlift compiler architecture.
The Rust side is a thin validated host/codegen layer over the current `Back` command stream.

Do not “fix” frontend or middle-layer design problems by inventing richer hidden Rust IR.

---

# 4. All switching is done by pvm

## 4.1 What this means

Meaningful semantic dispatch should happen through:

```lua
pvm.phase("name", {
    [T.SomeType] = function(self, ...)
        ...
    end,
})
```

Not through:

- `if node.kind == "..." then`
- `if op == "add" then`
- `if mt.__class == ... then`
- helper tables keyed by string tags
- manual cascades over constructors that should have been separate ASDL variants

## 4.2 Good examples from Moonlift

These were correct architectural moves because they made distinctions explicit in ASDL and then dispatched with `pvm`:

- split void vs valued return nodes
- split stmt-switch arms vs expr-switch arms
- split loop stmt vs loop expr
- split local immutable values vs mutable cells
- split machine-facing binding classification into explicit pure/stored/cell cases through `SemBackBinding`
- split unresolved field refs vs offset-resolved field refs
- split scalar expr lowering results into `BackExprPlan` vs `BackExprTerminated`
- split address/materialization lowering results into `BackAddrWrites` vs `BackAddrTerminated`

Those are the model.

## 4.3 If a helper asks a semantic question, that is a warning sign

Moonlift now also has a ratcheting audit test for this class of mistake:

- `moonlift/test_semantic_dispatch_audit.lua`
- baseline file: `moonlift/semantic_dispatch_audit_baseline.txt`

Rule:

- do **not** add new raw semantic `.kind` dispatch or new raw helper type-classification logic in active semantic/backend compiler files
- if a distinction matters, represent it explicitly and answer it through ASDL + `pvm.phase(...)`
- the audit baseline is debt inventory, **not** permission to add more debt
- the current goal is to keep the baseline empty; treat any new finding as a regression unless the audit scope itself is intentionally expanded

If you remove old raw dispatch sites, update the baseline in the same change so the ratchet tightens.

Examples of dangerous helper questions:

- “does this terminate?”
- “is this really a stmt or expr arm?”
- “is this storage or just a value?”
- “does this path mean local or qualified global?”

If the answer matters to lowering, that choice should usually be in ASDL and queried through a phase.

---

# 5. ASDL do and don’t list

## 5.1 Do

- use explicit sum variants for real language distinctions
- use explicit product fields for real payload
- use separate constructors when lowering behavior differs
- use explicit ids where identity matters under interning
- use explicit result-shape types when consumers need to branch on lowering outcome
- use explicit env/layout/input ASDL where compiler boundaries require it

## 5.2 Don’t

- use stringly-typed `kind` fields where sum variants belong
- use one generic node plus helper branching if the variants are semantically different
- encode semantic distinctions in nil-check conventions unless the optionality is truly semantic
- rely on Lua object wrappers for domain/compiler values
- keep meaningful dependencies outside ASDL in closures or globals
- invent opaque “context” bags that silently affect lowering

---

# 6. Opaque context objects are not allowed to carry semantics

This is one of the easiest ways to break the architecture.

## Wrong

```lua
local function lower_expr(node, ctx)
    if ctx.in_loop then ... end
    if ctx.want_addr then ... end
    if ctx.current_module == ... then ... end
end
```

Why it is wrong:

- the dependency is invisible to the ASDL
- it becomes hard to reason about what the layer means
- you silently create extra semantic state outside the compiler IR
- future contributors will not know which fields are real semantics vs helper convenience

## Right

Use one of these instead:

- put the distinction into ASDL
- use an explicit phase input if it is truly a compiler-boundary parameter
- define an explicit ASDL env/input object if it is part of a real boundary

Compiler-boundary inputs are allowed when they are explicit and honest.
Hidden semantic dependencies are not.

---

# 7. Result shapes must be explicit when flow differs

If a lowering path can produce structurally different outcomes, represent that in ASDL.

Examples:

- value result vs terminated path
- writes-to-address vs terminated-before-write
- resolved field-by-offset vs unresolved field-by-name
- direct call target vs extern call target vs indirect call target

Do not return mixed Lua shapes such as:

- sometimes an array, sometimes a table
- sometimes a value, sometimes `nil`
- sometimes a tuple, sometimes an object

If consumers need to know which case happened, define an ASDL type for it.

---

# 8. Names, bindings, and identity

Moonlift uses interned ASDL values.
That means identity mistakes are architectural bugs, not minor implementation details.

## 8.1 If shadowing can happen, names are not enough

If two locals can share the same surface name, then `(name, ty)` is not enough identity.
Use explicit ids.

## 8.2 Binding class is semantic

Do not collapse these into one generic binding plus flags:

- local immutable value
- local mutable cell
- arg
- global
- extern

They lower differently.
Therefore they should be distinct ASDL variants.

## 8.3 Resolution belongs in the right layer

Typical rule:

- authored names in `Surface`
- resolved bindings in `Elab`
- machine-relevant target classes in `Sem`

Do not jump directly from authored names to backend assumptions.

---

# 9. Layout and type resolution rules

If field access, aggregate construction, or indexing depends on layout/type knowledge, do not hide that lookup in arbitrary helper code.

Instead:

- model unresolved references explicitly
- add an explicit resolution boundary
- produce resolved semantic forms for downstream lowering

Moonlift already follows this pattern with field refs:

- unresolved field selection by name
- explicit layout-resolution pass
- resolved field-by-offset for `Sem -> Back`

That is the pattern to copy.

---

# 10. Adding a feature: required workflow

When adding a feature, work in this order.

## Step 1: decide the layer where the distinction belongs

Ask:

- is this authored syntax?
- elaborated typing/binding structure?
- machine-facing semantic structure?
- backend command structure?

## Step 2: update ASDL first

Add or split nodes first.
Do not begin by writing helper logic.

## Step 3: add phase boundaries / handlers

All new dispatch should be expressed as `pvm.phase(...)` handlers.

## Step 4: add explicit result/env shapes if needed

If the new feature introduces:

- multiple flow outcomes
- different materialization modes
- different resolution states
- new boundary inputs

then model those explicitly too.

## Step 5: add tests for each boundary crossed

At minimum, test the transitions you changed:

- `Surface -> Elab`
- `Elab -> Sem`
- `Sem` resolution passes
- `Sem -> Back`
- backend/FFI if affected

## Step 6: update docs/checklists

If the feature checks off a box, update:

- `moonlift/CURRENT_IMPLEMENTATION_STATUS.md`
- `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md`

if those docs are affected.

---

# 11. Review checklist for contributions

Use this before merging any nontrivial change.

## ASDL correctness

- Is every meaningful distinction explicit in ASDL?
- Is any distinction still hidden in helper logic, strings, flags, or context objects?
- Were any semantically different cases collapsed into one constructor with manual branching?

## Phase correctness

- Is dispatch done through `pvm.phase(...)`?
- Are phase inputs explicit and honest?
- Is a side cache being introduced where a phase should exist?

## Layer correctness

- Does the feature live in the right layer?
- Did the change skip `Elab` or `Sem` when it should not have?
- Did Rust stay thin, or did it start owning frontend/middle semantics?

## Flow/result correctness

- If consumers branch on lowering outcome, is that outcome represented in ASDL?
- Are mixed raw Lua result shapes avoided?

## Identity correctness

- Are binding/object identities explicit where interning makes name-only identity unsafe?
- Are mutability and storage distinctions explicit where lowering differs?

## Documentation correctness

- If this changes implementation status, did the Moonlift docs get updated?

---

# 12. Examples of rejected contribution patterns

These are not acceptable directions.

## 12.1 Manual operator switch over a generic node

```lua
if expr.op == "add" then ... elseif expr.op == "sub" then ... end
```

Fix: separate ASDL variants and dispatch with `pvm`.

## 12.2 Hidden flow convention in helpers

```lua
local plan = lower_expr(x)
if plan.terminated then ...
```

when `terminated` is just an ad hoc Lua field rather than an ASDL result variant.

Fix: add an explicit ASDL result type.

## 12.3 One binding type plus mutability flag

```lua
Binding(name, ty, is_mut)
```

Fix: separate binding variants if storage/lowering semantics differ.

## 12.4 Opaque context bag controlling semantics

```lua
lower_stmt(node, { in_loop = true, want_addr = false, ... })
```

Fix: make the distinction explicit in ASDL or an honest compiler-boundary input/result shape.

## 12.5 Rich Rust-side hidden IR

Fixing a Moonlift semantic design problem by inventing a second Rust compiler IR is not acceptable.

Fix: change Moonlift ASDL/lowering first.

---

# 13. What “ASDL first” means in practice

It does **not** mean every temporary helper variable must be an ASDL node.
It means every **semantic distinction** must be represented explicitly in the compiler architecture.

Local helper computation is fine.
Hidden semantic design is not.

Good local helper use:

- building a small command array from already-decided semantic inputs
- copying arrays
- formatting ids/paths deterministically
- small structural utility functions

Bad helper use:

- deciding which semantic variant something really is
- deciding whether something is terminating vs value-producing without ASDL backing
- deciding whether a binding is mutable/addressable/callable through flags or metatable checks
- deciding layout or resolution state implicitly in downstream code

---

# 14. Canonical reading order for contributors

Before changing architecture-heavy code, read in this order:

1. `docs/COMPILER_PATTERN.md`
2. `moonlift/CLOSED_LANGUAGE_SEMANTIC_DECISIONS.md`
3. `moonlift/CURRENT_IMPLEMENTATION_STATUS.md`
4. `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md`
5. this file

And if you are touching future-design areas:

6. `moonlift/QUOTING_SYSTEM_DESIGN.md`
7. `moonlift/LUAJIT_HOSTED_INTEGRATION.md`

---

# 15. Final rule

> Do not ask “how can I implement this with the current helpers?”
>
> Ask: “what is the real distinction here, which layer owns it, and how should it appear in ASDL?”

That is the Moonlift contribution rule.
