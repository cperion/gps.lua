# Benchmark: ui/ vs clay.h

**Date**: 2026-04-14  
**Platform**: x86_64 Linux (Fedora), LuaJIT 2.1, cc -O2  
**Clay version**: 0.14 (single-header C)  
**ui/**: current HEAD (`bench/ui_bench_lib.lua`, `bench/ui_clay_compare.lua`)

## What is being compared

`clay.h` is a C immediate-mode layout engine. Every frame it rebuilds the tree,
measures/layouts it, and returns a render command array.

`ui/` is the current pvm-native UI stack. For the comparison benchmark we measure
**compiler-only** work on the `ui/` side:

1. build authored ASDL (`build_auth`) — reported separately
2. lower authored UI to layout (`ui.lower.phase`)
3. render layout to flat op stream (`ui.render.root` drained to an array)

This keeps the comparison closer to Clay's scope. The Love runtime / draw driver
is **not** included in the `ui/` vs Clay comparison script.

## Workloads

Shared workloads in both harnesses:

- `flat_list` — header + stacked cards with title/detail text
- `text_heavy` — header + wrapped paragraph cards
- `nested_panels` — header + groups containing 6 cards each

## Reproduction

```bash
# Build Clay harness (script also tries to build this automatically)
cc -O2 -I./bench -o bench/clay_bench bench/clay_bench.c -lm

# Run comparison
luajit bench/ui_clay_compare.lua all
```

## Sample results

Output from:

```bash
luajit bench/ui_clay_compare.lua all
```

### flat_list (n=200)

| Metric | Time (µs/op) |
|---|---:|
| Clay frame | 106.00 |
| ui build_auth | 1538.02 |
| ui compile cold | 34124.25 |
| ui compile hot | 15.90 |
| ui compile incr | 463.78 |

- Cold: **Clay faster by 321.9×**
- Hot: **ui faster by 6.7×**
- Incremental: **Clay faster by 4.4×**

### text_heavy (n=120)

| Metric | Time (µs/op) |
|---|---:|
| Clay frame | 52.18 |
| ui build_auth | 380.42 |
| ui compile cold | 10081.95 |
| ui compile hot | 5.80 |
| ui compile incr | 129.10 |

- Cold: **Clay faster by 193.2×**
- Hot: **ui faster by 9.0×**
- Incremental: **Clay faster by 2.5×**

### nested_panels (n=40)

| Metric | Time (µs/op) |
|---|---:|
| Clay frame | 179.58 |
| ui build_auth | 2298.15 |
| ui compile cold | 40084.20 |
| ui compile hot | 16.99 |
| ui compile incr | 308.13 |

- Cold: **Clay faster by 223.2×**
- Hot: **ui faster by 10.6×**
- Incremental: **Clay faster by 1.7×**

## Interpretation

Current `ui/` behaves very differently from the old `mgps` comparison in
`bench/RESULTS.md`.

What the updated numbers say:

- **Cold compile**: Clay wins by a very large margin.
- **No-op hot compile**: `ui/` is faster, but by roughly **7-10×**, not
  four orders of magnitude.
- **Current incremental compile benchmark**: `ui/` still does substantial work;
  it does **not** yet beat Clay on these change workloads.

That means the present `ui/` stack is already good at **skipping totally
unchanged frames**, but it is **not yet in the “tiny changed subtree costs almost
nothing” regime** that the older mgps/clay writeup demonstrated.

## Important caveat

`bench/RESULTS.md` is a historical document for the older `mgps` benchmark
harness. It should not be read as representing the current `ui/` stack.

For the current system, use:

- `bench/ui_bench.lua`
- `bench/ui_hot_profile.lua`
- `bench/ui_cold_profile.lua`
- `bench/ui_clay_compare.lua`
- this document
