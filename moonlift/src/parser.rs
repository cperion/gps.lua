use crate::ast::*;
use crate::diag::ParseError;
use crate::lexer::lex;
use crate::source::Span;
use crate::token::{Token, TokenKind};

pub fn parse_code(source: &str) -> Result<Item, ParseError> {
    let tokens = lex(source)?;
    let mut p = Parser::new(source, tokens);
    p.skip_separators();
    let item = p.parse_item()?;
    p.skip_separators();
    p.expect_simple(TokenKind::Eof)?;
    Ok(item)
}

pub fn parse_module(source: &str) -> Result<ModuleAst, ParseError> {
    let tokens = lex(source)?;
    let mut p = Parser::new(source, tokens);
    p.skip_separators();
    let start = p.current_span().start;
    let mut items = Vec::new();
    while !p.check_simple(&TokenKind::Eof) {
        items.push(p.parse_item()?);
        p.skip_separators();
    }
    let end = p.current_span().end;
    Ok(ModuleAst {
        items,
        span: Span::new(start, end),
    })
}

pub fn parse_expr(source: &str) -> Result<Expr, ParseError> {
    let tokens = lex(source)?;
    let mut p = Parser::new(source, tokens);
    p.skip_separators();
    let expr = p.parse_expr()?;
    p.skip_separators();
    p.expect_simple(TokenKind::Eof)?;
    Ok(expr)
}

pub fn parse_type(source: &str) -> Result<TypeExpr, ParseError> {
    let tokens = lex(source)?;
    let mut p = Parser::new(source, tokens);
    p.skip_separators();
    let ty = p.parse_type_expr()?;
    p.skip_separators();
    p.expect_simple(TokenKind::Eof)?;
    Ok(ty)
}

pub fn parse_externs(source: &str) -> Result<Vec<Item>, ParseError> {
    let tokens = lex(source)?;
    let mut p = Parser::new(source, tokens);
    p.skip_separators();
    let mut items = Vec::new();
    while !p.check_simple(&TokenKind::Eof) {
        let item = p.parse_item()?;
        match item.kind {
            ItemKind::ExternFunc(_) => items.push(item),
            _ => {
                return Err(ParseError::new(
                    "extern fragment expects only extern func declarations",
                    item.span,
                ))
            }
        }
        p.skip_separators();
    }
    Ok(items)
}

pub fn parse_code_dump(source: &str) -> Result<String, ParseError> {
    Ok(format!("{:#?}", parse_code(source)?))
}

pub fn parse_module_dump(source: &str) -> Result<String, ParseError> {
    Ok(format!("{:#?}", parse_module(source)?))
}

pub fn parse_expr_dump(source: &str) -> Result<String, ParseError> {
    Ok(format!("{:#?}", parse_expr(source)?))
}

pub fn parse_type_dump(source: &str) -> Result<String, ParseError> {
    Ok(format!("{:#?}", parse_type(source)?))
}

pub fn parse_externs_dump(source: &str) -> Result<String, ParseError> {
    Ok(format!("{:#?}", parse_externs(source)?))
}

struct Parser<'a> {
    source: &'a str,
    tokens: Vec<Token>,
    index: usize,
}

impl<'a> Parser<'a> {
    fn new(source: &'a str, tokens: Vec<Token>) -> Self {
        Self {
            source,
            tokens,
            index: 0,
        }
    }

    fn current(&self) -> &Token {
        &self.tokens[self.index]
    }

    fn current_span(&self) -> Span {
        self.current().span
    }

    fn previous_span(&self) -> Span {
        if self.index == 0 {
            Span::new(0, 0)
        } else {
            self.tokens[self.index - 1].span
        }
    }

    fn bump(&mut self) -> Token {
        let tok = self.tokens[self.index].clone();
        if !matches!(tok.kind, TokenKind::Eof) {
            self.index += 1;
        }
        tok
    }

    fn check_simple(&self, kind: &TokenKind) -> bool {
        self.current().kind.same_variant(kind)
    }

    fn eat_simple(&mut self, kind: TokenKind) -> bool {
        if self.check_simple(&kind) {
            self.bump();
            true
        } else {
            false
        }
    }

    fn expect_simple(&mut self, kind: TokenKind) -> Result<Token, ParseError> {
        if self.check_simple(&kind) {
            Ok(self.bump())
        } else {
            Err(ParseError::new(
                format!("expected {:?}", kind),
                self.current_span(),
            ))
        }
    }

    fn skip_separators(&mut self) {
        while matches!(self.current().kind, TokenKind::Newline | TokenKind::Semicolon) {
            self.bump();
        }
    }

    fn expect_ident(&mut self) -> Result<(String, Span), ParseError> {
        match &self.current().kind {
            TokenKind::Ident(name) => {
                let span = self.current().span;
                let out = name.clone();
                self.bump();
                Ok((out, span))
            }
            _ => Err(ParseError::new("expected identifier", self.current_span())),
        }
    }

    fn expect_decl_name(&mut self) -> Result<(String, Span), ParseError> {
        match &self.current().kind {
            TokenKind::Ident(name) => {
                let span = self.current().span;
                let out = name.clone();
                self.bump();
                Ok((out, span))
            }
            TokenKind::KwLoad
            | TokenKind::KwStore
            | TokenKind::KwMemcpy
            | TokenKind::KwMemmove
            | TokenKind::KwMemset
            | TokenKind::KwMemcmp
            | TokenKind::KwCast
            | TokenKind::KwTrunc
            | TokenKind::KwZext
            | TokenKind::KwSext
            | TokenKind::KwBitcast
            | TokenKind::KwSizeof
            | TokenKind::KwAlignof
            | TokenKind::KwOffsetof => {
                let span = self.current().span;
                let out = self.token_text(self.current()).to_string();
                self.bump();
                Ok((out, span))
            }
            _ => Err(ParseError::new("expected identifier", self.current_span())),
        }
    }

    fn parse_attr_arg(&mut self) -> Result<AttrArg, ParseError> {
        match &self.current().kind {
            TokenKind::Ident(v) => {
                let out = AttrArg::Ident(v.clone());
                self.bump();
                Ok(out)
            }
            TokenKind::Number(v) => {
                let out = AttrArg::Number(v.clone());
                self.bump();
                Ok(out)
            }
            TokenKind::String(v) => {
                let out = AttrArg::String(v.clone());
                self.bump();
                Ok(out)
            }
            _ => Err(ParseError::new(
                "expected attribute argument",
                self.current_span(),
            )),
        }
    }

    fn parse_attributes(&mut self) -> Result<Vec<Attribute>, ParseError> {
        let mut out = Vec::new();
        loop {
            if !self.eat_simple(TokenKind::At) {
                break;
            }
            let start = self.previous_span().start;
            let (name, _) = self.expect_ident()?;
            let mut args = Vec::new();
            if self.eat_simple(TokenKind::LParen) {
                if !self.check_simple(&TokenKind::RParen) {
                    loop {
                        args.push(self.parse_attr_arg()?);
                        if !self.eat_simple(TokenKind::Comma) {
                            break;
                        }
                    }
                }
                self.expect_simple(TokenKind::RParen)?;
            }
            let end = self.previous_span().end;
            out.push(Attribute {
                name,
                args,
                span: Span::new(start, end),
            });
            self.skip_separators();
        }
        Ok(out)
    }

    fn parse_visibility(&mut self) -> Visibility {
        if self.eat_simple(TokenKind::KwPub) {
            Visibility::Public
        } else {
            Visibility::Private
        }
    }

    fn parse_path(&mut self) -> Result<Path, ParseError> {
        let (first, first_span) = self.expect_ident()?;
        let start = first_span.start;
        let mut segments = vec![first];
        let mut end = first_span.end;
        while self.eat_simple(TokenKind::Dot) {
            let (seg, span) = self.expect_ident()?;
            segments.push(seg);
            end = span.end;
        }
        Ok(Path {
            segments,
            span: Span::new(start, end),
        })
    }

    fn parse_item(&mut self) -> Result<Item, ParseError> {
        let start = self.current_span().start;
        let visibility = self.parse_visibility();
        self.skip_separators();
        let attributes = self.parse_attributes()?;
        let kind = match &self.current().kind {
            TokenKind::KwConst => ItemKind::Const(self.parse_const_decl()?),
            TokenKind::KwType => ItemKind::TypeAlias(self.parse_type_alias_decl()?),
            TokenKind::KwStruct => ItemKind::Struct(self.parse_struct_decl()?),
            TokenKind::KwUnion => ItemKind::Union(self.parse_union_decl()?),
            TokenKind::KwTagged => ItemKind::TaggedUnion(self.parse_tagged_union_decl()?),
            TokenKind::KwEnum => ItemKind::Enum(self.parse_enum_decl()?),
            TokenKind::KwOpaque => ItemKind::Opaque(self.parse_opaque_decl()?),
            TokenKind::KwSlice => ItemKind::Slice(self.parse_slice_decl()?),
            TokenKind::KwFunc => ItemKind::Func(self.parse_func_decl()?),
            TokenKind::KwExtern => ItemKind::ExternFunc(self.parse_extern_func_decl()?),
            TokenKind::KwImpl => ItemKind::Impl(self.parse_impl_decl()?),
            TokenKind::Splice(s) => {
                let src = s.clone();
                self.bump();
                ItemKind::Splice(src)
            }
            _ => {
                return Err(ParseError::new(
                    "expected top-level item",
                    self.current_span(),
                ))
            }
        };
        let end = self.previous_span().end;
        Ok(Item {
            visibility,
            attributes,
            kind,
            span: Span::new(start, end),
        })
    }

    fn parse_const_decl(&mut self) -> Result<ConstDecl, ParseError> {
        let start = self.expect_simple(TokenKind::KwConst)?.span.start;
        let (name, _) = self.expect_ident()?;
        let ty = if self.eat_simple(TokenKind::Colon) {
            Some(self.parse_type_expr()?)
        } else {
            None
        };
        self.expect_simple(TokenKind::Assign)?;
        let value = self.parse_expr()?;
        Ok(ConstDecl {
            name,
            ty,
            span: Span::new(start, value.span.end),
            value,
        })
    }

    fn parse_type_alias_decl(&mut self) -> Result<TypeAliasDecl, ParseError> {
        let start = self.expect_simple(TokenKind::KwType)?.span.start;
        let (name, _) = self.expect_ident()?;
        self.expect_simple(TokenKind::Assign)?;
        let ty = self.parse_type_expr()?;
        Ok(TypeAliasDecl {
            name,
            span: Span::new(start, ty.span().end),
            ty,
        })
    }

    fn parse_field_decl(&mut self) -> Result<FieldDecl, ParseError> {
        let (name, span) = self.expect_ident()?;
        self.expect_simple(TokenKind::Colon)?;
        let ty = self.parse_type_expr()?;
        Ok(FieldDecl {
            name,
            span: Span::new(span.start, ty.span().end),
            ty,
        })
    }

    fn parse_named_field_block_until_end(&mut self) -> Result<Vec<FieldDecl>, ParseError> {
        self.skip_separators();
        let mut fields = Vec::new();
        while !self.check_simple(&TokenKind::KwEnd) && !self.check_simple(&TokenKind::Eof) {
            fields.push(self.parse_field_decl()?);
            self.skip_separators();
        }
        self.expect_simple(TokenKind::KwEnd)?;
        Ok(fields)
    }

    fn next_non_separator_starts_field_decl(&self) -> bool {
        let mut i = self.index;
        while i < self.tokens.len()
            && matches!(self.tokens[i].kind, TokenKind::Newline | TokenKind::Semicolon)
        {
            i += 1;
        }
        matches!(
            (self.tokens.get(i), self.tokens.get(i + 1)),
            (
                Some(Token {
                    kind: TokenKind::Ident(_),
                    ..
                }),
                Some(Token {
                    kind: TokenKind::Colon,
                    ..
                })
            )
        )
    }

    fn parse_struct_decl(&mut self) -> Result<StructDecl, ParseError> {
        let start = self.expect_simple(TokenKind::KwStruct)?.span.start;
        let (name, _) = self.expect_ident()?;
        let fields = self.parse_named_field_block_until_end()?;
        Ok(StructDecl {
            name,
            fields,
            span: Span::new(start, self.previous_span().end),
        })
    }

    fn parse_union_decl(&mut self) -> Result<UnionDecl, ParseError> {
        let start = self.expect_simple(TokenKind::KwUnion)?.span.start;
        let (name, _) = self.expect_ident()?;
        let fields = self.parse_named_field_block_until_end()?;
        Ok(UnionDecl {
            name,
            fields,
            span: Span::new(start, self.previous_span().end),
        })
    }

    fn parse_tagged_union_decl(&mut self) -> Result<TaggedUnionDecl, ParseError> {
        let start = self.expect_simple(TokenKind::KwTagged)?.span.start;
        self.expect_simple(TokenKind::KwUnion)?;
        let (name, _) = self.expect_ident()?;
        let base_ty = if self.eat_simple(TokenKind::Colon) {
            Some(self.parse_type_expr()?)
        } else {
            None
        };
        self.skip_separators();
        let mut variants = Vec::new();
        while !self.check_simple(&TokenKind::KwEnd) && !self.check_simple(&TokenKind::Eof) {
            let (vname, vspan) = self.expect_ident()?;
            let has_fields = self.next_non_separator_starts_field_decl();
            let fields = if has_fields {
                self.parse_named_field_block_until_end()?
            } else {
                Vec::new()
            };
            let vend = if has_fields { self.previous_span().end } else { vspan.end };
            variants.push(TaggedVariantDecl {
                name: vname,
                fields,
                span: Span::new(vspan.start, vend),
            });
            self.skip_separators();
        }
        self.expect_simple(TokenKind::KwEnd)?;
        Ok(TaggedUnionDecl {
            name,
            base_ty,
            variants,
            span: Span::new(start, self.previous_span().end),
        })
    }

    fn parse_enum_decl(&mut self) -> Result<EnumDecl, ParseError> {
        let start = self.expect_simple(TokenKind::KwEnum)?.span.start;
        let (name, _) = self.expect_ident()?;
        let base_ty = if self.eat_simple(TokenKind::Colon) {
            Some(self.parse_type_expr()?)
        } else {
            None
        };
        self.skip_separators();
        let mut members = Vec::new();
        while !self.check_simple(&TokenKind::KwEnd) && !self.check_simple(&TokenKind::Eof) {
            let (mname, span) = self.expect_ident()?;
            let value = if self.eat_simple(TokenKind::Assign) {
                Some(self.parse_expr()?)
            } else {
                None
            };
            let end = value.as_ref().map(|v| v.span.end).unwrap_or(span.end);
            members.push(EnumMemberDecl {
                name: mname,
                value,
                span: Span::new(span.start, end),
            });
            self.skip_separators();
        }
        self.expect_simple(TokenKind::KwEnd)?;
        Ok(EnumDecl {
            name,
            base_ty,
            members,
            span: Span::new(start, self.previous_span().end),
        })
    }

    fn parse_opaque_decl(&mut self) -> Result<OpaqueDecl, ParseError> {
        let start = self.expect_simple(TokenKind::KwOpaque)?.span.start;
        let (name, span) = self.expect_ident()?;
        Ok(OpaqueDecl {
            name,
            span: Span::new(start, span.end),
        })
    }

    fn parse_slice_decl(&mut self) -> Result<SliceDecl, ParseError> {
        let start = self.expect_simple(TokenKind::KwSlice)?.span.start;
        let (name, _) = self.expect_ident()?;
        self.expect_simple(TokenKind::Assign)?;
        let ty = self.parse_type_expr()?;
        Ok(SliceDecl {
            name,
            span: Span::new(start, ty.span().end),
            ty,
        })
    }

    fn parse_param_list(&mut self) -> Result<Vec<Param>, ParseError> {
        let mut params = Vec::new();
        if self.check_simple(&TokenKind::RParen) {
            return Ok(params);
        }
        loop {
            let (name, span) = self.expect_ident()?;
            self.expect_simple(TokenKind::Colon)?;
            let ty = self.parse_type_expr()?;
            params.push(Param {
                name,
                span: Span::new(span.start, ty.span().end),
                ty,
            });
            if !self.eat_simple(TokenKind::Comma) {
                break;
            }
        }
        Ok(params)
    }

    fn parse_result_type_opt(&mut self) -> Result<Option<TypeExpr>, ParseError> {
        if self.eat_simple(TokenKind::Arrow) {
            Ok(Some(self.parse_type_expr()?))
        } else {
            Ok(None)
        }
    }

    fn parse_func_signature(&mut self) -> Result<FuncSig, ParseError> {
        let start = self.expect_simple(TokenKind::KwFunc)?.span.start;
        let name = if self.check_simple(&TokenKind::LParen) {
            FuncName::Anonymous
        } else {
            let path = self.parse_path()?;
            if self.eat_simple(TokenKind::Colon) {
                let (method, _) = self.expect_ident()?;
                FuncName::Method {
                    target: path,
                    method,
                }
            } else if path.segments.len() == 1 {
                FuncName::Named(path.segments[0].clone())
            } else {
                return Err(ParseError::new(
                    "qualified function names are only valid in method declarations",
                    path.span,
                ));
            }
        };
        self.expect_simple(TokenKind::LParen)?;
        let params = self.parse_param_list()?;
        self.expect_simple(TokenKind::RParen)?;
        let result = self.parse_result_type_opt()?;
        let end = result
            .as_ref()
            .map(|t| t.span().end)
            .unwrap_or_else(|| self.previous_span().end);
        Ok(FuncSig {
            name,
            params,
            result,
            span: Span::new(start, end),
        })
    }

    fn parse_stmt_block_until<F>(&mut self, stop: F) -> Result<Block, ParseError>
    where
        F: Fn(&TokenKind) -> bool,
    {
        self.skip_separators();
        let start = self.current_span().start;
        let mut stmts = Vec::new();
        while !stop(&self.current().kind) && !self.check_simple(&TokenKind::Eof) {
            stmts.push(self.parse_stmt()?);
            self.skip_separators();
        }
        let end = if stmts.is_empty() {
            start
        } else {
            stmts.last().map(stmt_span_end).unwrap_or(start)
        };
        Ok(Block {
            stmts,
            span: Span::new(start, end),
        })
    }

    fn parse_func_decl(&mut self) -> Result<FuncDecl, ParseError> {
        let sig = self.parse_func_signature()?;
        let body = self.parse_stmt_block_until(|k| matches!(k, TokenKind::KwEnd))?;
        self.expect_simple(TokenKind::KwEnd)?;
        Ok(FuncDecl {
            span: Span::new(sig.span.start, self.previous_span().end),
            sig,
            body,
        })
    }

    fn parse_extern_func_decl(&mut self) -> Result<ExternFuncDecl, ParseError> {
        let start = self.expect_simple(TokenKind::KwExtern)?.span.start;
        self.expect_simple(TokenKind::KwFunc)?;
        let (name, _) = self.expect_decl_name()?;
        self.expect_simple(TokenKind::LParen)?;
        let params = self.parse_param_list()?;
        self.expect_simple(TokenKind::RParen)?;
        let result = self.parse_result_type_opt()?;
        let end = result
            .as_ref()
            .map(|t| t.span().end)
            .unwrap_or_else(|| self.previous_span().end);
        Ok(ExternFuncDecl {
            name,
            params,
            result,
            span: Span::new(start, end),
        })
    }

    fn parse_impl_decl(&mut self) -> Result<ImplDecl, ParseError> {
        let start = self.expect_simple(TokenKind::KwImpl)?.span.start;
        let target = self.parse_path()?;
        self.skip_separators();
        let mut items = Vec::new();
        while !self.check_simple(&TokenKind::KwEnd) && !self.check_simple(&TokenKind::Eof) {
            let attrs = self.parse_attributes()?;
            let func = self.parse_func_decl()?;
            let span = Span::new(
                attrs.first().map(|a| a.span.start).unwrap_or(func.span.start),
                func.span.end,
            );
            items.push(ImplItem {
                attributes: attrs,
                func,
                span,
            });
            self.skip_separators();
        }
        self.expect_simple(TokenKind::KwEnd)?;
        Ok(ImplDecl {
            target,
            items,
            span: Span::new(start, self.previous_span().end),
        })
    }

    fn parse_type_expr(&mut self) -> Result<TypeExpr, ParseError> {
        if self.eat_simple(TokenKind::KwFunc) {
            let start = self.previous_span().start;
            self.expect_simple(TokenKind::LParen)?;
            let mut params = Vec::new();
            if !self.check_simple(&TokenKind::RParen) {
                loop {
                    params.push(self.parse_type_expr()?);
                    if !self.eat_simple(TokenKind::Comma) {
                        break;
                    }
                }
            }
            self.expect_simple(TokenKind::RParen)?;
            let result = if self.eat_simple(TokenKind::Arrow) {
                Some(Box::new(self.parse_type_expr()?))
            } else {
                None
            };
            let end = result
                .as_ref()
                .map(|t| t.span().end)
                .unwrap_or_else(|| self.previous_span().end);
            return Ok(TypeExpr::Func {
                params,
                result,
                span: Span::new(start, end),
            });
        }
        self.parse_type_prefix()
    }

    fn parse_type_prefix(&mut self) -> Result<TypeExpr, ParseError> {
        match &self.current().kind {
            TokenKind::Amp => {
                let start = self.bump().span.start;
                let inner = self.parse_type_prefix()?;
                Ok(TypeExpr::Pointer {
                    span: Span::new(start, inner.span().end),
                    inner: Box::new(inner),
                })
            }
            TokenKind::LBracket => {
                let start = self.bump().span.start;
                if self.eat_simple(TokenKind::RBracket) {
                    let elem = self.parse_type_expr()?;
                    Ok(TypeExpr::Slice {
                        span: Span::new(start, elem.span().end),
                        elem: Box::new(elem),
                    })
                } else {
                    let len = self.parse_expr()?;
                    self.expect_simple(TokenKind::RBracket)?;
                    let elem = self.parse_type_expr()?;
                    Ok(TypeExpr::Array {
                        span: Span::new(start, elem.span().end),
                        len: Box::new(len),
                        elem: Box::new(elem),
                    })
                }
            }
            TokenKind::Splice(src) => {
                let span = self.current_span();
                let source = src.clone();
                self.bump();
                Ok(TypeExpr::Splice { source, span })
            }
            TokenKind::LParen => {
                let start = self.bump().span.start;
                let inner = self.parse_type_expr()?;
                let end = self.expect_simple(TokenKind::RParen)?.span.end;
                Ok(TypeExpr::Group {
                    inner: Box::new(inner),
                    span: Span::new(start, end),
                })
            }
            TokenKind::Ident(_) => {
                let path = self.parse_path()?;
                Ok(TypeExpr::Path(path))
            }
            _ => {
                if let Some(path) = self.parse_scalar_type_path() {
                    Ok(TypeExpr::Path(path))
                } else {
                    Err(ParseError::new("expected type", self.current_span()))
                }
            }
        }
    }

    fn parse_scalar_type_path(&mut self) -> Option<Path> {
        let text = self.token_text(self.current()).to_string();
        if matches!(
            text.as_str(),
            "void" | "bool" | "i8" | "i16" | "i32" | "i64" | "u8" | "u16" | "u32"
                | "u64" | "isize" | "usize" | "f32" | "f64" | "byte"
        ) {
            let span = self.current_span();
            self.bump();
            Some(Path {
                segments: vec![text],
                span,
            })
        } else {
            None
        }
    }

    fn token_text<'b>(&'b self, tok: &'b Token) -> &'b str {
        &self.source[tok.span.start..tok.span.end]
    }

    fn parse_stmt(&mut self) -> Result<Stmt, ParseError> {
        self.skip_separators();
        match self.current().kind {
            TokenKind::KwLet => self.parse_let_stmt(),
            TokenKind::KwVar => self.parse_var_stmt(),
            TokenKind::KwIf => self.parse_if_stmt(),
            TokenKind::KwWhile => self.parse_while_stmt(),
            TokenKind::KwFor => self.parse_for_stmt(),
            TokenKind::KwSwitch => self.parse_switch_stmt(),
            TokenKind::KwBreak => {
                let span = self.bump().span;
                Ok(Stmt::Break { span })
            }
            TokenKind::KwContinue => {
                let span = self.bump().span;
                Ok(Stmt::Continue { span })
            }
            TokenKind::KwReturn => self.parse_return_stmt(),
            TokenKind::KwMemcpy | TokenKind::KwMemmove | TokenKind::KwMemset | TokenKind::KwStore => {
                self.parse_memory_stmt()
            }
            _ => self.parse_assign_or_expr_stmt(),
        }
    }

    fn parse_let_stmt(&mut self) -> Result<Stmt, ParseError> {
        let start = self.expect_simple(TokenKind::KwLet)?.span.start;
        let (name, _) = self.expect_ident()?;
        let ty = if self.eat_simple(TokenKind::Colon) {
            Some(self.parse_type_expr()?)
        } else {
            None
        };
        self.expect_simple(TokenKind::Assign)?;
        let value = self.parse_expr()?;
        Ok(Stmt::Let {
            name,
            ty,
            span: Span::new(start, value.span.end),
            value,
        })
    }

    fn parse_var_stmt(&mut self) -> Result<Stmt, ParseError> {
        let start = self.expect_simple(TokenKind::KwVar)?.span.start;
        let (name, _) = self.expect_ident()?;
        let ty = if self.eat_simple(TokenKind::Colon) {
            Some(self.parse_type_expr()?)
        } else {
            None
        };
        self.expect_simple(TokenKind::Assign)?;
        let value = self.parse_expr()?;
        Ok(Stmt::Var {
            name,
            ty,
            span: Span::new(start, value.span.end),
            value,
        })
    }

    fn parse_if_stmt(&mut self) -> Result<Stmt, ParseError> {
        let start = self.expect_simple(TokenKind::KwIf)?.span.start;
        let cond = self.parse_expr()?;
        self.expect_simple(TokenKind::KwThen)?;
        let then_block = self.parse_stmt_block_until(|k| {
            matches!(k, TokenKind::KwElseIf | TokenKind::KwElse | TokenKind::KwEnd)
        })?;
        let mut branches = vec![IfStmtBranch {
            span: Span::new(cond.span.start, then_block.span.end),
            cond,
            body: then_block,
        }];
        while self.eat_simple(TokenKind::KwElseIf) {
            let cond = self.parse_expr()?;
            self.expect_simple(TokenKind::KwThen)?;
            let body = self.parse_stmt_block_until(|k| {
                matches!(k, TokenKind::KwElseIf | TokenKind::KwElse | TokenKind::KwEnd)
            })?;
            let span = Span::new(cond.span.start, body.span.end);
            branches.push(IfStmtBranch { cond, body, span });
        }
        let else_branch = if self.eat_simple(TokenKind::KwElse) {
            Some(self.parse_stmt_block_until(|k| matches!(k, TokenKind::KwEnd))?)
        } else {
            None
        };
        self.expect_simple(TokenKind::KwEnd)?;
        Ok(Stmt::If(IfStmt {
            branches,
            else_branch,
            span: Span::new(start, self.previous_span().end),
        }))
    }

    fn parse_while_stmt(&mut self) -> Result<Stmt, ParseError> {
        let start = self.expect_simple(TokenKind::KwWhile)?.span.start;
        let cond = self.parse_expr()?;
        self.expect_simple(TokenKind::KwDo)?;
        let body = self.parse_stmt_block_until(|k| matches!(k, TokenKind::KwEnd))?;
        self.expect_simple(TokenKind::KwEnd)?;
        Ok(Stmt::While {
            cond,
            span: Span::new(start, self.previous_span().end),
            body,
        })
    }

    fn parse_for_stmt(&mut self) -> Result<Stmt, ParseError> {
        let start = self.expect_simple(TokenKind::KwFor)?.span.start;
        let (name, _) = self.expect_ident()?;
        self.expect_simple(TokenKind::Assign)?;
        let start_expr = self.parse_expr()?;
        self.expect_simple(TokenKind::Comma)?;
        let end_expr = self.parse_expr()?;
        let step = if self.eat_simple(TokenKind::Comma) {
            Some(self.parse_expr()?)
        } else {
            None
        };
        self.expect_simple(TokenKind::KwDo)?;
        let body = self.parse_stmt_block_until(|k| matches!(k, TokenKind::KwEnd))?;
        self.expect_simple(TokenKind::KwEnd)?;
        Ok(Stmt::For(ForStmt {
            name,
            start: start_expr,
            end: end_expr,
            step,
            body,
            span: Span::new(start, self.previous_span().end),
        }))
    }

    fn parse_switch_stmt(&mut self) -> Result<Stmt, ParseError> {
        let start = self.expect_simple(TokenKind::KwSwitch)?.span.start;
        let value = self.parse_expr()?;
        self.expect_simple(TokenKind::KwDo)?;
        self.skip_separators();
        let mut cases = Vec::new();
        let mut default = None;
        while !self.check_simple(&TokenKind::KwEnd) && !self.check_simple(&TokenKind::Eof) {
            if self.eat_simple(TokenKind::KwCase) {
                let case_value = self.parse_expr()?;
                self.expect_simple(TokenKind::KwThen)?;
                let body = self.parse_stmt_block_until(|k| {
                    matches!(k, TokenKind::KwCase | TokenKind::KwDefault | TokenKind::KwEnd)
                })?;
                let span = Span::new(case_value.span.start, body.span.end);
                cases.push(SwitchStmtCase {
                    value: case_value,
                    body,
                    span,
                });
            } else if self.eat_simple(TokenKind::KwDefault) {
                self.expect_simple(TokenKind::KwThen)?;
                default = Some(self.parse_stmt_block_until(|k| matches!(k, TokenKind::KwEnd))?);
            } else {
                return Err(ParseError::new(
                    "expected case, default, or end in switch statement",
                    self.current_span(),
                ));
            }
            self.skip_separators();
        }
        self.expect_simple(TokenKind::KwEnd)?;
        Ok(Stmt::Switch(SwitchStmt {
            value,
            cases,
            default,
            span: Span::new(start, self.previous_span().end),
        }))
    }

    fn parse_return_stmt(&mut self) -> Result<Stmt, ParseError> {
        let start = self.expect_simple(TokenKind::KwReturn)?.span.start;
        if matches!(
            self.current().kind,
            TokenKind::Newline | TokenKind::Semicolon | TokenKind::KwEnd | TokenKind::KwElse
                | TokenKind::KwElseIf | TokenKind::KwCase | TokenKind::KwDefault | TokenKind::Eof
        ) {
            return Ok(Stmt::Return {
                value: None,
                span: Span::new(start, self.previous_span().end),
            });
        }
        let value = self.parse_expr()?;
        Ok(Stmt::Return {
            span: Span::new(start, value.span.end),
            value: Some(value),
        })
    }

    fn parse_memory_stmt(&mut self) -> Result<Stmt, ParseError> {
        match self.current().kind.clone() {
            TokenKind::KwMemcpy => {
                let start = self.bump().span.start;
                self.expect_simple(TokenKind::LParen)?;
                let dst = self.parse_expr()?;
                self.expect_simple(TokenKind::Comma)?;
                let src = self.parse_expr()?;
                self.expect_simple(TokenKind::Comma)?;
                let len = self.parse_expr()?;
                let end = self.expect_simple(TokenKind::RParen)?.span.end;
                Ok(Stmt::Memory(MemoryStmt::Memcpy {
                    dst,
                    src,
                    len,
                    span: Span::new(start, end),
                }))
            }
            TokenKind::KwMemmove => {
                let start = self.bump().span.start;
                self.expect_simple(TokenKind::LParen)?;
                let dst = self.parse_expr()?;
                self.expect_simple(TokenKind::Comma)?;
                let src = self.parse_expr()?;
                self.expect_simple(TokenKind::Comma)?;
                let len = self.parse_expr()?;
                let end = self.expect_simple(TokenKind::RParen)?.span.end;
                Ok(Stmt::Memory(MemoryStmt::Memmove {
                    dst,
                    src,
                    len,
                    span: Span::new(start, end),
                }))
            }
            TokenKind::KwMemset => {
                let start = self.bump().span.start;
                self.expect_simple(TokenKind::LParen)?;
                let dst = self.parse_expr()?;
                self.expect_simple(TokenKind::Comma)?;
                let byte = self.parse_expr()?;
                self.expect_simple(TokenKind::Comma)?;
                let len = self.parse_expr()?;
                let end = self.expect_simple(TokenKind::RParen)?.span.end;
                Ok(Stmt::Memory(MemoryStmt::Memset {
                    dst,
                    byte,
                    len,
                    span: Span::new(start, end),
                }))
            }
            TokenKind::KwStore => {
                let start = self.bump().span.start;
                self.expect_simple(TokenKind::Less)?;
                let ty = self.parse_type_expr()?;
                self.expect_simple(TokenKind::Greater)?;
                self.expect_simple(TokenKind::LParen)?;
                let dst = self.parse_expr()?;
                self.expect_simple(TokenKind::Comma)?;
                let value = self.parse_expr()?;
                let end = self.expect_simple(TokenKind::RParen)?.span.end;
                Ok(Stmt::Memory(MemoryStmt::Store {
                    ty,
                    dst,
                    value,
                    span: Span::new(start, end),
                }))
            }
            _ => Err(ParseError::new(
                "expected memory statement",
                self.current_span(),
            )),
        }
    }

    fn parse_assign_or_expr_stmt(&mut self) -> Result<Stmt, ParseError> {
        let expr = self.parse_expr()?;
        if self.eat_simple(TokenKind::Assign) {
            let value = self.parse_expr()?;
            let span = Span::new(expr.span.start, value.span.end);
            Ok(Stmt::Assign {
                target: expr,
                value,
                span,
            })
        } else {
            let span = expr.span;
            Ok(Stmt::Expr { expr, span })
        }
    }

    fn parse_expr(&mut self) -> Result<Expr, ParseError> {
        self.parse_expr_bp(0)
    }

    fn parse_expr_bp(&mut self, min_bp: u8) -> Result<Expr, ParseError> {
        let mut lhs = self.parse_prefix_expr()?;
        loop {
            lhs = match &self.current().kind {
                TokenKind::LParen => {
                    let (lbp, _) = postfix_binding_power();
                    if lbp < min_bp {
                        break;
                    }
                    self.bump();
                    let mut args = Vec::new();
                    if !self.check_simple(&TokenKind::RParen) {
                        loop {
                            args.push(self.parse_expr()?);
                            if !self.eat_simple(TokenKind::Comma) {
                                break;
                            }
                        }
                    }
                    let end = self.expect_simple(TokenKind::RParen)?.span.end;
                    Expr {
                        span: Span::new(lhs.span.start, end),
                        kind: ExprKind::Call {
                            callee: Box::new(lhs),
                            args,
                        },
                    }
                }
                TokenKind::LBracket => {
                    let (lbp, _) = postfix_binding_power();
                    if lbp < min_bp {
                        break;
                    }
                    self.bump();
                    let index = self.parse_expr()?;
                    let end = self.expect_simple(TokenKind::RBracket)?.span.end;
                    Expr {
                        span: Span::new(lhs.span.start, end),
                        kind: ExprKind::Index {
                            base: Box::new(lhs),
                            index: Box::new(index),
                        },
                    }
                }
                TokenKind::Colon => {
                    let (lbp, _) = postfix_binding_power();
                    if lbp < min_bp {
                        break;
                    }
                    self.bump();
                    let (method, _) = self.expect_ident()?;
                    self.expect_simple(TokenKind::LParen)?;
                    let mut args = Vec::new();
                    if !self.check_simple(&TokenKind::RParen) {
                        loop {
                            args.push(self.parse_expr()?);
                            if !self.eat_simple(TokenKind::Comma) {
                                break;
                            }
                        }
                    }
                    let end = self.expect_simple(TokenKind::RParen)?.span.end;
                    Expr {
                        span: Span::new(lhs.span.start, end),
                        kind: ExprKind::MethodCall {
                            receiver: Box::new(lhs),
                            method,
                            args,
                        },
                    }
                }
                TokenKind::Dot => {
                    let (lbp, _) = postfix_binding_power();
                    if lbp < min_bp {
                        break;
                    }
                    self.bump();
                    let (name, span) = self.expect_ident()?;
                    Expr {
                        span: Span::new(lhs.span.start, span.end),
                        kind: ExprKind::Field {
                            base: Box::new(lhs),
                            name,
                        },
                    }
                }
                _ => {
                    let Some((lbp, rbp, op)) = self.current_binary_op() else {
                        break;
                    };
                    if lbp < min_bp {
                        break;
                    }
                    self.bump();
                    let rhs = self.parse_expr_bp(rbp)?;
                    let end = rhs.span.end;
                    Expr {
                        span: Span::new(lhs.span.start, end),
                        kind: ExprKind::Binary {
                            op,
                            lhs: Box::new(lhs),
                            rhs: Box::new(rhs),
                        },
                    }
                }
            };
        }
        Ok(lhs)
    }

    fn parse_prefix_expr(&mut self) -> Result<Expr, ParseError> {
        self.skip_separators();
        let token = self.current().clone();
        match token.kind {
            TokenKind::Number(raw) => {
                self.bump();
                Ok(Expr {
                    span: token.span,
                    kind: ExprKind::Number(NumberLit {
                        kind: if raw.contains('.') || raw.contains('e') || raw.contains('E') {
                            NumberKind::Float
                        } else {
                            NumberKind::Int
                        },
                        raw,
                        span: token.span,
                    }),
                })
            }
            TokenKind::String(s) => {
                self.bump();
                Ok(Expr {
                    span: token.span,
                    kind: ExprKind::String(s),
                })
            }
            TokenKind::KwTrue => {
                self.bump();
                Ok(Expr {
                    span: token.span,
                    kind: ExprKind::Bool(true),
                })
            }
            TokenKind::KwFalse => {
                self.bump();
                Ok(Expr {
                    span: token.span,
                    kind: ExprKind::Bool(false),
                })
            }
            TokenKind::KwNil => {
                self.bump();
                Ok(Expr {
                    span: token.span,
                    kind: ExprKind::Nil,
                })
            }
            TokenKind::Splice(source) => {
                self.bump();
                Ok(Expr {
                    span: token.span,
                    kind: ExprKind::Splice(source),
                })
            }
            TokenKind::Question => self.parse_hole_expr(),
            TokenKind::Minus => self.parse_unary_expr(UnaryOp::Neg),
            TokenKind::KwNot => self.parse_unary_expr(UnaryOp::Not),
            TokenKind::Tilde => self.parse_unary_expr(UnaryOp::BitNot),
            TokenKind::Amp => self.parse_unary_expr(UnaryOp::AddrOf),
            TokenKind::Star => self.parse_unary_expr(UnaryOp::Deref),
            TokenKind::KwIf => self.parse_if_expr(),
            TokenKind::KwSwitch => self.parse_switch_expr(),
            TokenKind::KwDo => self.parse_block_expr(),
            TokenKind::KwFunc => self.parse_anonymous_func_expr(),
            TokenKind::KwCast => self.parse_cast_like_expr(CastKind::Cast),
            TokenKind::KwTrunc => self.parse_cast_like_expr(CastKind::Trunc),
            TokenKind::KwZext => self.parse_cast_like_expr(CastKind::Zext),
            TokenKind::KwSext => self.parse_cast_like_expr(CastKind::Sext),
            TokenKind::KwBitcast => self.parse_cast_like_expr(CastKind::Bitcast),
            TokenKind::KwSizeof => self.parse_sizeof_expr(),
            TokenKind::KwAlignof => self.parse_alignof_expr(),
            TokenKind::KwOffsetof => self.parse_offsetof_expr(),
            TokenKind::KwLoad => self.parse_load_expr(),
            TokenKind::KwMemcmp => self.parse_memcmp_expr(),
            TokenKind::LParen => {
                self.bump();
                let expr = self.parse_expr()?;
                let end = self.expect_simple(TokenKind::RParen)?.span.end;
                Ok(Expr {
                    span: Span::new(token.span.start, end),
                    kind: expr.kind,
                })
            }
            TokenKind::LBracket => self.parse_array_aggregate_expr(),
            TokenKind::Ident(_) => self.parse_name_or_aggregate_expr(),
            _ => Err(ParseError::new("expected expression", token.span)),
        }
    }

    fn parse_unary_expr(&mut self, op: UnaryOp) -> Result<Expr, ParseError> {
        let start = self.bump().span.start;
        let expr = self.parse_expr_bp(prefix_binding_power())?;
        Ok(Expr {
            span: Span::new(start, expr.span.end),
            kind: ExprKind::Unary {
                op,
                expr: Box::new(expr),
            },
        })
    }

    fn parse_if_expr(&mut self) -> Result<Expr, ParseError> {
        let start = self.expect_simple(TokenKind::KwIf)?.span.start;
        let cond = self.parse_expr()?;
        self.expect_simple(TokenKind::KwThen)?;
        let then_value = self.parse_expr()?;
        let mut branches = vec![IfExprBranch {
            span: Span::new(cond.span.start, then_value.span.end),
            cond,
            value: then_value,
        }];
        while self.eat_simple(TokenKind::KwElseIf) {
            let cond = self.parse_expr()?;
            self.expect_simple(TokenKind::KwThen)?;
            let value = self.parse_expr()?;
            let span = Span::new(cond.span.start, value.span.end);
            branches.push(IfExprBranch { cond, value, span });
        }
        self.expect_simple(TokenKind::KwElse)?;
        let else_branch = self.parse_expr()?;
        self.expect_simple(TokenKind::KwEnd)?;
        Ok(Expr {
            span: Span::new(start, self.previous_span().end),
            kind: ExprKind::If(IfExpr {
                span: Span::new(start, self.previous_span().end),
                branches,
                else_branch: Box::new(else_branch),
            }),
        })
    }

    fn parse_switch_expr(&mut self) -> Result<Expr, ParseError> {
        let start = self.expect_simple(TokenKind::KwSwitch)?.span.start;
        let value = self.parse_expr()?;
        self.expect_simple(TokenKind::KwDo)?;
        self.skip_separators();
        let mut cases = Vec::new();
        while self.eat_simple(TokenKind::KwCase) {
            let case_value = self.parse_expr()?;
            self.expect_simple(TokenKind::KwThen)?;
            let body = self.parse_expr()?;
            let span = Span::new(case_value.span.start, body.span.end);
            cases.push(SwitchExprCase {
                value: case_value,
                body,
                span,
            });
            self.skip_separators();
        }
        self.expect_simple(TokenKind::KwDefault)?;
        self.expect_simple(TokenKind::KwThen)?;
        let default = self.parse_expr()?;
        self.skip_separators();
        self.expect_simple(TokenKind::KwEnd)?;
        Ok(Expr {
            span: Span::new(start, self.previous_span().end),
            kind: ExprKind::Switch(SwitchExpr {
                value: Box::new(value),
                cases,
                default: Box::new(default),
                span: Span::new(start, self.previous_span().end),
            }),
        })
    }

    fn parse_block_expr(&mut self) -> Result<Expr, ParseError> {
        let start = self.expect_simple(TokenKind::KwDo)?.span.start;
        let body = self.parse_stmt_block_until(|k| matches!(k, TokenKind::KwEnd))?;
        self.expect_simple(TokenKind::KwEnd)?;
        Ok(Expr {
            span: Span::new(start, self.previous_span().end),
            kind: ExprKind::Block(body),
        })
    }

    fn parse_anonymous_func_expr(&mut self) -> Result<Expr, ParseError> {
        let sig = self.parse_func_signature()?;
        match sig.name {
            FuncName::Anonymous => {}
            _ => {
                return Err(ParseError::new(
                    "anonymous func expression must use func(...) form",
                    sig.span,
                ))
            }
        }
        let body = self.parse_stmt_block_until(|k| matches!(k, TokenKind::KwEnd))?;
        self.expect_simple(TokenKind::KwEnd)?;
        let decl = FuncDecl {
            span: Span::new(sig.span.start, self.previous_span().end),
            sig,
            body,
        };
        Ok(Expr {
            span: decl.span,
            kind: ExprKind::AnonymousFunc(decl),
        })
    }

    fn parse_cast_like_expr(&mut self, kind: CastKind) -> Result<Expr, ParseError> {
        let start = self.bump().span.start;
        self.expect_simple(TokenKind::Less)?;
        let ty = self.parse_type_expr()?;
        self.expect_simple(TokenKind::Greater)?;
        self.expect_simple(TokenKind::LParen)?;
        let value = self.parse_expr()?;
        let end = self.expect_simple(TokenKind::RParen)?.span.end;
        Ok(Expr {
            span: Span::new(start, end),
            kind: ExprKind::Cast {
                kind,
                ty,
                value: Box::new(value),
            },
        })
    }

    fn parse_sizeof_expr(&mut self) -> Result<Expr, ParseError> {
        let start = self.bump().span.start;
        self.expect_simple(TokenKind::LParen)?;
        let ty = self.parse_type_expr()?;
        let end = self.expect_simple(TokenKind::RParen)?.span.end;
        Ok(Expr {
            span: Span::new(start, end),
            kind: ExprKind::SizeOf(ty),
        })
    }

    fn parse_alignof_expr(&mut self) -> Result<Expr, ParseError> {
        let start = self.bump().span.start;
        self.expect_simple(TokenKind::LParen)?;
        let ty = self.parse_type_expr()?;
        let end = self.expect_simple(TokenKind::RParen)?.span.end;
        Ok(Expr {
            span: Span::new(start, end),
            kind: ExprKind::AlignOf(ty),
        })
    }

    fn parse_offsetof_expr(&mut self) -> Result<Expr, ParseError> {
        let start = self.bump().span.start;
        self.expect_simple(TokenKind::LParen)?;
        let ty = self.parse_type_expr()?;
        self.expect_simple(TokenKind::Comma)?;
        let (field, _) = self.expect_ident()?;
        let end = self.expect_simple(TokenKind::RParen)?.span.end;
        Ok(Expr {
            span: Span::new(start, end),
            kind: ExprKind::OffsetOf { ty, field },
        })
    }

    fn parse_load_expr(&mut self) -> Result<Expr, ParseError> {
        let start = self.bump().span.start;
        self.expect_simple(TokenKind::Less)?;
        let ty = self.parse_type_expr()?;
        self.expect_simple(TokenKind::Greater)?;
        self.expect_simple(TokenKind::LParen)?;
        let ptr = self.parse_expr()?;
        let end = self.expect_simple(TokenKind::RParen)?.span.end;
        Ok(Expr {
            span: Span::new(start, end),
            kind: ExprKind::Load {
                ty,
                ptr: Box::new(ptr),
            },
        })
    }

    fn parse_memcmp_expr(&mut self) -> Result<Expr, ParseError> {
        let start = self.bump().span.start;
        self.expect_simple(TokenKind::LParen)?;
        let a = self.parse_expr()?;
        self.expect_simple(TokenKind::Comma)?;
        let b = self.parse_expr()?;
        self.expect_simple(TokenKind::Comma)?;
        let len = self.parse_expr()?;
        let end = self.expect_simple(TokenKind::RParen)?.span.end;
        Ok(Expr {
            span: Span::new(start, end),
            kind: ExprKind::Memcmp {
                a: Box::new(a),
                b: Box::new(b),
                len: Box::new(len),
            },
        })
    }

    fn parse_hole_expr(&mut self) -> Result<Expr, ParseError> {
        let start = self.expect_simple(TokenKind::Question)?.span.start;
        let (name, _) = self.expect_ident()?;
        self.expect_simple(TokenKind::Colon)?;
        let ty = self.parse_type_expr()?;
        Ok(Expr {
            span: Span::new(start, ty.span().end),
            kind: ExprKind::Hole { name, ty },
        })
    }

    fn parse_name_or_aggregate_expr(&mut self) -> Result<Expr, ParseError> {
        let path = self.parse_path()?;
        if self.check_simple(&TokenKind::LBrace) {
            let ctor = TypeCtor::Path(path.clone());
            return self.parse_aggregate_literal(ctor, path.span.start);
        }
        Ok(Expr {
            span: path.span,
            kind: ExprKind::Path(path),
        })
    }

    fn parse_array_aggregate_expr(&mut self) -> Result<Expr, ParseError> {
        let start = self.expect_simple(TokenKind::LBracket)?.span.start;
        let len = self.parse_expr()?;
        self.expect_simple(TokenKind::RBracket)?;
        let elem = self.parse_type_expr()?;
        let ctor = TypeCtor::Array {
            span: Span::new(start, elem.span().end),
            len: Box::new(len),
            elem: Box::new(elem),
        };
        self.parse_aggregate_literal(ctor, start)
    }

    fn parse_aggregate_literal(&mut self, ctor: TypeCtor, start: usize) -> Result<Expr, ParseError> {
        self.expect_simple(TokenKind::LBrace)?;
        let mut fields = Vec::new();
        if !self.check_simple(&TokenKind::RBrace) {
            loop {
                let field = if matches!(self.current().kind, TokenKind::Ident(_))
                    && self.tokens.get(self.index + 1).is_some_and(|t| matches!(t.kind, TokenKind::Assign))
                {
                    let (name, span) = self.expect_ident()?;
                    self.expect_simple(TokenKind::Assign)?;
                    let value = self.parse_expr()?;
                    AggregateField::Named {
                        name,
                        span: Span::new(span.start, value.span.end),
                        value,
                    }
                } else {
                    let value = self.parse_expr()?;
                    AggregateField::Positional {
                        span: value.span,
                        value,
                    }
                };
                fields.push(field);
                if !self.eat_simple(TokenKind::Comma) {
                    break;
                }
                if self.check_simple(&TokenKind::RBrace) {
                    break;
                }
            }
        }
        let end = self.expect_simple(TokenKind::RBrace)?.span.end;
        Ok(Expr {
            span: Span::new(start, end),
            kind: ExprKind::Aggregate { ctor, fields },
        })
    }

    fn current_binary_op(&self) -> Option<(u8, u8, BinaryOp)> {
        let (lbp, rbp, op) = match self.current().kind {
            TokenKind::KwOr => (10, 11, BinaryOp::Or),
            TokenKind::KwAnd => (20, 21, BinaryOp::And),
            TokenKind::EqEq => (30, 31, BinaryOp::Eq),
            TokenKind::NotEq => (30, 31, BinaryOp::Ne),
            TokenKind::Less => (30, 31, BinaryOp::Lt),
            TokenKind::LessEq => (30, 31, BinaryOp::Le),
            TokenKind::Greater => (30, 31, BinaryOp::Gt),
            TokenKind::GreaterEq => (30, 31, BinaryOp::Ge),
            TokenKind::Pipe => (40, 41, BinaryOp::BitOr),
            TokenKind::Tilde => (50, 51, BinaryOp::BitXor),
            TokenKind::Amp => (60, 61, BinaryOp::BitAnd),
            TokenKind::Shl => (70, 71, BinaryOp::Shl),
            TokenKind::Shr => (70, 71, BinaryOp::Shr),
            TokenKind::ShrU => (70, 71, BinaryOp::ShrU),
            TokenKind::Plus => (80, 81, BinaryOp::Add),
            TokenKind::Minus => (80, 81, BinaryOp::Sub),
            TokenKind::Star => (90, 91, BinaryOp::Mul),
            TokenKind::Slash => (90, 91, BinaryOp::Div),
            TokenKind::Percent => (90, 91, BinaryOp::Rem),
            _ => return None,
        };
        Some((lbp, rbp, op))
    }
}

fn prefix_binding_power() -> u8 {
    100
}

fn postfix_binding_power() -> (u8, u8) {
    (110, 111)
}

fn stmt_span_end(stmt: &Stmt) -> usize {
    match stmt {
        Stmt::Let { span, .. }
        | Stmt::Var { span, .. }
        | Stmt::Assign { span, .. }
        | Stmt::While { span, .. }
        | Stmt::For(ForStmt { span, .. })
        | Stmt::Break { span }
        | Stmt::Continue { span }
        | Stmt::Return { span, .. }
        | Stmt::Expr { span, .. } => span.end,
        Stmt::If(v) => v.span.end,
        Stmt::Switch(v) => v.span.end,
        Stmt::Memory(v) => match v {
            MemoryStmt::Memcpy { span, .. }
            | MemoryStmt::Memmove { span, .. }
            | MemoryStmt::Memset { span, .. }
            | MemoryStmt::Store { span, .. } => span.end,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_function_type() {
        let ty = parse_type("func(&u8, usize) -> void").unwrap();
        match ty {
            TypeExpr::Func { params, result, .. } => {
                assert_eq!(params.len(), 2);
                assert!(result.is_some());
            }
            _ => panic!("expected func type"),
        }
    }

    #[test]
    fn parse_hole_expr() {
        let expr = parse_expr("?lhs: i32 + ?rhs: i32").unwrap();
        match expr.kind {
            ExprKind::Binary { .. } => {}
            _ => panic!("expected binary hole expr"),
        }
    }

    #[test]
    fn parse_basic_func_item() {
        let item = parse_code(
            "func add(a: i32, b: i32) -> i32\n    return a + b\nend\n",
        )
        .unwrap();
        match item.kind {
            ItemKind::Func(FuncDecl { sig, .. }) => match sig.name {
                FuncName::Named(name) => assert_eq!(name, "add"),
                _ => panic!("expected named function"),
            },
            _ => panic!("expected function item"),
        }
    }

    #[test]
    fn parse_module_with_impl_and_struct() {
        let module = parse_module(
            "struct Pair\n    a: i32\n    b: i32\nend\n\nimpl Pair\n    func sum(self: &Pair) -> i32\n        return self.a + self.b\n    end\nend\n\nfunc pair_sum(p: &Pair) -> i32\n    return p:sum()\nend\n",
        )
        .unwrap();
        assert_eq!(module.items.len(), 3);
    }

    #[test]
    fn parse_tagged_union_and_switch() {
        let module = parse_module(
            "tagged union Value : u8\n    I32\n        value: i32\n    end\n\n    Pair\n        a: i16\n        b: i16\n    end\n\n    Nil\nend\n\nfunc code(x: i32) -> i32\n    switch x do\n    case 0 then\n        return 0\n    default then\n        return 42\n    end\nend\n",
        )
        .unwrap();
        assert_eq!(module.items.len(), 2);
    }

    #[test]
    fn parse_splice_expr() {
        let expr = parse_expr("@{N} + 1").unwrap();
        match expr.kind {
            ExprKind::Binary { .. } => {}
            _ => panic!("expected binary expr with splice"),
        }
    }

    #[test]
    fn parse_extern_fragment() {
        let items = parse_externs(
            "@abi(\"C\")\nextern func abs(x: i32) -> i32\nextern func memcpy(dst: &u8, src: &u8, len: usize) -> void\n",
        )
        .unwrap();
        assert_eq!(items.len(), 2);
    }

    #[test]
    fn parse_block_expr_and_if_expr() {
        let expr = parse_expr(
            "if x < y then do\n    let z: i32 = 1\n    return z\nend else 0 end",
        )
        .unwrap();
        match expr.kind {
            ExprKind::If(_) => {}
            _ => panic!("expected if expression"),
        }
    }

    #[test]
    fn parse_anonymous_func_expression() {
        let expr = parse_expr(
            "func(x: i32) -> i32\n    return x + 1\nend",
        )
        .unwrap();
        match expr.kind {
            ExprKind::AnonymousFunc(_) => {}
            _ => panic!("expected anonymous func expression"),
        }
    }
}
