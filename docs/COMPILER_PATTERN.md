# Interactive Software as Compilers

---

## Part 1: The Claim

### 1.1 Every interactive program is a compiler

An interactive program takes human gestures — clicks, keystrokes, edits,
messages — and turns them into machine behavior — pixels, samples,
network bytes, driver calls.

Between what the user said and what the machine does, there is a gap.
The user thinks in domain concepts: make this louder, insert a paragraph,
connect these nodes. The machine thinks in registers, buffers, and
function pointers.

Traditional systems bridge the gap at runtime. Every frame, every
callback, they re-traverse authored structure and re-answer:

> What does this node mean, really?

The compiler pattern bridges the gap earlier. Authored structure is the
source program. Memoized phase boundaries compile it into progressively
narrower representations. The narrowest representation is consumed by
a loop. When the source changes, only the affected subtrees recompile.
Everything else is cached.

That is the claim:

> Interactive software is a live compiler from authored intent to
> executable facts, where phases gather facts as iterators, caching is
> a side effect of full iteration, and a loop is the only execution.

### 1.2 The ASDL is a language

The ASDL is not a data format. It is the input language of the compiler.

The user is the programmer. The UI is the IDE. Every gesture is a program
edit. Every edit produces a new source program — a new ASDL tree. The
compiler compiles it. The output runs.

A good input language has clear nouns, clear verbs, orthogonal features,
completeness, minimality, and composability. These are the same properties
that make a programming language good, because the source ASDL IS a
domain-specific programming language whose programs are domain artifacts
— songs, documents, spreadsheets, scenes, tools — and whose compiler
produces the facts needed to realize them.

The ASDL is the architecture. Everything else is downstream.

### 1.3 The gap has layers

The gap between authored intent and machine execution is never one step.
There are intermediate levels of knowledge:

```
User intent:      "a track with a muted kick drum"
  ↓
Domain vocabulary: Track("Kick", mute=true, ...)
  ↓
Layout vocabulary: Column(spacing=0, [Rect("header", ...), ...])
  ↓
Positioned facts:  PushTransform(0, 48), Rect("row", ...), PopTransform, ...
  ↓
Execution:         for _, fact in phase(source) do draw(fact) end
```

Each layer consumes knowledge. Each boundary exists because a real
question is being answered. The number of layers equals the number of
distinct knowledge-resolution levels the domain actually has. Not more.
Not fewer.

### 1.4 The hard part

The framework primitives — ASDL, phase, once, with, for-loop — are tools.
They do not tell you what to model, where knowledge is consumed, or how
many layers you need.

That is the hard part. And it must be done correctly, because a wrong type
at the source layer propagates through every boundary, every computation,
every for-loop. The cost compounds.

---

## Part 2: The Five Concepts

### 2.1 Source ASDL

What the program IS. The user-authored, persistent, saveable model of the
domain.

In a music tool: tracks, clips, devices, parameters.
In a text editor: document, blocks, spans, selections.
In a UI system: widgets, layout declarations, style tokens.

The source ASDL answers: what did the user author? What survives
save/load? What does undo restore? It must contain exactly the user's
authored choices — no more (no derived data, no backend scaffolding),
no less (no lost preferences, no invisible state).

### 2.2 Event ASDL

What can HAPPEN to the program. Input modeled as a language, not as
callbacks.

Pointer moved. Key pressed. Node inserted. Selection changed. Parameter
edited. File opened. Transport started.

Events are architectural because they define how the source evolves. They
are typed, closed, exhaustive — every possible input has a variant.

### 2.3 Apply

The pure reducer:

```
Apply : (state, event) → state
```

Apply does not mutate. It takes the current source and an event and
returns the next source. Purity gives: undo by storing the previous
root, structural sharing through `pvm.with`, coherent memoization
(same input → same output → skip), and tests by constructor + assertion.

### 2.4 Phases

A phase is a fact-gathering iterator over the source.

It asks: "What facts does this node produce?" The answer is an iterator
— a triplet `(gen, param, state)` that yields zero or more facts when
pulled. The facts might be draw commands, sizes, HTML fragments, audio
samples, bytecodes — whatever the phase computes.

```lua
local render = pvm.phase("render", {
    [T.App.Button] = function(self)
        return pvm.once(Rect(self.tag, self.bg))
    end,
    [T.App.Panel] = function(self)
        return pvm.children(render, self.children)
    end,
})
```

Every handler returns a triplet. `pvm.once` wraps a single fact.
`pvm.children` maps the phase over children and concatenates their
triplets. `pvm.empty()` returns zero facts. `pvm.concat2/3/all`
composes multiple triplets.

Caching is a side effect of iteration. On miss, the handler runs and
its output is recorded as the consumer pulls. When fully consumed, the
recording commits to cache. On hit, the cache replays instantly via
`seq_gen` over the cached array. The consumer cannot distinguish a hit
from a miss — same interface, same protocol.

Phases compose by nesting. A render handler calls `render(child)`. If
the child hits cache, the parent gets `seq_gen` — array index increment.
If the child misses, the parent gets a recording triplet. The triplets
nest. The outermost consumer pulls through all of them in one fused
pass. There is no intermediate collection. Values flow from the deepest
handler directly to the consumer.

### 2.5 The loop

The final consumer is a loop:

```lua
for _, fact in phase(source) do
    act(fact)
end
```

That is the entire execution model. The loop pulls facts. Facts flow
through nested iterators. Handlers fire on miss. Caches replay on hit.
Draw calls happen. Buffers fill. HTML streams to a socket.

The loop is the only thing that runs. Everything else — caching, fusion,
structural identity, lazy evaluation — is machinery that makes the
iterator fast. The loop doesn't know about any of it. It pulls a fact.
It acts on the fact. It pulls the next.

### 2.6 The live loop

The five concepts yield the live loop:

```
poll → apply → phase(source) → loop
```

**poll** — read input from the outside world.
**apply** — pure reducer produces the next source.
**phase(source)** — return a fact-gathering iterator. Nothing evaluates yet.
**loop** — pull facts, act on them. Caches fill as a side effect.

This is incremental compilation as a consequence of architecture. When
nothing changes, the phase returns cached facts. When one thing changes,
the phase returns cached facts for unchanged subtrees and fresh facts
for the changed subtree. The cost is proportional to the change, not
the tree.

---

## Part 3: Why Iterators

### 3.1 The three roles

Lua's generic `for` loop decomposes iteration into three values:

```lua
local gen, param, state = phase(source)
while true do
    local next_state, value = gen(param, state)
    if next_state == nil then break end
    state = next_state
    -- use value
end
```

`gen` is the step function — how to get the next fact.
`param` is the invariant environment — the data being traversed.
`state` is the mutable cursor — where we are now.

These three roles are orthogonal. Same gen, different param → traverse
a different collection the same way. Same gen, different state → resume
from a different position. Different gen, same param → traverse the same
collection a different way.

This decomposition is not an abstraction layered over execution. It IS
execution factored into its three irreducible roles. Every running thing
decomposes this way:

| Domain | gen | param | state |
|--------|-----|-------|-------|
| Audio filter | filter equation | coefficients | delay history |
| Parser | parse rule | grammar tables | position + stack |
| UI render | draw step | layout plan | cursor through tree |
| Compiler pass | transform rule | input IR | traversal cursor |

### 3.2 Fusion

When one phase handler calls another phase, the inner phase returns a
triplet. The outer handler wraps it in its own triplet. The consumer
pulls through both. There is no intermediate array. No temporary
collection. Values flow from the inner handler through the outer handler
to the consumer.

```lua
[T.App.Panel] = function(self)
    return pvm.concat2(
        pvm.once(background_rect),
        pvm.children(render, self.children))
end
```

`pvm.children(render, self.children)` maps the render phase over
children and concatenates their outputs. Each child returns a triplet.
The triplets nest inside the parent's `concat2`. The outermost loop
pulls through all of them. One traversal. One loop.

A traditional pipeline — build tree, then layout, then render, then
draw — allocates three intermediate data structures and traverses four
times. The iterator approach allocates zero intermediate structures and
traverses once.

### 3.3 Laziness

Nothing computes until the loop pulls. If the loop stops early (found a
hit test target, filled a buffer, reached a limit), everything stops.
No wasted work. No cleanup. No cancel signal.

```lua
-- stop after finding the first visible element
for _, cmd in render(root) do
    if is_visible(cmd) then return cmd end
end
```

Handlers deeper in the tree never fire. Their sub-phases never run.
Their children are never visited. The cost is proportional to what was
consumed, not the size of the tree.

This is virtualization for free. A list with 10,000 items where 20 are
visible — if the handler only yields visible items, only 20 handlers
run. The other 9,980 are never entered.

### 3.4 Caching as a property of iteration

In pvm, caching is not a separate mechanism. Caching is what happens
when you fully consume a recording triplet.

On miss: the handler returns a triplet. The phase wraps it in a
recording gen. As the consumer pulls values, each is recorded. When
the consumer exhausts the triplet, the recorded values commit to cache.

On hit: the phase returns `seq_gen` over the cached array. The consumer
pulls values from the array. Same interface. Same protocol.

The consumer doesn't configure caching. Doesn't call a cache API.
Doesn't declare dependencies. It iterates, and caching happens. Stop
iterating, and the partial recording doesn't commit — also correct.
The iteration protocol IS the caching protocol.

### 3.5 Sharing

When two parts of the tree reference the same node, and the first
renders it (miss, recording starts), and the second asks for it during
the same drain — the second gets a reader over the in-flight recording.
Same values. No duplicate work.

This falls out of the iterator protocol. Two consumers of the same
triplet source. The recording is the shared state. pvm.report shows it
as the "shared" stat.

### 3.6 Composition

Every combinator takes triplets and returns triplets. The algebra is
closed:

```
pvm.once(v)              → triplet (one element)
pvm.empty()              → triplet (zero elements)
pvm.children(phase, arr) → triplet (mapped concatenation)
pvm.concat2(t1, t2)      → triplet (sequential)
pvm.concat_all(ts)       → triplet (N-way sequential)

T.map(f, g, p, c)        → triplet
T.filter(pred, g, p, c)  → triplet
T.flatmap(f, g, p, c)    → triplet
T.take(n, g, p, c)       → triplet
T.scan(f, acc, g, p, c)  → triplet
T.zip(t1, t2)            → triplet
```

A handler can combine these freely. Filter by visibility. Map
coordinates. Interleave separators. Limit to first N. Zip with metadata.
Every combination produces a triplet. The caching wraps it. The fusion
composes through it. The consumer pulls through it.

### 3.7 Memory

At any point during the pull, only the path from root to current leaf
is live on the stack. Completed subtrees are cached arrays. Future
subtrees are pending handler calls. The live memory during traversal
is O(depth), not O(tree size).

### 3.8 LuaJIT traces through it

LuaJIT's generic `for` has dedicated bytecodes for `gen(param, state)`.
They expect three roles: step function, invariant value, changing
control value. That is `gen, param, state`.

For cache hits, the trace sees `seq_gen`: array index increment, bounds
check, return value. Compiles to tight native code. For recording hits,
the trace follows the handler. Adjacent misses fuse — one trace through
the entire chain.

---

## Part 4: Designing the Source

### 4.1 Step 1: List the nouns

Open the program. Look at every element the user sees and interacts with.
Write down every noun.

For a DAW:
```
project, track, clip, audio clip, MIDI clip, note, device, effect,
instrument, parameter, automation, breakpoint, send, bus, tempo,
time signature, marker, transport, selection, mute, solo, volume, pan
```

For a text editor:
```
document, paragraph, heading, list, code block, span, bold, italic,
link, cursor, selection, font, indent, bookmark
```

### 4.2 Step 2: Find the entities

Not all nouns are equal. Some are THINGS with identity — the user can
point to them and say "that one." Others are PROPERTIES of things.

```
DAW:
    ENTITIES: project, track, clip, device, parameter, send, automation
    PROPERTIES: volume, pan, mute, solo, frequency, Q, tempo value
```

Entities become ASDL records. Properties become fields on those records.

### 4.3 Step 3: Find the sum types

Every "or" in the domain is a sum type:

```
A clip is an audio clip OR a MIDI clip.
A device is a native device OR a plugin.
A selection is a cursor OR a range.
A transport is stopped OR playing OR recording.
```

Each "or" becomes a sum type with variants. Each variant has its own
fields. No strings where sums belong. Every boolean flag that constrains
another boolean is a sum type trying to escape.

### 4.4 Step 4: Draw the containment tree

Domain objects contain other domain objects. The containment forms a tree:

```
Project
└── Track*
    ├── DeviceChain → Device*
    │                  └── Parameter*
    ├── Clip*
    └── AutomationLane* → Breakpoint*
```

Containment is the default. If a relationship is ownership, model it.
If it's a cross-link (a send referencing another track), use a stable ID
and resolve it in an explicit phase.

### 4.5 Step 5: Find the coupling points

Coupling points are where independent subtrees need information from each
other. They determine boundary ordering:

```
Send ←→ Track: sends reference tracks by ID → resolve after all tracks defined
Text ←→ Layout: text wrap depends on width, layout depends on text height → same pass
Formula ←→ Cell: circular references → dependency analysis is its own phase
```

### 4.6 Step 6: Define the phases

Phases are ordered by knowledge. Each phase knows everything the previous
knew, plus the decisions it resolved.

A layer boundary exists where the vocabulary changes — where the types on
one side answer a different question than the types on the other. The
number of layers equals the number of distinct questions the domain
actually asks between source and execution:

```
DAW:
    Source: all user vocabulary, all sum types
    → "what are the resolved connections?"
    Resolved: cross-references validated
    → "what is the execution schedule?"
    Scheduled: buffer slots, execution order
    → "what should be drawn / played?"
    Facts: flat audio + view output

Text editor:
    Source: blocks with spans
    → "where does everything go?"
    Laid: positions computed, text shaped
    → "what should be drawn?"
    Facts: flat draw output
```

Each transition has a verb: lower, resolve, schedule, compile, layout.
The verb names the question being answered. If you cannot name the verb,
the boundary should not exist.

Layers are not mandatory per recursive type. A single phase can handle
multiple recursive type families if they answer the same question. You
choose to separate them when the questions are genuinely different and
benefit from independent caching.

### 4.7 Test the source ASDL

Before writing any phase:

**Save/load.** Serialize to JSON and back. Is every user-visible aspect
restored? If something is lost, a field is missing.

**Undo.** Revert to the previous root. Because `unique` gives structural
identity, the reverted root IS the same object. Every phase returns
cached facts instantly. The entire program reverts with zero recompilation.

**Completeness.** Can the user create every variant? If a variant is
unreachable through the UI, it shouldn't exist.

**Minimality.** Is there a user action that changes ONLY this field?
If not, it may be derived (belongs in a later phase) or bundled with
another field.

**Orthogonality.** Can these two fields vary independently? If not,
they may hide a sum type.

**Testability.** Can every function be tested with one ASDL constructor
and one assertion? If it needs mocks, fixtures, or context setup, the
ASDL is incomplete.

---

## Part 5: Recursion, Flattening, and the Iterator

### 5.1 What recursion is

A phase calls itself on children:

```lua
[T.App.Panel] = function(self)
    return pvm.children(render, self.children)
end
```

That is recursion. But look at what happens. `pvm.children(render,
self.children)` constructs a triplet. Each child's `render` call
returns a sub-triplet. The sub-triplets are concatenated. The consumer
pulls through the concatenation and sees a flat stream.

The recursion IS the iterator nesting. Each recursive call adds a
nesting level. Each nesting level is a cache boundary. The consumer
sees a flat sequence. The nesting is invisible.

Recursion is not something to be "solved" or "eliminated." Recursion
is what turns a tree into a flat stream. The phase walks the tree by
calling itself on children. Each call returns an iterator. The iterators
nest. The consumer pulls through the nesting and gets flat facts out.

`pvm.children` is a flatmap — map a phase over children, flatten the
results. A tree of nested flatmaps produces a flat stream. This is what
iterators do. There is no separate "flattening step." The recursion IS
the flattening.

### 5.2 The canonical form

> A tree becomes a flat stream when a recursive phase wraps each
> container's children in push/pop markers.

```lua
[T.UI.Clip] = function(self)
    return pvm.concat3(
        pvm.once(PushClip(self.w, self.h)),
        pvm.children(render, self.children),
        pvm.once(PopClip))
end

[T.UI.Rect] = function(self)
    return pvm.once(Rect(self.visual))
end
```

The consumer sees:

```
PushClip(800, 600)
  Rect(visual_1)
  Rect(visual_2)
PopClip
```

Flat. No tree structure. Containers are push/pop pairs. Leaves are
single facts. The phase produced this by recursion — calling itself on
children, wrapping them with push before and pop after. The iterator
nesting did the flattening.

### 5.3 State is always a stack

When containment linearizes to push/pop, the only state the consumer
needs is: what containers are currently open?

That is a stack.

```lua
local transform_stack = { {0, 0} }

for _, fact in render(root) do
    if fact.kind == K_PUSH_TRANSFORM then
        local top = transform_stack[#transform_stack]
        transform_stack[#transform_stack + 1] = {
            top[1] + fact.x, top[2] + fact.y }
    elseif fact.kind == K_POP_TRANSFORM then
        transform_stack[#transform_stack] = nil
    elseif fact.kind == K_RECT then
        local t = transform_stack[#transform_stack]
        draw_rect(t[1], t[2], fact.visual)
    end
end
```

The stack is the only state shape because it is a mathematical
consequence. Containment is nesting. Nesting linearizes to push/pop.
Push/pop is a stack.

If the consumer needs complex mutable state beyond push/pop stacks,
either the phase didn't resolve enough, or the state comes from a
genuine runtime concern (physics, audio delay) separate from the
authored structure.

### 5.4 Why layers exist

If recursion is just iterator nesting, and iterator nesting is free
(fusion, caching, laziness all work through it), then why have layers
at all? Why not one phase that handles everything?

You could. A single phase can dispatch on both App.Widget types AND
UI.Node types. The iterator nesting handles the recursion through both
type families. Cache hits work at every level.

So layers are not about recursion classes. **Layers are about where
vocabulary changes.** A boundary exists when the types on one side
answer a different question than the types on the other.

App.Widget types answer: "what does the user want?"
UI.Node types answer: "what layout structure does that require?"
D.Cmd facts answer: "what should be drawn?"

These are different questions. Each question is a different vocabulary.
The boundary between vocabularies is a phase that translates.

But the boundary is not mandatory. You choose to separate vocabularies
when they are complex enough to deserve their own types and their own
cache domain. You choose to merge them when the domain is simple enough
that the intermediate vocabulary adds nothing.

The practical test: does the intermediate vocabulary enable caching that
wouldn't exist without it? If App.Widget → UI.Node means ten widgets
share the same UI.Node subtree (because they have the same layout but
different domain meanings), the cache hits on the shared layout. That
caching wouldn't exist without the intermediate vocabulary. The layer
earns its existence.

If the intermediate vocabulary is 1:1 with the source vocabulary (every
widget maps to one unique layout node that nothing else shares), the
layer adds overhead without benefit. Skip it.

### 5.5 Transform stacks enable per-node caching

If facts carry absolute positions, a sibling's size change cascades
position changes to every subsequent sibling. Every fact is new. Every
cache misses.

With transform stacks, facts are position-independent:

```
PushTransform(x, y)   ← parent emits, changes when position changes
  Rect(visual)        ← node emits, cached, position-independent
PopTransform          ← parent emits
```

The Rect has no position. It's at its local origin. The parent wraps it
in a transform. When a sibling's height changes, the parent emits a
different PushTransform. But `render(child)` still hits cache — the
child hasn't changed. Its facts are the same cached sequence.

Position flows through the loop's transform stack at execution time,
not through the facts at production time. This is what makes per-node
caching work for layout: the cached facts are valid regardless of where
the node ends up positioned.

### 5.6 Sub-phases, not passes

When parents need information from children AND children need constraints
from parents, the traditional description says "multiple passes." But in
the iterator model, there are no separate passes. There are sub-phases.

A render handler needs child sizes before it can compute positions. It
calls a measurement sub-phase:

```lua
[T.L.Container] = function(self)
    -- gather size facts (sub-phase)
    local sizes = {}
    for i = 1, #self.children do
        sizes[i] = pvm.one(measure(self.children[i], avail_w))
    end
    -- compute positions from size facts
    local positions = flex_layout(self, sizes)
    -- produce draw facts
    return emit_positioned_children(self, positions)
end
```

`measure` is a sub-phase with a different question ("how big?") and a
different cache domain (keyed on node × constraint). It may itself call
measure on its children (recursive). Each child's measurement is
independently cached. Unchanged children hit the measurement cache even
when the render cache missed.

The "first pass" (measure) and "second pass" (render) interleave
per-node, driven by the consumer. There is no separate traversal for
measurement. The render handler calls measure when it needs sizes. If
sizes are cached, the "measurement pass" for that subtree is a cache
hit — one lookup, zero traversal.

Dependency cycles between parent and child (parent needs child sizes,
child text-wrap needs parent width) are resolved by the sub-phase's
caching: `measure(text_node, parent_width)` caches on `(text_node,
parent_width)`. Different constraint → different cache entry. Same
constraint → cache hit. The cycle doesn't require a separate traversal.
It requires a sub-phase with the right cache key.

---

## Part 6: The Three Levels

### 6.1 Compilation

Where the system reasons about the authored program. Includes: source
ASDL, event ASDL, apply, phase boundaries. Pure, structural, memoized.
Questions answered here: what layout does this widget need? What size is
this text at this width? What does this reference resolve to?

### 6.2 Codegen

Where compilation primitives are made fast. Includes: code-generated
ASDL constructors (unrolled interning tries via `quote.lua`). Happens
once at definition time, not per frame. The generated code IS what the
JIT traces.

### 6.3 Execution

Where the loop runs. Includes: the `for` loop over phase output,
transform/clip stacks, the graphics backend. Imperative, linear, does
not rediscover source semantics. The loop reads fact kinds and payload
fields. It does not ask "what type of widget produced this?"

### 6.4 Why this split matters

If compilation leaks into execution: runtime branching on source
variants in the loop, repeated name lookups, strings interpreted where
sums should have decided.

If execution leaks into compilation: source ASDL polluted with pixel
positions or resource handles, domain types shaped by rendering concerns.

The split prevents both.

---

## Part 7: Classification

### 7.1 Three classes of field

At every boundary, every field is one of:

**Code-shaping.** Determines which handler runs. Always a sum type
variant. Phase dispatch resolves it. Downstream, the decision is
consumed — the narrower representation has fewer variants.

**Payload.** Data read by the handler or the loop. Fields on the output
facts. Carried through, not branched on.

**Dead.** Not needed downstream. Stripped at the boundary. Carrying dead
fields wastes memory and can cause false cache misses (dead field changes
→ different fact → different interned object → miss).

### 7.2 The invariant

> Every distinction that matters at runtime is either resolved in the
> sum type (phase dispatch), present in the fact fields (payload), or
> stripped (dead). Nothing is lost. Nothing is duplicated. Nothing is
> misclassified.

### 7.3 Common classification errors

**Code-shaping treated as payload.** `if kind_str == "biquad"` in a hot
path. Fix: sum type + phase dispatch.

**Payload treated as code-shaping.** One handler per color. Fix: color is
a field, one handler.

**Dead fields kept alive.** A paint fact carries hit-test tags that paint
never reads. The tag changes → different fact → cache miss → unnecessary
recomputation.

---

## Part 8: Structural Identity

### 8.1 Why structural over reference

ASDL with `unique` gives structural identity: same fields → same object.
`a == b` is a pointer comparison that means structural equality.

| Problem | Reference identity | Structural identity |
|---------|-------------------|---------------------|
| Equality | Deep comparison | `==` (instant) |
| Caching | Manual keys | Automatic from identity |
| Change detection | Dirty flags | Identity comparison |
| Structural sharing | Manual | Automatic via `pvm.with` |
| Undo | Clone entire state | Store previous root |

### 8.2 Structural sharing

`pvm.with(node, { field = new_value })` produces a new interned node
with one field changed. All other fields keep their existing identity.

When one track's volume changes, `pvm.with(track, { vol = -3 })` creates
a new track. The other tracks are the same objects. Every phase that
processes them returns cached facts. One edit → one subtree recompiles.
Everything else is free.

### 8.3 Design for incrementality

The phase cache effectiveness depends on ASDL structure:

**Right granularity.** One boundary per identity noun (track, widget,
parameter). Too fine (per-pixel): lookup dominates. Too coarse
(per-project): any edit recompiles everything.

**No derived data in source.** Derived values change when source changes,
creating false misses if they're source fields. They belong in phases.

**Stable identity.** IDs identify the thing, not its position. Moving an
item should not change its identity.

**The diagnostic.** `pvm.report_string` shows hit rates. Above 90% means
structural sharing works and incrementality is real. Below 50% means the
ASDL boundaries are wrong.

---

## Part 9: What the Pattern Eliminates

The pattern eliminates infrastructure whose only job was to reconnect
truths that should never have been split apart.

**State management frameworks.** The source ASDL is the state. Apply
computes the next state. No stores, no reducers, no subscriptions.

**Invalidation frameworks.** Structural identity + phase caching.
Unchanged nodes hit. Changed nodes miss. No dirty flags, no TTLs,
no manual invalidation.

**Observer buses.** Event ASDL + Apply is the explicit state transition.
Consequences are derived by phases, not propagated by notification.

**Dependency injection.** Phase boundaries make each node self-contained.
No function needs external context — everything it needs is on the node
or gathered from sub-phases.

**Runtime interpretation.** Phases resolve type dispatch at compilation
time. The loop does not ask "what are you?" — it reads fact fields that
are already decided.

**Virtual DOM.** ASDL interning IS reconciliation. Same fields → same
object → cache hit. No O(N) tree diff. No heuristic key matching.

**Ad hoc caches.** Phase boundaries are the ONLY caches. Structural,
automatic, inspectable via `pvm.report`.

**Test scaffolding.** Pure functions. Construct input, call phase,
assert output. No mocks, no fixtures, no setup.

### What does NOT disappear

Careful domain modeling. Backend engineering. Performance work. Error
handling. Judgment about boundary design and layer count. The pattern
moves complexity to where it is more explicit, more local, and more
testable.

---

## Part 10: The ASDL Convergence Cycle

### 10.1 Three stages

```
DRAFT → EXPANSION → COLLAPSE
```

**Draft.** Top-down from domain intuition. Always too coarse. The loop
has not spoken.

**Expansion.** Driven by the loop and the profiler. Trace aborts demand
new types. Cache misses demand new boundaries. Low hit rates demand
structural changes. The ASDL grows.

**Collapse.** Driven by the expanded types themselves. Variants that
share structure merge. Boundaries that do the same verb merge. Fields
that appear on every variant become the uniform product type. The ASDL
shrinks to its minimal stable form.

### 10.2 Convergence criterion

The ASDL has converged when: every loop traces clean, every phase is a
pure structural transform, the cache report shows 90%+ reuse, and
recent features were purely additive — one new variant, one new handler,
zero changes to existing layers.

### 10.3 Why you cannot regress

During expansion, every new type was demanded by a loop that couldn't
trace clean. Remove it, the trace breaks.

During collapse, every merge is validated by the profiler. Merge two
types. Does the loop still trace? Does the cache ratio hold? Yes → merge
correct. No → distinction is real.

The cache hit ratio is the regression oracle.

---

## Part 11: Worked Examples

### 11.1 Track editor (ui5)

**Source ASDL:**
```
module App {
    Track = (string name, number color, number vol, number pan,
             boolean mute, boolean solo, number meter) unique
    Widget = TrackRow(...) unique | Button(...) unique | Meter(...) unique
           | TrackList(...) unique | Transport(...) unique | ... (11 total)
}
```

**Phase boundary (streaming, type-dispatched):**
```lua
local render = pvm.phase("ui", {
    [T.App.Button] = function(self)
        return pvm.once(Rect(self.tag, self.bg))
    end,
    [T.App.TrackList] = function(self)
        return pvm.children(render, self.rows)
    end,
    -- 11 handlers
})
```

**Execution (one loop):**
```lua
for _, fact in render(root) do
    draw(fact)
end
```

**Performance:** 16µs framework total = 1% of frame budget. 93% reuse
rate during animated playback.

### 11.2 Text editor

Source: Document with Blocks, Spans, Selection. Three layers: source →
laid (shaped, positioned) → flat facts. One keystroke changes one Span
→ phases cache all others → one block recompiles. Undo = previous root
→ cache hit → instant.

### 11.3 Spreadsheet

Source: Cells with Formulas and Expressions. Evaluation IS compilation.
`=SUM(A1:A10)` compiles to a resolved chain. The chain doesn't interpret
the formula — it executes pre-resolved operations.

### 11.4 Audio DSP

Source: signal graph (Osc, Filter, Gain, Chain, Mix). Compiled to a flat
schedule of processing steps. Each step reads stable coefficients
(payload) and mutates delay history (execution state). The graph is the
source. The schedule is the compiled output. The loop is the audio
callback.

### 11.5 Server-rendered web

Source: page ASDL (data + session state + navigation). Phases lower
through HTML structure to string fragments. The triplet streams
directly into the HTTP response. Unchanged subtrees' fragments are
cached. Structural caching at arbitrary boundaries with zero
configuration.

### 11.6 The applicability test

> Is my user editing a structured program whose meaning I keep
> rediscovering at runtime? Would it be better to compile that meaning
> into facts and iterate them?

If yes, the pattern applies.

---

## Part 12: Philosophy

### 12.1 Programs are compilers, not interpreters

A UI framework takes widget descriptions, resolves layout, produces draw
calls. That is a compiler. An audio engine takes signal graphs, resolves
routing, produces processing schedules. That is a compiler.

The pattern makes this nature explicit. Every design question becomes a
compiler design question: "What type?" → "What ASDL type?" "How do I
handle events?" → "How does the source update?" "How do I optimize?" →
"Where are the memoized phases?" "How do I manage state?" → "What is
source ASDL vs. what are compiled facts?"

### 12.2 Phases gather facts as iterators

A phase does not "transform" or "lower" or "compile" in the sense of
producing a data structure. A phase gathers facts about a node as an
iterator. The consumer pulls facts. Caching is a side effect of full
consumption. Fusion is a consequence of iterator nesting.

This is not a metaphor. The implementation is literally an iterator
protocol. `gen(param, state) → next_state, value`. Lua's `for` loop
runs it. The phase wraps it in recording machinery. The cache stores
the exhausted recording. Next time, `seq_gen` replays it. Same protocol.
Same loop. Same code.

### 12.3 Structure over keys

Keys are escape hatches. They leak framework mechanics into domain code.
Structure is already there — the ASDL, the interning, the phase dispatch.
Every time you reach for a key, ask: can I express this as structure?

### 12.4 Compilation over interpretation

An interpreter traverses the source every frame, re-dispatching at every
node. A compiler traverses once (or incrementally), gathers facts, and
the loop consumes them.

```
Interpreter:  every frame = traverse + dispatch + execute
Compiler:     first frame = gather facts (recording fills, caches commit)
              next frames = loop over cached facts (if source unchanged)
              on change   = re-gather for changed subtree + loop
```

### 12.5 One unified concept

There is one boundary primitive: `pvm.phase`. It returns a triplet.
Always lazy. Always composable. Always cached on identity.

When the answer is one fact, the consumer calls `pvm.one`. When the
answer is many facts, the consumer calls `for`. When the answer needs
materializing, the consumer calls `pvm.drain`. These are consumption
choices, not production differences. The phase doesn't know how it will
be consumed. It gathers facts as an iterator. The consumer decides.

There is no "streaming boundary" vs "scalar boundary." There is no
separate memo primitive. There is one thing: a phase that gathers facts
as an iterator. One concept. One diagnostic. One caching model.

---

## The Master Checklist

### Source ASDL
```
□ Every user-visible thing is an ASDL type
□ Every "or" is a sum type (not a string)
□ Every type is unique (interned)
□ No derived data in source
□ No backend concerns in source
□ Cross-references are IDs, resolved in phases
□ Save/load round-trips everything
□ Undo = previous root = cache hit = instant
```

### Phases
```
□ Each phase has a named verb
□ Each phase consumes at least one decision
□ Handlers return triplets (pvm.once / pvm.empty / pvm.children / concat)
□ Sub-phases for parameterized facts (extra args, cached per arg)
□ No side caches outside phases
□ pvm.report shows >70% reuse under realistic edits
```

### Classification
```
□ Code-shaping = sum type variants (phase dispatch)
□ Payload = fields on output facts
□ Dead = stripped at boundary
□ No strings where sums belong
□ No code-shaping treated as payload (or vice versa)
```

### Execution
```
□ for _, fact in phase(source) do act(fact) end
□ State in the loop is push/pop stacks only
□ No source-level semantics rediscovered in the loop
□ No recursive dispatch during execution
□ Continuously-varying values applied as post-phase overlays
```

---

## Summary

```
THE USER
    edits a domain program

THE SOURCE
    ASDL values — interned, immutable, structural identity

THE INPUT LANGUAGE
    Event ASDL

STATE EVOLUTION
    Apply : (state, event) → state

THE FIVE CONCEPTS
    source ASDL
    event ASDL
    apply
    phases (fact-gathering iterators, cached on identity)
    the loop

THE EXECUTION MODEL
    phase(source) → triplet → for loop
    one traversal, fused, lazy, cached
    caching is a side effect of full iteration
    fusion is a consequence of iterator nesting

THE FLATTEN THEOREM
    recursion IS flattening (iterator nesting produces flat streams)
    state is always a stack (push/pop from linearized containment)
    layers exist where vocabulary changes (not per recursion class)
    sub-phases replace passes (interleaved, independently cached)
    transform stacks enable per-node caching

THE LIVE LOOP
    poll → apply → phase(source) → loop

THE DEEPEST RULE
    the source ASDL is the architecture

THE ITERATOR RULE
    phases gather facts as iterators
    caching IS iteration (recording on miss, replay on hit)
    fusion IS nesting (inner triplets compose into outer triplets)
    the loop IS execution (the only loop, pulling through everything)
```

> The pattern is: the user edits a program in a domain language.
> That program is source ASDL — interned, immutable, structurally
> identified. Input is Event ASDL. State changes are a pure Apply.
> Phases gather facts about the source as iterators. Facts are
> cached as a side effect of full iteration. Nested iterators fuse
> into one traversal. A loop pulls the facts and acts on them.
> When the source changes, only the affected subtrees re-gather.
> Everything else replays from cache. The loop is the only execution.
