#![allow(unsafe_op_in_unsafe_fn)]

use crate::cranelift_jit::{
    BinaryOp, CallTarget, CastOp, CompileStats, Expr, FunctionSpec, JitError, LocalDecl,
    MoonliftJit, ScalarType, Stmt, UnaryOp,
};
use crate::luajit::{
    lua_State, lua_Number, LuaCFunction, LuaError, LuaState, LUA_TNIL, LUA_TSTRING, LUA_TTABLE,
};
use std::os::raw::{c_int, c_void};

pub struct Runtime {
    lua: LuaState,
    jit: MoonliftJit,
}

impl Runtime {
    pub fn new() -> Result<Self, LuaError> {
        let mut lua = LuaState::new()?;
        lua.openlibs();
        let jit = MoonliftJit::new().map_err(jit_error)?;
        Ok(Self { lua, jit })
    }

    pub fn initialize(&mut self) -> Result<(), LuaError> {
        self.install_bootstrap_globals()?;
        self.install_lua_bootstrap()?;
        Ok(())
    }

    pub fn run_file(&mut self, path: &str) -> Result<(), LuaError> {
        self.lua.dofile(path)
    }

    #[allow(dead_code)]
    pub fn lua_state(&mut self) -> *mut crate::luajit::lua_State {
        self.lua.raw()
    }

    fn install_bootstrap_globals(&mut self) -> Result<(), LuaError> {
        let self_ptr = self as *mut Runtime as *mut c_void;
        self.lua.set_lightuserdata_global("__moonlift_runtime", self_ptr)?;

        self.lua.new_table(0, 7);
        self.lua
            .set_cfunction_field_on_top("add", moonlift_add_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("compile", moonlift_compile_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("addr", moonlift_addr_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("call", moonlift_call_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("call1", moonlift_call1_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("call2", moonlift_call2_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("stats", moonlift_stats_lua as LuaCFunction)?;
        self.lua.set_global_from_top("__moonlift_backend")?;
        Ok(())
    }

    fn install_lua_bootstrap(&mut self) -> Result<(), LuaError> {
        self.lua.dostring(
            r#"
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
"#,
        )
    }

    fn add_i32_i32(&self, a: i32, b: i32) -> i32 {
        self.jit.add_i32_i32(a, b)
    }

    fn compile_function(&mut self, spec: FunctionSpec) -> Result<u32, LuaError> {
        self.jit.compile_function(spec).map_err(jit_error)
    }

    fn code_addr(&self, handle: u32) -> Option<u64> {
        self.jit.code_addr(handle)
    }

    fn stats(&self) -> CompileStats {
        self.jit.stats()
    }
}

fn jit_error(err: JitError) -> LuaError {
    LuaError {
        code: -1,
        message: err.to_string(),
    }
}

fn runtime_from_state(state: *mut lua_State) -> *mut Runtime {
    match LuaState::get_lightuserdata_global_from_state(state, "__moonlift_runtime") {
        Ok(ptr) => ptr as *mut Runtime,
        Err(_) => std::ptr::null_mut(),
    }
}

unsafe extern "C" fn moonlift_add_lua(state: *mut lua_State) -> c_int {
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime is not initialized");
    }

    let rt = &mut *rt_ptr;
    let a = LuaState::to_integer(state, 1) as i32;
    let b = LuaState::to_integer(state, 2) as i32;
    let out = rt.add_i32_i32(a, b);
    LuaState::push_integer(state, out as isize);
    1
}

unsafe extern "C" fn moonlift_compile_lua(state: *mut lua_State) -> c_int {
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        eprintln!("moonlift compile error: runtime is not initialized");
        LuaState::push_integer(state, -1);
        return 1;
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let spec = parse_function_spec(state, 1)?;
        let rt = &mut *rt_ptr;
        let handle = rt.compile_function(spec).map_err(|e| e.to_string())?;
        Ok::<u32, String>(handle)
    }));

    let handle = match result {
        Ok(Ok(handle)) => handle,
        Ok(Err(msg)) => {
            eprintln!("moonlift compile error: {}", msg);
            LuaState::push_integer(state, -1);
            return 1;
        }
        Err(panic) => {
            let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = panic.downcast_ref::<String>() {
                s.clone()
            } else {
                "moonlift compile panic".to_string()
            };
            eprintln!("moonlift compile panic: {}", msg);
            LuaState::push_integer(state, -1);
            return 1;
        }
    };

    LuaState::push_integer(state, handle as isize);
    1
}

unsafe extern "C" fn moonlift_addr_lua(state: *mut lua_State) -> c_int {
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime is not initialized");
    }
    let rt = &mut *rt_ptr;
    let handle = LuaState::to_integer(state, 1) as u32;
    let addr = match rt.code_addr(handle) {
        Some(v) => v,
        None => return LuaState::raise_error(state, "unknown moonlift function handle"),
    };
    LuaState::push_number(state, addr as lua_Number);
    1
}

unsafe extern "C" fn moonlift_call_lua(state: *mut lua_State) -> c_int {
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime is not initialized");
    }
    let rt = &mut *rt_ptr;

    let argc = LuaState::gettop(state);
    if argc < 1 {
        return LuaState::raise_error(state, "moonlift call expects a handle");
    }
    let handle = LuaState::to_integer(state, 1) as u32;
    let params = match rt.jit.param_types(handle) {
        Some(p) => p,
        None => return LuaState::raise_error(state, "unknown moonlift function handle"),
    };
    let got = (argc - 1) as usize;
    if got != params.len() {
        return LuaState::raise_error(
            state,
            &format!("moonlift call expected {} arguments, got {}", params.len(), got),
        );
    }
    let mut packed = Vec::with_capacity(params.len());
    for i in 0..params.len() {
        let v = match pack_lua_arg(state, (i + 2) as c_int, params[i]) {
            Ok(v) => v,
            Err(err) => return LuaState::raise_error(state, &err),
        };
        packed.push(v);
    }
    let out = match rt.jit.call_packed(handle, &packed) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err.to_string()),
    };
    let result_ty = match rt.jit.result_type(handle) {
        Some(t) => t,
        None => return LuaState::raise_error(state, "unknown moonlift function handle"),
    };
    if result_ty.is_void() {
        return 0;
    }
    if let Err(err) = push_packed_result(state, result_ty, out) {
        return LuaState::raise_error(state, &err);
    }
    1
}

unsafe extern "C" fn moonlift_call1_lua(state: *mut lua_State) -> c_int {
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime is not initialized");
    }
    let rt = &mut *rt_ptr;

    let handle = LuaState::to_integer(state, 1) as u32;
    let params = match rt.jit.param_types(handle) {
        Some(p) => p,
        None => return LuaState::raise_error(state, "unknown moonlift function handle"),
    };
    if params.len() != 1 {
        return LuaState::raise_error(state, "moonlift call1 used on function with wrong arity");
    }
    let packed = match pack_lua_arg(state, 2, params[0]) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err),
    };
    let out = match rt.jit.call1_packed(handle, packed) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err.to_string()),
    };
    let result_ty = match rt.jit.result_type(handle) {
        Some(t) => t,
        None => return LuaState::raise_error(state, "unknown moonlift function handle"),
    };
    if result_ty.is_void() {
        return 0;
    }
    if let Err(err) = push_packed_result(state, result_ty, out) {
        return LuaState::raise_error(state, &err);
    }
    1
}

unsafe extern "C" fn moonlift_call2_lua(state: *mut lua_State) -> c_int {
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime is not initialized");
    }
    let rt = &mut *rt_ptr;

    let handle = LuaState::to_integer(state, 1) as u32;
    let params = match rt.jit.param_types(handle) {
        Some(p) => p,
        None => return LuaState::raise_error(state, "unknown moonlift function handle"),
    };
    if params.len() != 2 {
        return LuaState::raise_error(state, "moonlift call2 used on function with wrong arity");
    }
    let a = match pack_lua_arg(state, 2, params[0]) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err),
    };
    let b = match pack_lua_arg(state, 3, params[1]) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err),
    };
    let out = match rt.jit.call2_packed(handle, a, b) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err.to_string()),
    };
    let result_ty = match rt.jit.result_type(handle) {
        Some(t) => t,
        None => return LuaState::raise_error(state, "unknown moonlift function handle"),
    };
    if result_ty.is_void() {
        return 0;
    }
    if let Err(err) = push_packed_result(state, result_ty, out) {
        return LuaState::raise_error(state, &err);
    }
    1
}

unsafe extern "C" fn moonlift_stats_lua(state: *mut lua_State) -> c_int {
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime is not initialized");
    }

    let rt = &mut *rt_ptr;
    let stats = rt.stats();
    LuaState::create_table(state, 0, 4);
    if let Err(err) = LuaState::set_integer_field_on_top(state, "compile_hits", stats.compile_hits as isize)
    {
        return LuaState::raise_error(state, &err.message);
    }
    if let Err(err) = LuaState::set_integer_field_on_top(state, "compile_misses", stats.compile_misses as isize)
    {
        return LuaState::raise_error(state, &err.message);
    }
    if let Err(err) = LuaState::set_integer_field_on_top(state, "cache_entries", stats.cache_entries as isize)
    {
        return LuaState::raise_error(state, &err.message);
    }
    if let Err(err) = LuaState::set_integer_field_on_top(state, "compiled_functions", stats.compiled_functions as isize)
    {
        return LuaState::raise_error(state, &err.message);
    }
    1
}

unsafe fn parse_function_spec(state: *mut lua_State, idx: c_int) -> Result<FunctionSpec, String> {
    expect_type(state, idx, LUA_TTABLE, "moonlift.compile expects a table")?;
    let name = read_required_string_field(state, idx, "name")?;
    let params = parse_param_types(state, idx)?;
    let result = read_required_scalar_type_field(state, idx, "result")?;
    let locals = read_legacy_locals_field(state, idx)?;
    let mut body = read_expr_field(state, idx, "body")?;
    if !locals.is_empty() {
        body = Expr::Block {
            stmts: locals
                .into_iter()
                .map(|local| Stmt::Let {
                    name: local.name,
                    ty: local.ty,
                    init: local.init,
                })
                .collect(),
            result: Box::new(body),
            ty: result,
        };
    }
    Ok(FunctionSpec {
        name,
        params,
        result,
        locals: Vec::new(),
        body,
    })
}

unsafe fn parse_param_types(state: *mut lua_State, idx: c_int) -> Result<Vec<ScalarType>, String> {
    LuaState::get_field(state, idx, "params").map_err(|e| e.message)?;
    if LuaState::get_type(state, -1) != LUA_TTABLE {
        LuaState::pop(state, 1);
        return Err("moonlift.compile requires params to be a table".to_string());
    }
    let params_idx = LuaState::gettop(state);
    let mut out = Vec::new();
    let mut i: i64 = 1;
    loop {
        LuaState::raw_get_i(state, params_idx, i);
        let ty = LuaState::get_type(state, -1);
        if ty == LUA_TNIL {
            LuaState::pop(state, 1);
            break;
        }
        if ty != LUA_TSTRING {
            LuaState::pop(state, 2);
            return Err(format!("params[{}] must be a type name string", i));
        }
        let name = LuaState::to_string(state, -1).unwrap_or_default();
        LuaState::pop(state, 1);
        let scalar = ScalarType::from_name(&name)
            .ok_or_else(|| format!("unsupported Moonlift type {name:?}"))?;
        out.push(scalar);
        i = i + 1;
    }
    LuaState::pop(state, 1);
    if out.len() > 4 {
        return Err("moonlift currently supports only arity 0..4".to_string());
    }
    Ok(out)
}

unsafe fn read_legacy_locals_field(state: *mut lua_State, idx: c_int) -> Result<Vec<LocalDecl>, String> {
    LuaState::get_field(state, idx, "locals").map_err(|e| e.message)?;
    let ty = LuaState::get_type(state, -1);
    if ty == LUA_TNIL {
        LuaState::pop(state, 1);
        return Ok(Vec::new());
    }
    if ty != LUA_TTABLE {
        LuaState::pop(state, 1);
        return Err("field 'locals' must be a table when present".to_string());
    }
    let arr_idx = LuaState::gettop(state);
    let mut out = Vec::new();
    let mut i: i64 = 1;
    loop {
        LuaState::raw_get_i(state, arr_idx, i);
        let entry_ty = LuaState::get_type(state, -1);
        if entry_ty == LUA_TNIL {
            LuaState::pop(state, 1);
            break;
        }
        if entry_ty != LUA_TTABLE {
            LuaState::pop(state, 2);
            return Err(format!("locals[{}] must be a table", i));
        }
        let local_idx = LuaState::gettop(state);
        let name = read_required_string_field(state, local_idx, "name")?;
        let ty = read_required_scalar_type_field(state, local_idx, "type")?;
        let init = read_expr_field(state, local_idx, "init")?;
        LuaState::pop(state, 1);
        out.push(LocalDecl { name, ty, init });
        i = i + 1;
    }
    LuaState::pop(state, 1);
    Ok(out)
}

unsafe fn read_stmt_array_field(state: *mut lua_State, idx: c_int, name: &str) -> Result<Vec<Stmt>, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    if LuaState::get_type(state, -1) != LUA_TTABLE {
        LuaState::pop(state, 1);
        return Err(format!("field {name:?} must be a table of statements"));
    }
    let arr_idx = LuaState::gettop(state);
    let out = parse_stmt_array(state, arr_idx)?;
    LuaState::pop(state, 1);
    Ok(out)
}

unsafe fn parse_stmt_array(state: *mut lua_State, idx: c_int) -> Result<Vec<Stmt>, String> {
    let mut out = Vec::new();
    let mut i: i64 = 1;
    loop {
        LuaState::raw_get_i(state, idx, i);
        let ty = LuaState::get_type(state, -1);
        if ty == LUA_TNIL {
            LuaState::pop(state, 1);
            break;
        }
        if ty != LUA_TTABLE {
            LuaState::pop(state, 1);
            return Err(format!("statement array entry {} must be a table", i));
        }
        let stmt_idx = LuaState::gettop(state);
        let stmt = parse_stmt(state, stmt_idx)?;
        LuaState::pop(state, 1);
        out.push(stmt);
        i = i + 1;
    }
    Ok(out)
}

unsafe fn parse_stmt(state: *mut lua_State, idx: c_int) -> Result<Stmt, String> {
    let tag = read_required_string_field(state, idx, "tag")?;
    match tag.as_str() {
        "let" => Ok(Stmt::Let {
            name: read_required_string_field(state, idx, "name")?,
            ty: read_required_scalar_type_field(state, idx, "type")?,
            init: read_expr_field(state, idx, "init")?,
        }),
        "var" => Ok(Stmt::Var {
            name: read_required_string_field(state, idx, "name")?,
            ty: read_required_scalar_type_field(state, idx, "type")?,
            init: read_expr_field(state, idx, "init")?,
        }),
        "set" => Ok(Stmt::Set {
            name: read_required_string_field(state, idx, "name")?,
            value: read_expr_field(state, idx, "value")?,
        }),
        "while" => Ok(Stmt::While {
            cond: read_expr_field(state, idx, "cond")?,
            body: read_stmt_array_field(state, idx, "body")?,
        }),
        "store" => Ok(Stmt::Store {
            ty: read_required_scalar_type_field(state, idx, "type")?,
            addr: read_expr_field(state, idx, "addr")?,
            value: read_expr_field(state, idx, "value")?,
        }),
        "call" => Ok(Stmt::Call {
            target: parse_call_target(state, idx)?,
            args: read_expr_array_field(state, idx, "args")?,
        }),
        "break" => Ok(Stmt::Break),
        "continue" => Ok(Stmt::Continue),
        _ => Err(format!("unknown Moonlift statement tag {tag:?}")),
    }
}

unsafe fn read_expr_field(state: *mut lua_State, idx: c_int, name: &str) -> Result<Expr, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    let expr_idx = LuaState::gettop(state);
    let out = parse_expr(state, expr_idx);
    LuaState::pop(state, 1);
    out
}

unsafe fn parse_expr(state: *mut lua_State, idx: c_int) -> Result<Expr, String> {
    expect_type(state, idx, LUA_TTABLE, "expression must be a table")?;
    let tag = read_required_string_field(state, idx, "tag")?;
    match tag.as_str() {
        "arg" => {
            let index = read_required_i64_field(state, idx, "index")?;
            if index <= 0 {
                return Err("arg.index must be >= 1".to_string());
            }
            Ok(Expr::Arg {
                index: index as u32,
                ty: read_required_scalar_type_field(state, idx, "type")?,
            })
        }
        "local" => Ok(Expr::Local {
            name: read_required_string_field(state, idx, "name")?,
            ty: read_required_scalar_type_field(state, idx, "type")?,
        }),
        "bool" => Ok(Expr::Const {
            ty: ScalarType::Bool,
            bits: if read_required_bool_field(state, idx, "value")? { 1 } else { 0 },
        }),
        "i8" | "i16" | "i32" | "i64" => {
            let ty = ScalarType::from_name(tag.as_str()).unwrap();
            let v = read_required_i64_field(state, idx, "value")?;
            Ok(Expr::Const { ty, bits: v as u64 })
        }
        "u8" | "u16" | "u32" | "u64" => {
            let ty = ScalarType::from_name(tag.as_str()).unwrap();
            let v = read_required_u64_field(state, idx, "value")?;
            Ok(Expr::Const { ty, bits: v })
        }
        "f32" => {
            let v = read_required_number_field(state, idx, "value")? as f32;
            Ok(Expr::Const {
                ty: ScalarType::F32,
                bits: v.to_bits() as u64,
            })
        }
        "f64" => {
            let v = read_required_number_field(state, idx, "value")?;
            Ok(Expr::Const {
                ty: ScalarType::F64,
                bits: v.to_bits(),
            })
        }
        "neg" => Ok(Expr::Unary {
            op: UnaryOp::Neg,
            ty: read_required_scalar_type_field(state, idx, "type")?,
            value: Box::new(read_expr_field(state, idx, "value")?),
        }),
        "not" => Ok(Expr::Unary {
            op: UnaryOp::Not,
            ty: ScalarType::Bool,
            value: Box::new(read_expr_field(state, idx, "value")?),
        }),
        "bnot" => Ok(Expr::Unary {
            op: UnaryOp::Bnot,
            ty: read_required_scalar_type_field(state, idx, "type")?,
            value: Box::new(read_expr_field(state, idx, "value")?),
        }),
        "add" => parse_binary_expr(state, idx, BinaryOp::Add),
        "sub" => parse_binary_expr(state, idx, BinaryOp::Sub),
        "mul" => parse_binary_expr(state, idx, BinaryOp::Mul),
        "div" => parse_binary_expr(state, idx, BinaryOp::Div),
        "rem" => parse_binary_expr(state, idx, BinaryOp::Rem),
        "eq" => parse_bool_binary_expr(state, idx, BinaryOp::Eq),
        "ne" => parse_bool_binary_expr(state, idx, BinaryOp::Ne),
        "lt" => parse_bool_binary_expr(state, idx, BinaryOp::Lt),
        "le" => parse_bool_binary_expr(state, idx, BinaryOp::Le),
        "gt" => parse_bool_binary_expr(state, idx, BinaryOp::Gt),
        "ge" => parse_bool_binary_expr(state, idx, BinaryOp::Ge),
        "and" => parse_bool_binary_expr(state, idx, BinaryOp::And),
        "or" => parse_bool_binary_expr(state, idx, BinaryOp::Or),
        "band" => parse_binary_expr(state, idx, BinaryOp::Band),
        "bor" => parse_binary_expr(state, idx, BinaryOp::Bor),
        "bxor" => parse_binary_expr(state, idx, BinaryOp::Bxor),
        "shl" => parse_binary_expr(state, idx, BinaryOp::Shl),
        "shr_u" => parse_binary_expr(state, idx, BinaryOp::ShrU),
        "shr_s" => parse_binary_expr(state, idx, BinaryOp::ShrS),
        "cast" => parse_cast_expr(state, idx, CastOp::Cast),
        "trunc" => parse_cast_expr(state, idx, CastOp::Trunc),
        "zext" => parse_cast_expr(state, idx, CastOp::Zext),
        "sext" => parse_cast_expr(state, idx, CastOp::Sext),
        "bitcast" => parse_cast_expr(state, idx, CastOp::Bitcast),
        "let" => Ok(Expr::Let {
            name: read_required_string_field(state, idx, "name")?,
            ty: read_required_scalar_type_field(state, idx, "type")?,
            init: Box::new(read_expr_field(state, idx, "init")?),
            body: Box::new(read_expr_field(state, idx, "body")?),
        }),
        "block" => Ok(Expr::Block {
            stmts: read_stmt_array_field(state, idx, "stmts")?,
            result: Box::new(read_expr_field(state, idx, "result")?),
            ty: read_required_scalar_type_field(state, idx, "type")?,
        }),
        "if" => Ok(Expr::If {
            cond: Box::new(read_expr_field(state, idx, "cond")?),
            then_expr: Box::new(read_expr_field(state, idx, "then_")?),
            else_expr: Box::new(read_expr_field(state, idx, "else_")?),
            ty: read_required_scalar_type_field(state, idx, "type")?,
        }),
        "load" => Ok(Expr::Load {
            ty: read_required_scalar_type_field(state, idx, "type")?,
            addr: Box::new(read_expr_field(state, idx, "addr")?),
        }),
        "ptr" => {
            let v = read_required_u64_field(state, idx, "value")?;
            Ok(Expr::Const { ty: ScalarType::Ptr, bits: v })
        }
        "call" => Ok(Expr::Call {
            target: parse_call_target(state, idx)?,
            ty: read_required_scalar_type_field(state, idx, "type")?,
            args: read_expr_array_field(state, idx, "args")?,
        }),
        _ => Err(format!("unknown Moonlift expression tag {tag:?}")),
    }
}

unsafe fn parse_binary_expr(state: *mut lua_State, idx: c_int, op: BinaryOp) -> Result<Expr, String> {
    Ok(Expr::Binary {
        op,
        ty: read_required_scalar_type_field(state, idx, "type")?,
        lhs: Box::new(read_expr_field(state, idx, "lhs")?),
        rhs: Box::new(read_expr_field(state, idx, "rhs")?),
    })
}

unsafe fn parse_bool_binary_expr(state: *mut lua_State, idx: c_int, op: BinaryOp) -> Result<Expr, String> {
    Ok(Expr::Binary {
        op,
        ty: ScalarType::Bool,
        lhs: Box::new(read_expr_field(state, idx, "lhs")?),
        rhs: Box::new(read_expr_field(state, idx, "rhs")?),
    })
}

unsafe fn parse_cast_expr(state: *mut lua_State, idx: c_int, op: CastOp) -> Result<Expr, String> {
    Ok(Expr::Cast {
        op,
        ty: read_required_scalar_type_field(state, idx, "type")?,
        value: Box::new(read_expr_field(state, idx, "value")?),
    })
}

unsafe fn read_type_array_field(state: *mut lua_State, idx: c_int, name: &str) -> Result<Vec<ScalarType>, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    if LuaState::get_type(state, -1) != LUA_TTABLE {
        LuaState::pop(state, 1);
        return Err(format!("field {name:?} must be a table of types"));
    }
    let arr_idx = LuaState::gettop(state);
    let mut out = Vec::new();
    let mut i: i64 = 1;
    loop {
        LuaState::raw_get_i(state, arr_idx, i);
        let ty = LuaState::get_type(state, -1);
        if ty == LUA_TNIL {
            LuaState::pop(state, 1);
            break;
        }
        if ty != LUA_TSTRING {
            LuaState::pop(state, 2);
            return Err(format!("type array entry {} must be a string", i));
        }
        let name = LuaState::to_string(state, -1).unwrap_or_default();
        let scalar = ScalarType::from_name(&name)
            .ok_or_else(|| format!("unsupported Moonlift type {name:?}"))?;
        LuaState::pop(state, 1);
        out.push(scalar);
        i = i + 1;
    }
    LuaState::pop(state, 1);
    Ok(out)
}

unsafe fn read_expr_array_field(state: *mut lua_State, idx: c_int, name: &str) -> Result<Vec<Expr>, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    if LuaState::get_type(state, -1) != LUA_TTABLE {
        LuaState::pop(state, 1);
        return Err(format!("field {name:?} must be a table of expressions"));
    }
    let arr_idx = LuaState::gettop(state);
    let mut out = Vec::new();
    let mut i: i64 = 1;
    loop {
        LuaState::raw_get_i(state, arr_idx, i);
        let ty = LuaState::get_type(state, -1);
        if ty == LUA_TNIL {
            LuaState::pop(state, 1);
            break;
        }
        if ty != LUA_TTABLE {
            LuaState::pop(state, 2);
            return Err(format!("expression array entry {} must be a table", i));
        }
        let expr_idx = LuaState::gettop(state);
        out.push(parse_expr(state, expr_idx)?);
        LuaState::pop(state, 1);
        i = i + 1;
    }
    LuaState::pop(state, 1);
    Ok(out)
}

unsafe fn parse_call_target(state: *mut lua_State, idx: c_int) -> Result<CallTarget, String> {
    let kind = read_required_string_field(state, idx, "callee_kind")?;
    let params = read_type_array_field(state, idx, "params")?;
    let result = read_required_scalar_type_field(state, idx, "result")?;
    match kind.as_str() {
        "direct" => Ok(CallTarget::Direct {
            name: read_required_string_field(state, idx, "name")?,
            params,
            result,
        }),
        "indirect" => Ok(CallTarget::Indirect {
            addr: Box::new(read_expr_field(state, idx, "addr")?),
            params,
            result,
        }),
        _ => Err(format!("unknown Moonlift call target kind {kind:?}")),
    }
}

unsafe fn read_required_scalar_type_field(
    state: *mut lua_State,
    idx: c_int,
    name: &str,
) -> Result<ScalarType, String> {
    let name = read_required_string_field(state, idx, name)?;
    ScalarType::from_name(&name).ok_or_else(|| format!("unsupported Moonlift type {name:?}"))
}

unsafe fn read_required_string_field(
    state: *mut lua_State,
    idx: c_int,
    name: &str,
) -> Result<String, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    let ty = LuaState::get_type(state, -1);
    let out = if ty == LUA_TSTRING {
        LuaState::to_string(state, -1).ok_or_else(|| format!("field {name:?} must be a string"))
    } else {
        Err(format!("field {name:?} must be a string"))
    };
    LuaState::pop(state, 1);
    out
}

unsafe fn read_required_i64_field(
    state: *mut lua_State,
    idx: c_int,
    name: &str,
) -> Result<i64, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    if LuaState::get_type(state, -1) == LUA_TNIL {
        LuaState::pop(state, 1);
        return Err(format!("field {name:?} is missing"));
    }
    let v = LuaState::to_integer(state, -1) as i64;
    LuaState::pop(state, 1);
    Ok(v)
}

unsafe fn read_required_u64_field(
    state: *mut lua_State,
    idx: c_int,
    name: &str,
) -> Result<u64, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    if LuaState::get_type(state, -1) == LUA_TNIL {
        LuaState::pop(state, 1);
        return Err(format!("field {name:?} is missing"));
    }
    let v = LuaState::to_number(state, -1);
    LuaState::pop(state, 1);
    Ok(v as u64)
}

unsafe fn read_required_number_field(
    state: *mut lua_State,
    idx: c_int,
    name: &str,
) -> Result<lua_Number, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    if LuaState::get_type(state, -1) == LUA_TNIL {
        LuaState::pop(state, 1);
        return Err(format!("field {name:?} is missing"));
    }
    let v = LuaState::to_number(state, -1);
    LuaState::pop(state, 1);
    Ok(v)
}

unsafe fn read_required_bool_field(
    state: *mut lua_State,
    idx: c_int,
    name: &str,
) -> Result<bool, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    if LuaState::get_type(state, -1) == LUA_TNIL {
        LuaState::pop(state, 1);
        return Err(format!("field {name:?} is missing"));
    }
    let v = LuaState::to_boolean(state, -1);
    LuaState::pop(state, 1);
    Ok(v)
}

unsafe fn expect_type(
    state: *mut lua_State,
    idx: c_int,
    expected: c_int,
    message: &str,
) -> Result<(), String> {
    let got = LuaState::get_type(state, idx);
    if got == expected {
        Ok(())
    } else {
        Err(format!("{} (got {})", message, lua_type_name(got)))
    }
}

fn lua_type_name(ty: c_int) -> &'static str {
    match ty {
        LUA_TNIL => "nil",
        LUA_TSTRING => "string",
        LUA_TTABLE => "table",
        _ => "other",
    }
}

unsafe fn pack_lua_arg(state: *mut lua_State, idx: c_int, ty: ScalarType) -> Result<u64, String> {
    Ok(match ty {
        ScalarType::Void => return Err("cannot pass a value for Moonlift void".to_string()),
        ScalarType::Bool => {
            if LuaState::to_boolean(state, idx) {
                1
            } else {
                0
            }
        }
        ScalarType::I8 => LuaState::to_integer(state, idx) as i8 as u8 as u64,
        ScalarType::I16 => LuaState::to_integer(state, idx) as i16 as u16 as u64,
        ScalarType::I32 => LuaState::to_integer(state, idx) as i32 as u32 as u64,
        ScalarType::I64 => LuaState::to_integer(state, idx) as i64 as u64,
        ScalarType::U8 => LuaState::to_number(state, idx) as u8 as u64,
        ScalarType::U16 => LuaState::to_number(state, idx) as u16 as u64,
        ScalarType::U32 => LuaState::to_number(state, idx) as u32 as u64,
        ScalarType::U64 => LuaState::to_number(state, idx) as u64,
        ScalarType::F32 => (LuaState::to_number(state, idx) as f32).to_bits() as u64,
        ScalarType::F64 => (LuaState::to_number(state, idx) as f64).to_bits(),
        ScalarType::Ptr => LuaState::to_integer(state, idx) as u64,
    })
}

unsafe fn push_packed_result(state: *mut lua_State, ty: ScalarType, bits: u64) -> Result<(), String> {
    match ty {
        ScalarType::Void => return Err("cannot push a Moonlift void result as a value".to_string()),
        ScalarType::Bool => LuaState::push_boolean(state, bits & 1 != 0),
        ScalarType::I8 => LuaState::push_integer(state, (bits as u8 as i8) as isize),
        ScalarType::I16 => LuaState::push_integer(state, (bits as u16 as i16) as isize),
        ScalarType::I32 => LuaState::push_integer(state, (bits as u32 as i32) as isize),
        ScalarType::I64 => LuaState::push_integer(state, bits as i64 as isize),
        ScalarType::U8 => LuaState::push_integer(state, (bits as u8) as isize),
        ScalarType::U16 => LuaState::push_integer(state, (bits as u16) as isize),
        ScalarType::U32 => LuaState::push_integer(state, (bits as u32) as isize),
        ScalarType::U64 => {
            if bits <= isize::MAX as u64 {
                LuaState::push_integer(state, bits as isize)
            } else {
                LuaState::push_number(state, bits as lua_Number)
            }
        }
        ScalarType::F32 => LuaState::push_number(state, f32::from_bits(bits as u32) as lua_Number),
        ScalarType::F64 => LuaState::push_number(state, f64::from_bits(bits) as lua_Number),
        ScalarType::Ptr => LuaState::push_integer(state, bits as isize),
    }
    Ok(())
}
