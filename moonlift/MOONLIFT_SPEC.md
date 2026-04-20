# Moonlift Language and Host Specification

Status: design + target spec for Moonlift's full source language, host API, metaprogramming model, and runtime surface.

This document is intentionally broader than the current builder DSL. It defines the intended Moonlift surface as a real Moonlift-native staged language embedded in Lua, not a Terra clone and not a thin Lua metatable trick.

Companion documents:

- `moonlift/MOONLIFT_NAMING.md` — naming rationale and canonical host/source spellings
- `moonlift/MOONLIFT_GRAMMAR.md` — parser-oriented grammar and precedence reference
- `moonlift/MOONLIFT_IMPLEMENTATION_PLAN.md` — staged implementation plan from the current builder/runtime to the full language

---

## 1. Design goals

Moonlift is a staged, typed, low-level language hosted by Lua.

Its goals are:

1. **Moonlift-native identity**
   - no `terra` keyword
   - no Terra compatibility surface as the primary frontend
   - Lua-hosted, Moonlift-branded syntax and semantics

2. **Language feel, not builder feel**
   - users should write Moonlift source, not nested `block(function() ...)`
   - the current builder DSL remains supported as the raw IR layer and macro substrate

3. **Typed low-level programming**
   - explicit scalar types
   - explicit aggregate layout
   - explicit ABI and memory operations
   - deterministic layout and code generation

4. **Strong metaprogramming**
   - quotes
   - splices
   - typed holes
   - IR rewrites / walking / querying
   - staged specialization driven by Lua

5. **Interop-first systems programming**
   - direct C ABI interop
   - explicit extern declarations
   - future `cimport`
   - stable layout rules

6. **Compiler-first architecture**
   - parsed source lowers to typed Moonlift IR
   - Moonlift IR is inspectable and transformable
   - code generation is a backend, not the language definition

---

## 2. Layers

Moonlift has three language layers.

### 2.1 Source layer
The user-facing language.

Entry points:

- `ml.code[[ ... ]]`
- `ml.module[[ ... ]]`
- `ml.expr[[ ... ]]`
- `ml.type[[ ... ]]`
- `ml.extern[[ ... ]]`
- `ml.cimport[[ ... ]]`

This is the primary authoring surface.

### 2.2 Quote / meta layer
Moonlift source or IR fragments treated as typed compile-time values.

Entry points:

- `ml.quote.func[[ ... ]]`
- `ml.quote.expr[[ ... ]]`
- `ml.quote.block[[ ... ]]`
- `ml.quote.type[[ ... ]]`
- `ml.quote.module[[ ... ]]`

Quote values support:

- `:splice(...)`
- `:bind{ ... }`
- `:rewrite{ ... }`
- `:walk(...)`
- `:query(...)`

### 2.3 IR / builder layer
The current Lua builder DSL.

Examples:

- `func`
- `block`
- `let`
- `var`
- `while_`
- `switch_`
- `cast`, `trunc`, `zext`, `sext`, `bitcast`
- `quote`, `quote_expr`, `quote_block`, `hole`

This layer remains supported as:

- compiler bootstrap surface
- low-level escape hatch
- macro implementation substrate
- programmatic IR construction API

It is **not** the long-term primary user surface.

---

## 3. Host integration model

Moonlift is hosted in Lua.

A typical host program looks like:

```lua
local ml = require("moonlift")
ml.use()

local add = ml.code[[
func add(a: i32, b: i32) -> i32
    return a + b
end
]]

local add_h = add()
print(add_h(20, 22)) -- 42
```

### 3.1 Host-side values
The host may manipulate:

- source fragments
- quote values
- type values
- compiled function handles
- module handles
- extern descriptors
- imported C declarations

### 3.2 Staging boundary
Lua is the compile-time host.
Moonlift is the compiled language.

Lua may:

- build Moonlift programs
- generate Moonlift code
- specialize Moonlift programs
- inspect / rewrite Moonlift IR
- call compiled Moonlift functions

Moonlift code does not execute Lua code at runtime except through explicit foreign calls.

---

## 4. Source entry points

### 4.1 `ml.code[[ ... ]]`
Parses exactly one top-level Moonlift item and returns the corresponding host-side object.

```lua
local add = ml.code[[
func add(a: i32, b: i32) -> i32
    return a + b
end
]]
```

If the parsed item is a function, the returned object is compilable and callable.

### 4.2 `ml.module[[ ... ]]`
Parses a complete Moonlift module.

```lua
local mathx = ml.module[[
struct Vec2
    x: f32
    y: f32
end

func dot(a: &Vec2, b: &Vec2) -> f32
    return a.x * b.x + a.y * b.y
end
]]
```

A module may contain multiple items and internal direct calls.

### 4.3 `ml.expr[[ ... ]]`
Parses one expression fragment and returns a typed expression quote or typed IR value.

### 4.4 `ml.type[[ ... ]]`
Parses one type fragment and returns a host-side type value.

### 4.5 `ml.extern[[ ... ]]`
Parses one or more extern declarations without requiring a full module.

### 4.6 `ml.cimport[[ ... ]]`
Imports C declarations. This is a host-side facility that produces Moonlift extern/type declarations.

---

## 5. Lexical rules

### 5.1 Whitespace
Whitespace separates tokens and is otherwise insignificant except inside strings and comments.

### 5.2 Comments
Single-line:

```text
-- comment
```

Block:

```text
--[[
comment
]]
```

### 5.3 Identifiers
Identifiers follow Lua-like rules:

- first character: `A-Z`, `a-z`, or `_`
- following characters: alphanumeric or `_`

Examples:

- `x`
- `sum4`
- `_tmp`
- `Vec2`

### 5.4 Keywords
Reserved words:

- `func`
- `extern`
- `struct`
- `union`
- `tagged`
- `enum`
- `slice`
- `opaque`
- `type`
- `impl`
- `const`
- `let`
- `var`
- `if`
- `then`
- `elseif`
- `else`
- `while`
- `do`
- `for`
- `in`
- `break`
- `continue`
- `return`
- `switch`
- `case`
- `default`
- `end`
- `true`
- `false`
- `nil`
- `pub`
- `as`
- `cast`
- `trunc`
- `zext`
- `sext`
- `bitcast`
- `sizeof`
- `alignof`
- `offsetof`
- `load`
- `store`
- `memcpy`
- `memmove`
- `memset`
- `memcmp`

### 5.5 Literals
Core literal kinds:

- integer literals: `0`, `42`, `0xff`
- float literals: `1.0`, `3.14`, `6.02e23`
- boolean literals: `true`, `false`
- nil literal: `nil`

No managed string type is part of core Moonlift. String literals are valid only in host/API/import contexts unless a future string ABI type is added.

### 5.6 Operators
Unary:

- `-`
- `not`
- `~`
- `&` (address-of)
- `*` (explicit dereference/load)

Binary:

- `+ - * / %`
- `== ~= < <= > >=`
- `and or`
- `& | ~`
- `<< >> >>>`

Indexing / field / call:

- `x.y`
- `x[y]`
- `f(...)`
- `x:method(...)`

---

## 6. Type system

Moonlift is statically typed.

### 6.1 Scalar built-ins
Built-in scalar types:

- `void`
- `bool`
- `i8`, `i16`, `i32`, `i64`
- `u8`, `u16`, `u32`, `u64`
- `isize`, `usize`
- `f32`, `f64`

Aliases:

- `byte` = `u8`

Type sizes:

- `bool` is 1 byte
- `i8/u8` 1 byte
- `i16/u16` 2 bytes
- `i32/u32/f32` 4 bytes
- `i64/u64/f64/isize/usize` 8 bytes on the current backend target

### 6.2 Named types
Named user types include:

- `struct`
- `union`
- `tagged union`
- `enum`
- `slice`
- `opaque`
- `type` aliases

### 6.3 Pointer types
Pointer syntax:

```text
&T
```

Examples:

- `&i32`
- `&Vec2`
- `&&u8`

`&T` is a raw ABI pointer type. It is not a borrow-checking or ownership type.

### 6.4 Array types
Fixed-size array syntax:

```text
[N]T
```

Examples:

- `[4]i32`
- `[16]u8`
- `[2]Vec2`

### 6.5 Slice types
Dynamic slice syntax:

```text
[]T
```

Examples:

- `[]i32`
- `[]byte`

A slice lowers to a layout-equivalent struct:

```text
struct slice<T>
    ptr: &T
    len: usize
end
```

### 6.6 Function types
Function pointer / function ABI syntax:

```text
func(T1, T2, ...) -> R
```

Examples:

- `func(i32, i32) -> i32`
- `func(&u8, usize) -> void`

For extern C declarations, ABI annotations may refine this.

### 6.7 Struct types
Syntax:

```text
struct Vec2
    x: f32
    y: f32
end
```

Field order is declaration order.

### 6.8 Union types
Syntax:

```text
union NumberBits
    i: i32
    u: u32
    f: f32
end
```

All fields overlap at offset 0.

### 6.9 Tagged union types
Syntax:

```text
tagged union Value : u8
    I32
        value: i32
    end

    Pair
        a: i16
        b: i16
    end
end
```

Meaning:

- an automatically generated tag enum with base type `u8`
- a payload union
- an outer struct containing `tag` and `payload`

Tag numbering is deterministic:

- explicit declaration order if written as ordered item blocks
- stable lexical key order if host tables are used to construct the equivalent declaration programmatically

### 6.10 Enum types
Syntax:

```text
enum Status : u8
    Idle = 0
    Busy = 1
    Done = 42
end
```

The base type is required unless a default is specified by the embedding.

### 6.11 Opaque types
Syntax:

```text
opaque FILE
```

Opaque types support pointers and ABI references but have no Moonlift-visible fields.

### 6.12 Type aliases
Syntax:

```text
type Index = u32
```

Aliases are nominal only at the source level and lower to the aliased type unless explicitly preserved for diagnostics.

---

## 7. Type attributes and layout attributes

Moonlift supports item attributes written with `@`.

Core attributes:

- `@align(N)`
- `@packed`
- `@abi("C")`
- `@export`
- `@link_name("symbol")`
- `@inline`
- `@noinline`
- `@cold`
- `@hot`

Examples:

```text
@align(16)
struct Vec4
    x: f32
    y: f32
    z: f32
    w: f32
end
```

```text
@abi("C")
extern func abs(x: i32) -> i32
```

---

## 8. Items and declarations

Module-level items:

- `const`
- `type`
- `struct`
- `union`
- `tagged union`
- `enum`
- `slice`
- `opaque`
- `func`
- `extern func`
- `impl`

### 8.1 Visibility
Items are private by default.

Public items use `pub`:

```text
pub func add(a: i32, b: i32) -> i32
    return a + b
end
```

### 8.2 Constants
Syntax:

```text
const Answer: i32 = 42
const Scale = 4
```

Module constants are compile-time values.

### 8.3 Functions
Syntax:

```text
func add(a: i32, b: i32) -> i32
    return a + b
end
```

Return type defaults to `void` if omitted.

Unnamed quote-level lambdas are allowed in quote contexts:

```text
func (x: i32) -> i32
    return x + 1
end
```

### 8.4 Extern functions
Syntax:

```text
extern func abs(x: i32) -> i32
extern func memcpy(dst: &u8, src: &u8, len: usize) -> void
```

Refinements:

```text
@abi("C")
@link_name("fabs")
extern func c_fabs(x: f64) -> f64
```

### 8.5 Impl blocks
Methods are declared in `impl` blocks.

```text
impl Pair
    func sum(self: &Pair) -> i32
        return self.a + self.b
    end

    func bump_sum(self: &Pair, delta: i32) -> i32
        self.a = self.a + delta
        return self.a + self.b
    end
end
```

Method-call syntax:

```text
p:sum()
p:bump_sum(2)
```

Method sugar form may also be supported:

```text
func Pair:sum() -> i32
    return self.a + self.b
end
```

Both lower to the same method item.

---

## 9. Expressions

Moonlift has expression-oriented blocks.

### 9.1 Name expressions

```text
x
acc
Vec2
Status.Done
```

### 9.2 Literal expressions

```text
42
0xff
3.14
true
false
nil
```

### 9.3 Aggregate literals
Struct literal:

```text
Vec2 { x = 3.0, y = 4.0 }
```

Array literal:

```text
[4]i32 { 10, 11, 12, 9 }
```

Union literal:

```text
NumberBits { i = 42 }
```

Tagged union literal:

```text
Value {
    tag = Value.Pair,
    payload = Value.Payload {
        Pair = { a = 20, b = 22 }
    }
}
```

Shorthand payload literal may be supported:

```text
Value.Pair { a = 20, b = 22 }
```

### 9.4 Field access

```text
v.x
pair.a
slice.len
```

If `p: &Struct`, `p.x` refers to the field reachable through the pointer.

### 9.5 Indexing

```text
arr[i]
p[i]
slice.ptr[i]
```

If `p: &T`, indexing refers to pointer arithmetic / memory indexing on `T`.

### 9.6 Calls

```text
f(x)
abs(x)
invoke(cb, x)
```

### 9.7 Method calls

```text
p:sum()
p:bump_sum(2)
```

### 9.8 Unary operations

```text
-x
not b
~x
&p
*p
```

Rules:

- `-` numeric negation
- `not` logical negation with canonical bool result `0/1`
- `~` bitwise not
- `&x` address-of lvalue
- `*p` explicit load / dereference

### 9.9 Binary operations
Arithmetic:

```text
x + y
x - y
x * y
x / y
x % y
```

Comparison:

```text
x == y
x ~= y
x < y
x <= y
x > y
x >= y
```

Logical:

```text
a and b
a or b
```

Bitwise:

```text
x & y
x | y
x ~ y
x << n
x >> n
x >>> n
```

Bool results are always canonicalized to `false/true` values represented as `0/1` at the IR level.

### 9.10 Cast family
Moonlift distinguishes cast kinds.

Syntax:

```text
cast<T>(x)
trunc<T>(x)
zext<T>(x)
sext<T>(x)
bitcast<T>(x)
```

Examples:

```text
cast<f64>(x)
zext<u32>(flag)
sext<i64>(x)
bitcast<u32>(f)
```

### 9.11 If expressions

```text
if cond then
    expr1
else
    expr2
end
```

A value-producing `if` expression requires all branches to produce a compatible type.

### 9.12 Block expressions

```text
do
    let x = 20
    let y = 22
    return x + y
end
```

A block expression yields the value of its `return`.

Rules:

- every value-producing block must return exactly one value type
- `break` and `continue` are not valid ways to exit a value-producing block
- a block that terminates via `break`/`continue` before producing a value is a compile-time error

### 9.13 Switch expressions
Scalar switch syntax:

```text
switch key do
case 0 then
    0
case 1 then
    1
default then
    42
end
```

Lowering must be deterministic regardless of source table construction order in host-generated code.

### 9.14 Introspection intrinsics

```text
sizeof(T)
alignof(T)
offsetof(T, field)
```

These are compile-time expressions of integer type.

---

## 10. Statements

### 10.1 Immutable local binding

```text
let x = 42
let y: i32 = 42
```

`let` binds an immutable local.

### 10.2 Mutable local binding

```text
var acc = 0
var i: i32 = 0
```

`var` binds a mutable local.

### 10.3 Assignment

```text
x = y
p.a = p.a + 1
arr[i] = 99
```

Assignability is limited to lvalues.

### 10.4 If statement

```text
if cond then
    ...
elseif other then
    ...
else
    ...
end
```

### 10.5 While loop

```text
while i < n do
    i = i + 1
end
```

### 10.6 Numeric for loop

```text
for i = 0, n - 1 do
    acc = acc + p[i]
end
```

Lowering of `for` is defined in terms of an explicit loop variable and a `while` loop.

### 10.7 Break / continue

```text
break
continue
```

Rules:

- valid only inside loops
- valid only in statement-position control flow
- not valid as the way a value-producing block obtains its value

### 10.8 Return

```text
return
return x
return x + y
```

### 10.9 Expression statement
A non-void expression may appear as a statement only if explicitly discarded or if it is a call used for side effects.

### 10.10 Memory statements
Intrinsic statements:

```text
memcpy(dst, src, len)
memmove(dst, src, len)
memset(dst, byte, len)
store<T>(dst, value)
```

`memcmp` is an expression returning `i32`.

---

## 11. Lvalues, rvalues, and projection semantics

This section defines the core semantics that make Moonlift feel consistent.

### 11.1 Lvalues
Assignable / addressable forms:

- mutable local variable
- field projection of an lvalue
- index projection of an lvalue
- pointer-dereferenced field/index projection
- explicit `*p` result when used as an lvalue of a load/store-capable type

### 11.2 Rvalues
Ordinary computed expressions are rvalues.

### 11.3 Pointer auto-projection
Moonlift intentionally supports pointer projection sugar:

If `p: &Vec2`, then:

```text
p.x
```

means the field at the pointed-to address, not a field on the pointer value itself.

If `p: &i32`, then:

```text
p[i]
```

means indexed memory relative to `p`.

### 11.4 Explicit load/store
Low-level forms remain available:

```text
load<T>(p)
store<T>(p, value)
```

`load<T>(p)` copies a value of type `T` out of memory.
`store<T>(p, value)` writes a value of type `T` into memory.

### 11.5 Aggregate assignment
Assigning a struct/array value copies the value.

```text
var p = Pair { a = 1, b = 2 }
p = Pair { a = 40, b = 2 }
```

Aggregate copies are value copies with deterministic layout semantics.

---

## 12. Integer and float semantics

### 12.1 Integer operations
Integer operations are width-aware and signedness-aware.

- division and remainder use signed or unsigned lowering based on operand type
- shifts use the requested shift kind
- comparisons use signed or unsigned lowering based on operand type

### 12.2 Bool semantics
`bool` is a distinct type.

Rules:

- logical results are canonicalized to `0/1`
- `not`, `and`, `or`, and comparisons must always yield canonical bools
- host-facing bool results must decode using canonical bool rules

### 12.3 Float semantics
`f32` and `f64` are IEEE-style backend float types as supported by the active backend.

### 12.4 Literal fallback
Unsuffixed integer literals are context-sensitive.

Fallback rules:

- if context constrains the type, the literal adopts that type
- otherwise integer literals default to `i32`
- float literals default to `f64`

---

## 13. Layout rules

Moonlift layout is explicit and deterministic.

### 13.1 Struct layout
For a struct:

- fields are placed in declaration order
- each field is aligned up to its natural or attributed alignment
- overall struct size is rounded up to the struct alignment
- struct alignment is the max field alignment unless overridden by attributes

### 13.2 Array layout
For `[N]T`:

- element stride = `sizeof(T)` rounded to `alignof(T)`
- total size = `N * stride`
- alignment = `alignof(T)`

### 13.3 Union layout
For a union:

- all members have offset `0`
- size = max field size rounded up to max alignment
- alignment = max field alignment

### 13.4 Tagged union layout
A tagged union lowers conceptually to:

```text
struct Outer
    tag: Tag
    payload: Payload
end
```

Where:

- `Tag` is an enum with deterministic variant values
- `Payload` is a union of variant payload layouts

### 13.5 Slice layout
A slice lowers to:

```text
struct Slice<T>
    ptr: &T
    len: usize
end
```

### 13.6 Enum layout
An enum has exactly the size and alignment of its base integer type.

---

## 14. Functions and calls

### 14.1 Compilation model
A Moonlift function object is a host-side descriptor until compiled.

Compilation may occur:

- explicitly via `f()` or `ml.compile(f)`
- transitively when referenced by other compiled Moonlift code
- at module compilation time

### 14.2 Direct calls
Calls between known Moonlift functions in the same compilation unit lower to **direct calls**, not function-pointer trampolines.

This is required for:

- recursion
- mutual recursion
- inlining
- good optimizer behavior
- Terra-level language feel

### 14.3 Indirect calls
Indirect calls are used for:

- function pointers
- unknown host-provided code addresses
- explicit callback values
- unresolved extern function values when required by the backend

### 14.4 Arity
The source language has no inherent small fixed arity limit.
If the host-call ABI currently has one, that is an implementation limit, not the language definition.

### 14.5 Return values
Current core Moonlift returns one scalar or one aggregate value.
Multi-result functions are a future extension and not part of the initial spec.

---

## 15. Modules

A module is a collection of items compiled together.

### 15.1 Internal references
Functions and types declared in a module may refer to each other according to normal declaration and forward-declaration rules.

### 15.2 Namespaces
A module namespace contains:

- items
- nested type members (`Enum.Member`, `TaggedUnion.Tag.Member`, etc.)
- impl methods attached to nominal types

### 15.3 Module compilation result
Compiling a module yields a host-side handle with:

- compiled exported functions by name
- accessible type descriptors where requested
- metadata / diagnostics / stats

---

## 16. Interop

Interop is first-class.

### 16.1 Manual extern declarations
Source form:

```text
extern func abs(x: i32) -> i32
```

Host form:

```lua
local c_abs = extern("abs") {
    i32"x",
    i32,
}
```

### 16.2 Imported symbol modules
Host API:

```lua
local libc = ml.import_module("libc", ffi.C)
```

Source-level equivalent may be represented by module import declarations.

### 16.3 C import
Target source API:

```lua
local C = ml.cimport[[
    int abs(int x);
    typedef struct { float x; float y; } Vec2;
]]
```

`cimport` produces Moonlift-visible:

- extern functions
- opaque / layout-compatible structs
- enums and constants when representable
- typedef aliases

### 16.4 ABI strings
Supported ABI names include at least:

- `"C"`
- `"moonlift"`

`"moonlift"` is the internal compiled-code calling convention.
`"C"` is the foreign interop ABI.

### 16.5 Layout compatibility
C-imported structs and enums must preserve C ABI layout.

### 16.6 Callbacks
Moonlift functions may be materialized as callable addresses when their ABI and capture model allow it.

---

## 17. Metaprogramming model

Metaprogramming is a core Moonlift feature.

### 17.1 Host splices
Inside Moonlift source parsed from strings, Lua-host values may be spliced with:

```text
@{lua_expr}
```

Examples:

```lua
local N = 4

local sum4 = ml.code[[
func sum4(p: &i32) -> i32
    var acc: i32 = 0
    for i = 0, @{N} - 1 do
        acc = acc + p[i]
    end
    return acc
end
]]
```

Splice categories are context-sensitive:

- expression splice
- type splice
- item splice
- identifier splice where explicitly allowed

### 17.2 Typed holes
Quote-time placeholders are written with `?name: Type`.

Example:

```lua
local q = ml.quote.expr[[
?a: i32 + ?b: i32
]]
```

Later:

```lua
local q2 = q:bind { a = ml.expr[[20]], b = ml.expr[[22]] }
```

### 17.3 Quotes
Quote forms:

- `ml.quote.expr[[ ... ]]`
- `ml.quote.block[[ ... ]]`
- `ml.quote.func[[ ... ]]`
- `ml.quote.type[[ ... ]]`
- `ml.quote.module[[ ... ]]`

Quotes preserve typed structure and source spans.

### 17.4 Splicing quoted values
A quote may be spliced into a larger quote or source form.

### 17.5 Hygiene
Local bindings created by splicing are hygienic by default:

- spliced locals do not accidentally capture surrounding locals
- quote-local names are renamed as needed on splice
- intentionally shared names require explicit mechanisms

### 17.6 Quote operations
Quotes support:

- `:splice(...)` — substitute positional quote parameters
- `:bind{...}` — fill named holes
- `:rewrite{ expr = f?, stmt = f?, item = f? }` — transform IR
- `:walk(visitor)` — visit nodes
- `:query(query_fn)` — collect derived information

### 17.7 Specialization
Compilation caches on canonical lowered form plus specialization inputs.

Specialization inputs may include:

- compile-time Lua splices
- bound quote holes
- backend settings
- ABI settings
- explicit specialization parameters

---

## 18. Source grammar

This grammar is intentionally high-level EBNF, not parser-generator-ready grammar.

### 18.1 Module

```text
module        ::= { item }
item          ::= visibility? attributes? item_core
visibility    ::= "pub"
attributes    ::= { attribute }
attribute     ::= "@" ident [ "(" attr_args ")" ]
```

### 18.2 Items

```text
item_core      ::= const_decl
                 | type_alias
                 | struct_decl
                 | union_decl
                 | tagged_union_decl
                 | enum_decl
                 | opaque_decl
                 | func_decl
                 | extern_func_decl
                 | impl_decl
```

### 18.3 Types

```text
type           ::= scalar_type
                 | named_type
                 | "&" type
                 | "[" expr "]" type
                 | "[]" type
                 | "func" "(" [ type_list ] ")" [ "->" type ]
```

### 18.4 Functions

```text
func_decl        ::= "func" ident "(" [ param_list ] ")" [ "->" type ] block_end
extern_func_decl ::= "extern" "func" ident "(" [ param_list ] ")" [ "->" type ]
param_list     ::= param { "," param }
param          ::= ident ":" type
```

### 18.5 Blocks and statements

```text
block_end      ::= newline { stmt } "end"
stmt           ::= let_stmt
                 | var_stmt
                 | assign_stmt
                 | if_stmt
                 | while_stmt
                 | for_stmt
                 | break_stmt
                 | continue_stmt
                 | return_stmt
                 | expr_stmt
```

### 18.6 Expressions

```text
expr           ::= if_expr
                 | switch_expr
                 | binary_expr
                 | unary_expr
                 | call_expr
                 | method_call_expr
                 | field_expr
                 | index_expr
                 | aggregate_literal
                 | name_expr
                 | literal
                 | block_expr
                 | intrinsic_expr
                 | splice_expr
                 | hole_expr
```

The actual parser defines precedence and associativity in the normal way.

---

## 19. Builder / IR API status

The current builder API remains part of Moonlift.

### 19.1 Supported host-level builder concepts
Current/fundamental builder concepts include:

- scalar types (`i32`, `f64`, etc.)
- `func`
- `module`
- `param`
- `let`, `var`
- `block`
- `if_`
- `while_`
- `switch_`
- `break_`, `continue_`
- `quote`, `quote_ir`, `quote_expr`, `quote_block`
- `hole`
- `rewrite`, `walk`, `query`
- structs, arrays, unions, tagged unions, enums, slices
- pointers and memory ops
- extern/import module interop

### 19.2 Role of the builder API
The builder API is normative for Moonlift IR construction and transformations, even after the parsed source frontend becomes primary.

### 19.3 Source lowering
Every parsed Moonlift source form lowers to the same typed IR model exposed by the builder and quote APIs.

---

## 20. Diagnostics

Moonlift diagnostics are compiler diagnostics, not generic Lua assertion failures.

Required diagnostic classes:

1. **Parse errors**
   - unexpected token
   - unterminated block
   - malformed type/item/expression

2. **Name resolution errors**
   - unknown identifier
   - duplicate declaration
   - unknown field / method / variant

3. **Type errors**
   - mismatched branch types
   - invalid assignment
   - invalid arithmetic or cast
   - wrong call arity
   - invalid pointer / aggregate operation

4. **Control-flow errors**
   - `break` outside loop
   - `continue` outside loop
   - value-producing block terminated without producing a value

5. **Layout / interop errors**
   - invalid packed alignment
   - unsupported extern type
   - incompatible C ABI item

Each diagnostic should include:

- primary span
- notes on related spans
- typed context where useful
- origin notes for quote/splice expansions

---

## 21. Tooling surface

Target tooling methods:

- `f:dump_source()`
- `f:dump_ir()`
- `f:dump_clif()`
- `f:dump_asm()`
- `f:addr()`
- `ml.stats()`
- `ml.report()`

Module tooling:

- `mod:dump_items()`
- `mod:dump_layouts()`
- `mod:dump_symbols()`

Quote tooling:

- `quote:dump()`
- `quote:dump_typed()`
- `quote:walk(...)`
- `quote:query(...)`

---

## 22. Semantic guarantees

Moonlift commits to the following guarantees.

### 22.1 Deterministic lowering
Equivalent source must lower deterministically.

Specifically:

- tagged union tag numbering is deterministic
- `switch` lowering order is deterministic
- quote rewrites are deterministic given the same inputs

### 22.2 Canonical bools
All bool-producing operations produce canonical `0/1` results.

### 22.3 Stable layout
Type layout is deterministic given:

- type declaration
- target pointer width / backend ABI
- explicit attributes

### 22.4 Direct internal calls
Known Moonlift-to-Moonlift calls compile as direct calls within a module or compilation unit.

### 22.5 Clear block-value rules
Value-producing blocks cannot silently terminate via `break` or `continue`.

---

## 23. Non-goals for the first complete language version

The following are intentionally not required in v1 unless explicitly added later:

- GC-managed reference types
- automatic ownership / borrow checking
- exceptions
- coroutines inside Moonlift code
- generic HM-style type inference
- implicit heap allocation
- operator overloading beyond defined built-ins
- hidden automatic boxing

Moonlift is a low-level staged systems language, not a managed runtime language.

---

## 24. Canonical examples

### 24.1 Basic function

```lua
local add = ml.code[[
func add(a: i32, b: i32) -> i32
    return a + b
end
]]
```

### 24.2 Loop

```lua
local triangular = ml.code[[
func triangular(n: i32) -> i32
    var i: i32 = 0
    var acc: i32 = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end
]]
```

### 24.3 Struct + method

```lua
local pair_mod = ml.module[[
struct Pair
    a: i32
    b: i32
end

impl Pair
    func sum(self: &Pair) -> i32
        return self.a + self.b
    end
end

func pair_sum(p: &Pair) -> i32
    return p:sum()
end
]]
```

### 24.4 Extern interop

```lua
local libc = ml.cimport[[
    int abs(int x);
]]

local use_abs = ml.code[[
func use_abs(x: i32) -> i32
    return abs(x)
end
]]
```

### 24.5 Quote + hole

```lua
local add_hole = ml.quote.expr[[
?lhs: i32 + ?rhs: i32
]]

local forty_two = add_hole:bind {
    lhs = ml.expr[[20]],
    rhs = ml.expr[[22]],
}
```

### 24.6 Host splice

```lua
local N = 4

local sum4 = ml.code[[
func sum4(p: &i32) -> i32
    var acc: i32 = 0
    for i = 0, @{N} - 1 do
        acc = acc + p[i]
    end
    return acc
end
]]
```

---

## 25. Relationship to the current implementation

This spec is larger than the currently implemented frontend.

Interpretation rules:

- where the current builder API already implements the behavior, the implementation should conform to this spec
- where the current system lacks a parsed source frontend, this spec defines the target frontend
- where implementation limits currently exist, they should be treated as implementation limits unless explicitly stated as language limits

The intended end state is:

1. Moonlift source is parsed from Moonlift-native syntax.
2. That source lowers to the same typed Moonlift IR used by the current builder/quote APIs.
3. Quotes and rewrites operate on that typed IR.
4. Modules compile with direct internal calls and deterministic lowering.
5. Interop and diagnostics are first-class.

---

## 26. Summary

Moonlift is defined by these principles:

- Moonlift-native syntax
- Lua-hosted staging
- typed low-level semantics
- deterministic layout and lowering
- direct compiled calls
- first-class interop
- first-class quotes and rewrites
- builder DSL retained as the raw IR layer, not the main language surface

That is the full-direction Moonlift language spec, not a limited slice.
