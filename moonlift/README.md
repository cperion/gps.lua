# moonlift

Fresh reboot of Moonlift around Lua/ASDL/pvm frontend layers and a smaller Rust backend.

The previous Rust-heavy implementation was moved to:

- `moonlift-old/`

Current focus:
- define correct ASDL compiler layers
- move semantic/frontend lowering into Lua
- keep Rust as a small validated backend/codegen layer

Design docs for the current direction:

- `moonlift/CURRENT_IMPLEMENTATION_STATUS.md` — what is and is not coded yet
- `moonlift/COMPLETE_LANGUAGE_CHECKLIST.md` — checklist from current state to complete language + hosting + FFI
- `moonlift/QUOTING_SYSTEM_DESIGN.md` — fragment/function metaprogramming design
- `moonlift/LUAJIT_HOSTED_INTEGRATION.md` — why deeper LuaJIT hosting + hosted parsing is attractive

Lua ASDL schema currently lives in a single file:

- `moonlift/lua/moonlift/asdl.lua`

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

## LuaJIT FFI bridge

This is the **current** practical bridge and remains useful.
Longer-term, Moonlift may prefer a deeper LuaJIT/state-aware hosted integration, but that does **not** rule out also providing a plain FFI-facing API later for LuaJIT users who want the simpler library/loading model.


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
