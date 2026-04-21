use crate::ast::{
    AttrArg, BinaryOp as AstBinaryOp, Block, CastKind, Expr as AstExpr, ExprKind, ExternFuncDecl,
    ForStmt, FuncDecl, FuncName, IfStmt, Item, ItemKind, LoopExpr as AstLoopExpr,
    LoopHead as AstLoopHead, LoopNextAssign as AstLoopNextAssign, LoopStmt as AstLoopStmt,
    LoopVarInit as AstLoopVarInit, ModuleAst, NumberKind, Param, Path, Stmt as AstStmt,
    SwitchExpr, SwitchStmt, TypeCtor, TypeExpr, UnaryOp as AstUnaryOp,
};
use crate::cranelift_jit::{
    BinaryOp, CallTarget, CastOp, Expr, FunctionSpec, LoopVar, ScalarType, StepDirection, Stmt,
    UnaryOp,
};
use crate::parser::{parse_code, parse_expr as parse_source_expr, parse_externs, parse_module, parse_type};
use std::collections::{HashMap, HashSet};

#[derive(Clone, Debug)]
pub struct NativeParamMeta {
    pub name: String,
    pub ty: ScalarType,
    pub ty_ref: NativeTypeRefMeta,
}

#[derive(Clone, Debug)]
pub struct NativeFuncMeta {
    pub name: String,
    pub params: Vec<NativeParamMeta>,
    pub result: ScalarType,
    pub owner: Option<String>,
    pub method_name: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum NativeTypeRefMeta {
    Scalar(String),
    Pointer(Box<NativeTypeRefMeta>),
    Array {
        elem: Box<NativeTypeRefMeta>,
        len: u32,
    },
    Slice(Box<NativeTypeRefMeta>),
    Func {
        params: Vec<NativeTypeRefMeta>,
        result: Option<Box<NativeTypeRefMeta>>,
    },
    Path(String),
}

#[derive(Clone, Debug)]
pub struct NativeFieldMeta {
    pub name: String,
    pub ty: NativeTypeRefMeta,
}

#[derive(Clone, Debug)]
pub struct NativeTaggedVariantMeta {
    pub name: String,
    pub fields: Vec<NativeFieldMeta>,
}

#[derive(Clone, Debug)]
pub struct NativeEnumMemberMeta {
    pub name: String,
    pub value: i64,
}

#[derive(Clone, Debug)]
pub struct NativeConstFieldMeta {
    pub name: Option<String>,
    pub value: NativeConstValueMeta,
}

#[derive(Clone, Debug)]
pub enum NativeConstValueMeta {
    Bool(bool),
    Int(i64),
    Float(f64),
    Aggregate {
        fields: Vec<NativeConstFieldMeta>,
    },
}

#[derive(Clone, Debug)]
pub struct NativeConstMeta {
    pub name: String,
    pub ty: NativeTypeRefMeta,
    pub value: NativeConstValueMeta,
}

#[derive(Clone, Debug)]
pub enum NativeTypeMeta {
    Struct {
        name: String,
        fields: Vec<NativeFieldMeta>,
    },
    Union {
        name: String,
        fields: Vec<NativeFieldMeta>,
    },
    TaggedUnion {
        name: String,
        base: Option<NativeTypeRefMeta>,
        variants: Vec<NativeTaggedVariantMeta>,
    },
    Enum {
        name: String,
        base: NativeTypeRefMeta,
        members: Vec<NativeEnumMemberMeta>,
    },
    Slice {
        name: String,
        elem: NativeTypeRefMeta,
    },
    TypeAlias {
        name: String,
        ty: NativeTypeRefMeta,
    },
}

#[derive(Clone, Debug)]
pub struct NativeExternMeta {
    pub name: String,
    pub symbol: String,
    pub params: Vec<NativeParamMeta>,
    pub result: ScalarType,
}

#[derive(Clone, Debug)]
pub struct PreparedCode {
    pub meta: NativeFuncMeta,
    pub spec: FunctionSpec,
}

#[derive(Clone, Debug)]
pub struct PreparedExpr {
    pub expr: Expr,
    pub ty: ScalarType,
}

#[derive(Clone, Debug)]
pub struct PreparedModule {
    pub funcs: Vec<PreparedCode>,
    pub types: Vec<NativeTypeMeta>,
    pub externs: Vec<NativeExternMeta>,
    pub consts: Vec<NativeConstMeta>,
    pub meta_complete: bool,
}

#[derive(Clone)]
struct FuncSigInfo {
    symbol: String,
    params: Vec<ScalarType>,
    result: Option<ScalarType>,
}

#[derive(Clone)]
struct StructFieldInfo {
    ty: ScalarType,
    offset: u32,
}

#[derive(Clone)]
struct StructLayout {
    name: String,
    fields: HashMap<String, StructFieldInfo>,
    size: u32,
    align: u32,
    slice_elem_ty: Option<ScalarType>,
}

#[derive(Clone)]
struct TaggedUnionLayout {
    name: String,
    tag_ty: ScalarType,
    payload_offset: u32,
    payload_size: u32,
    size: u32,
    align: u32,
    variants: HashMap<String, StructLayout>,
    variant_tags: HashMap<String, u64>,
}

#[derive(Clone)]
struct ArrayLayout {
    elem_ty: ScalarType,
    count: u32,
    size: u32,
    align: u32,
}

#[derive(Clone)]
struct BindingInfo {
    lowered_name: String,
    ty: ScalarType,
    mutable: bool,
    arg_index: Option<u32>,
    stack_slot_name: Option<String>,
    struct_name: Option<String>,
    array_layout: Option<ArrayLayout>,
    pointer_elem_ty: Option<ScalarType>,
}

#[derive(Clone)]
struct IndexBaseInfo {
    base_ptr: Expr,
    elem_ty: ScalarType,
    elem_size: u32,
    limit: Option<Expr>,
}

#[derive(Clone)]
struct DomainOverrideInfo {
    base: IndexBaseInfo,
}

#[derive(Clone)]
struct LowerCtx<'a> {
    scopes: Vec<HashMap<String, BindingInfo>>,
    domain_scopes: Vec<HashMap<String, DomainOverrideInfo>>,
    funcs: &'a HashMap<String, FuncSigInfo>,
    methods: &'a HashMap<String, HashMap<String, FuncSigInfo>>,
    structs: &'a HashMap<String, StructLayout>,
    taggeds: &'a HashMap<String, TaggedUnionLayout>,
    next_temp_id: usize,
}

#[derive(Clone)]
struct ReturnState {
    result_name: Option<String>,
    result_ty: Option<ScalarType>,
    returned_name: String,
    void_function: bool,
}

#[derive(Clone)]
struct LoopStateBinding {
    source_name: String,
    lowered_name: String,
    ty: ScalarType,
}

#[derive(Default)]
struct LoweredStmt {
    stmts: Vec<Stmt>,
    stop: bool,
}

#[derive(Clone)]
struct EnumEvalInfo {
    base: NativeTypeRefMeta,
    members: HashMap<String, i64>,
}

#[derive(Clone)]
struct ConstEvalField {
    name: Option<String>,
    value: ConstEvalValue,
}

#[derive(Clone)]
enum ConstEvalValue {
    Bool(bool),
    Int(i64),
    Float(f64),
    Aggregate { fields: Vec<ConstEvalField> },
}

#[derive(Clone)]
struct RelaxCallable<'a> {
    display_name: String,
    source_name: Option<String>,
    method_owner: Option<String>,
    method_name: Option<String>,
    func: &'a FuncDecl,
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
        TypeExpr::Pointer { .. } => Ok(ScalarType::Ptr),
        _ => unsupported("only scalar and pointer types are supported natively right now"),
    }
}

fn prepare_param_meta(param: &Param) -> Result<NativeParamMeta, String> {
    Ok(NativeParamMeta {
        name: param.name.clone(),
        ty: scalar_type_from_type_expr(&param.ty)?,
        ty_ref: type_ref_meta_from_type_expr(&param.ty)?,
    })
}

fn type_ref_meta_from_type_expr(ty: &TypeExpr) -> Result<NativeTypeRefMeta, String> {
    match ty {
        TypeExpr::Path(path) => {
            let key = type_path_key(path);
            if ScalarType::from_name(&key).is_some() {
                Ok(NativeTypeRefMeta::Scalar(key))
            } else {
                Ok(NativeTypeRefMeta::Path(key))
            }
        }
        TypeExpr::Pointer { inner, .. } => Ok(NativeTypeRefMeta::Pointer(Box::new(
            type_ref_meta_from_type_expr(inner)?,
        ))),
        TypeExpr::Array { len, elem, .. } => Ok(NativeTypeRefMeta::Array {
            elem: Box::new(type_ref_meta_from_type_expr(elem)?),
            len: eval_const_u32(len).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}native module metadata requires constant array lengths")
            })?,
        }),
        TypeExpr::Slice { elem, .. } => Ok(NativeTypeRefMeta::Slice(Box::new(
            type_ref_meta_from_type_expr(elem)?,
        ))),
        TypeExpr::Func { params, result, .. } => Ok(NativeTypeRefMeta::Func {
            params: params
                .iter()
                .map(type_ref_meta_from_type_expr)
                .collect::<Result<Vec<_>, _>>()?,
            result: result
                .as_ref()
                .map(|v| type_ref_meta_from_type_expr(v))
                .transpose()?
                .map(Box::new),
        }),
        TypeExpr::Group { inner, .. } => type_ref_meta_from_type_expr(inner),
        _ => unsupported("type form is not yet supported by native module metadata"),
    }
}

fn field_meta_from_decl(field: &crate::ast::FieldDecl) -> Result<NativeFieldMeta, String> {
    Ok(NativeFieldMeta {
        name: field.name.clone(),
        ty: type_ref_meta_from_type_expr(&field.ty)?,
    })
}

fn type_meta_from_item(item: &Item) -> Result<Option<NativeTypeMeta>, String> {
    Ok(match &item.kind {
        ItemKind::Struct(decl) => Some(NativeTypeMeta::Struct {
            name: decl.name.clone(),
            fields: decl
                .fields
                .iter()
                .map(field_meta_from_decl)
                .collect::<Result<Vec<_>, _>>()?,
        }),
        ItemKind::Union(decl) => Some(NativeTypeMeta::Union {
            name: decl.name.clone(),
            fields: decl
                .fields
                .iter()
                .map(field_meta_from_decl)
                .collect::<Result<Vec<_>, _>>()?,
        }),
        ItemKind::TaggedUnion(decl) => Some(NativeTypeMeta::TaggedUnion {
            name: decl.name.clone(),
            base: decl
                .base_ty
                .as_ref()
                .map(type_ref_meta_from_type_expr)
                .transpose()?,
            variants: decl
                .variants
                .iter()
                .map(|variant| {
                    Ok(NativeTaggedVariantMeta {
                        name: variant.name.clone(),
                        fields: variant
                            .fields
                            .iter()
                            .map(field_meta_from_decl)
                            .collect::<Result<Vec<_>, _>>()?,
                    })
                })
                .collect::<Result<Vec<_>, String>>()?,
        }),
        ItemKind::Slice(decl) => Some(NativeTypeMeta::Slice {
            name: decl.name.clone(),
            elem: type_ref_meta_from_type_expr(&decl.ty)?,
        }),
        ItemKind::TypeAlias(decl) => Some(NativeTypeMeta::TypeAlias {
            name: decl.name.clone(),
            ty: type_ref_meta_from_type_expr(&decl.ty)?,
        }),
        _ => None,
    })
}

fn const_eval_to_meta(value: &ConstEvalValue) -> NativeConstValueMeta {
    match value {
        ConstEvalValue::Bool(v) => NativeConstValueMeta::Bool(*v),
        ConstEvalValue::Int(v) => NativeConstValueMeta::Int(*v),
        ConstEvalValue::Float(v) => NativeConstValueMeta::Float(*v),
        ConstEvalValue::Aggregate { fields } => NativeConstValueMeta::Aggregate {
            fields: fields
                .iter()
                .map(|field| NativeConstFieldMeta {
                    name: field.name.clone(),
                    value: const_eval_to_meta(&field.value),
                })
                .collect(),
        },
    }
}

fn const_truthy(value: &ConstEvalValue) -> bool {
    !matches!(value, ConstEvalValue::Bool(false))
}

fn const_as_f64(value: &ConstEvalValue) -> Result<f64, String> {
    match value {
        ConstEvalValue::Bool(v) => Ok(if *v { 1.0 } else { 0.0 }),
        ConstEvalValue::Int(v) => Ok(*v as f64),
        ConstEvalValue::Float(v) => Ok(*v),
        ConstEvalValue::Aggregate { .. } => unsupported("aggregate constant is not numeric"),
    }
}

fn const_as_i64(value: &ConstEvalValue) -> Result<i64, String> {
    match value {
        ConstEvalValue::Bool(v) => Ok(if *v { 1 } else { 0 }),
        ConstEvalValue::Int(v) => Ok(*v),
        ConstEvalValue::Float(v) => Ok(*v as i64),
        ConstEvalValue::Aggregate { .. } => unsupported("aggregate constant is not integer-like"),
    }
}

fn cast_const_value_to_type(
    value: ConstEvalValue,
    ty: &NativeTypeRefMeta,
    enums: &HashMap<String, EnumEvalInfo>,
) -> Result<ConstEvalValue, String> {
    let target = match ty {
        NativeTypeRefMeta::Path(name) => {
            if enums.contains_key(name) || name.ends_with(".Tag") {
                NativeTypeRefMeta::Scalar("i32".to_string())
            } else {
                ty.clone()
            }
        }
        _ => ty.clone(),
    };
    match target {
        NativeTypeRefMeta::Scalar(name) => {
            let scalar = ScalarType::from_name(&name).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}unsupported scalar constant cast target '{name}'")
            })?;
            Ok(match scalar {
                ScalarType::Bool => ConstEvalValue::Bool(const_truthy(&value)),
                ScalarType::F32 | ScalarType::F64 => ConstEvalValue::Float(const_as_f64(&value)?),
                ScalarType::Void => {
                    return Err(format!("{UNSUPPORTED_PREFIX}cannot cast a constant to void"))
                }
                _ => ConstEvalValue::Int(const_as_i64(&value)?),
            })
        }
        NativeTypeRefMeta::Pointer(_) => Ok(ConstEvalValue::Int(const_as_i64(&value)?)),
        NativeTypeRefMeta::Path(name) if enums.contains_key(&name) || name.ends_with(".Tag") => {
            Ok(ConstEvalValue::Int(const_as_i64(&value)?))
        }
        _ => Ok(value),
    }
}

struct ExportEvalState<'a> {
    const_decls: HashMap<String, &'a crate::ast::ConstDecl>,
    const_types: HashMap<String, NativeTypeRefMeta>,
    const_values: HashMap<String, ConstEvalValue>,
    type_stack: HashSet<String>,
    value_stack: HashSet<String>,
    aliases: HashMap<String, NativeTypeRefMeta>,
    enums: HashMap<String, EnumEvalInfo>,
    taggeds: &'a HashMap<String, TaggedUnionLayout>,
    structs: &'a HashMap<String, StructLayout>,
}

impl<'a> ExportEvalState<'a> {
    fn resolve_type_ref(&mut self, ty: &TypeExpr) -> Result<NativeTypeRefMeta, String> {
        match ty {
            TypeExpr::Path(path) => {
                let key = type_path_key(path);
                if ScalarType::from_name(&key).is_some() {
                    Ok(NativeTypeRefMeta::Scalar(key))
                } else {
                    Ok(NativeTypeRefMeta::Path(key))
                }
            }
            TypeExpr::Pointer { inner, .. } => Ok(NativeTypeRefMeta::Pointer(Box::new(
                self.resolve_type_ref(inner)?,
            ))),
            TypeExpr::Array { len, elem, .. } => Ok(NativeTypeRefMeta::Array {
                elem: Box::new(self.resolve_type_ref(elem)?),
                len: const_as_i64(&self.eval_expr(len, &HashMap::new(), &HashMap::new())?)
                    .map_err(|_| {
                        format!("{UNSUPPORTED_PREFIX}native module metadata requires constant array lengths")
                    })?
                    .try_into()
                    .map_err(|_| {
                        format!("{UNSUPPORTED_PREFIX}native module metadata requires non-negative array lengths")
                    })?,
            }),
            TypeExpr::Slice { elem, .. } => Ok(NativeTypeRefMeta::Slice(Box::new(
                self.resolve_type_ref(elem)?,
            ))),
            TypeExpr::Func { params, result, .. } => Ok(NativeTypeRefMeta::Func {
                params: params
                    .iter()
                    .map(|v| self.resolve_type_ref(v))
                    .collect::<Result<Vec<_>, _>>()?,
                result: result
                    .as_ref()
                    .map(|v| self.resolve_type_ref(v))
                    .transpose()?
                    .map(Box::new),
            }),
            TypeExpr::Group { inner, .. } => self.resolve_type_ref(inner),
            _ => unsupported("type form is not yet supported by native module metadata"),
        }
    }

    fn tagged_variant_value(&self, path: &Path) -> Option<ConstEvalValue> {
        match path.segments.as_slice() {
            [tagged_name, variant_name] => {
                let tagged = self.taggeds.get(tagged_name)?;
                Some(ConstEvalValue::Int(*tagged.variant_tags.get(variant_name)? as i64))
            }
            [tagged_name, tag_name, variant_name] if tag_name == "Tag" => {
                let tagged = self.taggeds.get(tagged_name)?;
                Some(ConstEvalValue::Int(*tagged.variant_tags.get(variant_name)? as i64))
            }
            _ => None,
        }
    }

    fn tagged_variant_type(&self, path: &Path) -> Option<NativeTypeRefMeta> {
        match path.segments.as_slice() {
            [tagged_name, variant_name] => {
                let tagged = self.taggeds.get(tagged_name)?;
                tagged.variant_tags.get(variant_name)?;
                Some(NativeTypeRefMeta::Path(format!("{}.Tag", tagged_name)))
            }
            [tagged_name, tag_name, variant_name] if tag_name == "Tag" => {
                let tagged = self.taggeds.get(tagged_name)?;
                tagged.variant_tags.get(variant_name)?;
                Some(NativeTypeRefMeta::Path(format!("{}.Tag", tagged_name)))
            }
            _ => None,
        }
    }

    fn size_align_of_type_ref(&self, ty: &NativeTypeRefMeta) -> Result<(u32, u32), String> {
        match ty {
            NativeTypeRefMeta::Scalar(name) => {
                let scalar = ScalarType::from_name(name).ok_or_else(|| {
                    format!("{UNSUPPORTED_PREFIX}unknown scalar type '{name}'")
                })?;
                Ok((scalar_size(scalar), scalar_align(scalar)))
            }
            NativeTypeRefMeta::Pointer(_) => Ok((8, 8)),
            NativeTypeRefMeta::Array { elem, len } => {
                let (elem_size, elem_align) = self.size_align_of_type_ref(elem)?;
                Ok((elem_size.saturating_mul(*len), elem_align))
            }
            NativeTypeRefMeta::Slice(_) => Ok((16, 8)),
            NativeTypeRefMeta::Func { .. } => Ok((8, 8)),
            NativeTypeRefMeta::Path(name) => {
                if let Some(alias) = self.aliases.get(name) {
                    return self.size_align_of_type_ref(alias);
                }
                if let Some(en) = self.enums.get(name) {
                    return self.size_align_of_type_ref(&en.base);
                }
                if let Some(layout) = self.structs.get(name) {
                    return Ok((layout.size, layout.align));
                }
                if let Some(layout) = self.taggeds.get(name) {
                    return Ok((layout.size, layout.align));
                }
                if let Some(tagged_name) = name.strip_suffix(".Tag") {
                    if let Some(layout) = self.taggeds.get(tagged_name) {
                        return Ok((scalar_size(layout.tag_ty), scalar_align(layout.tag_ty)));
                    }
                }
                Err(format!("{UNSUPPORTED_PREFIX}unknown type path '{name}' for sizeof/alignof"))
            }
        }
    }

    fn field_offset_of_type_ref(&self, ty: &NativeTypeRefMeta, field_name: &str) -> Result<u32, String> {
        match ty {
            NativeTypeRefMeta::Path(name) => {
                if let Some(alias) = self.aliases.get(name) {
                    return self.field_offset_of_type_ref(alias, field_name);
                }
                if let Some(layout) = self.structs.get(name) {
                    let field = layout.fields.get(field_name).ok_or_else(|| {
                        format!("{UNSUPPORTED_PREFIX}layout '{}' has no field '{}'", layout.name, field_name)
                    })?;
                    return Ok(field.offset);
                }
                if let Some(layout) = self.taggeds.get(name) {
                    return match field_name {
                        "tag" => Ok(0),
                        "payload" => Ok(layout.payload_offset),
                        _ => Err(format!(
                            "{UNSUPPORTED_PREFIX}tagged union '{}' has no field '{}'",
                            layout.name, field_name
                        )),
                    };
                }
                Err(format!("{UNSUPPORTED_PREFIX}unknown type path '{}' for offsetof", name))
            }
            _ => unsupported("offsetof currently requires a struct/union/tagged union or alias type"),
        }
    }

    fn infer_named_const_type(&mut self, name: &str) -> Result<NativeTypeRefMeta, String> {
        if let Some(ty) = self.const_types.get(name) {
            return Ok(ty.clone());
        }
        if !self.type_stack.insert(name.to_string()) {
            return Err(format!(
                "{UNSUPPORTED_PREFIX}recursive const type inference for '{}' is not supported",
                name
            ));
        }
        let result = (|| {
            let decl = *self.const_decls.get(name).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}unknown const '{name}'")
            })?;
            if let Some(ty) = &decl.ty {
                self.resolve_type_ref(ty)
            } else {
                self.infer_expr_type(&decl.value, &HashMap::new())
            }
        })();
        self.type_stack.remove(name);
        let ty = result?;
        self.const_types.insert(name.to_string(), ty.clone());
        Ok(ty)
    }

    fn eval_named_const(&mut self, name: &str) -> Result<ConstEvalValue, String> {
        if let Some(value) = self.const_values.get(name) {
            return Ok(value.clone());
        }
        if !self.value_stack.insert(name.to_string()) {
            return Err(format!(
                "{UNSUPPORTED_PREFIX}recursive const '{}' is not supported natively",
                name
            ));
        }
        let result = (|| {
            let decl = *self.const_decls.get(name).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}unknown const '{name}'")
            })?;
            let ty = self.infer_named_const_type(name)?;
            let value = self.eval_expr(&decl.value, &HashMap::new(), &HashMap::new())?;
            cast_const_value_to_type(value, &ty, &self.enums)
        })();
        self.value_stack.remove(name);
        let value = result?;
        self.const_values.insert(name.to_string(), value.clone());
        Ok(value)
    }

    fn infer_path_type(
        &mut self,
        path: &Path,
        local_types: &HashMap<String, NativeTypeRefMeta>,
    ) -> Result<NativeTypeRefMeta, String> {
        match path.segments.as_slice() {
            [name] => {
                if let Some(ty) = local_types.get(name) {
                    return Ok(ty.clone());
                }
                if self.const_decls.contains_key(name) {
                    return self.infer_named_const_type(name);
                }
                Err(format!("{UNSUPPORTED_PREFIX}unknown const path '{name}'"))
            }
            [enum_name, member] => {
                if self
                    .enums
                    .get(enum_name)
                    .and_then(|en| en.members.get(member))
                    .is_some()
                {
                    Ok(NativeTypeRefMeta::Path(enum_name.clone()))
                } else {
                    self.tagged_variant_type(path).ok_or_else(|| {
                        format!("{UNSUPPORTED_PREFIX}unknown const path '{}'", type_path_key(path))
                    })
                }
            }
            [..] => self.tagged_variant_type(path).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}unknown const path '{}'", type_path_key(path))
            }),
        }
    }

    fn eval_path(
        &mut self,
        path: &Path,
        local_values: &HashMap<String, ConstEvalValue>,
    ) -> Result<ConstEvalValue, String> {
        match path.segments.as_slice() {
            [name] => {
                if let Some(value) = local_values.get(name) {
                    return Ok(value.clone());
                }
                if self.const_decls.contains_key(name) {
                    return self.eval_named_const(name);
                }
                Err(format!("{UNSUPPORTED_PREFIX}unknown const path '{name}'"))
            }
            [enum_name, member] => {
                if let Some(value) = self
                    .enums
                    .get(enum_name)
                    .and_then(|en| en.members.get(member))
                {
                    Ok(ConstEvalValue::Int(*value))
                } else {
                    self.tagged_variant_value(path).ok_or_else(|| {
                        format!("{UNSUPPORTED_PREFIX}unknown const path '{}'", type_path_key(path))
                    })
                }
            }
            [..] => self.tagged_variant_value(path).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}unknown const path '{}'", type_path_key(path))
            }),
        }
    }

    fn infer_expr_type(
        &mut self,
        expr: &AstExpr,
        local_types: &HashMap<String, NativeTypeRefMeta>,
    ) -> Result<NativeTypeRefMeta, String> {
        match &expr.kind {
            ExprKind::Number(v) => Ok(NativeTypeRefMeta::Scalar(match v.kind {
                NumberKind::Int => "i32".to_string(),
                NumberKind::Float => "f64".to_string(),
            })),
            ExprKind::Bool(_) => Ok(NativeTypeRefMeta::Scalar("bool".to_string())),
            ExprKind::Path(path) => self.infer_path_type(path, local_types),
            ExprKind::If(v) => {
                let mut out = None;
                for branch in &v.branches {
                    let ty = self.infer_expr_type(&branch.value, local_types)?;
                    out = Some(match out {
                        None => ty,
                        Some(prev) if prev == ty => ty,
                        Some(prev) => {
                            return Err(format!(
                                "{UNSUPPORTED_PREFIX}const if branches have incompatible types: {:?} vs {:?}",
                                prev, ty
                            ))
                        }
                    });
                }
                let else_ty = self.infer_expr_type(&v.else_branch, local_types)?;
                match out {
                    None => Ok(else_ty),
                    Some(prev) if prev == else_ty => Ok(else_ty),
                    Some(prev) => Err(format!(
                        "{UNSUPPORTED_PREFIX}const if branches have incompatible types: {:?} vs {:?}",
                        prev, else_ty
                    )),
                }
            }
            ExprKind::Switch(v) => {
                let out = self.infer_expr_type(&v.default, local_types)?;
                for case in &v.cases {
                    let ty = self.infer_expr_type(&case.body, local_types)?;
                    if ty != out {
                        return Err(format!(
                            "{UNSUPPORTED_PREFIX}const switch branches have incompatible types: {:?} vs {:?}",
                            out, ty
                        ));
                    }
                }
                Ok(out)
            }
            ExprKind::Unary { op, expr } => match op {
                AstUnaryOp::Not => Ok(NativeTypeRefMeta::Scalar("bool".to_string())),
                AstUnaryOp::Neg | AstUnaryOp::BitNot => self.infer_expr_type(expr, local_types),
                _ => unsupported("const unary operator is not supported natively"),
            },
            ExprKind::Binary { op, lhs, rhs } => match op {
                AstBinaryOp::Eq
                | AstBinaryOp::Ne
                | AstBinaryOp::Lt
                | AstBinaryOp::Le
                | AstBinaryOp::Gt
                | AstBinaryOp::Ge
                | AstBinaryOp::And
                | AstBinaryOp::Or => Ok(NativeTypeRefMeta::Scalar("bool".to_string())),
                _ => {
                    let lhs_ty = self.infer_expr_type(lhs, local_types).ok();
                    let rhs_ty = self.infer_expr_type(rhs, local_types).ok();
                    if let Some(ty) = lhs_ty.or(rhs_ty) {
                        Ok(ty)
                    } else {
                        Ok(NativeTypeRefMeta::Scalar("i32".to_string()))
                    }
                }
            },
            ExprKind::Cast { ty, .. } => self.resolve_type_ref(ty),
            ExprKind::SizeOf(_) | ExprKind::AlignOf(_) | ExprKind::OffsetOf { .. } => {
                Ok(NativeTypeRefMeta::Scalar("usize".to_string()))
            }
            ExprKind::Aggregate { ctor, .. } => match ctor {
                TypeCtor::Array { len, elem, .. } => Ok(NativeTypeRefMeta::Array {
                    elem: Box::new(self.resolve_type_ref(elem)?),
                    len: const_as_i64(&self.eval_expr(len, &HashMap::new(), &HashMap::new())?)
                        .map_err(|_| {
                            format!("{UNSUPPORTED_PREFIX}const aggregate arrays require constant lengths")
                        })?
                        .try_into()
                        .map_err(|_| {
                            format!("{UNSUPPORTED_PREFIX}const aggregate arrays require non-negative lengths")
                        })?,
                }),
                TypeCtor::Path(path) => {
                    if let Some((tagged_name, _)) = tagged_variant_ctor_name(path, self.taggeds) {
                        Ok(NativeTypeRefMeta::Path(tagged_name))
                    } else {
                        Ok(NativeTypeRefMeta::Path(type_path_key(path)))
                    }
                }
            },
            _ => unsupported("const expression type inference is not supported for this form"),
        }
    }

    fn eval_expr(
        &mut self,
        expr: &AstExpr,
        local_values: &HashMap<String, ConstEvalValue>,
        local_types: &HashMap<String, NativeTypeRefMeta>,
    ) -> Result<ConstEvalValue, String> {
        match &expr.kind {
            ExprKind::Number(v) => Ok(match v.kind {
                NumberKind::Int => ConstEvalValue::Int(v.raw.parse::<i64>().map_err(|_| {
                    format!("{UNSUPPORTED_PREFIX}failed to parse integer literal {:?}", v.raw)
                })?),
                NumberKind::Float => ConstEvalValue::Float(v.raw.parse::<f64>().map_err(|_| {
                    format!("{UNSUPPORTED_PREFIX}failed to parse float literal {:?}", v.raw)
                })?),
            }),
            ExprKind::Bool(v) => Ok(ConstEvalValue::Bool(*v)),
            ExprKind::Path(path) => self.eval_path(path, local_values),
            ExprKind::If(v) => {
                for branch in &v.branches {
                    if const_truthy(&self.eval_expr(&branch.cond, local_values, local_types)?) {
                        return self.eval_expr(&branch.value, local_values, local_types);
                    }
                }
                self.eval_expr(&v.else_branch, local_values, local_types)
            }
            ExprKind::Switch(v) => {
                let key = self.eval_expr(&v.value, local_values, local_types)?;
                let key_num = const_as_i64(&key)?;
                for case in &v.cases {
                    if key_num == const_as_i64(&self.eval_expr(&case.value, local_values, local_types)?)? {
                        return self.eval_expr(&case.body, local_values, local_types);
                    }
                }
                self.eval_expr(&v.default, local_values, local_types)
            }
            ExprKind::Unary { op, expr } => {
                let value = self.eval_expr(expr, local_values, local_types)?;
                match op {
                    AstUnaryOp::Neg => match value {
                        ConstEvalValue::Int(v) => Ok(ConstEvalValue::Int(-v)),
                        _ => Ok(ConstEvalValue::Float(-const_as_f64(&value)?)),
                    },
                    AstUnaryOp::Not => Ok(ConstEvalValue::Bool(!const_truthy(&value))),
                    AstUnaryOp::BitNot => Ok(ConstEvalValue::Int(!const_as_i64(&value)?)),
                    _ => unsupported("const unary operator is not supported natively"),
                }
            }
            ExprKind::Binary { op, lhs, rhs } => {
                let lhs = self.eval_expr(lhs, local_values, local_types)?;
                let rhs = self.eval_expr(rhs, local_values, local_types)?;
                use AstBinaryOp as B;
                Ok(match op {
                    B::Add => match (&lhs, &rhs) {
                        (ConstEvalValue::Int(a), ConstEvalValue::Int(b)) => ConstEvalValue::Int(a + b),
                        _ => ConstEvalValue::Float(const_as_f64(&lhs)? + const_as_f64(&rhs)?),
                    },
                    B::Sub => match (&lhs, &rhs) {
                        (ConstEvalValue::Int(a), ConstEvalValue::Int(b)) => ConstEvalValue::Int(a - b),
                        _ => ConstEvalValue::Float(const_as_f64(&lhs)? - const_as_f64(&rhs)?),
                    },
                    B::Mul => match (&lhs, &rhs) {
                        (ConstEvalValue::Int(a), ConstEvalValue::Int(b)) => ConstEvalValue::Int(a * b),
                        _ => ConstEvalValue::Float(const_as_f64(&lhs)? * const_as_f64(&rhs)?),
                    },
                    B::Div => ConstEvalValue::Float(const_as_f64(&lhs)? / const_as_f64(&rhs)?),
                    B::Rem => match (&lhs, &rhs) {
                        (ConstEvalValue::Int(a), ConstEvalValue::Int(b)) => ConstEvalValue::Int(a % b),
                        _ => ConstEvalValue::Float(const_as_f64(&lhs)? % const_as_f64(&rhs)?),
                    },
                    B::Eq => ConstEvalValue::Bool(const_as_f64(&lhs)? == const_as_f64(&rhs)?),
                    B::Ne => ConstEvalValue::Bool(const_as_f64(&lhs)? != const_as_f64(&rhs)?),
                    B::Lt => ConstEvalValue::Bool(const_as_f64(&lhs)? < const_as_f64(&rhs)?),
                    B::Le => ConstEvalValue::Bool(const_as_f64(&lhs)? <= const_as_f64(&rhs)?),
                    B::Gt => ConstEvalValue::Bool(const_as_f64(&lhs)? > const_as_f64(&rhs)?),
                    B::Ge => ConstEvalValue::Bool(const_as_f64(&lhs)? >= const_as_f64(&rhs)?),
                    B::And => {
                        if const_truthy(&lhs) { rhs } else { lhs }
                    }
                    B::Or => {
                        if const_truthy(&lhs) { lhs } else { rhs }
                    }
                    B::BitAnd => ConstEvalValue::Int(const_as_i64(&lhs)? & const_as_i64(&rhs)?),
                    B::BitOr => ConstEvalValue::Int(const_as_i64(&lhs)? | const_as_i64(&rhs)?),
                    B::BitXor => ConstEvalValue::Int(const_as_i64(&lhs)? ^ const_as_i64(&rhs)?),
                    B::Shl => ConstEvalValue::Int(const_as_i64(&lhs)? << (const_as_i64(&rhs)? as u32)),
                    B::Shr | B::ShrU => ConstEvalValue::Int(const_as_i64(&lhs)? >> (const_as_i64(&rhs)? as u32)),
                })
            }
            ExprKind::SizeOf(ty) => {
                let ty_ref = self.resolve_type_ref(ty)?;
                Ok(ConstEvalValue::Int(self.size_align_of_type_ref(&ty_ref)?.0 as i64))
            }
            ExprKind::AlignOf(ty) => {
                let ty_ref = self.resolve_type_ref(ty)?;
                Ok(ConstEvalValue::Int(self.size_align_of_type_ref(&ty_ref)?.1 as i64))
            }
            ExprKind::OffsetOf { ty, field } => {
                let ty_ref = self.resolve_type_ref(ty)?;
                Ok(ConstEvalValue::Int(self.field_offset_of_type_ref(&ty_ref, field)? as i64))
            }
            ExprKind::Cast { ty, value, .. } => {
                let value = self.eval_expr(value, local_values, local_types)?;
                cast_const_value_to_type(value, &self.resolve_type_ref(ty)?, &self.enums)
            }
            ExprKind::Aggregate { ctor, fields } => match ctor {
                TypeCtor::Array { .. } => Ok(ConstEvalValue::Aggregate {
                    fields: fields
                        .iter()
                        .map(|field| match field {
                            crate::ast::AggregateField::Named { .. } => unsupported(
                                "const array aggregates require positional entries",
                            ),
                            crate::ast::AggregateField::Positional { value, .. } => Ok::<ConstEvalField, String>(ConstEvalField {
                                name: None,
                                value: self.eval_expr(value, local_values, local_types)?,
                            }),
                        })
                        .collect::<Result<Vec<_>, _>>()?,
                }),
                TypeCtor::Path(path) => {
                    if let Some((_tagged_name, variant_name)) = tagged_variant_ctor_name(path, self.taggeds) {
                        let tag_value = self
                            .tagged_variant_value(path)
                            .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown tagged variant '{}'", type_path_key(path)))?;
                        let payload_fields = fields
                            .iter()
                            .map(|field| match field {
                                crate::ast::AggregateField::Named { name, value, .. } => Ok::<ConstEvalField, String>(ConstEvalField {
                                    name: Some(name.clone()),
                                    value: self.eval_expr(value, local_values, local_types)?,
                                }),
                                crate::ast::AggregateField::Positional { .. } => unsupported(
                                    "const tagged variant aggregates require named fields",
                                ),
                            })
                            .collect::<Result<Vec<_>, _>>()?;
                        return Ok(ConstEvalValue::Aggregate {
                            fields: vec![
                                ConstEvalField {
                                    name: Some("tag".to_string()),
                                    value: tag_value,
                                },
                                ConstEvalField {
                                    name: Some("payload".to_string()),
                                    value: ConstEvalValue::Aggregate {
                                        fields: vec![ConstEvalField {
                                            name: Some(variant_name),
                                            value: ConstEvalValue::Aggregate {
                                                fields: payload_fields,
                                            },
                                        }],
                                    },
                                },
                            ],
                        });
                    }
                    Ok(ConstEvalValue::Aggregate {
                        fields: fields
                            .iter()
                            .map(|field| match field {
                                crate::ast::AggregateField::Named { name, value, .. } => Ok::<ConstEvalField, String>(ConstEvalField {
                                    name: Some(name.clone()),
                                    value: self.eval_expr(value, local_values, local_types)?,
                                }),
                                crate::ast::AggregateField::Positional { value, .. } => Ok::<ConstEvalField, String>(ConstEvalField {
                                    name: None,
                                    value: self.eval_expr(value, local_values, local_types)?,
                                }),
                            })
                            .collect::<Result<Vec<_>, _>>()?,
                    })
                }
            },
            _ => unsupported("const expression form is not supported by native module metadata"),
        }
    }
}

fn attr_string(item: &Item, name: &str) -> Option<String> {
    let attr = item.attributes.iter().find(|attr| attr.name == name)?;
    let first = attr.args.first()?;
    Some(match first {
        AttrArg::Ident(v) | AttrArg::Number(v) | AttrArg::String(v) => v.clone(),
    })
}

fn extern_symbol(item: &Item, decl: &ExternFuncDecl) -> String {
    attr_string(item, "link_name").unwrap_or_else(|| decl.name.clone())
}

fn func_name_symbol(func: &FuncDecl) -> Result<String, String> {
    match &func.sig.name {
        FuncName::Named(name) => Ok(name.clone()),
        FuncName::Anonymous => unsupported("anonymous funcs are not yet supported natively"),
        FuncName::Method { .. } => unsupported("methods are not yet supported natively"),
    }
}

fn scalar_size(ty: ScalarType) -> u32 {
    match ty {
        ScalarType::Void => 0,
        ScalarType::Bool | ScalarType::I8 | ScalarType::U8 => 1,
        ScalarType::I16 | ScalarType::U16 => 2,
        ScalarType::I32 | ScalarType::U32 | ScalarType::F32 => 4,
        ScalarType::I64 | ScalarType::U64 | ScalarType::F64 | ScalarType::Ptr => 8,
    }
}

fn scalar_align(ty: ScalarType) -> u32 {
    scalar_size(ty).max(1)
}

fn align_up(value: u32, align: u32) -> u32 {
    let align = align.max(1);
    (value + (align - 1)) & !(align - 1)
}

fn type_path_key(path: &Path) -> String {
    path.segments.join(".")
}

fn layout_name_from_type_expr(
    ty: &TypeExpr,
    structs: &HashMap<String, StructLayout>,
    taggeds: &HashMap<String, TaggedUnionLayout>,
) -> Option<String> {
    let TypeExpr::Path(path) = ty else {
        return None;
    };
    let key = type_path_key(path);
    if structs.contains_key(&key) || taggeds.contains_key(&key) {
        Some(key)
    } else {
        None
    }
}

fn pointer_struct_name_from_type_expr(
    ty: &TypeExpr,
    structs: &HashMap<String, StructLayout>,
    taggeds: &HashMap<String, TaggedUnionLayout>,
) -> Option<String> {
    let TypeExpr::Pointer { inner, .. } = ty else {
        return None;
    };
    layout_name_from_type_expr(inner, structs, taggeds)
}

fn pointer_elem_scalar_from_type_expr(ty: &TypeExpr) -> Option<ScalarType> {
    let TypeExpr::Pointer { inner, .. } = ty else {
        return None;
    };
    scalar_type_from_type_expr(inner).ok()
}

fn eval_const_u32(expr: &AstExpr) -> Option<u32> {
    match &expr.kind {
        ExprKind::Number(v) if v.kind == NumberKind::Int => v.raw.parse::<i64>().ok().and_then(|n| {
            if n >= 0 && n <= u32::MAX as i64 {
                Some(n as u32)
            } else {
                None
            }
        }),
        ExprKind::Unary { op: AstUnaryOp::Neg, expr } => {
            let n = eval_const_u32(expr)? as i64;
            if -n >= 0 { Some((-n) as u32) } else { None }
        }
        ExprKind::Binary { op, lhs, rhs } => {
            let l = eval_const_u32(lhs)? as i64;
            let r = eval_const_u32(rhs)? as i64;
            let out = match op {
                AstBinaryOp::Add => l.checked_add(r)?,
                AstBinaryOp::Sub => l.checked_sub(r)?,
                AstBinaryOp::Mul => l.checked_mul(r)?,
                AstBinaryOp::Div => {
                    if r == 0 { return None; }
                    l.checked_div(r)?
                }
                AstBinaryOp::Rem => {
                    if r == 0 { return None; }
                    l.checked_rem(r)?
                }
                _ => return None,
            };
            if out >= 0 && out <= u32::MAX as i64 { Some(out as u32) } else { None }
        }
        ExprKind::Cast { value, .. } => eval_const_u32(value),
        _ => None,
    }
}

fn array_layout_from_type_expr(ty: &TypeExpr) -> Option<ArrayLayout> {
    let TypeExpr::Array { len, elem, .. } = ty else {
        return None;
    };
    let elem_ty = scalar_type_from_type_expr(elem).ok()?;
    let count = eval_const_u32(len)?;
    Some(ArrayLayout {
        elem_ty,
        count,
        size: scalar_size(elem_ty).saturating_mul(count),
        align: scalar_align(elem_ty),
    })
}

fn aggregate_ctor_array_layout(expr: &AstExpr) -> Option<ArrayLayout> {
    let ExprKind::Aggregate { ctor, .. } = &expr.kind else {
        return None;
    };
    let TypeCtor::Array { len, elem, .. } = ctor else {
        return None;
    };
    let elem_ty = scalar_type_from_type_expr(elem).ok()?;
    let count = eval_const_u32(len)?;
    Some(ArrayLayout {
        elem_ty,
        count,
        size: scalar_size(elem_ty).saturating_mul(count),
        align: scalar_align(elem_ty),
    })
}

fn tagged_variant_ctor_name(
    path: &Path,
    taggeds: &HashMap<String, TaggedUnionLayout>,
) -> Option<(String, String)> {
    match path.segments.as_slice() {
        [tagged_name, variant_name] => {
            let layout = taggeds.get(tagged_name)?;
            if layout.variant_tags.contains_key(variant_name) {
                Some((tagged_name.clone(), variant_name.clone()))
            } else {
                None
            }
        }
        [tagged_name, payload_name, variant_name] if payload_name == "Payload" => {
            let layout = taggeds.get(tagged_name)?;
            if layout.variant_tags.contains_key(variant_name) {
                Some((tagged_name.clone(), variant_name.clone()))
            } else {
                None
            }
        }
        _ => None,
    }
}

fn aggregate_ctor_layout_name(
    expr: &AstExpr,
    structs: &HashMap<String, StructLayout>,
    taggeds: &HashMap<String, TaggedUnionLayout>,
) -> Option<String> {
    let ExprKind::Aggregate { ctor, .. } = &expr.kind else {
        return None;
    };
    match ctor {
        TypeCtor::Path(path) => {
            let key = type_path_key(path);
            if structs.contains_key(&key) || taggeds.contains_key(&key) {
                Some(key)
            } else {
                tagged_variant_ctor_name(path, taggeds).map(|(tagged_name, _)| tagged_name)
            }
        }
        _ => None,
    }
}

fn type_size_align_from_type_expr(
    ty: &TypeExpr,
    structs: &HashMap<String, StructLayout>,
    taggeds: &HashMap<String, TaggedUnionLayout>,
) -> Result<(u32, u32), String> {
    if let Ok(scalar) = scalar_type_from_type_expr(ty) {
        return Ok((scalar_size(scalar), scalar_align(scalar)));
    }
    if let Some(array_layout) = array_layout_from_type_expr(ty) {
        return Ok((array_layout.size, array_layout.align));
    }
    if let Some(layout_name) = layout_name_from_type_expr(ty, structs, taggeds) {
        if let Some(layout) = structs.get(&layout_name) {
            return Ok((layout.size, layout.align));
        }
        if let Some(layout) = taggeds.get(&layout_name) {
            return Ok((layout.size, layout.align));
        }
    }
    unsupported("sizeof/alignof currently require a scalar, pointer, array, struct/union, or tagged union type")
}

fn field_offset_from_type_expr(
    ty: &TypeExpr,
    field_name: &str,
    structs: &HashMap<String, StructLayout>,
    taggeds: &HashMap<String, TaggedUnionLayout>,
) -> Result<u32, String> {
    if let Some(layout_name) = layout_name_from_type_expr(ty, structs, taggeds) {
        if let Some(layout) = structs.get(&layout_name) {
            let field = layout.fields.get(field_name).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}layout '{}' has no field '{}'", layout.name, field_name)
            })?;
            return Ok(field.offset);
        }
        if let Some(layout) = taggeds.get(&layout_name) {
            return match field_name {
                "tag" => Ok(0),
                "payload" => Ok(layout.payload_offset),
                _ => Err(format!(
                    "{UNSUPPORTED_PREFIX}tagged union '{}' has no field '{}'",
                    layout.name, field_name
                )),
            };
        }
    }
    unsupported("offsetof currently requires a struct/union or tagged union type")
}

fn collect_struct_layouts(module: &ModuleAst) -> Result<HashMap<String, StructLayout>, String> {
    let mut out = HashMap::new();
    for item in &module.items {
        match &item.kind {
            ItemKind::Struct(decl) => {
                let name = &decl.name;
                let union_kind = false;
                let mut fields = HashMap::new();
                let mut offset = 0u32;
                let mut max_align = 1u32;
                let mut max_size = 0u32;
                for field in &decl.fields {
                    let field_ty = scalar_type_from_type_expr(&field.ty).map_err(|_| {
                        format!(
                            "{UNSUPPORTED_PREFIX}native relaxed struct/union fields currently support only scalar/pointer types"
                        )
                    })?;
                    let field_align = scalar_align(field_ty);
                    let field_size = scalar_size(field_ty);
                    max_align = max_align.max(field_align);
                    let field_offset = if union_kind { 0 } else { align_up(offset, field_align) };
                    if fields.contains_key(&field.name) {
                        return Err(format!("duplicate native field '{}.{}'", name, field.name));
                    }
                    fields.insert(
                        field.name.clone(),
                        StructFieldInfo {
                            ty: field_ty,
                            offset: field_offset,
                        },
                    );
                    if union_kind {
                        max_size = max_size.max(field_size);
                    } else {
                        offset = field_offset + field_size;
                    }
                }
                let size = align_up(offset, max_align);
                out.insert(
                    name.clone(),
                    StructLayout {
                        name: name.clone(),
                        fields,
                        size,
                        align: max_align,
                        slice_elem_ty: None,
                    },
                );
            }
            ItemKind::Union(decl) => {
                let name = &decl.name;
                let union_kind = true;
                let mut fields = HashMap::new();
                let mut offset = 0u32;
                let mut max_align = 1u32;
                let mut max_size = 0u32;
                for field in &decl.fields {
                    let field_ty = scalar_type_from_type_expr(&field.ty).map_err(|_| {
                        format!(
                            "{UNSUPPORTED_PREFIX}native relaxed struct/union fields currently support only scalar/pointer types"
                        )
                    })?;
                    let field_align = scalar_align(field_ty);
                    let field_size = scalar_size(field_ty);
                    max_align = max_align.max(field_align);
                    let field_offset = if union_kind { 0 } else { align_up(offset, field_align) };
                    if fields.contains_key(&field.name) {
                        return Err(format!("duplicate native field '{}.{}'", name, field.name));
                    }
                    fields.insert(
                        field.name.clone(),
                        StructFieldInfo {
                            ty: field_ty,
                            offset: field_offset,
                        },
                    );
                    if union_kind {
                        max_size = max_size.max(field_size);
                    } else {
                        offset = field_offset + field_size;
                    }
                }
                let size = align_up(max_size, max_align);
                out.insert(
                    name.clone(),
                    StructLayout {
                        name: name.clone(),
                        fields,
                        size,
                        align: max_align,
                        slice_elem_ty: None,
                    },
                );
            }
            ItemKind::Slice(decl) => {
                let elem_ty = scalar_type_from_type_expr(&decl.ty).map_err(|_| {
                    format!(
                        "{UNSUPPORTED_PREFIX}native slice declarations currently support only scalar/pointer element types"
                    )
                })?;
                let mut fields = HashMap::new();
                fields.insert(
                    "ptr".to_string(),
                    StructFieldInfo {
                        ty: ScalarType::Ptr,
                        offset: 0,
                    },
                );
                fields.insert(
                    "len".to_string(),
                    StructFieldInfo {
                        ty: ScalarType::U64,
                        offset: 8,
                    },
                );
                out.insert(
                    decl.name.clone(),
                    StructLayout {
                        name: decl.name.clone(),
                        fields,
                        size: 16,
                        align: 8,
                        slice_elem_ty: Some(elem_ty),
                    },
                );
            }
            _ => {}
        }
    }
    Ok(out)
}

fn collect_tagged_union_layouts(module: &ModuleAst) -> Result<HashMap<String, TaggedUnionLayout>, String> {
    let mut out = HashMap::new();
    for item in &module.items {
        let ItemKind::TaggedUnion(decl) = &item.kind else {
            continue;
        };
        let tag_ty = decl
            .base_ty
            .as_ref()
            .map(scalar_type_from_type_expr)
            .transpose()?
            .unwrap_or(ScalarType::U8);
        let tag_size = scalar_size(tag_ty);
        let tag_align = scalar_align(tag_ty);
        let mut variants = HashMap::new();
        let mut variant_tags = HashMap::new();
        let mut max_variant_size = 0u32;
        let mut max_variant_align = 1u32;
        for (variant_index, variant) in decl.variants.iter().enumerate() {
            let variant_name = format!("{}.Payload.{}", decl.name, variant.name);
            let mut fields = HashMap::new();
            let mut offset = 0u32;
            let mut align = 1u32;
            for field in &variant.fields {
                let field_ty = scalar_type_from_type_expr(&field.ty).map_err(|_| {
                    format!(
                        "{UNSUPPORTED_PREFIX}native tagged union payload fields currently support only scalar/pointer types"
                    )
                })?;
                let field_align = scalar_align(field_ty);
                let field_size = scalar_size(field_ty);
                align = align.max(field_align);
                offset = align_up(offset, field_align);
                fields.insert(
                    field.name.clone(),
                    StructFieldInfo {
                        ty: field_ty,
                        offset,
                    },
                );
                offset += field_size;
            }
            let size = align_up(offset, align);
            max_variant_size = max_variant_size.max(size);
            max_variant_align = max_variant_align.max(align);
            variant_tags.insert(variant.name.clone(), variant_index as u64);
            variants.insert(
                variant.name.clone(),
                StructLayout {
                    name: variant_name,
                    fields,
                    size,
                    align,
                    slice_elem_ty: None,
                },
            );
        }
        let payload_align = max_variant_align.max(1);
        let payload_offset = align_up(tag_size, payload_align);
        let payload_size = align_up(max_variant_size, payload_align);
        let size = align_up(payload_offset + payload_size, tag_align.max(payload_align));
        out.insert(
            decl.name.clone(),
            TaggedUnionLayout {
                name: decl.name.clone(),
                tag_ty,
                payload_offset,
                payload_size,
                size,
                align: tag_align.max(payload_align),
                variants,
                variant_tags,
            },
        );
    }
    Ok(out)
}

fn default_number_type(kind: &NumberKind) -> ScalarType {
    match kind {
        NumberKind::Int => ScalarType::I32,
        NumberKind::Float => ScalarType::F64,
    }
}

fn zero_expr(ty: ScalarType) -> Expr {
    Expr::Const { ty, bits: 0 }
}

fn bool_expr(value: bool) -> Expr {
    Expr::Const {
        ty: ScalarType::Bool,
        bits: if value { 1 } else { 0 },
    }
}

fn local_expr(name: impl Into<String>, ty: ScalarType) -> Expr {
    Expr::Local {
        name: name.into(),
        ty,
    }
}

fn arg_expr(index: u32, ty: ScalarType) -> Expr {
    Expr::Arg { index, ty }
}

fn not_expr(value: Expr) -> Expr {
    Expr::Unary {
        op: UnaryOp::Not,
        ty: ScalarType::Bool,
        value: Box::new(value),
    }
}

fn and_expr(lhs: Expr, rhs: Expr) -> Expr {
    Expr::Binary {
        op: BinaryOp::And,
        ty: ScalarType::Bool,
        lhs: Box::new(lhs),
        rhs: Box::new(rhs),
    }
}

fn eq_expr(lhs: Expr, rhs: Expr, operand_ty: ScalarType) -> Expr {
    Expr::Binary {
        op: BinaryOp::Eq,
        ty: ScalarType::Bool,
        lhs: Box::new(cast_if_needed(lhs, operand_ty)),
        rhs: Box::new(cast_if_needed(rhs, operand_ty)),
    }
}

fn cast_if_needed(expr: Expr, ty: ScalarType) -> Expr {
    if expr.ty() == ty {
        expr
    } else {
        Expr::Cast {
            op: CastOp::Cast,
            ty,
            value: Box::new(expr),
        }
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
                _ => unreachable!(),
            })
        }
    }
}

impl<'a> LowerCtx<'a> {
    fn new(
        funcs: &'a HashMap<String, FuncSigInfo>,
        methods: &'a HashMap<String, HashMap<String, FuncSigInfo>>,
        structs: &'a HashMap<String, StructLayout>,
        taggeds: &'a HashMap<String, TaggedUnionLayout>,
    ) -> Self {
        Self {
            scopes: vec![HashMap::new()],
            domain_scopes: vec![HashMap::new()],
            funcs,
            methods,
            structs,
            taggeds,
            next_temp_id: 0,
        }
    }

    fn push_scope(&mut self) {
        self.scopes.push(HashMap::new());
    }

    fn pop_scope(&mut self) {
        self.scopes.pop();
    }

    fn push_domain_scope(&mut self) {
        self.domain_scopes.push(HashMap::new());
    }

    fn pop_domain_scope(&mut self) {
        self.domain_scopes.pop();
    }

    fn bind_domain_override(&mut self, name: &str, base: IndexBaseInfo) {
        self.domain_scopes
            .last_mut()
            .expect("domain scope stack is never empty")
            .insert(name.to_string(), DomainOverrideInfo { base });
    }

    fn lookup_domain_override(&self, name: &str) -> Option<&DomainOverrideInfo> {
        for scope in self.domain_scopes.iter().rev() {
            if let Some(info) = scope.get(name) {
                return Some(info);
            }
        }
        None
    }

    fn bind_param(
        &mut self,
        name: &str,
        ty: ScalarType,
        index: u32,
        struct_name: Option<String>,
        pointer_elem_ty: Option<ScalarType>,
    ) {
        self.scopes[0].insert(
            name.to_string(),
            BindingInfo {
                lowered_name: name.to_string(),
                ty,
                mutable: false,
                arg_index: Some(index),
                stack_slot_name: None,
                struct_name,
                array_layout: None,
                pointer_elem_ty,
            },
        );
    }

    fn bind(
        &mut self,
        name: &str,
        ty: ScalarType,
        mutable: bool,
        struct_name: Option<String>,
        prefix: Option<&str>,
    ) -> BindingInfo {
        let lowered_name = if self.scopes.len() == 1 && self.lookup(name).is_none() {
            name.to_string()
        } else {
            self.fresh_temp(prefix.unwrap_or(name))
        };
        let binding = BindingInfo {
            lowered_name: lowered_name.clone(),
            ty,
            mutable,
            arg_index: None,
            stack_slot_name: None,
            struct_name,
            array_layout: None,
            pointer_elem_ty: None,
        };
        self.scopes
            .last_mut()
            .expect("scope stack is never empty")
            .insert(name.to_string(), binding.clone());
        binding
    }

    fn bind_struct_slot(&mut self, name: &str, slot_name: String, struct_name: String, mutable: bool) {
        self.scopes
            .last_mut()
            .expect("scope stack is never empty")
            .insert(
                name.to_string(),
                BindingInfo {
                    lowered_name: slot_name.clone(),
                    ty: ScalarType::Ptr,
                    mutable,
                    arg_index: None,
                    stack_slot_name: Some(slot_name),
                    struct_name: Some(struct_name),
                    array_layout: None,
                    pointer_elem_ty: None,
                },
            );
    }

    fn bind_array_slot(&mut self, name: &str, slot_name: String, array_layout: ArrayLayout, mutable: bool) {
        self.scopes
            .last_mut()
            .expect("scope stack is never empty")
            .insert(
                name.to_string(),
                BindingInfo {
                    lowered_name: slot_name.clone(),
                    ty: ScalarType::Ptr,
                    mutable,
                    arg_index: None,
                    stack_slot_name: Some(slot_name),
                    struct_name: None,
                    array_layout: Some(array_layout),
                    pointer_elem_ty: None,
                },
            );
    }

    fn lookup(&self, name: &str) -> Option<&BindingInfo> {
        for scope in self.scopes.iter().rev() {
            if let Some(binding) = scope.get(name) {
                return Some(binding);
            }
        }
        None
    }

    fn fresh_temp(&mut self, prefix: &str) -> String {
        self.next_temp_id += 1;
        format!("{prefix}${}", self.next_temp_id)
    }
}

fn binding_value_expr(binding: &BindingInfo) -> Expr {
    if let Some(slot_name) = &binding.stack_slot_name {
        Expr::StackAddr {
            name: slot_name.clone(),
        }
    } else if let Some(index) = binding.arg_index {
        arg_expr(index, binding.ty)
    } else {
        local_expr(binding.lowered_name.clone(), binding.ty)
    }
}

fn binding_name(path: &Path) -> Result<&str, String> {
    path.segments
        .first()
        .map(|s| s.as_str())
        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}empty path"))
}

fn array_binding<'a>(path: &Path, ctx: &'a LowerCtx<'_>) -> Result<(&'a BindingInfo, &'a ArrayLayout), String> {
    let name = binding_name(path)?;
    let binding = ctx
        .lookup(name)
        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown local name '{name}'"))?;
    let layout = binding
        .array_layout
        .as_ref()
        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}name '{name}' is not an array local"))?;
    Ok((binding, layout))
}

fn array_elem_addr(base: Expr, elem_ty: ScalarType, index: Expr) -> Expr {
    let elem_size = scalar_size(elem_ty) as u64;
    let scaled = Expr::Binary {
        op: BinaryOp::Mul,
        ty: ScalarType::I64,
        lhs: Box::new(index),
        rhs: Box::new(Expr::Const {
            ty: ScalarType::I64,
            bits: elem_size,
        }),
    };
    Expr::Binary {
        op: BinaryOp::Add,
        ty: ScalarType::Ptr,
        lhs: Box::new(base),
        rhs: Box::new(scaled),
    }
}

fn struct_field_addr(base: Expr, field: &StructFieldInfo) -> Expr {
    Expr::Binary {
        op: BinaryOp::Add,
        ty: ScalarType::Ptr,
        lhs: Box::new(base),
        rhs: Box::new(Expr::Const {
            ty: ScalarType::I64,
            bits: field.offset as u64,
        }),
    }
}

fn lookup_method_sig<'a>(
    ctx: &'a LowerCtx<'_>,
    struct_name: &str,
    method_name: &str,
) -> Option<&'a FuncSigInfo> {
    ctx.methods.get(struct_name).and_then(|bucket| bucket.get(method_name))
}

fn layout_name_of_expr(expr: &AstExpr, ctx: &LowerCtx<'_>) -> Option<String> {
    match &expr.kind {
        ExprKind::Path(path) if path.segments.len() == 1 => {
            let name = binding_name(path).ok()?;
            ctx.lookup(name)?.struct_name.clone()
        }
        ExprKind::Aggregate { .. } => aggregate_ctor_layout_name(expr, ctx.structs, ctx.taggeds),
        _ => None,
    }
}

fn array_layout_of_expr(expr: &AstExpr, ctx: &LowerCtx<'_>) -> Option<ArrayLayout> {
    match &expr.kind {
        ExprKind::Path(path) if path.segments.len() == 1 => ctx.lookup(binding_name(path).ok()?)?.array_layout.clone(),
        ExprKind::Aggregate { .. } => aggregate_ctor_array_layout(expr),
        _ => None,
    }
}

fn pointer_elem_type_of_expr(expr: &AstExpr, ctx: &LowerCtx<'_>) -> Option<ScalarType> {
    match &expr.kind {
        ExprKind::Path(path) if path.segments.len() == 1 => ctx.lookup(binding_name(path).ok()?)?.pointer_elem_ty,
        _ => None,
    }
}

fn index_base_info(base: &AstExpr, ctx: &mut LowerCtx<'_>) -> Result<IndexBaseInfo, String> {
    if let ExprKind::Path(path) = &base.kind {
        if path.segments.len() == 1 {
            if let Some(info) = ctx.lookup_domain_override(binding_name(path)?) {
                return Ok(info.base.clone());
            }
        }
    }

    if let Some(array_layout) = array_layout_of_expr(base, ctx) {
        return Ok(IndexBaseInfo {
            base_ptr: lower_expr(base, ctx, Some(ScalarType::Ptr))?,
            elem_ty: array_layout.elem_ty,
            elem_size: scalar_size(array_layout.elem_ty),
            limit: Some(Expr::Const {
                ty: ScalarType::U64,
                bits: array_layout.count as u64,
            }),
        });
    }

    if let Some(layout_name) = layout_name_of_expr(base, ctx) {
        if let Some(layout) = ctx.structs.get(&layout_name) {
            if let Some(elem_ty) = layout.slice_elem_ty {
                let header_ptr = lower_expr(base, ctx, Some(ScalarType::Ptr))?;
                let ptr_field = layout.fields.get("ptr").expect("slice layout has ptr field");
                let len_field = layout.fields.get("len").expect("slice layout has len field");
                return Ok(IndexBaseInfo {
                    base_ptr: Expr::Load {
                        ty: ScalarType::Ptr,
                        addr: Box::new(struct_field_addr(header_ptr.clone(), ptr_field)),
                    },
                    elem_ty,
                    elem_size: scalar_size(elem_ty),
                    limit: Some(Expr::Load {
                        ty: len_field.ty,
                        addr: Box::new(struct_field_addr(header_ptr, len_field)),
                    }),
                });
            }
        }
    }

    if let ExprKind::Field { base: field_base, name } = &base.kind {
        if name == "ptr" {
            if let Some(layout_name) = layout_name_of_expr(field_base, ctx) {
                if let Some(layout) = ctx.structs.get(&layout_name) {
                    if let Some(elem_ty) = layout.slice_elem_ty {
                        let header_ptr = lower_expr(field_base, ctx, Some(ScalarType::Ptr))?;
                        let ptr_field = layout.fields.get("ptr").expect("slice layout has ptr field");
                        let len_field = layout.fields.get("len").expect("slice layout has len field");
                        return Ok(IndexBaseInfo {
                            base_ptr: Expr::Load {
                                ty: ScalarType::Ptr,
                                addr: Box::new(struct_field_addr(header_ptr.clone(), ptr_field)),
                            },
                            elem_ty,
                            elem_size: scalar_size(elem_ty),
                            limit: Some(Expr::Load {
                                ty: len_field.ty,
                                addr: Box::new(struct_field_addr(header_ptr, len_field)),
                            }),
                        });
                    }
                }
            }
        }
    }

    if let Some(elem_ty) = pointer_elem_type_of_expr(base, ctx) {
        return Ok(IndexBaseInfo {
            base_ptr: lower_expr(base, ctx, Some(ScalarType::Ptr))?,
            elem_ty,
            elem_size: scalar_size(elem_ty),
            limit: None,
        });
    }

    unsupported("native array indexing requires an array local, aggregate base, slice base, or typed pointer base")
}

fn tagged_binding<'a>(path: &Path, ctx: &'a LowerCtx<'_>) -> Result<(&'a BindingInfo, &'a TaggedUnionLayout), String> {
    let name = binding_name(path)?;
    let binding = ctx
        .lookup(name)
        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown local name '{name}'"))?;
    let tagged_name = binding
        .struct_name
        .as_ref()
        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}name '{name}' is not a tagged union pointer/value"))?;
    let layout = ctx
        .taggeds
        .get(tagged_name)
        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown tagged union layout '{tagged_name}'"))?;
    Ok((binding, layout))
}

fn tagged_payload_base(base: Expr, layout: &TaggedUnionLayout) -> Expr {
    Expr::Binary {
        op: BinaryOp::Add,
        ty: ScalarType::Ptr,
        lhs: Box::new(base),
        rhs: Box::new(Expr::Const {
            ty: ScalarType::I64,
            bits: layout.payload_offset as u64,
        }),
    }
}

fn lower_tagged_variant_const(path: &Path, ctx: &LowerCtx<'_>) -> Option<Expr> {
    match path.segments.as_slice() {
        [tagged_name, variant_name] => {
            let layout = ctx.taggeds.get(tagged_name)?;
            let bits = *layout.variant_tags.get(variant_name)?;
            Some(Expr::Const {
                ty: layout.tag_ty,
                bits,
            })
        }
        [tagged_name, tag_name, variant_name] if tag_name == "Tag" => {
            let layout = ctx.taggeds.get(tagged_name)?;
            let bits = *layout.variant_tags.get(variant_name)?;
            Some(Expr::Const {
                ty: layout.tag_ty,
                bits,
            })
        }
        _ => None,
    }
}

fn lower_tagged_path_expr(path: &Path, ctx: &LowerCtx<'_>) -> Result<Expr, String> {
    let (binding, layout) = tagged_binding(path, ctx)?;
    let base = binding_value_expr(binding);
    match path.segments.len() {
        2 if path.segments[1] == "tag" => Ok(Expr::Load {
            ty: layout.tag_ty,
            addr: Box::new(base),
        }),
        4 if path.segments[1] == "payload" => {
            let variant = &path.segments[2];
            let field_name = &path.segments[3];
            let variant_layout = layout.variants.get(variant).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}tagged union '{}' has no payload variant '{}'", layout.name, variant)
            })?;
            let field = variant_layout.fields.get(field_name).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}payload variant '{}.{}' has no field '{}'", layout.name, variant, field_name)
            })?;
            Ok(Expr::Load {
                ty: field.ty,
                addr: Box::new(struct_field_addr(tagged_payload_base(base, layout), field)),
            })
        }
        _ => unsupported("native tagged union path access currently supports '.tag' and '.payload.<Variant>.<field>' only"),
    }
}

fn lower_path_expr(path: &Path, ctx: &LowerCtx<'_>) -> Result<Expr, String> {
    if let Some(value) = path.segments.first().and_then(|first| ctx.lookup(first)).map(binding_value_expr) {
        if path.segments.len() == 1 {
            return Ok(value);
        }
        let first = &path.segments[0];
        let binding = ctx
            .lookup(first)
            .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown local name '{first}'"))?;
        let struct_name = binding
            .struct_name
            .as_ref()
            .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}name '{first}' is not a struct/union/tagged union pointer/value"))?;
        if ctx.taggeds.contains_key(struct_name) {
            return lower_tagged_path_expr(path, ctx);
        }
        let layout = ctx
            .structs
            .get(struct_name)
            .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown struct/union layout '{struct_name}'"))?;
        if path.segments.len() != 2 {
            return unsupported("nested struct path chains are not yet supported natively");
        }
        let field_name = &path.segments[1];
        let field = layout.fields.get(field_name).ok_or_else(|| {
            format!("{UNSUPPORTED_PREFIX}struct '{}' has no field '{}'", layout.name, field_name)
        })?;
        return Ok(Expr::Load {
            ty: field.ty,
            addr: Box::new(struct_field_addr(value, field)),
        });
    }

    if let Some(value) = lower_tagged_variant_const(path, ctx) {
        return Ok(value);
    }

    let first = path
        .segments
        .first()
        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}empty path"))?;
    Err(format!("{UNSUPPORTED_PREFIX}unknown local or native constant path '{first}'"))
}

fn unify_types(current: Option<ScalarType>, next: Option<ScalarType>) -> Result<Option<ScalarType>, String> {
    match (current, next) {
        (None, x) | (x, None) => Ok(x),
        (Some(a), Some(b)) if a == b => Ok(Some(a)),
        (Some(a), Some(b)) => Err(format!(
            "{UNSUPPORTED_PREFIX}could not infer a unique scalar result type: {} vs {}",
            a.name(),
            b.name()
        )),
    }
}

fn known_expr_type(expr: &AstExpr, ctx: &LowerCtx<'_>) -> Option<ScalarType> {
    match &expr.kind {
        ExprKind::Path(path) => {
            if path.segments.len() == 1 {
                if let Some(binding) = ctx.lookup(binding_name(path).ok()?) {
                    Some(binding.ty)
                } else {
                    lower_tagged_variant_const(path, ctx).map(|expr| expr.ty())
                }
            } else {
                let first = &path.segments[0];
                if let Some(binding) = ctx.lookup(first) {
                    let layout_name = binding.struct_name.as_ref()?;
                    if let Some(tagged) = ctx.taggeds.get(layout_name) {
                        if path.segments.len() == 2 && path.segments[1] == "tag" {
                            Some(tagged.tag_ty)
                        } else if path.segments.len() == 4 && path.segments[1] == "payload" {
                            tagged
                                .variants
                                .get(&path.segments[2])
                                .and_then(|layout| layout.fields.get(&path.segments[3]))
                                .map(|field| field.ty)
                        } else {
                            None
                        }
                    } else if path.segments.len() == 2 {
                        let layout = ctx.structs.get(layout_name)?;
                        layout.fields.get(&path.segments[1]).map(|field| field.ty)
                    } else {
                        None
                    }
                } else {
                    lower_tagged_variant_const(path, ctx).map(|expr| expr.ty())
                }
            }
        }
        ExprKind::Bool(_) => Some(ScalarType::Bool),
        ExprKind::Number(v) => Some(default_number_type(&v.kind)),
        ExprKind::Cast { ty, .. } => scalar_type_from_type_expr(ty).ok(),
        ExprKind::SizeOf(_) | ExprKind::AlignOf(_) | ExprKind::OffsetOf { .. } => Some(ScalarType::U64),
        ExprKind::Load { ty, .. } => scalar_type_from_type_expr(ty).ok(),
        ExprKind::Memcmp { .. } => Some(ScalarType::I32),
        ExprKind::Call { callee, .. } => match &callee.kind {
            ExprKind::Path(path) if path.segments.len() == 1 => ctx.funcs.get(binding_name(path).ok()?)?.result,
            _ => None,
        },
        ExprKind::MethodCall { receiver, method, .. } => {
            let struct_name = layout_name_of_expr(receiver, ctx)?;
            lookup_method_sig(ctx, &struct_name, method)?.result
        }
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
        ExprKind::If(v) => {
            let mut out = None;
            for branch in &v.branches {
                out = unify_types(out, known_expr_type(&branch.value, ctx)).ok()?;
            }
            unify_types(out, known_expr_type(&v.else_branch, ctx)).ok()?
        }
        ExprKind::Field { base, name } => {
            let layout_name = layout_name_of_expr(base, ctx)?;
            if let Some(tagged) = ctx.taggeds.get(&layout_name) {
                if name == "tag" {
                    Some(tagged.tag_ty)
                } else {
                    None
                }
            } else {
                let layout = ctx.structs.get(&layout_name)?;
                Some(layout.fields.get(name)?.ty)
            }
        }
        ExprKind::Index { base, .. } => array_layout_of_expr(base, ctx)
            .map(|layout| layout.elem_ty)
            .or_else(|| {
                layout_name_of_expr(base, ctx)
                    .and_then(|name| ctx.structs.get(&name))
                    .and_then(|layout| layout.slice_elem_ty)
            })
            .or_else(|| {
                if let ExprKind::Field { base: field_base, name } = &base.kind {
                    if name == "ptr" {
                        return layout_name_of_expr(field_base, ctx)
                            .and_then(|layout_name| ctx.structs.get(&layout_name))
                            .and_then(|layout| layout.slice_elem_ty);
                    }
                }
                None
            })
            .or_else(|| pointer_elem_type_of_expr(base, ctx)),
        ExprKind::Switch(v) => known_switch_expr_type(v, ctx),
        ExprKind::Loop(v) => {
            let mut loop_ctx = ctx.clone();
            loop_ctx.push_scope();
            match &v.head {
                AstLoopHead::While { vars, .. } => {
                    for var in vars {
                        let ty = scalar_type_from_type_expr(&var.ty).ok()?;
                        let _ = loop_ctx.bind(&var.name, ty, false, None, None);
                    }
                }
                AstLoopHead::Over { carries, .. } => {
                    for carry in carries {
                        let ty = scalar_type_from_type_expr(&carry.ty).ok()?;
                        let _ = loop_ctx.bind(&carry.name, ty, false, None, None);
                    }
                }
            }
            let out = known_expr_type(&v.result, &loop_ctx);
            loop_ctx.pop_scope();
            out
        }
        ExprKind::Block(block) => known_block_value_type(block, ctx),
        _ => None,
    }
}

fn known_switch_expr_type(expr: &SwitchExpr, ctx: &LowerCtx<'_>) -> Option<ScalarType> {
    let mut out = known_expr_type(&expr.default, ctx);
    for case in &expr.cases {
        out = unify_types(out, known_expr_type(&case.body, ctx)).ok()?;
    }
    out
}

fn known_terminal_stmt_value_type(stmt: &AstStmt, ctx: &mut LowerCtx<'_>) -> Option<ScalarType> {
    match stmt {
        AstStmt::Return { value: Some(value), .. } => known_expr_type(value, ctx),
        AstStmt::Expr { expr, .. } => known_expr_type(expr, ctx),
        AstStmt::If(v) => {
            let mut out = None;
            for branch in &v.branches {
                out = unify_types(out, known_block_value_type(&branch.body, ctx)).ok()?;
            }
            let else_block = v.else_branch.as_ref()?;
            unify_types(out, known_block_value_type(else_block, ctx)).ok()?
        }
        AstStmt::Switch(v) => {
            let mut out = None;
            for case in &v.cases {
                out = unify_types(out, known_block_value_type(&case.body, ctx)).ok()?;
            }
            let default = v.default.as_ref()?;
            unify_types(out, known_block_value_type(default, ctx)).ok()?
        }
        _ => None,
    }
}

fn known_block_value_type(block: &Block, ctx: &LowerCtx<'_>) -> Option<ScalarType> {
    let mut ctx = ctx.clone();
    ctx.push_scope();
    let result = (|| {
        let last = block.stmts.last()?;
        for stmt in &block.stmts[..block.stmts.len().saturating_sub(1)] {
            apply_stmt_bindings_for_inference(stmt, &mut ctx);
        }
        known_terminal_stmt_value_type(last, &mut ctx)
    })();
    ctx.pop_scope();
    result
}

fn apply_stmt_bindings_for_inference(stmt: &AstStmt, ctx: &mut LowerCtx<'_>) {
    match stmt {
        AstStmt::Let { name, ty, value, .. } | AstStmt::Var { name, ty, value, .. } => {
            if let Some(layout_name) = ty
                .as_ref()
                .and_then(|ty| layout_name_from_type_expr(ty, ctx.structs, ctx.taggeds))
                .or_else(|| aggregate_ctor_layout_name(value, ctx.structs, ctx.taggeds))
            {
                ctx.bind(name, ScalarType::Ptr, matches!(stmt, AstStmt::Var { .. }), Some(layout_name), None);
                return;
            }
            if let Some(array_layout) = ty.as_ref().and_then(array_layout_from_type_expr)
                .or_else(|| aggregate_ctor_array_layout(value))
            {
                let mut binding = ctx.bind(name, ScalarType::Ptr, matches!(stmt, AstStmt::Var { .. }), None, None);
                binding.array_layout = Some(array_layout.clone());
                ctx.scopes
                    .last_mut()
                    .expect("scope stack is never empty")
                    .insert(name.clone(), binding);
                return;
            }
            let inferred = ty
                .as_ref()
                .and_then(|ty| scalar_type_from_type_expr(ty).ok())
                .or_else(|| known_expr_type(value, ctx));
            if let Some(inferred) = inferred {
                let mut binding = ctx.bind(name, inferred, matches!(stmt, AstStmt::Var { .. }), None, None);
                binding.pointer_elem_ty = ty
                    .as_ref()
                    .and_then(pointer_elem_scalar_from_type_expr)
                    .or_else(|| pointer_elem_type_of_expr(value, ctx));
                ctx.scopes
                    .last_mut()
                    .expect("scope stack is never empty")
                    .insert(name.clone(), binding);
            }
        }
        _ => {}
    }
}

fn collect_return_types_from_block(
    block: &Block,
    ctx: &mut LowerCtx<'_>,
    out: &mut Option<ScalarType>,
) -> Result<(), String> {
    ctx.push_scope();
    for stmt in &block.stmts {
        collect_return_types_from_stmt(stmt, ctx, out)?;
        apply_stmt_bindings_for_inference(stmt, ctx);
    }
    ctx.pop_scope();
    Ok(())
}

fn collect_return_types_from_stmt(
    stmt: &AstStmt,
    ctx: &mut LowerCtx<'_>,
    out: &mut Option<ScalarType>,
) -> Result<(), String> {
    match stmt {
        AstStmt::Return { value: Some(value), .. } => {
            *out = unify_types(*out, known_expr_type(value, ctx))?;
        }
        AstStmt::If(v) => {
            for branch in &v.branches {
                collect_return_types_from_block(&branch.body, ctx, out)?;
            }
            if let Some(block) = &v.else_branch {
                collect_return_types_from_block(block, ctx, out)?;
            }
        }
        AstStmt::Switch(v) => {
            for case in &v.cases {
                collect_return_types_from_block(&case.body, ctx, out)?;
            }
            if let Some(block) = &v.default {
                collect_return_types_from_block(block, ctx, out)?;
            }
        }
        AstStmt::While { body, .. } => collect_return_types_from_block(body, ctx, out)?,
        AstStmt::For(ForStmt { body, .. }) => collect_return_types_from_block(body, ctx, out)?,
        AstStmt::Loop(AstLoopStmt { body, .. }) => collect_return_types_from_block(body, ctx, out)?,
        _ => {}
    }
    Ok(())
}

fn stmt_has_return(stmt: &AstStmt) -> bool {
    match stmt {
        AstStmt::Return { .. } => true,
        AstStmt::If(v) => {
            v.branches.iter().any(|b| block_has_return(&b.body))
                || v.else_branch.as_ref().is_some_and(block_has_return)
        }
        AstStmt::Switch(v) => {
            v.cases.iter().any(|c| block_has_return(&c.body))
                || v.default.as_ref().is_some_and(block_has_return)
        }
        AstStmt::While { body, .. } => block_has_return(body),
        AstStmt::For(ForStmt { body, .. }) => block_has_return(body),
        AstStmt::Loop(AstLoopStmt { body, .. }) => block_has_return(body),
        _ => false,
    }
}

fn block_has_return(block: &Block) -> bool {
    block.stmts.iter().any(stmt_has_return)
}

fn stmt_always_returns(stmt: &AstStmt) -> bool {
    match stmt {
        AstStmt::Return { .. } => true,
        AstStmt::If(v) => {
            let Some(else_block) = &v.else_branch else {
                return false;
            };
            v.branches.iter().all(|b| block_always_returns(&b.body)) && block_always_returns(else_block)
        }
        AstStmt::Switch(v) => {
            let Some(default) = &v.default else {
                return false;
            };
            v.cases.iter().all(|c| block_always_returns(&c.body)) && block_always_returns(default)
        }
        _ => false,
    }
}

fn block_always_returns(block: &Block) -> bool {
    block.stmts.iter().any(stmt_always_returns)
}

fn infer_function_result(
    func: &FuncDecl,
    sig_map: &HashMap<String, FuncSigInfo>,
    method_map: &HashMap<String, HashMap<String, FuncSigInfo>>,
    structs: &HashMap<String, StructLayout>,
    taggeds: &HashMap<String, TaggedUnionLayout>,
) -> Result<Option<ScalarType>, String> {
    let mut ctx = LowerCtx::new(sig_map, method_map, structs, taggeds);
    for (i, param) in func.sig.params.iter().enumerate() {
        let struct_name = pointer_struct_name_from_type_expr(&param.ty, structs, taggeds);
        let pointer_elem_ty = pointer_elem_scalar_from_type_expr(&param.ty);
        ctx.bind_param(
            &param.name,
            scalar_type_from_type_expr(&param.ty)?,
            (i + 1) as u32,
            struct_name,
            pointer_elem_ty,
        );
    }

    let mut out = None;
    collect_return_types_from_block(&func.body, &mut ctx, &mut out)?;
    if !block_always_returns(&func.body) {
        if let Some(last) = func.body.stmts.last() {
            out = unify_types(out, known_terminal_stmt_value_type(last, &mut ctx))?;
        }
    }
    Ok(out)
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

fn simple_reusable_switch_value(expr: &AstExpr) -> bool {
    matches!(expr.kind, ExprKind::Path(_) | ExprKind::Number(_) | ExprKind::Bool(_))
}

fn lower_switch_expr(
    expr: &SwitchExpr,
    ctx: &mut LowerCtx<'_>,
    expected: Option<ScalarType>,
) -> Result<Expr, String> {
    let value_ty = known_expr_type(&expr.value, ctx).unwrap_or(ScalarType::I32);
    let result_ty = expected
        .or_else(|| known_switch_expr_type(expr, ctx))
        .unwrap_or(ScalarType::I32);

    fn build_case_expr(
        cases: &[crate::ast::SwitchExprCase],
        index: usize,
        default: &AstExpr,
        value_expr: &Expr,
        value_ty: ScalarType,
        result_ty: ScalarType,
        ctx: &mut LowerCtx<'_>,
    ) -> Result<Expr, String> {
        if index >= cases.len() {
            return lower_expr(default, ctx, Some(result_ty));
        }
        let case = &cases[index];
        let cond = eq_expr(
            value_expr.clone(),
            lower_expr(&case.value, ctx, Some(value_ty))?,
            value_ty,
        );
        let then_expr = lower_expr(&case.body, ctx, Some(result_ty))?;
        let else_expr = build_case_expr(cases, index + 1, default, value_expr, value_ty, result_ty, ctx)?;
        Ok(Expr::Select {
            cond: Box::new(cond),
            then_expr: Box::new(then_expr),
            else_expr: Box::new(else_expr),
            ty: result_ty,
        })
    }

    if simple_reusable_switch_value(&expr.value) {
        let value_expr = lower_expr(&expr.value, ctx, Some(value_ty))?;
        return build_case_expr(&expr.cases, 0, &expr.default, &value_expr, value_ty, result_ty, ctx);
    }

    let value_name = ctx.fresh_temp("switchv");
    let value_init = lower_expr(&expr.value, ctx, Some(value_ty))?;
    let value_expr = local_expr(value_name.clone(), value_ty);
    let body = build_case_expr(&expr.cases, 0, &expr.default, &value_expr, value_ty, result_ty, ctx)?;
    Ok(Expr::Let {
        name: value_name,
        ty: value_ty,
        init: Box::new(value_init),
        body: Box::new(body),
    })
}

fn lower_aggregate_expr(expr: &AstExpr, ctx: &mut LowerCtx<'_>, expected: Option<ScalarType>) -> Result<Expr, String> {
    if expected != Some(ScalarType::Ptr) {
        return unsupported(
            "aggregate expressions currently require a pointer-typed context natively",
        );
    }
    if let Some(layout_name) = aggregate_ctor_layout_name(expr, ctx.structs, ctx.taggeds) {
        let slot_name = ctx.fresh_temp("agg");
        let mut stmts = Vec::new();
        if let Some(layout) = ctx.structs.get(&layout_name).cloned() {
            stmts.push(Stmt::StackSlot {
                name: slot_name.clone(),
                size: layout.size,
                align: layout.align,
            });
            stmts.extend(populate_struct_slot(&layout, &slot_name, expr, ctx)?);
        } else if let Some(layout) = ctx.taggeds.get(&layout_name).cloned() {
            stmts.push(Stmt::StackSlot {
                name: slot_name.clone(),
                size: layout.size,
                align: layout.align,
            });
            stmts.extend(populate_tagged_slot(&layout, &slot_name, expr, ctx)?);
        } else {
            return Err(format!("{UNSUPPORTED_PREFIX}unknown native layout '{}'", layout_name));
        }
        return Ok(Expr::Block {
            ty: ScalarType::Ptr,
            stmts,
            result: Box::new(Expr::StackAddr { name: slot_name }),
        });
    }
    if let Some(array_layout) = aggregate_ctor_array_layout(expr) {
        let slot_name = ctx.fresh_temp("agg");
        let mut stmts = vec![Stmt::StackSlot {
            name: slot_name.clone(),
            size: array_layout.size,
            align: array_layout.align,
        }];
        stmts.extend(populate_array_slot(&array_layout, &slot_name, expr, ctx)?);
        return Ok(Expr::Block {
            ty: ScalarType::Ptr,
            stmts,
            result: Box::new(Expr::StackAddr { name: slot_name }),
        });
    }
    unsupported("aggregate expressions currently support only struct/union/tagged/array literals natively")
}

fn lower_expr(expr: &AstExpr, ctx: &mut LowerCtx<'_>, expected: Option<ScalarType>) -> Result<Expr, String> {
    match &expr.kind {
        ExprKind::Path(path) => lower_path_expr(path, ctx),
        ExprKind::Number(v) => lower_number_const(&v.raw, v.kind.clone(), expected),
        ExprKind::Bool(v) => Ok(bool_expr(*v)),
        ExprKind::Aggregate { .. } => lower_aggregate_expr(expr, ctx, expected),
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
            AstUnaryOp::AddrOf | AstUnaryOp::Deref => unsupported("addr-of and deref are not yet supported natively"),
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
                .or_else(|| known_expr_type(expr, ctx))
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
            Ok(Expr::Select {
                cond: Box::new(cond),
                then_expr: Box::new(then_expr),
                else_expr: Box::new(else_expr),
                ty: branch_ty,
            })
        }
        ExprKind::Switch(v) => lower_switch_expr(v, ctx, expected),
        ExprKind::Loop(v) => lower_loop_expr_native(v, ctx, expected),
        ExprKind::Cast { kind, ty, value } => {
            let ty = scalar_type_from_type_expr(ty)?;
            if matches!(kind, CastKind::Cast | CastKind::Trunc | CastKind::Zext | CastKind::Sext) {
                match &value.kind {
                    ExprKind::Number(v) => return lower_number_const(&v.raw, v.kind.clone(), Some(ty)),
                    ExprKind::Bool(v) => {
                        return lower_number_const(if *v { "1" } else { "0" }, NumberKind::Int, Some(ty))
                    }
                    _ => {}
                }
            }
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
        ExprKind::SizeOf(ty) => {
            let (size, _) = type_size_align_from_type_expr(ty, ctx.structs, ctx.taggeds)?;
            Ok(Expr::Const {
                ty: ScalarType::U64,
                bits: size as u64,
            })
        }
        ExprKind::AlignOf(ty) => {
            let (_, align) = type_size_align_from_type_expr(ty, ctx.structs, ctx.taggeds)?;
            Ok(Expr::Const {
                ty: ScalarType::U64,
                bits: align as u64,
            })
        }
        ExprKind::OffsetOf { ty, field } => Ok(Expr::Const {
            ty: ScalarType::U64,
            bits: field_offset_from_type_expr(ty, field, ctx.structs, ctx.taggeds)? as u64,
        }),
        ExprKind::Load { ty, ptr } => Ok(Expr::Load {
            ty: scalar_type_from_type_expr(ty)?,
            addr: Box::new(lower_expr(ptr, ctx, Some(ScalarType::Ptr))?),
        }),
        ExprKind::Memcmp { a, b, len } => Ok(Expr::Memcmp {
            a: Box::new(lower_expr(a, ctx, Some(ScalarType::Ptr))?),
            b: Box::new(lower_expr(b, ctx, Some(ScalarType::Ptr))?),
            len: Box::new(lower_expr(len, ctx, Some(ScalarType::U64))?),
        }),
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
            let result_ty = sig
                .result
                .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}callee '{name}' result type is not inferred yet"))?;
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
                    name: sig.symbol,
                    params: sig.params,
                    result: result_ty,
                },
                ty: result_ty,
                args: lowered_args,
            })
        }
        ExprKind::Field { base, name } => {
            let layout_name = layout_name_of_expr(base, ctx).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}native field access currently requires a layout local/arg/aggregate base")
            })?;
            let base_ptr = lower_expr(base, ctx, Some(ScalarType::Ptr))?;
            if let Some(tagged) = ctx.taggeds.get(&layout_name) {
                if name == "tag" {
                    Ok(Expr::Load {
                        ty: tagged.tag_ty,
                        addr: Box::new(base_ptr),
                    })
                } else {
                    unsupported("native tagged union field access via postfix currently supports only '.tag'; use path syntax for payload fields")
                }
            } else {
                let layout = ctx
                    .structs
                    .get(&layout_name)
                    .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown struct/union layout '{layout_name}'"))?;
                let field = layout
                    .fields
                    .get(name)
                    .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}struct '{}' has no field '{}'", layout.name, name))?;
                Ok(Expr::Load {
                    ty: field.ty,
                    addr: Box::new(struct_field_addr(base_ptr, field)),
                })
            }
        }
        ExprKind::MethodCall { receiver, method, args } => {
            let struct_name = layout_name_of_expr(receiver, ctx).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}native method calls currently require a layout local/arg/aggregate receiver")
            })?;
            let sig = lookup_method_sig(ctx, &struct_name, method)
                .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown method '{}:{}'", struct_name, method))?
                .clone();
            let result_ty = sig
                .result
                .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}method '{}:{}' result type is not inferred yet", struct_name, method))?;
            if sig.params.is_empty() {
                return Err(format!("native method '{}:{}' has no receiver parameter", struct_name, method));
            }
            if sig.params.len() != args.len() + 1 {
                return Err(format!(
                    "native method '{}:{}' expected {} args, got {}",
                    struct_name,
                    method,
                    sig.params.len() - 1,
                    args.len()
                ));
            }
            let mut lowered_args = Vec::with_capacity(args.len() + 1);
            lowered_args.push(lower_expr(receiver, ctx, Some(sig.params[0]))?);
            for (arg, param_ty) in args.iter().zip(sig.params.iter().copied().skip(1)) {
                lowered_args.push(lower_expr(arg, ctx, Some(param_ty))?);
            }
            Ok(Expr::Call {
                target: CallTarget::Direct {
                    name: sig.symbol,
                    params: sig.params,
                    result: result_ty,
                },
                ty: result_ty,
                args: lowered_args,
            })
        }
        ExprKind::Index { base, index } => {
            let base_info = index_base_info(base, ctx)?;
            let index_expr = lower_expr(index, ctx, None)?;
            Ok(Expr::Load {
                ty: base_info.elem_ty,
                addr: Box::new(Expr::IndexAddr {
                    base: Box::new(base_info.base_ptr),
                    index: Box::new(index_expr),
                    elem_size: base_info.elem_size,
                    limit: base_info.limit.map(Box::new),
                }),
            })
        }
        ExprKind::Block(block) => lower_block_value(block, ctx, expected),
        ExprKind::Splice(_) => unsupported("splices are not available in rust-only source mode yet"),
        ExprKind::Hole { .. } => unsupported("holes are not available in rust-only source mode yet"),
        ExprKind::AnonymousFunc(_) => unsupported("standalone anonymous func expressions are not available in rust-only source mode yet"),
        _ => unsupported("expression form is not yet supported by the native fast path"),
    }
}

fn lower_terminal_stmt_value(
    stmt: &AstStmt,
    ctx: &mut LowerCtx<'_>,
    expected: Option<ScalarType>,
) -> Result<Expr, String> {
    match stmt {
        AstStmt::Return { value: Some(value), .. } => lower_expr(value, ctx, expected),
        AstStmt::Expr { expr, .. } => lower_expr(expr, ctx, expected),
        AstStmt::If(v) => {
            let branch_ty = expected
                .or_else(|| known_terminal_stmt_value_type(stmt, ctx))
                .unwrap_or(ScalarType::I32);
            let first = v
                .branches
                .first()
                .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}empty if statement"))?;
            let cond = lower_expr(&first.cond, ctx, Some(ScalarType::Bool))?;
            let then_expr = lower_block_value(&first.body, ctx, Some(branch_ty))?;
            let else_expr = if v.branches.len() > 1 {
                let nested = AstStmt::If(IfStmt {
                    branches: v.branches[1..].to_vec(),
                    else_branch: v.else_branch.clone(),
                    span: v.span,
                });
                lower_terminal_stmt_value(&nested, ctx, Some(branch_ty))?
            } else {
                let else_block = v
                    .else_branch
                    .as_ref()
                    .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}terminal if is missing an else branch"))?;
                lower_block_value(else_block, ctx, Some(branch_ty))?
            };
            Ok(Expr::If {
                cond: Box::new(cond),
                then_expr: Box::new(then_expr),
                else_expr: Box::new(else_expr),
                ty: branch_ty,
            })
        }
        AstStmt::Switch(v) => {
            let fake = SwitchExpr {
                value: Box::new(v.value.clone()),
                cases: v
                    .cases
                    .iter()
                    .map(|case| crate::ast::SwitchExprCase {
                        value: case.value.clone(),
                        body: crate::ast::Expr {
                            kind: ExprKind::Block(case.body.clone()),
                            span: case.body.span,
                        },
                        span: case.span,
                    })
                    .collect(),
                default: Box::new(crate::ast::Expr {
                    kind: ExprKind::Block(
                        v.default
                            .clone()
                            .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}terminal switch is missing a default"))?,
                    ),
                    span: v.span,
                }),
                span: v.span,
            };
            lower_switch_expr(&fake, ctx, expected)
        }
        _ => unsupported("block value cannot end in this statement kind natively"),
    }
}

fn lower_block_value(
    block: &Block,
    ctx: &mut LowerCtx<'_>,
    expected: Option<ScalarType>,
) -> Result<Expr, String> {
    ctx.push_scope();
    let result = (|| {
        let Some((last, prefix)) = block.stmts.split_last() else {
            return unsupported("empty value blocks are not yet supported natively");
        };

        let mut stmts = Vec::with_capacity(prefix.len());
        for stmt in prefix {
            let lowered = lower_stmt(stmt, ctx, false, None)?;
            if lowered.stop {
                return unsupported("value blocks hit unsupported control flow natively");
            }
            stmts.extend(lowered.stmts);
        }

        let terminal_expected = expected.or_else(|| known_terminal_stmt_value_type(last, ctx));
        let result_expr = lower_terminal_stmt_value(last, ctx, terminal_expected)?;
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

fn lower_block_void(
    block: &Block,
    ctx: &mut LowerCtx<'_>,
    in_loop: bool,
    return_state: Option<&ReturnState>,
) -> Result<Vec<Stmt>, String> {
    ctx.push_scope();
    let result = lower_stmt_range(&block.stmts, ctx, in_loop, return_state);
    ctx.pop_scope();
    result
}

fn lower_if_stmt_chain(
    stmt: &IfStmt,
    ctx: &mut LowerCtx<'_>,
    in_loop: bool,
    return_state: Option<&ReturnState>,
) -> Result<Stmt, String> {
    let first = stmt
        .branches
        .first()
        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}empty if statement"))?;
    let cond = lower_expr(&first.cond, ctx, Some(ScalarType::Bool))?;
    let then_body = lower_block_void(&first.body, ctx, in_loop, return_state)?;
    let else_body = if stmt.branches.len() > 1 {
        let nested = IfStmt {
            branches: stmt.branches[1..].to_vec(),
            else_branch: stmt.else_branch.clone(),
            span: stmt.span,
        };
        vec![lower_if_stmt_chain(&nested, ctx, in_loop, return_state)?]
    } else if let Some(block) = &stmt.else_branch {
        lower_block_void(block, ctx, in_loop, return_state)?
    } else {
        Vec::new()
    };
    Ok(Stmt::If {
        cond,
        then_body,
        else_body,
    })
}

fn lower_switch_stmt(
    stmt: &SwitchStmt,
    ctx: &mut LowerCtx<'_>,
    in_loop: bool,
    return_state: Option<&ReturnState>,
) -> Result<Vec<Stmt>, String> {
    let value_ty = known_expr_type(&stmt.value, ctx).unwrap_or(ScalarType::I32);

    fn build_case_stmt(
        cases: &[crate::ast::SwitchStmtCase],
        index: usize,
        default: Option<&Block>,
        value_expr: &Expr,
        value_ty: ScalarType,
        ctx: &mut LowerCtx<'_>,
        in_loop: bool,
        return_state: Option<&ReturnState>,
    ) -> Result<Vec<Stmt>, String> {
        if index >= cases.len() {
            return match default {
                Some(block) => lower_block_void(block, ctx, in_loop, return_state),
                None => Ok(Vec::new()),
            };
        }
        let case = &cases[index];
        let cond = eq_expr(
            value_expr.clone(),
            lower_expr(&case.value, ctx, Some(value_ty))?,
            value_ty,
        );
        let then_body = lower_block_void(&case.body, ctx, in_loop, return_state)?;
        let else_body = build_case_stmt(cases, index + 1, default, value_expr, value_ty, ctx, in_loop, return_state)?;
        Ok(vec![Stmt::If {
            cond,
            then_body,
            else_body,
        }])
    }

    if simple_reusable_switch_value(&stmt.value) {
        let value_expr = lower_expr(&stmt.value, ctx, Some(value_ty))?;
        return build_case_stmt(
            &stmt.cases,
            0,
            stmt.default.as_ref(),
            &value_expr,
            value_ty,
            ctx,
            in_loop,
            return_state,
        );
    }

    let value_name = ctx.fresh_temp("switchv");
    let mut out = vec![Stmt::Let {
        name: value_name.clone(),
        ty: value_ty,
        init: lower_expr(&stmt.value, ctx, Some(value_ty))?,
    }];
    let value_expr = local_expr(value_name.clone(), value_ty);
    out.extend(build_case_stmt(
        &stmt.cases,
        0,
        stmt.default.as_ref(),
        &value_expr,
        value_ty,
        ctx,
        in_loop,
        return_state,
    )?);
    Ok(out)
}

fn lower_return_stmt(
    value: &Option<AstExpr>,
    ctx: &mut LowerCtx<'_>,
    in_loop: bool,
    return_state: Option<&ReturnState>,
) -> Result<LoweredStmt, String> {
    let Some(return_state) = return_state else {
        return unsupported("return statements are only supported in function bodies natively");
    };
    let mut out = LoweredStmt::default();
    if return_state.void_function {
        if value.is_some() {
            return Err("void Moonlift function must not return a value".to_string());
        }
    } else {
        let result_ty = return_state
            .result_ty
            .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}missing native return result type"))?;
        let result_name = return_state
            .result_name
            .as_ref()
            .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}missing native return result slot"))?;
        let value = value
            .as_ref()
            .ok_or_else(|| "non-void Moonlift function must return a value".to_string())?;
        out.stmts.push(Stmt::Set {
            name: result_name.clone(),
            value: lower_expr(value, ctx, Some(result_ty))?,
        });
    }
    out.stmts.push(Stmt::Set {
        name: return_state.returned_name.clone(),
        value: bool_expr(true),
    });
    if in_loop {
        out.stmts.push(Stmt::Break);
    }
    out.stop = true;
    Ok(out)
}

fn guard_cond(cond: Expr, return_state: Option<&ReturnState>) -> Expr {
    if let Some(return_state) = return_state {
        and_expr(
            not_expr(local_expr(return_state.returned_name.clone(), ScalarType::Bool)),
            cond,
        )
    } else {
        cond
    }
}

fn loop_assign_target_name(target: &AstExpr) -> Option<&str> {
    match &target.kind {
        ExprKind::Path(path) if path.segments.len() == 1 => binding_name(path).ok(),
        _ => None,
    }
}

fn stmt_contains_canonical_loop_control(stmt: &AstStmt) -> bool {
    match stmt {
        AstStmt::Break { .. } | AstStmt::Continue { .. } | AstStmt::Return { .. } => true,
        AstStmt::If(v) => {
            v.branches.iter().any(|b| block_contains_canonical_loop_control(&b.body))
                || v.else_branch.as_ref().is_some_and(block_contains_canonical_loop_control)
        }
        AstStmt::While { body, .. } => block_contains_canonical_loop_control(body),
        AstStmt::For(ForStmt { body, .. }) => block_contains_canonical_loop_control(body),
        AstStmt::Loop(v) => block_contains_canonical_loop_control(&v.body),
        AstStmt::Switch(v) => {
            v.cases.iter().any(|c| block_contains_canonical_loop_control(&c.body))
                || v.default.as_ref().is_some_and(block_contains_canonical_loop_control)
        }
        _ => false,
    }
}

fn block_contains_canonical_loop_control(block: &Block) -> bool {
    block.stmts.iter().any(stmt_contains_canonical_loop_control)
}

fn stmt_assigns_any_name(stmt: &AstStmt, names: &HashSet<String>) -> bool {
    match stmt {
        AstStmt::Assign { target, .. } => loop_assign_target_name(target).is_some_and(|name| names.contains(name)),
        AstStmt::If(v) => {
            v.branches.iter().any(|b| block_assigns_any_name(&b.body, names))
                || v.else_branch.as_ref().is_some_and(|b| block_assigns_any_name(b, names))
        }
        AstStmt::While { body, .. } => block_assigns_any_name(body, names),
        AstStmt::For(ForStmt { body, .. }) => block_assigns_any_name(body, names),
        AstStmt::Loop(v) => {
            block_assigns_any_name(&v.body, names)
                || v.next.iter().any(|entry| names.contains(&entry.name))
        }
        AstStmt::Switch(v) => {
            v.cases.iter().any(|c| block_assigns_any_name(&c.body, names))
                || v.default.as_ref().is_some_and(|b| block_assigns_any_name(b, names))
        }
        _ => false,
    }
}

fn block_assigns_any_name(block: &Block, names: &HashSet<String>) -> bool {
    block.stmts.iter().any(|stmt| stmt_assigns_any_name(stmt, names))
}

fn lower_loop_state_bindings(
    vars: &[AstLoopVarInit],
    ctx: &mut LowerCtx<'_>,
) -> Result<(Vec<Stmt>, Vec<LoopStateBinding>), String> {
    let mut prelude = Vec::new();
    let mut out = Vec::new();
    for var in vars {
        let ty = scalar_type_from_type_expr(&var.ty)?;
        let init = lower_expr(&var.init, ctx, Some(ty))?;
        let binding = ctx.bind(&var.name, ty, false, None, Some("var"));
        prelude.push(Stmt::Var {
            name: binding.lowered_name.clone(),
            ty,
            init,
        });
        out.push(LoopStateBinding {
            source_name: var.name.clone(),
            lowered_name: binding.lowered_name,
            ty,
        });
    }
    Ok((prelude, out))
}

fn collect_loop_next_values(
    next: &[AstLoopNextAssign],
    states: &[LoopStateBinding],
    ctx: &mut LowerCtx<'_>,
) -> Result<Vec<Expr>, String> {
    let mut next_map: HashMap<String, &AstLoopNextAssign> = HashMap::new();
    for entry in next {
        if next_map.insert(entry.name.clone(), entry).is_some() {
            return Err(format!("duplicate loop next binding '{}'", entry.name));
        }
    }
    let mut out = Vec::with_capacity(states.len());
    for state in states {
        let entry = next_map
            .remove(&state.source_name)
            .ok_or_else(|| format!("loop next section is missing '{}'", state.source_name))?;
        out.push(lower_expr(&entry.value, ctx, Some(state.ty))?);
    }
    if let Some(extra) = next_map.keys().next() {
        return Err(format!("loop next section has no carried state named '{}'", extra));
    }
    Ok(out)
}

fn loop_ir_expr_is_local(expr: &Expr, name: &str, ty: ScalarType) -> bool {
    matches!(expr, Expr::Local { name: n, ty: t } if n == name && *t == ty)
}

fn loop_ir_const_step_direction(ty: ScalarType, expr: &Expr) -> Option<StepDirection> {
    match expr {
        Expr::Const { ty: expr_ty, bits } if *expr_ty == ty && !ty.is_float() => match ty {
            ScalarType::I8 => match *bits as i8 {
                v if v > 0 => Some(StepDirection::Asc),
                v if v < 0 => Some(StepDirection::Desc),
                _ => None,
            },
            ScalarType::I16 => match *bits as i16 {
                v if v > 0 => Some(StepDirection::Asc),
                v if v < 0 => Some(StepDirection::Desc),
                _ => None,
            },
            ScalarType::I32 => match *bits as i32 {
                v if v > 0 => Some(StepDirection::Asc),
                v if v < 0 => Some(StepDirection::Desc),
                _ => None,
            },
            ScalarType::I64 => match *bits as i64 {
                v if v > 0 => Some(StepDirection::Asc),
                v if v < 0 => Some(StepDirection::Desc),
                _ => None,
            },
            ScalarType::U8 | ScalarType::U16 | ScalarType::U32 | ScalarType::U64 | ScalarType::Ptr => {
                if *bits > 0 {
                    Some(StepDirection::Asc)
                } else {
                    None
                }
            }
            _ => None,
        },
        _ => None,
    }
}

fn loop_ir_extract_compare(cond: &Expr, name: &str, ty: ScalarType) -> Option<StepDirection> {
    match cond {
        Expr::Binary {
            op,
            ty: ScalarType::Bool,
            lhs,
            rhs,
        } if loop_ir_expr_is_local(lhs, name, ty) => match op {
            BinaryOp::Lt | BinaryOp::Le => Some(StepDirection::Asc),
            BinaryOp::Gt | BinaryOp::Ge => Some(StepDirection::Desc),
            _ => None,
        },
        Expr::Binary {
            op,
            ty: ScalarType::Bool,
            lhs,
            rhs,
        } if loop_ir_expr_is_local(rhs, name, ty) => match op {
            BinaryOp::Gt | BinaryOp::Ge => Some(StepDirection::Asc),
            BinaryOp::Lt | BinaryOp::Le => Some(StepDirection::Desc),
            _ => None,
        },
        _ => None,
    }
}

fn loop_ir_extract_step(next: &Expr, name: &str, ty: ScalarType) -> Option<StepDirection> {
    match next {
        Expr::Binary {
            op: BinaryOp::Add,
            ty: expr_ty,
            lhs,
            rhs,
        } if *expr_ty == ty && loop_ir_expr_is_local(lhs, name, ty) => loop_ir_const_step_direction(ty, rhs),
        Expr::Binary {
            op: BinaryOp::Add,
            ty: expr_ty,
            lhs,
            rhs,
        } if *expr_ty == ty && loop_ir_expr_is_local(rhs, name, ty) => loop_ir_const_step_direction(ty, lhs),
        Expr::Binary {
            op: BinaryOp::Sub,
            ty: expr_ty,
            lhs,
            rhs,
        } if *expr_ty == ty && loop_ir_expr_is_local(lhs, name, ty) => {
            if loop_ir_const_step_direction(ty, rhs) == Some(StepDirection::Asc) {
                Some(StepDirection::Desc)
            } else {
                None
            }
        }
        _ => None,
    }
}

fn canonicalize_loopwhile_primary(vars: &mut Vec<LoopVar>, cond: &Expr, next: &mut Vec<Expr>) {
    if vars.len() != next.len() {
        return;
    }
    let mut found = None;
    for (i, var) in vars.iter().enumerate() {
        if var.ty.is_float() {
            continue;
        }
        let Some(dir) = loop_ir_extract_compare(cond, &var.name, var.ty) else {
            continue;
        };
        if loop_ir_extract_step(&next[i], &var.name, var.ty) != Some(dir) {
            continue;
        }
        if found.is_some() {
            return;
        }
        found = Some(i);
    }
    let Some(idx) = found else {
        return;
    };
    if idx == 0 {
        return;
    }
    let primary_var = vars.remove(idx);
    let primary_next = next.remove(idx);
    vars.insert(0, primary_var);
    next.insert(0, primary_next);
}

fn infer_range_loop_type(args: &[AstExpr], ctx: &LowerCtx<'_>) -> Result<ScalarType, String> {
    let mut inferred_nonliteral = None;
    for arg in args {
        let ty = match &arg.kind {
            ExprKind::Number(n) if n.kind == NumberKind::Int => None,
            _ => known_expr_type(arg, ctx),
        };
        inferred_nonliteral = unify_types(inferred_nonliteral, ty)?;
    }
    if let Some(ty) = inferred_nonliteral {
        return Ok(ty);
    }

    let mut inferred = None;
    for arg in args {
        inferred = unify_types(inferred, known_expr_type(arg, ctx))?;
    }
    Ok(inferred.unwrap_or(ScalarType::U64))
}

fn lower_loop_next_assignments(
    next: &[AstLoopNextAssign],
    states: &[LoopStateBinding],
    ctx: &mut LowerCtx<'_>,
    backedge_last: Option<&str>,
) -> Result<Vec<Stmt>, String> {
    if states.is_empty() {
        if next.is_empty() {
            return Ok(Vec::new());
        }
        return unsupported("loop next section is only valid when the loop carries explicit state");
    }

    let next_values = collect_loop_next_values(next, states, ctx)?;

    let mut temp_entries = Vec::new();
    let mut out = Vec::new();
    for (state, value) in states.iter().zip(next_values.into_iter()) {
        let temp_name = ctx.fresh_temp("next");
        out.push(Stmt::Let {
            name: temp_name.clone(),
            ty: state.ty,
            init: value,
        });
        temp_entries.push((state.clone(), temp_name));
    }

    for (state, temp_name) in temp_entries
        .iter()
        .filter(|(state, _)| Some(state.source_name.as_str()) != backedge_last)
    {
        out.push(Stmt::Set {
            name: state.lowered_name.clone(),
            value: local_expr(temp_name.clone(), state.ty),
        });
    }
    if let Some(last_name) = backedge_last {
        if let Some((state, temp_name)) = temp_entries
            .iter()
            .find(|(state, _)| state.source_name == last_name)
        {
            out.push(Stmt::Set {
                name: state.lowered_name.clone(),
                value: local_expr(temp_name.clone(), state.ty),
            });
        }
    }
    Ok(out)
}

fn simple_path_name(expr: &AstExpr) -> Option<String> {
    match &expr.kind {
        ExprKind::Path(path) if path.segments.len() == 1 => binding_name(path).ok().map(|s| s.to_string()),
        _ => None,
    }
}

fn cached_domain_base(
    expr: &AstExpr,
    ctx: &mut LowerCtx<'_>,
    prefix: &str,
) -> Result<(Vec<Stmt>, IndexBaseInfo), String> {
    let base = index_base_info(expr, ctx)?;
    let limit = base.limit.clone().ok_or_else(|| {
        format!("{UNSUPPORTED_PREFIX}loop over domains require a bounded array/slice value, not a raw pointer")
    })?;
    let limit_ty = limit.ty();
    let limit_name = ctx.fresh_temp(&format!("{prefix}len"));
    let base_name = ctx.fresh_temp(&format!("{prefix}base"));
    Ok((
        vec![
            Stmt::Let {
                name: base_name.clone(),
                ty: ScalarType::Ptr,
                init: base.base_ptr,
            },
            Stmt::Let {
                name: limit_name.clone(),
                ty: limit_ty,
                init: limit,
            },
        ],
        IndexBaseInfo {
            base_ptr: local_expr(base_name, ScalarType::Ptr),
            elem_ty: base.elem_ty,
            elem_size: base.elem_size,
            limit: Some(local_expr(limit_name, limit_ty)),
        },
    ))
}

fn lower_loop_over_domain(
    domain: &AstExpr,
    ctx: &mut LowerCtx<'_>,
) -> Result<(Vec<Stmt>, ScalarType, Expr, Expr, Vec<(String, IndexBaseInfo)>), String> {
    if let ExprKind::Call { callee, args } = &domain.kind {
        if let ExprKind::Path(path) = &callee.kind {
            if path.segments.len() == 1 && path.segments[0] == "range" {
                let loop_ty = infer_range_loop_type(args, ctx)?;
                return match args.as_slice() {
                    [stop] => Ok((
                        Vec::new(),
                        loop_ty,
                        zero_expr(loop_ty),
                        lower_expr(stop, ctx, Some(loop_ty))?,
                        Vec::new(),
                    )),
                    [start, stop] => Ok((
                        Vec::new(),
                        loop_ty,
                        lower_expr(start, ctx, Some(loop_ty))?,
                        lower_expr(stop, ctx, Some(loop_ty))?,
                        Vec::new(),
                    )),
                    _ => unsupported("range(...) domains require one or two arguments"),
                };
            }
            if path.segments.len() == 1 && path.segments[0] == "zip_eq" {
                if args.len() < 2 {
                    return unsupported("zip_eq(...) domains require at least two bounded values");
                }
                let mut prelude = Vec::new();
                let mut overrides = Vec::new();
                let first_name = simple_path_name(&args[0]).ok_or_else(|| {
                    format!("{UNSUPPORTED_PREFIX}zip_eq(...) loop domains currently require simple path arguments")
                })?;
                let (first_prelude, first_base) = cached_domain_base(&args[0], ctx, "zip")?;
                let shared_limit = first_base
                    .limit
                    .clone()
                    .expect("cached domain base always carries a limit");
                let loop_ty = shared_limit.ty();
                prelude.extend(first_prelude);
                overrides.push((
                    first_name,
                    IndexBaseInfo {
                        base_ptr: first_base.base_ptr.clone(),
                        elem_ty: first_base.elem_ty,
                        elem_size: first_base.elem_size,
                        limit: Some(shared_limit.clone()),
                    },
                ));
                for arg in &args[1..] {
                    let name = simple_path_name(arg).ok_or_else(|| {
                        format!("{UNSUPPORTED_PREFIX}zip_eq(...) loop domains currently require simple path arguments")
                    })?;
                    let (member_prelude, member_base) = cached_domain_base(arg, ctx, "zip")?;
                    let member_limit = member_base
                        .limit
                        .clone()
                        .expect("cached domain base always carries a limit");
                    prelude.extend(member_prelude);
                    prelude.push(Stmt::Assert {
                        cond: Expr::Binary {
                            op: BinaryOp::Eq,
                            ty: ScalarType::Bool,
                            lhs: Box::new(shared_limit.clone()),
                            rhs: Box::new(member_limit),
                        },
                    });
                    overrides.push((
                        name,
                        IndexBaseInfo {
                            base_ptr: member_base.base_ptr.clone(),
                            elem_ty: member_base.elem_ty,
                            elem_size: member_base.elem_size,
                            limit: Some(shared_limit.clone()),
                        },
                    ));
                }
                return Ok((prelude, loop_ty, zero_expr(loop_ty), shared_limit, overrides));
            }
        }
    }

    let (prelude, base) = cached_domain_base(domain, ctx, "dom")?;
    let finish = base
        .limit
        .clone()
        .expect("cached domain base always carries a limit");
    let loop_ty = finish.ty();
    let overrides = if let Some(name) = simple_path_name(domain) {
        vec![(name, base)]
    } else {
        Vec::new()
    };
    Ok((prelude, loop_ty, zero_expr(loop_ty), finish, overrides))
}

fn lower_loop_stmt_native(loop_stmt: &AstLoopStmt, ctx: &mut LowerCtx<'_>) -> Result<Vec<Stmt>, String> {
    match &loop_stmt.head {
        AstLoopHead::While { vars, cond, .. } => {
            if vars.is_empty() {
                return unsupported("loop while requires at least one loop variable");
            }
            if block_contains_canonical_loop_control(&loop_stmt.body) {
                return unsupported("canonical loop bodies do not support break, continue, or return");
            }
            let names: HashSet<String> = vars.iter().map(|v| v.name.clone()).collect();
            if block_assigns_any_name(&loop_stmt.body, &names) {
                return unsupported("canonical loop bodies must update loop variables only through the next section");
            }

            ctx.push_scope();
            let mut ir_vars = Vec::new();
            let mut states = Vec::new();
            for var in vars {
                let ty = scalar_type_from_type_expr(&var.ty)?;
                let binding = ctx.bind(&var.name, ty, false, None, Some("var"));
                ir_vars.push(LoopVar {
                    name: binding.lowered_name.clone(),
                    ty,
                    init: lower_expr(&var.init, ctx, Some(ty))?,
                });
                states.push(LoopStateBinding {
                    source_name: var.name.clone(),
                    lowered_name: binding.lowered_name,
                    ty,
                });
            }
            let cond = lower_expr(cond, ctx, Some(ScalarType::Bool))?;
            ctx.push_scope();
            let body = lower_stmt_range(&loop_stmt.body.stmts, ctx, true, None)?;
            let mut next = collect_loop_next_values(&loop_stmt.next, &states, ctx)?;
            ctx.pop_scope();
            canonicalize_loopwhile_primary(&mut ir_vars, &cond, &mut next);
            ctx.pop_scope();
            Ok(vec![Stmt::LoopWhile {
                vars: ir_vars,
                cond,
                body,
                next,
            }])
        }
        AstLoopHead::Over {
            index,
            domain,
            carries,
            ..
        } => {
            if block_contains_canonical_loop_control(&loop_stmt.body) {
                return unsupported("canonical loop bodies do not support break, continue, or return");
            }
            let mut names: HashSet<String> = carries.iter().map(|v| v.name.clone()).collect();
            names.insert(index.clone());
            if block_assigns_any_name(&loop_stmt.body, &names) {
                return unsupported("canonical loop bodies must not assign to the loop index or carried state directly");
            }

            ctx.push_scope();
            let (mut out, states) = lower_loop_state_bindings(carries, ctx)?;
            let (domain_prelude, loop_ty, start, finish, overrides) = lower_loop_over_domain(domain, ctx)?;
            out.extend(domain_prelude);
            ctx.push_scope();
            ctx.push_domain_scope();
            let index_binding = ctx.bind(index, loop_ty, false, None, Some("var"));
            for (name, base) in overrides {
                ctx.bind_domain_override(&name, base);
            }
            let mut body = lower_stmt_range(&loop_stmt.body.stmts, ctx, true, None)?;
            body.extend(lower_loop_next_assignments(&loop_stmt.next, &states, ctx, None)?);
            ctx.pop_domain_scope();
            ctx.pop_scope();
            ctx.pop_scope();
            out.push(Stmt::ForRange {
                name: index_binding.lowered_name,
                ty: loop_ty,
                start,
                finish,
                step: Expr::Const { ty: loop_ty, bits: 1 },
                dir: None,
                inclusive: false,
                scoped: true,
                body,
            });
            Ok(out)
        }
    }
}

fn lower_loop_expr_native(
    loop_expr: &AstLoopExpr,
    ctx: &mut LowerCtx<'_>,
    expected: Option<ScalarType>,
) -> Result<Expr, String> {
    match &loop_expr.head {
        AstLoopHead::While { vars, cond, .. } => {
            if vars.is_empty() {
                return unsupported("loop while requires at least one loop variable");
            }
            if block_contains_canonical_loop_control(&loop_expr.body) {
                return unsupported("canonical loop bodies do not support break, continue, or return");
            }
            let names: HashSet<String> = vars.iter().map(|v| v.name.clone()).collect();
            if block_assigns_any_name(&loop_expr.body, &names) {
                return unsupported("canonical loop bodies must update loop variables only through the next section");
            }

            ctx.push_scope();
            let mut ir_vars = Vec::new();
            let mut states = Vec::new();
            for var in vars {
                let ty = scalar_type_from_type_expr(&var.ty)?;
                let binding = ctx.bind(&var.name, ty, false, None, Some("var"));
                ir_vars.push(LoopVar {
                    name: binding.lowered_name.clone(),
                    ty,
                    init: lower_expr(&var.init, ctx, Some(ty))?,
                });
                states.push(LoopStateBinding {
                    source_name: var.name.clone(),
                    lowered_name: binding.lowered_name,
                    ty,
                });
            }
            let cond = lower_expr(cond, ctx, Some(ScalarType::Bool))?;
            ctx.push_scope();
            let body = lower_stmt_range(&loop_expr.body.stmts, ctx, true, None)?;
            let mut next = collect_loop_next_values(&loop_expr.next, &states, ctx)?;
            ctx.pop_scope();
            canonicalize_loopwhile_primary(&mut ir_vars, &cond, &mut next);
            let result_ty = expected
                .or_else(|| known_expr_type(&loop_expr.result, ctx))
                .unwrap_or(ScalarType::I32);
            let result = lower_expr(&loop_expr.result, ctx, Some(result_ty))?;
            ctx.pop_scope();
            Ok(Expr::Block {
                ty: result_ty,
                stmts: vec![Stmt::LoopWhile {
                    vars: ir_vars,
                    cond,
                    body,
                    next,
                }],
                result: Box::new(result),
            })
        }
        AstLoopHead::Over {
            index,
            domain,
            carries,
            ..
        } => {
            if block_contains_canonical_loop_control(&loop_expr.body) {
                return unsupported("canonical loop bodies do not support break, continue, or return");
            }
            let mut names: HashSet<String> = carries.iter().map(|v| v.name.clone()).collect();
            names.insert(index.clone());
            if block_assigns_any_name(&loop_expr.body, &names) {
                return unsupported("canonical loop bodies must not assign to the loop index or carried state directly");
            }

            ctx.push_scope();
            let (mut stmts, states) = lower_loop_state_bindings(carries, ctx)?;
            let (domain_prelude, loop_ty, start, finish, overrides) = lower_loop_over_domain(domain, ctx)?;
            stmts.extend(domain_prelude);
            ctx.push_scope();
            ctx.push_domain_scope();
            let index_binding = ctx.bind(index, loop_ty, false, None, Some("var"));
            for (name, base) in overrides {
                ctx.bind_domain_override(&name, base);
            }
            let mut body = lower_stmt_range(&loop_expr.body.stmts, ctx, true, None)?;
            body.extend(lower_loop_next_assignments(&loop_expr.next, &states, ctx, None)?);
            ctx.pop_domain_scope();
            ctx.pop_scope();
            stmts.push(Stmt::ForRange {
                name: index_binding.lowered_name,
                ty: loop_ty,
                start,
                finish,
                step: Expr::Const { ty: loop_ty, bits: 1 },
                dir: None,
                inclusive: false,
                scoped: true,
                body,
            });
            let result_ty = expected
                .or_else(|| known_expr_type(&loop_expr.result, ctx))
                .unwrap_or(ScalarType::I32);
            let result = lower_expr(&loop_expr.result, ctx, Some(result_ty))?;
            ctx.pop_scope();
            Ok(Expr::Block {
                ty: result_ty,
                stmts,
                result: Box::new(result),
            })
        }
    }
}

fn lower_for_stmt(
    stmt: &ForStmt,
    ctx: &mut LowerCtx<'_>,
    in_loop: bool,
    return_state: Option<&ReturnState>,
) -> Result<Vec<Stmt>, String> {
    let loop_ty = scalar_type_from_type_expr(&TypeExpr::Path(Path {
        segments: vec!["i32".to_string()],
        span: stmt.span,
    }))
    .unwrap_or(ScalarType::I32);
    let start_ty = known_expr_type(&stmt.start, ctx);
    let end_ty = known_expr_type(&stmt.end, ctx);
    let step_ty = stmt.step.as_ref().and_then(|step| known_expr_type(step, ctx));
    let loop_ty = start_ty.or(end_ty).or(step_ty).unwrap_or(loop_ty);

    let start = lower_expr(&stmt.start, ctx, Some(loop_ty))?;
    let finish = lower_expr(&stmt.end, ctx, Some(loop_ty))?;
    let step = if let Some(step) = &stmt.step {
        lower_expr(step, ctx, Some(loop_ty))?
    } else {
        lower_number_const("1", NumberKind::Int, Some(loop_ty))?
    };

    ctx.push_scope();
    let binding = ctx.bind(&stmt.name, loop_ty, true, None, Some("var"));
    let body = lower_stmt_range(&stmt.body.stmts, ctx, true, return_state)?;
    ctx.pop_scope();

    let _ = in_loop;
    Ok(vec![Stmt::ForRange {
        name: binding.lowered_name,
        ty: loop_ty,
        start,
        finish,
        step,
        dir: None,
        inclusive: true,
        scoped: true,
        body,
    }])
}

fn local_layout_name(
    ty: Option<&TypeExpr>,
    value: &AstExpr,
    ctx: &LowerCtx<'_>,
) -> Option<String> {
    if let Some(ty) = ty {
        if let Some(name) = layout_name_from_type_expr(ty, ctx.structs, ctx.taggeds) {
            return Some(name);
        }
    }
    aggregate_ctor_layout_name(value, ctx.structs, ctx.taggeds)
}

fn local_array_layout(ty: Option<&TypeExpr>, value: &AstExpr) -> Option<ArrayLayout> {
    if let Some(ty) = ty {
        if let Some(layout) = array_layout_from_type_expr(ty) {
            return Some(layout);
        }
    }
    aggregate_ctor_array_layout(value)
}

fn populate_struct_slot(
    layout: &StructLayout,
    slot_name: &str,
    value: &AstExpr,
    ctx: &mut LowerCtx<'_>,
) -> Result<Vec<Stmt>, String> {
    let mut out = Vec::new();
    out.push(Stmt::Memset {
        dst: Expr::StackAddr {
            name: slot_name.to_string(),
        },
        byte: Expr::Const {
            ty: ScalarType::U8,
            bits: 0,
        },
        len: Expr::Const {
            ty: ScalarType::U64,
            bits: layout.size as u64,
        },
    });

    match &value.kind {
        ExprKind::Aggregate { ctor, fields } => {
            let TypeCtor::Path(path) = ctor else {
                return unsupported("native struct aggregate constructors require a named struct type");
            };
            let ctor_name = type_path_key(path);
            if ctor_name != layout.name {
                return Err(format!(
                    "native struct aggregate for '{}' cannot initialize '{}'",
                    ctor_name, layout.name
                ));
            }
            for field_value in fields {
                let crate::ast::AggregateField::Named { name, value, .. } = field_value else {
                    return unsupported("native struct aggregates currently require named fields");
                };
                let field = layout.fields.get(name).ok_or_else(|| {
                    format!("{UNSUPPORTED_PREFIX}struct '{}' has no field '{}'", layout.name, name)
                })?;
                let addr = struct_field_addr(
                    Expr::StackAddr {
                        name: slot_name.to_string(),
                    },
                    field,
                );
                out.push(Stmt::Store {
                    ty: field.ty,
                    addr,
                    value: lower_expr(value, ctx, Some(field.ty))?,
                });
            }
        }
        ExprKind::Path(path) => {
            let name = binding_name(path)?;
            let binding = ctx
                .lookup(name)
                .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown struct source '{name}'"))?;
            if binding.struct_name.as_deref() != Some(layout.name.as_str()) {
                return unsupported("native struct copies currently require the same struct type");
            }
            out.push(Stmt::Memcpy {
                dst: Expr::StackAddr {
                    name: slot_name.to_string(),
                },
                src: binding_value_expr(binding),
                len: Expr::Const {
                    ty: ScalarType::U64,
                    bits: layout.size as u64,
                },
            });
        }
        _ => {
            return unsupported("native struct locals currently require an aggregate literal or same-struct copy")
        }
    }
    Ok(out)
}

fn populate_tagged_variant_payload(
    layout: &TaggedUnionLayout,
    payload_base: Expr,
    variant_name: &str,
    value: &AstExpr,
    ctx: &mut LowerCtx<'_>,
) -> Result<Vec<Stmt>, String> {
    let variant_layout = layout.variants.get(variant_name).ok_or_else(|| {
        format!("{UNSUPPORTED_PREFIX}tagged union '{}' has no variant '{}'", layout.name, variant_name)
    })?;
    let mut out = Vec::new();
    match &value.kind {
        ExprKind::Aggregate { ctor, fields } => {
            let TypeCtor::Path(path) = ctor else {
                return unsupported("native tagged union variant payload constructors require a named ctor");
            };
            let ctor_name = type_path_key(path);
            let expected_short = format!("{}.{}", layout.name, variant_name);
            let expected_payload = format!("{}.Payload.{}", layout.name, variant_name);
            if ctor_name != expected_short && ctor_name != expected_payload {
                return Err(format!(
                    "native tagged union variant '{}' cannot be initialized from '{}'",
                    expected_short, ctor_name
                ));
            }
            for field_value in fields {
                let crate::ast::AggregateField::Named { name, value, .. } = field_value else {
                    return unsupported("native tagged union payload structs currently require named fields");
                };
                let field = variant_layout.fields.get(name).ok_or_else(|| {
                    format!(
                        "{UNSUPPORTED_PREFIX}payload variant '{}.{}' has no field '{}'",
                        layout.name, variant_name, name
                    )
                })?;
                out.push(Stmt::Store {
                    ty: field.ty,
                    addr: struct_field_addr(payload_base.clone(), field),
                    value: lower_expr(value, ctx, Some(field.ty))?,
                });
            }
        }
        _ => {
            return unsupported(
                "native tagged union payload initialization currently requires a matching variant aggregate",
            )
        }
    }
    Ok(out)
}

fn populate_tagged_payload(
    layout: &TaggedUnionLayout,
    payload_base: Expr,
    value: &AstExpr,
    ctx: &mut LowerCtx<'_>,
    zero_first: bool,
) -> Result<Vec<Stmt>, String> {
    let mut out = Vec::new();
    if zero_first {
        out.push(Stmt::Memset {
            dst: payload_base.clone(),
            byte: Expr::Const {
                ty: ScalarType::U8,
                bits: 0,
            },
            len: Expr::Const {
                ty: ScalarType::U64,
                bits: layout.payload_size as u64,
            },
        });
    }
    match &value.kind {
        ExprKind::Aggregate { ctor, fields } => {
            let TypeCtor::Path(path) = ctor else {
                return unsupported("native tagged union payload initialization requires a named ctor");
            };
            let ctor_name = type_path_key(path);
            let expected_payload = format!("{}.Payload", layout.name);
            if ctor_name == expected_payload {
                for field_value in fields {
                    let crate::ast::AggregateField::Named { name, value, .. } = field_value else {
                        return unsupported("native tagged union payload union aggregates require named fields");
                    };
                    out.extend(populate_tagged_variant_payload(
                        layout,
                        payload_base.clone(),
                        name,
                        value,
                        ctx,
                    )?);
                }
            } else if let Some((tagged_name, variant_name)) = tagged_variant_ctor_name(path, ctx.taggeds) {
                if tagged_name != layout.name {
                    return Err(format!(
                        "native tagged union payload for '{}' cannot be initialized from '{}'",
                        layout.name, ctor_name
                    ));
                }
                out.extend(populate_tagged_variant_payload(
                    layout,
                    payload_base,
                    &variant_name,
                    value,
                    ctx,
                )?);
            } else {
                return unsupported("native tagged union payload initialization requires a payload or variant ctor");
            }
        }
        ExprKind::Path(path) if path.segments.len() == 2 && path.segments[1] == "payload" => {
            let (binding, src_layout) = tagged_binding(path, ctx)?;
            if src_layout.name != layout.name {
                return unsupported("native tagged union payload copies currently require the same tagged union type");
            }
            out.push(Stmt::Memcpy {
                dst: payload_base,
                src: tagged_payload_base(binding_value_expr(binding), src_layout),
                len: Expr::Const {
                    ty: ScalarType::U64,
                    bits: layout.payload_size as u64,
                },
            });
        }
        _ => {
            return unsupported(
                "native tagged union payload initialization currently requires a payload aggregate, variant aggregate, or same-tagged payload copy",
            )
        }
    }
    Ok(out)
}

fn populate_tagged_slot(
    layout: &TaggedUnionLayout,
    slot_name: &str,
    value: &AstExpr,
    ctx: &mut LowerCtx<'_>,
) -> Result<Vec<Stmt>, String> {
    let base = Expr::StackAddr {
        name: slot_name.to_string(),
    };
    let payload_base = tagged_payload_base(base.clone(), layout);
    let mut out = vec![Stmt::Memset {
        dst: base.clone(),
        byte: Expr::Const {
            ty: ScalarType::U8,
            bits: 0,
        },
        len: Expr::Const {
            ty: ScalarType::U64,
            bits: layout.size as u64,
        },
    }];

    match &value.kind {
        ExprKind::Aggregate { ctor, fields } => {
            let TypeCtor::Path(path) = ctor else {
                return unsupported("native tagged union aggregate constructors require a named ctor");
            };
            let ctor_name = type_path_key(path);
            if ctor_name == layout.name {
                for field_value in fields {
                    let crate::ast::AggregateField::Named { name, value, .. } = field_value else {
                        return unsupported("native tagged union aggregates currently require named fields");
                    };
                    match name.as_str() {
                        "tag" => out.push(Stmt::Store {
                            ty: layout.tag_ty,
                            addr: base.clone(),
                            value: lower_expr(value, ctx, Some(layout.tag_ty))?,
                        }),
                        "payload" => out.extend(populate_tagged_payload(
                            layout,
                            payload_base.clone(),
                            value,
                            ctx,
                            false,
                        )?),
                        _ => {
                            return Err(format!(
                                "{UNSUPPORTED_PREFIX}tagged union '{}' has no field '{}'",
                                layout.name, name
                            ))
                        }
                    }
                }
            } else if let Some((tagged_name, variant_name)) = tagged_variant_ctor_name(path, ctx.taggeds) {
                if tagged_name != layout.name {
                    return Err(format!(
                        "native tagged union '{}' cannot be initialized from '{}'",
                        layout.name, ctor_name
                    ));
                }
                let tag_bits = *layout.variant_tags.get(&variant_name).expect("tagged variant tag exists");
                out.push(Stmt::Store {
                    ty: layout.tag_ty,
                    addr: base.clone(),
                    value: Expr::Const {
                        ty: layout.tag_ty,
                        bits: tag_bits,
                    },
                });
                out.extend(populate_tagged_variant_payload(
                    layout,
                    payload_base,
                    &variant_name,
                    value,
                    ctx,
                )?);
            } else {
                return unsupported("native tagged union aggregate constructors require the tagged union type or a tagged variant shorthand");
            }
        }
        ExprKind::Path(path) => {
            let name = binding_name(path)?;
            let binding = ctx
                .lookup(name)
                .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown tagged union source '{name}'"))?;
            if binding.struct_name.as_deref() != Some(layout.name.as_str()) {
                return unsupported("native tagged union copies currently require the same tagged union type");
            }
            out.push(Stmt::Memcpy {
                dst: base,
                src: binding_value_expr(binding),
                len: Expr::Const {
                    ty: ScalarType::U64,
                    bits: layout.size as u64,
                },
            });
        }
        _ => {
            return unsupported("native tagged union locals currently require an aggregate literal or same-tagged copy")
        }
    }
    Ok(out)
}

fn populate_array_slot(
    layout: &ArrayLayout,
    slot_name: &str,
    value: &AstExpr,
    ctx: &mut LowerCtx<'_>,
) -> Result<Vec<Stmt>, String> {
    let mut out = Vec::new();
    out.push(Stmt::Memset {
        dst: Expr::StackAddr {
            name: slot_name.to_string(),
        },
        byte: Expr::Const {
            ty: ScalarType::U8,
            bits: 0,
        },
        len: Expr::Const {
            ty: ScalarType::U64,
            bits: layout.size as u64,
        },
    });

    match &value.kind {
        ExprKind::Aggregate { ctor, fields } => {
            let TypeCtor::Array { len, elem, .. } = ctor else {
                return unsupported("native array aggregate constructors require an array ctor");
            };
            let elem_ty = scalar_type_from_type_expr(elem).map_err(|_| {
                format!("{UNSUPPORTED_PREFIX}native arrays currently require scalar/pointer element types")
            })?;
            let count = eval_const_u32(len).ok_or_else(|| {
                format!("{UNSUPPORTED_PREFIX}native array constructors require a constant length")
            })?;
            let ctor_layout = ArrayLayout {
                elem_ty,
                count,
                size: scalar_size(elem_ty).saturating_mul(count),
                align: scalar_align(elem_ty),
            };
            if ctor_layout.elem_ty != layout.elem_ty || ctor_layout.count != layout.count {
                return Err("native array aggregate type mismatch".to_string());
            }
            for (i, field_value) in fields.iter().enumerate() {
                let crate::ast::AggregateField::Positional { value, .. } = field_value else {
                    return unsupported("native arrays currently require positional aggregate entries");
                };
                let addr = array_elem_addr(
                    Expr::StackAddr {
                        name: slot_name.to_string(),
                    },
                    layout.elem_ty,
                    Expr::Const {
                        ty: ScalarType::I64,
                        bits: i as u64,
                    },
                );
                out.push(Stmt::Store {
                    ty: layout.elem_ty,
                    addr,
                    value: lower_expr(value, ctx, Some(layout.elem_ty))?,
                });
            }
        }
        ExprKind::Path(path) => {
            let (_, src_layout) = array_binding(path, ctx)?;
            if src_layout.elem_ty != layout.elem_ty || src_layout.count != layout.count {
                return unsupported("native array copies currently require the same array layout");
            }
            out.push(Stmt::Memcpy {
                dst: Expr::StackAddr {
                    name: slot_name.to_string(),
                },
                src: lower_path_expr(path, ctx)?,
                len: Expr::Const {
                    ty: ScalarType::U64,
                    bits: layout.size as u64,
                },
            });
        }
        _ => return unsupported("native arrays currently require an aggregate literal or same-array copy"),
    }
    Ok(out)
}

fn lower_stmt(
    stmt: &AstStmt,
    ctx: &mut LowerCtx<'_>,
    in_loop: bool,
    return_state: Option<&ReturnState>,
) -> Result<LoweredStmt, String> {
    match stmt {
        AstStmt::Let { name, ty, value, .. } => {
            if let Some(struct_name) = local_layout_name(ty.as_ref(), value, ctx) {
                let slot_name = ctx.fresh_temp(name);
                let stmts = if let Some(layout) = ctx.structs.get(&struct_name).cloned() {
                    let mut stmts = vec![Stmt::StackSlot {
                        name: slot_name.clone(),
                        size: layout.size,
                        align: layout.align,
                    }];
                    stmts.extend(populate_struct_slot(&layout, &slot_name, value, ctx)?);
                    stmts
                } else if let Some(layout) = ctx.taggeds.get(&struct_name).cloned() {
                    let mut stmts = vec![Stmt::StackSlot {
                        name: slot_name.clone(),
                        size: layout.size,
                        align: layout.align,
                    }];
                    stmts.extend(populate_tagged_slot(&layout, &slot_name, value, ctx)?);
                    stmts
                } else {
                    return Err(format!("{UNSUPPORTED_PREFIX}unknown native layout '{struct_name}'"));
                };
                ctx.bind_struct_slot(name, slot_name, struct_name, false);
                return Ok(LoweredStmt { stmts, stop: false });
            }
            if let Some(array_layout) = local_array_layout(ty.as_ref(), value) {
                let slot_name = ctx.fresh_temp(name);
                let mut stmts = vec![Stmt::StackSlot {
                    name: slot_name.clone(),
                    size: array_layout.size,
                    align: array_layout.align,
                }];
                stmts.extend(populate_array_slot(&array_layout, &slot_name, value, ctx)?);
                ctx.bind_array_slot(name, slot_name, array_layout, false);
                return Ok(LoweredStmt { stmts, stop: false });
            }
            let inferred = ty
                .as_ref()
                .map(scalar_type_from_type_expr)
                .transpose()?
                .or_else(|| known_expr_type(value, ctx))
                .unwrap_or(ScalarType::I32);
            let init = lower_expr(value, ctx, Some(inferred))?;
            let binding = ctx.bind(name, inferred, false, None, Some("let"));
            Ok(LoweredStmt {
                stmts: vec![Stmt::Let {
                    name: binding.lowered_name,
                    ty: inferred,
                    init,
                }],
                stop: false,
            })
        }
        AstStmt::Var { name, ty, value, .. } => {
            if let Some(struct_name) = local_layout_name(ty.as_ref(), value, ctx) {
                let slot_name = ctx.fresh_temp(name);
                let stmts = if let Some(layout) = ctx.structs.get(&struct_name).cloned() {
                    let mut stmts = vec![Stmt::StackSlot {
                        name: slot_name.clone(),
                        size: layout.size,
                        align: layout.align,
                    }];
                    stmts.extend(populate_struct_slot(&layout, &slot_name, value, ctx)?);
                    stmts
                } else if let Some(layout) = ctx.taggeds.get(&struct_name).cloned() {
                    let mut stmts = vec![Stmt::StackSlot {
                        name: slot_name.clone(),
                        size: layout.size,
                        align: layout.align,
                    }];
                    stmts.extend(populate_tagged_slot(&layout, &slot_name, value, ctx)?);
                    stmts
                } else {
                    return Err(format!("{UNSUPPORTED_PREFIX}unknown native layout '{struct_name}'"));
                };
                ctx.bind_struct_slot(name, slot_name, struct_name, true);
                return Ok(LoweredStmt { stmts, stop: false });
            }
            if let Some(array_layout) = local_array_layout(ty.as_ref(), value) {
                let slot_name = ctx.fresh_temp(name);
                let mut stmts = vec![Stmt::StackSlot {
                    name: slot_name.clone(),
                    size: array_layout.size,
                    align: array_layout.align,
                }];
                stmts.extend(populate_array_slot(&array_layout, &slot_name, value, ctx)?);
                ctx.bind_array_slot(name, slot_name, array_layout, true);
                return Ok(LoweredStmt { stmts, stop: false });
            }
            let inferred = ty
                .as_ref()
                .map(scalar_type_from_type_expr)
                .transpose()?
                .or_else(|| known_expr_type(value, ctx))
                .unwrap_or(ScalarType::I32);
            let init = lower_expr(value, ctx, Some(inferred))?;
            let binding = ctx.bind(name, inferred, true, None, Some("var"));
            Ok(LoweredStmt {
                stmts: vec![Stmt::Var {
                    name: binding.lowered_name,
                    ty: inferred,
                    init,
                }],
                stop: false,
            })
        }
        AstStmt::Assign { target, value, .. } => {
            if let ExprKind::Path(path) = &target.kind {
                if path.segments.len() == 2 {
                    let first = &path.segments[0];
                    let field_name = &path.segments[1];
                    let binding = ctx
                        .lookup(first)
                        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown assignment target '{first}'"))?;
                    let layout_name = binding.struct_name.as_ref().ok_or_else(|| {
                        format!("{UNSUPPORTED_PREFIX}assignment target '{first}' is not a struct/union/tagged union pointer/value")
                    })?;
                    if let Some(layout) = ctx.taggeds.get(layout_name) {
                        if field_name == "tag" {
                            return Ok(LoweredStmt {
                                stmts: vec![Stmt::Store {
                                    ty: layout.tag_ty,
                                    addr: binding_value_expr(binding),
                                    value: lower_expr(value, ctx, Some(layout.tag_ty))?,
                                }],
                                stop: false,
                            });
                        }
                        if field_name == "payload" {
                            return Ok(LoweredStmt {
                                stmts: populate_tagged_payload(
                                    layout,
                                    tagged_payload_base(binding_value_expr(binding), layout),
                                    value,
                                    ctx,
                                    true,
                                )?,
                                stop: false,
                            });
                        }
                        return Err(format!(
                            "{UNSUPPORTED_PREFIX}tagged union '{}' has no field '{}'",
                            layout.name, field_name
                        ));
                    }
                    let layout = ctx
                        .structs
                        .get(layout_name)
                        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown struct/union layout '{layout_name}'"))?;
                    let field = layout.fields.get(field_name).ok_or_else(|| {
                        format!("{UNSUPPORTED_PREFIX}struct '{}' has no field '{}'", layout.name, field_name)
                    })?;
                    return Ok(LoweredStmt {
                        stmts: vec![Stmt::Store {
                            ty: field.ty,
                            addr: struct_field_addr(binding_value_expr(binding), field),
                            value: lower_expr(value, ctx, Some(field.ty))?,
                        }],
                        stop: false,
                    });
                }
                if path.segments.len() == 4 && path.segments[1] == "payload" {
                    let first = &path.segments[0];
                    let variant_name = &path.segments[2];
                    let field_name = &path.segments[3];
                    let binding = ctx
                        .lookup(first)
                        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown assignment target '{first}'"))?;
                    let tagged_name = binding.struct_name.as_ref().ok_or_else(|| {
                        format!("{UNSUPPORTED_PREFIX}assignment target '{first}' is not a tagged union pointer/value")
                    })?;
                    let layout = ctx
                        .taggeds
                        .get(tagged_name)
                        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown tagged union layout '{tagged_name}'"))?;
                    let variant_layout = layout.variants.get(variant_name).ok_or_else(|| {
                        format!("{UNSUPPORTED_PREFIX}tagged union '{}' has no payload variant '{}'", layout.name, variant_name)
                    })?;
                    let field = variant_layout.fields.get(field_name).ok_or_else(|| {
                        format!("{UNSUPPORTED_PREFIX}payload variant '{}.{}' has no field '{}'", layout.name, variant_name, field_name)
                    })?;
                    return Ok(LoweredStmt {
                        stmts: vec![Stmt::Store {
                            ty: field.ty,
                            addr: struct_field_addr(
                                tagged_payload_base(binding_value_expr(binding), layout),
                                field,
                            ),
                            value: lower_expr(value, ctx, Some(field.ty))?,
                        }],
                        stop: false,
                    });
                }
                let name = binding_name(path)?;
                let binding = ctx
                    .lookup(name)
                    .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown assignment target '{name}'"))?
                    .clone();
                if !binding.mutable {
                    return Err(format!("cannot assign to immutable local '{name}'"));
                }
                if let (Some(struct_name), Some(slot_name)) =
                    (binding.struct_name.clone(), binding.stack_slot_name.clone())
                {
                    if let Some(layout) = ctx.structs.get(&struct_name).cloned() {
                        return Ok(LoweredStmt {
                            stmts: populate_struct_slot(&layout, &slot_name, value, ctx)?,
                            stop: false,
                        });
                    }
                    if let Some(layout) = ctx.taggeds.get(&struct_name).cloned() {
                        return Ok(LoweredStmt {
                            stmts: populate_tagged_slot(&layout, &slot_name, value, ctx)?,
                            stop: false,
                        });
                    }
                    return Err(format!("{UNSUPPORTED_PREFIX}unknown native layout '{struct_name}'"));
                }
                if let (Some(array_layout), Some(slot_name)) =
                    (binding.array_layout.clone(), binding.stack_slot_name.clone())
                {
                    return Ok(LoweredStmt {
                        stmts: populate_array_slot(&array_layout, &slot_name, value, ctx)?,
                        stop: false,
                    });
                }
                return Ok(LoweredStmt {
                    stmts: vec![Stmt::Set {
                        name: binding.lowered_name,
                        value: lower_expr(value, ctx, Some(binding.ty))?,
                    }],
                    stop: false,
                });
            }
            if let ExprKind::Field { base, name } = &target.kind {
                let layout_name = layout_name_of_expr(base, ctx).ok_or_else(|| {
                    format!("{UNSUPPORTED_PREFIX}native field assignment currently requires a layout local/arg base")
                })?;
                let base_ptr = lower_expr(base, ctx, Some(ScalarType::Ptr))?;
                if let Some(tagged) = ctx.taggeds.get(&layout_name) {
                    if name == "tag" {
                        return Ok(LoweredStmt {
                            stmts: vec![Stmt::Store {
                                ty: tagged.tag_ty,
                                addr: base_ptr,
                                value: lower_expr(value, ctx, Some(tagged.tag_ty))?,
                            }],
                            stop: false,
                        });
                    }
                    return unsupported("native tagged union postfix field assignment currently supports only '.tag'; use path syntax for payload fields");
                }
                let layout = ctx
                    .structs
                    .get(&layout_name)
                    .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}unknown struct/union layout '{layout_name}'"))?;
                let field = layout.fields.get(name).ok_or_else(|| {
                    format!("{UNSUPPORTED_PREFIX}struct '{}' has no field '{}'", layout.name, name)
                })?;
                return Ok(LoweredStmt {
                    stmts: vec![Stmt::Store {
                        ty: field.ty,
                        addr: struct_field_addr(base_ptr, field),
                        value: lower_expr(value, ctx, Some(field.ty))?,
                    }],
                    stop: false,
                });
            }
            if let ExprKind::Index { base, index } = &target.kind {
                let base_info = index_base_info(base, ctx)?;
                let idx = lower_expr(index, ctx, None)?;
                return Ok(LoweredStmt {
                    stmts: vec![Stmt::Store {
                        ty: base_info.elem_ty,
                        addr: Expr::IndexAddr {
                            base: Box::new(base_info.base_ptr),
                            index: Box::new(idx),
                            elem_size: base_info.elem_size,
                            limit: base_info.limit.map(Box::new),
                        },
                        value: lower_expr(value, ctx, Some(base_info.elem_ty))?,
                    }],
                    stop: false,
                });
            }
            unsupported("only simple local, layout field, tagged payload field, and array index assignment targets are supported natively")
        }
        AstStmt::While { cond, body, .. } => Ok(LoweredStmt {
            stmts: vec![Stmt::While {
                cond: guard_cond(lower_expr(cond, ctx, Some(ScalarType::Bool))?, return_state),
                body: lower_block_void(body, ctx, true, return_state)?,
            }],
            stop: false,
        }),
        AstStmt::For(v) => Ok(LoweredStmt {
            stmts: lower_for_stmt(v, ctx, in_loop, return_state)?,
            stop: false,
        }),
        AstStmt::Loop(v) => Ok(LoweredStmt {
            stmts: lower_loop_stmt_native(v, ctx)?,
            stop: false,
        }),
        AstStmt::If(v) => Ok(LoweredStmt {
            stmts: vec![lower_if_stmt_chain(v, ctx, in_loop, return_state)?],
            stop: stmt_always_returns(stmt),
        }),
        AstStmt::Switch(v) => Ok(LoweredStmt {
            stmts: lower_switch_stmt(v, ctx, in_loop, return_state)?,
            stop: stmt_always_returns(stmt),
        }),
        AstStmt::Break { .. } => Ok(LoweredStmt {
            stmts: vec![Stmt::Break],
            stop: true,
        }),
        AstStmt::Continue { .. } => Ok(LoweredStmt {
            stmts: vec![Stmt::Continue],
            stop: true,
        }),
        AstStmt::Return { value, .. } => lower_return_stmt(value, ctx, in_loop, return_state),
        AstStmt::Expr { expr, .. } => {
            let lowered = lower_expr(expr, ctx, None)?;
            match lowered {
                Expr::Call { target, args, .. } => Ok(LoweredStmt {
                    stmts: vec![Stmt::Call { target, args }],
                    stop: false,
                }),
                _ => Ok(LoweredStmt::default()),
            }
        }
        _ => unsupported("statement form is not yet supported by the native fast path"),
    }
}

fn lower_stmt_range(
    stmts: &[AstStmt],
    ctx: &mut LowerCtx<'_>,
    in_loop: bool,
    return_state: Option<&ReturnState>,
) -> Result<Vec<Stmt>, String> {
    let mut out = Vec::new();
    let mut i = 0usize;
    while i < stmts.len() {
        let lowered = lower_stmt(&stmts[i], ctx, in_loop, return_state)?;
        out.extend(lowered.stmts);
        if lowered.stop {
            return Ok(out);
        }
        if return_state.is_some() && stmt_has_return(&stmts[i]) && i + 1 < stmts.len() {
            let cond = not_expr(local_expr(
                return_state
                    .expect("checked above")
                    .returned_name
                    .clone(),
                ScalarType::Bool,
            ));
            let then_body = lower_stmt_range(&stmts[i + 1..], ctx, in_loop, return_state)?;
            out.push(Stmt::If {
                cond,
                then_body,
                else_body: Vec::new(),
            });
            return Ok(out);
        }
        i += 1;
    }
    Ok(out)
}

fn terminal_stmt_can_lower_direct_value(stmt: &AstStmt) -> bool {
    matches!(stmt, AstStmt::Return { .. } | AstStmt::Expr { .. } | AstStmt::If(_) | AstStmt::Switch(_))
}

fn block_can_lower_direct_value(block: &Block) -> bool {
    let Some((last, prefix)) = block.stmts.split_last() else {
        return false;
    };
    !prefix.iter().any(stmt_has_return) && terminal_stmt_can_lower_direct_value(last)
}

fn lower_function_body(
    func: &FuncDecl,
    ctx: &mut LowerCtx<'_>,
    result_ty: ScalarType,
) -> Result<Expr, String> {
    if !result_ty.is_void() && block_can_lower_direct_value(&func.body) {
        return lower_block_value(&func.body, ctx, Some(result_ty));
    }
    if result_ty.is_void() && !block_has_return(&func.body) {
        let stmts = lower_block_void(&func.body, ctx, false, None)?;
        return Ok(Expr::Block {
            ty: ScalarType::I8,
            stmts,
            result: Box::new(zero_expr(ScalarType::I8)),
        });
    }

    let mut stmts = Vec::new();
    let body_ty = if result_ty.is_void() { ScalarType::I8 } else { result_ty };
    let return_state = ReturnState {
        result_name: if result_ty.is_void() {
            None
        } else {
            Some(ctx.fresh_temp("retv"))
        },
        result_ty: if result_ty.is_void() { None } else { Some(result_ty) },
        returned_name: ctx.fresh_temp("returned"),
        void_function: result_ty.is_void(),
    };

    if let Some(result_name) = &return_state.result_name {
        stmts.push(Stmt::Var {
            name: result_name.clone(),
            ty: result_ty,
            init: zero_expr(result_ty),
        });
    }
    stmts.push(Stmt::Var {
        name: return_state.returned_name.clone(),
        ty: ScalarType::Bool,
        init: bool_expr(false),
    });

    let mut lowered_stmts = func.body.stmts.clone();
    if !result_ty.is_void() && !block_always_returns(&func.body) {
        let Some(last) = lowered_stmts.last_mut() else {
            return unsupported("non-void native function body is empty");
        };
        match last {
            AstStmt::Expr { expr, span } => {
                let value = expr.clone();
                *last = AstStmt::Return {
                    value: Some(value),
                    span: *span,
                };
            }
            _ => {
                return unsupported(
                    "non-void function must end in a tail expression or return statement",
                )
            }
        }
    }

    stmts.extend(lower_stmt_range(&lowered_stmts, ctx, false, Some(&return_state))?);
    let result_expr = if let Some(result_name) = &return_state.result_name {
        local_expr(result_name.clone(), result_ty)
    } else {
        zero_expr(body_ty)
    };
    Ok(Expr::Block {
        ty: body_ty,
        stmts,
        result: Box::new(result_expr),
    })
}

fn build_sig_map_for_funcs(
    funcs: &[&FuncDecl],
    externs: &[(&Item, &ExternFuncDecl)],
) -> Result<HashMap<String, FuncSigInfo>, String> {
    let mut out = HashMap::new();
    for func in funcs {
        let name = func_name_symbol(func)?;
        let mut params = Vec::with_capacity(func.sig.params.len());
        for param in &func.sig.params {
            params.push(scalar_type_from_type_expr(&param.ty)?);
        }
        let result = func
            .sig
            .result
            .as_ref()
            .map(scalar_type_from_type_expr)
            .transpose()?;
        out.insert(
            name.clone(),
            FuncSigInfo {
                symbol: name,
                params,
                result,
            },
        );
    }
    for (item, decl) in externs {
        let mut params = Vec::with_capacity(decl.params.len());
        for param in &decl.params {
            params.push(scalar_type_from_type_expr(&param.ty)?);
        }
        let result = decl
            .result
            .as_ref()
            .map(scalar_type_from_type_expr)
            .transpose()?
            .unwrap_or(ScalarType::Void);
        out.insert(
            decl.name.clone(),
            FuncSigInfo {
                symbol: extern_symbol(item, decl),
                params,
                result: Some(result),
            },
        );
    }
    Ok(out)
}

fn infer_sig_results(
    funcs: &[&FuncDecl],
    sig_map: &mut HashMap<String, FuncSigInfo>,
    method_map: &HashMap<String, HashMap<String, FuncSigInfo>>,
    structs: &HashMap<String, StructLayout>,
    taggeds: &HashMap<String, TaggedUnionLayout>,
) -> Result<(), String> {
    loop {
        let mut changed = false;
        for func in funcs {
            let name = func_name_symbol(func)?;
            let current = sig_map.get(&name).and_then(|info| info.result);
            if current.is_some() {
                continue;
            }
            if let Some(inferred) = infer_function_result(func, sig_map, method_map, structs, taggeds)? {
                sig_map
                    .get_mut(&name)
                    .expect("function signature entry should exist")
                    .result = Some(inferred);
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    Ok(())
}

fn extern_meta_from_decl(item: &Item, decl: &ExternFuncDecl) -> Result<NativeExternMeta, String> {
    let mut params = Vec::with_capacity(decl.params.len());
    for param in &decl.params {
        params.push(prepare_param_meta(param)?);
    }
    Ok(NativeExternMeta {
        name: decl.name.clone(),
        symbol: extern_symbol(item, decl),
        params,
        result: decl
            .result
            .as_ref()
            .map(scalar_type_from_type_expr)
            .transpose()?
            .unwrap_or(ScalarType::Void),
    })
}

fn meta_from_func_decl(
    func: &FuncDecl,
    sig_map: &HashMap<String, FuncSigInfo>,
) -> Result<NativeFuncMeta, String> {
    let name = func_name_symbol(func)?;
    let info = sig_map
        .get(&name)
        .ok_or_else(|| format!("{UNSUPPORTED_PREFIX}missing function signature for '{name}'"))?;
    let result = info.result.ok_or_else(|| {
        format!(
            "{UNSUPPORTED_PREFIX}could not infer result type for function '{name}'; add an explicit result type"
        )
    })?;
    let mut params = Vec::with_capacity(func.sig.params.len());
    for param in &func.sig.params {
        params.push(prepare_param_meta(param)?);
    }
    Ok(NativeFuncMeta {
        name,
        params,
        result,
        owner: None,
        method_name: None,
    })
}

fn lower_func_decl(
    func: &FuncDecl,
    meta: &NativeFuncMeta,
    sig_map: &HashMap<String, FuncSigInfo>,
    method_map: &HashMap<String, HashMap<String, FuncSigInfo>>,
    structs: &HashMap<String, StructLayout>,
    taggeds: &HashMap<String, TaggedUnionLayout>,
) -> Result<FunctionSpec, String> {
    let mut ctx = LowerCtx::new(sig_map, method_map, structs, taggeds);
    let mut lowered_params = Vec::with_capacity(meta.params.len());
    for (i, param) in meta.params.iter().enumerate() {
        let struct_name = pointer_struct_name_from_type_expr(&func.sig.params[i].ty, structs, taggeds);
        let pointer_elem_ty = pointer_elem_scalar_from_type_expr(&func.sig.params[i].ty);
        ctx.bind_param(&param.name, param.ty, (i + 1) as u32, struct_name, pointer_elem_ty);
        lowered_params.push(param.ty);
    }
    let body = lower_function_body(func, &mut ctx, meta.result)?;
    Ok(FunctionSpec {
        name: meta.name.clone(),
        params: lowered_params,
        result: meta.result,
        locals: Vec::new(),
        body,
    })
}

pub fn prepare_code_item_ast(item: &Item) -> Result<PreparedCode, String> {
    let ItemKind::Func(func) = &item.kind else {
        return unsupported("only func code items are currently supported natively");
    };
    let funcs = vec![func];
    let mut sig_map = build_sig_map_for_funcs(&funcs, &[])?;
    let empty_methods = HashMap::new();
    let empty_structs = HashMap::new();
    let empty_taggeds = HashMap::new();
    infer_sig_results(&funcs, &mut sig_map, &empty_methods, &empty_structs, &empty_taggeds)?;
    let meta = meta_from_func_decl(func, &sig_map)?;
    let spec = lower_func_decl(func, &meta, &sig_map, &empty_methods, &empty_structs, &empty_taggeds)?;
    Ok(PreparedCode { meta, spec })
}

fn infer_relaxed_sig_results(
    callables: &[RelaxCallable<'_>],
    funcs: &mut HashMap<String, FuncSigInfo>,
    methods: &mut HashMap<String, HashMap<String, FuncSigInfo>>,
    structs: &HashMap<String, StructLayout>,
    taggeds: &HashMap<String, TaggedUnionLayout>,
) -> Result<(), String> {
    loop {
        let mut changed = false;
        for callable in callables {
            let current = if let (Some(owner), Some(method_name)) =
                (callable.method_owner.as_ref(), callable.method_name.as_ref())
            {
                methods
                    .get(owner)
                    .and_then(|bucket| bucket.get(method_name))
                    .and_then(|sig| sig.result)
            } else {
                let name = callable
                    .source_name
                    .as_ref()
                    .expect("free callable source name is present");
                funcs.get(name).and_then(|sig| sig.result)
            };
            if current.is_some() {
                continue;
            }
            if let Some(inferred) = infer_function_result(callable.func, funcs, methods, structs, taggeds)? {
                if let (Some(owner), Some(method_name)) =
                    (callable.method_owner.as_ref(), callable.method_name.as_ref())
                {
                    methods
                        .get_mut(owner)
                        .and_then(|bucket| bucket.get_mut(method_name))
                        .expect("method signature entry should exist")
                        .result = Some(inferred);
                } else {
                    let name = callable
                        .source_name
                        .as_ref()
                        .expect("free callable source name is present");
                    funcs.get_mut(name)
                        .expect("function signature entry should exist")
                        .result = Some(inferred);
                }
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    Ok(())
}

pub fn prepare_module_ast(module: &ModuleAst) -> Result<PreparedModule, String> {
    let structs = collect_struct_layouts(module)?;
    let taggeds = collect_tagged_union_layouts(module)?;

    let mut funcs: HashMap<String, FuncSigInfo> = HashMap::new();
    let mut methods: HashMap<String, HashMap<String, FuncSigInfo>> = HashMap::new();
    let mut callables: Vec<RelaxCallable<'_>> = Vec::new();
    let mut types_meta: Vec<NativeTypeMeta> = Vec::new();
    let mut externs_meta: Vec<NativeExternMeta> = Vec::new();
    let mut consts_meta: Vec<NativeConstMeta> = Vec::new();
    let mut meta_complete = true;
    let mut eval_state = ExportEvalState {
        const_decls: HashMap::new(),
        const_types: HashMap::new(),
        const_values: HashMap::new(),
        type_stack: HashSet::new(),
        value_stack: HashSet::new(),
        aliases: HashMap::new(),
        enums: HashMap::new(),
        taggeds: &taggeds,
        structs: &structs,
    };

    for item in &module.items {
        match &item.kind {
            ItemKind::Struct(_) | ItemKind::Union(_) | ItemKind::TaggedUnion(_) => match type_meta_from_item(item) {
                Ok(Some(meta)) => types_meta.push(meta),
                Ok(None) => {}
                Err(_) => meta_complete = false,
            },
            ItemKind::Slice(decl) => {
                match type_meta_from_item(item) {
                    Ok(Some(meta)) => types_meta.push(meta),
                    Ok(None) => {}
                    Err(_) => meta_complete = false,
                }
                if let Ok(elem) = type_ref_meta_from_type_expr(&decl.ty) {
                    eval_state
                        .aliases
                        .insert(decl.name.clone(), NativeTypeRefMeta::Slice(Box::new(elem)));
                } else {
                    meta_complete = false;
                }
            }
            ItemKind::TypeAlias(decl) => {
                match type_meta_from_item(item) {
                    Ok(Some(meta)) => types_meta.push(meta),
                    Ok(None) => {}
                    Err(_) => meta_complete = false,
                }
                if let Ok(alias_ty) = type_ref_meta_from_type_expr(&decl.ty) {
                    eval_state.aliases.insert(decl.name.clone(), alias_ty);
                } else {
                    meta_complete = false;
                }
            }
            ItemKind::Enum(decl) => {
                let enum_meta = (|| -> Result<NativeTypeMeta, String> {
                    let base = decl
                        .base_ty
                        .as_ref()
                        .map(type_ref_meta_from_type_expr)
                        .transpose()?
                        .unwrap_or_else(|| NativeTypeRefMeta::Scalar("u8".to_string()));
                    let mut local_values: HashMap<String, ConstEvalValue> = HashMap::new();
                    let mut local_types: HashMap<String, NativeTypeRefMeta> = HashMap::new();
                    let mut members_meta = Vec::with_capacity(decl.members.len());
                    let mut members = HashMap::new();
                    eval_state.enums.insert(
                        decl.name.clone(),
                        EnumEvalInfo {
                            base: base.clone(),
                            members: HashMap::new(),
                        },
                    );
                    for (i, member) in decl.members.iter().enumerate() {
                        let raw_value = if let Some(value) = &member.value {
                            eval_state.eval_expr(value, &local_values, &local_types)?
                        } else {
                            ConstEvalValue::Int(i as i64)
                        };
                        let casted = cast_const_value_to_type(raw_value, &base, &eval_state.enums)?;
                        let numeric = const_as_i64(&casted)?;
                        members_meta.push(NativeEnumMemberMeta {
                            name: member.name.clone(),
                            value: numeric,
                        });
                        members.insert(member.name.clone(), numeric);
                        if let Some(current) = eval_state.enums.get_mut(&decl.name) {
                            current.members.insert(member.name.clone(), numeric);
                        }
                        local_values.insert(member.name.clone(), ConstEvalValue::Int(numeric));
                        local_types.insert(member.name.clone(), NativeTypeRefMeta::Path(decl.name.clone()));
                    }
                    if let Some(current) = eval_state.enums.get_mut(&decl.name) {
                        current.members = members;
                    }
                    Ok(NativeTypeMeta::Enum {
                        name: decl.name.clone(),
                        base,
                        members: members_meta,
                    })
                })();
                match enum_meta {
                    Ok(meta) => types_meta.push(meta),
                    Err(_) => meta_complete = false,
                }
            }
            ItemKind::Const(decl) => {
                eval_state.const_decls.insert(decl.name.clone(), decl);
            }
            ItemKind::ExternFunc(decl) => {
                if let Ok(meta) = extern_meta_from_decl(item, decl) {
                    externs_meta.push(meta);
                } else {
                    meta_complete = false;
                }
            }
            ItemKind::Opaque(_) | ItemKind::Splice(_) => {
                meta_complete = false;
            }
            _ => {}
        }
        match &item.kind {
            ItemKind::ExternFunc(decl) => {
                let mut params = Vec::with_capacity(decl.params.len());
                for param in &decl.params {
                    params.push(scalar_type_from_type_expr(&param.ty)?);
                }
                let result = decl
                    .result
                    .as_ref()
                    .map(scalar_type_from_type_expr)
                    .transpose()?
                    .unwrap_or(ScalarType::Void);
                funcs.insert(
                    decl.name.clone(),
                    FuncSigInfo {
                        symbol: extern_symbol(item, decl),
                        params,
                        result: Some(result),
                    },
                );
            }
            ItemKind::Func(func) => {
                let name = func_name_symbol(func)?;
                let mut params = Vec::with_capacity(func.sig.params.len());
                for param in &func.sig.params {
                    params.push(scalar_type_from_type_expr(&param.ty)?);
                }
                let result = func
                    .sig
                    .result
                    .as_ref()
                    .map(scalar_type_from_type_expr)
                    .transpose()?;
                funcs.insert(
                    name.clone(),
                    FuncSigInfo {
                        symbol: name.clone(),
                        params,
                        result,
                    },
                );
                callables.push(RelaxCallable {
                    display_name: name.clone(),
                    source_name: Some(name),
                    method_owner: None,
                    method_name: None,
                    func,
                });
            }
            ItemKind::Impl(impl_decl) => {
                let target_name = path_name(&impl_decl.target)?.to_string();
                if !structs.contains_key(&target_name) && !taggeds.contains_key(&target_name) {
                    return unsupported(format!(
                        "native relaxed impl target '{}' must be a known struct/union/tagged union",
                        target_name
                    ));
                }
                for impl_item in &impl_decl.items {
                    let func = &impl_item.func;
                    let method_name = func_name_symbol(func)?;
                    let symbol = format!("{}_{}", target_name, method_name);
                    let mut params = Vec::with_capacity(func.sig.params.len());
                    for param in &func.sig.params {
                        params.push(scalar_type_from_type_expr(&param.ty)?);
                    }
                    let result = func
                        .sig
                        .result
                        .as_ref()
                        .map(scalar_type_from_type_expr)
                        .transpose()?;
                    methods
                        .entry(target_name.clone())
                        .or_default()
                        .insert(
                            method_name.clone(),
                            FuncSigInfo {
                                symbol: symbol.clone(),
                                params,
                                result,
                            },
                        );
                    callables.push(RelaxCallable {
                        display_name: symbol,
                        source_name: None,
                        method_owner: Some(target_name.clone()),
                        method_name: Some(method_name),
                        func,
                    });
                }
            }
            _ => {}
        }
    }

    for item in &module.items {
        if let ItemKind::Const(decl) = &item.kind {
            let const_meta = (|| -> Result<NativeConstMeta, String> {
                let ty = eval_state.infer_named_const_type(&decl.name)?;
                let value = eval_state.eval_named_const(&decl.name)?;
                Ok(NativeConstMeta {
                    name: decl.name.clone(),
                    ty,
                    value: const_eval_to_meta(&value),
                })
            })();
            match const_meta {
                Ok(meta) => consts_meta.push(meta),
                Err(_) => meta_complete = false,
            }
        }
    }

    infer_relaxed_sig_results(&callables, &mut funcs, &mut methods, &structs, &taggeds)?;

    let mut prepared = Vec::with_capacity(callables.len());
    for callable in callables {
        let sig = if let (Some(owner), Some(method_name)) =
            (callable.method_owner.as_ref(), callable.method_name.as_ref())
        {
            methods
                .get(owner)
                .and_then(|bucket| bucket.get(method_name))
                .cloned()
                .expect("method signature should exist")
        } else {
            funcs.get(
                callable
                    .source_name
                    .as_ref()
                    .expect("free callable source name is present"),
            )
            .cloned()
            .expect("function signature should exist")
        };
        let result = sig.result.ok_or_else(|| {
            format!(
                "{UNSUPPORTED_PREFIX}could not infer result type for '{}' ; add an explicit result type",
                callable.display_name
            )
        })?;
        let mut params = Vec::with_capacity(callable.func.sig.params.len());
        for param in &callable.func.sig.params {
            params.push(prepare_param_meta(param)?);
        }
        let meta = NativeFuncMeta {
            name: callable.display_name.clone(),
            params,
            result,
            owner: callable.method_owner.clone(),
            method_name: callable.method_name.clone(),
        };
        prepared.push(PreparedCode {
            meta: meta.clone(),
            spec: lower_func_decl(callable.func, &meta, &funcs, &methods, &structs, &taggeds)?,
        });
    }

    Ok(PreparedModule {
        funcs: prepared,
        types: types_meta,
        externs: externs_meta,
        consts: consts_meta,
        meta_complete,
    })
}

pub fn prepare_code(source: &str) -> Result<PreparedCode, String> {
    let item = parse_code(source).map_err(|e| e.render(source))?;
    prepare_code_item_ast(&item)
}

pub fn prepare_module_relaxed(source: &str) -> Result<PreparedModule, String> {
    let module = parse_module(source).map_err(|e| e.render(source))?;
    prepare_module_ast(&module)
}

pub fn prepare_expr_ast(expr: &AstExpr) -> Result<PreparedExpr, String> {
    let funcs = HashMap::new();
    let methods = HashMap::new();
    let structs = HashMap::new();
    let taggeds = HashMap::new();
    let mut ctx = LowerCtx::new(&funcs, &methods, &structs, &taggeds);
    let lowered = lower_expr(expr, &mut ctx, None)?;
    let ty = lowered.ty();
    if ty.is_void() {
        return unsupported("standalone expr source must produce a value");
    }
    Ok(PreparedExpr { expr: lowered, ty })
}

pub fn prepare_expr(source: &str) -> Result<PreparedExpr, String> {
    let expr = parse_source_expr(source).map_err(|e| e.render(source))?;
    prepare_expr_ast(&expr)
}

pub fn prepare_type_ast(ty: &TypeExpr) -> Result<NativeTypeRefMeta, String> {
    type_ref_meta_from_type_expr(ty)
}

pub fn prepare_type_meta(source: &str) -> Result<NativeTypeRefMeta, String> {
    let ty = parse_type(source).map_err(|e| e.render(source))?;
    prepare_type_ast(&ty)
}

pub fn prepare_externs_items_ast(items: &[Item]) -> Result<Vec<NativeExternMeta>, String> {
    let mut out = Vec::with_capacity(items.len());
    for item in items {
        match &item.kind {
            ItemKind::ExternFunc(decl) => out.push(extern_meta_from_decl(item, decl)?),
            _ => return unsupported("extern fragment expects only extern func declarations"),
        }
    }
    Ok(out)
}

pub fn prepare_externs_meta(source: &str) -> Result<Vec<NativeExternMeta>, String> {
    let items = parse_externs(source).map_err(|e| e.render(source))?;
    prepare_externs_items_ast(&items)
}
