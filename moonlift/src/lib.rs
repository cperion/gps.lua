use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::immediates::{Ieee32, Ieee64};
use cranelift_codegen::ir::{
    AbiParam, Block, BlockArg, InstBuilder, MemFlags, Signature, StackSlot, StackSlotData,
    StackSlotKind, TrapCode, Type, UserFuncName, Value, types,
};
use cranelift_codegen::settings::{self, Configurable};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Switch};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{DataDescription, DataId, FuncId, Linkage, Module, default_libcall_names};
use std::collections::{HashMap, HashSet};
use std::error::Error;
use std::ffi::c_void;
use std::fmt;

mod ffi;

macro_rules! id_type {
    ($name:ident) => {
        #[derive(Clone, Debug, PartialEq, Eq, Hash)]
        pub struct $name(pub String);

        impl $name {
            pub fn new(text: impl Into<String>) -> Self {
                Self(text.into())
            }

            pub fn as_str(&self) -> &str {
                &self.0
            }
        }

        impl From<&str> for $name {
            fn from(value: &str) -> Self {
                Self(value.to_string())
            }
        }

        impl From<String> for $name {
            fn from(value: String) -> Self {
                Self(value)
            }
        }
    };
}

id_type!(BackSigId);
id_type!(BackFuncId);
id_type!(BackExternId);
id_type!(BackDataId);
id_type!(BackBlockId);
id_type!(BackValId);
id_type!(BackStackSlotId);

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackSwitchCase {
    pub raw: String,
    pub dest: BackBlockId,
}

impl BackSwitchCase {
    pub fn new(raw: impl Into<String>, dest: BackBlockId) -> Self {
        Self {
            raw: raw.into(),
            dest,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BackScalar {
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
    Index,
}

impl BackScalar {
    fn clif_type(self, ptr_ty: Type) -> Type {
        match self {
            Self::Bool => types::I8,
            Self::I8 | Self::U8 => types::I8,
            Self::I16 | Self::U16 => types::I16,
            Self::I32 | Self::U32 => types::I32,
            Self::I64 | Self::U64 => types::I64,
            Self::F32 => types::F32,
            Self::F64 => types::F64,
            Self::Ptr | Self::Index => ptr_ty,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BackCmd {
    CreateSig(BackSigId, Vec<BackScalar>, Vec<BackScalar>),
    DeclareData(BackDataId, u32, u32),
    DataInitZero(BackDataId, u32, u32),
    DataInitInt(BackDataId, u32, BackScalar, String),
    DataInitFloat(BackDataId, u32, BackScalar, String),
    DataInitBool(BackDataId, u32, bool),
    DataAddr(BackValId, BackDataId),
    DeclareFuncLocal(BackFuncId, BackSigId),
    DeclareFuncExport(BackFuncId, BackSigId),
    DeclareFuncExtern(BackExternId, String, BackSigId),
    BeginFunc(BackFuncId),
    CreateBlock(BackBlockId),
    SwitchToBlock(BackBlockId),
    SealBlock(BackBlockId),
    BindEntryParams(BackBlockId, Vec<BackValId>),
    AppendBlockParam(BackBlockId, BackValId, BackScalar),
    CreateStackSlot(BackStackSlotId, u32, u32),
    Alias(BackValId, BackValId),
    StackAddr(BackValId, BackStackSlotId),
    ConstInt(BackValId, BackScalar, String),
    ConstFloat(BackValId, BackScalar, String),
    ConstBool(BackValId, bool),
    ConstNull(BackValId),
    Ineg(BackValId, BackScalar, BackValId),
    Fneg(BackValId, BackScalar, BackValId),
    Bnot(BackValId, BackScalar, BackValId),
    BoolNot(BackValId, BackValId),
    Popcount(BackValId, BackScalar, BackValId),
    Clz(BackValId, BackScalar, BackValId),
    Ctz(BackValId, BackScalar, BackValId),
    Bswap(BackValId, BackScalar, BackValId),
    Sqrt(BackValId, BackScalar, BackValId),
    Abs(BackValId, BackScalar, BackValId),
    Floor(BackValId, BackScalar, BackValId),
    Ceil(BackValId, BackScalar, BackValId),
    TruncFloat(BackValId, BackScalar, BackValId),
    Round(BackValId, BackScalar, BackValId),
    Iadd(BackValId, BackScalar, BackValId, BackValId),
    Isub(BackValId, BackScalar, BackValId, BackValId),
    Imul(BackValId, BackScalar, BackValId, BackValId),
    Fadd(BackValId, BackScalar, BackValId, BackValId),
    Fsub(BackValId, BackScalar, BackValId, BackValId),
    Fmul(BackValId, BackScalar, BackValId, BackValId),
    Sdiv(BackValId, BackScalar, BackValId, BackValId),
    Udiv(BackValId, BackScalar, BackValId, BackValId),
    Fdiv(BackValId, BackScalar, BackValId, BackValId),
    Srem(BackValId, BackScalar, BackValId, BackValId),
    Urem(BackValId, BackScalar, BackValId, BackValId),
    Frem(BackValId, BackScalar, BackValId, BackValId),
    Band(BackValId, BackScalar, BackValId, BackValId),
    Bor(BackValId, BackScalar, BackValId, BackValId),
    Bxor(BackValId, BackScalar, BackValId, BackValId),
    Ishl(BackValId, BackScalar, BackValId, BackValId),
    Ushr(BackValId, BackScalar, BackValId, BackValId),
    Sshr(BackValId, BackScalar, BackValId, BackValId),
    Rotl(BackValId, BackScalar, BackValId, BackValId),
    Rotr(BackValId, BackScalar, BackValId, BackValId),
    IcmpEq(BackValId, BackScalar, BackValId, BackValId),
    IcmpNe(BackValId, BackScalar, BackValId, BackValId),
    SIcmpLt(BackValId, BackScalar, BackValId, BackValId),
    SIcmpLe(BackValId, BackScalar, BackValId, BackValId),
    SIcmpGt(BackValId, BackScalar, BackValId, BackValId),
    SIcmpGe(BackValId, BackScalar, BackValId, BackValId),
    UIcmpLt(BackValId, BackScalar, BackValId, BackValId),
    UIcmpLe(BackValId, BackScalar, BackValId, BackValId),
    UIcmpGt(BackValId, BackScalar, BackValId, BackValId),
    UIcmpGe(BackValId, BackScalar, BackValId, BackValId),
    FCmpEq(BackValId, BackScalar, BackValId, BackValId),
    FCmpNe(BackValId, BackScalar, BackValId, BackValId),
    FCmpLt(BackValId, BackScalar, BackValId, BackValId),
    FCmpLe(BackValId, BackScalar, BackValId, BackValId),
    FCmpGt(BackValId, BackScalar, BackValId, BackValId),
    FCmpGe(BackValId, BackScalar, BackValId, BackValId),
    Bitcast(BackValId, BackScalar, BackValId),
    Ireduce(BackValId, BackScalar, BackValId),
    Sextend(BackValId, BackScalar, BackValId),
    Uextend(BackValId, BackScalar, BackValId),
    Fpromote(BackValId, BackScalar, BackValId),
    Fdemote(BackValId, BackScalar, BackValId),
    SToF(BackValId, BackScalar, BackValId),
    UToF(BackValId, BackScalar, BackValId),
    FToS(BackValId, BackScalar, BackValId),
    FToU(BackValId, BackScalar, BackValId),
    Load(BackValId, BackScalar, BackValId),
    Store(BackScalar, BackValId, BackValId),
    Select(BackValId, BackScalar, BackValId, BackValId, BackValId),
    Fma(BackValId, BackScalar, BackValId, BackValId, BackValId),
    CallValueDirect(BackValId, BackScalar, BackFuncId, BackSigId, Vec<BackValId>),
    CallStmtDirect(BackFuncId, BackSigId, Vec<BackValId>),
    CallValueExtern(BackValId, BackScalar, BackExternId, BackSigId, Vec<BackValId>),
    CallStmtExtern(BackExternId, BackSigId, Vec<BackValId>),
    CallValueIndirect(BackValId, BackScalar, BackValId, BackSigId, Vec<BackValId>),
    CallStmtIndirect(BackValId, BackSigId, Vec<BackValId>),
    Jump(BackBlockId, Vec<BackValId>),
    BrIf(BackValId, BackBlockId, Vec<BackValId>, BackBlockId, Vec<BackValId>),
    SwitchInt(BackValId, BackScalar, Vec<BackSwitchCase>, BackBlockId),
    ReturnVoid,
    ReturnValue(BackValId),
    Trap,
    FinishFunc(BackFuncId),
    FinalizeModule,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackProgram {
    pub cmds: Vec<BackCmd>,
}

impl BackProgram {
    pub fn new(cmds: Vec<BackCmd>) -> Self {
        Self { cmds }
    }
}

#[derive(Debug)]
pub struct MoonliftError(pub String);

impl MoonliftError {
    fn new(message: impl Into<String>) -> Self {
        Self(message.into())
    }
}

impl fmt::Display for MoonliftError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl Error for MoonliftError {}

fn switch_int_bits(ty: BackScalar, ptr_ty: Type) -> Result<u8, MoonliftError> {
    match ty {
        BackScalar::Bool | BackScalar::I8 | BackScalar::U8 => Ok(8),
        BackScalar::I16 | BackScalar::U16 => Ok(16),
        BackScalar::I32 | BackScalar::U32 => Ok(32),
        BackScalar::I64 | BackScalar::U64 => Ok(64),
        BackScalar::Index => Ok(ptr_ty.bits() as u8),
        _ => Err(MoonliftError::new(format!(
            "BackCmdSwitchInt requires bool/integer/index type, got {:?}",
            ty
        ))),
    }
}

fn mask_to_bits(value: u128, bits: u8) -> u128 {
    if bits >= 128 {
        value
    } else {
        value & ((1u128 << bits) - 1)
    }
}

fn parse_switch_int_case(raw: &str, ty: BackScalar, ptr_ty: Type) -> Result<u128, MoonliftError> {
    let bits = switch_int_bits(ty, ptr_ty)?;
    match ty {
        BackScalar::Bool => match raw {
            "0" => Ok(0),
            "1" => Ok(1),
            _ => Err(MoonliftError::new(format!(
                "BackCmdSwitchInt bool case must be '0' or '1', got '{}'",
                raw
            ))),
        },
        BackScalar::I8 | BackScalar::I16 | BackScalar::I32 | BackScalar::I64 => {
            let value = raw.parse::<i128>().map_err(|e| {
                MoonliftError::new(format!("could not parse signed switch case '{}': {}", raw, e))
            })?;
            Ok(mask_to_bits(value as u128, bits))
        }
        BackScalar::U8 | BackScalar::U16 | BackScalar::U32 | BackScalar::U64 | BackScalar::Index => {
            let value = raw.parse::<u128>().map_err(|e| {
                MoonliftError::new(format!("could not parse unsigned switch case '{}': {}", raw, e))
            })?;
            Ok(mask_to_bits(value, bits))
        }
        _ => Err(MoonliftError::new(format!(
            "BackCmdSwitchInt requires bool/integer/index type, got {:?}",
            ty
        ))),
    }
}

pub struct Jit {
    symbols: HashMap<String, *const u8>,
}

impl Jit {
    pub fn new() -> Self {
        Self {
            symbols: HashMap::new(),
        }
    }

    pub fn symbol(&mut self, name: impl Into<String>, ptr: *const u8) {
        self.symbols.insert(name.into(), ptr);
    }

    pub fn compile(&self, program: &BackProgram) -> Result<Artifact, MoonliftError> {
        let mut compiler = Compiler::new(&self.symbols)?;
        compiler.compile(program)
    }
}

impl Default for Jit {
    fn default() -> Self {
        Self::new()
    }
}

pub struct Artifact {
    _module: JITModule,
    function_ptrs: HashMap<BackFuncId, *const u8>,
}

impl Artifact {
    pub fn getpointer(&self, func: &BackFuncId) -> Result<*const c_void, MoonliftError> {
        let ptr = self
            .function_ptrs
            .get(func)
            .copied()
            .ok_or_else(|| MoonliftError::new(format!("unknown compiled function id '{}'", func.as_str())))?;
        Ok(ptr.cast())
    }

    pub fn getpointer_by_name(&self, func: &str) -> Result<*const c_void, MoonliftError> {
        self.getpointer(&BackFuncId::from(func))
    }

    pub fn free(self) {}

    pub fn contains_function(&self, func: &BackFuncId) -> bool {
        self.function_ptrs.contains_key(func)
    }

    pub fn function_ids(&self) -> impl Iterator<Item = &BackFuncId> {
        self.function_ptrs.keys()
    }
}

#[derive(Clone)]
struct FuncDecl {
    sig: BackSigId,
    linkage: Linkage,
    symbol: String,
    func_id: Option<FuncId>,
}

#[derive(Clone)]
struct ExternDecl {
    sig: BackSigId,
    symbol: String,
    func_id: Option<FuncId>,
}

#[derive(Clone)]
enum DataInit {
    Zero { offset: u32, size: u32 },
    Int { offset: u32, ty: BackScalar, raw: String },
    Float { offset: u32, ty: BackScalar, raw: String },
    Bool { offset: u32, value: bool },
}

#[derive(Clone)]
struct DataDecl {
    symbol: String,
    size: u32,
    align: u32,
    inits: Vec<DataInit>,
    data_id: Option<DataId>,
}

struct Compiler {
    module: JITModule,
    signatures: HashMap<BackSigId, Signature>,
    funcs: HashMap<BackFuncId, FuncDecl>,
    externs: HashMap<BackExternId, ExternDecl>,
    datas: HashMap<BackDataId, DataDecl>,
    bodies: Vec<(BackFuncId, Vec<BackCmd>)>,
}

impl Compiler {
    fn new(symbols: &HashMap<String, *const u8>) -> Result<Self, MoonliftError> {
        let mut flag_builder = settings::builder();
        flag_builder
            .set("use_colocated_libcalls", "false")
            .map_err(|e| MoonliftError::new(format!("failed to set Cranelift flag use_colocated_libcalls: {e}")))?;
        flag_builder
            .set("is_pic", "false")
            .map_err(|e| MoonliftError::new(format!("failed to set Cranelift flag is_pic: {e}")))?;
        flag_builder
            .set("opt_level", "speed")
            .map_err(|e| MoonliftError::new(format!("failed to set Cranelift flag opt_level: {e}")))?;

        let isa_builder = cranelift_native::builder()
            .map_err(|e| MoonliftError::new(format!("host machine is not supported by Cranelift: {e}")))?;
        let isa = isa_builder
            .finish(settings::Flags::new(flag_builder))
            .map_err(|e| MoonliftError::new(format!("failed to finalize Cranelift ISA: {e}")))?;

        let mut builder = JITBuilder::with_isa(isa, default_libcall_names());
        for (name, ptr) in symbols {
            builder.symbol(name, *ptr);
        }

        Ok(Self {
            module: JITModule::new(builder),
            signatures: HashMap::new(),
            funcs: HashMap::new(),
            externs: HashMap::new(),
            datas: HashMap::new(),
            bodies: Vec::new(),
        })
    }

    fn compile(&mut self, program: &BackProgram) -> Result<Artifact, MoonliftError> {
        self.collect(program)?;
        self.declare_all()?;
        self.define_all()?;
        self.module
            .finalize_definitions()
            .map_err(|e| MoonliftError::new(format!("failed to finalize Moonlift artifact: {e}")))?;

        let mut function_ptrs = HashMap::new();
        for (id, decl) in &self.funcs {
            let func_id = decl
                .func_id
                .ok_or_else(|| MoonliftError::new(format!("internal error: missing finalized FuncId for '{}'", id.as_str())))?;
            let ptr = self.module.get_finalized_function(func_id);
            function_ptrs.insert(id.clone(), ptr);
        }

        Ok(Artifact {
            _module: std::mem::replace(&mut self.module, empty_module()?),
            function_ptrs,
        })
    }

    fn collect(&mut self, program: &BackProgram) -> Result<(), MoonliftError> {
        let mut current_func: Option<BackFuncId> = None;
        let mut current_cmds: Vec<BackCmd> = Vec::new();

        for cmd in &program.cmds {
            self.collect_global_decl(cmd)?;
            match cmd {
                BackCmd::BeginFunc(func) => {
                    if current_func.is_some() {
                        return Err(MoonliftError::new(format!(
                            "nested BackCmdBeginFunc for '{}' is not allowed",
                            func.as_str()
                        )));
                    }
                    if self.bodies.iter().any(|(id, _)| id == func) {
                        return Err(MoonliftError::new(format!(
                            "duplicate BackCmdBeginFunc for '{}'",
                            func.as_str()
                        )));
                    }
                    current_func = Some(func.clone());
                    current_cmds.clear();
                }
                BackCmd::FinishFunc(func) => {
                    let open = current_func.take().ok_or_else(|| {
                        MoonliftError::new(format!(
                            "BackCmdFinishFunc('{}') appears outside any function body",
                            func.as_str()
                        ))
                    })?;
                    if &open != func {
                        return Err(MoonliftError::new(format!(
                            "BackCmdFinishFunc('{}') closes '{}', expected matching function id",
                            func.as_str(),
                            open.as_str()
                        )));
                    }
                    self.bodies.push((open, current_cmds.clone()));
                    current_cmds.clear();
                }
                other => {
                    if current_func.is_some() {
                        current_cmds.push(other.clone());
                    } else {
                        self.validate_top_level_cmd(other)?;
                    }
                }
            }
        }

        if let Some(func) = current_func {
            return Err(MoonliftError::new(format!(
                "unterminated function body for '{}'",
                func.as_str()
            )));
        }

        for (func, decl) in &self.funcs {
            if decl.linkage != Linkage::Import && !self.bodies.iter().any(|(id, _)| id == func) {
                return Err(MoonliftError::new(format!(
                    "declared function '{}' has no BackCmdBeginFunc/BackCmdFinishFunc body",
                    func.as_str()
                )));
            }
        }

        Ok(())
    }

    fn collect_global_decl(&mut self, cmd: &BackCmd) -> Result<(), MoonliftError> {
        match cmd {
            BackCmd::CreateSig(id, params, results) => {
                if results.len() > 1 {
                    return Err(MoonliftError::new(format!(
                        "signature '{}' currently has {} results; the direct function-pointer artifact API currently supports at most one result",
                        id.as_str(),
                        results.len()
                    )));
                }
                let sig = make_signature(&self.module, params, results);
                if let Some(existing) = self.signatures.get(id) {
                    if existing != &sig {
                        return Err(MoonliftError::new(format!(
                            "signature id '{}' was declared multiple times with different shapes",
                            id.as_str()
                        )));
                    }
                } else {
                    self.signatures.insert(id.clone(), sig);
                }
            }
            BackCmd::DeclareData(data, size, align) => {
                if *size == 0 {
                    return Err(MoonliftError::new(format!(
                        "data object '{}' must have size >= 1",
                        data.as_str()
                    )));
                }
                if *align == 0 || !align.is_power_of_two() {
                    return Err(MoonliftError::new(format!(
                        "data object '{}' alignment {} must be a non-zero power of two",
                        data.as_str(),
                        align
                    )));
                }
                match self.datas.get(data) {
                    Some(existing) => {
                        if existing.size != *size || existing.align != *align {
                            return Err(MoonliftError::new(format!(
                                "data id '{}' was declared multiple times with different size/alignment",
                                data.as_str()
                            )));
                        }
                    }
                    None => {
                        self.datas.insert(
                            data.clone(),
                            DataDecl {
                                symbol: local_data_symbol_name(data),
                                size: *size,
                                align: *align,
                                inits: Vec::new(),
                                data_id: None,
                            },
                        );
                    }
                }
            }
            BackCmd::DataInitZero(data, offset, size) => {
                let decl = self.datas.get_mut(data).ok_or_else(|| {
                    MoonliftError::new(format!("data init references unknown data '{}'", data.as_str()))
                })?;
                decl.inits.push(DataInit::Zero { offset: *offset, size: *size });
            }
            BackCmd::DataInitInt(data, offset, ty, raw) => {
                let decl = self.datas.get_mut(data).ok_or_else(|| {
                    MoonliftError::new(format!("data init references unknown data '{}'", data.as_str()))
                })?;
                decl.inits.push(DataInit::Int { offset: *offset, ty: *ty, raw: raw.clone() });
            }
            BackCmd::DataInitFloat(data, offset, ty, raw) => {
                let decl = self.datas.get_mut(data).ok_or_else(|| {
                    MoonliftError::new(format!("data init references unknown data '{}'", data.as_str()))
                })?;
                decl.inits.push(DataInit::Float { offset: *offset, ty: *ty, raw: raw.clone() });
            }
            BackCmd::DataInitBool(data, offset, value) => {
                let decl = self.datas.get_mut(data).ok_or_else(|| {
                    MoonliftError::new(format!("data init references unknown data '{}'", data.as_str()))
                })?;
                decl.inits.push(DataInit::Bool { offset: *offset, value: *value });
            }
            BackCmd::DeclareFuncLocal(func, sig) => {
                self.insert_func_decl(func, sig, Linkage::Local)?;
            }
            BackCmd::DeclareFuncExport(func, sig) => {
                self.insert_func_decl(func, sig, Linkage::Export)?;
            }
            BackCmd::DeclareFuncExtern(extern_id, symbol, sig) => {
                let spec = self
                    .signatures
                    .get(sig)
                    .ok_or_else(|| MoonliftError::new(format!(
                        "extern '{}' references unknown signature '{}'",
                        extern_id.as_str(),
                        sig.as_str()
                    )))?;
                if spec.returns.len() > 1 {
                    return Err(MoonliftError::new(format!(
                        "extern '{}' uses signature '{}' with {} results; multi-result extern ABIs are not yet supported by the raw pointer API",
                        extern_id.as_str(),
                        sig.as_str(),
                        spec.returns.len()
                    )));
                }
                match self.externs.get(extern_id) {
                    Some(existing) => {
                        if existing.sig != *sig || existing.symbol != *symbol {
                            return Err(MoonliftError::new(format!(
                                "extern id '{}' was declared multiple times with different symbol/signature data",
                                extern_id.as_str()
                            )));
                        }
                    }
                    None => {
                        self.externs.insert(
                            extern_id.clone(),
                            ExternDecl {
                                sig: sig.clone(),
                                symbol: symbol.clone(),
                                func_id: None,
                            },
                        );
                    }
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn insert_func_decl(&mut self, func: &BackFuncId, sig: &BackSigId, linkage: Linkage) -> Result<(), MoonliftError> {
        let spec = self.signatures.get(sig).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' references unknown signature '{}'",
                func.as_str(),
                sig.as_str()
            ))
        })?;
        if spec.returns.len() > 1 {
            return Err(MoonliftError::new(format!(
                "function '{}' uses signature '{}' with {} results; the direct function-pointer artifact API currently supports at most one result",
                func.as_str(),
                sig.as_str(),
                spec.returns.len()
            )));
        }
        let symbol = local_symbol_name(func);
        match self.funcs.get(func) {
            Some(existing) => {
                if existing.sig != *sig || existing.linkage != linkage {
                    return Err(MoonliftError::new(format!(
                        "function id '{}' was declared multiple times with different linkage/signature data",
                        func.as_str()
                    )));
                }
            }
            None => {
                self.funcs.insert(
                    func.clone(),
                    FuncDecl {
                        sig: sig.clone(),
                        linkage,
                        symbol,
                        func_id: None,
                    },
                );
            }
        }
        Ok(())
    }

    fn validate_top_level_cmd(&self, cmd: &BackCmd) -> Result<(), MoonliftError> {
        match cmd {
            BackCmd::CreateSig(..)
            | BackCmd::DeclareData(..)
            | BackCmd::DataInitZero(..)
            | BackCmd::DataInitInt(..)
            | BackCmd::DataInitFloat(..)
            | BackCmd::DataInitBool(..)
            | BackCmd::DeclareFuncLocal(..)
            | BackCmd::DeclareFuncExport(..)
            | BackCmd::DeclareFuncExtern(..)
            | BackCmd::FinalizeModule => Ok(()),
            BackCmd::FinishFunc(func) => Err(MoonliftError::new(format!(
                "BackCmdFinishFunc('{}') appears outside any function body",
                func.as_str()
            ))),
            BackCmd::BeginFunc(..) => Ok(()),
            other => Err(MoonliftError::new(format!(
                "command '{:?}' cannot appear at module top level; only declarations, BeginFunc/FinishFunc, and FinalizeModule are allowed outside a function body",
                other
            ))),
        }
    }

    fn declare_all(&mut self) -> Result<(), MoonliftError> {
        for decl in self.datas.values_mut() {
            let data_id = self
                .module
                .declare_data(&decl.symbol, Linkage::Local, false, false)
                .map_err(|e| MoonliftError::new(format!("failed to declare data object '{}': {e}", decl.symbol)))?;
            decl.data_id = Some(data_id);
        }

        for decl in self.externs.values_mut() {
            let sig = self.signatures.get(&decl.sig).ok_or_else(|| {
                MoonliftError::new(format!("missing signature '{}' for extern declaration", decl.sig.as_str()))
            })?;
            let func_id = self
                .module
                .declare_function(&decl.symbol, Linkage::Import, sig)
                .map_err(|e| MoonliftError::new(format!("failed to declare extern function '{}': {e}", decl.symbol)))?;
            decl.func_id = Some(func_id);
        }

        for decl in self.funcs.values_mut() {
            let sig = self.signatures.get(&decl.sig).ok_or_else(|| {
                MoonliftError::new(format!("missing signature '{}' for function declaration", decl.sig.as_str()))
            })?;
            let func_id = self
                .module
                .declare_function(&decl.symbol, decl.linkage, sig)
                .map_err(|e| MoonliftError::new(format!("failed to declare function '{}': {e}", decl.symbol)))?;
            decl.func_id = Some(func_id);
        }
        Ok(())
    }

    fn define_all(&mut self) -> Result<(), MoonliftError> {
        let ptr_ty = self.module.target_config().pointer_type();
        for (data_id_text, decl) in &self.datas {
            let data_id = decl.data_id.ok_or_else(|| {
                MoonliftError::new(format!("internal error: missing DataId for '{}'", data_id_text.as_str()))
            })?;
            let mut bytes = vec![0u8; decl.size as usize];
            for init in &decl.inits {
                write_data_init(&mut bytes, ptr_ty, init)?;
            }
            let mut data_desc = DataDescription::new();
            data_desc.define(bytes.into_boxed_slice());
            data_desc.set_align(decl.align as u64);
            self.module
                .define_data(data_id, &data_desc)
                .map_err(|e| MoonliftError::new(format!("failed to define data object '{}': {e:?}", data_id_text.as_str())))?;
        }

        let mut func_ctx = FunctionBuilderContext::new();

        for (func_id_text, cmds) in &self.bodies {
            let decl = self.funcs.get(func_id_text).ok_or_else(|| {
                MoonliftError::new(format!(
                    "function body '{}' has no matching DeclareFuncLocal/DeclareFuncExport",
                    func_id_text.as_str()
                ))
            })?;
            let func_id = decl.func_id.ok_or_else(|| {
                MoonliftError::new(format!("internal error: missing FuncId for '{}'", func_id_text.as_str()))
            })?;
            let sig = self.signatures.get(&decl.sig).ok_or_else(|| {
                MoonliftError::new(format!(
                    "internal error: missing signature '{}' for '{}'",
                    decl.sig.as_str(),
                    func_id_text.as_str()
                ))
            })?;

            let mut ctx = self.module.make_context();
            ctx.func.signature = sig.clone();
            ctx.func.name = UserFuncName::user(0, func_id.as_u32());

            {
                let mut builder = FunctionBuilder::new(&mut ctx.func, &mut func_ctx);
                {
                    let mut lower = FunctionLowerer::new(
                        &mut self.module,
                        &self.signatures,
                        &self.funcs,
                        &self.externs,
                        &self.datas,
                        ptr_ty,
                        func_id_text,
                        &mut builder,
                    );
                    lower.lower(cmds)?;
                }
                builder.seal_all_blocks();
                builder.finalize();
            }

            if std::env::var("MOONLIFT_DUMP_CLIF").ok().as_deref() == Some("1") {
                eprintln!("MOONLIFT_CLIF {}:\n{}", func_id_text.as_str(), ctx.func.display());
            }

            self.module
                .define_function(func_id, &mut ctx)
                .map_err(|e| MoonliftError::new(format!("failed to define function '{}': {e:?}", func_id_text.as_str())))?;
            self.module.clear_context(&mut ctx);
        }

        Ok(())
    }
}

struct FunctionLowerer<'a, 'b> {
    module: &'a mut JITModule,
    signatures: &'a HashMap<BackSigId, Signature>,
    funcs: &'a HashMap<BackFuncId, FuncDecl>,
    externs: &'a HashMap<BackExternId, ExternDecl>,
    datas: &'a HashMap<BackDataId, DataDecl>,
    ptr_ty: Type,
    func_name: &'a BackFuncId,
    builder: &'b mut FunctionBuilder<'a>,
    values: HashMap<BackValId, Value>,
    blocks: HashMap<BackBlockId, Block>,
    stack_slots: HashMap<BackStackSlotId, StackSlot>,
}

impl<'a, 'b> FunctionLowerer<'a, 'b> {
    fn new(
        module: &'a mut JITModule,
        signatures: &'a HashMap<BackSigId, Signature>,
        funcs: &'a HashMap<BackFuncId, FuncDecl>,
        externs: &'a HashMap<BackExternId, ExternDecl>,
        datas: &'a HashMap<BackDataId, DataDecl>,
        ptr_ty: Type,
        func_name: &'a BackFuncId,
        builder: &'b mut FunctionBuilder<'a>,
    ) -> Self {
        Self {
            module,
            signatures,
            funcs,
            externs,
            datas,
            ptr_ty,
            func_name,
            builder,
            values: HashMap::new(),
            blocks: HashMap::new(),
            stack_slots: HashMap::new(),
        }
    }

    fn lower(&mut self, cmds: &[BackCmd]) -> Result<(), MoonliftError> {
        for cmd in cmds {
            self.lower_cmd(cmd)?;
        }
        Ok(())
    }

    fn lower_cmd(&mut self, cmd: &BackCmd) -> Result<(), MoonliftError> {
        match cmd {
            BackCmd::CreateSig(id, params, results) => {
                let expected = self.signatures.get(id).ok_or_else(|| {
                    MoonliftError::new(format!(
                        "function '{}' references unknown signature '{}'",
                        self.func_name.as_str(),
                        id.as_str()
                    ))
                })?;
                let local = make_signature(self.module, params, results);
                if &local != expected {
                    return Err(MoonliftError::new(format!(
                        "function '{}' re-declared signature '{}' with a different shape",
                        self.func_name.as_str(),
                        id.as_str()
                    )));
                }
                Ok(())
            }
            BackCmd::DeclareData(data, size, align) => {
                let decl = self.datas.get(data).ok_or_else(|| {
                    MoonliftError::new(format!(
                        "function '{}' references undeclared data '{}': missing top-level declaration collection",
                        self.func_name.as_str(),
                        data.as_str()
                    ))
                })?;
                if decl.size != *size || decl.align != *align {
                    return Err(MoonliftError::new(format!(
                        "function '{}' re-declared data '{}' with different size/alignment",
                        self.func_name.as_str(),
                        data.as_str()
                    )));
                }
                Ok(())
            }
            BackCmd::DataInitZero(..)
            | BackCmd::DataInitInt(..)
            | BackCmd::DataInitFloat(..)
            | BackCmd::DataInitBool(..) => Err(MoonliftError::new(format!(
                "data initialization commands cannot appear inside function body '{}'",
                self.func_name.as_str()
            ))),
            BackCmd::DeclareFuncLocal(func, sig) | BackCmd::DeclareFuncExport(func, sig) => {
                let decl = self.funcs.get(func).ok_or_else(|| {
                    MoonliftError::new(format!(
                        "function '{}' references undeclared callee '{}': missing top-level declaration collection",
                        self.func_name.as_str(),
                        func.as_str()
                    ))
                })?;
                if decl.sig != *sig {
                    return Err(MoonliftError::new(format!(
                        "function '{}' re-declared '{}' with a different signature id",
                        self.func_name.as_str(),
                        func.as_str()
                    )));
                }
                Ok(())
            }
            BackCmd::DeclareFuncExtern(extern_id, symbol, sig) => {
                let decl = self.externs.get(extern_id).ok_or_else(|| {
                    MoonliftError::new(format!(
                        "function '{}' references undeclared extern '{}': missing top-level declaration collection",
                        self.func_name.as_str(),
                        extern_id.as_str()
                    ))
                })?;
                if decl.sig != *sig || decl.symbol != *symbol {
                    return Err(MoonliftError::new(format!(
                        "function '{}' re-declared extern '{}' with different symbol/signature data",
                        self.func_name.as_str(),
                        extern_id.as_str()
                    )));
                }
                Ok(())
            }
            BackCmd::BeginFunc(func) => Err(MoonliftError::new(format!(
                "nested BackCmdBeginFunc('{}') inside function '{}'",
                func.as_str(),
                self.func_name.as_str()
            ))),
            BackCmd::FinishFunc(func) => Err(MoonliftError::new(format!(
                "unexpected BackCmdFinishFunc('{}') inside function body '{}'",
                func.as_str(),
                self.func_name.as_str()
            ))),
            BackCmd::CreateBlock(id) => {
                let block = self.builder.create_block();
                if self.blocks.insert(id.clone(), block).is_some() {
                    return Err(MoonliftError::new(format!(
                        "function '{}' created block '{}' more than once",
                        self.func_name.as_str(),
                        id.as_str()
                    )));
                }
                Ok(())
            }
            BackCmd::SwitchToBlock(id) => {
                let block = self.block(id)?;
                self.builder.switch_to_block(block);
                Ok(())
            }
            BackCmd::SealBlock(id) => {
                let block = self.block(id)?;
                self.builder.seal_block(block);
                Ok(())
            }
            BackCmd::SwitchInt(value_id, ty, cases, default_id) => {
                let value = self.value(value_id)?;
                let value_ty = self.builder.func.dfg.value_type(value);
                let expected_ty = ty.clif_type(self.ptr_ty);
                if value_ty != expected_ty {
                    return Err(MoonliftError::new(format!(
                        "function '{}' used BackCmdSwitchInt value '{}' with CLIF type {:?}, expected {:?}",
                        self.func_name.as_str(),
                        value_id.as_str(),
                        value_ty,
                        expected_ty
                    )));
                }
                let default_block = self.block(default_id)?;
                let mut switch = Switch::new();
                let mut seen = HashSet::new();
                for case in cases {
                    let index = parse_switch_int_case(&case.raw, *ty, self.ptr_ty)?;
                    if !seen.insert(index) {
                        return Err(MoonliftError::new(format!(
                            "function '{}' repeated BackCmdSwitchInt case '{}'",
                            self.func_name.as_str(),
                            case.raw
                        )));
                    }
                    switch.set_entry(index, self.block(&case.dest)?);
                }
                switch.emit(&mut self.builder, value, default_block);
                Ok(())
            }
            BackCmd::BindEntryParams(id, values) => {
                let block = self.block(id)?;
                self.builder.append_block_params_for_function_params(block);
                let block_params = self.builder.block_params(block).to_vec();
                if block_params.len() != values.len() {
                    return Err(MoonliftError::new(format!(
                        "function '{}' bound {} entry params for block '{}' but the function signature has {} params",
                        self.func_name.as_str(),
                        values.len(),
                        id.as_str(),
                        block_params.len()
                    )));
                }
                for (name, value) in values.iter().zip(block_params.iter().copied()) {
                    self.bind_value(name, value)?;
                }
                Ok(())
            }
            BackCmd::AppendBlockParam(block_id, value_id, ty) => {
                let block = self.block(block_id)?;
                let value = self.builder.append_block_param(block, ty.clif_type(self.ptr_ty));
                self.bind_value(value_id, value)?;
                Ok(())
            }
            BackCmd::CreateStackSlot(id, size, align) => {
                let align_shift = align_to_shift(*align)?;
                let slot = self.builder.create_sized_stack_slot(StackSlotData::new(
                    StackSlotKind::ExplicitSlot,
                    *size,
                    align_shift,
                ));
                if self.stack_slots.insert(id.clone(), slot).is_some() {
                    return Err(MoonliftError::new(format!(
                        "function '{}' created stack slot '{}' more than once",
                        self.func_name.as_str(),
                        id.as_str()
                    )));
                }
                Ok(())
            }
            BackCmd::Alias(dst, src) => {
                let value = self.value(src)?;
                self.values.insert(dst.clone(), value);
                Ok(())
            }
            BackCmd::StackAddr(dst, slot_id) => {
                let slot = self.stack_slot(slot_id)?;
                let value = self.builder.ins().stack_addr(self.ptr_ty, slot, 0);
                self.bind_value(dst, value)
            }
            BackCmd::DataAddr(dst, data_id) => {
                let data = self.data(data_id)?;
                let gv = self.module.declare_data_in_func(data, &mut self.builder.func);
                let value = self.builder.ins().global_value(self.ptr_ty, gv);
                self.bind_value(dst, value)
            }
            BackCmd::ConstInt(dst, ty, raw) => {
                let value = lower_const_int(self.builder, self.ptr_ty, *ty, raw)?;
                self.bind_value(dst, value)
            }
            BackCmd::ConstFloat(dst, ty, raw) => {
                let value = lower_const_float(self.builder, *ty, raw)?;
                self.bind_value(dst, value)
            }
            BackCmd::ConstBool(dst, value) => {
                let raw = self.builder.ins().iconst(types::I8, if *value { 1 } else { 0 });
                self.bind_value(dst, raw)
            }
            BackCmd::ConstNull(dst) => {
                let value = self.builder.ins().iconst(self.ptr_ty, 0);
                self.bind_value(dst, value)
            }
            BackCmd::Ineg(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().ineg(value);
                self.bind_value(dst, out)
            }
            BackCmd::Fneg(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fneg(value);
                self.bind_value(dst, out)
            }
            BackCmd::Bnot(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().bnot(value);
                self.bind_value(dst, out)
            }
            BackCmd::BoolNot(dst, value) => {
                let value = self.value(value)?;
                let cond = self.builder.ins().icmp_imm(IntCC::Equal, value, 0);
                let out = bool_value_from_cond(self.builder, cond);
                self.bind_value(dst, out)
            }
            BackCmd::Popcount(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().popcnt(value);
                self.bind_value(dst, out)
            }
            BackCmd::Clz(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().clz(value);
                self.bind_value(dst, out)
            }
            BackCmd::Ctz(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().ctz(value);
                self.bind_value(dst, out)
            }
            BackCmd::Bswap(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().bswap(value);
                self.bind_value(dst, out)
            }
            BackCmd::Sqrt(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().sqrt(value);
                self.bind_value(dst, out)
            }
            BackCmd::Abs(dst, ty, value) => {
                let value = self.value(value)?;
                let out = match ty {
                    BackScalar::F32 | BackScalar::F64 => self.builder.ins().fabs(value),
                    _ => self.builder.ins().iabs(value),
                };
                self.bind_value(dst, out)
            }
            BackCmd::Floor(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().floor(value);
                self.bind_value(dst, out)
            }
            BackCmd::Ceil(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().ceil(value);
                self.bind_value(dst, out)
            }
            BackCmd::TruncFloat(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().trunc(value);
                self.bind_value(dst, out)
            }
            BackCmd::Round(dst, _, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().nearest(value);
                self.bind_value(dst, out)
            }
            BackCmd::Iadd(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().iadd(l, r)),
            BackCmd::Isub(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().isub(l, r)),
            BackCmd::Imul(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().imul(l, r)),
            BackCmd::Fadd(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().fadd(l, r)),
            BackCmd::Fsub(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().fsub(l, r)),
            BackCmd::Fmul(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().fmul(l, r)),
            BackCmd::Sdiv(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().sdiv(l, r)),
            BackCmd::Udiv(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().udiv(l, r)),
            BackCmd::Fdiv(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().fdiv(l, r)),
            BackCmd::Srem(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().srem(l, r)),
            BackCmd::Urem(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().urem(l, r)),
            BackCmd::Frem(..) => Err(MoonliftError::new(
                "BackCmdFrem is not yet supported by the current Cranelift host layer; Cranelift does not expose a direct floating remainder instruction in this subset",
            )),
            BackCmd::Band(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().band(l, r)),
            BackCmd::Bor(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().bor(l, r)),
            BackCmd::Bxor(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().bxor(l, r)),
            BackCmd::Ishl(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().ishl(l, r)),
            BackCmd::Ushr(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().ushr(l, r)),
            BackCmd::Sshr(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().sshr(l, r)),
            BackCmd::Rotl(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().rotl(l, r)),
            BackCmd::Rotr(dst, _, lhs, rhs) => self.bind_binop(dst, lhs, rhs, |b, l, r| b.ins().rotr(l, r)),
            BackCmd::IcmpEq(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::Equal, lhs, rhs),
            BackCmd::IcmpNe(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::NotEqual, lhs, rhs),
            BackCmd::SIcmpLt(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::SignedLessThan, lhs, rhs),
            BackCmd::SIcmpLe(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::SignedLessThanOrEqual, lhs, rhs),
            BackCmd::SIcmpGt(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::SignedGreaterThan, lhs, rhs),
            BackCmd::SIcmpGe(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::SignedGreaterThanOrEqual, lhs, rhs),
            BackCmd::UIcmpLt(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::UnsignedLessThan, lhs, rhs),
            BackCmd::UIcmpLe(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::UnsignedLessThanOrEqual, lhs, rhs),
            BackCmd::UIcmpGt(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::UnsignedGreaterThan, lhs, rhs),
            BackCmd::UIcmpGe(dst, _, lhs, rhs) => self.bind_icmp(dst, IntCC::UnsignedGreaterThanOrEqual, lhs, rhs),
            BackCmd::FCmpEq(dst, _, lhs, rhs) => self.bind_fcmp(dst, FloatCC::Equal, lhs, rhs),
            BackCmd::FCmpNe(dst, _, lhs, rhs) => self.bind_fcmp(dst, FloatCC::NotEqual, lhs, rhs),
            BackCmd::FCmpLt(dst, _, lhs, rhs) => self.bind_fcmp(dst, FloatCC::LessThan, lhs, rhs),
            BackCmd::FCmpLe(dst, _, lhs, rhs) => self.bind_fcmp(dst, FloatCC::LessThanOrEqual, lhs, rhs),
            BackCmd::FCmpGt(dst, _, lhs, rhs) => self.bind_fcmp(dst, FloatCC::GreaterThan, lhs, rhs),
            BackCmd::FCmpGe(dst, _, lhs, rhs) => self.bind_fcmp(dst, FloatCC::GreaterThanOrEqual, lhs, rhs),
            BackCmd::Bitcast(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().bitcast(ty.clif_type(self.ptr_ty), MemFlags::new(), value);
                self.bind_value(dst, out)
            }
            BackCmd::Ireduce(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().ireduce(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            BackCmd::Sextend(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().sextend(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            BackCmd::Uextend(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().uextend(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            BackCmd::Fpromote(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fpromote(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            BackCmd::Fdemote(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fdemote(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            BackCmd::SToF(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fcvt_from_sint(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            BackCmd::UToF(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fcvt_from_uint(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            BackCmd::FToS(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fcvt_to_sint(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            BackCmd::FToU(dst, ty, value) => {
                let value = self.value(value)?;
                let out = self.builder.ins().fcvt_to_uint(ty.clif_type(self.ptr_ty), value);
                self.bind_value(dst, out)
            }
            BackCmd::Load(dst, ty, addr) => {
                let addr = self.value(addr)?;
                let out = self
                    .builder
                    .ins()
                    .load(ty.clif_type(self.ptr_ty), MemFlags::new(), addr, 0);
                self.bind_value(dst, out)
            }
            BackCmd::Store(_, addr, value) => {
                let addr = self.value(addr)?;
                let value = self.value(value)?;
                self.builder.ins().store(MemFlags::new(), value, addr, 0);
                Ok(())
            }
            BackCmd::Select(dst, _, cond, then_value, else_value) => {
                let cond_value = self.cond_value(cond)?;
                let then_value = self.value(then_value)?;
                let else_value = self.value(else_value)?;
                let out = self.builder.ins().select(cond_value, then_value, else_value);
                self.bind_value(dst, out)
            }
            BackCmd::Fma(dst, _, a, b, c) => {
                let a = self.value(a)?;
                let b = self.value(b)?;
                let c = self.value(c)?;
                let out = self.builder.ins().fma(a, b, c);
                self.bind_value(dst, out)
            }
            BackCmd::CallValueDirect(dst, _, func, sig, args) => {
                let value = self.call_direct(func, sig, args)?;
                self.bind_value(dst, value)
            }
            BackCmd::CallStmtDirect(func, sig, args) => {
                self.call_direct_stmt(func, sig, args)?;
                Ok(())
            }
            BackCmd::CallValueExtern(dst, _, func, sig, args) => {
                let value = self.call_extern(func, sig, args)?;
                self.bind_value(dst, value)
            }
            BackCmd::CallStmtExtern(func, sig, args) => {
                self.call_extern_stmt(func, sig, args)?;
                Ok(())
            }
            BackCmd::CallValueIndirect(dst, _, callee, sig, args) => {
                let value = self.call_indirect(callee, sig, args)?;
                self.bind_value(dst, value)
            }
            BackCmd::CallStmtIndirect(callee, sig, args) => {
                self.call_indirect_stmt(callee, sig, args)?;
                Ok(())
            }
            BackCmd::Jump(dest, args) => {
                let block = self.block(dest)?;
                let args = self.block_args(args)?;
                self.builder.ins().jump(block, &args);
                Ok(())
            }
            BackCmd::BrIf(cond, then_block, then_args, else_block, else_args) => {
                let cond = self.cond_value(cond)?;
                let then_block = self.block(then_block)?;
                let else_block = self.block(else_block)?;
                let then_args = self.block_args(then_args)?;
                let else_args = self.block_args(else_args)?;
                self.builder.ins().brif(cond, then_block, &then_args, else_block, &else_args);
                Ok(())
            }
            BackCmd::ReturnVoid => {
                self.builder.ins().return_(&[]);
                Ok(())
            }
            BackCmd::ReturnValue(value) => {
                let value = self.value(value)?;
                self.builder.ins().return_(&[value]);
                Ok(())
            }
            BackCmd::Trap => {
                self.builder.ins().trap(TrapCode::unwrap_user(0));
                Ok(())
            }
            BackCmd::FinalizeModule => Err(MoonliftError::new(
                "BackCmdFinalizeModule cannot appear inside a function body",
            )),
        }
    }

    fn bind_binop<F>(&mut self, dst: &BackValId, lhs: &BackValId, rhs: &BackValId, f: F) -> Result<(), MoonliftError>
    where
        F: FnOnce(&mut FunctionBuilder<'a>, Value, Value) -> Value,
    {
        let lhs = self.value(lhs)?;
        let rhs = self.value(rhs)?;
        let out = f(self.builder, lhs, rhs);
        self.bind_value(dst, out)
    }

    fn bind_icmp(&mut self, dst: &BackValId, cc: IntCC, lhs: &BackValId, rhs: &BackValId) -> Result<(), MoonliftError> {
        let lhs = self.value(lhs)?;
        let rhs = self.value(rhs)?;
        let cond = self.builder.ins().icmp(cc, lhs, rhs);
        let out = bool_value_from_cond(self.builder, cond);
        self.bind_value(dst, out)
    }

    fn bind_fcmp(&mut self, dst: &BackValId, cc: FloatCC, lhs: &BackValId, rhs: &BackValId) -> Result<(), MoonliftError> {
        let lhs = self.value(lhs)?;
        let rhs = self.value(rhs)?;
        let cond = self.builder.ins().fcmp(cc, lhs, rhs);
        let out = bool_value_from_cond(self.builder, cond);
        self.bind_value(dst, out)
    }

    fn call_direct(&mut self, func: &BackFuncId, sig: &BackSigId, args: &[BackValId]) -> Result<Value, MoonliftError> {
        let decl = self.funcs.get(func).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' calls unknown direct callee '{}'",
                self.func_name.as_str(),
                func.as_str()
            ))
        })?;
        if &decl.sig != sig {
            return Err(MoonliftError::new(format!(
                "function '{}' called '{}' with signature '{}' but it was declared with '{}'",
                self.func_name.as_str(),
                func.as_str(),
                sig.as_str(),
                decl.sig.as_str()
            )));
        }
        let func_id = decl.func_id.ok_or_else(|| {
            MoonliftError::new(format!("internal error: missing FuncId for direct callee '{}'", func.as_str()))
        })?;
        let func_ref = self.module.declare_func_in_func(func_id, self.builder.func);
        let args = self.values(args)?;
        let call = self.builder.ins().call(func_ref, &args);
        self.take_single_result(call, func.as_str())
    }

    fn call_direct_stmt(&mut self, func: &BackFuncId, sig: &BackSigId, args: &[BackValId]) -> Result<(), MoonliftError> {
        let decl = self.funcs.get(func).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' calls unknown direct callee '{}'",
                self.func_name.as_str(),
                func.as_str()
            ))
        })?;
        if &decl.sig != sig {
            return Err(MoonliftError::new(format!(
                "function '{}' called '{}' with signature '{}' but it was declared with '{}'",
                self.func_name.as_str(),
                func.as_str(),
                sig.as_str(),
                decl.sig.as_str()
            )));
        }
        let func_id = decl.func_id.ok_or_else(|| {
            MoonliftError::new(format!("internal error: missing FuncId for direct callee '{}'", func.as_str()))
        })?;
        let func_ref = self.module.declare_func_in_func(func_id, self.builder.func);
        let args = self.values(args)?;
        self.builder.ins().call(func_ref, &args);
        Ok(())
    }

    fn call_extern(&mut self, extern_id: &BackExternId, sig: &BackSigId, args: &[BackValId]) -> Result<Value, MoonliftError> {
        let decl = self.externs.get(extern_id).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' calls unknown extern '{}'",
                self.func_name.as_str(),
                extern_id.as_str()
            ))
        })?;
        if &decl.sig != sig {
            return Err(MoonliftError::new(format!(
                "function '{}' called extern '{}' with signature '{}' but it was declared with '{}'",
                self.func_name.as_str(),
                extern_id.as_str(),
                sig.as_str(),
                decl.sig.as_str()
            )));
        }
        let func_id = decl.func_id.ok_or_else(|| {
            MoonliftError::new(format!("internal error: missing FuncId for extern '{}'", extern_id.as_str()))
        })?;
        let func_ref = self.module.declare_func_in_func(func_id, self.builder.func);
        let args = self.values(args)?;
        let call = self.builder.ins().call(func_ref, &args);
        self.take_single_result(call, extern_id.as_str())
    }

    fn call_extern_stmt(&mut self, extern_id: &BackExternId, sig: &BackSigId, args: &[BackValId]) -> Result<(), MoonliftError> {
        let decl = self.externs.get(extern_id).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' calls unknown extern '{}'",
                self.func_name.as_str(),
                extern_id.as_str()
            ))
        })?;
        if &decl.sig != sig {
            return Err(MoonliftError::new(format!(
                "function '{}' called extern '{}' with signature '{}' but it was declared with '{}'",
                self.func_name.as_str(),
                extern_id.as_str(),
                sig.as_str(),
                decl.sig.as_str()
            )));
        }
        let func_id = decl.func_id.ok_or_else(|| {
            MoonliftError::new(format!("internal error: missing FuncId for extern '{}'", extern_id.as_str()))
        })?;
        let func_ref = self.module.declare_func_in_func(func_id, self.builder.func);
        let args = self.values(args)?;
        self.builder.ins().call(func_ref, &args);
        Ok(())
    }

    fn call_indirect(&mut self, callee: &BackValId, sig: &BackSigId, args: &[BackValId]) -> Result<Value, MoonliftError> {
        let signature = self.signatures.get(sig).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' calls indirect signature '{}' which was never created",
                self.func_name.as_str(),
                sig.as_str()
            ))
        })?;
        let sig_ref = self.builder.import_signature(signature.clone());
        let callee = self.value(callee)?;
        let args = self.values(args)?;
        let call = self.builder.ins().call_indirect(sig_ref, callee, &args);
        self.take_single_result(call, sig.as_str())
    }

    fn call_indirect_stmt(&mut self, callee: &BackValId, sig: &BackSigId, args: &[BackValId]) -> Result<(), MoonliftError> {
        let signature = self.signatures.get(sig).ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' calls indirect signature '{}' which was never created",
                self.func_name.as_str(),
                sig.as_str()
            ))
        })?;
        let sig_ref = self.builder.import_signature(signature.clone());
        let callee = self.value(callee)?;
        let args = self.values(args)?;
        self.builder.ins().call_indirect(sig_ref, callee, &args);
        Ok(())
    }

    fn take_single_result(&mut self, inst: cranelift_codegen::ir::Inst, target: &str) -> Result<Value, MoonliftError> {
        let results = self.builder.inst_results(inst);
        if results.len() != 1 {
            return Err(MoonliftError::new(format!(
                "call target '{}' produced {} results; the current BackCmd value-call subset expects exactly one result",
                target,
                results.len()
            )));
        }
        Ok(results[0])
    }

    fn bind_value(&mut self, id: &BackValId, value: Value) -> Result<(), MoonliftError> {
        if self.values.insert(id.clone(), value).is_some() {
            return Err(MoonliftError::new(format!(
                "function '{}' bound value '{}' more than once",
                self.func_name.as_str(),
                id.as_str()
            )));
        }
        Ok(())
    }

    fn value(&self, id: &BackValId) -> Result<Value, MoonliftError> {
        self.values.get(id).copied().ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' references unknown value '{}'",
                self.func_name.as_str(),
                id.as_str()
            ))
        })
    }

    fn values(&self, ids: &[BackValId]) -> Result<Vec<Value>, MoonliftError> {
        ids.iter().map(|id| self.value(id)).collect()
    }

    fn block_args(&self, ids: &[BackValId]) -> Result<Vec<BlockArg>, MoonliftError> {
        ids.iter()
            .map(|id| self.value(id).map(BlockArg::Value))
            .collect()
    }

    fn cond_value(&mut self, id: &BackValId) -> Result<Value, MoonliftError> {
        let raw = self.value(id)?;
        Ok(self.builder.ins().icmp_imm(IntCC::NotEqual, raw, 0))
    }

    fn block(&self, id: &BackBlockId) -> Result<Block, MoonliftError> {
        self.blocks.get(id).copied().ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' references unknown block '{}'",
                self.func_name.as_str(),
                id.as_str()
            ))
        })
    }

    fn stack_slot(&self, id: &BackStackSlotId) -> Result<StackSlot, MoonliftError> {
        self.stack_slots.get(id).copied().ok_or_else(|| {
            MoonliftError::new(format!(
                "function '{}' references unknown stack slot '{}'",
                self.func_name.as_str(),
                id.as_str()
            ))
        })
    }

    fn data(&self, id: &BackDataId) -> Result<DataId, MoonliftError> {
        self.datas
            .get(id)
            .and_then(|decl| decl.data_id)
            .ok_or_else(|| {
                MoonliftError::new(format!(
                    "function '{}' references unknown data object '{}'",
                    self.func_name.as_str(),
                    id.as_str()
                ))
            })
    }
}

fn bool_value_from_cond(builder: &mut FunctionBuilder<'_>, cond: Value) -> Value {
    let one = builder.ins().iconst(types::I8, 1);
    let zero = builder.ins().iconst(types::I8, 0);
    builder.ins().select(cond, one, zero)
}

fn make_signature(module: &JITModule, params: &[BackScalar], results: &[BackScalar]) -> Signature {
    let ptr_ty = module.target_config().pointer_type();
    let mut sig = module.make_signature();
    for param in params {
        sig.params.push(AbiParam::new(param.clif_type(ptr_ty)));
    }
    for result in results {
        sig.returns.push(AbiParam::new(result.clif_type(ptr_ty)));
    }
    sig
}

fn lower_const_int(
    builder: &mut FunctionBuilder<'_>,
    ptr_ty: Type,
    ty: BackScalar,
    raw: &str,
) -> Result<Value, MoonliftError> {
    let clif_ty = ty.clif_type(ptr_ty);
    let imm = match ty {
        BackScalar::Bool => {
            return Err(MoonliftError::new(
                "BackCmdConstInt cannot build a bool; use BackCmdConstBool instead",
            ))
        }
        BackScalar::I8 | BackScalar::I16 | BackScalar::I32 | BackScalar::I64 => raw.parse::<i64>().map_err(|e| {
            MoonliftError::new(format!("failed to parse signed integer literal '{}': {e}", raw))
        })?,
        BackScalar::U8
        | BackScalar::U16
        | BackScalar::U32
        | BackScalar::U64
        | BackScalar::Ptr
        | BackScalar::Index => raw.parse::<u64>().map_err(|e| {
            MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw))
        })? as i64,
        BackScalar::F32 | BackScalar::F64 => {
            return Err(MoonliftError::new(
                "BackCmdConstInt cannot build a float; use BackCmdConstFloat instead",
            ))
        }
    };
    Ok(builder.ins().iconst(clif_ty, imm))
}

fn lower_const_float(
    builder: &mut FunctionBuilder<'_>,
    ty: BackScalar,
    raw: &str,
) -> Result<Value, MoonliftError> {
    match ty {
        BackScalar::F32 => {
            let value = raw.parse::<f32>().map_err(|e| {
                MoonliftError::new(format!("failed to parse f32 literal '{}': {e}", raw))
            })?;
            Ok(builder.ins().f32const(Ieee32::with_float(value)))
        }
        BackScalar::F64 => {
            let value = raw.parse::<f64>().map_err(|e| {
                MoonliftError::new(format!("failed to parse f64 literal '{}': {e}", raw))
            })?;
            Ok(builder.ins().f64const(Ieee64::with_float(value)))
        }
        _ => Err(MoonliftError::new(
            "BackCmdConstFloat requires BackF32 or BackF64",
        )),
    }
}

fn write_data_bytes(dst: &mut [u8], offset: usize, src: &[u8], what: &str) -> Result<(), MoonliftError> {
    let end = offset.checked_add(src.len()).ok_or_else(|| {
        MoonliftError::new(format!("{} write overflowed offset arithmetic", what))
    })?;
    if end > dst.len() {
        return Err(MoonliftError::new(format!(
            "{} write [{}..{}) exceeds data object size {}",
            what,
            offset,
            end,
            dst.len()
        )));
    }
    dst[offset..end].copy_from_slice(src);
    Ok(())
}

fn write_data_init(bytes: &mut [u8], ptr_ty: Type, init: &DataInit) -> Result<(), MoonliftError> {
    match init {
        DataInit::Zero { offset, size } => {
            let start = *offset as usize;
            let len = *size as usize;
            let end = start.checked_add(len).ok_or_else(|| {
                MoonliftError::new("data zero-init overflowed offset arithmetic")
            })?;
            if end > bytes.len() {
                return Err(MoonliftError::new(format!(
                    "data zero-init [{}..{}) exceeds data object size {}",
                    start,
                    end,
                    bytes.len()
                )));
            }
            for b in &mut bytes[start..end] {
                *b = 0;
            }
            Ok(())
        }
        DataInit::Int { offset, ty, raw } => {
            let data = match ty {
                BackScalar::Bool => {
                    return Err(MoonliftError::new(
                        "BackCmdDataInitInt cannot build a bool; use BackCmdDataInitBool instead",
                    ))
                }
                BackScalar::I8 => (raw.parse::<i8>().map_err(|e| MoonliftError::new(format!("failed to parse signed integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::I16 => (raw.parse::<i16>().map_err(|e| MoonliftError::new(format!("failed to parse signed integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::I32 => (raw.parse::<i32>().map_err(|e| MoonliftError::new(format!("failed to parse signed integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::I64 => (raw.parse::<i64>().map_err(|e| MoonliftError::new(format!("failed to parse signed integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::U8 => (raw.parse::<u8>().map_err(|e| MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::U16 => (raw.parse::<u16>().map_err(|e| MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::U32 => (raw.parse::<u32>().map_err(|e| MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::U64 => (raw.parse::<u64>().map_err(|e| MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec(),
                BackScalar::Ptr | BackScalar::Index => {
                    if ptr_ty.bytes() == 8 {
                        (raw.parse::<u64>().map_err(|e| MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec()
                    } else {
                        (raw.parse::<u32>().map_err(|e| MoonliftError::new(format!("failed to parse unsigned integer literal '{}': {e}", raw)))?).to_le_bytes().to_vec()
                    }
                }
                BackScalar::F32 | BackScalar::F64 => {
                    return Err(MoonliftError::new(
                        "BackCmdDataInitInt cannot build a float; use BackCmdDataInitFloat instead",
                    ))
                }
            };
            write_data_bytes(bytes, *offset as usize, &data, "data integer init")
        }
        DataInit::Float { offset, ty, raw } => {
            let data = match ty {
                BackScalar::F32 => (raw.parse::<f32>().map_err(|e| MoonliftError::new(format!("failed to parse f32 literal '{}': {e}", raw)))?).to_bits().to_le_bytes().to_vec(),
                BackScalar::F64 => (raw.parse::<f64>().map_err(|e| MoonliftError::new(format!("failed to parse f64 literal '{}': {e}", raw)))?).to_bits().to_le_bytes().to_vec(),
                _ => {
                    return Err(MoonliftError::new(
                        "BackCmdDataInitFloat requires BackF32 or BackF64",
                    ))
                }
            };
            write_data_bytes(bytes, *offset as usize, &data, "data float init")
        }
        DataInit::Bool { offset, value } => {
            write_data_bytes(bytes, *offset as usize, &[*value as u8], "data bool init")
        }
    }
}

fn align_to_shift(align: u32) -> Result<u8, MoonliftError> {
    if align == 0 {
        return Err(MoonliftError::new(
            "stack slot alignment must be >= 1 byte",
        ));
    }
    if !align.is_power_of_two() {
        return Err(MoonliftError::new(format!(
            "stack slot alignment {} is not a power of two",
            align
        )));
    }
    Ok(align.trailing_zeros() as u8)
}

fn local_symbol_name(id: &BackFuncId) -> String {
    let mut out = String::from("moonlift_fn_");
    for byte in id.as_str().as_bytes() {
        out.push(hex_digit(byte >> 4));
        out.push(hex_digit(byte & 0x0f));
    }
    out
}

fn local_data_symbol_name(id: &BackDataId) -> String {
    let mut out = String::from("moonlift_data_");
    for byte in id.as_str().as_bytes() {
        out.push(hex_digit(byte >> 4));
        out.push(hex_digit(byte & 0x0f));
    }
    out
}

fn hex_digit(n: u8) -> char {
    match n {
        0..=9 => (b'0' + n) as char,
        10..=15 => (b'a' + (n - 10)) as char,
        _ => unreachable!(),
    }
}

fn empty_module() -> Result<JITModule, MoonliftError> {
    Compiler::new(&HashMap::new()).map(|c| c.module)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::mem;

    #[test]
    fn compiles_and_calls_exported_function() {
        let jit = Jit::new();
        let program = BackProgram::new(vec![
            BackCmd::CreateSig(BackSigId::from("sig:add1"), vec![BackScalar::I32], vec![BackScalar::I32]),
            BackCmd::DeclareFuncExport(BackFuncId::from("add1"), BackSigId::from("sig:add1")),
            BackCmd::BeginFunc(BackFuncId::from("add1")),
            BackCmd::CreateBlock(BackBlockId::from("entry")),
            BackCmd::SwitchToBlock(BackBlockId::from("entry")),
            BackCmd::BindEntryParams(BackBlockId::from("entry"), vec![BackValId::from("arg")]),
            BackCmd::ConstInt(BackValId::from("one"), BackScalar::I32, "1".to_string()),
            BackCmd::Iadd(
                BackValId::from("sum"),
                BackScalar::I32,
                BackValId::from("arg"),
                BackValId::from("one"),
            ),
            BackCmd::ReturnValue(BackValId::from("sum")),
            BackCmd::SealBlock(BackBlockId::from("entry")),
            BackCmd::FinishFunc(BackFuncId::from("add1")),
            BackCmd::FinalizeModule,
        ]);

        let artifact = jit.compile(&program).unwrap();
        let ptr = artifact.getpointer_by_name("add1").unwrap();
        let f = unsafe { mem::transmute::<*const c_void, extern "C" fn(i32) -> i32>(ptr) };
        assert_eq!(f(41), 42);
    }

    extern "C" fn triple(x: i32) -> i32 {
        x * 3
    }

    #[test]
    fn compiles_and_calls_registered_extern() {
        let mut jit = Jit::new();
        jit.symbol("triple_host", triple as *const u8);

        let program = BackProgram::new(vec![
            BackCmd::CreateSig(BackSigId::from("sig:triple"), vec![BackScalar::I32], vec![BackScalar::I32]),
            BackCmd::DeclareFuncExtern(
                BackExternId::from("triple"),
                "triple_host".to_string(),
                BackSigId::from("sig:triple"),
            ),
            BackCmd::CreateSig(BackSigId::from("sig:caller"), vec![BackScalar::I32], vec![BackScalar::I32]),
            BackCmd::DeclareFuncExport(BackFuncId::from("caller"), BackSigId::from("sig:caller")),
            BackCmd::BeginFunc(BackFuncId::from("caller")),
            BackCmd::CreateBlock(BackBlockId::from("entry")),
            BackCmd::SwitchToBlock(BackBlockId::from("entry")),
            BackCmd::BindEntryParams(BackBlockId::from("entry"), vec![BackValId::from("arg")]),
            BackCmd::CallValueExtern(
                BackValId::from("ret"),
                BackScalar::I32,
                BackExternId::from("triple"),
                BackSigId::from("sig:triple"),
                vec![BackValId::from("arg")],
            ),
            BackCmd::ReturnValue(BackValId::from("ret")),
            BackCmd::SealBlock(BackBlockId::from("entry")),
            BackCmd::FinishFunc(BackFuncId::from("caller")),
            BackCmd::FinalizeModule,
        ]);

        let artifact = jit.compile(&program).unwrap();
        let ptr = artifact.getpointer_by_name("caller").unwrap();
        let f = unsafe { mem::transmute::<*const c_void, extern "C" fn(i32) -> i32>(ptr) };
        assert_eq!(f(14), 42);
    }

    #[test]
    fn compiles_and_reads_data_object() {
        let jit = Jit::new();
        let program = BackProgram::new(vec![
            BackCmd::DeclareData(BackDataId::from("const:k"), 4, 4),
            BackCmd::DataInitInt(BackDataId::from("const:k"), 0, BackScalar::I32, "42".to_string()),
            BackCmd::CreateSig(BackSigId::from("sig:getk"), vec![], vec![BackScalar::I32]),
            BackCmd::DeclareFuncExport(BackFuncId::from("getk"), BackSigId::from("sig:getk")),
            BackCmd::BeginFunc(BackFuncId::from("getk")),
            BackCmd::CreateBlock(BackBlockId::from("entry")),
            BackCmd::SwitchToBlock(BackBlockId::from("entry")),
            BackCmd::DataAddr(BackValId::from("addr"), BackDataId::from("const:k")),
            BackCmd::Load(BackValId::from("value"), BackScalar::I32, BackValId::from("addr")),
            BackCmd::ReturnValue(BackValId::from("value")),
            BackCmd::SealBlock(BackBlockId::from("entry")),
            BackCmd::FinishFunc(BackFuncId::from("getk")),
            BackCmd::FinalizeModule,
        ]);

        let artifact = jit.compile(&program).unwrap();
        let ptr = artifact.getpointer_by_name("getk").unwrap();
        let f = unsafe { mem::transmute::<*const c_void, extern "C" fn() -> i32>(ptr) };
        assert_eq!(f(), 42);
    }

    #[test]
    fn compiles_block_param_loop_cfg() {
        let jit = Jit::new();
        let program = BackProgram::new(vec![
            BackCmd::CreateSig(BackSigId::from("sig:count"), vec![], vec![BackScalar::I32]),
            BackCmd::DeclareFuncExport(BackFuncId::from("count"), BackSigId::from("sig:count")),
            BackCmd::BeginFunc(BackFuncId::from("count")),
            BackCmd::CreateBlock(BackBlockId::from("entry")),
            BackCmd::CreateBlock(BackBlockId::from("header")),
            BackCmd::CreateBlock(BackBlockId::from("body")),
            BackCmd::CreateBlock(BackBlockId::from("exit")),
            BackCmd::SwitchToBlock(BackBlockId::from("entry")),
            BackCmd::AppendBlockParam(BackBlockId::from("header"), BackValId::from("header.i"), BackScalar::I32),
            BackCmd::AppendBlockParam(BackBlockId::from("body"), BackValId::from("body.i"), BackScalar::I32),
            BackCmd::AppendBlockParam(BackBlockId::from("exit"), BackValId::from("exit.i"), BackScalar::I32),
            BackCmd::ConstInt(BackValId::from("zero"), BackScalar::I32, "0".to_string()),
            BackCmd::Jump(BackBlockId::from("header"), vec![BackValId::from("zero")]),
            BackCmd::SwitchToBlock(BackBlockId::from("header")),
            BackCmd::Alias(BackValId::from("i"), BackValId::from("header.i")),
            BackCmd::ConstInt(BackValId::from("limit"), BackScalar::I32, "4".to_string()),
            BackCmd::SIcmpLt(
                BackValId::from("cond"),
                BackScalar::Bool,
                BackValId::from("i"),
                BackValId::from("limit"),
            ),
            BackCmd::BrIf(
                BackValId::from("cond"),
                BackBlockId::from("body"),
                vec![BackValId::from("header.i")],
                BackBlockId::from("exit"),
                vec![BackValId::from("header.i")],
            ),
            BackCmd::SealBlock(BackBlockId::from("body")),
            BackCmd::SealBlock(BackBlockId::from("exit")),
            BackCmd::SwitchToBlock(BackBlockId::from("body")),
            BackCmd::Alias(BackValId::from("i"), BackValId::from("body.i")),
            BackCmd::ConstInt(BackValId::from("one"), BackScalar::I32, "1".to_string()),
            BackCmd::Iadd(
                BackValId::from("next"),
                BackScalar::I32,
                BackValId::from("i"),
                BackValId::from("one"),
            ),
            BackCmd::Jump(BackBlockId::from("header"), vec![BackValId::from("next")]),
            BackCmd::SealBlock(BackBlockId::from("header")),
            BackCmd::SwitchToBlock(BackBlockId::from("exit")),
            BackCmd::Alias(BackValId::from("result"), BackValId::from("exit.i")),
            BackCmd::ReturnValue(BackValId::from("result")),
            BackCmd::FinishFunc(BackFuncId::from("count")),
            BackCmd::FinalizeModule,
        ]);

        let artifact = jit.compile(&program).unwrap();
        let ptr = artifact.getpointer_by_name("count").unwrap();
        let f = unsafe { mem::transmute::<*const c_void, extern "C" fn() -> i32>(ptr) };
        assert_eq!(f(), 4);
    }
}
