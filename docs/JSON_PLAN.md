# JSON_PLAN.md — pvm-native JSON design plan

## Purpose

Build a JSON stack that fits the architecture of this repository:

- exact structural ASDL as the primary representation
- fused frontend parsing
- pvm-native semantic boundaries where meaning is consumed
- flat chunk-stream output at execution time
- strong structural reuse for hot reload and repeated emission

This is not a generic Lua-table JSON codec. It is a compiler-style JSON frontend and backend for pvm.

---

## Core thesis

A good JSON implementation here should not optimize primarily by micro-ops.

It should optimize by:

- modeling JSON exactly in ASDL
- making hidden semantic choices explicit at the right layer
- preserving structural sharing
- placing phase boundaries where ambiguity is consumed
- letting iterator fusion specialize the execution path naturally

In short:

> Exact ASDL gives structural truth, phase boundaries consume meaning, and triplet fusion specializes execution.

---

## Design axioms

### 1. JSON is a language, not a table format

The core representation is an ASDL language:

- parse text into `Json.Value`
- do not use plain Lua tables as the primary JSON model
- any Lua-table interop is secondary and optional

### 2. Exactness first

The raw JSON layer must preserve distinctions that matter:

- object entry order
- duplicate keys
- exact number lexeme
- null as a real value
- array order

Do not normalize these away in the exact layer.

### 3. Hidden branches are types in hiding

Branches such as:

- required vs optional field
- number interpretation
- duplicate-key behavior
- tagged union resolution
- null/default behavior

should become explicit structural distinctions when they represent real semantic choices.

### 4. Parsing is a fused frontend

Parsing is syntax recognition:

`text -> Json.Value`

The parser should be direct and fused, not artificially decomposed into phase towers.

### 5. Real pvm value starts after syntax

The main architectural gains happen in:

- semantic projection
- typed decoding
- normalization
- emission
- downstream hot reload reuse

### 6. Emission is a real phase boundary

Emission is a lowering from JSON tree meaning to a flat chunk stream:

`Json.Value -> chunk stream`

That should be implemented as a pvm boundary.

### 7. Schema is first implicit, then explicit

A large amount of schema is already present implicitly in:

- constructor choice
- interned structure
- recurring subtree identity
- downstream phase reuse

Do not overbuild a formal schema language too early. Only introduce explicit schema/policy types when they express meaning not already implied by exact JSON structure.

### 8. Specialization arises from fusion

Specialization happens naturally through:

- correct ASDL distinctions
- proper boundaries
- triplet fusion through a single pull loop

### 9. Typed decoding is a compiler boundary

Decoding from JSON into domain types is a semantic step:

`Json.Value -> Domain.*`

This boundary consumes ambiguity and should be treated as a first-class compiler stage.

### 10. Keep exact JSON separate from domain meaning

Do not collapse external JSON representation and internal meaning into one layer.

Use:

- `Json.Value` for exact external structure
- `Domain.*` for internal typed meaning

### 11. Hot reload is structural reuse

The system should be designed so that small changes in JSON text ideally produce:

- small `Json.Value` changes
- small typed-domain changes
- widespread downstream cache hits

### 12. Flatten only at the true execution boundary

JSON trees remain trees until output execution needs a flat stream:

- emitted chunks
- socket/file writes
- downstream command streams

Tree in, flat out.

---

## Layer model

### Layer 0 — exact JSON

Faithful source language for external structured text.

```lua
module Json {
    Value = Null
          | Bool(boolean v) unique
          | Num(string lexeme) unique
          | Str(string v) unique
          | Arr(Json.Value* items) unique
          | Obj(Json.Member* entries) unique

    Member = (string key, Json.Value value) unique
}
```

Properties:

- exact
- stable
- interned
- suitable as source for reuse and downstream phases

### Layer 1 — semantic/decode policy (minimal, only when needed)

This layer should not be overdesigned up front. It should appear when repeated semantic choices are not already captured by the exact JSON tree.

Examples of likely policy distinctions:

- duplicate-key handling
- required vs optional field presence
- numeric interpretation
- tagged union discrimination
- null/default semantics

This may start as small focused ASDL types rather than a giant universal schema language.

### Layer 2 — typed domain projection

Examples:

- `Json.Value -> Theme.*`
- `Json.Value -> App.*`
- `Json.Value -> Geo.*`

This is the main semantic compiler boundary.

### Layer 3 — output projection / emission

Examples:

- `Domain.* -> Json.Value`
- `Json.Value -> chunk stream`

The flat output path lives here.

---

## What should be implicit vs explicit

### Implicit first

Let these arise naturally from exact ASDL + interning + reuse:

- observed structural shape
- repeated object/list forms
- repeated member keys and subtree forms
- repeated downstream decode/emission results

### Explicit only when semantically required

Introduce explicit policy/schema types only for distinctions such as:

- required/optional/default
- null meaning
- duplicate-key strategy
- numeric coercion/interpretation
- tagged union discrimination
- open vs closed object expectations

Rule:

> explicit schema exists only for semantic constraints not already implied by the exact JSON structure.

---

## Module plan

### Implement now

```text
json/
  asdl.lua        -- exact Json.Value language
  parse.lua       -- strict fused parser: text -> Json.Value
  emit.lua        -- pvm-native compact emitter: Json.Value -> chunks
  encode.lua      -- convenience wrappers over emit
  decode.lua      -- minimal typed helpers over Json.Value
  init.lua        -- public facade
```

### Add next

```text
json/
  policy.lua      -- minimal semantic/decode policy types or helpers
  project.lua     -- typed/domain -> Json.Value
```

### Add only when clearly needed

```text
json/
  schema_asdl.lua -- explicit schema language, if repeated semantic patterns justify it
  plan.lua        -- schema/policy -> decode plan
  pretty.lua      -- separate pretty-printing emitter/boundary
  canonical.lua   -- canonical ordering/formatting policy
  schema.lua      -- facade for schema/plan APIs
```

---

## Current representation choices

### Numbers

JSON numbers remain exact lexemes in the source layer:

```lua
Num(string lexeme)
```

Reason:

- preserves roundtrip fidelity
- avoids premature coercion
- allows later semantic interpretation by explicit boundaries

### Objects

JSON objects remain ordered entry lists:

```lua
Obj(Member* entries)
```

Reason:

- preserves duplicate keys
- preserves source order
- avoids pretending JSON objects are plain hash maps

### Null

JSON null remains its own singleton variant, not Lua `nil`.

Reason:

- `nil` means absence in Lua
- `null` means explicit value in JSON

---

## Boundary plan

### Parser

`text -> Json.Value`

- strict RFC JSON first
- no comments
- no trailing commas
- no NaN/Infinity
- no Lua-table public representation

### Emitter

`Json.Value -> chunk stream`

Compact emitter first.

Rules:

- stream chunks, do not recursively build one giant string in the core design
- let pvm cache unchanged subtree emissions
- let consumers drain to string, socket, file, or downstream sink

### Typed decode

`Json.Value -> Domain.*`

This is where semantic ambiguity is consumed.

Likely patterns:

- object field extraction helpers
- tagged object discrimination
- number interpretation helpers
- duplicate-key policy helpers
- optional/default/null handling

### Projection back to JSON

`Domain.* -> Json.Value`

Needed for:

- snapshots
- config writeback
- protocol replies
- test fixtures

This should eventually also be pvm-native and structural.

---

## Performance philosophy

Do not start with micro-optimizing parser internals or string concatenation tricks.

Primary optimization order:

1. exact ASDL modeling
2. correct semantic boundaries
3. structural sharing preservation
4. phase reuse diagnostics
5. only then local micro-ops

The most valuable performance outcomes are:

- warm/incremental reuse
- cheap hot reload
- repeated subtree emission hits
- typed decode reuse on stable config trees

Cold parse speed matters, but architectural reuse matters more.

---

## Benchmark plan

Measure three classes separately.

### 1. Cold parse

`text -> Json.Value`

Goal:

- competitive strict parser performance under LuaJIT

### 2. Cold emit

`Json.Value -> bytes`

Goal:

- strong chunk-stream emission performance

### 3. Warm/incremental re-emit

Small edit in a large JSON tree, then re-emit.

Goal:

- show architectural advantage from structural reuse
- this is where pvm-native JSON should shine most clearly

### 4. Typed decode reuse

Stable typed config schema + repeated reloads with small edits.

Goal:

- demonstrate that semantic lowering benefits from structural reuse as well

---

## Hot reload story

Desired pipeline:

```text
file text
  -> Json.Value
  -> typed domain ASDL
  -> downstream pvm phases
  -> execution artifacts
```

Desired property:

- one small edit in the text changes one small branch of `Json.Value`
- one small branch of typed domain changes
- downstream boundaries hit everywhere else

This is a primary architectural goal, not a side effect.

---

## Design warnings

### Don’t

- don’t expose Lua tables as the core JSON representation
- don’t normalize duplicate keys away in the exact layer
- don’t coerce numbers eagerly to Lua numbers in the exact layer
- don’t mix exact JSON with typed domain meaning
- don’t add a large formal schema subsystem before repeated semantic patterns justify it
- don’t optimize tiny string ops before the ASDL and boundary structure are correct

### Do

- preserve exactness in the source layer
- make hidden choices structural when they matter semantically
- keep parsing direct and fused
- make emission a true pvm boundary
- design typed decoding as compiler staging
- measure reuse, not only cold throughput

---

## Immediate next steps

### Step 1

Stabilize the exact JSON layer:

- keep `Json.Value` minimal and exact
- ensure parser/emitter roundtrip fidelity

### Step 2

Identify the smallest useful semantic policy set needed for real domain decoding.

Likely first candidates:

- field presence helpers
- number interpretation helpers
- tagged union object helpers
- duplicate-key policy helpers

### Step 3

Prototype one real typed decoder from JSON into an existing domain/config ASDL.

This is the right test of the architecture.

### Step 4

Add warm/hot-reload benchmarks showing structural reuse under small edits.

---

## Success criteria

The JSON stack is successful if:

1. exact JSON roundtrips faithfully
2. JSON is represented structurally in ASDL, not ad hoc Lua tables
3. emission is a pvm-native chunk stream
4. typed decoding into domain ASDL is clean and boundary-shaped
5. hot reload of large structured JSON shows strong downstream reuse
6. optimization decisions are driven first by modeling and boundary design

---

## Short formulation

```text
JSON text is source.
Json.Value is the exact source language.
Typed decoding is a compiler boundary.
Emission is a compiler boundary.
Structure carries meaning.
Fusion specializes execution.
Reuse is the performance story.
```
