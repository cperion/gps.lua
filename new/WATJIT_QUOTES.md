# watjit quotes

*Target design document.*

This document describes the target quote system for `watjit`: hygienic IR
quotes embedded in Lua, inspired by the role quotes play in Terra, but shaped
for `watjit`'s Lua-native builder model.

This is not a phased implementation plan. It is the target semantics and target
API.

---

## Table of contents

1. [Why watjit needs quotes](#why-watjit-needs-quotes)
2. [What a quote is](#what-a-quote-is)
3. [What quotes are not](#what-quotes-are-not)
4. [Core API target](#core-api-target)
5. [quote_expr semantics](#quote_expr-semantics)
6. [quote_block semantics](#quote_block-semantics)
7. [Hygiene](#hygiene)
8. [Why symbols matter](#why-symbols-matter)
9. [Template capture model](#template-capture-model)
10. [Splice model](#splice-model)
11. [Parameter binding rules](#parameter-binding-rules)
12. [Locals, labels, and renaming](#locals-labels-and-renaming)
13. [Relationship to wj.fn](#relationship-to-wjfn)
14. [Relationship to Lua helpers](#relationship-to-lua-helpers)
15. [Nested quote composition](#nested-quote-composition)
16. [Restrictions for the quote system](#restrictions-for-the-quote-system)
17. [Desired internal representation](#desired-internal-representation)
18. [Emitter implications](#emitter-implications)
19. [Examples](#examples)
20. [The thesis](#the-thesis)

---

## Why watjit needs quotes

`watjit` already has two useful composition mechanisms:

1. **Lua helper functions** that build staged expressions directly
2. **`wj.fn`** which builds real Wasm functions and emits real `call` instructions

These are useful, but they do not solve the full problem of hygienic staged
composition.

The missing capability is:

> treat code fragments themselves as values that can be spliced safely into
> another builder scope.

This matters because low-level helper logic is often not best understood as a
function call boundary. Many useful low-level helpers are naturally:

- an expression fragment
- a short statement block
- a probe step
- a control-flow pattern
- a reduction fragment
- a specialized store sequence
- a SIMD micro-pattern

Quotes solve that problem directly.

They provide:

- code as a value
- hygienic splicing
- inline composition by construction
- statement-level composition, not just expression-level reuse

This is why Terra quotes are so powerful. `watjit` should have the same class of
capability, even though the surface syntax will necessarily be Lua-shaped rather
than Terra-shaped.

---

## What a quote is

A `watjit` quote is a **typed IR template**.

It is built in Lua using the same builder model as `wj.fn`, but instead of
becoming a real Wasm function, it becomes a reusable hygienic template that can
be spliced into a surrounding builder scope.

There are two fundamental forms:

- **expression quote** — yields a staged value and may emit internal statements
- **block quote** — yields no value and emits statements only

Quotes are built from watjit IR, not from text.

---

## What quotes are not

Quotes are not:

- text macros
- WAT snippets
- strings containing code
- exported Wasm functions
- parser tricks
- fake C/Terra syntax pasted onto Lua

A quote should compose the real `watjit` builder IR and preserve all of:

- types
- effects
- statement order
- label structure
- hygiene

---

## Core API target

The target API should expose two first-class constructors.

### Expression quote

```lua
local mix32 = wj.quote_expr {
    params = { wj.u32 "x" },
    ret = wj.u32,
    body = function(x)
        local t = wj.u32("t", x:bxor(x:shr_u(16)))
        t(t * wj.u32(0x7feb352d))
        t(t:bxor(t:shr_u(15)))
        t(t * wj.u32(0x846ca68b))
        t(t:bxor(t:shr_u(16)))
        return t
    end,
}
```

Use:

```lua
local y = mix32(x)
```

This is a splice site, not a Wasm `call`.

### Block quote

```lua
local probe_step = wj.quote_block {
    params = {
        wj.i32 "idx",
        wj.ptr(wj.u8) "states",
        wj.i32 "EMPTY",
        wj.i32 "active",
    },
    body = function(idx, states, EMPTY, active)
        wj.if_(states[idx]:eq(EMPTY), function()
            active(0)
        end)
    end,
}
```

Use:

```lua
probe_step(idx, states, EMPTY, active)
```

This emits statements into the current builder scope.

### Zero-arg quotes

```lua
local init_hash = wj.quote_expr {
    ret = wj.u32,
    body = function()
        return wj.u32(2166136261)
    end,
}
```

Quotes should be callable like normal Lua objects.

---

## quote_expr semantics

A `quote_expr` represents a reusable expression template.

When spliced into a builder scope:

- it may emit internal statements first
- it then returns a staged `Val`

This matters because many useful inline helpers need temporary locals before
producing a final expression.

For example, an expression quote may internally:

- allocate hygienic locals
- assign intermediate values
- branch internally
- then produce the final result expression

So `quote_expr` is not restricted to a single pure expression node. It is a
statement-producing expression template.

---

## quote_block semantics

A `quote_block` represents a reusable statement template.

When spliced into a builder scope:

- it emits statements
- it returns no value

This is the natural abstraction for:

- probe steps
- update fragments
- small structured control patterns
- repeated store sequences
- specialized runtime subroutines that do not merit real function calls

---

## Hygiene

Hygiene is the central non-negotiable property of the quote system.

A quote must not accidentally capture or collide with:

- caller locals
- caller labels
- caller loop labels
- sibling quote expansions
- repeated expansions of the same quote

Example of the problem:

```lua
local q = wj.quote_expr {
    params = { wj.i32 "x" },
    ret = wj.i32,
    body = function(x)
        local t = wj.i32("t", x + 1)
        return t
    end,
}
```

If this is expanded twice in the same caller, the two internal `t` locals must
not collide.

Therefore, quote expansion must hygienically rename all internal identities.

---

## Why symbols matter

A real hygienic quote system should not fundamentally key locals and labels by
user-facing strings.

Today many builder constructs naturally look string-based:

```lua
local x = wj.i32 "x"
local t = wj.i32("t", init)
```

This is good as a **surface syntax**.

But internally, the correct representation for locals and labels should move
from:

```lua
{ op = "get", name = "t" }
```

toward something like:

```lua
{ op = "get", sym = <symbol> }
```

with declarations like:

```lua
{ sym = <symbol>, hint = "t", t = wj.i32 }
```

and labels similarly using symbol identity with a human-readable hint.

This is the key enabler for hygienic quotes.

### The rule

> User-visible names are hints. Internal identity is symbol-based.

That applies to:

- params
- locals
- labels
- any generated temporaries

---

## Template capture model

A quote is built once and stored as a template.

Creating a quote should:

1. create a special **template scope**
2. install typed param placeholders into that scope
3. run the quote body closure
4. capture the resulting:
   - parameter symbols
   - local declarations
   - statements
   - result expression (for expr quotes)

This is similar in spirit to `wj.fn` body capture, except that the result is a
template object rather than a function definition.

---

## Splice model

Calling a quote in a real builder scope performs a hygienic splice.

### For both quote types:

1. coerce actual arguments to the quote parameter types
2. bind arguments exactly once
3. clone the template IR
4. rename locals and labels hygienically
5. append cloned statements to the caller scope
6. return the cloned result expression for `quote_expr`

This is the essence of quote expansion.

---

## Parameter binding rules

Arguments to a quote must be evaluated exactly once.

That matters because quote bodies may use a parameter multiple times, and the
actual argument may be a non-trivial expression.

Example:

```lua
mix32(a + b)
```

If the quote uses its parameter multiple times, the expansion must not duplicate
`a + b` repeatedly in a way that changes evaluation order or cost model.

### Safe target rule

The splice engine should conservatively:

- create fresh temp locals for actual arguments
- assign each argument once
- substitute parameter symbols with those temp locals

Later optimizations may avoid temp locals for simple constants or `get` nodes,
but that is an optimization, not the semantic model.

---

## Locals, labels, and renaming

The splicer must clone and remap all local identities.

### Locals
Every local inside the quote gets a fresh caller-local symbol.

### Labels
Every label inside the quote gets a fresh caller-label symbol.

This includes labels created by:

- `block`
- `loop`
- `for_`
- `while_`
- any control helpers that synthesize labels

### Parameter symbols
Parameter symbols are remapped to the exactly-once bound argument temps.

This requires a general IR cloning pass with symbol substitution.

---

## Relationship to wj.fn

The distinction between quotes and functions must remain sharp.

### `wj.fn`
A `wj.fn` is:

- a real Wasm function
- emitted into the module
- callable via `call`
- exportable/importable

### `wj.quote_expr` / `wj.quote_block`
A quote is:

- a hygienic IR template
- not a Wasm function
- not emitted as its own callable function
- spliced inline into the caller

This distinction is important for clarity and performance reasoning.

### Design rule

> `wj.fn` is a runtime boundary. Quotes are a staging boundary.

---

## Relationship to Lua helpers

Today, plain Lua helper functions already provide a weak form of inline staging.

Example:

```lua
local function mix32(x)
    x = x:bxor(x:shr_u(16))
    x = x * wj.u32(0x7feb352d)
    x = x:bxor(x:shr_u(15))
    x = x * wj.u32(0x846ca68b)
    x = x:bxor(x:shr_u(16))
    return x
end
```

This is already useful and should remain useful.

But plain Lua helpers do not provide:

- hygienic local capture
- statement templates as first-class values
- label hygiene
- template reuse as explicit IR objects
- structured splicing semantics

So Lua helpers remain a convenient lightweight layer, but quotes are the real
first-class solution.

---

## Nested quote composition

Quotes should compose naturally.

### Expr inside expr

```lua
local y = mix32(x)
```

### Expr inside block

```lua
local h = wj.u32("h", init_hash())
h(hash_step(h, b))
```

### Block inside block

```lua
probe_step(idx, states, EMPTY, active)
```

### Quote inside quote
A quote body should be able to invoke another quote and have that inner quote
splice hygienically into the outer quote template.

This means quote capture itself must already respect symbol identity and avoid
string-based accidental capture.

---

## Restrictions for the quote system

A first real quote system should be intentionally disciplined.

### Disallow arbitrary ambient staged-value capture
This should be forbidden or strongly discouraged:

```lua
local outer = some_staged_value

local q = wj.quote_expr {
    body = function()
        return outer + 1
    end,
}
```

Because the meaning of captured staged values becomes ambiguous and fragile.

### Recommended rule
Quote bodies should only depend on:

- explicit quote parameters
- Lua compile-time values
- literal constants
- other quotes
- global library helpers that themselves build staged code

Not arbitrary surrounding staged locals.

### Additional reasonable restrictions for the initial design

- no recursive quote expansion model
- no multi-result quote returns initially
- no quote serialization requirement
- no separate backend textual quote format

---

## Desired internal representation

### Expression quote target representation

```lua
{
    kind = "quote_expr",
    params = { ...symbolic params... },
    ret = T,
    locals = { ...template locals... },
    body = { ...template statements... },
    result = expr_node,
}
```

### Block quote target representation

```lua
{
    kind = "quote_block",
    params = { ...symbolic params... },
    locals = { ...template locals... },
    body = { ...template statements... },
}
```

The quote object itself is callable, and call means splice.

---

## Emitter implications

The emitter does not emit quotes directly.

Quotes are expanded before emission into ordinary function-scope IR.

So the emitter continues to see:

- locals
- blocks
- loops
- branches
- stores
- expressions
- calls

The quote system is therefore a transformation and hygiene layer above the
existing emitter model, not a separate backend language.

This is important because it preserves:

- one IR
- one emitter pipeline
- one code generation path

---

## Examples

### Expression quote

```lua
local mix32 = wj.quote_expr {
    params = { wj.u32 "x" },
    ret = wj.u32,
    body = function(x)
        local t = wj.u32("t", x:bxor(x:shr_u(16)))
        t(t * wj.u32(0x7feb352d))
        t(t:bxor(t:shr_u(15)))
        t(t * wj.u32(0x846ca68b))
        t(t:bxor(t:shr_u(16)))
        return t
    end,
}

local probe = wj.fn {
    name = "probe",
    params = { wj.u32 "k" },
    ret = wj.u32,
    body = function(k)
        return mix32(k):band(wj.u32(1023))
    end,
}
```

### Block quote

```lua
local probe_step = wj.quote_block {
    params = {
        wj.i32 "idx",
        wj.ptr(wj.u8) "states",
        wj.i32 "EMPTY",
        wj.i32 "active",
    },
    body = function(idx, states, EMPTY, active)
        wj.if_(states[idx]:eq(EMPTY), function()
            active(0)
        end)
    end,
}

local loop_fn = wj.fn {
    name = "loop_fn",
    params = { wj.i32 "idx", wj.ptr(wj.u8) "states" },
    body = function(idx, states)
        local active = wj.i32("active", 1)
        probe_step(idx, states, 0, active)
    end,
}
```

### Nested quote composition

```lua
local hash_step = wj.quote_expr {
    params = { wj.u32 "h", wj.u8 "b" },
    ret = wj.u32,
    body = function(h, b)
        return (h:bxor(wj.zext(wj.u32, b))) * wj.u32(16777619)
    end,
}

local hash_bytes = wj.quote_expr {
    params = { wj.i32 "base", wj.i32 "len" },
    ret = wj.u32,
    body = function(base, len)
        local bytes = wj.view(wj.u8, base, "bytes")
        local i = wj.i32("i")
        local h = wj.u32("h", wj.u32(2166136261))
        wj.for_(i, len, function()
            h(hash_step(h, bytes[i]))
        end)
        return h
    end,
}
```

This is exactly the kind of reusable inline staged composition the quote system
should make natural.

---

## The thesis

> `watjit` quotes should be hygienic IR templates defined with Lua closures and
> spliced into the current builder scope. `quote_expr` returns a staged value and
> may emit preparatory statements; `quote_block` emits statements only. Quote
> parameters are typed placeholders, arguments are bound exactly once at splice
> sites, and template locals/labels are renamed hygienically using internal
> symbols rather than raw string names. `wj.fn` remains a real Wasm function
> boundary; quotes are the staging and inlining substrate beneath any future
> inline-call API.
