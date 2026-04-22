# Moonlift Source Span Strategy

Status: reboot source-span design and implementation strategy.

This document is for the **current reboot**.
It is grounded in the current ASDL and current parser/bootstrap work, not in `moonlift-old/`.

Companion files:

- `moonlift/REBOOT_SOURCE_SPEC.md`
- `moonlift/REBOOT_SOURCE_GRAMMAR.md`
- `moonlift/PARSER_BOOTSTRAP_PLAN.md`
- `moonlift/lua/moonlift/parse_lexer.lua`
- `moonlift/lua/moonlift/parse.lua`
- `moonlift/lua/moonlift/source_spans.lua`
- `moonlift/lua/moonlift/source.lua`

---

## 1. The central problem

Moonlift values are ASDL values.
Most of the source-layer nodes are `unique`.
That means structurally identical nodes intern to the same canonical object.

Example:

- one occurrence of `1`
- another occurrence of `1`

both become the same canonical `SurfInt("1")` value.

So this is **not** correct for spans:

```lua
spans[node] = { line = ..., col = ... }
```

Why it is wrong:

- node identity is **value identity**
- source spans are **occurrence identity**
- one canonical node may correspond to multiple source occurrences

This is the key architectural fact.

---

## 2. What source spans are and are not

Source spans are:

- diagnostic metadata
- occurrence metadata
- parser/frontend metadata

Source spans are **not**:

- semantic distinctions
- typing distinctions
- backend distinctions
- cache key semantics

So spans do not need to be forced into the core semantic ASDL just because they exist.
But they also cannot be naively keyed by interned node identity.

---

## 3. Current reboot answer: path-keyed span index

For the reboot bootstrap, the right answer is:

- keep the closed parser target as `MoonliftSurface`
- keep spans in a **parallel path-keyed index**

Current bootstrap implementation:

- `moonlift/lua/moonlift/source_spans.lua`

The span index stores spans by structural/source path strings such as:

- `module`
- `item.1`
- `func.main`
- `func.main.param.1`
- `func.main.stmt.1`
- `func.main.stmt.2.then.stmt.1`
- `func.main.stmt.3.carries.1`
- `func.main.stmt.3.next.2`

This is robust against interning because the key is:

- occurrence path in the parsed source structure

not:

- node object identity

---

## 4. Why this is a good reboot fit

A path-keyed span index fits the reboot well because:

1. the parser is already direct-to-ASDL
2. the current compiler already uses structural path strings in several lowering places
3. it does not force a giant ASDL rewrite immediately
4. it avoids corrupting interning assumptions
5. it is compatible with later richer diagnostics

---

## 5. Current bootstrap implementation state

Current implemented parser-side span support:

- lexer tokens carry:
  - line
  - col
  - offset
  - finish
- parser can now return:
  - parsed value only
  - parsed value + span index
- structured diagnostics carry:
  - `kind`
  - `line`
  - `col`
  - `message`
  - offsets when available
  - matched source path when bridged from lower-stage errors

Current public entrypoints include:

- `parse_module_with_spans`
- `parse_item_with_spans`
- `parse_expr_with_spans`
- `parse_stmt_with_spans`
- `parse_type_with_spans`

and via the public source facade:

- `pipeline_module_with_spans`
- `lower_module_with_spans`

Current bootstrap span coverage is strongest for:

- module root
- top-level items
- functions
- function params
- statement positions in function/branch/loop bodies
- loop carries
- loop next assignments
- standalone parse roots (`expr`, `stmt`, `type`, `item`, `module`)

This is intentionally a bootstrap, not full final coverage.

---

## 6. Why not attach spans to every `Surface` node right now

We could imagine changing the ASDL so that every `Surface` node carried explicit span payload.

That would solve occurrence identity cleanly.
But it would also have immediate costs:

- large ASDL rewrite
- large lowering rewrite
- likely broad test churn
- reduced interning reuse at the source layer unless carefully factored
- more pressure on every phase boundary while the reboot lower layers are still actively moving

So for the current moment, the path-index approach is the safer staging move.

---

## 7. When ASDL growth may become warranted

If later diagnostics need precise origin on every subexpression through all phases, there are two serious options:

### Option A — keep path-indexed spans and propagate origin ids

Add explicit origin-path/id fields only where needed in later layers.

For example:

- certain `Elab` binders already have stable ids
- statement paths already exist in lowering
- loop ids/port ids already exist

This lets diagnostics map later nodes back to source paths.

### Option B — add explicit occurrence wrappers in `Surface`

If the language eventually needs pervasive source-origin tracking inside the closed ASDL itself,
we could add explicit occurrence wrappers or source-annotation nodes.

That would be a larger architectural move and should happen only deliberately.

---

## 8. Recommended next propagation strategy

The recommended near-term strategy is:

### Step 1 — parser spans first

Done/started already.

- parser produces path-keyed span index
- standalone diagnostics already use parser token spans

### Step 2 — make later diagnostics speak in source paths

When lower layers produce errors, prefer reporting with stable structural ids/paths where possible.

Examples:

- `func.main.stmt.3`
- `func.main.param.2`
- `func.main.stmt.4.next.1`

### Step 3 — bridge source paths to spans in the public facade

This is now partially implemented in the reboot source facade.

Current bridge behavior in `moonlift/lua/moonlift/source.lua`:

- `try_lower_*`
- `try_sem_module`
- `try_resolve_module`
- `try_back_module`
- `try_compile_module`

attempt to:

- catch lower-stage errors
- detect structural path text in the error message when available
- look that path up in the parser span index
- return a structured diagnostic carrying:
  - stage kind
  - line/column
  - byte offsets when available
  - matched source path when available

So the public source facade can then turn:

- lower-layer path/id

into:

- source line/column/span

using the parser span index.

### Step 4 — only then decide if ASDL needs more explicit origin fields

If the path-bridge proves insufficient, grow ASDL deliberately.
Do not jump there prematurely.

---

## 9. Practical rule for current development

While lower layers are still moving quickly:

- parser owns source occurrence spans
- source facade owns span lookup helpers
- lower layers should avoid depending on hidden parser internals
- if a later layer needs a stable origin, use or introduce an explicit structural id/path, not a hidden mutable side channel

---

## 10. Summary

The key reboot conclusion is:

> Because `Surface` nodes are interned values, source spans cannot be modeled correctly as a simple `node -> span` side table.

So the current reboot strategy is:

- parse to `MoonliftSurface`
- keep spans in a **parallel path-keyed span index**
- use structural ids/paths to bridge later diagnostics back to source
- delay any large ASDL-wide span embedding until it is clearly justified

That gives Moonlift a source-span story that is honest about interning, compatible with pvm discipline, and safe to evolve while lower layers are still under active construction.
