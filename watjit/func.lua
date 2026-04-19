local Scope = require("watjit.scope")
local emit = require("watjit.emit")
local types = require("watjit.types")
local quote = require("watjit.quote")

local coerce = types.coerce
local void = types.void
local FunctionMT = {}

local function normalize_param_list(params)
    local param_list = {}
    for i = 1, #params do
        local p = params[i]
        param_list[i] = { name = p.name, t = p.t }
    end
    return param_list
end

local function build_call(self, ...)
    local argc = select("#", ...)
    if argc ~= #self.params then
        error(
            string.format("function '%s' expects %d arguments, got %d", self.name, #self.params, argc),
            3
        )
    end

    local args = {}
    for i = 1, #self.params do
        args[i] = coerce(select(i, ...), self.params[i].t).expr
    end

    if self.ret ~= void then
        return types.Val.new({
            op = "call",
            name = self.name,
            args = args,
            t = self.ret,
        }, self.ret)
    end

    local scope = Scope.current()
    if not scope then
        error("void function call outside of a watjit scope", 2)
    end
    scope:push_stmt({
        op = "call",
        name = self.name,
        args = args,
    })
    return nil
end

FunctionMT.__index = FunctionMT
FunctionMT.__call = function(self, ...)
    return build_call(self, ...)
end

function FunctionMT:inline_call(...)
    if self._inline == nil then
        error(("function '%s' has no inline quote available"):format(self.name or "?"), 2)
    end
    return self._inline(...)
end

local function unwrap_body(body)
    if type(body) ~= "function" then
        error("function body must be a function", 3)
    end
    return body
end

local function func(name)
    return function(...)
        local params = { ... }
        local ret_type = void
        local builder = {}

        function builder:returns(t)
            ret_type = t
            return self
        end

        return setmetatable(builder, {
            __call = function(_, body)
                local body_fn = unwrap_body(body)
                local scope = Scope.push()
                local ret = body_fn(table.unpack(params))
                Scope.pop()

                if ret ~= nil then
                    if ret_type == void then
                        error("void function returned a value", 2)
                    end
                    scope:push_stmt({
                        op = "return",
                        value = coerce(ret, ret_type).expr,
                    })
                end

                return setmetatable({
                    op = "func",
                    name = name,
                    params = normalize_param_list(params),
                    locals = scope.locals,
                    ret = ret_type,
                    body = scope.stmts,
                }, FunctionMT)
            end,
        })
    end
end

local function import(spec)
    assert(type(spec) == "table", "import spec must be a table")
    assert(type(spec.module) == "string", "import spec.module must be a string")
    assert(type(spec.name) == "string", "import spec.name must be a string")
    assert(type(spec.params) == "table", "import spec.params must be a table")

    local ret = spec.ret or spec.returns or void
    return setmetatable({
        op = "import",
        import_module = spec.module,
        import_name = spec.name,
        name = spec.as or spec.alias or spec.name,
        params = normalize_param_list(spec.params),
        ret = ret,
    }, FunctionMT)
end

local function fn(spec)
    assert(type(spec) == "table", "fn spec must be a table")
    assert(type(spec.name) == "string", "fn spec.name must be a string")
    assert(type(spec.params) == "table", "fn spec.params must be a table")
    assert(type(spec.body) == "function", "fn spec.body must be a function")

    local builder = func(spec.name)(table.unpack(spec.params, 1, #spec.params))
    local ret = spec.ret or spec.returns
    if ret ~= nil then
        builder:returns(ret)
    end
    local out = builder(spec.body)
    if spec.no_inline ~= true then
        if ret ~= nil and ret ~= void then
            out._inline = quote.quote_expr {
                params = spec.params,
                ret = ret,
                body = spec.body,
            }
        else
            out._inline = quote.quote_block {
                params = spec.params,
                body = spec.body,
            }
        end
    end
    return out
end

local function module(funcs, opts)
    opts = opts or {}

    local mod = {
        funcs = {},
        imports = {},
        memory_pages = opts.memory_pages or 1,
        memory_max_pages = opts.memory_max_pages,
        memory_export = opts.memory_export or "memory",
    }

    function mod:add(fn_obj)
        if fn_obj.op == "import" then
            self.imports[#self.imports + 1] = fn_obj
        else
            self.funcs[#self.funcs + 1] = fn_obj
        end
        return self
    end

    if funcs then
        for i = 1, #funcs do
            mod:add(funcs[i])
        end
    end

    function mod:wat()
        return emit.module(self)
    end

    function mod:compile(engine, opts2)
        local wasmtime = require("watjit.wasmtime")
        return wasmtime.instantiate(engine, wasmtime.compile(engine, self:wat()), self.imports, opts2 and opts2.imports)
    end

    return mod
end

return {
    func = func,
    fn = fn,
    import = import,
    module = module,
    PAGE_SIZE = 65536,
    pages_for_bytes = function(bytes)
        return math.max(1, math.ceil(bytes / 65536))
    end,
}
