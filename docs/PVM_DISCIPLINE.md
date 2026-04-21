# PVM Discipline

This is the **long-form architectural discipline** for working in the PVM codebase.

Use `AGENTS.md` for the short operational rules.
Use this file for the deeper doctrine, anti-pattern catalog, and review reference.

Grounding docs:

- `docs/COMPILER_PATTERN.md`
- `docs/PVM_GUIDE.md`
- `pvm.lua`

---

# 1. The one principle

> **If it isn't an ASDL value, it doesn't exist to the system.**

Phase caches key on ASDL identity.
Structural sharing works through ASDL interning.
Type dispatch works through ASDL classes.
`pvm.with` operates on ASDL nodes.
`pvm.report` diagnoses ASDL-keyed caches.

The moment something meaningful lives outside the ASDL — in a ctx table,
a closure capture, a registry, a global, a plain table, a string tag, or a
non-ASDL wrapper — it becomes invisible to the mechanisms that make PVM work.

---

# 2. The execution model

There is no separate execution layer.
The phase boundary returns a triplet `(gen, param, state)`. You consume it.
That **is** execution.

```lua
for _, v in phase(node) do
    -- this is the machine running
end
```

Or equivalently:

- `pvm.each(...)`
- `pvm.drain(...)`
- `pvm.fold(...)`
- `pvm.one(...)` for scalar boundaries

The triplet is not an abstraction layered over execution.
It **is** execution factored into step function, invariant environment, and mutable cursor.

---

# 3. ASDL rules

## 3.1 No plain tables as domain values

Wrong:

```lua
{ tag = "btn", w = 100, h = 30 }
```

Right:

```lua
T.App.Button("btn", 100, 30, ...)
```

Plain tables have no interning, no identity, no cache keying, no structural sharing,
no type safety, no `pvm.with`, and no phase dispatch.

## 3.2 No strings where sum types belong

Wrong:

```lua
kind = "button"
```

Right:

```asdl
Kind = Button | Slider | Meter
```

Every boolean flag that constrains another boolean is probably a sum type.

## 3.3 No optional fields as variant discrimination

Wrong:

```asdl
Param = (number value, Automation? automation) unique
```

then branching on `node.automation ~= nil`.

Right:

```asdl
ParamSource = Static(number value) unique
            | Automated(Automation curve) unique
```

## 3.4 Keep derived data out of source ASDL

Source ASDL answers:

- what did the user author?
- what survives save/load?
- what does undo restore?

Derived values belong in later phases.

## 3.5 Mark cacheable domain types `unique`

Without `unique`, constructors allocate fresh nodes and identity never stabilizes.
The code may still run, but caching will quietly degrade.

## 3.6 Never mutate ASDL nodes

Wrong:

```lua
rawset(node, "vol", 0.7)
node.vol = 0.7
```

Right:

```lua
local next_node = pvm.with(node, { vol = 0.7 })
```

Mutation corrupts interning and silently breaks structural identity.

## 3.7 Use `pvm.with`, not manual reconstruction

Wrong:

```lua
local next = T.App.Track(t.name, t.color, new_vol, t.pan, t.mute, t.solo)
```

Right:

```lua
local next = pvm.with(t, { vol = new_vol })
```

## 3.8 Use `pvm.with`, not deep copy

Deep copy destroys structural sharing.
`pvm.with` preserves unchanged identities and lets phase caches hit.

---

# 4. Event and state discipline

Input is Event ASDL.
State change is pure `Apply(state, event) -> state`.

Do not register callbacks on nodes.
Do not attach closures to ASDL values.
Do not build event buses.

Wrong:

```lua
node.on_click = function() ... end
```

Right:

- model the event as Event ASDL
- update state structurally with `pvm.with`

---

# 5. Phase boundary rules

## 5.1 A phase answers a specific question

Examples:

- `measure(node) -> Size`
- `resolve(project) -> ResolvedProject`
- `lower(widget) -> DrawCmd stream`
- `hit_regions(root) -> HitRegion stream`

Name phases with verbs.
Do not create vague phases like `process`, `handle`, or `update`.

## 5.2 Streaming handlers must return triplets

Wrong:

```lua
[T.App.Button] = function(self)
    return Cmd(...)
end
```

Right:

```lua
[T.App.Button] = function(self)
    return pvm.once(Cmd(...))
end
```

Other canonical cases:

- zero output: `pvm.empty()`
- recurse over children: `pvm.children(...)`
- multiple streams: `pvm.concat2/3/all(...)`

## 5.3 Scalar boundaries use `pvm.phase(name, fn)` + `pvm.one(...)`

If the question produces exactly one value per node, use the scalar form.
Do not build manual memo wrappers.

## 5.4 No hidden dependencies in handlers

If handler output depends on a value, that value must be visible in:

- the ASDL node identity, or
- explicit phase arguments

No hidden `ctx`, mutable capture, or ambient global should affect output.

## 5.5 No parallel caches

The phase boundary **is** the cache.
Do not add `local cache = {}` or `local memo = {}` alongside proper phases.

## 5.6 Call phases, not handlers directly

Calling a handler directly bypasses recording, hits, shared in-flight use, and cache commit.
Always call through the phase boundary.

## 5.7 Understand partial drain

If a consumer breaks early, the recording does not commit.
This is correct.
Do not patch around it with manual caching.

---

# 6. Flattening and execution discipline

## 6.1 Flatten before the final loop

The final execution loop should consume flat facts.
It must not recursively interpret source nodes.

## 6.2 Prefer uniform command product types in hot loops

For hot output streams, prefer one flat product type with a singleton `Kind` field.
Use singleton ASDL values, not string command tags.

## 6.3 Containment becomes push/pop facts

Examples:

- `PushClip / PopClip`
- `PushTransform / PopTransform`
- `PushOpacity / PopOpacity`

Execution state is usually a stack.

## 6.4 The final loop must not rediscover source semantics

The source tree has already been compiled.
The loop should execute facts, not reinterpret authored structure.

---

# 7. Field classification discipline

Classify fields before choosing a representation.

## 7.1 Code-shaping fields

These affect structure, branching, layout, or which facts are produced.
They belong in ASDL because phase output depends on them.

Examples:

- children
- orientation
- selected
- visible
- mode variants
- layout constraints

## 7.2 Payload fields

These are carried downstream but do not decide structure much.
Examples:

- x/y/w/h in final commands
- rgba8
- shaped text payload

## 7.3 Dead fields

These are not authored and not needed downstream.
Remove them.

### Classification invariant

If changing a field changes phase output, it must be part of the phase cache key
through ASDL identity or explicit phase arguments.

---

# 8. Memory discipline

## 8.1 Use weak side tables only

Wrong:

```lua
local index = {}
index[node] = data
```

Right:

```lua
local index = setmetatable({}, { __mode = "k" })
index[node] = data
```

Strong side tables pin nodes and their downstream cache chains.

## 8.2 Do not accumulate results across frames

Wrong:

```lua
all_results[#all_results + 1] = pvm.drain(render(root))
```

Right:

```lua
current_results = pvm.drain(render(root))
```

## 8.3 Do not wrap ASDL nodes in plain objects

If extra data is meaningful, put it in ASDL.
If the association is external, use a justified weak-key side table.

---

# 9. Anti-pattern catalog

Reject or refactor these patterns unless there is an explicit, justified escape hatch.

## 9.1 Plain domain tables

Use ASDL.

## 9.2 String dispatch

Use ASDL sum types and singleton values.

## 9.3 Opaque context threading

Wrong:

```lua
render(node, ctx)
```

If `ctx` affects output, its values belong in ASDL nodes or explicit phase args.

## 9.4 Callback registration

Use Event ASDL + Apply.

## 9.5 Managers and registries

Use ASDL lists and structural updates.
Do not build manager objects as the primary architecture.

## 9.6 Mutable accumulators that shape output

If sibling layout is needed, use a proper layout phase.
Do not thread mutable state through handlers as hidden semantics.

## 9.7 Manual dirty flags

Use structural identity and phase caches.

## 9.8 Non-ASDL classes for domain values

Use ASDL product/sum types.
Do not reinvent the domain type system in plain Lua objects.

---

# 10. Testing discipline

## 10.1 One-constructor test

A good PVM function should often be testable with one ASDL constructor and one assertion.
If testing requires managers, registries, mutable context, listeners, or manual caches,
the design likely hid state outside ASDL.

## 10.2 Cache-correctness test

Ask for every handler:

> Can this handler produce different output for the same ASDL node identity?

If yes, find the hidden dependency and move it into ASDL or explicit phase args.

## 10.3 Memory test

Ask:

> If this node leaves the source tree, can it be garbage collected?

If a plain table, closure, or wrapper still references it, fix the lifetime.

## 10.4 Diagnostics test

Use:

```lua
print(pvm.report_string({ phase1, phase2, phase3 }))
```

Interpretation:

- `90%+ reuse` = healthy
- `70–90%` = acceptable during genuine change
- `<50%` = architecture smell

Low reuse usually means:

- hidden dependencies
- wrong boundary placement
- missing `unique`
- excess reconstruction
- deep copy
- execution rediscovering structure

---

# 11. How to think when a smell appears

If the code you are about to write feels like a framework smell, stop.

Typical smells:

- “I’ll just add a helper switch for now”
- “I’ll pass a ctx table through this boundary”
- “I’ll return a raw Lua shape and inspect it later”
- “I’ll add a Rust-only intermediate form to avoid fixing the Lua design”

Correct response:

1. go back to ASDL
2. make the distinction explicit
3. put it in the right layer
4. dispatch through `pvm.phase(...)`
5. keep execution flat

Do not postpone architectural fixes if the smell has already appeared.
Fix the design as soon as it becomes visible.

---

# 12. Final doctrine

A PVM application is a live compiler:

- ASDL is the source language
- events edit the source
- `Apply` produces the next source program
- phases compile it into flat facts
- a loop executes those facts
- structural identity makes unchanged work disappear
