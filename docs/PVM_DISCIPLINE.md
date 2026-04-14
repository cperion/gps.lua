# PVM Discipline Rules for AI Coding

> This document defines the architectural discipline for working with pvm.
> Every rule exists because violating it silently degrades caching, type
> safety, memory management, or performance. There are no optional rules.

---

## The One Principle

**If it isn't an ASDL value, it doesn't exist to the system.**

Phase caches key on ASDL identity. Structural sharing works through ASDL
interning. Type dispatch works through ASDL class lookup. `pvm.with` operates
on ASDL nodes. `pvm.report` diagnoses ASDL-keyed caches.

The moment something meaningful lives outside the ASDL — in a ctx, a closure,
a registry, a global, a plain table — it becomes invisible to every mechanism
that makes pvm work.

---

## The Execution Model

There is no separate "execution layer." The phase boundary returns a triplet
`(gen, param, state)`. You consume it. That IS execution.

```lua
for _, v in phase(node) do
    -- this is the machine running
end
```

Or equivalently: `pvm.each(phase(node), fn)`, `pvm.drain(phase(node))`,
`pvm.fold(phase(node), init, fn)`.

The triplet is not an abstraction over execution. It IS execution factored
into its three irreducible roles: step function, invariant environment,
mutable cursor. Every phase boundary returns one. Every consumer runs one.
Cache fills as a side effect of full consumption. There is nothing else.

---

## ASDL Rules

### R1: No plain tables as domain values

NEVER:
```lua
{ tag = "btn", w = 100, h = 30 }
```
ALWAYS:
```lua
T.App.Button("btn", 100, 30, ...)
```

Plain tables have no interning, no identity, no cache keying, no structural
sharing, no type safety, no `pvm.with`, no phase dispatch, and no weak-key
compatibility with pvm's cache system.

### R2: No strings where sum types belong

NEVER:
```lua
kind = "button"
```
ALWAYS:
```lua
Kind = Button | Slider | Meter
```

Strings lose exhaustiveness, variant-specific fields, singleton identity
comparison, and phase dispatch.

Every boolean flag that constrains another boolean is a sum type:

```lua
-- WRONG: boolean soup with implicit constraints
is_playing = true, is_recording = false, is_paused = false

-- RIGHT: impossible invalid state
TransportState = Stopped | Playing | Recording | Paused
```

### R3: No optional fields as variant discrimination

NEVER branch behavior on nil-checking an optional field.
ALWAYS use a sum type with explicit variants:

```lua
-- WRONG
Param = (number value, Automation? automation) unique
-- then: if node.automation ~= nil then ...

-- RIGHT
ParamSource = Static(number value) unique
            | Automated(Automation curve) unique
```

### R4: No derived data in source ASDL

If a value is computed from other values, it belongs in a later phase.

```lua
-- WRONG: coefficients are derived from freq and q
Filter = (number freq, number q, number b0, number b1, number b2) unique

-- RIGHT: source has only authored fields
Filter = (number freq, number q) unique
-- coefficients computed in a phase boundary
```

The source ASDL answers: what did the user author? What survives save/load?
What does undo restore? Nothing else belongs there.

### R5: Always mark types `unique`

Types without `unique` don't intern. Every constructor allocates a new object.
Phase caches never hit because identity comparison fails. The code runs. It
just runs slowly and leaks.

### R6: Never mutate ASDL nodes

NEVER use `rawset(node, field, value)` or any other mutation path.
ALWAYS use `pvm.with(node, { field = value })`.

Mutation corrupts the interning trie. The node stored at the old key now has
different values. Every future lookup for those keys returns a corrupt node.
Interning is globally and silently broken.

The `__newindex` error on ASDL nodes exists for this reason. Do not bypass it.

### R7: Use `pvm.with`, not manual reconstruction

```lua
-- WRONG: fragile, breaks when fields are added
local new = T.App.Track(t.name, t.color, new_vol, t.pan, t.mute, t.solo, t.level)

-- RIGHT: only name what changes
local new = pvm.with(t, { vol = new_vol })
```

### R8: Use `pvm.with`, not deep copy

Deep copy creates new objects for everything. Every cache lookup misses.
Zero structural sharing.

`pvm.with` produces a new node for changed fields only. All unchanged fields
keep their interned identity. All phase caches hit on unchanged subtrees.

---

## Phase Boundary Rules

### R9: Handlers MUST return triplets

NEVER return nil, a raw value, or a table from a phase handler.
ALWAYS return `(gen, param, ctrl)`:

```lua
-- One output element
return pvm.once(value)

-- Map phase over children
return pvm.children(phase_fn, self.children)

-- Multiple elements
return pvm.concat2(pvm.once(a), pvm.once(b))

-- Zero output
return pvm.empty()
```

Returning nil from a handler is an error. Returning a raw value or table
breaks the recording protocol.

### R10: No parallel caching

NEVER add `local cache = {}` or `local memo = {}` alongside pvm phases.
NEVER write manual memoization wrappers.

```lua
-- WRONG: parallel cache with string keys, manual invalidation, strong refs
local memo = {}
local function get_layout(node)
    local key = node.tag .. ":" .. node.w .. ":" .. node.h
    if memo[key] then return memo[key] end
    local result = compute_layout(node)
    memo[key] = result
    return result
end
```

The phase boundary IS the cache. `pvm.phase` records on miss, commits on
full drain, and returns seq on hit. If you see `local cache = {}` or
`local memo = {}` anywhere outside pvm's own machinery, it is a bug.

Either the work belongs in a `pvm.phase` boundary (which caches
automatically), or it's genuinely ephemeral and shouldn't be cached at all.

The one legitimate exception is a multi-key cache like layout measurement
`cached_measure(node, max_width)` that keys on `(node identity × constraint)`.
Even this MUST use weak keys.

### R11: No ctx / bag-of-state arguments

NEVER thread an opaque context table through handlers or build functions:

```lua
-- WRONG
local function build_row(ctx, track, index)
    local bg = index == ctx.selected and ACTIVE or NORMAL
    ...
end
```

If a handler's output depends on a value, that value MUST be a field on the
ASDL node:

```lua
-- RIGHT: everything the handler needs is in the node
T.App.TrackRow(index, track, is_selected, is_hovered)
```

**Why this is fatal:** Phase caches key on node identity. The ctx is invisible
to the cache. When ctx changes but the node doesn't, the cache returns stale
results. The AI introduces an invisible dependency that the phase boundary
cannot track.

**The fix is always the same:** whatever the handler reads from ctx belongs as
a field on the ASDL type. If `hover_tag` affects output, it's a field. If
`theme` affects colors, resolve theme to concrete color values BEFORE
constructing the node.

### R12: No closures over mutable state in handlers

```lua
-- WRONG: output depends on captured `selected`, cache keys on node only
local selected = 1
[T.App.TrackRow] = function(self)
    if self.index == selected then ...  -- captured mutable!
```

The value of `selected` must be a field on the node itself. Same reason as
R11: the cache can't see it.

### R13: Call phases, not handlers directly

NEVER call a handler function directly or inline its logic.
ALWAYS call through the phase boundary:

```lua
-- WRONG: bypasses recording, caching, shared deduplication
local result = my_handler_fn(node)

-- RIGHT: goes through the phase machinery
for _, v in phase(node) do ... end
```

### R14: Understand partial drain

If a for-loop over a phase triplet breaks early, the recording does NOT
commit to cache. This is correct and safe. Do NOT add manual caching to
"fix" the re-evaluation on next access.

If you need the full cache, drain fully.

---

## Memory Rules

### R15: No strong references to ASDL nodes in external tables

pvm's caches use `__mode = "k"` (weak keys). When a node leaves the live
source tree, GC collects it and its cache entries die naturally.

If you store nodes in a plain table without weak keys, those nodes and all
their downstream cache entries are pinned forever:

```lua
-- WRONG: strong key, pins node and all downstream forever
local index = {}
index[node] = data

-- RIGHT: weak key, node dies when no longer in live tree
local index = setmetatable({}, { __mode = "k" })
index[node] = data
```

**This is the primary memory leak vector in pvm applications.**

### R16: No accumulating results across frames

NEVER append to a growing table each frame:

```lua
-- WRONG: grows forever, pins all nodes
all_results[#all_results + 1] = pvm.drain(phase(root))

-- RIGHT: replace, old results become garbage
current_results = pvm.drain(phase(root))
```

### R17: No non-ASDL wrappers holding ASDL nodes

NEVER wrap an ASDL node in a plain Lua object:

```lua
-- WRONG: strong reference pins the node
local wrapper = { node = my_node, extra = "stuff" }
```

If you need extra data associated with a node, either add it as a field on
the ASDL type, or store it in a weak-keyed side table.

---

## Anti-Pattern Catalog

These are patterns that look like normal good programming but are
fundamentally incompatible with pvm.

### Functions that take IDs instead of values

```lua
-- WRONG: indirection, opaque lookup, untestable without the table
local function render_track(track_id, tracks_table)
    local track = tracks_table[track_id]
    ...
end

-- RIGHT: the node IS the value, pass it directly
local function render_track(track_node)
    ...
end
```

IDs belong only where there is a real authored cross-reference between
independent subtrees (a send referencing another track). Even then, resolve
the ID in an explicit early phase, producing a new ASDL node carrying the
resolved value.

### Mutable accumulator threading

```lua
-- WRONG: output depends on call order, caching impossible
local function build_ui(node, state)
    state.y = state.y + ROW_H
    state.count = state.count + 1
    ...
end
```

Phase handlers must be pure functions of their node. If position depends on
sibling layout, that's a layout pass that runs inside a scalar phase boundary
and caches the entire result.

### Observer / callback registration

```lua
-- WRONG: interpreter pattern, breaks interning
node.on_click = function() ... end
node:addEventListener("hover", fn)
```

In pvm, input is Event ASDL, state change is `Apply : (state, event) → state`,
the new state compiles through phases. There is no listener. There is no
event bus. There is: poll → apply → compile → execute.

Callbacks also break interning — function identity is reference identity in
Lua, so two structurally identical nodes with different closures can never
intern to the same value.

### Managers and registries

```lua
-- WRONG: opaque mutable container, invisible to ASDL and caching
local WidgetManager = {
    widgets = {},
    register = function(self, w) ... end,
    update = function(self, id, props) ... end,
}
```

The collection is an ASDL list field: `Project(App.Track* tracks) unique`.
Updating a track is `pvm.with(project, { tracks = new_tracks })`. No manager.

### Ad hoc type wrappers / classes

```lua
-- WRONG: reinventing types outside ASDL
local Button = {}
Button.__index = Button
function Button.new(tag, w, h)
    return setmetatable({ tag = tag, w = w, h = h }, Button)
end
```

This is an ASDL type: `Button = (string tag, number w, number h) unique`.
ASDL gives you interning, immutability, type checking, phase dispatch,
`pvm.with`, and structural sharing. The ad hoc class gives you none of those.

### Imperative state machines with mode flags

```lua
-- WRONG: mode string controlling behavior
local mode = "editing"
if mode == "editing" then ...
elseif mode == "previewing" then ...
```

This is a sum type in the source ASDL:
```
AppMode = Editing(EditState state) unique
        | Previewing(PreviewState state) unique
```

Phase handlers dispatch on the variant. Each variant carries its own state.
Impossible to be in "editing" mode with preview state.

---

## The Diagnostic Questions

When reviewing or writing pvm code, apply these tests:

### The one-constructor test

> Can you test this function with one ASDL constructor call and one assertion,
> with nothing else?

If the answer requires building a ctx, populating a registry, setting up a
listener, initializing a mutable accumulator, constructing a lookup table,
or resetting a manual cache — the ASDL is incomplete, a dependency is hidden,
or the work is in the wrong layer.

### The cache-correctness test

> If this node is unchanged next frame, will the phase cache return the
> correct result?

If the handler reads ANYTHING not in the node (globals, captures, ctx,
side tables), the answer is no. The cache will return stale results.

### The memory test

> If this node leaves the source tree, will it be garbage collected?

If anything holds a strong reference to it (a plain table without `__mode`,
a closure capture, a non-ASDL wrapper), the answer is no. The node and its
entire cache chain are pinned.

### The pvm.report test

> Does `pvm.report_string` show healthy reuse ratios?

- 90%+ = healthy, structural sharing works, incrementality is real
- 70-90% = acceptable during genuine change (animation, editing)
- Below 50% = ASDL design problem — types aren't interning, boundaries
  are wrong, or invisible dependencies are defeating the cache

If the hit ratio is low but the data hasn't changed, something outside the
ASDL is varying (ctx, capture, accumulator) and poisoning the cache key.

---

## Summary of What pvm Eliminates

When the discipline is followed, these things do not exist in the codebase:

- State managers, stores, or reducers (Apply is a pure function, source ASDL is the state)
- Observer patterns, event buses, or listener registration (Event ASDL + Apply)
- Manual caching, memoization wrappers, or invalidation logic (phase boundaries)
- Dirty flags or change tracking (ASDL identity comparison)
- Virtual DOM or diffing (structural sharing via `pvm.with` + interning)
- Object-relational mapping or ID-based registries (ASDL nodes are values, pass them)
- Deep equality checks (interned `==` is reference equality)
- Type-checking boilerplate (ASDL constructors validate)
- Opaque context threading (all inputs are ASDL fields)
- Ad hoc Lua classes or metatables for domain types (ASDL types)
- Manager objects or service containers (ASDL list fields + `pvm.with`)

Every item on this list represents a failure mode where an AI will reach for
the standard solution instead of the ASDL-first solution. The standard
solution will appear to work. It will silently degrade caching, leak memory,
defeat type safety, or introduce stale-data bugs that are invisible until
`pvm.report` reveals the damage.
