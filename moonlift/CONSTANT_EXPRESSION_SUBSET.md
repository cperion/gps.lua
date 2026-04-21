# Moonlift Constant Expression Subset

Status: current explicit definition of what the rebooted Moonlift compiler treats as a constant expression today.

This file is normative for the current implementation.
If the implementation and this file disagree, fix one of them immediately.

The goal of this file is not to describe some future ideal const system.
It describes the **current closed subset** that the implementation actually supports.

This subset is split across two distinct places in the compiler:

- **type-level constant evaluation** for array counts during `Elab -> Sem`
- **value-level constant evaluation** for `SemConst` materialization during `Sem -> Back`

Those two subsets overlap, but they are not identical.

---

# 1. Core rule

A Moonlift constant expression is only valid when it can be evaluated through the explicit compiler phases already present in the reboot:

- type-level counts through explicit `ElabConstEnv`
- value-level constant data through explicit `SemConstEnv`
- block/loop local state through explicit `SemConstLocalEnv`
- statement/control effects through explicit `SemConstStmtResult`

No hidden Lua-side evaluator caches or ambient runtime state are part of the model.

If a form depends on:

- runtime locals not represented in `SemConstLocalEnv`
- address identity
- loads/stores
- calls/intrinsics outside the explicitly allowed subset
- backend rediscovery of source semantics

then it is **not** part of the current constant-expression subset.

---

# 2. Type-level constant subset for array counts

Current type-level array count expressions support:

- integer literals
- arithmetic over count expressions:
  - add
  - sub
  - mul
- references to explicit index-typed global const bindings through `ElabConstEnv`
- sibling module const references when `ElabModule` lowering seeds them into the const env

Current type-level array count expressions do **not** support:

- runtime local bindings
- mutable locals
- argument bindings
- extern bindings
- calls
- intrinsics
- control-flow expressions
- address/load/store forms
- general loops

Type-level count evaluation must produce a non-negative integer.

---

# 3. Value-level constant subset for `SemConst`

## 3.1 Scalar literals and references

Supported:

- integer literals
- float literals
- bool literals
- nil / zero-init
- references to sibling/global const bindings through explicit `SemConstEnv`
- local constant bindings through explicit `SemConstLocalEnv`

Current global const references are limited to the current module sibling story already implemented in `SemConstEnv` synthesis.

## 3.2 Unary forms

Supported:

- `neg`
- `not`
- `bnot`

## 3.3 Binary scalar forms

Supported:

- arithmetic:
  - `add`
  - `sub`
  - `mul`
  - `div`
  - `rem`
- comparisons:
  - `eq`
  - `ne`
  - `lt`
  - `le`
  - `gt`
  - `ge`
- bool:
  - `and`
  - `or`
- bitwise:
  - `bitand`
  - `bitor`
  - `bitxor`
  - `shl`
  - `lshr`
  - `ashr`

## 3.4 Cast forms

Supported:

- `cast`
- `trunc`
- `zext`
- `sext`
- `bitcast`
- `sat_cast`

## 3.5 Selection and projection

Supported:

- `if`
- `select`
- aggregate field projection
- array index projection

## 3.6 Aggregate and array materialization

Supported:

- named aggregate literal consts
- array literal consts
- recursive aggregate/array const materialization

---

# 4. Constant statement subset

Constant statements are evaluated through explicit `SemConstStmtResult` values.

Supported statement forms:

- `let`
- `var`
- `set`
- expr stmt
- `if`
- `switch`
- `assert`
- loop stmt
- loop-local `break`
- loop-local `continue`

Not supported as constant statements:

- `store`
- general address-manipulating statements
- calls
- intrinsics
  - except insofar as the currently supported const subset may grow in the future; today they are excluded

`return`/`break`/`continue` are tracked explicitly in `SemConstStmtResult` and only valid where consumed by the enclosing constant control form.

---

# 5. Constant control-flow subset

## 5.1 Block and switch

Supported:

- block expressions
- switch expressions
- switch statements inside constant blocks/loops

These use:

- explicit block-local env growth
- explicit statement fallthrough/control result tracking

## 5.2 Loop subset

Supported loop forms:

- `while` stmt loops
- `while` expr loops
- `over range(stop)` stmt/expr loops
- `over range(start, stop)` stmt/expr loops

Loop evaluation uses:

- explicit loop-carried binding values
- explicit outer/local env projection
- explicit `break` / `continue` handling

Not supported in constant loops:

- `over bounded value`
- `over zip_eq(...)`

---

# 6. Explicit exclusions

The following are **not** part of the current value-level constant-expression subset:

- address-taking
- dereference
- loads
- stores
- normal calls
- intrinsic calls
- multi-module general const reference resolution beyond the currently implemented sibling/module env story
- `over bounded value` constant loops
- `zip_eq` constant loops

So, to answer the open checklist question explicitly:

- **calls are not part of the current constant-expression subset**
- **intrinsics are not part of the current constant-expression subset**

---

# 7. Operational notes

- The constant subset is intentionally defined by explicit ASDL/env/result shapes, not by ad hoc evaluator heuristics.
- If new forms are added, update this file in the same patch.
- If semantics change, update this file immediately.

This file should shrink the gap between “implemented” and “documented” for the current reboot.
