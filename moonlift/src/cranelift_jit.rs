use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::{InstBuilder, MemFlags, UserFuncName, Value, types};
use cranelift_codegen::settings::Configurable;
use cranelift_codegen::{ir, settings};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Variable};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{default_libcall_names, Linkage, Module};
use std::collections::HashMap;
use std::error::Error;
use std::fmt;
use std::mem;

#[derive(Debug)]
pub struct JitError(pub String);

impl fmt::Display for JitError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl Error for JitError {}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ScalarType {
    Void,
    Bool,
    I8,
    I16,
    I32,
    I64,
    U8,
    U16,
    U32,
    U64,
    F32,
    F64,
    Ptr,
}

impl ScalarType {
    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "void" => Some(Self::Void),
            "bool" => Some(Self::Bool),
            "i8" => Some(Self::I8),
            "i16" => Some(Self::I16),
            "i32" => Some(Self::I32),
            "i64" => Some(Self::I64),
            "isize" => Some(Self::I64),
            "u8" | "byte" => Some(Self::U8),
            "u16" => Some(Self::U16),
            "u32" => Some(Self::U32),
            "u64" | "usize" => Some(Self::U64),
            "f32" => Some(Self::F32),
            "f64" => Some(Self::F64),
            "ptr" => Some(Self::Ptr),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Void => "void",
            Self::Bool => "bool",
            Self::I8 => "i8",
            Self::I16 => "i16",
            Self::I32 => "i32",
            Self::I64 => "i64",
            Self::U8 => "u8",
            Self::U16 => "u16",
            Self::U32 => "u32",
            Self::U64 => "u64",
            Self::F32 => "f32",
            Self::F64 => "f64",
            Self::Ptr => "ptr",
        }
    }

    pub fn abi_type(self) -> ir::Type {
        match self {
            Self::Void => panic!("moonlift void has no ABI value type"),
            Self::Bool | Self::I8 | Self::U8 => types::I8,
            Self::I16 | Self::U16 => types::I16,
            Self::I32 | Self::U32 => types::I32,
            Self::I64 | Self::U64 | Self::Ptr => types::I64,
            Self::F32 => types::F32,
            Self::F64 => types::F64,
        }
    }

    pub fn is_void(self) -> bool {
        matches!(self, Self::Void)
    }

    pub fn is_bool(self) -> bool {
        matches!(self, Self::Bool)
    }

    pub fn is_float(self) -> bool {
        matches!(self, Self::F32 | Self::F64)
    }

    pub fn is_integer(self) -> bool {
        !self.is_float()
    }

    pub fn is_signed_integer(self) -> bool {
        matches!(self, Self::I8 | Self::I16 | Self::I32 | Self::I64)
    }

}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum UnaryOp {
    Neg,
    Not,
    Bnot,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
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
    Band,
    Bor,
    Bxor,
    Shl,
    ShrU,
    ShrS,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum CastOp {
    Cast,
    Trunc,
    Zext,
    Sext,
    Bitcast,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum CallTarget {
    Direct {
        name: String,
        params: Vec<ScalarType>,
        result: ScalarType,
    },
    Indirect {
        addr: Box<Expr>,
        params: Vec<ScalarType>,
        result: ScalarType,
    },
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Expr {
    Arg { index: u32, ty: ScalarType },
    Local { name: String, ty: ScalarType },
    Const { ty: ScalarType, bits: u64 },
    Unary {
        op: UnaryOp,
        ty: ScalarType,
        value: Box<Expr>,
    },
    Binary {
        op: BinaryOp,
        ty: ScalarType,
        lhs: Box<Expr>,
        rhs: Box<Expr>,
    },
    Let {
        name: String,
        ty: ScalarType,
        init: Box<Expr>,
        body: Box<Expr>,
    },
    Block {
        stmts: Vec<Stmt>,
        result: Box<Expr>,
        ty: ScalarType,
    },
    If {
        cond: Box<Expr>,
        then_expr: Box<Expr>,
        else_expr: Box<Expr>,
        ty: ScalarType,
    },
    Load {
        ty: ScalarType,
        addr: Box<Expr>,
    },
    Cast {
        op: CastOp,
        ty: ScalarType,
        value: Box<Expr>,
    },
    Call {
        target: CallTarget,
        ty: ScalarType,
        args: Vec<Expr>,
    },
}

impl Expr {
    pub fn ty(&self) -> ScalarType {
        match self {
            Expr::Arg { ty, .. }
            | Expr::Local { ty, .. }
            | Expr::Const { ty, .. }
            | Expr::Unary { ty, .. }
            | Expr::Binary { ty, .. }
            | Expr::Let { ty, .. }
            | Expr::Block { ty, .. }
            | Expr::If { ty, .. }
            | Expr::Load { ty, .. }
            | Expr::Cast { ty, .. }
            | Expr::Call { ty, .. } => *ty,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Stmt {
    Let {
        name: String,
        ty: ScalarType,
        init: Expr,
    },
    Var {
        name: String,
        ty: ScalarType,
        init: Expr,
    },
    Set {
        name: String,
        value: Expr,
    },
    While {
        cond: Expr,
        body: Vec<Stmt>,
    },
    Store {
        ty: ScalarType,
        addr: Expr,
        value: Expr,
    },
    Call {
        target: CallTarget,
        args: Vec<Expr>,
    },
    Break,
    Continue,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct LocalDecl {
    pub name: String,
    pub ty: ScalarType,
    pub init: Expr,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct FunctionSpec {
    pub name: String,
    pub params: Vec<ScalarType>,
    pub result: ScalarType,
    pub locals: Vec<LocalDecl>,
    pub body: Expr,
}

enum CodePtr {
    Arity0(unsafe extern "C" fn() -> u64),
    Arity1(unsafe extern "C" fn(u64) -> u64),
    Arity2(unsafe extern "C" fn(u64, u64) -> u64),
    Arity3(unsafe extern "C" fn(u64, u64, u64) -> u64),
    Arity4(unsafe extern "C" fn(u64, u64, u64, u64) -> u64),
}

struct CompiledFn {
    name: String,
    params: Vec<ScalarType>,
    result: ScalarType,
    code: CodePtr,
}

#[derive(Clone, Copy)]
enum Binding {
    Value(Value),
    Var(Variable),
}

#[derive(Clone)]
struct LowerCtx {
    args: Vec<Value>,
    bindings: HashMap<String, Binding>,
}

#[derive(Clone, Copy, Debug)]
pub struct CompileStats {
    pub compile_hits: u64,
    pub compile_misses: u64,
    pub cache_entries: usize,
    pub compiled_functions: usize,
}

pub struct MoonliftJit {
    module: JITModule,
    add_i32_i32: unsafe extern "C" fn(i32, i32) -> i32,
    next_handle: u32,
    functions: HashMap<u32, CompiledFn>,
    spec_cache: HashMap<FunctionSpec, u32>,
    compile_hits: u64,
    compile_misses: u64,
}

impl MoonliftJit {
    pub fn new() -> Result<Self, JitError> {
        let mut flag_builder = settings::builder();
        flag_builder
            .set("use_colocated_libcalls", "false")
            .map_err(|e| JitError(format!("failed to set Cranelift flag use_colocated_libcalls: {e}")))?;
        flag_builder
            .set("is_pic", "false")
            .map_err(|e| JitError(format!("failed to set Cranelift flag is_pic: {e}")))?;

        let isa_builder = cranelift_native::builder()
            .map_err(|e| JitError(format!("host machine is not supported by Cranelift: {e}")))?;
        let isa = isa_builder
            .finish(settings::Flags::new(flag_builder))
            .map_err(|e| JitError(format!("failed to finalize Cranelift ISA: {e}")))?;

        let builder = JITBuilder::with_isa(isa, default_libcall_names());
        let mut module = JITModule::new(builder);
        let add_i32_i32 = compile_add_i32_i32(&mut module)?;
        Ok(Self {
            module,
            add_i32_i32,
            next_handle: 1,
            functions: HashMap::new(),
            spec_cache: HashMap::new(),
            compile_hits: 0,
            compile_misses: 0,
        })
    }

    pub fn add_i32_i32(&self, a: i32, b: i32) -> i32 {
        unsafe { (self.add_i32_i32)(a, b) }
    }

    pub fn compile_function(&mut self, spec: FunctionSpec) -> Result<u32, JitError> {
        if let Some(handle) = self.spec_cache.get(&spec).copied() {
            self.compile_hits = self.compile_hits.saturating_add(1);
            return Ok(handle);
        }

        let handle = self.next_handle;
        self.next_handle = self
            .next_handle
            .checked_add(1)
            .ok_or_else(|| JitError("jit handle overflow".to_string()))?;
        let compiled = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            compile_function(&mut self.module, handle, &spec)
        })) {
            Ok(Ok(compiled)) => compiled,
            Ok(Err(err)) => return Err(err),
            Err(panic) => {
                let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                    (*s).to_string()
                } else if let Some(s) = panic.downcast_ref::<String>() {
                    s.clone()
                } else {
                    "unknown Rust panic".to_string()
                };
                return Err(JitError(format!("panic compiling {}: {}", spec.name, msg)));
            }
        };
        self.functions.insert(handle, compiled);
        self.spec_cache.insert(spec, handle);
        self.compile_misses = self.compile_misses.saturating_add(1);
        Ok(handle)
    }

    pub fn param_types(&self, handle: u32) -> Option<&[ScalarType]> {
        self.functions.get(&handle).map(|f| f.params.as_slice())
    }

    pub fn result_type(&self, handle: u32) -> Option<ScalarType> {
        self.functions.get(&handle).map(|f| f.result)
    }

    pub fn call_packed(&self, handle: u32, args: &[u64]) -> Result<u64, JitError> {
        let f = self
            .functions
            .get(&handle)
            .ok_or_else(|| JitError(format!("unknown moonlift JIT handle {}", handle)))?;
        match f.code {
            CodePtr::Arity0(fp) => {
                if !args.is_empty() {
                    Err(JitError(format!("function '{}' expects 0 arguments, got {}", f.name, args.len())))
                } else {
                    Ok(unsafe { fp() })
                }
            }
            CodePtr::Arity1(fp) => {
                if args.len() != 1 {
                    Err(JitError(format!("function '{}' expects 1 argument, got {}", f.name, args.len())))
                } else {
                    Ok(unsafe { fp(args[0]) })
                }
            }
            CodePtr::Arity2(fp) => {
                if args.len() != 2 {
                    Err(JitError(format!("function '{}' expects 2 arguments, got {}", f.name, args.len())))
                } else {
                    Ok(unsafe { fp(args[0], args[1]) })
                }
            }
            CodePtr::Arity3(fp) => {
                if args.len() != 3 {
                    Err(JitError(format!("function '{}' expects 3 arguments, got {}", f.name, args.len())))
                } else {
                    Ok(unsafe { fp(args[0], args[1], args[2]) })
                }
            }
            CodePtr::Arity4(fp) => {
                if args.len() != 4 {
                    Err(JitError(format!("function '{}' expects 4 arguments, got {}", f.name, args.len())))
                } else {
                    Ok(unsafe { fp(args[0], args[1], args[2], args[3]) })
                }
            }
        }
    }

    pub fn call1_packed(&self, handle: u32, a: u64) -> Result<u64, JitError> {
        self.call_packed(handle, &[a])
    }

    pub fn call2_packed(&self, handle: u32, a: u64, b: u64) -> Result<u64, JitError> {
        self.call_packed(handle, &[a, b])
    }

    pub fn code_addr(&self, handle: u32) -> Option<u64> {
        let f = self.functions.get(&handle)?;
        let addr = match f.code {
            CodePtr::Arity0(fp) => fp as usize as u64,
            CodePtr::Arity1(fp) => fp as usize as u64,
            CodePtr::Arity2(fp) => fp as usize as u64,
            CodePtr::Arity3(fp) => fp as usize as u64,
            CodePtr::Arity4(fp) => fp as usize as u64,
        };
        Some(addr)
    }

    pub fn stats(&self) -> CompileStats {
        CompileStats {
            compile_hits: self.compile_hits,
            compile_misses: self.compile_misses,
            cache_entries: self.spec_cache.len(),
            compiled_functions: self.functions.len(),
        }
    }
}

fn compile_add_i32_i32(module: &mut JITModule) -> Result<unsafe extern "C" fn(i32, i32) -> i32, JitError> {
    let mut ctx = module.make_context();
    let mut func_ctx = FunctionBuilderContext::new();

    let mut sig = module.make_signature();
    sig.params.push(ir::AbiParam::new(types::I32));
    sig.params.push(ir::AbiParam::new(types::I32));
    sig.returns.push(ir::AbiParam::new(types::I32));

    let func_id = module
        .declare_function("moonlift_add_i32_i32", Linkage::Export, &sig)
        .map_err(|e| JitError(format!("failed to declare JIT function moonlift_add_i32_i32: {e}")))?;

    ctx.func.signature = sig;
    ctx.func.name = UserFuncName::user(0, func_id.as_u32());

    {
        let mut b = FunctionBuilder::new(&mut ctx.func, &mut func_ctx);
        let block = b.create_block();
        b.switch_to_block(block);
        b.append_block_params_for_function_params(block);
        let a = b.block_params(block)[0];
        let c = b.block_params(block)[1];
        let sum = b.ins().iadd(a, c);
        b.ins().return_(&[sum]);
        b.seal_all_blocks();
        b.finalize();
    }

    module
        .define_function(func_id, &mut ctx)
        .map_err(|e| JitError(format!("failed to define JIT function moonlift_add_i32_i32: {e}")))?;
    module.clear_context(&mut ctx);
    module
        .finalize_definitions()
        .map_err(|e| JitError(format!("failed to finalize JIT definitions: {e}")))?;

    let code = module.get_finalized_function(func_id);
    let fp = unsafe { mem::transmute::<_, unsafe extern "C" fn(i32, i32) -> i32>(code) };
    Ok(fp)
}

fn compile_function(
    module: &mut JITModule,
    handle: u32,
    spec: &FunctionSpec,
) -> Result<CompiledFn, JitError> {
    let code = compile_function_raw(module, handle, spec)?;
    let code = match spec.params.len() {
        0 => CodePtr::Arity0(unsafe { mem::transmute::<_, unsafe extern "C" fn() -> u64>(code) }),
        1 => CodePtr::Arity1(unsafe { mem::transmute::<_, unsafe extern "C" fn(u64) -> u64>(code) }),
        2 => CodePtr::Arity2(unsafe { mem::transmute::<_, unsafe extern "C" fn(u64, u64) -> u64>(code) }),
        3 => CodePtr::Arity3(unsafe {
            mem::transmute::<_, unsafe extern "C" fn(u64, u64, u64) -> u64>(code)
        }),
        4 => CodePtr::Arity4(unsafe {
            mem::transmute::<_, unsafe extern "C" fn(u64, u64, u64, u64) -> u64>(code)
        }),
        n => {
            return Err(JitError(format!(
                "Moonlift currently supports only functions with arity 0..4, got {}",
                n
            )))
        }
    };
    Ok(CompiledFn {
        name: spec.name.clone(),
        params: spec.params.clone(),
        result: spec.result,
        code,
    })
}

fn compile_function_raw(
    module: &mut JITModule,
    handle: u32,
    spec: &FunctionSpec,
) -> Result<*const u8, JitError> {
    let mut ctx = module.make_context();
    let mut func_ctx = FunctionBuilderContext::new();

    let mut sig = module.make_signature();
    for _ in 0..spec.params.len() {
        sig.params.push(ir::AbiParam::new(types::I64));
    }
    sig.returns.push(ir::AbiParam::new(types::I64));

    let name = format!("moonlift_fn_{}_{}", handle, sanitize_symbol(&spec.name));
    let func_id = module
        .declare_function(&name, Linkage::Export, &sig)
        .map_err(|e| JitError(format!("failed to declare JIT function {name}: {e}")))?;

    ctx.func.signature = sig;
    ctx.func.name = UserFuncName::user(0, func_id.as_u32());

    {
        let mut b = FunctionBuilder::new(&mut ctx.func, &mut func_ctx);
        let entry = b.create_block();
        b.switch_to_block(entry);
        b.append_block_params_for_function_params(entry);
        let packed = b.block_params(entry).to_vec();
        let mut args = Vec::with_capacity(spec.params.len());
        for i in 0..spec.params.len() {
            args.push(unpack_scalar(&mut b, packed[i], spec.params[i])?);
        }
        let mut lower = LowerCtx {
            args,
            bindings: HashMap::new(),
        };
        let mut next_var_index = 0u32;
        let mut loop_stack = Vec::new();
        bind_legacy_locals(module, &mut b, &spec.locals, &mut lower, &mut next_var_index, &mut loop_stack)?;
        let out = lower_expr(module, &mut b, &spec.body, &mut lower, &mut next_var_index, &mut loop_stack)?;
        let packed_out = if spec.result.is_void() {
            let _ = out;
            b.ins().iconst(types::I64, 0)
        } else {
            pack_scalar(&mut b, out, spec.result)?
        };
        b.ins().return_(&[packed_out]);
        b.seal_all_blocks();
        b.finalize();
    }

    module
        .define_function(func_id, &mut ctx)
        .map_err(|e| JitError(format!("failed to define JIT function {name}: {e:?}")))?;
    module.clear_context(&mut ctx);
    module
        .finalize_definitions()
        .map_err(|e| JitError(format!("failed to finalize JIT definitions for {name}: {e}")))?;

    Ok(module.get_finalized_function(func_id))
}

fn make_packed_signature(module: &mut JITModule, params: &[ScalarType]) -> ir::Signature {
    let mut sig = module.make_signature();
    for _ in 0..params.len() {
        sig.params.push(ir::AbiParam::new(types::I64));
    }
    sig.returns.push(ir::AbiParam::new(types::I64));
    sig
}

fn lower_call_value(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    target: &CallTarget,
    args: &[Expr],
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<(ir::Block, ir::Block)>,
) -> Result<Value, JitError> {
    let (params, result_ty, inst) = match target {
        CallTarget::Direct { name, params, result } => {
            let sig = make_packed_signature(module, params);
            let func_id = module
                .declare_function(name, Linkage::Import, &sig)
                .map_err(|e| JitError(format!("failed to declare callee {name}: {e}")))?;
            let func_ref = module.declare_func_in_func(func_id, b.func);
            let mut packed_args = Vec::with_capacity(args.len());
            for i in 0..args.len() {
                let v = lower_expr(module, b, &args[i], lower, next_var_index, loop_stack)?;
                packed_args.push(pack_scalar(b, v, params[i])?);
            }
            let inst = b.ins().call(func_ref, &packed_args);
            (params.as_slice(), *result, inst)
        }
        CallTarget::Indirect { addr, params, result } => {
            let sig = make_packed_signature(module, params);
            let sig_ref = b.import_signature(sig);
            let addr_val = lower_expr(module, b, addr, lower, next_var_index, loop_stack)?;
            let mut packed_args = Vec::with_capacity(args.len());
            for i in 0..args.len() {
                let v = lower_expr(module, b, &args[i], lower, next_var_index, loop_stack)?;
                packed_args.push(pack_scalar(b, v, params[i])?);
            }
            let inst = b.ins().call_indirect(sig_ref, addr_val, &packed_args);
            (params.as_slice(), *result, inst)
        }
    };
    let _ = params;
    let packed = b.inst_results(inst)[0];
    if result_ty.is_void() {
        Ok(b.ins().iconst(types::I8, 0))
    } else {
        unpack_scalar(b, packed, result_ty)
    }
}

fn lower_call_stmt(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    target: &CallTarget,
    args: &[Expr],
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<(ir::Block, ir::Block)>,
) -> Result<(), JitError> {
    let _ = lower_call_value(module, b, target, args, lower, next_var_index, loop_stack)?;
    Ok(())
}

fn bind_legacy_locals(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    locals: &[LocalDecl],
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<(ir::Block, ir::Block)>,
) -> Result<(), JitError> {
    for local in locals {
        if lower.bindings.contains_key(&local.name) {
            return Err(JitError(format!(
                "duplicate Moonlift local '{}' in lowered function",
                local.name
            )));
        }
        let init = lower_expr(module, b, &local.init, lower, next_var_index, loop_stack)?;
        lower.bindings.insert(local.name.clone(), Binding::Value(init));
    }
    Ok(())
}

fn declare_var(
    b: &mut FunctionBuilder<'_>,
    next_var_index: &mut u32,
    ty: ScalarType,
) -> Variable {
    let var = b.declare_var(ty.abi_type());
    *next_var_index = next_var_index.saturating_add(1);
    var
}

fn pack_scalar(b: &mut FunctionBuilder<'_>, value: Value, ty: ScalarType) -> Result<Value, JitError> {
    match ty {
        ScalarType::Void => Err(JitError("cannot pack void as a scalar value".to_string())),
        ScalarType::Bool
        | ScalarType::I8
        | ScalarType::I16
        | ScalarType::I32
        | ScalarType::U8
        | ScalarType::U16
        | ScalarType::U32 => Ok(b.ins().uextend(types::I64, value)),
        ScalarType::I64 | ScalarType::U64 | ScalarType::Ptr => Ok(value),
        ScalarType::F32 => {
            let bits = b.ins().bitcast(types::I32, MemFlags::new(), value);
            Ok(b.ins().uextend(types::I64, bits))
        }
        ScalarType::F64 => Ok(b.ins().bitcast(types::I64, MemFlags::new(), value)),
    }
}

fn unpack_scalar(
    b: &mut FunctionBuilder<'_>,
    packed: Value,
    ty: ScalarType,
) -> Result<Value, JitError> {
    match ty {
        ScalarType::Void => Err(JitError("cannot unpack void as a scalar value".to_string())),
        ScalarType::Bool => Ok(b.ins().ireduce(types::I8, packed)),
        ScalarType::I8 | ScalarType::U8 => Ok(b.ins().ireduce(types::I8, packed)),
        ScalarType::I16 | ScalarType::U16 => Ok(b.ins().ireduce(types::I16, packed)),
        ScalarType::I32 | ScalarType::U32 => Ok(b.ins().ireduce(types::I32, packed)),
        ScalarType::I64 | ScalarType::U64 | ScalarType::Ptr => Ok(packed),
        ScalarType::F32 => {
            let bits = b.ins().ireduce(types::I32, packed);
            Ok(b.ins().bitcast(types::F32, MemFlags::new(), bits))
        }
        ScalarType::F64 => Ok(b.ins().bitcast(types::F64, MemFlags::new(), packed)),
    }
}

fn lower_binding_read(b: &mut FunctionBuilder<'_>, binding: Binding) -> Value {
    match binding {
        Binding::Value(v) => v,
        Binding::Var(v) => b.use_var(v),
    }
}

fn lower_condition(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    expr: &Expr,
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<(ir::Block, ir::Block)>,
) -> Result<Value, JitError> {
    if expr.ty() != ScalarType::Bool {
        return Err(JitError("Moonlift condition must have type bool".to_string()));
    }
    let v = lower_expr(module, b, expr, lower, next_var_index, loop_stack)?;
    Ok(b.ins().icmp_imm(IntCC::NotEqual, v, 0))
}

fn lower_stmts(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    stmts: &[Stmt],
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<(ir::Block, ir::Block)>,
) -> Result<bool, JitError> {
    for stmt in stmts {
        if lower_stmt(module, b, stmt, lower, next_var_index, loop_stack)? {
            return Ok(true);
        }
    }
    Ok(false)
}

fn lower_stmt(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    stmt: &Stmt,
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<(ir::Block, ir::Block)>,
) -> Result<bool, JitError> {
    match stmt {
        Stmt::Let { name, init, .. } => {
            let init_val = lower_expr(module, b, init, lower, next_var_index, loop_stack)?;
            lower.bindings.insert(name.clone(), Binding::Value(init_val));
            Ok(false)
        }
        Stmt::Var { name, ty, init } => {
            let init_val = lower_expr(module, b, init, lower, next_var_index, loop_stack)?;
            let var = declare_var(b, next_var_index, *ty);
            b.def_var(var, init_val);
            lower.bindings.insert(name.clone(), Binding::Var(var));
            Ok(false)
        }
        Stmt::Set { name, value } => {
            let binding = lower
                .bindings
                .get(name)
                .copied()
                .ok_or_else(|| JitError(format!("unknown Moonlift variable '{}'", name)))?;
            let var = match binding {
                Binding::Var(v) => v,
                Binding::Value(_) => {
                    return Err(JitError(format!(
                        "Moonlift binding '{}' is immutable and cannot be assigned",
                        name
                    )))
                }
            };
            let val = lower_expr(module, b, value, lower, next_var_index, loop_stack)?;
            b.def_var(var, val);
            Ok(false)
        }
        Stmt::While { cond, body } => {
            let head = b.create_block();
            let loop_body = b.create_block();
            let exit = b.create_block();

            b.ins().jump(head, &[]);
            b.switch_to_block(head);
            let cond_val = lower_condition(module, b, cond, lower, next_var_index, loop_stack)?;
            b.ins().brif(cond_val, loop_body, &[], exit, &[]);
            b.seal_block(loop_body);

            b.switch_to_block(loop_body);
            let mut body_ctx = lower.clone();
            loop_stack.push((head, exit));
            let terminated = lower_stmts(module, b, body, &mut body_ctx, next_var_index, loop_stack)?;
            loop_stack.pop();
            if !terminated {
                b.ins().jump(head, &[]);
            }

            b.seal_block(head);
            b.seal_block(exit);
            b.switch_to_block(exit);
            Ok(false)
        }
        Stmt::Store { ty: _, addr, value } => {
            let addr_val = lower_expr(module, b, addr, lower, next_var_index, loop_stack)?;
            let val = lower_expr(module, b, value, lower, next_var_index, loop_stack)?;
            b.ins().store(MemFlags::trusted(), val, addr_val, 0i32);
            Ok(false)
        }
        Stmt::Call { target, args } => {
            lower_call_stmt(module, b, target, args, lower, next_var_index, loop_stack)?;
            Ok(false)
        }
        Stmt::Break => {
            let (_, exit) = loop_stack.last().copied().ok_or_else(|| JitError("break used outside of a loop".to_string()))?;
            b.ins().jump(exit, &[]);
            Ok(true)
        }
        Stmt::Continue => {
            let (head, _) = loop_stack.last().copied().ok_or_else(|| JitError("continue used outside of a loop".to_string()))?;
            b.ins().jump(head, &[]);
            Ok(true)
        }
    }
}

fn lower_expr(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    expr: &Expr,
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<(ir::Block, ir::Block)>,
) -> Result<Value, JitError> {
    match expr {
        Expr::Arg { index, .. } => {
            let idx0 = index
                .checked_sub(1)
                .ok_or_else(|| JitError("argument indices are 1-based".to_string()))?
                as usize;
            lower
                .args
                .get(idx0)
                .copied()
                .ok_or_else(|| JitError(format!("argument {} is out of range", index)))
        }
        Expr::Local { name, .. } => {
            let binding = lower
                .bindings
                .get(name)
                .copied()
                .ok_or_else(|| JitError(format!("unknown Moonlift local '{}'", name)))?;
            Ok(lower_binding_read(b, binding))
        }
        Expr::Const { ty, bits } => lower_const(b, *ty, *bits),
        Expr::Unary { op, ty, value } => {
            let v = lower_expr(module, b, value, lower, next_var_index, loop_stack)?;
            lower_unary(b, *op, *ty, v)
        }
        Expr::Binary { op, ty, lhs, rhs } => {
            let l = lower_expr(module, b, lhs, lower, next_var_index, loop_stack)?;
            let r = lower_expr(module, b, rhs, lower, next_var_index, loop_stack)?;
            lower_binary(b, *op, *ty, lhs.ty(), rhs.ty(), l, r)
        }
        Expr::Let {
            name,
            ty: _,
            init,
            body,
        } => {
            let init_val = lower_expr(module, b, init, lower, next_var_index, loop_stack)?;
            let mut child = lower.clone();
            child.bindings.insert(name.clone(), Binding::Value(init_val));
            lower_expr(module, b, body, &mut child, next_var_index, loop_stack)
        }
        Expr::Block { stmts, result, .. } => {
            let mut child = lower.clone();
            let _ = lower_stmts(module, b, stmts, &mut child, next_var_index, loop_stack)?;
            lower_expr(module, b, result, &mut child, next_var_index, loop_stack)
        }
        Expr::If {
            cond,
            then_expr,
            else_expr,
            ty,
        } => {
            let cond_val = lower_condition(module, b, cond, lower, next_var_index, loop_stack)?;
            let then_block = b.create_block();
            let else_block = b.create_block();
            let merge_block = b.create_block();
            b.append_block_param(merge_block, ty.abi_type());

            b.ins().brif(cond_val, then_block, &[], else_block, &[]);
            b.seal_block(then_block);
            b.seal_block(else_block);

            b.switch_to_block(then_block);
            let mut then_ctx = lower.clone();
            let then_val = lower_expr(module, b, then_expr, &mut then_ctx, next_var_index, loop_stack)?;
            b.ins().jump(merge_block, &[then_val.into()]);

            b.switch_to_block(else_block);
            let mut else_ctx = lower.clone();
            let else_val = lower_expr(module, b, else_expr, &mut else_ctx, next_var_index, loop_stack)?;
            b.ins().jump(merge_block, &[else_val.into()]);

            b.seal_block(merge_block);
            b.switch_to_block(merge_block);
            Ok(b.block_params(merge_block)[0])
        }
        Expr::Load { ty, addr } => {
            let addr_val = lower_expr(module, b, addr, lower, next_var_index, loop_stack)?;
            Ok(b.ins().load(ty.abi_type(), MemFlags::trusted(), addr_val, 0i32))
        }
        Expr::Cast { op, ty, value } => {
            let v = lower_expr(module, b, value, lower, next_var_index, loop_stack)?;
            lower_cast(b, *op, value.ty(), *ty, v)
        }
        Expr::Call { target, args, .. } => lower_call_value(module, b, target, args, lower, next_var_index, loop_stack),
    }
}

fn lower_const(b: &mut FunctionBuilder<'_>, ty: ScalarType, bits: u64) -> Result<Value, JitError> {
    Ok(match ty {
        ScalarType::Void => return Err(JitError("cannot materialize a void constant".to_string())),
        ScalarType::Bool => b.ins().iconst(types::I8, if bits & 1 == 0 { 0 } else { 1 }),
        ScalarType::I8 | ScalarType::U8 => b.ins().iconst(types::I8, bits as i8 as i64),
        ScalarType::I16 | ScalarType::U16 => b.ins().iconst(types::I16, bits as i16 as i64),
        ScalarType::I32 | ScalarType::U32 => b.ins().iconst(types::I32, bits as i32 as i64),
        ScalarType::I64 | ScalarType::U64 | ScalarType::Ptr => b.ins().iconst(types::I64, bits as i64),
        ScalarType::F32 => {
            let i = b.ins().iconst(types::I32, (bits as u32) as i32 as i64);
            b.ins().bitcast(types::F32, MemFlags::new(), i)
        }
        ScalarType::F64 => {
            let i = b.ins().iconst(types::I64, bits as i64);
            b.ins().bitcast(types::F64, MemFlags::new(), i)
        }
    })
}

fn coerce_value(
    b: &mut FunctionBuilder<'_>,
    value: Value,
    src_ty: ScalarType,
    dst_ty: ScalarType,
) -> Result<Value, JitError> {
    if src_ty == dst_ty {
        return Ok(value);
    }

    if src_ty.is_float() || dst_ty.is_float() {
        return match (src_ty, dst_ty) {
            (ScalarType::F32, ScalarType::F64) => Ok(b.ins().fpromote(types::F64, value)),
            (ScalarType::F64, ScalarType::F32) => Ok(b.ins().fdemote(types::F32, value)),
            _ => Err(JitError(format!(
                "cannot coerce Moonlift value from {} to {}",
                src_ty.name(),
                dst_ty.name()
            ))),
        };
    }

    let src_ir = src_ty.abi_type();
    let dst_ir = dst_ty.abi_type();
    if src_ir == dst_ir {
        return Ok(value);
    }

    let src_bits = src_ir.bits();
    let dst_bits = dst_ir.bits();
    if src_bits < dst_bits {
        if src_ty.is_signed_integer() {
            Ok(b.ins().sextend(dst_ir, value))
        } else {
            Ok(b.ins().uextend(dst_ir, value))
        }
    } else if src_bits > dst_bits {
        Ok(b.ins().ireduce(dst_ir, value))
    } else {
        Ok(value)
    }
}

fn lower_unary(
    b: &mut FunctionBuilder<'_>,
    op: UnaryOp,
    ty: ScalarType,
    value: Value,
) -> Result<Value, JitError> {
    match op {
        UnaryOp::Neg => {
            if ty.is_float() {
                Ok(b.ins().fneg(value))
            } else if ty.is_integer() {
                Ok(b.ins().ineg(value))
            } else {
                Err(JitError(format!("unary negation is not valid for {}", ty.name())))
            }
        }
        UnaryOp::Not => {
            if ty.is_bool() {
                Ok(b.ins().bnot(value))
            } else {
                Err(JitError(format!("logical not is not valid for {}", ty.name())))
            }
        }
        UnaryOp::Bnot => {
            if ty.is_integer() {
                Ok(b.ins().bnot(value))
            } else {
                Err(JitError(format!("bitwise not is not valid for {}", ty.name())))
            }
        }
    }
}

fn lower_cast(
    b: &mut FunctionBuilder<'_>,
    op: CastOp,
    src_ty: ScalarType,
    dst_ty: ScalarType,
    value: Value,
) -> Result<Value, JitError> {
    match op {
        CastOp::Cast => {
            if src_ty == dst_ty {
                return Ok(value);
            }
            if src_ty.is_float() && dst_ty.is_float() {
                return match (src_ty, dst_ty) {
                    (ScalarType::F32, ScalarType::F64) => Ok(b.ins().fpromote(types::F64, value)),
                    (ScalarType::F64, ScalarType::F32) => Ok(b.ins().fdemote(types::F32, value)),
                    _ => Err(JitError(format!("cannot cast {} to {}", src_ty.name(), dst_ty.name()))),
                };
            }
            if !src_ty.is_float() && dst_ty.is_float() {
                return if src_ty.is_signed_integer() {
                    Ok(b.ins().fcvt_from_sint(dst_ty.abi_type(), value))
                } else {
                    Ok(b.ins().fcvt_from_uint(dst_ty.abi_type(), value))
                };
            }
            if src_ty.is_float() && !dst_ty.is_float() {
                return if dst_ty.is_signed_integer() {
                    Ok(b.ins().fcvt_to_sint(dst_ty.abi_type(), value))
                } else {
                    Ok(b.ins().fcvt_to_uint(dst_ty.abi_type(), value))
                };
            }
            coerce_value(b, value, src_ty, dst_ty)
        }
        CastOp::Trunc => {
            if src_ty.is_float() || dst_ty.is_float() {
                return Err(JitError("trunc expects integer/pointer types".to_string()));
            }
            let src_bits = src_ty.abi_type().bits();
            let dst_bits = dst_ty.abi_type().bits();
            if dst_bits > src_bits {
                return Err(JitError(format!("cannot trunc {} to {}", src_ty.name(), dst_ty.name())));
            }
            Ok(b.ins().ireduce(dst_ty.abi_type(), value))
        }
        CastOp::Zext => {
            if src_ty.is_float() || dst_ty.is_float() {
                return Err(JitError("zext expects integer/pointer types".to_string()));
            }
            let src_bits = src_ty.abi_type().bits();
            let dst_bits = dst_ty.abi_type().bits();
            if dst_bits < src_bits {
                return Err(JitError(format!("cannot zext {} to {}", src_ty.name(), dst_ty.name())));
            }
            if dst_bits == src_bits {
                return Ok(value);
            }
            Ok(b.ins().uextend(dst_ty.abi_type(), value))
        }
        CastOp::Sext => {
            if src_ty.is_float() || dst_ty.is_float() {
                return Err(JitError("sext expects integer/pointer types".to_string()));
            }
            let src_bits = src_ty.abi_type().bits();
            let dst_bits = dst_ty.abi_type().bits();
            if dst_bits < src_bits {
                return Err(JitError(format!("cannot sext {} to {}", src_ty.name(), dst_ty.name())));
            }
            if dst_bits == src_bits {
                return Ok(value);
            }
            Ok(b.ins().sextend(dst_ty.abi_type(), value))
        }
        CastOp::Bitcast => {
            let src_bits = src_ty.abi_type().bits();
            let dst_bits = dst_ty.abi_type().bits();
            if src_bits != dst_bits {
                return Err(JitError(format!("cannot bitcast {} to {}", src_ty.name(), dst_ty.name())));
            }
            if src_ty.is_float() && !dst_ty.is_float() {
                Ok(b.ins().bitcast(dst_ty.abi_type(), MemFlags::new(), value))
            } else if !src_ty.is_float() && dst_ty.is_float() {
                Ok(b.ins().bitcast(dst_ty.abi_type(), MemFlags::new(), value))
            } else {
                Ok(value)
            }
        }
    }
}

fn lower_binary(
    b: &mut FunctionBuilder<'_>,
    op: BinaryOp,
    ty: ScalarType,
    lhs_ty: ScalarType,
    rhs_ty: ScalarType,
    lhs: Value,
    rhs: Value,
) -> Result<Value, JitError> {
    match op {
        BinaryOp::Add => {
            let lhs = coerce_value(b, lhs, lhs_ty, ty)?;
            let rhs = coerce_value(b, rhs, rhs_ty, ty)?;
            if ty.is_float() {
                Ok(b.ins().fadd(lhs, rhs))
            } else {
                Ok(b.ins().iadd(lhs, rhs))
            }
        }
        BinaryOp::Sub => {
            let lhs = coerce_value(b, lhs, lhs_ty, ty)?;
            let rhs = coerce_value(b, rhs, rhs_ty, ty)?;
            if ty.is_float() {
                Ok(b.ins().fsub(lhs, rhs))
            } else {
                Ok(b.ins().isub(lhs, rhs))
            }
        }
        BinaryOp::Mul => {
            let lhs = coerce_value(b, lhs, lhs_ty, ty)?;
            let rhs = coerce_value(b, rhs, rhs_ty, ty)?;
            if ty.is_float() {
                Ok(b.ins().fmul(lhs, rhs))
            } else {
                Ok(b.ins().imul(lhs, rhs))
            }
        }
        BinaryOp::Div => {
            let lhs = coerce_value(b, lhs, lhs_ty, ty)?;
            let rhs = coerce_value(b, rhs, rhs_ty, ty)?;
            if ty.is_float() {
                Ok(b.ins().fdiv(lhs, rhs))
            } else if lhs_ty.is_signed_integer() {
                Ok(b.ins().sdiv(lhs, rhs))
            } else {
                Ok(b.ins().udiv(lhs, rhs))
            }
        }
        BinaryOp::Rem => {
            let lhs = coerce_value(b, lhs, lhs_ty, ty)?;
            let rhs = coerce_value(b, rhs, rhs_ty, ty)?;
            if ty.is_float() {
                Err(JitError("floating-point remainder is not supported yet".to_string()))
            } else if lhs_ty.is_signed_integer() {
                Ok(b.ins().srem(lhs, rhs))
            } else {
                Ok(b.ins().urem(lhs, rhs))
            }
        }
        BinaryOp::Eq => lower_compare_int_or_float(b, ty, lhs_ty, rhs, lhs, CompareOp::Eq),
        BinaryOp::Ne => lower_compare_int_or_float(b, ty, lhs_ty, rhs, lhs, CompareOp::Ne),
        BinaryOp::Lt => lower_compare_int_or_float(b, ty, lhs_ty, rhs, lhs, CompareOp::Lt),
        BinaryOp::Le => lower_compare_int_or_float(b, ty, lhs_ty, rhs, lhs, CompareOp::Le),
        BinaryOp::Gt => lower_compare_int_or_float(b, ty, lhs_ty, rhs, lhs, CompareOp::Gt),
        BinaryOp::Ge => lower_compare_int_or_float(b, ty, lhs_ty, rhs, lhs, CompareOp::Ge),
        BinaryOp::And => {
            if ty.is_bool() {
                Ok(b.ins().band(lhs, rhs))
            } else {
                Err(JitError("logical and is only valid for bool".to_string()))
            }
        }
        BinaryOp::Or => {
            if ty.is_bool() {
                Ok(b.ins().bor(lhs, rhs))
            } else {
                Err(JitError("logical or is only valid for bool".to_string()))
            }
        }
        BinaryOp::Band => {
            let lhs = coerce_value(b, lhs, lhs_ty, ty)?;
            let rhs = coerce_value(b, rhs, rhs_ty, ty)?;
            Ok(b.ins().band(lhs, rhs))
        }
        BinaryOp::Bor => {
            let lhs = coerce_value(b, lhs, lhs_ty, ty)?;
            let rhs = coerce_value(b, rhs, rhs_ty, ty)?;
            Ok(b.ins().bor(lhs, rhs))
        }
        BinaryOp::Bxor => {
            let lhs = coerce_value(b, lhs, lhs_ty, ty)?;
            let rhs = coerce_value(b, rhs, rhs_ty, ty)?;
            Ok(b.ins().bxor(lhs, rhs))
        }
        BinaryOp::Shl => {
            let lhs = coerce_value(b, lhs, lhs_ty, ty)?;
            let rhs = coerce_value(b, rhs, rhs_ty, ty)?;
            Ok(b.ins().ishl(lhs, rhs))
        }
        BinaryOp::ShrU => {
            let lhs = coerce_value(b, lhs, lhs_ty, ty)?;
            let rhs = coerce_value(b, rhs, rhs_ty, ty)?;
            Ok(b.ins().ushr(lhs, rhs))
        }
        BinaryOp::ShrS => {
            let lhs = coerce_value(b, lhs, lhs_ty, ty)?;
            let rhs = coerce_value(b, rhs, rhs_ty, ty)?;
            Ok(b.ins().sshr(lhs, rhs))
        }
    }
}

enum CompareOp {
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
}

fn lower_compare_int_or_float(
    b: &mut FunctionBuilder<'_>,
    result_ty: ScalarType,
    operand_ty: ScalarType,
    rhs: Value,
    lhs: Value,
    op: CompareOp,
) -> Result<Value, JitError> {
    if result_ty != ScalarType::Bool {
        return Err(JitError("comparison result must have type bool".to_string()));
    }

    let cmp = if operand_ty.is_float() {
        b.ins().fcmp(
            match op {
                CompareOp::Eq => FloatCC::Equal,
                CompareOp::Ne => FloatCC::NotEqual,
                CompareOp::Lt => FloatCC::LessThan,
                CompareOp::Le => FloatCC::LessThanOrEqual,
                CompareOp::Gt => FloatCC::GreaterThan,
                CompareOp::Ge => FloatCC::GreaterThanOrEqual,
            },
            lhs,
            rhs,
        )
    } else {
        let cc = match op {
            CompareOp::Eq => IntCC::Equal,
            CompareOp::Ne => IntCC::NotEqual,
            CompareOp::Lt => {
                if operand_ty.is_signed_integer() {
                    IntCC::SignedLessThan
                } else {
                    IntCC::UnsignedLessThan
                }
            }
            CompareOp::Le => {
                if operand_ty.is_signed_integer() {
                    IntCC::SignedLessThanOrEqual
                } else {
                    IntCC::UnsignedLessThanOrEqual
                }
            }
            CompareOp::Gt => {
                if operand_ty.is_signed_integer() {
                    IntCC::SignedGreaterThan
                } else {
                    IntCC::UnsignedGreaterThan
                }
            }
            CompareOp::Ge => {
                if operand_ty.is_signed_integer() {
                    IntCC::SignedGreaterThanOrEqual
                } else {
                    IntCC::UnsignedGreaterThanOrEqual
                }
            }
        };
        b.ins().icmp(cc, lhs, rhs)
    };
    Ok(cmp)
}

fn sanitize_symbol(name: &str) -> String {
    let mut out = String::with_capacity(name.len());
    for ch in name.chars() {
        if ch.is_ascii_alphanumeric() || ch == '_' {
            out.push(ch);
        } else {
            out.push('_');
        }
    }
    if out.is_empty() {
        out.push_str("fn");
    }
    out
}
