local types = require("watjit.types")
local ctrl = require("watjit.ctrl")
local func = require("watjit.func")
local quote = require("watjit.quote")
local stream = require("watjit.stream")

local i32 = types.i32
local coerce = types.coerce

local M = {}
local BoundMT = {}

local uid = 0
local function gensym(prefix)
    uid = uid + 1
    return ("%s_%d"):format(prefix, uid)
end

local function new_ctx()
    return {
        locals = {},
        stop = nil,
    }
end

local function local_once(ctx, key, t, init, prefix)
    local v = ctx.locals[key]
    if v ~= nil then
        return v
    end
    v = types.let(t, gensym(prefix or "tmp"), init)
    ctx.locals[key] = v
    return v
end

local function halt_flag(ctx)
    if ctx.stop ~= nil then
        return ctx.stop
    end
    ctx.stop = types.let(i32, gensym("iter_halt"), 0)
    return ctx.stop
end

local function continue_code()
    return i32(0)
end

local function break_code()
    return i32(1)
end

local function halt_code()
    return i32(2)
end

local function host_const(x)
    if type(x) == "table" and x.expr ~= nil and x.expr.op == "const" then
        return x.expr.value
    end
    return x
end

local function is_quote(x)
    return type(x) == "table" and (x.kind == "quote_expr" or x.kind == "quote_block")
end

local function is_bound(x)
    return getmetatable(x) == BoundMT
end

local function pack_args(...)
    return { n = select("#", ...), ... }
end

local function call_with_packed(callable, packed, extra)
    extra = extra or pack_args()
    local total = packed.n + extra.n
    local args = {}
    local k = 0
    for i = 1, packed.n do
        k = k + 1
        args[k] = packed[i]
    end
    for i = 1, extra.n do
        k = k + 1
        args[k] = extra[i]
    end
    return callable(table.unpack(args, 1, total))
end

local function adapt_emit(emit)
    if type(emit) == "function" then
        return emit
    end
    if is_quote(emit) then
        if emit.kind == "quote_expr" then
            return function(v)
                return emit(v)
            end
        end
        return function(v)
            emit(v)
            return continue_code()
        end
    end
    if is_bound(emit) then
        local target = emit.target
        if type(target) == "function" then
            return function(v)
                return call_with_packed(target, emit.bound, pack_args(v))
            end
        end
        if is_quote(target) then
            if target.kind == "quote_expr" then
                return function(v)
                    return call_with_packed(target, emit.bound, pack_args(v))
                end
            end
            return function(v)
                call_with_packed(target, emit.bound, pack_args(v))
                return continue_code()
            end
        end
    end
    error("watjit.iter: emit must be a function, quote, or iter.bind(...) result", 3)
end

local function adapt_reducer(reducer)
    if type(reducer) == "function" then
        return reducer
    end
    if is_quote(reducer) then
        assert(reducer.kind == "quote_expr", "watjit.iter.fold: reducer quote must be quote_expr")
        return function(acc, v)
            return reducer(acc, v)
        end
    end
    if is_bound(reducer) then
        local target = reducer.target
        if type(target) == "function" then
            return function(acc, v)
                return call_with_packed(target, reducer.bound, pack_args(acc, v))
            end
        end
        assert(is_quote(target) and target.kind == "quote_expr", "watjit.iter.fold: bound reducer must target a quote_expr or function")
        return function(acc, v)
            return call_with_packed(target, reducer.bound, pack_args(acc, v))
        end
    end
    error("watjit.iter.fold: reducer must be a function, quote_expr, or iter.bind(...) result", 3)
end

local function typed_param(x, default_name)
    assert(type(x) == "table" and x.t ~= nil, "watjit.iter: expected a typed named watjit value")
    local name = x.name or default_name
    assert(name ~= nil, "watjit.iter: typed param is missing a name")
    return { name = name, t = x.t }
end

local function build_quote_params(prefix, params, final_param)
    local out = {}
    params = params or {}
    for i = 1, #params do
        out[i] = typed_param(params[i], prefix .. i)
    end
    out[#out + 1] = typed_param(final_param, prefix .. (#out + 1))
    return out
end

local function empty_plan(item_t)
    return {
        kind = "empty",
        item_t = item_t,
        count_hint = 0,
    }
end

local function is_empty_plan(plan)
    return plan.kind == "empty"
end

local normalize

local function normalize_map(plan)
    local src = normalize(plan.src)
    if is_empty_plan(src) then
        return empty_plan(plan.item_t)
    end
    if src == plan.src then
        return plan
    end
    return {
        kind = "map",
        item_t = plan.item_t,
        count_hint = src.count_hint,
        src = src,
        f = plan.f,
    }
end

local function normalize_filter(plan)
    local src = normalize(plan.src)
    if is_empty_plan(src) then
        return empty_plan(plan.item_t)
    end
    if src == plan.src then
        return plan
    end
    return {
        kind = "filter",
        item_t = plan.item_t,
        count_hint = nil,
        src = src,
        pred = plan.pred,
    }
end

local function normalize_concat(plan)
    local left = normalize(plan.left)
    local right = normalize(plan.right)

    if is_empty_plan(left) then
        return right
    end
    if is_empty_plan(right) then
        return left
    end

    return {
        kind = "concat",
        item_t = plan.item_t,
        count_hint = (left.count_hint ~= nil and right.count_hint ~= nil) and (left.count_hint + right.count_hint) or nil,
        left = left,
        right = right,
    }
end

local function normalize_take(plan)
    local src = normalize(plan.src)
    local n = host_const(plan.n)

    if type(n) == "number" then
        if n <= 0 then
            return empty_plan(plan.item_t)
        end
        if is_empty_plan(src) or src.kind == "once" then
            return src
        end
        if src.kind == "take" then
            local inner_n = host_const(src.n)
            if type(inner_n) == "number" then
                return normalize({
                    kind = "take",
                    item_t = plan.item_t,
                    src = src.src,
                    n = math.min(n, inner_n),
                })
            end
        end
    end

    if src == plan.src then
        return plan
    end
    return {
        kind = "take",
        item_t = plan.item_t,
        count_hint = (src.count_hint ~= nil and type(n) == "number") and math.min(src.count_hint, n) or plan.count_hint,
        src = src,
        n = plan.n,
    }
end

local function normalize_drop(plan)
    local src = normalize(plan.src)
    local n = host_const(plan.n)

    if type(n) == "number" then
        if n <= 0 then
            return src
        end
        if is_empty_plan(src) then
            return src
        end
        if src.kind == "once" then
            return empty_plan(plan.item_t)
        end
        if src.kind == "drop" then
            local inner_n = host_const(src.n)
            if type(inner_n) == "number" then
                return normalize({
                    kind = "drop",
                    item_t = plan.item_t,
                    src = src.src,
                    n = n + inner_n,
                })
            end
        end
    end

    if src == plan.src then
        return plan
    end
    return {
        kind = "drop",
        item_t = plan.item_t,
        count_hint = (src.count_hint ~= nil and type(n) == "number") and math.max(0, src.count_hint - n) or plan.count_hint,
        src = src,
        n = plan.n,
    }
end

local function normalize_simd_map(plan)
    local src = normalize(plan.src)
    if is_empty_plan(src) then
        return empty_plan(plan.item_t)
    end
    if src == plan.src then
        return plan
    end
    return {
        kind = "simd_map",
        item_t = plan.item_t,
        count_hint = src.count_hint,
        src = src,
        vector_t = plan.vector_t,
        vf = plan.vf,
        sf = plan.sf,
    }
end

function normalize(plan)
    assert(type(plan) == "table" and plan.kind ~= nil, "watjit.iter.normalize: expected a watjit.stream plan")

    local kind = plan.kind
    if kind == "empty" or kind == "once" or kind == "range" or kind == "seq" or kind == "cached_seq" then
        return plan
    elseif kind == "map" then
        return normalize_map(plan)
    elseif kind == "filter" then
        return normalize_filter(plan)
    elseif kind == "concat3" then
        return normalize({
            kind = "concat",
            item_t = plan.item_t,
            left = normalize({ kind = "concat", item_t = plan.item_t, left = plan.a, right = plan.b }),
            right = plan.c,
        })
    elseif kind == "concat2" then
        return normalize({ kind = "concat", item_t = plan.item_t, left = plan.left, right = plan.right })
    elseif kind == "concat" then
        return normalize_concat(plan)
    elseif kind == "take" then
        return normalize_take(plan)
    elseif kind == "drop" then
        return normalize_drop(plan)
    elseif kind == "simd_map" then
        return normalize_simd_map(plan)
    end

    return plan
end

local lower_plan

local function lower_emit_result(v, emit, ctx, break_loop)
    local halt = halt_flag(ctx)
    ctrl.if_(halt:eq(0), function()
        local code = types.let(i32, gensym("emit_code"), emit(v))
        ctrl.if_(code:ne(0), function()
            ctrl.if_(code:eq(halt_code()), function()
                halt(1)
            end)
            if break_loop ~= nil then
                break_loop:break_()
            end
        end)
    end)
end

local function lower_source_seq(node, emit, ctx)
    local count = assert(node.count, "watjit.iter.lower(seq): seq count is required")
    local view = types.view(node.item_t, node.base, gensym("seq"))
    local i = types.let(i32, gensym("i"), 0)
    ctrl.for_(i, count, function(loop)
        lower_emit_result(view[i], emit, ctx, loop)
    end)
end

local function lower_source_cached_seq(node, emit, ctx)
    local count = assert(node.count, "watjit.iter.lower(cached_seq): cached_seq count is required")
    local view = types.view(node.item_t, node.values, gensym("cached_seq"))
    local i = types.let(i32, gensym("i"), 0)
    ctrl.for_(i, count, function(loop)
        lower_emit_result(view[i], emit, ctx, loop)
    end)
end

local function lower_source_range(node, emit, ctx)
    local step = node.step or 1
    local idx = types.let(node.item_t, gensym("range_i"), node.start)
    ctrl.for_(idx, node.start, node.stop, step, function(loop)
        lower_emit_result(idx, emit, ctx, loop)
    end)
end

local function lower_source_once(node, emit, ctx)
    lower_emit_result(coerce(node.value, node.item_t), emit, ctx, nil)
end

local function lower_source_empty(_node, _emit, _ctx)
end

local function wrap_map(node, emit, _ctx)
    return function(v)
        return emit(node.f(v))
    end
end

local function wrap_filter(node, emit, _ctx)
    return function(v)
        local out = types.let(i32, gensym("filter_out"), continue_code())
        ctrl.if_(node.pred(v), function()
            out(emit(v))
        end)
        return out
    end
end

local function wrap_take(node, emit, ctx)
    local remaining = local_once(ctx, node, i32, node.n, "take")
    return function(v)
        local out = types.let(i32, gensym("take_out"), continue_code())
        ctrl.if_(remaining:gt(0), function()
            remaining(remaining - i32(1))
            out(emit(v))
            ctrl.if_(out:eq(continue_code()), function()
                ctrl.if_(remaining:eq(0), function()
                    out(break_code())
                end)
            end)
        end, function()
            out(break_code())
        end)
        return out
    end
end

local function wrap_drop(node, emit, ctx)
    local remaining = local_once(ctx, node, i32, node.n, "drop")
    return function(v)
        local out = types.let(i32, gensym("drop_out"), continue_code())
        ctrl.if_(remaining:gt(0), function()
            remaining(remaining - i32(1))
        end, function()
            out(emit(v))
        end)
        return out
    end
end

local function wrap_simd_map(node, emit, _ctx)
    return function(v)
        return emit(node.sf(v))
    end
end

function lower_plan(plan, emit, ctx)
    ctx = ctx or new_ctx()
    plan = normalize(plan)

    local kind = plan.kind
    if kind == "map" then
        return lower_plan(plan.src, wrap_map(plan, emit, ctx), ctx)
    elseif kind == "filter" then
        return lower_plan(plan.src, wrap_filter(plan, emit, ctx), ctx)
    elseif kind == "take" then
        return lower_plan(plan.src, wrap_take(plan, emit, ctx), ctx)
    elseif kind == "drop" then
        return lower_plan(plan.src, wrap_drop(plan, emit, ctx), ctx)
    elseif kind == "simd_map" then
        return lower_plan(plan.src, wrap_simd_map(plan, emit, ctx), ctx)
    elseif kind == "concat" then
        lower_plan(plan.left, emit, ctx)
        ctrl.if_(halt_flag(ctx):eq(0), function()
            lower_plan(plan.right, emit, ctx)
        end)
        return ctx
    elseif kind == "seq" then
        lower_source_seq(plan, emit, ctx)
        return ctx
    elseif kind == "cached_seq" then
        lower_source_cached_seq(plan, emit, ctx)
        return ctx
    elseif kind == "range" then
        lower_source_range(plan, emit, ctx)
        return ctx
    elseif kind == "once" then
        lower_source_once(plan, emit, ctx)
        return ctx
    elseif kind == "empty" then
        lower_source_empty(plan, emit, ctx)
        return ctx
    end

    error("watjit.iter.lower: unknown stream kind: " .. tostring(kind), 2)
end

function M.normalize(plan)
    return normalize(plan)
end

M.CONTINUE = continue_code
M.BREAK = break_code
M.HALT = halt_code
M.CONTINUE_VALUE = 0
M.BREAK_VALUE = 1
M.HALT_VALUE = 2

function M.bind(target, ...)
    assert(type(target) == "function" or is_quote(target), "watjit.iter.bind: target must be a function or quote")
    return setmetatable({
        kind = "iter_bound",
        target = target,
        bound = pack_args(...),
    }, BoundMT)
end

function M.sink_expr(spec)
    assert(type(spec) == "table", "watjit.iter.sink_expr: spec must be a table")
    local item = spec.item or (spec.item_t and spec.item_name and spec.item_t(spec.item_name)) or (spec.item_t and spec.item_t("item"))
    assert(item ~= nil, "watjit.iter.sink_expr: spec.item or spec.item_t is required")
    return quote.quote_expr {
        params = build_quote_params("sink", spec.params, item),
        ret = i32,
        body = assert(spec.body, "watjit.iter.sink_expr: spec.body is required"),
    }
end

function M.sink_block(spec)
    assert(type(spec) == "table", "watjit.iter.sink_block: spec must be a table")
    local item = spec.item or (spec.item_t and spec.item_name and spec.item_t(spec.item_name)) or (spec.item_t and spec.item_t("item"))
    assert(item ~= nil, "watjit.iter.sink_block: spec.item or spec.item_t is required")
    return quote.quote_block {
        params = build_quote_params("sink", spec.params, item),
        body = assert(spec.body, "watjit.iter.sink_block: spec.body is required"),
    }
end

function M.reducer_expr(spec)
    assert(type(spec) == "table", "watjit.iter.reducer_expr: spec must be a table")
    local acc = assert(spec.acc, "watjit.iter.reducer_expr: spec.acc is required")
    local item = spec.item or (spec.item_t and spec.item_name and spec.item_t("item"))
    assert(item ~= nil, "watjit.iter.reducer_expr: spec.item or spec.item_t is required")
    local params = {}
    if spec.params ~= nil then
        for i = 1, #spec.params do
            params[#params + 1] = spec.params[i]
        end
    end
    params[#params + 1] = acc
    params[#params + 1] = item
    return quote.quote_expr {
        params = params,
        ret = spec.ret or acc.t,
        body = assert(spec.body, "watjit.iter.reducer_expr: spec.body is required"),
    }
end

function M.lower(plan, emit, ctx)
    return lower_plan(plan, adapt_emit(emit), ctx or new_ctx())
end

function M.fold(plan, init, reducer, ret_t)
    local step = adapt_reducer(reducer)
    plan = normalize(plan)
    ret_t = ret_t or plan.item_t
    local acc = types.let(ret_t, gensym("fold_acc"), init)
    lower_plan(plan, function(v)
        acc(step(acc, v))
        return continue_code()
    end, new_ctx())
    return acc
end

function M.sum(plan, init)
    plan = normalize(plan)
    return M.fold(plan, init or 0, function(acc, v)
        return acc + v
    end, plan.item_t)
end

function M.count(plan)
    return M.fold(plan, 0, function(acc, _v)
        return acc + i32(1)
    end, i32)
end

function M.one(plan, default)
    plan = normalize(plan)
    local out = types.let(plan.item_t, gensym("one_out"), default or 0)
    local seen = types.let(i32, gensym("one_seen"), 0)
    lower_plan(plan, function(v)
        local code = types.let(i32, gensym("one_code"), continue_code())
        ctrl.if_(seen:eq(0), function()
            out(v)
            seen(1)
            code(halt_code())
        end, function()
            code(halt_code())
        end)
        return code
    end, new_ctx())
    return out
end

function M.drain_into(plan, out_base)
    plan = normalize(plan)
    local out = types.view(plan.item_t, out_base, gensym("drain_out"))
    local out_i = types.let(i32, gensym("drain_i"), 0)
    lower_plan(plan, function(v)
        out[out_i](v)
        out_i(out_i + i32(1))
        return continue_code()
    end, new_ctx())
    return out_i
end

function M.compile_drain_into(spec)
    assert(type(spec) == "table", "compile_drain_into spec must be a table")
    assert(type(spec.name) == "string", "compile_drain_into spec.name must be a string")
    assert(type(spec.params) == "table", "compile_drain_into spec.params must be a table")
    assert(type(spec.build) == "function", "compile_drain_into spec.build must be a function")

    return func.fn {
        name = spec.name,
        params = spec.params,
        ret = i32,
        body = function(...)
            local s, out_base = spec.build(...)
            assert(s and s.kind, "build must return (stream, out_base)")
            return M.drain_into(s, out_base)
        end,
    }
end

function M.compile_fold(spec)
    assert(type(spec) == "table", "compile_fold spec must be a table")
    assert(type(spec.name) == "string", "compile_fold spec.name must be a string")
    assert(type(spec.params) == "table", "compile_fold spec.params must be a table")
    assert(type(spec.build) == "function", "compile_fold spec.build must be a function")
    assert(type(spec.reducer) == "function", "compile_fold spec.reducer must be a function")
    assert(spec.ret ~= nil, "compile_fold spec.ret is required")

    return func.fn {
        name = spec.name,
        params = spec.params,
        ret = spec.ret,
        body = function(...)
            local s = spec.build(...)
            assert(s and s.kind, "build must return a stream")
            return M.fold(s, spec.init, spec.reducer, spec.ret)
        end,
    }
end

function M.compile_sum(spec)
    assert(type(spec) == "table", "compile_sum spec must be a table")
    assert(type(spec.name) == "string", "compile_sum spec.name must be a string")
    assert(type(spec.params) == "table", "compile_sum spec.params must be a table")
    assert(type(spec.build) == "function", "compile_sum spec.build must be a function")
    assert(spec.ret ~= nil, "compile_sum spec.ret is required")

    return func.fn {
        name = spec.name,
        params = spec.params,
        ret = spec.ret,
        body = function(...)
            local s = spec.build(...)
            assert(s and s.kind, "build must return a stream")
            return M.fold(s, spec.init or 0, function(acc, v)
                return acc + v
            end, spec.ret)
        end,
    }
end

function M.compile_count(spec)
    assert(type(spec) == "table", "compile_count spec must be a table")
    return M.compile_fold {
        name = assert(spec.name, "compile_count spec.name is required"),
        params = assert(spec.params, "compile_count spec.params is required"),
        ret = i32,
        init = 0,
        build = assert(spec.build, "compile_count spec.build is required"),
        reducer = function(acc, _v)
            return acc + i32(1)
        end,
    }
end

function M.compile_one(spec)
    assert(type(spec) == "table", "compile_one spec must be a table")
    assert(type(spec.name) == "string", "compile_one spec.name must be a string")
    assert(type(spec.params) == "table", "compile_one spec.params must be a table")
    assert(type(spec.build) == "function", "compile_one spec.build must be a function")
    assert(spec.ret ~= nil, "compile_one spec.ret is required")

    return func.fn {
        name = spec.name,
        params = spec.params,
        ret = spec.ret,
        body = function(...)
            local s = spec.build(...)
            assert(s and s.kind, "build must return a stream")
            return M.one(s, spec.default or 0)
        end,
    }
end

stream.Stream.lower = function(self, emit, ctx)
    return M.lower(self, emit, ctx)
end

stream.Stream.sum = function(self, init)
    return M.sum(self, init)
end

stream.Stream.count = function(self)
    return M.count(self)
end

stream.Stream.one = function(self, default)
    return M.one(self, default)
end

stream.Stream.drain_into = function(self, out_base)
    return M.drain_into(self, out_base)
end

stream.Stream.fold = function(self, init, reducer, ret_t)
    return M.fold(self, init, reducer, ret_t)
end

return M
