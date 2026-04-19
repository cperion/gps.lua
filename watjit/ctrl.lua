local Scope = require("watjit.scope")
local types = require("watjit.types")

local i32 = types.i32
local coerce = types.coerce
local Val = types.Val

local next_label = 0
local LabelMT = {}

local function fresh(prefix)
    next_label = next_label + 1
    return ("$%s_%d"):format(prefix, next_label)
end

local function new_label(prefix, explicit_name)
    local name
    if explicit_name ~= nil then
        assert(type(explicit_name) == "string", "label name must be a string")
        if explicit_name:sub(1, 1) == "$" then
            name = explicit_name
        else
            name = fresh(explicit_name)
        end
    else
        name = fresh(prefix)
    end
    return setmetatable({ kind = "label", name = name }, LabelMT)
end

local function as_label(label, prefix)
    if label == nil then
        return new_label(prefix)
    end
    if getmetatable(label) == LabelMT then
        return label
    end
    if type(label) == "string" then
        return new_label(prefix or label, label)
    end
    error("expected a label or label name", 3)
end

local function append_all(dst, src)
    for i = 1, #src do
        dst[#dst + 1] = src[i]
    end
    return dst
end

local function push_stmt(stmt)
    local scope = Scope.current()
    if not scope then
        error("control operation outside of a watjit scope", 3)
    end
    scope:push_stmt(stmt)
end

local function br(label)
    local resolved = as_label(label, "label")
    push_stmt({
        op = "br",
        label = resolved.name,
    })
end

local function br_if(label, cond)
    local resolved = as_label(label, "label")
    push_stmt({
        op = "br_if",
        label = resolved.name,
        cond = coerce(cond, i32).expr,
    })
end

local function make_ctrl(labels)
    return {
        break_label = labels.break_label,
        continue_label = labels.continue_label,
        break_ = function(self)
            local label = self.break_label
            if label == nil then
                error("break_ used without a break label", 2)
            end
            br(label)
        end,
        continue_ = function(self)
            local label = self.continue_label
            if label == nil then
                error("continue_ used without a continue label", 2)
            end
            br(label)
        end,
        br = function(self, label)
            br(label)
        end,
        br_if = function(self, label, cond)
            br_if(label, cond)
        end,
        ["goto"] = function(self, label)
            br(label)
        end,
    }
end

local function capture_block(body, ctrl)
    if type(body) ~= "function" then
        error("control-flow body must be a function", 3)
    end
    local scope, ret = Scope.capture(function()
        return body(ctrl)
    end)
    if ret ~= nil then
        error("control-flow body must not return a value", 3)
    end
    return scope.stmts
end

local function block(label_or_body, maybe_body)
    local label, body
    if type(label_or_body) == "function" then
        label = new_label("block")
        body = label_or_body
    else
        label = as_label(label_or_body, "block")
        body = maybe_body
    end
    if type(body) ~= "function" then
        error("block requires a body function", 2)
    end
    push_stmt({
        op = "block",
        label = label.name,
        body = capture_block(body, make_ctrl { break_label = label }),
    })
    return label
end

local function loop(label_or_body, maybe_body)
    local loop_label, body
    if type(label_or_body) == "function" then
        loop_label = new_label("loop")
        body = label_or_body
    else
        loop_label = as_label(label_or_body, "loop")
        body = maybe_body
    end
    if type(body) ~= "function" then
        error("loop requires a body function", 2)
    end
    local break_label = new_label("break")
    local continue_label = new_label("continue")
    local ctrl = make_ctrl {
        break_label = break_label,
        continue_label = continue_label,
    }
    push_stmt({
        op = "block",
        label = break_label.name,
        body = {
            {
                op = "loop",
                label = loop_label.name,
                body = {
                    {
                        op = "block",
                        label = continue_label.name,
                        body = capture_block(body, ctrl),
                    },
                    {
                        op = "br",
                        label = loop_label.name,
                    },
                },
            },
        },
    })
    return loop_label
end

local function for_(var, from_or_to, maybe_to, maybe_step, body)
    local from, to, step

    if type(maybe_to) == "function" then
        from = var.t(0)
        to = from_or_to
        step = var.t(1)
        body = maybe_to
    elseif type(maybe_step) == "function" then
        from = from_or_to
        to = maybe_to
        step = var.t(1)
        body = maybe_step
    else
        from = from_or_to
        to = maybe_to
        step = maybe_step or var.t(1)
    end

    local scope = Scope.current()
    if not scope then
        error("for_ outside of a watjit scope", 2)
    end
    if var.name == nil then
        error("for_ loop variable must be a named local", 2)
    end
    if type(body) ~= "function" then
        error("for_ requires a body function", 2)
    end

    local break_label = new_label("break")
    local loop_label = new_label("loop")
    local continue_label = new_label("continue")
    local ctrl = make_ctrl {
        break_label = break_label,
        continue_label = continue_label,
    }
    local cond = var:lt(to)
    local next_value = var + step

    scope:push_stmt({
        op = "block",
        label = break_label.name,
        body = {
            {
                op = "set",
                name = var.name,
                value = coerce(from, var.t).expr,
            },
            {
                op = "loop",
                label = loop_label.name,
                body = append_all({
                    {
                        op = "br_if",
                        label = break_label.name,
                        cond = {
                            op = "eqz",
                            t = i32,
                            val = cond.expr,
                        },
                    },
                    {
                        op = "block",
                        label = continue_label.name,
                        body = capture_block(body, ctrl),
                    },
                    {
                        op = "set",
                        name = var.name,
                        value = next_value.expr,
                    },
                    {
                        op = "br",
                        label = loop_label.name,
                    },
                }, {}),
            },
        },
    })
end

local function while_(cond, body)
    local scope = Scope.current()
    if not scope then
        error("while_ outside of a watjit scope", 2)
    end
    if type(body) ~= "function" then
        error("while_ requires a body function", 2)
    end

    local break_label = new_label("break")
    local loop_label = new_label("loop")
    local continue_label = new_label("continue")
    local ctrl = make_ctrl {
        break_label = break_label,
        continue_label = continue_label,
    }
    local cond_val = coerce(cond, i32)

    scope:push_stmt({
        op = "block",
        label = break_label.name,
        body = {
            {
                op = "loop",
                label = loop_label.name,
                body = {
                    {
                        op = "br_if",
                        label = break_label.name,
                        cond = {
                            op = "eqz",
                            t = i32,
                            val = cond_val.expr,
                        },
                    },
                    {
                        op = "block",
                        label = continue_label.name,
                        body = capture_block(body, ctrl),
                    },
                    {
                        op = "br",
                        label = loop_label.name,
                    },
                },
            },
        },
    })
end

local function if_(cond, then_body, else_body)
    local scope = Scope.current()
    if not scope then
        error("if_ outside of a watjit scope", 2)
    end
    if type(then_body) ~= "function" then
        error("if_ requires a then-body function", 2)
    end
    if else_body ~= nil and type(else_body) ~= "function" then
        error("if_ else-body must be a function", 2)
    end

    local stmt = {
        op = "if",
        cond = coerce(cond, i32).expr,
        then_ = capture_block(then_body),
        else_ = else_body and capture_block(else_body) or {},
    }
    scope:push_stmt(stmt)
    return stmt
end

local function normalize_switch_cases(cases)
    assert(type(cases) == "table", "switch cases must be a table")
    local entries = {}
    for key, body in pairs(cases) do
        assert(type(body) == "function", "switch case body must be a function")
        local sort_value = key
        if Val.is(key) then
            assert(key.expr and key.expr.op == "const", "switch case keys must be numeric literals or const watjit values")
            sort_value = key.expr.value
        else
            assert(type(key) == "number", "switch case keys must be numeric literals or const watjit values")
        end
        entries[#entries + 1] = {
            key = key,
            sort_value = sort_value,
            body = body,
        }
    end
    table.sort(entries, function(a, b)
        return a.sort_value < b.sort_value
    end)
    return entries
end

local function build_switch_stmts(tag, entries, index, default)
    if index > #entries then
        return default and capture_block(default) or {}
    end
    local entry = entries[index]
    return {
        {
            op = "if",
            cond = tag:eq(entry.key).expr,
            then_ = capture_block(entry.body),
            else_ = build_switch_stmts(tag, entries, index + 1, default),
        },
    }
end

local function switch(tag, cases, default)
    local scope = Scope.current()
    if not scope then
        error("switch outside of a watjit scope", 2)
    end
    assert(Val.is(tag), "switch tag must be a watjit value")
    if default ~= nil and type(default) ~= "function" then
        error("switch default must be a function", 2)
    end

    local entries = normalize_switch_cases(cases)
    local stmts = build_switch_stmts(tag, entries, 1, default)
    for i = 1, #stmts do
        scope:push_stmt(stmts[i])
    end
    return stmts[1]
end

return {
    label = function(name)
        return new_label(name or "label", name)
    end,
    block = block,
    loop = loop,
    br = br,
    br_if = br_if,
    goto_ = br,
    for_ = for_,
    while_ = while_,
    if_ = if_,
    switch = switch,
}
