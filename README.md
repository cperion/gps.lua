# gps.lua

A Lua framework for building interactive software as compilers.

The centerpiece is **`pvm.lua`**: an ASDL type system combined with
recording-triplet phase boundaries. You define domain types, connect them
with lazy memoized boundaries, and drain the result into a flat command
array that a for-loop executes.

The repo now also contains adjacent projects:

- **`watjit/`** — a typed Lua→WAT/Wasmtime low-level language toolkit with
  scalar integer types, structs/arrays/unions/tagged unions, packed/aligned
  layouts, imports, SIMD, memory helpers, a fixed-capacity hashtable, and
  stream compilation
- **`iwatjit/`** — a bounded-memory phase-caching/runtime layer on top of
  `watjit`, plus a newer spec-first machine-definition surface
- **`asdljit/`** — an early native-ASDL subproject scaffold exploring schema
  parsing + quote/inlining/codegen-driven kernel generation on top of `watjit`

For current `watjit` / `iwatjit` direction, see:

- `iwatjit/README.md`
- `new/IWATJIT_MACHINE_SPEC.md`
- `new/IWATJIT_RUNTIME_LAYOUT.md`
- `new/IWATJIT_PVM_PARITY_CHECKLIST.md`
- `new/ASDLJIT.md`
- `asdljit/README.md`

- `watjit/README.md`
- `new/WATJIT_LANGUAGE.md` for the broader target design

---

## The core idea

Interactive software keeps re-answering the same question at runtime:

> "what does this node mean, really?"

pvm answers it once, caches the answer structurally, and skips the work on
every subsequent frame where the node hasn't changed.

The mechanism is a **recording-triplet phase boundary**:

- On **miss**: the handler dispatches by ASDL type and returns a triplet
  `(gen, param, ctrl)`. A recording wrapper pulls values lazily. When fully
  drained, the result commits to cache.
- On **hit**: returns `seq_gen` over the cached array instantly. Handler not
  called. Zero work.
- On **in-flight (shared)**: another consumer asked for the same node while a
  miss was already recording. They share the same recording entry. No
  duplicate evaluation.

The outermost consumer (`for _, v in phase(node) do ... end`, `pvm.drain`, or
`pvm.each`) is the only loop. Adjacent misses fuse automatically because their
triplets nest — one pull pass flows through the entire chain that LuaJIT can trace.

The compiler doesn't produce machines. The compiler **is** machines, all the
way down. `(gen, param, ctrl)` is not an abstraction over execution — it is
execution factored into its three irreducible roles. Every phase boundary
returns a triplet. Every triplet is a machine. Lua's native generic `for` runs it.

---

## pvm API

```lua
local pvm = require("pvm")
```

### ASDL types

```lua
pvm.context()                   → T       -- create a GC-backed ASDL context
T:Define(schema_string)         → T       -- define types (chainable)
pvm.with(node, {field=value})   → node    -- structural update, preserves sharing
pvm.NIL                         -- sentinel for clearing optional fields in pvm.with
```

### Runtime contract

Current pvm is GC-backed:

- all ASDL runtime values are ordinary GC-managed ASDL objects
- `unique` values are canonical while live
- old ASDL worlds are reclaimed automatically by Lua GC
- optional fields are cleared via `pvm.with(node, { field = pvm.NIL })`

Internal hot-kernel hooks used inside this repo:

- `node:__raw()` — scalar product fast path, returns fields in schema order
- `node:__raw_<field>()` — list fast path, returns `buffer, start, len, present`

These raw helpers are runtime internals for hot code, not general app-facing API.

### Phase boundary — the ONE boundary primitive

```lua
pvm.phase(name, handlers)       → boundary
-- handlers: { [ASDLType] = function(node) → (g, p, c) }
-- handlers MUST return a triplet; use pvm.empty() for zero output
-- returning nil from a handler is an error
-- installs node:name() method on each handled type
-- hit  → seq_gen over cached array (zero work)
-- shared → shared recording_gen (no duplicate eval)
-- miss → recording_gen wrapping handler's triplet; commits on drain
boundary(node)  → g, p, c      -- call form
node:name()     → g, p, c      -- method form

pvm.phase(name, fn)             → boundary
-- fn: function(node) → value
-- value is exposed as a lazy single-element stream
-- consume with pvm.one(boundary(node))
```

### Boundary methods

```lua
boundary:stats()            → { name, calls, hits, shared? }
boundary:hit_ratio()        → number          -- hits / calls
boundary:reuse_ratio()      → number          -- (hits+shared) / calls
boundary:reset()            → nil
boundary:cached(node, ...)  → cached output or nil  -- inspect without populating
boundary:warm(node, ...)    → pre-populate
```

### Triplet constructors

```lua
pvm.once(value)             → g, p, c   -- single-element triplet (leaf handlers)
pvm.empty()                 → g, p, c   -- zero-element triplet
pvm.seq(array, n?)          → g, p, c   -- array as forward triplet
pvm.seq_rev(array, n?)      → g, p, c   -- array as reverse triplet
```

### Triplet composition

```lua
pvm.concat2(g1,p1,c1, g2,p2,c2)        → g, p, c   -- two triplets
pvm.concat3(g1,p1,c1, ..., g3,p3,c3)   → g, p, c   -- three triplets
pvm.concat_all(trips)                    → g, p, c   -- N triplets: {{g,p,c},...}
pvm.children(phase_fn, array, n?)        → g, p, c   -- map phase over children
```

### Consumption helpers (native `for` also works)

`for _, v in phase(node) do ... end` is the canonical executor because pvm returns
Lua-native iterators (`gen, param, state`). The helpers below are convenience
terminals.

```lua
pvm.drain(g, p, c)          → table     -- materialize all values to array
pvm.drain_into(g, p, c, out)→ out       -- append to existing array
pvm.each(g, p, c, fn)       → nil       -- call fn(value) for each element
pvm.fold(g, p, c, init, fn) → acc       -- reduce to single value
pvm.one(g, p, c)            → value     -- require exactly one element
```

### Diagnostics

```lua
pvm.report(phases)          → table of { name, calls, hits, shared, reuse_ratio }
pvm.report_string(phases)   → formatted string
```

### Triplet algebra (`pvm.T`)

Full iterator algebra from `triplet.lua` — `map`, `filter`, `take`, `drop`,
`flatmap`, `zip`, `scan`, `dedup`, `take_while`, `collect`, `fold`, `each`,
`find`, `any`, `all`, `count`, `first`, ...

---

## Quick example

```lua
local pvm = require("pvm")

-- 1. Define domain types
local T = pvm.context():Define [[
    module App {
        Widget = Button(string tag, number w, number h, number rgba8) unique
               | Row(App.Widget* children) unique
    }
    module View {
        Kind = Rect | PushClip | PopClip
        Cmd = (View.Kind kind, string tag,
               number x, number y, number w, number h,
               number rgba8) unique
    }
]]

local B = T:Builders()      -- safe named-field builder surface
local F = T:FastBuilders()  -- trusted named-field builder surface

local K_RECT = T.View.Rect

local function Rct(tag, x, y, w, h, rgba8)
    return T.View.Cmd(K_RECT, tag, x, y, w, h, rgba8)
end

-- 2. Define a phase boundary (handlers must return triplets)
local lower = pvm.phase("lower", {

    [T.App.Button] = function(self)
        -- leaf: wrap one command in pvm.once
        return pvm.once(Rct(self.tag, 0, 0, self.w, self.h, self.rgba8))
    end,

    [T.App.Row] = function(self)
        -- recursive: map phase over children, lazy concat
        return pvm.children(lower, self.children)
    end,

    -- for zero output, return pvm.empty() -- never plain nil

})

-- 3. Build source ASDL (immediate-mode style; interning makes this free)
local root = T.App.Row({
    T.App.Button("play",  48, 30, 0xff3366ff),
    T.App.Button("stop",  48, 30, 0xffcc3333),
    T.App.Button("rec",   48, 30, 0xffcc4400),
})

-- 4. Execute: native Lua generic for over the triplet
-- First call: handlers run, recording fills, caches commit
for _, cmd in lower(root) do
    local k = cmd.kind
    if k == K_RECT then
        -- draw cmd.x, cmd.y, cmd.w, cmd.h, cmd.rgba8
    end
end

-- Second call: all nodes hit cache → seq_gen, zero handler work
for _, cmd in lower(root) do
    -- same commands, no handlers called
end

-- Edit: only the changed button misses; the rest hit instantly
local new_root = pvm.with(root, {
    children = {
        pvm.with(root.children[1], { rgba8 = 0xff336699 }),  -- changed
        root.children[2],  -- same canonical value → cache hit
        root.children[3],  -- same canonical value → cache hit
    }
})

print(pvm.report_string({ lower }))
-- lower                    calls=8  hits=3  shared=0  reuse=37.5%
```

---

## The live loop

```text
poll → apply → phase(source) → for/drain/each → execute
```

**poll** — read input from outside world

**apply** — pure reducer: `(source_asdl, event) → source_asdl`

**phase(source)** — return a triplet chain; nothing evaluates yet

**for/drain/each** — pull through the chain; misses run handlers; caches fill

**execute** — your loop body issues draw calls, fills buffers, etc.

On the next frame: unchanged nodes return `seq_gen` (instant). Only changed
subtrees run handlers. Incrementality is structural, not bolted on.

---

## File map

```
pvm.lua              — the centerpiece: phase boundaries, one, lower (compat),
                        drain, each, fold, once, children, concat, seq, report
triplet.lua          — iterator algebra: map/filter/take/flatmap/zip/scan/...
quote.lua            — hygienic codegen for constructors and hot kernels

asdl_context.lua     — ASDL type system: GC-backed objects, interning, sum types
asdl_lexer.lua       — ASDL schema lexer
asdl_parser.lua      — ASDL schema parser (recursive descent, lexer-fused)

watjit/              — typed Lua→WAT/Wasmtime toolkit: kernels, structs,
                        arrays, arena/slab/LRU helpers, SIMD, stream compilation

archive/             — historical files (gps/mgps era, experimental parsers,
                        retired iwatjit experiment, ...)

docs/
  COMPILER_PATTERN.md    — the paradigm: interactive software as compilers,
                            ASDL design methodology, flatten theorem, five concepts
  PVM_GUIDE.md           — complete pvm/uvm implementation guide
  LIBUI_AUTHORING_GUIDE.md — UI app authoring on top of uilib
```

---

## ASDL quick reference

```text
module Name { definitions... }

TypeName = (field_type field_name, ...) unique?    -- product type
TypeName = Variant1(fields...) unique?             -- sum type
         | Variant2(fields...) unique?
         | Singleton                               -- no fields = canonical singleton handle

Field types:  number  string  boolean
              Module.Type     Module.Type*    Module.Type?
```

Optional named-field builder surface:

```lua
local B = T:Builders()
local F = T:FastBuilders()

local btn = B.App.Button {
    tag = "play",
    w = 96,
    h = 32,
    rgba8 = 0x22c55eff,
}
```

Preferred style:
- `B.*` first for normal authored code — explicit parameter names, safest API
- `F.*` once the code is stable and you want the same named-field style with lower overhead
- `T.*` only when you explicitly want the canonical maximum-speed exact path in hot code, parsers, or benchmarks

All three produce the same canonical interned ASDL values.

`unique` enables structural interning: same fields → same canonical ASDL value.
In current pvm, ASDL values are ordinary GC-managed objects, so identity is ordinary object identity.

---

## Cache hit rates

`pvm.report_string({ phase_boundary, lower_boundary })` prints:

```text
  lower                    calls=4174  hits=3037  shared=892   reuse=93.3%
  solve                    calls=120   hits=118   shared=0     reuse=98.3%
```

| Rate | Meaning |
|------|---------|
| 90%+ | Excellent. Structural sharing works. Incrementality is real. |
| 70–90% | Good during animation (things genuinely change). |
| Below 50% | ASDL design problem — recheck boundaries and identity. |

The reuse ratio (`(hits + shared) / calls`) is the architecture quality metric.

---

## Design documentation

**[COMPILER_PATTERN.md](docs/COMPILER_PATTERN.md)** — the paradigm paper.

- Why interactive software is a compiler
- The five concepts: source ASDL, Event ASDL, Apply, boundaries, flat execution
- The flatten theorem: tree in, flat out, for-loop forever
- ASDL design methodology (six steps, seven tests)
- What the pattern eliminates (state managers, observer buses, virtual DOM, ...)

**[PVM_GUIDE.md](docs/PVM_GUIDE.md)** — the implementation guide.

- All pvm primitives with examples
- The ui5 track editor walkthrough (three ASDL layers, 93% reuse rate)
- Classification discipline: code-shaping vs payload vs dead
- uvm: resumable machine algebra (family/image/machine, step/yield/halt)
- Performance and diagnostics
- Design methodology and checklists

---

## Philosophical note

The original GPS insight (this repo's name) remains the foundation:

> `gen, param, state` is not an abstraction layered over execution.
> It is execution factored into its three irreducible roles.

Lua's generic `for` loop reveals it unusually clearly: `gen` is the step
function, `param` is the invariant environment, `state` is the mutable cursor.
Every running thing decomposes this way — audio filters, parsers, UI renderers,
compilers, spreadsheet evaluators.

pvm takes that decomposition one layer deeper:

> The compiler doesn't produce machines. The compiler IS machines.

Every `pvm.phase` boundary returns a triplet — a machine that runs lazily as
the consumer pulls. Caching is a side effect of full consumption, not an
explicit act. Adjacent phase calls fuse because their machines nest
transparently. The outermost consumer loop is the only loop that runs.

The long-form argument for why this decomposition matters — and what it means
for every domain from audio to UI to parsers — lives in the
[COMPILER_PATTERN.md](docs/COMPILER_PATTERN.md) and the historical GUIDE
section below.

---

## Historical context

This repository evolved through several designs:

1. **GPS** — `gen/param/state` as the minimal model of execution. Lua iterators
   as the natural host. The essay below develops this in full.

2. **mgps** — a refinement: compilation must classify authored distinctions into
   code-shaping / state-shaping / payload. `emit(gen, state_decl, param)`.
   Backends, slots, resource reconciliation. Described in `init.lua`.

3. **pvm** — the current design. Lazy recording-triplet phase boundaries replace
   eager emit+slot. Caching is structural and automatic. Handlers return triplets.
   Drain is the only evaluation trigger. Described in `pvm.lua`.

The essay below (the original GPS guide) remains accurate as the philosophical
foundation. The implementation it describes (`M.emit`, `M.slot`, `M.state.*`)
is the mgps era — superseded by pvm, but the reasoning behind it all still
stands.

---

# The GPS Guide

*The original long-form conceptual argument. Still accurate as philosophy.
Implementation examples reference the older mgps API.*

## The Rabbit Hole Starts with a For Loop

If you have written any Lua, you have written this:

```lua
for i, v in ipairs(mylist) do
    print(v)
end
```

Lua's `for` loop does not call a method on a list object. It does not create
an iterator object. It does not allocate anything on the heap.

What it actually does:

```lua
local gen, param, state = ipairs(mylist)
while true do
    local next_state, value = gen(param, state)
    if next_state == nil then break end
    state = next_state
    print(value)
end
```

Three values:

- `gen` — a function that knows how to get the next element
- `param` — the collection being traversed (never changes)
- `state` — where we are right now (changes every step)

That is a machine.

### Separation

The three concerns are orthogonal. You can change any one without touching the others:

- Same gen, different param → walk a different collection the same way
- Same gen, different state → resume from a different position
- Different gen, same param → walk the same collection a different way

No iterator object can give you that. An iterator object bundles all three
together into one opaque thing. The triple keeps them apart.

### Zero allocation

Because the triple is three values — not an object — iterating costs nothing
beyond the loop itself. No allocation, no GC pressure, no method dispatch.
Safe in audio callbacks, real-time rendering, hot inner loops.

### Composition = fusion

```lua
local function filter_gen(p, s)
    while true do
        local ns, v = p.inner_gen(p.inner_param, s.inner_state)
        if ns == nil then return nil end
        if p.pred(v) then return { inner_state = ns }, v end
        s = { inner_state = ns }
    end
end

function filter(gen, param, state, pred)
    return filter_gen, { inner_gen=gen, inner_param=param, pred=pred }, { inner_state=state }
end
```

No temporary arrays. No intermediate collections. Map, filter, take, drop,
zip, chain — all expressible as triple transformations. This is fusion by
construction, not as an after-the-fact optimization pass.

### LuaJIT already understands `gen, param, state`

LuaJIT's generic `for` loop has dedicated loop bytecodes for generic
iteration. Those bytecodes expect three roles: a step function, an invariant
value, a changing control value. That is `gen, param, state`.

When you write GPS-style code, you are writing code in a shape the JIT was
designed to optimize. The traces compile cleanly. Generated machine code is
tight. Closures cause NYI bytecodes. Dynamic dispatch causes trace exits.
Temporary allocations cause GC pressure. GPS avoids all of it.

### A function is a collapsed machine

Every callable thing decomposes into the same three roles:

| Form | gen | param | state |
|------|-----|-------|-------|
| Pure function | body | — | — |
| Closure with captures | code | captured values | — |
| Stateful closure | code | — | hidden mutable cells |
| Lua iterator | step function | collection | cursor |
| Object with method | method body | `self` config fields | mutable `self` fields |

A function is the degenerate case — a machine where param is implicit and
state is absent.

### Machines everywhere

| Domain | gen | param | state |
|--------|-----|-------|-------|
| Audio filter | filter equation | coefficients | delay history |
| Parser | parse rule | grammar tables | position + stack |
| UI renderer | draw routine | layout plan | GPU cursor |
| Compiler pass | transform rule | input IR + env | traversal cursor |
| Spreadsheet | eval step | dependency graph | cell values |
| Game simulation | physics step | world constants | entity positions |
| Text editor | edit/render step | document model | cursor + view state |

These are not metaphors. They are literally the same decomposition.

### Why this matters for interactive software

An interactive program takes human gestures — clicks, keystrokes, edits —
and turns them into machine behavior — pixels, samples, network bytes.

Between intent and execution there is a gap. The user thinks in domain
concepts ("make this track louder"). The machine works in registers, buffers,
driver calls.

Traditional systems bridge that gap at runtime by re-interpreting broad
authored structure every frame. They keep re-answering:

> "what does this node mean, really?"

The compiler pattern bridges the gap earlier. It treats the authored program
as source, compiles through memoized boundaries into progressively narrower
forms, and produces flat executable artifacts that run without rediscovering
source-level meaning.

That is the claim pvm embodies:

> Interactive software is best understood as a live compiler from authored
> intent to executable flat commands.

For the full treatment — ASDL design, the flatten theorem, what this
eliminates, worked examples for DAWs / text editors / parsers / game engines
— see [COMPILER_PATTERN.md](docs/COMPILER_PATTERN.md).

For the pvm implementation — phase boundaries, the recording-triplet
mechanics, the ui5 walkthrough, performance diagnostics — see
[PVM_GUIDE.md](docs/PVM_GUIDE.md).
