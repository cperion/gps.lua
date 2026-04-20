use std::error::Error;
use std::ffi::{CStr, CString};
use std::fmt;
use std::os::raw::{c_char, c_double, c_int, c_longlong, c_void};
use std::ptr::NonNull;

pub const LUA_MULTRET: c_int = -1;
pub const LUA_OK: c_int = 0;
pub const LUA_GLOBALSINDEX: c_int = -10002;
pub const LUA_TNIL: c_int = 0;
pub const LUA_TSTRING: c_int = 4;
pub const LUA_TTABLE: c_int = 5;

#[allow(non_camel_case_types)]
pub type lua_Integer = isize;
#[allow(non_camel_case_types)]
pub type lua_Number = c_double;
pub type LuaCFunction = unsafe extern "C" fn(*mut lua_State) -> c_int;

#[repr(C)]
pub struct lua_State {
    _private: [u8; 0],
}

unsafe extern "C" {
    fn luaL_newstate() -> *mut lua_State;
    fn luaL_openlibs(state: *mut lua_State);
    fn luaL_loadfile(state: *mut lua_State, filename: *const c_char) -> c_int;
    fn luaL_loadstring(state: *mut lua_State, s: *const c_char) -> c_int;
    fn lua_pcall(state: *mut lua_State, nargs: c_int, nresults: c_int, errfunc: c_int) -> c_int;
    fn lua_tolstring(state: *mut lua_State, idx: c_int, len: *mut usize) -> *const c_char;
    fn lua_settop(state: *mut lua_State, idx: c_int);
    fn lua_gettop(state: *mut lua_State) -> c_int;
    fn lua_type(state: *mut lua_State, idx: c_int) -> c_int;
    fn lua_close(state: *mut lua_State);
    fn lua_pushlightuserdata(state: *mut lua_State, p: *mut c_void);
    fn lua_pushcclosure(state: *mut lua_State, f: LuaCFunction, n: c_int);
    fn lua_pushinteger(state: *mut lua_State, n: lua_Integer);
    fn lua_pushnumber(state: *mut lua_State, n: lua_Number);
    fn lua_pushboolean(state: *mut lua_State, b: c_int);
    fn lua_pushnil(state: *mut lua_State);
    fn lua_pushstring(state: *mut lua_State, s: *const c_char) -> *const c_char;
    fn lua_error(state: *mut lua_State) -> c_int;
    fn lua_tointeger(state: *mut lua_State, idx: c_int) -> lua_Integer;
    fn lua_tonumber(state: *mut lua_State, idx: c_int) -> lua_Number;
    fn lua_toboolean(state: *mut lua_State, idx: c_int) -> c_int;
    fn lua_getfield(state: *mut lua_State, idx: c_int, k: *const c_char);
    fn lua_rawgeti(state: *mut lua_State, idx: c_int, n: c_longlong);
    fn lua_rawseti(state: *mut lua_State, idx: c_int, n: c_longlong);
    fn lua_touserdata(state: *mut lua_State, idx: c_int) -> *mut c_void;
    fn lua_setfield(state: *mut lua_State, idx: c_int, k: *const c_char);
    fn lua_createtable(state: *mut lua_State, narr: c_int, nrec: c_int);
}

#[derive(Debug)]
pub struct LuaError {
    pub code: c_int,
    pub message: String,
}

impl fmt::Display for LuaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "lua error {}: {}", self.code, self.message)
    }
}

impl Error for LuaError {}

pub struct LuaState {
    raw: NonNull<lua_State>,
}

impl LuaState {
    pub fn new() -> Result<Self, LuaError> {
        let raw = unsafe { luaL_newstate() };
        let raw = NonNull::new(raw).ok_or_else(|| LuaError {
            code: -1,
            message: "luaL_newstate returned null".to_string(),
        })?;
        Ok(Self { raw })
    }

    pub fn openlibs(&mut self) {
        unsafe { luaL_openlibs(self.raw.as_ptr()) }
    }

    pub fn set_lightuserdata_global(&mut self, name: &str, ptr: *mut c_void) -> Result<(), LuaError> {
        let cname = CString::new(name).map_err(|_| LuaError {
            code: -1,
            message: format!("global name contains interior NUL: {name:?}"),
        })?;
        unsafe {
            lua_pushlightuserdata(self.raw.as_ptr(), ptr);
            lua_setfield(self.raw.as_ptr(), LUA_GLOBALSINDEX, cname.as_ptr());
        }
        Ok(())
    }

    pub fn new_table(&mut self, narr: c_int, nrec: c_int) {
        unsafe { lua_createtable(self.raw.as_ptr(), narr, nrec) }
    }

    pub fn set_cfunction_field_on_top(&mut self, name: &str, f: LuaCFunction) -> Result<(), LuaError> {
        let cname = CString::new(name).map_err(|_| LuaError {
            code: -1,
            message: format!("field name contains interior NUL: {name:?}"),
        })?;
        unsafe {
            lua_pushcclosure(self.raw.as_ptr(), f, 0);
            lua_setfield(self.raw.as_ptr(), -2, cname.as_ptr());
        }
        Ok(())
    }

    pub fn set_global_from_top(&mut self, name: &str) -> Result<(), LuaError> {
        let cname = CString::new(name).map_err(|_| LuaError {
            code: -1,
            message: format!("global name contains interior NUL: {name:?}"),
        })?;
        unsafe { lua_setfield(self.raw.as_ptr(), LUA_GLOBALSINDEX, cname.as_ptr()) }
        Ok(())
    }

    pub fn get_lightuserdata_global_from_state(
        state: *mut lua_State,
        name: &str,
    ) -> Result<*mut c_void, LuaError> {
        let cname = CString::new(name).map_err(|_| LuaError {
            code: -1,
            message: format!("global name contains interior NUL: {name:?}"),
        })?;
        let ptr = unsafe {
            lua_getfield(state, LUA_GLOBALSINDEX, cname.as_ptr());
            let ptr = lua_touserdata(state, -1);
            lua_settop(state, -2);
            ptr
        };
        Ok(ptr)
    }

    pub unsafe fn to_integer(state: *mut lua_State, idx: c_int) -> lua_Integer {
        unsafe { lua_tointeger(state, idx) }
    }

    pub unsafe fn push_integer(state: *mut lua_State, value: lua_Integer) {
        unsafe { lua_pushinteger(state, value) }
    }

    pub unsafe fn to_number(state: *mut lua_State, idx: c_int) -> lua_Number {
        unsafe { lua_tonumber(state, idx) }
    }

    pub unsafe fn push_number(state: *mut lua_State, value: lua_Number) {
        unsafe { lua_pushnumber(state, value) }
    }

    pub unsafe fn to_boolean(state: *mut lua_State, idx: c_int) -> bool {
        unsafe { lua_toboolean(state, idx) != 0 }
    }

    pub unsafe fn push_boolean(state: *mut lua_State, value: bool) {
        unsafe { lua_pushboolean(state, if value { 1 } else { 0 }) }
    }

    pub unsafe fn push_nil(state: *mut lua_State) {
        unsafe { lua_pushnil(state) }
    }

    pub unsafe fn push_string(state: *mut lua_State, value: &str) -> Result<(), LuaError> {
        let cvalue = CString::new(value).map_err(|_| LuaError {
            code: -1,
            message: "lua string contains interior NUL".to_string(),
        })?;
        unsafe { lua_pushstring(state, cvalue.as_ptr()) };
        Ok(())
    }

    pub unsafe fn create_table(state: *mut lua_State, narr: c_int, nrec: c_int) {
        unsafe { lua_createtable(state, narr, nrec) }
    }

    pub unsafe fn set_integer_field_on_top(
        state: *mut lua_State,
        name: &str,
        value: lua_Integer,
    ) -> Result<(), LuaError> {
        let cname = CString::new(name).map_err(|_| LuaError {
            code: -1,
            message: format!("field name contains interior NUL: {name:?}"),
        })?;
        unsafe {
            lua_pushinteger(state, value);
            lua_setfield(state, -2, cname.as_ptr());
        }
        Ok(())
    }

    pub unsafe fn set_string_field_on_top(
        state: *mut lua_State,
        name: &str,
        value: &str,
    ) -> Result<(), LuaError> {
        let cname = CString::new(name).map_err(|_| LuaError {
            code: -1,
            message: format!("field name contains interior NUL: {name:?}"),
        })?;
        let cvalue = CString::new(value).map_err(|_| LuaError {
            code: -1,
            message: "lua string contains interior NUL".to_string(),
        })?;
        unsafe {
            lua_pushstring(state, cvalue.as_ptr());
            lua_setfield(state, -2, cname.as_ptr());
        }
        Ok(())
    }

    pub unsafe fn set_field_from_top(
        state: *mut lua_State,
        idx: c_int,
        name: &str,
    ) -> Result<(), LuaError> {
        let cname = CString::new(name).map_err(|_| LuaError {
            code: -1,
            message: format!("field name contains interior NUL: {name:?}"),
        })?;
        unsafe {
            lua_setfield(state, idx, cname.as_ptr());
        }
        Ok(())
    }

    pub unsafe fn gettop(state: *mut lua_State) -> c_int {
        unsafe { lua_gettop(state) }
    }

    pub unsafe fn get_type(state: *mut lua_State, idx: c_int) -> c_int {
        unsafe { lua_type(state, idx) }
    }

    pub unsafe fn pop(state: *mut lua_State, n: c_int) {
        unsafe { lua_settop(state, -n - 1) }
    }

    pub unsafe fn get_field(state: *mut lua_State, idx: c_int, name: &str) -> Result<(), LuaError> {
        let cname = CString::new(name).map_err(|_| LuaError {
            code: -1,
            message: format!("field name contains interior NUL: {name:?}"),
        })?;
        unsafe { lua_getfield(state, idx, cname.as_ptr()) };
        Ok(())
    }

    pub unsafe fn raw_get_i(state: *mut lua_State, idx: c_int, n: i64) {
        unsafe { lua_rawgeti(state, idx, n as c_longlong) }
    }

    pub unsafe fn raw_set_i_from_top(state: *mut lua_State, idx: c_int, n: i64) {
        unsafe { lua_rawseti(state, idx, n as c_longlong) }
    }

    pub unsafe fn to_string(state: *mut lua_State, idx: c_int) -> Option<String> {
        let ptr = unsafe { lua_tolstring(state, idx, std::ptr::null_mut()) };
        if ptr.is_null() {
            None
        } else {
            Some(unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned())
        }
    }

    pub unsafe fn raise_error(state: *mut lua_State, message: &str) -> c_int {
        let cmsg = CString::new(message).unwrap_or_else(|_| CString::new("moonlift error").unwrap());
        unsafe {
            lua_pushstring(state, cmsg.as_ptr());
            lua_error(state)
        }
    }

    pub fn dostring(&mut self, source: &str) -> Result<(), LuaError> {
        let csrc = CString::new(source).map_err(|_| LuaError {
            code: -1,
            message: "lua source contains interior NUL".to_string(),
        })?;

        let load_rc = unsafe { luaL_loadstring(self.raw.as_ptr(), csrc.as_ptr()) };
        if load_rc != LUA_OK {
            return Err(self.last_error(load_rc));
        }

        let call_rc = unsafe { lua_pcall(self.raw.as_ptr(), 0, LUA_MULTRET, 0) };
        if call_rc != LUA_OK {
            return Err(self.last_error(call_rc));
        }
        Ok(())
    }

    pub fn dofile(&mut self, path: &str) -> Result<(), LuaError> {
        let cpath = CString::new(path).map_err(|_| LuaError {
            code: -1,
            message: format!("script path contains interior NUL: {path:?}"),
        })?;

        let load_rc = unsafe { luaL_loadfile(self.raw.as_ptr(), cpath.as_ptr()) };
        if load_rc != LUA_OK {
            return Err(self.last_error(load_rc));
        }

        let call_rc = unsafe { lua_pcall(self.raw.as_ptr(), 0, LUA_MULTRET, 0) };
        if call_rc != LUA_OK {
            return Err(self.last_error(call_rc));
        }
        Ok(())
    }

    #[allow(dead_code)]
    pub fn raw(&mut self) -> *mut lua_State {
        self.raw.as_ptr()
    }

    fn last_error(&mut self, code: c_int) -> LuaError {
        let message = unsafe {
            let ptr = lua_tolstring(self.raw.as_ptr(), -1, std::ptr::null_mut());
            if ptr.is_null() {
                format!("lua error code {}", code)
            } else {
                CStr::from_ptr(ptr).to_string_lossy().into_owned()
            }
        };
        unsafe { lua_settop(self.raw.as_ptr(), -2) };
        LuaError { code, message }
    }
}

impl Drop for LuaState {
    fn drop(&mut self) {
        unsafe { lua_close(self.raw.as_ptr()) }
    }
}
