# Moonlift LuaJIT-Hosted Integration and Hosted Parsing

Status: design document for a **deferred future** Moonlift integration direction in which Moonlift hosts or deeply integrates with LuaJIT and also hosts parsing, so the language is not limited to:

- LuaJIT + raw strings
- FFI-loaded shared libraries
- builder API only

This hosted/state-aware path is **not** the current implementation and is **not** the current project priority.
Today the implemented and prioritized bridge is the thinner `moonlift/lua/moonlift/jit.lua` FFI replay path over `BackProgram`, and the current plan is to finish the language/compiler through that FFI path first.

This document explains the ergonomic, architectural, and compiler-architecture wins of a LuaJIT-hosted and parser-hosted design if/when Moonlift revisits that direction later.

It is complementary to:

- `moonlift/QUOTING_SYSTEM_DESIGN.md`

That document defines the quote / fragment / function model.
This document explains why hosting LuaJIT and hosting parsing opens a better user surface and a cleaner runtime integration seam.

---

# Executive summary

## Main idea

If Moonlift hosts LuaJIT itself — or at least deeply integrates at the `lua_State*` level rather than through a raw FFI-only seam — and also hosts parsing, then Moonlift can move from:

- library-looking quote builders
- raw string parser entrypoints
- pointer-ish artifact ergonomics

to:

- real integrated fragment syntax
- natural callable compiled values
- direct session/state objects
- registry-backed caches and lifetimes
- parser-hook syntax for `expr`, `region`, and `func`

## Core conclusion

A hosted LuaJIT + hosted parser direction would let Moonlift have:

- **one semantic core** in Lua/ASDL/PVM
- **much better user ergonomics** at the host/front-end boundary
- **much better backend/session ergonomics** at the native boundary

Without changing the central compiler architecture.

This also does **not** mean Moonlift must abandon a plain FFI-facing API forever.
A reasonable long-term shape is:

- finish and keep the plain FFI-facing API as a supported public path for LuaJIT users
- only later, if still wanted, add hosted/state-aware integration as an additional richer layer

## Most important wins

### 1. Real integrated syntax
Instead of being limited to:

- `q.expr({ ... }, function(...) ... end)`
- `q.expr({ ... }, [[ ... ]])`

Moonlift could expose syntax like:

```lua
local add1 = expr (x: i32) -> i32
    x + 1
end

local gain_step = region (i: index, out: &f32, g: f32)
    out[i] = out[i] * g
end

local dot = func dot(a: &Vec2, b: &Vec2) -> f32
    return a.x * b.x + a.y * b.y
end
```

### 2. Better runtime objects
Compiled code can become:

- real Lua userdata
- directly callable
- lifetime-managed automatically
- associated with native sessions/artifacts without awkward raw pointer APIs

### 3. Registry-backed caches and sessions
With direct `lua_State*` access, Moonlift can naturally manage:

- compile sessions
- persistent backend state
- native caches
- weak references
- artifact retention
- fragment/function -> compiled object maps

### 4. Better separation of concerns
The architecture can stay:

- Lua / ASDL / PVM = semantic/compiler center
- native backend = session/artifact/codegen layer

while the user-facing seam becomes much cleaner than the current FFI bridge.

---

# 1. Current situation and current limitation

The current reboot uses a direct LuaJIT FFI bridge to a thin Rust backend.

That is useful and has already validated the new architecture.

But the current seam naturally has some awkwardness:

- `ffi.cdef` boilerplate
- explicit shared-library loading
- raw pointer-ish backend handles
- manual artifact lifetime considerations
- explicit pointer retrieval and `ffi.cast`
- string/array marshaling through FFI
- parser ergonomics largely limited to raw strings or builder APIs

This is not a problem in the core compiler design.
It is a problem in the **host/native boundary ergonomics**.

The hosted LuaJIT direction exists to improve that seam.

---

# 2. Important distinction: native module vs full embedding

It is useful to distinguish two related but different possibilities.

## 2.1 Native Lua module / state-aware integration

This means:

- Moonlift backend code talks directly to `lua_State*`
- creates real userdata
- uses metatables
- raises real Lua errors
- stores registry references
- manages hidden lifetimes and caches inside Lua state

This already gives most of the ergonomic wins.

## 2.2 Full hosted LuaJIT runtime

This means:

- Moonlift owns the LuaJIT runtime process/state lifecycle itself
- Moonlift can also own the parser integration story more tightly
- Moonlift can potentially integrate parser hooks / fragment syntax directly into the host language surface

This is a stronger move, but the conceptual wins are similar.

### Practical note

For many of the runtime/object-model gains, a state-aware native module is already enough.
For the real parser-hook / integrated-syntax story, deeper hosting becomes much more attractive.

### Important non-goal

Exploring a richer hosted/state-aware direction later does **not** mean Moonlift should abandon or demote the public FFI surface.

Those are different questions:

- what additional integration model might be attractive later?
- what public/API surface should Moonlift finish and keep working for real users now?

A good long-term answer may be:

- Moonlift first completes and stabilizes the FFI path for real LuaJIT use
- Moonlift later may add hosted/state-aware integration if it still looks worthwhile
- the working FFI path remains supported for LuaJIT users who just want to load a library and call into it

---

# 3. What direct `lua_State*` access buys us

Even before discussing hosted parsing, direct Lua-state integration gives several major wins.

## 3.1 Real userdata instead of pointer-ish wrappers

Instead of awkward FFI tables containing raw pointers, Moonlift can expose:

- `Session` userdata
- `Artifact` userdata
- `CompiledFunction` userdata
- later maybe `CompiledCallback` userdata

These can have:

- methods
- `__gc`
- `__tostring`
- hidden native references
- registry-backed caches

This is a much better Lua object model.

## 3.2 Direct callable compiled values

Instead of this FFI-oriented style:

```lua
local artifact = jit:compile(program)
local ptr = artifact:getpointer(Back.BackFuncId("main"))
local f = ffi.cast("int32_t (*)(int32_t)", ptr)
assert(f(41) == 42)
```

Moonlift could expose:

```lua
local f = session:compile(func_value)
assert(f(41) == 42)
```

where `f` is already a callable Lua object.

This is one of the biggest ergonomic wins.

## 3.3 Hidden lifetime retention

Today the raw model forces users to think about artifact lifetime:

- pointers are valid only while the artifact is alive

With state-aware integration, a callable compiled object can keep hidden references to:

- its artifact
- its session
- maybe its sealing/compile metadata

That means users do not have to manually think in terms of “keep this artifact alive or the function pointer dies”.

## 3.4 Better errors

A state-aware native integration can raise normal Lua errors directly.

That is much nicer than:

- C return codes
- fetch last error string
- wrap it later manually

Compiler APIs feel much better when failures are ordinary Lua errors.

## 3.5 Registry-backed caches

With direct access to the Lua state, Moonlift can maintain:

- weak tables
- registry references
- session-local caches
- fragment/function -> compiled object mappings
- hidden native handles

This fits naturally with the PVM/ASDL design.

---

# 4. Why hosting parsing changes the language horizon

This is the deeper reason for caring about LuaJIT hosting.

If Moonlift hosts parsing, then the system is no longer limited to:

- raw source strings passed to parsing functions
- builder-only APIs
- library-looking quote surfaces

Instead Moonlift can expose **real integrated syntax**.

This is a major change in user ergonomics.

## 4.1 Without hosted parsing

The ergonomic ceiling looks like:

```lua
local add1 = q.expr({ i32"x" }, function(x)
    return x + i32(1)
end)
```

or:

```lua
local add1 = q.expr({ i32"x" }, [[
    x + 1
]])
```

These are already decent, but they still feel like:

- library entrypoints
- or string-based embedded parsing

## 4.2 With hosted parsing

Moonlift can instead expose fragment literals as actual syntax:

```lua
local add1 = expr (x: i32) -> i32
    x + 1
end

local plus_rhs = expr (x: i32, ?rhs: i32) -> i32
    let y = x + 1
    y + rhs
end

local gain_step = region (i: index, out: &f32, g: f32)
    out[i] = out[i] * g
end

local dot = func dot(a: &Vec2, b: &Vec2) -> f32
    return a.x * b.x + a.y * b.y
end
```

This is a major qualitative improvement.

---

# 5. The parser hook story

A hookable parser — Terra is one proof that such a thing is possible and useful — changes the ergonomic question from:

- “how do we encode fragments as builder calls or strings?”

to:

- “what syntax should fragments have?”

That is a much better place to be.

## 5.1 Fragment literals become language forms

A hookable parser allows Moonlift to make these first-class surface forms:

- `expr`
- `region`
- `func`
- later maybe `module`

This is much more pleasant than forcing users through raw builder/library forms.

## 5.2 Antiquote / host escape becomes natural

Because Lua remains the host metaprogramming language, parser hooks also make antiquote natural.

Conceptual form:

```lua
local function addk(k)
    return expr (x: i32) -> i32
        x + @{k}
    end
end
```

This is much better than manual string interpolation or awkward builder-only forms in many cases.

## 5.3 The semantic rule still stays the same

Even with parser hooks, the semantic rule must remain:

- builder forms
- string-based source forms
- parser-hosted fragment syntax

all lower to the **same Fragment / Function model**.

Parser hooks improve the surface.
They must not create a second semantic universe.

---

# 6. Integrated syntax and the Fragment / Function model

The hosted parser story only makes sense because the semantic core is already converging on a clean model.

That model is:

- **Fragment**
  - expression-shaped fragment
  - region-shaped fragment
- **Function**

So parser-hosted syntax should map as follows:

## 6.1 `expr`
Parses into an expression-shaped Fragment.

## 6.2 `region`
Parses into a region-shaped Fragment.

## 6.3 `func`
Parses into a Function whose body is region/function code.

This preserves the important conceptual split:

- Fragment = assemblable code
- Function = callable compile unit

---

# 7. Why this is better than raw strings

Raw strings are workable, but they have obvious limits.

## 7.1 Raw strings are second-class surface syntax

Even if the semantic system is good, raw strings still feel like:

- parser calls hidden in a library
- not fully integrated into the host language
- harder to format, inspect, and tool nicely

## 7.2 Integrated syntax is a real language feature

With hosted parsing, fragments become true surface-language constructs.

That improves:

- readability
- authoring flow
- error reporting
- syntax highlighting / tooling prospects
- antiquote ergonomics
- overall language identity

## 7.3 The semantic core does not need to change

That is what makes this especially attractive.

Hosted parsing is not a reason to redesign the fragment/function semantics.
It is a reason to expose them more naturally.

---

# 8. The runtime-object-model wins of hosting LuaJIT ourselves

Beyond syntax, hosting LuaJIT or deeply owning the state gives several object-model wins.

## 8.1 Sessions become first-class

Moonlift can expose a first-class `Session` object that owns:

- backend compile state
- caches
- registered externs
- compiled body retention
- maybe later closure-plan state

Example shape:

```lua
local sess = ml.session()
local f = sess:compile(func_value)
```

This is much more natural than a raw FFI seam.

## 8.2 Compiled callbacks become first-class

For audio and interactive systems, compiled callbacks can become natural host objects:

```lua
local cb = sess:compile(callback_func)
audio:set_callback(cb)
```

where `cb`:

- is callable or callback-compatible
- retains its native artifact/session
- can expose debug info / stats
- can later be swapped or rebuilt naturally

## 8.3 Extern registration becomes more natural

Instead of raw pointer plumbing only, a hosted state can support cleaner extern registration APIs.

Even if hot-path Lua callbacks should be avoided, tooling and session setup become easier.

---

# 9. Audio callback angle

Hosted parsing and direct state integration are especially interesting for the DAW/audio case.

Why?

Because the desired hot shape is often:

- one exported callback function
- one big loop
- loop body assembled from many reusable fragments

With parser-hosted syntax, that becomes much nicer to express.

Example conceptual callback surface:

```lua
local osc_step = region (i: index, out: &f32, st: &State)
    let s = sample_from_phase(st.phase)
    out[i] = s
    st.phase = st.phase + st.inc
end

local gain_step = region (i: index, out: &f32, g: f32)
    out[i] = out[i] * g
end

local callback = func audio_callback(out: &f32, st: &State, g: f32, nframes: index) -> void
    loop i over range(nframes)
        osc_step(i, out, st)
        gain_step(i, out, g)
    end
end
```

This is much nicer than forcing the same thing through library calls or raw strings.

Yet the underlying semantic story stays the same:

- `osc_step` = region fragment
- `gain_step` = region fragment
- `callback` = function

That is exactly what we want.

---

# 10. What should not change even if LuaJIT is hosted

It is important to state what **should remain stable**.

## 10.1 Semantic lowering should stay in Lua/ASDL/PVM

Hosting LuaJIT should not mean moving the compiler center back into Rust.

The semantic center should remain:

- Lua
- ASDL
- PVM

The native side should own:

- sessions
- artifacts
- backend state
- compiled objects
- parser/runtime integration as needed

## 10.2 Builder API must remain

Even if parser-hosted syntax becomes available, the builder API must remain because it is still the right tool for:

- programmatic generation
- higher-order specialization
- compiler tooling
- analysis/transformation utilities

Hosted syntax is a major ergonomic win, but it should be a frontend over the same core, not a replacement for the builder path.

## 10.3 The Fragment / Function core should remain the same

This is essential.

Hosted syntax must still lower to:

- Fragments
- Functions
- explicit params and slots
- structural hygiene
- explicit later sealing

Otherwise the system will split.

---

# 11. Recommended direction

The strongest long-term direction is:

## 11.1 Semantic/compiler center
Keep this in:

- Lua
- ASDL
- PVM

## 11.2 Runtime/backend seam
Move toward a state-aware native integration so Moonlift gets:

- real userdata objects
- direct callable compiled values
- hidden artifact/session retention
- direct Lua errors
- registry-backed caches
- session objects

## 11.3 Parsing/story of syntax
Move toward hosted parsing / hookable parser integration so Moonlift gets:

- integrated `expr` syntax
- integrated `region` syntax
- integrated `func` syntax
- antiquote/host escape forms
- not just raw strings

## 11.4 Strict invariant

No matter which frontend is used:

- builder API
- raw source strings
- parser-hosted integrated syntax

all must lower to the same Fragment / Function semantic core.

That is the invariant that keeps the system clean.

---

# 12. Final summary

Hosting LuaJIT ourselves and hosting parsing too would give Moonlift two major classes of wins.

## 12.1 Runtime / object-model wins

- real userdata instead of awkward pointer wrappers
- direct callable compiled values
- hidden artifact/session lifetime retention
- better errors
- registry-backed caches
- natural session and callback objects

## 12.2 Language / syntax wins

- real integrated fragment syntax
- not limited to raw strings
- antiquote becomes natural
- `expr`, `region`, and `func` become real host-language forms
- far better ergonomics for fragment-heavy code, especially DSP / callback assembly

## 12.3 Most important constraint

These wins are only worth taking if the semantic core remains unified.

That means:

- hosted syntax is a new frontend
- not a new semantic world
- the true semantic core remains:
  - Fragment
  - Function
  - explicit interfaces
  - structural hygiene
  - PVM-cached ASDL values

That is the recommended horizon.
