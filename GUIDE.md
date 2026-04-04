# The Complete Guide to Designing Good ASDL and GPS Systems

> **Note:** The current canonical runtime in this repository is the flat-command
> `gps` runtime in `init.lua`. This guide still contains extensive material
> from the older `emit/state/compose` runtime and should be treated as design
> background until it is fully rewritten.

## Bridging the Gap: From Low-Level IR to High-Level Domain Representations

*A practitioner's manual based on deep study of the mgps architecture.*

---

# Preface: What This Guide Is For

You have a domain. Maybe it is a UI toolkit, an audio engine, a game, a
language compiler, a spreadsheet evaluator, a document editor. You know
what the user sees and does. You know what the machine at the bottom
must do — issue draw calls, fill audio buffers, emit bytecode, write
pixels.

The gap between those two worlds is the hardest part of software
architecture. Most frameworks solve it with objects, callbacks,
managers, buses, virtual DOMs, signals, observers. All of those work.
None of them make the gap disappear.

GPS / mgps proposes a different path:

> Model your domain as typed structure (ASDL).
> Express the descent from user-level to machine-level as a series of
> **lowerings**: structural transformations that classify, simplify,
> and finally emit executable machines.
> Let the framework derive identity, caching, and reuse from the
> structure you already wrote.

This guide teaches you how to do that well. It is organized as a
bottom-up climb: we start with what a running machine looks like at the
very bottom, then work our way up through IR design, ASDL schema
design, lowering discipline, and finally full application architecture.

Throughout, we use concrete examples from rendering, audio, parsing,
and UI. The principles are domain-agnostic.

---

# Part I — The Bottom: What a Running Machine Looks Like

---

## Chapter 1: The Three Runtime Roles

Every running machine in GPS has exactly three parts:

```
gen   — the rule that executes
param — stable data the rule reads but never mutates
state — mutable data the rule owns and evolves
```

This is not a metaphor. It is the literal runtime shape:

```lua
result = gen(param, state, input)
```

`gen` is a function pointer. `param` is a table or cdata. `state` is a
table, cdata, or resource handle.

### Why Exactly Three?

Because those are the irreducible roles of any executing process:

- Something must say **what to do**. That is gen.
- Something must provide **stable context**. That is param.
- Something must hold **evolving data**. That is state.

You can collapse any two together (a closure hides param inside gen; an
object hides all three behind `self`). But collapsing them loses the
ability to reason about them independently.

GPS keeps them separate. That separation is the foundation of
everything: caching, hot-swap, composition, diagnostics.

### The Lua Iterator Tells You This Directly

Lua's generic `for` loop is literally `gen, param, state`:

```lua
for state, value in gen, param, initial_state do
    body(value)
end
```

The VM has dedicated bytecodes for this shape. LuaJIT traces it
natively. GPS machines are near the host's own loop primitive.

### Examples Across Domains

| Domain          | gen                    | param                     | state                    |
|-----------------|------------------------|---------------------------|--------------------------|
| Audio filter    | biquad equation        | coefficients (b0,b1,b2,a1,a2) | delay history (x1,x2,y1,y2) |
| Rect painter    | fill_rect routine      | {x,y,w,h,color}          | (none)                   |
| Text painter    | draw_text routine      | {x,y,text,font,color}    | TextBlob resource        |
| Hit tester      | point-in-rect check    | {x,y,w,h,tag}            | (none)                   |
| Lexer           | lex_next               | {input_buf, len, source}  | byte position            |
| Parser          | parse_production       | grammar tables + lexer    | parse cursor + stack     |
| Spreadsheet cell| formula evaluation     | cell references + constants | cached value            |

The bottom line: **if you cannot name gen, param, and state for your
machine, you do not yet understand your machine.**

---

## Chapter 2: The Terminal Contract

The absolute bottom of any GPS pipeline is a **terminal**: a leaf
lowering that produces a running machine. A terminal emits exactly
three things:

```lua
M.emit(gen, state_decl, param)
```

This triple is the terminal contract. Every domain, every backend,
every leaf compiler must eventually produce it.

### gen: The Rule

`gen` is a plain Lua function. It receives `(param, state, ...inputs)`
and returns results. It must be a stable function reference — ideally
defined once at module load time, never re-created per node.

Good:

```lua
local function rect_fill_gen(param, state, g)
    g:fill_rect(param.x, param.y, param.w, param.h, param.rgba8)
    return g
end
```

Bad:

```lua
function T.View.Rect:paint()
    -- Creating a NEW function every call. Defeats caching.
    return M.emit(
        function(param, state, g)
            g:fill_rect(param.x, param.y, param.w, param.h, param.rgba8)
            return g
        end,
        M.state.none(),
        { ... }
    )
end
```

### state_decl: The Structural State Declaration

`state_decl` is not a live allocation. It is a **description** of what
state the machine needs. The framework realizes it into an actual
allocator/releaser when needed.

This is the single most important design innovation in mgps over
original GPS. State is described structurally so the framework can:

- compare state shapes between old and new machines
- decide whether to preserve, reallocate, or release state
- compose child state into parent state products
- derive state identity automatically (no user keys)

### param: The Payload

`param` is everything else. All the stable data the gen reads. Position,
color, text content, coefficients, references to shared resources.

Param changes are **cheap**: the framework keeps the same compiled family
and just rebinds the new param. No state reallocation. No code
recompilation.

---

## Chapter 3: State Declarations In Depth

The state declaration algebra is how you tell the framework what your
machine's mutable footprint looks like. It is a small structural
language:

```lua
M.state.none()                         -- stateless
M.state.ffi("struct { double phase; }") -- FFI cdata
M.state.value(initial)                 -- deep-copied Lua value
M.state.f64(0)                         -- single double
M.state.table(name, opts)              -- Lua table with init/release
M.state.record(name, { k = decl })    -- named fields, each a decl
M.state.product(name, { d1, d2, ... }) -- ordered children
M.state.array(of_decl, n)             -- n copies of a declaration
M.state.resource(kind, spec, ops)      -- backend-owned resource
```

### The Shape Is the Identity

Every state declaration has a **shape string** computed by `state_shape_of()`.
Two declarations with the same shape string are considered identical.
This is how the framework knows whether to preserve or reallocate state.

For example:

```lua
M.state.resource("TextBlob", { cap = 16, font_id = 1 })
-- shape = 'resource(TextBlob|{["cap"]=16,["font_id"]=1})'

M.state.resource("TextBlob", { cap = 32, font_id = 1 })
-- shape = 'resource(TextBlob|{["cap"]=32,["font_id"]=1})'
```

Different cap → different shape → state gets reallocated.
Same cap, same font_id → same shape → state preserved, only param
rebound.

### Design Principle: Put State-Shaping Facts Into the Declaration

If changing a value requires new state allocation, that value belongs
in the state declaration, not in param.

- `text_capacity_bucket` → state declaration (controls TextBlob size)
- `text_content` → param (read by gen, does not affect allocation)
- `canvas_width` → state declaration (controls Canvas allocation)
- `clear_color` → param (used by gen but does not change Canvas size)
- `font_id` → state declaration (different font = different resource)
- `text_color` → param (does not affect the resource shape)

### Design Principle: State Declarations Compose

When you compose machines (see Chapter 8), their state declarations
compose automatically via `M.state.product()`. Each child retains its
own state slot. The framework tracks them positionally.

This is why you must be honest about state. If a child has state and
you pretend it does not, the composition becomes incoherent.

---

## Chapter 4: The Realization Pipeline

When you call `M.emit(gen, state_decl, param)`, nothing is allocated
yet. Here is what happens when the result reaches a slot:

```
emit(gen, state_decl, param)
    │
    ▼
ensure_bound()
    ├── compute code_shape from gen identity
    ├── compute state_shape from state_decl
    ├── realize_state(state_decl) → layout with alloc/release
    ├── create Family { gen, state_decl, state_layout, code_shape, state_shape }
    └── return Bound { family, param }
    │
    ▼
slot:update(bound)
    ├── same code_shape AND same state_shape?
    │       → keep state, replace param only (HOT PATH)
    ├── same code_shape, different state_shape?
    │       → retire old state, allocate new state
    └── different code_shape?
            → retire old state, allocate new state, new gen
```

This cascade is the heart of mgps runtime behavior. Design your
terminals so that the common case hits the hot path: same family, only
param changes.

---

# Part II — The Middle: Intermediate Representations

---

## Chapter 5: What Is an IR and Why Do You Need Layers?

An **Intermediate Representation** is any structured data format that
sits between two phases of your pipeline. In mgps terms, it is an
ASDL-defined type that is:

- **produced** by one lowering
- **consumed** by the next lowering

### The Layer Stack

A typical mgps application has at least two, often three or four layers:

```
User Domain ASDL     (what the user thinks in)
    │
    ▼  lowering: layout / resolve / schedule
View / Scene ASDL    (what the visual/audio/logical scene looks like)
    │
    ▼  lowering: backend compile
Backend IR ASDL      (what the terminal understands)
    │
    ▼  terminal: emit(gen, state_decl, param)
Running Machine      (gen + param + state executing)
```

Each layer is its own ASDL module. Each lowering is a structural
transformation from one ASDL to the next.

### Why Not Go Direct?

You *can* go from user domain directly to terminal. For trivial cases
that is fine. But for anything real, intermediate layers give you:

1. **Separation of concerns.** Layout logic does not know about GPU
   resources. Backend code does not know about user interaction models.

2. **Multiple backends from one source.** The same View ASDL can be
   compiled to a paint terminal AND a hit-test terminal AND an
   accessibility terminal.

3. **Incremental compilation.** Each layer's lowering is independently
   memoized. If only param changes at the bottom, nothing above
   recompiles.

4. **Testability.** You can inspect the IR at any layer without running
   the full pipeline.

### The UI Example Shows This Clearly

The mgps UI demo has exactly this stack:

```
UI ASDL (Column, Row, Padding, Rect, Text, ...)
    │
    ├──► View ASDL (Box, Label, Group, Clip, Transform, ...)
    │       │
    │       ├──► LovePaint ASDL (RectFill, Text, Clip, Transform, ...)
    │       │       │
    │       │       └──► emit(gen, state_decl, param)  → paint slot
    │       │
    │       └──► Hit ASDL (Rect, Text, Clip, Transform, ...)
    │               │
    │               └──► emit(gen, state_decl, param)  → hit slot
```

Each arrow is a lowering. Each box is a separate ASDL module.

---

## Chapter 6: Designing Your Lowest IR (The Backend IR)

The backend IR sits directly above the terminal. It is the last
structured representation before things become running machines.

### Principles for Backend IR Design

**Principle 1: Every node should map to exactly one `emit()` call or one
`compose()` call.**

If a backend IR node requires complex conditional logic to decide what
to emit, the node is too coarse. Split it.

Bad:

```
DrawCommand = (string type, any data) unique
```

Good:

```
Node = RectFill(number x, number y, number w, number h, number rgba8) unique
     | Text(number x, number y, number font_id, number rgba8, string text) unique
     | Clip(number x, number y, number w, number h, Node* body) unique
```

**Principle 2: Every sum type variant at this level IS a code-shaping
choice.**

Sum types in the backend IR directly determine which gen function runs.
`RectFill` → `rect_fill_gen`. `Text` → `text_gen`. No ambiguity.

**Principle 3: Every scalar at this level is either payload or
state-shaping. Nothing is code-shaping.**

All code-shaping choices have been resolved by the time you reach the
backend IR. What remains are values that either:

- go into param (payload)
- go into state_decl (state-shaping)

If you find a scalar that still determines which gen to use, you have
not lowered far enough. Push the choice into a sum type.

**Principle 4: Container nodes (Clip, Transform, Group) define
composition structure.**

These nodes do not emit a single gen. They compose child emissions. In
mgps this means they call `M.compose()` with a body function that
wraps child execution with container behavior (push/pop clip, push/pop
transform, etc.).

**Principle 5: The backend IR should be `unique` (structurally interned).**

This is critical for the caching story. If the same backend IR subtree
appears twice, structural interning gives it the same identity. The
memoized lowering boundary (`M.lower()`) can skip recompilation
entirely.

### Example: A Minimal Paint Backend IR

```lua
T:Define [[
    module LovePaint {
        Frame = (Pass* passes) unique

        Pass = Screen(Node* body) unique

        Node = Group(Node* children) unique
             | Clip(number x, number y, number w, number h, Node* body) unique
             | Transform(number tx, number ty, Node* body) unique
             | RectFill(number x, number y, number w, number h, number rgba8) unique
             | Text(number x, number y, number font_id, number rgba8, string text) unique
    }
]]
```

Notice:

- `Node` is a sum type. Each variant is a clear code-shaping choice.
- `RectFill` and `Text` are leaf nodes → single `emit()` calls.
- `Group`, `Clip`, `Transform` are container nodes → `compose()` calls.
- `Frame` and `Pass` are structural containers → auto-wired by the
  framework.
- Everything is `unique` → structural interning for free.

### Example: A Minimal Hit-Test Backend IR

```lua
T:Define [[
    module Hit {
        Root = (Node* nodes) unique

        Node = Group(Node* children) unique
             | Clip(number x, number y, number w, number h, Node* children) unique
             | Transform(number tx, number ty, Node* children) unique
             | Rect(number x, number y, number w, number h, string tag) unique
             | Text(number x, number y, number w, number h, string tag) unique
    }
]]
```

Almost the same structure as the paint IR! That is intentional. Both
backends need to traverse the same spatial tree. They differ only in
what the leaf nodes do (paint vs. probe).

This is a key insight: **multiple backend IRs can share the same spatial
topology while having completely different terminal behaviors.**

---

## Chapter 7: Writing Leaf Compilers for the Backend IR

Leaf compilers are the user-written code that turns backend IR nodes
into emitted machines. They are the most important code you write.

### The Simple Leaf: Stateless

Most backend IR leaves are stateless. They just pass data through.

```lua
local function rect_fill_gen(param, state, g)
    g:fill_rect(param.x, param.y, param.w, param.h, param.rgba8)
    return g
end

function T.LovePaint.RectFill:draw()
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

Classification:

- **code shape**: `RectFill` (the sum variant)
- **state shape**: none
- **payload**: all fields

This is the easiest case. Gen is fixed. State is empty. Everything
else is payload.

### The Stateful Leaf: Backend Resources

Text rendering is the classic stateful leaf. The backend needs a
retained resource (TextBlob, texture atlas entry, shaped glyph buffer)
whose allocation depends on capacity and font.

```lua
local function text_gen(param, state, g)
    g:draw_text(state, param.font_id, param.text, param.x, param.y, param.rgba8)
    return g
end

function T.LovePaint.Text:draw()
    return M.emit(
        text_gen,
        M.state.resource("TextBlob", {
            cap = next_power_of_two(#self.text),
            font_id = self.font_id,
        }, {
            alloc = alloc_text_blob,
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
```

Classification:

- **code shape**: `Text` (the sum variant)
- **state shape**: `resource(TextBlob|{cap=..., font_id=...})`
- **payload**: position, color, text content

Notice the design:

- `cap` is **state-shaping** because changing it means reallocating the
  TextBlob (different buffer size).
- `font_id` is **state-shaping** because changing it means a different
  font resource.
- `text` content is **payload** because the existing TextBlob can hold
  any text up to its capacity.
- The capacity is bucketed via `next_power_of_two` so small text
  changes don't cause reallocation.

This is the central classification exercise. Getting it right means
the framework can:

- Preserve the TextBlob when only text content changes
- Reallocate when the text grows past the current bucket
- Reuse the code family always (gen never changes for Text nodes)

### The Container: Compose with Behavior

Containers like `Clip` and `Transform` wrap child nodes with
push/pop behavior:

```lua
function T.LovePaint.Clip:draw()
    local children = {}
    for i = 1, #self.body do
        children[i] = self.body[i]:draw()
    end
    local out = M.compose(children, function(child_gens, param, state, g)
        g:push_clip(param.x, param.y, param.w, param.h)
        for i = 1, #child_gens do
            g = child_gens[i](param[i], state[i], g) or g
        end
        g:pop_clip()
        return g
    end)
    out.param.x = self.x
    out.param.y = self.y
    out.param.w = self.w
    out.param.h = self.h
    return out
end
```

The pattern:

1. Compile all children recursively
2. Compose them with a body function that wraps execution
3. Attach container-level payload (clip rect coordinates) to the
   composed param

The composed code_shape includes the container type and the shapes of
all children. If the tree structure changes (different number/types of
children), code_shape changes. If only coordinates change, it is a
payload-only update.

### The Hit-Test Leaf: Same Structure, Different Behavior

```lua
local function rect_probe_gen(param, state, query)
    if inside(query.x, query.y, param.x, param.y, param.w, param.h) then
        return { kind = "Rect", tag = param.tag, x = param.x, y = param.y, w = param.w, h = param.h }
    end
    return nil
end

function T.Hit.Rect:probe()
    return M.emit(
        rect_probe_gen,
        M.state.none(),
        { x = self.x, y = self.y, w = self.w, h = self.h, tag = self.tag }
    )
end
```

Exact same classification pattern. Different gen. Different runtime
behavior. Same structural discipline.

---

## Chapter 8: Composition — How Machines Combine

Composition is how parent machines are built from child machines.

### Sequential Composition (Default)

```lua
M.compose(children)
```

Children execute in order. Each receives its own param and state
slice. The result of one is passed as input to the next.

Internally:

```lua
gen = function(parent_param, parent_state, ...)
    local result = ...
    for i = 1, n do
        result = child_gens[i](parent_param[i], parent_state[i], result)
    end
    return result
end
state_decl = M.state.product("Compose", child_state_decls)
param = { child_params[1], child_params[2], ... }
```

### Behavioral Composition (With Body Function)

```lua
M.compose(children, function(child_gens, param, state, ...)
    -- custom orchestration
end)
```

The body function receives all child gens, the composed param, the
composed state, and the runtime input. It can call children in any
order, conditionally, repeatedly, or not at all.

This is how `Clip` wraps children with push/pop, how `Transform`
offsets coordinates, how hit-test probes children back-to-front.

### Composition Shapes

The composed code_shape is derived from:

1. The composition tag (sequential or body function identity)
2. All child code_shapes

If any child's code_shape changes (e.g., a variant swap deep in the
tree), the parent's code_shape changes too. This propagates correctly.

If only child params change, the parent's code_shape stays the same.
Only param is rebound. This is the structural caching payoff.

### Design Principle: Composition Is Honest

Do not try to hide state behind composition. If a child has state, the
composed product has state. If a child changes its state shape, the
composed product's state shape changes.

This honesty is what makes the slot's update logic correct. It can
compare old vs. new state_shape and decide precisely what to preserve
vs. reallocate.

---

# Part III — The Upper Layers: Domain ASDL Design

---

## Chapter 9: Your Domain ASDL Is Your Architecture

The single most important design decision in a GPS system is:
**what goes into the ASDL?**

The ASDL is not just a type definition. It is the architecture:

- **Sum types** define dispatch points (code-shaping choices)
- **Product types** define structural containers (composition points)
- **Containment** (child lists) defines the compilation tree shape
- **`unique`** enables structural interning (identity from structure)

### Design Principle: Model What the User Authors, Not What the Machine Needs

The top-level ASDL should reflect the user's mental model:

Good (models what the user builds):

```
Node = Column(number spacing, Node* children) unique
     | Row(number spacing, Node* children) unique
     | Rect(string tag, number w, number h, number rgba8) unique
     | Text(string tag, number font_id, number rgba8, string text) unique
```

Bad (models what the renderer needs):

```
DrawOp = FillRect(number x, number y, number w, number h, number rgba8)
       | DrawText(number x, number y, number font_id, number rgba8, string text, number cap)
```

The renderer's concerns (absolute positions, capacity buckets) are
**lowering artifacts**. They belong in a lower IR, not in the user's
schema.

### Design Principle: Sum Types Are Your Dispatch Architecture

Every sum type in your ASDL becomes a dispatch point. The framework
auto-wires `M.match()` for sum types, routing each variant to its own
compiler arm.

Think carefully about where you put sum types:

- A sum type **at the top level** means the user chooses between
  fundamentally different things (Column vs. Row vs. Rect vs. Text).
- A sum type **nested in a product** means a secondary classification
  within a larger thing (AlignH = Left | Center | Right inside an
  Align node).
- A sum type **in the backend IR** means a code-shaping terminal choice
  (RectFill vs. Text vs. Clip).

### Design Principle: Use `unique` Aggressively

Mark types as `unique` whenever the same field values should produce
the same object identity. This enables:

- **L1 cache hits in M.lower()**: same interned node → skip entire
  recompilation
- **Structural sharing**: unchanged subtrees share identity across
  frames
- **Correct equality**: no need for deep comparison

In practice, almost every type in a GPS ASDL should be `unique`.
The exception is types that are genuinely ephemeral or carry
non-structural payload.

### Design Principle: Lists Are Plain Tables

GPS/ASDL does not wrap lists in a special List type. `Node* children`
means "a plain Lua table of Node values." The interning machinery
handles list identity (same elements → same interned table).

This keeps the API honest: a list is a list. You iterate it normally.
You index it normally. No wrapper ceremony.

---

## Chapter 10: Designing the View Layer (The Middle IR)

The view layer sits between the user domain and the backend IR. It
represents "what the scene looks like" without backend-specific details.

### Why Have a View Layer?

1. **Layout resolution.** User nodes say `Column(spacing=10, children)`
   but the view layer says `Box(tag, x=100, y=200, w=120, h=30)`.
   Layout has been computed.

2. **Multiple projections.** The same view can be projected to paint,
   hit-test, accessibility, serialization. Each is a separate backend.

3. **Stable identity.** If the user changes something that does not
   affect the visible scene (e.g., reordering invisible layers), the
   view ASDL catches that: the interned view tree is unchanged, so
   all downstream compilation is skipped.

### Example: View ASDL

```lua
T:Define [[
    module View {
        Root = (VNode* nodes) unique

        VNode = Group(VNode* children) unique
              | Clip(number x, number y, number w, number h, VNode* body) unique
              | Transform(number tx, number ty, VNode* body) unique
              | Box(string tag, number x, number y, number w, number h, number rgba8) unique
              | Label(string tag, number x, number y, number w, number h,
                      number font_id, number rgba8, string text) unique
    }
]]
```

Notice:

- All positions are absolute (layout resolved)
- `tag` is present for hit-testing (carried through to hit backend)
- `font_id` is present (needed by both paint and hit-test sizing)
- Everything is `unique`

### The Lowering: User → View

This lowering resolves layout. In the mgps UI demo, it is the
`:measure()` / `:place(x, y)` protocol:

```lua
function U.UI.Column:place(x, y)
    local out = {}
    local cy = y
    for i = 1, #self.children do
        local child = self.children[i]
        local _, ch = child:measure()
        append_all(out, child:place(x, cy))
        cy = cy + ch + self.spacing
    end
    return out
end
```

This is a classic tree walk that produces view nodes from UI nodes.
The output is a flat or shallow list of positioned view nodes.

### The Projection: View → Backend IR

Each view node knows how to project itself to each backend:

```lua
function V.View.Box:paint_ast()
    return Paint.LovePaint.RectFill(self.x, self.y, self.w, self.h, self.rgba8)
end

function V.View.Box:hit_ast()
    return Hit.Hit.Rect(self.x, self.y, self.w, self.h, self.tag)
end
```

Same source (Box), two projections (paint and hit), two different
backend IR nodes. The structural interning ensures that if the view
tree is unchanged, both projections are skipped.

---

## Chapter 11: Designing the User ASDL (The Top Layer)

The user ASDL is the highest-level representation. It models what the
user *thinks* about, not what the machine *does*.

### Widget-Level Thinking

For a UI:

```
Node = Column(number spacing, Node* children) unique
     | Row(number spacing, Node* children) unique
     | Padding(number left, number top, number right, number bottom, Node child) unique
     | Align(number w, number h, AlignH halign, AlignV valign, Node child) unique
     | Rect(string tag, number w, number h, number rgba8) unique
     | Text(string tag, number font_id, number rgba8, string text) unique
```

For audio:

```
Device = Osc(number hz) unique
       | Filter(FilterMode mode, number freq, number q) unique
       | Gain(number db) unique
       | Chain(Device* devices) unique
       | Mix(Device* inputs) unique
```

For a language:

```
Expr = Literal(number value) unique
     | Var(string name) unique
     | BinOp(Op op, Expr left, Expr right) unique
     | Call(string func, Expr* args) unique
     | If(Expr cond, Expr then_branch, Expr else_branch) unique
```

### Design Principle: The User ASDL Has No Backend Knowledge

The user ASDL must not contain:

- Absolute positions (those are layout artifacts)
- Capacity buckets (those are backend allocation artifacts)
- Resource handles (those are runtime state)
- Draw commands (those are backend IR)

If you find yourself putting `cap`, `canvas_w`, `resource_id` in the
user ASDL, you are leaking backend concerns upward.

### Design Principle: The User ASDL Enables Structural Updates

Because the user ASDL is `unique`, you can update it with `M.with()`:

```lua
local new_track = M.with(old_track, { volume_db = -6 })
```

If `volume_db` is the only thing that changed, the new track has a
different identity from the old one (because the value is different),
but all other fields share structure.

This is how GPS applications handle events:

```lua
function apply(state, event)
    if event.kind == "SetVolume" then
        return M.with(state, {
            tracks = update_track(state.tracks, event.track_id, { volume_db = event.value })
        })
    end
    return state
end
```

Pure functional update. Structural sharing. No mutation. No observers.
No signals. No subscriptions.

---

## Chapter 12: The Event / State / View Triangle

Most interactive GPS applications follow this pattern:

```
         ┌──── Events ◄──── Input ────┐
         │                             │
         ▼                             │
    ┌─────────┐                   ┌────┴────┐
    │  apply  │                   │  slot   │
    │ (pure)  │                   │ .callback│
    └────┬────┘                   └────▲────┘
         │                             │
         ▼                             │
      Source ──── compile ──── Emitted ─┘
      (ASDL)     (lowering)   (machines)
```

1. **Source** is the application state, modeled as ASDL.
2. **Events** describe what happened (user input, timers, network).
3. **apply** is a pure function: `(Source, Event) → Source`.
4. **compile** is a lowering pipeline: `Source → ... → emit(gen, state_decl, param)`.
5. **slot** holds the running machine. `slot:update(compiled)` installs it.
6. **slot.callback(...)** runs the machine (paint, process audio, etc.).

This is the app loop. `M.app()` codifies it:

```lua
M.app {
    initial = function() return initial_source end,
    poll = function() return next_event_or_nil end,
    apply = function(source, event) return new_source end,
    compile = {
        paint = function(source) return source.root:view():paint_ast():draw() end,
        hit = function(source) return source.root:view():hit_ast():probe() end,
    },
}
```

### Why This Pattern Works

- Source is immutable (ASDL + `unique`). No hidden mutation.
- Apply is pure. Easy to test, replay, undo.
- Compile is memoized. Same source → same compiled result → skip work.
- Slot preserves state across updates. Same family → keep running state.
- The framework handles all of this. No manual wiring.

---

# Part IV — The Discipline: Classification at Every Boundary

---

## Chapter 13: The Central Classification Problem

This is the core intellectual discipline of GPS/mgps design.

At every boundary — every point where one representation is transformed
into another — every field must be classified:

```
┌──────────────────────┬───────────────────────────────────────────┐
│ Classification       │ What it means                             │
├──────────────────────┼───────────────────────────────────────────┤
│ Code-shaping         │ Changing it changes which gen runs        │
│ State-shaping        │ Changing it changes state allocation      │
│ Payload              │ Changing it only changes param data       │
│ Dead / consumed      │ It should not exist at this level anymore │
└──────────────────────┴───────────────────────────────────────────┘
```

### At the User ASDL Level

Everything is still "authored structure." Classification has not
happened yet. Sum type variants are inherently code-shaping. Scalars
are undifferentiated — they could become anything downstream.

```
Text(string tag, number font_id, number rgba8, string text) unique
     ^^^^          ^^^^^^^^        ^^^^^^^^       ^^^^^
     eventually    eventually      eventually     eventually
     dead at       state-shaping   payload        payload
     paint level   at paint level
```

### At the View Level

Layout has been resolved. Positions are now concrete. Tag may or may
not survive depending on the backend.

```
Label(string tag, number x, number y, number w, number h,
      number font_id, number rgba8, string text) unique
```

For the paint backend: tag is dead. x/y are payload. font_id is
state-shaping. rgba8 and text are payload.

For the hit backend: tag is payload (it is the hit identity). x/y/w/h
are payload. font_id is dead. rgba8 is dead. text is dead.

**The same view node classifies differently for different backends.**

### At the Backend IR Level

Classification is now final:

```
LovePaint.Text(number x, number y, number font_id, number rgba8, string text)
```

- Sum variant `Text` → code-shaping (determines gen)
- `font_id` → state-shaping (goes into resource spec)
- `#text` (capacity bucket) → state-shaping (goes into resource spec)
- `x, y, rgba8, text` → payload (goes into param)

### At the Terminal

The terminal crystallizes the classification into the emit triple:

```lua
M.emit(
    text_gen,                              -- code shape: Text
    M.state.resource("TextBlob", {         -- state shape
        cap = next_power_of_two(#self.text),
        font_id = self.font_id,
    }),
    {                                      -- payload
        x = self.x, y = self.y,
        font_id = self.font_id,
        rgba8 = self.rgba8,
        text = self.text,
    }
)
```

Notice: `font_id` appears in BOTH state_decl and param. That is
correct! The state declaration needs it to decide resource allocation.
The gen needs it to select the right font at draw time. Same data,
two roles, two appearances.

---

## Chapter 14: The Four Classification Errors

Most bugs in GPS system design come from misclassifying fields.

### Error 1: Treating State-Shaping as Payload

**Symptom**: The machine runs with stale/wrong state. Text renders in
a too-small buffer. Canvas has the wrong resolution.

**Example**: Putting `text_length` only in param and using a fixed-size
TextBlob. When text grows, the blob is too small.

**Fix**: Move the state-shaping fact into the state declaration:

```lua
M.state.resource("TextBlob", { cap = next_power_of_two(#text) })
```

### Error 2: Treating Payload as State-Shaping

**Symptom**: State is reallocated on every frame even though nothing
structurally changed. Performance tanks.

**Example**: Putting the actual text content in the state declaration.
Every character typed causes a new TextBlob allocation.

**Fix**: Only put allocation-relevant facts in the state declaration.
Text *content* is payload. Text *capacity bucket* is state-shaping.

### Error 3: Treating Code-Shaping as Payload

**Symptom**: The wrong gen runs. A lowpass filter is asked to behave
like a highpass by setting a param field.

**Example**: `filter_type = "lowpass"` in param, with a single gen
that switches on it at runtime.

**Fix**: Model filter type as a sum type. Each variant gets its own gen.

```
Filter = LowPass(number freq, number q) unique
       | HighPass(number freq, number q) unique
```

### Error 4: Keeping Dead Fields

**Symptom**: Wasted memory, confusing code, false cache misses.

**Example**: The paint backend carries `tag` through to the terminal
even though it never uses it. Different tags cause different interned
nodes, defeating structural sharing.

**Fix**: Strip dead fields at the lowering boundary. The paint
projection of a Box does not include `tag`:

```lua
function V.View.Box:paint_ast()
    return Paint.LovePaint.RectFill(self.x, self.y, self.w, self.h, self.rgba8)
    -- no self.tag
end
```

---

## Chapter 15: How to Classify Any Field — A Decision Procedure

For any field `f` at any boundary, apply this checklist:

```
1. Does `f` determine which gen function runs?
   YES → code-shaping. Model as sum type or conditional gen selection.

2. Does `f` determine the size, shape, or kind of allocated state?
   YES → state-shaping. Include in state_decl.

3. Does `f` survive to this boundary at all?
   NO  → dead. Strip it in the lowering.

4. Is `f` read by the gen at runtime?
   YES → payload. Include in param.
   NO  → dead. Strip it.
```

Run this for every field at every boundary. The first YES wins.

### Worked Example: Audio Filter Node

Source ASDL:

```
Filter(FilterMode mode, number freq, number q, number gain_db)
```

At the `compile` boundary:

| Field     | Classification    | Reason                                  |
|-----------|-------------------|-----------------------------------------|
| `mode`    | code-shaping      | LowPass vs HighPass → different gen      |
| `freq`    | payload           | changes coefficient, not state layout    |
| `q`       | payload           | same                                     |
| `gain_db` | payload           | same                                     |

Terminal:

```lua
-- For LowPass variant:
M.emit(
    lowpass_gen,         -- code-shaping choice resolved
    M.state.ffi("struct { double x1, x2, y1, y2; }"),  -- fixed state layout
    compute_coefficients(freq, q, gain_db, sample_rate)  -- payload
)
```

### Worked Example: Canvas Render Target

Source ASDL:

```
Canvas(number w, number h, number msaa, number clear_r, number clear_g, number clear_b)
```

At the `compile_render_pass` boundary:

| Field     | Classification    | Reason                                  |
|-----------|-------------------|-----------------------------------------|
| `w`       | state-shaping     | canvas allocation depends on dimensions  |
| `h`       | state-shaping     | same                                     |
| `msaa`    | state-shaping     | different MSAA = different framebuffer   |
| `clear_r` | payload           | clear color does not change allocation   |
| `clear_g` | payload           | same                                     |
| `clear_b` | payload           | same                                     |

Terminal:

```lua
M.emit(
    render_pass_gen,
    M.state.resource("Canvas", { w = self.w, h = self.h, msaa = self.msaa }),
    { clear_r = self.clear_r, clear_g = self.clear_g, clear_b = self.clear_b }
)
```

---

# Part V — Structural Mechanics

---

## Chapter 16: Structural Interning and Why It Matters

Structural interning means: **same fields → same object**.

When you define an ASDL type as `unique`, the constructor returns the
same Lua table for the same argument values:

```lua
local a = T.View.Box("btn", 10, 20, 100, 30, 0xff0000ff)
local b = T.View.Box("btn", 10, 20, 100, 30, 0xff0000ff)
assert(a == b)  -- true! same object
```

This is implemented via a trie (prefix tree) keyed by field values.
The first call creates the object; subsequent calls with the same
values return the existing one.

### Why This Is Powerful

**L1 cache in M.lower()**: The lowering boundary uses a weak-keyed
table (`node_cache[input]`). If the same interned node is passed again,
the entire lowering is skipped — including all descendant lowerings.

**Structural sharing**: When you update one field with `M.with()`, all
other fields keep their existing interned identity. Unchanged subtrees
are literally the same objects.

**Free equality**: `a == b` (reference equality) means structural
equality. No deep comparison needed.

**Automatic deduplication**: If two parts of your tree produce the same
subtree, they get the same object. The lowering compiles it once.

### The Interning Trie

For a type `Box(string tag, number x, number y, number w, number h, number rgba8)`:

```
cache[tag][x][y][w][h][rgba8] → existing_box_or_nil
```

The trie is walked one field at a time. If the full path exists, the
cached object is returned. Otherwise a new object is created and stored.

For list fields (e.g., `Node* children`), the list is first interned
by its elements, producing a canonical list object. That canonical
list is then used as a single key in the parent's trie.

### Design Principle: Interning Must Be Total

If you mark a type as `unique`, ALL instances must go through the
constructor. Never create an object by hand (`setmetatable({...}, T)`)
because it bypasses interning and breaks identity.

### Design Principle: Interned Objects Are Immutable

Never mutate fields of an interned object. Use `M.with()` to create a
new version. Mutation would corrupt the interning trie (the old keys
would point to an object with different values).

---

## Chapter 17: Memoized Boundaries (M.lower)

`M.lower(name, fn)` wraps a lowering function with structural caching:

```lua
local compile_paint = M.lower("ui_to_paint", function(root)
    local view = root:view()
    return view:paint_ast():draw()
end)
```

### Three Cache Levels

**L1: Node identity.** If the same interned object is passed again, the
entire result is returned from cache. This is the fastest path.

**L2: Code-shape cache.** If the emitted code_shape has been seen before,
the cached gen is reused. Code families are shared across different
inputs that produce the same code structure.

**L3: State-shape cache.** If the emitted state_shape has been seen
before, the cached state layout is reused. State families are shared
across different inputs that produce the same state structure.

### What Gets Cached vs. Recomputed

| Change                | L1 hit? | L2 hit? | L3 hit? | What happens            |
|-----------------------|---------|---------|---------|-------------------------|
| Same interned node    | ✓       | —       | —       | Return cached result    |
| Different node, same code+state | ✗ | ✓ | ✓ | Reuse family, new param |
| Different code shape  | ✗       | ✗       | —       | New gen, new family     |
| Different state shape | ✗       | ?       | ✗       | New state layout        |

### Design Principle: Boundaries Should Be Narrow

Put `M.lower()` at the narrowest useful point — where structural
identity is most likely to hit. In the UI demo, the outermost boundary
wraps the entire pipeline from UI root to emitted machines:

```lua
local compile_paint = M.lower("ui_to_paint", function(root)
    local view = root:view()
    return view:paint_ast():draw()
end)
```

If the root is unchanged (same interned object), the entire pipeline
is skipped. If the root changed but most children are the same,
inner lowerings (on the children) hit their own L1 caches.

### Design Principle: The Framework Wires Sum-Type Boundaries Automatically

When you call `M.context("paint")`, the framework creates a
`M.lower()` boundary around each sum type's dispatch for the given
verb. You do not need to add them manually for standard dispatch.

You DO need to add explicit `M.lower()` boundaries for cross-module
lowerings (e.g., UI → View → Backend) or for custom compilation
pipelines.

---

## Chapter 18: Slots — Runtime Installation

A slot is the runtime holder for a compiled machine:

```lua
local slot = M.slot()
slot:update(compiled_result)
slot.callback(runtime_input)
```

### The Update Decision Tree

When `slot:update(new_compiled)` is called, the slot compares the new
result's family identity against the currently installed machine:

```
Same code_shape AND same state_shape?
    → Keep existing state. Replace param only. (Fastest.)

Same code_shape, different state_shape?
    → Retire old state. Allocate new state. Keep gen.

Different code_shape?
    → Retire old state. Allocate new state. Install new gen.
```

"Retire" means the old state is queued for release. `slot:collect()`
actually releases it (calls the state layout's `release` function).
This two-phase approach allows graceful cleanup.

### Design Principle: One Slot Per Output

Each independent output (screen, audio stream, hit-test query engine)
gets its own slot. A slot does not multiplex multiple machines.

### Design Principle: Slots Are Long-Lived

Create slots at initialization. Update them on every state change.
Close them at shutdown. Do not create/destroy slots per frame.

---

## Chapter 19: Auto-Wiring — How the Framework Reads Your Schema

`M.context(verb)` + `:Define(schema)` does the following:

1. **Parse the ASDL schema** into type definitions.
2. **Build constructors** for each type (with interning if `unique`).
3. **Detect sum types** and create auto-dispatch lowering boundaries.
4. **Detect container types** (types with `Child* field` lists) and
   create auto-composition verb methods.

### Sum Type Wiring

For each sum type `Node = Rect | Text | Clip`, the framework creates:

```lua
-- Pseudocode of what happens internally:
Node._mgps_paint = M.lower("Node:paint", function(node, ...)
    return stamp_code_shape(node:paint(...), node.kind)
end)
```

This means calling `some_node:paint()` on a sum parent automatically
dispatches to the right variant's `:paint()` method, through a cached
lowering boundary that stamps the variant name as the code_shape.

### Container Wiring

For a type like `Frame = (Node* nodes) unique`, the framework generates
a default `:paint()` method that:

1. Iterates `self.nodes`
2. Dispatches each child through the sum type's lowering boundary
3. Composes all child results with `M.compose()`

You do not write this boilerplate. The schema implies it.

### What You DO Write

You write:

- **Leaf variant methods**: `function T.View.Rect:paint() ... end`
- **Custom container methods** (if the default compose is wrong)
- **Cross-module lowerings**: explicit `M.lower()` calls

You do NOT write:

- Sum type dispatchers
- Default compose over child lists
- Cache key logic
- Family management

---

# Part VI — Bridging the Gap: Layer-by-Layer Design Methodology

---

This is the heart of the guide. If you read only one part, read this.
The central challenge of any real GPS system is not writing leaf
compilers or declaring state. It is **designing the layers between
your top-level user representation and your bottom-level terminal**.

Each layer is an ASDL module. Each transition is a lowering. The art
is knowing how many layers you need, what each layer should contain,
and how fields transform as they descend.

---

## Chapter 20: The Layer Design Method — A Step-by-Step Process

### Step 1: Start at Both Ends

Do NOT design top-down or bottom-up exclusively. Start at both ends
simultaneously:

**Bottom**: What does your runtime need? What are the `gen` functions?
What state do they allocate? What param do they read?

**Top**: What does the user think about? What are the natural concepts
in your domain? What events change them?

Write rough ASDL for both:

```lua
-- TOP: what the user builds
module UI {
    Node = Column(number spacing, Node* children) unique
         | Rect(string tag, number w, number h, number rgba8) unique
         | Text(string tag, number font_id, number rgba8, string text) unique
}

-- BOTTOM: what the paint backend needs
module Paint {
    Node = RectFill(number x, number y, number w, number h, number rgba8) unique
         | DrawText(number x, number y, number font_id, number rgba8, string text) unique
}
```

### Step 2: Identify the Semantic Gaps

Now list everything that is different between top and bottom:

| Aspect           | Top (UI)                    | Bottom (Paint)                |
|------------------|-----------------------------| ------------------------------|
| Position         | implicit (layout resolves)  | explicit (x, y)              |
| Size             | declared (w, h)             | resolved (may change)        |
| Tag              | present (for hit-testing)   | absent (paint doesn't need)  |
| Spacing          | present (Column logic)      | consumed (layout artifact)   |
| Capacity bucket  | absent                      | needed (TextBlob allocation) |
| Clip/Transform   | absent at leaf level        | may wrap leaves              |

Each row in this table is a gap that some lowering must bridge.

### Step 3: Group the Gaps into Layers

Each cluster of related gaps becomes a separate layer:

**Gap cluster 1: Layout resolution** — Turn implicit positions into
explicit coordinates. Consume spacing, padding, alignment.
→ This becomes the **View layer**.

**Gap cluster 2: Backend projection** — Strip dead fields (tag for
paint), add backend-specific facts (capacity bucket), choose backend
types (RectFill vs DrawText).
→ This becomes the **Backend IR layer**.

**Gap cluster 3: Terminal emission** — Turn backend IR nodes into
`emit(gen, state_decl, param)` triples.
→ This is the **terminal** (leaf compilers on the backend IR).

### Step 4: Design Each Layer's ASDL

Now design the intermediate ASDL. The View layer carries everything
that any backend might need, with positions resolved:

```lua
module View {
    Root = (VNode* nodes) unique
    VNode = Box(string tag, number x, number y, number w, number h, number rgba8) unique
          | Label(string tag, number x, number y, number w, number h,
                  number font_id, number rgba8, string text) unique
          | Clip(number x, number y, number w, number h, VNode* body) unique
          | Transform(number tx, number ty, VNode* body) unique
          | Group(VNode* children) unique
}
```

Notice: View has BOTH `tag` (needed by hit backend) AND `font_id`
(needed by paint backend). The View layer is the **union** of what all
downstream backends need.

### Step 5: Design Each Lowering's Classification

For every field at every boundary, apply the classification:

**UI → View (layout lowering)**:

| Field     | In UI            | In View           | Classification      |
|-----------|------------------|--------------------|---------------------|
| spacing   | present          | absent             | consumed by layout  |
| tag       | present          | present            | passed through      |
| w, h      | declared          | resolved (same or changed) | transformed  |
| x, y      | absent           | computed           | produced by layout  |
| font_id   | present          | present            | passed through      |
| rgba8     | present          | present            | passed through      |
| text      | present          | present            | passed through      |

**View → Paint IR (paint projection)**:

| Field     | In View          | In Paint IR        | Classification      |
|-----------|------------------|--------------------|---------------------|
| tag       | present          | absent             | dead for paint      |
| x, y      | present          | present            | passed through      |
| w, h      | present          | present            | passed through      |
| font_id   | present          | present            | passed through      |
| rgba8     | present          | present            | passed through      |
| text      | present          | present            | passed through      |

**View → Hit IR (hit projection)**:

| Field     | In View          | In Hit IR          | Classification      |
|-----------|------------------|--------------------|---------------------|
| tag       | present          | present            | payload (hit identity)|
| x, y      | present          | present            | payload             |
| w, h      | present          | present            | payload             |
| font_id   | present          | absent             | dead for hit        |
| rgba8     | present          | absent             | dead for hit        |
| text      | present          | absent             | dead for hit        |

**Paint IR → Terminal (paint emission)**:

| Field     | In Paint IR      | Emit classification | Destination         |
|-----------|------------------|---------------------|---------------------|
| variant   | RectFill/DrawText| code-shaping        | determines gen      |
| font_id   | present          | state-shaping       | state_decl spec     |
| text len  | implicit          | state-shaping       | bucketed cap in spec|
| x, y, w, h| present         | payload             | param               |
| rgba8     | present          | payload             | param               |
| text      | present          | payload             | param               |

This systematic analysis is the core design activity. Do it on paper
before writing code.

### Step 6: Write the Lowerings

Now implementation follows naturally from the analysis:

```lua
-- UI → View (layout)
function U.UI.Column:place(x, y)
    local out, cy = {}, y
    for i = 1, #self.children do
        local _, ch = self.children[i]:measure()
        append_all(out, self.children[i]:place(x, cy))
        cy = cy + ch + self.spacing  -- spacing consumed here
    end
    return out
end

-- View → Paint IR (projection)
function V.View.Box:paint_ast()
    -- tag stripped (dead for paint)
    return Paint.Node.RectFill(self.x, self.y, self.w, self.h, self.rgba8)
end

-- View → Hit IR (projection)
function V.View.Box:hit_ast()
    -- rgba8 stripped (dead for hit)
    return Hit.Node.Rect(self.x, self.y, self.w, self.h, self.tag)
end

-- Paint IR → Terminal
function Paint.Node.RectFill:draw()
    return M.emit(rect_fill_gen, M.state.none(), {
        x = self.x, y = self.y, w = self.w, h = self.h, rgba8 = self.rgba8
    })
end
```

Each lowering does exactly what the analysis predicted. No surprises.
No ad hoc decisions. The design flows from the classification tables.

---

## Chapter 21: Recognizing When You Need Another Layer

Signs that you need an intermediate layer:

**Sign 1: A lowering does two unrelated things.** If your lowering both
resolves layout AND projects to a backend, split it. Layout is one
layer. Projection is another.

**Sign 2: Multiple backends need different projections of the same data.**
The shared data should live in its own layer (the View), and each
backend gets its own projection.

**Sign 3: A field is dead for one consumer but alive for another.**
That field belongs in a shared intermediate layer, where each consumer's
projection can keep or strip it.

**Sign 4: Cache hit rates are poor.** If small changes cause large
recompilations, you probably need a narrower intermediate layer that
isolates the changing part.

**Sign 5: Your leaf compilers are doing complex logic.** If a leaf
compiler has 50 lines of conditional logic, the backend IR is too
coarse. Add another layer that resolves the complexity, so the leaf
compiler becomes trivial.

### Counter-Sign: You Do NOT Need Another Layer

If the lowering is a simple 1:1 mapping with no gaps, no dead fields,
and no classification changes, you may not need a separate IR. A
direct method call suffices.

Over-layering is a real anti-pattern. Each layer adds schema code,
constructor overhead, and conceptual weight. Add layers for genuine
semantic gaps, not for architectural purity.

---

## Chapter 22: The Field Lifecycle — Tracing a Field from Top to Bottom

Let us trace the lifecycle of a single field — `text` in a label
widget — through all layers. This illustrates the bridge in
concrete detail.

### Layer 0: User Event

```
SetText(string tag, string new_text)
```

`new_text` enters the system.

### Layer 1: User ASDL (Source)

```lua
local label = U.UI.Text("greeting", 1, 0xffffffff, "hello world")
--                                                  ^^^^^^^^^^^^^
-- text = "hello world"
```

Classification: **undifferentiated**. The ASDL does not know yet what
"hello world" means to any backend.

### Layer 2: View ASDL (After Layout)

```lua
local vlabel = V.View.Label("greeting", 100, 50, 120, 20, 1, 0xffffffff, "hello world")
--                                                                        ^^^^^^^^^^^^^
-- text = "hello world" (passed through, now with resolved position)
```

Classification: still **undifferentiated** at the view level. The view
is backend-agnostic.

### Layer 3a: Paint Backend IR

```lua
local ptext = Paint.Node.Text(100, 50, 1, 0xffffffff, "hello world")
--                                                     ^^^^^^^^^^^^^
-- text = "hello world"
```

Classification: **splits into two roles**:

- `#text` → contributes to cap = `next_power_of_two(11)` = 16 → **state-shaping**
- `text` content → **payload** (read by gen to draw the actual glyphs)

### Layer 3b: Hit Backend IR

```lua
local htext = Hit.Node.Text(100, 50, 120, 20, "greeting")
--                                              ^^^^^^^^
-- tag = "greeting" (the text CONTENT is dead here)
```

Classification: `text` is **dead** for the hit backend. It is not
present in the hit IR at all. Only `tag` survives.

### Layer 4: Terminal Emission (Paint)

```lua
M.emit(
    text_gen,
    M.state.resource("TextBlob", { cap = 16, font_id = 1 }),
    { x = 100, y = 50, font_id = 1, rgba8 = 0xffffffff, text = "hello world" }
)
```

`text` appears in param. `#text`'s bucketed form appears in state_decl.
The field has been fully classified.

### What Happens on Update

User types "hello world!" (12 chars):

- cap = `next_power_of_two(12)` = 16 → **same** bucket
- state_shape unchanged → state preserved
- param changes → gen gets new text
- **Result**: payload-only update. TextBlob reused. Instant.

User pastes a 20-char string:

- cap = `next_power_of_two(20)` = 32 → **different** bucket
- state_shape changed → state reallocated (new, larger TextBlob)
- gen unchanged (still `text_gen`)
- **Result**: state-shaping update. Slightly more expensive.

This is the classification system working exactly as designed.

---

## Chapter 23: The Container Lifecycle — Tracing Structure from Top to Bottom

Now let us trace how a **container** (like Column or Clip) transforms
across layers.

### User ASDL

```lua
local col = U.UI.Column(10, {
    U.UI.Rect("header", 200, 40, 0xff3366ff),
    U.UI.Text("title", 1, 0xffffffff, "mgps"),
})
```

At this level, Column is a **layout concept**. It knows spacing but
not positions.

### View ASDL (After Layout)

```lua
-- Column is GONE. Its layout effect has been applied.
-- What remains is positioned leaves:
{
    V.View.Box("header", 0, 0, 200, 40, 0xff3366ff),
    V.View.Label("title", 0, 50, 40, 20, 1, 0xffffffff, "mgps"),
    --                       ^ y=50 because: h=40 + spacing=10
}
```

The Column node is **consumed** by layout. It does not exist in the View
layer. Its semantic contribution (vertical stacking with spacing) is
now baked into the positions of its children.

### Contrast: Clip Survives

```lua
-- User ASDL
local clipped = U.UI.Clip(200, 100, U.UI.Text(...))

-- View ASDL — Clip survives as a structural container
V.View.Clip(x, y, 200, 100, { V.View.Label(...) })

-- Paint Backend IR — Clip still survives
Paint.Node.Clip(x, y, 200, 100, { Paint.Node.Text(...) })

-- Terminal — Clip becomes a compose with push/pop behavior
M.compose(children, function(child_gens, param, state, g)
    g:push_clip(param.x, param.y, param.w, param.h)
    for i = 1, #child_gens do
        g = child_gens[i](param[i], state[i], g) or g
    end
    g:pop_clip()
    return g
end)
```

Clip is a **structural container** — it must exist at every layer
because its runtime effect (scissor rect) cannot be baked into leaf
positions alone.

### The Rule

> If a container's effect can be fully resolved by modifying its
> children's properties, the container should be **consumed** at the
> resolution layer and not appear downstream.
>
> If a container's effect requires runtime behavior (push/pop state),
> the container must **survive** to the terminal as a compose node.

Column (spacing resolved into positions) → consumed.
Clip (requires scissor state) → survives.
Transform (requires matrix push/pop) → survives.
Padding (resolved into offsets) → consumed.
Align (resolved into offsets) → consumed.

---

## Chapter 24: Designing Sum Types Across Layers

Sum types transform as they descend through layers. Understanding how
is crucial for good ASDL design.

### Layer Behavior of Sum Types

**User ASDL**: Sum types represent user-facing choices.

```
Node = Column(...) | Row(...) | Rect(...) | Text(...)
```

**View ASDL**: Some user variants collapse. Column and Row both produce
positioned children — the View does not distinguish them.

```
VNode = Box(...) | Label(...) | Clip(...) | Transform(...) | Group(...)
```

Column → produces flat list of positioned VNodes (no Column in View)
Row → produces flat list of positioned VNodes (no Row in View)
Rect → produces Box
Text → produces Label

**Backend IR**: View variants may split or merge for backend needs.

```
-- Paint backend
Node = RectFill(...) | Text(...) | Clip(...) | Transform(...) | Group(...)

-- Hit backend
Node = Rect(...) | Text(...) | Clip(...) | Transform(...) | Group(...)
```

Paint and Hit have nearly identical variant structures because they
traverse the same spatial tree. They differ only in field content and
gen behavior.

### The Variant Evolution Rules

1. **Variants can merge** going down: Column and Row both produce
   generic positioned children. The distinction is consumed by layout.

2. **Variants can split** going down: A user `Image` node might become
   `TexturedRect` or `AnimatedSprite` in the backend IR depending on
   whether it is animated.

3. **Variants can disappear** going down: A `Spacer` node produces no
   visual output. It affects layout but generates no backend IR node.

4. **New variants can appear** going down: A `Shadow` effect might be
   absent in the user ASDL but synthesized as a backend IR node by
   the view projection.

### Design Principle: Sum Types at Each Layer Should Be Natural for That Layer

Do not force upper sum types onto lower layers or vice versa. Each
layer's sum types should reflect the **genuine code-shaping choices at
that level**.

At the user level: Column vs Row is code-shaping (different layout
algorithm).

At the view level: Column vs Row is not a meaningful distinction
(layout is done).

At the backend level: RectFill vs Text is code-shaping (different gen
functions).

---

## Chapter 25: Pattern — Multiple Backends from One Source

**Problem**: You need both painting and hit-testing from the same UI
tree.

**Solution**: Define two backend IRs with the same spatial structure.
Each view node has a projection method for each backend.

```lua
function V.View.Box:paint_ast()
    return Paint.LovePaint.RectFill(self.x, self.y, self.w, self.h, self.rgba8)
end

function V.View.Box:hit_ast()
    return Hit.Hit.Rect(self.x, self.y, self.w, self.h, self.tag)
end
```

Two compile pipelines:

```lua
local compile_paint = M.lower("paint", function(root) ... end)
local compile_hit = M.lower("hit", function(root) ... end)
```

Two slots:

```lua
paint_slot:update(compile_paint(source.root))
hit_slot:update(compile_hit(source.root))
```

Same source, two machines, independent caching and state.

---

## Chapter 26: Pattern — Capacity Bucketing

**Problem**: Text rendering needs a buffer, but text length varies
continuously. You do not want to reallocate on every keystroke.

**Solution**: Bucket the capacity to the next power of two.

```lua
local cap = next_power_of_two(#self.text)
M.state.resource("TextBlob", { cap = cap, font_id = self.font_id })
```

This means:

- Text of length 1–16 → cap=16 → same state shape
- Text of length 17–32 → cap=32 → different state shape (realloc)
- Text of length 33–64 → cap=64 → different state shape (realloc)

Reallocation happens logarithmically, not linearly. Most updates are
payload-only.

### General Principle

Whenever a continuously varying value is state-shaping, bucket it.
Choose a bucketing function that balances waste vs. reallocation
frequency:

- Power of two: simple, good for buffers
- Fixed tiers: `{ 64, 256, 1024, 4096 }` for resource pools
- Round up to nearest N: `math.ceil(x / 64) * 64` for aligned buffers

---

## Chapter 27: Pattern — Structural Updates with M.with

**Problem**: The user changes one field of a deeply nested ASDL node.
How do you propagate this without rebuilding everything?

**Solution**: `M.with()` creates a new interned node with the changed
field, reusing all other fields:

```lua
local new_node = M.with(old_node, { rgba8 = 0xff0000ff })
```

Because the type is `unique`, this goes through the constructor. If
the result happens to match an existing interned node, you get back
that existing node — further collapsing redundant updates.

### Propagation

In a functional update pattern:

```lua
local new_root = M.with(root, {
    nodes = map(root.nodes, function(n)
        if n == target then return M.with(n, { rgba8 = new_color }) end
        return n  -- unchanged nodes keep identity
    end)
})
```

Unchanged children are literally the same objects. The lowering
boundary hits L1 cache for them. Only the changed path recompiles.

---

## Chapter 28: Pattern — Container Nodes with Push/Pop Behavior

**Problem**: Clip and Transform need to wrap child rendering with
push/pop calls to the graphics backend.

**Solution**: Use `M.compose()` with a body function:

```lua
function T.LovePaint.Clip:draw()
    local children = {}
    for i = 1, #self.body do
        children[i] = self.body[i]:draw()
    end
    return M.compose(children, function(child_gens, param, state, g)
        g:push_clip(param.x, param.y, param.w, param.h)
        for i = 1, #child_gens do
            g = child_gens[i](param[i], state[i], g) or g
        end
        g:pop_clip()
        return g
    end)
end
```

The body function is the container's runtime behavior. It receives all
child gens, the composed param (array of child params plus container
params), and the composed state (array of child states).

### Code Shape

The composed code_shape includes the body function identity and all
child shapes. If a child changes type (say, RectFill becomes Text),
the parent's code_shape changes. If only child params change, code_shape
is stable.

---

## Chapter 29: Pattern — Hit Testing as a Separate Pipeline

**Problem**: You need spatial queries (mouse hit testing) but do not
want to pollute the paint pipeline.

**Solution**: Hit testing is a separate backend with its own IR, its
own leaf compilers, its own slot.

Hit-test gens return hit records instead of drawing:

```lua
local function rect_probe_gen(param, state, query)
    if inside(query.x, query.y, param.x, param.y, param.w, param.h) then
        return { kind = "Rect", tag = param.tag, ... }
    end
    return nil
end
```

Hit-test containers probe children back-to-front (top element wins):

```lua
function(child_gens, param, state, query)
    for i = #child_gens, 1, -1 do
        local hit = child_gens[i](param[i], state[i], query)
        if hit then return hit end
    end
    return nil
end
```

Hit-test Clip validates the query is inside the clip rect before
probing children:

```lua
function(child_gens, param, state, query)
    if not inside(query.x, query.y, param.x, param.y, param.w, param.h) then
        return nil
    end
    -- probe children...
end
```

Hit-test Transform adjusts query coordinates:

```lua
function(child_gens, param, state, query)
    local local_query = { x = query.x - param.tx, y = query.y - param.ty }
    -- probe children with local_query...
end
```

This is a complete, independent pipeline. It shares the view ASDL
with paint but has completely different runtime behavior.

---

## Chapter 30: Pattern — The Module Pattern for Leaf Compilers

**Problem**: Leaf compiler methods clutter the main file.

**Solution**: Put them in separate modules. The `:use()` method
installs them:

```lua
-- paint_methods.lua
return function(T, M)
    function T.View.Rect:paint(env)
        return M.emit(rect_fill_gen, M.state.none(), { ... })
    end
    function T.View.Text:paint(env)
        return M.emit(text_gen, M.state.resource(...), { ... })
    end
end

-- main.lua
local T = M.context("paint")
    :Define(schema)
    :use(require("paint_methods"))
```

This keeps schema definition, leaf compilers, and application logic in
separate files. Each module receives the context `T` and the framework
`M`, so it can access both types and framework primitives.

---

## Chapter 31: Pattern — Diagnostics and Performance Tuning

`M.report()` gives you visibility into the caching behavior:

```lua
local report = M.report({ compile_paint, compile_hit })
print(report)
```

Output:

```
ui_to_paint    calls=850 node_hits=847 code_hits=100 code_misses=3 code_reuse=97% state_hits=95 state_misses=5 state_reuse=95%
ui_to_hit      calls=850 node_hits=849 code_hits=100 code_misses=1 code_reuse=99% state_hits=100 state_misses=0 state_reuse=100%
```

### What to Look For

**High node_hits**: Good. Most updates are hitting L1 cache (same
interned node). Means your structural sharing is working.

**Low node_hits**: Bad. Nodes are being recreated unnecessarily. Check
that types are `unique` and that you are reusing subtrees.

**High code_reuse**: Good. The gen family is stable across updates.
Means your code-shaping classification is correct.

**Low code_reuse**: Could be fine (if the tree structure genuinely
changes) or bad (if code_shape is being polluted by payload data).

**High state_reuse**: Good. State allocations are being preserved.
Means your state-shaping classification is correct.

**Low state_reuse**: Could be fine (if state-shaping facts genuinely
change) or bad (if payload data is leaking into state declarations).

### Tuning Checklist

1. Is everything that should be `unique` marked `unique`?
2. Are dead fields stripped at each lowering?
3. Are state-shaping values properly bucketed?
4. Are gen functions defined once at module load, not per-call?
5. Are `M.lower()` boundaries at the right granularity?

---

## Chapter 32: Pattern — Designing for Incremental Updates

**Problem**: Your application recompiles the entire tree every frame,
even when only one leaf changed.

**Solution**: Leverage structural interning and boundary caching.

### The Incremental Cascade

When a user changes one leaf:

```
old_root = UI.Root(UI.Column(10, { rect_a, rect_b, text_c }))
new_root = UI.Root(UI.Column(10, { rect_a, rect_b, text_c_modified }))
```

Because all types are `unique`:

- `rect_a` is the same object (identity preserved)
- `rect_b` is the same object (identity preserved)
- `text_c_modified` is a new object (different text)
- The children list is new (contains a new element)
- The Column is new (contains a new children list)
- The Root is new (contains a new Column)

But when the lowering boundary processes the Root:

1. Root is new → L1 miss → recompile
2. Column is new → L1 miss → recompile children
3. `rect_a` is unchanged → L1 hit! Skip.
4. `rect_b` is unchanged → L1 hit! Skip.
5. `text_c_modified` is new → L1 miss → recompile leaf
6. Leaf emission: same gen (Text), maybe same state shape (if cap
   bucket unchanged) → L2/L3 hits → reuse family, rebind param

Result: Only one leaf recompiles. Everything else is cached.

### Design Principle: Maximize Subtree Stability

To get good incremental behavior:

1. Use `unique` on everything
2. Use `M.with()` for updates (preserves unchanged field identity)
3. Build lists functionally (map with identity preservation)
4. Put `M.lower()` boundaries at sum type dispatch points
5. Keep leaf compilers simple (so L2/L3 hits are common)

### Design Principle: The Narrowest Change Wins

If only param changes → instant (rebind only)
If state shape changes → one reallocation
If code shape changes → one recompile
If tree structure changes → recompile affected subtree only

The classification system ensures the framework always picks the
narrowest response.

---

## Chapter 33: Pattern — Event-Driven Architecture with ASDL Events

**Problem**: How do you model user interaction in a GPS system?

**Solution**: Events are ASDL types. Apply is a pure function. The
compile pipeline is triggered by source identity change.

### Event ASDL

```lua
module Event {
    Ev = Click(number x, number y)
       | Hover(number x, number y)
       | KeyPress(string key)
       | SetVolume(number track_id, number value)
       | Resize(number w, number h)
}
```

### The Apply Function

```lua
local function apply(source, event)
    if event.kind == "Click" then
        local hit = hit_slot.callback({ x = event.x, y = event.y })
        if hit and hit.tag:match("^btn:") then
            return M.with(source, { selected = hit.tag })
        end
    elseif event.kind == "SetVolume" then
        return M.with(source, {
            tracks = update_at(source.tracks, event.track_id, function(t)
                return M.with(t, { volume_db = event.value })
            end)
        })
    end
    return source  -- unchanged
end
```

### The Key Insight

`apply` returns the old source if nothing changed. The identity check
(`new_source ~= source`) in the app loop gates recompilation:

```lua
local new_source = apply(source, event)
if new_source ~= source then
    source = new_source
    paint_slot:update(compile_paint(source))
    hit_slot:update(compile_hit(source))
end
```

No diff. No dirty flags. No observer pattern. No signal system. Just
structural identity.

### The Interaction Loop in Full

```
User moves mouse → Hover(x, y) event
  → hit_slot.callback({x, y}) → hit result with tag
  → apply: set hover_tag in source
  → source changed? yes → recompile
  → recompile: only the hovered element's color param changes
  → paint_slot:update: same code_shape, same state_shape
  → only param rebound. Instant.
```

The entire interaction cycle — from mouse event to screen update —
flows through the classification system. Hover changes are payload.
Payload updates are instant.

---

## Chapter 34: Pattern — Sharing Computed Values Across Backends

**Problem**: Both paint and hit backends need layout information.
You do not want to compute layout twice.

**Solution**: Compute layout at the View layer. Both backends read
from the same View tree.

```lua
local compile_paint = M.lower("paint", function(root)
    local view = root:view()           -- layout computed here, once
    return view:paint_ast():draw()     -- paint projection
end)

local compile_hit = M.lower("hit", function(root)
    local view = root:view()           -- SAME view (interned!)
    return view:hit_ast():probe()      -- hit projection
end)
```

Because View nodes are `unique`, if both pipelines produce the same
View tree (which they will, since they start from the same source),
the View tree is interned once and shared.

If you want to be even more explicit about this sharing, compute the
View once and pass it to both backends:

```lua
local view = source.root:view()  -- compute once
paint_slot:update(compile_paint_from_view(view))
hit_slot:update(compile_hit_from_view(view))
```

---

## Chapter 35: Pattern — Backend-Specific State Factories

**Problem**: State allocation depends on the backend (Love2D vs. SDL
vs. headless testing). How do you keep backends swappable?

**Solution**: Pass allocation functions through resource ops:

```lua
-- Love2D backend
local function alloc_text_blob(spec)
    local font = fonts[spec.font_id]
    local text_obj = love.graphics.newText(font)
    return { text_obj = text_obj, cap = spec.cap, cache = false }
end

-- SDL backend
local function alloc_text_blob_sdl(spec)
    local surface = sdl.createSurface(spec.cap * 16, 32)
    return { surface = surface, cap = spec.cap }
end

-- Headless / test backend
local function alloc_text_blob_fake(spec)
    return { kind = "TextBlob", cap = spec.cap, font_id = spec.font_id }
end
```

The state declaration carries the alloc function:

```lua
M.state.resource("TextBlob", { cap = cap, font_id = fid }, {
    alloc = alloc_text_blob,  -- or alloc_text_blob_sdl, etc.
})
```

The gen function receives the allocated resource as `state` and
interacts with it through a backend-appropriate interface.

This keeps the schema and classification logic backend-agnostic. Only
the alloc/release functions and the gen implementations are
backend-specific.

---

## Chapter 36: Pattern — The Two-Phase Compile for Complex Containers

**Problem**: A container node needs information from its children
before it can configure itself (e.g., a scroll container needs total
content height to set scrollbar range).

**Solution**: Use a two-phase approach:

**Phase 1: Measure** — Traverse children to collect metrics.
**Phase 2: Place** — Use metrics to compute positions and produce
View nodes.

```lua
function U.UI.ScrollView:measure()
    local content_h = 0
    for i = 1, #self.children do
        local _, ch = self.children[i]:measure()
        content_h = content_h + ch
    end
    return self.viewport_w, self.viewport_h, content_h
end

function U.UI.ScrollView:place(x, y)
    local _, _, content_h = self:measure()
    local scroll_ratio = self.scroll_offset / math.max(1, content_h - self.viewport_h)

    local inner = {}
    local cy = y - self.scroll_offset
    for i = 1, #self.children do
        local _, ch = self.children[i]:measure()
        append_all(inner, self.children[i]:place(x, cy))
        cy = cy + ch
    end

    return {
        V.View.Clip(x, y, self.viewport_w, self.viewport_h,
            { V.View.Transform(0, -self.scroll_offset, inner) }
        )
    }
end
```

The two-phase approach is a layout-level concern. It does not leak
into the backend IR or the terminal. The View layer receives fully
resolved, positioned nodes.

---

## Chapter 37: The Flatten-Early Rule — Recursive Structures Are Expensive

This is arguably the single most important canonical rule in GPS/ASDL
design. It is easy to miss because trees feel natural and the ASDL
schema language makes them easy to write.

> **The Rule**: A recursive data structure (tree, graph) must be
> flattened into a linear traversal as early as possible. The first
> thing after a tree is a gen/param/state that iterates linearly.
> Containment goes on the side.

### Why Trees Are Expensive

A tree costs you at every level:

1. **Construction**: Allocating/interning nodes at every nesting level.
   An N-leaf tree with depth D creates O(N+D) intermediate nodes.

2. **Traversal**: Every lowering that walks the tree is O(N) recursive
   calls. Method dispatch at every node. Stack frames. Cache-unfriendly
   pointer chasing.

3. **Repetition**: If you have Tree → Tree → Tree → Machine, you are
   paying the recursive traversal cost THREE times before anything
   runs linearly.

4. **Composition overhead**: `M.compose()` on a tree produces nested
   gen calls. The runtime machine has N levels of function call
   nesting matching the tree shape.

Consider the current UI demo pipeline:

```
UI ASDL (tree)
  → recursive :measure() + :place()       ← traversal #1
    → View ASDL (tree)                     ← still a tree!
      → recursive :paint_ast()             ← traversal #2
        → LovePaint ASDL (tree)            ← still a tree!
          → recursive :draw()              ← traversal #3
            → recursive M.compose()        ← traversal #4
              → nested gen(param,state)     ← execution is nested calls
```

Four tree walks. The tree shape persists all the way to the terminal.

### What Flattening Means

Flattening means converting the tree into a **linear command sequence**
with **containment expressed as push/pop markers**:

```
Tree:                           Flat:
  Clip(0,0,800,600,             push_clip(0,0,800,600)
    Transform(10,20,              push_transform(10,20)
      Rect(0,0,100,30,0xff)        fill_rect(0,0,100,30,0xff)
      Text(0,0,1,0xff,"hi")        draw_text(0,0,1,0xff,"hi")
    )                             pop_transform
  )                             pop_clip
```

The flat list is just an array. Iterating it is a single `for` loop.
No recursion. No method dispatch. No pointer chasing. Cache-friendly
linear memory access.

Containment is expressed by push/pop pairs, not by nesting. The
**depth** information is implicit in the push/pop stack — it exists
on the side, as runtime state of the iterator, not in the structure
of the data.

### The Canonical Flattened IR

Instead of:

```
module Paint {
    Frame = (Node* nodes) unique
    Node = Group(Node* children) unique           ← RECURSIVE
         | Clip(... Node* body) unique             ← RECURSIVE
         | Transform(... Node* body) unique        ← RECURSIVE
         | RectFill(...) unique
         | Text(...) unique
}
```

The flattened IR is:

```
module DrawList {
    Frame = (Cmd* cmds) unique
    Cmd = PushClip(number x, number y, number w, number h) unique
        | PopClip unique
        | PushTransform(number tx, number ty) unique
        | PopTransform unique
        | FillRect(number x, number y, number w, number h, number rgba8) unique
        | DrawText(number x, number y, number font_id, number rgba8, string text) unique
}
```

No recursion. `Cmd*` is a flat list. The sum type has push/pop
variants for containment. A `Frame` is just an array of commands.

### The gen/param/state for a Flat DrawList

The flattened IR maps directly to a single gen/param/state machine:

```lua
local function drawlist_gen(param, state, g)
    local cmds = param.cmds
    for i = 1, #cmds do
        local cmd = cmds[i]
        local k = cmd.kind
        if k == "FillRect" then
            g:fill_rect(cmd.x, cmd.y, cmd.w, cmd.h, cmd.rgba8)
        elseif k == "DrawText" then
            g:draw_text(cmd.x, cmd.y, cmd.font_id, cmd.rgba8, cmd.text)
        elseif k == "PushClip" then
            g:push_clip(cmd.x, cmd.y, cmd.w, cmd.h)
        elseif k == "PopClip" then
            g:pop_clip()
        elseif k == "PushTransform" then
            g:push_transform(cmd.tx, cmd.ty)
        elseif k == "PopTransform" then
            g:pop_transform()
        end
    end
    return g
end
```

One gen. One param (the command array). State is whatever the
graphics backend tracks (clip stack, transform stack). No
`M.compose()`, no recursive gen nesting. Just a flat loop.

### Where Flattening Should Happen

The rule says: **immediately after the tree**.

The tree is the user's mental model. The user thinks in nested
containment: "this column contains these rows, each row contains
these widgets." That is correct and natural for authoring.

But the moment layout is resolved and we know positions, the tree
should become a flat list:

```
UI ASDL (tree)      ← user thinks in trees, that's fine
  │
  │  layout: :measure() + :place()
  │  ← the place() walk is the ONLY recursive traversal
  │  ← it produces flat commands, not a new tree
  ▼
DrawList (flat)     ← containment as push/pop markers
  │
  │  terminal: one emit() with a flat-loop gen
  ▼
Running machine     ← single gen, linear iteration
```

This replaces:

```
UI ASDL (tree)
  → View ASDL (tree)          ← eliminated
    → Paint ASDL (tree)       ← eliminated
      → composed machines     ← eliminated
```

Three intermediate tree layers collapse into one flat IR.

### How :place() Produces a Flat List

The layout walk already visits every node. Instead of producing
nested View nodes, it appends to a flat command list:

```lua
function UI.Clip:place(x, y, cmds)
    cmds[#cmds+1] = DrawList.Cmd.PushClip(x, y, self.w, self.h)
    self.child:place(x, y, cmds)     -- children append to same list
    cmds[#cmds+1] = DrawList.Cmd.PopClip
end

function UI.Rect:place(x, y, cmds)
    cmds[#cmds+1] = DrawList.Cmd.FillRect(x, y, self.w, self.h, self.rgba8)
end

function UI.Column:place(x, y, cmds)
    local cy = y
    for i = 1, #self.children do
        local _, ch = self.children[i]:measure()
        self.children[i]:place(x, cy, cmds)
        cy = cy + ch + self.spacing
    end
end
```

One recursive walk (the layout pass) produces a flat output.
Everything downstream is linear.

### State-Shaping in a Flat List

The question is: where does state-shaping classification happen in a
flat world?

Answer: **in the command itself**. Each `DrawText` command carries
enough information for the terminal gen to classify state:

```lua
local function drawlist_gen(param, state, g)
    local cmds = param.cmds
    for i = 1, #cmds do
        local cmd = cmds[i]
        if cmd.kind == "DrawText" then
            -- State management: check if this text's resource needs
            -- reallocation (capacity bucket changed, font changed)
            local res = state.text_resources[i]
            local cap = next_pow2(#cmd.text)
            if not res or res.cap ~= cap or res.font_id ~= cmd.font_id then
                if res then release_text_blob(res) end
                res = alloc_text_blob(cap, cmd.font_id)
                state.text_resources[i] = res
            end
            g:draw_text(res, cmd.font_id, cmd.text, cmd.x, cmd.y, cmd.rgba8)
        end
    end
    return g
end
```

State is managed per-command-slot in a flat array. When the command
list changes shape (commands added/removed/reordered), the state
array is reconciled — but that reconciliation is a flat diff, not a
tree diff.

### Containment on the Side

The phrase "containment on the side" means: the push/pop structure is
not in the data layout. It is in the **runtime execution state**.

The gen function maintains a clip stack and transform stack as it
walks the flat list:

```lua
-- Inside the gen:
if cmd.kind == "PushClip" then
    state.clip_depth = state.clip_depth + 1
    state.clip_stack[state.clip_depth] = { cmd.x, cmd.y, cmd.w, cmd.h }
    g:push_clip(cmd.x, cmd.y, cmd.w, cmd.h)
elseif cmd.kind == "PopClip" then
    g:pop_clip()
    state.clip_depth = state.clip_depth - 1
end
```

Containment is state. Iteration is linear. Data is flat.
That is the canonical shape.

### When NOT to Flatten

The user's authoring ASDL should remain a tree. Users think in
containment. Forcing them to think in push/pop is hostile.

The rule is about **the IR between authoring and execution**, not
about the authoring language itself.

Also, if you need multiple backends from one source (paint + hit-test),
you might flatten into different lists for each backend during the
same layout walk. The layout walk visits the tree once and appends
to multiple flat lists simultaneously:

```lua
function UI.Rect:place(x, y, paint_cmds, hit_cmds)
    paint_cmds[#paint_cmds+1] = PaintCmd.FillRect(x, y, self.w, self.h, self.rgba8)
    hit_cmds[#hit_cmds+1]     = HitCmd.Rect(x, y, self.w, self.h, self.tag)
end

function UI.Text:place(x, y, paint_cmds, hit_cmds)
    local w, h = self:measure()
    paint_cmds[#paint_cmds+1] = PaintCmd.DrawText(x, y, self.font_id, self.rgba8, self.text)
    hit_cmds[#hit_cmds+1]     = HitCmd.Rect(x, y, w, h, self.tag)
end
```

One tree walk, two flat outputs. No intermediate View tree needed.

### How This Changes the Layer Stack

Before (current mgps demo):

```
UI ASDL (tree, user-authored)
  → View ASDL (tree, positioned)       ← unnecessary intermediate tree
    → Paint ASDL (tree, backend)        ← unnecessary intermediate tree
      → M.compose() (recursive)         ← tree-shaped runtime
        → nested gen calls
```

After (flattened):

```
UI ASDL (tree, user-authored)
  │
  │  layout walk (one recursive pass, the ONLY recursive pass)
  │  outputs flat command lists for each backend
  ▼
PaintCmds (flat array) + HitCmds (flat array)
  │
  │  one emit() per backend, flat-loop gen
  ▼
Running machines (linear iteration)
```

### The Interning Story for Flat Lists

Flat command lists are still ASDL with `unique`. A `Frame(Cmd* cmds)`
is interned by its command sequence. If the same commands appear in
the same order, you get the same Frame object — L1 cache hit in
`M.lower()`, entire pipeline skipped.

Individual `Cmd` nodes are also interned. If a rect does not move,
its `FillRect(10, 20, 100, 30, 0xff0000ff)` is the same interned
object as last frame. The list interning walks the elements and
finds the same canonical list.

So structural caching still works. But now the cached object is a
flat array, not a tree. Cache comparison is a linear element walk,
not a recursive tree walk.

### The Performance Consequence

With flattening:

- **One** recursive traversal (layout) instead of three or four
- **Zero** intermediate tree allocations (View, Paint IR)
- **Zero** `M.compose()` overhead (no recursive gen nesting)
- **Linear** execution: one gen, one loop, cache-friendly
- **Simpler** state management: flat array of per-command resources

For N leaf nodes, the current pipeline does ~4N recursive method
calls across four tree layers. The flattened pipeline does ~N
recursive calls (layout) plus ~N linear iterations (execution).

### Summary: The Canonical Shape

```
User ASDL:    tree     (natural for authoring)
                │
         layout walk    (the ONE recursive pass)
                │
                ▼
Backend IR:   flat     (Cmd* array, push/pop for containment)
                │
         one emit()     (single gen with a for loop)
                │
                ▼
Execution:    linear   (gen iterates commands, state on the side)
```

Tree in. Flat out. Linear forever after.

That is the canonical rule.

---

## Chapter 38: The Layer-Count Rule — Mutual Recursion Materializes as Layers

Chapter 37 gives you the flatten-early rule: tree in, flat out, linear
forever. But it leaves a question open: **what if one recursive pass
is not enough?**

This happens constantly in real systems. The answer is the second
canonical pattern:

> Every cycle in the data dependency between parent and child
> costs you one materialized intermediate representation.

### The Problem: Parent-Child Dependency Cycles

Consider word-wrapping text inside a flex-grow container:

```
Parent asks child:  "how tall are you?"
Child (text) says:  "depends — how wide am I allowed to be?"
Parent says:        "depends — how wide are all my children."
```

That is a cycle:

```
parent height ← child height ← child width ← parent width ← child widths
                                                              ↑
                                                         (cycle back)
```

A single tree pass cannot resolve this. A top-down pass does not know
child heights yet. A bottom-up pass does not know parent width
constraints yet. You need **both directions**.

### The Solution: Two Passes, One Intermediate

Split the cycle into two passes over the same tree, with an
intermediate representation carrying partial results between them:

```
Pass 1 (down):  propagate constraints
  • parent tells child: "you have at most 300px width"
  • child records the constraint

Pass 2 (up):    resolve sizes
  • child wraps text within 300px → needs 4 lines → height = 80px
  • parent collects child heights → total height = 240px
```

The intermediate is the **constraint record** — the thing that pass 1
produces and pass 2 consumes. It can be as simple as a number
(available width) threaded through the recursion, or as complex as a
full constraint object (min/max width, min/max height, flex basis).

### The General Rule

Count the dependency cycles between parent and child:

| Cycles | Passes needed | Intermediate layers | Example                          |
|--------|---------------|--------------------|---------------------------------|
| 0      | 1             | 0                  | Static layout, fixed sizes       |
| 1      | 2             | 1                  | Word wrap + grow                 |
| 2      | 3             | 2                  | Intrinsic sizing + flex + wrap   |
| N      | N+1           | N                  | Full CSS (many cycles)           |

CSS layout is expensive because it has **many** such cycles:
percentage widths, min/max constraints, flex grow/shrink, baseline
alignment, intrinsic sizing. Each demands another pass. That is not
bad engineering — it is the honest cost of the dependency structure.

### What the Intermediate Looks Like

The intermediate is NOT a new ASDL tree. It is data attached to the
existing tree — or threaded through the traversal as parameters:

```lua
-- Pass 1: propagate constraints down
function UI.Column:layout(max_w)
    local child_constraints = {}
    for i = 1, #self.children do
        child_constraints[i] = { max_w = max_w }  -- or flex-computed
    end
    return child_constraints
end

-- Pass 2: resolve sizes up, emit flat commands
function UI.Column:place(x, y, max_w, dc, hc)
    local cy = y
    for i = 1, #self.children do
        local c = self.children[i]
        local ch = c:measure(max_w)   -- measure WITHIN constraint
        c:place(x, cy, max_w, dc, hc) -- emit flat commands
        cy = cy + ch + self.spacing
    end
end
```

In this example, `max_w` IS the intermediate. It flows down in pass 1
(often folded into the same traversal as pass 2 when the constraint is
simple enough). The resolved height flows up as the return value.

For more complex constraints (flex), the intermediate might be a
struct:

```lua
-- Constraint object threaded between passes
{
    min_w = 0, max_w = 300,
    min_h = 0, max_h = math.huge,
    flex_basis = 0, flex_grow = 1, flex_shrink = 1,
}
```

### The Two-Pass Flatten Pattern

Combining this with the flatten-early rule gives the complete
canonical shape for layout-heavy systems:

```
UI ASDL (tree, user-authored)
  │
  │  Pass 1 (down): propagate constraints
  │  Pass 2 (up):   resolve sizes + emit flat commands
  │
  │  (these can be fused into a single walk if the constraint
  │   is simple enough — e.g. just "available width")
  ▼
Flat Cmd* arrays — linear forever after
```

The key insight: **the two passes are still over the same tree**.
No new tree is materialized. The intermediate is a parameter
(constraint flowing down) and a return value (size flowing up).
The output is flat.

### When You Actually Need a Separate Tree Layer

Sometimes the intermediate really is big enough to justify its own
ASDL. This happens when:

1. **The intermediate is shared across multiple consumers.** If both
   the paint backend and the hit backend need the resolved layout
   (positions + sizes), you might materialize it as a positioned
   node list so both can read it.

2. **The intermediate needs to be cached independently.** If
   constraints change rarely but content changes often, caching the
   resolved layout separately lets you skip re-layout when only
   paint data changes.

3. **The intermediate has a different shape than the input.** If
   layout resolution collapses containers (Column disappears, its
   children become positioned leaves), the output shape differs
   enough from the input to warrant its own type.

But even in these cases, the materialized layer should be **flat**
(a list of positioned commands), not another tree.

### The Design Procedure

When designing your layer stack:

1. Write down what parents need from children.
2. Write down what children need from parents.
3. Count the dependency cycles.
4. That number is how many intermediate representations
   (constraint records) you need between passes.
5. All passes are over the **same** UI tree.
6. The output of the **last** pass is flat.

```
0 cycles →  1 pass  →  flat output
1 cycle  →  2 passes →  constraint + flat output
N cycles →  N+1 passes →  N intermediates + flat output
```

### Worked Example: Finding Cycles in a UI Layout System from Scratch

You are designing a UI from nothing. You want columns, rows, text
with word wrap, padding, and maybe flex-grow later. How do you know
how many passes you need?

**Step 1: List your layout features.**

Write them down plainly:

```
1. Fixed-size rectangles (Rect with explicit w, h)
2. Text with word wrap (width affects height)
3. Columns (stack children vertically, spacing)
4. Rows (stack children horizontally, spacing)
5. Padding (insets around a child)
6. Flex grow (distribute leftover space to children)
7. Min/max width constraints on flex children
```

**Step 2: For each feature, write what flows down and what flows up.**

Draw two columns — what the parent tells the child (constraints flowing
down), and what the child tells the parent (measurements flowing up):

```
Feature             Down (parent → child)         Up (child → parent)
───────────────────────────────────────────────────────────────────────
1. Fixed rect       (nothing)                     width, height
2. Text wrap        available width               wrapped height
3. Column           (nothing special)             total height, max width
4. Row              (nothing special)             total width, max height
5. Padding          (reduces available space)      adds to child size
6. Flex grow        assigned width (after grow)   natural width (before grow)
7. Min/max          (nothing extra)               clamped size
```

**Step 3: Trace data-flow arrows and look for loops.**

Start with features 1–5 only (no flex):

```
Column layout:
  Column has available width W (from its parent or the window).
  │
  ├─▶ Pass available width W to each child
  │     │
  │     ▼
  │   Child measures itself given W
  │   • Fixed rect: returns (w, h) — ignores W
  │   • Text: wraps within W → returns (actual_w, wrapped_h)
  │   • Padding: subtracts insets from W, asks inner child, adds insets back
  │     │
  │     ▼
  ├─◀ Child returns (child_w, child_h)
  │
  Column sums child heights + spacing → returns (max_child_w, total_h)
```

Data flows down (W) then up (sizes). **No cycle.** One pass suffices.
The parent knows W before it asks children. Children don't need
anything that depends on other children's answers.

This is why a simple Column + Row + Text + Padding layout needs only
**one pass**. You can fold measure and place into a single walk.

Now add feature 6 — **flex grow**:

```
Row with flex-grow children:
  Row has available width W.
  │
  ├─▶ Ask each child: "what is your natural width?"
  │     │
  │     ▼
  │   Child returns natural_w
  │     │
  ├─◀───┘
  │
  Row computes: leftover = W - sum(natural_widths)
  Row distributes leftover to children by grow factor
  │
  ├─▶ Tell each child: "your assigned width is X"
  │     │
  │     ▼
  │   Child re-measures within assigned width X
  │   (text re-wraps → new height)
  │     │
  ├─◀ Child returns (X, new_h)
  │
  Row returns (W, max(new_heights))
```

Trace the arrows:

```
child natural_w → parent leftover → parent distribution
    → child assigned_w → child wraps → child height → parent height
```

Is there a cycle? Let’s check:

- Parent needs child natural widths to compute distribution. ✔
- Child needs distribution result to know assigned width. ✔
- But child natural width does NOT depend on the distribution.
  It depends on the child's content and min-content.

So it is NOT a cycle in the strict sense — it is a **two-phase
linear dependency**:

```
Phase A (up):   children report natural sizes
Phase B (down): parent distributes, children resolve within assigned sizes
```

But it does require **two traversals of the children**: once to
collect natural sizes, once to assign and resolve. That’s two passes
over the same list. Whether you call this "one cycle" or "a two-phase
linear flow" is a matter of terminology — the practical consequence is
the same: **you need to visit children twice**.

So: flex grow = **1 additional pass** = **2 total passes**.

Now add feature 7 — **min/max constraints on flex children**:

```
Row with flex-grow + min/max:
  Phase A: collect natural widths
  Phase B: distribute leftover
    → child 3 gets assigned 400px, but max-width is 200px
    → child 3 is clamped to 200px
    → 200px of leftover is now unassigned
    → must redistribute to unclamped children   ← NEW PHASE
  Phase C: redistribute overflow from clamped children
    → child 1 and child 2 absorb the extra 200px
    → but wait — child 1 might now hit ITS max-width
    → iterate until stable                      ← POTENTIAL LOOP
```

This is a genuine cycle: redistribution depends on which children
clamped, but clamping depends on the distribution. In the worst case
this iterates up to N times (N = number of children). CSS flexbox
specifies this as a loop that terminates when no more children clamp.

In practice you can bound it: each iteration clamps at least one more
child, so at most N iterations. But it IS an additional pass (or
several).

So: min/max constraints on flex = **1 more potential pass** = **3 total**.

**Step 4: Build the cycle count table for your design.**

```
Design level         Features                        Cycles  Passes
─────────────────────────────────────────────────────────────────────
① Minimal           fixed + text + col/row + pad     0       1
② Flex              add grow/shrink                  1       2
③ Constrained flex  add min/max on flex children      2       3
④ Full CSS-like     add % sizes, intrinsic, baseline  3–4     4–5
```

**Step 5: Choose your design level.**

This is the critical engineering decision. You are not forced to
implement full CSS. Most UI toolkits don't.

- **Level ①** is what the mgps demos use. One pass. Simple. Covers
  90% of real UI layouts (fixed panels, scrollable lists, text labels,
  padding, columns, rows).

- **Level ②** is what Flutter and SwiftUI roughly do. Two passes
  (constraints down, sizes up). Covers flex layouts, which handle
  most responsive designs.

- **Level ③** is what CSS Flexbox does. Three passes with a clamp
  loop. Covers min/max constrained flex. More complex, but handles
  edge cases.

- **Level ④** is full CSS. Four or five passes. Handles everything
  but is famously complex and hard to optimize.

You choose the level based on what your users actually need. Each
level adds exactly one more pass, not one more tree layer.

**Step 6: Implement as passes over the same tree.**

For level ② (flex):

```lua
-- Pass 1: collect natural sizes (bottom-up)
function UI.Row:measure_natural()
    local sizes = {}
    for i = 1, #self.children do
        sizes[i] = { self.children[i]:measure_natural() }
    end
    return sizes
end

-- Pass 2: distribute and resolve (top-down), emit flat commands
function UI.Row:place(x, y, available_w, dc, hc)
    local sizes = self:measure_natural()
    local total_natural = 0
    for i = 1, #sizes do total_natural = total_natural + sizes[i][1] end

    local leftover = available_w - total_natural - (self.spacing * (#sizes - 1))
    local total_grow = 0
    for i = 1, #self.children do
        total_grow = total_grow + (self.children[i].grow or 0)
    end

    local cx = x
    for i = 1, #self.children do
        local child = self.children[i]
        local w = sizes[i][1]
        if total_grow > 0 and (child.grow or 0) > 0 then
            w = w + leftover * (child.grow / total_grow)
        end
        child:place(cx, y, w, dc, hc)
        cx = cx + w + self.spacing
    end
end
```

Two passes, same tree, flat output. No intermediate tree layer.

**The complete procedure summarized:**

```
1. List layout features
2. For each: what flows down? what flows up?
3. Trace arrows. Find loops.
4. Count unique cycles → that’s your pass count - 1
5. Choose your design level (you don’t have to support everything)
6. Implement as passes over the same tree
7. Last pass emits flat command arrays
8. Linear forever after
```

### Example: Audio DSP — Cycle Analysis

The same procedure works outside UI. Consider an audio graph:

```
Parent asks child:  "what is your output buffer?"
Child asks parent:  "what is the sample rate? buffer size?"
```

Sample rate and buffer size are **global constants**, not dependent on
child output. No cycle. One pass suffices.

But add feedback:

```
Delay node:  output depends on input from a FUTURE node in the graph
```

That is a cycle in the **graph** (not the tree). It requires a
different resolution strategy: break the cycle with a one-buffer
delay, which is standard in audio DSP. The "intermediate" is the
delay buffer — one per feedback cycle in the graph.

Same rule, different domain.

### Example: Compiler — Cycle Analysis

Type inference with bidirectional typing:

```
Parent (function call) asks child (argument): "what is your type?"
Child (lambda) asks parent: "what type are you expecting me to be?"
```

One cycle. Two passes: first synthesize types bottom-up, then check
types top-down. That’s exactly what bidirectional type checking does.
The intermediate is the "expected type" flowing down.

Mutual recursion in type definitions (type A references type B which
references type A) adds another cycle. The intermediate is a
"forward declaration" or "type variable" that gets unified later.

Same rule, same counting procedure.

### Combined with Chapter 37

The complete layer-count rule is:

> **Layers from flattening**: exactly 1 (tree → flat).
> **Layers from mutual recursion**: one per dependency cycle.
> **Total layers** = 1 + number of parent↔child dependency cycles.
> **The last output is always flat.**

This is mechanical. You do not guess how many layers you need.
You count cycles.

---

# Part VII — Advanced Topics

---

## Chapter 39: Fusion — Why GPS Machines Compose Without Materialization

One of the deepest consequences of the GPS model is **fusion**: composed
machines execute without materializing intermediate results.

When machine A's output feeds machine B's input:

```lua
M.compose({ machine_a, machine_b })
```

The composed gen directly calls A's gen and passes the result to B's
gen. There is no intermediate buffer, no command list, no temporary
array.

This is because composition preserves the `gen(param, state, input)`
shape. The outer gen is:

```lua
function(parent_param, parent_state, input)
    local mid = gen_a(parent_param[1], parent_state[1], input)
    return gen_b(parent_param[2], parent_state[2], mid)
end
```

Contrast with typical frameworks where each stage materializes a
command list, a diff, a virtual DOM, or an intermediate buffer.

### When to Break Fusion

Sometimes you WANT materialization: when you need to inspect, debug,
serialize, or replay the intermediate representation. In GPS, you
break fusion deliberately by inserting a lowering boundary that
captures the intermediate IR as an ASDL tree.

This is a design choice, not an accident.

---

## Chapter 40: The Self-Hosted Story — ASDL Parses Itself

The mgps ASDL parser is itself a GPS machine:

- **Lexer**: `lex_next` is the gen. The compiled byte buffer is param.
  The byte position is state.
- **Parser**: The parse functions step the lexer directly (fusion!).
  Parser param contains `lex_gen` and `lex_param`. Parser state is
  the current token position.

This is not just cute. It demonstrates that the GPS model is
self-consistent: the tools that build GPS structures are themselves GPS
machines.

### The Lexer Is an Iterator

```lua
for pos, kind, start, stop in lex_next, compiled_param, 0 do
    -- process token
end
```

Zero allocation. The VM sees the native loop shape. The trace compiler
handles it perfectly.

### The Parser Fuses with the Lexer

The parser does not tokenize first and then parse. It steps the lexer
on demand:

```lua
local function advance(param, state)
    local new_pos, kind, start, stop = param.lex_gen(param.lex_param, state.pos)
    state.pos = new_pos
    state.tok_kind = kind
    state.tok_start = start
    state.tok_stop = stop
end
```

One machine (parser) driving another machine (lexer) through stable
param references. No token array materialized. Pure fusion.

---

## Chapter 41: Designing for Hot Reload / Live Coding

GPS machines naturally support hot reload because gen, param, and state
are separate:

1. **Change gen** (new code): Slot detects different code_shape.
   Depending on state_shape compatibility, state may be preserved.

2. **Change param** (new data): Slot detects same family. State is
   preserved. Only param is rebound. Instant.

3. **Change state_decl** (new state layout): Slot detects different
   state_shape. Old state is retired, new state allocated. Gen may
   be preserved if code_shape is unchanged.

This means:

- Tweaking visual parameters (colors, positions) → instant (payload)
- Tweaking buffer sizes → state realloc (state-shaping) but gen reuse
- Changing widget types → full recompile of that subtree

The key is that GPS tells you exactly what kind of change happened,
so the framework can choose the minimal response.

---

## Chapter 42: The Grammar Compiler — ASDL All the Way Down

The `grammar.lua` module demonstrates the full GPS philosophy applied
to parsing:

1. **The grammar itself is ASDL**:

   ```
   module Grammar {
       Spec = (Lex lex, Parse parse) unique
       Rule = (string name, Expr body) unique
       Expr = Seq(Expr* items) | Choice(Expr* arms) | ...
   }
   ```

2. **The grammar compiler is a GPS lowering**: Grammar ASDL →
   specialized lexer + parser.

3. **The resulting parser is a GPS machine**: gen = parse function,
   param = grammar tables + lexer, state = parse cursor.

4. **The lexer inside the parser is also a GPS machine**: fused, zero
   allocation, directly stepped by the parser gen.

This is four layers of GPS, each with its own ASDL, each with its own
lowering, all the way from grammar specification to parsed output.

---

## Chapter 43: When Classification Is Ambiguous

Sometimes a field genuinely resists clean classification. Here are the
hard cases and how to resolve them.

### Case: A Value That Is Both State-Shaping and Payload

`font_id` in a Text node:

- State-shaping: different font → different TextBlob resource
- Payload: gen needs it to select the font at draw time

**Resolution**: Include it in BOTH state_decl and param:

```lua
M.emit(
    text_gen,
    M.state.resource("TextBlob", { cap = cap, font_id = self.font_id }),
    { ..., font_id = self.font_id, ... }
)
```

This is correct. The duplication is semantic, not mechanical. The
state declaration needs `font_id` to choose the right resource
allocation. The param needs `font_id` to pass to the gen at runtime.
They serve different purposes.

### Case: A Value Whose Classification Depends on Magnitude

Text length:

- Length 1–16: cap=16 (state shape A)
- Length 17–32: cap=32 (state shape B)
- Length 1‒16 changing to length 13: same cap, payload-only
- Length 16 changing to length 17: cap changes, state-shaping

**Resolution**: Bucket and split. The bucketed value is state-shaping.
The raw value is payload:

```lua
local cap = next_power_of_two(#self.text)  -- state-shaping
local text = self.text                     -- payload
```

### Case: A Value That Is Code-Shaping at One Level but Payload at Another

`filter_mode` in audio:

- At the device level: code-shaping (LowPass vs HighPass → different gen)
- At the graph level: payload (the graph just calls whatever device is there)

**Resolution**: Classification is per-boundary, not per-field. The same
field can have different classifications at different layers. The
schema expresses this naturally: `FilterMode` is a sum type at the
device level (code-shaping) but an opaque value at the graph level
(just one of many devices).

### Case: A Field That Might Be Dead or Might Be Needed

`tag` in a View node:

- Dead for paint backend
- Alive for hit backend
- Alive for accessibility backend

**Resolution**: Keep it in the View layer. Each backend projection
decides to include or strip it. The View is the union of all backend
needs.

---

## Chapter 44: Composition Depth and Performance

Deep composition trees can become expensive if not designed carefully.

### The Cost Model

Each composition level adds:

- One composed gen function call
- One level of param array indexing
- One level of state array indexing

For 100 children in a Group, the composed gen is:

```lua
for i = 1, 100 do
    child_gens[i](param[i], state[i], g)
end
```

This is fast. LuaJIT traces this inner loop well.

For 10 levels of nesting, each with 10 children, you get 10 billion
param/state index lookups per traversal. That is... fine, actually.
The lookups are array indexing into Lua tables. Very fast.

### When Composition Becomes Expensive

Composition becomes expensive when:

1. **Code shape changes frequently.** If the tree structure changes
   every frame, the composed code_shape changes, the slot detects a
   different family, and state is reallocated. This is correct but
   expensive.

2. **State composition is deep with many resources.** If every leaf
   has a resource, the product state has many children to
   allocate/release on structural changes.

3. **The composition body function is expensive.** If the body
   function does complex work beyond calling child gens, that work
   runs every frame.

### Mitigation

1. **Stabilize tree structure.** If possible, design your UI so the
   tree shape is stable across frames. Content changes (text, colors)
   are payload. Structure changes (adding/removing children) are
   code-shaping and more expensive.

2. **Use sub-boundaries.** Put `M.lower()` boundaries at stable
   subtree roots. If a subtree is unchanged, its entire composition
   result is cached.

3. **Pool resources.** For resource-heavy trees, consider pooled
   allocation strategies in your state declaration's alloc function.

---

## Chapter 45: Designing ASDL for Animations and Time-Varying Data

Animations are an interesting GPS design challenge because they
involve time-varying values.

### Approach 1: Animation as Source Data

Model the animation parameters in the source ASDL:

```lua
module Anim {
    Value = Static(number v) unique
          | Linear(number from, number to, number t) unique
          | Spring(number target, number stiffness, number damping) unique
}
```

The lowering resolves the current value:

```lua
function Anim.Value.Linear:resolve()
    return self.from + (self.to - self.from) * self.t
end
```

Every frame, `t` is updated via `M.with()`, producing a new source.
The structural identity change triggers recompilation, but only the
animated subtree recompiles.

Classification: `t` is payload at the terminal level. The animation
kind (Linear vs Spring) is code-shaping at the resolve level but
disappears after resolution.

### Approach 2: Animation as State

For physics-based animations (springs, particles), the animation
state lives in the machine's state:

```lua
M.state.ffi("struct { double pos, vel; }")
```

The gen function steps the simulation:

```lua
local function spring_gen(param, state, dt)
    local force = (param.target - state[0].pos) * param.stiffness
                  - state[0].vel * param.damping
    state[0].vel = state[0].vel + force * dt
    state[0].pos = state[0].pos + state[0].vel * dt
    return state[0].pos
end
```

Here, `target` is payload (can change without state reallocation).
`stiffness` and `damping` are also payload. Only the choice of spring
vs. linear is code-shaping.

### When to Use Which Approach

**Source data approach**: When the animation is driven by external
time (keyframes, interpolation curves). The source changes every
frame, but the change is payload-only.

**State approach**: When the animation has internal dynamics (springs,
particles, physics). The machine owns evolving state that cannot be
expressed as a pure function of source data.

---

## Chapter 46: Testing GPS Systems

The GPS architecture makes testing unusually clean.

### Level 1: Test the ASDL

Construct nodes and verify structural properties:

```lua
local a = T.View.Box("test", 0, 0, 100, 30, 0xff0000ff)
local b = T.View.Box("test", 0, 0, 100, 30, 0xff0000ff)
assert(a == b, "unique interning should give same object")

local c = T.View.Box("test", 0, 0, 100, 30, 0x00ff00ff)
assert(a ~= c, "different color should give different object")
```

### Level 2: Test Individual Lowerings

Call a lowering function and inspect the output ASDL:

```lua
local ui_node = U.UI.Rect("btn", 100, 30, 0xff0000ff)
local view_nodes = ui_node:place(50, 75)
assert(#view_nodes == 1)
assert(view_nodes[1].x == 50)
assert(view_nodes[1].y == 75)
```

### Level 3: Test Terminal Emission

Call the terminal method and inspect the emitted triple:

```lua
local paint_node = P.Paint.RectFill(10, 20, 100, 30, 0xff0000ff)
local result = paint_node:draw()
assert(M.is_compiled(result))
-- Check that state is none
assert(result.state_decl.tag == "none")
-- Check param
assert(result.param.x == 10)
assert(result.param.y == 20)
```

### Level 4: Test Running Machines

Use a fake/mock backend:

```lua
local gfx = FakeGraphics:new()
slot.callback(gfx)
assert(#gfx.ops > 0)
assert(gfx.ops[1].op == "fill_rect")
assert(gfx.ops[1].x == 10)
```

The `FakeGraphics` in the mgps UI demo is exactly this pattern:
a mock backend that records operations for verification.

### Level 5: Test Cache Behavior

Use `M.report()` to verify caching expectations:

```lua
slot:update(compile(source))
slot:update(compile(source))  -- same source
local stats = compile.stats()
assert(stats.node_hits >= 1, "second call should hit L1 cache")
```

---

# Part VIII — Complete Worked Examples

---

## Chapter 47: Example — Audio DSP Pipeline

### Schema

```lua
local T = M.context("compile")
    :Define [[
        module DSP {
            Graph = (Device* devices) unique

            Device = Osc(number hz) unique
                   | Filter(FilterMode mode, number freq, number q) unique
                   | Gain(number db) unique
                   | Chain(Device* devices) unique
                   | Mix(Device* inputs) unique

            FilterMode = LowPass | HighPass | BandPass
        }
    ]]
```

### Classification Analysis

| Type/Field         | Classification | Reason                                    |
|--------------------|----------------|-------------------------------------------|
| `Osc \| Filter \| Gain` | code-shaping   | different gen per device type              |
| `LowPass \| HighPass`   | code-shaping   | different filter equation                 |
| `hz`               | payload         | changes phase increment, not state layout |
| `freq`, `q`        | payload         | changes coefficients, not state layout    |
| `db`               | payload         | changes gain factor, not state layout     |
| `Chain`, `Mix`     | composition     | structural containers                     |

### Leaf Compilers

```lua
local function osc_gen(param, state, buf)
    for i = 0, buf.len - 1 do
        buf.data[i] = math.sin(state[0] * 2 * math.pi)
        state[0] = (state[0] + param.phase_inc) % 1.0
    end
    return buf
end

function T.DSP.Osc:compile(sr)
    return M.emit(
        osc_gen,
        M.state.ffi("double[1]"),
        { phase_inc = self.hz / sr }
    )
end

local function lowpass_gen(param, state, buf)
    -- biquad lowpass implementation using param coefficients and state delays
    ...
end

function T.DSP.Filter:compile(sr)
    local gen_map = {
        LowPass = lowpass_gen,
        HighPass = highpass_gen,
        BandPass = bandpass_gen,
    }
    return M.emit(
        gen_map[self.mode.kind],
        M.state.ffi("struct { double x1, x2, y1, y2; }"),
        compute_biquad_coefficients(self.mode.kind, self.freq, self.q, sr)
    )
end

function T.DSP.Gain:compile(sr)
    return M.emit(
        gain_gen,
        M.state.none(),
        { factor = 10 ^ (self.db / 20) }
    )
end
```

### Composition

`Chain` sequences devices. `Mix` sums their outputs. The framework
auto-wires both because they have `Device* devices` / `Device* inputs`
fields.

But you might override Mix to sum instead of sequence:

```lua
function T.DSP.Mix:compile(sr)
    local children = {}
    for i = 1, #self.inputs do
        children[i] = self.inputs[i]:compile(sr)
    end
    return M.compose(children, function(child_gens, param, state, buf)
        local sum_buf = alloc_temp_buf(buf.len)
        clear_buf(sum_buf)
        for i = 1, #child_gens do
            local child_buf = alloc_temp_buf(buf.len)
            copy_buf(child_buf, buf)
            child_gens[i](param[i], state[i], child_buf)
            add_buf(sum_buf, child_buf)
        end
        copy_buf(buf, sum_buf)
        return buf
    end)
end
```

---

## Chapter 48: Example — Full UI Application Structure

### File Organization

```
app/
├── schema.lua          -- all ASDL definitions
├── ui_methods.lua      -- UI ASDL lowering methods (:view, :measure, :place)
├── view_methods.lua    -- View ASDL projection methods (:paint_ast, :hit_ast)
├── paint_backend.lua   -- Paint IR terminal methods (:draw)
├── hit_backend.lua     -- Hit IR terminal methods (:probe)
├── events.lua          -- Event ASDL + apply function
├── main.lua            -- App loop, slots, wiring
```

### schema.lua

```lua
return function(M)
    -- User domain
    local U = M.context("view")
        :Define [[
            module UI {
                Root = (Node body) unique
                Node = Column(number spacing, Node* children) unique
                     | Rect(string tag, number w, number h, number rgba8) unique
                     | Text(string tag, number font_id, number rgba8, string text) unique
            }
        ]]

    -- View layer
    local V = M.context("paint_ast")
        :Define [[
            module View {
                Root = (VNode* nodes) unique
                VNode = Box(string tag, number x, number y, number w, number h, number rgba8) unique
                      | Label(string tag, number x, number y, number w, number h,
                              number font_id, number rgba8, string text) unique
            }
        ]]

    -- Paint backend
    local P = M.context("draw")
        :Define [[
            module Paint {
                Frame = (Node* nodes) unique
                Node = RectFill(number x, number y, number w, number h, number rgba8) unique
                     | Text(number x, number y, number font_id, number rgba8, string text) unique
            }
        ]]

    -- Hit backend
    local H = M.context("probe")
        :Define [[
            module Hit {
                Root = (Node* nodes) unique
                Node = Rect(number x, number y, number w, number h, string tag) unique
                     | Text(number x, number y, number w, number h, string tag) unique
            }
        ]]

    return { UI = U, View = V, Paint = P, Hit = H }
end
```

### events.lua

```lua
return function(M, schema)
    local E = M.context()
        :Define [[
            module Event {
                Ev = Click(number x, number y)
                   | Hover(number x, number y)
                   | KeyPress(string key)
                   | SetColor(string tag, number rgba8)
            }
        ]]

    local function apply(source, event)
        if event.kind == "SetColor" then
            return M.with(source, {
                body = update_node_by_tag(source.body, event.tag, { rgba8 = event.rgba8 })
            })
        end
        return source
    end

    return { Event = E, apply = apply }
end
```

### main.lua

```lua
local M = require("mgps")
local schema = require("schema")(M)
local events = require("events")(M, schema)

-- Install leaf compilers
schema.UI:use(require("ui_methods"))
schema.View:use(require("view_methods"))
schema.Paint:use(require("paint_backend"))
schema.Hit:use(require("hit_backend"))

-- Compile pipelines
local compile_paint = M.lower("paint", function(root)
    return root:view():paint_ast():draw()
end)

local compile_hit = M.lower("hit", function(root)
    return root:view():hit_ast():probe()
end)

-- Slots
local paint_slot = M.slot()
local hit_slot = M.slot()

-- Initial source
local source = build_initial_ui()

-- Compile
paint_slot:update(compile_paint(source))
hit_slot:update(compile_hit(source))

-- App loop
while running do
    local event = poll_event()
    local new_source = events.apply(source, event)
    if new_source ~= source then
        source = new_source
        paint_slot:update(compile_paint(source))
        hit_slot:update(compile_hit(source))
    end
    paint_slot.callback(graphics)
end

-- Cleanup
paint_slot:close()
hit_slot:close()
```

---

## Chapter 49: Example — Language Compiler Pipeline

### Schema

```lua
local T = M.context("compile")
    :Define [[
        module Lang {
            Program = (Stmt* stmts) unique

            Stmt = Let(string name, Expr value) unique
                 | Return(Expr value) unique
                 | ExprStmt(Expr value) unique

            Expr = Literal(number value) unique
                 | Var(string name) unique
                 | BinOp(Op op, Expr left, Expr right) unique
                 | Call(string func, Expr* args) unique

            Op = Add | Sub | Mul | Div
        }
    ]]
```

### Layer Design

```
Lang (source)    →  IR (lowered)       →  Terminal (bytecode gen)
  Expr.BinOp         IR.BinOp              emit(binop_gen, state, param)
  Expr.Call           IR.Call               emit(call_gen, state, param)
  Expr.Var            IR.Load               emit(load_gen, state, param)
  Expr.Literal        IR.Const              emit(const_gen, state, param)
```

### Classification Analysis

| Source Field  | At IR boundary | At Terminal      |
|---------------|----------------|------------------|
| Op (Add/Sub)  | code-shaping   | code-shaping     |
| value (Literal)| payload       | payload          |
| name (Var)    | resolved to slot index | payload (slot index) |
| func (Call)   | resolved to address    | payload (address)    |
| args (Call)   | composition    | compose children |

Notice: `name` is **consumed** at the IR boundary. The IR does not
contain variable names; it contains resolved slot indices. The name
is dead after name resolution.

### The IR ASDL

```lua
module IR {
    Block = (Inst* insts) unique

    Inst = Const(number value) unique
         | Load(number slot) unique
         | Store(number slot) unique
         | BinOp(BinOpKind kind) unique
         | Call(number addr, number nargs) unique
         | Ret unique

    BinOpKind = Add | Sub | Mul | Div
}
```

This IR is register-less (stack machine). Each Inst is a single
operation. BinOpKind is a sum type for code-shaping.

### Terminal

```lua
local function const_gen(param, state, vm)
    vm:push(param.value)
    return vm
end

function IR.Inst.Const:compile()
    return M.emit(const_gen, M.state.none(), { value = self.value })
end

local binop_gens = {
    Add = function(param, state, vm)
        local b, a = vm:pop(), vm:pop()
        vm:push(a + b)
        return vm
    end,
    Sub = function(param, state, vm) ... end,
    Mul = function(param, state, vm) ... end,
    Div = function(param, state, vm) ... end,
}

function IR.Inst.BinOp:compile()
    return M.emit(
        binop_gens[self.kind.kind],  -- code-shaping from sum type
        M.state.none(),
        {}
    )
end
```

The pattern is identical to UI painting: sum types determine gen,
scalars become payload, composition follows containment.

---

## Chapter 50: Example — Spreadsheet Evaluator

### Schema

```lua
module Sheet {
    Cell = Formula(CellRef* deps, Expr expr) unique
         | Value(number val) unique
         | Empty unique

    CellRef = (number row, number col) unique

    Expr = Literal(number value) unique
         | Ref(CellRef cell) unique
         | Sum(Expr* args) unique
         | Product(Expr* args) unique
}
```

### Layer Design

The spreadsheet has only two layers:

1. **Source**: The cell grid with formulas
2. **Terminal**: Evaluation machines

No intermediate IR is needed because the lowering is simple.

### Classification

| Field          | Classification | Reason                               |
|----------------|----------------|--------------------------------------|
| Formula/Value  | code-shaping   | different evaluation strategy        |
| Sum/Product    | code-shaping   | different aggregation gen            |
| Literal value  | payload        | just data                            |
| CellRef        | payload        | reference to another cell's value    |
| deps           | state-shaping  | determines dependency tracking state |

`deps` is state-shaping because the dependency tracking state changes
when the set of dependencies changes. If cell A1 suddenly depends on
B2 instead of B1, the evaluation order and caching structure change.

### Terminal

```lua
function Sheet.Expr.Sum:compile(grid)
    local children = {}
    for i = 1, #self.args do
        children[i] = self.args[i]:compile(grid)
    end
    return M.compose(children, function(child_gens, param, state, env)
        local total = 0
        for i = 1, #child_gens do
            total = total + child_gens[i](param[i], state[i], env)
        end
        return total
    end)
end

function Sheet.Expr.Ref:compile(grid)
    return M.emit(
        function(param, state, env)
            return env.values[param.row][param.col]
        end,
        M.state.none(),
        { row = self.cell.row, col = self.cell.col }
    )
end
```

When a cell formula changes, only that cell's machine recompiles.
The slot preserves state for unchanged cells. Same patterns, different
domain.

---

## Chapter 51: Example — Game Entity System

### Schema

```lua
module Game {
    World = (Entity* entities) unique

    Entity = Player(number x, number y, number hp, number speed) unique
           | Enemy(EnemyKind kind, number x, number y, number hp) unique
           | Projectile(number x, number y, number vx, number vy, number damage) unique
           | Pickup(PickupKind kind, number x, number y) unique

    EnemyKind = Zombie | Skeleton | Boss
    PickupKind = Health | Ammo | Key
}
```

### Classification

| Field          | Classification | Reason                               |
|----------------|----------------|--------------------------------------|
| Player/Enemy   | code-shaping   | different update and render gen       |
| EnemyKind      | code-shaping   | different AI behavior                |
| x, y           | payload        | position changes every frame         |
| hp             | payload        | changes on damage, not state-shaping |
| speed          | payload        | tuning parameter                     |
| vx, vy         | payload        | velocity changes every frame         |

Notice: nothing is state-shaping here! Game entities are often
stateless at the machine level (all mutable data is in the ASDL
source, not in machine state). The source IS the state.

This is a valid and common pattern for ECS-style games:

- Source = entity data (functional, immutable per frame)
- Gen = update/render logic per entity kind
- Param = entity data
- State = none (or minimal per-entity render state)

The compile pipeline turns the entity list into a composed machine
that updates/renders all entities in sequence.

---

# Part IX — Design Checklist and Anti-Patterns

---

## Chapter 52: The ASDL Design Checklist

Use this checklist when designing any ASDL schema:

### Structure

- [ ] Every type that benefits from identity-based caching is `unique`
- [ ] Sum types represent genuine code-shaping choices
- [ ] Product types with child lists represent composition points
- [ ] No backend-specific fields in the user ASDL
- [ ] No layout-specific fields above the view layer
- [ ] No resource handles in any ASDL (those are state, not schema)

### Fields

- [ ] Every field at the backend IR level is classifiable as code-shaping,
      state-shaping, payload, or dead
- [ ] No field is ambiguously classified
- [ ] State-shaping continuous values are bucketed
- [ ] Dead fields are stripped at the appropriate lowering

### Lowerings

- [ ] Each lowering has a clear source ASDL and target ASDL
- [ ] Cross-module lowerings are wrapped in `M.lower()`
- [ ] Leaf compilers call `M.emit()` with all three parts
- [ ] Container compilers call `M.compose()` with appropriate body functions
- [ ] Gen functions are defined once at module load time

### Runtime

- [ ] One slot per output
- [ ] Slots are long-lived
- [ ] `slot:collect()` is called periodically (or `slot:close()` at shutdown)
- [ ] Diagnostics (`M.report()`) are available for tuning

---

## Chapter 53: Common Anti-Patterns

### Anti-Pattern: The God ASDL

**Symptom**: One enormous ASDL that covers everything from user input
to GPU commands.

**Fix**: Split into layers. Each layer is its own ASDL module with its
own concerns.

### Anti-Pattern: Runtime Dispatch on Source Structure

**Symptom**: A gen function contains `if node.kind == "Rect" then ...
elseif node.kind == "Text" then ...`.

**Fix**: That is a sum type dispatch. Use `M.match()` or let the
framework auto-wire it. Each variant gets its own gen.

### Anti-Pattern: Keys in User Space

**Symptom**: User code computes `gen_key = "text_" .. font_id .. "_" ..
cap`. Manual cache keys everywhere.

**Fix**: Use structural state declarations. The framework computes
shape strings from the declaration structure. No user keys.

### Anti-Pattern: Closures as Gens

**Symptom**: A new closure is created every time a node is compiled.
Code_shape is never stable because every closure is a different
function reference.

**Fix**: Define gen functions once at module scope. Pass varying data
through param, not through closure captures.

### Anti-Pattern: Mutation of Interned Nodes

**Symptom**: Mysterious bugs where changing one node affects unrelated
parts of the tree.

**Fix**: Never mutate interned objects. Use `M.with()` for structural
updates.

### Anti-Pattern: Unbucketed State-Shaping Values

**Symptom**: State is reallocated on every frame because a
continuously varying value (text length, buffer size) is in the state
declaration without bucketing.

**Fix**: Bucket with `next_power_of_two()` or similar.

### Anti-Pattern: Payload in State Declaration

**Symptom**: State reallocation on every parameter change. Terrible
performance.

**Fix**: Audit the state declaration. Only allocation-relevant facts
belong there. Everything else is payload.

### Anti-Pattern: Monolithic Lowering

**Symptom**: One huge function that goes from user ASDL to emitted
machines with no intermediate boundaries.

**Fix**: Insert intermediate IRs and lowering boundaries. Each boundary
is a caching opportunity.

---

# Part X — Philosophy, Principles, and the Deep "Why"

---

## Chapter 54: The Fundamental Insight — Programs Are Compilers, Not Interpreters

The deepest thing GPS teaches is that virtually all interactive
programs are compilers in disguise.

Consider what a UI framework does:

1. Takes a description of widgets (source)
2. Resolves layout (analysis pass)
3. Produces draw commands (code generation)
4. Executes draw commands (runtime)
5. On user input, potentially re-does steps 1–4 (recompilation)

That is a compiler. The source is the widget tree. The target is GPU
commands. The "runtime" is the graphics backend.

Consider what an audio engine does:

1. Takes a description of the signal graph (source)
2. Resolves routing and buffer allocation (analysis pass)
3. Produces a processing schedule (code generation)
4. Executes the schedule per audio buffer (runtime)
5. On parameter change, potentially re-does steps 1–4 (recompilation)

Same thing. Different domain.

GPS makes this compiler nature explicit. Instead of hiding it behind
object graphs, event buses, and reactive frameworks, GPS says:

> Your program has a source representation.
> Your program has a target representation.
> The transformation between them is compilation.
> The execution of the result is runtime.
> These are different concerns. Keep them separate.

Once you see this, the entire architecture becomes clear. Every design
question reduces to a compiler design question:

- "What type should this object be?" → "What ASDL type is this node?"
- "How do I handle events?" → "How does the source update?"
- "How do I optimize rendering?" → "Where are the memoization boundaries?"
- "How do I manage state?" → "What is the state declaration?"
- "How do I hot-reload?" → "What recompilation level does this change trigger?"

---

## Chapter 55: Why Three Roles and Not Two or Four

Could we collapse param into gen (like closures do)? Yes, but then we
lose the ability to rebind param without changing gen. Payload updates
become code-shape changes. Performance craters.

Could we collapse state into param (make everything immutable)? Yes,
but then we lose the ability to have persistent mutable resources
(GPU buffers, audio delay lines, file handles). We would need to
recreate them every frame.

Could we add a fourth role — say, "env" for shared global state? We
could, but it would not add explanatory power. Global shared state is
just param that happens to be shared across machines. The runtime
shape is still `gen(param, state, input)` where param contains a
reference to the shared environment.

Could we add a "meta" role for compilation-time-only data? We already
have it implicitly: it is the ASDL node that the lowering consumes.
It does not need to be a runtime role because it does not exist at
runtime.

Three roles is the minimal complete decomposition:

- **gen**: what to do (code)
- **param**: what to do it with (data the code reads)
- **state**: what persists across invocations (data the code owns)

Anything fewer loses expressiveness. Anything more does not add it.

---

## Chapter 56: Why Structural Identity Over Reference Identity

In OOP, two objects with identical fields are still two different
objects (`a ~= b` even if all fields match). Identity is reference-
based.

In GPS/ASDL with `unique`, two nodes with identical fields ARE the
same object (`a == b`). Identity is structural.

This single difference eliminates entire categories of bugs and
complexity:

| Problem                  | Reference identity          | Structural identity        |
|--------------------------|-----------------------------|----------------------------|
| Equality testing         | Deep comparison (expensive) | `==` (instant)             |
| Caching                  | Manual cache keys            | Automatic from identity    |
| Change detection         | Dirty flags / observers      | Identity comparison        |
| Deduplication            | Manual interning             | Automatic from constructor |
| Structural sharing       | Manual (error-prone)         | Automatic from `M.with()`  |
| Undo/redo                | Clone entire state           | Just store old root ref    |

The cost is immutability: you cannot mutate interned nodes. But GPS
never NEEDS to mutate them, because the source is updated functionally
and the runtime state is separate (in slots).

---

## Chapter 57: Why Classification Over Convention

Many frameworks use convention to manage the gen/param/state split:

- "Methods that start with `render_` are gens"
- "Props are params, state is state"
- "Use `useMemo` for caching, `useRef` for state"

GPS uses classification instead:

- Sum type variants ARE code-shaping (structural, not convention)
- State declarations ARE structural data (not hooks or decorators)
- Payload IS whatever is left after classification (not a guess)

Convention fails under pressure: developers break conventions,
edge cases accumulate, the framework cannot verify correctness.

Classification is verifiable: the framework can check that every emit
has a gen, a state_decl, and a param. It can compute shape strings. It
can report cache statistics. It can detect misclassification through
performance anomalies.

This is why `M.report()` exists and is so valuable: it surfaces
classification errors as measurable performance data.

---

## Chapter 58: Why Structure Over Keys

The deepest design principle of GPS/mgps is:

> Tell me your structure, not your keys.

Keys are an escape hatch. They let the user manually specify cache
identity. They work, but they:

- Leak framework mechanics into domain code
- Are error-prone (wrong key → stale cache or missed cache)
- Are non-compositional (parent keys must include child keys)
- Cannot be verified by the framework

Structure is the opposite:

- It is already there (the ASDL, the state declaration, the gen
  reference)
- It composes naturally (product of child structures)
- The framework can verify it (type checks, shape comparison)
- The user does not think about it (it is implicit in the domain model)

Every time you reach for a key, ask: "Can I express this as structure
instead?" Usually you can.

---

## Chapter 59: Why ASDL Over Ad Hoc Types

ASDL gives you:

1. **Sum types**: real, tagged, with membership checks. Not `if
   type(x) == "table" and x.kind == ...`.

2. **Structural interning**: same values → same object. Not possible
   with plain Lua tables.

3. **Constructor validation**: type-checked fields at construction
   time. Catches errors early.

4. **Method propagation**: define a method on a sum parent, all
   variants get it. Define on a variant, only that variant has it.

5. **Schema as documentation**: the ASDL is a readable, parseable
   specification of your domain types.

6. **Framework integration**: the context auto-wires dispatch and
   composition from the schema.

You could build all of this by hand with metatables, but you would
spend more time on plumbing than on your domain.

---

## Chapter 60: Why Compilation Over Interpretation

GPS models applications as compilers, not interpreters.

An interpreter traverses the source tree at runtime, making decisions
at every node. It is simple but slow: every frame re-traverses, re-
dispatches, re-checks.

A compiler traverses the source tree once (or incrementally), produces
an optimized machine, and installs it in a slot. The machine runs
without re-traversal:

```
Interpreter:  every frame = traverse + dispatch + execute
Compiler:     first frame = compile + install
              next frames = execute only (if source unchanged)
              on change   = recompile changed subtree + update slot
```

The compilation model is why GPS applications are fast even with
complex, deeply nested structures. The lowering boundaries cache
aggressively. The slot preserves state across updates. The gen
functions run without dynamic dispatch.

---

## Chapter 61: The Invariant That Holds Everything Together

There is one invariant that, if maintained, guarantees the entire
GPS/mgps system works correctly:

> **Every distinction that matters at runtime is either resolved in
> the code shape, captured in the state shape, or present in the
> payload. Nothing is lost. Nothing is duplicated. Nothing is
> misclassified.**

If you maintain this invariant at every boundary, then:

- Caching is correct (no stale results)
- State management is correct (no leaked resources)
- Hot-swap is correct (minimal disruption)
- Composition is correct (structural products)
- Diagnostics are meaningful (true reuse percentages)

The entire guide you have just read is, ultimately, about how to
maintain this one invariant.

---

## Chapter 62: Summary — The Complete Design Discipline

For every type at every layer:

1. **What is code-shaping?** → Sum types. Different gen functions.
2. **What is state-shaping?** → Goes into `M.state.*` declarations.
   Bucketed if continuous.
3. **What is payload?** → Goes into param. Read by gen at runtime.
4. **What is dead?** → Stripped at the lowering boundary.

For every leaf compiler:

1. Define gen once at module scope.
2. Classify all fields.
3. Call `M.emit(gen, state_decl, param)`.

For every container:

1. Compile children recursively.
2. Call `M.compose(children, body_fn)`.
3. Attach container-level payload.

For every application:

1. Model source as ASDL.
2. Define events as ASDL.
3. Write pure `apply(source, event) → source`.
4. Write lowering pipelines through intermediate IRs.
5. Install in slots. Run in a loop.
6. Let the framework handle caching, state, identity.

That is the complete discipline of designing good ASDL and GPS systems.

---

# Appendices

---

## Appendix A: The State Declaration Algebra Reference

| Declaration                        | Shape String                                    | Alloc Behavior                        |
|------------------------------------|-------------------------------------------------|---------------------------------------|
| `M.state.none()`                   | `"none"`                                        | returns nil                           |
| `M.state.ffi(ctype)`              | `"ffi(ctype_string)"`                           | `ffi.new(ctype)`                      |
| `M.state.value(v)`                | `"value(encoded_v)"`                            | deep copy of v                        |
| `M.state.f64(init)`               | `"f64(init)"`                                   | `ffi.new("double[1]", init)` or number|
| `M.state.table(name, opts)`       | `"table({name=..., shape=...})"`                | `opts.alloc()` or `{}`               |
| `M.state.record(name, fields)`    | `"record(name\|k1:shape1,k2:shape2,...)"`       | table with allocated children         |
| `M.state.product(name, children)` | `"product(name\|shape1,shape2,...)"`             | array of allocated children           |
| `M.state.array(decl, n)`          | `"array(inner_shape,n)"`                        | n copies of inner allocation          |
| `M.state.resource(kind, spec)`    | `"resource(kind\|encoded_spec)"`                 | `ops.alloc(spec)` or `{kind, spec}`  |

---

## Appendix B: The Slot Update Decision Matrix

| Old code_shape | New code_shape | Old state_shape | New state_shape | Action                              |
|----------------|----------------|-----------------|-----------------|-------------------------------------|
| same           | same           | same            | same            | Replace param only                  |
| same           | same           | different       | different       | Retire old state, alloc new state   |
| different      | different      | any             | any             | Retire old state, alloc new, new gen|
| (empty)        | any            | (empty)         | any             | First install: alloc state, set gen |

---

## Appendix C: The Cache Hit Hierarchy

```
M.lower("name", fn) called with input:
    │
    ├── Is input the same interned object as last time? (L1)
    │       YES → return cached result immediately
    │       NO  ↓
    │
    ├── Run fn(input, ...) → emitted result
    │
    ├── Is code_shape in the code cache? (L2)
    │       YES → reuse cached gen
    │       NO  → store gen in code cache
    │
    ├── Is state_shape in the state cache? (L3)
    │       YES → reuse cached state layout
    │       NO  → store state layout in state cache
    │
    └── Return bound result with cached family + fresh param
```

---

## Appendix D: ASDL Syntax Quick Reference

```
# Module
module Name {
    definitions...
}

# Product type (single constructor)
TypeName = (field1_type field1_name, field2_type field2_name) unique?

# Sum type (multiple constructors)
TypeName = Variant1(fields...) unique?
         | Variant2(fields...) unique?
         | Variant3  # no fields = singleton

# Field types
number, string, boolean, table, function, any   # builtins
TypeName                                         # ASDL type reference
TypeName?                                        # optional
TypeName*                                        # list (plain Lua table)

# Attributes (shared fields across all variants)
TypeName = A(fields...) | B(fields...) attributes (shared_fields...)
```

---

## Appendix E: The Full mgps Public API

```lua
-- Schema and context
M.context(verb?)          → T (context)
T:Define(schema_text)     → T
T:use(module)             → T

-- Emission (terminal contract)
M.emit(gen, state_decl, param)  → emitted term

-- State declarations
M.state.none()
M.state.ffi(ctype, opts?)
M.state.value(initial)
M.state.f64(initial?)
M.state.table(name?, opts?)
M.state.record(name, fields)
M.state.product(name, children)
M.state.array(of_decl, n)
M.state.resource(kind, spec, ops?)

-- Leaf helpers
M.leaf(gen, state_fn?, param_fn?)     → function(node, ...) → emitted
M.variant { classify, gen, state, param, code_shape? }  → function(node, ...) → emitted

-- Structural compilation
M.match(arms)                    → function(node, ...) → emitted
M.match(node, arms)              → emitted
M.compose(children, body_fn?)    → emitted
M.lower(name, fn)                → boundary (callable, with .stats() and .reset())

-- Runtime
M.slot()                         → slot
slot:update(compiled)
slot.callback(...)               → result
slot:peek()                      → bound, state
slot:collect()
slot:close()

-- Structural helpers
M.with(node, overrides)          → new interned node
M.is_compiled(v)                 → boolean

-- Diagnostics
M.report(boundaries)             → string

-- App loop
M.app { initial, poll, apply, compile, start?, stop? }
```

---

## Appendix F: Glossary

**ASDL** — Abstract Syntax Description Language. A schema language for
defining algebraic data types with sum types, product types, optional
fields, and list fields.

**Boundary** — A memoized compilation point (`M.lower`). Caches results
by structural identity.

**Code shape** — The identity of the gen function (which code runs).
Determined by sum type variants and conditional gen selection.

**Emit** — The terminal contract: `M.emit(gen, state_decl, param)`.

**Family** — Internal framework concept: a reusable compiled unit with
fixed gen and state layout. Payload is bound separately.

**Fusion** — Composed machines executing without intermediate
materialization. The natural consequence of the `gen(param, state, input)`
shape.

**Gen** — The execution rule. A plain function `(param, state, ...) → result`.

**Interning** — Structural deduplication: same field values → same
object identity. Enabled by `unique` in ASDL.

**Lowering** — A transformation from one ASDL representation to another.

**Param** — Stable payload data. Read by gen, never mutated. Changed
by rebinding, not by mutation.

**Payload** — Synonym for param data. Fields that can change without
affecting code or state identity.

**Slot** — A runtime holder for a compiled machine. Manages state
lifecycle across updates.

**State** — Mutable runtime data owned by a machine. Allocated/released
by the framework based on state declarations.

**State declaration** — A structural description of what state a machine
needs. Built with `M.state.*` functions.

**State shape** — The identity of a state declaration. Two declarations
with the same shape string are considered identical.

**State-shaping** — A field whose value determines state allocation.
Changing it may cause state reallocation.

**Terminal** — The leaf of a lowering pipeline. Produces `M.emit()`
with concrete gen, state_decl, and param.

**Unique** — ASDL modifier that enables structural interning for a type.

---

# Part XI — The Bridging Methodology: A Condensed Reference

This final part distills the entire guide into a practical reference
for the specific challenge of bridging upper representations (user
events, view ASDL) and lower representations (backend IR, terminal
emission).

---

## Step-by-Step: From Domain Concept to Running Machine

### 1. Write the User ASDL

Model what the user thinks about. No positions, no resources, no
backend concerns.

```
module MyDomain {
    Root = (Thing* things) unique
    Thing = Foo(number a, string b) unique
          | Bar(number c, Thing* children) unique
}
```

### 2. Write the Lowest Terminal Gen Functions

What does the machine at the bottom actually do?

```lua
local function foo_gen(param, state, output)
    output:do_foo(param.a_resolved, param.b_processed)
    return output
end
```

### 3. Identify Every Gap Between 1 and 2

Make a table:

```
| User Field | Terminal Need        | Gap                        |
|------------|----------------------|----------------------------|
| a (number) | a_resolved (derived) | needs computation          |
| b (string) | b_processed (string) | needs transformation       |
| (nothing)  | position (x, y)      | needs layout resolution    |
| (nothing)  | resource handle      | needs state allocation     |
| children   | child machines       | needs recursive compilation|
```

### 4. Group Gaps into Layers

Each cluster of related gaps = one intermediate ASDL.

### 5. For Each Layer, Design the ASDL

The intermediate ASDL carries exactly what the next lowering needs.
No more, no less.

### 6. For Each Boundary, Classify Every Field

Use the four-way classification: code-shaping, state-shaping, payload,
dead.

### 7. Write the Lowerings

Each lowering is a structural transformation between ASDL layers.
Methods on the source ASDL types produce target ASDL nodes.

### 8. Write the Leaf Compilers

Terminal-level variants get `:verb()` methods that call `M.emit()`.

### 9. Wire It Up

Create contexts, install modules, define `M.lower()` boundaries,
create slots, write the app loop.

### 10. Verify with Diagnostics

Use `M.report()` to check cache behavior. High node_hits = good
structural sharing. High code/state reuse = good classification.

---

## Quick Reference: Field Classification Decision Tree

```
Field F at boundary B:
│
├─ Does F determine which gen function runs?
│   YES → CODE-SHAPING. Model as sum type variant.
│   NO  ↓
│
├─ Does F determine the size/shape/kind of allocated state?
│   YES → STATE-SHAPING. Put in M.state.*(... { F = value }).
│         If continuous, BUCKET it first.
│   NO  ↓
│
├─ Is F still needed by any downstream consumer at this level?
│   NO  → DEAD. Strip it in this lowering.
│   YES ↓
│
└─ F is PAYLOAD. Put in param.
```

---

## Quick Reference: Layer Design Template

```
Layer N (ASDL module):
  - Purpose: [what this layer represents]
  - Consumed from above: [what upper concepts are resolved here]
  - Produced for below: [what this layer provides to the next]
  - Sum types: [what code-shaping choices exist at this level]
  - Unique: [yes/no and why]

Lowering N→N+1:
  - Method: [verb name, e.g., :place(), :paint_ast(), :draw()]
  - Per-field classification table
  - Container handling: [consumed or surviving?]
```

## Quick Reference: Layer Count Decision Procedure

```
1. List what parents need from children:  [heights, baselines, ...]
2. List what children need from parents:  [max width, flex grow, ...]
3. Count dependency cycles:               [N]
4. Layer count = 1 (flatten) + N (cycle resolution)
5. All N resolution passes traverse the SAME tree
6. The last pass emits flat command arrays
7. Everything after that is linear iteration

   0 cycles:  tree ─── 1 pass ───▶ flat Cmd*
   1 cycle:   tree ─── 2 passes (constraints down, sizes up) ──▶ flat Cmd*
   N cycles:  tree ─── N+1 passes ───▶ flat Cmd*
```

---

## Quick Reference: The Eight Invariants of a Well-Designed GPS System

1. **Every `unique` type is immutable.** Never mutate interned nodes.

2. **Every leaf compiler calls `M.emit()`.** No exceptions. No
   returning raw tables or functions.

3. **Every gen is defined once at module scope.** No closures per call.
   No anonymous functions in emit.

4. **Every state-shaping value is in the state declaration.** If
   changing it needs reallocation, it must be in `M.state.*()`.

5. **Every dead field is stripped at its boundary.** No carrying
   unused data through lowerings.

6. **Every sum type dispatch goes through the framework.** Auto-wired
   by `M.context()` or explicitly via `M.match()`.

7. **Every cross-module lowering is wrapped in `M.lower()`.** This
   ensures caching at structural boundaries.

8. **Recursive structures are flattened immediately.** The first IR
   after a tree/graph is a flat command list. Containment is push/pop.
   Everything downstream is linear iteration.

9. **Layer count is determined by dependency cycles.** Count the
   mutual recursion cycles between parent and child. That number
   is how many intermediate representations (constraint records)
   you need. Total layers = 1 (flatten) + number of cycles.
   The last output is always flat.

---

## Quick Reference: Common Layer Stacks by Domain

### UI Rendering (canonical flattened form)

```
UI ASDL          (widgets, layout spec — TREE)
  ↓ layout walk: measure + place (the ONE recursive pass)
  ↓ outputs flat command lists directly
PaintCmds (flat) + HitCmds (flat)    push/pop for containment
  ↓ one emit() each, flat-loop gen
emit(gen, state, param)              linear iteration
```

### Audio DSP

```
Device ASDL      (signal graph)
  ↓ compile (resolve routing, compute coefficients)
Terminal         (emit per device type)
  ↓
emit(gen, state, param)
```

### Language Compiler

```
AST ASDL         (parsed source)
  ↓ analysis (type check, name resolution)
IR ASDL          (lowered, typed, resolved)
  ↓ codegen
Terminal         (emit per IR instruction)
  ↓
emit(gen, state, param)
```

### Game Entity System

```
World ASDL       (entities with components)
  ↓ compile (per entity type)
Terminal         (update/render per entity kind)
  ↓
emit(gen, state, param)
```

### Document Editor

```
Doc ASDL         (paragraphs, spans, styles)
  ↓ layout (line breaking, pagination)
View ASDL        (positioned runs)
  ↓ backend projection
Paint IR         (glyph runs, decorations)
  ↓ terminal
emit(gen, state, param)
```

---

*End of guide.*

*Written from deep study of the mgps codebase: init.lua (core framework),
MGPS.md (design manifesto), README.md (conceptual background and
architecture), asdl_context.lua (structural interning), asdl_parser.lua
(fused parser), asdl_lexer.lua (GPS lexer machine), lovepaint.lua
(paint terminal), hittest.lua (hit-test terminal), main.lua (full UI
application), grammar.lua (self-hosted grammar compiler), lex.lua
(general lexer toolkit), parse.lua (parser facade), rd.lua (recursive
descent helper).*
