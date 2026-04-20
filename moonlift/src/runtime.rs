#![allow(unsafe_op_in_unsafe_fn)]

use crate::cranelift_jit::{
    BinaryOp, CallTarget, CastOp, CompileStats, Expr, FunctionSpec, JitError, LocalDecl,
    MoonliftJit, ScalarType, Stmt, UnaryOp,
};
use crate::lua_ast::{expr_to_lua, externs_to_lua, item_to_lua, module_to_lua, type_to_lua};
use crate::luajit::{
    lua_State, lua_Number, LuaCFunction, LuaError, LuaState, LUA_TNIL, LUA_TSTRING, LUA_TTABLE,
};
use crate::parser::{
    parse_code, parse_code_dump, parse_expr as parse_source_expr, parse_expr_dump, parse_externs,
    parse_externs_dump, parse_module, parse_module_dump, parse_type, parse_type_dump,
};
use crate::source_native::{prepare_code as prepare_native_code, prepare_module as prepare_native_module, PreparedCode, PreparedModule};
use std::collections::HashMap;
use std::os::raw::{c_int, c_void};

pub struct Runtime {
    lua: LuaState,
    jit: MoonliftJit,
    native_code_cache: HashMap<String, PreparedCode>,
    native_module_cache: HashMap<String, PreparedModule>,
}

impl Runtime {
    pub fn new() -> Result<Self, LuaError> {
        let mut lua = LuaState::new()?;
        lua.openlibs();
        let jit = MoonliftJit::new().map_err(jit_error)?;
        Ok(Self {
            lua,
            jit,
            native_code_cache: HashMap::new(),
            native_module_cache: HashMap::new(),
        })
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

        self.lua.new_table(0, 25);
        self.lua
            .set_cfunction_field_on_top("add", moonlift_add_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("compile", moonlift_compile_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("compile_module", moonlift_compile_module_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("addr", moonlift_addr_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("call", moonlift_call_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("call0", moonlift_call0_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("call1", moonlift_call1_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("call2", moonlift_call2_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("call3", moonlift_call3_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("call4", moonlift_call4_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("stats", moonlift_stats_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("parse_code", moonlift_parse_code_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("parse_module", moonlift_parse_module_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("parse_expr", moonlift_parse_expr_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("parse_type", moonlift_parse_type_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("parse_extern", moonlift_parse_extern_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("ast_code", moonlift_ast_code_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("ast_module", moonlift_ast_module_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("ast_expr", moonlift_ast_expr_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("ast_type", moonlift_ast_type_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("ast_extern", moonlift_ast_extern_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("source_meta_code", moonlift_source_meta_code_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("source_meta_module", moonlift_source_meta_module_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("compile_source_code", moonlift_compile_source_code_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("compile_source_module", moonlift_compile_source_module_lua as LuaCFunction)?;
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

    fn compile_module(&mut self, specs: Vec<FunctionSpec>) -> Result<Vec<u32>, LuaError> {
        self.jit.compile_module(specs).map_err(jit_error)
    }

    fn code_addr(&self, handle: u32) -> Option<u64> {
        self.jit.code_addr(handle)
    }

    fn stats(&self) -> CompileStats {
        self.jit.stats()
    }

    fn prepared_native_code(&mut self, source: &str) -> Result<PreparedCode, String> {
        if let Some(cached) = self.native_code_cache.get(source) {
            return Ok(cached.clone());
        }
        let prepared = prepare_native_code(source)?;
        self.native_code_cache
            .insert(source.to_string(), prepared.clone());
        Ok(prepared)
    }

    fn prepared_native_module(&mut self, source: &str) -> Result<PreparedModule, String> {
        if let Some(cached) = self.native_module_cache.get(source) {
            return Ok(cached.clone());
        }
        let prepared = prepare_native_module(source)?;
        self.native_module_cache
            .insert(source.to_string(), prepared.clone());
        Ok(prepared)
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

unsafe fn push_compile_error(state: *mut lua_State, message: &str) -> c_int {
    LuaState::push_nil(state);
    match LuaState::push_string(state, message) {
        Ok(()) => 2,
        Err(err) => LuaState::raise_error(state, &err.message),
    }
}

unsafe fn parse_source_arg(state: *mut lua_State, what: &str) -> Result<String, c_int> {
    match LuaState::to_string(state, 1) {
        Some(s) => Ok(s),
        None => Err(LuaState::raise_error(
            state,
            &format!("moonlift {} expects a source string", what),
        )),
    }
}

unsafe fn push_parse_result(state: *mut lua_State, result: Result<String, String>) -> c_int {
    match result {
        Ok(text) => match LuaState::push_string(state, &text) {
            Ok(()) => 1,
            Err(err) => LuaState::raise_error(state, &err.message),
        },
        Err(message) => {
            LuaState::push_nil(state);
            match LuaState::push_string(state, &message) {
                Ok(()) => 2,
                Err(err) => LuaState::raise_error(state, &err.message),
            }
        }
    }
}

unsafe extern "C" fn moonlift_parse_code_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "parse_code") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    push_parse_result(state, parse_code_dump(&source).map_err(|e| e.render(&source)))
}

unsafe extern "C" fn moonlift_parse_module_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "parse_module") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    push_parse_result(state, parse_module_dump(&source).map_err(|e| e.render(&source)))
}

unsafe extern "C" fn moonlift_parse_expr_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "parse_expr") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    push_parse_result(state, parse_expr_dump(&source).map_err(|e| e.render(&source)))
}

unsafe extern "C" fn moonlift_parse_type_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "parse_type") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    push_parse_result(state, parse_type_dump(&source).map_err(|e| e.render(&source)))
}

unsafe extern "C" fn moonlift_parse_extern_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "parse_extern") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    push_parse_result(state, parse_externs_dump(&source).map_err(|e| e.render(&source)))
}

unsafe extern "C" fn moonlift_ast_code_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "ast_code") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    push_parse_result(state, parse_code(&source).map(|v| item_to_lua(&v)).map_err(|e| e.render(&source)))
}

unsafe extern "C" fn moonlift_ast_module_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "ast_module") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    push_parse_result(state, parse_module(&source).map(|v| module_to_lua(&v)).map_err(|e| e.render(&source)))
}

unsafe extern "C" fn moonlift_ast_expr_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "ast_expr") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    push_parse_result(
        state,
        parse_source_expr(&source)
            .map(|v| expr_to_lua(&v))
            .map_err(|e| e.render(&source)),
    )
}

unsafe extern "C" fn moonlift_ast_type_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "ast_type") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    push_parse_result(state, parse_type(&source).map(|v| type_to_lua(&v)).map_err(|e| e.render(&source)))
}

unsafe extern "C" fn moonlift_ast_extern_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "ast_extern") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    push_parse_result(state, parse_externs(&source).map(|v| externs_to_lua(&v)).map_err(|e| e.render(&source)))
}

unsafe fn push_native_param_meta(state: *mut lua_State, name: &str, ty: ScalarType) -> Result<(), LuaError> {
    LuaState::create_table(state, 0, 2);
    LuaState::set_string_field_on_top(state, "name", name)?;
    LuaState::set_string_field_on_top(state, "type", ty.name())?;
    Ok(())
}

unsafe fn push_native_func_meta(state: *mut lua_State, prepared: &PreparedCode) -> Result<(), LuaError> {
    LuaState::create_table(state, 0, 3);
    LuaState::set_string_field_on_top(state, "name", &prepared.meta.name)?;
    LuaState::set_string_field_on_top(state, "result", prepared.meta.result.name())?;
    LuaState::create_table(state, prepared.meta.params.len() as c_int, 0);
    for (i, param) in prepared.meta.params.iter().enumerate() {
        push_native_param_meta(state, &param.name, param.ty)?;
        LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
    }
    LuaState::set_field_from_top(state, -2, "params")?;
    Ok(())
}

unsafe fn push_native_module_meta(state: *mut lua_State, prepared: &PreparedModule) -> Result<(), LuaError> {
    LuaState::create_table(state, 0, 1);
    LuaState::create_table(state, prepared.funcs.len() as c_int, 0);
    for (i, func) in prepared.funcs.iter().enumerate() {
        push_native_func_meta(state, func)?;
        LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
    }
    LuaState::set_field_from_top(state, -2, "funcs")?;
    Ok(())
}

unsafe extern "C" fn moonlift_source_meta_code_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "source_meta_code") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime not installed");
    }
    match (&mut *rt_ptr).prepared_native_code(&source) {
        Ok(prepared) => match push_native_func_meta(state, &prepared) {
            Ok(()) => 1,
            Err(err) => LuaState::raise_error(state, &err.message),
        },
        Err(message) => push_compile_error(state, &message),
    }
}

unsafe extern "C" fn moonlift_source_meta_module_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "source_meta_module") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime not installed");
    }
    match (&mut *rt_ptr).prepared_native_module(&source) {
        Ok(prepared) => match push_native_module_meta(state, &prepared) {
            Ok(()) => 1,
            Err(err) => LuaState::raise_error(state, &err.message),
        },
        Err(message) => push_compile_error(state, &message),
    }
}

unsafe extern "C" fn moonlift_compile_source_code_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "compile_source_code") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime not installed");
    }
    let rt = &mut *rt_ptr;
    match rt.prepared_native_code(&source) {
        Ok(prepared) => match rt.compile_function(prepared.spec) {
            Ok(handle) => {
                LuaState::push_integer(state, handle as isize);
                1
            }
            Err(err) => push_compile_error(state, &err.message),
        },
        Err(message) => push_compile_error(state, &message),
    }
}

unsafe extern "C" fn moonlift_compile_source_module_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "compile_source_module") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime not installed");
    }
    let rt = &mut *rt_ptr;
    match rt.prepared_native_module(&source) {
        Ok(prepared) => match rt.compile_module(prepared.funcs.into_iter().map(|v| v.spec).collect()) {
            Ok(handles) => {
                LuaState::create_table(state, handles.len() as c_int, 0);
                for (i, handle) in handles.iter().enumerate() {
                    LuaState::push_integer(state, *handle as isize);
                    LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
                }
                1
            }
            Err(err) => push_compile_error(state, &err.message),
        },
        Err(message) => push_compile_error(state, &message),
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
        return push_compile_error(state, "moonlift runtime is not initialized");
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let spec = parse_function_spec(state, 1)?;
        let rt = &mut *rt_ptr;
        let handle = rt.compile_function(spec).map_err(|e| e.to_string())?;
        Ok::<u32, String>(handle)
    }));

    let handle = match result {
        Ok(Ok(handle)) => handle,
        Ok(Err(msg)) => return push_compile_error(state, &format!("moonlift compile error: {}", msg)),
        Err(panic) => {
            let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = panic.downcast_ref::<String>() {
                s.clone()
            } else {
                "moonlift compile panic".to_string()
            };
            return push_compile_error(state, &format!("moonlift compile panic: {}", msg));
        }
    };

    LuaState::push_integer(state, handle as isize);
    1
}

unsafe extern "C" fn moonlift_compile_module_lua(state: *mut lua_State) -> c_int {
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return push_compile_error(state, "moonlift runtime is not initialized");
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let specs = parse_function_spec_array(state, 1)?;
        let rt = &mut *rt_ptr;
        let handles = rt.compile_module(specs).map_err(|e| e.to_string())?;
        Ok::<Vec<u32>, String>(handles)
    }));

    let handles = match result {
        Ok(Ok(handles)) => handles,
        Ok(Err(msg)) => return push_compile_error(state, &format!("moonlift compile module error: {}", msg)),
        Err(panic) => {
            let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = panic.downcast_ref::<String>() {
                s.clone()
            } else {
                "moonlift compile module panic".to_string()
            };
            return push_compile_error(state, &format!("moonlift compile module panic: {}", msg));
        }
    };

    LuaState::create_table(state, handles.len() as c_int, 0);
    let out_idx = LuaState::gettop(state);
    for i in 0..handles.len() {
        LuaState::push_integer(state, handles[i] as isize);
        LuaState::raw_set_i_from_top(state, out_idx, (i + 1) as i64);
    }
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

unsafe extern "C" fn moonlift_call0_lua(state: *mut lua_State) -> c_int {
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
    if !params.is_empty() {
        return LuaState::raise_error(state, "moonlift call0 used on function with wrong arity");
    }
    let out = match rt.jit.call0_packed(handle) {
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

unsafe extern "C" fn moonlift_call3_lua(state: *mut lua_State) -> c_int {
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
    if params.len() != 3 {
        return LuaState::raise_error(state, "moonlift call3 used on function with wrong arity");
    }
    let a = match pack_lua_arg(state, 2, params[0]) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err),
    };
    let b = match pack_lua_arg(state, 3, params[1]) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err),
    };
    let c = match pack_lua_arg(state, 4, params[2]) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err),
    };
    let out = match rt.jit.call3_packed(handle, a, b, c) {
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

unsafe extern "C" fn moonlift_call4_lua(state: *mut lua_State) -> c_int {
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
    if params.len() != 4 {
        return LuaState::raise_error(state, "moonlift call4 used on function with wrong arity");
    }
    let a = match pack_lua_arg(state, 2, params[0]) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err),
    };
    let b = match pack_lua_arg(state, 3, params[1]) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err),
    };
    let c = match pack_lua_arg(state, 4, params[2]) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err),
    };
    let d = match pack_lua_arg(state, 5, params[3]) {
        Ok(v) => v,
        Err(err) => return LuaState::raise_error(state, &err),
    };
    let out = match rt.jit.call4_packed(handle, a, b, c, d) {
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

unsafe fn parse_function_spec_array(state: *mut lua_State, idx: c_int) -> Result<Vec<FunctionSpec>, String> {
    expect_type(state, idx, LUA_TTABLE, "moonlift.compile_module expects a table")?;
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
            return Err(format!("compile_module entry {} must be a function spec table", i));
        }
        let spec_idx = LuaState::gettop(state);
        let spec = parse_function_spec(state, spec_idx)?;
        LuaState::pop(state, 1);
        out.push(spec);
        i += 1;
    }
    Ok(out)
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
        "if" => Ok(Stmt::If {
            cond: read_expr_field(state, idx, "cond")?,
            then_body: read_stmt_array_field(state, idx, "then_body")?,
            else_body: read_stmt_array_field(state, idx, "else_body")?,
        }),
        "store" => Ok(Stmt::Store {
            ty: read_required_scalar_type_field(state, idx, "type")?,
            addr: read_expr_field(state, idx, "addr")?,
            value: read_expr_field(state, idx, "value")?,
        }),
        "stack_slot" => Ok(Stmt::StackSlot {
            name: read_required_string_field(state, idx, "name")?,
            size: read_required_u64_field(state, idx, "size")? as u32,
            align: read_required_u64_field(state, idx, "align")? as u32,
        }),
        "memcpy" => Ok(Stmt::Memcpy {
            dst: read_expr_field(state, idx, "dst")?,
            src: read_expr_field(state, idx, "src")?,
            len: read_expr_field(state, idx, "len")?,
        }),
        "memmove" => Ok(Stmt::Memmove {
            dst: read_expr_field(state, idx, "dst")?,
            src: read_expr_field(state, idx, "src")?,
            len: read_expr_field(state, idx, "len")?,
        }),
        "memset" => Ok(Stmt::Memset {
            dst: read_expr_field(state, idx, "dst")?,
            byte: read_expr_field(state, idx, "byte")?,
            len: read_expr_field(state, idx, "len")?,
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
        "select" => Ok(Expr::Select {
            cond: Box::new(read_expr_field(state, idx, "cond")?),
            then_expr: Box::new(read_expr_field(state, idx, "then_")?),
            else_expr: Box::new(read_expr_field(state, idx, "else_")?),
            ty: read_required_scalar_type_field(state, idx, "type")?,
        }),
        "load" => Ok(Expr::Load {
            ty: read_required_scalar_type_field(state, idx, "type")?,
            addr: Box::new(read_expr_field(state, idx, "addr")?),
        }),
        "stack_addr" => Ok(Expr::StackAddr {
            name: read_required_string_field(state, idx, "name")?,
        }),
        "memcmp" => Ok(Expr::Memcmp {
            a: Box::new(read_expr_field(state, idx, "a")?),
            b: Box::new(read_expr_field(state, idx, "b")?),
            len: Box::new(read_expr_field(state, idx, "len")?),
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

#[cfg(test)]
mod tests {
    use super::*;

    fn run_lua_test(source: &str) {
        let mut rt = Runtime::new().expect("runtime init");
        rt.initialize().expect("runtime bootstrap");
        let manifest = env!("CARGO_MANIFEST_DIR").replace('\\', "\\\\");
        rt.lua
            .dostring(&format!(
                "package.path = \"{0}/lua/?.lua;{0}/lua/?/init.lua;\" .. package.path",
                manifest
            ))
            .expect("package.path setup");
        rt.lua.dostring(source).expect("lua test script");
    }

    #[test]
    fn native_source_fast_path_handles_simple_scalar_funcs_and_modules() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()

local simple = code[[
func simple_add(x: i32) -> i32
    x + 2
end
]]
assert(simple.__native_source ~= nil)
local simple_h = simple()
assert(simple_h(40) == 42)

local simple_mod = module[[
func add2(x: i32) -> i32
    x + 2
end

func use_add2(x: i32) -> i32
    add2(x) * 2
end
]]
assert(simple_mod.__native_source ~= nil)
local compiled = simple_mod()
assert(compiled.use_add2(19) == 42)
"#,
        );
    }

    #[test]
    fn source_frontend_handles_returns_in_loops_and_stmt_if() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()

local maybe_answer = code[[
func maybe_answer(flag: bool) -> i32
    if flag then
        return 42
    end
    7
end
]]
local maybeh = maybe_answer()
assert(maybeh(true) == 42)
assert(maybeh(false) == 7)

local nested_return = code[[
func nested_return(limit: i32) -> i32
    var i: i32 = 0
    while i < limit do
        var j: i32 = 0
        while j < limit do
            if j == 2 then
                return 42
            end
            j = j + 1
        end
        i = i + 1
    end
    return 0
end
]]
local nestedh = nested_return()
assert(nestedh(6) == 42)

local stmt_if = code[[
func stmt_if(x: i32) -> i32
    var acc: i32 = 0
    if x > 0 then
        acc = 40
    else
        acc = 10
    end
    return acc + 2
end
]]
local stmt_if_h = stmt_if()
assert(stmt_if_h(1) == 42)
assert(stmt_if_h(-1) == 12)
"#,
        );
    }

    #[test]
    fn source_frontend_handles_switch_loop_control_and_inferred_results() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()
local ffi = require('ffi')

local infer_maybe = code[[
func infer_maybe(flag: bool)
    if flag then
        return 42
    end
    7
end
]]
local infer_maybe_h = infer_maybe()
assert(infer_maybe_h(true) == 42)
assert(infer_maybe_h(false) == 7)

local switch_loop = code[[
func switch_loop(limit: i32) -> i32
    var i: i32 = 0
    var acc: i32 = 0
    while i < limit do
        switch i do
        case 0 then
            i = i + 1
            continue
        case 4 then
            break
        default then
            acc = acc + i
        end
        i = i + 1
    end
    return acc
end
]]
local switch_loop_h = switch_loop()
assert(switch_loop_h(10) == 6)

local inferred_mod = module[[
struct Pair2
    a: i32
    b: i32
end

impl Pair2
    func sum(self: &Pair2)
        self.a + self.b
    end
end

func add2_infer(x: i32)
    x + 2
end

func use_add2_infer(x: i32)
    return add2_infer(x) * 2
end

func pair2_sum(p: &Pair2)
    return p:sum()
end
]]
local compiled = inferred_mod()
local pair = ffi.new('int32_t[2]')
pair[0] = 20
pair[1] = 22
local p = tonumber(ffi.cast('intptr_t', pair))
assert(compiled.add2_infer(40) == 42)
assert(compiled.use_add2_infer(19) == 42)
assert(compiled.pair2_sum(p) == 42)
"#,
        );
    }

    #[test]
    fn source_frontend_handles_recursive_inference_splices_and_const_array_lengths() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()

local recursive_infer = code[[
func fact(n: i32)
    if n <= 1 then
        return 1
    end
    return n * fact(n - 1)
end
]]
local facth = recursive_infer()
assert(facth(5) == 120)

local splice_infer = code[[
func from_splice()
    @{42}
end
]]
local from_splice_h = splice_infer()
assert(from_splice_h() == 42)

local array_len_mod = module[[
enum Width : u8
    One = 1
    Two = One + 1
    Four = cast<i32>(Two) * 2
end

const N = if true then cast<i32>(Width.Two) else 0 end
const M = switch Width.Two do
    case 1 then 3
    case 2 then 4
    default then 5
end
const XS = [N + M - 2]i32 { 10, 11, 12, 9 }

func array_len_ok() -> i32
    return 42
end
]]
assert(array_len_mod.Width.Four.node.value == 4)
assert(array_len_mod.XS ~= nil and array_len_mod.XS._layout.count == 4)
local compiled = array_len_mod()
assert(compiled.array_len_ok() == 42)
"#,
        );
    }

    #[test]
    fn source_frontend_module_methods_and_externs_work() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()
local ffi = require('ffi')
ffi.cdef[[ int abs(int x); ]]

local m = module[[
struct Pair
    a: i32
    b: i32
end

impl Pair
    func sum(self: &Pair) -> i32
        return self.a + self.b
    end
end

@abi("C")
extern func abs(x: i32) -> i32

func add2(x: i32) -> i32
    return x + 2
end

func pair_sum(p: &Pair) -> i32
    return p:sum()
end

func use_add2(x: i32) -> i32
    return add2(x) * 2
end

func use_abs(x: i32) -> i32
    return abs(x)
end
]]

local compiled = m()
local pair = ffi.new('int32_t[2]')
pair[0] = 20
pair[1] = 22
local p = tonumber(ffi.cast('intptr_t', pair))
assert(compiled.pair_sum(p) == 42)
assert(compiled.use_add2(19) == 42)
assert(compiled.use_abs(-42) == 42)
"#,
        );
    }

    #[test]
    fn parsed_ast_tables_pretty_print() {
        run_lua_test(
            r#"
local ml = require('moonlift')
local ast = ml.parse.code[[
func add(a: i32, b: i32) -> i32
    return a + b
end
]]
local s = tostring(ast)
assert(type(s) == 'string')
assert(s:find('tag = "func"', 1, true) ~= nil)
assert(s:find('params', 1, true) ~= nil)
assert(ml.parse.pretty(ast) == s)

local ty = ml.parse.type[[i32]]
assert(tostring(ty) == '{ tag = "path", segments = [ "i32" ] }')
"#,
        );
    }
}
