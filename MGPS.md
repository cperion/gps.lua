# mgps

> **Note:** The repository runtime has now converged on the flat-command `gps`
> architecture in `init.lua`. This document remains useful as historical design
> context for the older `emit/state/compose` direction, but it no longer
> describes the canonical public API.

A ground-up redesign of GPS around one refined insight:

> Runtime still decomposes into **gen / param / state**.
> But compilation must classify authored distinctions into **code shape / state shape / payload**.

In plain terms:

- `gen` is the code to run
- `param` is the residual authored payload
- `state` is the mutable retained runtime data

This document describes what `mgps` should be if redesigned from the start, not patched incrementally.

It is intentionally expansive. The goal is to make the architecture precise enough that implementation follows from it rather than inventing itself ad hoc.

---

# 1. The Central Thesis

The original GPS insight remains true:

- **gen** — the code that runs
- **param** — residual payload the code reads
- **state** — mutable runtime data the code owns

A function is a collapsed machine.
A closure is a machine with hidden param.
An object is a machine with hidden everything.
A Lua iterator reveals the decomposition unusually clearly.

That part does not change.

What changes is our understanding of **lowering**.

The refined insight is:

> A lowering is not only a transformation.
> It is first a **classification problem**.

For every distinction in the input, the lowering must determine whether changing it:

- changes the **compiled code**
- changes the **runtime state layout / ownership / allocation / initialization**
- changes only the **residual payload**
- or means the field should not still exist at this boundary

That yields the new compiler discipline.

---

# 2. Runtime Roles vs Boundary Sensitivities

This distinction is the heart of `mgps`.

## Runtime roles

Every running machine still has exactly three runtime roles:

- **gen** — code to run
- **param** — residual payload
- **state** — retained mutable data

That is execution.

## Boundary sensitivities

But fields at a compilation boundary are not classified directly by runtime role. They are classified by **what changing them invalidates**:

- **code-shaping** — changing it changes the compiled code
- **state-shaping** — changing it changes runtime state layout, ownership, allocation, or initialization strategy
- **payload** — changing it only changes residual data read by the code
- **dead / misplaced** — it should not still be present here

This is the key refinement.

A field can be **state-shaping** without becoming mutable runtime state itself.
It may only determine how runtime state is declared or allocated.

Examples:

- `FilterMode = LowPass | HighPass` is code-shaping
- `freq = 2000` is payload in a typical biquad terminal
- `glyph_cap = 256` is state-shaping for a text backend
- `canvas_w = 1024` is state-shaping for a canvas resource
- `theme_name = "warning"` at a render backend terminal is probably dead or misplaced

So:

> Runtime roles describe **what execution is**.
> Boundary sensitivities describe **what compilation must preserve**.

---

# 3. The Primary Promise of mgps

The primary promise of `mgps` is the same kind of promise original GPS made:

> The user should not manually invent keys.
> The structure should already know enough.

So `mgps` must remain:

- **ASDL-first**
- **structural**
- **keyless in public API**

Users should express:

- source structure in ASDL
- lowerings
- structural state declarations
- payload extraction

The framework should derive automatically:

- code identity
- state identity
- reusable compiled families
- composition identity
- hot-swap behavior

The user should **not** write:

- `gen_key`
- `state_key`
- cache-key strings
- manual family IDs
- ad hoc shape hashes

Those are framework mechanics.

---

# 4. The ASDL Is Still the Architecture

This must not change.

The original GPS insight that the **GPS tree is the ASDL tree** remains central.

`mgps` is not a runtime-only machine library. It is a compiler architecture whose topology should still come from schema structure.

That means:

- **sum types** define dispatch points
- **containment** defines structural composition
- **structural interning** gives identity for memoization
- **leaf compilers** remain the main user-written logic

The framework should still be able to auto-wire most of the tree from:

```lua
local M = require("mgps")

local T = M.context("paint")
    :Define [[
        module View {
            Frame = (Node* nodes) unique
            Node = Rect(number x, number y, number w, number h, number rgba8) unique
                 | Text(number x, number y, number font_id, number rgba8, string text) unique
        }
    ]]
```

Users should still mostly write methods on leaf variants, such as:

```lua
function T.View.Rect:paint(env) ... end
function T.View.Text:paint(env) ... end
```

Everything else should still be inferred where possible.

---

# 5. What the ASDL Knows Automatically

The ASDL still provides the first and strongest structural information.

## Sum types

Sum types are still the best default marker of **code shape**.

If you have:

```text
Device = Osc(number hz)
       | Filter(FilterMode mode, number freq, number q)
       | Gain(number db)
```

then:

- `Osc | Filter | Gain` are code-shaping
- nested `FilterMode = LowPass | HighPass | BandPass` is also code-shaping

The schema tells us that directly.

## Scalars

Scalars are no longer all naively treated as “param”.
They must be classified by lowering into:

- payload
- state-shaping

Examples:

- `freq`, `q`, `db` might become payload
- `glyph_cap`, `sprite_cap`, `canvas_w`, `canvas_h` are state-shaping

So the corrected doctrine is:

> Sum types usually identify code shape.
> Lowerings must finish classification by splitting surviving scalars into payload and state shape.

This is how we preserve the original ASDL genius without overclaiming that the schema alone settles every question.

---

# 6. The Public Primitive: emit

The public primitive result of a lowering should be:

```lua
M.emit(gen, state_decl, param)
```

This is the center of the new design.

It says:

- here is the **rule**
- here is the **structural state declaration**
- here is the **payload**

No keys.
No explicit family objects in user code.
No manual currying ceremony.

`M.emit(...)` is the public replacement for the old idea of returning a fully collapsed machine.

It is intentionally direct and literal.

## Why `emit` is right

Because it is exactly what a leaf lowering should conceptually produce:

- a fixed rule family
- an explicit declaration of what state that rule needs
- the residual stable data

The framework can then internally separate:

- reusable family
- bound payload

without exposing that split.

---

# 7. Structural State Declarations

This is the most important addition in `mgps`.

For state-shaping distinctions to remain structural, `state` must first exist as a **declaration language**, not only as opaque allocation functions.

So `mgps` needs a `state` algebra.

## Proposed state API

```lua
M.state.none()
M.state.ffi(ctype, opts?)
M.state.record(name, fields)
M.state.product(name, children)
M.state.array(of_decl, n)
M.state.resource(kind, spec)
```

These should return structural state declarations.

### `M.state.none()`
For stateless machines.

### `M.state.ffi(ctype, opts?)`
For FFI-backed plain data state.
Still structural because the ctype becomes part of the declaration.

### `M.state.record(name, fields)`
For explicit structured state.
Useful for backend-independent declarations.

### `M.state.product(name, children)`
For composed state across child machines.
This is how structural composition remains honest.

### `M.state.array(of_decl, n)`
For regular repeated state families.

### `M.state.resource(kind, spec)`
For retained backend-owned resources like:

- `TextBlob`
- `SpriteBatch`
- `Canvas`
- `Mesh`

This is critical for UI/render backends.

## Examples

### Oscillator

```lua
M.state.ffi("struct { double phase; }")
```

### Filter state

```lua
M.state.record("BiquadState", {
    x1 = M.state.f64(),
    x2 = M.state.f64(),
    y1 = M.state.f64(),
    y2 = M.state.f64(),
})
```

### Text resource

```lua
M.state.resource("TextBlob", {
    cap = 256,
    font_id = 3,
})
```

### Composed child state

```lua
M.state.product("ChainState", {
    state_a,
    state_b,
    state_c,
})
```

The point is not syntax fetishism. The point is that state-shaping facts must become **structural data**.

That is what lets `mgps` infer state identity automatically.

---

# 8. Internal Reality: Family and Binding

Although the public API stays keyless, internally `mgps` should still split the emitted result.

This split is real and necessary.

## Public emitted term

Conceptually, a lowering returns:

```lua
Emit = {
    gen = ...,
    state_decl = ...,
    param = ...,
}
```

## Internal family

From that, `mgps` derives an internal reusable family:

```lua
Family = {
    gen = ...,
    state_layout = realize(state_decl),
    code_shape = ...,
    state_shape = ...,
}
```

## Internal bound result

And then binds payload:

```lua
Bound = {
    family = Family,
    param = ...,
}
```

This is the internal form of currying.

The important design point is:

> `mgps` still needs the split, but users do not need to manage the split explicitly.

So the system keeps the power of currying while hiding its ceremony.

---

# 9. Leaf Compilers

Leaf compilers remain the main user-written logic.

`mgps` should provide two principal forms.

## 9.1 Simple leaf

The common case:

```lua
M.leaf(gen, state_fn, param_fn)
```

Where:

- `gen` is fixed
- `state_fn(node, ...) -> state_decl`
- `param_fn(node, ...) -> param`

### Example

```lua
local Osc = M.leaf(
    osc_gen,
    function(node, sr)
        return M.state.ffi("struct { double phase; }")
    end,
    function(node, sr)
        return { phase_inc = node.hz / sr }
    end
)
```

Then:

```lua
function T.Source.Osc:compile(sr)
    return Osc(self, sr)
end
```

No keys.
No family plumbing.
Still fully structural.

## 9.2 Classified variant leaf

For more advanced cases where state shape depends on classified scalar data:

```lua
M.variant{
    classify = function(node, ...) ... end,
    gen = function(shape, ...) ... end,
    state = function(shape, ...) ... end,
    param = function(node, shape, ...) ... end,
}
```

This is the pure form of the new lowering discipline.

### Why this helper matters

Because not all leaves are “fixed gen + fixed state”.

A UI backend text node is the classic example:

- code family may be fixed
- state shape depends on capacity bucket / font family / resource class
- payload is the actual text and draw position

### Example

```lua
local PaintText = M.variant{
    classify = function(node, fonts)
        return {
            cap = next_power_of_two(#node.text),
            font_id = node.font_id,
        }
    end,

    gen = function(shape, fonts)
        return draw_text_gen
    end,

    state = function(shape, fonts)
        return M.state.resource("TextBlob", {
            cap = shape.cap,
            font_id = shape.font_id,
        })
    end,

    param = function(node, shape, fonts)
        return {
            text = node.text,
            x = node.x,
            y = node.y,
            color = node.rgba8,
            font = fonts[shape.font_id],
        }
    end,
}
```

This is exactly the new theory in code:

1. classify
2. choose gen
3. declare state
4. extract payload

Still keyless.

---

# 10. Sum Dispatch: match

`mgps` must retain the original dispatch elegance.

The user should still be able to write:

```lua
local paint_node = M.match{
    Rect = PaintRect,
    Text = PaintText,
    Image = PaintImage,
}
```

This remains one of the best ideas in GPS:

- ASDL sum types define code-shaping choice
- dispatch follows schema structure
- variant arms are the true local compilers

`M.match` should therefore remain central and high-level.

It should simply return an emitted result.

No keys.
No explicit family objects.
No change to the user’s architectural mental model.

---

# 11. Containment and Composition

The other half of “the GPS tree is the ASDL tree” is containment.

If a product type contains `Child*`, then the framework should still know that child compilers must be mapped and structurally composed.

So `mgps` should retain structural composition either explicitly or through context auto-wiring.

## Public composition helper

```lua
M.compose(children, body_fn?)
```

This should accept emitted child results and produce a new emitted result.

Internally it should:

1. compose child `gen`s into a parent `gen`
2. compose child `state_decl`s into a parent `state_decl`
3. package child payloads into a parent payload

Conceptually:

```lua
M.emit(
    composed_gen,
    M.state.product("Compose", child_state_decls),
    child_params
)
```

This is exactly how composition remains faithful to the runtime decomposition while also preserving state identity automatically.

## Why composition remains powerful

The outer `gen` still directly calls inner `gen`s.
There is still no need for intermediate buffers or materialized command arrays unless a phase intentionally produces them.

So the original fusion story survives.

In fact it becomes cleaner:

- code shape composes structurally
- state shape composes structurally
- payload composes by product

Three roles, three composition laws.

---

# 12. context: Auto-Wiring the ASDL Tree

`M.context()` should remain the primary entry point.

It should still do the heavy lifting that made original GPS elegant.

## Responsibilities of `M.context()`

### Sum-type wiring
For each sum type, create a memoized dispatch boundary around the relevant verb.

### Containment wiring
For each product type with child lists, generate default structural composition over child compilers.

### Module installation
Allow users to install leaf compilers in modules:

```lua
return function(T, M)
    function T.View.Rect:paint(env) ... end
    function T.View.Text:paint(env) ... end
end
```

That module pattern should stay.

The key property is unchanged:

> the framework should derive the compiler topology from the schema,
> not require the user to rebuild it manually.

---

# 13. lower: Memoized Structural Boundaries

`M.lower(name, fn)` remains the single boundary primitive.

Publicly, it should feel almost identical to the old one.

```lua
local compile_text = M.lower("compile_text", function(node, env)
    ...
    return M.emit(gen, state_decl, param)
end)
```

## What it should cache

### L1: node identity
Same as old GPS.
If the exact same interned node is seen again, reuse the full result instantly.

### L2: derived family shape
But now L2 should be derived from structure, not user-facing keys.

Internally, `mgps` should project the emitted result into:

- **code shape projection**
- **state shape projection**

and cache the reusable family from that.

Payload is then rebound freshly.

This is the internal currying split.

## Why this matters

This gives exactly the behavior we want:

- payload-only change → reuse family, rebind payload
- state-shaping change → preserve code family if possible, replace state family
- code-shaping change → replace everything

But it remains hidden behind a clean structural boundary API.

---

# 14. slot: Runtime Installation

`M.slot()` remains the installed runtime holder.

Publicly:

```lua
local slot = M.slot()
slot:update(compiled)
slot.callback(...)
```

That should still work.

## Internal semantics

A slot now compares internal family identity derived from:

- code shape
- state shape

### Cases

#### Same family
- keep live state
- replace payload only

#### Same code shape, different state shape
- replace live state
- possibly reuse code family

#### Different code shape
- replace all

Again, the key point:

> these comparisons should be structural and automatic,
> not a user-visible key protocol.

---

# 15. report: Diagnostics

`M.report(...)` should surface the new distinctions clearly.

The old diagnostics only showed node hits and gen reuse.
That is no longer enough.

`mgps` should expose at least:

- node hits
- code-family reuse
- state-family reuse
- payload-only changes

Example conceptual output:

```text
paint_text        calls=850  node_hits=847  code_reuse=100%  state_reuse=92%
paint_rect        calls=850  node_hits=849  code_reuse=100%  state_reuse=100%
```

This directly reflects the new boundary classification.

---

# 16. The UI Example: Why mgps Exists

The refined design becomes most obvious in UI/rendering.

## Old simplified story
The old GPS story often looked like:

- same `gen` means keep state
- different `gen` means rebuild state

That works well for simple DSP leaves.

## UI exposes the missing distinction

For a text node:

- changing text content may only change payload
- changing text capacity bucket changes backend state layout
- changing primitive family changes code shape

Similarly for canvases:

- clear color is payload
- width/height/MSAA are state-shaping
- switching pass kind is code-shaping

So UI reveals that the compiler must classify more finely.

This is not a failure of GPS.
It is GPS becoming more precise.

`mgps` is GPS rebuilt around that precision.

---

# 17. Example: Tiny View Backend

## Schema

```lua
local T = M.context("paint")
    :Define [[
        module View {
            Frame = (Node* nodes) unique
            Node = Rect(number x, number y, number w, number h, number rgba8) unique
                 | Text(number x, number y, number font_id, number rgba8, string text) unique
        }
    ]]
```

## Rect leaf

```lua
function T.View.Rect:paint()
    return M.emit(
        rect_fill_gen,
        M.state.none(),
        {
            x = self.x,
            y = self.y,
            w = self.w,
            h = self.h,
            rgba8 = self.rgba8,
        }
    )
end
```

### Classification

- code shape: `Rect`
- state shape: none
- payload: geometry and color

## Text leaf

```lua
function T.View.Text:paint(fonts)
    local cap = next_power_of_two(#self.text)

    return M.emit(
        draw_text_gen,
        M.state.resource("TextBlob", {
            cap = cap,
            font_id = self.font_id,
        }),
        {
            x = self.x,
            y = self.y,
            text = self.text,
            rgba8 = self.rgba8,
            font = fonts[self.font_id],
        }
    )
end
```

### Classification

- code shape: `Text`
- state shape: `TextBlob(cap, font_id)`
- payload: x/y/text/color/font object

The framework should infer all reuse behavior from this structure.

---

# 18. What mgps Intentionally Does Not Expose

To preserve the original GPS genius, `mgps` should not expose these as ordinary user concepts:

- `gen_key`
- `state_key`
- explicit family hashes
- manual cache-key functions
- slot equality hooks
- custom shape-string generation

Those may exist internally.
They should not be the way users talk to the framework.

The user should instead expose more structure:

- in the ASDL
- in the state declaration
- in the lowering shape

Then the framework computes what it needs.

That is the GPS way.

---

# 19. Currying: Internal but Real

A subtle point.

Do we still need currying?

## Publicly
Not necessarily.
Users do not need to manually create families and bind payloads.

## Internally
Absolutely.

`mgps` still needs to split:

- reusable compiled family
- bound payload

That split is what enables:

- family reuse across payload changes
- correct state replacement when state shape changes
- hot swap with payload rebinding

So `mgps` should keep currying as an **internal implementation truth** while exposing a seamless direct API like `M.emit(...)`.

This is the best of both worlds:

- conceptual honesty
- public simplicity

---

# 20. Why This Is Better Than Patched GPS

A patched `gps.lua` tends to drift toward:

- explicit `gen_key`
- explicit `state_key`
- surface-level key mechanics

That is useful as an intermediate step.
But it leaks framework internals into user space.

`mgps` should avoid that by redesigning around structural declarations from the start.

So instead of saying:

> tell me your keys

`mgps` says:

> tell me your structure

That is much closer to original GPS.

---

# 21. The Full Public API Proposal

This is the API I would freeze first for `mgps`.

## Topology and schema

```lua
M.context(verb?)
T:Define(schema_text)
T:use(module)
```

## Emission

```lua
M.emit(gen, state_decl, param)
```

## Leaf helpers

```lua
M.leaf(gen, state_fn, param_fn)

M.variant{
    classify = fn,
    gen = fn,
    state = fn,
    param = fn,
}
```

## Structural compilation

```lua
M.match{ ... }
M.compose(children, body_fn?)
M.lower(name, fn)
```

## State declarations

```lua
M.state.none()
M.state.ffi(ctype, opts?)
M.state.record(name, fields)
M.state.product(name, children)
M.state.array(of_decl, n)
M.state.resource(kind, spec)
```

## Runtime

```lua
M.slot()
M.report(boundaries)
```

That is not much larger than original GPS.
But it is significantly more expressive and more correct for modern backends like UI/rendering.

---

# 22. The Design Discipline of mgps

If I had to summarize the design discipline in operational terms:

## For every type at every phase, ask:

1. Which distinctions here still change code shape?
2. Which distinctions here still change state shape?
3. Which distinctions here now only change payload?
4. Which distinctions should have been consumed already?

## For every leaf compiler, ensure it returns:

- `gen`
- structural `state_decl`
- `param`

## For every terminal, ensure:

- no unresolved code choice remains
- all state-shaping facts are explicit and structural
- everything else is payload

## For every runtime path, ensure:

- no runtime dispatch on unresolved source structure
- no hidden state ownership
- no user-exposed key logic

That should be the practical doctrine of `mgps`.

---

# 23. Final Statement

`mgps` is not a rejection of GPS.
It is GPS made more precise.

The original insight remains untouched:

- execution decomposes into **gen / param / state**
- ASDL defines architecture
- the GPS tree should be the ASDL tree
- the framework should infer structure rather than asking users to wire it manually

The refinement is that compilation must now be described more honestly.

Compilation is not just moving “gen facts into param and state.”
It is first **classifying distinctions** into:

- **code shape**
- **state shape**
- **payload**

And then moving those results into runtime form.

`mgps` therefore rebuilds GPS around a stronger terminal contract:

> lowerings emit **gen + structural state declaration + payload**,
> and the framework derives reusable families automatically from that structure.

That keeps the original genius:

- no user-visible keys
- no manual cache protocol
- no framework leakage into domain code
- no loss of ASDL primacy

But it gains what the UI/backend exercise revealed was missing:

- explicit state-shaping structure
- state-layout-aware reuse
- correct separation of reusable family from payload binding
- a principled way to handle modern retained backends without collapsing the model

That is what `mgps` should be.
