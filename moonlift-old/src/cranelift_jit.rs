use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::{InstBuilder, MemFlags, StackSlot, StackSlotData, StackSlotKind, UserFuncName, Value, types};
use cranelift_codegen::settings::Configurable;
use cranelift_codegen::{ir, settings};
use cranelift_control::ControlPlane;
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Variable};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{default_libcall_names, FuncId, Linkage, Module};
use std::cell::RefCell;
use std::collections::HashMap;
use std::error::Error;
use std::ffi::c_void;
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
            "u64" | "usize" | "index" => Some(Self::U64),
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
        packed: bool,
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
    IndexAddr {
        base: Box<Expr>,
        index: Box<Expr>,
        elem_size: u32,
        limit: Option<Box<Expr>>,
    },
    StackAddr {
        name: String,
    },
    Memcmp {
        a: Box<Expr>,
        b: Box<Expr>,
        len: Box<Expr>,
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
    Select {
        cond: Box<Expr>,
        then_expr: Box<Expr>,
        else_expr: Box<Expr>,
        ty: ScalarType,
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
            | Expr::Call { ty, .. }
            | Expr::Select { ty, .. } => *ty,
            Expr::IndexAddr { .. } | Expr::StackAddr { .. } => ScalarType::Ptr,
            Expr::Memcmp { .. } => ScalarType::I32,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct LoopVar {
    pub name: String,
    pub ty: ScalarType,
    pub init: Expr,
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
    LoopWhile {
        vars: Vec<LoopVar>,
        cond: Expr,
        body: Vec<Stmt>,
        next: Vec<Expr>,
    },
    ForRange {
        name: String,
        ty: ScalarType,
        start: Expr,
        finish: Expr,
        step: Expr,
        dir: Option<StepDirection>,
        inclusive: bool,
        scoped: bool,
        body: Vec<Stmt>,
    },
    If {
        cond: Expr,
        then_body: Vec<Stmt>,
        else_body: Vec<Stmt>,
    },
    Store {
        ty: ScalarType,
        addr: Expr,
        value: Expr,
    },
    BoundsCheck {
        index: Expr,
        limit: Expr,
    },
    Assert {
        cond: Expr,
    },
    StackSlot {
        name: String,
        size: u32,
        align: u32,
    },
    Memcpy {
        dst: Expr,
        src: Expr,
        len: Expr,
    },
    Memmove {
        dst: Expr,
        src: Expr,
        len: Expr,
    },
    Memset {
        dst: Expr,
        byte: Expr,
        len: Expr,
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

type CodePtr = unsafe extern "C" fn(*const u64) -> u64;

#[derive(Clone)]
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
    stack_slots: HashMap<String, StackSlot>,
}

#[derive(Clone, Copy)]
struct LoopTargets {
    continue_block: ir::Block,
    exit: ir::Block,
}

#[derive(Clone, Copy, Debug)]
pub struct CompileStats {
    pub compile_hits: u64,
    pub compile_misses: u64,
    pub cache_entries: usize,
    pub compiled_functions: usize,
}

unsafe extern "C" {
    fn memcmp(lhs: *const c_void, rhs: *const c_void, len: usize) -> i32;
}

unsafe extern "C" fn moonlift_rt_memcpy(dst: *mut u8, src: *const u8, len: u64) {
    unsafe {
        std::ptr::copy_nonoverlapping(src, dst, len as usize);
    }
}

unsafe extern "C" fn moonlift_rt_memmove(dst: *mut u8, src: *const u8, len: u64) {
    unsafe {
        std::ptr::copy(src, dst, len as usize);
    }
}

unsafe extern "C" fn moonlift_rt_memset(dst: *mut u8, byte: u8, len: u64) {
    unsafe {
        std::ptr::write_bytes(dst, byte, len as usize);
    }
}

unsafe extern "C" fn moonlift_rt_memcmp(a: *const u8, b: *const u8, len: u64) -> i32 {
    let raw = unsafe { memcmp(a as *const c_void, b as *const c_void, len as usize) };
    if raw < 0 {
        -1
    } else if raw > 0 {
        1
    } else {
        0
    }
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
struct DirectFuncInfo {
    typed_func_id: FuncId,
    params: Vec<ScalarType>,
    result: ScalarType,
}

struct StableFuncRecord {
    handle: u32,
    packed_id: FuncId,
    typed_entry_id: FuncId,
    body_id: FuncId,
    body_cell: Box<u64>,
    body_ready: bool,
}

thread_local! {
    static ACTIVE_DIRECT_FUNCS: RefCell<Option<HashMap<String, DirectFuncInfo>>> = const { RefCell::new(None) };
}

pub struct MoonliftJit {
    module: JITModule,
    add_i32_i32: unsafe extern "C" fn(i32, i32) -> i32,
    next_handle: u32,
    next_debug_id: u32,
    functions: HashMap<u32, CompiledFn>,
    spec_cache: HashMap<FunctionSpec, u32>,
    stable_funcs: HashMap<FunctionSpec, StableFuncRecord>,
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
        flag_builder
            .set("opt_level", "speed")
            .map_err(|e| JitError(format!("failed to set Cranelift flag opt_level: {e}")))?;

        let isa_builder = cranelift_native::builder()
            .map_err(|e| JitError(format!("host machine is not supported by Cranelift: {e}")))?;
        let isa = isa_builder
            .finish(settings::Flags::new(flag_builder))
            .map_err(|e| JitError(format!("failed to finalize Cranelift ISA: {e}")))?;

        let mut builder = JITBuilder::with_isa(isa, default_libcall_names());
        builder.symbol("moonlift_rt_memcpy", moonlift_rt_memcpy as *const u8);
        builder.symbol("moonlift_rt_memmove", moonlift_rt_memmove as *const u8);
        builder.symbol("moonlift_rt_memset", moonlift_rt_memset as *const u8);
        builder.symbol("moonlift_rt_memcmp", moonlift_rt_memcmp as *const u8);
        let mut module = JITModule::new(builder);
        let add_i32_i32 = compile_add_i32_i32(&mut module)?;
        Ok(Self {
            module,
            add_i32_i32,
            next_handle: 1,
            next_debug_id: 1,
            functions: HashMap::new(),
            spec_cache: HashMap::new(),
            stable_funcs: HashMap::new(),
            compile_hits: 0,
            compile_misses: 0,
        })
    }

    pub fn add_i32_i32(&self, a: i32, b: i32) -> i32 {
        unsafe { (self.add_i32_i32)(a, b) }
    }

    pub fn compile_function(&mut self, spec: FunctionSpec) -> Result<u32, JitError> {
        let spec = optimize_function_spec(&spec);
        let handles = self.compile_stable_specs(&[spec])?;
        Ok(handles[0])
    }

    pub fn compile_function_unoptimized(&mut self, spec: FunctionSpec) -> Result<u32, JitError> {
        self.compile_function_without_cache(spec)
    }

    pub fn compile_module(&mut self, specs: Vec<FunctionSpec>) -> Result<Vec<u32>, JitError> {
        if specs.is_empty() {
            return Ok(Vec::new());
        }
        let specs: Vec<FunctionSpec> = specs.iter().map(optimize_function_spec).collect();
        self.compile_stable_specs(&specs)
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
        if args.len() != f.params.len() {
            return Err(JitError(format!(
                "function '{}' expects {} arguments, got {}",
                f.name,
                f.params.len(),
                args.len()
            )));
        }
        let ptr = if args.is_empty() {
            std::ptr::null()
        } else {
            args.as_ptr()
        };
        Ok(unsafe { (f.code)(ptr) })
    }

    pub fn call0_packed(&self, handle: u32) -> Result<u64, JitError> {
        self.call_packed(handle, &[])
    }

    pub fn call1_packed(&self, handle: u32, a: u64) -> Result<u64, JitError> {
        self.call_packed(handle, &[a])
    }

    pub fn call2_packed(&self, handle: u32, a: u64, b: u64) -> Result<u64, JitError> {
        self.call_packed(handle, &[a, b])
    }

    pub fn call3_packed(&self, handle: u32, a: u64, b: u64, c: u64) -> Result<u64, JitError> {
        self.call_packed(handle, &[a, b, c])
    }

    pub fn call4_packed(&self, handle: u32, a: u64, b: u64, c: u64, d: u64) -> Result<u64, JitError> {
        self.call_packed(handle, &[a, b, c, d])
    }

    pub fn code_addr(&self, handle: u32) -> Option<u64> {
        let f = self.functions.get(&handle)?;
        Some(f.code as usize as u64)
    }

    pub fn stats(&self) -> CompileStats {
        CompileStats {
            compile_hits: self.compile_hits,
            compile_misses: self.compile_misses,
            cache_entries: self.spec_cache.len(),
            compiled_functions: self.functions.len(),
        }
    }

    pub fn dump_disasm(&mut self, spec: &FunctionSpec) -> Result<String, JitError> {
        self.dump_disasm_impl(optimize_function_spec(spec))
    }

    pub fn dump_disasm_unoptimized(&mut self, spec: &FunctionSpec) -> Result<String, JitError> {
        self.dump_disasm_impl(spec.clone())
    }

    fn declare_stable_record(&mut self, spec: &FunctionSpec) -> Result<u32, JitError> {
        let handle = self.next_handle;
        self.next_handle = self
            .next_handle
            .checked_add(1)
            .ok_or_else(|| JitError("jit handle overflow".to_string()))?;

        let symbol_name = format!("moonlift_stable_{}_{}", handle, sanitize_symbol(&spec.name));
        let packed_id = declare_packed_function(&mut self.module, &format!("{}_packed", symbol_name))?;
        let typed_sig = make_typed_signature(&mut self.module, spec);
        let typed_entry_id = self
            .module
            .declare_function(&format!("{}_entry", symbol_name), Linkage::Local, &typed_sig)
            .map_err(|e| JitError(format!("failed to declare typed entry trampoline: {e}")))?;
        let body_id = self
            .module
            .declare_function(&format!("{}_body", symbol_name), Linkage::Local, &typed_sig)
            .map_err(|e| JitError(format!("failed to declare typed body function: {e}")))?;

        let mut body_cell = Box::new(0u64);
        let cell_ptr = (&mut *body_cell) as *mut u64 as usize as u64;
        define_typed_entry_trampoline(&mut self.module, typed_entry_id, spec, cell_ptr)?;
        build_packed_wrapper(&mut self.module, packed_id, typed_entry_id, spec)?;

        self.stable_funcs.insert(
            spec.clone(),
            StableFuncRecord {
                handle,
                packed_id,
                typed_entry_id,
                body_id,
                body_cell,
                body_ready: false,
            },
        );
        self.spec_cache.insert(spec.clone(), handle);
        self.compile_misses = self.compile_misses.saturating_add(1);
        Ok(handle)
    }

    fn compile_stable_specs(&mut self, specs: &[FunctionSpec]) -> Result<Vec<u32>, JitError> {
        if specs.is_empty() {
            return Ok(Vec::new());
        }

        let mut seen = HashMap::new();
        for spec in specs {
            if seen.insert(spec.name.clone(), ()).is_some() {
                return Err(JitError(format!("duplicate Moonlift function '{}' in module compile", spec.name)));
            }
        }

        let mut handles = Vec::with_capacity(specs.len());
        for spec in specs {
            if let Some(record) = self.stable_funcs.get(spec) {
                if record.body_ready {
                    self.compile_hits = self.compile_hits.saturating_add(1);
                }
                handles.push(record.handle);
            } else {
                handles.push(self.declare_stable_record(spec)?);
            }
        }

        let mut direct_funcs = HashMap::new();
        let mut pending = Vec::new();
        let mut need_finalize = false;
        for spec in specs {
            let record = self
                .stable_funcs
                .get(spec)
                .ok_or_else(|| JitError(format!("missing stable record for {}", spec.name)))?;
            direct_funcs.insert(
                spec.name.clone(),
                DirectFuncInfo {
                    typed_func_id: record.typed_entry_id,
                    params: spec.params.clone(),
                    result: spec.result,
                },
            );
            if !record.body_ready {
                pending.push((spec.clone(), record.body_id, record.handle, record.packed_id));
                need_finalize = true;
            }
        }

        if !need_finalize {
            return Ok(handles);
        }

        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            ACTIVE_DIRECT_FUNCS.with(|slot| {
                *slot.borrow_mut() = Some(direct_funcs.clone());
            });
            for (spec, body_id, _, _) in &pending {
                let mut ctx = build_function_context_typed(
                    &mut self.module,
                    UserFuncName::user(0, body_id.as_u32()),
                    spec,
                )?;
                self.module
                    .define_function(*body_id, &mut ctx)
                    .map_err(|e| JitError(format!("failed to define typed body function {}: {e:?}", spec.name)))?;
                self.module.clear_context(&mut ctx);
            }
            self.module
                .finalize_definitions()
                .map_err(|e| JitError(format!("failed to finalize JIT stable definitions: {e}")))?;

            let mut wrappers = Vec::new();
            let mut bodies = Vec::new();
            for (spec, body_id, handle, packed_id) in &pending {
                if !self.functions.contains_key(handle) {
                    let code = self.module.get_finalized_function(*packed_id);
                    wrappers.push((*handle, compiled_fn_from_raw(spec, code)?));
                }
                let body_code = self.module.get_finalized_function(*body_id);
                bodies.push((spec.clone(), body_code as usize as u64));
            }
            Ok::<(Vec<(u32, CompiledFn)>, Vec<(FunctionSpec, u64)>), JitError>((wrappers, bodies))
        }));
        ACTIVE_DIRECT_FUNCS.with(|slot| {
            *slot.borrow_mut() = None;
        });

        let (wrappers, bodies) = match result {
            Ok(Ok(v)) => v,
            Ok(Err(err)) => return Err(err),
            Err(panic) => {
                let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                    (*s).to_string()
                } else if let Some(s) = panic.downcast_ref::<String>() {
                    s.clone()
                } else {
                    "unknown Rust panic".to_string()
                };
                return Err(JitError(format!("panic compiling Moonlift stable batch: {}", msg)));
            }
        };

        for (handle, compiled) in wrappers {
            self.functions.insert(handle, compiled);
        }
        for (spec, addr) in bodies {
            if let Some(record) = self.stable_funcs.get_mut(&spec) {
                *record.body_cell = addr;
                record.body_ready = true;
            }
        }

        Ok(handles)
    }

    fn compile_function_without_cache(&mut self, spec: FunctionSpec) -> Result<u32, JitError> {
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
        Ok(handle)
    }

    fn dump_disasm_impl(&mut self, spec: FunctionSpec) -> Result<String, JitError> {
        let debug_id = self.next_debug_id;
        self.next_debug_id = self
            .next_debug_id
            .checked_add(1)
            .ok_or_else(|| JitError("jit debug id overflow".to_string()))?;
        let symbol_name = format!("moonlift_dbg_{}_{}", debug_id, sanitize_symbol(&spec.name));
        let typed_symbol = format!("{}_typed", symbol_name);
        let typed_sig = make_typed_signature(&mut self.module, &spec);
        let typed_id = self.module
            .declare_function(&typed_symbol, Linkage::Local, &typed_sig)
            .map_err(|e| JitError(format!("failed to declare typed debug function: {e}")))?;

        let mut direct_funcs: HashMap<String, DirectFuncInfo> = HashMap::new();
        direct_funcs.insert(spec.name.clone(), DirectFuncInfo {
            typed_func_id: typed_id,
            params: spec.params.clone(),
            result: spec.result,
        });

        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            ACTIVE_DIRECT_FUNCS.with(|slot| {
                *slot.borrow_mut() = Some(direct_funcs.clone());
            });
            dump_function_disasm_typed(&mut self.module, typed_id, &spec)
        }));
        ACTIVE_DIRECT_FUNCS.with(|slot| {
            *slot.borrow_mut() = None;
        });

        match result {
            Ok(Ok(text)) => Ok(text),
            Ok(Err(err)) => Err(err),
            Err(panic) => {
                let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                    (*s).to_string()
                } else if let Some(s) = panic.downcast_ref::<String>() {
                    s.clone()
                } else {
                    "unknown Rust panic".to_string()
                };
                Err(JitError(format!("panic dumping disasm for {}: {}", spec.name, msg)))
            }
        }
    }
}

fn expr_local(name: &str, ty: ScalarType) -> Expr {
    Expr::Local {
        name: name.to_string(),
        ty,
    }
}

fn expr_const(ty: ScalarType, bits: u64) -> Expr {
    Expr::Const { ty, bits }
}

fn expr_binary(op: BinaryOp, ty: ScalarType, lhs: Expr, rhs: Expr) -> Expr {
    Expr::Binary {
        op,
        ty,
        lhs: Box::new(lhs),
        rhs: Box::new(rhs),
    }
}

fn expr_index_addr(base: Expr, index: Expr, elem_size: u32, limit: Option<Expr>) -> Expr {
    Expr::IndexAddr {
        base: Box::new(base),
        index: Box::new(index),
        elem_size,
        limit: limit.map(Box::new),
    }
}

fn expr_is_local(expr: &Expr, name: &str, ty: ScalarType) -> bool {
    matches!(expr, Expr::Local { name: n, ty: t } if n == name && *t == ty)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum StepDirection {
    Asc,
    Desc,
}

impl StepDirection {
    pub fn name(self) -> &'static str {
        match self {
            StepDirection::Asc => "asc",
            StepDirection::Desc => "desc",
        }
    }

    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "asc" => Some(StepDirection::Asc),
            "desc" => Some(StepDirection::Desc),
            _ => None,
        }
    }
}

fn const_step_direction(ty: ScalarType, expr: &Expr) -> Option<StepDirection> {
    match expr {
        Expr::Const { ty: expr_ty, bits } if *expr_ty == ty && !ty.is_float() => match ty {
            ScalarType::I8 => {
                let v = *bits as i8;
                if v > 0 {
                    Some(StepDirection::Asc)
                } else if v < 0 {
                    Some(StepDirection::Desc)
                } else {
                    None
                }
            }
            ScalarType::I16 => {
                let v = *bits as i16;
                if v > 0 {
                    Some(StepDirection::Asc)
                } else if v < 0 {
                    Some(StepDirection::Desc)
                } else {
                    None
                }
            }
            ScalarType::I32 => {
                let v = *bits as i32;
                if v > 0 {
                    Some(StepDirection::Asc)
                } else if v < 0 {
                    Some(StepDirection::Desc)
                } else {
                    None
                }
            }
            ScalarType::I64 => {
                let v = *bits as i64;
                if v > 0 {
                    Some(StepDirection::Asc)
                } else if v < 0 {
                    Some(StepDirection::Desc)
                } else {
                    None
                }
            }
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

fn effective_step_direction(ty: ScalarType, step: &Expr, dir: Option<StepDirection>) -> Option<StepDirection> {
    dir.or_else(|| const_step_direction(ty, step))
}

fn explicit_for_range_direction(dir: StepDirection) -> Option<StepDirection> {
    match dir {
        StepDirection::Asc => None,
        StepDirection::Desc => Some(StepDirection::Desc),
    }
}

fn const_step_magnitude_bits(ty: ScalarType, expr: &Expr, dir: Option<StepDirection>) -> Option<u64> {
    let _ = effective_step_direction(ty, expr, dir)?;
    match expr {
        Expr::Const { ty: expr_ty, bits } if *expr_ty == ty && !ty.is_float() => match ty {
            ScalarType::I8 => {
                let v = *bits as i8 as i64;
                if v == 0 { None } else { Some(v.unsigned_abs()) }
            }
            ScalarType::I16 => {
                let v = *bits as i16 as i64;
                if v == 0 { None } else { Some(v.unsigned_abs()) }
            }
            ScalarType::I32 => {
                let v = *bits as i32 as i64;
                if v == 0 { None } else { Some(v.unsigned_abs()) }
            }
            ScalarType::I64 => {
                let v = *bits as i64;
                if v == 0 { None } else { Some(v.unsigned_abs()) }
            }
            ScalarType::U8 | ScalarType::U16 | ScalarType::U32 | ScalarType::U64 | ScalarType::Ptr => {
                if *bits == 0 { None } else { Some(*bits) }
            }
            _ => None,
        },
        _ => None,
    }
}

fn stmt_contains_break(stmt: &Stmt) -> bool {
    match stmt {
        Stmt::Break => true,
        Stmt::If { then_body, else_body, .. } => {
            then_body.iter().any(stmt_contains_break) || else_body.iter().any(stmt_contains_break)
        }
        Stmt::While { body, .. }
        | Stmt::LoopWhile { body, .. }
        | Stmt::ForRange { body, .. } => body.iter().any(stmt_contains_break),
        _ => false,
    }
}

fn stmt_contains_continue(stmt: &Stmt) -> bool {
    match stmt {
        Stmt::Continue => true,
        Stmt::If { then_body, else_body, .. } => {
            then_body.iter().any(stmt_contains_continue) || else_body.iter().any(stmt_contains_continue)
        }
        Stmt::While { body, .. }
        | Stmt::LoopWhile { body, .. }
        | Stmt::ForRange { body, .. } => body.iter().any(stmt_contains_continue),
        _ => false,
    }
}

fn stmt_assigns_name(stmt: &Stmt, target: &str) -> bool {
    match stmt {
        Stmt::Let { name, .. } | Stmt::Var { name, .. } | Stmt::Set { name, .. } => name == target,
        Stmt::If { then_body, else_body, .. } => {
            then_body.iter().any(|stmt| stmt_assigns_name(stmt, target))
                || else_body.iter().any(|stmt| stmt_assigns_name(stmt, target))
        }
        Stmt::While { body, .. } | Stmt::ForRange { body, .. } => {
            body.iter().any(|stmt| stmt_assigns_name(stmt, target))
        }
        Stmt::LoopWhile { vars, body, .. } => {
            vars.iter().any(|var| var.name == target) || body.iter().any(|stmt| stmt_assigns_name(stmt, target))
        }
        _ => false,
    }
}

fn extract_local_loop_compare(cond: &Expr, name: &str, ty: ScalarType) -> Option<(Expr, StepDirection, bool)> {
    match cond {
        Expr::Binary {
            op,
            ty: ScalarType::Bool,
            lhs,
            rhs,
        } if expr_is_local(lhs, name, ty) => match op {
            BinaryOp::Lt => Some((rhs.as_ref().clone(), StepDirection::Asc, false)),
            BinaryOp::Le => Some((rhs.as_ref().clone(), StepDirection::Asc, true)),
            BinaryOp::Gt => Some((rhs.as_ref().clone(), StepDirection::Desc, false)),
            BinaryOp::Ge => Some((rhs.as_ref().clone(), StepDirection::Desc, true)),
            _ => None,
        },
        Expr::Binary {
            op,
            ty: ScalarType::Bool,
            lhs,
            rhs,
        } if expr_is_local(rhs, name, ty) => match op {
            BinaryOp::Gt => Some((lhs.as_ref().clone(), StepDirection::Asc, false)),
            BinaryOp::Ge => Some((lhs.as_ref().clone(), StepDirection::Asc, true)),
            BinaryOp::Lt => Some((lhs.as_ref().clone(), StepDirection::Desc, false)),
            BinaryOp::Le => Some((lhs.as_ref().clone(), StepDirection::Desc, true)),
            _ => None,
        },
        _ => None,
    }
}

fn extract_local_step_update(expr: &Expr, name: &str, ty: ScalarType) -> Option<(Expr, StepDirection)> {
    match expr {
        Expr::Binary {
            op: BinaryOp::Add,
            ty: expr_ty,
            lhs,
            rhs,
        } if *expr_ty == ty && expr_is_local(lhs, name, ty) => {
            let dir = const_step_direction(ty, rhs)?;
            let bits = const_step_magnitude_bits(ty, rhs, Some(dir))?;
            Some((expr_const(ty, bits), dir))
        }
        Expr::Binary {
            op: BinaryOp::Add,
            ty: expr_ty,
            lhs,
            rhs,
        } if *expr_ty == ty && expr_is_local(rhs, name, ty) => {
            let dir = const_step_direction(ty, lhs)?;
            let bits = const_step_magnitude_bits(ty, lhs, Some(dir))?;
            Some((expr_const(ty, bits), dir))
        }
        Expr::Binary {
            op: BinaryOp::Sub,
            ty: expr_ty,
            lhs,
            rhs,
        } if *expr_ty == ty && expr_is_local(lhs, name, ty) => {
            let bits = const_step_magnitude_bits(ty, rhs, Some(StepDirection::Desc))?;
            Some((expr_const(ty, bits), StepDirection::Desc))
        }
        _ => None,
    }
}

fn loopwhile_primary_index(vars: &[LoopVar], cond: &Expr, next: &[Expr]) -> Option<usize> {
    if vars.len() != next.len() {
        return None;
    }
    let mut found = None;
    for (i, var) in vars.iter().enumerate() {
        if var.ty.is_float() {
            continue;
        }
        let Some((_, dir, _)) = extract_local_loop_compare(cond, &var.name, var.ty) else {
            continue;
        };
        if extract_local_step_update(&next[i], &var.name, var.ty)
            .map(|(_, step_dir)| step_dir)
            != Some(dir)
        {
            continue;
        }
        if found.is_some() {
            return None;
        }
        found = Some(i);
    }
    found
}

fn reorder_loopwhile_primary_first(vars: &[LoopVar], next: &[Expr], primary_idx: usize) -> (Vec<LoopVar>, Vec<Expr>) {
    let mut ordered_vars = Vec::with_capacity(vars.len());
    let mut ordered_next = Vec::with_capacity(next.len());
    ordered_vars.push(vars[primary_idx].clone());
    ordered_next.push(next[primary_idx].clone());
    for i in 0..vars.len() {
        if i == primary_idx {
            continue;
        }
        ordered_vars.push(vars[i].clone());
        ordered_next.push(next[i].clone());
    }
    (ordered_vars, ordered_next)
}

fn try_rewrite_loopwhile_to_for_range(stmt: &Stmt) -> Option<Vec<Stmt>> {
    let Stmt::LoopWhile { vars, cond, body, next } = stmt else {
        return None;
    };
    if vars.is_empty() || vars.len() != next.len() {
        return None;
    }
    if body.iter().any(stmt_contains_break) || body.iter().any(stmt_contains_continue) {
        return None;
    }

    let primary_idx = loopwhile_primary_index(vars, cond, next)?;
    let (vars, next) = reorder_loopwhile_primary_first(vars, next, primary_idx);
    let first = &vars[0];
    let (finish, dir, inclusive) = extract_local_loop_compare(cond, &first.name, first.ty)?;
    if vars.iter().any(|var| expr_mentions_local(&finish, &var.name, var.ty)) {
        return None;
    }
    if body.iter().any(|stmt| vars.iter().any(|var| stmt_assigns_name(stmt, &var.name))) {
        return None;
    }

    let (step, step_dir) = extract_local_step_update(&next[0], &first.name, first.ty)?;
    if step_dir != dir {
        return None;
    }

    let mut out = Vec::with_capacity(vars.len() + 1);
    for var in &vars {
        out.push(Stmt::Var {
            name: var.name.clone(),
            ty: var.ty,
            init: var.init.clone(),
        });
    }

    let mut loop_body = body.clone();
    if vars.len() > 1 {
        for i in 1..vars.len() {
            let temp_name = format!("__mlopt_next${}", i);
            loop_body.push(Stmt::Let {
                name: temp_name.clone(),
                ty: vars[i].ty,
                init: next[i].clone(),
            });
            loop_body.push(Stmt::Set {
                name: vars[i].name.clone(),
                value: expr_local(&temp_name, vars[i].ty),
            });
        }
    }

    out.push(Stmt::ForRange {
        name: first.name.clone(),
        ty: first.ty,
        start: expr_local(&first.name, first.ty),
        finish,
        step,
        dir: explicit_for_range_direction(dir),
        inclusive,
        scoped: false,
        body: loop_body,
    });
    Some(out)
}

fn scalar_bit_width(ty: ScalarType) -> Option<u32> {
    match ty {
        ScalarType::I8 | ScalarType::U8 => Some(8),
        ScalarType::I16 | ScalarType::U16 => Some(16),
        ScalarType::I32 | ScalarType::U32 | ScalarType::F32 => Some(32),
        ScalarType::I64 | ScalarType::U64 | ScalarType::F64 => Some(64),
        _ => None,
    }
}

fn wrap_int_bits(ty: ScalarType, value: u128) -> u64 {
    let bits = scalar_bit_width(ty).expect("integer type required") as u128;
    if bits == 64 {
        value as u64
    } else {
        let mask = (1u128 << bits) - 1;
        (value & mask) as u64
    }
}

fn wrapping_add_bits(ty: ScalarType, lhs: u64, rhs: u64) -> u64 {
    wrap_int_bits(ty, lhs as u128 + rhs as u128)
}

fn wrapping_sub_bits(ty: ScalarType, lhs: u64, rhs: u64) -> u64 {
    let bits = scalar_bit_width(ty).expect("integer type required") as u128;
    let modulus = if bits == 64 { 1u128 << 64 } else { 1u128 << bits };
    wrap_int_bits(ty, (lhs as u128 + modulus - rhs as u128) % modulus)
}

fn wrapping_mul_bits(ty: ScalarType, lhs: u64, rhs: u64) -> u64 {
    wrap_int_bits(ty, lhs as u128 * rhs as u128)
}

fn unit_step_direction(ty: ScalarType, expr: &Expr, dir: Option<StepDirection>) -> Option<StepDirection> {
    let dir = effective_step_direction(ty, expr, dir)?;
    if const_step_magnitude_bits(ty, expr, Some(dir)) == Some(1) {
        Some(dir)
    } else {
        None
    }
}

#[derive(Clone, Copy)]
struct LoopAffineOffset {
    has_loop: bool,
    offset: i64,
}

fn loop_index_const_offset(expr: &Expr, loop_name: &str, ty: ScalarType) -> Option<i64> {
    let affine = loop_index_affine(expr, loop_name, ty)?;
    if affine.has_loop {
        Some(affine.offset)
    } else {
        None
    }
}

fn loop_index_affine(expr: &Expr, loop_name: &str, ty: ScalarType) -> Option<LoopAffineOffset> {
    match expr {
        Expr::Local { name, ty: expr_ty } if *expr_ty == ty && name == loop_name => {
            Some(LoopAffineOffset { has_loop: true, offset: 0 })
        }
        Expr::Const { .. } => const_signed_i64(expr, ty).map(|offset| LoopAffineOffset {
            has_loop: false,
            offset,
        }),
        Expr::Binary {
            op: BinaryOp::Add,
            ty: expr_ty,
            lhs,
            rhs,
        } if *expr_ty == ty => {
            let lhs = loop_index_affine(lhs, loop_name, ty)?;
            let rhs = loop_index_affine(rhs, loop_name, ty)?;
            if lhs.has_loop && rhs.has_loop {
                None
            } else {
                Some(LoopAffineOffset {
                    has_loop: lhs.has_loop || rhs.has_loop,
                    offset: lhs.offset.checked_add(rhs.offset)?,
                })
            }
        }
        Expr::Binary {
            op: BinaryOp::Sub,
            ty: expr_ty,
            lhs,
            rhs,
        } if *expr_ty == ty => {
            let lhs = loop_index_affine(lhs, loop_name, ty)?;
            let rhs = loop_index_affine(rhs, loop_name, ty)?;
            if rhs.has_loop {
                None
            } else {
                Some(LoopAffineOffset {
                    has_loop: lhs.has_loop,
                    offset: lhs.offset.checked_sub(rhs.offset)?,
                })
            }
        }
        _ => None,
    }
}

fn expr_mentions_local(expr: &Expr, loop_name: &str, ty: ScalarType) -> bool {
    match expr {
        Expr::Local { name, ty: expr_ty } => *expr_ty == ty && name == loop_name,
        Expr::Unary { value, .. } | Expr::Cast { value, .. } => expr_mentions_local(value, loop_name, ty),
        Expr::Binary { lhs, rhs, .. } => {
            expr_mentions_local(lhs, loop_name, ty) || expr_mentions_local(rhs, loop_name, ty)
        }
        Expr::Let { init, body, .. } => {
            expr_mentions_local(init, loop_name, ty) || expr_mentions_local(body, loop_name, ty)
        }
        Expr::Block { stmts, result, .. } => {
            stmts.iter().any(|stmt| stmt_mentions_local(stmt, loop_name, ty))
                || expr_mentions_local(result, loop_name, ty)
        }
        Expr::If {
            cond,
            then_expr,
            else_expr,
            ..
        }
        | Expr::Select {
            cond,
            then_expr,
            else_expr,
            ..
        } => {
            expr_mentions_local(cond, loop_name, ty)
                || expr_mentions_local(then_expr, loop_name, ty)
                || expr_mentions_local(else_expr, loop_name, ty)
        }
        Expr::Load { addr, .. } => expr_mentions_local(addr, loop_name, ty),
        Expr::IndexAddr {
            base,
            index,
            limit,
            ..
        } => {
            expr_mentions_local(base, loop_name, ty)
                || expr_mentions_local(index, loop_name, ty)
                || limit
                    .as_deref()
                    .map(|limit| expr_mentions_local(limit, loop_name, ty))
                    .unwrap_or(false)
        }
        Expr::Memcmp { a, b, len } => {
            expr_mentions_local(a, loop_name, ty)
                || expr_mentions_local(b, loop_name, ty)
                || expr_mentions_local(len, loop_name, ty)
        }
        Expr::Call { target, args, .. } => {
            let target_mentions = match target {
                CallTarget::Direct { .. } => false,
                CallTarget::Indirect { addr, .. } => expr_mentions_local(addr, loop_name, ty),
            };
            target_mentions || args.iter().any(|arg| expr_mentions_local(arg, loop_name, ty))
        }
        Expr::Arg { .. } | Expr::Const { .. } | Expr::StackAddr { .. } => false,
    }
}

fn stmt_mentions_local(stmt: &Stmt, loop_name: &str, ty: ScalarType) -> bool {
    match stmt {
        Stmt::Let { init, .. } | Stmt::Var { init, .. } => expr_mentions_local(init, loop_name, ty),
        Stmt::Set { value, .. } => expr_mentions_local(value, loop_name, ty),
        Stmt::While { cond, body } => {
            expr_mentions_local(cond, loop_name, ty)
                || body.iter().any(|stmt| stmt_mentions_local(stmt, loop_name, ty))
        }
        Stmt::LoopWhile { vars, cond, body, next } => {
            vars.iter().any(|var| expr_mentions_local(&var.init, loop_name, ty))
                || expr_mentions_local(cond, loop_name, ty)
                || body.iter().any(|stmt| stmt_mentions_local(stmt, loop_name, ty))
                || next.iter().any(|expr| expr_mentions_local(expr, loop_name, ty))
        }
        Stmt::ForRange {
            start,
            finish,
            step,
            body,
            ..
        } => {
            expr_mentions_local(start, loop_name, ty)
                || expr_mentions_local(finish, loop_name, ty)
                || expr_mentions_local(step, loop_name, ty)
                || body.iter().any(|stmt| stmt_mentions_local(stmt, loop_name, ty))
        }
        Stmt::If {
            cond,
            then_body,
            else_body,
        } => {
            expr_mentions_local(cond, loop_name, ty)
                || then_body.iter().any(|stmt| stmt_mentions_local(stmt, loop_name, ty))
                || else_body.iter().any(|stmt| stmt_mentions_local(stmt, loop_name, ty))
        }
        Stmt::Store { addr, value, .. } => {
            expr_mentions_local(addr, loop_name, ty) || expr_mentions_local(value, loop_name, ty)
        }
        Stmt::BoundsCheck { index, limit } => {
            expr_mentions_local(index, loop_name, ty) || expr_mentions_local(limit, loop_name, ty)
        }
        Stmt::Assert { cond } => expr_mentions_local(cond, loop_name, ty),
        Stmt::Memcpy { dst, src, len } | Stmt::Memmove { dst, src, len } => {
            expr_mentions_local(dst, loop_name, ty)
                || expr_mentions_local(src, loop_name, ty)
                || expr_mentions_local(len, loop_name, ty)
        }
        Stmt::Memset { dst, byte, len } => {
            expr_mentions_local(dst, loop_name, ty)
                || expr_mentions_local(byte, loop_name, ty)
                || expr_mentions_local(len, loop_name, ty)
        }
        Stmt::Call { target, args } => {
            let target_mentions = match target {
                CallTarget::Direct { .. } => false,
                CallTarget::Indirect { addr, .. } => expr_mentions_local(addr, loop_name, ty),
            };
            target_mentions || args.iter().any(|arg| expr_mentions_local(arg, loop_name, ty))
        }
        Stmt::StackSlot { .. } | Stmt::Break | Stmt::Continue => false,
    }
}

fn const_signed_i64(expr: &Expr, ty: ScalarType) -> Option<i64> {
    match expr {
        Expr::Const { ty: expr_ty, bits } if *expr_ty == ty && !ty.is_float() => Some(match ty {
            ScalarType::I8 => *bits as i8 as i64,
            ScalarType::I16 => *bits as i16 as i64,
            ScalarType::I32 => *bits as i32 as i64,
            ScalarType::I64 => *bits as i64,
            ScalarType::U8 => *bits as u8 as i64,
            ScalarType::U16 => *bits as u16 as i64,
            ScalarType::U32 => *bits as u32 as i64,
            ScalarType::U64 | ScalarType::Ptr => *bits as i64,
            _ => return None,
        }),
        _ => None,
    }
}

fn offset_index_expr(base: Expr, ty: ScalarType, offset: i64) -> Expr {
    if offset == 0 {
        return base;
    }
    if offset > 0 {
        expr_binary(BinaryOp::Add, ty, base, expr_const(ty, offset as u64))
    } else {
        expr_binary(BinaryOp::Sub, ty, base, expr_const(ty, (-offset) as u64))
    }
}

fn enter_loop_expr(start: Expr, finish: Expr, dir: StepDirection, inclusive: bool) -> Expr {
    expr_binary(
        match (dir, inclusive) {
            (StepDirection::Asc, false) => BinaryOp::Lt,
            (StepDirection::Asc, true) => BinaryOp::Le,
            (StepDirection::Desc, false) => BinaryOp::Gt,
            (StepDirection::Desc, true) => BinaryOp::Ge,
        },
        ScalarType::Bool,
        start,
        finish,
    )
}

fn collect_static_bounded_index_offsets_from_expr(expr: &Expr, loop_name: &str, ty: ScalarType, out: &mut Vec<(Expr, i64)>) {
    match expr {
        Expr::IndexAddr { base, index, limit, .. } => {
            if let Some(limit_expr) = limit.as_deref() {
                if let Some(offset) = loop_index_const_offset(index, loop_name, ty) {
                    out.push((limit_expr.clone(), offset));
                }
                collect_static_bounded_index_offsets_from_expr(limit_expr, loop_name, ty, out);
            }
            collect_static_bounded_index_offsets_from_expr(base, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(index, loop_name, ty, out);
        }
        Expr::Unary { value, .. } | Expr::Cast { value, .. } => {
            collect_static_bounded_index_offsets_from_expr(value, loop_name, ty, out);
        }
        Expr::Binary { lhs, rhs, .. } => {
            collect_static_bounded_index_offsets_from_expr(lhs, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(rhs, loop_name, ty, out);
        }
        Expr::Let { init, body, .. } => {
            collect_static_bounded_index_offsets_from_expr(init, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(body, loop_name, ty, out);
        }
        Expr::Block { stmts, result, .. } => {
            for stmt in stmts {
                collect_static_bounded_index_offsets_from_stmt(stmt, loop_name, ty, out);
            }
            collect_static_bounded_index_offsets_from_expr(result, loop_name, ty, out);
        }
        Expr::If {
            cond,
            then_expr,
            else_expr,
            ..
        }
        | Expr::Select {
            cond,
            then_expr,
            else_expr,
            ..
        } => {
            collect_static_bounded_index_offsets_from_expr(cond, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(then_expr, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(else_expr, loop_name, ty, out);
        }
        Expr::Load { addr, .. } => collect_static_bounded_index_offsets_from_expr(addr, loop_name, ty, out),
        Expr::Memcmp { a, b, len } => {
            collect_static_bounded_index_offsets_from_expr(a, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(b, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(len, loop_name, ty, out);
        }
        Expr::Call { target, args, .. } => {
            if let CallTarget::Indirect { addr, .. } = target {
                collect_static_bounded_index_offsets_from_expr(addr, loop_name, ty, out);
            }
            for arg in args {
                collect_static_bounded_index_offsets_from_expr(arg, loop_name, ty, out);
            }
        }
        Expr::Arg { .. } | Expr::Local { .. } | Expr::Const { .. } | Expr::StackAddr { .. } => {}
    }
}

fn collect_static_bounded_index_offsets_from_stmt(stmt: &Stmt, loop_name: &str, ty: ScalarType, out: &mut Vec<(Expr, i64)>) {
    match stmt {
        Stmt::Let { init, .. } | Stmt::Var { init, .. } => collect_static_bounded_index_offsets_from_expr(init, loop_name, ty, out),
        Stmt::Set { value, .. } => collect_static_bounded_index_offsets_from_expr(value, loop_name, ty, out),
        Stmt::If {
            cond,
            then_body,
            else_body,
        } => {
            collect_static_bounded_index_offsets_from_expr(cond, loop_name, ty, out);
            for stmt in then_body {
                collect_static_bounded_index_offsets_from_stmt(stmt, loop_name, ty, out);
            }
            for stmt in else_body {
                collect_static_bounded_index_offsets_from_stmt(stmt, loop_name, ty, out);
            }
        }
        Stmt::Store { addr, value, .. } => {
            collect_static_bounded_index_offsets_from_expr(addr, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(value, loop_name, ty, out);
        }
        Stmt::BoundsCheck { index, limit } => {
            collect_static_bounded_index_offsets_from_expr(index, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(limit, loop_name, ty, out);
        }
        Stmt::Assert { cond } => {
            collect_static_bounded_index_offsets_from_expr(cond, loop_name, ty, out);
        }
        Stmt::Memcpy { dst, src, len } | Stmt::Memmove { dst, src, len } => {
            collect_static_bounded_index_offsets_from_expr(dst, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(src, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(len, loop_name, ty, out);
        }
        Stmt::Memset { dst, byte, len } => {
            collect_static_bounded_index_offsets_from_expr(dst, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(byte, loop_name, ty, out);
            collect_static_bounded_index_offsets_from_expr(len, loop_name, ty, out);
        }
        Stmt::Call { target, args } => {
            if let CallTarget::Indirect { addr, .. } = target {
                collect_static_bounded_index_offsets_from_expr(addr, loop_name, ty, out);
            }
            for arg in args {
                collect_static_bounded_index_offsets_from_expr(arg, loop_name, ty, out);
            }
        }
        Stmt::LoopWhile { vars, cond, body, next } => {
            for var in vars {
                collect_static_bounded_index_offsets_from_expr(&var.init, loop_name, ty, out);
            }
            collect_static_bounded_index_offsets_from_expr(cond, loop_name, ty, out);
            for stmt in body {
                collect_static_bounded_index_offsets_from_stmt(stmt, loop_name, ty, out);
            }
            for value in next {
                collect_static_bounded_index_offsets_from_expr(value, loop_name, ty, out);
            }
        }
        Stmt::While { .. } | Stmt::ForRange { .. } | Stmt::StackSlot { .. } | Stmt::Break | Stmt::Continue => {}
    }
}

fn strip_hoisted_static_bounds_from_expr(expr: &Expr, loop_name: &str, ty: ScalarType, finish: &Expr) -> Expr {
    match expr {
        Expr::IndexAddr {
            base,
            index,
            elem_size,
            limit,
        } => {
            let base = strip_hoisted_static_bounds_from_expr(base, loop_name, ty, finish);
            let index = strip_hoisted_static_bounds_from_expr(index, loop_name, ty, finish);
            let limit = limit
                .as_deref()
                .map(|v| strip_hoisted_static_bounds_from_expr(v, loop_name, ty, finish));
            let keep_limit = if let Some(limit_expr) = &limit {
                !(loop_index_const_offset(&index, loop_name, ty).is_some()
                    && !expr_mentions_local(limit_expr, loop_name, ty))
            } else {
                false
            };
            expr_index_addr(base, index, *elem_size, if keep_limit { limit } else { None })
        }
        Expr::Unary { op, ty: expr_ty, value } => Expr::Unary {
            op: *op,
            ty: *expr_ty,
            value: Box::new(strip_hoisted_static_bounds_from_expr(value, loop_name, ty, finish)),
        },
        Expr::Binary {
            op,
            ty: expr_ty,
            lhs,
            rhs,
        } => expr_binary(
            *op,
            *expr_ty,
            strip_hoisted_static_bounds_from_expr(lhs, loop_name, ty, finish),
            strip_hoisted_static_bounds_from_expr(rhs, loop_name, ty, finish),
        ),
        Expr::Let {
            name,
            ty: expr_ty,
            init,
            body,
        } => Expr::Let {
            name: name.clone(),
            ty: *expr_ty,
            init: Box::new(strip_hoisted_static_bounds_from_expr(init, loop_name, ty, finish)),
            body: Box::new(strip_hoisted_static_bounds_from_expr(body, loop_name, ty, finish)),
        },
        Expr::Block { stmts, result, ty: expr_ty } => Expr::Block {
            stmts: stmts
                .iter()
                .map(|stmt| strip_hoisted_static_bounds_from_stmt(stmt, loop_name, ty, finish))
                .collect(),
            result: Box::new(strip_hoisted_static_bounds_from_expr(result, loop_name, ty, finish)),
            ty: *expr_ty,
        },
        Expr::If {
            cond,
            then_expr,
            else_expr,
            ty: expr_ty,
        } => Expr::If {
            cond: Box::new(strip_hoisted_static_bounds_from_expr(cond, loop_name, ty, finish)),
            then_expr: Box::new(strip_hoisted_static_bounds_from_expr(then_expr, loop_name, ty, finish)),
            else_expr: Box::new(strip_hoisted_static_bounds_from_expr(else_expr, loop_name, ty, finish)),
            ty: *expr_ty,
        },
        Expr::Load { ty: expr_ty, addr } => Expr::Load {
            ty: *expr_ty,
            addr: Box::new(strip_hoisted_static_bounds_from_expr(addr, loop_name, ty, finish)),
        },
        Expr::Memcmp { a, b, len } => Expr::Memcmp {
            a: Box::new(strip_hoisted_static_bounds_from_expr(a, loop_name, ty, finish)),
            b: Box::new(strip_hoisted_static_bounds_from_expr(b, loop_name, ty, finish)),
            len: Box::new(strip_hoisted_static_bounds_from_expr(len, loop_name, ty, finish)),
        },
        Expr::Cast { op, ty: expr_ty, value } => Expr::Cast {
            op: *op,
            ty: *expr_ty,
            value: Box::new(strip_hoisted_static_bounds_from_expr(value, loop_name, ty, finish)),
        },
        Expr::Call { target, ty: expr_ty, args } => Expr::Call {
            target: match target {
                CallTarget::Direct { name, params, result } => CallTarget::Direct {
                    name: name.clone(),
                    params: params.clone(),
                    result: *result,
                },
                CallTarget::Indirect { addr, params, result, packed } => CallTarget::Indirect {
                    addr: Box::new(strip_hoisted_static_bounds_from_expr(addr, loop_name, ty, finish)),
                    params: params.clone(),
                    result: *result,
                    packed: *packed,
                },
            },
            ty: *expr_ty,
            args: args
                .iter()
                .map(|arg| strip_hoisted_static_bounds_from_expr(arg, loop_name, ty, finish))
                .collect(),
        },
        Expr::Select {
            cond,
            then_expr,
            else_expr,
            ty: expr_ty,
        } => Expr::Select {
            cond: Box::new(strip_hoisted_static_bounds_from_expr(cond, loop_name, ty, finish)),
            then_expr: Box::new(strip_hoisted_static_bounds_from_expr(then_expr, loop_name, ty, finish)),
            else_expr: Box::new(strip_hoisted_static_bounds_from_expr(else_expr, loop_name, ty, finish)),
            ty: *expr_ty,
        },
        Expr::Arg { .. } | Expr::Local { .. } | Expr::Const { .. } | Expr::StackAddr { .. } => expr.clone(),
    }
}

fn strip_hoisted_static_bounds_from_stmt(stmt: &Stmt, loop_name: &str, ty: ScalarType, finish: &Expr) -> Stmt {
    match stmt {
        Stmt::Let { name, ty: stmt_ty, init } => Stmt::Let {
            name: name.clone(),
            ty: *stmt_ty,
            init: strip_hoisted_static_bounds_from_expr(init, loop_name, ty, finish),
        },
        Stmt::Var { name, ty: stmt_ty, init } => Stmt::Var {
            name: name.clone(),
            ty: *stmt_ty,
            init: strip_hoisted_static_bounds_from_expr(init, loop_name, ty, finish),
        },
        Stmt::Set { name, value } => Stmt::Set {
            name: name.clone(),
            value: strip_hoisted_static_bounds_from_expr(value, loop_name, ty, finish),
        },
        Stmt::If {
            cond,
            then_body,
            else_body,
        } => Stmt::If {
            cond: strip_hoisted_static_bounds_from_expr(cond, loop_name, ty, finish),
            then_body: then_body
                .iter()
                .map(|stmt| strip_hoisted_static_bounds_from_stmt(stmt, loop_name, ty, finish))
                .collect(),
            else_body: else_body
                .iter()
                .map(|stmt| strip_hoisted_static_bounds_from_stmt(stmt, loop_name, ty, finish))
                .collect(),
        },
        Stmt::Store { ty: stmt_ty, addr, value } => Stmt::Store {
            ty: *stmt_ty,
            addr: strip_hoisted_static_bounds_from_expr(addr, loop_name, ty, finish),
            value: strip_hoisted_static_bounds_from_expr(value, loop_name, ty, finish),
        },
        Stmt::BoundsCheck { index, limit } => Stmt::BoundsCheck {
            index: strip_hoisted_static_bounds_from_expr(index, loop_name, ty, finish),
            limit: strip_hoisted_static_bounds_from_expr(limit, loop_name, ty, finish),
        },
        Stmt::Assert { cond } => Stmt::Assert {
            cond: strip_hoisted_static_bounds_from_expr(cond, loop_name, ty, finish),
        },
        Stmt::Memcpy { dst, src, len } => Stmt::Memcpy {
            dst: strip_hoisted_static_bounds_from_expr(dst, loop_name, ty, finish),
            src: strip_hoisted_static_bounds_from_expr(src, loop_name, ty, finish),
            len: strip_hoisted_static_bounds_from_expr(len, loop_name, ty, finish),
        },
        Stmt::Memmove { dst, src, len } => Stmt::Memmove {
            dst: strip_hoisted_static_bounds_from_expr(dst, loop_name, ty, finish),
            src: strip_hoisted_static_bounds_from_expr(src, loop_name, ty, finish),
            len: strip_hoisted_static_bounds_from_expr(len, loop_name, ty, finish),
        },
        Stmt::Memset { dst, byte, len } => Stmt::Memset {
            dst: strip_hoisted_static_bounds_from_expr(dst, loop_name, ty, finish),
            byte: strip_hoisted_static_bounds_from_expr(byte, loop_name, ty, finish),
            len: strip_hoisted_static_bounds_from_expr(len, loop_name, ty, finish),
        },
        Stmt::Call { target, args } => Stmt::Call {
            target: match target {
                CallTarget::Direct { name, params, result } => CallTarget::Direct {
                    name: name.clone(),
                    params: params.clone(),
                    result: *result,
                },
                CallTarget::Indirect { addr, params, result, packed } => CallTarget::Indirect {
                    addr: Box::new(strip_hoisted_static_bounds_from_expr(addr, loop_name, ty, finish)),
                    params: params.clone(),
                    result: *result,
                    packed: *packed,
                },
            },
            args: args
                .iter()
                .map(|arg| strip_hoisted_static_bounds_from_expr(arg, loop_name, ty, finish))
                .collect(),
        },
        Stmt::LoopWhile { vars, cond, body, next } => Stmt::LoopWhile {
            vars: vars
                .iter()
                .map(|var| LoopVar {
                    name: var.name.clone(),
                    ty: var.ty,
                    init: strip_hoisted_static_bounds_from_expr(&var.init, loop_name, ty, finish),
                })
                .collect(),
            cond: strip_hoisted_static_bounds_from_expr(cond, loop_name, ty, finish),
            body: body
                .iter()
                .map(|stmt| strip_hoisted_static_bounds_from_stmt(stmt, loop_name, ty, finish))
                .collect(),
            next: next
                .iter()
                .map(|expr| strip_hoisted_static_bounds_from_expr(expr, loop_name, ty, finish))
                .collect(),
        },
        Stmt::While { .. } | Stmt::ForRange { .. } | Stmt::StackSlot { .. } | Stmt::Break | Stmt::Continue => stmt.clone(),
    }
}

fn try_hoist_bounds_checks_for_range(stmt: &Stmt) -> Option<Vec<Stmt>> {
    let (name, ty, start, finish, step, dir_hint, inclusive, scoped, body) = match stmt {
        Stmt::ForRange {
            name,
            ty,
            start,
            finish,
            step,
            dir,
            inclusive,
            scoped,
            body,
        } if !ty.is_float() => (name, *ty, start, finish, step, *dir, *inclusive, *scoped, body),
        _ => return None,
    };

    let dir = unit_step_direction(ty, step, dir_hint)?;
    if body.iter().any(stmt_contains_break) || body.iter().any(stmt_contains_continue) {
        return None;
    }

    let mut candidates = Vec::new();
    for stmt in body {
        collect_static_bounded_index_offsets_from_stmt(stmt, name, ty, &mut candidates);
    }
    let accepted: Vec<(Expr, i64)> = candidates
        .into_iter()
        .filter(|(limit, _)| !expr_mentions_local(limit, name, ty))
        .collect();
    if accepted.is_empty() {
        return None;
    }

    let enter = enter_loop_expr(start.clone(), finish.clone(), dir, inclusive);
    let first = start.clone();
    let last = match (dir, inclusive) {
        (StepDirection::Asc, true) | (StepDirection::Desc, true) => finish.clone(),
        (StepDirection::Asc, false) => expr_binary(BinaryOp::Sub, ty, finish.clone(), expr_const(ty, 1)),
        (StepDirection::Desc, false) => expr_binary(BinaryOp::Add, ty, finish.clone(), expr_const(ty, 1)),
    };
    let (low_base, high_base) = match dir {
        StepDirection::Asc => (first, last),
        StepDirection::Desc => (last, first),
    };

    let mut checks = Vec::new();
    for (limit, offset) in accepted {
        let low = offset_index_expr(low_base.clone(), ty, offset);
        let high = offset_index_expr(high_base.clone(), ty, offset);
        let same = low == high;
        checks.push(Stmt::BoundsCheck {
            index: low,
            limit: limit.clone(),
        });
        if !same {
            checks.push(Stmt::BoundsCheck {
                index: high,
                limit,
            });
        }
    }

    let stripped_body: Vec<Stmt> = body
        .iter()
        .map(|stmt| strip_hoisted_static_bounds_from_stmt(stmt, name, ty, finish))
        .collect();

    Some(vec![Stmt::If {
        cond: enter,
        then_body: optimize_stmts(&checks),
        else_body: Vec::new(),
    }, Stmt::ForRange {
        name: name.clone(),
        ty,
        start: start.clone(),
        finish: finish.clone(),
        step: step.clone(),
        dir: dir_hint.or_else(|| explicit_for_range_direction(dir)),
        inclusive,
        scoped,
        body: stripped_body,
    }])
}

fn try_hoist_bounds_checks_loopwhile(stmt: &Stmt) -> Option<Vec<Stmt>> {
    let Stmt::LoopWhile { vars, cond, body, next } = stmt else {
        return None;
    };
    if vars.is_empty() || vars.len() != next.len() {
        return None;
    }
    if body.iter().any(stmt_contains_break) || body.iter().any(stmt_contains_continue) {
        return None;
    }

    let primary_idx = loopwhile_primary_index(vars, cond, next)?;
    let (vars, next) = reorder_loopwhile_primary_first(vars, next, primary_idx);
    let first = &vars[0];
    let (finish, dir, inclusive) = extract_local_loop_compare(cond, &first.name, first.ty)?;
    let (step, step_dir) = extract_local_step_update(&next[0], &first.name, first.ty)?;
    if step_dir != dir || const_step_magnitude_bits(first.ty, &step, Some(dir)) != Some(1) {
        return None;
    }

    let mut candidates = Vec::new();
    for stmt in body {
        collect_static_bounded_index_offsets_from_stmt(stmt, &first.name, first.ty, &mut candidates);
    }
    for value in &next {
        collect_static_bounded_index_offsets_from_expr(value, &first.name, first.ty, &mut candidates);
    }
    let accepted: Vec<(Expr, i64)> = candidates
        .into_iter()
        .filter(|(limit, _)| !expr_mentions_local(limit, &first.name, first.ty))
        .collect();
    if accepted.is_empty() {
        return None;
    }

    let enter = enter_loop_expr(first.init.clone(), finish.clone(), dir, inclusive);
    let first_base = first.init.clone();
    let last_base = match (dir, inclusive) {
        (StepDirection::Asc, true) | (StepDirection::Desc, true) => finish.clone(),
        (StepDirection::Asc, false) => expr_binary(BinaryOp::Sub, first.ty, finish.clone(), expr_const(first.ty, 1)),
        (StepDirection::Desc, false) => expr_binary(BinaryOp::Add, first.ty, finish.clone(), expr_const(first.ty, 1)),
    };
    let (low_base, high_base) = match dir {
        StepDirection::Asc => (first_base, last_base),
        StepDirection::Desc => (last_base, first.init.clone()),
    };

    let mut checks = Vec::new();
    for (limit, offset) in accepted {
        let low = offset_index_expr(low_base.clone(), first.ty, offset);
        let high = offset_index_expr(high_base.clone(), first.ty, offset);
        let same = low == high;
        checks.push(Stmt::BoundsCheck {
            index: low,
            limit: limit.clone(),
        });
        if !same {
            checks.push(Stmt::BoundsCheck {
                index: high,
                limit,
            });
        }
    }

    let stripped = strip_hoisted_static_bounds_from_stmt(stmt, &first.name, first.ty, &finish);
    Some(vec![Stmt::If {
        cond: enter,
        then_body: optimize_stmts(&checks),
        else_body: Vec::new(),
    }, stripped])
}

fn optimize_stmt(stmt: &Stmt) -> Vec<Stmt> {
    let optimized = match stmt {
        Stmt::Let { name, ty, init } => Stmt::Let {
            name: name.clone(),
            ty: *ty,
            init: optimize_expr(init),
        },
        Stmt::Var { name, ty, init } => Stmt::Var {
            name: name.clone(),
            ty: *ty,
            init: optimize_expr(init),
        },
        Stmt::Set { name, value } => Stmt::Set {
            name: name.clone(),
            value: optimize_expr(value),
        },
        Stmt::While { cond, body } => Stmt::While {
            cond: optimize_expr(cond),
            body: optimize_stmts(body),
        },
        Stmt::LoopWhile { vars, cond, body, next } => {
            let optimized = Stmt::LoopWhile {
                vars: vars
                    .iter()
                    .map(|var| LoopVar {
                        name: var.name.clone(),
                        ty: var.ty,
                        init: optimize_expr(&var.init),
                    })
                    .collect(),
                cond: optimize_expr(cond),
                body: optimize_stmts(body),
                next: next.iter().map(optimize_expr).collect(),
            };
            if let Some(hoisted) = try_hoist_bounds_checks_loopwhile(&optimized) {
                return optimize_stmts(&hoisted);
            }
            if let Some(rewritten) = try_rewrite_loopwhile_to_for_range(&optimized) {
                return optimize_stmts(&rewritten);
            }
            optimized
        },
        Stmt::ForRange {
            name,
            ty,
            start,
            finish,
            step,
            dir,
            inclusive,
            scoped,
            body,
        } => Stmt::ForRange {
            name: name.clone(),
            ty: *ty,
            start: optimize_expr(start),
            finish: optimize_expr(finish),
            step: optimize_expr(step),
            dir: *dir,
            inclusive: *inclusive,
            scoped: *scoped,
            body: optimize_stmts(body),
        },
        Stmt::If {
            cond,
            then_body,
            else_body,
        } => Stmt::If {
            cond: optimize_expr(cond),
            then_body: optimize_stmts(then_body),
            else_body: optimize_stmts(else_body),
        },
        Stmt::Store { ty, addr, value } => Stmt::Store {
            ty: *ty,
            addr: optimize_expr(addr),
            value: optimize_expr(value),
        },
        Stmt::BoundsCheck { index, limit } => Stmt::BoundsCheck {
            index: optimize_expr(index),
            limit: optimize_expr(limit),
        },
        Stmt::Assert { cond } => Stmt::Assert {
            cond: optimize_expr(cond),
        },
        Stmt::StackSlot { name, size, align } => Stmt::StackSlot {
            name: name.clone(),
            size: *size,
            align: *align,
        },
        Stmt::Memcpy { dst, src, len } => Stmt::Memcpy {
            dst: optimize_expr(dst),
            src: optimize_expr(src),
            len: optimize_expr(len),
        },
        Stmt::Memmove { dst, src, len } => Stmt::Memmove {
            dst: optimize_expr(dst),
            src: optimize_expr(src),
            len: optimize_expr(len),
        },
        Stmt::Memset { dst, byte, len } => Stmt::Memset {
            dst: optimize_expr(dst),
            byte: optimize_expr(byte),
            len: optimize_expr(len),
        },
        Stmt::Call { target, args } => Stmt::Call {
            target: target.clone(),
            args: args.iter().map(optimize_expr).collect(),
        },
        Stmt::Break => Stmt::Break,
        Stmt::Continue => Stmt::Continue,
    };

    if let Stmt::BoundsCheck { index, limit } = &optimized {
        if bounds_check_const_safe(index, limit) == Some(true) {
            return Vec::new();
        }
    }
    if let Some(hoisted) = try_hoist_bounds_checks_for_range(&optimized) {
        return hoisted;
    }
    vec![optimized]
}

fn optimize_stmts(stmts: &[Stmt]) -> Vec<Stmt> {
    let mut out = Vec::new();
    for stmt in stmts {
        let optimized = optimize_stmt(stmt);
        for item in optimized {
            let redundant = matches!(
                (&item, out.last()),
                (
                    Stmt::BoundsCheck { index: a_idx, limit: a_lim },
                    Some(Stmt::BoundsCheck { index: b_idx, limit: b_lim })
                ) if a_idx == b_idx && a_lim == b_lim
            );
            if !redundant {
                out.push(item);
            }
        }
    }
    out
}

fn sign_extend(bits: u64, width: u32) -> i64 {
    if width == 0 || width >= 64 {
        return bits as i64;
    }
    let shift = 64 - width;
    ((bits as i64) << shift) >> shift
}

fn is_zero_const(expr: &Expr, ty: ScalarType) -> bool {
    match expr {
        Expr::Const { ty: cty, bits } => *cty == ty && *bits == 0,
        _ => false,
    }
}

fn is_one_const(expr: &Expr, ty: ScalarType) -> bool {
    match expr {
        Expr::Const { ty: cty, bits } => *cty == ty && *bits == 1,
        _ => false,
    }
}

fn try_fold_compare(op: BinaryOp, operand_ty: ScalarType, lhs_bits: u64, rhs_bits: u64) -> Option<Expr> {
    let result = if operand_ty.is_float() {
        let width = scalar_bit_width(operand_ty);
        let (lv, rv) = match width {
            Some(32) => {
                let l = f32::from_bits(lhs_bits as u32) as f64;
                let r = f32::from_bits(rhs_bits as u32) as f64;
                (l, r)
            }
            Some(64) => {
                let l = f64::from_bits(lhs_bits);
                let r = f64::from_bits(rhs_bits);
                (l, r)
            }
            _ => return None,
        };
        // NaN comparisons
        if lv.is_nan() || rv.is_nan() {
            match op {
                BinaryOp::Ne => true,
                _ => false,
            }
        } else {
            match op {
                BinaryOp::Eq => lv == rv,
                BinaryOp::Ne => lv != rv,
                BinaryOp::Lt => lv < rv,
                BinaryOp::Le => lv <= rv,
                BinaryOp::Gt => lv > rv,
                BinaryOp::Ge => lv >= rv,
                _ => return None,
            }
        }
    } else {
        let width = scalar_bit_width(operand_ty)?;
        match op {
            BinaryOp::Eq => lhs_bits == rhs_bits,
            BinaryOp::Ne => lhs_bits != rhs_bits,
            BinaryOp::Lt => {
                if operand_ty.is_signed_integer() {
                    sign_extend(lhs_bits, width) < sign_extend(rhs_bits, width)
                } else {
                    lhs_bits < rhs_bits
                }
            }
            BinaryOp::Le => {
                if operand_ty.is_signed_integer() {
                    sign_extend(lhs_bits, width) <= sign_extend(rhs_bits, width)
                } else {
                    lhs_bits <= rhs_bits
                }
            }
            BinaryOp::Gt => {
                if operand_ty.is_signed_integer() {
                    sign_extend(lhs_bits, width) > sign_extend(rhs_bits, width)
                } else {
                    lhs_bits > rhs_bits
                }
            }
            BinaryOp::Ge => {
                if operand_ty.is_signed_integer() {
                    sign_extend(lhs_bits, width) >= sign_extend(rhs_bits, width)
                } else {
                    lhs_bits >= rhs_bits
                }
            }
            _ => return None,
        }
    };
    Some(Expr::Const { ty: ScalarType::Bool, bits: if result { 1 } else { 0 } })
}

fn try_fold_binary(op: BinaryOp, ty: ScalarType, lhs: &Expr, rhs: &Expr) -> Option<Expr> {
    let (lhs_bits, rhs_bits) = match (lhs, rhs) {
        (Expr::Const { ty: lt, bits: lb }, Expr::Const { ty: rt, bits: rb }) if *lt == *rt => (*lb, *rb),
        _ => return None,
    };
    let operand_ty = match lhs {
        Expr::Const { ty, .. } => *ty,
        _ => return None,
    };

    // Comparisons: operand_ty is the type of operands, result is Bool
    match op {
        BinaryOp::Eq | BinaryOp::Ne | BinaryOp::Lt | BinaryOp::Le | BinaryOp::Gt | BinaryOp::Ge => {
            return try_fold_compare(op, operand_ty, lhs_bits, rhs_bits);
        }
        _ => {}
    }

    // Logical And/Or on bools
    if ty.is_bool() {
        let lb = lhs_bits & 1;
        let rb = rhs_bits & 1;
        return match op {
            BinaryOp::And => Some(Expr::Const { ty, bits: lb & rb }),
            BinaryOp::Or => Some(Expr::Const { ty, bits: lb | rb }),
            _ => None,
        };
    }

    // Float arithmetic
    if ty.is_float() {
        let width = scalar_bit_width(ty);
        return match width {
            Some(32) => {
                let l = f32::from_bits(lhs_bits as u32);
                let r = f32::from_bits(rhs_bits as u32);
                let result = match op {
                    BinaryOp::Add => l + r,
                    BinaryOp::Sub => l - r,
                    BinaryOp::Mul => l * r,
                    BinaryOp::Div => l / r,
                    _ => return None,
                };
                Some(Expr::Const { ty, bits: result.to_bits() as u64 })
            }
            Some(64) => {
                let l = f64::from_bits(lhs_bits);
                let r = f64::from_bits(rhs_bits);
                let result = match op {
                    BinaryOp::Add => l + r,
                    BinaryOp::Sub => l - r,
                    BinaryOp::Mul => l * r,
                    BinaryOp::Div => l / r,
                    _ => return None,
                };
                Some(Expr::Const { ty, bits: result.to_bits() })
            }
            _ => None,
        };
    }

    // Integer arithmetic
    let width = scalar_bit_width(ty)?;
    let result_bits = match op {
        BinaryOp::Add => wrapping_add_bits(ty, lhs_bits, rhs_bits),
        BinaryOp::Sub => wrapping_sub_bits(ty, lhs_bits, rhs_bits),
        BinaryOp::Mul => wrapping_mul_bits(ty, lhs_bits, rhs_bits),
        BinaryOp::Div => {
            if rhs_bits == 0 { return None; }
            if ty.is_signed_integer() {
                let l = sign_extend(lhs_bits, width);
                let r = sign_extend(rhs_bits, width);
                if r == -1 && l == i64::MIN >> (64 - width) { return None; }
                wrap_int_bits(ty, l.wrapping_div(r) as u128)
            } else {
                wrap_int_bits(ty, (lhs_bits / rhs_bits) as u128)
            }
        }
        BinaryOp::Rem => {
            if rhs_bits == 0 { return None; }
            if ty.is_signed_integer() {
                let l = sign_extend(lhs_bits, width);
                let r = sign_extend(rhs_bits, width);
                if r == -1 && l == i64::MIN >> (64 - width) { return None; }
                wrap_int_bits(ty, l.wrapping_rem(r) as u128)
            } else {
                wrap_int_bits(ty, (lhs_bits % rhs_bits) as u128)
            }
        }
        BinaryOp::Band => lhs_bits & rhs_bits,
        BinaryOp::Bor => lhs_bits | rhs_bits,
        BinaryOp::Bxor => lhs_bits ^ rhs_bits,
        BinaryOp::Shl => {
            let shift = rhs_bits as u32;
            if shift >= width { 0 } else { wrap_int_bits(ty, (lhs_bits as u128) << shift) }
        }
        BinaryOp::ShrU => {
            let shift = rhs_bits as u32;
            if shift >= width { 0 } else { lhs_bits >> shift }
        }
        BinaryOp::ShrS => {
            let shift = rhs_bits as u32;
            if shift >= width {
                if sign_extend(lhs_bits, width) < 0 { wrap_int_bits(ty, u64::MAX as u128) } else { 0 }
            } else {
                let signed = sign_extend(lhs_bits, width);
                wrap_int_bits(ty, (signed >> shift) as u128)
            }
        }
        _ => return None,
    };
    Some(Expr::Const { ty, bits: result_bits })
}

fn try_simplify_binary(op: BinaryOp, ty: ScalarType, lhs: &Expr, rhs: &Expr) -> Option<Expr> {
    match op {
        BinaryOp::Add => {
            if is_zero_const(rhs, ty) { return Some(lhs.clone()); }
            if is_zero_const(lhs, ty) { return Some(rhs.clone()); }
        }
        BinaryOp::Sub => {
            if is_zero_const(rhs, ty) { return Some(lhs.clone()); }
        }
        BinaryOp::Mul => {
            if is_one_const(rhs, ty) { return Some(lhs.clone()); }
            if is_one_const(lhs, ty) { return Some(rhs.clone()); }
            if !ty.is_float() && is_zero_const(rhs, ty) { return Some(Expr::Const { ty, bits: 0 }); }
            if !ty.is_float() && is_zero_const(lhs, ty) { return Some(Expr::Const { ty, bits: 0 }); }
        }
        BinaryOp::Band => {
            if is_zero_const(rhs, ty) || is_zero_const(lhs, ty) {
                return Some(Expr::Const { ty, bits: 0 });
            }
        }
        BinaryOp::Bor => {
            if is_zero_const(rhs, ty) { return Some(lhs.clone()); }
            if is_zero_const(lhs, ty) { return Some(rhs.clone()); }
        }
        BinaryOp::Bxor => {
            if is_zero_const(rhs, ty) { return Some(lhs.clone()); }
            if is_zero_const(lhs, ty) { return Some(rhs.clone()); }
        }
        _ => {}
    }
    None
}

fn try_fold_unary(op: UnaryOp, ty: ScalarType, value: &Expr) -> Option<Expr> {
    let bits = match value {
        Expr::Const { ty: vty, bits } if *vty == ty => *bits,
        _ => return None,
    };
    match op {
        UnaryOp::Neg => {
            if ty.is_float() {
                match scalar_bit_width(ty) {
                    Some(32) => {
                        let f = f32::from_bits(bits as u32);
                        Some(Expr::Const { ty, bits: (-f).to_bits() as u64 })
                    }
                    Some(64) => {
                        let f = f64::from_bits(bits);
                        Some(Expr::Const { ty, bits: (-f).to_bits() })
                    }
                    _ => None,
                }
            } else {
                let width = scalar_bit_width(ty)?;
                let signed = sign_extend(bits, width);
                Some(Expr::Const { ty, bits: wrap_int_bits(ty, signed.wrapping_neg() as u128) })
            }
        }
        UnaryOp::Not => {
            if ty.is_bool() {
                Some(Expr::Const { ty, bits: if bits & 1 == 0 { 1 } else { 0 } })
            } else {
                None
            }
        }
        UnaryOp::Bnot => {
            let width = scalar_bit_width(ty)?;
            let mask = if width == 64 { u64::MAX } else { (1u64 << width) - 1 };
            Some(Expr::Const { ty, bits: !bits & mask })
        }
    }
}

fn optimize_expr(expr: &Expr) -> Expr {
    match expr {
        Expr::Arg { .. } | Expr::Local { .. } | Expr::Const { .. } | Expr::StackAddr { .. } => expr.clone(),
        Expr::Unary { op, ty, value } => {
            let opt_value = optimize_expr(value);
            if let Some(folded) = try_fold_unary(*op, *ty, &opt_value) {
                return folded;
            }
            Expr::Unary {
                op: *op,
                ty: *ty,
                value: Box::new(opt_value),
            }
        },
        Expr::Binary { op, ty, lhs, rhs } => {
            let opt_lhs = optimize_expr(lhs);
            let opt_rhs = optimize_expr(rhs);
            if let Some(folded) = try_fold_binary(*op, *ty, &opt_lhs, &opt_rhs) {
                return folded;
            }
            if let Some(simplified) = try_simplify_binary(*op, *ty, &opt_lhs, &opt_rhs) {
                return simplified;
            }
            Expr::Binary {
                op: *op,
                ty: *ty,
                lhs: Box::new(opt_lhs),
                rhs: Box::new(opt_rhs),
            }
        },
        Expr::Let { name, ty, init, body } => Expr::Let {
            name: name.clone(),
            ty: *ty,
            init: Box::new(optimize_expr(init)),
            body: Box::new(optimize_expr(body)),
        },
        Expr::Block { stmts, result, ty } => Expr::Block {
            stmts: optimize_stmts(stmts),
            result: Box::new(optimize_expr(result)),
            ty: *ty,
        },
        Expr::If {
            cond,
            then_expr,
            else_expr,
            ty,
        } => Expr::If {
            cond: Box::new(optimize_expr(cond)),
            then_expr: Box::new(optimize_expr(then_expr)),
            else_expr: Box::new(optimize_expr(else_expr)),
            ty: *ty,
        },
        Expr::Load { ty, addr } => Expr::Load {
            ty: *ty,
            addr: Box::new(optimize_expr(addr)),
        },
        Expr::IndexAddr {
            base,
            index,
            elem_size,
            limit,
        } => {
            let base = optimize_expr(base);
            let index = optimize_expr(index);
            let limit = limit.as_ref().map(|v| optimize_expr(v));
            if let Some(limit_expr) = &limit {
                if bounds_check_const_safe(&index, limit_expr) == Some(true) {
                    return Expr::IndexAddr {
                        base: Box::new(base),
                        index: Box::new(index),
                        elem_size: *elem_size,
                        limit: None,
                    };
                }
            }
            Expr::IndexAddr {
                base: Box::new(base),
                index: Box::new(index),
                elem_size: *elem_size,
                limit: limit.map(Box::new),
            }
        }
        Expr::Memcmp { a, b, len } => Expr::Memcmp {
            a: Box::new(optimize_expr(a)),
            b: Box::new(optimize_expr(b)),
            len: Box::new(optimize_expr(len)),
        },
        Expr::Cast { op, ty, value } => Expr::Cast {
            op: *op,
            ty: *ty,
            value: Box::new(optimize_expr(value)),
        },
        Expr::Call { target, ty, args } => Expr::Call {
            target: target.clone(),
            ty: *ty,
            args: args.iter().map(optimize_expr).collect(),
        },
        Expr::Select {
            cond,
            then_expr,
            else_expr,
            ty,
        } => Expr::Select {
            cond: Box::new(optimize_expr(cond)),
            then_expr: Box::new(optimize_expr(then_expr)),
            else_expr: Box::new(optimize_expr(else_expr)),
            ty: *ty,
        },
    }
}

pub fn optimize_function_spec(spec: &FunctionSpec) -> FunctionSpec {
    FunctionSpec {
        name: spec.name.clone(),
        params: spec.params.clone(),
        result: spec.result,
        locals: spec.locals.iter().map(|l| LocalDecl {
            name: l.name.clone(),
            ty: l.ty,
            init: optimize_expr(&l.init),
        }).collect(),
        body: optimize_expr(&spec.body),
    }
}

fn active_direct_func_info(name: &str) -> Option<DirectFuncInfo> {
    ACTIVE_DIRECT_FUNCS.with(|slot| slot.borrow().as_ref().and_then(|m| m.get(name).cloned()))
}

fn declare_packed_function(module: &mut JITModule, name: &str) -> Result<FuncId, JitError> {
    let mut sig = module.make_signature();
    sig.params.push(ir::AbiParam::new(types::I64));
    sig.returns.push(ir::AbiParam::new(types::I64));
    module
        .declare_function(name, Linkage::Export, &sig)
        .map_err(|e| JitError(format!("failed to declare JIT function {name}: {e}")))
}

fn compiled_fn_from_raw(spec: &FunctionSpec, code: *const u8) -> Result<CompiledFn, JitError> {
    let code = unsafe { mem::transmute::<_, unsafe extern "C" fn(*const u64) -> u64>(code) };
    Ok(CompiledFn {
        name: spec.name.clone(),
        params: spec.params.clone(),
        result: spec.result,
        code,
    })
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
    compiled_fn_from_raw(spec, code)
}

fn build_function_context(
    module: &mut JITModule,
    func_name: UserFuncName,
    spec: &FunctionSpec,
) -> Result<cranelift_codegen::Context, JitError> {
    let mut ctx = module.make_context();
    let mut func_ctx = FunctionBuilderContext::new();

    let sig = make_packed_signature(module);
    ctx.func.signature = sig;
    ctx.func.name = func_name;

    {
        let mut b = FunctionBuilder::new(&mut ctx.func, &mut func_ctx);
        let entry = b.create_block();
        b.switch_to_block(entry);
        b.append_block_params_for_function_params(entry);
        let packed_args_ptr = b.block_params(entry)[0];
        let args = unpack_packed_args_from_ptr(&mut b, packed_args_ptr, &spec.params)?;
        let mut lower = LowerCtx {
            args,
            bindings: HashMap::new(),
            stack_slots: HashMap::new(),
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

    Ok(ctx)
}

fn build_function_context_typed(
    module: &mut JITModule,
    func_name: UserFuncName,
    spec: &FunctionSpec,
) -> Result<cranelift_codegen::Context, JitError> {
    let mut ctx = module.make_context();
    let mut func_ctx = FunctionBuilderContext::new();

    let sig = make_typed_signature(module, spec);
    ctx.func.signature = sig;
    ctx.func.name = func_name;

    {
        let mut b = FunctionBuilder::new(&mut ctx.func, &mut func_ctx);
        let entry = b.create_block();
        b.switch_to_block(entry);
        b.append_block_params_for_function_params(entry);
        let params = b.block_params(entry).to_vec();
        let args = params;
        let mut lower = LowerCtx {
            args,
            bindings: HashMap::new(),
            stack_slots: HashMap::new(),
        };
        let mut next_var_index = 0u32;
        let mut loop_stack = Vec::new();
        bind_legacy_locals(module, &mut b, &spec.locals, &mut lower, &mut next_var_index, &mut loop_stack)?;
        let out = lower_expr(module, &mut b, &spec.body, &mut lower, &mut next_var_index, &mut loop_stack)?;
        let ret = if spec.result.is_void() {
            let _ = out;
            b.ins().iconst(types::I8, 0)
        } else {
            out
        };
        b.ins().return_(&[ret]);
        b.seal_all_blocks();
        b.finalize();
    }

    Ok(ctx)
}

fn define_typed_entry_trampoline(
    module: &mut JITModule,
    typed_id: FuncId,
    spec: &FunctionSpec,
    cell_ptr: u64,
) -> Result<(), JitError> {
    let mut ctx = module.make_context();
    let mut func_ctx = FunctionBuilderContext::new();

    let sig = make_typed_signature(module, spec);
    ctx.func.signature = sig;
    ctx.func.name = UserFuncName::user(0, typed_id.as_u32());

    {
        let mut b = FunctionBuilder::new(&mut ctx.func, &mut func_ctx);
        let entry = b.create_block();
        b.switch_to_block(entry);
        b.append_block_params_for_function_params(entry);
        let args = b.block_params(entry).to_vec();
        let cell_addr = b.ins().iconst(types::I64, cell_ptr as i64);
        let body_addr = b.ins().load(types::I64, MemFlags::new(), cell_addr, 0);
        b.ins().trapz(body_addr, ir::TrapCode::unwrap_user(1));
        let sig_ref = b.import_signature(make_typed_signature(module, spec));
        let inst = b.ins().call_indirect(sig_ref, body_addr, &args);
        let results = b.inst_results(inst).to_vec();
        b.ins().return_(&results);
        b.seal_all_blocks();
        b.finalize();
    }

    module
        .define_function(typed_id, &mut ctx)
        .map_err(|e| JitError(format!("failed to define typed entry trampoline for {}: {e:?}", spec.name)))?;
    module.clear_context(&mut ctx);
    Ok(())
}

fn build_packed_wrapper(
    module: &mut JITModule,
    packed_id: FuncId,
    typed_id: FuncId,
    spec: &FunctionSpec,
) -> Result<(), JitError> {
    let mut ctx = module.make_context();
    let mut func_ctx = FunctionBuilderContext::new();

    let packed_sig = make_packed_signature(module);
    ctx.func.signature = packed_sig;
    ctx.func.name = UserFuncName::user(0, packed_id.as_u32());

    {
        let mut b = FunctionBuilder::new(&mut ctx.func, &mut func_ctx);
        let entry = b.create_block();
        b.switch_to_block(entry);
        b.append_block_params_for_function_params(entry);
        let packed_args_ptr = b.block_params(entry)[0];
        let native_args = unpack_packed_args_from_ptr(&mut b, packed_args_ptr, &spec.params)?;

        let typed_ref = module.declare_func_in_func(typed_id, b.func);
        let inst = b.ins().call(typed_ref, &native_args);
        let typed_result = b.inst_results(inst)[0];

        let packed_result = if spec.result.is_void() {
            b.ins().iconst(types::I64, 0)
        } else {
            pack_scalar(&mut b, typed_result, spec.result)?
        };
        b.ins().return_(&[packed_result]);
        b.seal_all_blocks();
        b.finalize();
    }

    module
        .define_function(packed_id, &mut ctx)
        .map_err(|e| JitError(format!("failed to define packed wrapper for {}: {e:?}", spec.name)))?;
    module.clear_context(&mut ctx);
    Ok(())
}

fn define_function_body(
    module: &mut JITModule,
    func_id: FuncId,
    spec: &FunctionSpec,
) -> Result<(), JitError> {
    let mut ctx = build_function_context(module, UserFuncName::user(0, func_id.as_u32()), spec)?;
    module
        .define_function(func_id, &mut ctx)
        .map_err(|e| JitError(format!("failed to define JIT function {}: {e:?}", spec.name)))?;
    module.clear_context(&mut ctx);
    Ok(())
}

fn dump_function_disasm_typed(
    module: &mut JITModule,
    func_id: FuncId,
    spec: &FunctionSpec,
) -> Result<String, JitError> {
    let mut ctx = build_function_context_typed(module, UserFuncName::user(0, func_id.as_u32()), spec)?;
    ctx.set_disasm(true);
    let mut ctrl_plane = ControlPlane::default();
    ctx.compile(module.isa(), &mut ctrl_plane)
        .map_err(|e| JitError(format!("failed to compile disasm for {}: {e:?}", spec.name)))?;
    let clif = ctx.func.display().to_string();
    let vcode = ctx
        .compiled_code()
        .and_then(|compiled| compiled.vcode.clone())
        .ok_or_else(|| JitError(format!("no Cranelift disassembly available for {}", spec.name)))?;
    module.clear_context(&mut ctx);
    Ok(format!(";; clif\n{}\n;; vcode\n{}", clif, vcode))
}

fn compile_function_raw(
    module: &mut JITModule,
    handle: u32,
    spec: &FunctionSpec,
) -> Result<*const u8, JitError> {
    let name = format!("moonlift_fn_{}_{}", handle, sanitize_symbol(&spec.name));
    let func_id = declare_packed_function(module, &name)?;
    define_function_body(module, func_id, spec)?;
    module
        .finalize_definitions()
        .map_err(|e| JitError(format!("failed to finalize JIT definitions for {name}: {e}")))?;

    Ok(module.get_finalized_function(func_id))
}

fn make_packed_signature(module: &mut JITModule) -> ir::Signature {
    let mut sig = module.make_signature();
    sig.params.push(ir::AbiParam::new(types::I64));
    sig.returns.push(ir::AbiParam::new(types::I64));
    sig
}

fn unpack_packed_args_from_ptr(
    b: &mut FunctionBuilder<'_>,
    packed_args_ptr: Value,
    params: &[ScalarType],
) -> Result<Vec<Value>, JitError> {
    let mut args = Vec::with_capacity(params.len());
    let flags = MemFlags::new();
    for (i, ty) in params.iter().copied().enumerate() {
        let offset = i32::try_from(i.checked_mul(8).ok_or_else(|| {
            JitError("moonlift packed arg offset overflow".to_string())
        })?)
        .map_err(|_| JitError("moonlift packed arg offset overflow".to_string()))?;
        let bits = b.ins().load(types::I64, flags, packed_args_ptr, offset);
        args.push(unpack_scalar(b, bits, ty)?);
    }
    Ok(args)
}

fn make_typed_signature_from_parts(
    module: &mut JITModule,
    params: &[ScalarType],
    result: ScalarType,
) -> ir::Signature {
    let mut sig = module.make_signature();
    for p in params {
        sig.params.push(ir::AbiParam::new(p.abi_type()));
    }
    if result.is_void() {
        sig.returns.push(ir::AbiParam::new(types::I8));
    } else {
        sig.returns.push(ir::AbiParam::new(result.abi_type()));
    }
    sig
}

fn make_typed_signature(module: &mut JITModule, spec: &FunctionSpec) -> ir::Signature {
    make_typed_signature_from_parts(module, &spec.params, spec.result)
}

fn align_shift(align: u32) -> u8 {
    let mut shift = 0u8;
    let mut v = 1u32;
    while v < align.max(1) {
        v <<= 1;
        shift = shift.saturating_add(1);
    }
    shift
}

fn lower_runtime_memcpy(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    dst: Value,
    src: Value,
    len: Value,
    helper: &str,
) -> Result<Option<Value>, JitError> {
    let mut sig = module.make_signature();
    sig.params.push(ir::AbiParam::new(types::I64));
    sig.params.push(ir::AbiParam::new(types::I64));
    sig.params.push(ir::AbiParam::new(types::I64));
    if helper == "moonlift_rt_memcmp" {
        sig.returns.push(ir::AbiParam::new(types::I32));
    }
    let func_id = module
        .declare_function(helper, Linkage::Import, &sig)
        .map_err(|e| JitError(format!("failed to declare runtime helper {helper}: {e}")))?;
    let func_ref = module.declare_func_in_func(func_id, b.func);
    let inst = b.ins().call(func_ref, &[dst, src, len]);
    if helper == "moonlift_rt_memcmp" {
        Ok(Some(b.inst_results(inst)[0]))
    } else {
        Ok(None)
    }
}

fn lower_runtime_memset(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    dst: Value,
    byte: Value,
    len: Value,
) -> Result<(), JitError> {
    let mut sig = module.make_signature();
    sig.params.push(ir::AbiParam::new(types::I64));
    sig.params.push(ir::AbiParam::new(types::I8));
    sig.params.push(ir::AbiParam::new(types::I64));
    let func_id = module
        .declare_function("moonlift_rt_memset", Linkage::Import, &sig)
        .map_err(|e| JitError(format!("failed to declare runtime helper moonlift_rt_memset: {e}")))?;
    let func_ref = module.declare_func_in_func(func_id, b.func);
    b.ins().call(func_ref, &[dst, byte, len]);
    Ok(())
}

fn lower_packed_call_args_ptr(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    args: &[Expr],
    params: &[ScalarType],
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<LoopTargets>,
) -> Result<Value, JitError> {
    if args.is_empty() {
        return Ok(b.ins().iconst(types::I64, 0));
    }
    let size = u32::try_from(args.len().checked_mul(8).ok_or_else(|| {
        JitError("moonlift packed call arg buffer overflow".to_string())
    })?)
    .map_err(|_| JitError("moonlift packed call arg buffer overflow".to_string()))?;
    let slot = b.create_sized_stack_slot(StackSlotData::new(
        StackSlotKind::ExplicitSlot,
        size,
        align_shift(8),
    ));
    let base = b.ins().stack_addr(types::I64, slot, 0);
    let flags = MemFlags::new();
    for i in 0..args.len() {
        let v = lower_expr(module, b, &args[i], lower, next_var_index, loop_stack)?;
        let packed = pack_scalar(b, v, params[i])?;
        let offset = i32::try_from(i.checked_mul(8).ok_or_else(|| {
            JitError("moonlift packed call arg offset overflow".to_string())
        })?)
        .map_err(|_| JitError("moonlift packed call arg offset overflow".to_string()))?;
        b.ins().store(flags, packed, base, offset);
    }
    Ok(base)
}

fn lower_call_value(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    target: &CallTarget,
    args: &[Expr],
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<LoopTargets>,
) -> Result<Value, JitError> {
    match target {
        CallTarget::Direct { name, params, result } => {
            if let Some(info) = active_direct_func_info(name) {
                // Typed direct call — no pack/unpack overhead
                let func_ref = module.declare_func_in_func(info.typed_func_id, b.func);
                let mut native_args = Vec::with_capacity(args.len());
                for i in 0..args.len() {
                    native_args.push(lower_expr(module, b, &args[i], lower, next_var_index, loop_stack)?);
                }
                let inst = b.ins().call(func_ref, &native_args);
                let raw = b.inst_results(inst)[0];
                if info.result.is_void() {
                    Ok(b.ins().iconst(types::I8, 0))
                } else {
                    Ok(raw)
                }
            } else {
                // External direct import uses its native typed ABI.
                let sig = make_typed_signature_from_parts(module, params, *result);
                let func_id = module
                    .declare_function(name, Linkage::Import, &sig)
                    .map_err(|e| JitError(format!("failed to declare callee {name}: {e}")))?;
                let func_ref = module.declare_func_in_func(func_id, b.func);
                let mut native_args = Vec::with_capacity(args.len());
                for i in 0..args.len() {
                    native_args.push(lower_expr(module, b, &args[i], lower, next_var_index, loop_stack)?);
                }
                let inst = b.ins().call(func_ref, &native_args);
                let raw = b.inst_results(inst)[0];
                if result.is_void() {
                    Ok(b.ins().iconst(types::I8, 0))
                } else {
                    Ok(raw)
                }
            }
        }
        CallTarget::Indirect { addr, params, result, packed } => {
            let addr_val = lower_expr(module, b, addr, lower, next_var_index, loop_stack)?;
            if *packed {
                let sig = make_packed_signature(module);
                let sig_ref = b.import_signature(sig);
                let packed_args_ptr = lower_packed_call_args_ptr(
                    module,
                    b,
                    args,
                    params,
                    lower,
                    next_var_index,
                    loop_stack,
                )?;
                let inst = b.ins().call_indirect(sig_ref, addr_val, &[packed_args_ptr]);
                let packed = b.inst_results(inst)[0];
                if result.is_void() {
                    Ok(b.ins().iconst(types::I8, 0))
                } else {
                    unpack_scalar(b, packed, *result)
                }
            } else {
                let sig = make_typed_signature_from_parts(module, params, *result);
                let sig_ref = b.import_signature(sig);
                let mut native_args = Vec::with_capacity(args.len());
                for i in 0..args.len() {
                    native_args.push(lower_expr(module, b, &args[i], lower, next_var_index, loop_stack)?);
                }
                let inst = b.ins().call_indirect(sig_ref, addr_val, &native_args);
                let raw = b.inst_results(inst)[0];
                if result.is_void() {
                    Ok(b.ins().iconst(types::I8, 0))
                } else {
                    Ok(raw)
                }
            }
        }
    }
}

fn lower_call_stmt(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    target: &CallTarget,
    args: &[Expr],
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<LoopTargets>,
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
    loop_stack: &mut Vec<LoopTargets>,
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

fn binary_op_to_compare_op(op: BinaryOp) -> Option<CompareOp> {
    match op {
        BinaryOp::Eq => Some(CompareOp::Eq),
        BinaryOp::Ne => Some(CompareOp::Ne),
        BinaryOp::Lt => Some(CompareOp::Lt),
        BinaryOp::Le => Some(CompareOp::Le),
        BinaryOp::Gt => Some(CompareOp::Gt),
        BinaryOp::Ge => Some(CompareOp::Ge),
        _ => None,
    }
}

fn lower_expr_as_cond(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    expr: &Expr,
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<LoopTargets>,
) -> Result<Value, JitError> {
    match expr {
        Expr::Binary { op, ty: ScalarType::Bool, lhs, rhs } if binary_op_to_compare_op(*op).is_some() => {
            let cmp_op = binary_op_to_compare_op(*op).unwrap();
            let operand_ty = lhs.ty();
            let l = lower_expr(module, b, lhs, lower, next_var_index, loop_stack)?;
            let r = lower_expr(module, b, rhs, lower, next_var_index, loop_stack)?;
            Ok(lower_compare_raw(b, operand_ty, l, r, &cmp_op))
        }
        Expr::Binary { op: BinaryOp::And, ty: ScalarType::Bool, lhs, rhs } => {
            let l = lower_expr_as_cond(module, b, lhs, lower, next_var_index, loop_stack)?;
            let r = lower_expr_as_cond(module, b, rhs, lower, next_var_index, loop_stack)?;
            Ok(b.ins().band(l, r))
        }
        Expr::Binary { op: BinaryOp::Or, ty: ScalarType::Bool, lhs, rhs } => {
            let l = lower_expr_as_cond(module, b, lhs, lower, next_var_index, loop_stack)?;
            let r = lower_expr_as_cond(module, b, rhs, lower, next_var_index, loop_stack)?;
            Ok(b.ins().bor(l, r))
        }
        Expr::Unary { op: UnaryOp::Not, ty: ScalarType::Bool, value } => {
            let v = lower_expr_as_cond(module, b, value, lower, next_var_index, loop_stack)?;
            Ok(b.ins().bxor_imm(v, 1))
        }
        Expr::Const { ty: ScalarType::Bool, bits } => {
            Ok(b.ins().iconst(types::I8, if *bits & 1 != 0 { 1 } else { 0 }))
        }
        Expr::Select { cond, then_expr, else_expr, ty: ScalarType::Bool } => {
            let c = lower_expr_as_cond(module, b, cond, lower, next_var_index, loop_stack)?;
            let t = lower_expr_as_cond(module, b, then_expr, lower, next_var_index, loop_stack)?;
            let e = lower_expr_as_cond(module, b, else_expr, lower, next_var_index, loop_stack)?;
            Ok(b.ins().select(c, t, e))
        }
        _ => {
            let v = lower_expr(module, b, expr, lower, next_var_index, loop_stack)?;
            Ok(lower_bool_cond_from_value(b, v))
        }
    }
}

fn lower_condition(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    expr: &Expr,
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<LoopTargets>,
) -> Result<Value, JitError> {
    if expr.ty() != ScalarType::Bool {
        return Err(JitError("Moonlift condition must have type bool".to_string()));
    }
    lower_expr_as_cond(module, b, expr, lower, next_var_index, loop_stack)
}

fn lower_bool_cond_from_value(b: &mut FunctionBuilder<'_>, value: Value) -> Value {
    b.ins().icmp_imm(IntCC::NotEqual, value, 0)
}

fn lower_bool_value_from_cond(b: &mut FunctionBuilder<'_>, cond: Value) -> Value {
    let one = b.ins().iconst(types::I8, 1);
    let zero = b.ins().iconst(types::I8, 0);
    b.ins().select(cond, one, zero)
}

fn lower_compare_values_raw(
    b: &mut FunctionBuilder<'_>,
    ty: ScalarType,
    lhs: Value,
    rhs: Value,
    op: CompareOp,
) -> Value {
    lower_compare_raw(b, ty, lhs, rhs, &op)
}

fn lower_for_range_condition_with_direction(
    b: &mut FunctionBuilder<'_>,
    ty: ScalarType,
    current: Value,
    finish: Value,
    inclusive: bool,
    dir: StepDirection,
) -> Value {
    let op = match (dir, inclusive) {
        (StepDirection::Asc, false) => CompareOp::Lt,
        (StepDirection::Asc, true) => CompareOp::Le,
        (StepDirection::Desc, false) => CompareOp::Gt,
        (StepDirection::Desc, true) => CompareOp::Ge,
    };
    lower_compare_values_raw(b, ty, current, finish, op)
}

fn lower_for_range_condition(
    b: &mut FunctionBuilder<'_>,
    ty: ScalarType,
    current: Value,
    finish: Value,
    step: Value,
    inclusive: bool,
) -> Result<Value, JitError> {
    let asc_op = if inclusive { CompareOp::Le } else { CompareOp::Lt };
    let desc_op = if inclusive { CompareOp::Ge } else { CompareOp::Gt };

    if ty.is_signed_integer() || ty.is_float() {
        let zero = lower_const(b, ty, 0)?;
        let step_nonneg = lower_compare_values_raw(b, ty, step, zero, CompareOp::Ge);
        let asc_cond = lower_compare_values_raw(b, ty, current, finish, asc_op);
        let desc_cond = lower_compare_values_raw(b, ty, current, finish, desc_op);
        return Ok(b.ins().select(step_nonneg, asc_cond, desc_cond));
    }

    Ok(lower_compare_values_raw(b, ty, current, finish, asc_op))
}

fn lower_stmts(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    stmts: &[Stmt],
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<LoopTargets>,
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
    loop_stack: &mut Vec<LoopTargets>,
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
            loop_stack.push(LoopTargets {
                continue_block: head,
                exit,
            });
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
        Stmt::LoopWhile { vars, cond, body, next } => {
            if vars.len() != next.len() {
                return Err(JitError("loop-while state and next arity mismatch".to_string()));
            }
            if body.iter().any(stmt_contains_break) || body.iter().any(stmt_contains_continue) {
                return Err(JitError(
                    "loop-while lowering does not support break/continue in canonical loop bodies"
                        .to_string(),
                ));
            }

            let mut init_vals = Vec::with_capacity(vars.len());
            for var in vars {
                init_vals.push(lower_expr(module, b, &var.init, lower, next_var_index, loop_stack)?);
            }

            let head = b.create_block();
            let loop_body = b.create_block();
            let exit = b.create_block();
            for var in vars {
                b.append_block_param(head, var.ty.abi_type());
                b.append_block_param(loop_body, var.ty.abi_type());
                b.append_block_param(exit, var.ty.abi_type());
            }

            let head_args = init_vals;
            let head_block_args: Vec<ir::BlockArg> = head_args.iter().copied().map(Into::into).collect();
            b.ins().jump(head, &head_block_args);
            b.switch_to_block(head);

            let head_params = b.block_params(head).to_vec();
            let mut head_ctx = lower.clone();
            for (var, value) in vars.iter().zip(head_params.iter().copied()) {
                head_ctx.bindings.insert(var.name.clone(), Binding::Value(value));
            }
            let cond_val = lower_condition(module, b, cond, &mut head_ctx, next_var_index, loop_stack)?;
            let body_args: Vec<ir::BlockArg> = head_params.iter().copied().map(Into::into).collect();
            let exit_args: Vec<ir::BlockArg> = head_params.iter().copied().map(Into::into).collect();
            b.ins().brif(cond_val, loop_body, &body_args, exit, &exit_args);
            b.seal_block(loop_body);
            b.seal_block(exit);

            b.switch_to_block(loop_body);
            let body_params = b.block_params(loop_body).to_vec();
            let mut body_ctx = lower.clone();
            for (var, value) in vars.iter().zip(body_params.iter().copied()) {
                body_ctx.bindings.insert(var.name.clone(), Binding::Value(value));
            }
            let terminated = lower_stmts(module, b, body, &mut body_ctx, next_var_index, loop_stack)?;
            if !terminated {
                let mut next_vals = Vec::with_capacity(next.len());
                for value in next {
                    next_vals.push(lower_expr(module, b, value, &mut body_ctx, next_var_index, loop_stack)?);
                }
                let next_args: Vec<ir::BlockArg> = next_vals.iter().copied().map(Into::into).collect();
                b.ins().jump(head, &next_args);
            }

            b.seal_block(head);
            b.switch_to_block(exit);
            let exit_params = b.block_params(exit).to_vec();
            for (var, value) in vars.iter().zip(exit_params.iter().copied()) {
                lower.bindings.insert(var.name.clone(), Binding::Value(value));
            }
            Ok(false)
        }
        Stmt::ForRange {
            name,
            ty,
            start,
            finish,
            step,
            dir,
            inclusive,
            scoped,
            body,
        } => {
            let start_val = lower_expr(module, b, start, lower, next_var_index, loop_stack)?;
            let finish_val = lower_expr(module, b, finish, lower, next_var_index, loop_stack)?;
            let step_val = lower_expr(module, b, step, lower, next_var_index, loop_stack)?;
            let known_dir = effective_step_direction(*ty, step, *dir);

            let saved_binding = lower.bindings.get(name).copied();
            let loop_var = if *scoped {
                let var = declare_var(b, next_var_index, *ty);
                b.def_var(var, start_val);
                var
            } else {
                match saved_binding {
                    Some(Binding::Var(var)) => {
                        b.def_var(var, start_val);
                        var
                    }
                    Some(Binding::Value(_)) => {
                        return Err(JitError(format!(
                            "Moonlift binding '{}' is immutable and cannot be used as a for-range variable",
                            name
                        )))
                    }
                    None => {
                        return Err(JitError(format!(
                            "unknown Moonlift variable '{}' for for-range loop",
                            name
                        )))
                    }
                }
            };

            let head = b.create_block();
            let loop_body = b.create_block();
            let step_block = b.create_block();
            let exit = b.create_block();

            b.ins().jump(head, &[]);
            b.switch_to_block(head);
            let current = b.use_var(loop_var);
            let cond_val = if let Some(dir) = known_dir {
                lower_for_range_condition_with_direction(b, *ty, current, finish_val, *inclusive, dir)
            } else {
                lower_for_range_condition(b, *ty, current, finish_val, step_val, *inclusive)?
            };
            b.ins().brif(cond_val, loop_body, &[], exit, &[]);

            b.switch_to_block(loop_body);
            let mut body_ctx = lower.clone();
            body_ctx.bindings.insert(name.clone(), Binding::Var(loop_var));
            loop_stack.push(LoopTargets {
                continue_block: step_block,
                exit,
            });
            let terminated = lower_stmts(module, b, body, &mut body_ctx, next_var_index, loop_stack)?;
            loop_stack.pop();
            if !terminated {
                b.ins().jump(step_block, &[]);
            }

            b.seal_block(step_block);
            b.switch_to_block(step_block);
            let current = b.use_var(loop_var);
            let next = match dir {
                Some(StepDirection::Desc) => lower_binary(b, BinaryOp::Sub, *ty, *ty, *ty, current, step_val)?,
                _ => lower_binary(b, BinaryOp::Add, *ty, *ty, *ty, current, step_val)?,
            };
            b.def_var(loop_var, next);
            if let Some(dir) = known_dir {
                let cond_val = lower_for_range_condition_with_direction(b, *ty, next, finish_val, *inclusive, dir);
                b.ins().brif(cond_val, loop_body, &[], exit, &[]);
            } else {
                b.ins().jump(head, &[]);
            }

            b.seal_block(head);
            b.seal_block(loop_body);
            b.seal_block(exit);
            b.switch_to_block(exit);
            if *scoped {
                if let Some(binding) = saved_binding {
                    lower.bindings.insert(name.clone(), binding);
                } else {
                    lower.bindings.remove(name);
                }
            }
            Ok(false)
        }
        Stmt::If {
            cond,
            then_body,
            else_body,
        } => {
            let cond_val = lower_condition(module, b, cond, lower, next_var_index, loop_stack)?;
            let then_block = b.create_block();
            let else_block = b.create_block();
            let merge_block = b.create_block();

            b.ins().brif(cond_val, then_block, &[], else_block, &[]);
            b.seal_block(then_block);
            b.seal_block(else_block);

            b.switch_to_block(then_block);
            let mut then_ctx = lower.clone();
            let then_terminated = lower_stmts(module, b, then_body, &mut then_ctx, next_var_index, loop_stack)?;
            if !then_terminated {
                b.ins().jump(merge_block, &[]);
            }

            b.switch_to_block(else_block);
            let mut else_ctx = lower.clone();
            let else_terminated = lower_stmts(module, b, else_body, &mut else_ctx, next_var_index, loop_stack)?;
            if !else_terminated {
                b.ins().jump(merge_block, &[]);
            }

            if then_terminated && else_terminated {
                Ok(true)
            } else {
                b.seal_block(merge_block);
                b.switch_to_block(merge_block);
                Ok(false)
            }
        }
        Stmt::Store { ty: _, addr, value } => {
            let (addr_val, offset) = lower_memory_addr(module, b, addr, lower, next_var_index, loop_stack)?;
            let val = lower_expr(module, b, value, lower, next_var_index, loop_stack)?;
            b.ins().store(MemFlags::trusted(), val, addr_val, offset);
            Ok(false)
        }
        Stmt::BoundsCheck { index, limit } => {
            lower_bounds_check(module, b, index, limit, lower, next_var_index, loop_stack)?;
            Ok(false)
        }
        Stmt::Assert { cond } => {
            let cond_val = lower_condition(module, b, cond, lower, next_var_index, loop_stack)?;
            b.ins().trapz(cond_val, ir::TrapCode::unwrap_user(2));
            Ok(false)
        }
        Stmt::StackSlot { name, size, align } => {
            if lower.stack_slots.contains_key(name) {
                return Err(JitError(format!("duplicate Moonlift stack slot '{}'", name)));
            }
            let slot = b.create_sized_stack_slot(StackSlotData::new(
                StackSlotKind::ExplicitSlot,
                *size,
                align_shift(*align),
            ));
            lower.stack_slots.insert(name.clone(), slot);
            Ok(false)
        }
        Stmt::Memcpy { dst, src, len } => {
            let dst_val = lower_expr(module, b, dst, lower, next_var_index, loop_stack)?;
            let src_val = lower_expr(module, b, src, lower, next_var_index, loop_stack)?;
            let len_val = lower_expr(module, b, len, lower, next_var_index, loop_stack)?;
            let _ = lower_runtime_memcpy(module, b, dst_val, src_val, len_val, "moonlift_rt_memcpy")?;
            Ok(false)
        }
        Stmt::Memmove { dst, src, len } => {
            let dst_val = lower_expr(module, b, dst, lower, next_var_index, loop_stack)?;
            let src_val = lower_expr(module, b, src, lower, next_var_index, loop_stack)?;
            let len_val = lower_expr(module, b, len, lower, next_var_index, loop_stack)?;
            let _ = lower_runtime_memcpy(module, b, dst_val, src_val, len_val, "moonlift_rt_memmove")?;
            Ok(false)
        }
        Stmt::Memset { dst, byte, len } => {
            let dst_val = lower_expr(module, b, dst, lower, next_var_index, loop_stack)?;
            let byte_val = lower_expr(module, b, byte, lower, next_var_index, loop_stack)?;
            let len_val = lower_expr(module, b, len, lower, next_var_index, loop_stack)?;
            lower_runtime_memset(module, b, dst_val, byte_val, len_val)?;
            Ok(false)
        }
        Stmt::Call { target, args } => {
            lower_call_stmt(module, b, target, args, lower, next_var_index, loop_stack)?;
            Ok(false)
        }
        Stmt::Break => {
            let targets = loop_stack
                .last()
                .copied()
                .ok_or_else(|| JitError("break used outside of a loop".to_string()))?;
            b.ins().jump(targets.exit, &[]);
            Ok(true)
        }
        Stmt::Continue => {
            let targets = loop_stack
                .last()
                .copied()
                .ok_or_else(|| JitError("continue used outside of a loop".to_string()))?;
            b.ins().jump(targets.continue_block, &[]);
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
    loop_stack: &mut Vec<LoopTargets>,
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
            let terminated = lower_stmts(module, b, stmts, &mut child, next_var_index, loop_stack)?;
            if terminated {
                return Err(JitError(
                    "Moonlift expression block terminated via break/continue before producing a value"
                        .to_string(),
                ));
            }
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
            let (addr_val, offset) = lower_memory_addr(module, b, addr, lower, next_var_index, loop_stack)?;
            Ok(b.ins().load(ty.abi_type(), MemFlags::trusted(), addr_val, offset))
        }
        Expr::IndexAddr {
            base,
            index,
            elem_size,
            limit,
        } => lower_index_addr_value(module, b, base, index, *elem_size, limit.as_deref(), lower, next_var_index, loop_stack),
        Expr::StackAddr { name } => {
            let slot = lower
                .stack_slots
                .get(name)
                .copied()
                .ok_or_else(|| JitError(format!("unknown Moonlift stack slot '{}'", name)))?;
            Ok(b.ins().stack_addr(types::I64, slot, 0))
        }
        Expr::Memcmp { a, b: rhs, len } => {
            let a_val = lower_expr(module, b, a, lower, next_var_index, loop_stack)?;
            let b_val = lower_expr(module, b, rhs, lower, next_var_index, loop_stack)?;
            let len_val = lower_expr(module, b, len, lower, next_var_index, loop_stack)?;
            match lower_runtime_memcpy(module, b, a_val, b_val, len_val, "moonlift_rt_memcmp")? {
                Some(v) => Ok(v),
                None => Err(JitError("moonlift internal error lowering memcmp".to_string())),
            }
        }
        Expr::Cast { op, ty, value } => {
            let v = lower_expr(module, b, value, lower, next_var_index, loop_stack)?;
            lower_cast(b, *op, value.ty(), *ty, v)
        }
        Expr::Call { target, args, .. } => lower_call_value(module, b, target, args, lower, next_var_index, loop_stack),
        Expr::Select { cond, then_expr, else_expr, .. } => {
            let cond_val = lower_condition(module, b, cond, lower, next_var_index, loop_stack)?;
            let then_val = lower_expr(module, b, then_expr, lower, next_var_index, loop_stack)?;
            let else_val = lower_expr(module, b, else_expr, lower, next_var_index, loop_stack)?;
            Ok(b.ins().select(cond_val, then_val, else_val))
        }
    }
}

fn lower_memory_addr(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    expr: &Expr,
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<LoopTargets>,
) -> Result<(Value, i32), JitError> {
    match expr {
        Expr::IndexAddr {
            base,
            index,
            elem_size,
            limit,
        } => lower_index_addr_parts(module, b, base, index, *elem_size, limit.as_deref(), lower, next_var_index, loop_stack),
        Expr::Binary {
            op: BinaryOp::Add,
            ty: ScalarType::Ptr,
            lhs,
            rhs,
        } => {
            if let Expr::Const {
                ty: ScalarType::I64 | ScalarType::U64 | ScalarType::Ptr,
                bits,
            } = rhs.as_ref()
            {
                if let Ok(offset) = i32::try_from(*bits as i64) {
                    let base = lower_expr(module, b, lhs, lower, next_var_index, loop_stack)?;
                    return Ok((base, offset));
                }
            }
            let addr = lower_expr(module, b, expr, lower, next_var_index, loop_stack)?;
            Ok((addr, 0))
        }
        _ => {
            let addr = lower_expr(module, b, expr, lower, next_var_index, loop_stack)?;
            Ok((addr, 0))
        }
    }
}

fn lower_index_addr_parts(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    base: &Expr,
    index: &Expr,
    elem_size: u32,
    limit: Option<&Expr>,
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<LoopTargets>,
) -> Result<(Value, i32), JitError> {
    if let Some(limit_expr) = limit {
        lower_bounds_check(module, b, index, limit_expr, lower, next_var_index, loop_stack)?;
    }

    let base_val = lower_expr(module, b, base, lower, next_var_index, loop_stack)?;
    let mut offset_bytes: i64 = 0;
    let mut dynamic_index = index;

    match index {
        Expr::Binary {
            op: BinaryOp::Add,
            ty,
            lhs,
            rhs,
        } if !ty.is_float() => {
            if let Expr::Const { ty: cty, bits } = rhs.as_ref() {
                if *cty == *ty {
                    dynamic_index = lhs;
                    offset_bytes = ((*bits as i64) as i128 * elem_size as i128) as i64;
                }
            } else if let Expr::Const { ty: cty, bits } = lhs.as_ref() {
                if *cty == *ty {
                    dynamic_index = rhs;
                    offset_bytes = ((*bits as i64) as i128 * elem_size as i128) as i64;
                }
            }
        }
        Expr::Binary {
            op: BinaryOp::Sub,
            ty,
            lhs,
            rhs,
        } if !ty.is_float() => {
            if let Expr::Const { ty: cty, bits } = rhs.as_ref() {
                if *cty == *ty {
                    dynamic_index = lhs;
                    offset_bytes = (-(*bits as i64) as i128 * elem_size as i128) as i64;
                }
            }
        }
        _ => {}
    }

    let index_val = lower_expr(module, b, dynamic_index, lower, next_var_index, loop_stack)?;
    let elem_size_val = b.ins().iconst(types::I64, elem_size as i64);
    let scaled = if elem_size == 1 {
        coerce_value(b, index_val, dynamic_index.ty(), ScalarType::I64)?
    } else {
        let widened = coerce_value(b, index_val, dynamic_index.ty(), ScalarType::I64)?;
        b.ins().imul(widened, elem_size_val)
    };
    let addr = b.ins().iadd(base_val, scaled);
    if let Ok(offset) = i32::try_from(offset_bytes) {
        Ok((addr, offset))
    } else {
        let final_addr = b.ins().iadd_imm(addr, offset_bytes);
        Ok((final_addr, 0))
    }
}

fn lower_index_addr_value(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    base: &Expr,
    index: &Expr,
    elem_size: u32,
    limit: Option<&Expr>,
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<LoopTargets>,
) -> Result<Value, JitError> {
    let (addr, offset) = lower_index_addr_parts(module, b, base, index, elem_size, limit, lower, next_var_index, loop_stack)?;
    if offset == 0 {
        Ok(addr)
    } else {
        Ok(b.ins().iadd_imm(addr, offset as i64))
    }
}

fn bounds_check_const_safe(index: &Expr, limit: &Expr) -> Option<bool> {
    let index_bits = const_index_bits(index)?;
    let limit_bits = const_index_bits(limit)?;
    Some(index_bits < limit_bits)
}

fn const_index_bits(expr: &Expr) -> Option<u128> {
    match expr {
        Expr::Const { ty, bits } if !ty.is_float() && !ty.is_void() => {
            let width = ty.abi_type().bits() as u32;
            let widened = if ty.is_signed_integer() {
                sign_extend(*bits, width) as i128 as u128
            } else {
                *bits as u128
            };
            Some(if width >= 128 { widened } else { widened & ((1u128 << width) - 1) })
        }
        _ => None,
    }
}

fn lower_bounds_check(
    module: &mut JITModule,
    b: &mut FunctionBuilder<'_>,
    index: &Expr,
    limit: &Expr,
    lower: &mut LowerCtx,
    next_var_index: &mut u32,
    loop_stack: &mut Vec<LoopTargets>,
) -> Result<(), JitError> {
    if bounds_check_const_safe(index, limit) == Some(true) {
        return Ok(());
    }
    let index_val = lower_expr(module, b, index, lower, next_var_index, loop_stack)?;
    let limit_val = lower_expr(module, b, limit, lower, next_var_index, loop_stack)?;
    let cmp_ty = common_unsigned_index_type(index.ty(), limit.ty())?;
    let lhs = coerce_value(b, index_val, index.ty(), cmp_ty)?;
    let rhs = coerce_value(b, limit_val, limit.ty(), cmp_ty)?;
    let ok = lower_compare_raw(b, cmp_ty, lhs, rhs, &CompareOp::Lt);
    b.ins().trapz(ok, ir::TrapCode::HEAP_OUT_OF_BOUNDS);
    Ok(())
}

fn common_unsigned_index_type(lhs: ScalarType, rhs: ScalarType) -> Result<ScalarType, JitError> {
    if lhs.is_float() || rhs.is_float() || lhs.is_void() || rhs.is_void() {
        return Err(JitError("Moonlift bounds checks require integer index and limit expressions".to_string()));
    }
    let bits = lhs.abi_type().bits().max(rhs.abi_type().bits());
    Ok(match bits {
        8 => ScalarType::U8,
        16 => ScalarType::U16,
        32 => ScalarType::U32,
        _ => ScalarType::U64,
    })
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
                let is_zero = b.ins().icmp_imm(IntCC::Equal, value, 0);
                Ok(lower_bool_value_from_cond(b, is_zero))
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
                let lhs = lower_bool_cond_from_value(b, lhs);
                let rhs = lower_bool_cond_from_value(b, rhs);
                let both = b.ins().band(lhs, rhs);
                Ok(lower_bool_value_from_cond(b, both))
            } else {
                Err(JitError("logical and is only valid for bool".to_string()))
            }
        }
        BinaryOp::Or => {
            if ty.is_bool() {
                let lhs = lower_bool_cond_from_value(b, lhs);
                let rhs = lower_bool_cond_from_value(b, rhs);
                let either = b.ins().bor(lhs, rhs);
                Ok(lower_bool_value_from_cond(b, either))
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

fn lower_compare_raw(
    b: &mut FunctionBuilder<'_>,
    operand_ty: ScalarType,
    lhs: Value,
    rhs: Value,
    op: &CompareOp,
) -> Value {
    if operand_ty.is_float() {
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
    }
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
    let cmp = lower_compare_raw(b, operand_ty, lhs, rhs, &op);
    Ok(lower_bool_value_from_cond(b, cmp))
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
