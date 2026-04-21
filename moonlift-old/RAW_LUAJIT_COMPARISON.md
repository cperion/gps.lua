# Moonlift vs Terra vs raw LuaJIT

This document records a direct three-way comparison using the checked-in benchmark scripts:

- Moonlift: `examples/bench_moonlift_vs_terra.lua`
- Terra: `examples/bench_terra.lua`
- raw LuaJIT: `examples/bench_luajit_raw.lua`
- fair Collatz follow-up:
  - Moonlift: `examples/fair_bench.lua`
  - Terra: `examples/terra_fair.lua`
  - raw LuaJIT: `examples/fair_luajit_raw.lua`

## How to run

```bash
cd moonlift
cargo build --release
./target/release/moonlift run examples/bench_moonlift_vs_terra.lua
terra examples/bench_terra.lua
./target/release/moonlift run examples/bench_luajit_raw.lua
./target/release/moonlift run examples/fair_bench.lua
terra examples/terra_fair.lua
./target/release/moonlift run examples/fair_luajit_raw.lua
```

Or use the combined summary script:

```bash
cd moonlift
./bench_vs_terra_luajit.sh
```

## Notes

- `sum_loop` is **not** a fair Terra runtime benchmark; LLVM folds it aggressively.
- The raw LuaJIT `fib_sum` benchmark intentionally uses **FFI `int64_t`** so it preserves the same wrapped-`i64` semantics as Moonlift and Terra.
- Moonlift now prints exact 64-bit results on the host side, so the old `fib_sum` display mismatch is gone.

## Sample run (current machine)

### Main suite

| kernel | Moonlift (s) | Terra (s) | raw LuaJIT (s) | ML/T | ML/LJ |
|---|---:|---:|---:|---:|---:|
| COMPILE_ALL | 0.00278 | 0.03660 | 0.00000 | 0.08x | n/a |
| sum_loop | 0.06012 | 0.00000 | 0.08104 | n/a | 0.74x |
| collatz | 0.93966 | 0.46158 | 2.21121 | 2.04x | 0.42x |
| mandelbrot | 0.03633 | 0.02937 | 0.03353 | 1.24x | 1.08x |
| poly_grid | 0.00112 | 0.00103 | 0.00112 | 1.09x | 1.00x |
| popcount | 0.14830 | 0.06452 | 0.12703 | 2.30x | 1.17x |
| fib_sum | 0.01175 | 0.00586 | 0.70042 | 2.01x | 0.02x |
| gcd_sum | 0.08547 | 0.06596 | 0.15566 | 1.30x | 0.55x |
| switch_sum | 0.05576 | 0.05629 | 0.13761 | 0.99x | 0.41x |

Interpretation:

- `ML/T < 1` means Moonlift is faster than Terra.
- `ML/LJ < 1` means Moonlift is faster than raw LuaJIT.

### Fair Collatz

| runtime | time |
|---|---:|
| Moonlift | 2161.025 ms |
| Terra | 1046.925 ms |
| raw LuaJIT | 4647.666 ms |

Derived ratios:

- Moonlift vs Terra: Moonlift is **2.06x slower**
- Moonlift vs raw LuaJIT: Moonlift is **2.15x faster**
- Terra vs raw LuaJIT: Terra is **4.44x faster**

## Takeaways

### Moonlift vs raw LuaJIT

Moonlift is clearly ahead on:

- `collatz`
- `fib_sum`
- `gcd_sum`
- `switch_sum`

Raw LuaJIT is still competitive or ahead on:

- `mandelbrot`
- `poly_grid`
- `popcount`

### Moonlift vs Terra

Moonlift still has the major compile-time advantage, but Terra remains stronger on most scalar runtime kernels.

Notable current points:

- Moonlift compile is still much faster than Terra compile (about **13.2x** in the latest combined run).
- Canonical `fib_sum` is now exact and stable again.
- `switch_sum` remains a good case for Moonlift's current canonical loop + branchy next-state design.
