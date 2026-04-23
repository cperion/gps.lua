# Moonlift Closed-Language Semantic Decisions

Status: **frozen semantic target** for the current rebooted **closed** Moonlift language.

This document exists to stop architectural drift.
It records the semantic choices that have now been settled for the current closed compiler path, even where implementation still lags behind the target.

Primary closed compiler path:

```text
Surface -> Elab -> Sem -> Back -> Artifact
```

This document is about that path only.
It does **not** define the future `Meta` layer or deferred hosted integration.

Companion docs:

- `moonlift/CONTRIBUTING.md`
- `moonlift/REBOOT_SOURCE_SPEC.md`
- `moonlift/TYPED_LOOP_SIGNATURE_PROPOSAL.md`
- `moonlift/CURRENT_IMPLEMENTATION_STATUS.md`
- `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md`

---

# 1. How to use this document

Use this file when a contribution would otherwise reopen a semantic question such as:

- is this a value or a stored cell?
- does this loop produce one result or many?
- is `select` just syntax sugar for `if`?
- are function values really first-class?
- are slices/views real runtime values or just helper lowering notions?
- does the language have multi-result returns?

If this file and the implementation disagree:

- the implementation/status/checklist should be updated explicitly
- do **not** silently drift by treating old uncertainty as permission to improvise

Short rule:

> implement against these decisions unless the user explicitly asks to reopen one.

---

# 2. Single-result language, no anonymous product values

The closed language is a **single-result** language.

That means:

- expressions produce exactly one value
- loop expressions produce exactly one value
- functions return exactly one value
- calls receive exactly one result value
- the language does **not** use anonymous tuple/product values
- the language does **not** have multi-result returns

If multiple logical results are needed, they must be packaged in an explicit named aggregate value.

Canonical pattern:

```text
end -> Stats { sum = sum, count = count }
```

not:

```text
end -> (sum, count)
```

This is a deliberate simplification for:

- ASDL clarity
- simpler `Sem` and `Back` result shapes
- easier Cranelift-facing lowering
- avoiding tuple/multi-result pressure infecting the entire language

---

# 3. Loop semantics

Moonlift loops are explicit state-transition forms.
That is a distinctive language choice and should be preserved.

## 3.1 Loop carries are state, not implicit outputs

Loop carries represent the evolving loop state.
They are **not** implicitly the result of the loop.

So a loop does **not** automatically return:

- all carries
- the last carry
- some hidden output port

The result is always explicit.

## 3.2 `next` is fundamental

`next` is not optional sugar.
It is the explicit recurrence relation for loop state.

That means the intended loop reading is:

```text
initial state
-> body
-> next state
-> final projection
```

not mutation-driven rediscovery.

## 3.3 Loop expressions return one value

A loop expression returns exactly one value.

There are two result paths:

### Natural completion

If the loop terminates normally, the trailing projection is used:

```text
... end -> expr
```

That `expr` is the loop expression's final value.

### Early completion

If the loop exits early with:

```text
break expr
```

then that `expr` is the loop expression's final value.

These two result paths must agree on one result type.

## 3.3a Surface syntax note

The source language may expose expr-loop result types in the loop header so loops read more like typed signatures.
That remains a **Surface** concern only.
It does **not** change the meaning frozen here:

- natural completion still uses an explicit final projection
- early completion still uses `break expr`
- carries remain state, not hidden outputs

See:

- `moonlift/TYPED_LOOP_SIGNATURE_PROPOSAL.md`

## 3.4 Bare `break`

Bare `break` belongs to statement-loop control.
It is not the valued early-result form for a non-void loop expression.

## 3.5 Shared body-local values are semantically one value

If a loop body computes a local value and then uses it in multiple places in the same iteration, that is semantically one value, not an invitation for later lowering to rediscover or duplicate it arbitrarily.

Canonical example:

```text
let out = ...
set dst[i] = out
next acc = out
```

The architecture should preserve that shared value honestly.

---

# 4. Value, place, and storage model

## 4.1 Source-level binding meaning

The closed language uses these source-level meanings:

- `let` = immutable value binding
- `var` = mutable cell binding
- params = value bindings
- loop carries = value bindings
- loop indices = value bindings

So storage is **not** a general source-level property.
The main authored storage-bearing construct is `var`.

## 4.2 Storage is decided later and explicitly

For immutable locals/params/carries/indices:

- they are values first
- they become stored/addressable only when semantics or ABI/materialization require it

That classification belongs in explicit machine-facing `Sem` answers, not in early/source-facing binders.

## 4.3 Addressability

Addressability flows through explicit place forms.
The language should not treat arbitrary expressions as implicitly addressable.

Address-of applies to real places rooted in explicit place categories such as:

- immutable locals
- mutable locals
- params
- loop carries
- loop indices
- statics
- projections/dereferences/indexes rooted in those addressable bases

Address-of does **not** apply to:

- pure compile-time `const` values
- arbitrary temporary rvalues
- ad hoc computed expressions that are not real places

## 4.4 Required `Sem` truth

Because lowering materially differs, `Sem` should distinguish binding/storage classes when needed, rather than hiding the difference in helper logic.

Important intended distinctions include:

- pure immutable local value
- stored immutable local
- mutable local cell
- pure value param
- stored/address-taken param
- pure value loop carry / index
- stored/address-taken loop carry / index

---

# 5. Conditional and dispatch forms

## 5.1 `if`

`if` is the ordinary control-flow conditional.
It has lazy branch semantics:

- only the taken branch is evaluated
- it may lower through CFG/control structure

## 5.2 `select`

`select(cond, a, b)` is a distinct dataflow choose form.
It is **not** merely a generic `if` with a codegen hint attached.

It should remain explicit in the semantic layers as the choose-shaped operation.

So the intended split is:

- `if` = control-flow conditional
- `select` = explicit choose/dataflow conditional

## 5.3 `switch`

`switch` is a first-class semantic dispatch form and should be preserved as such through `Sem`.
It should not be collapsed early into compare chains unless that is the deliberate lowering step.

Frozen closed-language switch rules:

- no fallthrough
- stmt-switch and expr-switch remain distinct
- expr-switch arms remain `stmt* + result expr`
- intended key kinds are:
  - `bool`
  - integral scalar values
  - `index`
- non-scalar switch keys are **not** part of the closed language target
- float switch keys are **not** part of the closed language target

---

# 6. Value categories

## 6.1 Structs and arrays

Named structs and arrays are first-class language values.
If multiple logical values must move together, use an explicit struct.

## 6.2 Slices

Slices are first-class descriptor values.
Their canonical runtime meaning is:

```text
data + len
```

That is the intended language/runtime model, even if some implementation paths still lag.

## 6.3 Views

Views are also first-class descriptor values.
Their canonical runtime meaning is:

```text
data + len + stride
```

Richer semantic view forms such as:

- contiguous
- strided
- windowed
- interleaved

may normalize into that canonical descriptor-oriented runtime story.

So views are not merely ad hoc lowering helpers.
They are real closed-language value/iteration nouns.

## 6.4 Function values

Function values are first-class immutable callable values.
That includes the semantic direction for:

- ordinary function items
- extern function items
- direct call targets
- indirect call targets

The closed language does **not** include closures/captures in this model.
Function values are code-pointer-like callable values, not closure environments.

---

# 7. ABI target

The intended ABI target for the closed language is:

- exactly one result
- no multi-result returns

## 7.1 By-value categories

These are intended to travel by value:

- scalar ints/floats/bool/index
- pointers
- function values
- slice descriptors
- view descriptors

## 7.2 Aggregate categories

These are intended to lower through hidden-pointer/materialization conventions rather than anonymous tuple-like or multi-result ABIs:

- named structs
- arrays
- other aggregate values in the same family

That means the ABI model is deliberately friendly to a Cranelift-facing lowering path:

- one result
- descriptor values where appropriate
- aggregate materialization where appropriate

---

# 8. Global/item semantics

## 8.1 `const`

`const` means a pure compile-time value.
It is not an addressable runtime storage location.

## 8.2 `static`

`static` means addressable storage.
It is the addressable global-data form.

## 8.3 Mutable globals

If mutable global storage exists, it belongs to the `static`/addressable-data story, not the pure `const` story.

## 8.4 Externs

Extern function items are semantically function values in the same callable family, even if current implementation still supports them incompletely outside call-target position.

---

# 9. What these decisions imply for implementation

These decisions freeze the target.
They do **not** claim every implementation piece is complete today.

In particular, the implementation still needs to finish work such as:

- splitting `Sem` binding/storage classes where lowering differs
- preserving `select` and `switch` honestly through later lowering
- finishing loop-body control/result lowering for realistic branchy bodies
- completing aggregate/non-scalar load/call/return support under the single-result + explicit-struct model
- completing first-class function-value handling under the no-closure model
- aligning Rust/FFI ABI details with the frozen single-result descriptor/aggregate strategy

Use `moonlift/CURRENT_IMPLEMENTATION_STATUS.md` for what exists today.
Use `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md` for the remaining implementation work.

---

# 10. Short summary

The closed Moonlift language is now frozen around these core choices:

- one-result language
- no anonymous tuple/product values
- explicit structs for multi-field results
- loops as explicit state-transition forms with explicit final projection
- value-first bindings with later explicit storage classification
- `if` distinct from `select`
- `switch` preserved as switch
- slices/views as real descriptor values
- function values as first-class immutable callable values
- one-result ABI with aggregates lowered through materialization/hidden-pointer paths

That is the current closed-language target.