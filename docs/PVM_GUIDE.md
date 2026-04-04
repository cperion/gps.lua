# The Complete Guide to pvm/uvm

> **pvm** (365 lines) is the foundation: ASDL context, structural update,
> memoized boundaries, code-generated dispatch.
>
> **uvm** (523 lines) extends pvm with resumable machine algebra:
> family/image/machine, status protocol, composition operators.
>
> **quote.lua** (148 lines) provides hygienic codegen: auto-captured upvalues,
> gensym, composable code fragments.
>
> Together: 1036 lines. That is the entire framework.

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
| `pvm.lower(name, fn)` | Identity-cached function boundary |
| `pvm.verb(name, handlers, {cache=true})` | Type-dispatched cached method install |
| `pvm.report(items)` | Diagnostic report on cache behavior |

Plus three helpers for iterators (`collect`, `fold`, `each`) and one for
composing stages (`pipe`).

Total: 365 lines of Lua. Everything else — your ASDL schemas, your layout
algorithms, your rendering, your interaction — is your domain.

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

-- 4. Type-dispatched cached boundary
local greet = pvm.verb("greet", {
    [T.Greet.English] = function(self) return "Hello, " .. self.name end,
    [T.Greet.French]  = function(self) return "Bonjour, " .. self.name end,
    [T.Greet.German]  = function(self) return "Hallo, " .. self.name end,
}, { cache = true })
-- Wait — verb dispatches on the metatable of the first arg.
-- For a Message with a Lang field, we'd dispatch on Message's metatable.
-- Let's show the real pattern: verb on the Message type.

local translate = pvm.verb("translate", {
    [T.Greet.Message] = function(self)
        local k = self.lang.kind
        if k == "English" then return "Hello, " .. self.name
        elseif k == "French" then return "Bonjour, " .. self.name
        elseif k == "German" then return "Hallo, " .. self.name end
    end,
}, { cache = true })

-- Now: m1:translate() returns "Hello, world" (and caches it)
assert(m1:translate() == "Hello, world")
assert(m1:translate() == "Hello, world")  -- cache hit, handler not called

-- 5. Diagnostics
print(pvm.report({translate}))
-- verb:translate  calls=2  hits=1  rate=50%
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

## Chapter 4: verb — Type-Dispatched Cached Methods

`pvm.verb` is the primary boundary primitive. It does three things in one call:

1. **Dispatches** by the node's ASDL type (metatable pointer comparison)
2. **Caches** the result on the node's identity
3. **Installs** a method on each type so you can call `node:name()`

### Basic usage

```lua
local widget_to_ui = pvm.verb("ui", {
    [T.App.Button]   = function(self)
        return Rct(self.tag, self.w, self.h, self.bg)
    end,
    [T.App.Meter]    = function(self)
        local fill_w = math.floor(self.w * self.level)
        return Row(0, {
            Rct(self.tag..":fill", fill_w, self.h, green),
            Rct(self.tag..":bg", self.w - fill_w, self.h, gray),
        })
    end,
    [T.App.TrackRow] = function(self)
        return Col(0, { ... })  -- complex layout tree
    end,
}, { cache = true })
```

After this, every App.Widget node has a `:ui()` method:
```lua
local ui_tree = widget:ui()   -- dispatches to the right handler, caches result
```

### The generated code

verb generates a single function via loadstring. You can inspect it:

```lua
print(widget_to_ui.source)
```

Output:
```lua
return function(node)
  _stats.calls = _stats.calls + 1
  local hit = _cache[node]
  if hit ~= nil then _stats.hits = _stats.hits + 1; return hit end
  local mt = _getmetatable(node)
  local result
  if mt == _class_1 then result = _handler_1(node)
  elseif mt == _class_2 then result = _handler_2(node)
  elseif mt == _class_3 then result = _handler_3(node)
  else error('pvm.verb "ui": no handler for ' .. tostring(mt and mt.kind or type(node)), 2)
  end
  _cache[node] = result
  return result
end
```

One function. No table dispatch. No closures. No `select()`. The upvalues
(`_class_1`, `_handler_1`, `_cache`, `_stats`) are constants from LuaJIT's
perspective — they never change after creation. The JIT traces this as tight
straight-line code.

### Cache behavior

The cache is a weak-keyed table: `cache[node] → result`. If the same
interned node is passed again, the handler is not called — the cached result
is returned directly.

```lua
local w = T.App.Button("play", 48, 30, 0xff, 0xffffff, 1, "▶", false)
w:ui()   -- cache miss → handler runs → result cached
w:ui()   -- cache hit → handler NOT called → cached result returned
```

This is why interning matters: same fields → same node → cache hit.

### Without cache

Omit `{cache = true}` for boundaries that should always re-run:
```lua
local debug_print = pvm.verb("debug", {
    [T.App.Button] = function(self) print("Button:", self.tag) end,
    [T.App.Meter]  = function(self) print("Meter:", self.tag, self.level) end,
})
-- No cache. Every call runs the handler.
```

### verb vs lower

Use **verb** when you dispatch by type (sum types, multiple handlers).
Use **lower** when you don't dispatch — one function, cache on identity.

```lua
-- verb: different handler per widget type
pvm.verb("ui", { [T.App.Button]=fn1, [T.App.Meter]=fn2 }, {cache=true})

-- lower: one function, cache on input identity
pvm.lower("compile", function(root) return layout(root) end)
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

### Input types

lower can specialize its cache for the input type:

```lua
-- For ASDL nodes (table identity):
pvm.lower("layout", fn, { input = "table" })

-- For strings (string hash):
pvm.lower("parse", fn, { input = "string" })

-- For anything (generic, slightly slower):
pvm.lower("transform", fn)  -- default: "any"
```

### Generated code

Like verb, lower generates its cache function via quote.lua:

```lua
return function(input)
  _stats.calls = _stats.calls + 1
  local hit = _cache[input]
  if hit ~= nil then _stats.hits = _stats.hits + 1; return hit end
  local result = _fn(input)
  _cache[input] = result
  return result
end
```

### Stats

```lua
local stats = compile:stats()
print(stats.name, stats.calls, stats.hits)
```

Or use `pvm.report()` which formats all boundaries:
```lua
print(pvm.report({ widget_to_ui, compile }))
-- verb:ui       calls=4174  hits=3037  rate=72%
-- layout        calls=120   hits=118   rate=98%
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

When a verb boundary processes a TrackRow containing this track:

```lua
local row1 = T.App.TrackRow(1, old_track, false, false)
local row2 = T.App.TrackRow(1, new_track, false, false)
```

`row1 ~= row2` (different track) so the verb cache misses on this row.
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
for constructors, 6.2ns vs 7.3ns for verb dispatch). But loadstring can do things
closures cannot:

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
Leaves (Rect, Text) emit a single command. The output is a flat `View.Cmd*` list.

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
  ↓ verb boundary: widget:ui() → UI.Node
Layer 1: UI.Node     — structural recursion (Column contains children)
  ↓ layout walk: :place(x,y,mw,mh,out) → View.Cmd*
Layer 2: View.Cmd    — FLAT (no recursion, just an array)
  ↓ for-loop execution
```

**App.Widget** has structural recursion: TrackList contains Widgets, Inspector
contains Buttons and Sliders. This recursion is consumed by the verb boundary,
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
    local cmds = compile(build_ui(source))

    for i = 1, #cmds do
        local cmd = cmds[i]
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
    end
end
```

That is the entire execution story. The Cmd array is the installed artifact.
When the source changes, verb/lower boundaries produce a new Cmd array.
The old one is garbage-collected. The new one is iterated.

### Hit testing: reverse for-loop

Same Cmd array, different direction:

```lua
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

---

# Part III — Building a Real App (ui5 Walkthrough)

## Chapter 13: The Three ASDL Layers

The ui5 track editor has exactly three layers:

```text
Layer 0: App.Widget   — 11 widget types (domain vocabulary)
  ↓ verb "ui" (memoized on widget identity)
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
the SAME Lua table as last frame. The verb cache hits. The widget's entire
UI subtree is skipped.

**Immediate-mode authoring. Retained-mode performance.**

## Chapter 15: Layer 2 — The verb Boundary

The verb "ui" dispatches each widget type to its handler:

```lua
local widget_to_ui = pvm.verb("ui", {

[T.App.Button] = function(self)
    local bg = self.hovered and C.panel_hi or self.bg
    return Rct(self.tag, self.w, self.h, bg)
end,

[T.App.Meter] = function(self)
    local fill_w = math.max(1, math.floor(self.w * self.level))
    local fill_color = self.level > 0.9 and C.meter_clip
                    or self.level > 0.7 and C.meter_hot
                    or C.meter_fill
    return Row(0, {
        Rct(self.tag..":fill", fill_w, self.h, fill_color),
        Rct(self.tag..":bg", self.w - fill_w, self.h, C.meter_bg),
    })
end,

[T.App.TrackRow] = function(self)
    -- Complex layout: name, mute/solo buttons, meter, color swatch
    local t, tag = self.track, "track:"..self.index
    local bg = self.selected and C.row_active
            or self.hovered and C.row_hover
            or (self.index % 2 == 0 and C.row_even or C.row_odd)
    return Rct(tag, TRACK_W, ROW_H, bg)
    -- (simplified for brevity — real handler builds full row layout)
end,

-- ... 8 more handlers

}, { cache = true })
```

During animated playback, the verb reports:
```text
verb:ui  calls=4174  hits=3037  rate=72%
```

72% of widget-to-UI conversions are cache hits — the widget didn't change,
so its entire UI subtree is reused from last frame.

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
| **Code-shaping** | Determines which handler/branch runs | Sum type variant (verb dispatch) |
| **Payload** | Data read by the handler or for-loop | Fields on the output node |
| **Dead** | Not needed downstream | Stripped at the boundary |

### Code-shaping

Code-shaping fields determine WHICH code runs. In pvm, this is always a
sum type — the verb dispatches on the node's variant.

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
-- Device = Biquad(...) | Gain(...) — verb dispatches by type
```

### Error 2: Payload treated as code-shaping

**Symptom**: Many unnecessary verb handlers that do the same thing.

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
-- uvm inherits everything from pvm: context, with, lower, verb, report
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
print(pvm.report({ widget_to_ui, compile_layout }))
```

Output:
```text
  verb:ui          calls=4174  hits=3037  rate=72%
  layout           calls=120   hits=118   rate=98%
```

| Rate | Meaning |
|------|---------|
| 90%+ | Excellent. Structural sharing works. Incrementality is real. |
| 70-90% | Good during animation (things genuinely change). |
| Below 50% | ASDL design problem. Too much recompilation. |

The hit ratio IS the architecture quality metric. If one small edit causes
many cache misses, the ASDL boundaries are too coarse, structural sharing
is broken, or identity is unstable.

## Chapter 27: Codegen Inspection

Every codegen'd function stores its source:

```lua
-- verb dispatch:
print(widget_to_ui.source)

-- lower cache:
print(compile_layout.source)
```

The generated source IS what LuaJIT traces. If you want to understand
performance, read the generated source.

## Chapter 28: Benchmark Patterns

| What | Cold (miss) | Hot (hit) |
|------|-------------|-----------|
| ASDL constructor (all-builtin, unique) | 1.6 ns | 0 ns |
| ASDL constructor (with ASDL fields) | 25 ns | 0 ns |
| verb dispatch (cache hit) | 0.7 ns | — |
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
- Codegen produces unrolled dispatch, not loops → traces
- Flat array iteration, not tree recursion → traces

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
□ verb/lower boundaries at identity nouns
□ Changed subtree is small relative to whole
□ pvm.report() shows >70% hit rate
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
□ verb for type-dispatched transforms
□ lower for type-agnostic transforms
□ Cache on identity (not manual keys)
□ pvm.report() checked regularly
```

### Execution
```text
□ Paint: forward for-loop over Cmd array
□ Hit: reverse for-loop over same array
□ No source-level semantics rediscovered during execution
□ Generated dispatch inspected via .source
```

## Chapter 35: Common Anti-Patterns

| Anti-pattern | Symptom | Fix |
|-------------|---------|-----|
| God ASDL | One huge type covers everything | Split into layers |
| String dispatch | `if kind == "rect"` in hot path | Sum type + verb |
| Closures per call | New function every frame | Define handlers at module scope |
| Mutating interned nodes | Mysterious cross-tree bugs | Use pvm.with() |
| Polymorphic Cmd types | Trace aborts in for-loop | Uniform product + Kind singleton |
| Deep nesting at execution | Nested gen calls, no flattening | Flatten to Cmd array |
| Monolithic boundary | One function does layout AND projection | Split into verb + lower |
| Missing boundary | No caching, full recompute | Add verb/lower at identity nouns |

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
-- Context and types
pvm.context()                        → T (ASDL context)
T:Define(schema_string)              → T (chainable)

-- Structural update
pvm.with(node, {field=value, ...})   → new interned node

-- Boundaries
pvm.lower(name, fn, opts?)           → boundary (callable + stats + source)
pvm.verb(name, handlers, opts?)      → boundary (callable + stats + source)
  opts.cache = true                  -- enable identity cache
  opts.name = "custom name"          -- override stats name

-- Iterators
pvm.collect(gen, param, state)       → table
pvm.fold(gen, param, state, step, acc) → acc
pvm.each(gen, param, state, fn)      → nil
pvm.count(gen, param, state)         → number

-- Composition
pvm.pipe(stage1, stage2, ...)        → stage

-- Diagnostics
pvm.report(boundaries)               → string
boundary:stats()                     → {name, calls, hits}
boundary:reset()                     → nil
boundary.source                      -- generated source string
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

**Boundary** — A memoized transformation. verb (type-dispatched) or lower
(identity-cached).

**Cmd** — The flat command record. One product type with Kind singleton tag.

**Flatten-early** — Convert trees to flat Cmd arrays as soon as layout is resolved.

**Interning** — Same field values → same Lua table. Enabled by `unique`.

**Kind** — Singleton sum type used as a tag in the uniform Cmd product type.

**Lower** — Identity-cached function boundary. `pvm.lower(name, fn)`.

**Structural sharing** — Unchanged subtrees keep identity across edits via `pvm.with()`.

**Unique** — ASDL modifier enabling structural interning.

**Verb** — Type-dispatched cached method install. `pvm.verb(name, handlers, {cache=true})`.
