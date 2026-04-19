local Fragment = require("watjit.fragment")

local function op_name(t, op)
    local wat = assert(t.wat, "expression type is missing a WAT name")

    if t.kind == "simd" then
        local base = t.op_wat or wat
        if t.lane_type and t.lane_type.family == "int" and (op == "lt" or op == "le" or op == "gt" or op == "ge") then
            return base .. "." .. op .. "_s"
        end
        return base .. "." .. op
    end

    if op == "band" then
        return wat .. ".and"
    end
    if op == "bor" then
        return wat .. ".or"
    end
    if op == "bxor" then
        return wat .. ".xor"
    end
    if op == "shl" or op == "shr_u" or op == "shr_s" or op == "rotl" or op == "rotr" then
        return wat .. "." .. op
    end
    if op == "div_u" or op == "div_s" or op == "rem_u" or op == "rem_s"
        or op == "lt_u" or op == "le_u" or op == "gt_u" or op == "ge_u" then
        return wat .. "." .. op
    end

    if op == "div" then
        if wat == "i32" or wat == "i64" then
            return wat .. ".div_" .. ((t.signed == false) and "u" or "s")
        end
        return wat .. ".div"
    end

    if op == "rem" then
        if wat == "i32" or wat == "i64" then
            return wat .. ".rem_" .. ((t.signed == false) and "u" or "s")
        end
        return wat .. ".rem"
    end

    if op == "lt" or op == "le" or op == "gt" or op == "ge" then
        if wat == "i32" or wat == "i64" then
            return wat .. "." .. op .. "_" .. ((t.signed == false) and "u" or "s")
        end
        return wat .. "." .. op
    end

    return wat .. "." .. op
end

local function load_op_name(t)
    return t.load_op or (t.wat .. ".load")
end

local function store_op_name(t)
    return t.store_op or (t.wat .. ".store")
end

local emit_expr
local emit_stmt

function emit_expr(f, node)
    local op = node.op

    if op == "const" then
        f:write("(%s.const %s)", node.t.wat, tostring(node.value))
        return
    end

    if op == "vconst" then
        local parts = {}
        for i = 1, #node.lanes do
            local lane = node.lanes[i]
            if lane.op ~= "const" then
                error("v128.const lanes must be scalar const expressions", 2)
            end
            parts[i] = tostring(lane.value)
        end
        f:write("(v128.const %s %s)", node.t.op_wat or node.t.wat, table.concat(parts, " "))
        return
    end

    if op == "get" then
        f:write("(local.get $%s)", node.name)
        return
    end

    if op == "wat_unary" then
        f:open("(%s", node.wat_op)
        emit_expr(f, node.value)
        f:close()
        return
    end

    if op == "add" or op == "sub" or op == "mul" or op == "div" or op == "rem"
        or op == "div_u" or op == "div_s" or op == "rem_u" or op == "rem_s"
        or op == "band" or op == "bor" or op == "bxor"
        or op == "shl" or op == "shr_u" or op == "shr_s" or op == "rotl" or op == "rotr"
        or op == "lt" or op == "le" or op == "gt" or op == "ge"
        or op == "lt_u" or op == "le_u" or op == "gt_u" or op == "ge_u"
        or op == "eq" or op == "ne" then
        f:open("(%s", op_name(node.t, op))
        emit_expr(f, node.l)
        emit_expr(f, node.r)
        f:close()
        return
    end

    if op == "select" then
        f:open("(select")
        emit_expr(f, node.then_)
        emit_expr(f, node.else_)
        emit_expr(f, node.cond)
        f:close()
        return
    end

    if op == "load" then
        f:open("(%s", load_op_name(node.t))
        emit_expr(f, node.ptr)
        f:close()
        return
    end

    if op == "vload" then
        f:open("(v128.load")
        emit_expr(f, node.ptr)
        f:close()
        return
    end

    if op == "splat" then
        f:open("(%s.splat", node.t.op_wat or node.t.wat)
        emit_expr(f, node.value)
        f:close()
        return
    end

    if op == "extract_lane" then
        f:open("(%s.extract_lane %d", node.vec_t.op_wat or node.vec_t.wat, node.lane)
        emit_expr(f, node.value)
        f:close()
        return
    end

    if op == "replace_lane" then
        f:open("(%s.replace_lane %d", node.t.op_wat or node.t.wat, node.lane)
        emit_expr(f, node.value)
        emit_expr(f, node.scalar)
        f:close()
        return
    end

    if op == "call" then
        f:open("(call $%s", node.name)
        for i = 1, #node.args do
            emit_expr(f, node.args[i])
        end
        f:close()
        return
    end

    if op == "vbitselect" then
        f:open("(v128.bitselect")
        emit_expr(f, node.then_)
        emit_expr(f, node.else_)
        emit_expr(f, node.mask)
        f:close()
        return
    end

    if op == "shuffle" then
        f:open("(i8x16.shuffle %s", table.concat(node.lanes, " "))
        emit_expr(f, node.l)
        emit_expr(f, node.r)
        f:close()
        return
    end

    if op == "eqz" then
        f:open("(%s.eqz", node.t.wat)
        emit_expr(f, node.val)
        f:close()
        return
    end

    error("unknown expression op: " .. tostring(op), 2)
end

function emit_stmt(f, node)
    local op = node.op

    if op == "set" then
        f:open("(local.set $%s", node.name)
        emit_expr(f, node.value)
        f:close()
        return
    end

    if op == "store" then
        f:open("(%s", store_op_name(node.t))
        emit_expr(f, node.ptr)
        emit_expr(f, node.value)
        f:close()
        return
    end

    if op == "vstore" then
        f:open("(v128.store")
        emit_expr(f, node.ptr)
        emit_expr(f, node.value)
        f:close()
        return
    end

    if op == "call" then
        f:open("(call $%s", node.name)
        for i = 1, #node.args do
            emit_expr(f, node.args[i])
        end
        f:close()
        return
    end

    if op == "block" or op == "loop" then
        f:open("(%s %s", op, node.label)
        for i = 1, #node.body do
            emit_stmt(f, node.body[i])
        end
        f:close()
        return
    end

    if op == "br" then
        f:write("(br %s)", node.label)
        return
    end

    if op == "br_if" then
        f:open("(br_if %s", node.label)
        emit_expr(f, node.cond)
        f:close()
        return
    end

    if op == "if" then
        f:open("(if")
        emit_expr(f, node.cond)
        f:open("(then")
        for i = 1, #node.then_ do
            emit_stmt(f, node.then_[i])
        end
        f:close()
        if #node.else_ > 0 then
            f:open("(else")
            for i = 1, #node.else_ do
                emit_stmt(f, node.else_[i])
            end
            f:close()
        end
        f:close()
        return
    end

    if op == "return" then
        f:open("(return")
        emit_expr(f, node.value)
        f:close()
        return
    end

    error("unknown statement op: " .. tostring(op), 2)
end

local function emit_import(f, fn)
    f:open('(import "%s" "%s"', fn.import_module, fn.import_name)
    f:open('(func $%s', fn.name)
    for i = 1, #fn.params do
        local p = fn.params[i]
        f:write("(param %s)", p.t.wat)
    end
    if fn.ret and fn.ret.wat then
        f:write("(result %s)", fn.ret.wat)
    end
    f:close()
    f:close()
end

local function emit_func(f, fn)
    f:open('(func $%s (export "%s")', fn.name, fn.name)
    for i = 1, #fn.params do
        local p = fn.params[i]
        f:write("(param $%s %s)", p.name, p.t.wat)
    end
    if fn.ret and fn.ret.wat then
        f:write("(result %s)", fn.ret.wat)
    end
    for i = 1, #fn.locals do
        local local_ = fn.locals[i]
        f:write("(local $%s %s)", local_.name, local_.t.wat)
    end
    for i = 1, #fn.body do
        emit_stmt(f, fn.body[i])
    end
    f:close()
end

local function emit_module(mod)
    local f = Fragment()
    local memory_pages = mod.memory_pages or 1
    local memory_export = mod.memory_export or "memory"

    f:open("(module")
    for i = 1, #(mod.imports or {}) do
        emit_import(f, mod.imports[i])
    end
    if mod.memory_max_pages ~= nil then
        f:write('(memory (export "%s") %d %d)', memory_export, memory_pages, mod.memory_max_pages)
    else
        f:write('(memory (export "%s") %d)', memory_export, memory_pages)
    end
    for i = 1, #mod.funcs do
        emit_func(f, mod.funcs[i])
    end
    f:close()
    return tostring(f)
end

return {
    expr = emit_expr,
    stmt = emit_stmt,
    import = emit_import,
    func = emit_func,
    module = emit_module,
}
