# gps.lua

A Lua framework for building interactive software as compilers.

**2712 lines. Zero external dependencies. Self-hosted.**

## What It Is

Every executable thing decomposes into three roles:

- **gen** — the rule (what code runs)
- **param** — the stable data (what the code reads)
- **state** — the mutable runtime data (what evolves per step)

A function is a collapsed machine. A closure is a machine with hidden param. An object is a machine with hidden everything. GPS makes the roles explicit.

The framework provides:

- **ASDL** (builtin) — define your domain types with structural interning
- **GPS.lower** — memoized compilation boundary with two-level cache
- **GPS.compose** — structural composition with automatic fusion
- **GPS.slot** — hot swap that preserves state on param-only changes
- **GPS.context** — auto-wires the ASDL tree into a compilation pipeline
- **GPS.grammar** — builtin grammar compiler: grammar ASDL → fused lexer+parser
- **GPS.parse** — primary parser facade over compiled grammar families
- **GPS.lex / GPS.rd** — low-level GPS-native lexer and manual recursive-descent helpers

The ASDL type system already encodes GPS roles: **sum types are gen-shaping, scalars are param**. The framework reads the schema and caches accordingly. No annotations needed.

## Install

Clone into your project as `gps/`:

```bash
git clone git@github.com:cperion/gps.lua.git gps
```

Requires LuaJIT (for FFI). No other dependencies.

## Quick Example

```lua
local GPS = require("gps")

local T = GPS.context()
    :Define [[
        module Source {
            Project = (Track* tracks, number sample_rate) unique
            Track = (number id, string name, Device* devices, number volume_db) unique
            Device = Osc(number id, number hz) unique
                   | Filter(number id, FilterMode mode, number freq, number q) unique
                   | Gain(number id, number db) unique
            FilterMode = LowPass | HighPass | BandPass
        }
    ]]

-- Only write leaf machines — the framework wires everything else
function T.Source.Osc:compile(sr)
    return GPS.machine(
        function(p, s, t) return math.sin(p.phase_inc * t * 6.283) end,
        { phase_inc = self.hz / sr },
        GPS.state_ffi("struct { double phase; }"))
end

function T.Source.Filter:compile(sr)
    local coeffs = compute_coeffs(self.mode, self.freq, self.q, sr)
    return GPS.machine(biquad_gen, coeffs, biquad_state)
end

function T.Source.Gain:compile(sr)
    return GPS.machine(gain_gen, { gain = 10 ^ (self.db / 20) })
end

-- Build, compile, run
local project = T.Source.Project({ ... }, 44100)
local machine = project:compile()

local slot = GPS.slot()
slot:update(machine)
slot.callback(...)  -- run the machine

-- Edit: turn a knob (param-only → state preserved, no glitch)
local project2 = T.Source.Project({ ... }, 44100)  -- freq changed
slot:update(project2:compile())  -- same gen_key → rebind param, keep state
```

## Module Pattern

```lua
-- audio.lua
return function(T, GPS)
    function T.Source.Osc:compile(sr) ... end
    function T.Source.Filter:compile(sr) ... end
    function T.Source.Gain:compile(sr) ... end
end

-- main.lua
local T = GPS.context()
    :Define(schema_text)
    :use(require("audio"))
```

## How It Works

1. **`T:Define`** parses the ASDL schema, creates types with structural interning, and auto-wires sum type dispatch + containment composition
2. You install `:compile()` methods on leaf variant types — the only hand-written code
3. Calling `node:compile()` walks the ASDL tree: sum types dispatch to variant methods, containment fields map children + compose
4. `GPS.lower` wraps each dispatch with a two-level cache: L1 (node identity for siblings) + L2 (gen_key for param-only changes)
5. `GPS.compose` fuses children's gens as upvalues — one hot trace, no indirection
6. `GPS.slot` detects gen vs param changes: same gen_key → rebind param, preserve state

The gen_key is the variant name, set automatically by `GPS.match`. Most edits (knob turns, value changes) are param-only: the gen_key doesn't change, the gen is reused, the state is preserved.

---

# Guide

*The ideas behind the framework.*

---

## The Hard Rules

Before the examples, the rules.

This document is not only an explanation of a useful pattern. It is also an operational discipline.

If you are designing ASDL, phases, Machine IR, backend lowering, or runtime contracts using this model, these rules are not optional.

### Every field has exactly one GPS role

Every field in every phase must be classified as one of:

- **gen-shaping** — it determines which machine is built
- **param** — it becomes stable payload the machine reads
- **state declaration** — it declares mutable runtime layout or ownership

If a field cannot be classified, the design is wrong.

If a field seems to play multiple roles at once, the phase is wrong.

If a field is present only because "the next phase might need it," the IR is wrong.

### Every phase must justify itself by role movement

A phase is real only if it moves knowledge between GPS roles.

Good phase verbs:

- lower
- resolve
- classify
- schedule
- bind
- specialize
- compile

Bad phase descriptions:

- "cleanup"
- "prepare stuff"
- "gather data"
- "make runtime easier"

If you cannot say which gen-shaping facts are being consumed into param or state, the phase is not real yet.

### Terminal input must have zero gen-shaping facts

A terminal is allowed to define execution meaning.

A terminal is **not** allowed to keep rediscovering semantics.

If the terminal still branches on variants, tag strings, unresolved references, or broad authored choices, then lowering is incomplete.

The terminal input should contain:

- stable param
- state declarations
- no unresolved machine choice

### Unclassified bags are forbidden

Reject IR that looks like this:

- bag-of-fields records with mixed derived/runtime/authored facts
- broad records whose fields are present "for convenience"
- records that contain both unresolved semantic choices and backend layout data
- fields that exist only to save a lookup in some later ad hoc function

Those are signs that GPS roles are being mixed instead of phased.

### Runtime dispatch on gen-shaping facts is a design error

If execution code does any of these, treat it as a type error in the architecture:

- `if kind == ...` in a hot path
- `match` on authored variants during execution
- lookup by unresolved name/tag in the terminal or backend hot loop
- dynamic rediscovery of layout that should have been declared earlier

The fix is upstream: consume the gen-shaping fact in an earlier phase.

### State is explicit, never smuggled

If evolving machine state is hidden in:

- closure cells
- object internals
- coroutine suspension state
- mutable accumulators in "pure" compiler code
- ad hoc runtime tables that stand in for a designed layout

then the machine boundary is underspecified.

State must be explicit data with a clear owner.

### The mandatory role audit

For every new type, every new field, and every new phase, ask:

1. What fields here are gen-shaping?
2. Which boundary consumes them?
3. What becomes param?
4. What becomes state declaration?
5. What remains for the next phase, and why?

If you cannot answer all five, stop and redesign before coding.

### The ASDL already knows GPS roles

There is a deeper rule that makes role classification mechanical rather than manual:

> **Sum types are gen-shaping. Scalars are param. The ASDL type system already encodes which is which.**

A sum type (variant choice) is always gen-shaping because you MUST dispatch on it to know what code to run. An `Osc` needs an oscillator equation. A `Filter` needs a filter equation. The variant tag IS the code choice.

A scalar (number, string, boolean) is param. `freq = 2000` does not force a branch. The biquad equation is the same for freq=2000 and freq=3000. Only the coefficients change.

This means:

- You do not need to annotate fields with GPS roles manually
- The framework can extract the **variant skeleton** (all sum-type tags, recursively) as the **gen_key** automatically
- Two nodes with the same variant skeleton produce the same machine code
- Different scalars only change param

The design discipline follows: **if changing a value changes what code runs, model it as a sum type. If it changes what data the code reads, keep it scalar.**

A `boolean muted` that determines whether a machine is emitted should be `MuteState = Active | Muted`. A `number channel_count` that determines mono vs stereo processing should be `ChannelConfig = Mono | Stereo`. If it shapes code, it wants to be a sum type.

### Worked role-audit example

Here is a bad IR:

```text
Node = (
    number id,
    string kind,
    number freq,
    number q,
    number b0, number b1, number b2, number a1, number a2,
    number state_offset,
    number state_size
)
```

This looks practical. It is also architecturally wrong.

Why it is wrong:

- `kind` is **gen-shaping** (but encoded as a string — should be a sum type)
- `freq`, `q` are **param** (scalars that become coefficients)
- `b0..a2` are **param** derived values
- `state_offset`, `state_size` are **state declarations**

So one record contains three different role layers at once:

- unresolved machine choice
- compiled stable payload
- backend/runtime layout

That means at least one phase is missing.

A better design is:

```text
Source.Filter = (
    number id,
    FilterMode mode,
    number freq,
    number q
) unique

Resolved.Filter = (
    number id,
    FilterMode mode,
    number freq,
    number q,
    number sample_rate
) unique

Scheduled.BiquadJob = (
    number id,
    number b0, number b1, number b2, number a1, number a2,
    number state_offset,
    number state_size
) unique
```

Now the role movement is visible:

- `mode` is a sum type → **gen-shaping**. It gets consumed when the variant is dispatched and coefficients are computed.
- `freq`, `q` are scalars → **param**. They feed coefficient computation.
- `sample_rate` is resolved from context → **param**
- `b0..a2` are computed scalars → **param**
- `state_offset` is layout → **state declaration**
- the terminal input (`BiquadJob`) has zero sum-type fields = zero gen-shaping facts

The gen_key at the terminal is the **type name** itself: `BiquadJob` vs `OscJob` vs `GainJob`. The ASDL already knows this. No annotation needed.

### The quick test for any candidate type

For any type you are about to add, fill this in before accepting it:

```text
Type name:

Fields:
- field_a → ?
- field_b → ?
- field_c → ?

Consumed here:
- ...

Left unresolved for next phase:
- ...
```

If you cannot fill it in cleanly, the type is not ready.

---

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

## The Deeper Pattern — GPS as a Type System

### Every field has a role

We have seen that every executable thing decomposes into gen, param, and state. Now comes the deeper insight.

If every machine has three roles, then the **data that feeds machines** also has three roles.

Consider an audio processing pipeline. Somewhere in the system there is an IR node that describes a filter:

```
ScheduledFilter = (
    number id,
    number kind_code,
    number b0, number b1, number b2,
    number a1, number a2,
    number state_offset,
    number state_size
)
```

Every one of those fields serves a specific GPS role:

- `kind_code` — **gen-shaping**: determines which filter equation is used
- `b0..a2` — **param**: stable coefficients the machine reads
- `state_offset`, `state_size` — **state declaration**: defines the machine's mutable layout
- `id` — **param**: stable identity

No field is "just a field." Every field feeds one of three machine roles.

### This is a type system

That classification has the properties of a type system:

**Exhaustive.** Every field must be gen-shaping, param, or state-declaring. If a field does not serve any of those roles for a downstream machine, it does not belong in this IR.

**Checked.** A gen-shaping fact that ends up in state is wrong — it should have been consumed. A state declaration that ends up in source is wrong — it should not be there yet. Stable param that gets recomputed every frame is wrong — it should be cached.

**Compositional.** Gen-shaping facts compose by specialization (narrowing choices). Param composes by product (bundling data). State composes by layout (allocating slots). These are different composition rules. Mixing them is an error.

**Phase-ordered.** Gen-shaping facts must be consumed before code is emitted. Param must be available before installation. State must be declared before execution. The roles impose an order.

### What changes in practice

Without GPS roles, you design an IR by asking: "what fields does the next phase need?"

That is correct but vague. It invites bag-of-fields designs where derived data, runtime state, unresolved references, and stable constants all sit together on one record.

With GPS roles, you ask three specific questions for each field:

1. Does this field determine which machine variant is built? → **gen-shaping**
2. Does this field become stable payload the machine reads? → **param**
3. Does this field declare mutable runtime layout? → **state**

If a field does not answer any of these, it does not belong here. It belongs in a different phase, a different projection, or nowhere.

### Sum types are gen-shaping. Scalars are param.

This is the key insight that makes GPS roles mechanical rather than subjective.

Consider a music tool:

```
Editor.Track = (number id, string name, Device* devices,
                number volume_db, number pan, MuteState muted) unique

MuteState = Active | Muted
```

- `id` — scalar → **param** (stable identity, does not shape code)
- `name` — scalar → **param** (a label, does not shape code)
- `devices` — list of sum-typed items → **gen-shaping** (determines what machines get built)
- `volume_db` — scalar → **param** (becomes a gain coefficient)
- `pan` — scalar → **param** (becomes a pan coefficient)
- `muted` — sum type → **gen-shaping** (determines whether a machine is emitted or bypassed)

The gen_key of this Track is: the list of Device variant tags + the MuteState tag. The scalars (`id`, `name`, `volume_db`, `pan`) do not contribute. A knob turn (scalar change) does not change the gen_key. Only structural changes (add/remove device, change device type, mute/unmute) change the gen_key.

Sum types are the gen-shaping facts:

```
Device = Osc(number id, number hz)
       | Gain(number id, number db)
       | Filter(number id, FilterMode mode, number hz, number q)

FilterMode = LowPass | HighPass | BandPass
```

The variant choice directly determines which gen is emitted. An oscillator gets an oscillator equation. A filter gets a filter equation. `FilterMode` determines which coefficient formula is used. These are the only things that shape the machine's code.

The scalars (`hz`, `db`, `freq`, `q`) become param — they feed into coefficient computation but do not change the code shape. The biquad equation is the same for freq=2000 and freq=3000.

### Lower phases consume sum types

As the compiler pipeline progresses, sum types get consumed:

```
Source:      Device = Osc | Gain | Filter     ← sum type (gen-shaping)
                     FilterMode = LowPass | HighPass | BandPass

Resolved:    Same structure + sample_rate attached (scalar = param)

Scheduled:   Job = BiquadJob(...) | OscJob(...) | GainJob(...)
             BiquadJob has only scalars inside: b0, b1, b2, a1, a2
```

At the source level, `Device` is a sum type with three variants. `FilterMode` is a nested sum type. These are all gen-shaping.

At the scheduled level, the `Job` is still a sum type (gen-shaping at the *parent* level), but each variant's *fields* are all scalars (param). The `FilterMode` has been consumed — its information folded into which coefficient formula was used. The `Device` variant has been consumed — its information determines which `Job` variant was emitted.

By the time you reach a single `BiquadJob` node, there are zero sum-type fields inside. Everything is scalar. Everything is param or state. That is exactly the right input for a machine.

The gen_key at the terminal is just the variant tag: `"BiquadJob"` vs `"OscJob"` vs `"GainJob"`. The ASDL knows this from the type definitions. No annotation needed.

### The pipeline is sum-type consumption

Now we can say precisely what a compiler pipeline does:

> **A compiler pipeline progressively consumes sum types into scalars.**

Each phase transition dispatches on a sum type and produces scalar results. The variant choice disappears — its information becomes computed numbers, resolved indices, concrete coefficients.

When all sum types have been consumed, you have a machine. The machine's gen is fixed (determined by the consumed variant path). Its param is stable (all the scalars). Its state is declared. The machine can be installed and run.

That is what "compilation" means. And the ASDL tracks it automatically: count the sum-type fields at each phase. The number must decrease monotonically. At the terminal, it reaches zero.

### How to use this as a design discipline

At this point the most important shift is operational, not philosophical.

Do **not** read GPS as a nice explanatory layer you can apply after the architecture is already designed.

Use it as a gate.

When you draft a type, perform a role audit immediately:

- Which fields are still gen-shaping?
- Which fields are already stable param?
- Which fields declare state?

When you draft a phase, perform a movement audit immediately:

- Which gen-shaping facts are consumed here?
- Into what param values?
- Into what state declarations?
- What gen-shaping facts remain for the next phase?

When you draft a terminal, perform a terminal audit immediately:

- Does the input contain any unresolved machine choice?
- Does execution still branch on authored variants?
- Does the terminal still need semantic lookups that should have happened upstream?

If the answer to any of those is yes, stop.

Do not patch the implementation. Do not add helper tables. Do not add context objects. Do not add runtime switches. Fix the ASDL or insert the missing phase.

### The three immediate rejection tests

Reject a design immediately if any of these happen:

**Test 1: unclassified field**

You add a field and cannot say whether it is gen-shaping, param, or state declaration.

→ The type is wrong.

**Test 2: mixed-role record**

One record contains unresolved semantic choices, derived coefficients, and backend layout data all at once.

→ A phase boundary is missing.

**Test 3: terminal rediscovery**

The terminal still needs to inspect broad source structure to decide what machine to emit.

→ Lowering is incomplete.

These are not style problems. They are architectural failures.

---

## Interactive Software Is a Compiler

### The old way

Most interactive software works like this:

```
User does something
→ Event handler fires
→ Handler modifies some state
→ Various parts of the system notice (or don't)
→ UI updates (maybe)
→ Audio engine updates (maybe)
→ Network sends a message (maybe)
→ Some caches are invalidated (hopefully)
→ The system is in a new state (probably consistent)
```

That is an **interpreter**. Every user gesture is interpreted at runtime. Every callback re-examines broad state. Every update re-traverses data structures. Every frame re-answers the question: "what should be happening right now?"

This works, but it is architecturally expensive:

- State is scattered across objects
- Coupling is managed by observers, buses, and managers
- Caching is ad hoc (some things cached, some not, invalidation bugs everywhere)
- Incrementality is hard (every change potentially affects everything)
- Testing requires mocks, fixtures, and elaborate setup

### The compiler way

The compiler pattern says: treat the user's work as a **program**, and compile it.

```
User does something
→ Event (explicit, typed)
→ Apply: pure (old_source, event) → new_source
→ Compile: progressively move gen-shaping facts → param/state
    → transitions consume decisions (memoized, incremental)
    → terminal produces machines (gen/param/state)
→ Realize: specialize machines for the backend (GPS → backend-native GPS)
→ Execute: drive the installed machines
→ Repeat
```

The source ASDL is the program. Events are input. Apply is the state transition. Compilation moves knowledge through GPS roles. Machines — all the way down — are GPS machines.

### Why this is better

**Incrementality for free.** Because ASDL nodes are unique (structurally interned), unchanged subtrees are the same objects. Memoized transitions hit the cache instantly. Only changed subtrees recompile.

**No invalidation framework.** The cache key is the ASDL node identity. If the node did not change, the result did not change. No dirty flags. No observer notifications. No manual cache management.

**Pure compilation.** Every transition is a pure function from ASDL to ASDL. No side effects. No ambient state. Testable with one constructor and one assertion.

**Structural sharing.** Edits produce new ASDL trees that share structure with the old ones. Changing one track's volume produces a new project where every other track is literally the same object. This is how O(1) cache lookups work on O(n) data.

**Hot swap.** When the source changes, affected machines recompile. New artifacts replace old ones. Execution continues. No restart. No rebuild. No "did you save?"

### GPS makes the compiler pattern precise

The original "Modeling Programs as Compilers" document described this architecture powerfully but did not fully name the underlying mechanism.

GPS names it: **compilation is progressive role movement of gen-shaping facts into param and state**.

That is what every transition does. That is what every terminal produces. That is what every machine is.

And because GPS is a structural type system, you can check the health of your pipeline at every stage:

- Does this phase reduce gen-shaping facts? If not, it is not a real phase.
- Does this IR field serve a GPS role? If not, it does not belong here.
- Does the terminal input have zero gen-shaping facts? If not, the lowering is incomplete.

---

## The Source Language

### ASDL: the user's programming language

The ASDL (Abstract Syntax Description Language) is not a data format. It is not a config schema. It is not a serialization format.

It is a **language**. The user's domain-specific language.

A good ASDL has:

- clear nouns (what things exist)
- clear variants (what choices are possible)
- compositional structure (what owns what)
- stable identity (what can be pointed to)
- completeness (every user-reachable state is representable)
- minimality (every field is an independent authored choice)

These are the same properties that make any programming language good.

### Designing the source ASDL

This is the hard part. GPS does not make it easy — it makes it precise.

The method, step by step:

**Step 1: List the nouns.** Open the program (or imagine it). What does the user see and interact with? Write down every noun.

For a music tool:

```
project, track, clip, device, parameter, knob, fader,
automation curve, breakpoint, send, bus, modulator,
transport, tempo, time signature, scene, mixer, waveform
```

For a text editor:

```
document, paragraph, heading, list, code block, span,
cursor, selection, font, style, link, image, table, cell
```

**Step 2: Classify identity vs property.** For each noun, ask: "Can the user point to this and say 'that one'?"

If yes → **identity noun** → gets its own ASDL record with a stable ID.
If no → **property** → becomes a field on an identity noun.

```
IDENTITY: track, clip, device, parameter, send, automation curve
PROPERTY: volume_db, pan, muted, frequency, Q, gain_db
```

**Step 3: Find the sum types.** Every "or" in the domain becomes an enum:

```
Device = Osc(...) | Gain(...) | Filter(...)
Clip = AudioClip(...) | MIDIClip(...)
Selection = Cursor(...) | Range(...)
```

GPS note: these are the strongest gen-shaping facts. Each variant determines a different machine.

**Step 4: Draw the containment tree.** What owns what? Parents own children. Cross-references are IDs, never pointers.

```
Project
└── Track*
    ├── Device*
    │   └── Parameter*
    ├── Clip*
    └── Send*
```

**Step 5: Find the coupling points.** Where do two subtrees need each other's information? These determine phase ordering.

**Step 6: Define the phases.** Each phase consumes gen-shaping facts. Name the verb.

```
Editor → Authored     (verb: lower — containers → graphs)
Authored → Resolved   (verb: resolve — validate references)
Resolved → Scheduled  (verb: schedule — assign buffers, order)
Scheduled → Machine   (verb: compile — emit gen/param/state)
```

**Step 7: Test the source ASDL.**

GPS adds step 8:

**Step 8: Verify GPS roles.** At each phase, check that sum types decrease monotonically. Verify terminal input has zero sum-type fields. The ASDL already encodes the roles — sum types are gen-shaping, scalars are param. No manual annotation needed.

### The quality tests

Before writing any code, verify:

**Save/load.** Serializing and deserializing the source ASDL preserves all user intent. If something is lost, a field is missing.

**Undo.** Restoring the previous ASDL tree restores all behavior. No repair logic, no special cleanup. Just replace the tree. Memoize handles the rest.

**Completeness.** Every state the user can reach through the UI is representable. Every variant is reachable.

**Minimality.** Every field is an independent authored choice. Derived values (computed coefficients, layout positions, buffer allocations) do not belong in the source.

**Orthogonality.** Independent fields vary independently. If changing one constrains another, a sum type is missing.

**Testing.** Every function is testable with one constructor and one assertion. No mocks, no fixtures, no setup.

GPS adds:

**Role purity.** Every source field is gen-shaping. No param (derived data) or state (runtime layout) has leaked into the source.

---

## Phases as Role Movements

### What a phase transition really does

In the old formulation: "a transition consumes unresolved knowledge."

In GPS terms: "a transition moves fields from gen-shaping to param or state."

Those are the same thing said more precisely. "Unresolved knowledge" is gen-shaping facts. "Consuming" is turning them into param values or state declarations.

### Example: resolve phase

Source:

```
Editor.Send = (number id, number target_track_id, number gain_db) unique
```

- `target_track_id` is gen-shaping: it is an unresolved reference.

Resolved:

```
Resolved.Send = (number id, number target_track_id, number gain_db,
                 number target_bus_ix) unique
```

- `target_bus_ix` is now param: the reference was validated and the bus index computed.
- The gen-shaping fact (which track?) was consumed into a concrete param value (bus index 3).

### Example: schedule phase

Resolved:

```
Resolved.Node = (number id, NodeKind kind, Param* params) unique
```

- `NodeKind` is still gen-shaping: the variant choice shapes the machine.
- `params` contain gen-shaping values (user-set frequency, Q, etc.)

Scheduled:

```
Scheduled.Job = (number node_id, number kind_code,
                 number* coeffs, number in_bus, number out_bus,
                 number state_offset, number state_size) unique
```

- `kind_code` — param (variant consumed, encoded as number)
- `coeffs` — param (computed from user parameters + sample rate)
- `in_bus`, `out_bus` — param (buffer allocation resolved)
- `state_offset`, `state_size` — state declaration (runtime layout)
- Zero gen-shaping facts remain.

### The monotonic decrease

Each phase should have fewer gen-shaping facts than the previous one. This is the **narrowing property**.

```
Phase          Gen-shaping facts    Role movement
─────────      ─────────────────    ──────────────
Editor         12 sum types         (source — all gen-shaping)
Authored       8 sum types          lower: containers → graphs
Resolved       5 sum types          resolve: references validated
Classified     2 sum types          classify: rates assigned
Scheduled      0 sum types          schedule: all → param/state
Terminal       0 gen-shaping        compile: machines emitted
```

If a phase adds gen-shaping facts, something is wrong. You are creating decisions instead of consuming them.

### The terminal phase

The terminal phase has **zero gen-shaping facts**. Everything is param or state. The terminal's job is to define the execution machine — which is itself a GPS machine:

```lua
local compile_biquad = GPS.lower("compile_biquad", function(job)
    -- job has zero gen-shaping facts
    -- job.coeffs are param
    -- job.state_offset declares state layout

    local b0, b1, b2, a1, a2 = unpack(job.coeffs)

    return {
        gen = function(param, state, input)
            local y = param.b0 * input + param.b1 * state.x1 + param.b2 * state.x2
                                       - param.a1 * state.y1 - param.a2 * state.y2
            state.x2 = state.x1; state.x1 = input
            state.y2 = state.y1; state.y1 = y
            return state, y
        end,
        param = { b0 = b0, b1 = b1, b2 = b2, a1 = a1, a2 = a2 },
        state = { x1 = 0, x2 = 0, y1 = 0, y2 = 0 },  -- or FFI cdata
    }
end)
```

The execution machine is a GPS machine. Gen is the filter step. Param is the baked coefficients. State is the delay history — FFI cdata in production.

There is no separate "Unit" concept. The machine IS the artifact. The bottom transition(s) specialize it for the backend — on LuaJIT, that means making gen trace-friendly and state FFI-typed — but the result is still a GPS machine, not a different kind of thing.

No gen-shaping facts in the hot path. No variant dispatch. No name lookup. No dynamic decisions. Just gen reading param and mutating state.

That is what a clean terminal looks like.

### When transitions are GPS machines

For simple tree-shaped transforms, transitions are just recursive maps: transform each child, collect results, construct the output node.

But some transitions are naturally **irregular**:

- **Worklists**: process nodes from a queue, add new ones as discovered
- **Dataflow solvers**: propagate facts until fixed point
- **Graph traversals**: walk edges, track visited nodes
- **Frontier propagation**: spread information from changed nodes outward

For these, the transition itself is best expressed as a GPS machine:

```lua
local reach = GPS.lower("reach", function(request)
    return {
        gen = worklist_step,
        param = { graph = request.graph, index = build_index(request.graph) },
        state = { queue = { entry_id }, seen = {}, order = {} },
        finish = function(param, state) return ReachFacts(state.order) end,
    }
end)
```

Gen is the worklist step. Param is the stable graph environment. State is the frontier. The machine runs until the queue is empty.

This is much more honest than hiding the worklist inside a recursive function or a mutable object.

### The hybrid principle

Use both:

- **Structural transitions** for regular tree lowerings (simple, clear, canonical)
- **GPS machines** for irregular passes (worklists, solvers, graph walks)
- **Memoization** at boundaries between phases

The strongest pattern combines them:

```
per-node memoized summaries (structural boundary)
+
GPS worklist solver (irregular machine)
=
fine-grained incremental analysis
```

Summaries are stable local facts keyed by node identity. The solver orchestrates them. When the source changes, unchanged nodes hit the summary cache. Only the solver reruns.

---

## The Live Loop

### The six concepts

The architecture has six concepts. GPS is not an add-on — it is the unifying principle that makes the separate "proto" and "Unit" concepts unnecessary.

1. **Source ASDL** — the user's program (gen-shaping facts)
2. **Event ASDL** — what can happen (perturbations to gen-shaping facts)
3. **Apply** — pure state transition `(source, event) → source`
4. **Transitions** — memoized role movements (gen-shaping → param/state) — themselves GPS machines
5. **Terminals** — where all gen-facts are consumed — producing execution GPS machines
6. **GPS role system** — the structural type system that governs every level (gen-shaping / param / state)

There is no separate "Unit" concept. The running artifact IS a GPS machine.

There is no separate "proto language." Backend specialization is just the bottom transition(s) of the same pipeline — the same kind of GPS role movement as every other phase. Some pipelines need one realization step. Some need several. But they are not a different kind of thing.

### The loop

```
poll → apply → compile → execute
```

**Poll.** Read input from the world.

**Apply.** Pure reducer: `(source, event) → source`. Changes gen-shaping facts. Structural sharing preserves unchanged subtrees.

**Compile.** Re-run memoized transitions for affected subtrees. Move gen-shaping → param/state. Produce execution GPS machines. Realize them for the backend. This is incremental: unchanged subtrees hit the cache.

**Execute.** Drive the installed GPS machines. Audio callbacks. Draw loops. Parser steps. Each machine's gen is called with its param and state. That is execution.

**Repeat.** The program stays alive. The user keeps editing. The system keeps compiling incrementally.

### Why this eliminates infrastructure

**No state management framework.** The source ASDL is the state. Apply is the state transition. Done.

**No invalidation framework.** Memoization with structural identity. Unchanged nodes hit the cache. Changed nodes miss. No dirty flags.

**No observer bus.** Events are Event ASDL. Apply handles them. Compilation chases the consequences structurally.

**No dependency injection.** Every function gets what it needs from its ASDL input. If data is missing, add a phase to resolve it.

**No accidental interpreters.** Gen-shaping facts are consumed during compilation. Runtime does not rediscover semantics.

---

## The Bottom of the Pipeline

### There is no separate artifact type, and no separate proto language

In the older architecture, the compiler pipeline ended with three extra concepts:

- a "Machine" (gen/param/state) as the semantic product
- a "proto language" as a separate installation language
- a "Unit { fn, state_t }" as the collapsed installed artifact

That was three concepts for one job: making the machine run on the backend.

In the GPS architecture, those three concepts dissolve into one: **the bottom transition(s) of the same pipeline**.

```
Source ASDL           (all gen-shaping)
→ transition          (role movement)
→ transition          (role movement)
→ terminal            (zero gen-shaping → execution GPS machine)
→ backend transition  (specialize GPS for this backend)
→ backend-native GPS machine
→ host drives gen(param, state, ...)
```

Every arrow is the same kind of thing: a GPS-to-GPS transition that moves knowledge between roles. The backend transition is not special. It just happens to be last.

### What the backend transition actually does

The terminal produces a semantic GPS machine:

```
gen:    the execution rule (Lua function)
param:  stable compiled data (Lua tables, numbers)
state:  mutable layout (Lua tables)
```

The backend transition specializes it:

```
gen:    trace-friendly Lua function (monomorphic, no closures in hot path)
param:  upvalues or FFI-typed data (no hash lookups in hot path)
state:  FFI cdata with typed layout (no GC pressure)
```

This is a GPS-to-GPS transition. It takes gen-shaping facts about the backend ("which code form?", "which data representation?") and consumes them into concrete gen/param/state.

Same mechanism. Same discipline. Same GPS role movements.

### Thin vs rich backend transitions

Some machines need minimal backend work:

```
semantic machine
→ make state FFI-typed
→ done
```

One step. Gen is already trace-friendly. Param is already small. Only state needs specialization.

Other machines need more:

```
semantic machine
→ choose gen form (template? source kernel? direct closure?)
→ specialize param form (upvalues? bound payload? FFI struct?)
→ prepare state layout (FFI cdata definition)
→ backend-native GPS machine
```

Multiple steps. Each one is a GPS transition that consumes a backend gen-shaping fact.

The difference between "thin" and "rich" is just: how many backend gen-shaping facts exist. Not a different kind of architecture.

### What happened to the proto nouns

The old architecture had proto-specific nouns: template family, binding plan, artifact key, bytecode blob, shape key, install catalog.

Those concerns are real. But they are not a separate language. They are **fields in the backend transition's ASDL**, classified by GPS roles:

| Old proto noun | What it really is |
|---|---|
| template family | gen-shaping fact at the backend level (which execution skeleton?) |
| binding plan | param description (what gets bound where?) |
| shape key | gen identity (for memoization) |
| artifact key | gen + param identity (for caching) |
| bytecode blob | serialized form of gen |
| state layout descriptor | state declaration |
| install mode | gen-shaping fact (which realization strategy?) |

These are just fields. They follow the same GPS discipline as every other phase. They get consumed by the backend transition into a concrete GPS machine.

### Three LuaJIT backend strategies

All three are just different backend transitions. All produce GPS machines.

**Direct closure:**
Gen becomes a closure body. Param becomes upvalues. State becomes FFI cdata.

```lua
local b0, b1, b2, a1, a2 = ...  -- param as upvalues
local gen = function(state, input)
    local y = b0 * input + b1 * state.x1 + b2 * state.x2
                         - a1 * state.y1 - a2 * state.y2
    state.x2 = state.x1; state.x1 = input
    state.y2 = state.y1; state.y1 = y
    return y
end
-- state: ffi.new("struct { double x1, x2, y1, y2; }")
```

Gen is the closure. Param is baked into upvalues. State is FFI cdata. Still a GPS machine.

**Template → bytecode → bind:**

```
template_fn → string.dump(template) → load(blob) → debug.setupvalue(param)
```

Gen is the loaded bytecode. Param is bound via `debug.setupvalue`. State is allocated FFI cdata. Still a GPS machine.

**Source kernel:**

```lua
load(generated_source)
```

Gen is the loaded source (shaped for exact LuaJIT trace behavior). Still a GPS machine.

### Host contracts

Different runtime worlds drive GPS machines differently:

- **Audio host**: calls gen once per sample/block, provides input, expects output
- **View host**: calls gen once per frame, provides input events, expects draw commands
- **Network host**: calls gen per message, provides message, expects response

The host contract defines HOW the machine is driven. It does not change WHAT the machine is. The machine is always gen/param/state.

### Composition and fusion

When two child machines must run together, the parent is also a GPS machine. But the GPS separation enables something deeper: **fusion**.

Because gen is separate from param, and gen is cached by gen_key, the framework knows all children's gen functions at composition time. It can bake them as upvalues:

```lua
-- At compose time (only on gen_key change — rare):
local g1 = children[1].gen  -- captured as upvalue
local g2 = children[2].gen  -- captured as upvalue

parent.gen = function(param, state, input)
    local a = g1(param[1], state[1], input)   -- direct call, no lookup
    local b = g2(param[2], state[2], a)        -- direct call, no lookup
    return b
end
parent.param = { children[1].param, children[2].param }  -- rebindable
parent.state = { state_a, state_b }
```

Children's gens are **baked** (upvalues — stable, traced by LuaJIT). Children's params are **rebound** through the param table (changeable on knob turns). This is fusion by construction:

- No indirection through `param.children[i].gen` at runtime
- LuaJIT sees direct function calls and can trace through them
- One hot path, no dynamic dispatch
- Param changes (knob turns) do not rebuild the fused gen
- Only structural changes (add/remove child, change child's gen_key) rebuild

This is why the old Unit framework could not fuse: `Unit { fn, state_t }` collapses gen and param into one closure. Change param → new closure → new composition → fusion lost. GPS keeps them apart, so the fused gen survives across param changes.

### Hot swap with state preservation

When the source changes and a machine recompiles, the GPS framework compares gen_keys:

**Same gen_key** (most edits — knob turns, value changes):
- Keep the existing gen function
- Keep the existing runtime state (filter history preserved!)
- Rebind param only (new coefficients)
- No audible glitch. No state reallocation. No closure creation.

**Different gen_key** (rare — structural changes):
- Install new gen function
- Allocate new state
- Retire old state
- Full swap

This is managed by `GPS.slot`, which compares `machine.gen_key` on each update. The old Unit framework always did a full swap (new closure, new state, history lost). GPS preserves state when the machine's code shape hasn't changed.

---

## The gps.lua Framework

The insights above are not just conceptual. They are implemented in `gps.lua`, the GPS framework library. This section describes what it provides and how it works internally.

### The single boundary primitive: GPS.lower

There is no separate `transition` vs `terminal` distinction. Every phase boundary uses the same primitive:

```lua
local resolve_filter = GPS.lower("resolve_filter", function(node)
    -- upper phase: return an ASDL node
    return Resolved.Filter(node.id, node.mode, node.freq, node.q, lookup_sr())
end)

local compile_job = GPS.lower("compile_job", function(job)
    -- terminal: return a GPS machine
    return GPS.match(job, {
        BiquadJob = function(j)
            return GPS.machine(
                biquad_gen,
                { b0=j.b0, b1=j.b1, b2=j.b2, a1=j.a1, a2=j.a2 },
                GPS.state_ffi("struct { double x1, x2, y1, y2; }")
            )
        end,
        OscJob = function(j)
            return GPS.machine(
                osc_gen,
                { phase_inc = j.phase_inc },
                GPS.state_ffi("struct { double phase; }")
            )
        end,
    })
end)
```

Same API. Same shape. The framework detects whether the result is a GPS machine and applies the right caching strategy.

### The two-level cache

`GPS.lower` maintains two caches internally:

**Level 1: node identity** (weak table, keyed by ASDL node object)

If the exact same node is seen again, return the cached result instantly. This handles unchanged siblings — the nodes that structural sharing preserved. Same mechanism as the old `U.memoize`.

**Level 2: gen_key** (keyed by variant skeleton string)

If the node changed but the variant skeleton is the same, reuse the cached gen function and state layout. Only recompute param. This is the new mechanism that GPS adds.

The gen_key is extracted automatically by walking the ASDL node's fields:
- Sum-type children (things with `.kind`) contribute their variant tag
- Scalars (numbers, strings, booleans) are ignored
- Lists of sum-typed children contribute the list of their variant tags
- The result is a string like `"Filter|mode=LowPass"` or `"BiquadJob"`

Lua strings are interned by the VM, so same content = same object = efficient table key.

The cache flow:

```
GPS.lower called with input node
  │
  ├─ L1 hit (same node object)? → return cached result
  │
  ├─ L1 miss → run fn(input) → get result
  │   │
  │   ├─ result is GPS machine?
  │   │   │
  │   │   ├─ L2 hit (same gen_key)?
  │   │   │   → REUSE cached gen + state_layout
  │   │   │   → KEEP new param from result
  │   │   │   → return machine with reused gen
  │   │   │
  │   │   └─ L2 miss?
  │   │       → cache gen + state_layout by gen_key
  │   │       → return full result
  │   │
  │   └─ result is ASDL node?
  │       → cache by node identity (L1)
  │       → return result
```

### What the two levels mean in practice

Consider a user turning a frequency knob on a biquad filter:

1. `apply()` produces a new `Source.Filter` node (freq changed, everything else same)
2. All sibling nodes are the same objects → **L1 hits** everywhere except the changed filter
3. The changed filter misses L1 → `schedule_device` runs → new `BiquadJob` with new coefficients
4. `compile_job` is called with the new `BiquadJob` → L1 miss
5. gen_key = `"BiquadJob"` → **L2 hit** → reuse the biquad gen function and state layout
6. Only the new param (coefficients) is kept
7. `GPS.slot:update()` sees same gen_key → **rebinds param, preserves state**

Result: coefficient arithmetic + param rebind. No code generation. No state allocation. No audible glitch. Filter history preserved.

Now consider adding a new device to the chain:

1. `apply()` produces a new `Source.Track` with one more device
2. All unchanged devices → **L1 hits**
3. The new device → L1 miss → full compilation
4. The chain's gen_key changes (different list of variant tags) → **L2 miss**
5. New composed gen is built (children's gens baked as upvalues = fused)
6. `GPS.slot:update()` sees different gen_key → **full swap**, new state allocated

### GPS.machine — separated roles

The result of compilation is not an opaque `Unit { fn, state_t }`. It is a GPS machine with separated roles:

```lua
GPS.machine(gen, param, state_layout)
-- gen:          function(param, state, ...) → results
-- param:        table or cdata — stable payload the gen reads
-- state_layout: { alloc = fn, release = fn } — runtime state descriptor
-- gen_key:      string — set automatically by GPS.lower
```

Because gen and param are separate:
- The slot can rebind param without replacing gen
- The slot can preserve state when gen hasn't changed
- Compose can bake children's gens as upvalues while keeping params rebindable

### GPS.slot — gen-aware hot swap

```lua
local slot = GPS.slot()

-- First install
slot:update(compiled_machine)
-- → allocates state, installs gen + param

-- User turns knob (param-only change)
slot:update(recompiled_machine)
-- → detects: gen_key unchanged
-- → KEEPS state (filter history preserved)
-- → REBINDS param only (new coefficients)

-- User changes filter type (gen change)
slot:update(recompiled_machine)
-- → detects: gen_key changed
-- → ALLOCATES new state, retires old state
-- → FULL SWAP
```

The host drives the slot through a stable callback:

```lua
-- Audio callback just calls:
slot.callback(input_buffer, output_buffer, n)
-- Internally: current.machine.gen(current.machine.param, current.state, ...)
```

### GPS.compose — fusion by construction

```lua
local chain = GPS.compose({ osc_machine, filter_machine, gain_machine })
```

Internally, `GPS.compose` captures children's gen functions as upvalues:

```lua
local g1 = children[1].gen  -- baked
local g2 = children[2].gen  -- baked
local g3 = children[3].gen  -- baked

composed_gen = function(param, state, input)
    local r1 = g1(param[1], state[1], input)   -- direct call
    local r2 = g2(param[2], state[2], r1)        -- direct call
    local r3 = g3(param[3], state[3], r2)        -- direct call
    return r3
end
```

The composed gen_key is the concatenation of children's gen_keys. When a child's param changes (knob turn), the composed gen_key is unchanged, so the fused gen is reused. When a child is added or removed, the composed gen_key changes, and a new fused gen is built.

This is fusion for free from the GPS separation. The old Unit framework could not do this because `Unit { fn, state_t }` collapses gen and param into one closure — change param, get a new closure, lose the fused composition.

### GPS.leaf — curried machine builder

`GPS.leaf` separates gen (fixed) from param (computed) explicitly:

```lua
GPS.leaf(gen, state_layout, param_fn)
-- gen + state_layout are bound at definition time (the machine family)
-- param_fn runs at call time (extracts param from source node's scalars)
-- returns: function(node, ...) → GPS.machine(gen, param_fn(node, ...), state_layout)
```

This is the curried form of `GPS.machine`. The gen_key is set automatically by `GPS.match` (the variant name). No runtime gen_key extraction needed.

Usage:

```lua
GPS.lower("device", GPS.match {
    Osc = GPS.leaf(osc_gen, osc_state, function(d, sr)
        return { phase_inc = d.hz / sr }
    end),
    Filter = GPS.leaf(biquad_gen, biquad_state, function(d, sr)
        return compute_coeffs(d.mode, d.freq, d.q, sr)
    end),
    Gain = GPS.leaf(gain_gen, nil, function(d)
        return { gain = 10 ^ (d.db / 20) }
    end),
})
```

The framework sees three `GPS.leaf` declarations. Each has a fixed gen. The gen_key is the variant name chosen by `GPS.match`. No ASDL metadata walking. No string building. The curry structure tells the framework the gen_key at definition time.

### GPS.over — curried containment compiler

`GPS.over` mirrors the ASDL containment tree:

```lua
GPS.over(field_name, child_compiler, compose_fn)
-- Maps each child in node[field_name] through child_compiler
-- Composes the resulting machines
-- Default: GPS.compose (sequential pipeline with fusion)
```

Usage:

```lua
-- ASDL: Track = (... Device* devices ...) unique
GPS.lower("track", GPS.over("devices", compile_device))

-- With custom composition:
GPS.lower("project", GPS.over("tracks", compile_track, function(children, node)
    return GPS.compose(children, parallel_mix)
end))
```

One line per containment level. The ASDL field name (`"devices"`) + the child compiler + optional compose policy. The per-child caching, the gen_key composition, the fusion — all handled by the framework.

### The GPS tree IS the ASDL tree

With `GPS.leaf`, `GPS.match`, `GPS.over`, and `GPS.lower`, the compilation tree mirrors the ASDL containment tree exactly:

```
ASDL                              GPS tree
────                              ────────
Project                           GPS.lower("project",
  └── Track*                        GPS.over("tracks", compile_track))
        └── Device*                 GPS.lower("track",
              Osc | Filter | Gain     GPS.over("devices", compile_device))
                                    GPS.lower("device", GPS.match {
                                      Osc    = GPS.leaf(...),
                                      Filter = GPS.leaf(...),
                                      Gain   = GPS.leaf(...),
                                    })
```

The mapping:

| ASDL concept | GPS concept |
|---|---|
| Identity noun (`unique` with id) | `GPS.lower` boundary |
| Containment (`Child*` field) | `GPS.over(field, compiler)` |
| Sum type (`Osc \| Filter \| Gain`) | `GPS.match { variants }` |
| Variant arm | `GPS.leaf(gen, state, param_fn)` |
| Scalar field (`number freq`) | param value (inside `param_fn`) |

The user writes two things:
1. **Leaf machine builders** — what gen/param/state does each variant produce? (`GPS.leaf`)
2. **Composition policy** — how do siblings combine? (`GPS.over` with optional compose function)

Everything else — the tree structure, the caching boundaries, the gen_key computation, the state preservation, the fusion — comes from the ASDL shape plus the framework.

### Phases dissolve into fused pipelines

Traditional compiler architecture separates phases:

```
source → check → resolve → schedule → compile
```

Each phase is a separate memoized boundary with an intermediate ASDL node.

With GPS, those phases can fuse into one `GPS.lower` per identity noun:

```lua
local compile_device = GPS.lower("device", GPS.match {
    Filter = GPS.leaf(biquad_gen, biquad_state, function(d, sr)
        -- check: validate
        assert(d.freq > 0 and d.q > 0)
        -- resolve: attach context
        -- schedule: compute coefficients (consumes FilterMode!)
        local b0, b1, b2, a1, a2 = GPS.match(d.mode, {
            LowPass  = function() return compute_lp(d.freq, d.q, sr) end,
            HighPass = function() return compute_hp(d.freq, d.q, sr) end,
        })
        -- compile: the machine is the GPS.leaf result
        return { b0=b0, b1=b1, b2=b2, a1=a1, a2=a2 }
    end),
})
```

One boundary. Source device → GPS machine. No intermediate ASDL nodes. All conceptual phases (check, resolve, schedule, compile) fused into one pass. The two-level cache handles incrementality:
- L1: unchanged siblings hit the node cache
- L2: same gen_key (variant name) → reuse gen, recompute param

Separate phases are only needed when **multiple consumers** share an intermediate result (e.g., both audio and view pipelines need the resolved form).

### The complete API

| Primitive | Purpose | Replaces |
|---|---|---|
| `GPS.lower(name, fn)` | Memoized boundary, two-level cache | `U.transition` + `U.terminal` + `U.memoize` |
| `GPS.machine(gen, param, state_layout)` | GPS machine with separated roles | `U.new(fn, state_t)` |
| `GPS.leaf(gen, state, param_fn)` | Curried machine: gen fixed, param deferred | (new) |
| `GPS.match(arms)` | Curried dispatch, auto-sets gen_key | `U.match` |
| `GPS.over(field, compiler, compose_fn)` | Curried containment compiler | (new) |
| `GPS.slot()` | Hot swap with gen/param detection | `U.hot_slot()` |
| `GPS.compose(children)` | Structural composition with fusion | `U.compose_linear` |
| `GPS.with(node, overrides)` | Structural sharing | `U.with` |
| `GPS.errors()` | Error collection | `U.errors` |
| `GPS.state_ffi(ctype)` | FFI state layout | `U.state_ffi` |
| `GPS.app(config)` | The live loop | `U.app` |
| `GPS.report(boundaries)` | Cache diagnostics | (new) |

Iteration algebra: `GPS.drive`, `GPS.start`, `GPS.resume`, `GPS.finish`, `GPS.value`, `GPS.map`, `GPS.filter`, `GPS.take`, `GPS.fuse`.

### What the user writes

The entire compiler for a domain:

```lua
local compile_device = GPS.lower("device", GPS.match {
    Osc    = GPS.leaf(osc_gen, osc_state, extract_osc_param),
    Filter = GPS.leaf(biquad_gen, biquad_state, extract_filter_param),
    Gain   = GPS.leaf(gain_gen, nil, extract_gain_param),
})

local compile_track = GPS.lower("track",
    GPS.over("devices", compile_device))

local compile_project = GPS.lower("project",
    GPS.over("tracks", compile_track, function(children)
        return GPS.compose(children, parallel_mix)
    end))
```

Three declarations. The ASDL tree is visible. The variant dispatch is visible. The gen/param split is visible. Everything else is automatic.

### Diagnostics

```lua
print(GPS.report({ schedule_device, compile_job }))
```

Output:

```
schedule_device    calls=850   node_hits=847   gen_hits=3    gen_misses=3    gen_reuse=50%
compile_job        calls=850   node_hits=847   gen_hits=3    gen_misses=0    gen_reuse=100%
```

Reading: 850 edits. 847 were to unchanged siblings (L1 hits). 3 were to the changed filter. Of those 3, `compile_job` had 3 gen_key hits and 0 gen_key misses — meaning all 3 were param-only changes. Zero code regeneration. 100% gen reuse.

---

## The Convergence Cycle

### The lifecycle of an ASDL

The ASDL is never perfect on the first draft. It goes through a predictable lifecycle:

```
DRAFT → EXPANSION → COLLAPSE
```

### Draft

Top-down. List nouns, find variants, draw containment. All fields are gen-shaping. The draft captures the user's vocabulary but has not been tested against machines.

### Expansion

Bottom-up. Implement leaf machines. Each leaf says:

- "I need this resolved" → add a phase
- "I need this pre-computed" → add a field
- "I need this as a variant" → split a type
- "I need this as param, not gen-shaping" → the transition above must consume it

The type count grows. New phases appear. This is expected.

GPS makes expansion systematic: when a leaf's three questions are not answered by the IR above, you know exactly which role movement is missing.

### Collapse

Once all leaves work, patterns emerge:

- Variants that share structure merge
- Phases with the same verb merge
- Fields on multiple types become a shared header
- Types that existed because of UI naming, not machine need, collapse

GPS makes collapse safe: merge two types, re-check GPS roles. If the merge causes a gen-shaping fact to appear where there should be only param, the distinction was real. Undo the merge.

### Convergence criterion

The ASDL has converged when:

- every leaf's three GPS questions are answered cleanly
- memoize hit ratio > 90% for representative edits
- recent features are purely additive (one new variant + one new terminal)
- no existing phases or boundaries change

At that point, the ASDL is the architecture, and the architecture is done.

---

## Performance

### Three costs

Performance in this architecture has three costs:

1. **Semantic rebuild** — recomputing role movements in upper phases (gen-shaping → param/state)
2. **Backend specialization** — running the bottom transitions (GPS → backend-native GPS)
3. **Runtime** — driving the backend-native GPS machines

### GPS-informed diagnostics

| Symptom | GPS diagnosis | Fix |
|---|---|---|
| Small edit causes broad rebuild | gen-shaping facts too coarse | split identity boundaries |
| Terminal is slow | gen-shaping facts not consumed | add a phase |
| Runtime branches on variant | gen-shaping fact in hot path | consume it before terminal |
| Hot path does name lookup | param not pre-resolved | add resolve phase |
| Backend transition rediscovers meaning | gen-shaping fact leaked past terminal | fix terminal input |
| Trace exit on type check | gen-shaping in execution | monomorphize |
| NYI in hot path | param through untyped access | use FFI |
| Cache miss on unrelated edit | structural sharing broken | use GPS.with |

### The bake / bind / live split

GPS makes this mechanical:

| Classification | GPS role | When to use |
|---|---|---|
| Bake into code shape | gen-shaping → consumed | compile-time-known, shapes the rule |
| Bind as stable payload | param | compile-time-known, too large to inline |
| Keep as runtime-owned mutable | state | changes per call, execution-time data |

### The two-level hit ratio

With the GPS framework, there are two metrics, not one:

**Node hit ratio** (L1) — same as the old memoize hit ratio. Measures structural sharing quality. Should be 90%+.

**Gen reuse ratio** (L2) — of the L1 misses, how many reused the gen? Measures how often edits are param-only (knob turns) vs structural (adding/removing nodes). Should be high for interactive editing.

```
node hit ratio:  847 / 850 = 99.6%  (structural sharing working)
gen reuse ratio: 3 / 3 = 100%       (all edits were param-only)
```

If the gen reuse ratio is low, ask: are scalars being modeled as sum types unnecessarily? Is a phase failing to consume a sum type into scalars?

If the node hit ratio is low, the structural sharing is broken (same diagnosis as before).

---

## The Iteration Algebra

GPS is not just a decomposition. It is an **algebra** — a set of composable operations over machines.

### The primitives

```
value(x)                       — immediate result (degenerate machine)
drive(machine)                 — run to completion
start(machine) / resume / finish — step with control
```

### Transformers

```
map(machine, f)     — transform outputs
filter(machine, p)  — skip non-matching outputs
take(machine, n)    — first n outputs
drop(machine, n)    — skip first n
slice(machine, lo, hi) — subrange
reverse(machine)    — backward
zip(m1, m2)         — parallel walk
chain(m1, m2)       — sequential walk
flatten(m)          — expand nested machines
```

Each transformer returns a new GPS triple. No allocation of intermediate collections.

### Fusion

The deepest trick: push transformations into gen.

Map-fusion: return `f(x)` directly instead of materializing a mapped array.
Filter-fusion: skip inside gen instead of creating a filter wrapper.
Decode-fusion: unpack fields lazily as they are yielded.

Fusion eliminates intermediate data structures.

### Resumability

Because state is explicit data:

```lua
local run = GPS.start(machine)
GPS.resume(run, 10)    -- 10 steps
-- save run.state
-- later...
GPS.resume(run)        -- finish
return GPS.finish(run)
```

Pause. Save. Fork. Resume. All free.

### Budgeted execution

```lua
GPS.resume(run, budget)
```

Run at most `budget` steps. Then return control. Perfect for:

- cooperative scheduling
- long analyses split across frames
- incremental compilation
- interactive responsiveness during heavy computation

---

## What Gets Eliminated

The pattern eliminates infrastructure whose job was to reconnect truths that should never have been split apart.

### State management frameworks

Eliminated because: source ASDL is the state. Apply is the transition. GPS roles classify what is authored vs derived vs runtime.

### Invalidation frameworks

Eliminated because: structural identity + memoization. GPS roles tell you what can cause invalidation (gen-shaping and param changes) and what cannot (state changes).

### Observer buses

Eliminated because: events are typed Event ASDL. Apply handles them. Compilation chases consequences.

### Dependency injection

Eliminated because: every function gets what it needs from its ASDL input. Missing data → missing phase.

### Accidental interpreters

Eliminated because: gen-shaping facts are consumed during compilation. Any runtime dispatch on a gen-shaping fact is a GPS type error.

### Iterator object churn

Eliminated because: the GPS triple IS the iterator. No allocation needed.

### Ad hoc caching

Eliminated because: the two-level cache in GPS.lower handles it. L1 for node identity, L2 for gen_key. No per-subsystem cache design needed.

### Full-swap overhead

Eliminated because: GPS.slot detects gen vs param changes. Most interactive edits (knob turns, value changes) are param-only → state preserved, no reallocation. The old Unit framework always did a full swap.

### Implicit traversal state

Eliminated because: GPS makes traversal state explicit. No hidden call stacks, no closure-captured progress, no implicit cursors.

---

## Smells — GPS-Informed

Every code smell can be diagnosed through GPS roles.

| Smell | GPS diagnosis |
|---|---|
| String tags where enums belong | gen-shaping fact not typed |
| Derived values in source | param leaked into source |
| Context/environment arguments | gen-shaping fact not structurally resolved |
| Mutable accumulator in pure layer | should be GPS machine with explicit state |
| if/elseif on kind in boundary | gen-shaping fact not consumed by match |
| Lua tables as production state | state not typed for backend |
| Deep copy instead of GPS.with | memoization destroyed |
| Cross-references as pointers | gen-shaping fact as live ref |
| One boundary doing two things | missing phase (two role movements) |
| Sum type in hot path | gen-shaping fact not consumed before terminal |
| Unstable IDs | param identity broken |
| Buffer sizes in source ASDL | state declaration in source phase |
| Coefficients in source ASDL | param (derived data) in source phase |

**The GPS smell test:** for any function that feels wrong, ask:

1. Is it operating on gen-shaping facts that should have been consumed upstream?
2. Is it recomputing param that should be stable?
3. Is it managing state that should be declared by a machine?
4. Is it an implicit GPS machine that should be made explicit?

If any answer is yes, the fix is upstream — in the ASDL or phase structure, not in the code.

---

## Worked Examples

### Audio: biquad filter — full GPS trace

**Source (all gen-shaping):**

```
Editor.Filter = (number id, FilterMode mode, number freq, number q) unique
```

GPS roles: `id` gen-shaping, `mode` gen-shaping (sum type!), `freq` gen-shaping, `q` gen-shaping.

**Resolved (gen → param for sample_rate):**

```
Resolved.Filter = (number id, FilterMode mode, number freq, number q,
                   number sample_rate) unique
```

`sample_rate` was a context lookup. Now it is param. `mode` is still gen-shaping.

**Scheduled (all gen → param/state):**

```
Scheduled.BiquadJob = (number id,
    number b0, number b1, number b2, number a1, number a2,
    number state_offset) unique
```

`b0..a2` are param (computed from mode + freq + q + sample_rate). `state_offset` is state declaration. `FilterMode` was consumed — the coefficients encode the mode. Zero gen-shaping.

**Machine:**

```
gen:    y = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2
param:  { b0, b1, b2, a1, a2 }
state:  { x1, x2, y1, y2 }
```

**What GPS reveals:** the entire pipeline is a systematic movement from gen-shaping (what the user chose) to param (stable coefficients) to state (mutable delay history). Nothing mysterious. Nothing hidden.

### Text editor: keystroke → screen

**Source (gen-shaping):**

```
Editor.Document = (Block* blocks, Cursor cursor) unique
Editor.Block = Paragraph(Span* spans) | Heading(Span* spans, number level) | ...
```

**Event:**

```
InsertChar = (number block_id, number offset, string char)
```

**Apply:** produce new Document with one Block changed. All other blocks are the same objects (structural sharing).

**Compilation:**

```
Block → Resolved (font lookup → param)
      → Laid (text shaping + layout → param)
      → Draw commands → machine
```

Only the edited block recompiles. All other blocks hit the cache. One keystroke causes one block's role movement. Everything else is free.

**Machine for one line:**

```
gen:    draw glyph run
param:  { x, y, glyph_ids, advances, color }
state:  { gpu_cursor }
```

### Dataflow: liveness analysis — GPS-native

**Source (gen-shaping):**

```
Block = (number id, number* succ_ids, number* use_ids, number* def_ids) unique
```

All fields shape what liveness facts are computed.

**Summary (param — memoized per block):**

```
BlockSummary = (number id, number* use_ids, number* def_ids) unique
```

Local transfer function. Computed once per block. Cached by block identity.

**GPS solver:**

```
gen:    worklist step (process one block, propagate to predecessors)
param:  { graph, predecessor_index, block_summaries }
state:  { queue, in_sets, out_sets }
```

The solver is an explicit GPS machine. Summaries are memoized structural boundaries. When a block changes, only its summary recomputes. The solver reruns, but unchanged blocks' summaries are cached.

This is the **memoized-summary + GPS-solver** hybrid — the strongest pattern we discovered in our experiments.

---

## Machine IR and Lower Architecture

### Machine IR is GPS-typed

Machine IR is the typed layer immediately above the machine. Its job is to make the machine trivial to derive.

Every field should have a clear GPS role:

- gen-shaping facts → should be zero (consumed by prior phases)
- param → stable payload for the machine
- state declarations → runtime layout for the machine

If Machine IR still has gen-shaping facts, a phase is missing above it.

### Headers and facets

When multiple downstream machines share structural alignment:

**Header spine** — shared structural facts (all param):

```
View.Header = (number id, number parent_ix, number start_ix,
               number end_ix, NodeRole role) unique
```

**Facets** — orthogonal semantic planes (all param):

```
View.LayoutFacet = (number id, number x, number y, number w, number h) unique
View.PaintFacet = (number id, PaintKind paint, bool selected) unique
View.HitFacet = (number id, HitKind hit, number action_id) unique
```

Different machines consume different facets. Orthogonal edits stay local.

### Backend transition fields

When the backend transition has its own ASDL, the fields follow GPS roles:

| Backend field | GPS role |
|---|---|
| code form choice | gen-shaping (which execution skeleton?) |
| template family | gen-shaping (consumed into concrete gen) |
| binding plan | param description |
| shape key | gen identity (for memoization) |
| artifact key | gen + param identity (for caching) |
| bytecode blob | serialized form of gen |
| state layout descriptor | state declaration |

These are not a separate "proto language." They are fields in the backend transition's IR, consumed the same way every other phase consumes gen-shaping facts.

---

## The Master Checklist

### Domain

```
□ Listed every user-visible noun
□ Classified identity vs property
□ Each identity noun has a stable ID
□ No implementation nouns in source
```

### Sum types

```
□ Every "or" is an enum
□ No strings where enums belong
□ Every variant reachable
```

### GPS roles

```
□ Every source field classified as gen-shaping
□ No param or state leaked into source
□ Gen-shaping decreases monotonically through phases
□ Terminal input has zero gen-shaping facts
□ Every field at every phase has a clear GPS role
```

### Phases

```
□ Each phase named with a verb
□ Each verb describes a role movement
□ Later phases have fewer gen-shaping facts
□ Irregular passes use explicit GPS machines
```

### Quality

```
□ Save/load preserves all authored state
□ Undo: revert ASDL → everything restores
□ Every function testable with constructor + assertion
□ Memoize hit ratio > 90%
```

### Mandatory role audit

```
□ Every field classified as gen-shaping, param, or state declaration
□ No unclassified convenience fields
□ No mixed-role records without an explicit phase justification
□ For every phase, the consumed gen-shaping facts are named explicitly
□ Terminal input has zero gen-shaping facts
```

### Immediate rejection tests

```
□ No bag-of-fields IR carrying unresolved + derived + layout facts together
□ No runtime dispatch on gen-shaping facts in execution code
□ No hidden mutable semantic state in closures/objects/coroutines where a machine boundary should exist
□ No backend layout/state declarations leaked into source ASDL
```

### Machine design

```
□ Each terminal produces gen/param/state
□ Bake/bind/live split explicit via GPS roles
□ No gen-shaping facts in hot path
```

### Backend transitions

```
□ Backend specialization steps identified (thin or rich)
□ gen → trace-friendly code, param → typed payload, state → FFI/native layout
□ Backend gen-shaping facts consumed (code form, data form, layout form)
□ Backend concerns don't leak into source ASDL
```

### Trace quality (LuaJIT)

```
□ Gen is small with predictable control flow
□ Param through stable typed fields
□ State is numeric or FFI cdata
□ No closures created per step
□ No dynamic dispatch in hot path
```

---

## Summary

```
THE CENTRAL INSIGHT
    A function is a collapsed machine.
    gen / param / state is the unreduced form.

THE KEY DISCOVERY
    Sum types are gen-shaping. Scalars are param.
    The ASDL type system already encodes which is which.
    The variant skeleton IS the gen_key.
    No annotations needed. The schema does the work.

THE STRUCTURAL TYPE SYSTEM
    Sum-type fields are gen-shaping (they shape code).
    Scalar fields are param (they shape data).
    Phases consume sum types into scalars.
    When no sum-type fields remain, you have a machine.

THE SIX CONCEPTS
    Source ASDL          (sum types = gen-shaping, scalars = param)
    Event ASDL           (perturbations to source)
    Apply                (the only place source changes)
    Transitions          (consume sum types — GPS.lower everywhere)
    Terminals            (zero sum types → execution GPS machines)
    GPS role system       (sum types = gen, scalars = param, the ASDL knows)

    There is no separate "Unit" or "proto language."
    Backend specialization is just the bottom GPS.lower.
    GPS all the way down.

THE FRAMEWORK: gps.lua
    GPS.lower(name, fn)           — one primitive for every phase
    Two-level cache:              node identity + gen_key
    GPS.leaf(gen, state, param_fn)— curried: gen fixed, param deferred
    GPS.match { arms }            — curried dispatch, auto-sets gen_key
    GPS.over(field, compiler)     — curried containment, mirrors ASDL tree
    GPS.compose(children)         — fusion (children's gens as upvalues)
    GPS.slot()                    — gen-aware hot swap, preserves state

THE GPS TREE IS THE ASDL TREE
    Identity noun           → GPS.lower boundary
    Containment (Child*)    → GPS.over(field, compiler)
    Sum type variant        → GPS.match { GPS.leaf per variant }
    Scalar field            → param value inside param_fn
    The user writes: leaf machines + composition policy
    Everything else is automatic

THE THREE QUESTIONS
    What is the rule?     (gen — determined by sum types)
    What is stable?       (param — the scalars)
    What is live?         (state — mutable runtime data)

THE LIVE LOOP
    poll → apply → compile → execute
    Most edits are param-only: gen_key unchanged → reuse gen, rebind param
    State preserved. No glitch. No rebuild.

PHASES DISSOLVE INTO FUSED PIPELINES
    One GPS.lower per identity noun
    All conceptual phases fuse into one pass inside
    No intermediate ASDL nodes needed
    Separate phases only when multiple consumers share intermediate results

FUSION BY CONSTRUCTION
    GPS.compose bakes children's gens as upvalues
    Param stays runtime-rebindable
    One hot trace, no indirection
    Fusion survives across param changes

THE CONVERGENCE CYCLE
    Draft → Expansion → Collapse → Stable architecture

THE DEEPEST RULE
    The ASDL is the architecture.
    The GPS tree IS the ASDL tree.
    Sum types are gen-shaping. Scalars are param.
    Phases consume sum types into scalars.
    GPS.leaf fixes gen. GPS.match picks the variant. GPS.over walks the tree.
    The framework does the rest.
```

---

## Final Statement

> Gen-param-state is not merely an iterator convention, not merely a machine layer near the terminal, and not merely a Lua protocol.
>
> It is the minimal first-order model of executable semantics.
>
> A function is a collapsed machine. An iterator is an explicit one. A closure is a machine with hidden param. An object is a machine with hidden everything.
>
> GPS makes the hidden structure visible. And once it is visible, everything becomes clearer: what to cache, what to bake, what to allocate, where to put phase boundaries, how to test, how to make edits cheap, how to make execution fast.
>
> The deepest discovery is that the ASDL type system already encodes GPS roles. Sum types are gen-shaping — they determine which code runs. Scalars are param — they determine what data the code reads. And the GPS compilation tree IS the ASDL containment tree.
>
> `GPS.leaf` fixes gen and state at definition time, deferring param to call time. `GPS.match` dispatches on variants and sets the gen_key to the variant name — no runtime extraction needed. `GPS.over` maps children through their compilers and composes the results. The curried structure makes the gen/param split visible to the framework at definition time, not at runtime.
>
> Phases dissolve into fused pipelines. One `GPS.lower` per identity noun. All conceptual phases (check, resolve, schedule, compile) fuse into one pass inside. No intermediate ASDL nodes. The two-level cache handles incrementality: L1 for unchanged siblings, L2 for gen reuse on param-only changes. Most interactive edits are param-only: the gen_key doesn't change, the gen is reused, the state is preserved.
>
> Composition becomes fusion because gen is separate from param. `GPS.compose` bakes children's gens as upvalues — direct calls, one hot trace, no indirection. Param stays rebindable. The fused gen survives across knob turns. Fusion is not an optimization pass; it is what happens when machines are composed honestly with their roles separated.
>
> The user writes two things: leaf machine builders (`GPS.leaf` per variant) and composition policy (`GPS.over` with optional compose function). Everything else — the tree structure, the caching boundaries, the gen_key computation, the state preservation, the fusion — comes from the ASDL shape plus the framework.
>
> GPS all the way down. That is the complete story.

---

## API Reference

`require("gps")` returns the GPS module. ASDL is builtin — no external dependencies beyond LuaJIT.

### Quick Start

```lua
local GPS = require("gps")

-- 1. Create a context and define types
local T = GPS.context()
    :Define [[
        module Source {
            Project = (Track* tracks, number sample_rate) unique
            Track = (number id, string name, Device* devices, number volume_db) unique
            Device = Osc(number id, number hz) unique
                   | Filter(number id, FilterMode mode, number freq, number q) unique
                   | Gain(number id, number db) unique
            FilterMode = LowPass | HighPass | BandPass
        }
    ]]

-- 2. Install leaf machines on variant types
function T.Source.Osc:compile(sr)
    return GPS.machine(osc_gen, { phase_inc = self.hz / sr }, osc_state)
end

function T.Source.Filter:compile(sr)
    local coeffs = compute_coeffs(self.mode, self.freq, self.q, sr)
    return GPS.machine(biquad_gen, coeffs, biquad_state)
end

function T.Source.Gain:compile(sr)
    return GPS.machine(gain_gen, { gain = 10 ^ (self.db / 20) })
end

-- 3. Compile and run
local project = T.Source.Project({ ... }, 44100)
local machine = project:compile()
local slot = GPS.slot()
slot:update(machine)
slot.callback(...)  -- run the machine
```

### Modules

```lua
-- audio.lua — a GPS module
return function(T, GPS)
    function T.Source.Osc:compile(sr) ... end
    function T.Source.Filter:compile(sr) ... end
    function T.Source.Gain:compile(sr) ... end
end

-- main.lua
local T = GPS.context()
    :Define(schema_text)
    :use(require("audio"))
```

---

### ASDL (builtin)

#### `GPS.context(verb?)`

Create an ASDL context with GPS wiring. Returns a context object `T`.

- `verb` — the method name to wire up (default: `"compile"`)
- Calling `T:Define(text)` parses the ASDL schema and auto-generates:
  - **Sum type dispatch**: GPS.lower-wrapped per-child caching + gen_key = variant name
  - **Containment composition**: auto-compose children from `Child*` list fields

```lua
local T = GPS.context()
T:Define [[ module Source { ... } ]]
```

#### `T:Define(text)`

Parse ASDL text and create types. Returns `T` (chainable).

ASDL syntax:

```
module Name {
    Product = (Type field, Type* list_field, Type? opt_field) unique
    Sum = Variant1(Type field) unique
        | Variant2(Type field)
        | Singleton
}
```

- `unique` — structural interning (same args → same object)
- `*` — list field (plain Lua table)
- `?` — optional field (may be nil)
- Types: `number`, `string`, `boolean`, `table`, `any`, or other ASDL types
- Lists are plain Lua tables: `{ item1, item2, ... }`

#### `T:use(module)`

Load a module function `(T, GPS) → void` that installs methods on types. Returns `T` (chainable).

```lua
T:use(require("audio"))
T:use(function(T, GPS)
    function T.Source.Osc:compile(sr) ... end
end)
```

#### Constructed Values

```lua
local osc = T.Source.Osc(1, 440)
osc.kind     -- "Osc"
osc.id       -- 1
osc.hz       -- 440

T.Source.Device:isclassof(osc)  -- true
T.Source.Osc:isclassof(osc)    -- true

T.Source.LowPass        -- singleton value
T.Source.LowPass.kind   -- "LowPass"
```

---

### Grammar (builtin)

#### `GPS.grammar()`

Create a grammar builder. The grammar language is itself builtin ASDL.

```lua
local GPS = require("gps")
local G = GPS.grammar()
```

The builder exposes the `Grammar` constructors directly plus:

- `G:context()` — the grammar ASDL context
- `G:schema()` — the grammar ASDL text
- `G:compile(spec)` — compile a `Grammar.Spec`

You can also call `GPS.grammar(spec)` directly.

#### Grammar source language

```text
module Grammar {
    Spec = (Lex lex, Parse parse) unique

    Lex = (TokenDef* tokens, SkipDef* skip) unique
    TokenDef = Symbol(string text)
             | Keyword(string text)
             | Ident(string name)
             | Number(string name)
             | String(string name, string quote)

    SkipDef = Whitespace
            | LineComment(string open)
            | BlockComment(string open, string close)

    Parse = (Rule* rules, string start) unique
    Rule = (string name, Expr body) unique

    Expr = Seq(Expr* items)
         | Choice(Expr* arms)
         | ZeroOrMore(Expr body)
         | OneOrMore(Expr body)
         | Optional(Expr body)
         | Ref(string name)
         | Tok(string name)
         | Empty
}
```

Current fast subset:

- Lex: `Symbol`, `Keyword`, `Ident`, `Number`, `String`, `Whitespace`, `LineComment`, `BlockComment`
- Parse: `Seq`, `Choice`, `ZeroOrMore`, `OneOrMore`, `Optional`, `Ref`, `Tok`, `Empty`
- Left recursion is rejected
- Nullable repetition is rejected

#### Example

```lua
local GPS = require("gps")
local G = GPS.grammar()

local spec = G.Spec(
  G.Lex({
    G.Symbol("+"), G.Symbol("-"), G.Symbol("*"), G.Symbol("/"),
    G.Symbol("("), G.Symbol(")"),
    G.Number("NUMBER")
  }, {
    G.Whitespace
  }),
  G.Parse({
    G.Rule("Expr", G.Seq({
      G.Ref("Term"),
      G.ZeroOrMore(G.Seq({
        G.Choice({ G.Tok("+"), G.Tok("-") }),
        G.Ref("Term")
      }))
    })),
    G.Rule("Term", G.Seq({
      G.Ref("Factor"),
      G.ZeroOrMore(G.Seq({
        G.Choice({ G.Tok("*"), G.Tok("/") }),
        G.Ref("Factor")
      }))
    })),
    G.Rule("Factor", G.Choice({
      G.Tok("NUMBER"),
      G.Seq({ G.Tok("("), G.Ref("Expr"), G.Tok(")") }),
      G.Seq({ G.Tok("-"), G.Ref("Factor") })
    }))
  }, "Expr")
)

local P = G:compile(spec)
print(P:match("1 + 2 * 3"))
```

#### Compiled parser API

A compiled parser `P` provides:

- `P:match(input)` — fast recognizer, returns `true`/`false`
- `P:emit(input, sink)` — replay token/rule events on success
- `P:try_emit(input, sink)` — returns `ok, value_or_error`
- `P:reducer(actions)` — build a direct semantic reducer family
- `P:reduce(input, actions)` / `P:try_reduce(input, actions)`
- `P:tree(input)` / `P:try_tree(input)` — convenience tree mode
- `P:machine(input, mode?, arg?)` — produce a GPS machine

#### `GPS.parse(parser_or_spec, input, mode_or_actions?, arg?)`

Primary parse facade.

- If given a compiled parser family `P`, it drives that family
- If given a `Grammar.Spec`, it compiles it once per spec identity, then drives it
- Default mode is tree parse
- Passing an actions table is a reducer shortcut

```lua
local P = GPS.grammar(spec)

local tree  = GPS.parse(P, input)                -- same as P:tree(input)
local ok    = GPS.parse(P, input, "match")      -- recognizer
local value = GPS.parse(P, input, actions)       -- reducer shortcut
local n     = GPS.parse(P, input, "emit", sink) -- event replay
```

Also available:

- `GPS.parse.compile(parser_or_spec)`
- `GPS.parse.try(parser_or_spec, input, mode_or_actions?, arg?)`
- `GPS.parse.machine(parser_or_spec, input, mode?, arg?)`

Machine modes:

- `"match"` — recognizer machine
- `"emit"` — event machine (`arg = sink`)
- `"reduce"` — reducer machine (`arg = actions`)
- `"tree"` — tree machine

#### Reducers

Reducers are the fast semantic path: tokens and rules reduce directly to values.

```lua
local R = P:reducer {
  tokens = {
    NUMBER = function(source, start, stop)
      return tonumber(source:sub(start + 1, stop))
    end,
    ["+"] = function() return "+" end,
    ["*"] = function() return "*" end,
    ["("] = function() return nil end,
    [")"] = function() return nil end,
  },
  rules = {
    Expr = function(v) ... end,
    Term = function(v) ... end,
    Factor = function(v) ... end,
  }
}

local value = R:parse("1 + 2 * 3")
```

#### Emit sinks

```lua
P:emit(input, {
  token = function(self, name, source, start, stop) ... end,
  rule  = function(self, name, source, start, stop) ... end,
})
```

Events are replayed only after a successful parse.

#### Low-level lexer/parser helpers

For lower-level use, the module also exposes:

- `GPS.lex(spec)` — build a GPS-native lexer from a simple spec table
- `GPS.rd(lexer, input, grammar_fn)` — manual fused recursive-descent helper

These are the low-level tools. `GPS.grammar` + `GPS.parse` are the primary parser path.

---

### Machines

#### `GPS.machine(gen, param, state_layout, gen_key?)`

Create a GPS machine with separated roles.

- `gen` — `function(param, state, ...) → results`. The execution rule.
- `param` — table or cdata. Stable payload the gen reads.
- `state_layout` — `{ alloc = fn, release = fn }` or `nil`. Mutable runtime state descriptor.
- `gen_key` — string. Set automatically by `GPS.lower` / `GPS.match` / `GPS.compose`.

```lua
local m = GPS.machine(
    function(param, state, input)
        return input * param.gain
    end,
    { gain = 0.5 },
    GPS.state_ffi("struct { double x; }")
)
```

#### `GPS.is_machine(value)`

Returns `true` if `value` is a GPS machine.

#### `GPS.state_ffi(ctype, opts?)`

Create an FFI-backed state layout.

```lua
GPS.state_ffi("struct { double x1, x2, y1, y2; }")
GPS.state_ffi("struct { double phase; }", { init = function(s) s.phase = 0 end })
```

#### `GPS.state_table(init?, release?)`

Create a table-backed state layout.

```lua
GPS.state_table(function(s) s.count = 0; return s end)
```

---

### Compilation Boundaries

#### `GPS.lower(name, fn)`

Create a memoized boundary with two-level cache. The single primitive for every phase.

- **Level 1** — node identity cache (unchanged siblings hit instantly)
- **Level 2** — gen_key cache (param-only changes reuse gen + state_layout)

```lua
local compile_device = GPS.lower("compile_device", function(device, sr)
    return GPS.machine(gen, { freq = device.freq }, state)
end)
```

Returns a callable with `.stats()` and `.reset()`.

```lua
local s = compile_device.stats()
-- s.name, s.calls, s.node_hits, s.gen_hits, s.gen_misses
```

#### `GPS.leaf(gen, state_layout, param_fn)`

Curried machine builder. Gen + state fixed at definition time, param computed at call time.

```lua
local build_osc = GPS.leaf(osc_gen, osc_state, function(node, sr)
    return { phase_inc = node.hz / sr }
end)
local machine = build_osc(osc_node, 44100)
```

#### `GPS.match(value, arms)` — direct dispatch

```lua
local b0 = GPS.match(mode, {
    LowPass  = function() return 0.5 end,
    HighPass = function() return 0.3 end,
})
```

#### `GPS.match(arms)` — curried dispatch

Returns a function. Auto-sets `gen_key = variant name` on machine results.

```lua
local compile = GPS.match {
    Osc  = GPS.leaf(osc_gen, osc_state, extract_osc_param),
    Gain = GPS.leaf(gain_gen, nil, extract_gain_param),
}
local machine = compile(device_node, sr)
```

---

### Runtime

#### `GPS.slot()`

Hot swap slot with gen/param-aware state preservation.

```lua
local slot = GPS.slot()
slot:update(machine)          -- install or update
slot.callback(...)            -- call the current machine
slot:update(new_machine)      -- same gen_key → rebind param, KEEP state
                              -- different gen_key → full swap, new state
slot:peek()                   -- returns machine, state
slot:collect()                -- release retired state
slot:close()                  -- release everything
```

#### `GPS.compose(children, body_fn?)`

Structural composition with fusion. Children's gens are baked as upvalues.

```lua
-- Sequential pipeline (default)
local chain = GPS.compose({ osc_machine, filter_machine, gain_machine })

-- Custom composition
local mix = GPS.compose(track_machines, function(child_gens, param, state, input)
    local sum = 0
    for i = 1, #child_gens do
        sum = sum + child_gens[i](param[i], state[i], input)
    end
    return sum
end)
```

Composite `gen_key` = concatenation of children's gen_keys.

#### `GPS.app(config)`

The live loop: poll → apply → compile → execute.

```lua
GPS.app {
    initial = function() return source end,
    apply = function(source, event) return new_source end,
    compile = {
        audio = function(source) return machine end,
    },
    poll = function() return event end,
    start = { audio = function(callback) ... end },
    stop  = { audio = function() ... end },
}
```

---

### Structural Helpers

#### `GPS.with(node, overrides)`

Create a new ASDL node with some fields changed. Structural sharing.

```lua
local new_filter = GPS.with(filter, { freq = 3000 })
-- filter.freq = 2000, new_filter.freq = 3000
-- filter.mode is the same object (shared)
```

#### `GPS.errors()`

Error collector for boundary functions.

```lua
local errs = GPS.errors()
local results = errs:each(items, function(item)
    return item:compile()
end)
errs:add("manual error")
errs:merge(child_errors)
local error_list = errs:get()  -- nil if no errors
```

---

### Iteration Algebra

Zero-allocation streaming over `(gen, param, state)` triples. Compatible with Lua's generic `for` loop.

#### `GPS.filter(gen, param, state, pred)`

```lua
local g, p, s = GPS.filter(lexer.tokens(input), function(kind) return kind == NUMBER end)
for pos, kind, start, stop in g, p, s do ... end
```

#### `GPS.take(gen, param, state, n)`

```lua
local g, p, s = GPS.take(lexer.tokens(input), 10)
```

#### `GPS.map(gen, param, state, fn)`

```lua
local g, p, s = GPS.map(gen, param, state, function(v) return v * 2 end)
```

#### `GPS.fuse(outer_fn, inner_gen, inner_param, inner_state)`

```lua
local g, p, s = GPS.fuse(tonumber, lex_gen, lex_param, 0)
```

#### `GPS.drive(gen, param, state)`

Run to completion, return last value.

---

### Collection Helpers

#### `GPS.map_list(items, fn)`

```lua
local machines = GPS.map_list(track.devices, function(d) return d:compile(sr) end)
```

#### `GPS.each(items, fn)` / `GPS.fold(items, fn, init)` / `GPS.find(items, pred)`

Standard collection operations.

---

### Diagnostics

#### `GPS.report(boundaries)`

```lua
print(GPS.report({ compile_device, compile_track }))
-- compile_device    calls=850   node_hits=847   gen_hits=3   gen_misses=0   gen_reuse=100%
```

---

### Module Layout

```
gps/
  init.lua            the framework
  asdl_context.lua    type builder (constructors, interning, sum types)
  asdl_parser.lua     ASDL parser (lexer fused in param)
  asdl_lexer.lua      ASDL lexer (gen/param/state over FFI bytes)
  lex.lua             general-purpose GPS-native lexer toolkit
  rd.lua              low-level fused recursive-descent helper
  parse.lua           primary parser facade over compiled grammars
  grammar.lua         grammar compiler: grammar ASDL → fused lexer+parser
  README.md           this document
```

Zero external dependencies. ~2700 lines. Self-hosted: the ASDL parser is itself a GPS machine.
