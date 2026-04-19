# watjit

*A C-like DSL for LuaJIT that compiles to native code via WebAssembly. Terra-grade power, no LLVM, portable by construction, deterministic memory.*

---

## Table of contents

1. [What this is](#what-this-is)
2. [Why this exists](#why-this-exists)
3. [The architecture](#the-architecture)
4. [Layer 0: Wasmtime / Cranelift](#layer-0-wasmtime--cranelift)
5. [Layer 1: watjit — the C-like DSL](#layer-1-watjit--the-c-like-dsl)
6. [Layer 2: language features](#layer-2-language-features)
7. [Layer 3: systems abstractions](#layer-3-systems-abstractions)
8. [Layer 4: domain libraries](#layer-4-domain-libraries)
9. [A complete worked example](#a-complete-worked-example)
10. [Comparison to Terra and alternatives](#comparison-to-terra-and-alternatives)
11. [Implementation plan](#implementation-plan)
12. [Non-goals](#non-goals)
13. [The thesis](#the-thesis)

---

## What this is

watjit is a stack of small Lua libraries that together let you write native-speed systems code — numeric kernels, DSP, interpreters, parsers, codegen backends — entirely inside LuaJIT. You write the code in a C-like Lua DSL. It compiles through WebAssembly to native machine code via Wasmtime/Cranelift. The result runs at native speed on x86-64 and ARM64, with no GC interaction, no LLVM dependency, and no build step.

It is Terra's idea — Lua as the meta-language, a low-level language as the object language — reimplemented with WebAssembly as the object language and Wasmtime as the backend. Same power. Better ergonomics. No LLVM.

The whole stack is roughly 2,000 lines of Lua for the core layers. Each layer is independently useful and can be adopted on its own. The project has one external dependency: the Wasmtime shared library.

A companion library, **iwatjit**, was explored as an incremental (memoized)
layer on top of watjit, but that experiment has been retired for now. This
document is only about watjit itself. The retired design notes live under
`archive/iwatjit_retired/IWATJIT.md`.

---

## Why this exists

Three problems drove this project.

**LuaJIT alone is unreliable for kernels.** The JIT is fast when it works, but GC pauses, trace recording, NYI bytecodes, and type instability create unpredictable performance cliffs. Numeric code, real-time audio, hard latency budgets — these require guarantees LuaJIT cannot provide on its own.

**C is a toolchain, not a language feature.** The standard answer to "write it in C and FFI it" assumes a build system, a C compiler, target-specific compilation, and a loss of the Lua development loop. For a library author shipping Lua code, C is a distribution problem.

**Terra solved this once, but dragged in LLVM.** Terra showed the pattern works: a two-level language where Lua generates and specializes low-level code at runtime. But Terra is tied to LLVM — hundreds of megabytes of dependency, x86-centric in practice, slow to compile, hard to embed.

The observation that makes watjit possible: WebAssembly is now a production-quality portable low-level target, and Wasmtime is a stable, embeddable, actively-maintained implementation. The substrate exists. The tools exist. The stack just needs to be assembled.

---

## The architecture

Five layers. Each is independently useful. Each is built on the one below and reaches no further.

```
┌──────────────────────────────────────────────────┐
│  Layer 4: Domain libraries                       │
│  DSP, linear algebra, image, parsers, JITs       │
├──────────────────────────────────────────────────┤
│  Layer 3: Systems abstractions                   │
│  structs, arrays, arenas, typed memory           │
├──────────────────────────────────────────────────┤
│  Layer 2: Language features                      │
│  generics, macros, inline, specialization        │
├──────────────────────────────────────────────────┤
│  Layer 1: watjit — C-like WAT DSL                │
│  types, expressions, control flow, modules       │
├──────────────────────────────────────────────────┤
│  Layer 0: Wasmtime / Cranelift                   │
│  native compilation and execution substrate      │
└──────────────────────────────────────────────────┘
```

Every arrow in that diagram points up. No layer reaches sideways or downward past its immediate neighbor. The stack is strictly layered.

### Design principles

Four principles, applied consistently across all layers.

**Small, focused libraries that compose.** Each layer does one thing. None depends on anything it doesn't need. The core DSL does not know about structs. Structs do not know about arenas at the API level. Each piece is understandable alone.

**Lua all the way down.** No second language. No preprocessor. No build step. Every layer is written in normal Lua, using normal Lua mechanisms — metatables, closures, no-parens calls, operator overloading. Users learn Lua, not watjit.

**Inspectable at every level.** Generated WAT is text. Intermediate representations are Lua tables. Nothing is opaque. Debugging means reading the output of the layer above. This is what Terra lost by emitting LLVM IR — a clear picture of the generated code. watjit keeps it.

**Determinism where it matters.** Memory allocation is explicit. Arena lifetime is explicit. Specialization is a function call, not a compiler heuristic. Performance characteristics are predictable because the mechanisms are visible.

---

## Layer 0: Wasmtime / Cranelift

An external dependency. One shared library (~30 MB). Stable C API. Accessed via LuaJIT's FFI through a thin binding.

This is the only external dependency of the entire project. No LLVM, no Rust toolchain, no build infrastructure. Drop `libwasmtime.so` (or `.dll` / `.dylib`) next to your Lua files and everything works.

### wasmtime.lua — the FFI binding

The entire binding is about 150 lines. Its surface is three operations: compile WAT text into a module, extract a function by name, and expose linear memory for shared data.

```lua
-- wasmtime.lua — FFI binding to Wasmtime's C API
-- Exposes only what watjit needs: engine, module, export, memory

local ffi = require "ffi"

ffi.cdef[[
    typedef struct wasm_engine_t          wasm_engine_t;
    typedef struct wasmtime_store_t       wasmtime_store_t;
    typedef struct wasmtime_context_t     wasmtime_context_t;
    typedef struct wasmtime_module_t      wasmtime_module_t;
    typedef struct wasmtime_instance_t    wasmtime_instance_t;
    typedef struct wasmtime_error_t       wasmtime_error_t;

    typedef struct wasm_byte_vec_t {
        size_t   size;
        uint8_t* data;
    } wasm_byte_vec_t;

    // engine + store
    wasm_engine_t*        wasm_engine_new(void);
    void                  wasm_engine_delete(wasm_engine_t*);
    wasmtime_store_t*     wasmtime_store_new(wasm_engine_t*, void*, void (*)(void*));
    void                  wasmtime_store_delete(wasmtime_store_t*);
    wasmtime_context_t*   wasmtime_store_context(wasmtime_store_t*);

    // WAT -> WASM bytes
    wasmtime_error_t*     wasmtime_wat2wasm(const char*, size_t, wasm_byte_vec_t*);

    // module compilation
    wasmtime_error_t*     wasmtime_module_new(wasm_engine_t*, const uint8_t*, size_t,
                                              wasmtime_module_t**);
    void                  wasmtime_module_delete(wasmtime_module_t*);

    // instance + export lookup -- simplified signatures;
    // the real API uses wasmtime_extern_t for exports and we wrap that
    wasmtime_error_t*     wasmtime_instance_new(wasmtime_context_t*, const wasmtime_module_t*,
                                                const void*, size_t, wasmtime_instance_t*,
                                                void*);

    // get exported function as a raw callable pointer (wrapping logic in Lua)
    void*                 wasmtime_instance_export_get_fn(wasmtime_context_t*,
                                                          wasmtime_instance_t*,
                                                          const char*, size_t);

    // linear memory access
    uint8_t*              wasmtime_memory_data(wasmtime_context_t*, void*);
    size_t                wasmtime_memory_data_size(wasmtime_context_t*, void*);

    // error handling
    void                  wasmtime_error_message(const wasmtime_error_t*, wasm_byte_vec_t*);
    void                  wasmtime_error_delete(wasmtime_error_t*);
    void                  wasm_byte_vec_delete(wasm_byte_vec_t*);
]]

local wt = ffi.load("wasmtime")
local M  = {}

-- check and raise on error
local function check(err)
    if err ~= nil then
        local msg = ffi.new("wasm_byte_vec_t")
        wt.wasmtime_error_message(err, msg)
        local text = ffi.string(msg.data, msg.size)
        wt.wasm_byte_vec_delete(msg)
        wt.wasmtime_error_delete(err)
        error("wasmtime: " .. text, 2)
    end
end

-- create a new engine (one per process is typical)
function M.engine()
    local e = wt.wasm_engine_new()
    ffi.gc(e, wt.wasm_engine_delete)
    return e
end

-- compile WAT text into a native module
function M.compile(engine, wat_text)
    local wasm = ffi.new("wasm_byte_vec_t")
    check(wt.wasmtime_wat2wasm(wat_text, #wat_text, wasm))

    local mod = ffi.new("wasmtime_module_t*[1]")
    check(wt.wasmtime_module_new(engine, wasm.data, wasm.size, mod))
    wt.wasm_byte_vec_delete(wasm)

    ffi.gc(mod[0], wt.wasmtime_module_delete)
    return mod[0]
end

-- instantiate a module and return an object with :fn(name, signature)
function M.instantiate(engine, module)
    local store   = wt.wasmtime_store_new(engine, nil, nil)
    ffi.gc(store, wt.wasmtime_store_delete)
    local context = wt.wasmtime_store_context(store)

    local inst = ffi.new("wasmtime_instance_t")
    check(wt.wasmtime_instance_new(context, module, nil, 0, inst, nil))

    return {
        store   = store,
        context = context,
        inst    = inst,

        -- get an export as a callable function via FFI cast
        -- signature is a C function pointer type: "double(*)(double,double)"
        fn = function(self, name, signature)
            local ptr = wt.wasmtime_instance_export_get_fn(
                self.context, self.inst, name, #name)
            if ptr == nil then
                error("no export named '" .. name .. "'", 2)
            end
            return ffi.cast(signature, ptr)
        end,

        -- get exported memory as a typed pointer into Wasm linear memory
        memory = function(self, name, element_type)
            -- ... similar pattern, returns ffi pointer
        end,
    }
end

return M
```

The surface is deliberately small. A user of the watjit DSL never touches this module directly — `module:compile(engine)` hides it. But it is a clean standalone tool: someone who already has hand-written WAT can use `wasmtime.lua` to run it.

---

## Layer 1: watjit — the C-like DSL

The base. About 600 lines split across a few files. Lets you write C-like code in Lua and compile it to native through Wasmtime.

### fragment.lua — the composable line buffer

Both watjit and any other text-generation tool build on this. Pure utility, no dependencies.

```lua
-- fragment.lua — composable indented line buffer

local F = {}
local mt = { __index = F }

function F.new()
    return setmetatable({
        lines  = {},
        indent = 0,
    }, mt)
end

-- write one formatted line at the current indent level
function F:write(fmt, ...)
    local text = select("#", ...) > 0 and fmt:format(...) or fmt
    self.lines[#self.lines + 1] = string.rep("  ", self.indent) .. text
    return self
end

-- open a nesting level: write a line, then indent for subsequent lines
function F:open(fmt, ...)
    self:write(fmt, ...)
    self.indent = self.indent + 1
    return self
end

-- close a nesting level: dedent, then write ")"
function F:close()
    self.indent = self.indent - 1
    return self:write(")")
end

-- splice another fragment in at the current indent level
function F:emit(other)
    local prefix = string.rep("  ", self.indent)
    for _, line in ipairs(other.lines) do
        self.lines[#self.lines + 1] = prefix .. line
    end
    return self
end

function F:source()
    return table.concat(self.lines, "\n")
end

mt.__tostring = F.source

setmetatable(F, { __call = function() return F.new() end })
return F
```

That's the entire utility. Every WAT emission in the framework goes through this. The indentation semantics and S-expression structure of WAT fall out of `open` / `close` naturally.

### Types as constructors

The key design choice in watjit: every Wasm type is a Lua object that can be *called*, and what it does depends on what you pass. This collapses what C spells three different ways (declaration, cast, literal) into one consistent mechanism.

```lua
-- watjit_types.lua — type objects, typed Val, operator overloading

local F   = require "fragment"
local Val = {}
Val.__index = Val

-- a typed Val represents a WAT expression with a known type
-- .expr is an ASDL-like table describing the WAT expression
-- .t is the type tag
function Val.new(expr, t) return setmetatable({expr=expr, t=t}, Val) end

-- when two Vals are combined, their types must match; the type flows through
local function coerce(x, t)
    if type(x) == "number" then
        return Val.new({op="const", t=t, value=x}, t)
    elseif type(x) == "string" then
        -- bare string in an expression context means "look up this named local"
        return Val.new({op="get", name=x}, t)  -- caller must validate type
    end
    return x  -- already a Val
end

-- arithmetic: builds an Add/Sub/Mul/Div node, keeps type
Val.__add = function(a, b)
    a, b = coerce(a), coerce(b, a.t or b.t)
    return Val.new({op="add", t=a.t, l=a.expr, r=b.expr}, a.t)
end
Val.__sub = function(a, b)
    a, b = coerce(a), coerce(b, a.t or b.t)
    return Val.new({op="sub", t=a.t, l=a.expr, r=b.expr}, a.t)
end
Val.__mul = function(a, b)
    a, b = coerce(a), coerce(b, a.t or b.t)
    return Val.new({op="mul", t=a.t, l=a.expr, r=b.expr}, a.t)
end

-- comparisons always return i32 (Wasm has no bool type)
function Val:lt(b) b = coerce(b, self.t)
    return Val.new({op="lt", t=self.t, l=self.expr, r=b.expr}, i32) end
function Val:le(b) b = coerce(b, self.t)
    return Val.new({op="le", t=self.t, l=self.expr, r=b.expr}, i32) end
function Val:eq(b) b = coerce(b, self.t)
    return Val.new({op="eq", t=self.t, l=self.expr, r=b.expr}, i32) end
-- ... ge, gt, ne similarly

-- a type is a Lua object with a metatable that makes it callable.
-- calling it different ways does different things.
local function make_type(name, size, wat_name)
    local T = { name = name, size = size, wat = wat_name }
    setmetatable(T, {
        __call = function(self, a, b)
            -- type(number)       → typed constant
            -- type(name)         → declaration, returns Val bound to that name
            -- type(name, init)   → declaration + initialization
            if type(a) == "number" then
                return Val.new({op="const", t=self, value=a}, self)
            elseif type(a) == "string" then
                local v = Val.new({op="get", name=a}, self)
                v.name = a
                v.decl = true  -- scope collector picks these up
                if b ~= nil then v.init = coerce(b, self) end
                return v
            end
            error(("bad call to type %s"):format(self.name), 2)
        end,
        __tostring = function(self) return self.name end,
    })
    return T
end

local i32 = make_type("i32", 4, "i32")
local i64 = make_type("i64", 8, "i64")
local f32 = make_type("f32", 4, "f32")
local f64 = make_type("f64", 8, "f64")

-- pointer type: an i32 Val that remembers what it points to
-- supports a[i] indexing via __index / __newindex, scaled by element size
local function ptr(element_type)
    local P = { name = "ptr("..element_type.name..")", elem = element_type, size = 4 }
    setmetatable(P, {
        __call = function(self, name, init)
            if type(name) == "string" then
                local v = Val.new({op="get", name=name}, self)
                v.name, v.decl = name, true
                if init ~= nil then v.init = coerce(init, self) end
                return v
            end
            error("cannot construct ptr literal; use a pointer variable", 2)
        end,
        __tostring = function(self) return self.name end,
    })
    return P
end

-- pointer Vals get an indexing metatable (glued on when Val.new sees a ptr type)
-- p[i] builds: (load t (add ptr (mul i elem_size)))
-- p[i] = v builds: (store t (add ptr (mul i elem_size)) v)

return {
    Val = Val, coerce = coerce,
    i32 = i32, i64 = i64, f32 = f32, f64 = f64,
    ptr = ptr,
    void = { name = "void" },  -- sentinel for no-return funcs
}
```

The `coerce` function is the bridge that makes strings and numbers work inside expressions. When you write `a + 1` inside a watjit body, the `1` is a Lua number but `a` is a Val; `__add` calls `coerce(1, a.t)` and produces a typed constant. When you write `a + "b"`, the `"b"` is coerced to `get "b"` in the current scope. This is what lets expressions read like C.

### Scopes and assignment

A scope is the accumulator for statements inside a function body. When you write `sum:set(sum + f64(1.0))` inside a body, the new expression is pushed onto the current scope's statement list. A scope stack tracks nested bodies (inside loops, conditionals, etc.).

```lua
-- watjit_scope.lua — statement collection for function bodies

local Scope = {}
Scope.__index = Scope

local stack = {}  -- stack of active scopes

function Scope.push()
    local s = setmetatable({
        stmts = {},
        decls = {},  -- local declarations collected from Val constructors
    }, Scope)
    stack[#stack+1] = s
    return s
end

function Scope.pop()   return table.remove(stack)                  end
function Scope.current() return stack[#stack]                      end

function Scope:push(stmt)             self.stmts[#self.stmts+1] = stmt end
function Scope:declare(name, t)       self.decls[#self.decls+1] = {name=name, t=t} end
function Scope:assign(name, val)      self:push({op="set", name=name, value=val.expr}) end

return Scope
```

Assignment in watjit bodies is done via the `:set` method on a Val. Because Lua doesn't let you overload assignment to a local variable, you have to spell it explicitly:

```lua
-- in a watjit body:
sum:set(sum + f64(1.0))   -- same as C's sum += 1.0;
```

`:set` is a method on Val that takes the right-hand side and emits a Set statement into the current scope. It's one more token than `=`, and it's unambiguous about what it does.

```lua
Val.set = function(self, rhs)
    if self.name == nil then
        error("cannot assign to unnamed Val", 2)
    end
    Scope.current():assign(self.name, coerce(rhs, self.t))
end
```

### Control flow helpers

Every C-style control flow construct is implemented as a function that takes a condition (or a variable and range) and returns a function expecting the body as a table.

```lua
-- watjit_ctrl.lua — control flow helpers

local Scope = require "watjit_scope"
local next_label = 0
local function fresh(name)
    next_label = next_label + 1
    return ("$%s_%d"):format(name, next_label)
end

-- for_(var, to) { body }
-- for_(var, from, to) { body }
-- for_(var, from, to, step) { body }
--
-- emits: (block (loop (br_if not_cond) body increment (br loop)))
local function for_(var, from_or_to, maybe_to, maybe_step)
    local from, to, step
    if maybe_to == nil then
        from, to, step = var.t(0), from_or_to, var.t(1)
    else
        from, to, step = from_or_to, maybe_to, (maybe_step or var.t(1))
    end

    return function(body_table)
        -- body_table is {stmt, stmt, ...} as collected from body construction
        local body_stmts = body_table  -- already a list of statements

        local lbl_break = fresh("break")
        local lbl_loop  = fresh("loop")
        local stmt = {
            op = "block", label = lbl_break,
            body = {
                {op="set", name=var.name, value=from.expr},
                {op="loop", label=lbl_loop, body = concat(
                    {{op="br_if", label=lbl_break,
                      cond={op="eqz", t=var.t,
                            val={op="lt", t=var.t,
                                 l={op="get", name=var.name},
                                 r=to.expr}}}},
                    body_stmts,
                    {{op="set", name=var.name,
                      value={op="add", t=var.t,
                             l={op="get", name=var.name},
                             r=step.expr}},
                     {op="br", label=lbl_loop}}
                )}
            }
        }
        Scope.current():push(stmt)
    end
end

local function if_(cond)
    return function(then_body)
        local stmt = {op="if", cond=cond.expr, then_=then_body, else_={}}
        Scope.current():push(stmt)
        return {
            else_ = function(else_body) stmt.else_ = else_body end,
        }
    end
end

local function while_(cond)
    return function(body_table)
        local lbl_break, lbl_loop = fresh("break"), fresh("loop")
        Scope.current():push({
            op = "block", label = lbl_break,
            body = {
                {op="loop", label=lbl_loop, body=concat(
                    {{op="br_if", label=lbl_break,
                      cond={op="eqz", t=cond.t, val=cond.expr}}},
                    body_table,
                    {{op="br", label=lbl_loop}}
                )}
            }
        })
    end
end

-- break_ and continue_ are sentinels recognized by the enclosing loop
-- they compile to (br $outer_label) and (br $loop_label) respectively

return { for_ = for_, if_ = if_, while_ = while_ }
```

### Function definitions and modules

```lua
-- watjit_func.lua — function definitions with curried signatures

local Scope = require "watjit_scope"

-- func "name" (p1, p2, p3) :returns(t) {body_fn}
-- returns is optional (defaults to void)
local function func(name)
    return function(...)
        local params = {...}
        local p_list = {}
        for i, p in ipairs(params) do
            p_list[i] = {name = p.name, t = p.t}
        end

        local ret_type = void
        local function make_body(body_fn)
            local s = Scope.push()
            local ret = body_fn(table.unpack(params))
            if ret ~= nil then
                s:push({op="return", value=coerce(ret, ret_type).expr})
            end
            local scope = Scope.pop()
            return {
                op      = "func",
                name    = name,
                params  = p_list,
                locals  = scope.decls,
                ret     = ret_type,
                body    = scope.stmts,
            }
        end

        local tail = {}
        function tail:returns(t) ret_type = t; return tail end
        setmetatable(tail, { __call = function(_, body_tbl)
            return make_body(body_tbl[1])
        end})
        return tail
    end
end

-- module: collects functions, provides :wat, :compile, and :fn
local function module(funcs)
    local m = { funcs = funcs }

    function m:wat()
        local f = require "fragment".new()
        f:open("(module")
        f:write("(memory (export \"memory\") 1)")
        for _, fn in ipairs(funcs) do emit_func(f, fn) end
        f:close()
        return tostring(f)
    end

    function m:compile(engine)
        local wasmtime = require "wasmtime"
        local mod  = wasmtime.compile(engine, self:wat())
        local inst = wasmtime.instantiate(engine, mod)
        return inst   -- has :fn(name, signature) and :memory(name, type)
    end

    return m
end

return { func = func, module = module }
```

### The emit pass

The final piece: turn the ASDL-like tree into WAT text. A simple recursive emitter.

```lua
-- watjit_emit.lua — tree → WAT text

local function emit_expr(f, node)
    if node.op == "const" then
        f:write("(%s.const %s)", node.t.wat, node.value)
    elseif node.op == "get" then
        f:write("(local.get $%s)", node.name)
    elseif node.op == "add" or node.op == "sub"
        or node.op == "mul" or node.op == "div" then
        f:open("(%s.%s", node.t.wat, node.op)
        emit_expr(f, node.l); emit_expr(f, node.r)
        f:close()
    elseif node.op == "load" then
        f:open("(%s.load", node.t.wat)
        emit_expr(f, node.ptr)
        f:close()
    elseif node.op == "eqz" then
        f:open("(%s.eqz", node.t.wat)
        emit_expr(f, node.val)
        f:close()
    -- ... lt, le, gt, ge, eq, ne similarly
    else error("unknown expr op: " .. tostring(node.op)) end
end

local function emit_stmt(f, node)
    if node.op == "set" then
        f:open("(local.set $%s", node.name)
        emit_expr(f, node.value)
        f:close()
    elseif node.op == "store" then
        f:open("(%s.store", node.t.wat)
        emit_expr(f, node.ptr); emit_expr(f, node.value)
        f:close()
    elseif node.op == "block" or node.op == "loop" then
        f:open("(%s %s", node.op, node.label)
        for _, s in ipairs(node.body) do emit_stmt(f, s) end
        f:close()
    elseif node.op == "br" then
        f:write("(br %s)", node.label)
    elseif node.op == "br_if" then
        f:open("(br_if %s", node.label); emit_expr(f, node.cond); f:close()
    elseif node.op == "if" then
        f:open("(if"); emit_expr(f, node.cond)
        f:open("(then"); for _,s in ipairs(node.then_) do emit_stmt(f,s) end; f:close()
        if #node.else_ > 0 then
            f:open("(else"); for _,s in ipairs(node.else_) do emit_stmt(f,s) end; f:close()
        end
        f:close()
    elseif node.op == "return" then
        f:open("(return"); emit_expr(f, node.value); f:close()
    else error("unknown stmt op: " .. tostring(node.op)) end
end

local function emit_func(f, fn)
    f:open('(func $%s (export "%s")', fn.name, fn.name)
    for _, p in ipairs(fn.params) do
        f:write("(param $%s %s)", p.name, p.t.wat)
    end
    if fn.ret and fn.ret.wat then f:write("(result %s)", fn.ret.wat) end
    for _, l in ipairs(fn.locals) do
        f:write("(local $%s %s)", l.name, l.t.wat)
    end
    for _, s in ipairs(fn.body) do emit_stmt(f, s) end
    f:close()
end

return { emit_expr = emit_expr, emit_stmt = emit_stmt, emit_func = emit_func }
```

That completes the lowest level. The user writes C-like Lua, the DSL builds an ASDL-like tree, `emit_func` produces WAT text, `wasmtime.lua` compiles it, and `module:fn(name, signature)` hands back a native function pointer.

---

## Layer 2: language features

Built on the watjit DSL. Adds the pieces that turn a code generator into a language. None of these require new primitives — they fall out of watjit being a normal Lua library with first-class values.

### Generics

A generic function is a Lua function that takes types and returns a specialized `func` definition. Full power of C++ templates, in the host language:

```lua
-- vec_add<T>(a, b, c, n): c[i] = a[i] + b[i] for i in 0..n
local function vec_add(T)
    return func("vec_add_"..T.name) (
        ptr(T) "a", ptr(T) "b", ptr(T) "c", i32 "n"
    ) {function(a, b, c, n)
        local i = i32("i", 0)
        for_(i, n) {
            c[i] = a[i] + b[i],
        }
    end}
end

local vec_add_f32 = jit(vec_add(f32))
local vec_add_f64 = jit(vec_add(f64))
local vec_add_i32 = jit(vec_add(i32))
```

The type `T` is a Lua value captured by the closure. When `vec_add(f64)` is called, `T` is bound to the `f64` type object, and the resulting `ptr(T)`, `T(0)`, etc. produce f64-specialized WAT. The compiler sees monomorphic code; the user writes it once.

### Macros

A macro in watjit is a Lua function that takes Val expressions and returns Val expressions, structurally inlined into the call site:

```lua
-- saturate(x, lo, hi) = max(lo, min(hi, x))
local function saturate(x, lo, hi)
    return max_(lo, min_(hi, x))
end

-- use inline:
c[i] = saturate(a[i] + b[i], f32(0), f32(1))
```

No call overhead. No dispatch. The macro is pure Lua running at codegen time; its result is spliced into the expression tree and becomes part of the generated WAT. Same semantics as a C inline function. Zero runtime cost.

### Specialization on constants

The biggest win: closing over Lua values from the enclosing scope bakes them into the generated WAT as literal constants. The compiler sees them as known, and Cranelift optimizes accordingly.

```lua
-- FIR filter specialized on its coefficients
-- the loop is unrolled at codegen time, coefficients baked in
local function make_filter(coeffs)
    local N = #coeffs

    return func "filter" (f32ptr "x", f32ptr "y", i32 "n") {function(x, y, n)
        local i = i32("i", N-1)

        for_(i, n) {
            local acc = f32("acc", 0.0)
            -- this is a Lua for loop: it runs at codegen time,
            -- emitting N separate multiply-add instructions.
            for j = 0, N-1 do
                acc:set(acc + f32(coeffs[j+1]) * x[i - i32(j)])
            end
            y[i] = acc,
        }
    end}
end

local fir = jit(make_filter({0.1, 0.2, 0.4, 0.2, 0.1}))
```

The inner `for j = 0, N-1` is Lua. It runs during codegen. Each iteration emits one multiply-add statement into the WAT body. The resulting kernel has no loop for the convolution — just a straight line of N multiplies and N adds, coefficient values baked in as f32 literals. Specialization that static C cannot match without preprocessor tricks.

---

## Layer 3: systems abstractions

The pieces that make WAT usable for non-trivial programs without hand-rolling memory management for every kernel.

### Typed structs

Wasm has no struct type — linear memory is flat bytes. A struct in watjit is metadata (field name → offset, type) plus a wrapper that generates the right loads and stores.

```lua
-- struct.lua — typed structs over Wasm linear memory

local function struct(name, fields)
    local ordered, offsets, offset = {}, {}, 0

    for i, field in ipairs(fields) do
        local fname, ftype = field[1], field[2]
        offsets[fname] = offset
        ordered[i] = {name=fname, type=ftype, offset=offset}
        offset = offset + ftype.size
    end

    local S = {
        name    = name,
        size    = offset,
        fields  = ordered,
        offsets = offsets,
    }

    -- wrap a base pointer; s.x → load at (base + offset_x), etc.
    function S.at(base_ptr)
        return setmetatable({_base = base_ptr, _struct = S}, {
            __index = function(self, fname)
                local field
                for _, f in ipairs(ordered) do
                    if f.name == fname then field = f; break end
                end
                if field == nil then error("no field " .. fname, 2) end
                local addr = base_ptr + i32(field.offset)
                return Val.new({op="load", t=field.type, ptr=addr.expr}, field.type)
            end,
            __newindex = function(self, fname, val)
                local field
                for _, f in ipairs(ordered) do
                    if f.name == fname then field = f; break end
                end
                if field == nil then error("no field " .. fname, 2) end
                local addr = base_ptr + i32(field.offset)
                Scope.current():push({
                    op="store", t=field.type,
                    ptr=addr.expr, value=coerce(val, field.type).expr
                })
            end,
        })
    end

    return S
end

-- usage:
local Vec3 = struct("Vec3", {
    {"x", f32}, {"y", f32}, {"z", f32},
})

-- inside a watjit body, given a base pointer p of type ptr(Vec3):
-- local v = Vec3.at(p)
-- v.x = f32(1.0)
-- v.y = f32(2.0)
-- local mag_sq = v.x*v.x + v.y*v.y + v.z*v.z
```

The struct is completely transparent — it generates exactly the loads and stores you would write by hand, with the field offsets computed from the layout. No runtime overhead, no dispatch. Just typed memory access.

### Arenas — the bump allocator

Deterministic memory management, implemented as WAT helper functions generated at module-definition time:

```lua
-- arena.lua — bump allocator in Wasm linear memory

-- An arena occupies a contiguous region of linear memory.
-- It maintains a bump pointer; alloc bumps forward, reset sets it back.
-- No freeing of individual allocations; the only reclamation is reset.

local function arena(capacity)
    return {
        capacity = capacity,

        -- install generates arena_init, arena_alloc, arena_reset as watjit funcs
        install = function(self, module)
            local init = func "arena_init" (i32 "base") {function(base)
                -- [base .. base+4): current bump pointer
                -- [base+4 .. base+8): capacity
                -- allocatable region starts at base+8
                i32ptr.at(base):set(base + i32(8))
                i32ptr.at(base + i32(4)):set(i32(capacity))
            end}

            local alloc = func "arena_alloc" (i32 "base", i32 "size")
                :returns(i32) {function(base, size)
                -- align size up to 8 bytes
                local aligned = (size + i32(7)):band(i32(-8))
                local bump = i32.load(base)
                local new_bump = bump + aligned
                -- check capacity
                if_(new_bump:gt(base + i32(8) + i32.load(base + i32(4)))) {
                    unreachable,   -- arena exhausted: hard error
                }
                i32ptr.at(base):set(new_bump)
                return bump
            end}

            local reset = func "arena_reset" (i32 "base") {function(base)
                i32ptr.at(base):set(base + i32(8))
            end}

            module:add(init, alloc, reset)
        end,
    }
end
```

The arena is a few WAT functions plus a convention about metadata layout. O(1) alloc, O(1) reset, zero fragmentation. Exactly what C systems programmers build by hand. Made safe by typed accessors (the struct wrappers). Made portable by compiling to WAT.

### Slab allocators and LRU caches

Same pattern, more elaborate. The slab allocator divides the arena into fixed-size slots with a free list. The LRU cache adds a doubly-linked list for recency tracking. Both are a few hundred lines of Lua that generate a few dozen lines of WAT per installed instance.

The key insight: memory management strategies become small libraries that install WAT helpers, not framework machinery. If a user wants a different strategy, they write a new library. The base system does not impose a choice.

---

## Layer 4: domain libraries

Once layers 1–3 exist, domain libraries are just normal Lua code that uses them. No upper bound — this is where the ecosystem grows.

### Example: a DSP primitive library

```lua
-- dsp/fir.lua — FIR filter kernel generators

local wj = require "watjit"

local dsp = {}

function dsp.fir(T, coeffs)
    local N = #coeffs
    local Tptr = wj.ptr(T)

    return wj.func("fir") (Tptr "x", Tptr "y", wj.i32 "n") {function(x, y, n)
        local i = wj.i32("i", N-1)
        for_(i, n) {
            local acc = T("acc", T(0))
            for j = 0, N-1 do
                acc:set(acc + T(coeffs[j+1]) * x[i - wj.i32(j)])
            end
            y[i] = acc,
        }
    end}
end

function dsp.biquad(T, b0, b1, b2, a1, a2)
    local Tptr = wj.ptr(T)
    return wj.func("biquad") (Tptr "x", Tptr "y",
                              T "z1_in", T "z2_in", wj.i32 "n")
        :returns(T) {function(x, y, z1_in, z2_in, n)
        local z1 = T("z1", z1_in)
        local z2 = T("z2", z2_in)
        local i  = wj.i32("i", 0)
        for_(i, n) {
            local xn = T("xn", x[i])
            local yn = T("yn", T(b0) * xn + z1)
            z1:set(T(b1) * xn - T(a1) * yn + z2),
            z2:set(T(b2) * xn - T(a2) * yn),
            y[i] = yn,
        }
        return z1
    end}
end

return dsp
```

A hundred lines of Lua generate specialized kernels for any filter the user describes. Each kernel is compiled once (the user caches it, or a future incremental layer caches it structurally), and called at native speed.

### Other domain libraries

- **Linear algebra** — BLAS-style operations specialized on dimensions.
- **Image processing** — convolutions specialized on kernel sizes.
- **Parsing** — combinators that generate specialized recognizers.
- **Interpreters** — bytecode dispatch with specialized opcodes.
- **JITs** — pipelines where watjit generates kernels for user programs at runtime.

Each is a library on top of watjit. None requires modifying watjit. The base library stays small and stable; the ecosystem grows above it.

---

## A complete worked example

A fully-specialized matrix multiply, compiled to native code and called from Lua. Exercises every layer.

```lua
local wj       = require "watjit"
local wasmtime = require "wasmtime"
local ffi      = require "ffi"

local i32, f64 = wj.i32, wj.f64
local f64ptr   = wj.ptr(f64)

-- layer 2: a generator function
local function make_matmul(M, N, K)
    return wj.func "matmul" (f64ptr "a", f64ptr "b", f64ptr "c") {function(a, b, c)
        local i   = i32("i", 0)
        local j   = i32("j", 0)
        local k   = i32("k", 0)
        local sum = f64("sum", 0.0)

        for_(i, i32(M)) {
            for_(j, i32(N)) {
                sum:set(f64(0.0)),
                for_(k, i32(K)) {
                    sum:set(sum +
                        a[i * i32(K) + k] *
                        b[k * i32(N) + j])
                },
                c[i * i32(N) + j] = sum,
            },
        }
    end}
end

-- compile for a specific shape
local engine = wasmtime.engine()
local m3x4x4 = wj.module { make_matmul(3, 4, 4) }:compile(engine)
local matmul = m3x4x4:fn("matmul", "void(*)(double*,double*,double*)")

-- FFI-allocated data, outside LuaJIT's GC
local a = ffi.new("double[12]")
local b = ffi.new("double[16]")
local c = ffi.new("double[12]")
-- ... fill a, b ...

-- call at native speed
matmul(a, b, c)
```

The dimensions M=3, N=4, K=4 are baked into the generated WAT as constants. Cranelift sees fixed loop bounds and optimizes — unrolling, constant propagation, strength reduction on address computations. The kernel runs with no GC involvement, no LuaJIT tracing, no warmup curve. The first call is fast.

---

## Comparison to Terra and alternatives

| | watjit | Terra | LuaJIT FFI + C |
|---|---|---|---|
| Meta-language | Lua | Lua | Lua |
| Object language | WAT (W3C std) | Terra DSL | C |
| Compiler | Cranelift | LLVM | any C compiler |
| Dependency size | ~30 MB (wasmtime) | ~500 MB (LLVM) | toolchain |
| Build step | no | no | yes |
| Runtime compilation | yes | yes | no |
| Specialization | yes (Lua closures) | yes (quote/escape) | no |
| Inspectable IR | WAT text | LLVM IR | source |
| x86-64 | ✓ | ✓ | ✓ |
| ARM64 | ✓ | ✓ | ✓ (separate build) |
| Apple Silicon | ✓ first-class | partial | ✓ (separate build) |
| Browser (Wasm) | ✓ | ✗ | ✗ |
| Compile time per function | µs to low ms | tens of ms | seconds (build) |
| GC interaction | none | present | none |
| Peak optimization | Cranelift (good) | LLVM (deeper) | C compiler (deepest for static) |
| SIMD | 128-bit (Wasm SIMD) | full | full |

The honest tradeoffs: LLVM optimizes more deeply than Cranelift for general code. Wasm SIMD is 128-bit where AVX2 is 256-bit. These are real limitations. For the 95% case — specialized numeric kernels, systems code, runtime codegen — watjit is the better tool because the tradeoff pays for itself in portability, compile time, and deployment simplicity.

---

## Implementation plan

Ordered by dependency. Each phase is independently demonstrable.

### Phase 1: the base

1. `fragment.lua` — line buffer, indent, splice.
2. `wasmtime.lua` — FFI binding. Validate against a hardcoded "add two ints" WAT string.
3. `watjit_types.lua` — i32, f64, ptr, Val, operator overloading.
4. `watjit_ctrl.lua` — for_, while_, if_, break_, return.
5. `watjit_func.lua` + `watjit_emit.lua` — func, module, compile, fn.

**Milestone 1**: compile `add(a, b) = a + b` from Lua, call via FFI, get the right answer. All of layer 1 working end to end.

### Phase 2: first real kernel

6. Matrix multiply, parameterized by dimensions.
7. Benchmark against: Terra, hand-written C with `-O3`, naive Lua.

**Milestone 2**: matmul(64, 64, 64) within 20% of Terra. If yes, the project is viable.

### Phase 3: language features (layer 2)

8. Generics helpers, documented idioms.
9. Macro patterns, structural inlining.
10. Specialization examples — FIR filter with baked coefficients.

**Milestone 3**: specialized FIR outperforms a variable-coefficient FIR by a measurable margin.

### Phase 4: systems abstractions (layer 3)

11. `struct.lua`, `array.lua`, `arena.lua`, `slab.lua`, `lru.lua`.

**Milestone 4**: a kernel that uses structs, arrays, and arenas together. Memory discipline proven.

### Phase 5: first domain library

12. Pick one: DSP, linear algebra, or parsing.
13. Build enough to solve a real problem end to end.

**Milestone 5**: external user solves a real problem with watjit and reports back.

### Phase 6: ecosystem

14. More domain libraries.
15. Integration with a future incremental layer (if a clean redesign is pursued).
16. Production-readiness work.

---

## Non-goals

**Not a general-purpose language.** watjit is for systems kernels that LuaJIT can't handle well. Use Lua for everything else.

**Not a replacement for Terra in all cases.** If your workload requires AVX2, LLVM-grade optimization, or integration with a large C ecosystem, Terra may be the right tool.

**Not a framework.** Each layer is a library. Users compose layers as needed.

**Not a Wasm toolkit.** watjit uses Wasm as a compilation target, not as a feature surface. Tables, host imports, exceptions, and GC types are out of scope for now.

**Not coupled to any incremental layer.** watjit stands alone. Any future
memoized/runtime layer may build on watjit, but watjit itself must not know
about it.

---

## The thesis

> WebAssembly is now a production-quality portable low-level compilation target, and Wasmtime/Cranelift is an embeddable implementation with a stable C API. These facts make a Terra-grade systems programming environment possible without LLVM. watjit is that environment: five layers, roughly 2,000 lines of Lua for layers 0–3, each layer independently useful, each built on normal Lua mechanisms, each inspectable. The result is a small, coherent stack that makes Lua a viable language for systems code — numeric kernels, DSP, interpreters, codegen — while keeping the Lua development loop and avoiding the deployment cost of a large compiler dependency.

---

## File layout

```
watjit/
├── README.md                 — this document
│
├── lib/
│   ├── fragment.lua          — line buffer (~60 lines)
│   ├── wasmtime.lua          — FFI binding (~150 lines)
│   ├── watjit.lua            — main module, re-exports
│   ├── watjit_types.lua      — types, Val, operators
│   ├── watjit_scope.lua      — scope collection
│   ├── watjit_ctrl.lua       — for_, while_, if_, break_
│   ├── watjit_func.lua       — func, module, compile
│   ├── watjit_emit.lua       — tree → WAT text
│   │
│   ├── generics.lua          — layer 2 helpers (~100 lines)
│   ├── macros.lua            — layer 2 helpers (~100 lines)
│   │
│   ├── struct.lua            — layer 3 typed structs (~150 lines)
│   ├── array.lua             — layer 3 fixed arrays (~100 lines)
│   ├── arena.lua             — layer 3 bump allocator (~150 lines)
│   ├── slab.lua              — layer 3 slab allocator (~200 lines)
│   └── lru.lua               — layer 3 LRU cache (~150 lines)
│
├── domain/                    — layer 4 libraries
│   ├── dsp/ { fir, iir, fft }
│   ├── linalg/ { matmul, blas, ... }
│   └── parse/ { combinator }
│
├── test/                      — test suite
├── bench/                     — benchmarks vs Terra, vs C
└── examples/ { hello, matmul, filter, interpreter }
```

Estimated total for layers 0–3: ~2,000 lines of Lua. Layer 4 grows indefinitely.

---

## Status

Design complete. Implementation beginning with Phase 1.

A future incremental/memoized layer may eventually be rebuilt on top of
watjit, but that is separate work. The retired `iwatjit` design notes are
archived under `archive/iwatjit_retired/IWATJIT.md`.

---

*watjit is not trying to be everything. It is trying to be the right tool for a specific problem: making Lua a viable language for systems programming, without inventing a new language and without dragging in LLVM. If it succeeds at that, it will be small, useful, and composable with the rest of a Lua programmer's toolkit.*
