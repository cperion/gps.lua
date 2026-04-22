-- Run from gps.lua/ root: luajit moonlift/bench_compile_time.lua
package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path
if not package.preload["gps.asdl_lexer"] then
    package.preload["gps.asdl_lexer"]   = function() return require("asdl_lexer") end
    package.preload["gps.asdl_parser"]  = function() return require("asdl_parser") end
    package.preload["gps.asdl_context"] = function() return require("asdl_context") end
end

local ffi = require("ffi")
local pvm = require("pvm")
local A = require("moonlift.asdl")
local Source = require("moonlift.source")

local TESTS = {
    {
        name = "sum3 (simple func)",
        src = [[
func sum3(a: i32, b: i32, c: i32) -> i32
    let s1: i32 = a + b
    let s2: i32 = s1 + c
    return s2
end
]],
        func_name = "sum3",
        sig = "int32_t (*)(int32_t, int32_t, int32_t)",
        args = {1, 2, 3},
        expect = 6,
    },
    {
        name = "arith (more ops)",
        src = [[
func arith(x: i32, y: i32) -> i32
    let a: i32 = x + y
    let b: i32 = x - y
    let c: i32 = a * b
    let d: i32 = c / 2
    return d
end
]],
        func_name = "arith",
        sig = "int32_t (*)(int32_t, int32_t)",
        args = {5, 3},
        expect = 8,  -- (5+3)*(5-3)/2 = 8*2/2 = 8
    },
}

local function bench_one(test)
    local T = pvm.context()
    A.Define(T)
    local S = Source.Define(T)
    local jit = require("moonlift.jit").Define(T).jit()

    -- Warm up (fills pvm caches)
    for _ = 1, 5 do
        local ok, art = pcall(S.compile_module, test.src, nil, nil, nil, jit)
        if ok and art then art:free() end
    end

    collectgarbage("stop")

    local function now() return os.clock() end

    local t0 = now()
    local surface = S.parse_module(test.src)
    local t1 = now()

    local elab = S.lower_module(test.src, nil)
    local t2 = now()

    local sem = S.sem_module(test.src, nil)
    local t3 = now()

    local resolved = S.resolve_module(test.src, nil, nil)
    local t4 = now()

    local back = S.back_module(test.src, nil, nil, nil)
    local t5 = now()

    local artifact = jit:compile(back)
    local t6 = now()

    local ptr = artifact:getpointer(T.MoonliftBack.BackFuncId(test.func_name))
    local f = ffi.cast(test.sig, ptr)
    local result = f(unpack(test.args))
    assert(result == test.expect,
        test.name .. ": expected " .. test.expect .. " got " .. tostring(result))

    artifact:free()
    collectgarbage("restart")

    return {
        total     = (t6 - t0) * 1000,
        parse     = (t1 - t0) * 1000,
        elab      = (t2 - t1) * 1000,
        sem       = (t3 - t2) * 1000,
        resolve   = (t4 - t3) * 1000,
        back      = (t5 - t4) * 1000,
        cranelift = (t6 - t5) * 1000,
    }
end

print()
print("=== Moonlift end-to-end compile time ===")
print()
for _, test in ipairs(TESTS) do
    local ok, r = pcall(bench_one, test)
    if not ok then
        print(string.format("%s: FAILED (%s)", test.name, tostring(r)))
    else
        print(string.format("%s:", test.name))
        print(string.format("  Parse          : %8.3f ms  (%5.1f%%)", r.parse,     r.parse     / r.total * 100))
        print(string.format("  Surface -> Elab: %8.3f ms  (%5.1f%%)", r.elab,      r.elab      / r.total * 100))
        print(string.format("  Elab -> Sem    : %8.3f ms  (%5.1f%%)", r.sem,       r.sem       / r.total * 100))
        print(string.format("  Resolve layout : %8.3f ms  (%5.1f%%)", r.resolve,   r.resolve   / r.total * 100))
        print(string.format("  Sem -> Back    : %8.3f ms  (%5.1f%%)", r.back,      r.back      / r.total * 100))
        print(string.format("  Cranelift JIT  : %8.3f ms  (%5.1f%%)", r.cranelift, r.cranelift / r.total * 100))
        print(string.format("  ─────────────────────────────────"))
        print(string.format("  Total          : %8.3f ms", r.total))
        print()
    end
end
