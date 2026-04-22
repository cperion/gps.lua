local M = {}

M.SCHEMA = [[
module MoonliftSurface {
    SurfName = (string text) unique
    SurfPath = (MoonliftSurface.SurfName* parts) unique

    SurfIntrinsic = SurfPopcount
                  | SurfClz
                  | SurfCtz
                  | SurfRotl
                  | SurfRotr
                  | SurfBswap
                  | SurfFma
                  | SurfSqrt
                  | SurfAbs
                  | SurfFloor
                  | SurfCeil
                  | SurfTruncFloat
                  | SurfRound
                  | SurfTrap
                  | SurfAssume

    SurfTypeExpr = SurfTVoid
                 | SurfTBool
                 | SurfTI8 | SurfTI16 | SurfTI32 | SurfTI64
                 | SurfTU8 | SurfTU16 | SurfTU32 | SurfTU64
                 | SurfTF32 | SurfTF64
                 | SurfTIndex
                 | SurfTPtr(MoonliftSurface.SurfTypeExpr elem) unique
                 | SurfTArray(MoonliftSurface.SurfExpr count, MoonliftSurface.SurfTypeExpr elem) unique
                 | SurfTSlice(MoonliftSurface.SurfTypeExpr elem) unique
                 | SurfTView(MoonliftSurface.SurfTypeExpr elem) unique
                 | SurfTFunc(MoonliftSurface.SurfTypeExpr* params, MoonliftSurface.SurfTypeExpr result) unique
                 | SurfTNamed(MoonliftSurface.SurfPath path) unique

    SurfParam = (string name, MoonliftSurface.SurfTypeExpr ty) unique
    SurfFieldDecl = (string field_name, MoonliftSurface.SurfTypeExpr ty) unique
    SurfFieldInit = (string name, MoonliftSurface.SurfExpr value) unique
    SurfSwitchStmtArm = (MoonliftSurface.SurfExpr key, MoonliftSurface.SurfStmt* body) unique
    SurfSwitchExprArm = (MoonliftSurface.SurfExpr key, MoonliftSurface.SurfStmt* body, MoonliftSurface.SurfExpr result) unique
    SurfLoopCarryInit = (string name, MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr init) unique
    SurfLoopNextAssign = (string name, MoonliftSurface.SurfExpr value) unique

    SurfPlace = SurfPlaceName(string name) unique
              | SurfPlacePath(MoonliftSurface.SurfPath path) unique
              | SurfPlaceDeref(MoonliftSurface.SurfExpr base) unique
              | SurfPlaceDot(MoonliftSurface.SurfPlace base, string name) unique
              | SurfPlaceField(MoonliftSurface.SurfPlace base, string name) unique
              | SurfPlaceIndex(MoonliftSurface.SurfExpr base, MoonliftSurface.SurfExpr index) unique

    SurfDomainExpr = SurfDomainRange(MoonliftSurface.SurfExpr stop) unique
                   | SurfDomainRange2(MoonliftSurface.SurfExpr start, MoonliftSurface.SurfExpr stop) unique
                   | SurfDomainZipEq(MoonliftSurface.SurfExpr* values) unique
                   | SurfDomainValue(MoonliftSurface.SurfExpr value) unique

    SurfLoopStmt = SurfLoopWhileStmt(MoonliftSurface.SurfLoopCarryInit* carries, MoonliftSurface.SurfExpr cond, MoonliftSurface.SurfStmt* body, MoonliftSurface.SurfLoopNextAssign* next) unique
                 | SurfLoopOverStmt(string index_name, MoonliftSurface.SurfDomainExpr domain, MoonliftSurface.SurfLoopCarryInit* carries, MoonliftSurface.SurfStmt* body, MoonliftSurface.SurfLoopNextAssign* next) unique

    SurfLoopExpr = SurfLoopWhileExpr(MoonliftSurface.SurfLoopCarryInit* carries, MoonliftSurface.SurfExpr cond, MoonliftSurface.SurfStmt* body, MoonliftSurface.SurfLoopNextAssign* next, MoonliftSurface.SurfExpr result) unique
                 | SurfLoopOverExpr(string index_name, MoonliftSurface.SurfDomainExpr domain, MoonliftSurface.SurfLoopCarryInit* carries, MoonliftSurface.SurfStmt* body, MoonliftSurface.SurfLoopNextAssign* next, MoonliftSurface.SurfExpr result) unique

    SurfExpr = SurfInt(string raw) unique
             | SurfFloat(string raw) unique
             | SurfBool(boolean value) unique
             | SurfNil
             | SurfNameRef(string name) unique
             | SurfPathRef(MoonliftSurface.SurfPath path) unique
             | SurfExprDot(MoonliftSurface.SurfExpr base, string name) unique
             | SurfExprNeg(MoonliftSurface.SurfExpr value) unique
             | SurfExprNot(MoonliftSurface.SurfExpr value) unique
             | SurfExprBNot(MoonliftSurface.SurfExpr value) unique
             | SurfExprRef(MoonliftSurface.SurfPlace place) unique
             | SurfExprDeref(MoonliftSurface.SurfExpr value) unique
             | SurfExprAdd(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprSub(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprMul(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprDiv(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprRem(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprEq(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprNe(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprLt(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprLe(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprGt(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprGe(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprAnd(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprOr(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprBitAnd(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprBitOr(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprBitXor(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprShl(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprLShr(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprAShr(MoonliftSurface.SurfExpr lhs, MoonliftSurface.SurfExpr rhs) unique
             | SurfExprCastTo(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
             | SurfExprTruncTo(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
             | SurfExprZExtTo(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
             | SurfExprSExtTo(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
             | SurfExprBitcastTo(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
             | SurfExprSatCastTo(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
             | SurfExprIntrinsicCall(MoonliftSurface.SurfIntrinsic op, MoonliftSurface.SurfExpr* args) unique
             | SurfCall(MoonliftSurface.SurfExpr callee, MoonliftSurface.SurfExpr* args) unique
             | SurfField(MoonliftSurface.SurfExpr base, string name) unique
             | SurfIndex(MoonliftSurface.SurfExpr base, MoonliftSurface.SurfExpr index) unique
             | SurfAgg(MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfFieldInit* fields) unique
             | SurfArrayLit(MoonliftSurface.SurfTypeExpr elem_ty, MoonliftSurface.SurfExpr* elems) unique
             | SurfIfExpr(MoonliftSurface.SurfExpr cond, MoonliftSurface.SurfExpr then_expr, MoonliftSurface.SurfExpr else_expr) unique
             | SurfSelectExpr(MoonliftSurface.SurfExpr cond, MoonliftSurface.SurfExpr then_expr, MoonliftSurface.SurfExpr else_expr) unique
             | SurfSwitchExpr(MoonliftSurface.SurfExpr value, MoonliftSurface.SurfSwitchExprArm* arms, MoonliftSurface.SurfExpr default_expr) unique
             | SurfLoopExprNode(MoonliftSurface.SurfLoopExpr loop) unique
             | SurfBlockExpr(MoonliftSurface.SurfStmt* stmts, MoonliftSurface.SurfExpr result) unique

    SurfStmt = SurfLet(string name, MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr init) unique
             | SurfVar(string name, MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr init) unique
             | SurfSet(MoonliftSurface.SurfPlace place, MoonliftSurface.SurfExpr value) unique
             | SurfExprStmt(MoonliftSurface.SurfExpr expr) unique
             | SurfIf(MoonliftSurface.SurfExpr cond, MoonliftSurface.SurfStmt* then_body, MoonliftSurface.SurfStmt* else_body) unique
             | SurfSwitch(MoonliftSurface.SurfExpr value, MoonliftSurface.SurfSwitchStmtArm* arms, MoonliftSurface.SurfStmt* default_body) unique
             | SurfReturnVoid
             | SurfReturnValue(MoonliftSurface.SurfExpr value) unique
             | SurfBreak
             | SurfBreakValue(MoonliftSurface.SurfExpr value) unique
             | SurfContinue
             | SurfLoopStmtNode(MoonliftSurface.SurfLoopStmt loop) unique

    SurfFunc = (string name, MoonliftSurface.SurfParam* params, MoonliftSurface.SurfTypeExpr result, MoonliftSurface.SurfStmt* body) unique
    SurfExternFunc = (string name, string symbol, MoonliftSurface.SurfParam* params, MoonliftSurface.SurfTypeExpr result) unique
    SurfConst = (string name, MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
    SurfStatic = (string name, MoonliftSurface.SurfTypeExpr ty, MoonliftSurface.SurfExpr value) unique
    SurfImport = (MoonliftSurface.SurfPath path) unique
    SurfTypeDecl = SurfStruct(string name, MoonliftSurface.SurfFieldDecl* fields) unique

    SurfItem = SurfItemFunc(MoonliftSurface.SurfFunc func) unique
             | SurfItemExtern(MoonliftSurface.SurfExternFunc func) unique
             | SurfItemConst(MoonliftSurface.SurfConst c) unique
             | SurfItemStatic(MoonliftSurface.SurfStatic s) unique
             | SurfItemImport(MoonliftSurface.SurfImport imp) unique
             | SurfItemType(MoonliftSurface.SurfTypeDecl t) unique

    SurfModule = (MoonliftSurface.SurfItem* items) unique
}

module MoonliftElab {
    ElabIntrinsic = ElabPopcount
                  | ElabClz
                  | ElabCtz
                  | ElabRotl
                  | ElabRotr
                  | ElabBswap
                  | ElabFma
                  | ElabSqrt
                  | ElabAbs
                  | ElabFloor
                  | ElabCeil
                  | ElabTruncFloat
                  | ElabRound
                  | ElabTrap
                  | ElabAssume

    ElabType = ElabTVoid
             | ElabTBool
             | ElabTI8 | ElabTI16 | ElabTI32 | ElabTI64
             | ElabTU8 | ElabTU16 | ElabTU32 | ElabTU64
             | ElabTF32 | ElabTF64
             | ElabTIndex
             | ElabTPtr(MoonliftElab.ElabType elem) unique
             | ElabTArray(MoonliftElab.ElabExpr count, MoonliftElab.ElabType elem) unique
             | ElabTSlice(MoonliftElab.ElabType elem) unique
             | ElabTView(MoonliftElab.ElabType elem) unique
             | ElabTFunc(MoonliftElab.ElabType* params, MoonliftElab.ElabType result) unique
             | ElabTNamed(string module_name, string type_name) unique

    ElabBinding = ElabLocalValue(string id, string name, MoonliftElab.ElabType ty) unique
                | ElabLocalCell(string id, string name, MoonliftElab.ElabType ty) unique
                | ElabArg(number index, string name, MoonliftElab.ElabType ty) unique
                | ElabLoopCarry(string loop_id, string port_id, string name, MoonliftElab.ElabType ty) unique
                | ElabLoopIndex(string loop_id, string name, MoonliftElab.ElabType ty) unique
                | ElabGlobalFunc(string module_name, string item_name, MoonliftElab.ElabType ty) unique
                | ElabGlobalConst(string module_name, string item_name, MoonliftElab.ElabType ty) unique
                | ElabGlobalStatic(string module_name, string item_name, MoonliftElab.ElabType ty) unique
                | ElabExtern(string symbol, MoonliftElab.ElabType ty) unique

    ElabValueEntry = (string name, MoonliftElab.ElabBinding binding) unique
    ElabTypeEntry = (string name, MoonliftElab.ElabType ty) unique
    ElabFieldType = (string field_name, MoonliftElab.ElabType ty) unique
    ElabTypeLayout = ElabLayoutNamed(string module_name, string type_name, MoonliftElab.ElabFieldType* fields) unique
    ElabEnv = (string module_name, MoonliftElab.ElabValueEntry* values, MoonliftElab.ElabTypeEntry* types, MoonliftElab.ElabTypeLayout* layouts) unique
    ElabConstEntry = (string module_name, string item_name, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
    ElabConstEnv = (MoonliftElab.ElabConstEntry* entries) unique
    ElabStmtEnvEffect = ElabNoBinding
                      | ElabAddBinding(MoonliftElab.ElabValueEntry entry) unique

    ElabParam = (string name, MoonliftElab.ElabType ty) unique
    ElabFieldInit = (string name, MoonliftElab.ElabExpr value) unique
    ElabSwitchStmtArm = (MoonliftElab.ElabExpr key, MoonliftElab.ElabStmt* body) unique
    ElabSwitchExprArm = (MoonliftElab.ElabExpr key, MoonliftElab.ElabStmt* body, MoonliftElab.ElabExpr result) unique
    ElabLoopCarryPort = (string port_id, string name, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr init) unique
    ElabLoopIndexPort = (string name, MoonliftElab.ElabType ty) unique
    ElabLoopUpdate = (string port_id, MoonliftElab.ElabExpr value) unique

    ElabPlace = ElabPlaceBinding(MoonliftElab.ElabBinding binding) unique
              | ElabPlaceDeref(MoonliftElab.ElabExpr base, MoonliftElab.ElabType elem) unique
              | ElabPlaceField(MoonliftElab.ElabPlace base, string name, MoonliftElab.ElabType ty) unique
              | ElabPlaceIndex(MoonliftElab.ElabIndexBase base, MoonliftElab.ElabExpr index, MoonliftElab.ElabType ty) unique

    ElabIndexBase = ElabIndexBasePlace(MoonliftElab.ElabPlace base, MoonliftElab.ElabType elem) unique
                  | ElabIndexBaseView(MoonliftElab.ElabExpr base, MoonliftElab.ElabType elem) unique

    ElabDomain = ElabDomainRange(MoonliftElab.ElabExpr stop) unique
               | ElabDomainRange2(MoonliftElab.ElabExpr start, MoonliftElab.ElabExpr stop) unique
               | ElabDomainZipEq(MoonliftElab.ElabExpr* values) unique
               | ElabDomainValue(MoonliftElab.ElabExpr value) unique

    ElabLoop = ElabLoopWhileStmt(string loop_id, MoonliftElab.ElabLoopCarryPort* carries, MoonliftElab.ElabExpr cond, MoonliftElab.ElabStmt* body, MoonliftElab.ElabLoopUpdate* next) unique
             | ElabLoopOverStmt(string loop_id, MoonliftElab.ElabLoopIndexPort index_port, MoonliftElab.ElabDomain domain, MoonliftElab.ElabLoopCarryPort* carries, MoonliftElab.ElabStmt* body, MoonliftElab.ElabLoopUpdate* next) unique
             | ElabLoopWhileExpr(string loop_id, MoonliftElab.ElabLoopCarryPort* carries, MoonliftElab.ElabExpr cond, MoonliftElab.ElabStmt* body, MoonliftElab.ElabLoopUpdate* next, MoonliftElab.ElabExpr result) unique
             | ElabLoopOverExpr(string loop_id, MoonliftElab.ElabLoopIndexPort index_port, MoonliftElab.ElabDomain domain, MoonliftElab.ElabLoopCarryPort* carries, MoonliftElab.ElabStmt* body, MoonliftElab.ElabLoopUpdate* next, MoonliftElab.ElabExpr result) unique

    ElabExpr = ElabInt(string raw, MoonliftElab.ElabType ty) unique
             | ElabFloat(string raw, MoonliftElab.ElabType ty) unique
             | ElabBool(boolean value, MoonliftElab.ElabType ty) unique
             | ElabNil(MoonliftElab.ElabType ty) unique
             | ElabBindingExpr(MoonliftElab.ElabBinding binding) unique
             | ElabExprNeg(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprNot(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprBNot(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprAddrOf(MoonliftElab.ElabPlace place, MoonliftElab.ElabType ty) unique
             | ElabExprDeref(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprAdd(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprSub(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprMul(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprDiv(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprRem(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprEq(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprNe(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprLt(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprLe(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprGt(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprGe(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprAnd(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprOr(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprBitAnd(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprBitOr(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprBitXor(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprShl(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprLShr(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprAShr(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr lhs, MoonliftElab.ElabExpr rhs) unique
             | ElabExprCastTo(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprTruncTo(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprZExtTo(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprSExtTo(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprBitcastTo(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprSatCastTo(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
             | ElabExprIntrinsicCall(MoonliftElab.ElabIntrinsic op, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr* args) unique
             | ElabCall(MoonliftElab.ElabExpr callee, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr* args) unique
             | ElabField(MoonliftElab.ElabExpr base, string name, MoonliftElab.ElabType ty) unique
             | ElabIndex(MoonliftElab.ElabIndexBase base, MoonliftElab.ElabExpr index, MoonliftElab.ElabType ty) unique
             | ElabAgg(MoonliftElab.ElabType ty, MoonliftElab.ElabFieldInit* fields) unique
             | ElabArrayLit(MoonliftElab.ElabType ty, MoonliftElab.ElabExpr* elems) unique
             | ElabIfExpr(MoonliftElab.ElabExpr cond, MoonliftElab.ElabExpr then_expr, MoonliftElab.ElabExpr else_expr, MoonliftElab.ElabType ty) unique
             | ElabSelectExpr(MoonliftElab.ElabExpr cond, MoonliftElab.ElabExpr then_expr, MoonliftElab.ElabExpr else_expr, MoonliftElab.ElabType ty) unique
             | ElabSwitchExpr(MoonliftElab.ElabExpr value, MoonliftElab.ElabSwitchExprArm* arms, MoonliftElab.ElabExpr default_expr, MoonliftElab.ElabType ty) unique
             | ElabLoopExprNode(MoonliftElab.ElabLoop loop, MoonliftElab.ElabType ty) unique
             | ElabBlockExpr(MoonliftElab.ElabStmt* stmts, MoonliftElab.ElabExpr result, MoonliftElab.ElabType ty) unique

    ElabStmt = ElabLet(string id, string name, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr init) unique
             | ElabVar(string id, string name, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr init) unique
             | ElabSet(MoonliftElab.ElabPlace place, MoonliftElab.ElabExpr value) unique
             | ElabExprStmt(MoonliftElab.ElabExpr expr) unique
             | ElabIf(MoonliftElab.ElabExpr cond, MoonliftElab.ElabStmt* then_body, MoonliftElab.ElabStmt* else_body) unique
             | ElabSwitch(MoonliftElab.ElabExpr value, MoonliftElab.ElabSwitchStmtArm* arms, MoonliftElab.ElabStmt* default_body) unique
             | ElabReturnVoid
             | ElabReturnValue(MoonliftElab.ElabExpr value) unique
             | ElabBreak
             | ElabBreakValue(MoonliftElab.ElabExpr value) unique
             | ElabContinue
             | ElabLoopStmtNode(MoonliftElab.ElabLoop loop) unique

    ElabFunc = (string name, MoonliftElab.ElabParam* params, MoonliftElab.ElabType result, MoonliftElab.ElabStmt* body) unique
    ElabExternFunc = (string name, string symbol, MoonliftElab.ElabParam* params, MoonliftElab.ElabType result) unique
    ElabConst = (string name, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
    ElabStatic = (string name, MoonliftElab.ElabType ty, MoonliftElab.ElabExpr value) unique
    ElabImport = (string module_name) unique
    ElabTypeDecl = ElabStruct(string name, MoonliftElab.ElabFieldType* fields) unique

    ElabItem = ElabItemFunc(MoonliftElab.ElabFunc func) unique
             | ElabItemExtern(MoonliftElab.ElabExternFunc func) unique
             | ElabItemConst(MoonliftElab.ElabConst c) unique
             | ElabItemStatic(MoonliftElab.ElabStatic s) unique
             | ElabItemImport(MoonliftElab.ElabImport imp) unique
             | ElabItemType(MoonliftElab.ElabTypeDecl t) unique

    ElabModule = (string module_name, MoonliftElab.ElabItem* items) unique
}

module MoonliftSem {
    SemType = SemTVoid
            | SemTBool
            | SemTI8 | SemTI16 | SemTI32 | SemTI64
            | SemTU8 | SemTU16 | SemTU32 | SemTU64
            | SemTF32 | SemTF64
            | SemTPtr
            | SemTIndex
            | SemTPtrTo(MoonliftSem.SemType elem) unique
            | SemTArray(MoonliftSem.SemType elem, number count) unique
            | SemTSlice(MoonliftSem.SemType elem) unique
            | SemTView(MoonliftSem.SemType elem) unique
            | SemTFunc(MoonliftSem.SemType* params, MoonliftSem.SemType result) unique
            | SemTNamed(string module_name, string type_name) unique

    SemIntrinsic = SemPopcount
                 | SemClz
                 | SemCtz
                 | SemRotl
                 | SemRotr
                 | SemBswap
                 | SemFma
                 | SemSqrt
                 | SemAbs
                 | SemFloor
                 | SemCeil
                 | SemTruncFloat
                 | SemRound
                 | SemTrap
                 | SemAssume

    SemParam = (string name, MoonliftSem.SemType ty) unique
    SemBinding = SemBindLocalValue(string id, string name, MoonliftSem.SemType ty) unique
               | SemBindLocalCell(string id, string name, MoonliftSem.SemType ty) unique
               | SemBindArg(number index, string name, MoonliftSem.SemType ty) unique
               | SemBindLoopCarry(string loop_id, string port_id, string name, MoonliftSem.SemType ty) unique
               | SemBindLoopIndex(string loop_id, string name, MoonliftSem.SemType ty) unique
               | SemBindGlobalFunc(string module_name, string item_name, MoonliftSem.SemType ty) unique
               | SemBindGlobalConst(string module_name, string item_name, MoonliftSem.SemType ty) unique
               | SemBindGlobalStatic(string module_name, string item_name, MoonliftSem.SemType ty) unique
               | SemBindExtern(string symbol, MoonliftSem.SemType ty) unique

    SemResidence = SemResidenceValue | SemResidenceStack
    SemResidenceEntry = (MoonliftSem.SemBinding binding, MoonliftSem.SemResidence residence) unique
    SemResidencePlan = (MoonliftSem.SemResidenceEntry* entries) unique

    SemView = SemViewValue(MoonliftSem.SemExpr base, MoonliftSem.SemType elem) unique
            | SemViewContiguous(MoonliftSem.SemExpr data, MoonliftSem.SemType elem, MoonliftSem.SemExpr len) unique
            | SemViewStrided(MoonliftSem.SemExpr data, MoonliftSem.SemType elem, MoonliftSem.SemExpr len, MoonliftSem.SemExpr stride) unique
            | SemViewWindow(MoonliftSem.SemView base, MoonliftSem.SemExpr start, MoonliftSem.SemExpr len) unique
            | SemViewInterleaved(MoonliftSem.SemExpr data, MoonliftSem.SemType elem, MoonliftSem.SemExpr len, MoonliftSem.SemExpr stride, MoonliftSem.SemExpr lane) unique

    SemDomain = SemDomainRange(MoonliftSem.SemExpr stop) unique
              | SemDomainRange2(MoonliftSem.SemExpr start, MoonliftSem.SemExpr stop) unique
              | SemDomainView(MoonliftSem.SemView view) unique
              | SemDomainZipEq(MoonliftSem.SemView* views) unique

    SemIndexBase = SemIndexBasePlace(MoonliftSem.SemPlace base, MoonliftSem.SemType elem) unique
                 | SemIndexBaseView(MoonliftSem.SemView view) unique

    SemCallTarget = SemCallDirect(string module_name, string func_name, MoonliftSem.SemType fn_ty) unique
                  | SemCallIndirect(MoonliftSem.SemExpr callee, MoonliftSem.SemType fn_ty) unique
                  | SemCallExtern(string symbol, MoonliftSem.SemType fn_ty) unique

    SemFieldRef = SemFieldByName(string field_name, MoonliftSem.SemType ty) unique
                | SemFieldByOffset(string field_name, number offset, MoonliftSem.SemType ty) unique

    SemFieldType = (string field_name, MoonliftSem.SemType ty) unique
    SemFieldLayout = (string field_name, number offset, MoonliftSem.SemType ty) unique
    SemTypeLayout = SemLayoutNamed(string module_name, string type_name, MoonliftSem.SemFieldLayout* fields, number size, number align) unique
    SemLayoutEnv = (MoonliftSem.SemTypeLayout* layouts) unique
    SemConstFieldValue = (string name, MoonliftSem.SemConstValue value) unique
    SemConstValue = SemConstInt(MoonliftSem.SemType ty, string raw) unique
                  | SemConstFloat(MoonliftSem.SemType ty, string raw) unique
                  | SemConstBool(boolean value) unique
                  | SemConstNil(MoonliftSem.SemType ty) unique
                  | SemConstAgg(MoonliftSem.SemType ty, MoonliftSem.SemConstFieldValue* fields) unique
                  | SemConstArray(MoonliftSem.SemType elem_ty, MoonliftSem.SemConstValue* elems) unique
    SemConstEntry = (string module_name, string item_name, MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
    SemConstEnv = (MoonliftSem.SemConstEntry* entries) unique
    SemConstLocalEntry = (MoonliftSem.SemBinding binding, MoonliftSem.SemConstValue value) unique
    SemConstLocalEnv = (MoonliftSem.SemConstLocalEntry* entries) unique
    SemConstStmtResult = SemConstStmtFallsThrough(MoonliftSem.SemConstLocalEnv local_env) unique
                       | SemConstStmtReturnVoid(MoonliftSem.SemConstLocalEnv local_env) unique
                       | SemConstStmtReturnValue(MoonliftSem.SemConstLocalEnv local_env, MoonliftSem.SemConstValue value) unique
                       | SemConstStmtBreak(MoonliftSem.SemConstLocalEnv local_env) unique
                       | SemConstStmtBreakValue(MoonliftSem.SemConstLocalEnv local_env, MoonliftSem.SemConstValue value) unique
                       | SemConstStmtContinue(MoonliftSem.SemConstLocalEnv local_env) unique

    SemFieldInit = (string name, MoonliftSem.SemExpr value) unique
    SemSwitchStmtArm = (MoonliftSem.SemExpr key, MoonliftSem.SemStmt* body) unique
    SemSwitchExprArm = (MoonliftSem.SemExpr key, MoonliftSem.SemStmt* body, MoonliftSem.SemExpr result) unique
    SemLoopCarryPort = (string port_id, string name, MoonliftSem.SemType ty, MoonliftSem.SemExpr init) unique
    SemLoopIndexPort = (string name, MoonliftSem.SemType ty) unique
    SemLoopUpdate = (string port_id, MoonliftSem.SemExpr value) unique

    SemPlace = SemPlaceBinding(MoonliftSem.SemBinding binding) unique
             | SemPlaceDeref(MoonliftSem.SemExpr base, MoonliftSem.SemType elem) unique
             | SemPlaceField(MoonliftSem.SemPlace base, MoonliftSem.SemFieldRef field) unique
             | SemPlaceIndex(MoonliftSem.SemIndexBase base, MoonliftSem.SemExpr index, MoonliftSem.SemType ty) unique

    SemExpr = SemExprConstInt(MoonliftSem.SemType ty, string raw) unique
            | SemExprConstFloat(MoonliftSem.SemType ty, string raw) unique
            | SemExprConstBool(boolean value) unique
            | SemExprNil(MoonliftSem.SemType ty) unique
            | SemExprBinding(MoonliftSem.SemBinding binding) unique
            | SemExprNeg(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprNot(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprBNot(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprAddrOf(MoonliftSem.SemPlace place, MoonliftSem.SemType ty) unique
            | SemExprDeref(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprAdd(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprSub(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprMul(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprDiv(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprRem(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprEq(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprNe(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprLt(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprLe(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprGt(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprGe(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprAnd(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprOr(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprBitAnd(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprBitOr(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprBitXor(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprShl(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprLShr(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprAShr(MoonliftSem.SemType ty, MoonliftSem.SemExpr lhs, MoonliftSem.SemExpr rhs) unique
            | SemExprCastTo(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprTruncTo(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprZExtTo(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprSExtTo(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprBitcastTo(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprSatCastTo(MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
            | SemExprSelect(MoonliftSem.SemExpr cond, MoonliftSem.SemExpr then_value, MoonliftSem.SemExpr else_value, MoonliftSem.SemType ty) unique
            | SemExprIndex(MoonliftSem.SemIndexBase base, MoonliftSem.SemExpr index, MoonliftSem.SemType ty) unique
            | SemExprField(MoonliftSem.SemExpr base, MoonliftSem.SemFieldRef field) unique
            | SemExprLoad(MoonliftSem.SemType ty, MoonliftSem.SemExpr addr) unique
            | SemExprIntrinsicCall(MoonliftSem.SemIntrinsic op, MoonliftSem.SemType ty, MoonliftSem.SemExpr* args) unique
            | SemExprCall(MoonliftSem.SemCallTarget target, MoonliftSem.SemType ty, MoonliftSem.SemExpr* args) unique
            | SemExprAgg(MoonliftSem.SemType ty, MoonliftSem.SemFieldInit* fields) unique
            | SemExprArrayLit(MoonliftSem.SemType elem_ty, MoonliftSem.SemExpr* elems) unique
            | SemExprBlock(MoonliftSem.SemStmt* stmts, MoonliftSem.SemExpr result, MoonliftSem.SemType ty) unique
            | SemExprIf(MoonliftSem.SemExpr cond, MoonliftSem.SemExpr then_expr, MoonliftSem.SemExpr else_expr, MoonliftSem.SemType ty) unique
            | SemExprSwitch(MoonliftSem.SemExpr value, MoonliftSem.SemSwitchExprArm* arms, MoonliftSem.SemExpr default_expr, MoonliftSem.SemType ty) unique
            | SemExprLoop(MoonliftSem.SemLoop loop, MoonliftSem.SemType ty) unique

    SemLoop = SemLoopWhileStmt(string loop_id, MoonliftSem.SemLoopCarryPort* carries, MoonliftSem.SemExpr cond, MoonliftSem.SemStmt* body, MoonliftSem.SemLoopUpdate* next) unique
            | SemLoopOverStmt(string loop_id, MoonliftSem.SemLoopIndexPort index_port, MoonliftSem.SemDomain domain, MoonliftSem.SemLoopCarryPort* carries, MoonliftSem.SemStmt* body, MoonliftSem.SemLoopUpdate* next) unique
            | SemLoopWhileExpr(string loop_id, MoonliftSem.SemLoopCarryPort* carries, MoonliftSem.SemExpr cond, MoonliftSem.SemStmt* body, MoonliftSem.SemLoopUpdate* next, MoonliftSem.SemExpr result) unique
            | SemLoopOverExpr(string loop_id, MoonliftSem.SemLoopIndexPort index_port, MoonliftSem.SemDomain domain, MoonliftSem.SemLoopCarryPort* carries, MoonliftSem.SemStmt* body, MoonliftSem.SemLoopUpdate* next, MoonliftSem.SemExpr result) unique

    SemStmt = SemStmtLet(string id, string name, MoonliftSem.SemType ty, MoonliftSem.SemExpr init) unique
            | SemStmtVar(string id, string name, MoonliftSem.SemType ty, MoonliftSem.SemExpr init) unique
            | SemStmtSet(MoonliftSem.SemPlace place, MoonliftSem.SemExpr value) unique
            | SemStmtExpr(MoonliftSem.SemExpr expr) unique
            | SemStmtIf(MoonliftSem.SemExpr cond, MoonliftSem.SemStmt* then_body, MoonliftSem.SemStmt* else_body) unique
            | SemStmtSwitch(MoonliftSem.SemExpr value, MoonliftSem.SemSwitchStmtArm* arms, MoonliftSem.SemStmt* default_body) unique
            | SemStmtAssert(MoonliftSem.SemExpr cond) unique
            | SemStmtReturnVoid
            | SemStmtReturnValue(MoonliftSem.SemExpr value) unique
            | SemStmtBreak
            | SemStmtBreakValue(MoonliftSem.SemExpr value) unique
            | SemStmtContinue
            | SemStmtLoop(MoonliftSem.SemLoop loop) unique

    SemFunc = SemFuncLocal(string name, MoonliftSem.SemParam* params, MoonliftSem.SemType result, MoonliftSem.SemStmt* body) unique
            | SemFuncExport(string name, MoonliftSem.SemParam* params, MoonliftSem.SemType result, MoonliftSem.SemStmt* body) unique
    SemExternFunc = (string name, string symbol, MoonliftSem.SemParam* params, MoonliftSem.SemType result) unique
    SemConst = (string name, MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
    SemStatic = (string name, MoonliftSem.SemType ty, MoonliftSem.SemExpr value) unique
    SemImport = (string module_name) unique
    SemTypeDecl = SemStruct(string name, MoonliftSem.SemFieldType* fields) unique
    SemItem = SemItemFunc(MoonliftSem.SemFunc func) unique
            | SemItemExtern(MoonliftSem.SemExternFunc func) unique
            | SemItemConst(MoonliftSem.SemConst c) unique
            | SemItemStatic(MoonliftSem.SemStatic s) unique
            | SemItemImport(MoonliftSem.SemImport imp) unique
            | SemItemType(MoonliftSem.SemTypeDecl t) unique
    SemModule = (string module_name, MoonliftSem.SemItem* items) unique
}

module MoonliftBack {
    BackScalar = BackVoid
               | BackBool
               | BackI8 | BackI16 | BackI32 | BackI64
               | BackU8 | BackU16 | BackU32 | BackU64
               | BackF32 | BackF64
               | BackPtr
               | BackIndex

    BackSigId = (string text) unique
    BackFuncId = (string text) unique
    BackExternId = (string text) unique
    BackDataId = (string text) unique
    BackBlockId = (string text) unique
    BackValId = (string text) unique
    BackStackSlotId = (string text) unique
    BackSwitchCase = (string raw, MoonliftBack.BackBlockId dest) unique

    BackCmd = BackCmdCreateSig(MoonliftBack.BackSigId sig, MoonliftBack.BackScalar* params, MoonliftBack.BackScalar* results) unique
            | BackCmdDeclareData(MoonliftBack.BackDataId data, number size, number align) unique
            | BackCmdDataInitZero(MoonliftBack.BackDataId data, number offset, number size) unique
            | BackCmdDataInitInt(MoonliftBack.BackDataId data, number offset, MoonliftBack.BackScalar ty, string raw) unique
            | BackCmdDataInitFloat(MoonliftBack.BackDataId data, number offset, MoonliftBack.BackScalar ty, string raw) unique
            | BackCmdDataInitBool(MoonliftBack.BackDataId data, number offset, boolean value) unique
            | BackCmdDataAddr(MoonliftBack.BackValId dst, MoonliftBack.BackDataId data) unique
            | BackCmdDeclareFuncLocal(MoonliftBack.BackFuncId func, MoonliftBack.BackSigId sig) unique
            | BackCmdDeclareFuncExport(MoonliftBack.BackFuncId func, MoonliftBack.BackSigId sig) unique
            | BackCmdDeclareFuncExtern(MoonliftBack.BackExternId func, string symbol, MoonliftBack.BackSigId sig) unique
            | BackCmdBeginFunc(MoonliftBack.BackFuncId func) unique
            | BackCmdCreateBlock(MoonliftBack.BackBlockId block) unique
            | BackCmdSwitchToBlock(MoonliftBack.BackBlockId block) unique
            | BackCmdSealBlock(MoonliftBack.BackBlockId block) unique
            | BackCmdBindEntryParams(MoonliftBack.BackBlockId block, MoonliftBack.BackValId* values) unique
            | BackCmdAppendBlockParam(MoonliftBack.BackBlockId block, MoonliftBack.BackValId value, MoonliftBack.BackScalar ty) unique
            | BackCmdCreateStackSlot(MoonliftBack.BackStackSlotId slot, number size, number align) unique
            | BackCmdAlias(MoonliftBack.BackValId dst, MoonliftBack.BackValId src) unique
            | BackCmdStackAddr(MoonliftBack.BackValId dst, MoonliftBack.BackStackSlotId slot) unique
            | BackCmdConstInt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, string raw) unique
            | BackCmdConstFloat(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, string raw) unique
            | BackCmdConstBool(MoonliftBack.BackValId dst, boolean value) unique
            | BackCmdConstNull(MoonliftBack.BackValId dst) unique
            | BackCmdIneg(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdFneg(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdBnot(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdBoolNot(MoonliftBack.BackValId dst, MoonliftBack.BackValId value) unique
            | BackCmdPopcount(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdClz(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdCtz(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdBswap(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdSqrt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdAbs(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdFloor(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdCeil(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdTruncFloat(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdRound(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdIadd(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdIsub(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdImul(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFadd(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFsub(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFmul(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSdiv(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUdiv(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFdiv(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSrem(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUrem(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFrem(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdBand(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdBor(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdBxor(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdIshl(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUshr(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSshr(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdRotl(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdRotr(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdIcmpEq(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdIcmpNe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSIcmpLt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSIcmpLe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSIcmpGt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdSIcmpGe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUIcmpLt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUIcmpLe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUIcmpGt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdUIcmpGe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFCmpEq(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFCmpNe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFCmpLt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFCmpLe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFCmpGt(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdFCmpGe(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId lhs, MoonliftBack.BackValId rhs) unique
            | BackCmdBitcast(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdIreduce(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdSextend(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdUextend(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdFpromote(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdFdemote(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdSToF(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdUToF(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdFToS(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdFToU(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId value) unique
            | BackCmdLoad(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId addr) unique
            | BackCmdStore(MoonliftBack.BackScalar ty, MoonliftBack.BackValId addr, MoonliftBack.BackValId value) unique
            | BackCmdSelect(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId cond, MoonliftBack.BackValId then_value, MoonliftBack.BackValId else_value) unique
            | BackCmdFma(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId a, MoonliftBack.BackValId b, MoonliftBack.BackValId c) unique
            | BackCmdCallValueDirect(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackFuncId func, MoonliftBack.BackSigId sig, MoonliftBack.BackValId* args) unique
            | BackCmdCallStmtDirect(MoonliftBack.BackFuncId func, MoonliftBack.BackSigId sig, MoonliftBack.BackValId* args) unique
            | BackCmdCallValueExtern(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackExternId func, MoonliftBack.BackSigId sig, MoonliftBack.BackValId* args) unique
            | BackCmdCallStmtExtern(MoonliftBack.BackExternId func, MoonliftBack.BackSigId sig, MoonliftBack.BackValId* args) unique
            | BackCmdCallValueIndirect(MoonliftBack.BackValId dst, MoonliftBack.BackScalar ty, MoonliftBack.BackValId callee, MoonliftBack.BackSigId sig, MoonliftBack.BackValId* args) unique
            | BackCmdCallStmtIndirect(MoonliftBack.BackValId callee, MoonliftBack.BackSigId sig, MoonliftBack.BackValId* args) unique
            | BackCmdJump(MoonliftBack.BackBlockId dest, MoonliftBack.BackValId* args) unique
            | BackCmdBrIf(MoonliftBack.BackValId cond, MoonliftBack.BackBlockId then_block, MoonliftBack.BackValId* then_args, MoonliftBack.BackBlockId else_block, MoonliftBack.BackValId* else_args) unique
            | BackCmdSwitchInt(MoonliftBack.BackValId value, MoonliftBack.BackScalar ty, MoonliftBack.BackSwitchCase* cases, MoonliftBack.BackBlockId default_dest) unique
            | BackCmdReturnVoid
            | BackCmdReturnValue(MoonliftBack.BackValId value) unique
            | BackCmdTrap
            | BackCmdFinishFunc(MoonliftBack.BackFuncId func) unique
            | BackCmdFinalizeModule

    BackFlow = BackFallsThrough | BackTerminates
    BackSigSpec = (MoonliftBack.BackScalar* params, MoonliftBack.BackScalar* results) unique
    BackStackSlotSpec = (number size, number align) unique
    BackExprLowering = BackExprPlan(MoonliftBack.BackCmd* cmds, MoonliftBack.BackValId value, MoonliftBack.BackScalar ty) unique
                     | BackExprTerminated(MoonliftBack.BackCmd* cmds) unique
    BackAddrLowering = BackAddrWrites(MoonliftBack.BackCmd* cmds) unique
                     | BackAddrTerminated(MoonliftBack.BackCmd* cmds) unique
    BackStmtPlan = (MoonliftBack.BackCmd* cmds, MoonliftBack.BackFlow flow) unique
    BackFuncPlan = (MoonliftBack.BackCmd* cmds) unique
    BackItemPlan = (MoonliftBack.BackCmd* cmds) unique
    BackProgram = (MoonliftBack.BackCmd* cmds) unique
}
]]

function M.Define(T)
    T:Define(M.SCHEMA)
    return T
end

return M
