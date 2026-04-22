# Moonlift Reboot Source Spec

Status: working spec for the **current rebooted Moonlift source language**.

This document is intentionally grounded in the current reboot implementation, not in
`moonlift-old/`.

Primary source of truth:

- `moonlift/lua/moonlift/asdl.lua`

Important companion docs:

- `moonlift/REBOOT_SOURCE_GRAMMAR.md` — parser-oriented grammar for the reboot source
- `moonlift/CURRENT_IMPLEMENTATION_STATUS.md` — coded vs missing today
- `moonlift/QUOTING_SYSTEM_DESIGN.md` — future open-code / quote layer (`Meta`)

---

## 1. Purpose

The reboot parser should not lower source text directly to Cranelift-facing commands.
It should lower source text to the **current ASDL surface layer** first.

The intended closed compiler path is:

```text
text
  -> MoonliftSurface
  -> MoonliftElab
  -> MoonliftSem
  -> resolve_sem_layout
  -> MoonliftBack
  -> Rust / Cranelift
```

That means the first parser contract is:

> parse text into canonical `MoonliftSurface` ASDL values.

Not plain Lua tables.
Not ad hoc parser ASTs.
Not direct backend commands.

---

## 2. Architectural rule

For the reboot, the parser is part of the `Surface` language boundary.

So the parser should:

- use the **current reboot ASDL** as its immediate target
- preserve authored structure at the `MoonliftSurface` level
- avoid prematurely committing to `Elab`, `Sem`, or backend structure
- emit ASDL values directly so that the rest of the pipeline can stay honest

The parser may be implemented in Lua.
That is compatible with the architecture, as long as it emits canonical ASDL values.

---

## 3. Source of truth order

When deciding what the reboot source language is, use this order:

1. `moonlift/lua/moonlift/asdl.lua`
2. this spec
3. `moonlift/REBOOT_SOURCE_GRAMMAR.md`
4. actual lowering files such as:
   - `moonlift/lua/moonlift/lower_surface_to_elab.lua`
   - `moonlift/lua/moonlift/lower_surface_to_elab_expr.lua`
   - `moonlift/lua/moonlift/lower_surface_to_elab_loop.lua`
   - `moonlift/lua/moonlift/lower_surface_to_elab_top.lua`

`moonlift-old/` remains useful historical context, but it is not the reboot source of truth.

---

## 4. Current closed source layer

The current reboot already has a real closed source family:

- `MoonliftSurface`

This family currently models:

- names and paths
- scalar/pointer/function/array/slice/view/named types
- explicit places and domains
- expressions
- statements
- canonical loop forms with explicit carries, updates, and valued breaks
- top-level `func` / `extern func` / `const` / `static` / `import` / `type` items
- modules

The source parser should target those forms directly.

---

## 5. Current top-level items

The current `MoonliftSurface` supports these top-level item families:

- `func`
- `extern func`
- `const`
- `static`
- `import`
- `type`
- module packaging of those items

Current surface constructors:

- `SurfFunc`
- `SurfExternFunc`
- `SurfConst`
- `SurfStatic`
- `SurfImport`
- `SurfStruct`
- `SurfItem*`
- `SurfModule`

### 5.1 Function items

A function item carries:

- name
- params
- result type
- statement body

Parser target:

- `SurfFunc(name, params, result, body)`

### 5.2 Extern function items

An extern function item carries:

- local item name
- external symbol name
- params
- result type

Parser target:

- `SurfExternFunc(name, symbol, params, result)`

### 5.3 Constants

A constant carries:

- name
- explicit type
- value expression

Parser target:

- `SurfConst(name, ty, value)`

### 5.4 Statics

A static carries:

- name
- explicit type
- initializer expression

Parser target:

- `SurfStatic(name, ty, value)`

### 5.5 Imports

The reboot now has explicit module import items.

An import item currently carries:

- imported module path

Parser target:

- `SurfImport(path)`

Current reboot note:

- current package/module names are supplied by the host/package API rather than authored `module ...` declarations
- authored source uses `import Demo` and then qualified refs/types like `Demo.K`, `Demo.inc(...)`, `Demo.Pair`
- current imports add qualified namespaces only; they do not introduce unqualified names

### 5.6 Authored named struct types

The reboot now has authored named aggregate/type items.

A type item currently carries:

- type name
- explicit field list

Parser target:

- `SurfStruct(name, fields)`

Current reboot note:

- this is the real source of module-local named type/layout information for the closed compiler path
- later phases synthesize `ElabTypeLayout` and `SemLayoutEnv` from these items

---

## 6. Current type language

The current reboot `Surface` type family includes:

### 6.1 Scalar types

- `void`
- `bool`
- `i8`
- `i16`
- `i32`
- `i64`
- `u8`
- `u16`
- `u32`
- `u64`
- `f32`
- `f64`
- `index`

Parser targets:

- `SurfTVoid`
- `SurfTBool`
- `SurfTI8` ... `SurfTU64`
- `SurfTF32`, `SurfTF64`
- `SurfTIndex`

### 6.2 Pointer types

Pointer type:

```text
&T
```

Parser target:

- `SurfTPtr(elem)`

### 6.3 Fixed array types

Fixed array type:

```text
[count]T
```

Parser target:

- `SurfTArray(count_expr, elem_ty)`

Important current rule:
- the count remains a `Surface` expression
- later lowering constrains it to index-compatible constant-like forms

### 6.4 Slice types

Slice type:

```text
[]T
```

Parser target:

- `SurfTSlice(elem)`

### 6.5 Function types

Function type:

```text
func(T1, T2, ...) -> R
```

Parser target:

- `SurfTFunc(params, result)`

### 6.6 Named types

Named types are represented as paths.

Examples:

```text
Pair
Demo.Pair
```

Parser target:

- `SurfTNamed(SurfPath(...))`

### 6.7 `view` types

The current ASDL already contains:

- `SurfTView`

The current bootstrap reboot parser freezes the following source spelling:

```text
view(T)
```

Example:

```text
view(i32)
```

Parser target:

- `SurfTView(elem)`

---

## 7. Current expression language

The current reboot `Surface` expression family includes:

### 7.1 Literals

- integer literals
- float literals
- boolean literals
- `nil`

Parser targets:

- `SurfInt(raw)`
- `SurfFloat(raw)`
- `SurfBool(value)`
- `SurfNil`

Important parser rule:

- integer and float literals should preserve their **raw source spelling** in `Surface`
- numeric interpretation belongs later

### 7.2 Name and path references

Examples:

```text
x
helper
Demo.K
Demo.helper
pair.left
```

Parser targets:

- single identifier -> `SurfNameRef`
- authored dotted value syntax -> nested `SurfExprDot(...)`
- explicit already-disambiguated qualified references may still be represented as `SurfPathRef(SurfPath(...))`

Important current reboot rule:

- authored dot syntax is preserved first and resolved later
- if the head of a dotted chain resolves as a local/runtime value binding, lowering treats the chain as value-field projection
- otherwise lowering may resolve the chain as a qualified binding path

### 7.3 Unary expressions

Current unary expression family:

- numeric negation
- logical not
- bitwise not
- address-of
- dereference

Parser targets:

- `SurfExprNeg`
- `SurfExprNot`
- `SurfExprBNot`
- `SurfExprRef`
- `SurfExprDeref`

Important parser rule:

- `&x` must parse through an lvalue/place path and emit `SurfExprRef(place)`
- `*p` emits `SurfExprDeref(expr)`

### 7.4 Binary expressions

Current binary expression family includes:

- arithmetic: `+ - * / %`
- comparisons: `== ~= < <= > >=`
- logical: `and or`
- bitwise: `& | ~ << >> >>>`

Parser targets are the corresponding `SurfExpr*` binary nodes.

### 7.5 Cast family

Current cast-family surface nodes include:

- `cast<T>(x)`
- `trunc<T>(x)`
- `zext<T>(x)`
- `sext<T>(x)`
- `bitcast<T>(x)`
- `satcast<T>(x)`

Parser targets:

- `SurfExprCastTo`
- `SurfExprTruncTo`
- `SurfExprZExtTo`
- `SurfExprSExtTo`
- `SurfExprBitcastTo`
- `SurfExprSatCastTo`

### 7.6 Intrinsic calls

Current intrinsic surface family includes:

- `popcount`
- `clz`
- `ctz`
- `rotl`
- `rotr`
- `bswap`
- `fma`
- `sqrt`
- `abs`
- `floor`
- `ceil`
- `trunc_float`
- `round`
- `trap`
- `assume`

Parser target:

- `SurfExprIntrinsicCall(op, args)`

### 7.7 Calls, field access, indexing

Current postfix expression family includes:

- call
- authored dot projection
- index projection

Parser targets:

- `SurfCall(callee, args)`
- `SurfExprDot(base, name)`
- `SurfIndex(base, index)`

Later lowering resolves `SurfExprDot` either to:

- qualified binding lookup
- field projection

### 7.8 Aggregate literals

The current surface supports typed field-based aggregate literals:

- `SurfAgg(ty, field_inits)`

The reboot spec blesses field-based aggregate syntax of the form:

```text
TypeName { field = expr, other = expr }
```

Parser target:

- `SurfAgg(ty, fields)`

### 7.9 Array literals

The current ASDL includes:

- `SurfArrayLit(elem_ty, elems)`

The current bootstrap reboot parser freezes the following source spelling:

```text
[]T { e1, e2, e3 }
```

Examples:

```text
[]i32 { 1, 2, 3 }
[]f64 { x, y, z }
```

Parser target:

- `SurfArrayLit(elem_ty, elems)`

Important current note:

- the literal records element type and element expressions only
- array extent is currently inferred from element count at later lowering
- if we later want source-visible declared extent on array literals, the `Surface` ASDL should grow explicitly for it

### 7.10 `if` expressions

Current parser target:

- `SurfIfExpr(cond, then_expr, else_expr)`

This is a pure expression form.
If branch-local statements are needed, they should be expressed through block expressions.

### 7.11 `select` expressions

The current ASDL includes:

- `SurfSelectExpr`

The current bootstrap reboot parser freezes the following explicit surface spelling:

```text
select(cond, then_expr, else_expr)
```

Example:

```text
select(flag, x, y)
```

Parser target:

- `SurfSelectExpr(cond, then_expr, else_expr)`

This is the explicit pure-choice form that stays distinct from statement-shaped `if` and from expression-shaped `if`.

### 7.12 `switch` expressions

Current parser target:

- `SurfSwitchExpr(value, arms, default_expr)`

Each arm structurally contains:

- a key expression
- zero or more statements
- one result expression

This means reboot `switch` expression arms are expression-block-shaped, not merely single raw expressions.

### 7.13 Block expressions

Current parser target:

- `SurfBlockExpr(stmts, result)`

The reboot block expression is best understood as:

- zero or more statements
- then one required result expression

This matches the current `Surface` representation directly.

### 7.14 Loop expressions

Current parser target:

- `SurfLoopExprNode(loop)`

Loop expressions use the canonical loop families described below.

---

## 8. Current statement language

The current reboot `Surface` statement family includes:

- `let`
- `var`
- `set`
- expr statement
- `if`
- `switch`
- `return`
- `break`
- `continue`
- loop statement

### 8.1 `let`

Parser target:

- `SurfLet(name, ty, init)`

Current reboot rule:

- local `let` bindings are explicitly typed in `Surface`

### 8.2 `var`

Parser target:

- `SurfVar(name, ty, init)`

Current reboot rule:

- local `var` bindings are explicitly typed in `Surface`

### 8.3 Assignment / set

Parser target:

- `SurfSet(place, value)`

The parser must lower assignable syntax into `SurfPlace`:

- `SurfPlaceName`
- `SurfPlacePath`
- `SurfPlaceDeref`
- `SurfPlaceDot`
- `SurfPlaceField`
- `SurfPlaceIndex`

Authored dotted place syntax is preserved first as `SurfPlaceDot` and then resolved later either as:

- qualified binding lookup
- field place projection

### 8.4 Expression statement

Parser target:

- `SurfExprStmt(expr)`

### 8.5 `if` statement

Parser target:

- `SurfIf(cond, then_body, else_body)`

`elseif` chains may parse as nested `SurfIf` in the else-body.

### 8.6 `switch` statement

Parser target:

- `SurfSwitch(value, arms, default_body)`

### 8.7 Return

Parser targets:

- `SurfReturnVoid`
- `SurfReturnValue(expr)`

### 8.8 Break / continue

Parser targets:

- `SurfBreak`
- `SurfBreakValue`
- `SurfContinue`

Current bootstrap reboot parser spelling:

```text
break
break expr
continue
```

This means:

- bare `break` -> `SurfBreak`
- `break expr` -> `SurfBreakValue(expr)`

### 8.9 Loop statements

Parser target:

- `SurfLoopStmtNode(loop)`

---

## 9. Canonical reboot loop forms

The reboot `Surface` does **not** currently have separate plain `while` / `for` AST nodes.
Its loop surface is already centered on canonical loop forms.

That means the reboot parser should primarily target:

- `loop ... while ...`
- `loop ... over ...`

not a separate old-style `while_` / `for_` source AST.

### 9.1 Loop carries

Current carry node:

- `SurfLoopCarryInit(name, ty, init)`

Carries are explicit in the surface layer.
They are not inferred from mutation after parsing.

### 9.2 Loop next updates

Current update node:

- `SurfLoopNextAssign(name, value)`

`next` is explicit structure in the source representation.

### 9.3 `loop ... while ...`

Current parser targets:

- `SurfLoopWhileStmt`
- `SurfLoopWhileExpr`

This is the reboot phi/state loop form.

### 9.4 `loop ... over ...`

Current parser targets:

- `SurfLoopOverStmt`
- `SurfLoopOverExpr`

This is the reboot domain loop form.

### 9.5 Domains

Current domain nodes:

- `SurfDomainRange(stop)`
- `SurfDomainRange2(start, stop)`
- `SurfDomainZipEq(values)`
- `SurfDomainValue(value)`

The parser should preserve these domain distinctions at the `Surface` level.

---

## 10. Names, paths, and environments

The parser only builds source names and paths.
It does **not** resolve them.

Resolution happens later through environments such as:

- `ElabEnv.values`
- `ElabEnv.types`
- `ElabEnv.layouts`

So the parser’s job is:

- preserve identifier spelling
- preserve dotted path shape
- preserve type-vs-value syntactic context

not to decide meaning early.

---

## 11. Current parser contract

The first reboot parser should be:

- fast
- Lua-based if convenient
- direct-to-ASDL
- closed-language-first

Recommended contract:

- `parse_module(text) -> SurfModule`
- `parse_item(text) -> SurfItem`
- `parse_expr(text) -> SurfExpr`
- `parse_stmt(text) -> SurfStmt`
- `parse_type(text) -> SurfTypeExpr`
- `try_parse_* -> value | nil, diag`

Current public reboot helper layer also now exists at:

- `moonlift/lua/moonlift/source.lua`

This facade currently exposes:

- parse helpers
- try-parse helpers with structured diagnostics
- `parse -> Surface -> Elab`
- `parse -> Surface -> Elab -> Sem`

Important implementation preference:

- direct constructor calls like `Surf.SurfExprAdd(...)`
- preserve raw numeric spelling
- avoid building an intermediate plain-table AST

---

## 12. Future quote / open-code relation

Per `moonlift/QUOTING_SYSTEM_DESIGN.md`:

- the **closed** parser target is `MoonliftSurface`
- future quote/parser-hosted open-code forms should target `MoonliftMeta`, not `Surface`

So the reboot should eventually have:

```text
closed source text  -> Surface
open quote text     -> Meta
```

The lexer and much of the grammar machinery may be shared.
The target ASDL layer should differ.

---

## 13. What is intentionally not specified yet

The reboot source spec intentionally does **not** yet freeze text syntax for everything present in old Moonlift or future Moonlift.

Not yet frozen here:

- hosted/public policy for when `view(T)` should be preferred over slice/pointer forms
- full authored type-item syntax:
  - `type`
  - `struct`
  - `union`
  - `tagged union`
  - `enum`
  - `opaque`
- method / `impl` syntax
- visibility / attributes / imports
- quote/meta source syntax

Those need either:

- corresponding `Surface` growth first, or
- explicit reboot design decisions before parser commitment

---

## 14. Summary

The reboot parser should start from the current ASDL, not from nostalgia.

That means:

- parse text to `MoonliftSurface`
- keep the parser ASDL-first
- keep canonical loop structure explicit
- keep names unresolved until `Elab`
- treat `moonlift-old/` as history, not law
- use the new quote design later for `Meta`, not as a reason to muddy the closed parser now
