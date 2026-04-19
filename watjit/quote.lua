local Scope = require("watjit.scope")
local types = require("watjit.types")

local coerce = types.coerce
local Val = types.Val
local QuoteMT = {}
local next_label_id = 0

local function sanitize_hint(hint)
    hint = tostring(hint or "q")
    hint = hint:gsub("^%$+", "")
    hint = hint:gsub("[^%w_]", "_")
    if hint == "" then
        hint = "q"
    end
    return hint
end

local function fresh_label(hint)
    next_label_id = next_label_id + 1
    return ("$%s_%d"):format(sanitize_hint(hint), next_label_id)
end

local function normalize_params(params)
    params = params or {}
    assert(type(params) == "table", "quote params must be a table")
    local out = {}
    for i = 1, #params do
        local p = params[i]
        assert(type(p) == "table" and p.t ~= nil and p.name ~= nil, "quote params must be typed named watjit values")
        out[i] = { name = p.name, t = p.t }
    end
    return out
end

local function clone_expr(node, remap)
    local op = node.op

    if op == "const" then
        return { op = op, t = node.t, value = node.value }
    end
    if op == "vconst" then
        local lanes = {}
        for i = 1, #node.lanes do
            lanes[i] = clone_expr(node.lanes[i], remap)
        end
        return { op = op, t = node.t, lanes = lanes }
    end
    if op == "get" then
        return { op = op, name = remap.locals[node.name] or node.name }
    end
    if op == "wat_unary" then
        return { op = op, t = node.t, wat_op = node.wat_op, value = clone_expr(node.value, remap) }
    end
    if op == "add" or op == "sub" or op == "mul" or op == "div" or op == "rem"
        or op == "div_u" or op == "div_s" or op == "rem_u" or op == "rem_s"
        or op == "band" or op == "bor" or op == "bxor"
        or op == "shl" or op == "shr_u" or op == "shr_s" or op == "rotl" or op == "rotr"
        or op == "lt" or op == "le" or op == "gt" or op == "ge"
        or op == "lt_u" or op == "le_u" or op == "gt_u" or op == "ge_u"
        or op == "eq" or op == "ne" then
        return {
            op = op,
            t = node.t,
            l = clone_expr(node.l, remap),
            r = clone_expr(node.r, remap),
        }
    end
    if op == "select" then
        return {
            op = op,
            t = node.t,
            cond = clone_expr(node.cond, remap),
            then_ = clone_expr(node.then_, remap),
            else_ = clone_expr(node.else_, remap),
        }
    end
    if op == "load" or op == "vload" then
        return {
            op = op,
            t = node.t,
            ptr = clone_expr(node.ptr, remap),
        }
    end
    if op == "splat" then
        return { op = op, t = node.t, value = clone_expr(node.value, remap) }
    end
    if op == "extract_lane" then
        return {
            op = op,
            t = node.t,
            vec_t = node.vec_t,
            value = clone_expr(node.value, remap),
            lane = node.lane,
        }
    end
    if op == "replace_lane" then
        return {
            op = op,
            t = node.t,
            value = clone_expr(node.value, remap),
            scalar = clone_expr(node.scalar, remap),
            lane = node.lane,
        }
    end
    if op == "call" then
        local args = {}
        for i = 1, #node.args do
            args[i] = clone_expr(node.args[i], remap)
        end
        return {
            op = op,
            name = node.name,
            args = args,
            t = node.t,
        }
    end
    if op == "vbitselect" then
        return {
            op = op,
            t = node.t,
            mask = clone_expr(node.mask, remap),
            then_ = clone_expr(node.then_, remap),
            else_ = clone_expr(node.else_, remap),
        }
    end
    if op == "shuffle" then
        local lanes = {}
        for i = 1, #node.lanes do
            lanes[i] = node.lanes[i]
        end
        return {
            op = op,
            t = node.t,
            l = clone_expr(node.l, remap),
            r = clone_expr(node.r, remap),
            lanes = lanes,
        }
    end
    if op == "eqz" then
        return {
            op = op,
            t = node.t,
            val = clone_expr(node.val, remap),
        }
    end

    error("unsupported quote expression op: " .. tostring(op), 2)
end

local function clone_stmt(node, remap)
    local op = node.op

    if op == "set" then
        return {
            op = op,
            name = remap.locals[node.name] or node.name,
            value = clone_expr(node.value, remap),
        }
    end
    if op == "store" or op == "vstore" then
        return {
            op = op,
            t = node.t,
            ptr = clone_expr(node.ptr, remap),
            value = clone_expr(node.value, remap),
        }
    end
    if op == "call" then
        local args = {}
        for i = 1, #node.args do
            args[i] = clone_expr(node.args[i], remap)
        end
        return {
            op = op,
            name = node.name,
            args = args,
        }
    end
    if op == "block" or op == "loop" then
        local label = remap.labels[node.label]
        if label == nil then
            label = fresh_label(node.label)
            remap.labels[node.label] = label
        end
        local body = {}
        for i = 1, #node.body do
            body[i] = clone_stmt(node.body[i], remap)
        end
        return {
            op = op,
            label = label,
            body = body,
        }
    end
    if op == "br" then
        return {
            op = op,
            label = remap.labels[node.label] or node.label,
        }
    end
    if op == "br_if" then
        return {
            op = op,
            label = remap.labels[node.label] or node.label,
            cond = clone_expr(node.cond, remap),
        }
    end
    if op == "if" then
        local then_ = {}
        local else_ = {}
        for i = 1, #node.then_ do
            then_[i] = clone_stmt(node.then_[i], remap)
        end
        for i = 1, #node.else_ do
            else_[i] = clone_stmt(node.else_[i], remap)
        end
        return {
            op = op,
            cond = clone_expr(node.cond, remap),
            then_ = then_,
            else_ = else_,
        }
    end
    if op == "return" then
        return {
            op = op,
            value = clone_expr(node.value, remap),
        }
    end

    error("unsupported quote statement op: " .. tostring(op), 2)
end

local function splice(self, ...)
    local scope = Scope.current()
    if not scope then
        error("quote splice outside of a watjit scope", 2)
    end

    local argc = select("#", ...)
    if argc ~= #self.params then
        error(string.format("quote expects %d arguments, got %d", #self.params, argc), 2)
    end

    local remap = {
        locals = {},
        labels = {},
    }

    for i = 1, #self.params do
        local param = self.params[i]
        local arg = coerce(select(i, ...), param.t)
        local temp_name = scope:declare_fresh(param.name or "arg", param.t)
        scope:push_stmt({ op = "set", name = temp_name, value = arg.expr })
        remap.locals[param.name] = temp_name
    end

    for i = 1, #self.locals do
        local local_ = self.locals[i]
        remap.locals[local_.name] = scope:declare_fresh(local_.name, local_.t)
    end

    for i = 1, #self.body do
        scope:push_stmt(clone_stmt(self.body[i], remap))
    end

    if self.kind == "quote_expr" then
        local expr = clone_expr(self.result, remap)
        return Val.new(expr, self.ret)
    end
    return nil
end

QuoteMT.__index = QuoteMT
QuoteMT.__call = function(self, ...)
    return splice(self, ...)
end

local function quote_expr(spec)
    assert(type(spec) == "table", "quote_expr spec must be a table")
    assert(type(spec.body) == "function", "quote_expr spec.body must be a function")

    local params = normalize_params(spec.params)
    local scope = Scope.push()
    local args = {}
    for i = 1, #params do
        local p = params[i]
        args[i] = Val.new({ op = "get", name = p.name }, p.t, { name = p.name })
    end
    local ret = spec.body(table.unpack(args, 1, #args))
    Scope.pop()

    assert(ret ~= nil, "quote_expr body must return a value")
    local ret_t = spec.ret or spec.returns or ret.t
    assert(ret_t ~= nil, "quote_expr could not infer return type")
    ret = coerce(ret, ret_t)

    return setmetatable({
        kind = "quote_expr",
        params = params,
        ret = ret_t,
        locals = scope.locals,
        body = scope.stmts,
        result = ret.expr,
    }, QuoteMT)
end

local function quote_block(spec)
    assert(type(spec) == "table", "quote_block spec must be a table")
    assert(type(spec.body) == "function", "quote_block spec.body must be a function")

    local params = normalize_params(spec.params)
    local scope = Scope.push()
    local args = {}
    for i = 1, #params do
        local p = params[i]
        args[i] = Val.new({ op = "get", name = p.name }, p.t, { name = p.name })
    end
    local ret = spec.body(table.unpack(args, 1, #args))
    Scope.pop()

    if ret ~= nil then
        error("quote_block body must not return a value", 2)
    end

    return setmetatable({
        kind = "quote_block",
        params = params,
        locals = scope.locals,
        body = scope.stmts,
    }, QuoteMT)
end

return {
    quote_expr = quote_expr,
    quote_block = quote_block,
}
