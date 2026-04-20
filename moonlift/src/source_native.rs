use crate::ast::{
    BinaryOp as AstBinaryOp, Block, CastKind, Expr as AstExpr, ExprKind, FuncDecl, FuncName,
    IfStmt, Item, ItemKind, ModuleAst, NumberKind, Param, Path, Stmt as AstStmt, TypeExpr,
    UnaryOp as AstUnaryOp,
};
use crate::cranelift_jit::{
    BinaryOp, CallTarget, CastOp, Expr, FunctionSpec, ScalarType, Stmt, UnaryOp,
};
use crate::parser::{parse_code, parse_module};
use std::collections::HashMap;

#[derive(Clone, Debug)]
pub struct NativeParamMeta {
    pub name: String,
    pub ty: ScalarType,
}

#[derive(Clone, Debug)]
pub struct NativeFuncMeta {
    pub name: String,
    pub params: Vec<NativeParamMeta>,
    pub result: ScalarType,
}

#[derive(Clone, Debug)]
pub struct PreparedCode {
    pub meta: NativeFuncMeta,
    pub spec: FunctionSpec,
}

#[derive(Clone, Debug)]
pub struct PreparedModule {
    pub funcs: Vec<PreparedCode>,
}

#[derive(Clone)]
struct FuncSigInfo {
    params: Vec<ScalarType>,
    result: ScalarType,
}

#[derive(Clone)]
struct BindingInfo {
    lowered_name: String,
    ty: ScalarType,
    mutable: bool,
    arg_index: Option<u32>,
}

struct LowerCtx<'a> {
    scopes: Vec<HashMap<String, BindingInfo>>,
    funcs: &'a HashMap<String, FuncSigInfo>,
    next_local_id: usize,
}

const UNSUPPORTED_PREFIX: &str = "unsupported native source fast path: ";

fn unsupported<T>(message: impl Into<String>) -> Result<T, String> {
    Err(format!("{UNSUPPORTED_PREFIX}{}", message.into()))
}

fn path_name(path: &Path) -> Result<&str, String> {
    if path.segments.len() == 1 {
        Ok(&path.segments[0])
    } else {
        unsupported("qualified paths are not yet supported")
    }
}

fn scalar_type_from_type_expr(ty: &TypeExpr) -> Result<ScalarType, String> {
    match ty {
        TypeExpr::Path(path) => {
            let name = path_name(path)?;
            ScalarType::from_name(name).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}non-scalar type '{name}' is not yet supported")
            })
        }
        _ => unsupported("only scalar path types are supported natively right now"),
    }
}

fn prepare_param_meta(param: &Param) -> Result<NativeParamMeta, String> {
    Ok(NativeParamMeta {
        name: param.name.clone(),
        ty: scalar_type_from_type_expr(&param.ty)?,
    })
}

fn func_meta_from_decl(func: &FuncDecl) -> Result<NativeFuncMeta, String> {
    let name = match &func.sig.name {
        FuncName::Named(name) => name.clone(),
        FuncName::Anonymous => return unsupported("anonymous funcs are not yet supported natively"),
        FuncName::Method { .. } => return unsupported("methods are not yet supported natively"),
    };
    let mut params = Vec::with_capacity(func.sig.params.len());
    for param in &func.sig.params {
        params.push(prepare_param_meta(param)?);
    }
    let Some(result_ty) = &func.sig.result else {
        return unsupported("explicit function results are currently required natively");
    };
    Ok(NativeFuncMeta {
        name,
        params,
        result: scalar_type_from_type_expr(result_ty)?,
    })
}

fn collect_module_metas(module: &ModuleAst) -> Result<Vec<NativeFuncMeta>, String> {
    let mut out = Vec::new();
    for item in &module.items {
        match &item.kind {
            ItemKind::Func(func) => out.push(func_meta_from_decl(func)?),
            _ => {
                return unsupported(
                    "modules with non-func items are not yet supported by the native fast path",
                )
            }
        }
    }
    Ok(out)
}

fn known_expr_type(expr: &AstExpr, ctx: &LowerCtx<'_>) -> Option<ScalarType> {
    match &expr.kind {
        ExprKind::Path(path) => ctx.lookup(path_name(path).ok()?).map(|v| v.ty),
        ExprKind::Bool(_) => Some(ScalarType::Bool),
        ExprKind::Number(v) => Some(match v.kind {
            NumberKind::Int => ScalarType::I32,
            NumberKind::Float => ScalarType::F64,
        }),
        ExprKind::Cast { ty, .. } => scalar_type_from_type_expr(ty).ok(),
        ExprKind::Call { callee, .. } => match &callee.kind {
            ExprKind::Path(path) => ctx.funcs.get(path_name(path).ok()?).map(|v| v.result),
            _ => None,
        },
        ExprKind::Unary { op, expr } => match op {
            AstUnaryOp::Not => Some(ScalarType::Bool),
            AstUnaryOp::Neg | AstUnaryOp::BitNot => known_expr_type(expr, ctx),
            AstUnaryOp::AddrOf | AstUnaryOp::Deref => None,
        },
        ExprKind::Binary { op, lhs, rhs } => match op {
            AstBinaryOp::Eq
            | AstBinaryOp::Ne
            | AstBinaryOp::Lt
            | AstBinaryOp::Le
            | AstBinaryOp::Gt
            | AstBinaryOp::Ge
            | AstBinaryOp::And
            | AstBinaryOp::Or => Some(ScalarType::Bool),
            _ => known_expr_type(lhs, ctx).or_else(|| known_expr_type(rhs, ctx)),
        },
        ExprKind::If(v) => known_expr_type(&v.branches.first()?.value, ctx)
            .or_else(|| known_expr_type(&v.else_branch, ctx)),
        ExprKind::Block(block) => final_block_expr_type(block, ctx),
        _ => None,
    }
}

fn final_block_expr_type(block: &Block, ctx: &LowerCtx<'_>) -> Option<ScalarType> {
    let last = block.stmts.last()?;
    match last {
        AstStmt::Return { value: Some(value), .. } => known_expr_type(value, ctx),
        AstStmt::Expr { expr, .. } => known_expr_type(expr, ctx),
        _ => None,
    }
}

fn default_number_type(kind: &NumberKind) -> ScalarType {
    match kind {
        NumberKind::Int => ScalarType::I32,
        NumberKind::Float => ScalarType::F64,
    }
}

fn parse_int_bits(raw: &str, ty: ScalarType) -> Result<u64, String> {
    match ty {
        ScalarType::I8 | ScalarType::I16 | ScalarType::I32 | ScalarType::I64 => raw
            .parse::<i64>()
            .map(|v| v as u64)
            .map_err(|_| format!("failed to parse integer literal {raw:?}")),
        ScalarType::U8 | ScalarType::U16 | ScalarType::U32 | ScalarType::U64 | ScalarType::Ptr => raw
            .parse::<u64>()
            .or_else(|_| raw.parse::<i64>().map(|v| v as u64))
            .map_err(|_| format!("failed to parse integer literal {raw:?}")),
        _ => Err(format!("integer literal is not valid for type {}", ty.name())),
    }
}

fn lower_number_const(raw: &str, kind: NumberKind, expected: Option<ScalarType>) -> Result<Expr, String> {
    let ty = expected.unwrap_or_else(|| default_number_type(&kind));
    match kind {
        NumberKind::Int => {
            if ty.is_float() {
                let value = raw
                    .parse::<f64>()
                    .map_err(|_| format!("failed to parse float literal {raw:?}"))?;
                Ok(match ty {
                    ScalarType::F32 => Expr::Const {
                        ty,
                        bits: (value as f32).to_bits() as u64,
                    },
                    ScalarType::F64 => Expr::Const {
                        ty,
                        bits: value.to_bits(),
                    },
                    _ => unreachable!(),
                })
            } else {
                Ok(Expr::Const {
                    ty,
                    bits: parse_int_bits(raw, ty)?,
                })
            }
        }
        NumberKind::Float => {
            let ty = if ty.is_float() { ty } else { ScalarType::F64 };
            let value = raw
                .parse::<f64>()
                .map_err(|_| format!("failed to parse float literal {raw:?}"))?;
            Ok(match ty {
                ScalarType::F32 => Expr::Const {
                    ty,
                    bits: (value as f32).to_bits() as u64,
                },
                ScalarType::F64 => Expr::Const {
                    ty,
                    bits: value.to_bits(),
                },
                _ => return unsupported("float literals currently require a float context natively"),
            })
        }
    }
}

impl<'a> LowerCtx<'a> {
    fn new(funcs: &'a HashMap<String, FuncSigInfo>) -> Self {
        Self {
            scopes: vec![HashMap::new()],
            funcs,
            next_local_id: 0,
        }
    }

    fn push_scope(&mut self) {
        self.scopes.push(HashMap::new());
    }

    fn pop_scope(&mut self) {
        self.scopes.pop();
    }

    fn bind_param(&mut self, name: &str, ty: ScalarType, index: u32) -> BindingInfo {
        let binding = BindingInfo {
            lowered_name: name.to_string(),
            ty,
            mutable: false,
            arg_index: Some(index),
        };
        self.scopes
            .first_mut()
            .expect("scope stack is never empty")
            .insert(name.to_string(), binding.clone());
        binding
    }

    fn bind(&mut self, name: &str, ty: ScalarType, mutable: bool) -> BindingInfo {
        let lowered_name = if self.scopes.len() == 1 && self.lookup(name).is_none() {
            name.to_string()
        } else {
            self.next_local_id += 1;
            format!("{name}${}", self.next_local_id)
        };
        let binding = BindingInfo {
            lowered_name: lowered_name.clone(),
            ty,
            mutable,
            arg_index: None,
        };
        self.scopes
            .last_mut()
            .expect("scope stack is never empty")
            .insert(name.to_string(), binding.clone());
        binding
    }

    fn lookup(&self, name: &str) -> Option<&BindingInfo> {
        for scope in self.scopes.iter().rev() {
            if let Some(binding) = scope.get(name) {
                return Some(binding);
            }
        }
        None
    }
}

fn select_binary_operand_type(
    lhs: &AstExpr,
    rhs: &AstExpr,
    ctx: &LowerCtx<'_>,
    expected: Option<ScalarType>,
) -> ScalarType {
    if let Some(t) = expected.filter(|t| *t != ScalarType::Bool) {
        return t;
    }
    if let Some(t) = known_expr_type(lhs, ctx) {
        return t;
    }
    if let Some(t) = known_expr_type(rhs, ctx) {
        return t;
    }
    let lhs_float = matches!(lhs.kind, ExprKind::Number(ref n) if n.kind == NumberKind::Float);
    let rhs_float = matches!(rhs.kind, ExprKind::Number(ref n) if n.kind == NumberKind::Float);
    if lhs_float || rhs_float {
        ScalarType::F64
    } else {
        ScalarType::I32
    }
}

fn lower_expr(expr: &AstExpr, ctx: &mut LowerCtx<'_>, expected: Option<ScalarType>) -> Result<Expr, String> {
    match &expr.kind {
        ExprKind::Path(path) => {
            let name = path_name(path)?;
            let binding = ctx
                .lookup(name)
                .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown local name '{name}'"))?;
            if let Some(index) = binding.arg_index {
                Ok(Expr::Arg {
                    index,
                    ty: binding.ty,
                })
            } else {
                Ok(Expr::Local {
                    name: binding.lowered_name.clone(),
                    ty: binding.ty,
                })
            }
        }
        ExprKind::Number(v) => lower_number_const(&v.raw, v.kind.clone(), expected),
        ExprKind::Bool(v) => Ok(Expr::Const {
            ty: ScalarType::Bool,
            bits: if *v { 1 } else { 0 },
        }),
        ExprKind::Unary { op, expr } => match op {
            AstUnaryOp::Neg => {
                let ty = expected
                    .or_else(|| known_expr_type(expr, ctx))
                    .unwrap_or(ScalarType::I32);
                let value = lower_expr(expr, ctx, Some(ty))?;
                Ok(Expr::Unary {
                    op: UnaryOp::Neg,
                    ty,
                    value: Box::new(value),
                })
            }
            AstUnaryOp::Not => {
                let value = lower_expr(expr, ctx, Some(ScalarType::Bool))?;
                Ok(Expr::Unary {
                    op: UnaryOp::Not,
                    ty: ScalarType::Bool,
                    value: Box::new(value),
                })
            }
            AstUnaryOp::BitNot => {
                let ty = expected
                    .or_else(|| known_expr_type(expr, ctx))
                    .unwrap_or(ScalarType::I32);
                let value = lower_expr(expr, ctx, Some(ty))?;
                Ok(Expr::Unary {
                    op: UnaryOp::Bnot,
                    ty,
                    value: Box::new(value),
                })
            }
            AstUnaryOp::AddrOf | AstUnaryOp::Deref => {
                unsupported("addr-of and deref are not yet supported natively")
            }
        },
        ExprKind::Binary { op, lhs, rhs } => {
            use AstBinaryOp as B;
            match op {
                B::And | B::Or => {
                    let lhs = lower_expr(lhs, ctx, Some(ScalarType::Bool))?;
                    let rhs = lower_expr(rhs, ctx, Some(ScalarType::Bool))?;
                    Ok(Expr::Binary {
                        op: if matches!(op, B::And) { BinaryOp::And } else { BinaryOp::Or },
                        ty: ScalarType::Bool,
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    })
                }
                B::Eq | B::Ne | B::Lt | B::Le | B::Gt | B::Ge => {
                    let operand_ty = select_binary_operand_type(lhs, rhs, ctx, None);
                    let lhs = lower_expr(lhs, ctx, Some(operand_ty))?;
                    let rhs = lower_expr(rhs, ctx, Some(operand_ty))?;
                    let op = match op {
                        B::Eq => BinaryOp::Eq,
                        B::Ne => BinaryOp::Ne,
                        B::Lt => BinaryOp::Lt,
                        B::Le => BinaryOp::Le,
                        B::Gt => BinaryOp::Gt,
                        B::Ge => BinaryOp::Ge,
                        _ => unreachable!(),
                    };
                    Ok(Expr::Binary {
                        op,
                        ty: ScalarType::Bool,
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    })
                }
                _ => {
                    let ty = select_binary_operand_type(lhs, rhs, ctx, expected);
                    let lhs = lower_expr(lhs, ctx, Some(ty))?;
                    let rhs = lower_expr(rhs, ctx, Some(ty))?;
                    let op = match op {
                        B::Add => BinaryOp::Add,
                        B::Sub => BinaryOp::Sub,
                        B::Mul => BinaryOp::Mul,
                        B::Div => BinaryOp::Div,
                        B::Rem => BinaryOp::Rem,
                        B::BitAnd => BinaryOp::Band,
                        B::BitOr => BinaryOp::Bor,
                        B::BitXor => BinaryOp::Bxor,
                        B::Shl => BinaryOp::Shl,
                        B::ShrU => BinaryOp::ShrU,
                        B::Shr => {
                            if ty.is_signed_integer() {
                                BinaryOp::ShrS
                            } else {
                                BinaryOp::ShrU
                            }
                        }
                        _ => unreachable!(),
                    };
                    Ok(Expr::Binary {
                        op,
                        ty,
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    })
                }
            }
        }
        ExprKind::If(v) => {
            let branch_ty = expected
                .or_else(|| known_expr_type(&v.branches[0].value, ctx))
                .or_else(|| known_expr_type(&v.else_branch, ctx))
                .unwrap_or(ScalarType::I32);
            let cond = lower_expr(&v.branches[0].cond, ctx, Some(ScalarType::Bool))?;
            let then_expr = lower_expr(&v.branches[0].value, ctx, Some(branch_ty))?;
            let else_expr = if v.branches.len() == 1 {
                lower_expr(&v.else_branch, ctx, Some(branch_ty))?
            } else {
                let nested = crate::ast::Expr {
                    kind: ExprKind::If(crate::ast::IfExpr {
                        branches: v.branches[1..].to_vec(),
                        else_branch: v.else_branch.clone(),
                        span: v.span,
                    }),
                    span: expr.span,
                };
                lower_expr(&nested, ctx, Some(branch_ty))?
            };
            Ok(Expr::If {
                cond: Box::new(cond),
                then_expr: Box::new(then_expr),
                else_expr: Box::new(else_expr),
                ty: branch_ty,
            })
        }
        ExprKind::Cast { kind, ty, value } => {
            let ty = scalar_type_from_type_expr(ty)?;
            let value = lower_expr(value, ctx, None)?;
            let op = match kind {
                CastKind::Cast => CastOp::Cast,
                CastKind::Trunc => CastOp::Trunc,
                CastKind::Zext => CastOp::Zext,
                CastKind::Sext => CastOp::Sext,
                CastKind::Bitcast => CastOp::Bitcast,
            };
            Ok(Expr::Cast {
                op,
                ty,
                value: Box::new(value),
            })
        }
        ExprKind::Call { callee, args } => {
            let ExprKind::Path(path) = &callee.kind else {
                return unsupported("only direct named calls are supported natively");
            };
            let name = path_name(path)?;
            let sig = ctx
                .funcs
                .get(name)
                .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown callee '{name}'"))?
                .clone();
            if sig.params.len() != args.len() {
                return Err(format!(
                    "native source fast path call '{}' expected {} args, got {}",
                    name,
                    sig.params.len(),
                    args.len()
                ));
            }
            let mut lowered_args = Vec::with_capacity(args.len());
            for (arg, param_ty) in args.iter().zip(sig.params.iter().copied()) {
                lowered_args.push(lower_expr(arg, ctx, Some(param_ty))?);
            }
            Ok(Expr::Call {
                target: CallTarget::Direct {
                    name: name.to_string(),
                    params: sig.params.clone(),
                    result: sig.result,
                },
                ty: sig.result,
                args: lowered_args,
            })
        }
        ExprKind::Block(block) => lower_block_value(block, ctx, expected),
        _ => unsupported("expression form is not yet supported by the native fast path"),
    }
}

fn lower_if_stmt_chain(stmt: &IfStmt, ctx: &mut LowerCtx<'_>) -> Result<Stmt, String> {
    let first = stmt
        .branches
        .first()
        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}empty if statement"))?;
    let cond = lower_expr(&first.cond, ctx, Some(ScalarType::Bool))?;
    let then_body = lower_stmt_block(&first.body, ctx)?;
    let else_body = if stmt.branches.len() > 1 {
        let nested = IfStmt {
            branches: stmt.branches[1..].to_vec(),
            else_branch: stmt.else_branch.clone(),
            span: stmt.span,
        };
        vec![lower_if_stmt_chain(&nested, ctx)?]
    } else if let Some(block) = &stmt.else_branch {
        lower_stmt_block(block, ctx)?
    } else {
        Vec::new()
    };
    Ok(Stmt::If {
        cond,
        then_body,
        else_body,
    })
}

fn lower_stmt(stmt: &AstStmt, ctx: &mut LowerCtx<'_>) -> Result<Stmt, String> {
    match stmt {
        AstStmt::Let { name, ty, value, .. } => {
            let inferred = ty
                .as_ref()
                .map(scalar_type_from_type_expr)
                .transpose()?
                .or_else(|| known_expr_type(value, ctx))
                .unwrap_or(ScalarType::I32);
            let init = lower_expr(value, ctx, Some(inferred))?;
            let binding = ctx.bind(name, inferred, false);
            Ok(Stmt::Let {
                name: binding.lowered_name,
                ty: inferred,
                init,
            })
        }
        AstStmt::Var { name, ty, value, .. } => {
            let inferred = ty
                .as_ref()
                .map(scalar_type_from_type_expr)
                .transpose()?
                .or_else(|| known_expr_type(value, ctx))
                .unwrap_or(ScalarType::I32);
            let init = lower_expr(value, ctx, Some(inferred))?;
            let binding = ctx.bind(name, inferred, true);
            Ok(Stmt::Var {
                name: binding.lowered_name,
                ty: inferred,
                init,
            })
        }
        AstStmt::Assign { target, value, .. } => {
            let ExprKind::Path(path) = &target.kind else {
                return unsupported("only simple local assignment targets are supported natively");
            };
            let name = path_name(path)?;
            let binding = ctx
                .lookup(name)
                .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown assignment target '{name}'"))?
                .clone();
            if !binding.mutable {
                return Err(format!("cannot assign to immutable local '{name}'"));
            }
            Ok(Stmt::Set {
                name: binding.lowered_name,
                value: lower_expr(value, ctx, Some(binding.ty))?,
            })
        }
        AstStmt::While { cond, body, .. } => Ok(Stmt::While {
            cond: lower_expr(cond, ctx, Some(ScalarType::Bool))?,
            body: lower_stmt_block(body, ctx)?,
        }),
        AstStmt::If(v) => lower_if_stmt_chain(v, ctx),
        AstStmt::Break { .. } => Ok(Stmt::Break),
        AstStmt::Continue { .. } => Ok(Stmt::Continue),
        AstStmt::Expr { expr, .. } => {
            let lowered = lower_expr(expr, ctx, None)?;
            match lowered {
                Expr::Call { target, args, ty } if ty == ScalarType::Void => Ok(Stmt::Call { target, args }),
                _ => unsupported("non-tail expression statements are not yet supported natively"),
            }
        }
        AstStmt::Return { .. } => unsupported("early return statements are not yet supported natively"),
        _ => unsupported("statement form is not yet supported by the native fast path"),
    }
}

fn lower_stmt_block(block: &Block, ctx: &mut LowerCtx<'_>) -> Result<Vec<Stmt>, String> {
    ctx.push_scope();
    let result = (|| {
        let mut out = Vec::with_capacity(block.stmts.len());
        for stmt in &block.stmts {
            out.push(lower_stmt(stmt, ctx)?);
        }
        Ok(out)
    })();
    ctx.pop_scope();
    result
}

fn lower_block_value(block: &Block, ctx: &mut LowerCtx<'_>, expected: Option<ScalarType>) -> Result<Expr, String> {
    ctx.push_scope();
    let result = (|| {
        let Some((last, prefix)) = block.stmts.split_last() else {
            return unsupported("empty value blocks are not yet supported natively");
        };

        let mut stmts = Vec::with_capacity(prefix.len());
        for stmt in prefix {
            stmts.push(lower_stmt(stmt, ctx)?);
        }

        let result_expr = match last {
            AstStmt::Return { value: Some(value), .. } => {
                lower_expr(value, ctx, expected.or_else(|| known_expr_type(value, ctx)))?
            }
            AstStmt::Expr { expr, .. } => lower_expr(expr, ctx, expected.or_else(|| known_expr_type(expr, ctx)))?,
            AstStmt::If(v) => {
                let stmt = lower_if_stmt_chain(v, ctx)?;
                stmts.push(stmt);
                return unsupported(
                    "value blocks ending in statement if are not yet supported natively",
                );
            }
            AstStmt::Return { value: None, .. } => {
                return unsupported("void returns are not yet supported natively")
            }
            _ => {
                return unsupported(
                    "value blocks must end in return <expr> or a tail expression natively",
                )
            }
        };
        if stmts.is_empty() {
            Ok(result_expr)
        } else {
            Ok(Expr::Block {
                ty: result_expr.ty(),
                stmts,
                result: Box::new(result_expr),
            })
        }
    })();
    ctx.pop_scope();
    result
}

fn build_sig_map(metas: &[NativeFuncMeta]) -> HashMap<String, FuncSigInfo> {
    let mut out = HashMap::new();
    for meta in metas {
        out.insert(
            meta.name.clone(),
            FuncSigInfo {
                params: meta.params.iter().map(|v| v.ty).collect(),
                result: meta.result,
            },
        );
    }
    out
}

fn prepare_code_from_item(item: &Item) -> Result<PreparedCode, String> {
    let ItemKind::Func(func) = &item.kind else {
        return unsupported("only func code items are currently supported natively");
    };
    let meta = func_meta_from_decl(func)?;
    let sig_map = build_sig_map(std::slice::from_ref(&meta));
    let spec = lower_func_decl(func, &meta, &sig_map)?;
    Ok(PreparedCode { meta, spec })
}

fn lower_func_decl(
    func: &FuncDecl,
    meta: &NativeFuncMeta,
    sig_map: &HashMap<String, FuncSigInfo>,
) -> Result<FunctionSpec, String> {
    let mut ctx = LowerCtx::new(sig_map);
    let mut lowered_params = Vec::with_capacity(meta.params.len());
    for (i, param) in meta.params.iter().enumerate() {
        ctx.bind_param(&param.name, param.ty, (i + 1) as u32);
        lowered_params.push(param.ty);
    }
    let body = lower_block_value(&func.body, &mut ctx, Some(meta.result))?;
    Ok(FunctionSpec {
        name: meta.name.clone(),
        params: lowered_params,
        result: meta.result,
        locals: Vec::new(),
        body,
    })
}

pub fn prepare_code(source: &str) -> Result<PreparedCode, String> {
    let item = parse_code(source).map_err(|e| e.render(source))?;
    prepare_code_from_item(&item)
}

pub fn prepare_module(source: &str) -> Result<PreparedModule, String> {
    let module = parse_module(source).map_err(|e| e.render(source))?;
    let metas = collect_module_metas(&module)?;
    let sig_map = build_sig_map(&metas);
    let mut funcs = Vec::with_capacity(module.items.len());
    for (item, meta) in module.items.iter().zip(metas.iter()) {
        let ItemKind::Func(func) = &item.kind else {
            return unsupported("only func module items are currently supported natively");
        };
        funcs.push(PreparedCode {
            meta: meta.clone(),
            spec: lower_func_decl(func, meta, &sig_map)?,
        });
    }
    Ok(PreparedModule { funcs })
}
