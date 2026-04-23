# CODEGEN_FINDINGS.md — current Cranelift code observed from Moonlift

This document records what the current rebooted Moonlift pipeline actually emits at
machine-code level when compiled through the current Cranelift backend.

The goal is not to judge the backend in the abstract. The goal is to use emitted
machine code as feedback for:

- Moonlift surface forms
- ASDL layer shape
- lowering boundaries
- which semantic facts are preserved or lost too early

This is a machine-code-first companion to the normal lowering docs.

---

## How these findings were obtained

Using the current peek utility:

- `moonlift/lua/moonlift/peek.lua`
- `moonlift/examples/peek_codegen.lua`

Workflow used:

1. author current reboot `MoonliftSurface` ASDL shapes in Lua
2. run the normal lowering pipeline:
   - `Surface -> Elab -> Sem -> resolve_sem_layout -> Back`
3. compile with the current Cranelift backend via `moonlift.jit`
4. grab the final function pointer
5. dump a fixed byte window and disassemble it with `objdump`

Environment observed here:

- host: x86_64
- disassembler: `objdump -D -Mintel -b binary -m i386:x86-64`

Important limitation:

- the peek utility disassembles a fixed number of bytes starting at the function
  entrypoint; it is intended for regular inspection, not exact object reconstruction

---

## Highest-level findings

### 1. The current pipeline already produces useful low-level structure

For scalar arithmetic and basic branchy control flow, Cranelift is already emitting
reasonable code from the current Moonlift lowering.

### 2. The biggest globally visible quality issue is eager argument spilling

Nearly every successfully compiled function starts by materializing arguments into
stack slots, even when the body can stay entirely in registers.

Typical shape:

```asm
sub    rsp,0x10
mov    DWORD PTR [rsp],edi
mov    DWORD PTR [rsp+0x8],esi
```

Float variant:

```asm
vmovsd QWORD PTR [rsp],xmm0
vmovsd QWORD PTR [rsp+0x8],xmm1
```

This means the current lowering/backend contract is effectively treating all params
as immediately addressable locals.

### 3. The previous two hard blockers are now fixed enough to inspect

A second probing pass after lowering fixes shows that the two biggest first-pass blockers
are no longer hard blockers:

- **recursive/direct-call functions** now compile and emit direct self-calls
- **loop-carried benchmark kernels** now compile and emit real loop backedges

That changes the nature of the investigation. The question is no longer “can Moonlift emit
recursive and loop-heavy benchmark kernels at all?” The question is now “how much stack/
slot traffic and control-shape baggage is still visible in those emitted kernels?”

### 4. Typed expr loops with valued `break expr` now compile; the old failure was a sealing-order bug

A follow-up probe on typed `while` and typed `over range(...)` expr loops with valued early exit
now compiles successfully.

The previous crash was not a surface-syntax problem. It was a `Sem -> Back` CFG-order bug:
Moonlift sealed the loop expr `exit` block before the body had finished emitting all possible
`break` edges into that block.

Observed current emitted shape for valued-break loops:

- loop header/body/continue/exit blocks still use block params for carried state/indexes
- expr-loop result selection still uses a break-flag stack slot plus break-value stack slot
- early `break expr` stores the break value, sets the flag, and jumps to the shared exit block
- exit tests the flag and joins either the break value or the normal `end -> expr` result

Moonlift now represents that distinction explicitly in ASDL (`ElabLoopExprExit` / `SemLoopExprExit`).
That matters in codegen: breakless expr loops no longer share this path.

Observed current emitted shape for end-only expr loops after the ASDL split:

- no break-flag stack slot
- no break-value stack slot
- plain block-param recurrence header/body/continue/exit
- exit computes the final `end -> expr` result directly and returns/joins it

So the remaining cost-model issue is now narrower and more honest:
**break-capable expr loops** still pay explicit break-result machinery, while **breakless expr loops**
no longer do.

---

## Successful shapes and what Cranelift emitted

## A. Simple add

Shape:

```text
add1(x) = x + 1
```

Observed code:

```asm
mov    DWORD PTR [rsp],edi
lea    eax,[rdi+0x1]
```

### Finding

Good:

- addition by constant lowered to `lea`

Bad:

- dead arg spill remains visible

---

## B. `if` expression

Shape:

```text
if b then x else y
```

Observed shape:

- `test`
- conditional branch
- move chosen register to result

### Finding

The CFG shape is clean, but the final code is branchy, not branchless.

---

## C. Boolean short-circuit `and`

Shape:

```text
a and b
```

Observed shape:

- branch on lhs
- false path becomes `xor eax,eax`
- true path returns rhs register

### Finding

Current lowering preserves short-circuit structure correctly.
This is already backend-friendly.

---

## D. Scalar min / pure choose remains branchy

Shape:

```text
min2_i32(x, y) = if x < y then x else y
```

Observed code:

```asm
cmp    edi,esi
jl     take_x
mov    rax,rsi
jmp    done
mov    rax,rdi
```

### Finding

Current pure scalar choice is compiling to normal branchy CFG, not `cmov` or select-like
code.

### Language implication

If branchless scalar choose matters, Moonlift likely needs either:

- a first-class select-like semantic form, or
- a canonical lowering that recognizes pure scalar branch-free choice before CFG lowering

---

## E. Clamp is also branchy

Shape:

```text
if x < lo then lo else if x > hi then hi else x
```

Observed code:

- compare against `lo`
- branch
- compare against `hi`
- branch
- moves into result register

### Finding

Nested scalar choose still stays branchy.
There is no `cmov`-style lowering visible here.

---

## F. Dense switch now preserves real switch structure and becomes `br_table`

Shape:

```text
switch x
  0 => 10
  1 => 11
  2 => 12
  3 => 13
  4 => 14
  else 99
end
```

Observed CLIF:

```text
br_table v0, block6, [block1, block2, block3, block4, block5]
```

Observed machine code includes:

```asm
mov    r11d,0x5
cmp    eax,r11d
cmovb  r11d,eax
lea    rcx,[rip+...]
movsxd rax,DWORD PTR [rcx+r11*4]
add    rcx,rax
jmp    rcx
```

### Finding

Moonlift now preserves dense integer switch structure through `Sem -> Back` via
`BackCmdSwitchInt`, and Cranelift can turn that into a real jump-table-style dispatch.
This is the intended architectural shape: Moonlift no longer destroys dense switch form
before the backend sees it.

---

## G. Sparse switch is now preserved long enough for backend strategy choice

Shape:

```text
switch x
  1   => ...
  8   => ...
  33  => ...
  100 => ...
  else 99
end
```

Observed CLIF:

```text
v2 = icmp_imm uge v0, 33
brif v2, block8, block7
...
v3 = icmp_imm.i32 eq v0, 100
...
v4 = icmp_imm.i32 eq v0, 33
...
v5 = icmp_imm.i32 eq v0, 8
...
v6 = icmp_imm.i32 eq v0, 1
```

Observed machine code is still compare-based, but no longer as Moonlift’s own fixed linear
chain.

### Finding

Sparse switch does not become a jump table here, but that is now a **backend choice after
preserved switch lowering**, not an early Moonlift collapse. Cranelift sees first-class
switch structure and chooses a sparse dispatch tree.

So the remaining switch problem is narrower than before:
Moonlift now has an explicit machine-facing constant-key classification at the `Sem -> Back`
boundary, so dense/sparse strategy selection is no longer lost prematurely for constant-key
integer/bool/index switches.

The remaining gap is no longer “hidden switch-shape rediscovery in backend lowering”.
The remaining gap is simply that non-constant or duplicate-key cases still take the compare path,
which is now an explicit classified fallback rather than an ad hoc probe of raw semantic arms.

---

## H. Constant signed division by 10 is already good

Shape:

```text
div10_i32(x) = x / 10
```

Observed code:

```asm
mov    rax,rdi
imul   DWORD PTR [rip+...]
sar    edx,0x2
shr    esi,0x1f
lea    eax,[rdx+rsi*1]
```

### Finding

Cranelift is already using a magic-multiply style lowering here.
There is no obvious `idiv`.

### Language implication

Moonlift probably does **not** need special-case surface design just to make constant
signed division by non-powers-of-two good.

---

## I. Constant signed remainder by 10 is also already good

Shape:

```text
rem10_i32(x) = x % 10
```

Observed code:

- magic multiply / quotient approximation
- multiply by 10
- subtract to reconstruct remainder

### Finding

Again, no raw `idiv`; current backend code is decent for this pattern.

---

## J. Signed `% 8 == 0` is not just a low-bit test

Shape:

```text
x % 8 == 0
```

Observed code:

```asm
sar    r8d,0x2
shr    r8d,0x1d
add    r8d,edi
and    r8d,0xfffffff8
sub    edi,r8d
test   edi,edi
sete   al
```

### Finding

Signed remainder semantics are blocking the simplest “just test low bits” lowering.

### Language implication

If Moonlift wants cheap multiple-of-`2^k` tests, unsigned/index paths and better typed
literal ergonomics matter. Signed `%` carries semantics that the backend preserves.

---

## K. Signed Collatz step on `i32` is better than expected

Shape:

```text
if n % 2 == 0 then n / 2 else 3*n + 1
```

Observed code:

```asm
shr    r10d,0x1f
lea    eax,[rdi+r10*1]
and    r10d,0xfffffffe
sub    r11d,r10d
test   r11d,r11d
je     even
imul   eax,edi,0x3
add    eax,0x1
sar    eax,1
```

### Finding

Cranelift is already strength-reducing this signed `%2` / `/2` pattern nicely.
There is no general divide instruction in the emitted code.

---

## L. Bit-mix kernels lower cleanly

Shape:

```text
((x << 5) ^ (x >> 2)) + (x & 255)
```

Observed code:

```asm
shl    esi,0x5
sar    r8d,0x2
xor    esi,r8d
and    edi,0xff
lea    eax,[rsi+rdi*1]
```

### Finding

Straight-line integer bit arithmetic is already in good shape.

---

## M. Pointer indexing/addressing lowers well

Shape:

```text
p[0] + p[1]
```

Observed code:

```asm
mov    eax,DWORD PTR [rdi]
add    eax,DWORD PTR [rdi+0x4]
```

### Finding

Pointer indexing is preserving enough address structure to become efficient base+offset
machine addressing.

This is one of the strongest signs that current pointer/index lowering is on a good path.

---

## N. Integer polynomial kernels lower well

Shape:

```text
x*x + 3*(x*y) + y*y + 7
```

Observed code:

```asm
imul   r10d,edi
imul   edi,esi
imul   r11d,edi,0x3
add    r10d,r11d
imul   esi,esi
lea    eax,[r10+rsi*1+0x7]
```

### Finding

Straight-line integer arithmetic is already generating good machine code.

Notable positive points:

- no obviously pointless temporaries at machine-code level
- constant add folded into final `lea`

---

## O. Float polynomial kernels are decent, but not fused

Shape:

```text
x*x + 3.0*(x*y) + y*y + 7.0
```

Observed code:

```asm
vmulsd xmm2,xmm0,xmm0
vmulsd xmm0,xmm0,xmm1
vmulsd xmm0,xmm3,xmm0
vaddsd xmm0,xmm2,xmm0
vmulsd xmm1,xmm1,xmm1
vaddsd xmm1,xmm1,[rip+...]
vaddsd xmm0,xmm0,xmm1
```

### Finding

Scalar float code is decent and uses scalar AVX instructions, but there is **no FMA**.
Constants are materialized via a mix of immediate-to-register and literal-pool loads.

### Language implication

If Moonlift wants reliable fused multiply-add code, it likely needs an explicit `fma`
operation in the language/semantic layers.
Generic `a*b + c` is not being fused here.

---

## Second pass after the hard blocker fixes

## P. Recursive/direct-call functions now compile, and self-calls are honest

Shapes re-tried successfully:

- recursive Fibonacci
- recursive GCD

### Recursive Fibonacci observed shape

Observed code includes direct self-recursive calls:

```asm
sub    edi,0x1
call   0x0
...
sub    edi,0x2
call   0x0
```

Because the disassembly is over a copied raw code blob, the self-call target prints as
`call 0x0`; in the real JIT artifact this is a direct self-relative call.

The emitted function also:

- keeps the input in `r12`
- saves/restores `r12` in the prologue/epilogue
- branches on the base case `n < 2`
- preserves the first recursive result across the second recursive call via `r12`

### Recursive GCD observed shape

Observed code includes:

```asm
test   esi,esi
je     base
mov    rax,rdi
cdq
...
idiv   esi
mov    rdi,rsi
mov    rsi,rdx
call   0x0
```

This is exactly the kind of thing we want to observe:

- the recursive call path is now real
- variable signed remainder really lowers to `idiv`
- the backend is not “magically optimizing away” variable Euclidean remainder

### Finding

The direct-call/recursion path is now honest enough to study real recursive benchmark
kernels at machine-code level.

### Language implication

This is important architecturally: if a recursive benchmark is slow now, that is no longer
just a declaration/lowering bug hiding the real backend behavior. We can now inspect actual
recursive call shape.

---

## Q. Loop-carried benchmark kernels now compile, but they are still too memory-resident

Shapes re-tried successfully:

- `sum_range(n)` over a counted domain
- iterative Fibonacci via `SurfLoopWhileExpr`

### `sum_range` observed shape

The emitted code now contains a real loop backedge and an unsigned loop condition:

```asm
xor    r8,r8
...
cmp    r8,rdi
jb     body
...
add    r8,0x1
add    rax,QWORD PTR [rcx]
jmp    loop_head
```

So the current lowering now preserves enough counted-loop structure to generate a real loop.

But the function still repeatedly stores loop-carried values to stack slots and reloads them
through stack-address pointers inside the loop.

### Iterative Fibonacci observed shape

The emitted iterative Fibonacci also contains a real loop and real carried-state updates:

```asm
cmp    r8d,edi
jl     body
...
mov    r9d,0x1
add    r9d,DWORD PTR [rcx]
mov    rsi,rax
add    esi,DWORD PTR [rdx]
...
jmp    loop_head
```

This is already enough to inspect real loop recurrence code, but the generated machine code
still shows a lot of repeated stores like:

```asm
mov    DWORD PTR [rsp+0x8],r9d
mov    DWORD PTR [rsp+0x10],esi
mov    DWORD PTR [rsp+0x18],eax
```

and repeated reloads of carried state through stack-slot addresses.

### Finding

The loop blocker is gone, but the next code-quality problem is now extremely visible:

- loop-carried vars are still being kept too memory-resident
- the loop structure is real, but the carried-state policy is still much more stack-heavy
  than it should be for hot kernels

### Language / lowering implication

This is now one of the clearest next optimization targets:

- keep loop-carried values in SSA/register form longer
- avoid re-materializing every carried variable through stack homes on each cycle unless
  addressability really requires it

---

## R. Real-life buffer reduction loops lower to good addressing modes, but remain scalar and stack-heavy

Shapes probed successfully:

- `sum_buf_f64(src, n)`
- `dot_f64(x, y, n)`

### `sum_buf_f64` observed shape

Observed code includes:

```asm
vxorpd xmm0,xmm0,xmm0
...
cmp    r9,rsi
jb     body
...
vaddsd xmm0,xmm0,QWORD PTR [rdi+rax*8]
```

This is good in one important sense:

- pointer indexing is becoming proper scaled memory addressing (`[base + index*8]`)
- the floating accumulator stays live in an XMM register across the loop

But the loop index is still repeatedly written to a stack home, and the loop prologue/body
contains more stack traffic than a hot reduction kernel should need.

### `dot_f64` observed shape

Observed code includes:

```asm
vmovsd xmm1,QWORD PTR [rdi+rax*8]
vmulsd xmm1,xmm1,QWORD PTR [rsi+rax*8]
vaddsd xmm0,xmm0,xmm1
```

Again, addressing is good and the recurrence is understandable, but the loop remains purely
scalar and still carries index/cursor state through stack slots more than necessary.

### Finding

For real-life buffer reductions, the good news is:

- addressing modes are already healthy
- scalar FP recurrence code is readable and honest

The less good news is:

- no vectorization is appearing
- no unrolling is appearing
- loop/cursor state is still more stack-resident than desirable

### Language implication

If Moonlift wants strong performance on data-parallel kernels, it should not rely on the
backend to “recover SIMD” from ordinary scalar loops. The observed code strongly suggests
that explicit SIMD/vector forms may eventually be a better language direction than hoping
for automatic vectorization.

---

## S. Real-life buffer transform loops lower cleanly, but still show no FMA or vectorization

Shapes probed successfully:

- `saxpy_f64(dst, x, y, a, n)`
- `onepole_f64(dst, src, a, b, n)`

### `saxpy_f64` observed shape

Observed code includes:

```asm
vmulsd xmm1,xmm0,QWORD PTR [rsi+rax*8]
vaddsd xmm1,xmm1,QWORD PTR [rdx+rax*8]
vmovsd QWORD PTR [rdi+rax*8],xmm1
```

This is a perfectly recognizable scalar SAXPY kernel, with good scaled addressing.
But it is still scalar, not vectorized, and the multiply-add is not fused.

### `onepole_f64` observed shape

Observed code includes two separate computations of the same output expression:

```asm
vmulsd xmm3,xmm0,QWORD PTR [rsi+rcx*8]
vmulsd xmm4,xmm1,xmm2
vaddsd xmm3,xmm3,xmm4
vmovsd QWORD PTR [rdi+rcx*8],xmm3
...
vmulsd xmm3,xmm0,QWORD PTR [rsi+rcx*8]
vmulsd xmm2,xmm1,xmm2
vaddsd xmm2,xmm3,xmm2
```

This corresponds exactly to the authored shape:

- compute output and store it
- compute the same value again for `next y1 = ...`

### Finding

The machine code is telling us something useful about language shape here:

- scaled addressing and scalar floating arithmetic are fine
- but the current authored/lowered form does **not** share the computed latch value between
  “store to output” and “next carried state”
- there is still no FMA and no vectorization

### Language implication

This suggests a real language/lowering opportunity:

- Moonlift should make it easy to express a **shared latch value** once, then both store it
  and feed it into loop-carried state

That does **not** require a new schema variant if the existing distinctions are already
sufficient, but it does require the lowering to keep that honesty all the way down.

It also reinforces the case for explicit `fma` if fused floating update chains matter.

---

## T. Previously failing realistic branchy loop bodies now compile through the current path

A follow-up probe pass rechecked three analogous realistic loop-body shapes:

- a body-local `let out = ...` feeding a later `next y = out`
- a statement-level `if` inside a counted loop body
- nested `if` expressions inside a bounded loop update

The current authored/FFI path now compiles and runs those shapes successfully.

The earlier structural crash turned out not to be a loop-only semantic hole.
The root cause was the LuaJIT FFI replay path memoizing side-effectful `BackCmd` replay via
`pvm.phase(...)`, which could drop repeated identical CFG commands such as matching join jumps.
Once replay became plain non-memoized command dispatch, those branchy loop-body shapes started
compiling normally.

### Finding

The previous realistic failures were primarily a backend-host replay bug, not evidence that
simple body-local shared values or ordinary branchy loop bodies inherently need a new loop-only
source/schema split.

In other words:

- straight counted loops compile
- simple carried-state loops compile
- branchy stmt `if` loop bodies compile
- nested `if`-expression loop updates compile
- linear body-local values that later feed `next` also compile through the current path

### Language implication

This does **not** prove that no future explicit loop/body result shape will ever be needed.
If Moonlift later needs branch-produced values to be exported from a loop body into later loop
steps in a way that is not already explicit in the current authored/Elab/Sem structure, that
should still be represented honestly rather than rediscovered by helper code.

But the earlier probed failures themselves were not evidence for that stronger redesign.

---

## U. Unsigned/index authoring is still awkward

A natural `u32` benchmark shape hit literal/type-equality issues and required typed
constant globals just to compile cleanly.
When forced through typed globals, emitted code became much worse, involving data loads
and a real divide path.

### Finding

Unsigned/index-oriented authoring is not yet ergonomic or robust enough for fair codegen
inspection.

### Language implication

Moonlift needs stronger type-directed literal elaboration for:

- `u32`
- `u64`
- `index`

Otherwise benchmark authoring will distort the emitted code.

---

## V. Stencil / FIR kernels compile, but reveal missing const-folding and still stay scalar

Shapes probed successfully:

- `moving_avg3_f64(dst, src, n)`
- `fir4_f64(dst, src, c0, c1, c2, c3, n)`

### `moving_avg3_f64` observed shape

Observed code includes:

```asm
lea    rax,[rip+...]
mov    r10,QWORD PTR [rax]
...
sub    rcx,QWORD PTR [rax]
...
vmovsd xmm0,QWORD PTR [rsi+r8*8]
vmovsd xmm1,QWORD PTR [rsi+r10*8]
...
vaddsd xmm0,xmm0,QWORD PTR [rsi+rcx*8]
vmulsd xmm0,xmm2,xmm0
vmovsd QWORD PTR [rdi+r10*8],xmm0
```

The good parts are clear:

- stencil addressing becomes proper scaled addressing
- three-tap neighborhood access is visible and honest
- scalar floating arithmetic is straightforward

This probe originally exposed an important missed opportunity:

- the typed index constants like `ONE` were being materialized as data loads from RIP-relative
  constant objects instead of folded into immediate arithmetic at codegen time

That specific constant-folding issue has now been fixed for typed numeric / `index` const globals and pure derived scalar const expressions. A current probe like:

```text
const ONE: index = 1
const TWO: index = ONE + ONE
bump_index(i) = i + TWO
```

now lowers to:

```text
v1 = iconst.i64 2
v2 = iadd v0, v1
```

### `fir4_f64` observed shape

Observed code includes four separate source loads and four scalar coefficient multiplies:

```asm
vmovsd xmm4,[rsi+rax*8]
vmovsd xmm5,[rsi+r8*8]
vmovsd xmm6,[rsi+r8*8]
...
vmulsd xmm4,xmm0,xmm4
vmulsd xmm5,xmm1,xmm5
vmulsd xmm5,xmm2,xmm6
vmulsd xmm6,xmm3,[rsi+rcx*8]
```

Again, addressing is structurally good, but:

- the kernel stays entirely scalar
- there is no unrolling
- there is no vectorization
- there is no fused multiply-add
- older stencil/FIR probes showed index-offset constants loaded via data objects instead of folded immediates; the simple typed-const-global case is now fixed, but larger kernels should be re-probed to see how much of the old finding remains after the new `Sem -> Sem` const-scalar normalization

### Finding

These kernels are valuable because they show both what is already good and what is still
missing:

Good:

- neighborhood/gather-like addressing shapes survive into machine code
- Cranelift gets honest stencil/FIR memory access structure

Missing / weak:

- larger stencil/FIR kernels should be re-checked now that typed numeric / `index` const globals are folded earlier
- hot signal-processing kernels remain purely scalar
- multiply-add chains are not fused

### Language implication

There are at least two opportunities here:

1. stronger const propagation / immediate folding for typed numeric and index constants
2. eventual explicit SIMD/vector and explicit `fma` forms for hot DSP kernels

---

## W. Small loop-body dispatch now preserves switch structure inside the loop

Shape probed successfully:

- `dispatch_pair(op0, op1)`

This is a small loop carrying an accumulator, choosing an opcode per iteration, and then
switching on that opcode inside the loop body.

Observed CLIF includes a real loop backedge plus an in-body preserved switch:

```text
block7(v23: i32):
    br_table v23, block10, [block8, block9]
```

### Finding

Moonlift no longer needs to collapse loop-body switch dispatch into its own compare CFG before
Cranelift sees it. In this probe, the loop body still contains first-class switch structure,
so hot dispatch code is at least eligible for backend strategy choice.

That is a major architectural improvement over the previous state where switch shape was lost
before backend lowering could decide anything interesting.

### Remaining limitation

This improvement currently applies to constant-key `bool` / integer / `index` switch forms.
General non-constant arm-key expressions still fall back to compare CFG because the machine-
facing switch/key split is not yet fully explicit.

---

## X. Indirect gather loops compile honestly, but show no recovery beyond scalar gather

Shape probed successfully:

- `gather_sum_f64(values, idxs, n)`

Observed code includes:

```asm
mov    rax,QWORD PTR [rsi+rax*8]
vaddsd xmm0,xmm0,QWORD PTR [rdi+rax*8]
```

### Finding

This is a useful real-life data point:

- Moonlift can already express indirect indexed access cleanly enough for the backend to
  emit an honest scalar gather pattern
- but the backend does not recover anything more powerful from it
- there is no vector gather, no batching, no restructuring

### Language implication

For indirect memory kernels, Moonlift should assume that scalar gather-like code will stay
scalar unless the language explicitly grows a stronger data-parallel vocabulary.

---

## Y. Some cast paths are still missing in the current pipeline

A `poly_f32` path that required explicit casts currently hit a missing lowering handler:

```text
pvm.phase 'sem_to_back_expr': no handler for SemExprCastTo
```

### Finding

Some cast-heavy realistic numeric authoring paths are still incomplete.
This currently limits machine-code inspection for mixed-precision and explicit-cast code.

---

## Z. Fixed-field decode / packet-style bit extraction already lowers honestly, but stays spill-heavy

Shape probed successfully:

- `packet_fields_i32(hdr)`

This shape loads two header words and extracts fields with shifts and masks.

Observed code includes:

```asm
mov    eax,DWORD PTR [rdi]
mov    eax,DWORD PTR [rdi+0x4]
shr    eax,0x1c
and    eax,0xf
shr    ecx,0x18
and    ecx,0xf
shr    ecx,0x10
and    ecx,0x7
```

### Finding

This is encouraging for parser-like fixed-field extraction:

- the semantic shape survives honestly into `load -> shift -> mask`
- immediates are used directly for the masks and shifts
- the backend is not obscuring the bitfield structure

But the current lowering still stores intermediate words and extracted fields into stack
homes between steps, so even a simple packet-field decode is more spill-heavy than it should
be.

### Language implication

Packet/header parsing appears compatible with the current core language, but there is still
room for a cleaner lowering discipline around local temporaries. Later, if Moonlift wants a
more explicit packet/bitfield vocabulary, this emitted code gives a baseline for judging
whether that vocabulary is buying anything real.

---

## AA. Search / probe loops compile honestly, but the lack of early-exit structure is now visible

Shape probed successfully:

- `hash_probe_i32(keys, target, n)`

This loop carries `found = n` as a sentinel and uses nested choice logic to update it when a
match is seen.

Observed code includes:

```asm
cmp    rax,rdx         ; found == n ?
jne    skip_load
mov    rcx,QWORD PTR [rsp+0x18]
mov    r8d,DWORD PTR [rdi+rcx*4]
cmp    r8d,esi
jne    skip_set
mov    rax,rcx
```

### Finding

This is a very useful real-life result:

- nested if-style carried-state update now compiles in at least some loop-next positions
- once `found != n`, later iterations skip the expensive key load and comparison

But the loop still iterates all the way to `n`. There is no real early exit; there is only
“keep looping, but gate the work”.

### Language implication

For search/probe kernels, Moonlift now needs to think about the difference between:

- carried-state loops that continue structurally, and
- loops that want true **early exit** once a result is found

This is not just a backend issue. The generated code is showing that the current loop model
can express “I found it, stop doing expensive work”, but not yet “I found it, stop the loop”.

---

## AB. Nested map-reduce kernels compile, but row-base invariants are not shared well enough

Shape probed successfully:

- `gemv_f64(dst, mat, vec, rows, cols)`

This is a nested loop:

- outer loop over rows
- inner reduction over columns
- flat matrix index `i * cols + j`

Observed code includes:

```asm
imul   r11,r8
add    r11,r10
vmovsd xmm1,QWORD PTR [rsi+r11*8]
vmulsd xmm1,xmm1,QWORD PTR [rdx+r10*8]
vaddsd xmm0,xmm0,xmm1
```

### Finding

This is another strong “language opportunity” result:

- nested loops do compile
- matrix/vector addressing stays understandable and honest
- but the row-base computation `i * cols` is still being performed inside the inner loop
  rather than obviously being hoisted/shared as a row base

### Language implication

For real matrix/tensor-ish kernels, Moonlift may benefit from making row/segment bases easier
to express and preserve, for example through stronger loop-body sharing or view/slice forms.
Even without adding a whole new syntax family, the machine code is clearly pointing at a
missing invariant-sharing opportunity.

---

## AC. Pointer-chasing loops compile honestly, which is useful precisely because they stay ugly

Shape probed successfully:

- `walk_next_f64(values, nexts, start, nsteps)`

This loop carries an index through `nexts[idx]` and accumulates `values[idx]`.

Observed code includes:

```asm
mov    rdx,QWORD PTR [rsi+r9*8]   ; next idx
add    rax,QWORD PTR [r8]         ; step + 1
vaddsd xmm0,xmm0,QWORD PTR [rdi+r9*8]
```

### Finding

This is a good honesty test:

- dependent-load / pointer-chasing structure is preserved
- the backend does not invent locality or vectorization that is not really there
- the emitted code remains a scalar dependent-load chain

### Language implication

This is a reminder that not every performance problem is a syntax problem. For pointer-
chasing kernels, data layout and algorithm structure matter more than backend cleverness.
The value of Moonlift here is that it preserves the real structure honestly enough to see
that fact.

---

## AD. Some realistic branchy expression-in-loop shapes still expose a frontend inconsistency

Shape probed unsuccessfully:

- `ascii_count_i32(bytes, n)` with:
  - `next acc = acc + (if bytes[i] < 128 then 1 else 0)`

Observed failure:

```text
pvm.phase 'surface_to_elab_expr': no handler for SurfIfExpr
```

### Finding

This is interesting because not all `if`-expression uses are equally broken:

- some nested carried-state choice forms now compile (`hash_probe_i32`)
- but this more ordinary byte-classifier/counting shape still fails

So the current expression-lowering support for `if` inside loop-next expressions is still not
uniform across realistic authored contexts.

### Language implication

This is important for parser/scanner/text-processing kernels, where “accumulate based on a
predicate” is a very ordinary pattern. The language does not need a new concept here; it
needs more consistent honest lowering of the existing one.

---

## AE. Serial parser-style digit accumulation compiles honestly, but still looks scalar and spill-heavy

Shape probed successfully:

- `digit_accum_i32(bytes, n)`

This is a simple decimal-accumulation kernel:

```text
acc = acc * 10 + (byte - '0')
```

Observed code includes:

```asm
imul   eax,eax,0xa
sub    ecx,0x30
add    eax,ecx
```

### Finding

This is encouraging:

- serial parser/state-machine accumulation compiles honestly
- the backend sees the multiply-by-10 and byte-to-digit subtract exactly as authored

But it also shows that these parser loops are still just scalar recurrence loops with the same
stack-slot traffic around carried state and indices as other loops.

### Language implication

Parser-like accumulation patterns do not appear to require a new language category, but they do
need the same loop-state cleanup work as numeric kernels.

---

## AF. Text search loops compile honestly, but again highlight the missing early-exit story

Shape probed successfully:

- `find_colon_i32(bytes, n)`

Observed code includes:

```asm
cmp    rax,rsi
jne    skip_check
mov    edx,DWORD PTR [rdi+rcx*4]
cmp    edx,0x3a
jne    skip_set
mov    rax,rcx
```

### Finding

This is the text/scanner analog of the earlier probe/search result:

- once a match is found, later iterations skip the expensive byte comparison
- but the loop still structurally runs to the end

### Language implication

For scanner/parser kernels, early-exit is not a niche feature. It is a core shape. The emitted
machine code is again showing the difference between:

- “I found it, so skip expensive work now”, and
- “I found it, so exit the loop now”.

Moonlift should likely support the latter more directly for real search kernels.

---

## AG. Naive vs hoisted blend kernels show that invariant authoring already matters

Shapes probed successfully:

- `alpha_blend_f64(dst, src, alpha, n)`
- `alpha_blend_hoisted_f64(dst, src, alpha, n)`

The naive authored form computes `1.0 - alpha` inside the loop body.

Observed code includes:

```asm
movabs rax,0x3ff0000000000000
vmovq  xmm2,rax
vsubsd xmm2,xmm2,xmm0
vmulsd xmm2,xmm2,QWORD PTR [rdi+r11*8]
```

The hoisted version computes `inv = 1.0 - alpha` once before the loop.

Observed code includes:

```asm
movabs rax,0x3ff0000000000000
vmovq  xmm1,rax
vsubsd xmm1,xmm1,xmm0
vmovsd QWORD PTR [rsp+0x20],xmm1
...
vmovsd xmm2,QWORD PTR [rsp+0x20]
```

### Finding

This is one of the clearest language opportunities so far:

- manual invariant hoisting already changes the emitted code shape in a meaningful way
- the current compiler is **not** hoisting `1.0 - alpha` out of the loop for you
- even after manual hoisting, the hoisted value is still kept in a stack home instead of
  obviously staying register-resident across the loop

### Language implication

Moonlift should care about loop-invariant value expression and preservation, not just loop-carried
state. A language that makes invariants easy to express and keep visible may generate much cleaner
hot-loop code without asking the backend to rediscover everything.

---

## AH. Interleaved image kernels compile honestly, but strongly suggest a need for better view/base sharing

Shape probed successfully:

- `rgba_gray4_f64(dst, src, npix)`

This computes luma from interleaved RGBA-like input using indices like:

- `src[4*i + 0]`
- `src[4*i + 1]`
- `src[4*i + 2]`

Observed code includes:

```asm
imul   rcx,QWORD PTR [rax]       ; i * FOUR
...
add    r8,QWORD PTR [rcx]        ; + ONE
...
add    rax,QWORD PTR [r8]        ; + TWO
```

and then scalar coefficient multiplies.

### Finding

This is highly informative:

- interleaved image addressing survives honestly into codegen
- but typed index constants (`FOUR`, `ONE`, `TWO`) are still materialized via memory loads
- the base/index arithmetic is repeated rather than clearly shared as a pixel base
- the kernel stays scalar

### Language implication

This strongly suggests value in making it easier to express and preserve:

- strided/interleaved views
- shared per-pixel base addresses
- structured lane/group access

Without that, the compiler sees repeated scalar address arithmetic instead of a clearer image-
layout vocabulary.

---

## AI. Historical interpreter-dispatch compare-chain finding is now stale

An earlier `opcode_interp_dense8_i32` probe was recorded here as a long linear compare chain.
That finding should no longer be treated as the current architectural baseline.

Since then, Moonlift gained explicit `BackCmdSwitchInt` lowering and current probes show:

- dense constant-key switch can reach CLIF as `br_table`
- sparse constant-key switch can stay preserved long enough for Cranelift to choose a sparse tree
- loop-body switch dispatch can remain preserved inside the loop body

### Current implication

The remaining interpreter-dispatch question is no longer “does Moonlift destroy switch shape
before the backend sees it?”

The current question is narrower:

- how well does Cranelift scale preserved `BackCmdSwitchInt` dispatch for larger opcode sets?
- when do we still need a more explicit machine-facing constant-key split for switches that fall
  back to compare CFG?

A refreshed large-interpreter probe should be re-run against the new backend path rather than
relying on the older compare-chain result.

---

## AJ. Unrolled matrix microkernels compile honestly, but they show no automatic reuse or fusion

Shape probed successfully:

- `matmul2x2_f64(c, a, b)`

Observed code includes a sequence like:

```asm
vmovsd xmm0,QWORD PTR [rsi]
vmovsd xmm1,QWORD PTR [rdx]
vmovsd xmm2,QWORD PTR [rsi+0x8]
vmulsd xmm0,xmm0,xmm1
vmulsd xmm1,xmm2,QWORD PTR [rdx+0x10]
vaddsd xmm0,xmm0,xmm1
vmovsd QWORD PTR [rdi],xmm0
```

repeated again for the other outputs.

### Finding

This is useful because it shows what the backend is **not** doing for us:

- it is not fusing multiply-adds
- it is not obviously reusing loaded `a` values across multiple outputs
- it is not turning the unrolled microkernel into a more register-blocked shape

### Language implication

If Moonlift wants serious small-matrix / microkernel performance, it may eventually need a more
explicit vocabulary for:

- fused math
- block/microkernel structure
- perhaps explicit vector lanes or small fixed-size fragments

At the very least, the emitted code suggests that relying on backend recovery alone will leave
performance on the table.

---

## Consolidated design implications

These findings point to the following language/ASDL/lowering priorities.

## 1. Stop forcing eager stack homes for every parameter

The emitted machine code is showing this issue everywhere.
A future lowering split should distinguish:

- params whose address is actually taken
- params that can remain pure SSA values

## 2. Keep loop-carried values in SSA/register form longer

Now that loop kernels compile, the biggest loop-specific code-quality issue is no longer
blockage — it is repeated spill/store/reload traffic for loop-carried values.

## 3. Preserve switch as switch longer

If dense switch performance matters, the language/lowering should retain a real switch form
longer instead of lowering immediately to comparison CFG.

## 4. Add a scalar select-oriented path

If branchless `min/max/clamp` matters, Moonlift should likely provide either:

- an explicit select-like semantic operation, or
- a canonical lowering for pure scalar choose forms

## 5. Add explicit math/bit intrinsics where code shape matters

At minimum, explicit `fma` looks justified from these observations.
Later likely candidates include:

- popcount
- clz
- ctz
- rotl
- rotr
- bswap

## 6. Improve typed literal elaboration for unsigned/index code

This matters not just for ergonomics, but for honest codegen inspection.
If the author has to contort code into typed globals, the backend signal becomes noisy.

## 7. Fill remaining cast-heavy lowering holes

Some explicit-cast paths are still incomplete enough to block realistic mixed-precision
probe cases.

## 8. Keep using emitted machine code as a language-design feedback loop

The strongest lesson from this probe is that many important “optimization” questions are
really questions about what semantic structure Moonlift preserves long enough for Cranelift
to use.

That is exactly the kind of feedback loop the peek utility should support regularly.

---

## Short summary

### Already promising

- straight-line integer arithmetic
- straight-line bit-mix arithmetic
- pointer indexing/addressing
- constant signed div/rem by non-powers-of-two
- some signed `%2` / `/2` patterns like Collatz step
- recursive direct self-calls now compile honestly enough to inspect
- counted and carried loops now compile honestly enough to inspect
- real buffer kernels already lower to sensible scaled memory addressing
- stencil/FIR/gather-style memory access patterns survive honestly into machine code
- packet-style fixed-field decode lowers honestly to load/shift/mask code
- search/probe loops and pointer-chasing loops now compile honestly enough to inspect
- nested map-reduce kernels now compile honestly enough to inspect
- serial parser-like accumulation loops compile honestly enough to inspect
- manual authoring changes like invariant hoisting already have visible machine-code effects
- interleaved image kernels compile honestly enough to inspect
- unrolled matrix microkernels compile honestly enough to inspect

### Clearly needing language/lowering work

- unconditional arg spills
- loop-carried values are still too memory-resident
- branchy loop bodies still expose a structural lowering bug
- current loop authoring/lowering does not yet share latch values cleanly across store + next-state use
- lack of real early-exit structure for search/probe and scanner kernels
- loop-invariant values are not hoisted/preserved strongly enough unless authored manually
- dense switch preservation, especially inside interpreter-style hot loops
- branchless scalar select-like forms
- explicit float semantic ops like `fma`
- likely explicit SIMD/vector forms for serious data-parallel kernels
- stronger const propagation / immediate folding for typed numeric and index constants
- better invariant/base sharing in nested matrix/stencil/image kernels
- better vocabulary for strided/interleaved views if image-style kernels matter
- typed unsigned/index literals
- some explicit cast-heavy lowering paths
- some realistic expression-in-loop predicate forms still hit frontend lowering holes
- small matrix/microkernel code still lacks obvious reuse/fusion structure

---

## Suggested next implementation order

1. revisit param spilling policy
2. keep loop-carried vars/register state live longer instead of repeatedly materializing them through stack slots
3. fix structural lowering for branchy loop bodies and body-local values feeding later loop structure
4. make shared latch-value authoring/lowering work cleanly for store + next-state patterns
5. add or preserve real early-exit structure for search/probe and scanner kernels where continued gated looping is not good enough
6. make loop-invariant value authoring/retention stronger so obvious hoists do not depend only on manual source refactoring
7. preserve switch more structurally in lower layers, especially for interpreter-style loop bodies
8. add explicit select and/or canonical pure-choice lowering
9. add explicit `fma` surface/semantic support
10. strengthen const propagation / immediate folding for typed numeric and index constants
11. improve invariant/base sharing for nested matrix/stencil/image kernels
12. consider better vocabulary for strided/interleaved views if image-style kernels are a target
13. improve typed literal elaboration for unsigned/index forms
14. fill remaining cast-heavy and expression-in-loop lowering holes
15. consider explicit SIMD/vector surface forms for real data-parallel kernels rather than relying on backend recovery
16. consider whether small matrix/microkernel work needs a more explicit block/register-oriented surface eventually
