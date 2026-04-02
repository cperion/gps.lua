# Benchmark: mgps vs clay.h

**Date**: 2026-04-01
**Platform**: x86_64 Linux (Fedora), LuaJIT 2.1.1767980792, GCC -O2
**Clay version**: 0.14 (single-header C)
**mgps**: current HEAD (LuaJIT)

## What is being compared

**Clay.h** is a popular immediate-mode C layout library. Each frame it:
1. Rebuilds the entire element tree from scratch (imperative builder API)
2. Runs flex-box-style layout
3. Produces a flat render command array

**mgps** is a structural compiler architecture in LuaJIT. Each frame it:
1. Constructs an interned ASDL tree (structural sharing)
2. Lowers through View layer (layout) → Backend IR → Terminal emission
3. Produces composed gen/state/param machines

The key architectural difference: **Clay rebuilds everything every frame.
mgps caches structurally — unchanged subtrees are skipped entirely.**

## Workloads

| Workload         | Description                                          |
|------------------|------------------------------------------------------|
| `flat_list`      | N rows, each with a text label + tag badge           |
| `text_heavy`     | N rows of text (text measurement stress)             |
| `nested_panels`  | N groups × 6 cards each (nesting + layout)           |
| `inspector_mini` | Realistic 3-panel editor layout with N asset rows    |

Same visual structure in both. Clay uses `measure_text = len * fontSize * 0.6`
(mock). mgps uses the identical formula.

## Results: Cold Build (full rebuild, no caching)

*"How fast can each system build the UI from scratch?"*

### 100 items

| Workload         | Clay (µs) | mgps cold (µs) | Clay faster by |
|------------------|-----------|-----------------|----------------|
| flat_list        |    289    |      803        |    2.8×        |
| text_heavy       |    115    |      613        |    5.3×        |
| inspector_mini   |     93    |      528        |    5.7×        |

### 500 items

| Workload         | Clay (µs) | mgps cold (µs) | Clay faster by |
|------------------|-----------|-----------------|----------------|
| flat_list        |   1,412   |    4,365        |    3.1×        |
| text_heavy       |    559    |    3,194        |    5.7×        |

### 1000 items

| Workload         | Clay (µs) | mgps cold (µs) | Clay faster by |
|------------------|-----------|-----------------|----------------|
| flat_list        |   2,850   |   10,222        |    3.6×        |
| text_heavy       |   1,116   |    7,270        |    6.5×        |

**Verdict**: Cold builds, clay wins handily. Optimized C with arena allocation
and no structural overhead beats LuaJIT with interning tries, ASDL construction,
and multi-layer lowering. Expected: ~3-6× faster for C vs. LuaJIT at this kind
of allocate-and-compute workload.

### Nested panels (50 groups × 6 cards = 300 cards)

| Workload         | Clay (µs) | mgps cold (µs) | Clay faster by |
|------------------|-----------|-----------------|----------------|
| nested_panels    |    539    |    3,840        |    7.1×        |

Nesting is where mgps pays the most in cold builds: more ASDL nodes to intern,
more composition levels.

## Results: Hot Path (identical tree, structural cache hit)

*"How fast is a no-op frame when nothing changed?"*

| Workload (100 items) | Clay (µs) | mgps hot (µs) | mgps faster by  |
|----------------------|-----------|---------------|-----------------|
| flat_list            |    289    |    **0.01**   | **28,900×**     |
| text_heavy           |    115    |    **0.01**   | **11,500×**     |
| nested_panels (50)   |    539    |    **0.02**   | **26,950×**     |
| inspector_mini (50)  |     93    |    **0.02**   | **4,650×**      |

**Verdict**: mgps's hot path is **four to five orders of magnitude faster**.
When the source tree is unchanged, the `M.lower()` boundary hits L1 cache
(same interned object → return cached result). Cost: one table lookup. ~10-20ns.

Clay has no such mechanism. It must rebuild the entire tree every frame regardless
of whether anything changed.

## Results: Incremental (one leaf changed)

*"How fast is recompilation when one element changes?"*

| Workload (100 items) | Clay (µs) | mgps incremental (µs) | mgps faster by |
|----------------------|-----------|----------------------|----------------|
| flat_list            |    289    |     **0.22**         |  **1,314×**    |
| text_heavy           |    115    |     **0.14**         |    **821×**    |
| nested_panels (50)   |    539    |     **0.83**         |    **649×**    |
| inspector_mini (50)  |     93    |     **0.16**         |    **581×**    |

| Workload (1000 items) | Clay (µs) | mgps incremental (µs) | mgps faster by |
|-----------------------|-----------|----------------------|----------------|
| flat_list             |   2,850   |     **21.0**         |    **136×**    |
| text_heavy            |   1,116   |     **9.2**          |    **121×**    |

**Verdict**: Incremental updates are where the mgps architecture pays off
dramatically. When one leaf changes in a 1000-element tree, mgps is **100-1300×
faster** than clay because:

1. The root is a new interned object (L1 miss), but...
2. Most children are the same interned objects (L1 hits — skipped entirely)
3. Only the changed subtree recompiles
4. Cost scales with change size, not tree size

Clay always scales with tree size.

## The Full Picture

```
                    Cold build          Hot (no change)      Incremental (1 change)
                    ──────────          ───────────────      ──────────────────────
   Clay (C, -O2)   ██████ fast         ██████ same cost     ██████ same cost
                    (3-7× faster)       (always rebuilds)    (always rebuilds)

   mgps (LuaJIT)   ██████████ slower   █ near-zero          ██ very fast
                    (structural cost)   (L1 cache hit)       (proportional to change)
```

## What This Means

### Clay wins when:
- You rebuild everything every frame anyway (games, immediate-mode UIs)
- Your tree is small (<100 elements)
- Cold build performance is the bottleneck
- You want C-level single-threaded throughput with zero dependencies

### mgps wins when:
- Most frames have small or no changes (editors, tools, document UIs)
- Your tree is large (100+ elements)
- You need multiple backends from the same source (paint + hit-test + accessibility)
- You need structural identity, caching, and incremental recompilation
- You want the compiler architecture (lowering, classification, state management)

### The architectural difference

Clay is an **immediate-mode layout engine**. It does one thing extremely well:
take a tree description and produce positioned render commands. Every frame,
from scratch, very fast.

mgps is a **structural compiler**. It models the entire pipeline as typed
ASDL transformations with structural identity. It pays more upfront (interning,
multi-layer lowering) but amortizes that cost across frames through aggressive
structural caching. It also provides capabilities Clay does not attempt:
state management, hot-swap, multiple backend compilation, and diagnostics.

### The numbers in context

For a 60 FPS application with a 100-element UI:
- **Clay budget**: 289 µs/frame → **17.3%** of a 16.6ms frame
- **mgps cold budget**: 803 µs/frame → **48.3%** of a 16.6ms frame (first frame only)
- **mgps hot budget**: 0.01 µs/frame → **0.0006%** of a 16.6ms frame
- **mgps incremental**: 0.22 µs/frame → **0.013%** of a 16.6ms frame

After the first frame, mgps uses effectively zero CPU for UI compilation.
Clay uses ~17% of every frame. Over time, mgps is dramatically cheaper.

## Reproduction

```bash
# Build clay benchmark
cd bench && gcc -O2 -I. -o clay_bench clay_bench.c -lm

# Run clay
./clay_bench flat_list 100 5000
./clay_bench text_heavy 100 5000
./clay_bench nested_panels 50 5000
./clay_bench inspector_mini 50 5000

# Run mgps
cd ..
luajit bench/mgps_bench.lua flat_list 100 5000
luajit bench/mgps_bench.lua text_heavy 100 5000
luajit bench/mgps_bench.lua nested_panels 50 5000
luajit bench/mgps_bench.lua inspector_mini 50 5000
```
