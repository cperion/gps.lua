# moonlift

Fresh reboot of Moonlift around Lua/ASDL/pvm frontend layers and a smaller Rust backend.

The previous Rust-heavy implementation was moved to:

- `moonlift-old/`

Current focus:
- define correct ASDL compiler layers
- move semantic/frontend lowering into Lua
- keep Rust as a small validated backend/codegen layer
- finish the closed language and the public LuaJIT FFI path first
- treat deeper hosted/state-aware integration as later follow-on work, not the current priority

Design docs for the current direction:

- `moonlift/CONTRIBUTING.md` — ASDL-first contribution rules and architecture discipline
- `moonlift/REBOOT_SOURCE_SPEC.md` — reboot closed source-language spec grounded in current `MoonliftSurface`
- `moonlift/REBOOT_SOURCE_GRAMMAR.md` — parser-oriented grammar for the reboot source language
- `moonlift/PARSER_BOOTSTRAP_PLAN.md` — immediate direct-to-`Surface` parser plan for the reboot
- `moonlift/SOURCE_SPAN_STRATEGY.md` — reboot source-span design and current path-keyed span plan
- `moonlift/CURRENT_IMPLEMENTATION_STATUS.md` — what is and is not coded yet
- `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md` — living checklist from current state to complete language + hosting + FFI
- `moonlift/CODEGEN_FINDINGS.md` — current machine-code findings observed from the Cranelift backend
- `moonlift/QUOTING_SYSTEM_DESIGN.md` — fragment/function metaprogramming design
- `moonlift/LUAJIT_HOSTED_INTEGRATION.md` — deferred future hosted/state-aware integration design; not the current priority

Lua ASDL schema currently lives in a single file:

- `moonlift/lua/moonlift/asdl.lua`

There is now also an initial reboot parser/bootstrap source frontend at:

- `moonlift/lua/moonlift/parse_lexer.lua`
- `moonlift/lua/moonlift/parse.lua`
- `moonlift/lua/moonlift/source.lua`
- `moonlift/lua/moonlift/source_spans.lua`
- `moonlift/test_parse_smoke.lua`
- `moonlift/test_source_frontend.lua`

Current parser/source bootstrap support includes:

- top-level `func` / `extern func` / `const` / `static` / `import` / `type = struct { ... }`
- scalar/pointer/array/slice/view/function/named types
- unary/binary/cast/intrinsic/call/dot/index expressions
- authored dotted value/place syntax preserved explicitly and resolved later (`Demo.K`, `pair.left`, `&place`, `place = expr`)
- `if` expr
- `switch` stmt/expr
- `do ... end` block expr
- canonical `loop ... while ...` and `loop ... over ...`
- explicit loop carries and `next` updates in the reboot source grammar
- field-based aggregate literals
- array literals via `[]T { ... }`
- explicit `select(cond, a, b)` parsing
- valued `break expr` parsing
- `view(T)` type parsing
- direct `parse -> Surface` and `parse -> Elab/Sem` helper APIs
- named-module package helpers with explicit imports (`pipeline_package`, `back_package`, `compile_package`)
- `parse_*_with_spans` / `pipeline_*_with_spans` helpers
- `try_parse_*` / `try_lower_*` style diagnostic helpers
- lower-stage diagnostics can now be bridged back to source paths/line+column when structural path text is available

Current package/import note:

- module names are currently supplied by the host/package API (`pipeline_package`, `back_package`, `compile_package`)
- authored source currently imports them with `import Demo` and uses qualified refs/types like `Demo.K`, `Demo.inc(...)`, `Demo.Pair`
- exported backend/JIT function ids for named package modules are currently namespaced as `Module::func`

## Rust backend crate

`moonlift/` now also contains a new standalone Rust crate:

- `moonlift/Cargo.toml`
- `moonlift/src/lib.rs`

This crate is intentionally **thin**.
It does **not** define a second Moonlift IR in Rust.
Instead it mirrors the current symbolic `MoonliftBack.BackCmd` layer directly and compiles a `BackProgram` through Cranelift JIT/module/frontend APIs.

### Current primitive API

The core Rust surface is:

- `Jit::new()`
- `jit.symbol(name, ptr)`
- `jit.compile(&back_program) -> Artifact`
- `artifact.getpointer(&func_id)`
- `artifact.getpointer_by_name("...")`
- `artifact.free()`

The important lifetime rule is:

- **function pointers stay valid only while the `Artifact` is alive**

That is deliberate. The compiled machine code is owned by the artifact's internal `JITModule`, so users must keep the artifact alive for as long as they may call any pointer obtained from it.

### Current supported backend subset

The Rust host currently supports the explicit command subset needed by the current Lua `Sem -> Back` lowering, including:

- signatures
- local/export/extern function declarations
- blocks / switching / sealing / block params / entry params
- stack slots / stack addresses / loads / stores
- integer, float, bool, and null constants
- aliasing
- integer and float arithmetic subset
- integer and float comparisons
- jumps / conditional branches / returns / trap
- direct / extern / indirect calls
- select
- cast/extension/reduction subset used by the current command layer

Notable explicit limitation kept for now:

- `BackCmdFrem` is not yet implemented in the Rust host and returns a clear error
- the direct raw-pointer artifact API currently supports **at most one function result**

### Running Rust tests

```bash
cd moonlift
cargo test
```

The Rust tests currently validate:

- direct exported function compilation and invocation
- registered extern symbol calls
- block-param CFG lowering with a loop-shaped function
- data object declaration / initialization / readback

## LuaJIT FFI bridge

This is the **current** practical bridge and the current project-priority integration path.
The near-term goal is to finish the language/compiler through this FFI-facing path first.
Only after that is done should deeper hosted/state-aware integration be revisited, and even then the working FFI path should remain available for LuaJIT users who want the simpler library/loading model.

There is now also a direct LuaJIT bridge at:

- `moonlift/lua/moonlift/jit.lua`

This bridge does **not** serialize `BackProgram`.
Lua lowers to ASDL `MoonliftBack.BackProgram`, then replays each `BackCmd` directly into the Rust `moonlift_program_t` builder through LuaJIT FFI.

### Lua-side shape

```lua
local pvm = require("pvm")
local A = require("moonlift.asdl")
local J = require("moonlift.jit")

local T = pvm.context()
A.Define(T)

local api = J.Define(T)
local jit = api.jit()
local artifact = jit:compile(back_program)
local ptr = artifact:getpointer(T.MoonliftBack.BackFuncId("main"))
```

### Build the shared library

Before using the LuaJIT bridge, build the Rust shared library once:

```bash
cd moonlift
cargo build
```

The Lua wrapper searches the default cargo output locations automatically:

- `moonlift/target/debug/`
- `moonlift/target/release/`

### Lua smoke test

```bash
cd moonlift
cargo build
cd ..
luajit moonlift/test_rust_ffi.lua
```

## Regular codegen peeking

There is now a small utility layer intended specifically for inspecting the **machine code Cranelift emits for Moonlift code**:

- `moonlift/lua/moonlift/peek.lua`
- `moonlift/examples/peek_codegen.lua`
- `moonlift/test_peek.lua`

The main intended path is:

- write Moonlift code as current reboot `Surface` ASDL
- run the normal lowering pipeline
- compile it through Cranelift
- inspect the emitted machine code regularly while adjusting ASDL/lowering design

At the lowest level, compiled artifacts from `moonlift.jit` now expose:

```lua
local artifact = jit:compile(back_program)
print(artifact:hexbytes("main", 64))
print(artifact:disasm("main", { bytes = 128 }))
```

This is intentionally simple: it grabs a function pointer, copies a fixed number of bytes from the compiled entrypoint, writes a temporary binary blob, and runs `objdump` on it. The goal is regular codegen observation, not exact object-file reconstruction.

For the higher-level Moonlift-authoring workflow, use:

```bash
cd /home/cedric/dev/gps.lua
cargo build --manifest-path moonlift/Cargo.toml
luajit moonlift/examples/peek_codegen.lua add1
luajit moonlift/examples/peek_codegen.lua switchexpr 192
```

That example is machine-code first: by default it prints the final disassembly for a chosen Moonlift shape. If the current lowering still has a bug, it prints the compile/disasm error instead.

`moonlift/lua/moonlift/peek.lua` also still retains the intermediate lowered stages, so when a generated code shape looks wrong you can correlate the final machine code back to the produced `BackProgram`.
