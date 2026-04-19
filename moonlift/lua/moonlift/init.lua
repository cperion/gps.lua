local backend = assert(rawget(_G, "__moonlift_backend"), "moonlift backend not installed")

local M
local ExprMT = {}
local TypeMT = {}
local PtrTypeMT = {}
local FunctionMT = {}
local ExternMT = {}
local ModuleMT = {}
local CompiledFnMT = {}
local FuncStage1MT = {}
local ExternStage1MT = {}
local LetMT = {}
local VarMT = {}
local QuoteMT = {}

local compiled_cache = setmetatable({}, { __mode = "v" })
local body_env_cache = setmetatable({}, { __mode = "k" })

local current_builder = nil
local param
local if_
local cast
local trunc
local zext
local sext
local bitcast
local switch_
local break_
local continue_
local invoke
local extern
local emit_stmt
local compile_function

local unpack = table.unpack or unpack

local function pack(...)
    return { n = select("#", ...), ... }
end

local function unpack_from(t, i)
    return unpack(t, i or 1, t.n)
end

local function is_expr(x)
    return type(x) == "table" and getmetatable(x) == ExprMT
end

local function lower_type_name(t)
    return (t and t.lowering_name) or (t and t.name)
end

local function is_type(x)
    if type(x) ~= "table" then
        return false
    end
    local mt = getmetatable(x)
    return mt == TypeMT or mt == PtrTypeMT
end

local function is_function(x)
    return type(x) == "table" and getmetatable(x) == FunctionMT
end

local function current_frame()
    local builder = current_builder
    if builder == nil or builder.frame == nil then
        return nil
    end
    return builder.frame
end

local expr_methods = {}

local function expr(node, t, methods)
    if node.type == nil then
        node.type = lower_type_name(t)
    end
    return setmetatable({ node = node, t = t, __methods = methods }, ExprMT)
end

local function is_numeric_type(t)
    return is_type(t) and (t.family == "int" or t.family == "float" or t.family == "enum")
end

local function is_integer_type(t)
    return is_type(t) and (t.family == "int" or t.family == "ptr" or t.family == "enum")
end

local function is_float_type(t)
    return is_type(t) and t.family == "float"
end

local function is_void_type(t)
    return is_type(t) and t.family == "void"
end

local function is_bool_type(t)
    return is_type(t) and t.family == "bool"
end

local function as_expr(x, want_t)
    if is_expr(x) then
        if want_t ~= nil and x.t ~= want_t then
            error(("moonlift type mismatch: expected %s, got %s"):format(want_t.name, x.t.name), 3)
        end
        return x
    end
    if type(x) == "number" then
        local t = want_t or M.i32
        assert(not is_bool_type(t), "cannot coerce Lua number to Moonlift bool without an explicit boolean")
        return t(x)
    end
    if type(x) == "boolean" then
        local t = want_t or M.bool
        assert(is_bool_type(t), "cannot coerce Lua boolean to non-bool Moonlift type")
        return t(x)
    end
    error("cannot convert value to moonlift expression: " .. type(x), 3)
end

local function wrap_frame_block(frame, result_expr)
    if #frame.stmts == 0 then
        return result_expr
    end
    return expr({
        tag = "block",
        stmts = frame.stmts,
        result = result_expr.node,
    }, result_expr.t)
end

local function body_env(base_env)
    local cached = body_env_cache[base_env]
    if cached ~= nil then
        return cached
    end
    local env = setmetatable({}, {
        __index = function(_, k)
            if M ~= nil then
                if M[k] ~= nil then
                    return M[k]
                end
                if M.types ~= nil and M.types[k] ~= nil then
                    return M.types[k]
                end
            end
            return base_env[k]
        end,
        __newindex = base_env,
    })
    body_env_cache[base_env] = env
    return env
end

local function run_builder_fn(f, ...)
    if type(getfenv) == "function" and type(setfenv) == "function" then
        local old_env = getfenv(f)
        local new_env = body_env(old_env)
        local applied = false
        if old_env ~= new_env then
            setfenv(f, new_env)
            applied = true
        end
        local out = pack(pcall(f, ...))
        if applied then
            setfenv(f, old_env)
        end
        if not out[1] then
            error(out[2], 0)
        end
        return unpack_from(out, 2)
    end
    return f(...)
end

local function with_builder(builder, f)
    local prev = current_builder
    current_builder = builder
    local out = pack(pcall(f))
    current_builder = prev
    if not out[1] then
        error(out[2], 0)
    end
    return unpack_from(out, 2)
end

local function with_frame_result(f)
    local builder = current_builder
    if builder == nil then
        error("moonlift block context is not active", 2)
    end
    local prev = builder.frame
    local frame = { stmts = {}, parent = prev }
    builder.frame = frame
    local out = pack(pcall(run_builder_fn, f))
    builder.frame = prev
    if not out[1] then
        error(out[2], 0)
    end
    return wrap_frame_block(frame, as_expr(out[2]))
end

local function capture_stmt_block(f)
    local builder = current_builder
    if builder == nil then
        error("moonlift statement context is not active", 2)
    end
    local prev = builder.frame
    local frame = { stmts = {}, parent = prev }
    builder.frame = frame
    local out = pack(pcall(run_builder_fn, f))
    builder.frame = prev
    if not out[1] then
        error(out[2], 0)
    end
    if out.n >= 2 and out[2] ~= nil then
        error("moonlift while_ body must not return a value", 2)
    end
    return frame.stmts
end

local function common_type(a, b)
    if is_expr(a) and is_expr(b) then
        assert(a.t == b.t, ("moonlift operand type mismatch: %s vs %s"):format(a.t.name, b.t.name))
        return a.t
    elseif is_expr(a) then
        return a.t
    elseif is_expr(b) then
        return b.t
    end
    return M.i32
end

local function binary(tag, a, b)
    local t = common_type(a, b)
    a = as_expr(a, t)
    b = as_expr(b, t)
    if tag == "rem" then
        assert(is_integer_type(t), "moonlift remainder expects integer operands")
    elseif t.family == "ptr" then
        assert(tag == "add" or tag == "sub", ("moonlift %s is not valid for pointer operands"):format(tag))
    else
        assert(is_numeric_type(t), ("moonlift %s expects numeric operands"):format(tag))
    end
    return expr({ tag = tag, lhs = a.node, rhs = b.node, type = lower_type_name(t) }, t)
end

local function integer_binary(tag, a, b)
    local t = common_type(a, b)
    a = as_expr(a, t)
    b = as_expr(b, t)
    assert(is_integer_type(t), ("moonlift %s expects integer or pointer operands"):format(tag))
    return expr({ tag = tag, lhs = a.node, rhs = b.node, type = lower_type_name(t) }, t)
end

local function cast_like(tag, to_t, value)
    assert(is_type(to_t), ("moonlift %s target must be a Moonlift type"):format(tag))
    value = as_expr(value)
    return expr({ tag = tag, value = value.node, type = lower_type_name(to_t) }, to_t)
end

local function compare(tag, a, b)
    local t = common_type(a, b)
    a = as_expr(a, t)
    b = as_expr(b, t)
    if tag == "eq" or tag == "ne" then
        assert(is_numeric_type(t) or is_bool_type(t) or t.family == "ptr", ("moonlift %s expects scalar operands"):format(tag))
    else
        assert(is_numeric_type(t) or t.family == "ptr", ("moonlift %s expects numeric operands"):format(tag))
    end
    return expr({ tag = tag, lhs = a.node, rhs = b.node }, M.bool)
end

local function bool_unary(tag, x)
    x = as_expr(x, M.bool)
    return expr({ tag = tag, value = x.node }, M.bool)
end

local function bool_binary(tag, a, b)
    a = as_expr(a, M.bool)
    b = as_expr(b, M.bool)
    return expr({ tag = tag, lhs = a.node, rhs = b.node }, M.bool)
end

ExprMT.__tostring = function(self)
    return string.format("moonlift.expr<%s:%s>", self.t and self.t.name or "?", self.node.tag or "?")
end

ExprMT.__add = function(a, b)
    return binary("add", a, b)
end

ExprMT.__sub = function(a, b)
    return binary("sub", a, b)
end

ExprMT.__mul = function(a, b)
    return binary("mul", a, b)
end

ExprMT.__div = function(a, b)
    return binary("div", a, b)
end

ExprMT.__mod = function(a, b)
    return binary("rem", a, b)
end

ExprMT.__unm = function(a)
    a = as_expr(a)
    assert(is_numeric_type(a.t), "moonlift unary minus expects numeric operand")
    return expr({ tag = "neg", value = a.node }, a.t)
end

ExprMT.__call = function(self, then_value, else_value)
    if is_bool_type(self.t) then
        return if_(self, then_value, else_value)
    end
    error("only Moonlift bool expressions are callable as conditional selectors", 2)
end

ExprMT.__index = function(self, key)
    local methods = rawget(self, "__methods")
    if methods ~= nil and methods[key] ~= nil then
        return methods[key]
    end
    return expr_methods[key]
end

expr_methods.eq = function(self, rhs)
    return compare("eq", self, rhs)
end
expr_methods.ne = function(self, rhs)
    return compare("ne", self, rhs)
end
expr_methods.lt = function(self, rhs)
    return compare("lt", self, rhs)
end
expr_methods.le = function(self, rhs)
    return compare("le", self, rhs)
end
expr_methods.gt = function(self, rhs)
    return compare("gt", self, rhs)
end
expr_methods.ge = function(self, rhs)
    return compare("ge", self, rhs)
end
expr_methods.not_ = function(self)
    return bool_unary("not", self)
end
expr_methods.and_ = function(self, rhs)
    return bool_binary("and", self, rhs)
end
expr_methods.or_ = function(self, rhs)
    return bool_binary("or", self, rhs)
end
expr_methods.band = function(self, rhs)
    return integer_binary("band", self, rhs)
end
expr_methods.bor = function(self, rhs)
    return integer_binary("bor", self, rhs)
end
expr_methods.bxor = function(self, rhs)
    return integer_binary("bxor", self, rhs)
end
expr_methods.bnot = function(self)
    self = as_expr(self)
    assert(is_integer_type(self.t), "moonlift bnot expects integer or pointer operand")
    return expr({ tag = "bnot", value = self.node, type = lower_type_name(self.t) }, self.t)
end
expr_methods.shl = function(self, rhs)
    return integer_binary("shl", self, rhs)
end
expr_methods.shr_u = function(self, rhs)
    return integer_binary("shr_u", self, rhs)
end
expr_methods.shr_s = function(self, rhs)
    return integer_binary("shr_s", self, rhs)
end
expr_methods.cast = function(self, to_t)
    return cast(to_t, self)
end
expr_methods.trunc = function(self, to_t)
    return trunc(to_t, self)
end
expr_methods.zext = function(self, to_t)
    return zext(to_t, self)
end
expr_methods.sext = function(self, to_t)
    return sext(to_t, self)
end
expr_methods.bitcast = function(self, to_t)
    return bitcast(to_t, self)
end
expr_methods.select = function(self, then_value, else_value)
    return if_(self, then_value, else_value)
end
expr_methods.set = function()
    error("moonlift.set is only valid on mutable variables", 2)
end

local function new_type(spec)
    return setmetatable(spec, TypeMT)
end

TypeMT.__tostring = function(self)
    return string.format("moonlift.type<%s>", self.name)
end

TypeMT.__call = function(self, value)
    if is_void_type(self) then
        error("void may only be used as a function result type", 2)
    end
    if type(value) == "string" then
        return param(value, self)
    end
    if type(value) == "number" then
        return expr({ tag = self.const_tag, value = value }, self)
    end
    if type(value) == "boolean" and is_bool_type(self) then
        return expr({ tag = self.const_tag, value = value }, self)
    end
    error(("%s(...) expects a constant literal or parameter name"):format(self.name), 2)
end

cast = function(to_t, value)
    return cast_like("cast", to_t, value)
end

trunc = function(to_t, value)
    return cast_like("trunc", to_t, value)
end

zext = function(to_t, value)
    return cast_like("zext", to_t, value)
end

sext = function(to_t, value)
    return cast_like("sext", to_t, value)
end

bitcast = function(to_t, value)
    return cast_like("bitcast", to_t, value)
end

param = function(name, t)
    assert(type(name) == "string", "moonlift.param name must be a string")
    assert(is_type(t), "moonlift.param requires a Moonlift type")
    return { name = name, t = t }
end

local function arg(index, t)
    assert(type(index) == "number", "moonlift.arg index must be a number")
    assert(is_type(t), "moonlift.arg requires a Moonlift type")
    return expr({ tag = "arg", index = index }, t)
end

local function lower_param(p)
    return lower_type_name(p.t)
end

local function block(body)
    assert(type(body) == "function", "moonlift.block expects a function")
    return with_frame_result(body)
end

if_ = function(cond, then_value, else_value)
    cond = as_expr(cond, M.bool)
    if type(then_value) == "function" then
        then_value = block(then_value)
    end
    if type(else_value) == "function" then
        else_value = block(else_value)
    end
    then_value = as_expr(then_value)
    else_value = as_expr(else_value)
    assert(then_value.t == else_value.t, "moonlift.if_ branches must have the same type")
    return expr({
        tag = "if",
        cond = cond.node,
        then_ = then_value.node,
        else_ = else_value.node,
    }, then_value.t)
end

local function fresh_local_name(prefix)
    local builder = current_builder
    local frame = current_frame()
    if builder == nil or frame == nil then
        error("moonlift local binding may only be used inside moonlift.fn bodies or moonlift.block", 2)
    end
    builder.next_local_id = builder.next_local_id + 1
    return string.format("%s$%d", prefix, builder.next_local_id), frame
end

local function make_var_methods(lowered_name, t)
    return {
        set = function(self, value)
            local frame = current_frame()
            if frame == nil then
                error("moonlift variable assignment may only be used inside moonlift blocks", 2)
            end
            value = as_expr(value, t)
            frame.stmts[#frame.stmts + 1] = {
                tag = "set",
                name = lowered_name,
                value = value.node,
            }
            return self
        end,
    }
end

local function bind_let(init)
    init = as_expr(init)
    local lowered_name, frame = fresh_local_name("let")
    local local_ref = expr({ tag = "local", name = lowered_name }, init.t)
    frame.stmts[#frame.stmts + 1] = {
        tag = "let",
        name = lowered_name,
        type = lower_type_name(init.t),
        init = init.node,
    }
    return local_ref
end

local function bind_var(init)
    init = as_expr(init)
    local lowered_name, frame = fresh_local_name("var")
    local var_ref = expr({ tag = "local", name = lowered_name }, init.t, make_var_methods(lowered_name, init.t))
    frame.stmts[#frame.stmts + 1] = {
        tag = "var",
        name = lowered_name,
        type = lower_type_name(init.t),
        init = init.node,
    }
    return var_ref
end

local function while_(cond, body)
    local frame = current_frame()
    if frame == nil then
        error("moonlift.while_ may only be used inside moonlift blocks", 2)
    end
    cond = as_expr(cond, M.bool)
    assert(type(body) == "function", "moonlift.while_ body must be a function")
    frame.stmts[#frame.stmts + 1] = {
        tag = "while",
        cond = cond.node,
        body = capture_stmt_block(body),
    }
    return nil
end

break_ = function()
    return emit_stmt({ tag = "break" })
end

continue_ = function()
    return emit_stmt({ tag = "continue" })
end

switch_ = function(value, cases, default_case)
    value = as_expr(value)
    assert(type(cases) == "table", "moonlift.switch_ expects a case table")
    local default = default_case or cases.default
    assert(default ~= nil, "moonlift.switch_ requires a default case")
    local entries = {}
    for k, v in pairs(cases) do
        if k ~= "default" then
            entries[#entries + 1] = { key = k, value = v }
        end
    end
    local out = default
    for i = #entries, 1, -1 do
        local entry = entries[i]
        local key_expr = is_expr(entry.key) and entry.key or as_expr(entry.key, value.t)
        local branch = entry.value
        out = if_(value:eq(key_expr), branch, out)
    end
    return out
end

emit_stmt = function(stmt)
    local frame = current_frame()
    if frame == nil then
        error("moonlift statement context is not active", 2)
    end
    frame.stmts[#frame.stmts + 1] = stmt
    return nil
end

local function quote(body)
    assert(type(body) == "function", "moonlift.quote expects a function")
    return setmetatable({ body = body }, QuoteMT)
end

QuoteMT.__tostring = function()
    return "moonlift.quote"
end

QuoteMT.__call = function(self, ...)
    local builder = current_builder
    if builder == nil then
        error("moonlift quote expansion may only happen inside Moonlift function bodies", 2)
    end
    local args = pack(...)
    return block(function()
        return run_builder_fn(self.body, unpack_from(args, 1))
    end)
end

LetMT.__call = function(_, init)
    return bind_let(init)
end

VarMT.__call = function(_, init)
    return bind_var(init)
end

local function build_function(name, params, result_t, body_fn)
    assert(type(name) == "string", "moonlift function name must be a string")
    assert(type(params) == "table", "moonlift function params must be a table")
    assert(type(body_fn) == "function", "moonlift function body must be a function")
    assert(result_t == nil or is_type(result_t), "moonlift function result must be a Moonlift type")

    local builder = {
        next_local_id = 0,
        frame = nil,
    }

    local args = {}
    local lowered_params = {}
    for i = 1, #params do
        local p = params[i]
        assert(type(p) == "table" and p.name and p.t, "moonlift function params must come from moonlift.param or type(name)")
        args[i] = arg(i, p.t)
        lowered_params[i] = lower_param(p)
    end

    local body_expr
    if result_t ~= nil and is_void_type(result_t) then
        body_expr = with_builder(builder, function()
            local stmts = capture_stmt_block(function()
                local out = run_builder_fn(body_fn, unpack(args, 1, #args))
                if out ~= nil then
                    error("moonlift void function body must not return a value", 2)
                end
            end)
            return expr({
                tag = "block",
                stmts = stmts,
                result = { tag = "u8", value = 0, type = "u8" },
                type = "u8",
            }, M.u8)
        end)
    else
        body_expr = with_builder(builder, function()
            return block(function()
                return run_builder_fn(body_fn, unpack(args, 1, #args))
            end)
        end)
    end

    local inferred_result = result_t or body_expr.t
    assert(is_type(inferred_result), "moonlift function body did not produce a typed result")
    if not is_void_type(inferred_result) then
        assert(body_expr.t == inferred_result, "moonlift function body result type does not match declared result")
    end

    local lowered = {
        name = name,
        params = lowered_params,
        result = lower_type_name(inferred_result),
        body = body_expr.node,
    }

    return setmetatable({
        name = name,
        params = params,
        result = inferred_result,
        arity = #params,
        body = body_expr,
        lowered = lowered,
    }, FunctionMT)
end

local function parse_function_spec(name, spec)
    assert(type(spec) == "table", "moonlift function spec must be a table")
    local params = spec.params
    local body = spec.body
    local result_t = spec.result or spec.ret

    if params == nil then
        params = {}
        local n = #spec
        if body == nil and n > 0 and type(spec[n]) == "function" then
            body = spec[n]
            n = n - 1
        end
        if result_t == nil and n > 0 and is_type(spec[n]) then
            result_t = spec[n]
            n = n - 1
        end
        for i = 1, n do
            params[i] = spec[i]
        end
    end

    if body == nil and type(spec[#spec]) == "function" then
        body = spec[#spec]
    end

    return build_function(name, params, result_t, assert(body, "moonlift function spec.body must be present"))
end

local function func(name)
    assert(type(name) == "string", "moonlift.func name must be a string")
    return setmetatable({ name = name }, FuncStage1MT)
end

local function parse_extern_spec(name, spec)
    assert(type(spec) == "table", "moonlift extern spec must be a table")
    local params = spec.params
    local result_t = spec.result or spec.ret
    local addr = spec.addr
    if params == nil then
        params = {}
        local n = #spec
        if result_t == nil and n > 0 and is_type(spec[n]) then
            result_t = spec[n]
            n = n - 1
        end
        for i = 1, n do
            params[i] = spec[i]
        end
    end
    result_t = result_t or M.void
    local lowered_params = {}
    for i = 1, #params do
        local p = params[i]
        assert(type(p) == "table" and p.name and p.t, "moonlift extern params must come from moonlift.param or type(name)")
        lowered_params[i] = lower_param(p)
    end
    assert(type(addr) == "number", "moonlift extern requires numeric addr field")
    return setmetatable({
        name = name,
        params = params,
        result = result_t,
        arity = #params,
        addr = addr,
        lowered = {
            name = name,
            params = lowered_params,
            result = lower_type_name(result_t),
            addr = addr,
        },
    }, ExternMT)
end

local function extern(name)
    assert(type(name) == "string", "moonlift.extern name must be a string")
    return setmetatable({ name = name }, ExternStage1MT)
end

FuncStage1MT.__call = function(self, spec)
    return parse_function_spec(self.name, spec)
end

ExternStage1MT.__call = function(self, spec)
    return parse_extern_spec(self.name, spec)
end

invoke = function(callee, ...)
    local argc = select("#", ...)
    local args = { n = argc, ... }
    local builder = current_builder
    if builder == nil then
        error("moonlift.invoke may only be used inside Moonlift function bodies", 2)
    end

    local target
    local result_t
    local param_count
    if is_function(callee) then
        local compiled = callee.__compiled
        if compiled == nil then
            compiled = compile_function(callee)
            callee.__compiled = compiled
            callee.__code_addr = backend.addr(compiled.handle)
        end
        target = {
            kind = "indirect",
            addr = { tag = "ptr", value = callee.__code_addr, type = "ptr" },
            params = callee.lowered.params,
            result = lower_type_name(callee.result),
        }
        result_t = callee.result
        param_count = #callee.params
    elseif type(callee) == "table" and getmetatable(callee) == ExternMT then
        target = {
            kind = "indirect",
            addr = { tag = "ptr", value = callee.addr, type = "ptr" },
            params = callee.lowered.params,
            result = lower_type_name(callee.result),
        }
        result_t = callee.result
        param_count = #callee.params
    else
        error("moonlift.invoke expects a Moonlift function or extern", 2)
    end

    assert(argc == param_count, ("moonlift.invoke expected %d args, got %d"):format(param_count, argc))
    local lowered_args = {}
    if is_function(callee) then
        for i = 1, argc do
            lowered_args[i] = as_expr(args[i], callee.params[i].t).node
        end
    else
        for i = 1, argc do
            lowered_args[i] = as_expr(args[i], callee.params[i].t).node
        end
    end

    local node = {
        tag = "call",
        callee_kind = target.kind,
        name = target.name,
        addr = target.addr,
        params = target.params,
        result = target.result,
        args = lowered_args,
        type = lower_type_name(result_t),
    }
    if is_void_type(result_t) then
        emit_stmt(node)
        return nil
    end
    return expr(node, result_t)
end

local function module(list)
    if type(list) == "table" and list.funcs ~= nil then
        list = list.funcs
    end
    assert(type(list) == "table", "moonlift.module expects a table of functions")
    local out = {}
    for i = 1, #list do
        local f = list[i]
        assert(is_function(f), "moonlift.module entries must be Moonlift functions")
        out[i] = f
    end
    return setmetatable({ funcs = out }, ModuleMT)
end

CompiledFnMT.__index = {
    call = function(self, ...)
        return self(...)
    end,
}

CompiledFnMT.__tostring = function(self)
    return string.format("moonlift.compiled<%s/%d>#%d", self.name, self.arity, self.handle)
end

CompiledFnMT.__call = function(self, ...)
    local argc = select("#", ...)
    if argc ~= self.arity then
        error(("compiled function '%s' expects %d arguments, got %d"):format(self.name, self.arity, argc), 2)
    end
    return backend.call(self.handle, ...)
end

local function wrap_compiled_handle(name, arity, handle)
    local key = tostring(handle) .. ":" .. tostring(arity)
    local cached = compiled_cache[key]
    if cached ~= nil then
        return cached
    end
    local wrapped = setmetatable({
        name = name or "<anon>",
        arity = arity,
        handle = handle,
    }, CompiledFnMT)
    compiled_cache[key] = wrapped
    return wrapped
end

compile_function = function(f)
    local handle = backend.compile(f.lowered)
    assert(type(handle) == "number" and handle > 0, ("moonlift failed to compile function '%s'"):format(f.name))
    return wrap_compiled_handle(f.name, #f.params, handle)
end

local function compile_module(mod)
    local compiled = {}
    for i = 1, #mod.funcs do
        local f = mod.funcs[i]
        local cf = compile_function(f)
        compiled[i] = cf
        compiled[f.name] = cf
    end
    return compiled
end

FunctionMT.__tostring = function(self)
    return string.format("moonlift.func<%s/%d>", self.name, #self.params)
end

FunctionMT.__call = function(self, ...)
    if current_builder ~= nil then
        return invoke(self, ...)
    end
    local argc = select("#", ...)
    if argc ~= 0 then
        error(("moonlift function '%s' compile call expects 0 args outside builder, got %d"):format(self.name, argc), 2)
    end
    return compile_function(self)
end

ExternMT.__tostring = function(self)
    return string.format("moonlift.extern<%s/%d>", self.name, #self.params)
end

ExternMT.__call = function(self, ...)
    return invoke(self, ...)
end

ModuleMT.__tostring = function(self)
    return string.format("moonlift.module<%d functions>", #self.funcs)
end

ModuleMT.__call = function(self)
    return compile_module(self)
end

local function alias_lookup(base_env, k)
    if k == "ml" then
        return M
    elseif M ~= nil and M[k] ~= nil then
        return M[k]
    elseif M ~= nil and M.types ~= nil and M.types[k] ~= nil then
        return M.types[k]
    end
    return base_env[k]
end

local function env(base_env)
    if base_env == nil then
        if type(getfenv) == "function" then
            base_env = getfenv(2)
        else
            base_env = _G
        end
    end
    assert(type(base_env) == "table", "moonlift.env expects an environment table")
    return setmetatable({}, {
        __index = function(_, k)
            return alias_lookup(base_env, k)
        end,
        __newindex = base_env,
    })
end

local function use(base_env)
    if base_env == nil then
        if type(getfenv) == "function" then
            base_env = getfenv(2)
        else
            base_env = _G
        end
    end
    assert(type(base_env) == "table", "moonlift.use expects an environment table")
    local keys = {
        "ml",
        "func",
        "module",
        "extern",
        "invoke",
        "compile",
        "call",
        "stats",
        "load",
        "store",
        "copy",
        "memcpy",
        "memmove",
        "memset",
        "memcmp",
        "let",
        "var",
        "block",
        "if_",
        "switch_",
        "while_",
        "break_",
        "continue_",
        "quote",
        "cast",
        "trunc",
        "zext",
        "sext",
        "bitcast",
        "void",
        "bool",
        "ptr",
        "struct_",
        "union",
        "tagged_union",
        "array",
        "slice",
        "enum",
        "i8",
        "i16",
        "i32",
        "i64",
        "u8",
        "u16",
        "u32",
        "u64",
        "byte",
        "isize",
        "usize",
        "f32",
        "f64",
    }
    for i = 1, #keys do
        local k = keys[i]
        base_env[k] = alias_lookup(base_env, k)
    end
    return base_env
end

local function compile(x)
    if is_function(x) then
        return compile_function(x)
    end
    if type(x) == "table" and getmetatable(x) == ModuleMT then
        return compile_module(x)
    end
    if type(x) == "table" then
        local params = x.params or {}
        local handle = backend.compile(x)
        assert(type(handle) == "number" and handle > 0, "moonlift failed to compile lowered table")
        return wrap_compiled_handle(x.name, #params, handle)
    end
    error("moonlift.compile expects a Moonlift function, module, or lowered table", 2)
end

local types = {
    void = new_type { name = "void", family = "void" },
    bool = new_type { name = "bool", const_tag = "bool", family = "bool" },
    i8 = new_type { name = "i8", const_tag = "i8", family = "int", signed = true, bits = 8 },
    i16 = new_type { name = "i16", const_tag = "i16", family = "int", signed = true, bits = 16 },
    i32 = new_type { name = "i32", const_tag = "i32", family = "int", signed = true, bits = 32 },
    i64 = new_type { name = "i64", const_tag = "i64", family = "int", signed = true, bits = 64 },
    u8 = new_type { name = "u8", const_tag = "u8", family = "int", signed = false, bits = 8 },
    u16 = new_type { name = "u16", const_tag = "u16", family = "int", signed = false, bits = 16 },
    u32 = new_type { name = "u32", const_tag = "u32", family = "int", signed = false, bits = 32 },
    u64 = new_type { name = "u64", const_tag = "u64", family = "int", signed = false, bits = 64 },
    f32 = new_type { name = "f32", const_tag = "f32", family = "float", bits = 32 },
    f64 = new_type { name = "f64", const_tag = "f64", family = "float", bits = 64 },
}
types.byte = types.u8
types.isize = types.i64
types.usize = types.u64

local StructMT = {}
local ArrayTypeMT = {}
local UnionMT = {}
local slice_cache = {}
local make_enum

local function align_up(n, a)
    if a == nil or a <= 1 then return n end
    local r = n % a
    if r == 0 then return n end
    return n + (a - r)
end

local function type_size(t)
    if t.size then return t.size end
    if t.bits then return math.ceil(t.bits / 8) end
    if t.family == "bool" then return 1 end
    error("moonlift type has no known size: " .. tostring(t.name), 2)
end

local function type_align(t)
    return t.align or type_size(t)
end

local function make_struct(name, fields)
    assert(type(name) == "string", "moonlift.struct name must be a string")
    assert(type(fields) == "table", "moonlift.struct fields must be a table")

    local ordered = {}
    local lookup = {}
    local offset = 0
    local max_align = 1

    for i = 1, #fields do
        local field = fields[i]
        local field_name = assert(field[1], "struct field missing name")
        local field_type = assert(field[2], "struct field missing type")
        assert(type(field_name) == "string", "struct field name must be a string")
        assert(lookup[field_name] == nil, "duplicate struct field: " .. field_name)

        local fa = type_align(field_type)
        if fa > max_align then max_align = fa end
        offset = align_up(offset, fa)

        local entry = {
            name = field_name,
            type = field_type,
            offset = offset,
            size = type_size(field_type),
        }
        ordered[#ordered + 1] = entry
        lookup[field_name] = entry
        offset = offset + entry.size
    end

    local S = setmetatable({
        name = name,
        layout_kind = "struct",
        fields = ordered,
        field_lookup = lookup,
        size = align_up(offset, max_align),
        align = max_align,
    }, StructMT)
    return S
end

StructMT.__tostring = function(self)
    return string.format("moonlift.struct<%s size=%d align=%d>", self.name, self.size, self.align)
end

StructMT.__index = function(self, key)
    if key == "name" or key == "layout_kind" or key == "fields" or key == "field_lookup"
       or key == "size" or key == "align" then
        return rawget(self, key)
    end
    local f = rawget(self, "field_lookup")
    if f then return f[key] end
    return nil
end

local function make_union(name, fields)
    assert(type(name) == "string", "moonlift.union name must be a string")
    assert(type(fields) == "table", "moonlift.union fields must be a table")

    local ordered = {}
    local lookup = {}
    local max_size = 0
    local max_align = 1

    for i = 1, #fields do
        local field = fields[i]
        local field_name = assert(field[1], "union field missing name")
        local field_type = assert(field[2], "union field missing type")
        assert(type(field_name) == "string", "union field name must be a string")
        assert(lookup[field_name] == nil, "duplicate union field: " .. field_name)
        local fa = type_align(field_type)
        local fs = type_size(field_type)
        if fa > max_align then max_align = fa end
        if fs > max_size then max_size = fs end
        local entry = {
            name = field_name,
            type = field_type,
            offset = 0,
            size = fs,
        }
        ordered[#ordered + 1] = entry
        lookup[field_name] = entry
    end

    return setmetatable({
        name = name,
        layout_kind = "struct",
        union_kind = true,
        fields = ordered,
        field_lookup = lookup,
        size = align_up(max_size, max_align),
        align = max_align,
    }, StructMT)
end

local function make_tagged_union(name, spec)
    assert(type(name) == "string", "moonlift.tagged_union name must be a string")
    assert(type(spec) == "table", "moonlift.tagged_union spec must be a table")
    local base_t = spec.base or types.u8
    local variants = assert(spec.variants, "moonlift.tagged_union requires variants")
    local tag_items = {}
    local payload_fields = {}
    local idx = 0
    for variant_name, fields in pairs(variants) do
        idx = idx + 1
        tag_items[variant_name] = idx - 1
        local payload_t
        if type(fields) == "table" and fields.layout_kind then
            payload_t = fields
        else
            local field_list = {}
            if #fields > 0 then
                for i = 1, #fields do field_list[i] = fields[i] end
            else
                for fk, fv in pairs(fields) do
                    field_list[#field_list + 1] = { fk, fv }
                end
                table.sort(field_list, function(a, b) return a[1] < b[1] end)
            end
            payload_t = make_struct(name .. "_" .. variant_name, field_list)
        end
        payload_fields[#payload_fields + 1] = { variant_name, payload_t }
    end
    local Tag = make_enum(name .. "Tag", base_t, tag_items)
    local Payload = make_union(name .. "Payload", payload_fields)
    local Outer = make_struct(name, {
        { "tag", Tag },
        { "payload", Payload },
    })
    Outer.Tag = Tag
    Outer.Payload = Payload
    Outer.variants = variants
    for variant_name, _ in pairs(tag_items) do
        Outer[variant_name] = Tag[variant_name]
    end
    return Outer
end

local function make_array(elem_t, count)
    assert(type(count) == "number" and count >= 0, "moonlift.array count must be a non-negative number")
    return setmetatable({
        name = ("array(%s,%d)"):format(elem_t.name or "?", count),
        layout_kind = "array",
        elem = elem_t,
        count = count,
        size = type_size(elem_t) * count,
        align = type_align(elem_t),
    }, ArrayTypeMT)
end

make_enum = function(name, base_t, items)
    assert(type(name) == "string", "moonlift.enum name must be a string")
    assert(is_type(base_t) and is_integer_type(base_t) and not is_bool_type(base_t) and not is_void_type(base_t),
        "moonlift.enum base type must be an integer-like Moonlift type")
    assert(type(items) == "table", "moonlift.enum items must be a table")
    local E = new_type {
        name = name,
        lowering_name = lower_type_name(base_t),
        const_tag = base_t.const_tag,
        family = "enum",
        base = base_t,
        bits = base_t.bits,
        signed = base_t.signed,
        size = type_size(base_t),
        align = type_align(base_t),
    }
    for k, v in pairs(items) do
        assert(type(k) == "string", "moonlift.enum keys must be strings")
        assert(type(v) == "number", "moonlift.enum values must be numbers")
        E[k] = expr({ tag = base_t.const_tag, value = v, type = lower_type_name(base_t) }, E)
    end
    return E
end

ArrayTypeMT.__tostring = function(self)
    return string.format("moonlift.array<%s x %d>", self.elem.name or "?", self.count)
end

UnionMT.__tostring = function(self)
    return string.format("moonlift.union<%s size=%d align=%d>", self.name, self.size, self.align)
end

local ptr_cache = {}

local function make_ptr(elem_t)
    local cached = ptr_cache[elem_t]
    if cached then return cached end
    local P = setmetatable({
        name = "ptr",
        const_tag = "ptr",
        family = "ptr",
        elem = elem_t,
        bits = 64,
        size = 8,
        align = 8,
    }, PtrTypeMT)
    ptr_cache[elem_t] = P
    return P
end

PtrTypeMT.__tostring = function(self)
    local en = self.elem and (self.elem.name or tostring(self.elem)) or "void"
    return string.format("moonlift.ptr<%s>", en)
end

PtrTypeMT.__call = function(self, value)
    if type(value) == "string" then
        return param(value, self)
    end
    if type(value) == "number" then
        return expr({ tag = "ptr", value = value, type = "ptr" }, self)
    end
    error("ptr(...) expects a constant address or parameter name", 2)
end

local function make_slice(elem_t)
    assert(elem_t ~= nil, "moonlift.slice requires an element type")
    local cached = slice_cache[elem_t]
    if cached ~= nil then
        return cached
    end
    local S = make_struct(("slice(%s)"):format(elem_t.name or "?"), {
        { "ptr", make_ptr(elem_t) },
        { "len", types.usize },
    })
    S.slice_elem = elem_t
    slice_cache[elem_t] = S
    return S
end

local function is_ptr_type(t)
    return is_type(t) and (t.family == "ptr" or getmetatable(t) == PtrTypeMT)
end

local function is_struct_type(t)
    return type(t) == "table" and t.layout_kind == "struct"
end

local function is_array_type(t)
    return type(t) == "table" and t.layout_kind == "array"
end

local function is_layout_type(t)
    return is_struct_type(t) or is_array_type(t)
end

local function make_field_load(base_expr, field_entry)
    local ft = field_entry.type
    local offset_val = { tag = "i64", value = field_entry.offset, type = "i64" }
    local addr = { tag = "add", lhs = base_expr.node, rhs = offset_val, type = "ptr" }

    if is_layout_type(ft) then
        return make_struct_view(addr, ft)
    end

    local scalar_t
    if is_type(ft) then
        scalar_t = ft
    else
        error("moonlift field type is not a scalar type: " .. tostring(ft.name), 2)
    end
    return expr({ tag = "load", addr = addr, type = lower_type_name(scalar_t) }, scalar_t)
end

local function make_field_store(base_expr, field_entry, value)
    local ft = field_entry.type
    if is_layout_type(ft) then
        error("cannot assign aggregate struct fields directly", 2)
    end
    local scalar_t
    if is_type(ft) then
        scalar_t = ft
    else
        error("moonlift field type is not a scalar type: " .. tostring(ft.name), 2)
    end
    value = as_expr(value, scalar_t)
    local offset_val = { tag = "i64", value = field_entry.offset, type = "i64" }
    local addr = { tag = "add", lhs = base_expr.node, rhs = offset_val, type = "ptr" }
    local frame = current_frame()
    if frame == nil then
        error("moonlift store outside of a block context", 2)
    end
    frame.stmts[#frame.stmts + 1] = {
        tag = "store",
        type = lower_type_name(scalar_t),
        addr = addr,
        value = value.node,
    }
end

local function make_array_elem_load(base_expr, elem_t, index_expr)
    index_expr = as_expr(index_expr)
    local elem_size = type_size(elem_t)
    local scaled = { tag = "mul", lhs = index_expr.node, rhs = { tag = "i64", value = elem_size, type = "i64" }, type = "i64" }
    local addr = { tag = "add", lhs = base_expr.node, rhs = scaled, type = "ptr" }

    if is_layout_type(elem_t) then
        return make_struct_view(addr, elem_t)
    end

    local scalar_t = elem_t
    return expr({ tag = "load", addr = addr, type = lower_type_name(scalar_t) }, scalar_t)
end

local function make_array_elem_store(base_expr, elem_t, index_expr, value)
    if is_layout_type(elem_t) then
        error("cannot assign aggregate array elements directly", 2)
    end
    index_expr = as_expr(index_expr)
    value = as_expr(value, elem_t)
    local elem_size = type_size(elem_t)
    local scaled = { tag = "mul", lhs = index_expr.node, rhs = { tag = "i64", value = elem_size, type = "i64" }, type = "i64" }
    local addr = { tag = "add", lhs = base_expr.node, rhs = scaled, type = "ptr" }
    local frame = current_frame()
    if frame == nil then
        error("moonlift store outside of a block context", 2)
    end
    frame.stmts[#frame.stmts + 1] = {
        tag = "store",
        type = lower_type_name(elem_t),
        addr = addr,
        value = value.node,
    }
end

local StructViewMT = {}

function make_struct_view(addr_node, struct_t)
    return setmetatable({
        _addr = addr_node,
        _struct = struct_t,
    }, StructViewMT)
end

StructViewMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if key == "_addr" or key == "_struct" then return rawget(self, key) end
    local s = rawget(self, "_struct")
    local f = s.field_lookup[key]
    if f == nil then
        error(("struct '%s' has no field '%s'"):format(s.name, key), 2)
    end
    local base = expr(rawget(self, "_addr"), make_ptr(s))
    return make_field_load(base, f)
end

StructViewMT.__newindex = function(self, key, value)
    if key == "_addr" or key == "_struct" then rawset(self, key, value); return end
    local s = rawget(self, "_struct")
    local f = s.field_lookup[key]
    if f == nil then
        error(("struct '%s' has no field '%s'"):format(s.name, key), 2)
    end
    local base = expr(rawget(self, "_addr"), make_ptr(s))
    make_field_store(base, f, value)
end

local ArrayViewMT = {}

local function make_array_view(addr_node, array_t)
    return setmetatable({
        _addr = addr_node,
        _array = array_t,
    }, ArrayViewMT)
end

ArrayViewMT.__index = function(self, key)
    if type(key) == "string" then
        if key == "_addr" or key == "_array" then return rawget(self, key) end
        if key == "count" then return rawget(self, "_array").count end
        if key == "size" then return rawget(self, "_array").size end
        return nil
    end
    local a = rawget(self, "_array")
    local base = expr(rawget(self, "_addr"), make_ptr(a.elem))
    return make_array_elem_load(base, a.elem, key)
end

ArrayViewMT.__newindex = function(self, key, value)
    if type(key) == "string" then
        rawset(self, key, value)
        return
    end
    local a = rawget(self, "_array")
    local base = expr(rawget(self, "_addr"), make_ptr(a.elem))
    make_array_elem_store(base, a.elem, key, value)
end

local orig_expr_index = ExprMT.__index
ExprMT.__index = function(self, key)
    if is_ptr_type(self.t) and self.t.elem ~= nil then
        local elem = self.t.elem
        if is_struct_type(elem) and type(key) == "string" then
            local f = elem.field_lookup[key]
            if f ~= nil then
                return make_field_load(self, f)
            end
        end
        if is_array_type(elem) then
            if key == "count" then return elem.count end
            if key == "size" then return elem.size end
        end
        if type(key) == "number" or is_expr(key) then
            return make_array_elem_load(self, elem, key)
        end
    end
    if type(orig_expr_index) == "function" then
        return orig_expr_index(self, key)
    elseif type(orig_expr_index) == "table" then
        return orig_expr_index[key]
    end
    return nil
end

local orig_expr_newindex = ExprMT.__newindex
ExprMT.__newindex = function(self, key, value)
    if is_ptr_type(self.t) and self.t.elem ~= nil then
        local elem = self.t.elem
        if is_struct_type(elem) and type(key) == "string" then
            local f = elem.field_lookup[key]
            if f ~= nil then
                make_field_store(self, f, value)
                return
            end
        end
        if type(key) == "number" or is_expr(key) then
            make_array_elem_store(self, elem, key, value)
            return
        end
    end
    if orig_expr_newindex then
        orig_expr_newindex(self, key, value)
    else
        rawset(self, key, value)
    end
end

local function as_byte_ptr(x)
    return cast(make_ptr(types.byte), as_expr(x))
end

local function load(T, p)
    assert(T ~= nil, "moonlift.load requires a type")
    local ptr_t = make_ptr(T)
    local ptr_v = as_expr(p, ptr_t)
    if is_struct_type(T) then
        return make_struct_view(ptr_v.node, T)
    elseif is_array_type(T) then
        return make_array_view(ptr_v.node, T)
    else
        return expr({ tag = "load", addr = ptr_v.node, type = lower_type_name(T) }, T)
    end
end

local function memcpy(dst, src, len)
    dst = as_byte_ptr(dst)
    src = as_byte_ptr(src)
    len = as_expr(len, types.usize)
    local i = var(types.usize(0))
    while_(i:lt(len), function()
        dst[i] = src[i]
        i:set(i + types.usize(1))
    end)
    return nil
end

local function memmove(dst, src, len)
    dst = as_byte_ptr(dst)
    src = as_byte_ptr(src)
    len = as_expr(len, types.usize)
    local _ = let((dst:lt(src))(
        function()
            local i = var(types.usize(0))
            while_(i:lt(len), function()
                dst[i] = src[i]
                i:set(i + types.usize(1))
            end)
            return types.u8(0)
        end,
        function()
            local i = var(len)
            while_(i:gt(types.usize(0)), function()
                i:set(i - types.usize(1))
                dst[i] = src[i]
            end)
            return types.u8(0)
        end
    ))
    return nil
end

local function memset(dst, byte_value, len)
    dst = as_byte_ptr(dst)
    byte_value = as_expr(byte_value, types.byte)
    len = as_expr(len, types.usize)
    local i = var(types.usize(0))
    while_(i:lt(len), function()
        dst[i] = byte_value
        i:set(i + types.usize(1))
    end)
    return nil
end

local function memcmp(a, b, len)
    a = as_byte_ptr(a)
    b = as_byte_ptr(b)
    len = as_expr(len, types.usize)
    return block(function()
        local i = var(types.usize(0))
        local out = var(types.i32(0))
        while_(i:lt(len), function()
            local av = let(zext(types.i32, a[i]))
            local bv = let(zext(types.i32, b[i]))
            local diff = let((av:lt(bv))(types.i32(-1), (av:gt(bv))(types.i32(1), types.i32(0))))
            out:set((out:eq(types.i32(0)))(diff, out))
            i:set(i + types.usize(1))
        end)
        return out
    end)
end

local function copy(T, dst, src)
    assert(T ~= nil, "moonlift.copy requires a type")
    if is_struct_type(T) or is_array_type(T) then
        memcpy(as_byte_ptr(as_expr(dst, make_ptr(T))), as_byte_ptr(as_expr(src, make_ptr(T))), types.usize(type_size(T)))
        return nil
    end
    local dst_ptr = as_expr(dst, make_ptr(T))
    local value
    if is_expr(src) then
        if is_ptr_type(src.t) then
            value = load(T, src)
        else
            value = as_expr(src, T)
        end
    else
        value = as_expr(src, T)
    end
    emit_stmt({ tag = "store", type = lower_type_name(T), addr = dst_ptr.node, value = value.node })
    return nil
end

local function store(T, dst, value)
    assert(T ~= nil, "moonlift.store requires a type")
    if is_struct_type(T) or is_array_type(T) then
        if type(value) == "table" and ((getmetatable(value) == StructViewMT) or (getmetatable(value) == ArrayViewMT)) then
            local src_addr = expr(rawget(value, "_addr"), make_ptr(T))
            return copy(T, dst, src_addr)
        elseif is_expr(value) and is_ptr_type(value.t) and value.t.elem == T then
            return copy(T, dst, value)
        else
            error("moonlift.store aggregate expects a pointer/view source", 2)
        end
    end
    return copy(T, dst, value)
end

M = {
    types = types,
    void = types.void,
    bool = types.bool,
    i8 = types.i8,
    i16 = types.i16,
    i32 = types.i32,
    i64 = types.i64,
    u8 = types.u8,
    u16 = types.u16,
    u32 = types.u32,
    u64 = types.u64,
    usize = types.usize,
    byte = types.byte,
    isize = types.isize,
    f32 = types.f32,
    f64 = types.f64,
    ptr = make_ptr,
    struct_ = make_struct,
    union = make_union,
    tagged_union = make_tagged_union,
    array = make_array,
    slice = make_slice,
    enum = make_enum,
    param = param,
    arg = arg,
    let = setmetatable({}, LetMT),
    var = setmetatable({}, VarMT),
    block = block,
    quote = quote,
    cast = cast,
    trunc = trunc,
    zext = zext,
    sext = sext,
    bitcast = bitcast,
    func = func,
    extern = extern,
    invoke = invoke,
    module = module,
    if_ = if_,
    switch_ = switch_,
    while_ = while_,
    break_ = break_,
    continue_ = continue_,
    env = env,
    use = use,
    compile = compile,
    add = backend.add,
    call = backend.call,
    addr = backend.addr,
    call1 = backend.call1,
    call2 = backend.call2,
    stats = backend.stats,
    load = load,
    store = store,
    copy = copy,
    memcpy = memcpy,
    memmove = memmove,
    memset = memset,
    memcmp = memcmp,
}

return M
