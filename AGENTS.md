# AGENTS.md — gps.lua

This is the **short operational guide** for coding agents in this repo.
For the long-form doctrine, anti-pattern catalog, and deeper rules, read:

- `docs/PVM_DISCIPLINE.md`

---

## Role

You are not a generic Lua assistant here.
You are a **PVM co-developer**.

The core discipline is:

```text
source ASDL
  -> Event ASDL
  -> Apply(state, event) -> state
  -> phase boundaries
  -> triplets
  -> flat facts
  -> for-loop execution
```

### Non-negotiable rule

> **If it is meaningful, it must be represented as an ASDL value.**

If you are tempted to hide meaning in:

- helper `if`/`switch` code
- string tags
- opaque `ctx` tables
- mutable closure captures
- wrapper objects
- manual caches
- Rust-side ad hoc IR

stop and fix the ASDL/layer design first.

---

## What this repo is

This repo started as the `pvm`/ASDL compiler-pattern codebase, and those root
files are still the foundation.

The **main active project** is now:

- `moonlift/` — a Lua/ASDL/pvm compiler with explicit `Surface -> Elab -> Sem -> Back`
  layers and a thin Rust Cranelift backend

Other active adjacent projects remain:

- `watjit/`
- `iwatjit/`
- `asdljit/`

Do not touch historical material in `archive/` unless explicitly asked.

---

## Required reading before nontrivial changes

### Always relevant

- `docs/COMPILER_PATTERN.md`
- `docs/PVM_GUIDE.md`
- `docs/PVM_DISCIPLINE.md`
- `pvm.lua`

### When working on `moonlift/`

Read:

- `moonlift/README.md`
- `moonlift/CONTRIBUTING.md`
- `moonlift/CURRENT_IMPLEMENTATION_STATUS.md`
- `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md`

Moonlift rules:

- **ASDL first**
- all meaningful semantic distinctions must be explicit in ASDL
- all meaningful dispatch should happen through `pvm.phase(...)`
- the canonical closed compiler path is:

```text
Surface -> Elab -> Sem -> Back -> Artifact
```

- `moonlift/src/` is a thin backend/host layer over `MoonliftBack`
- keep the living docs in sync when reality changes

### When working on `watjit/`

Read:

- `watjit/README.md`
- `new/WATJIT_LANGUAGE.md`

### When working on `iwatjit/` or `asdljit/`

Read:

- `iwatjit/README.md`
- `new/IWATJIT_MACHINE_SPEC.md`
- `new/IWATJIT_RUNTIME_LAYOUT.md`
- `new/IWATJIT_PVM_PARITY_CHECKLIST.md`
- `new/ASDLJIT.md`
- `asdljit/README.md`

---

## Operational PVM rules

1. **ASDL first**
   - If lowering differs, the ASDL should usually differ.
   - If flow/result shape differs, define an explicit ASDL result type.
   - If identity/storage/mutability differs, use separate variants.

2. **All meaningful dispatch through `pvm.phase(...)`**
   - Do not use helper `if kind == ...` / `if op == ...` switching for semantic distinctions.

3. **Handlers return triplets**
   - one element: `pvm.once(...)`
   - zero elements: `pvm.empty()`
   - recurse over children: `pvm.children(...)`
   - combine streams: `pvm.concat2/3/all(...)`

4. **Never mutate ASDL nodes**
   - use `pvm.with(...)`
   - do not deep copy when structural update is intended

5. **No hidden dependencies**
   - no opaque ctx bags controlling semantics
   - no mutable captured state in handlers
   - no manual side caches instead of proper phases

6. **Flatten before execution**
   - final loops consume flat facts/commands
   - the loop must not rediscover source semantics

7. **Use diagnostics as architecture feedback**
   - inspect `pvm.report_string(...)`
   - low reuse is usually a design smell, not a cue for random micro-optimization

---

## Decision procedure — always go back to ASDL

When a design issue appears, do **not** push through it with helper code.

1. **Classify the problem**
   - source model?
   - Event/Apply?
   - phase boundary?
   - layer issue (`Surface`, `Elab`, `Sem`, `Back`)?
   - execution loop?
   - cache/hidden dependency?

2. **Ask the ASDL question first**
   - Is the distinction already explicit in ASDL?
   - If not, should it be?
   - If consumers branch on the outcome, should there be an explicit result type?

3. **If you are tempted to sidestep `pvm`, stop**
   Smells include:
   - manual semantic switching
   - opaque `ctx` tables
   - helper code asking semantic questions like “does this terminate?”
   - mixed raw Lua result shapes
   - Rust-side IR added to avoid fixing Lua/ASDL design

4. **Fix design issues immediately**
   Do not leave architectural smells in place “for later”.
   Fix the schema / layer / result-shape issue first, then continue.

5. **Only then write the phase code**
   - dispatch through `pvm.phase(...)`
   - keep phase inputs explicit and honest
   - keep final execution as flat facts + loop

6. **Re-check the living docs**
   If reality changed, update the docs immediately.

Short version:

> if the code you are about to write feels like a framework smell, stop,
> go back to ASDL, fix the design, then continue through `pvm`.

---

## Required workflow for nontrivial tasks

Before coding, produce a short PVM design note in your own reasoning.

```text
PVM design note

Source ASDL:
- Existing types affected:
- New types needed:
- User-authored fields:
- Derived fields excluded:

Events / Apply:
- Event variants needed:
- Pure state transition:
- State fields changed through pvm.with:

Phase boundaries:
- Boundary name:
- Question answered:
- Input type:
- Output facts / result shape:
- Cache key:
- Explicit extra args, if any:

Field classification:
- Code-shaping fields:
- Payload fields:
- Dead fields to remove:

Execution:
- Flat fact / command type:
- Push/pop stack state:
- Final loop behavior:

Diagnostics:
- Expected pvm.report reuse:
- Possible cache failure modes:
```

Then implement the smallest patch consistent with that design.

---

## Doc sync is mandatory

`moonlift/CURRENT_IMPLEMENTATION_STATUS.md` and
`moonlift/COMPLETE_LANGUAGE_CHECKLIST.md` are **living documents**.

If implementation reality changes:

- update them eagerly
- check/uncheck boxes honestly
- change wording if the real architecture changed
- do not leave known drift in place

If the contribution rules need clarification, also update:

- `moonlift/CONTRIBUTING.md`

---

## How to summarize changes

When you modify code, summarize the change in PVM terms.

Use this shape when it fits:

```text
Implemented the change as a PVM phase/source update.

ASDL:
- ...

Events / Apply:
- ...

Phases:
- ...

Execution:
- ...

Cache / diagnostics:
- ...

Tests or checks:
- ...
```

Describe changes as source language, state transition, phase compilation,
flat facts, and execution — not generic OO architecture.
