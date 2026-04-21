# Cranelift IR Explorations

This document records the direct Cranelift IR experiments carried out while investigating how Moonlift can emit better code for Cranelift, especially in places where LLVM/Terra still wins on runtime benchmarks.

The goal of these experiments was **not** to benchmark Moonlift itself, but to answer a more precise question:

> Given explicit Cranelift IR, what shapes, instructions, and combinations produce good machine code, and where does Cranelift still need better frontend help than LLVM?

---

## Scope and method

These experiments were run in a temporary standalone Rust crate under:

- `/tmp/clifplay`

The crate:

- built CLIF directly with `cranelift-frontend`
- targeted the host ISA via `cranelift-native`
- used `opt_level = speed`
- dumped both:
  - **CLIF** (`ctx.func.display()`)
  - **vcode / machine-ish disassembly** (`compiled_code().vcode`)

So the observations below are about:

- Cranelift IR shape
- Cranelift legalization / instruction selection
- emitted x86-64 machine patterns on the current host

They are **not** abstract guesses; they are based on direct CLIF and vcode inspection.

---

## High-level conclusions

The strongest overall conclusion is:

> Cranelift likes **explicit CFG shape**, **explicit address shape**, and **explicit target-friendly operations**.

More concretely:

- **Dense integer switch** should be emitted as structured switch, not nested `if` or nested `select`.
- **Branchy loop-carried state** should stay as CFG + latch, not expression soup.
- **Indexed loads/stores** should preserve base/index/scale/offset shape as long as possible.
- **Cheap scalar two-way choice** is a good fit for `select`.
- **Expensive or multi-arm choice** is usually a bad fit for `select`.
- **Bit ops and special arithmetic ops** (`popcnt`, `clz`, `ctz`, `rotl`, `bswap`, `fma`, etc.) should be emitted directly when possible.
- **Alias ambiguity** causes Cranelift to get conservative very quickly.
- **Constant division/modulo** is fairly good; **variable quotient+remainder together** is still weak.
- **Narrow induction/index types** are often preferable if semantically valid.

---

## Experiment list

The direct experiments covered all of the following functions:

### Control-flow / switch / selection

- `dense_switch`
- `sparse_switch`
- `select_chain`
- `select_add`
- `branch_add`

### Indexing / loops / induction width

- `scaled_index_load`
- `scaled_index_load_i32_index`
- `loop_sum`
- `loop_sum_i32`
- `sum_array_i32_index`
- `sum_array_i64_index`
- `branchy_latch_like`

### Scalar arithmetic / comparisons

- `smax_direct`
- `max_via_select`
- `clamp_smax_smin`
- `affine_mix`

### Bit / low-level integer ops

- `popcnt_direct`
- `clz_ctz_mix`
- `rotate_bswap`
- `mod8_eqzero_srem`
- `mod8_eqzero_band`
- `sdiv8`
- `srem8`
- `overflow_add_trap`

### Float / numeric conversions

- `fma_direct`
- `mul_add`
- `fmin_direct`
- `fmin_via_select`
- `clamp_f64`
- `fcvt_sat`

### Memory / alias / bounds

- `repeated_load`
- `load_store_forward`
- `load_store_other_reload`
- `load_store_other_reload_split_regions`
- `trap_bounds_load`

### SIMD / vector

- `vector_add_extract`
- `vector_load_unaligned`
- `vector_load_aligned`
- `splat_scalar_add`
- `lane_insert_extract`
- `sat_add_i8` (vector-packed saturating add experiment)

---

# 1. Control flow, switch lowering, and selection

## 1.1 `dense_switch`

### Shape emitted
A dense integer dispatch on `0..6` was emitted using `cranelift_frontend::Switch`.

### CLIF result
It lowered to a real `br_table`:

```clif
br_table v0, block9, [block2, block3, block4, block5, block6, block7, block8]
```

### vcode result
The x86-64 lowering used a clamp/guard plus jump-table dispatch:

```asm
cmpl %eax, %ecx
cmovbl %ecx, %eax
br_table %rax, %rcx, %rax
```

### Observation
Cranelift handles dense switch dispatch well when given structured switch IR.

### Moonlift implication
For dense integer/tag dispatch, Moonlift should prefer a real switch IR form instead of lowering to nested `If` or nested `Select`.

---

## 1.2 `sparse_switch`

### Shape emitted
Structured switch over sparse keys:

- `0, 10, 20, 30, 40, 50`

### CLIF result
Cranelift built a compare tree rather than a jump table.

### vcode result
Reasonable compare/jump sequence, e.g.:

```asm
cmpl $0x1e, %edi
jnb ...
cmpl $0x14, %edi
jz ...
cmpl $0xa, %edi
jz ...
```

### Observation
Even when it does **not** become a jump table, `Switch` still gives Cranelift a better dispatch problem than nested expression lowering.

### Moonlift implication
A structured integer switch IR still makes sense for sparse switches.

---

## 1.3 `select_chain`

### Shape emitted
A many-arm nested `select` chain returning constants.

### CLIF result
Cranelift preserved nested `select` nodes.

### vcode result
It became a branchless sequence of compares and conditional moves, but with RIP-relative constant loads:

```asm
cmpl $0x6, %edi
cmoveq (%rip), %rax
cmpl $0x5, %edi
cmoveq (%rip), %rax
...
```

### Observation
This is branchless, but not especially elegant:

- many compares
- many cmovs
- many literal loads

### Moonlift implication
Nested `select` chains are **not** a good substitute for real switch lowering.
Use `select` only for small cheap two-way scalar choices.

---

## 1.4 `select_add`

### Shape emitted
Two cheap scalar arms computed eagerly, then selected:

```clif
a = x + 1
b = x + 3
out = select(cond, a, b)
```

### vcode result
Excellent branchless lowering:

```asm
leaq 1(%rdi), %rsi
leaq 3(%rdi), %rax
testq $0x1, %rdi
cmoveq %rsi, %rax
```

### Observation
`select` is very good when both arms are cheap scalar arithmetic.

### Moonlift implication
Use `Select` for cheap arithmetic two-way choices.

---

## 1.5 `branch_add`

### Shape emitted
Same logic as `select_add`, but as explicit CFG branches.

### vcode result
Straight branch form:

```asm
testq $0x1, %rdi
jz ...
leaq 3(%rdi), %rax
...
leaq 1(%rdi), %rax
```

### Observation
Branch version is fine, but the branchless `select_add` version is cleaner for this tiny case.

### Moonlift implication
- cheap two-way scalar choice -> `Select`
- branchy/memory-heavy/expensive arms -> CFG

---

# 2. Addressing, loops, and induction width

## 2.1 `scaled_index_load`

### Shape emitted

```clif
scaled = ishl idx, 2
addr   = iadd base, scaled
load.i32 addr+8
```

### vcode result
Perfect x86 addressing fusion:

```asm
movl 8(%rdi, %rsi, 4), %eax
```

### Observation
Preserving base/index/scale/offset shape works extremely well.

### Moonlift implication
This strongly validates the `IndexAddr` / late-address-formation direction.

---

## 2.2 `scaled_index_load_i32_index`

### Shape emitted
An `i32` index was zero-extended before address formation:

```clif
idx64 = uextend.i64 idx32
scaled = ishl idx64, 2
...
```

### vcode result
Still fused nicely:

```asm
movl %esi, %esi
movl 8(%rdi, %rsi, 4), %eax
```

### Observation
Cranelift handles narrow indices well.

### Moonlift implication
Do not over-widen induction/index types unless necessary.
Using `i32/u32` indices can still generate excellent addressing code.

---

## 2.3 `loop_sum`

### Shape emitted
Block-param loop with `i64` induction/state.

### vcode result
Clean compare/backedge recurrence with `lea`:

```asm
cmpq %rdi, %rdx
jl ...
leaq 1(%rdx), %rcx
leaq 1(%rax, %rdx), %rax
```

### Observation
Cranelift likes explicit block-param loops very much.

### Moonlift implication
The current Moonlift move toward block-param-style canonical loop lowering is correct.

---

## 2.4 `loop_sum_i32`

### Shape emitted
Same loop as above, but `i32` induction/state.

### vcode result
Narrower version:

```asm
cmpl %edi, %edx
leal 1(%rdx), %ecx
leal 1(%rax, %rdx), %eax
```

### Observation
Narrow induction stays narrow and looks good.

### Moonlift implication
Prefer narrow induction when semantically valid.

---

## 2.5 `sum_array_i32_index`

### Shape emitted
Array-sum loop with `i32` induction and explicit widening for addressing.

### vcode result
Very clean loop body:

```asm
cmpl %esi, %r8d
movl %r8d, %ecx
leal 1(%r8), %r8d
addl (%rdi, %rcx, 4), %eax
```

### Observation
`i32` induction plus scaled addressing is excellent.

### Moonlift implication
For bounded arrays/slices, `i32` induction variables are attractive when semantically legal.

---

## 2.6 `sum_array_i64_index`

### Shape emitted
Same idea, but `i64` induction.

### vcode result
Still good, but wider:

```asm
cmpq %rsi, %r8
leaq 1(%r8), %rcx
addl (%rdi, %r8, 4), %eax
```

### Observation
Good code, but not obviously better than the narrow-index form.

### Moonlift implication
Prefer narrow induction/index types where possible.

---

## 2.7 `branchy_latch_like`

### Shape emitted
A loop with branchy state update through a dedicated latch block.

### vcode result
Very clean machine shape:

```asm
testq $0x1, %rdx
jz ...
leaq 3(%rax), %rax
...
leaq 1(%rax), %rax
...
leaq 1(%rdx), %rdx
```

### Observation
Cranelift likes branchy carried-state expressed as CFG + latch, not as a giant value expression.

### Moonlift implication
This strongly supports the current direction for branchy `next` state: explicit CFG/latch structure rather than giant `Vec<Expr>`-style selection trees.

---

# 3. Scalar arithmetic and integer helpers

## 3.1 `smax_direct`

### Shape emitted
Direct `smax`.

### vcode result

```asm
cmpq %rdi, %rsi
movq %rdi, %rax
cmovgeq %rsi, %rax
```

### Observation
Direct min/max ops map well.

---

## 3.2 `max_via_select`

### Shape emitted
Compare + `select(x, y)`.

### CLIF result
Cranelift canonicalized it to `smax`.

### vcode result
Same as `smax_direct`.

### Observation
Cranelift already recognizes this scalar idiom.

### Moonlift implication
Moonlift probably does not need heavy custom rewriting for trivial compare+select max/min cases.

---

## 3.3 `clamp_smax_smin`

### Shape emitted
Clamp via `smax(x, 0)` then `smin(..., 100)`.

### vcode result
Two compares with cmovs.

### Observation
Cranelift handles integer clamp idioms well if expressed directly via min/max.

### Moonlift implication
Useful candidate for future `min/max/clamp` builtins or canonical lowering patterns.

---

## 3.4 `affine_mix`

### Shape emitted

```clif
x*3 + y*5 + 7
```

### vcode result

```asm
imulq $0x3, ...
imulq $0x5, ...
leaq 7(%rsi, %rdi), %rax
```

### Observation
Cranelift did not aggressively rewrite small multiplies into shift/add/lea chains; it kept `imul` and then used `lea` for the final combine.

### Moonlift implication
Do not assume Cranelift will always strength-reduce every small constant multiply. Profile before inventing frontend strength reduction.

---

# 4. Bit operations and checked arithmetic

## 4.1 `popcnt_direct`

### Shape emitted
Direct `popcnt`.

### vcode result

```asm
popcntq %rdi, %rax
```

### Observation
Excellent direct lowering.

### Moonlift implication
Expose `popcnt` directly if possible; this is a strong candidate for narrowing the `popcount` benchmark gap.

---

## 4.2 `clz_ctz_mix`

### Shape emitted
Direct `clz` + `ctz`.

### vcode result

```asm
lzcntq %rdi, %rsi
tzcntq %rdi, %rdi
leaq (%rsi, %rdi), %rax
```

### Observation
Again excellent direct lowering.

### Moonlift implication
Expose `clz`/`ctz` directly.

---

## 4.3 `rotate_bswap`

### Shape emitted
Rotate-left by 13, then byte-swap.

### vcode result

```asm
rorxq $0x33, %rdi, %rax
bswapq %rax
```

### Observation
Cranelift has good direct lowering for rotate and byte-swap.

### Moonlift implication
Direct low-level bit builtins are worthwhile:

- `rotl`
- `rotr`
- `bswap`

---

## 4.4 `overflow_add_trap`

### Shape emitted
Direct checked unsigned add:

```clif
uadd_overflow_trap x, y, user9
```

### vcode result

```asm
addq %rsi, %rax
jb #trap=user9
```

### Observation
This is excellent checked-arithmetic lowering.

### Moonlift implication
If Moonlift ever wants explicit checked integer math builtins, Cranelift already has a very strong backend path.

---

# 5. Float operations and conversions

## 5.1 `fma_direct`

### Shape emitted
Direct fused multiply-add.

### vcode result

```asm
vfmadd213sd (%rip), %xmm1, %xmm0
```

### Observation
Cranelift will happily emit FMA if asked directly.

### Moonlift implication
Explicit `fma` is a real opportunity for float-heavy kernels.

---

## 5.2 `mul_add`

### Shape emitted
Separate multiply then add.

### vcode result

```asm
vmulsd %xmm1, %xmm0, %xmm4
vaddsd (%rip), %xmm4, %xmm0
```

### Observation
Cranelift did **not** fuse `fmul + fadd` into FMA on its own.

### Moonlift implication
If Moonlift wants FMA codegen, it should emit `fma` explicitly or add a fast-math-style transformation.

---

## 5.3 `fmin_direct`

### Shape emitted
Direct semantic `fmin`.

### vcode result
Cranelift used a more semantic-aware min sequence:

```asm
xmm min seq f64 ...
```

### Observation
This preserves proper `fmin` semantics better than a naïve compare+select.

---

## 5.4 `fmin_via_select`

### Shape emitted
`fcmp lt` + `select`.

### vcode result

```asm
vminsd %xmm1, %xmm0, %xmm0
```

### Observation
This is shorter and nicer-looking, but not equivalent to true `fmin` under NaN/edge semantics.

### Moonlift implication
There is a real design split here:

- precise `fmin/fmax`
- fast min/max via compare+select / fast-math

Moonlift could eventually expose both surfaces.

---

## 5.5 `clamp_f64`

### Shape emitted
Clamp with `fmax(x, 0.0)` then `fmin(..., 1.0)`.

### vcode result
A good semantic clamp sequence with max then min.

### Observation
Direct float min/max clamp emits reasonably well.

### Moonlift implication
`clamp`-style float builtins are viable.

---

## 5.6 `fcvt_sat`

### Shape emitted
Saturating float-to-int conversion.

### vcode result
Cranelift used a dedicated saturating conversion sequence macro.

### Observation
Cranelift has real support for saturating conversions.

### Moonlift implication
If Moonlift exposes saturating conversions, Cranelift can support them directly.

---

# 6. Division, remainder, and power-of-two cases

## 6.1 `divrem_imm`

### Shape emitted
`q = sdiv_imm x, 7` and `r = srem_imm x, 7`.

### vcode result
Cranelift produced a reciprocal-multiply / high-multiply based sequence and reused work sensibly.

### Observation
Constant division/modulo lowering is pretty good.

### Moonlift implication
Preserve constant divisors as immediates whenever possible.

---

## 6.2 `divrem_var`

### Shape emitted
`q = sdiv x, y`, `r = srem x, y`.

### vcode result
Two separate sequences:

- full divide path for quotient
- separate remainder path (`checked_srem_seq`)

### Observation
Cranelift did **not** combine quotient and remainder into one shared divide result.

### Moonlift implication
This is a likely LLVM advantage area.
A future Moonlift internal `DivRem`-style node could help.

---

## 6.3 `mod8_eqzero_srem`

### Shape emitted
`(x % 8) == 0` using signed remainder.

### vcode result
A fairly involved signed-correction sequence.

### Observation
Signed `% power_of_two` is not a cheap bit-test in general because signed remainder semantics require correction.

### Moonlift implication
Do **not** lower obvious power-of-two divisibility tests through signed remainder when a bitwise test is semantically valid.

---

## 6.4 `mod8_eqzero_band`

### Shape emitted
`(x & 7) == 0`.

### vcode result
Excellent:

```asm
testq $0x7, %rdi
sete ...
```

### Observation
This is far better than the signed remainder form when semantics allow it.

### Moonlift implication
Recognize / preserve bit-test forms for power-of-two divisibility and masking logic.

---

## 6.5 `sdiv8`

### Shape emitted
Signed divide by `8`.

### vcode result
Bias/correction plus shift sequence.

### Observation
Signed division by power-of-two still needs correction logic; it is not always just `sar`.

### Moonlift implication
If Moonlift can prove nonnegative or unsigned semantics, it may be able to emit cheaper forms.

---

## 6.6 `srem8`

### Shape emitted
Signed remainder by `8`.

### vcode result
Again a corrected sequence, not just `and 7`.

### Observation
Same lesson: signed semantics matter.

### Moonlift implication
Unsigned/nonnegative knowledge is valuable for modulo lowering.

---

# 7. Memory, aliasing, and bounds checks

## 7.1 `repeated_load`

### Shape emitted
Two identical loads from the same address with no intervening store.

### vcode result
Only one load remained.

### Observation
Cranelift can CSE repeated loads in simple cases.

### Moonlift implication
Good news, but only when alias conditions stay simple.

---

## 7.2 `load_store_forward`

### Shape emitted
Store then reload from the same address.

### vcode result
Reload eliminated; stored value returned directly.

### Observation
Store-to-load forwarding for obvious same-address cases is strong.

### Moonlift implication
This is good for stack slots / obvious locals.

---

## 7.3 `load_store_other_reload`

### Shape emitted
Load from `p`, store to `q`, reload from `p`.

### vcode result
Second load stayed present.

### Observation
Unknown aliasing blocks the optimization.

### Moonlift implication
This is one of the biggest practical lessons from the exploration:

- alias ambiguity is costly
- preserving already-loaded SSA values is important
- reloading through pointers after unrelated stores can hurt

---

## 7.4 `load_store_other_reload_split_regions`

### Shape emitted
Same as above, but with split alias regions (`heap` vs `table`).

### vcode result
Second load was eliminated; the value was reused.

### Observation
Alias metadata can unlock reload elimination.

### Important caveat
Cranelift alias regions are coarse; they are not a general user-pointer noalias system.

### Moonlift implication
Long-term, a stronger noalias/view design could help. Near-term, SSA retention and scalar replacement are likely more important than relying solely on backend memflags.

---

## 7.5 `trap_bounds_load`

### Shape emitted
Compare + trap + indexed load.

### vcode result
Excellent:

```asm
cmpq %rdx, %rsi
jnb #trap=user7
movl (%rdi, %rsi, 4), %eax
```

### Observation
Cranelift likes explicit compare+trap bounds checks.

### Moonlift implication
The current Moonlift explicit-bounds-check path is well aligned with Cranelift.

---

# 8. SIMD / vector explorations

## 8.1 `vector_add_extract`

### Shape emitted
Add two constant `f32x4` vectors, then extract one lane.

### vcode result

```asm
vmovups (%rip), %xmm2
vmovups (%rip), %xmm3
vaddps %xmm3, %xmm2, %xmm0
```

### Observation
Cranelift vector arithmetic works, but constant vectors come from literal-pool loads.

### Moonlift implication
SIMD is viable, but constant-heavy vector code may still pay literal-load costs.

---

## 8.2 `vector_load_unaligned`

### Shape emitted
Load `f32x4`, extract lane 0.

### vcode result

```asm
vmovups (%rdi), %xmm0
```

### Observation
Good simple vector load.

---

## 8.3 `vector_load_aligned`

### Shape emitted
Same as above, but with `aligned` memflag.

### vcode result
Still:

```asm
vmovups (%rdi), %xmm0
```

### Observation
On this target/case, the `aligned` flag did not improve the emitted load instruction.

### Moonlift implication
`aligned` alone is not a silver bullet for vector memory code on Cranelift/x86.

---

## 8.4 `splat_scalar_add`

### Shape emitted
Splat scalar float into vector, add vector to itself, extract a lane.

### vcode result

```asm
vbroadcastss %xmm0, %xmm4
vaddps %xmm4, %xmm4, %xmm4
vpshufd $0x3, %xmm4, %xmm0
```

### Observation
This is a very nice lowering. Cranelift handles `splat` well.

### Moonlift implication
Explicit vector splat is a promising primitive for SIMD-friendly Moonlift code.

---

## 8.5 `lane_insert_extract`

### Shape emitted
Build a vector by repeated `insertlane`, then extract lane 3.

### vcode result

```asm
vmovdqu (%rip), %xmm4
vpinsrd $0x1, (%rip), %xmm4, %xmm4
vpinsrd $0x2, (%rip), %xmm4, %xmm4
vpinsrd $0x3, (%rip), %xmm4, %xmm4
vpextrd $0x3, %xmm4, %eax
```

### Observation
Lane-by-lane constant vector construction is expensive and literal-load-heavy.

### Moonlift implication
Do not construct constant vectors lane-by-lane if whole-vector constants or splats are available.

---

## 8.6 `sat_add_i8` (vector-packed saturating add)

### Shape emitted
Packed saturating add on `i16x8`, then extract lane 0.

### vcode result

```asm
vpaddsw ...
vpextrw ...
```

### Observation
Packed saturating arithmetic is well supported.

### Additional note
Direct scalar `sadd_sat.i8` / `i16` forms were rejected by the verifier in these experiments; the successful path here was vector-packed.

### Moonlift implication
If Moonlift grows SIMD, packed saturating operations could be a strong fit.
Scalar saturating ops may need their own canonical lowering.

---

# 9. Cross-cutting observations

## 9.1 Cranelift strongly rewards explicit structure
This came up repeatedly:

- explicit switch IR -> better dispatch
- explicit loop CFG -> better loop code
- explicit address shape -> fused addressing modes
- explicit bit ops -> direct target instructions
- explicit `fma` -> fused instruction
- explicit bounds trap -> clean compare+trap+load

Cranelift is less interested than LLVM in recovering all of this from frontend-desugared soup.

---

## 9.2 `select` is good, but only in a narrow band
Good fit:

- two-way
- scalar
- cheap arms
- no memory
- no branchy nested state

Bad fit:

- multi-arm dispatch
- expensive arms
- memory-heavy arms
- branchy carried state

This exactly matches the Moonlift loop/switch benchmark experience.

---

## 9.3 Alias ambiguity is a major performance lever
The alias experiments were among the most useful in the entire exploration.

Cranelift is willing to optimize reloads aggressively **when it can prove safety**, but it gets conservative quickly once another store may alias.

This suggests Moonlift performance work should focus not only on loop and switch shape, but also on:

- SSA retention of loaded values
- scalar replacement
- reducing needless pointer reloads
- eventually, richer noalias/view semantics

---

## 9.4 Narrow induction/index types are worth preferring
Using `i32` induction variables where valid produced clean narrow code and still fused addressing well.

Moonlift should not default to wider types in hot loops unless semantics require them.

---

## 9.5 Some LLVM advantages are still visible
Likely LLVM/Terra advantage zones after these experiments:

- variable `div + rem` sharing
- richer arithmetic/algebraic combining
- more aggressive float fusion unless Cranelift is given explicit `fma`
- possibly better vector constant handling in some cases

---

# 10. Direct implications for Moonlift

## Highest-value likely wins

### 1. Structured integer switch IR
This is one of the clearest wins from the experiments.

### 2. Direct low-level bit builtins / pattern preservation
Expose or preserve:

- `popcnt`
- `clz`
- `ctz`
- `rotl`
- `rotr`
- `bswap`

### 3. Explicit `fma`
Especially for float-heavy kernels.

### 4. Keep `IndexAddr` / late address formation
This continues to look like exactly the right direction.

### 5. Keep branchy carried-state in CFG/latch form
Do not collapse it into giant value expressions.

### 6. Prefer narrow induction and narrow index types when valid
Especially `i32/u32` for bounded loops over arrays/slices.

### 7. Reduce reload churn in pointer-heavy code
This could matter as much as loop shape in some workloads.

---

## Medium-value / research directions

### 8. Internal `DivRem`-style node or transform
For cases where both quotient and remainder of the same variable divisor are needed.

### 9. Distinguish precise vs fast float min/max / clamp surfaces
The `fmin_direct` vs `fmin_via_select` experiment shows a real semantic/codegen tradeoff.

### 10. SIMD surface design
SIMD looks viable, but:

- splat is attractive
- lane-by-lane constant construction is unattractive
- vector constants often become literal loads
- packed saturating math is promising

### 11. Explore a real noalias/view model
Not because Cranelift memflags alone solve everything, but because alias semantics shape what Moonlift can safely scalar-replace or keep live in SSA.

---

# 11. Final synthesis

If all of the experiments are compressed into one rule, it is this:

> Moonlift should emit **more semantic operations** and **more structured control/data shape**, not more clever desugared arithmetic soup.

Cranelift performs best when Moonlift preserves and exposes:

- integer switch structure
- loop/latch structure
- address formation structure
- bit-manip structure
- exact numeric operation choice (`fma`, `popcnt`, etc.)
- safe alias separation when it exists

And the places where LLVM still wins most naturally are the places where:

- the IR still hides intent
- the backend would need deeper global recovery/combining
- or quotient/remainder / float-fusion / alias-sensitive simplification are not expressed directly enough

That makes the path forward for Moonlift fairly concrete.
