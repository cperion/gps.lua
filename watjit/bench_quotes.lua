package.path = "./?.lua;./?/init.lua;" .. package.path

local wj = require("watjit")
local wm = require("watjit.wasmtime")

local u32 = wj.u32

local function now_ms()
    return os.clock() * 1000.0
end

local function bench_ms(iters, fn)
    local t0 = now_ms()
    local out = nil
    for _ = 1, iters do
        out = fn()
    end
    return now_ms() - t0, out
end

local function warm(fn, n)
    n = n or 10
    for _ = 1, n do
        fn()
    end
end

local function make_mix_fn(name)
    return wj.fn {
        name = name,
        params = { u32 "x" },
        ret = u32,
        body = function(x)
            local t = u32("t", x:bxor(x:shr_u(16)))
            t(t * u32(0x7feb352d))
            t(t:bxor(t:shr_u(15)))
            t(t * u32(0x846ca68b))
            t(t:bxor(t:shr_u(16)))
            return t
        end,
    }
end

local mix_quote = wj.quote_expr {
    params = { u32 "x" },
    ret = u32,
    body = function(x)
        local t = u32("t", x:bxor(x:shr_u(16)))
        t(t * u32(0x7feb352d))
        t(t:bxor(t:shr_u(15)))
        t(t * u32(0x846ca68b))
        t(t:bxor(t:shr_u(16)))
        return t
    end,
}

local mix_call = make_mix_fn("mix_call")

local sum_via_call = wj.fn {
    name = "sum_via_call",
    params = { wj.i32 "n" },
    ret = u32,
    body = function(n)
        local i = wj.i32("i")
        local acc = u32("acc", 0)
        wj.for_(i, n, function()
            acc(acc + mix_call(wj.cast(u32, i)))
        end)
        return acc
    end,
}

local sum_via_quote = wj.fn {
    name = "sum_via_quote",
    params = { wj.i32 "n" },
    ret = u32,
    body = function(n)
        local i = wj.i32("i")
        local acc = u32("acc", 0)
        wj.for_(i, n, function()
            acc(acc + mix_quote(wj.cast(u32, i)))
        end)
        return acc
    end,
}

local function compile_case(engine, funcs)
    local mod = wj.module(funcs)
    local t0 = now_ms()
    local inst = mod:compile(engine)
    local compile_ms = now_ms() - t0
    return mod, inst, compile_ms
end

local engine = wm.engine()
local n = tonumber(os.getenv("N") or "1000000")
local iters = tonumber(os.getenv("ITERS") or "50")

local mod_call, inst_call, compile_call_ms = compile_case(engine, { mix_call, sum_via_call })
local mod_quote, inst_quote, compile_quote_ms = compile_case(engine, { sum_via_quote })

local wat_call = mod_call:wat()
local wat_quote = mod_quote:wat()
assert(wat_call:find("(call $mix_call", 1, true), wat_call)
assert(not wat_quote:find("(call $", 1, true), wat_quote)

local run_call = inst_call:fn("sum_via_call")
local run_quote = inst_quote:fn("sum_via_quote")

local expect_call = run_call(n)
local expect_quote = run_quote(n)
assert(expect_call == expect_quote, string.format("result mismatch: call=%u quote=%u", expect_call, expect_quote))

warm(function() return run_call(n) end, 5)
warm(function() return run_quote(n) end, 5)

local call_ms, out_call = bench_ms(iters, function() return run_call(n) end)
local quote_ms, out_quote = bench_ms(iters, function() return run_quote(n) end)
assert(out_call == out_quote)

print(string.format("watjit quote inline bench (n=%d, iters=%d)", n, iters))
print(string.format("compile  call=%8.3f ms  quote=%8.3f ms", compile_call_ms, compile_quote_ms))
print(string.format("wat size call=%d bytes  quote=%d bytes", #wat_call, #wat_quote))
print(string.format("run      call=%8.3f ms  quote=%8.3f ms  speedup=%6.2fx", call_ms, quote_ms, call_ms / quote_ms))
print(string.format("result   %u", out_call))
