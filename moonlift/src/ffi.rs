use crate::{
    Artifact, BackBlockId, BackCmd, BackDataId, BackExternId, BackFuncId, BackProgram, BackScalar,
    BackSigId, BackStackSlotId, BackValId, Jit, MoonliftError,
};
use std::cell::RefCell;
use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::ptr;

#[repr(C)]
pub struct moonlift_jit_t {
    inner: Jit,
}

#[repr(C)]
pub struct moonlift_program_t {
    cmds: Vec<BackCmd>,
}

#[repr(C)]
pub struct moonlift_artifact_t {
    inner: Artifact,
}

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::new("ok").expect("valid CString"));
}

fn set_last_error(message: impl Into<String>) {
    let mut text = message.into();
    if text.as_bytes().contains(&0) {
        text = text.replace('\0', "?");
    }
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = CString::new(text).unwrap_or_else(|_| CString::new("moonlift ffi error").unwrap());
    });
}

fn clear_last_error() {
    set_last_error("ok");
}

fn fail_ptr<T>(message: impl Into<String>) -> *mut T {
    set_last_error(message);
    ptr::null_mut()
}

fn fail_const_ptr<T>(message: impl Into<String>) -> *const T {
    set_last_error(message);
    ptr::null()
}

fn fail_int(message: impl Into<String>) -> c_int {
    set_last_error(message);
    0
}

fn ok_int() -> c_int {
    clear_last_error();
    1
}

fn require_ptr<'a, T>(ptr: *mut T, what: &str) -> Result<&'a mut T, MoonliftError> {
    unsafe { ptr.as_mut() }.ok_or_else(|| MoonliftError(format!("{what} pointer was null")))
}

fn read_cstr(ptr: *const c_char, what: &str) -> Result<String, MoonliftError> {
    if ptr.is_null() {
        return Err(MoonliftError(format!("{what} string pointer was null")));
    }
    let text = unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|e| MoonliftError(format!("{what} was not valid UTF-8: {e}")))?;
    Ok(text.to_string())
}

fn read_scalar(code: u32) -> Result<BackScalar, MoonliftError> {
    match code {
        1 => Ok(BackScalar::Bool),
        2 => Ok(BackScalar::I8),
        3 => Ok(BackScalar::I16),
        4 => Ok(BackScalar::I32),
        5 => Ok(BackScalar::I64),
        6 => Ok(BackScalar::U8),
        7 => Ok(BackScalar::U16),
        8 => Ok(BackScalar::U32),
        9 => Ok(BackScalar::U64),
        10 => Ok(BackScalar::F32),
        11 => Ok(BackScalar::F64),
        12 => Ok(BackScalar::Ptr),
        13 => Ok(BackScalar::Index),
        _ => Err(MoonliftError(format!("unknown BackScalar code {code}"))),
    }
}

fn read_scalar_slice(ptr: *const u32, len: usize, what: &str) -> Result<Vec<BackScalar>, MoonliftError> {
    if len == 0 {
        return Ok(Vec::new());
    }
    if ptr.is_null() {
        return Err(MoonliftError(format!("{what} array pointer was null with len={len}")));
    }
    let raw = unsafe { std::slice::from_raw_parts(ptr, len) };
    raw.iter().map(|code| read_scalar(*code)).collect()
}

fn read_string_array(ptr: *const *const c_char, len: usize, what: &str) -> Result<Vec<String>, MoonliftError> {
    if len == 0 {
        return Ok(Vec::new());
    }
    if ptr.is_null() {
        return Err(MoonliftError(format!("{what} pointer array was null with len={len}")));
    }
    let raw = unsafe { std::slice::from_raw_parts(ptr, len) };
    raw.iter()
        .enumerate()
        .map(|(i, p)| read_cstr(*p, &format!("{what}[{i}]")))
        .collect()
}

fn val_ids(ptr: *const *const c_char, len: usize, what: &str) -> Result<Vec<BackValId>, MoonliftError> {
    Ok(read_string_array(ptr, len, what)?
        .into_iter()
        .map(BackValId::from)
        .collect())
}

fn push_cmd(program: &mut moonlift_program_t, cmd: BackCmd) {
    program.cmds.push(cmd);
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_last_error_message() -> *const c_char {
    LAST_ERROR.with(|slot| slot.borrow().as_ptr())
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_new() -> *mut moonlift_jit_t {
    clear_last_error();
    Box::into_raw(Box::new(moonlift_jit_t { inner: Jit::new() }))
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_free(ptr: *mut moonlift_jit_t) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_new() -> *mut moonlift_program_t {
    clear_last_error();
    Box::into_raw(Box::new(moonlift_program_t { cmds: Vec::new() }))
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_free(ptr: *mut moonlift_program_t) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_artifact_free(ptr: *mut moonlift_artifact_t) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_symbol(
    jit: *mut moonlift_jit_t,
    name: *const c_char,
    ptr_value: *const c_void,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let jit = require_ptr(jit, "moonlift_jit_t")?;
        let name = read_cstr(name, "symbol name")?;
        jit.inner.symbol(name, ptr_value.cast());
        Ok(())
    })();
    match result {
        Ok(()) => ok_int(),
        Err(err) => fail_int(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_compile(
    jit: *mut moonlift_jit_t,
    program: *const moonlift_program_t,
) -> *mut moonlift_artifact_t {
    let result: Result<_, MoonliftError> = (|| {
        let jit = require_ptr(jit, "moonlift_jit_t")?;
        let program = unsafe { program.as_ref() }
            .ok_or_else(|| MoonliftError("moonlift_program_t pointer was null".to_string()))?;
        let artifact = jit.inner.compile(&BackProgram::new(program.cmds.clone()))?;
        Ok(Box::into_raw(Box::new(moonlift_artifact_t { inner: artifact })))
    })();
    match result {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => fail_ptr(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_artifact_getpointer(
    artifact: *const moonlift_artifact_t,
    func: *const c_char,
) -> *const c_void {
    let result: Result<_, MoonliftError> = (|| {
        let artifact = unsafe { artifact.as_ref() }
            .ok_or_else(|| MoonliftError("moonlift_artifact_t pointer was null".to_string()))?;
        let func = read_cstr(func, "function id")?;
        artifact.inner.getpointer_by_name(&func)
    })();
    match result {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => fail_const_ptr(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_create_sig(
    program: *mut moonlift_program_t,
    sig: *const c_char,
    params: *const u32,
    params_len: usize,
    results: *const u32,
    results_len: usize,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let sig = read_cstr(sig, "signature id")?;
        let params = read_scalar_slice(params, params_len, "signature params")?;
        let results = read_scalar_slice(results, results_len, "signature results")?;
        push_cmd(program, BackCmd::CreateSig(BackSigId::from(sig), params, results));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_declare_data(
    program: *mut moonlift_program_t,
    data: *const c_char,
    size: u32,
    align: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DeclareData(BackDataId::from(read_cstr(data, "data id")?), size, align));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_data_init_zero(
    program: *mut moonlift_program_t,
    data: *const c_char,
    offset: u32,
    size: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DataInitZero(BackDataId::from(read_cstr(data, "data id")?), offset, size));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_data_init_int(
    program: *mut moonlift_program_t,
    data: *const c_char,
    offset: u32,
    ty: u32,
    raw: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DataInitInt(
            BackDataId::from(read_cstr(data, "data id")?),
            offset,
            read_scalar(ty)?,
            read_cstr(raw, "integer literal")?,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_data_init_float(
    program: *mut moonlift_program_t,
    data: *const c_char,
    offset: u32,
    ty: u32,
    raw: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DataInitFloat(
            BackDataId::from(read_cstr(data, "data id")?),
            offset,
            read_scalar(ty)?,
            read_cstr(raw, "float literal")?,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_data_init_bool(
    program: *mut moonlift_program_t,
    data: *const c_char,
    offset: u32,
    value: c_int,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DataInitBool(BackDataId::from(read_cstr(data, "data id")?), offset, value != 0));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_declare_func_local(
    program: *mut moonlift_program_t,
    func: *const c_char,
    sig: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DeclareFuncLocal(BackFuncId::from(read_cstr(func, "function id")?), BackSigId::from(read_cstr(sig, "signature id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_declare_func_export(
    program: *mut moonlift_program_t,
    func: *const c_char,
    sig: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DeclareFuncExport(BackFuncId::from(read_cstr(func, "function id")?), BackSigId::from(read_cstr(sig, "signature id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_declare_func_extern(
    program: *mut moonlift_program_t,
    func: *const c_char,
    symbol: *const c_char,
    sig: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DeclareFuncExtern(
            BackExternId::from(read_cstr(func, "extern id")?),
            read_cstr(symbol, "extern symbol")?,
            BackSigId::from(read_cstr(sig, "signature id")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_begin_func(program: *mut moonlift_program_t, func: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::BeginFunc(BackFuncId::from(read_cstr(func, "function id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_create_block(program: *mut moonlift_program_t, block: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::CreateBlock(BackBlockId::from(read_cstr(block, "block id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_switch_to_block(program: *mut moonlift_program_t, block: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::SwitchToBlock(BackBlockId::from(read_cstr(block, "block id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_seal_block(program: *mut moonlift_program_t, block: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::SealBlock(BackBlockId::from(read_cstr(block, "block id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_bind_entry_params(
    program: *mut moonlift_program_t,
    block: *const c_char,
    values: *const *const c_char,
    values_len: usize,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::BindEntryParams(BackBlockId::from(read_cstr(block, "block id")?), val_ids(values, values_len, "entry params")?));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_append_block_param(
    program: *mut moonlift_program_t,
    block: *const c_char,
    value: *const c_char,
    ty: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::AppendBlockParam(
            BackBlockId::from(read_cstr(block, "block id")?),
            BackValId::from(read_cstr(value, "value id")?),
            read_scalar(ty)?,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_create_stack_slot(
    program: *mut moonlift_program_t,
    slot: *const c_char,
    size: u32,
    align: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::CreateStackSlot(BackStackSlotId::from(read_cstr(slot, "stack slot id")?), size, align));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_alias(program: *mut moonlift_program_t, dst: *const c_char, src: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Alias(BackValId::from(read_cstr(dst, "dst value id")?), BackValId::from(read_cstr(src, "src value id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_stack_addr(program: *mut moonlift_program_t, dst: *const c_char, slot: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::StackAddr(BackValId::from(read_cstr(dst, "dst value id")?), BackStackSlotId::from(read_cstr(slot, "stack slot id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_data_addr(program: *mut moonlift_program_t, dst: *const c_char, data: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DataAddr(BackValId::from(read_cstr(dst, "dst value id")?), BackDataId::from(read_cstr(data, "data id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_const_int(program: *mut moonlift_program_t, dst: *const c_char, ty: u32, raw: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ConstInt(BackValId::from(read_cstr(dst, "dst value id")?), read_scalar(ty)?, read_cstr(raw, "integer literal")?));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_const_float(program: *mut moonlift_program_t, dst: *const c_char, ty: u32, raw: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ConstFloat(BackValId::from(read_cstr(dst, "dst value id")?), read_scalar(ty)?, read_cstr(raw, "float literal")?));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_const_bool(program: *mut moonlift_program_t, dst: *const c_char, value: c_int) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ConstBool(BackValId::from(read_cstr(dst, "dst value id")?), value != 0));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_const_null(program: *mut moonlift_program_t, dst: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ConstNull(BackValId::from(read_cstr(dst, "dst value id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

fn unary_cmd(op: u32, dst: BackValId, ty: BackScalar, value: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::Ineg(dst, ty, value)),
        2 => Ok(BackCmd::Fneg(dst, ty, value)),
        3 => Ok(BackCmd::Bnot(dst, ty, value)),
        4 => Ok(BackCmd::BoolNot(dst, value)),
        _ => Err(MoonliftError(format!("unknown unary opcode {op}"))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_unary(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    ty: u32,
    value: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = unary_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(value, "input value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

fn binary_cmd(op: u32, dst: BackValId, ty: BackScalar, lhs: BackValId, rhs: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::Iadd(dst, ty, lhs, rhs)),
        2 => Ok(BackCmd::Isub(dst, ty, lhs, rhs)),
        3 => Ok(BackCmd::Imul(dst, ty, lhs, rhs)),
        4 => Ok(BackCmd::Fadd(dst, ty, lhs, rhs)),
        5 => Ok(BackCmd::Fsub(dst, ty, lhs, rhs)),
        6 => Ok(BackCmd::Fmul(dst, ty, lhs, rhs)),
        7 => Ok(BackCmd::Sdiv(dst, ty, lhs, rhs)),
        8 => Ok(BackCmd::Udiv(dst, ty, lhs, rhs)),
        9 => Ok(BackCmd::Fdiv(dst, ty, lhs, rhs)),
        10 => Ok(BackCmd::Srem(dst, ty, lhs, rhs)),
        11 => Ok(BackCmd::Urem(dst, ty, lhs, rhs)),
        12 => Ok(BackCmd::Frem(dst, ty, lhs, rhs)),
        13 => Ok(BackCmd::Band(dst, ty, lhs, rhs)),
        14 => Ok(BackCmd::Bor(dst, ty, lhs, rhs)),
        15 => Ok(BackCmd::Bxor(dst, ty, lhs, rhs)),
        16 => Ok(BackCmd::Ishl(dst, ty, lhs, rhs)),
        17 => Ok(BackCmd::Ushr(dst, ty, lhs, rhs)),
        18 => Ok(BackCmd::Sshr(dst, ty, lhs, rhs)),
        19 => Ok(BackCmd::IcmpEq(dst, ty, lhs, rhs)),
        20 => Ok(BackCmd::IcmpNe(dst, ty, lhs, rhs)),
        21 => Ok(BackCmd::SIcmpLt(dst, ty, lhs, rhs)),
        22 => Ok(BackCmd::SIcmpLe(dst, ty, lhs, rhs)),
        23 => Ok(BackCmd::SIcmpGt(dst, ty, lhs, rhs)),
        24 => Ok(BackCmd::SIcmpGe(dst, ty, lhs, rhs)),
        25 => Ok(BackCmd::UIcmpLt(dst, ty, lhs, rhs)),
        26 => Ok(BackCmd::UIcmpLe(dst, ty, lhs, rhs)),
        27 => Ok(BackCmd::UIcmpGt(dst, ty, lhs, rhs)),
        28 => Ok(BackCmd::UIcmpGe(dst, ty, lhs, rhs)),
        29 => Ok(BackCmd::FCmpEq(dst, ty, lhs, rhs)),
        30 => Ok(BackCmd::FCmpNe(dst, ty, lhs, rhs)),
        31 => Ok(BackCmd::FCmpLt(dst, ty, lhs, rhs)),
        32 => Ok(BackCmd::FCmpLe(dst, ty, lhs, rhs)),
        33 => Ok(BackCmd::FCmpGt(dst, ty, lhs, rhs)),
        34 => Ok(BackCmd::FCmpGe(dst, ty, lhs, rhs)),
        _ => Err(MoonliftError(format!("unknown binary opcode {op}"))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_binary(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    ty: u32,
    lhs: *const c_char,
    rhs: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = binary_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(lhs, "lhs value id")?),
            BackValId::from(read_cstr(rhs, "rhs value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

fn cast_cmd(op: u32, dst: BackValId, ty: BackScalar, value: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::Bitcast(dst, ty, value)),
        2 => Ok(BackCmd::Ireduce(dst, ty, value)),
        3 => Ok(BackCmd::Sextend(dst, ty, value)),
        4 => Ok(BackCmd::Uextend(dst, ty, value)),
        5 => Ok(BackCmd::Fpromote(dst, ty, value)),
        6 => Ok(BackCmd::Fdemote(dst, ty, value)),
        7 => Ok(BackCmd::SToF(dst, ty, value)),
        8 => Ok(BackCmd::UToF(dst, ty, value)),
        9 => Ok(BackCmd::FToS(dst, ty, value)),
        10 => Ok(BackCmd::FToU(dst, ty, value)),
        _ => Err(MoonliftError(format!("unknown cast opcode {op}"))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_cast(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    ty: u32,
    value: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = cast_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(value, "input value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_load(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    ty: u32,
    addr: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Load(
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(addr, "address value id")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_store(
    program: *mut moonlift_program_t,
    ty: u32,
    addr: *const c_char,
    value: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Store(
            read_scalar(ty)?,
            BackValId::from(read_cstr(addr, "address value id")?),
            BackValId::from(read_cstr(value, "stored value id")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_select(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    ty: u32,
    cond: *const c_char,
    then_value: *const c_char,
    else_value: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Select(
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(cond, "condition value id")?),
            BackValId::from(read_cstr(then_value, "then value id")?),
            BackValId::from(read_cstr(else_value, "else value id")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_call_value(
    program: *mut moonlift_program_t,
    kind: u32,
    dst: *const c_char,
    ty: u32,
    target: *const c_char,
    sig: *const c_char,
    args: *const *const c_char,
    args_len: usize,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let dst = BackValId::from(read_cstr(dst, "dst value id")?);
        let ty = read_scalar(ty)?;
        let target = read_cstr(target, "call target id")?;
        let sig = BackSigId::from(read_cstr(sig, "signature id")?);
        let args = val_ids(args, args_len, "call args")?;
        let cmd = match kind {
            1 => BackCmd::CallValueDirect(dst, ty, BackFuncId::from(target), sig, args),
            2 => BackCmd::CallValueExtern(dst, ty, BackExternId::from(target), sig, args),
            3 => BackCmd::CallValueIndirect(dst, ty, BackValId::from(target), sig, args),
            _ => return Err(MoonliftError(format!("unknown call kind {kind}"))),
        };
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_call_stmt(
    program: *mut moonlift_program_t,
    kind: u32,
    target: *const c_char,
    sig: *const c_char,
    args: *const *const c_char,
    args_len: usize,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let target = read_cstr(target, "call target id")?;
        let sig = BackSigId::from(read_cstr(sig, "signature id")?);
        let args = val_ids(args, args_len, "call args")?;
        let cmd = match kind {
            1 => BackCmd::CallStmtDirect(BackFuncId::from(target), sig, args),
            2 => BackCmd::CallStmtExtern(BackExternId::from(target), sig, args),
            3 => BackCmd::CallStmtIndirect(BackValId::from(target), sig, args),
            _ => return Err(MoonliftError(format!("unknown call kind {kind}"))),
        };
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_jump(
    program: *mut moonlift_program_t,
    dest: *const c_char,
    args: *const *const c_char,
    args_len: usize,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Jump(BackBlockId::from(read_cstr(dest, "destination block id")?), val_ids(args, args_len, "jump args")?));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_brif(
    program: *mut moonlift_program_t,
    cond: *const c_char,
    then_block: *const c_char,
    then_args: *const *const c_char,
    then_args_len: usize,
    else_block: *const c_char,
    else_args: *const *const c_char,
    else_args_len: usize,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::BrIf(
            BackValId::from(read_cstr(cond, "condition value id")?),
            BackBlockId::from(read_cstr(then_block, "then block id")?),
            val_ids(then_args, then_args_len, "then args")?,
            BackBlockId::from(read_cstr(else_block, "else block id")?),
            val_ids(else_args, else_args_len, "else args")?,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_return_void(program: *mut moonlift_program_t) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ReturnVoid);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_return_value(program: *mut moonlift_program_t, value: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ReturnValue(BackValId::from(read_cstr(value, "return value id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_trap(program: *mut moonlift_program_t) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Trap);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_finish_func(program: *mut moonlift_program_t, func: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::FinishFunc(BackFuncId::from(read_cstr(func, "function id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_finalize_module(program: *mut moonlift_program_t) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::FinalizeModule);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}
