# Moonlift Parser Bootstrap Plan

Status: immediate implementation plan for the reboot parser.

Current state:

- an initial direct-to-`MoonliftSurface` lexer/parser scaffold now exists in:
  - `moonlift/lua/moonlift/parse_lexer.lua`
  - `moonlift/lua/moonlift/parse.lua`
- smoke coverage exists in:
  - `moonlift/test_parse_smoke.lua`
- the parser already handles a useful bootstrap subset, including:
  - top-level value/import/type items
  - scalar/pointer/array/slice/function/named types
  - unary/binary/cast/intrinsic/call/field/index expressions
  - `if` expr
  - `switch` stmt/expr
  - `do ... end` block expr
  - canonical `loop ... while ...` and `loop ... over ...`
  - field-based aggregate literals
  - element-typed array literals via `[]T { ... }`
  - structured parse diagnostics through `try_parse_*`
- it is still intentionally incomplete

This file is about the **closed reboot parser**:

```text
text -> MoonliftSurface
```

It is intentionally separate from the future open quote/parser-hosted path described in:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

---

## 1. Core rule

The reboot parser should construct `MoonliftSurface` ASDL values directly.

That means:

- no plain Lua-table AST staging as the main representation
- no backend-directed parse output
- no direct `Elab`/`Sem` construction from text

The parser is a `Surface` frontend.

---

## 2. Recommended file split

Immediate practical split:

- `moonlift/lua/moonlift/parse_lexer.lua`
- `moonlift/lua/moonlift/parse.lua`

Meaning:

- `parse_lexer.lua` owns tokenization only
- `parse.lua` owns direct-to-ASDL parsing only

This keeps the hot path simple while avoiding one giant local-heavy file.

---

## 3. Parsing strategy

Recommended strategy for the reboot parser:

- hand-written Lua lexer
- recursive descent for items/types/statements
- Pratt parser (or precedence climbing) for expressions
- direct constructor calls into `MoonliftSurface`

Why this is the right fit:

- current source grammar is structured and block-oriented
- we want direct ASDL construction
- we want low overhead and no generator dependency
- Lua can call ASDL constructors directly and cheaply enough for the reboot stage

---

## 4. Phase order

### Phase 1 — bootstrap subset

Get a direct-to-ASDL parser working for the current stable subset first:

- types
  - scalar
  - pointer
  - array
  - slice
  - function type
  - named path
- expressions
  - literals
  - names / paths
  - unary / binary ops
  - casts
  - intrinsic calls
  - call / field / index
  - basic `if` expr
- statements
  - `let`
  - `var`
  - `set`
  - expr stmt
  - `return`
  - `break`
  - `continue`
  - `if` stmt
- items
  - `func`
  - `extern func`
  - `const`
  - `static`
  - `import`
  - authored `type ... = struct { ... }`
- modules

### Phase 2 — current reboot control forms

Done in the current bootstrap parser:

- `switch` stmt
- `switch` expr
- `do ... end` block expr
- canonical `loop ... while ...`
- canonical `loop ... over ...`
- domain forms:
  - `range(stop)`
  - `range(start, stop)`
  - `zip_eq(...)`
  - domain value fallback

### Phase 3 — current reboot aggregate forms

Partially done in the current bootstrap parser:

- field-based typed aggregate literals -> `SurfAgg`
- reboot array literal syntax -> `SurfArrayLit` via `[]T { ... }`
- explicit pure-choice surface via `select(cond, then_expr, else_expr)` -> `SurfSelectExpr`
- value-carrying break parsing via `break expr` -> `SurfBreakValue`
- `view(T)` type parsing -> `SurfTView`

Still open in this area:

- any richer aggregate syntactic sugar beyond explicit field form

### Phase 4 — ASDL growth first, parser second

For anything not in the current closed `Surface` family yet:

- change ASDL first
- then change grammar/spec
- then extend parser

Do **not** backsolve missing ASDL distinctions in the parser with helper flags or ad hoc tags.

---

## 5. Immediate current parser contract

The parser module should expose:

- `parse_module(text) -> SurfModule`
- `parse_item(text) -> SurfItem`
- `parse_expr(text) -> SurfExpr`
- `parse_stmt(text) -> SurfStmt`
- `parse_type(text) -> SurfTypeExpr`
- `try_parse_* -> value | nil, diag`

And the parser should also expose lexing for diagnostics/debugging:

- `lex(text) -> token_array`

---

## 6. Important early decisions

### 6.1 Preserve literal raw spelling

- `42` stays `SurfInt("42")`
- `0xff` stays `SurfInt("0xff")`
- `3.14` stays `SurfFloat("3.14")`

Interpretation belongs later.

### 6.2 Default extern symbol for bootstrap syntax

Given the current `Surface` node:

- `SurfExternFunc(name, symbol, params, result)`

and the current reboot closed grammar:

```text
extern func abs(x: i32) -> i32
```

bootstrap parser behavior should be:

- if no richer syntax is present, default `symbol = name`

That keeps the parser aligned with the current ASDL without inventing a large extern-attribute syntax prematurely.

### 6.3 Keep names unresolved

The parser should emit:

- `SurfNameRef`
- `SurfExprDot` / `SurfPlaceDot` for authored dotted syntax
- `SurfPathRef` only for explicit already-disambiguated qualified references when constructed directly
- `SurfTNamed`
- authored type items like `SurfStruct`

It should not try to resolve names during parsing.

### 6.4 Keep canonical loop structure explicit

This is now implemented in the bootstrap parser.

When loop parsing is used, it constructs:

- `SurfLoopCarryInit`
- `SurfLoopNextAssign`
- `SurfLoopWhile*`
- `SurfLoopOver*`
- `SurfDomain*`

It should not parse into mutable-local sugar and then recover loop structure later.

---

## 7. Diagnostics shape

Minimum useful bootstrap diagnostics:

- unexpected token
- unexpected end of input
- malformed type
- malformed expression
- malformed statement
- malformed item
- expected newline / expected `end`

Current bootstrap parser diagnostics now expose at least:

- `kind`
- `line`
- `column`
- short message
- source byte offsets when available

The public source facade also now exposes:

- `try_lower_*`
- `try_sem_module`
- `try_resolve_module`
- `try_back_module`
- `try_pipeline_module`
- `try_compile_module`

---

## 8. Relationship to future `Meta`

Per `QUOTING_SYSTEM_DESIGN.md`, future hosted/source quote parsing should target:

- `MoonliftMeta`

not `MoonliftSurface`.

So the right long-term split is:

- closed source parser -> `Surface`
- open quote parser -> `Meta`

The lexer and some grammar machinery can be shared.
The target layer should remain distinct.

---

## 9. Immediate extension order after bootstrap

Now that the bootstrap subset exists, the next parser work should be:

1. richer diagnostics / source span plumbing across later stages
2. aggregate and array literal coverage expansion beyond the current bootstrap forms
3. any ASDL-backed authored type/item growth
4. coherent public source facade over parse + lower + sem + later compile integration
5. later, separate `Meta` parser-hosted forms

That order matches the reboot architecture better than trying to jump straight to the old larger language surface.
