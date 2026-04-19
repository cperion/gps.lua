# iwatjit

Bounded-memory pvm-successor runtime built on `watjit`, with an additional
spec-first machine-definition surface.

This directory now combines two things:

- the **full runtime** shape restored from the earlier retired `iwatjit`
  experiment: runtime, phase caching, recording/shared/hit behavior,
  seq-hit replay, bounded result ownership, eviction, and reporting
- the newer **machine-spec surface** described in:

- `../new/IWATJIT_MACHINE_SPEC.md`
- `../new/IWATJIT_RUNTIME_LAYOUT.md`
- `../new/IWATJIT_PVM_PARITY_CHECKLIST.md`

## Current scope

### Runtime surface

Implemented and working:

- `iw.runtime(opts?)`
- `iw.phase(rt, name, handlers_or_fn, opts?)`
- `iw.count(plan)`
- `iw.sum(plan)`
- `iw.one(plan, default?)`
- `iw.drain(plan)`
- `iw.open(plan)`
- `iw.phase_stats(phase)`
- `iw.memory_stats(rt)`
- `iw.report_string(rt)`

This runtime supports:

- miss recording
- shared in-flight readers
- committed cached-seq replay hits
- staged native seq-hit terminals
- bounded per-phase caches
- global result LRU eviction
- memory accounting/reporting
- ASDL-backed canonical structural handles (`unique` values expose stable native-ref metadata for cache lookup)

### Machine-spec surface

Also implemented as an overlay on top of the runtime:

- `iw.runtime { memory = ..., tables = ... }`
- `iw.phase { ... }`
- `iw.scalar_phase { ... }`
- `iw.terminal { ... }`
- generated layouts:
  - `Param`
  - `State`
  - `Result`
  - `Entry`
  - `Cursor`
  - `Status`
- wrapper generation helpers:
  - `phase:gen_fn { ... }`
  - `scalar_phase:compute_fn { ... }`
  - `terminal:step_fn { ... }`

So `iwatjit` now has both:

- a **complete runtime path**
- a **spec-first declaration path**

## Example

```lua
local iw = require("iwatjit")
local wj = require("watjit")

local lower = iw.phase {
  name = "lower",
  key_t = wj.i32,
  item_t = wj.i32,

  param = {
    { "node",  wj.i32 },
    { "max_w", wj.i32 },
  },

  state = {
    { "pc",      wj.u8 },
    { "child_i", wj.i32 },
  },

  result = {
    storage = "slab_seq",
    item_t = wj.i32,
  },

  cache = {
    args = "last",
    policy = "bounded_lru",
  },

  gen = function(P, S, emit, R)
    local code = emit(P.node + P.max_w + S.child_i)
    S.child_i(S.child_i + 1)
    return code
  end,
}
```

## Tests

```bash
luajit iwatjit/test_phase.lua
luajit iwatjit/test_recording.lua
luajit iwatjit/test_eviction.lua
luajit iwatjit/test_phase_bounded.lua
luajit iwatjit/test_phase_memory.lua
luajit iwatjit/test_seq_hit.lua
luajit iwatjit/test_native_seq_hit.lua
luajit iwatjit/test_slab_seq.lua
luajit iwatjit/test_asdl_port.lua
luajit iwatjit/test_machine_spec.lua
```

## Comparison bench

```bash
luajit iwatjit/bench_pvm_vs_iw.lua 16384 300
```
