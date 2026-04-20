use crate::ast::*;

pub fn item_to_lua(item: &Item) -> String {
    let mut out = String::new();
    push_item(&mut out, item);
    out
}

pub fn module_to_lua(module: &ModuleAst) -> String {
    let mut out = String::new();
    out.push_str("{ tag = \"module\", items = ");
    push_items(&mut out, &module.items);
    out.push_str(" }");
    out
}

pub fn expr_to_lua(expr: &Expr) -> String {
    let mut out = String::new();
    push_expr(&mut out, expr);
    out
}

pub fn type_to_lua(ty: &TypeExpr) -> String {
    let mut out = String::new();
    push_type(&mut out, ty);
    out
}

pub fn externs_to_lua(items: &[Item]) -> String {
    let mut out = String::new();
    push_items(&mut out, items);
    out
}

fn push_visibility(out: &mut String, vis: &Visibility) {
    out.push_str(match vis {
        Visibility::Private => "\"private\"",
        Visibility::Public => "\"public\"",
    });
}

fn push_quoted(out: &mut String, s: &str) {
    out.push('"');
    for ch in s.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c => out.push(c),
        }
    }
    out.push('"');
}

fn push_attr_arg(out: &mut String, arg: &AttrArg) {
    match arg {
        AttrArg::Ident(v) => {
            out.push_str("{ tag = \"ident\", value = ");
            push_quoted(out, v);
            out.push_str(" }");
        }
        AttrArg::Number(v) => {
            out.push_str("{ tag = \"number\", value = ");
            push_quoted(out, v);
            out.push_str(" }");
        }
        AttrArg::String(v) => {
            out.push_str("{ tag = \"string\", value = ");
            push_quoted(out, v);
            out.push_str(" }");
        }
    }
}

fn push_attribute(out: &mut String, attr: &Attribute) {
    out.push_str("{ name = ");
    push_quoted(out, &attr.name);
    out.push_str(", args = ");
    push_list(out, &attr.args, push_attr_arg);
    out.push_str(" }");
}

fn push_path(out: &mut String, path: &Path) {
    out.push_str("{ tag = \"path\", segments = ");
    push_list(out, &path.segments, |out, s| push_quoted(out, s));
    out.push_str(" }");
}

fn push_type(out: &mut String, ty: &TypeExpr) {
    match ty {
        TypeExpr::Path(path) => push_path(out, path),
        TypeExpr::Pointer { inner, .. } => {
            out.push_str("{ tag = \"pointer\", inner = ");
            push_type(out, inner);
            out.push_str(" }");
        }
        TypeExpr::Array { len, elem, .. } => {
            out.push_str("{ tag = \"array\", len = ");
            push_expr(out, len);
            out.push_str(", elem = ");
            push_type(out, elem);
            out.push_str(" }");
        }
        TypeExpr::Slice { elem, .. } => {
            out.push_str("{ tag = \"slice\", elem = ");
            push_type(out, elem);
            out.push_str(" }");
        }
        TypeExpr::Func { params, result, .. } => {
            out.push_str("{ tag = \"func_type\", params = ");
            push_list(out, params, push_type);
            out.push_str(", result = ");
            if let Some(result) = result {
                push_type(out, result);
            } else {
                out.push_str("nil");
            }
            out.push_str(" }");
        }
        TypeExpr::Splice { source, .. } => {
            out.push_str("{ tag = \"splice\", source = ");
            push_quoted(out, source);
            out.push_str(" }");
        }
        TypeExpr::Group { inner, .. } => push_type(out, inner),
    }
}

fn push_param(out: &mut String, param: &Param) {
    out.push_str("{ name = ");
    push_quoted(out, &param.name);
    out.push_str(", ty = ");
    push_type(out, &param.ty);
    out.push_str(" }");
}

fn push_func_name(out: &mut String, name: &FuncName) {
    match name {
        FuncName::Named(name) => {
            out.push_str("{ tag = \"named\", name = ");
            push_quoted(out, name);
            out.push_str(" }");
        }
        FuncName::Method { target, method } => {
            out.push_str("{ tag = \"method\", target = ");
            push_path(out, target);
            out.push_str(", method = ");
            push_quoted(out, method);
            out.push_str(" }");
        }
        FuncName::Anonymous => {
            out.push_str("{ tag = \"anonymous\" }");
        }
    }
}

fn push_func_sig(out: &mut String, sig: &FuncSig) {
    out.push_str("{ name = ");
    push_func_name(out, &sig.name);
    out.push_str(", params = ");
    push_list(out, &sig.params, push_param);
    out.push_str(", result = ");
    if let Some(result) = &sig.result {
        push_type(out, result);
    } else {
        out.push_str("nil");
    }
    out.push_str(" }");
}

fn push_field_decl(out: &mut String, field: &FieldDecl) {
    out.push_str("{ name = ");
    push_quoted(out, &field.name);
    out.push_str(", ty = ");
    push_type(out, &field.ty);
    out.push_str(" }");
}

fn push_enum_member(out: &mut String, member: &EnumMemberDecl) {
    out.push_str("{ name = ");
    push_quoted(out, &member.name);
    out.push_str(", value = ");
    if let Some(value) = &member.value {
        push_expr(out, value);
    } else {
        out.push_str("nil");
    }
    out.push_str(" }");
}

fn push_tagged_variant(out: &mut String, variant: &TaggedVariantDecl) {
    out.push_str("{ name = ");
    push_quoted(out, &variant.name);
    out.push_str(", fields = ");
    push_list(out, &variant.fields, push_field_decl);
    out.push_str(" }");
}

fn push_block(out: &mut String, block: &Block) {
    out.push_str("{ tag = \"block\", stmts = ");
    push_list(out, &block.stmts, push_stmt);
    out.push_str(" }");
}

fn push_if_stmt_branch(out: &mut String, branch: &IfStmtBranch) {
    out.push_str("{ cond = ");
    push_expr(out, &branch.cond);
    out.push_str(", body = ");
    push_block(out, &branch.body);
    out.push_str(" }");
}

fn push_switch_stmt_case(out: &mut String, case: &SwitchStmtCase) {
    out.push_str("{ value = ");
    push_expr(out, &case.value);
    out.push_str(", body = ");
    push_block(out, &case.body);
    out.push_str(" }");
}

fn push_stmt(out: &mut String, stmt: &Stmt) {
    match stmt {
        Stmt::Let { name, ty, value, .. } => {
            out.push_str("{ tag = \"let\", name = ");
            push_quoted(out, name);
            out.push_str(", ty = ");
            if let Some(ty) = ty {
                push_type(out, ty);
            } else {
                out.push_str("nil");
            }
            out.push_str(", value = ");
            push_expr(out, value);
            out.push_str(" }");
        }
        Stmt::Var { name, ty, value, .. } => {
            out.push_str("{ tag = \"var\", name = ");
            push_quoted(out, name);
            out.push_str(", ty = ");
            if let Some(ty) = ty {
                push_type(out, ty);
            } else {
                out.push_str("nil");
            }
            out.push_str(", value = ");
            push_expr(out, value);
            out.push_str(" }");
        }
        Stmt::Assign { target, value, .. } => {
            out.push_str("{ tag = \"assign\", target = ");
            push_expr(out, target);
            out.push_str(", value = ");
            push_expr(out, value);
            out.push_str(" }");
        }
        Stmt::If(v) => {
            out.push_str("{ tag = \"if\", branches = ");
            push_list(out, &v.branches, push_if_stmt_branch);
            out.push_str(", else_body = ");
            if let Some(block) = &v.else_branch {
                push_block(out, block);
            } else {
                out.push_str("nil");
            }
            out.push_str(" }");
        }
        Stmt::While { cond, body, .. } => {
            out.push_str("{ tag = \"while\", cond = ");
            push_expr(out, cond);
            out.push_str(", body = ");
            push_block(out, body);
            out.push_str(" }");
        }
        Stmt::For(v) => {
            out.push_str("{ tag = \"for\", name = ");
            push_quoted(out, &v.name);
            out.push_str(", start = ");
            push_expr(out, &v.start);
            out.push_str(", finish = ");
            push_expr(out, &v.end);
            out.push_str(", step = ");
            if let Some(step) = &v.step {
                push_expr(out, step);
            } else {
                out.push_str("nil");
            }
            out.push_str(", body = ");
            push_block(out, &v.body);
            out.push_str(" }");
        }
        Stmt::Switch(v) => {
            out.push_str("{ tag = \"switch\", value = ");
            push_expr(out, &v.value);
            out.push_str(", cases = ");
            push_list(out, &v.cases, push_switch_stmt_case);
            out.push_str(", default = ");
            if let Some(default) = &v.default {
                push_block(out, default);
            } else {
                out.push_str("nil");
            }
            out.push_str(" }");
        }
        Stmt::Break { .. } => out.push_str("{ tag = \"break\" }"),
        Stmt::Continue { .. } => out.push_str("{ tag = \"continue\" }"),
        Stmt::Return { value, .. } => {
            out.push_str("{ tag = \"return\", value = ");
            if let Some(value) = value {
                push_expr(out, value);
            } else {
                out.push_str("nil");
            }
            out.push_str(" }");
        }
        Stmt::Memory(v) => match v {
            MemoryStmt::Memcpy { dst, src, len, .. } => {
                out.push_str("{ tag = \"memcpy\", dst = ");
                push_expr(out, dst);
                out.push_str(", src = ");
                push_expr(out, src);
                out.push_str(", len = ");
                push_expr(out, len);
                out.push_str(" }");
            }
            MemoryStmt::Memmove { dst, src, len, .. } => {
                out.push_str("{ tag = \"memmove\", dst = ");
                push_expr(out, dst);
                out.push_str(", src = ");
                push_expr(out, src);
                out.push_str(", len = ");
                push_expr(out, len);
                out.push_str(" }");
            }
            MemoryStmt::Memset { dst, byte, len, .. } => {
                out.push_str("{ tag = \"memset\", dst = ");
                push_expr(out, dst);
                out.push_str(", byte = ");
                push_expr(out, byte);
                out.push_str(", len = ");
                push_expr(out, len);
                out.push_str(" }");
            }
            MemoryStmt::Store { ty, dst, value, .. } => {
                out.push_str("{ tag = \"store\", ty = ");
                push_type(out, ty);
                out.push_str(", dst = ");
                push_expr(out, dst);
                out.push_str(", value = ");
                push_expr(out, value);
                out.push_str(" }");
            }
        },
        Stmt::Expr { expr, .. } => {
            out.push_str("{ tag = \"expr\", expr = ");
            push_expr(out, expr);
            out.push_str(" }");
        }
    }
}

fn push_number(out: &mut String, number: &NumberLit) {
    out.push_str("{ tag = \"number\", raw = ");
    push_quoted(out, &number.raw);
    out.push_str(", kind = ");
    push_quoted(
        out,
        match number.kind {
            NumberKind::Int => "int",
            NumberKind::Float => "float",
        },
    );
    out.push_str(" }");
}

fn push_type_ctor(out: &mut String, ctor: &TypeCtor) {
    match ctor {
        TypeCtor::Path(path) => push_path(out, path),
        TypeCtor::Array { len, elem, .. } => {
            out.push_str("{ tag = \"array_ctor\", len = ");
            push_expr(out, len);
            out.push_str(", elem = ");
            push_type(out, elem);
            out.push_str(" }");
        }
    }
}

fn push_aggregate_field(out: &mut String, field: &AggregateField) {
    match field {
        AggregateField::Named { name, value, .. } => {
            out.push_str("{ tag = \"named\", name = ");
            push_quoted(out, name);
            out.push_str(", value = ");
            push_expr(out, value);
            out.push_str(" }");
        }
        AggregateField::Positional { value, .. } => {
            out.push_str("{ tag = \"positional\", value = ");
            push_expr(out, value);
            out.push_str(" }");
        }
    }
}

fn push_if_expr_branch(out: &mut String, branch: &IfExprBranch) {
    out.push_str("{ cond = ");
    push_expr(out, &branch.cond);
    out.push_str(", value = ");
    push_expr(out, &branch.value);
    out.push_str(" }");
}

fn push_switch_expr_case(out: &mut String, case: &SwitchExprCase) {
    out.push_str("{ value = ");
    push_expr(out, &case.value);
    out.push_str(", body = ");
    push_expr(out, &case.body);
    out.push_str(" }");
}

fn push_expr(out: &mut String, expr: &Expr) {
    match &expr.kind {
        ExprKind::Path(path) => push_path(out, path),
        ExprKind::Number(number) => push_number(out, number),
        ExprKind::Bool(v) => {
            out.push_str("{ tag = \"bool\", value = ");
            out.push_str(if *v { "true" } else { "false" });
            out.push_str(" }");
        }
        ExprKind::Nil => out.push_str("{ tag = \"nil\" }"),
        ExprKind::String(v) => {
            out.push_str("{ tag = \"string\", value = ");
            push_quoted(out, v);
            out.push_str(" }");
        }
        ExprKind::Aggregate { ctor, fields } => {
            out.push_str("{ tag = \"aggregate\", ctor = ");
            push_type_ctor(out, ctor);
            out.push_str(", fields = ");
            push_list(out, fields, push_aggregate_field);
            out.push_str(" }");
        }
        ExprKind::Cast { kind, ty, value } => {
            out.push_str("{ tag = ");
            push_quoted(
                out,
                match kind {
                    CastKind::Cast => "cast",
                    CastKind::Trunc => "trunc",
                    CastKind::Zext => "zext",
                    CastKind::Sext => "sext",
                    CastKind::Bitcast => "bitcast",
                },
            );
            out.push_str(", ty = ");
            push_type(out, ty);
            out.push_str(", value = ");
            push_expr(out, value);
            out.push_str(" }");
        }
        ExprKind::SizeOf(ty) => {
            out.push_str("{ tag = \"sizeof\", ty = ");
            push_type(out, ty);
            out.push_str(" }");
        }
        ExprKind::AlignOf(ty) => {
            out.push_str("{ tag = \"alignof\", ty = ");
            push_type(out, ty);
            out.push_str(" }");
        }
        ExprKind::OffsetOf { ty, field } => {
            out.push_str("{ tag = \"offsetof\", ty = ");
            push_type(out, ty);
            out.push_str(", field = ");
            push_quoted(out, field);
            out.push_str(" }");
        }
        ExprKind::Load { ty, ptr } => {
            out.push_str("{ tag = \"load\", ty = ");
            push_type(out, ty);
            out.push_str(", ptr = ");
            push_expr(out, ptr);
            out.push_str(" }");
        }
        ExprKind::Memcmp { a, b, len } => {
            out.push_str("{ tag = \"memcmp\", a = ");
            push_expr(out, a);
            out.push_str(", b = ");
            push_expr(out, b);
            out.push_str(", len = ");
            push_expr(out, len);
            out.push_str(" }");
        }
        ExprKind::Block(block) => push_block(out, block),
        ExprKind::If(v) => {
            out.push_str("{ tag = \"if\", branches = ");
            push_list(out, &v.branches, push_if_expr_branch);
            out.push_str(", else_value = ");
            push_expr(out, &v.else_branch);
            out.push_str(" }");
        }
        ExprKind::Switch(v) => {
            out.push_str("{ tag = \"switch\", value = ");
            push_expr(out, &v.value);
            out.push_str(", cases = ");
            push_list(out, &v.cases, push_switch_expr_case);
            out.push_str(", default = ");
            push_expr(out, &v.default);
            out.push_str(" }");
        }
        ExprKind::Unary { op, expr } => {
            out.push_str("{ tag = \"unary\", op = ");
            push_quoted(
                out,
                match op {
                    UnaryOp::Neg => "neg",
                    UnaryOp::Not => "not",
                    UnaryOp::BitNot => "bnot",
                    UnaryOp::AddrOf => "addr_of",
                    UnaryOp::Deref => "deref",
                },
            );
            out.push_str(", expr = ");
            push_expr(out, expr);
            out.push_str(" }");
        }
        ExprKind::Binary { op, lhs, rhs } => {
            out.push_str("{ tag = \"binary\", op = ");
            push_quoted(
                out,
                match op {
                    BinaryOp::Add => "add",
                    BinaryOp::Sub => "sub",
                    BinaryOp::Mul => "mul",
                    BinaryOp::Div => "div",
                    BinaryOp::Rem => "rem",
                    BinaryOp::Eq => "eq",
                    BinaryOp::Ne => "ne",
                    BinaryOp::Lt => "lt",
                    BinaryOp::Le => "le",
                    BinaryOp::Gt => "gt",
                    BinaryOp::Ge => "ge",
                    BinaryOp::And => "and",
                    BinaryOp::Or => "or",
                    BinaryOp::BitAnd => "band",
                    BinaryOp::BitOr => "bor",
                    BinaryOp::BitXor => "bxor",
                    BinaryOp::Shl => "shl",
                    BinaryOp::Shr => "shr",
                    BinaryOp::ShrU => "shr_u",
                },
            );
            out.push_str(", lhs = ");
            push_expr(out, lhs);
            out.push_str(", rhs = ");
            push_expr(out, rhs);
            out.push_str(" }");
        }
        ExprKind::Field { base, name } => {
            out.push_str("{ tag = \"field\", base = ");
            push_expr(out, base);
            out.push_str(", name = ");
            push_quoted(out, name);
            out.push_str(" }");
        }
        ExprKind::Index { base, index } => {
            out.push_str("{ tag = \"index\", base = ");
            push_expr(out, base);
            out.push_str(", index = ");
            push_expr(out, index);
            out.push_str(" }");
        }
        ExprKind::Call { callee, args } => {
            out.push_str("{ tag = \"call\", callee = ");
            push_expr(out, callee);
            out.push_str(", args = ");
            push_list(out, args, push_expr);
            out.push_str(" }");
        }
        ExprKind::MethodCall {
            receiver,
            method,
            args,
        } => {
            out.push_str("{ tag = \"method_call\", receiver = ");
            push_expr(out, receiver);
            out.push_str(", method = ");
            push_quoted(out, method);
            out.push_str(", args = ");
            push_list(out, args, push_expr);
            out.push_str(" }");
        }
        ExprKind::Splice(source) => {
            out.push_str("{ tag = \"splice\", source = ");
            push_quoted(out, source);
            out.push_str(" }");
        }
        ExprKind::Hole { name, ty } => {
            out.push_str("{ tag = \"hole\", name = ");
            push_quoted(out, name);
            out.push_str(", ty = ");
            push_type(out, ty);
            out.push_str(" }");
        }
        ExprKind::AnonymousFunc(func) => {
            out.push_str("{ tag = \"anonymous_func\", func = ");
            push_func_decl(out, func, "func");
            out.push_str(" }");
        }
    }
}

fn push_func_decl(out: &mut String, func: &FuncDecl, tag: &str) {
    out.push_str("{ tag = ");
    push_quoted(out, tag);
    out.push_str(", sig = ");
    push_func_sig(out, &func.sig);
    out.push_str(", body = ");
    push_block(out, &func.body);
    out.push_str(" }");
}

fn push_item(out: &mut String, item: &Item) {
    match &item.kind {
        ItemKind::Const(v) => {
            out.push_str("{ tag = \"const\", visibility = ");
            push_visibility(out, &item.visibility);
            out.push_str(", attrs = ");
            push_list(out, &item.attributes, push_attribute);
            out.push_str(", name = ");
            push_quoted(out, &v.name);
            out.push_str(", ty = ");
            if let Some(ty) = &v.ty {
                push_type(out, ty);
            } else {
                out.push_str("nil");
            }
            out.push_str(", value = ");
            push_expr(out, &v.value);
            out.push_str(" }");
        }
        ItemKind::TypeAlias(v) => {
            out.push_str("{ tag = \"type_alias\", visibility = ");
            push_visibility(out, &item.visibility);
            out.push_str(", attrs = ");
            push_list(out, &item.attributes, push_attribute);
            out.push_str(", name = ");
            push_quoted(out, &v.name);
            out.push_str(", ty = ");
            push_type(out, &v.ty);
            out.push_str(" }");
        }
        ItemKind::Struct(v) => {
            out.push_str("{ tag = \"struct\", visibility = ");
            push_visibility(out, &item.visibility);
            out.push_str(", attrs = ");
            push_list(out, &item.attributes, push_attribute);
            out.push_str(", name = ");
            push_quoted(out, &v.name);
            out.push_str(", fields = ");
            push_list(out, &v.fields, push_field_decl);
            out.push_str(" }");
        }
        ItemKind::Union(v) => {
            out.push_str("{ tag = \"union\", visibility = ");
            push_visibility(out, &item.visibility);
            out.push_str(", attrs = ");
            push_list(out, &item.attributes, push_attribute);
            out.push_str(", name = ");
            push_quoted(out, &v.name);
            out.push_str(", fields = ");
            push_list(out, &v.fields, push_field_decl);
            out.push_str(" }");
        }
        ItemKind::TaggedUnion(v) => {
            out.push_str("{ tag = \"tagged_union\", visibility = ");
            push_visibility(out, &item.visibility);
            out.push_str(", attrs = ");
            push_list(out, &item.attributes, push_attribute);
            out.push_str(", name = ");
            push_quoted(out, &v.name);
            out.push_str(", base_ty = ");
            if let Some(base_ty) = &v.base_ty {
                push_type(out, base_ty);
            } else {
                out.push_str("nil");
            }
            out.push_str(", variants = ");
            push_list(out, &v.variants, push_tagged_variant);
            out.push_str(" }");
        }
        ItemKind::Enum(v) => {
            out.push_str("{ tag = \"enum\", visibility = ");
            push_visibility(out, &item.visibility);
            out.push_str(", attrs = ");
            push_list(out, &item.attributes, push_attribute);
            out.push_str(", name = ");
            push_quoted(out, &v.name);
            out.push_str(", base_ty = ");
            if let Some(base_ty) = &v.base_ty {
                push_type(out, base_ty);
            } else {
                out.push_str("nil");
            }
            out.push_str(", members = ");
            push_list(out, &v.members, push_enum_member);
            out.push_str(" }");
        }
        ItemKind::Opaque(v) => {
            out.push_str("{ tag = \"opaque\", visibility = ");
            push_visibility(out, &item.visibility);
            out.push_str(", attrs = ");
            push_list(out, &item.attributes, push_attribute);
            out.push_str(", name = ");
            push_quoted(out, &v.name);
            out.push_str(" }");
        }
        ItemKind::Slice(v) => {
            out.push_str("{ tag = \"slice_decl\", visibility = ");
            push_visibility(out, &item.visibility);
            out.push_str(", attrs = ");
            push_list(out, &item.attributes, push_attribute);
            out.push_str(", name = ");
            push_quoted(out, &v.name);
            out.push_str(", ty = ");
            push_type(out, &v.ty);
            out.push_str(" }");
        }
        ItemKind::Func(v) => {
            out.push_str("{ visibility = ");
            push_visibility(out, &item.visibility);
            out.push_str(", attrs = ");
            push_list(out, &item.attributes, push_attribute);
            out.push_str(", item = ");
            push_func_decl(out, v, "func");
            out.push_str(" }");
        }
        ItemKind::ExternFunc(v) => {
            out.push_str("{ tag = \"extern_func\", visibility = ");
            push_visibility(out, &item.visibility);
            out.push_str(", attrs = ");
            push_list(out, &item.attributes, push_attribute);
            out.push_str(", name = ");
            push_quoted(out, &v.name);
            out.push_str(", params = ");
            push_list(out, &v.params, push_param);
            out.push_str(", result = ");
            if let Some(result) = &v.result {
                push_type(out, result);
            } else {
                out.push_str("nil");
            }
            out.push_str(" }");
        }
        ItemKind::Impl(v) => {
            out.push_str("{ tag = \"impl\", visibility = ");
            push_visibility(out, &item.visibility);
            out.push_str(", attrs = ");
            push_list(out, &item.attributes, push_attribute);
            out.push_str(", target = ");
            push_path(out, &v.target);
            out.push_str(", items = ");
            push_list(out, &v.items, |out, item| {
                out.push_str("{ attrs = ");
                push_list(out, &item.attributes, push_attribute);
                out.push_str(", item = ");
                push_func_decl(out, &item.func, "func");
                out.push_str(" }");
            });
            out.push_str(" }");
        }
        ItemKind::Splice(v) => {
            out.push_str("{ tag = \"splice_item\", visibility = ");
            push_visibility(out, &item.visibility);
            out.push_str(", attrs = ");
            push_list(out, &item.attributes, push_attribute);
            out.push_str(", source = ");
            push_quoted(out, v);
            out.push_str(" }");
        }
    }
}

fn push_items(out: &mut String, items: &[Item]) {
    push_list(out, items, push_item)
}

fn push_list<T>(out: &mut String, items: &[T], push: fn(&mut String, &T)) {
    out.push('{');
    for (i, item) in items.iter().enumerate() {
        if i > 0 {
            out.push_str(", ");
        }
        push(out, item);
    }
    out.push('}');
}
