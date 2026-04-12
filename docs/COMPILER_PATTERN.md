# Modeling Interactive Software as Compilers

## Part 1: The Core Insight

### 1.1 The ASDL is a language

The ASDL is not a data format. It is not just a schema. It is not merely a description of what the program stores.

The ASDL is a LANGUAGE.

The source ASDL is the input language of a compiler. The user is the programmer. The UI is the IDE. Every user gesture is a program edit. Every edit produces a new program — a new ASDL tree. The compiler compiles it. The output runs.

Getting the ASDL right means getting the LANGUAGE right. A good language has:
- clear nouns
- clear verbs
- orthogonal features
- completeness
- minimality
- composability

These are the same properties that make a programming language good, because that is what the source ASDL is: a domain-specific programming language whose programs are domain artifacts — songs, documents, spreadsheets, scenes, grammars, tools — and whose compiler produces executable machinery that realizes those artifacts.

The ASDL is the architecture. Everything else is downstream.

### 1.2 Interactive software is a compiler

Every interactive program takes human gestures — clicks, keystrokes, drags, edits, messages, file updates — and turns them into machine behavior — pixels, samples, queries, responses, network bytes, driver calls.

Between intent and execution there is a gap. The user thinks in domain concepts:
- "make this louder"
- "insert a paragraph here"
- "parse this grammar"
- "connect these nodes"

The machine does not think in those terms. It works in registers, memory layouts, loops, buffers, function pointers, and driver callbacks.

Traditional systems bridge that gap at runtime by repeatedly interpreting broad authored structure. Every frame, every callback, every update, they re-answer some version of:

> what does this node mean, really?

The compiler pattern bridges the gap earlier. It treats the program as authored source, compiles that source through memoized boundaries into progressively narrower forms, and produces a flat executable artifact that runs without rediscovering source-level meaning.

That is the core claim:

> Interactive software is best understood as a live compiler from authored intent to executable flat commands.

### 1.3 The gap has layers, and those layers are your boundaries

The gap between "what the user said" and "what the runtime executes" is never one step. There are always intermediate levels of knowledge.

```text
User intent:      "I want a track with a muted kick drum"
    ↓
Domain vocabulary: TrackRow(index=1, track=Track("Kick", mute=true, ...))
    ↓
Layout vocabulary: Column(spacing=0, [Rect("header", 200, 40, ...), ...])
    ↓
Flat commands:     [Rect(0,0,200,40,bg), Text(4,12,1,fg,"Kick"), PushClip(...), ...]
    ↓
Execution:         for i = 1, #cmds do paint(cmds[i]) end
```

Each layer consumes knowledge. Each boundary exists because some real decision is being resolved.

The question "how many layers should I have?" is answered by:

> how many distinct levels of knowledge resolution does this domain actually have?

Not more. Not fewer.

### 1.4 The source phase is still the most important

The source phase — the first phase, the one the user edits — determines everything.

It is the input language of the compiler. Every later phase is derived from it. Every boundary consumes knowledge from it. Every flat command array is downstream of it.

If the source phase is wrong — wrong nouns, wrong granularity, wrong containment, wrong variants, wrong identity boundaries — every lower phase inherits the mistake. The entire pipeline compiles the wrong thing correctly.

Getting the source phase right requires answering:

> what are the domain nouns?

Not implementation nouns:
- buffer
- callback
- registry
- renderer state
- service container

But user nouns:
- track
- clip
- parameter
- rule
- token
- widget
- cell
- scene

### 1.5 The hard part

The framework primitives — ASDL, phase, one, with, for-loop execution — are tools. They do not tell you what to model. They do not tell you what the source language should be. They do not tell you where knowledge is consumed, what lower forms are honest, or how many layers you actually need.

That is the hard part.

And it must be done correctly, because the ASDL is the architecture. A wrong type at the source phase propagates through every boundary, every layout computation, every flat command, and every for-loop. The cost compounds.

This document is about making those design decisions explicitly and correctly.

---

## Part 2: The Five Concepts and the Live Loop

The pattern is built from five concepts. They are small enough to state simply and strong enough to organize an entire interactive system.

### 2.1 Source ASDL

This is what the program IS: the user-authored, user-visible, persistent model of the domain.

In a music tool: tracks, clips, devices, routings, parameters.
In a text editor: document, blocks, spans, cursors, selections.
In a parser tool: grammar, token, rule, product.
In a UI system: widgets, layout declarations, style declarations.

The source ASDL is not runtime scaffolding. It is not a cache of derived facts. It is not a bag of backend conveniences. It is the authored program.

It must answer:
- what did the user author?
- what survives save/load?
- what does undo restore?
- what exists as a user-visible thing?
- which choices are independent authored choices rather than derived consequences?

### 2.2 Event ASDL

This is what can HAPPEN to the program.

Instead of treating interaction as arbitrary callbacks, the pattern models input as a language too. Examples:
- pointer moved
- key pressed
- node inserted
- selection changed
- parameter edited
- file opened
- transport started

Events are architectural because they define how the source program evolves.

### 2.3 Apply

The pure reducer:

```text
Apply : (state, event) → state
```

Apply does not mutate the world in place. It takes the current source program and an event and returns the next source program.

That purity is what makes:
- undo simple — store the previous root node
- structural sharing possible — unchanged subtrees keep identity
- memoization coherent — same input → same output → skip
- tests trivial — construct input, call apply, assert output

### 2.4 Boundaries (phase)

A boundary is a memoized transformation from one representation to another.

Publicly, pvm has one boundary concept: **phase**.

**phase (handlers form)** — type-dispatched streaming boundary. Each sum type variant gets its own handler. The boundary dispatches by the node's type, wraps the handler's output in a recording triplet, and caches the result on first full drain.

```lua
local widget_to_cmds = pvm.phase("ui", {
    [T.App.TrackRow]  = function(self) ... return pvm.children(widget_to_cmds, self.rows) end,
    [T.App.Button]    = function(self) ... return pvm.once(Rct(self.tag, ...)) end,
    [T.App.Meter]     = function(self) ... return pvm.once(Rct(self.tag, ...)) end,
})

for _, cmd in widget_to_cmds(root) do paint(cmd) end
```

**phase (function form)** — scalar boundary encoded as a lazy single-element stream.

```lua
local solve_phase = pvm.phase("solve", function(root)
    return layout_solver(root)
end)

local solved = pvm.one(solve_phase(root))
```

`pvm.lower(name, fn)` remains available as compatibility sugar for the second form.

A boundary consumes unresolved knowledge. A real boundary answers a real question:
- what commands does this widget produce? (phase)
- what solved layout does this tree require? (scalar phase + `pvm.one`)
- what does this name resolve to? (phase)

A boundary is not just "another pass." It is a reduction of ambiguity.

### 2.5 Flat execution

The final output of the compilation pipeline is not a "machine" in the abstract. It is a concrete flat array of command nodes:

```lua
cmds = { VRect("bg", 0, 0, 800, 600, bg_color),
         VPushClip(0, 0, 220, 500),
         VRect("row:1", 0, 0, 220, 48, row_bg),
         VText("name:1", 4, 14, 0, 0, 1, fg, "Kick"),
         VPopClip,
         ... }
```

Execution is a for-loop:

```lua
for i = 1, #cmds do
    local cmd = cmds[i]
    local k = cmd.kind
    if k == K_RECT then
        love.graphics.setColor(rgba8_to_love(cmd.rgba8))
        love.graphics.rectangle("fill", cmd.x, cmd.y, cmd.w, cmd.h)
    elseif k == K_TEXT then
        love.graphics.setColor(rgba8_to_love(cmd.rgba8))
        love.graphics.print(cmd.text, cmd.x, cmd.y)
    elseif k == K_PUSH_CLIP then
        love.graphics.setScissor(cmd.x, cmd.y, cmd.w, cmd.h)
    elseif k == K_POP_CLIP then
        love.graphics.setScissor()
    end
end
```

There is no installation step. No slot. No retirement. No swap. The for-loop IS the execution. The Cmd array IS the installed artifact.

Recompilation is: produce a new Cmd array. The old one is garbage-collected. The new one is iterated.

This is simpler than it sounds, and the simplicity is the point.

### 2.6 The live loop

Put together, those five concepts yield the live loop:

```text
poll → apply → compile → execute
```

**poll** — read an input from the outside world (mouse, keyboard, timer, network)

**apply** — use the pure reducer to derive the next source program

**compile** — re-run memoized boundaries for affected subtrees only, producing flat commands

**execute** — run the for-loop over the current command array

This is incremental compilation as a direct consequence of architecture, not a bolt-on invalidation subsystem.

### 2.7 Hot swap is the natural execution story

The loop makes hot swap natural rather than exotic:
- old source compiled to a Cmd array
- a new event changes the source
- affected subtrees recompile (phase caches skip unchanged parts; scalar boundaries use phase+one)
- a new Cmd array is produced
- the for-loop runs the new array

There is no need for a second shadow architecture called "live objects" that must somehow be reconciled with compilation output. The Cmd array is the live thing. When the source changes, a new Cmd array replaces it.

### 2.8 The loop is continuous, not one-shot

This is not an ahead-of-time compiler that runs once and disappears. The program stays alive. The user keeps editing. The system keeps repeating:
- receive event
- derive next source
- recompile affected parts
- run the result

That is why the pattern fits interactive software so well.

### 2.9 Multiple outputs from one source

The same source program may feed multiple for-loops:

```lua
-- Same View.Cmd array, two consumers:
for i = 1, #cmds do paint(cmds[i]) end          -- painting
for i = #cmds, 1, -1 do hit_test(cmds[i]) end   -- hit testing (reverse z-order)
```

Or different phase boundaries producing different output arrays:

```lua
local paint_cmds = compile_paint(source)   -- phase: source → paint commands
local hit_cmds   = compile_hit(source)     -- phase: source → hit regions
local a11y_tree  = compile_a11y(source)    -- phase: source → accessibility tree
```

These are not special cases. They are ordinary outputs of the same compiler architecture. Each is a separate memoized boundary. Each caches independently. Editing the source recompiles only the affected subtrees for each output.

### 2.10 Why this is stronger than "just use immutable data"

Many systems use immutable data and still remain interpreter-shaped. They still:
- walk broad generic trees every frame
- branch on wide variants in hot paths
- bolt on caches later
- mix code generation with runtime object graphs

The compiler pattern is stronger. Its real claim is:

> the program should be modeled as source, compiled through memoized boundaries into flat command arrays, and then executed with a for-loop.

That is much stronger than "use immutable data."

Immutable data is necessary (for structural sharing and memoization). But it is not sufficient. The pattern also requires: layers (each boundary resolves a real question), flattening (the output is a flat array, not a tree), and memoized boundaries (unchanged subtrees are skipped).

---

## Part 3: The Three Levels — Compilation, Codegen, and Execution

The pattern stays coherent because it distinguishes three different kinds of work:

1. work that decides what the flat commands should be
2. work that makes that decision fast (code generation)
3. work that runs the flat commands

### 3.1 The compilation level

The compilation level is where the system reasons about the authored program.

It includes:
- Source ASDL and its constructors
- Event ASDL
- Apply
- phase boundaries (type-dispatched recording-triplet transforms)
- scalar phase boundaries (`pvm.phase(name, fn)` + `pvm.one`) for single-value transforms
- layout computation
- structural error collection

Its characteristic properties are:
- pure (no side effects)
- structural (ASDL nodes in, ASDL nodes out)
- memoized at boundaries (same input → cached output)
- testable by constructor + assertion

This is where questions are answered:
- what layout nodes does this widget produce?
- what positioned commands does this layout tree emit?
- what does this reference resolve to?

### 3.2 The codegen level

The codegen level is where the compilation primitives themselves are made fast.

It includes:
- code-generated ASDL constructors (unrolled interning tries, no loops or `select()`)
- hygienic codegen via quote.lua for custom hot-path generation

Its characteristic properties are:
- happens once at definition time, not per frame
- produces inspectable source strings
- uses loadstring to compile specialized functions
- the generated code IS what LuaJIT traces

Note: `pvm.phase` dispatch uses a direct `getmetatable` table lookup — no
loadstring, no generated source. The dispatch is simple and predictable.
Code generation applies where it matters most: ASDL constructor interning
(unrolled per field count) and any custom hot-path kernels you author with
quote.lua.

This is the realization layer. In older descriptions of this pattern, realization was a large conceptual architecture involving "proto languages," "artifact families," "binding schemas," "install catalogs," and "host contracts." Those abstractions were needed when the target was native code via LLVM (Terra) or bytecode templates via string.dump.

In pvm, realization is 148 lines of quote.lua for ASDL constructor codegen. The insight is preserved — machine meaning must become executable form — but the mechanism is direct: `pvm.phase` wraps handlers in recording triplets, and `pvm.drain` / `pvm.each` pulls through them.

### 3.3 The execution level

The execution level is where the flat command array actually runs.

It includes:
- a for-loop over the Cmd array (painting)
- a reverse for-loop over the same array (hit testing)
- the graphics backend (Love2D, SDL, GPU)
- push/pop state management (clip stack, transform stack)

Its characteristic properties are:
- imperative (it draws pixels, fills buffers, issues driver calls)
- linear (one for-loop, no recursion, no tree walking)
- does not rediscover source semantics
- should be narrow, monomorphic, and predictable

The execution level is not where the app decides what exists. It is where the compiled commands do the work they were specialized to do.

### 3.4 Why this split matters

If compilation work leaks downward into execution, you get bad symptoms:
- runtime branching on wide source variants in the for-loop
- repeated name or ID lookup in hot paths
- strings being interpreted where sum types should have decided
- the for-loop doing layout work that should already be resolved

If execution concerns leak upward into compilation, you get different bad symptoms:
- source ASDL polluted with pixel positions or resource handles
- domain types shaped by rendering concerns
- user vocabulary replaced by backend vocabulary
- save/load truth corrupted by implementation details

The split exists to prevent those failures.

### 3.5 Codegen IS realization

Earlier descriptions of this pattern described a rich "proto language" layer between compilation and execution. That layer handled:
- artifact families and template families
- binding schemas and install plans
- bytecode blobs and source kernels
- install catalogs and artifact keys
- host contracts for different execution environments

This was architecturally honest for systems targeting native code via LLVM or bytecode templates via string.dump. Those systems really did need a separate lower language for installable artifacts.

In pvm, the entire realization story is:

1. **phase** dispatches by `getmetatable(node)` — a plain table lookup. On miss, the handler's triplet is wrapped in a recording that commits to cache on full drain. No loadstring. No generated dispatch.

2. **scalar phase** (`pvm.phase(name, fn)`) wraps a function result as a single lazy element and caches it by identity via the same recording machinery.

3. **ASDL constructors** generate interning functions via loadstring. Unrolled trie walks with no loops, no `select()`. This IS the codegen-level work.

4. **quote.lua** (148 lines) provides hygienic codegen: `val()` captures upvalues, `sym()` creates fresh names, `compile()` does the loadstring. Used for constructors and custom hot-path kernels.

That's it. No proto language. No artifact families. No binding schemas. No install catalogs. The flat Cmd array IS the installed artifact. Recompilation IS producing a new Cmd array (incrementally, only for changed subtrees).

The insight from the old proto/realization vocabulary is preserved in a single sentence:

> Machine meaning must become executable form. In pvm, that form is a recording-triplet phase boundary, executed by native `for` (or helper terminals like `pvm.each`/`pvm.drain`).

### 3.6 When the three levels compress

Not every application needs all three levels to be visible:

**Small apps** (calculator, simple tool): Compilation + execution only. No codegen needed. `pvm.phase` (handlers or function form) works without code generation — plain metatable lookups and closure caches.

**Medium apps** (track editor, document editor): ASDL constructor codegen for hot interning. The generated trie-walk functions present LuaJIT with unrolled, monomorphic code to trace.

**Large apps** (DAW, game engine, IDE): quote.lua for custom hot-path generation. Hand-crafted codegen for specialized inner loops, shader compilation, audio kernel generation.

### 3.7 Error handling by level

At the compilation level, errors are structural:
- invalid authored combination
- missing reference
- unknown variant

At the codegen level, errors are generation-time:
- loadstring parse failure (malformed generated code)
- type mismatch in generated dispatch

At the execution level, errors are operational:
- driver failure
- device failure
- resource exhaustion

Mixing these error families leads to bad design.

### 3.8 Testing by level

Compilation-level tests look like:
- construct ASDL input
- call phase / one / apply (or `pvm.lower` compatibility)
- assert output

Codegen-level tests look like:
- define types + handlers
- inspect generated source string
- verify dispatch correctness

Execution-level tests may involve:
- smoke tests with mock backends
- benchmarks
- frame timing

All three matter, but they are not the same kind of test.

---

## Part 4: The Flatten Theorem

This is the single most important structural insight in the pattern. Everything about the execution model follows from it.

### 4.1 Recursive structures are expensive

A tree costs you at every level:

1. **Construction**: Allocating/interning nodes at every nesting level. An N-leaf tree with depth D creates O(N+D) intermediate nodes.

2. **Traversal**: Every boundary that walks the tree is O(N) recursive calls. Method dispatch at every node. Stack frames. Cache-unfriendly pointer chasing.

3. **Repetition**: If you have Tree → Tree → Tree → for-loop, you are paying the recursive traversal cost THREE times before anything runs linearly.

4. **JIT hostility**: Recursive dispatch through heterogeneous node types produces polymorphic call sites. LuaJIT cannot trace through them. The trace compiler falls back to the interpreter.

Consider a naive UI pipeline:

```text
UI ASDL (tree)
  → recursive :view()              ← traversal #1
    → View ASDL (tree)             ← still a tree!
      → recursive :paint_ast()     ← traversal #2
        → Paint ASDL (tree)        ← still a tree!
          → recursive :draw()      ← traversal #3
            → recursive compose()  ← traversal #4
              → nested gen calls   ← execution is nested calls
```

Four tree walks. The tree shape persists all the way to execution.

### 4.2 The canonical form: tree in, flat out, for-loop forever

The flatten theorem says:

> Any tree of typed nodes can be faithfully represented as a flat array of commands where containment is expressed by push/pop marker pairs.

```text
Tree:                           Flat:
  Clip(0,0,800,600,             PushClip(0,0,800,600)
    Transform(10,20,              PushTransform(10,20)
      Rect(0,0,100,30,0xff)        Rect(0,0,100,30,0xff)
      Text(0,0,1,0xff,"hi")        Text(0,0,1,0xff,"hi")
    )                             PopTransform
  )                             PopClip
```

The flat list is just an array. Iterating it is a single `for` loop. No recursion. No method dispatch. No pointer chasing. Cache-friendly linear memory access.

Containment is expressed by push/pop pairs, not by nesting. The depth information is implicit in the push/pop stack — it exists as runtime state of the iterator, not in the structure of the data.

### 4.3 State is always a stack

This follows directly from flattening.

When you flatten a tree, every container node becomes a push/pop pair. The only state the for-loop needs to maintain is: what containers are currently open? That is a stack.

```lua
-- The for-loop maintains stacks:
local clip_stack = {}
local transform_stack = {}

for i = 1, #cmds do
    local cmd = cmds[i]
    if cmd.kind == K_PUSH_CLIP then
        push(clip_stack, {cmd.x, cmd.y, cmd.w, cmd.h})
        love.graphics.setScissor(cmd.x, cmd.y, cmd.w, cmd.h)
    elseif cmd.kind == K_POP_CLIP then
        pop(clip_stack)
        restore_scissor(clip_stack)
    elseif cmd.kind == K_PUSH_TX then
        push(transform_stack, {cmd.tx, cmd.ty})
        love.graphics.translate(cmd.tx, cmd.ty)
    elseif cmd.kind == K_POP_TX then
        pop(transform_stack)
        restore_transform(transform_stack)
    elseif cmd.kind == K_RECT then
        -- draw using current clip and transform
    end
end
```

The stack is the ONLY state shape for structural traversal. This is not a design choice — it is a mathematical consequence of flattening a tree. Containment is nesting. Nesting linearizes to push/pop. Push/pop is a stack.

This means: if you find yourself needing complex mutable state during execution, either you haven't flattened far enough (the tree is still present), or you have a genuine runtime concern that doesn't come from the authored structure (physics simulation, audio delay history, etc.).

### 4.4 Each recursion class = one ASDL layer

The rule that tells you how many layers you need:

> Every level of structural recursion in your domain requires one ASDL layer. Each layer's output is consumed by the next layer's phase boundary (handlers or scalar function form). The final layer is flat.

In the track editor (ui5):

```text
Layer 0: App.Widget  — structural recursion (TrackList contains TrackRow)
Layer 1: UI.Node     — structural recursion (Column contains children)
Layer 2: View.Cmd    — FLAT (no recursion, just an array)
```

App.Widget has structural recursion: TrackList contains TrackRows, Inspector contains Buttons and Sliders. This recursion is consumed by the `:ui()` phase boundary, which produces UI.Nodes.

UI.Node has structural recursion: Column contains children, Padding wraps a child. This recursion is consumed by the `:place()` layout walk, which produces flat View.Cmd arrays.

View.Cmd has NO recursion. It is a flat array of uniform command records. A for-loop iterates it.

The rule is: **count the recursive types, that's your layer count, plus one flat layer at the bottom.**

### 4.5 The uniform command type

This is the crucial implementation insight that makes flattening fast on modern JIT compilers.

The View.Cmd type in ui5 is:

```asdl
module View {
    Kind = Rect | Text | PushClip | PopClip | PushTransform | PopTransform

    Cmd = (View.Kind kind, string htag,
           number x, number y, number w, number h,
           number rgba8, number font_id, string text,
           number tx, number ty) unique
}
```

ONE product type with a Kind singleton tag. Not a sum type with different fields per variant. ONE table shape. ONE metatable. All fields always present (unused fields set to 0 or "").

Why?

Because LuaJIT traces loops. When it traces a loop, it records the metatables of the objects it encounters. If every iteration sees the same metatable, it compiles one trace and runs it for every element. If different iterations see different metatables, the trace aborts and falls back to the interpreter.

A sum type with variants (Rect, Text, Clip) means different metatables per variant. A for-loop over mixed variants = trace aborts = slow.

A uniform product type with a Kind field means one metatable for ALL commands. A for-loop over uniform Cmds = one trace = golden bytecode.

The Kind field is a singleton sum type — a table with no fields, just identity. Comparing `cmd.kind == K_RECT` is a pointer comparison, not a string comparison. The JIT sees it as an integer comparison after constant folding.

This design means: unused fields waste memory (a Rect command carries font_id=0, text=""). That is the correct trade-off. The memory cost is negligible. The JIT-friendliness cost of polymorphic metatables is catastrophic.

### 4.6 Mutual recursion materializes as passes

Sometimes a single tree walk is not enough. This happens when parents need information from children AND children need information from parents:

```text
Parent asks child:  "how tall are you?"
Child (text) says:  "depends — how wide am I allowed to be?"
Parent says:        "depends — how wide are all my children."
```

That is a dependency cycle. A single top-down pass does not know child heights. A single bottom-up pass does not know parent width constraints. You need both directions.

The rule:

> Count the dependency cycles between parent and child. Each cycle requires one additional pass over the same tree. Total passes = 1 + number of cycles. All passes traverse the SAME tree. The output of the LAST pass is flat.

| Cycles | Passes | Example |
|--------|--------|---------|
| 0 | 1 | Static layout, fixed sizes |
| 1 | 2 | Text wrap + flex (constraints down, sizes up) |
| 2 | 3 | Intrinsic sizing + flex + wrap |
| N | N+1 | Full CSS (many cycles) |

In ui5, text wrapping creates one cycle:
- Column needs child heights to compute total height
- Text child needs available width (from Column) to compute wrapped height

The solution: a cached measure pass. `cached_measure(node, max_width)` resolves the cycle by memoizing on (node identity × constraint width). The place pass then reads cached measurements.

Two passes, same tree, flat output. No intermediate tree layer needed.

### 4.7 Worked example: finding cycles in a UI layout system from scratch

You are designing a UI from nothing. How do you know how many passes you need?

**Step 1: List your layout features.**

```text
1. Fixed-size rectangles (Rect with explicit w, h)
2. Text with word wrap (width affects height)
3. Columns (stack vertically, spacing)
4. Rows (stack horizontally, spacing)
5. Padding (insets around a child)
6. Flex grow (distribute leftover space)
7. Min/max width constraints on flex children
```

**Step 2: For each feature, write what flows down and what flows up.**

```text
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

```text
Column layout:
  Column has available width W.
  │
  ├─▶ Pass available width W to each child
  │     │
  │     ▼
  │   Child measures itself given W
  │   • Fixed rect: returns (w, h) — ignores W
  │   • Text: wraps within W → returns (actual_w, wrapped_h)
  │   • Padding: subtracts insets from W, asks inner child, adds back
  │     │
  │     ▼
  ├─◀ Child returns (child_w, child_h)
  │
  Column sums child heights + spacing → returns (max_child_w, total_h)
```

Data flows down (W) then up (sizes). **No cycle.** One pass suffices. The parent knows W before it asks children.

Now add feature 6 — **flex grow**:

```text
Row with flex-grow children:
  Row has available width W.
  │
  ├─▶ Ask each child: "what is your natural width?"
  │   Child returns natural_w
  ├─◀
  │
  Row computes: leftover = W - sum(natural_widths)
  Row distributes leftover by grow factor
  │
  ├─▶ Tell each child: "your assigned width is X"
  │   Child re-measures within X (text re-wraps → new height)
  ├─◀ Child returns (X, new_h)
  │
  Row returns (W, max(new_heights))
```

This requires **two traversals of the children**: once to collect natural sizes, once to assign and resolve. That's one cycle = two passes.

Now add feature 7 — **min/max constraints on flex**:

```text
Phase B distributes leftover →
  child 3 gets 400px, but max-width is 200px →
  child 3 clamped to 200px →
  200px unassigned → redistribute to unclamped children →
  child 1 might now hit ITS max-width → iterate until stable
```

Genuine cycle: redistribution depends on which children clamped, clamping depends on distribution. Another pass.

**Step 4: Build the cycle count table.**

```text
Design level         Features                        Cycles  Passes
─────────────────────────────────────────────────────────────────────
① Minimal           fixed + text + col/row + pad     0       1
② Flex              add grow/shrink                  1       2
③ Constrained flex  add min/max on flex              2       3
④ Full CSS-like     add %, intrinsic, baseline       3–4     4–5
```

**Step 5: Choose your design level.** You are not forced to implement full CSS. Level ① covers 90% of real UI layouts.

**Step 6: Implement as passes over the same tree.** All passes traverse the SAME UI tree. No intermediate tree is materialized. The output of the LAST pass is flat commands.

### 4.8 When NOT to flatten

The user's authoring ASDL should remain a tree. Users think in containment: "this column contains these rows, each row contains these widgets." That is correct and natural for authoring.

The rule is about **the IR between authoring and execution**, not about the authoring language itself.

Similarly, layout-internal structure (UI.Node) remains a tree because layout computation is inherently recursive (parent sizes depend on child sizes). The tree is consumed by layout, and the output is flat commands.

The discipline is:
- **Source ASDL**: tree (users author containment)
- **Layout ASDL**: tree (layout resolves containment)
- **Command output**: flat (execution iterates linearly)

Tree in. Flat out. For-loop forever after.

---

## Part 5: Designing the ASDL

Before the step-by-step method, it helps to make the architectural vocabulary explicit.

### 5.0 The minimal architectural vocabulary

#### 5.0.1 The formal minimum

At the deepest level, most useful ASDL is built from a very small algebra:

- **product** — a record with named fields
- **sum** — a tagged choice / variant / enum
- **sequence** — zero or more children (`*` in ASDL)
- **reference** — a stable cross-link by ID
- **identity** — stable naming of independently editable things

This is the mathematical minimum. But it is too low-level to guide architecture by itself.

A note on **reference**: reference belongs in the formal minimum, but should be treated with caution. A reference is never free. It introduces non-local dependency, validation burden, phase-ordering pressure, and lookup needs. Containment is the calm default. Reference is a controlled escape from the tree.

The right stance:
- containment first
- references only for real authored cross-links
- references represented as stable IDs, never live object pointers
- references resolved in explicit phases as early as possible

#### 5.0.2 The architectural minimum

A more useful working vocabulary:

- **entity** — a persistent user-visible thing with stable identity
- **variant** — a real domain "or" (a sum type)
- **projection** — a derived ASDL view of another ASDL
- **spine** — a shared structural alignment space used by several consumers
- **facet** — one orthogonal semantic plane aligned to a shared spine

These are not new formal type constructors. They are recurring architectural roles built from products, sums, sequences, and references.

#### 5.0.3 Entity

An entity is a persistent user-visible thing with stable identity. The user can point to it and say "that one."

Examples: track, clip, device, document, block, cell, layer, node.

An entity is usually a product type with a stable ID, marked `unique`.

#### 5.0.4 Variant

A variant is a real domain "or."

Examples: a clip is audio OR MIDI. A selection is cursor OR range. A filter is lowpass OR highpass.

A variant is a sum type. Each option has its own fields. This is better than string tags because it gives exhaustiveness, variant-specific payloads, and explicit domain closure.

The smell to watch for: `kind: string` where `Kind = A | B | C` belongs.

#### 5.0.5 Projection

A projection is a derived ASDL view of another ASDL.

Examples: source → view, document → outline, graph → render tree.

Projection matters because the source ASDL models the user's world, not every consumer's world. A view pipeline needs positions, colors, and hit regions. Those do not belong in the source.

#### 5.0.6 Spine and facet

A spine is a shared structural alignment space. A facet is one orthogonal semantic plane aligned to that spine.

These become relevant in larger systems where several downstream consumers need the same structural alignment (a header spine) but different semantic facts (layout facet, paint facet, hit facet, accessibility facet).

For smaller systems (most pvm apps), the uniform Cmd type serves as both spine and facet — one structure carrying everything. The spine/facet split becomes valuable when the "everything" gets too wide and unrelated edits start coupling.

### 5.1 Step 1: List the nouns

Open the program you're modeling (or imagine it). Look at every element the user can see and interact with. Write down every noun.

For a DAW:
```text
project, track, clip, audio clip, MIDI clip, note, device,
effect, instrument, parameter, knob, fader, slider, automation,
breakpoint, send, bus, tempo, time signature, marker, transport,
playhead, loop region, selection, solo, mute, volume, pan, meter
```

For a text editor:
```text
document, paragraph, line, character, word, selection, cursor,
font, size, weight, color, style, span, heading, list, link,
image, table, cell, row, column, page, margin, indent, bookmark
```

For a spreadsheet:
```text
workbook, sheet, cell, row, column, range, formula, reference,
function call, value, number, string, boolean, format, border,
fill, font, chart, axis, series, filter, sort, pivot table
```

### 5.2 Step 2: Find the identity nouns (entities)

Not all nouns are equal. Some are THINGS with identity. Others are PROPERTIES of things.

Identity test: "Can the user point to this and say 'that one'?"

```text
DAW:
    IDENTITY (user can point to it):
        project, track, clip, device, parameter, send,
        automation curve, modulator, scene

    PROPERTY (attribute of an identity noun):
        volume, pan, mute, solo, frequency, Q,
        tempo value, time signature
```

Identity nouns become ASDL records. Property nouns become fields ON those records.

### 5.3 Step 3: Find the sum types (variants)

Look for the word "or" in your domain:

```text
DAW:
    A clip is an audio clip OR a MIDI clip.
    A device is a native device OR a layer device OR a selector.
    A parameter source is static OR automated OR modulated.
    A track is an audio track OR an instrument track OR a group.

Text editor:
    A block is a paragraph OR a heading OR a list OR a code block.
    A span is plain OR bold OR italic OR link OR code.
    A selection is a cursor (collapsed) OR a range.

Spreadsheet:
    A cell value is number OR string OR boolean OR formula OR empty.
    A formula term is literal OR cell ref OR range ref OR function call.
    A chart type is bar OR line OR scatter OR pie.
```

Each "or" becomes an ASDL sum type. Each option becomes a variant.

### 5.4 Step 4: Find the containment hierarchy

Domain objects contain other domain objects. The containment forms a tree. This tree IS the ASDL structure.

```text
DAW:
    Project
    └── Track*
        ├── DeviceChain → Device*
        │                  └── Parameter*
        ├── Clip*
        ├── Send*
        └── AutomationLane* → Breakpoint*

Text editor:
    Document
    └── Block*
        ├── Paragraph → Span*
        ├── Heading → Span*, level
        ├── CodeBlock → text, language
        └── List → ListItem* → Block* (recursive!)
```

Containment is the default structural relation. If a relationship is really ownership, model ownership. If it is a non-owning cross-link, represent it as a stable ID and resolve it in a later boundary.

### 5.5 Step 5: Find the coupling points

Coupling points are places where two independent subtrees need information from each other. These determine boundary ordering and layer count.

```text
DAW:
    Send ←→ Track:
        A send references another track by ID.
        → sends must be resolved AFTER all tracks are defined.

    Automation ←→ Parameter:
        A parameter's value at time T depends on automation.
        → automation must be resolved AFTER parameters are defined.

Text editor:
    Text ←→ Layout:
        Text wrapping depends on available width (from layout).
        Layout height depends on text measurement (from shaping).
        → must be resolved in the SAME pass (one cycle).

Spreadsheet:
    Formula ←→ Cell:
        A formula references other cells.
        Those cells might contain formulas referencing this cell.
        → dependency analysis is its own phase (topological sort).
```

Each coupling point tells you something about boundary ordering. If A depends on B and B depends on A, they must be resolved in the same pass. If A depends on B but not vice versa, B is resolved first.

### 5.6 Step 6: Define the phases / layers

Phases are ordered by knowledge. Each phase knows everything the previous phase knew, plus the decisions it resolved.

The method:
1. Start with the source phase (the user's vocabulary)
2. List all the decisions that need to be resolved
3. Order them by dependency
4. Group decisions that must happen together (coupling)
5. Each group becomes a phase boundary (streaming handlers or scalar function form)

The counting rule from §4.6 tells you how many layers:
- Count recursive types → that many layers + one flat layer
- Count dependency cycles → that many additional passes

```text
DAW phases:
    Editor (source): all user vocabulary, all sum types
    Resolved: IDs stable, cross-references validated
    Scheduled: buffer slots assigned, execution order determined
    Compiled: flat command arrays for audio + view

Text editor phases:
    Editor (source): blocks with spans, user vocabulary
    Laid: positions computed, text shaped, measurements known
    Compiled: flat command arrays for rendering + hit-testing
```

Each transition has a VERB: lower, resolve, schedule, compile, layout. The verb describes what knowledge is consumed. If you cannot name the verb, the boundary should not exist.

### 5.7 Test the source ASDL

Once the source phase is drafted, test it before writing a single boundary function.

#### The save/load test

Serialize your source ASDL to JSON. Load it back. Is every user-visible aspect restored?

If something is lost — a UI layout preference, a device ordering, a selection state — the source ASDL is missing a field.

Rule: if the user would be surprised that something changed after save/load, it belongs in the source ASDL.

#### The undo test

The user performs an edit. Then undoes it. The source ASDL should be identical to the pre-edit state — and because ASDL `unique` gives structural identity, "identical" means the SAME Lua object. Every memoized boundary returns the cached result instantly. The entire UI reverts with zero recompilation.

If undo requires special handling, the source ASDL is wrong. Undo should be: replace the current root with the previous root. That's it.

#### The collaboration test

Two users edit the same project simultaneously. They edit different things. Can their edits be merged?

ASDL trees are VALUES. Merging two value-trees is structural: for each node, take the newer version. If both users edited the same node, conflict. This works if each identity noun has a stable ID and edits produce new nodes with structural sharing.

#### The completeness test

For each sum type, ask: "Can the user create an instance of every variant?" If a variant is impossible to reach through the UI, it shouldn't exist. If a user action creates something that doesn't fit any variant, a variant is missing.

#### The minimality test

For each field, ask: "Is there a user action that changes ONLY this field?" If yes, the field is at the right granularity. If no — if this field always changes with another — they might be one field, or one might be derived.

```text
Track:
    volume_db — user drags fader → changes only this → CORRECT
    pan       — user drags pan knob → changes only this → CORRECT

Biquad:
    freq — user turns freq knob → changes only this → CORRECT
    coefficients (b0, b1, b2, a1, a2)?
    → DERIVED from freq and q. Not source. Belongs in a later phase.
```

Rule: if a value is derived from other values in the ASDL, it belongs in a later phase.

#### The orthogonality test

For each pair of fields, ask: "Can these vary independently?" If yes, orthogonal — good. If not, you may have a hidden dependency that should be a sum type.

```text
Track: volume_db and pan
    → Can volume be -6dB with pan center? Yes.
    → Can volume be 0dB with pan hard left? Yes.
    → ORTHOGONAL. Good.

Device: kind and params
    → Can a Biquad have gain params? No.
    → NOT orthogonal. kind constrains params.
    → This is correct IF kind is a sum type with per-variant fields.
```

#### The testing test

For each function you write, ask: "Can I test this with nothing but an ASDL constructor and an assertion?"

If you need mocks, fixtures, setup, teardown, or specific ordering of prior calls — the function has hidden dependencies, which means the ASDL is incomplete or the function is impure.

```text
"I need a context argument"
    → The node doesn't carry everything the function needs.
      Either the ASDL is missing a field, or a prior phase
      should have attached the needed data.

"I need to look up another node by ID"
    → A resolve phase should have already linked the reference.

"I need a mutable accumulator"
    → A prior phase should make each node self-contained.
```

The rule: **every function is testable with one constructor call and one assertion.** If it needs more, fix the ASDL, not the test.

### 5.8 Design for incrementality

The memoized boundary cache is the incremental compilation system. Its effectiveness depends on ASDL structure.

#### Structural sharing

When the user edits one track, the other tracks are unchanged. If each Track is ASDL `unique`, the unchanged tracks are the SAME Lua objects. The boundary cache hits on them instantly.

This requires that edits produce new ASDL nodes with structural sharing:

```lua
-- User changes Track 2's volume
-- WRONG (deep copy — destroys caching):
local new_project = deep_copy(old_project)
new_project.tracks[2].volume_db = -3
-- Every track is a new object. Every cache lookup misses.

-- RIGHT (structural sharing — preserves caching):
local new_track = pvm.with(old_track, { volume_db = -3 })
-- Only Track 2 is new. Tracks 1, 3, ... are the SAME objects.
-- Boundary cache hits on every unchanged track.
```

#### The granularity tradeoff

Finer granularity = more cache hits, but more boundary lookups.
Coarser granularity = fewer lookups, but more cache misses.

```text
TOO FINE (per-pixel boundary): millions of entries, lookup dominates
TOO COARSE (per-project boundary): one entry, any edit recompiles all
RIGHT (per-identity-noun boundary): one entry per track/device/widget
```

The right granularity: one boundary per identity noun. Each track, each widget, each parameter is a potential cache boundary.

### 5.9 Verify parallelism

The ASDL dependency graph IS the execution plan. Independent subtrees can compile in parallel:

```text
        Project
       /       \
    Track1     Track2    ← independent, parallel-safe
    /   \       /   \
  Dev1  Dev2  Dev3  Dev4  ← all independent
```

The pattern's purity guarantees make parallelism safe by construction:
- Memoized boundaries are pure (no shared mutable state)
- ASDL nodes are immutable (no data races)
- Structural identity handles deduplication

### 5.10 Design the view projection

Every program has at least two for-loops from the same source:

```text
Source ASDL ──phase──> ... ──place──> Cmd[]
                                      │
                                      ├── for i=1,#cmds do paint(cmds[i]) end
                                      └── for i=#cmds,1,-1 do hit(cmds[i]) end
```

Both start from the same source ASDL. Both are memoized independently. Editing the source recompiles only the changed subtrees.

The view is NOT the source. The source represents the user's domain model. The view represents visual presentation. They are different shapes:

```text
Source (DAW):              View:
    Project                    Shell
    ├── Track 1                ├── Track header row
    │   ├── Devices            ├── Mixer strip
    │   └── Clips              ├── Clip rectangles
    └── Track 2                └── Device panel
```

The same Track appears in three places in the view. The view is a PROJECTION, not a mirror.

---

## Part 6: Type Design Principles

### 6.1 Sum types are domain decisions

Every sum type in the source ASDL represents a decision the user made. "This is an audio clip, not a MIDI clip." "This is a lowpass filter, not a highpass."

Later boundaries RESOLVE these decisions. A sum type that exists at layer N and does not exist at layer N+1 was consumed by the boundary between them.

```text
Layer          Sum types          What they represent
──────         ──────             ───────────────────
App.Widget     11 variants        User's widget choices
UI.Node        10 variants        Layout structure choices
View.Kind      6 variants         Draw command classification
For-loop       0 sum types        Everything is a branch in if/elseif
```

Each layer should have fewer sum types than the previous. The terminal for-loop has zero — everything is concrete branches.

#### Anti-pattern: strings where enums belong

```text
WRONG: Node = (number id, string kind, ...)
       kind = "biquad" — no exhaustiveness, no variant-specific fields

RIGHT: Node = Biquad(number freq, number q)
            | Gain(number db)
            | Sine(number freq)
```

Strings are bags. Sum types are decisions. Every string that represents a fixed set of options should be a sum type.

### 6.2 Records should be deep modules

Each record should be a "deep module" — a simple interface hiding significant complexity.

```text
SHALLOW (too many fields, mixed concerns):
    BiquadNode = (number b0, number b1, number b2,
                  number a1, number a2, number x1, number x2,
                  number y1, number y2, number frequency, number q)

DEEP (meaningful fields, complexity hidden):
    BiquadNode = (FilterMode mode, number frequency, number q) unique
    -- Coefficients computed during compilation.
    -- History state owned by the execution layer.
```

### 6.3 IDs should be structural, not sequential

IDs should identify the THING, not its POSITION. Moving things should not change their identity. This maximizes cache hits.

### 6.4 Lists vs maps

ASDL has `*` for lists. If you need key-value lookup, model it as a list of key-value records:

```text
Setting = (string key, string value) unique
Settings = (Setting* entries) unique
```

Not `settings: table` (which breaks interning, save/load, and the type system).

### 6.5 Cross-references are IDs, resolved later

Model cross-references as ID numbers, not Lua references:

```text
WRONG: Send = (Track target, number gain_db)
       -- Lua pointer, breaks interning and save/load

RIGHT: Send = (number target_track_id, number gain_db) unique
       -- ID reference, validated in a resolve phase
```

### 6.6 Containment anti-patterns

**Over-flattening**: losing structure. `Project = (string* track_names, number* volumes)` — how do you know which devices belong to which track?

**Under-flattening**: redundant wrapping. `Project = (TrackList tracks)`, `TrackList = (TrackEntry* entries)`, `TrackEntry = (Track track, Metadata meta)` — just use `Project = (Track* tracks)`.

### 6.7 Missing a phase

Symptom: a boundary function is doing two unrelated things. It resolves references AND assigns buffer slots.

Fix: split into two boundaries. Each should do ONE kind of knowledge consumption.

### 6.8 The invariant

There is one invariant that, if maintained, guarantees the system works correctly:

> **Every distinction that matters at runtime is either resolved in the sum type (phase dispatch), present in the Cmd fields (payload), or stripped (dead). Nothing is lost. Nothing is duplicated. Nothing is misclassified.**

---

## Part 7: What the Pattern Eliminates

The pattern does not eliminate complexity by pretending complex programs are simple. It eliminates infrastructure by removing the architectural conditions that made coordinating machinery necessary.

### 7.1 State management frameworks

Centralized stores, action/effect plumbing, observer-heavy propagation systems.

In the pattern: the source ASDL is the state. Apply computes the next state. Boundaries derive what should run. No meta-infrastructure needed to answer "what is the application right now?"

### 7.2 Invalidation frameworks

Complex machinery to track what changed, what needs recomputation, what caches must be repaired.

In the pattern: structural identity + memoized boundaries. Unchanged nodes hit the cache. Changed nodes miss. Incrementality is not a second architecture bolted on.

### 7.3 Observer buses and event-dispatch webs

Listeners, subscriptions, bubbling systems, change-notification graphs.

In the pattern: Event ASDL + Apply is the explicit state transition. Consequences are derived structurally by boundaries, not propagated by notification.

### 7.4 Dependency injection containers

Service containers, DI graphs, registries passed everywhere.

In the pattern: resolution phases make each node self-contained. No function needs external context — everything it needs is ON the node.

### 7.5 Hand-built runtime interpretation layers

Dynamic dispatch tables, generic node walkers asking "what are you?" repeatedly, runtime graph traversals rediscovering semantic facts.

In the pattern: phase boundaries resolve type dispatch at compilation time. The for-loop does not ask "what are you?" — it reads `cmd.kind` which is already decided.

### 7.6 Virtual DOM and reconciliation

Virtual DOM frameworks build a new virtual tree, diff it against the old one, and patch the real DOM with the differences.

In the pattern: ASDL interning IS reconciliation. Same fields → same object (identity preserved) → downstream caches hit → no recompilation. Different fields → new object → recompile that subtree. No diffing needed. Identity IS the diff.

This is cheaper and more correct than virtual DOM diffing because:
- No O(N) tree diff algorithm — just O(1) identity comparison per node
- No heuristic key matching — structural identity is exact
- No patch application — boundaries produce the new output directly

### 7.7 Redundant test scaffolding

Mocks, fixtures, setup, teardown for services and environments.

In the pattern: pure functions. Construct ASDL input, call function, assert output. No setup needed.

### 7.8 Ad hoc caches and installer glue

Hand-rolled code caches, one-off registries, closure caches with unclear invalidation.

In the pattern: phase boundaries are the ONLY caches. They are structural, automatic, and inspectable via `pvm.report_string()`.

### 7.9 The general principle

> The pattern eliminates glue whose only job was to reconnect truths that should never have been split apart.

If authored truth and compiled truth are connected by memoized boundaries, less glue.
If change propagation is handled by identity + caching, less glue.
If interaction is an explicit Event language, less glue.

### 7.10 What does NOT disappear

The pattern does not eliminate:
- the need for careful domain modeling
- backend engineering (graphics, audio, network)
- performance work
- operational error handling
- judgment about boundary design and layer count

It moves complexity to places where it is more explicit, more local, and more meaningful.

### 7.11 Warning against reintroducing eliminated machinery

Once the pattern simplifies a codebase, there is a temptation to reintroduce the old furniture by habit:
- adding a state manager where Source ASDL + Apply suffices
- adding an observer bus where Event ASDL + Apply suffices
- adding invalidation flags where identity + phase caches suffice
- adding a service container where a resolution phase suffices
- adding a virtual DOM where ASDL interning suffices

Sometimes these tools are genuinely needed at specific boundaries. But they should be treated as exceptions requiring justification, not as default architecture.

---

## Part 8: The ASDL Convergence Cycle

The ASDL goes through a predictable lifecycle:

### 8.1 The three stages

```text
DRAFT        →      EXPANSION        →      COLLAPSE
(too coarse)        (too many types)         (just right)
```

The draft is your first attempt — top-down, based on domain intuition. It is always too coarse. The expansion is driven by the profiler — every trace exit, every polymorphic dispatch, every classification error demands a new type or boundary. The collapse is driven by the expanded types themselves — once you see all the real distinctions, you also see which are redundant.

### 8.2 Stage 1: The draft — too coarse

You model the domain top-down using Part 5. The draft captures the user's vocabulary faithfully. But it has not been tested against the machine. The for-loops have not spoken.

### 8.3 Stage 2: The expansion — driven by the profiler

You implement the for-loop. You profile it.

**"Trace abort on mixed metatables."** The for-loop iterates a sum type with per-variant metatables. Fix: flatten to a uniform Cmd type with Kind singleton. Type count changes.

**"Cache miss on every frame."** A boundary receives nodes that differ on a derived field. Fix: strip the derived field at the boundary. Or move it to a later phase.

**"Boundary doing two things."** A verb handler resolves layout AND projects to commands. Fix: split into two boundaries. New layer.

Each implementation step adds distinctions. The ASDL grows:
```text
Draft:       3 types, 0 enums, 1 layer
Expanded:   14 types, 4 enums, 3 layers
```

### 8.4 Stage 3: The collapse — driven by structural redundancy

Once validated — every for-loop traces clean, every boundary fits the canonical shape, cache hit ratio above 90% — patterns emerge:

**Variants that share structure.** They collapse into fewer variants with shared fields.

**Boundaries that do the same verb.** They can be one boundary.

**Fields that belong on a header.** Every command variant carries the same x,y,w,h fields. Those become the uniform Cmd product type. Variants become Kind singletons.

```text
Draft:       3 types, 0 enums, 1 layer
Expanded:   14 types, 4 enums, 3 layers
Collapsed:   8 types, 3 enums, 3 layers
```

### 8.5 Why you cannot regress

During expansion: every new type was demanded by a for-loop that couldn't trace clean. Remove it, the trace breaks.

During collapse: every merge is validated by the profiler. Merge two types. Does the for-loop still trace? Yes → merge correct. No → distinction is real.

The cache hit ratio is the regression oracle. If it degrades after a change, the change broke structural sharing.

### 8.6 Practical signs

**Signs you're still in expansion:**
- for-loops have trace aborts
- boundaries resist the canonical shape
- cache hit ratios below 70%
- boundary functions longer than 30 lines

**Signs you're ready for collapse:**
- all for-loops trace clean
- cache hit ratios above 90%
- structural similarity between types added separately
- the same fields appear on multiple variant types

**Signs collapse is done:**
- further merges cause trace regressions
- type count is stable across feature additions
- new features are additive (one new variant + one new handler)

### 8.7 The convergence criterion

The ASDL has converged when:

> every for-loop traces clean, every boundary is a pure structural transform, the cache report shows 90%+ reuse, and recent features were purely additive — one new variant, one new handler, zero changes to existing layers.

---

## Part 9: Worked Examples

### 9.1 Track editor (ui5 — the primary example)

This is a fully working 850-line Love2D application with 12 tracks, live playback animation, drag-to-scroll, mute/solo toggling, volume/pan sliders, and a transport bar.

**Source ASDL** (Layer 0 — what the user edits):

```asdl
module App {
    Track = (string name, number color, number vol, number pan,
             boolean mute, boolean solo, number meter) unique

    Widget = TrackRow(number index, App.Track track,
                      boolean selected, boolean hovered) unique
           | TrackList(App.Widget* rows, number scroll_y, number view_h) unique
           | Header(number count) unique
           | Transport(number win_w, number bpm, boolean playing,
                       string time_str, string beat_str, string hover) unique
           | Inspector(App.Track track, number idx, number win_h, string hover) unique
           | Button(string tag, number w, number h,
                    number bg, number fg, number font_id,
                    string label, boolean hovered) unique
           | ... (11 widget types total)
}
```

**Layout ASDL** (Layer 1 — layout vocabulary):

```asdl
module UI {
    Node = Column(number spacing, UI.Node* children) unique
         | Row(number spacing, UI.Node* children) unique
         | Padding(number l, number t, number r, number b, UI.Node child) unique
         | Clip(number w, number h, UI.Node child) unique
         | Transform(number tx, number ty, UI.Node child) unique
         | Rect(string tag, number w, number h, number rgba8) unique
         | Text(string tag, number font_id, number rgba8, string text) unique
         | ... (10 node types total)
}
```

**Command ASDL** (Layer 2 — flat draw commands):

```asdl
module View {
    Kind = Rect | Text | PushClip | PopClip | PushTransform | PopTransform

    Cmd = (View.Kind kind, string htag,
           number x, number y, number w, number h,
           number rgba8, number font_id, string text,
           number tx, number ty) unique
}
```

**The phase boundary** (Layer 0 → Layer 1):

```lua
local widget_to_cmds = pvm.phase("ui", {
    [T.App.TrackRow] = function(self) ... return pvm.children(widget_to_cmds, self.rows) end,
    [T.App.Button]   = function(self) ... return pvm.once(Rct(self.tag, ...)) end,
    [T.App.Meter]    = function(self) ... return pvm.once(Rct(self.tag, ...)) end,
    ... -- 11 handlers
})
```

Dispatch: `getmetatable(node)` lookup — no generated code, plain table read.
On hit: `seq_gen` over cached array, zero handler work.
On miss: recording triplet wraps handler output, commits to cache on drain.

**The layout walk** (Layer 1 → Layer 2):

Layout methods on UI.Node compute sizes and emit flat View.Cmd arrays:
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
```

**Execution** (pull-driven):
```lua
-- Paint: pull lazily, cache fills as side effect
pvm.each(widget_to_cmds(root), function(cmd)
    local k = cmd.kind
    if k == K_RECT then ... paint rectangle ...
    elseif k == K_TEXT then ... paint text ...
    elseif k == K_PUSH_CLIP then ... set scissor ...
    end
end)

-- Hit test: drain to array, reverse-iterate
local cmds = pvm.drain(widget_to_cmds(root))   -- instant seq hit if cached
for i = #cmds, 1, -1 do hit_test(cmds[i], mx, my) end
```

**Performance**: build_widgets = 14.3µs (90%), compile = 1.6µs (10%), paint = 343µs. Total framework = 16µs = 1% of frame budget. Love2D draw calls are the bottleneck.

**Cache behavior**: phase "ui" shows 93% reuse rate during animated playback (4174 calls, 3037 hits + 892 shared). Track rows that didn't change → cache hit or shared recording → skip handler entirely.

### 9.2 Text editor

**Source ASDL**:
```asdl
module Editor {
    Document = (Block* blocks, Selection selection) unique
    Block = Paragraph(Span* spans, Alignment align)
          | Heading(Span* spans, number level)
          | CodeBlock(string text, string language)
          | List(ListKind kind, ListItem* items)
    Span = Plain(string text) | Styled(string text, Style style)
         | Link(string text, string url) | Code(string text)
    Selection = Cursor(number block_idx, number offset)
              | Range(Cursor anchor, Cursor focus)
}
```

**Three layers**: Editor (source) → Laid (positions computed, text shaped) → View.Cmd (flat).

**What falls out**: keystroke changes one Span → memoized boundaries cache all others → one block recompiles. Undo = previous Document node → cache hit → instant.

### 9.3 Spreadsheet

**Source ASDL**:
```asdl
module Sheet {
    Cell = Formula(CellRef* deps, Expr expr) unique
         | Value(number val) unique | Empty unique
    Expr = Literal(number value) | Ref(CellRef cell)
         | Sum(Expr* args) | Product(Expr* args)
}
```

**Key insight**: evaluation IS compilation. `=SUM(A1:A10)` compiles to a function that adds 10 cells. The compiled evaluator doesn't interpret formulas — it executes a pre-resolved chain.

### 9.4 Drawing / vector graphics

Almost identical pipeline to UI:
- Source: shapes with artistic properties (gradients, strokes)
- Layout: absolute positions (transforms resolved)
- Commands: flat draw calls (rectangles, paths, text)

The same flatten-early architecture. Different source vocabulary, same execution story.

### 9.5 Game / simulation

Two terminal compilations from one source:
- Scene ASDL → render commands (for-loop: draw calls)
- Scene ASDL → physics commands (for-loop: collision checks)

Physics affects rendering (transforms change per-frame). The compiled render commands read physics state as mutable data — transforms are not baked, they are live. But WHAT to draw (which mesh, which shader) was compiled away.

### 9.6 Audio DSP

```asdl
module DSP {
    Device = Osc(number hz) | Filter(FilterMode mode, number freq, number q)
           | Gain(number db) | Chain(Device* devices) | Mix(Device* inputs)
}
```

Verb per device type. The compiled audio graph is a flat schedule of processing steps. Each step reads stable coefficients (payload) and mutates delay history (execution state).

### 9.7 Parser frontend (pvm + uvm)

A grammar is source ASDL. The compiled parser is a uvm machine:
- family = parser type (step function + init + status)
- image = grammar tables + lexer config
- machine = running parse state (cursor, stack)

Coarse-grained stepping (per definition) matches recursive-descent speed (1.1×) with full resumability at definition boundaries.

### 9.8 The applicability test

> Is my user editing a structured program whose meaning I keep rediscovering at runtime? Would it be better to compile that meaning into flat commands?

If yes, the pattern applies.

### 9.9 What is a weaker fit

The pattern is weaker when:
- there is little persistent authored structure
- execution is inherently generic (no benefit from specialization)
- the domain is mostly ad hoc dynamic scripting
- the cost of modeling exceeds the value

---

## Part 10: Philosophy

### 10.1 Programs are compilers, not interpreters

A UI framework takes widget descriptions, resolves layout, produces draw commands, executes them, and on input potentially re-does it. That is a compiler.

An audio engine takes signal graph descriptions, resolves routing, produces processing schedules, executes them, and on parameter change re-does it. That is a compiler.

GPS/pvm makes this compiler nature explicit. Every design question becomes a compiler design question:
- "What type?" → "What ASDL type?"
- "How do I handle events?" → "How does the source update?"
- "How do I optimize?" → "Where are the memoized boundaries?"
- "How do I manage state?" → "What is mutable state vs. what is compiled flat commands?"

### 10.2 Why structural identity over reference identity

In OOP, two objects with identical fields are still different objects (`a ~= b`). In ASDL with `unique`, they ARE the same object (`a == b`).

| Problem | Reference identity | Structural identity |
|---------|-------------------|-------------------|
| Equality | Deep comparison | `==` (instant) |
| Caching | Manual keys | Automatic from identity |
| Change detection | Dirty flags | Identity comparison |
| Structural sharing | Manual | Automatic from with() |
| Undo | Clone entire state | Store previous root |

### 10.3 Why classification over convention

Convention: "Methods starting with `render_` are gens." "Props are params, state is state." "Use `useMemo` for caching."

Classification: Sum type variants ARE code-shaping (structural). Cmd fields ARE payload. Dead fields ARE stripped. The framework can verify this through cache statistics.

Convention fails under pressure. Classification is observable via `pvm.report()`.

### 10.4 Why structure over keys

Keys are an escape hatch. They leak framework mechanics into domain code, are error-prone, and cannot be verified.

Structure is already there — the ASDL, the interning, the phase dispatch. Every time you reach for a key, ask: "Can I express this as structure instead?" Usually you can.

### 10.5 Why ASDL over ad hoc types

ASDL gives: sum types with exhaustiveness, structural interning, constructor validation, method propagation (define on sum parent → all variants get it), and schema as documentation.

### 10.6 Why compilation over interpretation

An interpreter traverses the source tree every frame, re-dispatching at every node. A compiler traverses once (or incrementally), produces flat commands, and runs a for-loop.

```text
Interpreter:  every frame = traverse + dispatch + execute
Compiler:     first frame = compile + install
              next frames = for-loop only (if source unchanged)
              on change   = recompile changed subtree + new for-loop
```

### 10.7 Why flat execution over nested dispatch

Nested dispatch (recursive gen calls through a tree) produces:
- polymorphic call sites → trace aborts
- O(depth) stack frames per element
- cache-unfriendly pointer chasing
- difficulty profiling (where is time spent?)

Flat execution (for-loop over uniform Cmd array) produces:
- one function, one trace
- O(1) stack depth
- cache-friendly linear iteration
- trivial to profile

### 10.8 Why codegen over generic interpretation

Generic dispatch (`select(i, ...)`, `type()` checks, table lookups) produces interpretive overhead in hot paths.

Codegen (loadstring'd functions with inlined constants and unrolled dispatch) produces the exact code LuaJIT would need to trace optimally. The generated source IS the documentation of what the JIT sees.

---

## The Master Checklist

### Domain nouns
```
□ Listed every user-visible noun
□ Classified each as identity noun or property
□ Each identity noun has a stable ID
□ No implementation nouns in the source
```

### Sum types
```
□ Every "or" in the domain is a sum type
□ Each variant has its own fields
□ No strings used where sums belong
□ Every variant is reachable from the UI
```

### Containment
```
□ Drawn the containment tree
□ Each parent owns its children
□ Cross-references are IDs, resolved later
□ Lists use ASDL *, not raw Lua tables
```

### Layers and boundaries
```
□ Named each layer
□ Named each boundary verb
□ Each boundary consumes at least one decision
□ Layer count matches recursion classes + 1 flat
□ Dependency cycles determine pass count
```

### Flatten-early
```
□ Final output layer is flat (Cmd array, no recursion)
□ Cmd type is uniform (one product, Kind singleton)
□ Containment expressed as push/pop markers
□ For-loop execution, no recursive dispatch
```

### Quality tests
```
□ Save/load: every user-visible aspect round-trips
□ Undo: revert root → cache hit → instant
□ Completeness: every variant reachable, every state representable
□ Minimality: every field independently editable
□ Orthogonality: independent fields don't constrain each other
□ Testing: every function testable with one constructor + one assertion
```

### Structural mechanics
```
□ Types marked unique for interning
□ Edits produce new nodes with structural sharing (pvm.with)
□ Boundary caches align with identity nouns
□ phase for type-dispatched streaming boundaries
□   handlers return triplets (pvm.once / pvm.children / pvm.concat2/3/all)
□ scalar boundaries use pvm.phase(name, fn) + pvm.one (pvm.lower is compatibility sugar)
```

### Execution
```
□ Paint: for _, cmd in phase(root) do draw_fn(cmd) end — pull-driven, lazy
□ Hit test: pvm.drain(phase(root)) → reverse for-loop over materialized array
□ State in the execution loop is push/pop stacks only
□ No source-level semantics rediscovered during execution
```

### Performance
```
□ pvm.report() shows cache behavior per boundary
□ Cache hit ratio > 70% during realistic edits
□ For-loop traces clean (one metatable, uniform Cmd)
□ Codegen inspection shows tight generated dispatch
```

---

## Summary

```text
THE USER
    edits a domain program

THE SOURCE OF TRUTH
    source ASDL (interned, immutable, structural identity)

THE INPUT LANGUAGE
    Event ASDL

STATE EVOLUTION
    Apply : (state, event) → state

THE FIVE CONCEPTS
    source ASDL
    Event ASDL
    Apply
    boundaries (phase, memoized on identity; scalar via phase+one)
    flat execution (native for-loop; or pvm.each / pvm.drain helpers)

THE THREE LEVELS
    compilation: pure, structural, memoized
    codegen: quote.lua for ASDL constructors and custom hot paths
    execution: pvm.each / for-loop, push/pop stacks, linear

THE FLATTEN THEOREM
    tree in, flat out, for-loop forever
    state is always a stack
    each recursion class = one ASDL layer
    uniform Cmd product type = one trace = golden bytecode

THE LIVE LOOP
    poll → apply → compile → execute

THE DEEPEST RULE
    the source ASDL is the architecture

THE EXECUTION RULE
    phase boundaries compile lazily via recording triplets (scalar via phase+one)
    pvm.each or pvm.drain pulls the triplet chain
    cache fills as side effect of full drain
    unchanged subtrees hit seq_gen instantly
```

> The pattern is: the user edits a program in a domain language, that
> program is represented as source ASDL, input is represented as Event
> ASDL, state changes are modeled by a pure Apply reducer, authored
> structure is compiled through memoized boundaries into progressively
> narrower representations, the final representation is a flat array of
> uniform command records, and a for-loop executes them until the source
> changes again.
