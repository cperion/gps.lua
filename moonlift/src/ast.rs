use crate::source::Span;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Visibility {
    Private,
    Public,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Attribute {
    pub name: String,
    pub args: Vec<AttrArg>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum AttrArg {
    Ident(String),
    Number(String),
    String(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Path {
    pub segments: Vec<String>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ModuleAst {
    pub items: Vec<Item>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Item {
    pub visibility: Visibility,
    pub attributes: Vec<Attribute>,
    pub kind: ItemKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ItemKind {
    Const(ConstDecl),
    TypeAlias(TypeAliasDecl),
    Struct(StructDecl),
    Union(UnionDecl),
    TaggedUnion(TaggedUnionDecl),
    Enum(EnumDecl),
    Opaque(OpaqueDecl),
    Slice(SliceDecl),
    Func(FuncDecl),
    ExternFunc(ExternFuncDecl),
    Impl(ImplDecl),
    Splice(String),
}

#[derive(Clone, Debug, PartialEq)]
pub struct ConstDecl {
    pub name: String,
    pub ty: Option<TypeExpr>,
    pub value: Expr,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TypeAliasDecl {
    pub name: String,
    pub ty: TypeExpr,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FieldDecl {
    pub name: String,
    pub ty: TypeExpr,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct StructDecl {
    pub name: String,
    pub fields: Vec<FieldDecl>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct UnionDecl {
    pub name: String,
    pub fields: Vec<FieldDecl>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TaggedVariantDecl {
    pub name: String,
    pub fields: Vec<FieldDecl>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TaggedUnionDecl {
    pub name: String,
    pub base_ty: Option<TypeExpr>,
    pub variants: Vec<TaggedVariantDecl>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct EnumMemberDecl {
    pub name: String,
    pub value: Option<Expr>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct EnumDecl {
    pub name: String,
    pub base_ty: Option<TypeExpr>,
    pub members: Vec<EnumMemberDecl>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct OpaqueDecl {
    pub name: String,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SliceDecl {
    pub name: String,
    pub ty: TypeExpr,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Param {
    pub name: String,
    pub ty: TypeExpr,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FuncName {
    Named(String),
    Method { target: Path, method: String },
    Anonymous,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FuncSig {
    pub name: FuncName,
    pub params: Vec<Param>,
    pub result: Option<TypeExpr>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FuncDecl {
    pub sig: FuncSig,
    pub body: Block,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ExternFuncDecl {
    pub name: String,
    pub params: Vec<Param>,
    pub result: Option<TypeExpr>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ImplDecl {
    pub target: Path,
    pub items: Vec<ImplItem>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ImplItem {
    pub attributes: Vec<Attribute>,
    pub func: FuncDecl,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum TypeExpr {
    Path(Path),
    Pointer {
        inner: Box<TypeExpr>,
        span: Span,
    },
    Array {
        len: Box<Expr>,
        elem: Box<TypeExpr>,
        span: Span,
    },
    Slice {
        elem: Box<TypeExpr>,
        span: Span,
    },
    Func {
        params: Vec<TypeExpr>,
        result: Option<Box<TypeExpr>>,
        span: Span,
    },
    Splice {
        source: String,
        span: Span,
    },
    Group {
        inner: Box<TypeExpr>,
        span: Span,
    },
}

impl TypeExpr {
    pub fn span(&self) -> Span {
        match self {
            Self::Path(v) => v.span,
            Self::Pointer { span, .. }
            | Self::Array { span, .. }
            | Self::Slice { span, .. }
            | Self::Func { span, .. }
            | Self::Splice { span, .. }
            | Self::Group { span, .. } => *span,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Block {
    pub stmts: Vec<Stmt>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Stmt {
    Let {
        name: String,
        ty: Option<TypeExpr>,
        value: Expr,
        span: Span,
    },
    Var {
        name: String,
        ty: Option<TypeExpr>,
        value: Expr,
        span: Span,
    },
    Assign {
        target: Expr,
        value: Expr,
        span: Span,
    },
    If(IfStmt),
    While {
        cond: Expr,
        body: Block,
        span: Span,
    },
    For(ForStmt),
    Switch(SwitchStmt),
    Break {
        span: Span,
    },
    Continue {
        span: Span,
    },
    Return {
        value: Option<Expr>,
        span: Span,
    },
    Memory(MemoryStmt),
    Expr {
        expr: Expr,
        span: Span,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub struct IfStmt {
    pub branches: Vec<IfStmtBranch>,
    pub else_branch: Option<Block>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct IfStmtBranch {
    pub cond: Expr,
    pub body: Block,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ForStmt {
    pub name: String,
    pub start: Expr,
    pub end: Expr,
    pub step: Option<Expr>,
    pub body: Block,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SwitchStmt {
    pub value: Expr,
    pub cases: Vec<SwitchStmtCase>,
    pub default: Option<Block>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SwitchStmtCase {
    pub value: Expr,
    pub body: Block,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum MemoryStmt {
    Memcpy {
        dst: Expr,
        src: Expr,
        len: Expr,
        span: Span,
    },
    Memmove {
        dst: Expr,
        src: Expr,
        len: Expr,
        span: Span,
    },
    Memset {
        dst: Expr,
        byte: Expr,
        len: Expr,
        span: Span,
    },
    Store {
        ty: TypeExpr,
        dst: Expr,
        value: Expr,
        span: Span,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub enum NumberKind {
    Int,
    Float,
}

#[derive(Clone, Debug, PartialEq)]
pub struct NumberLit {
    pub raw: String,
    pub kind: NumberKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum TypeCtor {
    Path(Path),
    Array {
        len: Box<Expr>,
        elem: Box<TypeExpr>,
        span: Span,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub enum AggregateField {
    Named {
        name: String,
        value: Expr,
        span: Span,
    },
    Positional {
        value: Expr,
        span: Span,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum UnaryOp {
    Neg,
    Not,
    BitNot,
    AddrOf,
    Deref,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BinaryOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    And,
    Or,
    BitAnd,
    BitOr,
    BitXor,
    Shl,
    Shr,
    ShrU,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CastKind {
    Cast,
    Trunc,
    Zext,
    Sext,
    Bitcast,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Expr {
    pub kind: ExprKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ExprKind {
    Path(Path),
    Number(NumberLit),
    Bool(bool),
    Nil,
    String(String),
    Aggregate {
        ctor: TypeCtor,
        fields: Vec<AggregateField>,
    },
    Cast {
        kind: CastKind,
        ty: TypeExpr,
        value: Box<Expr>,
    },
    SizeOf(TypeExpr),
    AlignOf(TypeExpr),
    OffsetOf {
        ty: TypeExpr,
        field: String,
    },
    Load {
        ty: TypeExpr,
        ptr: Box<Expr>,
    },
    Memcmp {
        a: Box<Expr>,
        b: Box<Expr>,
        len: Box<Expr>,
    },
    Block(Block),
    If(IfExpr),
    Switch(SwitchExpr),
    Unary {
        op: UnaryOp,
        expr: Box<Expr>,
    },
    Binary {
        op: BinaryOp,
        lhs: Box<Expr>,
        rhs: Box<Expr>,
    },
    Field {
        base: Box<Expr>,
        name: String,
    },
    Index {
        base: Box<Expr>,
        index: Box<Expr>,
    },
    Call {
        callee: Box<Expr>,
        args: Vec<Expr>,
    },
    MethodCall {
        receiver: Box<Expr>,
        method: String,
        args: Vec<Expr>,
    },
    Splice(String),
    Hole {
        name: String,
        ty: TypeExpr,
    },
    AnonymousFunc(FuncDecl),
}

#[derive(Clone, Debug, PartialEq)]
pub struct IfExpr {
    pub branches: Vec<IfExprBranch>,
    pub else_branch: Box<Expr>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct IfExprBranch {
    pub cond: Expr,
    pub value: Expr,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SwitchExpr {
    pub value: Box<Expr>,
    pub cases: Vec<SwitchExprCase>,
    pub default: Box<Expr>,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SwitchExprCase {
    pub value: Expr,
    pub body: Expr,
    pub span: Span,
}
