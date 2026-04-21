package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path
local pvm = require('pvm')

local defs = {
[[    Sign = Signed | Unsigned]],
[[    IntWidth = W8 | W16 | W32 | W64]],
[[    FloatWidth = F32 | F64]],
[[    Scalar = Void
           | Bool
           | Int(MLangSem.Sign sign, MLangSem.IntWidth width) unique
           | Float(MLangSem.FloatWidth width) unique
           | Ptr
           | Index]],
[[    CastOp = Cast | Trunc | ZExt | SExt | Bitcast | SatCast]],
[[    UnaryOp = Neg | Not | BNot]],
[[    BinaryOp = Add | Sub | Mul | Div | Rem
             | Eq | Ne | Lt | Le | Gt | Ge
             | And | Or
             | BitAnd | BitOr | BitXor
             | Shl | LShr | AShr
             | Min | Max]],
[[    Intrinsic = Popcount
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
              | Assume]],
[[    Type = ScalarType(MLangSem.Scalar scalar) unique
         | PtrTo(MLangSem.Type elem) unique
         | Array(MLangSem.Type elem, number count) unique
         | Slice(MLangSem.Type elem) unique
         | FuncType(MLangSem.Type* params, MLangSem.Type result) unique
         | NamedType(string module_name, string type_name) unique]],
[[    Param = (string name, MLangSem.Type ty) unique]],
[[    Binding = Local(string name, MLangSem.Type ty) unique
            | Arg(number index, string name, MLangSem.Type ty) unique]],
[[    Domain = Range(MLangSem.Expr stop) unique
           | Range2(MLangSem.Expr start, MLangSem.Expr stop) unique
           | BoundedValue(MLangSem.Expr value) unique
           | ZipEq(MLangSem.Expr* values) unique]],
[[    IndexBase = ViewBase(MLangSem.Expr base, MLangSem.Type elem, MLangSem.Expr limit) unique
              | PtrBase(MLangSem.Expr base, MLangSem.Type elem) unique]],
[[    CallTarget = Direct(string func_name, MLangSem.Type fn_ty) unique
               | Indirect(MLangSem.Expr callee, MLangSem.Type fn_ty) unique
               | Extern(string symbol, MLangSem.Type fn_ty) unique]],
[[    Expr = ConstInt(MLangSem.Scalar ty, string raw) unique
         | ConstFloat(MLangSem.Scalar ty, string raw) unique
         | ConstBool(boolean value) unique
         | Nil unique
         | Bind(MLangSem.Binding binding) unique
         | Unary(MLangSem.UnaryOp op, MLangSem.Type ty, MLangSem.Expr value) unique
         | Binary(MLangSem.BinaryOp op, MLangSem.Type ty, MLangSem.Expr lhs, MLangSem.Expr rhs) unique
         | Cast(MLangSem.CastOp op, MLangSem.Type ty, MLangSem.Expr value) unique
         | Select(MLangSem.Expr cond, MLangSem.Expr then_value, MLangSem.Expr else_value, MLangSem.Type ty) unique
         | IndexAddr(MLangSem.IndexBase base, MLangSem.Expr index, number elem_size) unique
         | FieldAddr(MLangSem.Expr base, string field_name, number offset, MLangSem.Type ty) unique
         | Load(MLangSem.Type ty, MLangSem.Expr addr) unique
         | IntrinsicCall(MLangSem.Intrinsic op, MLangSem.Type ty, MLangSem.Expr* args) unique
         | Call(MLangSem.CallTarget target, MLangSem.Type ty, MLangSem.Expr* args) unique
         | Agg(MLangSem.Type ty, MLangSem.FieldInit* fields) unique
         | ArrayLit(MLangSem.Type elem_ty, MLangSem.Expr* elems) unique
         | BlockExpr(MLangSem.Stmt* stmts, MLangSem.Expr result, MLangSem.Type ty) unique
         | IfExpr(MLangSem.Expr cond, MLangSem.Expr then_expr, MLangSem.Expr else_expr, MLangSem.Type ty) unique
         | SwitchExpr(MLangSem.Expr value, MLangSem.SwitchArm* arms, MLangSem.Expr default_expr, MLangSem.Type ty) unique]],
[[    FieldInit = (string name, MLangSem.Expr value) unique]],
[[    SwitchArm = (MLangSem.Expr key, MLangSem.Stmt* body) unique]],
[[    LoopBinding = (string name, MLangSem.Type ty, MLangSem.Expr init) unique]],
[[    LoopNext = (string name, MLangSem.Expr value) unique]],
[[    Loop = While(
        MLangSem.LoopBinding* vars,
        MLangSem.Expr cond,
        MLangSem.Stmt* body,
        MLangSem.LoopNext* next,
        MLangSem.Expr? result) unique
         | Over(
        string index_name,
        MLangSem.Type index_ty,
        MLangSem.Domain domain,
        MLangSem.LoopBinding* carries,
        MLangSem.Stmt* body,
        MLangSem.LoopNext* next,
        MLangSem.Expr? result) unique]],
[[    Stmt = Let(string name, MLangSem.Type ty, MLangSem.Expr init) unique
         | Var(string name, MLangSem.Type ty, MLangSem.Expr init) unique
         | Set(string name, MLangSem.Expr value) unique
         | Store(MLangSem.Type ty, MLangSem.Expr addr, MLangSem.Expr value) unique
         | ExprStmt(MLangSem.Expr expr) unique
         | IfStmt(MLangSem.Expr cond, MLangSem.Stmt* then_body, MLangSem.Stmt* else_body) unique
         | SwitchStmt(MLangSem.Expr value, MLangSem.SwitchArm* arms, MLangSem.Stmt* default_body) unique
         | Assert(MLangSem.Expr cond) unique
         | Return(MLangSem.Expr? value) unique
         | LoopStmt(MLangSem.Loop loop) unique]],
[[    Func = (string name, MLangSem.Param* params, MLangSem.Type result, MLangSem.Stmt* body) unique]],
[[    ExternFunc = (string name, string symbol, MLangSem.Param* params, MLangSem.Type result) unique]],
[[    Const = (string name, MLangSem.Type ty, MLangSem.Expr value) unique]],
[[    Item = FuncItem(MLangSem.Func func) unique
         | ExternItem(MLangSem.ExternFunc func) unique
         | ConstItem(MLangSem.Const c) unique]],
[[    Module = (MLangSem.Item* items) unique]],
}

local prefix = {}
for i, d in ipairs(defs) do
  prefix[#prefix+1] = d
  local schema = 'module MLangSem {\n' .. table.concat(prefix, '\n\n') .. '\n}'
  local ok, err = pcall(function()
    local T = pvm.context()
    T:Define(schema)
  end)
  print(i, ok)
  if not ok then
    print(err)
    break
  end
end
