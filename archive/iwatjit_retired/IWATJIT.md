# iwatjit

*Incremental watjit. A memoized phase boundary framework with deterministic memory, built on watjit.*

---

## Table of contents

1. [What this is](#what-this-is)
2. [Why this exists](#why-this-exists)
3. [The foundational insight](#the-foundational-insight)
4. [Architecture: three arenas, three roles](#architecture-three-arenas-three-roles)
5. [The API](#the-api)
6. [Implementation: the hot path in watjit](#implementation-the-hot-path-in-watjit)
7. [The recording lifecycle](#the-recording-lifecycle)
8. [Memory accounting and introspection](#memory-accounting-and-introspection)
9. [Migration from the original pvm](#migration-from-the-original-pvm)
10. [Comparison table](#comparison-table)
11. [Implementation plan](#implementation-plan)
12. [Non-goals](#non-goals)
13. [The thesis](#the-thesis)

---

## What this is

iwatjit is a memoized phase boundary system for Lua. You define phases — typed transformations over ASDL-like structural values — and iwatjit caches their outputs keyed on input identity. Edit a small part of an input graph; only the phases touching the changed subtree re-run. Everything else hits the cache instantly.

Think of it as a framework for building incremental compilers, incremental renderers, incremental query engines — any system where the shape of the computation is stable but parts of the input change between runs.

iwatjit is the next-generation replacement for the original pvm. It has the same user-facing model — `phase(name, handlers) → boundary` — but is implemented on top of watjit, using native kernels over deterministic typed memory instead of Lua tables and weak references. This changes everything about its performance, correctness, and predictability.

**iwatjit depends on watjit. watjit does not depend on iwatjit.** The libraries are strictly layered.

---

## Why this exists

The original pvm solved a real problem well: caching phase outputs keyed on canonical ASDL identity, with lazy recording-triplet drain and automatic fusion of adjacent misses. It shipped reuse ratios of 90%+ on real workloads.

But it has five structural limitations that are all manifestations of one underlying issue: it is a caching system implemented in a GC language without control over memory.

- **Weak tables are hints, not guarantees.** Source nodes can be held alive through cache values even when they should be collectable.
- **Pending entries leak on partial drain.** Recordings that never complete pin their source nodes indefinitely through strong refs in the entry.
- **Cache growth is unbounded by policy.** Nothing stops a phase from accumulating entries across a long-running process.
- **Hot-path dispatch uses Lua table hash lookups.** Every phase call pays the cost of one or more hashmap lookups in a GC-managed structure.
- **Memory usage is unmeasurable.** You can count entries; you cannot measure their footprint precisely.

All five of these dissolve when the caching primitives are native kernels operating on typed structs in deterministic memory. Not because natives are faster (though they are), but because *the right tool for implementing a cache is a typed memory system, not a GC runtime*.

watjit provides exactly that — typed structs, arenas, slab allocators, LRU helpers, all compiled to native code. iwatjit is what you get when you reimagine pvm with those tools available.

---

## The foundational insight

One observation drives the entire design of iwatjit.

The lifetimes in a phase boundary cache fall into three categories:

- **Phase structure itself** — the set of types, handlers, and hash tables. Determined by program structure. Process lifetime. Never evicted.
- **Cached outputs** — committed results from successful recordings. Stable while live. Evictable under policy (LRU). Policy lifetime.
- **In-flight recordings** — partial accumulation buffers during a drain. Transient. Cursor-like. Drain lifetime.

These three categories are the same three categories as `gen`, `param`, and `state` in the GPS iteration decomposition:

- **gen** — the step function, invariant, eternal
- **param** — the invariant environment for one iteration, stable
- **state** — the mutable cursor, transient

The mapping is not an analogy. It is the same decomposition — *any stateful process with invariant context and transient operation factors into these three roles* — applied once to iteration and again to caching. They agree because they describe the same underlying structure from different angles.

This means the memory architecture of iwatjit is not a design choice. It is a logical consequence of the role decomposition. Three arenas, three allocators, three lifetime regimes — each determined by which role it plays, not by engineering preference.

```
gen    ↔  shape arena   — eternal, structural, process lifetime
param  ↔  result arena  — stable, bounded, policy lifetime
state  ↔  temp arena    — transient, mutable, drain lifetime
```

Everything that follows — the allocators, the hot paths, the entry layout — falls out of this mapping.

---

## Architecture: three arenas, three roles

Memory layout in watjit's linear memory:

```
┌──────────────────────────────────────────────────┐  ← fixed base
│  shape arena                                     │
│                                                  │
│  hash tables: (phase_id, key) → slot index       │
│  phase descriptor table                          │
│  size: O(types × phases), fixed at init          │
│  allocator: static offsets                       │
│  eviction: none, ever                            │
│  role: gen                                       │
├──────────────────────────────────────────────────┤  ← shape_limit
│  result arena                                    │
│                                                  │
│  slab allocator: fixed-size output arrays        │
│  LRU metadata: prev/next pointers                │
│  size: sum of bounded capacities                 │
│  allocator: slab + free list, O(1)               │
│  eviction: LRU, O(1)                             │
│  role: param                                     │
├──────────────────────────────────────────────────┤  ← result_limit
│  temp arena                                      │
│                                                  │
│  bump allocator                                  │
│  scope stack (grows downward from top)           │
│  size: O(max concurrent recordings)              │
│  allocator: bump, O(1)                           │
│  reclamation: scope reset, O(1)                  │
│  role: state                                     │
└──────────────────────────────────────────────────┘  ← memory limit
```

Each arena uses the simplest possible allocator for its role:

**Shape arena: static layout.** Not really an allocator at all. At init, we compute offsets for each phase's hash table and fix them. No runtime allocation. Hash tables use open addressing with linear probing. Power-of-two capacity. Pointer-sized keys and values (i32).

**Result arena: slab + LRU.** Slabs are fixed-size slots. Each slab can hold one committed recording output. Allocation takes from the free list (O(1)) or evicts the LRU tail (O(1)) if full. A doubly-linked list maintains LRU order; `touch` splices a slab to the head in O(1).

**Temp arena: bump allocator with scope stack.** Allocation is a pointer increment. The scope stack grows downward from the top of the region while allocations grow upward from the base. They meet in the middle if exhausted — which is a hard error, not a soft one. `save` pushes the current bump pointer onto the scope stack. `restore` pops and resets bump. All O(1).

None of these allocators are chosen for cleverness. Each is the only correct allocator for its role, given the invariants.

---

## The API

The user-facing surface is nearly identical to the original pvm. Migration is mechanical.

### Creating a runtime

```lua
local iwj = require "iwatjit"

local rt = iwj.runtime {
    shape_capacity  =  1 * 1024 * 1024,   -- 1 MB for cache hash tables
    result_capacity = 64 * 1024 * 1024,   -- 64 MB for cached outputs
    temp_capacity   =  4 * 1024 * 1024,   -- 4 MB for in-flight recordings
}
```

The runtime is the whole memory system: three arenas, their allocators, and the WAT kernels that operate on them. A single runtime supports many phases. Typically you create one runtime per process (or per request pool in an SSR server).

Memory usage is bounded by the sum of the three capacities. **Full stop.** iwatjit cannot grow past this limit. Ever. By construction.

### Defining phases

```lua
-- dispatch-style: handlers per ASDL type
local lower = iwj.phase(rt, "lower", {
    [AST.Add] = function(node)
        return T.concat(lower(node.lhs), lower(node.rhs))
    end,
    [AST.Literal] = function(node)
        return iwj.once(emit_literal(node.value))
    end,
})

-- value-style: a single scalar function
local solve = iwj.phase(rt, "solve", function(node)
    return compute_solution(node)
end)

-- call phases
local commands = iwj.drain(lower(root))
local value    = iwj.one(solve(constraint))
```

Identical shape to pvm. The only new argument is the runtime `rt` passed as the first parameter.

### Bounded phases (explicit policy)

For phases whose inputs are unbounded (per-user renders, per-request compilations), set an explicit capacity:

```lua
local render_user = iwj.phase(rt, "render_user", handlers, {
    bounded = 1024,   -- cache at most 1024 distinct inputs
})
```

Without `bounded`, the phase uses the result arena up to its global capacity (with LRU eviction kicking in when the arena fills). With `bounded`, the phase has its own sub-arena capped at `bounded` slots. This gives fine-grained control over which phases dominate memory.

### Terminals (unchanged from pvm)

```lua
iwj.drain(g, p, c)          → table
iwj.drain_into(g, p, c, out) → out
iwj.each(g, p, c, fn)       → nil
iwj.fold(g, p, c, init, fn) → acc
iwj.one(g, p, c)            → value
```

### Diagnostics (richer than pvm)

```lua
rt:memory_stats()   -- exact byte counts, eviction counts
-- {
--   shape  = { used =   423456, cap =  1048576 },
--   result = { used = 12847360, cap = 67108864, evictions = 127 },
--   temp   = { used =       64, cap =  4194304, peak = 892144 },
-- }

rt:phase_stats(lower)   -- per-phase accounting
-- {
--   name = "lower",
--   calls = 4174, hits = 3037, shared = 892,
--   reuse_ratio = 94.0%,
--   memory = 128256, evictions = 12,
-- }

rt:report()   -- all phases, formatted
```

The memory numbers are **exact**, because we own the allocator. Not estimates.

---

## Implementation: the hot path in watjit

The core hot-path function — called on every phase invocation — is a watjit kernel that does cache lookup and returns a triplet handle. Written in watjit's C-like DSL:

```lua
-- iwatjit_kernels.lua — the hot path as watjit kernels

local wj = require "watjit"
local i32 = wj.i32

-- the entry struct, living in the temp arena (for pending) or
-- referenced from the result arena (for committed outputs)
local Entry = wj.struct("Entry", {
    {"key",        i32},
    {"phase_id",   i32},
    {"state",      i32},   -- 0=empty, 1=pending, 2=committed
    {"slot",       i32},   -- slab index in result arena (if committed)
    {"buf_ptr",    i32},   -- recording buffer pointer
    {"buf_n",      i32},
    {"buf_cap",    i32},
    {"scope_mark", i32},   -- for cancellation
})

-- phase_call_kernel: the entry point
-- returns an entry pointer, or -1 for miss-that-needs-handler
local function phase_call_kernel()
    return wj.func "phase_call" (
        i32 "rt_base",
        i32 "phase_id",
        i32 "key"
    ) :returns(i32) {function(rt, phase_id, key)

        -- hash table for this phase lives at a known offset
        local table_addr = rt + phase_id * i32(HASH_TABLE_STRIDE)

        -- look up: returns slot index or -1
        local slot = wj.call("hash_lookup", table_addr, key)

        -- hit: cached result exists
        if_(slot:ge(i32(0))) {
            local entry_addr = wj.call("result_slab_addr", slot)
            local entry = Entry.at(entry_addr)
            if_(entry.state:eq(i32(2))) {
                -- fully committed: touch LRU, return entry
                wj.call("lru_touch", slot),
                return entry_addr,
            }
            -- pending (in-flight miss): share the recording
            if_(entry.state:eq(i32(1))) {
                return entry_addr,    -- caller sees shared recording
            }
        }

        -- miss: allocate a new pending entry in temp arena
        local mark = wj.call("temp_save", rt)
        local entry_ptr = wj.call("temp_alloc", rt, i32(Entry.size))
        local entry = Entry.at(entry_ptr)

        entry.key        = key,
        entry.phase_id   = phase_id,
        entry.state      = i32(1),   -- pending
        entry.slot       = i32(-1),
        entry.buf_ptr    = wj.call("temp_alloc", rt, i32(INIT_BUF_SIZE)),
        entry.buf_n      = i32(0),
        entry.buf_cap    = i32(INIT_BUF_CAP),
        entry.scope_mark = mark,

        wj.call("hash_insert", table_addr, key, entry_ptr),
        return entry_ptr
    end}
end
```

Every operation in the hot path is a typed memory access. No hash table of Lua tables. No weak references. No GC involvement. The whole function compiles down to a few dozen machine instructions.

The Lua-side dispatch code around this kernel is thin:

```lua
-- iwatjit.lua — thin Lua wrapper over the WAT kernels

function iwj.phase(rt, name, handlers, opts)
    opts = opts or {}
    local phase_id = rt:register_phase(name, handlers, opts)

    return setmetatable({
        name     = name,
        phase_id = phase_id,
        runtime  = rt,
    }, {
        __call = function(self, node, ...)
            local key = canonical_key(node)
            local entry_ptr = rt.kernel_phase_call(rt.base, phase_id, key)

            local entry = read_entry(entry_ptr)
            if entry.state == 2 then
                -- committed: return seq triplet over cached slab
                return seq_gen_over_slab, entry.slot, 0
            end

            -- pending: we need to drive the recording
            -- (either this call created it or it's shared in-flight)
            return recording_gen, entry_ptr, 0
        end,
    })
end
```

The handler is still called from Lua — it has to be, since user handlers produce triplets and call other phases, which means they need access to the full Lua environment. But the bookkeeping around the handler is in WAT.

---

## The recording lifecycle

A recording progresses through four states: empty, pending, advancing, committed. Or, on error: empty, pending, advancing, cancelled.

### Begin

```
temp_save(rt) → mark
temp_alloc(rt, sizeof(Entry)) → entry_ptr
temp_alloc(rt, INIT_BUF_SIZE) → buf_ptr
initialize entry fields
hash_insert(table, key, entry_ptr)
```

All five operations are O(1) in the temp arena. The `mark` is critical — it records exactly where the temp arena's bump pointer was before this recording started. If anything goes wrong, `temp_restore(rt, mark)` reclaims everything in one pointer assignment.

### Advance

Each element pulled from the source triplet:

```
source_gen(source_param, source_ctrl) → (ctrl', value)
if ctrl' == nil → recording exhausted, commit
else:
    if buf_n == buf_cap → grow buffer (also in temp arena)
    buf[buf_n] = value
    buf_n += 1
    source_ctrl = ctrl'
```

Growth strategy: allocate a new larger buffer in the temp arena, copy over, update `buf_ptr` and `buf_cap`. The old buffer is abandoned but will be reclaimed along with everything else when the recording's scope closes. No explicit free needed.

### Commit (drain complete)

```
slot = result_alloc()
if slot == -1:
    slot = result_evict_lru()          -- frees LRU tail
    hash_insert(other_table, other_key, -1)  -- clear old entry
copy buf[0..buf_n] into result slab at slot
entry.slot = slot
entry.state = 2                        -- committed
hash_insert(table, key, entry_ptr)    -- update to point at committed entry
lru_push_head(slot)
temp_restore(rt, entry.scope_mark)    -- reclaim entry + buffer in O(1)
```

Observe: after commit, the entry pointer is no longer valid — temp was reset. The hash table now stores a slot index (or a pointer into the result arena) instead. From this point forward, subsequent calls hit the committed path: lookup returns the slot, we return a seq triplet over the cached slab data, handler never runs.

### Cancel (error, partial drain)

```
hash_remove(table, key)               -- pending entry no longer findable
temp_restore(rt, entry.scope_mark)    -- reclaim entry + buffer in O(1)
```

The strong reference to the source node — held inside the entry's `source_param` — is gone the moment `temp_restore` runs. No GC needed. No weak-table timing. The leak that plagues the original pvm is impossible here by construction.

---

## Memory accounting and introspection

Because we own every byte, we can report exactly:

```lua
local stats = rt:memory_stats()

-- per-arena:
stats.shape.used     -- bytes of hash table storage currently occupied
stats.shape.cap      -- total bytes allocated to shape arena
stats.result.used    -- bytes of cached outputs currently live
stats.result.cap     -- total bytes allocated to result arena
stats.result.evictions  -- count of LRU evictions since last reset
stats.temp.used      -- bytes currently in use (usually small; grows during active drain)
stats.temp.cap       -- total bytes allocated to temp arena
stats.temp.peak      -- high-water mark since last reset
```

Per-phase accounting tracks where the result arena's bytes are going:

```lua
for _, phase in ipairs(rt:phases()) do
    local s = rt:phase_stats(phase)
    print(string.format(
        "%-20s  calls=%-6d reuse=%-6.1f%%  mem=%-8d  evict=%d",
        s.name, s.calls, s.reuse_ratio * 100, s.memory, s.evictions))
end
```

This is the diagnostic surface iwatjit offers that pvm cannot. In production, you log these numbers alongside application metrics. A phase whose memory footprint grows without its reuse ratio improving is a smell — it means identities are fragmenting, and the input canonicalization is leaking.

---

## Migration from the original pvm

The surface is almost identical. Concrete changes:

```lua
-- pvm
local ctx = pvm.context():Define(schema)
local p = pvm.phase("name", handlers)
p(node)
pvm.drain(p(node))

-- iwatjit
local rt = iwatjit.runtime { ... }    -- NEW: explicit memory config
local ctx = iwatjit.context():Define(schema)
local p = iwatjit.phase(rt, "name", handlers)   -- NEW: rt argument
p(node)
iwatjit.drain(p(node))
```

Four differences:

1. Require `iwatjit` instead of `pvm`.
2. Create a runtime explicitly. This forces you to think about memory bounds at definition time, which is a good thing.
3. Pass the runtime as the first argument to `phase`.
4. Optionally add `{bounded = N}` to phases with unbounded input spaces.

The handler surface, triplet API, drain semantics, and reuse-ratio diagnostics are identical. Code that uses pvm correctly will work on iwatjit with mechanical changes. Code that relied on pvm's accidental behavior (e.g. unbounded growth) will need to have its memory story made explicit.

A migration shim is possible:

```lua
-- pvm_compat.lua — makes iwatjit usable under the pvm API
local iwj = require "iwatjit"
local default_rt = iwj.runtime {
    shape_capacity  =  4 * 1024 * 1024,
    result_capacity = 64 * 1024 * 1024,
    temp_capacity   =  4 * 1024 * 1024,
}
local pvm = {}
function pvm.phase(name, handlers)
    return iwj.phase(default_rt, name, handlers)
end
-- ... other re-exports
return pvm
```

This is useful during the transition period. It should not be the long-term path — the runtime's capacities should be tuned per application.

---

## Comparison table

| | original pvm | iwatjit |
|---|---|---|
| Memory model | Lua tables, weak refs | Wasm linear memory, owned allocators |
| Hot path | Lua table hash lookup | watjit kernel over typed struct |
| Cache eviction | GC-driven (unpredictable) | LRU-driven (deterministic, policy-set) |
| Memory bounds | implicit (unbounded) | explicit (configured) |
| Partial drain leak | possible | impossible by construction |
| Memory introspection | entry counts only | exact bytes, per-arena, per-phase |
| Hash lookup cost | ~50-200 ns (GC-managed) | ~5-20 ns (native) |
| Implementation | ~1200 lines of Lua | ~400 lines Lua + ~500 lines WAT |
| Dependency | none | watjit |
| Deterministic latency | no (GC pauses possible) | yes (no GC in hot path) |

---

## Implementation plan

Sequenced after watjit. Each phase is independently demonstrable.

### Phase 1: arenas in watjit

1. Implement hash table as a watjit library (using struct + array).
2. Implement slab allocator + LRU as a watjit library.
3. Implement temp arena with scope stack as a watjit library.
4. Each arena used standalone, tested in isolation.

**Milestone 1**: all three arenas pass their unit tests. They work as watjit libraries independent of iwatjit.

### Phase 2: the iwatjit runtime

5. Define the Entry struct.
6. Implement `phase_call_kernel`, `recording_advance_kernel`, `commit_kernel`, `cancel_kernel` in watjit.
7. Lua-side wrapper: runtime constructor, phase constructor, triplet conversion.
8. Basic tests: hit/miss/shared paths, correctness equivalence with pvm.

**Milestone 2**: `iwatjit.phase` works for scalar handlers and returns correct triplets. Unit tests cover the three paths.

### Phase 3: feature parity with pvm

9. Dispatch-style handlers (per-type).
10. Extra-args cache keying.
11. All terminal helpers: drain, drain_into, each, fold, one.
12. Behavioral equivalence test suite: everything that works on pvm must work on iwatjit.

**Milestone 3**: pvm's test suite passes on iwatjit.

### Phase 4: bounded phases and eviction

13. Per-phase bounded capacity via sub-arenas.
14. LRU touch on every hit.
15. Eviction correctness tests: evicted entries are unreachable; re-access recomputes correctly.

**Milestone 4**: long-running test with unbounded input identity keeps memory bounded at the configured capacity.

### Phase 5: diagnostics and introspection

16. `memory_stats`, `phase_stats`, `report`.
17. Per-phase memory accounting.
18. Hot-path profiling hooks for when phases are slow.

**Milestone 5**: diagnostics surface is complete and documented.

### Phase 6: migration

19. pvm compatibility shim.
20. Benchmarks: pvm vs iwatjit on real workloads.
21. Documentation: migration guide, memory tuning guide.

**Milestone 6**: existing pvm user migrates a real project to iwatjit and reports numbers.

---

## Non-goals

**Not a replacement for pvm in all cases.** If your workload is small and short-lived — a build tool, a one-shot compiler — the original pvm's simplicity may be preferable. iwatjit is for long-running or memory-sensitive workloads where explicit bounds matter.

**Not a general memory management system.** The three arenas are specialized for the three caching roles. They are not offered as a general allocator framework. (watjit's arena/slab/lru libraries are separate and more general.)

**Not coupled to specific ASDL.** iwatjit uses canonical identity as its key, but does not require a specific ASDL implementation. Any value with stable identity works.

**Not a framework that dictates architecture.** iwatjit provides phases and caching. How you use them is your decision.

**Does not swallow watjit.** watjit remains a standalone library. iwatjit is strictly a consumer of watjit. The boundary between the two is clean.

---

## The thesis

> The three lifetimes of a caching system — structural (process lifetime), result (policy lifetime), transient (operation lifetime) — are the same three roles as gen/param/state in the iteration decomposition. Mapping those roles to three arenas in Wasm linear memory gives each lifetime the simplest correct allocator (static layout, slab+LRU, bump+scope). Implementing the hot path as watjit kernels over typed structs eliminates GC involvement, makes memory bounds explicit and enforced, and makes leaks impossible by construction. The result is pvm's user-facing model, preserved exactly, with the implementation rebuilt on watjit. Same ergonomics. Predictable performance. Bounded memory. Honest diagnostics.

---

## File layout

```
iwatjit/
├── README.md                  — this document
│
├── lib/
│   ├── iwatjit.lua            — main module: runtime, phase, terminals
│   ├── iwatjit_kernels.lua    — watjit kernel definitions
│   ├── iwatjit_entry.lua      — Entry struct, lifecycle helpers
│   ├── iwatjit_dispatch.lua   — Lua-side phase dispatch wrapper
│   ├── iwatjit_stats.lua      — diagnostics and introspection
│   │
│   ├── hashtable.lua          — watjit library: open-address hash table
│   ├── slab_lru.lua           — watjit library: slab + LRU
│   └── temp_arena.lua         — watjit library: bump + scope stack
│
├── compat/
│   └── pvm.lua                — pvm API shim over iwatjit
│
├── test/                      — behavioral equivalence with pvm
├── bench/                     — throughput and latency benchmarks
└── examples/
    ├── compiler_pipeline.lua
    ├── ui_renderer.lua
    └── ssr_cache.lua
```

Estimated size: ~400 lines of Lua (the orchestration layer) + ~500 lines of watjit code (the kernel hot paths and arena implementations).

---

## Status

Design complete. Awaiting watjit implementation to reach Milestone 4 (layer 3 abstractions stable) before Phase 1 of iwatjit begins.

The two projects are strictly sequenced: watjit proves itself standalone, then iwatjit builds on a stable foundation. This avoids the failure mode where both evolve simultaneously and each blocks the other.

---

*iwatjit is the next generation of pvm, built right. Same model, better substrate. The user writes the same code; the framework makes better guarantees.*
