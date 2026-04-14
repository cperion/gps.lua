# JSON_POLICY_PLAN.md — minimal semantic policy ASDL

## Purpose

This document defines the **smallest explicit semantic policy layer** we should add on top of exact `Json.Value`.

It is intentionally **not** a full formal JSON Schema system.

The exact JSON tree already carries a large amount of implicit structure through:

- ASDL constructor choice
- interned subtree identity
- recurring object/list shapes
- downstream phase reuse

So the policy layer should only express semantic choices that are **not already naturally implied** by exact JSON structure.

---

## Core rule

> Exact JSON carries observed structure.
> Policy carries semantic expectations.

Observed structure includes:

- object vs array vs scalar
- object entry order
- duplicate key preservation
- exact number lexeme
- repeated subtree shape

Semantic expectations include:

- whether a key is required
- whether `null` is allowed
- how duplicates are handled
- how numbers are interpreted
- whether extra fields are allowed
- how tagged object variants are resolved

This is the boundary between implicit schema and explicit policy.

---

## Why this layer exists

Without a policy layer, domain decoders end up re-embedding hidden enums in code:

- `if required then ...`
- `if allow_null then ...`
- `if duplicate_mode == ... then ...`
- `if kind == ... then ...`

Those are semantic distinctions in hiding.

The policy layer exists to make those distinctions explicit, typed, and reusable.

---

## Scope

The minimal policy layer should cover only:

1. scalar interpretation
2. object field presence
3. null handling
4. duplicate-key strategy
5. extra-field strategy
6. tagged object discrimination
7. arrays of homogeneous item shape

It should **not** initially try to solve:

- advanced numeric ranges
- regex validation
- dependent constraints
- arbitrary predicates
- universal external schema interchange
- full JSON Schema compatibility

Those can come later if they become real architectural needs.

---

## Proposed ASDL

```lua
module JsonPolicy {
    Spec = Any unique
         | Null unique
         | Bool unique
         | Str unique
         | Num(JsonPolicy.NumSem sem) unique
         | Arr(JsonPolicy.ArraySpec spec) unique
         | Obj(JsonPolicy.ObjectSpec spec) unique
         | TaggedObj(JsonPolicy.TaggedSpec spec) unique

    NumSem = KeepLexeme unique
           | LuaNumber unique
           | Integer unique

    Presence = Required unique
             | Optional unique
             | DefaultNull unique
             | DefaultBool(boolean value) unique
             | DefaultNum(string lexeme) unique
             | DefaultStr(string value) unique

    NullPolicy = ForbidNull unique
               | AllowNull unique
               | NullMeansAbsent unique

    DupPolicy = Preserve unique
              | Reject unique
              | FirstWins unique
              | LastWins unique

    ExtraPolicy = ForbidExtra unique
                | AllowExtra unique

    FieldSpec = (string key,
                 JsonPolicy.Spec spec,
                 JsonPolicy.Presence presence,
                 JsonPolicy.NullPolicy nulls) unique

    ObjectSpec = (JsonPolicy.FieldSpec* fields,
                  JsonPolicy.DupPolicy dups,
                  JsonPolicy.ExtraPolicy extras) unique

    ArraySpec = (JsonPolicy.Spec items) unique

    TaggedCase = (string tag, JsonPolicy.ObjectSpec object) unique

    TaggedSpec = (string tag_key,
                  JsonPolicy.TaggedCase* cases,
                  JsonPolicy.DupPolicy dups,
                  JsonPolicy.ExtraPolicy extras) unique
}
```

---

## Design notes

### `Spec`

This is the top semantic expectation for a JSON position.

It intentionally stays small:

- scalar expectations
- homogeneous arrays
- object expectations
- tagged objects as the important union case

It does **not** yet include a full generic `OneOf` / universal union mechanism. Tagged objects cover the most important practical case for app/protocol/config decoding.

### `NumSem`

This is a real semantic distinction that exact `Json.Num(string lexeme)` does not consume by itself.

- `KeepLexeme` — preserve exact text meaning downstream
- `LuaNumber` — coerce via `tonumber`
- `Integer` — require integer interpretation

This should be explicit, not buried in decoder code.

### `Presence`

This expresses whether a field must appear, may be omitted, or supplies a default.

Defaults are intentionally limited at first to common JSON scalar defaults.

We should not generalize this prematurely to arbitrary JSON subtrees unless a real use case demands it.

### `NullPolicy`

This is separate from presence because they answer different questions.

Examples:

- a key may be required but allow `null`
- a key may be optional but forbid explicit `null`
- a key may treat `null` as equivalent to absence

That is real semantic structure.

### `DupPolicy`

Exact JSON preserves duplicates. Policy decides what that means.

This is one of the most important hidden branches to make explicit.

### `ExtraPolicy`

This controls whether undeclared object keys are accepted.

Again: a real semantic choice, not a micro implementation detail.

### `TaggedObj`

We should model tagged-object discrimination directly because it is the most common and most optimization-relevant union shape in real JSON configs and protocols.

Examples:

- `{ "kind": "rect", ... }`
- `{ "type": "open", ... }`
- `{ "op": "insert", ... }`

Those are almost always hidden sum types.

---

## Why no full schema language yet

A full schema language would likely add:

- universal references
- generic unions
- tuples
- length constraints
- numeric ranges
- pattern properties
- recursive named schemas
- etc.

That may become useful later, but it would be too early now.

The repository rule from `COMPILER_PATTERN.md` applies:

- make real distinctions explicit
- do not add architecture before the domain demands it

So this policy layer is deliberately minimal and practical.

---

## Boundary shape

The policy layer is consumed at semantic decode boundaries.

Conceptually:

```text
Json.Value + JsonPolicy.Spec -> typed/domain meaning
```

There are two likely implementation strategies.

### Strategy A — explicit pair node

Create an ASDL node such as:

```lua
DecodeReq = (JsonPolicy.Spec spec, Json.Value value) unique
```

and run a pvm phase over that node.

Pros:

- very pvm-native
- policy identity and value identity both participate structurally
- simple conceptual model

Cons:

- if used on unbounded request-space data without care, pair cardinality can grow

### Strategy B — policy-specialized decoder

Resolve/build a decoder from policy, then apply it to JSON trees.

Pros:

- good for bounded policy sets reused over many values
- cleaner for long-lived application schemas

Cons:

- slightly less direct as a pure ASDL story

Both are valid. For config/hot-reload-oriented uses, Strategy A is especially attractive.

---

## Example policies

### Example 1 — simple object config

```text
Obj(
  fields = {
    FieldSpec("name", Str, Required, ForbidNull),
    FieldSpec("enabled", Bool, Optional, ForbidNull),
    FieldSpec("threshold", Num(LuaNumber), DefaultNum("0.5"), ForbidNull)
  },
  dups = Reject,
  extras = ForbidExtra
)
```

Meaning:

- `name` must exist and be a string
- `enabled` may be absent
- `threshold` defaults to `0.5`
- duplicate keys are rejected
- no undeclared keys allowed

### Example 2 — tagged union

```text
TaggedObj(
  tag_key = "kind",
  cases = {
    TaggedCase("point", Obj(...)),
    TaggedCase("line", Obj(...)),
    TaggedCase("polygon", Obj(...))
  },
  dups = Reject,
  extras = ForbidExtra
)
```

Meaning:

- the object must contain `kind`
- `kind` selects the semantic variant
- each variant has its own object field expectations

This is the JSON-level reflection of a sum type.

---

## Relation to exact JSON

The policy layer must not rewrite or erase exact JSON structure by itself.

Exact layer:

- preserves all entries
- preserves duplicates
- preserves source order
- preserves exact number lexeme

Policy layer:

- interprets those structures
- rejects, normalizes, or projects according to semantic needs

This separation is essential.

---

## Relation to domain ASDL

The policy layer is not the domain model.

It exists only to guide semantic interpretation from exact JSON into domain ASDL.

Example pipeline:

```text
text
  -> Json.Value
  -> policy-guided decode
  -> Theme.* / App.* / Geo.*
```

The domain ASDL remains the internal architecture.

---

## Suggested module path

When we resume code, the likely module should be:

```text
json/policy_asdl.lua
```

with a facade in:

```text
json/policy.lua
```

Suggested exports:

- `P.T` — policy context/types
- small constructors/helpers for common patterns
- no giant helper API initially

---

## Immediate coding plan from this design

When we restart implementation:

1. add `json/policy_asdl.lua`
2. implement minimal policy helpers
3. prototype one real policy-guided typed decoder for an existing config/domain shape
4. benchmark hot reload / repeated decode reuse

---

## Success criteria

This policy layer is successful if:

1. it removes semantic branching from decoder code
2. it stays much smaller than a full JSON Schema implementation
3. it composes cleanly with exact `Json.Value`
4. it improves typed decoding clarity and reuse
5. it remains aligned with the repo principle: design by real distinctions, not by metadata inflation

---

## Short formulation

```text
Exact JSON preserves structure.
Policy expresses semantic expectation.
Domain ASDL carries meaning.
Only make explicit what exact structure does not already imply.
```
