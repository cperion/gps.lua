# Moonlift Naming Decisions

Status: canonical naming rationale for the Moonlift source frontend, quote frontend, and builder-layer terminology.

This document exists to prevent Moonlift from drifting into:

- Terra naming
- duplicated host/source spellings like `ml.fn[[ fn ... ]]`
- confusing overlap between parser APIs and builder APIs

---

## 1. Core principle

Moonlift should feel like:

> a Moonlift-native language hosted by Lua

not:

> a Lua wrapper pretending to be Terra

That means naming must do three things:

1. avoid Terra branding
2. avoid redundant syntax
3. make the host/source boundary obvious

---

## 2. Canonical naming decisions

### 2.1 Host entry points

Canonical host parser entry points:

- `ml.code[[ ... ]]`
- `ml.module[[ ... ]]`
- `ml.expr[[ ... ]]`
- `ml.type[[ ... ]]`
- `ml.extern[[ ... ]]`
- `ml.cimport[[ ... ]]`

Canonical quote entry points:

- `ml.quote.func[[ ... ]]`
- `ml.quote.expr[[ ... ]]`
- `ml.quote.block[[ ... ]]`
- `ml.quote.type[[ ... ]]`
- `ml.quote.module[[ ... ]]`

Canonical builder-layer names:

- `func`
- `module`
- `let`
- `var`
- `block`
- `while_`
- `switch_`
- `quote`
- `quote_expr`
- `quote_block`
- `hole`

### 2.2 Source-language keywords

Canonical source item/function introducer:

- `func`

Canonical extern introducer:

- `extern func`

Canonical function-type syntax:

- `func(T1, T2, ...) -> R`

Examples:

```lua
local add = ml.code[[
func add(a: i32, b: i32) -> i32
    return a + b
end
]]
```

```text
extern func abs(x: i32) -> i32
```

```text
func(i32, i32) -> i32
```

---

## 3. Why `ml.code` is the canonical host entry point

`ml.code[[ ... ]]` is preferred over the obvious alternatives because it cleanly names what the host is doing:

- it is giving Moonlift source code to the frontend
- it does not repeat the inner item kind
- it does not imply a parser implementation detail
- it works for any single top-level item, not only functions

### Good

```lua
ml.code[[
func add(a: i32, b: i32) -> i32
    return a + b
end
]]
```

### Bad

```lua
ml.fn[[
fn add(a: i32, b: i32) -> i32
    return a + b
end
]]
```

The bad version is redundant twice:

- `ml.fn`
- `fn`

and it also imports non-Moonlift flavor.

---

## 4. Why `func` is the canonical source keyword

`func` is preferred because it is:

- already aligned with Moonlift's current builder DSL
- clearer than `fn`
- shorter than `function`
- less Python/Lua-generic than `def`
- more systems-language neutral than borrowing a Rust/Terra feel

### Ranking

Preferred source spellings:

1. `func`
2. `function` (acceptable but too verbose)
3. `def` (acceptable but wrong tone)
4. `fn` (rejected as canonical Moonlift syntax)

---

## 5. Rejected host entry point names

### 5.1 `ml.fn`
Rejected because it duplicates the inner function introducer and makes the surface feel borrowed.

### 5.2 `ml.func`
Rejected as the canonical parser entry point because it still tends to duplicate the inner function/item introducer:

```lua
ml.func[[
func add(...)
end
]]
```

This is better than `ml.fn`, but still noisy.

### 5.3 `ml.parse`
Rejected as the canonical name because it exposes the mechanism instead of the language surface.

It says:

- “call the parser”

rather than:

- “this is Moonlift code”

`ml.parse` is acceptable as an implementation helper or debug API, but not as the primary user surface.

### 5.4 `ml.source`
`ml.source` is a reasonable alias candidate, but `ml.code` is preferred because:

- it is slightly shorter
- it reads naturally in Lua
- it maps cleanly to “give Moonlift code to the frontend”

If desired, `ml.source` may exist as an alias for `ml.code`, but the spec should only bless one canonical name.

---

## 6. Rejected source keyword names

### 6.1 `fn`
Rejected because it gives Moonlift the wrong accent.

It suggests:

- Rust-like shorthand
- Terra adjacency
- a copied embedded-language style

Moonlift should sound like itself.

### 6.2 `function`
Rejected as canonical because it is too verbose for a low-level staged language and too close to raw Lua surface syntax.

### 6.3 `def`
Rejected as canonical because it pushes the surface toward a scripting-language tone rather than a low-level compiler-language tone.

---

## 7. Naming split by layer

This split is intentional and should be preserved.

### 7.1 Host parser layer
The host names tell you what kind of fragment is being parsed:

- `code`
- `module`
- `expr`
- `type`
- `extern`
- `cimport`

### 7.2 Source language layer
The source names tell you what the language item is:

- `func`
- `struct`
- `union`
- `tagged union`
- `enum`
- `impl`
- `extern`

### 7.3 Builder layer
The builder names stay close to the existing implementation surface:

- `func(...)`
- `let(...)`
- `var(...)`
- `block(...)`
- `quote(...)`

This means the user can always tell whether they are:

- parsing Moonlift source
- writing Moonlift source
- building Moonlift IR directly

---

## 8. Quote naming

Quotes should follow the same source-level terminology.

Canonical quote forms:

- `ml.quote.func[[ ... ]]`
- `ml.quote.expr[[ ... ]]`
- `ml.quote.block[[ ... ]]`
- `ml.quote.type[[ ... ]]`
- `ml.quote.module[[ ... ]]`

Why not `ml.quote.code`?

Because quotes are typed fragments, and fragment kind matters more there:

- expression quote
- block quote
- function quote
- module quote

At the quote layer, being explicit about fragment kind is useful, not redundant.

---

## 9. Short aliases

Short aliases are acceptable, but they should be clearly secondary.

Possible optional aliases:

- `ml.source = ml.code`
- `ml.q = ml.quote`

Not recommended as canonical:

- `ml.f`
- `ml.fn`
- `ml.p`

If aliases exist, docs and examples should still use the canonical names.

---

## 10. Naming conventions for future features

Apply the same rules to future APIs.

### 10.1 Good future names

- `ml.layout[[ ... ]]`
- `ml.asm[[ ... ]]`
- `ml.intrinsic[[ ... ]]`
- `ml.target[[ ... ]]`

### 10.2 Bad future names

- Terra-derived names
- parser-mechanism names as the public face
- doubled host/source names

Examples of bad forms:

- `ml.func[[ func ... ]]`
- `ml.type[[ type ... ]]` if the inside also redundantly requires a wrapper item when parsing a fragment
- `ml.parser[[ ... ]]`

---

## 11. Canonical examples

### Single item

```lua
local add = ml.code[[
func add(a: i32, b: i32) -> i32
    return a + b
end
]]
```

### Module

```lua
local mathx = ml.module[[
struct Vec2
    x: f32
    y: f32
end

func dot(a: &Vec2, b: &Vec2) -> f32
    return a.x * b.x + a.y * b.y
end
]]
```

### Function quote

```lua
local plus_one = ml.quote.func[[
func (x: i32) -> i32
    return x + 1
end
]]
```

### Extern declaration

```lua
local libc_abs = ml.extern[[
extern func abs(x: i32) -> i32
]]
```

---

## 12. Final decision summary

Canonical Moonlift naming is:

- host parser entrypoint: `ml.code`
- source function keyword: `func`
- extern function spelling: `extern func`
- function type spelling: `func(...) -> T`
- quote function entrypoint: `ml.quote.func`

Rejected as canonical:

- `ml.fn`
- `fn`
- Terra-derived naming
- duplicated host/source spellings

That naming split gives Moonlift a cleaner voice and keeps the surface from feeling borrowed.
