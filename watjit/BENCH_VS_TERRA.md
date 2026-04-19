# watjit vs Terra

Current benchmark snapshot for the repo-local `watjit` implementation against `terra` on this machine.

## Commands

```bash
luajit ./watjit/bench_vs_terra.lua
luajit ./watjit/bench_fir_vs_terra.lua
luajit ./watjit/bench_matmul_variants.lua
```

## What changed before these numbers

- `watjit.wasmtime` now uses `wasmtime_func_call_unchecked` automatically for numeric-only signatures.
- exported funcs/memories are copied out of `wasmtime_extern_t` before deletion.
- `watjit.matmul` now has:
  - scalar generation
  - threshold-based scalar K-unrolling
  - explicit SIMD microkernels using `f64x2` across output columns
- `watjit.simd` now exists with first-class vector types:
  - `f32x4`
  - `f64x2`
  - `i32x4`
- `watjit.fir` now has both:
  - scalar kernel generation
  - explicit SIMD FIR generation using `f64x2`

## Matmul: watjit vs Terra

Output from `luajit ./watjit/bench_vs_terra.lua`:

```text
watjit vs terra — matmul
case             sc cmp     sc run     sd cmp     sd run      terra     sc/t     sd/t
--------------------------------------------------------------------------------------------
16x16x16          5.708      0.664      2.208      0.305      0.352     1.89x     0.87x
32x32x32          1.902      1.323      1.825      0.680      1.074     1.23x     0.63x
64x64x64          1.217      1.432      1.525      0.773      1.346     1.06x     0.57x
```

Interpretation:

- Scalar watjit is in the same ballpark as Terra.
- SIMD watjit is now better than Terra on these matmul cases on this machine.
- The explicit `f64x2` output-column microkernel is the first major proof that watjit SIMD pays off.
- `sc cmp` / `sd cmp` are honest Wasmtime compile+instantiate times.

## Matmul variants inside watjit

Output from `luajit ./watjit/bench_matmul_variants.lua`:

```text
watjit matmul variants
case              loop    unroll      simd       l/u       l/s       u/s
----------------------------------------------------------------------------
16x16x16         0.781     0.952     0.306      0.82x      2.55x      3.11x
32x32x32         1.208     2.190     0.700      0.55x      1.73x      3.13x
64x64x64         1.836     2.487     0.765      0.74x      2.40x      3.25x
```

Interpretation:

- scalar K-unrolling is not the main win here.
- explicit SIMD is the clear winner for all three cases.
- the right direction for matmul is now obvious: vector microkernels, not more scalar unrolling.

## FIR: watjit vs Terra

Output from `luajit ./watjit/bench_fir_vs_terra.lua`:

```text
watjit vs terra — FIR
case             sc cmp     sc run     sd cmp     sd run      terra     sc/t     sd/t
--------------------------------------------------------------------------------------------
8/4096            4.910      1.676      1.908      1.112      0.329     5.09x     3.38x
16/4096           1.810      3.745      1.521      1.767      0.602     6.22x     2.94x
32/4096           1.647      6.945      1.896      2.932      0.728     9.54x     4.03x
```

Interpretation:

- Terra is still clearly stronger here.
- But explicit SIMD in watjit helps a lot.
- SIMD FIR cuts the watjit/Terra gap substantially compared to the scalar FIR kernel.
- LLVM still appears to be doing better codegen/vectorization on this style of kernel.
- FIR remains the benchmark that most clearly shows where further SIMD/codegen work is needed.

## Current conclusion

watjit is already competitive enough to be real.

- For matmul, explicit SIMD now makes watjit very competitive and in these cases faster than Terra on this machine.
- For FIR, Terra remains ahead, but explicit SIMD already improved watjit materially.
- The main next optimization targets are:
  - richer SIMD support (`f32x4`, shuffles, selects, comparisons)
  - better FIR/vector reduction patterns
  - more SIMD microkernels in domain code

watjit is no longer "just an idea". The numbers are real; now the work is in refinement.
