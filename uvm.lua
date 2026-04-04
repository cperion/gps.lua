-- uvm.lua — tiny machine DSL + structural compiler
--
-- Public surface:
--   uvm.stream / uvm.runner / uvm.dispatch
--   fam:chain / :guard / :limit / :fuse
--   fam:compile() -> compiled family
--   fam:spawn(...) -> machine
--   machine:run(...)
--
-- Semantic core:
--   gen, param, state
--
--     param = immutable program / configuration
--     state = mutable machine store
--     gen   = one-step semantics
--
-- Internal pipeline:
--   composition IR  -> analysis -> lowered plan -> flat slot layout
--   -> generated init/patch/shared exec bundle -> compiled family
--
-- UVM keeps both:
--   * an interpreted reference path over explicit composition IR
--   * a compiled flat-state path for hot execution

local pvm = require("pvm")
local Quote = require("quote")
local uvm = setmetatable({}, { __index = pvm })

local unpack = table.unpack or unpack

local function check_table(x, name)
    if type(x) ~= "table" then error((name or "value") .. " must be a table", 3) end
    return x
end
local function check_fn(x, name)
    if type(x) ~= "function" then error((name or "value") .. " must be a function", 3) end
    return x
end
local function shallow_copy(t)
    local out = {}; if t then for k,v in pairs(t) do out[k]=v end end; return out
end
local function default_init(_p, seed) return seed end
local function default_patch(_op, _np, old_state) return old_state end
local function default_shape_key(parts) return parts and parts.shape_key or nil end
local function default_payload_key(parts) return parts and parts.payload_key or nil end
local function default_patchable() return true end
local function default_disasm(param) return "<image " .. tostring(param) .. ">" end

-- ══════════════════════════════════════════════════════════════
--  STATUS PROTOCOL
-- ══════════════════════════════════════════════════════════════

uvm.status = { RUN=1, YIELD=2, TRAP=3, HALT=4 }
local S = uvm.status

local STATUS_NAME = {
    [1]="RUN", [2]="YIELD", [3]="TRAP", [4]="HALT",
}
uvm.status_name = STATUS_NAME

function uvm.status_name_of(code)
    return STATUS_NAME[code] or ("UNKNOWN("..tostring(code)..")")
end

local function status_set(...)
    local out = {}
    for i = 1, select("#", ...) do out[select(i, ...)] = true end
    return out
end

local function status_set_copy(src)
    local out = {}
    if src then for k, v in pairs(src) do if v then out[k] = true end end end
    return out
end

local function status_set_union(a, b)
    local out = status_set_copy(a)
    if b then for k, v in pairs(b) do if v then out[k] = true end end end
    return out
end

local function status_set_list(src)
    local out = {}
    if src then for k, v in pairs(src) do if v then out[#out + 1] = STATUS_NAME[k] or tostring(k) end end end
    table.sort(out)
    return out
end

-- ══════════════════════════════════════════════════════════════
--  FAMILY / IMAGE / MACHINE
-- ══════════════════════════════════════════════════════════════

local family_mt = {}; family_mt.__index = family_mt
local image_mt = {};  image_mt.__index = image_mt
local machine_mt = {}; machine_mt.__index = machine_mt

function uvm.family(spec)
    check_table(spec, "family spec"); check_fn(spec.step, "family.step")
    local meta = spec.meta or {}
    return setmetatable({
        name = spec.name or "uvm.family",
        step_fn = spec.step,
        init_fn = spec.init or default_init,
        patch_fn = spec.patch or default_patch,
        patchable_fn = spec.patchable or default_patchable,
        shape_key_fn = spec.shape_key or default_shape_key,
        payload_key_fn = spec.payload_key or default_payload_key,
        disasm_fn = spec.disasm or default_disasm,
        meta = meta,
        family_kind = spec.family_kind or "leaf",
        ir = spec.ir,
        status_set = status_set_copy(spec.statuses or meta.statuses),
        codegen = spec.codegen or meta.codegen,
    }, family_mt)
end

function family_mt:__tostring() return "<uvm.family " .. self.name .. ">" end
function family_mt:init(p, seed) return self.init_fn(p, seed) end
function family_mt:patch(op, np, os) return self.patch_fn(op, np, os) end
function family_mt:patchable(p, s) return self.patchable_fn(p, s) end
function family_mt:shape_key(parts) return self.shape_key_fn(parts) end
function family_mt:payload_key(parts) return self.payload_key_fn(parts) end
function family_mt:disasm(p) return self.disasm_fn(p) end
function family_mt:statuses() return status_set_copy(self.status_set) end
function family_mt:codegen_info() return self.codegen end
function family_mt:ir_node()
    if uvm.comp then return uvm.comp.ir(self) end
    return self.ir
end
function family_mt:describe()
    if uvm.comp and self.ir then return uvm.comp.describe(self.ir) end
    return "leaf(" .. self.name .. ")"
end
function family_mt:compile(opts)
    if uvm.comp then return uvm.comp.compile(self, opts) end
    return self
end
function family_mt:chain(other, opts) return uvm.chain(self, other, opts) end
function family_mt:guard(pred, opts) return uvm.guard(self, pred, opts) end
function family_mt:limit(n, opts) return uvm.limit(self, n, opts) end
function family_mt:fuse(exec_step, opts) return uvm.fuse(self, exec_step, opts) end
function family_mt:run(param_or_img, seed, budget)
    return self:spawn(param_or_img, seed):run(budget)
end

function family_mt:image(parts)
    parts = check_table(parts or {}, "image parts")
    return setmetatable({
        family=self, parts=parts,
        shape_key=self:shape_key(parts), payload_key=self:payload_key(parts),
    }, image_mt)
end

function family_mt:spawn(img_or_param, seed)
    local param = getmetatable(img_or_param)==image_mt and img_or_param.parts or img_or_param
    return setmetatable({
        family=self, gen=self.step_fn, param=param,
        state=self:init(param, seed), halted=false, last_status=nil,
    }, machine_mt)
end

function family_mt:resume(img_or_param, token)
    check_table(token, "resume token")
    local param = getmetatable(img_or_param)==image_mt and img_or_param.parts or img_or_param
    return setmetatable({
        family=self, gen=self.step_fn, param=param,
        state=token.state, halted=token.halted or false, last_status=token.last_status,
    }, machine_mt)
end

-- Image
function image_mt:__tostring()
    return string.format("<uvm.image family=%s shape=%s>", self.family.name, tostring(self.shape_key))
end
function image_mt:clone(overrides)
    local parts = shallow_copy(self.parts)
    if overrides then for k,v in pairs(overrides) do parts[k]=v end end
    return self.family:image(parts)
end

-- Machine
function uvm.machine(fam, img, seed) return fam:spawn(img, seed) end

function machine_mt:__tostring()
    return string.format("<uvm.machine family=%s status=%s>", self.family.name, uvm.status_name_of(self.last_status))
end
function machine_mt:triplet() return self.gen, self.param, self.state end
function machine_mt:is_halted() return self.halted end
function machine_mt:status() return self.last_status end
function machine_mt:patchable() return self.family:patchable(self.param, self.state) end
function machine_mt:snapshot()
    return { family_name=self.family.name, state=self.state, halted=self.halted, last_status=self.last_status }
end

function machine_mt:step()
    if self.halted then self.last_status=S.HALT; return S.HALT end
    local ns, status, a, b, c, d = self.gen(self.param, self.state)
    if status == nil then error("family step returned nil status", 2) end
    self.state = ns; self.last_status = status
    if status == S.HALT or ns == nil then
        self.halted=true; self.last_status=S.HALT; return S.HALT, a, b, c, d
    end
    return status, a, b, c, d
end

function machine_mt:run(budget)
    budget = budget or math.huge
    if (not self.halted) and self.family.run_fn then
        local ns, status, a, b, c, d, steps = self.family.run_fn(self.param, self.state, budget)
        if status == nil then error("family run returned nil status", 2) end
        self.state = ns
        self.last_status = status
        if status == S.HALT or ns == nil then
            self.halted = true
            self.last_status = S.HALT
            return S.HALT, a, b, c, d, steps
        end
        return status, a, b, c, d, steps
    end
    local steps = 0
    while steps < budget do
        local status, a, b, c, d = self:step(); steps = steps + 1
        if status ~= S.RUN then return status, a, b, c, d, steps end
    end
    return S.RUN, nil, nil, nil, nil, steps
end

function machine_mt:reimage(img_or_param, patch_fn)
    local new_param = getmetatable(img_or_param)==image_mt and img_or_param.parts or img_or_param
    local new_state = (patch_fn or self.family.patch_fn)(self.param, new_param, self.state)
    return setmetatable({
        family=self.family, gen=self.family.step_fn, param=new_param,
        state=new_state, halted=false, last_status=self.last_status,
    }, machine_mt)
end

function machine_mt:refamily(new_fam, img_or_param, patch_fn)
    local new_param = getmetatable(img_or_param)==image_mt and img_or_param.parts or img_or_param
    local new_state = (patch_fn or new_fam.patch_fn or default_patch)(self.param, new_param, self.state)
    return setmetatable({
        family=new_fam, gen=new_fam.step_fn, param=new_param,
        state=new_state, halted=false, last_status=self.last_status,
    }, machine_mt)
end

function machine_mt:disasm() return self.family:disasm(self.param) end

-- ══════════════════════════════════════════════════════════════
--  FAMILY BUILDERS
-- ══════════════════════════════════════════════════════════════

uvm.families = {}

function uvm.families.stream(name, step_stream, opts)
    opts = opts or {}; check_fn(step_stream, "step_stream")
    return uvm.family({
        name=name or "stream", init=opts.init or default_init,
        patch=opts.patch or default_patch, disasm=opts.disasm or default_disasm,
        statuses = opts.statuses or status_set(S.YIELD, S.HALT),
        step = function(param, state)
            local ns, a, b, c, d = step_stream(param, state)
            if ns == nil then return nil, S.HALT, a, b, c, d end
            return ns, S.YIELD, a, b, c, d
        end,
    })
end

function uvm.families.runner(name, step_runner, opts)
    opts = opts or {}; check_fn(step_runner, "step_runner")
    return uvm.family({
        name=name or "runner", init=opts.init or default_init,
        patch=opts.patch or default_patch, disasm=opts.disasm or default_disasm,
        statuses = opts.statuses or status_set(S.RUN, S.YIELD, S.TRAP, S.HALT),
        step=step_runner,
    })
end

-- ══════════════════════════════════════════════════════════════
--  COMPOSITION ALGEBRA / IR
-- ══════════════════════════════════════════════════════════════

uvm.op = {}
uvm.comp = {}

local function fallback_ucomp_context()
    local function key_of(v)
        local tv = type(v)
        if tv == "table" then
            local mt = getmetatable(v)
            if mt == family_mt then return "family:" .. tostring(v.name) end
            if mt and mt.__fields then
                local parts = {}
                for i = 1, #mt.__fields do
                    local name = mt.__fields[i].name
                    parts[i] = name .. "=" .. key_of(v[name])
                end
                return (mt.kind or tostring(mt)) .. "(" .. table.concat(parts, ",") .. ")"
            end
            local parts = {}
            for i = 1, #v do parts[i] = key_of(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        return tv .. ":" .. tostring(v)
    end

    local function make_ctor(kind, field_names, opts)
        opts = opts or {}
        local class = { kind = kind, __fields = {} }
        for i = 1, #field_names do class.__fields[i] = { name = field_names[i] } end
        local cache = opts.unique and {} or nil
        local singleton = nil
        local function build(self, ...)
            local args = { ... }
            if cache then
                local ks = {}
                for i = 1, #field_names do ks[i] = key_of(args[i]) end
                local key = table.concat(ks, "|")
                local hit = cache[key]
                if hit then return hit end
                local obj = setmetatable({}, self)
                for i = 1, #field_names do obj[field_names[i]] = args[i] end
                cache[key] = obj
                return obj
            else
                local obj = setmetatable({}, self)
                for i = 1, #field_names do obj[field_names[i]] = args[i] end
                return obj
            end
        end
        local mt = {
            __index = class,
            __call = function(self, ...)
                local n = select("#", ...)
                if #field_names == 0 and n == 0 then return singleton end
                return build(self, ...)
            end,
            __tostring = function(self) return kind end,
        }
        setmetatable(class, mt)
        function class:__tostring() return kind end
        if #field_names == 0 then
            singleton = setmetatable({}, class)
            return singleton
        end
        return class
    end

    local UComp = {}
    UComp.FamilyRef = make_ctor("UComp.FamilyRef", { "name", "family" }, { unique = true })
    UComp.OpaqueShape = make_ctor("UComp.OpaqueShape", { "value" }, { unique = true })
    UComp.NoShape = make_ctor("UComp.NoShape", {}, { unique = true })
    UComp.OpaquePayload = make_ctor("UComp.OpaquePayload", { "value" }, { unique = true })
    UComp.NoPayload = make_ctor("UComp.NoPayload", {}, { unique = true })
    UComp.PredicateGuard = make_ctor("UComp.PredicateGuard", { "fn" }, { unique = true })
    UComp.AlwaysGuard = make_ctor("UComp.AlwaysGuard", {}, { unique = true })
    UComp.NeverGuard = make_ctor("UComp.NeverGuard", {}, { unique = true })
    UComp.Not = make_ctor("UComp.Not", { "inner" }, { unique = true })
    UComp.And = make_ctor("UComp.And", { "left", "right" }, { unique = true })
    UComp.Or = make_ctor("UComp.Or", { "left", "right" }, { unique = true })
    UComp.OpaqueExec = make_ctor("UComp.OpaqueExec", { "fn" }, { unique = true })
    UComp.ChainChild = make_ctor("UComp.ChainChild", { "path", "node" }, { unique = true })
    UComp.Leaf = make_ctor("UComp.Leaf", { "family", "shape", "payload" }, { unique = true })
    UComp.Chain = make_ctor("UComp.Chain", { "left", "right" }, { unique = true })
    UComp.ChainSeq = make_ctor("UComp.ChainSeq", { "children" }, { unique = true })
    UComp.Guard = make_ctor("UComp.Guard", { "inner", "guard" }, { unique = true })
    UComp.Limit = make_ctor("UComp.Limit", { "inner", "max_steps" }, { unique = true })
    UComp.Fuse = make_ctor("UComp.Fuse", { "inner", "exec" }, { unique = true })
    return { UComp = UComp }
end

local ok_ctx, U = pcall(function()
    return pvm.context():Define [[
module UComp {
    FamilyRef = (string name,
                 table family) unique

    Shape = OpaqueShape(table value) unique
          | NoShape

    Payload = OpaquePayload(table value) unique
            | NoPayload

    GuardSpec = PredicateGuard(function fn) unique
              | AlwaysGuard
              | NeverGuard
              | Not(UComp.GuardSpec inner) unique
              | And(UComp.GuardSpec left,
                    UComp.GuardSpec right) unique
              | Or(UComp.GuardSpec left,
                   UComp.GuardSpec right) unique

    ExecSpec = OpaqueExec(function fn) unique

    ChainChild = (string* path,
                  UComp.Node node) unique

    Node = Leaf(UComp.FamilyRef family,
                UComp.Shape shape,
                UComp.Payload payload) unique
         | Chain(UComp.Node left,
                 UComp.Node right) unique
         | ChainSeq(UComp.ChainChild* children) unique
         | Guard(UComp.Node inner,
                 UComp.GuardSpec guard) unique
         | Limit(UComp.Node inner,
                 number max_steps) unique
         | Fuse(UComp.Node inner,
                UComp.ExecSpec exec) unique
}
]]
end)
if not ok_ctx then U = fallback_ucomp_context() end

uvm.comp.types = U.UComp

local FamilyRef = U.UComp.FamilyRef
local OpaqueShape = U.UComp.OpaqueShape
local NoShape = U.UComp.NoShape
local OpaquePayload = U.UComp.OpaquePayload
local NoPayload = U.UComp.NoPayload
local PredicateGuard = U.UComp.PredicateGuard
local AlwaysGuard = U.UComp.AlwaysGuard
local NeverGuard = U.UComp.NeverGuard
local GuardNot = U.UComp.Not
local GuardAnd = U.UComp.And
local GuardOr = U.UComp.Or
local OpaqueExec = U.UComp.OpaqueExec
local ChainChild = U.UComp.ChainChild
local Leaf = U.UComp.Leaf
local Chain = U.UComp.Chain
local ChainSeq = U.UComp.ChainSeq
local Guard = U.UComp.Guard
local Limit = U.UComp.Limit
local Fuse = U.UComp.Fuse

local function is_ir_node(x)
    local mt = getmetatable(x)
    return mt == Leaf or mt == Chain or mt == ChainSeq or mt == Guard or mt == Limit or mt == Fuse
end

local function copy_path(path)
    local out = {}
    for i = 1, #path do out[i] = path[i] end
    return out
end

local function append_path(path, key)
    local out = copy_path(path)
    out[#out + 1] = key
    return out
end

local function path_value(root, path)
    local value = root
    for i = 1, #path do
        if value == nil then return nil end
        value = value[path[i]]
    end
    return value
end

local function path_expr(root_expr, path)
    local expr = root_expr
    for i = 1, #path do expr = expr .. "." .. path[i] end
    return expr
end

local function comp_tag_name(x)
    local mt = is_ir_node(x) and getmetatable(x) or x
    if mt == Leaf then return "leaf" end
    if mt == Chain then return "chain" end
    if mt == ChainSeq then return "chain_seq" end
    if mt == Guard then return "guard" end
    if mt == Limit then return "limit" end
    if mt == Fuse then return "fuse" end
    return tostring(mt and mt.kind or mt)
end

local function leaf_family(node)
    return node.family.family
end

local function leaf_node(fam)
    return Leaf(FamilyRef(fam.name, fam), NoShape, NoPayload)
end

local function node_name(node)
    local mt = getmetatable(node)
    if mt == Leaf then return node.family.name end
    if mt == Limit then return node_name(node.inner) .. ".limit(" .. tostring(node.max_steps) .. ")" end
    if mt == Guard then return node_name(node.inner) .. ".guard" end
    if mt == Fuse then return node_name(node.inner) .. ".fused" end
    if mt == Chain then return node_name(node.left) .. ".then." .. node_name(node.right) end
    if mt == ChainSeq then
        local parts = {}
        for i = 1, #node.children do parts[i] = node_name(node.children[i].node) end
        return table.concat(parts, ".then.")
    end
    return comp_tag_name(mt)
end

function uvm.comp.ir(x)
    if is_ir_node(x) then return x end
    if getmetatable(x) == family_mt then
        if x.ir then return x.ir end
        return leaf_node(x)
    end
    error("expected family or composition node", 2)
end

function uvm.comp.is_composite(x)
    return getmetatable(uvm.comp.ir(x)) ~= Leaf
end

function uvm.comp.is_leaf(x)
    return getmetatable(uvm.comp.ir(x)) == Leaf
end

function uvm.comp.codegen_of(x)
    local node = uvm.comp.ir(x)
    if getmetatable(node) == Leaf then return leaf_family(node):codegen_info() end
    return nil
end

function uvm.comp.walk(x, fn)
    local node = uvm.comp.ir(x)
    check_fn(fn, "walk fn")
    local function visit(n)
        fn(n)
        local mt = getmetatable(n)
        if mt == Chain then
            visit(n.left)
            visit(n.right)
        elseif mt == ChainSeq then
            for i = 1, #n.children do visit(n.children[i].node) end
        elseif mt == Guard or mt == Limit or mt == Fuse then
            visit(n.inner)
        end
    end
    visit(node)
end

function uvm.comp.describe(x)
    local node = uvm.comp.ir(x)
    local lines = {}
    local function emit(n, indent)
        local prefix = string.rep("  ", indent)
        local mt = getmetatable(n)
        if mt == Leaf then
            lines[#lines + 1] = prefix .. "leaf(" .. n.family.name .. ")"
        elseif mt == Chain then
            lines[#lines + 1] = prefix .. "chain"
            emit(n.left, indent + 1)
            emit(n.right, indent + 1)
        elseif mt == ChainSeq then
            lines[#lines + 1] = prefix .. "chain_seq"
            for i = 1, #n.children do emit(n.children[i].node, indent + 1) end
        elseif mt == Guard then
            lines[#lines + 1] = prefix .. "guard"
            emit(n.inner, indent + 1)
        elseif mt == Limit then
            lines[#lines + 1] = prefix .. "limit max_steps=" .. tostring(n.max_steps)
            emit(n.inner, indent + 1)
        elseif mt == Fuse then
            lines[#lines + 1] = prefix .. "fuse"
            emit(n.inner, indent + 1)
        else
            lines[#lines + 1] = prefix .. tostring(mt and mt.kind or mt)
        end
    end
    emit(node, 0)
    return table.concat(lines, "\n")
end

local function clone_guard_spec(spec)
    local mt = getmetatable(spec)
    if mt == PredicateGuard or spec == AlwaysGuard or spec == NeverGuard then return spec end
    if mt == GuardNot then return GuardNot(clone_guard_spec(spec.inner)) end
    if mt == GuardAnd then return GuardAnd(clone_guard_spec(spec.left), clone_guard_spec(spec.right)) end
    if mt == GuardOr then return GuardOr(clone_guard_spec(spec.left), clone_guard_spec(spec.right)) end
    error("cannot clone guard spec", 2)
end

local function clone_exec_spec(spec)
    return spec
end

local function clone_node(node)
    local mt = getmetatable(node)
    if mt == Leaf then
        return Leaf(node.family, node.shape, node.payload)
    elseif mt == Chain then
        return Chain(clone_node(node.left), clone_node(node.right))
    elseif mt == ChainSeq then
        local children = {}
        for i = 1, #node.children do
            children[i] = ChainChild(copy_path(node.children[i].path), clone_node(node.children[i].node))
        end
        return ChainSeq(children)
    elseif mt == Guard then
        return Guard(clone_node(node.inner), clone_guard_spec(node.guard))
    elseif mt == Limit then
        return Limit(clone_node(node.inner), node.max_steps)
    elseif mt == Fuse then
        return Fuse(clone_node(node.inner), clone_exec_spec(node.exec))
    end
    error("cannot clone composition node", 2)
end

local normalize_node
normalize_node = pvm.verb("uvm.normalize", {
    [Leaf] = function(node) return clone_node(node) end,
    [Chain] = function(node)
        local children = {}
        local function append_chain(n, path)
            local mt = getmetatable(n)
            if mt == Chain then
                append_chain(n.left, append_path(path, "a"))
                append_chain(n.right, append_path(path, "b"))
            else
                children[#children + 1] = ChainChild(copy_path(path), normalize_node(n))
            end
        end
        append_chain(node, {})
        return ChainSeq(children)
    end,
    [ChainSeq] = function(node)
        local children = {}
        for i = 1, #node.children do
            children[i] = ChainChild(copy_path(node.children[i].path), normalize_node(node.children[i].node))
        end
        return ChainSeq(children)
    end,
    [Guard] = function(node)
        return Guard(normalize_node(node.inner), clone_guard_spec(node.guard))
    end,
    [Limit] = function(node)
        return Limit(normalize_node(node.inner), node.max_steps)
    end,
    [Fuse] = function(node)
        return Fuse(normalize_node(node.inner), clone_exec_spec(node.exec))
    end,
}, { cache = true, name = "uvm.normalize" })

function uvm.comp.normalize(x, _opts)
    return normalize_node(uvm.comp.ir(x))
end

function uvm.comp.analyze(x, opts)
    opts = opts or {}
    local root = opts.normalized and x or uvm.comp.normalize(x, opts)
    local nodes, leaves = {}, {}

    local function analyze_node(node)
        local mt = getmetatable(node)
        local info = { key = node, tag = mt, node = node }
        nodes[node] = info

        if mt == Leaf then
            local fam = leaf_family(node)
            local codegen = fam:codegen_info()
            info.name = fam.name
            info.family = fam
            info.family_ref = node.family
            info.shape = node.shape
            info.payload = node.payload
            info.statuses = fam:statuses()
            if not next(info.statuses) then info.statuses = status_set(S.RUN, S.YIELD, S.TRAP, S.HALT) end
            info.codegen = codegen
            info.lowerable = codegen and (codegen.emit_step or codegen.emit_run or codegen.allocate_state)
            leaves[#leaves + 1] = info

        elseif mt == Chain then
            info.left = analyze_node(node.left)
            info.right = analyze_node(node.right)
            info.statuses = status_set_union(info.left.statuses, info.right.statuses)
            info.statuses[S.HALT] = true
            info.phases = 2

        elseif mt == ChainSeq then
            info.children = {}
            info.statuses = {}
            for i = 1, #node.children do
                local child_info = analyze_node(node.children[i].node)
                info.children[i] = { path = copy_path(node.children[i].path), info = child_info }
                info.statuses = status_set_union(info.statuses, child_info.statuses)
            end
            info.statuses[S.HALT] = true
            info.phases = #node.children

        elseif mt == Guard then
            info.inner = analyze_node(node.inner)
            info.statuses = status_set_union(info.inner.statuses, status_set(S.HALT))
            info.guard_kind = getmetatable(node.guard)

        elseif mt == Limit then
            info.inner = analyze_node(node.inner)
            info.statuses = status_set_union(info.inner.statuses, status_set(S.HALT))
            info.max_steps = node.max_steps
            info.max_steps_const = true

        elseif mt == Fuse then
            info.inner = analyze_node(node.inner)
            info.statuses = status_set(S.RUN, S.YIELD, S.TRAP, S.HALT)
            info.exec_kind = getmetatable(node.exec)
        else
            error("cannot analyze composition node " .. comp_tag_name(node), 2)
        end

        return info
    end

    local root_info = analyze_node(root)
    return {
        root = root,
        root_info = root_info,
        nodes = nodes,
        leaves = leaves,
    }
end

function uvm.comp.lower(x, opts)
    opts = opts or {}
    local analysis = opts.analysis or uvm.comp.analyze(x, opts)
    local next_plan_id = 0
    local function plan_id() next_plan_id = next_plan_id + 1; return next_plan_id end

    local function lower_node(info)
        local node = info.node
        local mt = getmetatable(node)
        local plan = {
            tag = mt,
            id = plan_id(),
            node = node,
            name = node_name(node),
            statuses = status_set_copy(info.statuses),
            lowerable = info.lowerable,
        }

        if mt == Leaf then
            plan.family = info.family
            plan.codegen = info.codegen
            plan.state_kind = (info.codegen and info.codegen.state_kind) or "opaque_leaf"
            plan.status_list = status_set_list(info.statuses)
            plan.family_ref = info.family_ref
            plan.shape = info.shape
            plan.payload = info.payload

        elseif mt == Chain then
            plan.left = lower_node(info.left)
            plan.right = lower_node(info.right)
            plan.phase_count = 2
            plan.state_kind = "chain_phase"

        elseif mt == ChainSeq then
            plan.children = {}
            for i = 1, #info.children do
                plan.children[i] = {
                    path = copy_path(info.children[i].path),
                    plan = lower_node(info.children[i].info),
                }
            end
            plan.phase_count = info.phases
            plan.state_kind = "chain_seq_phase"

        elseif mt == Guard then
            plan.inner = lower_node(info.inner)
            plan.guard = node.guard
            plan.guard_kind = info.guard_kind
            plan.state_kind = plan.inner.state_kind

        elseif mt == Limit then
            plan.inner = lower_node(info.inner)
            plan.max_steps = info.max_steps
            plan.state_kind = "limit_counter"

        elseif mt == Fuse then
            plan.inner = lower_node(info.inner)
            plan.exec = node.exec
            plan.state_kind = "fuse_acc"
        end

        return plan
    end

    return {
        root = lower_node(analysis.root_info),
        analysis = analysis,
    }
end

function uvm.comp.allocate_state(x, opts)
    opts = opts or {}
    local lowered = opts.lowered or uvm.comp.lower(x, opts)
    local slots, node_slots = {}, {}
    local next_slot = 0

    local function alloc(owner_id, kind, name)
        next_slot = next_slot + 1
        slots[next_slot] = { index = next_slot, owner_id = owner_id, kind = kind, name = name }
        return next_slot
    end

    local function alloc_node(plan)
        if plan.tag == Leaf then
            if plan.codegen and plan.codegen.allocate_state then
                node_slots[plan.id] = plan.codegen.allocate_state(plan, alloc) or {}
            else
                node_slots[plan.id] = { state = alloc(plan.id, "leaf_state", plan.name .. ".state") }
            end

        elseif plan.tag == Chain then
            alloc_node(plan.left)
            alloc_node(plan.right)
            node_slots[plan.id] = { phase = alloc(plan.id, "phase", plan.name .. ".phase") }

        elseif plan.tag == ChainSeq then
            for i = 1, #plan.children do alloc_node(plan.children[i].plan) end
            node_slots[plan.id] = { phase = alloc(plan.id, "phase", plan.name .. ".phase") }

        elseif plan.tag == Guard then
            alloc_node(plan.inner)
            node_slots[plan.id] = node_slots[plan.inner.id]

        elseif plan.tag == Limit then
            alloc_node(plan.inner)
            node_slots[plan.id] = { seen = alloc(plan.id, "counter", plan.name .. ".seen") }

        elseif plan.tag == Fuse then
            alloc_node(plan.inner)
            node_slots[plan.id] = { acc = alloc(plan.id, "acc", plan.name .. ".acc") }
        end
    end

    alloc_node(lowered.root)
    return {
        slots = slots,
        node_slots = node_slots,
        slot_count = next_slot,
        lowered = lowered,
    }
end

function uvm.comp.plan(x, opts)
    opts = opts or {}
    local analysis = uvm.comp.analyze(x, opts)
    local lowered = uvm.comp.lower(x, { analysis = analysis })
    local layout = uvm.comp.allocate_state(x, { lowered = lowered })
    return {
        ir = analysis.root,
        analysis = analysis,
        lowered = lowered,
        layout = layout,
    }
end

local function eval_guard_spec(spec, param, state)
    local mt = getmetatable(spec)
    if mt == PredicateGuard then return spec.fn(param, state) end
    if spec == AlwaysGuard then return true end
    if spec == NeverGuard then return false end
    if mt == GuardNot then return not eval_guard_spec(spec.inner, param, state) end
    if mt == GuardAnd then return eval_guard_spec(spec.left, param, state) and eval_guard_spec(spec.right, param, state) end
    if mt == GuardOr then return eval_guard_spec(spec.left, param, state) or eval_guard_spec(spec.right, param, state) end
    error("unknown guard spec", 2)
end

local function exec_spec_fn(spec)
    local mt = getmetatable(spec)
    if mt == OpaqueExec then return spec.fn end
    error("unknown exec spec", 2)
end

local function comp_init(node, param, seed)
    local mt = getmetatable(node)
    if mt == Leaf then
        return leaf_family(node):init(param, seed)
    elseif mt == Chain then
        seed = seed or {}
        return {
            phase = 1,
            a = comp_init(node.left, param and param.a, seed.a),
            b = comp_init(node.right, param and param.b, seed.b),
        }
    elseif mt == ChainSeq then
        local inner = {}
        for i = 1, #node.children do
            local child = node.children[i]
            inner[i] = comp_init(child.node, path_value(param, child.path), path_value(seed, child.path))
        end
        return { phase = 1, inner = inner }
    elseif mt == Guard then
        return comp_init(node.inner, param and param.inner, seed)
    elseif mt == Limit then
        return { inner = comp_init(node.inner, param and param.inner, seed), seen = 0 }
    elseif mt == Fuse then
        seed = seed or {}
        return { inner = comp_init(node.inner, param and param.inner, seed.inner), acc = seed.acc }
    end
    error("unknown composition node " .. comp_tag_name(node), 2)
end

local function comp_patch(node, old_param, new_param, old_state)
    local mt = getmetatable(node)
    if mt == Leaf then
        return leaf_family(node):patch(old_param, new_param, old_state)
    elseif mt == Chain then
        return {
            phase = old_state.phase,
            a = comp_patch(node.left, old_param and old_param.a, new_param and new_param.a, old_state.a),
            b = comp_patch(node.right, old_param and old_param.b, new_param and new_param.b, old_state.b),
        }
    elseif mt == ChainSeq then
        local inner = {}
        for i = 1, #node.children do
            local child = node.children[i]
            inner[i] = comp_patch(child.node, path_value(old_param, child.path), path_value(new_param, child.path), old_state.inner[i])
        end
        return { phase = old_state.phase, inner = inner }
    elseif mt == Guard then
        return comp_patch(node.inner, old_param and old_param.inner, new_param and new_param.inner, old_state)
    elseif mt == Limit then
        return {
            inner = comp_patch(node.inner, old_param and old_param.inner, new_param and new_param.inner, old_state.inner),
            seen = old_state.seen,
        }
    elseif mt == Fuse then
        return {
            inner = comp_patch(node.inner, old_param and old_param.inner, new_param and new_param.inner, old_state.inner),
            acc = old_state.acc,
        }
    end
    error("unknown composition node " .. comp_tag_name(node), 2)
end

local function comp_step(node, param, state)
    local mt = getmetatable(node)
    if mt == Leaf then
        return leaf_family(node).step_fn(param, state)

    elseif mt == Chain then
        while true do
            if state.phase == 1 then
                local ns, st, a, b, c, d = comp_step(node.left, param.a, state.a)
                if st == S.HALT or ns == nil then
                    state.a = ns
                    state.phase = 2
                else
                    state.a = ns
                    return state, st, a, b, c, d
                end
            else
                local ns, st, a, b, c, d = comp_step(node.right, param.b, state.b)
                if st == S.HALT or ns == nil then return nil, S.HALT, a, b, c, d end
                state.b = ns
                return state, st, a, b, c, d
            end
        end

    elseif mt == ChainSeq then
        while true do
            local phase = state.phase
            local child = node.children[phase]
            if not child then return state, S.TRAP, "bad_phase", phase end
            local ns, st, a, b, c, d = comp_step(child.node, path_value(param, child.path), state.inner[phase])
            if st == S.HALT or ns == nil then
                state.inner[phase] = ns
                if phase >= #node.children then return nil, S.HALT, a, b, c, d end
                state.phase = phase + 1
            else
                state.inner[phase] = ns
                return state, st, a, b, c, d
            end
        end

    elseif mt == Guard then
        if not eval_guard_spec(node.guard, param, state) then return nil, S.HALT end
        return comp_step(node.inner, param and param.inner, state)

    elseif mt == Limit then
        if state.seen >= node.max_steps then return nil, S.HALT end
        local ns, st, a, b, c, d = comp_step(node.inner, param.inner, state.inner)
        state.seen = state.seen + 1
        if st == S.HALT or ns == nil then return nil, S.HALT, a, b, c, d end
        state.inner = ns
        return state, st, a, b, c, d

    elseif mt == Fuse then
        while true do
            local ns, st, a, b, c, d = comp_step(node.inner, param.inner, state.inner)
            if st == S.HALT or ns == nil then return nil, S.HALT, state.acc end
            state.inner = ns
            if st == S.RUN then
                return state, S.RUN
            elseif st == S.TRAP then
                return state, S.TRAP, a, b, c, d
            elseif st == S.YIELD then
                local nacc, ost, x1, x2, x3, x4 = exec_spec_fn(node.exec)(param and param.exec, state.acc, a, b, c, d)
                state.acc = nacc
                if ost ~= S.RUN then return state, ost, x1, x2, x3, x4 end
            else
                return state, S.TRAP, "bad_status", st
            end
        end
    end

    error("unknown composition node " .. comp_tag_name(node), 2)
end

uvm.comp.init = comp_init
uvm.comp.patch = comp_patch
uvm.comp.step = comp_step

local function composite_family(node, spec)
    spec = spec or {}
    local statuses = spec.statuses or (uvm.comp.analyze(node, { normalized = true }).root_info.statuses)
    local fam = uvm.family({
        name = spec.name or node_name(node),
        step = spec.step or function(param, state) return comp_step(node, param, state) end,
        init = spec.init or function(param, seed) return comp_init(node, param, seed) end,
        patch = spec.patch or function(op, np, os) return comp_patch(node, op, np, os) end,
        disasm = spec.disasm or function() return uvm.comp.describe(node) end,
        meta = spec.meta or {},
        statuses = statuses,
        family_kind = "composite",
        ir = node,
    })
    if spec.source then fam.source = spec.source end
    if spec.run_fn then fam.run_fn = spec.run_fn end
    if spec.run_source then fam.run_source = spec.run_source end
    if spec.normalized_ir then fam.normalized_ir = spec.normalized_ir end
    return fam
end

-- Old nested-state codegen helpers removed.
-- Compiled families now lower through explicit analysis/lowering/layout
-- passes and emit flat-state init/patch/step/run functions only.

local function slot_expr(state_expr, slot)
    return string.format("%s[%d]", state_expr, slot)
end

local function safe_field_expr(base_expr, key)
    return string.format("((%s) and (%s).%s)", base_expr, base_expr, key)
end

local function emit_flat_init_node(q, plan_node, layout, param_expr, seed_expr, state_expr)
    local slots = layout.node_slots[plan_node.id] or {}
    if plan_node.tag == Leaf then
        if plan_node.codegen and plan_node.codegen.kind == "dispatch_codegen" then
            local init_vm = q:val(plan_node.codegen.init_vm, "init_vm_" .. tostring(plan_node.id))
            local seed_local = q:sym("seed_" .. tostring(plan_node.id))
            q("  local %s = %s or {}", seed_local, seed_expr)
            q("  %s = %s.pc or %d", slot_expr(state_expr, slots.pc), seed_local, plan_node.codegen.pc0 or 1)
            q("  %s = %s(%s, %s.vm)", slot_expr(state_expr, slots.vm), init_vm, param_expr, seed_local)
        else
            local fam = q:val(plan_node.family, "fam_" .. tostring(plan_node.id))
            q("  %s = %s:init(%s, %s)", slot_expr(state_expr, slots.state), fam, param_expr, seed_expr)
        end

    elseif plan_node.tag == Chain then
        emit_flat_init_node(q, plan_node.left, layout, safe_field_expr(param_expr, "a"), safe_field_expr(seed_expr, "a"), state_expr)
        emit_flat_init_node(q, plan_node.right, layout, safe_field_expr(param_expr, "b"), safe_field_expr(seed_expr, "b"), state_expr)
        q("  %s = 1", slot_expr(state_expr, slots.phase))

    elseif plan_node.tag == ChainSeq then
        local _path_value = q:val(path_value, "path_value")
        for i = 1, #plan_node.children do
            local child = plan_node.children[i]
            local path_ref = q:val(copy_path(child.path), "path_" .. tostring(plan_node.id) .. "_" .. tostring(i))
            emit_flat_init_node(q, child.plan, layout,
                string.format("%s(%s, %s)", _path_value, param_expr, path_ref),
                string.format("%s(%s, %s)", _path_value, seed_expr, path_ref),
                state_expr)
        end
        q("  %s = 1", slot_expr(state_expr, slots.phase))

    elseif plan_node.tag == Guard then
        emit_flat_init_node(q, plan_node.inner, layout, safe_field_expr(param_expr, "inner"), seed_expr, state_expr)

    elseif plan_node.tag == Limit then
        emit_flat_init_node(q, plan_node.inner, layout, safe_field_expr(param_expr, "inner"), seed_expr, state_expr)
        q("  %s = 0", slot_expr(state_expr, slots.seen))

    elseif plan_node.tag == Fuse then
        emit_flat_init_node(q, plan_node.inner, layout, safe_field_expr(param_expr, "inner"), safe_field_expr(seed_expr, "inner"), state_expr)
        q("  %s = %s", slot_expr(state_expr, slots.acc), safe_field_expr(seed_expr, "acc"))
    end
end

local function emit_flat_patch_node(q, plan_node, layout, old_param_expr, new_param_expr, old_state_expr, state_expr)
    local slots = layout.node_slots[plan_node.id] or {}
    if plan_node.tag == Leaf then
        if plan_node.codegen and plan_node.codegen.kind == "dispatch_codegen" then
            local patch_vm = q:val(plan_node.codegen.patch_vm, "patch_vm_" .. tostring(plan_node.id))
            q("  %s = %s", slot_expr(state_expr, slots.pc), slot_expr(old_state_expr, slots.pc))
            q("  %s = %s(%s, %s, %s)", slot_expr(state_expr, slots.vm), patch_vm, old_param_expr, new_param_expr, slot_expr(old_state_expr, slots.vm))
        else
            local fam = q:val(plan_node.family, "fam_" .. tostring(plan_node.id))
            q("  %s = %s:patch(%s, %s, %s)", slot_expr(state_expr, slots.state), fam, old_param_expr, new_param_expr, slot_expr(old_state_expr, slots.state))
        end

    elseif plan_node.tag == Chain then
        emit_flat_patch_node(q, plan_node.left, layout, safe_field_expr(old_param_expr, "a"), safe_field_expr(new_param_expr, "a"), old_state_expr, state_expr)
        emit_flat_patch_node(q, plan_node.right, layout, safe_field_expr(old_param_expr, "b"), safe_field_expr(new_param_expr, "b"), old_state_expr, state_expr)
        q("  %s = %s", slot_expr(state_expr, slots.phase), slot_expr(old_state_expr, slots.phase))

    elseif plan_node.tag == ChainSeq then
        local _path_value = q:val(path_value, "path_value")
        for i = 1, #plan_node.children do
            local child = plan_node.children[i]
            local path_ref = q:val(copy_path(child.path), "path_" .. tostring(plan_node.id) .. "_" .. tostring(i))
            emit_flat_patch_node(q, child.plan, layout,
                string.format("%s(%s, %s)", _path_value, old_param_expr, path_ref),
                string.format("%s(%s, %s)", _path_value, new_param_expr, path_ref),
                old_state_expr, state_expr)
        end
        q("  %s = %s", slot_expr(state_expr, slots.phase), slot_expr(old_state_expr, slots.phase))

    elseif plan_node.tag == Guard then
        emit_flat_patch_node(q, plan_node.inner, layout, safe_field_expr(old_param_expr, "inner"), safe_field_expr(new_param_expr, "inner"), old_state_expr, state_expr)

    elseif plan_node.tag == Limit then
        emit_flat_patch_node(q, plan_node.inner, layout, safe_field_expr(old_param_expr, "inner"), safe_field_expr(new_param_expr, "inner"), old_state_expr, state_expr)
        q("  %s = %s", slot_expr(state_expr, slots.seen), slot_expr(old_state_expr, slots.seen))

    elseif plan_node.tag == Fuse then
        emit_flat_patch_node(q, plan_node.inner, layout, safe_field_expr(old_param_expr, "inner"), safe_field_expr(new_param_expr, "inner"), old_state_expr, state_expr)
        q("  %s = %s", slot_expr(state_expr, slots.acc), slot_expr(old_state_expr, slots.acc))
    end
end

local function emit_flat_step_functions(q, root_plan, layout)
    local refs = {
        S_RUN = q:val(S.RUN, "S_RUN"),
        S_YIELD = q:val(S.YIELD, "S_YIELD"),
        S_TRAP = q:val(S.TRAP, "S_TRAP"),
        S_HALT = q:val(S.HALT, "S_HALT"),
    }
    local fn_cache = {}

    local function emit_node(plan_node)
        if fn_cache[plan_node] then return fn_cache[plan_node] end
        local fname = q:sym("step_n" .. tostring(plan_node.id))
        fn_cache[plan_node] = fname
        local slots = layout.node_slots[plan_node.id] or {}

        if plan_node.tag == Leaf then
            if plan_node.codegen and plan_node.codegen.kind == "dispatch_codegen" then
                local decode = q:val(plan_node.codegen.decode, "decode_" .. tostring(plan_node.id))
                local opcodes = {}
                for opcode in pairs(plan_node.codegen.handlers) do opcodes[#opcodes + 1] = opcode end
                table.sort(opcodes, function(a, b) return tostring(a) < tostring(b) end)
                local op_refs, handler_refs = {}, {}
                for i = 1, #opcodes do
                    op_refs[i] = q:val(opcodes[i], "OP_" .. tostring(plan_node.id) .. "_" .. tostring(i))
                    handler_refs[i] = q:val(plan_node.codegen.handlers[opcodes[i]], "H_" .. tostring(plan_node.id) .. "_" .. tostring(i))
                end
                q("local function %s(param, state)", fname)
                q("  local pc = %s", slot_expr("state", slots.pc))
                q("  local vm = %s", slot_expr("state", slots.vm))
                q("  local word = param.code[pc]")
                q("  if word == nil then return nil, %s, vm end", refs.S_HALT)
                q("  local opcode, a, b, c, d = %s(param, word, pc)", decode)
                q("  pc = pc + 1")
                q("  local nvm, ost, x1, x2, x3, x4")
                for i = 1, #opcodes do
                    local kw = (i == 1) and "if" or "elseif"
                    q("  %s opcode == %s then", kw, op_refs[i])
                    q("    nvm, ost, x1, x2, x3, x4 = %s(param, vm, pc - 1, a, b, c, d)", handler_refs[i])
                end
                q("  else")
                q("    return state, %s, \"bad_opcode\", opcode, pc - 1", refs.S_TRAP)
                q("  end")
                q("  %s = pc", slot_expr("state", slots.pc))
                q("  %s = nvm", slot_expr("state", slots.vm))
                q("  if ost == %s then return nil, %s, x1, x2, x3, x4 end", refs.S_HALT, refs.S_HALT)
                q("  return state, ost, x1, x2, x3, x4")
                q("end")
            else
                local leaf_step = q:val(plan_node.family.step_fn, "step_" .. tostring(plan_node.id))
                q("local function %s(param, state)", fname)
                q("  local ns, st, a, b, c, d = %s(param, %s)", leaf_step, slot_expr("state", slots.state))
                q("  %s = ns", slot_expr("state", slots.state))
                q("  if st == %s or ns == nil then return nil, %s, a, b, c, d end", refs.S_HALT, refs.S_HALT)
                q("  return state, st, a, b, c, d")
                q("end")
            end

        elseif plan_node.tag == Chain then
            local left_fn = emit_node(plan_node.left)
            local right_fn = emit_node(plan_node.right)
            q("local function %s(param, state)", fname)
            q("  while true do")
            q("    if %s == 1 then", slot_expr("state", slots.phase))
            q("      local ns, st, a, b, c, d = %s(param.a, state)", left_fn)
            q("      if st == %s or ns == nil then", refs.S_HALT)
            q("        %s = 2", slot_expr("state", slots.phase))
            q("      else")
            q("        return state, st, a, b, c, d")
            q("      end")
            q("    else")
            q("      return %s(param.b, state)", right_fn)
            q("    end")
            q("  end")
            q("end")

        elseif plan_node.tag == ChainSeq then
            local child_fns = {}
            for i = 1, #plan_node.children do child_fns[i] = emit_node(plan_node.children[i].plan) end
            q("local function %s(param, state)", fname)
            q("  while true do")
            q("    local phase = %s", slot_expr("state", slots.phase))
            for i = 1, #plan_node.children do
                local kw = (i == 1) and "if" or "elseif"
                local child = plan_node.children[i]
                q("    %s phase == %d then", kw, i)
                q("      local ns, st, a, b, c, d = %s(%s, state)", child_fns[i], path_expr("param", child.path))
                q("      if st == %s or ns == nil then", refs.S_HALT)
                if i < #plan_node.children then
                    q("        %s = %d", slot_expr("state", slots.phase), i + 1)
                else
                    q("        return nil, %s, a, b, c, d", refs.S_HALT)
                end
                q("      else")
                q("        return state, st, a, b, c, d")
                q("      end")
            end
            q("    else")
            q("      return state, %s, \"bad_phase\", phase", refs.S_TRAP)
            q("    end")
            q("  end")
            q("end")

        elseif plan_node.tag == Guard then
            local inner_fn = emit_node(plan_node.inner)
            local pred = q:val((getmetatable(plan_node.guard) == PredicateGuard) and plan_node.guard.fn or function(param, state) return eval_guard_spec(plan_node.guard, param, state) end, "pred_" .. tostring(plan_node.id))
            q("local function %s(param, state)", fname)
            q("  if not %s(param, state) then return nil, %s end", pred, refs.S_HALT)
            q("  return %s(param.inner, state)", inner_fn)
            q("end")

        elseif plan_node.tag == Limit then
            local inner_fn = emit_node(plan_node.inner)
            q("local function %s(param, state)", fname)
            q("  if %s >= %d then return nil, %s end", slot_expr("state", slots.seen), plan_node.max_steps, refs.S_HALT)
            q("  local ns, st, a, b, c, d = %s(param.inner, state)", inner_fn)
            q("  %s = %s + 1", slot_expr("state", slots.seen), slot_expr("state", slots.seen))
            q("  if st == %s or ns == nil then return nil, %s, a, b, c, d end", refs.S_HALT, refs.S_HALT)
            q("  return state, st, a, b, c, d")
            q("end")

        elseif plan_node.tag == Fuse then
            local inner_fn = emit_node(plan_node.inner)
            local exec_step = q:val(exec_spec_fn(plan_node.exec), "exec_" .. tostring(plan_node.id))
            local statuses = plan_node.inner.statuses or {}
            q("local function %s(param, state)", fname)
            q("  while true do")
            q("    local ns, st, a, b, c, d = %s(param.inner, state)", inner_fn)
            q("    if st == %s or ns == nil then return nil, %s, %s end", refs.S_HALT, refs.S_HALT, slot_expr("state", slots.acc))
            if statuses[S.RUN] then
                q("    if st == %s then return state, %s end", refs.S_RUN, refs.S_RUN)
            end
            if statuses[S.TRAP] then
                q("    if st == %s then return state, %s, a, b, c, d end", refs.S_TRAP, refs.S_TRAP)
            end
            if statuses[S.YIELD] then
                q("    if st == %s then", refs.S_YIELD)
                q("      local nacc, ost, x1, x2, x3, x4 = %s(param.exec, %s, a, b, c, d)", exec_step, slot_expr("state", slots.acc))
                q("      %s = nacc", slot_expr("state", slots.acc))
                q("      if ost ~= %s then return state, ost, x1, x2, x3, x4 end", refs.S_RUN)
                q("    else")
                q("      return state, %s, \"bad_status\", st", refs.S_TRAP)
                q("    end")
            else
                q("    return state, %s, \"bad_status\", st", refs.S_TRAP)
            end
            q("  end")
            q("end")
        end

        return fname
    end

    return { root_step = emit_node(root_plan), refs = refs, emit_node = emit_node }
end

-- Shared compiled execution bundle.
--
-- We emit the helper forest once, then define both the public step_fn
-- and the fused run_fn from that same generated chunk. This keeps the
-- compiled backend centered on one executable artifact instead of
-- regenerating the same helper functions twice.
local function build_flat_exec_bundle(root, layout)
    local q = Quote()
    local ctx = emit_flat_step_functions(q, root, layout)
    local step_name = q:sym("compiled_step")
    local run_name = q:sym("compiled_run")

    q("local function %s(param, state)", step_name)
    q("  return %s(param, state)", ctx.root_step)
    q("end")

    if root.tag == Limit then
        local seen_slot = layout.node_slots[root.id].seen
        local inner_fn = ctx.emit_node(root.inner)
        q("local function %s(param, state, budget)", run_name)
        q("  budget = budget or 1e18")
        q("  local steps = 0")
        q("  local seen = %s", slot_expr("state", seen_slot))
        q("  local remaining = %d - seen", root.max_steps)
        q("  local hard_budget = budget")
        q("  if remaining < hard_budget then hard_budget = remaining end")
        q("  while steps < hard_budget do")
        q("    local ns, st, a, b, c, d = %s(param.inner, state)", inner_fn)
        q("    seen = seen + 1")
        q("    if st == %s or ns == nil then %s = seen; return nil, %s, a, b, c, d, steps + 1 end", ctx.refs.S_HALT, slot_expr("state", seen_slot), ctx.refs.S_HALT)
        q("    steps = steps + 1")
        q("    if st ~= %s then %s = seen; return state, st, a, b, c, d, steps end", ctx.refs.S_RUN, slot_expr("state", seen_slot))
        q("  end")
        q("  %s = seen", slot_expr("state", seen_slot))
        q("  if steps < budget and seen >= %d then return nil, %s, nil, nil, nil, nil, steps + 1 end", root.max_steps, ctx.refs.S_HALT)
        q("  return state, %s, nil, nil, nil, nil, steps", ctx.refs.S_RUN)
        q("end")
    else
        q("local function %s(param, state, budget)", run_name)
        q("  budget = budget or 1e18")
        q("  local steps = 0")
        q("  while steps < budget do")
        q("    local ns, st, a, b, c, d = %s(param, state)", ctx.root_step)
        q("    steps = steps + 1")
        q("    if st ~= %s then return ns, st, a, b, c, d, steps end", ctx.refs.S_RUN)
        q("  end")
        q("  return state, %s, nil, nil, nil, nil, steps", ctx.refs.S_RUN)
        q("end")
    end

    q("return { step = %s, run = %s }", step_name, run_name)
    local bundle, src = q:compile("=(uvm.compiled.exec)")
    return bundle.step, bundle.run, src
end

local function compile_from_plan(plan, opts)
    opts = opts or {}
    local ir = plan.ir
    local root = plan.lowered.root
    local layout = plan.layout
    if getmetatable(ir) == Leaf and not opts.force and not (root.codegen and root.codegen.kind == "dispatch_codegen") then return leaf_family(ir) end

    local init_q = Quote()
    init_q("return function(param, seed)")
    init_q("  local state = {}")
    emit_flat_init_node(init_q, root, layout, "param", "seed", "state")
    init_q("  return state")
    init_q("end")
    local init_fn, init_src = init_q:compile("=(uvm.compiled.init)")

    local patch_q = Quote()
    patch_q("return function(old_param, new_param, old_state)")
    patch_q("  local state = {}")
    emit_flat_patch_node(patch_q, root, layout, "old_param", "new_param", "old_state", "state")
    patch_q("  return state")
    patch_q("end")
    local patch_fn, patch_src = patch_q:compile("=(uvm.compiled.patch)")

    local step_fn, run_fn, exec_src = build_flat_exec_bundle(root, layout)

    local compiled = composite_family(ir, {
        name = opts.name or (node_name(ir) .. ".compiled"),
        init = init_fn,
        patch = patch_fn,
        step = step_fn,
        run_fn = run_fn,
        meta = {
            compiled = true,
            compile_stage = "specialized",
            run_compiled = true,
            run_hoisted = true,
            flat_state = true,
            statuses = status_set_copy(plan.analysis.root_info.statuses),
        },
        statuses = plan.analysis.root_info.statuses,
        source = exec_src,
        run_source = exec_src,
        normalized_ir = ir,
    })
    compiled.exec_source = exec_src
    compiled.init_source = init_src
    compiled.patch_source = patch_src
    compiled.analysis = plan.analysis
    compiled.lowered_plan = plan.lowered
    compiled.state_layout = plan.layout
    return compiled
end

local compile_lower = pvm.lower("uvm.compile_family", function(root)
    return compile_from_plan(uvm.comp.plan(root, { normalized = true }), {})
end, { input = "table" })

function uvm.comp.compile(x, opts)
    opts = opts or {}
    local normalized = uvm.comp.normalize(x, opts)
    if next(opts) == nil then return compile_lower(normalized) end
    return compile_from_plan(uvm.comp.plan(normalized, { normalized = true }), opts)
end

local function as_guard_spec(x)
    local mt = getmetatable(x)
    if mt == PredicateGuard or x == AlwaysGuard or x == NeverGuard or mt == GuardNot or mt == GuardAnd or mt == GuardOr then
        return x
    end
    if type(x) == "function" then return PredicateGuard(x) end
    if x == true then return AlwaysGuard end
    if x == false then return NeverGuard end
    error("guard must be a predicate function or guard spec", 3)
end

local function as_exec_spec(x)
    local mt = getmetatable(x)
    if mt == OpaqueExec then return x end
    if type(x) == "function" then return OpaqueExec(x) end
    error("exec must be a function or exec spec", 3)
end

local function as_node(x, name)
    if is_ir_node(x) then return x end
    if getmetatable(x) == family_mt then
        if x.ir then return x.ir end
        return leaf_node(x)
    end
    error((name or "value") .. " must be a family or composition node", 3)
end

function uvm.op.chain(fa, fb, opts)
    opts = opts or {}
    local left = as_node(fa, "fa")
    local right = as_node(fb, "fb")
    return composite_family(Chain(left, right), {
        name = opts.name or (node_name(left) .. ".then." .. node_name(right)),
    })
end

function uvm.op.guard(fam, pred, opts)
    opts = opts or {}
    local inner = as_node(fam, "fam")
    return composite_family(Guard(inner, as_guard_spec(pred)), {
        name = opts.name or (node_name(inner) .. ".guard"),
    })
end

function uvm.op.limit(fam, max_steps, opts)
    opts = opts or {}
    assert(type(max_steps) == "number" and max_steps > 0)
    local inner = as_node(fam, "fam")
    return composite_family(Limit(inner, max_steps), {
        name = opts.name or (node_name(inner) .. ".limit(" .. max_steps .. ")"),
    })
end

function uvm.op.fuse(decoder_family, exec_step, opts)
    opts = opts or {}
    local inner = as_node(decoder_family, "decoder_family")
    return composite_family(Fuse(inner, as_exec_spec(exec_step)), {
        name = opts.name or (node_name(inner) .. ".fused"),
    })
end

-- ══════════════════════════════════════════════════════════════
--  VM HELPERS
-- ══════════════════════════════════════════════════════════════

uvm.vm = {}

function uvm.vm.word_stream(opts)
    opts = opts or {}
    local code_key = opts.code_key or "code"; local pc0 = opts.pc0 or 1
    return uvm.families.stream(opts.name or "vm.word_stream", function(param, pc)
        local word = param[code_key][pc]
        if word == nil then return nil end
        return pc + 1, pc, word
    end, { init = function(_, seed) return seed or pc0 end,
            patch = function(_, _, old_pc) return old_pc end })
end

function uvm.vm.decoder(stream_family, decode_fn, opts)
    opts = opts or {}; check_fn(decode_fn, "decode_fn")
    return uvm.family({
        name = opts.name or (stream_family.name .. ".decode"),
        init = function(p, seed) return stream_family:init(p.stream, seed) end,
        patch = function(op, np, os) return stream_family:patch(op.stream, np.stream, os) end,
        statuses = opts.statuses or status_set(S.YIELD, S.TRAP, S.HALT),
        step = function(param, state)
            local ns, st, pc, word = stream_family.step_fn(param.stream, state)
            if st==S.HALT or ns==nil then return nil, S.HALT end
            if st ~= S.YIELD then return ns, st, pc, word end
            return ns, S.YIELD, decode_fn(param, word, pc)
        end,
    })
end

function uvm.vm.dispatch(opts)
    opts = opts or {}
    local handlers = check_table(opts.handlers or {}, "handlers")
    local decode = check_fn(opts.decode, "decode")
    local init_vm = opts.init_vm or default_init
    local patch_vm = opts.patch_vm or default_patch
    return uvm.family({
        name = opts.name or "vm.dispatch",
        statuses = opts.statuses or status_set(S.RUN, S.YIELD, S.TRAP, S.HALT),
        init = function(p, seed) seed=seed or {}
            return { pc=seed.pc or (opts.pc0 or 1), vm=init_vm(p, seed.vm) } end,
        patch = function(op, np, os)
            return { pc=os.pc, vm=patch_vm(op, np, os.vm) } end,
        step = function(param, state)
            local word = param.code[state.pc]
            if word == nil then return nil, S.HALT, state.vm end
            local opcode, a, b, c, d = decode(param, word, state.pc)
            local handler = handlers[opcode]
            if not handler then return state, S.TRAP, "bad_opcode", opcode, state.pc end
            state.pc = state.pc + 1
            local nvm, ost, x1,x2,x3,x4 = handler(param, state.vm, state.pc-1, a, b, c, d)
            state.vm = nvm
            if ost==S.HALT then return nil, S.HALT, x1,x2,x3,x4 end
            return state, ost, x1,x2,x3,x4
        end,
    })
end

-- ══════════════════════════════════════════════════════════════
--  CODEGEN: generate specialized step and fused run functions
--
--  Emits direct opcode tests and one fused run loop so the VM hot path
--  has a simple shape for LuaJIT.
-- ══════════════════════════════════════════════════════════════

function uvm.vm.dispatch_codegen(opts)
    opts = opts or {}
    local handlers = check_table(opts.handlers or {}, "handlers")
    local decode = check_fn(opts.decode, "decode")
    local init_vm = opts.init_vm or default_init
    local patch_vm = opts.patch_vm or default_patch
    local vm_name = opts.name or "vm.dispatch_cg"

    -- Collect opcode names and assign numeric tags
    local opcodes = {}
    local handler_list = {}
    for opcode, handler in pairs(handlers) do
        opcodes[#opcodes+1] = opcode
        handler_list[#handler_list+1] = handler
    end
    table.sort(opcodes, function(a, b) return tostring(a) < tostring(b) end)

    -- Build opcode → index mapping
    local op_to_idx = {}
    for i = 1, #opcodes do op_to_idx[opcodes[i]] = i end

    local step_q = Quote()
    local _decode = step_q:val(decode, "decode")
    local _S_HALT = step_q:val(S.HALT, "S_HALT")
    local _S_TRAP = step_q:val(S.TRAP, "S_TRAP")
    local op_refs, handler_refs = {}, {}
    for i = 1, #opcodes do
        op_refs[i] = step_q:val(opcodes[i], "OP_" .. i)
        handler_refs[i] = step_q:val(handlers[opcodes[i]], "H_" .. i)
    end

    step_q("return function(param, state)")
    step_q("  local pc = state.pc")
    step_q("  local word = param.code[pc]")
    step_q("  if word == nil then return nil, %s, state.vm end", _S_HALT)
    step_q("  local opcode, a, b, c, d = %s(param, word, pc)", _decode)
    step_q("  state.pc = pc + 1")
    step_q("  local nvm, ost, x1, x2, x3, x4")
    for i = 1, #opcodes do
        local kw = (i == 1) and "if" or "elseif"
        step_q("  %s opcode == %s then", kw, op_refs[i])
        step_q("    nvm, ost, x1, x2, x3, x4 = %s(param, state.vm, pc, a, b, c, d)", handler_refs[i])
    end
    step_q("  else")
    step_q("    return state, %s, \"bad_opcode\", opcode, pc", _S_TRAP)
    step_q("  end")
    step_q("  state.vm = nvm")
    step_q("  if ost == %s then return nil, %s, x1, x2, x3, x4 end", _S_HALT, _S_HALT)
    step_q("  return state, ost, x1, x2, x3, x4")
    step_q("end")

    local step_fn, step_src = step_q:compile("=(" .. vm_name .. ".step)")

    local run_q = Quote()
    local _r_decode = run_q:val(decode, "decode")
    local _r_S_HALT = run_q:val(S.HALT, "S_HALT")
    local _r_S_TRAP = run_q:val(S.TRAP, "S_TRAP")
    local _r_S_RUN = run_q:val(S.RUN, "S_RUN")
    local run_op_refs, run_handler_refs = {}, {}
    for i = 1, #opcodes do
        run_op_refs[i] = run_q:val(opcodes[i], "OP_" .. i)
        run_handler_refs[i] = run_q:val(handlers[opcodes[i]], "H_" .. i)
    end

    run_q("return function(param, state, budget)")
    run_q("  budget = budget or 1e18")
    run_q("  local vm = state.vm")
    run_q("  local code = param.code")
    run_q("  local steps = 0")
    run_q("  while steps < budget do")
    run_q("    local pc = state.pc")
    run_q("    local word = code[pc]")
    run_q("    if word == nil then return nil, %s, vm, steps end", _r_S_HALT)
    run_q("    local opcode, a, b, c, d = %s(param, word, pc)", _r_decode)
    run_q("    state.pc = pc + 1")
    run_q("    steps = steps + 1")
    run_q("    local ost, x1, x2, x3, x4")
    for i = 1, #opcodes do
        local kw = (i == 1) and "if" or "elseif"
        run_q("    %s opcode == %s then", kw, run_op_refs[i])
        run_q("      vm, ost, x1, x2, x3, x4 = %s(param, vm, pc, a, b, c, d)", run_handler_refs[i])
    end
    run_q("    else")
    run_q("      state.vm = vm; return state, %s, \"bad_opcode\", opcode, steps", _r_S_TRAP)
    run_q("    end")
    run_q("    if ost ~= %s then", _r_S_RUN)
    run_q("      state.vm = vm")
    run_q("      if ost == %s then return nil, %s, x1, x2, x3, x4, steps end", _r_S_HALT, _r_S_HALT)
    run_q("      return state, ost, x1, x2, x3, x4, steps")
    run_q("    end")
    run_q("  end")
    run_q("  state.vm = vm")
    run_q("  return state, %s, nil, nil, nil, nil, steps", _r_S_RUN)
    run_q("end")

    local run_fn, run_src = run_q:compile("=(" .. vm_name .. ".run)")

    local fam = uvm.family({
        name = vm_name,
        statuses = opts.statuses or status_set(S.RUN, S.YIELD, S.TRAP, S.HALT),
        codegen = {
            kind = "dispatch_codegen",
            state_kind = "vm_state",
            decode = decode,
            handlers = handlers,
            init_vm = init_vm,
            patch_vm = patch_vm,
            pc0 = opts.pc0 or 1,
            allocate_state = function(plan, alloc)
                return {
                    pc = alloc(plan.id, "pc", plan.name .. ".pc"),
                    vm = alloc(plan.id, "vm", plan.name .. ".vm"),
                }
            end,
        },
        init = function(p, seed) seed = seed or {}
            return { pc = seed.pc or (opts.pc0 or 1), vm = init_vm(p, seed.vm) } end,
        patch = function(op, np, os)
            return { pc = os.pc, vm = patch_vm(op, np, os.vm) } end,
        step = step_fn,
    })

    -- Attach the fused run function
    fam.run_fn = run_fn
    fam.source = step_src
    fam.run_source = run_src

    return fam
end

-- ══════════════════════════════════════════════════════════════
--  DRIVERS
-- ══════════════════════════════════════════════════════════════

uvm.run = {}

function uvm.run.to_halt(machine, max_steps)
    max_steps = max_steps or math.huge; local steps = 0
    while steps < max_steps do
        local st, a, b, c, d = machine:step(); steps = steps + 1
        if st ~= S.RUN then return st, a, b, c, d, steps end
    end
    return S.RUN, nil, nil, nil, nil, steps
end

function uvm.run.collect(machine, max_steps)
    max_steps = max_steps or math.huge; local out, steps = {}, 0
    while steps < max_steps do
        local st, a, b, c, d = machine:step(); steps = steps + 1
        if st == S.YIELD then out[#out+1] = { a, b, c, d }
        elseif st ~= S.RUN then return out, st, a, b, c, d, steps end
    end
    return out, S.RUN, nil, nil, nil, nil, steps
end

function uvm.run.collect_flat(machine, max_steps, out, n)
    max_steps = max_steps or math.huge
    out = out or {}
    n = n or 1
    local steps = 0
    while steps < max_steps do
        local st, a, b, c, d = machine:step(); steps = steps + 1
        if st == S.YIELD then
            out[n], out[n+1], out[n+2], out[n+3] = a, b, c, d
            n = n + 4
        elseif st ~= S.RUN then
            return out, n - 1, st, a, b, c, d, steps
        end
    end
    return out, n - 1, S.RUN, nil, nil, nil, nil, steps
end

function uvm.run.each(machine, max_steps, sink)
    sink = sink or function() end
    max_steps = max_steps or math.huge
    local steps = 0
    while steps < max_steps do
        local st, a, b, c, d = machine:step(); steps = steps + 1
        if st == S.YIELD then
            sink(a, b, c, d)
        elseif st ~= S.RUN then
            return st, a, b, c, d, steps
        end
    end
    return S.RUN, nil, nil, nil, nil, steps
end

function uvm.run.trace(machine, max_steps, sink)
    sink = sink or print; max_steps = max_steps or math.huge; local steps = 0
    while steps < max_steps do
        local st, a, b, c, d = machine:step(); steps = steps + 1
        sink(string.format("[%06d] %s", steps, uvm.status_name_of(st)), a, b, c, d)
        if st ~= S.RUN then return st, a, b, c, d, steps end
    end
    return S.RUN, nil, nil, nil, nil, steps
end

-- ══════════════════════════════════════════════════════════════
--  INSPECTION
-- ══════════════════════════════════════════════════════════════

uvm.inspect = {}
function uvm.inspect.family(f)
    return {
        name = f.name,
        family_kind = f.family_kind,
        has_ir = f.ir ~= nil,
        has_run_fn = f.run_fn ~= nil,
        statuses = status_set_list(f.status_set),
        meta = shallow_copy(f.meta),
    }
end
function uvm.inspect.image(img)
    return { family=img.family.name, shape_key=img.shape_key, payload_key=img.payload_key, parts=img.parts }
end
function uvm.inspect.machine(m)
    return { family=m.family.name, halted=m.halted, last_status=m.last_status, param=m.param, state=m.state }
end
function uvm.inspect.analysis(a)
    return {
        root_tag = a.root and comp_tag_name(a.root) or nil,
        node_count = a.nodes and (function() local n = 0; for _ in pairs(a.nodes) do n = n + 1 end; return n end)() or 0,
        leaf_count = a.leaves and #a.leaves or 0,
        root_statuses = a.root_info and status_set_list(a.root_info.statuses) or {},
    }
end
function uvm.inspect.layout(layout)
    return {
        slot_count = layout.slot_count,
        slots = layout.slots,
    }
end

-- ══════════════════════════════════════════════════════════════
--  CONVENIENCE / SMALL PUBLIC API
-- ══════════════════════════════════════════════════════════════

uvm.stream = uvm.families.stream
uvm.runner = uvm.families.runner
uvm.chain = uvm.op.chain
uvm.guard = uvm.op.guard
uvm.limit = uvm.op.limit
uvm.fuse = uvm.op.fuse
uvm.compile = uvm.comp.compile
uvm.describe = uvm.comp.describe
uvm.analyze = uvm.comp.analyze
uvm.lower = uvm.comp.lower
uvm.plan = uvm.comp.plan
uvm.dispatch = uvm.vm.dispatch_codegen
uvm.json = require("uvm_json")(uvm)

function uvm.image(family, parts) return family:image(parts) end
function uvm.spawn(family, img, seed) return family:spawn(img, seed) end
function uvm.resume(family, img, token) return family:resume(img, token) end

return uvm
