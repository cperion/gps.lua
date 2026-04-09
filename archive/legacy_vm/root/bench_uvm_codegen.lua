-- bench_uvm_codegen.lua — table dispatch vs codegen dispatch

package.path = "./?.lua;./?/init.lua;" .. package.path

if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local uvm = require("uvm")
local S = uvm.status

-- ══════════════════════════════════════════════════════════════
--  Shared: opcode set + handlers + test program
-- ══════════════════════════════════════════════════════════════

local function decode(param, word, pc)
    return word.op, word.a, word.b, word.c
end

local handlers = {}

handlers.CONST = function(param, vm, pc, dst, kidx)
    vm.regs[dst] = param.k[kidx]; return vm, S.RUN
end
handlers.ADD = function(param, vm, pc, dst, ra, rb)
    vm.regs[dst] = vm.regs[ra] + vm.regs[rb]; return vm, S.RUN
end
handlers.MUL = function(param, vm, pc, dst, ra, rb)
    vm.regs[dst] = vm.regs[ra] * vm.regs[rb]; return vm, S.RUN
end
handlers.SUB = function(param, vm, pc, dst, ra, rb)
    vm.regs[dst] = vm.regs[ra] - vm.regs[rb]; return vm, S.RUN
end
handlers.YIELD = function(param, vm, pc, reg)
    return vm, S.YIELD, vm.regs[reg]
end
handlers.HALT = function(param, vm, pc, reg)
    return vm, S.HALT, vm.regs[reg or 1]
end
handlers.JMP = function(param, vm, pc, target)
    -- note: dispatch increments pc, so we adjust
    return vm, S.RUN
end

local function init_vm(param, seed)
    if seed and seed.regs then return seed end
    local regs = {}; for i = 1, 16 do regs[i] = 0 end
    return { regs = regs }
end

-- Build the two families
local table_family = uvm.vm.dispatch({
    name = "vm.table",
    handlers = handlers,
    decode = decode,
    init_vm = init_vm,
})

local codegen_family = uvm.vm.dispatch_codegen({
    name = "vm.codegen",
    handlers = handlers,
    decode = decode,
    init_vm = init_vm,
})

-- Print the generated source
print("=== Generated step function ===")
print(codegen_family.source)
print("\n=== Generated run function ===")
print(codegen_family.run_source)

-- ══════════════════════════════════════════════════════════════
--  Test program: compute fibonacci iteratively
-- ══════════════════════════════════════════════════════════════

local I = function(op, a, b, c) return { op=op, a=a, b=b, c=c } end

-- fib(N): r1=0, r2=1, loop N times: r3=r1+r2, r1=r2, r2=r3
local function make_fib_program(n)
    return {
        k = { 0, 1, n },
        code = {
            I("CONST", 1, 1),   -- r1 = 0
            I("CONST", 2, 2),   -- r2 = 1
            I("CONST", 3, 3),   -- r3 = n (counter)
            I("CONST", 4, 1),   -- r4 = 0 (zero)
            I("CONST", 5, 2),   -- r5 = 1
            -- loop:
            I("ADD", 6, 1, 2),  -- r6 = r1 + r2
            I("ADD", 1, 2, 4),  -- r1 = r2 (copy via add 0)
            I("ADD", 2, 6, 4),  -- r2 = r6 (copy via add 0)
            I("SUB", 3, 3, 5),  -- r3 = r3 - 1
            I("YIELD", 2),      -- yield current fib
            -- jump back: we can't really jump with this dispatch,
            -- so unroll by repeating the loop body
        },
    }
end

-- For a proper loop, let's make a long straight-line program
local function make_arith_program(n_ops)
    local code = {}
    code[#code+1] = I("CONST", 1, 1)  -- r1 = 0
    code[#code+1] = I("CONST", 2, 2)  -- r2 = 1
    for i = 1, n_ops do
        if i % 3 == 0 then
            code[#code+1] = I("ADD", 1, 1, 2)
        elseif i % 3 == 1 then
            code[#code+1] = I("MUL", 2, 1, 2)
        else
            code[#code+1] = I("SUB", 1, 1, 2)
        end
    end
    code[#code+1] = I("YIELD", 1)
    code[#code+1] = I("HALT", 1)
    return { k = { 0, 1 }, code = code }
end

-- ══════════════════════════════════════════════════════════════
--  Verify
-- ══════════════════════════════════════════════════════════════

local prog = make_arith_program(100)

local m1 = table_family:spawn(prog)
local r1, s1 = uvm.run.collect(m1, 10000)

local m2 = codegen_family:spawn(prog)
local r2, s2 = uvm.run.collect(m2, 10000)

assert(s1 == s2, "status mismatch")
assert(#r1 == #r2, "result count mismatch")
assert(r1[1][1] == r2[1][1], "result value mismatch: " .. tostring(r1[1][1]) .. " vs " .. tostring(r2[1][1]))
print("\nCorrectness: OK\n")

-- ══════════════════════════════════════════════════════════════
--  Bench
-- ══════════════════════════════════════════════════════════════

local function bench_machine(family, prog, N)
    for i = 1, 200 do
        local m = family:spawn(prog)
        uvm.run.to_halt(m, 100000)
    end
    collectgarbage("collect"); collectgarbage("collect")
    local t0 = os.clock()
    for i = 1, N do
        local m = family:spawn(prog)
        uvm.run.to_halt(m, 100000)
    end
    return (os.clock() - t0) / N
end

-- Also bench the fused run_fn directly (bypasses machine:step overhead)
local function bench_run_fn(family, prog, N)
    for i = 1, 200 do
        local state = { pc = 1, vm = init_vm(prog) }
        family.run_fn(prog, state, 100000)
    end
    collectgarbage("collect"); collectgarbage("collect")
    local t0 = os.clock()
    for i = 1, N do
        local state = { pc = 1, vm = init_vm(prog) }
        family.run_fn(prog, state, 100000)
    end
    return (os.clock() - t0) / N
end

for _, size in ipairs({ 100, 1000, 10000 }) do
    local prog = make_arith_program(size)
    local n_ops = size + 4  -- +2 CONST +1 YIELD +1 HALT
    local N = size <= 100 and 50000 or (size <= 1000 and 5000 or 500)

    local t_table   = bench_machine(table_family, prog, N)
    local t_codegen = bench_machine(codegen_family, prog, N)
    local t_run_fn  = bench_run_fn(codegen_family, prog, N)

    print(string.format("  %5d ops:  table: %7.1fus (%4.0fns/op)  codegen: %7.1fus (%4.0fns/op)  run_fn: %7.1fus (%4.0fns/op)  speedup: %.1fx / %.1fx",
        n_ops,
        t_table * 1e6, t_table / n_ops * 1e9,
        t_codegen * 1e6, t_codegen / n_ops * 1e9,
        t_run_fn * 1e6, t_run_fn / n_ops * 1e9,
        t_table / t_codegen, t_table / t_run_fn))
end
