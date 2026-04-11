# The Complete Guide to pvm/uvm

> **pvm** is the foundation: ASDL context, structural update,
> recording-triplet phase boundaries, and lazy pull-driven evaluation.
>
> **triplet.lua** provides the iterator algebra: map, filter, concat,
> flatmap, and all combinators used inside phase handlers.
>
> **uvm** extends pvm with resumable machine algebra:
> family/image/machine, status protocol, composition operators.
>
> **quote.lua** provides hygienic codegen: auto-captured upvalues,
> gensym, composable code fragments — primarily used for ASDL
> constructor codegen (interning tries).
>
> That is the entire framework.

---

# Preface: What This Guide Is For

You have a domain. Maybe it is a UI toolkit, an audio engine, a game, a
language compiler, a document editor. You know what the user sees and does.
You know what the machine at the bottom must do — issue draw calls, fill
audio buffers, emit bytecode.

This guide teaches you how to bridge that gap using pvm/uvm. The central
discipline is:

1. Model your domain as ASDL types (interned, immutable, structural identity)
2. Express the descent from user-level to machine-level as memoized boundaries
3. Flatten the output to a uniform command array
4. Execute with a for-loop

Throughout, we use the ui5 track editor as the running example — an 850-line
Love2D application with 12 tracks, live playback, mute/solo, volume/pan
sliders, scrolling, hit testing, and a transport bar.

---

# Part I — The Foundation

## Chapter 1: What pvm Is

pvm is not a framework. It is a vocabulary — five primitives and nothing else:

| Primitive | What it does |
|-----------|-------------|
| `pvm.context()` | Creates an ASDL context for defining types |
| `pvm.with(node, overrides)` | Structural update preserving sharing |
| `pvm.phase(name, handlers)` | Recording-triplet boundary: the ONE boundary primitive |
| `pvm.lower(name, fn)` | Identity-cached value boundary |
| `pvm.drain(g, p, c)` | Materialize a triplet chain into a flat array |
| `pvm.drain_into(g, p, c, out)` | Append a triplet chain into an existing array |
| `pvm.each(g, p, c, fn)` | Execute a callback for each element |
| `pvm.fold(g, p, c, init, fn)` | Reduce a triplet chain to a single value |
| `pvm.once(value)` | Single-element triplet (leaf handler helper) |
| `pvm.children(phase_fn, array)` | Map a phase over child nodes, lazy concat |
| `pvm.report(phases)` | Diagnostic report on cache behavior |

Plus `pvm.T` — the full Triplet algebra (`map`, `filter`, `concat`, `flatmap`, ...).

Everything else — your ASDL schemas, your layout algorithms, your rendering,
your interaction — is your domain.

### Using pvm

```lua
local pvm = require("pvm")

-- 1. Create a context and define types
local T = pvm.context():Define [[
    module Greet {
        Lang = English | French | German
        Message = (Greet.Lang lang, string name) unique
    }
]]

-- 2. Construct interned nodes
local m1 = T.Greet.Message(T.Greet.English, "world")
local m2 = T.Greet.Message(T.Greet.English, "world")
assert(m1 == m2)  -- same fields → same object (structural identity)

-- 3. Structural update
local m3 = pvm.with(m1, { name = "Lua" })
assert(m3 ~= m1)               -- different name → different object
assert(m3.lang == m1.lang)      -- unchanged field: SAME object

-- 4. Recording-triplet boundary (the ONE boundary primitive)
--    Handlers dispatch by ASDL type and return a triplet (g, p, c).
--    The phase is lazy: nothing evaluates until you drain.
--    Cache fills as a side effect of full drain. Next call is a seq hit.
local translate = pvm.phase("translate", {
    [T.Greet.Message] = function(self)
        local k = self.lang.kind
        if k == "English" then return pvm.once("Hello, " .. self.name)
        elseif k == "French" then return pvm.once("Bonjour, " .. self.name)
        elseif k == "German" then return pvm.once("Hallo, " .. self.name)
        end
    end,
})

-- Drain the triplet to materialize values. On miss: handler runs,
-- recording fills the buffer, cache commits on exhaustion.
local r1 = pvm.drain(translate(m1))
assert(r1[1] == "Hello, world")

-- On hit: seq_gen over cached array. Handler not called. Zero work.
local r2 = pvm.drain(translate(m1))
assert(r2[1] == "Hello, world")

-- 5. Diagnostics
print(pvm.report_string({translate}))
-- translate                 calls=2  hits=1  shared=0  reuse=50.0%
```

That is pvm. Five primitives. No magic. No auto-wiring. You declare types,
construct values, define boundaries, and inspect cache behavior.

---

## Chapter 2: ASDL — The Universal Type System

ASDL (Abstract Syntax Description Language) is how you define the types in
your domain. Every type in a pvm system is an ASDL type.

### Defining types

```lua
local T = pvm.context():Define [[
    module UI {
        Node = Column(number spacing, UI.Node* children) unique
             | Row(number spacing, UI.Node* children) unique
             | Rect(string tag, number w, number h, number rgba8) unique
             | Text(string tag, number font_id, number rgba8, string text) unique
    }
]]
```

This defines:
- A **module** `UI` (namespace)
- A **sum type** `Node` with four variants: Column, Row, Rect, Text
- Each variant is a **product type** with named fields
- `unique` means structurally interned (same fields → same object)
- `UI.Node*` is a list of Node values

### Sum types (variants)

A sum type represents a choice. `Node` can be a Column OR a Row OR a Rect
OR a Text. Each variant has different fields.

Access the variant's kind:
```lua
local col = T.UI.Column(10, { rect1, rect2 })
print(col.kind)  -- "Column"
```

### Product types (records)

A product type is a record with named fields:
```lua
local rect = T.UI.Rect("header", 200, 40, 0xff3366ff)
print(rect.tag, rect.w, rect.h, rect.rgba8)
-- "header"  200  40  0xff3366ff
```

### Singleton types

A variant with no fields is a singleton — one unique object:
```lua
T:Define [[ module View { Kind = Rect | Text | PushClip | PopClip } ]]
local K_RECT = T.View.Rect      -- singleton (no parens — it IS the value)
local K_TEXT = T.View.Text       -- singleton
assert(K_RECT ~= K_TEXT)         -- different objects
assert(K_RECT == T.View.Rect)    -- same object (singleton)
```

Singletons are used as Kind tags. Comparing `cmd.kind == K_RECT` is a
pointer comparison, not a string comparison.

### Field types

| ASDL type | Lua type | Notes |
|-----------|----------|-------|
| `number` | Lua number | |
| `string` | Lua string | |
| `boolean` | Lua boolean | |
| `T.Module.Type` | ASDL type | Must be defined in the same context |
| `T.Module.Type*` | Lua table (list) | Interned: same elements → same list |
| `T.Module.Type?` | ASDL type or nil | Optional |

### Module nesting

Types reference other types by qualified name:
```lua
T:Define [[
    module App {
        Track = (string name, number vol) unique
        Widget = TrackRow(number index, App.Track track) unique
               | Button(string tag, number w, number h) unique
    }
]]
```

`App.Track` is referenced by `App.Widget.TrackRow`. The context resolves
references at Define time.

### Multiple Define calls

You can call `:Define` multiple times on the same context:
```lua
local T = pvm.context()
T:Define [[ module App { Track = (string name) unique } ]]
T:Define [[ module UI  { Node = Rect(string tag) unique } ]]
-- Both App and UI are available on T
```

This lets you define layers in separate blocks or even separate files.

---

## Chapter 3: Interning — Same Values, Same Object

When a type is marked `unique`, its constructor returns the same Lua table
for the same field values:

```lua
local a = T.UI.Rect("btn", 100, 30, 0xff0000ff)
local b = T.UI.Rect("btn", 100, 30, 0xff0000ff)
assert(a == b)        -- true! same Lua table
assert(rawequal(a,b)) -- true! reference equality
```

### How it works

The constructor maintains a **trie** (nested tables) keyed by field values.
For `Rect(tag, w, h, rgba8)`:

```text
cache[tag][w][h][rgba8] → existing_rect_or_nil
```

The trie is walked one field at a time. If the full path exists, the cached
object is returned. Otherwise a new object is created and stored.

In pvm, the trie walk is **code-generated** — an unrolled sequence of
table lookups with no loops, no `select()`, no `type()` checks. On LuaJIT:

| Operation | Time |
|-----------|------|
| Cache hit (existing node) | 0 ns (identity) |
| Cache miss (new node, all-builtin fields) | 1.6 ns |
| Cache miss (fields include ASDL types) | 25 ns |

### Why interning matters

**Free equality.** `a == b` (reference equality) means structural equality.
No deep comparison needed.

**Free caching.** Memoized boundaries use `cache[node]`. If the same interned
node is passed again, the result is returned instantly.

**Free deduplication.** If two parts of your tree independently produce the
same subtree, they get the same object.

**Structural sharing.** When you update one field with `pvm.with()`, all
other fields keep their existing interned identity. Unchanged subtrees are
literally the same Lua tables.

### List interning

Lists (ASDL `*` fields) are interned too. Same elements in the same order
→ same Lua table:

```lua
local list1 = { T.UI.Rect("a",10,10,0xff), T.UI.Rect("b",20,20,0xff) }
local list2 = { T.UI.Rect("a",10,10,0xff), T.UI.Rect("b",20,20,0xff) }
-- After interning through a constructor that takes Node*:
-- the interned lists are the same table
```

### Immutability

Interned objects are immutable. NEVER mutate their fields. Mutation would
corrupt the interning trie (the old keys would point to an object with
different values).

Use `pvm.with()` instead:
```lua
local new_rect = pvm.with(old_rect, { rgba8 = 0x00ff00ff })
-- new_rect is a NEW interned node. old_rect is unchanged.
```

---

## Chapter 4: phase — Recording-Triplet Boundary

`pvm.phase` is the ONE boundary primitive. It does four things in one call:

1. **Dispatches** by the node's ASDL type (metatable pointer comparison)
2. **Returns a triplet** `(g, p, c)` — a lazy stream of output values
3. **Records** lazily: evaluation happens only as a consumer pulls values
4. **Caches** as a side effect of full drain: same node next time → instant seq

### The handler contract

Handlers receive a node and **return a triplet** — a `(gen, param, ctrl)` triple
that produces zero or more output values when pulled.

**Leaf handler** — produce one element with `pvm.once`:

```lua
local widget_to_cmds = pvm.phase("lower", {

    [T.App.Button] = function(self)
        local bg = self.hovered and C.panel_hi or self.bg
        return pvm.once(Rct(self.tag, self.w, self.h, bg))
    end,
```

**Multi-element handler** — concatenate with `pvm.concat2/3` or `pvm.concat_all`:

```lua
    [T.App.Meter] = function(self)
        local fill_w = math.max(1, math.floor(self.w * self.level))
        local color  = self.level > 0.9 and C.meter_clip or C.meter_fill
        return pvm.concat2(
            pvm.once(Rct(self.tag.."|fill", fill_w,          self.h, color)),
            pvm.once(Rct(self.tag.."|bg",   self.w - fill_w, self.h, C.meter_bg))
        )
    end,
```

**Recursive handler** — map phase over children with `pvm.children`:

```lua
    [T.App.TrackList] = function(self)
        return pvm.children(widget_to_cmds, self.rows)
    end,

})
```

### Three-way cache

Every call resolves one of three cases:

**Hit** — node was fully drained before. Returns `seq_gen` over cached array.
Handler is not called. Zero work.

```lua
widget:lower()   -- miss → recording_gen; handler runs as consumer pulls
widget:lower()   -- hit  → seq_gen over cached array; instant
```

**In-flight (shared)** — same node is already being recorded by another consumer
in the same frame. Returns another reader over the same recording entry.
No duplicate work. Both consumers see the same values.

```lua
-- Two subtrees reference the same shared widget node:
widget:lower()   -- first consumer: miss → recording starts
widget:lower()   -- second consumer (same drain): shared → same recording
```

**Miss** — node not seen. Handler dispatches and returns a triplet. That triplet
is wrapped in a `recording_gen` that buffers values as they are pulled.
When the recording is fully exhausted, the buffer commits to cache.

### Lazy evaluation — nothing runs until you drain

Calling `phase(node)` returns a triplet immediately. The handler has not run.
No values have been produced. The triplet is a promise of future values.

Draining causes evaluation:

```lua
local cmds = pvm.drain(widget_to_cmds(root))
-- NOW handlers ran (for nodes that missed cache)
-- NOW caches filled as side effect of exhaustion
-- cmds is a flat array of all produced values
```

Alternatively, consume without materializing a full array:

```lua
pvm.each(widget_to_cmds(root), function(cmd)
    execute_draw(cmd)
end)
-- Pull-driven. No intermediate array. Cache still fills as side effect.
```

### Adjacent misses fuse automatically

When a handler calls a child phase, the child's triplet nests inside the
parent's recording. The outermost drain pulls through all of them in one
continuous pass. LuaJIT traces the entire chain as a single path.

```lua
[T.App.Panel] = function(self)
    -- Each child may hit (seq) or miss (recording).
    -- They nest transparently. One drain runs them all.
    return pvm.children(widget_to_cmds, self.children)
end,
```

### Method installation

After `pvm.phase(name, handlers)`, every handled ASDL type gains a method
`:name()` returning the triplet directly:

```lua
local g, p, c = widget:lower()       -- same as widget_to_cmds(widget)
local cmds    = pvm.drain(widget:lower())
```

### Stats — calls, hits, shared

```lua
local s = widget_to_cmds:stats()
-- s.name   = "lower"
-- s.calls  = total invocations
-- s.hits   = cache hits (seq path, zero work)
-- s.shared = in-flight hits (shared recording, no duplicate eval)

widget_to_cmds:hit_ratio()    -- hits / calls
widget_to_cmds:reuse_ratio()  -- (hits + shared) / calls
```

The `reuse_ratio` is the true quality metric: the fraction of all calls
that skipped redundant evaluation entirely.

```text
pvm.report_string({ widget_to_cmds, compile_layout })
  lower                    calls=4174  hits=3037  shared=892   reuse=93.3%
  layout                   calls=120   hits=118   shared=0     reuse=98.3%
```

### phase vs lower

Use **phase** when the handler produces a **stream** — zero or more elements
via `pvm.once`, `pvm.children`, or `pvm.concat2/3/all`. The cache holds an
array. Hits return `seq_gen` over it.

Use **lower** when the handler produces a **single value** — a solved layout,
a compiled plan, a measurement. The cache holds that value directly.

```lua
-- phase: streaming boundary (many output elements per node)
pvm.phase("lower", { [T.App.Button] = function(n) return pvm.once(Cmd(n)) end })

-- lower: single-value boundary (one output per node)
pvm.lower("solve", function(tree) return layout_solver(tree) end)
```

---

## Chapter 5: lower — Identity-Cached Function Boundaries

`pvm.lower` wraps a function with an identity cache. Same input → cached output.

### Basic usage

```lua
local compile = pvm.lower("layout", function(root)
    local out = {}
    root:place(0, 0, 800, 600, out)
    return out
end)

local cmds = compile(ui_tree)   -- runs layout, caches result
local cmds2 = compile(ui_tree)  -- same tree → cache hit → instant
```

### Stats and diagnostics

```lua
local stats = compile:stats()
print(stats.name, stats.calls, stats.hits)

-- Hit ratio shorthand:
print(compile:hit_ratio())    -- e.g. 0.98 (98%)

-- Inspect what is cached for a node (nil if not yet cached):
local cached = compile:cached(some_node)

-- Force pre-population (warm the cache eagerly):
compile:warm(some_node)
```

Use `pvm.report_string` to format multiple boundaries together:

```lua
print(pvm.report_string({ layout_boundary, solve_boundary }))
--   layout                   calls=120   hits=118   shared=0     reuse=98.3%
--   solve                    calls=44    hits=43    shared=0     reuse=97.7%
```

---

## Chapter 6: with — Structural Update Preserving Sharing

`pvm.with(node, overrides)` creates a new interned node with some fields
changed and all other fields identical:

```lua
local old_track = T.App.Track("Kick", 0xff0000, 75, 0, false, false, 0.6)
local new_track = pvm.with(old_track, { vol = 80 })

assert(new_track ~= old_track)          -- different vol → different node
assert(new_track.name == old_track.name) -- "Kick" — same string
assert(new_track.color == old_track.color) -- same number
```

### Why this matters for caching

When a phase boundary processes a TrackRow containing this track:

```lua
local row1 = T.App.TrackRow(1, old_track, false, false)
local row2 = T.App.TrackRow(1, new_track, false, false)
```

`row1 ~= row2` (different track) so the phase cache misses on this row.
But all OTHER rows (whose tracks didn't change) hit the cache.

One user edit → one cache miss → one subtree recompiles. Everything else
is cached. That is structural incrementality.

### Propagation

In a functional update pattern:
```lua
local new_source = pvm.with(source, {
    tracks = update_track(source.tracks, 2, function(t)
        return pvm.with(t, { vol = 80 })
    end)
})
```

Only track 2 is new. Tracks 1, 3, ... are the SAME objects. Every boundary
cache hits on them.

---

## Chapter 7: quote — Hygienic Codegen

`quote.lua` provides Terra-style metaprogramming for loadstring-based codegen.
It eliminates the three pain points of raw loadstring:

1. **Manual env tables** → `q:val(v, "name")` auto-captures upvalues
2. **Name collisions** → `q:sym("hint")` creates unique names
3. **Non-composable strings** → `q:emit(other_q)` splices quotes

### Basic usage

```lua
local Q = require("quote")

local q = Q()
local cache = q:val(setmetatable({}, {__mode="k"}), "cache")
local fn    = q:val(my_function, "fn")

q("return function(input)")
q("  local hit = %s[input]", cache)
q("  if hit then return hit end")
q("  local result = %s(input)", fn)
q("  %s[input] = result", cache)
q("  return result")
q("end")

local compiled, source = q:compile("=my_cache")
print(source)  -- readable, with named upvalues
```

Output:
```lua
return function(input)
  local hit = _cache[input]
  if hit then return hit end
  local result = _fn(input)
  _cache[input] = result
  return result
end
```

### API

| Method | What it does |
|--------|-------------|
| `q:val(v, "name")` | Register a Lua value as an upvalue. Returns its generated name. Same value → same name (deduplication). |
| `q:sym("hint")` | Create a unique symbol name. Never collides. |
| `q(fmt, ...)` | Append a formatted line (string.format if args given). |
| `q:block(str)` | Append a multi-line block verbatim. |
| `q:emit(other_q)` | Splice another quote's code AND bindings. |
| `q:source()` | Return the generated source string. |
| `q:compile("=name")` | loadstring + env setup. Returns `(function, source_string)`. |

### Why loadstring and not closures?

Closures match loadstring performance for simple cases (tested: 1.4ns vs 1.4ns
for constructors). But loadstring can do things closures cannot:

- **Inline handler bodies** into the dispatch function (zero call overhead)
- **Eliminate dead branches** (skip checks that always pass)
- **Specialize on field count** (unrolled trie with no loop variable)
- **Fuse across layers** (one function for lex + parse + emit)
- **Bake constants** (literal numbers in the generated code)

Closures are fixed function bodies with variable upvalues. Loadstring is a
**compiler** — it reshapes the code itself. That's why we keep it.

### Composable quotes

```lua
local inner = Q()
local x = inner:val(42, "x")
inner("local a = %s + 1", x)

local outer = Q()
outer("return function()")
outer:emit(inner)  -- splices inner's code AND its bindings
outer("  return a")
outer("end")

local fn = outer:compile("=composed")
assert(fn() == 43)
```

---

# Part II — The Execution Model

## Chapter 8: Flatten Early — Tree In, Flat Out, For-Loop Forever

This is the single most important structural pattern in pvm.

### The problem with trees

A tree of typed nodes looks natural. But it costs you at every level:

```text
UI ASDL (tree)
  → recursive :view()              ← O(N) dispatch calls
    → View ASDL (tree)             ← still a tree
      → recursive :paint()         ← O(N) dispatch calls again
        → recursive compose()      ← nested execution calls
```

Each tree layer multiplies the traversal cost. Method dispatch at every node
produces polymorphic call sites — LuaJIT cannot trace through them.

### The solution: flatten

Convert the tree into a flat array of commands with push/pop markers for
containment:

```text
Tree:                           Flat:
  Clip(0,0,800,600,             PushClip(0,0,800,600)
    Transform(10,20,              PushTransform(10,20)
      Rect(0,0,100,30,0xff)        Rect(0,0,100,30,0xff)
      Text(0,0,1,0xff,"hi")        Text(0,0,1,0xff,"hi")
    )                             PopTransform
  )                             PopClip
```

ONE recursive traversal (the layout walk) produces a flat list. Everything
after that is a `for i = 1, #cmds do` loop. No recursion. No dispatch. Linear.

### How it works in ui5

The layout walk's `:place()` method appends to an output list:

```lua
function T.UI.Column:place(x, y, mw, mh, out)
    local cy = y
    for i = 1, #self.children do
        local cw, ch = cached_measure(self.children[i], mw)
        self.children[i]:place(x, cy, mw, ch, out)
        cy = cy + ch + self.spacing
    end
end

function T.UI.Rect:place(x, y, mw, mh, out)
    out[#out+1] = VRect(self.tag, x, y, self.w, self.h, self.rgba8)
end

function T.UI.Clip:place(x, y, mw, mh, out)
    out[#out+1] = VPushClip(x, y, self.w, self.h)
    self.child:place(x, y, self.w, self.h, out)
    out[#out+1] = VPopClip
end
```

Containers (Clip, Transform) emit push before children and pop after.
Leaves (Rect, Text) emit a single command.

The layout walk fills a flat array imperatively. A phase boundary wraps
the walk, returning the result as a triplet via `pvm.seq`:

```lua
local compile = pvm.lower("compile", function(root_ui_node)
    local out = {}
    root_ui_node:place(0, 0, win_w, win_h, out)
    return out    -- lower caches this array on root_ui_node's identity
end)

-- Or, as a phase returning a triplet:
local render = pvm.phase("render", {
    [T.App.Root] = function(self)
        local ui_tree = build_ui(self)
        local out = {}
        ui_tree:place(0, 0, self.w, self.h, out)
        return pvm.seq(out)  -- wrap array as triplet
    end,
})

-- Execution: pull-driven, cache fills on drain
pvm.each(render(root), function(cmd) paint(cmd) end)
```

The layout walk stays imperative (`:place()` appending to `out`). The phase
boundary is what gives it lazy caching and composability.

---

## Chapter 9: State Is Always a Stack

When you flatten a tree, every container becomes a push/pop pair. The only
state the for-loop needs is: what containers are currently open?

That is a stack.

```lua
local clip_stack = {}
local tx_stack = { {0, 0} }

for i = 1, #cmds do
    local cmd = cmds[i]
    local k = cmd.kind
    if k == K_PUSH_CLIP then
        push(clip_stack, {cmd.x, cmd.y, cmd.w, cmd.h})
        love.graphics.setScissor(cmd.x, cmd.y, cmd.w, cmd.h)
    elseif k == K_POP_CLIP then
        pop(clip_stack)
        -- restore previous scissor or clear
    elseif k == K_PUSH_TX then
        local top = tx_stack[#tx_stack]
        push(tx_stack, {top[1] + cmd.tx, top[2] + cmd.ty})
        love.graphics.push()
        love.graphics.translate(cmd.tx, cmd.ty)
    elseif k == K_POP_TX then
        pop(tx_stack)
        love.graphics.pop()
    elseif k == K_RECT then
        love.graphics.setColor(rgba8_to_love(cmd.rgba8))
        love.graphics.rectangle("fill", cmd.x, cmd.y, cmd.w, cmd.h)
    elseif k == K_TEXT then
        love.graphics.setColor(rgba8_to_love(cmd.rgba8))
        love.graphics.print(cmd.text, cmd.x, cmd.y)
    end
end
```

The stack is the ONLY state shape for structural traversal. This is not a
design choice. It is a mathematical consequence of flattening.

If you find yourself needing complex mutable state during execution, either:
- You haven't flattened far enough (tree still present)
- You have genuine runtime state (audio delay, physics) that is separate
  from the authored structure

---

## Chapter 10: Each Recursion Class = One ASDL Layer

The rule that tells you how many layers you need:

```text
Layer 0: App.Widget  — structural recursion (TrackList contains TrackRows)
  ↓ phase boundary: widget:ui() → UI.Node
Layer 1: UI.Node     — structural recursion (Column contains children)
  ↓ layout walk: :place(x,y,mw,mh,out) → View.Cmd*
Layer 2: View.Cmd    — FLAT (no recursion, just an array)
  ↓ for-loop execution
```

**App.Widget** has structural recursion: TrackList contains Widgets, Inspector
contains Buttons and Sliders. This recursion is consumed by the phase boundary,
which produces UI.Nodes.

**UI.Node** has structural recursion: Column contains children, Padding wraps
a child. This recursion is consumed by the layout walk, which appends to a
flat output list.

**View.Cmd** has no recursion. It is a flat array. A for-loop iterates it.

The pattern: **count the recursive type layers, add one flat layer at the bottom.**

---

## Chapter 11: The Uniform Cmd Product Type

This is the crucial implementation insight for JIT-friendly execution.

### The design

```asdl
module View {
    Kind = Rect | Text | PushClip | PopClip | PushTransform | PopTransform

    Cmd = (View.Kind kind, string htag,
           number x, number y, number w, number h,
           number rgba8, number font_id, string text,
           number tx, number ty) unique
}
```

ONE product type. Not a sum type with per-variant fields. ALL fields always
present. Unused fields set to 0 or "".

### Why not a sum type?

A sum type:
```asdl
Cmd = RectCmd(string tag, number x, number y, number w, number h, number rgba8)
    | TextCmd(string tag, number x, number y, number font_id, number rgba8, string text)
    | PushClipCmd(number x, number y, number w, number h)
    | PopClipCmd
```

Each variant has a different metatable. A for-loop over mixed variants
encounters different metatables at each iteration. LuaJIT records the metatable
in its trace. Mixed metatables → trace abort → interpreter fallback → slow.

The uniform product type has ONE metatable for ALL commands. The for-loop
sees one metatable forever → one trace → compiled native code → fast.

### The Kind field

`Kind` is a singleton sum type — each variant has no fields. `T.View.Rect`,
`T.View.Text`, etc. are distinct Lua tables with different identity.

Comparing `cmd.kind == K_RECT` is a pointer comparison (table identity).
LuaJIT constant-folds it. The entire dispatch becomes a small integer switch
in the compiled trace.

### The waste trade-off

A Rect command carries `font_id=0, text=""` — unused fields. A PushClip
carries `rgba8=0, font_id=0, text=""` — more waste.

This is the correct trade-off:
- Memory cost: ~10 unused fields × 8 bytes = 80 bytes per command. Negligible.
- JIT cost of polymorphic metatables: trace aborts, interpreter fallback. Catastrophic.

One wasted metatable is infinitely cheaper than one trace abort.

---

## Chapter 12: The For-Loop IS the Slot

There is no `M.slot()`. No installation. No retirement. No swap ceremony.

Recompile → get a new Cmd array → iterate it.

```lua
function love.draw()
    -- render_phase(source) returns a triplet. pvm.each pulls lazily.
    -- Cache fills as side effect of full drain. Next frame: seq hit.
    pvm.each(render_phase(source), function(cmd)
        local k = cmd.kind
        if k == K_RECT then
            love.graphics.setColor(rgba8_to_love(cmd.rgba8))
            love.graphics.rectangle("fill", cmd.x, cmd.y, cmd.w, cmd.h)
        elseif k == K_TEXT then
            love.graphics.setFont(fonts[cmd.font_id])
            love.graphics.setColor(rgba8_to_love(cmd.rgba8))
            love.graphics.print(cmd.text, cmd.x, cmd.y)
        elseif k == K_PUSH_CLIP then
            love.graphics.setScissor(cmd.x, cmd.y, cmd.w, cmd.h)
        elseif k == K_POP_CLIP then
            love.graphics.setScissor()
        elseif k == K_PUSH_TX then
            love.graphics.push()
            love.graphics.translate(cmd.tx, cmd.ty)
        elseif k == K_POP_TX then
            love.graphics.pop()
        end
    end)
end
```

That is the entire execution story. `render_phase(source)` returns a triplet.
`pvm.each` pulls values out of it one by one, running the draw callback.
When fully drained, the cache commits. Next frame, if source is unchanged,
`render_phase(source)` returns a `seq_gen` hit — the callback runs over the
cached array directly, with zero handler invocations.

When the source changes, only the affected subtrees miss. The rest hit.

### Hit testing: drain then reverse for-loop

For hit testing, materialize first with `pvm.drain`, then reverse-iterate.
The same cached array serves both painting and hit testing:

```lua
-- Painting (pull-driven, no materialization needed):
pvm.each(render_phase(source), draw_cmd)

-- Hit testing (needs reverse order, so drain to array first):
local cmds = pvm.drain(render_phase(source))  -- instant seq hit if cached

function hit_test(cmds, mx, my)
    local tx, ty = 0, 0
    for i = #cmds, 1, -1 do
        local cmd = cmds[i]
        local k = cmd.kind
        -- Note: POP before PUSH because we're going backward
        if k == K_POP_TX then
            tx = tx + cmd.tx; ty = ty + cmd.ty
        elseif k == K_PUSH_TX then
            tx = tx - cmd.tx; ty = ty - cmd.ty
        elseif k == K_RECT or k == K_TEXT then
            local lx, ly = mx - tx, my - ty
            if lx >= cmd.x and lx < cmd.x + cmd.w
            and ly >= cmd.y and ly < cmd.y + cmd.h then
                return cmd.htag
            end
        end
    end
    return nil
end
```

Reverse iteration gives correct z-ordering: the last-painted element (topmost
visually) is tested first. Same Cmd array, no extra data structure.
`pvm.drain` is instant on a cache hit — it just copies the cached seq array.

---

# Part III — Building a Real App (ui5 Walkthrough)

## Chapter 13: The Three ASDL Layers

The ui5 track editor has exactly three layers:

```text
Layer 0: App.Widget   — 11 widget types (domain vocabulary)
  ↓ phase "ui" (memoized on widget identity)
Layer 1: UI.Node      — 10 layout types (Column, Row, Rect, Text, ...)
  ↓ layout walk :place() (appends to flat output)
Layer 2: View.Cmd     — 1 uniform product type (flat array)
  ↓ for-loop (paint, hit-test)
```

**Layer 0** speaks the domain language: TrackRow, Transport, Inspector, Button.
The user (application code) constructs App.Widget nodes every frame using
immediate-mode style — just call constructors.

**Layer 1** speaks the layout language: Column, Row, Padding, Rect, Text.
Each widget's `:ui()` handler returns a UI.Node tree describing its layout.

**Layer 2** speaks the draw language: one Cmd type with Kind = Rect|Text|PushClip|...
The layout walk flattens the UI.Node tree into a Cmd array.

### Why three and not two or four?

Two layers would mean going directly from App.Widget to View.Cmd. That would
force every widget handler to compute absolute positions — mixing domain logic
with layout. Bad separation of concerns.

Four layers would add an intermediate between UI.Node and View.Cmd — perhaps
a positioned-but-still-tree "View.Node". That is unnecessary because the
layout walk can flatten directly.

Three layers is the honest count: two recursive types (Widget, Node) + one
flat type (Cmd). The rule from Chapter 10 confirms it.

## Chapter 14: Layer 1 — Widgets as ASDL Types

Every widget is an ASDL type with `unique`:

```lua
T:Define [[
    module App {
        Widget = TrackRow(number index, App.Track track,
                          boolean selected, boolean hovered) unique
               | Button(string tag, number w, number h,
                        number bg, number fg, number font_id,
                        string label, boolean hovered) unique
               | Meter(string tag, number w, number h,
                       number level) unique
               | ... -- 11 widget types
    }
]]
```

### Immediate-mode authoring

Widgets are constructed fresh every frame from application state:

```lua
function build_widgets(s)
    local rows = {}
    for i = 1, #s.tracks do
        rows[i] = T.App.TrackRow(i, s.tracks[i],
                    i == s.selected, s.hover_tag == "track:"..i)
    end
    return Col(0, {
        Row(0, {
            Col(0, {
                T.App.Header(#s.tracks):ui(),
                T.App.TrackList(rows, s.scroll_y, s.view_h):ui(),
            }),
            T.App.Inspector(s.tracks[s.selected], s.selected, s.win_h, s.hover_tag):ui(),
        }),
        T.App.Transport(s.win_w, s.bpm, s.playing, time_str, beat_str, s.hover_tag):ui(),
    })
end
```

This looks like immediate-mode code — you call constructors every frame. But
because every type is `unique`, the constructors are actually interning lookups.
If the track data didn't change, `T.App.TrackRow(1, track, false, false)` returns
the SAME Lua table as last frame. The phase cache hits. The widget's entire
UI subtree is skipped.

**Immediate-mode authoring. Retained-mode performance.**

## Chapter 15: Layer 2 — The phase Boundary

The phase "ui" dispatches each widget type to its handler:

```lua
local widget_to_cmds = pvm.phase("ui", {

[T.App.Button] = function(self)
    local bg = self.hovered and C.panel_hi or self.bg
    return pvm.once(Rct(self.tag, self.w, self.h, bg))
end,

[T.App.Meter] = function(self)
    local fill_w = math.max(1, math.floor(self.w * self.level))
    local fill_color = self.level > 0.9 and C.meter_clip
                    or self.level > 0.7 and C.meter_hot
                    or C.meter_fill
    return pvm.concat2(
        pvm.once(Rct(self.tag..":fill", fill_w,          self.h, fill_color)),
        pvm.once(Rct(self.tag..":bg",   self.w - fill_w, self.h, C.meter_bg))
    )
end,

[T.App.TrackRow] = function(self)
    local t, tag = self.track, "track:"..self.index
    local bg = self.selected and C.row_active
            or self.hovered and C.row_hover
            or (self.index % 2 == 0 and C.row_even or C.row_odd)
    return pvm.once(Rct(tag, TRACK_W, ROW_H, bg))
    -- (simplified for brevity — real handler builds full row output)
end,

-- ... 8 more handlers

})
```

Handlers return triplets — `pvm.once` for leaves, `pvm.concat2/children` for
composites. The phase dispatches by type, wraps the handler's triplet in a
recording, and caches the drained result.

During animated playback, the phase reports:
```text
  ui                       calls=4174  hits=3037  shared=892   reuse=93.3%
```

93.3% reuse rate: 3037 full hits (handler not called, seq instant) plus 892
in-flight hits (shared recording, no duplicate eval). Only 245 full misses.

## Chapter 16: The Layout Walk (UI.Node → View.Cmd)

Layout methods on UI.Node compute sizes and emit flat View.Cmd:

### Measure

```lua
local measure_cache = setmetatable({}, { __mode = "k" })

local function cached_measure(node, mw)
    local by_node = measure_cache[node]
    if by_node then
        local hit = by_node[mw]
        if hit then return hit[1], hit[2] end
    end
    local w, h = node:measure(mw)
    if not by_node then by_node = {}; measure_cache[node] = by_node end
    by_node[mw] = { w, h }
    return w, h
end
```

The cache is keyed on (node identity × max width). Same node with same
constraint → cached measurement. This resolves the text-wrap cycle:
- Column needs child heights (calls cached_measure)
- Text needs available width (receives mw)
- cached_measure breaks the cycle by memoizing

### Place

```lua
function T.UI.Column:place(x, y, mw, mh, out)
    local cy = y
    for i = 1, #self.children do
        local cw, ch = cached_measure(self.children[i], mw)
        self.children[i]:place(x, cy, mw, ch, out)
        cy = cy + ch + self.spacing
    end
end

function T.UI.Rect:place(x, y, mw, mh, out)
    out[#out+1] = VRect(self.tag, x, y, self.w, self.h, self.rgba8)
end

function T.UI.Text:place(x, y, mw, mh, out)
    out[#out+1] = VText(self.tag, x, y, 0, 0, self.font_id, self.rgba8, self.text)
end

function T.UI.Clip:place(x, y, mw, mh, out)
    out[#out+1] = VPushClip(x, y, self.w, self.h)
    self.child:place(x, y, self.w, self.h, out)
    out[#out+1] = VPopClip
end

function T.UI.Transform:place(x, y, mw, mh, out)
    out[#out+1] = VPushTx(self.tx, self.ty)
    self.child:place(x + self.tx, y + self.ty, mw, mh, out)
    out[#out+1] = VPopTx
end
```

One recursive walk. Flat output. Every container emits push before children
and pop after. Every leaf emits one Cmd.

## Chapter 17: The Frame Budget

Where does time go in the ui5 track editor?

```text
build_widgets  = 14.3 µs  (90% of framework time)
compile/layout =  1.6 µs  (10% of framework time)
─────────────────────────
framework total = 15.9 µs  (1.0% of 16ms frame budget)

paint (Love2D)  = 343 µs   (21% of frame budget)
─────────────────────────
total           = 359 µs   (2.2% of frame budget)
```

The framework is not the bottleneck. Love2D draw calls are. The architecture
is so cheap (~16µs) that it disappears into noise.

This is the performance payoff of flatten-early + uniform Cmd + memoized verbs.

---

# Part IV — The Classification Discipline

## Chapter 18: Three Classes of Field

At every boundary, every field falls into one of three classes:

| Class | What it means | Where it goes |
|-------|--------------|---------------|
| **Code-shaping** | Determines which handler/branch runs | Sum type variant (phase dispatch) |
| **Payload** | Data read by the handler or for-loop | Fields on the output node |
| **Dead** | Not needed downstream | Stripped at the boundary |

### Code-shaping

Code-shaping fields determine WHICH code runs. In pvm, this is always a
sum type — the phase dispatches on the node's variant.

```text
App.Widget variant → determines which :ui() handler runs
UI.Node variant → determines which :measure()/:place() runs
View.Kind → determines which branch in the for-loop runs
```

If you find yourself switching on a string or number at runtime to decide
what code to execute, it should be a sum type instead.

### Payload

Payload is everything else — data that the handler reads but that does
not change which code runs.

```text
Button.tag, Button.w, Button.h, Button.bg → all payload
Rect.x, Rect.y, Rect.rgba8 → all payload
Track.name, Track.vol, Track.pan → all payload
```

### Dead

Dead fields are not needed by the downstream consumer. They should be
stripped at the boundary.

```text
At paint time: cmd.htag is dead (paint doesn't use hit tags)
At hit time: cmd.rgba8, cmd.font_id, cmd.text are dead (hit only needs geometry)
```

In ui5, the uniform Cmd type carries everything for ALL consumers. Each
consumer ignores irrelevant fields. This is the right trade-off for small
systems — one Cmd type is simpler than per-backend Cmd types.

For larger systems, you might have separate paint and hit Cmd types. The
layout walk would emit into separate lists. The boundary strips dead fields.

## Chapter 19: The Interning Test

Construct two nodes with the same fields. Assert they are the same object:

```lua
local a = T.UI.Rect("btn", 100, 30, 0xff0000ff)
local b = T.UI.Rect("btn", 100, 30, 0xff0000ff)
assert(rawequal(a, b), "interning is broken")
```

If this fails: `unique` is missing, or you're constructing objects by hand
(bypassing the constructor).

If identity changes on a pure-payload edit (e.g., changing only color):
```lua
local old = T.UI.Rect("btn", 100, 30, 0xff0000ff)
local new = T.UI.Rect("btn", 100, 30, 0x00ff00ff)
assert(old ~= new, "different color must be different identity")
assert(old.tag == new.tag, "unchanged fields must keep identity")
```

This is structural sharing working correctly.

## Chapter 20: Classification Errors

### Error 1: Code-shaping treated as payload

**Symptom**: Runtime branching on a string to decide behavior.

```lua
-- WRONG:
if node.kind_str == "biquad" then ... elseif node.kind_str == "gain" then ...

-- RIGHT: kind_str should be a sum type
-- Device = Biquad(...) | Gain(...) — phase dispatches by type
```

### Error 2: Payload treated as code-shaping

**Symptom**: Many unnecessary phase handlers that do the same thing.

```lua
-- WRONG: one handler per color
[T.RedButton]   = function(self) return Rct(self.tag, self.w, self.h, RED) end,
[T.GreenButton] = function(self) return Rct(self.tag, self.w, self.h, GREEN) end,

-- RIGHT: color is payload, one handler
[T.Button] = function(self) return Rct(self.tag, self.w, self.h, self.color) end,
```

### Error 3: Dead fields kept alive

**Symptom**: Wasted memory, false cache misses.

```lua
-- WRONG: paint Cmd carries hit-test tag
-- Changing the tag invalidates the interned Cmd
-- → cache miss → unnecessary recompile

-- RIGHT: strip dead fields at the boundary
-- Or: accept the waste in the uniform Cmd type (usually fine)
```

---

# Part V — uvm: Resumable Machine Algebra

## Chapter 21: When You Need uvm

pvm handles most applications: ASDL schemas, memoized boundaries, flat
execution. But some domains need machines that:

- **Pause and resume** (parsers, interactive debuggers)
- **Compose sequentially** (pipeline stages)
- **Signal status** (yielding values, trapping on errors)
- **Hot-swap** (change behavior while running)

uvm adds these capabilities on top of pvm:

```lua
local uvm = require("uvm")
-- uvm inherits everything from pvm: context, with, phase, lower, drain, each, report
-- uvm adds: family, image, machine, status protocol, composition ops
```

## Chapter 22: family / image / machine

**family** — a machine type. Defines the gen (step function), initialization,
patching, and metadata.

```lua
local counter_family = uvm.family {
    name = "counter",
    gen = function(param, state)
        state.n = state.n + param.step
        if state.n >= param.limit then
            return uvm.status.HALT, state.n
        end
        return uvm.status.YIELD, state.n
    end,
    init = function(param, seed)
        return { n = seed or 0 }
    end,
}
```

**image** — an immutable configuration snapshot. Created from a family
with specific parameters.

```lua
local img = counter_family:image({ step = 1, limit = 10 })
```

**machine** — a running instance. Has gen + param + state + status.

```lua
local m = counter_family:spawn(img, 0)  -- seed = 0
```

### Stepping

```lua
local status, value = m:step()
print(status, value)  -- 2 (YIELD), 1
status, value = m:step()
print(status, value)  -- 2 (YIELD), 2
-- ... until HALT
```

### Running to completion

```lua
local results = uvm.run.collect(m, 100)  -- max 100 steps
-- results = {1, 2, 3, ..., 10}
```

## Chapter 23: Status Protocol

| Code | Name | Meaning |
|------|------|---------|
| 1 | RUN | Not finished, continue stepping |
| 2 | YIELD | Produced a value, can continue |
| 3 | TRAP | Exceptional machine condition |
| 4 | HALT | Finished |

A step function returns `(next_state, status, a, b, c, d)`:

```lua
step = function(param, state)
    -- do work
    if done then return nil, uvm.status.HALT, result end
    if produced_value then return state, uvm.status.YIELD, value end
    return state, uvm.status.RUN
end
```

## Chapter 24: Composition Ops

**chain(fa, fb)** — run family A, feed result to family B:
```lua
local pipeline = uvm.op.chain(tokenizer_family, parser_family)
```

**guard(fam, fn)** — run only if guard function returns true:
```lua
local guarded = uvm.op.guard(processor, function(param)
    return param.enabled
end)
```

**limit(fam, n)** — run at most n steps:
```lua
local bounded = uvm.op.limit(solver, 1000)
```

**fuse(decoder, exec)** — decode a stream into dispatched execution:
```lua
local vm = uvm.op.fuse(instruction_decoder, execute_step)
```

## Chapter 25: Worked Example — ASDL Parser as uvm Machine

The ASDL parser (asdl_parser3.lua) is a uvm machine that parses ASDL
definitions with full resumability at definition boundaries:

```lua
local parser_family = uvm.families.stream("asdl_parse", function(param, state)
    -- Coarse-grained: parse one complete definition per step
    -- Recursive descent WITHIN the step (no uvm overhead)
    local def = parse_one_definition(param.input, state.pos)
    state.pos = def.end_pos
    if state.pos >= #param.input then
        return uvm.status.HALT, def
    end
    return uvm.status.YIELD, def
end)
```

Performance: matches recursive descent speed (1.1×) because the grain
is coarse — one step per definition, not per token.

### The grain-size principle

| Grain | Overhead | Use case |
|-------|----------|----------|
| Per token | 7× slower | Fine control (debugger, interactive) |
| Per definition | 0% overhead | Resumable at semantic boundaries |
| Per file | None | Batch processing |

Rule: step at semantic boundaries, recurse within them.

---

# Part VI — Performance and Diagnostics

## Chapter 26: pvm.report() — The Design Quality Metric

```lua
print(pvm.report_string({ widget_to_cmds, layout_boundary }))
```

Output:
```text
  ui                       calls=4174  hits=3037  shared=892   reuse=93.3%
  layout                   calls=120   hits=118   shared=0     reuse=98.3%
```

| Metric | Meaning |
|--------|---------|
| `hits` | Cache hit: seq_gen over cached array, zero handler work |
| `shared` | In-flight hit: shared recording, no duplicate evaluation |
| `reuse` | `(hits + shared) / calls` — the true quality metric |

| Reuse rate | Meaning |
|-----------|---------|
| 90%+ | Excellent. Structural sharing works. Incrementality is real. |
| 70-90% | Good during animation (things genuinely change). |
| Below 50% | ASDL design problem. Too much recompilation. |

The reuse ratio IS the architecture quality metric. If one small edit causes
many full misses, the ASDL boundaries are too coarse, structural sharing
is broken, or identity is unstable.

For `pvm.lower` boundaries (single-value, no `shared`), the hit ratio alone
is the metric: `hits / calls`.

## Chapter 27: Codegen Inspection

ASDL constructors are code-generated via `quote.lua`. Every constructor stores
its generated source on the type's metatable and can be inspected for debugging:

```lua
-- ASDL constructor codegen (interning trie, unrolled per field count):
-- Access via the type's metatable.__source if exposed by asdl_context
```

`pvm.phase` dispatch uses a direct `getmetatable` lookup — no loadstring,
no generated source to inspect. The dispatch is a single table read followed
by a function call: simple, predictable, and JIT-friendly.

`pvm.lower` similarly uses a plain closure cache — no codegen.

For custom hot-path generation (specialized inner loops, shader compilation,
audio kernel generation), use `quote.lua` directly:

```lua
local Q = require("quote")
local q = Q()
local threshold = q:val(0.9, "threshold")
q("return function(level)")
q("  return level > %s", threshold)
q("end")
local fn = q:compile("=hot_check")
```

The generated source IS what LuaJIT traces for your custom kernels.
Read `q:source()` to inspect it.

## Chapter 28: Benchmark Patterns

| What | Cold (miss) | Hot (hit) |
|------|-------------|-----------|
| ASDL constructor (all-builtin, unique) | 1.6 ns | 0 ns |
| ASDL constructor (with ASDL fields) | 25 ns | 0 ns |
| phase dispatch (seq hit, no handler) | ~1 ns | — |
| phase dispatch (recording, handler runs) | handler cost | — |
| lower (cache hit) | 0.9 ns | — |
| Full ui5 frame (build + compile) | 16 µs | — |

### JSON benchmark (real-world)

```text
FFI fused (1 pass, no ASDL):   107 MB/s
pvm 3-layer (lex + parse + emit):  85 MB/s  (1.3× vs fused)
```

The 3-layer ASDL approach is only 1.3× slower than raw hand-written code,
while providing full structural interning, memoized boundaries, and
typed intermediate representations.

## Chapter 29: What LuaJIT Traces

LuaJIT's trace compiler is what makes flat execution fast. Understanding
what it can and cannot trace is essential:

**Traces well:**
- Uniform metatable in a for-loop (one Cmd type)
- Pointer comparison (`cmd.kind == K_RECT`)
- Stable upvalues in generated functions
- Simple arithmetic and table lookups
- Linear iteration over arrays

**Does NOT trace well:**
- Mixed metatables in a loop (sum type variants = trace abort)
- `select(i, ...)` (NYI in traces)
- `type()` checks in hot paths (NYI in some cases)
- Nested closures as dispatch targets (polymorphic calls)
- `pairs()` / `next()` in hot paths (NYI)

This is why:
- Cmd is one product type, not a sum type → traces
- Kind comparison is pointer, not string → traces
- `pvm.each` / `pvm.drain` iteration is linear, not recursive → traces
- Cached results are flat arrays → seq_gen loops trace cleanly
- Phase hit path is `seq_gen(array, i)` — pure integer increment + table read → traces

---

# Part VII — Design Methodology

## Chapter 30: The Complete Design Method

### Top-down: model the domain

1. List the nouns (§5.1)
2. Find identity nouns vs. properties (§5.2)
3. Find sum types (§5.3)
4. Draw containment (§5.4)
5. Find coupling points (§5.5)
6. Define layers (§5.6)
7. Test the ASDL (§5.7)

### Bottom-up: imagine the for-loop

8. What does the for-loop need? (What Cmd fields?)
9. What ASDL layer produces those Cmds?
10. What layer above produces the nodes for that layer?
11. Recurse upward until you reach the user's vocabulary

### Meet in the middle

12. The top-down draft and the bottom-up demands converge
13. Fix mismatches: missing fields → add to ASDL. Missing boundary → add layer.
14. ASDL stabilizes when the for-loop stops demanding changes

## Chapter 31: Test the ASDL

Before writing any boundary code:

```text
□ Save/load: every user-visible aspect round-trips
□ Undo: revert root → cache hit → instant
□ Completeness: every variant reachable, every state representable
□ Minimality: every field independently editable
□ Orthogonality: independent fields don't constrain each other
□ Testing: every function testable with one constructor + one assertion
```

## Chapter 32: Design for Incrementality

```text
□ All types marked unique
□ Edits via pvm.with() (preserves structural sharing)
□ phase/lower boundaries at identity nouns
□ Changed subtree is small relative to whole
□ pvm.report_string() shows >70% reuse rate
```

## Chapter 33: The Convergence Cycle

```text
DRAFT (top-down)
  → EXPANSION (for-loop demands new types/boundaries)
    → COLLAPSE (redundant types merge, final ASDL emerges)
```

Signs of expansion: trace aborts, low cache hits, long handlers.
Signs of collapse readiness: clean traces, 90%+ cache hits, structural similarity.
Convergence: new features are additive (one variant + one handler).

## Chapter 34: The Design Checklist

### ASDL
```text
□ Every user-visible thing is an ASDL type
□ Every "or" is a sum type (not a string)
□ Every type is unique (interned)
□ No backend concerns in source ASDL
□ No derived values in source ASDL
□ Cross-references are IDs, not Lua pointers
```

### Layers
```text
□ Layer count = number of recursive types + 1 flat
□ Each boundary has a named verb
□ Each boundary consumes at least one decision
□ Final layer is flat (Cmd array)
```

### Flatten-early
```text
□ Cmd type is uniform (one product, Kind singleton)
□ Containment is push/pop markers
□ For-loop execution (no recursive dispatch)
□ State is push/pop stacks only
```

### Boundaries
```text
□ phase for type-dispatched streaming boundaries
□   handlers return triplets (pvm.once / pvm.children / pvm.concat2/3/all)
□ lower for type-agnostic single-value boundaries
□ Cache on identity (not manual keys)
□ pvm.report_string() checked regularly
```

### Execution
```text
□ Paint: pvm.each(phase(root), draw_fn) — pull-driven, lazy
□ Hit: pvm.drain(phase(root)) → reverse for-loop over materialized array
□ No source-level semantics rediscovered during execution
□ State in the execution loop is push/pop stacks only
```

## Chapter 35: Common Anti-Patterns

| Anti-pattern | Symptom | Fix |
|-------------|---------|-----|
| God ASDL | One huge type covers everything | Split into layers |
| String dispatch | `if kind == "rect"` in hot path | Sum type + phase |
| Closures per call | New function every frame | Define handlers at module scope |
| Mutating interned nodes | Mysterious cross-tree bugs | Use pvm.with() |
| Polymorphic Cmd types | Trace aborts in for-loop | Uniform product + Kind singleton |
| Deep nesting at execution | No flattening, trees reach the for-loop | Flatten to Cmd array via pvm.drain/each |
| Monolithic boundary | One handler does layout AND projection | Split into phase + lower |
| Missing boundary | No caching, full recompute every frame | Add phase/lower at identity nouns |
| Eager handler (returns value not triplet) | Cache never fills, no composition | Return pvm.once(v) not v |

---

# Appendices

## Appendix A: ASDL Syntax Quick Reference

```text
# Module
module Name { definitions... }

# Product type
TypeName = (field_type field_name, ...) unique?

# Sum type
TypeName = Variant1(fields...) unique?
         | Variant2(fields...) unique?
         | Variant3                       -- no fields = singleton

# Field types
number, string, boolean                   -- builtins
Module.TypeName                           -- ASDL type
Module.TypeName*                          -- list
Module.TypeName?                          -- optional
```

## Appendix B: pvm API Reference

```lua
-- ── Context and types ──────────────────────────────────────────────────
pvm.context()                          → T (ASDL context)
T:Define(schema_string)                → T (chainable)

-- ── Structural update ─────────────────────────────────────────────────
pvm.with(node, {field=value, ...})     → new interned node

-- ── Phase boundary (streaming, type-dispatched) ───────────────────────
pvm.phase(name, handlers)              → boundary
  -- handlers: { [ASDLType] = function(node) → (g, p, c) }
  -- Installs node:name() method on each handled type.
  -- On hit:     returns seq_gen over cached array (zero work)
  -- On shared:  returns recording_gen shared with in-flight consumer
  -- On miss:    dispatches handler, wraps triplet in recording_gen
  --             cache commits as side effect of full drain
  boundary(node)           → g, p, c    -- call form
  node:name()              → g, p, c    -- method form

-- ── Lower boundary (single-value, type-agnostic) ──────────────────────
pvm.lower(name, fn)                    → boundary
  -- fn: function(node) → value
  -- Caches one value per node identity. Returns value directly (not triplet).
  boundary(node)           → value

-- ── Boundary methods (both phase and lower) ───────────────────────────
boundary:stats()           → { name, calls, hits, shared? }
boundary:hit_ratio()       → number         -- hits / calls
boundary:reuse_ratio()     → number         -- (hits + shared) / calls (phase only)
boundary:reset()           → nil            -- clear cache and stats
boundary:cached(node)      → value or nil   -- inspect cache without populating
boundary:warm(node)        → value or array -- pre-populate (phase: drains; lower: calls)

-- ── Triplet constructors ───────────────────────────────────────────────
pvm.once(value)                        → g, p, c   -- single-element triplet
pvm.empty()                            → g, p, c   -- zero-element triplet
pvm.seq(array, n?)                     → g, p, c   -- array as forward triplet
pvm.seq_rev(array, n?)                 → g, p, c   -- array as reverse triplet

-- ── Triplet composition ────────────────────────────────────────────────
pvm.concat2(g1,p1,c1, g2,p2,c2)       → g, p, c   -- concat two triplets
pvm.concat3(g1,p1,c1, ..., g3,p3,c3)  → g, p, c   -- concat three triplets
pvm.concat_all(trips)                  → g, p, c   -- concat N triplets (array of {g,p,c})
pvm.children(phase_fn, array, n?)      → g, p, c   -- map phase over children, lazy concat

-- ── Triplet terminals ─────────────────────────────────────────────────
pvm.drain(g, p, c)                     → table     -- materialize all values to array
pvm.drain_into(g, p, c, out)           → out       -- append all values to existing array
pvm.each(g, p, c, fn)                  → nil       -- call fn(value) for each element
pvm.fold(g, p, c, init, fn)            → acc       -- reduce: acc = fn(acc, value)

-- ── Triplet algebra (pvm.T = triplet.lua) ─────────────────────────────
pvm.T.map(f, g, p, c)                  → g, p, c
pvm.T.filter(pred, g, p, c)            → g, p, c
pvm.T.take(n, g, p, c)                 → g, p, c
pvm.T.drop(n, g, p, c)                 → g, p, c
pvm.T.flatmap(f, g, p, c)              → g, p, c
pvm.T.zip(g1,p1,c1, g2,p2,c2)         → g, p, c
pvm.T.concat(g1,p1,c1, g2,p2,c2)      → g, p, c
pvm.T.scan(f, acc, g, p, c)            → g, p, c
pvm.T.dedup(g, p, c)                   → g, p, c
pvm.T.take_while(pred, g, p, c)        → g, p, c
pvm.T.collect(g, p, c)                 → table
pvm.T.fold(f, acc, g, p, c)            → acc
pvm.T.each(f, g, p, c)                 → nil
pvm.T.first(g, p, c, default)          → value
pvm.T.count(g, p, c)                   → number
pvm.T.any(pred, g, p, c)               → boolean
pvm.T.all(pred, g, p, c)               → boolean
pvm.T.find(pred, g, p, c)              → value or nil
-- ... (full algebra in triplet.lua)

-- ── Diagnostics ───────────────────────────────────────────────────────
pvm.report(phases)         → table of {name, calls, hits, shared, ratio, reuse_ratio}
pvm.report_string(phases)  → formatted string (one line per boundary)
```

## Appendix C: uvm API Reference

```lua
-- Inherits all of pvm

-- Status protocol
uvm.status.RUN           = 1
uvm.status.YIELD         = 2
uvm.status.TRAP          = 3
uvm.status.HALT          = 4

-- Family
uvm.family(spec)                     → family
  spec.name                          -- string
  spec.step                          -- function(param, state) -> ns, status, a, b, c, d
  spec.init                          -- function(param, seed) -> state
  spec.patch                         -- function(old_param, new_param, old_state) -> state

-- Image
family:image(parts)                  → image
image:clone(overrides)               → image

-- Machine
family:spawn(image_or_param, seed)   → machine
machine:step()                       → status, a, b, c, d
machine:run(budget)                  → status, a, b, c, d, steps
machine:is_halted()                  → boolean
machine:triplet()                    → gen, param, state

-- Composition
family:chain(other)                  → family
family:guard(pred)                   → family
family:limit(max_steps)              → family
family:fuse(exec_fn)                 → family
family:compile(opts?)                → family

-- Drivers
uvm.run.to_halt(machine, max)        → status, a, b, c, d, steps
uvm.run.collect(machine, max)        → rows, status, a, b, c, d, steps
uvm.run.collect_flat(machine, max)   → flat, n, status, a, b, c, d, steps
uvm.run.each(machine, max, sink)     → status, a, b, c, d, steps
uvm.run.trace(machine, max, sink)    → status, a, b, c, d, steps

-- Factory helpers
uvm.stream(name, step, opts)         → family
uvm.runner(name, step, opts)         → family
uvm.dispatch(opts)                   → family

-- Handwritten coarse JSON helpers
uvm.json.raw_decode(src)             → lua_value
uvm.json.decoder(opts?)              → family
uvm.json.define_types(ctx?, name?)   → asdl_context
uvm.json.raw_decode_asdl(src, opts?) → asdl_value
uvm.json.asdl_decoder(opts?)         → family

-- Generated JSON helpers (compile spec -> lowered plan -> generated decoder)
uvm.json.spec_types(ctx?)            → asdl_context
uvm.json.plan_types(ctx?)            → asdl_context
uvm.json.spec_table(ctx?)            → UJsonSpec.Spec
uvm.json.spec_asdl(opts?)            → UJsonSpec.Spec
uvm.json.generated(opts?)            → { decode=fn, source=string, spec=UJsonSpec.Spec, plan=UJsonPlan.Plan }
uvm.json.generated_decoder(opts?)    → family
uvm.json.generated_asdl_decoder(opts?) → family
```

Example:

```lua
local uvm = require("uvm")

local fam = uvm.json.decoder():compile()
local st, value = fam:spawn({ source = '{"a":1,"b":[2,3]}' }):run()
assert(st == uvm.status.YIELD)
assert(value.a == 1 and value.b[2] == 3)

local T = uvm.json.define_types()
local afam = uvm.json.asdl_decoder({ types = T })
local _, node = afam:spawn({ source = '{"ok":true}' }):run()
assert(node.kind == "Obj")

local spec = uvm.json.spec_asdl({ types = T })
local gen = uvm.json.generated({ spec = spec })
assert(gen.plan ~= nil)
```

See also: `examples/json_uvm.lua`.

## Appendix D: quote.lua API Reference

```lua
local Q = require("quote")

local q = Q()                        -- new quote builder
q:val(value, "hint")                 -- register upvalue, returns name
q:sym("hint")                        -- create unique symbol name
q("format string", ...)              -- append formatted line
q:block("multi-line string")         -- append block
q:emit(other_quote)                  -- splice code + bindings
q:source()                           -- return source string
q:compile("=chunk_name")             -- → function, source_string
```

## Appendix E: Glossary

**ASDL** — Abstract Syntax Description Language. Defines typed, interned
algebraic data types.

**Boundary** — A memoized transformation. `pvm.phase` (type-dispatched streaming,
returns triplet) or `pvm.lower` (identity-cached single value).

**Cmd** — The flat command record. One product type with Kind singleton tag.

**Flatten-early** — Convert trees to flat Cmd arrays as soon as layout is resolved.

**Interning** — Same field values → same Lua table. Enabled by `unique`.

**Kind** — Singleton sum type used as a tag in the uniform Cmd product type.

**Lower** — Identity-cached single-value boundary. `pvm.lower(name, fn)`. The function
receives a node and returns one value (not a triplet). Use for solved layouts,
scheduled plans, or any boundary that produces exactly one output per node.

**Structural sharing** — Unchanged subtrees keep identity across edits via `pvm.with()`.

**Unique** — ASDL modifier enabling structural interning.

**Phase** — Type-dispatched recording-triplet boundary. `pvm.phase(name, handlers)`.
Handlers dispatch by ASDL type and return a triplet `(g, p, c)`. Cache fills lazily
as a side effect of draining. Installs `node:name()` method on each handled type.

**Recording triplet** — The miss-path result of a `pvm.phase` call. A
`(recording_gen, entry, 0)` triplet that lazily evaluates the handler's output,
buffers values, and commits to cache when fully drained. Multiple consumers of the
same in-flight node share one recording entry (the `shared` stat).
