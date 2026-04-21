package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("pvm")

ffi.cdef [[
typedef struct moonlift_jit_t moonlift_jit_t;
typedef struct moonlift_program_t moonlift_program_t;
typedef struct moonlift_artifact_t moonlift_artifact_t;

const char* moonlift_last_error_message(void);

moonlift_jit_t* moonlift_jit_new(void);
void moonlift_jit_free(moonlift_jit_t*);
int moonlift_jit_symbol(moonlift_jit_t*, const char* name, const void* ptr);
moonlift_artifact_t* moonlift_jit_compile(moonlift_jit_t*, const moonlift_program_t*);

moonlift_program_t* moonlift_program_new(void);
void moonlift_program_free(moonlift_program_t*);

void moonlift_artifact_free(moonlift_artifact_t*);
const void* moonlift_artifact_getpointer(const moonlift_artifact_t*, const char* func);

int moonlift_program_cmd_create_sig(moonlift_program_t*, const char* sig, const uint32_t* params, size_t params_len, const uint32_t* results, size_t results_len);
int moonlift_program_cmd_declare_data(moonlift_program_t*, const char* data, uint32_t size, uint32_t align);
int moonlift_program_cmd_data_init_zero(moonlift_program_t*, const char* data, uint32_t offset, uint32_t size);
int moonlift_program_cmd_data_init_int(moonlift_program_t*, const char* data, uint32_t offset, uint32_t ty, const char* raw);
int moonlift_program_cmd_data_init_float(moonlift_program_t*, const char* data, uint32_t offset, uint32_t ty, const char* raw);
int moonlift_program_cmd_data_init_bool(moonlift_program_t*, const char* data, uint32_t offset, int value);
int moonlift_program_cmd_declare_func_local(moonlift_program_t*, const char* func, const char* sig);
int moonlift_program_cmd_declare_func_export(moonlift_program_t*, const char* func, const char* sig);
int moonlift_program_cmd_declare_func_extern(moonlift_program_t*, const char* func, const char* symbol, const char* sig);
int moonlift_program_cmd_begin_func(moonlift_program_t*, const char* func);
int moonlift_program_cmd_create_block(moonlift_program_t*, const char* block);
int moonlift_program_cmd_switch_to_block(moonlift_program_t*, const char* block);
int moonlift_program_cmd_seal_block(moonlift_program_t*, const char* block);
int moonlift_program_cmd_bind_entry_params(moonlift_program_t*, const char* block, const char* const* values, size_t values_len);
int moonlift_program_cmd_append_block_param(moonlift_program_t*, const char* block, const char* value, uint32_t ty);
int moonlift_program_cmd_create_stack_slot(moonlift_program_t*, const char* slot, uint32_t size, uint32_t align);
int moonlift_program_cmd_alias(moonlift_program_t*, const char* dst, const char* src);
int moonlift_program_cmd_stack_addr(moonlift_program_t*, const char* dst, const char* slot);
int moonlift_program_cmd_data_addr(moonlift_program_t*, const char* dst, const char* data);
int moonlift_program_cmd_const_int(moonlift_program_t*, const char* dst, uint32_t ty, const char* raw);
int moonlift_program_cmd_const_float(moonlift_program_t*, const char* dst, uint32_t ty, const char* raw);
int moonlift_program_cmd_const_bool(moonlift_program_t*, const char* dst, int value);
int moonlift_program_cmd_const_null(moonlift_program_t*, const char* dst);
int moonlift_program_cmd_unary(moonlift_program_t*, uint32_t op, const char* dst, uint32_t ty, const char* value);
int moonlift_program_cmd_binary(moonlift_program_t*, uint32_t op, const char* dst, uint32_t ty, const char* lhs, const char* rhs);
int moonlift_program_cmd_cast(moonlift_program_t*, uint32_t op, const char* dst, uint32_t ty, const char* value);
int moonlift_program_cmd_load(moonlift_program_t*, const char* dst, uint32_t ty, const char* addr);
int moonlift_program_cmd_store(moonlift_program_t*, uint32_t ty, const char* addr, const char* value);
int moonlift_program_cmd_select(moonlift_program_t*, const char* dst, uint32_t ty, const char* cond, const char* then_value, const char* else_value);
int moonlift_program_cmd_call_value(moonlift_program_t*, uint32_t kind, const char* dst, uint32_t ty, const char* target, const char* sig, const char* const* args, size_t args_len);
int moonlift_program_cmd_call_stmt(moonlift_program_t*, uint32_t kind, const char* target, const char* sig, const char* const* args, size_t args_len);
int moonlift_program_cmd_jump(moonlift_program_t*, const char* dest, const char* const* args, size_t args_len);
int moonlift_program_cmd_brif(moonlift_program_t*, const char* cond, const char* then_block, const char* const* then_args, size_t then_args_len, const char* else_block, const char* const* else_args, size_t else_args_len);
int moonlift_program_cmd_return_void(moonlift_program_t*);
int moonlift_program_cmd_return_value(moonlift_program_t*, const char* value);
int moonlift_program_cmd_trap(moonlift_program_t*);
int moonlift_program_cmd_finish_func(moonlift_program_t*, const char* func);
int moonlift_program_cmd_finalize_module(moonlift_program_t*);
]]

local M = {}

local SCALAR = {
    BOOL = 1,
    I8 = 2,
    I16 = 3,
    I32 = 4,
    I64 = 5,
    U8 = 6,
    U16 = 7,
    U32 = 8,
    U64 = 9,
    F32 = 10,
    F64 = 11,
    PTR = 12,
    INDEX = 13,
}

local UNARY = {
    INEG = 1,
    FNEG = 2,
    BNOT = 3,
    BOOL_NOT = 4,
}

local BINARY = {
    IADD = 1,
    ISUB = 2,
    IMUL = 3,
    FADD = 4,
    FSUB = 5,
    FMUL = 6,
    SDIV = 7,
    UDIV = 8,
    FDIV = 9,
    SREM = 10,
    UREM = 11,
    FREM = 12,
    BAND = 13,
    BOR = 14,
    BXOR = 15,
    ISHL = 16,
    USHR = 17,
    SSHR = 18,
    ICMPEQ = 19,
    ICMPNE = 20,
    SICMPLT = 21,
    SICMPLE = 22,
    SICMPGT = 23,
    SICMPGE = 24,
    UICMPLT = 25,
    UICMPLE = 26,
    UICMPGT = 27,
    UICMPGE = 28,
    FCMPEQ = 29,
    FCMPNE = 30,
    FCMPLT = 31,
    FCMPLE = 32,
    FCMPGT = 33,
    FCMPGE = 34,
}

local CAST = {
    BITCAST = 1,
    IREDUCE = 2,
    SEXTEND = 3,
    UEXTEND = 4,
    FPROMOTE = 5,
    FDEMOTE = 6,
    STOF = 7,
    UTOF = 8,
    FTOS = 9,
    FTOU = 10,
}

local CALL = {
    DIRECT = 1,
    EXTERN = 2,
    INDIRECT = 3,
}

local function load_library(libpath)
    if libpath ~= nil then
        return ffi.load(libpath)
    end

    local ext
    local prefix = "lib"
    if ffi.os == "OSX" then
        ext = ".dylib"
    elseif ffi.os == "Windows" then
        ext = ".dll"
        prefix = ""
    else
        ext = ".so"
    end

    local candidates = {
        "./moonlift/target/debug/" .. prefix .. "moonlift" .. ext,
        "./moonlift/target/release/" .. prefix .. "moonlift" .. ext,
        prefix .. "moonlift" .. ext,
        "moonlift",
    }

    local last_err = nil
    for i = 1, #candidates do
        local ok, lib = pcall(ffi.load, candidates[i])
        if ok then
            return lib
        end
        last_err = lib
    end
    error("moonlift.jit: could not load Rust moonlift library: " .. tostring(last_err))
end

local function last_error(lib)
    local p = lib.moonlift_last_error_message()
    if p == nil then
        return "unknown moonlift ffi error"
    end
    return ffi.string(p)
end

local function check_ok(lib, rc, context)
    if rc == 0 then
        error(context .. ": " .. last_error(lib))
    end
end

local function check_ptr(lib, ptr, context)
    if ptr == nil or ptr == ffi.NULL then
        error(context .. ": " .. last_error(lib))
    end
    return ptr
end

local function cstring(text)
    return ffi.new("char[?]", #text + 1, text)
end

local function cstring_array(texts)
    local arr = ffi.new("const char *[?]", #texts)
    local keep = {}
    for i = 1, #texts do
        keep[i] = cstring(texts[i])
        arr[i - 1] = keep[i]
    end
    return arr, keep
end

local function u32_array(values)
    local arr = ffi.new("uint32_t[?]", #values)
    for i = 1, #values do
        arr[i - 1] = values[i]
    end
    return arr
end

function M.Define(T, opts)
    local Back = T.MoonliftBack
    local lib = load_library(opts and opts.libpath or nil)

    local scalar_code
    local replay_cmd

    local function one_scalar_code(node)
        return pvm.one(scalar_code(node))
    end

    local function id_text(node)
        return node.text
    end

    local function scalar_codes(nodes)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_scalar_code(nodes[i])
        end
        return out
    end

    local function id_texts(nodes)
        local out = {}
        for i = 1, #nodes do
            out[i] = id_text(nodes[i])
        end
        return out
    end

    scalar_code = pvm.phase("moonlift_ffi_scalar_code", {
        [Back.BackBool] = function() return pvm.once(SCALAR.BOOL) end,
        [Back.BackI8] = function() return pvm.once(SCALAR.I8) end,
        [Back.BackI16] = function() return pvm.once(SCALAR.I16) end,
        [Back.BackI32] = function() return pvm.once(SCALAR.I32) end,
        [Back.BackI64] = function() return pvm.once(SCALAR.I64) end,
        [Back.BackU8] = function() return pvm.once(SCALAR.U8) end,
        [Back.BackU16] = function() return pvm.once(SCALAR.U16) end,
        [Back.BackU32] = function() return pvm.once(SCALAR.U32) end,
        [Back.BackU64] = function() return pvm.once(SCALAR.U64) end,
        [Back.BackF32] = function() return pvm.once(SCALAR.F32) end,
        [Back.BackF64] = function() return pvm.once(SCALAR.F64) end,
        [Back.BackPtr] = function() return pvm.once(SCALAR.PTR) end,
        [Back.BackIndex] = function() return pvm.once(SCALAR.INDEX) end,
        [Back.BackVoid] = function()
            error("moonlift.jit: BackVoid is not a materializable runtime scalar for the direct FFI builder")
        end,
    })

    local function handler_binary(op)
        return function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_binary(
                program,
                op,
                cstring(id_text(self.dst)),
                one_scalar_code(self.ty),
                cstring(id_text(self.lhs)),
                cstring(id_text(self.rhs))
            ), "moonlift ffi binary")
            return pvm.once(true)
        end
    end

    local function handler_cast(op)
        return function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_cast(
                program,
                op,
                cstring(id_text(self.dst)),
                one_scalar_code(self.ty),
                cstring(id_text(self.value))
            ), "moonlift ffi cast")
            return pvm.once(true)
        end
    end

    local replay_handlers = {
        [Back.BackCmdCreateSig] = function(self, program)
            local params = scalar_codes(self.params)
            local results = scalar_codes(self.results)
            check_ok(lib, lib.moonlift_program_cmd_create_sig(
                program,
                cstring(id_text(self.sig)),
                u32_array(params), #params,
                u32_array(results), #results
            ), "moonlift ffi create_sig")
            return pvm.once(true)
        end,
        [Back.BackCmdDeclareData] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_declare_data(program, cstring(id_text(self.data)), self.size, self.align), "moonlift ffi declare_data")
            return pvm.once(true)
        end,
        [Back.BackCmdDataInitZero] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_data_init_zero(program, cstring(id_text(self.data)), self.offset, self.size), "moonlift ffi data_init_zero")
            return pvm.once(true)
        end,
        [Back.BackCmdDataInitInt] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_data_init_int(program, cstring(id_text(self.data)), self.offset, one_scalar_code(self.ty), cstring(self.raw)), "moonlift ffi data_init_int")
            return pvm.once(true)
        end,
        [Back.BackCmdDataInitFloat] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_data_init_float(program, cstring(id_text(self.data)), self.offset, one_scalar_code(self.ty), cstring(self.raw)), "moonlift ffi data_init_float")
            return pvm.once(true)
        end,
        [Back.BackCmdDataInitBool] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_data_init_bool(program, cstring(id_text(self.data)), self.offset, self.value and 1 or 0), "moonlift ffi data_init_bool")
            return pvm.once(true)
        end,
        [Back.BackCmdDeclareFuncLocal] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_declare_func_local(program, cstring(id_text(self.func)), cstring(id_text(self.sig))), "moonlift ffi declare_func_local")
            return pvm.once(true)
        end,
        [Back.BackCmdDeclareFuncExport] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_declare_func_export(program, cstring(id_text(self.func)), cstring(id_text(self.sig))), "moonlift ffi declare_func_export")
            return pvm.once(true)
        end,
        [Back.BackCmdDeclareFuncExtern] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_declare_func_extern(program, cstring(id_text(self.func)), cstring(self.symbol), cstring(id_text(self.sig))), "moonlift ffi declare_func_extern")
            return pvm.once(true)
        end,
        [Back.BackCmdBeginFunc] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_begin_func(program, cstring(id_text(self.func))), "moonlift ffi begin_func")
            return pvm.once(true)
        end,
        [Back.BackCmdCreateBlock] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_create_block(program, cstring(id_text(self.block))), "moonlift ffi create_block")
            return pvm.once(true)
        end,
        [Back.BackCmdSwitchToBlock] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_switch_to_block(program, cstring(id_text(self.block))), "moonlift ffi switch_to_block")
            return pvm.once(true)
        end,
        [Back.BackCmdSealBlock] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_seal_block(program, cstring(id_text(self.block))), "moonlift ffi seal_block")
            return pvm.once(true)
        end,
        [Back.BackCmdBindEntryParams] = function(self, program)
            local args = id_texts(self.values)
            local arr, keep = cstring_array(args)
            check_ok(lib, lib.moonlift_program_cmd_bind_entry_params(program, cstring(id_text(self.block)), arr, #args), "moonlift ffi bind_entry_params")
            return pvm.once(keep ~= nil)
        end,
        [Back.BackCmdAppendBlockParam] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_append_block_param(program, cstring(id_text(self.block)), cstring(id_text(self.value)), one_scalar_code(self.ty)), "moonlift ffi append_block_param")
            return pvm.once(true)
        end,
        [Back.BackCmdCreateStackSlot] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_create_stack_slot(program, cstring(id_text(self.slot)), self.size, self.align), "moonlift ffi create_stack_slot")
            return pvm.once(true)
        end,
        [Back.BackCmdAlias] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_alias(program, cstring(id_text(self.dst)), cstring(id_text(self.src))), "moonlift ffi alias")
            return pvm.once(true)
        end,
        [Back.BackCmdStackAddr] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_stack_addr(program, cstring(id_text(self.dst)), cstring(id_text(self.slot))), "moonlift ffi stack_addr")
            return pvm.once(true)
        end,
        [Back.BackCmdDataAddr] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_data_addr(program, cstring(id_text(self.dst)), cstring(id_text(self.data))), "moonlift ffi data_addr")
            return pvm.once(true)
        end,
        [Back.BackCmdConstInt] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_const_int(program, cstring(id_text(self.dst)), one_scalar_code(self.ty), cstring(self.raw)), "moonlift ffi const_int")
            return pvm.once(true)
        end,
        [Back.BackCmdConstFloat] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_const_float(program, cstring(id_text(self.dst)), one_scalar_code(self.ty), cstring(self.raw)), "moonlift ffi const_float")
            return pvm.once(true)
        end,
        [Back.BackCmdConstBool] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_const_bool(program, cstring(id_text(self.dst)), self.value and 1 or 0), "moonlift ffi const_bool")
            return pvm.once(true)
        end,
        [Back.BackCmdConstNull] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_const_null(program, cstring(id_text(self.dst))), "moonlift ffi const_null")
            return pvm.once(true)
        end,
        [Back.BackCmdIneg] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_unary(program, UNARY.INEG, cstring(id_text(self.dst)), one_scalar_code(self.ty), cstring(id_text(self.value))), "moonlift ffi ineg")
            return pvm.once(true)
        end,
        [Back.BackCmdFneg] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_unary(program, UNARY.FNEG, cstring(id_text(self.dst)), one_scalar_code(self.ty), cstring(id_text(self.value))), "moonlift ffi fneg")
            return pvm.once(true)
        end,
        [Back.BackCmdBnot] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_unary(program, UNARY.BNOT, cstring(id_text(self.dst)), one_scalar_code(self.ty), cstring(id_text(self.value))), "moonlift ffi bnot")
            return pvm.once(true)
        end,
        [Back.BackCmdBoolNot] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_unary(program, UNARY.BOOL_NOT, cstring(id_text(self.dst)), SCALAR.BOOL, cstring(id_text(self.value))), "moonlift ffi bool_not")
            return pvm.once(true)
        end,
        [Back.BackCmdLoad] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_load(program, cstring(id_text(self.dst)), one_scalar_code(self.ty), cstring(id_text(self.addr))), "moonlift ffi load")
            return pvm.once(true)
        end,
        [Back.BackCmdStore] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_store(program, one_scalar_code(self.ty), cstring(id_text(self.addr)), cstring(id_text(self.value))), "moonlift ffi store")
            return pvm.once(true)
        end,
        [Back.BackCmdSelect] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_select(program, cstring(id_text(self.dst)), one_scalar_code(self.ty), cstring(id_text(self.cond)), cstring(id_text(self.then_value)), cstring(id_text(self.else_value))), "moonlift ffi select")
            return pvm.once(true)
        end,
        [Back.BackCmdCallValueDirect] = function(self, program)
            local args = id_texts(self.args)
            local arr, keep = cstring_array(args)
            check_ok(lib, lib.moonlift_program_cmd_call_value(program, CALL.DIRECT, cstring(id_text(self.dst)), one_scalar_code(self.ty), cstring(id_text(self.func)), cstring(id_text(self.sig)), arr, #args), "moonlift ffi call_value_direct")
            return pvm.once(keep ~= nil)
        end,
        [Back.BackCmdCallStmtDirect] = function(self, program)
            local args = id_texts(self.args)
            local arr, keep = cstring_array(args)
            check_ok(lib, lib.moonlift_program_cmd_call_stmt(program, CALL.DIRECT, cstring(id_text(self.func)), cstring(id_text(self.sig)), arr, #args), "moonlift ffi call_stmt_direct")
            return pvm.once(keep ~= nil)
        end,
        [Back.BackCmdCallValueExtern] = function(self, program)
            local args = id_texts(self.args)
            local arr, keep = cstring_array(args)
            check_ok(lib, lib.moonlift_program_cmd_call_value(program, CALL.EXTERN, cstring(id_text(self.dst)), one_scalar_code(self.ty), cstring(id_text(self.func)), cstring(id_text(self.sig)), arr, #args), "moonlift ffi call_value_extern")
            return pvm.once(keep ~= nil)
        end,
        [Back.BackCmdCallStmtExtern] = function(self, program)
            local args = id_texts(self.args)
            local arr, keep = cstring_array(args)
            check_ok(lib, lib.moonlift_program_cmd_call_stmt(program, CALL.EXTERN, cstring(id_text(self.func)), cstring(id_text(self.sig)), arr, #args), "moonlift ffi call_stmt_extern")
            return pvm.once(keep ~= nil)
        end,
        [Back.BackCmdCallValueIndirect] = function(self, program)
            local args = id_texts(self.args)
            local arr, keep = cstring_array(args)
            check_ok(lib, lib.moonlift_program_cmd_call_value(program, CALL.INDIRECT, cstring(id_text(self.dst)), one_scalar_code(self.ty), cstring(id_text(self.callee)), cstring(id_text(self.sig)), arr, #args), "moonlift ffi call_value_indirect")
            return pvm.once(keep ~= nil)
        end,
        [Back.BackCmdCallStmtIndirect] = function(self, program)
            local args = id_texts(self.args)
            local arr, keep = cstring_array(args)
            check_ok(lib, lib.moonlift_program_cmd_call_stmt(program, CALL.INDIRECT, cstring(id_text(self.callee)), cstring(id_text(self.sig)), arr, #args), "moonlift ffi call_stmt_indirect")
            return pvm.once(keep ~= nil)
        end,
        [Back.BackCmdJump] = function(self, program)
            local args = id_texts(self.args)
            local arr, keep = cstring_array(args)
            check_ok(lib, lib.moonlift_program_cmd_jump(program, cstring(id_text(self.dest)), arr, #args), "moonlift ffi jump")
            return pvm.once(keep ~= nil)
        end,
        [Back.BackCmdBrIf] = function(self, program)
            local then_args = id_texts(self.then_args)
            local else_args = id_texts(self.else_args)
            local then_arr, keep_then = cstring_array(then_args)
            local else_arr, keep_else = cstring_array(else_args)
            check_ok(lib, lib.moonlift_program_cmd_brif(program, cstring(id_text(self.cond)), cstring(id_text(self.then_block)), then_arr, #then_args, cstring(id_text(self.else_block)), else_arr, #else_args), "moonlift ffi brif")
            return pvm.once(keep_then ~= nil or keep_else ~= nil)
        end,
        [Back.BackCmdReturnVoid] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_return_void(program), "moonlift ffi return_void")
            return pvm.once(true)
        end,
        [Back.BackCmdReturnValue] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_return_value(program, cstring(id_text(self.value))), "moonlift ffi return_value")
            return pvm.once(true)
        end,
        [Back.BackCmdTrap] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_trap(program), "moonlift ffi trap")
            return pvm.once(true)
        end,
        [Back.BackCmdFinishFunc] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_finish_func(program, cstring(id_text(self.func))), "moonlift ffi finish_func")
            return pvm.once(true)
        end,
        [Back.BackCmdFinalizeModule] = function(self, program)
            check_ok(lib, lib.moonlift_program_cmd_finalize_module(program), "moonlift ffi finalize_module")
            return pvm.once(true)
        end,
    }

    local binary_codes = {
        [Back.BackCmdIadd] = BINARY.IADD,
        [Back.BackCmdIsub] = BINARY.ISUB,
        [Back.BackCmdImul] = BINARY.IMUL,
        [Back.BackCmdFadd] = BINARY.FADD,
        [Back.BackCmdFsub] = BINARY.FSUB,
        [Back.BackCmdFmul] = BINARY.FMUL,
        [Back.BackCmdSdiv] = BINARY.SDIV,
        [Back.BackCmdUdiv] = BINARY.UDIV,
        [Back.BackCmdFdiv] = BINARY.FDIV,
        [Back.BackCmdSrem] = BINARY.SREM,
        [Back.BackCmdUrem] = BINARY.UREM,
        [Back.BackCmdFrem] = BINARY.FREM,
        [Back.BackCmdBand] = BINARY.BAND,
        [Back.BackCmdBor] = BINARY.BOR,
        [Back.BackCmdBxor] = BINARY.BXOR,
        [Back.BackCmdIshl] = BINARY.ISHL,
        [Back.BackCmdUshr] = BINARY.USHR,
        [Back.BackCmdSshr] = BINARY.SSHR,
        [Back.BackCmdIcmpEq] = BINARY.ICMPEQ,
        [Back.BackCmdIcmpNe] = BINARY.ICMPNE,
        [Back.BackCmdSIcmpLt] = BINARY.SICMPLT,
        [Back.BackCmdSIcmpLe] = BINARY.SICMPLE,
        [Back.BackCmdSIcmpGt] = BINARY.SICMPGT,
        [Back.BackCmdSIcmpGe] = BINARY.SICMPGE,
        [Back.BackCmdUIcmpLt] = BINARY.UICMPLT,
        [Back.BackCmdUIcmpLe] = BINARY.UICMPLE,
        [Back.BackCmdUIcmpGt] = BINARY.UICMPGT,
        [Back.BackCmdUIcmpGe] = BINARY.UICMPGE,
        [Back.BackCmdFCmpEq] = BINARY.FCMPEQ,
        [Back.BackCmdFCmpNe] = BINARY.FCMPNE,
        [Back.BackCmdFCmpLt] = BINARY.FCMPLT,
        [Back.BackCmdFCmpLe] = BINARY.FCMPLE,
        [Back.BackCmdFCmpGt] = BINARY.FCMPGT,
        [Back.BackCmdFCmpGe] = BINARY.FCMPGE,
    }

    for mt, op in pairs(binary_codes) do
        replay_handlers[mt] = handler_binary(op)
    end

    local cast_codes = {
        [Back.BackCmdBitcast] = CAST.BITCAST,
        [Back.BackCmdIreduce] = CAST.IREDUCE,
        [Back.BackCmdSextend] = CAST.SEXTEND,
        [Back.BackCmdUextend] = CAST.UEXTEND,
        [Back.BackCmdFpromote] = CAST.FPROMOTE,
        [Back.BackCmdFdemote] = CAST.FDEMOTE,
        [Back.BackCmdSToF] = CAST.STOF,
        [Back.BackCmdUToF] = CAST.UTOF,
        [Back.BackCmdFToS] = CAST.FTOS,
        [Back.BackCmdFToU] = CAST.FTOU,
    }

    for mt, op in pairs(cast_codes) do
        replay_handlers[mt] = handler_cast(op)
    end

    replay_cmd = pvm.phase("moonlift_ffi_replay_cmd", replay_handlers)

    local Artifact = {}
    Artifact.__index = Artifact

    function Artifact:getpointer(func)
        local text = type(func) == "string" and func or id_text(func)
        return check_ptr(lib, lib.moonlift_artifact_getpointer(self._raw, cstring(text)), "moonlift ffi artifact:getpointer")
    end

    function Artifact:free()
        if self._raw ~= nil and self._raw ~= ffi.NULL then
            lib.moonlift_artifact_free(self._raw)
            self._raw = ffi.NULL
        end
    end

    local Jit = {}
    Jit.__index = Jit

    function Jit:symbol(name, ptr)
        check_ok(lib, lib.moonlift_jit_symbol(self._raw, cstring(name), ffi.cast("const void*", ptr)), "moonlift ffi jit:symbol")
    end

    function Jit:compile(program)
        local raw_program = check_ptr(lib, lib.moonlift_program_new(), "moonlift ffi program_new")
        local ok, err = pcall(function()
            for i = 1, #program.cmds do
                pvm.one(replay_cmd(program.cmds[i], raw_program))
            end
        end)
        if not ok then
            lib.moonlift_program_free(raw_program)
            error(err)
        end
        local raw_artifact = check_ptr(lib, lib.moonlift_jit_compile(self._raw, raw_program), "moonlift ffi jit:compile")
        lib.moonlift_program_free(raw_program)
        return setmetatable({ _raw = raw_artifact }, Artifact)
    end

    function Jit:free()
        if self._raw ~= nil and self._raw ~= ffi.NULL then
            lib.moonlift_jit_free(self._raw)
            self._raw = ffi.NULL
        end
    end

    return {
        lib = lib,
        jit = function()
            local raw = check_ptr(lib, lib.moonlift_jit_new(), "moonlift ffi jit_new")
            return setmetatable({ _raw = raw }, Jit)
        end,
    }
end

return M
