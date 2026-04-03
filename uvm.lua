-- uvm.lua — resumable machine algebra
--
-- Built on pvm (pico VM) which provides:
--   context, with, lower, verb, collect, fold, each, count, report
--
-- uvm adds:
--   status protocol, family, image, machine, composition ops,
--   VM helpers, drivers, inspection

local pvm = require("pvm")
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

uvm.status = { RUN=1, YIELD=2, TRAP=3, PATCHPOINT=4, HALT=5 }
local S = uvm.status

local STATUS_NAME = {
    [1]="RUN", [2]="YIELD", [3]="TRAP", [4]="PATCHPOINT", [5]="HALT",
}
uvm.status_name = STATUS_NAME

function uvm.status_name_of(code)
    return STATUS_NAME[code] or ("UNKNOWN("..tostring(code)..")")
end

-- ══════════════════════════════════════════════════════════════
--  FAMILY / IMAGE / MACHINE
-- ══════════════════════════════════════════════════════════════

local family_mt = {}; family_mt.__index = family_mt
local image_mt = {};  image_mt.__index = image_mt
local machine_mt = {}; machine_mt.__index = machine_mt

function uvm.family(spec)
    check_table(spec, "family spec"); check_fn(spec.step, "family.step")
    return setmetatable({
        name = spec.name or "uvm.family",
        step_fn = spec.step,
        init_fn = spec.init or default_init,
        patch_fn = spec.patch or default_patch,
        patchable_fn = spec.patchable or default_patchable,
        shape_key_fn = spec.shape_key or default_shape_key,
        payload_key_fn = spec.payload_key or default_payload_key,
        disasm_fn = spec.disasm or default_disasm,
        meta = spec.meta or {},
    }, family_mt)
end

function family_mt:__tostring() return "<uvm.family " .. self.name .. ">" end
function family_mt:init(p, seed) return self.init_fn(p, seed) end
function family_mt:patch(op, np, os) return self.patch_fn(op, np, os) end
function family_mt:patchable(p, s) return self.patchable_fn(p, s) end
function family_mt:shape_key(parts) return self.shape_key_fn(parts) end
function family_mt:payload_key(parts) return self.payload_key_fn(parts) end
function family_mt:disasm(p) return self.disasm_fn(p) end

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
        step=step_runner,
    })
end

-- ══════════════════════════════════════════════════════════════
--  COMPOSITION ALGEBRA
-- ══════════════════════════════════════════════════════════════

uvm.op = {}

function uvm.op.chain(fa, fb, opts)
    opts = opts or {}
    return uvm.family({
        name = opts.name or (fa.name .. ".then." .. fb.name),
        init = function(p, seed) seed=seed or {}
            return { phase=1, a=fa:init(p.a,seed.a), b=fb:init(p.b,seed.b) } end,
        patch = function(op, np, os)
            return { phase=os.phase, a=fa:patch(op.a,np.a,os.a), b=fb:patch(op.b,np.b,os.b) } end,
        step = function(param, state)
            if state.phase == 1 then
                local ns, st, a, b, c, d = fa.step_fn(param.a, state.a)
                if st==S.HALT or ns==nil then state.a=ns; state.phase=2; return state, S.PATCHPOINT, "chain.phase", 2 end
                state.a=ns; return state, st, a, b, c, d
            else
                local ns, st, a, b, c, d = fb.step_fn(param.b, state.b)
                if st==S.HALT or ns==nil then return nil, S.HALT, a, b, c, d end
                state.b=ns; return state, st, a, b, c, d
            end
        end,
    })
end

function uvm.op.guard(fam, guard_fn, opts)
    opts = opts or {}; check_fn(guard_fn, "guard_fn")
    return uvm.family({
        name = opts.name or (fam.name .. ".guard"),
        init = function(p, seed) return fam:init(p.inner, seed) end,
        patch = function(op, np, os) return fam:patch(op.inner, np.inner, os) end,
        step = function(param, state)
            local ns, st, a, b, c, d = fam.step_fn(param.inner, state)
            return guard_fn(param, state, ns, st, a, b, c, d)
        end,
    })
end

function uvm.op.limit(fam, every, opts)
    opts = opts or {}; assert(type(every)=="number" and every>0)
    return uvm.family({
        name = opts.name or (fam.name .. ".limit(" .. every .. ")"),
        init = function(p, seed) return { inner=fam:init(p.inner, seed), seen=0 } end,
        patch = function(op, np, os) return { inner=fam:patch(op.inner,np.inner,os.inner), seen=os.seen } end,
        step = function(param, state)
            local ns, st, a, b, c, d = fam.step_fn(param.inner, state.inner)
            if st==S.HALT or ns==nil then return nil, S.HALT, a, b, c, d end
            state.inner=ns
            if st ~= S.RUN then state.seen=state.seen+1
                if state.seen % every == 0 then return state, S.PATCHPOINT, "limit", state.seen end end
            return state, st, a, b, c, d
        end,
    })
end

function uvm.op.fuse(decoder_family, exec_step, opts)
    opts = opts or {}; check_fn(exec_step, "exec_step")
    return uvm.family({
        name = opts.name or (decoder_family.name .. ".fused"),
        init = function(p, seed) seed=seed or {}
            return { inner=decoder_family:init(p.inner,seed.inner), acc=seed.acc } end,
        patch = function(op, np, os)
            return { inner=decoder_family:patch(op.inner,np.inner,os.inner), acc=os.acc } end,
        step = function(param, state)
            while true do
                local ns, st, a, b, c, d = decoder_family.step_fn(param.inner, state.inner)
                if st==S.HALT or ns==nil then return nil, S.HALT, state.acc end
                state.inner = ns
                if st==S.RUN then return state, S.RUN
                elseif st==S.PATCHPOINT then return state, S.PATCHPOINT, a, b, c, d
                elseif st==S.TRAP then return state, S.TRAP, a, b, c, d
                elseif st==S.YIELD then
                    local nacc, ost, x1,x2,x3,x4 = exec_step(param.exec, state.acc, a, b, c, d)
                    state.acc = nacc
                    if ost ~= S.RUN then return state, ost, x1,x2,x3,x4 end
                else return state, S.TRAP, "bad_status", st end
            end
        end,
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
--  CODEGEN: generate specialized step function
--
--  Replaces table dispatch with inline if/elseif.
--  One function, no indirect calls, LuaJIT traces it as one path.
-- ══════════════════════════════════════════════════════════════

local function compile_chunk(src, env, name)
    local fn, err
    if loadstring then
        fn, err = loadstring(src, name)
        if not fn then error(err, 2) end
        if setfenv then setfenv(fn, env) end
    else
        fn, err = load(src, name, "t", env)
        if not fn then error(err, 2) end
    end
    return fn()
end

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

    -- Generate the step function source
    local src = {}
    src[#src+1] = "return function(param, state)"
    src[#src+1] = "  local pc = state.pc"
    src[#src+1] = "  local word = param.code[pc]"
    src[#src+1] = "  if word == nil then return nil, S_HALT, state.vm end"
    src[#src+1] = "  local opcode, a, b, c, d = decode(param, word, pc)"
    src[#src+1] = "  state.pc = pc + 1"
    src[#src+1] = "  local nvm, ost, x1, x2, x3, x4"

    for i = 1, #opcodes do
        local kw = (i == 1) and "if" or "elseif"
        src[#src+1] = string.format("  %s opcode == OP_%d then", kw, i)
        src[#src+1] = string.format("    nvm, ost, x1, x2, x3, x4 = H_%d(param, state.vm, pc, a, b, c, d)", i)
    end
    src[#src+1] = "  else"
    src[#src+1] = '    return state, S_TRAP, "bad_opcode", opcode, pc'
    src[#src+1] = "  end"
    src[#src+1] = "  state.vm = nvm"
    src[#src+1] = "  if ost == S_HALT then return nil, S_HALT, x1, x2, x3, x4 end"
    src[#src+1] = "  return state, ost, x1, x2, x3, x4"
    src[#src+1] = "end"

    -- Build environment with handler upvalues
    local env = { decode = decode, S_HALT = S.HALT, S_TRAP = S.TRAP }
    for i = 1, #opcodes do
        env["OP_" .. i] = opcodes[i]
        env["H_" .. i] = handlers[opcodes[i]]
    end

    local step_fn = compile_chunk(table.concat(src, "\n"),
        env, "=(" .. vm_name .. ".step)")

    -- Also generate a fused run-to-completion function
    -- This is the GOLDEN loop: while true do <inline step> end
    local run_src = {}
    run_src[#run_src+1] = "return function(param, state, budget)"
    run_src[#run_src+1] = "  budget = budget or 1e18"
    run_src[#run_src+1] = "  local vm = state.vm"
    run_src[#run_src+1] = "  local code = param.code"
    run_src[#run_src+1] = "  local steps = 0"
    run_src[#run_src+1] = "  while steps < budget do"
    run_src[#run_src+1] = "    local pc = state.pc"
    run_src[#run_src+1] = "    local word = code[pc]"
    run_src[#run_src+1] = "    if word == nil then return nil, S_HALT, vm, steps end"
    run_src[#run_src+1] = "    local opcode, a, b, c, d = decode(param, word, pc)"
    run_src[#run_src+1] = "    state.pc = pc + 1"
    run_src[#run_src+1] = "    steps = steps + 1"
    run_src[#run_src+1] = "    local ost, x1, x2, x3, x4"

    for i = 1, #opcodes do
        local kw = (i == 1) and "if" or "elseif"
        run_src[#run_src+1] = string.format("    %s opcode == OP_%d then", kw, i)
        run_src[#run_src+1] = string.format("      vm, ost, x1, x2, x3, x4 = H_%d(param, vm, pc, a, b, c, d)", i)
    end
    run_src[#run_src+1] = "    else"
    run_src[#run_src+1] = '      state.vm = vm; return state, S_TRAP, "bad_opcode", opcode, steps'
    run_src[#run_src+1] = "    end"
    run_src[#run_src+1] = "    if ost ~= S_RUN then"
    run_src[#run_src+1] = "      state.vm = vm"
    run_src[#run_src+1] = "      if ost == S_HALT then return nil, S_HALT, x1, x2, x3, x4, steps end"
    run_src[#run_src+1] = "      return state, ost, x1, x2, x3, x4, steps"
    run_src[#run_src+1] = "    end"
    run_src[#run_src+1] = "  end"
    run_src[#run_src+1] = "  state.vm = vm"
    run_src[#run_src+1] = "  return state, S_RUN, nil, nil, nil, nil, steps"
    run_src[#run_src+1] = "end"

    local run_env = { decode = decode, S_HALT = S.HALT, S_TRAP = S.TRAP, S_RUN = S.RUN }
    for i = 1, #opcodes do
        run_env["OP_" .. i] = opcodes[i]
        run_env["H_" .. i] = handlers[opcodes[i]]
    end

    local run_fn = compile_chunk(table.concat(run_src, "\n"),
        run_env, "=(" .. vm_name .. ".run)")

    local fam = uvm.family({
        name = vm_name,
        init = function(p, seed) seed = seed or {}
            return { pc = seed.pc or (opts.pc0 or 1), vm = init_vm(p, seed.vm) } end,
        patch = function(op, np, os)
            return { pc = os.pc, vm = patch_vm(op, np, os.vm) } end,
        step = step_fn,
    })

    -- Attach the fused run function
    fam.run_fn = run_fn
    fam.source = table.concat(src, "\n")
    fam.run_source = table.concat(run_src, "\n")

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
function uvm.inspect.family(f) return { name=f.name, meta=shallow_copy(f.meta) } end
function uvm.inspect.image(img)
    return { family=img.family.name, shape_key=img.shape_key, payload_key=img.payload_key, parts=img.parts }
end
function uvm.inspect.machine(m)
    return { family=m.family.name, halted=m.halted, last_status=m.last_status, param=m.param, state=m.state }
end

-- ══════════════════════════════════════════════════════════════
--  CONVENIENCE
-- ══════════════════════════════════════════════════════════════

function uvm.image(family, parts) return family:image(parts) end
function uvm.spawn(family, img, seed) return family:spawn(img, seed) end
function uvm.resume(family, img, token) return family:resume(img, token) end

return uvm
