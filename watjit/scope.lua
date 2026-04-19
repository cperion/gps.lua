local Scope = {}
local stack = {}
local next_id = 0

local function sanitize_hint(hint)
    hint = tostring(hint or "tmp")
    hint = hint:gsub("^%$+", "")
    hint = hint:gsub("[^%w_]", "_")
    if hint == "" then
        hint = "tmp"
    end
    return hint
end

function Scope.push(parent)
    local root = parent and parent.root or nil
    local scope = setmetatable({
        stmts = {},
        locals = root and root.locals or {},
        declared = root and root.declared or {},
        root = nil,
    }, { __index = Scope })
    scope.root = root or scope
    stack[#stack + 1] = scope
    return scope
end

function Scope.pop()
    return table.remove(stack)
end

function Scope.current()
    return stack[#stack]
end

function Scope.capture(fn)
    local scope = Scope.push(Scope.current())
    local ret = fn()
    Scope.pop()
    return scope, ret
end

function Scope:push_stmt(stmt)
    self.stmts[#self.stmts + 1] = stmt
end

function Scope:fresh_name(hint)
    next_id = next_id + 1
    return ("%s_%d"):format(sanitize_hint(hint), next_id)
end

function Scope:declare(name, t)
    local root = self.root
    if root.declared[name] then
        return
    end
    root.declared[name] = true
    root.locals[#root.locals + 1] = { name = name, t = t }
end

function Scope:declare_fresh(hint, t)
    local name = self:fresh_name(hint)
    self:declare(name, t)
    return name
end

function Scope:assign(name, value)
    self:push_stmt({
        op = "set",
        name = name,
        value = value.expr,
    })
end

return Scope
