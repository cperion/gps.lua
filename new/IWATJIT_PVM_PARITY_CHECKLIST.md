# iwatjit pvm parity checklist

*Implementation checklist.*

This document answers one question:

> What must exist in `iwatjit` before a speed comparison against `pvm` is
> architecturally meaningful?

The point is not to compare “something native” against `pvm`.
The point is to compare:

> **the same architectural tricks, on a stronger implementation substrate**

So this checklist is the parity gate.

---

## The rule

A benchmark only really means what we want if `iwatjit` preserves the winning
`pvm` semantics:

- canonical structural identity
- identity-keyed phase caching
- lazy miss recording
- shared in-flight readers
- commit-on-full-drain
- cheap seq-hit replay
- bounded arg-cache policy
- flat committed outputs
- reuse diagnostics

If a comparison is missing one of these, the result may still be interesting,
but it is **not** yet a fair “pvm successor” comparison.

---

## Status legend

- **DONE** — implemented in active `iwatjit/`
- **PARTIAL** — exists, but not yet at the right architectural level
- **MISSING** — not implemented yet in the active path

---

## 1. Canonical structural identity

### Why it matters

This is the biggest one.

`pvm` gets real reuse because unchanged authored structure is literally the same
canonical ASDL value. That makes cache keying cheap and correct.

Without canonical structure, the same logical tree becomes fresh runtime nodes,
and identity-keyed caches cannot show the same reuse behavior.

### `pvm` trick

- ASDL `unique`
- structural interning
- unchanged subtree identity survives updates

### `iwatjit` status

**DONE / PARTIAL**

Done for the ASDL-centered path:

- active GC-backed ASDL values now carry stable native-ref metadata for unique
  values (`__ref_class_id` on classes, `__slot` on canonical values)
- active `iwatjit` can use those canonical ASDL identities directly for cache
  lookup and comparison workloads
- the comparison suite now uses ASDL-backed trees for the runtime-vs-runtime
  path, so reuse ratios line up structurally with `pvm`

Still partial at the larger architecture level:

- a fully native/non-GC canonical interned node world for `iwatjit` itself does
  not yet exist
- outside ASDL-backed workloads, users can still fall back to plain Lua node
  identity and lose the full structural-sharing benefit

### What must still be implemented

- eventually, a real canonical/native interned node runtime for `iwatjit`
  itself, if we want the whole system to stop depending on GC ASDL identity for
  the centerpiece structural-sharing story

### Expected perf effect

Huge.

This is the main gate for getting `iwatjit` back to `pvm`-level reuse behavior.
Without this, hit ratios and reuse ratios are fundamentally disadvantaged.

---

## 2. Cache key = structural identity + explicit arg dimensions

### Why it matters

The cache key is not just the node.
It is:

```text
(phase, structural_key, explicit_arg_key)
```

Volatile args like widths must not accumulate unbounded history unless the phase
really wants that.

### `pvm` trick

- `args_cache = "full" | "last" | "none"`

### `iwatjit` status

**PARTIAL**

The runtime caches on node + args, and the machine-spec layer already models
cache policy as explicit spec data, but the active runtime path has not yet been
cleanly upgraded to the newer `full/last/none` vocabulary and bounded arg
retention discipline everywhere.

### What must be implemented

- unify active runtime arg policy with the newer machine-spec language
- ensure per-phase arg retention policy is explicit and bounded
- add direct comparison benches for volatile-width style workloads

### Expected perf effect

Large for real UIs / measure/render phases.
This is more about bounded memory and stable long-run behavior than microbench
speed alone.

---

## 3. Lazy miss recording

### Why it matters

On miss, work should not be eagerly materialized if the consumer may only pull a
prefix. Recording should happen while consumption proceeds.

### `pvm` trick

- miss returns recording triplet
- recording fills as elements are demanded

### `iwatjit` status

**DONE**

Active `iwatjit` runtime supports recording streams on miss.

Validated by:

- `iwatjit/test_phase.lua`
- `iwatjit/test_recording.lua`

### Expected perf effect

Essential for semantic parity.
Also avoids fake eager work on partial consumers.

---

## 4. Shared in-flight readers

### Why it matters

If two consumers ask for the same uncached result while the first recording is
still in progress, re-running is wrong and slow.

### `pvm` trick

- shared pending recording
- repeated lookup while recording increments `shared`

### `iwatjit` status

**DONE**

Active runtime supports shared in-flight recording behavior.

Validated by:

- `iwatjit/test_recording.lua`
- `iwatjit/test_phase.lua`

### Expected perf effect

Very important for nested reuse and repeated demand during the same outer pass.

---

## 5. Commit on full drain only

### Why it matters

A partially consumed miss must not publish an incomplete cached result.

### `pvm` trick

- commit only when the recording fully exhausts
- partial drain re-evaluates later

### `iwatjit` status

**DONE**

Active runtime respects cancel / non-commit behavior.

Validated by:

- `iwatjit/test_recording.lua`
- partial/cancel behavior visible in `iwatjit/compare_suite.lua`

### Expected perf effect

Correctness first. Also essential for safe lazy replay semantics.

---

## 6. Cheap seq-hit replay

### Why it matters

This is the gold path.
If cached hits are not extremely cheap, the whole memoized architecture loses a
lot of value.

### `pvm` trick

- hit path collapses to flat seq replay
- very small loop over cached array

### `iwatjit` status

**DONE / IMPROVING**

Done semantically:

- active runtime has committed cached-seq replay
- staged native seq-hit terminals exist

Improving operationally:

- the ASDL-centered hit path now uses the same winning lookup trick as `pvm`
  first: weak-key canonical-object hit lookup before falling back to native
  handle lookup
- direct cached-seq terminals can use stored metadata (`count`, first element,
  cached sum) for the simplest hit cases
- on the current ASDL-centered benchmark, `iw runtime cached hit` now beats
  `pvm cached hit`

Validated by:

- `iwatjit/test_seq_hit.lua`
- `iwatjit/test_native_seq_hit.lua`

### What must be improved

- reduce replay overhead on cached hits
- compare terminal-by-terminal (`count`, `sum`, `one`, `drain`)
- isolate lookup cost vs replay loop cost vs terminal cost

### Expected perf effect

Huge.
This is likely the cleanest place for `watjit` to beat `pvm` once tuned.

---

## 7. Flat committed outputs

### Why it matters

Replay wants contiguous flat results.
Nested runtime structures make hit paths expensive.

### `pvm` trick

- flatten recursive meaning to flat terminal outputs
- cached hits replay flat arrays

### `iwatjit` status

**DONE**

Active runtime uses flat scalar numeric seqs / slab-backed result storage for
current runtime paths.

Validated by:

- `iwatjit/test_slab_seq.lua`
- seq-hit tests

### Expected perf effect

Fundamental replay-path win.

---

## 8. Bounded result ownership + eviction

### Why it matters

A successor is not enough if it is fast but unbounded.
Bounded ownership is part of the point.

### `pvm` trick

`pvm` itself is GC/weak-table driven and not strongly bounded, so this is where
`iwatjit` is intended to go beyond `pvm`.

### `iwatjit` status

**DONE**

Active runtime supports:

- global result LRU eviction
- per-phase bounded caches
- memory accounting

Validated by:

- `iwatjit/test_eviction.lua`
- `iwatjit/test_phase_bounded.lua`
- `iwatjit/test_phase_memory.lua`

### Expected perf effect

Mainly long-run stability / bounded memory rather than microbench speed.
Can also improve locality if tuned well.

---

## 9. Native cache table path

### Why it matters

Once semantics match, the next speed lever is replacing Lua hash/table paths
with native typed tables.

### `pvm` trick

`pvm` uses Lua weak tables because that is the right tool in that system.

### `iwatjit` status

**PARTIAL**

There is native table machinery in the runtime, but this path needs to become
more central and better integrated with the canonical structural-handle world.

### What must be implemented

- make native lookup the default for canonical node handles
- benchmark lookup separately from replay
- ensure arg-key policy layers cleanly over native lookup

### Expected perf effect

Potentially large on hot call-heavy boundaries.

---

## 10. Reuse diagnostics comparable to `pvm.report`

### Why it matters

If we cannot see reuse clearly, we will optimize blind.

### `pvm` trick

- `calls`
- `hits`
- `shared`
- `reuse_ratio`

### `iwatjit` status

**DONE / PARTIAL**

Done:

- runtime reports calls/hits/shared/misses/seq_hits/commits/cancels/evictions
- memory stats exist

Partial:

- cross-system comparison is still awkward because the two systems count work at
  somewhat different granularities in current workloads

### What must be improved

- normalize comparison metrics in `iwatjit/compare_suite.lua`
- add side-by-side derived metrics like hit %, reuse %, bytes/live-entry

### Expected perf effect

No direct runtime speed effect, but critical for knowing whether we are really
matching `pvm` structurally.

---

## 11. Machine-spec layer on top of runtime

### Why it matters

This is not a `pvm` trick exactly. This is the new authoring goal.
But it must not come at the cost of runtime completeness.

### `iwatjit` status

**DONE as overlay**

The active `iwatjit/` now has:

- full runtime path
- machine-spec overlay:
  - `iw.phase { ... }`
  - `iw.scalar_phase { ... }`
  - `iw.terminal { ... }`

Validated by:

- `iwatjit/test_machine_spec.lua`

### Expected perf effect

Mostly authoring clarity / future codegen leverage.
Indirect speed benefit if it helps us generate tighter machine layouts and
better native kernels.

---

## Benchmark readiness summary

## Architecturally ready now

These are already present in active `iwatjit`:

- lazy miss recording
- shared in-flight readers
- commit-on-full-drain semantics
- cached seq replay
- bounded result ownership / eviction
- memory accounting
- machine-spec overlay

## Still blocking a truly fair “pvm successor” comparison

### A. canonical structural identity
This is the biggest remaining parity gate.

### B. fully explicit arg-cache policy parity
Needed especially for real UI-like workloads.

### C. optimized cached-hit replay path
Semantically present, but still needs tuning if it is to clearly beat `pvm`.

### D. normalized reporting / comparison metrics
Needed to reason about parity cleanly.

---

## Priority order

### Priority 1 — canonical structure
Until this exists, some runtime-vs-runtime comparisons are fundamentally not
measuring equivalent reuse architectures.

### Priority 2 — cached-hit replay optimization
Once identity parity exists, optimize the hit path until it beats `pvm` on fair
workloads.

### Priority 3 — arg-policy parity
Bring `full/last/none` explicitly into active runtime behavior.

### Priority 4 — report normalization
Make the comparison suite print derived metrics that line up across systems.

---

## One-line thesis

`iwatjit` benchmarking matters when it is no longer “something native”, but:

> **the same structural-sharing + recording + seq-hit architecture as `pvm`,
> rebuilt on typed native memory and compiled replay terminals**
