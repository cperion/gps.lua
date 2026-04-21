# Moonlift ASDL Layers

Status: draft compiler architecture for moving Moonlift frontend lowering into Lua/ASDL/pvm and shrinking the Rust backend.

Principle:

> correct-first, not minimal-first

The point of these layers is **not** to minimize node count.
The point is to represent each real semantic question exactly once, so the compiler does not need to rediscover structure later.

---

## Intended stack

```text
Surface AST
  -> phase: elaborate + canonicalize
Sem IR
  -> phase: backend shaping
Back IR
  -> Rust: validate + emit Cranelift
```

This document focuses on the two new core IR layers:

- `MLang.Sem`  — canonical semantic IR
- `MLang.Back` — backend-oriented structured IR

These are the layers that should replace most of the current giant Rust lowering logic.

---

# 1. `MLang.Sem` — canonical semantic IR

This layer answers:

- what is the program in Moonlift’s intended kernel form?
- what are the canonical loops/domains/switches?
- what exact primitive operations does the backend need to see?
- what memory and indexing semantics are intended?

It should preserve distinctions that are both:
- semantically real
- backend-relevant

Examples:
- `LoopOver` vs `LoopWhile`
- `Switch` vs nested `If`
- `IndexAddr` vs generic pointer arithmetic
- `Intrinsic(popcount)` vs generic call
- `Fma` vs `Mul + Add`

## Draft ASDL schema

```asdl
module MLangSem {
    -- ---------- scalar / low-level primitive enums ----------

    Width = W8 | W16 | W32 | W64
    Signedness = Signed | Unsigned
    FloatWidth = F32 | F64

    ScalarType = Void
               | Bool
               | Int(MLangSem.Signedness sign, MLangSem.Width width)
               | Float(MLangSem.FloatWidth width)
               | Ptr
               | Index

    CastOp = Cast | Trunc | ZExt | SExt | Bitcast | SatCast

    UnaryOp = Neg | Not | BNot

    BinaryOp = Add | Sub | Mul | Div | Rem
             | Eq | Ne | Lt | Le | Gt | Ge
             | And | Or
             | BitAnd | BitOr | BitXor
             | Shl | LShr | AShr
             | Min | Max

    Intrinsic = Popcount
              | Clz
              | Ctz
              | Rotl
              | Rotr
              | Bswap
              | Fma
              | Sqrt
              | Abs
              | Floor
              | Ceil
              | TruncFloat
              | Round
              | Trap
              | Assume

    -- ---------- types ----------

    Type = Scalar(MLangSem.ScalarType scalar)
         | PtrTo(MLangSem.Type elem)
         | Array(MLangSem.Type elem, int count)
         | Slice(MLangSem.Type elem)
         | FuncType(MLangSem.Type* params, MLangSem.Type result)
         | NamedType(string module_name, string type_name)
         unique

    Param = (string name, MLangSem.Type ty) unique

    Binding = Local(string name, MLangSem.Type ty) unique
            | Arg(int index, string name, MLangSem.Type ty) unique

    -- ---------- memory / domains ----------

    Domain = Range(stop: MLangSem.Expr) unique
           | Range2(start: MLangSem.Expr, stop: MLangSem.Expr) unique
           | BoundedValue(value: MLangSem.Expr) unique
           | ZipEq(MLangSem.Expr* values) unique
           unique

    IndexBase = ViewBase(base: MLangSem.Expr, elem: MLangSem.Type, limit: MLangSem.Expr) unique
              | PtrBase(base: MLangSem.Expr, elem: MLangSem.Type) unique
              unique

    CallTarget = Direct(string func_name, MLangSem.Type fn_ty) unique
               | Indirect(MLangSem.Expr callee, MLangSem.Type fn_ty) unique
               | Extern(string symbol, MLangSem.Type fn_ty) unique
               unique

    -- ---------- expressions ----------

    Expr = ConstInt(MLangSem.ScalarType ty, string raw) unique
         | ConstFloat(MLangSem.ScalarType ty, string raw) unique
         | ConstBool(boolean value) unique
         | Nil unique
         | Bind(MLangSem.Binding binding) unique
         | Unary(MLangSem.UnaryOp op, MLangSem.Type ty, MLangSem.Expr value) unique
         | Binary(MLangSem.BinaryOp op, MLangSem.Type ty, MLangSem.Expr lhs, MLangSem.Expr rhs) unique
         | Cast(MLangSem.CastOp op, MLangSem.Type ty, MLangSem.Expr value) unique
         | Select(MLangSem.Expr cond, MLangSem.Expr then_value, MLangSem.Expr else_value, MLangSem.Type ty) unique
         | IndexAddr(MLangSem.IndexBase base, MLangSem.Expr index, int elem_size) unique
         | FieldAddr(MLangSem.Expr base, string field_name, int offset, MLangSem.Type ty) unique
         | Load(MLangSem.Type ty, MLangSem.Expr addr) unique
         | IntrinsicCall(MLangSem.Intrinsic op, MLangSem.Type ty, MLangSem.Expr* args) unique
         | Call(MLangSem.CallTarget target, MLangSem.Type ty, MLangSem.Expr* args) unique
         | Agg(MLangSem.Type ty, MLangSem.FieldInit* fields) unique
         | ArrayLit(MLangSem.Type elem_ty, MLangSem.Expr* elems) unique
         | BlockExpr(MLangSem.Stmt* stmts, MLangSem.Expr result, MLangSem.Type ty) unique
         | IfExpr(MLangSem.Expr cond, MLangSem.Expr then_expr, MLangSem.Expr else_expr, MLangSem.Type ty) unique
         | SwitchExpr(MLangSem.Expr value, MLangSem.SwitchArm* arms, MLangSem.Expr default_expr, MLangSem.Type ty) unique
         unique

    FieldInit = (string name, MLangSem.Expr value) unique

    -- ---------- statements ----------

    Stmt = Let(string name, MLangSem.Type ty, MLangSem.Expr init) unique
         | Var(string name, MLangSem.Type ty, MLangSem.Expr init) unique
         | Set(string name, MLangSem.Expr value) unique
         | Store(MLangSem.Type ty, MLangSem.Expr addr, MLangSem.Expr value) unique
         | ExprStmt(MLangSem.Expr expr) unique
         | IfStmt(MLangSem.Expr cond, MLangSem.Stmt* then_body, MLangSem.Stmt* else_body) unique
         | SwitchStmt(MLangSem.Expr value, MLangSem.SwitchArm* arms, MLangSem.Stmt* default_body) unique
         | Assert(MLangSem.Expr cond) unique
         | Return(MLangSem.Expr? value) unique
         | LoopStmt(MLangSem.Loop loop) unique
         unique

    SwitchArm = (MLangSem.Expr key, MLangSem.Stmt* body) unique

    -- ---------- canonical loops ----------

    LoopBinding = (string name, MLangSem.Type ty, MLangSem.Expr init) unique
    LoopNext = (string name, MLangSem.Expr value) unique

    Loop = LoopWhile(
                MLangSem.LoopBinding* vars,
                MLangSem.Expr cond,
                MLangSem.Stmt* body,
                MLangSem.LoopNext* next,
                MLangSem.Expr? result)
         | LoopOver(
                string index_name,
                MLangSem.Type index_ty,
                MLangSem.Domain domain,
                MLangSem.LoopBinding* carries,
                MLangSem.Stmt* body,
                MLangSem.LoopNext* next,
                MLangSem.Expr? result)
         unique

    -- ---------- items / modules ----------

    Func = (
        string name,
        MLangSem.Param* params,
        MLangSem.Type result,
        MLangSem.Stmt* body)
        unique

    ExternFunc = (
        string name,
        string symbol,
        MLangSem.Param* params,
        MLangSem.Type result)
        unique

    Const = (string name, MLangSem.Type ty, MLangSem.Expr value) unique

    Item = FuncItem(MLangSem.Func func)
         | ExternItem(MLangSem.ExternFunc func)
         | ConstItem(MLangSem.Const c)
         unique

    Module = (MLangSem.Item* items) unique
}
```

## Notes on `MLang.Sem`

### Why `LoopWhile` and `LoopOver` are separate
Because they answer different semantic questions:
- `LoopWhile`: carried-state recurrence with explicit guard
- `LoopOver`: bounded traversal with explicit domain facts

Do **not** collapse them too early.

### Why `Switch` is explicit
Cranelift wants structured switch shape.
This should not be rediscovered from nested `if` or `select`.

### Why `IntrinsicCall` is explicit
At least these should be explicit in Sem IR:
- `popcount`
- `clz`
- `ctz`
- `rotl`
- `rotr`
- `bswap`
- `fma`

Do not expect backend recovery.

### Why `IndexAddr` and `IndexBase` exist
Address shape is backend-relevant.
Preserve:
- base
- index
- element size
- limit when present

This is one of the strongest Cranelift findings.

---

# 2. `MLang.Back` — backend-oriented structured IR

This layer answers:

- what exact structured shape should Rust emit to Cranelift?
- what blocks, loop headers, latches, and exits exist?
- what explicit backend-friendly operations are present?

This is **not** raw CLIF.
But it should be close enough that Rust lowering is mostly structural.

## Draft ASDL schema

```asdl
module MLangBack {
    -- ---------- primitive enums ----------

    Width = W8 | W16 | W32 | W64
    Signedness = Signed | Unsigned
    FloatWidth = F32 | F64

    ScalarType = Void
               | Bool
               | Int(MLangBack.Signedness sign, MLangBack.Width width)
               | Float(MLangBack.FloatWidth width)
               | Ptr

    CastOp = Cast | Trunc | ZExt | SExt | Bitcast | SatCast

    UnaryOp = Neg | Not | BNot

    BinaryOp = Add | Sub | Mul | Div | Rem
             | Eq | Ne | Lt | Le | Gt | Ge
             | And | Or
             | BitAnd | BitOr | BitXor
             | Shl | LShr | AShr
             | Min | Max

    Intrinsic = Popcount
              | Clz
              | Ctz
              | Rotl
              | Rotr
              | Bswap
              | Fma
              | Sqrt
              | Abs
              | Floor
              | Ceil
              | TruncFloat
              | Round

    StepDir = Asc | Desc

    -- ---------- basic program entities ----------

    Param = (string name, MLangBack.ScalarType ty) unique
    Local = (string name, MLangBack.ScalarType ty) unique
    LoopVar = (string name, MLangBack.ScalarType ty, MLangBack.Expr init) unique

    CallTarget = Direct(string name) unique
               | Extern(string symbol) unique
               | Indirect(MLangBack.Expr callee) unique
               unique

    -- ---------- backend expressions ----------

    Expr = Const(MLangBack.ScalarType ty, string raw) unique
         | Arg(int index, MLangBack.ScalarType ty) unique
         | LocalRef(string name, MLangBack.ScalarType ty) unique
         | StackAddr(string name) unique
         | Unary(MLangBack.UnaryOp op, MLangBack.ScalarType ty, MLangBack.Expr value) unique
         | Binary(MLangBack.BinaryOp op, MLangBack.ScalarType ty, MLangBack.Expr lhs, MLangBack.Expr rhs) unique
         | Cast(MLangBack.CastOp op, MLangBack.ScalarType ty, MLangBack.Expr value) unique
         | Select(MLangBack.Expr cond, MLangBack.Expr then_value, MLangBack.Expr else_value, MLangBack.ScalarType ty) unique
         | IndexAddr(
                MLangBack.Expr base,
                MLangBack.Expr index,
                int elem_size,
                MLangBack.Expr? limit) unique
         | Load(MLangBack.ScalarType ty, MLangBack.Expr addr) unique
         | IntrinsicCall(MLangBack.Intrinsic op, MLangBack.ScalarType ty, MLangBack.Expr* args) unique
         | Call(MLangBack.CallTarget target, MLangBack.ScalarType ty, MLangBack.Expr* args) unique
         | Memcmp(MLangBack.Expr a, MLangBack.Expr b, MLangBack.Expr len) unique
         | BlockExpr(MLangBack.Stmt* stmts, MLangBack.Expr result, MLangBack.ScalarType ty) unique
         unique

    -- ---------- backend statements ----------

    SwitchArm = (MLangBack.Expr key, MLangBack.Stmt* body) unique

    Stmt = Let(string name, MLangBack.ScalarType ty, MLangBack.Expr init) unique
         | Var(string name, MLangBack.ScalarType ty, MLangBack.Expr init) unique
         | Set(string name, MLangBack.Expr value) unique
         | Store(MLangBack.ScalarType ty, MLangBack.Expr addr, MLangBack.Expr value) unique
         | BoundsCheck(MLangBack.Expr index, MLangBack.Expr limit) unique
         | Assert(MLangBack.Expr cond) unique
         | If(MLangBack.Expr cond, MLangBack.Stmt* then_body, MLangBack.Stmt* else_body) unique
         | Switch(MLangBack.Expr value, MLangBack.SwitchArm* arms, MLangBack.Stmt* default_body) unique
         | LoopWhile(
                MLangBack.LoopVar* vars,
                MLangBack.Expr cond,
                MLangBack.Stmt* body,
                MLangBack.Expr* next) unique
         | ForRange(
                string name,
                MLangBack.ScalarType ty,
                MLangBack.Expr start,
                MLangBack.Expr finish,
                MLangBack.Expr step,
                MLangBack.StepDir? dir,
                boolean inclusive,
                boolean scoped,
                MLangBack.Stmt* body) unique
         | StackSlot(string name, int size, int align) unique
         | Memcpy(MLangBack.Expr dst, MLangBack.Expr src, MLangBack.Expr len) unique
         | Memmove(MLangBack.Expr dst, MLangBack.Expr src, MLangBack.Expr len) unique
         | Memset(MLangBack.Expr dst, MLangBack.Expr byte, MLangBack.Expr len) unique
         | CallStmt(MLangBack.CallTarget target, MLangBack.Expr* args) unique
         | Break unique
         | Continue unique
         unique

    Func = (
        string name,
        MLangBack.Param* params,
        MLangBack.ScalarType result,
        MLangBack.Local* locals,
        MLangBack.Stmt* body,
        MLangBack.Expr result_expr)
        unique

    Module = (MLangBack.Func* funcs) unique
}
```

## Notes on `MLang.Back`

### Why `LoopWhile` and `ForRange` both exist
At backend level these are both useful:
- `LoopWhile` is the general block-param/header/latch form
- `ForRange` is the specialized counted traversal form that Cranelift likes

This lets the Lua frontend phase make the choice explicitly.

### Why `Switch` is still explicit
This should survive all the way to Rust so Cranelift gets a real structured switch.

### Why `IndexAddr` is explicit
This should survive all the way to Rust so Cranelift gets base/index/scale/offset shape.

### Why `IntrinsicCall` is explicit
These should lower almost directly to Cranelift ops where supported.

---

# 3. Phase boundary: `MLang.Sem -> MLang.Back`

This phase should be explicit and mostly structural.

## Main jobs

### Control
- `Sem.Switch*` -> `Back.Switch`
- `Sem.LoopWhile` -> `Back.LoopWhile`
- `Sem.LoopOver(range/zip/bounded)` -> domain prelude + `Back.ForRange`

### Memory/addressing
- preserve `IndexAddr`
- turn view/slice indexing into explicit `IndexAddr(base,index,elem_size,limit)`
- preserve explicit bounds facts instead of re-inferring them later

### Intrinsics
Map `Sem.IntrinsicCall` directly to `Back.IntrinsicCall` for:
- `popcount`
- `clz`
- `ctz`
- `rotl`
- `rotr`
- `bswap`
- `fma`
- etc.

### Types
- collapse `Sem.Type` into backend-legal scalar/pointer forms where needed
- keep enough distinction to preserve narrow induction and addressing shape

---

# 4. Rust boundary rule

Rust should accept **only `MLang.Back`** (or a trivially bridged form of it).

Rust should not be responsible for:
- rediscovering loop structure
- recovering switch from expression soup
- recognizing popcount/clz/ctz idioms
- reconstructing address shape from raw pointer arithmetic
- deciding whether something is a domain traversal

Rust should mostly:
- validate backend IR
- emit Cranelift
- handle ABI/layout/runtime details

That is the whole simplification win.

---

# 5. Immediate next step

The first implementation pass should probably target:

1. `MLang.Sem` loop/domain/switch/intrinsic nodes in Lua ASDL
2. one `pvm.phase` lowering `Sem.Module -> Back.Module`
3. a very small Rust loader/emitter for `Back.Module`

The initial high-value features to carry end-to-end are:
- canonical loops
- `range`
- `zip_eq`
- structured `switch`
- `IndexAddr`
- `popcount`
- `clz`
- `ctz`
- `rotl` / `rotr`
- `bswap`
- `fma`

These are exactly the places where the Cranelift explorations say “preserve intent directly”.
