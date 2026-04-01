# mgps

A Lua framework for building interactive software as compilers.

**ASDL-first. Structural. Keyless in public API. Self-hosted.**

`mgps` is the redesign of the original GPS around one refined insight:

> Runtime still decomposes into **gen / param / state**.
> But compilation must classify authored distinctions into **code shape / state shape / payload**.

This repository now treats that refined design as the main architecture.
The old GPS ideas are not discarded; they are sharpened.

What remains central:

- execution still decomposes into `gen`, `param`, `state`
- the ASDL is still the architecture
- the compiler tree should still follow the schema tree
- users should still mostly write **leaf lowerings**
- the framework should still infer structure rather than asking users to hand-wire it

What changes:

- lowerings are described more honestly as **classification boundaries**
- public API is **keyless**
- terminals emit **`gen + structural state declaration + payload`**
- the framework derives reusable compiled families automatically from that structure

The current core provides:

- **ASDL** (builtin) — define domain types with structural interning
- **`M.context()`** — ASDL context and auto-wiring entrypoint
- **`M.emit()`** — public lowering primitive
- **`M.state.*`** — structural state declaration algebra
- **`M.lower()`** — memoized structural boundaries
- **`M.match()`** — sum-type dispatch
- **`M.compose()`** — structural composition with fusion
- **`M.slot()`** — runtime installation with structural state preservation/reallocation
- **`M.app()` / `M.report()`** — live-loop harness and diagnostics

Current status of old parser builtins:

- `M.lex` — not yet ported
- `M.rd` — not yet ported
- `M.grammar` — not yet ported
- `M.parse` — not yet ported

They exist as explicit stubs in the current core so the status is visible and honest.

## Install

Clone into your project as `mgps/` or `gps/`.

In this repository, both module names are currently made available for convenience during the rename:

```lua
local M = require("mgps")
-- or locally:
local M = require("gps")
```

Requires LuaJIT for FFI-backed state declarations and ASDL parser internals.

## Quick Example

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

local function rect_gen(param, state, g)
    g:fill_rect(param.x, param.y, param.w, param.h, param.rgba8)
    return g
end

local function text_gen(param, state, g)
    g:draw_text(state, param.font_id, param.text, param.x, param.y, param.rgba8)
    return g
end

function T.View.Rect:paint()
    return M.emit(
        rect_gen,
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

function T.View.Text:paint()
    return M.emit(
        text_gen,
        M.state.resource("TextBlob", {
            cap = 16,
            font_id = self.font_id,
        }),
        {
            x = self.x,
            y = self.y,
            font_id = self.font_id,
            rgba8 = self.rgba8,
            text = self.text,
        }
    )
end

local frame = T.View.Frame({
    T.View.Rect(10, 10, 120, 30, 0xff3366ff),
    T.View.Text(16, 18, 1, 0xffffffff, "hello")
})

local slot = M.slot()
slot:update(frame:paint())
slot.callback(graphics_backend)
```

What leaf lowerings return is now deliberately sharper than the old `machine(gen, param, state_layout)` story.
They return:

- `gen`
- structural `state_decl`
- residual `param`

The framework then derives reusable compiled families automatically and keeps the key logic hidden.

## Module Pattern

```lua
-- paint.lua
return function(T, M)
    function T.View.Rect:paint(env) ... end
    function T.View.Text:paint(env) ... end
end

-- main.lua
local T = M.context("paint")
    :Define(schema_text)
    :use(require("paint"))
```

## How To Read This README

This README now has two jobs:

1. preserve the long-form conceptual argument that made the original GPS compelling
2. restate the architecture in its new, more precise `mgps` form

So below you will first find the long execution/machine argument that still matters unchanged, and then the redesigned `mgps` doctrine, API, and discipline.

---

# Guide

*The long-form conceptual background, followed by the redesigned mgps architecture.*

## The Rabbit Hole Starts with a For Loop

### Something you already know

If you have written any Lua, you have written this:

```lua
for i, v in ipairs(mylist) do
    print(v)
end
```

You probably think of this as "iterating over a list." That is correct. But there is something hiding inside that loop that almost nobody talks about, and it changes everything.

Lua's `for` loop does not work the way most people think. It does not call a method on a list object. It does not create an iterator object. It does not allocate anything on the heap.

What it actually does is this:

```lua
local gen, param, state = ipairs(mylist)
while true do
    local next_state, value = gen(param, state)
    if next_state == nil then break end
    state = next_state
    -- your loop body here
    print(value)
end
```

Three values. That is it.

- `gen` — a function that knows how to get the next element
- `param` — the collection being traversed (never changes)
- `state` — where we are right now (changes every step)

The function `ipairs` does not "iterate." It returns a triple: a stepping rule, an invariant environment, and a starting cursor. Then the loop drives that triple until it returns nil.

That is a machine.

### Why this matters

Most languages hide this. In Python, you get an iterator object with `__next__`. In Java, you get an `Iterator<T>` with `hasNext()` and `next()`. In C++, you get begin/end pairs with operator overloads. In JavaScript, you get the Symbol.iterator protocol.

All of those allocate. All of those create objects. All of those hide the stepping rule behind a method dispatch. All of those conflate the traversal policy with the collection.

Lua does something different. It says: here are three values. Drive them yourself. No object. No allocation. No dispatch.

That seems like a small implementation detail. It is not. It is the beginning of a completely different way to think about programs.

### The first surprise: separation

Look at the triple again:

- `gen` — the stepping rule. It says *how* to advance.
- `param` — the stable environment. It says *what* we are walking over.
- `state` — the cursor. It says *where* we are.

These three concerns are **orthogonal**. You can change any one without touching the others:

- Same gen, different param → walk a different collection the same way
- Same gen, different state → resume from a different position
- Different gen, same param → walk the same collection a different way
- Same param + state, but swap gen → change traversal policy without touching data

No iterator object can give you that. An iterator object bundles all three together into one opaque thing. Lua keeps them apart.

That separation is the key to everything that follows.

### The second surprise: zero allocation

Because the triple is three values — not an object — iterating costs nothing beyond the loop itself.

No allocation. No garbage collection pressure. No method dispatch overhead. No closure created per iteration.

For most languages, iteration is one of the largest sources of hidden allocation. Iterator objects, closures, generator frames, temporary collections — all of that garbage must be created and collected.

Lua's triple eliminates all of it.

That is not just a performance trick. It means you can iterate in places where allocation is forbidden: audio callbacks, real-time rendering, embedded systems, hot inner loops. The triple is always safe to use.

### The third surprise: composition

Because the triple is just three values, you can transform it:

```lua
-- Slice: iterate only indices lo..hi
function slice(gen, param, state, lo, hi)
    local function slice_gen(p, s)
        if s >= hi then return nil end
        return gen(p, s)
    end
    return slice_gen, param, lo
end

-- Filter: skip elements that don't match
function filter(gen, param, state, pred)
    local function filter_gen(p, s)
        while true do
            local ns, v = gen(p, s)
            if ns == nil then return nil end
            if pred(v) then return ns, v end
            s = ns
        end
    end
    return filter_gen, param, state
end
```

No temporary arrays. No intermediate collections. Just a new triple that wraps the old one.

This is called **fusion**. Operations compose without materializing intermediate results. Map, filter, take, drop, zip, chain — all expressible as triple transformations.

### Where the rabbit hole goes

At this point, most people think: "OK, Lua has a nice iterator protocol. Neat."

But the rabbit hole goes much deeper. Because the triple is not just an iterator protocol. It is a **minimal model of execution itself**.

And once you see that, everything changes.

### The VM already knows `gen, param, state`

The deepest part is this: in LuaJIT, `gen, param, state` is not merely a convenient source-level convention.

It is already reflected in the VM's loop machinery.

LuaJIT's generic `for` loop is not implemented as "some sugar that then becomes ordinary dynamic calls." The VM has dedicated loop bytecodes for generic iteration. Those bytecodes expect exactly three conceptual roles:

- a callable
- an invariant
- a control variable

That is `gen, param, state`.

So when you write:

```lua
for state, value in gen, param, state0 do
    body(value)
end
```

what the VM sees is not "some abstraction the JIT must recover." It already sees the machine shape:

- `gen` → the callable slot
- `param` → the invariant slot
- `state` → the control variable updated every iteration

The consequence is profound.

You are not building an abstraction *above* the VM and hoping the JIT sees through it.
You are writing code in a shape that the VM already treats as a loop primitive.

### Why this is near-free in LuaJIT

This is why GPS machines are so cheap in LuaJIT.

The generic `for` loop already tells the VM:

- this is a loop
- this value is invariant
- this value is the evolving control state
- call the step function
- stop when the first return is nil

So the trace compiler does not have to guess whether it is looking at a loop, or reconstruct one from object methods, closure factories, coroutine resumes, or callback protocols.

The structure is already explicit.

That means a streaming GPS machine is near the VM's native execution shape:

- a stable `gen`
- a stable `param`
- a tiny evolving `state`
- one hot back-edge

This is radically different from other common encodings.

#### Closures as iterators

```lua
local function make_iter(list)
    local i = 0
    return function()
        i = i + 1
        if i > #list then return nil end
        return list[i]
    end
end
```

Now the system has to deal with:

- closure allocation
- captured mutable cells
- general call shape
- hidden state inside upvalues

The machine is still there, but it is hidden.

#### Objects as iterators

```lua
local iter = list:iterator()
while iter:hasNext() do
    local v = iter:next()
end
```

Now the machine is buried behind:

- object allocation
- method lookup
- dynamic dispatch
- hidden mutable fields

Again, the machine is still there, but the host has to recover it through extra machinery.

#### Coroutines as iterators

```lua
local co = coroutine.wrap(function()
    for i, v in ipairs(list) do
        coroutine.yield(v)
    end
end)

for v in co do
    body(v)
end
```

Now traversal is expressed through suspension and resumption.
The machine is spread across coroutine machinery instead of being presented directly as `gen, param, state`.

GPS avoids all of this by not adding a wrapper in the first place.
The machine is already in the host's loop shape.

### A lexer is not wrapped as an iterator — it is the iterator

This is why the following matters so much:

```lua
local function lex_next(param, pos)
    if pos >= param.len then return nil end

    local start = pos
    local dfa_state = 0
    while pos < param.len do
        dfa_state = param.transitions[dfa_state][param.input[pos]]
        if dfa_state < 0 then break end
        pos = pos + 1
    end

    return pos, param.token_kinds[-dfa_state], start, pos
end

for pos, kind, start, stop in lex_next, compiled_dfa, 0 do
    -- process token
end
```

This is not "a lexer API that happens to support iteration."
It is a lexer expressed directly in the VM's native loop form.

Its roles are exact:

- `gen` = `lex_next`
- `param` = the compiled DFA and input buffer
- `state` = the byte cursor

No object is created.
No token array is materialized.
No coroutine is resumed.
No wrapper has to be optimized away.

The parser, decoder, or lowering pass can then do the same thing.
One machine's `param` can hold another machine's `gen` and `param`, and the outer `gen` can step the inner `gen` directly.

That means fusion is not an after-the-fact optimization. It is the natural composition rule of the machine shape.

### Fusion for free

This deserves to be stated as bluntly as possible:

> GPS machines get fusion for free.

Why?
Because composition preserves the same shape.

If one machine's `param` contains another machine's `gen` and `param`, then the outer `gen` can step the inner `gen` directly.
No token array has to be materialized.
No temporary sequence has to be built.
No adapter protocol has to be inserted.
No separate fusion optimization pass has to rediscover what should have happened.

The composition rule already is the fused form.

This also means the execution is inline-shaped by construction.
One machine does not need to allocate a wrapper around another, materialize its outputs, or cross an opaque abstraction boundary. The outer `gen` can step the inner `gen` directly through stable `param` and tiny `state`.

So the important architectural fact is automatic:

- the runtime shape is already fused
- the runtime shape is already inline-shaped
- the optimizer does not have to rediscover that shape after the fact

A backend may still decide for itself how aggressively to inline, trace, or specialize the resulting calls. But the critical point is that GPS removes the abstraction barriers that would otherwise prevent that. Structural inlining is already present before backend optimization begins.

That is the important difference from many iterator, stream, parser, and compiler frameworks.
In those systems, you often start by building layers of wrappers, intermediate objects, callback boundaries, or materialized collections, and then later try to recover performance through a dedicated fusion pass or heroic optimizer work.

GPS starts in the fused shape.

A pipeline like:

```text
bytes → tokens → syntax items → IR nodes → instructions
```

does not have to mean:

```text
bytes -> token array -> syntax tree -> IR list -> instruction list
```

It can instead mean:

```text
outer gen
    calls lower gen
        calls parse gen
            calls lex gen
```

with stable nested `param` and tiny nested `state`.

So the whole stack can run as one streaming machine.
Fusion is not a bonus feature here. It is what happens by default when machines are composed honestly.

This is one of the strongest practical consequences of the GPS view:

- composition is structural
- streaming is natural
- intermediate allocation disappears
- the host sees one hot path

That is why GPS is not only a clean way to describe machines. It is also a clean way to get the performance properties people usually need a separate optimizer to recover.

### The architecture goes deeper than Lua

LuaJIT makes this insight unusually visible because the host loop protocol already exposes the triple directly.

But the idea is deeper than LuaJIT.

At every level, execution keeps decomposing the same way:

- instruction rule / code pointer / loop body → `gen`
- constants / bound environment / read-only tables → `param`
- registers / stack / cursors / mutable cells → `state`

So GPS is not merely a useful way to package software structure.
It is the recurring shape of execution itself.

That is why the model transfers so cleanly across backends:

- LuaJIT
- Terra
- Cranelift
- LLVM
- native code generally

The concrete mechanism changes, but the roles do not.

### The real conclusion

The real conclusion is not simply that Lua has a clever iterator protocol.

It is this:

> `gen, param, state` is not an abstraction layered over execution.
> It is execution factored into its irreducible roles.

Lua's generic `for` loop just happens to reveal that truth unusually clearly.

---

## A Function Is a Collapsed Machine

Part 1 showed something stronger than "Lua has a nice iterator protocol."
It showed that the VM already knows how to execute a machine shaped as `gen, param, state`.

Part 2 now turns that insight around.

If `gen, param, state` is the explicit machine form, then an ordinary function is not the primitive thing we should reason from.
An ordinary function is what you get after some or all of those roles have been collapsed together and hidden.

### The most familiar thing in programming

You write functions every day:

```lua
function add(a, b)
    return a + b
end
```

A function takes inputs, does work, returns outputs. It is the universal building block of software. Every language has them. Every programmer uses them.

But a function hides something.

It hides the same three roles that Part 1 made explicit in the loop:

- what rule is being executed?
- what stable environment is it executing against?
- what mutable execution state exists across steps or calls?

When those roles are left implicit, a function looks like a primitive.
When those roles are separated, the function is revealed as a compressed presentation of a machine.

### What a closure really is

Consider:

```lua
function make_adder(offset)
    return function(x)
        return x + offset
    end
end

local add5 = make_adder(5)
print(add5(3))  -- 8
```

`add5` is a closure. It captures `offset = 5` from its creation environment. When you call it, it reads that captured value.

Now look at it through the triple lens:

- **gen** — the code: `return x + offset`
- **param** — the captured environment: `offset = 5`
- **state** — nothing (stateless)

A closure is a machine with empty state.

### What a stateful closure really is

```lua
function make_counter()
    local count = 0
    return function()
        count = count + 1
        return count
    end
end

local counter = make_counter()
print(counter())  -- 1
print(counter())  -- 2
```

Through the triple lens:

- **gen** — the code: `count = count + 1; return count`
- **param** — nothing (no stable environment beyond the code)
- **state** — `count` (mutable, evolving)

But here is the problem: `count` is hidden inside the closure. You cannot see it. You cannot save it. You cannot restart from a previous value. You cannot run two copies with different counts. You cannot checkpoint and resume.

The closure hides its state. That is convenient for simple uses. It is architecturally devastating for anything serious.

### The general pattern

Every callable thing decomposes into three roles:

| | gen | param | state |
|---|---|---|---|
| Pure function | body | (none) | (none) |
| Closure with captures | code | captured values | (none) |
| Stateful closure | code | (none or captures) | hidden mutable cells |
| Lua iterator | step function | collection | cursor |
| Object with method | method body | `self` fields | mutable `self` fields |
| Coroutine | resume logic | environment | suspension point |

These are all the same structure. They differ only in which of the three roles are explicit versus hidden.

A function is not the primitive. A function is the **degenerate case** — a machine where param is implicit and state is absent.

### Why this matters

If you start from "function," you are starting from the collapsed form. You cannot see the architecture.

If you start from "machine," you can see everything:

- **What is the rule?** → gen
- **What is the stable environment?** → param
- **What is the evolving state?** → state

Those three questions are precise. "What function do I want?" is vague.

When you design a system by asking "what function?", you make one big decision. When you design by asking three specific questions, you make three small decisions that compose independently.

That is a fundamentally different design posture.

### The OOP parallel

If you come from object-oriented programming, you already know a version of this. An object has:

- methods (behavior)
- immutable configuration (constructor arguments, constants)
- mutable fields (instance state)

That is gen, param, state — just with different names and different packaging.

But OOP conflates them into one `self`. The method, the configuration, and the mutable state are all accessed through the same object reference. You cannot separate them.

GPS keeps them apart. That is the difference.

### What you gain from separation

When gen, param, and state are separate:

**You can cache by param identity.** Two machines with the same param and the same gen but different state share compiled structure. You do not need to recompile when only state changes.

**You can hot-swap gen while preserving state.** Change the rule without losing the accumulated history. This is how live coding and hot reload become natural.

**You can checkpoint and resume.** State is explicit data, not hidden in a call stack. Save it. Restore it. Fork it.

**You can compose structurally.** Two machines can share param. Two machines can share gen. State composes by layout — each child owns its own mutable data.

**You can reason about performance.** Gen determines code shape. Param determines what gets baked. State determines what gets allocated. Those are different concerns with different costs.

None of this is possible when all three roles are collapsed into a function.

---

## Machines Everywhere

### Audio: the clearest example

An audio filter processes samples. One sample at a time, thousands per second.

```
input sample → filter → output sample
```

A biquad filter has:

- **gen** — the filter equation: `y = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2`
- **param** — the coefficients: `b0, b1, b2, a1, a2` (computed from frequency, Q, sample rate)
- **state** — the delay history: `x1, x2, y1, y2` (mutated every sample)

The coefficients change when the user turns a knob. The history changes every sample. The equation never changes (for this filter type).

If you implement this as a function:

```lua
function process(x, b0, b1, b2, a1, a2, state)
    local y = b0*x + b1*state.x1 + b2*state.x2
                   - a1*state.y1 - a2*state.y2
    state.x2 = state.x1; state.x1 = x
    state.y2 = state.y1; state.y1 = y
    return y
end
```

That works, but it mixes all three roles in one call signature. Every call passes the coefficients. Every call passes the state reference. The function cannot distinguish "the user changed the frequency" from "another sample arrived."

If you implement this as a GPS machine:

- **gen** = the filter equation (fixed for this filter type)
- **param** = `{ b0, b1, b2, a1, a2 }` (recomputed when the user changes settings)
- **state** = `{ x1, x2, y1, y2 }` (mutated every sample)

Now the architecture is visible:

- Changing the frequency recomputes param. Gen stays the same. State may or may not be preserved (design choice).
- Processing a sample steps the machine. Gen reads param and mutates state. No recomputation.
- Switching filter type changes gen (different equation). Param and state are recomputed for the new type.

That is much cleaner.

### Parsing: a machine you already write

A parser processes tokens. One token at a time.

- **gen** — the parse rule for the current grammar production
- **param** — the grammar tables (first sets, follow sets, production rules)
- **state** — the parse position, the parse stack, the current AST being built

When the grammar changes, param changes. When a token is consumed, state advances. Gen is fixed for a given parser family.

Most parser implementations hide this structure behind recursive descent (state hidden in the call stack) or table-driven automata (gen hidden in a dispatch loop). GPS makes it explicit.

### UI rendering: a machine you don't think of as one

A UI renderer draws widgets. One widget at a time (or one draw command at a time).

- **gen** — the draw routine for this widget family
- **param** — the layout plan (positions, sizes, colors, text runs, clip regions)
- **state** — GPU cursor, batch state, frame-level counters

When the user edits a widget, param changes (the layout plan is recomputed). When a frame is drawn, state evolves (GPU commands are issued). Gen stays the same (the draw routine for rectangles does not change).

Most UI frameworks hide this behind object trees, virtual DOM diffs, or retained-mode scene graphs. Those all work, but they all conflate gen (what to draw), param (where and how), and state (GPU-level frame state) into one amorphous "render pass."

### Compilers: a machine writing machines

A compiler pass transforms IR nodes. One node at a time (or one region at a time).

- **gen** — the transformation rule for this pass
- **param** — the input IR + environment (symbol tables, type context, optimization flags)
- **state** — the traversal cursor (current node, worklist position, accumulated facts)

When the source changes, param changes. When the pass advances, state evolves. Gen stays the same (the type checker always type-checks the same way).

Most compilers hide this behind visitor patterns, recursive descent, or ad hoc pass managers. GPS makes the structure explicit — and that explicitness is exactly what enables incrementality and resumability.

### Spreadsheets: every cell is a machine

A spreadsheet formula is a machine:

- **gen** — the arithmetic operation (`+`, `SUM`, `VLOOKUP`)
- **param** — the cell references and constants (already resolved to indices)
- **state** — nothing (pure computation) or caching state if incremental

The spreadsheet evaluation engine is also a machine:

- **gen** — the evaluation step (compute next cell in topological order)
- **param** — the dependency graph + formula table
- **state** — which cells have been evaluated, current values

### The pattern is everywhere

Once you see it, you cannot unsee it:

| Domain | gen | param | state |
|---|---|---|---|
| Audio filter | filter equation | coefficients | delay history |
| Parser | parse production | grammar tables | parse position + stack |
| UI renderer | draw routine | layout plan | GPU cursor |
| Compiler pass | transform rule | input IR + env | traversal cursor |
| Spreadsheet | eval step | dependency graph | cell values |
| Game simulation | physics step | world constants | entity positions |
| Network handler | protocol step | routing tables | connection state |
| Animation | interpolation step | keyframes | current time + values |
| Database query | scan/join step | query plan | cursor + result set |
| Text editor | edit/render step | document model | cursor + view state |

These are not metaphors. They are literally the same decomposition.

---

## What This Means for How You Think

### The procedural programmer's habit

If you learned to program procedurally, you think in steps:

```
do this
then do that
then check this condition
then loop over these items
then call this function
then store the result
```

That is a fine way to think about the *inside* of gen. But it is a terrible way to think about the *architecture* of a system.

Procedural code conflates rule, environment, and state into one stream of instructions. You cannot see which parts are stable, which parts evolve, and which parts determine code shape.

### The OOP programmer's habit

If you learned to program with objects, you think in nouns:

```
create a FilterNode
give it a frequency property
give it a process() method
connect it to a GraphManager
register it with the AudioEngine
```

That is better — you have named things. But OOP conflates method behavior (gen), configuration (param), and mutable fields (state) into one object. You cannot separate the concerns.

Worse, OOP encourages **identity over value**. Objects are mutable references. Two objects with the same data are still two different objects. That destroys caching, sharing, and structural comparison.

### The functional programmer's habit

If you learned functional programming, you think in transformations:

```
map this function over this list
fold the result with this accumulator
compose these two transformations
```

That is closest to GPS thinking. But pure FP avoids state entirely, which means it cannot naturally express machines that evolve over time. Monads, state transformers, and effect systems are all ways of smuggling state back in — often with significant cognitive and runtime cost.

GPS says: state is real. It is not something to be avoided or hidden. It is one of three explicit roles.

### The GPS programmer's way

GPS thinking asks three questions, always:

1. **What is the rule?** — What computation happens at each step?
2. **What is stable?** — What data does the machine read but never change?
3. **What is live?** — What data does the machine own and mutate?

That is it. Those three questions replace:

- "What class should I create?"
- "What methods should it have?"
- "What state should it hold?"
- "How should it be constructed?"
- "Who manages its lifecycle?"
- "How does it communicate with other objects?"

Most of those questions dissolve when you think in machines.

### A concrete example: the shift

Suppose you are building a volume fader for an audio track.

**OOP approach:**

```
class VolumeFader
    property value: float
    property track_id: int
    method on_drag(new_value)
        self.value = new_value
        self.audio_engine.update_volume(self.track_id, new_value)
    method render(canvas)
        canvas.draw_slider(self.value)
```

This works. But it has hidden coupling (the audio engine), mutable identity (`self`), mixed concerns (input handling, rendering, audio control), and no clear caching or incrementality story.

**GPS approach:**

First, separate the concerns into their roles:

The *source ASDL* (what the user authored):

```
Track = (number id, string name, number volume_db) unique
```

The *event* (what happened):

```
SetVolume = (number track_id, number value)
```

The *apply* (pure state transition):

```lua
function apply(state, event)
    -- returns new state with volume_db changed
    -- structural sharing: unchanged tracks are the same objects
end
```

The *compilation* (source → machine):

- volume_db is a gen-shaping fact at source level
- it becomes a param value (linear gain coefficient) at the scheduled level
- the audio machine reads it as stable payload
- state is the filter history (unrelated to volume)

The *view projection* (source → visual):

- volume_db becomes a slider position (param for the draw machine)
- no runtime coupling to the audio engine
- the slider and the audio path share a source truth (the Track node)

Nothing is hidden. Nothing is coupled through mutable shared state. Nothing needs a "manager" or "engine" or "bus" to coordinate.

### Why this feels unfamiliar

GPS thinking is unfamiliar because it reverses the usual priority:

| Usual priority | GPS priority |
|---|---|
| Start with objects | Start with machines |
| Methods encapsulate behavior | Gen is separate from data |
| Mutable state is hidden inside objects | State is explicit and visible |
| Coupling is managed by patterns | Coupling is eliminated by separation |
| Identity is reference-based | Identity is structural |
| Caching is added later | Caching falls out from param identity |
| Incrementality is a feature | Incrementality is a consequence of architecture |
| Lifecycle is managed by frameworks | Lifecycle is compilation + installation |

This is genuinely different. It is not a refinement of OOP. It is not a variant of FP. It is a different paradigm.

It takes time to internalize. But once you do, you will find that many problems you used to solve with patterns, frameworks, managers, and buses simply do not arise.

---

## Fast Data Structures — The Practical Payoff

Before going deeper into compiler architecture, let us see the immediate practical payoff of GPS thinking: fast, allocation-free data structure APIs.

This is where the Lua iterator protocol becomes genuinely powerful.

### The allocation problem

In most languages, working with collections means allocating:

```python
# Python: every operation creates a new list
filtered = [x for x in items if x > 0]
mapped = [x * 2 for x in filtered]
result = sum(mapped)
```

Three temporary lists. Three allocations. Three garbage collections eventually.

In Lua with GPS, the same logic costs zero allocations:

```lua
local result = 0
for _, v in filter(items, function(x) return x > 0 end) do
    result = result + v * 2
end
```

No intermediate collections. The filter is just a different gen over the same param. The multiply happens inside the loop body. One traversal. Zero allocation.

### Building a vector with GPS iteration

```lua
local function vec_next(vec, i)
    i = i + 1
    if i <= vec.n then
        return i, vec.data[i]
    end
end

local Vec = {}

function Vec.new(data, n)
    return { data = data, n = n }
end

function Vec.items(vec)
    return vec_next, vec, 0
end

function Vec.slice(vec, lo, hi)
    return vec_next, vec, lo - 1  -- start from lo
    -- (would need a slice_next that checks hi)
end
```

Usage:

```lua
for i, v in Vec.items(myvec) do
    -- zero allocation, direct array access
end
```

The key insight: `vec_next` is defined once at module load time. Every call to `Vec.items` returns the same function. Only param and state differ. No closure is created per iteration.

### Sparse sets

A sparse set stores entities in a dense array with O(1) add, remove, and membership test. It is the workhorse data structure of Entity Component Systems.

```lua
local function sparse_next(set, i)
    i = i + 1
    if i <= set.count then
        return i, set.dense[i]
    end
end

function SparseSet.alive(set)
    return sparse_next, set, 0
end
```

Iterating only visits alive entities. Dead entities are never touched. The dense array is contiguous in memory. LuaJIT traces this perfectly.

### Ring buffers

```lua
local function ring_next(ring, i)
    i = i + 1
    if i > ring.count then return nil end
    local idx = (ring.head + i - 1) % ring.capacity
    return i, ring.data[idx]
end

function Ring.items(ring)
    return ring_next, ring, 0
end
```

The loop looks linear. The storage wraps. The caller does not need to know. Param carries the ring metadata. State is the logical position.

### Zero-copy views

Instead of copying a subarray:

```lua
function Vec.view(vec, lo, hi)
    local function view_next(p, i)
        i = i + 1
        if i + p.lo - 1 > p.hi then return nil end
        return i, p.vec.data[i + p.lo - 1]
    end
    return view_next, { vec = vec, lo = lo, hi = hi }, 0
end
```

No copy. No allocation (beyond the small param table, which could be avoided with packing). The view is a different traversal of the same storage.

### Multiple traversals over one structure

The same data structure can expose multiple GPS triples:

```lua
container:items()        -- all values
container:alive()        -- skip tombstones
container:reverse()      -- backward
container:keys()         -- keys only
container:values()       -- values only
container:pairs()        -- key-value
container:slice(lo, hi)  -- subrange
```

Each is a different `(gen, param, state)` triple. Same storage. Different policy. Zero allocation per traversal.

### Resumable iteration

Because state is explicit data, you can save it and resume later:

```lua
local gen, param, state = Vec.items(myvec)

-- Process 10 items
for i = 1, 10 do
    state, v = gen(param, state)
    if state == nil then break end
    process(v)
end

-- Save state for later
saved_state = state

-- ... later ...

-- Resume from where we left off
for remaining_state, v in gen, param, saved_state do
    process(v)
end
```

This is impossible with closure-based iterators. The closure's state is hidden. You cannot access it, save it, or fork it.
G
With GPS, resumability is free. It is just: save state, resume later.

This matters for:

- long computations split across frames
- cooperative scheduling
- incremental processing
- chunked traversals over many ticks

### Why LuaJIT loves GPS

LuaJIT's tracing JIT compiler is specifically good at GPS patterns because:

1. **Predictable control flow.** Gen is a small function with clear branching. The trace compiler can see the whole loop shape.

2. **Stable types.** Param is accessed through consistent field paths. State is usually a number. No type instability.

3. **No allocation in the loop.** No closures, no iterator objects, no temporary tables. Nothing for the GC to worry about.

4. **Monomorphic dispatch.** Gen is called directly. No method lookup, no virtual dispatch, no metatables in the hot path.

When you write GPS-style code in LuaJIT, you are writing code that the JIT was designed to optimize. The traces compile cleanly. The generated machine code is tight.

When you write closure-heavy, object-heavy, or dynamic-dispatch-heavy code, LuaJIT struggles. Closures cause NYI (not yet implemented) bytecodes. Dynamic dispatch causes trace exits. Temporary allocations cause GC pressure.

GPS and LuaJIT are a natural fit.

---


---

# 1. The Central Thesis

The original GPS insight remains true:

- **gen** — the rule that runs
- **param** — stable payload the rule reads
- **state** — mutable runtime data the rule owns

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

- changes the **compiled rule**
- changes the **runtime state layout / ownership / allocation / initialization**
- changes only the **stable payload**
- or means the field should not still exist at this boundary

That yields the new compiler discipline.

---

# 2. Runtime Roles vs Boundary Sensitivities

This distinction is the heart of `mgps`.

## Runtime roles

Every running machine still has exactly three runtime roles:

- **gen**
- **param**
- **state**

That is execution.

## Boundary sensitivities

But fields at a compilation boundary are not classified directly by runtime role. They are classified by **what changing them invalidates**:

- **code-shaping** — changing it changes the compiled rule
- **state-shaping** — changing it changes runtime state layout, ownership, allocation, or initialization strategy
- **payload** — changing it only changes stable data read by the rule
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

---

# Current Implementation Notes

The code in this repository currently reflects the new `mgps` core.

That means:

- `init.lua` contains the structural `mgps` redesign
- `mgps.lua` and `gps.lua` are local wrappers for convenience
- the old parser subsystem has **not** yet been ported
- demos should be written in `mgps` style: `emit(gen, state_decl, param)`

Compatibility notes:

- `M.with(...)` exists and should be used for structural updates of ASDL nodes
- `M.state_ffi(...)` and `M.state_table(...)` currently exist as convenience aliases/wrappers over `M.state.*`
- `M.lex`, `M.rd`, `M.grammar`, and `M.parse` are explicit stubs for now

The important thing is that the architecture has changed even where some old names still exist for convenience.
The project should now be thought of as **mgps**.
