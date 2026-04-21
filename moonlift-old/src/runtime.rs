#![allow(unsafe_op_in_unsafe_fn)]

use crate::ast::{
    AggregateField, Block as AstBlock, Expr as AstExpr, ExprKind, FieldDecl, ForStmt, FuncDecl,
    FuncSig, IfExpr, IfExprBranch, IfStmt, IfStmtBranch, ImplDecl, ImplItem, Item, ItemKind,
    LoopExpr as AstLoopExpr, LoopHead as AstLoopHead, LoopNextAssign, LoopStmt as AstLoopStmt,
    LoopVarInit, MemoryStmt, ModuleAst, OpaqueDecl, Param, SliceDecl, Stmt as AstStmt,
    StructDecl, SwitchExpr, SwitchExprCase, SwitchStmt, SwitchStmtCase, TaggedUnionDecl,
    TaggedVariantDecl, TypeAliasDecl, TypeCtor, TypeExpr, UnionDecl, EnumDecl,
    EnumMemberDecl, ExternFuncDecl,
};
use crate::cranelift_jit::{
    optimize_function_spec, BinaryOp, CallTarget, CastOp, CompileStats, Expr, FunctionSpec,
    JitError, LocalDecl, MoonliftJit, ScalarType, Stmt, UnaryOp,
};
use crate::lua_ast::{expr_to_lua, externs_to_lua, item_to_lua, module_to_lua, type_to_lua};
use crate::luajit::{
    lua_State, lua_Number, LuaCFunction, LuaError, LuaState, LUA_GLOBALSINDEX, LUA_OK,
    LUA_TNIL, LUA_TSTRING, LUA_TTABLE,
};
use crate::parser::{
    parse_code, parse_code_dump, parse_expr as parse_source_expr, parse_expr_dump, parse_externs,
    parse_externs_dump, parse_module, parse_module_dump, parse_type, parse_type_dump,
};
use crate::source_native::{
    prepare_code as prepare_native_code, prepare_code_item_ast as prepare_native_code_item_ast,
    prepare_expr as prepare_native_expr, prepare_expr_ast as prepare_native_expr_ast,
    prepare_externs_items_ast as prepare_native_externs_items_ast,
    prepare_externs_meta as prepare_native_externs_meta,
    prepare_module_ast as prepare_native_module_ast,
    prepare_module_relaxed as prepare_native_module_relaxed,
    prepare_type_ast as prepare_native_type_ast, prepare_type_meta as prepare_native_type_meta,
    NativeConstMeta, NativeConstValueMeta, NativeTypeMeta, NativeTypeRefMeta, PreparedCode,
    PreparedExpr, PreparedModule,
};
use std::collections::HashMap;
use std::os::raw::{c_int, c_void};

pub struct Runtime {
    lua: LuaState,
    jit: MoonliftJit,
    native_code_cache: HashMap<String, PreparedCode>,
    native_module_cache: HashMap<String, PreparedModule>,
    native_module_meta_cache: HashMap<String, PreparedModule>,
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
            native_module_meta_cache: HashMap::new(),
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

        self.lua.new_table(0, 44);
        self.lua
            .set_cfunction_field_on_top("add", moonlift_add_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("compile", moonlift_compile_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("compile_unoptimized", moonlift_compile_unoptimized_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("compile_module", moonlift_compile_module_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("compile_module_entry", moonlift_compile_module_entry_lua as LuaCFunction)?;
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
            .set_cfunction_field_on_top("source_meta_expr", moonlift_source_meta_expr_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("source_meta_type", moonlift_source_meta_type_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("source_meta_extern", moonlift_source_meta_extern_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("compile_source_code", moonlift_compile_source_code_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top(
                "compile_source_code_unoptimized",
                moonlift_compile_source_code_unoptimized_lua as LuaCFunction,
            )?;
        self.lua
            .set_cfunction_field_on_top("compile_source_module", moonlift_compile_source_module_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top(
                "compile_source_module_entry",
                moonlift_compile_source_module_entry_lua as LuaCFunction,
            )?;
        self.lua
            .set_cfunction_field_on_top("dump_spec", moonlift_dump_spec_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("dump_optimized_spec", moonlift_dump_optimized_spec_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top("dump_source_code_spec", moonlift_dump_source_code_spec_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top(
                "dump_optimized_source_code_spec",
                moonlift_dump_optimized_source_code_spec_lua as LuaCFunction,
            )?;
        self.lua
            .set_cfunction_field_on_top("dump_disasm", moonlift_dump_disasm_lua as LuaCFunction)?;
        self.lua
            .set_cfunction_field_on_top(
                "dump_unoptimized_disasm",
                moonlift_dump_unoptimized_disasm_lua as LuaCFunction,
            )?;
        self.lua
            .set_cfunction_field_on_top(
                "dump_source_code_disasm",
                moonlift_dump_source_code_disasm_lua as LuaCFunction,
            )?;
        self.lua
            .set_cfunction_field_on_top(
                "dump_unoptimized_source_code_disasm",
                moonlift_dump_unoptimized_source_code_disasm_lua as LuaCFunction,
            )?;
        self.lua.set_global_from_top("__moonlift_backend")?;
        Ok(())
    }

    fn install_lua_bootstrap(&mut self) -> Result<(), LuaError> {
        self.lua.dostring(
            r#"
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local ffi = require('ffi')
function __moonlift_exact_int_result(lo, hi, signed)
    local box = ffi.new('uint64_t[1]')
    local parts = ffi.cast('uint32_t*', box)
    if ffi.abi('le') then
        parts[0] = lo
        parts[1] = hi
    else
        parts[0] = hi
        parts[1] = lo
    end
    local u = box[0]
    if signed then
        return ffi.cast('int64_t', u)
    end
    return u
end
"#,
        )
    }

    fn add_i32_i32(&self, a: i32, b: i32) -> i32 {
        self.jit.add_i32_i32(a, b)
    }

    fn compile_function(&mut self, spec: FunctionSpec) -> Result<u32, LuaError> {
        self.jit.compile_function(spec).map_err(jit_error)
    }

    fn compile_function_unoptimized(&mut self, spec: FunctionSpec) -> Result<u32, LuaError> {
        self.jit.compile_function_unoptimized(spec).map_err(jit_error)
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

    fn dump_disasm(&mut self, spec: &FunctionSpec) -> Result<String, LuaError> {
        self.jit.dump_disasm(spec).map_err(jit_error)
    }

    fn dump_disasm_unoptimized(&mut self, spec: &FunctionSpec) -> Result<String, LuaError> {
        self.jit.dump_disasm_unoptimized(spec).map_err(jit_error)
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
        let prepared = prepare_native_module_relaxed(source)?;
        self.native_module_cache
            .insert(source.to_string(), prepared.clone());
        Ok(prepared)
    }

    fn prepared_native_module_meta(&mut self, source: &str) -> Result<PreparedModule, String> {
        if let Some(cached) = self.native_module_meta_cache.get(source) {
            return Ok(cached.clone());
        }
        let prepared = prepare_native_module_relaxed(source)?;
        if !prepared.meta_complete {
            return Err(format!(
                "unsupported native source fast path: native module metadata export is incomplete for this source"
            ));
        }
        self.native_module_meta_cache
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

unsafe fn parse_required_string_arg(state: *mut lua_State, idx: c_int, what: &str) -> Result<String, c_int> {
    match LuaState::to_string(state, idx) {
        Some(s) => Ok(s),
        None => Err(LuaState::raise_error(
            state,
            &format!("moonlift {} expects a string at argument {}", what, idx),
        )),
    }
}

unsafe fn push_sparse_handles_table(state: *mut lua_State, handles: &[Option<u32>]) -> Result<c_int, LuaError> {
    LuaState::create_table(state, handles.len() as c_int, 0);
    let out_idx = LuaState::gettop(state);
    for (i, handle) in handles.iter().enumerate() {
        if let Some(handle) = handle {
            LuaState::push_integer(state, *handle as isize);
            LuaState::raw_set_i_from_top(state, out_idx, (i + 1) as i64);
        }
    }
    Ok(1)
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

unsafe fn push_native_param_meta(
    state: *mut lua_State,
    name: &str,
    ty: ScalarType,
    ty_ref: &NativeTypeRefMeta,
) -> Result<(), LuaError> {
    LuaState::create_table(state, 0, 3);
    LuaState::set_string_field_on_top(state, "name", name)?;
    LuaState::set_string_field_on_top(state, "type", ty.name())?;
    push_native_type_ref_meta(state, ty_ref)?;
    LuaState::set_field_from_top(state, -2, "ty_ref")?;
    Ok(())
}

unsafe fn push_native_type_ref_meta(state: *mut lua_State, meta: &NativeTypeRefMeta) -> Result<(), LuaError> {
    match meta {
        NativeTypeRefMeta::Scalar(name) => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "scalar")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
        }
        NativeTypeRefMeta::Pointer(inner) => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "pointer")?;
            push_native_type_ref_meta(state, inner)?;
            LuaState::set_field_from_top(state, -2, "inner")?;
        }
        NativeTypeRefMeta::Array { elem, len } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", "array")?;
            push_native_type_ref_meta(state, elem)?;
            LuaState::set_field_from_top(state, -2, "elem")?;
            LuaState::push_integer(state, *len as isize);
            LuaState::set_field_from_top(state, -2, "len")?;
        }
        NativeTypeRefMeta::Slice(elem) => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "slice")?;
            push_native_type_ref_meta(state, elem)?;
            LuaState::set_field_from_top(state, -2, "elem")?;
        }
        NativeTypeRefMeta::Func { params, result } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", "func")?;
            LuaState::create_table(state, params.len() as c_int, 0);
            for (i, param) in params.iter().enumerate() {
                push_native_type_ref_meta(state, param)?;
                LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
            }
            LuaState::set_field_from_top(state, -2, "params")?;
            if let Some(result) = result {
                push_native_type_ref_meta(state, result)?;
                LuaState::set_field_from_top(state, -2, "result")?;
            }
        }
        NativeTypeRefMeta::Path(name) => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "path")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
        }
    }
    Ok(())
}

unsafe fn push_native_field_meta(state: *mut lua_State, name: &str, ty: &NativeTypeRefMeta) -> Result<(), LuaError> {
    LuaState::create_table(state, 0, 2);
    LuaState::set_string_field_on_top(state, "name", name)?;
    push_native_type_ref_meta(state, ty)?;
    LuaState::set_field_from_top(state, -2, "ty")?;
    Ok(())
}

unsafe fn push_native_type_meta(state: *mut lua_State, meta: &NativeTypeMeta) -> Result<(), LuaError> {
    match meta {
        NativeTypeMeta::Struct { name, fields } | NativeTypeMeta::Union { name, fields } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(
                state,
                "tag",
                if matches!(meta, NativeTypeMeta::Struct { .. }) { "struct" } else { "union" },
            )?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            LuaState::create_table(state, fields.len() as c_int, 0);
            for (i, field) in fields.iter().enumerate() {
                push_native_field_meta(state, &field.name, &field.ty)?;
                LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
            }
            LuaState::set_field_from_top(state, -2, "fields")?;
        }
        NativeTypeMeta::TaggedUnion { name, base, variants } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", "tagged_union")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            if let Some(base) = base {
                push_native_type_ref_meta(state, base)?;
                LuaState::set_field_from_top(state, -2, "base")?;
            }
            LuaState::create_table(state, variants.len() as c_int, 0);
            for (i, variant) in variants.iter().enumerate() {
                LuaState::create_table(state, 0, 2);
                LuaState::set_string_field_on_top(state, "name", &variant.name)?;
                LuaState::create_table(state, variant.fields.len() as c_int, 0);
                for (j, field) in variant.fields.iter().enumerate() {
                    push_native_field_meta(state, &field.name, &field.ty)?;
                    LuaState::raw_set_i_from_top(state, -2, (j + 1) as i64);
                }
                LuaState::set_field_from_top(state, -2, "fields")?;
                LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
            }
            LuaState::set_field_from_top(state, -2, "variants")?;
        }
        NativeTypeMeta::Enum { name, base, members } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", "enum")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            push_native_type_ref_meta(state, base)?;
            LuaState::set_field_from_top(state, -2, "base")?;
            LuaState::create_table(state, members.len() as c_int, 0);
            for (i, member) in members.iter().enumerate() {
                LuaState::create_table(state, 0, 2);
                LuaState::set_string_field_on_top(state, "name", &member.name)?;
                LuaState::push_integer(state, member.value as isize);
                LuaState::set_field_from_top(state, -2, "value")?;
                LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
            }
            LuaState::set_field_from_top(state, -2, "members")?;
        }
        NativeTypeMeta::Slice { name, elem } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", "slice")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            push_native_type_ref_meta(state, elem)?;
            LuaState::set_field_from_top(state, -2, "elem")?;
        }
        NativeTypeMeta::TypeAlias { name, ty } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", "type_alias")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            push_native_type_ref_meta(state, ty)?;
            LuaState::set_field_from_top(state, -2, "ty")?;
        }
    }
    Ok(())
}

unsafe fn push_native_const_value_meta(state: *mut lua_State, value: &NativeConstValueMeta) -> Result<(), LuaError> {
    match value {
        NativeConstValueMeta::Bool(v) => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "bool")?;
            LuaState::push_boolean(state, *v);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        NativeConstValueMeta::Int(v) => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "int")?;
            LuaState::push_integer(state, *v as isize);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        NativeConstValueMeta::Float(v) => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "float")?;
            LuaState::push_number(state, *v);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        NativeConstValueMeta::Aggregate { fields } => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "aggregate")?;
            LuaState::create_table(state, fields.len() as c_int, 0);
            for (i, field) in fields.iter().enumerate() {
                LuaState::create_table(state, 0, 2);
                if let Some(name) = &field.name {
                    LuaState::set_string_field_on_top(state, "name", name)?;
                }
                push_native_const_value_meta(state, &field.value)?;
                LuaState::set_field_from_top(state, -2, "value")?;
                LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
            }
            LuaState::set_field_from_top(state, -2, "fields")?;
        }
    }
    Ok(())
}

unsafe fn push_native_const_meta(state: *mut lua_State, meta: &NativeConstMeta) -> Result<(), LuaError> {
    LuaState::create_table(state, 0, 3);
    LuaState::set_string_field_on_top(state, "name", &meta.name)?;
    push_native_type_ref_meta(state, &meta.ty)?;
    LuaState::set_field_from_top(state, -2, "ty")?;
    push_native_const_value_meta(state, &meta.value)?;
    LuaState::set_field_from_top(state, -2, "value")?;
    Ok(())
}

unsafe fn push_native_func_meta(state: *mut lua_State, prepared: &PreparedCode) -> Result<(), LuaError> {
    LuaState::create_table(state, 0, 5);
    LuaState::set_string_field_on_top(state, "name", &prepared.meta.name)?;
    LuaState::set_string_field_on_top(state, "result", prepared.meta.result.name())?;
    if let Some(owner) = &prepared.meta.owner {
        LuaState::set_string_field_on_top(state, "owner", owner)?;
    }
    if let Some(method_name) = &prepared.meta.method_name {
        LuaState::set_string_field_on_top(state, "method", method_name)?;
    }
    LuaState::create_table(state, prepared.meta.params.len() as c_int, 0);
    for (i, param) in prepared.meta.params.iter().enumerate() {
        push_native_param_meta(state, &param.name, param.ty, &param.ty_ref)?;
        LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
    }
    LuaState::set_field_from_top(state, -2, "params")?;
    Ok(())
}

unsafe fn push_native_extern_meta(state: *mut lua_State, ext: &crate::source_native::NativeExternMeta) -> Result<(), LuaError> {
    LuaState::create_table(state, 0, 4);
    LuaState::set_string_field_on_top(state, "name", &ext.name)?;
    LuaState::set_string_field_on_top(state, "symbol", &ext.symbol)?;
    LuaState::set_string_field_on_top(state, "result", ext.result.name())?;
    LuaState::create_table(state, ext.params.len() as c_int, 0);
    for (i, param) in ext.params.iter().enumerate() {
        push_native_param_meta(state, &param.name, param.ty, &param.ty_ref)?;
        LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
    }
    LuaState::set_field_from_top(state, -2, "params")?;
    Ok(())
}

unsafe fn push_native_module_meta(state: *mut lua_State, prepared: &PreparedModule) -> Result<(), LuaError> {
    LuaState::create_table(state, 0, 4);
    LuaState::create_table(state, prepared.funcs.len() as c_int, 0);
    for (i, func) in prepared.funcs.iter().enumerate() {
        push_native_func_meta(state, func)?;
        LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
    }
    LuaState::set_field_from_top(state, -2, "funcs")?;
    LuaState::create_table(state, prepared.types.len() as c_int, 0);
    for (i, ty) in prepared.types.iter().enumerate() {
        push_native_type_meta(state, ty)?;
        LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
    }
    LuaState::set_field_from_top(state, -2, "types")?;
    LuaState::create_table(state, prepared.externs.len() as c_int, 0);
    for (i, ext) in prepared.externs.iter().enumerate() {
        push_native_extern_meta(state, ext)?;
        LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
    }
    LuaState::set_field_from_top(state, -2, "externs")?;
    LuaState::create_table(state, prepared.consts.len() as c_int, 0);
    for (i, c) in prepared.consts.iter().enumerate() {
        push_native_const_meta(state, c)?;
        LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
    }
    LuaState::set_field_from_top(state, -2, "consts")?;
    Ok(())
}

fn unary_tag(op: UnaryOp) -> &'static str {
    match op {
        UnaryOp::Neg => "neg",
        UnaryOp::Not => "not",
        UnaryOp::Bnot => "bnot",
    }
}

fn binary_tag(op: BinaryOp) -> &'static str {
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
        BinaryOp::Band => "band",
        BinaryOp::Bor => "bor",
        BinaryOp::Bxor => "bxor",
        BinaryOp::Shl => "shl",
        BinaryOp::ShrU => "shr_u",
        BinaryOp::ShrS => "shr_s",
    }
}

fn cast_tag(op: CastOp) -> &'static str {
    match op {
        CastOp::Cast => "cast",
        CastOp::Trunc => "trunc",
        CastOp::Zext => "zext",
        CastOp::Sext => "sext",
        CastOp::Bitcast => "bitcast",
    }
}

unsafe fn push_type_array_meta(state: *mut lua_State, tys: &[ScalarType]) -> Result<(), LuaError> {
    LuaState::create_table(state, tys.len() as c_int, 0);
    for (i, ty) in tys.iter().enumerate() {
        LuaState::push_string(state, ty.name())?;
        LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
    }
    Ok(())
}

unsafe fn push_ir_const_expr(state: *mut lua_State, ty: ScalarType, bits: u64) -> Result<(), LuaError> {
    match ty {
        ScalarType::Bool => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "bool")?;
            LuaState::push_boolean(state, bits != 0);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        ScalarType::I8 => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "i8")?;
            LuaState::push_integer(state, (bits as u8 as i8) as isize);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        ScalarType::I16 => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "i16")?;
            LuaState::push_integer(state, (bits as u16 as i16) as isize);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        ScalarType::I32 => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "i32")?;
            LuaState::push_integer(state, (bits as u32 as i32) as isize);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        ScalarType::I64 => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "i64")?;
            LuaState::push_integer(state, bits as i64 as isize);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        ScalarType::U8 => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "u8")?;
            LuaState::push_integer(state, (bits as u8) as isize);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        ScalarType::U16 => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "u16")?;
            LuaState::push_integer(state, (bits as u16) as isize);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        ScalarType::U32 => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "u32")?;
            LuaState::push_integer(state, (bits as u32) as isize);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        ScalarType::U64 => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "u64")?;
            LuaState::push_number(state, bits as lua_Number);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        ScalarType::F32 => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "f32")?;
            LuaState::push_number(state, f32::from_bits(bits as u32) as lua_Number);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        ScalarType::F64 => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "f64")?;
            LuaState::push_number(state, f64::from_bits(bits) as lua_Number);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        ScalarType::Ptr => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "ptr")?;
            LuaState::push_number(state, bits as lua_Number);
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        ScalarType::Void => {
            return Err(LuaError {
                code: -1,
                message: "cannot serialize void expression constant to lua".to_string(),
            })
        }
    }
    Ok(())
}

unsafe fn push_ir_call_target_fields(state: *mut lua_State, target: &CallTarget) -> Result<(), LuaError> {
    match target {
        CallTarget::Direct { name, params, result } => {
            LuaState::set_string_field_on_top(state, "callee_kind", "direct")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            push_type_array_meta(state, params)?;
            LuaState::set_field_from_top(state, -2, "params")?;
            LuaState::set_string_field_on_top(state, "result", result.name())?;
        }
        CallTarget::Indirect { addr, params, result, packed } => {
            LuaState::set_string_field_on_top(state, "callee_kind", "indirect")?;
            LuaState::push_boolean(state, *packed);
            LuaState::set_field_from_top(state, -2, "packed")?;
            push_ir_expr(state, addr)?;
            LuaState::set_field_from_top(state, -2, "addr")?;
            push_type_array_meta(state, params)?;
            LuaState::set_field_from_top(state, -2, "params")?;
            LuaState::set_string_field_on_top(state, "result", result.name())?;
        }
    }
    Ok(())
}

unsafe fn push_ir_expr_array(state: *mut lua_State, exprs: &[Expr]) -> Result<(), LuaError> {
    LuaState::create_table(state, exprs.len() as c_int, 0);
    for (i, expr) in exprs.iter().enumerate() {
        push_ir_expr(state, expr)?;
        LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
    }
    Ok(())
}

unsafe fn push_ir_stmt_array(state: *mut lua_State, stmts: &[Stmt]) -> Result<(), LuaError> {
    LuaState::create_table(state, stmts.len() as c_int, 0);
    for (i, stmt) in stmts.iter().enumerate() {
        push_ir_stmt(state, stmt)?;
        LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
    }
    Ok(())
}

unsafe fn push_ir_loop_var_array(state: *mut lua_State, vars: &[crate::cranelift_jit::LoopVar]) -> Result<(), LuaError> {
    LuaState::create_table(state, vars.len() as c_int, 0);
    for (i, var) in vars.iter().enumerate() {
        LuaState::create_table(state, 0, 3);
        LuaState::set_string_field_on_top(state, "name", &var.name)?;
        LuaState::set_string_field_on_top(state, "type", var.ty.name())?;
        push_ir_expr(state, &var.init)?;
        LuaState::set_field_from_top(state, -2, "init")?;
        LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64);
    }
    Ok(())
}

unsafe fn push_ir_expr(state: *mut lua_State, expr: &Expr) -> Result<(), LuaError> {
    match expr {
        Expr::Arg { index, ty } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", "arg")?;
            LuaState::push_integer(state, *index as isize);
            LuaState::set_field_from_top(state, -2, "index")?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
        }
        Expr::Local { name, ty } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", "local")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
        }
        Expr::Const { ty, bits } => push_ir_const_expr(state, *ty, *bits)?,
        Expr::Unary { op, ty, value } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", unary_tag(*op))?;
            if !matches!(op, UnaryOp::Not) {
                LuaState::set_string_field_on_top(state, "type", ty.name())?;
            }
            push_ir_expr(state, value)?;
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        Expr::Binary { op, ty, lhs, rhs } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", binary_tag(*op))?;
            if !matches!(op, BinaryOp::Eq | BinaryOp::Ne | BinaryOp::Lt | BinaryOp::Le | BinaryOp::Gt | BinaryOp::Ge | BinaryOp::And | BinaryOp::Or) {
                LuaState::set_string_field_on_top(state, "type", ty.name())?;
            }
            push_ir_expr(state, lhs)?;
            LuaState::set_field_from_top(state, -2, "lhs")?;
            push_ir_expr(state, rhs)?;
            LuaState::set_field_from_top(state, -2, "rhs")?;
        }
        Expr::Let { name, ty, init, body } => {
            LuaState::create_table(state, 0, 5);
            LuaState::set_string_field_on_top(state, "tag", "let")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
            push_ir_expr(state, init)?;
            LuaState::set_field_from_top(state, -2, "init")?;
            push_ir_expr(state, body)?;
            LuaState::set_field_from_top(state, -2, "body")?;
        }
        Expr::Block { stmts, result, ty } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", "block")?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
            push_ir_stmt_array(state, stmts)?;
            LuaState::set_field_from_top(state, -2, "stmts")?;
            push_ir_expr(state, result)?;
            LuaState::set_field_from_top(state, -2, "result")?;
        }
        Expr::If { cond, then_expr, else_expr, ty } => {
            LuaState::create_table(state, 0, 5);
            LuaState::set_string_field_on_top(state, "tag", "if")?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
            push_ir_expr(state, cond)?;
            LuaState::set_field_from_top(state, -2, "cond")?;
            push_ir_expr(state, then_expr)?;
            LuaState::set_field_from_top(state, -2, "then_")?;
            push_ir_expr(state, else_expr)?;
            LuaState::set_field_from_top(state, -2, "else_")?;
        }
        Expr::Load { ty, addr } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", "load")?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
            push_ir_expr(state, addr)?;
            LuaState::set_field_from_top(state, -2, "addr")?;
        }
        Expr::IndexAddr {
            base,
            index,
            elem_size,
            limit,
        } => {
            LuaState::create_table(state, 0, 6);
            LuaState::set_string_field_on_top(state, "tag", "index_addr")?;
            LuaState::set_string_field_on_top(state, "type", "ptr")?;
            push_ir_expr(state, base)?;
            LuaState::set_field_from_top(state, -2, "base")?;
            push_ir_expr(state, index)?;
            LuaState::set_field_from_top(state, -2, "index")?;
            LuaState::push_number(state, *elem_size as lua_Number);
            LuaState::set_field_from_top(state, -2, "elem_size")?;
            if let Some(limit_expr) = limit {
                push_ir_expr(state, limit_expr)?;
                LuaState::set_field_from_top(state, -2, "limit")?;
            }
        }
        Expr::StackAddr { name } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", "stack_addr")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            LuaState::set_string_field_on_top(state, "type", "ptr")?;
        }
        Expr::Memcmp { a, b, len } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", "memcmp")?;
            push_ir_expr(state, a)?;
            LuaState::set_field_from_top(state, -2, "a")?;
            push_ir_expr(state, b)?;
            LuaState::set_field_from_top(state, -2, "b")?;
            push_ir_expr(state, len)?;
            LuaState::set_field_from_top(state, -2, "len")?;
        }
        Expr::Cast { op, ty, value } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", cast_tag(*op))?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
            push_ir_expr(state, value)?;
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        Expr::Call { target, ty, args } => {
            LuaState::create_table(state, 0, 6);
            LuaState::set_string_field_on_top(state, "tag", "call")?;
            push_ir_call_target_fields(state, target)?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
            push_ir_expr_array(state, args)?;
            LuaState::set_field_from_top(state, -2, "args")?;
        }
        Expr::Select { cond, then_expr, else_expr, ty } => {
            LuaState::create_table(state, 0, 5);
            LuaState::set_string_field_on_top(state, "tag", "select")?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
            push_ir_expr(state, cond)?;
            LuaState::set_field_from_top(state, -2, "cond")?;
            push_ir_expr(state, then_expr)?;
            LuaState::set_field_from_top(state, -2, "then_")?;
            push_ir_expr(state, else_expr)?;
            LuaState::set_field_from_top(state, -2, "else_")?;
        }
    }
    Ok(())
}

unsafe fn push_ir_stmt(state: *mut lua_State, stmt: &Stmt) -> Result<(), LuaError> {
    match stmt {
        Stmt::Let { name, ty, init } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", "let")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
            push_ir_expr(state, init)?;
            LuaState::set_field_from_top(state, -2, "init")?;
        }
        Stmt::Var { name, ty, init } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", "var")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
            push_ir_expr(state, init)?;
            LuaState::set_field_from_top(state, -2, "init")?;
        }
        Stmt::Set { name, value } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", "set")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            push_ir_expr(state, value)?;
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        Stmt::While { cond, body } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", "while")?;
            push_ir_expr(state, cond)?;
            LuaState::set_field_from_top(state, -2, "cond")?;
            push_ir_stmt_array(state, body)?;
            LuaState::set_field_from_top(state, -2, "body")?;
        }
        Stmt::LoopWhile { vars, cond, body, next } => {
            LuaState::create_table(state, 0, 5);
            LuaState::set_string_field_on_top(state, "tag", "loop_while")?;
            push_ir_loop_var_array(state, vars)?;
            LuaState::set_field_from_top(state, -2, "vars")?;
            push_ir_expr(state, cond)?;
            LuaState::set_field_from_top(state, -2, "cond")?;
            push_ir_stmt_array(state, body)?;
            LuaState::set_field_from_top(state, -2, "body")?;
            push_ir_expr_array(state, next)?;
            LuaState::set_field_from_top(state, -2, "next")?;
        }
        Stmt::ForRange { name, ty, start, finish, step, dir, inclusive, scoped, body } => {
            LuaState::create_table(state, 0, 9);
            LuaState::set_string_field_on_top(state, "tag", "for_range")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
            push_ir_expr(state, start)?;
            LuaState::set_field_from_top(state, -2, "start")?;
            push_ir_expr(state, finish)?;
            LuaState::set_field_from_top(state, -2, "finish")?;
            push_ir_expr(state, step)?;
            LuaState::set_field_from_top(state, -2, "step")?;
            if let Some(dir) = dir {
                LuaState::set_string_field_on_top(state, "dir", dir.name())?;
            }
            LuaState::push_boolean(state, *inclusive);
            LuaState::set_field_from_top(state, -2, "inclusive")?;
            LuaState::push_boolean(state, *scoped);
            LuaState::set_field_from_top(state, -2, "scoped")?;
            push_ir_stmt_array(state, body)?;
            LuaState::set_field_from_top(state, -2, "body")?;
        }
        Stmt::If { cond, then_body, else_body } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", "if")?;
            push_ir_expr(state, cond)?;
            LuaState::set_field_from_top(state, -2, "cond")?;
            push_ir_stmt_array(state, then_body)?;
            LuaState::set_field_from_top(state, -2, "then_body")?;
            push_ir_stmt_array(state, else_body)?;
            LuaState::set_field_from_top(state, -2, "else_body")?;
        }
        Stmt::Store { ty, addr, value } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", "store")?;
            LuaState::set_string_field_on_top(state, "type", ty.name())?;
            push_ir_expr(state, addr)?;
            LuaState::set_field_from_top(state, -2, "addr")?;
            push_ir_expr(state, value)?;
            LuaState::set_field_from_top(state, -2, "value")?;
        }
        Stmt::BoundsCheck { index, limit } => {
            LuaState::create_table(state, 0, 3);
            LuaState::set_string_field_on_top(state, "tag", "bounds_check")?;
            push_ir_expr(state, index)?;
            LuaState::set_field_from_top(state, -2, "index")?;
            push_ir_expr(state, limit)?;
            LuaState::set_field_from_top(state, -2, "limit")?;
        }
        Stmt::Assert { cond } => {
            LuaState::create_table(state, 0, 2);
            LuaState::set_string_field_on_top(state, "tag", "assert")?;
            push_ir_expr(state, cond)?;
            LuaState::set_field_from_top(state, -2, "cond")?;
        }
        Stmt::StackSlot { name, size, align } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", "stack_slot")?;
            LuaState::set_string_field_on_top(state, "name", name)?;
            LuaState::push_number(state, *size as lua_Number);
            LuaState::set_field_from_top(state, -2, "size")?;
            LuaState::push_number(state, *align as lua_Number);
            LuaState::set_field_from_top(state, -2, "align")?;
        }
        Stmt::Memcpy { dst, src, len } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", "memcpy")?;
            push_ir_expr(state, dst)?;
            LuaState::set_field_from_top(state, -2, "dst")?;
            push_ir_expr(state, src)?;
            LuaState::set_field_from_top(state, -2, "src")?;
            push_ir_expr(state, len)?;
            LuaState::set_field_from_top(state, -2, "len")?;
        }
        Stmt::Memmove { dst, src, len } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", "memmove")?;
            push_ir_expr(state, dst)?;
            LuaState::set_field_from_top(state, -2, "dst")?;
            push_ir_expr(state, src)?;
            LuaState::set_field_from_top(state, -2, "src")?;
            push_ir_expr(state, len)?;
            LuaState::set_field_from_top(state, -2, "len")?;
        }
        Stmt::Memset { dst, byte, len } => {
            LuaState::create_table(state, 0, 4);
            LuaState::set_string_field_on_top(state, "tag", "memset")?;
            push_ir_expr(state, dst)?;
            LuaState::set_field_from_top(state, -2, "dst")?;
            push_ir_expr(state, byte)?;
            LuaState::set_field_from_top(state, -2, "byte")?;
            push_ir_expr(state, len)?;
            LuaState::set_field_from_top(state, -2, "len")?;
        }
        Stmt::Call { target, args } => {
            LuaState::create_table(state, 0, 5);
            LuaState::set_string_field_on_top(state, "tag", "call")?;
            push_ir_call_target_fields(state, target)?;
            push_ir_expr_array(state, args)?;
            LuaState::set_field_from_top(state, -2, "args")?;
        }
        Stmt::Break => {
            LuaState::create_table(state, 0, 1);
            LuaState::set_string_field_on_top(state, "tag", "break")?;
        }
        Stmt::Continue => {
            LuaState::create_table(state, 0, 1);
            LuaState::set_string_field_on_top(state, "tag", "continue")?;
        }
    }
    Ok(())
}

unsafe fn push_native_expr_meta(state: *mut lua_State, prepared: &PreparedExpr) -> Result<(), LuaError> {
    LuaState::create_table(state, 0, 2);
    push_ir_expr(state, &prepared.expr)?;
    LuaState::set_field_from_top(state, -2, "node")?;
    LuaState::set_string_field_on_top(state, "type", prepared.ty.name())?;
    Ok(())
}

fn source_has_host_metaprogramming(source: &str) -> bool {
    source.contains("@{") || source.contains("?")
}

unsafe fn optional_table_arg(state: *mut lua_State, idx: c_int) -> Option<c_int> {
    (LuaState::get_type(state, idx) == LUA_TTABLE).then_some(idx)
}

unsafe fn optional_host_env_arg(state: *mut lua_State) -> Option<c_int> {
    optional_table_arg(state, 2)
}

unsafe fn with_eval_host_splice_source<T, F>(
    state: *mut lua_State,
    env_idx: Option<c_int>,
    source: &str,
    context: &str,
    f: F,
) -> Result<T, String>
where
    F: FnOnce(&str, Option<c_int>) -> Result<T, String>,
{
    LuaState::get_field(state, crate::luajit::LUA_GLOBALSINDEX, "__moonlift_eval_source_splice")
        .map_err(|e| e.message)?;
    if let Some(idx) = env_idx {
        LuaState::push_value(state, idx);
    } else {
        LuaState::push_nil(state);
    }
    LuaState::push_string(state, source).map_err(|e| e.message)?;
    LuaState::push_string(state, context).map_err(|e| e.message)?;
    let rc = LuaState::pcall(state, 3, 1);
    if rc != LUA_OK {
        let msg = LuaState::to_string(state, -1)
            .unwrap_or_else(|| "moonlift host splice evaluation failed".to_string());
        LuaState::pop(state, 1);
        return Err(msg);
    }

    let result_ty = LuaState::get_type(state, -1);
    if result_ty == LUA_TSTRING {
        let out = LuaState::to_string(state, -1)
            .ok_or_else(|| "moonlift host splice helper must return a string".to_string())?;
        LuaState::pop(state, 1);
        return f(&out, env_idx);
    }
    if result_ty == LUA_TTABLE {
        let result_idx = LuaState::gettop(state);
        LuaState::get_field(state, result_idx, "source").map_err(|e| e.message)?;
        let out = LuaState::to_string(state, -1).ok_or_else(|| {
            "moonlift host splice helper table must contain a string field 'source'".to_string()
        })?;
        LuaState::pop(state, 1);

        LuaState::get_field(state, result_idx, "env").map_err(|e| e.message)?;
        let pushed_env_idx = if LuaState::get_type(state, -1) == LUA_TTABLE {
            Some(LuaState::gettop(state))
        } else {
            LuaState::pop(state, 1);
            None
        };
        let effective_env = pushed_env_idx.or(env_idx);
        let result = f(&out, effective_env);
        if pushed_env_idx.is_some() {
            LuaState::pop(state, 1);
        }
        LuaState::pop(state, 1);
        return result;
    }

    LuaState::pop(state, 1);
    Err("moonlift host splice helper must return a string or { source = string, env = table? }"
        .to_string())
}

fn resolve_type_splices(state: *mut lua_State, env_idx: Option<c_int>, ty: &TypeExpr) -> Result<TypeExpr, String> {
    Ok(match ty {
        TypeExpr::Path(v) => TypeExpr::Path(v.clone()),
        TypeExpr::Pointer { inner, span } => TypeExpr::Pointer {
            inner: Box::new(resolve_type_splices(state, env_idx, inner)?),
            span: *span,
        },
        TypeExpr::Array { len, elem, span } => TypeExpr::Array {
            len: Box::new(resolve_expr_splices(state, env_idx, len)?),
            elem: Box::new(resolve_type_splices(state, env_idx, elem)?),
            span: *span,
        },
        TypeExpr::Slice { elem, span } => TypeExpr::Slice {
            elem: Box::new(resolve_type_splices(state, env_idx, elem)?),
            span: *span,
        },
        TypeExpr::Func { params, result, span } => TypeExpr::Func {
            params: params
                .iter()
                .map(|v| resolve_type_splices(state, env_idx, v))
                .collect::<Result<Vec<_>, _>>()?,
            result: result
                .as_ref()
                .map(|v| resolve_type_splices(state, env_idx, v))
                .transpose()?
                .map(Box::new),
            span: *span,
        },
        TypeExpr::Splice { source, .. } => unsafe {
            with_eval_host_splice_source(state, env_idx, source, "type", |snippet, next_env| {
                let parsed = parse_type(snippet).map_err(|e| e.render(snippet))?;
                resolve_type_splices(state, next_env, &parsed)
            })?
        },
        TypeExpr::Group { inner, .. } => resolve_type_splices(state, env_idx, inner)?,
    })
}

fn resolve_type_ctor_splices(
    state: *mut lua_State,
    env_idx: Option<c_int>,
    ctor: &TypeCtor,
) -> Result<TypeCtor, String> {
    Ok(match ctor {
        TypeCtor::Path(v) => TypeCtor::Path(v.clone()),
        TypeCtor::Array { len, elem, span } => TypeCtor::Array {
            len: Box::new(resolve_expr_splices(state, env_idx, len)?),
            elem: Box::new(resolve_type_splices(state, env_idx, elem)?),
            span: *span,
        },
    })
}

fn resolve_block_splices(state: *mut lua_State, env_idx: Option<c_int>, block: &AstBlock) -> Result<AstBlock, String> {
    Ok(AstBlock {
        stmts: block
            .stmts
            .iter()
            .map(|stmt| resolve_stmt_splices(state, env_idx, stmt))
            .collect::<Result<Vec<_>, _>>()?,
        span: block.span,
    })
}

fn resolve_func_sig_splices(
    state: *mut lua_State,
    env_idx: Option<c_int>,
    sig: &FuncSig,
) -> Result<FuncSig, String> {
    Ok(FuncSig {
        name: sig.name.clone(),
        params: sig
            .params
            .iter()
            .map(|param| {
                Ok(Param {
                    name: param.name.clone(),
                    ty: resolve_type_splices(state, env_idx, &param.ty)?,
                    span: param.span,
                })
            })
            .collect::<Result<Vec<_>, String>>()?,
        result: sig
            .result
            .as_ref()
            .map(|v| resolve_type_splices(state, env_idx, v))
            .transpose()?,
        span: sig.span,
    })
}

fn resolve_func_splices(state: *mut lua_State, env_idx: Option<c_int>, func: &FuncDecl) -> Result<FuncDecl, String> {
    Ok(FuncDecl {
        sig: resolve_func_sig_splices(state, env_idx, &func.sig)?,
        body: resolve_block_splices(state, env_idx, &func.body)?,
        span: func.span,
    })
}

fn resolve_loop_var_init_splices(
    state: *mut lua_State,
    env_idx: Option<c_int>,
    var: &LoopVarInit,
) -> Result<LoopVarInit, String> {
    Ok(LoopVarInit {
        name: var.name.clone(),
        ty: resolve_type_splices(state, env_idx, &var.ty)?,
        init: resolve_expr_splices(state, env_idx, &var.init)?,
        span: var.span,
    })
}

fn resolve_loop_next_assign_splices(
    state: *mut lua_State,
    env_idx: Option<c_int>,
    next: &LoopNextAssign,
) -> Result<LoopNextAssign, String> {
    Ok(LoopNextAssign {
        name: next.name.clone(),
        value: resolve_expr_splices(state, env_idx, &next.value)?,
        span: next.span,
    })
}

fn resolve_loop_head_splices(
    state: *mut lua_State,
    env_idx: Option<c_int>,
    head: &AstLoopHead,
) -> Result<AstLoopHead, String> {
    Ok(match head {
        AstLoopHead::While { vars, cond, span } => AstLoopHead::While {
            vars: vars
                .iter()
                .map(|v| resolve_loop_var_init_splices(state, env_idx, v))
                .collect::<Result<Vec<_>, _>>()?,
            cond: Box::new(resolve_expr_splices(state, env_idx, cond)?),
            span: *span,
        },
        AstLoopHead::Over {
            index,
            domain,
            carries,
            span,
        } => AstLoopHead::Over {
            index: index.clone(),
            domain: Box::new(resolve_expr_splices(state, env_idx, domain)?),
            carries: carries
                .iter()
                .map(|v| resolve_loop_var_init_splices(state, env_idx, v))
                .collect::<Result<Vec<_>, _>>()?,
            span: *span,
        },
    })
}

fn resolve_expr_splices(state: *mut lua_State, env_idx: Option<c_int>, expr: &AstExpr) -> Result<AstExpr, String> {
    Ok(match &expr.kind {
        ExprKind::Path(v) => AstExpr {
            kind: ExprKind::Path(v.clone()),
            span: expr.span,
        },
        ExprKind::Number(v) => AstExpr {
            kind: ExprKind::Number(v.clone()),
            span: expr.span,
        },
        ExprKind::Bool(v) => AstExpr {
            kind: ExprKind::Bool(*v),
            span: expr.span,
        },
        ExprKind::Nil => AstExpr {
            kind: ExprKind::Nil,
            span: expr.span,
        },
        ExprKind::String(v) => AstExpr {
            kind: ExprKind::String(v.clone()),
            span: expr.span,
        },
        ExprKind::Aggregate { ctor, fields } => AstExpr {
            kind: ExprKind::Aggregate {
                ctor: resolve_type_ctor_splices(state, env_idx, ctor)?,
                fields: fields
                    .iter()
                    .map(|field| {
                        Ok(match field {
                            AggregateField::Named { name, value, span } => AggregateField::Named {
                                name: name.clone(),
                                value: resolve_expr_splices(state, env_idx, value)?,
                                span: *span,
                            },
                            AggregateField::Positional { value, span } => AggregateField::Positional {
                                value: resolve_expr_splices(state, env_idx, value)?,
                                span: *span,
                            },
                        })
                    })
                    .collect::<Result<Vec<_>, String>>()?,
            },
            span: expr.span,
        },
        ExprKind::Cast { kind, ty, value } => AstExpr {
            kind: ExprKind::Cast {
                kind: kind.clone(),
                ty: resolve_type_splices(state, env_idx, ty)?,
                value: Box::new(resolve_expr_splices(state, env_idx, value)?),
            },
            span: expr.span,
        },
        ExprKind::SizeOf(ty) => AstExpr {
            kind: ExprKind::SizeOf(resolve_type_splices(state, env_idx, ty)?),
            span: expr.span,
        },
        ExprKind::AlignOf(ty) => AstExpr {
            kind: ExprKind::AlignOf(resolve_type_splices(state, env_idx, ty)?),
            span: expr.span,
        },
        ExprKind::OffsetOf { ty, field } => AstExpr {
            kind: ExprKind::OffsetOf {
                ty: resolve_type_splices(state, env_idx, ty)?,
                field: field.clone(),
            },
            span: expr.span,
        },
        ExprKind::Load { ty, ptr } => AstExpr {
            kind: ExprKind::Load {
                ty: resolve_type_splices(state, env_idx, ty)?,
                ptr: Box::new(resolve_expr_splices(state, env_idx, ptr)?),
            },
            span: expr.span,
        },
        ExprKind::Memcmp { a, b, len } => AstExpr {
            kind: ExprKind::Memcmp {
                a: Box::new(resolve_expr_splices(state, env_idx, a)?),
                b: Box::new(resolve_expr_splices(state, env_idx, b)?),
                len: Box::new(resolve_expr_splices(state, env_idx, len)?),
            },
            span: expr.span,
        },
        ExprKind::Block(block) => AstExpr {
            kind: ExprKind::Block(resolve_block_splices(state, env_idx, block)?),
            span: expr.span,
        },
        ExprKind::If(v) => AstExpr {
            kind: ExprKind::If(IfExpr {
                branches: v
                    .branches
                    .iter()
                    .map(|branch| {
                        Ok(IfExprBranch {
                            cond: resolve_expr_splices(state, env_idx, &branch.cond)?,
                            value: resolve_expr_splices(state, env_idx, &branch.value)?,
                            span: branch.span,
                        })
                    })
                    .collect::<Result<Vec<_>, String>>()?,
                else_branch: Box::new(resolve_expr_splices(state, env_idx, &v.else_branch)?),
                span: v.span,
            }),
            span: expr.span,
        },
        ExprKind::Switch(v) => AstExpr {
            kind: ExprKind::Switch(SwitchExpr {
                value: Box::new(resolve_expr_splices(state, env_idx, &v.value)?),
                cases: v
                    .cases
                    .iter()
                    .map(|case| {
                        Ok(SwitchExprCase {
                            value: resolve_expr_splices(state, env_idx, &case.value)?,
                            body: resolve_expr_splices(state, env_idx, &case.body)?,
                            span: case.span,
                        })
                    })
                    .collect::<Result<Vec<_>, String>>()?,
                default: Box::new(resolve_expr_splices(state, env_idx, &v.default)?),
                span: v.span,
            }),
            span: expr.span,
        },
        ExprKind::Loop(v) => AstExpr {
            kind: ExprKind::Loop(AstLoopExpr {
                head: resolve_loop_head_splices(state, env_idx, &v.head)?,
                body: resolve_block_splices(state, env_idx, &v.body)?,
                next: v
                    .next
                    .iter()
                    .map(|entry| resolve_loop_next_assign_splices(state, env_idx, entry))
                    .collect::<Result<Vec<_>, _>>()?,
                result: Box::new(resolve_expr_splices(state, env_idx, &v.result)?),
                span: v.span,
            }),
            span: expr.span,
        },
        ExprKind::Unary { op, expr: inner } => AstExpr {
            kind: ExprKind::Unary {
                op: op.clone(),
                expr: Box::new(resolve_expr_splices(state, env_idx, inner)?),
            },
            span: expr.span,
        },
        ExprKind::Binary { op, lhs, rhs } => AstExpr {
            kind: ExprKind::Binary {
                op: op.clone(),
                lhs: Box::new(resolve_expr_splices(state, env_idx, lhs)?),
                rhs: Box::new(resolve_expr_splices(state, env_idx, rhs)?),
            },
            span: expr.span,
        },
        ExprKind::Field { base, name } => AstExpr {
            kind: ExprKind::Field {
                base: Box::new(resolve_expr_splices(state, env_idx, base)?),
                name: name.clone(),
            },
            span: expr.span,
        },
        ExprKind::Index { base, index } => AstExpr {
            kind: ExprKind::Index {
                base: Box::new(resolve_expr_splices(state, env_idx, base)?),
                index: Box::new(resolve_expr_splices(state, env_idx, index)?),
            },
            span: expr.span,
        },
        ExprKind::Call { callee, args } => AstExpr {
            kind: ExprKind::Call {
                callee: Box::new(resolve_expr_splices(state, env_idx, callee)?),
                args: args
                    .iter()
                    .map(|arg| resolve_expr_splices(state, env_idx, arg))
                    .collect::<Result<Vec<_>, _>>()?,
            },
            span: expr.span,
        },
        ExprKind::MethodCall { receiver, method, args } => AstExpr {
            kind: ExprKind::MethodCall {
                receiver: Box::new(resolve_expr_splices(state, env_idx, receiver)?),
                method: method.clone(),
                args: args
                    .iter()
                    .map(|arg| resolve_expr_splices(state, env_idx, arg))
                    .collect::<Result<Vec<_>, _>>()?,
            },
            span: expr.span,
        },
        ExprKind::Splice(source) => unsafe {
            with_eval_host_splice_source(state, env_idx, source, "expr", |snippet, next_env| {
                let parsed = parse_source_expr(snippet).map_err(|e| e.render(snippet))?;
                resolve_expr_splices(state, next_env, &parsed)
            })?
        },
        ExprKind::Hole { name, .. } => unsafe {
            with_eval_host_splice_source(state, env_idx, name, "hole", |snippet, next_env| {
                let parsed = parse_source_expr(snippet).map_err(|e| e.render(snippet))?;
                resolve_expr_splices(state, next_env, &parsed)
            })?
        },
        ExprKind::AnonymousFunc(func) => AstExpr {
            kind: ExprKind::AnonymousFunc(resolve_func_splices(state, env_idx, func)?),
            span: expr.span,
        },
    })
}

fn resolve_stmt_splices(state: *mut lua_State, env_idx: Option<c_int>, stmt: &AstStmt) -> Result<AstStmt, String> {
    Ok(match stmt {
        AstStmt::Let { name, ty, value, span } => AstStmt::Let {
            name: name.clone(),
            ty: ty
                .as_ref()
                .map(|v| resolve_type_splices(state, env_idx, v))
                .transpose()?,
            value: resolve_expr_splices(state, env_idx, value)?,
            span: *span,
        },
        AstStmt::Var { name, ty, value, span } => AstStmt::Var {
            name: name.clone(),
            ty: ty
                .as_ref()
                .map(|v| resolve_type_splices(state, env_idx, v))
                .transpose()?,
            value: resolve_expr_splices(state, env_idx, value)?,
            span: *span,
        },
        AstStmt::Assign { target, value, span } => AstStmt::Assign {
            target: resolve_expr_splices(state, env_idx, target)?,
            value: resolve_expr_splices(state, env_idx, value)?,
            span: *span,
        },
        AstStmt::If(v) => AstStmt::If(IfStmt {
            branches: v
                .branches
                .iter()
                .map(|branch| {
                    Ok(IfStmtBranch {
                        cond: resolve_expr_splices(state, env_idx, &branch.cond)?,
                        body: resolve_block_splices(state, env_idx, &branch.body)?,
                        span: branch.span,
                    })
                })
                .collect::<Result<Vec<_>, String>>()?,
            else_branch: v
                .else_branch
                .as_ref()
                .map(|b| resolve_block_splices(state, env_idx, b))
                .transpose()?,
            span: v.span,
        }),
        AstStmt::While { cond, body, span } => AstStmt::While {
            cond: resolve_expr_splices(state, env_idx, cond)?,
            body: resolve_block_splices(state, env_idx, body)?,
            span: *span,
        },
        AstStmt::For(v) => AstStmt::For(ForStmt {
            name: v.name.clone(),
            start: resolve_expr_splices(state, env_idx, &v.start)?,
            end: resolve_expr_splices(state, env_idx, &v.end)?,
            step: v
                .step
                .as_ref()
                .map(|e| resolve_expr_splices(state, env_idx, e))
                .transpose()?,
            body: resolve_block_splices(state, env_idx, &v.body)?,
            span: v.span,
        }),
        AstStmt::Loop(v) => AstStmt::Loop(AstLoopStmt {
            head: resolve_loop_head_splices(state, env_idx, &v.head)?,
            body: resolve_block_splices(state, env_idx, &v.body)?,
            next: v
                .next
                .iter()
                .map(|entry| resolve_loop_next_assign_splices(state, env_idx, entry))
                .collect::<Result<Vec<_>, _>>()?,
            span: v.span,
        }),
        AstStmt::Switch(v) => AstStmt::Switch(SwitchStmt {
            value: resolve_expr_splices(state, env_idx, &v.value)?,
            cases: v
                .cases
                .iter()
                .map(|case| {
                    Ok(SwitchStmtCase {
                        value: resolve_expr_splices(state, env_idx, &case.value)?,
                        body: resolve_block_splices(state, env_idx, &case.body)?,
                        span: case.span,
                    })
                })
                .collect::<Result<Vec<_>, String>>()?,
            default: v
                .default
                .as_ref()
                .map(|b| resolve_block_splices(state, env_idx, b))
                .transpose()?,
            span: v.span,
        }),
        AstStmt::Break { span } => AstStmt::Break { span: *span },
        AstStmt::Continue { span } => AstStmt::Continue { span: *span },
        AstStmt::Return { value, span } => AstStmt::Return {
            value: value
                .as_ref()
                .map(|e| resolve_expr_splices(state, env_idx, e))
                .transpose()?,
            span: *span,
        },
        AstStmt::Memory(mem) => AstStmt::Memory(match mem {
            MemoryStmt::Memcpy { dst, src, len, span } => MemoryStmt::Memcpy {
                dst: resolve_expr_splices(state, env_idx, dst)?,
                src: resolve_expr_splices(state, env_idx, src)?,
                len: resolve_expr_splices(state, env_idx, len)?,
                span: *span,
            },
            MemoryStmt::Memmove { dst, src, len, span } => MemoryStmt::Memmove {
                dst: resolve_expr_splices(state, env_idx, dst)?,
                src: resolve_expr_splices(state, env_idx, src)?,
                len: resolve_expr_splices(state, env_idx, len)?,
                span: *span,
            },
            MemoryStmt::Memset { dst, byte, len, span } => MemoryStmt::Memset {
                dst: resolve_expr_splices(state, env_idx, dst)?,
                byte: resolve_expr_splices(state, env_idx, byte)?,
                len: resolve_expr_splices(state, env_idx, len)?,
                span: *span,
            },
            MemoryStmt::Store { ty, dst, value, span } => MemoryStmt::Store {
                ty: resolve_type_splices(state, env_idx, ty)?,
                dst: resolve_expr_splices(state, env_idx, dst)?,
                value: resolve_expr_splices(state, env_idx, value)?,
                span: *span,
            },
        }),
        AstStmt::Expr { expr, span } => AstStmt::Expr {
            expr: resolve_expr_splices(state, env_idx, expr)?,
            span: *span,
        },
    })
}

fn resolve_field_decl_splices(state: *mut lua_State, env_idx: Option<c_int>, field: &FieldDecl) -> Result<FieldDecl, String> {
    Ok(FieldDecl {
        name: field.name.clone(),
        ty: resolve_type_splices(state, env_idx, &field.ty)?,
        span: field.span,
    })
}

fn resolve_item_splices(state: *mut lua_State, env_idx: Option<c_int>, item: &Item) -> Result<Vec<Item>, String> {
    match &item.kind {
        ItemKind::Splice(source) => unsafe {
            return with_eval_host_splice_source(state, env_idx, source, "item", |snippet, next_env| {
                let parsed = parse_module(snippet).map_err(|e| e.render(snippet))?;
                parsed
                    .items
                    .iter()
                    .map(|it| resolve_item_splices(state, next_env, it))
                    .collect::<Result<Vec<_>, _>>()
                    .map(|lists| lists.into_iter().flatten().collect())
            });
        },
        ItemKind::Const(v) => Ok(vec![Item {
            visibility: item.visibility.clone(),
            attributes: item.attributes.clone(),
            kind: ItemKind::Const(crate::ast::ConstDecl {
                name: v.name.clone(),
                ty: v
                    .ty
                    .as_ref()
                    .map(|t| resolve_type_splices(state, env_idx, t))
                    .transpose()?,
                value: resolve_expr_splices(state, env_idx, &v.value)?,
                span: v.span,
            }),
            span: item.span,
        }]),
        ItemKind::TypeAlias(v) => Ok(vec![Item {
            visibility: item.visibility.clone(),
            attributes: item.attributes.clone(),
            kind: ItemKind::TypeAlias(TypeAliasDecl {
                name: v.name.clone(),
                ty: resolve_type_splices(state, env_idx, &v.ty)?,
                span: v.span,
            }),
            span: item.span,
        }]),
        ItemKind::Struct(v) => Ok(vec![Item {
            visibility: item.visibility.clone(),
            attributes: item.attributes.clone(),
            kind: ItemKind::Struct(StructDecl {
                name: v.name.clone(),
                fields: v
                    .fields
                    .iter()
                    .map(|f| resolve_field_decl_splices(state, env_idx, f))
                    .collect::<Result<Vec<_>, _>>()?,
                span: v.span,
            }),
            span: item.span,
        }]),
        ItemKind::Union(v) => Ok(vec![Item {
            visibility: item.visibility.clone(),
            attributes: item.attributes.clone(),
            kind: ItemKind::Union(UnionDecl {
                name: v.name.clone(),
                fields: v
                    .fields
                    .iter()
                    .map(|f| resolve_field_decl_splices(state, env_idx, f))
                    .collect::<Result<Vec<_>, _>>()?,
                span: v.span,
            }),
            span: item.span,
        }]),
        ItemKind::TaggedUnion(v) => Ok(vec![Item {
            visibility: item.visibility.clone(),
            attributes: item.attributes.clone(),
            kind: ItemKind::TaggedUnion(TaggedUnionDecl {
                name: v.name.clone(),
                base_ty: v
                    .base_ty
                    .as_ref()
                    .map(|t| resolve_type_splices(state, env_idx, t))
                    .transpose()?,
                variants: v
                    .variants
                    .iter()
                    .map(|variant| {
                        Ok(TaggedVariantDecl {
                            name: variant.name.clone(),
                            fields: variant
                                .fields
                                .iter()
                                .map(|f| resolve_field_decl_splices(state, env_idx, f))
                                .collect::<Result<Vec<_>, String>>()?,
                            span: variant.span,
                        })
                    })
                    .collect::<Result<Vec<_>, String>>()?,
                span: v.span,
            }),
            span: item.span,
        }]),
        ItemKind::Enum(v) => Ok(vec![Item {
            visibility: item.visibility.clone(),
            attributes: item.attributes.clone(),
            kind: ItemKind::Enum(EnumDecl {
                name: v.name.clone(),
                base_ty: v
                    .base_ty
                    .as_ref()
                    .map(|t| resolve_type_splices(state, env_idx, t))
                    .transpose()?,
                members: v
                    .members
                    .iter()
                    .map(|member| {
                        Ok(EnumMemberDecl {
                            name: member.name.clone(),
                            value: member
                                .value
                                .as_ref()
                                .map(|e| resolve_expr_splices(state, env_idx, e))
                                .transpose()?,
                            span: member.span,
                        })
                    })
                    .collect::<Result<Vec<_>, String>>()?,
                span: v.span,
            }),
            span: item.span,
        }]),
        ItemKind::Opaque(v) => Ok(vec![Item {
            visibility: item.visibility.clone(),
            attributes: item.attributes.clone(),
            kind: ItemKind::Opaque(OpaqueDecl {
                name: v.name.clone(),
                span: v.span,
            }),
            span: item.span,
        }]),
        ItemKind::Slice(v) => Ok(vec![Item {
            visibility: item.visibility.clone(),
            attributes: item.attributes.clone(),
            kind: ItemKind::Slice(SliceDecl {
                name: v.name.clone(),
                ty: resolve_type_splices(state, env_idx, &v.ty)?,
                span: v.span,
            }),
            span: item.span,
        }]),
        ItemKind::Func(v) => Ok(vec![Item {
            visibility: item.visibility.clone(),
            attributes: item.attributes.clone(),
            kind: ItemKind::Func(resolve_func_splices(state, env_idx, v)?),
            span: item.span,
        }]),
        ItemKind::ExternFunc(v) => Ok(vec![Item {
            visibility: item.visibility.clone(),
            attributes: item.attributes.clone(),
            kind: ItemKind::ExternFunc(ExternFuncDecl {
                name: v.name.clone(),
                params: v
                    .params
                    .iter()
                    .map(|param| {
                        Ok(Param {
                            name: param.name.clone(),
                            ty: resolve_type_splices(state, env_idx, &param.ty)?,
                            span: param.span,
                        })
                    })
                    .collect::<Result<Vec<_>, String>>()?,
                result: v
                    .result
                    .as_ref()
                    .map(|t| resolve_type_splices(state, env_idx, t))
                    .transpose()?,
                span: v.span,
            }),
            span: item.span,
        }]),
        ItemKind::Impl(v) => Ok(vec![Item {
            visibility: item.visibility.clone(),
            attributes: item.attributes.clone(),
            kind: ItemKind::Impl(ImplDecl {
                target: v.target.clone(),
                items: v
                    .items
                    .iter()
                    .map(|impl_item| {
                        Ok(ImplItem {
                            attributes: impl_item.attributes.clone(),
                            func: resolve_func_splices(state, env_idx, &impl_item.func)?,
                            span: impl_item.span,
                        })
                    })
                    .collect::<Result<Vec<_>, String>>()?,
                span: v.span,
            }),
            span: item.span,
        }]),
    }
}

fn resolve_module_splices(state: *mut lua_State, env_idx: Option<c_int>, module: &ModuleAst) -> Result<ModuleAst, String> {
    let mut items = Vec::new();
    for item in &module.items {
        items.extend(resolve_item_splices(state, env_idx, item)?);
    }
    Ok(ModuleAst { items, span: module.span })
}

unsafe fn prepared_native_code_from_source(
    state: *mut lua_State,
    rt: &mut Runtime,
    source: &str,
    env_idx: Option<c_int>,
) -> Result<PreparedCode, String> {
    if source_has_host_metaprogramming(source) {
        let item = parse_code(source).map_err(|e| e.render(source))?;
        let resolved = resolve_item_splices(state, env_idx, &item)?;
        if resolved.len() != 1 {
            return Err(
                "unsupported native source fast path: code item splice must resolve to exactly one item"
                    .to_string(),
            );
        }
        prepare_native_code_item_ast(&resolved[0])
    } else {
        rt.prepared_native_code(source)
    }
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
    let env_idx = optional_host_env_arg(state);
    if source_has_host_metaprogramming(&source) {
        let item = match parse_code(&source).map_err(|e| e.render(&source)) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        let resolved = match resolve_item_splices(state, env_idx, &item) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        if resolved.len() != 1 {
            return push_compile_error(state, "unsupported native source fast path: code item splice must resolve to exactly one item");
        }
        match prepare_native_code_item_ast(&resolved[0]) {
            Ok(prepared) => match push_native_func_meta(state, &prepared) {
                Ok(()) => 1,
                Err(err) => LuaState::raise_error(state, &err.message),
            },
            Err(message) => push_compile_error(state, &message),
        }
    } else {
        match (&mut *rt_ptr).prepared_native_code(&source) {
            Ok(prepared) => match push_native_func_meta(state, &prepared) {
                Ok(()) => 1,
                Err(err) => LuaState::raise_error(state, &err.message),
            },
            Err(message) => push_compile_error(state, &message),
        }
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
    let env_idx = optional_host_env_arg(state);
    if source_has_host_metaprogramming(&source) {
        let module = match parse_module(&source).map_err(|e| e.render(&source)) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        let resolved = match resolve_module_splices(state, env_idx, &module) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        match prepare_native_module_ast(&resolved) {
            Ok(prepared) => {
                if !prepared.meta_complete {
                    return push_compile_error(state, "unsupported native source fast path: native module metadata export is incomplete for this source");
                }
                match push_native_module_meta(state, &prepared) {
                    Ok(()) => 1,
                    Err(err) => LuaState::raise_error(state, &err.message),
                }
            }
            Err(message) => push_compile_error(state, &message),
        }
    } else {
        match (&mut *rt_ptr).prepared_native_module_meta(&source) {
            Ok(prepared) => match push_native_module_meta(state, &prepared) {
                Ok(()) => 1,
                Err(err) => LuaState::raise_error(state, &err.message),
            },
            Err(message) => push_compile_error(state, &message),
        }
    }
}

unsafe extern "C" fn moonlift_source_meta_expr_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "source_meta_expr") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let env_idx = optional_host_env_arg(state);
    if source_has_host_metaprogramming(&source) {
        let expr_ast = match parse_source_expr(&source).map_err(|e| e.render(&source)) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        let resolved = match resolve_expr_splices(state, env_idx, &expr_ast) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        match prepare_native_expr_ast(&resolved) {
            Ok(prepared) => match push_native_expr_meta(state, &prepared) {
                Ok(()) => 1,
                Err(err) => LuaState::raise_error(state, &err.message),
            },
            Err(message) => push_compile_error(state, &message),
        }
    } else {
        match prepare_native_expr(&source) {
            Ok(prepared) => match push_native_expr_meta(state, &prepared) {
                Ok(()) => 1,
                Err(err) => LuaState::raise_error(state, &err.message),
            },
            Err(message) => push_compile_error(state, &message),
        }
    }
}

unsafe extern "C" fn moonlift_source_meta_type_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "source_meta_type") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let env_idx = optional_host_env_arg(state);
    if source_has_host_metaprogramming(&source) {
        let ty_ast = match parse_type(&source).map_err(|e| e.render(&source)) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        let resolved = match resolve_type_splices(state, env_idx, &ty_ast) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        match prepare_native_type_ast(&resolved) {
            Ok(meta) => match push_native_type_ref_meta(state, &meta) {
                Ok(()) => 1,
                Err(err) => LuaState::raise_error(state, &err.message),
            },
            Err(message) => push_compile_error(state, &message),
        }
    } else {
        match prepare_native_type_meta(&source) {
            Ok(meta) => match push_native_type_ref_meta(state, &meta) {
                Ok(()) => 1,
                Err(err) => LuaState::raise_error(state, &err.message),
            },
            Err(message) => push_compile_error(state, &message),
        }
    }
}

unsafe extern "C" fn moonlift_source_meta_extern_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "source_meta_extern") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let env_idx = optional_host_env_arg(state);
    let result = if source_has_host_metaprogramming(&source) {
        let items = match parse_externs(&source).map_err(|e| e.render(&source)) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        let mut resolved_items = Vec::new();
        for item in &items {
            match resolve_item_splices(state, env_idx, item) {
                Ok(v) => resolved_items.extend(v),
                Err(message) => return push_compile_error(state, &message),
            }
        }
        prepare_native_externs_items_ast(&resolved_items)
    } else {
        prepare_native_externs_meta(&source)
    };
    match result {
        Ok(externs) => {
            LuaState::create_table(state, externs.len() as c_int, 0);
            for (i, ext) in externs.iter().enumerate() {
                match push_native_extern_meta(state, ext) {
                    Ok(()) => LuaState::raw_set_i_from_top(state, -2, (i + 1) as i64),
                    Err(err) => return LuaState::raise_error(state, &err.message),
                }
            }
            1
        }
        Err(message) => push_compile_error(state, &message),
    }
}

fn expr_has_direct_call(expr: &Expr) -> bool {
    match expr {
        Expr::Arg { .. } | Expr::Local { .. } | Expr::Const { .. } | Expr::StackAddr { .. } => false,
        Expr::Unary { value, .. } | Expr::Cast { value, .. } | Expr::Load { addr: value, .. } => {
            expr_has_direct_call(value)
        }
        Expr::IndexAddr { base, index, limit, .. } => {
            expr_has_direct_call(base)
                || expr_has_direct_call(index)
                || limit.as_deref().is_some_and(expr_has_direct_call)
        }
        Expr::Binary { lhs, rhs, .. } => expr_has_direct_call(lhs) || expr_has_direct_call(rhs),
        Expr::Select {
            cond,
            then_expr,
            else_expr,
            ..
        } => expr_has_direct_call(cond) || expr_has_direct_call(then_expr) || expr_has_direct_call(else_expr),
        Expr::Let { init, body, .. } => expr_has_direct_call(init) || expr_has_direct_call(body),
        Expr::Block { stmts, result, .. } => stmts.iter().any(stmt_has_direct_call) || expr_has_direct_call(result),
        Expr::If { cond, then_expr, else_expr, .. } => {
            expr_has_direct_call(cond) || expr_has_direct_call(then_expr) || expr_has_direct_call(else_expr)
        }
        Expr::Memcmp { a, b, len } => expr_has_direct_call(a) || expr_has_direct_call(b) || expr_has_direct_call(len),
        Expr::Call { target, args, .. } => {
            call_target_is_direct(target) || args.iter().any(expr_has_direct_call)
        }
    }
}

fn call_target_is_direct(target: &CallTarget) -> bool {
    match target {
        CallTarget::Direct { .. } => true,
        CallTarget::Indirect { addr, .. } => expr_has_direct_call(addr),
    }
}

fn stmt_has_direct_call(stmt: &Stmt) -> bool {
    match stmt {
        Stmt::Let { init, .. } | Stmt::Var { init, .. } | Stmt::Set { value: init, .. } => expr_has_direct_call(init),
        Stmt::While { cond, body } => expr_has_direct_call(cond) || body.iter().any(stmt_has_direct_call),
        Stmt::LoopWhile { vars, cond, body, next } => {
            vars.iter().any(|var| expr_has_direct_call(&var.init))
                || expr_has_direct_call(cond)
                || body.iter().any(stmt_has_direct_call)
                || next.iter().any(expr_has_direct_call)
        }
        Stmt::ForRange {
            start,
            finish,
            step,
            body,
            ..
        } => {
            expr_has_direct_call(start)
                || expr_has_direct_call(finish)
                || expr_has_direct_call(step)
                || body.iter().any(stmt_has_direct_call)
        }
        Stmt::If {
            cond,
            then_body,
            else_body,
        } => {
            expr_has_direct_call(cond)
                || then_body.iter().any(stmt_has_direct_call)
                || else_body.iter().any(stmt_has_direct_call)
        }
        Stmt::Store { addr, value, .. } => expr_has_direct_call(addr) || expr_has_direct_call(value),
        Stmt::BoundsCheck { index, limit } => expr_has_direct_call(index) || expr_has_direct_call(limit),
        Stmt::Assert { cond } => expr_has_direct_call(cond),
        Stmt::Memcpy { dst, src, len } | Stmt::Memmove { dst, src, len } => {
            expr_has_direct_call(dst) || expr_has_direct_call(src) || expr_has_direct_call(len)
        }
        Stmt::Memset { dst, byte, len } => {
            expr_has_direct_call(dst) || expr_has_direct_call(byte) || expr_has_direct_call(len)
        }
        Stmt::Call { target, args } => call_target_is_direct(target) || args.iter().any(expr_has_direct_call),
        Stmt::StackSlot { .. } | Stmt::Break | Stmt::Continue => false,
    }
}

fn function_spec_has_direct_call(spec: &FunctionSpec) -> bool {
    expr_has_direct_call(&spec.body)
}

fn collect_direct_callee_names_expr(expr: &Expr, out: &mut HashMap<String, ()>) {
    match expr {
        Expr::Arg { .. } | Expr::Local { .. } | Expr::Const { .. } | Expr::StackAddr { .. } => {}
        Expr::Unary { value, .. } | Expr::Cast { value, .. } | Expr::Load { addr: value, .. } => {
            collect_direct_callee_names_expr(value, out)
        }
        Expr::IndexAddr { base, index, limit, .. } => {
            collect_direct_callee_names_expr(base, out);
            collect_direct_callee_names_expr(index, out);
            if let Some(limit) = limit.as_deref() {
                collect_direct_callee_names_expr(limit, out);
            }
        }
        Expr::Binary { lhs, rhs, .. } => {
            collect_direct_callee_names_expr(lhs, out);
            collect_direct_callee_names_expr(rhs, out);
        }
        Expr::Select { cond, then_expr, else_expr, .. }
        | Expr::If { cond, then_expr, else_expr, .. } => {
            collect_direct_callee_names_expr(cond, out);
            collect_direct_callee_names_expr(then_expr, out);
            collect_direct_callee_names_expr(else_expr, out);
        }
        Expr::Let { init, body, .. } => {
            collect_direct_callee_names_expr(init, out);
            collect_direct_callee_names_expr(body, out);
        }
        Expr::Block { stmts, result, .. } => {
            for stmt in stmts {
                collect_direct_callee_names_stmt(stmt, out);
            }
            collect_direct_callee_names_expr(result, out);
        }
        Expr::Memcmp { a, b, len } => {
            collect_direct_callee_names_expr(a, out);
            collect_direct_callee_names_expr(b, out);
            collect_direct_callee_names_expr(len, out);
        }
        Expr::Call { target, args, .. } => {
            match target {
                CallTarget::Direct { name, .. } => {
                    out.insert(name.clone(), ());
                }
                CallTarget::Indirect { addr, .. } => collect_direct_callee_names_expr(addr, out),
            }
            for arg in args {
                collect_direct_callee_names_expr(arg, out);
            }
        }
    }
}

fn collect_direct_callee_names_stmt(stmt: &Stmt, out: &mut HashMap<String, ()>) {
    match stmt {
        Stmt::Let { init, .. } | Stmt::Var { init, .. } | Stmt::Set { value: init, .. } => {
            collect_direct_callee_names_expr(init, out)
        }
        Stmt::While { cond, body } => {
            collect_direct_callee_names_expr(cond, out);
            for stmt in body {
                collect_direct_callee_names_stmt(stmt, out);
            }
        }
        Stmt::LoopWhile { vars, cond, body, next } => {
            for var in vars {
                collect_direct_callee_names_expr(&var.init, out);
            }
            collect_direct_callee_names_expr(cond, out);
            for stmt in body {
                collect_direct_callee_names_stmt(stmt, out);
            }
            for value in next {
                collect_direct_callee_names_expr(value, out);
            }
        }
        Stmt::ForRange { start, finish, step, body, .. } => {
            collect_direct_callee_names_expr(start, out);
            collect_direct_callee_names_expr(finish, out);
            collect_direct_callee_names_expr(step, out);
            for stmt in body {
                collect_direct_callee_names_stmt(stmt, out);
            }
        }
        Stmt::If { cond, then_body, else_body } => {
            collect_direct_callee_names_expr(cond, out);
            for stmt in then_body {
                collect_direct_callee_names_stmt(stmt, out);
            }
            for stmt in else_body {
                collect_direct_callee_names_stmt(stmt, out);
            }
        }
        Stmt::Store { addr, value, .. } => {
            collect_direct_callee_names_expr(addr, out);
            collect_direct_callee_names_expr(value, out);
        }
        Stmt::BoundsCheck { index, limit } => {
            collect_direct_callee_names_expr(index, out);
            collect_direct_callee_names_expr(limit, out);
        }
        Stmt::Assert { cond } => {
            collect_direct_callee_names_expr(cond, out);
        }
        Stmt::Memcpy { dst, src, len } | Stmt::Memmove { dst, src, len } => {
            collect_direct_callee_names_expr(dst, out);
            collect_direct_callee_names_expr(src, out);
            collect_direct_callee_names_expr(len, out);
        }
        Stmt::Memset { dst, byte, len } => {
            collect_direct_callee_names_expr(dst, out);
            collect_direct_callee_names_expr(byte, out);
            collect_direct_callee_names_expr(len, out);
        }
        Stmt::Call { target, args } => {
            match target {
                CallTarget::Direct { name, .. } => {
                    out.insert(name.clone(), ());
                }
                CallTarget::Indirect { addr, .. } => collect_direct_callee_names_expr(addr, out),
            }
            for arg in args {
                collect_direct_callee_names_expr(arg, out);
            }
        }
        Stmt::StackSlot { .. } | Stmt::Break | Stmt::Continue => {}
    }
}

struct ModuleCompilePlan {
    name_to_index: HashMap<String, usize>,
    comp_of: Vec<usize>,
    comp_members: Vec<Vec<usize>>,
    comp_deps: Vec<Vec<usize>>,
}

fn build_module_compile_plan(specs: &[FunctionSpec]) -> Result<ModuleCompilePlan, String> {
    let mut name_to_index = HashMap::new();
    for (i, spec) in specs.iter().enumerate() {
        if name_to_index.insert(spec.name.clone(), i).is_some() {
            return Err(format!("duplicate Moonlift function '{}' in module compile plan", spec.name));
        }
    }

    let mut deps: Vec<Vec<usize>> = Vec::with_capacity(specs.len());
    for spec in specs {
        let mut seen = HashMap::new();
        collect_direct_callee_names_expr(&spec.body, &mut seen);
        let mut out: Vec<usize> = seen
            .into_keys()
            .filter_map(|name| name_to_index.get(&name).copied())
            .collect();
        out.sort_unstable();
        out.dedup();
        deps.push(out);
    }

    fn strongconnect(
        v: usize,
        deps: &[Vec<usize>],
        next_index: &mut usize,
        indices: &mut [Option<usize>],
        lowlink: &mut [usize],
        stack: &mut Vec<usize>,
        onstack: &mut [bool],
        comp_of: &mut [usize],
        comp_members: &mut Vec<Vec<usize>>,
    ) {
        *next_index += 1;
        indices[v] = Some(*next_index);
        lowlink[v] = *next_index;
        stack.push(v);
        onstack[v] = true;

        for &w in &deps[v] {
            if indices[w].is_none() {
                strongconnect(w, deps, next_index, indices, lowlink, stack, onstack, comp_of, comp_members);
                if lowlink[w] < lowlink[v] {
                    lowlink[v] = lowlink[w];
                }
            } else if onstack[w] {
                let idx_w = indices[w].unwrap_or(0);
                if idx_w < lowlink[v] {
                    lowlink[v] = idx_w;
                }
            }
        }

        if lowlink[v] == indices[v].unwrap_or(usize::MAX) {
            let comp_id = comp_members.len();
            let mut members = Vec::new();
            loop {
                let w = stack.pop().expect("tarjan stack underflow");
                onstack[w] = false;
                comp_of[w] = comp_id;
                members.push(w);
                if w == v {
                    break;
                }
            }
            members.sort_unstable();
            comp_members.push(members);
        }
    }

    let mut indices = vec![None; specs.len()];
    let mut lowlink = vec![0usize; specs.len()];
    let mut stack = Vec::new();
    let mut onstack = vec![false; specs.len()];
    let mut comp_of = vec![usize::MAX; specs.len()];
    let mut comp_members = Vec::new();
    let mut next_index = 0usize;

    for v in 0..specs.len() {
        if indices[v].is_none() {
            strongconnect(
                v,
                &deps,
                &mut next_index,
                &mut indices,
                &mut lowlink,
                &mut stack,
                &mut onstack,
                &mut comp_of,
                &mut comp_members,
            );
        }
    }

    let mut comp_deps = vec![Vec::new(); comp_members.len()];
    for (i, out_edges) in deps.iter().enumerate() {
        let src = comp_of[i];
        let mut seen = HashMap::new();
        for &j in out_edges {
            let dst = comp_of[j];
            if dst != src && seen.insert(dst, ()).is_none() {
                comp_deps[src].push(dst);
            }
        }
        comp_deps[src].sort_unstable();
    }

    Ok(ModuleCompilePlan {
        name_to_index,
        comp_of,
        comp_members,
        comp_deps,
    })
}

fn module_entry_closure_indices(specs: &[FunctionSpec], entry_name: &str) -> Result<Vec<usize>, String> {
    let plan = build_module_compile_plan(specs)?;
    let entry_idx = *plan
        .name_to_index
        .get(entry_name)
        .ok_or_else(|| format!("unknown Moonlift module entry '{}'", entry_name))?;
    let mut seen = vec![false; plan.comp_members.len()];
    fn visit(comp: usize, deps: &[Vec<usize>], seen: &mut [bool]) {
        if seen[comp] {
            return;
        }
        seen[comp] = true;
        for &dep in &deps[comp] {
            visit(dep, deps, seen);
        }
    }
    visit(plan.comp_of[entry_idx], &plan.comp_deps, &mut seen);
    let mut out = Vec::new();
    for i in 0..specs.len() {
        if seen[plan.comp_of[i]] {
            out.push(i);
        }
    }
    Ok(out)
}

fn compile_spec_entry_sparse(
    rt: &mut Runtime,
    specs: Vec<FunctionSpec>,
    entry_name: &str,
) -> Result<Vec<Option<u32>>, String> {
    let indices = module_entry_closure_indices(&specs, entry_name)?;
    let mut sparse = vec![None; specs.len()];
    if indices.len() == 1 && !function_spec_has_direct_call(&specs[indices[0]]) {
        sparse[indices[0]] = Some(rt.compile_function(specs[indices[0]].clone()).map_err(|e| e.to_string())?);
        return Ok(sparse);
    }
    let subset: Vec<FunctionSpec> = indices.iter().map(|&i| specs[i].clone()).collect();
    let handles = rt.compile_module(subset).map_err(|e| e.to_string())?;
    for (pos, &idx) in indices.iter().enumerate() {
        sparse[idx] = Some(handles[pos]);
    }
    Ok(sparse)
}

fn compile_prepared_module_entry_sparse(
    rt: &mut Runtime,
    prepared: PreparedModule,
    entry_name: &str,
) -> Result<Vec<Option<u32>>, String> {
    let specs: Vec<FunctionSpec> = prepared.funcs.iter().map(|f| f.spec.clone()).collect();
    compile_spec_entry_sparse(rt, specs, entry_name)
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
    let env_idx = optional_host_env_arg(state);
    match prepared_native_code_from_source(state, rt, &source, env_idx) {
        Ok(prepared) => {
            if function_spec_has_direct_call(&prepared.spec) {
                match rt.compile_module(vec![prepared.spec]) {
                    Ok(handles) => {
                        LuaState::push_integer(state, handles[0] as isize);
                        1
                    }
                    Err(err) => push_compile_error(state, &err.message),
                }
            } else {
                match rt.compile_function(prepared.spec) {
                    Ok(handle) => {
                        LuaState::push_integer(state, handle as isize);
                        1
                    }
                    Err(err) => push_compile_error(state, &err.message),
                }
            }
        }
        Err(message) => push_compile_error(state, &message),
    }
}

unsafe extern "C" fn moonlift_compile_source_code_unoptimized_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "compile_source_code_unoptimized") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime not installed");
    }
    let rt = &mut *rt_ptr;
    let env_idx = optional_host_env_arg(state);
    match prepared_native_code_from_source(state, rt, &source, env_idx) {
        Ok(prepared) => {
            if function_spec_has_direct_call(&prepared.spec) {
                return push_compile_error(
                    state,
                    "moonlift unoptimized source compile currently requires a code item without direct calls",
                );
            }
            match rt.compile_function_unoptimized(prepared.spec) {
                Ok(handle) => {
                    LuaState::push_integer(state, handle as isize);
                    1
                }
                Err(err) => push_compile_error(state, &err.message),
            }
        }
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
    let env_idx = optional_host_env_arg(state);
    let prepared_result = if source_has_host_metaprogramming(&source) {
        let module = match parse_module(&source).map_err(|e| e.render(&source)) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        let resolved = match resolve_module_splices(state, env_idx, &module) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        prepare_native_module_ast(&resolved)
    } else {
        rt.prepared_native_module(&source)
    };
    match prepared_result {
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

unsafe extern "C" fn moonlift_compile_source_module_entry_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "compile_source_module_entry") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let entry = match parse_required_string_arg(state, 2, "compile_source_module_entry") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime not installed");
    }
    let rt = &mut *rt_ptr;
    let env_idx = optional_table_arg(state, 3);
    let prepared_result = if source_has_host_metaprogramming(&source) {
        let module = match parse_module(&source).map_err(|e| e.render(&source)) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        let resolved = match resolve_module_splices(state, env_idx, &module) {
            Ok(v) => v,
            Err(message) => return push_compile_error(state, &message),
        };
        prepare_native_module_ast(&resolved)
    } else {
        rt.prepared_native_module(&source)
    };
    match prepared_result {
        Ok(prepared) => match compile_prepared_module_entry_sparse(rt, prepared, &entry) {
            Ok(handles) => match push_sparse_handles_table(state, &handles) {
                Ok(rc) => rc,
                Err(err) => LuaState::raise_error(state, &err.message),
            },
            Err(message) => push_compile_error(state, &message),
        },
        Err(message) => push_compile_error(state, &message),
    }
}

unsafe extern "C" fn moonlift_dump_source_code_spec_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "dump_source_code_spec") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime not installed");
    }
    let rt = &mut *rt_ptr;
    let env_idx = optional_host_env_arg(state);
    match prepared_native_code_from_source(state, rt, &source, env_idx) {
        Ok(prepared) => match LuaState::push_string(state, &format!("{:#?}", prepared.spec)) {
            Ok(()) => 1,
            Err(err) => LuaState::raise_error(state, &err.message),
        },
        Err(message) => push_compile_error(state, &message),
    }
}

unsafe extern "C" fn moonlift_dump_optimized_source_code_spec_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "dump_optimized_source_code_spec") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime not installed");
    }
    let rt = &mut *rt_ptr;
    let env_idx = optional_host_env_arg(state);
    match prepared_native_code_from_source(state, rt, &source, env_idx) {
        Ok(prepared) => {
            let optimized = optimize_function_spec(&prepared.spec);
            match LuaState::push_string(state, &format!("{:#?}", optimized)) {
                Ok(()) => 1,
                Err(err) => LuaState::raise_error(state, &err.message),
            }
        }
        Err(message) => push_compile_error(state, &message),
    }
}

unsafe extern "C" fn moonlift_dump_spec_lua(state: *mut lua_State) -> c_int {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let spec = parse_function_spec(state, 1)?;
        Ok::<String, String>(format!("{:#?}", spec))
    }));

    let text = match result {
        Ok(Ok(text)) => text,
        Ok(Err(msg)) => return push_compile_error(state, &format!("moonlift dump spec error: {}", msg)),
        Err(panic) => {
            let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = panic.downcast_ref::<String>() {
                s.clone()
            } else {
                "moonlift dump spec panic".to_string()
            };
            return push_compile_error(state, &format!("moonlift dump spec panic: {}", msg));
        }
    };

    match LuaState::push_string(state, &text) {
        Ok(()) => 1,
        Err(err) => LuaState::raise_error(state, &err.message),
    }
}

unsafe extern "C" fn moonlift_dump_optimized_spec_lua(state: *mut lua_State) -> c_int {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let spec = parse_function_spec(state, 1)?;
        let optimized = optimize_function_spec(&spec);
        Ok::<String, String>(format!("{:#?}", optimized))
    }));

    let text = match result {
        Ok(Ok(text)) => text,
        Ok(Err(msg)) => {
            return push_compile_error(state, &format!("moonlift dump optimized spec error: {}", msg))
        }
        Err(panic) => {
            let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = panic.downcast_ref::<String>() {
                s.clone()
            } else {
                "moonlift dump optimized spec panic".to_string()
            };
            return push_compile_error(state, &format!("moonlift dump optimized spec panic: {}", msg));
        }
    };

    match LuaState::push_string(state, &text) {
        Ok(()) => 1,
        Err(err) => LuaState::raise_error(state, &err.message),
    }
}

unsafe extern "C" fn moonlift_dump_disasm_lua(state: *mut lua_State) -> c_int {
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return push_compile_error(state, "moonlift runtime is not initialized");
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let spec = parse_function_spec(state, 1)?;
        let rt = &mut *rt_ptr;
        rt.dump_disasm(&spec).map_err(|e| e.to_string())
    }));

    let text = match result {
        Ok(Ok(text)) => text,
        Ok(Err(msg)) => return push_compile_error(state, &format!("moonlift dump disasm error: {}", msg)),
        Err(panic) => {
            let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = panic.downcast_ref::<String>() {
                s.clone()
            } else {
                "moonlift dump disasm panic".to_string()
            };
            return push_compile_error(state, &format!("moonlift dump disasm panic: {}", msg));
        }
    };

    match LuaState::push_string(state, &text) {
        Ok(()) => 1,
        Err(err) => LuaState::raise_error(state, &err.message),
    }
}

unsafe extern "C" fn moonlift_dump_source_code_disasm_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "dump_source_code_disasm") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime not installed");
    }
    let rt = &mut *rt_ptr;
    let env_idx = optional_host_env_arg(state);
    match prepared_native_code_from_source(state, rt, &source, env_idx) {
        Ok(prepared) => match rt.dump_disasm(&prepared.spec) {
            Ok(text) => match LuaState::push_string(state, &text) {
                Ok(()) => 1,
                Err(err) => LuaState::raise_error(state, &err.message),
            },
            Err(err) => push_compile_error(state, &err.message),
        },
        Err(message) => push_compile_error(state, &message),
    }
}

unsafe extern "C" fn moonlift_dump_unoptimized_disasm_lua(state: *mut lua_State) -> c_int {
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return push_compile_error(state, "moonlift runtime is not initialized");
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let spec = parse_function_spec(state, 1)?;
        let rt = &mut *rt_ptr;
        rt.dump_disasm_unoptimized(&spec).map_err(|e| e.to_string())
    }));

    let text = match result {
        Ok(Ok(text)) => text,
        Ok(Err(msg)) => return push_compile_error(state, &format!("moonlift dump unoptimized disasm error: {}", msg)),
        Err(panic) => {
            let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = panic.downcast_ref::<String>() {
                s.clone()
            } else {
                "moonlift dump unoptimized disasm panic".to_string()
            };
            return push_compile_error(state, &format!("moonlift dump unoptimized disasm panic: {}", msg));
        }
    };

    match LuaState::push_string(state, &text) {
        Ok(()) => 1,
        Err(err) => LuaState::raise_error(state, &err.message),
    }
}

unsafe extern "C" fn moonlift_dump_unoptimized_source_code_disasm_lua(state: *mut lua_State) -> c_int {
    let source = match parse_source_arg(state, "dump_unoptimized_source_code_disasm") {
        Ok(v) => v,
        Err(rc) => return rc,
    };
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return LuaState::raise_error(state, "moonlift runtime not installed");
    }
    let rt = &mut *rt_ptr;
    let env_idx = optional_host_env_arg(state);
    match prepared_native_code_from_source(state, rt, &source, env_idx) {
        Ok(prepared) => match rt.dump_disasm_unoptimized(&prepared.spec) {
            Ok(text) => match LuaState::push_string(state, &text) {
                Ok(()) => 1,
                Err(err) => LuaState::raise_error(state, &err.message),
            },
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

unsafe extern "C" fn moonlift_compile_unoptimized_lua(state: *mut lua_State) -> c_int {
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return push_compile_error(state, "moonlift runtime is not initialized");
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let spec = parse_function_spec(state, 1)?;
        let rt = &mut *rt_ptr;
        let handle = rt.compile_function_unoptimized(spec).map_err(|e| e.to_string())?;
        Ok::<u32, String>(handle)
    }));

    let handle = match result {
        Ok(Ok(handle)) => handle,
        Ok(Err(msg)) => return push_compile_error(state, &format!("moonlift compile unoptimized error: {}", msg)),
        Err(panic) => {
            let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = panic.downcast_ref::<String>() {
                s.clone()
            } else {
                "moonlift compile unoptimized panic".to_string()
            };
            return push_compile_error(state, &format!("moonlift compile unoptimized panic: {}", msg));
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

unsafe extern "C" fn moonlift_compile_module_entry_lua(state: *mut lua_State) -> c_int {
    let rt_ptr = runtime_from_state(state);
    if rt_ptr.is_null() {
        return push_compile_error(state, "moonlift runtime is not initialized");
    }
    let entry = match parse_required_string_arg(state, 2, "compile_module_entry") {
        Ok(v) => v,
        Err(rc) => return rc,
    };

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let specs = parse_function_spec_array(state, 1)?;
        let rt = &mut *rt_ptr;
        compile_spec_entry_sparse(rt, specs, &entry)
    }));

    let handles = match result {
        Ok(Ok(handles)) => handles,
        Ok(Err(msg)) => return push_compile_error(state, &format!("moonlift compile module entry error: {}", msg)),
        Err(panic) => {
            let msg = if let Some(s) = panic.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = panic.downcast_ref::<String>() {
                s.clone()
            } else {
                "moonlift compile module entry panic".to_string()
            };
            return push_compile_error(state, &format!("moonlift compile module entry panic: {}", msg));
        }
    };

    match push_sparse_handles_table(state, &handles) {
        Ok(rc) => rc,
        Err(err) => LuaState::raise_error(state, &err.message),
    }
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
        "loop_while" => Ok(Stmt::LoopWhile {
            vars: read_loop_var_array_field(state, idx, "vars")?,
            cond: read_expr_field(state, idx, "cond")?,
            body: read_stmt_array_field(state, idx, "body")?,
            next: read_expr_array_field(state, idx, "next")?,
        }),
        "for_range" => Ok(Stmt::ForRange {
            name: read_required_string_field(state, idx, "name")?,
            ty: read_required_scalar_type_field(state, idx, "type")?,
            start: read_expr_field(state, idx, "start")?,
            finish: read_expr_field(state, idx, "finish")?,
            step: read_expr_field(state, idx, "step")?,
            dir: read_optional_step_direction_field(state, idx, "dir")?,
            inclusive: read_required_bool_field(state, idx, "inclusive")?,
            scoped: read_required_bool_field(state, idx, "scoped")?,
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
        "bounds_check" => Ok(Stmt::BoundsCheck {
            index: read_expr_field(state, idx, "index")?,
            limit: read_expr_field(state, idx, "limit")?,
        }),
        "assert" => Ok(Stmt::Assert {
            cond: read_expr_field(state, idx, "cond")?,
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

unsafe fn read_optional_expr_field(state: *mut lua_State, idx: c_int, name: &str) -> Result<Option<Expr>, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    let ty = LuaState::get_type(state, -1);
    let out = if ty == LUA_TNIL {
        Ok(None)
    } else {
        parse_expr(state, LuaState::gettop(state)).map(Some)
    };
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
        "index_addr" => Ok(Expr::IndexAddr {
            base: Box::new(read_expr_field(state, idx, "base")?),
            index: Box::new(read_expr_field(state, idx, "index")?),
            elem_size: read_required_u64_field(state, idx, "elem_size")? as u32,
            limit: read_optional_expr_field(state, idx, "limit")?.map(Box::new),
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

unsafe fn read_loop_var_array_field(
    state: *mut lua_State,
    idx: c_int,
    name: &str,
) -> Result<Vec<crate::cranelift_jit::LoopVar>, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    if LuaState::get_type(state, -1) != LUA_TTABLE {
        LuaState::pop(state, 1);
        return Err(format!("field {name:?} must be a table of loop vars"));
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
            return Err(format!("loop-var array entry {} must be a table", i));
        }
        let var_idx = LuaState::gettop(state);
        out.push(crate::cranelift_jit::LoopVar {
            name: read_required_string_field(state, var_idx, "name")?,
            ty: read_required_scalar_type_field(state, var_idx, "type")?,
            init: read_expr_field(state, var_idx, "init")?,
        });
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
            packed: read_optional_bool_field(state, idx, "packed", false)?,
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

unsafe fn read_optional_bool_field(
    state: *mut lua_State,
    idx: c_int,
    name: &str,
    default: bool,
) -> Result<bool, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    if LuaState::get_type(state, -1) == LUA_TNIL {
        LuaState::pop(state, 1);
        return Ok(default);
    }
    let v = LuaState::to_boolean(state, -1);
    LuaState::pop(state, 1);
    Ok(v)
}

unsafe fn read_optional_step_direction_field(
    state: *mut lua_State,
    idx: c_int,
    name: &str,
) -> Result<Option<crate::cranelift_jit::StepDirection>, String> {
    LuaState::get_field(state, idx, name).map_err(|e| e.message)?;
    let out = match LuaState::get_type(state, -1) {
        LUA_TNIL => Ok(None),
        LUA_TSTRING => {
            let s = LuaState::to_string(state, -1)
                .ok_or_else(|| format!("field {name:?} must be a string"))?;
            crate::cranelift_jit::StepDirection::from_name(&s)
                .map(Some)
                .ok_or_else(|| format!("field {name:?} has unknown loop direction {s:?}"))
        }
        _ => Err(format!("field {name:?} must be a string if present")),
    };
    LuaState::pop(state, 1);
    out
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

unsafe fn push_exact_int_result(state: *mut lua_State, bits: u64, signed: bool) -> Result<(), String> {
    LuaState::get_field(state, LUA_GLOBALSINDEX, "__moonlift_exact_int_result")
        .map_err(|err| err.message)?;
    if LuaState::get_type(state, -1) == LUA_TNIL {
        LuaState::pop(state, 1);
        return Err("moonlift exact integer result helper is not installed".to_string());
    }
    LuaState::push_integer(state, (bits as u32) as isize);
    LuaState::push_integer(state, ((bits >> 32) as u32) as isize);
    LuaState::push_boolean(state, signed);
    let rc = LuaState::pcall(state, 3, 1);
    if rc != LUA_OK {
        let msg = LuaState::to_string(state, -1)
            .unwrap_or_else(|| "moonlift exact integer result helper failed".to_string());
        LuaState::pop(state, 1);
        return Err(msg);
    }
    Ok(())
}

unsafe fn push_packed_result(state: *mut lua_State, ty: ScalarType, bits: u64) -> Result<(), String> {
    match ty {
        ScalarType::Void => return Err("cannot push a Moonlift void result as a value".to_string()),
        ScalarType::Bool => LuaState::push_boolean(state, bits & 1 != 0),
        ScalarType::I8 => LuaState::push_integer(state, (bits as u8 as i8) as isize),
        ScalarType::I16 => LuaState::push_integer(state, (bits as u16 as i16) as isize),
        ScalarType::I32 => LuaState::push_integer(state, (bits as u32 as i32) as isize),
        ScalarType::I64 => return push_exact_int_result(state, bits, true),
        ScalarType::U8 => LuaState::push_integer(state, (bits as u8) as isize),
        ScalarType::U16 => LuaState::push_integer(state, (bits as u16) as isize),
        ScalarType::U32 => LuaState::push_integer(state, (bits as u32) as isize),
        ScalarType::U64 => return push_exact_int_result(state, bits, false),
        ScalarType::F32 => LuaState::push_number(state, f32::from_bits(bits as u32) as lua_Number),
        ScalarType::F64 => LuaState::push_number(state, f64::from_bits(bits) as lua_Number),
        ScalarType::Ptr => return push_exact_int_result(state, bits, false),
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
    fn native_source_fast_path_handles_extended_scalar_source() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()
local ffi = require('ffi')

local simple = code[[
func simple_add(x: i32) -> i32
    x + 2
end
]]
assert(simple.__native_source ~= nil)
local simple_h = simple()
assert(simple_h(40) == 42)

local maybe = code[[
func maybe_answer(flag: bool) -> i32
    if flag then
        return 42
    end
    7
end
]]
assert(maybe.__native_source ~= nil)
local maybe_h = maybe()
assert(maybe_h(true) == 42)
assert(maybe_h(false) == 7)

local recursive = code[[
func fact(n: i32)
    if n <= 1 then
        return 1
    end
    return n * fact(n - 1)
end
]]
assert(recursive.__native_source ~= nil)
local fact_h = recursive()
assert(fact_h(5) == 120)

local switchy = code[[
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
assert(switchy.__native_source ~= nil)
local switch_h = switchy()
assert(switch_h(10) == 6)

ffi.cdef[[ int abs(int x); ]]
local ext_mod = module[[
@abi("C")
extern func abs(x: i32) -> i32

func use_abs(x: i32) -> i32
    return abs(x)
end
]]
assert(ext_mod.__native_source ~= nil)
local compiled = ext_mod()
assert(compiled.use_abs(-42) == 42)

local simple_mod = module[[
func add2(x: i32) -> i32
    x + 2
end

func use_add2(x: i32) -> i32
    add2(x) * 2
end
]]
assert(simple_mod.__native_source ~= nil)
local compiled_simple = simple_mod()
assert(compiled_simple.use_add2(19) == 42)

local array_mod = module[[
func array_sum_local() -> i32
    let xs: [4]i32 = [4]i32 { 10, 11, 12, 9 }
    return xs[0] + xs[1] + xs[2] + xs[3]
end

func array_sum_var() -> i32
    var xs: [2]i32 = [2]i32 { 0, 0 }
    xs[0] = 20
    xs[1] = 22
    return xs[0] + xs[1]
end
]]
assert(array_mod.__native_source ~= nil)
local array_compiled = array_mod()
assert(array_compiled.array_sum_local() == 42)
assert(array_compiled.array_sum_var() == 42)

local slice_mod = module[[
slice I32Slice = i32

func sum_slice(s: &I32Slice) -> i32
    var acc: i32 = 0
    var i: usize = 0
    while i < s.len do
        acc = acc + s[i]
        i = i + 1
    end
    return acc
end
]]
assert(slice_mod.__native_source ~= nil)
local compiled_slice = slice_mod()
local sbuf = ffi.new('int32_t[4]')
sbuf[0] = 10
sbuf[1] = 11
sbuf[2] = 12
sbuf[3] = 9
local slice_header = ffi.new('uint64_t[2]')
slice_header[0] = tonumber(ffi.cast('intptr_t', sbuf))
slice_header[1] = 4
local slice_ptr = tonumber(ffi.cast('intptr_t', slice_header))
assert(compiled_slice.sum_slice(slice_ptr) == 42)

local bits_tagged_src = [[
union NumberBits
    i: i32
    f: f32
end

impl NumberBits
    func as_i32(self: &NumberBits)
        self.i
    end
end

tagged union TaggedValue : u8
    I32
        value: i32
    end
    Pair
        a: i16
        b: i16
    end
end

impl TaggedValue
    func tag_code(self: &TaggedValue)
        cast<i32>(self.tag)
    end
end

func union_i(p: &NumberBits) -> i32
    p:as_i32()
end

func tagged_sum(tv: &TaggedValue) -> i32
    cast<i32>(tv.tag) + cast<i32>(tv.payload.Pair.a) + cast<i32>(tv.payload.Pair.b)
end
]]
local bits_tagged_mod = module(bits_tagged_src)
assert(bits_tagged_mod.__native_source ~= nil)
assert(bits_tagged_mod.NumberBits ~= nil)
assert(bits_tagged_mod.TaggedValue ~= nil)
local compiled_bits_tagged = bits_tagged_mod()
local nbbuf = ffi.new('int32_t[1]')
nbbuf[0] = 42
local nbptr = tonumber(ffi.cast('intptr_t', nbbuf))
assert(compiled_bits_tagged.union_i(nbptr) == 42)
assert(compiled_bits_tagged.NumberBits_as_i32(nbptr) == 42)
local tvbuf = ffi.new('uint8_t[?]', bits_tagged_mod.TaggedValue.size)
local tvptr = tonumber(ffi.cast('intptr_t', tvbuf))
local tvbytes = ffi.cast('uint8_t*', tvbuf)
tvbytes[0] = bits_tagged_mod.TaggedValue.Pair.node.value
local payload_i16 = ffi.cast('int16_t*', tvbytes + bits_tagged_mod.TaggedValue.payload.offset)
payload_i16[0] = 20
payload_i16[1] = 22
assert(compiled_bits_tagged.TaggedValue_tag_code(tvptr) == bits_tagged_mod.TaggedValue.Pair.node.value)
assert(compiled_bits_tagged.tagged_sum(tvptr) == bits_tagged_mod.TaggedValue.Pair.node.value + 20 + 22)

local backend = rawget(_G, '__moonlift_backend')
local handles, err = backend.compile_source_module(bits_tagged_src)
assert(type(handles) == 'table', err)
assert(#handles == 4)

local rich_bits_tagged_src = [[
union NumberBits
    i: i32
    f: f32
end

impl NumberBits
    func as_i32(self: &NumberBits)
        self.i
    end
end

tagged union TaggedValue : u8
    I32
        value: i32
    end
    Pair
        a: i16
        b: i16
    end
end

impl TaggedValue
    func tag_code(self: &TaggedValue)
        cast<i32>(self.tag)
    end
end

func union_i(p: &NumberBits) -> i32
    p:as_i32()
end

func union_inline() -> i32
    return NumberBits { i = 42 }:as_i32()
end

func tagged_sum(tv: &TaggedValue) -> i32
    cast<i32>(tv.tag) + cast<i32>(tv.payload.Pair.a) + cast<i32>(tv.payload.Pair.b)
end

func tagged_inline() -> i32
    return tagged_sum(TaggedValue.Pair { a = 20, b = 22 })
end

func tagged_local_full() -> i32
    let tv: TaggedValue = TaggedValue { tag = TaggedValue.Pair, payload = TaggedValue.Payload { Pair = TaggedValue.Pair { a = 20, b = 22 } } }
    return tagged_sum(tv)
end

func tagged_local_short() -> i32
    let tv = TaggedValue.Pair { a = 20, b = 22 }
    return tagged_sum(tv)
end

func tagged_field_mutate() -> i32
    var tv = TaggedValue.Pair { a = 0, b = 0 }
    tv.payload.Pair.a = 20
    tv.payload.Pair.b = 22
    return tagged_sum(tv)
end
]]
local rich_handles, rich_err = backend.compile_source_module(rich_bits_tagged_src)
assert(type(rich_handles) == 'table', rich_err)
assert(#rich_handles == 9)
assert(backend.call0(rich_handles[4]) == 42)
assert(backend.call1(rich_handles[5], tvptr) == bits_tagged_mod.TaggedValue.Pair.node.value + 20 + 22)
assert(backend.call0(rich_handles[6]) == bits_tagged_mod.TaggedValue.Pair.node.value + 20 + 22)
assert(backend.call0(rich_handles[7]) == bits_tagged_mod.TaggedValue.Pair.node.value + 20 + 22)
assert(backend.call0(rich_handles[8]) == bits_tagged_mod.TaggedValue.Pair.node.value + 20 + 22)
assert(backend.call0(rich_handles[9]) == bits_tagged_mod.TaggedValue.Pair.node.value + 20 + 22)

local pair_src = [[
struct Pair
    a: i32
    b: i32
end

impl Pair
    func sum(self: &Pair)
        self.a + self.b
    end
end

func pair_sum(p: &Pair)
    return p:sum()
end

func pair_sum_local() -> i32
    let p: Pair = Pair { a = 40, b = 2 }
    return p.a + p.b
end
]]
local handles2, err2 = backend.compile_source_module(pair_src)
assert(type(handles2) == 'table', err2)
assert(#handles2 == 3)
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

local for_continue = code[[
func for_continue(limit: i32) -> i32
    var acc: i32 = 0
    for i = 0, limit - 1 do
        if i == 2 then
            continue
        end
        acc = acc + 1
    end
    return acc
end
]]
local for_continue_h = for_continue()
assert(for_continue_h(5) == 4)

local reverse_sum = code[[
func reverse_sum() -> i32
    var acc: i32 = 0
    for i = 5, 1, -2 do
        acc = acc + i
    end
    return acc
end
]]
local reverse_sum_h = reverse_sum()
assert(reverse_sum_h() == 9)

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
    fn source_frontend_handles_recursive_inference_and_const_array_lengths() {
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

local type_splice = code[[
func id_spliced(x: @{i32}) -> @{i32}
    return x
end
]]
local id_spliced_h = type_splice()
assert(id_spliced_h(42) == 42)

local item_splice_mod = module[[
@{"func extra_answer() -> i32\n    return 42\nend"}
]]
local compiled_item_splice = item_splice_mod()
assert(compiled_item_splice.extra_answer() == 42)

local hole_bound_expr = expr("?L: i32 + ?R: i32", { L = 20, R = 22 })
assert(hole_bound_expr ~= nil and hole_bound_expr.t == i32)

local source_bound_expr = expr[[20 + 22]]
local hole_expr_code = code([[
func from_hole_expr() -> i32
    return ?E: i32
end
]], { E = source_bound_expr })
local from_hole_expr_h = hole_expr_code()
assert(from_hole_expr_h() == 42)

local hole_mod = module([[
const N = ?N: i32
const XS = [N]i32 { 10, 11, 12, 9 }

func hole_len_ok() -> i32
    return ?RET: i32
end
]], { N = 4, RET = 42 })
assert(hole_mod.__native_source ~= nil)
assert(hole_mod.XS ~= nil and hole_mod.XS._layout.count == 4)
local compiled_hole_mod = hole_mod()
assert(compiled_hole_mod.hole_len_ok() == 42)

local missing_hole_ok, missing_hole_err = pcall(function()
    return code[[
func missing_hole() -> i32
    return ?MISSING: i32
end
]]
end)
assert(not missing_hole_ok)
assert(tostring(missing_hole_err):find("source hole 'MISSING' is unbound", 1, true) ~= nil)

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
assert(array_len_mod.__native_source ~= nil)
assert(array_len_mod.Width.Four.node.value == 4)
assert(array_len_mod.XS ~= nil and array_len_mod.XS._layout.count == 4)
local compiled = array_len_mod()
assert(compiled.array_len_ok() == 42)

local e = expr[[if true then 42 else 0 end]]
assert(e ~= nil and e.t == i32)

local t = ml.type[[func(&u8, usize) -> void]]
assert(t ~= nil and t.name == 'func(1,2)->void')

local ext = ml.extern[[
@abi("C")
extern func abs(x: i32) -> i32
]]
assert(ext ~= nil and ext.name == 'abs')
assert(ext.result == i32)
assert(ext.params[1].t == i32)
"#,
        );
    }

    #[test]
    fn source_quote_expr_block_and_func_work() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()

local add_hole_q = ml.quote.expr[[
?lhs: i32 + ?rhs: i32
]]
local quoted_answer = (func "quoted_answer") {
    function()
        return add_hole_q:bind {
            lhs = expr[[20]],
            rhs = expr[[22]],
        }()
    end,
}
local quoted_answer_h = quoted_answer()
assert(quoted_answer_h() == 42)

local block_q = ml.quote.block[[
do
    let x: i32 = 20
    x + ?tail: i32
end
]]
local quoted_block = (func "quoted_block") {
    function()
        return block_q:bind { tail = 22 }()
    end,
}
local quoted_block_h = quoted_block()
assert(quoted_block_h() == 42)

local addk_q = ml.quote.func[[
func (x: i32) -> i32
    return x + ?k: i32
end
]]
local quoted_func = (func "quoted_func") {
    i32"x",
    addk_q:bind { k = expr[[2]] },
}
local quoted_func_h = quoted_func()
assert(quoted_func_h(40) == 42)

local array_t_q = ml.quote.type[[[?N: i32]i32]]
local free_type_holes = array_t_q:free_holes()
assert(free_type_holes.N == i32)
local hole_names = array_t_q:query {
    expr = function(node)
        if node.tag == 'hole' then return node.name end
    end,
}
assert(#hole_names == 1 and hole_names[1] == 'N')
local rewritten_array_t = array_t_q:rewrite {
    expr = function(node)
        if node.tag == 'hole' and node.name == 'N' then
            return { tag = 'number', raw = '4', kind = 'int' }
        end
    end,
}()
assert(rewritten_array_t ~= nil and rewritten_array_t.count == 4 and rewritten_array_t.elem == i32)
local array_t = array_t_q:bind { N = 4 }()
assert(array_t ~= nil and array_t.count == 4 and array_t.elem == i32)

local quoted_mod_q = ml.quote.module[[
func quoted_module_answer() -> i32
    return ?base: i32 + ?delta: i32
end
]]
local free_mod_holes = quoted_mod_q:free_holes()
assert(free_mod_holes.base == i32 and free_mod_holes.delta == i32)
local item_tags = quoted_mod_q:query {
    item = function(node)
        return node.tag
    end,
}
assert(#item_tags == 1 and item_tags[1] == 'func')
local rewritten_mod_q = quoted_mod_q:rewrite {
    expr = function(node)
        if node.tag == 'hole' and node.name == 'base' then
            return { tag = 'number', raw = '40', kind = 'int' }
        elseif node.tag == 'hole' and node.name == 'delta' then
            return { tag = 'number', raw = '2', kind = 'int' }
        end
    end,
}
local compiled_rewritten_mod = rewritten_mod_q()()
assert(compiled_rewritten_mod.quoted_module_answer() == 42)
local quoted_mod = quoted_mod_q:bind { base = 40, delta = 2 }()
local compiled_quoted_mod = quoted_mod()
assert(compiled_quoted_mod.quoted_module_answer() == 42)

local expr_splice_q = ml.quote.expr[[?lhs: i32 + ?rhs: i32]]:bind {
    lhs = expr[[20]],
    rhs = expr[[22]],
}
local spliced_expr_fn = code([[
func from_quote_expr() -> i32
    return @{expr_splice_q}
end
]], { expr_splice_q = expr_splice_q })
assert(spliced_expr_fn()() == 42)

local type_splice_q = ml.quote.type[[[?N: i32]i32]]:bind { N = 4 }
local spliced_type = ml.type("@{type_splice_q}", { type_splice_q = type_splice_q })
assert(spliced_type ~= nil and spliced_type.count == 4 and spliced_type.elem == i32)

local rewritten_type_splice_q = ml.quote.type[[[?N: i32]i32]]:rewrite {
    expr = function(node)
        if node.tag == 'hole' and node.name == 'N' then
            return { tag = 'number', raw = '4', kind = 'int' }
        end
    end,
}
local rewritten_spliced_type = ml.type("@{rewritten_type_splice_q}", { rewritten_type_splice_q = rewritten_type_splice_q })
assert(rewritten_spliced_type ~= nil and rewritten_spliced_type.count == 4 and rewritten_spliced_type.elem == i32)

local module_splice_q = ml.quote.module[[
func extra_answer() -> i32
    return 42
end
]]
local spliced_mod = module([[
@{module_splice_q}
]], { module_splice_q = module_splice_q })
assert(spliced_mod().extra_answer() == 42)

local rewritten_module_splice_q = ml.quote.module[[
func rewritten_extra() -> i32
    return ?x: i32
end
]]:rewrite {
    expr = function(node)
        if node.tag == 'hole' and node.name == 'x' then
            return { tag = 'number', raw = '42', kind = 'int' }
        end
    end,
}
local rewritten_spliced_mod = module([[
@{rewritten_module_splice_q}
]], { rewritten_module_splice_q = rewritten_module_splice_q })
assert(rewritten_spliced_mod().rewritten_extra() == 42)

local missing_bind_ok, missing_bind_err = pcall(function()
    local bad_q = ml.quote.expr[[?x: i32 + 1]]
    local f = (func "bad_q") {
        function()
            return bad_q()
        end,
    }
    return f()
end)
assert(not missing_bind_ok)
assert(tostring(missing_bind_err):find("quote hole 'x' is unbound", 1, true) ~= nil)
"#,
        );
    }

    #[test]
    fn builder_module_function_compile_is_dependency_granular() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()
local backend = rawget(_G, '__moonlift_backend')

local add2 = (func 'gran_add2') {
    i32'x',
    function(x)
        return x + 2
    end,
}

local use_add2 = (func 'gran_use_add2') {
    i32'x',
    function(x)
        return add2(x) * 2
    end,
}

local use_add2_plus1 = (func 'gran_use_add2_plus1') {
    i32'x',
    function(x)
        return add2(x) * 2 + 1
    end,
}

local unrelated = (func 'gran_unrelated') {
    i32'x',
    function(x)
        return x - 1
    end,
}

local mod = module { add2, use_add2, use_add2_plus1, unrelated }
local before = backend.stats()
local use_add2_h = use_add2()
local after = backend.stats()
assert(use_add2_h(19) == 42)
assert(after.compile_misses - before.compile_misses == 2)
assert(rawget(mod, '__compiled') == nil)
assert(rawget(mod, '__compiled_granular') ~= nil)

local shared_before = after.compile_misses
local use_add2_plus1_h = use_add2_plus1()
local after_shared = backend.stats()
assert(use_add2_plus1_h(20) == 45)
assert(after_shared.compile_misses - shared_before == 1)

local unrelated_before = after_shared.compile_misses
local unrelated_h = unrelated()
local after2 = backend.stats()
assert(unrelated_h(43) == 42)
assert(after2.compile_misses - unrelated_before == 1)
"#,
        );
    }

    #[test]
    fn source_module_function_compile_is_dependency_granular() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()
local backend = rawget(_G, '__moonlift_backend')

local mod = module[[
func add2(x: i32) -> i32
    return x + 2
end

func use_add2(x: i32) -> i32
    return add2(x) * 2
end

func use_add2_plus1(x: i32) -> i32
    return add2(x) * 2 + 1
end

func unrelated(x: i32) -> i32
    return x - 1
end
]]

local before = backend.stats()
local use_add2_h = mod.use_add2()
local after = backend.stats()
assert(use_add2_h(19) == 42)
assert(after.compile_misses - before.compile_misses == 2)
assert(rawget(mod, '__compiled') == nil)
assert(rawget(mod, '__compiled_granular') ~= nil)

local shared_before = after.compile_misses
local use_add2_plus1_h = mod.use_add2_plus1()
local after_shared = backend.stats()
assert(use_add2_plus1_h(20) == 45)
assert(after_shared.compile_misses - shared_before == 1)

local unrelated_before = after_shared.compile_misses
local unrelated_h = mod.unrelated()
local after2 = backend.stats()
assert(unrelated_h(43) == 42)
assert(after2.compile_misses - unrelated_before == 1)
"#,
        );
    }

    #[test]
    fn canonical_loop_source_forms_work() {
        run_lua_test(
            r#"
local ffi = require('ffi')
local ml = require('moonlift')
ml.use()
local backend = rawget(_G, '__moonlift_backend')

local mod = module[[
slice F32Slice = f32

func sum_while(n: usize) -> i32
    return loop i: index = 0, acc: i32 = 0 while i < n
        let xi: i32 = cast<i32>(i) + 1
    next
        acc = acc + xi
        i = i + 1
    end -> acc
end

func sum_range(n: usize) -> i32
    return loop i over range(n), acc: i32 = 0
    next
        acc = acc + cast<i32>(i) + 1
    end -> acc
end

func sum_range_from_one(n: i64) -> i64
    return loop i over range(1, n), acc: i64 = 0
    next
        acc = acc + i
    end -> acc
end

func sum_while_induction_last(n: usize) -> i32
    return loop acc: i32 = 0, i: index = 0 while i < n
        let xi: i32 = cast<i32>(i) + 1
    next
        acc = acc + xi
        i = i + 1
    end -> acc
end

func sum_desc() -> i32
    return loop i: i32 = 5, acc: i32 = 0 while i > 0
    next
        acc = acc + i
        i = i - 2
    end -> acc
end

func iter_final() -> i32
    return loop i: i32 = 0 while i < 3
    next
        i = i + 1
    end -> i
end

func no_iter_final() -> i32
    return loop i: i32 = 7 while false
    next
        i = i + 1
    end -> i
end

func sum_desc_slice(s: &F32Slice) -> f32
    return loop i: index = s.len, acc: f32 = 0.0 while i > 0
    next
        acc = acc + s[i - 1]
        i = i - 1
    end -> acc
end

func gain_sum(dst: &F32Slice, src: &F32Slice, gain: f32) -> f32
    return loop i over zip_eq(dst, src), acc: f32 = 0.0
        let y = src[i] * gain
        dst[i] = y
    next
        acc = acc + y
    end -> acc
end
]]
assert(mod.__native_source ~= nil)
local compiled = mod()
assert(compiled.sum_while(6) == 21)
assert(compiled.sum_range(6) == 21)
assert(compiled.sum_range_from_one(7) == 21)
assert(compiled.sum_while_induction_last(6) == 21)
assert(compiled.sum_desc() == 9)
assert(compiled.iter_final() == 3)
assert(compiled.no_iter_final() == 7)

local src = ffi.new('float[4]', {1, 2, 3, 4})
local dst = ffi.new('float[4]')
local src_header = ffi.new('uint64_t[2]')
local dst_header = ffi.new('uint64_t[2]')
src_header[0] = tonumber(ffi.cast('intptr_t', src))
src_header[1] = 4
dst_header[0] = tonumber(ffi.cast('intptr_t', dst))
dst_header[1] = 4
local src_ptr = tonumber(ffi.cast('intptr_t', src_header))
local dst_ptr = tonumber(ffi.cast('intptr_t', dst_header))
local total = compiled.gain_sum(dst_ptr, src_ptr, 0.5)
assert(math.abs(total - 5.0) < 1e-6)
for i = 0, 3 do
    assert(math.abs(dst[i] - src[i] * 0.5) < 1e-6)
end
assert(math.abs(compiled.sum_desc_slice(src_ptr) - 10.0) < 1e-6)

local e = expr[[loop i over range(4), acc: i32 = 0
next
    acc = acc + cast<i32>(i)
end -> acc]]
assert(e ~= nil and e.t == i32)

local e2 = expr[[loop i: index = 0, acc: i32 = 0 while i < 4
next
    acc = acc + cast<i32>(i)
    i = i + 1
end -> acc]]
assert(e2 ~= nil and e2.t == i32)

local loop_while_opt = assert(backend.dump_optimized_source_code_spec([[
func loop_sum(n: usize) -> i32
    return loop i: index = 0, acc: i32 = 0 while i < n
    next
        acc = acc + cast<i32>(i)
        i = i + 1
    end -> acc
end
]]))
assert(loop_while_opt:find('ForRange {', 1, true) ~= nil)
assert(loop_while_opt:find('LoopWhile {', 1, true) == nil)

local loop_while_induction_last_opt = assert(backend.dump_optimized_source_code_spec([[
func loop_sum_reordered(n: usize) -> i32
    return loop acc: i32 = 0, i: index = 0 while i < n
        let xi: i32 = cast<i32>(i)
    next
        acc = acc + xi
        i = i + 1
    end -> acc
end
]]))
assert(loop_while_induction_last_opt:find('ForRange {', 1, true) ~= nil)
assert(loop_while_induction_last_opt:find('LoopWhile {', 1, true) == nil)

local loop_while_desc_opt = assert(backend.dump_optimized_source_code_spec([[
func loop_sum_desc() -> i32
    return loop i: i32 = 5, acc: i32 = 0 while i > 0
    next
        acc = acc + i
        i = i - 2
    end -> acc
end
]]))
assert(loop_while_desc_opt:find('ForRange {', 1, true) ~= nil)
assert(loop_while_desc_opt:find('LoopWhile {', 1, true) == nil)

local desc_index_opt = assert(backend.dump_optimized_source_code_spec([[
func sum_desc_arr() -> f32
    let xs: [4]f32 = [4]f32 { 1.0, 2.0, 3.0, 4.0 }
    return loop i: index = 4, acc: f32 = 0.0 while i > 0
    next
        acc = acc + xs[i - 1]
        i = i - 1
    end -> acc
end
]]))
assert(desc_index_opt:find('dir:', 1, true) ~= nil)
assert(desc_index_opt:find('Desc', 1, true) ~= nil)
assert(desc_index_opt:find('If {', 1, true) ~= nil)
assert(desc_index_opt:find('limit: None', 1, true) ~= nil)

local switch_select_opt = assert(backend.dump_optimized_source_code_spec([[
func switch_sum(n: i64) -> i64
    return loop i: i64 = 0, acc: i64 = 0 while i < n
        let r: i64 = i % 7
        let add: i64 = switch r do
            case 0 then 1
            case 1 then 3
            case 2 then 5
            case 3 then 7
            case 4 then 11
            case 5 then 13
            default then 17
        end
    next
        i = i + 1
        acc = acc + add
    end -> acc
end
]]))
assert(switch_select_opt:find('Select {', 1, true) ~= nil)
assert(switch_select_opt:find('If {', 1, true) == nil)
"#,
        );
    }

    #[test]
    fn compiled_i64_u64_results_keep_exact_host_values() {
        run_lua_test(
            r#"
local ffi = require('ffi')
local ml = require('moonlift')
ml.use()
local backend = rawget(_G, '__moonlift_backend')

local h64 = code[[
func big_i64() -> i64
    return 9007199254740992 + 123
end
]]()
local r64 = h64()
assert(type(r64) == 'cdata')
assert(exact_tostring(r64) == '9007199254741115')
assert(string.format('%d', r64) == '9007199254741115')
local r64_raw = backend.call0(h64.handle)
assert(type(r64_raw) == 'cdata')
assert(exact_tostring(r64_raw) == '9007199254741115')
assert(string.format('%d', r64_raw) == '9007199254741115')

local hu64 = code[[
func small_u64() -> u64
    return 42
end
]]()
local ru64 = hu64()
assert(type(ru64) == 'cdata')
assert(exact_tostring(ru64) == '42')
assert(string.format('%u', ru64) == '42')
local ru64_raw = backend.call0(hu64.handle)
assert(type(ru64_raw) == 'cdata')
assert(exact_tostring(ru64_raw) == '42')
assert(string.format('%u', ru64_raw) == '42')

local hid = (func 'id_ptr') {
    ptr(u8)'p',
    ptr(u8),
    function(p)
        return p
    end,
}()
local buf = ffi.new('uint8_t[1]')
local addr = tonumber(ffi.cast('intptr_t', buf))
local expected_ptr = string.format('%u', ffi.cast('uint64_t', addr))
local rptr = hid(addr)
assert(type(rptr) == 'cdata')
assert(exact_tostring(rptr) == expected_ptr)
assert(string.format('%u', rptr) == expected_ptr)
local rptr_raw = backend.call1(hid.handle, addr)
assert(type(rptr_raw) == 'cdata')
assert(exact_tostring(rptr_raw) == expected_ptr)
assert(string.format('%u', rptr_raw) == expected_ptr)
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

    #[test]
    fn optimized_spec_dumps_match_and_loop_opts_fire() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()
local backend = rawget(_G, '__moonlift_backend')

local recur_src = [[
func recur_loop(n: u64) -> u64
    var x: u64 = 0
    var i: u64 = 0
    while i < n do
        x = x * 1664525 + i + 1013904223
        i = i + 1
    end
    return x
end
]]

local recur_builder = (func 'recur_loop') {
    u64'n',
    function(n)
        return block(function()
            local x = var(u64(0))
            local i = var(u64(0))
            while_(i:lt(n), function()
                x:set(x * u64(1664525) + i + u64(1013904223))
                i:set(i + u64(1))
            end)
            return x
        end)
    end,
}

local recur_source_opt = assert(backend.dump_optimized_source_code_spec(recur_src))
local recur_builder_opt = assert(backend.dump_optimized_spec(recur_builder.lowered))
assert(recur_source_opt == recur_builder_opt)
assert(recur_source_opt:find('While {', 1, true) ~= nil)
assert(recur_source_opt:find('ForRange {', 1, true) == nil)
assert(recur_source_opt:find('__mlopt_var$1_chunkc8', 1, true) == nil)
assert(recur_source_opt:find('bits: 1664525', 1, true) ~= nil)
assert(recur_source_opt:find('bits: 1013904223', 1, true) ~= nil)

local add_source_opt = assert(backend.dump_optimized_source_code_spec[[
func add_loop(n: i64) -> i64
    var x: i64 = 0
    var i: i64 = 0
    while i < n do
        x = x + 1
        i = i + 1
    end
    return x
end
]])
assert(add_source_opt:find('While {', 1, true) ~= nil)
assert(add_source_opt:find('ForRange {', 1, true) == nil)

local recur_disasm = assert(backend.dump_source_code_disasm(recur_src))
assert(recur_disasm:find(';; clif', 1, true) ~= nil)
assert(recur_disasm:find(';; vcode', 1, true) ~= nil)
assert(recur_disasm:find('block0', 1, true) ~= nil or recur_disasm:find('block1', 1, true) ~= nil)
"#,
        );
    }

    #[test]
    fn optimized_static_array_bounds_checks_hoist() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()
local backend = rawget(_G, '__moonlift_backend')

local src = [[
func sum_arr() -> i32
    let xs: [4]i32 = [4]i32 { 10, 11, 12, 9 }
    return loop i: i32 = 0, acc: i32 = 0 while i < 4
    next
        acc = acc + xs[i]
        i = i + 1
    end -> acc
end
]]

local opt = assert(backend.dump_optimized_source_code_spec(src))
assert(opt:find('BoundsCheck {', 1, true) == nil)
assert(opt:find('IndexAddr {', 1, true) ~= nil)
assert(opt:find('limit: None', 1, true) ~= nil)
"#,
        );
    }

    #[test]
    fn optimized_slice_bounds_checks_hoist_affine_window() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()
local ffi = require('ffi')
local backend = rawget(_G, '__moonlift_backend')
local debug = ml.debug

local I32Slice = slice(i32)
local builder = (func 'sum_slice_affine2') {
    ptr(I32Slice)'s',
    function(s)
        return block(function()
            local acc = var(i32(0))
            for_range_(usize(0), s.len - usize(3), function(i)
                acc:set(acc + s[(i + usize(1)) + usize(1)])
            end)
            return acc
        end)
    end,
}

local raw = assert(backend.dump_spec(builder.lowered))
local opt = debug.dump_optimized_spec(builder.lowered)
assert(raw:find('limit: Some(', 1, true) ~= nil)
assert(opt:find('BoundsCheck {', 1, true) ~= nil)
assert(opt:find('limit: None', 1, true) ~= nil)
assert(debug.dump_raw_disasm(builder.lowered):find('trapz', 1, true) ~= nil)
assert(debug.dump_disasm(builder.lowered):find('trapz', 1, true) ~= nil)

local raw_handle = assert(backend.compile_unoptimized(builder.lowered))
local opt_handle = assert(backend.compile(builder.lowered))
local buf = ffi.new('int32_t[6]')
buf[0] = 1; buf[1] = 2; buf[2] = 10; buf[3] = 11; buf[4] = 12; buf[5] = 9
local hdr = ffi.new('uint64_t[2]')
hdr[0] = tonumber(ffi.cast('intptr_t', buf))
hdr[1] = 6
local sptr = tonumber(ffi.cast('intptr_t', hdr))
assert(backend.call1(raw_handle, sptr) == 42)
assert(backend.call1(opt_handle, sptr) == 42)
"#,
        );
    }

    #[test]
    fn supports_generic_packed_abi_beyond_four_args() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()
local backend = rawget(_G, '__moonlift_backend')

local builder = (func 'sum6_builder') {
    i32'a',
    i32'b',
    i32'c',
    i32'd',
    i32'e',
    i32'f',
    function(a, b, c, d, e, f)
        return a + b + c + d + e + f
    end,
}
local builder_h = builder()
assert(rawget(builder_h, '__fast_call') ~= nil)
assert(builder_h(1, 2, 3, 4, 5, 27) == 42)
local builder_handle, builder_err = backend.compile(builder.lowered)
assert(type(builder_handle) == 'number' and builder_handle > 0, builder_err)
assert(backend.call(builder_handle, 1, 2, 3, 4, 5, 27) == 42)

local src_text = [[
func sum6_source(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32) -> i32
    return a + b + c + d + e + f
end
]]
local source_fn = code(src_text)
local source_h = source_fn()
assert(rawget(source_h, '__fast_call') ~= nil)
assert(source_h(1, 2, 3, 4, 5, 27) == 42)
local source_handle, source_err = backend.compile_source_code(src_text)
assert(type(source_handle) == 'number' and source_handle > 0, source_err)
assert(backend.call(source_handle, 1, 2, 3, 4, 5, 27) == 42)
"#,
        );
    }

    #[test]
    fn rust_source_matches_builder_for_float_kernels() {
        run_lua_test(
            r#"
local ml = require('moonlift')
ml.use()
local debug = ml.debug

local function assert_same(src, builder)
    local cmp = debug.compare_source_builder(src, builder.lowered)
    assert(cmp.spec.same)
    assert(cmp.disasm.same)
end

assert_same([[
func audio_gain(src: &f32, dst: &f32, n: i32, gain: f32) -> f32
    var i: i32 = 0
    var last: f32 = cast<f32>(0.0)
    while i < n do
        let y: f32 = src[i] * gain
        dst[i] = y
        last = y
        i = i + 1
    end
    return last
end
]], (func 'audio_gain') {
    ptr(f32)'src',
    ptr(f32)'dst',
    i32'n',
    f32'gain',
    function(src, dst, n, gain)
        return block(function()
            local i = var(i32(0))
            local last = var(f32(0.0))
            while_(i:lt(n), function()
                local y = let(src[i] * gain)
                dst[i] = y
                last:set(y)
                i:set(i + i32(1))
            end)
            return last
        end)
    end,
})

assert_same([[
func audio_mix2(src_a: &f32, src_b: &f32, dst: &f32, n: i32) -> f32
    var i: i32 = 0
    var last: f32 = cast<f32>(0.0)
    while i < n do
        let y: f32 = src_a[i] * cast<f32>(0.65) + src_b[i] * cast<f32>(0.35)
        dst[i] = y
        last = y
        i = i + 1
    end
    return last
end
]], (func 'audio_mix2') {
    ptr(f32)'src_a',
    ptr(f32)'src_b',
    ptr(f32)'dst',
    i32'n',
    function(src_a, src_b, dst, n)
        return block(function()
            local i = var(i32(0))
            local last = var(f32(0.0))
            while_(i:lt(n), function()
                local y = let(src_a[i] * f32(0.65) + src_b[i] * f32(0.35))
                dst[i] = y
                last:set(y)
                i:set(i + i32(1))
            end)
            return last
        end)
    end,
})

assert_same([[
func audio_env_follow(src: &f32, dst: &f32, n: i32) -> f32
    var i: i32 = 0
    var env: f32 = cast<f32>(0.0)
    while i < n do
        let x: f32 = src[i]
        let ax: f32 = if x < cast<f32>(0.0) then cast<f32>(0.0) - x else x end
        let coeff: f32 = if ax > env then cast<f32>(0.15) else cast<f32>(0.002) end
        env = env + coeff * (ax - env)
        dst[i] = env
        i = i + 1
    end
    return env
end
]], (func 'audio_env_follow') {
    ptr(f32)'src',
    ptr(f32)'dst',
    i32'n',
    function(src, dst, n)
        return block(function()
            local i = var(i32(0))
            local env = var(f32(0.0))
            while_(i:lt(n), function()
                local x = let(src[i])
                local ax = let((x:lt(f32(0.0)))(f32(0.0) - x, x))
                local coeff = let((ax:gt(env))(f32(0.15), f32(0.002)))
                env:set(env + coeff * (ax - env))
                dst[i] = env
                i:set(i + i32(1))
            end)
            return env
        end)
    end,
})
"#,
        );
    }
}
